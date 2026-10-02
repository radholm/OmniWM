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
    /// Eases in and out so the tilt reads as a deliberate page turn instead of snapping into place.
    static var timing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
    }

    /// Cards with a 3D transform are depth-sorted against their siblings, so a card tipped back (negative z)
    /// would vanish behind the overlay's flat wallpaper layer. These lift the cards well above any tilt depth,
    /// the outgoing card above the incoming one.
    private var zPosition: CGFloat {
        switch self {
        case .out: 20000
        case .in: 10000
        }
    }

    /// Opacity over the effect: the outgoing card stays visible while it tips, the incoming one appears early.
    private var opacityKeyframes: (values: [Float], times: [NSNumber]) {
        switch self {
        case .out: ([1, 0.9, 0], [0, 0.45, 1])
        case .in: ([0, 1, 1], [0, 0.55, 1])
        }
    }

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

    /// Sideways shift as a fraction of the width: the stack swings to the left, so the outgoing card leaves
    /// leftwards and the incoming card arrives from slightly right.
    private var sideShift: CGFloat {
        switch self {
        case .out: -0.22
        case .in: 0.06
        }
    }

    /// Turn around the vertical axis; negative turns the card's left edge away, facing it to the left.
    private var yaw: CGFloat {
        switch self {
        case .out: -.pi / 9
        case .in: .pi / 24
        }
    }

    /// In-plane tilt; positive tilts counterclockwise (to the left).
    private var roll: CGFloat {
        switch self {
        case .out: .pi / 22
        case .in: -.pi / 45
        }
    }

    /// The tipped-back pose: swung to the side, tilted, rotated back around the bottom edge, lowered and shrunk.
    func tippedTransform(size: CGSize) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1 / Self.perspective
        transform = CATransform3DTranslate(transform, size.width * sideShift, -size.height * drop, 0)
        transform = CATransform3DRotate(transform, roll, 0, 0, 1)
        transform = CATransform3DRotate(transform, yaw, 0, 1, 0)
        transform = CATransform3DRotate(transform, angle, 1, 0, 0)
        return CATransform3DScale(transform, scale, scale, 1)
    }

    /// Undoes a previous stack effect, so the layer can be placed by frame again.
    static func resetPose(of layer: CALayer) {
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        layer.zPosition = 0
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    /// Plays the effect on `layer`, which is already placed at its frame.
    func animate(_ layer: CALayer, duration: CFTimeInterval) {
        let frame = layer.frame
        layer.zPosition = zPosition
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.position = CGPoint(x: frame.midX, y: frame.minY)
        let tipped = tippedTransform(size: frame.size)
        let fromTransform = self == .out ? CATransform3DIdentity : tipped
        let toTransform = self == .out ? tipped : CATransform3DIdentity
        let toOpacity: Float = self == .out ? 0 : 1
        layer.transform = toTransform
        layer.opacity = toOpacity
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: fromTransform)
        transform.toValue = NSValue(caTransform3D: toTransform)
        transform.timingFunction = Self.timing
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = opacityKeyframes.values
        opacity.keyTimes = opacityKeyframes.times
        let group = CAAnimationGroup()
        group.animations = [transform, opacity]
        group.duration = duration
        layer.add(group, forKey: "stack")
    }
}
