import XCTest
import SwiftUI

@MainActor
final class ProjectStorageIntegrityLogicTests: XCTestCase {
    private var root: URL!
    private var defaultsName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-integrity-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defaultsName = "storage-integrity-\(UUID())"
        ProjectBackupManager.settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsName)))
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        ProjectBackupManager.settings = .standard
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: root)
    }

    private func package(_ name: String = "Projects/current.paintproj",
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

    private func placedStroke() -> VectorStroke {
        let samples = StrokeSamples(points: [CGPoint(x: 8, y: 12), CGPoint(x: 48, y: 18)])
        return VectorStroke(brush: TestBrushes.pencil,
            color: CodableColor(red: 0.6, green: 0.1, blue: 0.2, alpha: 1), size: 5, opacity: 0.8,
            samples: samples, placement: StrokePlacement(map: .identity, restSize: 5,
                source: .retained(samples: samples, lattice: nil, precise: true)))
    }

    private func fileBytes(_ package: URL) throws -> [String: Data] {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(package.path.count))] = try Data(contentsOf: file)
        }
        return result
    }

    func testMissingSidecarFailsBothMetadataPreflights() throws {
        let package = try package(), recipe = try recipeURL(package)
        try FileManager.default.removeItem(at: recipe)
        XCTAssertFalse(ProjectBackupManager.validateProject(at: package))
        XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package))
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
        }
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: package))
        let loaded = try XCTUnwrap(ProjectStore.load(from: package))
        XCTAssertEqual(loaded.layers[0].cels[0].interpolation?.localEdits.first?.stroke.brush, TestBrushes.hardRound)
    }

    func testPresentMalformedLiquifySelectionFailsCurrentReadsWithoutChangingBytes() throws {
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
            XCTAssertEqual(try Data(contentsOf: manifest), currentManifest)
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

    func testMalformedCurrentStreamCannotReplaceHealthyScene() throws {
        let backup = try package("Backups/stream.paintproj") { manager in
            let stream = VectorStreamElement(naturalSize: CGSize(width: 20, height: 8), host: "laptop", port: 47301,
                sourceLabel: "Saved reference", rendersInPlace: true,
                transform: LayerTransform(position: CGPoint(x: 32, y: 32), scale: 1, rotation: 0))
            manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stream(stream)])
        }
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: backup), "a current stream is restorable")
        let live = try package("Projects/live.paintproj"), liveBefore = try fileBytes(live)
        try edit(vectorURL(backup)) { json in
            var elements = json["elements"] as! [[String: Any]]
            var stream = elements[0]["stream"] as! [String: Any]
            stream["rendersInPlace"] = "damaged"
            elements[0]["stream"] = stream; json["elements"] = elements
        }
        let sourceBefore = try fileBytes(backup)
        XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: backup))
        XCTAssertFalse(ProjectBackupManager.restoreBackup(at: backup, toProjectAt: live),
                       "a malformed current stream cannot replace a healthy scene")
        XCTAssertEqual(try fileBytes(backup), sourceBefore, "restore validation preserves every source file")
        XCTAssertEqual(try fileBytes(live), liveBefore, "failed restore leaves live artwork untouched")
    }

    func testGeometryVersionDamageAbortsBothOpenPathsAndStagedRestoreWithoutChangingEitherPackage() async throws {
        let package = try await packageAsync { manager in
            manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize,
                elements: [.stroke(placedStroke())])
        }
        let drawing = try vectorURL(package), recipe = try recipeURL(package)
        let goodDrawing = try Data(contentsOf: drawing), goodRecipe = try Data(contentsOf: recipe)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: package))
        let live = try await packageAsync("Projects/live.paintproj")
        let liveBefore = try fileBytes(live)
        for file in [drawing, recipe] {
            try goodDrawing.write(to: drawing); try goodRecipe.write(to: recipe)
            try edit(file) { $0["geometryVersion"] = 2 }
            let before = try fileBytes(package)
            XCTAssertNil(ProjectStore.load(from: package))
            let background = await ProjectStore.loadInBackground(from: package)
            XCTAssertNil(background)
            XCTAssertFalse(ProjectBackupManager.validateProject(at: package))
            XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package))
            XCTAssertFalse(ProjectBackupManager.restoreBackup(at: package, toProjectAt: live))
            XCTAssertEqual(try fileBytes(package), before)
            XCTAssertEqual(try fileBytes(live), liveBefore)
        }
    }

    func testRecipeGestureImportedTipTravelsWithoutAnyStrokeUsingIt() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: PixelOps.transparentFormat()).image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 7, height: 16))
        }
        let tip = try BrushTipImport.importTip(from: image)
        let name = try XCTUnwrap(tip.importedTextureFileName)
        defer { BrushStorage.shared.remove(name) }
        let gesture = LiquifyDeformation(brush: Brush(name: "gesture-only", tip: tip, size: 16),
            size: 16, power: 0.4, mode: .push, seed: 43,
            samples: StrokeSamples(points: [CGPoint(x: 12, y: 12), CGPoint(x: 20, y: 16)]))
        let package = try package { $0.layers[0].cels[0].interpolation?.deformations = [gesture] }
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("brushes/\(name)").path))
        BrushStorage.shared.remove(name)
        let loaded = try XCTUnwrap(ProjectStore.load(from: package))
        XCTAssertTrue(BrushStorage.shared.contains(name))
        XCTAssertEqual(loaded.layers[0].cels[0].interpolation?.deformations, [gesture])
    }

    func testFailedJSONEncodingCannotReplaceTheLastGoodSave() throws {
        let package = try package { manager in
            manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize,
                elements: [.stroke(placedStroke())])
        }
        let original = try fileBytes(package)
        for fault in ["vector placement", "recipe placement", "generic encoding error"] {
            let loaded = try XCTUnwrap(ProjectStore.load(from: package))
            var invalid = placedStroke()
            if fault == "generic encoding error" { invalid.visibilityThreshold = .nan }
            else { invalid.placement?.restSize = .nan }
            if fault == "recipe placement" {
                loaded.layers[0].cels[0].interpolation?.localEdits = [LocalEdit(stroke: invalid)]
            } else {
                loaded.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(invalid)])
            }
            let saved = expectation(description: "reject unreadable geometry")
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

}
