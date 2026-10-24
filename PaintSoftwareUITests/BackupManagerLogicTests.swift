import XCTest

/// Pure-logic tests for `ProjectBackupManager` — validation, rotation, restore selection, trash
/// retention, app-update snapshots, the size cap, and the launch-time repair pass — run against a
/// per-test temp directory via the manager's `rootDirectoryOverride`, with no simulator gestures
/// or app launch. `Services/ProjectBackupManager.swift` is compiled directly into this test bundle
/// (the shared-source pattern used by the rest of the logic tier).
final class BackupManagerLogicTests: XCTestCase {

    private var settingsSuite = ""

    private var root: URL!
    private let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-logic-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        ProjectBackupManager.trashRetentionInterval = 7 * 24 * 60 * 60
        ProjectBackupManager.maxTotalBackupBytes = ProjectBackupManager.defaultMaxTotalBackupBytes
        // The update signature is kept in a suite of this test's own, so a run neither reads nor leaves
        // the real one.
        settingsSuite = "backup-settings-\(UUID().uuidString)"
        ProjectBackupManager.settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: settingsSuite)))
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        ProjectBackupManager.settings = .standard
        UserDefaults.standard.removePersistentDomain(forName: settingsSuite)
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Helpers

    /// Writes a minimal-but-valid project package: manifest.json + images/<uuid>_raster.png with a
    /// real PNG header followed by `rasterBytes` payload bytes.
    ///
    /// `omitRaster` writes the package a save produces for a cel whose raster tier holds nothing: the
    /// manifest still names the file it *would* have had (see `CelManifest.rasterOmitted`), flags the
    /// omission, and no PNG is written. `writeRasterFile` is the separate knob for the damaged case —
    /// a cel that claims a raster and cannot produce it.
    @discardableResult
    private func makeProject(name: String = "Art", id: UUID = UUID(), rasterBytes: Int = 64,
                             omitRaster: Bool? = nil, writeRasterFile: Bool = true) -> URL {
        let url = ProjectBackupManager.projectsDirectory.appendingPathComponent("\(name).paintproj")
        let images = url.appendingPathComponent("images", isDirectory: true)
        try! FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let rasterName = "\(UUID().uuidString)_raster.png"
        if writeRasterFile && omitRaster != true {
            var png = Data(pngHeader)
            png.append(Data(repeating: 0xAB, count: rasterBytes))
            try! png.write(to: images.appendingPathComponent(rasterName))
        }
        var cel: [String: Any] = [
            "id": UUID().uuidString,
            "startFrame": 0,
            "frameCount": 1,
            "rasterFileName": rasterName
        ]
        if let omitRaster { cel["rasterOmitted"] = omitRaster }
        let manifest: [String: Any] = [
            "geometryVersion": 1,
            "id": id.uuidString,
            "name": name,
            "canvasWidth": 64, "canvasHeight": 64, "fps": 12, "modifiedAt": 0,
            "editorState": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(EditorStateManifest())),
            "layers": [["id": UUID().uuidString, "name": "Ink", "opacity": 1,
                        "isVisible": true, "cels": [cel]]]
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
    /// (here: recreate the package), refresh latest, rotate. Each cycle is a session's first save,
    /// which is the one that takes a rotated slot; `AutosaveLogicTests` covers the rolling one.
    private func simulateSaveCycle(projectURL: URL, id: UUID) {
        XCTAssertTrue(ProjectBackupManager.stashLiveProjectForSave(projectURL: projectURL, projectID: id,
                                                                   stash: .sessionStart))
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

    /// A package whose cel says its raster was omitted has no PNG to check, and must validate.
    ///
    /// **This is the gate that decides whether the save commits at all.**
    /// `ProjectStore.writeAtomically` validates its own staged package before the atomic swap and, on
    /// failure, moves the stage to Trash tagged "failedsave" — while still firing the caller's
    /// completion. So a validator that had not learned about `rasterOmitted` would not produce a red
    /// test in the app; it would make every save of every document with one undrawn cel do nothing,
    /// quietly, forever.
    func testValidateAcceptsACelWhoseRasterWasOmitted() throws {
        let url = makeProject(omitRaster: true)
        let images = url.appendingPathComponent("images", isDirectory: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: images.path), [],
                       "Setup: an omitted raster means there is no PNG on disk to validate")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
    }

    /// And the other direction, which is the whole reason the validator exists: `rasterOmitted` is
    /// permission to have no file, not permission to lose one. A cel that does *not* set the flag and
    /// cannot produce the PNG it names is damaged, whether the file is gone or truncated.
    func testValidateStillRejectsAClaimedRasterThatIsMissingOrTruncated() {
        let missing = makeProject(name: "Missing")
        let missingImages = missing.appendingPathComponent("images", isDirectory: true)
        let missingFiles = try! FileManager.default.contentsOfDirectory(atPath: missingImages.path)
        try! FileManager.default.removeItem(at: missingImages.appendingPathComponent(missingFiles[0]))
        XCTAssertFalse(ProjectBackupManager.validateProject(at: missing))

        let truncated = makeProject(name: "Truncated")
        let truncatedImages = truncated.appendingPathComponent("images", isDirectory: true)
        let truncatedFiles = try! FileManager.default.contentsOfDirectory(atPath: truncatedImages.path)
        try! Data([0x89, 0x50]).write(to: truncatedImages.appendingPathComponent(truncatedFiles[0]))
        XCTAssertFalse(ProjectBackupManager.validateProject(at: truncated))

        // An explicit `rasterOmitted: false` is the same claim as no key at all, and must not become
        // a loophole: the cel says there is a file, so the file has to be there.
        let claimed = makeProject(name: "Claimed", omitRaster: false, writeRasterFile: false)
        XCTAssertFalse(ProjectBackupManager.validateProject(at: claimed))
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

    /// Eight sessions' opening states inside one ten-minute stretch: only the newest three survive.
    func testRapidSavesKeepTheNewestThree() throws {
        let id = UUID()
        let url = makeProject(id: id)
        let started = Date()
        simulateSaveCycle(projectURL: url, id: id)
        let first = try XCTUnwrap(backupDirFileNames(id).first { $0.hasPrefix("auto-") })
        for _ in 1..<8 {
            simulateSaveCycle(projectURL: url, id: id)
        }
        try XCTSkipIf(Int(started.timeIntervalSince1970 / 600) != Int(Date().timeIntervalSince1970 / 600),
                      "The run crossed a ten-minute boundary, which keeps one more")
        let names = backupDirFileNames(id)
        XCTAssertEqual(names.filter { $0.hasPrefix("auto-") }.count, 3, "only the newest three in the current bucket")
        XCTAssertFalse(names.contains(first), "an older state in the same bucket is replaced by its newest member")
        XCTAssertTrue(names.contains("latest.paintproj"), "latest must survive rotation")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url), "the live package must be intact after every cycle")
    }

    // MARK: - Version retention on disk

    /// Mid-way through every slot of the schedule — 5½ minutes into its ten-minute slot, 45½ into its
    /// hour, 12¾ hours into its day, 3½ days into its week — so a version's age says where it falls.
    private let now = Date(timeIntervalSince1970: 2960 * 604_800 + 3 * 86_400 + 12 * 3_600 + 45 * 60 + 30)
    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    /// Plants a restore point named as `ProjectBackupManager` would have named it at `date`.
    @discardableResult
    private func plant(_ prefix: String, _ id: UUID, at date: Date, from project: URL) -> String {
        let name = "\(prefix)-\(ProjectBackupManager.timestampString(date)).paintproj"
        let dir = ProjectBackupManager.backupsDirectory(projectID: id)
        XCTAssertTrue(ProjectBackupManager.cloneItem(at: project, to: dir.appendingPathComponent(name)))
        return name
    }

    /// **One schedule for every dated kind.** Session starts, update snapshots and saves made aside
    /// are all versions; the newest in each age slot survives, and the fixed slots are not versions.
    func testPruneThinsEveryKindOfDatedSlotAndLeavesTheFixedOnes() {
        let id = UUID()
        let url = makeProject(id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: url, projectID: id)
        let dir = ProjectBackupManager.backupsDirectory(projectID: id)
        XCTAssertTrue(ProjectBackupManager.cloneItem(at: url, to: dir.appendingPathComponent(ProjectBackupManager.rollingSlotName)))

        let newest = [10, 20, 30].map { plant("auto", id, at: ago(TimeInterval($0)), from: url) }
        let installOlder = plant("preupdate-1-0-43-1-1791438480-0", id, at: ago(150 * 60), from: url)
        let installNewer = plant("preupdate-1-0-43-2-1791438480-0", id, at: ago(120 * 60), from: url)
        let asideOlder = plant("unsaved", id, at: ago(26 * 3600), from: url)
        let asideNewer = plant("unsaved", id, at: ago(25 * 3600), from: url)

        ProjectBackupManager.pruneBackups(forProjectID: id, now: now)

        let names = Set(backupDirFileNames(id))
        XCTAssertTrue(names.isSuperset(of: newest + [installNewer, asideNewer]),
                      "the newest three and newest update/unsaved version in each age slot stay")
        XCTAssertTrue(names.isDisjoint(with: [installOlder, asideOlder]),
                      "older versions in an hour and day slot are replaced by the newer member")
        XCTAssertTrue(names.isSuperset(of: ["latest.paintproj", ProjectBackupManager.rollingSlotName, "origin.name"]),
                      "the slots that are replaced in place are not versions and are never thinned")
        XCTAssertEqual(ProjectBackupManager.listBackups(forProjectAt: url).filter { $0.label == "Before app update" }.count, 1,
                       "an update snapshot is a version like the rest, and keeps its label while it lasts")
    }

    /// **Installs alone cannot push an earlier snapshot out of its older hour slot** — the hourly
    /// re-signer reinstalls, and a dev loop does it every few minutes. The same-slot burst keeps its
    /// newest three, while the snapshot from three hours ago remains independently recoverable.
    func testAnInstallBurstDoesNotPushOutAnEarlierSnapshot() throws {
        let id = UUID()
        let url = makeProject(id: id)
        let earlier = plant("preupdate-1-0-43-1-1791438480-0", id, at: Date().addingTimeInterval(-3 * 3600), from: url)

        let started = Date()
        for install in 1...8 {
            ProjectBackupManager.snapshotAllProjectsForAppUpdate(signature: "build \(install)")
        }
        try XCTSkipIf(Int(started.timeIntervalSince1970 / 600) != Int(Date().timeIntervalSince1970 / 600),
                      "The run crossed a ten-minute boundary, which keeps one more")

        XCTAssertTrue(backupDirFileNames(id).contains(earlier), "the snapshot taken before the burst is still there")
        XCTAssertEqual(ProjectBackupManager.listBackups(forProjectAt: url).filter { $0.label == "Before app update" }.count, 4,
                       "the earlier hourly restore point and the newest three snapshots remain")
    }

    /// A version's date is read from the end of its name, because it now decides whether the version
    /// is deleted. An update snapshot's name leads with the app signature, whose own digits can look
    /// like a stamp, and a collision counter follows the stamp.
    func testAVersionIsDatedByTheStampAtTheEndOfItsName() {
        let id = UUID()
        let url = makeProject(id: id)
        let dir = ProjectBackupManager.backupsDirectory(projectID: id)
        let stamp = DateComponents(calendar: .current, year: 2026, month: 10, day: 8, hour: 1, minute: 52, second: 53).date!
        for name in ["preupdate-1-0-43-1-1791438480-481766-20261008-015253.paintproj", "auto-20261008-015253-2.paintproj"] {
            XCTAssertTrue(ProjectBackupManager.cloneItem(at: url, to: dir.appendingPathComponent(name)))
        }
        let dates = ProjectBackupManager.listBackups(forProjectAt: url).map(\.date)
        XCTAssertEqual(dates, [stamp, stamp])
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

    func testAmbiguousOriginNameCannotRestoreAnotherScenesBackup() throws {
        let firstID = UUID(), secondID = UUID()
        let first = makeProject(name: "First", id: firstID)
        let second = makeProject(name: "Second", id: secondID)
        let folderA = ProjectBackupManager.projectsDirectory.appendingPathComponent("Folder A")
        let folderB = ProjectBackupManager.projectsDirectory.appendingPathComponent("Folder B")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        let firstScene = folderA.appendingPathComponent("Scene.paintproj")
        let secondScene = folderB.appendingPathComponent("Scene.paintproj")
        try FileManager.default.moveItem(at: first, to: firstScene)
        try FileManager.default.moveItem(at: second, to: secondScene)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: firstScene, projectID: firstID)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: secondScene, projectID: secondID)
        XCTAssertNotNil(ProjectBackupManager.backupDirectory(forProjectAt: firstScene), "a readable manifest remains authoritative")
        corruptManifest(of: firstScene)
        func allBytes() throws -> [String: Data] {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
            var result: [String: Data] = [:]
            for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: file)
            }
            return result
        }
        let before = try allBytes()
        XCTAssertNil(ProjectBackupManager.backupDirectory(forProjectAt: firstScene))
        XCTAssertTrue(ProjectBackupManager.listBackups(forProjectAt: firstScene).isEmpty)
        XCTAssertFalse(ProjectBackupManager.restoreNewestValidBackup(forProjectAt: firstScene))
        ProjectBackupManager.repairCorruptedProjects()
        XCTAssertFalse(ProjectBackupManager.validateProject(at: firstScene))
        XCTAssertEqual(ProjectBackupManager.manifestID(at: secondScene), secondID)
        XCTAssertEqual(try allBytes(), before, "ambiguous names must not replace either scene or change their backups")
    }

    // MARK: - Trash

    func testTrashRestoreRoundTrip() {
        let id = UUID()
        let url = makeProject(name: "KeepMe", id: id)
        let trashURL = ProjectBackupManager.moveToTrash(url, tag: "deleted")
        XCTAssertNotNil(trashURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let restored = ProjectBackupManager.restoreFromTrash(trashURL!)
        XCTAssertEqual(restored?.url.lastPathComponent, "KeepMe.paintproj")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: restored!.url))
        XCTAssertEqual(restored?.origin, [],
                       "a project deleted from the top of the tree came from the top of the tree")
        XCTAssertNil(restored?.notice,
                     "and a restore that landed where it was asked to has nothing to explain")
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

    func testExpiredTrashCannotDeleteANewerSameNamedProjectsHistory() throws {
        let now = Date()
        let oldID = UUID(), recentID = UUID()
        let old = makeProject(name: "Rough", id: oldID)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: old, projectID: oldID)
        let oldTrash = try XCTUnwrap(ProjectBackupManager.moveToTrash(old, tag: "deleted"))
        let expired = oldTrash.deletingLastPathComponent().appendingPathComponent(
            "Rough__deleted__\(ProjectBackupManager.timestampString(now.addingTimeInterval(-8 * 24 * 60 * 60))).paintproj")
        try FileManager.default.moveItem(at: oldTrash, to: expired)
        let recent = makeProject(name: "Rough", id: recentID)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: recent, projectID: recentID)
        let kept = try XCTUnwrap(ProjectBackupManager.moveToTrash(recent, tag: "deleted"))
        let latest = ProjectBackupManager.backupsRootDirectory.appendingPathComponent(
            "\(recentID.uuidString)/latest.paintproj/manifest.json")
        let before = try Data(contentsOf: latest)
        XCTAssertTrue(ProjectStore.listProjects().isEmpty, "PREMISE: no live names can protect the recent history")

        ProjectBackupManager.purgeExpiredTrash(now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
        XCTAssertEqual(try Data(contentsOf: latest), before, "History belongs to the recent project's UUID")
        XCTAssertTrue(backupDirFileNames(oldID).isEmpty, "The expired independent project's own history is purged")
        XCTAssertEqual(ProjectBackupManager.listTrash().map(\.url), [kept])
    }

    func testRetainedTrashWithTheSameProjectIDKeepsItsHistory() throws {
        let now = Date(), id = UUID()
        let first = makeProject(name: "Rough", id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: first, projectID: id)
        let firstTrash = try XCTUnwrap(ProjectBackupManager.moveToTrash(first, tag: "deleted"))
        let expired = firstTrash.deletingLastPathComponent().appendingPathComponent(
            "Rough__deleted__\(ProjectBackupManager.timestampString(now.addingTimeInterval(-8 * 24 * 60 * 60))).paintproj")
        try FileManager.default.moveItem(at: firstTrash, to: expired)
        let anotherVersion = makeProject(name: "Rough", id: id)
        let retained = try XCTUnwrap(ProjectBackupManager.moveToTrash(anotherVersion, tag: "deleted"))

        ProjectBackupManager.purgeExpiredTrash(now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        XCTAssertTrue(backupDirFileNames(id).contains("latest.paintproj"))
        ProjectBackupManager.purgeExpiredTrash(now: now.addingTimeInterval(8 * 24 * 60 * 60))
        XCTAssertTrue(backupDirFileNames(id).isEmpty, "History expires after the last actual owner is gone")
    }

    func testUnreadableLiveOwnershipPreservesRecoveryHistories() throws {
        let now = Date(), id = UUID()
        let old = makeProject(name: "Expired", id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: old, projectID: id)
        let trash = try XCTUnwrap(ProjectBackupManager.moveToTrash(old, tag: "deleted"))
        let expired = trash.deletingLastPathComponent().appendingPathComponent(
            "Expired__deleted__\(ProjectBackupManager.timestampString(now.addingTimeInterval(-8 * 24 * 60 * 60))).paintproj")
        try FileManager.default.moveItem(at: trash, to: expired)
        let unreadable = makeProject(name: "Unresolved")
        corruptManifest(of: unreadable)

        ProjectBackupManager.purgeExpiredTrash(now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        XCTAssertTrue(backupDirFileNames(id).contains("latest.paintproj"),
                      "An unreadable live manifest cannot establish that no project owns this history")
        XCTAssertEqual(try String(contentsOf: unreadable.appendingPathComponent("manifest.json"), encoding: .utf8), "corrupted")
    }

    func testUnreadableRetainedTrashOwnershipPreservesRecoveryHistories() throws {
        let now = Date(), id = UUID()
        let old = makeProject(name: "Expired", id: id)
        ProjectBackupManager.refreshLatestSnapshot(projectURL: old, projectID: id)
        let expiredTrash = try XCTUnwrap(ProjectBackupManager.moveToTrash(old, tag: "deleted"))
        let expired = expiredTrash.deletingLastPathComponent().appendingPathComponent(
            "Expired__deleted__\(ProjectBackupManager.timestampString(now.addingTimeInterval(-8 * 24 * 60 * 60))).paintproj")
        try FileManager.default.moveItem(at: expiredTrash, to: expired)

        let unknown = makeProject(name: "Unknown")
        let retained = try XCTUnwrap(ProjectBackupManager.moveToTrash(unknown, tag: "deleted"))
        corruptManifest(of: retained)

        ProjectBackupManager.purgeExpiredTrash(now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path), "The unexpired package remains")
        XCTAssertTrue(backupDirFileNames(id).contains("latest.paintproj"),
                      "An unreadable retained Trash owner cannot prove this history is orphaned")
        XCTAssertEqual(try String(contentsOf: retained.appendingPathComponent("manifest.json"), encoding: .utf8),
                       "corrupted", "Ownership inspection must preserve the damaged package")
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
        let id = UUID()
        let url = makeProject(name: "Cap", id: id, rasterBytes: 400)
        // Keep two complete current-format packages; the editor metadata is larger than the old
        // skeleton-only fixture. The cap should make exactly the latest and newest slot survive.
        ProjectBackupManager.maxTotalBackupBytes = ProjectBackupManager.directorySize(url) * 2 + 128
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
