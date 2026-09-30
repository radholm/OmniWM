// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension WMController {
    /// Whether focus-follows-mouse should raise `token` when it focuses it.
    ///
    /// With floating windows kept on top, a tiled window is focused without raising only while a visible
    /// floating window overlaps it, so raising it cannot cover a floating window. Otherwise the regular
    /// raise-and-activate path is used: some apps (Chromium/WebView based ones such as Microsoft Teams)
    /// swallow the first click after a focus-only handoff, and raising also keeps a fullscreen tiled window
    /// in front of its siblings.
    func raisesOnMouseFocus(_ token: WindowToken) -> Bool {
        guard settings.focus.raiseOnMouseFocus else { return false }
        guard settings.focus.floatingWindowsAlwaysOnTop,
              let entry = workspaceManager.entry(for: token),
              entry.mode != .floating
        else { return true }
        return !isOverlappedByVisibleFloatingWindow(entry)
    }

    private func isOverlappedByVisibleFloatingWindow(_ entry: WindowState) -> Bool {
        let floating = workspaceManager.visibleWorkspaceIds()
            .flatMap { workspaceManager.entries(in: $0) }
            .filter {
                $0.mode == .floating && $0.token != entry.token
                    && !workspaceManager.isWindowSuppressedByMacOS($0.token)
                    && workspaceManager.hiddenState(for: $0.token) == nil
            }
        guard !floating.isEmpty else { return false }
        guard let frame = axManager.lastAppliedFrame(for: entry.windowId)
            ?? AXWindowService.framePreferFast(entry.axRef)
        else { return true }
        return floating.contains { other in
            guard let otherFrame = AXWindowService.framePreferFast(other.axRef)
                ?? axManager.lastAppliedFrame(for: other.windowId)
            else { return true }
            return otherFrame.intersects(frame)
        }
    }
}
