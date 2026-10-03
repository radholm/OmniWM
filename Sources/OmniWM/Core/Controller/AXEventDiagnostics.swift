// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

struct ManagedReplacementTraceEvent: Equatable {
    enum Kind: Equatable {
        case enqueued(
            policy: String,
            createCount: Int,
            destroyCount: Int,
            holdCount: Int,
            deadlineReset: Bool
        )
        case flushed(
            policy: String,
            createCount: Int,
            destroyCount: Int,
            holdCount: Int,
            elapsedMillis: Int
        )
        case matched(policy: String, elapsedMillis: Int)
    }

    let timestamp: TimeInterval
    let pid: pid_t
    let workspaceId: WorkspaceDescriptor.ID
    let kind: Kind
}

@MainActor
struct AXEventDiagnostics {
    private static let managedReplacementTraceLimit = 128
    private static let managedReplacementTraceLoggingEnabled =
        ProcessInfo.processInfo.environment["OMNIWM_DEBUG_MANAGED_REPLACEMENT"] == "1"
    private var managedReplacementTrace =
        RingBuffer<ManagedReplacementTraceEvent>(capacity: Self.managedReplacementTraceLimit)

    func managedReplacementTraceDump() -> String {
        let events = managedReplacementTrace.snapshot()
        guard !events.isEmpty else { return "none" }
        return events
            .map {
                "uptime=\(String(format: "%.3f", $0.timestamp)) pid=\($0.pid)"
                    + " workspace=\($0.workspaceId.uuidString) \(String(describing: $0.kind))"
            }
            .joined(separator: "\n")
    }

    mutating func recordManagedReplacementTrace(
        key: AXEventHandler.ManagedReplacementKey,
        kind: ManagedReplacementTraceEvent.Kind
    ) {
        let event = ManagedReplacementTraceEvent(
            timestamp: ProcessInfo.processInfo.systemUptime,
            pid: key.pid,
            workspaceId: key.workspaceId,
            kind: kind
        )
        managedReplacementTrace.append(event)

        if Self.managedReplacementTraceLoggingEnabled {
            Log.ax.debug(
                "[ManagedReplacement] pid=\(key.pid) workspace=\(key.workspaceId.uuidString) kind=\(String(describing: kind))"
            )
        }
    }
}
