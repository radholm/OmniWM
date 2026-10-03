// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import OmniWMIPC

enum WindowMovementAction: Equatable, Hashable {
    case down
    case up
}

extension WindowMovementAction {
    func actionDisplayName() -> LocalizedStringResource {
        switch self {
        case .down: LocalizedStringResource(
                "command.window.reorderDown", defaultValue: "Reorder Window Down", table: "Commands", bundle: .omniWM
            )
        case .up: LocalizedStringResource(
                "command.window.reorderUp", defaultValue: "Reorder Window Up", table: "Commands", bundle: .omniWM
            )
        }
    }

    func ipcCommandName() -> IPCCommandName? {
        switch self {
        case .down:
            .windowMovement(.down)
        case .up:
            .windowMovement(.up)
        }
    }

    var compatibility: LayoutCompatibility {
        switch self {
        case .down,
             .up:
            .shared
        }
    }
}
