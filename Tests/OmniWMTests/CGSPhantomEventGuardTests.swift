// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class CGSPhantomEventGuardTests: XCTestCase {
    func testManagedReplacementDoesNotTransferVanishedSpaceMembership() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let oldToken = WindowToken(pid: 949_301, windowId: 949_302)
        let newToken = WindowToken(pid: oldToken.pid, windowId: 949_303)
        _ = controller.workspaceManager.addWindow(
            AXWindowRef(
                element: AXUIElementCreateApplication(oldToken.pid),
                windowId: oldToken.windowId
            ),
            pid: oldToken.pid,
            windowId: oldToken.windowId,
            to: workspaceId
        )
        let currentSpaceId: UInt64 = 949_304
        let vanishedSpaceId: UInt64 = 949_305
        controller.workspaceManager.commitSpaceTopology(
            SpaceTopology(
                displays: [
                    .init(
                        displayIdentifier: "test-display",
                        spaceIds: [currentSpaceId],
                        currentSpaceId: currentSpaceId
                    )
                ],
                activeSpaceId: currentSpaceId,
                fullscreenSpaceIds: [],
                windowSpace: [oldToken.windowId: vanishedSpaceId]
            )
        )

        let entry = controller.workspaceManager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(
                element: AXUIElementCreateApplication(newToken.pid),
                windowId: newToken.windowId
            )
        )

        XCTAssertNotNil(entry)
        XCTAssertNil(controller.workspaceManager.spaceTopology.spaceForWindow(oldToken.windowId))
        XCTAssertNil(controller.workspaceManager.spaceTopology.spaceForWindow(newToken.windowId))
    }

    func testCGSCreateForOwnProcessWindowSchedulesNoRetry() async throws {
        let controller = Self.controller()
        let windowId: UInt32 = 943_101
        controller.axEventHandler.windowInfoProvider = { id in
            guard id == windowId else { return nil }
            return WindowServerInfo(
                id: id,
                pid: getpid(),
                level: 0,
                frame: CGRect(x: 0, y: 0, width: 400, height: 300)
            )
        }

        controller.axEventHandler.handleCGSEvent(.created(windowId: windowId, spaceId: 0))
        await controller.axEventHandler.lifecycleQueries.task?.value

        XCTAssertNil(controller.axEventHandler.pendingCreatePlacementContext(for: Int(windowId)))
        XCTAssertNil(controller.workspaceManager.entry(forWindowId: Int(windowId)))
        XCTAssertEqual(controller.workspaceManager.invariantViolationCountsDump(), "clean")
    }

    func testCGSDestroyForUnmanagedWindowDoesNotScheduleFullRescan() async {
        let controller = Self.controller()
        let windowId: UInt32 = 944_101
        controller.axEventHandler.windowInfoProvider = { _ in nil }

        controller.axEventHandler.handleCGSEvent(
            .destroyed(windowId: windowId, spaceId: 0)
        )
        await controller.axEventHandler.lifecycleQueries.task?.value

        XCTAssertNil(controller.layoutRefreshController.layoutState.activeRefresh)
        XCTAssertNil(controller.layoutRefreshController.layoutState.pendingRefresh)
        XCTAssertEqual(controller.workspaceManager.invariantViolationCountsDump(), "clean")
    }

    private static func managedReplacementMetadata(
        workspaceId: WorkspaceDescriptor.ID,
        pid: pid_t,
        frame: CGRect
    ) -> ManagedReplacementMetadata {
        ManagedReplacementMetadata(
            bundleId: "com.omniwm.tests.close-evidence.\(pid)",
            workspaceId: workspaceId,
            mode: .tiling,
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            title: "replacement",
            windowLevel: 0,
            parentWindowId: nil,
            frame: frame
        )
    }

    private static func controller() -> WMController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMCGSPhantomTests-\(UUID().uuidString)", isDirectory: true)
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
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        let handler = controller.axEventHandler
        handler.lifecycleQueries.query = { [weak handler] in handler?.windowInfoProvider($0) }
        return controller
    }
}
