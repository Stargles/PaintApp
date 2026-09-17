import SwiftUI

// MARK: - Editor state that survives the gallery round trip (TODO (77))
//
// Leaving the editor discards the `CanvasManager`; reopening the project builds a new one from the
// manifest. Everything the manifest did not carry therefore came back at its default — the brush
// size and opacity, the frame, the zoom, the layer — which is the owner's report. The rule that
// decides where each piece now lives is one sentence: **how this document is being looked at goes
// with the document; the tools in the artist's hand go with the app.**
//
// `EditorStateManifest` is the first half, written into `manifest.json` by every save and applied by
// `ProjectStore.assemble`. `EditorPreferences` is the second, in `UserDefaults` beside
// `pencilOnlyDrawing` and `renderResolution`, stored by every save and applied to a manager as it
// enters the editor.
//
// Left to reset on purpose, and named so nobody re-files them: a floating Move or Duplicate piece and
// a lasso float (committed by `commitAllInteractiveState` on the way out), the selection, every open
// panel and presentation, interpolate mode, the graph editor, notices, and the undo history.

/// The zoom, rotation and pan the artist left the canvas at — `CanvasView.Coordinator`'s committed
/// navigation transform, in its own units: `scale` is relative to the fit-to-host scale, `rotation`
/// is radians, and the offset is host points from the fitted centre. Relative to fit rather than
/// absolute so the same document opens at the same apparent zoom on a differently sized host.
struct CanvasViewTransform: Codable, Equatable {
    var scale: Double
    var rotation: Double
    var offsetX: Double
    var offsetY: Double
}

/// What the editor was showing of this document when it was saved.
///
/// Every field decodes with a default when absent, which is §3.5's field-presence versioning: a
/// package written before (77) has no `editorState` at all and opens exactly as it did, and a field
/// added later leaves older records readable. A record this build cannot decode at all is treated
/// the same way — it is a view of the artwork, never the artwork, so nothing is worth refusing to
/// open over.
struct EditorStateManifest: Codable, Equatable {
    var currentFrame: Int = 0
    /// The layer, by id rather than index: a layer added or removed by another build would move an
    /// index onto a different layer without a word.
    var selectedLayerID: UUID? = nil
    var selectedFolderID: UUID? = nil
    var isOnionSkinEnabled: Bool = true
    var onionSkin = OnionSkinSettings()
    var isLoopEnabled: Bool = true
    var loopStartFrame: Int? = nil
    var loopEndFrame: Int? = nil
    var view: CanvasViewTransform? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentFrame = try c.decodeIfPresent(Int.self, forKey: .currentFrame) ?? 0
        selectedLayerID = try c.decodeIfPresent(UUID.self, forKey: .selectedLayerID)
        selectedFolderID = try c.decodeIfPresent(UUID.self, forKey: .selectedFolderID)
        isOnionSkinEnabled = try c.decodeIfPresent(Bool.self, forKey: .isOnionSkinEnabled) ?? true
        onionSkin = (try? c.decodeIfPresent(OnionSkinSettings.self, forKey: .onionSkin)) ?? OnionSkinSettings()
        isLoopEnabled = try c.decodeIfPresent(Bool.self, forKey: .isLoopEnabled) ?? true
        loopStartFrame = try c.decodeIfPresent(Int.self, forKey: .loopStartFrame)
        loopEndFrame = try c.decodeIfPresent(Int.self, forKey: .loopEndFrame)
        view = try c.decodeIfPresent(CanvasViewTransform.self, forKey: .view)
    }

    private enum CodingKeys: String, CodingKey {
        case currentFrame, selectedLayerID, selectedFolderID, isOnionSkinEnabled, onionSkin,
             isLoopEnabled, loopStartFrame, loopEndFrame, view
    }
}

/// The tools in the artist's hand — app-wide, because the toolbar is theirs rather than the
/// document's: the brush size they nudged follows them into the next document as well as back into
/// this one. The pen's *preset* stays in the manifest where it has always been (`selectedBrush`,
/// BRUSH.md §8.1); this carries the size and opacity nudged away from it, the eraser's preset by id,
/// the tool, and the colour.
struct EditorPreferences: Codable, Equatable {
    var tool: Tool
    var brushSize: Double
    var brushOpacity: Double
    var brushColor: CodableColor
    var eraserBrushID: UUID
    var eraserSize: Double
    var eraserOpacity: Double

    /// One key, one JSON value — a seven-field record is one preference, and seven keys would let
    /// half of it be read against the other half's absence.
    static let defaultsKey = "paintapp.editorPreferences"

    static func stored(in defaults: UserDefaults = .standard) -> EditorPreferences? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(EditorPreferences.self, from: data)
    }

    func store(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// The launch-argument test hook: `-resetEditorPreferences` forgets the stored tools, and so
    /// does `-resetGallery`, whose whole purpose is a launch that looks like a fresh install. The
    /// brush size, opacity, colour and tool outlive a launch now, so a UI test that opens a new
    /// document and reads the default brush has to ask for the defaults
    /// (`PaintUITestCase.launchIntoEditor` does) or it inherits whatever the previous test left.
    /// Synchronous, in `PaintApp.init`, because the next tap can read the record.
    static func forgetIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                                  defaults: UserDefaults = .standard) {
        guard arguments.contains("-resetEditorPreferences") || arguments.contains("-resetGallery") else { return }
        defaults.removeObject(forKey: defaultsKey)
    }
}

extension Tool {
    /// Whether this tool is one the artist can be handed back on their next document. The
    /// eyedropper and the text tool are both entered for one action and leave through their own
    /// exit paths (`toolBeforeEyedropper`, the text session), so restoring either would open the
    /// editor mid-gesture with nothing to finish.
    var restoresAcrossDocuments: Bool {
        switch self {
        case .pen, .pencil, .eraser, .fill: return true
        case .eyedropper, .text:            return false
        }
    }
}

extension CanvasManager {
    /// The document half of the round trip, read for the manifest.
    var editorState: EditorStateManifest {
        var state = EditorStateManifest()
        state.currentFrame = currentFrame
        state.selectedLayerID = layers.indices.contains(currentLayerIndex) ? layers[currentLayerIndex].id : nil
        state.selectedFolderID = selectedFolderID
        state.isOnionSkinEnabled = isOnionSkinEnabled
        state.onionSkin = onionSkin
        state.isLoopEnabled = isLoopEnabled
        state.loopStartFrame = loopStartFrame
        state.loopEndFrame = loopEndFrame
        state.view = viewTransform
        return state
    }

    /// Puts a loaded document back where its editor was — `ProjectStore.assemble`'s last step, after
    /// the layers exist. A layer id the document no longer has falls back to the first layer, which
    /// is what a fresh open showed before (77).
    func restoreEditorState(_ state: EditorStateManifest) {
        currentFrame = max(0, state.currentFrame)
        currentLayerIndex = state.selectedLayerID.flatMap { id in layers.firstIndex { $0.id == id } } ?? 0
        // After the layer: `currentLayerIndex`'s `didSet` clears the folder pick on a change.
        selectedFolderID = state.selectedFolderID.flatMap { id in folders.contains { $0.id == id } ? id : nil }
        isOnionSkinEnabled = state.isOnionSkinEnabled
        onionSkin = state.onionSkin
        isLoopEnabled = state.isLoopEnabled
        loopStartFrame = state.loopStartFrame
        loopEndFrame = state.loopEndFrame
        viewTransform = state.view
    }

    /// The app half, read for `UserDefaults`. The eyedropper reports the tool it will hand back to.
    var editorPreferences: EditorPreferences {
        let tool = selectedTool == .eyedropper ? toolBeforeEyedropper ?? .pen : selectedTool
        return EditorPreferences(tool: tool.restoresAcrossDocuments ? tool : .pen,
                                 brushSize: Double(brushSize), brushOpacity: brushOpacity,
                                 brushColor: brushColor.codable,
                                 eraserBrushID: selectedEraserBrush.id,
                                 eraserSize: Double(eraserSize), eraserOpacity: eraserOpacity)
    }

    /// Hands the artist their tools back as a manager enters the editor — new document or reopened
    /// one. The eraser's preset is resolved through the library, which is the same lookup
    /// `adoptLibrarySelections` makes; an id the library no longer has keeps the literal default.
    /// **After** `selectBrush` has run for the document's pen preset, because that call re-baselines
    /// size and opacity from the preset and this is what the artist nudged them to since.
    func applyEditorPreferences(_ preferences: EditorPreferences) {
        selectedTool = preferences.tool
        brushSize = CGFloat(preferences.brushSize)
        brushOpacity = preferences.brushOpacity
        brushColor = preferences.brushColor.color
        if let eraser = brushLibrary.brush(withID: preferences.eraserBrushID) { selectedEraserBrush = eraser }
        eraserSize = CGFloat(preferences.eraserSize)
        eraserOpacity = preferences.eraserOpacity
    }
}
