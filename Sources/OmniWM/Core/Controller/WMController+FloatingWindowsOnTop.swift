// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension WMController {
    /// Whether focus-follows-mouse should raise `token` when it focuses it.
    ///
    /// With floating windows kept on top, tiled windows are focused without raising: tiled windows never
    /// overlap each other, so raising one would only move it in front of the floating windows.
    func raisesOnMouseFocus(_ token: WindowToken) -> Bool {
        guard settings.focus.raiseOnMouseFocus else { return false }
        guard settings.focus.floatingWindowsAlwaysOnTop else { return true }
        return workspaceManager.entry(for: token)?.mode == .floating
    }
}
