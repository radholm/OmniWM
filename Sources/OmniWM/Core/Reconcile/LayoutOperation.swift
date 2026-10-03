// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

enum LayoutOperation: Equatable {
    case fullscreenToggled(token: WindowToken)
    case groupMemberMoved(token: WindowToken)
    case groupMembershipChanged(token: WindowToken)
    case interactiveMoveEnded(token: WindowToken)
    case interactiveResizeEnded(token: WindowToken)
    case preselectionChanged
    case sizesBalanced
    case splitOrientationToggled
    case splitRatioChanged
    case splitSwapped
    case tabActivated(token: WindowToken)
    case windowInserted(token: WindowToken)
    case windowMovedToRoot
    case windowMovedToWorkspace(token: WindowToken, to: WorkspaceDescriptor.ID)
    case windowsSwapped

    var summary: String {
        switch self {
        case let .fullscreenToggled(token):
            "fullscreen_toggled token=\(token)"
        case let .groupMemberMoved(token):
            "group_member_moved token=\(token)"
        case let .groupMembershipChanged(token):
            "group_membership_changed token=\(token)"
        case let .interactiveMoveEnded(token):
            "interactive_move_ended token=\(token)"
        case let .interactiveResizeEnded(token):
            "interactive_resize_ended token=\(token)"
        case .preselectionChanged:
            "preselection_changed"
        case .sizesBalanced:
            "sizes_balanced"
        case .splitOrientationToggled:
            "split_orientation_toggled"
        case .splitRatioChanged:
            "split_ratio_changed"
        case .splitSwapped:
            "split_swapped"
        case let .tabActivated(token):
            "tab_activated token=\(token)"
        case let .windowInserted(token):
            "window_inserted token=\(token)"
        case .windowMovedToRoot:
            "window_moved_to_root"
        case let .windowMovedToWorkspace(token, to):
            "window_moved_to_workspace token=\(token) to=\(to.uuidString)"
        case .windowsSwapped:
            "windows_swapped"
        }
    }
}
