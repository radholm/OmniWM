// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import QuartzCore

/// Moves a window snapshot within a 3D deck of cards. Depth 0 is the top card at the snapshot's frame; deeper
/// cards sit zoomed out and dimmer behind it. Paging rotates the deck: the top card zooms out and flies back under
/// the next card while every other card moves up one place, the next card zooming in to full size.
struct SnapshotStackEffect: Equatable {
    let fromDepth: Int
    let toDepth: Int
    /// The card leaves the top by zooming out and flying under the next card to the back of the deck.
    var tucksUnder = false

    /// Perspective distance; smaller values exaggerate the depth.
    static let perspective: CGFloat = 1400
    /// Per depth level: how much smaller and how far leaned back a card is.
    static let depthScale: CGFloat = 0.25
    static let depthLean: CGFloat = -.pi / 60
    /// Cards deeper than this are hidden.
    static let visibleDepth = 3

    /// Eases in and out so the page turn reads as one deliberate motion.
    static var timing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
    }

    /// Cards with a 3D transform are depth-sorted against their siblings, so cards leaning back (negative z)
    /// would vanish behind the overlay's flat wallpaper layer. Deck positions sit far above any tilt depth,
    /// higher for cards nearer the top.
    static func zPosition(depth: Int) -> CGFloat {
        20000 - CGFloat(depth) * 2000
    }

    /// The leaving card stays above the deck only until it has dipped away, then it slides under the next card.
    static let tuckZPosition: CGFloat = 30000
    static let orderSwapTime: NSNumber = 0.3

    static func opacity(depth: Int) -> Float {
        depth > visibleDepth ? 0 : 1 - Float(depth) * 0.22
    }

    /// The card's resting pose at `depth` in the deck: zoomed out around its centre (it pivots on its bottom
    /// edge, so it is raised by half the size it loses) and leaned back slightly.
    static func pose(depth: Int, size: CGSize) -> CATransform3D {
        let level = CGFloat(min(depth, visibleDepth + 1))
        let scale = max(0.2, 1 - depthScale * level)
        var transform = CATransform3DIdentity
        transform.m34 = -1 / perspective
        transform = CATransform3DTranslate(transform, 0, size.height * (1 - scale) / 2, 0)
        transform = CATransform3DRotate(transform, depthLean * level, 1, 0, 0)
        return CATransform3DScale(transform, scale, scale, 1)
    }

    /// How far the leaving card zooms out as it flies back under the next one.
    static let tuckScale: CGFloat = 0.62

    /// Pose of the leaving card as it flies under the next one: zoomed out around its centre, nudged left and
    /// tipped back a little.
    static func tuckPose(size: CGSize) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1 / perspective
        transform = CATransform3DTranslate(
            transform, -size.width * 0.06, size.height * (1 - tuckScale) / 2, 0
        )
        transform = CATransform3DRotate(transform, -.pi / 30, 1, 0, 0)
        return CATransform3DScale(transform, tuckScale, tuckScale, 1)
    }

    /// Undoes a previous stack effect, so the layer can be placed by frame again.
    static func resetPose(of layer: CALayer) {
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        layer.zPosition = 0
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    /// Plays the effect on `layer`, which is already placed at the top card's frame.
    func animate(_ layer: CALayer, duration: CFTimeInterval) {
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.position = CGPoint(x: frame.midX, y: frame.minY)
        let start = Self.pose(depth: fromDepth, size: frame.size)
        let end = Self.pose(depth: toDepth, size: frame.size)
        let endOpacity = Self.opacity(depth: toDepth)
        let endZ = Self.zPosition(depth: toDepth)
        layer.transform = end
        layer.opacity = endOpacity
        layer.zPosition = endZ

        let transform = CAKeyframeAnimation(keyPath: "transform")
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        let zPosition = CAKeyframeAnimation(keyPath: "zPosition")
        zPosition.calculationMode = .discrete
        // Discrete keyframes take one more key time than values.
        zPosition.keyTimes = [0, Self.orderSwapTime, 1]
        if tucksUnder {
            let tuck = Self.tuckPose(size: frame.size)
            transform.values = [start, tuck, end].map { NSValue(caTransform3D: $0) }
            transform.keyTimes = [0, 0.45, 1]
            transform.timingFunctions = [Self.timing, Self.timing]
            // Fades quickly while it slides under, then settles at its dimmed place at the back of the deck.
            opacity.values = [Self.opacity(depth: fromDepth), 0.25, endOpacity]
            opacity.keyTimes = [0, 0.3, 1]
            zPosition.values = [Self.tuckZPosition, endZ]
        } else {
            transform.values = [start, end].map { NSValue(caTransform3D: $0) }
            transform.timingFunctions = [Self.timing]
            opacity.values = [Self.opacity(depth: fromDepth), endOpacity]
            zPosition.values = [Self.zPosition(depth: fromDepth), endZ]
        }
        let group = CAAnimationGroup()
        group.animations = [transform, opacity, zPosition]
        group.duration = duration
        layer.add(group, forKey: "stack")
    }
}
