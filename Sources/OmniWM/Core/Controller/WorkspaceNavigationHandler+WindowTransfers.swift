// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

extension WorkspaceNavigationHandler {
    struct WindowTransferResult {
        let succeeded: Bool
        let newSourceFocusToken: WindowToken?
    }

    @discardableResult
    func moveFocusedWindow(toWorkspaceSlot slot: Int) -> Bool {
        guard let controller,
              let token = controller.workspaceManager.selectedManagedToken,
              let targetWorkspace = workspaceSlot(slot),
              controller.workspaceManager.workspace(for: token) != targetWorkspace.id
        else { return false }
        if case .changed = commitWindowMove(handle: WindowHandle(id: token), toWorkspaceId: targetWorkspace.id) {
            return true
        }
        return false
    }

    private func transferWindowFromSourceEngine(
        token: WindowToken,
        from sourceWsId: WorkspaceDescriptor.ID?,
        to targetWsId: WorkspaceDescriptor.ID
    ) -> WindowTransferResult {
        guard let controller else { return WindowTransferResult(succeeded: false, newSourceFocusToken: nil) }
        let transfer = WindowEngineTransfer(
            token: token,
            sourceWorkspaceId: sourceWsId,
            targetWorkspaceId: targetWsId,
            controller: controller
        )
        var progress = WindowEngineTransferProgress()
        if controller.workspaceManager.windowMode(for: token) == .floating {
            controller.reassignManagedWindow(token, to: targetWsId)
            if let sourceWsId {
                recordLayoutOperation(.windowMovedToWorkspace(token: token, to: targetWsId), in: sourceWsId)
            }
            return WindowTransferResult(succeeded: true, newSourceFocusToken: nil)
        }
        detachTransferredWindow(transfer, controller: controller, progress: &progress)
        let succeeded = sourceWsId == nil || transfer.sourceIsDwindle || transfer.targetIsDwindle
        if succeeded {
            controller.reassignManagedWindow(token, to: targetWsId)
            if let sourceWsId {
                recordLayoutOperation(.windowMovedToWorkspace(token: token, to: targetWsId), in: sourceWsId)
            }
        }

        return WindowTransferResult(succeeded: succeeded, newSourceFocusToken: progress.newSourceFocusToken)
    }

    func moveWindowToAdjacentWorkspace(direction: Direction) {
        guard let controller else { return }
        guard let token = controller.workspaceManager.selectedManagedToken else { return }
        guard case let .changed(mutation) = moveWindowToAdjacentWorkspace(
            handle: WindowHandle(id: token),
            direction: direction
        ) else { return }

        finishWorkspaceMove(mutation)
    }

    func moveFocusedWindow(toWorkspaceIndex index: Int) {
        guard let rawWorkspaceID = WorkspaceIDPolicy.rawID(from: max(0, index) + 1) else { return }
        moveFocusedWindow(toRawWorkspaceID: rawWorkspaceID)
    }

    func moveFocusedWindow(toRawWorkspaceID rawWorkspaceID: String) {
        guard let controller,
              let token = controller.workspaceManager.selectedManagedToken,
              let targetWorkspaceId = controller.workspaceManager.workspaceId(
                  for: rawWorkspaceID,
                  createIfMissing: false
              )
        else { return }
        commitWindowMove(handle: WindowHandle(id: token), toWorkspaceId: targetWorkspaceId)
    }

    @discardableResult
    func commitWindowMove(
        handle: WindowHandle,
        toWorkspaceId targetWorkspaceId: WorkspaceDescriptor.ID
    ) -> StructuralMutationOutcome {
        let outcome = moveWindow(handle: handle, toWorkspaceId: targetWorkspaceId)
        if case let .changed(mutation) = outcome, let controller {
            let movesSelection = controller.workspaceManager.selectedManagedToken == handle.id
            finishWorkspaceMove(mutation, focusPolicy: movesSelection ? .configured : .retainCurrent)
        }
        return outcome
    }

    @discardableResult
    func moveWindow(
        handle: WindowHandle,
        toWorkspaceId targetWsId: WorkspaceDescriptor.ID
    ) -> StructuralMutationOutcome {
        guard let controller,
              controller.workspaceManager.descriptor(for: targetWsId) != nil,
              controller.workspaceManager.monitorForWorkspace(targetWsId) != nil,
              !controller.workspaceManager.isWindowSuppressedByMacOS(handle.id)
        else {
            return .unchanged
        }
        let token = handle.id

        guard let currentWorkspaceId = controller.workspaceManager.workspace(for: token),
              currentWorkspaceId != targetWsId
        else {
            return .unchanged
        }
        let transferResult = transferWindowFromSourceEngine(
            token: token,
            from: currentWorkspaceId,
            to: targetWsId
        )
        guard transferResult.succeeded else { return .unchanged }

        _ = controller.workspaceManager.rememberFocus(token, in: targetWsId)

        recoverSourceFocus(after: transferResult, from: currentWorkspaceId)

        return .changed(
            StructuralMutation(
                sourceWorkspaceId: currentWorkspaceId,
                destinationWorkspaceId: targetWsId,
                selectedHandle: handle,
                movedTokens: [token]
            )
        )
    }

    func moveWindow(
        handle: WindowHandle,
        toWorkspaceIndex index: Int
    ) -> StructuralMutationOutcome {
        guard let controller,
              let rawWorkspaceId = WorkspaceIDPolicy.rawID(from: max(0, index) + 1),
              let targetWorkspaceId = controller.workspaceManager.workspaceId(
                  for: rawWorkspaceId,
                  createIfMissing: false
              )
        else {
            return .unchanged
        }
        return moveWindow(handle: handle, toWorkspaceId: targetWorkspaceId)
    }

    func moveWindowToAdjacentWorkspace(
        handle: WindowHandle,
        direction: Direction
    ) -> StructuralMutationOutcome {
        guard direction == .up || direction == .down,
              let controller,
              let sourceWorkspaceId = controller.workspaceManager.workspace(for: handle.id),
              canTransferWindow(handle, from: sourceWorkspaceId),
              let sourceMonitorId = controller.workspaceManager.monitorId(for: sourceWorkspaceId),
              let targetWorkspace = resolveOrCreateAdjacentWorkspace(
                  from: sourceWorkspaceId,
                  direction: direction,
                  on: sourceMonitorId
              )
        else {
            return .unchanged
        }
        return moveWindow(handle: handle, toWorkspaceId: targetWorkspace.id)
    }

    private func canTransferWindow(
        _ handle: WindowHandle,
        from workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard let controller else { return false }
        if controller.workspaceManager.windowMode(for: handle.id) == .floating {
            return true
        }
        switch controller.workspaceManager.activeLayoutKind(for: workspaceId) {
        case .dwindle:
            return controller.dwindleEngine?.findNode(for: handle.id, in: workspaceId) != nil
        }
    }

    private func detachTransferredWindow(
        _ transfer: WindowEngineTransfer,
        controller: WMController,
        progress: inout WindowEngineTransferProgress
    ) {
        let token = transfer.token
        let sourceWsId = transfer.sourceWorkspaceId
        let sourceIsDwindle = transfer.sourceIsDwindle
        if sourceIsDwindle,
           let sourceWsId,
           let dwindleEngine = controller.dwindleEngine
        {
            progress.newSourceFocusToken = controller.workspaceManager.withEngineMutationScope(in: sourceWsId) {
                dwindleEngine.removeWindow(token: token, from: sourceWsId)
                return dwindleEngine.selectedNode(in: sourceWsId)?.windowToken
            }
        }
    }
}
