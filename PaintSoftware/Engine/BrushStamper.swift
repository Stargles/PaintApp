import UIKit
import CoreGraphics

/// The single source of truth for turning brush + input samples into stamps on a
/// `RasterLayerTexture`. Both live raster drawing (`StrokeCanvasView`) and vector re-rendering
/// (`VectorCanvas.render`) go through here, so a vector stroke rasterizes identically to how it
/// would have been drawn live — same shape/hardness/dynamics/grain/scatter/spacing.
enum BrushStamper {
    struct Sample {
        var point: CGPoint
        var pressure: CGFloat
    }

    /// Per-dab pseudo-randomness for scatter and rotation jitter, seeded explicitly so a stroke can
    /// be *replayed* to the same pixels rather than merely to the same statistics.
    ///
    /// This exists because `CGFloat.random` cannot live in this pipeline. `VectorCanvas
    /// .renderLocalContent` re-runs `stampStroke` over every stored stroke on every invalidation, so
    /// with a global RNG a brush carrying `scatter > 0` or `rotationJitter > 0` landed its dabs in new
    /// positions each time the layer was re-rendered: draw a second stroke and the first one visibly
    /// jumps. That directly contradicts what a vector layer promises (see `VectorStroke` — geometry
    /// re-rasterized losslessly on demand), and it would apply to an eraser stroke just the same, its
    /// punched hole crawling on every render.
    ///
    /// splitmix64 — chosen because it is a handful of integer ops with no allocation and no shared
    /// state, so seeding one per stroke costs nothing on a path that runs thousands of times per
    /// stroke. Statistical quality far exceeds what jittering a brush dab needs.
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
    /// The dab lattice this walk lays down is anchored at `samples[0]`: dabs land every `spacing`
    /// along the path, with the leftover carried across segments. Hand it a *sub-run* of a stroke —
    /// which is what cutting a stroke and re-stamping the surviving piece does — and the anchor moves
    /// to the cut, so the piece's ink lands somewhere new along its **whole length**, most visibly at
    /// the far tip. That is the measurement that unwired Mode 1's geometric split (see
    /// `VectorEraser`'s Mode 1 notes and VECTOR_ERASER_PLAN.md §1).
    ///
    /// `visibleRange` is the fix, and it is deliberately a *filter over the original walk* rather than
    /// a re-derivation of it: the caller passes the **whole** stroke's samples, this walks all of them
    /// exactly as before — same spacing arithmetic, same carry, same floating-point — and simply routes
    /// the dabs outside the range to a sink that draws nothing. The dabs that do land are therefore not
    /// approximately where the uncut stroke put them, they are bit-for-bit the same call with the same
    /// arguments. Nothing else reproduces the lattice that exactly, which matters because §8's
    /// acceptance criterion is asserted at *zero* tolerance.
    ///
    /// The range is in `StrokeGeometry`'s "sample index + fraction" domain, and a dab exactly on a
    /// boundary is drawn — so two pieces cut at `low`/`high` render, between them, every dab of the
    /// original except those strictly inside `(low, high)`.
    ///
    /// The skipped dabs still go through `stampDab`, so they consume the RNG exactly as they would
    /// have. Without that a piece of a scattering stroke would re-roll every dab after the first
    /// skipped one — the same class of bug in a different place.
    static func stampStroke(into raster: DabTarget, samples: [Sample], brush: Brush,
                            color: UIColor, brushSize: CGFloat, brushOpacity: Double, isEraser: Bool = false,
                            seed: UInt64? = nil, visibleRange: ClosedRange<CGFloat>? = nil) {
        guard !samples.isEmpty else { return }
        raster.beginStroke()
        let spacing = stampSpacing(brushSize: brushSize, brush: brush)
        var rng = seed.map { DabRNG(seed: $0) } ?? DabRNG()
        var last: CGPoint?
        var lastPressure: CGFloat = samples[0].pressure
        // The parameter of the *carry point* — which is a dab position, not a sample, whenever the
        // previous segment placed one. Tracked alongside `last` so a dab's parameter is exact rather
        // than inferred from its position: within a segment, position is affine in parameter, so the
        // same `t` that ramps pressure maps the parameter too.
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

    /// Stamps one dab, honoring the brush's shape/hardness/pressure dynamics/scatter/grain. Ported
    /// verbatim from `StrokeCanvasView.stampOne` so live and replayed strokes match exactly.
    ///
    /// The eraser reuses this exact pipeline rather than a special-cased hard circle: it "paints"
    /// with the same shape/dynamics/spacing/grain as any other brush, just composited with
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
        case .softRound, .hardRound, .pen:
            raster.stampCircle(at: stampPoint, radius: radius, color: color, alpha: alpha, hardness: hardness, blendMode: blendMode)
        case .pencil:
            let grainMultiplier = brush.grain.isEnabled ? grainAlphaMultiplier(at: stampPoint, grain: brush.grain) : 1
            raster.stampCircle(at: stampPoint, radius: radius, color: color, alpha: alpha * grainMultiplier, hardness: hardness, blendMode: blendMode)
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

    static func grainAlphaMultiplier(at point: CGPoint, grain: BrushGrain) -> CGFloat {
        let noise = BrushGrain.noiseValue(atX: Double(point.x), y: Double(point.y), scale: grain.scale, rotation: grain.rotation)
        let depth = CGFloat(max(0, min(grain.depth, 1)))
        return (1 - depth) + depth * CGFloat(noise)
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
