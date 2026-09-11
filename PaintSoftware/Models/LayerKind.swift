import Foundation

/// The four layer kinds. `.raster` (ordinary brush-stroke drawing) and `.vector` (brush
/// strokes/images stored as resolution-independent geometry — move/rotate/scale without quality
/// loss, re-rasterized on demand) hold pixels. The other two hold none.
///
/// `.value` is **two things chosen by one field**. With `Layer.effect` set it is §4.4's stack-layer
/// wrapper — Photoshop's adjustment layer — grading everything accumulated below it *within its own
/// container*. With `Layer.effect` absent it carries `Layer.fill` and *is* one flat colour across the
/// whole canvas — Photoshop's Solid Colour layer. `Layer.layerEffect` and `Layer.valueFill` are the
/// two accessors that read the mode out; nothing else asks.
///
/// **One kind with two modes rather than two kinds**, and that is the owner's call rather than a
/// tidying. The two never coexist on one layer — an adjustment layer that is also a flat colour is
/// not a picture anyone can describe — so a kind apiece made the mutually-exclusive pair expressible
/// twice, once as `kind` and once as which payload happened to be set, with nothing keeping them
/// honest. It also made "change this layer from a grade to a colour" a kind rewrite, which every
/// `kind ==` test in the app has an opinion about, instead of the one-field edit it now is.
///
/// `.transform` is **the transformation layer, and it is a kind of its own** — TRANSFORM_LAYER.md
/// §2 ruling 2 (2026-09-11), which reversed the recipe above for this one payload. It was the
/// *third mode* of `.value` from KEYFRAMES §4.4 until then, chosen by `Layer.transform` being
/// present, and the owner asked for *"its own layer type instead of attached to the value layer"*
/// because the two are not two answers to one question the way a grade and a colour are: a value
/// layer contributes pixels or a grade to the composite, and a transform layer contributes
/// nothing to it at all — its whole effect is spent in `RenderTree.renderNodes`' walk on the
/// entries beneath it. `Layer.transform` is its payload and `Layer.layerTransform` the accessor;
/// the five modes TRANSFORM_LAYER.md §5 specifies arrive on this kind, not on `.value`.
///
/// The flat colour exists to be an operand: `Mix(A, B, .multiply)` where A and B are single layers is
/// identical to stacking B over A with Multiply (`RenderTree.swift` says so), so a value layer is the
/// honest answer to "why use a node at all" — `Mix(folder-of-drawings, grey 50%, .multiply)` combines
/// the folder as a unit and *then* halves it, which a flat stack cannot express. It also blends with
/// what is beneath it like any other leaf, which is the flat-background and tint case.
///
/// **Three exhaustive `switch`es over this enum exist, and they are what made the fourth case
/// answer at compile time**: `Tool.textUnavailableReason(onLayerOfKind:)`,
/// `CanvasManager.selectionMembershipUnavailableReason` and `CanvasActiveLayer.init(kind:)` — plus
/// `holdsPixels` below, which is the one every other reader should ask instead of `kind == .value`.
/// `LayerKindLogicTests` walks `allCases` through each of them so a fifth case cannot arrive with
/// a site left answering for four.
enum LayerKind: String, Codable, Equatable, CaseIterable {
    case raster
    case vector
    case value
    case transform
}

extension LayerKind {

    /// Whether a layer of this kind holds pixels — somewhere for a stroke, a fill or a piece of text
    /// to land, something for the onion skin to draw, alpha for the fill tool's boundary.
    ///
    /// **The question every reader used to spell as `kind == .value`**, which was one kind's name
    /// standing in for a property and stopped being true the day a second pixel-less kind arrived.
    /// A `switch` rather than a comparison so that the next kind has to say which side it is on.
    var holdsPixels: Bool {
        switch self {
        case .raster, .vector: return true
        case .value, .transform: return false
        }
    }
}

extension LayerKind {

    /// **The whole of the effect-layer migration, written as a line someone can find.**
    ///
    /// Until §4.4's wrapper became a mode of `.value`, an effect layer was its own kind and every
    /// project holding one has the literal string `"compositing"` in its layer's `kind` field. Read
    /// that string as `.value` and the same document reopens as the layer it always was: the grade is
    /// already sitting in the manifest's own `effect` key, decoded on the next line by the
    /// `decodeIfPresent` every optional payload here uses, and a non-nil `effect` on a `.value` layer
    /// *is* effect mode. Nothing else in the document needs touching — the layer had no `fill` to
    /// conflict with, its cel was already blank and unrendered, and `hasNoDrawingSurface` answered
    /// true for the old kind exactly as it does for the new one.
    ///
    /// **Without this the whole project fails to open, silently.** `LayerKind` is a bare
    /// `String, Codable` enum with a synthesized raw-value decoder, and `decodeIfPresent` substitutes
    /// its default only when the key is *absent* — a key that is present and unparseable throws
    /// `DecodingError.dataCorrupted`. That throw escapes `LayerManifest.init(from:)`, escapes
    /// `JSONDecoder.decode(ProjectManifest.self, …)`, and lands in `ProjectStore.loadManifest`'s
    /// `try?`, which turns it into nil; `ProjectStore.load(from:)` then returns nil for the *entire*
    /// document. Not one lost layer — the artist's project simply refuses to open, with no error
    /// anywhere saying why.
    ///
    /// Follows `CompositorRole.decodeIfSupported`'s precedent exactly, for its stated reason: a
    /// migration that lives inside somebody else's `try?` migrates correctly by accident, riding on
    /// error handling that exists for a different purpose. A migration nobody can grep for is a
    /// migration nobody can change.
    ///
    /// An unrecognised string still throws, deliberately. That is what this decode did before, and a
    /// silent fallback to `.raster` would turn a genuinely corrupt manifest — or a kind from a build
    /// newer than this one — into a raster layer whose pixels are an empty cel, which looks to the
    /// artist like the layer's content was deleted rather than like the file could not be read.
    ///
    /// - Returns: nil when the key is absent, which is what a project saved before layer kinds existed
    ///   says and which the caller resolves to `.raster`.
    static func decodeMigratingEffectLayers<K: CodingKey>(from container: KeyedDecodingContainer<K>,
                                                         forKey key: K) throws -> LayerKind? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        if raw == retiredEffectLayerRawValue { return .value }
        guard let kind = LayerKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container,
                                                   debugDescription: "Unknown layer kind \"\(raw)\"")
        }
        return kind
    }

    /// The raw value the retired effect-layer kind was written as. Named rather than inlined so the
    /// migration above and any test pinning it are quoting the same string.
    static let retiredEffectLayerRawValue = "compositing"

    /// **The whole of the transform-layer migration, written as a line someone can find** —
    /// `decodeMigratingEffectLayers`' twin for TRANSFORM_LAYER.md §2 ruling 2.
    ///
    /// Until 2026-09-11 a transformation layer was a `.value` layer carrying `transform` and no
    /// `effect` (KEYFRAMES §4.4's third mode), so every document holding one has `"kind": "value"`
    /// beside a `transform` key. Read that pair as `.transform` and the document reopens as the layer
    /// it always was: the pose and its whole track are already sitting in the manifest's own
    /// `transform` key, decoded by the same `decodeIfPresent` every optional payload uses.
    ///
    /// **A `.value` layer carrying both a grade and a pose stays a value layer.** Under the old
    /// precedence the grade won and the pose was inert storage a flip-back could restore; there is no
    /// flip-back now — a value layer cannot become a transform layer — so `LayerManifest.init(from:)`
    /// drops the pose in that case rather than carrying a field nothing will ever read.
    ///
    /// **An older build cannot open a document this writes.** `"transform"` is a raw value the
    /// synthesized decoder there does not know, so `decodeMigratingEffectLayers` throws and the whole
    /// project answers nil — the failure that function's doc describes, and the one the standing
    /// no-migration permission (TODO.md) covers. Said here so nobody reads it as data loss.
    static func migratingTransformModeValueLayers(_ kind: LayerKind, effect: Effect?,
                                                  transform: LayerPose?) -> LayerKind {
        kind == .value && effect == nil && transform != nil ? .transform : kind
    }
}
