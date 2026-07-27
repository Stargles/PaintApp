import XCTest

/// Pure-logic tests for `ProjectBackupManager` — validation, rotation, restore selection, trash
/// retention, app-update snapshots, the size cap, and the launch-time repair pass — run against a
/// per-test temp directory via the manager's `rootDirectoryOverride`, with no simulator gestures
/// or app launch. `Services/ProjectBackupManager.swift` is compiled directly into this test bundle
/// (same pattern as `Engine/Brush.swift` — see BrushEngineLogicTests' header comment for why
/// `@testable import` can't be used in this target), and is deliberately pure Foundation so that's
/// possible.
final class BackupManagerLogicTests: XCTestCase {

    private var root: URL!
    private let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-logic-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        ProjectBackupManager.maxAutosaveBackupsPerProject = 5
        ProjectBackupManager.maxPreUpdateBackupsPerProject = 3
        ProjectBackupManager.trashRetentionInterval = 7 * 24 * 60 * 60
        ProjectBackupManager.maxTotalBackupBytes = 1_000_000_000
        UserDefaults.standard.removeObject(forKey: ProjectBackupManager.signatureDefaultsKey)
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        UserDefaults.standard.removeObject(forKey: ProjectBackupManager.signatureDefaultsKey)
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Helpers

    /// Writes a minimal-but-valid project package: manifest.json + images/<uuid>_raster.png with a
    /// real PNG header followed by `rasterBytes` payload bytes.
    @discardableResult
    private func makeProject(name: String = "Art", id: UUID = UUID(), rasterBytes: Int = 64) -> URL {
        let url = ProjectBackupManager.projectsDirectory.appendingPathComponent("\(name).paintproj")
        let images = url.appendingPathComponent("images", isDirectory: true)
        try! FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let rasterName = "\(UUID().uuidString)_raster.png"
        var png = Data(pngHeader)
        png.append(Data(repeating: 0xAB, count: rasterBytes))
        try! png.write(to: images.appendingPathComponent(rasterName))
        let manifest: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "layers": [[
                "cels": [[
                    "id": UUID().uuidString,
                    "startFrame": 0,
                    "frameCount": 1,
                    "rasterFileName": rasterName
                ]]
            ]]
        ]
        try! JSONSerialization.data(withJSONObject: manifest).write(to: url.appendingPathComponent("manifest.json"))
        return url
    }

    private func corruptManifest(of url: URL) {
        try! Data("corrupted".utf8).write(to: url.appendingPathComponent("manifest.json"))
    }

    private func backupDirFileNames(_ id: UUID) -> [String] {
        let dir = ProjectBackupManager.backupsRootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    /// Mirrors what ProjectStore.save does around writePackage: stash live, "write" the new state
    /// (here: recreate the package), refresh latest, rotate.
    private func simulateSaveCycle(projectURL: URL, id: UUID) {
        XCTAssertTrue(ProjectBackupManager.stashLiveProjectForSave(projectURL: projectURL, projectID: id))
        _ = makeProject(name: projectURL.deletingPathExtension().lastPathComponent, id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: projectURL, projectID: id)
        ProjectBackupManager.pruneBackups(forProjectID: id)
    }

    // MARK: - Validation

    func testValidateAcceptsIntactPackage() {
        let url = makeProject()
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
    }

    func testValidateRejectsMissingManifest() {
        let url = makeProject()
        try! FileManager.default.removeItem(at: url.appendingPathComponent("manifest.json"))
        XCTAssertFalse(ProjectBackupManager.validateProject(at: url))
    }

    func testValidateRejectsUnreadableManifest() {
        let url = makeProject()
        corruptManifest(of: url)
        XCTAssertFalse(ProjectBackupManager.validateProject(at: url))
    }

    func testValidateRejectsMissingReferencedPNG() {
        let url = makeProject()
        let images = url.appendingPathComponent("images", isDirectory: true)
        let files = try! FileManager.default.contentsOfDirectory(atPath: images.path)
        try! FileManager.default.removeItem(at: images.appendingPathComponent(files[0]))
        XCTAssertFalse(ProjectBackupManager.validateProject(at: url))
    }

    func testValidateRejectsTruncatedPNG() {
        let url = makeProject()
        let images = url.appendingPathComponent("images", isDirectory: true)
        let files = try! FileManager.default.contentsOfDirectory(atPath: images.path)
        // A crash mid-write leaves a truncated PNG: exists, but doesn't start with the signature.
        try! Data([0x89, 0x50]).write(to: images.appendingPathComponent(files[0]))
        XCTAssertFalse(ProjectBackupManager.validateProject(at: url))
    }

    // MARK: - Save rotation

    func testFirstSaveCreatesValidLatestRestorePoint() {
        let id = UUID()
        let url = makeProject(id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: url, projectID: id)
        let latest = ProjectBackupManager.latestSnapshotURL(directory: ProjectBackupManager.backupsDirectory(projectID: id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: latest.path))
        XCTAssertTrue(ProjectBackupManager.validateProject(at: latest))
    }

    func testRotationStashesPreviousStatesAndPrunesToFive() {
        let id = UUID()
        let url = makeProject(id: id)
        for _ in 0..<8 {
            simulateSaveCycle(projectURL: url, id: id)
        }
        let names = backupDirFileNames(id)
        XCTAssertEqual(names.filter { $0.hasPrefix("auto-") }.count, 5, "autos must rotate at maxAutosaveBackupsPerProject")
        XCTAssertTrue(names.contains("latest.paintproj"), "latest must survive rotation")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url), "the live package must be intact after every cycle")
    }

    // MARK: - Restore

    func testCorruptProjectRestoresFromLatestAndTrashesDamagedCopy() {
        let id = UUID()
        let url = makeProject(id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: url, projectID: id)
        corruptManifest(of: url)

        XCTAssertTrue(ProjectBackupManager.restoreNewestValidBackup(forProjectAt: url))
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
        XCTAssertEqual(ProjectBackupManager.manifestID(at: url), id)

        let trash = ProjectBackupManager.listTrash()
        XCTAssertEqual(trash.count, 1, "the damaged package must be kept in Trash, not destroyed")
        XCTAssertTrue(trash[0].id.contains("__corrupt__"))
    }

    func testRestoreSkipsDamagedLatestAndFallsBackToAutosave() {
        let id = UUID()
        let url = makeProject(id: id)
        let dir = ProjectBackupManager.backupsDirectory(projectID: id)
        // A valid autosave of the current state, then a `latest` that itself got damaged.
        XCTAssertTrue(ProjectBackupManager.cloneItem(at: url, to: dir.appendingPathComponent("auto-20260701-120000.paintproj")))
        ProjectBackupManager.refreshLatestSnapshot(projectURL: url, projectID: id)
        corruptManifest(of: ProjectBackupManager.latestSnapshotURL(directory: dir))
        corruptManifest(of: url)

        XCTAssertTrue(ProjectBackupManager.restoreNewestValidBackup(forProjectAt: url))
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
        XCTAssertEqual(ProjectBackupManager.manifestID(at: url), id)
    }

    func testBackupsFoundViaOriginMarkerWhenManifestUnreadable() {
        let id = UUID()
        let url = makeProject(id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: url, projectID: id)
        corruptManifest(of: url) // ID lookup impossible now — must fall back to origin.name
        XCTAssertFalse(ProjectBackupManager.listBackups(forProjectAt: url).isEmpty)
    }

    // MARK: - Trash

    func testTrashRestoreRoundTrip() {
        let id = UUID()
        let url = makeProject(name: "KeepMe", id: id)
        let trashURL = ProjectBackupManager.moveToTrash(url, tag: "deleted")
        XCTAssertNotNil(trashURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let restored = ProjectBackupManager.restoreFromTrash(trashURL!)
        XCTAssertEqual(restored?.lastPathComponent, "KeepMe.paintproj")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: restored!))
    }

    func testExpiredTrashPurgedWithItsBackupHistory_RecentKept() {
        let oldID = UUID()
        let oldURL = makeProject(name: "Old", id: oldID)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: oldURL, projectID: oldID)
        XCTAssertNotNil(ProjectBackupManager.moveToTrash(oldURL, tag: "deleted"))

        let newURL = makeProject(name: "New", id: UUID())
        XCTAssertNotNil(ProjectBackupManager.moveToTrash(newURL, tag: "deleted"))

        // Nothing is old enough yet — both survive a normal purge.
        ProjectBackupManager.purgeExpiredTrash()
        XCTAssertEqual(ProjectBackupManager.listTrash().count, 2)

        // Eight days later both are purged, and the deleted project's backup history goes with it
        // (no live project named "Old.paintproj" exists to protect it).
        ProjectBackupManager.purgeExpiredTrash(now: Date(timeIntervalSinceNow: 8 * 24 * 60 * 60))
        XCTAssertTrue(ProjectBackupManager.listTrash().isEmpty)
        let remainingBackupDirs = (try? FileManager.default.contentsOfDirectory(atPath: ProjectBackupManager.backupsRootDirectory.path)) ?? []
        XCTAssertFalse(remainingBackupDirs.contains(oldID.uuidString))
    }

    // MARK: - App-update snapshots

    func testAppUpdateSnapshotsEveryProjectOncePerSignature() {
        let a = makeProject(name: "A", id: UUID())
        let b = makeProject(name: "B", id: UUID())

        func preupdateCount(_ url: URL) -> Int {
            ProjectBackupManager.listBackups(forProjectAt: url).filter { $0.label == "Before app update" }.count
        }

        ProjectBackupManager.runStartupMaintenance() // first launch (no stored signature)
        XCTAssertEqual(preupdateCount(a), 1)
        XCTAssertEqual(preupdateCount(b), 1)

        ProjectBackupManager.runStartupMaintenance() // same binary -> not an update -> no new slots
        XCTAssertEqual(preupdateCount(a), 1)
        XCTAssertEqual(preupdateCount(b), 1)
    }

    // MARK: - Launch-time repair

    func testStartupMaintenanceAutoRepairsCorruptProject() {
        let id = UUID()
        let url = makeProject(name: "Repair", id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: url, projectID: id)
        corruptManifest(of: url)

        ProjectBackupManager.runStartupMaintenance()

        XCTAssertTrue(ProjectBackupManager.validateProject(at: url), "maintenance must restore the damaged package from its backup")
        XCTAssertEqual(ProjectBackupManager.manifestID(at: url), id)
    }

    // MARK: - Size cap

    func testSizeCapPrunesOldestButKeepsLatestAndOneRestorePoint() {
        ProjectBackupManager.maxTotalBackupBytes = 1500
        let id = UUID()
        let url = makeProject(name: "Cap", id: id, rasterBytes: 400)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: url, projectID: id)
        let dir = ProjectBackupManager.backupsDirectory(projectID: id)
        for day in 1...4 {
            let slot = dir.appendingPathComponent("auto-2026010\(day)-120000.paintproj")
            XCTAssertTrue(ProjectBackupManager.cloneItem(at: url, to: slot))
        }

        ProjectBackupManager.pruneToSizeCap()

        let names = backupDirFileNames(id)
        XCTAssertTrue(names.contains("latest.paintproj"), "the cap must never delete the latest snapshot")
        XCTAssertLessThanOrEqual(
            ProjectBackupManager.directorySize(ProjectBackupManager.backupsRootDirectory),
            ProjectBackupManager.maxTotalBackupBytes,
            "total backup size must be brought back under the cap"
        )
        // Newest slot is the survivor when pruning oldest-first.
        XCTAssertEqual(names.filter { $0.hasPrefix("auto-") }, ["auto-20260104-120000.paintproj"])
    }
}
