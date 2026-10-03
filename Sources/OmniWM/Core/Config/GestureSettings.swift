// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon
import Foundation
import OmniWMIPC

@MainActor @Observable
final class GestureSettings {
    private nonisolated static let defaults = SettingsExport.Gestures.defaults()
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var isApplying = false

    nonisolated static let windowGestureSensitivityRange = 0.1 ... 5.0
    nonisolated static let workspaceSwipeSensitivityRange = 0.5 ... 4.0
    nonisolated static let workspaceWallpaperParallaxAmountRange = 0.02 ... 0.5

    var mouseMoveModifierKey = GestureSettings.defaults.mouseMoveModifierKey {
        didSet { notifyChange() }
    }

    var mouseResizeModifierKey = GestureSettings.defaults.mouseResizeModifierKey {
        didSet { notifyChange() }
    }

    var invertDirection = GestureSettings.defaults.invertDirection {
        didSet { notifyChange() }
    }

    var workspaceSwipeEnabled = GestureSettings.defaults.workspaceSwipeEnabled {
        didSet {
            guard oldValue != workspaceSwipeEnabled else { return }
            notifyChange()
        }
    }

    var workspaceSwipeFingerCount = GestureSettings.defaults.workspaceSwipeFingerCount {
        didSet { notifyChange() }
    }

    var workspaceSwipeAxis = GestureSettings.defaults.workspaceSwipeAxis {
        didSet { notifyChange() }
    }

    var overviewGestureEnabled = GestureSettings.defaults.overviewGestureEnabled ?? false {
        didSet {
            guard oldValue != overviewGestureEnabled else { return }
            notifyChange()
        }
    }

    var overviewGestureFingerCount = GestureSettings.defaults.overviewGestureFingerCount ?? .four {
        didSet { notifyChange() }
    }

    var windowMoveEnabled = GestureSettings.defaults.windowMoveEnabled ?? false {
        didSet {
            guard oldValue != windowMoveEnabled else { return }
            notifyChange()
        }
    }

    var windowMoveFingerCount = GestureSettings.defaults.windowMoveFingerCount ?? .four {
        didSet { notifyChange() }
    }

    var windowResizeEnabled = GestureSettings.defaults.windowResizeEnabled ?? false {
        didSet {
            guard oldValue != windowResizeEnabled else { return }
            notifyChange()
        }
    }

    var windowResizeFingerCount = GestureSettings.defaults.windowResizeFingerCount ?? .three {
        didSet { notifyChange() }
    }

    var windowGestureSensitivity = GestureSettings.defaults.windowGestureSensitivity ?? 1.0 {
        didSet {
            let range = GestureSettings.windowGestureSensitivityRange
            let normalized = windowGestureSensitivity.isFinite
                ? min(max(windowGestureSensitivity, range.lowerBound), range.upperBound)
                : GestureSettings.defaults.windowGestureSensitivity ?? 1.0
            guard normalized == windowGestureSensitivity else {
                windowGestureSensitivity = normalized
                return
            }
            notifyChange()
        }
    }

    var workspaceSwipeSensitivity = GestureSettings.defaults.workspaceSwipeSensitivity ?? 1.0 {
        didSet {
            let range = GestureSettings.workspaceSwipeSensitivityRange
            let normalized = workspaceSwipeSensitivity.isFinite
                ? min(max(workspaceSwipeSensitivity, range.lowerBound), range.upperBound)
                : GestureSettings.defaults.workspaceSwipeSensitivity ?? 1.0
            guard normalized == workspaceSwipeSensitivity else {
                workspaceSwipeSensitivity = normalized
                return
            }
            notifyChange()
        }
    }

    var workspaceWallpaperParallax = GestureSettings.defaults.workspaceWallpaperParallax ?? true {
        didSet {
            guard oldValue != workspaceWallpaperParallax else { return }
            notifyChange()
        }
    }

    var mouseEdgeDragResize = GestureSettings.defaults.mouseEdgeDragResize ?? true {
        didSet {
            guard oldValue != mouseEdgeDragResize else { return }
            notifyChange()
        }
    }

    var mouseTitleBarDragSwap = GestureSettings.defaults.mouseTitleBarDragSwap ?? true {
        didSet {
            guard oldValue != mouseTitleBarDragSwap else { return }
            notifyChange()
        }
    }

    var workspaceWallpaperParallaxAmount = GestureSettings.defaults.workspaceWallpaperParallaxAmount ?? 0.1 {
        didSet {
            let range = GestureSettings.workspaceWallpaperParallaxAmountRange
            let normalized = workspaceWallpaperParallaxAmount.isFinite
                ? min(max(workspaceWallpaperParallaxAmount, range.lowerBound), range.upperBound)
                : GestureSettings.defaults.workspaceWallpaperParallaxAmount ?? 0.1
            guard normalized == workspaceWallpaperParallaxAmount else {
                workspaceWallpaperParallaxAmount = normalized
                return
            }
            guard oldValue != workspaceWallpaperParallaxAmount else { return }
            notifyChange()
        }
    }

    func export() -> SettingsExport.Gestures {
        SettingsExport.Gestures(
            mouseMoveModifierKey: mouseMoveModifierKey,
            mouseResizeModifierKey: mouseResizeModifierKey,
            invertDirection: invertDirection,
            workspaceSwipeEnabled: workspaceSwipeEnabled,
            workspaceSwipeFingerCount: workspaceSwipeFingerCount,
            workspaceSwipeAxis: workspaceSwipeAxis,
            overviewGestureEnabled: overviewGestureEnabled,
            overviewGestureFingerCount: overviewGestureFingerCount,
            windowMoveEnabled: windowMoveEnabled,
            windowMoveFingerCount: windowMoveFingerCount,
            windowResizeEnabled: windowResizeEnabled,
            windowResizeFingerCount: windowResizeFingerCount,
            windowGestureSensitivity: windowGestureSensitivity,
            workspaceSwipeSensitivity: workspaceSwipeSensitivity,
            workspaceWallpaperParallax: workspaceWallpaperParallax,
            workspaceWallpaperParallaxAmount: workspaceWallpaperParallaxAmount,
            mouseEdgeDragResize: mouseEdgeDragResize,
            mouseTitleBarDragSwap: mouseTitleBarDragSwap
        )
    }

    private func notifyChange() {
        guard !isApplying else { return }
        onChange?()
    }

    func apply(_ gestures: SettingsExport.Gestures) {
        let previous = export()
        isApplying = true
        mouseMoveModifierKey = gestures.mouseMoveModifierKey
        mouseResizeModifierKey = gestures.mouseResizeModifierKey
        invertDirection = gestures.invertDirection
        workspaceSwipeEnabled = gestures.workspaceSwipeEnabled
        workspaceSwipeFingerCount = gestures.workspaceSwipeFingerCount
        workspaceSwipeAxis = gestures.workspaceSwipeAxis
        overviewGestureEnabled = gestures.overviewGestureEnabled ?? false
        overviewGestureFingerCount = gestures.overviewGestureFingerCount ?? .four
        windowMoveEnabled = gestures.windowMoveEnabled ?? false
        windowMoveFingerCount = gestures.windowMoveFingerCount ?? .four
        windowResizeEnabled = gestures.windowResizeEnabled ?? false
        windowResizeFingerCount = gestures.windowResizeFingerCount ?? .three
        windowGestureSensitivity = gestures.windowGestureSensitivity ?? 1.0
        workspaceSwipeSensitivity = gestures.workspaceSwipeSensitivity ?? 1.0
        workspaceWallpaperParallax = gestures.workspaceWallpaperParallax ?? true
        workspaceWallpaperParallaxAmount = gestures.workspaceWallpaperParallaxAmount ?? 0.1
        mouseEdgeDragResize = gestures.mouseEdgeDragResize ?? true
        mouseTitleBarDragSwap = gestures.mouseTitleBarDragSwap ?? true
        isApplying = false
        if export() != previous {
            notifyChange()
        }
    }
}
