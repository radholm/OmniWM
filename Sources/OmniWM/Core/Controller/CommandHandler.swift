// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

@MainActor
final class CommandHandler {
    weak var controller: WMController?
    var nativeFullscreenStateProvider: ((AXWindowRef) -> Bool)?
    var nativeFullscreenSetter: ((AXWindowRef, Bool) -> Bool)?
    var frontmostAppPidProvider: (() -> pid_t?)?
    var frontmostFocusedWindowTokenProvider: (() -> WindowToken?)?
    var requestWindowMarkName: () -> String? = { CommandPaletteMarkNamePrompt.requestName() }
    var chooseWindowMarkNameToRemove: ([String]) -> String? = {
        CommandPaletteMarkRemovalPrompt.requestName(from: $0)
    }

    init(controller: WMController) {
        self.controller = controller
    }

    @discardableResult
    func handleHotkeyInvocation(_ invocation: HotkeyInvocation) -> ExternalCommandResult {
        guard let controller else { return .notFound }
        guard controller.isEnabled else { return .ignoredDisabled }
        if invocation.command == .presentation(.overview), invocation.trigger?.isRepeat == true {
            return .executed
        }
        switch controller.handleOverviewHotkey(invocation) {
        case .handled:
            return .executed
        case .blocked:
            return .ignoredOverview
        case .inactive:
            return performCommand(invocation.command)
        }
    }

    @discardableResult
    func performCommand(_ command: HotkeyCommand) -> ExternalCommandResult {
        guard let controller else { return .notFound }
        guard controller.isEnabled else { return .ignoredDisabled }
        guard !Self.shouldIgnoreCommand(command, isOverviewOpen: controller.isOverviewOpen()) else {
            return .ignoredOverview
        }

        guard Self.isLayoutCompatible(command.layoutCompatibility, with: currentLayoutType()) else {
            return .ignoredLayoutMismatch
        }

        return performAllowedCommand(command, controller: controller)
    }

    static func isLayoutCompatible(_ compatibility: LayoutCompatibility, with layoutType: LayoutType) -> Bool {
        true
    }

    private func performAllowedCommand(_ command: HotkeyCommand, controller: WMController) -> ExternalCommandResult {
        switch command {
        case let .focus(direction):
            focusWindow(direction: direction)
        case let .focusNavigation(action):
            return perform(action, controller: controller)
        case let .move(direction):
            let outcome = moveWindow(direction: direction)
            if outcome == .atWorkspaceEdge, controller.settings.focus.moveCrossesMonitorAtEdge {
                controller.workspaceNavigationHandler.moveWindowAcrossMonitorAtEdge(direction: direction)
            }
        case let .workspace(action):
            return perform(action, controller: controller)
        case let .windowMovement(action):
            return perform(action, controller: controller)
        case let .monitorFocus(action):
            return perform(action, controller: controller)
        case let .fullscreen(action):
            return perform(action, controller: controller)
        case let .sizing(action):
            return perform(action, controller: controller)
        case let .dwindle(action):
            return perform(action, controller: controller)
        case .openCommandPalette:
            controller.openCommandPalette()
        case .raiseAllFloatingWindows:
            controller.raiseAllFloatingWindows()
        case .rescueOffscreenWindows:
            _ = controller.rescueOffscreenWindows()
        case .windowState(.toggleFloating):
            return controller.toggleFocusedWindowFloating()
        case .windowState(.close):
            return controller.closeFocusedWindow()
        case let .scratchpad(action):
            return perform(action, controller: controller)
        case .openMenuAnywhere:
            controller.openMenuAnywhere()
        case let .windowMark(action):
            return perform(action, controller: controller)
        case let .presentation(action):
            return perform(action, controller: controller)
        }
        return .executed
    }

    static func shouldIgnoreCommand(_ command: HotkeyCommand, isOverviewOpen: Bool) -> Bool {
        isOverviewOpen && command != .presentation(.overview)
    }

    func layoutHandler<T>(as capability: T.Type) -> T? {
        guard let controller else { return nil }
        let layoutType = currentLayoutType()
        let handler: AnyObject = switch layoutType {
        case .dwindle,
             .defaultLayout:
            controller.layoutRefreshController.dwindleHandler
        }
        return handler as? T
    }

    private func moveWindow(direction: Direction) -> WindowMoveOutcome {
        switch currentLayoutType() {
        case .dwindle,
             .defaultLayout:
            controller?.dwindleLayoutHandler.moveWindow(direction: direction) ?? .blocked
        }
    }

    private func focusWindow(direction: Direction) {
        guard let controller else { return }
        switch currentLayoutType() {
        case .dwindle,
             .defaultLayout:
            if controller.dwindleLayoutHandler.focusNeighbor(direction: direction) {
                return
            }
            if controller.settings.focus.crossesMonitorAtEdge,
               controller.workspaceNavigationHandler.focusMonitor(direction: direction)
            {
                return
            }
            _ = controller.dwindleLayoutHandler.wrapGroupFocus(direction: direction)
        }
    }

    func moveWindowWithinContainer(direction: Direction) {
        switch currentLayoutType() {
        case .dwindle,
             .defaultLayout:
            controller?.dwindleLayoutHandler.moveGroupMember(direction: direction)
        }
    }

    func focusWindowWrapping(direction: Direction) {
        switch currentLayoutType() {
        case .dwindle,
             .defaultLayout:
            _ = controller?.dwindleLayoutHandler.wrapGroupFocus(direction: direction)
        }
    }

    func toggleFullscreen() {
        switch currentLayoutType() {
        case .dwindle,
             .defaultLayout:
            controller?.dwindleLayoutHandler.toggleFullscreen()
        }
    }

    func toggleNativeFullscreenForFocused() {
        guard let controller else { return }
        let setFullscreen = nativeFullscreenSetter ?? { axRef, fullscreen in
            AXWindowService.setNativeFullscreen(axRef, fullscreen: fullscreen)
        }
        let isFullscreen = nativeFullscreenStateProvider ?? { axRef in
            AXWindowService.isFullscreen(axRef)
        }

        if let token = controller.workspaceManager.selectedManagedToken,
           let entry = controller.workspaceManager.entry(for: token),
           !controller.workspaceManager.isWindowSuppressedByMacOS(entry.token)
        {
            let currentState = isFullscreen(entry.axRef)
            if currentState {
                applyNativeFullscreenExit(
                    token,
                    axRef: entry.axRef,
                    controller: controller,
                    setter: setFullscreen
                )
                return
            }

            guard controller.workspaceManager.requestNativeFullscreenEnter(token, in: entry.workspaceId) else {
                return
            }
            guard setFullscreen(entry.axRef, true) else {
                controller.workspaceManager.restoreNativeFullscreenRecord(for: token)
                return
            }
            return
        }

        guard controller.workspaceManager.isAppFullscreenActive
            || controller.workspaceManager.hasPendingNativeFullscreenTransition
        else {
            return
        }

        let frontmostPid = frontmostAppPidProvider?() ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostToken = frontmostFocusedWindowTokenProvider?()
            ?? frontmostPid.flatMap { controller.axEventHandler.focusedWindowToken(for: $0) }
        guard let token = controller.workspaceManager.nativeFullscreenCommandTarget(frontmostToken: frontmostToken),
              let entry = controller.workspaceManager.entry(for: token),
              !controller.workspaceManager.isWindowSuppressedByMacOS(entry.token)
        else {
            return
        }

        applyNativeFullscreenExit(
            token,
            axRef: entry.axRef,
            controller: controller,
            setter: setFullscreen
        )
    }

    private func applyNativeFullscreenExit(
        _ token: WindowToken,
        axRef: AXWindowRef,
        controller: WMController,
        setter: (AXWindowRef, Bool) -> Bool
    ) {
        guard controller.workspaceManager.requestNativeFullscreenExit(token) else { return }
        if !setter(axRef, false) {
            _ = controller.workspaceManager.markNativeFullscreenSuspended(token)
        }
    }

    private func currentLayoutType() -> LayoutType {
        guard let controller else { return .dwindle }
        guard let ws = controller.activeWorkspace() else { return .dwindle }
        return controller.settings.workspaces.layoutType(for: ws.name)
    }

    @discardableResult
    func setWorkspaceLayout(_ newLayout: LayoutType, forWorkspaceNamed workspaceName: String? = nil) -> Bool {
        guard let controller else { return false }
        let resolvedWorkspaceName = workspaceName ?? controller.activeWorkspace()?.name
        guard let resolvedWorkspaceName else { return false }

        var configs = controller.settings.workspaces.configurations
        guard let index = configs.firstIndex(where: { $0.name == resolvedWorkspaceName }) else { return false }

        guard configs[index].layoutType != newLayout else { return false }

        configs[index] = configs[index].with(layoutType: newLayout)
        controller.settings.workspaces.configurations = configs
        controller.layoutRefreshController.requestRelayout(reason: .workspaceLayoutToggled)
        if let ipcApplicationBridge = controller.ipcApplicationBridge {
            Task {
                await ipcApplicationBridge.publishEvent(.layoutChanged)
            }
        }
        return true
    }
}

extension CommandHandler {
    private func perform(_ action: WindowMarkHotkeyAction, controller: WMController) -> ExternalCommandResult {
        let token = controller.workspaceManager.nativeManagedFocusToken
        let expectedHandle = token.flatMap { controller.workspaceManager.handle(for: $0) }
        let interaction = CommandPaletteMarkInteraction(
            selectedWindowToken: token,
            isEligibleWindow: { token in
                guard let expectedHandle,
                      let entry = controller.workspaceManager.entry(for: token),
                      entry.layoutReason == .standard,
                      controller.workspaceManager.handle(for: token) === expectedHandle
                else {
                    return false
                }
                return true
            },
            requestName: requestWindowMarkName,
            chooseRemovalName: chooseWindowMarkNameToRemove,
            namesForWindow: { controller.windowMarkRegistry.names(for: $0) },
            lookupMark: { controller.windowMarkRegistry.lookup($0) },
            setMark: { token, name in controller.windowMarkRegistry.set(name, for: token) },
            removeMark: { controller.windowMarkRegistry.remove($0) }
        )
        let outcome = switch action {
        case .set:
            interaction.setSelectedWindowMark()
        case .remove:
            interaction.removeMarkFromSelectedWindow(token)
        }
        return switch outcome {
        case .marked,
             .alreadyMarked,
             .removed:
            .executed
        case .cancelled,
             .noMarks:
            .noChange
        case .duplicateName,
             .invalidName,
             .staleWindow,
             .noSelectedWindow,
             .staleMark:
            .windowActionFailed
        }
    }
}
