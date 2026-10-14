import XCTest

@MainActor
final class LegacyMaskRepairLogicTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mask-repair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }
    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try FileManager.default.removeItem(at: root)
    }

    // Copied from the owner's 2026-10-09 previous-build package, evidence-153/Backups/
    // 936C4492-5737-45C8-841A-3ADD65B16A5E/latest.paintproj/manifest.json. Artwork stays outside git.
    private let previousMask = #"{"sources":[{"kind":"layer","id":"7D7F35BB-D277-42D0-BFF5-7C7C237A3645"},{"kind":"layer","id":"E331C25C-0F5D-421B-BACA-C2A90C0FFB4C"},{"kind":"layer","id":"62A497C2-04F1-466F-89AE-0C72A1917C68"}],"invert":false,"isEnabled":true}"#

    private func earlier(_ path: String) throws -> URL {
        let package = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let mask = try JSONSerialization.jsonObject(with: Data(previousMask.utf8))
        try JSONSerialization.data(withJSONObject: ["layers": [["alphaMask": mask]], "folders": [["alphaMask": mask]]])
            .write(to: package.appendingPathComponent("manifest.json"))
        return package
    }

    private func masks(_ package: URL) throws -> [AlphaMask] {
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: package.appendingPathComponent("manifest.json"))) as? [String: Any])
        return try ["layers", "folders"].flatMap { list -> [AlphaMask] in
            try XCTUnwrap(manifest[list] as? [[String: Any]]).map {
                try JSONDecoder().decode(AlphaMask.self, from: JSONSerialization.data(withJSONObject: try XCTUnwrap($0["alphaMask"])))
            }
        }
    }

    func testPreviousBuildMaskRepairsWithoutLosingPicksAndSecondPassChangesNothing() throws {
        let package = try earlier("Projects/earlier.paintproj")
        XCTAssertEqual(LegacyMaskRepair.repair(packageAt: package), .repaired)
        let rewritten = try masks(package)
        XCTAssertEqual(rewritten.map { [$0.sources.count, $0.colours.count] }, [[3, 0], [3, 0]])
        XCTAssertEqual(rewritten.map(\.threshold), [0.1, 0.1])
        XCTAssertEqual(rewritten.map(\.antialiasHalfWidth), [0.01, 0.01])
        XCTAssertEqual(rewritten.map(\.invert), [false, false])
        XCTAssertEqual(rewritten.map(\.isEnabled), [true, true])
        XCTAssertEqual(rewritten.first?.sources.map { $0.id.uuidString },
                       ["7D7F35BB-D277-42D0-BFF5-7C7C237A3645", "E331C25C-0F5D-421B-BACA-C2A90C0FFB4C",
                        "62A497C2-04F1-466F-89AE-0C72A1917C68"])
        let once = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        XCTAssertEqual(LegacyMaskRepair.repair(packageAt: package), .alreadyCurrent)
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent("manifest.json")), once)
    }

    func testLibraryWalkIncludesProjectsBackupsAndTrash() throws {
        let packages = try ["Projects/current.paintproj", "Backups/scene/latest.paintproj", "Trash/deleted.paintproj"].map(earlier)
        LegacyMaskRepair.repairLibrary()
        XCTAssertEqual(try packages.map { try masks($0).first?.sources.count }, [3, 3, 3])
    }

    func testBrokenEarlierPicksAreReportedAndNotRewritten() throws {
        let package = try earlier("Projects/broken.paintproj")
        let url = package.appendingPathComponent("manifest.json")
        let data = Data(#"{"layers":[{"alphaMask":{"sources":"broken","invert":false,"isEnabled":true}}]}"#.utf8)
        try data.write(to: url)
        XCTAssertEqual(LegacyMaskRepair.repair(packageAt: package), .unreadable)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    private func savedScene() throws -> (CanvasManager, URL) {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        let url = ProjectStore.createNewProjectURL(name: "Masked scene")
        let saved = expectation(description: "Save current scene")
        ProjectStore.save(manager, to: url) { saved.fulfill() }
        wait(for: [saved], timeout: 30)
        return (manager, url)
    }

    private func editManifest(_ package: URL, _ edit: (inout [String: Any]) throws -> Void) throws {
        let url = package.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        try edit(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    /// Every byte of every file, including artwork and sidecars, rather than just the manifest.
    private func files(_ package: URL) throws -> [String: Data] {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: package,
            includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let url as URL in walker {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            result[String(url.path.dropFirst(package.path.count))] = try Data(contentsOf: url)
        }
        return result
    }

    func testRestoringUntouchedEarlierSnapshotRepairsOnlyItsCloneAndOpensInCurrentDecoder() throws {
        let (manager, live) = try savedScene()
        let backup = ProjectBackupManager.backupsDirectory(projectID: manager.projectID)
            .appendingPathComponent("preupdate-earlier-20261009-185936.paintproj")
        try FileManager.default.copyItem(at: live, to: backup)
        try editManifest(backup) { json in
            var layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
            var mask = try XCTUnwrap(layers[1]["alphaMask"] as? [String: Any])
            for key in ["colours", "threshold", "antialiasHalfWidth"] { mask.removeValue(forKey: key) }
            layers[1]["alphaMask"] = mask
            json["layers"] = layers
            var editor = try XCTUnwrap(json["editorState"] as? [String: Any])
            editor.removeValue(forKey: "tools")
            json["editorState"] = editor
            json["selectedBrush"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BrushLibrary.roundSoft))
        }
        let original = try files(backup), displaced = try files(live)
        XCTAssertTrue(ProjectBackupManager.restoreBackup(at: backup, toProjectAt: live))
        XCTAssertEqual(try files(backup), original)
        let trash = try XCTUnwrap(ProjectBackupManager.listTrash().first)
        XCTAssertEqual(try files(trash.url), displaced)
        let opened = try XCTUnwrap(ProjectStore.load(from: live))
        XCTAssertEqual(opened.layers[1].alphaMask, manager.layers[1].alphaMask)
    }

    func testUnreadableStagedRestoreLeavesEveryOriginalByteAndLiveSceneUntouched() throws {
        let (manager, live) = try savedScene()
        let backup = ProjectBackupManager.backupsDirectory(projectID: manager.projectID)
            .appendingPathComponent("preupdate-broken.paintproj")
        try FileManager.default.copyItem(at: live, to: backup)
        // The file skeleton is intact; a mandatory current metadata field is missing.
        try editManifest(backup) { json in
            json.removeValue(forKey: "fps")
            var layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
            var mask = try XCTUnwrap(layers[1]["alphaMask"] as? [String: Any])
            for key in ["colours", "threshold", "antialiasHalfWidth"] { mask.removeValue(forKey: key) }
            layers[1]["alphaMask"] = mask
            json["layers"] = layers
        }
        let original = try files(backup), current = try files(live)
        XCTAssertFalse(ProjectBackupManager.restoreBackup(at: backup, toProjectAt: live))
        XCTAssertEqual(try files(backup), original)
        XCTAssertTrue(ProjectBackupManager.listTrash().isEmpty)
        XCTAssertEqual(try files(live), current)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: live.deletingLastPathComponent().path)
            .contains { $0.hasPrefix(".saving-") })
    }

    func testAutomaticRestoreTriesNextSavedVersionWhenFirstCannotBeStrictlyRead() throws {
        let (manager, live) = try savedScene()
        let directory = ProjectBackupManager.backupsDirectory(projectID: manager.projectID)
        let older = directory.appendingPathComponent("auto-20261009-185936.paintproj")
        try FileManager.default.copyItem(at: live, to: older)
        try editManifest(live) { $0["name"] = "Later live scene" }
        ProjectBackupManager.refreshLatestSnapshot(projectURL: live, projectID: manager.projectID)
        try editManifest(ProjectBackupManager.latestSnapshotURL(directory: directory)) { $0.removeValue(forKey: "fps") }
        XCTAssertTrue(ProjectBackupManager.restoreNewestValidBackup(forProjectAt: live))
        XCTAssertEqual(try files(live), try files(older))
    }
}
