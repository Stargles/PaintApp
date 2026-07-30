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
        return coveredSpans(in: samples, clipTo: sweep.bounds, probeStep: sweep.probeStep) { parameter in
            guard let point = StrokeGeometry.interpolatedSample(in: samples, at: parameter)?.point else {
                return false
            }
            return sweep.contains(point)
        }
    }

    /// The probe-and-bisect walk both `cutRanges` and `cleanCutRanges` are built from: the maximal
    /// parametric spans of `samples` over which `predicate` holds, in the "sample index + fraction"
    /// domain.
    ///
    /// The two differ only in what "covered" means — centreline under the footprint for Mode 2, the
    /// stroke's whole width under it for Mode 1's clean-cut test — and getting the walk itself right
    /// (the clip, the stalled-finger case, closing a run at a segment boundary so `mergedCuts` can
    /// rejoin it) is the part that took the tests. One implementation, one set of edge cases.
    ///
    /// `rect` clips the walk: outside it the predicate is required to be false, which is what keeps a
    /// small nib on a long stroke from probing thousands of positions that cannot match. Callers whose
    /// predicate reaches beyond the eraser's own box — the clean-cut test does, by the stroke's
    /// half-width — must grow the rect to match.
    private static func coveredSpans(in samples: [VectorSample], clipTo rect: CGRect, probeStep: CGFloat,
                                     predicate: (CGFloat) -> Bool) -> [ClosedRange<CGFloat>] {
        guard !samples.isEmpty else { return [] }
        guard samples.count > 1 else { return predicate(0) ? [0...0] : [] }

        var ranges: [ClosedRange<CGFloat>] = []
        for i in 0..<(samples.count - 1) {
            let a = samples[i].point, b = samples[i + 1].point
            guard let (clipLow, clipHigh) = clipParameters(of: a, b, to: rect) else { continue }
            let base = CGFloat(i)
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > StrokeGeometry.epsilon else {
                // Repeated samples (a stationary finger emits them) have no extent to walk: every
                // parameter in `i...(i + 1)` maps to the same point, so the whole span is inside or
                // none of it is. Claiming the full span rather than the single point `i...i` is what
                // lets a cut spanning a stall abut its neighbours and merge into one range instead of
                // fragmenting the stroke into slivers around every duplicated sample.
                if predicate(base) { ranges.append(base...(base + 1)) }
                continue
            }

            let span = clipHigh - clipLow
            let steps = max(Int((span * length / probeStep).rounded(.up)), 1)
            var previousT = clipLow
            var previousInside = predicate(base + clipLow)
            // A run open at the clip's low end started at or before it — and before it is outside the
            // box, hence outside the sweep — so the clip boundary *is* the entry point.
            var runStart: CGFloat? = previousInside ? clipLow : nil

            for step in 1...steps {
                let t = clipLow + span * CGFloat(step) / CGFloat(steps)
                let inside = predicate(base + t)
                if inside != previousInside {
                    let crossing = refineCrossing(base: base,
                                                  outside: inside ? previousT : t,
                                                  inside: inside ? t : previousT,
                                                  predicate: predicate)
                    if inside {
                        runStart = crossing
                    } else if let start = runStart {
                        ranges.append((base + start)...(base + crossing))
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
                ranges.append((base + start)...(base + clipHigh))
            }
        }
        return ranges
    }

    // MARK: - Mode 1 — the hybrid resolution
    //
    // ## What the measurement changed about plan §1
    //
    // §1 proposed: cut the spans the eraser fully covers, subtract those from the eraser's footprint,
    // retain whatever is left as an alpha punch — and predicted that a hard round eraser swept across a
    // line the way people normally erase would leave *nothing* to retain.
    //
    // The first half survives. The prediction does not, and `RasterVectorParityLogicTests` is why. Two
    // measurements, both at zero tolerance against a raster layer erased identically:
    //
    // 1. **A retained punch is byte-identical to raster erasing.** Every pixel, across hard/soft
    //    brushes, full/partial opacity, square/diagonal/shave gestures, over a stroke, a fill and a
    //    placed image. §1's fallback is exactly as strong as it claimed.
    // 2. **A geometric split is not, even in its most favourable case.** A hard round eraser at full
    //    opacity cutting square across a line left 498 stray pixels at delta 255.
    //
    // The second is not a tuning failure, it is geometry. A cut stroke is re-rendered by stamping the
    // brush along the surviving samples, so its end is a **round cap of the stroke's own half-width**,
    // while the eraser removed ink along a **straight band edge**. Those two shapes differ by a lens of
    // area ≈ 0.43·w² however the cut boundary is placed — pushing the boundary out past the footprint
    // trades stray ink for missing ink and cannot reach zero. For a 2pt line that is sub-pixel; for the
    // 24pt line in the parity matrix it is hundreds of pixels.
    //
    // So the two representations are not interchangeable-when-clean, and the resolution changes shape:
    //
    // - **The punch is always retained**, which makes Mode 1 pixel-exact by construction rather than by
    //   a threshold nobody can defend.
    // - **A stroke the eraser wholly covers is deleted** (`isEntirelyCovered`). No new geometry, so
    //   nothing re-stamps and nothing can move; every pixel it contributed was under the punch.
    // - **A stroke the eraser partly covers is not cut.** This is the reversal, and it is the second
    //   thing measurement took away — see below.
    //
    // ## Why there is no partial split
    //
    // The obvious reading is that a cut hidden under the eraser cannot be seen, so a conservatively
    // inset cut (`conservativeCuts`, still here, still tested) is free. That is true of the ink *at*
    // the cut and false of the stroke as a whole, because a surviving piece is not edited — it is
    // **re-stamped from scratch as a new stroke**, and `BrushStamper.stampStroke` anchors two things at
    // `samples[0]`:
    //
    // 1. the **dab lattice** — dabs are laid every `stampSpacing` starting from the first sample, and
    // 2. the **pressure ramp** — `lastPressure` starts there and interpolates onward.
    //
    // A piece that begins at the cut re-anchors both, so its dabs land somewhere new along its *entire
    // length*, most visibly at its far tip — which is the end furthest from the eraser and therefore
    // the one the punch cannot cover. Measured on the parity harness, a 24pt line cut by a 48pt hard
    // round nib: split-versus-whole differs across x ∈ [41, 115] while the punch covers only x ∈
    // [40, 88], leaving 118 stray pixels at up to 183/255 after the punch. Widening the eraser does not
    // help; it moves the artefact further away rather than covering it, because the artefact's size is
    // set by the *stroke's* spacing and width.
    //
    // So splitting and exactness are incompatible **given this stamper**, and exactness won. Making
    // them compatible means giving the lattice and the ramp an anchor a sub-run can reproduce — dab
    // positions keyed to arclength from the stroke's origin, or a parametric visible-range on
    // `VectorStroke` so a piece reuses the original lattice instead of starting its own. Either is a
    // real change to `BrushStamper` and to what a stroke stores, which is why it is not in this phase.
    // Until then, geometric separation is Mode 2's job, where changing the pixels is the point.
    // - **The growth §1 worried about is answered by retain-or-drop and GC instead.** An element is
    //   kept only when some part of the gesture still has something beneath it (`hasResidue`), and
    //   `VectorCanvas` collects it later once nothing does. Scribbling a stroke out completely — the
    //   common case §1 wanted to cost nothing — costs nothing: the stroke is deleted outright, so
    //   nothing is left to punch and no element is retained at all.
    //
    //   The decision is a *bit*, not a set of spans, and the retained punch carries the gesture whole.
    //   Keeping only the stretches that had a backdrop moves every dab after the first retained one
    //   onto a different lattice and is measurably not pixel-exact; `hasResidue` carries the numbers.
    //   That is the same defect as the one that unwired the split, reached from the other side.

    /// Plan §1's alpha gate: whether this eraser brush is capable of a clean cut *at all*, before any
    /// geometry is considered.
    ///
    /// A clean cut asserts that the ink it deletes was going to be removed completely anyway. Anything
    /// that makes the eraser's own alpha less than 1 inside its geometric footprint breaks that, and
    /// the failure is asymmetric — a false "clean" is ink deleted that should have faded, a false
    /// "residue" is only a retained element — so every condition below is checked in the strict
    /// direction.
    ///
    /// `scatter` and `rotationJitter` are here because the capsule chain models the *un-scattered*
    /// sweep. `BrushStamper.applyScatter` displaces each dab by up to `radius · 2 · scatter` off the
    /// centreline, so the chain is wrong in both directions at once: it claims coverage where a
    /// displaced dab left a gap, and misses coverage where one landed outside. Neither is a margin that
    /// can be tuned away.
    ///
    /// `.square`/`.custom` are excluded because `BrushStamper.stampApproximateSquare` reaches
    /// `diameter/2 · √2` at the corners while the chain models `diameter/2`. That errs toward retaining
    /// a punch, which is the safe direction, and a square eraser therefore essentially never splits.
    /// `minPressure` is the **lightest pressure the gesture actually carried**, not a property of the
    /// brush. Judging `opacityPressure` against pressure 0 instead — which is what this did first —
    /// bottoms `opacityFraction` out at `1 - opacityPressure` and rejects every brush that reacts to
    /// pressure at all. That is not a conservative gate, it is a dead one: `hardRound` ships with
    /// `opacityPressure: 0.1` and `pen` with `0.05`, so no built-in brush could ever clean-cut and the
    /// entire split path was unreachable. The gesture's pressures are known at the call site, dab
    /// pressure interpolates linearly between samples so the minimum over the dabs is the minimum over
    /// the samples, and a drag from a finger or a mouse reports full pressure throughout — which is
    /// the common case the split exists for.
    static func supportsCleanCut(brush: Brush, opacity: Double, minPressure: CGFloat) -> Bool {
        switch brush.shape {
        case .square, .custom: return false
        case .softRound, .hardRound, .pen, .pencil: break
        }
        guard brush.hardness >= 0.95 else { return false }
        guard !brush.grain.isEnabled else { return false }
        guard opacity * brush.flow >= 0.999 else { return false }
        guard brush.dynamics.opacityFraction(forPressure: Double(minPressure)) >= 0.999 else { return false }
        guard brush.scatter <= 0, brush.rotationJitter <= 0 else { return false }
        return true
    }

    /// Whether a *paint* stroke may be split, as opposed to left to the punch.
    ///
    /// Split pieces mint fresh ids, and `BrushStamper` seeds its dab RNG from the id, so splitting a
    /// stroke whose brush scatters or jitters re-rolls where every one of its dabs lands — the two
    /// halves would visibly reshuffle at the moment of the cut, and the punch cannot put back ink that
    /// moved *outside* the erased region. Such a stroke is left whole and erased by the punch alone,
    /// which is exact.
    static func supportsSplitting(strokeBrush: Brush) -> Bool {
        strokeBrush.scatter <= 0 && strokeBrush.rotationJitter <= 0
    }

    /// The eraser footprint the clean-cut test is allowed to rely on: the sweep's capsules with every
    /// radius pulled in by the deepest gap between consecutive dabs.
    ///
    /// A capsule chain is the region the eraser sweeps only if its dabs actually overlap. `BrushStamper`
    /// spaces them `max(size · spacingFraction, 1)` apart, so a wide-spacing brush paints a row of
    /// beads whose union falls short of the capsule by the scallop depth `r - √(r² - (s/2)²)`. Pulling
    /// the radii in by exactly that is what stops such a brush claiming a clean cut through the gaps it
    /// left. Capsules that vanish entirely are dropped — that eraser cannot cleanly cut anything.
    static func cleanCutCapsules(_ capsules: [StrokeGeometry.Capsule], brush: Brush,
                                 size: CGFloat) -> [StrokeGeometry.Capsule] {
        let spacing = BrushStamper.stampSpacing(brushSize: size, brush: brush)
        var result: [StrokeGeometry.Capsule] = []
        result.reserveCapacity(capsules.count)
        for capsule in capsules {
            let ra = scalloped(capsule.ra, spacing: spacing)
            let rb = scalloped(capsule.rb, spacing: spacing)
            guard ra > StrokeGeometry.epsilon, rb > StrokeGeometry.epsilon else { continue }
            result.append(StrokeGeometry.Capsule(a: capsule.a, b: capsule.b, ra: ra, rb: rb))
        }
        return result
    }

    private static func scalloped(_ radius: CGFloat, spacing: CGFloat) -> CGFloat {
        let half = spacing / 2
        guard half < radius else { return 0 }
        return sqrt(radius * radius - half * half)
    }

    /// How far past the stroke's geometric half-width the eraser must reach before a span counts as
    /// cleanly cut. Plan §1's margin, for anti-aliased fringe at the very edge of the ink.
    static let cleanCutMargin: CGFloat = 0.05

    /// Parametric spans of `samples` where the eraser covers the stroke's **entire width** — §1's
    /// clean-cut test, as opposed to `cutRanges`, which only asks whether the centreline is under the
    /// footprint.
    ///
    /// The walk is `cutRanges`', with a different predicate; the clip rect is grown by the stroke's
    /// widest half-width because a centreline outside the sweep's box can still have ink inside it.
    ///
    /// **Merged before returning**, unlike `cutRanges`. `coveredSpans` closes a run at every segment
    /// boundary it is still inside and leaves the rejoining to a downstream `mergedCuts` — which is
    /// exactly what Mode 2 does, in `VectorCanvas.effectiveCuts`, at the end. Mode 1 cannot wait: it
    /// insets each span by the stroke's half-width first, and insetting the *fragments* insets at
    /// segment joins that are not coverage boundaries at all. A 24pt line sampled every 10pt turns one
    /// genuine 48pt clean span into six 10pt fragments, each of which then collapses under a 12pt
    /// inset, and the split silently never happens — which is precisely what it did.
    static func cleanCutRanges(in samples: [VectorSample], brush: Brush, size: CGFloat,
                               by erasers: [StrokeGeometry.Capsule], sweep: Sweep) -> [ClosedRange<CGFloat>] {
        guard !erasers.isEmpty, !samples.isEmpty else { return [] }
        let reach = StrokeGeometry.stampRadius(forPressure: 1, brush: brush, size: size) * (1 + cleanCutMargin)
        var scratch: [ClosedRange<CGFloat>] = []
        scratch.reserveCapacity(erasers.count)
        let spans = coveredSpans(in: samples, clipTo: sweep.bounds.insetBy(dx: -reach, dy: -reach),
                                 probeStep: sweep.probeStep) { parameter in
            StrokeGeometry.coverage(atParameter: parameter, in: samples, brush: brush, size: size,
                                    by: erasers, margin: cleanCutMargin, scratch: &scratch) >= 1
        }
        return StrokeGeometry.mergedCuts(spans, clampedTo: 0...CGFloat(max(samples.count - 1, 0)))
    }

    /// Whether the eraser covers **every part** of the stroke — each cross-section along it, and both
    /// round end caps. The one geometric verdict Mode 1 acts on.
    ///
    /// Deleting a stroke on this verdict is pixel-neutral in the strongest sense available: it produces
    /// no new geometry at all, so unlike a partial cut there is nothing to re-stamp and nothing that can
    /// land anywhere new. Every pixel the stroke contributed was inside the eraser's footprint, and the
    /// retained punch removes exactly that footprint.
    ///
    /// A single covered span reaching both ends, rather than a union of spans that happens to add up:
    /// `cleanCutRanges` merges before returning, so anything short of one full-domain span means there
    /// is a gap the eraser missed.
    static func isEntirelyCovered(_ samples: [VectorSample], brush: Brush, size: CGFloat,
                                  by erasers: [StrokeGeometry.Capsule], sweep: Sweep) -> Bool {
        guard !samples.isEmpty, !erasers.isEmpty else { return false }
        let domainEnd = CGFloat(samples.count - 1)
        guard capIsCovered(atParameter: 0, in: samples, brush: brush, size: size, by: erasers),
              capIsCovered(atParameter: domainEnd, in: samples, brush: brush, size: size, by: erasers)
        else { return false }
        let spans = cleanCutRanges(in: samples, brush: brush, size: size, by: erasers, sweep: sweep)
        guard spans.count == 1, let span = spans.first else { return false }
        return span.lowerBound <= StrokeGeometry.epsilon
            && span.upperBound >= domainEnd - StrokeGeometry.epsilon
    }

    /// `ranges` pulled in by the stroke's own half-width at each end — the step that would make a
    /// *partial* split safe to combine with a retained punch, if a partial split were safe at all.
    ///
    /// **Not currently wired into `VectorCanvas.eraseHybrid`.** It is correct as far as it goes, it is
    /// tested, and the future fix described in the Mode 1 notes needs it — but insetting solves only
    /// the ink lost to the *new* cap a split creates, and that is not the whole problem. See those
    /// notes. Reachable through the tests, which pin the divergence that unwired it.
    ///
    /// Deleting samples over `[c0, c1]` does not delete the ink over `[c0, c1]`: the surviving pieces
    /// end in round caps, so the ink actually lost runs from `c0 - w` to `c1 + w`, spilling half a
    /// stroke-width past the span that was measured as covered and out of the eraser's footprint
    /// entirely. That is ink the eraser never touched, and no punch can put it back. Insetting by `w`
    /// makes the lost ink a subset of the covered span instead, so the split is invisible and the punch
    /// remains the sole author of the result.
    ///
    /// A span shorter than the two insets disappears: the eraser is narrower than the line it crossed,
    /// so there is no separation to be had geometrically and the punch handles it alone.
    ///
    /// **A stroke's own end is not inset** when `erasers` already covers the cap there. The inset pays
    /// for a cap the split *creates*; at the stroke's own end no new cap appears, because that end is
    /// being deleted rather than moved, and the only ink at stake is the existing cap — which
    /// `StrokeGeometry.capsules(_:contain:radius:)` has just confirmed the eraser removes anyway.
    /// Without this a stroke scribbled out from end to end can never be deleted: both boundaries are
    /// pushed half a width inward, so two invisible stubs survive under the punch, they keep the punch
    /// alive through garbage collection, and plan §1's "erasing a stroke away completely costs
    /// nothing" is false for the one gesture it was written about.
    static func conservativeCuts(_ ranges: [ClosedRange<CGFloat>], in samples: [VectorSample],
                                 brush: Brush, size: CGFloat,
                                 by erasers: [StrokeGeometry.Capsule]) -> [ClosedRange<CGFloat>] {
        guard samples.count > 1 else { return ranges }
        let domainEnd = CGFloat(samples.count - 1)
        var result: [ClosedRange<CGFloat>] = []
        for range in ranges {
            let lowWidth = halfWidth(at: range.lowerBound, in: samples, brush: brush, size: size)
            let highWidth = halfWidth(at: range.upperBound, in: samples, brush: brush, size: size)
            let low = range.lowerBound <= StrokeGeometry.epsilon
                && capIsCovered(atParameter: 0, in: samples, brush: brush, size: size, by: erasers)
                ? 0
                : StrokeGeometry.offsetParameter(range.lowerBound, by: lowWidth, in: samples)
            let high = range.upperBound >= domainEnd - StrokeGeometry.epsilon
                && capIsCovered(atParameter: domainEnd, in: samples, brush: brush, size: size, by: erasers)
                ? domainEnd
                : StrokeGeometry.offsetParameter(range.upperBound, by: -highWidth, in: samples)
            guard high - low > StrokeGeometry.epsilon else { continue }
            result.append(low...high)
        }
        return result
    }

    /// Whether the round cap the stroke renders at `parameter` is inside the eraser's footprint. The
    /// same `cleanCutMargin` the cross-section test uses, for the same anti-aliased fringe.
    private static func capIsCovered(atParameter parameter: CGFloat, in samples: [VectorSample],
                                     brush: Brush, size: CGFloat,
                                     by erasers: [StrokeGeometry.Capsule]) -> Bool {
        guard let sample = StrokeGeometry.interpolatedSample(in: samples, at: parameter) else { return false }
        let radius = halfWidth(at: parameter, in: samples, brush: brush, size: size) * (1 + cleanCutMargin)
        return StrokeGeometry.capsules(erasers, contain: sample.point, radius: radius)
    }

    private static func halfWidth(at parameter: CGFloat, in samples: [VectorSample], brush: Brush,
                                  size: CGFloat) -> CGFloat {
        let pressure = StrokeGeometry.interpolatedSample(in: samples, at: parameter)?.pressure ?? 1
        return StrokeGeometry.stampRadius(forPressure: pressure, brush: brush, size: size)
    }

    /// Whether *any* of the eraser's gesture still has something under it, given `hasBackdrop` — plan
    /// §1's "subtract the resolved span from the eraser's footprint", reduced to the one bit
    /// `VectorCanvas` is allowed to act on.
    ///
    /// This is what keeps Mode 1 from growing the display list on every stroke. A drag that passed over
    /// nothing at all, or over ink the split has since removed entirely, has nothing left to punch and
    /// no element is kept; an erase that resolved completely retains nothing.
    ///
    /// **It reports a bit rather than the spans, and the punch keeps the whole gesture.** Retaining a
    /// sub-run instead was measurably wrong, which is worth stating plainly because the spans are right
    /// there and re-deriving the reason costs a day. `BrushStamper.stampStroke` lays its dabs on a
    /// lattice that starts at `samples[0]` and steps one `stampSpacing` at a time, carrying the
    /// remainder across segments. Start the run somewhere else and *every* dab after that point moves,
    /// including the ones over the ink that justified retaining the punch at all. The union of full-alpha
    /// dabs is unchanged in its interior, so this is invisible in the easy case — but at an
    /// anti-aliased edge, and at any eraser opacity below 1 where alpha never saturates, it is not:
    /// measured against the raster tier, trimming cost 4/255 over 22 pixels for a hard round eraser
    /// crossing diagonally and 27/255 over 81 pixels for the same gesture at opacity 0.4. Snapping the
    /// span boundary to a lattice position would fix the phase in exact arithmetic and not in
    /// floating-point, and §8 is asserted at *zero* tolerance.
    ///
    /// The cost of keeping the whole gesture is dabs that punch nothing, which is render time and no
    /// pixels. It is also not obviously a cost at all in display-list terms: trimming *split* a gesture
    /// that crossed two separated strokes into two retained elements, where this keeps one.
    ///
    /// `hasBackdrop` is asked at a parametric position along the gesture and answers "is there anything
    /// beneath the dab there" — it needs the display list, so `VectorCanvas` supplies it.
    static func hasResidue(in samples: [VectorSample], sweep: Sweep,
                           hasBackdrop: (CGFloat) -> Bool) -> Bool {
        guard !samples.isEmpty else { return false }
        return !coveredSpans(in: samples, clipTo: sweep.bounds, probeStep: sweep.probeStep,
                             predicate: hasBackdrop).isEmpty
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

    /// What one Mode-3 resolve did. `.missed` and `.unchanged` differ only in whether the eraser tip
    /// was over ink at all, which is the entire input to `IntersectionDriver`'s re-arming rule.
    enum CutOutcome: Equatable {
        /// No paint stroke's footprint reaches the tip.
        case missed
        /// A stroke is under the tip, but nothing came off it — either the caller asked not to cut, or
        /// the span between its neighbouring crossings was already gone.
        case unchanged
        /// Geometry was removed.
        case cut
    }

    /// Turns a stream of eraser positions into Mode 3 cuts: cut on entering a stroke, then stay quiet
    /// until the tip is over nothing again.
    ///
    /// The plan (§4, Mode 3) asks for a cut on touch-**down** and a re-query per crossing, so one drag
    /// across three lines cuts three spans. Cutting on *every* sample instead gets the three-line case
    /// right and everything else wrong: the span Mode 3 removes runs between the target's neighbouring
    /// crossings, which can be anywhere — including a few points from the finger — so a tip left
    /// sitting on a line would chew it away span by span, one per touch sample, from a stationary
    /// finger. Latching on "the tip has left ink" is what makes "per crossing" mean per *crossing*
    /// rather than per sample.
    ///
    /// A `struct` here rather than the three lines of state inlined into `StrokeCanvasView` for one
    /// reason: this file compiles into the test target and that view does not, and the rule above is
    /// exactly the kind of thing that is easy to get subtly wrong and impossible to notice without a
    /// test. `StrokeCanvasView` owns an instance and feeds it outcomes.
    struct IntersectionDriver {
        /// Whether the next position should cut. True at touch-down, so Mode 3 fires immediately.
        private(set) var isArmed = true
        /// Whether this gesture has removed anything, so the driver's owner can register exactly one
        /// undo entry for the drag — and none at all when the drag cut nothing.
        private(set) var didCut = false

        init() {}

        /// Feeds back the result of resolving at one position. Call with the outcome of a resolve made
        /// with `cutting: isArmed`.
        mutating func accept(_ outcome: CutOutcome) {
            switch outcome {
            case .missed:
                // Over nothing: the next stroke entered is a new crossing and gets its own cut.
                isArmed = true
            case .unchanged:
                isArmed = false
            case .cut:
                isArmed = false
                didCut = true
            }
        }
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
    private static func refineCrossing(base: CGFloat, outside: CGFloat, inside: CGFloat,
                                       predicate: (CGFloat) -> Bool) -> CGFloat {
        var outside = outside, inside = inside
        for _ in 0..<refinementSteps {
            let mid = (outside + inside) / 2
            if predicate(base + mid) { inside = mid } else { outside = mid }
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
