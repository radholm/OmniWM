// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore

/// Pages through fullscreen windows like a stack of cards: every window is stacked at the fullscreen frame,
/// the top one slides off to one side and the next one, already in place underneath, settles forward.
struct FullscreenSlide: Equatable {
    let workspaceId: WorkspaceDescriptor.ID
    let previousWindowId: Int
    let nextWindowId: Int
    let forward: Bool
    let time: TimeInterval

    /// How far the next card sits back in the stack before it settles forward, as a fraction of its size.
    static let stackDepth: CGFloat = 0.04

    /// Snapshot items for the slide, bottom to top. `items` holds the real targets: the previous window, on top,
    /// slides off the screen instead, revealing the next window right underneath it.
    func items(from items: [WindowSnapshotTransition.Item]) -> [WindowSnapshotTransition.Item] {
        guard let previous = items.first(where: { $0.windowId == previousWindowId }),
              let next = items.first(where: { $0.windowId == nextWindowId })
        else { return items }
        let fullscreen = next.to
        let shift = fullscreen.width * (forward ? 1 : -1)
        let behind = fullscreen.insetBy(
            dx: fullscreen.width * Self.stackDepth / 2,
            dy: fullscreen.height * Self.stackDepth / 2
        )
        let others = items.filter { $0.windowId != previousWindowId && $0.windowId != nextWindowId }
        return others + [
            .init(windowId: nextWindowId, from: behind, to: fullscreen),
            .init(windowId: previousWindowId, from: previous.from, to: previous.from.offsetBy(dx: -shift, dy: 0))
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

    /// A window activated from the fullscreen stack (Command+Tab, Dock) becomes the fullscreen one.
    func handOffFullscreen(
        to token: WindowToken,
        engine: DwindleLayoutEngine,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard let previous = engine.moveFullscreen(to: token, in: workspaceId) else { return false }
        recordLayoutOperation(.fullscreenToggled(token: previous), in: workspaceId, source: .focusPolicy)
        return true
    }

    func consumeFullscreenSlideArm(for workspaceId: WorkspaceDescriptor.ID) -> FullscreenSlide? {
        guard let slide = fullscreenSlideArm, slide.workspaceId == workspaceId else { return nil }
        fullscreenSlideArm = nil
        return CACurrentMediaTime() - slide.time < Self.fullscreenSlideArmWindow ? slide : nil
    }
}
