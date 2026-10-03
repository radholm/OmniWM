// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

extension SettingsStore {
    func updateGestureSettings(
        _ candidate: SettingsExport.Gestures
    ) -> TrackpadGestureConflict? {
        var disabledCandidate = gestures.export()
        disabledCandidate.workspaceSwipeEnabled = disabledCandidate.workspaceSwipeEnabled && candidate
            .workspaceSwipeEnabled
        disabledCandidate.overviewGestureEnabled =
            (disabledCandidate.overviewGestureEnabled ?? false) && (candidate.overviewGestureEnabled ?? false)
        disabledCandidate.windowMoveEnabled =
            (disabledCandidate.windowMoveEnabled ?? false) && (candidate.windowMoveEnabled ?? false)
        disabledCandidate.windowResizeEnabled =
            (disabledCandidate.windowResizeEnabled ?? false) && (candidate.windowResizeEnabled ?? false)
        if candidate != disabledCandidate,
           let conflict = GestureSettingsValidation.conflict(gestures: candidate)
        {
            return conflict
        }
        gestures.apply(candidate)
        return nil
    }

    func updateMonitorOrientation(
        _ orientation: Monitor.Orientation?,
        for monitor: Monitor
    ) {
        var overrides = self.monitors.orientationOverrides
        if let orientation {
            MonitorSettingsStore.update(
                MonitorOrientationSettings(monitorName: monitor.name, orientation: orientation),
                for: monitor,
                in: &overrides
            )
        } else {
            MonitorSettingsStore.remove(for: monitor, from: &overrides)
        }
        self.monitors.orientationOverrides = overrides
    }
}
