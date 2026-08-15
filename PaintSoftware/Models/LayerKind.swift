import Foundation

/// The three layer kinds. `.raster` (ordinary brush-stroke drawing) and `.vector` (brush
/// strokes/images stored as resolution-independent geometry — move/rotate/scale without quality
/// loss, re-rasterized on demand) hold pixels.
///
/// `.value` holds none, and is **two things chosen by one field**. With `Layer.effect` set it is
/// §4.4's stack-layer wrapper — Photoshop's adjustment layer — grading everything accumulated below
/// it *within its own container*. With `Layer.effect` absent it carries `Layer.fill` and *is* one
/// flat colour across the whole canvas — Photoshop's Solid Colour layer. `Layer.layerEffect` and
/// `Layer.valueFill` are the two accessors that read the mode out; nothing else asks.
///
/// **One kind with two modes rather than two kinds**, and that is the owner's call rather than a
/// tidying. The two never coexist on one layer — an adjustment layer that is also a flat colour is
/// not a picture anyone can describe — so a kind apiece made the mutually-exclusive pair expressible
/// twice, once as `kind` and once as which payload happened to be set, with nothing keeping them
/// honest. It also made "change this layer from a grade to a colour" a kind rewrite, which every
/// `kind ==` test in the app has an opinion about, instead of the one-field edit it now is.
///
/// The flat colour exists to be an operand: `Mix(A, B, .multiply)` where A and B are single layers is
/// identical to stacking B over A with Multiply (`RenderTree.swift` says so), so a value layer is the
/// honest answer to "why use a node at all" — `Mix(folder-of-drawings, grey 50%, .multiply)` combines
/// the folder as a unit and *then* halves it, which a flat stack cannot express. It also blends with
/// what is beneath it like any other leaf, which is the flat-background and tint case.
///
/// A `switch` over this enum that predates a case has to say what that case does — the compiler finds
/// them, and there are still none, because every reader asks `kind == .vector` / `layer.valueFill` /
/// `layer.layerEffect` rather than switching.
enum LayerKind: String, Codable, Equatable {
    case raster
    case vector
    case value
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
}
