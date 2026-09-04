import CoreGraphics

/// **The curve a stored stroke is, and the only thing any tier walks.** BRUSH.md §2.3 and §3.4.
///
/// A stroke is stored as a list of on-curve points (`VectorSample`), and this is the interpolant
/// through them: a centripetal Catmull-Rom chain, evaluated as a cubic Hermite per segment. Live
/// raster drawing, vector replay, the rest-space dab bake and the eraser's cross-section all read
/// the same curve, so there is no second reconstruction to disagree with the first.
///
/// ## Why a curve rather than the chords
///
/// The stored points are placed by `StrokePathFit` at a fixed geometric tolerance, so they are far
/// enough apart that the direction from one to the next is a *step function* — it changes only at a
/// knot. §3.4 rules that the tangent at a dab comes from the curve, and it is the tangent that makes
/// this worth doing: a brush whose angle follows the stroke's direction (§2.8) built on a chord
/// difference would rotate in visible jumps. Positionally the curve buys nothing at this tolerance
/// and MEASURED costs a little — see `StrokePathFit.tolerance`.
///
/// Pure `CoreGraphics` — no UIKit, no `Brush` — so the geometry can be exercised headless.
struct StrokePath {

    /// The stored knots, in the order they were drawn.
    let points: [CGPoint]

    init(points: [CGPoint]) { self.points = points }

    init(_ samples: some SampleRun) { self.init(points: samples.map(\.point)) }

    var isEmpty: Bool { points.count < 2 }

    /// The end of the parametric domain — see the "sample index + fraction" convention
    /// `StrokeGeometry` documents, which this shares.
    var domainEnd: CGFloat { CGFloat(max(points.count - 1, 0)) }

    // MARK: - Creases

    /// How sharply the stored path may turn at a knot before the curve stops smoothing through it.
    ///
    /// **60°, and it is a fidelity decision rather than a taste one.** Catmull-Rom rounds a corner
    /// the artist drew sharp: MEASURED on a traced right angle at 12 pt knot spacing, the curve cuts
    /// **0.868 pt** across the corner, which on a 5 pt brush is a sixth of the line's own width.
    /// Giving a knot that turns more than this a one-sided tangent on each side restores the corner
    /// exactly and drops the worst deviation over six stroke shapes × three speeds from **0.868 pt to
    /// 0.470 pt**, the remainder being ordinary curvature rather than corners.
    ///
    /// Real curvature cannot reach 60° at a knot, which is what makes the threshold safe: the fit
    /// places knots `sqrt(8 · radius · tolerance)` apart on an arc, so a knot's turn is
    /// `sqrt(8 · tolerance / radius)` — 28° at a 10 pt radius, 44° at 4 pt, and only past a 2 pt
    /// radius does an honest curve turn this far. MEASURED: thresholds of 60°, 75° and 90° all give
    /// the same worst deviation, so the choice inside that band costs nothing and 60° is the one that
    /// catches a corner a fast pen only half-sampled.
    static let cornerCosine: CGFloat = 0.5

    /// How far a flattened sub-chord may fall from the curve it approximates, in canvas points.
    ///
    /// A fifth of `PackedSampleRun.quantum`, so the walk resolves the curve well below the grid the
    /// path is stored on. **Deliberately not derived from the brush**: the flattening decides where
    /// dabs land, and a flatness that moved with `spacing` would make a stroke re-render differently
    /// after a spacing edit — which is exactly what §12 stage 0 exists to make impossible.
    static let flatness: CGFloat = 0.05

    /// Whether the path creases at knot `index` rather than curving through it. Endpoints crease by
    /// definition: they have no far side to blend with.
    static func isCorner(at index: Int, count: Int, point: (Int) -> CGPoint) -> Bool {
        guard index > 0, index + 1 < count else { return true }
        let here = point(index)
        guard let before = distinctNeighbour(of: index, step: -1, count: count, point: point),
              let after = distinctNeighbour(of: index, step: 1, count: count, point: point)
        else { return true }
        let inX = here.x - before.x, inY = here.y - before.y
        let outX = after.x - here.x, outY = after.y - here.y
        let inLength = hypot(inX, inY), outLength = hypot(outX, outY)
        guard inLength > epsilon, outLength > epsilon else { return true }
        return (inX * outX + inY * outY) / (inLength * outLength) < cornerCosine
    }

    /// The nearest neighbour of `index` in direction `step` that is not on top of it. A stationary
    /// pen whose pressure is changing stores repeated positions (`StrokePathFit`'s pressure escape),
    /// and a zero-length difference has no direction.
    static func distinctNeighbour(of index: Int, step: Int, count: Int,
                                  point: (Int) -> CGPoint) -> CGPoint? {
        let here = point(index)
        var i = index + step
        while i >= 0 && i < count {
            let candidate = point(i)
            if hypot(candidate.x - here.x, candidate.y - here.y) > epsilon { return candidate }
            i += step
        }
        return nil
    }

    // MARK: - The segment

    /// The two Hermite tangents of the segment from knot `index` to knot `index + 1`, under
    /// **centripetal** Catmull-Rom — the parameterisation whose square-root knot spacing is what
    /// keeps a cusp or a self-intersection out of the curve when two knots crowd together, which
    /// uniform Catmull-Rom does not.
    ///
    /// A knot `isCorner` reports on takes a one-sided tangent, so the segment meets it along its own
    /// chord and the crease survives.
    static func tangents(segment index: Int, count: Int, point: (Int) -> CGPoint) -> (CGPoint, CGPoint) {
        let p1 = point(index), p2 = point(index + 1)
        let chord = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
        let startCreases = isCorner(at: index, count: count, point: point)
        let endCreases = isCorner(at: index + 1, count: count, point: point)
        if startCreases && endCreases { return (chord, chord) }

        let p0 = distinctNeighbour(of: index, step: -1, count: count, point: point) ?? p1
        let p3 = distinctNeighbour(of: index + 1, step: 1, count: count, point: point) ?? p2
        // Centripetal knot spacing: the square root of the chord length, floored so a repeated point
        // cannot divide by zero.
        func spacing(_ a: CGPoint, _ b: CGPoint) -> CGFloat { max(sqrt(hypot(b.x - a.x, b.y - a.y)), epsilon) }
        let t1 = spacing(p0, p1)
        let t2 = t1 + spacing(p1, p2)
        let t3 = t2 + spacing(p2, p3)
        func difference(_ a: CGPoint, _ b: CGPoint, over dt: CGFloat) -> CGPoint {
            CGPoint(x: (a.x - b.x) / dt, y: (a.y - b.y) / dt)
        }
        let d10 = difference(p1, p0, over: t1)
        let d20 = difference(p2, p0, over: t2)
        let d21 = difference(p2, p1, over: t2 - t1)
        let d31 = difference(p3, p1, over: t3 - t1)
        let d32 = difference(p3, p2, over: t3 - t2)
        let width = t2 - t1
        let m1 = startCreases ? chord
            : CGPoint(x: (d10.x - d20.x + d21.x) * width, y: (d10.y - d20.y + d21.y) * width)
        let m2 = endCreases ? chord
            : CGPoint(x: (d32.x - d31.x + d21.x) * width, y: (d32.y - d31.y + d21.y) * width)
        return (m1, m2)
    }

    /// The cubic Hermite at `u ∈ [0, 1]`. With `m1 == m2 == p2 - p1` this reduces to
    /// `p1 + u · (p2 - p1)` **exactly**, which is why a straight run walks bit-for-bit as it did
    /// when the walk was a straight line between samples.
    static func hermite(p1: CGPoint, p2: CGPoint, m1: CGPoint, m2: CGPoint, u: CGFloat) -> CGPoint {
        let u2 = u * u, u3 = u2 * u
        let h00 = 2 * u3 - 3 * u2 + 1
        let h10 = u3 - 2 * u2 + u
        let h01 = -2 * u3 + 3 * u2
        let h11 = u3 - u2
        return CGPoint(x: h00 * p1.x + h10 * m1.x + h01 * p2.x + h11 * m2.x,
                       y: h00 * p1.y + h10 * m1.y + h01 * p2.y + h11 * m2.y)
    }

    /// The Hermite's first derivative — the *unnormalised* tangent.
    static func hermiteDerivative(p1: CGPoint, p2: CGPoint, m1: CGPoint, m2: CGPoint,
                                  u: CGFloat) -> CGPoint {
        let u2 = u * u
        let h00 = 6 * u2 - 6 * u
        let h10 = 3 * u2 - 4 * u + 1
        let h01 = -6 * u2 + 6 * u
        let h11 = 3 * u2 - 2 * u
        return CGPoint(x: h00 * p1.x + h10 * m1.x + h01 * p2.x + h11 * m2.x,
                       y: h00 * p1.y + h10 * m1.y + h01 * p2.y + h11 * m2.y)
    }

    /// How many straight pieces this segment is walked in, from the standard uniform-subdivision
    /// bound `error ≤ max|P''| / (8 n²)`. The second derivative of a cubic is linear in `u`, so its
    /// maximum is at one end or the other and needs no search. A straight segment answers **1**,
    /// which is what keeps the common case as cheap as the walk it replaces.
    static func subdivisions(p1: CGPoint, p2: CGPoint, m1: CGPoint, m2: CGPoint) -> Int {
        let dx = p2.x - p1.x, dy = p2.y - p1.y
        let startX = 6 * dx - 4 * m1.x - 2 * m2.x, startY = 6 * dy - 4 * m1.y - 2 * m2.y
        let endX = -6 * dx + 2 * m1.x + 4 * m2.x, endY = -6 * dy + 2 * m1.y + 4 * m2.y
        let curvature = max(hypot(startX, startY), hypot(endX, endY))
        guard curvature > epsilon else { return 1 }
        let n = (curvature / (8 * flatness)).squareRoot().rounded(.up)
        return min(max(Int(n), 1), 64)
    }

    // MARK: - Reading the curve

    /// The point at `parameter` in the "knot index + fraction" domain, clamped to the run.
    func point(at parameter: CGFloat) -> CGPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        guard points.count > 1 else { return first }
        guard parameter > 0 else { return first }
        guard parameter < domainEnd else { return last }
        let index = Int(parameter.rounded(.down))
        let (m1, m2) = tangents(segment: index)
        return StrokePath.hermite(p1: points[index], p2: points[index + 1], m1: m1, m2: m2,
                                  u: parameter - CGFloat(index))
    }

    /// The **unit** tangent at `parameter`, from the curve. Falls back to the segment's chord where
    /// the derivative vanishes (two coincident knots have no direction of their own) and to `(1, 0)`
    /// for a run with no length at all, which is the same answer `StrokeGeometry` has always given a
    /// single dab: for a round stamp every cross-section direction is equivalent, so any fixed choice
    /// is exact rather than merely acceptable.
    func tangent(at parameter: CGFloat) -> CGPoint {
        guard points.count > 1 else { return CGPoint(x: 1, y: 0) }
        let clamped = min(max(parameter, 0), domainEnd)
        let index = min(Int(clamped.rounded(.down)), points.count - 2)
        let (m1, m2) = tangents(segment: index)
        let derivative = StrokePath.hermiteDerivative(p1: points[index], p2: points[index + 1],
                                                      m1: m1, m2: m2, u: clamped - CGFloat(index))
        if let unit = StrokePath.normalized(derivative) { return unit }
        // A vanishing derivative: fall back on the nearest knots that are not on top of each other.
        let before = StrokePath.distinctNeighbour(of: index, step: -1, count: points.count) { points[$0] }
        let after = StrokePath.distinctNeighbour(of: index, step: 1, count: points.count) { points[$0] }
        let from = before ?? points[index], to = after ?? points[index]
        return StrokePath.normalized(CGPoint(x: to.x - from.x, y: to.y - from.y)) ?? CGPoint(x: 1, y: 0)
    }

    func tangents(segment index: Int) -> (CGPoint, CGPoint) {
        StrokePath.tangents(segment: index, count: points.count) { points[$0] }
    }

    /// The arc length of segment `index`, walked at the same flatness the dab march uses — the whole
    /// segment by default, or as far as `u ∈ [0, 1]` through it.
    ///
    /// The partial case stops the flattening at `u` rather than re-subdividing to it, so a prefix of a
    /// segment is measured on exactly the polyline the whole segment is measured on and the two cannot
    /// disagree about where a point along the curve is.
    func length(ofSegment index: Int, upTo u: CGFloat = 1) -> CGFloat {
        let p1 = points[index], p2 = points[index + 1]
        let (m1, m2) = tangents(segment: index)
        let steps = StrokePath.subdivisions(p1: p1, p2: p2, m1: m1, m2: m2)
        let end = min(max(u, 0), 1)
        var total: CGFloat = 0
        var previous = p1
        for step in 1...steps {
            let stepU = min(CGFloat(step) / CGFloat(steps), end)
            let next = StrokePath.hermite(p1: p1, p2: p2, m1: m1, m2: m2, u: stepU)
            total += hypot(next.x - previous.x, next.y - previous.y)
            previous = next
            if stepU >= end { break }
        }
        return total
    }

    /// The arc length from the start of the path to `parameter`, in the "knot index + fraction"
    /// domain this shares with `StrokeGeometry`.
    ///
    /// **Not what the dab march counts, and it is not trying to be.** The march's own arc length is a
    /// running sum of `spacing`, exact by construction and identical in every tier; this is a
    /// *geometric* measurement of the same curve, and it exists for the one caller that has to place a
    /// piece in its parent's random field after the walk has already been re-anchored
    /// (`VectorCanvas.detachedArcOffset`). There the dabs have moved anyway, so what is wanted is a
    /// faithful distance rather than a bit-identical one.
    func arcLength(to parameter: CGFloat) -> CGFloat {
        guard points.count > 1 else { return 0 }
        let clamped = min(max(parameter, 0), domainEnd)
        let whole = min(Int(clamped.rounded(.down)), points.count - 2)
        var total: CGFloat = 0
        for index in 0..<whole { total += length(ofSegment: index) }
        return total + length(ofSegment: whole, upTo: clamped - CGFloat(whole))
    }

    // MARK: - The walk

    /// Marches segment `index` by arc length at `spacing`, calling `body` with each dab's position
    /// and its parameter `u ∈ (0, 1]` inside the segment.
    ///
    /// `carried` is how far the path has already travelled since the previous dab — the leftover a
    /// segment too short to place one hands to the next, which is what keeps a slow drag from
    /// bunching dabs up at the start. The return value is the new leftover.
    ///
    /// The march follows the **curve**, not the chord between two knots: at the knot spacing the fit
    /// leaves, walking the chord would visibly polygonise a stroke that used to be walked at input
    /// density. `u` is the curve parameter, which on a straight segment is exactly the fraction of
    /// the distance travelled, and on a curved one differs from it by well under a percent over a
    /// segment the fit's cap keeps to 12 pt.
    func advance(segment index: Int, spacing: CGFloat, carried: CGFloat,
                 _ body: (CGPoint, CGFloat) -> Void) -> CGFloat {
        guard spacing > 0, index >= 0, index + 1 < points.count else { return carried }
        let p1 = points[index], p2 = points[index + 1]
        let (m1, m2) = tangents(segment: index)
        let steps = StrokePath.subdivisions(p1: p1, p2: p2, m1: m1, m2: m2)
        var since = carried
        var from = p1
        for step in 1...steps {
            let uEnd = CGFloat(step) / CGFloat(steps)
            let to = StrokePath.hermite(p1: p1, p2: p2, m1: m1, m2: m2, u: uEnd)
            let dx = to.x - from.x, dy = to.y - from.y
            let length = hypot(dx, dy)
            guard length > 0 else { from = to; continue }
            var offset: CGFloat = 0
            while since + (length - offset) >= spacing {
                offset += spacing - since
                let fraction = offset / length
                let u = (CGFloat(step - 1) + fraction) / CGFloat(steps)
                body(CGPoint(x: from.x + dx * fraction, y: from.y + dy * fraction), u)
                since = 0
            }
            since += length - offset
            from = to
        }
        return since
    }

    private static func normalized(_ v: CGPoint) -> CGPoint? {
        let length = hypot(v.x, v.y)
        guard length > epsilon else { return nil }
        return CGPoint(x: v.x / length, y: v.y / length)
    }

    private static let epsilon: CGFloat = 1e-9
}

/// **Which of the touch samples arriving during a stroke become stored geometry.** BRUSH.md §3.3 and
/// §5.3, and the whole of §12 stage 0.
///
/// A sample is kept when dropping it would move the stored path further than `tolerance` from the
/// path the pen actually drew. Nothing here consults the brush, and that is the point: the previous
/// rule admitted a sample once it had travelled half the current dab spacing, so *the stored path's
/// density was a function of the brush it was drawn with*. Retune a wide-spaced brush to a tight
/// spacing — which is what a brush editor is for — and there was no longer enough path to walk, and
/// the samples were gone. §5.3 makes the fixed tolerance a correctness requirement rather than a
/// saving; the saving is real and is a side effect.
///
/// ## The rule, and it is one rule with three escapes
///
/// Streaming, because the live preview and the stored geometry are the same gesture: the run of
/// samples since the last stored knot is held, and a knot is committed the moment the chord from the
/// last knot to the newest sample stops representing them.
///
/// - **Deviation.** No sample between two stored knots may sit further than `tolerance` from the
///   straight line between them.
/// - **The cap.** No two stored knots may be further apart than `maximumKnotSpacing`.
/// - **Pressure.** A knot is committed when pressure has moved `minimumPressureChange` from the last
///   one, whether or not the pen has.
///
/// ## Why the cap is not optional
///
/// A pure deviation rule collapses a straight run to its two endpoints, and interpolation deforms a
/// stroke by *warping its stored samples*, so a 400 pt line stored as two points bends as a straight
/// line under a warp that should curve it. This is the objection that had a perpendicular-deviation
/// rule rejected when the sample gate was written, and the cap is the answer to it. MEASURED, a
/// finger-drawn 400 pt line at constant pressure: **2 points stored with no cap, 36 with a 12 pt
/// one**. The pressure escape hides this from a pencil — an ordinary pressure ramp commits a knot
/// every couple of points on its own — but a finger reports a flat pressure of 1, so without the cap
/// the defect is one gesture away.
///
/// Pure `CoreGraphics` — no UIKit, no `Brush` — so the rule can be exercised headless against
/// synthetic sample sequences.
struct StrokePathFit {

    /// How far the drawn path may fall from the stored one, in canvas points.
    ///
    /// **One `PackedSampleRun.quantum`.** Stored coordinates are quarter-pixel fixed point, so a fit
    /// tighter than the grid is fitting to a precision the document cannot hold; a fit looser than it
    /// makes the refit, rather than the storage, the thing that decides how true a line is. MEASURED
    /// over six stroke shapes × three speeds with hand tremor and the stabilizer at its default: the
    /// stored polyline stays within **0.250 pt** of the drawn path by construction and the curve
    /// through it within **0.351 pt**, while storing **3–7×** fewer points than the sample gate did
    /// for a 20 pt brush and **6–12×** fewer than for a 5 pt one.
    ///
    /// Whether this should scale with zoom is BRUSH.md §13's open question and is deliberately not
    /// answered here.
    static let tolerance: CGFloat = PackedSampleRun.quantum

    /// The furthest apart two stored knots may be, in canvas points.
    ///
    /// **12 pt, MEASURED against the warp rather than guessed.** Deforming a stroke by warping its
    /// stored knots and comparing the result against the same warp applied to every drawn sample, on
    /// six shapes at lattice cell sizes of 20, 50 and 100 pt: **≤ 0.08 pt at a 12 pt cap, 0.19 pt at
    /// 24, 0.50 pt at 48 and up to 1.14 pt uncapped.** 12 keeps the warp error an order of magnitude
    /// under `tolerance`, so the cap is never the term that limits how true a deformed stroke is; at
    /// 24 it becomes comparable to it and past 48 it dominates. It costs almost nothing to hold it
    /// here — MEASURED, 67 stored points against 63 on a slow traced line.
    ///
    /// A gap wider than this survives only when the input itself was: the fit drops samples, it never
    /// invents them, so two knots are `min(cap, one input step)` apart at worst.
    static let maximumKnotSpacing: CGFloat = 12

    /// How much pressure must differ from the last stored knot to commit another one.
    ///
    /// 0.02 of the 0...1 range moves a 20 pt brush's dab diameter by about a third of a point under a
    /// typical size-to-pressure curve — below the width the renderer can resolve, so a finer
    /// threshold stores points describing a difference that cannot be drawn.
    ///
    /// **This is not a nicety, and the mechanism is worth naming**, because it is not "the dab at
    /// that point gets thicker": `BrushStamper.stampStroke` emits *no* dabs while the path is not
    /// advancing, so a stationary swell draws nothing by itself. What it does is set the pressure the
    /// ramp starts from across the **next** segment. Drop it and the stroke resumes at the pressure
    /// the pen had before the pause and ramps up over the first segment — a press-then-move starts
    /// thin and fattens instead of starting fat. MEASURED on a synthetic hold: without the escape a
    /// 0.2 → 0.9 swell carries 0.200 into the resumed drag instead of 0.886.
    ///
    /// `StrokeGeometry.capsuleChain` reads the same per-knot pressure for the eraser's footprint, so
    /// the escape keeps erase width honest for the same reason.
    static let minimumPressureChange: CGFloat = 0.02

    var tolerance: CGFloat
    var maximumKnotSpacing: CGFloat
    var minimumPressureChange: CGFloat

    /// The last knot committed — what every threshold is measured from.
    private var anchor: VectorSample?
    /// Samples offered since `anchor` and not yet committed. The invariant this type maintains is
    /// that the chord from `anchor` to `pending.last` represents all of them within `tolerance`,
    /// which is what makes committing `pending.last` on a break correct rather than approximate.
    private var pending: [VectorSample] = []

    init(tolerance: CGFloat = StrokePathFit.tolerance,
         maximumKnotSpacing: CGFloat = StrokePathFit.maximumKnotSpacing,
         minimumPressureChange: CGFloat = StrokePathFit.minimumPressureChange) {
        self.tolerance = tolerance
        self.maximumKnotSpacing = maximumKnotSpacing
        self.minimumPressureChange = minimumPressureChange
    }

    /// Starts a new stroke. The next sample offered is kept whatever it is.
    mutating func reset() { anchor = nil; pending = [] }

    /// Offers one sample and answers with the knots — none, or one — that became stored geometry.
    ///
    /// **The knot returned is behind the sample offered**, by design: a knot is committed only once
    /// the sample after it proves it was needed, so the fit is one sample of lag. The live preview
    /// does not wait on it (see `StrokeCanvasView.recordVectorSample`), so the lag is invisible.
    /// **The knot a break commits absorbs the intervals of the samples the fit is dropping**, which
    /// is `SampleChannel.isCumulative` (`VectorSample.absorbing`). Δt is "seconds since the previous
    /// *stored* point", not since the previous *offered* one; without this a refitted stroke's stored
    /// Δt would be the digitiser's period whatever the hand was doing, and BRUSH.md §2.8's velocity
    /// would read every stroke at 240 Hz. It is generic over the channel set, so the next interval
    /// channel needs no edit here.
    mutating func offer(_ sample: VectorSample) -> [VectorSample] {
        guard let anchor else {
            self.anchor = sample
            return [sample]
        }
        guard breaks(from: anchor, to: sample) else {
            pending.append(sample)
            return []
        }
        guard let trailing = pending.last else {
            self.anchor = sample
            pending = []
            return [sample]
        }
        let knot = trailing.absorbing(pending.dropLast())
        self.anchor = knot
        pending = [sample]
        return [knot]
    }

    /// Ends the stroke, and answers with the knots that close it.
    ///
    /// `sample` is the lift point, or nil for a stroke that was interrupted rather than lifted. **The
    /// lift point is stored unconditionally**, and that is not an edge case: artists decelerate into
    /// the end of nearly every stroke, so its last samples each fail the deviation test on their own
    /// and a fit without this ends the line short of where the pen stopped. It is also the one sample
    /// that cannot be recovered by interpolating between its survivors, because it has no successor.
    ///
    /// With no lift point the run still has to be flushed, or an interrupted stroke ends up to a
    /// whole `maximumKnotSpacing` short of the last position that arrived.
    mutating func finish(_ sample: VectorSample?) -> [VectorSample] {
        defer { pending = [] }
        guard let sample else {
            guard let trailing = pending.last else { return [] }
            let knot = trailing.absorbing(pending.dropLast())
            anchor = knot
            return [knot]
        }
        guard let anchor else {
            self.anchor = sample
            return [sample]
        }
        var committed: [VectorSample] = []
        // A tail the lift point does not represent is committed first, or the deceleration into the
        // end of the stroke is chamfered off between the last knot and the lift.
        //
        // The two identity tests are on **geometry** rather than on `==`. A sample carries an interval
        // as well as a reading now (`SampleChannel.isCumulative`), so two samples at one position and
        // one pressure are unequal whenever time passed between them — and "the lift landed where the
        // last pending sample did" is a question about where the pen is, not about when.
        if breaks(from: anchor, to: sample), let trailing = pending.last,
           !StrokePathFit.isSamePoint(trailing, sample) {
            committed.append(trailing.absorbing(pending.dropLast()))
        }
        if !StrokePathFit.isSamePoint(sample, anchor) || !committed.isEmpty {
            // Nothing was committed in between, so the lift absorbs the whole pending run; with a
            // trailing knot committed the lift follows it directly and absorbs nothing.
            committed.append(committed.isEmpty ? sample.absorbing(pending) : sample)
        }
        self.anchor = sample
        return committed
    }

    /// Whether two samples are the same *point* — position and pressure, the two things the fit's
    /// thresholds are about. See `finish`.
    private static func isSamePoint(_ a: VectorSample, _ b: VectorSample) -> Bool {
        a.x == b.x && a.y == b.y && a.pressure == b.pressure
    }

    /// Whether the chord from `anchor` to `sample` has stopped standing in for the run between them.
    private func breaks(from anchor: VectorSample, to sample: VectorSample) -> Bool {
        if abs(sample.pressure - anchor.pressure) >= minimumPressureChange { return true }
        if hypot(sample.x - anchor.x, sample.y - anchor.y) > maximumKnotSpacing { return true }
        return deviates(from: anchor.point, to: sample.point)
    }

    /// Whether any pending sample sits further than `tolerance` from the segment `a`–`b`.
    private func deviates(from a: CGPoint, to b: CGPoint) -> Bool {
        guard !pending.isEmpty else { return false }
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let limit = tolerance * tolerance
        for sample in pending {
            let px = sample.x - a.x, py = sample.y - a.y
            let distanceSquared: CGFloat
            if lengthSquared <= 1e-12 {
                distanceSquared = px * px + py * py
            } else {
                let t = min(max((px * dx + py * dy) / lengthSquared, 0), 1)
                let ex = px - dx * t, ey = py - dy * t
                distanceSquared = ex * ex + ey * ey
            }
            if distanceSquared > limit { return true }
        }
        return false
    }
}
