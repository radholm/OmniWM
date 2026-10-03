// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import OmniWMIPC
import TOML
import XCTest

final class DwindleOnlyConfigurationTests: XCTestCase {
    func testSupportedLayoutValuesAndDefaultAreDwindleOnly() throws {
        XCTAssertEqual(Set(LayoutType.allCases.map(\.rawValue)), ["default", "dwindle"])
        XCTAssertEqual(SettingsExport.defaults().defaultLayoutType, .dwindle)
        for rawValue in ["default", "dwindle"] {
            XCTAssertNotNil(IPCWorkspaceLayout(rawValue: rawValue))
        }
        XCTAssertNil(IPCWorkspaceLayout(rawValue: "unsupported"))
        XCTAssertEqual(SingleWindowFit.Mode.allCases, [.fill, .custom])
    }

    @MainActor
    func testWorkspaceDefaultSentinelRoundTripsButAlwaysResolvesToDwindle() throws {
        var export = SettingsExport.defaults()
        export.workspaceConfigurations = [
            .init(name: "1", layoutType: .defaultLayout),
            .init(name: "2", layoutType: .dwindle)
        ]
        let decoded = try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(export))
        XCTAssertEqual(decoded.workspaceConfigurations.map(\.layoutType), [.defaultLayout, .dwindle])
        let settings = WorkspaceSettings()
        settings.configurations = decoded.workspaceConfigurations
        settings.defaultLayoutType = .defaultLayout
        for name in ["1", "2", "unconfigured"] {
            XCTAssertEqual(settings.layoutType(for: name), .dwindle)
        }
    }

    func testCanonicalTablesAndGesturesContainOnlyRetainedSettings() throws {
        let tree = try TOMLDecoder().decode(
            [String: TOMLNode].self, from: SettingsTOMLCodec.encode(.defaults())
        )
        XCTAssertEqual(Set(tree.keys), [
            "schemaVersion", "general", "focus", "mouseWarp", "routing", "gaps", "dwindle", "borders",
            "overview", "workspaceBar", "gestures", "statusBar", "hiddenBar", "clipboard", "quakeTerminal",
            "scratchpads", "appearance", "hotkeys", "workspaces", "appRules", "monitorBarOverrides",
            "monitorOrientationOverrides", "monitorDwindleOverrides", "monitorGapOverrides"
        ])
        guard case let .table(gestures)? = tree["gestures"] else {
            return XCTFail("Expected canonical gestures table")
        }

        XCTAssertEqual(Set(gestures.keys), [
            "mouseMoveModifierKey", "mouseResizeModifierKey", "invertDirection", "workspaceSwipeEnabled",
            "workspaceSwipeFingerCount", "workspaceSwipeAxis", "overviewGestureEnabled",
            "overviewGestureFingerCount", "windowMoveEnabled", "windowMoveFingerCount", "windowResizeEnabled",
            "windowResizeFingerCount", "windowGestureSensitivity", "workspaceSwipeSensitivity",
            "workspaceWallpaperParallax", "workspaceWallpaperParallaxAmount", "mouseEdgeDragResize",
            "mouseTitleBarDragSwap"
        ])
    }

    func testUnknownSettingsAreIgnoredByDecodeAndDroppedByCanonicalExport() throws {
        let canonical = try SettingsTOMLCodec.encode(.defaults())
        let source = Data((String(decoding: canonical, as: UTF8.self)
                + "\n[legacyLayout]\nobsoleteSetting = true\n").utf8)
        let decoded = try SettingsTOMLCodec.decode(source)
        XCTAssertEqual(decoded, .defaults())
        XCTAssertEqual(try SettingsTOMLCodec.encode(decoded), canonical)
        let preserved = try SettingsTOMLCodec.encode(decoded, preservingUnknownKeysFrom: source)
        let tree = try TOMLDecoder().decode([String: TOMLNode].self, from: preserved)
        XCTAssertEqual(tree["legacyLayout"], .table(["obsoleteSetting": .boolean(true)]))
    }

    func testUnsupportedLayoutValueReportsCanonicalKeyPath() throws {
        let canonical = String(decoding: try SettingsTOMLCodec.encode(.defaults()), as: UTF8.self)
        let source = canonical.replacingOccurrences(
            of: "defaultLayoutType = \"dwindle\"", with: "defaultLayoutType = \"unsupported\""
        )
        XCTAssertNotEqual(source, canonical)
        XCTAssertThrowsError(try SettingsTOMLCodec.decode(Data(source.utf8))) { error in
            XCTAssertTrue(SettingsTOMLCodec.diagnosticDescription(for: error).contains("general.defaultLayoutType"))
        }
    }

    func testDwindleCommandsRemainTypedAndGroupMovementHasCanonicalWireName() throws {
        XCTAssertEqual(Set(IPCDwindleCommandName.allCases.map(\.rawValue)), [
            "cycle-size-forward", "cycle-size-backward",
            "balance-sizes", "move-to-root", "move-group", "toggle-split", "swap-split",
            "resize", "resize-focused", "preselect", "preselect-clear"
        ])
        let request = try IPCCommandRequest(
            name: .dwindle(.moveGroup), argumentValues: [.direction(.left)]
        )
        XCTAssertEqual(request, .dwindle(.moveGroup(direction: .left)))
        XCTAssertEqual(try JSONDecoder().decode(IPCCommandRequest.self, from: JSONEncoder().encode(request)), request)
        XCTAssertEqual(IPCCommandName(rawValue: "move-group"), .dwindle(.moveGroup))
        XCTAssertNil(IPCCommandName(rawValue: "move-column"))
        XCTAssertEqual(ActionCatalog.spec(for: .dwindle(.moveGroup(.left)))?.layoutCompatibility, .dwindle)
    }
}
