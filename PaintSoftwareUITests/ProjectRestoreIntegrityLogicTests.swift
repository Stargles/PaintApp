import XCTest

@MainActor
final class ProjectRestoreIntegrityLogicTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("restore-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }
    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try FileManager.default.removeItem(at: root)
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

    func testRestoringCurrentSnapshotPreservesSourceAndDisplacedScene() throws {
        let (manager, live) = try savedScene()
        let backup = ProjectBackupManager.backupsDirectory(projectID: manager.projectID)
            .appendingPathComponent("preupdate-current-20261009-185936.paintproj")
        try FileManager.default.copyItem(at: live, to: backup)
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
