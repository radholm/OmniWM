// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import OmniWMIPC
import XCTest

@MainActor
final class ActiveLayoutRoutingTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1600, height: 900)

    func testLayoutTopologyProjectsOnlyDwindleEngineForDwindleWorkspace() throws {
        let controller = makeController()
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let dwindleEngine = try XCTUnwrap(controller.dwindleEngine)
        let workspaceId = try makeTransientWorkspace(named: "61", layoutType: .dwindle, controller: controller)
        let token = addManagedWindow(pid: 951, windowId: 1, to: workspaceId, controller: controller)

        controller.workspaceManager.withEngineMutationScope {
            _ = dwindleEngine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
            _ = dwindleEngine.toggleFullscreen(in: workspaceId)
        }

        let topology = controller.workspaceManager.layoutTopology(for: workspaceId)
        XCTAssertEqual(topology.dwindleFullscreenTokens, [token])
        XCTAssertTrue(topology.isFullscreen(token))
    }

    func testKeyboardFocusFrameQueriesActiveDwindleEngine() throws {
        let controller = makeController()
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let dwindleEngine = try XCTUnwrap(controller.dwindleEngine)
        let workspaceId = try makeTransientWorkspace(named: "65", layoutType: .dwindle, controller: controller)
        let token = addManagedWindow(pid: 955, windowId: 1, to: workspaceId, controller: controller)

        controller.workspaceManager.withEngineMutationScope {
            _ = dwindleEngine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
            _ = dwindleEngine.calculateLayout(for: workspaceId, screen: screenFrame)
        }

        let dwindleFrame = try XCTUnwrap(dwindleEngine.findNode(for: token, in: workspaceId)?.cachedFrame)
        XCTAssertEqual(controller.preferredKeyboardFocusFrame(for: token), dwindleFrame)
    }

    func testFocusConfirmationActivatesOnlyDwindleEngineForDwindleWorkspace() throws {
        let controller = makeController()
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let dwindleEngine = try XCTUnwrap(controller.dwindleEngine)
        let workspaceId = try makeTransientWorkspace(named: "67", layoutType: .dwindle, controller: controller)
        let mainToken = addManagedWindow(pid: 957, windowId: 1, to: workspaceId, controller: controller)
        let otherToken = addManagedWindow(pid: 957, windowId: 2, to: workspaceId, controller: controller)

        controller.workspaceManager.withEngineMutationScope {
            _ = dwindleEngine.addWindow(token: mainToken, to: workspaceId, activeWindowFrame: nil)
            let otherNode = dwindleEngine.addWindow(token: otherToken, to: workspaceId, activeWindowFrame: nil)
            dwindleEngine.setSelectedNode(otherNode, in: workspaceId)
        }
        let entry = try XCTUnwrap(controller.workspaceManager.entry(for: mainToken))

        controller.axEventHandler.handleManagedAppActivation(
            entry: entry,
            isWorkspaceActive: true,
            appFullscreen: false,
            confirmRequest: false
        )

        let mainLeaf = try XCTUnwrap(dwindleEngine.findNode(for: mainToken, in: workspaceId))
        XCTAssertTrue(dwindleEngine.selectedNode(in: workspaceId) === mainLeaf)
    }

    func testFocusValidationUpdatesOnlyActiveDwindleSelection() throws {
        let controller = makeController()
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let dwindleEngine = try XCTUnwrap(controller.dwindleEngine)
        let workspaceId = try makeTransientWorkspace(named: "75", layoutType: .dwindle, controller: controller)
        let focusedToken = addManagedWindow(pid: 964, windowId: 1, to: workspaceId, controller: controller)
        let staleToken = addManagedWindow(pid: 964, windowId: 2, to: workspaceId, controller: controller)
        controller.workspaceManager.withEngineMutationScope {
            _ = dwindleEngine.addWindow(token: focusedToken, to: workspaceId, activeWindowFrame: nil)
            _ = dwindleEngine.addWindow(token: staleToken, to: workspaceId, activeWindowFrame: nil)
        }
        _ = controller.workspaceManager.setManagedFocus(focusedToken, in: workspaceId)

        controller.ensureFocusedTokenValid(in: workspaceId)

        XCTAssertEqual(dwindleEngine.selectedNode(in: workspaceId)?.windowToken, focusedToken)
    }

    func testWindowQueriesReportActiveLayoutFullscreen() throws {
        let controller = makeController()
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let dwindleEngine = try XCTUnwrap(controller.dwindleEngine)
        let workspaceId = try makeTransientWorkspace(named: "76", layoutType: .dwindle, controller: controller)
        let fullscreenToken = addManagedWindow(pid: 967, windowId: 1, to: workspaceId, controller: controller)
        let tiledToken = addManagedWindow(pid: 967, windowId: 2, to: workspaceId, controller: controller)

        controller.workspaceManager.withEngineMutationScope {
            _ = dwindleEngine.addWindow(token: fullscreenToken, to: workspaceId, activeWindowFrame: nil)
            _ = dwindleEngine.addWindow(token: tiledToken, to: workspaceId, activeWindowFrame: nil)
            dwindleEngine.setSelectedNode(
                dwindleEngine.findNode(for: fullscreenToken, in: workspaceId),
                in: workspaceId
            )
            _ = dwindleEngine.toggleFullscreen(in: workspaceId)
        }
        _ = controller.workspaceManager.setManagedFocus(fullscreenToken, in: workspaceId)
        let router = IPCQueryRouter(controller: controller, appVersion: nil, sessionToken: "fullscreen-query-tests")
        router.windowOrderedInProvider = { _ in true }

        let windows = router.windowsResult(IPCQueryRequest(name: .windows, fields: ["window-id", "is-fullscreen"]))
            .windows
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: windows.map { ($0.windowId, $0.isFullscreen) }),
            [1: true, 2: false]
        )
        XCTAssertNil(
            router.windowsResult(IPCQueryRequest(name: .windows, fields: ["window-id"])).windows.first?.isFullscreen
        )
        XCTAssertEqual(router.focusedWindowResult().window?.isFullscreen, true)
        XCTAssertTrue(IPCAutomationManifest.windowFieldCatalog.contains("is-fullscreen"))
    }

    private func makeTransientWorkspace(
        named name: String,
        layoutType: LayoutType,
        controller: WMController
    ) throws -> WorkspaceDescriptor.ID {
        controller.settings.workspaces.configurations.append(WorkspaceConfiguration(name: name, layoutType: layoutType))
        controller.workspaceManager.applySettings()
        return try XCTUnwrap(controller.workspaceManager.workspaceId(named: name))
    }

    private func addManagedWindow(
        pid: pid_t,
        windowId: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        controller: WMController
    ) -> WindowToken {
        controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
    }

    private func makeController() -> WMController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMActiveLayoutRoutingTests-\(UUID().uuidString)", isDirectory: true)
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
        return WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
    }
}
