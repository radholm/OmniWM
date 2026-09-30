// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import os
import XCTest

@MainActor
final class WindowSnapshotTransitionTests: XCTestCase {
    func testBeginFallsBackWithoutCaptureAccess() throws {
        let transition = try makeTransition(hasCaptureAccess: false)
        XCTAssertFalse(transition.begin(items: [item()], monitor: monitor, animated: true))
        XCTAssertFalse(transition.isActive)
    }

    func testBeginFallsBackWhenAnyWindowCaptureFails() throws {
        let transition = try makeTransition(capture: { $0 == 1 ? try? self.makeImage() : nil })
        let items = [item(windowId: 1), item(windowId: 2)]
        XCTAssertFalse(transition.begin(items: items, monitor: monitor, animated: true))
        XCTAssertFalse(transition.isActive)
    }

    func testBeginIgnoresParkedWindows() throws {
        var captured: [Int] = []
        let transition = try makeTransition(capture: { captured.append($0)
            return try? self.makeImage()
        })
        let parked = WindowSnapshotTransition.Item(
            windowId: 2,
            from: CGRect(x: 1195, y: 50, width: 400, height: 300),
            to: CGRect(x: 1195, y: 50, width: 400, height: 300)
        )
        XCTAssertTrue(transition.begin(items: [item(windowId: 1), parked], monitor: monitor, animated: true))
        XCTAssertEqual(captured, [1])
        transition.stop()
    }

    func testRetargetReusesSnapshotsAndStopCloses() throws {
        var captureCount = 0
        let transition = try makeTransition(capture: { _ in captureCount += 1
            return try? self.makeImage()
        })
        XCTAssertTrue(transition.begin(items: [item()], monitor: monitor, animated: true))
        XCTAssertTrue(transition.isActive)
        let retarget = WindowSnapshotTransition.Item(
            windowId: 1,
            from: CGRect(x: 50, y: 50, width: 400, height: 300),
            to: CGRect(x: 0, y: 30, width: 1200, height: 750)
        )
        XCTAssertTrue(transition.begin(items: [retarget], monitor: monitor, animated: true))
        transition.update(frames: [1: CGRect(x: 10, y: 40, width: 600, height: 700)])
        XCTAssertEqual(captureCount, 1)
        transition.stop()
        XCTAssertFalse(transition.isActive)
    }

    func testAppearingWindowPopsInAtTargetFrame() throws {
        let transition = try makeTransition()
        let appearing = WindowSnapshotTransition.Item(
            windowId: 3,
            from: CGRect(x: 300, y: 200, width: 500, height: 400),
            to: CGRect(x: 600, y: 30, width: 600, height: 750),
            appearing: true
        )
        XCTAssertTrue(transition.begin(items: [item(), appearing], monitor: monitor, animated: true))
        XCTAssertTrue(transition.isActive)
        transition.stop()
    }

    func testOnScreenAppearingWindowLeavesFadingGhost() {
        let display = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let onScreen = WindowSnapshotTransition.Item(
            windowId: 3,
            from: CGRect(x: 500, y: 40, width: 500, height: 700),
            to: CGRect(x: 600, y: 30, width: 600, height: 750),
            appearing: true
        )
        let offScreen = WindowSnapshotTransition.Item(
            windowId: 4,
            from: CGRect(x: 1195, y: 50, width: 400, height: 300),
            to: CGRect(x: 0, y: 30, width: 600, height: 750),
            appearing: true
        )
        let resolved = WindowSnapshotTransition.resolvingAppearance([onScreen, offScreen], in: display)
        XCTAssertEqual(resolved.map(\.appearing), [true, true])
        XCTAssertEqual(resolved.map(\.leavesGhost), [true, false])
        XCTAssertEqual(resolved.map(\.from), [onScreen.from, offScreen.from])
    }

    func testFinishRecapturesSettledWindowsBeforeClosing() async throws {
        var captureCount = 0
        let transition = try makeTransition(capture: { _ in captureCount += 1
            return try? self.makeImage()
        })
        XCTAssertTrue(transition.begin(items: [item()], monitor: monitor, animated: true))
        transition.finish(after: WindowSnapshotTransition.duration, settled: { true })
        for _ in 0 ..< 100 where transition.isActive {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(transition.isActive)
        XCTAssertEqual(captureCount, 2)
    }

    func testFinishRecapturesOffTheMainThreadWhenBackgroundCaptureIsAvailable() async throws {
        let image = try makeImage()
        let offMainCaptures = OSAllocatedUnfairLock(initialState: 0)
        var mainCaptures = 0
        let transition = try makeTransition(
            capture: { _ in mainCaptures += 1
                return image
            },
            backgroundCapture: { _ in
                offMainCaptures.withLock { $0 += Thread.isMainThread ? 0 : 1 }
                return image
            }
        )
        XCTAssertTrue(transition.begin(items: [item()], monitor: monitor, animated: true))
        transition.finish(after: WindowSnapshotTransition.duration, settled: { true })
        for _ in 0 ..< 100 where transition.isActive {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(transition.isActive)
        XCTAssertEqual(mainCaptures, 1)
        XCTAssertEqual(offMainCaptures.withLock { $0 }, 1)
    }

    func testFinishClosesOverlayOnceSettled() async throws {
        let transition = try makeTransition()
        XCTAssertTrue(transition.begin(items: [item()], monitor: monitor, animated: false))
        transition.finish(after: 0, settled: { true })
        for _ in 0 ..< 100 where transition.isActive {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(transition.isActive)
    }

    private func makeTransition(
        hasCaptureAccess: Bool = true,
        capture: (@MainActor (Int) -> CGImage?)? = nil,
        backgroundCapture: (@Sendable (Int) -> CGImage?)? = nil
    ) throws -> WindowSnapshotTransition {
        let image = try makeImage()
        let wallpaper = try makeImage(width: 1200, height: 800)
        let cache = OverviewWallpaperCache()
        cache.desktopImageURL = { _ in nil }
        cache.captureWallpaper = { _ in wallpaper }
        return WindowSnapshotTransition(
            ownedWindowRegistry: OwnedWindowRegistry(),
            backdrop: WorkspaceSwipeBackdrop(wallpaperCache: cache),
            captureWindow: capture ?? { _ in image },
            hasCaptureAccess: { hasCaptureAccess },
            backgroundCapture: backgroundCapture
        )
    }

    private func makeImage(width: Int = 400, height: Int = 300) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private var monitor: Monitor {
        Monitor(
            id: .init(displayId: 999), displayId: 999,
            frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: CGRect(x: 0, y: 30, width: 1200, height: 750),
            hasNotch: false, name: "Snapshot test"
        )
    }

    private func item(windowId: Int = 1) -> WindowSnapshotTransition.Item {
        .init(
            windowId: windowId,
            from: CGRect(x: 50, y: 50, width: 400, height: 300),
            to: CGRect(x: 0, y: 30, width: 600, height: 750)
        )
    }
}
