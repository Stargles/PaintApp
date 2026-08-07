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

        /// Motion groups to leave out of the evaluation entirely — Phase 5's solo/mute.
        ///
        /// A *view* filter and never document state: it answers "which part is moving wrongly" by
        /// taking the others away, and an artist who forgets to unmute must not find it in the file.
        /// `CanvasManager.hiddenMotionGroups` is the source, and it is also in
        /// `InterpolationPreviewKey` — the preview is memoized, so an input the key does not mention
        /// appears to do nothing until something unrelated forces a re-render (`HANDOFF.md` §5,
        /// Phase 4).
        ///
        /// Content is hidden by the group it **would move as**, which for anything untagged is the
        /// recipe's first binding. Untagged ink is carried by that group's motion, so leaving it on
        /// screen while its group is muted would show exactly the part the artist asked to hide.
        var hiddenGroups: Set<UUID> = []

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
    /// `subject` is the target cel's **own** display list, and it is read only in `.reproject`, where
    /// it is the whole content of the frame. It is a parameter rather than a `CelRef` on the recipe
    /// on purpose: the recipe lives *on* the cel it describes, so a stored self-reference is document
    /// state that duplicates something the caller already knows and can silently go stale — copy a
    /// cel and its recipe would point at the original's ink. Defaulted so every `.generate` call site
    /// is unaffected.
    static func evaluate(recipe: InterpolationRecipe,
                         at t: CGFloat,
                         content: ContentProvider,
                         subject: [VectorElement] = [],
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
        let fallbackID = recipe.groups.first?.groupID
        let fallback = fallbackID.flatMap { warps[$0] }

        // **Reproject: one set, not two, and nothing is derived** (`PLAN.md` §5.5). The cel's own
        // linework is the frame; all that slides is its pose. So there is no cross-fade to weight —
        // the subject sits at full strength at every `t` — and `backward` is empty rather than
        // holding a second copy of the same drawing.
        //
        // The subject rides the lattice **from rest**, exactly as a local edit does, because the rest
        // grid of a reprojection's lattice is the one drawn over *this cel's* cloud rather than a
        // keyframe's. See `CanvasManager.registerReprojection`.
        if recipe.mode == .reproject {
            // The artist's own linework at this frame, not a keyframe's content being faded in or
            // out — so it is never thinned, for the same reason a local edit is not. Solo/mute still
            // applies: it is a view filter over whatever is on screen.
            var full = options
            full.thicknessFade = .none
            return Evaluation(
                forward: warped(subject, at: t, weight: 1, direction: .fromRest, warps: warps,
                                fallback: fallback, fallbackID: fallbackID, options: full),
                backward: [],
                localEdits: warpedLocalEdits(recipe.localEdits, at: t, warps: warps,
                                             fallback: fallback, fallbackID: fallbackID,
                                             hidden: options.hiddenGroups),
                forwardWeight: 1,
                backwardWeight: 0)
        }

        let forwardElements = recipe.references[index].cels.flatMap(content)
        let backwardElements = recipe.references[index + 1].cels.flatMap(content)

        return Evaluation(
            forward: warped(forwardElements, at: t, weight: 1 - local, direction: .forward,
                            warps: warps, fallback: fallback, fallbackID: fallbackID,
                            options: options),
            backward: warped(backwardElements, at: t, weight: local, direction: .backward,
                             warps: warps, fallback: fallback, fallbackID: fallbackID,
                             options: options),
            localEdits: warpedLocalEdits(recipe.localEdits, at: t, warps: warps, fallback: fallback,
                                         fallbackID: fallbackID, hidden: options.hiddenGroups),
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
            warps[binding.groupID] = groupWarp(binding: binding, lattices: binding.lattices,
                                               recipe: recipe, at: t, segment: segment, span: span,
                                               options: options)
        }
        return warps
    }

    /// One binding's warp at `t`, over a supplied lattice array rather than the binding's own.
    ///
    /// The array is a parameter because `planLocalEdit` has to ask the same question of a *grown*
    /// set of lattices before it knows whether to keep them — see `LocalEditPlan`. Every other
    /// caller passes `binding.lattices` and gets exactly what it always got.
    private static func groupWarp(binding: MotionGroupBinding, lattices: [Lattice],
                                  recipe: InterpolationRecipe, at t: CGFloat, segment: Int,
                                  span: CGFloat, options: Options) -> GroupWarp {
        let groupT = (binding.spacing ?? recipe.spacing).eased(t)
        let u = min(max(groupT * span - CGFloat(segment), 0), 1)
        let from = lattices[segment]
        let to = lattices[segment + 1]
        // A topology mismatch has no meaningful in-between; `Interpolator.init` is failable for
        // that reason and the honest fallback is "do not move", not an invented blend.
        let current = ARAPInterpolation.Interpolator(from: from, to: to, options: options.arap)?
            .lattice(at: u) ?? from
        return GroupWarp(from: from, to: to, current: current)
    }

    // MARK: - Editing at an in-between

    /// Everything the document needs in order to store one stroke drawn *at* `t` — `PLAN.md` §5.4,
    /// `IMPLEMENTATION.md` Phase 6 item 2.
    ///
    /// A plan rather than a mutation because the two halves live in different places: the geometry
    /// goes into the recipe's `localEdits` and the grown lattices go back into a *binding*, and only
    /// `CanvasManager` may write either — inside one undo bracket. Keeping the arithmetic here keeps
    /// it testable without a document, which is the same rule the rest of this file follows.
    struct LocalEditPlan {
        /// The stroke's points, carried back to the group's rest space. This is what to store.
        var restPoints: [CGPoint]

        /// Which binding carries the edit — an index into `recipe.groups`. Nil when the recipe has
        /// no bindings at all, which is the legal degenerate "warp nothing" case (`HANDOFF.md`
        /// §5.8): there is no lattice, so `restPoints` is the input unchanged.
        var bindingIndex: Int?

        /// The id to record on the `LocalEdit`, so the evaluator re-warps it with the same group.
        var groupID: UUID?

        /// `binding.lattices` grown by whole rings so the stroke falls inside, or **nil** when no
        /// growth was needed — which is the overwhelmingly common case, and the nil is what tells
        /// the caller it has nothing to write back.
        var grownLattices: [Lattice]?
    }

    /// Where a stroke drawn at `t` has to be stored, and whether the lattice had to grow to hold it.
    ///
    /// Nil for an empty stroke or a recipe that cannot be evaluated — same "not yet" contract as
    /// `evaluate`, and the caller should decline to record rather than store geometry it cannot
    /// warp back.
    ///
    /// `points` are in the space the evaluator works in, which is the space the reference cels'
    /// display lists are in. See `CanvasManager.recordLocalEdit(canvasSpaceStroke:…)` for why that
    /// is canvas space in practice and what it costs.
    static func planLocalEdit(recipe: InterpolationRecipe, at t: CGFloat, points: [CGPoint],
                              options: Options = Options(),
                              maxRings: Int = 8) -> LocalEditPlan? {
        guard !points.isEmpty, recipe.isWellFormed else { return nil }

        let count = recipe.references.count
        let span = CGFloat(count - 1)
        let frameT = recipe.spacing.eased(t)
        let segment = min(max(Int((frameT * span).rounded(.down)), 0), count - 2)

        // No bindings: the recipe warps nothing, so rest space and the frame coincide and the
        // stroke stores verbatim. Recording it is still right — the artist drew it, and it renders
        // at full strength from τ onward exactly like any other local edit.
        guard !recipe.groups.isEmpty else {
            return LocalEditPlan(restPoints: points, bindingIndex: nil, groupID: nil,
                                 grownLattices: nil)
        }

        let index = bindingCarrying(points, recipe: recipe, at: t, segment: segment, span: span,
                                    options: options)
        let binding = recipe.groups[index]

        // Grow a ring at a time and re-interpolate, rather than growing the interpolated lattice
        // directly. What has to end up in the document is the *stored* `from`/`to`, and a ring added
        // to each of them does not produce quite the same grid as a ring added to their in-between —
        // so the only way to be sure the stroke lands inside what will actually be re-evaluated is
        // to re-evaluate. `Lattice.expanded(toContain:)` loops for the same reason: a deformed
        // lattice gives no closed form for "how many rings would reach this point".
        var lattices = binding.lattices
        var warp = groupWarp(binding: binding, lattices: lattices, recipe: recipe, at: t,
                             segment: segment, span: span, options: options)
        var rings = 0
        while rings < max(0, maxRings), !warp.current.embedInCurrent(points).allInside() {
            lattices = lattices.map { $0.addingRing() }
            warp = groupWarp(binding: binding, lattices: lattices, recipe: recipe, at: t,
                             segment: segment, span: span, options: options)
            rings += 1
        }

        return LocalEditPlan(restPoints: warp.mapToRest(points),
                             bindingIndex: index,
                             groupID: binding.groupID,
                             grownLattices: rings > 0 ? lattices : nil)
    }

    /// Which binding a stroke drawn at `t` belongs to.
    ///
    /// Containment in the group's lattice at `t`, which is the only signal available that does not
    /// require evaluating the frame: a stroke drawn over the arm falls inside the arm's grid. Ties —
    /// and they are common, because each group's lattice is padded past its own content — go to the
    /// group whose lattice is *centred* nearest the stroke, which is the one it is most plausibly
    /// part of.
    ///
    /// Falls back to binding **0** when nothing contains it, which is the same rule untagged content
    /// follows everywhere else (`HANDOFF.md` §5.9). Note the fallback is nearly unreachable in
    /// practice: the expansion loop above grows whichever binding is chosen until the stroke does
    /// fit, so "outside every lattice" only decides *which* group grows, never whether one does.
    private static func bindingCarrying(_ points: [CGPoint], recipe: InterpolationRecipe,
                                        at t: CGFloat, segment: Int, span: CGFloat,
                                        options: Options) -> Int {
        let centroid = CGPoint(x: points.reduce(0) { $0 + $1.x } / CGFloat(points.count),
                               y: points.reduce(0) { $0 + $1.y } / CGFloat(points.count))
        var best: (index: Int, distance: CGFloat)?
        for (index, binding) in recipe.groups.enumerated() {
            let warp = groupWarp(binding: binding, lattices: binding.lattices, recipe: recipe,
                                 at: t, segment: segment, span: span, options: options)
            guard warp.current.containsInCurrent(centroid) else { continue }
            let centre = warp.current.currentBounds
            let distance = hypot(centre.midX - centroid.x, centre.midY - centroid.y)
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index ?? 0
    }

    // MARK: - Warping one set

    /// Which configuration a set's geometry is embedded in before the current lattice warps it.
    ///
    /// `.forward`/`.backward` are the two keyframes a Generate cross-fades between. `.fromRest` is
    /// content stored in the lattice's own rest space — a local edit, or a whole reprojected cel.
    private enum Direction { case forward, backward, fromRest }

    /// One motion group's lattice at this `t`, alongside the two keyframe configurations its
    /// embeddings are taken in.
    private struct GroupWarp {
        let from: Lattice
        let to: Lattice
        let current: Lattice

        func map(_ points: [CGPoint], _ direction: Direction) -> [CGPoint] {
            switch direction {
            case .forward: return current.warp(Self.embed(points, in: from))
            case .backward: return current.warp(Self.embed(points, in: to))
            case .fromRest: return mapFromRest(points)
            }
        }

        /// A local edit is stored in rest space (`LocalEdit`), so it embeds in the rest grid and
        /// warps with whatever the lattice is doing now — which is what makes it follow the motion
        /// instead of sitting still (`PLAN.md` §5.4).
        func mapFromRest(_ points: [CGPoint]) -> [CGPoint] {
            current.warp(current.embedInRest(points))
        }

        /// The exact inverse of `mapFromRest`: where content sitting at the in-between *now* has to
        /// be stored so that re-warping puts it back here.
        ///
        /// This is `PLAN.md` §5.4's inverse map and the whole reason editing at an in-between works.
        /// It is an inverse in the strict sense rather than an approximation — `embedInCurrent`
        /// solves the same bilinear cell coordinates `embedInRest` assigns, and `warpToRest`
        /// evaluates them against the rest vertices that `warp` evaluates against the current ones.
        func mapToRest(_ points: [CGPoint]) -> [CGPoint] {
            current.warpToRest(current.embedInCurrent(points))
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
                               fallback: GroupWarp?, fallbackID: UUID?,
                               options: Options) -> [VectorElement] {
        elements.compactMap { element in
            // Hidden by the group the element *would move as*: its own tag when it has one, and the
            // recipe's first binding when it does not. A fill or a placed image never has one
            // (`HANDOFF.md` §8 item 11), so it is always the fallback that decides for them.
            let hidden = { (tag: UUID?) in
                (tag ?? fallbackID).map(options.hiddenGroups.contains) == true
            }
            switch element {
            case .stroke(let stroke):
                guard !hidden(stroke.motionGroupID) else { return nil }
                let warp = stroke.motionGroupID.flatMap { warps[$0] } ?? fallback
                guard let visible = visible(stroke, at: t) else { return nil }
                return .stroke(warped(visible, weight: weight, options: options) {
                    warp?.map($0, direction) ?? $0
                })
            case .fill(let fill):
                guard !hidden(nil) else { return nil }
                return .fill(warped(fill) { fallback?.map($0, direction) ?? $0 })
            case .image(let image):
                guard !hidden(nil) else { return nil }
                return .image(warped(image) { fallback?.map($0, direction) ?? $0 })
            }
        }
    }

    private static func warpedLocalEdits(_ edits: [LocalEdit], at t: CGFloat,
                                         warps: [UUID: GroupWarp],
                                         fallback: GroupWarp?, fallbackID: UUID?,
                                         hidden: Set<UUID>) -> [VectorElement] {
        edits.compactMap { edit in
            guard (edit.groupID ?? fallbackID).map(hidden.contains) != true else { return nil }
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

    // MARK: - Commit

    /// The single display list that **replaces** an evaluation when the artist commits it —
    /// `PLAN.md` §4's Commit, `HANDOFF.md` §8 item 17.
    ///
    /// ## This is lossy at an interior `t`, and the loss is structural rather than a shortcut
    ///
    /// `PLAN.md` §5.6 says the two sets "cannot be concatenated into one list", and it is right about
    /// rendering: `composite` draws each set in isolation and blends the two images, because an
    /// `.erase` stroke lowers the alpha of everything beneath it *in its list* and A's eraser has no
    /// business reaching C's ink. Commit's whole job is to produce one list, so it cannot honour that.
    /// Nor is there a way around it — `VectorElement` has no group case, so a display list has no
    /// per-set alpha either, and the weights have to reach the elements themselves.
    ///
    /// So this is the deliberate one-way flatten the artist asked for, and exactly three things
    /// change at an interior `t`:
    ///
    /// 1. **Overlapping ink inside one set darkens.** The set used to be rendered opaque and then
    ///    faded to `w`; now each element carries `w` and *n* overlapping ones give `1 − (1 − w)ⁿ`.
    ///    Two coincident strokes at `w = 0.5` land at 0.75 where they used to land at 0.5.
    /// 2. **The backward set's erasers reach the forward set's ink.** Order is what bounds this: the
    ///    forward set is emitted first, so its own erasers still see nothing but its own elements and
    ///    are exactly right. Only the later set leaks, and it leaks by its own weight (see below).
    /// 3. **A placed image cannot fade at all** — `VectorImageElement` has no opacity — so one in a
    ///    partially-faded set commits at full strength. `HANDOFF.md` §8 records it.
    ///
    /// **At `t = 0` and `t = 1` there is no loss whatsoever**, and that falls out rather than being
    /// special-cased: one weight is 0, so that set is dropped entirely, and the other is 1, so
    /// `faded` returns its elements untouched. A commit at an endpoint is bit-exact.
    ///
    /// Local edits go last and unweighted, which is the same position and the same strength
    /// `composite` gives them: an `.erase` local edit is *supposed* to reach both keyframes' ink
    /// (rule 3), so for that one set the flatten is not a compromise but the intended behaviour.
    static func flattened(_ evaluation: Evaluation) -> [VectorElement] {
        faded(evaluation.forward, by: evaluation.forwardWeight)
            + faded(evaluation.backward, by: evaluation.backwardWeight)
            + evaluation.localEdits
    }

    /// One set's elements carrying their set's cross-fade weight as their own opacity.
    ///
    /// **An eraser is scaled like everything else**, and that is a considered trade rather than an
    /// oversight, because the two choices are wrong in different places. Leaving an eraser at full
    /// strength is *more* faithful inside its own set — the hole clears completely, as it did in the
    /// isolated render — but it is much less faithful across sets, since the later set's eraser would
    /// then punch a full hole in the earlier set's ink. Measured as leftover/removed alpha at
    /// `w = 0.5`: scaling leaves a 0.25 ghost inside the set's own holes, while not scaling takes a
    /// 0.5 bite out of the other set's drawing — twice the error, and a hole reads as damage where a
    /// ghost reads as softness. Scaling also makes the leak vanish exactly as the leaking set fades
    /// out, and keeps this function one rule rather than two.
    private static func faded(_ elements: [VectorElement], by weight: CGFloat) -> [VectorElement] {
        // Both guards are what make the endpoints exact, so neither is an optimisation: a set at
        // weight 0 contributes nothing at all, and a set at weight 1 must come through bit-identical
        // rather than multiplied by a 1.0 that a `Double` round-trip could perturb.
        guard weight > 0 else { return [] }
        guard weight < 1 else { return elements }
        return elements.map { element in
            switch element {
            case .stroke(var stroke):
                stroke.opacity *= Double(weight)
                return .stroke(stroke)
            case .fill(var fill):
                fill.opacity *= Double(weight)
                return .fill(fill)
            case .image:
                // Nothing to scale — point 3 above.
                return element
            }
        }
    }

    /// Evaluate and composite in one call — what a caller that just wants the frame's pixels asks
    /// for. Nil for a recipe that is not evaluable, same contract as `evaluate`.
    static func render(recipe: InterpolationRecipe, at t: CGFloat, size: CGSize,
                       content: ContentProvider, subject: [VectorElement] = [],
                       quality: RenderQuality = .full,
                       options: Options = Options()) -> UIImage? {
        guard let evaluation = evaluate(recipe: recipe, at: t, content: content, subject: subject,
                                        options: options) else {
            return nil
        }
        return composite(evaluation, size: size, quality: quality)
    }
}
