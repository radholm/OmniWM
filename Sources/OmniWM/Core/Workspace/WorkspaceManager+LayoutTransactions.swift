// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore

extension WorkspaceManager {
    @discardableResult
    func withEngineMutationScope<T>(
        in workspaceId: WorkspaceDescriptor.ID? = nil,
        label: String = "engine_mutation",
        source: WMEventSource = .command,
        _ body: () -> T
    ) -> T {
        var result: T?
        commitWorldEvent(
            .userCommand(workspaceId: workspaceId, label: label, source: source),
            monitors: monitors,
            preMutate: { result = body() },
            resolvePlan: { plan, _, _ in plan }
        )
        return result!
    }

    @discardableResult
    func withBatchedLayoutBuild(_ build: () -> [WorkspaceLayoutPlan]) -> [WorkspaceLayoutPlan] {
        var plans: [WorkspaceLayoutPlan] = []
        commitWorldEvent(
            .userCommand(workspaceId: nil, label: "layout_build", source: .layoutRefresh),
            monitors: monitors,
            preMutate: {
                plans = build()
                let committedSeq = self.worldSeq
                for index in plans.indices {
                    plans[index].sessionPatch.plannedSeq = committedSeq
                }
            },
            resolvePlan: { plan, _, _ in plan }
        )
        return plans
    }
}
