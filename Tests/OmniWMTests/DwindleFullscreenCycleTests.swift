// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class DwindleFullscreenCycleTests: XCTestCase {
    private let screen = CGRect(x: 8, y: 8, width: 1424, height: 854)
    private let first = WindowToken(pid: 1, windowId: 1)
    private let second = WindowToken(pid: 2, windowId: 2)
    private let third = WindowToken(pid: 3, windowId: 3)

    func testCyclePagesFullscreenThroughWindowsInLayoutOrderAndWraps() throws {
        let (engine, workspace) = makeEngine()
        let tiled = sync(engine, [first, second, third], in: workspace)
        let order = try layoutOrder(engine, in: workspace)
        XCTAssertEqual(Set(order), [first, second, third])
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), order[0])

        var cycle = try XCTUnwrap(engine.cycleFullscreen(in: workspace))
        XCTAssertEqual(cycle, .init(previous: order[0], next: order[1]))
        XCTAssertEqual(engine.fullscreenTokens(in: workspace), [order[1]])
        XCTAssertEqual(engine.selectedNode(in: workspace)?.tile?.activeToken, order[1])
        let frames = layout(engine, in: workspace)
        XCTAssertEqual(frames[order[1]], screen)
        XCTAssertEqual(frames[order[0]], tiled[order[0]])

        cycle = try XCTUnwrap(engine.cycleFullscreen(in: workspace))
        XCTAssertEqual(cycle, .init(previous: order[1], next: order[2]))
        cycle = try XCTUnwrap(engine.cycleFullscreen(in: workspace))
        XCTAssertEqual(cycle, .init(previous: order[2], next: order[0]))
        XCTAssertEqual(engine.fullscreenTokens(in: workspace), [order[0]])
    }

    func testCycleBackwardWraps() throws {
        let (engine, workspace) = makeEngine()
        _ = sync(engine, [first, second, third], in: workspace)
        let order = try layoutOrder(engine, in: workspace)
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), order[0])
        XCTAssertEqual(try XCTUnwrap(engine.cycleFullscreen(in: workspace, forward: false)).next, order[2])
    }

    func testLeavingFullscreenRestoresTiledLayout() throws {
        let (engine, workspace) = makeEngine()
        let tiled = sync(engine, [first, second, third], in: workspace)
        let order = try layoutOrder(engine, in: workspace)
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), order[0])
        _ = try XCTUnwrap(engine.cycleFullscreen(in: workspace))
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), order[1])
        XCTAssertTrue(engine.fullscreenTokens(in: workspace).isEmpty)
        XCTAssertEqual(layout(engine, in: workspace), tiled)
    }

    func testCycleNeedsAFullscreenWindowAndAnotherWindow() {
        let (engine, workspace) = makeEngine()
        _ = sync(engine, [first, second], in: workspace)
        XCTAssertNil(engine.cycleFullscreen(in: workspace))

        let (single, singleWorkspace) = makeEngine()
        _ = sync(single, [first], in: singleWorkspace)
        XCTAssertEqual(single.toggleFullscreen(in: singleWorkspace), first)
        XCTAssertNil(single.cycleFullscreen(in: singleWorkspace))
        XCTAssertEqual(single.fullscreenTokens(in: singleWorkspace), [first])
    }

    func testCycleSkipsWindowsThatCannotTakeFocus() throws {
        let (engine, workspace) = makeEngine()
        _ = sync(engine, [first, second, third], in: workspace)
        let order = try layoutOrder(engine, in: workspace)
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), order[0])
        let skipped = order[1]
        let cycle = try XCTUnwrap(engine.cycleFullscreen(in: workspace, canFocus: { $0 != skipped }))
        XCTAssertEqual(cycle.next, order[2])
    }

    func testSlideMovesPagingWindowsAcrossTheScreenAboveTheOthers() {
        let fullscreen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let tile = CGRect(x: 0, y: 0, width: 500, height: 800)
        let items: [WindowSnapshotTransition.Item] = [
            .init(windowId: 2, from: tile, to: fullscreen),
            .init(windowId: 3, from: tile, to: tile),
            .init(windowId: 1, from: fullscreen, to: tile)
        ]
        let slide = FullscreenSlide(
            workspaceId: WorkspaceDescriptor.ID(), previousWindowId: 1, nextWindowId: 2, forward: true, time: 0
        )
        let shown = slide.items(from: items)
        XCTAssertEqual(shown.map(\.windowId), [3, 1, 2])
        XCTAssertEqual(shown[1].from, fullscreen)
        XCTAssertEqual(shown[1].to, fullscreen.offsetBy(dx: -1000, dy: 0))
        XCTAssertEqual(shown[2].from, fullscreen.offsetBy(dx: 1000, dy: 0))
        XCTAssertEqual(shown[2].to, fullscreen)

        let backward = FullscreenSlide(
            workspaceId: WorkspaceDescriptor.ID(), previousWindowId: 1, nextWindowId: 2, forward: false, time: 0
        ).items(from: items)
        XCTAssertEqual(backward[2].from, fullscreen.offsetBy(dx: -1000, dy: 0))
    }

    private func makeEngine() -> (DwindleLayoutEngine, WorkspaceDescriptor.ID) {
        (DwindleLayoutEngine(), WorkspaceDescriptor.ID())
    }

    private func sync(
        _ engine: DwindleLayoutEngine,
        _ tokens: [WindowToken],
        in workspace: WorkspaceDescriptor.ID
    ) -> [WindowToken: CGRect] {
        for count in 1 ... tokens.count {
            _ = engine.syncWindows(
                Array(tokens.prefix(count)),
                in: workspace,
                focusedToken: first,
                bootstrapScreen: screen,
                bootstrapFullscreenScreen: screen
            )
        }
        return layout(engine, in: workspace)
    }

    private func layoutOrder(
        _ engine: DwindleLayoutEngine,
        in workspace: WorkspaceDescriptor.ID
    ) throws -> [WindowToken] {
        let order = try XCTUnwrap(engine.root(for: workspace)).collectAllWindows()
        XCTAssertEqual(order.first, engine.selectedNode(in: workspace)?.tile?.activeToken)
        return order
    }

    private func layout(_ engine: DwindleLayoutEngine, in workspace: WorkspaceDescriptor.ID) -> [WindowToken: CGRect] {
        engine.calculateLayout(for: workspace, screen: screen, fullscreenScreen: screen)
    }
}
