import CoreGraphics
import Foundation

/// The geometry half of the vector eraser: given an eraser gesture and one stroke, which parametric
/// spans of that stroke does the gesture remove?
///
/// Split out of `VectorCanvas` deliberately. `VectorCanvas` owns a lock, a render cache and a display
/// list; this owns none of those and touches no reference type, so — like `StrokeGeometry` and
/// `ShapeGeometry` before it — it compiles a second time straight into `PaintSoftwareUITests` and
/// every decision below is testable headlessly instead of only through a simulator gesture.
/// `VectorCanvas.erase` is then a thin adapter: map into local space, ask the spatial index which
/// strokes are candidates, call in here, splice the results back.
///
/// Modes 1 and 2 live here. Mode 3 (`cutToIntersection`) needs the *other* strokes on the layer, not
/// just the one being cut, so it takes them as an explicit parameter rather than reaching for a
/// canvas — same rule, one more argument.
///
/// See VECTOR_ERASER_PLAN.md §4.
enum VectorEraser {

    /// One eraser gesture, resolved into the target canvas's **local** (pre-`transform`) space and
    /// reduced to the capsule chain its dabs sweep out.
    ///
    /// Built once per erase and reused across every candidate stroke: the chain, its bounding box and
    /// the probe step are all properties of the *gesture*, and recomputing them per stroke was a
    /// meaningful slice of the old implementation's cost on a dense layer.
    struct Sweep {
        let capsules: [StrokeGeometry.Capsule]
        /// Union of the chain's bounding boxes. Doubles as the spatial-index query rect and as the
        /// cheap reject in `contains(_:)`.
        let bounds: CGRect
        /// How far apart to place inside/outside probes when walking a stroke through this sweep.
        ///
        /// Set to the *smallest* radius anywhere along the chain. A stroke centreline crossing the
        /// sweep square-on has a chord of at least twice the local radius, so a step of one radius
        /// cannot straddle the crossing and miss it. `StrokeGeometry.stampRadius` floors at `0.25`
        /// (mirroring `BrushStamper`'s half-point diameter floor), so this is always positive and the
        /// probe walk always terminates.
        let probeStep: CGFloat
        let mode: VectorEraserMode

        /// Nil when the gesture has no footprint at all (no samples) — the caller reads that as
        /// "nothing to erase" and skips the whole traversal.
        init?(samples: [VectorSample], brush: Brush, size: CGFloat, mode: VectorEraserMode) {
            let capsules = StrokeGeometry.capsuleChain(samples: samples, brush: brush, size: size)
            guard let bounds = StrokeGeometry.bounds(of: capsules) else { return nil }
            var smallest = CGFloat.greatestFiniteMagnitude
            for capsule in capsules { smallest = min(smallest, min(capsule.ra, capsule.rb)) }
            self.capsules = capsules
            self.bounds = bounds
            self.probeStep = max(smallest, StrokeGeometry.epsilon)
            self.mode = mode
        }

        /// Whether `point` lies under the eraser's footprint.
        ///
        /// This is the test that replaces the old implementation's *first* defect. That one measured
        /// each stroke sample against each raw eraser **touch point**, so a small nib dragged between
        /// two coarsely-sampled touches erased nothing at all in the gap — the two endpoints were the
        /// only places it existed. A capsule chain is the swept region, continuous by construction.
        func contains(_ point: CGPoint) -> Bool {
            guard bounds.contains(point) else { return false }
            for capsule in capsules where capsule.contains(point) { return true }
            return false
        }
    }

    // MARK: - Modes 1 and 2 — cut what the footprint covers

    /// The parametric spans of `samples` that `sweep` removes, in `StrokeGeometry`'s
    /// "sample index + fraction" domain and ready to hand to `StrokeGeometry.splitStroke`.
    ///
    /// ## Why probing rather than `StrokeGeometry.subdivided`
    ///
    /// The plan (§4, Mode 2's third defect) called for densifying a coarse stroke to the eraser's
    /// radius before deciding anything, so a sample-granularity verdict lands within a radius of the
    /// truth. Densifying the *stored* samples achieves that but has two costs: the surviving pieces
    /// inherit every inserted sample, permanently inflating the file for a stroke that was cut once,
    /// and the parametric domain shifts, so cut positions have to be mapped back before they mean
    /// anything to the original.
    ///
    /// Walking probes along each original segment gets the same resolution with neither. The probes
    /// are transient, so nothing is inserted; the parameters come out in the original domain, so
    /// nothing is mapped back; and the boundary is then bisected to well under a pixel instead of
    /// landing on the nearest inserted sample. It is exact for the same reason the split is:
    /// `BrushStamper` walks a straight line between consecutive samples, so a position interpolated
    /// linearly along a segment is precisely where the renderer put ink.
    ///
    /// `StrokeGeometry.subdivided` stays as it is — liquify wants real densification, because there
    /// the extra samples are the deformation's degrees of freedom rather than scratch work.
    static func cutRanges(in samples: [VectorSample], sweep: Sweep) -> [ClosedRange<CGFloat>] {
        guard !samples.isEmpty else { return [] }
        // A lone dab has the degenerate domain `0...0`: it is either hit or it isn't.
        guard samples.count > 1 else {
            return sweep.contains(samples[0].point) ? [0...0] : []
        }

        var ranges: [ClosedRange<CGFloat>] = []
        for i in 0..<(samples.count - 1) {
            let a = samples[i].point, b = samples[i + 1].point
            // Only the stretch of this segment that reaches the sweep's box can be inside the sweep,
            // and outside the box `contains` is a guaranteed miss. Clipping first is what keeps a
            // small nib on a long stroke from probing thousands of positions that cannot match.
            guard let (clipLow, clipHigh) = clipParameters(of: a, b, to: sweep.bounds) else { continue }
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > StrokeGeometry.epsilon else {
                // Repeated samples (a stationary finger emits them) have no extent to walk: every
                // parameter in `i...(i + 1)` maps to the same point, so the whole span is inside or
                // none of it is. Claiming the full span rather than the single point `i...i` is what
                // lets a cut spanning a stall abut its neighbours and merge into one range instead of
                // fragmenting the stroke into slivers around every duplicated sample.
                if sweep.contains(a) { ranges.append(CGFloat(i)...CGFloat(i + 1)) }
                continue
            }

            let span = clipHigh - clipLow
            let steps = max(Int((span * length / sweep.probeStep).rounded(.up)), 1)
            var previousT = clipLow
            var previousInside = sweep.contains(point(on: a, b, at: clipLow))
            // A run open at the clip's low end started at or before it — and before it is outside the
            // box, hence outside the sweep — so the clip boundary *is* the entry point.
            var runStart: CGFloat? = previousInside ? clipLow : nil

            for step in 1...steps {
                let t = clipLow + span * CGFloat(step) / CGFloat(steps)
                let inside = sweep.contains(point(on: a, b, at: t))
                if inside != previousInside {
                    let crossing = refineCrossing(on: a, b, sweep: sweep,
                                                  outside: inside ? previousT : t,
                                                  inside: inside ? t : previousT)
                    if inside {
                        runStart = crossing
                    } else if let start = runStart {
                        ranges.append((CGFloat(i) + start)...(CGFloat(i) + crossing))
                        runStart = nil
                    }
                }
                previousT = t
                previousInside = inside
            }
            // Still inside at the clip's high end: close the run there. If the sweep continues past
            // it, the next segment opens its own run at its own low clip and `mergedCuts` — which
            // merges abutting ranges — joins the two.
            if let start = runStart {
                ranges.append((CGFloat(i) + start)...(CGFloat(i) + clipHigh))
            }
        }
        return ranges
    }

    // MARK: - Mode 3 — cut to intersection

    /// Where a stroke is cut back to its neighbouring crossings: the span of `samples` between the
    /// two intersections with `others` that bracket `hit`, clamped to the stroke's own ends where
    /// there is no crossing on a side.
    ///
    /// Returns a single-element array so the result drops straight into `splitStroke(_:removing:)`
    /// alongside the other modes' output, and an empty array when the stroke should be left alone.
    ///
    /// A stroke with **no** crossings at all yields its entire domain, i.e. it is deleted whole. That
    /// is Clip Studio's third eraser mode (*erase whole line*) arriving for free rather than as its
    /// own code path — clamping both ends of "the span between the neighbouring crossings" when
    /// neither crossing exists is, correctly, the whole stroke.
    ///
    /// `tolerance` is width-aware on purpose: two strokes whose *ink* visibly touches read as crossed
    /// to the user even when the centrelines miss by a point or two. Callers pass the sum of the two
    /// strokes' half-widths; see `StrokeGeometry.intersections(between:and:tolerance:)`.
    static func cutToIntersection(in samples: [VectorSample], at hit: CGFloat,
                                  others: [(points: [CGPoint], tolerance: CGFloat)])
        -> [ClosedRange<CGFloat>] {
        guard samples.count > 1 else { return samples.isEmpty ? [] : [0...0] }
        let domainEnd = CGFloat(samples.count - 1)
        let points = samples.map(\.point)

        var low: CGFloat = 0
        var high = domainEnd
        for other in others {
            for crossing in StrokeGeometry.intersections(between: points, and: other.points,
                                                         tolerance: other.tolerance) {
                let p = crossing.parameterOnA
                // Strictly bracketing, so a crossing sitting exactly under the touch doesn't collapse
                // the span to nothing and silently erase none of it.
                if p < hit { low = max(low, p) } else if p > hit { high = min(high, p) }
            }
        }
        guard high > low else { return [] }
        return [low...high]
    }

    // MARK: - Helpers

    private static func point(on a: CGPoint, _ b: CGPoint, at t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// How many bisection steps to spend locating a cut edge. Each halves the interval, so 16 puts the
    /// boundary within `length / 65536` of the truth — well under a pixel for any segment a touch
    /// stream produces, and cheap: the bisection only runs once per crossing, not once per probe.
    private static let refinementSteps = 16

    /// The parameter where the sweep's edge crosses this segment, bracketed by a known-outside and a
    /// known-inside parameter.
    ///
    /// This is Mode 2's *second* defect: the old implementation deleted whole samples, so a cut
    /// landed wherever the input sampler happened to have put one and the erased edge was ragged and
    /// visibly lagging the eraser. Bisecting the actual footprint boundary — and letting
    /// `splitStroke` interpolate a real sample there, pressure included — is what makes the cut land
    /// where the user swept.
    private static func refineCrossing(on a: CGPoint, _ b: CGPoint, sweep: Sweep,
                                       outside: CGFloat, inside: CGFloat) -> CGFloat {
        var outside = outside, inside = inside
        for _ in 0..<refinementSteps {
            let mid = (outside + inside) / 2
            if sweep.contains(point(on: a, b, at: mid)) { inside = mid } else { outside = mid }
        }
        return inside
    }

    /// The sub-interval of `t ∈ 0...1` along `a`→`b` that lies within `rect`, or nil if the segment
    /// misses it entirely. Liang–Barsky, four slabs.
    ///
    /// A segment wholly inside returns `(0, 1)`; a zero-length one returns `(0, 1)` when its point is
    /// in the rect, which is the degenerate answer `cutRanges` wants (it has already special-cased the
    /// walk for that case).
    static func clipParameters(of a: CGPoint, _ b: CGPoint, to rect: CGRect) -> (CGFloat, CGFloat)? {
        var low: CGFloat = 0, high: CGFloat = 1
        let dx = b.x - a.x, dy = b.y - a.y
        let rect = rect.standardized

        func clip(_ direction: CGFloat, _ distance: CGFloat) -> Bool {
            if abs(direction) <= StrokeGeometry.epsilon {
                // Parallel to this slab: in or out for the whole segment, no parameter to narrow.
                return distance >= 0
            }
            let t = distance / direction
            if direction > 0 {
                if t < low { return false }
                if t < high { high = t }
            } else {
                if t > high { return false }
                if t > low { low = t }
            }
            return true
        }

        guard clip(-dx, a.x - rect.minX), clip(dx, rect.maxX - a.x),
              clip(-dy, a.y - rect.minY), clip(dy, rect.maxY - a.y) else { return nil }
        return low <= high ? (low, high) : nil
    }
}
