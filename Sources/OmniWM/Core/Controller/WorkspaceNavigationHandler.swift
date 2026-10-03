// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

@MainActor
final class WorkspaceNavigationHandler {
    weak var controller: WMController?

    enum WorkspaceMoveFocusPolicy {
        case configured
        case alwaysFollow
        case retainCurrent
    }

    init(controller: WMController) {
        self.controller = controller
    }

    func recordLayoutOperation(
        _ operation: LayoutOperation,
        in workspaceId: WorkspaceDescriptor.ID
    ) {
        controller?.workspaceManager.recordLayoutOperation(operation, in: workspaceId)
    }

    func interactionMonitorId(for controller: WMController) -> Monitor.ID? {
        controller.workspaceManager.interactionMonitorId ?? controller.monitorForInteraction()?.id
    }
}
