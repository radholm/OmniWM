// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore

extension WorkspaceManager {
    func activeLayoutKind(for _: WorkspaceDescriptor.ID) -> ActiveLayoutKind {
        .dwindle
    }

    func isInactiveTabMember(_ token: WindowToken, in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        switch activeLayoutKind(for: workspaceId) {
        case .dwindle:
            return dwindleEngine?.isInactiveGroupMember(token, in: workspaceId) == true
        }
    }

    func reconcileSnapshot() -> ReconcileSnapshot {
        var snapshot = reconcileReductionSnapshot()
        populateReconcileLayouts(&snapshot)
        return snapshot
    }

    func reconcileReductionSnapshot() -> ReconcileSnapshot {
        let entries = windowQueries.allEntries()
        var windowOrder: [ReconcileWindowOrder] = []
        windowOrder.reserveCapacity(entries.count)
        for index in entries.indices {
            let entry = entries[index]
            windowOrder.append(ReconcileWindowOrder(index: index, workspaceId: entry.workspaceId, token: entry.token))
        }
        windowOrder.sort(by: Self.reconcileWindowPrecedes)

        var windowSnapshots: [ReconcileWindowSnapshot] = []
        windowSnapshots.reserveCapacity(entries.count)
        for item in windowOrder {
            let entry = entries[item.index]
            windowSnapshots.append(ReconcileWindowSnapshot(
                token: entry.token,
                workspaceId: entry.workspaceId,
                mode: entry.mode,
                lifecyclePhase: entry.lifecyclePhase,
                observedState: entry.observedState,
                desiredState: entry.desiredState,
                restoreIntent: entry.restoreIntent,
                lifetimeAuthority: entry.lifetimeAuthority
            ))
        }

        return ReconcileSnapshot(
            topologyProfile: currentTopologyProfile(),
            focusSession: focusSessionSnapshot,
            windows: windowSnapshots
        )
    }

    func populateReconcileLayouts(_ snapshot: inout ReconcileSnapshot) {
        var workspaceIds: Set<WorkspaceDescriptor.ID> = []
        do {
            let windows = snapshot.windows.span
            workspaceIds.reserveCapacity(min(windows.count, workspaceCatalog.count))
            for index in 0 ..< windows.count {
                workspaceIds.insert(windows[index].workspaceId)
            }
        }
        var layouts: [WorkspaceDescriptor.ID: LayoutTopology] = [:]
        for workspaceId in workspaceIds {
            let topology = layoutTopology(for: workspaceId)
            if !topology.dwindleFullscreenTokens.isEmpty {
                layouts[workspaceId] = topology
            }
        }
        snapshot.layouts = layouts
    }

    private struct ReconcileWindowOrder {
        let index: Int
        let workspaceId: WorkspaceDescriptor.ID
        let token: WindowToken
    }

    private nonisolated static func reconcileWindowPrecedes(
        _ lhs: ReconcileWindowOrder,
        _ rhs: ReconcileWindowOrder
    ) -> Bool {
        lhs.workspaceId == rhs.workspaceId
            ? (lhs.token.pid == rhs.token.pid
                ? lhs.token.windowId < rhs.token.windowId
                : lhs.token.pid < rhs.token.pid)
            : lhs.workspaceId < rhs.workspaceId
    }

    func reconcileSnapshotDump() -> String {
        ReconcileDebugDump.snapshot(reconcileSnapshot())
    }
}
