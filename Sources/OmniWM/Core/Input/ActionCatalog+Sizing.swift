// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Carbon
import OmniWMIPC

extension ActionCatalog {
    static func appendSizeCycleBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "cycleSizeForward", command: .sizing(.cycleSizeForward), category: .layout,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Period), modifiers: UInt32(optionKey)),
                visibility: .advanced
            ),
            action(
                id: "cycleSizeBackward", command: .sizing(.cycleSizeBackward), category: .layout,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_Comma), modifiers: UInt32(optionKey)),
                visibility: .advanced
            )
        ])
    }

    static func appendSplitStructureBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "balanceSizes",
                command: .sizing(.balanceSizes),
                category: .layout,
                binding: KeyBinding(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(optionKey | shiftKey))
            ),
            action(id: "moveToRoot", command: .dwindle(.moveToRoot), category: .layout, binding: .unassigned),
            action(id: "toggleSplit", command: .dwindle(.toggleSplit), category: .layout, binding: .unassigned),
            action(id: "swapSplit", command: .dwindle(.swapSplit), category: .layout, binding: .unassigned)
        ])
    }
}
