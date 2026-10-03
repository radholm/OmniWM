// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import OmniWMIPC
import XCTest

final class IPCCommandWireShapeTests: XCTestCase {
    func testEveryCommandConstructionPreservesWireShapeAndRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var coveredNames: Set<IPCCommandName> = []

        for fixture in Self.commandFixtures {
            let data = Data(fixture.utf8)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rawName = try XCTUnwrap(object["name"] as? String)
            let name = try XCTUnwrap(IPCCommandName(rawValue: rawName))
            let descriptor = try XCTUnwrap(IPCAutomationManifest.commandDescriptor(for: name))
            let request = try IPCCommandRequest(
                name: name,
                argumentValues: descriptor.arguments.map { argument($0.kind) }
            )

            XCTAssertTrue(coveredNames.insert(name).inserted, rawName)
            XCTAssertEqual(request.name, name)
            XCTAssertEqual(String(decoding: try encoder.encode(request), as: UTF8.self), fixture, rawName)
            XCTAssertEqual(try JSONDecoder().decode(IPCCommandRequest.self, from: data), request, rawName)
        }

        XCTAssertEqual(coveredNames, Set(IPCCommandName.allCases))
    }

    private func argument(_ kind: IPCCommandArgumentKind) -> IPCCommandArgumentValue {
        switch kind {
        case .direction:
            .direction(.left)
        case .workspaceNumber,
             .scratchpadIndex:
            .integer(2)
        case .layout:
            .layout(.dwindle)
        case .resizeAxis:
            .resizeAxis(.horizontal)
        case .resizeOperation:
            .resizeOperation(.grow)
        }
    }

    private static let commandFixtures = [
        #"{"name":"cycle-size-forward"}"#,
        #"{"name":"cycle-size-backward"}"#,
        #"{"arguments":{"direction":"left"},"name":"move-group"}"#,
        #"{"arguments":{"layout":"dwindle"},"name":"set-workspace-layout"}"#,
        #"{"arguments":{"direction":"left"},"name":"focus"}"#,
        #"{"name":"focus-previous"}"#,
        #"{"name":"focus-window-down-or-top"}"#,
        #"{"name":"focus-window-up-or-bottom"}"#,
        #"{"arguments":{"direction":"left"},"name":"move"}"#,
        #"{"name":"move-window-down"}"#,
        #"{"name":"move-window-up"}"#,
        #"{"arguments":{"workspaceNumber":2},"name":"switch-workspace"}"#,
        #"{"name":"switch-workspace-next"}"#,
        #"{"name":"switch-workspace-previous"}"#,
        #"{"name":"switch-workspace-back-and-forth"}"#,
        #"{"arguments":{"workspaceNumber":2},"name":"switch-workspace-anywhere"}"#,
        #"{"arguments":{"slotNumber":2},"name":"switch-workspace-slot"}"#,
        #"{"arguments":{"slotNumber":2},"name":"move-to-workspace-slot"}"#,
        #"{"arguments":{"workspaceNumber":2},"name":"move-to-workspace"}"#,
        #"{"name":"move-to-workspace-up"}"#,
        #"{"name":"move-to-workspace-down"}"#,
        #"{"arguments":{"direction":"left","workspaceNumber":2},"name":"move-to-workspace-on-monitor"}"#,
        #"{"arguments":{"direction":"left"},"name":"move-to-monitor"}"#,
        #"{"name":"focus-monitor-previous"}"#,
        #"{"name":"focus-monitor-next"}"#,
        #"{"name":"focus-monitor-last"}"#,
        #"{"arguments":{"direction":"left"},"name":"swap-workspace-with-monitor"}"#,
        #"{"name":"balance-sizes"}"#,
        #"{"name":"move-to-root"}"#,
        #"{"name":"toggle-split"}"#,
        #"{"name":"swap-split"}"#,
        #"{"arguments":{"axis":"horizontal","operation":"grow"},"name":"resize"}"#,
        #"{"arguments":{"operation":"grow"},"name":"resize-focused"}"#,
        #"{"arguments":{"direction":"left"},"name":"preselect"}"#,
        #"{"name":"preselect-clear"}"#,
        #"{"name":"open-command-palette"}"#,
        #"{"name":"raise-all-floating-windows"}"#,
        #"{"name":"rescue-offscreen-windows"}"#,
        #"{"name":"toggle-fullscreen"}"#,
        #"{"name":"toggle-native-fullscreen"}"#,
        #"{"name":"toggle-overview"}"#,
        #"{"name":"toggle-system-stats"}"#,
        #"{"name":"toggle-quake-terminal"}"#,
        #"{"name":"toggle-workspace-bar"}"#,
        #"{"name":"hidden-bar-panel"}"#,
        #"{"name":"toggle-focused-window-floating"}"#,
        #"{"name":"close-focused-window"}"#,
        #"{"arguments":{"scratchpadIndex":2},"name":"scratchpad-assign"}"#,
        #"{"arguments":{"scratchpadIndex":2},"name":"scratchpad-toggle"}"#,
        #"{"name":"open-menu-anywhere"}"#
    ]
}
