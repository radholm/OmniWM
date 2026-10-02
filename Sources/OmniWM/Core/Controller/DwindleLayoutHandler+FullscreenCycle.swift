// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore

/// Pages between fullscreen windows like a carousel: the fullscreen window slides out to one side while the
/// next window slides in from the other side, already at its fullscreen frame.
struct FullscreenSlide: Equatable {
    let workspaceId: WorkspaceDescriptor.ID
    let previousWindowId: Int
    let nextWindowId: Int
    let forward: Bool
    let time: TimeInterval

    /// Snapshot items for the slide. `items` holds the real targets; the two paging windows move off and onto
    /// the screen instead and are drawn above the other (covered) windows.
    func items(from items: [WindowSnapshotTransition.Item]) -> [WindowSnapshotTransition.Item] {
        guard let previous = items.first(where: { $0.windowId == previousWindowId }),
              let next = items.first(where: { $0.windowId == nextWindowId })
        else { return items }
        let fullscreen = next.to
        let shift = fullscreen.width * (forward ? 1 : -1)
        let others = items.filter { $0.windowId != previousWindowId && $0.windowId != nextWindowId }
        return others + [
            .init(windowId: previousWindowId, from: previous.from, to: previous.from.offsetBy(dx: -shift, dy: 0)),
            .init(windowId: nextWindowId, from: fullscreen.offsetBy(dx: shift, dy: 0), to: fullscreen)
        ]
    }
}

extension DwindleLayoutHandler {
    static let fullscreenSlideArmWindow: TimeInterval = 1.0

    /// Makes the next window of the active workspace fullscreen instead of the current fullscreen window.
    /// Returns `false` when no window is fullscreen, so the caller can fall back to its regular action.
    @discardableResult
    func cycleFullscreen(forward: Bool = true) -> Bool {
        guard let controller else { return false }
        var cycled = false
        withDwindleContext { engine, wsId in
            guard let cycle = engine.cycleFullscreen(
                in: wsId,
                forward: forward,
                canFocus: { !controller.isManagedWindowSuppressedByMacOS($0) }
            ) else { return }
            cycled = true
            recordLayoutOperation(.fullscreenToggled(token: cycle.previous), in: wsId)
            recordLayoutOperation(.fullscreenToggled(token: cycle.next), in: wsId)
            fullscreenSlideArm = FullscreenSlide(
                workspaceId: wsId,
                previousWindowId: cycle.previous.windowId,
                nextWindowId: cycle.next.windowId,
                forward: forward,
                time: CACurrentMediaTime()
            )
            _ = controller.workspaceManager.applySessionPatch(
                .init(
                    workspaceId: wsId,
                    viewportState: nil,
                    rememberedFocusToken: cycle.next,
                    plannedSeq: controller.workspaceManager.worldSeq
                )
            )
            controller.focusWindow(cycle.next)
            controller.layoutRefreshController.requestLayoutCommandRelayout(affectedWorkspaceIds: [wsId])
        }
        return cycled
    }

    func consumeFullscreenSlideArm(for workspaceId: WorkspaceDescriptor.ID) -> FullscreenSlide? {
        guard let slide = fullscreenSlideArm, slide.workspaceId == workspaceId else { return nil }
        fullscreenSlideArm = nil
        return CACurrentMediaTime() - slide.time < Self.fullscreenSlideArmWindow ? slide : nil
    }
}
