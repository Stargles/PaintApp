import UIKit

/// **One rendered thumbnail, held by reference so that installing it is not a mutation of the
/// `@Published` array the cel or layer lives in.** PERFORMANCE.md §18.6.
///
/// The problem it solves is not the tile's own cost — §18 had already taken the render off the main
/// thread, leaving `installThumbnail` at a fraction of a millisecond. It is that the *write*
/// published: `CanvasManager.layers` is `@Published` and `Layer`/`Cel` are structs, so putting a
/// 120×120 image on one block raised a SwiftUI pass over the whole editor, 400 ms after every edit,
/// MEASURED at ~43 ms of main-thread busy on the owner's iPad 9 — two orders of magnitude more than
/// the thing it delivered.
///
/// **It is one storage location, not a shadow of one.** `Cel.thumbnail` and `Layer.thumbnail` are
/// accessors over this and there is no other place a tile is kept, which is the difference between
/// this and a side-channel cache keyed by cel id: nothing can hold a second opinion, because there
/// is nothing else to hold it in. What the arrangement does change is *semantics* — two `Cel` values
/// with the same `id` share one cell, so a copy taken for an undo snapshot or an off-thread render
/// batch reads the tile the live cel has now rather than the one it had when the copy was taken.
/// For a picture that is *derived* from the cel's content that is the answer you want; a copy
/// carrying a stale tile is exactly the failure this cannot have.
///
/// **Nothing here notifies.** A cell has no back-reference to the document and giving it one would
/// be the duplicate-truth spaghetti this exists to avoid, so telling the views is
/// `CanvasManager`'s job — `installThumbnail` and `clearThumbnail` write a cell and then publish
/// `thumbnailInstalled`, and those two are the only writers the app has.
///
/// **Main-thread only, and deliberately not `Sendable`.** `Cel` values do cross threads — the
/// deferred regen and the load-time backfill both carry them to a queue — but nothing off the main
/// actor reads or writes a tile: `celThumbnailImage` renders from the raster and vector tiers and
/// never looks at this. The batches that carry those cels are `@unchecked Sendable` already, and
/// their doc comments say what makes each field safe; claiming it for a bare mutable class would be
/// claiming something this type cannot honour.
final class ThumbnailTile {
    var image: UIImage?

    init(image: UIImage? = nil) { self.image = image }
}

struct Cel: Identifiable {
    let id: UUID
    var startFrame: Int
    var frameCount: Int
    /// Live brush strokes, rasterized at canvas-native resolution. A class, not a value type — call
    /// sites needing an independent copy (duplicating/splitting a cel) must call `.makeCopy()`.
    var raster: RasterLayerTexture
    /// Rasterized bucket-fill output, composited underneath `bakedImage` and `raster`'s strokes.
    /// Nil until the fill tool is used on this cel.
    var fillImage: UIImage? = nil
    /// Flattened raster content "baked" in by a pixel-level operation (select+move, duplicate,
    /// color fill, clear selection). Sits above `fillImage`, underneath `raster`'s live strokes.
    var bakedImage: UIImage? = nil
    /// Vector content for `.vector` layers (strokes/images as geometry, re-rasterized at
    /// canvas-native resolution). Nil on `.raster` layers. Still uses `fillImage`/`bakedImage`
    /// the same way a raster layer does; only the live-stroke tier differs.
    var vector: VectorCanvas? = nil
    /// Non-nil makes this an *interpolated* cel: content is computed from the recipe's references
    /// at time `t` rather than stored here. Lives on `Cel` (inside `Layer.cels`, which
    /// `CanvasManager.StructureSnapshot` copies wholesale) so undo covers every recipe edit with
    /// no new machinery. A `.reproject` recipe coexists with `vector` content (the artist's own
    /// drawing, re-posed); a `.generate` recipe normally sits on a cel with none.
    ///
    /// **A copy of a cel carrying one does not carry it** — ruled 2026-09-03. Duplicate and paste
    /// flatten the in-between into a still and copy that (`CanvasManager.flattenedStill`), which is
    /// the same thing `rasterizeLayer` and `moveCelToLayer` already do to a cel they flatten. Split
    /// is the exception and carries it to *both* halves, because a split makes no copy: both halves
    /// are the same in-between of the same pair at the same `t`.
    var interpolation: InterpolationRecipe? = nil
    /// **The pose channels animating this cel's content** — KEYFRAMES.md stage 5, keyed by
    /// `TransformChannelID.id` (`"cel"`, or `"group.<uuid>"`).
    ///
    /// **On the cel and in cel-local frames**, which is §3.1's first row: the channel rides the cel
    /// through move, split, duplicate and paste. Effect-parameter channels are the other row — they
    /// live on the *layer* in absolute document frames (§2.4), because their target has no cel to
    /// ride.
    ///
    /// **"Rides for free" is what this comment said until 2026-09-02 and it was false of three of
    /// those four verbs.** `moveCel` genuinely is free — it writes `startFrame` and the keys are
    /// numbered from it — but `duplicateCel`, `splitCel` and `pasteCel` each *build a new `Cel`*, and
    /// a memberwise initialiser defaults an unmentioned field to `[:]`. So an animated cel duplicated,
    /// split or pasted came back as the drawing with its animation deleted, and nothing said so. The
    /// three call sites now carry these two fields explicitly, and `splitCel` carries §3.1's cut rule
    /// through `TransformTrack.split(atCelLocalFrame:)`. **Add a field here and you owe those three
    /// sites a line each** — two of them by way of `Cel.CopyTiers` below, where the compiler collects
    /// the debt; cel-local numbering is what makes the line a copy rather than a conversion, which is
    /// the part that really is free.
    ///
    /// **A key never lives outside `0..<frameCount`** — TODO (62), the owner's ruling of 2026-09-10.
    /// Every verb that can shorten this cel's span (both resize handles, split, a clamped duplicate
    /// or paste, a video speed change) calls `cropPoseKeysToSpan` from inside its own undo step, so
    /// the keys past the new end go with the frames and come back with them on undo; the crop is
    /// announced (`CanvasNotice.keyframesCropped`) and nothing else restores them. A left-edge resize
    /// keeps every key on the document frame it was on, so the local numbers shift with the origin.
    /// A document saved before the ruling may still carry a key past a span; it is left alone until a
    /// span change touches that cel, because a silent crop on load is the loss the ruling forbids.
    ///
    /// Empty is the overwhelmingly common case and every reader tests it first: a document that has
    /// never been keyframed must cost one `isEmpty` on the paths that ask, which is every rasterize of
    /// every cel.
    ///
    /// **A cel carrying an `interpolation` recipe ignores these, by §2.18** — a derived in-between has
    /// no stable elements to key, its display list is computed, and `CanvasManager.derivedCelContent`
    /// takes the interpolation arm. The writer refuses to create one there rather than leaving storage
    /// that renders nothing.
    var transformTracks: [String: TransformTrack] = [:]
    /// **§2.27's held pose, per channel id** — *"keyframe A is added, nothing is saved. A slider is
    /// then adjusted. The previous value is held. Then keyframe B is added"*, with a Move in place of
    /// the slider.
    ///
    /// **Persisted, and it is the field that looks like a transient and is not** (§3.5): it is the
    /// state *between* keyframe A and keyframe B, and that gap can span a save. Lose it across a
    /// reopen and placing B writes two identical poses, produces no animation, and puts nothing on
    /// screen to explain why.
    var pendingPoseBaselines: [String: PoseQuad] = [:]

    /// **Where this cel's timeline tile actually lives** — a reference cell rather than a stored
    /// image, and the whole of PERFORMANCE.md §18.6's change. See `ThumbnailTile`, and read
    /// `thumbnail` below as the accessor over it.
    ///
    /// A `let` with a default value, so the memberwise initialiser does not carry it and **every
    /// `Cel(...)` gets a cell of its own**. That is what makes a *duplicate* — a new cel with a new
    /// `id` — start out with its own tile rather than sharing the original's; `duplicateLayer`
    /// assigns the image across afterwards, which is a copy of a picture rather than a shared one.
    let tile = ThumbnailTile()

    /// The 120×120 picture of this cel that the timeline block and the layer rail draw.
    ///
    /// **Reading and writing this touches `tile` and nothing else, so a write publishes nothing.**
    /// `Cel` lives inside `CanvasManager.layers`, which is `@Published`; a *stored* thumbnail made
    /// installing one a mutation of that array, and the SwiftUI pass it raised — the whole editor,
    /// MEASURED at ~43 ms on the owner's iPad — cost far more than the tile did. A `nonmutating`
    /// setter over a class means `layers` is only *read* on the way to the cell (verified by
    /// counting `objectWillChange`, `ThumbnailRenderLogicTests`).
    ///
    /// **So a write here reaches no view by itself.** Go through `CanvasManager.installThumbnail` or
    /// `CanvasManager.clearThumbnail`, which write it and then say so on `thumbnailInstalled` — the
    /// timeline track and the layer rail listen there precisely because no pass will tell them.
    var thumbnail: UIImage? {
        get { tile.image }
        nonmutating set { tile.image = newValue }
    }

    var endFrame: Int { startFrame + frameCount }

    /// **A one-way answer: true means there is certainly nothing to draw; false means "maybe".**
    /// Model state only — no pixel scan, no rasterize — so it is free to ask about every cel in a
    /// layer on every pass, which is what the onion skin does before deciding whether a slot is
    /// worth a canvas-sized draw.
    ///
    /// Conservative in the direction that cannot produce a wrong picture. A cel erased back to
    /// transparency still reports false, because `raster.version` has moved and this cannot tell an
    /// erase from a stroke without looking at pixels — the cost of being sure is exactly the cost
    /// this exists to avoid, and the consequence of being wrong that way is one wasted draw rather
    /// than a missing skin.
    ///
    /// **An `interpolation` recipe is deliberately not consulted, and the reason is worth stating.**
    /// A derived in-between's pixels are computed by `InterpolationEvaluator`, not stored here, so a
    /// `.generate` cel reports blank — which is correct for every consumer that reads the *stored*
    /// tiers, and those are the only consumers this has. Treating a recipe as content instead would
    /// have the onion skin pay a canvas-sized draw to composite nothing.
    var isCertainlyBlank: Bool {
        fillImage == nil && bakedImage == nil
            && raster.strokeCount == 0 && raster.version == 0
            && (vector?.isEmpty ?? true)
    }

    /// **Everything a copy of a cel carries that is not its identity or its place in time** — the
    /// return type of `CanvasManager.copyTiers(of:)`, which is the one place the 2026-09-03 ruling on
    /// copying a derived cel is written down.
    ///
    /// It is a named type rather than a tuple so that the list of fields sits next to the fields it
    /// mirrors. `Cel.transformTracks`' doc comment asks whoever adds a field above to owe three call
    /// sites a line each; two of those three now read this instead, so the debt is one line here and
    /// the compiler collects it.
    ///
    /// **`interpolation` is deliberately absent**, and its absence is the ruling: a copy of an
    /// in-between is a flattened still that stops following the drawings it derived from, so no
    /// copying verb has a recipe to put anywhere. `splitCel` is not a copy — it cuts one span in two
    /// — and does not go through here.
    struct CopyTiers {
        var raster: RasterLayerTexture
        var fillImage: UIImage?
        var bakedImage: UIImage?
        var vector: VectorCanvas?
        var transformTracks: [String: TransformTrack]
        var pendingPoseBaselines: [String: PoseQuad]
    }
}
