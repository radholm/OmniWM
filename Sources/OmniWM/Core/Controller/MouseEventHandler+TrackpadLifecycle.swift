// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    func commitGestureMode(
        metrics: GestureFrameMetrics,
        lockedContext: MouseInputState.LockedGestureContext,
        timestamp: TimeInterval
    ) -> Bool {
        guard let controller, var config = trackpadGestureConfig else {
            abortActiveGestureIfNeeded()
            return false
        }
        if let axis = lockedContext.workspaceAxis {
            config.workspaceSwipeAxis = axis
        }
        config.overviewAction = controller.settings.overview.enabled ? lockedContext.overviewAction : nil
        guard let mode = TrackpadGestureIntent.resolveMode(
            config,
            fingerCount: lockedContext.fingerCount,
            cumulativeTranslation: CGVector(dx: metrics.cumulativeX, dy: metrics.cumulativeY),
            windowContextAvailable: lockedContext.windowGestureTarget != nil
        ) else {
            state.suppressGestureStartUntilAllTouchesLift = true
            resetGestureState()
            return false
        }
        if case .overview = mode, overviewGestureInteractive,
           !controller.windowActionHandler.beginOverviewGesture()
        {
            state.suppressGestureStartUntilAllTouchesLift = true
            resetGestureState()
            return false
        }
        if mode.isWindowInteraction, !beginGestureWindowInteraction(mode, lockedContext: lockedContext) {
            state.suppressGestureStartUntilAllTouchesLift = true
            resetGestureState()
            return false
        }
        MouseTrace.record("gesture: committed \(mode) with \(lockedContext.fingerCount) fingers")
        metrics.traceRecognition(mode, timestamp: timestamp)
        state.activeGestureMode = mode
        state.gesturePhase = .committed
        if case let .workspaceSwitch(axis) = mode {
            beginWorkspaceSwipePresentation(axis: axis, metrics: metrics, timestamp: timestamp)
        } else {
            controller.layoutRefreshController.workspaceSwipe.cancel(reason: "other-gesture")
        }
        return true
    }

    func dispatchCommittedGestureFrame(
        metrics: GestureFrameMetrics,
        lockedContext: MouseInputState.LockedGestureContext,
        monitor: Monitor,
        timestamp: TimeInterval
    ) {
        guard controller != nil else { return }
        switch state.activeGestureMode {
        case let .overview(action):
            handleOverviewSwipe(action, metrics: metrics, timestamp: timestamp)
        case let .workspaceSwitch(axis):
            dispatchWorkspaceSwipeFrame(
                axis: axis,
                metrics: metrics,
                monitorId: lockedContext.monitorId,
                timestamp: timestamp
            )
        case .windowMove:
            guard state.gestureOwnsWindowInteraction, state.isMoving else {
                abortActiveGestureIfNeeded()
                return
            }
            updateActiveMove(at: gestureWindowLocation(for: lockedContext))
        case .windowResize:
            guard state.gestureOwnsWindowInteraction, state.isResizing else {
                abortActiveGestureIfNeeded()
                return
            }
            updateManagedResize(at: gestureWindowLocation(for: lockedContext))
        case nil:
            abortActiveGestureIfNeeded()
        }
    }

    private func dispatchWorkspaceSwipeFrame(
        axis: WorkspaceSwipeAxis,
        metrics: GestureFrameMetrics,
        monitorId: Monitor.ID,
        timestamp: TimeInterval
    ) {
        guard let controller else { return }
        let cumulative = (axis == .horizontal ? metrics.cumulativeX : metrics.cumulativeY) * workspaceSwipeSensitivity
        if controller.layoutRefreshController.workspaceSwipe.update(
            cumulative: cumulative,
            timestamp: timestamp
        ) { return }
        handleWorkspaceSwipeFrame(
            axis: axis,
            cumulative: cumulative,
            monitorId: monitorId
        )
    }

    private func handleOverviewSwipe(
        _ action: OverviewGestureAction,
        metrics: GestureFrameMetrics,
        timestamp: TimeInterval
    ) {
        guard let controller, controller.settings.overview.enabled,
              controller.settings.gestures.overviewGestureEnabled
        else {
            abortActiveGestureIfNeeded()
            return
        }
        if overviewGestureInteractive {
            controller.windowActionHandler.updateOverviewGesture(
                cumulativeUnits: Double(metrics.cumulativeY),
                timestamp: timestamp,
                recognitionMovement: action == .resume ? nil : SwipeEvent(
                    delta: Double(metrics.rawDeltaY), timestamp: metrics.previousTimestamp
                )
            )
            return
        }
        let translation = CGPoint(x: metrics.cumulativeX, y: metrics.cumulativeY)
        guard TrackpadGestureIntent.overviewTriggered(action: action, translation: translation) else { return }
        retainConsumedTrackpadSession()
        state.suppressGestureStartUntilAllTouchesLift = true
        state.consumeTrackpadScrollUntilAllTouchesLift = true
        state.suppressTrackpadMomentumScroll = true
        resetGestureState()
        switch action {
        case .open:
            controller.windowActionHandler.openOverview()
        case .close:
            controller.windowActionHandler.dismissOverview()
        case .resume:
            break
        }
    }

    private func handleWorkspaceSwipeFrame(
        axis: WorkspaceSwipeAxis,
        cumulative: CGFloat,
        monitorId: Monitor.ID
    ) {
        guard !state.workspaceSwipeFired,
              abs(cumulative) >= TrackpadGestureIntent.workspaceSwipeTriggerUnits,
              let isNext = TrackpadGestureIntent.isNextWorkspace(
                  axis: axis,
                  displacement: cumulative,
                  naturalDirection: controller?.settings.gestures.invertDirection ?? true
              )
        else { return }
        state.workspaceSwipeFired = true
        controller?.workspaceNavigationHandler.switchWorkspaceRelative(isNext: isNext, monitorId: monitorId)
    }

    private func beginWorkspaceSwipePresentation(
        axis: WorkspaceSwipeAxis,
        metrics: GestureFrameMetrics,
        timestamp: TimeInterval
    ) {
        guard let controller else { return }
        let sensitivity = workspaceSwipeSensitivity
        controller.layoutRefreshController.workspaceSwipe.begin(
            axis: axis,
            cumulative: (axis == .horizontal ? metrics.cumulativeX : metrics.cumulativeY) * sensitivity,
            timestamp: timestamp,
            recognitionMovement: SwipeEvent(
                delta: Double((axis == .horizontal ? metrics.rawDeltaX : metrics.rawDeltaY) * sensitivity),
                timestamp: metrics.previousTimestamp
            )
        )
        if controller.layoutRefreshController.workspaceSwipe.hasPresentation { state.workspaceSwipeFired = true }
    }

    private var workspaceSwipeSensitivity: CGFloat {
        CGFloat(controller?.settings.gestures.workspaceSwipeSensitivity ?? 1.0)
    }

    func finishCommittedGestureOnRelease(timestamp: TimeInterval, allowFlick: Bool) {
        guard let lockedContext = state.lockedGestureContext else {
            assertionFailure("Committed gesture missing locked context")
            return
        }
        switch state.activeGestureMode {
        case .overview:
            controller?.windowActionHandler.endOverviewGesture(timestamp: allowFlick ? timestamp : nil)
            state.suppressTrackpadMomentumScroll = true
        case let .workspaceSwitch(axis):
            finalizeWorkspaceSwipe(
                monitorId: lockedContext.monitorId,
                axis: axis,
                allowFlick: allowFlick,
                timestamp: timestamp
            )
        case .windowMove,
             .windowResize:
            if allowFlick {
                commitGestureWindowInteraction(lockedContext: lockedContext)
            } else {
                cancelGestureWindowInteraction()
            }
        case nil:
            break
        }
    }

    private func finalizeWorkspaceSwipe(
        monitorId: Monitor.ID,
        axis: WorkspaceSwipeAxis,
        allowFlick: Bool,
        timestamp: TimeInterval
    ) {
        defer { state.suppressTrackpadMomentumScroll = true }
        if controller?.layoutRefreshController.workspaceSwipe
            .release(timestamp: timestamp, allowFlick: allowFlick) == true
        {
            return
        }
        defer {
            TrackpadScrollTrace.record(.workspaceFallback(
                cumulative: Double((axis == .horizontal
                        ? state.gestureLastAverageX - state.gestureStartX
                        : state.gestureLastAverageY - state.gestureStartY)
                    * GestureEventSnapshot.normalizedPositionToGestureUnits),
                velocity: state.workspaceSwipeTracker.velocity(), allowFlick: allowFlick,
                fired: state.workspaceSwipeFired
            ))
        }
        guard allowFlick, !state.workspaceSwipeFired else { return }
        state.workspaceSwipeTracker.push(delta: 0, timestamp: timestamp)
        let cumulative = (axis == .horizontal
            ? state.gestureLastAverageX - state.gestureStartX
            : state.gestureLastAverageY - state.gestureStartY)
            * GestureEventSnapshot.normalizedPositionToGestureUnits
            * workspaceSwipeSensitivity
        guard let displacement = TrackpadGestureIntent.releaseFlickDisplacement(
            cumulativeAxisUnits: cumulative,
            velocity: state.workspaceSwipeTracker.velocity() * Double(workspaceSwipeSensitivity)
        ),
            let isNext = TrackpadGestureIntent.isNextWorkspace(
                axis: axis,
                displacement: displacement,
                naturalDirection: controller?.settings.gestures.invertDirection ?? true
            )
        else { return }
        state.workspaceSwipeFired = true
        controller?.workspaceNavigationHandler.switchWorkspaceRelative(isNext: isNext, monitorId: monitorId)
    }

    func finalizeCommittedGestureAfterTouchRelease(timestamp: TimeInterval) {
        retainConsumedTrackpadSession()
        finishCommittedGestureOnRelease(timestamp: timestamp, allowFlick: true)
        state.suppressGestureStartUntilAllTouchesLift = true
        state.consumeTrackpadScrollUntilAllTouchesLift = true
        resetGestureState()
        state.suppressTrackpadMomentumScroll = true
    }

    func abortActiveGestureIfNeeded() {
        if state.gesturePhase == .committed {
            retainConsumedTrackpadSession()
            if case .overview = state.activeGestureMode {
                state.suppressTrackpadMomentumScroll = true
            } else if case .workspaceSwitch = state.activeGestureMode {
                controller?.layoutRefreshController.workspaceSwipe.cancel(reason: "gesture-aborted")
                state.suppressTrackpadMomentumScroll = true
            } else if state.activeGestureMode?.isWindowInteraction == true {
                cancelGestureWindowInteraction()
            } else {
                assertionFailure("Committed gesture missing locked context")
            }
            state.suppressGestureStartUntilAllTouchesLift = true
            state.consumeTrackpadScrollUntilAllTouchesLift = true
        }
        resetGestureState()
    }

    func resetGestureState() {
        controller?.layoutRefreshController.workspaceSwipe.stopPreparing(warm: true)
        cancelGestureWindowInteraction()
        if state.lockedGestureContext?.overviewAction != nil {
            controller?.windowActionHandler.endOverviewGesture(timestamp: nil)
        }
        state.gesturePhase = .idle
        state.gestureStartX = 0.0
        state.gestureStartY = 0.0
        state.gestureLastAverageX = 0.0
        state.gestureLastAverageY = 0.0
        state.gestureLastTimestamp = 0
        state.lockedGestureContext = nil
        state.activeGestureMode = nil
        state.gestureFingerCountMismatchSince = nil
        state.workspaceSwipeFired = false
    }
}
