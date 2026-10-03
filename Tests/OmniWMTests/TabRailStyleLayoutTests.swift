// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

final class TabRailStyleLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testDwindleIconWidthAppliesToContentAndMinimumOnce() throws {
        let engine = DwindleLayoutEngine()
        let workspace = WorkspaceDescriptor.ID()
        let first = WindowToken(pid: 1, windowId: 1)
        let second = WindowToken(pid: 2, windowId: 2)
        _ = engine.addWindow(token: first, to: workspace, activeWindowFrame: nil)
        _ = engine.addWindow(token: second, to: workspace, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: workspace, screen: screen)
        XCTAssertTrue(engine.groupWindow(direction: .left, in: workspace))
        let tile = try XCTUnwrap(engine.root(for: workspace)?.tile)
        engine.updateWindowConstraints(
            for: first,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 400, height: 300), maxSize: .zero, isFixed: false)
        )

        for width: CGFloat in [10, 28, 10] {
            engine.tabRailWidth = width
            let frame = try XCTUnwrap(engine.calculateLayout(for: workspace, screen: screen)[second])
            XCTAssertEqual(frame.minX, width)
            XCTAssertEqual(frame.width, screen.width - width)
            XCTAssertEqual(engine.minimumSize(for: tile, excluding: []), CGSize(width: 400 + width, height: 300))
            XCTAssertEqual(engine.minimumSize(for: tile, excluding: [second]), CGSize(width: 400, height: 300))
            XCTAssertEqual(
                engine.contentFrame(for: tile, member: tile.members[0], tileFrame: screen, excludedTokens: [second]),
                screen
            )
        }
    }

    @MainActor
    func testControllerToggleAndReloadUpdateBothEngines() throws {
        let settings = makeSettings()
        settings.borders.enabled = false
        settings.workspaceBar.enabled = false
        let controller = WMController(settings: settings)
        defer { controller.layoutRefreshController.resetState() }
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let dwindle = try XCTUnwrap(controller.dwindleEngine)
        let monitor = Monitor(
            id: .init(displayId: 1),
            displayId: 1,
            frame: screen,
            visibleFrame: screen,
            hasNotch: false,
            name: "Display"
        )
        XCTAssertEqual(dwindle.tabRailWidth, 10)

        for enabled in [true, false] {
            controller.layoutRefreshController.resetState()
            controller.setTabRailAppIcons(enabled)
            let expectedWidth: CGFloat = enabled ? 28 : 10
            XCTAssertEqual(settings.tabRailAppIcons, enabled)
            XCTAssertEqual(controller.tabRailStyle.reservedWidth, expectedWidth)
            XCTAssertEqual(dwindle.tabRailWidth, expectedWidth)
            XCTAssertEqual(
                controller.dwindleLayoutHandler.geometryContext(
                    monitor: monitor,
                    settings: controller.resolvedDwindleSettings(for: monitor)
                )?.tabRailWidth,
                expectedWidth
            )
            XCTAssertEqual(controller.layoutRefreshController.layoutState.activeRefresh?.kind, .relayout)
            XCTAssertEqual(controller.layoutRefreshController.layoutState.activeRefresh?.reason, .layoutConfigChanged)
        }

        for enabled in [true, false] {
            var exported = settings.toExport()
            exported.tabRailAppIcons = enabled
            settings.applyExport(exported)
            controller.layoutRefreshController.resetState()
            controller.applyPersistedSettings(settings, startServices: false)
            XCTAssertEqual(dwindle.tabRailWidth, enabled ? 28 : 10)
            XCTAssertNotNil(controller.layoutRefreshController.layoutState.pendingRefresh)
        }
    }

    @MainActor
    private func makeSettings() -> SettingsStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMTabRailStyleTests-\(UUID().uuidString)", isDirectory: true)
        return SettingsStore(
            persistence: SettingsFilePersistence(
                directory: directory.appendingPathComponent("config"), startWatching: false, deferSaves: false
            ),
            runtimeState: RuntimeStateStore(directory: directory.appendingPathComponent("state"), deferSaves: false),
            autosaveEnabled: false
        )
    }
}
