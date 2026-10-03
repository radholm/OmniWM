// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension WMController {
    func canDragWorkspaceBarWindow(_ token: WindowToken) -> Bool {
        guard let entry = workspaceManager.entry(for: token) else { return false }
        return entry.layoutReason == .standard
            && !workspaceManager.isWindowSuppressedByMacOS(token)
            && !isManagedWindowSuspendedForNativeFullscreen(token)
    }

    @discardableResult
    func commitWorkspaceBarDrop(_ action: WorkspaceBarDropAction, source: WorkspaceBarDragSource) -> Bool {
        switch action {
        case let .moveToWorkspace(workspaceId):
            return workspaceNavigationHandler.moveWindowsFromBar(source.tokens, toWorkspaceId: workspaceId)
        case let .dwindleSwap(workspaceId, target):
            guard source.tokens.count == 1,
                  let token = source.tokens.first,
                  workspaceManager.entry(for: token)?.workspaceId == workspaceId
            else { return false }
            return dwindleLayoutHandler.swapWindows(token, with: target, in: workspaceId)
        case .noOp,
             .cancel:
            return false
        }
    }
}
