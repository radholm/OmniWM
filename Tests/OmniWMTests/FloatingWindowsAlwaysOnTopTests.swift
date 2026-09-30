// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class FloatingWindowsAlwaysOnTopTests: XCTestCase {
    private enum Operation: Equatable {
        case activate(pid_t)
        case focus(WindowToken)
        case raise
    }

    private final class Recorder {
        var operations: [Operation] = []
    }

    func testMouseFocusOnTiledWindowDoesNotRaiseItOverOverlappingFloatingWindow() throws {
        let fixture = try makeFixture()
        let source = addWindow(pid: 830_001, windowId: 830_101, fixture: fixture)
        let target = addWindow(pid: 830_002, windowId: 830_102, fixture: fixture)
        let floating = addWindow(pid: 830_003, windowId: 830_103, fixture: fixture, mode: .floating)
        setFrame(CGRect(x: 800, y: 0, width: 800, height: 900), for: target, fixture: fixture)
        setFrame(CGRect(x: 1000, y: 200, width: 400, height: 300), for: floating, fixture: fixture)
        setFocused(source, fixture: fixture)
        fixture.recorder.operations.removeAll()

        fixture.controller.mouseEventHandler.dispatchMouseMoved(
            at: CGPoint(x: 100, y: 100),
            windowIdUnderPointer: target.windowId
        )

        XCTAssertEqual(fixture.recorder.operations, [.focus(target)])
    }

    func testMouseFocusOnTiledWindowRaisesWhenNoFloatingWindowOverlapsIt() throws {
        let fixture = try makeFixture()
        let source = addWindow(pid: 830_031, windowId: 830_131, fixture: fixture)
        let target = addWindow(pid: 830_032, windowId: 830_132, fixture: fixture)
        let floating = addWindow(pid: 830_033, windowId: 830_133, fixture: fixture, mode: .floating)
        setFrame(CGRect(x: 800, y: 0, width: 800, height: 900), for: target, fixture: fixture)
        setFrame(CGRect(x: 100, y: 200, width: 400, height: 300), for: floating, fixture: fixture)
        setFocused(source, fixture: fixture)
        fixture.recorder.operations.removeAll()

        fixture.controller.mouseEventHandler.dispatchMouseMoved(
            at: CGPoint(x: 100, y: 100),
            windowIdUnderPointer: target.windowId
        )

        XCTAssertEqual(fixture.recorder.operations, [.activate(target.pid), .focus(target), .raise])
    }

    func testMouseFocusOnTiledWindowRaisesWithoutFloatingWindows() throws {
        let fixture = try makeFixture()
        let source = addWindow(pid: 830_071, windowId: 830_171, fixture: fixture)
        let target = addWindow(pid: 830_072, windowId: 830_172, fixture: fixture)
        setFocused(source, fixture: fixture)
        fixture.recorder.operations.removeAll()

        fixture.controller.mouseEventHandler.dispatchMouseMoved(
            at: CGPoint(x: 100, y: 100),
            windowIdUnderPointer: target.windowId
        )

        XCTAssertEqual(fixture.recorder.operations, [.activate(target.pid), .focus(target), .raise])
    }

    func testMouseFocusOnTiledWindowRaisesWhenSettingDisabled() throws {
        let fixture = try makeFixture(alwaysOnTop: false)
        let source = addWindow(pid: 830_011, windowId: 830_111, fixture: fixture)
        let target = addWindow(pid: 830_012, windowId: 830_112, fixture: fixture)
        setFocused(source, fixture: fixture)
        fixture.recorder.operations.removeAll()

        fixture.controller.mouseEventHandler.dispatchMouseMoved(
            at: CGPoint(x: 100, y: 100),
            windowIdUnderPointer: target.windowId
        )

        XCTAssertEqual(fixture.recorder.operations, [.activate(target.pid), .focus(target), .raise])
    }

    func testMouseFocusOnFloatingWindowStillRaisesIt() throws {
        let fixture = try makeFixture()
        let source = addWindow(pid: 830_021, windowId: 830_121, fixture: fixture)
        let floating = addWindow(pid: 830_022, windowId: 830_122, fixture: fixture, mode: .floating)
        setFocused(source, fixture: fixture)
        fixture.recorder.operations.removeAll()

        fixture.controller.mouseEventHandler.dispatchMouseMoved(
            at: CGPoint(x: 100, y: 100),
            windowIdUnderPointer: floating.windowId
        )

        XCTAssertEqual(fixture.recorder.operations, [.activate(floating.pid), .focus(floating), .raise])
    }

    func testMouseOverTiledWindowKeepsFocusOnFloatingWindow() throws {
        let fixture = try makeFixture()
        let tiled = addWindow(pid: 830_041, windowId: 830_141, fixture: fixture)
        let floating = addWindow(pid: 830_042, windowId: 830_142, fixture: fixture, mode: .floating)
        setFocused(floating, fixture: fixture)
        fixture.recorder.operations.removeAll()

        fixture.controller.mouseEventHandler.dispatchMouseMoved(
            at: CGPoint(x: 100, y: 100),
            windowIdUnderPointer: tiled.windowId
        )

        XCTAssertEqual(fixture.recorder.operations, [])
        XCTAssertNil(fixture.controller.intentLedger.activeManagedRequest)
    }

    func testMouseOverTiledWindowFocusesItWhenSettingDisabled() throws {
        let fixture = try makeFixture(alwaysOnTop: false)
        let tiled = addWindow(pid: 830_051, windowId: 830_151, fixture: fixture)
        let floating = addWindow(pid: 830_052, windowId: 830_152, fixture: fixture, mode: .floating)
        setFocused(floating, fixture: fixture)
        fixture.recorder.operations.removeAll()

        fixture.controller.mouseEventHandler.dispatchMouseMoved(
            at: CGPoint(x: 100, y: 100),
            windowIdUnderPointer: tiled.windowId
        )

        XCTAssertEqual(fixture.controller.intentLedger.activeManagedRequest?.token, tiled)
    }

    func testMouseOverFloatingWindowStillTakesFocusFromTiledWindow() throws {
        let fixture = try makeFixture()
        let tiled = addWindow(pid: 830_061, windowId: 830_161, fixture: fixture)
        let floating = addWindow(pid: 830_062, windowId: 830_162, fixture: fixture, mode: .floating)
        setFocused(tiled, fixture: fixture)

        fixture.controller.mouseEventHandler.dispatchMouseMoved(
            at: CGPoint(x: 100, y: 100),
            windowIdUnderPointer: floating.windowId
        )

        XCTAssertEqual(fixture.controller.intentLedger.activeManagedRequest?.token, floating)
    }

    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let recorder: Recorder
    }

    private func makeFixture(alwaysOnTop: Bool = true) throws -> Fixture {
        let recorder = Recorder()
        let controller = WindowAdmissionTestSupport.controller(
            prefix: "OmniWMFloatingWindowsAlwaysOnTopTests",
            windowFocusOperations: WindowFocusOperations(
                activateApp: { recorder.operations.append(.activate($0)) },
                focusSpecificWindow: { pid, windowId, _ in
                    recorder.operations.append(.focus(WindowToken(pid: pid, windowId: Int(windowId))))
                },
                raiseWindow: { _ in recorder.operations.append(.raise) }
            )
        )
        let workspaceId = try XCTUnwrap(WindowAdmissionTestSupport.workspace(
            named: "831",
            layoutType: .dwindle,
            controller: controller
        ))
        _ = controller.workspaceManager.focusWorkspace(named: "831")
        controller.dwindleLayoutHandler.enableDwindleLayout()
        controller.settings.focus.floatingWindowsAlwaysOnTop = alwaysOnTop
        controller.settings.focus.raiseOnMouseFocus = true
        controller.setFocusFollowsMouse(true)
        return Fixture(controller: controller, workspaceId: workspaceId, recorder: recorder)
    }

    private func addWindow(
        pid: pid_t,
        windowId: Int,
        fixture: Fixture,
        mode: TrackedWindowMode = .tiling
    ) -> WindowToken {
        let token = fixture.controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: fixture.workspaceId,
            mode: mode
        )
        if mode == .tiling, let engine = fixture.controller.dwindleEngine {
            let tiled = fixture.controller.workspaceManager.tiledEntries(in: fixture.workspaceId).map(\.token)
            _ = fixture.controller.workspaceManager.withEngineMutationScope {
                engine.syncWindows(tiled, in: fixture.workspaceId, focusedToken: token)
            }
        }
        return token
    }

    private func setFrame(_ frame: CGRect, for token: WindowToken, fixture: Fixture) {
        fixture.controller.axManager.frameLedger.confirmFrameWrite(for: token.windowId, frame: frame)
    }

    private func setFocused(_ token: WindowToken, fixture: Fixture) {
        XCTAssertTrue(
            fixture.controller.workspaceManager.confirmManagedFocus(
                token,
                in: fixture.workspaceId,
                activateWorkspaceOnMonitor: false
            )
        )
    }
}
