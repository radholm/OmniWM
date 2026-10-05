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
        var shown = false

        init(
            slide: FullscreenSlide,
            items: [WindowSnapshotTransition.Item],
            monitor: Monitor,
            cumulative: Double,
            timestamp: TimeInterval,
            recognitionMovement: SwipeEvent?
        ) {
            self.slide = slide
            self.items = items
            self.monitor = monitor
            let sign: Double = cumulative < 0 ? -1 : 1
            inputSign = sign
            motion = WorkspaceSwipeMotion(
                cumulativeUnits: abs(cumulative),
                timestamp: timestamp,
                recognitionMovement: recognitionMovement.map {
                    SwipeEvent(delta: $0.delta * sign, timestamp: $0.timestamp)
                }
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

    private weak var handler: DwindleLayoutHandler?
    private var flight: Flight?
    private var preparedWorkspaceId: WorkspaceDescriptor.ID?
    private var prefetchedImages: [Int: CGImage] = [:]
    private var prefetchTask: Task<Void, Never>?
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
        guard let handler, handler.snapshotTransitionsEnabled else { return false }
        return handler.peekFullscreenSlide(in: workspaceId, forward: true) != nil
    }

    /// Captures the stacked windows off the main thread as soon as fingers touch, before the swipe is recognized.
    func prepare(workspaceId: WorkspaceDescriptor.ID) {
        guard flight == nil, let handler else { return }
        prefetchTask?.cancel()
        preparedWorkspaceId = workspaceId
        prefetchedImages = [:]
        let windowIds = handler.snapshotItems(workspaceId: workspaceId, targets: [:]).map(\.windowId)
        prefetchTask = Task { @MainActor [weak self, weak handler] in
            guard let handler else { return }
            let images = await handler.snapshotTransition.prefetchImages(for: windowIds)
            guard !Task.isCancelled, let self, preparedWorkspaceId == workspaceId else { return }
            prefetchedImages = images
            prefetchTask = nil
            if let flight, !flight.shown { show(flight) }
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
        guard flight == nil, let handler, handler.snapshotTransitionsEnabled,
              let monitor = handler.controller?.workspaceManager.monitor(for: workspaceId),
              let slide = handler.peekFullscreenSlide(in: workspaceId, forward: forward)
        else { return false }
        let items = slide.items(from: handler.snapshotItems(workspaceId: workspaceId, targets: [:]))
        guard items.contains(where: { $0.stackEffect != nil }) else { return false }
        let flight = Flight(
            slide: slide,
            items: items,
            monitor: monitor,
            cumulative: cumulative,
            timestamp: timestamp,
            recognitionMovement: recognitionMovement
        )
        self.flight = flight
        if prefetchTask == nil || preparedWorkspaceId != workspaceId { show(flight) }
        return true
    }

    @discardableResult
    func update(cumulative: Double, timestamp: TimeInterval) -> Bool {
        guard let flight, flight.motion.target == nil else { return false }
        flight.motion.update(cumulativeUnits: cumulative * flight.inputSign, timestamp: timestamp)
        present(flight, at: mediaTimeProvider())
        return true
    }

    /// Settles the page turn on the next window or back; returns `false` when no page turn is being scrubbed.
    @discardableResult
    func release(timestamp: TimeInterval, allowFlick: Bool) -> Bool {
        guard let flight else { return false }
        guard flight.motion.target == nil else { return true }
        guard flight.shown, flight.motion.release(
            timestamp: timestamp,
            allowFlick: allowFlick,
            animationTime: mediaTimeProvider(),
            motion: handler?.controller?.motionPolicy.snapshot() ?? .enabled
        ) else {
            end(paging: false)
            return true
        }
        startDisplayLink(for: flight.monitor)
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

    private func show(_ flight: Flight) {
        guard let handler, self.flight === flight else { return }
        guard handler.snapshotTransition.begin(
            items: flight.items,
            monitor: flight.monitor,
            animated: false,
            prefetched: prefetchedImages
        ) else {
            self.flight = nil
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
        guard let handler, flight.shown else { return }
        handler.snapshotTransition.scrubStack(flight.items, at: paging ? 1 : 0)
        if paging, handler.controller?.activeWorkspace()?.id == flight.slide.workspaceId {
            handler.cycleFullscreen(forward: flight.slide.forward, animated: false)
        }
        handler.snapshotTransition.finish(after: 0, settled: { true })
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
