// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension AXEventHandler {
    func holdWorkspaceIfEmptied(_ workspaceId: WorkspaceDescriptor.ID, departingPID: pid_t) {
        guard let controller,
              isWorkspaceActive(workspaceId),
              controller.workspaceManager.windowCount(in: workspaceId) == 0
        else { return }
        emptiedWorkspaceHold = EmptiedWorkspaceHold(
            workspaceId: workspaceId,
            departingPIDs: [departingPID],
            expiresAt: Date().addingTimeInterval(Self.emptiedWorkspaceHoldDuration)
        )
    }

    /// Keeps a workspace emptied by closing/quitting its last app from following
    /// macOS' activation of the next app onto another workspace.
    func shouldHoldEmptiedWorkspace(
        againstActivationOf pid: pid_t,
        targetWorkspaceId: WorkspaceDescriptor.ID,
        origin: ActivationCallOrigin
    ) -> Bool {
        guard origin == .external || origin == .appTerminationProbe,
              !hasRecentMouseFocusIntent(forPID: pid),
              let controller
        else { return false }
        armEmptiedWorkspaceHoldForTerminatingApps(controller)
        guard let hold = emptiedWorkspaceHold, !hold.departingPIDs.contains(pid) else { return false }
        guard hold.expiresAt > Date(),
              isWorkspaceActive(hold.workspaceId),
              controller.workspaceManager.entries(in: hold.workspaceId).allSatisfy(isDeparting)
        else {
            emptiedWorkspaceHold = nil
            return false
        }
        return hold.workspaceId != targetWorkspaceId
    }

    private func armEmptiedWorkspaceHoldForTerminatingApps(_ controller: WMController) {
        guard emptiedWorkspaceHold.map({ $0.expiresAt <= Date() }) ?? true,
              let monitorId = controller.workspaceManager.interactionMonitorId,
              let workspaceId = controller.workspaceManager.activeWorkspace(on: monitorId)?.id
        else { return }
        let entries = controller.workspaceManager.entries(in: workspaceId)
        guard let focusedPID = controller.workspaceManager.lastFocusedToken(in: workspaceId)?.pid,
              entries.contains(where: { $0.pid == focusedPID }),
              entries.allSatisfy({ !controller.workspaceManager.isAppHidden(pid: $0.pid) && isDeparting($0) })
        else { return }
        emptiedWorkspaceHold = EmptiedWorkspaceHold(
            workspaceId: workspaceId,
            departingPIDs: Set(entries.map(\.pid)),
            expiresAt: Date().addingTimeInterval(Self.emptiedWorkspaceHoldDuration)
        )
    }

    /// Quit/close activation of the next app can arrive before the destroy and
    /// termination are processed, so a window the window server no longer has counts too.
    private func isDeparting(_ entry: WindowState) -> Bool {
        applicationIsTerminatedProvider(entry.pid)
            || UInt32(exactly: entry.windowId).map { windowInfoProvider($0) == nil } ?? true
    }
}
