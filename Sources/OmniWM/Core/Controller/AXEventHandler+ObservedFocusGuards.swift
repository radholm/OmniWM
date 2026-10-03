// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension AXEventHandler {
    private func isTiledInActiveLayout(_ entry: WindowState) -> Bool {
        guard let controller, entry.mode == .tiling else { return false }
        switch controller.workspaceManager.activeLayoutKind(for: entry.workspaceId) {
        case .dwindle:
            return controller.dwindleEngine?.containsWindow(entry.token, in: entry.workspaceId) == true
        }
    }

    private func shouldDeferSameAppActivationForCloseProbe(
        entry observedEntry: WindowState,
        requestDisposition: ActivationRequestDisposition,
        source: ActivationEventSource,
        origin: ActivationCallOrigin,
        observationGeneration: UInt64
    ) -> Bool {
        guard source == .focusedWindowChanged, origin == .external else { return false }
        guard case .unrelatedNoRequest = requestDisposition else { return false }
        guard let controller else { return false }
        guard !hasRecentMouseFocusIntent(for: observedEntry.token) else { return false }
        guard isTiledInActiveLayout(observedEntry) else { return false }

        guard let focusedToken = controller.workspaceManager.selectedManagedToken,
              focusedToken != observedEntry.token,
              focusedToken.pid == observedEntry.pid,
              let focusedEntry = controller.workspaceManager.entry(for: focusedToken),
              isTiledInActiveLayout(focusedEntry)
        else {
            return false
        }

        deferSameAppCloseProbe(
            focusedToken: focusedToken,
            focusedWorkspaceId: focusedEntry.workspaceId,
            observedToken: observedEntry.token,
            source: source,
            observationGeneration: observationGeneration
        )
        return true
    }

    func shouldSuppressObservedManagedActivation(
        entry observedEntry: WindowState,
        requestDisposition: ActivationRequestDisposition,
        source: ActivationEventSource,
        origin: ActivationCallOrigin,
        observationGeneration: UInt64
    ) -> Bool {
        if hasRecentMouseFocusIntent(for: observedEntry.token) {
            return false
        }

        if shouldDeferSameAppActivationForCloseProbe(
            entry: observedEntry,
            requestDisposition: requestDisposition,
            source: source,
            origin: origin,
            observationGeneration: observationGeneration
        ) {
            return true
        }

        if shouldSuppressObservedActivationDuringWindowCloseRecovery(
            observedToken: observedEntry.token,
            requestDisposition: requestDisposition
        ) {
            return true
        }
        return false
    }

    func finishMouseFocusIntent(_ token: WindowToken) {
        if let open = controller?.intentLedger.openSameAppCloseProbe(),
           open.payload.observedToken == token
        {
            cancelSameAppCloseProbe(reason: "mouse_focus_intent")
        }
    }
}
