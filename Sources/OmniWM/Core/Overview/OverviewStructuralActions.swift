// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit

@MainActor
final class OverviewStructuralActions {
    private(set) weak var wmController: WMController?
    let windowFacts: OverviewWindowFacts

    init(wmController: WMController, windowFacts: OverviewWindowFacts) {
        self.wmController = wmController
        self.windowFacts = windowFacts
    }

    func performStructuralHotkey(
        _ command: HotkeyCommand,
        selectedHandle: WindowHandle
    ) -> StructuralMutationOutcome? {
        guard let wmController,
              let entry = windowFacts.visibleManagedEntry(for: selectedHandle),
              windowFacts.isStructurallyMutable(entry)
        else { return .unchanged }
        switch command {
        case .move,
             .dwindle(.moveGroup),
             .windowMovement:
            return .unchanged
        case let .workspace(.moveToMonitor(direction)):
            return wmController.workspaceNavigationHandler.moveWindowToMonitor(
                handle: selectedHandle, direction: direction
            )
        case let .workspace(.moveTo(index)):
            return wmController.workspaceNavigationHandler.moveWindow(
                handle: selectedHandle, toWorkspaceIndex: index
            )
        case .workspace(.moveUp):
            return wmController.workspaceNavigationHandler.moveWindowToAdjacentWorkspace(
                handle: selectedHandle, direction: .up
            )
        case .workspace(.moveDown):
            return wmController.workspaceNavigationHandler.moveWindowToAdjacentWorkspace(
                handle: selectedHandle, direction: .down
            )
        default:
            return nil
        }
    }

    static func isStructuralHotkey(_ command: HotkeyCommand) -> Bool {
        switch command {
        case .move,
             .dwindle(.moveGroup),
             .windowMovement,
             .workspace(.moveToMonitor),
             .workspace(.moveTo),
             .workspace(.moveUp),
             .workspace(.moveDown):
            true
        default:
            false
        }
    }
}
