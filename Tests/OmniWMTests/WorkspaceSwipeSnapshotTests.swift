// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
@testable import OmniWM
import Synchronization
import XCTest

@MainActor
final class WorkspaceSwipeSnapshotTests: XCTestCase {
    func testRapidPrepareABAWithSameHandlesRejectsOldSuccessAndStopsBeforeNextWindow() async throws {
        let image = try image()
        let old = Gate(image: image)
        let current = Gate(image: image)
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture()
        let preview = try preview(capture: capture, image: image)
        let first = item(1)
        let second = item(2)
        preview.snapshotCapture = { { old.capture($0) } }
        preview.prepare(source: [first, second], destination: [], monitor: monitor, snapshotsSource: true)
        await fulfillment(of: [old.entered], timeout: 1)

        preview.prepare(source: [], destination: [], monitor: monitor, snapshotsSource: true)
        preview.snapshotCapture = { { current.capture($0) } }
        preview.prepare(source: [first, second], destination: [], monitor: monitor, snapshotsSource: true)
        await fulfillment(of: [current.entered], timeout: 1)
        old.release()
        await fulfillment(of: [old.returned], timeout: 1)
        await drain()
        XCTAssertNil(capture.preview(for: first.handle), "Same handle/token must not accept generation A's late frame")
        XCTAssertEqual(old.calls.withLock { $0 }, [1], "Canceled batch must not capture the second window")
        XCTAssertFalse(preview.hasFreshPreviews(source: [first, second], destination: [], monitor: monitor))
        XCTAssertTrue(driver.streams.isEmpty)

        current.release()
        await waitForFresh(preview, items: [first, second])
        XCTAssertEqual(capture.preview(for: first.handle)?.surface.width, 400)
        XCTAssertEqual(capture.preview(for: first.handle)?.surface.height, 300)
        XCTAssertEqual(current.calls.withLock { $0 }, [1, 2])
        preview.stop()
    }

    func testSupersededSnapshotFailureCannotRestartStreamsInReplacementPreparation() async throws {
        let image = try image()
        let old = Gate(image: nil)
        let current = Gate(image: image)
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture()
        let preview = try preview(capture: capture, image: image)
        let item = item(1)
        preview.snapshotCapture = { { old.capture($0) } }
        preview.prepare(source: [item], destination: [], monitor: monitor, snapshotsSource: true)
        await fulfillment(of: [old.entered], timeout: 1)
        preview.prepare(source: [], destination: [], monitor: monitor, snapshotsSource: true)
        preview.snapshotCapture = { { current.capture($0) } }
        preview.prepare(source: [item], destination: [], monitor: monitor, snapshotsSource: true)
        await fulfillment(of: [current.entered], timeout: 1)
        old.release()
        await fulfillment(of: [old.returned], timeout: 1)
        await drain()
        XCTAssertTrue(driver.streams.isEmpty, "Old failure must not reconcile old source fallback requests")
        XCTAssertNil(capture.preview(for: item.handle))
        current.release()
        await waitForFresh(preview, items: [item])
        preview.stop()
    }

    func testStopCancelsCaptureBatchAndPreventsLateFailureFallback() async throws {
        let image = try image()
        let gate = Gate(image: nil)
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture()
        let preview = try preview(capture: capture, image: image)
        let first = item(1)
        preview.snapshotCapture = { { gate.capture($0) } }
        preview.prepare(source: [first, item(2)], destination: [], monitor: monitor, snapshotsSource: true)
        await fulfillment(of: [gate.entered], timeout: 1)
        preview.stop()
        gate.release()
        await fulfillment(of: [gate.returned], timeout: 1)
        await drain()
        XCTAssertEqual(gate.calls.withLock { $0 }, [1])
        XCTAssertTrue(driver.streams.isEmpty)
        XCTAssertEqual(capture.cachedByteCount, 0)
        XCTAssertFalse(preview.isVisible)
    }

    func testRemovedTokenIsSkippedWithoutCancelingOtherSnapshotParticipants() async throws {
        let image = try image()
        let gate = Gate(image: image)
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture()
        let preview = try preview(capture: capture, image: image)
        let first = item(1)
        let removed = item(2)
        let last = item(3)
        preview.snapshotCapture = { { gate.capture($0) } }
        preview.prepare(source: [first, removed, last], destination: [], monitor: monitor, snapshotsSource: true)
        await fulfillment(of: [gate.entered], timeout: 1)
        first.handle.id = WindowToken(pid: 123, windowId: 4)
        preview.remove(token: first.token)
        preview.remove(token: removed.token)
        gate.release()
        await waitForFresh(preview, items: [last])
        XCTAssertEqual(gate.calls.withLock { $0 }, [1, 3])
        XCTAssertNil(capture.preview(for: first.handle), "Removal during capture must reject the returned image")
        XCTAssertNil(capture.preview(for: removed.handle))
        XCTAssertTrue(driver.streams.isEmpty)
        preview.stop()
    }

    func testStopRejectsLateSuccessfulSnapshot() async throws {
        let image = try image()
        let gate = Gate(image: image)
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture()
        let preview = try preview(capture: capture, image: image)
        let item = item(1)
        preview.snapshotCapture = { { gate.capture($0) } }
        preview.prepare(source: [item], destination: [], monitor: monitor, snapshotsSource: true)
        await fulfillment(of: [gate.entered], timeout: 1)
        preview.stop()
        gate.release()
        await fulfillment(of: [gate.returned], timeout: 1)
        await drain()
        XCTAssertNil(capture.preview(for: item.handle))
        XCTAssertFalse(preview.hasFreshPreviews(source: [item], destination: [], monitor: monitor))
        XCTAssertTrue(driver.streams.isEmpty)
    }

    func testRekeyedReusedItemSnapshotsTokenFromCurrentPreparation() async throws {
        let image = try image()
        let gate = Gate(image: image)
        gate.release()
        let capture = OverviewPreviewTestDriver().makeCapture()
        let preview = try preview(capture: capture, image: image)
        let item = item(1)
        item.handle.id = WindowToken(pid: 123, windowId: 2)
        preview.snapshotCapture = { { gate.capture($0) } }
        preview.prepare(source: [item], destination: [], monitor: monitor, snapshotsSource: true)
        await waitForFresh(preview, items: [item])
        XCTAssertEqual(gate.calls.withLock { $0 }, [2])
        XCTAssertNotNil(capture.preview(for: item.handle))
        preview.stop()
    }

    func testCurrentSnapshotFailureFallsBackOnlyForSourceAndDoesNotRestartDestinationStream() async throws {
        let image = try image()
        let gate = Gate(image: nil)
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture()
        let preview = try preview(capture: capture, image: image)
        let source = item(1)
        let destination = item(2)
        preview.snapshotCapture = { { gate.capture($0) } }
        preview.prepare(source: [source], destination: [destination], monitor: monitor, snapshotsSource: true)
        await fulfillment(of: [gate.entered], timeout: 1)
        try await driver.waitForStarts(1)
        driver.completeAllStarts()
        gate.release()
        try await driver.waitForStarts(2)
        XCTAssertEqual(gate.calls.withLock { $0 }, [1], "Parked destinations must never be directly captured")
        XCTAssertEqual(driver.streams.map(\.request.handle), [destination.handle, source.handle])
        driver.completeAllStarts()
        preview.stop()
        try await driver.waitForStops(2)
    }

    private func waitForFresh(_ preview: WorkspaceSwipePreview, items: [WorkspaceSwipePreview.Item]) async {
        for _ in 0 ..< 200 {
            if preview.hasFreshPreviews(source: items, destination: [], monitor: monitor) { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Current snapshot generation did not publish")
    }

    private func drain() async {
        try? await Task.sleep(for: .milliseconds(40))
    }

    private func preview(capture: OverviewThumbnailCapture, image: CGImage) throws -> WorkspaceSwipePreview {
        let wallpaper = OverviewWallpaperCache()
        wallpaper.desktopImageURL = { _ in nil }
        wallpaper.captureWallpaper = { _ in image }
        return WorkspaceSwipePreview(
            ownedWindowRegistry: OwnedWindowRegistry(),
            previewCapture: capture,
            backdrop: WorkspaceSwipeBackdrop(wallpaperCache: wallpaper),
            hasCaptureAccess: { true }
        )
    }

    private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private func item(_ id: Int) -> WorkspaceSwipePreview.Item {
        .init(
            handle: WindowHandle(id: WindowToken(pid: 123, windowId: id)),
            frame: CGRect(x: 50, y: 50, width: 400, height: 300)
        )
    }

    private var monitor: Monitor {
        Monitor(
            id: .init(displayId: 999), displayId: 999,
            frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: CGRect(x: 0, y: 30, width: 1200, height: 750),
            hasNotch: false, name: "Snapshot test"
        )
    }

    private final class Gate: Sendable {
        let entered = XCTestExpectation(description: "snapshot entered")
        let returned = XCTestExpectation(description: "snapshot returned")
        let calls = Mutex<[UInt32]>([])
        private let semaphore = DispatchSemaphore(value: 0)
        private let image: CGImage?

        init(image: CGImage?) {
            self.image = image
        }

        func capture(_ id: UInt32) -> CGImage? {
            let first = calls.withLock {
                $0.append(id)
                return $0.count == 1
            }
            if first {
                entered.fulfill()
                _ = semaphore.wait(timeout: .now() + 3)
                returned.fulfill()
            }
            return image
        }

        func release() {
            semaphore.signal()
        }
    }
}
