// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class OverviewLayoutCalculatorTests: XCTestCase {
    func testGenericFallbackProjectsMonitorLocalFramesAtUniformStripScale() throws {
        let (layout, handles) = makeMixedLayout()
        let section = try XCTUnwrap(layout.workspaceSections.first)

        XCTAssertEqual(layout.searchBarFrame, CGRect(x: 50, y: 620, width: 500, height: 55))
        XCTAssertEqual(layout.viewportFrame, CGRect(x: -200, y: -100, width: 1000, height: 800))
        XCTAssertEqual(section.name, "Generic")
        XCTAssertTrue(section.isActive)
        XCTAssertEqual(section.labelFrame, CGRect(x: -170, y: 555, width: 940, height: 40))
        assertFrame(section.visibleFrame, CGRect(x: 40.625, y: 120, width: 518.75, height: 415))
        assertFrame(section.ribbonFrame, CGRect(x: -170, y: 120, width: 940, height: 415))
        XCTAssertEqual(section.gridFrame, section.ribbonFrame)
        assertFrame(section.sectionFrame, CGRect(x: -200, y: 120, width: 1000, height: 455))
        XCTAssertEqual(section.windows.map(\.handle), Array(handles.prefix(2)))
        for window in section.windows {
            assertFrame(
                window.overviewFrame,
                CGRect(
                    x: 40.625 + window.originalFrame.minX * 0.51875,
                    y: 120 + window.originalFrame.minY * 0.51875,
                    width: window.originalFrame.width * 0.51875,
                    height: window.originalFrame.height * 0.51875
                )
            )
        }
        XCTAssertEqual(section.windows.first?.originalFrame, CGRect(x: -640.25, y: 25.5, width: 300, height: 200))
    }

    func testEmptyWorkspacesKeepFullHeightRibbonsThatAcceptDrops() throws {
        let (layout, _) = makeMixedLayout()
        let section = try XCTUnwrap(layout.workspaceSections.first { $0.name == "Empty" })

        XCTAssertTrue(section.isEmpty)
        XCTAssertEqual(layout.workspaceSections.count, 3)
        assertFrame(section.visibleFrame, CGRect(x: 40.625, y: -870, width: 518.75, height: 415))
        XCTAssertEqual(section.visibleFrame.size, layout.workspaceSections.first?.visibleFrame.size)
        assertFrame(section.sectionFrame, CGRect(x: -200, y: -870, width: 1000, height: 455))
        let point = CGPoint(x: section.visibleFrame.midX, y: section.visibleFrame.midY)
        XCTAssertEqual(layout.ribbonSection(at: point)?.workspaceId, section.workspaceId)
        XCTAssertEqual(
            layout.resolveDragTarget(at: point, draggedHandle: nil),
            .workspaceMove(workspaceId: section.workspaceId)
        )
        XCTAssertNotNil(OverviewRenderGeometry.restAnchor(for: section))
    }

    func testDragAutoScrollVelocityOnlyInsideEdgeBands() {
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(
            OverviewLayoutCalculator.dragAutoScrollVelocity(pointerY: 400, viewportFrame: viewport, scale: 1),
            0
        )
        XCTAssertGreaterThan(
            OverviewLayoutCalculator.dragAutoScrollVelocity(pointerY: 790, viewportFrame: viewport, scale: 1),
            0
        )
        XCTAssertLessThan(
            OverviewLayoutCalculator.dragAutoScrollVelocity(pointerY: 10, viewportFrame: viewport, scale: 1),
            0
        )
        XCTAssertEqual(
            abs(OverviewLayoutCalculator.dragAutoScrollVelocity(pointerY: 800, viewportFrame: viewport, scale: 1)),
            1_400
        )
    }

    func testMixedProjectionPreservesHandleIdentitySearchAndContentBounds() {
        let (layout, handles) = makeMixedLayout()

        XCTAssertEqual(layout.workspaceSections.count, 3)
        XCTAssertEqual(layout.scale, 1.25)
        XCTAssertEqual(layout.totalContentHeight, 1515, accuracy: 1e-10)
        XCTAssertEqual(layout.allWindows.map(\.matchesSearch), [false, true, false, true, false])
        XCTAssertEqual(Set(layout.allWindows.map(\.handle.id)), Set(handles.map(\.id)))
        for window in layout.allWindows {
            XCTAssertTrue(handles.contains { window.handle === $0 })
        }
        let bounds = OverviewLayoutCalculator.scrollOffsetBounds(
            layout: layout,
            screenFrame: CGRect(x: -200, y: -100, width: 1000, height: 800)
        )
        XCTAssertEqual(bounds.lowerBound, -820, accuracy: 1e-10)
        XCTAssertEqual(bounds.upperBound, 0)
    }

    func testGenericRestAnchorInvertsProjectedFrames() throws {
        let (layout, _) = makeMixedLayout()
        let section = try XCTUnwrap(layout.workspaceSections.first)
        let anchor = try XCTUnwrap(OverviewRenderGeometry.restAnchor(for: section))

        for window in section.windows {
            assertFrame(
                OverviewRenderGeometry.restFrame(for: window.overviewFrame, anchor: anchor),
                window.originalFrame
            )
        }
    }

    func testMissingAndEmptyRestAnchorsClearPreviousProjection() throws {
        var (layout, _) = makeMixedLayout()
        let workspaceId = try XCTUnwrap(layout.workspaceSections.first?.workspaceId)
        layout.settleRestFrames(anchorWorkspaceId: workspaceId)
        XCTAssertTrue(layout.allWindows.contains { $0.restFrame != nil })

        for anchorId in [nil, WorkspaceDescriptor.ID()] {
            layout.settleRestFrames(anchorWorkspaceId: anchorId)
            XCTAssertTrue(layout.allWindows.allSatisfy { $0.restFrame == nil })
            XCTAssertTrue(layout.allWindows.allSatisfy { $0.interpolatedFrame(progress: 0) == $0.originalFrame })
        }
        var empty = try XCTUnwrap(layout.workspaceSections.first)
        empty.windows = []
        XCTAssertNotNil(OverviewRenderGeometry.restAnchor(for: empty))
        empty.visibleFrame = .zero
        XCTAssertNil(OverviewRenderGeometry.restAnchor(for: empty))
    }

    func testDegenerateRestAnchorUsesOriginalFrames() throws {
        var (layout, _) = makeMixedLayout()
        var section = try XCTUnwrap(layout.workspaceSections.first)
        let window = try XCTUnwrap(section.windows.first)
        section.windows = [OverviewWindowItem(
            handle: window.handle,
            windowId: window.windowId,
            workspaceId: window.workspaceId,
            title: window.title,
            appName: window.appName,
            appIcon: nil,
            originalFrame: .zero,
            overviewFrame: window.overviewFrame,
            matchesSearch: true
        )]
        section.visibleFrame = .zero
        layout.replaceWorkspaceSections([section] + layout.workspaceSections.dropFirst())
        layout.settleRestFrames(anchorWorkspaceId: section.workspaceId)

        XCTAssertNil(OverviewRenderGeometry.restAnchor(for: section))
        XCTAssertTrue(layout.allWindows.allSatisfy { $0.restFrame == nil })
    }
}

extension OverviewLayoutCalculatorTests {
    private func assertFrame(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }

    private func assertFrames(
        _ actual: [CGRect],
        _ expected: [CGRect],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (lhs, rhs) in zip(actual, expected) {
            assertFrame(lhs, rhs, file: file, line: line)
        }
    }

    private func makeMixedLayout() -> (OverviewLayout, [WindowHandle]) {
        let generic = WorkspaceDescriptor.ID()
        let dwindleWorkspace = WorkspaceDescriptor.ID()
        let handles = (1 ... 5).map { WindowHandle(id: WindowToken(pid: 7, windowId: $0)) }
        let frames = [
            CGRect(x: -640.25, y: 25.5, width: 300, height: 200),
            CGRect(x: -340.25, y: 25.5, width: 300, height: 200),
            CGRect(x: 0, y: 0, width: 200, height: 95),
            CGRect(x: 0, y: 0, width: 200, height: 95),
            CGRect(x: 0, y: 0, width: 100, height: 100)
        ]
        var windows: [WindowHandle: OverviewWindowLayoutData] = [:]
        for (index, handle) in handles.enumerated() {
            windows[handle] = OverviewWindowLayoutData(
                token: handle.id, workspaceId: index < 2 ? generic : dwindleWorkspace,
                title: index == 1 ? "TERMINAL" : "Window \(index)",
                appName: index == 2 ? "Terminal" : "Editor", appIcon: nil, frame: frames[index]
            )
        }
        let layout = OverviewLayoutCalculator(
            screenFrame: CGRect(x: -200, y: -100, width: 1000, height: 800),
            scale: 1.25
        ).calculateLayout(
            workspaces: [
                OverviewWorkspaceLayoutItem(id: generic, name: "Generic", isActive: true),
                OverviewWorkspaceLayoutItem(id: dwindleWorkspace, name: "Dwindle", isActive: false),
                OverviewWorkspaceLayoutItem(id: WorkspaceDescriptor.ID(), name: "Empty", isActive: false)
            ],
            windows: windows,
            searchQuery: "terminal"
        )
        return (layout, handles)
    }
}
