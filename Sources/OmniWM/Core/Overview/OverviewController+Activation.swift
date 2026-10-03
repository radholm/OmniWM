// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension OverviewController {
    func focusTargetWindow(_ handle: WindowHandle) {
        guard let workspaceId = activationWorkspaceId(for: handle) else { return }
        onActivateWindow?(handle, workspaceId)
    }

    func activateWorkspace(_ workspaceId: WorkspaceDescriptor.ID) {
        guard case .open = state, wmController != nil else { return }
        guard !hasActiveDragSession else { return }
        guard onActivateWorkspace?(workspaceId) == true else {
            dismiss(reason: .cancel, animated: true)
            return
        }
        dismiss(reason: .workspaceActivation, animated: true)
    }

    func createWorkspace(on monitorId: Monitor.ID) {
        guard case .open = state, !hasActiveDragSession,
              let workspace = wmController?.workspaceNavigationHandler.createOverviewWorkspace(on: monitorId)
        else { return }
        activateWorkspace(workspace.id)
    }

    func prepareActivation(_ handle: WindowHandle) {
        guard wmController != nil, let workspaceId = activationWorkspaceId(for: handle) else { return }
        onPrepareActivation?(handle, workspaceId)
    }

    func activationWorkspaceId(for handle: WindowHandle) -> WorkspaceDescriptor.ID? {
        guard let wmController,
              wmController.workspaceManager.handle(for: handle.id) === handle
        else { return nil }
        return wmController.workspaceManager.entry(for: handle)?.workspaceId
    }

    @discardableResult
    func closeWindow(_ handle: WindowHandle) -> Bool {
        guard case .open = state else { return false }
        return onCloseWindow?(handle) == true
    }
}
