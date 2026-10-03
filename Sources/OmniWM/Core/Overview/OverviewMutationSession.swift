// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon
import Foundation
import QuartzCore
import ScreenCaptureKit

@MainActor
final class OverviewMutationSession {
    private weak var wmController: WMController?
    private weak var overview: OverviewController?
    private let projection: OverviewViewportProjection
    private let windowFacts: OverviewWindowFacts
    private let structuralActions: OverviewStructuralActions
    private var structuralTransferGeneration: UInt64 = 0
    private var activeStructuralTransferGeneration: UInt64?
    private var projectionMutationGeneration: UInt64 = 0
    private var pendingProjectionWorkspaceIds: Set<WorkspaceDescriptor.ID> = []

    private var state: OverviewState {
        overview?.state ?? .closed
    }

    var isTransferring: Bool {
        activeStructuralTransferGeneration != nil
    }

    init(
        wmController: WMController,
        projection: OverviewViewportProjection,
        windowFacts: OverviewWindowFacts,
        structuralActions: OverviewStructuralActions
    ) {
        self.wmController = wmController
        self.projection = projection
        self.windowFacts = windowFacts
        self.structuralActions = structuralActions
    }

    func connect(overview: OverviewController) {
        self.overview = overview
    }

    func reset() {
        activeStructuralTransferGeneration = nil
        projectionMutationGeneration &+= 1
        pendingProjectionWorkspaceIds.removeAll(keepingCapacity: true)
    }

    func completeStructuralMutation(_ mutation: StructuralMutation, floatingPlacement: CGRect? = nil) {
        guard let wmController, activateStructuralDestination(mutation) else { return }
        if let floatingPlacement {
            wmController.placeFloatingWindow(mutation.selectedHandle, frame: floatingPlacement)
        }
        let transferGeneration = serializesTransfer(mutation) ? beginStructuralTransfer() : nil
        let projectionGeneration = beginProjectionMutation(
            affectedWorkspaceIds: projectionWorkspaceIds(for: mutation)
        )

        wmController.layoutRefreshController.requestImmediateRelayout(
            reason: .overviewMutation,
            affectedWorkspaceIds: mutation.affectedWorkspaceIds,
            postLayout: { [weak self] in
                self?.finishStructuralMutation(
                    mutation,
                    projectionGeneration: projectionGeneration,
                    transferGeneration: transferGeneration
                )
            },
            postLayoutInvalidated: { [weak self] in
                self?.finishStructuralMutation(
                    mutation,
                    projectionGeneration: projectionGeneration,
                    transferGeneration: transferGeneration,
                    update: .immediate
                )
            }
        )
    }

    private func beginProjectionMutation(
        affectedWorkspaceIds: Set<WorkspaceDescriptor.ID>
    ) -> UInt64 {
        pendingProjectionWorkspaceIds.formUnion(affectedWorkspaceIds)
        projectionMutationGeneration &+= 1
        return projectionMutationGeneration
    }

    private func finishStructuralMutation(
        _ mutation: StructuralMutation,
        projectionGeneration: UInt64,
        transferGeneration: UInt64?,
        update: OverviewLayoutUpdate = .structural
    ) {
        defer { finishStructuralTransfer(transferGeneration) }
        guard projectionMutationGeneration == projectionGeneration else { return }
        synchronizeStructuralSelection(mutation)
        pendingProjectionWorkspaceIds.formUnion(projectionWorkspaceIds(for: mutation))
        let affectedWorkspaceIds = pendingProjectionWorkspaceIds
        pendingProjectionWorkspaceIds.removeAll(keepingCapacity: true)
        overview?.refreshCachedOverviewProjection(
            affectedWorkspaceIds: affectedWorkspaceIds,
            preservingViewport: mutation.sourceWorkspaceId == mutation.destinationWorkspaceId,
            update: update
        )
    }

    private func projectionWorkspaceIds(
        for mutation: StructuralMutation
    ) -> Set<WorkspaceDescriptor.ID> {
        var workspaceIds = mutation.affectedWorkspaceIds
        if let workspaceId = wmController?.workspaceManager.workspace(for: mutation.selectedHandle.id) {
            workspaceIds.insert(workspaceId)
        }
        return workspaceIds
    }

    private func activateStructuralDestination(_ mutation: StructuralMutation) -> Bool {
        guard let wmController,
              let monitor = wmController.workspaceManager.monitorForWorkspace(mutation.destinationWorkspaceId)
        else {
            return false
        }
        guard wmController.workspaceManager.setActiveWorkspace(
            mutation.destinationWorkspaceId,
            on: monitor.id
        ) else {
            return false
        }
        _ = wmController.workspaceManager.setInteractionMonitor(monitor.id)
        synchronizeStructuralSelection(mutation)
        projection.activeInteractionMonitorId = monitor.id
        projection.setSelectedWindowHandle(mutation.selectedHandle)
        return true
    }

    private func synchronizeStructuralSelection(_ mutation: StructuralMutation) {
        guard let wmController,
              wmController.workspaceManager.workspace(for: mutation.selectedHandle.id)
              == mutation.destinationWorkspaceId,
              wmController.workspaceManager.monitorForWorkspace(mutation.destinationWorkspaceId) != nil
        else {
            return
        }

        _ = wmController.workspaceManager.rememberFocus(
            mutation.selectedHandle.id, in: mutation.destinationWorkspaceId
        )
        if wmController.workspaceManager.activeLayoutKind(for: mutation.destinationWorkspaceId) == .dwindle,
           let engine = wmController.dwindleEngine,
           let node = engine.findNode(for: mutation.selectedHandle.id, in: mutation.destinationWorkspaceId)
        {
            wmController.workspaceManager.withEngineMutationScope(in: mutation.destinationWorkspaceId) {
                engine.setSelectedNode(node, in: mutation.destinationWorkspaceId)
            }
        }
    }

    private func serializesTransfer(_ mutation: StructuralMutation) -> Bool {
        guard mutation.sourceWorkspaceId != mutation.destinationWorkspaceId,
              let wmController
        else {
            return false
        }
        return wmController.workspaceManager.activeLayoutKind(for: mutation.sourceWorkspaceId)
            != wmController.workspaceManager.activeLayoutKind(for: mutation.destinationWorkspaceId)
    }

    private func beginStructuralTransfer() -> UInt64? {
        guard activeStructuralTransferGeneration == nil else { return nil }
        structuralTransferGeneration &+= 1
        activeStructuralTransferGeneration = structuralTransferGeneration
        return structuralTransferGeneration
    }

    private func finishStructuralTransfer(_ generation: UInt64?) {
        guard let generation, activeStructuralTransferGeneration == generation else { return }
        activeStructuralTransferGeneration = nil
    }
}

extension OverviewMutationSession {
}
