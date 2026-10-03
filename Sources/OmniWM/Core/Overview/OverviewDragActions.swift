// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon
import Foundation
import QuartzCore
import ScreenCaptureKit

extension OverviewStructuralActions {
    enum DragMutationOutcome {
        case changed(StructuralMutation)
        case placedFloating(StructuralMutation, CGRect)
        case unchanged
    }

    struct DragSession {
        let handle: WindowHandle
        let windowId: Int
        let workspaceId: WorkspaceDescriptor.ID
        let monitorId: Monitor.ID
        let startPoint: CGPoint
    }
}

extension OverviewStructuralActions {
    func performDragAction(session: DragSession, target: OverviewDragTarget) -> DragMutationOutcome {
        guard let wmController,
              let entry = windowFacts.visibleManagedEntry(for: session.handle),
              entry.workspaceId == session.workspaceId,
              windowFacts.isStructurallyMutable(entry)
        else {
            return .unchanged
        }

        switch target {
        case let .floatingPlacement(destination, frame, _):
            guard entry.mode == .floating, frame.size.hasFinitePositiveDimensions(),
                  frame.origin.x.isFinite, frame.origin.y.isFinite
            else { return .unchanged }
            return placeFloatingWindow(session: session, destination: destination, frame: frame)

        case let .newWorkspace(monitorId):
            guard let workspace = wmController.workspaceNavigationHandler.createOverviewWorkspace(on: monitorId) else {
                return .unchanged
            }
            let outcome = performDragAction(session: session, target: .workspaceMove(workspaceId: workspace.id))
            if case .unchanged = outcome { wmController.workspaceManager.removeWorkspaces([workspace.id]) }
            return outcome

        case let .workspaceMove(targetWsId):
            guard targetWsId != session.workspaceId else { return .unchanged }
            guard case let .changed(mutation) = wmController.workspaceNavigationHandler.moveWindow(
                handle: session.handle,
                toWorkspaceId: targetWsId
            ) else { return .unchanged }
            return .changed(mutation)
        }
    }

    private func placeFloatingWindow(
        session: DragSession,
        destination: OverviewFloatingDestination,
        frame: CGRect
    ) -> DragMutationOutcome {
        guard let wmController else { return .unchanged }
        switch destination {
        case let .newWorkspace(monitorId):
            guard let workspace = wmController.workspaceNavigationHandler.createOverviewWorkspace(on: monitorId) else {
                return .unchanged
            }
            let outcome = placeFloatingWindow(session: session, destination: .workspace(workspace.id), frame: frame)
            if case .unchanged = outcome { wmController.workspaceManager.removeWorkspaces([workspace.id]) }
            return outcome
        case let .workspace(workspaceId):
            guard wmController.workspaceManager.descriptor(for: workspaceId) != nil,
                  let monitor = wmController.workspaceManager.monitorForWorkspace(workspaceId)
            else { return .unchanged }
            let mutation: StructuralMutation
            if workspaceId == session.workspaceId {
                mutation = insertionMutation(session: session, destination: workspaceId)
            } else {
                guard case let .changed(transfer) = wmController.workspaceNavigationHandler.moveWindow(
                    handle: session.handle,
                    toWorkspaceId: workspaceId
                ) else { return .unchanged }
                mutation = transfer
            }
            return .placedFloating(mutation, FloatingFrameGeometry.clamped(frame, in: monitor.visibleFrame))
        }
    }

    private func insertionMutation(session: DragSession, destination: WorkspaceDescriptor.ID) -> StructuralMutation {
        StructuralMutation(
            sourceWorkspaceId: session.workspaceId,
            destinationWorkspaceId: destination,
            selectedHandle: session.handle,
            movedTokens: [session.handle.id]
        )
    }
}
