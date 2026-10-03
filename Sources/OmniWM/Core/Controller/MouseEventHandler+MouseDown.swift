// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    func handleMouseDownFromTap(
        at location: CGPoint,
        modifiers: CGEventFlags,
        button: MouseButton,
        windowIdUnderPointer: Int?
    ) -> Bool {
        guard let controller else { return false }
        guard canHandleManagedMouseInteraction(controller: controller) else { return false }

        if shouldBlockOwnWindowInput(at: location) {
            return false
        }
        guard !state.isMoving, !state.isResizing else { return false }

        guard let wsId = workspaceIdForPointer(at: location) ?? controller.activeWorkspace()?.id else {
            return false
        }

        if button == .left,
           modifiers.isDisjoint(with: Self.relevantModifierFlags),
           handlePlainLeftMouseDown(at: location, workspaceId: wsId, windowIdUnderPointer: windowIdUnderPointer)
        {
            return true
        }

        return handleDwindleMouseDown(at: location, modifiers: modifiers, button: button, wsId: wsId)
    }

    /// Returns true when the press started an edge-drag resize and must be consumed.
    private func handlePlainLeftMouseDown(
        at location: CGPoint, workspaceId wsId: WorkspaceDescriptor.ID, windowIdUnderPointer: Int?
    ) -> Bool {
        if beginEdgeDragResizeIfNeeded(at: location, workspaceId: wsId) {
            return true
        }
        recordPointerFocusIntent(at: location, workspaceId: wsId, windowIdUnderPointer: windowIdUnderPointer)
        return false
    }

    private func recordPointerFocusIntent(
        at location: CGPoint, workspaceId wsId: WorkspaceDescriptor.ID, windowIdUnderPointer: Int?
    ) {
        guard let controller else { return }
        state.awaitsNativeTitleBarDragTarget = windowIdUnderPointer == nil
        state.nativeTitleBarDragFallbackReleased = false
        let exactToken = nativeTitleBarDragCandidate(windowIdUnderPointer: windowIdUnderPointer)
        let focusIntentToken = exactToken ?? (windowIdUnderPointer == nil
            ? geometricFocusIntentCandidate(at: location, workspaceId: wsId)
            : nil)
        if let token = focusIntentToken {
            controller.axEventHandler.noteMouseFocusIntent(token: token)
        } else {
            controller.axEventHandler.noteUnmanagedPointerClick()
        }
        state.nativeTitleBarDragFallbackToken = exactToken == nil ? focusIntentToken : nil
        if let exactToken {
            state.awaitsNativeTitleBarDragTarget = false
            let token = exactToken
            state.nativeTitleBarDrag = .init(token: token)
        }
    }

    private func handleDwindleMouseDown(
        at location: CGPoint,
        modifiers: CGEventFlags,
        button: MouseButton,
        wsId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard let controller, let engine = controller.dwindleEngine else { return false }
        if button == .left {
            guard Self.mouseMoveMode(
                modifiers: modifiers,
                required: controller.settings.gestures.mouseMoveModifierKey.cgEventFlags
            ) == .swap,
                let token = engine.hitTestFocusableWindow(
                    point: location,
                    in: wsId,
                    at: controller.animationClock.now()
                )
            else { return false }
            _ = beginDwindleMove(token: token, engine: engine, wsId: wsId, at: location, source: .mouse(button))
            return false
        }
        guard button == .right,
              Self.modifierFlagsMatch(
                  modifiers,
                  required: controller.settings.gestures.mouseResizeModifierKey.cgEventFlag
              )
        else { return false }

        guard let monitor = controller.workspaceManager.monitor(for: wsId) else { return false }
        let token = engine.hitTestFocusableWindow(point: location, in: wsId, at: controller.animationClock.now())
            ?? focusedBorderResizeToken(
                at: location,
                in: wsId,
                scale: controller.backingScaleFactor(for: monitor),
                appliedBorder: controller.surfaceReconciler.appliedScene.border
            )
        guard let token else { return false }
        return beginDwindleResize(token: token, engine: engine, wsId: wsId, at: location, source: .mouse(button))
    }

    func focusedBorderResizeToken(
        at location: CGPoint,
        in workspaceId: WorkspaceDescriptor.ID,
        scale: CGFloat,
        appliedBorder: DesiredBorderSurface?
    ) -> WindowToken? {
        guard let controller,
              let appliedBorder,
              appliedBorder.token == controller.workspaceManager.borderFocusToken,
              let entry = controller.workspaceManager.entry(for: appliedBorder.token),
              entry.workspaceId == workspaceId,
              entry.mode == .tiling
        else {
            return nil
        }
        let geometry = appliedBorder.config.resolvedGeometry(for: appliedBorder.frame, scale: scale)
        guard geometry.width > 0,
              geometry.targetFrame.insetBy(dx: -geometry.width, dy: -geometry.width).contains(location),
              !geometry.targetFrame.contains(location)
        else {
            return nil
        }
        return appliedBorder.token
    }

    func resizeEdges(for location: CGPoint, in frame: CGRect) -> ResizeEdge {
        var edges: ResizeEdge = location.x < frame.midX ? [.left] : [.right]
        edges.insert(location.y < frame.midY ? .bottom : .top)
        return edges
    }

    func shouldAcceptInteractionButton(_ button: MouseButton) -> Bool {
        state.activeInteractionSource == nil || state.activeInteractionSource == .mouse(button)
    }

    func isCapturedInteraction(_ button: MouseButton) -> Bool {
        state.capturedInteractionButton == button
    }
}
