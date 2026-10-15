import XCTest
import SwiftUI

@MainActor
final class LegacyLiquifyRepairLogicTests: XCTestCase {
    private var root: URL!
    private var defaultsName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("liquify-repair-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defaultsName = "liquify-repair-\(UUID())"
        ProjectBackupManager.settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsName)))
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        ProjectBackupManager.settings = .standard
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: root)
    }

    private func package(_ name: String = "Projects/earlier.paintproj",
                         configure: (CanvasManager) -> Void = { _ in }) throws -> URL {
        let url = root.appendingPathComponent(name)
        let manager = linkedManager()
        configure(manager)
        let saved = expectation(description: "save package")
        ProjectStore.save(manager, to: url) { saved.fulfill() }
        wait(for: [saved], timeout: 30)
        return url
    }

    private func linkedManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.layers[0].cels[0].interpolation = InterpolationRecipe(references: [
            InterpolationReference(layerID: manager.layers[0].id, celID: UUID()),
            InterpolationReference(layerID: manager.layers[0].id, celID: UUID())], t: 0.25)
        return manager
    }

    private func packageAsync(_ name: String = "Projects/async.paintproj",
                              configure: (CanvasManager) -> Void = { _ in }) async throws -> URL {
        let url = root.appendingPathComponent(name)
        let manager = linkedManager()
        configure(manager)
        let saved = expectation(description: "save async package")
        ProjectStore.save(manager, to: url) { saved.fulfill() }
        await fulfillment(of: [saved], timeout: 30)
        return url
    }

    private func object(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func edit(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
        var json = try object(url)
        change(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: url, options: .atomic)
    }

    private func recipeURL(_ package: URL) throws -> URL {
        let manifest = try JSONDecoder().decode(ProjectManifest.self,
            from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        let cel = try XCTUnwrap(manifest.layers.first?.cels.first)
        return ProjectPackageLayout.existingURL(named: try XCTUnwrap(cel.interpolationFileName),
            role: .interpolation, cel: cel.id, in: package)
    }

    private func vectorURL(_ package: URL) throws -> URL {
        let manifest = try JSONDecoder().decode(ProjectManifest.self,
            from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        let cel = try XCTUnwrap(manifest.layers.flatMap(\.cels).first { $0.vectorFileName != nil })
        return ProjectPackageLayout.existingURL(named: try XCTUnwrap(cel.vectorFileName),
            role: .drawing, cel: cel.id, in: package)
    }

    private func materialStroke(_ operation: InkMaterialOperation) -> VectorStroke {
        let samples = StrokeSamples(points: [CGPoint(x: 8, y: 12), CGPoint(x: 48, y: 18)])
        return VectorStroke(brush: TestBrushes.pencil,
            color: CodableColor(red: 0.6, green: 0.1, blue: 0.2, alpha: 1), size: 5, opacity: 0.8,
            samples: samples, placement: StrokePlacement(map: .identity, restSize: 5,
                source: .retained(samples: samples, lattice: nil, precise: true),
                material: InkMaterialProgram(bindings: [InkMaterialBinding(operation: operation, bridge: .identity)])))
    }

    private func materialOperation(brush: Brush = TestBrushes.hardRound) -> InkMaterialOperation {
        InkMaterialOperation(LiquifyDeformation(brush: brush, size: 16, power: 0.4, mode: .push, seed: 43,
            samples: StrokeSamples(points: [CGPoint(x: 12, y: 12), CGPoint(x: 20, y: 16)])))
    }

    private func fileBytes(_ package: URL) throws -> [String: Data] {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(package.path.count))] = try Data(contentsOf: file)
        }
        return result
    }

    private func makeEarlier(_ package: URL, recipe: URL) throws {
        try edit(package.appendingPathComponent("manifest.json")) { manifest in
            var editor = manifest["editorState"] as! [String: Any]
            var tools = editor["tools"] as! [String: Any]
            var profiles = tools["profiles"] as! [String: Any]
            profiles.removeValue(forKey: "liquify")
            tools["profiles"] = profiles
            tools.removeValue(forKey: "liquifyMode")
            editor["tools"] = tools
            manifest["editorState"] = editor
        }
        try edit(recipe) { json in
            for key in ["mode", "groups", "guideIDs", "localEdits", "spacing", "deformations", "materialOperations"] {
                json.removeValue(forKey: key)
            }
        }
    }

    func testEarlierToolsAndRecipeReceiveExactDefaultsAndSecondRunChangesNoBytes() throws {
        let package = try package(), recipe = try recipeURL(package)
        try makeEarlier(package, recipe: recipe)
        let date = Date(timeIntervalSince1970: 123456)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: package.path)
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .repaired)
        let manifest = try JSONDecoder().decode(ProjectManifest.self,
            from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        XCTAssertEqual(manifest.editorState.tools.profiles.liquify, ToolProfiles().liquify)
        XCTAssertEqual(manifest.editorState.tools.liquifyMode, .push)
        let current = try JSONDecoder().decode(InterpolationRecipe.self, from: Data(contentsOf: recipe))
        XCTAssertEqual(current.t, 0.25)
        XCTAssertEqual(current.mode, .generate)
        XCTAssertEqual(current.spacing, .linear)
        XCTAssertTrue(current.groups.isEmpty && current.guideIDs.isEmpty && current.localEdits.isEmpty && current.deformations.isEmpty)
        let before = try Data(contentsOf: recipe)
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .current)
        XCTAssertEqual(try Data(contentsOf: recipe), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: package.path)[.modificationDate] as? Date, date)
    }

    func testRepairPreservesPresentToolAndRecipeChoices() throws {
        let package = try package(), recipe = try recipeURL(package)
        try edit(package.appendingPathComponent("manifest.json")) { json in
            var editor = json["editorState"] as! [String: Any]
            var tools = editor["tools"] as! [String: Any]
            var profiles = tools["profiles"] as! [String: Any]
            var profile = profiles["liquify"] as! [String: Any]
            profile["size"] = 321; profile["opacity"] = 0.72
            profiles["liquify"] = profile; tools["profiles"] = profiles
            tools["liquifyMode"] = "twirl"; editor["tools"] = tools; json["editorState"] = editor
        }
        try edit(recipe) { json in
            json["mode"] = "reproject"
            json["spacing"] = ["kind": "easeIn", "samples": []]
            json.removeValue(forKey: "deformations")
        }
        let manifestBefore = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .repaired)
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent("manifest.json")), manifestBefore)
        let current = try JSONDecoder().decode(InterpolationRecipe.self, from: Data(contentsOf: recipe))
        XCTAssertEqual(current.mode, .reproject)
        XCTAssertEqual(current.spacing, SpacingCurve(kind: .easeIn))
        XCTAssertEqual(current.references.count, 2)
        XCTAssertEqual(current.t, 0.25)
        XCTAssertTrue(current.deformations.isEmpty)
    }

    func testMalformedPresentRecipeFieldDoesNotRewriteManifestOrSidecar() throws {
        let package = try package(), recipe = try recipeURL(package)
        try makeEarlier(package, recipe: recipe)
        try edit(recipe) { $0["mode"] = "broken" }
        let manifest = package.appendingPathComponent("manifest.json")
        let manifestBefore = try Data(contentsOf: manifest), recipeBefore = try Data(contentsOf: recipe)
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .unreadable)
        XCTAssertEqual(try Data(contentsOf: manifest), manifestBefore)
        XCTAssertEqual(try Data(contentsOf: recipe), recipeBefore)
    }

    func testMalformedPresentToolFieldIsNotReplacedWithDefault() throws {
        let package = try package()
        let manifest = package.appendingPathComponent("manifest.json")
        try edit(manifest) { json in
            var editor = json["editorState"] as! [String: Any]
            var tools = editor["tools"] as! [String: Any]
            tools["liquifyMode"] = NSNull()
            editor["tools"] = tools; json["editorState"] = editor
        }
        let before = try Data(contentsOf: manifest)
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .unreadable)
        XCTAssertEqual(try Data(contentsOf: manifest), before)
    }

    func testMissingSidecarFailsRepairAndBothMetadataPreflights() throws {
        let package = try package(), recipe = try recipeURL(package)
        try FileManager.default.removeItem(at: recipe)
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .unreadable)
        XCTAssertFalse(ProjectBackupManager.validateProject(at: package))
        XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package))
    }

    func testOnlyRestorePreflightAcceptsEarlierRecipeWithoutWritingIt() throws {
        let package = try package(), recipe = try recipeURL(package)
        try makeEarlier(package, recipe: recipe)
        let before = try Data(contentsOf: recipe)
        XCTAssertFalse(ProjectBackupManager.validateProject(at: package))
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: package))
        XCTAssertEqual(try Data(contentsOf: recipe), before)
    }

    func testRecipeMetadataResolvesLocalEditBrushesFromItsPackageTable() throws {
        let package = try package { manager in
            let stroke = VectorStroke(brush: TestBrushes.hardRound,
                color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 8, opacity: 1,
                samples: [VectorSample(x: 8, y: 8), VectorSample(x: 24, y: 8)])
            manager.layers[0].cels[0].interpolation?.localEdits = [LocalEdit(stroke: stroke)]
        }
        let recipe = try recipeURL(package)
        let manifest = try object(package.appendingPathComponent("manifest.json"))
        let table = package.appendingPathComponent(try XCTUnwrap(manifest["brushTableFileName"] as? String))
        try edit(table) { json in
            var entries = json["entries"] as! [[String: Any]]
            for i in entries.indices { entries[i]["ref"] = (entries[i]["ref"] as! Int) + 500_000 }
            json["entries"] = entries
        }
        try edit(recipe) { json in
            var edits = json["localEdits"] as! [[String: Any]]
            var stroke = edits[0]["stroke"] as! [String: Any]
            stroke["brush"] = (stroke["brush"] as! Int) + 500_000
            edits[0]["stroke"] = stroke; json["localEdits"] = edits
            json.removeValue(forKey: "deformations")
        }
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: package))
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .repaired)
        let loaded = try XCTUnwrap(ProjectStore.load(from: package))
        XCTAssertEqual(loaded.layers[0].cels[0].interpolation?.localEdits.first?.stroke.brush, TestBrushes.hardRound)
    }

    func testPresentMalformedLiquifySelectionFailsCurrentReadsAndRepairWithoutChangingBytes() throws {
        let selection = CGPath(rect: CGRect(x: 0, y: 0, width: 20, height: 20), transform: nil)
        let package = try package { manager in
            manager.layers[0].cels[0].interpolation?.deformations = [LiquifyDeformation(
                brush: TestBrushes.hardRound, size: 12, power: 0.5, mode: .expand, seed: 123,
                samples: [VectorSample(x: 10, y: 10, pressure: 1)], selection: selection)]
        }
        XCTAssertTrue(ProjectBackupManager.validateProject(at: package))
        XCTAssertNotNil(ProjectStore.load(from: package), "A valid secure selection archive opens")
        let recipe = try recipeURL(package)
        let manifest = package.appendingPathComponent("manifest.json")
        let currentManifest = try Data(contentsOf: manifest)
        for broken in [Data(), Data("not a secure path archive".utf8)] {
            try currentManifest.write(to: manifest, options: .atomic)
            try edit(recipe) { json in
                var deformations = json["deformations"] as! [[String: Any]]
                deformations[0]["selection"] = broken.base64EncodedString()
                json["deformations"] = deformations
            }
            XCTAssertFalse(ProjectBackupManager.validateProject(at: package))
            XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package))
            XCTAssertNil(ProjectStore.load(from: package), "A corrupt saved mask must not become an unlimited field")
            // Force a genuine pending repair write: invalid selection metadata must prevent it.
            try edit(manifest) { json in
                var editor = json["editorState"] as! [String: Any]
                var tools = editor["tools"] as! [String: Any]
                tools.removeValue(forKey: "liquifyMode")
                editor["tools"] = tools; json["editorState"] = editor
            }
            let before = try Data(contentsOf: manifest)
            XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .unreadable)
            XCTAssertEqual(try Data(contentsOf: manifest), before)
        }
    }

    func testDeformationImportedTipTravelsAndRestoresWithoutAnyPaletteEntry() throws {
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(x: 4, y: 0, width: 8, height: 16))
        }
        let tip = try BrushTipImport.importTip(from: image)
        let name = try XCTUnwrap(tip.importedTextureFileName)
        defer { BrushStorage.shared.remove(name) }
        let brush = Brush(name: "recipe-only", tip: tip, size: 12)
        let package = try package { manager in
            manager.layers[0].cels[0].interpolation?.deformations = [LiquifyDeformation(
                brush: brush, size: 12, power: 0.5, mode: .push, seed: 123,
                samples: StrokeSamples([VectorSample(x: 8, y: 8), VectorSample(x: 24, y: 8)], channels: .pressureOnly))]
        }
        let copied = package.appendingPathComponent("brushes/\(name)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        BrushStorage.shared.remove(name)
        XCTAssertFalse(BrushStorage.shared.contains(name))
        let loaded = try XCTUnwrap(ProjectStore.load(from: package))
        XCTAssertTrue(BrushStorage.shared.contains(name))
        XCTAssertEqual(loaded.layers[0].cels[0].interpolation?.deformations.first?.brush, brush)
    }

    func testGenuinePriorBuildPackagePreservesSnapshotLinksAndPixelsThroughCurrentRoundTrip() throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "liquify-before-deformation", withExtension: "paintproj"))
        let project = root.appendingPathComponent("Projects/prior.paintproj")
        try FileManager.default.createDirectory(at: project.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: project)
        func bytes(_ package: URL) throws -> [String: Data] {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey]))
            var result: [String: Data] = [:]
            for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(package.path.count))] = try Data(contentsOf: file)
            }
            return result
        }
        let original = try bytes(project)
        XCTAssertFalse(ProjectBackupManager.validateProject(at: project))
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: project))
        let prefix = ProjectBackupManager.takeUpdateSnapshotIfNeeded()
        let snapshot = try XCTUnwrap(LibraryRepair.packages(leavingUntouched: nil).first { $0.url.lastPathComponent.hasPrefix(prefix) }?.url)
        XCTAssertEqual(try bytes(snapshot), original)
        LegacyMaskRepair.repairLibrary()
        LegacyLiquifyRepair.repairLibrary()
        XCTAssertEqual(try bytes(snapshot), original)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: project))
        let loaded = try XCTUnwrap(ProjectStore.load(from: project))
        let layer = try XCTUnwrap(loaded.layers.first)
        let linked = layer.cels.filter { $0.interpolation != nil }
        XCTAssertEqual(layer.cels.count, 5)
        XCTAssertEqual(linked.map(\.startFrame), [4, 12])
        let references = linked.map { $0.interpolation!.references }
        for cel in linked {
            let recipe = try XCTUnwrap(cel.interpolation)
            XCTAssertTrue(recipe.deformations.isEmpty)
            for ref in recipe.references.flatMap(\.cels) {
                XCTAssertEqual(ref.layerID, layer.id)
                XCTAssertTrue(layer.cels.contains { $0.id == ref.celID && $0.vector?.strokes.count == 2 })
            }
        }
        let cel = try XCTUnwrap(linked.last)
        let picture = try XCTUnwrap(loaded.interpolatedImage(forCel: cel.id, inLayer: layer.id)?.cgImage)
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(picture))
        var black = 0, red = 0
        for i in stride(from: 0, to: before.count, by: 4) where before[i + 3] > 64 {
            if before[i] < 20 && before[i + 1] < 20 { black += 1 }
            if before[i] > 30 && before[i + 1] < 30 { red += 1 }
        }
        XCTAssertGreaterThan(black, 1000)
        XCTAssertGreaterThan(red, 1000)
        let current = root.appendingPathComponent("Projects/current.paintproj")
        let saved = expectation(description: "roundtrip prior scene")
        ProjectStore.save(loaded, to: current) { saved.fulfill() }
        wait(for: [saved], timeout: 30)
        let reopened = try XCTUnwrap(ProjectStore.load(from: current))
        XCTAssertEqual(reopened.layers[0].cels.compactMap { $0.interpolation?.references }, references)
        let after = try XCTUnwrap(reopened.interpolatedImage(forCel: cel.id, inLayer: layer.id)?.cgImage)
        XCTAssertEqual(CanvasFixture.rgbaBytes(after), before)
        XCTAssertTrue(ProjectBackupManager.restoreBackup(at: snapshot, toProjectAt: current))
        XCTAssertEqual(try bytes(snapshot), original)
        XCTAssertNotNil(ProjectStore.load(from: current))
    }

    func testDirectSyncAndBackgroundOpenRefuseMissingOrMalformedLinkedRecipe() async throws {
        let package = try await packageAsync(), recipe = try recipeURL(package)
        try edit(recipe) { $0["deformations"] = "unreadable" }
        XCTAssertNil(ProjectStore.load(from: package))
        let malformed = await ProjectStore.loadInBackground(from: package)
        XCTAssertNil(malformed)
        try FileManager.default.removeItem(at: recipe)
        XCTAssertNil(ProjectStore.load(from: package))
        let missing = await ProjectStore.loadInBackground(from: package)
        XCTAssertNil(missing)
    }

    func testFailedStagedRepairLeavesLiveProjectAndSourceVersionUntouched() throws {
        let live = try package("Projects/live.paintproj")
        let backup = try package("Backups/earlier.paintproj"), recipe = try recipeURL(backup)
        try makeEarlier(backup, recipe: recipe)
        let manifest = backup.appendingPathComponent("manifest.json")
        try edit(manifest) { json in
            var editor = json["editorState"] as! [String: Any]
            var tools = editor["tools"] as! [String: Any]
            tools["liquifyMode"] = "unreadable"
            editor["tools"] = tools; json["editorState"] = editor
        }
        let liveBefore = try Data(contentsOf: live.appendingPathComponent("manifest.json"))
        let backupBefore = try Data(contentsOf: manifest), recipeBefore = try Data(contentsOf: recipe)
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: backup))
        XCTAssertFalse(ProjectBackupManager.restoreBackup(at: backup, toProjectAt: live))
        XCTAssertEqual(try Data(contentsOf: live.appendingPathComponent("manifest.json")), liveBefore)
        XCTAssertEqual(try Data(contentsOf: manifest), backupBefore)
        XCTAssertEqual(try Data(contentsOf: recipe), recipeBefore)
        XCTAssertTrue(ProjectBackupManager.allProjectPackages(in: root.appendingPathComponent("Trash")).isEmpty)
    }

    func testLibraryWalkRepairsProjectsBackupsAndTrashWhilePreservingCurrentUpdateSnapshot() throws {
        var packages: [URL] = []
        for name in ["Projects/a.paintproj", "Backups/a/latest.paintproj", "Trash/a.paintproj"] {
            let package = try package(name) { manager in
                let ink = VectorStroke(brush: TestBrushes.pencil,
                    color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 4, opacity: 1,
                    samples: StrokeSamples(points: [CGPoint(x: 8, y: 8), CGPoint(x: 40, y: 40)]))
                manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(ink)])
            }
            let recipe = try recipeURL(package), drawing = try vectorURL(package)
            try makeEarlier(package, recipe: recipe); packages.append(package)
            try edit(drawing) { json in
                json.removeValue(forKey: "materialOperations")
                var elements = json["elements"] as! [[String: Any]], stroke = elements[0]["stroke"] as! [String: Any]
                stroke.removeValue(forKey: "placement"); elements[0]["stroke"] = stroke; json["elements"] = elements
            }
        }
        let prefix = ProjectBackupManager.takeUpdateSnapshotIfNeeded()
        let untouched = LibraryRepair.packages(leavingUntouched: nil).filter { $0.url.lastPathComponent.hasPrefix(prefix) }
        XCTAssertFalse(untouched.isEmpty)
        let before = try untouched.map { try fileBytes($0.url) }
        LegacyLiquifyRepair.repairLibrary()
        for package in packages {
            XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .current)
            XCTAssertEqual(ProjectStore.load(from: package)?.layers[0].cels[0].vector?.strokes.count, 1)
        }
        XCTAssertEqual(try untouched.map { try fileBytes($0.url) }, before)
    }

    func testMaterialDamageAbortsBothOpenPathsAndStagedRestoreWithoutChangingEitherPackage() async throws {
        let operation = materialOperation()
        let package = try await packageAsync { manager in
            manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize,
                elements: [.stroke(materialStroke(operation))])
            manager.layers[0].cels[0].interpolation?.localEdits = [LocalEdit(stroke: materialStroke(operation))]
        }
        let drawing = try vectorURL(package), recipe = try recipeURL(package)
        let goodDrawing = try Data(contentsOf: drawing), goodRecipe = try Data(contentsOf: recipe)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: package), "PREMISE: valid material opens")
        let live = try await packageAsync("Projects/live.paintproj")
        let liveBefore = try fileBytes(live)
        for fault in ["dangling", "missing placement", "recipe local"] {
            try goodDrawing.write(to: drawing); try goodRecipe.write(to: recipe)
            if fault == "recipe local" {
                try edit(recipe) { $0["materialOperations"] = [] }
            } else {
                try edit(drawing) { json in
                    var elements = json["elements"] as! [[String: Any]]
                    var stroke = elements[0]["stroke"] as! [String: Any]
                    if fault == "dangling" { json["materialOperations"] = [] }
                    else { stroke.removeValue(forKey: "placement") }
                    // Ordinary lossy damage must not hide unreadable material.
                    stroke["color"] = "unreadable"
                    elements[0]["stroke"] = stroke; json["elements"] = elements
                }
            }
            let before = try fileBytes(package)
            XCTAssertNil(ProjectStore.load(from: package), fault)
            let background = await ProjectStore.loadInBackground(from: package)
            XCTAssertNil(background, fault)
            XCTAssertFalse(ProjectBackupManager.validateProject(at: package), fault)
            XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package), fault)
            XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .unreadable, fault)
            XCTAssertFalse(ProjectBackupManager.restoreBackup(at: package, toProjectAt: live), fault)
            XCTAssertEqual(try fileBytes(package), before, "failed material read must not rewrite its source")
            XCTAssertEqual(try fileBytes(live), liveBefore, "failed repair must not replace the live scene")
        }
    }

    func testMaterialOnlyImportedTipsTravelForStrokesFillsAndRecipeLocalEdits() throws {
        var names: [String] = [], operations: [InkMaterialOperation] = []
        defer { for name in names { BrushStorage.shared.remove(name) } }
        for width in [3, 7, 11] {
            let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
                context.cgContext.setFillColor(UIColor.black.cgColor)
                context.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: 16))
            }
            let tip = try BrushTipImport.importTip(from: image)
            names.append(try XCTUnwrap(tip.importedTextureFileName))
            operations.append(materialOperation(brush: Brush(name: "material-only", tip: tip, size: 16)))
        }
        XCTAssertEqual(Set(names).count, 3, "PREMISE: independent operation-only assets")
        let package = try package { manager in
            var fill = VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 40, height: 40), transform: nil),
                color: CodableColor(red: 0.3, green: 0.6, blue: 0.1, alpha: 1))
            fill.placement = FillPlacement(pathData: fill.pathData,
                material: InkMaterialProgram(bindings: [InkMaterialBinding(operation: operations[1], bridge: .identity)]))
            manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize,
                elements: [.stroke(materialStroke(operations[0])), .fill(fill)])
            manager.layers[0].cels[0].interpolation?.localEdits = [LocalEdit(stroke: materialStroke(operations[2]))]
        }
        for name in names {
            XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("brushes/\(name)").path))
            BrushStorage.shared.remove(name)
            XCTAssertFalse(BrushStorage.shared.contains(name))
        }
        let loaded = try XCTUnwrap(ProjectStore.load(from: package))
        for name in names { XCTAssertTrue(BrushStorage.shared.contains(name), "material-only texture must restore") }
        let programs = loaded.layers[0].cels[0].vector!.elements.compactMap(\.materialProgram)
            + loaded.layers[0].cels[0].interpolation!.localEdits.compactMap { $0.stroke.placement?.material }
        XCTAssertEqual(programs.flatMap { $0.bindings.map { $0.operation.deformation } }, operations.map(\.deformation))
    }

    func testFailedJSONEncodingCannotReplaceTheLastGoodSave() throws {
        let shared = materialOperation()
        let package = try package { manager in
            manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize,
                elements: [.stroke(materialStroke(shared))])
        }
        let original = try fileBytes(package)
        for fault in ["vector conflict", "recipe conflict", "generic encoding error"] {
            let loaded = try XCTUnwrap(ProjectStore.load(from: package))
            var conflict = shared.deformation; conflict.power = 0.9
            let strokes = [materialStroke(shared), materialStroke(InkMaterialOperation(conflict))]
            if fault == "recipe conflict" {
                loaded.layers[0].cels[0].interpolation?.localEdits = strokes.map { LocalEdit(stroke: $0) }
            } else if fault == "generic encoding error" {
                var invalid = materialStroke(shared)
                // This optional metadata is not read by an ordinary vector render, but JSON cannot
                // encode it. Exercise EncodingError as well as the material table's own error type.
                invalid.visibilityThreshold = .nan
                loaded.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(invalid)])
            } else {
                loaded.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: strokes.map(VectorElement.stroke))
            }
            let saved = expectation(description: "reject conflicting material")
            ProjectStore.save(loaded, to: package) { saved.fulfill() }
            wait(for: [saved], timeout: 30)
            XCTAssertEqual(try fileBytes(package), original,
                           "\(fault): a failed sidecar must abort the atomic swap")
            XCTAssertNotNil(ProjectStore.load(from: package))
            let failed = ProjectBackupManager.allProjectPackages(in: root.appendingPathComponent("Trash"))
                .filter { $0.lastPathComponent.contains("__failedsave__") }
            XCTAssertFalse(failed.isEmpty, "failed stage is retained for diagnosis")
            for stage in failed {
                XCTAssertFalse(ProjectBackupManager.validateProject(at: stage), "failed stage must remain incomplete on disk")
                XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: stage), "runtime error state must not be needed to reject restore")
                XCTAssertFalse(ProjectBackupManager.restoreBackup(at: stage, toProjectAt: package))
            }
            XCTAssertEqual(try fileBytes(package), original, "a diagnostic failed stage cannot replace the good project later")
        }
    }

    func testLegacyDistortRepairMovesPackedNativeRunsAndPreservesLiveCutRange() throws {
        let native = StrokeSamples(points: [CGPoint(x: 4.125, y: 12.375), CGPoint(x: 16.4375, y: 18.8125),
            CGPoint(x: 32.0625, y: 10.1875), CGPoint(x: 52.6875, y: 20.5625)])
        let own = StrokeSamples([native[1], native[2]], channels: .pressureOnly)
        let map = Homography(CGAffineTransform(translationX: 1.25, y: 3.75))
        var strokes: [VectorStroke] = []
        for precise in [false, true] {
            var ink = VectorStroke(brush: TestBrushes.pencil,
                color: CodableColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1), size: 6, opacity: 1,
                samples: try XCTUnwrap(own.mapped(through: map)),
                lattice: DabLattice(samples: try XCTUnwrap(native.mapped(through: map)), parameters: [1, 2], precise: precise),
                placement: StrokePlacement(map: map, restSize: 6,
                    source: .retained(samples: own,
                        lattice: DabLattice(samples: native, parameters: [1, 2], precise: precise), precise: precise)))
            if precise { ink = ink.markedPrecise() }
            strokes.append(ink)
        }
        var derived = strokes[0]; derived.id = UUID(); derived.placement?.source = .derived
        strokes.append(derived)
        let package = try package { manager in
            let fill = VectorFillElement(path: CGPath(rect: CGRect(x: 4, y: 4, width: 8, height: 8), transform: nil),
                color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
            manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize,
                elements: strokes.map(VectorElement.stroke) + [.fill(fill)])
            manager.layers[0].cels[0].interpolation?.localEdits = [LocalEdit(stroke: strokes[1])]
        }
        let drawing = try vectorURL(package), recipe = try recipeURL(package)
        let current = try XCTUnwrap(ProjectStore.load(from: package))
        let expected = try XCTUnwrap(current.layers[0].cels[0].vector)
        let expectedPixels = try XCTUnwrap(CanvasFixture.rgbaBytes(XCTUnwrap(expected.render(quality: .full)?.cgImage)))
        // A synthetic wire-shape unit fixture. Genuine prior-writer packages are tested separately.
        func oldStroke(_ original: [String: Any]) -> [String: Any] {
            var ink = original
            if let placement = ink.removeValue(forKey: "placement") as? [String: Any] {
                ink["distort"] = ["map": placement["map"]!, "restSize": placement["restSize"]!]
                let source = placement["source"] as! [String: Any]
                if source["kind"] as? String == "retained" {
                    ink["distortRest"] = source["samples"]
                    if var lattice = source["lattice"] as? [String: Any] {
                        lattice["parameters"] = [0, 3] // The old renderer deliberately ignored these.
                        ink["distortRestLattice"] = lattice
                    }
                }
            }
            return ink
        }
        try edit(drawing) { json in
            json.removeValue(forKey: "materialOperations")
            var elements = json["elements"] as! [[String: Any]]
            for i in elements.indices {
                if let stroke = elements[i]["stroke"] as? [String: Any] { elements[i]["stroke"] = oldStroke(stroke) }
                if var fill = elements[i]["fill"] as? [String: Any] { fill.removeValue(forKey: "placement"); elements[i]["fill"] = fill }
            }
            json["elements"] = elements
        }
        try edit(recipe) { json in
            json.removeValue(forKey: "materialOperations")
            var edits = json["localEdits"] as! [[String: Any]]
            edits[0]["stroke"] = oldStroke(edits[0]["stroke"] as! [String: Any]); json["localEdits"] = edits
        }
        let old = try object(drawing)["elements"] as! [[String: Any]]
        XCTAssertFalse(ProjectBackupManager.validateProject(at: package))
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: package))
        let validOldDrawing = try Data(contentsOf: drawing)
        try edit(drawing) { json in
            var elements = json["elements"] as! [[String: Any]]
            var stroke = elements[0]["stroke"] as! [String: Any]
            stroke["distortRest"] = "unreadable native samples"
            elements[0]["stroke"] = stroke; json["elements"] = elements
        }
        let invalidBefore = try fileBytes(package)
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .unreadable)
        XCTAssertEqual(try fileBytes(package), invalidBefore, "invalid native geometry must prevent every planned write")
        try validOldDrawing.write(to: drawing)
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .repaired)
        let repaired = try XCTUnwrap(ProjectStore.load(from: package))
        let ink = try XCTUnwrap(repaired.layers[0].cels[0].vector)
        XCTAssertEqual(ink.strokes.map(\.placement), expected.strokes.map(\.placement))
        XCTAssertEqual(ink.strokes.map(\.precise), [false, true, false])
        XCTAssertEqual(repaired.layers[0].cels[0].interpolation?.localEdits.first?.stroke.placement,
                       current.layers[0].cels[0].interpolation?.localEdits.first?.stroke.placement)
        XCTAssertEqual(try XCTUnwrap(CanvasFixture.rgbaBytes(XCTUnwrap(ink.render(quality: .full)?.cgImage))), expectedPixels)
        let new = try object(drawing)["elements"] as! [[String: Any]]
        for i in 0..<2 {
            let priorStroke = old[i]["stroke"] as! [String: Any], stroke = new[i]["stroke"] as! [String: Any]
            let source = (stroke["placement"] as! [String: Any])["source"] as! [String: Any]
            XCTAssertTrue(NSDictionary(dictionary: source["samples"] as! [String: Any])
                .isEqual(to: priorStroke["distortRest"] as! [String: Any]), "packed origin, channels and bytes move without quantisation")
            XCTAssertNil(stroke["distort"]); XCTAssertNil(stroke["distortRest"]); XCTAssertNil(stroke["distortRestLattice"])
        }
        let beforeSecondRun = try fileBytes(package)
        XCTAssertEqual(LegacyLiquifyRepair.repair(packageAt: package), .current)
        XCTAssertEqual(try fileBytes(package), beforeSecondRun)
    }
    func testGenuinePreMaterialWriterPreservesDistortNativeWalksAndRenderedBytes() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "material-before-placement-evidence", withExtension: nil))
        let source = fixture.appendingPathComponent("material-before-placement.paintproj")
        let original = try fileBytes(source)
        let package = root.appendingPathComponent("Projects/native-placement.paintproj")
        try FileManager.default.createDirectory(at: package.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: package)
        let expected = try Data(contentsOf: fixture.appendingPathComponent("native.rgba"))
        let nativeWalks = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("native-walks.json")))
        XCTAssertEqual(expected.count, 64 * 64 * 4, "old app's independently rendered RGBA baseline")
        XCTAssertFalse(ProjectBackupManager.validateProject(at: package))
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: package))
        XCTAssertTrue(LibraryRepair.prepareForCurrentRead(package))
        let loaded = try XCTUnwrap(ProjectStore.load(from: package))
        func positions(_ samples: StrokeSamples) -> [[Double]] {
            samples.map { [Double($0.x), Double($0.y), Double($0.pressure)] }
        }
        func record(_ stroke: VectorStroke) -> [String: Any] {
            var result: [String: Any] = ["id": stroke.id.uuidString, "samples": positions(stroke.samples),
                "precise": stroke.precise, "size": Double(stroke.size)]
            if let walk = stroke.effectiveWalk {
                result["nativeSamples"] = positions(walk.samples)
                result["nativeSize"] = Double(walk.size)
                if let lattice = walk.lattice {
                    result["nativeParent"] = positions(lattice.samples)
                    result["nativeParameters"] = lattice.parameters.map(Double.init)
                    result["parentPrecise"] = lattice.precise
                }
            }
            return result
        }
        func verify(_ manager: CanvasManager) throws {
            let vector = try XCTUnwrap(manager.layers[1].cels[0].vector)
            let records = vector.strokes.map(record)
                + manager.layers[1].cels[1].interpolation!.localEdits.map { record($0.stroke) }
            XCTAssertEqual(records.count, 5)
            XCTAssertTrue(NSArray(array: records).isEqual(nativeWalks), "current native walks must equal the old writer's independent source records")
            let image = try XCTUnwrap(vector.render(quality: .full)?.cgImage)
            XCTAssertEqual(Data(try XCTUnwrap(CanvasFixture.rgbaBytes(image))), expected,
                           "migrated native material must match the old app's rendered bytes")
        }
        try verify(loaded)
        let current = root.appendingPathComponent("Projects/native-current.paintproj")
        let saved = expectation(description: "roundtrip repaired native placements")
        ProjectStore.save(loaded, to: current) { saved.fulfill() }
        wait(for: [saved], timeout: 30)
        try verify(XCTUnwrap(ProjectStore.load(from: current)))
        XCTAssertTrue(ProjectBackupManager.restoreBackup(at: source, toProjectAt: current))
        try verify(XCTUnwrap(ProjectStore.load(from: current)))
        XCTAssertEqual(try fileBytes(source), original, "genuine producer package must stay pristine")
    }
}
