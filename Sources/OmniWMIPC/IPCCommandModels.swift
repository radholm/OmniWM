// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

public enum IPCCommandArgumentValue: Equatable, Sendable {
    case direction(IPCDirection)
    case integer(Int)
    case layout(IPCWorkspaceLayout)
    case resizeAxis(IPCResizeAxis)
    case resizeOperation(IPCResizeOperation)
}

public enum IPCCommandRequestConstructionError: Error, Equatable, Sendable {
    case invalidArgumentCount
    case invalidArgumentType
}

public enum IPCCommandRequest: Equatable, Sendable {
    case focus(IPCFocusCommand)
    case windowMovement(IPCWindowMovementCommand)
    case workspace(IPCWorkspaceCommand)
    case monitorFocus(IPCMonitorFocusCommand)
    case swapWorkspaceWithMonitor(direction: IPCDirection)
    case dwindle(IPCDwindleCommand)
    case openCommandPalette
    case raiseAllFloatingWindows
    case rescueOffscreenWindows
    case workspaceLayout(IPCWorkspaceLayoutCommand)
    case fullscreen(IPCFullscreenCommand)
    case presentation(IPCPresentationCommand)
    case windowState(IPCWindowStateCommand)
    case scratchpad(IPCScratchpadCommand)
    case openMenuAnywhere

    public var name: IPCCommandName {
        switch self {
        case let .focus(command):
            .focus(command.name)
        case let .windowMovement(command):
            .windowMovement(command.name)
        case let .workspace(command):
            .workspace(command.name)
        case let .monitorFocus(command):
            .monitorFocus(command)
        case .swapWorkspaceWithMonitor:
            .swapWorkspaceWithMonitor
        case let .dwindle(command):
            .dwindle(command.name)
        case .openCommandPalette:
            .openCommandPalette
        case .raiseAllFloatingWindows:
            .raiseAllFloatingWindows
        case .rescueOffscreenWindows:
            .rescueOffscreenWindows
        case let .workspaceLayout(command):
            .workspaceLayout(command.name)
        case let .fullscreen(command):
            .fullscreen(command)
        case let .presentation(command):
            .presentation(command)
        case let .windowState(command):
            .windowState(command)
        case let .scratchpad(command):
            .scratchpad(command.name)
        case .openMenuAnywhere:
            .openMenuAnywhere
        }
    }
}
