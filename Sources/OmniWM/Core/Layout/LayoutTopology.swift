// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

enum ActiveLayoutKind: Equatable {
    case dwindle
}

struct LayoutTopology: Equatable {
    var dwindleFullscreenTokens: Set<WindowToken> = []
}

extension LayoutTopology {
    func isFullscreen(_ token: WindowToken) -> Bool {
        dwindleFullscreenTokens.contains(token)
    }
}
