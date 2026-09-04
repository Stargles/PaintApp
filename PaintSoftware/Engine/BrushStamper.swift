import UIKit
import CoreGraphics

/// The single source of truth for turning brush + input samples into stamps on a
/// `RasterLayerTexture`. Both live raster drawing (`StrokeCanvasView`) and vector re-rendering
/// (`VectorCanvas.render`) go through here, so a vector stroke rasterizes identically to how it
/// would have been drawn live — same shape/hardness/dynamics/scatter/spacing.
enum BrushStamper {
    struct Sample {
        var point: CGPoint
        var pressure: CGFloat
    }

    /// Per-dab pseudo-randomness for scatter and rotation jitter, seeded explicitly so a stroke can
    /// be *replayed* to the same pixels rather than merely to the same statistics.
    ///
    /// A global RNG would make a brush with `scatter > 0`/`rotationJitter > 0` re-roll its dabs on
    /// every re-render (`VectorCanvas.renderLocalContent` re-runs `stampStroke` over every stored
    /// stroke on each invalidation), visibly jumping an already-drawn stroke — including an eraser's
    /// punched hole. That breaks the promise that vector geometry re-rasterizes losslessly.
    ///
    /// splitmix64: a handful of integer ops, no allocation, no shared state — cheap enough to seed
    /// once per stroke on a path that runs thousands of times per stroke, and far more statistical
    /// quality than jittering a brush dab needs.
    struct DabRNG {
        private var state: UInt64

        /// Deterministic: the same seed always replays the same dab sequence.
        init(seed: UInt64) { state = seed }

        /// Non-deterministic, for live raster drawing — where dabs are baked into the bitmap as they
        /// land and are never replayed, so there is nothing to keep stable.
        init() { state = UInt64.random(in: .min ... .max) }

        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// Uniform in `0..<1`. Takes the top 53 bits, the standard way to land a `Double` mantissa
        /// exactly without the modulo bias of `next() % n`.
        mutating func unit() -> CGFloat { CGFloat(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }

        /// Uniform in `-1..<1`.
        mutating func signedUnit() -> CGFloat { unit() * 2 - 1 }
    }

    /// Stable 64-bit seed for a stroke's dab sequence, derived from its own identity so it survives
    /// save/load (a `Hasher` is per-process seeded and would not) and so two strokes never share a
    /// scatter pattern.
    static func seed(for id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { raw in
            var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a 64
            for byte in raw {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
            return hash
        }
    }

    /// Distance between consecutive stamps along a path. The 1pt floor keeps thin or tight-spacing
    /// brushes continuous even at `spacingFraction` ~= 0.
    static func stampSpacing(brushSize: CGFloat, brush: Brush) -> CGFloat {
        max(brushSize * CGFloat(brush.spacingFraction), 1)
    }

    /// How far the pen must travel before another input sample is worth *storing* as geometry —
    /// `StrokeSampleGate.minimumTravel`. Lives here, beside the dab spacing, because it is derived
    /// from it rather than tuned against it.
    ///
    /// **Half a dab.** The recorded path is what `advance` walks, so a sample dropped from it moves
    /// the walk by at most this much; at half a spacing no dab can shift by as much as the gap it
    /// already leaves to its neighbour, and the ink chain keeps its order and its position to within
    /// less than the engine's own resolution.
    ///
    /// Measured across five stroke shapes × three brush sizes × three speeds, jitter 0.4pt, comparing
    /// dab centre-lines before and after: at half a spacing every stroke at 400pt/s is **bit-identical**
    /// (the pen already outruns the gate) and the worst deviation anywhere is 1.15pt — on a 20pt brush,
    /// i.e. under 6% of the stroke's own width, and dominated by hand tremor rather than by the gate.
    ///
    /// A **whole** spacing was measured too and rejected: it doubles the saving but chamfers a slow
    /// 90° corner by 0.7 × the gate, which on a 60pt brush is a 3.5pt cut across the corner. A
    /// one-sample lookahead to rescue the corner vertex was built and refuted — at a slow corner the
    /// vertex sits in the middle of the rejected run, not at its end, so holding only the most recent
    /// rejected sample misses exactly the point it was written to save (measured: identical 3.512pt
    /// deviation with and without it). Rescuing it properly means a streaming max-deviation
    /// simplifier, which is a different piece of work from a gate.
    ///
    /// A perpendicular-deviation rule (Douglas-Peucker and relatives) was rejected for a different
    /// reason: it collapses a straight run to its two endpoints, and interpolation deforms a stroke by
    /// warping its stored samples, so a 400pt line stored as two points bends as a straight line under
    /// a warp that should curve it. A radial gate can never leave samples further apart than the input
    /// already had them plus one threshold, so it only ever makes a slow stroke as coarse as a fast
    /// one already is today.
    static func recordSpacing(brushSize: CGFloat, brush: Brush) -> CGFloat {
        stampSpacing(brushSize: brushSize, brush: brush) / 2
    }

    /// Walks from `last` toward `point`, invoking `body` at each `spacing`-sized step along the way,
    /// and returns the position of the final stamp — the carry point the next walk continues from.
    /// When the two points are closer together than one spacing, nothing is stamped and `last` comes
    /// straight back, so the leftover distance accumulates into the next call instead of being
    /// stamped short (which is what keeps a slow drag from bunching dabs up at the start).
    ///
    /// This is the arithmetic both callers share, and all they share: `stampStroke` below replays a
    /// whole finished stroke in one call and holds the carry point in a local, while
    /// `StrokeCanvasView.stampPath` is called once per incoming touch sample and holds it in a
    /// property across calls. Returning the carry point rather than storing it is what lets one
    /// helper serve both.
    static func advance(from last: CGPoint, to point: CGPoint, spacing: CGFloat,
                        _ body: (CGPoint) -> Void) -> CGPoint {
        advance(from: last, to: point, spacing: spacing) { dab, _ in body(dab) }
    }

    /// As above, but each callback also receives the dab's normalised position `t ∈ (0, 1]` along the
    /// `last`→`point` segment, so a caller can interpolate per-sample attributes across the dabs it
    /// generates instead of applying one endpoint's value to all of them (see `stampStroke`, which
    /// uses it to ramp pressure).
    static func advance(from last: CGPoint, to point: CGPoint, spacing: CGFloat,
                        _ body: (CGPoint, CGFloat) -> Void) -> CGPoint {
        let dx = point.x - last.x, dy = point.y - last.y
        let distance = hypot(dx, dy)
        guard spacing > 0, distance >= spacing else { return last }
        let steps = Int(distance / spacing)
        for i in 1...steps {
            let t = (CGFloat(i) * spacing) / distance
            body(CGPoint(x: last.x + dx * t, y: last.y + dy * t), t)
        }
        let coveredT = (CGFloat(steps) * spacing) / distance
        return CGPoint(x: last.x + dx * coveredT, y: last.y + dy * coveredT)
    }

    /// Replays a whole stroke (spacing-interpolated between samples, exactly like
    /// `StrokeCanvasView.stampPath`) into `raster`, as one `beginStroke`/`endStroke` unit.
    ///
    /// Pass `seed` (from `seed(for:)`, i.e. the stroke's own id) whenever the stroke can be replayed —
    /// which for stored vector geometry is every render. Without it, scatter and rotation jitter are
    /// re-rolled per render and the stroke's pixels change under the user; see `DabRNG`.
    ///
    /// ## `visibleRange` — showing a sub-run without re-phasing it
    ///
    /// The dab lattice is anchored at `samples[0]`: dabs land every `spacing` along the path, leftover
    /// carried across segments. Naively re-stamping just a cut stroke's surviving sub-run would move
    /// the anchor to the cut, shifting the piece's ink along its whole length (most visibly at the far
    /// tip) instead of leaving Mode 1's geometric split where it was.
    ///
    /// `visibleRange` fixes this as a *filter over the original walk*, not a re-derivation: the caller
    /// passes the **whole** stroke's samples, this walks all of them exactly as before — same spacing
    /// arithmetic, same carry, same floating-point — and routes dabs outside the range to a sink that
    /// draws nothing. The dabs that land are bit-for-bit what the uncut stroke produced, which matters
    /// because the acceptance test for this is asserted at *zero* tolerance.
    ///
    /// The range is in `StrokeGeometry`'s "sample index + fraction" domain; a dab exactly on a
    /// boundary is drawn, so two pieces cut at `low`/`high` render, between them, every dab of the
    /// original except those strictly inside `(low, high)`.
    ///
    /// Skipped dabs still go through `stampDab` so they consume the RNG exactly as they would have —
    /// otherwise a piece of a scattering stroke would re-roll every dab after the first skipped one.
    static func stampStroke(into raster: DabTarget, samples: [Sample], brush: Brush,
                            color: UIColor, brushSize: CGFloat, brushOpacity: Double, isEraser: Bool = false,
                            seed: UInt64? = nil, visibleRange: ClosedRange<CGFloat>? = nil) {
        guard !samples.isEmpty else { return }
        raster.beginStroke()
        let spacing = stampSpacing(brushSize: brushSize, brush: brush)
        var rng = seed.map { DabRNG(seed: $0) } ?? DabRNG()
        var last: CGPoint?
        var lastPressure: CGFloat = samples[0].pressure
        // The carry point's parameter — a dab position, not a sample, whenever the previous segment
        // placed one. Tracked alongside `last` so a dab's parameter is exact: within a segment,
        // position is affine in parameter, so the same `t` that ramps pressure maps the parameter too.
        var lastParameter: CGFloat = 0

        func sink(at parameter: CGFloat) -> DabTarget {
            guard let visibleRange else { return raster }
            return visibleRange.contains(parameter) ? raster : DiscardedDabTarget.shared
        }

        for (index, sample) in samples.enumerated() {
            let point = sample.point
            guard let lastPoint = last else {
                stampDab(into: sink(at: 0), at: point, pressure: sample.pressure, brush: brush, color: color,
                         brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser, rng: &rng)
                last = point
                lastPressure = sample.pressure
                lastParameter = 0
                continue
            }
            // Pressure ramps across the dabs bridging two input samples rather than every one of them
            // taking the destination sample's value. At the sampling rates a fast drag produces, one
            // segment can span many dabs, and holding pressure flat across them turned a smooth press
            // into a visible staircase in both width and opacity.
            let p0 = lastPressure, p1 = sample.pressure
            let q0 = lastParameter, q1 = CGFloat(index)
            var finalT: CGFloat?
            last = advance(from: lastPoint, to: point, spacing: spacing) { dab, t in
                finalT = t
                let parameter = q0 + (q1 - q0) * t
                stampDab(into: sink(at: parameter), at: dab, pressure: p0 + (p1 - p0) * t, brush: brush,
                         color: color, brushSize: brushSize, brushOpacity: brushOpacity,
                         isEraser: isEraser, rng: &rng)
            }
            // `advance` returns the last dab's position, or `lastPoint` unchanged when the segment was
            // too short to place one — in which case the carry point, and so its parameter, is unmoved.
            if let finalT { lastParameter = q0 + (q1 - q0) * finalT }
            lastPressure = sample.pressure
        }
        raster.endStroke()
    }

    /// Stamps one dab, honoring the brush's shape/hardness/pressure dynamics/scatter. Ported
    /// verbatim from `StrokeCanvasView.stampOne` so live and replayed strokes match exactly.
    ///
    /// The eraser reuses this exact pipeline rather than a special-cased hard circle: it "paints"
    /// with the same shape/dynamics/spacing as any other brush, just composited with
    /// `.destinationOut` instead of the brush's own blend mode — i.e. painting with 0 opacity as the
    /// color, so its stamp punches a hole instead of adding color. `color` is irrelevant under
    /// `.destinationOut` (only the stamp's alpha coverage matters), so it's ignored for an eraser dab.
    /// Live-drawing entry point: dabs land in the bitmap as they are made and are never replayed, so
    /// an unseeded `DabRNG` is the right choice. Replayable callers must use the `rng:` overload.
    static func stampDab(into raster: DabTarget, at point: CGPoint, pressure: CGFloat,
                         brush: Brush, color: UIColor, brushSize: CGFloat, brushOpacity: Double, isEraser: Bool) {
        var rng = DabRNG()
        stampDab(into: raster, at: point, pressure: pressure, brush: brush, color: color,
                 brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser, rng: &rng)
    }

    static func stampDab(into raster: DabTarget, at point: CGPoint, pressure: CGFloat,
                         brush: Brush, color: UIColor, brushSize: CGFloat, brushOpacity: Double, isEraser: Bool,
                         rng: inout DabRNG) {
        let pressureValue = Double(max(0, min(pressure, 1)))
        let sizeFraction = brush.dynamics.sizeFraction(forPressure: pressureValue)
        let opacityFraction = brush.dynamics.opacityFraction(forPressure: pressureValue)
        let diameter = max(brushSize * CGFloat(sizeFraction), 0.5)
        let radius = diameter / 2
        let alpha = CGFloat(brushOpacity) * CGFloat(brush.flow) * CGFloat(opacityFraction)
        guard alpha > 0, radius > 0 else { return }

        let stampPoint = applyScatter(to: point, radius: radius, scatter: brush.scatter, rng: &rng)
        let hardness = CGFloat(brush.hardness)
        let blendMode = isEraser ? CGBlendMode.destinationOut : brush.blendMode.cgBlendMode

        switch brush.shape {
        case .softRound, .hardRound, .pen, .pencil:
            raster.stampCircle(at: stampPoint, radius: radius, color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
        case .square, .custom:
            let rotation: CGFloat = brush.rotationJitter > 0
                ? rng.signedUnit() * .pi * CGFloat(brush.rotationJitter)
                : 0
            stampApproximateSquare(into: raster, at: stampPoint, diameter: diameter, rotation: rotation,
                                   color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
        }
    }

    static func applyScatter(to point: CGPoint, radius: CGFloat, scatter: Double, rng: inout DabRNG) -> CGPoint {
        guard scatter > 0 else { return point }
        let maxOffset = radius * 2 * CGFloat(scatter)
        let angle = rng.unit() * 2 * .pi
        let distance = rng.unit() * maxOffset
        return CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance)
    }

    static func stampApproximateSquare(into raster: DabTarget, at center: CGPoint, diameter: CGFloat,
                                       rotation: CGFloat, color: UIColor, alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        guard diameter > 0 else { return }
        let half = diameter / 2
        let dabDiameter = max(diameter * 0.42, 1)
        let dabRadius = dabDiameter / 2
        let step = max(dabDiameter * 0.65, 1)
        let cosR = cos(rotation), sinR = sin(rotation)
        var y = -half
        while y <= half {
            var x = -half
            while x <= half {
                let rx = x * cosR - y * sinR
                let ry = x * sinR + y * cosR
                raster.stampCircle(at: CGPoint(x: center.x + rx, y: center.y + ry), radius: dabRadius, color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
                x += step
            }
            y += step
        }
    }
}

// MARK: - KEYFRAMES.md §4.2 — the rest-space dab bake

extension BrushStamper {

    /// **One dab, in the space its stroke was drawn in.** KEYFRAMES.md §4.2's *"dab record"*.
    ///
    /// It carries the dab's **radius**, not its diameter, and its **centre**, not its position along
    /// the path — those are the only two things a pose has to touch.
    struct BakedDab: Equatable {
        var center: CGPoint
        var radius: CGFloat
        var color: UIColor
        var alpha: CGFloat
        var hardness: CGFloat
        var blendMode: CGBlendMode
    }

    /// **The pose a baked dab is replayed through — a point map, not a `CGAffineTransform`.**
    /// KEYFRAMES.md §4.2: *"One evaluator over `Homography.map` + `localScale(at:)` serves Uniform,
    /// Freeform and Distort. Three separate arms do not."*
    ///
    /// **`constantScale` is not an optimisation, it is the affine case being a different fact.** An
    /// affine's Jacobian determinant does not vary with position, so `sqrt(|det|)` *is* the local
    /// area root at every dab — LASSO_MOVE.md §5.17's rule, and the number
    /// `VectorCanvas.mapping(_:throughStretch:)` already writes into `VectorStroke.size`. Computing
    /// it once means a Uniform or Freeform pose lands the identical width the shipped path lands,
    /// bit for bit, rather than merely to within a `linearised` round trip. It is a homography whose
    /// `|det J|` varies across the stroke that has no scalar answer, and that is the only case that
    /// pays per dab.
    struct DabPose: Equatable {
        let map: Homography
        /// Nil exactly when the map is projective and the scale has to be asked per dab.
        let constantScale: CGFloat?

        init(_ map: Homography) {
            self.map = map
            // `affine(tolerance: 0)` is a decision, not a threshold — see its own doc comment. A
            // homography built from a `CGAffineTransform` has `g == h == 0` exactly.
            constantScale = map.affine().map { sqrt(abs($0.a * $0.d - $0.b * $0.c)) }
        }

        init(_ transform: CGAffineTransform) { self.init(Homography(transform)) }

        static let identity = DabPose(Homography.identity)

        var isIdentity: Bool { map == .identity }

        /// How much this pose magnifies area at `point`, as a linear scale. Nil on the vanishing
        /// line, where the dab has no image at all.
        func scale(at point: CGPoint) -> CGFloat? { constantScale ?? map.localScale(at: point) }

        /// One rest-space dab where this pose puts it. Nil where the pose has no image for it.
        func applied(to dab: BakedDab) -> BakedDab? {
            guard let center = map.map(dab.center), let k = scale(at: dab.center) else { return nil }
            var moved = dab
            moved.center = center
            moved.radius = dab.radius * k
            return moved
        }
    }

    /// **A `DabTarget` that collects instead of drawing** — KEYFRAMES.md §4.2 names it as
    /// *"structurally identical to the existing `DiscardedDabTarget`"*, and it is: the dab is
    /// computed by exactly the arithmetic that would have drawn it, and then kept instead of
    /// rasterized. Running `stampStroke` into one *is* the bake.
    ///
    /// Not shared and not thread-safe, unlike `DiscardedDabTarget` — it has state, so each bake owns
    /// one.
    final class CollectingDabTarget: DabTarget {
        private(set) var dabs: [BakedDab] = []
        init() {}
        func beginStroke() {}
        func endStroke() {}
        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            dabs.append(BakedDab(center: point, radius: radius, color: color,
                                 alpha: alpha, hardness: hardness, blendMode: blendMode))
        }
    }

    /// **A `DabTarget` that maps every dab through a pose on the way out** — the streaming form of
    /// bake-then-replay, and what the render path uses.
    ///
    /// Wrapping the sink rather than the walk is the whole trick, and it is what makes this stage
    /// small: `stampStroke`, `stampDab`, `applyScatter` and `stampApproximateSquare` all run
    /// **unchanged, in rest space**, so the dab count, the dab phase, the seeded `DabRNG` draws, and
    /// the square brush's sub-lattice are invariant across every frame of an animation *by
    /// construction* rather than by arithmetic that happens to agree. Only the two numbers a pose can
    /// legitimately change — where the dab is and
    /// how big it is — are touched, and they are touched last.
    ///
    /// `beginStroke`/`endStroke` forward, because the wrapped target may be a `RasterLayerTexture`
    /// keeping a stroke count.
    final class PosedDabTarget: DabTarget {
        private let inner: DabTarget
        private let pose: DabPose

        init(_ inner: DabTarget, pose: DabPose) {
            self.inner = inner
            self.pose = pose
        }

        func beginStroke() { inner.beginStroke() }
        func endStroke() { inner.endStroke() }

        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            guard let center = pose.map.map(point), let k = pose.scale(at: point) else { return }
            inner.stampCircle(at: center, radius: radius * k, color: color,
                              alpha: alpha, hardness: hardness, blendMode: blendMode)
        }
    }

    /// Walks a stroke in **rest space** and keeps its dabs instead of drawing them. Same arguments as
    /// `stampStroke`, because it is `stampStroke` — into a collector.
    static func bake(samples: [Sample], brush: Brush, color: UIColor, brushSize: CGFloat,
                     brushOpacity: Double, isEraser: Bool = false,
                     seed: UInt64? = nil, visibleRange: ClosedRange<CGFloat>? = nil) -> [BakedDab] {
        let collector = CollectingDabTarget()
        stampStroke(into: collector, samples: samples, brush: brush, color: color,
                    brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser,
                    seed: seed, visibleRange: visibleRange)
        return collector.dabs
    }

    /// Draws a baked walk through a pose. The replay entry point §4.2 asks for, and the same
    /// arithmetic `PosedDabTarget` applies — shared through `DabPose.applied(to:)` so a stored bake
    /// and a streamed one cannot drift.
    ///
    /// A dab the pose has no image for is dropped rather than clamped: it is behind the vanishing
    /// line, where there is no answer to draw.
    static func replay(_ dabs: [BakedDab], into target: DabTarget, through pose: DabPose) {
        target.beginStroke()
        for dab in dabs {
            guard let moved = pose.applied(to: dab) else { continue }
            target.stampCircle(at: moved.center, radius: moved.radius, color: moved.color,
                               alpha: moved.alpha, hardness: moved.hardness, blendMode: moved.blendMode)
        }
        target.endStroke()
    }
}

/// Where `stampStroke` sends the dabs outside a `visibleRange`.
///
/// The dab is still *computed* — same size, same alpha, same RNG draws — and then dropped, which is
/// the point: skipping the call instead would desynchronise the dab RNG for every dab after it, and
/// branching before the call would put the visibility test in the middle of the arithmetic that has
/// to stay bit-identical. Stateless, so one shared instance serves every caller on every thread.
final class DiscardedDabTarget: DabTarget {
    static let shared = DiscardedDabTarget()
    private init() {}
    func beginStroke() {}
    func endStroke() {}
    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                     alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {}
}
