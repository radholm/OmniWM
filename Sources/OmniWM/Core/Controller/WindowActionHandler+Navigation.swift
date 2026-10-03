// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension WindowActionHandler {
    @discardableResult
    func navigateToWindowInternal(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        affectedWorkspaces: Set<WorkspaceDescriptor.ID> = [],
        focusOrigin: ManagedFocusOrigin = .keyboardOrProgrammatic
    ) -> Bool {
        guard let controller,
              let handle = prepareWindowNavigation(token: token, workspaceId: workspaceId)
        else {
            return false
        }
        commitWindowNavigation(
            handle: handle, workspaceId: workspaceId,
            affectedWorkspaces: affectedWorkspaces, focusOrigin: focusOrigin, controller: controller
        )
        return true
    }

    func prepareOverviewSelection(handle: WindowHandle, workspaceId: WorkspaceDescriptor.ID) {
        guard let controller else { return }
        let workspaceManager = controller.workspaceManager
        guard workspaceManager.entry(for: handle)?.layoutReason == .standard else { return }
        let previousWorkspaceId = workspaceManager.monitorForWorkspace(workspaceId)
            .flatMap { workspaceManager.activeWorkspace(on: $0.id)?.id }
        guard prepareWindowNavigation(token: handle.id, workspaceId: workspaceId, settlesMotion: true) != nil else {
            return
        }
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .overviewMutation,
            affectedWorkspaceIds: Set([previousWorkspaceId, workspaceId].compactMap { $0 })
        )
    }

    private func prepareWindowNavigation(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        settlesMotion: Bool = false
    ) -> WindowHandle? {
        guard let controller,
              let handle = controller.workspaceManager.handle(for: token),
              let entry = controller.workspaceManager.entry(for: token),
              entry.workspaceId == workspaceId,
              !controller.workspaceManager.isWindowSuppressedByMacOS(entry.token)
        else {
            return nil
        }
        let targetLayoutKind = controller.workspaceManager.activeLayoutKind(for: workspaceId)

        let currentWsId = controller.activeWorkspace()?.id

        if workspaceId != currentWsId {
            let wsName = controller.workspaceManager.descriptor(for: workspaceId)?.name ?? ""
            if let result = controller.workspaceManager.focusWorkspace(named: wsName) {
                _ = controller.workspaceManager.setInteractionMonitor(result.monitor.id)
            }
        }

        switch targetLayoutKind {
        case .dwindle:
            if !prepareDwindleNavigationTarget(token, workspaceId: workspaceId) {
                _ = controller.workspaceManager.applySessionPatch(
                    .init(
                        workspaceId: workspaceId,
                        rememberedFocusToken: token,
                        plannedSeq: controller.workspaceManager.worldSeq
                    )
                )
            }
        }
        return handle
    }

    private func commitWindowNavigation(
        handle: WindowHandle,
        workspaceId: WorkspaceDescriptor.ID,
        affectedWorkspaces: Set<WorkspaceDescriptor.ID>,
        focusOrigin: ManagedFocusOrigin,
        controller: WMController
    ) {
        let newestFocusIntentId = controller.intentLedger.newestFocusIntentId()
        let focusTarget: LayoutRefreshController.PostLayoutAction = { [weak controller] in
            guard let controller,
                  controller.activeWorkspace()?.id == workspaceId,
                  controller.workspaceManager.handle(for: handle.id) === handle,
                  controller.workspaceManager.entry(for: handle)?.workspaceId == workspaceId
            else {
                return
            }
            controller.focusWindow(handle.id, origin: focusOrigin)
        }
        let focusTargetIfStillCurrent: LayoutRefreshController.PostLayoutAction = { [weak controller] in
            guard let controller,
                  controller.intentLedger.newestFocusIntentId() == newestFocusIntentId
            else {
                return
            }
            focusTarget()
        }
        controller.layoutRefreshController.commitWorkspaceTransition(
            affectedWorkspaces: affectedWorkspaces,
            reason: .workspaceTransition,
            postLayoutGateWorkspaceIds: [workspaceId],
            postLayout: focusTarget,
            postLayoutInvalidated: focusTargetIfStillCurrent
        )
    }

    func prepareDwindleNavigationTarget(
        _ token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard let controller,
              controller.workspaceManager.activeLayoutKind(for: workspaceId) == .dwindle,
              let entry = controller.workspaceManager.entry(for: token),
              entry.workspaceId == workspaceId,
              entry.mode == .tiling,
              entry.layoutReason == .standard,
              controller.dwindleEngine?.findNode(for: token, in: workspaceId) != nil
        else {
            return false
        }

        return controller.dwindleLayoutHandler.activateWindow(
            token,
            in: workspaceId,
            layoutRefresh: false,
            focusAfterLayout: false
        ) != .missing
    }
}
