// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics

struct Struts: Equatable {
    var left: CGFloat = 0
    var right: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    static let zero = Struts()
}

func computeWorkingArea(parentArea: CGRect, scale: CGFloat, struts: Struts) -> CGRect {
    var workingArea = parentArea
    workingArea.size.width = max(0, workingArea.size.width - struts.left - struts.right)
    workingArea.origin.x += struts.left
    workingArea.size.height = max(0, workingArea.size.height - struts.top - struts.bottom)
    workingArea.origin.y += struts.bottom
    let physicalX = ceil(workingArea.origin.x * scale) / scale
    let physicalY = ceil(workingArea.origin.y * scale) / scale
    let xDiff = min(workingArea.size.width, physicalX - workingArea.origin.x)
    let yDiff = min(workingArea.size.height, physicalY - workingArea.origin.y)
    workingArea.size.width -= xDiff
    workingArea.size.height -= yDiff
    workingArea.origin.x = physicalX
    workingArea.origin.y = physicalY
    return workingArea
}

func normalizedTopStrut(top: CGFloat, menuBarInset: CGFloat, reservedTopInset: CGFloat) -> CGFloat {
    max(0, top - menuBarInset) + reservedTopInset
}
