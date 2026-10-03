// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

enum OverviewState {
    case closed
    case opening
    case open
    case closing(targetWindow: WindowHandle?)

    var isOpen: Bool {
        switch self {
        case .open,
             .opening,
             .closing:
            return true
        case .closed:
            return false
        }
    }

    var isAnimating: Bool {
        switch self {
        case .opening,
             .closing:
            return true
        case .open,
             .closed:
            return false
        }
    }

    var gestureAction: OverviewGestureAction {
        switch self {
        case .closed:
            .open
        case .open:
            .close
        case .opening,
             .closing:
            .resume
        }
    }
}

struct OverviewWorkspaceSection {
    let workspaceId: WorkspaceDescriptor.ID
    let name: String
    var windows: [OverviewWindowItem]
    var sectionFrame: CGRect
    var labelFrame: CGRect
    var gridFrame: CGRect
    var isActive: Bool
    var displayId: CGDirectDisplayID?
    var viewportFrame: CGRect = .zero
    var visibleFrame: CGRect = .zero
    var ribbonFrame: CGRect = .zero
    var orientation: Monitor.Orientation = .horizontal

    var isEmpty: Bool {
        windows.isEmpty
    }

    var contentScale: CGFloat {
        viewportFrame.width > 0 ? visibleFrame.width / viewportFrame.width : 1
    }

    func clipFrame(for window: OverviewWindowItem) -> CGRect {
        visibleFrame
    }

    func containsInRibbon(_ frame: CGRect) -> Bool {
        ribbonFrame.isEmpty || frame.intersects(ribbonFrame)
    }
}

struct OverviewNewWorkspaceTarget {
    let monitorId: Monitor.ID
    let frame: CGRect
}

struct OverviewDwindleGroup: Equatable {
    let id: DwindleTileId
    let windowHandles: [WindowHandle]
    let activeHandle: WindowHandle
}

struct OverviewWindowItem {
    let handle: WindowHandle
    let windowId: Int
    let workspaceId: WorkspaceDescriptor.ID
    let title: String
    let appName: String
    let appIcon: CGImage?
    let originalFrame: CGRect
    var overviewFrame: CGRect
    let matchesSearch: Bool
    var restFrame: CGRect?
    var isNativeFullscreen = false
    var contentScale: CGFloat = 1
    var isDisplayed = true

    var closeButtonFrame: CGRect {
        let size: CGFloat = 20
        let padding: CGFloat = 6
        return CGRect(
            x: overviewFrame.maxX - size - padding,
            y: overviewFrame.maxY - size - padding,
            width: size,
            height: size
        )
    }

    func interpolatedFrame(progress: Double) -> CGRect {
        let fraction = CGFloat(progress)
        let from = restFrame ?? originalFrame
        return CGRect(
            x: from.origin.x + (overviewFrame.origin.x - from.origin.x) * fraction,
            y: from.origin.y + (overviewFrame.origin.y - from.origin.y) * fraction,
            width: from.width + (overviewFrame.width - from.width) * fraction,
            height: from.height + (overviewFrame.height - from.height) * fraction
        )
    }
}

struct OverviewLayout {
    struct WindowHit {
        let window: OverviewWindowItem
        let isCloseButton: Bool
    }

    private struct WindowPosition {
        let sectionIndex: Int
        let windowIndex: Int
    }

    private(set) var workspaceSections: [OverviewWorkspaceSection]
    private(set) var anchorWorkspaceId: WorkspaceDescriptor.ID?

    var searchBarFrame: CGRect
    var viewportFrame: CGRect
    var totalContentHeight: CGFloat
    var scrollOffset: CGFloat
    var scale: CGFloat
    var dragTarget: OverviewDragTarget?
    var newWorkspaceTarget: OverviewNewWorkspaceTarget?
    var dwindleGroupsByWorkspace: [WorkspaceDescriptor.ID: [OverviewDwindleGroup]]
    private var windowPositionByHandle: [WindowHandle: WindowPosition]

    init() {
        workspaceSections = []
        searchBarFrame = .zero
        viewportFrame = .zero
        totalContentHeight = 0
        scrollOffset = 0
        scale = 1.0
        dragTarget = nil
        newWorkspaceTarget = nil
        dwindleGroupsByWorkspace = [:]
        windowPositionByHandle = [:]
    }

    var allWindows: [OverviewWindowItem] {
        workspaceSections.flatMap(\.windows)
    }

    mutating func replaceWorkspaceSections(_ sections: [OverviewWorkspaceSection]) {
        workspaceSections = sections
        rebuildWindowIndex()
    }

    mutating func settleRestFrames(anchorWorkspaceId: WorkspaceDescriptor.ID?) {
        self.anchorWorkspaceId = anchorWorkspaceId
        let anchor = workspaceSections
            .first { $0.workspaceId == anchorWorkspaceId }
            .flatMap { OverviewRenderGeometry.restAnchor(for: $0) }
        for sectionIndex in workspaceSections.indices {
            let isAnchor = workspaceSections[sectionIndex].workspaceId == anchorWorkspaceId
            for windowIndex in workspaceSections[sectionIndex].windows.indices {
                let overviewFrame = workspaceSections[sectionIndex].windows[windowIndex].overviewFrame
                workspaceSections[sectionIndex].windows[windowIndex].restFrame = isAnchor
                    ? nil
                    : anchor.map { OverviewRenderGeometry.restFrame(for: overviewFrame, anchor: $0) }
            }
        }
    }

    private mutating func rebuildWindowIndex() {
        windowPositionByHandle.removeAll(keepingCapacity: true)
        for sectionIndex in workspaceSections.indices {
            for windowIndex in workspaceSections[sectionIndex].windows.indices {
                let handle = workspaceSections[sectionIndex].windows[windowIndex].handle
                windowPositionByHandle[handle] = WindowPosition(sectionIndex: sectionIndex, windowIndex: windowIndex)
            }
        }
    }

    func windowAt(point: CGPoint) -> OverviewWindowItem? {
        windowHit(at: point)?.window
    }

    func windowHit(at point: CGPoint) -> WindowHit? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        for section in workspaceSections {
            for window in section.windows.reversed()
                where window.matchesSearch && window.isDisplayed
            {
                let clip = section.clipFrame(for: window)
                if clip.isEmpty || clip.contains(adjustedPoint), window.overviewFrame.contains(adjustedPoint) {
                    return WindowHit(
                        window: window,
                        isCloseButton: window.closeButtonFrame.contains(adjustedPoint)
                    )
                }
            }
        }
        return nil
    }

    func workspaceSection(at point: CGPoint) -> OverviewWorkspaceSection? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        for section in workspaceSections where section.sectionFrame.contains(adjustedPoint) {
            return section
        }
        return nil
    }

    func ribbonSection(at point: CGPoint) -> OverviewWorkspaceSection? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        for section in workspaceSections where section.ribbonFrame.contains(adjustedPoint) {
            return section
        }
        return nil
    }

    mutating func revealTab(_ handle: WindowHandle) {
        guard let position = windowPositionByHandle[handle],
              let members = tabGroup(containing: handle, in: workspaceSections[position.sectionIndex].workspaceId)
        else { return }
        for index in workspaceSections[position.sectionIndex].windows.indices {
            let member = workspaceSections[position.sectionIndex].windows[index].handle
            if members.contains(member) {
                workspaceSections[position.sectionIndex].windows[index].isDisplayed = member == handle
            }
        }
    }

    func tabGroup(containing handle: WindowHandle, in workspaceId: WorkspaceDescriptor.ID) -> [WindowHandle]? {
        return dwindleGroupsByWorkspace[workspaceId]?
            .first(where: { $0.windowHandles.contains(handle) })?.windowHandles
    }

    func tabbedWindowGroups(in workspaceId: WorkspaceDescriptor.ID) -> [[WindowHandle]] {
        return (dwindleGroupsByWorkspace[workspaceId] ?? []).map(\.windowHandles)
    }

    func resolveDragTarget(at point: CGPoint, draggedHandle: WindowHandle?) -> OverviewDragTarget? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        if let newWorkspaceTarget, newWorkspaceTarget.frame.contains(adjustedPoint) {
            return .newWorkspace(monitorId: newWorkspaceTarget.monitorId)
        }

        if let window = windowAt(point: point) {
            guard window.handle != draggedHandle else { return nil }
            return .workspaceMove(workspaceId: window.workspaceId)
        }

        if let section = workspaceSection(at: point) {
            return .workspaceMove(workspaceId: section.workspaceId)
        }

        return nil
    }

    func window(for handle: WindowHandle) -> OverviewWindowItem? {
        guard let position = windowPositionByHandle[handle],
              workspaceSections.indices.contains(position.sectionIndex),
              workspaceSections[position.sectionIndex].windows.indices.contains(position.windowIndex)
        else {
            return nil
        }
        return workspaceSections[position.sectionIndex].windows[position.windowIndex]
    }
}

enum OverviewDragTarget: Equatable {
    case floatingPlacement(destination: OverviewFloatingDestination, frame: CGRect, previewFrame: CGRect)
    case newWorkspace(monitorId: Monitor.ID)
    case workspaceMove(
        workspaceId: WorkspaceDescriptor.ID
    )
}
