// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class SlowFrameWriterTests: XCTestCase {
    func testRecentLatencyNeedsSamplesAndFlagsSlowMeanOrSpike() {
        var latency = RecentFrameWriteLatency()
        for _ in 0 ..< 3 { latency.add(20_000_000) }
        XCTAssertFalse(latency.isSlow)
        latency.add(20_000_000)
        XCTAssertTrue(latency.isSlow)

        var fast = RecentFrameWriteLatency()
        for _ in 0 ..< 16 { fast.add(2_000_000) }
        XCTAssertFalse(fast.isSlow)
        fast.add(120_000_000)
        XCTAssertTrue(fast.isSlow)
        for _ in 0 ..< 16 { fast.add(2_000_000) }
        XCTAssertFalse(fast.isSlow, "old spikes roll out of the window")
        XCTAssertEqual(fast.samples.count, RecentFrameWriteLatency.capacity)
    }

    @MainActor
    func testOnlyMovedSlowWindowsRouteToSnapshots() {
        let slow = WindowToken(pid: 10, windowId: 1)
        let fast = WindowToken(pid: 20, windowId: 2)
        let a = CGRect(x: 0, y: 0, width: 500, height: 500)
        let b = CGRect(x: 500, y: 0, width: 500, height: 500)
        let isSlow: (pid_t) -> Bool = { $0 == 10 }

        let fastMoves = DwindleFrameTransition(
            oldFrames: [slow: a, fast: b],
            previousTargetFrames: [slow: a, fast: b],
            newFrames: [slow: a, fast: b.insetBy(dx: 50, dy: 0)]
        )
        XCTAssertFalse(DwindleLayoutHandler.movesSlowFrameWriter(fastMoves, isSlow: isSlow))

        let slowMoves = DwindleFrameTransition(
            oldFrames: [slow: a, fast: b],
            previousTargetFrames: [slow: a, fast: b],
            newFrames: [slow: b, fast: a]
        )
        XCTAssertTrue(DwindleLayoutHandler.movesSlowFrameWriter(slowMoves, isSlow: isSlow))
        XCTAssertFalse(DwindleLayoutHandler.movesSlowFrameWriter(slowMoves, isSlow: { _ in false }))
    }
}
