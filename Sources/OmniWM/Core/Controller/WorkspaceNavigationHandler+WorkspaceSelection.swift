// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

extension WorkspaceNavigationHandler {
    func switchWorkspace(index: Int) {
        guard let rawWorkspaceID = WorkspaceIDPolicy.rawID(from: max(0, index) + 1) else { return }
        if cycleFullscreenInCurrentWorkspace(rawWorkspaceID: rawWorkspaceID) { return }
        if animateSwitchWorkspace(rawWorkspaceID: rawWorkspaceID) { return }
        switchWorkspace(rawWorkspaceID: rawWorkspaceID)
    }

    /// Pressing the shortcut of the workspace already shown pages to its next window while one is fullscreen.
    private func cycleFullscreenInCurrentWorkspace(rawWorkspaceID: String) -> Bool {
        guard let controller,
              let currentWorkspace = controller.activeWorkspace(),
              currentWorkspace.name == rawWorkspaceID,
              controller.settings.workspaces.layoutType(for: currentWorkspace.name) == .dwindle
        else { return false }
        return controller.dwindleLayoutHandler.cycleFullscreen()
    }

    /// Slides to the workspace with the swipe presentation; the switch commits when the animation ends.
    private func animateSwitchWorkspace(rawWorkspaceID: String) -> Bool {
        guard let controller,
              let currentWorkspace = controller.activeWorkspace(),
              let targetWorkspaceId = controller.workspaceManager.workspaceId(
                  for: rawWorkspaceID,
                  createIfMissing: false
              ),
              controller.workspaceManager.monitorForWorkspace(targetWorkspaceId)?.id
              == controller.workspaceManager.monitorForWorkspace(currentWorkspace.id)?.id
        else { return false }
        return controller.layoutRefreshController.workspaceSwipe.animateSwitch(to: targetWorkspaceId) { [weak self] in
            self?.switchWorkspace(rawWorkspaceID: rawWorkspaceID)
        }
    }

    func canSkipSwitch(toVisibleWorkspace workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let controller else { return true }
        let nativeFocusWorkspaceId = controller.workspaceManager.nativeManagedFocusToken
            .flatMap { controller.workspaceManager.workspace(for: $0) }
        return nativeFocusWorkspaceId == nil || nativeFocusWorkspaceId == workspaceId
    }

    @discardableResult
    func switchWorkspace(
        rawWorkspaceID: String,
        affectedWorkspaces: Set<WorkspaceDescriptor.ID> = []
    ) -> Bool {
        guard let controller else { return false }
        let currentWorkspace = controller.activeWorkspace()
        if let currentWorkspace,
           currentWorkspace.name == rawWorkspaceID,
           canSkipSwitch(toVisibleWorkspace: currentWorkspace.id)
        {
            return false
        }

        guard let targetWorkspaceId = controller.workspaceManager.workspaceId(
            for: rawWorkspaceID,
            createIfMissing: false
        ),
            controller.workspaceManager.monitorForWorkspace(targetWorkspaceId) != nil
        else {
            return false
        }

        guard let result = controller.workspaceManager.focusWorkspace(named: rawWorkspaceID) else { return false }

        commitWorkspaceTransitionFocusHandoff(
            targetWorkspaceId: result.workspace.id,
            monitor: result.monitor,
            affectedWorkspaces: affectedWorkspaces
        )
        return true
    }

    func switchWorkspaceRelative(
        isNext: Bool,
        wrapAround: Bool = true,
        monitorId explicitMonitorId: Monitor.ID? = nil
    ) {
        guard let controller else { return }
        guard let currentMonitorId = explicitMonitorId ?? interactionMonitorId(for: controller)
        else { return }
        let resolvedWorkspace = explicitMonitorId == nil
            ? controller.activeWorkspace()
            : controller.workspaceManager.activeWorkspaceOrFirst(on: currentMonitorId)
        guard let currentWorkspace = resolvedWorkspace else { return }
        let skipEmpty = skipsEmptyWorkspaces(on: currentMonitorId)

        let targetWorkspace: WorkspaceDescriptor? = if isNext {
            controller.workspaceManager.nextWorkspaceInOrder(
                on: currentMonitorId,
                from: currentWorkspace.id,
                wrapAround: wrapAround,
                skipEmpty: skipEmpty
            )
        } else {
            controller.workspaceManager.previousWorkspaceInOrder(
                on: currentMonitorId,
                from: currentWorkspace.id,
                wrapAround: wrapAround,
                skipEmpty: skipEmpty
            )
        }

        guard let targetWorkspace else { return }
        activateWorkspaceInOrder(targetWorkspace, from: currentWorkspace.id, on: currentMonitorId)
    }

    func skipsEmptyWorkspaces(on monitorId: Monitor.ID) -> Bool {
        guard let controller, let monitor = controller.workspaceManager.monitor(byId: monitorId) else {
            return false
        }
        return controller.settings.workspaceBar.resolved(for: monitor).hideEmptyWorkspaces
    }

    func workspaceSlot(_ slot: Int) -> WorkspaceDescriptor? {
        guard let controller, slot >= 1, let monitorId = interactionMonitorId(for: controller) else { return nil }
        let ordered = controller.workspaceManager.workspaces(on: monitorId)
        return ordered.indices.contains(slot - 1) ? ordered[slot - 1] : nil
    }

    @discardableResult
    func switchWorkspaceSlot(_ slot: Int) -> Bool {
        guard let controller,
              let monitorId = interactionMonitorId(for: controller),
              let targetWorkspace = workspaceSlot(slot),
              let currentWorkspace = controller.workspaceManager.activeWorkspaceOrFirst(on: monitorId)
        else { return false }
        if currentWorkspace.id == targetWorkspace.id, canSkipSwitch(toVisibleWorkspace: targetWorkspace.id) {
            return false
        }
        return activateWorkspaceInOrder(targetWorkspace, from: currentWorkspace.id, on: monitorId)
    }

    @discardableResult
    private func activateWorkspaceInOrder(
        _ targetWorkspace: WorkspaceDescriptor,
        from currentWorkspaceId: WorkspaceDescriptor.ID,
        on monitorId: Monitor.ID
    ) -> Bool {
        guard let controller else { return false }
        guard controller.workspaceManager.setActiveWorkspace(targetWorkspace.id, on: monitorId) else {
            return false
        }

        let monitor = controller.workspaceManager.monitor(for: targetWorkspace.id)
            ?? controller.workspaceManager.monitor(byId: monitorId)
        commitWorkspaceTransitionFocusHandoff(
            targetWorkspaceId: targetWorkspace.id,
            monitor: monitor
        )
        return true
    }

    @discardableResult
    func focusWorkspaceAnywhere(rawWorkspaceID: String) -> Bool {
        guard let controller else { return false }
        guard let targetWsId = controller.workspaceManager.workspaceId(named: rawWorkspaceID) else { return false }
        guard let targetMonitor = controller.workspaceManager.monitorForWorkspace(targetWsId) else { return false }

        guard controller.workspaceManager.setActiveWorkspace(targetWsId, on: targetMonitor.id) else { return false }

        commitWorkspaceTransitionFocusHandoff(
            targetWorkspaceId: targetWsId,
            monitor: targetMonitor
        )
        return true
    }

    func workspaceBackAndForth() {
        guard let controller else { return }
        guard let currentMonitorId = interactionMonitorId(for: controller)
        else { return }

        guard let prevWorkspace = controller.workspaceManager.previousWorkspace(on: currentMonitorId) else {
            return
        }

        guard controller.workspaceManager.setActiveWorkspace(prevWorkspace.id, on: currentMonitorId) else {
            return
        }

        let monitor = controller.workspaceManager.monitor(for: prevWorkspace.id)
            ?? controller.workspaceManager.monitor(byId: currentMonitorId)
        commitWorkspaceTransitionFocusHandoff(
            targetWorkspaceId: prevWorkspace.id,
            monitor: monitor
        )
    }

    func resolveOrCreateAdjacentWorkspace(
        from workspaceId: WorkspaceDescriptor.ID,
        direction: Direction,
        on monitorId: Monitor.ID,
        requiredLayoutKind: ActiveLayoutKind? = nil
    ) -> WorkspaceDescriptor? {
        guard let controller else { return nil }
        let wm = controller.workspaceManager

        let existing: WorkspaceDescriptor? = if direction == .down {
            wm.nextWorkspaceInOrder(on: monitorId, from: workspaceId, wrapAround: false)
        } else {
            wm.previousWorkspaceInOrder(on: monitorId, from: workspaceId, wrapAround: false)
        }
        if let existing { return existing }

        guard let currentName = wm.descriptor(for: workspaceId)?.name,
              let currentNumber = Int(currentName)
        else { return nil }

        var candidateNumber = direction == .down ? currentNumber + 1 : currentNumber - 1
        while candidateNumber > 0 {
            let candidateName = String(candidateNumber)
            if wm.workspaceId(named: candidateName) == nil {
                let candidateLayoutKind: ActiveLayoutKind = .dwindle
                guard requiredLayoutKind == nil || candidateLayoutKind == requiredLayoutKind else { return nil }
                guard let workspace = wm.createDynamicWorkspace(named: candidateName, on: monitorId) else {
                    return nil
                }
                return workspace
            }
            let delta = direction == .down ? 1 : -1
            let next = candidateNumber.addingReportingOverflow(delta)
            guard !next.overflow else { return nil }
            candidateNumber = next.partialValue
        }
        return nil
    }
}
