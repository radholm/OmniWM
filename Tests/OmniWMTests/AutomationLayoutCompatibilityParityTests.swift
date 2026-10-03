// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import OmniWMIPC
import XCTest

final class AutomationLayoutCompatibilityParityTests: XCTestCase {
    func testManifestLayoutCompatibilityMatchesActionCatalog() {
        var compatibilitiesByCommand: [IPCCommandName: Set<IPCAutomationLayoutCompatibility>] = [:]
        for spec in ActionCatalog.allSpecs() {
            guard let name = spec.ipcCommandName else { continue }
            compatibilitiesByCommand[name, default: []]
                .insert(Self.automationCompatibility(for: spec.layoutCompatibility))
        }
        let commandsWithOneEnforcedCompatibility = compatibilitiesByCommand
            .compactMapValues { $0.count == 1 ? $0.first : nil }

        let mismatches = commandsWithOneEnforcedCompatibility.compactMap { name, enforced -> String? in
            guard let descriptor = IPCAutomationManifest.commandDescriptor(for: name),
                  descriptor.layoutCompatibility != enforced
            else { return nil }
            return "\(descriptor.path): manifest=\(descriptor.layoutCompatibility.rawValue), enforced=\(enforced.rawValue)"
        }.sorted()

        XCTAssertEqual(
            mismatches,
            [],
            "IPCAutomationManifest advertises a layout compatibility that CommandHandler does not enforce. "
                + "ActionCatalog is the runtime authority, so update the manifest to match it."
        )
    }

    func testMoveGroupCompatibilityIsDwindleInEveryDirection() {
        for direction in [Direction.left, .right, .up, .down] {
            XCTAssertEqual(ActionCatalog.layoutCompatibility(for: .dwindle(.moveGroup(direction))), .dwindle)
        }
        XCTAssertEqual(
            IPCAutomationManifest.commandDescriptor(for: .dwindle(.moveGroup))?.layoutCompatibility,
            .dwindle
        )
    }

    private static func automationCompatibility(
        for compatibility: LayoutCompatibility
    ) -> IPCAutomationLayoutCompatibility {
        switch compatibility {
        case .shared: .shared
        case .dwindle: .dwindle
        }
    }
}
