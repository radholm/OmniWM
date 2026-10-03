// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class OverviewNavigationTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1200, height: 900)

    func testGenericHorizontalNavigationUsesVisualRowsAcrossStackedGeometry() {
        let frameCases: [[[CGRect]]] = [
            [
                [
                    CGRect(x: 0, y: 500, width: 400, height: 100),
                    CGRect(x: 500, y: 500, width: 400, height: 100)
                ],
                [
                    CGRect(x: 0, y: 0, width: 400, height: 100),
                    CGRect(x: 500, y: 0, width: 400, height: 100)
                ]
            ],
            [
                [
                    CGRect(x: 0, y: 500, width: 400, height: 50),
                    CGRect(x: 500, y: 500, width: 400, height: 50)
                ],
                [
                    CGRect(x: 0, y: 0, width: 400, height: 300),
                    CGRect(x: 500, y: 0, width: 400, height: 300)
                ]
            ]
        ]

        for rowFrames in frameCases {
            let fixture = makeGenericFixture(rowFrames: rowFrames)
            for row in fixture.groups {
                assertHorizontalPair(
                    row[0],
                    row[1],
                    in: fixture.layout,
                    message: "row frames \(rowFrames)"
                )
            }
        }
    }

    func testHorizontalNavigationIgnoresSubpixelVerticalOverlap() {
        let fixture = makeGenericFixture(rowFrames: [
            [CGRect(x: 0, y: 0, width: 400, height: 100)],
            [CGRect(x: 500, y: 99.9, width: 400, height: 100)]
        ])
        let current = fixture.groups[0][0]

        XCTAssertEqual(
            OverviewNavigation.findNextWindow(
                in: fixture.layout,
                from: current,
                direction: .right
            ),
            current
        )
    }

    private func assertHorizontalPair(
        _ left: WindowHandle,
        _ right: WindowHandle,
        in layout: OverviewLayout,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            OverviewNavigation.findNextWindow(in: layout, from: left, direction: .right),
            right,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            OverviewNavigation.findNextWindow(in: layout, from: right, direction: .left),
            left,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            OverviewNavigation.findNextWindow(in: layout, from: left, direction: .left),
            left,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            OverviewNavigation.findNextWindow(in: layout, from: right, direction: .right),
            right,
            message,
            file: file,
            line: line
        )
    }

    private func makeGenericFixture(rowFrames: [[CGRect]]) -> NavigationFixture {
        let descriptor = WorkspaceDescriptor(name: "Generic Navigation")
        var windows: [WindowHandle: OverviewWindowLayoutData] = [:]
        var handlesByRow: [[WindowHandle]] = []

        for (rowIndex, frames) in rowFrames.enumerated() {
            var handles: [WindowHandle] = []
            for (columnIndex, frame) in frames.enumerated() {
                let ordinal = rowIndex * 100 + columnIndex + 1
                let token = WindowToken(pid: pid_t(90_000 + ordinal), windowId: 90_000 + ordinal)
                let handle = WindowHandle(id: token)
                windows[handle] = OverviewWindowLayoutData(
                    token: token,
                    workspaceId: descriptor.id,
                    title: "Row \(rowIndex) Column \(columnIndex)",
                    appName: "Navigation",
                    appIcon: nil,
                    frame: frame
                )
                handles.append(handle)
            }
            handlesByRow.append(handles)
        }

        let layout = OverviewLayoutCalculator(
            screenFrame: screenFrame,
            scale: 1
        ).calculateLayout(
            workspaces: [OverviewWorkspaceLayoutItem(id: descriptor.id, name: descriptor.name, isActive: true)],
            windows: windows,
            searchQuery: ""
        )
        return NavigationFixture(
            workspaceId: descriptor.id,
            layout: layout,
            groups: handlesByRow
        )
    }

    private struct NavigationFixture {
        let workspaceId: WorkspaceDescriptor.ID
        let layout: OverviewLayout
        let groups: [[WindowHandle]]
    }
}
