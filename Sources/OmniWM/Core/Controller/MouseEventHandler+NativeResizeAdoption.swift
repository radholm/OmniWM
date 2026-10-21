// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    func adoptNativeResizeIfEligible(
        _ drag: inout MouseInputState.NativeTitleBarDrag,
        entry: WindowState,
        observedFrame: CGRect?
    ) -> Bool {
        guard let controller else { return false }
        let wasResizing = drag.dwindleResizeWorkspaceId != nil
        controller.axManager.forceApplyNextFrame(for: entry.windowId)
        updateNativeDwindleResize(&drag, entry: entry, observedFrame: observedFrame, renderOnChange: false)
        guard wasResizing || drag.dwindleResizeWorkspaceId != nil else { return false }
        if let workspaceId = drag.dwindleResizeWorkspaceId {
            controller.layoutRefreshController.renderDwindleInteractiveResize(for: workspaceId)
        }
        finishNativeDwindleResize(&drag)
        requestNativeTitleBarDragCorrection(for: entry)
        drag.adoptionStartFrame = nil
        drag.phase = .awaitingCorrection
        drag.receivedFrameChange = false
        return true
    }

    private func nativeResizeStartFrame(
        _ drag: MouseInputState.NativeTitleBarDrag,
        entry: WindowState
    ) -> CGRect? {
        guard let controller,
              controller.settings.gestures.adoptNativeResize,
              let start = drag.adoptionStartFrame,
              entry.layoutReason == .standard,
              !controller.axManager.isAwaitingFrameWrite(entry.windowId),
              controller.axManager.lastAppliedFrame(for: entry.windowId)?.approximatelyEqual(
                  to: start,
                  tolerance: FrameTolerance.frameWrite
              ) == true
        else {
            return nil
        }
        return start
    }

    static func nativeResizeEdges(from start: CGRect, to observed: CGRect) -> ResizeEdge {
        func moved(_ before: CGFloat, _ after: CGFloat) -> Bool {
            abs(after - before) > FrameTolerance.screenMatch
        }
        let left = moved(start.minX, observed.minX)
        let right = moved(start.maxX, observed.maxX)
        let bottom = moved(start.minY, observed.minY)
        let top = moved(start.maxY, observed.maxY)
        guard !(left && right), !(bottom && top) else { return [] }
        var edges: ResizeEdge = []
        if left { edges.insert(.left) }
        if right { edges.insert(.right) }
        if bottom { edges.insert(.bottom) }
        if top { edges.insert(.top) }
        return edges
    }

    private static func nativeResizeLocation(
        _ edges: ResizeEdge,
        from start: CGRect,
        to observed: CGRect
    ) -> CGPoint {
        let dx: CGFloat = if edges.contains(.left) {
            observed.minX - start.minX
        } else if edges.contains(.right) {
            observed.maxX - start.maxX
        } else {
            0
        }
        let dy: CGFloat = if edges.contains(.bottom) {
            observed.minY - start.minY
        } else if edges.contains(.top) {
            observed.maxY - start.maxY
        } else {
            0
        }
        return CGPoint(x: start.minX + dx, y: start.minY + dy)
    }

    func updateNativeDwindleResize(
        _ drag: inout MouseInputState.NativeTitleBarDrag,
        entry: WindowState,
        observedFrame: CGRect?,
        renderOnChange: Bool = true
    ) {
        let workspaceId = entry.workspaceId
        guard let controller,
              let engine = controller.dwindleEngine,
              controller.workspaceManager.activeLayoutKind(for: workspaceId) == .dwindle,
              drag.dwindleResizeWorkspaceId == nil || drag.dwindleResizeWorkspaceId == workspaceId,
              let monitor = controller.workspaceManager.monitor(for: workspaceId),
              let start = nativeResizeStartFrame(drag, entry: entry)
        else {
            finishNativeDwindleResize(&drag)
            return
        }
        guard let observedFrame else { return }
        let edges = Self.nativeResizeEdges(from: start, to: observedFrame)
        guard !edges.isEmpty || observedFrame.approximatelyEqual(to: start, tolerance: FrameTolerance.screenMatch)
        else { return }
        if drag.dwindleResizeWorkspaceId == nil {
            guard !edges.isEmpty else { return }
            guard engine.interactiveResizeBegin(
                token: entry.token,
                edges: edges,
                startLocation: start.origin,
                in: workspaceId,
                innerGap: controller.resolvedDwindleSettings(for: monitor).innerGap,
                edgePolicy: .exact
            ) else { return }
            controller.dwindleLayoutHandler.refreshEngineConstraints(workspaceId: workspaceId, monitor: monitor)
            drag.dwindleResizeWorkspaceId = workspaceId
            controller.layoutRefreshController.stopDwindleAnimation(for: monitor.displayId)
            engine.cancelAnimations(in: workspaceId)
        }
        guard let resize = engine.interactiveResize,
              resize.token == entry.token, resize.workspaceId == workspaceId
        else {
            finishNativeDwindleResize(&drag)
            return
        }
        let combinedEdges = resize.edges.union(edges)
        guard !combinedEdges.isSuperset(of: [.left, .right]),
              !combinedEdges.isSuperset(of: [.top, .bottom])
        else { return }
        state.nativeTitleBarDrag = drag
        if engine.interactiveResizeUpdate(
            currentLocation: Self.nativeResizeLocation(combinedEdges, from: start, to: observedFrame),
            edges: edges
        ), renderOnChange {
            controller.layoutRefreshController.renderDwindleInteractiveResize(for: workspaceId)
        }
    }

    func finishNativeDwindleResize(_ drag: inout MouseInputState.NativeTitleBarDrag) {
        guard let workspaceId = drag.dwindleResizeWorkspaceId else { return }
        drag.dwindleResizeWorkspaceId = nil
        drag.adoptionStartFrame = nil
        guard let resize = controller?.dwindleEngine?.interactiveResize,
              resize.token == drag.token, resize.workspaceId == workspaceId
        else { return }
        finishDwindleResize()
    }
}
