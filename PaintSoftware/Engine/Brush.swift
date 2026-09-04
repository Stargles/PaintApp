import CoreGraphics
import Foundation

/// The stamp shape a brush lays down. Built-in shapes are generated procedurally (no bundled
/// texture assets); `.custom` uses an imported image (see `Brush.customTextureFileName`).
enum BrushShape: String, Codable, CaseIterable, Identifiable {
    case softRound
    case hardRound
    case pencil
    case pen
    case square
    case custom

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .softRound: return "Soft Round"
        case .hardRound: return "Hard Round"
        case .pencil: return "Pencil"
        case .pen: return "Pen"
        case .square: return "Square"
        case .custom: return "Custom"
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

/// A brush preset: shape/texture plus every Procreate-style adjustable setting (size, opacity,
/// spacing, pressure dynamics, stabilization, scatter, blend mode). Value-typed and
/// `Codable` so it can be edited via simple bindings and persisted (built-ins in `BrushLibrary`,
/// user imports under `Documents/Brushes`).
struct Brush: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var shape: BrushShape
    /// Set only when `shape == .custom`: file name of the imported stamp texture under
    /// `Documents/Brushes`.
    var customTextureFileName: String?

    var size: CGFloat // base stamp diameter, in canvas points, at full pressure
    var opacity: Double // 0...1, overall stroke opacity
    var flow: Double // 0...1, per-stamp opacity multiplier (build-up as stamps overlap)
    var spacingFraction: Double // distance between stamps, as a fraction of the current stamp size
    /// 0...1, edge falloff passed through to `RasterLayerTexture.stampCircle(hardness:)` (and used
    /// as the falloff of each small dab in the square-brush approximation, see `StrokeCanvasView.
    /// stampApproximateSquare`) — 0 is fully soft/feathered, 1 is a hard, crisp edge.
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
        shape: BrushShape,
        customTextureFileName: String? = nil,
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
        self.shape = shape
        self.customTextureFileName = customTextureFileName
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
