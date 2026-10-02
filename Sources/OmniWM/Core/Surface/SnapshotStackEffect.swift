// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import QuartzCore

/// Pages a window snapshot through a 3D deck of cards. A page turn has three phases:
/// 1. Zoom out: every stacked window shrinks into a deck fanned out towards the bottom right, the current window
///    at the front (top left), so the deck shows how many windows are stacked.
/// 2. Tuck: the current window dips below the deck and slides in at its back (bottom right) while every other
///    card moves up one place.
/// 3. Zoom in: the deck grows back to full size around the new front card, the next window.
/// Depth 0 is the front of the deck; `deckSize` is the number of cards.
struct SnapshotStackEffect: Equatable {
    let fromDepth: Int
    let toDepth: Int
    var deckSize = 2
    /// The card leaves the front by dipping below the deck and sliding in at its back.
    var tucksUnder = false

    /// Perspective distance; smaller values exaggerate the depth.
    static let perspective: CGFloat = 1600
    /// Size of the cards while the deck is shown, as a fraction of their full size.
    static let deckScale: CGFloat = 0.84
    /// Offset from each card to the one behind it, as a fraction of the card's full size (right and down).
    static let deckStepX: CGFloat = 0.07
    static let deckStepY: CGFloat = 0.06
    /// Cards turn their left edge away a little, like a fanned deck seen from the right.
    static let deckYaw: CGFloat = -.pi / 36
    /// Cards beyond this many are not drawn in the deck.
    static let maximumDeckSize = 7

    /// Phase boundaries, as fractions of the duration.
    static let deckShownTime: CGFloat = 0.3
    static let tuckedTime: CGFloat = 0.68
    /// How far the leaving card dips below the deck on its way to the back, as a fraction of its full height.
    static let tuckDrop: CGFloat = 0.35
    static let tuckSamples = 18

    /// The leaving card passes behind the other cards at the lowest point of its dip.
    static var orderSwapTime: CGFloat {
        (deckShownTime + tuckedTime) / 2
    }

    static var timing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
    }

    /// Cards with a 3D transform are depth-sorted against their siblings, so turned cards could vanish behind the
    /// overlay's flat wallpaper layer or cut through each other. Deck positions sit far apart and above it.
    static func zPosition(depth: Int) -> CGFloat {
        20000 - CGFloat(depth) * 2000
    }

    static let tuckZPosition: CGFloat = 30000

    func opacity(depth: Int) -> Float {
        depth >= min(deckSize, Self.maximumDeckSize) ? 0 : 1
    }

    /// Pose of a card at a (fractional) deck `slot` of a deck with `count` cards; `dip` (0...1) lowers it below
    /// the deck. The card pivots on its bottom centre, which sits at the bottom centre of its full-size frame.
    static func deckPose(slot: CGFloat, count: Int, dip: CGFloat = 0, size: CGSize) -> CATransform3D {
        let count = CGFloat(min(max(count, 1), maximumDeckSize))
        let centred = slot - (count - 1) / 2
        let offsetX = size.width * deckStepX * centred
        let offsetY = -size.height * deckStepY * centred - size.height * tuckDrop * dip
        var transform = CATransform3DIdentity
        transform.m34 = -1 / perspective
        transform = CATransform3DTranslate(
            transform, offsetX, size.height * (1 - deckScale) / 2 + offsetY, 0
        )
        transform = CATransform3DRotate(transform, deckYaw, 0, 1, 0)
        return CATransform3DScale(transform, deckScale, deckScale, 1)
    }

    /// Ease-in-out progress for `time` (0...1).
    static func easedProgress(_ time: CGFloat) -> CGFloat {
        (1 - cos(.pi * time)) / 2
    }

    /// Undoes a previous stack effect, so the layer can be placed by frame again.
    static func resetPose(of layer: CALayer) {
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        layer.zPosition = 0
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    /// Transform keyframes (values and times) for the whole page turn.
    func keyframes(size: CGSize) -> (values: [CATransform3D], times: [CGFloat]) {
        let full = CATransform3DIdentity
        let from = Self.deckPose(slot: CGFloat(fromDepth), count: deckSize, size: size)
        let to = Self.deckPose(slot: CGFloat(toDepth), count: deckSize, size: size)
        guard tucksUnder else {
            return ([full, from, to, full], [0, Self.deckShownTime, Self.tuckedTime, 1])
        }
        var values = [full]
        var times: [CGFloat] = [0]
        for index in 0 ... Self.tuckSamples {
            let local = CGFloat(index) / CGFloat(Self.tuckSamples)
            let progress = Self.easedProgress(local)
            let slot = CGFloat(fromDepth) + (CGFloat(toDepth) - CGFloat(fromDepth)) * progress
            values.append(Self.deckPose(slot: slot, count: deckSize, dip: sin(.pi * progress), size: size))
            times.append(Self.deckShownTime + (Self.tuckedTime - Self.deckShownTime) * local)
        }
        values.append(full)
        times.append(1)
        return (values, times)
    }

    /// Plays the effect on `layer`, which is already placed at the card's full-size frame.
    func animate(_ layer: CALayer, duration: CFTimeInterval) {
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.position = CGPoint(x: frame.midX, y: frame.minY)
        let endZ = Self.zPosition(depth: toDepth)
        let visible = opacity(depth: toDepth)
        layer.transform = CATransform3DIdentity
        layer.zPosition = endZ
        layer.opacity = visible

        let (values, times) = keyframes(size: frame.size)
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = values.map { NSValue(caTransform3D: $0) }
        transform.keyTimes = times.map { NSNumber(value: Double($0)) }
        let segments = values.count - 1
        transform.timingFunctions = (0 ..< segments).map { index in
            // The tuck samples are already eased; the zoom out and zoom in segments ease themselves.
            index == 0 || index == segments - 1 || !tucksUnder
                ? Self.timing
                : CAMediaTimingFunction(name: .linear)
        }

        let zPosition = CAKeyframeAnimation(keyPath: "zPosition")
        zPosition.calculationMode = .discrete
        zPosition.values = [tucksUnder ? Self.tuckZPosition : Self.zPosition(depth: fromDepth), endZ]
        // Discrete keyframes take one more key time than values.
        zPosition.keyTimes = [0, NSNumber(value: Double(Self.orderSwapTime)), 1]

        let group = CAAnimationGroup()
        group.animations = [transform, zPosition]
        group.duration = duration
        layer.add(group, forKey: "stack")
    }
}
