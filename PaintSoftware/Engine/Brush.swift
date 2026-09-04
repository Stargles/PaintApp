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
/// `.pencil` all called `stampCircle` and differed only in the `hardness`, `spacingFraction` and
/// `dynamics` their presets carried — every one of which is still a `Brush` field, so the four are
/// one case. `.square` stopped being procedural in §12 stage 3 and became a committed alpha mask;
/// `.custom` names a PNG under `BrushLibrary.customBrushesDirectory`. Both are `stampImage` of a
/// `BrushTextureRef`, so they are the other, and the difference between "a shipped tip" and "the
/// artist's own" is now a case of `BrushTextureRef` rather than a case of the brush's shape.
enum BrushTip: Equatable {
    /// Procedural — a radial gradient whose falloff is `Brush.hardness`. No orientation: a disc
    /// turned is the same disc, which is why `Brush.rotationJitter` reaches only the other arm.
    case round
    /// A picture. Its edge is in its own pixels, so `Brush.hardness` does not reach it, and it
    /// carries an angle because a turned square is not the same square.
    case stamp(BrushTextureRef)
}

extension BrushTip {
    /// The file this tip needs to exist under `BrushLibrary.customBrushesDirectory`, or nil for a
    /// tip the app bundle carries and for the procedural one.
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

/// How strongly Apple Pencil pressure affects a stamp's size and opacity. All fields are 0...1;
/// 0 means pressure has no effect at all (the brush behaves like a fixed-width pen).
struct BrushDynamics: Codable, Equatable {
    var sizePressure: Double
    var opacityPressure: Double
    /// Stamp size at zero pressure, as a fraction of `Brush.size` — keeps light touches from
    /// vanishing to a zero-width point when `sizePressure` is high.
    var minSizeFraction: Double

    static let `default` = BrushDynamics(sizePressure: 0.6, opacityPressure: 0.3, minSizeFraction: 0.3)
    static let fixed = BrushDynamics(sizePressure: 0, opacityPressure: 0, minSizeFraction: 1)

    /// Fraction (0...1, or slightly above if `minSizeFraction` > 1) of the brush's base size to use
    /// at a given 0...1 pressure sample. At `sizePressure == 0` this is always 1 (fixed-width,
    /// pressure has no effect); at `sizePressure == 1` it ranges from `minSizeFraction` at zero
    /// pressure up to 1 at full pressure. Intermediate `sizePressure` blends linearly between the
    /// two. Pure math — no UIKit/CoreGraphics dependency beyond `Double` — so it can be unit tested
    /// without a simulator.
    func sizeFraction(forPressure pressure: Double) -> Double {
        let p = max(0, min(pressure, 1))
        let pressureDriven = minSizeFraction + (1 - minSizeFraction) * p
        return (1 - sizePressure) * 1 + sizePressure * pressureDriven
    }

    /// Fraction (0...1) of the brush's base opacity to use at a given 0...1 pressure sample. At
    /// `opacityPressure == 0` this is always 1 (fixed opacity); at `opacityPressure == 1` it equals
    /// `pressure` itself (a feather-light touch is nearly invisible). Intermediate values blend
    /// linearly between the two, same shape as `sizeFraction`.
    func opacityFraction(forPressure pressure: Double) -> Double {
        let p = max(0, min(pressure, 1))
        return (1 - opacityPressure) * 1 + opacityPressure * p
    }
}

/// A brush preset: the tip it stamps plus every Procreate-style adjustable setting (size, opacity,
/// spacing, pressure dynamics, stabilization, scatter, blend mode). Value-typed and
/// `Codable` so it can be edited via simple bindings and persisted (built-ins in `BrushLibrary`,
/// user imports under `Documents/Brushes`).
struct Brush: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    /// Which mask a dab stamps — see `BrushTip`. One field, because the pair it replaced could
    /// contradict itself.
    var tip: BrushTip

    var size: CGFloat // base stamp diameter, in canvas points, at full pressure
    var opacity: Double // 0...1, overall stroke opacity
    var flow: Double // 0...1, per-stamp opacity multiplier (build-up as stamps overlap)
    var spacingFraction: Double // distance between stamps, as a fraction of the current stamp size
    /// 0...1, edge falloff passed through to `RasterLayerTexture.stampCircle(hardness:)` — 0 is
    /// fully soft/feathered, 1 is a hard, crisp edge. **A `.round` tip's parameter only**: a tip
    /// that is a picture carries its own edge in its pixels, so a `.stamp` dab has no `hardness` at
    /// all and does not read this.
    var hardness: Double
    /// 0...1 — how strongly raw input is smoothed before it reaches the canvas (see
    /// `StrokeStabilizer`); 0 draws exactly at the raw touch position.
    var stabilization: Double
    var scatter: Double // 0...1 random position jitter, as a fraction of size
    var rotationJitter: Double // 0...1 random per-stamp rotation

    var dynamics: BrushDynamics
    var blendMode: BrushBlendMode

    init(
        id: UUID = UUID(),
        name: String,
        tip: BrushTip,
        size: CGFloat,
        opacity: Double = 1,
        flow: Double = 1,
        spacingFraction: Double = 0.1,
        hardness: Double = 0.8,
        stabilization: Double = 0.2,
        scatter: Double = 0,
        rotationJitter: Double = 0,
        dynamics: BrushDynamics = .default,
        blendMode: BrushBlendMode = .normal
    ) {
        self.id = id
        self.name = name
        self.tip = tip
        self.size = size
        self.opacity = opacity
        self.flow = flow
        self.spacingFraction = spacingFraction
        self.hardness = hardness
        self.stabilization = stabilization
        self.scatter = scatter
        self.rotationJitter = rotationJitter
        self.dynamics = dynamics
        self.blendMode = blendMode
    }
}
