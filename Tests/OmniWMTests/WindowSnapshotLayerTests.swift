// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class WindowSnapshotLayerTests: XCTestCase {
    func testCropRectKeepsAspectAndAnchorsTopLeft() {
        let wider = WindowSnapshotLayer.cropRect(
            frameSize: CGSize(width: 2000, height: 1000),
            imageSize: CGSize(width: 1000, height: 1000)
        )
        XCTAssertEqual(wider, CGRect(x: 0, y: 0.5, width: 1, height: 0.5))

        let narrower = WindowSnapshotLayer.cropRect(
            frameSize: CGSize(width: 500, height: 1000),
            imageSize: CGSize(width: 1000, height: 1000)
        )
        XCTAssertEqual(narrower, CGRect(x: 0, y: 0, width: 0.5, height: 1))

        let same = WindowSnapshotLayer.cropRect(
            frameSize: CGSize(width: 400, height: 300),
            imageSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(same, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testPeakBlurScalesWithChangeAndSkipsTinyMoves() {
        let start = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(WindowSnapshotLayer.peakBlur(from: start, to: start.insetBy(dx: 5, dy: 5)), 0)
        XCTAssertEqual(
            WindowSnapshotLayer.peakBlur(from: start, to: CGRect(x: 0, y: 0, width: 2000, height: 800)),
            WindowSnapshotLayer.maxBlur
        )
        let small = WindowSnapshotLayer.peakBlur(from: start, to: CGRect(x: 0, y: 0, width: 1100, height: 800))
        XCTAssertGreaterThan(small, 0)
        XCTAssertLessThan(small, WindowSnapshotLayer.maxBlur)
    }
}
