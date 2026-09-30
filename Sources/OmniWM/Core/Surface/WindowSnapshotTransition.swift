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
    private let hasCaptureAccess: @MainActor () -> Bool
    private var panel: SnapshotTransitionPanel?
    private var monitor: Monitor?
    private var snapshots: [Int: WindowSnapshotLayer] = [:]
    private var finishTask: Task<Void, Never>?
    private var generation = 0

    var isActive: Bool {
        panel != nil
    }

    init(
        ownedWindowRegistry: OwnedWindowRegistry,
        backdrop: WorkspaceSwipeBackdrop = WorkspaceSwipeBackdrop(),
        captureWindow: @escaping @MainActor (Int) -> CGImage? = { SkyLight.shared.captureWindow(UInt32($0)) },
        hasCaptureAccess: @escaping @MainActor () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.ownedWindowRegistry = ownedWindowRegistry
        self.backdrop = backdrop
        self.captureWindow = captureWindow
        self.hasCaptureAccess = hasCaptureAccess
    }

    isolated deinit {
        stop()
    }

    /// Shows (or retargets) snapshots for `items`, ordered bottom to top, and moves them to their target
    /// frames. Returns `false` when the caller must fall back to regular frame updates.
    func begin(items: [Item], monitor: Monitor, animated: Bool) -> Bool {
        if let current = self.monitor, current.displayId != monitor.displayId || current.frame != monitor.frame {
            stop()
        }
        finishTask?.cancel()
        finishTask = nil
        generation += 1
        panel?.alphaValue = 1
        let frame = WorkspaceSwipePreview.overlayFrame(covering: monitor.visibleFrame, on: monitor)
        let items = items.filter { Self.isVisible($0.from, in: frame) || Self.isVisible($0.to, in: frame) }
        guard !items.isEmpty, hasCaptureAccess(), let images = captureMissingImages(items),
              let panel = panel ?? makePanel(frame: frame, monitor: monitor),
              let root = panel.contentView?.layer
        else {
            stop()
            return false
        }
        placeLayers(
            items,
            images: images,
            in: root,
            origin: CGPoint(x: -frame.minX, y: -frame.minY),
            animated: animated
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

    private func captureMissingImages(_ items: [Item]) -> [Int: CGImage]? {
        var images: [Int: CGImage] = [:]
        for item in items where snapshots[item.windowId] == nil {
            guard let image = captureWindow(item.windowId) else { return nil }
            images[item.windowId] = image
        }
        return images
    }

    private func placeLayers(
        _ items: [Item],
        images: [Int: CGImage],
        in root: CALayer,
        origin: CGPoint,
        animated: Bool
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in items {
            let existing = snapshots[item.windowId]
            let snapshot = existing ?? WindowSnapshotLayer(image: images[item.windowId])
            let end = item.to.offsetBy(dx: origin.x, dy: origin.y)
            let popIn = existing == nil && item.appearing
            let start = existing?.presentedFrame
                ?? (popIn ? end.insetBy(dx: end.width * 0.06, dy: end.height * 0.06)
                    : item.from.offsetBy(dx: origin.x, dy: origin.y))
            snapshot.move(from: start, to: end, animated: animated, fadeIn: popIn)
            snapshots[item.windowId] = snapshot
            snapshot.layer.removeFromSuperlayer()
            root.addSublayer(snapshot.layer)
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
            guard let snapshot = snapshots[windowId] else { continue }
            let target = frame.offsetBy(dx: origin.x, dy: origin.y)
            guard snapshot.layer.frame != target else { continue }
            snapshot.move(from: target, to: target, animated: false)
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
        snapshots.removeAll()
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
            if crossfadeToFreshSnapshots() {
                fadeAt = max(fadeAt, ContinuousClock.now + .seconds(Self.crossfadeDuration))
            }
            try? await Task.sleep(until: fadeAt)
            guard !Task.isCancelled, self.generation == generation else { return }
            fadeOut(generation: generation)
        }
    }

    /// Recaptures the resized real windows and cross-fades them in over the snapshots, following the running
    /// motion, so removing the overlay afterwards shows no content change.
    private func crossfadeToFreshSnapshots() -> Bool {
        var didCrossfade = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (windowId, snapshot) in snapshots where snapshot.motion != nil {
            guard let image = captureWindow(windowId) else { continue }
            snapshot.crossfade(to: image)
            didCrossfade = true
        }
        CATransaction.commit()
        return didCrossfade
    }

    private func fadeOut(generation: Int) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
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
        wallpaperLayer.frame = monitor.frame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        wallpaperLayer.contentsGravity = .resizeAspectFill
        wallpaperLayer.contents = wallpaper
        root.addSublayer(wallpaperLayer)
        let view = NSView(frame: root.frame)
        view.layerUsesCoreImageFilters = true
        view.layer = root
        view.wantsLayer = true
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
