// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class MouseMoveModifierTests: XCTestCase {
    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let token: WindowToken
        let windowFrame: CGRect

        @MainActor var handler: MouseEventHandler {
            controller.mouseEventHandler
        }
    }

    func testMouseMoveModifierMappingsResolveExactly() throws {
        XCTAssertNil(MouseMoveModifierKey.off.cgEventFlags)
        XCTAssertNil(MouseEventHandler.mouseMoveMode(modifiers: [], required: nil))
        XCTAssertNil(MouseEventHandler.mouseMoveMode(modifiers: .maskAlternate, required: nil))
        XCTAssertNil(MouseEventHandler.mouseMoveMode(modifiers: [], required: []))
        XCTAssertNil(MouseEventHandler.mouseMoveMode(modifiers: .maskShift, required: []))
        XCTAssertNil(MouseEventHandler.mouseMoveMode(modifiers: [], required: .maskAlternate))
        XCTAssertNil(MouseEventHandler.mouseMoveMode(modifiers: .maskShift, required: .maskAlternate))

        let baseModifierFlags: [CGEventFlags] = [.maskAlternate, .maskControl, .maskCommand]
        for modifier in MouseMoveModifierKey.allCases where modifier != .off {
            let required = try XCTUnwrap(modifier.cgEventFlags)

            XCTAssertEqual(
                MouseEventHandler.mouseMoveMode(modifiers: required, required: required),
                .swap
            )
            XCTAssertNil(
                MouseEventHandler.mouseMoveMode(
                    modifiers: required.union(.maskShift),
                    required: required
                )
            )
            XCTAssertEqual(
                MouseEventHandler.mouseMoveMode(
                    modifiers: required.union(.maskAlphaShift),
                    required: required
                ),
                .swap
            )

            for extra in baseModifierFlags where !required.contains(extra) {
                XCTAssertNil(
                    MouseEventHandler.mouseMoveMode(
                        modifiers: required.union(extra),
                        required: required
                    )
                )
            }
        }

        XCTAssertNil(
            MouseEventHandler.mouseMoveMode(
                modifiers: [.maskAlternate, .maskCommand],
                required: .maskAlternate
            )
        )
    }

    @MainActor
    func testDwindleLeftDragWithMoveModifierSwapsTilesOnRelease() throws {
        let fixture = try makeDwindleFixture(pid: 1_201)
        let manager = fixture.controller.workspaceManager
        let worldSeq = manager.worldSeq

        XCTAssertFalse(fixture.handler.dispatchMouseDown(at: fixture.firstFrame.center, modifiers: .maskControl))
        XCTAssertTrue(fixture.handler.state.isMoving)
        XCTAssertEqual(fixture.handler.state.moveLayout, .dwindle)
        XCTAssertEqual(fixture.handler.state.capturedInteractionButton, .left)
        XCTAssertEqual(fixture.engine.interactiveMove?.token, fixture.first)

        fixture.handler.dispatchMouseDragged(at: fixture.secondFrame.center)
        XCTAssertEqual(fixture.engine.interactiveMove?.targetToken, fixture.second)
        XCTAssertEqual(manager.worldSeq, worldSeq)

        fixture.handler.dispatchMouseUp(at: fixture.secondFrame.center)
        XCTAssertFalse(fixture.handler.state.isMoving)
        XCTAssertNil(fixture.handler.state.moveLayout)
        XCTAssertNil(fixture.handler.state.activeInteractionButton)
        XCTAssertNil(fixture.engine.interactiveMove)
        XCTAssertGreaterThan(manager.worldSeq, worldSeq)
        fixture.relayout()
        XCTAssertEqual(fixture.presentedFrame(fixture.first), fixture.secondFrame)
        XCTAssertEqual(fixture.presentedFrame(fixture.second), fixture.firstFrame)
    }

    @MainActor
    func testDwindleShiftInsertModeAndUnmodifiedClickDoNotStartDrag() throws {
        let fixture = try makeDwindleFixture(pid: 1_202)
        let worldSeq = fixture.controller.workspaceManager.worldSeq

        for modifiers in [CGEventFlags.maskShift.union(.maskControl), CGEventFlags(), .maskAlternate] {
            XCTAssertFalse(fixture.handler.dispatchMouseDown(at: fixture.firstFrame.center, modifiers: modifiers))
            XCTAssertFalse(fixture.handler.state.isMoving)
            XCTAssertNil(fixture.handler.state.activeInteractionButton)
            XCTAssertNil(fixture.engine.interactiveMove)
        }
        XCTAssertNil(fixture.engine.interactiveResize)
        XCTAssertEqual(fixture.controller.workspaceManager.worldSeq, worldSeq)
    }

    @MainActor
    func testDwindleReleaseOverSourceLeavesWorldUnchanged() throws {
        let fixture = try makeDwindleFixture(pid: 1_203)
        let worldSeq = fixture.controller.workspaceManager.worldSeq

        XCTAssertFalse(fixture.handler.dispatchMouseDown(at: fixture.firstFrame.center, modifiers: .maskControl))
        fixture.handler.dispatchMouseDragged(at: fixture.secondFrame.center)
        fixture.handler.dispatchMouseDragged(at: fixture.firstFrame.center)
        XCTAssertNil(fixture.engine.interactiveMove?.targetToken)
        fixture.handler.dispatchMouseUp(at: fixture.firstFrame.center)

        XCTAssertFalse(fixture.handler.state.isMoving)
        XCTAssertNil(fixture.engine.interactiveMove)
        XCTAssertEqual(fixture.controller.workspaceManager.worldSeq, worldSeq)
        fixture.relayout()
        XCTAssertEqual(fixture.presentedFrame(fixture.first), fixture.firstFrame)
        XCTAssertEqual(fixture.presentedFrame(fixture.second), fixture.secondFrame)
    }

    @MainActor
    func testCleanupReconcilesDwindleMoveEngineAndLocalState() throws {
        let fixture = try makeDwindleFixture(pid: 1_204)
        XCTAssertFalse(fixture.handler.dispatchMouseDown(at: fixture.firstFrame.center, modifiers: .maskControl))
        XCTAssertNotNil(fixture.engine.interactiveMove)

        fixture.handler.cleanup()

        XCTAssertNil(fixture.engine.interactiveMove)
        XCTAssertFalse(fixture.handler.state.isMoving)
        XCTAssertNil(fixture.handler.state.moveLayout)
        XCTAssertNil(fixture.handler.state.activeInteractionButton)
        XCTAssertFalse(fixture.handler.isInteractiveGestureActive)
    }

    private struct DwindleFixture {
        let controller: WMController
        let engine: DwindleLayoutEngine
        let workspaceId: WorkspaceDescriptor.ID
        let screen: CGRect
        let first: WindowToken
        let second: WindowToken
        let firstFrame: CGRect
        let secondFrame: CGRect

        @MainActor var handler: MouseEventHandler {
            controller.mouseEventHandler
        }

        func presentedFrame(_ token: WindowToken) -> CGRect? {
            engine.presentedFrame(for: token, in: workspaceId, at: 0)
        }

        func relayout() {
            _ = engine.calculateLayout(for: workspaceId, screen: screen)
            engine.cancelAnimations(in: workspaceId)
        }
    }

    @MainActor
    private func makeDwindleFixture(pid: pid_t) throws -> DwindleFixture {
        let controller = makeController()
        controller.settings.gestures.mouseMoveModifierKey = .control
        let monitor = makeMonitor()
        controller.settings.workspaces.configurations = [
            WorkspaceConfiguration(
                name: "1",
                monitorAssignment: .specificDisplay(OutputId(from: monitor)),
                layoutType: .dwindle
            )
        ]
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        controller.workspaceManager.applySettings()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(named: "1"))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.enableDwindleLayout()
        let engine = try XCTUnwrap(controller.dwindleEngine)
        var tokens: [WindowToken] = []
        for windowId in 1 ... 2 {
            let token = controller.workspaceManager.addWindow(
                WindowAdmissionTestSupport.axRef(for: WindowToken(pid: pid, windowId: windowId)),
                pid: pid,
                windowId: windowId,
                to: workspaceId
            )
            controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
                _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
            }
            tokens.append(token)
        }
        let screen = controller.insetWorkingFrame(for: monitor)
        _ = engine.calculateLayout(for: workspaceId, screen: screen)
        engine.cancelAnimations(in: workspaceId)
        controller.mouseEventHandler.pressedMouseButtonsProvider = { 1 }
        let firstFrame = try XCTUnwrap(engine.presentedFrame(for: tokens[0], in: workspaceId, at: 0))
        let secondFrame = try XCTUnwrap(engine.presentedFrame(for: tokens[1], in: workspaceId, at: 0))
        XCTAssertNotEqual(firstFrame, secondFrame)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.settings.workspaces.layoutType(for: "1"), .dwindle)
        XCTAssertEqual(
            MouseEventHandler.mouseMoveMode(
                modifiers: .maskControl,
                required: controller.settings.gestures.mouseMoveModifierKey.cgEventFlags
            ),
            .swap
        )
        XCTAssertEqual(
            engine.hitTestFocusableWindow(
                point: firstFrame.center,
                in: workspaceId,
                at: controller.animationClock.now()
            ),
            tokens[0]
        )

        return DwindleFixture(
            controller: controller,
            engine: engine,
            workspaceId: workspaceId,
            screen: screen,
            first: tokens[0],
            second: tokens[1],
            firstFrame: firstFrame,
            secondFrame: secondFrame
        )
    }

    private func borderConfig(enabled: Bool = true, width: CGFloat) -> BorderConfig {
        BorderConfig(
            enabled: enabled,
            width: width,
            color: SettingsColor(red: 1, green: 0, blue: 0, alpha: 1)
        )
    }

    @MainActor
    private func makeController() -> WMController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseMoveModifierTests-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        return WMController(settings: settings)
    }

    private func makeMonitor() -> Monitor {
        let workingFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        return Monitor(
            id: .init(displayId: 51_001),
            displayId: 51_001,
            frame: workingFrame,
            visibleFrame: workingFrame,
            hasNotch: false,
            name: "Mouse Move Modifier"
        )
    }
}
