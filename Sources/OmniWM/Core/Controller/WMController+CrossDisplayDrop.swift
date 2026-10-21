// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension WMController {
    func performCrossDisplayDrop(_ drop: CrossDisplayDrop) {
        guard let plan = crossDisplayDropPlan(for: drop) else { return }
        let heldSelection = workspaceManager.selectedManagedToken.map(plan.unit.tokens.contains) == true
        workspaceManager.withBatchedCrossWorkspaceDrop(into: drop.workspaceId) {
            let arrivals = plan.unit.tokens
                .map { CrossWorkspaceDropAssignment(token: $0, workspaceId: drop.workspaceId) }
            switch plan.operation {
            case let .move(placement):
                applyCrossDisplayMove(plan, placement: placement)
                return arrivals
            case let .swap(partner):
                swapDwindleUnits(plan.unit, in: drop.sourceWorkspaceId, with: partner, in: drop.workspaceId)
                return arrivals + partner.tokens.map {
                    CrossWorkspaceDropAssignment(token: $0, workspaceId: drop.sourceWorkspaceId)
                }
            }
        }
        finishCrossDisplayDrop(plan, heldSelection: heldSelection)
    }

    private func applyCrossDisplayMove(_ plan: CrossDisplayDropPlan, placement: CrossDisplayDrop.Placement) {
        guard let engine = dwindleEngine,
              let tile = engine.detachForTransfer(
                  token: plan.unit.activeToken,
                  wholeTile: plan.unit.isGroup,
                  from: plan.drop.sourceWorkspaceId
              )
        else { return }
        engine.attachTransferredTile(
            tile,
            placement: Self.dwindleTransferPlacement(placement),
            in: plan.drop.workspaceId
        )
    }

    private func swapDwindleUnits(
        _ unit: CrossDisplayDragUnit,
        in source: WorkspaceDescriptor.ID,
        with partner: CrossDisplayDragUnit,
        in target: WorkspaceDescriptor.ID
    ) {
        guard let dwindle = dwindleEngine,
              let incoming = dwindle.transferTile(containing: unit.activeToken, wholeTile: unit.isGroup, in: source),
              let outgoing = dwindle.replaceSlot(
                  of: partner.activeToken,
                  wholeTile: partner.isGroup,
                  with: incoming,
                  in: target
              )
        else { return }
        _ = dwindle.replaceSlot(of: unit.activeToken, wholeTile: unit.isGroup, with: outgoing, in: source)
    }

    private func finishCrossDisplayDrop(_ plan: CrossDisplayDropPlan, heldSelection: Bool) {
        let drop = plan.drop
        let source = drop.sourceWorkspaceId
        let target = drop.workspaceId
        let token = plan.unit.activeToken
        switch plan.operation {
        case .move:
            workspaceManager.recordLayoutOperation(
                .windowMovedToWorkspace(token: token, to: target), in: source, source: .mouse
            )
            workspaceManager.recordLayoutOperation(.windowInserted(token: token), in: target, source: .mouse)
            recoverSourceFocusAfterMove(in: source)
        case let .swap(partner):
            workspaceManager.recordLayoutOperation(.windowsSwapped, in: source, source: .mouse)
            workspaceManager.recordLayoutOperation(.windowsSwapped, in: target, source: .mouse)
            recoverSourceFocusAfterMove(in: source, preferredToken: partner.activeToken)
        }
        workspaceNavigationHandler.applySessionPatch(workspaceId: target, rememberedFocusToken: token)
        guard let handle = workspaceManager.handle(for: token) else { return }
        let mutation = StructuralMutation(
            sourceWorkspaceId: source,
            destinationWorkspaceId: target,
            selectedHandle: handle,
            movedTokens: plan.unit.tokens
        )
        let follows = heldSelection || settings.focus.followsWindowToMonitor
        workspaceNavigationHandler.finishWorkspaceMove(
            mutation,
            focusPolicy: follows ? .configured : .retainCurrent,
            focusOrigin: .pointerSelection
        )
    }

    private static func dwindleTransferPlacement(_ placement: CrossDisplayDrop.Placement) -> DwindleTransferPlacement {
        switch placement {
        case let .dwindleBeside(target, direction):
            .beside(target, direction)
        case let .dwindleEdge(direction):
            .workspaceEdge(direction)
        case let .dwindleSplitBoundary(splitId):
            .splitBoundary(splitId)
        case .swap,
             .workspace:
            .defaultPlacement
        }
    }
}
