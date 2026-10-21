// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class OwnedSurfaceFocusReleaseTests: XCTestCase {
    func testClosingOneOfTwoOwnedWindowsKeepsOwnedFocus() throws {
        let fixture = try Fixture()
        let closing = fixture.ownedWindow()
        fixture.registry.registerWindowNumber(
            surfaceId: "remaining-utility",
            policy: SurfacePolicy(
                kind: .utility,
                hitTestPolicy: .frontmostInteractive,
                capturePolicy: .included,
                suppressesManagedFocusRecovery: true
            ),
            windowNumber: 912_001,
            frameProvider: { nil },
            visibilityProvider: { true }
        )
        XCTAssertTrue(fixture.controller.workspaceManager.recordOwnedSurfaceFocus())

        fixture.registry.windowWillClose(closing)

        XCTAssertEqual(fixture.controller.workspaceManager.nativeFocusOwner, .ownedSurface)
    }

    func testHoveringEitherWindowAfterLastOwnedWindowClosesFocusesIt() throws {
        for hoverFirst in [true, false] {
            var focusedTokens: [WindowToken] = []
            let fixture = try Fixture { focusedTokens.append($0) }
            let window = fixture.ownedWindow()
            XCTAssertTrue(fixture.controller.workspaceManager.recordOwnedSurfaceFocus())
            fixture.registry.windowWillClose(window)

            XCTAssertEqual(fixture.controller.workspaceManager.nativeFocusOwner, NativeFocusOwner.none)
            XCTAssertEqual(fixture.controller.workspaceManager.selectedManagedToken, fixture.first)
            let target = hoverFirst ? fixture.first : fixture.second
            let frame = hoverFirst ? fixture.firstFrame : fixture.secondFrame
            fixture.controller.mouseEventHandler.dispatchMouseMoved(at: frame.center)

            XCTAssertEqual(focusedTokens, [target])
        }
    }

    func testHoveringTheFocusedWindowDoesNotRequestFocusAgain() throws {
        var focusedTokens: [WindowToken] = []
        let fixture = try Fixture { focusedTokens.append($0) }

        fixture.controller.mouseEventHandler.dispatchMouseMoved(at: fixture.firstFrame.center)

        XCTAssertEqual(focusedTokens, [])
    }
}

@MainActor
private struct Fixture {
    let controller: WMController
    let registry = OwnedWindowRegistry(surfaceCoordinator: SurfaceCoordinator())
    let first: WindowToken
    let second: WindowToken
    let firstFrame: CGRect
    let secondFrame: CGRect

    init(recordFocus: @escaping (WindowToken) -> Void = { _ in }) throws {
        controller = WindowAdmissionTestSupport.controller(
            prefix: "OwnedSurfaceFocusReleaseTests",
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    recordFocus(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            ),
            ownedWindowRegistry: registry
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.setFocusFollowsMouse(true)
        controller.dwindleLayoutHandler.enableDwindleLayout()
        first = try Self.addWindow(pid: 912_101, to: workspaceId, controller: controller)
        second = try Self.addWindow(pid: 912_102, to: workspaceId, controller: controller)
        let plan = controller.layoutRefreshController.buildRelayoutEffectPlan(
            recoverFocus: false,
            affectedWorkspaceIds: [workspaceId]
        )
        controller.layoutRefreshController.applyEffectPlan(plan, controller: controller)
        let frames = try XCTUnwrap(controller.dwindleEngine).currentFrames(in: workspaceId)
        firstFrame = try XCTUnwrap(frames[first])
        secondFrame = try XCTUnwrap(frames[second])
        XCTAssertTrue(controller.workspaceManager.confirmManagedFocus(
            first,
            in: workspaceId,
            activateWorkspaceOnMonitor: false
        ))
    }

    func ownedWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        registry.register(window)
        return window
    }

    private static func addWindow(
        pid: pid_t,
        to workspaceId: WorkspaceDescriptor.ID,
        controller: WMController
    ) throws -> WindowToken {
        let windowId = Int(pid) + 100
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
        let engine = try XCTUnwrap(controller.dwindleEngine)
        _ = controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
            engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        }
        return token
    }
}
