// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import QuartzCore

/// Draws the desktop wallpaper slightly enlarged in a desktop-level panel on each display and pans it with the
/// active workspace's position, so switching workspaces scrolls the wallpaper a little (parallax).
@MainActor
final class WorkspaceWallpaperParallax {
    struct Target: Equatable {
        let monitor: Monitor
        let position: CGFloat
        let axis: WorkspaceSwipeAxis
    }

    /// Extra wallpaper size, as a fraction of the display size, that is revealed across all workspaces.
    static let overscan: CGFloat = 0.1
    static let animationDuration: CFTimeInterval = 0.35
    static let refreshInterval: Duration = .seconds(30)

    private final class Display {
        let panel: WallpaperParallaxPanel
        let layer = CALayer()
        var target: Target
        var image: CGImage?
        var isPanned = false

        init(panel: WallpaperParallaxPanel, target: Target) {
            self.panel = panel
            self.target = target
        }
    }

    private let ownedWindowRegistry: OwnedWindowRegistry
    private let captureWallpaper: @MainActor (Monitor) -> CGImage?
    private var displays: [CGDirectDisplayID: Display] = [:]
    private var refreshTask: Task<Void, Never>?
    private var spaceObserver: NSObjectProtocol?

    init(
        ownedWindowRegistry: OwnedWindowRegistry,
        captureWallpaper: @escaping @MainActor (Monitor) -> CGImage? = { monitor in
            guard CGPreflightScreenCaptureAccess() else { return nil }
            return SkyLight.shared.captureWallpaper(in: ScreenCoordinateSpace.toWindowServer(rect: monitor.frame))
        }
    ) {
        self.ownedWindowRegistry = ownedWindowRegistry
        self.captureWallpaper = captureWallpaper
    }

    isolated deinit {
        removeAll()
    }

    var isActive: Bool {
        !displays.isEmpty
    }

    /// Normalized pan position (0 = start, 1 = end) of the workspace at `index` among `count` workspaces.
    static func position(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0.5 }
        return min(max(CGFloat(index) / CGFloat(count - 1), 0), 1)
    }

    /// Wallpaper frame in AppKit coordinates for a pan `position` along `axis`. Horizontal pans move from the
    /// left edge of the wallpaper to the right edge; vertical pans from the top to the bottom.
    static func frame(for monitorFrame: CGRect, position: CGFloat, axis: WorkspaceSwipeAxis) -> CGRect {
        let extraWidth = monitorFrame.width * overscan
        let extraHeight = monitorFrame.height * overscan
        let position = min(max(position, 0), 1)
        let origin = switch axis {
        case .horizontal:
            CGPoint(x: monitorFrame.minX - extraWidth * position, y: monitorFrame.minY - extraHeight / 2)
        case .vertical:
            CGPoint(x: monitorFrame.minX - extraWidth / 2, y: monitorFrame.minY - extraHeight * (1 - position))
        }
        return CGRect(origin: origin, size: CGSize(
            width: monitorFrame.width + extraWidth,
            height: monitorFrame.height + extraHeight
        ))
    }

    static func interpolate(_ from: CGRect, _ to: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }

    /// Wallpaper frame currently shown on `monitor`, or `nil` when the parallax wallpaper is not shown there.
    func wallpaperFrame(on monitor: Monitor) -> CGRect? {
        guard let display = displays[monitor.displayId], display.target.monitor.frame == monitor.frame else {
            return nil
        }
        return Self.frame(for: monitor.frame, position: display.target.position, axis: display.target.axis)
    }

    /// Shows the wallpaper for `targets` and removes it from every other display.
    func sync(_ targets: [Target], animated: Bool) {
        let ids = Set(targets.map(\.monitor.displayId))
        for (displayId, display) in displays where !ids.contains(displayId) {
            close(display)
            displays[displayId] = nil
        }
        for target in targets {
            if let display = displays[target.monitor.displayId], display.target.monitor.frame == target.monitor.frame {
                guard display.target != target || display.isPanned else { continue }
                let animate = animated && display.target.axis == target.axis
                display.target = target
                apply(display, animated: animate)
            } else {
                if let stale = displays[target.monitor.displayId] { close(stale) }
                displays[target.monitor.displayId] = makeDisplay(target)
            }
        }
        if displays.isEmpty { stopObserving() } else { startObserving() }
    }

    /// Pans the wallpaper on `displayId` to an explicit frame, e.g. to follow a workspace swipe.
    func pan(displayId: CGDirectDisplayID, to frame: CGRect) {
        guard let display = displays[displayId] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.isPanned = true
        display.layer.removeAnimation(forKey: "parallax")
        display.layer.frame = frame.offsetBy(
            dx: -display.target.monitor.frame.minX,
            dy: -display.target.monitor.frame.minY
        )
        CATransaction.commit()
    }

    func removeAll() {
        for display in displays.values { close(display) }
        displays.removeAll()
        stopObserving()
    }

    /// Captures the current macOS wallpaper again, e.g. after the user changed it.
    func refreshImages() {
        for display in displays.values {
            guard let image = captureWallpaper(display.target.monitor) else { continue }
            if let current = display.image, Self.sameContent(current, image) { continue }
            display.image = image
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            display.layer.contents = image
            CATransaction.commit()
        }
    }

    private static func sameContent(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        guard lhs.width == rhs.width, lhs.height == rhs.height,
              let left = lhs.dataProvider?.data, let right = rhs.dataProvider?.data
        else { return false }
        return CFEqual(left, right)
    }

    private func makeDisplay(_ target: Target) -> Display? {
        guard let image = captureWallpaper(target.monitor) else { return nil }
        let frame = target.monitor.frame
        let panel = WallpaperParallaxPanel(frame: frame)
        let display = Display(panel: panel, target: target)
        display.image = image
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        root.masksToBounds = true
        root.backgroundColor = NSColor.black.cgColor
        display.layer.contentsGravity = .resizeAspectFill
        display.layer.contents = image
        root.addSublayer(display.layer)
        let view = NSView(frame: root.frame)
        view.wantsLayer = true
        view.layer = root
        panel.contentView = view
        apply(display, animated: false)
        ownedWindowRegistry.register(
            panel,
            surfaceId: "wallpaper-parallax-\(target.monitor.displayId)",
            policy: SurfacePolicy(
                kind: .workspaceSwipe,
                hitTestPolicy: .passthrough,
                capturePolicy: .excluded,
                suppressesManagedFocusRecovery: false
            )
        )
        panel.orderFrontRegardless()
        return display
    }

    private func apply(_ display: Display, animated: Bool) {
        let monitorFrame = display.target.monitor.frame
        let frame = Self.frame(for: monitorFrame, position: display.target.position, axis: display.target.axis)
            .offsetBy(dx: -monitorFrame.minX, dy: -monitorFrame.minY)
        let layer = display.layer
        display.isPanned = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            let from = layer.presentation()?.position ?? layer.position
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: from)
            animation.toValue = NSValue(point: CGPoint(x: frame.midX, y: frame.midY))
            animation.duration = Self.animationDuration
            animation.timingFunction = WindowSnapshotTransition.timing
            layer.add(animation, forKey: "parallax")
        } else {
            layer.removeAnimation(forKey: "parallax")
        }
        layer.frame = frame
        CATransaction.commit()
    }

    private func close(_ display: Display) {
        ownedWindowRegistry.unregister(display.panel)
        display.panel.orderOut(nil)
        display.panel.close()
    }

    private func startObserving() {
        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.refreshImages()
                }
            }
        }
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled, let self else { return }
                refreshImages()
            }
        }
    }

    private func stopObserving() {
        refreshTask?.cancel()
        refreshTask = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }
}

@MainActor
private final class WallpaperParallaxPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        // Directly above the macOS wallpaper and below Finder's desktop icons.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
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
