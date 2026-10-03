// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

extension WorkspaceManager {
    typealias NativeFullscreenTransition = WorkspaceNativeFullscreenTransition
    typealias NativeFullscreenRecord = WorkspaceNativeFullscreenRecord

    func removeAnimationMotions<S: Sequence>(
        for workspaceIds: S
    ) where S.Element == WorkspaceDescriptor.ID {
        let activeWorkspaceIds = Set(workspaceIds)
        guard !activeWorkspaceIds.isEmpty else { return }
        onAnimationMotionsWillBeRemoved?(activeWorkspaceIds)
    }
}
