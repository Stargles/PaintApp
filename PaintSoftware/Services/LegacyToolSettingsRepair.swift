import Foundation
import os

/// **THROWAWAY: gives every scene an earlier build saved the tools that build kept app-wide, once, at
/// launch — and is deleted when the owner confirms their files are repaired.**
///
/// TODO (176): the owner ruled the tools in the artist's hand per scene — the tool, each stroke tool's
/// preset, size and opacity, the colour, the fill's and the interpolation's switches, the colour
/// panel's tab, Recent colours and palette. Earlier builds kept those app-wide (`EditorPreferences`,
/// `ToolSwitches`, `ColorPickerType`, `ColorHistoryStore`, `PaletteStore`'s selection) and the scene
/// kept only its pen preset, its eraser mode and its universal eraser, at the top of the manifest. The
/// app's decoder now reads the current record and nothing else (`EditorStateManifest`, strictly), so
/// every package an earlier build wrote is rewritten here: its `editorState` becomes the current record,
/// **with every tool filled from the artist's own app-wide values as they stand**, so a scene opens the
/// first time exactly as the earlier build showed it — and the three keys at the top move into it.
///
/// The earlier record is read the way the earlier build read it: a missing field is its default, an
/// onion skin it could not read field by field is that field's default, a whole record it could not
/// read is the defaults. Those were the earlier build's answers, so they are the answers here; the
/// current build reads none of them that way.
///
/// ## Why at launch, synchronously, and not in the maintenance pass
///
/// `LegacyPoseTrackRepair` runs in `ProjectBackupManager.runStartupMaintenance`, off the main thread,
/// while the gallery is already listing. This one cannot: every package it has not reached yet fails the
/// strict decoder, so the gallery's first listing would draw the artist's whole library as damaged and
/// offer to restore it. So `PaintApp.init` runs it before any view exists. When it has a package to
/// rewrite it first takes the update snapshot the maintenance pass would have taken
/// (`ProjectBackupManager.takeUpdateSnapshotIfNeeded`), and leaves that snapshot as it was, so the
/// earlier build's files are kept untouched in the scene's saved versions.
///
/// ## What it walks and how it writes
///
/// Every package under `Projects/`, `Backups/` and `Trash/` (`LibraryRepair`), except that snapshot. A
/// manifest is rewritten only when it is in the earlier shape, atomically, and a second run changes
/// nothing, so it runs on every launch until it is deleted. The earlier build's keys are deleted from the
/// app's settings once every package that needed them has them; until then they are read again on the
/// next launch.
///
/// ## Deleting it
///
/// This file, `LegacyToolSettingsRepairLogicTests.swift`, the call in `PaintApp.init`, and the two
/// files' entries in `project.pbxproj` — and `LibraryRepair.swift` with it, if it is the last repair left.
enum LegacyToolSettingsRepair {

    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "ToolSettingsRepair")

    /// The keys earlier builds kept the per-scene tools under, and the Select and Move switches the owner
    /// ruled are not saved at all.
    static let retiredKeys = [
        "paintapp.editorPreferences",
        "paintapp.fillMendsNeighbourGap", "paintapp.fillCanvasEdgeIsBoundary",
        "paintapp.interpolationThicknessFade", "paintapp.showMotionGroupOverlay",
        "paintapp.allowsPaintingOutsideSelection", "paintapp.subtractsSelection",
        "paintapp.preserveMovePrecision", "paintapp.keepsStrokeWidthOnMove",
        "paintapp.colorPickerType", "colorHistoryStore.colors.v1", "paletteStore.selectedPaletteID.v1",
    ]

    /// What one launch did.
    struct Report: Equatable {
        /// Packages rewritten, by their path below the library root.
        var repaired: [String] = []
        /// Packages no build could open — a manifest that is not JSON, or whose pen preset or eraser mode
        /// the earlier build could not read either. Left as they were, for the damage machinery
        /// (`ProjectBackupManager.repairCorruptedProjects`, the gallery's damaged tile) to answer.
        var unreadable: [String] = []
        /// Packages whose rewrite could not be written, left as they were and tried again next launch.
        var notWritten: [String] = []
        /// Whether the earlier build's keys were deleted — only once nothing is left to write.
        var retiredKeys = false
    }

    // MARK: - The library

    @discardableResult
    static func repairLibraryAndRetireKeys(defaults: UserDefaults = .standard,
                                           library: BrushLibraryStore = .shared) -> Report {
        var report = Report()
        let candidates = LibraryRepair.packages(leavingUntouched: nil).filter { mayNeedRepair($0.url) }
        if !candidates.isEmpty {
            let snapshot = ProjectBackupManager.takeUpdateSnapshotIfNeeded()
            let earlier = EarlierAppWideTools(defaults: defaults, library: library)
            for package in candidates where !package.url.lastPathComponent.hasPrefix(snapshot) {
                switch repair(packageAt: package.url, from: earlier) {
                case .alreadyCurrent: break
                case .repaired: report.repaired.append(package.path)
                case .unreadable: report.unreadable.append(package.path)
                case .notWritten: report.notWritten.append(package.path)
                }
            }
        }
        if report.notWritten.isEmpty {
            for key in retiredKeys { defaults.removeObject(forKey: key) }
            report.retiredKeys = true
        } else {
            log.error("Tool settings could not be written into \(report.notWritten.joined(separator: ", "), privacy: .public)")
        }
        if !report.unreadable.isEmpty {
            log.error("Tool settings: no build can read \(report.unreadable.joined(separator: ", "), privacy: .public)")
        }
        if !report.repaired.isEmpty {
            log.info("Tool settings repaired in \(report.repaired.count, privacy: .public) package(s)")
        }
        return report
    }

    /// The bytes say whether a manifest can be current: every earlier one names `selectedBrush`, and
    /// every current one carries `tools`. Only a manifest that might be earlier is parsed.
    private static func mayNeedRepair(_ package: URL) -> Bool {
        guard let data = try? Data(contentsOf: package.appendingPathComponent("manifest.json")) else { return false }
        return data.range(of: Data("\"selectedBrush\"".utf8)) != nil || data.range(of: Data("\"tools\"".utf8)) == nil
    }

    // MARK: - One package

    enum Outcome: Equatable { case alreadyCurrent, repaired, unreadable, notWritten }

    @discardableResult
    static func repair(packageAt package: URL, from earlier: EarlierAppWideTools) -> Outcome {
        let url = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              var manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unreadable }
        let movedKeys = ["selectedBrush", "vectorEraserMode", "universalEraser"]
        let stateIsCurrent = (manifest["editorState"] as? [String: Any])?["tools"] != nil
        guard !stateIsCurrent || movedKeys.contains(where: { manifest[$0] != nil }) else { return .alreadyCurrent }

        let state: EditorStateManifest
        do {
            state = try repairedEditorState(of: manifest, from: earlier)
        } catch {
            log.error("\(package.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return .unreadable
        }
        guard let encoded = try? JSONEncoder().encode(state),
              let object = try? JSONSerialization.jsonObject(with: encoded) else { return .notWritten }
        manifest["editorState"] = object
        for key in movedKeys { manifest.removeValue(forKey: key) }
        var written = false
        LibraryRepair.keepingItsDate(package) {
            written = LibraryRepair.write(manifest, to: url)
            return written
        }
        return written ? .repaired : .notWritten
    }

    /// The current record for a manifest an earlier build wrote: its own editor state, read the way that
    /// build read it, with the tools that build would have handed the artist on opening it. Throws when
    /// the earlier build could not have opened it either — a pen preset or eraser mode it could not read.
    static func repairedEditorState(of manifest: [String: Any],
                                    from earlier: EarlierAppWideTools) throws -> EditorStateManifest {
        let earlierState = (manifest["editorState"].flatMap { try? decode(EarlierEditorState.self, from: $0) })
            ?? EarlierEditorState()
        var state = EditorStateManifest()
        state.currentFrame = earlierState.currentFrame
        state.selectedLayerID = earlierState.selectedLayerID
        state.selectedFolderID = earlierState.selectedFolderID
        state.isOnionSkinEnabled = earlierState.isOnionSkinEnabled
        state.onionSkin = earlierState.onionSkin
        state.isLoopEnabled = earlierState.isLoopEnabled
        state.loopStartFrame = earlierState.loopStartFrame
        state.loopEndFrame = earlierState.loopEndFrame
        state.view = earlierState.view

        let pen = try decode(Brush.self, from: manifest["selectedBrush"]) ?? BrushLibrary.roundSoft
        var tools = earlier.tools(forPen: pen)
        tools.eyedropperMode = earlierState.eyedropperMode
        // A package with no mode was saved when Erase was the only eraser, so it was opened on Erase.
        tools.vectorEraserMode = try decode(VectorEraserMode.self, from: manifest["vectorEraserMode"]) ?? .erase
        tools.universalEraser = try decode(Bool.self, from: manifest["universalEraser"]) ?? false
        state.tools = tools
        return state
    }

    private static func decode<T: Decodable>(_ type: T.Type, from object: Any?) throws -> T? {
        guard let object, !(object is NSNull) else { return nil }
        let data = try JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - The earlier build's app-wide tools

    /// What earlier builds kept app-wide for the tools, read the way they read it — and so what one of
    /// them handed the artist on opening a scene.
    struct EarlierAppWideTools {
        /// `EditorPreferences`, a blob a build that could not decode it ignored.
        private struct Preferences: Decodable {
            var tool: Tool
            var brushSize: Double
            var brushOpacity: Double
            var brushColor: CodableColor
            var eraserBrushID: UUID
            var eraserSize: Double
            var eraserOpacity: Double
        }

        private let preferences: Preferences?
        private let switches: [String: Bool]
        private let pickerType: ColorPickerType
        private let recentColors: [PaletteColor]
        private let selectedPaletteID: UUID?
        private let library: BrushLibraryStore

        init(defaults: UserDefaults, library: BrushLibraryStore) {
            self.library = library
            preferences = defaults.data(forKey: "paintapp.editorPreferences")
                .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
            var switches: [String: Bool] = [:]
            for name in ["fillMendsNeighbourGap", "fillCanvasEdgeIsBoundary",
                         "interpolationThicknessFade", "showMotionGroupOverlay"]
            where defaults.object(forKey: "paintapp.\(name)") != nil {
                switches[name] = defaults.bool(forKey: "paintapp.\(name)")
            }
            self.switches = switches
            pickerType = defaults.string(forKey: "paintapp.colorPickerType").flatMap(ColorPickerType.init(rawValue:))
                ?? .initial
            recentColors = defaults.data(forKey: "colorHistoryStore.colors.v1")
                .flatMap { try? JSONDecoder().decode([PaletteColor].self, from: $0) } ?? []
            // A selection names a palette of the stored library; with none stored, the presets were
            // minted afresh on every launch, so no id outlived one and the first was shown.
            let palettes = AppSettings(defaults: defaults).readPalettes()
            selectedPaletteID = defaults.string(forKey: "paletteStore.selectedPaletteID.v1")
                .flatMap(UUID.init(uuidString:))
                .flatMap { id in
                    guard case .palettes(let stored) = palettes, stored.contains(where: { $0.id == id }) else { return nil }
                    return id
                }
        }

        /// The tools an earlier build put in the artist's hand on opening a scene whose pen preset was
        /// `pen`: the preset at the library's own version, at the size and opacity the artist last had
        /// (or the preset's, when nothing was kept), the eraser they last had, and the rest.
        func tools(forPen pen: Brush) -> SceneTools {
            var tools = SceneTools()
            let penShown = library.brush(withID: pen.id) ?? pen
            // The eraser a scene opened with before the artist's own was handed over: the literal, at
            // the library's version when it had been edited — and then at that version's size.
            let eraserLiteral = ToolProfiles().eraser
            let eraserShown = library.brush(withID: eraserLiteral.preset.id).flatMap { $0 == eraserLiteral.preset ? nil : $0 }
                .map { ToolProfile(preset: $0) } ?? eraserLiteral
            if let preferences {
                tools.tool = preferences.tool.isRestoredOnOpening ? preferences.tool : .pen
                tools.profiles.brush = ToolProfile(preset: penShown, size: CGFloat(preferences.brushSize),
                                                   opacity: preferences.brushOpacity)
                tools.profiles.eraser = ToolProfile(preset: library.brush(withID: preferences.eraserBrushID) ?? eraserShown.preset,
                                                    size: CGFloat(preferences.eraserSize),
                                                    opacity: preferences.eraserOpacity)
                tools.color = preferences.brushColor
            } else {
                tools.tool = BrushLibrary.isPencilPreset(pen) ? .pencil : .pen
                tools.profiles.brush = ToolProfile(preset: penShown)
                tools.profiles.eraser = eraserShown
            }
            tools.fill.mendsNeighbourGap = switches["fillMendsNeighbourGap"] ?? tools.fill.mendsNeighbourGap
            tools.fill.canvasEdgeIsBoundary = switches["fillCanvasEdgeIsBoundary"] ?? tools.fill.canvasEdgeIsBoundary
            tools.interpolationThicknessFade = switches["interpolationThicknessFade"] ?? tools.interpolationThicknessFade
            tools.showMotionGroupOverlay = switches["showMotionGroupOverlay"] ?? tools.showMotionGroupOverlay
            tools.colorPanel = ColorPanelManifest(pickerType: pickerType, recentColors: recentColors,
                                                  selectedPaletteID: selectedPaletteID)
            return tools
        }
    }

    // MARK: - The earlier editor record

    /// `EditorStateManifest` as earlier builds read it: every field its default when absent, the onion
    /// skin field by field, and the eyedropper mode its default when unreadable.
    private struct EarlierEditorState: Decodable {
        var currentFrame = 0
        var selectedLayerID: UUID?
        var selectedFolderID: UUID?
        var isOnionSkinEnabled = true
        var onionSkin = OnionSkinSettings()
        var isLoopEnabled = true
        var loopStartFrame: Int?
        var loopEndFrame: Int?
        var view: CanvasViewTransform?
        var eyedropperMode: Eyedropper.Mode = .layer

        init() {}

        private enum CodingKeys: String, CodingKey {
            case currentFrame, selectedLayerID, selectedFolderID, isOnionSkinEnabled, onionSkin,
                 isLoopEnabled, loopStartFrame, loopEndFrame, view, eyedropperMode
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            currentFrame = try c.decodeIfPresent(Int.self, forKey: .currentFrame) ?? 0
            selectedLayerID = try c.decodeIfPresent(UUID.self, forKey: .selectedLayerID)
            selectedFolderID = try c.decodeIfPresent(UUID.self, forKey: .selectedFolderID)
            isOnionSkinEnabled = try c.decodeIfPresent(Bool.self, forKey: .isOnionSkinEnabled) ?? true
            onionSkin = (try? c.decodeIfPresent(EarlierOnionSkin.self, forKey: .onionSkin))?.settings ?? OnionSkinSettings()
            isLoopEnabled = try c.decodeIfPresent(Bool.self, forKey: .isLoopEnabled) ?? true
            loopStartFrame = try c.decodeIfPresent(Int.self, forKey: .loopStartFrame)
            loopEndFrame = try c.decodeIfPresent(Int.self, forKey: .loopEndFrame)
            view = try c.decodeIfPresent(CanvasViewTransform.self, forKey: .view)
            eyedropperMode = (try? c.decodeIfPresent(Eyedropper.Mode.self, forKey: .eyedropperMode)) ?? .layer
        }
    }

    /// `OnionSkinSettings` as earlier builds read it: each field its default when missing or unreadable.
    private struct EarlierOnionSkin: Decodable {
        var settings = OnionSkinSettings()

        private enum CodingKeys: String, CodingKey {
            case neighbourhood, placement, previousCount, nextCount, loops, colouring, resolution,
                 previousTint, nextTint, isOpacityLinked, linkedPrevious, linkedNext,
                 freePreviousOpacities, freeNextOpacities
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func decoded<Value: Decodable>(_ key: CodingKeys) -> Value? {
                (try? c.decodeIfPresent(Value.self, forKey: key)).flatMap { $0 }
            }
            settings.neighbourhood = decoded(.neighbourhood) ?? settings.neighbourhood
            settings.placement = decoded(.placement) ?? settings.placement
            settings.previousCount = decoded(.previousCount) ?? settings.previousCount
            settings.nextCount = decoded(.nextCount) ?? settings.nextCount
            settings.loops = decoded(.loops) ?? settings.loops
            settings.colouring = decoded(.colouring) ?? settings.colouring
            settings.resolution = decoded(.resolution) ?? settings.resolution
            settings.previousTint = decoded(.previousTint) ?? settings.previousTint
            settings.nextTint = decoded(.nextTint) ?? settings.nextTint
            settings.isOpacityLinked = decoded(.isOpacityLinked) ?? settings.isOpacityLinked
            settings.linkedPrevious = decoded(.linkedPrevious) ?? settings.linkedPrevious
            settings.linkedNext = decoded(.linkedNext) ?? settings.linkedNext
            settings.freePreviousOpacities = decoded(.freePreviousOpacities) ?? settings.freePreviousOpacities
            settings.freeNextOpacities = decoded(.freeNextOpacities) ?? settings.freeNextOpacities
        }
    }
}
