// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit

extension WorkspaceSwipePresentation {
    func windowRemoved(_ token: WindowToken) {
        preview?.remove(token: token)
    }

    func syncAvailability() {
        guard let controller, preview != nil,
              !controller.motionPolicy.animationsEnabled || !controller.settings.gestures.workspaceSwipeEnabled
        else { return }
        cancel(reason: "disabled")
        preview?.release()
        preview = nil
    }

    func previewSurface(_ controller: WMController) -> WorkspaceSwipePreview {
        if let preview { return preview }
        let preview = WorkspaceSwipePreview(ownedWindowRegistry: controller.ownedWindowRegistry)
        preview.animationSpeed = { [weak controller] in controller?.motionPolicy.animationSpeed ?? 1 }
        self.preview = preview
        return preview
    }
}
