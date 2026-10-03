// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics

struct WorkspaceBarMeasurementGeometry: Equatable {
    private struct Item: Equatable {
        let label: String?
        let tiledWindowCounts: [Int]
        let floatingWindowCounts: [Int]
    }

    private struct Scratchpad: Equatable {
        let label: String
        let compact: Bool
        let appIconCount: Int
        let windowCount: Int
    }

    private let items: [Item]
    private let scratchpads: [Scratchpad]
    private let showLabels: Bool
    private let barHeight: CGFloat
    private let vertical: Bool
    private let solidBackground: Bool

    init(snapshot: WorkspaceBarSnapshot, slice: WorkspaceBarIslandSlice) {
        items = slice.items(in: snapshot).map {
            Item(
                label: snapshot.showLabels ? $0.name : nil,
                tiledWindowCounts: $0.tiledWindows.map(\.windowCount),
                floatingWindowCounts: $0.floatingWindows.map(\.windowCount)
            )
        }
        scratchpads = slice.scratchpads(in: snapshot).map {
            Scratchpad(
                label: $0.name,
                compact: $0.presentation == .compact,
                appIconCount: $0.windows.count,
                windowCount: $0.windowCount
            )
        }
        showLabels = snapshot.showLabels
        barHeight = snapshot.barHeight
        vertical = snapshot.orientation.isVertical
        solidBackground = snapshot.backgroundStyle == .solidBlack
    }
}
