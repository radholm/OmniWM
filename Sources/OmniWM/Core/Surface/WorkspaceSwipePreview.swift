// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import IOSurface
import QuartzCore

@MainActor
final class WorkspaceSwipePreview {
    struct Item {
        let handle: WindowHandle
        let token: WindowToken
        let frame: CGRect

        init(handle: WindowHandle, frame: CGRect) {
            self.handle = handle
            token = handle.token
            self.frame = frame
        }

        func captureRequest(backingScale: CGFloat) -> OverviewPreviewRequest {
            let scale = min(1, backingScale)
            return OverviewPreviewRequest(
                handle: handle,
                pixelWidth: Int(ceil(frame.width * scale)),
                pixelHeight: Int(ceil(frame.height * scale))
            )
        }
    }

    private final class Content {
        let layer = CALayer()
        var preview: OverviewPreviewFrame

        init(preview: OverviewPreviewFrame, frame: CGRect, scale: CGFloat) {
            self.preview = preview
            layer.frame = frame
            layer.contentsScale = scale
            layer.contentsGravity = .resize
            layer.contents = preview.surface
            layer.contentsRect = preview.contentsRect
            // Window captures exclude the system drop shadow; draw one from the content's alpha instead.
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = Self.shadowOpacity
            layer.shadowRadius = Self.shadowRadius
            layer.shadowOffset = Self.shadowOffset
            layer.shouldRasterize = true
            layer.rasterizationScale = scale
        }

        static let shadowOpacity: Float = 0.45
        static let shadowRadius: CGFloat = 16
        static let shadowOffset = CGSize(width: 0, height: -8)

        func update(_ preview: OverviewPreviewFrame) {
            let previous = self.preview
            self.preview = preview
            CATransaction.setCompletionBlock { withExtendedLifetime(previous) {} }
            layer.contents = preview.surface
            layer.contentsRect = preview.contentsRect
        }
    }

    private let ownedWindowRegistry: OwnedWindowRegistry
    private let capture: OverviewThumbnailCapture
    private let hasCaptureAccess: @MainActor () -> Bool
    private let backdrop: WorkspaceSwipeBackdrop
    private var tokens: [WindowHandle: WindowToken] = [:]
    private var panel: WorkspaceSwipePreviewPanel?
    private var sourceLayer: CALayer?
    private var destinationLayer: CALayer?
    private var wallpaperLayer: CALayer?
    private var overlayOrigin = CGPoint.zero
    private var contents: [WindowHandle: [Content]] = [:]
    /// Windows that delivered a frame since the last `prepare`; cached previews of other windows may be
    /// minutes old (captured when their workspace was last shown).
    private var freshHandles: Set<WindowHandle> = []
    private(set) var isWarming = false

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var canCapture: Bool {
        hasCaptureAccess()
    }

    init(
        ownedWindowRegistry: OwnedWindowRegistry,
        previewCapture: OverviewThumbnailCapture? = nil,
        backdrop: WorkspaceSwipeBackdrop = WorkspaceSwipeBackdrop(),
        hasCaptureAccess: @escaping @MainActor () -> Bool = {
            MainThreadAXSpanTrace.measure(.screenCapturePreflight) {
                CGPreflightScreenCaptureAccess()
            } succeeded: { $0 }
        }
    ) {
        self.ownedWindowRegistry = ownedWindowRegistry
        self.hasCaptureAccess = hasCaptureAccess
        self.backdrop = backdrop
        capture = previewCapture ?? OverviewThumbnailCapture(
            environment: OverviewEnvironment(),
            ownedWindowRegistry: ownedWindowRegistry,
            consumer: .workspaceSwipe,
            hasCaptureAccess: hasCaptureAccess
        )
        capture.onPreview = { [weak self] handle, frame in
            if frame != nil { self?.freshHandles.insert(handle) }
            self?.updatePreview(frame, for: handle)
        }
        capture.onReadinessChange = { [weak self] in self?.finishWarmupIfReady() }
    }

    isolated deinit {
        stop()
    }

    func remove(token: WindowToken) {
        tokens = tokens.filter { $0.value != token && $0.key.token != token }
        capture.remove(token: token)
    }

    func prepare(source: [Item], destination: [Item], monitor: Monitor, workingFrame: CGRect? = nil) {
        reconcile(
            source: source,
            destination: destination,
            monitor: monitor,
            workingFrame: workingFrame,
            warming: false
        )
    }

    func warm(source: [Item], destination: [Item], monitor: Monitor, workingFrame: CGRect? = nil) {
        guard panel == nil else { return }
        reconcile(source: source, destination: destination, monitor: monitor, workingFrame: workingFrame, warming: true)
    }

    private func reconcile(
        source: [Item], destination: [Item], monitor: Monitor, workingFrame: CGRect?, warming: Bool
    ) {
        isWarming = false
        let frame = workingFrame ?? monitor.visibleFrame
        let items = (source + destination).filter { $0.frame.intersects(frame) }
        if !backdrop.hasImage(for: monitor), hasCaptureAccess() { _ = backdrop.image(for: monitor) }
        let represented = Set(items.map(\.handle))
        for item in items where tokens[item.handle] != nil && tokens[item.handle] != item.handle.token {
            capture.remove(handle: item.handle)
        }
        tokens = Dictionary(items.map { ($0.handle, $0.handle.token) }, uniquingKeysWith: { _, latest in latest })
        if !warming { freshHandles.removeAll() }
        let scale = Self.scale(for: monitor)
        isWarming = warming
        let requested = warming ? items.filter { capture.preview(for: $0.handle) == nil } : items
        capture.reconcile(
            represented: represented,
            visible: requested.map { $0.captureRequest(backingScale: scale) },
            retainingUnrepresentedPreviews: true,
            firstFrameOnly: warming
        )
    }

    /// Whether every window shown by `begin` has a frame captured since `prepare`, not just a cached one.
    func hasFreshPreviews(source: [Item], destination: [Item], monitor: Monitor, workingFrame: CGRect? = nil) -> Bool {
        let frame = workingFrame ?? monitor.visibleFrame
        return (source + destination).allSatisfy { !$0.frame.intersects(frame) || freshHandles.contains($0.handle) }
    }

    private func finishWarmupIfReady() {
        guard isWarming, !capture.hasPendingFirstFrames else { return }
        isWarming = false
        capture.clear()
    }

    /// Starts the slide. With `wallpaperFrame`, workspaces slide over one shared wallpaper drawn at that frame
    /// (AppKit coordinates) that `update` pans separately; otherwise each workspace carries its own wallpaper.
    func begin(
        source: [Item], destination: [Item], monitor: Monitor, workingFrame: CGRect? = nil,
        wallpaperFrame: CGRect? = nil
    ) -> Bool {
        guard panel == nil, hasCaptureAccess() else { return false }
        guard let wallpaperImage = backdrop.image(for: monitor) else {
            backdrop.clear()
            return false
        }
        let visibleFrame = workingFrame ?? monitor.visibleFrame
        let source = source.filter { $0.frame.intersects(visibleFrame) }
        let destination = destination.filter { $0.frame.intersects(visibleFrame) }
        let frame = Self.overlayFrame(covering: visibleFrame, on: monitor)
        guard (source + destination).allSatisfy({
            tokens[$0.handle] == $0.handle.token && capture.preview(for: $0.handle) != nil
        }) else { return false }

        let (panel, root) = Self.makePanel(frame: frame)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = Self.scale(for: monitor)
        let wallpaperLayer = makeWallpaperLayer(wallpaperImage, monitor: monitor, frame: frame)
        if let wallpaperFrame {
            wallpaperLayer.frame = wallpaperFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
        root.addSublayer(wallpaperLayer)
        let workspaceWallpaper = wallpaperFrame == nil ? wallpaperImage : nil
        let sourceLayer = makeWorkspaceLayer(
            source, monitor: monitor, frame: frame, scale: scale, image: workspaceWallpaper
        )
        let destinationLayer = makeWorkspaceLayer(
            destination, monitor: monitor, frame: frame, scale: scale, image: workspaceWallpaper
        )
        destinationLayer.isHidden = true
        root.addSublayer(sourceLayer)
        root.addSublayer(destinationLayer)
        self.sourceLayer = sourceLayer
        self.destinationLayer = destinationLayer
        self.wallpaperLayer = wallpaperLayer
        overlayOrigin = frame.origin
        self.panel = panel
        CATransaction.commit()

        ownedWindowRegistry.register(panel, surfaceId: "workspace-swipe-\(monitor.displayId)", policy: Self.policy)
        panel.orderFrontRegardless()
        return true
    }

    func update(sourceOffset: CGVector, destinationOffset: CGVector, wallpaperFrame: CGRect? = nil) {
        guard panel != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let wallpaperFrame {
            wallpaperLayer?.frame = wallpaperFrame.offsetBy(dx: -overlayOrigin.x, dy: -overlayOrigin.y)
        }
        sourceLayer?.setAffineTransform(CGAffineTransform(translationX: sourceOffset.dx, y: sourceOffset.dy))
        destinationLayer?.setAffineTransform(CGAffineTransform(
            translationX: destinationOffset.dx,
            y: destinationOffset.dy
        ))
        destinationLayer?.isHidden = false
        CATransaction.commit()
    }

    /// Hold before fading a finished preview out, so revealed windows can redraw underneath it first.
    static let revealHold: Duration = .milliseconds(120)
    static let revealFade: TimeInterval = 0.12
    /// The user's animation speed multiplier (`general.animationSpeed`).
    var animationSpeed: @MainActor () -> Double = { 1 }

    /// Stops the preview. With `revealingWindows`, the panel stays on screen briefly and fades out, hiding the
    /// first frames of windows that were just moved on screen (stale content, activation redraws).
    func stop(revealingWindows: Bool = false) {
        isWarming = false
        let previous = contents.values.flatMap { $0.map(\.preview) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { withExtendedLifetime(previous) {} }
        if let panel {
            if revealingWindows {
                retire(panel, keepingAlive: previous)
            } else {
                close(panel)
            }
            backdrop.clear()
        }
        panel = nil
        sourceLayer = nil
        destinationLayer = nil
        wallpaperLayer = nil
        contents.removeAll()
        capture.clear()
        CATransaction.commit()
    }

    private func close(_ panel: NSPanel) {
        ownedWindowRegistry.unregister(panel)
        panel.orderOut(nil)
        panel.close()
    }

    private func retire(_ panel: NSPanel, keepingAlive previews: [OverviewPreviewFrame]) {
        // Free the display's surface id for the next preview while this one fades out.
        ownedWindowRegistry.unregister(panel)
        ownedWindowRegistry.register(
            panel, surfaceId: "workspace-swipe-retiring-\(ObjectIdentifier(panel).hashValue)", policy: Self.policy
        )
        let fade = Self.revealFade / AnimationSpeed.normalized(animationSpeed())
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.revealHold)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fade
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    withExtendedLifetime(previews) {}
                    if let self {
                        self.close(panel)
                    } else {
                        panel.orderOut(nil)
                        panel.close()
                    }
                }
            }
        }
    }

    private func updatePreview(_ frame: OverviewPreviewFrame?, for handle: WindowHandle) {
        guard let frame, tokens[handle] == handle.token, let layers = contents[handle] else { return }
        for content in layers {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content.update(frame)
            CATransaction.commit()
        }
    }
}

@MainActor
extension WorkspaceSwipePreview {
    fileprivate static let policy = SurfacePolicy(
        kind: .workspaceSwipe,
        hitTestPolicy: .passthrough,
        capturePolicy: .excluded,
        suppressesManagedFocusRecovery: false
    )

    fileprivate static func makePanel(frame: CGRect) -> (WorkspaceSwipePreviewPanel, CALayer) {
        let panel = WorkspaceSwipePreviewPanel(frame: frame)
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        root.masksToBounds = true
        let view = NSView(frame: root.frame)
        view.wantsLayer = true
        view.layer = root
        panel.contentView = view
        return (panel, root)
    }

    /// Real windows draw a 1pt dark outline just outside their frame. Windows touching the top of the visible
    /// frame would leave that outline showing above an overlay limited to the visible frame, so extend it.
    static func overlayFrame(covering frame: CGRect, on monitor: Monitor) -> CGRect {
        let maxY = min(frame.maxY + outlineOverlap, max(frame.maxY, monitor.frame.maxY))
        return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: maxY - frame.minY)
    }

    static let outlineOverlap: CGFloat = 2

    fileprivate func makeWorkspaceLayer(
        _ items: [Item], monitor: Monitor, frame: CGRect, scale: CGFloat, image: CGImage?
    ) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: frame.size)
        layer.masksToBounds = true
        if let image { layer.addSublayer(makeWallpaperLayer(image, monitor: monitor, frame: frame)) }
        for item in items {
            guard let preview = capture.preview(for: item.handle) else { continue }
            let content = Content(
                preview: preview,
                frame: item.frame.offsetBy(dx: -frame.minX, dy: -frame.minY),
                scale: scale
            )
            contents[item.handle, default: []].append(content)
            layer.addSublayer(content.layer)
        }
        return layer
    }

    fileprivate func makeWallpaperLayer(_ image: CGImage, monitor: Monitor, frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = monitor.frame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        layer.contentsGravity = .resizeAspectFill
        layer.contents = image
        return layer
    }

    fileprivate static func scale(for monitor: Monitor) -> CGFloat {
        NSScreen.screens.first(where: { $0.displayId == monitor.displayId })?.backingScaleFactor ?? 1
    }
}

@MainActor
private final class WorkspaceSwipePreviewPanel: NSPanel {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
