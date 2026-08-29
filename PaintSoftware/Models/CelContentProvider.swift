import UIKit

/// The pixels a cel **shows** when they are not the pixels it **stores** — VECTOR_INTERPOLATION.md
/// item 18's `ContentProvider` seam, and KEYFRAMES.md §8's one prerequisite that is not part of the
/// keyframe feature.
///
/// ## Why it is a value handed to the renderer rather than a link back to the manager
///
/// Item 18 rules that out explicitly and it is worth writing down why, because a back-reference is
/// the obvious shortcut. `Cel` is a value type living inside `Layer.cels`, which
/// `CanvasManager.StructureSnapshot` copies wholesale for undo — so a cel is routinely *duplicated*
/// (copy/paste, block drag, every undo snapshot) and a stored pointer to the document would either
/// be copied with it into a state nobody meant to share, or need clearing at every copy site. The
/// same shape one level up is what `InterpolationEvaluator` already refused: its own
/// `ContentProvider` is a closure "so the evaluator stays testable without a document and cannot
/// reach for state it has no business reading". This is that argument applied to the rasterizer.
///
/// **Do not confuse the two `ContentProvider`s.** `InterpolationEvaluator.ContentProvider` is
/// `(CelRef) -> [VectorElement]` and resolves a *reference keyframe* to the ink it stores — an
/// **input** to an evaluation. This one resolves *any* cel to the picture it displays, which for an
/// in-between is the **output** of that evaluation.
///
/// ## Why the answer is an image and not a display list
///
/// It cannot be a display list. VECTOR_INTERPOLATION §3 fact 9: "No display list can express an
/// in-between at an interior `t`" — an `.erase` stroke reaches everything beneath it *in the list it
/// is drawn in*, so the two keyframes' content must be rendered in isolation and blended, and
/// `VectorElement` has no group case to hold a per-set alpha. Handing back elements would silently
/// let keyframe A's eraser punch holes in keyframe C's ink. So the seam's currency is pixels.
struct DerivedCelContent {

    /// Everything `render` reads, folded into one value a cache can key on.
    ///
    /// **This is the field KEYFRAMES §4.5 says to pin on day one, and it is the reason this type is
    /// a pair rather than a plain closure.** The instant `PixelOps.rasterize` can return different
    /// pixels for the same `Cel`, its memo's key must carry whatever made them different — and the
    /// failure mode is invisible in the obvious place, because `CanvasView.SandwichKey` compares the
    /// whole node tree and so rebuilds the composite dutifully *from the stale flatten underneath
    /// it*. Green tests, wrong pixels, no key that looks wrong.
    ///
    /// The identity and the closure are minted **together, from the same locals**, by whoever
    /// implements the derivation (`CanvasManager.derivedCelContent`). That is the structural half of
    /// the guarantee: the enumeration that has to be complete lives three lines from the code whose
    /// inputs it enumerates, rather than in a separate key type in another file — which is how
    /// `InterpolationPreviewKey` came to be wrong four times.
    let identity: AnyHashable

    /// The derived pixels, at `quality`. **Called only on a memo miss**, which is why it is a thunk
    /// and not an image: resolving a provider is on every rasterize of every cel, and evaluating an
    /// in-between is two lattice embeddings, an ARAP solve and two canvas-sized renders.
    ///
    /// Nil means "not yet" rather than "empty" — a recipe can be malformed while a reference is
    /// being re-picked — and every caller falls back to the cel's stored content, which is what the
    /// app did before this seam existed.
    ///
    /// **Renders at canvas size, always**, with no size parameter: derived geometry is in canvas
    /// coordinates, so a smaller render would *clip* rather than scale. A caller that wants a
    /// reduced image (the onion skin) draws this into its own smaller context, exactly as
    /// `PixelOps.rasterizeUncached` already does with `cel.vector`'s render.
    ///
    /// **Must be pure and thread-safe.** `RenderRequest.renderSources` resolves providers on the
    /// main actor in its first pass and then calls this from `PixelOps.parallelMap`'s workers, so an
    /// implementation has to capture the values it needs rather than reach back into `@Published`
    /// document state.
    let render: (RenderQuality) -> UIImage?

    init(identity: AnyHashable, render: @escaping (RenderQuality) -> UIImage?) {
        self.identity = identity
        self.render = render
    }
}

/// Resolves a cel to the content it does not store, **at a frame**.
///
/// ## Why the frame is here from the start
///
/// Today's only derivation is an interpolation recipe, whose `t` lives on the *cel* and does not
/// vary across the frames that cel spans — so nothing in this version reads the frame. It is a
/// parameter anyway, for the reason ROADMAP §0 gives about a video layer and KEYFRAMES stage 5 gives
/// about a transform key: **a cel occupies a range of frames, and the next derivation source poses
/// it differently on each of them.** Adding the frame later would mean revisiting every call site a
/// second time, and every call site already has one — `makeRenderRequest` is frame-parametric, the
/// onion skin resolves cels by frame, and a thumbnail is a cel's start frame by definition.
///
/// It is bound to the provider rather than passed to `content(for:)` so that a caller which
/// rasterizes many cels at one frame states the frame once, and so that a provider can be handed to
/// something that does not know about frames at all. `at(_:)` rebinds it.
///
/// **A derivation decides for itself whether the frame is in its identity.** Interpolation's is
/// not, deliberately: including a value the render does not read would mint a second cache entry for
/// the same pixels every time the onion skin and the composite asked for one cel at two frames. A
/// pose key's identity will include it, because a pose key reads it.
struct CelContentProvider {

    /// The frame every `content(for:)` answer is for.
    let frame: Int

    private let derive: (Cel, Int) -> DerivedCelContent?

    init(frame: Int, derive: @escaping (Cel, Int) -> DerivedCelContent?) {
        self.frame = frame
        self.derive = derive
    }

    /// What `cel` displays at this provider's frame, or nil when the cel simply shows what it
    /// stores — which is every cel in a document that uses neither animation system, so this has to
    /// be cheap. Implementations answer nil on a field test before doing any work.
    func content(for cel: Cel) -> DerivedCelContent? { derive(cel, frame) }

    /// The same derivation, bound to another frame.
    func at(_ frame: Int) -> CelContentProvider {
        CelContentProvider(frame: frame, derive: derive)
    }

    /// A provider that derives nothing, for a caller that has no document — parity fixtures and the
    /// pure-logic tests. Behaviourally identical to passing nil, and named so a test can say which
    /// of the two it meant.
    static let none = CelContentProvider(frame: 0) { _, _ in nil }
}
