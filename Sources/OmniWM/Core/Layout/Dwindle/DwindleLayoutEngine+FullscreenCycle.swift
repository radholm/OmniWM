// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

extension DwindleLayoutEngine {
    struct FullscreenCycle: Equatable {
        let previous: WindowToken
        let next: WindowToken
    }

    /// Moves fullscreen from the workspace's fullscreen window to the next tiled window in layout order
    /// (wrapping around), so repeated presses page through every window as fullscreen. Leaving fullscreen
    /// restores the regular tiled layout. Returns `nil` when no window is fullscreen or no other window can
    /// take over.
    func cycleFullscreen(
        in workspaceId: WorkspaceDescriptor.ID,
        forward: Bool = true,
        canFocus: (WindowToken) -> Bool = { _ in true }
    ) -> FullscreenCycle? {
        assertSanctionedMutation()
        guard let state = existingState(for: workspaceId) else { return nil }
        let leaves = state.root.collectAllLeaves().compactMap { leaf -> (DwindleNode, DwindleTileMember)? in
            guard let tile = leaf.tile,
                  let member = visibleMember(in: tile, excluding: state.excludedTokens)
            else { return nil }
            return (leaf, member)
        }
        let selectedId = state.selectedNodeId
        guard let currentIndex = leaves.firstIndex(where: { $0.0.id == selectedId && $0.1.isFullscreen })
            ?? leaves.firstIndex(where: { $0.1.isFullscreen })
        else { return nil }
        let step = forward ? 1 : leaves.count - 1
        var index = (currentIndex + step) % leaves.count
        while index != currentIndex, !canFocus(leaves[index].1.token) {
            index = (index + step) % leaves.count
        }
        guard index != currentIndex else { return nil }

        let (currentLeaf, currentMember) = leaves[currentIndex]
        let (nextLeaf, nextMember) = leaves[index]
        currentLeaf.tile?.setFullscreen(false, for: currentMember.token)
        nextLeaf.tile?.setFullscreen(true, for: nextMember.token)
        setSelectedNode(nextLeaf, in: workspaceId)
        return FullscreenCycle(previous: currentMember.token, next: nextMember.token)
    }
}
