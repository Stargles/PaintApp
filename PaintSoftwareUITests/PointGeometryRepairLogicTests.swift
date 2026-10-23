import XCTest
import SwiftUI
import Darwin

@MainActor
final class PointGeometryRepairLogicTests: XCTestCase {
    private var root: URL!
    private var suite: String!
    private var fixture: [String: Any]!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("point-repair-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "point-repair-" + UUID().uuidString
        ProjectBackupManager.rootDirectoryOverride = root
        ProjectBackupManager.settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        ProjectBackupManager.settings.lastAppSignature = ProjectBackupManager.currentAppSignature
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "point-geometry-previous-writer", withExtension: "json"))
        fixture = try object(Data(contentsOf: url))
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        ProjectBackupManager.settings = .standard
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func install(_ name: String, at relativePath: String? = nil) throws -> URL {
        let packages = try XCTUnwrap(fixture["packages"] as? [String: [String: String]])
        let files = try XCTUnwrap(packages[name])
        let package = root.appendingPathComponent(relativePath ?? "Projects/\(name).paintproj")
        for (path, encoded) in files {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(Data(base64Encoded: encoded)).write(to: url)
        }
        return package
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    private func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
    }
    private func bytes(_ directory: URL) throws -> [String: Data] {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(directory.path.count + 1))] = try Data(contentsOf: file)
        }
        return result
    }
    /// Failure may add recoverable owned stages, but may never change or remove an input file.
    /// Every added file must be a canonical owner record or belong to its independently owned copy.
    private func assertInputsPreserved(_ before: [String: Data], file: StaticString = #filePath, line: UInt = #line) throws {
        let after = try bytes(root)
        for (path, data) in before { XCTAssertEqual(after[path], data, path, file: file, line: line) }
        for path in Set(after.keys).subtracting(before.keys) {
            let components = path.split(separator: "/").map(String.init)
            let index = try XCTUnwrap(components.firstIndex(where: { $0.hasPrefix(".point-geometry-") }), path, file: file, line: line)
            let part = components[index]
            let stem = part.hasSuffix(".owner.json") ? String(part.dropLast(".owner.json".count)) : part
            let token = String(stem.dropFirst(".point-geometry-".count))
            XCTAssertEqual(UUID(uuidString: token)?.uuidString, token, file: file, line: line)
            let parent = components.prefix(index).joined(separator: "/")
            let stage = root.appendingPathComponent(parent).appendingPathComponent(stem)
            let record = stage.appendingPathExtension("owner.json")
            let owner = try object(Data(contentsOf: record))
            let originalName = try XCTUnwrap(owner["originalName"] as? String, file: file, line: line)
            XCTAssertEqual((originalName as NSString).lastPathComponent, originalName, file: file, line: line)
            XCTAssertEqual((originalName as NSString).pathExtension, "paintproj", file: file, line: line)
            if let stagedID = owner["staged"] as? NSDictionary {
                XCTAssertEqual(try directoryIdentity(stage) as NSDictionary, stagedID, file: file, line: line)
            }
        }
    }
    private func vectorURL(_ package: URL) throws -> URL {
        try XCTUnwrap(ProjectRecipeMetadata.reader(in: package).vectorURLs.first)
    }
    private func editVector(_ package: URL, _ edit: (inout [String: Any]) throws -> Void) throws {
        let url = try vectorURL(package)
        var value = try object(Data(contentsOf: url)); try edit(&value)
        try data(value).write(to: url)
    }
    private func assertSamples(_ run: StrokeSamples, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(Int(run.channels.rawValue), expected["channels"] as? Int, file: file, line: line)
        let values = try XCTUnwrap(expected["values"] as? [[Double]], file: file, line: line)
        XCTAssertEqual(run.count, values.count, file: file, line: line)
        for (sample, row) in zip(run, values) {
            XCTAssertEqual([Double(sample.x), Double(sample.y), Double(sample.pressure), Double(sample.deltaTime),
                Double(sample.tiltAltitude), Double(sample.tiltAzimuth)], row, file: file, line: line)
        }
    }
    private func assertGeometry(_ manager: CanvasManager, name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let all = try XCTUnwrap(fixture["expected"] as? [String: [String: Any]])
        let expected = try XCTUnwrap(all[name])
        XCTAssertEqual(try json(manager.toolProfiles) as? NSDictionary, expected["toolProfiles"] as? NSDictionary, file: file, line: line)
        XCTAssertEqual(manager.liquifyMode.rawValue, expected["liquifyMode"] as? String, file: file, line: line)
        let cels = try XCTUnwrap(expected["cels"] as? [[String: Any]])
        let actual = manager.layers.flatMap(\.cels)
        XCTAssertEqual(actual.count, cels.count, file: file, line: line)
        for (cel, saved) in zip(actual, cels) {
            let strokes = (cel.vector?.elements.compactMap(\.stroke) ?? []) + (cel.interpolation?.localEdits.map(\.stroke) ?? [])
            let originals = (saved["strokes"] as? [[String: Any]] ?? []) + (saved["localStrokes"] as? [[String: Any]] ?? [])
            XCTAssertEqual(strokes.count, originals.count, file: file, line: line)
            for (stroke, original) in zip(strokes, originals) {
                XCTAssertEqual(stroke.id.uuidString, original["id"] as? String, file: file, line: line)
                try assertSamples(stroke.samples, XCTUnwrap(original["samples"] as? [String: Any]), file: file, line: line)
                XCTAssertEqual(stroke.precise, original["precise"] as? Bool, file: file, line: line)
                XCTAssertEqual(try json(stroke.brush) as? NSDictionary, original["brush"] as? NSDictionary, file: file, line: line)
                XCTAssertEqual(Double(stroke.size), original["size"] as? Double, file: file, line: line)
                XCTAssertEqual(stroke.opacity, original["opacity"] as? Double, file: file, line: line)
                XCTAssertEqual(String(stroke.seed), original["seed"] as? String, file: file, line: line)
                if let lattice = original["lattice"] as? [String: Any] {
                    let current = try XCTUnwrap(stroke.lattice, file: file, line: line)
                    try assertSamples(current.samples, XCTUnwrap(lattice["samples"] as? [String: Any]), file: file, line: line)
                    XCTAssertEqual(current.parameters.map(Double.init), lattice["parameters"] as? [Double], file: file, line: line)
                    XCTAssertEqual(current.precise, lattice["precise"] as? Bool, file: file, line: line)
                } else { XCTAssertNil(stroke.lattice, file: file, line: line) }
            }
            let fills = cel.vector?.elements.compactMap { element -> VectorFillElement? in
                if case .fill(let fill) = element { return fill }; return nil } ?? []
            let oldFills = saved["fills"] as? [[String: Any]] ?? []
            XCTAssertEqual(fills.count, oldFills.count, file: file, line: line)
            for (fill, original) in zip(fills, oldFills) {
                var old = original
                old.removeValue(forKey: "placement")
                XCTAssertEqual(try json(fill) as? NSDictionary, old as NSDictionary, file: file, line: line)
            }
        }
    }

    private func directoryIdentity(_ url: URL) throws -> [String: Any] {
        var value = stat()
        guard url.withUnsafeFileSystemRepresentation({ lstat($0!, &value) }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return ["volume": Int64(value.st_dev), "inode": UInt64(value.st_ino)]
    }
    private func interruptedStage(_ original: URL, clone: Bool = true,
                                  recordStagedIdentity: Bool = true) throws -> (URL, URL) {
        let target = original.deletingLastPathComponent().appendingPathComponent(".point-geometry-" + UUID().uuidString)
        let record = target.appendingPathExtension("owner.json")
        var owner: [String: Any] = ["originalName": original.lastPathComponent,
                                  "original": try directoryIdentity(original)]
        if clone {
            XCTAssertTrue(ProjectBackupManager.cloneItem(at: original, to: target))
            if recordStagedIdentity { owner["staged"] = try directoryIdentity(target) }
        }
        try data(owner).write(to: record, options: .atomic)
        return (target, record)
    }
    private func assertNoOwnedStages(file: StaticString = #filePath, line: UInt = #line) throws {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil), file: file, line: line)
        for case let fileURL as URL in files {
            XCTAssertFalse(fileURL.lastPathComponent.hasPrefix(".point-geometry-"), fileURL.path, file: file, line: line)
        }
    }

    func testRestartBeforeCloneRetiresOwnerAfterOldSourceValidates() throws {
        let project = try install("plain")
        _ = try interruptedStage(project, clone: false)
        XCTAssertEqual(try PointGeometryRepair.run().converted, 2)
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: project))
        try assertNoOwnedStages()
    }

    func testRestartDuringPartialCloneRetiresOnlyOwnedStage() throws {
        let project = try install("material-fills")
        let (target, _) = try interruptedStage(project, clone: false)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("an interrupted clone".utf8).write(to: target.appendingPathComponent("partial"))
        XCTAssertEqual(try PointGeometryRepair.run().converted, 2)
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: project))
        try assertNoOwnedStages()
    }

    func testRestartAfterSwapCleansAlreadyCurrentPackageWithoutRewritingIt() throws {
        let project = try install("plain")
        _ = try PointGeometryRepair.run()
        let before = try bytes(project)
        let (target, record) = try interruptedStage(project)
        // The source now has the staged directory's identity; the sibling has the displaced source.
        let displaced = project.deletingLastPathComponent().appendingPathComponent("displaced")
        try FileManager.default.moveItem(at: project, to: displaced)
        try FileManager.default.moveItem(at: target, to: project)
        try FileManager.default.moveItem(at: displaced, to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.path))
        XCTAssertEqual(try PointGeometryRepair.run().converted, 0)
        XCTAssertEqual(try bytes(project), before)
        try assertNoOwnedStages()
    }

    func testMissingOrChangedInterruptedSourcePreservesEveryOwnedCopy() throws {
        let project = try install("plain")
        let (target, record) = try interruptedStage(project)
        try FileManager.default.removeItem(at: project)
        let missing = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(missing)
        try FileManager.default.moveItem(at: target, to: root.appendingPathComponent("preserved-missing-source"))
        try FileManager.default.removeItem(at: record)
        let source = try install("plain")
        _ = try interruptedStage(source)
        let oldID = try directoryIdentity(source)
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("changed-source-original"))
        let replacement = try install("plain")
        XCTAssertNotEqual(try directoryIdentity(replacement) as NSDictionary, oldID as NSDictionary)
        let changed = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(changed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.path))
    }

    func testFailedSourceValidationKeepsItsSoundInterruptedCopy() throws {
        let project = try install("material-strokes")
        _ = try interruptedStage(project)
        try editVector(project) { $0["materialOperations"] = [] }
        let before = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(before)
    }

    func testUnknownStageAndChangedStageIdentityAreNeverDiscarded() throws {
        let project = try install("plain")
        let (target, record) = try interruptedStage(project)
        let displaced = root.appendingPathComponent("original-stage")
        try FileManager.default.moveItem(at: target, to: displaced)
        XCTAssertTrue(ProjectBackupManager.cloneItem(at: project, to: target))
        let changed = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(changed)
        try FileManager.default.removeItem(at: record)
        let unowned = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(unowned)
    }

    func testInterruptedOwnerCannotTraverseOrFollowLinks() throws {
        let project = try install("plain")
        let (target, record) = try interruptedStage(project)
        var owner = try object(Data(contentsOf: record))
        for name in ["../outside.paintproj", "/absolute.paintproj"] {
            owner["originalName"] = name; try data(owner).write(to: record)
            let before = try bytes(root)
            XCTAssertThrowsError(try PointGeometryRepair.run())
            try assertInputsPreserved(before)
        }
        let savedRecord = root.appendingPathComponent("owner.json")
        try FileManager.default.moveItem(at: record, to: savedRecord)
        try FileManager.default.createSymbolicLink(at: record, withDestinationURL: savedRecord)
        let linkedRecord = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(linkedRecord)
        try FileManager.default.removeItem(at: record)
        try FileManager.default.moveItem(at: savedRecord, to: record)
        owner["originalName"] = project.lastPathComponent; try data(owner).write(to: record)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: project)
        let linkedStage = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(linkedStage)
    }

    func testPreparedStageReplacementCannotBecomeLiveOrDiscardOriginal() throws {
        let project = try install("plain")
        let before = try bytes(project)
        var boundary: [String: Data] = [:]
        ProjectBackupManager.settings.lastAppSignature = "previous build"
        XCTAssertThrowsError(try PointGeometryRepair.run(beforeCommit: {
            let records = try FileManager.default.contentsOfDirectory(at: project.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".owner.json") }
            let record = try XCTUnwrap(records.first)
            let stage = record.deletingLastPathComponent().appendingPathComponent(String(record.lastPathComponent.dropLast(".owner.json".count)))
            try FileManager.default.moveItem(at: stage, to: root.appendingPathComponent("saved-prepared-copy"))
            try FileManager.default.createSymbolicLink(at: stage, withDestinationURL: project)
            boundary = try bytes(root)
        }))
        XCTAssertEqual(try bytes(project), before)
        XCTAssertEqual(try bytes(root), boundary, "neither the displaced valid copy nor the replacement link is removed")
        XCTAssertEqual(ProjectBackupManager.settings.lastAppSignature, "previous build")
    }

    func testPreparedCopyEditedInPlaceMustRevalidateBeforeExchange() throws {
        let project = try install("plain")
        let before = try bytes(project)
        var boundary: [String: Data] = [:]
        XCTAssertThrowsError(try PointGeometryRepair.run(beforeCommit: {
            let record = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: project.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasSuffix(".owner.json") })
            let stage = record.deletingLastPathComponent().appendingPathComponent(String(record.lastPathComponent.dropLast(".owner.json".count)))
            try Data("truncated".utf8).write(to: vectorURL(stage))
            boundary = try bytes(root)
        }))
        XCTAssertEqual(try bytes(project), before)
        XCTAssertEqual(try bytes(root), boundary)
    }

    func testSourceRemovedBeforeCommitKeepsOnlyCompletePreparedCopy() throws {
        let project = try install("plain")
        var boundary: [String: Data] = [:]
        XCTAssertThrowsError(try PointGeometryRepair.run(beforeCommit: {
            try FileManager.default.removeItem(at: project)
            boundary = try bytes(root)
        }))
        XCTAssertEqual(try bytes(root), boundary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.path))
        let stages = try FileManager.default.contentsOfDirectory(at: project.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".point-geometry-") && !$0.lastPathComponent.hasSuffix(".owner.json") }
        XCTAssertEqual(stages.count, 1)
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: try XCTUnwrap(stages.first)))
    }

    func testSuccessfulCleanupPrecedesRetentionOfConvertedOldBackups() throws {
        let project = try install("plain")
        let id = try XCTUnwrap(ProjectBackupManager.manifestID(at: project))
        let directory = ProjectBackupManager.backupsDirectory(projectID: id)
        for day in 1...20 {
            _ = try install("plain", at: "Backups/\(id.uuidString)/preupdate-old-200001\(String(format: "%02d", day))-000000.paintproj")
        }
        XCTAssertEqual(try PointGeometryRepair.run().converted, 22)
        try assertNoOwnedStages()
        let retained = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "paintproj" }
        XCTAssertLessThan(retained.count, 21, "dated old backups exercise actual retention deletion")
        XCTAssertTrue(retained.allSatisfy { ProjectBackupManager.validateProjectForRestore(at: $0) })
        let after = try bytes(root)
        XCTAssertEqual(try PointGeometryRepair.run().converted, 0)
        XCTAssertEqual(try bytes(root), after, "retention must not leave missing-source owner records for the next launch")
    }

    func testPreviousWriterPackagesConvertAndRoundtripThroughCurrentWriter() async throws {
        let names = try XCTUnwrap(fixture["packages"] as? [String: Any]).keys.sorted()
        var originalFiles: [String: [String: Data]] = [:]
        for name in names { originalFiles[name] = try bytes(install(name)) }
        XCTAssertEqual(try PointGeometryRepair.run().converted, names.count * 2, "even an already-seen build protects an imported old library")
        for name in names {
            let package = root.appendingPathComponent("Projects/\(name).paintproj")
            XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: package), name)
            let current = try XCTUnwrap(ProjectStore.load(from: package))
            current.streamCoordinator.startsClients = false
            XCTAssertFalse(current.loadDamage.isDamaged, name)
            try assertGeometry(current, name: name)
            let changed = Set(try ProjectRecipeMetadata.reader(in: package).vectorURLs
                .map { String($0.path.dropFirst(package.path.count + 1)) }
                + ProjectRecipeMetadata.reader(in: package).urls.map { String($0.path.dropFirst(package.path.count + 1)) })
            let after = try bytes(package)
            XCTAssertEqual(Set(after.keys), Set(try XCTUnwrap(originalFiles[name]).keys))
            for (path, bytes) in try XCTUnwrap(originalFiles[name]) where !changed.contains(path) && path != "manifest.json" {
                XCTAssertEqual(after[path], bytes, name + "/" + path)
            }
            var expectedManifest = try object(XCTUnwrap(originalFiles[name]?["manifest.json"]))
            expectedManifest["geometryVersion"] = 1
            XCTAssertEqual(try object(XCTUnwrap(after["manifest.json"])) as NSDictionary,
                expectedManifest as NSDictionary, "only the required package boundary changes in the manifest")
            let reopenedURL = root.appendingPathComponent("roundtrip/\(name).paintproj")
            try FileManager.default.createDirectory(at: reopenedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let done = expectation(description: "current save " + name)
            ProjectStore.save(current, to: reopenedURL, onSaveFailed: { XCTFail("Current save failed"); done.fulfill() }, completion: { done.fulfill() })
            await fulfillment(of: [done], timeout: 30)
            let reopened = try XCTUnwrap(ProjectStore.load(from: reopenedURL))
            reopened.streamCoordinator.startsClients = false
            XCTAssertFalse(reopened.loadDamage.isDamaged, name)
            try assertGeometry(reopened, name: name)
            if name == "ordinary-distort" || name == "retained-exact-bake" {
                let oldPictures = try XCTUnwrap(fixture["oldReopenedPictures"] as? [String: String])
                let oldPNG = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(oldPictures[name])))
                let oldPicture = try XCTUnwrap(UIImage(data: oldPNG)?.cgImage)
                let currentPicture = try XCTUnwrap(UIImage(contentsOfFile: reopenedURL.appendingPathComponent("thumbnail.png").path)?.cgImage)
                XCTAssertEqual(currentPicture.width, oldPicture.width)
                XCTAssertEqual(currentPicture.height, oldPicture.height)
                XCTAssertEqual(try XCTUnwrap(CanvasFixture.rgbaBytes(currentPicture)),
                    try XCTUnwrap(CanvasFixture.rgbaBytes(oldPicture)), name + " actual previous-writer versus current-writer pixels")
            }
        }
    }

    func testAllRootsAndNewUntouchedUpdateSnapshotConvertBeforeSignatureAdvances() throws {
        let project = try install("material-strokes", at: "Projects/Folder/scene.paintproj")
        _ = try install("material-fills", at: "Backups/old/fill.paintproj")
        _ = try install("linked-local-edits", at: "Trash/Folder/linked.paintproj")
        ProjectBackupManager.settings.lastAppSignature = "previous build"
        XCTAssertEqual(try PointGeometryRepair.run().converted, 4)
        let roots: [URL] = [ProjectBackupManager.projectsDirectory, ProjectBackupManager.backupsRootDirectory,
                            ProjectBackupManager.trashDirectory]
        let packages: [URL] = roots.flatMap { directory -> [URL] in
            ProjectBackupManager.allProjectPackages(in: directory)
        }
        XCTAssertEqual(packages.count, 4)
        XCTAssertTrue(packages.allSatisfy { ProjectBackupManager.validateProjectForRestore(at: $0) })
        let snapshot = try XCTUnwrap(packages.first { $0.lastPathComponent.hasPrefix("preupdate-") })
        XCTAssertEqual(try bytes(snapshot), try bytes(project), "snapshot starts with untouched old bytes and receives exactly the same conversion")
        XCTAssertEqual(ProjectBackupManager.settings.lastAppSignature, ProjectBackupManager.currentAppSignature)
        let before = try bytes(root)
        XCTAssertEqual(try PointGeometryRepair.run().converted, 0)
        XCTAssertEqual(try bytes(root), before, "an idempotent repair must not rewrite current JSON or create snapshots")
    }

    func testCurrentDamagedDrawingAndRecipeStillReachBackupRecovery() throws {
        for name in ["plain", "linked-local-edits"] {
            let project = try install(name)
            _ = try PointGeometryRepair.run()
            let reader = try ProjectRecipeMetadata.reader(in: project)
            let damaged = try XCTUnwrap(name == "plain" ? reader.vectorURLs.first : reader.urls.first)
            try Data("{ truncated current JSON".utf8).write(to: damaged)
            let before = try bytes(root)
            XCTAssertEqual(try PointGeometryRepair.run().converted, 0)
            XCTAssertEqual(try bytes(root), before, "current damage belongs to recovery, never previous-format rewriting")
            XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: project))
            ProjectBackupManager.repairCorruptedProjects()
            XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: project))
            let manager = try XCTUnwrap(ProjectStore.load(from: project)); manager.streamCoordinator.startsClients = false
            XCTAssertFalse(manager.loadDamage.isDamaged)
            try assertGeometry(manager, name: name)
            XCTAssertEqual(try PointGeometryRepair.run().converted, 0, "the displaced damaged current copy in Trash is also left to recovery")
        }
    }

    func testRasterOnlyPreviousPackageGetsStrictBoundaryAndIdempotence() throws {
        let package = try install("plain")
        let drawing = try vectorURL(package)
        let manifestURL = package.appendingPathComponent("manifest.json")
        var manifest = try object(Data(contentsOf: manifestURL))
        var layers = manifest["layers"] as! [[String: Any]]
        var cels = layers[0]["cels"] as! [[String: Any]]
        cels[0].removeValue(forKey: "vectorFileName"); layers[0]["cels"] = cels; layers[0]["kind"] = "raster"
        manifest["layers"] = layers
        try data(manifest).write(to: manifestURL)
        try FileManager.default.removeItem(at: drawing)
        XCTAssertThrowsError(try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL)))
        XCTAssertEqual(try PointGeometryRepair.run().converted, 2)
        _ = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: package))
        let before = try bytes(root)
        XCTAssertEqual(try PointGeometryRepair.run().converted, 0)
        XCTAssertEqual(try bytes(root), before)
        var current = try object(Data(contentsOf: manifestURL))
        for version in [NSNumber(value: 2), NSNumber(value: true)] {
            current["geometryVersion"] = version
            try data(current).write(to: manifestURL)
            XCTAssertThrowsError(try PointGeometryRepair.run())
            XCTAssertThrowsError(try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL)))
        }
    }

    func testAmbiguousManifestCanRecoverFromCurrentBackup() throws {
        let project = try install("plain")
        _ = try PointGeometryRepair.run()
        try Data("{ truncated manifest".utf8).write(to: project.appendingPathComponent("manifest.json"))
        let before = try bytes(project)
        let report = try PointGeometryRepair.run()
        XCTAssertEqual(report.converted, 0)
        XCTAssertEqual(report.ambiguous, [project])
        XCTAssertEqual(try bytes(project), before)
        ProjectBackupManager.repairCorruptedProjects()
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: project))
        let manager = try XCTUnwrap(ProjectStore.load(from: project)); manager.streamCoordinator.startsClients = false
        try assertGeometry(manager, name: "plain")
    }

    func testAmbiguousManifestCanRecoverAfterItsOldBackupConverts() throws {
        let project = try install("material-strokes")
        let id = try XCTUnwrap(ProjectBackupManager.manifestID(at: project))
        let backupDirectory = ProjectBackupManager.backupsDirectory(projectID: id)
        XCTAssertTrue(ProjectBackupManager.cloneItem(at: project, to: backupDirectory.appendingPathComponent("latest.paintproj")))
        try Data(project.lastPathComponent.utf8).write(to: backupDirectory.appendingPathComponent("origin.name"))
        try Data("{ truncated manifest".utf8).write(to: project.appendingPathComponent("manifest.json"))
        let before = try bytes(project)
        let report = try PointGeometryRepair.run()
        XCTAssertEqual(report.converted, 1)
        XCTAssertEqual(report.ambiguous, [project])
        XCTAssertEqual(try bytes(project), before)
        ProjectBackupManager.repairCorruptedProjects()
        XCTAssertTrue(ProjectBackupManager.validateProjectForRestore(at: project))
        let manager = try XCTUnwrap(ProjectStore.load(from: project)); manager.streamCoordinator.startsClients = false
        try assertGeometry(manager, name: "material-strokes")
    }

    func testAmbiguousManifestWithoutGoodBackupRemainsPresentAndDamaged() throws {
        let project = try install("plain")
        try Data("{ truncated manifest".utf8).write(to: project.appendingPathComponent("manifest.json"))
        let before = try bytes(project)
        let report = try PointGeometryRepair.run()
        XCTAssertEqual(report.converted, 0)
        XCTAssertEqual(report.ambiguous, [project])
        ProjectBackupManager.repairCorruptedProjects()
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path))
        XCTAssertFalse(ProjectBackupManager.validateProjectForRestore(at: project))
        XCTAssertEqual(try bytes(project), before)
    }

    func testParentFolderLinksCannotEscapeOrLoopTheCensus() throws {
        let outside = try install("plain", at: "outside/plain.paintproj").deletingLastPathComponent()
        let projects = ProjectBackupManager.projectsDirectory
        let link = projects.appendingPathComponent("linked-folder")
        ProjectBackupManager.settings.lastAppSignature = "previous build"
        for target in [outside, projects] {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let before = try bytes(root)
            XCTAssertThrowsError(try PointGeometryRepair.run())
            XCTAssertEqual(try bytes(root), before)
            XCTAssertEqual(ProjectBackupManager.settings.lastAppSignature, "previous build")
            try FileManager.default.removeItem(at: link)
        }
    }

    func testUnreadableTreeAndNonDirectoryRootCannotBecomeAnEmptyCensus() throws {
        _ = try install("plain", at: "Projects/locked/plain.paintproj")
        let locked = root.appendingPathComponent("Projects/locked")
        let before = try bytes(root)
        ProjectBackupManager.settings.lastAppSignature = "previous build"
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        XCTAssertEqual(try bytes(root), before)
        XCTAssertEqual(ProjectBackupManager.settings.lastAppSignature, "previous build")
        let trash = root.appendingPathComponent("Trash")
        if FileManager.default.fileExists(atPath: trash.path) { try FileManager.default.removeItem(at: trash) }
        try Data("not a directory".utf8).write(to: trash)
        let blocked = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        XCTAssertEqual(try bytes(root), blocked)
        XCTAssertEqual(ProjectBackupManager.settings.lastAppSignature, "previous build")
    }

    func testMaterialStrokeKeepsDisplayedGeometryAndIndependentProjectiveMap() throws {
        let package = try install("material-strokes")
        let before = try object(Data(contentsOf: vectorURL(package)))
        _ = try PointGeometryRepair.run()
        let after = try object(Data(contentsOf: vectorURL(package)))
        let oldElements = try XCTUnwrap(before["elements"] as? [[String: Any]])
        let newElements = try XCTUnwrap(after["elements"] as? [[String: Any]])
        XCTAssertNil(after["materialOperations"])
        XCTAssertEqual(after["geometryVersion"] as? Int, 1)
        for (old, new) in zip(oldElements, newElements) {
            let oldStroke = try XCTUnwrap(old["stroke"] as? [String: Any])
            let newStroke = try XCTUnwrap(new["stroke"] as? [String: Any])
            let placement = try XCTUnwrap(oldStroke["placement"] as? [String: Any])
            let map = try XCTUnwrap(placement["map"] as? [String: Any])
            let h = try JSONDecoder().decode(Homography.self, from: data(map))
            if h.affine()?.isIdentity == true { XCTAssertTrue(newStroke["placement"] is NSNull) }
            else {
                let kept = try XCTUnwrap(newStroke["placement"] as? [String: Any])
                XCTAssertEqual(kept["map"] as? NSDictionary, map as NSDictionary)
                XCTAssertEqual(kept["restSize"] as? Double, placement["restSize"] as? Double)
                XCTAssertEqual(kept["source"] as? NSDictionary, ["kind": "derived"] as NSDictionary)
                XCTAssertNil(kept["material"]); XCTAssertNil(kept["transport"])
            }
        }
    }

    func testOrdinaryDistortAndExactBakeRetainTheirNativeSources() throws {
        for name in ["ordinary-distort", "retained-exact-bake"] {
            let package = try install(name)
            let before = try object(Data(contentsOf: vectorURL(package)))
            let converted = try XCTUnwrap(PointGeometryRepair.convertedPayload(data(before), recipe: false))
            let after = try object(converted)
            let oldElements = try XCTUnwrap(before["elements"] as? [[String: Any]])
            let newElements = try XCTUnwrap(after["elements"] as? [[String: Any]])
            var old = try XCTUnwrap(oldElements.first?["stroke"] as? [String: Any])
            var placement = try XCTUnwrap(old["placement"] as? [String: Any])
            placement.removeValue(forKey: "material"); placement.removeValue(forKey: "transport")
            old["placement"] = placement
            XCTAssertEqual(newElements.first?["stroke"] as? NSDictionary, old as NSDictionary, name)
            XCTAssertEqual((placement["source"] as? [String: Any])?["kind"] as? String,
                name == "ordinary-distort" ? "derived" : "retained")
        }
    }

    func testLinkedCaptureAndRecipeOnlyImportedBrushSurvive() throws {
        let package = try install("linked-local-edits")
        let recipe = try XCTUnwrap(ProjectRecipeMetadata.reader(in: package).urls.first)
        let before = try object(Data(contentsOf: recipe))
        let imports = try bytes(package).filter { $0.key.hasPrefix("brushes/") }
        XCTAssertEqual(imports.count, 1)
        for path in imports.keys { BrushStorage.shared.remove(URL(fileURLWithPath: path).lastPathComponent) }
        defer { for path in imports.keys { BrushStorage.shared.remove(URL(fileURLWithPath: path).lastPathComponent) } }
        _ = try PointGeometryRepair.run()
        let after = try object(Data(contentsOf: recipe))
        for key in ["references", "t", "mode", "groups", "guideIDs", "spacing", "deformations"] {
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: before[key]!, options: [.sortedKeys, .fragmentsAllowed]),
                try JSONSerialization.data(withJSONObject: after[key]!, options: [.sortedKeys, .fragmentsAllowed]), key)
        }
        XCTAssertNil(after["materialOperations"])
        let manager = try XCTUnwrap(ProjectStore.load(from: package)); manager.streamCoordinator.startsClients = false
        XCTAssertFalse(manager.loadDamage.isDamaged)
        XCTAssertEqual(manager.layers.flatMap(\.cels).compactMap(\.interpolation).first?.deformations.first?.captures.first?.inkIDs.count, 2)
        for (path, bytes) in imports {
            XCTAssertEqual(BrushStorage.shared.read(URL(fileURLWithPath: path).lastPathComponent), bytes)
        }
    }

    func testDrawingOnlyImportedGestureUsesByValueBrushAndPackageStrokeReferences() throws {
        let package = try install("material-strokes")
        let packages = try XCTUnwrap(fixture["packages"] as? [String: [String: String]])
        let linked = try XCTUnwrap(packages["linked-local-edits"])
        let recipeData = try XCTUnwrap(linked.first { $0.key.contains("interp") })
        let recipe = try object(XCTUnwrap(Data(base64Encoded: recipeData.value)))
        let gestures = try XCTUnwrap(recipe["deformations"] as? [[String: Any]])
        let brush = try XCTUnwrap(gestures.first?["brush"] as? [String: Any])
        let imported = linked.filter { $0.key.hasPrefix("brushes/") }
        XCTAssertEqual(imported.count, 1)
        for (path, encoded) in imported {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(Data(base64Encoded: encoded)).write(to: url)
        }
        let manifest = try object(Data(contentsOf: package.appendingPathComponent("manifest.json")))
        let tableURL = package.appendingPathComponent(try XCTUnwrap(manifest["brushTableFileName"] as? String))
        var table = try object(Data(contentsOf: tableURL))
        var entries = try XCTUnwrap(table["entries"] as? [[String: Any]])
        for index in entries.indices { entries[index]["ref"] = (entries[index]["ref"] as! Int) + 500_000 }
        table["entries"] = entries; try data(table).write(to: tableURL)
        try editVector(package) { value in
            var operations = value["materialOperations"] as! [[String: Any]]
            for index in operations.indices { operations[index]["brush"] = brush }
            value["materialOperations"] = operations
            var elements = value["elements"] as! [[String: Any]]
            for index in elements.indices {
                var stroke = elements[index]["stroke"] as! [String: Any]
                stroke["brush"] = (stroke["brush"] as! Int) + 500_000
                elements[index]["stroke"] = stroke
            }
            value["elements"] = elements
        }
        XCTAssertTrue(try ProjectRecipeMetadata.reader(in: package).urls.isEmpty)
        XCTAssertEqual(try PointGeometryRepair.run().converted, 2)
        let manager = try XCTUnwrap(ProjectStore.load(from: package)); manager.streamCoordinator.startsClients = false
        XCTAssertFalse(manager.loadDamage.isDamaged)
        try assertGeometry(manager, name: "material-strokes")
        for (path, encoded) in imported {
            XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(path)), Data(base64Encoded: encoded))
        }
    }

    func testMalformedByValueGestureBrushCannotBeDiscardedWithItsOperation() throws {
        let package = try install("material-strokes")
        let original = try object(Data(contentsOf: vectorURL(package)))
        for invalid in [NSNull(), NSNumber(value: 500_000), "missing"] as [Any] {
            var value = original
            var operations = value["materialOperations"] as! [[String: Any]]
            if invalid is String { operations[0].removeValue(forKey: "brush") }
            else { operations[0]["brush"] = invalid }
            value["materialOperations"] = operations
            XCTAssertThrowsError(try PointGeometryRepair.convertedPayload(data(value), recipe: false))
        }
    }

    func testUnreadableSpatialReferenceRefusesWholeLibraryWithoutMutation() throws {
        _ = try install("plain", at: "Projects/A/plain.paintproj")
        let broken = try install("material-strokes", at: "Projects/Z/broken.paintproj")
        try editVector(broken) { $0["materialOperations"] = [] }
        ProjectBackupManager.settings.lastAppSignature = "previous build"
        let before = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(before)
        XCTAssertEqual(ProjectBackupManager.settings.lastAppSignature, "previous build")
    }

    func testFailedProtectionCopyDoesNotReplacePruneOrAdvanceSignature() throws {
        let project = try install("material-strokes")
        let id = try XCTUnwrap(ProjectBackupManager.manifestID(at: project))
        let blocker = root.appendingPathComponent("Backups/" + id.uuidString)
        try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("a file prevents the backup directory".utf8).write(to: blocker)
        _ = try install("plain", at: "Backups/other/preupdate-old-20000101-000000.paintproj")
        ProjectBackupManager.settings.lastAppSignature = "previous build"
        let before = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(before)
        XCTAssertEqual(ProjectBackupManager.settings.lastAppSignature, "previous build")
    }

    func testUnreadableRestoreStreamBlocksReplacement() throws {
        let project = try install("plain")
        try editVector(project) { value in
            var elements = value["elements"] as! [Any]
            elements.append(["kind": "stream", "stream": ["id": UUID().uuidString, "channel": "unreadable"]])
            value["elements"] = elements
        }
        let before = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        try assertInputsPreserved(before)
    }

    func testOrdinaryDamagedElementKeepsReportedLossPolicy() throws {
        let project = try install("plain")
        try editVector(project) { value in
            var elements = value["elements"] as! [[String: Any]]
            var stroke = elements[0]["stroke"] as! [String: Any]
            stroke["color"] = "ordinary damage"; elements[0]["stroke"] = stroke; value["elements"] = elements
        }
        XCTAssertEqual(try PointGeometryRepair.run().converted, 2)
        let reader = try ProjectRecipeMetadata.reader(in: project)
        let manifest = try object(Data(contentsOf: project.appendingPathComponent("manifest.json")))
        let table = try JSONDecoder().decode(BrushTable.self, from: Data(contentsOf: project.appendingPathComponent(
            try XCTUnwrap(manifest["brushTableFileName"] as? String))))
        reader.decoder.userInfo[.brushTable] = table.resolvingIntoPool()
        let payload = try reader.decoder.decode(VectorCanvasData.self, from: Data(contentsOf: vectorURL(project)))
        XCTAssertEqual(payload.decodeReport.malformedCount, 1)
        XCTAssertEqual(payload.elements.count, 1)
    }

    func testPackageRootSymbolicLinkCannotBeUsedAsAStagingCopy() throws {
        let actual = try install("plain", at: "outside/plain.paintproj")
        let project = root.appendingPathComponent("Projects/link.paintproj")
        try FileManager.default.createDirectory(at: project.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: project, withDestinationURL: actual)
        let before = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        XCTAssertEqual(try bytes(root), before)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: project.path), actual.path)
    }

    func testReferencedSymbolicLinkCannotModifyOriginalDuringStaging() throws {
        let project = try install("plain")
        let url = try vectorURL(project)
        let actual = url.deletingLastPathComponent().appendingPathComponent("actual.json")
        try FileManager.default.moveItem(at: url, to: actual)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: actual)
        let before = try bytes(root)
        XCTAssertThrowsError(try PointGeometryRepair.run())
        XCTAssertEqual(try bytes(root), before)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), actual.path)
    }

    func testDamagedSpatialMappingsAndChronologicalCutsFailLoudly() throws {
        let strokePackage = try install("material-strokes")
        let oldStroke = try object(Data(contentsOf: vectorURL(strokePackage)))
        let identity = try json(Homography.identity)
        let singular = try json(Homography(a: 0, b: 0, c: 0, d: 0, e: 0, f: 0, g: 0, h: 0, i: 0))
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["source"] = ["kind": "derived"] },
            { $0["restSize"] = true },
            { $0["restSize"] = -1 },
            { $0["map"] = singular },
            { $0["transport"] = ["kind": "unknown"] },
            { $0["transport"] = ["kind": "identity", "map": identity] },
            { $0["transport"] = ["kind": "homography", "map": singular] },
            { $0["transport"] = ["kind": "sequence", "parts": [["kind": "identity"]]] },
            { placement in
                var program = placement["material"] as! [String: Any]
                program["scope"] = "owned"; placement["material"] = program
            },
            { placement in
                var program = placement["material"] as! [String: Any]
                program["bindings"] = []; placement["material"] = program
            },
            { placement in
                var program = placement["material"] as! [String: Any]
                let bindings = program["bindings"] as! [Any]
                program["bindings"] = bindings + bindings; placement["material"] = program
            }]
        for (index, mutate) in mutations.enumerated() {
            var value = oldStroke
            var elements = value["elements"] as! [[String: Any]]
            var stroke = elements[0]["stroke"] as! [String: Any]
            var placement = stroke["placement"] as! [String: Any]
            mutate(&placement); stroke["placement"] = placement; elements[0]["stroke"] = stroke; value["elements"] = elements
            XCTAssertThrowsError(try PointGeometryRepair.convertedPayload(data(value), recipe: false), "damaged stroke ownership \(index)")
        }
        let fillPackage = try install("material-fills")
        let oldFill = try object(Data(contentsOf: vectorURL(fillPackage)))
        for key in ["afterOperation", "pathData", "bridge", "inverted"] {
            var value = oldFill
            var elements = value["elements"] as! [[String: Any]]
            var fill = elements[1]["fill"] as! [String: Any]
            var placement = fill["placement"] as! [String: Any]
            var coverage = placement["coverage"] as! [[String: Any]]
            XCTAssertFalse(coverage.isEmpty)
            if key == "afterOperation" { coverage[0][key] = UUID().uuidString }
            else { coverage[0].removeValue(forKey: key) }
            placement["coverage"] = coverage; fill["placement"] = placement; elements[1]["fill"] = fill; value["elements"] = elements
            XCTAssertThrowsError(try PointGeometryRepair.convertedPayload(data(value), recipe: false), "damaged fill cut " + key)
        }
    }

    func testUnknownVersionAndIncompletePreviousOwnershipFailLoudly() throws {
        let package = try install("material-strokes")
        let original = try object(Data(contentsOf: vectorURL(package)))
        var unknown = original; unknown["geometryVersion"] = 2
        XCTAssertThrowsError(try PointGeometryRepair.convertedPayload(data(unknown), recipe: false))
        unknown["geometryVersion"] = true
        XCTAssertThrowsError(try PointGeometryRepair.convertedPayload(data(unknown), recipe: false))
        var missing = original; missing.removeValue(forKey: "materialOperations")
        XCTAssertThrowsError(try PointGeometryRepair.convertedPayload(data(missing), recipe: false))
        var duplicated = original
        let definitions = try XCTUnwrap(original["materialOperations"] as? [Any])
        duplicated["materialOperations"] = definitions + definitions
        XCTAssertThrowsError(try PointGeometryRepair.convertedPayload(data(duplicated), recipe: false))
        for key in ["placement", "source", "transport", "material"] {
            var value = original
            var elements = value["elements"] as! [[String: Any]]
            var stroke = elements[0]["stroke"] as! [String: Any]
            if key == "placement" { stroke.removeValue(forKey: key) }
            else {
                var placement = stroke["placement"] as! [String: Any]
                placement.removeValue(forKey: key); stroke["placement"] = placement
            }
            elements[0]["stroke"] = stroke; value["elements"] = elements
            XCTAssertThrowsError(try PointGeometryRepair.convertedPayload(data(value), recipe: false), key)
        }
    }
}
