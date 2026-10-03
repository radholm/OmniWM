// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

public enum IPCWindowMovementCommandName: String, CaseIterable, Hashable, Sendable {
    case spatial = "move"
    case down = "move-window-down"
    case up = "move-window-up"
}

public enum IPCWindowMovementCommand: Equatable, Sendable {
    case spatial(direction: IPCDirection)
    case down
    case up

    public var name: IPCWindowMovementCommandName {
        switch self {
        case .spatial:
            .spatial
        case .down:
            .down
        case .up:
            .up
        }
    }

    init(name: IPCWindowMovementCommandName, arguments: IPCCommandArgumentSource) throws {
        switch name {
        case .spatial:
            self = try .spatial(direction: arguments.direction())
        case .down:
            self = try arguments.requireNoArguments(.down)
        case .up:
            self = try arguments.requireNoArguments(.up)
        }
    }

    func encodeArguments(to writer: inout IPCCommandArgumentWriter) throws {
        switch self {
        case let .spatial(direction):
            try writer.encode(direction: direction)
        case .down,
             .up:
            break
        }
    }
}
