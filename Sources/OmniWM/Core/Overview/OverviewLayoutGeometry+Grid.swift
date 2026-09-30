// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension OverviewLayoutGeometry {
    struct GridArrangement: Equatable {
        let columns: Int
        let scale: CGFloat
        let cellWidth: CGFloat
        let rowHeight: CGFloat
        let originX: CGFloat
    }

    var gridGap: CGFloat {
        scaledWorkspaceSectionPadding * 2
    }

    /// Picks the column count that shows `count` workspace cells as large as possible without scrolling,
    /// never larger than the regular list previews.
    func gridArrangement(count: Int) -> GridArrangement {
        let count = max(count, 1)
        let availableHeight = max(1, initialContentY - screenFrame.minY - contentBottomPadding)
        let chrome = scaledWorkspaceLabelHeight + scaledWorkspaceSectionPadding
        let width = max(screenFrame.width, 1)
        let height = max(screenFrame.height, 1)
        var best = (columns: 1, scale: CGFloat(0))
        for columns in 1 ... count {
            let rows = (count + columns - 1) / columns
            let widthScale = (availableWidth - gridGap * CGFloat(columns - 1)) / CGFloat(columns) / width
            let heightScale = ((availableHeight + gridGap) / CGFloat(rows) - gridGap - chrome) / height
            let scale = min(widthScale, heightScale, stripScale)
            if scale > best.scale + 0.0001 { best = (columns, scale) }
        }
        let scale = max(best.scale, 0.05)
        let cellWidth = width * scale
        let totalWidth = cellWidth * CGFloat(best.columns) + gridGap * CGFloat(best.columns - 1)
        return GridArrangement(
            columns: best.columns,
            scale: scale,
            cellWidth: cellWidth,
            rowHeight: chrome + height * scale + gridGap,
            originX: screenFrame.midX - totalWidth / 2
        )
    }

    /// Geometry and top edge of grid cell `index`, filled left to right, then top to bottom.
    func gridCell(_ index: Int, in grid: GridArrangement) -> (geometry: OverviewLayoutGeometry, top: CGFloat) {
        let row = index / grid.columns
        let column = index % grid.columns
        let minX = grid.originX + CGFloat(column) * (grid.cellWidth + gridGap)
        return (
            cell(minX: minX, width: grid.cellWidth, scale: grid.scale),
            initialContentY - CGFloat(row) * grid.rowHeight
        )
    }
}
