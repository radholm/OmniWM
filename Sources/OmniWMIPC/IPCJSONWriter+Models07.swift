// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension IPCJSONWriter {
    mutating func value(_ value: borrowing IPCDisplayTickMetrics) throws {
        begin(123)
        var first = true
        self.key("completionPastTargetCount", &first)
        try self.value(value.completionPastTargetCount)
        self.key("longTimestampGapCount", &first)
        try self.value(value.longTimestampGapCount)
        self.key("maxIntervalMicroseconds", &first)
        try self.value(value.maxIntervalMicroseconds)
        self.key("maxWorkMicroseconds", &first)
        try self.value(value.maxWorkMicroseconds)
        self.key("meanWorkMicroseconds", &first)
        try self.value(value.meanWorkMicroseconds)
        self.key("minCompletionSlackMicroseconds", &first)
        try self.value(value.minCompletionSlackMicroseconds)
        self.key("minEntrySlackMicroseconds", &first)
        try self.value(value.minEntrySlackMicroseconds)
        self.key("tickCount", &first)
        try self.value(value.tickCount)
        self.key("timingAnomalyCount", &first)
        try self.value(value.timingAnomalyCount)
        self.key("timingAnomalyPercent", &first)
        try self.value(value.timingAnomalyPercent)
        self.key("workExceededNominalPeriodCount", &first)
        try self.value(value.workExceededNominalPeriodCount)
        end(125)
    }

    mutating func value(_ value: borrowing IPCLayoutBuildMetrics) throws {
        begin(123)
        var first = true
        self.key("completedRelayoutCycles", &first)
        try self.value(value.completedRelayoutCycles)
        self.key("totalBuilds", &first)
        try self.value(value.totalBuilds)
        end(125)
    }

    mutating func value(_ value: borrowing IPCProcessResourceMetrics) throws {
        begin(123)
        var first = true
        self.key("energyNanojoules", &first)
        try self.value(value.energyNanojoules)
        self.key("interruptWakeups", &first)
        try self.value(value.interruptWakeups)
        self.key("packageIdleWakeups", &first)
        try self.value(value.packageIdleWakeups)
        self.key("physicalFootprintBytes", &first)
        try self.value(value.physicalFootprintBytes)
        self.key("residentSizeBytes", &first)
        try self.value(value.residentSizeBytes)
        self.key("systemTimeNanoseconds", &first)
        try self.value(value.systemTimeNanoseconds)
        self.key("userTimeNanoseconds", &first)
        try self.value(value.userTimeNanoseconds)
        end(125)
    }

    mutating func value(_ value: borrowing IPCMetricsQueryResult) throws {
        begin(123)
        var first = true
        self.key("axWrites", &first)
        try self.value(value.axWrites)
        self.key("displayTicks", &first)
        try self.value(value.displayTicks)
        self.key("layoutBuilds", &first)
        try self.value(value.layoutBuilds)
        if let fieldValue = value.process {
            self.key("process", &first)
            try self.value(fieldValue)
        }
        self.key("traceCaptureActive", &first)
        try self.value(value.traceCaptureActive)
        end(125)
    }

    mutating func value(_ value: borrowing IPCShellWidget) throws {
        begin(123)
        var first = true
        if let fieldValue = value.error {
            self.key("error", &first)
            try self.value(fieldValue)
        }
        self.key("name", &first)
        try self.value(value.name)
        self.key("placements", &first)
        try self.value(value.placements)
        self.key("source", &first)
        try self.value(value.source)
        self.key("state", &first)
        try self.value(value.state)
        end(125)
    }

    mutating func value(_ value: borrowing [IPCShellWidget]) throws {
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

    mutating func value(_ value: borrowing IPCShellWidgetsQueryResult) throws {
        begin(123)
        var first = true
        self.key("problems", &first)
        try self.value(value.problems)
        self.key("profile", &first)
        try self.value(value.profile)
        self.key("widgets", &first)
        try self.value(value.widgets)
        end(125)
    }

    mutating func value(_ value: borrowing IPCResult.Payload) throws {
        switch value {
        case let .pong(payload):
            try self.value(payload)
        case let .version(payload):
            try self.value(payload)
        case let .capture(payload):
            try self.value(payload)
        case let .workspaceBar(payload):
            try self.value(payload)
        case let .activeWorkspace(payload):
            try self.value(payload)
        case let .focusedMonitor(payload):
            try self.value(payload)
        case let .apps(payload):
            try self.value(payload)
        case let .focusedWindow(payload):
            try self.value(payload)
        case let .windows(payload):
            try self.value(payload)
        case let .workspaces(payload):
            try self.value(payload)
        case let .displays(payload):
            try self.value(payload)
        case let .rules(payload):
            try self.value(payload)
        case let .ruleActions(payload):
            try self.value(payload)
        case let .queries(payload):
            try self.value(payload)
        case let .commands(payload):
            try self.value(payload)
        case let .subscriptions(payload):
            try self.value(payload)
        case let .capabilities(payload):
            try self.value(payload)
        case let .subscribed(payload):
            try self.value(payload)
        case let .windowMarks(payload):
            try self.value(payload)
        case let .metrics(payload):
            try self.value(payload)
        case let .shellWidgets(payload):
            try self.value(payload)
        }
    }

    mutating func value(_ value: borrowing IPCResult) throws {
        begin(123)
        var first = true
        self.key("kind", &first)
        try self.value(value.kind)
        self.key("payload", &first)
        try self.value(value.payload)
        end(125)
    }

    mutating func value(_ value: borrowing IPCResponseStatus) throws {
        try self.value(value.rawValue)
    }

    mutating func value(_ value: borrowing IPCResponse) throws {
        begin(123)
        var first = true
        if let fieldValue = value.code {
            self.key("code", &first)
            try self.value(fieldValue)
        }
        self.key("id", &first)
        try self.value(value.id)
        self.key("kind", &first)
        try self.value(value.kind)
        self.key("ok", &first)
        try self.value(value.ok)
        if let fieldValue = value.result {
            self.key("result", &first)
            try self.value(fieldValue)
        }
        self.key("status", &first)
        try self.value(value.status)
        self.key("version", &first)
        try self.value(value.version)
        end(125)
    }

    mutating func value(_ value: borrowing IPCEventKind) throws {
        try self.value(value.rawValue)
    }

    mutating func value(_ value: borrowing IPCEventEnvelope) throws {
        begin(123)
        var first = true
        self.key("channel", &first)
        try self.value(value.channel)
        if let fieldValue = value.code {
            self.key("code", &first)
            try self.value(fieldValue)
        }
        self.key("id", &first)
        try self.value(value.id)
        self.key("kind", &first)
        try self.value(value.kind)
        self.key("ok", &first)
        try self.value(value.ok)
        self.key("result", &first)
        try self.value(value.result)
        self.key("status", &first)
        try self.value(value.status)
        self.key("version", &first)
        try self.value(value.version)
        end(125)
    }

    mutating func value(_ value: borrowing IPCRequestKind) throws {
        try self.value(value.rawValue)
    }

    mutating func value(_ value: borrowing IPCNoPayload) throws {
        begin(123)
        end(125)
    }

    mutating func value(_ value: borrowing IPCDirection) throws {
        try self.value(value.rawValue)
    }

    mutating func argument(_ name: StaticString, _ value: borrowing IPCDirection, _ first: inout Bool) throws {
        self.key("arguments", &first)
        begin(123)
        var argumentFirst = true
        self.key(name, &argumentFirst)
        try self.value(value)
        end(125)
    }
}
