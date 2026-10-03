// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceBarDropResolutionTests: XCTestCase {
    private let ws1 = WorkspaceDescriptor.ID()
    private let ws2 = WorkspaceDescriptor.ID()
    private let dwindleWorkspace = WorkspaceDescriptor.ID()
    private let a = WindowToken(pid: 1, windowId: 1)
    private let b = WindowToken(pid: 1, windowId: 2)
    private let c = WindowToken(pid: 1, windowId: 3)
    private let x = WindowToken(pid: 2, windowId: 1)
    private let y = WindowToken(pid: 2, windowId: 2)

    private func icon(_ token: WindowToken, minX: CGFloat, name: String) -> WorkspaceBarDropGeometry.Icon {
        .init(tokens: [token], frame: CGRect(x: minX, y: 2, width: 20, height: 20), appName: name)
    }

    private var geometry: WorkspaceBarDropGeometry {
        .init(workspaces: [
            .init(
                id: ws1, name: "1", hitFrame: CGRect(x: 0, y: 0, width: 110, height: 24),
                icons: [icon(a, minX: 10, name: "A"), icon(b, minX: 40, name: "B"), icon(c, minX: 70, name: "C")]
            ),
            .init(
                id: ws2, name: "2", hitFrame: CGRect(x: 2000, y: 0, width: 80, height: 24), icons: []
            ),
            .init(
                id: dwindleWorkspace, name: "3", hitFrame: CGRect(x: 120, y: 0, width: 80, height: 24),
                icons: [icon(x, minX: 130, name: "X"), icon(y, minX: 160, name: "Y")]
            )
        ])
    }

    private func resolve(
        _ tokens: [WindowToken],
        from workspaceId: WorkspaceDescriptor.ID? = nil,
        floating: Bool = false,
        atX pointX: CGFloat
    ) -> WorkspaceBarDropResolution {
        WorkspaceBarDropResolver.resolve(
            source: .init(tokens: tokens, workspaceId: workspaceId ?? ws1, isFloating: floating),
            at: CGPoint(x: pointX, y: 12), in: geometry
        )
    }

    func testDwindleDropsSwapWithTheIconUnderThePointer() {
        let swap = resolve([x], from: dwindleWorkspace, atX: 170)
        XCTAssertEqual(swap.action, .dwindleSwap(dwindleWorkspace, target: y))
        XCTAssertEqual(swap.label, "Swap with Y")
        XCTAssertEqual(resolve([x], from: dwindleWorkspace, atX: 140).action, .noOp)
        XCTAssertEqual(resolve([x], from: dwindleWorkspace, atX: 155).action, .noOp)
    }

    func testDroppingOnAnotherWorkspaceMovesThere() {
        let other = resolve([a], atX: 2050)
        XCTAssertEqual(other.action, .moveToWorkspace(ws2))
        XCTAssertEqual(other.label, "Move to 2")
        XCTAssertEqual(other.highlights, [.workspace(ws2)])
        XCTAssertEqual(resolve([x, y], from: dwindleWorkspace, atX: 40).action, .moveToWorkspace(ws1))
        XCTAssertEqual(resolve([a], floating: true, atX: 150).action, .moveToWorkspace(dwindleWorkspace))
    }

    func testFloatingAndGroupedSourcesCannotBeReorderedInPlace() {
        XCTAssertEqual(resolve([a], floating: true, atX: 83).action, .noOp)
        XCTAssertEqual(resolve([b, c], atX: 83).action, .noOp)
    }

    func testGroupedTargetsCannotBeSwappedInPlace() {
        var workspaces = geometry.workspaces
        workspaces[0] = .init(
            id: ws1, name: "1", hitFrame: workspaces[0].hitFrame,
            icons: [.init(tokens: [b, c], frame: CGRect(x: 40, y: 2, width: 20, height: 20), appName: "Group")]
        )
        XCTAssertEqual(
            WorkspaceBarDropResolver.resolve(
                source: .init(tokens: [a], workspaceId: ws1, isFloating: false),
                at: CGPoint(x: 50, y: 12), in: .init(workspaces: workspaces)
            ).action,
            .noOp
        )
    }

    func testVerticalDropZonesMatchHorizontalOrderingAcrossWorkspaces() {
        let transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: -500, ty: 2400)
        let vertical = WorkspaceBarDropGeometry(workspaces: geometry.workspaces.map { workspace in
            .init(
                id: workspace.id, name: workspace.name, hitFrame: workspace.hitFrame.applying(transform),
                icons: workspace.icons.map {
                    .init(tokens: $0.tokens, frame: $0.frame.applying(transform), appName: $0.appName)
                }, orientation: .vertical
            )
        })
        let source = WorkspaceBarDragSource(tokens: [a], workspaceId: ws1, isFloating: false)
        for x in [41, 49, 56, 83, 2018, 2026, 2043] {
            let point = CGPoint(x: x, y: 12)
            XCTAssertEqual(
                WorkspaceBarDropResolver.resolve(source: source, at: point.applying(transform), in: vertical),
                WorkspaceBarDropResolver.resolve(source: source, at: point, in: geometry), "x=\(x)"
            )
        }
    }

    func testDropsOutsideEveryWorkspaceCancel() {
        let result = resolve([a], atX: 500)
        XCTAssertEqual(result.action, .cancel)
        XCTAssertEqual(result.label, "Can’t drop here")
        XCTAssertTrue(result.highlights.isEmpty)
    }
}
