// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

final class SingleWindowFitTests: XCTestCase {
    func testDefaultIsFullScreen() {
        XCTAssertEqual(SingleWindowFit().mode, .fill)
        XCTAssertEqual(SingleWindowFit.fullScreen.mode, .fill)
    }

    func testSerializedRoundTrips() {
        XCTAssertEqual(SingleWindowFit(mode: .fill).serialized, "fill")
        XCTAssertEqual(SingleWindowFit(mode: .custom, width: 1920, height: 1080).serialized, "1920x1080")
        XCTAssertEqual(SingleWindowFit(mode: .custom, width: 1600, height: 900).serialized, "1600x900")
    }

    func testDecodeNewFormats() {
        XCTAssertEqual(SingleWindowFit(serialized: "fill"), SingleWindowFit(mode: .fill))
        XCTAssertEqual(
            SingleWindowFit(serialized: "1920x1080"),
            SingleWindowFit(mode: .custom, width: 1920, height: 1080)
        )
        XCTAssertEqual(
            SingleWindowFit(serialized: " 1600X900 "),
            SingleWindowFit(mode: .custom, width: 1600, height: 900)
        )
    }

    func testDecodeGarbageIsRejected() {
        for serialized in ["", "wat", "0x0", "-5x100", "ax9", "column_width", "column-width", "columnwidth"] {
            XCTAssertNil(SingleWindowFit(serialized: serialized), serialized)
        }
    }

    func testFrameFillReturnsWorkingFrame() {
        let working = CGRect(x: 100, y: 50, width: 2000, height: 1200)
        XCTAssertEqual(SingleWindowFit(mode: .fill).frame(in: working), working)
    }

    func testFrameCustomCentersWhenSmaller() {
        let working = CGRect(x: 100, y: 50, width: 2000, height: 1200)
        let frame = SingleWindowFit(mode: .custom, width: 1920, height: 1080).frame(in: working)
        XCTAssertEqual(frame, CGRect(x: 140, y: 110, width: 1920, height: 1080))
    }

    func testFrameCustomClampsWhenLarger() {
        let working = CGRect(x: 100, y: 50, width: 2000, height: 1200)
        let frame = SingleWindowFit(mode: .custom, width: 3000, height: 1500).frame(in: working)
        XCTAssertEqual(frame, working)
    }

    func testFrameCustomInvalidSizeFallsBackToWorkingFrame() {
        let working = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(SingleWindowFit(mode: .custom, width: 0, height: 1080).frame(in: working), working)
        XCTAssertEqual(SingleWindowFit(mode: .custom, width: 1920, height: -1).frame(in: working), working)
    }

    func testSettingsTOMLRoundTripsSingleWindowFitKeys() throws {
        var export = SettingsExport.defaults()
        export.dwindle.singleWindowFit = SingleWindowFit(mode: .custom, width: 1280, height: 720)
        export.monitorDwindleSettings = [
            MonitorDwindleSettings(
                monitorName: "Landscape",
                singleWindowFit: SingleWindowFit(mode: .custom, width: 1024, height: 768)
            )
        ]

        let data = try SettingsTOMLCodec.encode(export)
        let toml = String(decoding: data, as: UTF8.self)
        let decoded = try SettingsTOMLCodec.decode(data)

        XCTAssertTrue(toml.contains("singleWindowFit"))
        XCTAssertFalse(toml.contains("singleWindowAspectRatio"))
        XCTAssertEqual(decoded.dwindle.singleWindowFit.serialized, "1280x720")
        XCTAssertEqual(decoded.monitorDwindleSettings.first?.singleWindowFit?.serialized, "1024x768")
    }

    func testLegacySingleWindowAspectRatioKeysAreIgnoredAndDiagnosed() throws {
        var export = SettingsExport.defaults()
        export.dwindle.singleWindowFit = SingleWindowFit(mode: .custom, width: 1280, height: 720)
        export.monitorDwindleSettings = [
            MonitorDwindleSettings(
                monitorName: "Landscape",
                singleWindowFit: SingleWindowFit(mode: .custom, width: 1024, height: 768)
            )
        ]

        let canonical = String(decoding: try SettingsTOMLCodec.encode(export), as: UTF8.self)
        let legacy = Data(
            canonical
                .split(separator: "\n", omittingEmptySubsequences: false)
                .flatMap { line -> [Substring] in
                    guard line.contains("singleWindowFit") else { return [line] }
                    return [
                        line,
                        Substring(line.replacingOccurrences(
                            of: "singleWindowFit",
                            with: "singleWindowAspectRatio"
                        ))
                    ]
                }
                .joined(separator: "\n")
                .utf8
        )
        let decoded = try SettingsTOMLCodec.decode(legacy)
        let unknownKeys = Set(SettingsTOMLCodec.unknownKeyPaths(in: legacy))
        XCTAssertEqual(decoded.dwindle.singleWindowFit, export.dwindle.singleWindowFit)
        XCTAssertTrue(unknownKeys.contains("dwindle.singleWindowAspectRatio"))
        XCTAssertTrue(unknownKeys.contains("monitorDwindleOverrides[0].singleWindowAspectRatio"))
    }
}

final class DwindleSingleWindowFitEngineTests: XCTestCase {
    private struct Fixture {
        let engine: DwindleLayoutEngine
        let workspaceId: WorkspaceDescriptor.ID
        let token: WindowToken
    }

    private func makeSingleWindowFixture() -> Fixture {
        let engine = DwindleLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()
        let token = WindowToken(pid: 1, windowId: 1)
        _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        return Fixture(engine: engine, workspaceId: workspaceId, token: token)
    }

    func testFullScreenFillsTheScreen() {
        let fixture = makeSingleWindowFixture()
        fixture.engine.settings.singleWindowFit = SingleWindowFit(mode: .fill)
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let frame = fixture.engine.calculateLayout(for: fixture.workspaceId, screen: screen)[fixture.token]

        XCTAssertEqual(frame, screen)
    }

    func testCustomSizeIsCenteredAndFinite() {
        let fixture = makeSingleWindowFixture()
        fixture.engine.settings.singleWindowFit = SingleWindowFit(mode: .custom, width: 1920, height: 1080)
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let frame = fixture.engine.calculateLayout(for: fixture.workspaceId, screen: screen)[fixture.token]

        XCTAssertEqual(frame, CGRect(x: 320, y: 180, width: 1920, height: 1080))
        XCTAssertEqual(frame?.height.isFinite, true)
    }

    func testFillUsesBorderSafeFrameWhileFullscreenUsesFullscreenFrame() {
        let fixture = makeSingleWindowFixture()
        fixture.engine.settings.singleWindowFit = SingleWindowFit(mode: .fill)
        let workingFrame = CGRect(x: 24, y: 16, width: 1200, height: 760)
        let borderSafeFillFrame = CGRect(x: 8, y: 8, width: 1264, height: 784)
        let fullscreenFrame = CGRect(x: 0, y: 0, width: 1280, height: 800)

        let fillFrame = fixture.engine.calculateLayout(
            for: fixture.workspaceId,
            screen: workingFrame,
            borderSafeFillScreen: borderSafeFillFrame,
            fullscreenScreen: fullscreenFrame
        )[fixture.token]
        _ = fixture.engine.toggleFullscreen(in: fixture.workspaceId)
        let fullscreenResult = fixture.engine.calculateLayout(
            for: fixture.workspaceId,
            screen: workingFrame,
            borderSafeFillScreen: borderSafeFillFrame,
            fullscreenScreen: fullscreenFrame
        )[fixture.token]

        XCTAssertEqual(fillFrame, borderSafeFillFrame)
        XCTAssertEqual(fullscreenResult, fullscreenFrame)
    }

    func testInvalidCustomFitUsesBorderSafeFrame() {
        let fixture = makeSingleWindowFixture()
        fixture.engine.settings.singleWindowFit = SingleWindowFit(mode: .custom, width: .infinity, height: 600)
        let workingFrame = CGRect(x: 24, y: 16, width: 1200, height: 760)
        let borderSafeFillFrame = CGRect(x: 8, y: 8, width: 1264, height: 784)
        let fullscreenFrame = CGRect(x: 0, y: 0, width: 1280, height: 800)

        let frame = fixture.engine.calculateLayout(
            for: fixture.workspaceId,
            screen: workingFrame,
            borderSafeFillScreen: borderSafeFillFrame,
            fullscreenScreen: fullscreenFrame
        )[fixture.token]
        XCTAssertEqual(frame, borderSafeFillFrame)
    }

    func testCustomFitStaysBoundedByWorkingFrame() {
        let fixture = makeSingleWindowFixture()
        fixture.engine.settings.singleWindowFit = SingleWindowFit(mode: .custom, width: 800, height: 600)
        let workingFrame = CGRect(x: 24, y: 16, width: 1200, height: 760)
        let fullscreenFrame = CGRect(x: 0, y: 0, width: 1280, height: 800)

        let frame = fixture.engine.calculateLayout(
            for: fixture.workspaceId,
            screen: workingFrame,
            fullscreenScreen: fullscreenFrame
        )[fixture.token]

        XCTAssertEqual(frame, CGRect(x: 224, y: 96, width: 800, height: 600))
    }

    func testFullscreenLeafInMultiWindowLayoutUsesFullscreenLayoutFrame() {
        let engine = DwindleLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()
        let first = WindowToken(pid: 1, windowId: 1)
        let second = WindowToken(pid: 2, windowId: 2)
        _ = engine.addWindow(token: first, to: workspaceId, activeWindowFrame: nil)
        _ = engine.addWindow(token: second, to: workspaceId, activeWindowFrame: nil)
        _ = engine.toggleFullscreen(in: workspaceId)
        let workingFrame = CGRect(x: 24, y: 16, width: 1200, height: 760)
        let fullscreenFrame = CGRect(x: 0, y: 0, width: 1280, height: 800)

        let frames = engine.calculateLayout(
            for: workspaceId,
            screen: workingFrame,
            fullscreenScreen: fullscreenFrame
        )

        XCTAssertEqual(frames[second], fullscreenFrame)
        // The other windows stack underneath the fullscreen one so paging through them only reveals them.
        XCTAssertEqual(frames[first], fullscreenFrame)
    }
}
