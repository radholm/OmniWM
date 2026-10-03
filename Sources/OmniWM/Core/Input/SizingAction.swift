// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import OmniWMIPC

enum SizingAction: Equatable, Hashable {
    case cycleSizeForward
    case cycleSizeBackward
    case balanceSizes
}

extension SizingAction {
    func actionDisplayName() -> LocalizedStringResource {
        switch self {
        case .cycleSizeForward: LocalizedStringResource(
                "command.sizing.cycleForward", defaultValue: "Cycle Size Forward", table: "Commands", bundle: .omniWM
            )
        case .cycleSizeBackward: LocalizedStringResource(
                "command.sizing.cycleBackward", defaultValue: "Cycle Size Backward", table: "Commands", bundle: .omniWM
            )
        case .balanceSizes: LocalizedStringResource(
                "command.sizing.balance", defaultValue: "Balance Sizes", table: "Commands", bundle: .omniWM
            )
        }
    }

    func ipcCommandName() -> IPCCommandName? {
        switch self {
        case .cycleSizeForward:
            .dwindle(.cycleSizeForward)
        case .cycleSizeBackward:
            .dwindle(.cycleSizeBackward)
        case .balanceSizes:
            .dwindle(.balanceSizes)
        }
    }

    var compatibility: LayoutCompatibility {
        switch self {
        case
            .balanceSizes,
            .cycleSizeForward,
            .cycleSizeBackward:
            .shared
        }
    }
}
