// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class CrossDisplayDragTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let controller: WMController
        let dwindle: DwindleLayoutEngine
        let monitors: [Monitor]
        let workspaces: [WorkspaceDescriptor.ID]

        var manager: WorkspaceManager {
            controller.workspaceManager
        }

        var handler: MouseEventHandler {
            controller.mouseEventHandler
        }

        var source: WorkspaceDescriptor.ID {
            workspaces[0]
        }

        var target: WorkspaceDescriptor.ID {
            workspaces[1]
        }

        func dwindleTile(_ token: WindowToken) -> [WindowToken]? {
            manager.workspace(for: token)
                .flatMap { dwindle.tile(containing: token, in: $0) }?
                .members.map(\.token)
        }

        func frame(_ token: WindowToken) -> CGRect? {
            guard let workspaceId = manager.workspace(for: token) else { return nil }
            return dwindle.presentedFrame(for: token, in: workspaceId, at: 0)
        }

        func layout() {
            for (monitor, workspaceId) in zip(monitors, workspaces) {
                let workingFrame = controller.insetWorkingFrame(for: monitor)
                _ = dwindle.calculateLayout(for: workspaceId, screen: workingFrame)
                dwindle.cancelAnimations(in: workspaceId)
            }
        }

        func beginDrag(_ token: WindowToken) throws {
            layout()
            let start = try XCTUnwrap(frame(token)).center
            XCTAssertFalse(handler.dispatchMouseDown(at: start, modifiers: .maskControl))
            XCTAssertTrue(handler.state.isMoving)
        }

        func finishDrag(at point: CGPoint) {
            handler.dispatchMouseDragged(at: point)
            handler.dispatchMouseUp(at: point)
            XCTAssertFalse(handler.state.isMoving)
            XCTAssertNil(dwindle.interactiveMove)
        }

        func drag(_ token: WindowToken, to point: CGPoint) throws {
            try beginDrag(token)
            finishDrag(at: point)
        }
    }

    func testDropIntoAnEmptyWorkspaceOnTheOtherDisplay() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let stays = addWindow(2, to: fixture.source, fixture)

        try fixture.drag(moved, to: fixture.monitors[1].frame.center)

        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
        XCTAssertEqual(fixture.dwindleTile(stays), [stays])
        XCTAssertEqual(fixture.dwindleTile(moved), [moved])
        XCTAssertTrue(fixture.dwindle.root(for: fixture.target)?.isLeaf == true)
    }

    func testDwindleTileZonesInsertBesideTheTargetInEveryDirection() throws {
        for direction in [Direction.left, .right, .up, .down] {
            let fixture = try makeFixture([.dwindle, .dwindle])
            let moved = addWindow(1, to: fixture.source, fixture)
            let target = addWindow(2, to: fixture.target, fixture)
            let other = addWindow(3, to: fixture.target, fixture)
            fixture.layout()
            let targetSlot = try XCTUnwrap(fixture.frame(target))
            let otherFrame = try XCTUnwrap(fixture.frame(other))

            try fixture.drag(moved, to: dropPoint(in: targetSlot, direction))
            fixture.layout()

            let movedFrame = try XCTUnwrap(fixture.frame(moved))
            let targetFrame = try XCTUnwrap(fixture.frame(target))
            XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target, "\(direction)")
            XCTAssertTrue(targetSlot.insetBy(dx: -1, dy: -1).contains(movedFrame), "\(direction)")
            XCTAssertTrue(targetSlot.insetBy(dx: -1, dy: -1).contains(targetFrame), "\(direction)")
            XCTAssertEqual(fixture.frame(other), otherFrame, "\(direction)")
            switch direction {
            case .left: XCTAssertLessThan(movedFrame.maxX, targetFrame.minX + 1)
            case .right: XCTAssertGreaterThan(movedFrame.minX, targetFrame.maxX - 1)
            case .up: XCTAssertGreaterThan(movedFrame.minY, targetFrame.maxY - 1)
            case .down: XCTAssertLessThan(movedFrame.maxY, targetFrame.minY + 1)
            }
        }
    }

    func testDwindleWorkspaceEdgeSplitsTheWholeTargetTree() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let first = addWindow(2, to: fixture.target, fixture)
        let second = addWindow(3, to: fixture.target, fixture)
        fixture.layout()
        let workingFrame = fixture.controller.insetWorkingFrame(for: fixture.monitors[1])

        try fixture.drag(moved, to: CGPoint(x: workingFrame.midX, y: workingFrame.maxY - 2))
        fixture.layout()

        let movedFrame = try XCTUnwrap(fixture.frame(moved))
        for resident in [first, second] {
            XCTAssertGreaterThan(movedFrame.minY, try XCTUnwrap(fixture.frame(resident)).maxY - 1)
        }
        XCTAssertEqual(movedFrame.width, workingFrame.width, accuracy: 1)
    }

    func testDwindleDividerInsertsBetweenTheTargetSubtrees() throws {
        for sourceLayout in [LayoutType.dwindle] {
            let fixture = try makeFixture([sourceLayout, .dwindle])
            let moved = addWindow(1, to: fixture.source, fixture)
            let left = addWindow(2, to: fixture.target, fixture)
            let stacked = [addWindow(3, to: fixture.target, fixture), addWindow(4, to: fixture.target, fixture)]
            fixture.layout()
            let root = try XCTUnwrap(fixture.dwindle.root(for: fixture.target))
            let leftFrame = try XCTUnwrap(fixture.frame(left))
            let stackedFrames = try stacked.map { try XCTUnwrap(fixture.frame($0)) }
            let right = stackedFrames.reduce(CGRect.null) { $0.union($1) }
            let point = CGPoint(x: (leftFrame.maxX + right.minX) / 2, y: leftFrame.midY)
            try fixture.beginDrag(moved)

            fixture.handler.dispatchMouseDragged(at: point)
            guard case let .crossDisplay(drop) = fixture.handler.classifyMoveLocation(point) else {
                return XCTFail("expected a cross-display drop from \(sourceLayout)")
            }
            XCTAssertEqual(drop.placement, .dwindleSplitBoundary(root.id), "\(sourceLayout)")
            XCTAssertEqual(drop.previewFrame, WindowMoveGeometry.targetFrame(in: right, direction: .left))
            fixture.finishDrag(at: point)
            fixture.layout()

            let movedFrame = try XCTUnwrap(fixture.frame(moved))
            XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target, "\(sourceLayout)")
            XCTAssertEqual(fixture.frame(left), leftFrame, "\(sourceLayout)")
            XCTAssertGreaterThan(movedFrame.minX, leftFrame.maxX, "\(sourceLayout)")
            XCTAssertEqual(movedFrame.minY, right.minY, accuracy: 1, "\(sourceLayout)")
            XCTAssertEqual(movedFrame.height, right.height, accuracy: 1, "\(sourceLayout)")
            for (token, before) in zip(stacked, stackedFrames) {
                let frame = try XCTUnwrap(fixture.frame(token))
                XCTAssertGreaterThan(frame.minX, movedFrame.maxX, "\(sourceLayout)")
                XCTAssertEqual(frame.height, before.height, accuracy: 1, "\(sourceLayout)")
            }
        }
    }

    func testDwindleSwapTradesSingleTiles() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let sourceSibling = addWindow(2, to: fixture.source, fixture)
        let partner = addWindow(3, to: fixture.target, fixture)
        let partnerSibling = addWindow(4, to: fixture.target, fixture)
        fixture.layout()
        let movedSlot = try XCTUnwrap(fixture.frame(moved))
        let partnerSlot = try XCTUnwrap(fixture.frame(partner))

        try fixture.drag(moved, to: partnerSlot.center)
        fixture.layout()

        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
        XCTAssertEqual(fixture.manager.workspace(for: partner), fixture.source)
        XCTAssertEqual(fixture.frame(moved), partnerSlot)
        XCTAssertEqual(fixture.frame(partner), movedSlot)
        XCTAssertEqual(fixture.dwindleTile(sourceSibling), [sourceSibling])
        XCTAssertEqual(fixture.dwindleTile(partnerSibling), [partnerSibling])
    }

    func testWindowModeSwapIntoAGroupedMemberKeepsTheGroup() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        fixture.controller.settings.gestures.dwindleGroupDragAcrossDisplays = .window
        let moved = addWindow(1, to: fixture.source, fixture)
        let member = addWindow(2, to: fixture.target, fixture)
        let partner = addWindow(3, to: fixture.target, fixture)
        fixture.manager.withEngineMutationScope(in: fixture.target) {
            XCTAssertTrue(fixture.dwindle.groupWindow(partner, into: member, in: fixture.target))
        }
        XCTAssertEqual(fixture.dwindleTile(member), [member, partner])
        fixture.layout()
        let groupFrame = try XCTUnwrap(fixture.frame(partner))
        XCTAssertEqual(
            fixture.dwindle.hitTestFocusableWindow(point: groupFrame.center, in: fixture.target, at: 0),
            partner
        )

        try fixture.drag(moved, to: groupFrame.center)

        XCTAssertEqual(fixture.dwindleTile(moved), [member, moved])
        XCTAssertEqual(fixture.dwindleTile(partner), [partner])
        XCTAssertEqual(fixture.manager.workspace(for: partner), fixture.source)
        XCTAssertEqual(fixture.dwindle.tile(containing: moved, in: fixture.target)?.activeToken, moved)
    }

    func testFullscreenTargetCancelsTheDropAndClearsThePreview() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let resident = addWindow(2, to: fixture.target, fixture)
        fixture.manager.withEngineMutationScope(in: fixture.target) {
            XCTAssertEqual(fixture.dwindle.toggleFullscreen(in: fixture.target), resident)
        }
        let point = fixture.monitors[1].frame.center
        try fixture.beginDrag(moved)
        let worldSeq = fixture.manager.worldSeq

        fixture.handler.dispatchMouseDragged(at: point)
        XCTAssertEqual(fixture.handler.classifyMoveLocation(point), .cancel)
        fixture.handler.dispatchMouseUp(at: point)

        XCTAssertEqual(fixture.manager.worldSeq, worldSeq)
        XCTAssertEqual(fixture.dwindleTile(moved), [moved])
        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.source)
    }

    func testGroupMovesKeepTheTileOrderAndActiveMember() throws {
        for drop in ["beside", "edge", "workspace"] {
            let fixture = try makeFixture([.dwindle, .dwindle])
            let first = addWindow(1, to: fixture.source, fixture)
            let second = addWindow(2, to: fixture.source, fixture)
            let stays = addWindow(3, to: fixture.source, fixture)
            group(second, into: first, in: fixture.source, fixture)
            let resident = drop == "workspace" ? nil : addWindow(4, to: fixture.target, fixture)
            fixture.layout()
            let workingFrame = fixture.controller.insetWorkingFrame(for: fixture.monitors[1])
            let point = switch drop {
            case "beside": try dropPoint(in: XCTUnwrap(fixture.frame(XCTUnwrap(resident))), .right)
            case "edge": CGPoint(x: workingFrame.midX, y: workingFrame.maxY - 2)
            default: workingFrame.center
            }

            try fixture.drag(second, to: point)

            XCTAssertEqual(fixture.dwindleTile(first), [first, second], drop)
            XCTAssertEqual(fixture.dwindle.tile(containing: first, in: fixture.target)?.activeToken, second, drop)
            XCTAssertEqual(fixture.manager.workspace(for: first), fixture.target, drop)
            XCTAssertEqual(fixture.manager.workspace(for: second), fixture.target, drop)
            XCTAssertEqual(fixture.dwindleTile(stays), [stays], drop)
            XCTAssertEqual(fixture.dwindle.tileCount(in: fixture.source), 1, drop)
            XCTAssertEqual(fixture.dwindle.tileCount(in: fixture.target), resident == nil ? 1 : 2, drop)
        }
    }

    func testWindowModeMovesOnlyTheDraggedMember() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        fixture.controller.settings.gestures.dwindleGroupDragAcrossDisplays = .window
        let first = addWindow(1, to: fixture.source, fixture)
        let second = addWindow(2, to: fixture.source, fixture)
        group(second, into: first, in: fixture.source, fixture)

        try fixture.drag(second, to: fixture.monitors[1].frame.center)

        XCTAssertEqual(fixture.dwindleTile(second), [second])
        XCTAssertEqual(fixture.dwindleTile(first), [first])
        XCTAssertEqual(fixture.manager.workspace(for: first), fixture.source)
        XCTAssertEqual(fixture.manager.workspace(for: second), fixture.target)
    }

    func testGroupSwapsIntoWholeSlots() throws {
        let dwindleFixture = try makeFixture([.dwindle, .dwindle])
        let movedFirst = addWindow(1, to: dwindleFixture.source, dwindleFixture)
        let movedSecond = addWindow(2, to: dwindleFixture.source, dwindleFixture)
        _ = addWindow(3, to: dwindleFixture.source, dwindleFixture)
        group(movedSecond, into: movedFirst, in: dwindleFixture.source, dwindleFixture)
        let partnerFirst = addWindow(4, to: dwindleFixture.target, dwindleFixture)
        let partnerSecond = addWindow(5, to: dwindleFixture.target, dwindleFixture)
        _ = addWindow(6, to: dwindleFixture.target, dwindleFixture)
        group(partnerSecond, into: partnerFirst, in: dwindleFixture.target, dwindleFixture)
        dwindleFixture.layout()
        let movedSlot = try XCTUnwrap(dwindleFixture.frame(movedSecond))
        let partnerSlot = try XCTUnwrap(dwindleFixture.frame(partnerSecond))

        try dwindleFixture.drag(movedSecond, to: partnerSlot.center)
        dwindleFixture.layout()

        XCTAssertEqual(dwindleFixture.dwindleTile(movedFirst), [movedFirst, movedSecond])
        XCTAssertEqual(dwindleFixture.dwindleTile(partnerFirst), [partnerFirst, partnerSecond])
        XCTAssertEqual(dwindleFixture.manager.workspace(for: movedFirst), dwindleFixture.target)
        XCTAssertEqual(dwindleFixture.manager.workspace(for: partnerFirst), dwindleFixture.source)
        XCTAssertEqual(dwindleFixture.frame(movedSecond), partnerSlot)
        XCTAssertEqual(dwindleFixture.frame(partnerSecond), movedSlot)
    }

    func testExcludedGroupMembersTravelWithTheirExclusion() throws {
        for targetLayout in [LayoutType.dwindle] {
            let fixture = try makeFixture([.dwindle, targetLayout])
            let hidden = addWindow(1, to: fixture.source, pid: 8_661, fixture)
            let visible = addWindow(2, to: fixture.source, fixture)
            group(visible, into: hidden, in: fixture.source, fixture)
            fixture.manager.setAppHidden(true, pid: 8_661, source: .ax)
            XCTAssertTrue(fixture.dwindle.excludedTokens(in: fixture.source).contains(hidden))

            try fixture.drag(visible, to: fixture.monitors[1].frame.center)

            XCTAssertEqual(fixture.manager.workspace(for: hidden), fixture.target, "\(targetLayout)")
            XCTAssertFalse(fixture.dwindle.excludedTokens(in: fixture.source).contains(hidden), "\(targetLayout)")
            XCTAssertEqual(fixture.dwindleTile(visible), [hidden, visible])
            XCTAssertTrue(fixture.dwindle.excludedTokens(in: fixture.target).contains(hidden))
        }
    }

    private func makeFixture(_ layouts: [LayoutType]) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrossDisplayDragTests-\(UUID().uuidString)", isDirectory: true)
        let monitors = layouts.indices.map { index in
            let displayId = CGDirectDisplayID(720_000 + index)
            let frame = CGRect(x: CGFloat(index) * 1600, y: 0, width: 1600, height: 900)
            return Monitor(
                id: .init(displayId: displayId), displayId: displayId,
                frame: frame, visibleFrame: frame, hasNotch: false, name: "Display \(index + 1)"
            )
        }
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        settings.animationsEnabled = false
        settings.gestures.mouseMoveModifierKey = .control
        settings.workspaces.configurations = zip(monitors, layouts).enumerated().map { index, pair in
            WorkspaceConfiguration(
                name: "\(index + 1)",
                monitorAssignment: .specificDisplay(OutputId(from: pair.0)),
                layoutType: pair.1
            )
        }
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        let manager = controller.workspaceManager
        manager.applyMonitorConfigurationChange(monitors)
        manager.applySettings()
        let dwindle = DwindleLayoutEngine()
        dwindle.animationClock = controller.animationClock
        controller.dwindleEngine = dwindle
        let workspaces = try layouts.indices.map { try XCTUnwrap(manager.workspaceId(named: "\($0 + 1)")) }
        for index in workspaces.indices.reversed() {
            XCTAssertTrue(manager.setActiveWorkspace(
                workspaces[index], on: monitors[index].id, updateInteractionMonitor: index == 0
            ))
        }
        controller.layoutRefreshController.resetState()
        controller.mouseEventHandler.pressedMouseButtonsProvider = { 1 }
        return Fixture(
            controller: controller,
            dwindle: dwindle,
            monitors: monitors,
            workspaces: workspaces
        )
    }

    private func addWindow(
        _ windowId: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        pid: pid_t = 8_660,
        _ fixture: Fixture
    ) -> WindowToken {
        let manager = fixture.manager
        let token = manager.addWindow(
            WindowAdmissionTestSupport.axRef(for: WindowToken(pid: pid, windowId: windowId)),
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
        manager.withEngineMutationScope(in: workspaceId) {
            _ = fixture.dwindle.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        }
        return token
    }

    private func group(
        _ token: WindowToken,
        into target: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        _ fixture: Fixture
    ) {
        fixture.manager.withEngineMutationScope(in: workspaceId) {
            XCTAssertTrue(fixture.dwindle.groupWindow(token, into: target, in: workspaceId))
        }
    }

    private func dropPoint(in frame: CGRect, _ direction: Direction) -> CGPoint {
        switch direction {
        case .left: CGPoint(x: frame.minX + frame.width * 0.1, y: frame.midY)
        case .right: CGPoint(x: frame.maxX - frame.width * 0.1, y: frame.midY)
        case .up: CGPoint(x: frame.midX, y: frame.maxY - frame.height * 0.1)
        case .down: CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.1)
        }
    }

    private func constraints(minWidth: CGFloat = 0, minHeight: CGFloat) -> WindowSizeConstraints {
        WindowSizeConstraints(minSize: CGSize(width: minWidth, height: minHeight), maxSize: .zero, isFixed: false)
    }
}
