// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon
import Foundation
import QuartzCore
import ScreenCaptureKit

@MainActor
final class OverviewWindowFacts {
    private weak var wmController: WMController?
    private let environment: OverviewEnvironment

    init(wmController: WMController, environment: OverviewEnvironment) {
        self.wmController = wmController
        self.environment = environment
    }

    func windowFrame(_ entry: WindowState) -> CGRect? {
        environment.windowFrame(entry)
    }

    func makeOverviewWindowData(
        for entry: WindowState,
        preferredFrame: CGRect?,
        appInfoCache: AppInfoCache
    ) -> OverviewWindowLayoutData {
        let title = environment.windowTitle(entry) ?? ""
        let appInfo = appInfoCache.info(for: entry.pid)
        return OverviewWindowLayoutData(
            token: entry.token,
            workspaceId: entry.workspaceId,
            title: title.isEmpty ? (appInfo?.name ?? String(localized: "Window")) : title,
            appName: appInfo?.name ?? String(localized: "Unknown"),
            appIcon: appInfo?.icon,
            frame: preferredFrame ?? environment.windowFrame(entry) ?? .zero,
            isNativeFullscreen: entry.layoutReason == .nativeFullscreen,
            floatingPreviewFrame: floatingPreviewFrame(for: entry)
        )
    }

    func floatingPreviewFrame(for entry: WindowState) -> CGRect? {
        guard entry.mode == .floating else { return nil }
        return entry.desiredState.floatingFrame ?? entry.floatingState?.lastFrame
    }

    func visibleManagedEntry(for handle: WindowHandle) -> WindowState? {
        guard let workspaceManager = wmController?.workspaceManager,
              workspaceManager.handle(for: handle.id) === handle,
              let entry = workspaceManager.entry(for: handle),
              isOverviewEligible(entry, workspaceManager: workspaceManager)
        else {
            return nil
        }
        return entry
    }

    func isOverviewEligible(
        _ entry: WindowState,
        workspaceManager: WorkspaceManager
    ) -> Bool {
        !workspaceManager.isWindowSuppressedByMacOS(entry.token)
    }

    func isStructurallyMutable(_ entry: WindowState) -> Bool {
        entry.layoutReason == .standard
    }
}
