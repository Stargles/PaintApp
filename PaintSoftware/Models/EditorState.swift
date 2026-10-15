import SwiftUI

// MARK: - The editor as the artist left it in this scene — TODO (77), then TODO (176)
//
// Leaving the editor discards the `CanvasManager`; reopening the project builds a new one from the
// manifest. Everything the manifest did not carry therefore came back at its default — the owner's
// report for (77). The owner's ruling for (176) then put every option on one of three levels, and this
// file is the scene's: **how this scene is being looked at, and the tools in the artist's hand while they
// work on it, go with the scene.** A new scene starts at the defaults; reopening one finds it as it was
// left, whatever another scene did meanwhile.
//
// The other two levels are elsewhere: what the app keeps for itself (Fingers Can Paint, Render
// Resolution, the projects folder, the Palettes library…) is `AppSettings`, and what resets each launch
// is plain model state with no persistence code — the Select and Move switches, the selection mode, the
// timeline's zoom, every open panel and presentation, interpolate mode, the graph editor, notices, the
// undo history, and a floating Move or Duplicate piece (committed on the way out).
//
// **Decoded strictly.** A package this build cannot read is a package it does not open, never a scene
// whose tools quietly came back at their defaults: the owner's rule, *"if an update causes existing files
// to be outdated, then they should be automatically repaired"*. `LegacyToolSettingsRepair` is the one
// place that knows the earlier shapes.

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

/// What the editor was showing of this scene, and the tools it was showing them with, when it was saved.
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
    /// The view preset the Layers panel has active, by id for `selectedLayerID`'s reason; nil is All.
    var activeViewPresetID: UUID? = nil
    var tools = SceneTools()
}

/// **The tools in the artist's hand in this scene** — TODO (176)'s Document rows. Every default here is
/// what a new scene starts with; `EditorStateLogicTests` holds them to a new `CanvasManager`'s own.
struct SceneTools: Codable, Equatable {
    /// The active tool. Only one the artist can be handed back on opening (`Tool.isRestoredOnOpening`).
    var tool: Tool = .pen
    /// Each stroke tool's preset, size and opacity. The preset is carried whole so a package moved to
    /// another iPad still has it; on opening, the library's own version of it is taken
    /// (`CanvasManager.adoptLibrarySelections`), because a preset's parameters are app-wide (A8).
    var profiles = ToolProfiles()
    /// The colour in hand — Pen, Pencil, Fill, Rectangle, Ellipse and the selection's Fill share it.
    var color = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    /// What the eyedropper reads under the finger — TODO (119).
    var eyedropperMode: Eyedropper.Mode = .layer
    var vectorEraserMode: VectorEraserMode = .default
    var liquifyMode: LiquifyMode = .push
    /// Whether the eraser reaches every visible vector layer — TODO (82).
    var universalEraser = false
    var fill = FillToolManifest()
    /// The text tool's draft style — font, face, colour, size, spacing and alignment — with no words.
    var text = TextRecipe()
    var interpolationThicknessFade = false
    var showMotionGroupOverlay = true
    var colorPanel = ColorPanelManifest()
}

extension Tool {
    /// Whether this tool is one the artist can be handed back on opening a scene. The eyedropper, the
    /// text tool and a primed object are all entered for one action and leave through their own exit
    /// paths (`leaveMomentaryTool`, the text session, `leavePlacement`), so restoring any of them would
    /// open the editor mid-gesture with nothing to finish.
    var isRestoredOnOpening: Bool {
        switch self {
        case .pen, .pencil, .eraser, .liquify, .fill: return true
        case .eyedropper, .text, .place:    return false
        }
    }
}

extension CanvasManager {
    /// The scene's half of the editor, read for the manifest.
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
        state.activeViewPresetID = viewPresets.indices.contains(activeViewPresetIndex)
            ? viewPresets[activeViewPresetIndex].id : nil
        state.tools = sceneTools
        return state
    }

    /// The tools, read for the manifest. The eyedropper reports the tool it will hand back to.
    var sceneTools: SceneTools {
        let tool = selectedTool == .eyedropper ? toolReturnPath.handsBackTo : selectedTool
        var tools = SceneTools()
        tools.tool = tool.isRestoredOnOpening ? tool : .pen
        tools.profiles = toolProfiles
        tools.color = brushColor.codable
        tools.eyedropperMode = eyedropperMode
        tools.vectorEraserMode = vectorEraserMode
        tools.liquifyMode = liquifyMode
        tools.universalEraser = universalEraser
        tools.fill = FillToolManifest(mode: fillMode, settings: fillSettings)
        tools.text = textRecipe.styleOnly
        tools.interpolationThicknessFade = interpolationThicknessFade
        tools.showMotionGroupOverlay = showMotionGroupOverlay
        tools.colorPanel = colorPanel.manifest
        return tools
    }

    /// Puts a loaded scene back where its editor was — `ProjectStore.assemble`'s last step, after the
    /// layers, folders and view presets exist. A layer id the scene no longer has falls back to the
    /// first layer, which is what a fresh open shows.
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
        activeViewPresetIndex = state.activeViewPresetID.flatMap { id in viewPresets.firstIndex { $0.id == id } } ?? -1
        restoreSceneTools(state.tools)
    }

    func restoreSceneTools(_ tools: SceneTools) {
        selectedTool = tools.tool.isRestoredOnOpening ? tools.tool : .pen
        toolProfiles = tools.profiles
        brushColor = tools.color.color
        eyedropperMode = tools.eyedropperMode
        vectorEraserMode = tools.vectorEraserMode
        liquifyMode = tools.liquifyMode
        universalEraser = tools.universalEraser
        fillMode = tools.fill.mode
        tools.fill.apply(to: fillSettings)
        textRecipe = tools.text
        interpolationThicknessFade = tools.interpolationThicknessFade
        showMotionGroupOverlay = tools.showMotionGroupOverlay
        colorPanel.restore(tools.colorPanel)
    }
}
