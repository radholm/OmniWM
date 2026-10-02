// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import QuartzCore

/// Animates layout changes with window snapshots instead of per-frame Accessibility resizes.
///
/// Windows are captured at their current size, drawn on an overlay above the display and animated on the GPU
/// to their new frames, while the real windows jump to their final frames once underneath. The overlay fades
/// out after the real windows have been resized, so apps that redraw slowly never show a stuttering resize.
@MainActor
final class WindowSnapshotTransition {
    struct Item: Equatable {
        let windowId: Int
        /// Current on-screen frame (AppKit coordinates). Used when the window has no snapshot on screen yet.
        let from: CGRect
        /// Target frame (AppKit coordinates).
        let to: CGRect
        /// Newly tiled windows pop in at their target frame instead of moving from their current frame.
        var appearing = false
        /// Animates the window in place with a 3D stack effect instead of moving it between frames.
        var stackEffect: SnapshotStackEffect?
    }

    static let duration: CFTimeInterval = 0.25
    static let fadeDuration: CFTimeInterval = 0.12
    static let crossfadeDuration: CFTimeInterval = 0.18
    static let settleDelay: Duration = .milliseconds(60)
    static let maxSettleWait: Duration = .milliseconds(700)
    static let timing = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

    private let ownedWindowRegistry: OwnedWindowRegistry
    private let backdrop: WorkspaceSwipeBackdrop
    private let captureWindow: @MainActor (Int) -> CGImage?
    /// Captures the fresh end-of-transition snapshots off the main thread when set.
    private let backgroundCapture: (@Sendable (Int) -> CGImage?)?
    private let hasCaptureAccess: @MainActor () -> Bool
    private var panel: SnapshotTransitionPanel?
    private var monitor: Monitor?
    private var layers: [Int: CALayer] = [:]
    private var motions: [Int: Motion] = [:]
    private var finishTask: Task<Void, Never>?
    private var generation = 0
    /// Where the desktop wallpaper is drawn on a display (AppKit coordinates), when it differs from the display.
    var wallpaperFrame: @MainActor (Monitor) -> CGRect? = { _ in nil }
    /// The user's animation speed multiplier (`general.animationSpeed`).
    var animationSpeed: @MainActor () -> Double = { 1 }

    private struct Motion {
        let start: CGRect
        let end: CGRect
        let beginTime: CFTimeInterval
        let duration: CFTimeInterval
    }

    private var speed: Double {
        AnimationSpeed.normalized(animationSpeed())
    }

    /// Duration of the snapshot move, scaled by the animation speed.
    var scaledDuration: CFTimeInterval {
        Self.duration / speed
    }

    var isActive: Bool {
        panel != nil
    }

    init(
        ownedWindowRegistry: OwnedWindowRegistry,
        backdrop: WorkspaceSwipeBackdrop = WorkspaceSwipeBackdrop(),
        captureWindow: @escaping @MainActor (Int) -> CGImage? = { SkyLight.shared.captureWindow(UInt32($0)) },
        hasCaptureAccess: @escaping @MainActor () -> Bool = { CGPreflightScreenCaptureAccess() },
        backgroundCapture: (@Sendable (Int) -> CGImage?)? = nil
    ) {
        self.ownedWindowRegistry = ownedWindowRegistry
        self.backdrop = backdrop
        self.captureWindow = captureWindow
        self.backgroundCapture = backgroundCapture
        self.hasCaptureAccess = hasCaptureAccess
    }

    isolated deinit {
        stop()
    }

    /// Shows (or retargets) snapshots for `items`, ordered bottom to top, and moves them to their target
    /// frames. Returns `false` when the caller must fall back to regular frame updates.
    /// `duration` overrides the (speed-scaled) default move duration, e.g. for the fullscreen stack slide.
    func begin(
        items: [Item],
        monitor: Monitor,
        animated: Bool,
        prefetched: [Int: CGImage] = [:],
        duration: CFTimeInterval? = nil
    ) -> Bool {
        if let current = self.monitor, current.displayId != monitor.displayId || current.frame != monitor.frame {
            stop()
        }
        finishTask?.cancel()
        finishTask = nil
        generation += 1
        panel?.alphaValue = 1
        let frame = WorkspaceSwipePreview.overlayFrame(covering: monitor.visibleFrame, on: monitor)
        let items = Self.resolvingAppearance(
            items.filter { Self.isVisible($0.from, in: frame) || Self.isVisible($0.to, in: frame) },
            in: frame
        )
        guard !items.isEmpty, hasCaptureAccess(), let images = captureMissingImages(items, prefetched: prefetched),
              let panel = panel ?? makePanel(frame: frame, monitor: monitor),
              let root = panel.contentView?.layer
        else {
            stop()
            return false
        }
        removeLayers(notIn: Set(items.map(\.windowId)))
        placeLayers(
            items,
            images: images,
            in: root,
            origin: CGPoint(x: -frame.minX, y: -frame.minY),
            duration: animated ? duration ?? scaledDuration : nil
        )
        if self.panel == nil {
            show(panel, monitor: monitor)
        }
        CATransaction.flush()
        return true
    }

    static func isVisible(_ rect: CGRect, in frame: CGRect) -> Bool {
        let visible = rect.intersection(frame)
        return !visible.isNull && visible.width >= 8 && visible.height >= 8
    }

    /// Places snapshot layers for `items`, animating them over `duration`, or not at all when it is `nil`.
    private func placeLayers(
        _ items: [Item],
        images: [Int: CGImage],
        in root: CALayer,
        origin: CGPoint,
        duration: CFTimeInterval?
    ) {
        let animated = duration != nil
        let duration = duration ?? 0
        let speed = speed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in items {
            let existing = layers[item.windowId]
            let layer = existing ?? makeLayer(images[item.windowId])
            let end = item.to.offsetBy(dx: origin.x, dy: origin.y)
            let popIn = existing == nil && item.appearing
            let start = existing?.presentation()?.frame
                ?? (popIn ? end : item.from.offsetBy(dx: origin.x, dy: origin.y))
            layer.removeAllAnimations()
            promoteFreshContent(of: layer)
            SnapshotStackEffect.resetPose(of: layer)
            layer.frame = end
            if animated, let effect = item.stackEffect {
                effect.animate(layer, duration: duration)
            }
            layer.shadowPath = CGPath(rect: CGRect(origin: .zero, size: end.size), transform: nil)
            layers[item.windowId] = layer
            motions[item.windowId] = Motion(
                start: animated && item.stackEffect == nil ? start : end,
                end: end,
                beginTime: CACurrentMediaTime(),
                duration: duration
            )
            layer.removeFromSuperlayer()
            root.addSublayer(layer)
            if animated, item.stackEffect == nil, popIn {
                Self.jumpIn(layer, speed: speed)
            } else if animated, item.stackEffect == nil, start != end {
                animate(layer, from: start, to: end, duration: duration)
            }
        }
        CATransaction.commit()
    }

    private func show(_ panel: SnapshotTransitionPanel, monitor: Monitor) {
        self.panel = panel
        self.monitor = monitor
        ownedWindowRegistry.register(
            panel,
            surfaceId: "window-snapshot-transition-\(monitor.displayId)",
            policy: SurfacePolicy(
                kind: .workspaceSwipe,
                hitTestPolicy: .passthrough,
                capturePolicy: .excluded,
                suppressesManagedFocusRecovery: false
            )
        )
        panel.orderFrontRegardless()
    }

    /// Moves snapshots to new frames immediately (interactive resizing).
    func update(frames: [Int: CGRect]) {
        guard let panel, finishTask == nil else { return }
        let origin = CGPoint(x: -panel.frame.minX, y: -panel.frame.minY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (windowId, frame) in frames {
            guard let layer = layers[windowId] else { continue }
            let target = frame.offsetBy(dx: origin.x, dy: origin.y)
            guard layer.frame != target else { continue }
            layer.removeAllAnimations()
            motions[windowId] = Motion(start: target, end: target, beginTime: CACurrentMediaTime(), duration: 0)
            layer.frame = target
            layer.shadowPath = CGPath(rect: CGRect(origin: .zero, size: target.size), transform: nil)
        }
        CATransaction.commit()
    }

    /// Fades the overlay out once `settled` reports the real windows caught up (or a timeout passes).
    func finish(after delay: CFTimeInterval, settled: @escaping @MainActor () -> Bool) {
        guard panel != nil else { return }
        scheduleFinish(after: delay, settled: settled)
    }

    func stop() {
        finishTask?.cancel()
        finishTask = nil
        generation += 1
        if let panel {
            ownedWindowRegistry.unregister(panel)
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
        monitor = nil
        layers.removeAll()
        motions.removeAll()
    }

    private func scheduleFinish(after delay: CFTimeInterval, settled: @escaping @MainActor () -> Bool) {
        finishTask?.cancel()
        generation += 1
        let generation = generation
        finishTask = Task { @MainActor [weak self] in
            let start = ContinuousClock.now
            let deadline = start + .seconds(delay) + Self.maxSettleWait
            try? await Task.sleep(for: .milliseconds(20))
            while !Task.isCancelled, !settled(), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            var fadeAt = start + .seconds(delay)
            let images = await captureFreshSnapshots()
            guard !Task.isCancelled, self.generation == generation else { return }
            if crossfadeToFreshSnapshots(images) {
                fadeAt = max(fadeAt, ContinuousClock.now + .seconds(Self.crossfadeDuration / speed))
            }
            try? await Task.sleep(until: fadeAt)
            guard !Task.isCancelled, self.generation == generation else { return }
            fadeOut(generation: generation)
        }
    }

    /// Recaptures the resized real windows and cross-fades them in over the stretched snapshots, following
    /// the running motion, so removing the overlay afterwards shows no content change.
    private func crossfadeToFreshSnapshots(_ images: [Int: CGImage]) -> Bool {
        var didCrossfade = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (windowId, layer) in layers {
            guard let motion = motions[windowId], let image = images[windowId] else { continue }
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            let fresh = CALayer()
            fresh.contents = image
            fresh.contentsGravity = .resize
            fresh.frame = CGRect(origin: .zero, size: motion.end.size)
            if motion.start != motion.end {
                let bounds = CABasicAnimation(keyPath: "bounds")
                bounds.fromValue = NSValue(rect: CGRect(origin: .zero, size: motion.start.size))
                bounds.toValue = NSValue(rect: CGRect(origin: .zero, size: motion.end.size))
                let position = CABasicAnimation(keyPath: "position")
                position.fromValue = NSValue(point: CGPoint(x: motion.start.width / 2, y: motion.start.height / 2))
                position.toValue = NSValue(point: CGPoint(x: motion.end.width / 2, y: motion.end.height / 2))
                let group = CAAnimationGroup()
                group.animations = [bounds, position]
                group.beginTime = motion.beginTime
                group.duration = motion.duration
                group.timingFunction = Self.timing
                group.fillMode = .both
                fresh.add(group, forKey: "snapshotTransition")
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = Self.crossfadeDuration / speed
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fresh.add(fade, forKey: "crossfade")
            layer.addSublayer(fresh)
            didCrossfade = true
        }
        CATransaction.commit()
        return didCrossfade
    }

    /// Capturing takes ~10-15 ms per window, so it runs off the main thread when possible.
    private func captureFreshSnapshots() async -> [Int: CGImage] {
        let windowIds = layers.keys.filter { motions[$0] != nil }
        guard let backgroundCapture else {
            return Self.images(for: windowIds, capture: captureWindow)
        }
        return await Task.detached(priority: .userInitiated) {
            Self.images(for: windowIds, capture: backgroundCapture)
        }.value
    }

    private func promoteFreshContent(of layer: CALayer) {
        guard let fresh = layer.sublayers?.last else { return }
        layer.contents = fresh.contents
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func fadeOut(generation: Int) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration / speed
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.stop()
            }
        }
    }

    private func makePanel(frame: CGRect, monitor: Monitor) -> SnapshotTransitionPanel? {
        guard let wallpaper = backdrop.image(for: monitor) else { return nil }
        let panel = SnapshotTransitionPanel(frame: frame)
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        root.masksToBounds = true
        let wallpaperLayer = CALayer()
        wallpaperLayer.frame = (wallpaperFrame(monitor) ?? monitor.frame).offsetBy(dx: -frame.minX, dy: -frame.minY)
        wallpaperLayer.contentsGravity = .resizeAspectFill
        wallpaperLayer.contents = wallpaper
        root.addSublayer(wallpaperLayer)
        let view = NSView(frame: root.frame)
        view.wantsLayer = true
        view.layer = root
        panel.contentView = view
        return panel
    }
}

@MainActor
private final class SnapshotTransitionPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

extension WindowSnapshotTransition {
    /// A new window that macOS already shows on this display (e.g. a Finder window opened at its remembered
    /// frame) has already appeared once; it stays put or glides from there instead of appearing a second time.
    static func resolvingAppearance(_ items: [Item], in frame: CGRect) -> [Item] {
        items.map { item in
            guard item.appearing, isVisible(item.from, in: frame) else { return item }
            var item = item
            item.appearing = false
            if item.from.approximatelyEqual(to: item.to, tolerance: nearTargetTolerance) {
                item = Item(windowId: item.windowId, from: item.to, to: item.to)
            }
            return item
        }
    }

    /// A window opened this close to its tile would only twitch into place, so it stays still.
    static let nearTargetTolerance: CGFloat = 24

    static let jumpInScale: CGFloat = 0.86

    /// Springs a new window up from slightly smaller to full size at its tile while it fades in.
    static func jumpIn(_ layer: CALayer, speed: Double = 1) {
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = jumpInScale
        scale.toValue = 1
        scale.mass = 1
        // Same damping ratio at any speed: stiffness scales with speed², damping with speed.
        scale.stiffness = 420 * speed * speed
        scale.damping = 26 * speed
        scale.duration = scale.settlingDuration
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        opacity.duration = 0.12 / speed
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(scale, forKey: "jumpInScale")
        layer.add(opacity, forKey: "jumpInOpacity")
    }

    private nonisolated static func images(for windowIds: [Int], capture: (Int) -> CGImage?) -> [Int: CGImage] {
        var images: [Int: CGImage] = [:]
        for windowId in windowIds {
            images[windowId] = capture(windowId)
        }
        return images
    }

    private func makeLayer(_ image: CGImage?) -> CALayer {
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resize
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: -8)
        return layer
    }

    private func animate(_ layer: CALayer, from start: CGRect, to end: CGRect, duration: CFTimeInterval) {
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: CGPoint(x: start.midX, y: start.midY))
        position.toValue = NSValue(point: CGPoint(x: end.midX, y: end.midY))
        let bounds = CABasicAnimation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: CGRect(origin: .zero, size: start.size))
        bounds.toValue = NSValue(rect: CGRect(origin: .zero, size: end.size))
        let group = CAAnimationGroup()
        group.animations = [position, bounds]
        group.duration = duration
        group.timingFunction = Self.timing
        layer.add(group, forKey: "snapshotTransition")
    }
}

extension WindowSnapshotTransition {
    fileprivate func captureMissingImages(_ items: [Item], prefetched: [Int: CGImage]) -> [Int: CGImage]? {
        var images: [Int: CGImage] = [:]
        for item in items where layers[item.windowId] == nil {
            guard let image = prefetched[item.windowId] ?? captureWindow(item.windowId) else { return nil }
            images[item.windowId] = image
        }
        return images
    }

    /// Captures windows off the main thread, so a later `begin` doesn't block on capturing them.
    func prefetchImages(for windowIds: [Int]) async -> [Int: CGImage] {
        guard let backgroundCapture, hasCaptureAccess() else { return [:] }
        return await Task.detached(priority: .userInitiated) {
            Self.images(for: windowIds, capture: backgroundCapture)
        }.value
    }

    /// Drops snapshots of windows that left the transition (closed or moved away) while it was running.
    fileprivate func removeLayers(notIn windowIds: Set<Int>) {
        let stale = layers.keys.filter { !windowIds.contains($0) }
        guard !stale.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for windowId in stale {
            layers.removeValue(forKey: windowId)?.removeFromSuperlayer()
            motions.removeValue(forKey: windowId)
        }
        CATransaction.commit()
    }
}
