import Foundation

/// The colour picker's four types — the tabs along the foot of `ColorPickerPanel`: a hue ring around
/// an HSL triangle, the same ring around a saturation/brightness square, three sliders, and the
/// palette library. **Lives here and not inside the panel** for `ActivePanel`'s reason: the choice is
/// remembered across panels, and a `View` file cannot be compiled into the logic tier that tests the
/// remembering.
///
/// **Which one the panel opens on is the scene's** (TODO (141), then TODO (176)'s ruling, row J1) —
/// `ColorPanelState.pickerType`, saved with the scene like the rest of its tools.
enum ColorPickerType: String, Codable, CaseIterable, Identifiable {
    case triangle, square, value, palettes
    var id: String { rawValue }

    /// What a new scene's picker opens on until the artist chooses another.
    ///
    /// The tab bar's first *icon* is Triangle, but a dozen other features' XCUITests reach into this
    /// panel assuming its first-shown content is the SV square (`colorPanel.svSquare`) and the hex
    /// field, because that was this picker's one tab before it had several. Square is functionally
    /// what those tests were written against, so it stays the default, and every new canvas starts on
    /// it.
    static let initial: ColorPickerType = .square

    /// TODO (106): "label them in the reference's spirit" — the reference's own words for these four
    /// tabs, kept over the rawValue (unchanged, so every `colorPanel.tab.<rawValue>` identifier
    /// still resolves).
    var title: String {
        switch self {
        case .triangle: return "Wheel"
        case .square: return "Classic"
        case .value: return "Values"
        case .palettes: return "Palettes"
        }
    }

    var systemImage: String {
        switch self {
        case .triangle: return "triangle"
        case .square: return "square"
        case .value: return "slider.horizontal.3"
        case .palettes: return "square.grid.3x3.fill"
        }
    }
}
