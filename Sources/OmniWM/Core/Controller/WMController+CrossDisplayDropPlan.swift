// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct CrossDisplayDragUnit: Equatable {
    let tokens: [WindowToken]
    let activeIndex: Int

    var activeToken: WindowToken {
        tokens[activeIndex]
    }

    var isGroup: Bool {
        tokens.count > 1
    }
}

struct CrossDisplayDropPlan {
    enum Operation: Equatable {
        case move(CrossDisplayDrop.Placement)
        case swap(partner: CrossDisplayDragUnit)
    }

    let drop: CrossDisplayDrop
    let sourceLayout: ActiveLayoutKind
    let targetLayout: ActiveLayoutKind
    let unit: CrossDisplayDragUnit
    let operation: Operation
}

extension WMController {
    func crossDisplayDropPlan(for drop: CrossDisplayDrop) -> CrossDisplayDropPlan? {
        let manager = workspaceManager
        guard drop.sourceWorkspaceId != drop.workspaceId,
              isCrossDisplayTransferable(drop.sourceToken, in: drop.sourceWorkspaceId),
              manager.monitor(for: drop.sourceWorkspaceId) != nil
        else {
            return nil
        }
        let unit = crossDisplayDragUnit(for: drop.sourceToken, in: drop.sourceWorkspaceId)

        let operation: CrossDisplayDropPlan.Operation
        if case let .swap(target) = drop.placement {
            guard isCrossDisplayTransferable(target, in: drop.workspaceId) else { return nil }
            let partner = crossDisplayDragUnit(for: target, in: drop.workspaceId)
            guard slotAccepts(unit, replacing: partner, in: drop.workspaceId),
                  slotAccepts(partner, replacing: unit, in: drop.sourceWorkspaceId)
            else {
                return nil
            }
            operation = .swap(partner: partner)
        } else {
            operation = .move(validatedCrossDisplayPlacement(drop))
        }
        return CrossDisplayDropPlan(
            drop: drop,
            sourceLayout: manager.activeLayoutKind(for: drop.sourceWorkspaceId),
            targetLayout: manager.activeLayoutKind(for: drop.workspaceId),
            unit: unit,
            operation: operation
        )
    }

    func crossDisplayDragUnit(for token: WindowToken, in workspaceId: WorkspaceDescriptor.ID) -> CrossDisplayDragUnit {
        guard settings.gestures.dwindleGroupDragAcrossDisplays == .group,
              workspaceManager.activeLayoutKind(for: workspaceId) == .dwindle,
              let tile = dwindleEngine?.tile(containing: token, in: workspaceId),
              tile.members.count > 1,
              let activeIndex = tile.memberIndex(for: token)
        else {
            return CrossDisplayDragUnit(tokens: [token], activeIndex: 0)
        }
        return CrossDisplayDragUnit(tokens: tile.members.map(\.token), activeIndex: activeIndex)
    }

    private func isCrossDisplayTransferable(_ token: WindowToken, in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let entry = workspaceManager.entry(for: token),
              entry.workspaceId == workspaceId,
              entry.mode == .tiling,
              !workspaceManager.isWindowSuppressedByMacOS(token)
        else {
            return false
        }
        guard let engine = dwindleEngine,
              engine.tile(containing: token, in: workspaceId) != nil else { return false }
        return !engine.isWindowFullscreen(token, in: workspaceId)
            && !engine.excludedTokens(in: workspaceId).contains(token)
    }

    private func slotAccepts(
        _ incoming: CrossDisplayDragUnit,
        replacing partner: CrossDisplayDragUnit,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard incoming.isGroup else { return true }
        return dwindleEngine?.tile(containing: partner.activeToken, in: workspaceId)?.members.count
            == partner.tokens.count
    }

    private func validatedCrossDisplayPlacement(_ drop: CrossDisplayDrop) -> CrossDisplayDrop.Placement {
        let workspaceId = drop.workspaceId
        switch drop.placement {
        case let .dwindleBeside(target, _):
            guard let engine = dwindleEngine,
                  engine.tile(containing: target, in: workspaceId) != nil,
                  !engine.isWindowFullscreen(target, in: workspaceId)
            else {
                return .workspace
            }
            return drop.placement
        case .dwindleEdge:
            return dwindleEngine?.visibleTiles(in: workspaceId).any == true ? drop.placement : .workspace
        case let .dwindleSplitBoundary(splitId):
            return dwindleEngine?.canAttachTransfer(atSplitBoundary: splitId, in: workspaceId) == true
                ? drop.placement
                : .workspace
        case .swap,
             .workspace:
            return drop.placement
        }
    }
}
