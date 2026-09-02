import UIKit

struct Layer: Identifiable {
    let id: UUID
    var name: String
    /// Whether `name` above is the artist's own answer, or one the model wrote for them.
    ///
    /// **`fillReferenceOverride` below is the precedent, and this is the same problem in a second
    /// place**: a value nobody has chosen must be distinguishable from a value somebody *has*, or the
    /// recompute clobbers the choice. §4.4's value layer renames itself as its mode changes — pick
    /// Gaussian Blur and the row reads "Gaussian Blur", go back to a flat colour and it reads "Value
    /// n" again — because the row is the only place an artist reads their stack at a glance and a row
    /// labelled "Value 3" on something that is actually a blur is the state `LayerStackCell.title(for:)`
    /// exists to prevent. But a layer the artist has *named*, deliberately, from the Rename action, is
    /// not the model's to overwrite: that is real data loss, performed silently by a dropdown, and it
    /// is exactly the failure `fillReferenceOverride` was introduced to stop happening to a Bool.
    ///
    /// **A flag rather than `fillReferenceOverride`'s optional**, because the two shapes answer
    /// different-shaped questions. There is no "no name" state to model — every layer has one and
    /// always has — so the thing that needs recording is not the value but its *provenance*, and
    /// `String?` would have meant "unnamed", which is not a state the panel can render.
    ///
    /// False by default, so every existing `Layer(...)` call site is unchanged and every project saved
    /// before this field decodes to "never named by hand". That last part is a real, bounded
    /// concession: a value layer an artist hand-named in an earlier build reloads as auto-nameable and
    /// will be renamed the first time they change its mode. Bounded because that is the only edit that
    /// renames anything, and because the flag is set the moment they rename it again. The alternative —
    /// inferring provenance by testing the stored name against what the generator would have produced —
    /// is the recompute-over-a-decision trap wearing a different hat: it guesses, and it guesses wrong
    /// for the artist who deliberately types "Value 2".
    var hasCustomName: Bool = false
    var opacity: Double
    var isVisible: Bool
    /// The artist's own answer to "is this layer a fill boundary", or nil for "never asked" (§6.6).
    ///
    /// The distinction is the whole of the rule: a layer nobody has decided about follows the
    /// default, which tracks visibility, so hiding a layer drops it as a boundary and showing it
    /// brings it back. A layer somebody *has* decided about keeps that decision through every
    /// visibility change, including while hidden — a choice the artist made is not the model's to
    /// recompute. Without the nil case the two are indistinguishable and the recompute clobbers the
    /// choice, which is exactly what this used to do.
    var fillReferenceOverride: Bool? = nil
    /// Whether this layer's content contributes to the fill tool's boundary walls. The fill uses the
    /// union of all layers with this set (see `CanvasManager.fillReferenceSources`).
    /// See [[feedback-vector-layer-extensibility]].
    ///
    /// **The default is visibility for every kind but `.value`, and that exception is the point.** A
    /// value layer is one opaque colour across the entire canvas, so a visible one following the
    /// ordinary default would become a boundary wall *everywhere in the document* — the fill tool
    /// would refuse to spread anywhere, with nothing on screen saying why, and the layer that caused
    /// it is the one layer in the stack with no drawn content to blame. So the answer nobody has been
    /// asked for is "no" rather than "whatever the eye says".
    ///
    /// An explicit `fillReferenceOverride` still wins, exactly as it does for every other kind: this
    /// changes what "never asked" resolves to (§6.6's whole distinction), not whether the artist may
    /// answer.
    var isFillReference: Bool { fillReferenceOverride ?? (kind == .value ? false : isVisible) }
    var kind: LayerKind = .raster
    /// The grade a `.value` layer in **effect mode** applies (§4.4), or nil on a layer that draws
    /// pixels — and, on a `.value` layer, **the field whose presence decides the mode**.
    ///
    /// A value layer is one of two things and never both: an effect that grades the backdrop beneath
    /// it, or one flat colour. The discriminant is this field being non-nil, which is exactly the
    /// recipe `LayerFolder.effect` already uses for the folder form and `alphaMask`/`compositorRole`
    /// use for theirs — optional, absent means "not one". A third `mode` enum beside these two
    /// payloads was the alternative and was rejected: it is a second answer to a question the payloads
    /// already answer, so every write has to keep two fields in step and every read has to decide
    /// which one wins when they disagree. A document cannot say "effect mode, no effect".
    ///
    /// Stored on `Layer` rather than in `LayerKind`'s payload so that flipping a layer's kind cannot
    /// lose it, and so the field decodes with the one `decodeIfPresent` `Effect`'s persistence note
    /// prescribes. `layerEffect` below is what rendering reads — the kind is what decides whether this
    /// is live, and that decision has one home.
    var effect: Effect? = nil
    /// **The keyframe tracks driving this layer's effect parameters** — KEYFRAMES.md §8 stage 2 —
    /// keyed by `EffectParameter.id` and evaluated in **absolute document frames**.
    ///
    /// §2.4 is the ruling and §3.1 is the arithmetic behind it. An *object* channel rides a cel and is
    /// therefore stored in cel-local frames, so it survives move, split, duplicate and paste for free.
    /// A layer channel has no cel to ride: the grade is a property of the layer at every frame of the
    /// document, including frames on which this layer has no block at all, so there is no `startFrame`
    /// to be an offset from and a key's frame is the playhead's own number.
    ///
    /// **Keyed by the descriptor's stable string, not by a key path, a field name or an index.**
    /// `EffectParameter.id` is documented as *the persisted address, and the one field there that must
    /// never change*; it is already decoupled from the Swift property name in two places
    /// (`hsvShift.hue` addresses `hueDegrees`, `blur.angle` addresses `angleDegrees`). Storing anything
    /// else here would make a saved document depend on a rename or on the order of a `switch`.
    ///
    /// **Empty by default, so every existing `Layer(...)` call site and every saved manifest is
    /// unchanged by this field arriving** — `effect`'s and `fill`'s recipe, one field over, and
    /// `LayerManifest.effectTracks` writes no key for an empty one.
    ///
    /// **This layer's tracks are exactly the ones its current effect can drive.** Changing the effect
    /// destroys the rest, so a channel never outlives the grade it addressed.
    ///
    /// A curve whose id no current parameter names is storage the artist has no way to reach: the
    /// timeline's channel list is built from the current effect's descriptors
    /// (`CanvasManager.curvedEffectChannelIDs`), so it is invisible, uneditable and undeletable,
    /// and it is written into every saved copy of the document all the same. It renders nothing, and
    /// the artist meets it again only by accident.
    ///
    /// `valueFill`'s asymmetry one field over does **not** extend to it, and the difference is what
    /// makes each right: a fill is one value the artist chose and can see the instant they flip back,
    /// while a track is a whole channel that has already left the timeline. Keeping the first restores
    /// a choice; keeping the second is hoarding.
    ///
    /// **The rule is by parameter id, not by effect case** — `Effect.tracksAddressed(by:from:)` is the
    /// one place it is written, and the four writers in `CanvasManager` that touch `effect` all call
    /// it. So flipping `Blur.isDirectional`, which is one `.blur` case wearing two artist-facing
    /// names, keeps `blur.radius` and `blur.angle`; Levels → Curves keeps nothing.
    var effectTracks: [String: AnimationCurve] = [:]
    /// **The frames on which the artist has placed a keyframe on this layer** — KEYFRAMES.md §2.26,
    /// the 2026-08-29 workflow. Sorted, unique, **absolute document frames**, the same time base
    /// `effectTracks` uses and for §2.4's reason.
    ///
    /// **A mark with no channel is legal and is the whole point.** The owner's ruling is that adding
    /// a keyframe saves nothing by itself — *"keyframe A is added, nothing is saved"* — so a mark is a
    /// bare point in time that acquires channels lazily, when a later mark lands with a held baseline
    /// to commit (`CanvasManager.addKeyframe(_:atFrame:)`). Storing marks apart from the curves is
    /// what makes that possible: a curve cannot represent "the artist marked this frame and has not
    /// yet changed anything".
    ///
    /// **Not derivable from `effectTracks`.** A key's frame and a mark are different facts: a curve
    /// carries keys the artist never placed a mark on (an auto-key at the playhead, a seeded
    /// neighbour), and a mark carries no key at all until something changes. Deriving one from the
    /// other in either direction loses the distinction the workflow is built on.
    ///
    /// Empty by default, so every existing `Layer(...)` call site and every saved manifest is
    /// unchanged by this field arriving — `effectTracks`' recipe, one field up.
    var keyframeMarks: [Int] = []
    /// **The value each channel held *before* the artist's first edit since the last mark** — the
    /// owner's *"the previous value is held"*, keyed by `EffectParameter.id` like `effectTracks`.
    ///
    /// **Written once per channel per keyframe-placement cycle**, by the first edit after a mark;
    /// later tweaks in the same cycle must not overwrite it, because the first one is the only one
    /// that knows the value at A. Consumed and cleared by the next `addKeyframe`.
    ///
    /// **The edit still writes the stored base as it always did.** A provisional edit that is never
    /// committed is lost work and makes one slider mean two things depending on invisible state; this
    /// records the old value *beside* the ordinary write instead of replacing it.
    ///
    /// **Persisted, and that is not incidental.** Saving and reopening between keyframe A and
    /// keyframe B would otherwise produce two identical keys and no animation — a wrong result with
    /// nothing on screen to explain it.
    var pendingBaselines: [String: Double] = [:]
    /// The flat colour a `.value` layer is in **flat-colour mode** (§4.5), or nil on a layer that
    /// draws pixels instead.
    ///
    /// Not a discriminant, unlike `effect` above: it is read only once `effect` has already said the
    /// layer is in flat-colour mode, so a fill sitting on a layer that is currently grading is inert
    /// storage rather than a contradiction. That asymmetry is the whole of the mode flip — see
    /// `layerEffect` for what it buys.
    ///
    /// Stored on `Layer` beside `effect` and for its reasons, which are the same two: flipping a
    /// layer's kind cannot lose it, and it decodes with the one `decodeIfPresent` recipe the
    /// persistence note prescribes — so every existing `Layer(...)` call site and every saved manifest
    /// is unchanged by this field arriving. `valueFill` below is what rendering reads.
    var fill: ValueFill? = nil
    /// How this layer combines with everything beneath it *within its own container* — a layer inside
    /// a group blends against that group's contents, not through it, which is what §4.2's isolation
    /// means from the layer's side. Defaulted, so every existing project and every `Layer(...)` call
    /// site is unchanged.
    var blendMode: BlendMode = .normal
    /// Where this layer is allowed to show, clipped to the alpha of other layers or groups (§6.2).
    /// Nil — the default, and what a manifest without the key decodes to — is "no mask"; the mask is
    /// never baked into the pixels, so clearing it restores the whole buffer (§6.1).
    var alphaMask: AlphaMask? = nil
    /// If set, this layer belongs to the folder with this ID. Layer ordering in the `layers` array
    /// determines the stacking order within each folder. A folder's visibility/expand state lives on
    /// the corresponding `LayerFolder` in `CanvasManager.folders`.
    var parentFolderID: UUID? = nil
    var cels: [Cel]
    var thumbnail: UIImage? = nil
}

extension Layer {

    /// The grade this layer applies to the backdrop beneath it, or nil if it draws pixels or is a flat
    /// colour instead — §4.4's stack-layer wrapper, and the *only* place "is this layer an effect" is
    /// decided.
    ///
    /// **`layerEffect` rather than the old `compositingEffect`**, because there is no longer a
    /// `.compositing` kind for the name to refer to: §4.4's wrapper is now one of the two modes of a
    /// `.value` layer, chosen by whether `effect` is there. The old name outlived the thing it named,
    /// which is how an accessor comes to be read as a kind test by people who never look at it.
    ///
    /// Both halves are still required, and for the reasons they always were. A `.raster` layer that
    /// once carried a grade and has since been changed back must not silently start grading the stack;
    /// and a `.value` layer with no effect is not "an effect that does nothing", it is the *other*
    /// mode, which `valueFill` answers. Rendering asks this, never `kind` or `effect` on their own.
    var layerEffect: Effect? { kind == .value ? effect : nil }

    /// **The grade at one frame — the function KEYFRAMES.md stage 2 filled in.**
    ///
    /// It was `layerEffect` above with the frame ignored until stage 2; it is now that effect with
    /// every keyed parameter evaluated at `frame` and written back through the descriptor table's own
    /// lens (`Effect.resolved(atFrame:through:)`). A layer with no track still returns the stored
    /// value untouched, by the one `guard` at the top of that method, so nothing about a document
    /// nobody has animated moves — which is half of what
    /// `RenderTreeCharacterizationTests` now pins, the other half being that a document somebody
    /// *has* animated genuinely differs between two frames.
    ///
    /// The seam was cut one stage earlier, and the argument for cutting it early was
    /// exactly `ValueFill.resolvedColor(atFrame:)`'s one field over. The grade reaches the
    /// compositor through `RenderNode.effect`, which
    /// `CanvasManager.renderNodes(inContainer:atFrame:)` fills in from here; that derivation now takes
    /// the frame, so **the compositor never learns that a grade can be animated** — it receives an
    /// `Effect` like any other node's. Resolving further in (in `Compositor.draw`, or by giving
    /// `RenderNode` a track instead of a value) would put the constant somewhere the frame is not in
    /// scope, and a keyframe phase would then have to cut this seam under a deadline instead of
    /// finding it already cut.
    ///
    /// **The non-frame `layerEffect` stays, and the split between the two is a rule rather than an
    /// accident.** Everything on a *rendering* path asks this one, because a grade the artist animated
    /// must be the grade at the frame being drawn — the tree's leaf derivation, `leafSnapshots`'
    /// elision of a leaf that holds no pixels, and both content-version builders, all of which have a
    /// frame in hand and are documented as mirrors of each other. Everything on a *panel* path asks
    /// the property — `LayerPanel`'s effect row, `LayerStackListView`'s badge, `DrawingView`'s
    /// host-interaction gate — because "is this layer in effect mode" is a question about the layer
    /// and there is no playhead in the answer. That division holds only for as long as a track cannot
    /// turn a grade *on or off* at a frame, at which point the panel questions become genuinely
    /// ambiguous rather than merely frame-free; `CanvasManager.compositorSizeGate` is the other place
    /// the same assumption is load-bearing, and it says so at length.
    ///
    /// **Stage 2 did not spend that assumption, and could not have.** `effectTracks` drives parameter
    /// *values*; presence is decided one line up by `layerEffect`, which reads `kind` and `effect` and
    /// knows nothing about a track. The optional-chain below is the whole of the guarantee: a nil
    /// grade resolves to nil at every frame and a non-nil one stays non-nil, because
    /// `Effect.resolved(atFrame:through:)` takes an `Effect` and returns an `Effect` with no arm that
    /// could return nil. Turning a grade on or off at a frame would be a *different* channel — a
    /// presence channel — and it is that one, not this, that expires the two notes above.
    func layerEffect(atFrame frame: Int) -> Effect? {
        layerEffect?.resolved(atFrame: frame, through: effectTracks)
    }

    /// The flat colour this layer *is*, or nil if it draws pixels or is grading instead (§4.5) — and
    /// the **only** place "is this layer a flat colour" is decided, exactly as `layerEffect` is for
    /// effects. The two are mutually exclusive by construction: both read the same `effect` field, one
    /// for its presence and one for its absence, so no document and no in-memory state can make both
    /// answer non-nil.
    ///
    /// All three halves are required. `kind == .value` for `layerEffect`'s reason — a `fill` left on a
    /// layer whose kind has since changed back must not start painting over the stack. `effect == nil`
    /// because that is what flat-colour mode *is*. And a non-nil `fill`, because a `.value` layer
    /// carrying none is one nothing has configured — only reachable from a hand-written manifest,
    /// since `addValueLayer` always stamps one — and it must read as a **no-op** rather than as a
    /// colour guessed on its behalf. (The default colour is applied one level down instead, by
    /// `ValueFill`'s own decoder and by `addValueLayer`, so a fill that exists but omits its colour key
    /// is mid-grey while a fill that does not exist is nothing.)
    ///
    /// **The mode flip is deliberately asymmetric, and this accessor is why.** Going *to* flat colour
    /// clears `effect`, because `effect`'s presence is the discriminant and leaving it set would leave
    /// the layer in effect mode however the panel labelled it. Going *to* an effect keeps `fill`,
    /// because `fill` is not a discriminant — nothing reads it while `effect` is set — so keeping it
    /// costs one inert field and buys the round trip: flip to an effect, flip back, and the colour the
    /// artist mixed is still there. Clearing it instead would be a silent destructive edit performed by
    /// a mode picker, which is the one thing a mode picker must not do.
    var valueFill: ValueFill? { kind == .value && effect == nil ? fill : nil }

    /// Whether a brush stroke has anywhere to land on this layer.
    ///
    /// **Asked of the `kind`, not of the configuration**, and deliberately: a `.value` layer with no
    /// grade and no fill yet is still a layer a stroke would disappear into, so this must not flicker
    /// as the artist configures one — nor as they flip between the two modes, since neither holds
    /// pixels. `layerEffect` and `valueFill` answer the *rendering* question and are right to ask more
    /// than the kind; this one is about the drawing surface, and there is none in any configuration.
    ///
    /// One kind rather than the two this used to name: §4.4's effect layer stopped being a kind of its
    /// own and became a mode of this one, so the clause it contributed went with it rather than being
    /// preserved as a test that can no longer be true.
    ///
    /// One property rather than a clause repeated at each of `CanvasView`'s three sites (host
    /// interaction, the catch-all gesture's gate, the catch-all's handler) — those three have to agree
    /// or the touch is either swallowed with no feedback or fed to a host that cannot use it, and
    /// three spellings of the same list is how they come to disagree.
    var hasNoDrawingSurface: Bool { kind == .value }
}

// MARK: - §4.5's value layer

/// The flat colour a `.value` layer is: one colour across the whole canvas, **alpha included**.
///
/// A colour rather than a bare 0–1 number, which is the owner's first decision on this feature: a grey
/// *is* a colour, so this covers the scalar case a Mix node wants, and the same layer doubles as a
/// flat background or a tint.
///
/// **A struct rather than a bare `PaletteColor`, and that is the whole of the keyframe seam.** The
/// owner wants this animatable eventually and explicitly does not want keyframes built now, so this
/// phase builds the constant and cuts the seam where a later phase can use it: keyframe storage goes
/// *inside* this type, `resolvedColor(atFrame:)` starts reading it, and nothing outside changes. A
/// bare colour field on `Layer` would have to be found and rewritten at every call site instead.
struct ValueFill: Equatable, Hashable {

    /// The colour, alpha included.
    ///
    /// `PaletteColor` rather than a second colour representation: it is already `Codable`, and its hex
    /// round-trips through the same `ColorMath`/`ColorConversion` path every swatch in the app does —
    /// so a fill saved and reloaded is exactly the colour that was picked, including a non-opaque one
    /// (the 8-digit `RRGGBBAA` form).
    var color: PaletteColor = ValueFill.defaultColor

    /// **Mid-grey at full alpha.** A value layer at the top of the stack makes the canvas one flat
    /// colour — correct, and what Photoshop's Solid Colour layer does — so the default has to read as
    /// deliberate rather than as a crash on first add. Mid-grey is also the useful constant for the
    /// Mix-node case this feature exists for: `Mix(artwork, grey 50%, .multiply)` halves the artwork.
    static let defaultColor = PaletteColor(hex: "808080")

    /// **The colour at one frame, and the one function a later keyframe phase changes.**
    ///
    /// Constant today, and deliberately still stated as a function of the frame. The fill becomes
    /// pixels inside `leafSnapshots(atFrame:)`, which already takes the frame and already exists to
    /// turn "one layer" into "one layer's pixels at one frame" — so **the compositor never learns that
    /// value layers exist**; it receives a source like any other leaf's. Resolving further in (in
    /// `Compositor.draw`, or by giving `RenderNode` a colour field) would put the constant somewhere
    /// the frame is not in scope, and a keyframe phase would then have to cut this seam under a
    /// deadline instead of finding it already cut.
    func resolvedColor(atFrame frame: Int) -> PaletteColor { color }
}

// MARK: Persistence
//
// `Effect`'s recipe, unchanged: the owner declares `var fill: ValueFill?`, decodes it with
// `decodeIfPresent` (nil means "no fill", which is also what every project saved before value layers
// existed says) and encodes it only when it is there — so a document with no value layer in it is
// byte-for-byte the manifest it was. Nothing needs a migration and nothing reads an *absence* as a
// signal.

extension ValueFill: Codable {

    private enum CodingKeys: String, CodingKey { case color }

    /// Hand-written decode, synthesized encode — the asymmetry every parameter struct in `Effect.swift`
    /// already has, for its reason: a synthesized *decoder* demands every key, so a property's default
    /// is not a fallback for a missing one, and a field added by a later phase (a keyframe track, say)
    /// must be absent rather than fatal in every document written before it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(PaletteColor.self, forKey: .color) ?? ValueFill.defaultColor
    }
}
