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
    convenience init?(image: CGImage, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        let size = Self.snapshotSize(
            imageWidth: image.width, imageHeight: image.height,
            pixelWidth: pixelWidth ?? image.width, pixelHeight: pixelHeight ?? image.height
        )
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &buffer
        ) == kCVReturnSuccess, let buffer else { return nil }
        // Keeping the snapshot's own color space turns the draw into a copy instead of a per-pixel conversion;
        // the surface is tagged so Core Animation still color-matches it.
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpaceCreateDeviceRGB()
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        if let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue(),
           let properties = space.copyPropertyList()
        {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, properties)
        }
        self.init(pixelBuffer: buffer)
    }

    static func snapshotSize(
        imageWidth: Int, imageHeight: Int, pixelWidth: Int, pixelHeight: Int
    ) -> (width: Int, height: Int) {
        let scale = min(
            1, Double(max(1, pixelWidth)) / Double(max(1, imageWidth)),
            Double(max(1, pixelHeight)) / Double(max(1, imageHeight))
        )
        return (
            max(1, Int((Double(imageWidth) * scale).rounded(.down))),
            max(1, Int((Double(imageHeight) * scale).rounded(.down)))
        )
    }

    func covers(_ request: OverviewPreviewRequest) -> Bool {
        CGFloat(surface.width) * contentsRect.width + 1 >= CGFloat(request.pixelWidth)
            && CGFloat(surface.height) * contentsRect.height + 1 >= CGFloat(request.pixelHeight)
    }
}
