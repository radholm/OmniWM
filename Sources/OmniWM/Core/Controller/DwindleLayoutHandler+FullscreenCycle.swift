// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore

/// Pages through fullscreen windows like a deck of cards: every window is stacked at the fullscreen frame.
/// During the page turn the view zooms out to the whole deck, fanned towards the bottom right; the top window
/// moves to the back of the deck, and the view zooms back in on the next window.
struct FullscreenSlide: Equatable {
    let workspaceId: WorkspaceDescriptor.ID
    let previousWindowId: Int
    let nextWindowId: Int
    /// Window ids in paging order from the next window on, ending with the previous one.
    var deckWindowIds: [Int] = []
    let forward: Bool
    let time: TimeInterval

    /// Paging is a deliberate, visible motion, so it runs longer than regular layout snapshot transitions.
    static let duration: CFTimeInterval = 0.85

    /// Snapshot items for the page turn. `items` holds the real targets; the deck's windows instead stay at
    /// their fullscreen frame and move between deck depths, drawn above any other (floating) windows.
    func items(from items: [WindowSnapshotTransition.Item]) -> [WindowSnapshotTransition.Item] {
        let deck = deckWindowIds.isEmpty ? [nextWindowId, previousWindowId] : deckWindowIds
        let byId = Dictionary(items.map { ($0.windowId, $0) }, uniquingKeysWith: { first, _ in first })
        guard deck.last == previousWindowId, deck.first == nextWindowId,
              deck.allSatisfy({ byId[$0] != nil })
        else { return items }
        let others = items.filter { !deck.contains($0.windowId) }
        let cards = deck.enumerated().reversed().map { index, windowId -> WindowSnapshotTransition.Item in
            let frame = byId[windowId]?.from ?? .zero
            let effect = windowId == previousWindowId
                ? SnapshotStackEffect(fromDepth: 0, toDepth: index, deckSize: deck.count, tucksUnder: true)
                : SnapshotStackEffect(fromDepth: index + 1, toDepth: index, deckSize: deck.count)
            return .init(windowId: windowId, from: frame, to: frame, stackEffect: effect)
        }
        return others + cards
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
                deckWindowIds: cycle.deck.map(\.windowId),
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
