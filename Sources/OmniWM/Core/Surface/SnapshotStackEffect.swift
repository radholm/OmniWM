// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import QuartzCore

/// Moves a window snapshot within a 3D deck of cards. Depth 0 is the top card at the snapshot's frame; deeper
/// cards sit slightly zoomed out behind it. Paging rotates the deck: the top card moves down and slides back up
/// under the next card; then every other card moves up one place, the next card zooming into view.
struct SnapshotStackEffect: Equatable {
    let fromDepth: Int
    let toDepth: Int
    /// The card leaves the top by zooming out and flying under the next card to the back of the deck.
    var tucksUnder = false

    /// Perspective distance; smaller values exaggerate the depth.
    static let perspective: CGFloat = 1400
    /// Per depth level: how much smaller and how far leaned back a card is.
    static let depthScale: CGFloat = 0.08
    static let depthLean: CGFloat = -.pi / 180
    /// Cards deeper than this are hidden.
    static let visibleDepth = 3

    /// Eases in and out so the page turn reads as one deliberate motion.
    static var timing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
    }

    /// Starts moving at once, so the page turn responds immediately to the key press.
    static var departTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.4, 1)
    }

    /// Cards with a 3D transform are depth-sorted against their siblings, so cards leaning back (negative z)
    /// would vanish behind the overlay's flat wallpaper layer. Deck positions sit far above any tilt depth,
    /// higher for cards nearer the top.
    static func zPosition(depth: Int) -> CGFloat {
        20000 - CGFloat(depth) * 2000
    }

    /// The leaving card stays above the deck only until it has dipped away, then it slides under the next card.
    static let tuckZPosition: CGFloat = 30000
    /// The leaving card moves along one continuous path for the whole page turn: down and back up under the
    /// next card into its place in the deck. It starts gently and slows into place (ease-in-out), reaching its lowest
    /// point at `orderSwapTime`, where it passes behind the next card. The other cards wait until then and move
    /// up one place, the next card zooming into view.
    /// The leaving card drops far enough, and shrinks a little, to clear most of the next card before it passes
    /// behind it, so the next card is revealed rather than dropped over it.
    static let tuckDrop: CGFloat = 0.7
    static let tuckShrink: CGFloat = 0.08
    static let tuckSamples = 24
    static let orderSwapTime: NSNumber = 0.5
    static let advanceStartTime = orderSwapTime

    static func opacity(depth: Int) -> Float {
        depth > visibleDepth ? 0 : 1
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

    /// Pose of the leaving card at `progress` (0...1) along its path from the top to `depth` in the deck:
    /// it settles into the deck pose while dipping down by up to `tuckDrop` of its height and back up.
    static func tuckPose(progress: CGFloat, toDepth depth: Int, size: CGSize) -> CATransform3D {
        let level = CGFloat(min(depth, visibleDepth + 1)) * progress
        let dip = sin(.pi * progress)
        let scale = max(0.2, 1 - depthScale * level - tuckShrink * dip)
        var transform = CATransform3DIdentity
        transform.m34 = -1 / perspective
        transform = CATransform3DTranslate(
            transform, 0, size.height * (1 - scale) / 2 - size.height * tuckDrop * dip, 0
        )
        transform = CATransform3DRotate(transform, depthLean * level - .pi / 90 * dip, 1, 0, 0)
        return CATransform3DScale(transform, scale, scale, 1)
    }

    /// Ease-in-out progress for `time` (0...1): starts gently, speeds up and slows into place.
    static func tuckProgress(_ time: CGFloat) -> CGFloat {
        (1 - cos(.pi * time)) / 2
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
            // Stays fully visible and keeps moving the whole time: down, then back up under the next card.
            let times = (0 ... Self.tuckSamples).map { CGFloat($0) / CGFloat(Self.tuckSamples) }
            transform.values = times.map {
                NSValue(caTransform3D: Self.tuckPose(
                    progress: Self.tuckProgress($0), toDepth: toDepth, size: frame.size
                ))
            }
            transform.keyTimes = times.map { NSNumber(value: Double($0)) }
            opacity.values = [Self.opacity(depth: fromDepth), endOpacity]
            zPosition.values = [Self.tuckZPosition, endZ]
        } else {
            // Waits until the leaving card passes under it, then moves up one place.
            transform.values = [start, start, end].map { NSValue(caTransform3D: $0) }
            transform.keyTimes = [0, Self.advanceStartTime, 1]
            transform.timingFunctions = [Self.timing, Self.departTiming]
            opacity.values = [Self.opacity(depth: fromDepth), endOpacity]
            zPosition.values = [Self.zPosition(depth: fromDepth), endZ]
        }
        let group = CAAnimationGroup()
        group.animations = [transform, opacity, zPosition]
        group.duration = duration
        layer.add(group, forKey: "stack")
    }
}
