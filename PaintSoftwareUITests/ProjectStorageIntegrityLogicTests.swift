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
        ProjectStore.save(manager, to: url) { _ in saved.fulfill() }
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
        ProjectStore.save(manager, to: url) { _ in saved.fulfill() }
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

    private func corruptFirstRecentColor(in package: URL) throws -> Data {
        let manifestURL = package.appendingPathComponent("manifest.json")
        var json = try object(manifestURL)
        var editorState = try XCTUnwrap(json["editorState"] as? [String: Any])
        var tools = try XCTUnwrap(editorState["tools"] as? [String: Any])
        var panel = try XCTUnwrap(tools["colorPanel"] as? [String: Any])
        var recent = try XCTUnwrap(panel["recentColors"] as? [[String: Any]])
        XCTAssertFalse(recent.isEmpty, "The fixture must persist an actual recent swatch")
        recent[0]["hex"] = "not-a-color"
        panel["recentColors"] = recent
        tools["colorPanel"] = panel
        editorState["tools"] = tools
        json["editorState"] = editorState
        let damaged = try JSONSerialization.data(withJSONObject: json)
        try damaged.write(to: manifestURL, options: .atomic)
        return damaged
    }

    private func recipeURL(_ package: URL) throws -> URL {
        let manifest = try JSONDecoder().decode(ProjectManifest.self,
            from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        let cel = try XCTUnwrap(manifest.layers.first?.cels.first)
        return try ProjectPackageLayout.existingURL(named: try XCTUnwrap(cel.interpolationFileName),
            role: .interpolation, cel: cel.id, in: package)
    }

    private func vectorURL(_ package: URL) throws -> URL {
        let manifest = try JSONDecoder().decode(ProjectManifest.self,
            from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        let cel = try XCTUnwrap(manifest.layers.flatMap(\.cels).first { $0.vectorFileName != nil })
        return try ProjectPackageLayout.existingURL(named: try XCTUnwrap(cel.vectorFileName),
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

    func testCurrentTruncatedDrawingAndRecipeRecoverFromBackupAndPreserveDamagedPackages() throws {
        for drawingDamage in [true, false] {
            let package = try package("Projects/\(drawingDamage ? "drawing" : "recipe").paintproj") { manager in
                manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize,
                    elements: [.stroke(placedStroke())])
            }
            let goodBytes = try fileBytes(package)
            let manifest = try JSONDecoder().decode(ProjectManifest.self,
                from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
            let latest = ProjectBackupManager.latestSnapshotURL(
                directory: ProjectBackupManager.backupsDirectory(projectID: manifest.id))
            XCTAssertEqual(try fileBytes(latest), goodBytes, "The current writer supplies an exact valid backup")
            let damagedFile = try (drawingDamage ? vectorURL(package) : recipeURL(package))
            try Data("{ truncated current JSON".utf8).write(to: damagedFile)
            let damagedBytes = try fileBytes(package)
            XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package))

            ProjectBackupManager.repairCorruptedProjects()

            XCTAssertEqual(try fileBytes(package), goodBytes,
                           "Recovery restores the current writer's complete package bytes")
            let loaded = try XCTUnwrap(ProjectStore.load(from: package))
            XCTAssertFalse(loaded.loadDamage.isDamaged)
            XCTAssertEqual(loaded.layers[0].cels[0].vector?.strokes.count, 1)
            XCTAssertNotNil(loaded.layers[0].cels[0].interpolation)
            let preserved = try XCTUnwrap(ProjectBackupManager.listTrash().first {
                $0.displayName == package.deletingPathExtension().lastPathComponent
            })
            XCTAssertEqual(try fileBytes(preserved.url), damagedBytes,
                           "Every damaged original file remains recoverable in Trash")
        }
    }

    func testUnrepresentableCurrentVideoTimingRecoversExactBackupAndPreservesTheOriginal() throws {
        for expansion in [true, false] {
            let asset = root.appendingPathComponent("finite-\(expansion).mov")
            try Data("package asset; timing preflight reads no pixels".utf8).write(to: asset)
            let package = try package("Projects/video-\(expansion).paintproj") { manager in
                manager.addVectorLayer()
                manager.layers[1].cels[0].vector?.elements = [.stroke(placedStroke()), .video(VectorVideoElement(
                    assetURL: asset, assetFileName: asset.lastPathComponent, naturalSize: CGSize(width: 16, height: 16),
                    sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 1), speed: 1,
                    transform: LayerTransform(position: CGPoint(x: 24, y: 24), scale: 1, rotation: 0), mappedFrameRate: 24))]
                manager.layers[1].cels[0].vector?.bumpVersion()
            }
            let manifest = try JSONDecoder().decode(ProjectManifest.self,
                from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
            let good = try fileBytes(package)
            let latest = ProjectBackupManager.latestSnapshotURL(directory: ProjectBackupManager.backupsDirectory(projectID: manifest.id))
            XCTAssertEqual(try fileBytes(latest), good, "PREMISE: the actual current writer made an exact intact backup")
            XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: package), "PREMISE: the saved current timing is readable")
            let drawing = try vectorURL(package)
            try edit(drawing) { json in
                var elements = json["elements"] as! [[String: Any]]
                let index = elements.firstIndex { $0["kind"] as? String == "video" }!
                var video = elements[index]["video"] as! [String: Any]
                if expansion {
                    video["sourceStart"] = ["value": Int64.max - 1, "timescale": 1] as [String: Any]
                    video["sourceEnd"] = ["value": Int64.max, "timescale": 1] as [String: Any]
                } else { video["speed"] = 1e-300 }
                elements[index]["video"] = video; json["elements"] = elements
            }
            let damaged = try fileBytes(package)
            XCTAssertFalse(ProjectBackupManager.validateProject(at: package), "Timing metadata fails before Gallery can open the package")
            XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package), "An unsafe current timing cannot become a replacement backup")
            XCTAssertNil(ProjectStore.load(from: package), "The direct open refuses instead of dropping the video into a successful scene")

            ProjectBackupManager.repairCorruptedProjects()

            XCTAssertEqual(try fileBytes(package), good, "Recovery restores every current-writer backup byte")
            let loaded = try XCTUnwrap(ProjectStore.load(from: package))
            XCTAssertEqual(loaded.layers[1].cels[0].vector?.videos.first?.speed, 1)
            XCTAssertEqual(loaded.layers[1].cels[0].vector?.strokes.count, 1, "The neighboring drawn ink remains with the recovered video")
            let preserved = try XCTUnwrap(ProjectBackupManager.listTrash().first {
                $0.displayName == package.deletingPathExtension().lastPathComponent
            })
            XCTAssertEqual(try fileBytes(preserved.url), damaged, "Every original file survives unchanged in Trash")
        }
    }

    func testTypedColorDamageRestoresValidBackupAndPreservesDamagedPackageInTrash() throws {
        let package = try package { $0.colorPanel.recordPainted(.red) }
        let manifestURL = package.appendingPathComponent("manifest.json")
        let validBytes = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ProjectManifest.self, from: validBytes)
        let latest = ProjectBackupManager.latestSnapshotURL(
            directory: ProjectBackupManager.backupsDirectory(projectID: manifest.id))
        XCTAssertEqual(try Data(contentsOf: latest.appendingPathComponent("manifest.json")), validBytes,
                       "The setup has an exact valid latest backup")

        let damagedBytes = try corruptFirstRecentColor(in: package)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: package),
                      "The lightweight file check alone does not inspect typed editor-state values")
        XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package),
                       "Strict current-format decoding rejects the malformed shared value")

        ProjectBackupManager.repairCorruptedProjects()

        XCTAssertEqual(try Data(contentsOf: manifestURL), validBytes,
                       "The valid backup becomes the live scene without normalizing its bytes")
        XCTAssertNotNil(ProjectStore.load(from: package), "The restored current-format scene opens")
        let trashed = try XCTUnwrap(ProjectBackupManager.listTrash().first)
        XCTAssertEqual(try Data(contentsOf: trashed.url.appendingPathComponent("manifest.json")), damagedBytes,
                       "The malformed original is retained exactly in Trash")
    }

    func testMalformedCurrentNodeRolesRecoverTheExactBackupAndPreserveTheDamagedPackage() throws {
        let brokenRoles: [(String, [String: Any])] = [
            ("missing-op", ["kind": "node"]),
            ("unknown-op", ["kind": "node", "op": "unrecognized"]),
            ("missing-mix", ["kind": "node", "op": "mix"]),
            ("unknown-mix", ["kind": "node", "op": "mix", "mixMode": "unrecognized"]),
            ("typed-op", ["kind": "node", "op": 17]),
            ("typed-mix", ["kind": "node", "op": "mix", "mixMode": 17])
        ]
        for (name, role) in brokenRoles {
            let package = try package("Projects/node-\(name).paintproj") { manager in
                let node = manager.addCompositorNode(op: .mix(.multiply), name: "Mix")
                XCTAssertNotNil(node, "PREMISE: the normal graph owner creates the saved node")
                if let node {
                    manager.restackLayer(manager.layers[0].id, above: .folder(node), parentFolderID: node)
                }
            }
            let manifestURL = package.appendingPathComponent("manifest.json")
            let original = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
            let node = try XCTUnwrap(original.folders.first)
            XCTAssertEqual(node.compositorRole, .node(op: .mix(.multiply)),
                           "PREMISE: the current writer persisted a real Mix node")
            let goodBytes = try fileBytes(package)
            let latest = ProjectBackupManager.latestSnapshotURL(
                directory: ProjectBackupManager.backupsDirectory(projectID: original.id))
            XCTAssertEqual(try fileBytes(latest), goodBytes, "PREMISE: the latest backup is the exact intact package")
            try edit(manifestURL) { json in
                var folders = json["folders"] as! [[String: Any]]
                folders[0]["compositorRole"] = role
                json["folders"] = folders
            }
            let damagedBytes = try fileBytes(package)
            XCTAssertTrue(ProjectBackupManager.validateProject(at: package),
                          "PREMISE: the lightweight resource check cannot detect a typed node-role error")
            XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: package),
                           "Full current-format readability rejects the malformed \(name) node role")
            XCTAssertNil(ProjectStore.load(from: package), "The malformed current role cannot open as a plain group")

            ProjectBackupManager.repairCorruptedProjects()

            XCTAssertEqual(try fileBytes(package), goodBytes,
                           "Recovery restores every intact backup byte instead of rewriting the node")
            let loaded = try XCTUnwrap(ProjectStore.load(from: package))
            XCTAssertEqual(loaded.folders.first { $0.id == node.id }?.compositorRole, .node(op: .mix(.multiply)),
                           "The recovered node keeps its actual compositing operation")
            let preserved = try XCTUnwrap(ProjectBackupManager.listTrash().first {
                $0.displayName == package.deletingPathExtension().lastPathComponent
            })
            XCTAssertEqual(try fileBytes(preserved.url), damagedBytes,
                           "Every malformed original package file remains intact in Trash")
        }
    }

    func testMalformedCurrentNodeWithoutBackupKeepsTheOriginalPackageAndDamagedGalleryEntry() throws {
        let package = try package("Projects/node-no-backup.paintproj") { manager in
            let node = manager.addCompositorNode(op: .mix(.screen), name: "Mix")
            XCTAssertNotNil(node, "PREMISE: the normal graph owner creates the saved node")
            if let node {
                manager.restackLayer(manager.layers[0].id, above: .folder(node), parentFolderID: node)
            }
        }
        let manifestURL = package.appendingPathComponent("manifest.json")
        let original = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(original.folders.first?.compositorRole, .node(op: .mix(.screen)),
                       "PREMISE: the current writer persisted a Mix node before corruption")
        try FileManager.default.removeItem(at: ProjectBackupManager.backupsDirectory(projectID: original.id))
        try edit(manifestURL) { json in
            var folders = json["folders"] as! [[String: Any]]
            folders[0]["compositorRole"] = 17
            json["folders"] = folders
        }
        let damagedBytes = try fileBytes(package)

        ProjectBackupManager.repairCorruptedProjects()

        XCTAssertEqual(try fileBytes(package), damagedBytes,
                       "Without a backup, maintenance preserves the malformed original package exactly")
        XCTAssertNil(ProjectStore.load(from: package), "Malformed current node payload cannot become a plain group")
        XCTAssertTrue(ProjectStore.listProjects(in: package.deletingLastPathComponent()).first?.isCorrupted == true,
                      "The original remains exposed as damaged in Gallery instead of disappearing")
        XCTAssertTrue(ProjectBackupManager.listTrash().isEmpty,
                      "A package with no intact replacement is not displaced into Trash")
    }

    func testTypedColorDamageWithoutBackupLeavesOriginalBytesAndGalleryEntry() throws {
        let package = try package { $0.colorPanel.recordPainted(.red) }
        let manifest = try JSONDecoder().decode(ProjectManifest.self,
            from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        try FileManager.default.removeItem(at: ProjectBackupManager.backupsDirectory(projectID: manifest.id))
        let damagedBytes = try corruptFirstRecentColor(in: package)

        ProjectBackupManager.repairCorruptedProjects()

        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent("manifest.json")), damagedBytes,
                       "With no valid backup, repair leaves the original package untouched")
        XCTAssertNil(ProjectStore.load(from: package))
        XCTAssertTrue(ProjectStore.listProjects(in: package.deletingLastPathComponent()).first?.isCorrupted == true,
                       "The unreadable package remains surfaced as damaged instead of vanishing")
        XCTAssertTrue(ProjectBackupManager.listTrash().isEmpty)
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
            ProjectStore.save(loaded, to: package) { _ in saved.fulfill() }
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
