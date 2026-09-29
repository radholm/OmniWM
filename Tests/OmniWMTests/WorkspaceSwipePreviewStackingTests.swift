// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceSwipePreviewStackingTests: XCTestCase {
    func testFullscreenAndFloatingPreviewsStackAboveTiledPreviews() throws {
        let controller = WindowAdmissionTestSupport.controller(prefix: "OmniWMWorkspaceSwipePreviewStackingTests")
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let workspaceId = try XCTUnwrap(
            WindowAdmissionTestSupport.workspace(named: "841", layoutType: .dwindle, controller: controller)
        )
        let manager = controller.workspaceManager
        func add(_ windowId: Int, mode: TrackedWindowMode = .tiling) -> WindowToken {
            manager.addWindow(
                AXWindowRef(element: AXUIElementCreateApplication(840_000), windowId: windowId),
                pid: 840_000, windowId: windowId, to: workspaceId, mode: mode
            )
        }
        let floating = add(841_001, mode: .floating)
        let fullscreen = add(841_002)
        let tiled = add(841_003)
        let engine = try XCTUnwrap(controller.dwindleEngine)
        manager.withEngineMutationScope {
            _ = engine.syncWindows([fullscreen, tiled], in: workspaceId, focusedToken: fullscreen)
            engine.findNode(for: fullscreen, in: workspaceId)?.tile?.setFullscreen(true, for: fullscreen)
        }
        let swipe = WorkspaceSwipePresentation(refreshController: controller.layoutRefreshController)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let items = try [floating, fullscreen, tiled].map {
            try WorkspaceSwipePreview.Item(handle: XCTUnwrap(manager.handle(for: $0)), frame: frame)
        }

        XCTAssertEqual(swipe.stacked(items, in: workspaceId).map(\.token), [tiled, fullscreen, floating])
    }
}
