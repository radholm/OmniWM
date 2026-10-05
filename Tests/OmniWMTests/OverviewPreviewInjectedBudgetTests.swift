// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class OverviewPreviewInjectedBudgetTests: XCTestCase {
    func testEveryInjectionEnforcesRetainedBudgetIncludingReplacementAndOversize() throws {
        let small = try makeOverviewPreviewFrame()
        let larger = try makeOverviewPreviewFrame(width: 160, height: 120)
        let budget = small.surface.allocationSize * 2
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture(maximumRetainedBytes: budget)
        let handles = (1 ... 3).map { WindowHandle(id: WindowToken(pid: 123, windowId: $0)) }
        for handle in handles {
            capture.inject(try makeOverviewPreviewFrame(), for: handle)
            XCTAssertLessThanOrEqual(capture.cachedByteCount, budget)
        }
        XCTAssertNil(capture.preview(for: handles[0]))
        XCTAssertNotNil(capture.preview(for: handles[1]))
        XCTAssertNotNil(capture.preview(for: handles[2]))
        capture.inject(larger, for: handles[2])
        XCTAssertNil(capture.preview(for: handles[2]), "An oversized idle injection must not evade eviction")
        XCTAssertEqual(capture.cachedByteCount, small.surface.allocationSize)
        capture.releaseCache()
    }
}
