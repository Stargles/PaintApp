import CoreGraphics
import Foundation

/// Analyses a sequence of vector stroke samples to detect whether the freehand path most closely
/// resembles a line, rectangle, or oval. All functions are pure — no UIKit dependency, no state.
///
/// Detection strategy: **fit the candidates and keep the one the stroke actually lies on.** Every
/// candidate is scored by the same quantity — the RMS distance from the stroke's points to that
/// candidate's outline, divided by the candidate's own size — so the three scores live on one
/// comparable scale and the winner is simply the smallest. (A prior detector scored each kind with
/// an incomparable metric of its own — a hand-drawn square scored 1.00 as a rectangle and 0.94 as an
/// oval, so any wobble flipped the answer and rectangles came out as ellipses.)
///
/// Three things make the fit reliable:
///
///   - **Arc-length resampling.** Raw samples cluster wherever the pen moved slowly — and the
///     hold-to-detect gesture *ends* with the pen parked in one spot for 0.8s, piling hundreds of
///     samples on a single point. Resampling to evenly spaced points first makes every mean and
///     RMS below measure the shape rather than the drawing speed.
///   - **A rotation sweep instead of a PCA axis.** A square's covariance matrix is isotropic, so
///     its principal axis is pure noise — the old detector routinely evaluated a square inside a
///     45°-rotated (diamond) bounding box, where it fits nothing and the oval wins by default.
///     Sweeping the angle and keeping the best-fitting box has no degenerate case: for a circle
///     every angle ties and the sweep simply keeps 0°.
///   - **Gates on shape, not on score.** A line is recognised by its own arc-length test (a closed
///     shape must double back, so its arc length always exceeds ~2× its extent) before rect/oval
///     are considered at all, and a closed candidate must have points spread over essentially its
///     whole outline, which is what rejects arcs, hooks and part-drawn boxes.
enum ShapeDetector {

    // MARK: - Tunable thresholds

    /// The minimum total path length (in canvas points) before shape detection fires.
    static let minimumPathLength: CGFloat = 40

    /// Points every stroke is resampled to, evenly spaced by arc length, before anything is fitted.
    /// 64 is far more than the fits need for accuracy and keeps the whole sweep well under a
    /// millisecond.
    private static let resampleCount = 64

    /// A line's arc length may exceed the extent along its own axis by this much (wobble, a slight
    /// bow). Any closed shape has to travel out and back, so its ratio is at least ~2 — this
    /// separates the two cases regardless of how elongated the closed shape is, which an aspect
    /// ratio cutoff cannot do.
    private static let lineLengthRatioMax: CGFloat = 1.5

    /// RMS deviation from the line's own axis, as a fraction of the axis extent.
    private static let lineDeviationMax: CGFloat = 0.06

    /// Worst normalized RMS outline-fit error a rectangle or oval may have and still be accepted.
    /// For reference: a perfect circle measured against a rectangle scores ≈0.07, and a perfect
    /// square measured against an oval ≈0.10, so this floor admits genuinely wobbly freehand while
    /// still rejecting scribbles.
    private static let closedFitErrorMax: CGFloat = 0.16

    /// Angle sweep for rect/oval fitting. The bounding box repeats every 90°, so the sweep runs
    /// ±44° in 2° steps (45 evaluations, including exactly 0°) and then refines around the winner.
    private static let sweepStep: CGFloat = 2 * .pi / 180
    private static let sweepHalfSteps = 22
    private static let refineStep: CGFloat = 0.25 * .pi / 180
    private static let refineHalfSteps = 8

    /// A best-fit rotation this close to axis-aligned is taken as axis-aligned — hand-drawn boxes
    /// land a degree or two off true and reading back as "tilted by 1.5°" looks like a mistake.
    private static let axisSnapTolerance: CGFloat = 2.5 * .pi / 180

    /// Smallest bounding-box side (canvas points) a closed shape may have — of the point cloud, and
    /// of the fitted ellipse's own axes, which are no longer the same box.
    private static let minimumClosedDimension: CGFloat = 5

    /// How far past the stroke's own extent a fitted ellipse's semi-axis may reach. **Numerical
    /// conditioning, not a shape decision**: a short arc admits a family of ellipses and an
    /// algebraic fit can pick an arbitrarily large member of it. Legitimate arcs measure well inside
    /// their own extent at every span, so this is several times the slack they need, and it exists
    /// to catch the ill-posed rather than to judge the partial.
    private static let ellipseExtentMax: CGFloat = 6

    /// The outline is split into this many equal-parameter buckets; a closed candidate is rejected
    /// unless at least `coverageBucketsRequired` of them contain a point. 13/16 tolerates a gap of
    /// about an eighth of the outline (an unclosed circle, a rectangle missing its last corner)
    /// while rejecting arcs and hooks.
    private static let coverageBuckets = 16
    private static let coverageBucketsRequired = 13

    /// A stroke that *traces* an outline covers roughly that outline's own length; freehand wobble
    /// and the micro-jitter of the pen parked in place during the hold push it a little higher.
    /// A stroke covering far more than its outline is doing something else inside the same box —
    /// a zigzag between two edges, hatching, a scribble — and coverage alone can't tell, because
    /// every one of those points really is sitting on the box.
    private static let closedLengthRatioMax: CGFloat = 1.75

    // MARK: - Public API

    /// Detect from raw CGPoints (pressure-agnostic — used by the hold-to-detect gesture).
    static func detect(from points: [CGPoint]) -> ShapeGeometry? {
        let samples = points.map { VectorSample(x: $0.x, y: $0.y, pressure: 0.5) }
        return detect(from: samples)
    }

    /// Analyses the given samples and returns the most likely shape, or `nil` if nothing is
    /// confidently detected. The result's anchors are the two defining points of the detected
    /// shape (line endpoints, rect opposing corners, oval bounding-box corners), in the shape's own
    /// unrotated frame — paired with whatever `rotation` was detected for rect/oval candidates, so a
    /// shape drawn at an angle detects as a rotated rect/oval instead of always axis-aligned.
    static func detect(from samples: some SampleRun) -> ShapeGeometry? {
        guard samples.count >= 3 else { return nil }

        let raw = samples.map(\.point)
        let arcLength = pathLength(raw)
        guard arcLength >= minimumPathLength else { return nil }

        let points = resampled(raw, count: resampleCount)
        guard points.count >= 8 else { return nil }

        // A line is tested first and on its own terms: its gate (below) is one no closed shape can
        // pass, so there is nothing for the closed fits to steal and no scores to reconcile.
        if let line = lineCandidate(points: points, arcLength: arcLength) { return line }
        return closedCandidate(points: points, raw: raw, arcLength: arcLength)
    }

    // MARK: - Line

    /// The stroke as a line, or `nil` if it isn't one. The axis comes from the point cloud's
    /// principal direction rather than the first→last chord, so a hooked lift or a shaky start
    /// tilts the result far less; the endpoints are the extreme projections onto that axis.
    private static func lineCandidate(points: [CGPoint], arcLength: CGFloat) -> ShapeGeometry? {
        let pivot = centroid(points)
        let axis = principalAxis(points: points, about: pivot)

        var minT = CGFloat.greatestFiniteMagnitude, maxT = -CGFloat.greatestFiniteMagnitude
        var sumSquaredPerp: CGFloat = 0
        for p in points {
            let dx = p.x - pivot.x, dy = p.y - pivot.y
            let along = dx * axis.dx + dy * axis.dy
            let across = -dx * axis.dy + dy * axis.dx
            if along < minT { minT = along }
            if along > maxT { maxT = along }
            sumSquaredPerp += across * across
        }
        let extent = maxT - minT
        guard extent > 0 else { return nil }
        // A closed shape doubles back on itself, so its arc length runs to ~2× its extent or more.
        guard arcLength <= extent * lineLengthRatioMax else { return nil }
        let deviation = (sumSquaredPerp / CGFloat(points.count)).squareRoot()
        guard deviation / extent <= lineDeviationMax else { return nil }

        let low = CGPoint(x: pivot.x + axis.dx * minT, y: pivot.y + axis.dy * minT)
        let high = CGPoint(x: pivot.x + axis.dx * maxT, y: pivot.y + axis.dy * maxT)
        // Keep the direction the user drew in: `startPoint` is the end they started from, which is
        // what makes the two endpoint handles behave the way the stroke did.
        let first = points[0]
        let startIsLow = hypot(first.x - low.x, first.y - low.y) <= hypot(first.x - high.x, first.y - high.y)
        return ShapeGeometry(kind: .line,
                             startPoint: startIsLow ? low : high,
                             endPoint: startIsLow ? high : low)
    }

    // MARK: - Rectangle / oval

    /// One evaluated rect-or-oval fit: the bounding box in the frame rotated by `rotation`, and how
    /// far the stroke sits from that outline (RMS distance ÷ the box's geometric mean side).
    private struct ClosedFit {
        var kind: ShapeGeometry.Kind
        var rotation: CGFloat
        var rect: CGRect
        var error: CGFloat
    }

    /// The stroke as a rectangle or an oval — whichever it lies closer to — or `nil` if it is
    /// neither. If the better fit fails the outline-coverage gate the runner-up still gets its
    /// chance, so e.g. a squarish oval isn't lost just because the rectangle scored marginally
    /// better before coverage was considered.
    private static func closedCandidate(points: [CGPoint], raw: [CGPoint],
                                        arcLength: CGFloat) -> ShapeGeometry? {
        let pivot = centroid(points)
        let offsets = points.map { CGPoint(x: $0.x - pivot.x, y: $0.y - pivot.y) }

        let fits = [ShapeGeometry.Kind.rectangle, .oval]
            .compactMap { bestFit($0, offsets: offsets) }
            .filter { $0.error <= closedFitErrorMax }
            .sorted { $0.error < $1.error }

        for candidate in fits {
            // Re-fit dead-on axis-aligned when the winner is within a couple of degrees of it, so
            // the snap can't leave the box measured at one angle and drawn at another.
            let snapped = abs(candidate.rotation) < axisSnapTolerance
                ? (fit(candidate.kind, angle: 0, offsets: offsets) ?? candidate)
                : candidate
            var shape = geometry(for: snapped, pivot: pivot)
            if shape.kind == .oval {
                let span = measuredSpan(of: raw, on: shape)
                shape.spanStart = span.start
                shape.spanSweep = span.sweep
            }
            // The same "is this a trace or a scribble" test it has always been, finally measured
            // against what was actually traced rather than against the whole figure. A correct fit
            // has `arcLength ≈ spanLength` by construction, so a bad one shows up in either
            // direction — and the lower bound is not new policy, it is what `hasOutlineCoverage`
            // used to supply for free.
            let ratio = arcLength / max(shape.spanLength, 1)
            guard ratio <= closedLengthRatioMax, ratio >= 1 / closedLengthRatioMax else { continue }
            // **Rectangles keep coverage; ovals get a span, and that asymmetry is the owner's ask
            // stated precisely.** Coverage was one gate serving both kinds, and for an oval it is
            // the thing being deleted — "was this complete enough to count". For a rectangle it is
            // not: its own doc comment names "a rectangle missing its last corner" as something it
            // rejects, and dropping it there would make a three-sided box detect as a closed
            // rectangle with a phantom fourth side. The owner asked to change ovals.
            if shape.kind == .rectangle {
                guard hasOutlineCoverage(snapped, offsets: offsets) else { continue }
            }
            return shape
        }
        return nil
    }

    /// The portion of `shape`'s outline the raw stroke actually turned through, as a start and a
    /// **signed** sweep in the shape's own body frame.
    ///
    /// The trace is unwrapped rather than compared: each step adds the *shortest* change in `u`, so
    /// the running total is a continuous turn count that never consults the seam. Four properties
    /// fall out of that, and not one of them is a case:
    ///
    ///   - **Seam.** There is no interval with two endpoints to order; there is an origin and a
    ///     signed turn. An arc running from eccentric 120° to 300° crosses `u = 0/1` at 180° and
    ///     simply accumulates 0.833 → 1.333.
    ///   - **Overshoot.** `min(hi − lo, 1)` is monotone in coverage and saturates, so a stroke that
    ///     carries past its own start gives a whole oval and no more, with no oscillation possible.
    ///   - **Direction.** The sign is the direction drawn, and `start` is the artist's own first
    ///     sample — what `testDetectedLineKeepsTheDirectionItWasDrawn` already demands of lines.
    ///   - **Retrace.** `hi − lo` is the extent *visited*, so tracing 90°, backing off and going
    ///     forward again still gives 90° — not less (which would erase ink they laid) and not more
    ///     (which would count travel twice).
    ///
    /// **Raw samples, not the 64-point resample.** The sum telescopes, so sample density cannot
    /// change the answer, while arc-length-uniform resampling would risk aliasing: at a 20:1 aspect
    /// the `u`-step near the major-axis end reaches 0.4 turns. The parked hold at the end of the
    /// gesture contributes ≈ 0 net turn and is harmless.
    static func measuredSpan(of raw: [CGPoint], on shape: ShapeGeometry) -> (start: CGFloat, sweep: CGFloat) {
        guard raw.count >= 2 else { return (0, 1) }
        let inverse = shape.rotationTransform.inverted()
        let box = shape.boundingRect
        let rx = max(box.width / 2, 0.0001), ry = max(box.height / 2, 0.0001)

        /// `nil` for a sample projecting essentially onto the centre, which has no meaningful angle.
        func localU(_ p: CGPoint) -> CGFloat? {
            let q = p.applying(inverse)
            let nx = (q.x - box.midX) / rx, ny = (q.y - box.midY) / ry
            guard hypot(nx, ny) > 1e-3 else { return nil }
            return shape.outlineParameter(of: q)
        }
        func wrapHalf(_ x: CGFloat) -> CGFloat { x - x.rounded() }

        var index = 0
        var seed: CGFloat?
        while seed == nil && index < raw.count { seed = localU(raw[index]); index += 1 }
        guard let firstU = seed else { return (0, 1) }

        var unwrapped = firstU, lo = firstU, hi = firstU
        var currentU = firstU
        var currentPoint = raw[index - 1]

        /// One step of the walk. A jump of more than a quarter turn between consecutive samples
        /// could be a real fast stroke or an aliased one, and the two are indistinguishable from the
        /// endpoints alone — so split the canvas-space segment and look. At 120 Hz this fires on
        /// essentially nothing, but `minimumClosedDimension` permits a semi-axis of 2.5, where a
        /// fast stroke genuinely could alias, and this makes the unwrap unconditionally correct.
        func advance(to b: CGPoint, depth: Int) {
            guard let uB = localU(b) else { return }
            let delta = wrapHalf(uB - currentU)
            if abs(delta) > 0.25, depth < 6 {
                let mid = CGPoint(x: (currentPoint.x + b.x) / 2, y: (currentPoint.y + b.y) / 2)
                if localU(mid) != nil {
                    advance(to: mid, depth: depth + 1)
                    advance(to: b, depth: depth + 1)
                    return
                }
            }
            unwrapped += delta
            if unwrapped < lo { lo = unwrapped }
            if unwrapped > hi { hi = unwrapped }
            currentU = uB
            currentPoint = b
        }

        while index < raw.count {
            advance(to: raw[index], depth: 0)
            index += 1
        }

        let forward = unwrapped >= firstU
        let magnitude = min(hi - lo, 1)
        let origin = forward ? lo : hi
        return (origin - origin.rounded(.down), magnitude * (forward ? 1 : -1))
    }

    /// The lowest-error fit of `kind` over the rotation sweep: a coarse pass across the full 90°
    /// of distinct box orientations, then a fine pass around whatever that found.
    private static func bestFit(_ kind: ShapeGeometry.Kind, offsets: [CGPoint]) -> ClosedFit? {
        var best: ClosedFit?
        func consider(_ angle: CGFloat) {
            guard let candidate = fit(kind, angle: angle, offsets: offsets) else { return }
            if best == nil || candidate.error < best!.error { best = candidate }
        }
        for step in -sweepHalfSteps...sweepHalfSteps { consider(CGFloat(step) * sweepStep) }
        guard let coarse = best else { return nil }
        for step in -refineHalfSteps...refineHalfSteps where step != 0 {
            consider(coarse.rotation + CGFloat(step) * refineStep)
        }
        return best
    }

    /// Fits `kind` to the points inside the frame rotated by `angle`, and scores it by the RMS
    /// distance to that outline normalised by the **point cloud's own** size, so the score is
    /// scale-free.
    ///
    /// A rectangle is still its points' bounding box. **An ellipse is not**, and that is the change
    /// partial ovals rest on: a box only describes the ellipse a stroke lies on when the stroke
    /// reached all four axis extrema, which is exactly what a stroke that stopped short did not do.
    /// Measured on a known 120 × 70 ellipse at 25°, noise-free, the box fit recovers a = 68.5,
    /// b = 17.8 with its centre 74.5 pt adrift from a 90° arc — and scores 0.098, comfortably inside
    /// `closedFitErrorMax`. It would ship that garbage happily. The conic solve below recovers
    /// a = 120.0, b = 70.0 with 0.0 pt of centre error from the same arc.
    ///
    /// **The denominator is the other half, and without it the conic fit is catastrophic.** Dividing
    /// by the *candidate's* size rewards proposing a huge ellipse, and `bestFit` takes the minimum
    /// over the sweep, so it actively hunts for one: measured with 2 pt of jitter on a 90° arc, a
    /// candidate-normalised score picks a = 1257, b = 20279 centred 20 178 pt away. Normalising by
    /// the cloud instead is a provable no-op for everything that works today — for a rectangle the
    /// candidate box *is* the cloud box, and for a whole oval the two coincide to within jitter — and
    /// it is exactly the regulariser a partial stroke needs.
    private static func fit(_ kind: ShapeGeometry.Kind, angle: CGFloat, offsets: [CGPoint]) -> ClosedFit? {
        let c = cos(-angle), s = sin(-angle)
        var local: [CGPoint] = []
        local.reserveCapacity(offsets.count)
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in offsets {
            let x = p.x * c - p.y * s, y = p.x * s + p.y * c
            local.append(CGPoint(x: x, y: y))
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        let cloud = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard cloud.width >= minimumClosedDimension, cloud.height >= minimumClosedDimension else { return nil }
        // The cloud's own geometric mean side — the candidate's size for a rectangle by
        // construction, and deliberately *not* the candidate's size for an ellipse.
        let scale = (cloud.width * cloud.height).squareRoot()

        let rect: CGRect
        switch kind {
        case .rectangle, .line:
            rect = cloud
        case .oval:
            guard let fitted = ellipseThrough(local, cloud: cloud) else { return nil }
            rect = fitted
        }

        var sumSquared: CGFloat = 0
        for q in local {
            let d = kind == .rectangle ? distanceToRectOutline(q, rect) : distanceToEllipse(q, rect)
            sumSquared += d * d
        }
        let error = (sumSquared / CGFloat(offsets.count)).squareRoot() / scale
        return ClosedFit(kind: kind, rotation: angle, rect: rect, error: error)
    }

    /// The axis-aligned ellipse that best fits `local` in the least-squares sense, as the box it is
    /// inscribed in — or `nil` when the points admit no ellipse at all.
    ///
    /// Because `bestFit`'s rotation sweep already supplies the axis alignment, the conic has no `xy`
    /// term, so this is a 4×4 linear solve rather than the eigenproblem a general conic fit needs:
    ///
    ///     model    x² = A·y² + B·x + C·y + D        rows (y², x, y, 1), target x²
    ///     recover  λ = −A (must be > 0);  cx = B/2;  cy = C/(2λ)
    ///              a² = cx² + λ·cy² + D  (must be > 0);  b² = a²/λ
    ///
    /// Solved by Gaussian elimination with partial pivoting rather than `Accelerate`, so this file
    /// and `ShapeGeometry.swift` stay CoreGraphics-only and keep compiling into the test target —
    /// which is the whole reason the headless tier exists.
    ///
    /// This is also the ruling against a one-shot general conic fit (Halíř–Flusser and friends): it
    /// abandons the rotation sweep this file is built around, and recovers the axis angle through
    /// `½·atan2(B, A − C)`, which is degenerate on near-circular data — precisely the case the sweep
    /// was engineered to survive.
    private static func ellipseThrough(_ local: [CGPoint], cloud: CGRect) -> CGRect? {
        guard local.count >= 5 else { return nil }

        // Condition the data or the solve is worthless: at canvas coordinates the normal equations
        // run to ~1e12 condition number, and the recovered axes are noise.
        var meanX: CGFloat = 0, meanY: CGFloat = 0
        for p in local { meanX += p.x; meanY += p.y }
        meanX /= CGFloat(local.count); meanY /= CGFloat(local.count)
        var norm: CGFloat = 0
        for p in local { norm = max(norm, max(abs(p.x - meanX), abs(p.y - meanY))) }
        guard norm > 0 else { return nil }

        // Σ mmᵀ and Σ m·x², built in the conditioned frame.
        var ata = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: 4), count: 4)
        var atb = [CGFloat](repeating: 0, count: 4)
        for p in local {
            let x = (p.x - meanX) / norm, y = (p.y - meanY) / norm
            let m: [CGFloat] = [y * y, x, y, 1]
            let target = x * x
            for i in 0..<4 {
                for j in 0..<4 { ata[i][j] += m[i] * m[j] }
                atb[i] += m[i] * target
            }
        }
        guard let z = solve4x4(ata, atb) else { return nil }

        let lambda = -z[0]
        guard lambda > 1e-9, lambda.isFinite else { return nil }
        let cx = z[1] / 2
        let cy = z[2] / (2 * lambda)
        let aSquared = cx * cx + lambda * cy * cy + z[3]
        guard aSquared > 0, aSquared.isFinite else { return nil }
        let a = aSquared.squareRoot()
        let b = (aSquared / lambda).squareRoot()
        guard a.isFinite, b.isFinite else { return nil }

        // Back out of the conditioned frame.
        let cxR = cx * norm + meanX, cyR = cy * norm + meanY
        let aR = a * norm, bR = b * norm
        guard 2 * aR >= minimumClosedDimension, 2 * bR >= minimumClosedDimension else { return nil }
        // Belt and braces on genuinely ill-posed input: a short arc admits a whole family of
        // ellipses and an algebraic fit can pick an arbitrarily large member of it. Legitimate arcs
        // measure well inside their own extent at every span, so this is fourfold slack rather than
        // a shape decision.
        let extent = max(cloud.width, cloud.height)
        guard max(aR, bR) <= ellipseExtentMax * extent else { return nil }

        return CGRect(x: cxR - aR, y: cyR - bR, width: 2 * aR, height: 2 * bR)
    }

    /// Gaussian elimination with partial pivoting. Small and fixed-size on purpose — see
    /// `ellipseThrough` on why this file takes no dependency on `Accelerate`.
    private static func solve4x4(_ a: [[CGFloat]], _ b: [CGFloat]) -> [CGFloat]? {
        var m = a
        var v = b
        for col in 0..<4 {
            var pivot = col
            for row in (col + 1)..<4 where abs(m[row][col]) > abs(m[pivot][col]) { pivot = row }
            guard abs(m[pivot][col]) > 1e-12 else { return nil }
            if pivot != col { m.swapAt(pivot, col); v.swapAt(pivot, col) }
            for row in (col + 1)..<4 {
                let factor = m[row][col] / m[col][col]
                guard factor.isFinite else { return nil }
                for k in col..<4 { m[row][k] -= factor * m[col][k] }
                v[row] -= factor * v[col]
            }
        }
        var z = [CGFloat](repeating: 0, count: 4)
        for row in stride(from: 3, through: 0, by: -1) {
            var sum = v[row]
            for k in (row + 1)..<4 { sum -= m[row][k] * z[k] }
            z[row] = sum / m[row][row]
            guard z[row].isFinite else { return nil }
        }
        return z
    }

    /// Distance from a point to a rectangle's *outline* — zero on the perimeter, growing both
    /// outward and inward, unlike the usual point-in-rect distance which is zero everywhere inside.
    private static func distanceToRectOutline(_ p: CGPoint, _ rect: CGRect) -> CGFloat {
        let qx = max(rect.minX - p.x, p.x - rect.maxX)
        let qy = max(rect.minY - p.y, p.y - rect.maxY)
        if qx > 0 || qy > 0 { return hypot(max(qx, 0), max(qy, 0)) }
        return -max(qx, qy)  // inside: distance to the nearest edge
    }

    /// Distance from a point to the ellipse inscribed in `rect`, measured along the ray from the
    /// centre. The true nearest-point distance needs an iterative solve; this closed form agrees
    /// with it to within a few percent near the curve, is monotone in the same direction, and is
    /// what makes the whole sweep cheap enough to run twice per detection.
    private static func distanceToEllipse(_ p: CGPoint, _ rect: CGRect) -> CGFloat {
        let a = rect.width / 2, b = rect.height / 2
        let dx = p.x - rect.midX, dy = p.y - rect.midY
        let normalized = hypot(dx / a, dy / b)
        guard normalized > 0 else { return min(a, b) }
        let radius = hypot(dx, dy)
        return abs(radius - radius / normalized)
    }

    /// True when the stroke covers essentially the whole of `fit`'s outline. Buckets the points by
    /// their outline parameter, which is arc length for a rectangle and angle for an oval, so a
    /// missing side and a missing arc are both caught by one rule.
    private static func hasOutlineCoverage(_ fit: ClosedFit, offsets: [CGPoint]) -> Bool {
        let outline = ShapeGeometry(kind: fit.kind, startPoint: fit.rect.origin,
                                    endPoint: CGPoint(x: fit.rect.maxX, y: fit.rect.maxY))
        let c = cos(-fit.rotation), s = sin(-fit.rotation)
        var covered = [Bool](repeating: false, count: coverageBuckets)
        for p in offsets {
            let local = CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c)
            let u = outline.outlineParameter(of: local)
            covered[min(Int(u * CGFloat(coverageBuckets)), coverageBuckets - 1)] = true
        }
        return covered.lazy.filter { $0 }.count >= coverageBucketsRequired
    }

    /// Lifts a fit back into canvas space. The fit's box lives in a frame rotated about the point
    /// cloud's centroid, but `ShapeGeometry.rotation` turns about the shape's *own* centre — so the
    /// box is shifted by however far its centre moves under that rotation, which makes the two
    /// placements identical.
    private static func geometry(for fit: ClosedFit, pivot: CGPoint) -> ShapeGeometry {
        let localCenter = CGPoint(x: fit.rect.midX, y: fit.rect.midY)
        let c = cos(fit.rotation), s = sin(fit.rotation)
        let rotatedCenter = CGPoint(x: localCenter.x * c - localCenter.y * s,
                                    y: localCenter.x * s + localCenter.y * c)
        let originX = pivot.x + fit.rect.minX + (rotatedCenter.x - localCenter.x)
        let originY = pivot.y + fit.rect.minY + (rotatedCenter.y - localCenter.y)
        return ShapeGeometry(kind: fit.kind,
                             startPoint: CGPoint(x: originX, y: originY),
                             endPoint: CGPoint(x: originX + fit.rect.width, y: originY + fit.rect.height),
                             rotation: fit.rotation)
    }

    // MARK: - Path utilities

    /// Mean of a point set.
    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Unit vector along the point cloud's direction of greatest spread, from the closed-form
    /// dominant eigenvector of its 2×2 covariance matrix. Only the line fit uses this — rect and
    /// oval sweep instead, because this is degenerate (pure noise) for anything square or circular.
    private static func principalAxis(points: [CGPoint], about pivot: CGPoint) -> (dx: CGFloat, dy: CGFloat) {
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in points {
            let dx = p.x - pivot.x, dy = p.y - pivot.y
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        guard sxx != syy || sxy != 0 else { return (1, 0) }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        return (cos(angle), sin(angle))
    }

    /// Resamples a polyline to exactly `count` points spaced evenly by arc length. Every metric in
    /// this file assumes points sample the *shape* uniformly; raw input samples the *pen's motion*,
    /// which bunches up wherever it slowed or stopped.
    static func resampled(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count >= 2, count >= 2 else { return points }
        var cumulative: [CGFloat] = [0]
        cumulative.reserveCapacity(points.count)
        for i in 1..<points.count {
            cumulative.append(cumulative[i - 1] + hypot(points[i].x - points[i - 1].x,
                                                        points[i].y - points[i - 1].y))
        }
        guard let total = cumulative.last, total > 0 else { return points }

        var result: [CGPoint] = []
        result.reserveCapacity(count)
        var segment = 1
        for i in 0..<count {
            let target = total * CGFloat(i) / CGFloat(count - 1)
            while segment < points.count - 1 && cumulative[segment] < target { segment += 1 }
            let span = cumulative[segment] - cumulative[segment - 1]
            let t = span > 0 ? (target - cumulative[segment - 1]) / span : 0
            let a = points[segment - 1], b = points[segment]
            result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return result
    }

    /// Total arc length of a polyline.
    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for i in 1..<points.count {
            length += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return length
    }

    // MARK: - Stroke collapsing (collapse the freehand stroke down onto the detected shape)

    /// The fewest outline steps worth emitting, so a tiny shape still reads as its own kind rather
    /// than as a couple of stray dabs.
    ///
    /// The oval's floor scales with how much of the outline was actually drawn — 24 steps is what
    /// makes a whole ellipse read as a curve rather than a polygon, and spending all 24 on a
    /// twentieth of one would be a different, denser shape. At the default whole span this is
    /// exactly the 24 it has always been.
    private static func minimumSteps(for shape: ShapeGeometry) -> Int {
        switch shape.kind {
        case .line: return 2
        case .rectangle: return 8
        case .oval: return max(4, Int((24 * abs(shape.spanSweep)).rounded()))
        }
    }

    /// Collapses a freehand stroke down onto a detected shape: walks the shape's outline at
    /// `spacing` and gives every step the pressure the freehand stroke had where it passed that part
    /// of the outline. The result traces the shape exactly while keeping the original stroke's
    /// pressure profile, so the baked shape carries the same brush feel the user actually drew.
    ///
    /// Resampling the outline — rather than projecting each sample onto it and re-sorting — is what
    /// makes this seam-free. Projected samples leave a hole wherever the freehand path didn't quite
    /// close, and re-sorting them by outline position turns that hole into a chord drawn straight
    /// across the shape. Walking the outline instead means coverage is complete by construction.
    ///
    /// With no samples at all (nothing was captured before detection fired) the pressure is a flat
    /// 0.5, which makes this the sole shape-baking path rather than needing a separate fallback.
    /// `shape.rotation` is applied last, so the result lands exactly where the preview showed it.
    ///
    /// The walk runs along the *drawn* portion of the outline, which for a whole shape is the whole
    /// outline and for a stroke that stopped short is the part it reached. There is no branch for
    /// the two: `pointOnSpan(at: 1)` on a full span lands back on `spanStart`, so the seam still
    /// closes by construction, and on a partial one it lands where the pen lifted. The bug the
    /// paragraph above records — projecting samples and re-sorting them into a chord — stays
    /// structurally impossible either way, because this still walks rather than projects.
    /// **The result carries pressure and nothing else**, and that is a fact about the geometry rather
    /// than an omission: these points are not the ones the artist drew, they are a fresh walk of the
    /// shape's outline, so there is no tilt reading or interval that belongs to any of them. BRUSH.md
    /// §5.5's neutral is what a brush reading tilt gets from a shape, and it is the correct answer.
    static func collapseSamplesToShape(samples: some SampleRun, shape: ShapeGeometry,
                                       spacing: CGFloat) -> StrokeSamples {
        let length = shape.spanLength
        guard length > 0 else { return StrokeSamples(channels: .pressureOnly) }

        let step = max(spacing, 1)
        let steps = max(Int((length / step).rounded()), minimumSteps(for: shape))
        let profile = pressureProfile(samples: samples, shape: shape)
        let rotation = shape.rotationTransform
        let period = shape.pressurePeriod

        return StrokeSamples((0...steps).map { i in
            let s = CGFloat(i) / CGFloat(steps)
            let point = shape.pointOnSpan(at: s).applying(rotation)
            return VectorSample(x: point.x, y: point.y,
                                pressure: pressure(at: s, in: profile, period: period))
        }, channels: .pressureOnly)
    }

    /// The freehand stroke's pressure as a function of outline position, sorted by parameter.
    ///
    /// The samples are compared against the shape's *unrotated* outline on purpose: they were drawn
    /// in that frame (rotation only ever gets applied afterwards, by the user turning the shape), so
    /// this keeps the pressure profile glued to the shape's own frame and lets it turn with it.
    /// Keyed on the *drawn* arc's own parameter, so a stroke that covered a quarter of the ellipse
    /// spreads its pressure over that quarter rather than over the whole figure. At the default
    /// whole span this is `outlineParameter` exactly.
    private static func pressureProfile(samples: some SampleRun,
                                        shape: ShapeGeometry) -> [(u: CGFloat, pressure: CGFloat)] {
        samples
            .map { (u: shape.spanParameter(of: $0.point), pressure: max(0, min(1, $0.pressure))) }
            .sorted { $0.u < $1.u }
    }

    /// Pressure at drawn-arc parameter `s`, linearly interpolated between the two profile entries
    /// bracketing it. Past either end the profile wraps to its other end one `period` away.
    ///
    /// **`period` is where a boolean used to be, and replacing it is the point.** This took
    /// `isClosed` and had two `guard isClosed else { return first/last.pressure }` branches — the
    /// "closed versus not closed" split that a feature with no modes must not re-derive under a new
    /// name. One period covers all three cases as a limit rather than a case: a whole closed outline
    /// has period 1, so the wrap partner sits exactly one turn away and this is bit-identical to the
    /// old `isClosed == true` arm; a line has period 1e30, so `t` evaluates to exactly 1.0 in double
    /// precision and returns the end value, bit-identical to the old `isClosed == false` arm; a
    /// quarter arc has period 4, so the partner is three units away in `s` and carries under 1% of
    /// the weight, and the ends behave as open without anything having tested for it.
    private static func pressure(at s: CGFloat, in profile: [(u: CGFloat, pressure: CGFloat)],
                                 period: CGFloat) -> CGFloat {
        guard let first = profile.first, let last = profile.last else { return 0.5 }
        guard profile.count > 1 else { return first.pressure }

        // First index at or after `s`.
        var low = 0, high = profile.count
        while low < high {
            let mid = (low + high) / 2
            if profile[mid].u < s { low = mid + 1 } else { high = mid }
        }

        if low == 0 {
            return interpolate(from: (last.u - period, last.pressure), to: (first.u, first.pressure), at: s)
        }
        if low == profile.count {
            return interpolate(from: (last.u, last.pressure), to: (first.u + period, first.pressure), at: s)
        }
        return interpolate(from: profile[low - 1], to: profile[low], at: s)
    }

    private static func interpolate(from a: (u: CGFloat, pressure: CGFloat),
                                    to b: (u: CGFloat, pressure: CGFloat), at u: CGFloat) -> CGFloat {
        let span = b.u - a.u
        guard span > 0 else { return b.pressure }
        let t = max(0, min(1, (u - a.u) / span))
        return a.pressure + (b.pressure - a.pressure) * t
    }
}