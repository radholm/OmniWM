// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import IOSurface
@testable import OmniWM
import QuartzCore
import XCTest

final class OverviewSnapshotFrameTests: XCTestCase {
    func testSnapshotResolutionThresholdsAndAspectRatio() {
        let cases = [
            (2560, 1440, 1280, 720, 1280, 720),
            (1600, 1200, 400, 600, 400, 300),
            (600, 1200, 800, 400, 200, 400),
            (800, 600, 800, 600, 800, 600),
            (800, 600, 801, 601, 800, 600),
            (800, 600, 799, 600, 799, 599),
            (1919, 1079, 1280, 720, 1280, 719),
            (800, 600, 0, 0, 1, 1)
        ]
        for (width, height, requestedWidth, requestedHeight, expectedWidth, expectedHeight) in cases {
            let size = OverviewPreviewFrame.snapshotSize(
                imageWidth: width, imageHeight: height,
                pixelWidth: requestedWidth, pixelHeight: requestedHeight
            )
            XCTAssertEqual(size.width, expectedWidth)
            XCTAssertEqual(size.height, expectedHeight)
            XCTAssertLessThanOrEqual(size.width, max(1, requestedWidth))
            XCTAssertLessThanOrEqual(size.height, max(1, requestedHeight))
            let scale = min(Double(size.width) / Double(width), Double(size.height) / Double(height))
            XCTAssertLessThanOrEqual(abs(Double(size.width) - Double(width) * scale), 1.34)
            XCTAssertLessThanOrEqual(abs(Double(size.height) - Double(height) * scale), 1.34)
        }
    }

    func testRetinaSnapshotAllocatesOneQuarterOfNativeSurfaceBytes() throws {
        let image = try image(width: 2560, height: 1440, color: .red)
        let native = try XCTUnwrap(OverviewPreviewFrame(image: image))
        let sized = try XCTUnwrap(OverviewPreviewFrame(image: image, pixelWidth: 1280, pixelHeight: 720))
        XCTAssertEqual(sized.surface.width, 1280)
        XCTAssertEqual(sized.surface.height, 720)
        XCTAssertEqual(sized.contentsRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertLessThan(Double(sized.surface.allocationSize) / Double(native.surface.allocationSize), 0.251)
        print("Snapshot byte proof: \(native.surface.width)x\(native.surface.height) " +
            "\(native.surface.allocationSize) B -> \(sized.surface.width)x\(sized.surface.height) " +
            "\(sized.surface.allocationSize) B")
    }

    @MainActor
    func testRepeatedSnapshotsNeverOverwriteSurfacesRetainedOnlyByLayerOrCache() throws {
        let red = try image(width: 160, height: 120, color: .red)
        var first: OverviewPreviewFrame? = try XCTUnwrap(
            OverviewPreviewFrame(image: red, pixelWidth: 80, pixelHeight: 60)
        )
        weak let lifetime = first
        let layer = CALayer()
        layer.contents = first?.surface
        let surface = try XCTUnwrap(first?.surface)
        first = nil
        XCTAssertNil(lifetime, "CALayer owns the IOSurface, not the pixel buffer wrapper")
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture()
        let handle = WindowHandle(id: WindowToken(pid: 123, windowId: 456))
        let cached = try XCTUnwrap(OverviewPreviewFrame(image: red, pixelWidth: 80, pixelHeight: 60))
        capture.inject(cached, for: handle)
        let blue = try image(width: 160, height: 120, color: .blue)
        for _ in 0 ..< 32 {
            let next = try XCTUnwrap(OverviewPreviewFrame(image: blue, pixelWidth: 80, pixelHeight: 60))
            XCTAssertFalse(next.surface === surface)
            XCTAssertFalse(next.surface === cached.surface)
        }
        XCTAssertEqual(try redComponent(surface), 255)
        XCTAssertEqual(try redComponent(cached.surface), 255)
        XCTAssertTrue(capture.preview(for: handle) === cached)
        capture.releaseCache()
    }

    private func image(width: Int, height: Int, color: NSColor) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func redComponent(_ surface: IOSurface) throws -> UInt8 {
        XCTAssertEqual(surface.lock(options: .readOnly, seed: nil), 0)
        defer { _ = surface.unlock(options: .readOnly, seed: nil) }
        return surface.baseAddress.assumingMemoryBound(to: UInt8.self)[2]
    }
}
