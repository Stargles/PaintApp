import CoreGraphics

/// **What one stroke tool draws with** — its brush preset, and the size and opacity the artist has
/// nudged it to since picking that preset (TODO (176)).
///
/// Every tool that lays a brush walk on the canvas keeps one of these for itself, so adjusting the
/// eraser never disturbs the paint brush and switching tools never clobbers either one's settings.
/// The size and opacity are not folded into `preset` because the rail's sliders move them without
/// making a new preset: nudging a brush's size is not editing the brush.
///
/// `size` is in **canvas points** — `Brush.size`'s unit; the rail shows it as a percentage of the
/// canvas (`CanvasManager+BrushSize.swift`), and that mapping is presentation only.
struct ToolProfile: Codable, Equatable {
    var preset: Brush
    var size: CGFloat
    /// `0...1`, linear.
    var opacity: Double

    init(preset: Brush, size: CGFloat, opacity: Double) {
        self.preset = preset
        self.size = size
        self.opacity = opacity
    }

    /// `preset` at its own size and opacity — what picking it from a menu gives.
    init(preset: Brush) {
        self.init(preset: preset, size: preset.size, opacity: preset.opacity)
    }
}

/// **The tools that keep a `ToolProfile`.** Pen and pencil share the brush's — they are one tool whose
/// preset decides which of the two it is (`CanvasManager.selectPreset`). TODO (178)'s liquify is the
/// third, as a case here and a field of `ToolProfiles`, and every `switch` over this enum then says
/// what it does.
enum StrokeTool: String, CaseIterable {
    case brush
    case eraser
}

extension Tool {
    /// The profile this tool draws with, or nil for a tool that lays no brush walk.
    var strokeTool: StrokeTool? {
        switch self {
        case .pen, .pencil: return .brush
        case .eraser: return .eraser
        case .fill, .eyedropper, .text, .place: return nil
        }
    }
}

/// **One profile per stroke tool**, read and written by the tool it belongs to.
///
/// The defaults are what a new scene starts with: Round Soft at 5 points for the brush, and Round Hard
/// for the eraser at 20 — erasers are used broader than pens, and a hard edge is what most paint apps
/// default their eraser to.
struct ToolProfiles: Codable, Equatable {
    var brush = ToolProfile(preset: BrushLibrary.roundSoft, size: 5, opacity: 1)
    var eraser = ToolProfile(preset: BrushLibrary.roundHard, size: 20, opacity: 1)

    /// Every tool's preset, in `StrokeTool` order — what a saved package carries tip files for.
    var presets: [Brush] { StrokeTool.allCases.map { self[$0].preset } }

    subscript(tool: StrokeTool) -> ToolProfile {
        get {
            switch tool {
            case .brush: return brush
            case .eraser: return eraser
            }
        }
        set {
            switch tool {
            case .brush: brush = newValue
            case .eraser: eraser = newValue
            }
        }
    }
}
