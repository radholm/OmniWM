// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class OverviewPreviewCancellationTests: XCTestCase {
    func testLateFactoryControlIsStoppedWithoutStartingAfterClear() async throws {
        let entered = expectation(description: "factory entered")
        var continuation: CheckedContinuation<any OverviewPreviewStreamControl, Never>?
        var control: OverviewPreviewTestStream?
        var startCount = 0
        let capture = OverviewThumbnailCapture(
            environment: OverviewEnvironment(),
            ownedWindowRegistry: OwnedWindowRegistry(),
            hasCaptureAccess: { true },
            streamFactory: { request, output in
                let stream = OverviewPreviewTestStream(
                    request: request, output: output,
                    onStart: { startCount += 1 }, onStop: {}
                )
                control = stream
                return await withCheckedContinuation {
                    continuation = $0
                    entered.fulfill()
                }
            }
        )
        let handle = WindowHandle(id: WindowToken(pid: 123, windowId: 456))
        capture.reconcile(represented: [handle], visible: [
            OverviewPreviewRequest(handle: handle, pixelWidth: 80, pixelHeight: 60)
        ])
        await fulfillment(of: [entered], timeout: 1)
        capture.clear()
        let stream = try XCTUnwrap(control)
        continuation?.resume(returning: stream)
        for _ in 0 ..< 200 {
            if stream.stopCount > 0 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(stream.stopCount, 1)
        XCTAssertEqual(startCount, 0, "Canceled factory results must not start obsolete streams")
        stream.output.offer(try makeOverviewPreviewFrame())
        XCTAssertNil(stream.output.take())
        XCTAssertNil(capture.preview(for: handle))
        XCTAssertFalse(capture.hasPendingFirstFrames)
    }

    func testImmediatelySupersededQueuedStartNeverEntersFactory() async {
        var factoryCalls = 0
        let capture = OverviewThumbnailCapture(
            environment: OverviewEnvironment(),
            ownedWindowRegistry: OwnedWindowRegistry(),
            hasCaptureAccess: { true },
            streamFactory: { request, output in
                factoryCalls += 1
                return OverviewPreviewTestStream(request: request, output: output, onStart: {}, onStop: {})
            }
        )
        let handle = WindowHandle(id: WindowToken(pid: 123, windowId: 456))
        capture.reconcile(represented: [handle], visible: [
            OverviewPreviewRequest(handle: handle, pixelWidth: 80, pixelHeight: 60)
        ])
        capture.clear()
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertFalse(capture.hasPendingFirstFrames)
    }

    func testRapidReconcileABARejectsOldStreamWithSameHandleAndToken() async throws {
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture()
        let first = WindowHandle(id: WindowToken(pid: 123, windowId: 1))
        let second = WindowHandle(id: WindowToken(pid: 123, windowId: 2))
        let requestA = OverviewPreviewRequest(handle: first, pixelWidth: 80, pixelHeight: 60)
        let requestB = OverviewPreviewRequest(handle: second, pixelWidth: 80, pixelHeight: 60)
        capture.reconcile(represented: [first], visible: [requestA])
        await driver.waitForStarts(1)
        capture.reconcile(represented: [second], visible: [requestB])
        await driver.waitForStarts(2)
        capture.reconcile(represented: [first], visible: [requestA])
        await driver.waitForStarts(3)
        let old = driver.streams[0]
        let current = driver.streams[2]
        XCTAssertTrue(old.request.handle === current.request.handle)
        XCTAssertEqual(old.request.token, current.request.token)
        old.output.offer(try makeOverviewPreviewFrame())
        XCTAssertNil(old.output.take())
        XCTAssertNil(capture.preview(for: first))
        driver.completeAllStarts()
        await driver.waitForStops(2)
        let frame = try makeOverviewPreviewFrame()
        let published = expectation(description: "replacement frame")
        capture.onPreview = { _, preview in if preview === frame { published.fulfill() } }
        current.output.offer(frame)
        await fulfillment(of: [published], timeout: 1)
        XCTAssertTrue(capture.preview(for: first) === frame)
        capture.clear()
        await driver.waitForStops(3)
    }
}
