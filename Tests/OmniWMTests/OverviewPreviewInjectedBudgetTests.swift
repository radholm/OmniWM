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
            XCTAssertEqual(capture.residentByteCount, 0)
        }
        XCTAssertNil(capture.preview(for: handles[0]))
        XCTAssertNotNil(capture.preview(for: handles[1]))
        XCTAssertNotNil(capture.preview(for: handles[2]))
        capture.inject(larger, for: handles[2])
        XCTAssertNil(capture.preview(for: handles[2]), "An oversized idle injection must not evade eviction")
        XCTAssertEqual(capture.cachedByteCount, small.surface.allocationSize)
        capture.releaseCache()
    }

    func testResidentSnapshotsConsumeBudgetWithoutBlankingActivePreviewThenTrimOnEnd() throws {
        let frame = try makeOverviewPreviewFrame()
        let driver = OverviewPreviewTestDriver()
        let budget = frame.surface.allocationSize
        let capture = driver.makeCapture(maximumRetainedBytes: budget)
        let first = WindowHandle(id: WindowToken(pid: 123, windowId: 1))
        let second = WindowHandle(id: WindowToken(pid: 123, windowId: 2))
        let idle = WindowHandle(id: WindowToken(pid: 123, windowId: 3))
        capture.inject(try makeOverviewPreviewFrame(), for: idle)
        capture.reconcile(represented: [first, second], visible: [], retainingUnrepresentedPreviews: true)
        capture.inject(try makeOverviewPreviewFrame(), for: first)
        XCTAssertNil(capture.preview(for: idle))
        capture.inject(try makeOverviewPreviewFrame(), for: second)
        XCTAssertEqual(capture.residentByteCount, budget * 2)
        XCTAssertEqual(capture.retainedByteCount, 0)
        capture.releaseCache(reason: .memoryPressure)
        XCTAssertNotNil(capture.preview(for: first))
        XCTAssertNotNil(capture.preview(for: second))
        capture.clear()
        XCTAssertEqual(capture.residentByteCount, 0)
        XCTAssertEqual(capture.retainedByteCount, budget)
        XCTAssertNil(capture.preview(for: first))
        XCTAssertNotNil(capture.preview(for: second))
        capture.releaseCache()
        XCTAssertEqual(capture.cachedByteCount, 0)
    }

    func testChangingRepresentedHandlesTrimsInjectedHistoryBeforeClear() throws {
        let frame = try makeOverviewPreviewFrame()
        let capture = OverviewPreviewTestDriver().makeCapture(maximumRetainedBytes: frame.surface.allocationSize)
        let handles = (1 ... 3).map { WindowHandle(id: WindowToken(pid: 123, windowId: $0)) }
        capture.reconcile(represented: Set(handles), visible: [], retainingUnrepresentedPreviews: true)
        for handle in handles { capture.inject(try makeOverviewPreviewFrame(), for: handle) }
        XCTAssertEqual(capture.cachedByteCount, frame.surface.allocationSize * 3)
        capture.reconcile(represented: [handles[2]], visible: [], retainingUnrepresentedPreviews: true)
        XCTAssertEqual(capture.cachedByteCount, frame.surface.allocationSize)
        XCTAssertEqual(capture.retainedByteCount, 0)
        XCTAssertNotNil(capture.preview(for: handles[2]))
        capture.clear()
    }

    func testRemovingTokenClearsResidencyEvenBeforeItsFirstSnapshotArrives() throws {
        let frame = try makeOverviewPreviewFrame()
        let capture = OverviewPreviewTestDriver().makeCapture(maximumRetainedBytes: 0)
        let handle = WindowHandle(id: WindowToken(pid: 123, windowId: 1))
        capture.reconcile(represented: [handle], visible: [], retainingUnrepresentedPreviews: true)
        capture.remove(token: handle.token)
        capture.inject(frame, for: handle)
        XCTAssertEqual(capture.residentByteCount, 0)
        XCTAssertEqual(capture.retainedByteCount, 0)
        XCTAssertNil(capture.preview(for: handle))
    }
}
