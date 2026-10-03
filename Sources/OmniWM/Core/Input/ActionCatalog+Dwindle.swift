// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Carbon
import OmniWMIPC

extension ActionCatalog {
    static func appendGroupMoveBindings(_ specs: inout [ActionSpec]) {
        for direction in [Direction.left, .right, .up, .down] {
            let binding: KeyBinding = switch direction {
            case .left:
                .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey | controlKey | shiftKey))
            case .right:
                .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey | controlKey | shiftKey))
            case .up,
                 .down:
                .unassigned
            }
            specs.append(action(
                id: "moveGroup.\(direction.rawValue)",
                command: .dwindle(.moveGroup(direction)),
                category: .layout,
                binding: binding,
                visibility: .advanced,
                keywords: ["move", "tile", "group"]
            ))
        }
    }

    static func appendAxisResizeBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "resizeGrow.horizontal",
                command: .dwindle(.resizeAlongAxis(.horizontal, true)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["resize", "grow"]
            ),
            action(
                id: "resizeGrow.vertical",
                command: .dwindle(.resizeAlongAxis(.vertical, true)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["resize", "grow"]
            ),
            action(
                id: "resizeShrink.horizontal",
                command: .dwindle(.resizeAlongAxis(.horizontal, false)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["resize", "shrink"]
            ),
            action(
                id: "resizeShrink.vertical",
                command: .dwindle(.resizeAlongAxis(.vertical, false)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["resize", "shrink"]
            )
        ])
    }

    static func appendFocusedResizeBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "resizeFocusedWindow.grow",
                command: .dwindle(.resizeFocusedWindow(true)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["resize", "grow"]
            ),
            action(
                id: "resizeFocusedWindow.shrink",
                command: .dwindle(.resizeFocusedWindow(false)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["resize", "shrink"]
            )
        ])
    }

    static func appendPreselectionBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "preselect.left",
                command: .dwindle(.preselect(.left)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "preselect.right",
                command: .dwindle(.preselect(.right)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "preselect.up",
                command: .dwindle(.preselect(.up)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "preselect.down",
                command: .dwindle(.preselect(.down)),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced
            ),
            action(
                id: "preselectClear",
                command: .dwindle(.preselectClear),
                category: .layout,
                binding: .unassigned,
                visibility: .advanced
            )
        ])
    }
}
