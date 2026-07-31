import UIKit
import CoreGraphics

/// Turns an `InterpolationRecipe` into pixels: warp each keyframe's content through the group's
/// interpolated lattice, then composite the two results as **isolated groups** blended at (1−t)/t.
///
/// ## Why two sets and not one list
///
/// `PLAN.md` §5.6, and it is the correctness point of this whole file. An `.erase` stroke lowers the
/// alpha of everything beneath it *in the display list it is drawn in*
/// (`VectorCanvas.renderLocalContent` rule 3). Concatenating the forward and backward sets would put
/// keyframe A's eraser above keyframe C's strokes, and it would punch holes in geometry it has no
/// business touching. Two `VectorCanvas` instances rendered separately and blended cannot do that: an
/// eraser reaches only its own keyframe's content, by construction.
///
/// That choice deliberately buys correctness with a second render rather than with a change to the
/// renderer's isolation rules, which are load-bearing and heavily documented. Optimising it into a
/// single `.group` element is a measurement away, not a guess away — see `IMPLEMENTATION.md` Phase 3
/// item 2.
///
/// ## What this file does *not* keep
///
/// No embeddings are cached anywhere, here or in the recipe. `Lattice.expanded(toContain:)` shifts
/// every cell and vertex index when the lattice grows, so a persisted embedding would need re-mapping
/// or version-stamping; deriving it costs one pass and cannot be silently stale. See `HANDOFF.md`
/// §5.7 and §5.8.
enum InterpolationEvaluator {

    // MARK: - Inputs

    /// Resolves one of the recipe's references to the display list that cel holds.
    ///
    /// A closure rather than a reference to `CanvasManager`, so the evaluator stays testable without
    /// a document and cannot reach for state it has no business reading.
    typealias ContentProvider = (CelRef) -> [VectorElement]

    /// How a set's cross-fade weight reaches the width of the strokes in it.
    ///
    /// `PLAN.md` §7.1 wants fading-out content to *thin* rather than only ghost — a shrinking line
    /// (and, for an eraser, a shrinking hole) reads better than a translucent one. The mechanism is
    /// here and works. It is **off by default**, and the reason is worth stating because it looks
    /// like a missing feature:
    ///
    /// Thinning is right for a stroke that exists at one keyframe and has no counterpart at the
    /// other. It is wrong for a stroke that exists at both — which, without correspondence, is every
    /// stroke, since each set carries the whole drawing. Scaling both sets by their weight would make
    /// every mid-frame thin *and* washed out instead of merely washed out. The moment a matcher can
    /// say "this stroke has no counterpart" (engine D, `PLAN.md` §3), `.weighted` becomes right for
    /// exactly those strokes and wrong for the rest.
    enum ThicknessFade: Equatable {
        /// Widths untouched; the (1−t)/t blend does all the fading.
        case none
        /// Width scaled by `weight ^ exponent`. `1` is linear; higher holds the width longer.
        case weighted(exponent: CGFloat)

        func scale(weight: CGFloat) -> CGFloat {
            switch self {
            case .none: return 1
            case .weighted(let exponent): return pow(max(weight, 0), max(exponent, 0))
            }
        }
    }

    struct Options {
        var thicknessFade: ThicknessFade = .none
        var arap = ARAPInterpolation.Options()
        init() {}
    }

    // MARK: - Output

    /// What to draw at one `t`: three display lists and the two blend weights.
    ///
    /// Three rather than the two `IMPLEMENTATION.md` names, because `localEdits` cannot join either
    /// set. A stroke the artist drew *at* the in-between is not a keyframe's content being faded in
    /// or out — it is present at full strength from its threshold onward — and an `.erase` local edit
    /// has to reach **both** keyframes' ink, which only works if it is drawn after they are blended.
    /// `composite(_:size:quality:)` is where that ordering lives.
    struct Evaluation {
        /// Keyframe A's content, warped forward to `t`.
        var forward: [VectorElement]
        /// Keyframe C's content, warped backward to `t`.
        var backward: [VectorElement]
        /// The artist's own edits at the in-between, warped from rest space. Full strength.
        var localEdits: [VectorElement]
        var forwardWeight: CGFloat
        var backwardWeight: CGFloat
    }

    // MARK: - Evaluation

    /// The display lists for `recipe` at `t`, or nil when the recipe is not evaluable.
    ///
    /// `t` is the raw slider position, normalised across the **whole** reference span — `0` at the
    /// first reference, `1` at the last, not per segment (`HANDOFF.md` §5.8). It is taken as a
    /// parameter rather than read from `recipe.t` so a scrub can evaluate without mutating the
    /// document.
    ///
    /// Returns nil rather than a best effort when `isWellFormed` is false. A recipe can be broken by
    /// editing *around* it — deleting a referenced cel, adding a reference without re-registering the
    /// groups — and "not yet" is the honest answer to that, where a partial render would look like a
    /// bug in the interpolation.
    static func evaluate(recipe: InterpolationRecipe,
                         at t: CGFloat,
                         content: ContentProvider,
                         options: Options = Options()) -> Evaluation? {
        guard recipe.isWellFormed else { return nil }

        let count = recipe.references.count
        let span = CGFloat(count - 1)

        // Which pair of references this `t` sits between, and where between them.
        //
        // Uniform segments: each of the `count - 1` gaps takes an equal share of `0...1`. §5.8 leaves
        // this to the evaluator and notes it is picked once — changing it later changes what an
        // already-saved `t` means. With today's two references there is one segment and `local` is
        // exactly the slider.
        let frameT = recipe.spacing.eased(t)
        let index = min(max(Int((frameT * span).rounded(.down)), 0), count - 2)
        let local = min(max(frameT * span - CGFloat(index), 0), 1)

        let warps = groupWarps(recipe: recipe, at: t, segment: index, span: span, options: options)
        // Untagged content — every stroke the app creates today, plus every fill and image, since
        // only `VectorStroke` carries a `motionGroupID` — rides the first binding.
        //
        // With one binding that is the whole-frame group of §5.8 and this is exactly right. With
        // several it is a choice, and it is the safe one: content left behind while its neighbours
        // move is a much louder failure than content carried by a neighbouring group's motion. Phase
        // 5, which is where several groups first exist, is responsible for tagging.
        let fallback = recipe.groups.first.flatMap { warps[$0.groupID] }

        let forwardElements = recipe.references[index].cels.flatMap(content)
        let backwardElements = recipe.references[index + 1].cels.flatMap(content)

        return Evaluation(
            forward: warped(forwardElements, at: t, weight: 1 - local, direction: .forward,
                            warps: warps, fallback: fallback, options: options),
            backward: warped(backwardElements, at: t, weight: local, direction: .backward,
                             warps: warps, fallback: fallback, options: options),
            localEdits: warpedLocalEdits(recipe.localEdits, at: t, warps: warps, fallback: fallback),
            forwardWeight: 1 - local,
            backwardWeight: local)
    }

    /// One warp per motion group binding, evaluated at `t`.
    ///
    /// A group's own `spacing` retimes its **motion** — where its lattice sits between the two
    /// keyframes — and nothing else. The cross-fade weight stays frame-wide, because the two sets are
    /// composited as whole canvases and a canvas has one alpha. With no per-group override, which is
    /// every recipe today, the two coincide exactly.
    private static func groupWarps(recipe: InterpolationRecipe, at t: CGFloat, segment: Int,
                                   span: CGFloat, options: Options) -> [UUID: GroupWarp] {
        var warps: [UUID: GroupWarp] = [:]
        for binding in recipe.groups {
            let groupT = (binding.spacing ?? recipe.spacing).eased(t)
            let u = min(max(groupT * span - CGFloat(segment), 0), 1)
            let from = binding.lattices[segment]
            let to = binding.lattices[segment + 1]
            // A topology mismatch has no meaningful in-between; `Interpolator.init` is failable for
            // that reason and the honest fallback is "do not move", not an invented blend.
            let current = ARAPInterpolation.Interpolator(from: from, to: to, options: options.arap)?
                .lattice(at: u) ?? from
            warps[binding.groupID] = GroupWarp(from: from, to: to, current: current)
        }
        return warps
    }

    // MARK: - Warping one set

    private enum Direction { case forward, backward }

    /// One motion group's lattice at this `t`, alongside the two keyframe configurations its
    /// embeddings are taken in.
    private struct GroupWarp {
        let from: Lattice
        let to: Lattice
        let current: Lattice

        func map(_ points: [CGPoint], _ direction: Direction) -> [CGPoint] {
            current.warp(Self.embed(points, in: direction == .forward ? from : to))
        }

        /// A local edit is stored in rest space (`LocalEdit`), so it embeds in the rest grid and
        /// warps with whatever the lattice is doing now — which is what makes it follow the motion
        /// instead of sitting still (`PLAN.md` §5.4).
        func mapFromRest(_ points: [CGPoint]) -> [CGPoint] {
            current.warp(current.embedInRest(points))
        }

        /// `embedInCurrent` is the general inverse map and needs a point-in-quad search plus inverse
        /// bilinear. A lattice that is *exactly* at rest has the same answer in closed form and to
        /// the last bit, which is both faster and what keeps `t = 0` reproducing keyframe A exactly
        /// — so it is worth the branch. `tolerance: 0` and not `Lattice.epsilon`: "near rest" is not
        /// rest, and taking the cheap path for a lattice a hair off it would move geometry.
        private static func embed(_ points: [CGPoint], in lattice: Lattice) -> LatticeEmbedding {
            lattice.isRest(tolerance: 0) ? lattice.embedInRest(points) : lattice.embedInCurrent(points)
        }
    }

    private static func warped(_ elements: [VectorElement], at t: CGFloat, weight: CGFloat,
                               direction: Direction, warps: [UUID: GroupWarp],
                               fallback: GroupWarp?, options: Options) -> [VectorElement] {
        elements.compactMap { element in
            switch element {
            case .stroke(let stroke):
                let warp = stroke.motionGroupID.flatMap { warps[$0] } ?? fallback
                guard let visible = visible(stroke, at: t) else { return nil }
                return .stroke(warped(visible, weight: weight, options: options) {
                    warp?.map($0, direction) ?? $0
                })
            case .fill(let fill):
                return .fill(warped(fill) { fallback?.map($0, direction) ?? $0 })
            case .image(let image):
                return .image(warped(image) { fallback?.map($0, direction) ?? $0 })
            }
        }
    }

    private static func warpedLocalEdits(_ edits: [LocalEdit], at t: CGFloat,
                                         warps: [UUID: GroupWarp],
                                         fallback: GroupWarp?) -> [VectorElement] {
        edits.compactMap { edit in
            guard let visible = visible(edit.stroke, at: t) else { return nil }
            let warp = edit.groupID.flatMap { warps[$0] } ?? fallback
            // Weight 1 and no thickness fade: a local edit is the artist's own content at this
            // frame, not a keyframe's content being faded in or out.
            return .stroke(warped(visible, weight: 1, options: Options()) {
                warp?.mapFromRest($0) ?? $0
            })
        }
    }

    // MARK: - Visibility

    /// `stroke` with every sample that is not yet visible at `t` removed, or nil if none survive.
    ///
    /// The rule is one rule: a sample is visible when `t >= τ`, where τ is its own entry in
    /// `sampleVisibilityThresholds`, or the whole-stroke `visibilityThreshold`, or — for the
    /// overwhelmingly common stroke that carries neither — always. That subsumes the whole-stroke
    /// gate: if every sample falls back to a τ above `t`, nothing survives and the stroke is dropped.
    ///
    /// Note that content which exists at one keyframe and not the other needs **no** threshold. It
    /// lives in one set only, and that set's weight fades it. τ is for content that appears partway
    /// through — `PLAN.md` §5.4's edits at the in-between — which is why the comparison is one-sided.
    ///
    /// Surviving samples are re-joined in order, so a stroke whose visible samples are not contiguous
    /// shortcuts straight across the gap. Thresholds are expected to be monotone along a stroke,
    /// which is what "vanishing progressively along its length" means; a non-monotone set is not
    /// something any producer here creates.
    private static func visible(_ stroke: VectorStroke, at t: CGFloat) -> VectorStroke? {
        guard stroke.visibilityThreshold != nil || stroke.sampleVisibilityThresholds != nil else {
            return stroke
        }
        let perSample = stroke.sampleVisibilityThresholds ?? [:]
        let kept = stroke.samples.indices.filter { index in
            guard let threshold = perSample[index] ?? stroke.visibilityThreshold else { return true }
            return t >= threshold
        }
        guard !kept.isEmpty else { return nil }

        var trimmed = stroke
        trimmed.visibilityThreshold = nil
        trimmed.sampleVisibilityThresholds = nil
        guard kept.count < stroke.samples.count else { return trimmed }

        trimmed.samples = kept.map { stroke.samples[$0] }
        // A piece's `parameters` are aligned with its own samples, so they trim at the same indices.
        // The parent walk in `lattice.samples` is untouched — trimming narrows the piece's `range`,
        // which is exactly the effect wanted: fewer of the parent's dabs are drawn.
        if var lattice = trimmed.lattice, lattice.parameters.count == stroke.samples.count {
            lattice.parameters = kept.map { lattice.parameters[$0] }
            trimmed.lattice = lattice
        }
        return trimmed
    }

    // MARK: - Warping one element

    private static func warped(_ stroke: VectorStroke, weight: CGFloat, options: Options,
                               by map: ([CGPoint]) -> [CGPoint]) -> VectorStroke {
        var result = stroke
        let moved = map(stroke.samples.map(\.point))
        if moved.count == stroke.samples.count {
            result.samples = zip(stroke.samples, moved).map {
                VectorSample(x: $1.x, y: $1.y, pressure: $0.pressure)
            }
        }
        // A piece's dabs come from its *parent's* walk, so the parent's samples have to travel too —
        // otherwise the stroke's geometry moves and its ink stays behind. See `DabLattice`.
        if var lattice = result.lattice {
            let movedParent = map(lattice.samples.map(\.point))
            if movedParent.count == lattice.samples.count {
                lattice.samples = zip(lattice.samples, movedParent).map {
                    VectorSample(x: $1.x, y: $1.y, pressure: $0.pressure)
                }
                result.lattice = lattice
            }
        }
        result.size *= options.thicknessFade.scale(weight: weight)
        return result
    }

    /// A fill warped by its group's lattice.
    ///
    /// Control points, per `PLAN.md` §7.3 — a warped Bézier is not the Bézier through the warped
    /// control points, but at the lattice scales this feature uses the difference is far below a
    /// pixel, and subdividing every curve to fix it would cost more than the entire warp.
    ///
    /// The id is carried across. Nothing in rendering reads a fill's id, but keeping it stable is
    /// what lets a later matcher (§7.3's colour lerp between corresponded fills) recognise the same
    /// fill at two keyframes.
    private static func warped(_ fill: VectorFillElement, by map: ([CGPoint]) -> [CGPoint]) -> VectorFillElement {
        guard let path = fill.cgPath else { return fill }
        var result = VectorFillElement(path: warped(path: path, by: map), color: fill.color,
                                       opacity: fill.opacity, evenOddFill: fill.evenOddFill)
        result.id = fill.id
        return result
    }

    /// A placed image, moved.
    ///
    /// Only its centre travels: the payload is a bitmap drawn through one affine transform, so it
    /// cannot follow a lattice's local deformation without a mesh draw. Moving the centre keeps it
    /// travelling with the motion, which is the part that shows; leaving it behind while the drawing
    /// around it moved would be the visible failure. Worth revisiting if placed images turn out to
    /// matter inside an interpolated span.
    private static func warped(_ element: VectorImageElement, by map: ([CGPoint]) -> [CGPoint]) -> VectorImageElement {
        var result = element
        if let moved = map([element.transform.position]).first {
            result.transform.position = moved
        }
        return result
    }

    /// `path` with every point run through `map`, in one batch.
    ///
    /// Batched rather than point-by-point because the map is a lattice warp, and a warp of *n* points
    /// is one embedding pass plus *n* bilinear evaluations — while *n* warps of one point each would
    /// rebuild the deformed-cell index *n* times.
    static func warped(path: CGPath, by map: ([CGPoint]) -> [CGPoint]) -> CGPath {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            for i in 0..<pointCount(of: element.pointee.type) {
                points.append(element.pointee.points[i])
            }
        }
        let moved = map(points)
        guard moved.count == points.count else { return path }

        let result = CGMutablePath()
        var next = 0
        path.applyWithBlock { element in
            let type = element.pointee.type
            let taken = pointCount(of: type)
            defer { next += taken }
            switch type {
            case .moveToPoint:
                result.move(to: moved[next])
            case .addLineToPoint:
                result.addLine(to: moved[next])
            case .addQuadCurveToPoint:
                result.addQuadCurve(to: moved[next + 1], control: moved[next])
            case .addCurveToPoint:
                result.addCurve(to: moved[next + 2], control1: moved[next], control2: moved[next + 1])
            case .closeSubpath:
                result.closeSubpath()
            @unknown default:
                break
            }
        }
        return result
    }

    private static func pointCount(of type: CGPathElementType) -> Int {
        switch type {
        case .moveToPoint, .addLineToPoint: return 1
        case .addQuadCurveToPoint: return 2
        case .addCurveToPoint: return 3
        case .closeSubpath: return 0
        @unknown default: return 0
        }
    }

    // MARK: - Compositing

    /// The two sets rendered in isolation and blended at (1−t)/t, with local edits drawn over the
    /// result.
    ///
    /// The local-edit pass reuses the ordinary renderer rather than reaching into it: the blended
    /// image goes in as a `.image` element with the edits above it, so an `.erase` local edit punches
    /// through *both* keyframes' ink exactly as rule 3 says an eraser should, with no new drawing
    /// code and no change to the walk. It costs one extra canvas-sized render and only happens when
    /// there are edits to draw.
    static func composite(_ evaluation: Evaluation, size: CGSize,
                          quality: RenderQuality = .full) -> UIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let format = PixelOps.transparentFormat()
        format.preferredRange = .standard

        let forward = VectorCanvas(size: size, elements: evaluation.forward).render(quality: quality)
        let backward = VectorCanvas(size: size, elements: evaluation.backward).render(quality: quality)
        let blended = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            forward.draw(in: bounds, blendMode: .normal, alpha: evaluation.forwardWeight)
            backward.draw(in: bounds, blendMode: .normal, alpha: evaluation.backwardWeight)
        }
        guard !evaluation.localEdits.isEmpty else { return blended }

        let backdrop = VectorImageElement(
            image: blended,
            transform: LayerTransform(position: CGPoint(x: size.width / 2, y: size.height / 2),
                                      scale: 1, rotation: 0))
        return VectorCanvas(size: size, elements: [.image(backdrop)] + evaluation.localEdits)
            .render(quality: quality)
    }

    /// Evaluate and composite in one call — what a caller that just wants the frame's pixels asks
    /// for. Nil for a recipe that is not evaluable, same contract as `evaluate`.
    static func render(recipe: InterpolationRecipe, at t: CGFloat, size: CGSize,
                       content: ContentProvider, quality: RenderQuality = .full,
                       options: Options = Options()) -> UIImage? {
        guard let evaluation = evaluate(recipe: recipe, at: t, content: content, options: options) else {
            return nil
        }
        return composite(evaluation, size: size, quality: quality)
    }
}
