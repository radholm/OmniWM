// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension WorkspaceSwipePresentation {
    func trace(_ action: String, progress: Double = 0) {
        guard TrackpadScrollTrace.shared.isActive else { return }
        TrackpadScrollTrace.record(.workspacePresentation(
            renderer: "preview",
            action: action,
            progress: progress,
            velocity: flight?.motion.velocity(at: mediaTimeProvider()),
            target: flight?.motion.target
        ))
    }
}
