// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import os

struct AXWriteMetricsBucket: Equatable, Sendable {
    let pid: pid_t
    let callbackGeneration: UInt64
    let app: String?
    let bundleId: String?
    let lane: AppAXFrameLane
    let writeCount: Int
    let failureCount: Int
    let totalNanoseconds: UInt64
    let maxNanoseconds: UInt64

    var meanNanoseconds: UInt64 {
        writeCount == 0 ? 0 : totalNanoseconds / UInt64(writeCount)
    }
}

struct AXWriteMetricsSnapshot: Equatable, Sendable {
    let buckets: [AXWriteMetricsBucket]
    let totalCount: Int
    let totalFailureCount: Int
    let totalNanoseconds: UInt64
    let maxNanoseconds: UInt64

    static let empty = AXWriteMetricsSnapshot(
        buckets: [],
        totalCount: 0,
        totalFailureCount: 0,
        totalNanoseconds: 0,
        maxNanoseconds: 0
    )

    var meanNanoseconds: UInt64 {
        totalCount == 0 ? 0 : totalNanoseconds / UInt64(totalCount)
    }
}

final class AXWriteMetrics: Sendable {
    struct ContextToken: Hashable, Sendable {
        let pid: pid_t
        let callbackGeneration: UInt64
    }

    static let shared = AXWriteMetrics()

    private struct Stat {
        var count = 0
        var failureCount = 0
        var totalNanoseconds: UInt64 = 0
        var maxNanoseconds: UInt64 = 0

        mutating func add(nanoseconds: UInt64, succeeded: Bool) {
            count += 1
            if !succeeded { failureCount += 1 }
            totalNanoseconds &+= nanoseconds
            maxNanoseconds = max(maxNanoseconds, nanoseconds)
        }
    }

    private struct LiveContext {
        let app: String?
        let bundleId: String?
        var lanes: [AppAXFrameLane: Stat] = [:]
    }

    private struct State {
        var lifetime = Stat()
        var live: [ContextToken: LiveContext] = [:]
        var recentByPid: [pid_t: RecentFrameWriteLatency] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func register(_ token: ContextToken, app: String?, bundleId: String?) {
        state.withLock { state in
            guard state.live[token] == nil else { return }
            state.live[token] = LiveContext(app: app, bundleId: bundleId)
        }
    }

    func retire(_ token: ContextToken) {
        state.withLock { state in
            _ = state.live.removeValue(forKey: token)
            if !state.live.keys.contains(where: { $0.pid == token.pid }) {
                state.recentByPid.removeValue(forKey: token.pid)
            }
        }
    }

    /// Whether recent ordinary frame writes to `pid` are slow enough that live
    /// per-frame window animation would visibly stutter.
    func isSlowFrameWriter(pid: pid_t) -> Bool {
        state.withLock { $0.recentByPid[pid]?.isSlow ?? false }
    }

    func record(_ token: ContextToken, lane: AppAXFrameLane, nanoseconds: UInt64, succeeded: Bool) {
        state.withLock { state in
            state.lifetime.add(nanoseconds: nanoseconds, succeeded: succeeded)
            state.live[token]?.lanes[lane, default: Stat()].add(nanoseconds: nanoseconds, succeeded: succeeded)
            if lane == .ordinary {
                state.recentByPid[token.pid, default: RecentFrameWriteLatency()].add(nanoseconds)
            }
        }
    }

    func measure<Value>(
        _ token: ContextToken,
        lane: AppAXFrameLane,
        _ body: () -> Value,
        succeeded: (Value) -> Bool
    ) -> Value {
        let startedNs = DispatchTime.now().uptimeNanoseconds
        let value = body()
        record(
            token,
            lane: lane,
            nanoseconds: DispatchTime.now().uptimeNanoseconds &- startedNs,
            succeeded: succeeded(value)
        )
        return value
    }

    func snapshot() -> AXWriteMetricsSnapshot {
        let (lifetime, live) = state.withLock { ($0.lifetime, $0.live) }
        var buckets = live.flatMap { token, context in
            context.lanes.map { lane, stat in
                AXWriteMetricsBucket(
                    pid: token.pid,
                    callbackGeneration: token.callbackGeneration,
                    app: context.app,
                    bundleId: context.bundleId,
                    lane: lane,
                    writeCount: stat.count,
                    failureCount: stat.failureCount,
                    totalNanoseconds: stat.totalNanoseconds,
                    maxNanoseconds: stat.maxNanoseconds
                )
            }
        }
        buckets.sort { lhs, rhs in
            if lhs.totalNanoseconds != rhs.totalNanoseconds {
                return lhs.totalNanoseconds > rhs.totalNanoseconds
            }
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
            if lhs.callbackGeneration != rhs.callbackGeneration {
                return lhs.callbackGeneration < rhs.callbackGeneration
            }
            return lhs.lane.traceDescription < rhs.lane.traceDescription
        }
        return AXWriteMetricsSnapshot(
            buckets: buckets,
            totalCount: lifetime.count,
            totalFailureCount: lifetime.failureCount,
            totalNanoseconds: lifetime.totalNanoseconds,
            maxNanoseconds: lifetime.maxNanoseconds
        )
    }
}

/// Rolling window of the latest ordinary frame-write latencies for one app.
struct RecentFrameWriteLatency: Equatable, Sendable {
    static let capacity = 16
    static let minimumSamples = 4
    /// About half a 120 Hz frame budget spent inside one app's AX call.
    static let slowMeanNanoseconds: UInt64 = 8_000_000
    static let slowSpikeNanoseconds: UInt64 = 50_000_000

    private(set) var samples: [UInt64] = []
    private var nextIndex = 0

    mutating func add(_ nanoseconds: UInt64) {
        if samples.count < Self.capacity {
            samples.append(nanoseconds)
        } else {
            samples[nextIndex] = nanoseconds
        }
        nextIndex = (nextIndex + 1) % Self.capacity
    }

    var isSlow: Bool {
        guard samples.count >= Self.minimumSamples else { return false }
        let total = samples.reduce(UInt64(0)) { $0 &+ $1 }
        return total / UInt64(samples.count) > Self.slowMeanNanoseconds
            || samples.contains { $0 > Self.slowSpikeNanoseconds }
    }
}
