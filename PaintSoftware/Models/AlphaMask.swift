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

    /// The model object this names, whichever kind it is — every cycle and lifecycle rule below is
    /// stated over ids rather than over kinds.
    var id: UUID {
        switch self {
        case .layer(let id), .folder(let id): return id
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

    // MARK: - The tunables (§6.3, §10 item 1)

    /// **The coverage test, tuned once there was something to look at.** `mask = sourceAlpha >
    /// threshold`.
    ///
    /// It cannot be `alpha > 0`: the default brush is `softRound`, whose dab is a radial gradient
    /// falling to alpha ≈ 0 across its whole radius, so `> 0` would keep every pixel the dab touched
    /// however faintly. A threshold still excludes that faintest skirt — but 0.1 is not a derived
    /// number, it is what the product owner judged by eye on the iPad, against a soft brush, in a
    /// Release build. It replaced 0.5, the pre-hardware reasoned guess that this comment used to
    /// defend as "the visually solid part of a stroke"; measurement on a screen disagreed; the number
    /// is now the one the owner picked, not the one the reasoning predicted. `MaskParityLogicTests.
    /// testTheThresholdExcludesOnlyTheFaintestSkirtOfASoftDab` is the measurement behind that
    /// sentence rather than a restatement of it. Still reduces to `> 0` for a hard brush either way.
    ///
    /// MASK-TUNE (temporary, see `MaskTuningOverlay.swift`): `var` rather than `let` only so the
    /// on-iPad tuning harness can scrub it live. The shipping default is now 0.1; nothing but that
    /// overlay ever writes here. `didSet` bumps `tuningGeneration` — see its doc comment for why that
    /// is load-bearing rather than decoration. Revert to `let` (and delete `tuningGeneration`) when
    /// the harness is deleted.
    static var threshold: Float = 0.1 { didSet { tuningGeneration += 1 } }

    /// Half-width of the smoothstep across `threshold`, in alpha units — **antialiasing only**.
    ///
    /// A hard boolean edge stair-steps on diagonals; a ramp wide enough to fix that must still be
    /// narrow enough not to reintroduce the source's own falloff, which is the whole point of the
    /// threshold. 0.01 is narrower than the 0.05 this replaced — the same on-iPad judgement that moved
    /// `threshold` down to 0.1 also pulled this in, so the resolved edge sits nearer a hard boolean
    /// than the original reasoning here anticipated. Widen this and the mask starts inheriting the
    /// brush's own ramp, which is the failure §6.3 names.
    ///
    /// MASK-TUNE (temporary): same story as `threshold` above — `var` only for the harness, shipping
    /// default now 0.01, `didSet` bumps `tuningGeneration`.
    static var antialiasHalfWidth: Float = 0.01 { didSet { tuningGeneration += 1 } }

    /// MASK-TUNE (temporary): **this is what makes the harness's cache invalidation real rather than
    /// assumed.** `MaskResolver.CacheKey` keys on `AlphaMask`'s *stored* properties (`sources`,
    /// `isEnabled`, `invert`) plus content versions — `threshold`/`antialiasHalfWidth` are statics,
    /// not stored properties, so mutating them changes nothing the cache key can see on its own. This
    /// counter is folded into that key (see `MaskResolver.swift`) so a slider write invalidates every
    /// cached resolution instead of a `clearCache()` call the UI has to remember to make.
    /// `MaskParityLogicTests.testMutatingTheTuningThresholdInvalidatesTheMaskCache` is the regression
    /// this closes. Costs the shipping path nothing — it never moves off 0 there. Delete alongside
    /// the two tunables above.
    private(set) static var tuningGeneration: Int = 0

    /// The resolved coverage for one source alpha: the threshold test, softened only across the
    /// narrow band above, then inverted if asked.
    ///
    /// **Written here rather than in either backend** because it is the definition of the mask, and
    /// both backends consume the bytes it produces rather than computing them (see `MaskResolver`,
    /// which resolves through the CoreGraphics reference for both).
    func coverage(forSourceAlpha alpha: Float) -> Float {
        let low = Self.threshold - Self.antialiasHalfWidth
        let high = Self.threshold + Self.antialiasHalfWidth
        let t = min(max((alpha - low) / (high - low), 0), 1)
        let smooth = t * t * (3 - 2 * t)
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
        }
    }
}

extension AlphaMask: Codable {

    private enum CodingKeys: String, CodingKey { case sources, isEnabled, invert }

    /// Every field `decodeIfPresent`, so a manifest written with only some of them still loads —
    /// the same rule `FolderManifest` follows, and the reason §4.1 could defer this field to phase 6
    /// at no migration cost. The *absent* case is handled a level up: `LayerManifest` and
    /// `FolderManifest` decode a missing `alphaMask` key as nil, which is "no mask".
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decodeIfPresent([MaskSource].self, forKey: .sources) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        invert = try container.decodeIfPresent(Bool.self, forKey: .invert) ?? false
    }
}
