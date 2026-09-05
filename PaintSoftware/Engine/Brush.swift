import CoreGraphics
import Foundation

/// **Which mask a dab stamps — the one field that decides it.** BRUSH.md §6.
///
/// This replaces `BrushShape` **and** `Brush.customTextureFileName`, a case and a parallel optional
/// that could disagree in both directions: a `.custom` shape with a nil file name named no picture,
/// and any of the other five shapes could carry a file name that nothing read. Neither state is
/// expressible now, which is BRUSH.md §9.2's *"payload-carrying enums make illegal states
/// unrepresentable"* — and the switch in `BrushStamper.stampDab` is exhaustive with no `default:`,
/// so a third tip kind is a compile error at every dispatch rather than a search.
///
/// **Five shapes collapsed into two cases and no ink moved.** `.softRound`, `.hardRound`, `.pen` and
/// `.pencil` all called `stampCircle` and differed only in the hardness, spacing and pressure response
/// their presets carried — every one of which is still a `Brush` field, so the four are
/// one case. `.square` stopped being procedural in §12 stage 3 and became a committed alpha mask;
/// `.custom` names a PNG in the brush library (`BrushStorage`). Both are `stampImage` of a
/// `BrushTextureRef`, so they are the other, and the difference between "a shipped tip" and "the
/// artist's own" is now a case of `BrushTextureRef` rather than a case of the brush's shape.
enum BrushTip: Hashable {
    /// Procedural — a radial gradient whose falloff is `Brush.hardness`. No orientation: a disc
    /// turned is the same disc, which is why §6's `angle` output reaches only the other arm.
    case round
    /// A picture. Its edge is in its own pixels, so `Brush.hardness` does not reach it, and it
    /// carries an angle because a turned square is not the same square.
    case stamp(BrushTextureRef)
}

extension BrushTip {
    /// The file this tip needs the brush library to hold, or nil for a tip the app bundle carries
    /// and for the procedural one.
    ///
    /// `ProjectStore`'s save-time copy and load-time restore are the callers: what they need is
    /// *the artist's own files*, since a built-in tip travels inside the binary and a round tip is
    /// arithmetic. Expressing that as one accessor is what stops the two of them re-deriving
    /// "custom-shaped, and with a file name" out of a pair of fields that could disagree.
    var importedTextureFileName: String? {
        guard case .stamp(.imported(let fileName)) = self else { return nil }
        return fileName
    }
}

extension BrushTip: Codable {
    private enum CodingKeys: String, CodingKey { case kind, texture }
    private enum Kind: String, Codable { case round, stamp }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .round:
            try container.encode(Kind.round, forKey: .kind)
        case .stamp(let texture):
            try container.encode(Kind.stamp, forKey: .kind)
            try container.encode(texture, forKey: .texture)
        }
    }

    /// **Written out rather than synthesized, and strict rather than defaulted.** A synthesized
    /// enum codec spells the payload `_0`, which is a compiler artifact in a file an artist's work
    /// is stored in. Strict because BRUSH.md §2.14 rules the documents on the device expendable and
    /// there is therefore no earlier spelling to accept: an unrecognised `kind` is a corrupt
    /// manifest, not an old one, and saying so is better than silently substituting a round tip for
    /// a brush whose ink is visibly a picture.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .round:
            self = .round
        case .stamp:
            self = .stamp(try container.decode(BrushTextureRef.self, forKey: .texture))
        }
    }
}

/// Mirrors the subset of `CGBlendMode` brushes are allowed to use, kept as its own enum (rather
/// than storing `CGBlendMode` directly) so `Brush` stays `Codable`/persistable.
enum BrushBlendMode: String, Codable, CaseIterable, Identifiable {
    case normal
    case multiply
    case screen
    case darken
    case lighten

    var id: String { rawValue }
    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .darken: return .darken
        case .lighten: return .lighten
        }
    }
}


/// A brush preset: the tip it stamps, the stroke-level settings, and **BRUSH.md §6's modulation
/// matrix** — every parameter as `base value + [modulation]`, where a modulation is
/// *(input, curve, amount)*. That is the brief's *"every parameter should be able to be sensor
/// driven"*.
///
/// ## The flat scalars are gone, and so are the two pressure blends
///
/// §12 stage 7's row of §10's deletion ledger, in full: `BrushDynamics.sizeFraction` and
/// `.opacityFraction` — the two hardcoded linear pressure blends — are **deleted, not kept as a fast
/// path**, and the rest of the flat scalars are grouped into `dab` and `stroke`. §10 names the first
/// as its own trap: *"they are correct and cheap and there will be a reason to keep them as a fast
/// path beside the general one. Two ways to compute a dab's size is two ways for it to be wrong, and
/// the parity test compares tiers rather than paths, so it would not catch the divergence."*
///
/// What replaces them is a *row*: every preset's old dynamics are now `size ← pressure` and
/// `opacity ← pressure` with an explicit curve, and `BrushModulationLogicTests` pins that the five
/// shipped presets render **byte-identical** to what they rendered before. That pin is the assertion
/// that the matrix subsumes what it replaces; without it this is a rewrite with an opinion.
///
/// The grouping's reason is §6's: `Brush`'s `Codable` decides what a document can be read back from,
/// so every new *flat* key is a decode-compatibility question and a nested field with a default is
/// not. `dab`, `stroke` and `modulations` each carry a `static let default` and a defaulted decode.
///
/// **`size` and `opacity` stay flat, and that is not an exception to the grouping.** They are not dab
/// parameters at all: `BrushStamper` takes the stroke's own `brushSize` and `brushOpacity` as
/// arguments, because a lasso resize scales the first and the toolbar drives both. What these two
/// hold is the *preset's* default, copied into `CanvasManager.brushSize` / `.brushOpacity` when the
/// preset is picked. The matrix's `size` and `opacity` outputs are the fractions those are multiplied
/// by, and they live in `dab` with the rest.
///
/// **`Hashable` is what `BrushPool` addresses an entry by**, so every field here is part of a brush's
/// identity — including `id`, which keeps two presets that happen to carry identical settings apart.
/// A stroke stores a `BrushRef` into that pool rather than a `Brush` (BRUSH.md §2.9), and it is the
/// hash of the *whole value* that makes §2.10 fall out with no rule to enforce: an edited brush is a
/// different value, so it interns to a different ref, so the ink already on the canvas is untouched.
/// Every sub-struct is `Hashable` for that reason, and a row of the matrix is part of the identity
/// exactly as a scalar was.
struct Brush: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    /// Which mask a dab stamps — see `BrushTip`. One field, because the pair it replaced could
    /// contradict itself.
    var tip: BrushTip

    /// The preset's default stroke diameter, in canvas points. Copied into the toolbar's own size
    /// when the preset is picked; the *dab's* size is `dab.size` times whatever the stroke carries.
    var size: CGFloat
    /// The preset's default stroke opacity, `0…1` — **BRUSH.md §2.11's cap**, and it has no per-dab
    /// counterpart on `BrushDabSettings`. What one stamp lays down is `dab.flow`; this is the most
    /// all of them together may reach, applied once when the stroke merges.
    var opacity: Double

    /// Every dab output's base value — §6.
    var dab: BrushDabSettings
    /// What the brush does to the gesture rather than to a dab.
    var stroke: BrushStrokeSettings
    /// §6's matrix: the rows, each *(output, input, curve, amount)*.
    var modulations: BrushModulations

    /// **The paper this brush lays its ink through — BRUSH.md §2.25**, or nil for a brush that lays
    /// ink flat. See `BrushTextureSettings`.
    ///
    /// **Optional rather than a neutral value, and that is what makes the feature additive.** A
    /// brush with no texture takes no branch at any merge, hashes to what it hashed before, and
    /// renders byte-identically on every tier — which is the pin §2.25 is worth having. A
    /// `depth: 0` default would have been the same pixels through a different code path, and this
    /// repo has a section on what two paths to one answer cost.
    ///
    /// It is at the top level rather than inside `stroke` for the reason `opacity` is: it belongs to
    /// the merge, which is a property of the whole walk, and `BrushStrokeSettings` is what the brush
    /// does to the *gesture*.
    var texture: BrushTextureSettings?

    init(
        id: UUID = UUID(),
        name: String,
        tip: BrushTip,
        size: CGFloat,
        opacity: Double = 1,
        dab: BrushDabSettings = .default,
        stroke: BrushStrokeSettings = .default,
        modulations: BrushModulations = .default,
        texture: BrushTextureSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.tip = tip
        self.size = size
        self.opacity = opacity
        self.dab = dab
        self.stroke = stroke
        self.modulations = modulations
        self.texture = texture
    }
}

extension Brush {
    /// **Every file in the brush library this brush needs to exist**, which
    /// since §2.25 is two questions rather than one: the tip's picture and the texture's sheet.
    ///
    /// `ProjectStore`'s save-time copy and load-time restore are the callers. Stated here, once, for
    /// the reason `BrushTip.importedTextureFileName` was: two consumers re-deriving *"which files
    /// does this brush use"* is exactly how the second half of a brush stops travelling, and BUGS.md
    /// already carried that defect once for tips — a document reopened on another device whose ink
    /// names a file the package never carried.
    var importedTextureFileNames: Set<String> {
        var names = Set<String>()
        if let tipFile = tip.importedTextureFileName { names.insert(tipFile) }
        if let textureFile = texture?.mask.importedFileName { names.insert(textureFile) }
        return names
    }
}

extension Brush {
    private enum CodingKeys: String, CodingKey {
        case id, name, tip, size, opacity, dab, stroke, modulations, texture
    }

    /// **Written out so the three sub-structs decode to their defaults**, which is the property §6
    /// asks the grouping for: a setting added inside one of them later is one field rather than a
    /// decode-compatibility question. `id`, `name`, `tip` and the two stroke-level numbers are strict
    /// — a brush without them is not a brush.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tip = try c.decode(BrushTip.self, forKey: .tip)
        size = try c.decode(CGFloat.self, forKey: .size)
        opacity = try c.decode(Double.self, forKey: .opacity)
        dab = try c.decodeIfPresent(BrushDabSettings.self, forKey: .dab) ?? .default
        stroke = try c.decodeIfPresent(BrushStrokeSettings.self, forKey: .stroke) ?? .default
        modulations = try c.decodeIfPresent(BrushModulations.self, forKey: .modulations) ?? .default
        // Absent *is* the value, not a default standing in for one: a brush with no texture writes
        // no key and reads back as one with no texture — the same bytes, either way round.
        texture = try c.decodeIfPresent(BrushTextureSettings.self, forKey: .texture)
    }
}
