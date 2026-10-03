// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import CoreVideo
import IOSurface

final class OverviewPreviewFrame: @unchecked Sendable {
    private let pixelBuffer: CVPixelBuffer
    let surface: IOSurface
    let contentsRect: CGRect

    init?(pixelBuffer: CVPixelBuffer, contentRect: CGRect? = nil, scaleFactor: CGFloat = 1) {
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 0, height > 0, scaleFactor.isFinite, scaleFactor > 0 else { return nil }
        if let contentRect {
            let normalized = CGRect(
                x: contentRect.minX * scaleFactor / width,
                y: contentRect.minY * scaleFactor / height,
                width: contentRect.width * scaleFactor / width,
                height: contentRect.height * scaleFactor / height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !normalized.isNull, !normalized.isEmpty else { return nil }
            contentsRect = normalized
        } else {
            contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        self.surface = surface
        self.pixelBuffer = pixelBuffer
    }
}

extension OverviewPreviewFrame {
    /// Wraps a window-server snapshot in an IOSurface-backed frame, so it can stand in for a stream frame.
    convenience init?(image: CGImage) {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &buffer
        ) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        self.init(pixelBuffer: buffer)
    }
}
