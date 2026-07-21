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
}

/// Textured "tooth" modulation applied per-stamp (e.g. the Pencil brush's grain). `textureName`
/// nil means a built-in procedural noise texture rather than an imported image.
struct BrushGrain: Codable, Equatable {
    var isEnabled: Bool
    var scale: Double
    var rotation: Double // radians
    var depth: Double // 0...1, how strongly the grain modulates opacity
    var textureName: String?

    static let disabled = BrushGrain(isEnabled: false, scale: 1, rotation: 0, depth: 0, textureName: nil)
}

/// A brush preset: shape/texture plus every Procreate-style adjustable setting (size, opacity,
/// spacing, pressure dynamics, stabilization, scatter, grain, blend mode). Value-typed and
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
    /// 0...1 — how strongly raw input is smoothed before it reaches the canvas (see
    /// `StrokeStabilizer`); 0 draws exactly at the raw touch position.
    var stabilization: Double
    var scatter: Double // 0...1 random position jitter, as a fraction of size
    var rotationJitter: Double // 0...1 random per-stamp rotation

    var dynamics: BrushDynamics
    var grain: BrushGrain
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
        stabilization: Double = 0.2,
        scatter: Double = 0,
        rotationJitter: Double = 0,
        dynamics: BrushDynamics = .default,
        grain: BrushGrain = .disabled,
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
        self.stabilization = stabilization
        self.scatter = scatter
        self.rotationJitter = rotationJitter
        self.dynamics = dynamics
        self.grain = grain
        self.blendMode = blendMode
    }
}
