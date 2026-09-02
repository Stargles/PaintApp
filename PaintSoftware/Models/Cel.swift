import UIKit

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
    /// sites a line each**; cel-local numbering is what makes the line a copy rather than a
    /// conversion, which is the part that really is free.
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
    var thumbnail: UIImage? = nil

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
}
