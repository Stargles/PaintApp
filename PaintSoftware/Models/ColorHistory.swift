import SwiftUI
import Combine

/// App-wide history of the last colours actually used to paint — TODO item (73)'s history row, shown
/// on every picker type tab beside the selected palette (see `ColorPickerPanel`).
///
/// **"Actually used to paint", not "ever opened in the picker".** The seven call sites of
/// `ColorPickerPanel` cover the brush, the canvas paper, a value layer's flat colour, an effect's
/// colour and a gradient stop — most of which are never applied to the canvas with a stroke.
/// Recording on every colour the picker merely *shows* would flood this list with paper and gradient
/// tweaks. The one call this class gets is `CanvasManager.strokeEnded`, gated on the tool actually
/// painting `brushColor` (not the eraser, which commits a stroke but paints nothing) — see that
/// method's own comment.
///
/// Persisted exactly the way `PaletteStore` persists palettes: `UserDefaults`, JSON, a single
/// `.shared` instance, because it is the same kind of app-wide artist data (not per-project) that
/// file already argues for.
final class ColorHistoryStore: ObservableObject {
    static let shared = ColorHistoryStore()

    @Published private(set) var colors: [PaletteColor] {
        didSet { persist() }
    }

    /// Item (73)'s "N ≈ 20".
    static let capacity = 20

    private let defaults: UserDefaults
    private static let key = "colorHistoryStore.colors.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Same UI-test reset flag `PaletteStore` answers to, so a test that wants a known palette
        // library also gets a known (empty) history rather than whatever a previous run appended.
        if ProcessInfo.processInfo.arguments.contains("-resetPalettes") {
            defaults.removeObject(forKey: Self.key)
        }

        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([PaletteColor].self, from: data) {
            self.colors = decoded
        } else {
            self.colors = []
        }
    }

    /// Records a colour as just used to paint: newest first, deduplicated by hex (a re-used colour
    /// moves to the front rather than appearing twice), capped at `capacity`.
    ///
    /// A no-op when `color` is already the front entry — the common case of painting several strokes
    /// in a row with the same colour — so a continuous drawing session doesn't re-encode and
    /// re-persist this list on every single stroke lift.
    func record(_ color: Color) {
        let hex = color.hexString
        guard colors.first?.hex != hex else { return }
        colors.removeAll { $0.hex == hex }
        colors.insert(PaletteColor(hex: hex), at: 0)
        if colors.count > Self.capacity {
            colors.removeLast(colors.count - Self.capacity)
        }
    }

    func clear() {
        colors = []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(colors) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
