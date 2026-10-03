// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ObservedMinimumSizeClampTests: XCTestCase {
    func testStableClampGrowsOnlyRefusedAxesAndDoesNotInvalidateDuplicates() throws {
        let fixture = try makeFixture()
        let manager = fixture.controller.workspaceManager
        XCTAssertTrue(manager.setObservedSizeEvidence(
            ObservedSizeEvidence(minSize: CGSize(width: 500, height: 620)),
            for: fixture.token
        ))
        var invalidatedWorkspaces: [WorkspaceDescriptor.ID?] = []
        manager.onRuntimeInvalidation = { workspaceId, domains, _ in
            if domains.contains(.layout) {
                invalidatedWorkspaces.append(workspaceId)
            }
        }
        let target = CGRect(x: 20, y: 30, width: 400, height: 300)
        let result = clampResult(
            fixture,
            target: target,
            observed: CGRect(x: 20, y: 30, width: 520, height: 300)
        )

        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(result)

        XCTAssertEqual(manager.observedSizeEvidence(for: fixture.token)?.minSize, CGSize(width: 520, height: 620))
        XCTAssertEqual(invalidatedWorkspaces, [fixture.workspaceId])
        let adoptedSeq = manager.worldSeq

        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(result)
        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(
            clampResult(fixture, target: target, observed: CGRect(x: 20, y: 30, width: 510, height: 300))
        )

        XCTAssertEqual(manager.observedSizeEvidence(for: fixture.token)?.minSize, CGSize(width: 520, height: 620))
        XCTAssertEqual(invalidatedWorkspaces, [fixture.workspaceId])
        XCTAssertEqual(manager.worldSeq, adoptedSeq)

        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(
            clampResult(fixture, target: target, observed: CGRect(x: 20, y: target.maxY - 700, width: 400, height: 700))
        )

        XCTAssertEqual(manager.observedSizeEvidence(for: fixture.token)?.minSize, CGSize(width: 520, height: 700))
        XCTAssertEqual(invalidatedWorkspaces, [fixture.workspaceId, fixture.workspaceId])
    }

    func testStableClampClassifiesEachAxisByConvergenceBound() throws {
        let fixture = try makeFixture()
        let manager = fixture.controller.workspaceManager
        let target = CGRect(x: 20, y: 30, width: 400, height: 300)

        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(
            clampResult(fixture, target: target, observed: CGRect(x: 20, y: 24, width: 520, height: 306))
        )

        XCTAssertEqual(
            manager.observedSizeEvidence(for: fixture.token),
            ObservedSizeEvidence(
                minSize: CGSize(width: 520, height: 1),
                hints: ObservedPackingHints(height: ObservedAxisHint(requested: 300, observed: 306))
            )
        )

        let taller = CGRect(x: 20, y: 30, width: 400, height: 400)
        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(
            clampResult(fixture, target: taller, observed: CGRect(x: 20, y: 24, width: 400, height: 406))
        )
        let replacedSeq = manager.worldSeq

        XCTAssertEqual(
            manager.observedSizeEvidence(for: fixture.token),
            ObservedSizeEvidence(
                minSize: CGSize(width: 520, height: 1),
                hints: ObservedPackingHints(height: ObservedAxisHint(requested: 400, observed: 406))
            )
        )

        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(
            clampResult(fixture, target: taller, observed: CGRect(x: 20, y: 24, width: 400, height: 406))
        )
        XCTAssertEqual(manager.worldSeq, replacedSeq)
    }

    func testStableClampRejectsWrongProcessAndReplacedAXIdentity() throws {
        let fixture = try makeFixture()
        let manager = fixture.controller.workspaceManager
        let target = CGRect(x: 20, y: 30, width: 400, height: 300)
        let observed = CGRect(x: 20, y: 30, width: 520, height: 300)
        let originalResult = clampResult(fixture, target: target, observed: observed)

        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(
            clampResult(fixture, target: target, observed: observed, pid: fixture.token.pid + 1)
        )
        XCTAssertNil(manager.observedSizeEvidence(for: fixture.token)?.minSize)

        XCTAssertNotNil(manager.removeWindow(pid: fixture.token.pid, windowId: fixture.token.windowId))
        let replacement = AXWindowRef(
            element: AXUIElementCreateApplication(fixture.token.pid + 1),
            windowId: fixture.token.windowId
        )
        let replacementToken = manager.addWindow(
            replacement,
            pid: fixture.token.pid,
            windowId: fixture.token.windowId,
            to: fixture.workspaceId
        )
        XCTAssertFalse(sameAXWindowIdentity(fixture.window, replacement))

        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(originalResult)

        XCTAssertNil(manager.observedSizeEvidence(for: replacementToken)?.minSize)
        XCTAssertTrue(sameAXWindowIdentity(try XCTUnwrap(manager.entry(for: replacementToken)).axRef, replacement))

        fixture.controller.adoptObservedMinimumAfterStableSizeClamp(
            clampResult(fixture, target: target, observed: observed, window: replacement)
        )
        XCTAssertEqual(manager.observedSizeEvidence(for: replacementToken)?.minSize, CGSize(width: 520, height: 1))
    }

    func testStableClampDoesNotLearnFromFloatingFullscreenOrHiddenWindows() throws {
        for state in ["floating", "fullscreen", "parked", "app-hidden"] {
            let fixture = try makeFixture()
            let manager = fixture.controller.workspaceManager
            switch state {
            case "floating":
                XCTAssertTrue(manager.setWindowMode(.floating, for: fixture.token))
            case "fullscreen":
                manager.setLayoutReason(.nativeFullscreen, for: fixture.token)
            case "parked":
                manager.setHiddenState(
                    HiddenState(proportionalPosition: .zero, referenceMonitorId: nil, reason: .layoutTransient(.left)),
                    for: fixture.token
                )
            default:
                manager.setAppHidden(true, pid: fixture.token.pid, source: .service)
            }
            let initialSeq = manager.worldSeq

            fixture.controller.adoptObservedMinimumAfterStableSizeClamp(
                clampResult(
                    fixture,
                    target: CGRect(x: 20, y: 30, width: 400, height: 300),
                    observed: CGRect(x: 20, y: 30, width: 520, height: 300)
                )
            )

            XCTAssertNil(manager.observedSizeEvidence(for: fixture.token)?.minSize, state)
            XCTAssertEqual(manager.worldSeq, initialSeq, state)
        }
    }

    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let token: WindowToken
        let window: AXWindowRef
    }

    private func makeFixture() throws -> Fixture {
        let controller = WindowAdmissionTestSupport.controller(prefix: "OmniWMObservedMinimumSizeClampTests")
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let token = WindowToken(pid: 467_591, windowId: 467_691)
        let window = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        return Fixture(controller: controller, workspaceId: workspaceId, token: token, window: window)
    }

    private func clampResult(
        _ fixture: Fixture,
        target: CGRect,
        observed: CGRect,
        pid: pid_t? = nil,
        window: AXWindowRef? = nil
    ) -> AXFrameApplyResult {
        AXFrameApplyResult(
            requestId: 1,
            pid: pid ?? fixture.token.pid,
            windowId: fixture.token.windowId,
            expectedWindow: window ?? fixture.window,
            targetFrame: target,
            currentFrameHint: nil,
            writeResult: AXFrameWriteResult(
                observedFrame: observed,
                writeOrder: .sizeThenPosition,
                sizeError: .success,
                positionError: .success,
                failureReason: .verificationMismatch
            )
        )
    }
}
