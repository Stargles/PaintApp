import XCTest
import SwiftUI

/// **TODO (176)'s one-shot repair** — `LegacyToolSettingsRepair`: every scene an earlier build saved gains
/// the tools that build kept app-wide, filled from the artist's own values, so it opens the first time
/// exactly as the earlier build showed it; then the earlier keys are deleted.
///
/// **The earlier shape is the earlier build's own bytes.** `earlierEditorState`, `earlierRoundSoft` and
/// `earlierPreferences` were copied out of a scene and the settings the build at this branch's parent
/// (`43d57d0`) wrote on a simulator on 2026-10-13, after an artist's session — brush at the ceiling, half
/// opacity, a blue, the eraser in hand, Mend off, the Wheel tab — so the repair is held to what that
/// build actually wrote rather than to what this file thinks it wrote.
///
/// **Deleted with `LegacyToolSettingsRepair.swift`.**
@MainActor
final class LegacyToolSettingsRepairLogicTests: XCTestCase {

    private var root: URL!
    private var suites: [String] = []
    private var defaults: UserDefaults!
    private var library: BrushLibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-settings-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defaults = try suite("tool-settings-repair")
        ProjectBackupManager.settings = AppSettings(defaults: try suite("tool-settings-repair-backups"))
        library = CanvasFixture.isolatedBrushLibrary()
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        ProjectBackupManager.settings = .standard
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try? FileManager.default.removeItem(at: root)
    }

    private func suite(_ name: String) throws -> UserDefaults {
        let suite = "\(name)-\(UUID().uuidString)"
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    // MARK: - The earlier build's bytes

    private static let earlierEditorState = #"{"currentFrame":0,"eyedropperMode":"layer","isLoopEnabled":true,"isOnionSkinEnabled":true,"onionSkin":{"colouring":"tinted","freeNextOpacities":[0.35,0.27999999999999997,0.21,0.14,0.07],"freePreviousOpacities":[0.35,0.27999999999999997,0.21,0.14,0.07],"isOpacityLinked":true,"linkedNext":{"furthest":0.07,"nearest":0.35},"linkedPrevious":{"furthest":0.07,"nearest":0.35},"loops":false,"neighbourhood":"drawings","nextCount":1,"nextTint":{"alpha":1,"blue":0.31,"green":0.78,"red":0.3},"placement":"behind","previousCount":1,"previousTint":{"alpha":1,"blue":0.21,"green":0.26,"red":0.95},"resolution":"half"},"selectedLayerID":"A7D67B74-7728-4A62-9700-F1DB6C5D6413"}"#

    private static let earlierRoundSoft = #"{"dab":{"angle":{"base":0,"directionFollow":0,"jitter":0},"brightnessShift":0,"density":1,"flow":0.35,"hardness":0.12,"hueShift":0,"saturationShift":0,"scatterAcross":0,"scatterAlong":0,"size":0.5,"spacing":0.06},"id":"B7051000-0000-4000-A000-000000000011","modulations":[{"amount":0.5,"input":{"kind":"pressure"},"modules":[{"curve":{"keys":[{"frame":0,"inHandle":{"deltaFrames":0,"deltaValue":0},"interpolation":"linear","outHandle":{"deltaFrames":0,"deltaValue":0},"tangentMode":"vector","value":0.2},{"frame":1024,"inHandle":{"deltaFrames":0,"deltaValue":0},"interpolation":"linear","outHandle":{"deltaFrames":0,"deltaValue":0},"tangentMode":"vector","value":1}],"step":1},"kind":"curveRamp"}],"output":"size"},{"amount":0.65,"input":{"kind":"pressure"},"output":"flow"}],"name":"Round Soft","opacity":1,"size":22,"stroke":{"blendMode":"normal","stabilization":0.25},"tip":{"kind":"round"}}"#

    private static let earlierPreferences = #"{"brushColor":{"red":0.11764705926179886,"alpha":1,"green":0.5333333611488342,"blue":0.8980392217636108},"eraserSize":20,"brushSize":2048,"tool":"eraser","eraserBrushID":"B7051000-0000-4000-A000-000000000013","eraserOpacity":1,"brushOpacity":0.5243333578109741}"#

    private static let earlierHistory = #"[{"hex":"1E88E5","id":"BD4508FA-76FC-452D-91BF-B732454984D7"}]"#

    /// The settings that build had kept app-wide by the end of that session.
    private func seedTheEarlierSettings() {
        defaults.set(Data(Self.earlierPreferences.utf8), forKey: "paintapp.editorPreferences")
        defaults.set(false, forKey: "paintapp.fillMendsNeighbourGap")
        defaults.set("triangle", forKey: "paintapp.colorPickerType")
        defaults.set(Data(Self.earlierHistory.utf8), forKey: "colorHistoryStore.colors.v1")
        // A preset's id from a launch whose palettes were never stored, so no later launch had it.
        defaults.set("657923EA-69E5-40ED-BCBD-5B726FC58599", forKey: "paletteStore.selectedPaletteID.v1")
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL) {
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    private func manifest(of package: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: package.appendingPathComponent("manifest.json")))
                      as? [String: Any])
    }

    private func writeManifest(_ json: [String: Any], to package: URL) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: package.appendingPathComponent("manifest.json"))
    }

    /// A scene saved by this build and then given the manifest the earlier build wrote: no `tools`, the
    /// earlier editor record, and the pen preset and eraser mode at the top.
    private func earlierPackage(_ name: String, editorState: String = earlierEditorState,
                                edit: (inout [String: Any]) -> Void = { _ in }) throws -> URL {
        let manager = CanvasFixture.manager(layerCount: 1)
        let url = ProjectStore.createNewProjectURL(name: name)
        saveAndWait(manager, to: url)
        var json = try manifest(of: url)
        var state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(editorState.utf8)) as? [String: Any])
        if state["selectedLayerID"] != nil { state["selectedLayerID"] = manager.layers[0].id.uuidString }
        json["editorState"] = state
        json["selectedBrush"] = try JSONSerialization.jsonObject(with: Data(Self.earlierRoundSoft.utf8))
        json["vectorEraserMode"] = "cutPoints"
        edit(&json)
        try writeManifest(json, to: url)
        XCTAssertNil(ProjectStore.load(from: url), "PREMISE: this build does not open the earlier shape unrepaired")
        return url
    }

    @discardableResult
    private func repair() -> LegacyToolSettingsRepair.Report {
        LegacyToolSettingsRepair.repairLibraryAndRetireKeys(defaults: defaults, library: library)
    }

    // MARK: - The scene opens as the earlier build showed it

    func testASceneTheEarlierBuildSavedOpensWithTheToolsThatBuildHadInTheArtistsHand() throws {
        seedTheEarlierSettings()
        let url = try earlierPackage("Earlier")

        let report = repair()
        XCTAssertEqual(report.repaired.count, 1, "The one scene is rewritten")
        let scene = try XCTUnwrap(ProjectStore.load(from: url), "…and this build opens it")

        XCTAssertEqual(scene.selectedTool, .eraser, "The tool in hand")
        XCTAssertEqual(scene.toolProfiles.brush.preset.id, BrushLibrary.roundSoft.id, "The scene's own pen preset")
        XCTAssertEqual(scene.toolProfiles.brush.size, 2048, "…at the size the artist had, not the preset's 22")
        XCTAssertEqual(scene.toolProfiles.brush.opacity, 0.5243333578109741, accuracy: 1e-12)
        XCTAssertEqual(scene.brushColor.codable,
                       CodableColor(red: 0.11764705926179886, green: 0.5333333611488342, blue: 0.8980392217636108, alpha: 1))
        XCTAssertEqual(scene.toolProfiles.eraser.preset.id, BrushLibrary.roundHard.id, "The eraser's preset, by its id")
        XCTAssertEqual(scene.toolProfiles.eraser.size, 20)
        XCTAssertEqual(scene.toolProfiles.eraser.opacity, 1)
        XCTAssertEqual(scene.vectorEraserMode, .cutPoints, "The eraser mode moved into the record")
        XCTAssertFalse(scene.universalEraser)
        XCTAssertEqual(scene.eyedropperMode, .layer)
        XCTAssertFalse(scene.fillSettings.mendsNeighbourGap, "Mend was off")
        XCTAssertTrue(scene.fillSettings.canvasEdgeIsBoundary, "Canvas Edge was never touched")
        XCTAssertEqual(scene.colorPanel.pickerType, .triangle, "The Wheel tab")
        XCTAssertEqual(scene.colorPanel.recentColors.map(\.hex), ["1E88E5"], "The colour painted with")
        XCTAssertNil(scene.colorPanel.selectedPaletteID,
                     "A palette id no stored library had was shown as the first, and still is")
        XCTAssertEqual(scene.onionSkin, OnionSkinSettings(), "The earlier editor record is kept")
        XCTAssertEqual(scene.currentLayerIndex, 0)

        let rewritten = try manifest(of: url)
        for key in ["selectedBrush", "vectorEraserMode", "universalEraser"] {
            XCTAssertNil(rewritten[key], "\(key) is no longer at the top of the manifest")
        }
        for key in LegacyToolSettingsRepair.retiredKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) is deleted once every scene has it")
        }
    }

    func testASecondRunChangesNothing() throws {
        seedTheEarlierSettings()
        let url = try earlierPackage("Earlier")
        repair()
        let once = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let second = repair()
        XCTAssertEqual(second.repaired, [], "Nothing is left in the earlier shape")
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), once)
    }

    /// **The artist's values as they stand fill every scene** — two scenes the earlier build saved
    /// both open with the one set of tools it kept, which is what both showed before.
    func testEveryEarlierSceneGetsTheSameAppWideValues() throws {
        seedTheEarlierSettings()
        let first = try earlierPackage("First")
        let second = try earlierPackage("Second")
        repair()
        let a = try XCTUnwrap(ProjectStore.load(from: first))
        let b = try XCTUnwrap(ProjectStore.load(from: second))
        XCTAssertEqual(a.sceneTools, b.sceneTools)
        XCTAssertEqual(a.toolProfiles.brush.size, 2048)
    }

    /// With nothing kept app-wide — an install that never saved its tools — a scene opened at what the
    /// earlier build gave it: the pen at its preset's own size, the eraser at 20, in black.
    func testWithNoEarlierPreferencesASceneOpensAsTheEarlierBuildOpenedIt() throws {
        let url = try earlierPackage("Bare")
        repair()
        let scene = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(scene.selectedTool, .pen)
        XCTAssertEqual(scene.toolProfiles.brush, ToolProfile(preset: BrushLibrary.roundSoft),
                       "The preset at its own size and opacity, as picking it gave")
        XCTAssertEqual(scene.toolProfiles.eraser, ToolProfiles().eraser)
        XCTAssertEqual(scene.brushColor.codable, CodableColor(red: 0, green: 0, blue: 0, alpha: 1))
        XCTAssertTrue(scene.fillSettings.mendsNeighbourGap)
        XCTAssertEqual(scene.colorPanel.pickerType, .initial)
    }

    /// Earlier preferences that build could not decode were ignored by it, so they are here.
    func testEarlierPreferencesThatBuildCouldNotReadAreAsIfNoneWereKept() throws {
        defaults.set(Data("{\"tool\":\"pen\"}".utf8), forKey: "paintapp.editorPreferences")
        let url = try earlierPackage("Half a record")
        repair()
        let scene = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(scene.toolProfiles.brush, ToolProfile(preset: BrushLibrary.roundSoft))
    }

    /// The pencil was the tool a scene with a Sketching preset opened on, with nothing kept app-wide.
    func testAScenesPencilPresetOpensOnThePencil() throws {
        let pencil = String(decoding: try JSONEncoder().encode(BrushLibrary.pencilHard), as: UTF8.self)
        let url = try earlierPackage("Pencil") { json in
            json["selectedBrush"] = try? JSONSerialization.jsonObject(with: Data(pencil.utf8))
        }
        repair()
        let scene = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(scene.selectedTool, .pencil)
        XCTAssertEqual(scene.toolProfiles.brush.preset.id, BrushLibrary.pencilHard.id)
    }

    /// A package with no eraser mode was saved when Erase was the only eraser, and opened on Erase.
    func testAPackageWithNoEraserModeOpensOnEraseAndTheUniversalEraserIsCarried() throws {
        let noMode = try earlierPackage("No mode") { $0.removeValue(forKey: "vectorEraserMode") }
        let universal = try earlierPackage("Universal") { $0["universalEraser"] = true }
        repair()
        XCTAssertEqual(try XCTUnwrap(ProjectStore.load(from: noMode)).vectorEraserMode, .erase)
        XCTAssertTrue(try XCTUnwrap(ProjectStore.load(from: universal)).universalEraser)
    }

    /// The earlier build read its own editor record leniently, and the repair reads it the same way:
    /// an onion skin record missing fields keeps what it has, an eyedropper mode it did not know is the
    /// layer, and a record it could not read at all is the defaults.
    func testTheEarlierEditorRecordIsReadTheWayTheEarlierBuildReadIt() throws {
        let older = try earlierPackage("Older onion", editorState: #"{"currentFrame":3,"eyedropperMode":"somethingNewer","onionSkin":{"previousCount":3,"placement":"inFront","linkedLevel":0.6}}"#)
        let garbled = try earlierPackage("Garbled", editorState: #"{"currentFrame":"three"}"#)
        let none = try earlierPackage("None") { $0.removeValue(forKey: "editorState") }
        repair()

        let olderScene = try XCTUnwrap(ProjectStore.load(from: older))
        XCTAssertEqual(olderScene.currentFrame, 3)
        XCTAssertEqual(olderScene.onionSkin.previousCount, 3, "An onion record missing most fields keeps the ones it has")
        XCTAssertEqual(olderScene.onionSkin.placement, .inFront)
        XCTAssertEqual(olderScene.onionSkin.nextCount, OnionSkinSettings().nextCount, "…and defaults the rest")
        XCTAssertEqual(olderScene.eyedropperMode, .layer)
        XCTAssertEqual(try XCTUnwrap(ProjectStore.load(from: garbled)).currentFrame, 0, "An unreadable record was the defaults")
        XCTAssertEqual(try XCTUnwrap(ProjectStore.load(from: none)).currentFrame, 0, "So was none at all")
    }

    /// A palette selection is kept when the stored library has that palette.
    func testAPaletteSelectionTheStoredLibraryHasIsKept() throws {
        let palettes = PaletteStore(settings: AppSettings(defaults: defaults))
        let chosen = palettes.palettes[2]
        defaults.set(chosen.id.uuidString, forKey: "paletteStore.selectedPaletteID.v1")
        let url = try earlierPackage("Palette")
        repair()
        XCTAssertEqual(try XCTUnwrap(ProjectStore.load(from: url)).colorPanel.selectedPaletteID, chosen.id)
        XCTAssertEqual(PaletteStore(settings: AppSettings(defaults: defaults)).palettes.map(\.id),
                       palettes.palettes.map(\.id), "The library itself is untouched")
    }

    // MARK: - The library

    /// Every saved version and every trashed scene too — and this build's update snapshot, taken first,
    /// keeps the earlier files exactly as they were.
    func testItRepairsBackupsAndTrashAndLeavesTheUpdateSnapshotAsItWas() throws {
        seedTheEarlierSettings()
        let url = try earlierPackage("Everywhere")
        let earlierBytes = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let trashed = ProjectBackupManager.trashDirectory.appendingPathComponent("Trashed.paintproj")
        try FileManager.default.copyItem(at: url, to: trashed)

        let report = repair()

        let backups = ProjectBackupManager.allProjectPackages(in: ProjectBackupManager.backupsRootDirectory)
        let snapshot = try XCTUnwrap(backups.first { $0.lastPathComponent.hasPrefix("preupdate-") },
                                     "The update snapshot was taken before anything was rewritten")
        XCTAssertEqual(try Data(contentsOf: snapshot.appendingPathComponent("manifest.json")), earlierBytes,
                       "…and is left exactly as the earlier build wrote it")
        XCTAssertNotNil(ProjectStore.load(from: trashed), "A trashed scene is repaired")
        XCTAssertNotNil(ProjectStore.load(from: url))
        XCTAssertTrue(report.repaired.contains { $0.hasPrefix("Trash/") })
        XCTAssertFalse(report.repaired.contains { $0.contains("preupdate-") })
    }

    /// The earlier keys are deleted only once nothing is left to write; a manifest that is not JSON is
    /// one no build could open, for the damage machinery to answer, and does not hold them.
    func testAManifestNoBuildCanReadIsReportedAndDoesNotHoldTheKeys() throws {
        seedTheEarlierSettings()
        let url = try earlierPackage("Damaged")
        try Data("not json".utf8).write(to: url.appendingPathComponent("manifest.json"))
        let report = repair()
        XCTAssertEqual(report.unreadable.count, 1)
        XCTAssertTrue(report.retiredKeys)
        XCTAssertNil(defaults.object(forKey: "paintapp.editorPreferences"))
    }

    /// A launch with nothing to repair takes no snapshot, rewrites nothing, and retires the keys.
    func testALibraryAlreadyCurrentIsLeftAlone() throws {
        seedTheEarlierSettings()
        let url = ProjectStore.createNewProjectURL(name: "Current")
        saveAndWait(CanvasFixture.manager(layerCount: 1), to: url)
        let bytes = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let report = repair()
        XCTAssertEqual(report.repaired, [])
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), bytes)
        XCTAssertNil(ProjectBackupManager.settings.lastAppSignature, "No snapshot was needed")
        XCTAssertTrue(report.retiredKeys)
    }
}
