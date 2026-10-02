// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore

/// Pages through fullscreen windows like a stack of cards: every window is stacked at the fullscreen frame,
/// the top one tips back and fades away while the next one, already in place underneath, rises up and fades in.
struct FullscreenSlide: Equatable {
    let workspaceId: WorkspaceDescriptor.ID
    let previousWindowId: Int
    let nextWindowId: Int
    let forward: Bool
    let time: TimeInterval

    /// Paging is a deliberate, visible motion, so it runs longer than regular layout snapshot transitions.
    static let duration: CFTimeInterval = 0.55

    /// Snapshot items for the page turn, bottom to top. `items` holds the real targets: the previous window,
    /// on top, tips back and fades out, while the next window underneath rises up and fades in.
    func items(from items: [WindowSnapshotTransition.Item]) -> [WindowSnapshotTransition.Item] {
        guard let previous = items.first(where: { $0.windowId == previousWindowId }),
              let next = items.first(where: { $0.windowId == nextWindowId })
        else { return items }
        let others = items.filter { $0.windowId != previousWindowId && $0.windowId != nextWindowId }
        return others + [
            .init(windowId: nextWindowId, from: next.to, to: next.to, stackEffect: .in),
            .init(windowId: previousWindowId, from: previous.from, to: previous.from, stackEffect: .out)
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
            // Raise the next window only once the slide overlay covers the stack, so it doesn't flash on top first.
            let next = cycle.next
            controller.layoutRefreshController.requestLayoutCommandRelayout(
                affectedWorkspaceIds: [wsId],
                postLayout: { [weak controller] in controller?.focusWindow(next) }
            )
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
