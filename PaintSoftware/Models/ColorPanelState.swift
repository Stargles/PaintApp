import SwiftUI
import Combine

/// **The colour panel's state in one scene** — which picker type it opens on, the colours recently
/// painted with, and which palette it shows. Saved with the scene (TODO (176), rows J1, J2 and J4):
/// `ColorPanelManifest` is its record. The palettes themselves are the artist's whole library and are
/// app-wide (`PaletteStore`); a scene keeps only which one it has selected.
///
/// An object of its own on `CanvasManager` rather than `@Published` fields there, for `FillSettings`'
/// reason: only the colour panel observes it, so recording a painted colour at a stroke's lift redraws
/// the panel's Recent strip and nothing else in the editor.
final class ColorPanelState: ObservableObject {

    /// The picker type the panel opens on, in every one of its call sites (TODO (141)).
    @Published var pickerType: ColorPickerType = .initial

    /// **The last colours actually used to paint**, newest first — TODO (73)'s history row, on every
    /// picker type tab beside the selected palette.
    ///
    /// **"Actually used to paint", not "ever opened in the picker".** The call sites of
    /// `ColorPickerPanel` cover the brush, the canvas paper, a value layer's flat colour, an effect's
    /// colour and a gradient stop — most of which are never applied to the canvas with a stroke.
    /// Recording on every colour the picker merely *shows* would flood this list with paper and gradient
    /// tweaks. The one writer is `CanvasManager.strokeEnded`, gated on the tool actually painting
    /// `brushColor` (not the eraser, which commits a stroke but paints nothing).
    @Published private(set) var recentColors: [PaletteColor] = []

    /// The palette the type tabs show, from the app-wide library — nil, or an id the library no longer
    /// has, shows its first (`PaletteStore.palette(selectedBy:)`).
    @Published var selectedPaletteID: UUID?

    /// Item (73)'s "N ≈ 20".
    static let recentCapacity = 20

    /// Records a colour as just used to paint: newest first, deduplicated by hex (a re-used colour
    /// moves to the front rather than appearing twice), capped at `recentCapacity`.
    ///
    /// A no-op when `color` is already the front entry — the common case of painting several strokes
    /// in a row with the same colour — so a continuous drawing session doesn't republish on every lift.
    func recordPainted(_ color: Color) {
        let hex = color.hexString
        guard recentColors.first?.hex != hex else { return }
        recentColors.removeAll { $0.hex == hex }
        recentColors.insert(PaletteColor(hex: hex), at: 0)
        if recentColors.count > Self.recentCapacity {
            recentColors.removeLast(recentColors.count - Self.recentCapacity)
        }
    }

    func clearRecent() {
        recentColors = []
    }

    /// The record the scene's manifest carries.
    var manifest: ColorPanelManifest {
        ColorPanelManifest(pickerType: pickerType, recentColors: recentColors, selectedPaletteID: selectedPaletteID)
    }

    func restore(_ manifest: ColorPanelManifest) {
        pickerType = manifest.pickerType
        recentColors = manifest.recentColors
        selectedPaletteID = manifest.selectedPaletteID
    }
}

/// `ColorPanelState` in the scene's manifest.
struct ColorPanelManifest: Codable, Equatable {
    var pickerType: ColorPickerType = .initial
    var recentColors: [PaletteColor] = []
    var selectedPaletteID: UUID? = nil
}
