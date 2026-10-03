// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

public enum IPCFocusCommandName: String, CaseIterable, Hashable, Sendable {
    case spatial = "focus"
    case previous = "focus-previous"
    case windowDownOrTop = "focus-window-down-or-top"
    case windowUpOrBottom = "focus-window-up-or-bottom"
}

public enum IPCFocusCommand: Equatable, Sendable {
    case spatial(direction: IPCDirection)
    case previous
    case windowDownOrTop
    case windowUpOrBottom

    public var name: IPCFocusCommandName {
        switch self {
        case .spatial:
            .spatial
        case .previous:
            .previous
        case .windowDownOrTop:
            .windowDownOrTop
        case .windowUpOrBottom:
            .windowUpOrBottom
        }
    }

    init(name: IPCFocusCommandName, arguments: IPCCommandArgumentSource) throws {
        switch name {
        case .spatial:
            self = try .spatial(direction: arguments.direction())
        case .previous:
            self = try arguments.requireNoArguments(.previous)
        case .windowDownOrTop:
            self = try arguments.requireNoArguments(.windowDownOrTop)
        case .windowUpOrBottom:
            self = try arguments.requireNoArguments(.windowUpOrBottom)
        }
    }

    func encodeArguments(to writer: inout IPCCommandArgumentWriter) throws {
        switch self {
        case let .spatial(direction):
            try writer.encode(direction: direction)
        case .previous,
             .windowDownOrTop,
             .windowUpOrBottom:
            break
        }
    }
}
