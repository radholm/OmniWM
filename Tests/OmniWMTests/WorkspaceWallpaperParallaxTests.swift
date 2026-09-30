// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceWallpaperParallaxTests: XCTestCase {
    private let monitorFrame = CGRect(x: 100, y: 0, width: 2000, height: 1000)

    func testPositionSpreadsWorkspacesAcrossTheRange() {
        XCTAssertEqual(WorkspaceWallpaperParallax.position(index: 0, count: 5), 0)
        XCTAssertEqual(WorkspaceWallpaperParallax.position(index: 1, count: 5), 0.25)
        XCTAssertEqual(WorkspaceWallpaperParallax.position(index: 4, count: 5), 1)
        XCTAssertEqual(WorkspaceWallpaperParallax.position(index: 0, count: 1), 0.5)
        XCTAssertEqual(WorkspaceWallpaperParallax.position(index: 7, count: 3), 1)
    }

    func testHorizontalFramePansFromLeftEdgeToRightEdge() {
        let start = WorkspaceWallpaperParallax.frame(for: monitorFrame, position: 0, axis: .horizontal)
        let end = WorkspaceWallpaperParallax.frame(for: monitorFrame, position: 1, axis: .horizontal)
        XCTAssertEqual(start.size, CGSize(width: 2200, height: 1100))
        XCTAssertEqual(start.minX, monitorFrame.minX)
        XCTAssertEqual(end.maxX, monitorFrame.maxX)
        XCTAssertEqual(start.midY, monitorFrame.midY)
        XCTAssertEqual(end.midY, monitorFrame.midY)
        for position in stride(from: 0.0, through: 1.0, by: 0.25) {
            let frame = WorkspaceWallpaperParallax.frame(for: monitorFrame, position: position, axis: .horizontal)
            XCTAssertTrue(frame.contains(monitorFrame), "position \(position) must cover the display")
        }
    }

    func testVerticalFramePansFromTopEdgeToBottomEdge() {
        let start = WorkspaceWallpaperParallax.frame(for: monitorFrame, position: 0, axis: .vertical)
        let end = WorkspaceWallpaperParallax.frame(for: monitorFrame, position: 1, axis: .vertical)
        XCTAssertEqual(start.maxY, monitorFrame.maxY)
        XCTAssertEqual(end.minY, monitorFrame.minY)
        XCTAssertEqual(start.midX, monitorFrame.midX)
    }

    func testOverscanSetsHowFarTheWallpaperPans() {
        let start = WorkspaceWallpaperParallax.frame(
            for: monitorFrame, position: 0, axis: .horizontal, overscan: 0.3
        )
        let end = WorkspaceWallpaperParallax.frame(for: monitorFrame, position: 1, axis: .horizontal, overscan: 0.3)
        XCTAssertEqual(start.minX - end.minX, 600, accuracy: 0.001)
        XCTAssertEqual(start.size, CGSize(width: 2600, height: 1300))
    }

    func testParallaxAmountNormalizes() {
        let settings = GestureSettings()
        XCTAssertEqual(settings.workspaceWallpaperParallaxAmount, 0.1)
        for (value, expected) in [(Double.nan, 0.1), (0, 0.02), (9, 0.5), (0.25, 0.25)] {
            settings.workspaceWallpaperParallaxAmount = value
            XCTAssertEqual(settings.workspaceWallpaperParallaxAmount, expected)
        }
        var gestures = settings.export()
        gestures.workspaceWallpaperParallaxAmount = nil
        XCTAssertEqual(gestures.normalized().workspaceWallpaperParallaxAmount, 0.1)
    }

    func testInterpolateBlendsFrames() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 50)
        let to = CGRect(x: -20, y: 10, width: 100, height: 50)
        XCTAssertEqual(
            WorkspaceWallpaperParallax.interpolate(from, to, progress: 0.5),
            CGRect(x: -10, y: 5, width: 100, height: 50)
        )
    }

    func testSettingDefaultsOnAndRoundTrips() throws {
        XCTAssertEqual(SettingsExport.defaults().gestures.workspaceWallpaperParallax, true)
        var gestures = SettingsExport.defaults().gestures
        gestures.workspaceWallpaperParallax = nil
        XCTAssertEqual(gestures.normalized().workspaceWallpaperParallax, true)

        var export = SettingsExport.defaults()
        export.gestures.workspaceWallpaperParallax = false
        export.gestures.workspaceWallpaperParallaxAmount = 0.2
        let encoded = try SettingsTOMLCodec.encode(export)
        XCTAssertEqual(try SettingsTOMLCodec.decode(encoded), export)
        XCTAssertTrue(SettingsTOMLCodec.unknownKeyPaths(in: encoded).isEmpty)
    }
}
