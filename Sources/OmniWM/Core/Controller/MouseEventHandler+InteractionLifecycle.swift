// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    var isTrackpadSwipeSessionActive: Bool {
        state.gesturePhase != .idle
    }

    var isInteractiveGestureActive: Bool {
        state.isMoving || state.isResizing
    }

    func handleInputSuppressionBegan() {
        state.latestFocusFollowsMouseSample = nil
        clearNativeTitleBarDrag()
        cancelActiveMouseInteraction()
        dropPendingTapEvents()
        abortActiveGestureIfNeeded()
        clearGestureLatches()
        clearConsumedTrackpadSessions()
    }

    func handleAppVisibilityChanged() {
        state.latestFocusFollowsMouseSample = nil
        clearNativeTitleBarDrag()
        cancelActiveMouseInteraction()
        dropPendingTapEvents()
        abortActiveGestureIfNeeded()
        clearGestureLatches()
    }

    func cancelActiveMouseInteraction() {
        guard let controller else { return }
        let wasActive = state.isMoving || state.isResizing

        if state.isMoving {
            controller.dwindleEngine?.interactiveMoveCancel()
            clearMoveInteractionState()
        }

        if state.isResizing {
            finishActiveResize()
            clearResizeInteractionState()
        }

        resetHoveredEdgesIfNeeded()
        if wasActive {
            NSCursor.arrow.set()
        }
    }

    func recoverAfterTapDisable() {
        cancelActiveMouseInteraction()
        let pressedButtons = pressedMouseButtonsProvider()
        if pressedButtons & MouseButton.left.pressedMask == 0 {
            finishNativeTitleBarDragIfNeeded(button: .left)
        }
        if let button = state.capturedInteractionButton, pressedButtons & button.pressedMask == 0 {
            state.capturedInteractionButton = nil
        }
        if let button = state.capturedOverviewButton, pressedButtons & (1 << Int(button)) == 0 {
            state.capturedOverviewButton = nil
        }
    }

    private func finishActiveResize() {
        if state.resizeLayout == .dwindle {
            finishDwindleResize()
        } else {
        }
    }

    private func finishDwindleResize() {
        guard let controller, let engine = controller.dwindleEngine else { return }
        let workspaceId = engine.interactiveResize?.workspaceId
        guard engine.interactiveResizeEnd(), let workspaceId else {
            controller.dwindleLayoutHandler.cancelInteractiveSnapshotResize()
            return
        }
        controller.workspaceManager.recordLayoutOperation(.splitRatioChanged, in: workspaceId, source: .mouse)
        if controller.hasStartedServices {
            controller.layoutRefreshController.requestImmediateRelayout(reason: .interactiveGesture)
        }
        controller.dwindleLayoutHandler.endInteractiveSnapshotResize(workspaceId: workspaceId)
    }

    func resetHoveredEdgesIfNeeded() {
        if !state.currentHoveredEdges.isEmpty {
            NSCursor.arrow.set()
            state.currentHoveredEdges = []
        }
    }

    func handleMouseUpFromTap(at location: CGPoint, button: MouseButton) {
        guard let controller else { return }
        if controller.isOverviewOpen() {
            cancelActiveMouseInteraction()
            return
        }
        if state.isMoving {
            guard shouldAcceptInteractionButton(button) else { return }
            completeActiveMove(at: location)
            return
        }

        guard state.isResizing else { return }
        guard shouldAcceptInteractionButton(button) else { return }
        completeActiveResize()
    }

    func clearMoveInteractionState() {
        state.dragGhostController?.endDrag()
        state.isMoving = false
        state.moveLayout = nil
        state.activeInteractionSource = nil
    }

    func clearResizeInteractionState() {
        state.isResizing = false
        state.activeInteractionSource = nil
        state.resizeLayout = nil
        state.currentHoveredEdges = []
    }

    func completeActiveMove(at location: CGPoint) {
        if state.moveLayout == .dwindle {
            finishDwindleMove()
        } else {
        }
        clearMoveInteractionState()
        NSCursor.arrow.set()
    }

    func completeActiveResize() {
        finishActiveResize()
        clearResizeInteractionState()
        NSCursor.arrow.set()
    }
}
