// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
@testable import OmniWM
import QuartzCore
import XCTest

@MainActor
final class ResizeOverlayControllerTests: XCTestCase {
    private let screenFrame = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testPanelsAppearOnlyForWindowsThatMove() {
        let moving = WindowToken(pid: 1001, windowId: 101)
        let still = WindowToken(pid: 1001, windowId: 102)
        let overlay = makeOverlay(currentFrames: [moving: frame(x: 0, width: 400), still: frame(x: 420, width: 400)])

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .glass, pointerDriven: true)
        let grown = frame(x: 0, width: 480)
        overlay.update([change(moving, grown), change(still, frame(x: 420, width: 400))])

        XCTAssertEqual(Set(overlay.panels.keys), [moving])
        XCTAssertEqual(overlay.panels[moving]?.targetFrame, grown)
        overlay.reset()
    }

    func testTilesShareOneHostWindowThatOutlivesTheSession() throws {
        let left = WindowToken(pid: 1006, windowId: 108)
        let right = WindowToken(pid: 1006, windowId: 109)
        let overlay = makeOverlay(currentFrames: [left: frame(x: 0, width: 400), right: frame(x: 420, width: 400)])
        let workspaceId = WorkspaceDescriptor.ID()

        overlay.begin(workspaceId: workspaceId, style: .glass, pointerDriven: true)
        overlay.update([change(left, frame(x: 0, width: 480)), change(right, frame(x: 500, width: 400))])
        let host = try XCTUnwrap(overlay.panels[left]?.window)
        XCTAssertIdentical(overlay.panels[right]?.window, host)
        XCTAssertEqual(host.frame, screenFrame)
        XCTAssertTrue(host.isVisible)

        overlay.update([change(left, frame(x: 0, width: 520)), change(right, frame(x: 540, width: 400))])
        XCTAssertEqual(host.frame, screenFrame)
        XCTAssertEqual(overlay.panels[right]?.targetFrame, frame(x: 540, width: 400))

        overlay.reset()
        XCTAssertFalse(host.isVisible)
        overlay.begin(workspaceId: workspaceId, style: .glass, pointerDriven: true)
        overlay.update([change(left, frame(x: 0, width: 300))])
        XCTAssertIdentical(overlay.panels[left]?.window, host)
        overlay.reset()
    }

    func testTilesSitInTheirMonitorsCoordinates() throws {
        let token = WindowToken(pid: 1007, windowId: 110)
        let monitor = screenFrame.offsetBy(dx: screenFrame.width, dy: 0)
        let start = CGRect(x: monitor.minX + 420, y: monitor.minY + 20, width: 400, height: 300)
        let overlay = ResizeOverlayController(
            previews: PreviewCaptureCoordinator(ownedWindowRegistry: OwnedWindowRegistry()),
            captureImage: { _, _ in nil },
            currentFrame: { $0 == token ? start : nil },
            monitorFrame: { _ in monitor }
        )
        defer { overlay.reset() }

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .glass, pointerDriven: true)
        overlay.update([change(token, start.insetBy(dx: 40, dy: 0))])

        let tile = try XCTUnwrap(overlay.panels[token])
        XCTAssertEqual(tile.window?.frame, monitor)
        XCTAssertEqual(tile.frame, CGRect(x: 460, y: 20, width: 320, height: 300))
    }

    func testGlassNeverCaptures() {
        let token = WindowToken(pid: 1002, windowId: 103)
        let overlay = makeOverlay(currentFrames: [token: frame(x: 0, width: 400)])

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .glass, pointerDriven: true)
        overlay.update([change(token, frame(x: 0, width: 300))])

        XCTAssertNotNil(overlay.panels[token])
        XCTAssertTrue(overlay.captureTasks.isEmpty)
        XCTAssertEqual(overlay.panels[token]?.isVisible, true)
        overlay.reset()
    }

    func testSnapshotFallsBackToGlassWithoutPermission() {
        let token = WindowToken(pid: 1003, windowId: 104)
        let overlay = makeOverlay(currentFrames: [token: frame(x: 0, width: 400)], captureAllowed: false)

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .snapshot, pointerDriven: true)
        overlay.update([change(token, frame(x: 0, width: 300))])

        XCTAssertEqual(overlay.panels[token]?.isVisible, true)
        XCTAssertTrue(overlay.captureTasks.isEmpty)
        overlay.reset()
    }

    func testSnapshotShowsCapturedImage() async throws {
        let token = WindowToken(pid: 1004, windowId: 105)
        let overlay = makeOverlay(currentFrames: [token: frame(x: 0, width: 400)]) { _, _ in CGImage.blank() }
        defer { overlay.reset() }

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .snapshot, pointerDriven: true)
        overlay.update([change(token, frame(x: 0, width: 300))])
        let capture = try XCTUnwrap(overlay.captureTasks[token])
        XCTAssertEqual(overlay.panels[token]?.showsSnapshot, false)
        await capture.value

        XCTAssertEqual(overlay.panels[token]?.showsSnapshot, true)
    }

    func testLiveStyleNeverStarts() {
        let overlay = makeOverlay(currentFrames: [:])
        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .live, pointerDriven: true)
        XCTAssertFalse(overlay.isActive)
    }

    func testFinishKeepsPanelsUntilTheirWriteLands() {
        let written = WindowToken(pid: 1005, windowId: 106)
        let pending = WindowToken(pid: 1005, windowId: 107)
        let currentFrames = FrameBox([written: frame(x: 0, width: 400), pending: frame(x: 420, width: 400)])
        let overlay = ResizeOverlayController(captureImage: { _, _ in nil }, currentFrame: { currentFrames.map[$0] })
        let workspaceId = WorkspaceDescriptor.ID()
        overlay.begin(workspaceId: workspaceId, style: .glass, pointerDriven: false)
        let writtenTarget = frame(x: 0, width: 480)
        overlay.update([change(written, writtenTarget), change(pending, frame(x: 500, width: 400))])

        currentFrames.map[written] = writtenTarget
        overlay.finish()
        XCTAssertEqual(Set(overlay.panels.keys), [pending])
        XCTAssertFalse(overlay.isTracking(workspaceId))

        overlay.frameApplied(windowId: pending.windowId)
        XCTAssertTrue(overlay.panels.isEmpty)
        XCTAssertFalse(overlay.isActive)
    }

    @MainActor
    private final class FrameBox {
        var map: [WindowToken: CGRect]
        init(_ map: [WindowToken: CGRect]) {
            self.map = map
        }
    }

    private func change(_ token: WindowToken, _ frame: CGRect) -> LayoutFrameChange {
        LayoutFrameChange(token: token, frame: frame, forceApply: false)
    }

    private func frame(x: CGFloat, width: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX + x, y: screenFrame.minY, width: width, height: 300)
    }

    private func makeOverlay(
        currentFrames: [WindowToken: CGRect],
        captureAllowed: Bool = true,
        capture: ResizeOverlayController.ImageCapture? = nil
    ) -> ResizeOverlayController {
        ResizeOverlayController(
            previews: PreviewCaptureCoordinator(ownedWindowRegistry: OwnedWindowRegistry()),
            captureAccessAllowed: { captureAllowed },
            captureImage: capture ?? { _, _ in nil },
            currentFrame: { currentFrames[$0] }
        )
    }
}

extension CGImage {
    fileprivate static func blank() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
