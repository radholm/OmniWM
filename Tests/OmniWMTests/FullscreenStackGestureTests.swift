// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import QuartzCore
import XCTest

final class FullscreenStackGestureTests: XCTestCase {
    private let size = CGSize(width: 1440, height: 900)

    func testSwipeAcrossWorkspaceAxisPagesFullscreenStackOnlyWhenAvailable() {
        var config = TrackpadGestureIntent.Config(
            workspaceSwipeEnabled: true,
            workspaceSwipeFingerCount: 3,
            workspaceSwipeAxis: .horizontal
        )
        let vertical = CGVector(dx: 2, dy: 30)
        XCTAssertNil(TrackpadGestureIntent.resolveMode(config, fingerCount: 3, cumulativeTranslation: vertical))
        config.fullscreenStackAvailable = true
        XCTAssertEqual(
            TrackpadGestureIntent.resolveMode(config, fingerCount: 3, cumulativeTranslation: vertical),
            .fullscreenStack(axis: .vertical)
        )
        XCTAssertEqual(
            TrackpadGestureIntent.resolveMode(config, fingerCount: 3, cumulativeTranslation: CGVector(dx: 30, dy: 2)),
            .workspaceSwitch(axis: .horizontal)
        )
        XCTAssertNil(TrackpadGestureIntent.resolveMode(config, fingerCount: 4, cumulativeTranslation: vertical))
        XCTAssertFalse(TrackpadGestureMode.fullscreenStack(axis: .vertical).isWindowInteraction)
    }

    func testScrubbedPoseMatchesPageTurnKeyframes() {
        let effects = [
            SnapshotStackEffect(fromDepth: 0, toDepth: 2, deckSize: 3, tucksUnder: true),
            SnapshotStackEffect(fromDepth: 2, toDepth: 1, deckSize: 3)
        ]
        for effect in effects {
            assertEqual(effect.pose(at: 0, size: size).transform, CATransform3DIdentity)
            assertEqual(effect.pose(at: 1, size: size).transform, CATransform3DIdentity)
            assertEqual(
                effect.pose(at: SnapshotStackEffect.deckShownTime, size: size).transform,
                SnapshotStackEffect.deckPose(slot: CGFloat(effect.fromDepth), count: 3, size: size)
            )
            assertEqual(
                effect.pose(at: SnapshotStackEffect.tuckedTime, size: size).transform,
                SnapshotStackEffect.deckPose(slot: CGFloat(effect.toDepth), count: 3, size: size)
            )
            XCTAssertEqual(
                effect.pose(at: 1, size: size).zPosition,
                SnapshotStackEffect.zPosition(depth: effect.toDepth)
            )
        }
        XCTAssertEqual(effects[0].pose(at: 0.2, size: size).zPosition, SnapshotStackEffect.tuckZPosition)
        XCTAssertEqual(effects[1].pose(at: 0.2, size: size).zPosition, SnapshotStackEffect.zPosition(depth: 2))
    }

    func testTuckingCardDipsBelowTheDeckMidway() {
        let tucking = SnapshotStackEffect(fromDepth: 0, toDepth: 2, deckSize: 3, tucksUnder: true)
        let middle = (SnapshotStackEffect.deckShownTime + SnapshotStackEffect.tuckedTime) / 2
        let dipped = tucking.pose(at: middle, size: size).transform
        let level = SnapshotStackEffect.deckPose(slot: 1, count: 3, size: size)
        XCTAssertLessThan(dipped.m42, level.m42 - size.height * SnapshotStackEffect.tuckDrop * 0.9)
    }

    func testScrubbingClampsOutOfRangeTimes() {
        let effect = SnapshotStackEffect(fromDepth: 1, toDepth: 0, deckSize: 2)
        assertEqual(effect.pose(at: -0.4, size: size).transform, effect.pose(at: 0, size: size).transform)
        assertEqual(effect.pose(at: 1.3, size: size).transform, effect.pose(at: 1, size: size).transform)
    }

    private func assertEqual(
        _ lhs: CATransform3D,
        _ rhs: CATransform3D,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let left = [
            lhs.m11,
            lhs.m12,
            lhs.m13,
            lhs.m14,
            lhs.m21,
            lhs.m22,
            lhs.m23,
            lhs.m24,
            lhs.m31,
            lhs.m32,
            lhs.m33,
            lhs.m34,
            lhs.m41,
            lhs.m42,
            lhs.m43,
            lhs.m44
        ]
        let right = [
            rhs.m11,
            rhs.m12,
            rhs.m13,
            rhs.m14,
            rhs.m21,
            rhs.m22,
            rhs.m23,
            rhs.m24,
            rhs.m31,
            rhs.m32,
            rhs.m33,
            rhs.m34,
            rhs.m41,
            rhs.m42,
            rhs.m43,
            rhs.m44
        ]
        for (left, right) in zip(left, right) {
            XCTAssertEqual(left, right, accuracy: 1e-6, file: file, line: line)
        }
    }
}
