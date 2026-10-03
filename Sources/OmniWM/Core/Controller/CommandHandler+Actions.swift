// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

extension CommandHandler {
    func perform(_ action: FocusNavigationAction, controller: WMController) -> ExternalCommandResult {
        switch action {
        case .previous:
            let currentToken = controller.workspaceManager.selectedManagedToken
            if let target = controller.workspaceManager.mostRecentlyFocusedTiledToken(excluding: currentToken),
               let workspaceId = controller.workspaceManager.entry(for: target)?.workspaceId
            {
                _ = controller.windowActionHandler.navigateToWindowInternal(token: target, workspaceId: workspaceId)
            }
        case .windowDownOrTop:
            focusWindowWrapping(direction: .down)
        case .windowUpOrBottom:
            focusWindowWrapping(direction: .up)
        }
        return .executed
    }

    func perform(_ action: WorkspaceAction, controller: WMController) -> ExternalCommandResult {
        switch action {
        case let .moveToMonitor(direction):
            controller.workspaceNavigationHandler.moveWindowToMonitor(direction: direction)
        case let .moveTo(index):
            controller.workspaceNavigationHandler.moveFocusedWindow(toWorkspaceIndex: index)
        case .moveUp:
            controller.workspaceNavigationHandler.moveWindowToAdjacentWorkspace(direction: .up)
        case .moveDown:
            controller.workspaceNavigationHandler.moveWindowToAdjacentWorkspace(direction: .down)
        case let .switchTo(index):
            controller.workspaceNavigationHandler.switchWorkspace(index: index)
        case let .switchSlot(slot):
            controller.workspaceNavigationHandler.switchWorkspaceSlot(slot)
        case let .moveToSlot(slot):
            controller.workspaceNavigationHandler.moveFocusedWindow(toWorkspaceSlot: slot)
        case .next:
            controller.workspaceNavigationHandler.switchWorkspaceRelative(isNext: true)
        case .previous:
            controller.workspaceNavigationHandler.switchWorkspaceRelative(isNext: false)
        case let .moveWorkspaceToMonitor(direction):
            if let workspaceId = controller.activeWorkspace()?.id {
                _ = controller.workspaceNavigationHandler.moveWorkspaceToMonitor(
                    workspaceId,
                    direction: direction,
                    force: true
                )
            }
        case let .swapWithMonitor(direction):
            controller.workspaceNavigationHandler.swapCurrentWorkspaceWithMonitor(direction: direction)
        case .backAndForth:
            controller.workspaceNavigationHandler.workspaceBackAndForth()
        }
        return .executed
    }

    func perform(_ action: WindowMovementAction, controller: WMController) -> ExternalCommandResult {
        switch action {
        case .down:
            moveWindowWithinContainer(direction: .down)
        case .up:
            moveWindowWithinContainer(direction: .up)
        }
        return .executed
    }

    func perform(_ action: IPCMonitorFocusCommand, controller: WMController) -> ExternalCommandResult {
        switch action {
        case .previous:
            controller.workspaceNavigationHandler.focusMonitorCyclic(previous: true)
        case .next:
            controller.workspaceNavigationHandler.focusMonitorCyclic(previous: false)
        case .last:
            controller.workspaceNavigationHandler.focusLastMonitor()
        }
        return .executed
    }

    func perform(_ action: IPCFullscreenCommand, controller: WMController) -> ExternalCommandResult {
        switch action {
        case .managed:
            toggleFullscreen()
        case .native:
            toggleNativeFullscreenForFocused()
        }
        return .executed
    }

    func perform(_ action: SizingAction, controller: WMController) -> ExternalCommandResult {
        switch action {
        case .cycleSizeForward:
            layoutHandler(as: LayoutSizable.self)?.cycleSize(forward: true)
        case .cycleSizeBackward:
            layoutHandler(as: LayoutSizable.self)?.cycleSize(forward: false)
        case .balanceSizes:
            layoutHandler(as: LayoutSizable.self)?.balanceSizes()
        }
        return .executed
    }

    func perform(_ action: DwindleAction, controller: WMController) -> ExternalCommandResult {
        let changed = switch action {
        case .moveToRoot:
            controller.dwindleLayoutHandler.moveToRootInDwindle()
        case let .moveGroup(direction):
            controller.dwindleLayoutHandler.swapWindow(direction: direction) == .movedWithinWorkspace
        case .toggleSplit:
            controller.dwindleLayoutHandler.toggleSplitInDwindle()
        case .swapSplit:
            controller.dwindleLayoutHandler.swapSplitInDwindle()
        case let .resizeAlongAxis(orientation, grow):
            controller.dwindleLayoutHandler.resizeAlongAxisInDwindle(orientation: orientation, grow: grow)
        case let .resizeFocusedWindow(grow):
            controller.dwindleLayoutHandler.resizeFocusedWindowInDwindle(grow: grow)
        case let .preselect(direction):
            controller.dwindleLayoutHandler.preselectInDwindle(direction: direction)
        case .preselectClear:
            controller.dwindleLayoutHandler.clearPreselectInDwindle()
        }
        return changed ? .executed : .noChange
    }

    func perform(_ action: ScratchpadAction, controller: WMController) -> ExternalCommandResult {
        switch action {
        case let .assign(index):
            guard let index = ScratchpadIndex(index) else { return .invalidArguments }
            return controller.assignFocusedWindowToScratchpad(index)
        case let .toggle(index):
            guard let index = ScratchpadIndex(index) else { return .invalidArguments }
            return controller.toggleScratchpad(index)
        }
    }

    func perform(_ action: IPCPresentationCommand, controller: WMController) -> ExternalCommandResult {
        switch action {
        case .workspaceBar:
            controller.toggleWorkspaceBarVisibility()
        case .hiddenBar:
            controller.toggleHiddenBarPanel()
        case .quakeTerminal:
            guard controller.settings.quakeTerminal.enabled else { return .ignoredDisabled }
            controller.toggleQuakeTerminal()
        case .overview:
            guard controller.settings.overview.enabled else { return .ignoredDisabled }
            controller.toggleOverview()
        case .systemStats:
            controller.toggleSystemStats()
        }
        return .executed
    }
}
