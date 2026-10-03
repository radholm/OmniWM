// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

extension WorkspaceNavigationHandler {
    func moveWindowToMonitor(direction: Direction) {
        moveFocusedWindowToMonitor(direction: direction, focusPolicy: .configured)
    }

    func moveWindowAcrossMonitorAtEdge(direction: Direction) {
        moveFocusedWindowToMonitor(direction: direction, focusPolicy: .alwaysFollow)
    }

    private func moveFocusedWindowToMonitor(
        direction: Direction,
        focusPolicy: WorkspaceMoveFocusPolicy
    ) {
        guard let controller else { return }
        guard let token = controller.workspaceManager.selectedManagedToken else { return }
        guard case let .changed(mutation) = moveWindowToMonitor(
            handle: WindowHandle(id: token),
            direction: direction
        ) else { return }
        finishWorkspaceMove(mutation, focusPolicy: focusPolicy)
    }

    func moveWindowToMonitor(
        handle: WindowHandle,
        direction: Direction
    ) -> StructuralMutationOutcome {
        guard let controller,
              let sourceWorkspaceId = controller.workspaceManager.workspace(for: handle.id),
              let sourceMonitorId = controller.workspaceManager.monitorId(for: sourceWorkspaceId),
              let targetMonitor = controller.workspaceManager.adjacentMonitor(
                  from: sourceMonitorId,
                  direction: direction
              ),
              let targetWorkspace = controller.workspaceManager.activeWorkspaceOrFirst(on: targetMonitor.id),
              targetWorkspace.id != sourceWorkspaceId
        else {
            return .unchanged
        }
        let outcome = moveWindow(handle: handle, toWorkspaceId: targetWorkspace.id)
        guard case let .changed(mutation) = outcome else { return outcome }

        return .changed(
            StructuralMutation(
                sourceWorkspaceId: mutation.sourceWorkspaceId,
                destinationWorkspaceId: mutation.destinationWorkspaceId,
                selectedHandle: mutation.selectedHandle,
                movedTokens: mutation.movedTokens
            )
        )
    }

    func swapCurrentWorkspaceWithMonitor(direction: Direction) {
        guard let controller else { return }
        guard let currentMonitorId = interactionMonitorId(for: controller)
        else { return }
        guard let currentWsId = controller.activeWorkspace()?.id else { return }

        guard let targetMonitor = controller.workspaceManager.adjacentMonitor(
            from: currentMonitorId,
            direction: direction
        ) else { return }

        guard let targetWsId = controller.workspaceManager.activeWorkspace(on: targetMonitor.id)?.id
        else { return }
        restoreRememberedSelection(in: targetWsId)

        guard controller.workspaceManager.swapWorkspaces(
            currentWsId, on: currentMonitorId,
            with: targetWsId, on: targetMonitor.id
        ) else { return }

        let focusToken = controller.resolveAndSetWorkspaceFocusToken(for: targetWsId)

        controller.layoutRefreshController.commitWorkspaceTransition(
            affectedWorkspaces: [currentWsId, targetWsId],
            reason: .workspaceTransition
        ) { [weak controller] in
            if let focusToken {
                controller?.focusWindow(focusToken)
            }
        }
    }

    func moveWorkspaceToMonitor(
        _ workspaceId: WorkspaceDescriptor.ID,
        direction: Direction,
        force: Bool
    ) -> WorkspaceMonitorMoveOutcome? {
        guard let controller,
              let sourceMonitor = controller.workspaceManager.monitorForWorkspace(workspaceId),
              let targetMonitor = controller.workspaceManager.adjacentMonitor(
                  from: sourceMonitor.id,
                  direction: direction
              )
        else {
            return nil
        }
        return moveWorkspaceToMonitor(workspaceId, to: targetMonitor.id, force: force)
    }

    func moveWorkspaceToMonitor(
        _ workspaceId: WorkspaceDescriptor.ID,
        to targetMonitorId: Monitor.ID,
        force: Bool
    ) -> WorkspaceMonitorMoveOutcome? {
        guard let controller else { return nil }
        let outcome = controller.workspaceManager.moveWorkspaceToMonitor(
            workspaceId,
            to: targetMonitorId,
            force: force
        )
        controller.layoutRefreshController.commitWorkspaceMonitorTransition(outcome)
        return outcome
    }

    func moveWindowToWorkspaceOnMonitor(
        handle: WindowHandle,
        workspaceIndex: Int,
        monitorDirection: Direction
    ) -> StructuralMutationOutcome {
        guard let rawWorkspaceId = WorkspaceIDPolicy.rawID(from: max(0, workspaceIndex) + 1) else {
            return .unchanged
        }
        return moveWindowToWorkspaceOnMonitor(
            handle: handle,
            rawWorkspaceId: rawWorkspaceId,
            monitorDirection: monitorDirection
        )
    }

    func moveWindowToWorkspaceOnMonitor(
        handle: WindowHandle,
        rawWorkspaceId: String,
        monitorDirection: Direction
    ) -> StructuralMutationOutcome {
        guard let controller,
              let sourceWorkspaceId = controller.workspaceManager.workspace(for: handle.id),
              let sourceMonitorId = controller.workspaceManager.monitorId(for: sourceWorkspaceId),
              let targetMonitor = controller.workspaceManager.adjacentMonitor(
                  from: sourceMonitorId,
                  direction: monitorDirection
              ),
              let targetWorkspaceId = controller.workspaceManager.workspaceId(
                  for: rawWorkspaceId,
                  createIfMissing: false
              ),
              controller.workspaceManager.monitorId(for: targetWorkspaceId) == targetMonitor.id
        else {
            return .unchanged
        }
        return moveWindow(handle: handle, toWorkspaceId: targetWorkspaceId)
    }

    func moveWindowToWorkspaceOnMonitor(rawWorkspaceID: String, monitorDirection: Direction) {
        guard let controller else { return }
        guard let token = controller.workspaceManager.selectedManagedToken else { return }
        guard case let .changed(mutation) = moveWindowToWorkspaceOnMonitor(
            handle: WindowHandle(id: token),
            rawWorkspaceId: rawWorkspaceID,
            monitorDirection: monitorDirection
        ) else { return }

        finishWorkspaceMove(mutation)
    }
}
