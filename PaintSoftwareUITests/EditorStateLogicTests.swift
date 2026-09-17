import XCTest
import SwiftUI

/// TODO (77): what the editor was showing survives the gallery round trip — the document half through
/// `manifest.json`, the app half through `UserDefaults`.
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

    // MARK: - The document half

    func testTheEditorStateRoundTripsThroughTheManifest() throws {
        let manager = CanvasFixture.manager(layerCount: 3)
        let folderID = manager.addFolder(name: "Group")
        let defaults = manager.editorState

        manager.currentFrame = 7
        manager.currentLayerIndex = 2
        manager.selectedFolderID = folderID
        manager.isOnionSkinEnabled = false
        manager.onionSkin.previousCount = 3
        manager.onionSkin.placement = .inFront
        manager.onionSkin.linkedLevel = 0.6
        manager.isLoopEnabled = false
        manager.loopStartFrame = 2
        manager.loopEndFrame = 9
        manager.viewTransform = CanvasViewTransform(scale: 2.5, rotation: 0.4, offsetX: -30, offsetY: 12)
        let written = manager.editorState
        XCTAssertNotEqual(written, defaults, "Setup: every field is away from its default")

        let url = ProjectStore.createNewProjectURL(name: "Editor State")
        saveAndWait(manager, to: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        XCTAssertEqual(reopened.currentFrame, 7)
        XCTAssertEqual(reopened.currentLayerIndex, 2)
        XCTAssertEqual(reopened.layers[reopened.currentLayerIndex].id, manager.layers[2].id,
                       "The layer is restored by id")
        XCTAssertEqual(reopened.selectedFolderID, folderID)
        XCTAssertFalse(reopened.isOnionSkinEnabled)
        XCTAssertEqual(reopened.onionSkin, manager.onionSkin)
        XCTAssertFalse(reopened.isLoopEnabled)
        XCTAssertEqual(reopened.loopStartFrame, 2)
        XCTAssertEqual(reopened.loopEndFrame, 9)
        XCTAssertEqual(reopened.viewTransform, CanvasViewTransform(scale: 2.5, rotation: 0.4, offsetX: -30, offsetY: 12))
        XCTAssertEqual(reopened.editorState, written, "The whole record, field for field")
    }

    func testAPackageWrittenBeforeTheFieldOpensAtTheDefaults() throws {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.currentFrame = 5
        manager.currentLayerIndex = 1
        let url = ProjectStore.createNewProjectURL(name: "Old Package")
        saveAndWait(manager, to: url)

        // Strip the key the way a build before (77) never wrote it.
        let manifestURL = url.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        XCTAssertNotNil(json.removeValue(forKey: "editorState"), "Setup: this build wrote the key")
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)

        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(reopened.currentFrame, 0)
        XCTAssertEqual(reopened.currentLayerIndex, 0)
        XCTAssertEqual(reopened.editorState, freshOpenState(of: reopened), "Exactly what a fresh open showed before")
    }

    /// What a manager reads back as its editor state straight after an open with nothing to
    /// restore: the defaults, with the first layer as the selected one — an index of 0 always
    /// resolves to an id, so the record is never literally `EditorStateManifest()`.
    private func freshOpenState(of manager: CanvasManager) -> EditorStateManifest {
        var state = EditorStateManifest()
        state.selectedLayerID = manager.layers.first?.id
        return state
    }

    func testARecordThisBuildCannotReadIsTheDefaultsRatherThanARefusedOpen() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let url = ProjectStore.createNewProjectURL(name: "Garbled")
        saveAndWait(manager, to: url)
        let manifestURL = url.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        json["editorState"] = "not a record"
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)

        let reopened = try XCTUnwrap(ProjectStore.load(from: url), "The artwork opens; only the view is lost")
        XCTAssertEqual(reopened.editorState, freshOpenState(of: reopened))
    }

    func testAFieldMissingFromTheRecordDecodesToItsDefault() throws {
        let json = #"{"currentFrame": 4, "isLoopEnabled": false}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(EditorStateManifest.self, from: json)
        XCTAssertEqual(state.currentFrame, 4)
        XCTAssertFalse(state.isLoopEnabled)
        XCTAssertTrue(state.isOnionSkinEnabled, "Absent means the default, not a failure")
        XCTAssertEqual(state.onionSkin, OnionSkinSettings())
        XCTAssertNil(state.view)
    }

    func testALayerOrFolderTheDocumentNoLongerHasFallsBackRatherThanIndexingPastTheEnd() {
        let manager = CanvasFixture.manager(layerCount: 2)
        var state = EditorStateManifest()
        state.currentFrame = -3
        state.selectedLayerID = UUID()
        state.selectedFolderID = UUID()
        manager.currentLayerIndex = 1
        manager.restoreEditorState(state)
        XCTAssertEqual(manager.currentLayerIndex, 0, "An unknown layer id lands on the first layer")
        XCTAssertNil(manager.selectedFolderID, "An unknown folder id selects nothing")
        XCTAssertEqual(manager.currentFrame, 0, "A frame before the scene clamps to its start")
    }

    // MARK: - The app half

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "editor-state-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testTheArtistsToolsRoundTripThroughUserDefaults() throws {
        let defaults = try isolatedDefaults()
        XCTAssertNil(EditorPreferences.stored(in: defaults), "Nothing stored yet")

        let library = CanvasFixture.isolatedBrushLibrary()
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.brushLibraryOverride = library
        var eraser = BrushLibrary.roundHard
        eraser.name = "Wide eraser"
        eraser.size = 60
        _ = library.add(eraser)
        let before = manager.editorPreferences

        manager.selectedTool = .eraser
        manager.brushSize = 37
        manager.brushOpacity = 0.4
        manager.brushColor = Color(red: 0.2, green: 0.5, blue: 0.9)
        manager.selectEraserBrush(eraser)
        manager.eraserSize = 45
        manager.eraserOpacity = 0.7
        let stored = manager.editorPreferences
        XCTAssertNotEqual(stored, before, "Setup: every field is away from its default")
        stored.store(in: defaults)
        XCTAssertEqual(EditorPreferences.stored(in: defaults), stored)

        // A fresh manager — a new or reopened document — gets the same tools back.
        let next = CanvasFixture.manager(layerCount: 1)
        next.brushLibraryOverride = library
        next.applyEditorPreferences(try XCTUnwrap(EditorPreferences.stored(in: defaults)))
        XCTAssertEqual(next.selectedTool, .eraser)
        XCTAssertEqual(next.brushSize, 37)
        XCTAssertEqual(next.brushOpacity, 0.4)
        XCTAssertEqual(next.brushColor.codable, manager.brushColor.codable)
        XCTAssertEqual(next.selectedEraserBrush.id, eraser.id)
        XCTAssertEqual(next.selectedEraserBrush.name, "Wide eraser", "Resolved through the library")
        XCTAssertEqual(next.eraserSize, 45, "…and the nudged size wins over the preset's 60")
        XCTAssertEqual(next.eraserOpacity, 0.7)
    }

    func testAOneShotToolIsRecordedAsTheToolItHandsBackTo() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.selectedTool = .pencil
        manager.selectEyedropper()
        XCTAssertEqual(manager.selectedTool, .eyedropper, "Setup: the eyedropper is live")
        XCTAssertEqual(manager.editorPreferences.tool, .pencil, "The eyedropper reports what it will return to")

        manager.enterTextMode()
        XCTAssertEqual(manager.editorPreferences.tool, .pen, "A text session is not a tool to reopen into")
    }

    func testAnEraserPresetTheLibraryNoLongerHasKeepsTheDefault() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        var preferences = manager.editorPreferences
        preferences.eraserBrushID = UUID()
        preferences.eraserSize = 33
        manager.applyEditorPreferences(preferences)
        XCTAssertEqual(manager.selectedEraserBrush, BrushLibrary.roundHard, "An unknown id changes no preset")
        XCTAssertEqual(manager.eraserSize, 33, "…while the size the artist had still applies")
    }
}
