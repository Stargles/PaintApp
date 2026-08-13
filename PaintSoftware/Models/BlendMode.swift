import Foundation

// MARK: - Blend modes
//
// LAYER_COMPOSITING.md §7's Tier 1 and Tier 2, plus "Clip to below" — which is not a blend at all;
// see its own case for what it is instead. §5.1's framing holds: adding a mode is a case here, a
// case in `Composite.metal`'s switch, and nothing else. There is no per-mode plumbing, and if a
// change ever seems to need some, that is the signal something has gone wrong rather than a reason
// to add it.
//
// Moved out of `LayerFolder.swift` in phase 5, where it stopped being a folder's private business:
// `Layer` carries one too now, and a type owned by both belongs to neither.

/// How a layer or group combines with the backdrop beneath it.
///
/// **Tier 1 was separable, all of it** — per-channel arithmetic on the backdrop and source
/// independently, which is what let one `switch` cover it on the GPU and kept the CPU reference
/// tractable. §7's **Tier 2 breaks that**: Hue, Saturation, Color and Luminosity need the whole RGB
/// triple at once (they compare or transplant a colour's saturation/luminosity, which no per-channel
/// function can do), and Lighter Color/Darker Color do too, for a different reason — they compare the
/// *triple's* luminosity and pick one source or the other wholesale, not a per-channel min/max the
/// way Lighten/Darken already do. `Compositor.swift`'s `handRolledTriple` is where that shape of work
/// lives; `handRolledChannel` still covers everything else, Tier 2's five separable additions
/// included (Vivid Light, Pin Light, Linear Burn, Divide, Exclusion).
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
    // Tier 2 (§7) below. Vivid Light, Pin Light and Linear Burn are separable — combinations of the
    // Tier 1 dodge/burn and darken/lighten formulas — so they cost `handRolledChannel` a case each,
    // same as Tier 1's hand-rolled three. Divide is separable too. Hue/Saturation/Color/Luminosity and
    // Lighter/Darker Color are not; see the enum doc comment.
    case vividLight
    case pinLight
    case linearBurn
    case hue
    case saturation
    case color
    case luminosity
    case divide
    case exclusion
    case lighterColor
    case darkerColor

    /// **Not a blend, and in this enum anyway** — §7 lists it in Tier 1 while saying in the same
    /// breath that it "clips to the alpha of the layer beneath; it is the mask machinery with an
    /// implicit source". It is here because this is where the artist picks it: one control, one
    /// list, rather than a second menu meaning "and also, separately, clip".
    ///
    /// **Nothing downstream of the render tree ever sees this case.** `CanvasManager.renderNodes`
    /// resolves it into a node with `blendMode: .normal` and a mask whose source is the entry
    /// directly below it, so there is no shader code for it, no `CGBlendMode` for it, and no branch
    /// in either backend to keep in step. `compositedMode` is that translation, stated once.
    case clipToBelow

    /// The label the layer panel shows. Written out rather than derived from the case name so
    /// "Color Dodge" and "Linear Light" read as artists expect and `add` can present as the name §7
    /// gives it.
    var displayName: String {
        switch self {
        case .normal:       return "Normal"
        case .multiply:     return "Multiply"
        case .screen:       return "Screen"
        case .overlay:      return "Overlay"
        case .add:          return "Add"
        case .subtract:     return "Subtract"
        case .darken:       return "Darken"
        case .lighten:      return "Lighten"
        case .colorDodge:   return "Color Dodge"
        case .colorBurn:    return "Color Burn"
        case .softLight:    return "Soft Light"
        case .hardLight:    return "Hard Light"
        case .linearLight:  return "Linear Light"
        case .difference:   return "Difference"
        case .vividLight:   return "Vivid Light"
        case .pinLight:     return "Pin Light"
        case .linearBurn:   return "Linear Burn"
        case .hue:          return "Hue"
        case .saturation:   return "Saturation"
        case .color:        return "Color"
        case .luminosity:   return "Luminosity"
        case .divide:       return "Divide"
        case .exclusion:    return "Exclusion"
        case .lighterColor: return "Lighter Color"
        case .darkerColor:  return "Darker Color"
        case .clipToBelow:  return "Clip to Below"
        }
    }

    /// What the compositor is handed for this pick: every mode is itself, except `clipToBelow`, which
    /// composites normally and expresses itself as a mask instead (see that case's own note).
    var compositedMode: BlendMode { self == .clipToBelow ? .normal : self }

    /// Grouping for the picker, in the order artists expect to find them — darkening together,
    /// lightening together, contrast together, inversions together, and now the HSL family together.
    /// Presentation only; nothing in the compositor reads it.
    static let menuGroups: [[BlendMode]] = [
        [.normal],
        [.multiply, .colorBurn, .linearBurn, .darken, .darkerColor],
        [.screen, .colorDodge, .add, .lighten, .lighterColor],
        [.overlay, .softLight, .hardLight, .linearLight, .vividLight, .pinLight],
        [.difference, .subtract, .exclusion, .divide],
        [.hue, .saturation, .color, .luminosity],
        // Its own section because it is its own kind of thing — see the case's note. The divider
        // `Section` draws is the whole of the UI it needed.
        [.clipToBelow],
    ]

    /// Whether this mode is anything other than plain source-over.
    ///
    /// Reads better than `!= .normal` at the call sites that matter — `RenderNode.needsOwnBuffer` and
    /// its `enclosesABlend` walk — where the question really is "does this participate in blending",
    /// not "is this one particular case".
    ///
    /// **`clipToBelow` answers false, and that is not a special case being smuggled in.** It really
    /// does composite source-over; what it adds is a mask, and `needsOwnBuffer` asks about that
    /// separately (`!masks.isEmpty`). Answering true here would claim a group buffer for the blend it
    /// does not do, and — worse — would make `enclosesABlend` treat a clipped child as a reason to
    /// isolate its parent.
    var isBlending: Bool { compositedMode != .normal }
}
