// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
import Synchronization

/// A native capture cannot be interrupted, but cancellation prevents every subsequent capture and conversion.
final class WorkspaceSwipeSnapshot: Sendable {
    struct Request: Sendable {
        let token: WindowToken
        let pixelWidth: Int
        let pixelHeight: Int
    }

    private final class Cancellation: Sendable {
        let removed = Mutex<Set<WindowToken>>([])
    }

    private let cancellation: Cancellation
    let task: Task<[OverviewPreviewFrame?], Never>

    init(requests: [Request], capture: @escaping @Sendable (UInt32) -> CGImage?) {
        let cancellation = Cancellation()
        self.cancellation = cancellation
        task = Task.detached(priority: .userInitiated) {
            var frames: [OverviewPreviewFrame?] = []
            for request in requests {
                guard !Task.isCancelled else { return [] }
                guard !cancellation.removed.withLock({ $0.contains(request.token) }) else {
                    frames.append(nil)
                    continue
                }
                let frame = autoreleasepool {
                    let image = capture(UInt32(request.token.windowId))
                    guard !Task.isCancelled,
                          !cancellation.removed.withLock({ $0.contains(request.token) })
                    else { return nil as OverviewPreviewFrame? }
                    return image.flatMap {
                        OverviewPreviewFrame(
                            image: $0, pixelWidth: request.pixelWidth, pixelHeight: request.pixelHeight
                        )
                    }
                }
                guard !Task.isCancelled else { return [] }
                frames.append(cancellation.removed.withLock { $0.contains(request.token) } ? nil : frame)
            }
            return frames
        }
    }

    func cancel(token: WindowToken) {
        cancellation.removed.withLock { _ = $0.insert(token) }
    }

    func cancel() {
        task.cancel()
    }
}
