// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import QuartzCore

/// Pages the fullscreen stack with a trackpad swipe, the way the workspace swipe switches workspaces: the page
/// turn follows the fingers and, on release (or a flick), settles on the next window or back on the current one.
/// The stack only pages once the page turn has settled on the next window.
@MainActor
final class FullscreenStackGesturePresentation {
    private final class Flight {
        let slide: FullscreenSlide
        let items: [WindowSnapshotTransition.Item]
        let monitor: Monitor
        let inputSign: Double
        let motion: WorkspaceSwipeMotion
        let beganAt: TimeInterval
        /// Whether the page turn can be drawn; without it, the swipe still pages the stack on release.
        var canShow: Bool
        var shown = false

        init(
            slide: FullscreenSlide,
            items: [WindowSnapshotTransition.Item],
            monitor: Monitor,
            cumulative: Double,
            timestamp: TimeInterval,
            recognitionMovement: SwipeEvent?,
            beganAt: TimeInterval
        ) {
            self.slide = slide
            self.items = items
            self.monitor = monitor
            self.beganAt = beganAt
            canShow = items.contains { $0.stackEffect != nil }
            let sign: Double = cumulative < 0 ? -1 : 1
            inputSign = sign
            motion = WorkspaceSwipeMotion(
                cumulativeUnits: abs(cumulative),
                timestamp: timestamp,
                recognitionMovement: recognitionMovement.map {
                    SwipeEvent(delta: $0.delta * sign, timestamp: $0.timestamp)
                },
                springConfig: FullscreenStackGesturePresentation.springConfig
            )
        }
    }

    @MainActor
    private final class DisplayLinkTarget: NSObject {
        let onTick: @MainActor () -> Void

        init(onTick: @escaping @MainActor () -> Void) {
            self.onTick = onTick
        }

        @objc func tick(_: CADisplayLink) {
            onTick()
        }
    }

    /// Softer than the workspace swipe's spring, so the page turn stays visible while it settles.
    nonisolated static let springConfig = SpringConfig(
        dampingRatio: 1,
        stiffness: 140,
        epsilon: 0.0001,
        velocityEpsilon: 0.01
    )
    /// How long a recognized swipe waits for the background capture before capturing on the main thread.
    static let prefetchWait: TimeInterval = 0.06
    /// Captured stack windows are reused for the next swipe this long; fresh captures replace them when ready.
    static let imageCacheLifetime: TimeInterval = 30

    private weak var handler: DwindleLayoutHandler?
    private var flight: Flight?
    private var preparedWorkspaceId: WorkspaceDescriptor.ID?
    private var prefetchedImages: [Int: CGImage] = [:]
    private var prefetchTask: Task<Void, Never>?
    private var cachedImages: [Int: CGImage] = [:]
    private var cachedWorkspaceId: WorkspaceDescriptor.ID?
    private var cachedAt: TimeInterval = 0
    private var displayLink: CADisplayLink?
    private let mediaTimeProvider: () -> TimeInterval

    init(handler: DwindleLayoutHandler, mediaTimeProvider: @escaping () -> TimeInterval = CACurrentMediaTime) {
        self.handler = handler
        self.mediaTimeProvider = mediaTimeProvider
    }

    var hasPresentation: Bool {
        flight != nil
    }

    /// Whether a swipe on `workspaceId` can page its fullscreen stack.
    func canPage(workspaceId: WorkspaceDescriptor.ID) -> Bool {
        handler?.peekFullscreenSlide(in: workspaceId, forward: true) != nil
    }

    /// Captures the stacked windows off the main thread as soon as fingers touch, before the swipe is recognized.
    /// Recent captures of the same workspace are used meanwhile, so a quick swipe doesn't wait for them.
    func prepare(workspaceId: WorkspaceDescriptor.ID) {
        guard flight == nil, let handler, handler.snapshotTransitionsEnabled else { return }
        prefetchTask?.cancel()
        preparedWorkspaceId = workspaceId
        let now = mediaTimeProvider()
        prefetchedImages = cachedWorkspaceId == workspaceId && now - cachedAt < Self.imageCacheLifetime
            ? cachedImages : [:]
        let windowIds = handler.snapshotItems(workspaceId: workspaceId, targets: [:]).map(\.windowId)
        prefetchTask = Task { @MainActor [weak self, weak handler] in
            guard let handler else { return }
            let images = await handler.snapshotTransition.prefetchImages(for: windowIds)
            guard !Task.isCancelled, let self, preparedWorkspaceId == workspaceId else { return }
            prefetchedImages.merge(images) { _, fresh in fresh }
            cachedImages = prefetchedImages
            cachedWorkspaceId = workspaceId
            cachedAt = mediaTimeProvider()
            prefetchTask = nil
            if let flight, flight.canShow, !flight.shown, flight.motion.target == nil { show(flight) }
        }
    }

    /// Starts scrubbing the page turn; `cumulative` is the swipe distance along its axis when recognized.
    @discardableResult
    func begin(
        workspaceId: WorkspaceDescriptor.ID,
        forward: Bool,
        cumulative: Double,
        timestamp: TimeInterval,
        recognitionMovement: SwipeEvent?
    ) -> Bool {
        guard flight == nil, let handler,
              let monitor = handler.controller?.workspaceManager.monitor(for: workspaceId),
              let slide = handler.peekFullscreenSlide(in: workspaceId, forward: forward)
        else { return false }
        let items = handler.snapshotTransitionsEnabled
            ? slide.items(from: handler.snapshotItems(workspaceId: workspaceId, targets: [:])) : []
        let flight = Flight(
            slide: slide,
            items: items,
            monitor: monitor,
            cumulative: cumulative,
            timestamp: timestamp,
            recognitionMovement: recognitionMovement,
            beganAt: mediaTimeProvider()
        )
        self.flight = flight
        if flight.canShow, prefetchTask == nil || preparedWorkspaceId != workspaceId { show(flight) }
        return true
    }

    @discardableResult
    func update(cumulative: Double, timestamp: TimeInterval) -> Bool {
        guard let flight, flight.motion.target == nil else { return false }
        flight.motion.update(cumulativeUnits: cumulative * flight.inputSign, timestamp: timestamp)
        if flight.canShow, !flight.shown, mediaTimeProvider() - flight.beganAt >= Self.prefetchWait {
            showNow(flight)
        }
        present(flight, at: mediaTimeProvider())
        return true
    }

    /// Settles the page turn on the next window or back; returns `false` when no page turn is being scrubbed.
    /// When the page turn couldn't be drawn, the stack still pages if the swipe went far or fast enough.
    @discardableResult
    func release(timestamp: TimeInterval, allowFlick: Bool) -> Bool {
        guard let flight else { return false }
        guard flight.motion.target == nil else { return true }
        if flight.canShow, !flight.shown { showNow(flight) }
        guard flight.motion.release(
            timestamp: timestamp,
            allowFlick: allowFlick,
            animationTime: mediaTimeProvider(),
            motion: handler?.controller?.motionPolicy.snapshot() ?? .enabled
        ) else {
            end(paging: false)
            return true
        }
        if flight.shown {
            startDisplayLink(for: flight.monitor)
        } else {
            end(paging: flight.motion.target == 1)
        }
        return true
    }

    /// Abandons the swipe: a shown page turn settles back, so the stack is left as it was.
    func cancel() {
        guard let flight else {
            prefetchTask?.cancel()
            prefetchTask = nil
            preparedWorkspaceId = nil
            prefetchedImages = [:]
            return
        }
        guard flight.motion.target == nil else { return }
        if flight.shown, flight.motion.animate(
            to: 0,
            animationTime: mediaTimeProvider(),
            motion: handler?.controller?.motionPolicy.snapshot() ?? .enabled
        ) {
            startDisplayLink(for: flight.monitor)
        } else {
            end(paging: false)
        }
    }

    /// Shows the page turn without waiting any longer for the background capture.
    private func showNow(_ flight: Flight) {
        prefetchTask?.cancel()
        prefetchTask = nil
        show(flight)
    }

    private func show(_ flight: Flight) {
        guard let handler, self.flight === flight else { return }
        guard handler.snapshotTransition.begin(
            items: flight.items,
            monitor: flight.monitor,
            animated: false,
            prefetched: prefetchedImages
        ) else {
            flight.canShow = false
            return
        }
        flight.shown = true
        present(flight, at: mediaTimeProvider())
    }

    private func present(_ flight: Flight, at timestamp: TimeInterval) {
        guard flight.shown else { return }
        let progress = min(max(flight.motion.progress(at: timestamp), 0), 1)
        handler?.snapshotTransition.scrubStack(flight.items, at: CGFloat(progress))
    }

    private func tick() {
        guard let flight else {
            stopDisplayLink()
            return
        }
        let now = mediaTimeProvider()
        present(flight, at: now)
        if flight.motion.isComplete(at: now) { end(paging: flight.motion.target == 1) }
    }

    private func end(paging: Bool) {
        stopDisplayLink()
        prefetchTask?.cancel()
        prefetchTask = nil
        guard let flight else { return }
        self.flight = nil
        preparedWorkspaceId = nil
        prefetchedImages = [:]
        guard let handler else { return }
        if flight.shown { handler.snapshotTransition.scrubStack(flight.items, at: paging ? 1 : 0) }
        if paging, handler.controller?.activeWorkspace()?.id == flight.slide.workspaceId {
            handler.cycleFullscreen(forward: flight.slide.forward, animated: !flight.shown)
        }
        if flight.shown { handler.snapshotTransition.finish(after: 0, settled: { true }) }
    }

    private func startDisplayLink(for monitor: Monitor) {
        guard displayLink == nil else { return }
        guard let screen = NSScreen.screens.first(where: { $0.displayId == monitor.displayId }) else {
            end(paging: flight?.motion.target == 1)
            return
        }
        let target = DisplayLinkTarget { [weak self] in self?.tick() }
        let link = screen.displayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}
