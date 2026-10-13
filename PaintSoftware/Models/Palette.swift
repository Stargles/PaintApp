import SwiftUI
import Combine

/// A single saved color in a palette. Persisted as a hex string (not a SwiftUI `Color`, which isn't
/// `Codable`) and resolved back through the same `ColorMath`/`ColorConversion` path the rest of the
/// app uses, so a swatch always round-trips to exactly the color that was saved — including alpha,
/// carried in the 8-digit `RRGGBBAA` form when a color isn't fully opaque.
struct PaletteColor: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    /// Uppercase hex, no leading '#'. `RRGGBB` when opaque, `RRGGBBAA` otherwise.
    var hex: String

    init(id: UUID = UUID(), hex: String) {
        self.id = id
        self.hex = hex
    }

    init(id: UUID = UUID(), color: Color) {
        self.id = id
        self.hex = color.hexString
    }

    /// The resolved `Color`; falls back to black if a stored string somehow fails to parse (it never
    /// should, since it's only ever written from `Color.hexString`).
    var color: Color { Color(hex: hex) ?? .black }
}

/// A named grid of colors — the Procreate-style "palette". Palettes are app-wide (not per-project):
/// a color library the artist builds up and reuses across every drawing. `isBuiltIn` marks the
/// seeded presets so the UI can, for example, protect them from deletion or badge them.
struct Palette: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colors: [PaletteColor]
    var isBuiltIn: Bool

    /// Procreate lays palettes out 10 swatches per row; matching that keeps the grid math and the
    /// "add up to a full palette" feel familiar.
    static let columns = 10

    init(id: UUID = UUID(), name: String, colors: [PaletteColor], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.colors = colors
        self.isBuiltIn = isBuiltIn
    }

    /// Convenience for building presets from bare hex strings.
    init(name: String, hexes: [String], isBuiltIn: Bool = true) {
        self.init(
            name: name,
            colors: hexes.map { PaletteColor(hex: $0) },
            isBuiltIn: isBuiltIn
        )
    }
}

/// **The artist's palettes library** — app-wide, like the brush library (TODO (176), row J3): a colour
/// library built up and reused across every drawing, kept in `AppSettings`. Which palette a scene shows
/// is that scene's (`ColorPanelState.selectedPaletteID`), so this holds the palettes and nothing about
/// which one is in front. One shared instance backs every picker, so the library survives the panel
/// being torn down and rebuilt on every `activePanel` switch, and an edit made in one place is visible
/// everywhere.
final class PaletteStore: ObservableObject {
    static let shared = PaletteStore()

    @Published private(set) var palettes: [Palette]

    /// Set when a stored library could not be read: nothing is shown, nothing can be changed, and the
    /// stored library is left exactly as it was. The panel says this sentence instead.
    let unreadable: String?

    private let settings: AppSettings

    /// A first launch seeds the built-in presets **and stores them at once**, so their ids — which a
    /// scene's selection names — are the same on every launch after it.
    init(settings: AppSettings = .standard) {
        self.settings = settings
        switch settings.readPalettes() {
        case .palettes(let stored) where !stored.isEmpty:
            palettes = stored
            unreadable = nil
        case .none, .palettes:
            palettes = Self.defaultPresets
            unreadable = nil
            settings.writePalettes(palettes)
        case .unreadable(let sentence):
            palettes = []
            unreadable = sentence
        }
    }

    // MARK: - Selection

    /// The palette a scene's `selectedPaletteID` names, or the library's first when it names none the
    /// library has — never selected, or deleted in another scene.
    func palette(selectedBy id: UUID?) -> Palette? {
        id.flatMap { id in palettes.first { $0.id == id } } ?? palettes.first
    }

    // MARK: - Palette CRUD

    /// Creates an empty palette and returns it, for the scene that made it to select. Nil while the
    /// stored library is unreadable.
    @discardableResult
    func addPalette(name: String = "New Palette") -> Palette? {
        guard unreadable == nil else { return nil }
        let palette = Palette(name: uniqueName(from: name), colors: [], isBuiltIn: false)
        update { $0.append(palette) }
        return palette
    }

    func renamePalette(_ palette: Palette, to newName: String) {
        guard let index = palettes.firstIndex(where: { $0.id == palette.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { $0[index].name = trimmed }
    }

    /// Deletes a palette, refusing the last remaining one (there must always be something to show).
    /// Answers the neighbour that takes its place, for a scene that had it selected to select instead;
    /// nil when nothing was deleted.
    @discardableResult
    func deletePalette(_ palette: Palette) -> Palette? {
        guard palettes.count > 1, let index = palettes.firstIndex(where: { $0.id == palette.id }) else { return nil }
        update { $0.remove(at: index) }
        return palettes[min(index, palettes.count - 1)]
    }

    // MARK: - Swatch editing

    /// Appends a color to a palette (no deduping — Procreate lets you keep near-identical swatches
    /// side by side deliberately).
    func addColor(_ color: Color, to palette: Palette) {
        guard let index = palettes.firstIndex(where: { $0.id == palette.id }) else { return }
        update { $0[index].colors.append(PaletteColor(color: color)) }
    }

    func removeColor(_ swatch: PaletteColor, from palette: Palette) {
        guard let index = palettes.firstIndex(where: { $0.id == palette.id }) else { return }
        update { $0[index].colors.removeAll { $0.id == swatch.id } }
    }

    // MARK: - Helpers

    /// Ensures a palette name isn't a duplicate of an existing one by suffixing " 2", " 3", … as
    /// needed — keeps the palette menu unambiguous.
    private func uniqueName(from base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "New Palette" : trimmed
        let existing = Set(palettes.map(\.name))
        guard existing.contains(candidate) else { return candidate }
        var n = 2
        while existing.contains("\(candidate) \(n)") { n += 1 }
        return "\(candidate) \(n)"
    }

    /// Every change, saved as it is made. Nothing can change an unreadable library — every path that
    /// edits one already found nothing to edit — so what is stored stays what it was.
    private func update(_ change: (inout [Palette]) -> Void) {
        guard unreadable == nil else { return }
        change(&palettes)
        settings.writePalettes(palettes)
    }

    // MARK: - Default presets

    /// The palettes seeded on first launch. A small, useful spread: a general spectrum, warm and
    /// cool ramps, skin tones, and a neutral grayscale — enough to paint with immediately and to
    /// demonstrate what a palette is, without overwhelming the library.
    static let defaultPresets: [Palette] = [
        Palette(name: "Spectrum", hexes: [
            "000000", "FFFFFF", "9E9E9E", "F44336", "FF9800", "FFEB3B", "4CAF50", "009688", "2196F3", "3F51B5",
            "9C27B0", "E91E63", "795548", "607D8B", "00BCD4", "8BC34A", "CDDC39", "FFC107", "FF5722", "673AB7"
        ]),
        Palette(name: "Sunset", hexes: [
            "0D1B2A", "1B263B", "415A77", "778DA9", "E0AFA0", "F4A261", "E76F51", "E63946",
            "F77F00", "FCBF49", "EAE2B7", "D62828"
        ]),
        Palette(name: "Ocean", hexes: [
            "03045E", "023E8A", "0077B6", "0096C7", "00B4D8", "48CAE4", "90E0EF", "ADE8F4",
            "CAF0F8", "012A4A", "2C7DA0", "61A5C2"
        ]),
        Palette(name: "Skin Tones", hexes: [
            "FFE0BD", "FFCD94", "EAC086", "FFAD60", "E0AC69", "C68642", "A0522D", "8D5524",
            "6B4423", "3B2219", "F1C27D", "FFDBAC"
        ]),
        Palette(name: "Grayscale", hexes: [
            "000000", "1A1A1A", "333333", "4D4D4D", "666666", "808080", "999999", "B3B3B3",
            "CCCCCC", "E6E6E6", "F2F2F2", "FFFFFF"
        ])
    ]
}
