import UIKit

struct Layer: Identifiable {
    let id: UUID
    var name: String
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
    /// The grade a `.compositing` layer applies (§4.4), or nil on a layer that draws pixels instead.
    ///
    /// Stored on `Layer` rather than in `LayerKind`'s payload so that flipping a layer's kind cannot
    /// lose it, and so the field decodes with the one `decodeIfPresent` `Effect`'s persistence note
    /// prescribes. `compositingEffect` below is what rendering reads — the kind is what decides
    /// whether this is live, and that decision has one home.
    var effect: Effect? = nil
    /// The flat colour a `.value` layer is (§4.5), or nil on a layer that draws pixels instead.
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

    /// The grade this layer applies to the backdrop beneath it, or nil if it draws pixels instead —
    /// §4.4's stack-layer wrapper, and the *only* place "is this an effect layer" is decided.
    ///
    /// Both halves are required. A `.compositing` layer with no effect yet is one the artist has just
    /// added and not configured, and it must read as a no-op rather than as a missing grade; an
    /// `effect` left on a layer whose kind has since changed back must not silently start grading the
    /// stack. Rendering asks this, never `kind` or `effect` on their own.
    var compositingEffect: Effect? { kind == .compositing ? effect : nil }

    /// The flat colour this layer *is*, or nil if it draws pixels instead (§4.5) — and the **only**
    /// place "is this a value layer" is decided, exactly as `compositingEffect` is for effects.
    ///
    /// Both halves are required, for both of that accessor's reasons. A `.value` layer carrying no
    /// fill at all is one nothing has configured — only reachable from a hand-written manifest, since
    /// `addValueLayer` always stamps one — and it must read as a **no-op**, exactly as a `.compositing`
    /// layer with no grade does, rather than as a colour guessed on its behalf. (The default colour is
    /// applied one level down instead, by `ValueFill`'s own decoder and by `addValueLayer`, so a fill
    /// that exists but omits its colour key is mid-grey while a fill that does not exist is nothing.)
    /// And a `fill` left on a layer whose kind has since changed back must not silently start painting
    /// over the stack. Rendering asks this, never `kind` or `fill` on their own.
    var valueFill: ValueFill? { kind == .value ? fill : nil }

    /// Whether a brush stroke has anywhere to land on this layer.
    ///
    /// **Asked of the `kind`, not of the configuration**, and deliberately: a `.compositing` layer
    /// with no grade yet and a `.value` layer with no fill yet are both still layers a stroke would
    /// disappear into, so this must not flicker as the artist configures one. `compositingEffect` and
    /// `valueFill` answer the *rendering* question and are right to ask both halves; this one is about
    /// the drawing surface, and there is none either way.
    ///
    /// One property rather than a clause repeated at each of `CanvasView`'s three sites (host
    /// interaction, the catch-all gesture's gate, the catch-all's handler) — those three have to agree
    /// or the touch is either swallowed with no feedback or fed to a host that cannot use it, and
    /// three spellings of the same list is how they come to disagree.
    var hasNoDrawingSurface: Bool { kind == .compositing || kind == .value }
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
    /// pixels inside `renderSources(atFrame:)`, which already takes the frame and already exists to
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
