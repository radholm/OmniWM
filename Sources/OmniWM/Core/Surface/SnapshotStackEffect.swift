// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import QuartzCore

/// Pages a window snapshot through a deck of cards. A page turn blends three overlapping motions, so the cards
/// never come to rest midway:
/// 1. Zoom out: every stacked window shrinks into a flat deck stepped towards the bottom right, the current
///    window at the front (top left), so the deck shows how many windows are stacked.
/// 2. Tuck: the current window dips below the deck and slides in at its back (bottom right) while every other
///    card moves up one place.
/// 3. Zoom in: the deck grows back to full size around the new front card, the next window.
/// Cards behind the front are dimmed by their depth. Depth 0 is the front of the deck; `deckSize` is the number
/// of cards.
struct SnapshotStackEffect: Equatable {
    let fromDepth: Int
    let toDepth: Int
    var deckSize = 2
    /// The card leaves the front by dipping below the deck and sliding in at its back.
    var tucksUnder = false

    /// Size of the cards while the deck is shown, as a fraction of their full size.
    static let deckScale: CGFloat = 0.94
    /// Offset from each card to the one behind it, as a fraction of the card's full size (right and down).
    static let deckStepX: CGFloat = 0.015
    static let deckStepY: CGFloat = 0.0125
    /// Cards beyond this many are not drawn in the deck.
    static let maximumDeckSize = 7
    /// Black overlay opacity added per depth behind the front card, up to `maximumDim`.
    static let dimPerDepth: CGFloat = 0.28
    static let maximumDim: CGFloat = 0.5
    static let dimLayerName = "stackDim"

    /// The zoom out ends and the zoom in starts at these fractions of the duration.
    static let deckShownTime: CGFloat = 0.4
    static let tuckedTime: CGFloat = 0.6
    /// The tuck overlaps both zooms, so motion stays continuous from start to end.
    static let slideStartTime: CGFloat = 0.16
    static let slideEndTime: CGFloat = 0.84
    /// How far the leaving card dips below the deck on its way to the back, as a fraction of its full height.
    static let tuckDrop: CGFloat = 0.35
    /// Keyframe samples for the whole page turn; dense enough to follow the curve at 120 Hz.
    static let samples = 96

    /// The leaving card passes behind the other cards at the lowest point of its dip.
    static var orderSwapTime: CGFloat {
        (slideStartTime + slideEndTime) / 2
    }

    /// Cards are depth-sorted against their siblings, so they could vanish behind the overlay's flat wallpaper
    /// layer. Deck positions sit far apart and above it.
    static func zPosition(depth: Int) -> CGFloat {
        20000 - CGFloat(depth) * 2000
    }

    static let tuckZPosition: CGFloat = 30000

    func opacity(depth: Int) -> Float {
        depth >= min(deckSize, Self.maximumDeckSize) ? 0 : 1
    }

    /// Pose of a card at a (fractional) deck `slot` of a deck with `count` cards; `dip` (0...1) lowers it below
    /// the deck. The card pivots on its bottom centre, which sits at the bottom centre of its full-size frame.
    /// `zoom` (0...1) blends from the card's full-size frame (0) to its place in the deck (1).
    static func deckPose(slot: CGFloat, count: Int, dip: CGFloat = 0, zoom: CGFloat = 1, size: CGSize)
        -> CATransform3D
    {
        let count = CGFloat(min(max(count, 1), maximumDeckSize))
        let centred = slot - (count - 1) / 2
        let offsetX = size.width * deckStepX * centred * zoom
        let offsetY = (-size.height * deckStepY * centred - size.height * tuckDrop * dip) * zoom
        let scale = 1 - (1 - deckScale) * zoom
        let transform = CATransform3DMakeTranslation(offsetX, size.height * (1 - scale) / 2 + offsetY, 0)
        return CATransform3DScale(transform, scale, scale, 1)
    }

    /// Dim of a card at deck `slot`, faded in and out with `zoom`.
    static func dim(slot: CGFloat, zoom: CGFloat) -> CGFloat {
        min(max(slot, 0) * dimPerDepth, maximumDim) * zoom
    }

    struct Pose {
        let transform: CATransform3D
        let zPosition: CGFloat
        let dim: CGFloat
    }

    struct Keyframes {
        var values: [CATransform3D] = []
        var dims: [CGFloat] = []
        var times: [CGFloat] = []
    }

    private struct Phase {
        let zoom: CGFloat
        let slot: CGFloat
        let dip: CGFloat
    }

    private func phase(at time: CGFloat) -> Phase {
        let time = min(max(time, 0), 1)
        let zoom = time < Self.deckShownTime ? Self.easedProgress(time / Self.deckShownTime)
            : time <= Self.tuckedTime ? 1
            : 1 - Self.easedProgress((time - Self.tuckedTime) / (1 - Self.tuckedTime))
        let slide = min(max((time - Self.slideStartTime) / (Self.slideEndTime - Self.slideStartTime), 0), 1)
        let progress = Self.easedProgress(slide)
        let slot = CGFloat(fromDepth) + (CGFloat(toDepth) - CGFloat(fromDepth)) * progress
        return Phase(zoom: zoom, slot: slot, dip: tucksUnder ? sin(.pi * progress) : 0)
    }

    /// Pose of the card at `time` (0...1) of the page turn, for scrubbing it interactively (e.g. by a swipe).
    func pose(at time: CGFloat, size: CGSize) -> Pose {
        let phase = phase(at: time)
        let transform = phase.zoom <= 0 ? CATransform3DIdentity
            : Self.deckPose(slot: phase.slot, count: deckSize, dip: phase.dip, zoom: phase.zoom, size: size)
        let zPosition = time >= Self.orderSwapTime ? Self.zPosition(depth: toDepth)
            : tucksUnder ? Self.tuckZPosition : Self.zPosition(depth: fromDepth)
        return Pose(transform: transform, zPosition: zPosition, dim: Self.dim(slot: phase.slot, zoom: phase.zoom))
    }

    /// Places `layer`, whose full-size frame is `frame`, at `time` of the page turn without animating.
    func apply(to layer: CALayer, frame: CGRect, at time: CGFloat) {
        layer.removeAnimation(forKey: "stack")
        layer.transform = CATransform3DIdentity
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.position = CGPoint(x: frame.midX, y: frame.minY)
        let pose = pose(at: time, size: frame.size)
        layer.transform = pose.transform
        layer.zPosition = pose.zPosition
        layer.opacity = opacity(depth: toDepth)
        let dim = Self.dimLayer(of: layer)
        dim.removeAnimation(forKey: "stack")
        dim.opacity = Float(pose.dim)
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
        layer.sublayers?.filter { $0.name == dimLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    static func dimLayer(of layer: CALayer) -> CALayer {
        let dim = layer.sublayers?.first { $0.name == dimLayerName } ?? {
            let dim = CALayer()
            dim.name = dimLayerName
            dim.backgroundColor = CGColor(gray: 0, alpha: 1)
            dim.opacity = 0
            layer.addSublayer(dim)
            return dim
        }()
        dim.frame = layer.bounds
        dim.zPosition = 1
        return dim
    }

    /// Transform and dim keyframes for the whole page turn.
    func keyframes(size: CGSize) -> Keyframes {
        var keyframes = Keyframes()
        for index in 0 ... Self.samples {
            let time = CGFloat(index) / CGFloat(Self.samples)
            let pose = pose(at: time, size: size)
            keyframes.values.append(pose.transform)
            keyframes.dims.append(pose.dim)
            keyframes.times.append(time)
        }
        return keyframes
    }

    /// Sublayers holding window content, i.e. all but the dim overlay.
    static func contentSublayers(of layer: CALayer) -> [CALayer] {
        layer.sublayers?.filter { $0.name != dimLayerName } ?? []
    }

    /// Plays the effect on `layer`, which is already placed at the card's full-size frame.
    func animate(_ layer: CALayer, duration: CFTimeInterval) {
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.position = CGPoint(x: frame.midX, y: frame.minY)
        let endZ = Self.zPosition(depth: toDepth)
        layer.transform = CATransform3DIdentity
        layer.zPosition = endZ
        layer.opacity = opacity(depth: toDepth)

        let keyframes = keyframes(size: frame.size)
        let (values, dims) = (keyframes.values, keyframes.dims)
        let keyTimes = keyframes.times.map { NSNumber(value: Double($0)) }
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = values.map { NSValue(caTransform3D: $0) }
        transform.keyTimes = keyTimes

        let zPosition = CAKeyframeAnimation(keyPath: "zPosition")
        zPosition.calculationMode = .discrete
        zPosition.values = [tucksUnder ? Self.tuckZPosition : Self.zPosition(depth: fromDepth), endZ]
        // Discrete keyframes take one more key time than values.
        zPosition.keyTimes = [0, NSNumber(value: Double(Self.orderSwapTime)), 1]

        let group = CAAnimationGroup()
        group.animations = [transform, zPosition]
        group.duration = duration
        layer.add(group, forKey: "stack")

        let dim = Self.dimLayer(of: layer)
        dim.opacity = Float(dims.last ?? 0)
        let dimAnimation = CAKeyframeAnimation(keyPath: "opacity")
        dimAnimation.values = dims.map { NSNumber(value: Double($0)) }
        dimAnimation.keyTimes = keyTimes
        dimAnimation.duration = duration
        dim.add(dimAnimation, forKey: "stack")
    }
}
