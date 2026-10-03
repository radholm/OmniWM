// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import OmniWMIPC
import QuartzCore
import XCTest

@MainActor
final class OverviewStructuralCommandTests: XCTestCase {
    func testEmptiedDynamicWorkspaceSurvivesOverviewUntilClose() async throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let configuredId = fixture.workspaceIds[0]
        defer {
            controller.windowActionHandler.invalidateOverviewDeferredActionsForServiceStop()
        }
        let dynamicId = try await emptyDynamicWorkspaceInOverview(fixture)

        controller.motionPolicy.animationsEnabled = true
        controller.windowActionHandler.dismissOverview()
        guard case .closing = controller.windowActionHandler.overviewState else {
            return XCTFail("Expected Overview to retain its closing presentation")
        }
        controller.layoutRefreshController.collectUnusedWorkspacesIfIdle()
        XCTAssertNotNil(manager.descriptor(for: dynamicId))

        controller.windowActionHandler.invalidateOverviewDeferredActionsForServiceStop()

        XCTAssertFalse(controller.isOverviewOpen())
        while let task = controller.layoutRefreshController.layoutState.activeRefreshTask { await task.value }
        XCTAssertNil(manager.descriptor(for: dynamicId))
        XCTAssertNotNil(manager.descriptor(for: configuredId))
    }

    func testEmptiedDynamicWorkspaceIsCollectedWhenOverviewClosesWithoutRefresh() async throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let configuredId = fixture.workspaceIds[0]
        defer {
            controller.windowActionHandler.invalidateOverviewDeferredActionsForServiceStop()
        }
        let dynamicId = try await emptyDynamicWorkspaceInOverview(fixture)
        let refresh = controller.layoutRefreshController
        XCTAssertNil(refresh.layoutState.activeRefreshTask)
        XCTAssertNil(refresh.layoutState.activeRefresh)
        XCTAssertNil(refresh.layoutState.pendingRefresh)

        controller.windowActionHandler.invalidateOverviewDeferredActionsForServiceStop()

        XCTAssertFalse(controller.isOverviewOpen())
        XCTAssertNil(refresh.layoutState.activeRefreshTask)
        XCTAssertNil(refresh.layoutState.activeRefresh)
        XCTAssertNil(refresh.layoutState.pendingRefresh)
        XCTAssertNil(manager.descriptor(for: dynamicId))
        XCTAssertNotNil(manager.descriptor(for: configuredId))
    }

    func testOverviewGuardExemptsOnlyToggleOverview() {
        XCTAssertFalse(CommandHandler.shouldIgnoreCommand(.presentation(.overview), isOverviewOpen: true))
    }

    func testNativeFullscreenWindowsGetCardsButRefuseDragAndStructuralMutation() throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        let workspaceId = fixture.workspaceIds[0]
        let fullscreen = try addManagedWindow(pid: 461_040, windowId: 40, to: workspaceId, fixture: fixture)
        _ = try addManagedWindow(pid: 461_040, windowId: 41, to: workspaceId, fixture: fixture)
        let workspaceManager = fixture.controller.workspaceManager
        XCTAssertTrue(workspaceManager.markNativeFullscreenSuspended(fullscreen.id, ownsNativeFocus: false))
        XCTAssertEqual(workspaceManager.nativeFullscreenRecord(for: fullscreen.id)?.transition, .suspended)
        let entry = try XCTUnwrap(workspaceManager.entry(for: fullscreen))

        var environment = OverviewEnvironment()
        environment.windowTitle = { "Window \($0.windowId)" }
        environment.windowFrame = { _ in CGRect(x: 0, y: 0, width: 400, height: 300) }
        let facts = OverviewWindowFacts(wmController: fixture.controller, environment: environment)
        XCTAssertTrue(facts.isOverviewEligible(entry, workspaceManager: workspaceManager))
        XCTAssertFalse(facts.isStructurallyMutable(entry))
        XCTAssertTrue(
            facts.makeOverviewWindowData(for: entry, preferredFrame: nil, appInfoCache: fixture.controller.appInfoCache)
                .isNativeFullscreen
        )

        let overview = OverviewController(
            wmController: fixture.controller,
            motionPolicy: fixture.controller.motionPolicy,
            environment: environment
        )
        overview.prepareOpenState()
        overview.onAnimationComplete(state: .open)
        overview.drag.beginDrag(on: fixture.monitor.id, handle: fullscreen, startPoint: .zero)
        XCTAssertFalse(overview.hasActiveDragSession)
        XCTAssertEqual(
            overview.performStructuralHotkey(.workspace(.moveTo(1)), selectedHandle: fullscreen),
            .unchanged
        )
        XCTAssertEqual(workspaceManager.workspace(for: fullscreen.id), workspaceId)
    }

    func testNativeFullscreenSnapshotIncludesCardWithFullScreenCaption() throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        let fullscreen = try addManagedWindow(
            pid: 461_041, windowId: 42, to: fixture.workspaceIds[0], fixture: fixture
        )
        let manager = fixture.controller.workspaceManager
        XCTAssertTrue(manager.markNativeFullscreenSuspended(fullscreen.id, ownsNativeFocus: false))
        var environment = OverviewEnvironment()
        environment.windowTitle = { _ in "Fullscreen Document" }
        environment.windowFrame = { _ in CGRect(x: 100, y: 100, width: 600, height: 500) }
        let facts = OverviewWindowFacts(wmController: fixture.controller, environment: environment)
        let snapshot = OverviewSnapshot(wmController: fixture.controller, facts: facts)
        snapshot.build()
        let projection = OverviewViewportProjection(wmController: fixture.controller, snapshot: snapshot, scale: 1)
        projection.rebuildProjectedLayouts()
        let layout = try XCTUnwrap(projection.layoutsByMonitor[fixture.monitor.id])
        let card = try XCTUnwrap(layout.window(for: fullscreen))
        XCTAssertTrue(card.isNativeFullscreen)
        XCTAssertEqual(card.workspaceId, fixture.workspaceIds[0])
        let layer = OverviewWindowLayer()
        layer.updateContent(card, contentsScale: 2)
        let captions = (layer.root.sublayers ?? []).flatMap { $0.sublayers ?? [] }
            .compactMap { ($0 as? CATextLayer)?.string as? String }
        XCTAssertTrue(captions.contains("Full Screen"))
        XCTAssertTrue(captions.contains("Fullscreen Document"))
    }

    func testOverviewActivationUsesNativeFullscreenOwner() async throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        let fullscreen = try addManagedWindow(
            pid: 461_042, windowId: 43, to: fixture.workspaceIds[0], fixture: fixture
        )
        let manager = fixture.controller.workspaceManager
        XCTAssertTrue(manager.markNativeFullscreenSuspended(fullscreen.id, ownsNativeFocus: false))
        let focused = expectation(description: "Overview fronts the native fullscreen window")
        fixture.focusRecorder.onFocus = { focused.fulfill() }
        fixture.controller.toggleOverview()
        XCTAssertTrue(fixture.controller.isOverviewOpen())

        fixture.controller.windowActionHandler.dismissOverview()

        XCTAssertFalse(fixture.controller.isOverviewOpen())
        await fulfillment(of: [focused], timeout: 1)
        XCTAssertEqual(fixture.focusRecorder.activatedPIDs, [fullscreen.pid])
        XCTAssertEqual(fixture.focusRecorder.focusedTokens, [fullscreen.id])
        XCTAssertEqual(fixture.focusRecorder.raisedCount, 1)
        XCTAssertEqual(manager.nativeFullscreenRecord(for: fullscreen.id)?.transition, .suspended)
        XCTAssertEqual(manager.layoutReason(for: fullscreen.id), .nativeFullscreen)
        XCTAssertEqual(manager.selectedManagedToken, fullscreen.id)
        while let task = fixture.controller.layoutRefreshController.layoutState.activeRefreshTask { await task.value }
    }

    func testPerformCommandToggleOverviewClosesOpenOverview() throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        _ = try addManagedWindow(pid: 461_030, windowId: 30, to: fixture.workspaceIds[0], fixture: fixture)
        fixture.controller.toggleOverview()
        defer {
            if fixture.controller.isOverviewOpen() {
                fixture.controller.toggleOverview()
            }
        }
        XCTAssertTrue(fixture.controller.isOverviewOpen())
        XCTAssertEqual(fixture.controller.commandHandler.performCommand(.presentation(.overview)), .executed)
        XCTAssertFalse(fixture.controller.isOverviewOpen())

        let router = IPCCommandRouter(controller: fixture.controller, sessionToken: "test")
        XCTAssertEqual(router.handle(IPCCommandRequest.presentation(.overview)), .executed)
        XCTAssertTrue(fixture.controller.isOverviewOpen())
        XCTAssertEqual(router.handle(IPCCommandRequest.presentation(.overview)), .executed)
        XCTAssertFalse(fixture.controller.isOverviewOpen())
    }

    private final class FocusRecorder {
        var activatedPIDs: [pid_t] = []
        var focusedTokens: [WindowToken] = []
        var raisedCount = 0
        var onFocus: (() -> Void)?

        var callCount: Int {
            activatedPIDs.count + focusedTokens.count + raisedCount
        }
    }

    private struct Fixture {
        let controller: WMController
        let workspaceIds: [WorkspaceDescriptor.ID]
        let monitor: Monitor
        let focusRecorder: FocusRecorder
    }

    func testCoalescedStructuralActionsRefreshUnionOfAffectedWorkspacesOnce() async throws {
        let fixture = try makeFixture(layouts: [.dwindle, .dwindle])
        let firstWorkspaceId = fixture.workspaceIds[0]
        let secondWorkspaceId = fixture.workspaceIds[1]
        let firstSelected = try addManagedWindow(
            pid: 461_014,
            windowId: 14,
            to: firstWorkspaceId,
            fixture: fixture
        )
        _ = try addManagedWindow(
            pid: 461_014,
            windowId: 15,
            to: firstWorkspaceId,
            fixture: fixture
        )
        let secondSelected = try addManagedWindow(
            pid: 461_015,
            windowId: 16,
            to: secondWorkspaceId,
            fixture: fixture
        )
        _ = try addManagedWindow(
            pid: 461_015,
            windowId: 17,
            to: secondWorkspaceId,
            fixture: fixture
        )
        var refreshedWorkspaceSets: [Set<WorkspaceDescriptor.ID>] = []
        var environment = OverviewEnvironment()
        environment.windowTitle = { _ in "Window" }
        environment.windowFrame = { _ in CGRect(x: 0, y: 0, width: 500, height: 400) }
        environment.onCachedProjectionRefreshed = { refreshedWorkspaceSets.append($0) }
        let overview = OverviewController(
            wmController: fixture.controller,
            motionPolicy: fixture.controller.motionPolicy,
            environment: environment
        )
        overview.prepareOpenState()
        overview.onAnimationComplete(state: .open)

        XCTAssertTrue(overview.executeStructuralHotkey(
            .workspace(.moveTo(1)), selectedHandle: firstSelected
        )?.didMutate == true)
        XCTAssertTrue(overview.executeStructuralHotkey(
            .workspace(.moveTo(0)), selectedHandle: secondSelected
        )?.didMutate == true)

        for _ in 0 ..< 100
            where fixture.controller.layoutRefreshController.layoutState.activeRefreshTask != nil
            || fixture.controller.layoutRefreshController.layoutState.pendingRefresh != nil
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(refreshedWorkspaceSets.count, 1)
        XCTAssertEqual(refreshedWorkspaceSets.first, [firstWorkspaceId, secondWorkspaceId])
    }

    func testCompletedWorkspaceTransferActivatesDestinationWithoutAXFocus() throws {
        let fixture = try makeFixture(layouts: [.dwindle, .dwindle])
        let sourceWorkspaceId = fixture.workspaceIds[0]
        let destinationWorkspaceId = fixture.workspaceIds[1]
        let selected = try addManagedWindow(
            pid: 461_002,
            windowId: 1,
            to: sourceWorkspaceId,
            fixture: fixture
        )
        let liveFocused = try addManagedWindow(
            pid: 461_002,
            windowId: 2,
            to: sourceWorkspaceId,
            fixture: fixture
        )
        _ = try addManagedWindow(
            pid: 461_003,
            windowId: 1,
            to: destinationWorkspaceId,
            fixture: fixture
        )
        XCTAssertTrue(
            fixture.controller.workspaceManager.setManagedFocus(
                liveFocused.id,
                in: sourceWorkspaceId,
                onMonitor: fixture.monitor.id
            )
        )

        let overview = OverviewController(
            wmController: fixture.controller,
            motionPolicy: fixture.controller.motionPolicy
        )
        let outcome = withBlockedLayoutRefreshes(fixture) {
            overview.executeStructuralHotkey(.workspace(.moveTo(1)), selectedHandle: selected)
        }
        let mutation = try XCTUnwrap(outcome?.mutation)

        XCTAssertEqual(mutation.sourceWorkspaceId, sourceWorkspaceId)
        XCTAssertEqual(mutation.destinationWorkspaceId, destinationWorkspaceId)
        XCTAssertEqual(mutation.selectedHandle, selected)
        XCTAssertEqual(fixture.controller.workspaceManager.workspace(for: selected.id), destinationWorkspaceId)
        XCTAssertEqual(
            fixture.controller.workspaceManager.lastFocusedToken(in: destinationWorkspaceId),
            selected.id
        )
        XCTAssertEqual(
            fixture.controller.workspaceManager.activeWorkspace(on: fixture.monitor.id)?.id,
            destinationWorkspaceId
        )
        XCTAssertEqual(fixture.controller.workspaceManager.interactionMonitorId, fixture.monitor.id)
        XCTAssertEqual(overview.selectedWindowHandle, selected)
        XCTAssertEqual(fixture.controller.workspaceManager.selectedManagedToken, liveFocused.id)
        XCTAssertEqual(fixture.focusRecorder.callCount, 0)
    }

    func testDwindleOverviewRejectsMoveAndMoveContainerInEveryDirection() throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        let workspaceId = fixture.workspaceIds[0]
        let first = try addManagedWindow(pid: 461_025, windowId: 31, to: workspaceId, fixture: fixture)
        let second = try addManagedWindow(pid: 461_025, windowId: 32, to: workspaceId, fixture: fixture)
        let engine = try XCTUnwrap(fixture.controller.dwindleEngine)
        _ = fixture.controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
            engine.calculateLayout(for: workspaceId, screen: fixture.monitor.visibleFrame)
        }
        let firstNode = try XCTUnwrap(engine.findNode(for: first.id, in: workspaceId))
        let secondNode = try XCTUnwrap(engine.findNode(for: second.id, in: workspaceId))
        let parent = try XCTUnwrap(firstNode.parent)
        XCTAssertEqual(secondNode.parent?.id, parent.id)
        let originalChildIds = parent.children.map(\.id)
        let originalFirstTile = try XCTUnwrap(engine.tileSnapshot(for: first.id, in: workspaceId))
        let originalSecondTile = try XCTUnwrap(engine.tileSnapshot(for: second.id, in: workspaceId))
        let overview = OverviewController(
            wmController: fixture.controller,
            motionPolicy: fixture.controller.motionPolicy
        )
        let assertUnchanged = {
            XCTAssertEqual(parent.children.map(\.id), originalChildIds)
            XCTAssertEqual(engine.tileSnapshot(for: first.id, in: workspaceId), originalFirstTile)
            XCTAssertEqual(engine.tileSnapshot(for: second.id, in: workspaceId), originalSecondTile)
            XCTAssertEqual(engine.tileCount(in: workspaceId), 2)
        }

        for direction in [Direction.left, .right, .up, .down] {
            XCTAssertEqual(
                overview.performStructuralHotkey(.move(direction), selectedHandle: second),
                .unchanged,
                direction.rawValue
            )
            assertUnchanged()
            XCTAssertEqual(
                overview.performStructuralHotkey(.dwindle(.moveGroup(direction)), selectedHandle: second),
                .unchanged,
                direction.rawValue
            )
            assertUnchanged()
        }

        XCTAssertEqual(fixture.focusRecorder.callCount, 0)
    }

    func testRemovalCallbackObservesAuthoritativeWindowRemoval() throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        let workspaceId = fixture.workspaceIds[0]
        let handle = try addManagedWindow(pid: 461_008, windowId: 1, to: workspaceId, fixture: fixture)
        let manager = fixture.controller.workspaceManager
        var callbackTokens: [WindowToken] = []
        var callbackEntryWasPresent = true
        var callbackWorkspaceWasPresent = true
        manager.onWindowRemoved = { entry in
            callbackTokens.append(entry.token)
            callbackEntryWasPresent = manager.entry(for: entry.token) != nil
            callbackWorkspaceWasPresent = manager.workspace(for: entry.token) != nil
        }
        defer { manager.onWindowRemoved = nil }

        let removed = manager.removeWindow(pid: handle.id.pid, windowId: handle.id.windowId)

        XCTAssertEqual(removed?.token, handle.id)
        XCTAssertEqual(callbackTokens, [handle.id])
        XCTAssertFalse(callbackEntryWasPresent)
        XCTAssertFalse(callbackWorkspaceWasPresent)
        XCTAssertNil(manager.entry(for: handle.id))
        XCTAssertNil(manager.workspace(for: handle.id))
    }

    func testHiddenWindowCannotBeginOverviewDrag() throws {
        let fixture = try makeFixture(layouts: [.dwindle])
        let workspaceId = fixture.workspaceIds[0]
        let handle = try addManagedWindow(
            pid: 461_032,
            windowId: 42,
            to: workspaceId,
            fixture: fixture
        )
        let prepared = try prepareDragOverview(fixture)
        fixture.controller.workspaceManager.setAppHidden(
            true,
            pid: handle.pid,
            source: .service
        )

        prepared.overview.drag.beginDrag(
            on: fixture.monitor.id,
            handle: handle,
            startPoint: .zero
        )

        XCTAssertFalse(prepared.overview.hasActiveDragSession)
    }

    func testMouseDragOntoDwindleCardUsesWorkspaceOnlyPlacement() async throws {
        let fixture = try makeFixture(layouts: [.dwindle, .dwindle])
        let sourceWorkspaceId = fixture.workspaceIds[0]
        let destinationWorkspaceId = fixture.workspaceIds[1]
        let dragged = try addManagedWindow(
            pid: 461_023,
            windowId: 29,
            to: sourceWorkspaceId,
            fixture: fixture
        )
        let destination = try addManagedWindow(
            pid: 461_024,
            windowId: 30,
            to: destinationWorkspaceId,
            fixture: fixture
        )
        let prepared = try prepareDragOverview(fixture)
        let destinationFrame = try XCTUnwrap(prepared.layout.window(for: destination)?.overviewFrame)
        let dropPoint = CGPoint(x: destinationFrame.midX, y: destinationFrame.midY)

        prepared.overview.drag.beginDrag(on: fixture.monitor.id, handle: dragged, startPoint: .zero)
        prepared.overview.drag.updateDrag(on: fixture.monitor.id, at: dropPoint)
        prepared.overview.drag.endDrag(on: fixture.monitor.id, at: dropPoint)
        try await waitForLayoutRefreshes(fixture)

        let engine = try XCTUnwrap(fixture.controller.dwindleEngine)
        XCTAssertNil(engine.findNode(for: dragged.id, in: sourceWorkspaceId))
        XCTAssertNotNil(engine.findNode(for: dragged.id, in: destinationWorkspaceId))
        XCTAssertEqual(
            fixture.controller.workspaceManager.workspace(for: dragged.id),
            destinationWorkspaceId
        )
        XCTAssertEqual(
            fixture.controller.workspaceManager.activeWorkspace(on: fixture.monitor.id)?.id,
            destinationWorkspaceId
        )
        XCTAssertEqual(prepared.overview.selectedWindowHandle, dragged)
        XCTAssertEqual(fixture.focusRecorder.callCount, 0)
    }

    func testOverviewSelectionSettlesDestinationBeforeRelayout() async throws {
        for targetLayout in [LayoutType.dwindle] {
            let fixture = try makeFixture(layouts: [.dwindle, targetLayout])
            let controller = fixture.controller
            let manager = controller.workspaceManager
            let source = fixture.workspaceIds[0]
            let destination = fixture.workspaceIds[1]
            _ = try addManagedWindow(pid: 461_050, windowId: 50, to: source, fixture: fixture)
            var handles: [WindowHandle] = []
            for index in 0 ..< 4 {
                handles.append(try addManagedWindow(
                    pid: 461_051, windowId: 51 + index, to: destination, fixture: fixture
                ))
            }
            let refresh = controller.layoutRefreshController
            refresh.requestImmediateRelayout(reason: .overviewMutation, affectedWorkspaceIds: Set(fixture.workspaceIds))
            while let task = refresh.layoutState.activeRefreshTask { await task.value }
            let target = try XCTUnwrap(handles.last)
            let parked = CGRect(x: -20000, y: -20000, width: 500, height: 400)
            var environment = OverviewEnvironment()
            environment.windowTitle = { _ in "Window" }
            environment.windowFrame = { _ in parked }
            environment.activateOmniWM = {}
            environment.schedulePostCloseHandoff = { _ in }
            controller.motionPolicy.animationsEnabled = true
            let overview = OverviewController(
                wmController: controller,
                motionPolicy: controller.motionPolicy,
                environment: environment,
                animationInstaller: { _, _, _ in true },
                animationMediaTimeProvider: { 0 }
            )
            overview.onPrepareActivation = controller.windowActionHandler.prepareOverviewSelection
            overview.open()
            overview.onAnimationComplete(state: .open)
            let view = try XCTUnwrap(overview.windowSession.primaryOverviewWindow()?.contentView?.subviews
                .compactMap { $0 as? OverviewView }.first)
            let watermark = controller.intentLedger.newestFocusIntentId()

            overview.input.selectAndActivateWindow(target)

            guard case .closing = overview.state else { return XCTFail("Expected close before relayout runs") }
            let request = try XCTUnwrap(refresh.layoutState.activeRefresh ?? refresh.layoutState.pendingRefresh)
            XCTAssertEqual(request.reason, .overviewMutation)
            XCTAssertEqual(request.affectedWorkspaceIds, [source, destination])
            XCTAssertEqual(manager.activeWorkspace(on: fixture.monitor.id)?.id, destination)
            let restFrame = try XCTUnwrap(view.layout.window(for: target)?.interpolatedFrame(progress: 0))
            XCTAssertTrue(fixture.monitor.frame.intersects(restFrame))
            XCTAssertEqual(view.layout.anchorWorkspaceId, destination)
            XCTAssertEqual(fixture.focusRecorder.callCount, 0)

            while let task = refresh.layoutState.activeRefreshTask { await task.value }

            let frames = controller.dwindleEngine?.calculateLayout(
                for: destination,
                screen: controller.insetWorkingFrame(for: fixture.monitor)
            )
            XCTAssertEqual(restFrame, frames?[target.id])
            XCTAssertEqual(view.layout.window(for: target)?.interpolatedFrame(progress: 0), restFrame)
            XCTAssertEqual(controller.intentLedger.newestFocusIntentId(), watermark)
            XCTAssertEqual(fixture.focusRecorder.callCount, 0)
            overview.completeCloseTransition(targetWindow: nil)
        }
    }

    private func emptyDynamicWorkspaceInOverview(_ fixture: Fixture) async throws -> WorkspaceDescriptor.ID {
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let configuredId = fixture.workspaceIds[0]
        let dynamic = try XCTUnwrap(manager.createDynamicWorkspace(named: "2", on: fixture.monitor.id))
        let moved = try addManagedWindow(pid: 461_050, windowId: 50, to: dynamic.id, fixture: fixture)
        XCTAssertTrue(manager.setActiveWorkspace(dynamic.id, on: fixture.monitor.id))
        XCTAssertTrue(manager.setManagedFocus(moved.id, in: dynamic.id, onMonitor: fixture.monitor.id))
        controller.toggleOverview()
        XCTAssertTrue(controller.isOverviewOpen())

        XCTAssertEqual(
            controller.commandHandler.handleHotkeyInvocation(
                HotkeyInvocation(
                    command: .workspace(.moveTo(0)),
                    trigger: PhysicalHotkeyTrigger(keyCode: 18, modifiers: 0, isRepeat: false)
                )
            ),
            .executed
        )
        while let task = controller.layoutRefreshController.layoutState.activeRefreshTask { await task.value }

        XCTAssertEqual(manager.workspace(for: moved.id), configuredId)
        XCTAssertEqual(manager.activeWorkspace(on: fixture.monitor.id)?.id, configuredId)
        XCTAssertEqual(manager.windowQueries.windowCount(in: dynamic.id), 0)
        XCTAssertNotNil(manager.descriptor(for: dynamic.id))
        XCTAssertTrue(controller.isOverviewOpen())
        return dynamic.id
    }

    private func makeFixture(layouts: [LayoutType]) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMOverviewStructuralCommandTests-\(UUID().uuidString)", isDirectory: true)
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
        settings.overview.workspaceGrid = false
        settings.workspaces.configurations = layouts.enumerated().map { index, layout in
            WorkspaceConfiguration(name: String(index + 1), monitorAssignment: .main, layoutType: layout)
        }
        let focusRecorder = FocusRecorder()
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { focusRecorder.activatedPIDs.append($0) },
                focusSpecificWindow: { pid, windowId, _ in
                    focusRecorder.focusedTokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                    focusRecorder.onFocus?()
                },
                raiseWindow: { _ in focusRecorder.raisedCount += 1 }
            )
        )
        let frame = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let monitor = Monitor(
            id: .init(displayId: 46_100),
            displayId: 46_100,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Overview Structural Tests"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        controller.workspaceManager.applySettings()

        let dwindleEngine = DwindleLayoutEngine()
        dwindleEngine.animationClock = controller.animationClock
        controller.dwindleEngine = dwindleEngine

        let workspaceIds = try layouts.indices.map { index in
            try XCTUnwrap(
                controller.workspaceManager.workspaceId(for: String(index + 1), createIfMissing: false)
            )
        }
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(workspaceIds[0], on: monitor.id))

        return Fixture(
            controller: controller,
            workspaceIds: workspaceIds,
            monitor: monitor,
            focusRecorder: focusRecorder
        )
    }

    private func prepareDragOverview(
        _ fixture: Fixture
    ) throws -> (overview: OverviewController, layout: OverviewLayout) {
        let workspaceManager = fixture.controller.workspaceManager
        var workspaces: [OverviewWorkspaceLayoutItem] = []
        var windowData: [WindowHandle: OverviewWindowLayoutData] = [:]
        var framesByToken: [WindowToken: CGRect] = [:]

        for monitor in workspaceManager.monitors {
            let activeWorkspaceId = workspaceManager.activeWorkspace(on: monitor.id)?.id
            for workspace in workspaceManager.workspaces(on: monitor.id) {
                workspaces.append(OverviewWorkspaceLayoutItem(
                    id: workspace.id,
                    name: workspace.name,
                    isActive: workspace.id == activeWorkspaceId
                ))
                for entry in workspaceManager.entries(in: workspace.id) {
                    guard let handle = workspaceManager.handle(for: entry.token) else { continue }
                    let ordinal = CGFloat(entry.windowId % 10)
                    let frame = CGRect(
                        x: 50 + ordinal * 20,
                        y: 80 + ordinal * 15,
                        width: 520,
                        height: 360
                    )
                    framesByToken[entry.token] = frame
                    windowData[handle] = OverviewWindowLayoutData(
                        token: entry.token,
                        workspaceId: entry.workspaceId,
                        title: "Window \(entry.windowId)",
                        appName: "Test",
                        appIcon: nil,
                        frame: frame
                    )
                }
            }
        }

        var environment = OverviewEnvironment()
        environment.windowTitle = { "Window \($0.windowId)" }
        environment.windowFrame = { framesByToken[$0.token] }
        let overview = OverviewController(
            wmController: fixture.controller,
            motionPolicy: fixture.controller.motionPolicy,
            environment: environment
        )
        overview.prepareOpenState()
        overview.onAnimationComplete(state: .open)
        let layout = OverviewLayoutCalculator(
            screenFrame: OverviewLayoutCalculator.viewportFrame(for: fixture.monitor.frame),
            scale: OverviewLayoutCalculator.clampedScale(
                CGFloat(fixture.controller.settings.overview.zoom)
            )
        ).calculateLayout(
            workspaces: workspaces,
            windows: windowData,
            searchQuery: ""
        )
        return (overview, layout)
    }

    private func waitForLayoutRefreshes(_ fixture: Fixture) async throws {
        let refreshController = fixture.controller.layoutRefreshController
        for _ in 0 ..< 200 {
            if refreshController.layoutState.activeRefreshTask == nil,
               refreshController.layoutState.pendingRefresh == nil
            {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Layout refreshes did not settle")
    }

    private func addManagedWindow(
        pid: pid_t,
        windowId: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        fixture: Fixture
    ) throws -> WindowHandle {
        let controller = fixture.controller
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
        controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
            _ = controller.dwindleEngine?.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        }
        return try XCTUnwrap(controller.workspaceManager.handle(for: token))
    }

    private func withBlockedLayoutRefreshes<T>(
        _ fixture: Fixture,
        _ body: () throws -> T
    ) rethrows -> T {
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        let refreshController = fixture.controller.layoutRefreshController
        refreshController.layoutState.activeRefreshTask = blocker
        refreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .overviewMutation,
            affectedWorkspaceIds: [fixture.workspaceIds[0]]
        )
        defer {
            blocker.cancel()
            refreshController.layoutState.activeRefreshTask = nil
            refreshController.layoutState.activeRefresh = nil
            refreshController.layoutState.pendingRefresh = nil
        }
        return try body()
    }
}
