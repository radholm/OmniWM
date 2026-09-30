// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit

extension WorkspaceSwipePresentation {
    /// Pans the parallax wallpaper on each display to its active workspace's position.
    func syncWallpaper() {
        // A running slide pans the wallpaper itself; `cancel` syncs again once it ends.
        guard flight == nil else { return }
        let targets = wallpaperTargets()
        guard !targets.isEmpty || wallpaperParallax != nil, let controller else { return }
        let parallax = wallpaperParallax ?? WorkspaceWallpaperParallax(
            ownedWindowRegistry: controller.ownedWindowRegistry
        )
        wallpaperParallax = parallax
        parallax.sync(targets, animated: controller.motionPolicy.animationsEnabled)
    }

    func wallpaperTargets() -> [WorkspaceWallpaperParallax.Target] {
        guard let controller, controller.hasStartedServices,
              controller.settings.gestures.workspaceWallpaperParallax
        else { return [] }
        let manager = controller.workspaceManager
        let axis = controller.settings.gestures.workspaceSwipeAxis
        return manager.monitors.compactMap { monitor in
            guard let position = wallpaperPosition(
                of: manager.activeWorkspaceOrFirst(on: monitor.id)?.id, on: monitor
            ) else { return nil }
            return WorkspaceWallpaperParallax.Target(monitor: monitor, position: position, axis: axis)
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
        let axis = controller?.settings.gestures.workspaceSwipeAxis ?? flight.axis
        return (from, WorkspaceWallpaperParallax.frame(for: monitor.frame, position: position, axis: axis))
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
