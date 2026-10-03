// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import OmniWMIPC

enum FocusNavigationAction: Equatable, Hashable {
    case previous
    case windowDownOrTop
    case windowUpOrBottom
}

extension FocusNavigationAction {
    func actionDisplayName() -> LocalizedStringResource {
        switch self {
        case .previous: LocalizedStringResource(
                "command.focus.previous", defaultValue: "Focus Previous Window", table: "Commands", bundle: .omniWM
            )
        case
            .windowDownOrTop,
            .windowUpOrBottom:
            windowTitle()
        }
    }

    private func windowTitle() -> LocalizedStringResource {
        switch self {
        case .windowDownOrTop: LocalizedStringResource(
                "command.focus.windowDownOrTop", defaultValue: "Focus Down or Top", table: "Commands", bundle: .omniWM
            )
        case .windowUpOrBottom: LocalizedStringResource(
                "command.focus.windowUpOrBottom", defaultValue: "Focus Up or Bottom", table: "Commands", bundle: .omniWM
            )
        case .previous:
            actionDisplayName()
        }
    }

    func ipcCommandName() -> IPCCommandName? {
        switch self {
        case .previous:
            .focus(.previous)
        case .windowDownOrTop:
            .focus(.windowDownOrTop)
        case .windowUpOrBottom:
            .focus(.windowUpOrBottom)
        }
    }

    var compatibility: LayoutCompatibility {
        switch self {
        case .previous,
             .windowDownOrTop,
             .windowUpOrBottom:
            .shared
        }
    }
}
