// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension SettingsExport.Gestures {
    func normalized() -> Self {
        var normalized = self
        normalized.overviewGestureEnabled = overviewGestureEnabled ?? false
        normalized.overviewGestureFingerCount = overviewGestureFingerCount ?? .four
        normalized.windowMoveEnabled = windowMoveEnabled ?? false
        normalized.windowMoveFingerCount = windowMoveFingerCount ?? .four
        normalized.windowResizeEnabled = windowResizeEnabled ?? false
        normalized.windowResizeFingerCount = windowResizeFingerCount ?? .three
        normalized.windowGestureSensitivity = windowGestureSensitivity ?? 1.0
        normalized.workspaceSwipeSensitivity = workspaceSwipeSensitivity ?? 1.0
        return normalized
    }
}

extension SettingsExport.Dwindle {
    func normalized() -> Self {
        var dwindle = self
        dwindle.snapshotAnimations = snapshotAnimations ?? true
        return dwindle
    }
}

extension SettingsExport.Focus {
    func normalized() -> Self {
        var focus = self
        focus.floatingWindowsAlwaysOnTop = floatingWindowsAlwaysOnTop ?? false
        return focus
    }
}
