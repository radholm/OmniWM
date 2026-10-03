// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

struct StructuralMutation: Equatable {
    let sourceWorkspaceId: WorkspaceDescriptor.ID
    let destinationWorkspaceId: WorkspaceDescriptor.ID
    let selectedHandle: WindowHandle
    let movedTokens: [WindowToken]

    var affectedWorkspaceIds: Set<WorkspaceDescriptor.ID> {
        [sourceWorkspaceId, destinationWorkspaceId]
    }
}

enum StructuralMutationOutcome: Equatable {
    case changed(StructuralMutation)
    case atWorkspaceEdge
    case unchanged

    var mutation: StructuralMutation? {
        guard case let .changed(mutation) = self else { return nil }
        return mutation
    }

    var didMutate: Bool {
        mutation != nil
    }
}
