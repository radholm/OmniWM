// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

struct WorkspaceBarDragSource: Equatable {
    let tokens: [WindowToken]
    let workspaceId: WorkspaceDescriptor.ID
    let isFloating: Bool
}

struct WorkspaceBarDropGeometry: Equatable {
    struct Icon: Equatable {
        let tokens: [WindowToken]
        let frame: CGRect
        let appName: String
    }

    struct Workspace: Equatable {
        let id: WorkspaceDescriptor.ID
        let name: String
        let hitFrame: CGRect
        let icons: [Icon]
        var orientation: WorkspaceBarOrientation = .horizontal
    }

    let workspaces: [Workspace]
}

enum WorkspaceBarDropAction: Equatable {
    case dwindleSwap(WorkspaceDescriptor.ID, target: WindowToken)
    case moveToWorkspace(WorkspaceDescriptor.ID)
    case noOp
    case cancel
}

enum WorkspaceBarDropHighlight: Equatable {
    case workspace(WorkspaceDescriptor.ID)
    case icon(WorkspaceDescriptor.ID, WindowToken)
}

struct WorkspaceBarDropResolution: Equatable {
    let action: WorkspaceBarDropAction
    let label: String
    let highlights: [WorkspaceBarDropHighlight]

    static let cancelled = WorkspaceBarDropResolution(
        action: .cancel, label: String(localized: "Can’t drop here"), highlights: []
    )
}

enum WorkspaceBarDropResolver {
    static func resolve(
        source: WorkspaceBarDragSource,
        at point: CGPoint,
        in geometry: WorkspaceBarDropGeometry
    ) -> WorkspaceBarDropResolution {
        guard let workspace = geometry.workspaces.first(where: { $0.hitFrame.contains(point) }) else {
            return .cancelled
        }
        guard workspace.id == source.workspaceId else {
            return WorkspaceBarDropResolution(
                action: .moveToWorkspace(workspace.id),
                label: String(localized: "Move to \(workspace.name)"),
                highlights: [.workspace(workspace.id)]
            )
        }
        guard !source.isFloating, source.tokens.count == 1, let token = source.tokens.first,
              let icon = workspace.icons.first(where: { $0.frame.contains(point) }),
              icon.tokens.count == 1, let target = icon.tokens.first, target != token
        else {
            return WorkspaceBarDropResolution(
                action: .noOp, label: "", highlights: []
            )
        }
        return WorkspaceBarDropResolution(
            action: .dwindleSwap(workspace.id, target: target),
            label: String(localized: "Swap with \(icon.appName)"),
            highlights: [.workspace(workspace.id), .icon(workspace.id, target)]
        )
    }
}
