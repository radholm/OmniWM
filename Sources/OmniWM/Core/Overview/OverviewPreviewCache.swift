// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

extension OverviewThumbnailCapture {
    var cachedByteCount: Int {
        previewCache.values.reduce(0) { $0 + $1.frame.surface.allocationSize }
    }

    var residentByteCount: Int {
        previewCache.reduce(0) { $0 + (residentHandles.contains($1.key) ? $1.value.frame.surface.allocationSize : 0) }
    }

    var retainedByteCount: Int {
        cachedByteCount - residentByteCount
    }

    /// Represented frames stay resident for presentation; only idle history is evictable.
    /// Resident bytes consume the budget, so oversize presentations retain no unrelated history.
    func trimRetainedPreviews() {
        guard cachedByteCount > maximumRetainedBytes else { return }
        guard retainedByteCount > 0 else { return }
        var remaining = max(0, maximumRetainedBytes - residentByteCount)
        for (handle, preview) in previewCache.sorted(by: { $0.value.lastRequestedUse > $1.value.lastRequestedUse })
            where !residentHandles.contains(handle)
        {
            let bytes = preview.frame.surface.allocationSize
            if bytes <= remaining {
                remaining -= bytes
            } else {
                removeCachedPreview(for: handle, reason: .budget)
                onPreview(handle, nil)
            }
        }
    }
}
