// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import OmniWMIPC
import XCTest

@MainActor
final class WindowMinimizationTests: XCTestCase {
    func testDwindleMinimizationRetainsSplitAndRestoresFrames() throws {
        let controller = WindowAdmissionTestSupport.controller()
        let workspaceId = try XCTUnwrap(WindowAdmissionTestSupport.workspace(
            named: "688",
            layoutType: .dwindle,
            controller: controller
        ))
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let first = WindowToken(pid: 688_002, windowId: 688_201)
        let second = WindowToken(pid: 688_002, windowId: 688_202)
        _ = WindowAdmissionTestSupport.track(first, in: workspaceId, controller: controller)
        _ = WindowAdmissionTestSupport.track(second, in: workspaceId, controller: controller)
        let engine = try XCTUnwrap(controller.dwindleEngine)
        _ = controller.workspaceManager.withEngineMutationScope {
            engine.syncWindows([first, second], in: workspaceId, focusedToken: first)
        }
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let original = controller.workspaceManager.withEngineMutationScope {
            engine.calculateLayout(for: workspaceId, screen: frame)
        }
        let root = try XCTUnwrap(engine.root(for: workspaceId))
        let ratio = root.splitRatio
        controller.workspaceManager.setWindowMinimized(true, token: first)
        XCTAssertEqual(controller.workspaceManager.withEngineMutationScope {
            engine.calculateLayout(for: workspaceId, screen: frame)
        }, [second: frame])
        XCTAssertEqual(engine.root(for: workspaceId)?.id, root.id)
        XCTAssertEqual(engine.root(for: workspaceId)?.splitRatio, ratio)
        controller.workspaceManager.setWindowMinimized(false, token: first)
        XCTAssertEqual(controller.workspaceManager.withEngineMutationScope {
            engine.calculateLayout(for: workspaceId, screen: frame)
        }, original)
    }

    func testAppUnhidePreservesMinimizedFloatingWindowAndItsParkingState() throws {
        let controller = WindowAdmissionTestSupport.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let token = WindowToken(pid: 688_004, windowId: 688_401)
        _ = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        XCTAssertTrue(controller.workspaceManager.setWindowMode(.floating, for: token))
        let hidden = HiddenState(proportionalPosition: .zero, referenceMonitorId: nil, reason: .workspaceInactive)
        controller.workspaceManager.setHiddenState(hidden, for: token)
        controller.workspaceManager.setWindowMinimized(true, token: token)
        controller.workspaceManager.setAppHidden(true, pid: token.pid, source: .ax)
        controller.workspaceManager.setAppHidden(false, pid: token.pid, source: .ax)
        XCTAssertTrue(controller.workspaceManager.isWindowSuppressedByMacOS(token))
        XCTAssertEqual(
            controller.layoutRefreshController
                .restoreWorkspaceInactiveFloatingWindows(activeWorkspaceIds: [workspaceId]),
            0
        )
        XCTAssertEqual(controller.workspaceManager.hiddenState(for: token), hidden)
        controller.workspaceManager.setWindowMinimized(false, token: token)
        XCTAssertEqual(controller.workspaceManager.hiddenState(for: token), hidden)
    }

    func testMinimizedStateSurvivesRekeyAndEndsWithRetirement() throws {
        let controller = WindowAdmissionTestSupport.controller()
        let manager = controller.workspaceManager
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let token = WindowToken(pid: 688_005, windowId: 688_501)
        _ = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        manager.setWindowMinimized(true, token: token)
        let replacement = WindowToken(pid: token.pid, windowId: 688_502)
        let axRef = WindowAdmissionTestSupport.axRef(for: replacement)
        XCTAssertNotNil(manager.rekeyWindow(from: token, to: replacement, newAXRef: axRef))
        XCTAssertTrue(try XCTUnwrap(manager.entry(for: replacement)).observedState.isMinimized)
        _ = manager.removeWindow(pid: replacement.pid, windowId: replacement.windowId)
        _ = WindowAdmissionTestSupport.track(replacement, in: workspaceId, controller: controller)
        XCTAssertFalse(try XCTUnwrap(manager.entry(for: replacement)).observedState.isMinimized)
    }

    func testMinimizedWindowIsNotVisibleInIPCWithoutChangingAppHiddenState() throws {
        let controller = WindowAdmissionTestSupport.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let token = WindowToken(pid: 688_006, windowId: 688_601)
        _ = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        controller.workspaceManager.setWindowMinimized(true, token: token)
        let router = IPCQueryRouter(controller: controller, appVersion: nil, sessionToken: "minimize-tests")
        router.windowOrderedInProvider = { _ in true }
        let window = try XCTUnwrap(router.windowsResult(IPCQueryRequest(name: .windows)).windows.first)
        XCTAssertEqual(window.isVisible, false)
        XCTAssertEqual(window.isAppHidden, false)
    }

    func testRestoreNotificationRechecksNativeFocusAfterRescanAlreadyRestoredState() throws {
        let controller = WindowAdmissionTestSupport.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let token = WindowToken(pid: 688_007, windowId: 688_701)
        let axRef = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        controller.hasStartedServices = true
        defer {
            controller.hasStartedServices = false
            controller.factResolver.stop()
        }
        controller.axEventHandler.frontmostApplicationPIDProvider = { token.pid }
        var factReads = 0
        controller.factResolver.factProvider = { _ in
            factReads += 1
            return nil
        }
        controller.workspaceManager.setWindowMinimized(true, token: token)
        controller.axEventHandler.updateWindowMinimizedState(false, token: token, requestRefresh: false)
        controller.axEventHandler.handleWindowMinimized(pid: token.pid, axRef: axRef, minimized: false)
        XCTAssertEqual(factReads, 1)
    }

    func testUnknownWindowNotificationInvalidatesInitialEnumeration() {
        let controller = WindowAdmissionTestSupport.controller()
        let token = WindowToken(pid: 688_008, windowId: 688_801)
        let seq = controller.workspaceManager.worldSeq
        controller.layoutRefreshController.layoutState.activeFullEnumerationCount = 1
        controller.axEventHandler.handleWindowMinimized(
            pid: token.pid,
            axRef: WindowAdmissionTestSupport.axRef(for: token),
            minimized: false
        )
        XCTAssertFalse(controller.workspaceManager.isSeqEpochCurrent(seq, domains: .layoutCommit))
        controller.layoutRefreshController.layoutState.activeFullEnumerationCount = 0
    }
}
