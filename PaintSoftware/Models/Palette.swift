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

/// App-wide store of the user's palettes, persisted to `UserDefaults` as JSON. A single shared
/// instance backs the color picker so the library survives the picker panel being torn down and
/// rebuilt each time it's reopened (it's created fresh on every `activePanel` switch), and so edits
/// made in one place are immediately visible everywhere.
///
/// Persistence is deliberately kept here rather than in `ProjectStore`/`ProjectManifest`: palettes
/// belong to the artist, not to any one project file, so they shouldn't ride along in a project's
/// saved manifest or get overwritten when a different project is opened.
final class PaletteStore: ObservableObject {
    static let shared = PaletteStore()

    @Published var palettes: [Palette] {
        didSet { persist() }
    }
    /// The palette currently shown in the picker. Kept as a stored id (rather than an index) so it
    /// stays pointing at the same palette across reorders/deletes, and persisted so reopening the
    /// picker returns to the palette the artist was last using.
    @Published var selectedPaletteID: UUID? {
        didSet { defaults.set(selectedPaletteID?.uuidString, forKey: Self.selectedKey) }
    }

    private let defaults: UserDefaults
    private static let palettesKey = "paletteStore.palettes.v1"
    private static let selectedKey = "paletteStore.selectedPaletteID.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // UI tests pass this flag so each run starts from the seeded presets rather than inheriting
        // swatches a previous run appended to the persistent store (which would make index-based
        // assertions flaky). No effect on normal launches.
        if ProcessInfo.processInfo.arguments.contains("-resetPalettes") {
            defaults.removeObject(forKey: Self.palettesKey)
            defaults.removeObject(forKey: Self.selectedKey)
        }

        let loaded: [Palette]
        if let data = defaults.data(forKey: Self.palettesKey),
           let decoded = try? JSONDecoder().decode([Palette].self, from: data),
           !decoded.isEmpty {
            loaded = decoded
        } else {
            // First launch (or corrupted store): seed the built-in presets.
            loaded = Self.defaultPresets
        }
        self.palettes = loaded

        if let stored = defaults.string(forKey: Self.selectedKey),
           let uuid = UUID(uuidString: stored),
           loaded.contains(where: { $0.id == uuid }) {
            self.selectedPaletteID = uuid
        } else {
            self.selectedPaletteID = loaded.first?.id
        }
    }

    // MARK: - Selection

    var selectedPalette: Palette? {
        guard let selectedPaletteID else { return palettes.first }
        return palettes.first { $0.id == selectedPaletteID } ?? palettes.first
    }

    var selectedIndex: Int? {
        guard let id = selectedPalette?.id else { return nil }
        return palettes.firstIndex { $0.id == id }
    }

    func select(_ palette: Palette) {
        selectedPaletteID = palette.id
    }

    // MARK: - Palette CRUD

    /// Creates an empty palette, selects it, and returns it.
    @discardableResult
    func addPalette(name: String = "New Palette") -> Palette {
        let palette = Palette(name: uniqueName(from: name), colors: [], isBuiltIn: false)
        palettes.append(palette)
        selectedPaletteID = palette.id
        return palette
    }

    /// Duplicates a palette (as an editable, non-built-in copy) directly after it and selects it.
    @discardableResult
    func duplicatePalette(_ palette: Palette) -> Palette {
        var copy = palette
        copy.id = UUID()
        copy.name = uniqueName(from: palette.name + " Copy")
        copy.isBuiltIn = false
        copy.colors = palette.colors.map { PaletteColor(hex: $0.hex) }
        let insertAt = (palettes.firstIndex { $0.id == palette.id }).map { $0 + 1 } ?? palettes.count
        palettes.insert(copy, at: insertAt)
        selectedPaletteID = copy.id
        return copy
    }

    func renamePalette(_ palette: Palette, to newName: String) {
        guard let index = palettes.firstIndex(where: { $0.id == palette.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        palettes[index].name = trimmed
    }

    /// Deletes a palette. Refuses to remove the last remaining one (there must always be something
    /// to show) and re-points the selection at a neighbor when the deleted palette was selected.
    func deletePalette(_ palette: Palette) {
        guard palettes.count > 1, let index = palettes.firstIndex(where: { $0.id == palette.id }) else { return }
        let wasSelected = palette.id == selectedPaletteID
        palettes.remove(at: index)
        if wasSelected {
            let neighbor = palettes[min(index, palettes.count - 1)]
            selectedPaletteID = neighbor.id
        }
    }

    // MARK: - Swatch editing

    /// Appends a color to a palette (no deduping — Procreate lets you keep near-identical swatches
    /// side by side deliberately).
    func addColor(_ color: Color, to palette: Palette) {
        guard let index = palettes.firstIndex(where: { $0.id == palette.id }) else { return }
        palettes[index].colors.append(PaletteColor(color: color))
    }

    func removeColor(_ swatch: PaletteColor, from palette: Palette) {
        guard let index = palettes.firstIndex(where: { $0.id == palette.id }) else { return }
        palettes[index].colors.removeAll { $0.id == swatch.id }
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

    private func persist() {
        guard let data = try? JSONEncoder().encode(palettes) else { return }
        defaults.set(data, forKey: Self.palettesKey)
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
