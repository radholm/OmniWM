// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    private func handleDwindleMoveDrag(at location: CGPoint) {
        guard let controller, let engine = controller.dwindleEngine, let move = engine.interactiveMove else {
            cancelActiveMouseInteraction()
            return
        }
        let now = controller.animationClock.now()
        state.dragGhostController?.updatePosition(cursorLocation: location)
        if let target = engine.interactiveMoveUpdate(currentLocation: location, at: now),
           let frame = engine.presentedFrame(for: target, in: move.workspaceId, at: now)
        {
            state.dragGhostController?.showSwapTarget(frame: frame)
        } else {
            state.dragGhostController?.hideSwapTarget()
        }
    }

    func finishDwindleMove() {
        guard let controller, let engine = controller.dwindleEngine, let move = engine.interactiveMove else { return }
        guard move.targetToken != nil else {
            engine.interactiveMoveCancel()
            return
        }
        let wsId = move.workspaceId
        let swapped = controller.workspaceManager.withEngineMutationScope(
            in: wsId,
            label: "dwindle_mouse_swap",
            source: .mouse
        ) {
            engine.interactiveMoveEnd() != nil
        }
        guard swapped else { return }
        controller.workspaceManager.recordLayoutOperation(.windowsSwapped, in: wsId, source: .mouse)
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
