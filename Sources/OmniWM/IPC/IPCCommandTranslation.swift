// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import OmniWMIPC

extension HotkeyCommand {
    init?(ipc command: IPCFocusCommand) {
        switch command {
        case let .spatial(ipcDirection):
            self = .focus(Direction(ipc: ipcDirection))
        case .previous:
            self = .focusNavigation(.previous)
        case .windowDownOrTop:
            self = .focusNavigation(.windowDownOrTop)
        case .windowUpOrBottom:
            self = .focusNavigation(.windowUpOrBottom)
        }
    }

    init(ipc command: IPCWindowMovementCommand) {
        switch command {
        case let .spatial(ipcDirection):
            self = .move(Direction(ipc: ipcDirection))
        case .down:
            self = .windowMovement(.down)
        case .up:
            self = .windowMovement(.up)
        }
    }

    init(ipc command: IPCDwindleCommand) {
        switch command {
        case .cycleSizeForward:
            self = .sizing(.cycleSizeForward)
        case .cycleSizeBackward:
            self = .sizing(.cycleSizeBackward)
        case .balanceSizes:
            self = .sizing(.balanceSizes)
        case .moveToRoot:
            self = .dwindle(.moveToRoot)
        case let .moveGroup(direction):
            self = .dwindle(.moveGroup(Direction(ipc: direction)))
        case .toggleSplit:
            self = .dwindle(.toggleSplit)
        case .swapSplit:
            self = .dwindle(.swapSplit)
        case let .resize(axis, operation):
            self = .dwindle(.resizeAlongAxis(DwindleOrientation(ipc: axis), operation == .grow))
        case let .resizeFocused(operation):
            self = .dwindle(.resizeFocusedWindow(operation == .grow))
        case let .preselect(ipcDirection):
            self = .dwindle(.preselect(Direction(ipc: ipcDirection)))
        case .preselectClear:
            self = .dwindle(.preselectClear)
        }
    }

    init(ipc command: IPCScratchpadCommand) {
        switch command {
        case let .assign(index):
            self = .scratchpad(.assign(index))
        case let .toggle(index):
            self = .scratchpad(.toggle(index))
        }
    }

    private static func zeroBasedIndex(from oneBasedValue: Int) -> Int? {
        guard oneBasedValue > 0 else { return nil }
        return oneBasedValue - 1
    }
}

extension Direction {
    init(ipc value: IPCDirection) {
        switch value {
        case .left:
            self = .left
        case .right:
            self = .right
        case .up:
            self = .up
        case .down:
            self = .down
        }
    }
}

extension DwindleOrientation {
    init(ipc axis: IPCResizeAxis) {
        switch axis {
        case .horizontal:
            self = .horizontal
        case .vertical:
            self = .vertical
        }
    }
}

extension LayoutType {
    init(ipc value: IPCWorkspaceLayout) {
        switch value {
        case .defaultLayout:
            self = .defaultLayout
        case .dwindle:
            self = .dwindle
        }
    }
}
