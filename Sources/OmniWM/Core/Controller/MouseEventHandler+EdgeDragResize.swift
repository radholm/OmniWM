// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

struct EdgeDragResizeCandidate: Equatable {
    let token: WindowToken
    let edges: ResizeEdge
    let distance: CGFloat
}

extension MouseEventHandler {
    nonisolated static let edgeDragInsideBand: CGFloat = 4
    nonisolated static let edgeDragMinimumOutsideBand: CGFloat = 3

    nonisolated static func edgeDragOutsideBand(innerGap: CGFloat) -> CGFloat {
        max(innerGap / 2 + 1, edgeDragMinimumOutsideBand)
    }

    /// Edges of `frame` whose grab band contains `point`: `inside` points into the
    /// window plus `outside` points into the surrounding gap. AppKit coordinates.
    nonisolated static func edgeDragResizeEdges(
        point: CGPoint,
        frame: CGRect,
        inside: CGFloat,
        outside: CGFloat
    ) -> ResizeEdge {
        guard frame.width > inside * 2, frame.height > inside * 2,
              frame.insetBy(dx: -outside, dy: -outside).contains(point)
        else { return [] }
        var edges: ResizeEdge = []
        if point.x <= frame.minX + inside {
            edges.insert(.left)
        } else if point.x >= frame.maxX - inside {
            edges.insert(.right)
        }
        if point.y <= frame.minY + inside {
            edges.insert(.bottom)
        } else if point.y >= frame.maxY - inside {
            edges.insert(.top)
        }
        return edges
    }

    nonisolated static func edgeDragResizeCandidates(
        point: CGPoint,
        frames: [WindowToken: CGRect],
        inside: CGFloat,
        outside: CGFloat
    ) -> [EdgeDragResizeCandidate] {
        frames.compactMap { token, frame -> EdgeDragResizeCandidate? in
            let edges = edgeDragResizeEdges(point: point, frame: frame, inside: inside, outside: outside)
            guard !edges.isEmpty else { return nil }
            return EdgeDragResizeCandidate(token: token, edges: edges, distance: edgeDistance(point, frame, edges))
        }
        .sorted { lhs, rhs in
            lhs.distance == rhs.distance ? lhs.token.windowId < rhs.token.windowId : lhs.distance < rhs.distance
        }
    }

    private nonisolated static func edgeDistance(_ point: CGPoint, _ frame: CGRect, _ edges: ResizeEdge) -> CGFloat {
        var distances: [CGFloat] = []
        if edges.contains(.left) { distances.append(abs(point.x - frame.minX)) }
        if edges.contains(.right) { distances.append(abs(point.x - frame.maxX)) }
        if edges.contains(.bottom) { distances.append(abs(point.y - frame.minY)) }
        if edges.contains(.top) { distances.append(abs(point.y - frame.maxY)) }
        return distances.min() ?? .greatestFiniteMagnitude
    }

    func beginEdgeDragResizeIfNeeded(at location: CGPoint, workspaceId wsId: WorkspaceDescriptor.ID) -> Bool {
        guard let controller,
              controller.settings.gestures.mouseEdgeDragResize,
              let monitor = controller.workspaceManager.monitor(for: wsId)
        else { return false }
        let isDwindle = controller.workspaceManager.descriptor(for: wsId)
            .map { controller.settings.workspaces.layoutType(for: $0.name) } == .dwindle
        let frames: [WindowToken: CGRect]
        let innerGap: CGFloat
        if isDwindle {
            // Stacked fullscreen windows have no tile edges to drag.
            guard let engine = controller.dwindleEngine, engine.fullscreenTokens(in: wsId).isEmpty else { return false }
            frames = engine.presentedFrames(in: wsId, at: controller.animationClock.now())
            innerGap = controller.resolvedDwindleSettings(for: monitor).innerGap
        } else {
            guard let engine = controller.niriEngine else { return false }
            frames = niriTiledFrames(engine: engine, workspaceId: wsId)
            innerGap = controller.niriInteractionGeometry(for: monitor).innerGap
        }
        let tiledFrames = frames.filter { controller.workspaceManager.entry(for: $0.key)?.mode == .tiling }
        let candidates = Self.edgeDragResizeCandidates(
            point: location,
            frames: tiledFrames,
            inside: Self.edgeDragInsideBand,
            outside: Self.edgeDragOutsideBand(innerGap: innerGap)
        )
        guard !candidates.isEmpty,
              edgeDragUnobstructedProvider(location, Set(tiledFrames.keys.map(\.windowId)))
        else { return false }
        for candidate in candidates where beginEdgeDragResize(
            candidate,
            isDwindle: isDwindle,
            wsId: wsId,
            at: location
        ) {
            state.awaitsNativeTitleBarDragTarget = false
            state.nativeTitleBarDragFallbackToken = nil
            state.nativeTitleBarDragFallbackReleased = false
            return true
        }
        return false
    }

    private func beginEdgeDragResize(
        _ candidate: EdgeDragResizeCandidate,
        isDwindle: Bool,
        wsId: WorkspaceDescriptor.ID,
        at location: CGPoint
    ) -> Bool {
        guard let controller else { return false }
        if isDwindle {
            guard let engine = controller.dwindleEngine else { return false }
            return beginDwindleResize(
                token: candidate.token, engine: engine, wsId: wsId, at: location,
                edges: candidate.edges, source: .mouse(.left)
            )
        }
        guard let engine = controller.niriEngine,
              let window = engine.findNode(for: candidate.token, in: wsId)
        else { return false }
        return beginNiriResize(
            window: window, engine: engine, wsId: wsId, at: location,
            edges: candidate.edges, source: .mouse(.left)
        )
    }

    private func niriTiledFrames(
        engine: NiriLayoutEngine,
        workspaceId: WorkspaceDescriptor.ID
    ) -> [WindowToken: CGRect] {
        guard let root = engine.root(for: workspaceId) else { return [:] }
        var frames: [WindowToken: CGRect] = [:]
        for column in root.columns {
            for case let window as NiriWindow in column.children {
                guard engine.isProjectedFocusableWindow(window, in: workspaceId),
                      let frame = window.renderedFrame ?? window.frame
                else { continue }
                frames[window.token] = frame
            }
        }
        return frames
    }

    /// The press must land on a tiled window or on bare desktop, not on a floating
    /// window, menu or panel covering the gap.
    static func edgeDragPointIsUnobstructed(_ location: CGPoint, tiledWindowIds: Set<Int>) -> Bool {
        let point = ScreenCoordinateSpace.toWindowServer(point: location)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return true }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point),
                  (window[kCGWindowOwnerPID as String] as? pid_t) != ownPid,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            if layer < 0 || (layer > 0 && isScreenOverlay(bounds, at: point)) {
                continue
            }
            guard layer == 0, let windowId = window[kCGWindowNumber as String] as? Int else { return false }
            return tiledWindowIds.contains(windowId)
        }
        return true
    }

    /// Raised windows spanning the whole display (Dictation, screen tints, Dock
    /// event catchers) are click-through overlays rather than real obstructions.
    private static func isScreenOverlay(_ bounds: CGRect, at point: CGPoint) -> Bool {
        var displayId = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayId, &count) == .success, count > 0 else { return false }
        let display = CGDisplayBounds(displayId)
        let covered = bounds.intersection(display)
        return covered.width >= display.width * 0.95 && covered.height >= display.height * 0.9
    }
}

extension MouseEventHandler {
    /// Dropping a natively dragged Dwindle tile onto another tile swaps the two,
    /// instead of only snapping the dragged window back.
    func swapNativeTitleBarDropTargetIfNeeded(
        _ entry: WindowState,
        at location: CGPoint,
        observedFrame: CGRect?,
        lastAppliedFrame: CGRect?
    ) {
        guard let controller,
              controller.settings.gestures.mouseTitleBarDragSwap,
              let engine = controller.dwindleEngine,
              controller.workspaceManager.descriptor(for: entry.workspaceId)
              .map({ controller.settings.workspaces.layoutType(for: $0.name) }) == .dwindle,
              Self.nativeDragKeptSize(observedFrame: observedFrame, lastAppliedFrame: lastAppliedFrame),
              workspaceIdForPointer(at: location) == entry.workspaceId,
              engine.interactiveMoveBegin(token: entry.token, startLocation: location, in: entry.workspaceId)
        else { return }
        guard engine.interactiveMoveUpdate(currentLocation: location, at: controller.animationClock.now()) != nil
        else {
            engine.interactiveMoveCancel()
            return
        }
        finishDwindleMove()
    }

    nonisolated static func nativeDragKeptSize(observedFrame: CGRect?, lastAppliedFrame: CGRect?) -> Bool {
        guard let observedFrame, let lastAppliedFrame else { return false }
        return abs(observedFrame.width - lastAppliedFrame.width) <= 2
            && abs(observedFrame.height - lastAppliedFrame.height) <= 2
    }
}
