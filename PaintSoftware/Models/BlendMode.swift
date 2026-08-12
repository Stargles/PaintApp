import Foundation

// MARK: - Blend modes
//
// LAYER_COMPOSITING.md §7's Tier 1, less "Clip to below" — see the note at the bottom of this file
// for why that one is not here. §5.1's framing holds: adding a mode is a case here, a case in
// `Composite.metal`'s switch, and nothing else. There is no per-mode plumbing, and if a change ever
// seems to need some, that is the signal something has gone wrong rather than a reason to add it.
//
// Moved out of `LayerFolder.swift` in phase 5, where it stopped being a folder's private business:
// `Layer` carries one too now, and a type owned by both belongs to neither.

/// How a layer or group combines with the backdrop beneath it.
///
/// **Separable, all of them.** Every case below is per-channel arithmetic on the backdrop and source
/// independently, which is what lets one `switch` cover them on the GPU and what keeps the CPU
/// reference tractable. §7's Tier 2 adds Hue/Saturation/Color/Luminosity, which are *not* separable —
/// they need the whole RGB triple at once — so that tier is a genuinely different shape of work and
/// is deliberately a later phase rather than "more cases".
enum BlendMode: String, Codable, Equatable, CaseIterable {
    case normal
    case multiply
    case screen
    case overlay
    /// Linear Dodge, under the name artists reach for first.
    case add
    case subtract
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case linearLight
    case difference

    /// The label the layer panel shows. Written out rather than derived from the case name so
    /// "Color Dodge" and "Linear Light" read as artists expect and `add` can present as the name §7
    /// gives it.
    var displayName: String {
        switch self {
        case .normal:      return "Normal"
        case .multiply:    return "Multiply"
        case .screen:      return "Screen"
        case .overlay:     return "Overlay"
        case .add:         return "Add"
        case .subtract:    return "Subtract"
        case .darken:      return "Darken"
        case .lighten:     return "Lighten"
        case .colorDodge:  return "Color Dodge"
        case .colorBurn:   return "Color Burn"
        case .softLight:   return "Soft Light"
        case .hardLight:   return "Hard Light"
        case .linearLight: return "Linear Light"
        case .difference:  return "Difference"
        }
    }

    /// Grouping for the picker, in the order artists expect to find them — darkening together,
    /// lightening together, contrast together. Presentation only; nothing in the compositor reads it.
    static let menuGroups: [[BlendMode]] = [
        [.normal],
        [.multiply, .colorBurn, .darken],
        [.screen, .colorDodge, .add, .lighten],
        [.overlay, .softLight, .hardLight, .linearLight],
        [.difference, .subtract],
    ]

    /// Whether this mode is anything other than plain source-over.
    ///
    /// Reads better than `!= .normal` at the call sites that matter — `RenderNode.needsOwnBuffer` and
    /// its `enclosesABlend` walk — where the question really is "does this participate in blending",
    /// not "is this one particular case".
    var isBlending: Bool { self != .normal }
}

// **"Clip to below" is not here, and it is not an oversight.** §7 lists it in Tier 1 while saying in
// the same breath that it is "not a blend — clips to the alpha of the layer beneath; it is the mask
// machinery with an implicit source". Implementing it in phase 5 would mean building phase 6's mask
// resolution early, to serve one mode, and then rebuilding it when §6.2's real `AlphaMask` arrives
// with sources, inversion and the cycle rule. It lands in phase 6 as a mask with its source implied,
// which is what the plan says it is. Same call phase 4 made about `alphaMask` itself.
