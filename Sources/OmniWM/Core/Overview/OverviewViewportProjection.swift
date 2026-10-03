// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon
import Foundation
import QuartzCore
import ScreenCaptureKit

@MainActor
final class OverviewViewportProjection {
    private weak var wmController: WMController?
    private let overviewSnapshot: OverviewSnapshot
    private(set) var layoutsByMonitor: [Monitor.ID: OverviewLayout] = [:]
    var searchQuery = ""
    var scale: CGFloat = 1.0
    var selection: OverviewSelection?
    var selectedWindowHandle: WindowHandle? {
        get { selection?.windowHandle }
        set { selection = newValue.map(OverviewSelection.window) }
    }

    var activeInteractionMonitorId: Monitor.ID?
    static let zoomEpsilon: CGFloat = 0.0001

    init(wmController: WMController, snapshot: OverviewSnapshot, scale: CGFloat) {
        self.wmController = wmController
        overviewSnapshot = snapshot
        self.scale = scale
    }

    func resetLayouts() {
        layoutsByMonitor = [:]
    }

    private enum ScrollTuning {
        static let preciseScrollMultiplier: CGFloat = 3.5
        static let nonPreciseScrollMultiplier: CGFloat = 40.0
        static let zoomStep: CGFloat = 0.05
    }

    struct SelectedViewportAnchor {
        let handle: WindowHandle
        let midpointY: CGFloat
    }

    func rebuildProjectedLayouts(
        preservingSelectedAnchors anchors: [Monitor.ID: SelectedViewportAnchor] = [:],
        revealingSelection: Bool = true
    ) {
        guard let wmController else { return }

        let previousLayouts = layoutsByMonitor
        let monitors = wmController.workspaceManager.monitors

        if let selectedWindowHandle,
           overviewSnapshot.windows[selectedWindowHandle] == nil
        {
            self.selectedWindowHandle = nil
        }

        layoutsByMonitor = [:]
        for monitor in monitors {
            var layout = projectedLayout(
                for: monitor
            )
            let viewportFrame = OverviewLayoutCalculator.viewportFrame(for: monitor.frame)
            let previousOffset = previousLayouts[monitor.id]?.scrollOffset ?? 0
            layout.scrollOffset = OverviewLayoutCalculator.clampedScrollOffset(
                previousOffset,
                layout: layout,
                screenFrame: viewportFrame
            )
            restoreTabPreviews(from: previousLayouts[monitor.id], in: &layout)
            layout.dragTarget = previousLayouts[monitor.id]?.dragTarget
            layoutsByMonitor[monitor.id] = layout
        }

        reconcileSelectedWindowHandle()

        if let activeInteractionMonitorId,
           layoutsByMonitor[activeInteractionMonitorId] == nil
        {
            self.activeInteractionMonitorId = nil
        }

        if activeInteractionMonitorId == nil {
            activeInteractionMonitorId = monitors.first?.id
        }

        restoreSelectedViewportAnchors(anchors)
        if revealingSelection {
            revealSelectedWindow(on: activeInteractionMonitorId)
        }
        settleRestFrames(targetWindow: nil)
    }

    func settleRestFrames(targetWindow: WindowHandle?) {
        guard let wmController else { return }
        let workspaceManager = wmController.workspaceManager
        let targetWorkspaceId = targetWindow.flatMap { workspaceManager.workspace(for: $0.id) }
        let targetMonitorId = targetWorkspaceId.flatMap { workspaceManager.monitorForWorkspace($0)?.id }
        for monitorId in layoutsByMonitor.keys {
            let anchorWorkspaceId = monitorId == targetMonitorId
                ? targetWorkspaceId
                : workspaceManager.activeWorkspace(on: monitorId)?.id
            mutateLayout(for: monitorId) { $0.settleRestFrames(anchorWorkspaceId: anchorWorkspaceId) }
        }
    }

    private func projectedLayout(
        for monitor: Monitor
    ) -> OverviewLayout {
        let workspaces = overviewSnapshot.workspaces.filter { $0.displayId == monitor.displayId }
        let workspaceIds = Set(workspaces.map(\.id))
        let localizedWindowData = overviewSnapshot.windows
            .filter { workspaceIds.contains($0.value.workspaceId) }
            .mapValues { windowData in
                OverviewWindowLayoutData(
                    token: windowData.token,
                    workspaceId: windowData.workspaceId,
                    title: windowData.title,
                    appName: windowData.appName,
                    appIcon: windowData.appIcon,
                    frame: OverviewLayoutCalculator.localizedFrame(windowData.frame, to: monitor.frame),
                    isNativeFullscreen: windowData.isNativeFullscreen,
                    floatingPreviewFrame: windowData.floatingPreviewFrame.map { OverviewLayoutCalculator.localizedFrame(
                        $0,
                        to: monitor.frame
                    ) }
                )
            }

        let viewportFrame = OverviewLayoutCalculator.viewportFrame(for: monitor.frame)
        let layout = OverviewLayoutCalculator(
            screenFrame: viewportFrame,
            scale: scale,
            topInset: NSScreen.screens.first { $0.displayId == monitor.displayId }?.safeAreaInsets.top ?? 0,
            grid: wmController?.settings.overview.workspaceGrid ?? true
        ).calculateLayout(
            workspaces: workspaces,
            windows: localizedWindowData,
            dwindleGroupsByWorkspace: overviewSnapshot.dwindleGroupsByWorkspace,
            searchQuery: searchQuery,
            monitorId: monitor.id
        )
        return layout
    }

    func canonicalLayout(preferredMonitorId: Monitor.ID? = nil) -> OverviewLayout? {
        let monitorId = preferredMonitorId
            ?? activeInteractionMonitorId
            ?? wmController?.workspaceManager.monitors.first?.id
        if let monitorId,
           let layout = layoutsByMonitor[monitorId]
        {
            return layout
        }
        return layoutsByMonitor.values.first
    }

    func captureSelectedViewportAnchors() -> [Monitor.ID: SelectedViewportAnchor] {
        guard let selectedWindowHandle else { return [:] }

        var anchors: [Monitor.ID: SelectedViewportAnchor] = [:]
        anchors.reserveCapacity(layoutsByMonitor.count)
        for (monitorId, layout) in layoutsByMonitor {
            guard let window = layout.window(for: selectedWindowHandle), window.matchesSearch else { continue }
            anchors[monitorId] = SelectedViewportAnchor(
                handle: selectedWindowHandle,
                midpointY: window.overviewFrame.midY - layout.scrollOffset
            )
        }
        return anchors
    }

    private func restoreSelectedViewportAnchors(_ anchors: [Monitor.ID: SelectedViewportAnchor]) {
        guard let selectedWindowHandle else { return }

        for (monitorId, anchor) in anchors where anchor.handle == selectedWindowHandle {
            mutateLayout(for: monitorId) { layout in
                guard let window = layout.window(for: selectedWindowHandle), window.matchesSearch else { return }
                let screenFrame = viewportFrame(for: monitorId)
                layout.scrollOffset = OverviewLayoutCalculator.clampedScrollOffset(
                    window.overviewFrame.midY - anchor.midpointY,
                    layout: layout,
                    screenFrame: screenFrame
                )
            }
        }
    }

    @discardableResult
    func revealSelectedWindow(on monitorId: Monitor.ID?) -> Bool {
        if let selection, selection.windowHandle == nil,
           let monitorId, var layout = layoutsByMonitor[monitorId],
           let frame = selection.frame(in: layout)
        {
            let offset = OverviewLayoutCalculator.scrollOffsetRevealing(
                targetFrame: frame,
                currentOffset: layout.scrollOffset,
                layout: layout,
                screenFrame: viewportFrame(for: monitorId)
            )
            guard offset != layout.scrollOffset else { return false }
            layout.scrollOffset = offset
            layoutsByMonitor[monitorId] = layout
            return true
        }
        guard let monitorId,
              let selectedWindowHandle,
              var layout = layoutsByMonitor[monitorId],
              let window = layout.window(for: selectedWindowHandle),
              window.matchesSearch
        else {
            return false
        }
        let revealedTab = !window.isDisplayed
        layout.revealTab(selectedWindowHandle)
        let revealedFrame = layout.window(for: selectedWindowHandle)?.overviewFrame ?? window.overviewFrame
        let scrollOffset = OverviewLayoutCalculator.scrollOffsetRevealing(
            targetFrame: revealedFrame,
            currentOffset: layout.scrollOffset,
            layout: layout,
            screenFrame: viewportFrame(for: monitorId)
        )
        guard revealedTab || scrollOffset != layout.scrollOffset else { return false }
        layout.scrollOffset = scrollOffset
        layoutsByMonitor[monitorId] = layout
        return true
    }

    func setSelectedWindowHandle(_ handle: WindowHandle?) {
        selectedWindowHandle = handle
    }

    private func reconcileSelectedWindowHandle() {
        guard let layout = canonicalLayout(preferredMonitorId: activeInteractionMonitorId) else {
            selectedWindowHandle = nil
            return
        }

        if searchQuery.isEmpty, let selection, selection.windowHandle == nil,
           selection.frame(in: layout) != nil { return }

        if let selectedWindowHandle,
           let selectedWindow = layout.window(for: selectedWindowHandle),
           selectedWindow.matchesSearch
        {
            return
        }

        selection = OverviewSearchFilter.firstMatchingWindow(in: layout).map { .window($0.handle) }
            ?? OverviewNavigation.selections(in: layout, searching: !searchQuery.isEmpty).first
    }

    private func mutateLayout(
        for monitorId: Monitor.ID,
        _ mutate: (inout OverviewLayout) -> Void
    ) {
        guard var layout = layoutsByMonitor[monitorId] else { return }
        mutate(&layout)
        layoutsByMonitor[monitorId] = layout
    }

    func setDragTarget(_ target: OverviewDragTarget?, for monitorId: Monitor.ID) {
        for id in layoutsByMonitor.keys {
            mutateLayout(for: id) { layout in
                layout.dragTarget = id == monitorId ? target : nil
            }
        }
    }

    func clearDragTargets() {
        for monitorId in layoutsByMonitor.keys {
            mutateLayout(for: monitorId) { layout in
                layout.dragTarget = nil
            }
        }
    }

    func viewportFrame(for monitorId: Monitor.ID) -> CGRect {
        guard let wmController,
              let monitor = wmController.workspaceManager.monitor(byId: monitorId)
        else {
            return .zero
        }
        return OverviewLayoutCalculator.viewportFrame(for: monitor.frame)
    }

    func pointerLocation(
        from localPoint: CGPoint,
        on monitorId: Monitor.ID
    ) -> (monitorId: Monitor.ID, point: CGPoint) {
        guard let wmController else { return (monitorId, localPoint) }
        let global = globalPoint(from: localPoint, on: monitorId)
        guard let monitor = wmController.workspaceManager.monitors.first(where: { $0.frame.contains(global) }),
              monitor.id != monitorId,
              layoutsByMonitor[monitor.id] != nil
        else { return (monitorId, localPoint) }
        return (monitor.id, CGPoint(x: global.x - monitor.frame.minX, y: global.y - monitor.frame.minY))
    }

    func globalPoint(from localPoint: CGPoint, on monitorId: Monitor.ID) -> CGPoint {
        guard let wmController,
              let monitor = wmController.workspaceManager.monitor(byId: monitorId)
        else {
            return localPoint
        }
        return CGPoint(
            x: monitor.frame.minX + localPoint.x,
            y: monitor.frame.minY + localPoint.y
        )
    }
}

extension OverviewViewportProjection {
    private func restoreTabPreviews(from previous: OverviewLayout?, in layout: inout OverviewLayout) {
        guard let previous else { return }
        for section in previous.workspaceSections {
            for members in previous.tabbedWindowGroups(in: section.workspaceId) {
                if let handle = members.first(where: { previous.window(for: $0)?.isDisplayed == true }),
                   layout.window(for: handle)?.matchesSearch == true
                {
                    layout.revealTab(handle)
                }
            }
        }
    }

    func performSelectionNavigation(
        on monitorId: Monitor.ID?,
        resolveNextSelection: (OverviewLayout, OverviewSelection?) -> OverviewSelection?
    ) -> (changed: Bool, revealed: Bool) {
        let targetMonitorId = monitorId ?? activeInteractionMonitorId
        if let targetMonitorId {
            activeInteractionMonitorId = targetMonitorId
        }

        guard let layout = canonicalLayout(preferredMonitorId: targetMonitorId),
              let nextSelection = resolveNextSelection(layout, selection)
        else { return (false, false) }

        guard nextSelection != selection else { return (false, false) }
        selection = nextSelection
        return (true, revealSelectedWindow(on: targetMonitorId))
    }

    @discardableResult
    func adjustScrollOffset(by delta: CGFloat, on monitorId: Monitor.ID) -> Bool {
        activeInteractionMonitorId = monitorId
        var changed = false
        mutateLayout(for: monitorId) { layout in
            let screenFrame = viewportFrame(for: monitorId)
            let nextOffset = layout.scrollOffset + delta
            let offset = OverviewLayoutCalculator.clampedScrollOffset(
                nextOffset,
                layout: layout,
                screenFrame: screenFrame
            )
            changed = offset != layout.scrollOffset
            layout.scrollOffset = offset
        }
        return changed
    }

    func handleScroll(_ event: OverviewScrollInput.Event, on monitorId: Monitor.ID) -> Bool {
        activeInteractionMonitorId = monitorId
        let delta = event.dominantDelta

        if event.modifiers.contains([.option, .shift]) {
            guard abs(delta) > Self.zoomEpsilon else { return false }
            let step: CGFloat = delta > 0 ? ScrollTuning.zoomStep : -ScrollTuning.zoomStep
            let nextScale = (scale + step).clamped(to: 0.5 ... 1.5)
            guard abs(nextScale - scale) > Self.zoomEpsilon else { return false }
            let anchors = captureSelectedViewportAnchors()
            scale = nextScale
            rebuildProjectedLayouts(preservingSelectedAnchors: anchors)
            return true
        }

        let settings = wmController?.settings.overview
        let multiplier = event.isPrecise
            ? ScrollTuning.preciseScrollMultiplier
            : ScrollTuning.nonPreciseScrollMultiplier
            * CGFloat(OverviewSettings.validatedMouseScrollSpeed(settings?.mouseScrollSpeed ?? 1))
        let scrollDelta = delta * multiplier * (settings?.invertScrollDirection == true ? -1 : 1)
        if event.dominantAxis == .horizontal {
            return false
        }
        return adjustScrollOffset(by: scrollDelta, on: monitorId)
    }
}
