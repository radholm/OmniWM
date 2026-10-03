// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

extension WMController {
    @discardableResult
    func resolveAndSetWorkspaceFocusToken(for workspaceId: WorkspaceDescriptor.ID) -> WindowToken? {
        workspaceManager.resolveAndSetWorkspaceFocusToken(
            in: workspaceId,
            onMonitor: workspaceManager.monitorId(for: workspaceId)
        )
    }

    func reassignManagedWindow(
        _ token: WindowToken,
        to workspaceId: WorkspaceDescriptor.ID
    ) {
        workspaceManager.setWorkspace(for: token, to: workspaceId)
    }

    func recoverSourceFocusAfterMove(
        in workspaceId: WorkspaceDescriptor.ID,
        preferredToken: WindowToken? = nil
    ) {
        let monitorId = workspaceManager.monitorId(for: workspaceId)

        switch workspaceManager.activeLayoutKind(for: workspaceId) {
        case .dwindle:
            if let token = dwindleEngine?.selectedNode(in: workspaceId)?.windowToken,
               !isManagedWindowSuppressedByMacOS(token)
            {
                _ = workspaceManager.rememberFocus(token, in: workspaceId)
                return
            }
            if let preferredToken,
               !isManagedWindowSuppressedByMacOS(preferredToken),
               dwindleEngine?.findNode(for: preferredToken, in: workspaceId) != nil
            {
                commitWorkspaceFocusCandidate(preferredToken, in: workspaceId)
                return
            }
        }

        _ = workspaceManager.resolveAndSetWorkspaceFocusToken(in: workspaceId, onMonitor: monitorId)
    }

    @discardableResult
    private func commitWorkspaceFocusCandidate(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        focusDwindleCandidate: Bool = false
    ) -> Bool {
        switch workspaceManager.activeLayoutKind(for: workspaceId) {
        case .dwindle:
            if let engine = dwindleEngine,
               engine.findNode(for: token, in: workspaceId) != nil
            {
                _ = workspaceManager.rememberFocus(token, in: workspaceId)
                let activation = dwindleLayoutHandler.activateWindow(
                    token,
                    in: workspaceId,
                    focusAfterLayout: focusDwindleCandidate
                )
                return focusDwindleCandidate && activation != .missing
            }
        }

        _ = workspaceManager.applySessionPatch(
            .init(
                workspaceId: workspaceId,
                rememberedFocusToken: token,
                plannedSeq: workspaceManager.worldSeq
            )
        )
        return false
    }

    func ensureFocusedTokenValid(
        in workspaceId: WorkspaceDescriptor.ID,
        preferredRecoveryToken: WindowToken? = nil
    ) {
        guard !shouldSuppressManagedFocusRecovery else { return }
        guard !workspaceManager.hasPendingNativeFullscreenTransition(in: workspaceId) else { return }

        if let pendingFocusedToken = workspaceManager.pendingFocusedToken,
           workspaceManager.pendingFocusedWorkspaceId == workspaceId,
           !isManagedWindowSuppressedByMacOS(pendingFocusedToken)
        {
            commitWorkspaceFocusCandidate(pendingFocusedToken, in: workspaceId)
            return
        }

        if let preferredRecoveryToken {
            if let entry = workspaceManager.entry(for: preferredRecoveryToken),
               entry.workspaceId == workspaceId,
               !isManagedWindowSuppressedByMacOS(preferredRecoveryToken)
            {
                let routedDwindleFocus = commitWorkspaceFocusCandidate(
                    preferredRecoveryToken,
                    in: workspaceId,
                    focusDwindleCandidate: true
                )
                if !routedDwindleFocus {
                    focusWindow(preferredRecoveryToken)
                }
                return
            }
        }

        if let focusedToken = workspaceManager.selectedManagedToken,
           workspaceManager.entry(for: focusedToken)?.workspaceId == workspaceId,
           !isManagedWindowSuppressedByMacOS(focusedToken)
        {
            commitWorkspaceFocusCandidate(focusedToken, in: workspaceId)
            return
        }

        guard let nextFocusToken = workspaceManager.resolveAndSetWorkspaceFocusToken(
            in: workspaceId,
            onMonitor: workspaceManager.monitorId(for: workspaceId)
        ) else {
            return
        }

        let routedDwindleFocus = commitWorkspaceFocusCandidate(
            nextFocusToken,
            in: workspaceId,
            focusDwindleCandidate: true
        )
        if !routedDwindleFocus {
            focusWindow(nextFocusToken)
        }
    }
}
