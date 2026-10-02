// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import QuartzCore

/// A 3D "stack of cards" effect for window snapshots that stay at their frame: cards pivot on their bottom edge.
enum SnapshotStackEffect: Equatable {
    /// Tips back and sinks while fading out, like a card laid down onto the stack.
    case out
    /// Rises up from tipped back while fading in, like the next card lifted off the stack.
    case `in`

    /// Perspective distance; smaller values exaggerate the depth.
    static let perspective: CGFloat = 1400

    private var angle: CGFloat {
        switch self {
        case .out: -.pi / 4
        case .in: -.pi / 7
        }
    }

    /// How far the card sinks, as a fraction of its height.
    private var drop: CGFloat {
        switch self {
        case .out: 0.14
        case .in: 0.08
        }
    }

    private var scale: CGFloat {
        switch self {
        case .out: 0.88
        case .in: 0.94
        }
    }

    /// The tipped-back pose: rotated back around the bottom edge, lowered and shrunk.
    func tippedTransform(height: CGFloat) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1 / Self.perspective
        transform = CATransform3DTranslate(transform, 0, -height * drop, 0)
        transform = CATransform3DRotate(transform, angle, 1, 0, 0)
        return CATransform3DScale(transform, scale, scale, 1)
    }

    /// Undoes a previous stack effect, so the layer can be placed by frame again.
    static func resetPose(of layer: CALayer) {
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    /// Plays the effect on `layer`, which is already placed at its frame.
    func animate(_ layer: CALayer, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.position = CGPoint(x: frame.midX, y: frame.minY)
        let tipped = tippedTransform(height: frame.height)
        let fromTransform = self == .out ? CATransform3DIdentity : tipped
        let toTransform = self == .out ? tipped : CATransform3DIdentity
        let toOpacity: Float = self == .out ? 0 : 1
        layer.transform = toTransform
        layer.opacity = toOpacity
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: fromTransform)
        transform.toValue = NSValue(caTransform3D: toTransform)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1 - toOpacity
        opacity.toValue = toOpacity
        let group = CAAnimationGroup()
        group.animations = [transform, opacity]
        group.duration = duration
        group.timingFunction = timing
        layer.add(group, forKey: "stack")
    }
}
