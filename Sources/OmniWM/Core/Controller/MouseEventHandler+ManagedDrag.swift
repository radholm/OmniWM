// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    private func handleDwindleMoveDrag(at location: CGPoint) {
        guard let controller, let engine = controller.dwindleEngine,
              let move = engine.interactiveMove,
              let monitor = controller.workspaceManager.monitor(for: move.workspaceId)
        else {
            cancelActiveMouseInteraction()
            return
        }
        guard !updateCrossDisplayHover(at: location) else { return }
        let now = controller.animationClock.now()
        state.dragGhostController?.updatePosition(cursorLocation: location)
        _ = engine.interactiveMoveUpdate(
            currentLocation: location, at: now,
            workspaceFrame: controller.insetWorkingFrame(for: monitor)
        )
        guard engine.interactiveMove != nil else {
            cancelActiveMouseInteraction()
            return
        }
        if let frame = engine.interactiveMoveTargetFrame(at: now) {
            state.dragGhostController?.showSwapTarget(frame: frame)
        } else {
            state.dragGhostController?.hideSwapTarget()
        }
    }

    func finishDwindleMove(at location: CGPoint) {
        guard let controller, let engine = controller.dwindleEngine,
              let wsId = engine.interactiveMove?.workspaceId
        else { return }
        guard let monitor = controller.workspaceManager.monitor(for: wsId) else {
            engine.interactiveMoveCancel()
            return
        }
        _ = engine.interactiveMoveUpdate(
            currentLocation: location, at: controller.animationClock.now(),
            workspaceFrame: controller.insetWorkingFrame(for: monitor)
        )
        guard let move = engine.interactiveMove, move.target != nil else {
            engine.interactiveMoveCancel()
            return
        }
        let changed = controller.workspaceManager.withEngineMutationScope(
            in: wsId,
            label: move.isInsertion ? "dwindle_mouse_insert" : "dwindle_mouse_swap",
            source: .mouse
        ) {
            engine.interactiveMoveEnd() != nil
        }
        guard changed else { return }
        controller.workspaceManager.recordLayoutOperation(
            move.isInsertion ? .interactiveMoveEnded(token: move.token) : .windowsSwapped,
            in: wsId,
            source: .mouse
        )
        if controller.hasStartedServices {
            controller.layoutRefreshController.requestImmediateRelayout(reason: .interactiveGesture)
        }
    }

    func handleMouseDraggedFromTap(
        at location: CGPoint,
        button: MouseButton,
        requirePressedButtonCheck: Bool = true
    ) {
        guard let controller else { return }
        guard canHandleManagedMouseInteraction(controller: controller) else { return }
        guard !state.gestureOwnsWindowInteraction else { return }
        if requirePressedButtonCheck {
            guard pressedMouseButtonsProvider() & button.pressedMask != 0 else {
                cancelActiveMouseInteraction()
                return
            }
        }

        if state.isMoving {
            guard shouldAcceptInteractionButton(button) else { return }
            updateActiveMove(at: location)
            return
        }

        guard state.isResizing else { return }
        guard shouldAcceptInteractionButton(button) else { return }

        updateManagedResize(at: location)
    }

    func canHandleManagedMouseInteraction(controller: WMController) -> Bool {
        guard controller.isEnabled else {
            cancelActiveMouseInteraction()
            return false
        }
        if controller.isOverviewOpen() {
            cancelActiveMouseInteraction()
            return false
        }

        return true
    }

    func updateActiveMove(at location: CGPoint) {
        handleDwindleMoveDrag(at: location)
    }

    func updateManagedResize(at location: CGPoint) {
        guard let controller else { return }
        guard let engine = controller.dwindleEngine,
              let wsId = engine.interactiveResize?.workspaceId
        else {
            cancelActiveMouseInteraction()
            return
        }
        if engine.interactiveResizeUpdate(currentLocation: location) {
            controller.layoutRefreshController.renderDwindleInteractiveResize(for: wsId)
        }
    }
}
