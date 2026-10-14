// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension IPCJSONWriter {
    mutating func arguments(_ value: borrowing IPCFocusCommand, _ first: inout Bool) throws {
        switch value {
        case let .spatial(direction):
            try argument("direction", direction, &first)
        case .previous,
             .windowDownOrTop,
             .windowUpOrBottom:
            break
        }
    }

    mutating func arguments(_ value: borrowing IPCWindowMovementCommand, _ first: inout Bool) throws {
        switch value {
        case let .spatial(direction):
            try argument("direction", direction, &first)
        case .down,
             .up:
            break
        }
    }

    mutating func argument(_ name: StaticString, _ value: borrowing Int, _ first: inout Bool) throws {
        self.key("arguments", &first)
        begin(123)
        var argumentFirst = true
        self.key(name, &argumentFirst)
        try self.value(value)
        end(125)
    }

    mutating func arguments(_ value: borrowing IPCWorkspaceCommand, _ first: inout Bool) throws {
        switch value {
        case let .switchTo(workspaceNumber):
            try argument("workspaceNumber", workspaceNumber, &first)
        case let .switchAnywhere(workspaceNumber):
            try argument("workspaceNumber", workspaceNumber, &first)
        case let .switchSlot(slotNumber):
            try argument("slotNumber", slotNumber, &first)
        case let .moveTo(workspaceNumber):
            try argument("workspaceNumber", workspaceNumber, &first)
        case let .moveToOnMonitor(workspaceNumber, direction):
            self.key("arguments", &first)
            begin(123)
            var argumentFirst = true
            self.key("direction", &argumentFirst)
            try self.value(direction)
            self.key("workspaceNumber", &argumentFirst)
            try self.value(workspaceNumber)
            end(125)
        case let .moveToSlot(slotNumber):
            try argument("slotNumber", slotNumber, &first)
        case let .moveToMonitor(direction):
            try argument("direction", direction, &first)
        case .next,
             .previous,
             .backAndForth,
             .moveUp,
             .moveDown:
            break
        }
    }

    mutating func value(_ value: borrowing IPCResizeAxis) throws {
        try self.value(value.rawValue)
    }

    mutating func value(_ value: borrowing IPCResizeOperation) throws {
        try self.value(value.rawValue)
    }

    mutating func argument(_ name: StaticString, _ value: borrowing IPCResizeOperation, _ first: inout Bool) throws {
        self.key("arguments", &first)
        begin(123)
        var argumentFirst = true
        self.key(name, &argumentFirst)
        try self.value(value)
        end(125)
    }

    mutating func arguments(_ value: borrowing IPCDwindleCommand, _ first: inout Bool) throws {
        switch value {
        case let .moveGroup(direction):
            try argument("direction", direction, &first)
        case let .resize(axis, operation):
            self.key("arguments", &first)
            begin(123)
            var argumentFirst = true
            self.key("axis", &argumentFirst)
            try self.value(axis)
            self.key("operation", &argumentFirst)
            try self.value(operation)
            end(125)
        case let .resizeFocused(operation):
            try argument("operation", operation, &first)
        case let .preselect(direction):
            try argument("direction", direction, &first)
        case .cycleSizeForward,
             .cycleSizeBackward,
             .balanceSizes,
             .moveToRoot,
             .toggleSplit,
             .swapSplit,
             .preselectClear:
            break
        }
    }

    mutating func argument(_ name: StaticString, _ value: borrowing IPCWorkspaceLayout, _ first: inout Bool) throws {
        self.key("arguments", &first)
        begin(123)
        var argumentFirst = true
        self.key(name, &argumentFirst)
        try self.value(value)
        end(125)
    }

    mutating func arguments(_ value: borrowing IPCWorkspaceLayoutCommand, _ first: inout Bool) throws {
        switch value {
        case let .set(layout):
            try argument("layout", layout, &first)
        }
    }

    mutating func arguments(_ value: borrowing IPCScratchpadCommand, _ first: inout Bool) throws {
        switch value {
        case let .assign(index):
            try argument("scratchpadIndex", index, &first)
        case let .toggle(index):
            try argument("scratchpadIndex", index, &first)
        }
    }

    mutating func value(_ value: borrowing IPCCommandPaletteMode) throws {
        try self.value(value.rawValue)
    }

    mutating func value(_ value: borrowing IPCCommandRequest) throws {
        begin(123)
        var first = true
        switch value {
        case let .focus(command):
            try arguments(command, &first)
        case let .windowMovement(command):
            try arguments(command, &first)
        case let .workspace(command):
            try arguments(command, &first)
        case let .dwindle(command):
            try arguments(command, &first)
        case let .workspaceLayout(command):
            try arguments(command, &first)
        case let .scratchpad(command):
            try arguments(command, &first)
        case let .swapWorkspaceWithMonitor(argument):
            self.key("arguments", &first)
            begin(123)
            var argumentFirst = true
            self.key("direction", &argumentFirst)
            try self.value(argument)
            end(125)
        case let .openCommandPaletteMode(argument):
            self.key("arguments", &first)
            begin(123)
            var argumentFirst = true
            self.key("mode", &argumentFirst)
            try self.value(argument)
            end(125)
        case .monitorFocus,
             .openCommandPalette,
             .raiseAllFloatingWindows,
             .toggleFloatingFocus,
             .rescueOffscreenWindows,
             .fullscreen,
             .presentation,
             .media,
             .windowState,
             .openMenuAnywhere:
            break
        }
        self.key("name", &first)
        try self.value(value.name)
        end(125)
    }

    mutating func value(_ value: borrowing IPCCaptureRequest) throws {
        switch value {
        case let .start(profile):
            begin(123)
            var first = true
            self.key("name", &first)
            try self.value("start")
            self.key("profile", &first)
            try self.value(profile)
            end(125)
        case .stop:
            begin(123)
            var first = true
            self.key("name", &first)
            try self.value("stop")
            end(125)
        case .status:
            begin(123)
            var first = true
            self.key("name", &first)
            try self.value("status")
            end(125)
        }
    }

    mutating func fields0(_ value: borrowing IPCQuerySelectors, _ first: inout Bool) throws {
        if let fieldValue = value.app {
            self.key("app", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.bundleId {
            self.key("bundleId", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.current {
            self.key("current", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.display {
            self.key("display", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.floating {
            self.key("floating", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.focused {
            self.key("focused", &first)
            try self.value(fieldValue)
        }
    }

    mutating func fields1(_ value: borrowing IPCQuerySelectors, _ first: inout Bool) throws {
        if let fieldValue = value.main {
            self.key("main", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.scratchpad {
            self.key("scratchpad", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.visible {
            self.key("visible", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.window {
            self.key("window", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.workspace {
            self.key("workspace", &first)
            try self.value(fieldValue)
        }
    }

    mutating func value(_ value: borrowing IPCQuerySelectors) throws {
        begin(123)
        var first = true
        try fields0(value, &first)
        try fields1(value, &first)
        end(125)
    }
}
