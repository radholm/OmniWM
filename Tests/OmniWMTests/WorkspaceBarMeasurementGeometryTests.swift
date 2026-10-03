// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

final class WorkspaceBarMeasurementGeometryTests: XCTestCase {
    private let firstId = WorkspaceDescriptor.ID()
    private let secondId = WorkspaceDescriptor.ID()

    func testFocusChangesPreserveWholeBarGeometryButInvalidateSplitContent() {
        let first = snapshot(firstFocused: true)
        let second = snapshot(firstFocused: false)
        XCTAssertEqual(geometry(first, .all), geometry(second, .all))
        XCTAssertNotEqual(geometry(first, .active), geometry(second, .active))
        XCTAssertNotEqual(geometry(first, .secondary), geometry(second, .secondary))
    }

    func testSizingInputsInvalidateGeometryButUnshownLabelsDoNot() {
        let original = snapshot()
        XCTAssertNotEqual(geometry(original), geometry(snapshot(height: 32)))
        XCTAssertNotEqual(geometry(original), geometry(snapshot(orientation: .vertical)))
        XCTAssertNotEqual(geometry(original), geometry(snapshot(solidBackground: true)))
        XCTAssertNotEqual(geometry(original), geometry(snapshot(firstName: "Long workspace name")))
        XCTAssertEqual(
            geometry(snapshot(showLabels: false)),
            geometry(snapshot(firstName: "Long workspace name", showLabels: false))
        )
    }

    private func geometry(
        _ snapshot: WorkspaceBarSnapshot, _ slice: WorkspaceBarIslandSlice = .all
    ) -> WorkspaceBarMeasurementGeometry {
        WorkspaceBarMeasurementGeometry(snapshot: snapshot, slice: slice)
    }

    private func snapshot(
        firstFocused: Bool = true,
        firstName: String = "1",
        showLabels: Bool = true,
        height: Double = 24,
        orientation: WorkspaceBarOrientation = .horizontal,
        solidBackground: Bool = false
    ) -> WorkspaceBarSnapshot {
        WorkspaceBarSnapshot(
            projection: .init(items: [
                .init(
                    id: firstId,
                    name: firstName,
                    rawName: "1",
                    isFocused: firstFocused,
                    tiledWindows: [],
                    floatingWindows: []
                ),
                .init(
                    id: secondId,
                    name: "Development",
                    rawName: "2",
                    isFocused: !firstFocused,
                    tiledWindows: [],
                    floatingWindows: []
                )
            ], scratchpads: []),
            showLabels: showLabels, showSystemStatsButton: false, backgroundOpacity: 0.1,
            solidBlackBackground: solidBackground, barHeight: height, accentColor: nil, textColor: nil,
            orientation: orientation
        )
    }
}
