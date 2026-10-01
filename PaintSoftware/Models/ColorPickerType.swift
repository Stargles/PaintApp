import Foundation

/// The colour picker's four types — the tabs along the foot of `ColorPickerPanel`: a hue ring around
/// an HSL triangle, the same ring around a saturation/brightness square, three sliders, and the
/// palette library. **Lives here and not inside the panel** for `ActivePanel`'s reason: the choice is
/// remembered across panels, and a `View` file cannot be compiled into the logic tier that tests the
/// remembering.
///
/// ## What is remembered, and where
///
/// **The type the artist last chose, app-wide, in `UserDefaults`** (TODO (141), the owner: *"the color
/// wheel type resets to classic every time the canvas is exited and re-entered"*). `EditorState`'s own
/// rule decides the home — *how this document is being looked at goes with the document; the tools in
/// the artist's hand go with the app* — and which picker the artist works in is a tool in their hand,
/// not a property of any drawing. It follows them into the next document as the brush size does.
///
/// **Beside `EditorPreferences` rather than inside it**, which is the one departure from that file's
/// record. `EditorPreferences` is read and written by a `CanvasManager`, and the panel has none: it is
/// built at nine call sites from a colour binding alone, and threading a manager through all of them
/// to carry one enum would be the larger change. `forgetIfRequested` is the same launch hook that
/// record answers to, so a test that asks for the editor's defaults gets this one too —
/// `PaintUITestCase.launchIntoEditor` already does, on every launch.
///
/// **An instance of the defaults, not a static that writes through.** CLAUDE.md carries the section on
/// a `UserDefaults`-backed static that outlived the test that set it; every function below takes the
/// `UserDefaults` it reads and writes, so the logic tests hand it a suite of their own.
enum ColorPickerType: String, CaseIterable, Identifiable {
    case triangle, square, value, palettes
    var id: String { rawValue }

    /// What the picker opens on until the artist has chosen another.
    ///
    /// The tab bar's first *icon* is Triangle, but a dozen other features' XCUITests reach into this
    /// panel assuming its first-shown content is the SV square (`colorPanel.svSquare`) and the hex
    /// field, because that was this picker's one tab before it had several. Square is functionally
    /// what those tests were written against, so it stays the default — and since they all start
    /// from `-resetEditorPreferences`, they get it by that launch argument rather than by hoping
    /// nothing earlier chose otherwise.
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

    // MARK: - Remembered

    static let defaultsKey = "paintapp.colorPickerType"

    /// The type the artist last chose, or `initial` — also for a stored string this build does not
    /// know.
    static func remembered(in defaults: UserDefaults = .standard) -> ColorPickerType {
        defaults.string(forKey: defaultsKey).flatMap(ColorPickerType.init(rawValue:)) ?? initial
    }

    /// Makes this the type the picker opens on from now on.
    func remember(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    /// The launch-argument test hook, answered under `EditorPreferences.forgetIfRequested`'s own
    /// condition. Synchronous, in `PaintApp.init`, because the first panel the next tap opens reads it.
    static func forgetIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                                  defaults: UserDefaults = .standard) {
        guard EditorPreferences.forgetRequested(in: arguments) else { return }
        defaults.removeObject(forKey: defaultsKey)
    }
}
