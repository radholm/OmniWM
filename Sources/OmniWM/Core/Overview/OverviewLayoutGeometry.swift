// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

@MainActor
struct OverviewLayoutGeometry {
    let screenFrame: CGRect
    let metricsScale: CGFloat
    let availableWidth: CGFloat
    let searchBarFrame: CGRect
    let scaledWindowPadding: CGFloat
    let scaledWorkspaceLabelHeight: CGFloat
    let scaledWorkspaceSectionPadding: CGFloat
    let scaledWindowSpacing: CGFloat
    private(set) var stripScale: CGFloat
    /// Horizontal extent of the column the workspace sections are laid out in (the full padded width by
    /// default, one grid cell in the workspace grid).
    private(set) var cellMinX: CGFloat
    private(set) var cellWidth: CGFloat
    private(set) var isGridCell = false
    let initialContentY: CGFloat
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat

    /// `topInset` keeps the search bar clear of screen areas such as the camera housing (notch).
    init(screenFrame: CGRect, scale: CGFloat, topInset: CGFloat = 0) {
        let metricsScale = OverviewLayoutCalculator.clampedScale(scale)
        let scaledSearchBarHeight = OverviewLayoutMetrics.searchBarHeight * metricsScale
        let scaledSearchBarPadding = OverviewLayoutMetrics.searchBarPadding * metricsScale
        let searchBarY = screenFrame.maxY - max(topInset, 0) - scaledSearchBarHeight - scaledSearchBarPadding
        let searchBarFrame = CGRect(
            x: screenFrame.minX + screenFrame.width * 0.25,
            y: searchBarY,
            width: screenFrame.width * 0.5,
            height: scaledSearchBarHeight
        )

        let scaledWindowPadding = OverviewLayoutMetrics.windowPadding * metricsScale
        let availableWidth = max(1, screenFrame.width - (scaledWindowPadding * 2))

        self.screenFrame = screenFrame
        self.metricsScale = metricsScale
        self.availableWidth = availableWidth
        self.searchBarFrame = searchBarFrame
        self.scaledWindowPadding = scaledWindowPadding
        self.scaledWorkspaceLabelHeight = OverviewLayoutMetrics.workspaceLabelHeight * metricsScale
        self.scaledWorkspaceSectionPadding = OverviewLayoutMetrics.workspaceSectionPadding * metricsScale
        self.scaledWindowSpacing = OverviewLayoutMetrics.windowSpacing * metricsScale
        stripScale = max(1, (searchBarY - screenFrame.minY - 56) * 0.5 * metricsScale) / max(screenFrame.height, 1)
        self.initialContentY = searchBarY - OverviewLayoutMetrics.contentTopPadding * metricsScale
        self.contentTopPadding = OverviewLayoutMetrics.contentTopPadding * metricsScale
        self.contentBottomPadding = OverviewLayoutMetrics.contentBottomPadding * metricsScale
        cellMinX = screenFrame.minX + scaledWindowPadding
        cellWidth = availableWidth
    }

    /// A copy that lays sections out in one grid cell, with workspace previews at `scale`.
    func cell(minX: CGFloat, width: CGFloat, scale: CGFloat) -> OverviewLayoutGeometry {
        var cell = self
        cell.cellMinX = minX
        cell.cellWidth = width
        cell.stripScale = scale
        cell.isGridCell = true
        return cell
    }

    var monitorLocalFrame: CGRect {
        CGRect(origin: .zero, size: screenFrame.size)
    }

    func makeWorkspaceLabelFrame(currentY: inout CGFloat) -> CGRect {
        currentY -= scaledWorkspaceLabelHeight
        let frame = CGRect(
            x: cellMinX,
            y: currentY,
            width: cellWidth,
            height: scaledWorkspaceLabelHeight
        )
        currentY -= scaledWorkspaceSectionPadding
        return frame
    }

    func visibleFrame(top: CGFloat, scale: CGFloat) -> CGRect {
        let size = CGSize(width: screenFrame.width * scale, height: screenFrame.height * scale)
        return CGRect(
            x: cellMinX + cellWidth / 2 - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    func ribbonFrame(for visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: cellMinX,
            y: visibleFrame.minY,
            width: cellWidth,
            height: visibleFrame.height
        )
    }

    func project(_ monitorLocalFrame: CGRect, into visibleFrame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: visibleFrame.minX + monitorLocalFrame.minX * scale,
            y: visibleFrame.minY + monitorLocalFrame.minY * scale,
            width: max(monitorLocalFrame.width * scale, 1),
            height: max(monitorLocalFrame.height * scale, 1)
        )
    }

    func makeWorkspaceSection(
        workspace: OverviewWorkspaceLayoutItem,
        windows: [OverviewWindowItem],
        labelFrame: CGRect,
        visibleFrame: CGRect,
        currentY: inout CGFloat
    ) -> OverviewWorkspaceSection {
        let ribbonFrame = ribbonFrame(for: visibleFrame)
        let sectionBottom = ribbonFrame.minY
        let sectionFrame = CGRect(
            x: isGridCell ? cellMinX : screenFrame.minX,
            y: sectionBottom,
            width: isGridCell ? cellWidth : screenFrame.width,
            height: currentY + scaledWorkspaceLabelHeight - sectionBottom
        )

        let section = OverviewWorkspaceSection(
            workspaceId: workspace.id,
            name: workspace.name,
            windows: windows,
            sectionFrame: sectionFrame,
            labelFrame: labelFrame,
            gridFrame: ribbonFrame,
            isActive: workspace.isActive,
            displayId: workspace.displayId,
            viewportFrame: monitorLocalFrame,
            visibleFrame: visibleFrame,
            ribbonFrame: ribbonFrame
        )
        currentY = section.sectionFrame.minY - scaledWorkspaceSectionPadding
        return section
    }

    func buildEmptyWorkspaceSection(
        workspace: OverviewWorkspaceLayoutItem,
        currentY: inout CGFloat
    ) -> OverviewWorkspaceSection {
        let labelFrame = makeWorkspaceLabelFrame(currentY: &currentY)
        let visibleFrame = visibleFrame(
            top: currentY,
            scale: stripScale
        )
        return makeWorkspaceSection(
            workspace: workspace,
            windows: [],
            labelFrame: labelFrame,
            visibleFrame: visibleFrame,
            currentY: &currentY
        )
    }

    func makeWindowItem(
        handle: WindowHandle,
        workspaceId: WorkspaceDescriptor.ID,
        windowData: OverviewWindowLayoutData,
        overviewFrame: CGRect,
        searchQuery: String
    ) -> OverviewWindowItem {
        let matchesSearch = searchQuery.isEmpty ||
            windowData.title.localizedCaseInsensitiveContains(searchQuery) ||
            windowData.appName.localizedCaseInsensitiveContains(searchQuery)

        var item = OverviewWindowItem(
            handle: handle,
            windowId: windowData.token.windowId,
            workspaceId: workspaceId,
            title: windowData.title,
            appName: windowData.appName,
            appIcon: windowData.appIcon?.cgImage(forProposedRect: nil, context: nil, hints: nil),
            originalFrame: windowData.frame,
            overviewFrame: overviewFrame,
            matchesSearch: matchesSearch
        )
        item.isNativeFullscreen = windowData.isNativeFullscreen
        item.contentScale = stripScale
        return item
    }

    func totalContentHeight(currentY: CGFloat) -> CGFloat {
        let contentTop = searchBarFrame.minY - contentTopPadding
        let contentBottom = currentY + scaledWorkspaceSectionPadding - contentBottomPadding
        return contentTop - contentBottom
    }
}
