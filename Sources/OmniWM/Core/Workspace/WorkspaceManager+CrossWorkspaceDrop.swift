// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct CrossWorkspaceDropAssignment {
    let token: WindowToken
    let workspaceId: WorkspaceDescriptor.ID
}

extension WorkspaceManager {
    func withBatchedCrossWorkspaceDrop(
        into targetWorkspaceId: WorkspaceDescriptor.ID,
        _ apply: () -> [CrossWorkspaceDropAssignment]
    ) {
        commitWorldEvent(
            .userCommand(workspaceId: targetWorkspaceId, label: "cross_display_drop", source: .mouse),
            monitors: monitors,
            preMutate: {
                for assignment in apply() {
                    self.setWorkspace(for: assignment.token, to: assignment.workspaceId)
                }
            },
            resolvePlan: { plan, _, _ in plan }
        )
    }
}
