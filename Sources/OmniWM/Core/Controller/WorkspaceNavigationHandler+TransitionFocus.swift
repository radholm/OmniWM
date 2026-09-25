// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

extension WorkspaceNavigationHandler {
    private struct WorkspaceTransitionFocusHandoff {
        let focusToken: WindowToken?
        let shouldClearManagedFocus: Bool
    }

    private func resolveWorkspaceTransitionFocusHandoff(
        for workspaceId: WorkspaceDescriptor.ID
    ) -> WorkspaceTransitionFocusHandoff {
        guard let controller else {
            return WorkspaceTransitionFocusHandoff(
                focusToken: nil,
                shouldClearManagedFocus: false
            )
        }
        let focusToken = controller.resolveAndSetWorkspaceFocusToken(for: workspaceId)
        let shouldClearManagedFocus = focusToken == nil && controller.workspaceManager.entries(in: workspaceId).isEmpty
        return WorkspaceTransitionFocusHandoff(
            focusToken: focusToken,
            shouldClearManagedFocus: shouldClearManagedFocus
        )
    }

    func clearManagedFocusAfterEmptyWorkspaceSwitch() {
        guard let controller else { return }
        let canceledRequest = controller.intentLedger.cancelManagedRequest()
        if let canceledRequest {
            _ = controller.workspaceManager.cancelManagedFocusRequest(
                matching: canceledRequest.token,
                workspaceId: canceledRequest.workspaceId,
                requestId: canceledRequest.requestId
            )
            controller.scratchpadStacking.abortScratchpadStacking(matching: canceledRequest.requestId)
            controller.intentLedger.discardPendingFocus(canceledRequest.token)
        }
        _ = controller.workspaceManager.clearNativeFocusOwner()
        controller.windowFocusOperations.activateApp(getpid())
    }

    func commitWorkspaceTransitionFocusHandoff(
        targetWorkspaceId: WorkspaceDescriptor.ID,
        monitor: Monitor?,
        startScrollAnimation: Bool,
        affectedWorkspaces: Set<WorkspaceDescriptor.ID> = [],
        placementSubmitted: LayoutRefreshController.PostLayoutAction? = nil,
        placementInvalidated: LayoutRefreshController.PostLayoutAction? = nil
    ) {
        guard let controller else { return }
        let handoff = resolveWorkspaceTransitionFocusHandoff(for: targetWorkspaceId)
        if let monitor {
            controller.layoutRefreshController.stopScrollAnimation(for: monitor.displayId)
        }
        let newestFocusIntentId = controller.intentLedger.newestFocusIntentId()
        let focusEpochSeq = controller.workspaceManager.worldSeq
        let handoffAction: LayoutRefreshController.PostLayoutAction = { [weak self, weak controller] in
            guard let controller else { return }
            // A newer switch may have replaced the target before this placement finished; focusing
            // its window then would pull the user back to the workspace they just left.
            guard Self.isWorkspaceActive(targetWorkspaceId, controller: controller) else { return }
            if let focusToken = handoff.focusToken {
                self?.focusAfterRevealWrites(focusToken, workspaceId: targetWorkspaceId)
            } else if handoff.shouldClearManagedFocus {
                self?.clearManagedFocusAfterEmptyWorkspaceSwitch()
            }
            if startScrollAnimation {
                controller.layoutRefreshController.startScrollAnimation(for: targetWorkspaceId)
            }
        }
        controller.layoutRefreshController.commitWorkspaceTransition(
            affectedWorkspaces: affectedWorkspaces,
            reason: .workspaceTransition,
            postLayout: {
                handoffAction()
                placementSubmitted?()
            },
            postLayoutInvalidated: { [weak controller] in
                placementInvalidated?()
                guard let controller,
                      controller.intentLedger.newestFocusIntentId() == newestFocusIntentId,
                      controller.workspaceManager.isSeqEpochCurrent(focusEpochSeq, domains: .focus)
                else { return }
                handoffAction()
            }
        )
    }

    private static let revealWriteFocusTimeout: Duration = .milliseconds(250)
    private static let revealWritePollInterval: Duration = .milliseconds(4)

    private static func isWorkspaceActive(
        _ workspaceId: WorkspaceDescriptor.ID,
        controller: WMController
    ) -> Bool {
        guard let monitorId = controller.workspaceManager.monitorId(for: workspaceId) else { return false }
        return controller.workspaceManager.activeWorkspace(on: monitorId)?.id == workspaceId
    }

    /// Activating an app while its revealed windows are still being moved lets accessibility clients
    /// re-enable `AXEnhancedUserInterface` mid-write, which makes AppKit animate the window in from its
    /// park position. Wait (bounded) for the app's reveal writes to land before focusing it.
    private func focusAfterRevealWrites(
        _ token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        deadline: ContinuousClock.Instant? = nil
    ) {
        guard let controller else { return }
        let deadline = deadline ?? ContinuousClock.now.advanced(by: Self.revealWriteFocusTimeout)
        let hasPendingRevealWrite = controller.workspaceManager.entries(in: workspaceId).contains {
            $0.pid == token.pid && controller.axManager.hasPendingFrameWrite(for: $0.windowId)
        }
        guard hasPendingRevealWrite, ContinuousClock.now < deadline else {
            controller.focusWindow(token)
            return
        }
        let newestFocusIntentId = controller.intentLedger.newestFocusIntentId()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.revealWritePollInterval)
            guard let self, let controller = self.controller,
                  Self.isWorkspaceActive(workspaceId, controller: controller),
                  controller.intentLedger.newestFocusIntentId() == newestFocusIntentId
            else { return }
            self.focusAfterRevealWrites(token, workspaceId: workspaceId, deadline: deadline)
        }
    }
}
