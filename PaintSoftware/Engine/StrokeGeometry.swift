import CoreGraphics
import Foundation

/// The geometry that every vector-eraser mode needs, and that liquify and selection hit-testing will
/// need after them: distances to a stroke, the capsule chain a stroke's rendered footprint reduces
/// to, how much of a stroke's *own width* an eraser covers at a point, where two strokes cross, and
/// how to cut a sample run at an exact parametric position rather than at sample granularity.
///
/// Dependency-free on purpose — `CoreGraphics` + `Foundation`, no UIKit, no reference types, no
/// locks — same as `ShapeGeometry`: it lets this file compile a second time straight into
/// `PaintSoftwareUITests`, so every primitive here is unit-testable headlessly instead of only
/// reachable through a simulator gesture. An `enum` namespace rather than a struct: no state to carry.
///
/// ## Parametric positions
///
/// Positions along a sample run are expressed as a single `CGFloat` in "sample index + fraction"
/// form: `3.0` is exactly `samples[3]`, `3.5` is midway between `samples[3]` and `samples[4]`. The
/// valid domain of an `n`-sample run is therefore `0...(n - 1)`, and a single-sample run's domain is
/// the degenerate `0...0`. Every function here that takes or returns a position uses that
/// convention, so a parameter produced by `closestPoint(onPolyline:to:)` can be fed straight to
/// `interpolatedSample(in:at:)` or `splitStroke(_:removing:)` without conversion.
///
/// ## Squared distances
///
/// Distance queries return *squared* distances wherever the caller can use them that way. These run
/// per touch sample against every candidate segment in the eraser's swept box; `sqrt` on that path
/// buys nothing, because comparing against a radius is comparing against a radius squared.
enum StrokeGeometry {

    /// Below this, a length or a determinant is treated as zero. Chosen well under a canvas point:
    /// input samples arrive in canvas points and coordinates are in the hundreds-to-thousands range,
    /// so `1e-9` is comfortably inside `CGFloat`'s (Double's) precision at that magnitude while
    /// still catching genuinely coincident points.
    static let epsilon: CGFloat = 1e-9

    // MARK: - Distance primitives

    /// Where on segment `a`→`b` the point closest to `point` lies: the clamped projection parameter
    /// `t ∈ 0...1`, that point, and its squared distance from `point`.
    ///
    /// A zero-length segment reports `t == 0` and the distance to `a`, which is the answer a lone
    /// dab wants — `VectorCanvas` can and does hold single-sample strokes.
    static func closestPointOnSegment(from point: CGPoint, a: CGPoint, b: CGPoint)
        -> (t: CGFloat, point: CGPoint, distanceSquared: CGFloat) {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > epsilon else {
            let ex = point.x - a.x, ey = point.y - a.y
            return (0, a, ex * ex + ey * ey)
        }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let foot = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
        let fx = point.x - foot.x, fy = point.y - foot.y
        return (t, foot, fx * fx + fy * fy)
    }

    /// Squared distance from `point` to segment `a`→`b`.
    ///
    /// This is the primitive today's `VectorCanvas.erase` is missing: it compares the eraser's
    /// *points* to a stroke's samples, so a small eraser dragged between two coarse samples erases
    /// nothing at all. Point-to-segment closes that hole.
    static func distanceSquared(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        closestPointOnSegment(from: point, a: a, b: b).distanceSquared
    }

    /// Squared distance from `point` to the polyline through `polyline`. `.infinity` when empty.
    static func distanceSquared(from point: CGPoint, toPolyline polyline: [CGPoint]) -> CGFloat {
        closestPoint(count: polyline.count, to: point) { polyline[$0] }?.distanceSquared ?? .infinity
    }

    /// Squared distance from `point` to the polyline through `samples`. `.infinity` when empty.
    ///
    /// A separate overload rather than `samples.map(\.point)` at the call site: this is the hot query
    /// (once per stroke per eraser sample) and the mapping would allocate an array per call.
    static func distanceSquared(from point: CGPoint, toPolyline samples: [VectorSample]) -> CGFloat {
        closestPoint(count: samples.count, to: point) { samples[$0].point }?.distanceSquared ?? .infinity
    }

    /// The point on the polyline through `polyline` closest to `point`, as a parametric position (see
    /// the type comment), the point itself, and its squared distance. Nil for an empty polyline.
    static func closestPoint(onPolyline polyline: [CGPoint], to point: CGPoint)
        -> (parameter: CGFloat, point: CGPoint, distanceSquared: CGFloat)? {
        closestPoint(count: polyline.count, to: point) { polyline[$0] }
    }

    /// The point on the polyline through `samples` closest to `point` — Mode 3's opening move, which
    /// turns a touch-down location into "which stroke, and where along it".
    static func closestPoint(onPolyline samples: [VectorSample], to point: CGPoint)
        -> (parameter: CGFloat, point: CGPoint, distanceSquared: CGFloat)? {
        closestPoint(count: samples.count, to: point) { samples[$0].point }
    }

    /// Shared body of the two `closestPoint(onPolyline:to:)` overloads, reading vertices through a
    /// non-escaping accessor so neither overload has to materialise an intermediate array.
    private static func closestPoint(count: Int, to point: CGPoint, _ vertex: (Int) -> CGPoint)
        -> (parameter: CGFloat, point: CGPoint, distanceSquared: CGFloat)? {
        guard count > 0 else { return nil }
        guard count > 1 else {
            let v = vertex(0)
            let dx = point.x - v.x, dy = point.y - v.y
            return (0, v, dx * dx + dy * dy)
        }
        var best = (parameter: CGFloat(0), point: vertex(0), distanceSquared: CGFloat.infinity)
        for i in 0..<(count - 1) {
            let hit = closestPointOnSegment(from: point, a: vertex(i), b: vertex(i + 1))
            if hit.distanceSquared < best.distanceSquared {
                best = (CGFloat(i) + hit.t, hit.point, hit.distanceSquared)
            }
        }
        return best
    }

    /// Bounding box of a sample run's centerline, optionally inflated by `padding` (pass the stroke's
    /// maximum half-width to get the box its *ink* occupies). Nil for an empty run.
    static func bounds(of samples: [VectorSample], padding: CGFloat = 0) -> CGRect? {
        guard let first = samples.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for s in samples.dropFirst() {
            minX = min(minX, s.x); maxX = max(maxX, s.x)
            minY = min(minY, s.y); maxY = max(maxY, s.y)
        }
        return CGRect(x: minX - padding, y: minY - padding,
                      width: (maxX - minX) + 2 * padding, height: (maxY - minY) + 2 * padding)
    }

    // MARK: - Capsule chain

    /// One link of a stroke's rendered footprint: the region swept by a disk moving from `a` to `b`
    /// while its radius goes from `ra` to `rb` — i.e. the convex hull of `disk(a, ra)` and
    /// `disk(b, rb)`, a stadium when the radii match and a round-ended cone when they don't.
    ///
    /// This is the continuous stand-in for what `BrushStamper` actually paints, which is a discrete
    /// run of overlapping circular dabs spaced `stampSpacing` apart. The capsule is what the dabs
    /// *look like* once they overlap, and it is what makes coverage a closed-form calculation instead
    /// of a per-dab rasterisation. The approximation is tight for any spacing under ~1 (dabs
    /// overlapping), and generous — it fills the gaps — for a deliberately gappy brush, which is why
    /// Mode 1's clean-cut decision carries a separate alpha gate rather than trusting geometry alone.
    struct Capsule: Equatable {
        var a: CGPoint
        var b: CGPoint
        var ra: CGFloat
        var rb: CGFloat

        init(a: CGPoint, b: CGPoint, ra: CGFloat, rb: CGFloat) {
            self.a = a
            self.b = b
            self.ra = ra
            self.rb = rb
        }

        /// A lone dab: a zero-length capsule of constant radius.
        init(dabAt point: CGPoint, radius: CGFloat) {
            self.init(a: point, b: point, ra: radius, rb: radius)
        }

        var boundingBox: CGRect {
            let minX = min(a.x - ra, b.x - rb), maxX = max(a.x + ra, b.x + rb)
            let minY = min(a.y - ra, b.y - rb), maxY = max(a.y + ra, b.y + rb)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        /// Whether `point` is inside the swept region. Exact, including the tapered case.
        ///
        /// `point` is inside iff some disk along the sweep contains it, i.e. iff
        /// `min over t in 0...1 of (|point - c(t)|² - r(t)²) <= 0`. Both terms are quadratics in `t`,
        /// so their difference is one quadratic and its minimum over the unit interval is the vertex
        /// clamped to `0...1` — no iteration, no `sqrt`.
        func contains(_ point: CGPoint) -> Bool {
            let dx = b.x - a.x, dy = b.y - a.y
            let wx = point.x - a.x, wy = point.y - a.y
            let dr = rb - ra
            // f(t) = quadA·t² - 2·quadB·t + quadC
            let quadA = dx * dx + dy * dy - dr * dr
            let quadB = wx * dx + wy * dy + ra * dr
            let quadC = wx * wx + wy * wy - ra * ra
            func f(_ t: CGFloat) -> CGFloat { quadA * t * t - 2 * quadB * t + quadC }
            if f(0) <= 0 || f(1) <= 0 { return true }
            // A negative `quadA` means the radius grows faster than the centre moves — the sweep is
            // then just the larger end disk, whose interior is already covered by the endpoint checks
            // above, and f is concave so its minimum can only be at an endpoint.
            guard quadA > StrokeGeometry.epsilon else { return false }
            let vertex = quadB / quadA
            guard vertex > 0, vertex < 1 else { return false }
            return f(vertex) <= 0
        }
    }

    /// The stamp radius `BrushStamper` will use at a given pressure — the single definition both the
    /// renderer's geometry and the eraser's geometry must agree on.
    ///
    /// Mirrors `BrushStamper.stampDab` exactly, including its `max(..., 0.5)` diameter floor: if the
    /// two drifted apart, Mode 1 would decide a span was fully covered at a width the renderer never
    /// actually drew, and leave a fringe of ink behind at the cut.
    static func stampRadius(forPressure pressure: CGFloat, brush: Brush, size: CGFloat) -> CGFloat {
        let clamped = Double(max(0, min(pressure, 1)))
        let fraction = brush.dynamics.sizeFraction(forPressure: clamped)
        return max(size * CGFloat(fraction), 0.5) / 2
    }

    /// A stroke's footprint as a capsule chain: one capsule per segment, radii taken from the two
    /// samples' pressures. A single-sample run yields one zero-length capsule (the lone dab it
    /// renders as), so downstream code never has to special-case `count == 1`.
    static func capsuleChain(samples: [VectorSample], brush: Brush, size: CGFloat) -> [Capsule] {
        guard !samples.isEmpty else { return [] }
        guard samples.count > 1 else {
            return [Capsule(dabAt: samples[0].point,
                            radius: stampRadius(forPressure: samples[0].pressure, brush: brush, size: size))]
        }
        var chain: [Capsule] = []
        chain.reserveCapacity(samples.count - 1)
        var previousRadius = stampRadius(forPressure: samples[0].pressure, brush: brush, size: size)
        for i in 1..<samples.count {
            let radius = stampRadius(forPressure: samples[i].pressure, brush: brush, size: size)
            chain.append(Capsule(a: samples[i - 1].point, b: samples[i].point, ra: previousRadius, rb: radius))
            previousRadius = radius
        }
        return chain
    }

    /// A constant-radius capsule chain along a bare polyline — the shape of a live eraser drag, whose
    /// touch points carry no per-sample pressure of their own at the time the geometry is needed.
    static func capsuleChain(points: [CGPoint], radius: CGFloat) -> [Capsule] {
        guard !points.isEmpty else { return [] }
        guard points.count > 1 else { return [Capsule(dabAt: points[0], radius: radius)] }
        var chain: [Capsule] = []
        chain.reserveCapacity(points.count - 1)
        for i in 1..<points.count {
            chain.append(Capsule(a: points[i - 1], b: points[i], ra: radius, rb: radius))
        }
        return chain
    }

    /// Union of a chain's bounding boxes — the swept box a spatial-index query starts from. Nil when
    /// the chain is empty.
    static func bounds(of capsules: [Capsule]) -> CGRect? {
        guard let first = capsules.first else { return nil }
        return capsules.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
    }

    // MARK: - Coverage

    /// The interval along a line that one capsule covers, measured in the line's own parameter `s`
    /// (so `origin + s · direction`), or nil if the capsule never reaches the line. `direction` must
    /// be a unit vector, which makes `s` a signed distance.
    ///
    /// **Why this is closed form.** The capsule is the union over `t ∈ 0...1` of `disk(c(t), r(t))`
    /// with `c` and `r` both affine in `t`. Each disk meets the line in the interval
    /// `u(t) ± sqrt(r(t)² - v(t)²)`, where `u(t)` is the disk centre's coordinate along the line and
    /// `v(t)` its signed offset from the line — both affine in `t`. So `W(t) = r(t)² - v(t)²` is one
    /// quadratic, the covered set is `{ u(t) ± sqrt(W(t)) : t where W(t) >= 0 }`, and because the
    /// capsule is convex its intersection with a line is a single interval. The extremes of
    /// `u(t) ± sqrt(W(t))` are therefore attained either at a boundary of `{t in 0...1 : W(t) >= 0}`
    /// — which can only be `0`, `1`, or a root of `W` — or at an interior stationary point. Setting
    /// the derivative to zero and squaring gives one more quadratic, so **six candidate `t` values**
    /// bound the whole thing. Evaluating a candidate that is not actually an extremum is harmless: it
    /// can only produce an interval inside the true one, and we take the min/max.
    ///
    /// The alternative — marching along the cross-section testing `Capsule.contains` — costs an
    /// arbitrary accuracy/time trade-off per sample and gets the "exactly half covered" case subtly
    /// wrong, which is precisely the case Mode 1's clean-cut decision hinges on.
    static func coveredInterval(of capsule: Capsule, onLineThrough origin: CGPoint,
                                direction: CGPoint) -> ClosedRange<CGFloat>? {
        let dx = capsule.b.x - capsule.a.x, dy = capsule.b.y - capsule.a.y
        let ex = capsule.a.x - origin.x, ey = capsule.a.y - origin.y
        // The line's normal, so an offset can be measured perpendicular to `direction`.
        let px = -direction.y, py = direction.x

        let u0 = ex * direction.x + ey * direction.y      // u(t) = u0 + alpha·t
        let alpha = dx * direction.x + dy * direction.y
        let v0 = ex * px + ey * py                        // v(t) = v0 + beta·t
        let beta = dx * px + dy * py
        let r0 = capsule.ra                               // r(t) = r0 + gamma·t
        let gamma = capsule.rb - capsule.ra

        // W(t) = quadA·t² + 2·quadB·t + quadC
        let quadA = gamma * gamma - beta * beta
        let quadB = r0 * gamma - v0 * beta
        let quadC = r0 * r0 - v0 * v0

        var low = CGFloat.infinity
        var high = -CGFloat.infinity
        var found = false

        func consider(_ t: CGFloat) {
            guard t >= 0, t <= 1 else { return }
            let w = quadA * t * t + 2 * quadB * t + quadC
            guard w >= -epsilon else { return }
            let reach = sqrt(max(w, 0))
            let u = u0 + alpha * t
            low = min(low, u - reach)
            high = max(high, u + reach)
            found = true
        }

        consider(0)
        consider(1)
        // Boundaries of the reachable t-range.
        let (wRoot0, wRoot1) = quadraticRoots(a: quadA, halfB: quadB, c: quadC)
        if let wRoot0 { consider(wRoot0) }
        if let wRoot1 { consider(wRoot1) }
        // Interior stationary points of u(t) ± sqrt(W(t)): d/dt = alpha ± W'(t)/(2·sqrt(W)) = 0
        // squares to W'(t)² = 4·alpha²·W(t), i.e. the quadratic below.
        let shifted = quadA - alpha * alpha
        let (sRoot0, sRoot1) = quadraticRoots(a: quadA * shifted, halfB: quadB * shifted,
                                              c: quadB * quadB - alpha * alpha * quadC)
        if let sRoot0 { consider(sRoot0) }
        if let sRoot1 { consider(sRoot1) }

        return found ? low...high : nil
    }

    /// Fraction (`0...1`) of the interval `[-halfWidth, +halfWidth]` along the line through `center`
    /// in direction `normal` that lies inside the **union** of `capsules`.
    ///
    /// Union, not sum: overlapping eraser capsules — which is the normal case, since a chain's
    /// consecutive links always overlap — would otherwise push the fraction past 1 and report a
    /// grazing shave as a full-width cut.
    ///
    /// `scratch` is carried in by the caller because this runs once per paint sample per erase, and a
    /// fresh interval buffer per sample is a heap allocation on the touch path. Contents on entry are
    /// ignored; contents on exit are undefined.
    static func crossSectionCoverage(center: CGPoint, normal: CGPoint, halfWidth: CGFloat,
                                     by capsules: [Capsule],
                                     scratch: inout [ClosedRange<CGFloat>]) -> CGFloat {
        guard halfWidth > 0, !capsules.isEmpty else { return 0 }
        guard let unit = normalized(normal) else { return 0 }
        scratch.removeAll(keepingCapacity: true)
        for capsule in capsules {
            guard let interval = coveredInterval(of: capsule, onLineThrough: center, direction: unit) else { continue }
            let low = max(interval.lowerBound, -halfWidth)
            let high = min(interval.upperBound, halfWidth)
            guard high > low else { continue }
            scratch.append(low...high)
        }
        guard !scratch.isEmpty else { return 0 }
        scratch.sort { $0.lowerBound < $1.lowerBound }
        var covered: CGFloat = 0
        var runLow = scratch[0].lowerBound
        var runHigh = scratch[0].upperBound
        for interval in scratch.dropFirst() {
            if interval.lowerBound > runHigh {
                covered += runHigh - runLow
                runLow = interval.lowerBound
                runHigh = interval.upperBound
            } else if interval.upperBound > runHigh {
                runHigh = interval.upperBound
            }
        }
        covered += runHigh - runLow
        return min(max(covered / (2 * halfWidth), 0), 1)
    }

    /// Convenience form of `crossSectionCoverage` that owns its interval buffer. Fine for tests and
    /// one-shot queries; prefer the `scratch:` form when walking a whole stroke.
    static func crossSectionCoverage(center: CGPoint, normal: CGPoint, halfWidth: CGFloat,
                                     by capsules: [Capsule]) -> CGFloat {
        var scratch: [ClosedRange<CGFloat>] = []
        scratch.reserveCapacity(capsules.count)
        return crossSectionCoverage(center: center, normal: normal, halfWidth: halfWidth,
                                    by: capsules, scratch: &scratch)
    }

    /// How much of the paint stroke's own width at `index` the eraser capsules cover — the heart of
    /// Mode 1's clean-cut decision. `1` means the stroke is severed at this sample as far as geometry
    /// is concerned; anything less is a partial-width shave that only the alpha-punch path can express.
    ///
    /// Geometry only: the alpha gate (hardness, opacity × flow) is the caller's, deliberately,
    /// because it is a property of the eraser brush rather than of the two footprints.
    static func coverage(ofSampleAt index: Int, in samples: [VectorSample], brush: Brush, size: CGFloat,
                         by erasers: [Capsule], scratch: inout [ClosedRange<CGFloat>]) -> CGFloat {
        guard samples.indices.contains(index) else { return 0 }
        let sample = samples[index]
        let radius = stampRadius(forPressure: sample.pressure, brush: brush, size: size)
        return crossSectionCoverage(center: sample.point, normal: normal(ofSampleAt: index, in: samples),
                                    halfWidth: radius, by: erasers, scratch: &scratch)
    }

    /// Convenience form of `coverage(ofSampleAt:...)` that owns its interval buffer.
    static func coverage(ofSampleAt index: Int, in samples: [VectorSample], brush: Brush, size: CGFloat,
                         by erasers: [Capsule]) -> CGFloat {
        var scratch: [ClosedRange<CGFloat>] = []
        scratch.reserveCapacity(erasers.count)
        return coverage(ofSampleAt: index, in: samples, brush: brush, size: size,
                        by: erasers, scratch: &scratch)
    }

    /// Whether the disc of `radius` at `center` lies **wholly inside a single** capsule of `capsules`.
    ///
    /// Mode 1 needs this for the one piece of a stroke that has no cross-section: its round end cap.
    /// `coverage(atParameter:…)` answers about the segment across the stroke at a parameter, and the
    /// cap sticks out half a width *past* the last parameter there is, so a stroke whose every
    /// cross-section is covered can still have two uncovered blobs at its ends.
    ///
    /// Deliberately sufficient rather than necessary: a disc straddling two capsules that only cover
    /// it together is reported uncovered. Tightening that would mean unioning the boundary arcs, and
    /// the payoff would be small — the caller uses this to decide whether a stroke end may be deleted
    /// outright instead of being trimmed back, so a false negative costs a retained stub of geometry
    /// hidden under the punch, and a false positive would delete ink the eraser never touched. Only
    /// one of those is recoverable.
    ///
    /// `min(ra, rb)` rather than the radius interpolated at the closest point, for the same reason: a
    /// capsule's radius varies affinely along its axis, so the minimum is a lower bound everywhere on
    /// it and using it can only under-report.
    static func capsules(_ capsules: [Capsule], contain center: CGPoint, radius: CGFloat) -> Bool {
        for capsule in capsules {
            let inner = min(capsule.ra, capsule.rb) - radius
            guard inner >= 0 else { continue }
            if distanceSquared(from: center, toSegment: capsule.a, capsule.b) <= inner * inner {
                return true
            }
        }
        return false
    }

    /// Coverage at an arbitrary **parametric position** rather than at a stored sample.
    ///
    /// Mode 1's clean-cut decision needs this for the same reason Mode 2's cut boundaries do:
    /// judging coverage only at stored samples puts the verdict — and therefore the cut — wherever
    /// the touch sampler happened to drop a point, which on a fast drag is tens of points away from
    /// where the eraser's edge actually falls. Probing the parametric domain and bisecting the
    /// crossing puts it within a fraction of a pixel instead.
    ///
    /// `margin` inflates the half-width the eraser has to cover before this reports 1: anti-aliased
    /// fringe means a stroke whose geometric half-width is *just* covered still leaves a visible
    /// edge, so a clean cut requires the eraser to overshoot slightly.
    static func coverage(atParameter parameter: CGFloat, in samples: [VectorSample], brush: Brush,
                         size: CGFloat, by erasers: [Capsule], margin: CGFloat = 0,
                         scratch: inout [ClosedRange<CGFloat>]) -> CGFloat {
        guard let sample = interpolatedSample(in: samples, at: parameter) else { return 0 }
        let radius = stampRadius(forPressure: sample.pressure, brush: brush, size: size) * (1 + margin)
        let t = tangent(atParameter: parameter, in: samples)
        return crossSectionCoverage(center: sample.point, normal: CGPoint(x: -t.y, y: t.x),
                                    halfWidth: radius, by: erasers, scratch: &scratch)
    }

    /// Unit tangent at a parametric position, read off **the curve the renderer actually walks** —
    /// `StrokePath`, the interpolant through the stored points — falling back to the neighbouring
    /// sample's tangent where the derivative vanishes (a stationary finger emits coincident samples).
    ///
    /// It used to be the direction of the chord the position falls inside, and that stopped being
    /// what the renderer walks when the stored path became a refit at a fixed tolerance: the chord is
    /// a step function of the parameter, so the eraser's cross-section swung by the whole turn angle
    /// as a probe crossed a stored point. Reading the curve makes the normal continuous, which is
    /// what a cross-section wants.
    ///
    /// Evaluated through `StrokePath`'s statics rather than by building one, because this runs once
    /// per coverage probe and a probe walk is hundreds of them.
    static func tangent(atParameter parameter: CGFloat, in samples: [VectorSample]) -> CGPoint {
        guard samples.count > 1 else { return CGPoint(x: 1, y: 0) }
        let domainEnd = CGFloat(samples.count - 1)
        let clamped = min(max(parameter, 0), domainEnd)
        let index = min(Int(clamped.rounded(.down)), samples.count - 2)
        let (m1, m2) = StrokePath.tangents(segment: index, count: samples.count) { samples[$0].point }
        let derivative = StrokePath.hermiteDerivative(p1: samples[index].point,
                                                      p2: samples[index + 1].point,
                                                      m1: m1, m2: m2, u: clamped - CGFloat(index))
        if let unit = normalized(derivative) { return unit }
        return tangent(ofSampleAt: index, in: samples)
    }

    /// `parameter` moved `distance` along the polyline — forward for positive, backward for negative —
    /// clamped to the run's domain.
    ///
    /// The parametric domain is "sample index + fraction", which is *not* proportional to arclength
    /// when samples are unevenly spaced, so Mode 1 cannot place a cut boundary "half a stroke-width
    /// further out" by adding a constant to a parameter. This is the conversion. It walks rather than
    /// building a cumulative-length table because it runs a couple of times per cut boundary, not once
    /// per probe.
    static func offsetParameter(_ parameter: CGFloat, by distance: CGFloat,
                                in samples: [VectorSample]) -> CGFloat {
        guard samples.count > 1 else { return 0 }
        let domainEnd = CGFloat(samples.count - 1)
        var position = min(max(parameter, 0), domainEnd)
        var remaining = abs(distance)
        guard remaining > epsilon else { return position }
        let forward = distance > 0

        while remaining > epsilon {
            if forward {
                guard position < domainEnd else { return domainEnd }
                let index = min(Int(position.rounded(.down)), samples.count - 2)
                let a = samples[index].point, b = samples[index + 1].point
                let length = hypot(b.x - a.x, b.y - a.y)
                let available = length * (CGFloat(index + 1) - position)
                if available > remaining {
                    return position + remaining / length
                }
                remaining -= available
                position = CGFloat(index + 1)
            } else {
                guard position > 0 else { return 0 }
                // `rounded(.up) - 1` rather than `rounded(.down)` so a position sitting exactly on a
                // sample walks back into the segment *before* it, not the one after.
                let index = min(max(Int(position.rounded(.up)) - 1, 0), samples.count - 2)
                let a = samples[index].point, b = samples[index + 1].point
                let length = hypot(b.x - a.x, b.y - a.y)
                let available = length * (position - CGFloat(index))
                if available > remaining {
                    return position - remaining / length
                }
                remaining -= available
                position = CGFloat(index)
            }
        }
        return position
    }

    /// Unit tangent at `samples[index]`: a central difference in the interior, a forward/backward
    /// difference at the ends, and the nearest non-coincident neighbour when the immediate one
    /// duplicates the sample (a stationary finger emits repeats, and a zero tangent would collapse
    /// the cross-section to a point).
    ///
    /// A single-sample run — or a run of nothing but coincident samples — has no tangent at all. It
    /// gets `(1, 0)`: for a round dab every cross-section direction is equivalent, so *any* fixed
    /// choice is exact rather than merely acceptable.
    static func tangent(ofSampleAt index: Int, in samples: [VectorSample]) -> CGPoint {
        guard samples.count > 1, samples.indices.contains(index) else { return CGPoint(x: 1, y: 0) }
        let here = samples[index].point
        // Walk outward for a distinct neighbour on each side, so repeated samples don't zero the
        // difference. Interior samples prefer the central difference (both sides found).
        var before: CGPoint?
        var i = index - 1
        while i >= 0 {
            if !isNearlyEqual(samples[i].point, here) { before = samples[i].point; break }
            i -= 1
        }
        var after: CGPoint?
        var j = index + 1
        while j < samples.count {
            if !isNearlyEqual(samples[j].point, here) { after = samples[j].point; break }
            j += 1
        }
        let from = before ?? here
        let to = after ?? here
        return normalized(CGPoint(x: to.x - from.x, y: to.y - from.y)) ?? CGPoint(x: 1, y: 0)
    }

    /// Unit normal at `samples[index]` — the direction the stroke's cross-section runs in.
    static func normal(ofSampleAt index: Int, in samples: [VectorSample]) -> CGPoint {
        let t = tangent(ofSampleAt: index, in: samples)
        return CGPoint(x: -t.y, y: t.x)
    }

    // MARK: - Polyline intersection

    /// A crossing between two polylines: where it is, and where along each polyline it falls, in the
    /// "sample index + fraction" convention.
    struct Intersection: Equatable {
        var parameterOnA: CGFloat
        var parameterOnB: CGFloat
        var point: CGPoint
        /// How far along `a` the contact extends — `parameterOnA...parameterOnA` for a crossing, which
        /// happens at a point, and a wider range only when the two polylines run *parallel* over a
        /// stretch and every position in it is equally close.
        ///
        /// A cut has to stop somewhere definite, and for a parallel overlap "the closest approach" is
        /// not a place — `closestApproach` picks an arbitrary end of the tied interval and there is no
        /// principled reason to prefer it. `VectorEraser.cutToIntersection` reads the end of this span
        /// nearest the eraser instead, which makes a cut stop where the two lines part company rather
        /// than eating the whole shared run.
        var span: ClosedRange<CGFloat>

        init(parameterOnA: CGFloat, parameterOnB: CGFloat, point: CGPoint,
             span: ClosedRange<CGFloat>? = nil) {
            self.parameterOnA = parameterOnA
            self.parameterOnB = parameterOnB
            self.point = point
            self.span = span ?? parameterOnA...parameterOnA
        }
    }

    /// Segment-segment crossing, or nil when the segments are parallel or miss each other.
    ///
    /// Bounds are inclusive, so a T-junction — one stroke ending exactly on another — is reported,
    /// with the parameter landing on the touching endpoint. Collinear overlap is deliberately *not*
    /// reported: an overlap is a shared interval rather than a point, and Mode 3 needs a point to cut
    /// at. Two strokes drawn along each other are a near-approach case, which the tolerant variant
    /// below covers with a well-defined answer.
    static func segmentIntersection(_ a0: CGPoint, _ a1: CGPoint, _ b0: CGPoint, _ b1: CGPoint)
        -> (t: CGFloat, u: CGFloat, point: CGPoint)? {
        let rx = a1.x - a0.x, ry = a1.y - a0.y
        let sx = b1.x - b0.x, sy = b1.y - b0.y
        let denominator = rx * sy - ry * sx
        guard abs(denominator) > epsilon else { return nil }
        let qx = b0.x - a0.x, qy = b0.y - a0.y
        let t = (qx * sy - qy * sx) / denominator
        let u = (qx * ry - qy * rx) / denominator
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return (t, u, CGPoint(x: a0.x + rx * t, y: a0.y + ry * t))
    }

    /// Closest approach between two segments: the parameter on each, the squared distance, and the
    /// midpoint of the closest pair.
    ///
    /// For two segments that do not cross, the closest pair always involves at least one endpoint, so
    /// projecting all four endpoints onto the opposite segment is exact — no optimisation needed.
    /// Crossing segments are reported at their crossing with distance zero.
    static func closestApproach(betweenSegment a0: CGPoint, _ a1: CGPoint,
                                andSegment b0: CGPoint, _ b1: CGPoint)
        -> (t: CGFloat, u: CGFloat, distanceSquared: CGFloat, midpoint: CGPoint) {
        if let hit = segmentIntersection(a0, a1, b0, b1) {
            return (hit.t, hit.u, 0, hit.point)
        }
        var best = (t: CGFloat(0), u: CGFloat(0), distanceSquared: CGFloat.infinity, midpoint: a0)
        func consider(t: CGFloat, u: CGFloat, pointOnA: CGPoint, pointOnB: CGPoint, distanceSquared: CGFloat) {
            guard distanceSquared < best.distanceSquared else { return }
            best = (t, u, distanceSquared,
                    CGPoint(x: (pointOnA.x + pointOnB.x) / 2, y: (pointOnA.y + pointOnB.y) / 2))
        }
        let a0OnB = closestPointOnSegment(from: a0, a: b0, b: b1)
        consider(t: 0, u: a0OnB.t, pointOnA: a0, pointOnB: a0OnB.point, distanceSquared: a0OnB.distanceSquared)
        let a1OnB = closestPointOnSegment(from: a1, a: b0, b: b1)
        consider(t: 1, u: a1OnB.t, pointOnA: a1, pointOnB: a1OnB.point, distanceSquared: a1OnB.distanceSquared)
        let b0OnA = closestPointOnSegment(from: b0, a: a0, b: a1)
        consider(t: b0OnA.t, u: 0, pointOnA: b0OnA.point, pointOnB: b0, distanceSquared: b0OnA.distanceSquared)
        let b1OnA = closestPointOnSegment(from: b1, a: a0, b: a1)
        consider(t: b1OnA.t, u: 1, pointOnA: b1OnA.point, pointOnB: b1, distanceSquared: b1OnA.distanceSquared)
        return best
    }

    /// Every exact crossing of the two polylines, in ascending `parameterOnA` order.
    ///
    /// Centerline-exact: two strokes whose *ink* overlaps but whose centerlines miss are not reported.
    /// Use `intersections(between:and:tolerance:)` for the width-aware behaviour Mode 3 wants.
    static func intersections(between a: [CGPoint], and b: [CGPoint]) -> [Intersection] {
        guard a.count > 1, b.count > 1 else { return [] }
        var result: [Intersection] = []
        for i in 0..<(a.count - 1) {
            for j in 0..<(b.count - 1) {
                guard let hit = segmentIntersection(a[i], a[i + 1], b[j], b[j + 1]) else { continue }
                result.append(Intersection(parameterOnA: CGFloat(i) + hit.t,
                                           parameterOnB: CGFloat(j) + hit.u,
                                           point: hit.point))
            }
        }
        result.sort { $0.parameterOnA < $1.parameterOnA }
        return result
    }

    /// Exact crossings, plus one entry per *contact region* — a continuous stretch of `a` that runs
    /// within `tolerance` of `b` without crossing it — placed at that stretch's closest approach.
    ///
    /// Mode 3 needs this because "erase up to intersection" is width-aware in Clip Studio: two lines
    /// whose strokes visibly touch read as crossed to the user even when the centerlines miss by a
    /// point or two. The caller supplies `tolerance` as the sum of the two strokes' half-widths.
    ///
    /// **A region is a stretch of `a`, not a run of similar parameters, and that is the whole design.**
    /// The previous implementation grouped candidates by "within one *sample index* on both polylines",
    /// and dropped candidates within one sample index of an exact crossing. Sample index is not a
    /// distance: a real stroke is sampled every point or two, while `tolerance` is the sum of two brush
    /// half-widths — 10 to 20 points. So a genuine crossing came surrounded by a disk of near-contacts
    /// tens of samples wide, the ±1-index shadow test excluded almost none of them, and the ±1-index
    /// chain broke every time the fan of qualifying `parameterOnB` values jumped, leaving one
    /// "cluster" per sample. `VectorEraser.cutToIntersection` brackets the touch with the *nearest*
    /// obstacle on each side, so it picked the near edge of that disk and the erase stopped short of
    /// the crossing by `tolerance / sin(angle)` — the stub the owner reported on 2026-08-18, which at a
    /// shallow crossing ran to 29 points. Measured, before/after, in `VectorEraserLogicTests`'
    /// `…LandsExactlyOnTheCrossing` tests.
    ///
    /// Grouping over contact along `a` instead is unit-correct and density-independent: every segment
    /// of `a` with any qualifying partner joins a region, touching regions merge, and then
    ///
    /// * a region holding one or more exact crossings reports **those crossings and nothing else** —
    ///   the crossings already say where the two lines meet, to full precision;
    /// * a region with none reports its single closest approach, plus the `span` of positions tied for
    ///   that distance (a point unless the lines run parallel).
    ///
    /// Every exact crossing is inside some region (its own segment pair is at distance zero, so it
    /// always qualifies), which is what keeps the guarantee that the tolerant answer is a superset of
    /// the exact one.
    static func intersections(between a: [CGPoint], and b: [CGPoint], tolerance: CGFloat) -> [Intersection] {
        let exact = intersections(between: a, and: b)
        guard tolerance > 0, a.count > 1, b.count > 1 else { return exact }
        let toleranceSquared = tolerance * tolerance

        // One entry per segment of `a` that comes within tolerance of anything: its closest approach,
        // and how far along that segment the contact holds at that distance. Distance-zero pairs are
        // kept — a crossing's own segment is what anchors the region it sits in.
        var contacts: [(segment: Int, hit: Intersection, distanceSquared: CGFloat)] = []
        for i in 0..<(a.count - 1) {
            var best: (hit: Intersection, distanceSquared: CGFloat)?
            for j in 0..<(b.count - 1) {
                let approach = closestApproach(betweenSegment: a[i], a[i + 1], andSegment: b[j], b[j + 1])
                guard approach.distanceSquared <= toleranceSquared else { continue }
                // The tied stretch on this segment. Only a parallel pair has one wider than a point:
                // the four ends of the two segments are the only places a tie can start or stop, so
                // widening to whichever of them is also at the approach distance is exact.
                var low = CGFloat(i) + approach.t, high = low
                func widen(to parameter: CGFloat) {
                    low = min(low, parameter)
                    high = max(high, parameter)
                }
                if distanceSquared(from: a[i], toSegment: b[j], b[j + 1]) <= approach.distanceSquared + epsilon {
                    widen(to: CGFloat(i))
                }
                if distanceSquared(from: a[i + 1], toSegment: b[j], b[j + 1]) <= approach.distanceSquared + epsilon {
                    widen(to: CGFloat(i + 1))
                }
                for end in [b[j], b[j + 1]] {
                    let foot = closestPointOnSegment(from: end, a: a[i], b: a[i + 1])
                    if foot.distanceSquared <= approach.distanceSquared + epsilon {
                        widen(to: CGFloat(i) + foot.t)
                    }
                }
                let hit = Intersection(parameterOnA: CGFloat(i) + approach.t,
                                       parameterOnB: CGFloat(j) + approach.u,
                                       point: approach.midpoint, span: low...high)
                guard let current = best else { best = (hit, approach.distanceSquared); continue }
                if approach.distanceSquared < current.distanceSquared - epsilon {
                    best = (hit, approach.distanceSquared)
                } else if approach.distanceSquared <= current.distanceSquared + epsilon {
                    // Equally close to two segments of `b` — one contact, spanning both.
                    best?.hit.span = min(current.hit.span.lowerBound, low)...max(current.hit.span.upperBound, high)
                }
            }
            if let best { contacts.append((i, best.hit, best.distanceSquared)) }
        }
        guard !contacts.isEmpty else { return exact }

        var result = exact
        var start = 0
        while start < contacts.count {
            var end = start
            while end + 1 < contacts.count, contacts[end + 1].segment == contacts[end].segment + 1 { end += 1 }
            defer { start = end + 1 }
            let region = contacts[start...end]
            // Region bounds in `a`'s parameter space: the first segment's start to the last one's end.
            let regionLow = CGFloat(contacts[start].segment)
            let regionHigh = CGFloat(contacts[end].segment + 1)
            guard !exact.contains(where: { $0.parameterOnA >= regionLow - epsilon
                                        && $0.parameterOnA <= regionHigh + epsilon }) else { continue }
            var closest = CGFloat.greatestFiniteMagnitude
            for member in region { closest = min(closest, member.distanceSquared) }
            var representative: Intersection?
            for member in region where member.distanceSquared <= closest + epsilon {
                guard var found = representative else { representative = member.hit; continue }
                let low = min(found.span.lowerBound, member.hit.span.lowerBound)
                let high = max(found.span.upperBound, member.hit.span.upperBound)
                found.span = low...high
                representative = found
            }
            if let representative { result.append(representative) }
        }
        result.sort { $0.parameterOnA < $1.parameterOnA }
        return result
    }

    // MARK: - Sample interpolation and subdivision

    /// The sample at parametric position `parameter` (see the type comment), with **pressure
    /// interpolated as well as position**.
    ///
    /// Pressure is the whole point: a cut boundary inherits the width the stroke actually had there,
    /// so the piece that survives ends at the same thickness it was mid-stroke instead of snapping to
    /// the nearest stored sample's pressure and visibly stepping. `parameter` is clamped to the run's
    /// domain, so an out-of-range value returns the nearest endpoint rather than nil.
    static func interpolatedSample(in samples: [VectorSample], at parameter: CGFloat) -> VectorSample? {
        guard let first = samples.first, let last = samples.last else { return nil }
        guard parameter > 0 else { return first }
        guard parameter < CGFloat(samples.count - 1) else { return last }
        let index = Int(parameter.rounded(.down))
        let fraction = parameter - CGFloat(index)
        return lerp(samples[index], samples[index + 1], fraction)
    }

    /// `samples` with extra samples inserted so no two consecutive ones are farther apart than
    /// `maxSpacing`, interpolating position and pressure. Original samples are preserved exactly.
    ///
    /// Mode 2's third defect: a coarse stroke (fast flick, samples 40pt apart) erased with a small
    /// nib either over- or under-erases, because the nearest *sample* to the eraser can sit well
    /// outside its footprint. Densifying to the eraser's radius first makes sample-granularity
    /// decisions land within a radius of the truth.
    static func subdivided(_ samples: [VectorSample], maxSpacing: CGFloat) -> [VectorSample] {
        guard samples.count > 1, maxSpacing > 0 else { return samples }
        var result: [VectorSample] = []
        result.reserveCapacity(samples.count)
        result.append(samples[0])
        for i in 1..<samples.count {
            let from = samples[i - 1], to = samples[i]
            let distance = hypot(to.x - from.x, to.y - from.y)
            if distance > maxSpacing {
                let steps = Int((distance / maxSpacing).rounded(.up))
                for step in 1..<steps {
                    result.append(lerp(from, to, CGFloat(step) / CGFloat(steps)))
                }
            }
            result.append(to)
        }
        return result
    }

    // MARK: - Splitting

    /// Removes the parametric spans in `cuts` from `samples` and returns the surviving runs, in order
    /// — the one implementation of "delete spans and emit the pieces" that all three eraser modes
    /// share.
    ///
    /// ## Contract
    ///
    /// - `cuts` are closed ranges in the "sample index + fraction" domain (see the type comment).
    ///   They may overlap, be unsorted, and extend outside `0...(count - 1)`; they are clamped,
    ///   sorted and merged first, so callers can just append a range per touch sample.
    /// - Each surviving run gets **exact interpolated boundary samples** at both of its cut edges.
    ///   This is what makes a cut land where the eraser's edge actually was instead of at the nearest
    ///   stored sample — today's `VectorCanvas.erase` drops whole samples, which is why its cuts look
    ///   ragged and don't follow the eraser.
    /// - A run's boundary that is *not* a cut edge (the stroke's own start or end) keeps the original
    ///   sample untouched, bit for bit.
    /// - Runs of one sample are kept: a lone dab is legitimate ink, and today's `erase` keeps
    ///   `run.count >= 1`. Empty runs are dropped. A cut spanning the whole domain therefore returns
    ///   `[]`, which the caller reads as "this stroke is gone".
    /// - A single-sample input run has the degenerate domain `0...0`: any cut containing `0` removes
    ///   it entirely, and anything else leaves it alone.
    /// - No cuts, or only cuts that miss the domain, returns `[samples]` unchanged — so a caller can
    ///   compare identity cheaply and skip the mutation.
    ///
    /// If point decimation is ever added, it must not move these boundary samples, or the cut edge
    /// drifts away from where the user erased.
    static func splitStroke(_ samples: [VectorSample], removing cuts: [ClosedRange<CGFloat>]) -> [[VectorSample]] {
        splitStrokeRuns(samples, removing: cuts).map(\.samples)
    }

    /// One surviving piece of a split: its samples, and where each of them sits in the **input's**
    /// parametric domain.
    ///
    /// The parameters are what lets a piece keep rendering on the original's dab lattice instead of
    /// starting its own — see `DabLattice`, which stores exactly this alongside the parent's samples.
    /// They are free here and unrecoverable afterwards: a boundary sample is interpolated at a
    /// fractional parameter, and nothing about the resulting point says where it came from once the run
    /// has been handed back on its own.
    typealias SplitRun = (samples: [VectorSample], parameters: [CGFloat])

    /// `splitStroke`, reporting each run's source parameters as well as its samples. Same walk, same
    /// edge cases; `splitStroke` is this with the parameters dropped.
    static func splitStrokeRuns(_ samples: [VectorSample],
                                removing cuts: [ClosedRange<CGFloat>]) -> [SplitRun] {
        guard !samples.isEmpty else { return [] }
        let domainEnd = CGFloat(samples.count - 1)
        let merged = mergedCuts(cuts, clampedTo: 0...domainEnd)
        guard !merged.isEmpty else { return [(samples, identityParameters(count: samples.count))] }

        // A single sample has no extent to survive inside, so the only question is whether it was hit.
        guard samples.count > 1 else {
            return merged.contains { $0.lowerBound <= 0 && $0.upperBound >= 0 } ? [] : [(samples, [0])]
        }

        var runs: [SplitRun] = []
        var cursor: CGFloat = 0
        for cut in merged {
            appendRun(from: cursor, to: cut.lowerBound, of: samples, into: &runs)
            cursor = cut.upperBound
        }
        appendRun(from: cursor, to: domainEnd, of: samples, into: &runs)
        return runs
    }

    private static func identityParameters(count: Int) -> [CGFloat] {
        (0..<count).map(CGFloat.init)
    }

    /// Emits the samples of the surviving span `low...high` — boundaries interpolated, interior
    /// samples copied verbatim — with the parameter each one came from.
    ///
    /// Spans thinner than `epsilon` are dropped rather than emitted as a lone dab: they arise only
    /// where two cuts meet, where the "survivor" is a rounding artefact of the cut edges rather than
    /// ink the user left behind, and emitting one would stamp a visible dab in the middle of the hole
    /// they just erased.
    private static func appendRun(from low: CGFloat, to high: CGFloat, of samples: [VectorSample],
                                  into runs: inout [SplitRun]) {
        guard high - low > epsilon else { return }
        var run: [VectorSample] = []
        var parameters: [CGFloat] = []
        // Interior integer indices, plus the two interpolated ends.
        let firstInterior = Int(low.rounded(.down)) + 1
        let lastInterior = Int(high.rounded(.up)) - 1
        run.reserveCapacity(max(lastInterior - firstInterior + 1, 0) + 2)
        parameters.reserveCapacity(run.capacity)
        if let start = interpolatedSample(in: samples, at: low) { run.append(start); parameters.append(low) }
        if firstInterior <= lastInterior {
            for i in firstInterior...lastInterior where CGFloat(i) > low && CGFloat(i) < high {
                run.append(samples[i])
                parameters.append(CGFloat(i))
            }
        }
        if let end = interpolatedSample(in: samples, at: high) { run.append(end); parameters.append(high) }
        if !run.isEmpty { runs.append((run, parameters)) }
    }

    /// Splits `samples` into the maximal runs where `inside` holds — used to stop a selection clip
    /// from **bridging** a stroke that exits the selection and re-enters it. Filtering to a single
    /// array of the surviving samples (the naive fix) still draws one continuous line through them,
    /// because nothing in a `VectorStroke` records that two consecutive stored samples used to have
    /// excluded ones between them — the renderer just connects whatever is there. Splitting into
    /// separate runs, one stroke per run, is what actually produces two disconnected pieces.
    ///
    /// Each crossing is landed with one bisection rather than at sample granularity, so the cut sits
    /// close to the selection edge instead of jumping to the nearest stored sample. This is cheaper
    /// than `VectorEraser`'s probe-and-bisect walk (`coveredSpans`): a selection membership test is
    /// one boolean per point, not a footprint that needs stepped sampling to catch every entry/exit
    /// along a segment, so a single bisection per sign change is exact as long as a segment crosses
    /// the boundary once — true in the common case, since samples are already spaced at
    /// `BrushStamper`'s recording spacing. A segment that clips a thin sliver of a concave selection
    /// twice between two samples is not caught; that is the trade-off against the raster path's
    /// pixel-exact `PixelOps.maskedComposite`, accepted because vector geometry has no per-pixel mask
    /// to composite against.
    ///
    /// Runs of a single sample are kept, same as `splitStroke`: a lone dab inside the selection is
    /// legitimate ink. An empty `samples` returns `[]`.
    static func splitRuns(_ samples: [VectorSample], inside: (CGPoint) -> Bool) -> [[VectorSample]] {
        membershipRuns(samples, inside: inside).filter(\.isInside).map(\.samples)
    }

    /// One maximal run of a membership walk: its samples, where each sits in the **input's**
    /// parametric domain, and which side of the predicate the whole run is on.
    ///
    /// `SplitRun` plus the side, and the side is the point: the lasso move needs the half that stays
    /// behind as much as the half that travels, and paying for two walks would mean evaluating the
    /// containment test twice *and* landing each crossing twice — two bisections of the same segment
    /// that are only equal to within their own tolerance, so the two halves would not share a cut
    /// point and a zero-distance move would not be lossless.
    typealias MembershipRun = (samples: [VectorSample], parameters: [CGFloat], isInside: Bool)

    /// `samples` partitioned into the maximal runs where `inside` holds and the maximal runs where it
    /// does not, **from one walk**, in order, alternating.
    ///
    /// Every crossing is landed once, by `bisectCrossing`, and the resulting boundary sample is
    /// emitted as the *last* sample of the closing run and the *first* sample of the opening one —
    /// bit for bit the same value, at bit for bit the same parameter. That shared boundary is what
    /// makes the split conserve ink: rejoin the two runs and you have the original polyline back.
    ///
    /// `splitRuns` is this filtered to the inside runs, so the shipped live-selection clip and the
    /// lasso move take the same walk and can never disagree about where a stroke leaves a loop.
    ///
    /// Runs of a single sample are kept, same as `splitStroke`: a lone dab inside the selection is
    /// legitimate ink. An empty `samples` returns `[]`; a single sample returns one run.
    static func membershipRuns(_ samples: [VectorSample], inside: (CGPoint) -> Bool) -> [MembershipRun] {
        guard !samples.isEmpty else { return [] }
        guard samples.count > 1 else {
            return [(samples, [0], inside(samples[0].point))]
        }
        var runs: [MembershipRun] = []
        var current: [VectorSample] = [samples[0]]
        var currentParameters: [CGFloat] = [0]
        var previousInside = inside(samples[0].point)
        for i in 1..<samples.count {
            let a = samples[i - 1], b = samples[i]
            let bInside = inside(b.point)
            if bInside != previousInside {
                let crossing = bisectCrossing(from: a, aInside: previousInside, to: b, inside: inside)
                let parameter = CGFloat(i - 1) + crossing.t
                current.append(crossing.sample)
                currentParameters.append(parameter)
                runs.append((current, currentParameters, previousInside))
                current = [crossing.sample]
                currentParameters = [parameter]
            }
            current.append(b)
            currentParameters.append(CGFloat(i))
            previousInside = bInside
        }
        runs.append((current, currentParameters, previousInside))
        return runs
    }

    /// Binary-searches the segment `from`→`to` for the parametric `t` where `inside` flips, assuming
    /// (as `membershipRuns` does) that it flips exactly once. 40 iterations halves the segment down to
    /// a fraction of ~9e-13 of its length — with 20 (the first cut of this) a 10pt segment measured
    /// `testSplitRunsWithMultipleGapsYieldsARunPerSurvivingSpan` off by ~5e-6, comfortably past a
    /// canvas pixel and well past `assertXs`'s tolerance; 40 iterations costs nothing extra worth
    /// naming (it's a fixed unrolled loop, no allocation) and leaves headroom `CGFloat` itself can't
    /// resolve.
    ///
    /// Returns `t` as well as the sample, because a piece that is to keep drawing on its parent's dab
    /// lattice needs to say where in the parent's walk it came from, and a fractional crossing is
    /// unrecoverable from the interpolated point alone.
    private static func bisectCrossing(from: VectorSample, aInside: Bool, to: VectorSample,
                                       inside: (CGPoint) -> Bool) -> (sample: VectorSample, t: CGFloat) {
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<40 {
            let mid = (low + high) / 2
            let point = lerp(from, to, mid).point
            if inside(point) == aInside { low = mid } else { high = mid }
        }
        let t = (low + high) / 2
        return (lerp(from, to, t), t)
    }

    /// `cuts` clamped to `domain`, sorted, and merged where they overlap or abut — so the split walk
    /// below can assume a disjoint ascending list.
    static func mergedCuts(_ cuts: [ClosedRange<CGFloat>],
                           clampedTo domain: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        var clamped: [ClosedRange<CGFloat>] = []
        clamped.reserveCapacity(cuts.count)
        for cut in cuts {
            let low = max(cut.lowerBound, domain.lowerBound)
            let high = min(cut.upperBound, domain.upperBound)
            guard high >= low else { continue }
            clamped.append(low...high)
        }
        guard clamped.count > 1 else { return clamped }
        clamped.sort { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<CGFloat>] = [clamped[0]]
        for cut in clamped.dropFirst() {
            let last = merged[merged.count - 1]
            if cut.lowerBound <= last.upperBound {
                if cut.upperBound > last.upperBound { merged[merged.count - 1] = last.lowerBound...cut.upperBound }
            } else {
                merged.append(cut)
            }
        }
        return merged
    }

    // MARK: - Small helpers

    /// Linear blend of two samples — position **and** pressure.
    /// What `spans` leaves out of `domain` — merged, clamped, and in ascending order.
    ///
    /// Mode 1's residue trimming has the spans it wants to **keep** (where the eraser still has
    /// something beneath it) and `splitStroke` takes the spans to **remove**, so this is the bridge
    /// between them. Same shape as `mergedCuts`, from the other side.
    static func complementOfSpans(_ spans: [ClosedRange<CGFloat>],
                                  over domain: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        let merged = mergedCuts(spans, clampedTo: domain)
        guard !merged.isEmpty else { return [domain] }
        var result: [ClosedRange<CGFloat>] = []
        var cursor = domain.lowerBound
        for span in merged {
            if span.lowerBound > cursor { result.append(cursor...span.lowerBound) }
            cursor = max(cursor, span.upperBound)
        }
        if cursor < domain.upperBound { result.append(cursor...domain.upperBound) }
        return result
    }

    static func lerp(_ from: VectorSample, _ to: VectorSample, _ t: CGFloat) -> VectorSample {
        VectorSample(x: from.x + (to.x - from.x) * t,
                     y: from.y + (to.y - from.y) * t,
                     pressure: from.pressure + (to.pressure - from.pressure) * t)
    }

    /// `v` scaled to unit length, or nil if it has no direction to speak of.
    static func normalized(_ v: CGPoint) -> CGPoint? {
        let length = hypot(v.x, v.y)
        guard length > epsilon else { return nil }
        return CGPoint(x: v.x / length, y: v.y / length)
    }

    private static func isNearlyEqual(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) <= epsilon && abs(a.y - b.y) <= epsilon
    }

    /// Real roots of `a·t² + 2·halfB·t + c`, in the half-`b` form the coverage maths naturally
    /// produces. Degenerates to the linear case when `a` vanishes, which is exactly what happens for
    /// a constant-radius capsule perpendicular to the cross-section — the most common input there is.
    static func quadraticRoots(a: CGFloat, halfB: CGFloat, c: CGFloat) -> (CGFloat?, CGFloat?) {
        guard abs(a) > epsilon else {
            guard abs(halfB) > epsilon else { return (nil, nil) }
            return (-c / (2 * halfB), nil)
        }
        let discriminant = halfB * halfB - a * c
        guard discriminant >= 0 else { return (nil, nil) }
        let root = sqrt(discriminant)
        return ((-halfB + root) / a, (-halfB - root) / a)
    }
}
