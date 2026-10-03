// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class TrackpadWindowGestureTests: XCTestCase {
    private let workingFrame = CGRect(x: 0, y: 0, width: 1600, height: 900)

    @MainActor
    private struct GestureDriver {
        let handler: MouseEventHandler
        let location: CGPoint
        var contactSession: MultitouchContactSession?
        var time: TimeInterval = 100

        mutating func begin(fingers: Int, x: CGFloat, y: CGFloat = 0.5) {
            send(.began, fingers: fingers, x: x, y: y)
        }

        mutating func frame(fingers: Int, x: CGFloat, y: CGFloat = 0.5, after dt: TimeInterval = 0.01) {
            time += dt
            send(.changed, fingers: fingers, x: x, y: y)
        }

        mutating func drag(fingers: Int, fromX: CGFloat, toX: CGFloat, steps: Int = 10, y: CGFloat = 0.5) {
            for step in 1 ... steps {
                frame(fingers: fingers, x: fromX + (toX - fromX) * CGFloat(step) / CGFloat(steps), y: y)
            }
        }

        mutating func end(_ phase: NSEvent.Phase = .ended) {
            time += 0.01
            send(phase, fingers: 0, x: 0, y: 0)
        }

        private func send(_ phase: NSEvent.Phase, fingers: Int, x: CGFloat, y: CGFloat) {
            let touches = (0 ..< fingers).map { _ in
                MouseEventHandler.GestureTouchSample(phase: .moved, normalizedPosition: CGPoint(x: x, y: y))
            }
            handler.receiveTapGestureEvent(
                MouseEventHandler.GestureEventSnapshot(
                    location: location,
                    phaseRawValue: phase.rawValue,
                    timestamp: time,
                    touches: phase == .ended || phase == .cancelled ? [] : touches,
                    contactSession: contactSession
                )
            )
        }
    }

    @MainActor
    private struct DwindleFixture {
        let controller: WMController
        let engine: DwindleLayoutEngine
        let workspaceId: WorkspaceDescriptor.ID
        let screen: CGRect
        let first: WindowToken
        let second: WindowToken
        let firstFrame: CGRect
        let secondFrame: CGRect

        var handler: MouseEventHandler {
            controller.mouseEventHandler
        }

        func presentedFrame(_ token: WindowToken) -> CGRect? {
            engine.presentedFrame(for: token, in: workspaceId, at: 0)
        }

        func relayout() {
            _ = engine.calculateLayout(for: workspaceId, screen: screen)
            engine.cancelAnimations(in: workspaceId)
        }

        func driver(at location: CGPoint) -> GestureDriver {
            GestureDriver(handler: handler, location: location)
        }
    }

    func testFourFingerDragSwapsDwindleTilesOnRelease() throws {
        let fixture = try makeDwindleFixture(pid: 9_201)
        let handler = fixture.handler
        let travel = (fixture.secondFrame.center.x - fixture.firstFrame.center.x) / fixture.screen.width

        var gesture = fixture.driver(at: fixture.firstFrame.center)
        gesture.begin(fingers: 4, x: 0.2)
        gesture.drag(fingers: 4, fromX: 0.2, toX: 0.2 + travel)

        XCTAssertTrue(handler.state.isMoving)
        XCTAssertEqual(handler.state.moveLayout, .dwindle)
        XCTAssertEqual(fixture.engine.interactiveMove?.token, fixture.first)
        XCTAssertEqual(fixture.engine.interactiveMove?.targetToken, fixture.second)

        gesture.end()

        XCTAssertFalse(handler.state.isMoving)
        XCTAssertNil(fixture.engine.interactiveMove)
        fixture.relayout()
        XCTAssertEqual(fixture.presentedFrame(fixture.first), fixture.secondFrame)
        XCTAssertEqual(fixture.presentedFrame(fixture.second), fixture.firstFrame)
    }

    func testThreeFingerDragResizesDwindleSplit() throws {
        let fixture = try makeDwindleFixture(pid: 9_202)
        let handler = fixture.handler

        var gesture = fixture.driver(at: CGPoint(x: fixture.firstFrame.maxX - 20, y: fixture.firstFrame.midY))
        gesture.begin(fingers: 3, x: 0.4)
        gesture.drag(fingers: 3, fromX: 0.4, toX: 0.5, steps: 8)
        XCTAssertTrue(handler.state.isResizing)
        XCTAssertEqual(handler.state.resizeLayout, .dwindle)
        XCTAssertEqual(fixture.engine.interactiveResize?.token, fixture.first)

        gesture.end()

        XCTAssertFalse(handler.state.isResizing)
        XCTAssertNil(fixture.engine.interactiveResize)
        fixture.relayout()
        let widthAfter = try XCTUnwrap(fixture.presentedFrame(fixture.first)).width
        XCTAssertGreaterThan(widthAfter, fixture.firstFrame.width + 100)
    }

    func testDwindleResizeGestureFallsBackToTheEdgeThatCanMove() throws {
        let fixture = try makeDwindleFixture(pid: 9_203)
        let handler = fixture.handler

        var gesture = fixture.driver(at: CGPoint(x: fixture.firstFrame.minX + 20, y: fixture.firstFrame.minY + 20))
        gesture.begin(fingers: 3, x: 0.4)
        gesture.drag(fingers: 3, fromX: 0.4, toX: 0.5, steps: 8)
        XCTAssertTrue(handler.state.isResizing)
        XCTAssertEqual(fixture.engine.interactiveResize?.edges, .right)
        XCTAssertEqual(handler.state.currentHoveredEdges, .right)
        XCTAssertFalse(handler.state.suppressGestureStartUntilAllTouchesLift)

        gesture.end()

        XCTAssertFalse(handler.state.isResizing)
        fixture.relayout()
        let widthAfter = try XCTUnwrap(fixture.presentedFrame(fixture.first)).width
        XCTAssertGreaterThan(widthAfter, fixture.firstFrame.width + 100)
    }

    func testMouseResizeKeepsExactEdgesAndRefusesAnImmovableOne() throws {
        let fixture = try makeDwindleFixture(pid: 9_204)
        let leftGrip = CGPoint(x: fixture.firstFrame.minX + 20, y: fixture.firstFrame.midY)
        XCTAssertFalse(fixture.handler.dispatchMouseDown(at: leftGrip, modifiers: .maskAlternate, button: .right))
        XCTAssertNil(fixture.engine.interactiveResize)
    }

    private func makeController() -> WMController {
        let controller = WindowAdmissionTestSupport.controller(prefix: "TrackpadWindowGestureTests")
        controller.layoutRefreshController.displayLinkActivationForTests = { _ in true }
        let settings = controller.settings
        settings.animationsEnabled = false
        settings.gestures.workspaceSwipeEnabled = false
        settings.gestures.windowMoveEnabled = true
        settings.gestures.windowMoveFingerCount = .four
        settings.gestures.windowResizeEnabled = true
        settings.gestures.windowResizeFingerCount = .three
        settings.gestures.windowGestureSensitivity = 1.0
        return controller
    }

    private func makeMonitor() -> Monitor {
        Monitor(
            id: .init(displayId: 52_001),
            displayId: 52_001,
            frame: workingFrame,
            visibleFrame: workingFrame,
            hasNotch: false,
            name: "Trackpad Window Gesture"
        )
    }

    private func makeDwindleFixture(pid: pid_t) throws -> DwindleFixture {
        let controller = makeController()
        let monitor = makeMonitor()
        controller.settings.workspaces.configurations = [
            WorkspaceConfiguration(
                name: "1",
                monitorAssignment: .specificDisplay(OutputId(from: monitor)),
                layoutType: .dwindle
            )
        ]
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        controller.workspaceManager.applySettings()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(named: "1"))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.enableDwindleLayout()
        let engine = try XCTUnwrap(controller.dwindleEngine)
        var tokens: [WindowToken] = []
        for windowId in 1 ... 2 {
            let token = controller.workspaceManager.addWindow(
                WindowAdmissionTestSupport.axRef(for: WindowToken(pid: pid, windowId: windowId)),
                pid: pid,
                windowId: windowId,
                to: workspaceId
            )
            controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
                _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
            }
            tokens.append(token)
        }
        let screen = controller.insetWorkingFrame(for: monitor)
        _ = engine.calculateLayout(for: workspaceId, screen: screen)
        engine.cancelAnimations(in: workspaceId)
        let firstFrame = try XCTUnwrap(engine.presentedFrame(for: tokens[0], in: workspaceId, at: 0))
        let secondFrame = try XCTUnwrap(engine.presentedFrame(for: tokens[1], in: workspaceId, at: 0))
        XCTAssertNotEqual(firstFrame, secondFrame)
        XCTAssertEqual(controller.settings.workspaces.layoutType(for: "1"), .dwindle)

        return DwindleFixture(
            controller: controller,
            engine: engine,
            workspaceId: workspaceId,
            screen: screen,
            first: tokens[0],
            second: tokens[1],
            firstFrame: firstFrame,
            secondFrame: secondFrame
        )
    }
}
