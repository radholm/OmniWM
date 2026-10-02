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

    /// Carries the motion through without stopping between phases.
    static var throughTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeInEaseOut)
    }

    /// Cards with a 3D transform are depth-sorted against their siblings, so cards leaning back (negative z)
    /// would vanish behind the overlay's flat wallpaper layer. Deck positions sit far above any tilt depth,
    /// higher for cards nearer the top.
    static func zPosition(depth: Int) -> CGFloat {
        20000 - CGFloat(depth) * 2000
    }

    /// The leaving card stays above the deck only until it has dipped away, then it slides under the next card.
    static let tuckZPosition: CGFloat = 30000
    /// Phases of a page turn, as fractions of its duration: the leaving card moves down until `tuckDownTime`,
    /// passes behind the next card and slides back up under it until `tuckedTime`. The other cards wait until
    /// `advanceStartTime`, then move up one place, the next card zooming into view.
    static let tuckDownTime: NSNumber = 0.4
    static let tuckedTime: NSNumber = 0.75
    static let advanceStartTime: NSNumber = 0.5
    static let orderSwapTime: NSNumber = tuckDownTime

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

    /// How far the leaving card zooms out as it flies back under the next one.
    static let tuckScale: CGFloat = 0.92

    /// Pose of the leaving card once it has moved down, barely smaller, so the waiting next card shows above it;
    /// tipped back a little. From here it slides back up in under the next card.
    static func tuckPose(size: CGSize) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1 / perspective
        transform = CATransform3DTranslate(
            transform, 0, -size.height * 0.28, 0
        )
        transform = CATransform3DRotate(transform, -.pi / 90, 1, 0, 0)
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
            // Stays fully visible: moves down, then slides back up under the next card and stays there.
            let tuck = Self.tuckPose(size: frame.size)
            transform.values = [start, tuck, end, end].map { NSValue(caTransform3D: $0) }
            transform.keyTimes = [0, Self.tuckDownTime, Self.tuckedTime, 1]
            transform.timingFunctions = [Self.departTiming, Self.throughTiming, Self.timing]
            opacity.values = [Self.opacity(depth: fromDepth), endOpacity]
            zPosition.values = [Self.tuckZPosition, endZ]
        } else {
            // Waits until the leaving card is tucked under, then moves up one place.
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
