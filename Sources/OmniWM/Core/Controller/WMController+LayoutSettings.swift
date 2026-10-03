// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC

extension WMController {
    func updateMonitorOrientations() {
        var orientations: [Monitor.ID: Monitor.Orientation] = [:]
        for monitor in workspaceManager.monitors {
            orientations[monitor.id] = settings.monitors.effectiveOrientation(for: monitor)
        }
        layoutRefreshController.requestRelayout(reason: .monitorSettingsChanged)
    }

    func updateMonitorDwindleSettings() {
        guard dwindleEngine != nil else { return }
        workspaceManager.invalidateAllLayouts()
        layoutRefreshController.requestRelayout(reason: .monitorSettingsChanged)
    }

    func updateMonitorGapSettings() {
        workspaceManager.invalidateAllLayouts()
        layoutRefreshController.requestRelayout(reason: .monitorSettingsChanged)
        publishDisplayChanged()
    }

    func publishDisplayChanged() {
        guard let ipcApplicationBridge else { return }
        Task {
            await ipcApplicationBridge.publishEvent(.displayChanged)
        }
    }

    func updateWorkspaceConfig() {
        workspaceManager.applySettings()
        layoutRefreshController.requestRelayout(reason: .workspaceConfigChanged)
    }

    func rebuildAppRulesCache() {
        windowRuleEngine.rebuild(rules: settings.appRules)
    }

    func updateAppRules() {
        rebuildAppRulesCache()
        layoutRefreshController.requestFullRescan(reason: .appRulesChanged)
    }

    func enableDwindleLayout() {
        dwindleLayoutHandler.enableDwindleLayout()
    }

    func updateDwindleConfig(
        smartSplit: Bool? = nil,
        defaultSplitRatio: CGFloat? = nil,
        splitWidthMultiplier: CGFloat? = nil,
        singleWindowFit: SingleWindowFit? = nil,
        innerGap: CGFloat? = nil
    ) {
        dwindleLayoutHandler.updateDwindleConfig(
            smartSplit: smartSplit,
            defaultSplitRatio: defaultSplitRatio,
            splitWidthMultiplier: splitWidthMultiplier,
            singleWindowFit: singleWindowFit,
            innerGap: innerGap
        )
    }

    var dwindleEngine: DwindleLayoutEngine? {
        get { workspaceManager.dwindleEngine }
        set {
            if let current = workspaceManager.dwindleEngine, current !== newValue {
                layoutRefreshController.stopAllDwindleAnimations()
            }
            workspaceManager.dwindleEngine = newValue
        }
    }
}
