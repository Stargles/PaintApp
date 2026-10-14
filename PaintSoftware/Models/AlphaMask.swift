import Foundation

// MARK: - Alpha masks
//
// LAYER_COMPOSITING.md §6. **The mask is resolved at render time and never written into the masked
// layer's pixels** (§6.1) — the layer keeps its full buffer and the compositor multiplies its alpha
// by the resolved coverage when it draws. That is what makes "mask on → draw → change the source →
// draw again" re-clip *all* the content rather than only the ink laid down since, and it is why
// raster and vector need one implementation instead of two that agree (`MaskParityLogicTests`).
//
// Nothing here is per-layer storage of pixels: a mask is a list of *sources*, and the coverage it
// resolves to is cached once per distinct mask and shared by every layer using it
// (`MaskResolver`). So a second layer masked the same way costs three UUIDs, not a canvas.

/// One thing a mask clips to. A group is a legal source, which "select other layers **or groups**"
/// (§6.2) implies in both directions — a group can be masked *and* be a mask.
enum MaskSource: Hashable {
    case layer(UUID)
    case folder(UUID)
    /// **A layer's own ink, read as an amount rather than a clip** — TODO (92), EFFECT_BACKDROP.md
    /// §2.4: a vector layer's grade acts on the composite beneath it through the layer's rendered
    /// alpha times its opacity, so the alpha is the coverage *as it is* — no §6.3 threshold, a soft
    /// brush's skirt grades softly — where a `.layer` source is thresholded into a clip.
    ///
    /// **Minted by `RenderTree.renderNodes` alone, onto the grading node's own masks, and never by
    /// the panel**: an artist cannot name one, so no document writes one and none decodes one. It
    /// resolves through the same stack machinery as the other two (`RenderRequest.maskSourceStacks`
    /// builds the layer as a pixel leaf without its grade, since the grading node itself has no
    /// source to composite; the layer's opacity reaches the grade through the mix's own
    /// `opacity × coverage`), which is what lets `MaskResolver`'s cache and both backends' `mix`
    /// handle it with no new branch.
    case ink(UUID)

    /// The model object this names, whichever kind it is — every cycle and lifecycle rule below is
    /// stated over ids rather than over kinds.
    var id: UUID {
        switch self {
        case .layer(let id), .folder(let id), .ink(let id): return id
        }
    }

    /// Whether this source's alpha is the coverage itself (`.ink`) rather than the shape a clip is
    /// cut from (`.layer`, `.folder`, which `MaskResolver` puts through `AlphaMask.coverage`).
    var isAmount: Bool {
        switch self {
        case .ink: return true
        case .layer, .folder: return false
        }
    }
}

/// §6.2's model, on both `Layer` and `LayerFolder`.
struct AlphaMask: Hashable {

    /// Unioned, not intersected: composite each source's subtree, take its alpha, `max` across them
    /// (§6.2). Order is preserved for the UI's benefit; `max` does not care about it.
    var sources: [MaskSource] = []

    /// The §6.5 toggle. Separate from `sources` being empty so that turning a mask off keeps the
    /// selection to turn back on — except in the one case §6.6 names, where the *last* source is
    /// deleted out from under it and the mask disables itself (`dropping(_:)`).
    var isEnabled: Bool = true

    /// Flips the resolved result, after the union and after the threshold.
    var invert: Bool = false

    /// Whether this mask clips anything at all. An enabled mask with no sources is not a mask that
    /// hides everything — it is no mask, and the layer renders unmasked (§6.6).
    var isActive: Bool { isEnabled && !sources.isEmpty }

    /// Empty reads source alpha; otherwise only these colours on the chosen sources contribute.
    var colours: [ColourKey] = []
    private(set) var threshold: Float = 0.1
    private(set) var antialiasHalfWidth: Float = 0.01
    static let minimumTuningGap: Float = 1 / 255

    /// A value owned by this mask, so a held recipe and a background render read the same pair.
    mutating func setTuning(threshold requestedThreshold: Float, antialiasHalfWidth requestedWidth: Float) {
        let wantedThreshold = requestedThreshold.isFinite ? requestedThreshold : threshold
        let wantedWidth = requestedWidth.isFinite ? requestedWidth : antialiasHalfWidth
        threshold = min(max(wantedThreshold, Self.minimumTuningGap), 1)
        antialiasHalfWidth = min(max(wantedWidth, 0), threshold - Self.minimumTuningGap)
    }

    func coverage(forSourceAlpha alpha: Float) -> Float {
        let low = threshold - antialiasHalfWidth
        let high = threshold + antialiasHalfWidth
        let smooth: Float
        if high > low {
            let t = min(max((alpha - low) / (high - low), 0), 1)
            smooth = t * t * (3 - 2 * t)
        } else {
            smooth = alpha > threshold ? 1 : 0
        }
        return invert ? 1 - smooth : smooth
    }

    // MARK: - Lifecycle (§6.6)

    /// This mask with `source` gone — what a layer or folder deletion leaves behind.
    ///
    /// Emptying the list **disables the mask** rather than leaving an enabled one with nothing to
    /// clip to, so the layer renders unmasked and the §6.5 toggle reads off. Consistent with
    /// `resolvedContainer(ofFolder:)` treating a missing parent as "no parent" rather than vanishing
    /// the layer; and since every deletion already runs inside `withStructureUndo`, one undo restores
    /// the source and the mask that pointed at it together.
    func dropping(_ source: MaskSource) -> AlphaMask {
        var copy = self
        copy.sources.removeAll { $0 == source }
        if copy.sources.isEmpty { copy.isEnabled = false }
        return copy
    }
}

// MARK: - Persistence
//
// Hand-written rather than synthesized for `MaskSource`, which is the only enum with a payload in
// the manifest: the synthesized form of a payload case is `{"layer":{"_0":"…"}}`, a shape whose key
// is a compiler implementation detail rather than a format anyone would choose to migrate later.

extension MaskSource: Codable {

    private enum CodingKeys: String, CodingKey { case kind, id }
    /// `.ink` is not here: it is minted onto a render node and never onto a `Layer` or a
    /// `LayerFolder`, so no manifest carries one (`MaskSource.ink`'s doc). Encoding one is a
    /// caller's mistake and is said so rather than written as a kind a decoder would then need.
    private enum Kind: String, Codable { case layer, folder }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .layer:  self = .layer(id)
        case .folder: self = .folder(id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .layer(let id):
            try container.encode(Kind.layer, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .folder(let id):
            try container.encode(Kind.folder, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .ink:
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "A MaskSource.ink is a render node's, never a document's"))
        }
    }
}

extension AlphaMask: Codable {
    private enum CodingKeys: String, CodingKey {
        case sources, isEnabled, invert, colours, threshold, antialiasHalfWidth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = try c.decode([MaskSource].self, forKey: .sources)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        invert = try c.decode(Bool.self, forKey: .invert)
        colours = try c.decode([ColourKey].self, forKey: .colours)
        threshold = try c.decode(Float.self, forKey: .threshold)
        antialiasHalfWidth = try c.decode(Float.self, forKey: .antialiasHalfWidth)
        guard colours.count <= Effect.maxRecolorEntries, threshold.isFinite,
              threshold >= Self.minimumTuningGap, threshold <= 1,
              antialiasHalfWidth.isFinite, antialiasHalfWidth >= 0,
              antialiasHalfWidth <= threshold - Self.minimumTuningGap else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid mask tuning or colour count"))
        }
    }
}
