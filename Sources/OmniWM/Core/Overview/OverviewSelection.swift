// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit

enum OverviewSelection: Equatable {
    case window(WindowHandle)
    case workspace(WorkspaceDescriptor.ID)
    case newWorkspace(Monitor.ID)

    var windowHandle: WindowHandle? {
        guard case let .window(handle) = self else { return nil }
        return handle
    }

    func frame(in layout: OverviewLayout) -> CGRect? {
        switch self {
        case let .window(handle):
            layout.window(for: handle)?.overviewFrame
        case let .workspace(id):
            layout.workspaceSections.first { $0.workspaceId == id && $0.isEmpty }?.visibleFrame
        case let .newWorkspace(id):
            layout.newWorkspaceTarget.flatMap { $0.monitorId == id ? $0.frame : nil }
        }
    }
}

extension OverviewNavigation {
    static func selections(in layout: OverviewLayout, searching: Bool) -> [OverviewSelection] {
        var selections: [OverviewSelection] = []
        for section in layout.workspaceSections {
            if section.isEmpty, !searching {
                selections.append(.workspace(section.workspaceId))
            } else {
                selections.append(contentsOf: section.windows.filter(\.matchesSearch).map { .window($0.handle) })
            }
        }
        if !searching, let target = layout.newWorkspaceTarget {
            selections.append(.newWorkspace(target.monitorId))
        }
        return selections
    }

    static func cycledSelection(
        in layout: OverviewLayout,
        from current: OverviewSelection?,
        forward: Bool,
        searching: Bool
    ) -> OverviewSelection? {
        let candidates = selections(in: layout, searching: searching)
        guard !candidates.isEmpty else { return nil }
        guard let current, let index = candidates.firstIndex(of: current) else { return candidates.first }
        let nextIndex = index + (forward ? 1 : -1)
        return candidates.indices.contains(nextIndex) ? candidates[nextIndex] : current
    }

    static func nextSelection(
        in layout: OverviewLayout,
        from current: OverviewSelection?,
        direction: Direction,
        searching: Bool
    ) -> OverviewSelection? {
        let candidates = selections(in: layout, searching: searching)
        guard let current, candidates.contains(current), let frame = current.frame(in: layout) else {
            return candidates.first
        }
        if direction == .left || direction == .right {
            let inSection = current.windowHandle.flatMap {
                findNextWindow(in: layout, from: $0, direction: direction).map(OverviewSelection.window)
            }
            if let inSection, inSection != current { return inSection }
            return neighborInRow(
                of: current,
                frame: frame,
                in: layout,
                candidates: candidates,
                movingLeft: direction == .left
            )
                ?? inSection ?? current
        }
        let movingUp = direction == .up
        let windowCandidate = current.windowHandle.flatMap {
            findNextWindow(in: layout, from: $0, direction: direction).map(OverviewSelection.window)
        }
        var best = windowCandidate
        var bestDistance = best?.frame(in: layout).map { abs($0.midY - frame.midY) } ?? .infinity
        var bestHorizontal = best?.frame(in: layout).map { abs($0.midX - frame.midX) } ?? .infinity
        for candidate in candidates where candidate != current {
            if let handle = candidate.windowHandle {
                if current.windowHandle != nil || layout.window(for: handle)?.isDisplayed != true { continue }
            }
            guard let candidateFrame = candidate.frame(in: layout) else { continue }
            let delta = candidateFrame.midY - frame.midY
            guard movingUp ? delta > 0 : delta < 0 else { continue }
            let distance = abs(delta)
            let horizontal = abs(candidateFrame.midX - frame.midX)
            if distance < bestDistance || (distance == bestDistance && horizontal < bestHorizontal) {
                best = candidate
                bestDistance = distance
                bestHorizontal = horizontal
            }
        }
        return best ?? current
    }

    private static func workspaceId(of selection: OverviewSelection, in layout: OverviewLayout) -> WorkspaceDescriptor
        .ID?
    {
        switch selection {
        case let .window(handle): layout.window(for: handle)?.workspaceId
        case let .workspace(id): id
        case .newWorkspace: nil
        }
    }

    /// Nearest selection in another workspace cell on the same grid row; list layouts never have one.
    private static func neighborInRow(
        of current: OverviewSelection,
        frame: CGRect,
        in layout: OverviewLayout,
        candidates: [OverviewSelection],
        movingLeft: Bool
    ) -> OverviewSelection? {
        let currentWorkspace = workspaceId(of: current, in: layout)
        let row = layout.workspaceSections.first { $0.workspaceId == currentWorkspace }?.sectionFrame ?? frame
        var best: OverviewSelection?
        var bestDistance = CGSize(width: CGFloat.infinity, height: .infinity)
        for candidate in candidates where candidate != current {
            let candidateWorkspace = workspaceId(of: candidate, in: layout)
            guard candidateWorkspace != currentWorkspace || candidateWorkspace == nil,
                  let candidateFrame = candidate.frame(in: layout),
                  candidateFrame.midY >= row.minY, candidateFrame.midY <= row.maxY
            else { continue }
            if let handle = candidate.windowHandle, layout.window(for: handle)?.isDisplayed != true { continue }
            let delta = candidateFrame.midX - frame.midX
            guard movingLeft ? delta < -0.5 : delta > 0.5 else { continue }
            let horizontal = abs(delta)
            let vertical = abs(candidateFrame.midY - frame.midY)
            if horizontal < bestDistance.width - 0.5
                || (abs(horizontal - bestDistance.width) <= 0.5 && vertical < bestDistance.height)
            {
                best = candidate
                bestDistance = CGSize(width: horizontal, height: vertical)
            }
        }
        return best
    }
}
