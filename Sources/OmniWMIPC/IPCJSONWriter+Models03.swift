// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension IPCJSONWriter {
    mutating func fields2(_ value: borrowing IPCWindowQuerySnapshot, _ first: inout Bool) throws {
        if let fieldValue = value.mode {
            self.key("mode", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.pid {
            self.key("pid", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.scratchpadIndex {
            self.key("scratchpadIndex", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.title {
            self.key("title", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.windowId {
            self.key("windowId", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.workspace {
            self.key("workspace", &first)
            try self.value(fieldValue)
        }
    }

    mutating func value(_ value: borrowing IPCWindowQuerySnapshot) throws {
        begin(123)
        var first = true
        try fields0(value, &first)
        try fields1(value, &first)
        try fields2(value, &first)
        end(125)
    }

    mutating func value(_ value: borrowing [IPCWindowQuerySnapshot]) throws {
        begin(91)
        var first = true
        let span = value.span
        var index = 0
        while index < span.count {
            item(&first)
            try self.value(span[index])
            index += 1
        }
        end(93)
    }

    mutating func value(_ value: borrowing IPCWindowsQueryResult) throws {
        begin(123)
        var first = true
        self.key("windows", &first)
        try self.value(value.windows)
        end(125)
    }

    mutating func value(_ value: borrowing IPCWorkspaceWindowCounts) throws {
        begin(123)
        var first = true
        self.key("floating", &first)
        try self.value(value.floating)
        self.key("scratchpad", &first)
        try self.value(value.scratchpad)
        self.key("tiled", &first)
        try self.value(value.tiled)
        self.key("total", &first)
        try self.value(value.total)
        end(125)
    }

    mutating func value(_ value: borrowing IPCWorkspaceLayout) throws {
        try self.value(value.rawValue)
    }

    mutating func fields0(_ value: borrowing IPCWorkspaceQuerySnapshot, _ first: inout Bool) throws {
        if let fieldValue = value.counts {
            self.key("counts", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.display {
            self.key("display", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.displayName {
            self.key("displayName", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.focusedWindowId {
            self.key("focusedWindowId", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.id {
            self.key("id", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.isCurrent {
            self.key("isCurrent", &first)
            try self.value(fieldValue)
        }
    }

    mutating func fields1(_ value: borrowing IPCWorkspaceQuerySnapshot, _ first: inout Bool) throws {
        if let fieldValue = value.isFocused {
            self.key("isFocused", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.isVisible {
            self.key("isVisible", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.layout {
            self.key("layout", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.number {
            self.key("number", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.rawName {
            self.key("rawName", &first)
            try self.value(fieldValue)
        }
    }

    mutating func value(_ value: borrowing IPCWorkspaceQuerySnapshot) throws {
        begin(123)
        var first = true
        try fields0(value, &first)
        try fields1(value, &first)
        end(125)
    }

    mutating func value(_ value: borrowing [IPCWorkspaceQuerySnapshot]) throws {
        begin(91)
        var first = true
        let span = value.span
        var index = 0
        while index < span.count {
            item(&first)
            try self.value(span[index])
            index += 1
        }
        end(93)
    }

    mutating func value(_ value: borrowing IPCWorkspacesQueryResult) throws {
        begin(123)
        var first = true
        self.key("workspaces", &first)
        try self.value(value.workspaces)
        end(125)
    }

    mutating func value(_ value: borrowing [IPCRect]) throws {
        begin(91)
        var first = true
        let span = value.span
        var index = 0
        while index < span.count {
            item(&first)
            try self.value(span[index])
            index += 1
        }
        end(93)
    }

    mutating func value(_ value: borrowing IPCSpan) throws {
        begin(123)
        var first = true
        self.key("end", &first)
        try self.value(value.end)
        self.key("start", &first)
        try self.value(value.start)
        end(125)
    }

    mutating func value(_ value: borrowing IPCDisplayOrientation) throws {
        try self.value(value.rawValue)
    }

    mutating func value(_ value: borrowing IPCInsets) throws {
        begin(123)
        var first = true
        self.key("bottom", &first)
        try self.value(value.bottom)
        self.key("left", &first)
        try self.value(value.left)
        self.key("right", &first)
        try self.value(value.right)
        self.key("top", &first)
        try self.value(value.top)
        end(125)
    }

    mutating func fields0(_ value: borrowing IPCDisplayQuerySnapshot, _ first: inout Bool) throws {
        if let fieldValue = value.activeWorkspace {
            self.key("activeWorkspace", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.barFrames {
            self.key("barFrames", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.frame {
            self.key("frame", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.fullscreenUsesOuterGaps {
            self.key("fullscreenUsesOuterGaps", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.hasNotch {
            self.key("hasNotch", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.id {
            self.key("id", &first)
            try self.value(fieldValue)
        }
    }

    mutating func fields1(_ value: borrowing IPCDisplayQuerySnapshot, _ first: inout Bool) throws {
        if let fieldValue = value.innerGap {
            self.key("innerGap", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.isCurrent {
            self.key("isCurrent", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.isMain {
            self.key("isMain", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.menuBarHeight {
            self.key("menuBarHeight", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.name {
            self.key("name", &first)
            try self.value(fieldValue)
        }
        if let fieldValue = value.notch {
            self.key("notch", &first)
            try self.value(fieldValue)
        }
    }
}
