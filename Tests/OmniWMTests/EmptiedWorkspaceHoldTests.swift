// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class EmptiedWorkspaceHoldTests: XCTestCase {
    private struct Fixture {
        let controller: WMController
        let emptiedWorkspaceId: WorkspaceDescriptor.ID
        let otherWorkspaceId: WorkspaceDescriptor.ID
        let quittingToken: WindowToken
        let otherToken: WindowToken
    }

    func testActivationOfOtherWorkspaceIsFollowedWhileWorkspaceHasLiveWindows() throws {
        let fixture = try makeFixture(suffix: 1)
        defer { stop(fixture) }
        fixture.controller.axEventHandler.applicationIsTerminatedProvider = { _ in false }

        activateOther(fixture)

        XCTAssertEqual(activeWorkspaceId(fixture), fixture.otherWorkspaceId)
    }

    func testQuittingLastAppKeepsEmptiedWorkspaceActive() throws {
        let fixture = try makeFixture(suffix: 2)
        defer { stop(fixture) }
        fixture.controller.axEventHandler.applicationIsTerminatedProvider = {
            $0 == fixture.quittingToken.pid
        }

        fixture.controller.axEventHandler.handleAppTerminated(pid: fixture.quittingToken.pid)
        activateOther(fixture)

        XCTAssertEqual(fixture.controller.workspaceManager.windowCount(in: fixture.emptiedWorkspaceId), 0)
        XCTAssertEqual(activeWorkspaceId(fixture), fixture.emptiedWorkspaceId)
    }

    func testActivationBeforeTerminationKeepsEmptiedWorkspaceActive() throws {
        let fixture = try makeFixture(suffix: 3)
        defer { stop(fixture) }
        fixture.controller.axEventHandler.applicationIsTerminatedProvider = {
            $0 == fixture.quittingToken.pid
        }

        activateOther(fixture)
        fixture.controller.axEventHandler.handleAppTerminated(pid: fixture.quittingToken.pid)

        XCTAssertEqual(activeWorkspaceId(fixture), fixture.emptiedWorkspaceId)
    }

    func testActivationBeforeDestroyIsProcessedKeepsEmptiedWorkspaceActive() throws {
        let fixture = try makeFixture(suffix: 5)
        defer { stop(fixture) }
        let handler = fixture.controller.axEventHandler
        let liveInfo = handler.windowInfoProvider
        handler.applicationIsTerminatedProvider = { _ in false }
        handler.windowInfoProvider = { $0 == UInt32(fixture.quittingToken.windowId) ? nil : liveInfo($0) }

        activateOther(fixture)

        XCTAssertEqual(activeWorkspaceId(fixture), fixture.emptiedWorkspaceId)
    }

    func testClosingLastWindowKeepsEmptiedWorkspaceActive() throws {
        let fixture = try makeFixture(suffix: 4)
        defer { stop(fixture) }
        fixture.controller.axEventHandler.applicationIsTerminatedProvider = { _ in false }

        fixture.controller.axEventHandler.handleRemoved(token: fixture.quittingToken)
        activateOther(fixture)

        XCTAssertEqual(activeWorkspaceId(fixture), fixture.emptiedWorkspaceId)
    }

    private func activateOther(_ fixture: Fixture) {
        _ = fixture.controller.axEventHandler.handleAppActivation(
            pid: fixture.otherToken.pid,
            source: .workspaceDidActivateApplication
        )
        fixture.controller.eventIntake.drainNow()
    }

    private func activeWorkspaceId(_ fixture: Fixture) -> WorkspaceDescriptor.ID? {
        let manager = fixture.controller.workspaceManager
        return manager.monitorId(for: fixture.emptiedWorkspaceId).flatMap { manager.activeWorkspace(on: $0)?.id }
    }

    private func makeFixture(suffix: Int) throws -> Fixture {
        let controller = WindowAdmissionTestSupport.controller(
            prefix: "OmniWMEmptiedWorkspaceHoldTests\(suffix)",
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in },
                orderWindow: { _ in }
            )
        )
        let monitor = Monitor(
            id: .init(displayId: CGDirectDisplayID(790_100 + suffix)),
            displayId: CGDirectDisplayID(790_100 + suffix),
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 860),
            hasNotch: false,
            name: "Emptied Workspace Hold"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        let emptiedWorkspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let otherWorkspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "2", createIfMissing: true)
        )
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.dwindleLayoutHandler.enableDwindleLayout()

        let quittingToken = WindowToken(pid: pid_t(790_000 + suffix * 10), windowId: 790_001 + suffix * 10)
        let otherToken = WindowToken(pid: pid_t(790_002 + suffix * 10), windowId: 790_003 + suffix * 10)
        let quittingRef = WindowAdmissionTestSupport.axRef(for: quittingToken)
        let otherRef = WindowAdmissionTestSupport.axRef(for: otherToken)
        _ = controller.workspaceManager.addWindow(
            quittingRef,
            pid: quittingToken.pid,
            windowId: quittingToken.windowId,
            to: emptiedWorkspaceId,
            mode: .tiling
        )
        _ = controller.workspaceManager.addWindow(
            otherRef,
            pid: otherToken.pid,
            windowId: otherToken.windowId,
            to: otherWorkspaceId,
            mode: .tiling
        )
        let engine = try XCTUnwrap(controller.dwindleEngine)
        controller.workspaceManager.withEngineMutationScope(in: emptiedWorkspaceId) {
            _ = engine.addWindow(token: quittingToken, to: emptiedWorkspaceId, activeWindowFrame: nil)
        }
        controller.workspaceManager.withEngineMutationScope(in: otherWorkspaceId) {
            _ = engine.addWindow(token: otherToken, to: otherWorkspaceId, activeWindowFrame: nil)
        }
        XCTAssertTrue(
            controller.workspaceManager.confirmManagedFocus(
                quittingToken,
                in: emptiedWorkspaceId,
                activateWorkspaceOnMonitor: false
            )
        )

        controller.factResolver.factProvider = { pid in
            pid == otherToken.pid
                ? FocusedWindowFact(axRef: otherRef, isFullscreen: false, isSystemModalSurface: false)
                : nil
        }
        controller.axEventHandler.windowInfoProvider = { WindowServerInfo(id: $0, pid: 0, level: 0, frame: .zero) }
        controller.hasStartedServices = true
        controller.eventIntake.open(sink: controller.eventInterpreter)

        return Fixture(
            controller: controller,
            emptiedWorkspaceId: emptiedWorkspaceId,
            otherWorkspaceId: otherWorkspaceId,
            quittingToken: quittingToken,
            otherToken: otherToken
        )
    }

    private func stop(_ fixture: Fixture) {
        fixture.controller.eventIntake.close()
        fixture.controller.deadlineWheel.stop()
        fixture.controller.layoutRefreshController.resetState()
        fixture.controller.hasStartedServices = false
    }
}
