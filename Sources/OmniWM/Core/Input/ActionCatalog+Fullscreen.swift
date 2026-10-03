// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import OmniWMIPC

extension ActionCatalog {
    static func appendFullscreenBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            IPCFullscreenCommand.managed.actionSpec(),
            IPCFullscreenCommand.native.actionSpec()
        ])
    }
}
