// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import CoreImage
import QuartzCore

/// One window snapshot in a `WindowSnapshotTransition`.
///
/// The captured image is never distorted: it is scaled uniformly to cover the animated frame and cropped from
/// the top-left, the way window content reflows, while a short blur hides the scaling during fast motion.
@MainActor
final class WindowSnapshotLayer {
    struct Motion {
        let start: CGRect
        let end: CGRect
        let beginTime: CFTimeInterval
        let peakBlur: CGFloat
    }

    static let maxBlur: CGFloat = 14
    static let cornerRadius: CGFloat = 12
    private static let blurName = "motionBlur"

    let layer = CALayer()
    private let image = CALayer()
    private var imageSize: CGSize
    private var fresh: (layer: CALayer, size: CGSize)?
    private(set) var motion: Motion?

    init(image contents: CGImage?) {
        imageSize = CGSize(width: contents?.width ?? 1, height: contents?.height ?? 1)
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: -8)
        Self.configure(image, contents: contents)
        layer.addSublayer(image)
    }

    var presentedFrame: CGRect {
        layer.presentation()?.frame ?? layer.frame
    }

    /// Moves to `end`, animating from `start` when they differ.
    func move(from start: CGRect, to end: CGRect, animated: Bool, fadeIn: Bool = false) {
        layer.removeAllAnimations()
        image.removeAllAnimations()
        promoteFreshContent()
        let start = animated ? start : end
        let motion = Motion(
            start: start,
            end: end,
            beginTime: CACurrentMediaTime(),
            peakBlur: fadeIn ? 0 : Self.peakBlur(from: start, to: end)
        )
        self.motion = motion
        place(at: end)
        guard start != end else { return }
        Self.animateFrame(layer, from: start, to: end, beginTime: motion.beginTime, local: false)
        animateContent(image, imageSize: imageSize, motion: motion)
        if fadeIn {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0
            opacity.toValue = 1
            opacity.duration = WindowSnapshotTransition.duration
            opacity.timingFunction = WindowSnapshotTransition.timing
            layer.add(opacity, forKey: "fadeIn")
        }
    }

    /// Fades freshly captured content in over the snapshot, following the running motion.
    func crossfade(to contents: CGImage) {
        guard let motion else { return }
        fresh?.layer.removeFromSuperlayer()
        let freshLayer = CALayer()
        let size = CGSize(width: contents.width, height: contents.height)
        Self.configure(freshLayer, contents: contents)
        freshLayer.frame = CGRect(origin: .zero, size: motion.end.size)
        freshLayer.contentsRect = Self.cropRect(frameSize: motion.end.size, imageSize: size)
        if motion.start != motion.end {
            animateContent(freshLayer, imageSize: size, motion: motion)
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = WindowSnapshotTransition.crossfadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        freshLayer.add(fade, forKey: "crossfade")
        layer.addSublayer(freshLayer)
        fresh = (freshLayer, size)
    }

    private func promoteFreshContent() {
        guard let fresh else { return }
        image.contents = fresh.layer.contents
        imageSize = fresh.size
        fresh.layer.removeFromSuperlayer()
        self.fresh = nil
    }

    private func place(at frame: CGRect) {
        layer.frame = frame
        layer.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: frame.size),
            cornerWidth: Self.cornerRadius,
            cornerHeight: Self.cornerRadius,
            transform: nil
        )
        image.frame = CGRect(origin: .zero, size: frame.size)
        image.contentsRect = Self.cropRect(frameSize: frame.size, imageSize: imageSize)
    }

    private func animateContent(_ content: CALayer, imageSize: CGSize, motion: Motion) {
        Self.animateFrame(content, from: motion.start, to: motion.end, beginTime: motion.beginTime, local: true)
        let crop = CABasicAnimation(keyPath: "contentsRect")
        crop.fromValue = NSValue(rect: Self.cropRect(frameSize: motion.start.size, imageSize: imageSize))
        crop.toValue = NSValue(rect: Self.cropRect(frameSize: motion.end.size, imageSize: imageSize))
        Self.time(crop, beginTime: motion.beginTime)
        content.add(crop, forKey: "crop")
        guard motion.peakBlur > 0 else { return }
        let blur = CAKeyframeAnimation(keyPath: "filters.\(Self.blurName).inputRadius")
        blur.values = [0, motion.peakBlur, motion.peakBlur * 0.35, 0]
        blur.keyTimes = [0, 0.18, 0.5, 0.8]
        blur.beginTime = motion.beginTime
        blur.duration = WindowSnapshotTransition.duration
        blur.fillMode = .both
        blur.isRemovedOnCompletion = true
        content.add(blur, forKey: "blur")
    }

    private static func animateFrame(
        _ layer: CALayer,
        from start: CGRect,
        to end: CGRect,
        beginTime: CFTimeInterval,
        local: Bool
    ) {
        let bounds = CABasicAnimation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: CGRect(origin: .zero, size: start.size))
        bounds.toValue = NSValue(rect: CGRect(origin: .zero, size: end.size))
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: local
            ? CGPoint(x: start.width / 2, y: start.height / 2)
            : CGPoint(x: start.midX, y: start.midY))
        position.toValue = NSValue(point: local
            ? CGPoint(x: end.width / 2, y: end.height / 2)
            : CGPoint(x: end.midX, y: end.midY))
        let group = CAAnimationGroup()
        group.animations = [bounds, position]
        time(group, beginTime: beginTime)
        layer.add(group, forKey: "frame")
    }

    private static func time(_ animation: CAAnimation, beginTime: CFTimeInterval) {
        animation.beginTime = beginTime
        animation.duration = WindowSnapshotTransition.duration
        animation.timingFunction = WindowSnapshotTransition.timing
        animation.fillMode = .both
    }

    private static func configure(_ layer: CALayer, contents: CGImage?) {
        layer.contents = contents
        layer.contentsGravity = .resize
        layer.masksToBounds = true
        layer.cornerRadius = cornerRadius
        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.name = blurName
        blur?.setValue(0, forKey: kCIInputRadiusKey)
        layer.filters = blur.map { [$0] }
    }

    /// Blur strength for a move: stronger for bigger changes, none for tiny ones.
    static func peakBlur(from start: CGRect, to end: CGRect) -> CGFloat {
        let change = max(
            abs(start.width - end.width),
            abs(start.height - end.height),
            hypot(start.midX - end.midX, start.midY - end.midY)
        )
        guard change >= 24 else { return 0 }
        return min(maxBlur, max(3, change / 60))
    }

    /// The part of an image (unit coordinates) that fills `frameSize` when scaled uniformly to cover it,
    /// anchored at the top-left corner.
    static func cropRect(frameSize: CGSize, imageSize: CGSize) -> CGRect {
        guard frameSize.width > 0, frameSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let scale = max(frameSize.width / imageSize.width, frameSize.height / imageSize.height)
        let width = min(1, frameSize.width / (imageSize.width * scale))
        let height = min(1, frameSize.height / (imageSize.height * scale))
        return CGRect(x: 0, y: 1 - height, width: width, height: height)
    }
}
