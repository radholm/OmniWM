// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class EdgeDragResizeTests: XCTestCase {
    func testEdgeBandsCoverInsideAndGapOnly() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        func edges(_ x: CGFloat, _ y: CGFloat) -> ResizeEdge {
            MouseEventHandler.edgeDragResizeEdges(point: CGPoint(x: x, y: y), frame: frame, inside: 4, outside: 6)
        }
        XCTAssertEqual(edges(300, 250), [])
        XCTAssertEqual(edges(503, 250), .right)
        XCTAssertEqual(edges(497, 250), .right)
        XCTAssertEqual(edges(507, 250), [])
        XCTAssertEqual(edges(95, 250), .left)
        XCTAssertEqual(edges(300, 402), .top)
        XCTAssertEqual(edges(300, 98), .bottom)
        XCTAssertEqual(edges(502, 402), [.right, .top])
        XCTAssertEqual(MouseEventHandler.edgeDragOutsideBand(innerGap: 16), 9)
        XCTAssertEqual(MouseEventHandler.edgeDragOutsideBand(innerGap: 0), 3)
    }

    func testCandidatesPreferNearestEdge() {
        let left = WindowToken(pid: 1, windowId: 1)
        let right = WindowToken(pid: 1, windowId: 2)
        let frames = [
            left: CGRect(x: 0, y: 0, width: 100, height: 100),
            right: CGRect(x: 110, y: 0, width: 100, height: 100)
        ]
        let candidates = MouseEventHandler.edgeDragResizeCandidates(
            point: CGPoint(x: 104, y: 50), frames: frames, inside: 4, outside: 6
        )
        XCTAssertEqual(candidates.map(\.token), [left, right])
        XCTAssertEqual(candidates.map(\.edges), [.right, .left])
    }

    func testNativeDragKeptSize() {
        let applied = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertTrue(MouseEventHandler.nativeDragKeptSize(
            observedFrame: applied.offsetBy(dx: 200, dy: 30), lastAppliedFrame: applied
        ))
        XCTAssertFalse(MouseEventHandler.nativeDragKeptSize(
            observedFrame: CGRect(x: 0, y: 0, width: 460, height: 300), lastAppliedFrame: applied
        ))
        XCTAssertFalse(MouseEventHandler.nativeDragKeptSize(observedFrame: nil, lastAppliedFrame: applied))
    }

    @MainActor
    func testUnmodifiedDragOnDwindleGapResizesSplit() throws {
        let fixture = try makeDwindleFixture(pid: 1_301)
        let handler = fixture.handler
        let gapPoint = fixture.gapPoint

        XCTAssertTrue(handler.dispatchMouseDown(at: gapPoint, modifiers: []))
        XCTAssertTrue(handler.state.isResizing)
        XCTAssertEqual(handler.state.resizeLayout, .dwindle)
        XCTAssertEqual(handler.state.capturedInteractionButton, .left)
        XCTAssertNotNil(fixture.engine.interactiveResize)

        let target = fixture.isSideBySide
            ? CGPoint(x: gapPoint.x + 120, y: gapPoint.y)
            : CGPoint(x: gapPoint.x, y: gapPoint.y - 120)
        handler.dispatchMouseDragged(at: target)
        handler.dispatchMouseUp(at: target)

        XCTAssertFalse(handler.state.isResizing)
        XCTAssertNil(fixture.engine.interactiveResize)
        fixture.relayout()
        let first = try XCTUnwrap(fixture.presentedFrame(fixture.first))
        if fixture.isSideBySide {
            XCTAssertGreaterThan(first.width, fixture.firstFrame.width + 60)
        } else {
            XCTAssertGreaterThan(first.height, fixture.firstFrame.height + 60)
        }
    }

    @MainActor
    func testEdgeDragIsIgnoredInsideWindowWhenDisabledOrObstructed() throws {
        let fixture = try makeDwindleFixture(pid: 1_302)
        let handler = fixture.handler

        XCTAssertFalse(handler.dispatchMouseDown(at: fixture.firstFrame.center, modifiers: []))
        XCTAssertFalse(handler.state.isResizing)

        handler.edgeDragUnobstructedProvider = { _, _ in false }
        XCTAssertFalse(handler.dispatchMouseDown(at: fixture.gapPoint, modifiers: []))
        XCTAssertFalse(handler.state.isResizing)

        handler.edgeDragUnobstructedProvider = { _, _ in true }
        fixture.controller.settings.gestures.mouseEdgeDragResize = false
        XCTAssertFalse(handler.dispatchMouseDown(at: fixture.gapPoint, modifiers: []))
        XCTAssertFalse(handler.state.isResizing)
        XCTAssertNil(fixture.engine.interactiveResize)
    }

    @MainActor
    func testTitleBarDropOnOtherTileSwaps() throws {
        let fixture = try makeDwindleFixture(pid: 1_303)
        let entry = try XCTUnwrap(fixture.controller.workspaceManager.entry(for: fixture.first))
        let moved = fixture.firstFrame.offsetBy(dx: 300, dy: 0)

        fixture.handler.swapNativeTitleBarDropTargetIfNeeded(
            entry, at: fixture.secondFrame.center,
            observedFrame: moved.insetBy(dx: -50, dy: 0), lastAppliedFrame: fixture.firstFrame
        )
        fixture.relayout()
        XCTAssertEqual(fixture.presentedFrame(fixture.first), fixture.firstFrame)

        fixture.controller.settings.gestures.mouseTitleBarDragSwap = false
        fixture.handler.swapNativeTitleBarDropTargetIfNeeded(
            entry, at: fixture.secondFrame.center, observedFrame: moved, lastAppliedFrame: fixture.firstFrame
        )
        fixture.relayout()
        XCTAssertEqual(fixture.presentedFrame(fixture.first), fixture.firstFrame)

        fixture.controller.settings.gestures.mouseTitleBarDragSwap = true
        fixture.handler.swapNativeTitleBarDropTargetIfNeeded(
            entry, at: fixture.secondFrame.center, observedFrame: moved, lastAppliedFrame: fixture.firstFrame
        )
        XCTAssertNil(fixture.engine.interactiveMove)
        fixture.relayout()
        XCTAssertEqual(fixture.presentedFrame(fixture.first), fixture.secondFrame)
        XCTAssertEqual(fixture.presentedFrame(fixture.second), fixture.firstFrame)
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

        var isSideBySide: Bool {
            secondFrame.minX >= firstFrame.maxX
        }

        var gapPoint: CGPoint {
            isSideBySide
                ? CGPoint(x: (firstFrame.maxX + secondFrame.minX) / 2, y: firstFrame.midY)
                : CGPoint(x: firstFrame.midX, y: (firstFrame.minY + secondFrame.maxY) / 2)
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
        let workingFrame = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let monitor = Monitor(
            id: .init(displayId: 51_301),
            displayId: 51_301,
            frame: workingFrame,
            visibleFrame: workingFrame,
            hasNotch: false,
            name: "Edge Drag Resize"
        )
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
        controller.mouseEventHandler.edgeDragUnobstructedProvider = { _, _ in true }
        return try DwindleFixture(
            controller: controller,
            engine: engine,
            workspaceId: workspaceId,
            screen: screen,
            first: tokens[0],
            second: tokens[1],
            firstFrame: XCTUnwrap(engine.presentedFrame(for: tokens[0], in: workspaceId, at: 0)),
            secondFrame: XCTUnwrap(engine.presentedFrame(for: tokens[1], in: workspaceId, at: 0))
        )
    }

    @MainActor
    private func makeController() -> WMController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgeDragResizeTests-\(UUID().uuidString)", isDirectory: true)
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
}
