// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import QuartzCore
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
        XCTAssertEqual(cycle, .init(previous: order[0], next: order[1], deck: [order[1], order[2], order[0]]))
        XCTAssertEqual(engine.fullscreenTokens(in: workspace), [order[1]])
        XCTAssertEqual(engine.selectedNode(in: workspace)?.tile?.activeToken, order[1])
        XCTAssertNotEqual(tiled[order[0]], screen)
        XCTAssertEqual(Set(layout(engine, in: workspace).values), [screen], "windows stack under the fullscreen one")

        cycle = try XCTUnwrap(engine.cycleFullscreen(in: workspace))
        XCTAssertEqual(cycle, .init(previous: order[1], next: order[2], deck: [order[2], order[0], order[1]]))
        cycle = try XCTUnwrap(engine.cycleFullscreen(in: workspace))
        XCTAssertEqual(cycle, .init(previous: order[2], next: order[0], deck: [order[0], order[1], order[2]]))
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

    func testActivatingAStackedWindowMakesItFullscreen() throws {
        let (engine, workspace) = makeEngine()
        _ = sync(engine, [first, second, third], in: workspace)
        let order = try layoutOrder(engine, in: workspace)
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), order[0])
        XCTAssertEqual(engine.moveFullscreen(to: order[2], in: workspace), order[0])
        XCTAssertEqual(engine.fullscreenTokens(in: workspace), [order[2]])
        XCTAssertNil(engine.moveFullscreen(to: order[2], in: workspace))

        let (tiledEngine, tiledWorkspace) = makeEngine()
        _ = sync(tiledEngine, [first, second], in: tiledWorkspace)
        XCTAssertNil(tiledEngine.moveFullscreen(to: second, in: tiledWorkspace))
        XCTAssertTrue(tiledEngine.fullscreenTokens(in: tiledWorkspace).isEmpty)
    }

    func testPageTurnRotatesTheDeck() {
        let fullscreen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let floating = CGRect(x: 10, y: 10, width: 200, height: 100)
        let items: [WindowSnapshotTransition.Item] = [
            .init(windowId: 9, from: floating, to: floating),
            .init(windowId: 3, from: fullscreen, to: fullscreen),
            .init(windowId: 2, from: fullscreen, to: fullscreen),
            .init(windowId: 1, from: fullscreen, to: fullscreen)
        ]
        let slide = FullscreenSlide(
            workspaceId: WorkspaceDescriptor.ID(), previousWindowId: 1, nextWindowId: 2,
            deckWindowIds: [2, 3, 1], forward: true, time: 0
        )
        let shown = slide.items(from: items)
        XCTAssertEqual(shown.map(\.windowId), [9, 1, 3, 2])
        XCTAssertNil(shown[0].stackEffect)
        XCTAssertEqual(
            shown[1].stackEffect,
            SnapshotStackEffect(fromDepth: 0, toDepth: 2, deckSize: 3, tucksUnder: true)
        )
        XCTAssertEqual(shown[2].stackEffect, SnapshotStackEffect(fromDepth: 2, toDepth: 1, deckSize: 3))
        XCTAssertEqual(shown[3].stackEffect, SnapshotStackEffect(fromDepth: 1, toDepth: 0, deckSize: 3))
        XCTAssertTrue(shown.dropFirst().allSatisfy { $0.from == fullscreen && $0.to == fullscreen })
    }

    func testDeckFansTowardsTheBottomRightAndPageTurnZoomsOutAndIn() {
        let size = CGSize(width: 1000, height: 800)
        let front = SnapshotStackEffect.deckPose(slot: 0, count: 3, size: size)
        let back = SnapshotStackEffect.deckPose(slot: 2, count: 3, size: size)
        XCTAssertGreaterThan(back.m41, front.m41, "cards further back sit further right")
        XCTAssertLessThan(back.m42, front.m42, "and lower")
        XCTAssertGreaterThan(SnapshotStackEffect.zPosition(depth: 0), SnapshotStackEffect.zPosition(depth: 1))
        XCTAssertGreaterThan(SnapshotStackEffect.zPosition(depth: SnapshotStackEffect.maximumDeckSize), size.width)
        XCTAssertGreaterThan(SnapshotStackEffect.tuckZPosition, SnapshotStackEffect.zPosition(depth: 0))

        let leaving = SnapshotStackEffect(fromDepth: 0, toDepth: 2, deckSize: 3, tucksUnder: true)
        let (values, times) = leaving.keyframes(size: size)
        XCTAssertTrue(CATransform3DIsIdentity(values[0]), "starts at full size")
        XCTAssertTrue(CATransform3DIsIdentity(values[values.count - 1]), "and ends at full size")
        XCTAssertEqual(times.first, 0)
        XCTAssertEqual(times.last, 1)
        XCTAssertEqual(times, times.sorted())
        let lowest = values.min { $0.m42 < $1.m42 }
        XCTAssertLessThan(lowest?.m42 ?? 0, back.m42, "it dips below the deck on its way to the back")

        let next = SnapshotStackEffect(fromDepth: 1, toDepth: 0, deckSize: 3).keyframes(size: size)
        XCTAssertEqual(next.values.count, 4, "zoom out, move up one place, zoom in")
        XCTAssertTrue(CATransform3DIsIdentity(next.values[3]))
    }

    func testDeckStaysNearFullSizeWithShallowTiltAndCompactSpacing() {
        let size = CGSize(width: 1000, height: 800)
        let middle = SnapshotStackEffect.deckPose(slot: 1, count: 3, size: size)
        XCTAssertEqual(middle.m22, 0.94, accuracy: 0.0001)
        XCTAssertEqual(middle.m11, 0.94 * cos(.pi / 144), accuracy: 0.0001)
        XCTAssertEqual(abs(middle.m13), 0.94 * sin(.pi / 144), accuracy: 0.0001)

        let front = SnapshotStackEffect.deckPose(slot: 0, count: 3, size: size)
        let back = SnapshotStackEffect.deckPose(slot: 2, count: 3, size: size)
        XCTAssertEqual(back.m41 - front.m41, 80, accuracy: 0.0001)
        XCTAssertEqual(back.m42 - front.m42, -56, accuracy: 0.0001)
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
