// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class TrackpadGestureIntentTests: XCTestCase {
    func testOverviewTriggersInItsDirectionAtTwentyFourUnits() {
        for (action, direction) in [(OverviewGestureAction.open, CGFloat(1)), (.close, -1)] {
            for (point, expected) in [
                (CGPoint(x: 0, y: 23.9 * direction), false),
                (CGPoint(x: 0, y: 24 * direction), true),
                (CGPoint(x: 0, y: -140 * direction), false),
                (CGPoint(x: 30, y: 24 * direction), false),
                (CGPoint(x: 24, y: 24 * direction), false)
            ] {
                XCTAssertEqual(TrackpadGestureIntent.overviewTriggered(action: action, translation: point), expected)
            }
        }
    }

    func testOverviewSwipeRejectsOverlappingUpwardBindings() {
        var config = makeConfig(workspaceFingers: 3)
        config.overviewAction = .open
        XCTAssertEqual(TrackpadGestureIntent.resolveMode(
            config, fingerCount: 4, cumulativeTranslation: CGVector(dx: 0, dy: 24)
        ), .overview(.open))
        XCTAssertNil(TrackpadGestureIntent.resolveMode(
            config, fingerCount: 4, cumulativeTranslation: CGVector(dx: 0, dy: -24)
        ))
        config.workspaceSwipeFingerCount = 4
        XCTAssertNil(TrackpadGestureIntent.resolveMode(
            config, fingerCount: 4, cumulativeTranslation: CGVector(dx: 0, dy: 24)
        ))
        config.workspaceSwipeAxis = .horizontal
        XCTAssertEqual(TrackpadGestureIntent.resolveMode(
            config, fingerCount: 4, cumulativeTranslation: CGVector(dx: 0, dy: 24)
        ), .overview(.open))
    }

    func testOverviewOnlyConfigurationStartsWithConfiguredFingers() {
        var config = makeConfig(workspaceEnabled: false)
        for action in [OverviewGestureAction.open, .close] {
            config.overviewAction = action
            for fingers in [3, 4] {
                config.overviewFingerCount = fingers
                XCTAssertTrue(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: fingers))
                XCTAssertTrue(TrackpadGestureIntent.hasCandidateMode(
                    config,
                    fingerCount: fingers
                ))
                XCTAssertFalse(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 7 - fingers))
            }
        }
    }

    func testOverviewCloseOnlyResolvesDownwardWithConfiguredFingers() {
        var config = makeConfig(workspaceEnabled: false)
        config.overviewAction = .close
        for fingers in [3, 4] {
            config.overviewFingerCount = fingers
            for (translation, candidateFingers, expected) in [
                (CGVector(dx: 0, dy: -24), fingers, TrackpadGestureMode.overview(.close)),
                (CGVector(dx: 0, dy: 24), fingers, nil),
                (CGVector(dx: 25, dy: -24), fingers, nil),
                (CGVector(dx: 0, dy: -24), 7 - fingers, nil)
            ] {
                XCTAssertEqual(TrackpadGestureIntent.resolveMode(
                    config,
                    fingerCount: candidateFingers,
                    cumulativeTranslation: translation
                ), expected)
            }
        }
    }

    func testResumeActionResolvesEitherVerticalDirection() {
        var config = makeConfig(workspaceEnabled: false)
        config.overviewAction = .resume
        for fingers in [3, 4] {
            config.overviewFingerCount = fingers
            for (translation, candidateFingers, expected) in [
                (CGVector(dx: 0, dy: 24), fingers, TrackpadGestureMode.overview(.resume)),
                (CGVector(dx: 0, dy: -24), fingers, .overview(.resume)),
                (CGVector(dx: 30, dy: 24), fingers, nil),
                (CGVector(dx: 0, dy: 24), 7 - fingers, nil)
            ] {
                XCTAssertEqual(TrackpadGestureIntent.resolveMode(
                    config,
                    fingerCount: candidateFingers,
                    cumulativeTranslation: translation
                ), expected)
            }
        }

        var shared = makeConfig(workspaceFingers: 4)
        shared.overviewAction = .resume
        shared.overviewFingerCount = 4
        XCTAssertEqual(TrackpadGestureIntent.resolveMode(
            shared, fingerCount: 4, cumulativeTranslation: CGVector(dx: 0, dy: -24)
        ), .overview(.resume))
        XCTAssertFalse(TrackpadGestureIntent.overviewTriggered(action: .resume, translation: CGPoint(x: 0, y: 100)))
    }

    func testOverviewProgressScalesByTravel() {
        XCTAssertEqual(TrackpadGestureIntent.overviewTravelUnits, 300)
        XCTAssertEqual(TrackpadGestureIntent.overviewProgress(units: 150), 0.5)
        XCTAssertEqual(TrackpadGestureIntent.overviewProgress(units: 300), 1)
        XCTAssertEqual(TrackpadGestureIntent.overviewProgress(units: -30), -0.1, accuracy: 0.000000000001)
    }

    private func makeConfig(
        workspaceEnabled: Bool = true,
        workspaceFingers: Int = 3,
        workspaceAxis: WorkspaceSwipeAxis = .vertical
    ) -> TrackpadGestureIntent.Config {
        TrackpadGestureIntent.Config(
            workspaceSwipeEnabled: workspaceEnabled,
            workspaceSwipeFingerCount: workspaceFingers,
            workspaceSwipeAxis: workspaceAxis
        )
    }

    func testGestureStartAllowedForEitherEnabledFingerCount() {
        var config = makeConfig(workspaceFingers: 4)
        config.overviewAction = .open
        config.overviewFingerCount = 3
        XCTAssertTrue(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 3))
        XCTAssertTrue(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 4))
        XCTAssertFalse(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 2))
    }

    func testGestureStartRejectedWhenBothGesturesDisabled() {
        let config = makeConfig(workspaceEnabled: false)
        XCTAssertFalse(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 3))
    }

    func testGestureStartRespectsPerGestureEnablement() {
        let config = makeConfig(workspaceEnabled: true, workspaceFingers: 4)
        XCTAssertFalse(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 3))
        XCTAssertTrue(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 4))
    }

    func testCandidateModeAcceptsConfiguredWorkspaceFingers() {
        let config = makeConfig()
        XCTAssertTrue(TrackpadGestureIntent.hasCandidateMode(config, fingerCount: 3))
    }

    func testResolveModeResolvesVerticalWorkspaceSwitch() {
        let mode = TrackpadGestureIntent.resolveMode(
            makeConfig(),
            fingerCount: 3,
            cumulativeTranslation: CGVector(dx: 10, dy: 50)
        )
        XCTAssertEqual(mode, .workspaceSwitch(axis: .vertical))
    }

    func testResolveModeReturnsNilForWorkspaceCountOffAxisSwipe() {
        let mode = TrackpadGestureIntent.resolveMode(
            makeConfig(workspaceFingers: 4, workspaceAxis: .vertical),
            fingerCount: 4,
            cumulativeTranslation: CGVector(dx: 50, dy: 10)
        )
        XCTAssertNil(mode)
    }

    func testResolveModeResolvesWorkspaceSwitchWithConfiguredFingers() {
        let mode = TrackpadGestureIntent.resolveMode(
            makeConfig(),
            fingerCount: 3,
            cumulativeTranslation: CGVector(dx: 10, dy: 50)
        )
        XCTAssertEqual(mode, .workspaceSwitch(axis: .vertical))
    }

    func testResolveModeHonorsConfiguredHorizontalAxis() {
        let mode = TrackpadGestureIntent.resolveMode(
            makeConfig(workspaceFingers: 4, workspaceAxis: .horizontal),
            fingerCount: 4,
            cumulativeTranslation: CGVector(dx: 50, dy: 10)
        )
        XCTAssertEqual(mode, .workspaceSwitch(axis: .horizontal))
    }

    func testAxisTieResolvesAsVertical() {
        let mode = TrackpadGestureIntent.resolveMode(
            makeConfig(),
            fingerCount: 3,
            cumulativeTranslation: CGVector(dx: 30, dy: 30)
        )
        XCTAssertEqual(mode, .workspaceSwitch(axis: .vertical))
    }

    func testResolveModeReturnsNilWithNoCandidates() {
        let mode = TrackpadGestureIntent.resolveMode(
            makeConfig(workspaceEnabled: false),
            fingerCount: 3,
            cumulativeTranslation: CGVector(dx: 50, dy: 10)
        )
        XCTAssertNil(mode)
    }

    func testWorkspaceModeRejectsUnconfiguredFingerCountOffAxis() {
        let mode = TrackpadGestureIntent.resolveMode(
            makeConfig(workspaceFingers: 4),
            fingerCount: 3,
            cumulativeTranslation: CGVector(dx: 50, dy: 10)
        )
        XCTAssertNil(mode)
    }

    func testResolveModeHonorsConfiguredWorkspaceAxisWithDistinctCountsOnVerticalAxis() {
        let mode = TrackpadGestureIntent.resolveMode(
            makeConfig(workspaceFingers: 4, workspaceAxis: .horizontal),
            fingerCount: 4,
            cumulativeTranslation: CGVector(dx: 50, dy: 10)
        )
        XCTAssertEqual(mode, .workspaceSwitch(axis: .horizontal))
    }

    func testNaturalHorizontalSwipeLeftIsNext() {
        XCTAssertEqual(
            TrackpadGestureIntent.isNextWorkspace(axis: .horizontal, displacement: -1, naturalDirection: true),
            true
        )
    }

    func testNaturalHorizontalSwipeRightIsPrevious() {
        XCTAssertEqual(
            TrackpadGestureIntent.isNextWorkspace(axis: .horizontal, displacement: 1, naturalDirection: true),
            false
        )
    }

    func testInvertedHorizontalSwipeRightIsNext() {
        XCTAssertEqual(
            TrackpadGestureIntent.isNextWorkspace(axis: .horizontal, displacement: 1, naturalDirection: false),
            true
        )
    }

    func testInvertedHorizontalSwipeLeftIsPrevious() {
        XCTAssertEqual(
            TrackpadGestureIntent.isNextWorkspace(axis: .horizontal, displacement: -1, naturalDirection: false),
            false
        )
    }

    func testNaturalVerticalSwipeUpIsNext() {
        XCTAssertEqual(
            TrackpadGestureIntent.isNextWorkspace(axis: .vertical, displacement: 1, naturalDirection: true),
            true
        )
    }

    func testNaturalVerticalSwipeDownIsPrevious() {
        XCTAssertEqual(
            TrackpadGestureIntent.isNextWorkspace(axis: .vertical, displacement: -1, naturalDirection: true),
            false
        )
    }

    func testInvertedVerticalSwipeDownIsNext() {
        XCTAssertEqual(
            TrackpadGestureIntent.isNextWorkspace(axis: .vertical, displacement: -1, naturalDirection: false),
            true
        )
    }

    func testInvertedVerticalSwipeUpIsPrevious() {
        XCTAssertEqual(
            TrackpadGestureIntent.isNextWorkspace(axis: .vertical, displacement: 1, naturalDirection: false),
            false
        )
    }

    func testZeroDisplacementYieldsNoDirection() {
        XCTAssertNil(TrackpadGestureIntent.isNextWorkspace(axis: .vertical, displacement: 0, naturalDirection: true))
    }

    func testReleaseFlickFiresWhenVelocityExceedsFloor() {
        XCTAssertEqual(
            TrackpadGestureIntent.releaseFlickDisplacement(cumulativeAxisUnits: 60, velocity: 900),
            CGFloat(900)
        )
    }

    func testReleaseFlickRejectedBelowVelocityFloor() {
        XCTAssertNil(TrackpadGestureIntent.releaseFlickDisplacement(cumulativeAxisUnits: 60, velocity: 700))
    }

    func testReleaseFlickRejectedWhenVelocityOpposesCumulativeTravel() {
        XCTAssertNil(TrackpadGestureIntent.releaseFlickDisplacement(cumulativeAxisUnits: 60, velocity: -900))
    }

    func testReleaseFlickAllowedWithZeroCumulativeTravel() {
        XCTAssertEqual(
            TrackpadGestureIntent.releaseFlickDisplacement(cumulativeAxisUnits: 0, velocity: -900),
            CGFloat(-900)
        )
    }

    func testDisabledWindowGesturesNeverClaimTheirFingerCount() {
        var config = makeConfig(workspaceEnabled: false)
        config.windowMoveFingerCount = 4
        config.windowResizeFingerCount = 3
        XCTAssertNil(TrackpadGestureIntent.windowGestureMode(config, fingerCount: 4))
        XCTAssertNil(TrackpadGestureIntent.windowGestureMode(config, fingerCount: 3))
        XCTAssertFalse(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 4))
    }

    func testWindowGestureAllowsStartAndRequiresWindowContext() {
        var config = makeConfig(workspaceEnabled: false)
        config.windowMoveEnabled = true
        config.windowMoveFingerCount = 4
        XCTAssertTrue(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: 4))
        XCTAssertFalse(
            TrackpadGestureIntent.hasCandidateMode(
                config,
                fingerCount: 4,
                windowContextAvailable: false
            )
        )
        XCTAssertTrue(
            TrackpadGestureIntent.hasCandidateMode(
                config,
                fingerCount: 4,
                windowContextAvailable: true
            )
        )
    }

    func testWindowGestureLeavesOtherFingerCountsToExistingGestures() {
        var config = makeConfig(workspaceFingers: 3)
        config.windowMoveEnabled = true
        config.windowMoveFingerCount = 4
        let mode = TrackpadGestureIntent.resolveMode(
            config,
            fingerCount: 3,
            cumulativeTranslation: CGVector(dx: 50, dy: 10),
            windowContextAvailable: true
        )
        XCTAssertNil(mode)
    }

    func testWindowGestureLocationScalesTrackpadTravelToMonitorAndClamps() {
        let monitor = CGRect(x: 100, y: 200, width: 1600, height: 900)
        let start = CGPoint(x: 500, y: 650)

        let moved = TrackpadGestureIntent.windowGestureLocation(
            start: start,
            startTouch: CGPoint(x: 0.2, y: 0.5),
            currentTouch: CGPoint(x: 0.45, y: 0.4),
            monitorFrame: monitor,
            sensitivity: 1
        )
        XCTAssertEqual(moved.x, 900, accuracy: 0.001)
        XCTAssertEqual(moved.y, 560, accuracy: 0.001)

        let scaled = TrackpadGestureIntent.windowGestureLocation(
            start: start,
            startTouch: CGPoint(x: 0.2, y: 0.5),
            currentTouch: CGPoint(x: 0.3, y: 0.5),
            monitorFrame: monitor,
            sensitivity: 2
        )
        XCTAssertEqual(scaled.x, 820, accuracy: 0.001)

        let clamped = TrackpadGestureIntent.windowGestureLocation(
            start: start,
            startTouch: CGPoint(x: 0.9, y: 0.9),
            currentTouch: CGPoint(x: 0.0, y: 0.0),
            monitorFrame: monitor,
            sensitivity: 3
        )
        XCTAssertEqual(clamped, CGPoint(x: monitor.minX, y: monitor.minY))

        let unclamped = TrackpadGestureIntent.windowGestureLocation(
            start: start,
            startTouch: CGPoint(x: 0.9, y: 0.9),
            currentTouch: CGPoint(x: 0.0, y: 0.0),
            monitorFrame: monitor,
            sensitivity: 3,
            clampToMonitor: false
        )
        XCTAssertEqual(unclamped.x, start.x - 0.9 * 1600 * 3, accuracy: 0.001)
        XCTAssertEqual(unclamped.y, start.y - 0.9 * 900 * 3, accuracy: 0.001)
    }

    func testFingerCountGraceOnlyAppliesToWindowGestures() {
        XCTAssertEqual(TrackpadGestureMode.windowMove.fingerCountGrace, 0.15)
        XCTAssertEqual(TrackpadGestureMode.windowResize.fingerCountGrace, 0.15)
        XCTAssertEqual(TrackpadGestureMode.overview(.open).fingerCountGrace, 0)
        XCTAssertEqual(TrackpadGestureMode.overview(.close).fingerCountGrace, 0)
        XCTAssertEqual(TrackpadGestureMode.overview(.resume).fingerCountGrace, 0)
        XCTAssertEqual(TrackpadGestureMode.workspaceSwitch(axis: .horizontal).fingerCountGrace, 0)
    }

    func testWindowModesReportAsWindowInteractions() {
        XCTAssertTrue(TrackpadGestureMode.windowMove.isWindowInteraction)
        XCTAssertTrue(TrackpadGestureMode.windowResize.isWindowInteraction)
        XCTAssertFalse(TrackpadGestureMode.overview(.open).isWindowInteraction)
        XCTAssertFalse(TrackpadGestureMode.workspaceSwitch(axis: .vertical).isWindowInteraction)
    }

    func testWindowGestureUpperBoundsRemainInsideMonitorForDropTargets() {
        let monitor = CGRect(x: -1600, y: 200, width: 1600, height: 900)
        let location = TrackpadGestureIntent.windowGestureLocation(
            start: CGPoint(x: -500, y: 650),
            startTouch: .zero,
            currentTouch: CGPoint(x: 1, y: 1),
            monitorFrame: monitor,
            sensitivity: 5
        )
        XCTAssertEqual(location, CGPoint(x: monitor.maxX - 1, y: monitor.maxY - 1))
        XCTAssertTrue(monitor.contains(location))
        let unclamped = TrackpadGestureIntent.windowGestureLocation(
            start: CGPoint(x: -500, y: 650),
            startTouch: .zero,
            currentTouch: CGPoint(x: 1, y: 1),
            monitorFrame: monitor,
            sensitivity: 5,
            clampToMonitor: false
        )
        XCTAssertEqual(unclamped, CGPoint(x: 7500, y: 5150))
    }

    func testDistinctWindowGestureCountsResolveInEitherDirection() {
        var config = makeConfig(workspaceEnabled: false)
        config.windowMoveEnabled = true
        config.windowResizeEnabled = true
        for (fingers, expected) in [(4, TrackpadGestureMode.windowMove), (3, .windowResize)] {
            XCTAssertEqual(TrackpadGestureIntent.windowGestureMode(config, fingerCount: fingers), expected)
            for translation in [CGVector(dx: -40, dy: 0), CGVector(dx: 0, dy: 40)] {
                for context in [false, true] {
                    XCTAssertEqual(TrackpadGestureIntent.resolveMode(
                        config,
                        fingerCount: fingers,
                        cumulativeTranslation: translation,
                        windowContextAvailable: context
                    ), context ? expected : nil)
                }
            }
        }
        XCTAssertNil(TrackpadGestureIntent.windowGestureMode(config, fingerCount: 2))
    }

    func testEveryWindowGestureCollisionFailsClosed() {
        for mode in [TrackpadGestureMode.windowMove, .windowResize] {
            let other: TrackpadGestureMode = mode == .windowMove ? .windowResize : .windowMove
            for conflict in [other, .workspaceSwitch(axis: .vertical), .overview(.open)] {
                for fingers in [2, 3, 4] {
                    var config = makeConfig(workspaceEnabled: false)
                    enable(mode, fingers: fingers, in: &config)
                    enable(conflict, fingers: fingers, in: &config)
                    XCTAssertEqual(TrackpadGestureIntent.windowGestureConflict(config, mode: mode), conflict)
                    XCTAssertNil(TrackpadGestureIntent.windowGestureMode(config, fingerCount: fingers))
                    XCTAssertFalse(TrackpadGestureIntent.allowsGestureStart(config, fingerCount: fingers))
                    assertNoCandidate(config, fingers: fingers)
                }
            }
        }
    }

    func testDisabledWindowAssignmentDoesNotBlockOtherGestures() {
        let config = makeConfig(workspaceFingers: 3)
        XCTAssertNil(TrackpadGestureIntent.windowGestureConflict(config, mode: .windowResize))
    }

    private func assertNoCandidate(_ config: TrackpadGestureIntent.Config, fingers: Int) {
        for windowContext in [false, true] {
            XCTAssertFalse(TrackpadGestureIntent.hasCandidateMode(
                config, fingerCount: fingers,
                windowContextAvailable: windowContext
            ))
            for translation in [CGVector(dx: 40, dy: 0), CGVector(dx: 0, dy: 40)] {
                XCTAssertNil(TrackpadGestureIntent.resolveMode(
                    config, fingerCount: fingers, cumulativeTranslation: translation,
                    windowContextAvailable: windowContext
                ))
            }
        }
    }

    private func enable(_ mode: TrackpadGestureMode, fingers: Int, in config: inout TrackpadGestureIntent.Config) {
        switch mode {
        case .windowMove:
            config.windowMoveEnabled = true
            config.windowMoveFingerCount = fingers
        case .windowResize:
            config.windowResizeEnabled = true
            config.windowResizeFingerCount = fingers
        case let .workspaceSwitch(axis):
            config.workspaceSwipeEnabled = true
            config.workspaceSwipeFingerCount = fingers
            config.workspaceSwipeAxis = axis
        case let .overview(action):
            config.overviewAction = action
            config.overviewFingerCount = fingers
        }
    }
}
