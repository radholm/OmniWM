// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class OverviewGestureConflictTests: XCTestCase {
    func testOverlapsMatchEnabledMovementAndFingerCount() {
        for fingers in [3, 4] {
            var config = TrackpadGestureIntent.Config(
                workspaceSwipeEnabled: false,
                workspaceSwipeFingerCount: fingers,
                workspaceSwipeAxis: .horizontal,
                overviewAction: .open,
                overviewFingerCount: fingers
            )
            XCTAssertNil(TrackpadGestureIntent.overviewConflict(config))
            XCTAssertNil(TrackpadGestureIntent.overviewConflict(config))

            config.workspaceSwipeEnabled = true
            XCTAssertNil(TrackpadGestureIntent.overviewConflict(config))
            config.workspaceSwipeAxis = .vertical
            XCTAssertEqual(
                TrackpadGestureIntent.overviewConflict(config),
                .workspaceSwitch(axis: .vertical)
            )
            config.overviewFingerCount = 7 - fingers
            XCTAssertNil(TrackpadGestureIntent.overviewConflict(config))
            config.overviewFingerCount = fingers
            config.overviewAction = nil
            XCTAssertNil(TrackpadGestureIntent.overviewConflict(config))
        }
    }
}
