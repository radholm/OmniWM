// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import OmniWMIPC
import XCTest

@MainActor
final class IPCHiddenReasonProjectionTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let first: WindowToken
        let second: WindowToken
        let router: IPCQueryRouter

        var manager: WorkspaceManager {
            controller.workspaceManager
        }
    }

    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testSettledInactiveMembersKeepTabReasonAndVisibleFiltering() throws {
        for layout in [LayoutType.dwindle] {
            let fixture = try makeFixture(layout: layout)
            setHidden(.layoutTransient(.left), for: fixture.first, in: fixture)

            for _ in 0 ..< 3 {
                let inactive = try snapshot(fixture.first, in: fixture)
                XCTAssertEqual(inactive.hiddenReason?.rawValue, "tab-inactive")
                XCTAssertEqual(inactive.isVisible, false)
                let active = try snapshot(fixture.second, in: fixture)
                XCTAssertNil(active.hiddenReason)
                XCTAssertEqual(active.isVisible, true)
            }

            let visible = fixture.router.windowsResult(
                IPCQueryRequest(name: .windows, selectors: IPCQuerySelectors(visible: true), fields: ["window-id"])
            )
            XCTAssertEqual(visible.windows.compactMap(\.windowId), [fixture.second.windowId])
        }
    }

    func testSelectionTransfersReasonOnlyAfterRevealStateChanges() throws {
        for layout in [LayoutType.dwindle] {
            let fixture = try makeFixture(layout: layout)
            setHidden(.layoutTransient(.left), for: fixture.first, in: fixture)
            fixture.manager.withEngineMutationScope(in: fixture.workspaceId) {
                XCTAssertTrue(fixture.controller.dwindleEngine?.activateWindow(
                    fixture.first, in: fixture.workspaceId
                ) == true)
            }

            XCTAssertEqual(try snapshot(fixture.first, in: fixture).hiddenReason, .layoutTransient)
            XCTAssertEqual(try snapshot(fixture.first, in: fixture).isVisible, false)
            XCTAssertNil(try snapshot(fixture.second, in: fixture).hiddenReason)

            setHidden(nil, for: fixture.first, in: fixture)
            setHidden(.layoutTransient(.right), for: fixture.second, in: fixture)
            XCTAssertNil(try snapshot(fixture.first, in: fixture).hiddenReason)
            XCTAssertEqual(try snapshot(fixture.first, in: fixture).isVisible, true)
            XCTAssertEqual(try snapshot(fixture.second, in: fixture).hiddenReason?.rawValue, "tab-inactive")
        }
    }

    func testExtractionAndLeavingTabbedModeRemoveTabCauseBeforeRevealCompletes() throws {
        for layout in [LayoutType.dwindle] {
            let fixture = try makeFixture(layout: layout)
            setHidden(.layoutTransient(.left), for: fixture.first, in: fixture)
            let engine = try XCTUnwrap(fixture.controller.dwindleEngine)
            fixture.manager.withEngineMutationScope {
                XCTAssertTrue(engine.ungroupWindow(fixture.first, direction: .right, in: fixture.workspaceId))
            }

            XCTAssertEqual(try snapshot(fixture.first, in: fixture).hiddenReason, .layoutTransient)
            setHidden(nil, for: fixture.first, in: fixture)
            for token in [fixture.first, fixture.second] {
                XCTAssertNil(try snapshot(token, in: fixture).hiddenReason)
                XCTAssertEqual(try snapshot(token, in: fixture).isVisible, true)
            }
        }
    }

    func testWorkspaceAndScratchpadReasonsTakePrecedence() throws {
        for layout in [LayoutType.dwindle] {
            let fixture = try makeFixture(layout: layout)
            for (reason, expected) in [
                (HiddenReason.workspaceInactive, IPCHiddenReason.workspaceInactive),
                (.scratchpad, .scratchpad)
            ] {
                setHidden(reason, for: fixture.first, in: fixture)
                XCTAssertEqual(try snapshot(fixture.first, in: fixture).hiddenReason, expected)
                XCTAssertEqual(try snapshot(fixture.first, in: fixture).isVisible, false)
            }
        }
    }

    func testQueryWireRoundTripAndFieldSelection() throws {
        let fixture = try makeFixture(layout: .dwindle)
        setHidden(.layoutTransient(.left), for: fixture.first, in: fixture)
        let result = fixture.router.windowsResult(IPCQueryRequest(name: .windows))
        let response = IPCResponse.success(id: "tabs", kind: .query, result: IPCResult(windows: result))
        let data = try IPCWire.encodeResponseLine(response)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"hiddenReason\":\"tab-inactive\""))
        XCTAssertEqual(try IPCWire.decodeResponse(from: data), response)

        let selected = fixture.router.windowsResult(
            IPCQueryRequest(name: .windows, fields: ["window-id", "hidden-reason"])
        )
        let inactive = try XCTUnwrap(selected.windows.first { $0.windowId == fixture.first.windowId })
        XCTAssertEqual(inactive.hiddenReason?.rawValue, "tab-inactive")
        XCTAssertNil(inactive.isVisible)

        let omitted = fixture.router.windowsResult(IPCQueryRequest(name: .windows, fields: ["window-id"]))
        XCTAssertTrue(omitted.windows.allSatisfy { $0.hiddenReason == nil })
        let omittedData = try IPCWire.makeEncoder().encode(omitted)
        XCTAssertFalse(String(decoding: omittedData, as: UTF8.self).contains("hiddenReason"))
    }

    private func snapshot(_ token: WindowToken, in fixture: Fixture) throws -> IPCWindowQuerySnapshot {
        try XCTUnwrap(fixture.router.windowsResult(
            IPCQueryRequest(name: .windows, fields: ["window-id", "is-visible", "hidden-reason"])
        ).windows.first { $0.windowId == token.windowId })
    }

    private func setHidden(_ reason: HiddenReason?, for token: WindowToken, in fixture: Fixture) {
        fixture.manager.setHiddenState(reason.map {
            HiddenState(proportionalPosition: .zero, referenceMonitorId: nil, reason: $0)
        }, for: token)
    }

    private func makeFixture(layout: LayoutType) throws -> Fixture {
        let controller = WindowAdmissionTestSupport.controller(prefix: "IPCHiddenReasonProjectionTests")
        let manager = controller.workspaceManager
        manager.applyMonitorConfigurationChange([
            Monitor(
                id: .init(displayId: 1), displayId: 1, frame: screen, visibleFrame: screen,
                hasNotch: false, name: "Hidden reason"
            )
        ])
        let workspaceId = try XCTUnwrap(WindowAdmissionTestSupport.workspace(
            named: "91", layoutType: layout, controller: controller
        ))
        _ = manager.focusWorkspace(named: "91")
        let first = WindowToken(pid: 890_692, windowId: 692_001)
        let second = WindowToken(pid: 890_693, windowId: 692_002)
        for token in [first, second] {
            _ = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        }
        let router = IPCQueryRouter(controller: controller, appVersion: nil, sessionToken: "hidden-reason-tests")
        router.windowOrderedInProvider = { _ in true }
        let fixture = Fixture(
            controller: controller, workspaceId: workspaceId, first: first, second: second, router: router
        )
        let engine = DwindleLayoutEngine()
        controller.dwindleEngine = engine
        manager.withEngineMutationScope {
            _ = engine.addWindow(token: first, to: workspaceId, activeWindowFrame: nil)
            _ = engine.addWindow(token: second, to: workspaceId, activeWindowFrame: nil)
            XCTAssertTrue(engine.groupWindow(second, into: first, in: workspaceId))
        }
        controller.layoutRefreshController.resetState()
        return fixture
    }
}
