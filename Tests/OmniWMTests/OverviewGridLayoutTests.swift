// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class OverviewGridLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func layout(workspaceCount: Int, grid: Bool, topInset: CGFloat = 0) -> OverviewLayout {
        let workspaces = (0 ..< workspaceCount).map { index in
            OverviewWorkspaceLayoutItem(
                id: WorkspaceDescriptor(name: "\(index + 1)").id,
                name: "\(index + 1)",
                isActive: index == 0
            )
        }
        return OverviewLayoutCalculator(screenFrame: screen, scale: 1, topInset: topInset, grid: grid)
            .calculateLayout(
                workspaces: workspaces,
                windows: [:],
                searchQuery: "",
                monitorId: Monitor.ID(displayId: 77)
            )
    }

    func testGridFitsAllWorkspacesWithoutOverlap() throws {
        let layout = layout(workspaceCount: 7, grid: true)
        let sections = layout.workspaceSections
        XCTAssertEqual(sections.count, 7)
        let target = try XCTUnwrap(layout.newWorkspaceTarget)
        let frames = sections.map(\.sectionFrame)
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
            XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
            XCTAssertLessThan(frame.maxY, layout.searchBarFrame.minY)
            XCTAssertFalse(frame.intersects(target.frame))
            for other in frames[(index + 1)...] {
                XCTAssertFalse(frame.intersects(other), "\(frame) overlaps \(other)")
            }
        }
        XCTAssertGreaterThan(Set(frames.map(\.minY)).count, 1)
        XCTAssertGreaterThan(Set(frames.map(\.minX)).count, 1)
        XCTAssertEqual(frames[0].minY, frames[1].minY)
    }

    func testGridCellsKeepScreenAspectRatio() throws {
        let section = try XCTUnwrap(layout(workspaceCount: 5, grid: true).workspaceSections.first)
        XCTAssertEqual(
            section.visibleFrame.width / section.visibleFrame.height,
            screen.width / screen.height,
            accuracy: 0.001
        )
        XCTAssertEqual(section.ribbonFrame, section.visibleFrame)
    }

    func testGridNeverExceedsListPreviewSize() throws {
        let list = try XCTUnwrap(layout(workspaceCount: 1, grid: false).workspaceSections.first)
        let grid = try XCTUnwrap(layout(workspaceCount: 1, grid: true).workspaceSections.first)
        XCTAssertLessThanOrEqual(grid.visibleFrame.width, list.visibleFrame.width + 0.001)
    }

    func testListModeStacksWorkspacesVertically() {
        let frames = layout(workspaceCount: 3, grid: false).workspaceSections.map(\.sectionFrame)
        XCTAssertEqual(Set(frames.map(\.minX)).count, 1)
        XCTAssertGreaterThan(frames[0].minY, frames[1].minY)
        XCTAssertGreaterThan(frames[1].minY, frames[2].minY)
    }

    func testSearchBarMovesBelowTopInset() {
        let plain = layout(workspaceCount: 1, grid: true).searchBarFrame
        let notched = layout(workspaceCount: 1, grid: true, topInset: 32).searchBarFrame
        XCTAssertEqual(plain.minY - notched.minY, 32, accuracy: 0.001)
        XCTAssertLessThanOrEqual(notched.maxY, screen.maxY - 32)
    }

    func testWorkspaceGridSettingDefaultsOnAndRoundTrips() throws {
        XCTAssertEqual(SettingsExport.defaults().overview.workspaceGrid, true)
        var export = SettingsExport.defaults()
        export.overview.workspaceGrid = false
        let decoded = try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(export))
        XCTAssertEqual(decoded.overview.workspaceGrid, false)
        export.overview.workspaceGrid = nil
        XCTAssertEqual(try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(export)).overview.workspaceGrid, true)
    }

    func testArrowKeysMoveBetweenGridCellsOnTheSameRow() throws {
        let layout = layout(workspaceCount: 4, grid: true)
        let ids = layout.workspaceSections.map(\.workspaceId)
        XCTAssertEqual(layout.workspaceSections[0].sectionFrame.minY, layout.workspaceSections[1].sectionFrame.minY)
        let right = OverviewNavigation.nextSelection(
            in: layout, from: .workspace(ids[0]), direction: .right, searching: false
        )
        XCTAssertEqual(right, .workspace(ids[1]))
        let left = OverviewNavigation.nextSelection(
            in: layout,
            from: .workspace(ids[1]),
            direction: .left,
            searching: false
        )
        XCTAssertEqual(left, .workspace(ids[0]))
        XCTAssertEqual(
            OverviewNavigation.nextSelection(in: layout, from: .workspace(ids[0]), direction: .left, searching: false),
            .workspace(ids[0])
        )
    }
}
