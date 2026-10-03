// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Carbon
import OmniWMIPC

extension ActionCatalog {
    static func appendDirectionalFocusBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "focus.left",
                command: .focus(.left),
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey))
            ),
            action(
                id: "focus.down",
                command: .focus(.down),
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(optionKey)),
                keywords: ["group", "tab", "cycle"]
            ),
            action(
                id: "focus.up",
                command: .focus(.up),
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey)),
                keywords: ["group", "tab", "cycle"]
            ),
            action(
                id: "focus.right",
                command: .focus(.right),
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey))
            )
        ])
    }

    static func appendFocusHistoryBinding(_ specs: inout [ActionSpec]) {
        specs.append(
            action(
                id: "focusPrevious",
                command: .focusNavigation(.previous),
                category: .focus,
                binding: KeyBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey)),
                keywords: ["last focused", "recent window"]
            )
        )
    }

    static func appendWindowFocusBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "focusWindowDownOrTop",
                command: .focusNavigation(.windowDownOrTop),
                category: .focus,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["wrap", "group", "tab", "cycle"]
            ),
            action(
                id: "focusWindowUpOrBottom",
                command: .focusNavigation(.windowUpOrBottom),
                category: .focus,
                binding: .unassigned,
                visibility: .advanced,
                keywords: ["wrap", "group", "tab", "cycle"]
            )
        ])
    }
}
