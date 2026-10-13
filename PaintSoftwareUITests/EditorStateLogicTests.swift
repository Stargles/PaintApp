import XCTest
import SwiftUI

/// TODO (77), then TODO (176): what the editor was showing, and the tools in the artist's hand, are the
/// scene's — saved in its `manifest.json`, read back strictly, and each scene's own.
///
/// Every round trip here changes each field away from its default first, so an assertion that a
/// value came back equal is an assertion about the trip and not about two defaults agreeing.
@MainActor
final class EditorStateLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-state-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL) {
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    /// Every one of a scene's tools, away from where a new scene starts it.
    private func setEveryToolAwayFromItsDefault(_ manager: CanvasManager, eraser: Brush, paletteID: UUID) {
        manager.selectedTool = .eraser                                   // A1
        manager.toolProfiles.brush.preset = BrushLibrary.pencilHard      // A2
        manager.toolProfiles.brush.size = 37                             // A3
        manager.toolProfiles.brush.opacity = 0.4                         // A4
        manager.brushColor = Color(red: 0.2, green: 0.5, blue: 0.9)      // A5
        manager.eyedropperMode = .composite                              // A11
        manager.toolProfiles.eraser = ToolProfile(preset: eraser, size: 45, opacity: 0.7)   // B1–B3
        manager.vectorEraserMode = .wholeStroke                          // B4
        manager.universalEraser = true                                   // B5
        manager.fillMode = .lasso                                        // C1
        manager.fillSettings.gapClosing = 21                             // C2
        manager.fillSettings.threshold = 0.4                             // C3
        manager.fillSettings.bucketEdgeOverlap = 4                       // C4
        manager.fillSettings.lassoEdgeOverlap = 1                        // C5
        manager.fillSettings.mendsNeighbourGap = false                   // C7
        manager.fillSettings.mendReach = 30                              // C8
        manager.fillSettings.canvasEdgeIsBoundary = false                // C9
        manager.fillSettings.canvasEdgeExtension = 40                    // C10
        manager.textRecipe = TextRecipe(string: "words", font: FontDescriptor(familyName: "Georgia"),  // F1–F9
                                        typography: Typography(pointSize: 90, tracking: 3, lineHeightMultiple: 1.4,
                                                               lineSpacing: 5, paragraphSpacing: 9, alignment: .center),
                                        color: CodableColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        manager.interpolationThicknessFade = true                        // H1
        manager.showMotionGroupOverlay = false                           // H2
        manager.colorPanel.pickerType = .triangle                        // J1
        manager.colorPanel.recordPainted(.orange)                        // J2
        manager.colorPanel.selectedPaletteID = paletteID                 // J4
    }

    // MARK: - A scene's own

    func testTheEditorStateAndEveryToolRoundTripThroughTheManifest() throws {
        let library = CanvasFixture.isolatedBrushLibrary()
        let manager = CanvasFixture.manager(layerCount: 3)
        manager.brushLibraryOverride = library
        var eraser = BrushLibrary.roundHard
        eraser.name = "Wide eraser"
        eraser.size = 60
        let folderID = manager.addFolder(name: "Group")
        manager.addViewPreset()
        manager.addViewPreset()
        let defaults = manager.editorState

        manager.currentFrame = 7
        manager.currentLayerIndex = 2
        manager.selectedFolderID = folderID
        manager.isOnionSkinEnabled = false
        manager.onionSkin.previousCount = 3
        manager.onionSkin.placement = .inFront
        manager.onionSkin.linkedPrevious = OnionSkinRampEnds(nearest: 0.6, furthest: 0.4)
        manager.onionSkin.linkedNext = OnionSkinRampEnds(nearest: 0.2, furthest: 0.9)
        manager.isLoopEnabled = false
        manager.loopStartFrame = 2
        manager.loopEndFrame = 9
        manager.viewTransform = CanvasViewTransform(scale: 2.5, rotation: 0.4, offsetX: -30, offsetY: 12)
        manager.activeViewPresetIndex = 0                                // L16
        let paletteID = UUID()
        setEveryToolAwayFromItsDefault(manager, eraser: eraser, paletteID: paletteID)
        let written = manager.editorState
        XCTAssertNotEqual(written, defaults, "Setup: every field is away from its default")
        XCTAssertNotEqual(written.tools, SceneTools(), "Setup")

        let url = ProjectStore.createNewProjectURL(name: "Editor State")
        saveAndWait(manager, to: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        XCTAssertEqual(reopened.currentFrame, 7)
        XCTAssertEqual(reopened.layers[reopened.currentLayerIndex].id, manager.layers[2].id,
                       "The layer is restored by id")
        XCTAssertEqual(reopened.selectedFolderID, folderID)
        XCTAssertFalse(reopened.isOnionSkinEnabled)
        XCTAssertEqual(reopened.onionSkin, manager.onionSkin)
        XCTAssertEqual(reopened.viewTransform, CanvasViewTransform(scale: 2.5, rotation: 0.4, offsetX: -30, offsetY: 12))
        XCTAssertEqual(reopened.activeViewPresetIndex, 0, "The active view preset, by id")

        XCTAssertEqual(reopened.selectedTool, .eraser)
        XCTAssertEqual(reopened.toolProfiles, manager.toolProfiles, "Each stroke tool's preset, size and opacity")
        XCTAssertEqual(reopened.toolProfiles.eraser.preset.name, "Wide eraser", "The eraser's preset is carried whole")
        XCTAssertEqual(reopened.brushColor.codable, manager.brushColor.codable)
        XCTAssertEqual(reopened.eyedropperMode, .composite)
        XCTAssertEqual(reopened.vectorEraserMode, .wholeStroke)
        XCTAssertTrue(reopened.universalEraser)
        XCTAssertEqual(reopened.fillMode, .lasso)
        XCTAssertEqual(FillToolManifest(mode: reopened.fillMode, settings: reopened.fillSettings),
                       FillToolManifest(mode: manager.fillMode, settings: manager.fillSettings), "Every fill setting")
        XCTAssertEqual(reopened.textRecipe, manager.textRecipe.styleOnly, "The text tool's style, without the words")
        XCTAssertTrue(reopened.interpolationThicknessFade)
        XCTAssertFalse(reopened.showMotionGroupOverlay)
        XCTAssertEqual(reopened.colorPanel.pickerType, .triangle)
        XCTAssertEqual(reopened.colorPanel.recentColors.map(\.hex), [Color.orange.hexString])
        XCTAssertEqual(reopened.colorPanel.selectedPaletteID, paletteID)
        XCTAssertEqual(reopened.editorState, written, "The whole record, field for field")
    }

    /// **The owner's ask, at the model**: nudging the tools in one scene leaves another's alone, and the
    /// first gets its own back. A new scene starts on the defaults rather than on whatever was last used.
    func testEachSceneKeepsItsOwnToolsAndANewOneStartsOnTheDefaults() throws {
        let sceneA = CanvasFixture.manager(layerCount: 1)
        sceneA.toolProfiles.brush.size = 64
        sceneA.brushColor = Color(red: 0.9, green: 0.1, blue: 0.1)
        sceneA.fillSettings.gapClosing = 30
        let urlA = ProjectStore.createNewProjectURL(name: "Scene A")
        saveAndWait(sceneA, to: urlA)

        let sceneB = CanvasFixture.manager(layerCount: 1)
        XCTAssertEqual(sceneB.sceneTools, SceneTools(), "A new scene has the defaults, not scene A's tools")
        sceneB.toolProfiles.brush.size = 12
        let urlB = ProjectStore.createNewProjectURL(name: "Scene B")
        saveAndWait(sceneB, to: urlB)

        let reopenedA = try XCTUnwrap(ProjectStore.load(from: urlA))
        XCTAssertEqual(reopenedA.toolProfiles.brush.size, 64)
        XCTAssertEqual(reopenedA.brushColor.codable, sceneA.brushColor.codable)
        XCTAssertEqual(reopenedA.fillSettings.gapClosing, 30)
        let reopenedB = try XCTUnwrap(ProjectStore.load(from: urlB))
        XCTAssertEqual(reopenedB.toolProfiles.brush.size, 12, "…and scene B its own")
        XCTAssertEqual(reopenedB.fillSettings.gapClosing, FillSettings.defaultGapClosing)
    }

    /// **The Select panel's and the Move bar's switches are not saved** — the owner's ruling for (176),
    /// confirmed over (175)'s saving them. A scene saved with all four on reopens with all four off.
    func testTheSelectAndMoveSwitchesAreNotSavedWithTheScene() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.subtractsSelection = true
        manager.allowsPaintingOutsideSelection = true
        manager.keepsStrokeWidthOnMove = true
        manager.preserveMovePrecision = true
        let url = ProjectStore.createNewProjectURL(name: "Switches")
        saveAndWait(manager, to: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertFalse(reopened.subtractsSelection)
        XCTAssertFalse(reopened.allowsPaintingOutsideSelection)
        XCTAssertFalse(reopened.keepsStrokeWidthOnMove)
        XCTAssertFalse(reopened.preserveMovePrecision)
    }

    /// `SceneTools()` is what a new scene starts with, and it has to be what a new `CanvasManager` holds,
    /// or a scene saved untouched would come back changed.
    func testTheRecordsDefaultsAreANewScenesOwn() {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertEqual(manager.sceneTools, SceneTools())
        XCTAssertEqual(FillToolManifest(), FillToolManifest(mode: manager.fillMode, settings: manager.fillSettings))
        XCTAssertEqual(ColorPickerType.initial, .square, "Classic is the default the dozen picker tests reach into")
    }

    // MARK: - Read strictly

    private func savedPackage(_ name: String) -> URL {
        let url = ProjectStore.createNewProjectURL(name: name)
        saveAndWait(CanvasFixture.manager(layerCount: 1), to: url)
        return url
    }

    private func rewriteManifest(_ url: URL, _ edit: (inout [String: Any]) throws -> Void) throws {
        let manifestURL = url.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        try edit(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
    }

    /// **Unreadable data never reads as the defaults** — the owner's rule. An editor record this build
    /// cannot read is a package it does not open, never a scene whose tools quietly came back reset.
    func testAnEditorRecordThisBuildCannotReadIsAPackageItDoesNotOpen() throws {
        let cases: [(String, (inout [String: Any]) throws -> Void)] = [
            ("no editor record", { $0.removeValue(forKey: "editorState") }),
            ("a record that is not one", { $0["editorState"] = "not a record" }),
            ("a record with no tools", { json in
                var state = try XCTUnwrap(json["editorState"] as? [String: Any])
                state.removeValue(forKey: "tools")
                json["editorState"] = state
            }),
            ("an eyedropper mode this build does not know", { json in
                var state = try XCTUnwrap(json["editorState"] as? [String: Any])
                var tools = try XCTUnwrap(state["tools"] as? [String: Any])
                tools["eyedropperMode"] = "somethingNewer"
                state["tools"] = tools
                json["editorState"] = state
            }),
            ("an onion skin field it cannot read", { json in
                var state = try XCTUnwrap(json["editorState"] as? [String: Any])
                var onion = try XCTUnwrap(state["onionSkin"] as? [String: Any])
                onion["placement"] = 7
                state["onionSkin"] = onion
                json["editorState"] = state
            }),
        ]
        for (what, edit) in cases {
            let url = savedPackage(what)
            XCTAssertNotNil(ProjectStore.load(from: url), "PREMISE: the package opens before \(what)")
            try rewriteManifest(url, edit)
            XCTAssertNil(ProjectStore.load(from: url), "A package with \(what) is not opened at the defaults")
        }
    }

    func testALayerFolderOrViewTheDocumentNoLongerHasFallsBackRatherThanIndexingPastTheEnd() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()
        var state = EditorStateManifest()
        state.currentFrame = -3
        state.selectedLayerID = UUID()
        state.selectedFolderID = UUID()
        state.activeViewPresetID = UUID()
        manager.currentLayerIndex = 1
        manager.restoreEditorState(state)
        XCTAssertEqual(manager.currentLayerIndex, 0, "An unknown layer id lands on the first layer")
        XCTAssertNil(manager.selectedFolderID, "An unknown folder id selects nothing")
        XCTAssertEqual(manager.currentFrame, 0, "A frame before the scene clamps to its start")
        XCTAssertEqual(manager.activeViewPresetIndex, -1, "An unknown view is All")
    }

    func testAOneShotToolIsRecordedAsTheToolItHandsBackTo() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.selectedTool = .pencil
        manager.selectEyedropper()
        XCTAssertEqual(manager.selectedTool, .eyedropper, "Setup: the eyedropper is live")
        XCTAssertEqual(manager.sceneTools.tool, .pencil, "The eyedropper reports what it will return to")

        manager.enterTextMode()
        XCTAssertEqual(manager.sceneTools.tool, .pen, "A text session is not a tool to reopen into")
    }

    // MARK: - The library's presets are app-wide (A8)

    /// **A preset edited in another scene is the one this scene's next stroke uses, at this scene's own
    /// size and opacity.** The preset's parameters are app-wide; the size and opacity are the scene's.
    func testOpeningASceneTakesTheLibrarysPresetAndKeepsTheScenesSizeAndOpacity() {
        let library = CanvasFixture.isolatedBrushLibrary()
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.brushLibraryOverride = library
        var edited = BrushLibrary.roundSoft
        edited.dab.hardness = 0.9
        edited.size = 80
        library.update(edited)
        manager.toolProfiles.brush = ToolProfile(preset: BrushLibrary.roundSoft, size: 33, opacity: 0.5)
        XCTAssertNotEqual(manager.toolProfiles.brush.preset, library.brush(withID: edited.id), "PREMISE: the scene's copy is the older one")

        manager.adoptLibrarySelections()
        XCTAssertEqual(manager.toolProfiles.brush.preset, library.brush(withID: edited.id), "The library's version")
        XCTAssertEqual(manager.toolProfiles.brush.size, 33, "…at the scene's size, not the preset's 80")
        XCTAssertEqual(manager.toolProfiles.brush.opacity, 0.5)
    }
}
