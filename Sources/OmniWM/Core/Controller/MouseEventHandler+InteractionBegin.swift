// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    func beginDwindleMove(
        token: WindowToken,
        engine: DwindleLayoutEngine,
        wsId: WorkspaceDescriptor.ID,
        at location: CGPoint,
        source: MouseInputState.InteractionSource
    ) -> Bool {
        guard let controller else { return false }
        let now = controller.animationClock.now()
        guard let frame = engine.presentedFrame(for: token, in: wsId, at: now),
              engine.interactiveMoveBegin(token: token, startLocation: location, in: wsId)
        else { return false }

        state.isMoving = true
        state.moveLayout = .dwindle
        state.activeInteractionSource = source
        state.capturedInteractionButton = source.mouseButton
        NSCursor.closedHand.set()
        if state.dragGhostController == nil {
            state.dragGhostController = DragGhostController()
        }
        state.dragGhostController?.beginDrag(windowId: token.windowId, originalFrame: frame, cursorLocation: location)
        return true
    }

    func beginDwindleResize(
        token: WindowToken,
        engine: DwindleLayoutEngine,
        wsId: WorkspaceDescriptor.ID,
        at location: CGPoint,
        edgePolicy: DwindleResizeEdgePolicy = .exact,
        edges explicitEdges: ResizeEdge? = nil,
        source: MouseInputState.InteractionSource
    ) -> Bool {
        guard let controller,
              let monitor = controller.workspaceManager.monitor(for: wsId),
              let node = engine.findNode(for: token, in: wsId),
              let frame = node.presentedFrame(at: controller.animationClock.now())
        else { return false }

        controller.dwindleLayoutHandler.refreshEngineConstraints(workspaceId: wsId, monitor: monitor)
        let innerGap = controller.resolvedDwindleSettings(for: monitor).innerGap
        guard engine.interactiveResizeBegin(
            token: token,
            edges: explicitEdges ?? resizeEdges(for: location, in: frame),
            startLocation: location,
            in: wsId,
            innerGap: innerGap,
            edgePolicy: edgePolicy
        ),
            let edges = engine.interactiveResize?.edges
        else {
            return false
        }

        controller.layoutRefreshController.stopDwindleAnimation(for: monitor.displayId)
        engine.cancelAnimations(in: wsId)
        state.isResizing = true
        state.activeInteractionSource = source
        state.capturedInteractionButton = source.mouseButton
        state.currentHoveredEdges = edges
        state.resizeLayout = .dwindle
        controller.dwindleLayoutHandler.beginInteractiveSnapshotResize(workspaceId: wsId, monitor: monitor)
        edges.cursor.set()
        return true
    }
}
