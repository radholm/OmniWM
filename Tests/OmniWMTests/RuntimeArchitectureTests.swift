// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import XCTest

final class RuntimeArchitectureTests: XCTestCase {
    func testHyprlandDwindleBezierStartsAndEndsAtBounds() {
        let config = CubicConfig.hyprlandDwindle
        let startTime = 4.0
        let animation = CubicAnimation(
            from: 0.0,
            to: 1.0,
            startTime: startTime,
            config: config
        )

        XCTAssertEqual(animation.value(at: startTime), 0.0, accuracy: 0.000001)
        XCTAssertEqual(animation.value(at: startTime + config.duration), 1.0, accuracy: 0.000001)
        XCTAssertTrue(animation.isComplete(at: startTime + config.duration))
    }

    func testHyprlandDwindleBezierIsMonotonicAndSnappy() {
        let config = CubicConfig.hyprlandDwindle
        let startTime = 9.0
        let animation = CubicAnimation(
            from: 0.0,
            to: 1.0,
            startTime: startTime,
            config: config
        )
        var previous = -Double.infinity

        for step in 0 ... 40 {
            let time = startTime + config.duration * Double(step) / 40.0
            let value = animation.value(at: time)
            XCTAssertGreaterThanOrEqual(value + 0.000001, previous)
            previous = value
        }

        let quarterValue = animation.value(at: startTime + config.duration * 0.25)
        XCTAssertGreaterThan(quarterValue, 0.65)
        XCTAssertLessThan(quarterValue, 1.0)
    }

    func testDwindleRectAnimationRetargetsFromPresentedFrame() throws {
        let config = CubicConfig.hyprlandDwindle
        let node = DwindleNode(
            kind: .leaf(tile: DwindleTile(token: WindowToken(pid: 10, windowId: 20)))
        )
        let firstStart = CGRect(x: 10, y: 20, width: 320, height: 180)
        let firstTarget = CGRect(x: 200, y: 80, width: 480, height: 240)
        let secondTarget = CGRect(x: 60, y: 140, width: 360, height: 420)
        let retargetTime = config.duration * 0.35

        node.cachedFrame = firstTarget
        node.animateFrom(
            oldFrame: firstStart,
            newFrame: firstTarget,
            startTime: 0,
            config: config,
            animated: true
        )

        let visibleFrame = try XCTUnwrap(node.presentedFrame(at: retargetTime))
        node.cachedFrame = secondTarget
        node.animateFrom(
            oldFrame: visibleFrame,
            newFrame: secondTarget,
            startTime: retargetTime,
            config: config,
            animated: true
        )

        Self.assertFrame(
            try XCTUnwrap(node.presentedFrame(at: retargetTime)),
            equals: visibleFrame
        )
    }

    func testDwindleRectAnimationUsesSingleProgressForFrameComponents() throws {
        let config = CubicConfig.hyprlandDwindle
        let node = DwindleNode(
            kind: .leaf(tile: DwindleTile(token: WindowToken(pid: 11, windowId: 21)))
        )
        let startFrame = CGRect(x: 20, y: 40, width: 300, height: 200)
        let targetFrame = CGRect(x: 220, y: 160, width: 500, height: 440)
        let sampleTime = config.duration * 0.5
        let progress = CGFloat(CubicAnimation(
            from: 0.0,
            to: 1.0,
            startTime: 0,
            config: config
        ).value(at: sampleTime))

        node.cachedFrame = targetFrame
        node.animateFrom(
            oldFrame: startFrame,
            newFrame: targetFrame,
            startTime: 0,
            config: config,
            animated: true
        )

        let expectedFrame = CGRect(
            x: startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * progress,
            y: startFrame.origin.y + (targetFrame.origin.y - startFrame.origin.y) * progress,
            width: startFrame.width + (targetFrame.width - startFrame.width) * progress,
            height: startFrame.height + (targetFrame.height - startFrame.height) * progress
        )
        Self.assertFrame(
            try XCTUnwrap(node.presentedFrame(at: sampleTime)),
            equals: expectedFrame
        )

        node.tickAnimations(at: config.duration)
        XCTAssertFalse(node.hasActiveAnimations(at: config.duration))
        Self.assertFrame(
            try XCTUnwrap(node.presentedFrame(at: config.duration)),
            equals: targetFrame
        )
    }

    func testInvalidationMarksRejectOnlyRelevantDomains() {
        var marks = InvalidationMarks()
        marks.record(5, domains: .focus)
        XCTAssertTrue(marks.isCurrent(4, domains: .layoutCommit))
        XCTAssertFalse(marks.isCurrent(4, domains: .focusCommit))

        marks.record(6, domains: .layout)
        XCTAssertFalse(marks.isCurrent(5, domains: .layoutCommit))
        XCTAssertTrue(marks.isCurrent(6, domains: [.workspace, .layout, .focus, .fullscreen]))

        marks.record(7, domains: .fullscreen)
        XCTAssertFalse(marks.isCurrent(6, domains: .layoutCommit))
        XCTAssertTrue(marks.isCurrent(6, domains: .focusCommit))

        let merged = marks.merged(with: InvalidationMarks(workspace: 9, layout: 0, focus: 0, fullscreen: 0))
        XCTAssertFalse(merged.isCurrent(8, domains: .layoutCommit))
        XCTAssertTrue(merged.isCurrent(9, domains: [.workspace, .layout, .focus, .fullscreen]))
    }

    func testManagedFocusRequestCarriesRequestId() {
        let workspaceId = WorkspaceDescriptor.ID()
        let token = WindowToken(pid: 100, windowId: 42)
        let plan = StateReducer.reduce(
            event: .managedFocusRequested(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                requestId: 7,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: Self.snapshot(),
            monitors: []
        )

        XCTAssertEqual(plan.focusSession?.pendingManagedFocus.token, token)
        XCTAssertEqual(plan.focusSession?.pendingManagedFocus.workspaceId, workspaceId)
        XCTAssertEqual(plan.focusSession?.pendingManagedFocus.requestId, 7)
        XCTAssertTrue(plan.mutatesRuntimeState)
    }

    func testIsSystemModalSurfaceClassification() {
        XCTAssertTrue(AXWindowService.isSystemModalSurface(role: kAXSheetRole as String, subrole: nil))
        XCTAssertTrue(AXWindowService.isSystemModalSurface(role: nil, subrole: kAXDialogSubrole as String))
        XCTAssertTrue(AXWindowService.isSystemModalSurface(role: nil, subrole: kAXSystemDialogSubrole as String))
        XCTAssertFalse(
            AXWindowService.isSystemModalSurface(
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String
            )
        )
        XCTAssertFalse(AXWindowService.isSystemModalSurface(role: nil, subrole: nil))
    }

    func testSystemModalFocusChangedSetsToken() {
        let token = WindowToken(pid: 100, windowId: 42)
        let plan = StateReducer.reduce(
            event: .systemModalFocusChanged(token: token, source: .workspaceManager),
            existingEntry: nil,
            currentSnapshot: Self.snapshot(),
            monitors: []
        )

        XCTAssertEqual(plan.focusSession?.systemModalFocusToken, token)
    }

    func testSystemModalFocusChangedClearsToken() {
        let token = WindowToken(pid: 100, windowId: 42)
        let modalSnapshot = ReconcileSnapshot(
            topologyProfile: TopologyProfile(sortedMonitors: []),
            focusSession: FocusSessionSnapshot(systemModalFocusToken: token),
            windows: [],
            layouts: [:]
        )

        let plan = StateReducer.reduce(
            event: .systemModalFocusChanged(token: nil, source: .workspaceManager),
            existingEntry: nil,
            currentSnapshot: modalSnapshot,
            monitors: []
        )

        XCTAssertNil(plan.focusSession?.systemModalFocusToken)
    }

    func testWindowRekeyRekeysSystemModalFocusToken() {
        let workspaceId = WorkspaceDescriptor.ID()
        let oldToken = WindowToken(pid: 100, windowId: 42)
        let newToken = WindowToken(pid: 100, windowId: 43)
        let snapshot = Self.snapshot(
            systemModalFocusToken: oldToken,
            windows: [Self.window(token: oldToken, workspaceId: workspaceId)]
        )

        let plan = StateReducer.reduce(
            event: .windowRekeyed(
                from: oldToken,
                to: newToken,
                workspaceId: workspaceId,
                monitorId: nil,
                reason: .manualRekey,
                newAXRef: AXWindowRef(element: AXUIElementCreateApplication(oldToken.pid), windowId: newToken.windowId),
                managedReplacementMetadata: nil,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: snapshot,
            monitors: []
        )

        XCTAssertEqual(plan.focusSession?.systemModalFocusToken, newToken)
    }

    func testWindowRemovalClearsMatchingSystemModalFocusTokenOnly() {
        let workspaceId = WorkspaceDescriptor.ID()
        let modalToken = WindowToken(pid: 100, windowId: 42)
        let removedToken = WindowToken(pid: 100, windowId: 43)
        let matchingSnapshot = Self.snapshot(systemModalFocusToken: modalToken)
        let nonmatchingSnapshot = Self.snapshot(systemModalFocusToken: modalToken)

        let matchingPlan = StateReducer.reduce(
            event: .windowRemoved(token: modalToken, workspaceId: workspaceId, source: .workspaceManager),
            existingEntry: nil,
            currentSnapshot: matchingSnapshot,
            monitors: []
        )
        let nonmatchingPlan = StateReducer.reduce(
            event: .windowRemoved(token: removedToken, workspaceId: workspaceId, source: .workspaceManager),
            existingEntry: nil,
            currentSnapshot: nonmatchingSnapshot,
            monitors: []
        )

        XCTAssertNil(matchingPlan.focusSession?.systemModalFocusToken)
        XCTAssertEqual(nonmatchingPlan.focusSession?.systemModalFocusToken, modalToken)
    }

    @MainActor
    func testManagedFocusRequestMergesEveryOriginPairAtDeclaredPrecedence() {
        let workspaceId = WorkspaceDescriptor.ID()
        let token = WindowToken(pid: 100, windowId: 42)
        let cases: [(ManagedFocusOrigin, ManagedFocusOrigin, ManagedFocusOrigin)] = [
            (.focusFollowsMouse, .focusFollowsMouse, .focusFollowsMouse),
            (.focusFollowsMouse, .pointerHover, .pointerHover),
            (.focusFollowsMouse, .pointerSelection, .pointerSelection),
            (.focusFollowsMouse, .keyboardOrProgrammatic, .keyboardOrProgrammatic),
            (.pointerHover, .focusFollowsMouse, .pointerHover),
            (.pointerHover, .pointerHover, .pointerHover),
            (.pointerHover, .pointerSelection, .pointerSelection),
            (.pointerHover, .keyboardOrProgrammatic, .keyboardOrProgrammatic),
            (.pointerSelection, .focusFollowsMouse, .pointerSelection),
            (.pointerSelection, .pointerHover, .pointerSelection),
            (.pointerSelection, .pointerSelection, .pointerSelection),
            (.pointerSelection, .keyboardOrProgrammatic, .keyboardOrProgrammatic),
            (.keyboardOrProgrammatic, .focusFollowsMouse, .keyboardOrProgrammatic),
            (.keyboardOrProgrammatic, .pointerHover, .keyboardOrProgrammatic),
            (.keyboardOrProgrammatic, .pointerSelection, .keyboardOrProgrammatic),
            (.keyboardOrProgrammatic, .keyboardOrProgrammatic, .keyboardOrProgrammatic)
        ]

        for (current, incoming, expected) in cases {
            let ledger = IntentLedger()
            let initial = ledger.beginManagedRequest(
                token: token,
                workspaceId: workspaceId,
                origin: current
            )
            let merged = ledger.beginManagedRequest(
                token: token,
                workspaceId: workspaceId,
                origin: incoming
            )

            XCTAssertEqual(merged.requestId, initial.requestId)
            XCTAssertEqual(merged.origin, expected, "\(current) + \(incoming)")
            XCTAssertEqual(merged.origin.allowsMouseToFocusedWarp, expected == .keyboardOrProgrammatic)
            XCTAssertEqual(
                merged.origin.preservesViewportOnActivation,
                expected == .pointerHover || expected == .focusFollowsMouse
            )
        }
    }

    @MainActor
    func testConfirmedManagedFocusOriginControlsMouseWarpPolicy() throws {
        let bridge = IntentLedger()
        let workspaceId = WorkspaceDescriptor.ID()
        let token = WindowToken(pid: 100, windowId: 42)
        let rekeyedToken = WindowToken(pid: 100, windowId: 43)

        _ = bridge.beginManagedRequest(
            token: token,
            workspaceId: workspaceId,
            origin: .pointerHover
        )
        let pointerConfirmation = try XCTUnwrap(bridge.confirmManagedRequest(
            token: token,
            source: .focusedWindowChanged
        ))

        XCTAssertEqual(pointerConfirmation.origin, .pointerHover)
        XCTAssertFalse(bridge.allowsMouseToFocusedWarp(for: token))
        XCTAssertTrue(bridge.allowsMouseToFocusedWarp(for: rekeyedToken))

        bridge.rekeyManagedRequest(from: token, to: rekeyedToken)
        XCTAssertTrue(bridge.allowsMouseToFocusedWarp(for: token))
        XCTAssertFalse(bridge.allowsMouseToFocusedWarp(for: rekeyedToken))

        bridge.discardPendingFocus(rekeyedToken)
        XCTAssertTrue(bridge.allowsMouseToFocusedWarp(for: rekeyedToken))

        _ = bridge.beginManagedRequest(
            token: token,
            workspaceId: workspaceId,
            origin: .focusFollowsMouse
        )
        let focusFollowsMouseConfirmation = try XCTUnwrap(bridge.confirmManagedRequest(
            token: token,
            source: .focusedWindowChanged
        ))
        XCTAssertEqual(focusFollowsMouseConfirmation.origin, .focusFollowsMouse)
        XCTAssertFalse(bridge.allowsMouseToFocusedWarp(for: token))

        _ = bridge.beginManagedRequest(
            token: token,
            workspaceId: workspaceId,
            origin: .pointerSelection
        )
        XCTAssertFalse(bridge.allowsMouseToFocusedWarp(for: token))
        let pointerSelectionConfirmation = try XCTUnwrap(bridge.confirmManagedRequest(
            token: token,
            source: .focusedWindowChanged
        ))
        XCTAssertEqual(pointerSelectionConfirmation.origin, .pointerSelection)
        XCTAssertFalse(bridge.allowsMouseToFocusedWarp(for: token))

        _ = bridge.beginManagedRequest(
            token: token,
            workspaceId: workspaceId,
            origin: .pointerHover
        )
        _ = try XCTUnwrap(bridge.confirmManagedRequest(
            token: token,
            source: .focusedWindowChanged
        ))
        XCTAssertFalse(bridge.allowsMouseToFocusedWarp(for: token))

        _ = bridge.beginManagedRequest(
            token: token,
            workspaceId: workspaceId,
            origin: .keyboardOrProgrammatic
        )
        XCTAssertTrue(bridge.allowsMouseToFocusedWarp(for: token))
        let keyboardConfirmation = try XCTUnwrap(bridge.confirmManagedRequest(
            token: token,
            source: .focusedWindowChanged
        ))

        XCTAssertEqual(keyboardConfirmation.origin, .keyboardOrProgrammatic)
        XCTAssertTrue(bridge.allowsMouseToFocusedWarp(for: token))
    }

    @MainActor
    private static func clickUnmanagedWindow(controller: WMController, workspaceId: WorkspaceDescriptor.ID) {
        let visibleFrame = controller.workspaceManager.monitor(for: workspaceId)?.visibleFrame ?? .zero
        controller.mouseEventHandler.dispatchMouseDown(
            at: CGPoint(x: visibleFrame.minX + 10, y: visibleFrame.minY + 10),
            modifiers: [],
            button: .left,
            windowIdUnderPointer: 999_999
        )
    }

    @MainActor
    func testManagedSurfaceFocusActivatesItsWorkspace() throws {
        let fixture = try Self.inactiveWorkspaceFocusFixture(
            pid: 765_761,
            windowId: 765_861
        )

        fixture.controller.axEventHandler.handleActivationFactsResolved(fixture.facts)

        XCTAssertEqual(
            fixture.controller.workspaceManager.activeWorkspace(on: fixture.monitorId)?.id,
            fixture.surfaceWorkspaceId
        )
    }

    @MainActor
    func testDwindlePointerHoverActivationFocusesImmediatelyWhenLayoutRefreshBlocked() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let engine = DwindleLayoutEngine()
        engine.animationClock = controller.animationClock
        controller.dwindleEngine = engine
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_702), windowId: 765_802),
            pid: 765_702,
            windowId: 765_802,
            to: workspaceId
        )
        _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [workspaceId]
        )
        defer {
            blocker.cancel()
            controller.layoutRefreshController.layoutState.activeRefreshTask = nil
            controller.layoutRefreshController.layoutState.activeRefresh = nil
            controller.layoutRefreshController.layoutState.pendingRefresh = nil
        }

        controller.dwindleLayoutHandler.activateWindow(
            token,
            in: workspaceId,
            origin: .pointerHover,
            layoutRefresh: false
        )

        XCTAssertNil(controller.layoutRefreshController.layoutState.pendingRefresh)
        XCTAssertEqual(controller.intentLedger.activeManagedRequest?.origin, .pointerHover)
    }

    func testMouseMoveWindowIdPrefersRoutedFieldAndFallsBackToTopmostField() throws {
        let event = try XCTUnwrap(
            CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: .zero,
                mouseButton: .left
            )
        )
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 765_801)
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            value: 765_802
        )

        XCTAssertEqual(MouseEventHandler.eventWindowIdUnderPointer(event), 765_802)

        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            value: 0
        )

        XCTAssertEqual(MouseEventHandler.eventWindowIdUnderPointer(event), 765_801)

        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 0)

        XCTAssertNil(MouseEventHandler.eventWindowIdUnderPointer(event))
    }

    func testMouseMoveWindowIdRejectsValuesOutsideCGWindowIdRange() {
        XCTAssertNil(MouseEventHandler.normalizedEventWindowId(-1))
        XCTAssertNil(MouseEventHandler.normalizedEventWindowId(Int64(UInt32.max) + 1))
        XCTAssertNil(MouseEventHandler.normalizedEventWindowId(0))
        XCTAssertEqual(MouseEventHandler.normalizedEventWindowId(Int64(UInt32.max)), Int(UInt32.max))
    }

    func testAnnotatedMoveTapMakesSessionEventMasksMutuallyExclusive() {
        let moveBit: CGEventMask = 1 << CGEventType.mouseMoved.rawValue
        let annotatedMask = MouseEventHandler.sessionEventMask(annotatedMoveTapInstalled: true)
        let fallbackMask = MouseEventHandler.sessionEventMask(annotatedMoveTapInstalled: false)

        XCTAssertEqual(annotatedMask & moveBit, 0)
        XCTAssertNotEqual(fallbackMask & moveBit, 0)

        for type in [
            CGEventType.leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseDragged,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseDragged,
            .otherMouseUp,
            .scrollWheel
        ] {
            let bit: CGEventMask = 1 << type.rawValue
            XCTAssertNotEqual(annotatedMask & bit, 0)
            XCTAssertNotEqual(fallbackMask & bit, 0)
        }
    }

    @MainActor
    func testFocusFollowsMouseDoesNotFocusHiddenFloatingWindowId() throws {
        var focusedTokens: [WindowToken] = []
        let controller = Self.controller(
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    focusedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.setFocusFollowsMouse(true)
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let floatingToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(766_007), windowId: 766_107),
            pid: 766_007,
            windowId: 766_107,
            to: workspaceId,
            mode: .floating
        )
        controller.workspaceManager.setHiddenState(
            HiddenState(
                proportionalPosition: .zero,
                referenceMonitorId: monitor.id,
                reason: .scratchpad
            ),
            for: floatingToken
        )

        controller.mouseEventHandler.dispatchMouseMoved(
            at: monitor.visibleFrame.center,
            windowIdUnderPointer: floatingToken.windowId
        )

        XCTAssertTrue(focusedTokens.isEmpty)
        XCTAssertNil(controller.intentLedger.activeManagedRequest)
    }

    @MainActor
    func testScreenshotSelectionPausesAndResumesFocusFollowsMouse() throws {
        var focusedTokens: [WindowToken] = []
        let controller = Self.controller(
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    focusedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.setFocusFollowsMouse(true)
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let source = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(766_009), windowId: 766_109),
            pid: 766_009,
            windowId: 766_109,
            to: workspaceId,
            mode: .floating
        )
        let target = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(766_010), windowId: 766_110),
            pid: 766_010,
            windowId: 766_110,
            to: workspaceId,
            mode: .floating
        )
        let targetFrame = CGRect(
            x: monitor.visibleFrame.midX,
            y: monitor.visibleFrame.midY,
            width: 240,
            height: 160
        )
        controller.workspaceManager.updateFloatingGeometry(frame: targetFrame, for: target)
        XCTAssertTrue(controller.workspaceManager.confirmManagedFocus(
            source,
            in: workspaceId,
            activateWorkspaceOnMonitor: false
        ))
        var selectionActive = true
        var selectionChecks = 0
        controller.focusPolicyEngine.screenshotSelectionActiveProvider = {
            selectionChecks += 1
            return selectionActive
        }

        controller.mouseEventHandler.dispatchMouseMoved(
            at: targetFrame.center,
            windowIdUnderPointer: target.windowId
        )

        XCTAssertTrue(focusedTokens.isEmpty)
        XCTAssertNil(controller.intentLedger.activeManagedRequest)
        XCTAssertEqual(controller.workspaceManager.selectedManagedToken, source)
        XCTAssertEqual(selectionChecks, 1)

        selectionActive = false
        controller.mouseEventHandler.dispatchMouseMoved(
            at: targetFrame.center,
            windowIdUnderPointer: target.windowId
        )

        XCTAssertEqual(focusedTokens, [target])
        XCTAssertEqual(controller.intentLedger.activeManagedRequest?.token, target)
        XCTAssertEqual(selectionChecks, 2)
    }

    @MainActor
    func testDwindleFocusFollowsMouseDispatchFocusesHoveredWindowImmediately() throws {
        var focusedTokens: [WindowToken] = []
        let settings = Self.settingsStore()
        settings.workspaces.configurations = settings.workspaces.configurations.map {
            $0.name == "1" ? $0.with(layoutType: .dwindle) : $0
        }
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    focusedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.setFocusFollowsMouse(true)
        let engine = DwindleLayoutEngine()
        engine.animationClock = controller.animationClock
        controller.dwindleEngine = engine
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_705), windowId: 765_805),
            pid: 765_705,
            windowId: 765_805,
            to: workspaceId
        )
        _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        let frames = engine.calculateLayout(for: workspaceId, screen: monitor.visibleFrame)
        let targetFrame = try XCTUnwrap(frames[token])
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [workspaceId]
        )
        defer {
            blocker.cancel()
            controller.layoutRefreshController.layoutState.activeRefreshTask = nil
            controller.layoutRefreshController.layoutState.activeRefresh = nil
            controller.layoutRefreshController.layoutState.pendingRefresh = nil
        }

        controller.mouseEventHandler.dispatchMouseMoved(at: targetFrame.center)

        XCTAssertEqual(focusedTokens.last, token)
        XCTAssertNil(controller.layoutRefreshController.layoutState.pendingRefresh)
        XCTAssertEqual(controller.intentLedger.activeManagedRequest?.origin, .focusFollowsMouse)

        let exactTiledToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_710), windowId: 765_810),
            pid: 765_710,
            windowId: 765_810,
            to: workspaceId
        )
        _ = engine.addWindow(token: exactTiledToken, to: workspaceId, activeWindowFrame: nil)
        controller.mouseEventHandler.state.lastFocusFollowsMouseTime = .distantPast

        controller.mouseEventHandler.dispatchMouseMoved(
            at: targetFrame.center,
            windowIdUnderPointer: exactTiledToken.windowId
        )

        XCTAssertEqual(focusedTokens.last, exactTiledToken)
        XCTAssertEqual(controller.intentLedger.activeManagedRequest?.token, exactTiledToken)

        let floatingToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_709), windowId: 765_809),
            pid: 765_709,
            windowId: 765_809,
            to: workspaceId,
            mode: .floating
        )
        controller.workspaceManager.updateFloatingGeometry(frame: targetFrame, for: floatingToken)
        controller.mouseEventHandler.state.lastFocusFollowsMouseTime = .distantPast

        controller.mouseEventHandler.dispatchMouseMoved(
            at: targetFrame.center,
            windowIdUnderPointer: floatingToken.windowId
        )

        XCTAssertEqual(focusedTokens.last, floatingToken)
        XCTAssertEqual(controller.intentLedger.activeManagedRequest?.token, floatingToken)
        XCTAssertNil(controller.layoutRefreshController.layoutState.pendingRefresh)
    }

    @MainActor
    func testFocusLockModifierSuppressesDwindleFocusFollowsMouseWhileHeld() throws {
        var focusedTokens: [WindowToken] = []
        let settings = Self.settingsStore()
        settings.workspaces.configurations = settings.workspaces.configurations.map {
            $0.name == "1" ? $0.with(layoutType: .dwindle) : $0
        }
        settings.focus.lockModifier = .option
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    focusedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.setFocusFollowsMouse(true)
        let engine = DwindleLayoutEngine()
        engine.animationClock = controller.animationClock
        controller.dwindleEngine = engine
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_707), windowId: 765_807),
            pid: 765_707,
            windowId: 765_807,
            to: workspaceId
        )
        _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        let frames = engine.calculateLayout(for: workspaceId, screen: monitor.visibleFrame)
        let targetFrame = try XCTUnwrap(frames[token])
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [workspaceId]
        )
        defer {
            blocker.cancel()
            controller.layoutRefreshController.layoutState.activeRefreshTask = nil
            controller.layoutRefreshController.layoutState.activeRefresh = nil
            controller.layoutRefreshController.layoutState.pendingRefresh = nil
        }

        controller.mouseEventHandler.dispatchMouseMoved(
            at: targetFrame.center,
            modifiersRawValue: CGEventFlags.maskAlternate.rawValue
        )
        XCTAssertTrue(focusedTokens.isEmpty, "Focus lock modifier held should suppress Dwindle focus-follows-mouse")

        controller.mouseEventHandler.dispatchMouseMoved(at: targetFrame.center, modifiersRawValue: 0)
        XCTAssertEqual(focusedTokens.last, token, "Releasing the modifier should restore Dwindle focus-follows-mouse")
    }

    func testManagedFocusCancelRejectsMismatchedRequestId() {
        let workspaceId = WorkspaceDescriptor.ID()
        let token = WindowToken(pid: 100, windowId: 42)
        let snapshot = Self.snapshot(
            pendingManagedFocus: PendingManagedFocusSnapshot(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                requestId: 7
            )
        )

        let mismatchedPlan = StateReducer.reduce(
            event: .managedFocusCancelled(
                token: token,
                workspaceId: workspaceId,
                requestId: 8,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: snapshot,
            monitors: []
        )
        let matchingPlan = StateReducer.reduce(
            event: .managedFocusCancelled(
                token: token,
                workspaceId: workspaceId,
                requestId: 7,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: snapshot,
            monitors: []
        )

        XCTAssertFalse(mismatchedPlan.mutatesRuntimeState)
        XCTAssertEqual(matchingPlan.focusSession?.pendingManagedFocus, .empty)
    }

    func testWorkspaceReassignClearsStalePendingManagedFocus() {
        let token = WindowToken(pid: 100, windowId: 42)
        let workspaceA = WorkspaceDescriptor.ID()
        let workspaceB = WorkspaceDescriptor.ID()
        let snapshot = Self.snapshot(
            pendingManagedFocus: PendingManagedFocusSnapshot(
                token: token,
                workspaceId: workspaceA,
                monitorId: nil,
                requestId: 7
            )
        )

        let movedPlan = StateReducer.reduce(
            event: .workspaceAssigned(
                token: token,
                from: workspaceA,
                to: workspaceB,
                monitorId: nil,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: snapshot,
            monitors: []
        )
        XCTAssertEqual(movedPlan.focusSession?.pendingManagedFocus, .empty)

        let sameWorkspacePlan = StateReducer.reduce(
            event: .workspaceAssigned(
                token: token,
                from: workspaceA,
                to: workspaceA,
                monitorId: nil,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: snapshot,
            monitors: []
        )
        XCTAssertNil(sameWorkspacePlan.focusSession)
    }

    func testWorkspaceReassignLeavesUnrelatedTokenPendingFocus() {
        let token = WindowToken(pid: 100, windowId: 42)
        let workspaceA = WorkspaceDescriptor.ID()
        let workspaceB = WorkspaceDescriptor.ID()
        let snapshot = Self.snapshot(
            pendingManagedFocus: PendingManagedFocusSnapshot(
                token: token,
                workspaceId: workspaceA,
                monitorId: nil,
                requestId: 7
            )
        )

        let otherToken = WindowToken(pid: 200, windowId: 7)
        let otherPlan = StateReducer.reduce(
            event: .workspaceAssigned(
                token: otherToken,
                from: workspaceA,
                to: workspaceB,
                monitorId: nil,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: snapshot,
            monitors: []
        )
        XCTAssertNil(otherPlan.focusSession)
    }

    func testManagedFocusConfirmRequiresMatchingRequest() {
        let workspaceId = WorkspaceDescriptor.ID()
        let token = WindowToken(pid: 100, windowId: 42)
        let monitorId = Monitor.ID(displayId: 2)
        let previousMonitorId = Monitor.ID(displayId: 1)
        let nativeFullscreenOwner = WindowToken(pid: 200, windowId: 84)
        let snapshot = Self.snapshot(
            pendingManagedFocus: PendingManagedFocusSnapshot(
                token: token,
                workspaceId: workspaceId,
                monitorId: previousMonitorId,
                requestId: 7
            ),
            nativeFocusOwner: .external(
                pid: nativeFullscreenOwner.pid,
                windowId: nativeFullscreenOwner.windowId
            ),
            interactionMonitorId: previousMonitorId
        )

        let mismatch = StateReducer.reduce(
            event: .managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                requestId: 8,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: snapshot,
            monitors: []
        )
        let match = StateReducer.reduce(
            event: .managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                requestId: 7,
                source: .workspaceManager
            ),
            existingEntry: nil,
            currentSnapshot: snapshot,
            monitors: []
        )

        XCTAssertFalse(mismatch.mutatesRuntimeState)
        XCTAssertEqual(snapshot.focusSession.nativeFocusOwner.externalToken, nativeFullscreenOwner)
        XCTAssertEqual(match.focusSession?.selectedManagedToken, token)
        XCTAssertEqual(match.focusSession?.pendingManagedFocus, .empty)
        XCTAssertEqual(match.focusSession?.nativeFocusOwner.isExternal, false)
        XCTAssertNil(match.focusSession?.nativeFocusOwner.externalToken)
        XCTAssertEqual(match.focusSession?.interactionMonitorId, monitorId)
        XCTAssertEqual(match.focusSession?.previousInteractionMonitorId, previousMonitorId)
    }

    @MainActor
    func testRejectedManagedFocusConfirmDoesNotInvalidateRuntimeThroughRestoreIntentRefresh() throws {
        let manager = Self.workspaceManager()
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let token = manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 9_101),
            pid: getpid(),
            windowId: 9_101,
            to: workspaceId
        )

        _ = manager.beginManagedFocusRequest(token, in: workspaceId, requestId: 7)
        let before = manager.worldSeq
        let txn = manager.recordReconcileEvent(
            .managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                requestId: 8,
                source: .workspaceManager
            )
        )

        XCTAssertFalse(txn.plan.mutatesRuntimeState)
        XCTAssertTrue(
            manager.isSeqCurrent(before, for: workspaceId, domains: [.workspace, .layout, .focus, .fullscreen])
        )
    }

    func testPendingManagedFocusWithoutRequestIdIsInvariantViolation() {
        let workspaceId = WorkspaceDescriptor.ID()
        let token = WindowToken(pid: 100, windowId: 42)
        let snapshot = Self.snapshot(
            pendingManagedFocus: PendingManagedFocusSnapshot(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                requestId: nil
            )
        )

        let codes = Set(InvariantChecks.validate(snapshot: snapshot).map(\.code))

        XCTAssertTrue(codes.contains("pending_focus_token_missing"))
        XCTAssertTrue(codes.contains("pending_focus_without_request"))
    }

    func testFocusInvariantTableCoversCorruptSnapshots() {
        let token = WindowToken(pid: 100, windowId: 42)
        let workspaceId = WorkspaceDescriptor.ID()
        let otherWorkspaceId = WorkspaceDescriptor.ID()

        let duplicateCodes = Self.invariantCodes(
            windows: [
                Self.window(token: token, workspaceId: workspaceId),
                Self.window(token: token, workspaceId: workspaceId)
            ]
        )
        XCTAssertTrue(duplicateCodes.contains("duplicate_window_token"))

        let destroyedFocusedCodes = Self.invariantCodes(
            focusedToken: token,
            windows: [
                Self.window(token: token, workspaceId: workspaceId, lifecyclePhase: .destroyed)
            ]
        )
        XCTAssertTrue(destroyedFocusedCodes.contains("selected_managed_token_destroyed"))

        let requestShapeCodes = Self.invariantCodes(
            pendingManagedFocus: PendingManagedFocusSnapshot(
                token: nil,
                workspaceId: nil,
                monitorId: nil,
                requestId: 7
            )
        )
        XCTAssertTrue(requestShapeCodes.contains("pending_focus_request_without_token"))
        XCTAssertTrue(requestShapeCodes.contains("pending_focus_request_without_workspace"))

        let mismatchCodes = Self.invariantCodes(
            pendingManagedFocus: PendingManagedFocusSnapshot(
                token: token,
                workspaceId: otherWorkspaceId,
                monitorId: nil,
                requestId: 7
            ),
            windows: [
                Self.window(token: token, workspaceId: workspaceId)
            ]
        )
        XCTAssertTrue(mismatchCodes.contains("pending_focus_workspace_mismatch"))
    }

    @MainActor
    func testWorkspaceManagerDoesNotInvalidateForNoOpRuntimeSetters() throws {
        let manager = Self.workspaceManager()
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let token = manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 9_001),
            pid: getpid(),
            windowId: 9_001,
            to: workspaceId,
            mode: .floating
        )

        let hiddenState = HiddenState(
            proportionalPosition: CGPoint(x: 0.25, y: 0.5),
            referenceMonitorId: nil,
            reason: .workspaceInactive
        )
        let allDomains: InvalidationDomain = [.workspace, .layout, .focus, .fullscreen]
        manager.setHiddenState(hiddenState, for: token)
        let afterHiddenState = manager.worldSeq
        manager.setHiddenState(hiddenState, for: token)
        XCTAssertTrue(manager.isSeqCurrent(afterHiddenState, for: workspaceId, domains: allDomains))

        let floatingState = FloatingState(
            lastFrame: CGRect(x: 10, y: 20, width: 300, height: 200),
            normalizedOrigin: CGPoint(x: 0.1, y: 0.2),
            referenceMonitorId: nil,
            restoreToFloating: true
        )
        manager.setFloatingState(floatingState, for: token)
        let afterFloatingState = manager.worldSeq
        manager.setFloatingState(floatingState, for: token)
        XCTAssertTrue(manager.isSeqCurrent(afterFloatingState, for: workspaceId, domains: allDomains))

        let constraints = WindowSizeConstraints.fixed(size: CGSize(width: 320, height: 240))
        let beforeConstraints = manager.worldSeq
        manager.setCachedConstraints(constraints, for: token)
        XCTAssertTrue(manager.isSeqCurrent(beforeConstraints, for: workspaceId, domains: allDomains))
        let afterConstraints = manager.worldSeq
        manager.setCachedConstraints(constraints, for: token)
        XCTAssertTrue(manager.isSeqCurrent(afterConstraints, for: workspaceId, domains: allDomains))
    }

    @MainActor
    func testWorkspaceManagerDoesNotGlobalInvalidateForMissingTokens() throws {
        let manager = Self.workspaceManager()
        let missingToken = WindowToken(pid: getpid(), windowId: 987_654)
        let before = manager.worldSeq

        manager.setFloatingState(
            FloatingState(
                lastFrame: CGRect(x: 10, y: 20, width: 300, height: 200),
                normalizedOrigin: CGPoint(x: 0.1, y: 0.2),
                referenceMonitorId: nil,
                restoreToFloating: true
            ),
            for: missingToken
        )
        manager.setManualLayoutOverride(.forceFloat, for: missingToken)
        manager.setCachedConstraints(.fixed(size: CGSize(width: 320, height: 240)), for: missingToken)
        manager.setHiddenState(
            HiddenState(
                proportionalPosition: .zero,
                referenceMonitorId: nil,
                reason: .workspaceInactive
            ),
            for: missingToken
        )
        XCTAssertFalse(manager.setScratchpadMembership(missingToken, to: 1))

        XCTAssertTrue(
            manager.isSeqEpochCurrent(before, domains: [.workspace, .layout, .focus, .fullscreen])
        )
    }

    @MainActor
    func testApplySessionPatchRejectsStaleLayoutSeq() throws {
        let manager = Self.workspaceManager()
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let token = manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 9_101),
            pid: getpid(),
            windowId: 9_101,
            to: workspaceId
        )
        let staleSeq = manager.worldSeq
        manager.setHiddenState(
            HiddenState(
                proportionalPosition: .zero,
                referenceMonitorId: nil,
                reason: .workspaceInactive
            ),
            for: token
        )

        let changed = manager.applySessionPatch(
            WorkspaceSessionPatch(
                workspaceId: workspaceId,
                plannedSeq: staleSeq
            )
        )

        XCTAssertFalse(changed)
    }

    @MainActor
    func testApplySessionPatchRejectsStaleRememberedFocusWithoutMutation() throws {
        let manager = Self.workspaceManager()
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let firstToken = manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 9_201),
            pid: getpid(),
            windowId: 9_201,
            to: workspaceId
        )
        let secondToken = manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 9_202),
            pid: getpid(),
            windowId: 9_202,
            to: workspaceId
        )
        let staleFocusSeq = manager.worldSeq
        _ = manager.beginManagedFocusRequest(firstToken, in: workspaceId, requestId: 7)

        let changed = manager.applySessionPatch(
            WorkspaceSessionPatch(
                workspaceId: workspaceId,
                rememberedFocusToken: secondToken,
                plannedSeq: staleFocusSeq
            )
        )

        XCTAssertFalse(changed)
        XCTAssertEqual(manager.lastFocusedToken(in: workspaceId), firstToken)
    }

    func testPostLayoutActionForwardsAcceptedSeqsAndHonorsDomains() {
        let workspaceId = WorkspaceDescriptor.ID()
        let otherWorkspaceId = WorkspaceDescriptor.ID()
        let action = RefreshPostLayoutAction(
            workspaceSeqs: [
                workspaceId: 5,
                otherWorkspaceId: 7
            ],
            domains: .layoutCommit
        ) {}

        let forwarded = action.forwarded(
            by: [workspaceId: AcceptedSeq(after: 9, domains: .layoutCommit)],
            currentAtEntry: [workspaceId]
        )
        let notCurrentAtEntry = action.forwarded(
            by: [workspaceId: AcceptedSeq(after: 9, domains: .layoutCommit)],
            currentAtEntry: []
        )
        let focusAction = RefreshPostLayoutAction(
            workspaceSeqs: [workspaceId: 5],
            domains: .focusCommit
        ) {}
        let uncoveredDomainsNotForwarded = focusAction.forwarded(
            by: [workspaceId: AcceptedSeq(after: 9, domains: .layoutCommit)],
            currentAtEntry: [workspaceId]
        )
        let coveredDomainsForwarded = focusAction.forwarded(
            by: [workspaceId: AcceptedSeq(after: 9, domains: .layoutCommit.union(.focusCommit))],
            currentAtEntry: [workspaceId]
        )

        XCTAssertEqual(forwarded.workspaceSeqs[workspaceId], 9)
        XCTAssertEqual(forwarded.workspaceSeqs[otherWorkspaceId], 7)
        XCTAssertEqual(notCurrentAtEntry.workspaceSeqs[workspaceId], 5)
        XCTAssertEqual(uncoveredDomainsNotForwarded.workspaceSeqs[workspaceId], 5)
        XCTAssertEqual(coveredDomainsForwarded.workspaceSeqs[workspaceId], 9)
        XCTAssertTrue(action.hasWorkspace(in: [workspaceId]))
    }

    @MainActor
    func testPostLayoutActionRunsInvalidationContinuationInsteadOfStaleAction() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let plannedSeq = controller.workspaceManager.worldSeq
        var ranCurrentAction = false
        var ranInvalidatedAction = false
        let action = RefreshPostLayoutAction(
            workspaceSeqs: [workspaceId: plannedSeq],
            domains: .layoutCommit,
            action: { ranCurrentAction = true },
            invalidatedAction: { ranInvalidatedAction = true }
        )

        controller.workspaceManager.invalidateLayout(for: [workspaceId])
        action.runIfCurrent(using: controller.workspaceManager)

        XCTAssertFalse(ranCurrentAction)
        XCTAssertTrue(ranInvalidatedAction)
    }

    @MainActor
    func testWorkspaceTransitionPreservesInvalidatedFocusHandoff() async throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh = true
        var ranCurrentAction = false
        var ranInvalidatedAction = false

        controller.layoutRefreshController.commitWorkspaceTransition(
            affectedWorkspaces: [workspaceId],
            postLayoutGateWorkspaceIds: [workspaceId],
            postLayout: { ranCurrentAction = true },
            postLayoutInvalidated: { ranInvalidatedAction = true }
        )
        controller.workspaceManager.invalidateLayout(for: [workspaceId])

        for _ in 0 ..< 8 {
            if let task = controller.layoutRefreshController.layoutState.activeRefreshTask {
                await task.value
            } else if controller.layoutRefreshController.layoutState.pendingRefresh == nil {
                break
            } else {
                await Task.yield()
            }
        }

        XCTAssertFalse(ranCurrentAction)
        XCTAssertTrue(ranInvalidatedAction)
    }

    @MainActor
    func testWorkspaceTransitionTrailingClosureRemainsPostLayoutAction() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .workspaceTransition,
            affectedWorkspaceIds: [workspaceId]
        )
        defer {
            blocker.cancel()
            controller.layoutRefreshController.layoutState.activeRefreshTask = nil
            controller.layoutRefreshController.layoutState.activeRefresh = nil
            controller.layoutRefreshController.layoutState.pendingRefresh = nil
        }
        var ranPostLayout = false

        controller.layoutRefreshController.commitWorkspaceTransition(
            affectedWorkspaces: [workspaceId]
        ) {
            ranPostLayout = true
        }
        let action = try XCTUnwrap(
            controller.layoutRefreshController.layoutState.pendingRefresh?.postLayoutActions.first
        )
        action.runIfCurrent(using: controller.workspaceManager)

        XCTAssertTrue(ranPostLayout)
    }

    @MainActor
    func testAnimationLayoutPlanDoesNotScheduleFullSurfaceReconcile() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        controller.surfaceReconciler.reconcileNow()

        let animationPlan = WorkspaceLayoutPlan(
            workspaceId: workspaceId,
            monitor: Self.layoutMonitorSnapshot(monitor),
            sessionPatch: WorkspaceSessionPatch(
                workspaceId: workspaceId,
                plannedSeq: controller.workspaceManager.worldSeq
            ),
            diff: WorkspaceLayoutDiff(),
            isAnimationTick: true
        )

        XCTAssertNotNil(controller.layoutRefreshController.executeLayoutPlanReturningAcceptedSeq(animationPlan))
        XCTAssertFalse(controller.surfaceReconciler.reconcileScheduled)

        var fullPlan = animationPlan
        fullPlan.isAnimationTick = false
        XCTAssertNotNil(controller.layoutRefreshController.executeLayoutPlanReturningAcceptedSeq(fullPlan))
        XCTAssertTrue(controller.surfaceReconciler.reconcileScheduled)
        controller.surfaceReconciler.reconcileNow()
    }

    @MainActor
    func testAnimationSurfaceReconcilePreservesPendingFullWorkAndOrdering() {
        let controller = Self.controller()
        controller.surfaceReconciler.noteRestackOccurred()

        controller.surfaceReconciler.reconcileAnimationTick()

        XCTAssertTrue(controller.surfaceReconciler.reconcileScheduled)
        XCTAssertTrue(controller.surfaceReconciler.forceOrderingOnNextReconcile)

        controller.surfaceReconciler.reconcileNow()

        XCTAssertFalse(controller.surfaceReconciler.reconcileScheduled)
        XCTAssertFalse(controller.surfaceReconciler.forceOrderingOnNextReconcile)
    }

    @MainActor
    func testSurfaceReconcilerCleanupCancelsPendingReconcileAndOrdering() {
        let controller = Self.controller()
        controller.surfaceReconciler.noteRestackOccurred()

        XCTAssertTrue(controller.surfaceReconciler.reconcileScheduled)
        XCTAssertTrue(controller.surfaceReconciler.forceOrderingOnNextReconcile)

        controller.surfaceReconciler.cleanup()

        XCTAssertFalse(controller.surfaceReconciler.reconcileScheduled)
        XCTAssertFalse(controller.surfaceReconciler.forceOrderingOnNextReconcile)
        XCTAssertEqual(controller.surfaceReconciler.appliedScene, .empty)
    }

    @MainActor
    func testStoppedServiceReconcileDoesNotRepopulateWorkspaceBars() {
        let controller = Self.controller()
        controller.settings.workspaceBar.enabled = true
        controller.hasStartedServices = true
        let world = WorldView(controller: controller)

        XCTAssertFalse(SurfaceDerivation.derive(world: world).bars.isEmpty)
        XCTAssertFalse(SurfaceDerivation.derive(world: world).parkingEdgeMasks.isEmpty)
        controller.surfaceReconciler.reconcileNow()
        XCTAssertFalse(controller.surfaceReconciler.appliedScene.bars.isEmpty)
        XCTAssertFalse(controller.surfaceReconciler.appliedScene.parkingEdgeMasks.isEmpty)
        XCTAssertFalse(
            controller.ownedWindowRegistry.visibleSurfaceIDs(kind: .parkingEdgeMask).isEmpty
        )

        controller.hasStartedServices = false
        controller.surfaceReconciler.cleanup()

        XCTAssertTrue(SurfaceDerivation.derive(world: world).bars.isEmpty)
        XCTAssertTrue(SurfaceDerivation.derive(world: world).parkingEdgeMasks.isEmpty)
        XCTAssertTrue(controller.ownedWindowRegistry.visibleSurfaceIDs(kind: .parkingEdgeMask).isEmpty)
        controller.surfaceReconciler.reconcileNow()
        XCTAssertTrue(controller.surfaceReconciler.appliedScene.bars.isEmpty)
        XCTAssertTrue(controller.surfaceReconciler.appliedScene.parkingEdgeMasks.isEmpty)
    }

    @MainActor
    func testAnimationBorderDerivationDropsExternalSurfaceWithoutBoundsQuery() {
        let controller = Self.controller()
        controller.hasStartedServices = true
        controller.settings.borders.enabled = true
        let token = WindowToken(pid: 765_019, windowId: 765_119)
        _ = controller.workspaceManager.recordExternalFocus(pid: token.pid, windowId: token.windowId)
        let previous = DesiredBorderSurface(
            token: token,
            frame: CGRect(x: 20, y: 30, width: 400, height: 300),
            config: BorderConfig.from(settings: controller.settings, isDark: controller.borderUsesDarkAppearance)
        )
        var boundsQueryCount = 0
        let world = WorldView(controller: controller, liveBoundsProvider: { _ in
            boundsQueryCount += 1
            return nil
        })

        let derived = SurfaceDerivation.deriveAnimationBorder(world: world, previous: previous)

        XCTAssertNil(derived)
        XCTAssertEqual(boundsQueryCount, 0)
    }

    @MainActor
    func testVerifiedFrameApplySuccessUsesCurrentFullWindowToken() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_020), windowId: 765_120),
            pid: 765_020,
            windowId: 765_120,
            to: workspaceId
        )
        XCTAssertTrue(controller.workspaceManager.setManagedFocus(token, in: workspaceId))
        controller.surfaceReconciler.reconcileNow()
        let frame = CGRect(x: 20, y: 30, width: 400, height: 300)
        let reusedWindowIdResult = Self.frameResult(
            requestId: 1,
            pid: token.pid + 1,
            windowId: token.windowId,
            expectedWindow: AXWindowRef(
                element: AXUIElementCreateApplication(token.pid + 1),
                windowId: token.windowId
            ),
            targetFrame: frame,
            currentFrameHint: nil
        )

        controller.surfaceReconciler.handleVerifiedFrameApplySuccess(reusedWindowIdResult)

        XCTAssertFalse(controller.surfaceReconciler.reconcileScheduled)

        let focusedResult = Self.frameResult(
            requestId: 2,
            pid: token.pid,
            windowId: token.windowId,
            expectedWindow: AXWindowRef(
                element: AXUIElementCreateApplication(token.pid),
                windowId: token.windowId
            ),
            targetFrame: frame,
            currentFrameHint: nil
        )

        controller.surfaceReconciler.handleVerifiedFrameApplySuccess(focusedResult)
        controller.surfaceReconciler.handleVerifiedFrameApplySuccess(focusedResult)

        XCTAssertTrue(controller.surfaceReconciler.reconcileScheduled)
        controller.surfaceReconciler.reconcileNow()
    }

    @MainActor
    func testServiceLifecycleForwardsOnlyObservedFrameSuccesses() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_021), windowId: 765_121),
            pid: 765_021,
            windowId: 765_121,
            to: workspaceId
        )
        XCTAssertTrue(controller.workspaceManager.setManagedFocus(token, in: workspaceId))
        controller.surfaceReconciler.reconcileNow()
        let frame = CGRect(x: 20, y: 30, width: 400, height: 300)
        let expectedWindow = AXWindowRef(
            element: AXUIElementCreateApplication(token.pid),
            windowId: token.windowId
        )
        let animationResult = AXFrameApplyResult(
            requestId: 1,
            pid: token.pid,
            windowId: token.windowId,
            expectedWindow: expectedWindow,
            targetFrame: frame,
            currentFrameHint: nil,
            writeResult: AXFrameWriteResult(
                observedFrame: nil,
                writeOrder: .sizeThenPosition,
                sizeError: .success,
                positionError: .success,
                failureReason: nil
            )
        )

        controller.serviceLifecycleManager.handleFrameApplySucceeded(animationResult)

        XCTAssertFalse(controller.surfaceReconciler.reconcileScheduled)

        let unconfirmedResult = AXFrameApplyResult(
            requestId: 2,
            pid: token.pid,
            windowId: token.windowId,
            expectedWindow: expectedWindow,
            targetFrame: frame,
            currentFrameHint: nil,
            writeResult: AXFrameWriteResult(
                observedFrame: frame.offsetBy(dx: 20, dy: 0),
                writeOrder: .sizeThenPosition,
                sizeError: .success,
                positionError: .success,
                failureReason: .verificationMismatch
            )
        )

        controller.serviceLifecycleManager.handleFrameApplySucceeded(unconfirmedResult)

        XCTAssertFalse(controller.surfaceReconciler.reconcileScheduled)

        let verifiedResult = Self.frameResult(
            requestId: 3,
            pid: token.pid,
            windowId: token.windowId,
            expectedWindow: expectedWindow,
            targetFrame: frame,
            currentFrameHint: nil
        )
        controller.serviceLifecycleManager.handleFrameApplySucceeded(verifiedResult)

        XCTAssertTrue(controller.surfaceReconciler.reconcileScheduled)
        controller.surfaceReconciler.reconcileNow()
    }

    @MainActor
    func testAXManagerAcceptedFrameCallbackCarriesFullResult() {
        let controller = Self.controller()
        let frame = CGRect(x: 20, y: 30, width: 400, height: 300)
        let result = Self.frameResult(
            requestId: 3,
            pid: 765_022,
            windowId: 765_122,
            expectedWindow: AXWindowRef(
                element: AXUIElementCreateApplication(765_022),
                windowId: 765_122
            ),
            targetFrame: frame,
            currentFrameHint: nil
        )
        var received: AXFrameApplyResult?
        controller.axManager.onFrameApplySucceeded = { received = $0 }

        controller.axManager.handleAcceptedFrameApplySuccess(result)

        XCTAssertEqual(received, result)
    }

    @MainActor
    func testLayoutPlanAcceptedSeqIncludesAnimationDirectiveFocusMutation() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_005), windowId: 765_105),
            pid: 765_005,
            windowId: 765_105,
            to: workspaceId
        )
        let plannedSeq = controller.workspaceManager.worldSeq

        let accepted = try XCTUnwrap(
            controller.layoutRefreshController.executeLayoutPlanReturningAcceptedSeq(
                WorkspaceLayoutPlan(
                    workspaceId: workspaceId,
                    monitor: Self.layoutMonitorSnapshot(monitor),
                    sessionPatch: WorkspaceSessionPatch(
                        workspaceId: workspaceId,
                        plannedSeq: plannedSeq
                    ),
                    diff: WorkspaceLayoutDiff(),
                    animationDirectives: [.activateWindow(token: token)]
                )
            )
        )

        XCTAssertEqual(accepted.after, controller.workspaceManager.worldSeq)
        XCTAssertFalse(
            controller.workspaceManager.isSeqCurrent(plannedSeq, for: workspaceId, domains: .focusCommit)
        )
        XCTAssertTrue(accepted.domains.contains(.focus))
        XCTAssertEqual(controller.workspaceManager.pendingFocusedToken, token)
    }

    @MainActor
    func testLayoutPlanDoesNotActivateWindowOverFocusedSystemModal() throws {
        var focusedTokens: [WindowToken] = []
        let controller = Self.controller(
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    focusedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let modalToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_009), windowId: 765_109),
            pid: 765_009,
            windowId: 765_109,
            to: workspaceId,
            mode: .floating
        )
        let layoutToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_009), windowId: 765_110),
            pid: 765_009,
            windowId: 765_110,
            to: workspaceId
        )
        XCTAssertTrue(
            controller.workspaceManager.confirmManagedFocus(
                modalToken,
                in: workspaceId,
                activateWorkspaceOnMonitor: false
            )
        )
        controller.workspaceManager.setSystemModalFocus(modalToken)
        let plannedSeq = controller.workspaceManager.worldSeq

        let accepted = controller.layoutRefreshController.executeLayoutPlanReturningAcceptedSeq(
            WorkspaceLayoutPlan(
                workspaceId: workspaceId,
                monitor: Self.layoutMonitorSnapshot(monitor),
                sessionPatch: WorkspaceSessionPatch(
                    workspaceId: workspaceId,
                    plannedSeq: plannedSeq
                ),
                diff: WorkspaceLayoutDiff(),
                animationDirectives: [.activateWindow(token: layoutToken)]
            )
        )

        XCTAssertNotNil(accepted)
        XCTAssertTrue(controller.shouldSuppressManagedFocusRecovery)
        XCTAssertEqual(controller.workspaceManager.selectedManagedToken, modalToken)
        XCTAssertNil(controller.workspaceManager.pendingFocusedToken)
        XCTAssertNil(controller.intentLedger.activeManagedRequest)
        XCTAssertTrue(focusedTokens.isEmpty)
    }

    @MainActor
    func testLayoutPlanRejectsStaleFocusSeqBeforeApplyingEffects() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let firstToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_007), windowId: 765_107),
            pid: 765_007,
            windowId: 765_107,
            to: workspaceId
        )
        let secondToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_008), windowId: 765_108),
            pid: 765_008,
            windowId: 765_108,
            to: workspaceId
        )
        let plannedSeq = controller.workspaceManager.worldSeq
        _ = controller.workspaceManager.beginManagedFocusRequest(firstToken, in: workspaceId, requestId: 7)

        let accepted = controller.layoutRefreshController.executeLayoutPlanReturningAcceptedSeq(
            WorkspaceLayoutPlan(
                workspaceId: workspaceId,
                monitor: Self.layoutMonitorSnapshot(monitor),
                sessionPatch: WorkspaceSessionPatch(
                    workspaceId: workspaceId,
                    rememberedFocusToken: secondToken,
                    plannedSeq: plannedSeq
                ),
                diff: WorkspaceLayoutDiff(),
                animationDirectives: [.activateWindow(token: secondToken)]
            )
        )

        XCTAssertNil(accepted)
        XCTAssertEqual(controller.workspaceManager.pendingFocusedToken, firstToken)
        XCTAssertNotEqual(controller.workspaceManager.lastFocusedToken(in: workspaceId), secondToken)
    }

    @MainActor
    func testOverviewLayoutPlanSuppressesWindowActivationDirective() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_006), windowId: 765_106),
            pid: 765_006,
            windowId: 765_106,
            to: workspaceId
        )
        let plannedSeq = controller.workspaceManager.worldSeq

        let accepted = try XCTUnwrap(
            controller.layoutRefreshController.executeLayoutPlanReturningAcceptedSeq(
                WorkspaceLayoutPlan(
                    workspaceId: workspaceId,
                    monitor: Self.layoutMonitorSnapshot(monitor),
                    sessionPatch: WorkspaceSessionPatch(
                        workspaceId: workspaceId,
                        plannedSeq: plannedSeq
                    ),
                    diff: WorkspaceLayoutDiff(),
                    animationDirectives: [.activateWindow(token: token)]
                ),
                suppressWindowActivation: true
            )
        )

        XCTAssertNil(controller.workspaceManager.pendingFocusedToken)
        XCTAssertTrue(
            controller.workspaceManager.isSeqCurrent(plannedSeq, for: workspaceId, domains: .focusCommit)
        )
        XCTAssertEqual(accepted.after, controller.workspaceManager.worldSeq)
    }

    @MainActor
    func testOverviewMutationSuppressionSurvivesCallbackFreeFullRescanMerge() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        controller.layoutRefreshController.layoutState.pendingRefresh = .init(
            kind: .fullRescan,
            reason: .startup
        )
        defer { controller.layoutRefreshController.resetState() }

        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .overviewMutation,
            affectedWorkspaceIds: [workspaceId]
        )

        XCTAssertTrue(
            try XCTUnwrap(
                controller.layoutRefreshController.layoutState.activeRefresh
            ).suppressesWindowActivation
        )
    }

    @MainActor
    func testLayoutCommandPostLayoutDefaultRejectsFocusInvalidation() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_013), windowId: 765_113),
            pid: 765_013,
            windowId: 765_113,
            to: workspaceId
        )
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [workspaceId]
        )
        defer {
            blocker.cancel()
            controller.layoutRefreshController.layoutState.activeRefreshTask = nil
            controller.layoutRefreshController.layoutState.activeRefresh = nil
            controller.layoutRefreshController.layoutState.pendingRefresh = nil
        }

        var didRun = false
        controller.layoutRefreshController.requestLayoutCommandRelayout(
            affectedWorkspaceIds: [workspaceId]
        ) {
            didRun = true
        }
        let action = try XCTUnwrap(controller.layoutRefreshController.layoutState.pendingRefresh?.postLayoutActions
            .first)
        _ = controller.workspaceManager.rememberFocus(token, in: workspaceId)

        action.runIfCurrent(using: controller.workspaceManager)

        XCTAssertFalse(didRun)
    }

    @MainActor
    func testLayoutCommandPostLayoutRejectsLayoutInvalidation() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_060), windowId: 765_160),
            pid: 765_060,
            windowId: 765_160,
            to: workspaceId
        )
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [workspaceId]
        )
        defer {
            blocker.cancel()
            controller.layoutRefreshController.layoutState.activeRefreshTask = nil
            controller.layoutRefreshController.layoutState.activeRefresh = nil
            controller.layoutRefreshController.layoutState.pendingRefresh = nil
        }

        var didRun = false
        controller.layoutRefreshController.requestLayoutCommandRelayout(
            affectedWorkspaceIds: [workspaceId]
        ) {
            didRun = true
        }
        let action = try XCTUnwrap(controller.layoutRefreshController.layoutState.pendingRefresh?.postLayoutActions
            .first)
        controller.workspaceManager.invalidateLayout(for: [workspaceId])

        action.runIfCurrent(using: controller.workspaceManager)

        XCTAssertFalse(didRun)
    }

    @MainActor
    func testResetStateDropsOldCancelledRefreshCompletion() async throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")

        controller.layoutRefreshController.requestRelayout(
            reason: .axWindowChanged,
            affectedWorkspaceIds: [workspaceId]
        )
        let task = try XCTUnwrap(controller.layoutRefreshController.layoutState.pendingDebounceTask)

        controller.layoutRefreshController.resetState()
        await task.value

        XCTAssertNil(controller.layoutRefreshController.layoutState.pendingRefresh)
        XCTAssertNil(controller.layoutRefreshController.layoutState.activeRefresh)
        XCTAssertNil(controller.layoutRefreshController.layoutState.activeRefreshTask)
        XCTAssertNil(controller.layoutRefreshController.layoutState.pendingDebounceTask)
    }

    @MainActor
    func testAXFrameLedgerIgnoresStaleResultsAfterNewerRequest() throws {
        let ledger = AXFrameApplicationLedger()
        let firstFrame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let secondFrame = CGRect(x: 40, y: 50, width: 360, height: 240)
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        var firstResults: [AXFrameApplyResult] = []
        var secondResults: [AXFrameApplyResult] = []

        let firstDecision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: firstFrame),
            isRetry: false
        ) { result in
            firstResults.append(result)
        }
        let firstRequest = try XCTUnwrap(firstDecision.request)
        let secondDecision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: secondFrame),
            isRetry: false
        ) { result in
            secondResults.append(result)
        }
        let secondRequest = try XCTUnwrap(secondDecision.request)

        for delivery in secondDecision.deliveries {
            delivery.deliver()
        }
        XCTAssertEqual(firstResults.map(\.writeResult.failureReason), [.cancelled])

        let staleOutcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: firstRequest)
        ])
        XCTAssertTrue(staleOutcome.deliveries.isEmpty)
        XCTAssertTrue(staleOutcome.retries.isEmpty)
        XCTAssertEqual(ledger.pendingFrameWrite(for: 10), secondFrame)

        let currentOutcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: secondRequest)
        ])
        XCTAssertEqual(currentOutcome.deliveries.count, 1)
        for delivery in currentOutcome.deliveries {
            delivery.deliver()
        }
        XCTAssertEqual(secondResults.map(\.requestId), [secondRequest.requestId])
        XCTAssertEqual(ledger.lastAppliedFrame(for: 10), secondFrame)
        XCTAssertFalse(ledger.hasPendingFrameWrite(for: 10))
    }

    @MainActor
    func testAXFrameLedgerPreservesPendingAllComponentsWhenPositionSupersedes() throws {
        let ledger = AXFrameApplicationLedger()
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        let first = ledger.prepareFrameApplication(
            .init(
                pid: getpid(),
                window: window,
                frame: CGRect(x: 10, y: 20, width: 300, height: 200),
                components: .all
            ),
            isRetry: false,
            terminalObserver: nil
        )
        XCTAssertEqual(try XCTUnwrap(first.request).components, .all)

        let second = ledger.prepareFrameApplication(
            .init(
                pid: getpid(),
                window: window,
                frame: CGRect(x: 40, y: 50, width: 300, height: 200),
                components: .position
            ),
            isRetry: false,
            terminalObserver: nil
        )

        XCTAssertEqual(try XCTUnwrap(second.request).components, .all)
    }

    @MainActor
    func testAXFrameLedgerUnionsPendingPositionAndSizeComponents() throws {
        let ledger = AXFrameApplicationLedger()
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        let first = ledger.prepareFrameApplication(
            .init(
                pid: getpid(),
                window: window,
                frame: CGRect(x: 10, y: 20, width: 300, height: 200),
                components: .position
            ),
            isRetry: false,
            terminalObserver: nil
        )
        XCTAssertEqual(try XCTUnwrap(first.request).components, .position)

        let second = ledger.prepareFrameApplication(
            .init(
                pid: getpid(),
                window: window,
                frame: CGRect(x: 10, y: 20, width: 360, height: 240),
                components: .size
            ),
            isRetry: false,
            terminalObserver: nil
        )

        XCTAssertEqual(try XCTUnwrap(second.request).components, .all)
    }

    @MainActor
    func testAXFrameLedgerPreservesVerificationAndCancelsSupersededObserver() throws {
        let ledger = AXFrameApplicationLedger()
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        let firstFrame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let latestFrame = CGRect(x: 40, y: 50, width: 300, height: 200)
        var terminalResults: [AXFrameApplyResult] = []
        let first = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: firstFrame, components: .all),
            isRetry: false,
            verify: true,
            terminalObserver: { terminalResults.append($0) }
        )
        XCTAssertNotNil(first.request)

        let second = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: latestFrame, components: .position),
            isRetry: false,
            verify: false,
            terminalObserver: nil
        )
        let latestRequest = try XCTUnwrap(second.request)

        XCTAssertEqual(latestRequest.components, .all)
        XCTAssertTrue(latestRequest.verify)
        XCTAssertEqual(second.deliveries.count, 1)
        for delivery in second.deliveries {
            delivery.deliver()
        }
        XCTAssertEqual(terminalResults.map(\.targetFrame), [firstFrame])
        XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [.cancelled])

        let outcome = ledger.handleFrameApplyResults([Self.frameResult(for: latestRequest)])
        for delivery in outcome.deliveries {
            delivery.deliver()
        }

        XCTAssertEqual(terminalResults.map(\.targetFrame), [firstFrame])
    }

    @MainActor
    func testPendingParksAwaitingSkyLightMoveExcludeWindowsAlreadyMovedBySkyLight() {
        let manager = AXManager()
        defer { manager.cleanup() }
        let pid: pid_t = 71038
        manager.markParkPending(for: 10, pid: pid)
        manager.markParkPending(for: 20, pid: pid)
        manager.recordSkyLightMove(windowId: 20, origin: CGPoint(x: -799, y: 16))
        manager.recordSkyLightMove(windowId: 30, origin: CGPoint(x: 2559, y: 16))

        XCTAssertEqual(manager.pendingParkWindowIds, [10, 20])
        XCTAssertEqual(manager.pendingParkWindowIdsAwaitingSkyLightMove, [10])

        manager.clearSkyLightLivePosition(for: 20)

        XCTAssertEqual(manager.pendingParkWindowIdsAwaitingSkyLightMove, [10, 20])
    }

    @MainActor
    func testAcceptedFrameApplyClearsOnlyItsSkyLightLiveOrigin() {
        let manager = AXManager()
        defer { manager.cleanup() }
        let pid: pid_t = 71037
        let firstWindow = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: 10)
        let firstFrame = CGRect(x: 10, y: 20, width: 300, height: 200)
        manager.recordSkyLightMove(windowId: 10, origin: firstFrame.origin)
        manager.recordSkyLightMove(windowId: 20, origin: CGPoint(x: 50, y: 60))

        manager.handleAcceptedFrameApplySuccess(
            AXFrameApplyResult(
                pid: pid,
                windowId: 10,
                expectedWindow: firstWindow,
                targetFrame: firstFrame,
                currentFrameHint: nil,
                writeResult: AXFrameWriteResult(
                    observedFrame: firstFrame,
                    writeOrder: .sizeThenPosition,
                    sizeError: .success,
                    positionError: .success,
                    failureReason: nil,
                    components: .all
                )
            )
        )

        XCTAssertNil(manager.skyLightLivePosition(for: 10))
        XCTAssertEqual(manager.skyLightLivePosition(for: 20), CGPoint(x: 50, y: 60))
    }

    @MainActor
    func testAXManagerCleanupInvalidatesAnimationFrameComponentProvenance() {
        let manager = AXManager()
        let windowId = 10
        let frame = CGRect(x: 40, y: 50, width: 300, height: 200)
        let translatedFrame = frame.offsetBy(dx: 30, dy: 0)
        let resizedFrame = CGRect(
            x: translatedFrame.minX,
            y: translatedFrame.minY,
            width: translatedFrame.width + 20,
            height: translatedFrame.height
        )
        manager.confirmFrameWrite(for: windowId, frame: frame)
        manager.recordSkyLightMove(windowId: windowId, origin: translatedFrame.origin)

        XCTAssertEqual(
            manager.animationFrameComponents(for: windowId, targetFrame: translatedFrame),
            .position
        )
        XCTAssertEqual(
            manager.animationFrameComponents(for: windowId, targetFrame: resizedFrame),
            .all
        )

        manager.cleanup()

        XCTAssertNil(manager.lastAppliedFrame(for: windowId))
        XCTAssertNil(manager.skyLightLivePosition(for: windowId))
        XCTAssertEqual(
            manager.animationFrameComponents(for: windowId, targetFrame: translatedFrame),
            .all
        )
    }

    @MainActor
    func testAnimationFrameChangeRoutesTrustedSizesToPositionOnlyWrites() {
        let manager = AXManager()
        let token = WindowToken(pid: 4_733, windowId: 4_734)
        let frame = CGRect(x: 40, y: 50, width: 300, height: 200)
        let change = LayoutFrameChange(token: token, frame: frame, forceApply: false)

        let untracked = manager.animationFrameChange(change)
        XCTAssertEqual(untracked.components, .all)
        XCTAssertEqual(untracked.frame, frame)

        manager.confirmFrameWrite(for: token.windowId, frame: frame)
        let translated = manager.animationFrameChange(
            change.writing(frame.offsetBy(dx: 30, dy: 0), components: .all)
        )
        XCTAssertEqual(translated.components, .position)
        XCTAssertEqual(translated.frame, frame.offsetBy(dx: 30, dy: 0))

        let resized = manager.animationFrameChange(
            change.writing(frame.insetBy(dx: -20, dy: 0), components: .all)
        )
        XCTAssertEqual(resized.components, .all)
        XCTAssertEqual(resized.frame, frame.insetBy(dx: -20, dy: 0))
    }

    @MainActor
    func testAXFrameLedgerRekeysPendingRequestBeforeCompletion() throws {
        let ledger = AXFrameApplicationLedger()
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        var results: [AXFrameApplyResult] = []
        let decision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: frame),
            isRetry: false
        ) { result in
            results.append(result)
        }
        let request = try XCTUnwrap(decision.request)

        ledger.rekeyWindowState(oldWindowId: 10, newWindowId: 20)
        let outcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: request)
        ])
        XCTAssertEqual(outcome.deliveries.count, 1)
        for delivery in outcome.deliveries {
            delivery.deliver()
        }

        XCTAssertEqual(results.map(\.windowId), [20])
        XCTAssertEqual(ledger.lastAppliedFrame(for: 20), frame)
        XCTAssertFalse(ledger.hasPendingFrameWrite(for: 20))
    }

    @MainActor
    func testAXFrameLedgerRetriesRekeyCancelledOldIdCompletion() throws {
        let ledger = AXFrameApplicationLedger()
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        let rekeyedWindow = AXWindowRef(element: window.element, windowId: 20)
        var results: [AXFrameApplyResult] = []
        let firstDecision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: frame),
            isRetry: false
        ) { result in
            results.append(result)
        }
        let firstRequest = try XCTUnwrap(firstDecision.request)

        ledger.rekeyWindowState(oldWindowId: 10, newWindowId: 20)
        let cancelledOldCompletion = Self.frameResult(for: firstRequest, failureReason: .cancelled)
        let cancelledOutcome = ledger.handleFrameApplyResults([cancelledOldCompletion])

        XCTAssertTrue(cancelledOutcome.deliveries.isEmpty)
        XCTAssertEqual(cancelledOutcome.retries, [
            AXFrameRetryRequest(
                requestId: firstRequest.requestId,
                pid: getpid(),
                windowId: 20,
                expectedWindow: rekeyedWindow,
                frame: frame,
                currentFrameHint: firstRequest.currentFrameHint
            )
        ])

        let retryDecision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: rekeyedWindow, frame: frame),
            isRetry: true,
            terminalObserver: nil
        )
        let retryRequest = try XCTUnwrap(retryDecision.request)
        let retryOutcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: retryRequest)
        ])
        for delivery in retryOutcome.deliveries {
            delivery.deliver()
        }

        XCTAssertEqual(results.map(\.requestId), [retryRequest.requestId])
        XCTAssertEqual(ledger.lastAppliedFrame(for: 20), frame)
    }

    @MainActor
    func testAXFrameLedgerTransfersObserverToRetryRequest() throws {
        let ledger = AXFrameApplicationLedger()
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        var results: [AXFrameApplyResult] = []
        let firstDecision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: frame),
            isRetry: false
        ) { result in
            results.append(result)
        }
        let firstRequest = try XCTUnwrap(firstDecision.request)

        let failedOutcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: firstRequest, failureReason: .staleElement)
        ])
        XCTAssertTrue(failedOutcome.deliveries.isEmpty)
        XCTAssertEqual(failedOutcome.retries, [
            AXFrameRetryRequest(
                requestId: firstRequest.requestId,
                pid: getpid(),
                windowId: 10,
                expectedWindow: window,
                frame: frame,
                currentFrameHint: firstRequest.currentFrameHint
            )
        ])

        let retryDecision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: frame),
            isRetry: true,
            terminalObserver: nil
        )
        let retryRequest = try XCTUnwrap(retryDecision.request)

        let staleOutcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: firstRequest)
        ])
        XCTAssertTrue(staleOutcome.deliveries.isEmpty)

        let retryOutcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: retryRequest)
        ])
        XCTAssertEqual(retryOutcome.deliveries.count, 1)
        for delivery in retryOutcome.deliveries {
            delivery.deliver()
        }
        XCTAssertEqual(results.map(\.requestId), [retryRequest.requestId])
        XCTAssertEqual(ledger.lastAppliedFrame(for: 10), frame)
    }

    @MainActor
    func testAXFrameLedgerTransfersObserverToSameTargetNonRetryReplacement() throws {
        let ledger = AXFrameApplicationLedger()
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        var firstResults: [AXFrameApplyResult] = []
        var secondResults: [AXFrameApplyResult] = []
        let firstDecision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: frame),
            isRetry: false
        ) { result in
            firstResults.append(result)
        }
        let firstRequest = try XCTUnwrap(firstDecision.request)

        let failedOutcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: firstRequest, failureReason: .staleElement)
        ])
        XCTAssertEqual(failedOutcome.retries, [
            AXFrameRetryRequest(
                requestId: firstRequest.requestId,
                pid: getpid(),
                windowId: 10,
                expectedWindow: window,
                frame: frame,
                currentFrameHint: firstRequest.currentFrameHint
            )
        ])

        let secondDecision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: frame),
            isRetry: false
        ) { result in
            secondResults.append(result)
        }
        let secondRequest = try XCTUnwrap(secondDecision.request)

        let currentOutcome = ledger.handleFrameApplyResults([
            Self.frameResult(for: secondRequest)
        ])
        XCTAssertEqual(currentOutcome.deliveries.count, 1)
        for delivery in currentOutcome.deliveries {
            delivery.deliver()
        }
        XCTAssertEqual(firstResults.map(\.requestId), [secondRequest.requestId])
        XCTAssertEqual(secondResults.map(\.requestId), [secondRequest.requestId])
        XCTAssertEqual(ledger.lastAppliedFrame(for: 10), frame)
    }

    @MainActor
    func testAXFrameLedgerOldIdCancelAndSuppressDoNotDestroyRekeyedState() throws {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let cancelLedger = AXFrameApplicationLedger()
        let cancelWindow = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        let rekeyedCancelWindow = AXWindowRef(element: cancelWindow.element, windowId: 20)
        var cancelResults: [AXFrameApplyResult] = []
        let cancelDecision = cancelLedger.prepareFrameApplication(
            .init(pid: getpid(), window: cancelWindow, frame: frame),
            isRetry: false,
            terminalObserver: { result in
                cancelResults.append(result)
            }
        )
        let cancelRequest = try XCTUnwrap(cancelDecision.request)
        cancelLedger.rekeyWindowState(oldWindowId: 10, newWindowId: 20)
        XCTAssertEqual(cancelLedger.resolvedWindowId(for: 10), 20)
        XCTAssertTrue(cancelLedger.cancelFrameJob(windowId: 10).isEmpty)
        XCTAssertEqual(cancelLedger.resolvedWindowId(for: 10), 20)
        XCTAssertTrue(cancelLedger.hasPendingFrameWrite(for: 20))
        XCTAssertTrue(cancelResults.isEmpty)
        XCTAssertEqual(
            cancelLedger.handleFrameApplyResults([
                Self.frameResult(for: cancelRequest, failureReason: .cancelled)
            ]).retries,
            [AXFrameRetryRequest(
                requestId: cancelRequest.requestId,
                pid: getpid(),
                windowId: 20,
                expectedWindow: rekeyedCancelWindow,
                frame: frame,
                currentFrameHint: cancelRequest.currentFrameHint
            )]
        )

        let suppressLedger = AXFrameApplicationLedger()
        let suppressWindow = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 30)
        let suppressDecision = suppressLedger.prepareFrameApplication(
            .init(pid: getpid(), window: suppressWindow, frame: frame),
            isRetry: false,
            terminalObserver: nil
        )
        XCTAssertNotNil(suppressDecision.request)
        suppressLedger.rekeyWindowState(oldWindowId: 30, newWindowId: 40)
        XCTAssertEqual(suppressLedger.resolvedWindowId(for: 30), 40)
        XCTAssertTrue(suppressLedger.suppressFrameWrite(windowId: 30).isEmpty)
        XCTAssertEqual(suppressLedger.resolvedWindowId(for: 30), 40)
        XCTAssertTrue(suppressLedger.hasPendingFrameWrite(for: 40))
    }

    @MainActor
    func testAXFrameLedgerLiveIdCancelSuppressAndRemoveClearRekeyedState() throws {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let cancelLedger = AXFrameApplicationLedger()
        let cancelWindow = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        var cancelResults: [AXFrameApplyResult] = []
        let cancelDecision = cancelLedger.prepareFrameApplication(
            .init(pid: getpid(), window: cancelWindow, frame: frame),
            isRetry: false,
            terminalObserver: { result in
                cancelResults.append(result)
            }
        )
        let cancelRequest = try XCTUnwrap(cancelDecision.request)
        cancelLedger.rekeyWindowState(oldWindowId: 10, newWindowId: 20)
        for delivery in cancelLedger.cancelFrameJob(windowId: 20) {
            delivery.deliver()
        }
        XCTAssertEqual(cancelLedger.resolvedWindowId(for: 10), 10)
        XCTAssertEqual(cancelResults.map(\.writeResult.failureReason), [.cancelled])
        XCTAssertFalse(cancelLedger.hasPendingFrameWrite(for: 20))
        XCTAssertTrue(
            cancelLedger.handleFrameApplyResults([
                Self.frameResult(for: cancelRequest, failureReason: .cancelled)
            ]).deliveries.isEmpty
        )

        let suppressLedger = AXFrameApplicationLedger()
        let suppressWindow = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 30)
        let suppressDecision = suppressLedger.prepareFrameApplication(
            .init(pid: getpid(), window: suppressWindow, frame: frame),
            isRetry: false,
            terminalObserver: nil
        )
        XCTAssertNotNil(suppressDecision.request)
        suppressLedger.rekeyWindowState(oldWindowId: 30, newWindowId: 40)
        _ = suppressLedger.suppressFrameWrite(windowId: 40)
        XCTAssertEqual(suppressLedger.resolvedWindowId(for: 30), 30)
        XCTAssertFalse(suppressLedger.hasPendingFrameWrite(for: 40))

        let removeLedger = AXFrameApplicationLedger()
        let removeWindow = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 50)
        var removeResults: [AXFrameApplyResult] = []
        let removeDecision = removeLedger.prepareFrameApplication(
            .init(pid: getpid(), window: removeWindow, frame: frame),
            isRetry: false,
            terminalObserver: { result in
                removeResults.append(result)
            }
        )
        let removeRequest = try XCTUnwrap(removeDecision.request)
        removeLedger.rekeyWindowState(oldWindowId: 50, newWindowId: 60)
        for delivery in removeLedger.removeWindowState(windowId: 60) {
            delivery.deliver()
        }
        XCTAssertEqual(removeLedger.resolvedWindowId(for: 50), 50)
        XCTAssertEqual(removeResults.map(\.writeResult.failureReason), [.cancelled])
        XCTAssertFalse(removeLedger.hasPendingFrameWrite(for: 60))
        XCTAssertTrue(
            removeLedger.handleFrameApplyResults([
                Self.frameResult(for: removeRequest)
            ]).deliveries.isEmpty
        )
    }

    @MainActor
    func testAXFrameLedgerOldWindowRemoveDoesNotRemoveRekeyedPendingState() throws {
        let ledger = AXFrameApplicationLedger()
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: 10)
        let rekeyedWindow = AXWindowRef(element: window.element, windowId: 20)
        var results: [AXFrameApplyResult] = []
        let decision = ledger.prepareFrameApplication(
            .init(pid: getpid(), window: window, frame: frame),
            isRetry: false,
            terminalObserver: { result in
                results.append(result)
            }
        )
        let request = try XCTUnwrap(decision.request)

        ledger.rekeyWindowState(oldWindowId: 10, newWindowId: 20)
        XCTAssertEqual(ledger.resolvedWindowId(for: 10), 20)
        XCTAssertTrue(ledger.removeWindowState(windowId: 10).isEmpty)

        XCTAssertEqual(ledger.resolvedWindowId(for: 10), 20)
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(ledger.hasPendingFrameWrite(for: 20))
        XCTAssertEqual(
            ledger.handleFrameApplyResults([
                Self.frameResult(for: request, failureReason: .cancelled)
            ]).retries,
            [AXFrameRetryRequest(
                requestId: request.requestId,
                pid: getpid(),
                windowId: 20,
                expectedWindow: rekeyedWindow,
                frame: frame,
                currentFrameHint: request.currentFrameHint
            )]
        )
    }

    @MainActor
    func testAXFrameLedgerClearsSettledRekeyAliasWhenNoPendingState() {
        let ledger = AXFrameApplicationLedger()
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)

        ledger.confirmFrameWrite(for: 10, frame: frame)
        ledger.rekeyWindowState(oldWindowId: 10, newWindowId: 20)
        XCTAssertEqual(ledger.lastAppliedFrame(for: 20), frame)
        XCTAssertEqual(ledger.resolvedWindowId(for: 10), 10)

        let updatedFrame = CGRect(x: 30, y: 40, width: 500, height: 300)
        ledger.confirmFrameWrite(for: 10, frame: updatedFrame)

        XCTAssertEqual(ledger.lastAppliedFrame(for: 10), updatedFrame)
        XCTAssertEqual(ledger.lastAppliedFrame(for: 20), frame)
    }

    @MainActor
    func testManagedRetirementRemovesWorldBeforeTerminalFrameObserverDelivery() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let pid: pid_t = 765_011
        let windowId = 765_111
        let window = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId)
        let token = controller.workspaceManager.addWindow(
            window,
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
        var terminalResults: [AXFrameApplyResult] = []
        var worldOwnersDuringDelivery: [WindowToken?] = []

        controller.axManager.applyFramesParallel([
            .init(
                pid: pid,
                window: window,
                frame: CGRect(x: 10, y: 20, width: 300, height: 200)
            )
        ]) { result in
            terminalResults.append(result)
            worldOwnersDuringDelivery.append(
                controller.workspaceManager.entry(forWindowId: windowId)?.token
            )
        }
        XCTAssertTrue(terminalResults.isEmpty)

        controller.axEventHandler.handleRemoved(token: token)

        XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [.cancelled])
        XCTAssertEqual(worldOwnersDuringDelivery, [nil])
        XCTAssertNil(controller.workspaceManager.entry(forWindowId: windowId))
    }

    @MainActor
    func testLayoutInvalidationCancelsPendingAXFrameObserverThroughControllerWiring() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let pid: pid_t = 765_001
        let windowId = 765_101
        let axRef = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId)
        let token = controller.workspaceManager.addWindow(
            axRef,
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
        var terminalResults: [AXFrameApplyResult] = []

        controller.axManager.applyFramesParallel(
            [.init(pid: pid, window: axRef, frame: CGRect(x: 10, y: 20, width: 300, height: 200))]
        ) { result in
            terminalResults.append(result)
        }
        XCTAssertTrue(terminalResults.isEmpty)

        controller.workspaceManager.setHiddenState(
            HiddenState(
                proportionalPosition: .zero,
                referenceMonitorId: nil,
                reason: .workspaceInactive
            ),
            for: token
        )

        XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [.cancelled])
    }

    @MainActor
    func testFocusOnlyInvalidationDoesNotCancelPendingAXFrameObserverThroughControllerWiring() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let pid: pid_t = 765_002
        let windowId = 765_102
        let axRef = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId)
        let token = controller.workspaceManager.addWindow(
            axRef,
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
        var terminalResults: [AXFrameApplyResult] = []

        controller.axManager.applyFramesParallel(
            [.init(pid: pid, window: axRef, frame: CGRect(x: 10, y: 20, width: 300, height: 200))]
        ) { result in
            terminalResults.append(result)
        }
        XCTAssertTrue(terminalResults.isEmpty)

        _ = controller.workspaceManager.beginManagedFocusRequest(token, in: workspaceId, requestId: 7)
        XCTAssertTrue(terminalResults.isEmpty)

        controller.axManager.cancelPendingFrameJobs([(pid, windowId)], reason: "test")
        XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [.cancelled])
    }

    @MainActor
    func testPureLayoutInvalidationDoesNotCancelPendingAXFrameObserverThroughControllerWiring() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let pid: pid_t = 765_008
        let windowId = 765_108
        let axRef = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId)
        let token = controller.workspaceManager.addWindow(
            axRef,
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
        var terminalResults: [AXFrameApplyResult] = []

        controller.axManager.applyFramesParallel(
            [.init(pid: pid, window: axRef, frame: CGRect(x: 10, y: 20, width: 300, height: 200))]
        ) { result in
            terminalResults.append(result)
        }
        XCTAssertTrue(terminalResults.isEmpty)

        controller.workspaceManager.setManualLayoutOverride(.forceFloat, for: token)
        XCTAssertTrue(terminalResults.isEmpty)

        controller.axManager.cancelPendingFrameJobs([(pid, windowId)], reason: "test")
        XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [.cancelled])
    }

    @MainActor
    func testSuppressedLayoutInvalidationDoesNotCancelPendingAXFrameObserverThroughControllerWiring() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let pid: pid_t = 765_003
        let windowId = 765_103
        let axRef = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId)
        let token = controller.workspaceManager.addWindow(
            axRef,
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
        var terminalResults: [AXFrameApplyResult] = []

        controller.axManager.applyFramesParallel(
            [.init(pid: pid, window: axRef, frame: CGRect(x: 10, y: 20, width: 300, height: 200))]
        ) { result in
            terminalResults.append(result)
        }
        XCTAssertTrue(terminalResults.isEmpty)

        controller.withRuntimeFrameJobCancellationSuppressed {
            controller.workspaceManager.setHiddenState(
                HiddenState(
                    proportionalPosition: .zero,
                    referenceMonitorId: nil,
                    reason: .workspaceInactive
                ),
                for: token
            )
        }
        XCTAssertTrue(terminalResults.isEmpty)

        controller.axManager.cancelPendingFrameJobs([(pid, windowId)], reason: "test")
        XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [.cancelled])
    }

    @MainActor
    func testPendingScratchpadRevealUsesLiveWorkspaceAfterReassignment() throws {
        let controller = Self.controller()
        let sourceWorkspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let destinationWorkspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "2", createIfMissing: true)
        )
        let pid: pid_t = 765_004
        let windowId = 765_104
        let targetFrame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: sourceWorkspaceId,
            mode: .floating
        )
        let staleEntry = try XCTUnwrap(controller.workspaceManager.entry(for: token))
        let hiddenState = HiddenState(
            proportionalPosition: .zero,
            referenceMonitorId: nil,
            reason: .scratchpad
        )
        controller.workspaceManager.setScratchpadMembership(token, to: 1)
        controller.workspaceManager.setHiddenState(hiddenState, for: token)
        controller.reassignManagedWindow(token, to: destinationWorkspaceId)

        let transactionId = try XCTUnwrap(
            controller.layoutRefreshController.beginPendingRevealTransaction(
                for: staleEntry,
                hiddenState: hiddenState,
                targetFrame: targetFrame,
                monitor: controller.workspaceManager.monitor(for: destinationWorkspaceId) ?? Monitor.fallback()
            )
        )
        controller.workspaceManager.setManualLayoutOverride(.forceFloat, for: token)
        controller.axManager.confirmFrameWrite(for: windowId, frame: targetFrame)
        XCTAssertEqual(controller.axManager.lastAppliedFrame(for: windowId), targetFrame)
        controller.layoutRefreshController.completePendingRevealTransaction(
            with: Self.frameResult(
                requestId: 1,
                pid: pid,
                windowId: windowId,
                expectedWindow: staleEntry.axRef,
                targetFrame: targetFrame,
                currentFrameHint: nil
            ),
            transactionId: transactionId
        )

        XCTAssertEqual(controller.workspaceManager.hiddenState(for: token), hiddenState)
        XCTAssertNil(controller.axManager.lastAppliedFrame(for: windowId))
    }

    @MainActor
    func testPendingScratchpadRevealSuccessActionRejectsStaleFocusSeq() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let pid: pid_t = 765_006
        let windowId = 765_106
        let targetFrame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId,
            mode: .floating
        )
        let focusToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: 765_206),
            pid: pid,
            windowId: 765_206,
            to: workspaceId
        )
        let hiddenState = HiddenState(
            proportionalPosition: .zero,
            referenceMonitorId: nil,
            reason: .scratchpad
        )
        var didRun = false

        controller.workspaceManager.setScratchpadMembership(token, to: 1)
        controller.workspaceManager.setHiddenState(hiddenState, for: token)
        let entry = try XCTUnwrap(controller.workspaceManager.entry(for: token))
        let transactionId = try XCTUnwrap(
            controller.layoutRefreshController.beginPendingRevealTransaction(
                for: entry,
                hiddenState: hiddenState,
                targetFrame: targetFrame,
                monitor: monitor,
                onSuccess: {
                    didRun = true
                }
            )
        )
        _ = controller.workspaceManager.beginManagedFocusRequest(focusToken, in: workspaceId, requestId: 99)

        controller.layoutRefreshController.completePendingRevealTransaction(
            with: Self.frameResult(
                requestId: 1,
                pid: pid,
                windowId: windowId,
                expectedWindow: entry.axRef,
                targetFrame: targetFrame,
                currentFrameHint: nil
            ),
            transactionId: transactionId
        )

        XCTAssertNil(controller.workspaceManager.hiddenState(for: token))
        XCTAssertFalse(didRun)
    }

    @MainActor
    func testPendingScratchpadRevealSuccessActionRebasesLocalHiddenMutation() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let monitor = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId))
        let pid: pid_t = 765_007
        let windowId = 765_107
        let targetFrame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId,
            mode: .floating
        )
        let hiddenState = HiddenState(
            proportionalPosition: .zero,
            referenceMonitorId: nil,
            reason: .scratchpad
        )
        var didRun = false

        controller.workspaceManager.setScratchpadMembership(token, to: 1)
        controller.workspaceManager.setHiddenState(hiddenState, for: token)
        let entry = try XCTUnwrap(controller.workspaceManager.entry(for: token))
        let transactionId = try XCTUnwrap(
            controller.layoutRefreshController.beginPendingRevealTransaction(
                for: entry,
                hiddenState: hiddenState,
                targetFrame: targetFrame,
                monitor: monitor,
                onSuccess: {
                    didRun = true
                }
            )
        )

        controller.layoutRefreshController.completePendingRevealTransaction(
            with: Self.frameResult(
                requestId: 1,
                pid: pid,
                windowId: windowId,
                expectedWindow: entry.axRef,
                targetFrame: targetFrame,
                currentFrameHint: nil
            ),
            transactionId: transactionId
        )

        XCTAssertNil(controller.workspaceManager.hiddenState(for: token))
        XCTAssertTrue(didRun)
    }

    @MainActor
    func testDwindleFocusNeighborFocusesSelectedWindowSynchronously() throws {
        var focusedTokens: [WindowToken] = []
        let controller = Self.controller(
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    focusedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let engine = DwindleLayoutEngine()
        engine.animationClock = controller.animationClock
        controller.dwindleEngine = engine
        let firstToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_040), windowId: 765_140),
            pid: 765_040,
            windowId: 765_140,
            to: workspaceId
        )
        let secondToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_041), windowId: 765_141),
            pid: 765_041,
            windowId: 765_141,
            to: workspaceId
        )
        let thirdToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_042), windowId: 765_142),
            pid: 765_042,
            windowId: 765_142,
            to: workspaceId
        )
        _ = engine.addWindow(token: firstToken, to: workspaceId, activeWindowFrame: nil)
        _ = engine.addWindow(token: secondToken, to: workspaceId, activeWindowFrame: nil)
        _ = engine.addWindow(token: thirdToken, to: workspaceId, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: workspaceId, screen: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        let firstLeaf = try XCTUnwrap(engine.findNode(for: firstToken, in: workspaceId))
        controller.workspaceManager.withEngineMutationScope {
            engine.setSelectedNode(firstLeaf, in: workspaceId)
        }

        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [workspaceId]
        )
        defer {
            blocker.cancel()
            controller.layoutRefreshController.layoutState.activeRefreshTask = nil
            controller.layoutRefreshController.layoutState.activeRefresh = nil
            controller.layoutRefreshController.layoutState.pendingRefresh = nil
        }

        XCTAssertTrue(controller.dwindleLayoutHandler.focusNeighbor(direction: .right))
        XCTAssertTrue(controller.dwindleLayoutHandler.focusNeighbor(direction: .right))
        XCTAssertTrue(controller.dwindleLayoutHandler.focusNeighbor(direction: .left))

        XCTAssertEqual(focusedTokens, [secondToken, thirdToken, secondToken])
        XCTAssertEqual(engine.selectedNode(in: workspaceId)?.windowToken, secondToken)
    }

    @MainActor
    func testDwindleActivateWindowFocusesSynchronouslyWhenLayoutRefreshBlocked() throws {
        var focusedTokens: [WindowToken] = []
        let controller = Self.controller(
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    focusedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let engine = DwindleLayoutEngine()
        engine.animationClock = controller.animationClock
        controller.dwindleEngine = engine
        let firstToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_050), windowId: 765_150),
            pid: 765_050,
            windowId: 765_150,
            to: workspaceId
        )
        let secondToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_051), windowId: 765_151),
            pid: 765_051,
            windowId: 765_151,
            to: workspaceId
        )
        _ = engine.addWindow(token: firstToken, to: workspaceId, activeWindowFrame: nil)
        _ = engine.addWindow(token: secondToken, to: workspaceId, activeWindowFrame: nil)

        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [workspaceId]
        )
        defer {
            blocker.cancel()
            controller.layoutRefreshController.layoutState.activeRefreshTask = nil
            controller.layoutRefreshController.layoutState.activeRefresh = nil
            controller.layoutRefreshController.layoutState.pendingRefresh = nil
        }

        controller.dwindleLayoutHandler.activateWindow(firstToken, in: workspaceId, layoutRefresh: true)

        XCTAssertEqual(focusedTokens, [firstToken])
    }

    @MainActor
    func testStructuralReplacementUsesCapturedWindowServerEvidenceWithoutLiveQueries() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let frame = CGRect(x: 160, y: 120, width: 720, height: 520)
        let oldToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_515), windowId: 765_615),
            pid: 765_515,
            windowId: 765_615,
            to: workspaceId,
            managedReplacementMetadata: Self.managedReplacementMetadata(
                workspaceId: workspaceId,
                pid: 765_515,
                frame: frame
            )
        )
        let newToken = WindowToken(pid: oldToken.pid, windowId: 765_616)
        let newWindowInfo = Self.visibleWindowInfo(
            pid: newToken.pid,
            windowId: newToken.windowId,
            frame: frame
        )
        var visibleQueryCount = 0
        var windowQueryCount = 0
        controller.axEventHandler.visibleWindowInfoProvider = {
            visibleQueryCount += 1
            return []
        }
        controller.axEventHandler.windowInfoProvider = { _ in
            windowQueryCount += 1
            return nil
        }

        let match = controller.axEventHandler.structuralReplacementMatch(
            token: newToken,
            candidate: .init(
                bundleId: Self.nativeTabBundleId(pid: newToken.pid),
                mode: .tiling,
                facts: Self.nativeTabFacts(pid: newToken.pid, windowId: newToken.windowId, frame: frame)
            ),
            capturedInventory: .init(
                infoByWindowId: [newToken.windowId: newWindowInfo],
                authoritativeWindowIds: [oldToken.windowId, newToken.windowId]
            )
        )

        XCTAssertEqual(match?.token, oldToken)
        XCTAssertEqual(visibleQueryCount, 0)
        XCTAssertEqual(windowQueryCount, 0)
    }

    @MainActor
    func testStructuralReplacementRequiresCapturedWindowServerCoverageAndPIDAuthority() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let frame = CGRect(x: 160, y: 120, width: 720, height: 520)
        let oldToken = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(765_517), windowId: 765_617),
            pid: 765_517,
            windowId: 765_617,
            to: workspaceId,
            managedReplacementMetadata: Self.managedReplacementMetadata(
                workspaceId: workspaceId,
                pid: 765_517,
                frame: frame
            )
        )
        let newToken = WindowToken(pid: oldToken.pid, windowId: 765_618)
        let newWindowInfo = Self.visibleWindowInfo(
            pid: newToken.pid,
            windowId: newToken.windowId,
            frame: frame
        )
        var visibleQueryCount = 0
        var windowQueryCount = 0
        controller.axEventHandler.visibleWindowInfoProvider = {
            visibleQueryCount += 1
            return []
        }
        controller.axEventHandler.windowInfoProvider = { _ in
            windowQueryCount += 1
            return nil
        }

        let match = controller.axEventHandler.structuralReplacementMatch(
            token: newToken,
            candidate: .init(
                bundleId: Self.nativeTabBundleId(pid: newToken.pid),
                mode: .tiling,
                facts: Self.nativeTabFacts(pid: newToken.pid, windowId: newToken.windowId, frame: frame)
            ),
            capturedInventory: .init(
                infoByWindowId: [newToken.windowId: newWindowInfo],
                authoritativeWindowIds: [newToken.windowId]
            )
        )
        let pidLimitedMatch = controller.axEventHandler.structuralReplacementMatch(
            token: newToken,
            candidate: .init(
                bundleId: Self.nativeTabBundleId(pid: newToken.pid),
                mode: .tiling,
                facts: Self.nativeTabFacts(pid: newToken.pid, windowId: newToken.windowId, frame: frame)
            ),
            capturedInventory: .init(
                infoByWindowId: [newToken.windowId: newWindowInfo],
                authoritativeWindowIds: [oldToken.windowId, newToken.windowId],
                authoritativePIDs: []
            )
        )

        XCTAssertNil(match)
        XCTAssertNil(pidLimitedMatch)
        XCTAssertEqual(visibleQueryCount, 0)
        XCTAssertEqual(windowQueryCount, 0)
    }

    @MainActor
    func testBatchedLayoutBuildLeavesDwindlePlansWithoutViewportAndStampsPostBuildSeq() throws {
        let settings = Self.settingsStore()
        settings.workspaces.configurations = settings.workspaces.configurations.map {
            $0.name == "1" ? $0.with(layoutType: .dwindle) : $0
        }
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let engine = DwindleLayoutEngine()
        engine.animationClock = controller.animationClock
        controller.dwindleEngine = engine
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(766_010), windowId: 766_110),
            pid: 766_010,
            windowId: 766_110,
            to: workspaceId
        )
        _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)

        let plans = controller.workspaceManager.withBatchedLayoutBuild {
            controller.dwindleLayoutHandler.layoutWithDwindleEngine(activeWorkspaces: [workspaceId])
        }

        let committedSeq = controller.workspaceManager.worldSeq
        XCTAssertFalse(plans.isEmpty)
        for plan in plans {
            XCTAssertEqual(plan.sessionPatch.plannedSeq, committedSeq)
        }
    }

    @MainActor
    func testDwindleRelayoutDoesNotReplaceFloatingWorkspaceMRUWithTiledSelection() throws {
        let settings = Self.settingsStore()
        settings.workspaces.configurations = settings.workspaces.configurations.map {
            $0.name == "1" ? $0.with(layoutType: .dwindle) : $0
        }
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let engine = DwindleLayoutEngine()
        engine.animationClock = controller.animationClock
        controller.dwindleEngine = engine
        let tiled = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(766_030), windowId: 766_130),
            pid: 766_030,
            windowId: 766_130,
            to: workspaceId
        )
        let floating = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(766_031), windowId: 766_131),
            pid: 766_031,
            windowId: 766_131,
            to: workspaceId,
            mode: .floating
        )
        _ = controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
            engine.addWindow(token: tiled, to: workspaceId, activeWindowFrame: nil)
        }
        _ = controller.workspaceManager.rememberFocus(tiled, in: workspaceId)
        _ = controller.workspaceManager.rememberFocus(floating, in: workspaceId)

        let plans = controller.workspaceManager.withBatchedLayoutBuild {
            controller.dwindleLayoutHandler.layoutWithDwindleEngine(activeWorkspaces: [workspaceId])
        }
        let plan = try XCTUnwrap(plans.first { $0.workspaceId == workspaceId })

        XCTAssertEqual(plan.sessionPatch.rememberedFocusToken, tiled)
        XCTAssertNotNil(controller.layoutRefreshController.executeLayoutPlanReturningAcceptedSeq(plan))
        XCTAssertEqual(controller.workspaceManager.lastFocusedToken(in: workspaceId), tiled)
        XCTAssertEqual(controller.workspaceManager.lastFloatingFocusedToken(in: workspaceId), floating)
        XCTAssertEqual(
            controller.workspaceManager.resolveWorkspaceFocusToken(in: workspaceId),
            floating
        )
    }

    @MainActor
    func testAutomaticUnprovenIndependentRootDecisionPreservesModeWhileExternalSurfaceEvicts() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let unprovenRootDecision = WindowDecision(
            disposition: .unmanaged,
            source: .builtInRule(WindowRuleEngine.unprovenIndependentRootRuleName),
            layoutDecisionKind: .fallbackLayout,
            workspaceName: nil,
            ruleEffects: .none,
            heuristicReasons: [],
            deferredReason: nil
        )
        let externalSurfaceDecision = WindowDecision(
            disposition: .unmanaged,
            source: .builtInRule(WindowRuleEngine.externalSurfaceRuleName),
            layoutDecisionKind: .explicitLayout,
            workspaceName: nil,
            ruleEffects: .none,
            heuristicReasons: [],
            deferredReason: nil
        )

        for (offset, mode) in [TrackedWindowMode.tiling, .floating].enumerated() {
            let pid = pid_t(940_100 + offset)
            let windowId = 940_200 + offset
            let token = controller.workspaceManager.addWindow(
                AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
                pid: pid,
                windowId: windowId,
                to: workspaceId,
                mode: mode
            )
            let entry = try XCTUnwrap(controller.workspaceManager.entry(for: token))

            XCTAssertEqual(
                controller.trackedModePreservingAutomaticFallbackState(
                    decision: unprovenRootDecision,
                    existingEntry: entry,
                    context: .automatic
                ),
                mode
            )
            XCTAssertNil(
                controller.trackedModePreservingAutomaticFallbackState(
                    decision: externalSurfaceDecision,
                    existingEntry: entry,
                    context: .automatic
                )
            )
        }
    }

    @MainActor
    func testWindowServerResolutionUsesPreferredEvidenceOrOneTargetedLookupForAXWindows() {
        let controller = Self.controller()
        let token = WindowToken(pid: 940_301, windowId: 940_302)
        let exactWindowInfo = WindowServerInfo(
            id: 940_302,
            pid: 940_301,
            level: 0,
            frame: .zero,
            tags: 5_369_504_898,
            attributes: 3,
            parentId: 940_300
        )
        let candidateFacts = AXWindowFacts(
            role: kAXWindowRole as String,
            subrole: kAXUnknownSubrole as String,
            title: nil,
            hasCloseButton: false,
            hasFullscreenButton: false,
            fullscreenButtonEnabled: false,
            hasZoomButton: false,
            hasMinimizeButton: false,
            appPolicy: .regular,
            bundleId: "org.example.widget-host",
            attributeFetchSucceeded: true
        )
        let ordinaryFacts = AXWindowFacts(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            title: nil,
            hasCloseButton: true,
            hasFullscreenButton: true,
            fullscreenButtonEnabled: true,
            hasZoomButton: true,
            hasMinimizeButton: true,
            appPolicy: .regular,
            bundleId: "org.example.widget-host",
            attributeFetchSucceeded: true
        )
        let helpTagFacts = AXWindowFacts(
            role: kAXHelpTagRole as String,
            subrole: kAXUnknownSubrole as String,
            title: nil,
            hasCloseButton: false,
            hasFullscreenButton: false,
            fullscreenButtonEnabled: false,
            hasZoomButton: false,
            hasMinimizeButton: false,
            appPolicy: .regular,
            bundleId: "pl.maketheweb.cleanshotx",
            attributeFetchSucceeded: true
        )
        var queryCount = 0
        controller.axEventHandler.windowInfoProvider = { _ in
            queryCount += 1
            return exactWindowInfo
        }

        XCTAssertEqual(
            controller.resolveWindowServerInfoForDisposition(
                token: token,
                axFacts: ordinaryFacts,
                preferredWindowInfo: nil
            ),
            exactWindowInfo
        )
        XCTAssertEqual(queryCount, 1)
        XCTAssertNil(
            controller.resolveWindowServerInfoForDisposition(
                token: token,
                axFacts: helpTagFacts,
                preferredWindowInfo: nil
            )
        )
        XCTAssertEqual(queryCount, 1)
        XCTAssertEqual(
            controller.resolveWindowServerInfoForDisposition(
                token: token,
                axFacts: candidateFacts,
                preferredWindowInfo: exactWindowInfo
            ),
            exactWindowInfo
        )
        XCTAssertEqual(queryCount, 1)
        XCTAssertEqual(
            controller.resolveWindowServerInfoForDisposition(
                token: token,
                axFacts: candidateFacts,
                preferredWindowInfo: nil
            ),
            exactWindowInfo
        )
        XCTAssertEqual(queryCount, 2)
    }

    @MainActor
    func testTilingToFloatingCancelsTransientNativeTitleBarDragOwnership() throws {
        let controller = Self.controller()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(943_002), windowId: 943_102),
            pid: 943_002,
            windowId: 943_102,
            to: workspaceId
        )
        controller.mouseEventHandler.state.nativeTitleBarDrag = .init(token: token)
        controller.axManager.beginNativeTitleBarDrag(for: token)

        XCTAssertTrue(
            controller.transitionWindowMode(
                for: token,
                to: .floating,
                applyFloatingFrame: false,
                observedFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
                allowLiveFrameFallback: false
            )
        )

        XCTAssertEqual(controller.workspaceManager.entry(for: token)?.mode, .floating)
        XCTAssertNil(controller.mouseEventHandler.state.nativeTitleBarDrag)
        XCTAssertFalse(controller.axManager.isNativeTitleBarDragActive(for: token))
    }

    private static func snapshot(
        focusedToken: WindowToken? = nil,
        pendingManagedFocus: PendingManagedFocusSnapshot = .empty,
        nativeFocusOwner: NativeFocusOwner? = nil,
        systemModalFocusToken: WindowToken? = nil,
        interactionMonitorId: Monitor.ID? = nil,
        previousInteractionMonitorId: Monitor.ID? = nil,
        windows: [ReconcileWindowSnapshot] = [],
        layouts: [WorkspaceDescriptor.ID: LayoutTopology] = [:]
    ) -> ReconcileSnapshot {
        ReconcileSnapshot(
            topologyProfile: TopologyProfile(sortedMonitors: []),
            focusSession: FocusSessionSnapshot(
                selectedManagedToken: focusedToken,
                nativeFocusOwner: nativeFocusOwner ?? focusedToken.map(NativeFocusOwner.managed) ?? .none,
                pendingManagedFocus: pendingManagedFocus,
                focusLease: nil,
                systemModalFocusToken: systemModalFocusToken,
                interactionMonitorId: interactionMonitorId,
                previousInteractionMonitorId: previousInteractionMonitorId
            ),
            windows: windows,
            layouts: layouts
        )
    }

    private static func invariantCodes(
        focusedToken: WindowToken? = nil,
        pendingManagedFocus: PendingManagedFocusSnapshot = .empty,
        windows: [ReconcileWindowSnapshot] = []
    ) -> Set<String> {
        Set(
            InvariantChecks.validate(
                snapshot: snapshot(
                    focusedToken: focusedToken,
                    pendingManagedFocus: pendingManagedFocus,
                    windows: windows
                )
            ).map(\.code)
        )
    }

    private static func window(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        lifecyclePhase: WindowLifecyclePhase = .tiled
    ) -> ReconcileWindowSnapshot {
        ReconcileWindowSnapshot(
            token: token,
            workspaceId: workspaceId,
            mode: .tiling,
            lifecyclePhase: lifecyclePhase,
            observedState: .initial(workspaceId: workspaceId, monitorId: nil),
            desiredState: .initial(workspaceId: workspaceId, monitorId: nil, disposition: .tiling),
            restoreIntent: nil
        )
    }

    private static func frameResult(
        for request: AXFrameApplicationRequest,
        failureReason: AXFrameWriteFailureReason? = nil
    ) -> AXFrameApplyResult {
        frameResult(
            requestId: request.requestId,
            pid: request.pid,
            windowId: request.windowId,
            expectedWindow: request.expectedWindow,
            targetFrame: request.frame,
            currentFrameHint: request.currentFrameHint,
            components: request.components,
            failureReason: failureReason
        )
    }

    private static func frameResult(
        requestId: AXFrameRequestId,
        pid: pid_t,
        windowId: Int,
        expectedWindow: AXWindowRef,
        targetFrame: CGRect,
        currentFrameHint: CGRect?,
        components: AXFrameComponents = .all,
        failureReason: AXFrameWriteFailureReason? = nil
    ) -> AXFrameApplyResult {
        AXFrameApplyResult(
            requestId: requestId,
            pid: pid,
            windowId: windowId,
            expectedWindow: expectedWindow,
            targetFrame: targetFrame,
            currentFrameHint: currentFrameHint,
            writeResult: AXFrameWriteResult(
                observedFrame: failureReason == nil ? targetFrame : nil,
                writeOrder: .sizeThenPosition,
                sizeError: .success,
                positionError: .success,
                failureReason: failureReason,
                components: components
            )
        )
    }

    private static func layoutMonitorSnapshot(_ monitor: Monitor) -> LayoutMonitorSnapshot {
        LayoutMonitorSnapshot(
            monitorId: monitor.id,
            displayId: monitor.displayId,
            frame: monitor.frame,
            visibleFrame: monitor.visibleFrame,
            workingFrame: monitor.visibleFrame,
            fullscreenLayoutFrame: monitor.visibleFrame,
            scale: 1,
            orientation: monitor.autoOrientation
        )
    }

    @MainActor
    private static func waitForRemovalRefresh(
        _ controller: WMController,
        removedToken: WindowToken
    ) async {
        for _ in 0 ..< 80 {
            if let refreshTask = controller.layoutRefreshController.layoutState.activeRefreshTask {
                await refreshTask.value
                continue
            }
            if controller.workspaceManager.entry(for: removedToken) == nil,
               controller.layoutRefreshController.layoutState.pendingRefresh == nil
            {
                await Task.yield()
                if controller.layoutRefreshController.layoutState.activeRefreshTask == nil,
                   controller.layoutRefreshController.layoutState.pendingRefresh == nil
                {
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private static func horizontallyAdjacentUnequalMonitors() -> (left: Monitor, right: Monitor) {
        let left = Monitor(
            id: .init(displayId: 10_001), displayId: 10_001,
            frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            hasNotch: false, name: "Left"
        )
        let right = Monitor(
            id: .init(displayId: 10_002), displayId: 10_002,
            frame: CGRect(x: 1200, y: 0, width: 1800, height: 800),
            visibleFrame: CGRect(x: 1200, y: 0, width: 1800, height: 800),
            hasNotch: false, name: "Right"
        )
        return (left, right)
    }

    @MainActor
    func testPostLayoutGateDroppedBySourceSeqButTargetOnlyGateSurvives() throws {
        let controller = Self.controller()
        let sourceWs = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let targetWs = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "2", createIfMissing: true))
        let workspaceManager = controller.workspaceManager
        let plannedSeq = workspaceManager.worldSeq
        let domains: InvalidationDomain = [.workspace, .layout, .focus, .fullscreen]

        let bothGate = RefreshPostLayoutAction(
            workspaceSeqs: [sourceWs: plannedSeq, targetWs: plannedSeq],
            domains: domains,
            action: {}
        )
        let targetOnlyGate = RefreshPostLayoutAction(
            workspaceSeqs: [targetWs: plannedSeq],
            domains: domains,
            action: {}
        )
        XCTAssertTrue(bothGate.isCurrent(using: workspaceManager))
        XCTAssertTrue(targetOnlyGate.isCurrent(using: workspaceManager))

        workspaceManager.invalidateLayout(for: [sourceWs])

        XCTAssertFalse(bothGate.isCurrent(using: workspaceManager))
        XCTAssertTrue(targetOnlyGate.isCurrent(using: workspaceManager))
    }

    @MainActor
    private static func verticallyStackedMonitors() -> (lower: Monitor, upper: Monitor) {
        let lower = Monitor(
            id: .init(displayId: 10_001), displayId: 10_001,
            frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            hasNotch: false, name: "Lower"
        )
        let upper = Monitor(
            id: .init(displayId: 10_002), displayId: 10_002,
            frame: CGRect(x: 0, y: 800, width: 1200, height: 800),
            visibleFrame: CGRect(x: 0, y: 800, width: 1200, height: 800),
            hasNotch: false, name: "Upper"
        )
        return (lower, upper)
    }

    @MainActor
    private static func rekeyStructuralManagedReplacementIfNeeded(
        _ handler: AXEventHandler,
        token: WindowToken,
        windowId: UInt32,
        axRef: AXWindowRef,
        bundleId: String?,
        mode: TrackedWindowMode,
        facts: WindowRuleFacts
    ) -> Bool {
        guard let match = handler.structuralReplacementMatch(
            token: token,
            candidate: .init(bundleId: bundleId, mode: mode, facts: facts)
        ) else {
            return false
        }
        return handler.rekeyStructuralManagedReplacement(
            match: match,
            identity: .init(token: token, axRef: axRef),
            windowId: windowId,
            candidate: .init(bundleId: bundleId, mode: mode, facts: facts)
        )
    }

    private static func managedReplacementMetadata(
        workspaceId: WorkspaceDescriptor.ID,
        pid: pid_t,
        frame: CGRect
    ) -> ManagedReplacementMetadata {
        ManagedReplacementMetadata(
            bundleId: nativeTabBundleId(pid: pid),
            workspaceId: workspaceId,
            mode: .tiling,
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            title: "native-tab",
            windowLevel: 0,
            parentWindowId: nil,
            frame: frame
        )
    }

    private static func nativeTabBundleId(pid: pid_t) -> String {
        "com.omniwm.tests.native-tabs.\(pid)"
    }

    private static func nativeTabFacts(
        pid: pid_t,
        windowId: Int,
        frame: CGRect
    ) -> WindowRuleFacts {
        WindowRuleFacts(
            appName: "Native Tabs",
            ax: AXWindowFacts(
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                title: "native-tab",
                hasCloseButton: true,
                hasFullscreenButton: true,
                fullscreenButtonEnabled: true,
                hasZoomButton: true,
                hasMinimizeButton: true,
                appPolicy: .regular,
                bundleId: nativeTabBundleId(pid: pid),
                attributeFetchSucceeded: true
            ),
            sizeConstraints: nil,
            windowServer: visibleWindowInfo(pid: pid, windowId: windowId, frame: frame)
        )
    }

    private static func visibleWindowInfo(
        pid: pid_t,
        windowId: Int,
        frame: CGRect
    ) -> WindowServerInfo {
        WindowServerInfo(
            id: UInt32(windowId),
            pid: pid,
            level: 0,
            frame: frame,
            tags: 1,
            attributes: 2,
            parentId: 0,
            title: nil
        )
    }

    private static func assertFrame(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    @MainActor
    private static func workspaceManager(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> WorkspaceManager {
        WorkspaceManager(settings: settingsStore(file: file, line: line))
    }

    @MainActor
    private static func controller(
        windowFocusOperations: WindowFocusOperations = WindowFocusOperations(
            activateApp: { _ in },
            focusSpecificWindow: { _, _, _ in },
            raiseWindow: { _ in }
        ),
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> WMController {
        WMController(
            settings: settingsStore(file: file, line: line),
            windowFocusOperations: windowFocusOperations
        )
    }

    @MainActor
    private static func configureOrientation(
        _ orientation: Monitor.Orientation,
        for workspaceId: WorkspaceDescriptor.ID,
        controller: WMController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let monitor = try XCTUnwrap(
            controller.workspaceManager.monitor(for: workspaceId),
            file: file,
            line: line
        )
        controller.settings.monitors.updateOrientationSettings(
            MonitorOrientationSettings(
                monitorName: monitor.name,
                monitorDisplayId: monitor.displayId,
                orientation: orientation
            ),
            for: monitor
        )
    }

    @MainActor
    private static func inactiveWorkspaceFocusFixture(
        pid: pid_t,
        windowId: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (
        controller: WMController,
        token: WindowToken,
        facts: ActivationFacts,
        monitorId: Monitor.ID,
        activeWorkspaceId: WorkspaceDescriptor.ID,
        surfaceWorkspaceId: WorkspaceDescriptor.ID
    ) {
        let controller = Self.controller(file: file, line: line)
        let surfaceWorkspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "2", createIfMissing: true),
            file: file,
            line: line
        )
        let activeWorkspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true),
            file: file,
            line: line
        )
        let axRef = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId)
        let token = controller.workspaceManager.addWindow(
            axRef,
            pid: pid,
            windowId: windowId,
            to: surfaceWorkspaceId
        )
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.hasStartedServices = true

        let monitorId = try XCTUnwrap(
            controller.workspaceManager.monitor(for: surfaceWorkspaceId)?.id,
            file: file,
            line: line
        )
        XCTAssertEqual(
            controller.workspaceManager.activeWorkspace(on: monitorId)?.id,
            activeWorkspaceId,
            file: file,
            line: line
        )

        let facts = ActivationFacts(
            pid: pid,
            source: .focusedWindowChanged,
            origin: .external,
            observationGeneration: 0,
            requestedAtSeq: 0,
            focusedWindow: FocusedWindowFact(
                axRef: axRef,
                isFullscreen: false,
                isSystemModalSurface: false
            )
        )
        return (controller, token, facts, monitorId, activeWorkspaceId, surfaceWorkspaceId)
    }

    @MainActor
    private static func settingsStore(
        file _: StaticString = #filePath,
        line _: UInt = #line
    ) -> SettingsStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMTests-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        return settings
    }
}

private extension Array where Element == AnimationDirective {
    func containsActivateWindow(_ token: WindowToken) -> Bool {
        contains { directive in
            if case .activateWindow(let directiveToken) = directive {
                return directiveToken == token
            }
            return false
        }
    }
}
