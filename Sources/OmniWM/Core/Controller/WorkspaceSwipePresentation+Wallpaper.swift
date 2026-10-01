// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Observation

extension WorkspaceSwipePresentation {
    /// Pans the parallax wallpaper on each display to its active workspace's position.
    func syncWallpaper() {
        // A running slide pans the wallpaper itself; `cancel` syncs again once it ends.
        guard flight == nil else { return }
        observeWallpaperSettings()
        let targets = wallpaperTargets()
        guard !targets.isEmpty || wallpaperParallax != nil, let controller else { return }
        let parallax = wallpaperParallax ?? {
            let parallax = WorkspaceWallpaperParallax(ownedWindowRegistry: controller.ownedWindowRegistry)
            parallax.animationSpeed = { [weak controller] in controller?.motionPolicy.animationSpeed ?? 1 }
            return parallax
        }()
        wallpaperParallax = parallax
        parallax.sync(targets, animated: controller.motionPolicy.animationsEnabled)
    }

    /// Re-syncs when the parallax settings change, so the Settings slider applies live.
    private func observeWallpaperSettings() {
        guard !observesWallpaperSettings, let gestures = controller?.settings.gestures else { return }
        observesWallpaperSettings = true
        withObservationTracking {
            _ = gestures.workspaceWallpaperParallax
            _ = gestures.workspaceWallpaperParallaxAmount
            _ = gestures.workspaceSwipeAxis
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observesWallpaperSettings = false
                self?.syncWallpaper()
            }
        }
    }

    func wallpaperTargets() -> [WorkspaceWallpaperParallax.Target] {
        guard let controller, controller.hasStartedServices,
              controller.settings.gestures.workspaceWallpaperParallax
        else { return [] }
        let manager = controller.workspaceManager
        let axis = controller.settings.gestures.workspaceSwipeAxis
        let overscan = CGFloat(controller.settings.gestures.workspaceWallpaperParallaxAmount)
        return manager.monitors.compactMap { monitor in
            guard let position = wallpaperPosition(
                of: manager.activeWorkspaceOrFirst(on: monitor.id)?.id, on: monitor
            ) else { return nil }
            return WorkspaceWallpaperParallax.Target(
                monitor: monitor, position: position, axis: axis, overscan: overscan
            )
        }
    }

    func wallpaperPosition(of workspaceId: WorkspaceDescriptor.ID?, on monitor: Monitor) -> CGFloat? {
        guard let controller, let workspaceId else { return nil }
        let order = controller.workspaceManager.workspaces(on: monitor.id).map(\.id)
        guard let index = order.firstIndex(of: workspaceId) else { return nil }
        return WorkspaceWallpaperParallax.position(index: index, count: order.count)
    }

    /// Wallpaper frames at the start and end of `flight`, or `nil` when the parallax wallpaper is off.
    func wallpaperMotion(for flight: Flight) -> (from: CGRect, to: CGRect)? {
        let monitor = flight.preparation.monitor
        guard let parallax = wallpaperParallax, let from = parallax.wallpaperFrame(on: monitor),
              let position = wallpaperPosition(of: flight.destination.id, on: monitor)
        else { return nil }
        let gestures = controller?.settings.gestures
        let target = WorkspaceWallpaperParallax.Target(
            monitor: monitor, position: position, axis: gestures?.workspaceSwipeAxis ?? flight.axis,
            overscan: CGFloat(gestures?.workspaceWallpaperParallaxAmount ?? 0.1)
        )
        return (from, WorkspaceWallpaperParallax.frame(for: target))
    }

    /// Moves the desktop wallpaper along with `flight` and returns the frame the preview should draw it at.
    func panWallpaper(for flight: Flight) -> CGRect? {
        guard let motion = flight.wallpaper else { return nil }
        let progress = min(max(CGFloat(flight.progress), 0), 1)
        let frame = WorkspaceWallpaperParallax.interpolate(motion.from, motion.to, progress: progress)
        wallpaperParallax?.pan(displayId: flight.preparation.monitor.displayId, to: frame)
        return frame
    }
}
