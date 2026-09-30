// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore

extension DwindleLayoutHandler {
    static let snapshotTransitionArmWindow: TimeInterval = 1.0

    var snapshotTransitionsEnabled: Bool {
        guard let controller else { return false }
        return controller.settings.dwindle.snapshotAnimations
            && controller.motionPolicy.snapshot().animationsEnabled
    }

    /// Marks the next relayout of `workspaceId` as a user command that should animate with snapshots.
    func armSnapshotTransition(for workspaceId: WorkspaceDescriptor.ID) {
        snapshotTransitionArm = (workspaceId, CACurrentMediaTime())
    }

    /// Runs a snapshot transition for an armed relayout. Returns `true` when the real windows should jump
    /// straight to `transition.newFrames` underneath the overlay.
    func startSnapshotTransition(
        _ transition: DwindleFrameTransition,
        snapshot: DwindleWorkspaceSnapshot
    ) -> Bool {
        guard let arm = snapshotTransitionArm, arm.workspaceId == snapshot.workspaceId else { return false }
        snapshotTransitionArm = nil
        guard CACurrentMediaTime() - arm.time < Self.snapshotTransitionArmWindow,
              snapshotTransitionsEnabled,
              snapshot.isActiveWorkspace,
              let controller,
              let monitor = controller.workspaceManager.monitor(byId: snapshot.monitor.monitorId)
        else { return false }
        let changed = transition.newFrames.contains { token, frame in
            guard let old = transition.oldFrames[token] ?? transition.previousTargetFrames[token] else { return false }
            return !old.approximatelyEqual(to: frame, tolerance: 1)
        }
        guard changed else { return false }
        let items = snapshotItems(workspaceId: snapshot.workspaceId, targets: transition.newFrames)
        guard snapshotTransition.begin(items: items, monitor: monitor, animated: true) else { return false }
        snapshotTransition.finish(after: WindowSnapshotTransition.duration, settled: snapshotSettledCheck(items))
        return true
    }

    func beginInteractiveSnapshotResize(workspaceId: WorkspaceDescriptor.ID, monitor: Monitor) {
        guard snapshotTransitionsEnabled else { return }
        let items = snapshotItems(workspaceId: workspaceId, targets: [:])
        interactiveSnapshotWorkspaceId = snapshotTransition.begin(items: items, monitor: monitor, animated: false)
            ? workspaceId
            : nil
    }

    /// Moves snapshots during an interactive resize. Returns `false` when the real windows must be updated.
    func updateInteractiveSnapshotResize(workspaceId: WorkspaceDescriptor.ID, monitor: Monitor) -> Bool {
        guard interactiveSnapshotWorkspaceId == workspaceId,
              snapshotTransition.isActive,
              let engine = controller?.dwindleEngine,
              let snapshot = makeWorkspaceSnapshot(
                  workspaceId: workspaceId,
                  monitor: monitor,
                  resolveConstraints: false,
                  isActiveWorkspace: true
              )
        else { return false }
        let frames = engine.calculateLayout(
            for: workspaceId,
            screen: snapshot.monitor.workingFrame,
            borderSafeFillScreen: snapshot.monitor.borderSafeFillFrame,
            fullscreenScreen: snapshot.monitor.fullscreenLayoutFrame,
            calculationSettings: calculationSettings(snapshot.settings, from: engine)
        )
        snapshotTransition.update(frames: Dictionary(
            frames.map { ($0.key.windowId, $0.value) },
            uniquingKeysWith: { _, last in last }
        ))
        return true
    }

    /// Ends an interactive snapshot resize; the following relayout writes the final frames once.
    func endInteractiveSnapshotResize(workspaceId: WorkspaceDescriptor.ID) {
        guard interactiveSnapshotWorkspaceId == workspaceId else { return }
        interactiveSnapshotWorkspaceId = nil
        guard let engine = controller?.dwindleEngine,
              let monitor = controller?.workspaceManager.monitor(for: workspaceId),
              let snapshot = makeWorkspaceSnapshot(
                  workspaceId: workspaceId,
                  monitor: monitor,
                  resolveConstraints: false,
                  isActiveWorkspace: true
              )
        else {
            snapshotTransition.stop()
            return
        }
        let frames = engine.calculateLayout(
            for: workspaceId,
            screen: snapshot.monitor.workingFrame,
            borderSafeFillScreen: snapshot.monitor.borderSafeFillFrame,
            fullscreenScreen: snapshot.monitor.fullscreenLayoutFrame,
            calculationSettings: calculationSettings(snapshot.settings, from: engine)
        )
        let items = frames
            .map { WindowSnapshotTransition.Item(windowId: $0.key.windowId, from: $0.value, to: $0.value) }
        snapshotTransition.finish(after: 0, settled: snapshotSettledCheck(items))
    }

    func cancelInteractiveSnapshotResize() {
        guard interactiveSnapshotWorkspaceId != nil else { return }
        interactiveSnapshotWorkspaceId = nil
        snapshotTransition.stop()
    }

    /// Visible managed windows of the workspace, bottom to top, with their target frames.
    func snapshotItems(
        workspaceId: WorkspaceDescriptor.ID,
        targets: [WindowToken: CGRect]
    ) -> [WindowSnapshotTransition.Item] {
        guard let controller,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let manager = controller.workspaceManager
        var tokenById: [Int: WindowToken] = [:]
        for entry in manager.entries(in: workspaceId)
            where manager.hiddenState(for: entry.token) == nil && !manager.isWindowSuppressedByMacOS(entry.token)
        {
            tokenById[entry.windowId] = entry.token
        }
        var items: [WindowSnapshotTransition.Item] = []
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowId = window[kCGWindowNumber as String] as? Int,
                  let token = tokenById[windowId],
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let cgFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            let frame = ScreenCoordinateSpace.toAppKit(rect: cgFrame)
            items.append(.init(windowId: windowId, from: frame, to: targets[token] ?? frame))
        }
        return items.reversed()
    }

    private func snapshotSettledCheck(_ items: [WindowSnapshotTransition.Item]) -> @MainActor () -> Bool {
        let targets = items
        return { [weak self] in
            guard let controller = self?.controller else { return true }
            return targets.allSatisfy { item in
                guard !controller.axManager.frameLedger.hasPendingFrameWrite(for: item.windowId) else { return false }
                guard let cgFrame = SkyLight.shared.getWindowBounds(UInt32(item.windowId)) else { return true }
                return ScreenCoordinateSpace.toAppKit(rect: cgFrame).approximatelyEqual(to: item.to, tolerance: 2)
            }
        }
    }
}
