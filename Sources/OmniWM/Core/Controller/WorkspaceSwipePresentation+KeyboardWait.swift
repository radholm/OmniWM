// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension WorkspaceSwipePresentation {
    /// Starts a keyboard flight once every window has a fresh frame, so the slide doesn't show windows as they
    /// looked when last captured. When captures are slow, slides with the cached previews (they update live as
    /// frames arrive); without any previews, runs `fallback` (an unanimated switch).
    func waitForKeyboardPreviews(isNext: Bool, fallback: @escaping () -> Void) {
        keyboardSwitchFallback = fallback
        keyboardSwitchTask = Task { @MainActor [weak self] in
            let deadline = ContinuousClock.now + Self.keyboardPreviewWait
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(8))
                guard !Task.isCancelled, let self else { return }
                if beginKeyboardFlight(isNext: isNext, requireFresh: true) {
                    keyboardSwitchTask = nil
                    keyboardSwitchFallback = nil
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            if beginKeyboardFlight(isNext: isNext, requireFresh: false) {
                keyboardSwitchTask = nil
                keyboardSwitchFallback = nil
                return
            }
            flushPendingKeyboardSwitch()
        }
    }
}
