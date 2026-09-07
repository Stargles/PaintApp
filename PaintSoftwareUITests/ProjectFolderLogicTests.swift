import XCTest

/// **The gallery browses a tree, and everything that protects a project has to walk one** — TODO
/// (36)'s second half.
///
/// The owner asked for folders to organise *"projects, sequences, scenes, shots"*, so the nesting is
/// arbitrary rather than two fixed levels. The interesting tests here are not the CRUD ones — they
/// are the two places where adding folders could quietly *remove* a guarantee:
///
///  * every launch-time safety pass enumerated `Projects/` one level deep, so a project filed inside
///    a folder would stop being snapshotted before an update and stop being repaired after one, with
///    nothing going red anywhere; and
///  * deleting a folder is the first operation in this app that could plausibly be implemented as
///    `removeItem` on a directory full of artwork.
///
/// Run against a per-test temp root through `ProjectBackupManager.rootDirectoryOverride`, the same
/// seam every other storage suite uses.
final class ProjectFolderLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-folder-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - The guarantee that folders could have silently removed

    /// **A project inside a folder is still snapshotted before an app update and still repaired
    /// after one.** Both passes walked one level before TODO (36), which is a failure with no
    /// symptom until the day it matters.
    func testAProjectInsideAFolderIsStillSnapshottedAndRepaired() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 3", in: ProjectStore.projectsDirectory)
        let shot = try ProjectStore.createFolder(named: "Shot 12", in: scene)
        let nested = writeProject(named: "Deep", in: shot)
        let id = try XCTUnwrap(ProjectBackupManager.manifestID(at: nested))

        XCTAssertEqual(ProjectBackupManager.allProjectPackages().map { $0.lastPathComponent },
                       ["Deep.paintproj"],
                       "the walk finds a project two folders down")

        ProjectBackupManager.snapshotAllProjectsForAppUpdate(signature: "v2")
        let slots = ProjectBackupManager.listBackups(forProjectAt: nested)
        XCTAssertEqual(slots.count, 1, "an update snapshot was taken of the nested project")
        XCTAssertEqual(slots.first?.label, "Before app update")

        // Now damage it and let the repair pass find it.
        try Data("wrecked".utf8).write(to: nested.appendingPathComponent("manifest.json"))
        XCTAssertFalse(ProjectBackupManager.validateProject(at: nested), "PREMISE: it is damaged")

        ProjectBackupManager.repairCorruptedProjects()

        XCTAssertTrue(ProjectBackupManager.validateProject(at: nested),
                      "the nested project was restored from its snapshot")
        XCTAssertEqual(ProjectBackupManager.manifestID(at: nested), id,
                       "and it is the same project, not a fresh one")
    }

    /// A `.paintproj` is itself a directory, so a naive recursive walk would descend into one and
    /// return its `images/` folder as a candidate. Pinning this is cheap and the failure would be
    /// expensive: `repairCorruptedProjects` would then try to restore backups over `images/`.
    func testTheWalkDoesNotDescendIntoAPackage() throws {
        let project = writeProject(named: "Solo", in: ProjectStore.projectsDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent("images").path),
                      "PREMISE: the package contains a directory")
        XCTAssertEqual(ProjectBackupManager.allProjectPackages().map(\.standardizedFileURL),
                       [project.standardizedFileURL])
        XCTAssertEqual(ProjectStore.listFolders(in: ProjectStore.projectsDirectory).map(\.name), [],
                       "and a package is never listed as a folder the artist can open")
    }

    /// A save from inside a folder stages beside the project rather than at the top of the tree, and
    /// the sweep that cleans up after a killed save reaches it there.
    func testAStaleSaveStageInsideAFolderIsSweptUp() throws {
        let folder = try ProjectStore.createFolder(named: "Sequence 1", in: ProjectStore.projectsDirectory)
        let stale = folder.appendingPathComponent(".saving-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)

        ProjectBackupManager.cleanupStaleSaveDirectories()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path),
                      "and the folder itself survived the sweep")
    }

    /// **Deleting a folder trashes every project inside it individually.** Not `removeItem` on the
    /// directory, which is the obvious implementation and would be this storage layer's first
    /// unrecoverable delete. Each package lands in Recently Deleted under its own name, so the
    /// seven-day restore that already exists covers all of it.
    func testDeletingAFolderTrashesTheProjectsInsteadOfDestroyingThem() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 9", in: ProjectStore.projectsDirectory)
        let shot = try ProjectStore.createFolder(named: "Shot 1", in: scene)
        writeProject(named: "Rough", in: scene)
        writeProject(named: "Clean", in: shot)

        let trashed = ProjectStore.deleteFolder(at: scene)

        XCTAssertEqual(trashed, 2, "both projects were accounted for")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scene.path), "the folder is gone")
        XCTAssertEqual(Set(ProjectBackupManager.listTrash().map(\.displayName)), ["Rough", "Clean"],
                       "and both projects are in Recently Deleted, restorable, rather than destroyed")
    }

    /// The count the delete confirmation shows is the recursive one, so an artist deleting a
    /// sequence is told about the shots inside its scenes.
    func testAFolderTileCountsProjectsAllTheWayDown() throws {
        let sequence = try ProjectStore.createFolder(named: "Sequence 2", in: ProjectStore.projectsDirectory)
        let scene = try ProjectStore.createFolder(named: "Scene 1", in: sequence)
        writeProject(named: "A", in: sequence)
        writeProject(named: "B", in: scene)
        writeProject(named: "C", in: scene)

        let listed = ProjectStore.listFolders(in: ProjectStore.projectsDirectory)
        XCTAssertEqual(listed.map(\.name), ["Sequence 2"])
        XCTAssertEqual(listed.first?.projectCount, 3,
                       "the tile counts what is inside, not what is directly inside")
    }

    // MARK: - Making and naming folders

    func testAFolderIsCreatedAndListedWhereItWasMade() throws {
        let outer = try ProjectStore.createFolder(named: "Sequence 1", in: ProjectStore.projectsDirectory)
        let inner = try ProjectStore.createFolder(named: "Scene 2", in: outer)

        XCTAssertEqual(ProjectStore.listFolders(in: ProjectStore.projectsDirectory).map(\.name),
                       ["Sequence 1"])
        XCTAssertEqual(ProjectStore.listFolders(in: outer).map(\.name), ["Scene 2"])
        XCTAssertEqual(inner.lastPathComponent, "Scene 2")
        XCTAssertEqual(ProjectStore.allFolders().map { "\($0.depth):\($0.folder.name)" },
                       ["0:Sequence 1", "1:Scene 2"],
                       "and the move picker sees the whole tree, indented")
    }

    func testATakenNameIsRefusedRatherThanSilentlyMerged() throws {
        _ = try ProjectStore.createFolder(named: "Scene", in: ProjectStore.projectsDirectory)
        XCTAssertThrowsError(try ProjectStore.createFolder(named: "Scene",
                                                          in: ProjectStore.projectsDirectory)) { error in
            XCTAssertTrue((error as? ProjectStore.FolderError).map {
                if case .nameTaken = $0 { return true } else { return false }
            } ?? false, "got \(error)")
        }
    }

    /// A name with a slash in it must not create a nested path the artist did not ask for, and a
    /// leading dot must not create a folder they can never see again.
    func testANameIsSanitizedWithoutSilentlyMakingADifferentFolder() throws {
        XCTAssertEqual(ProjectStore.sanitizedFolderName("Scene 1/Shot 2"), "Scene 1 Shot 2")
        XCTAssertEqual(ProjectStore.sanitizedFolderName("  .hidden  "), "hidden")
        XCTAssertEqual(ProjectStore.sanitizedFolderName("   "), "")

        let made = try ProjectStore.createFolder(named: "Scene 1/Shot 2", in: ProjectStore.projectsDirectory)
        XCTAssertEqual(made.deletingLastPathComponent().standardizedFileURL,
                       ProjectStore.projectsDirectory.standardizedFileURL,
                       "one folder was made, not two levels")
        XCTAssertThrowsError(try ProjectStore.createFolder(named: "   ", in: ProjectStore.projectsDirectory))
    }

    func testRenamingAFolderKeepsTheProjectsInsideIt() throws {
        let folder = try ProjectStore.createFolder(named: "Untitled Scene", in: ProjectStore.projectsDirectory)
        writeProject(named: "Shot A", in: folder)

        let renamed = try ProjectStore.renameFolder(at: folder, to: "Rooftop Chase")

        XCTAssertEqual(renamed.lastPathComponent, "Rooftop Chase")
        XCTAssertEqual(ProjectStore.listProjects(in: renamed).map(\.name), ["Shot A"])
        XCTAssertEqual(ProjectBackupManager.allProjectPackages().count, 1,
                       "and the project did not get left behind under the old name")
    }

    // MARK: - Filing existing work

    /// **Projects can be moved into folders.** Without this the feature is write-only: migration
    /// lands every existing project at the top level, and a folder that can only be filled by
    /// creating a *new* project inside it cannot organise the work the owner asked to organise.
    func testAProjectCanBeMovedIntoAFolderAndListedThere() throws {
        let project = writeProject(named: "Filed", in: ProjectStore.projectsDirectory)
        let folder = try ProjectStore.createFolder(named: "Shots", in: ProjectStore.projectsDirectory)

        let moved = try XCTUnwrap(ProjectStore.moveProject(at: project, into: folder))

        XCTAssertEqual(moved.deletingLastPathComponent().standardizedFileURL,
                       folder.standardizedFileURL)
        XCTAssertEqual(ProjectStore.listProjects(in: ProjectStore.projectsDirectory).map(\.name), [],
                       "it is no longer at the top level")
        XCTAssertEqual(ProjectStore.listProjects(in: folder).map(\.name), ["Filed"])
    }

    /// Two shots called "Rough" in different scenes is the ordinary case once there are folders, so
    /// uniqueness is per folder rather than across the library.
    ///
    /// **The directory assertions are the load-bearing half, and their absence let a mutation live.**
    /// The first draft asserted only that both URLs ended in `Rough.paintproj` — which is true of an
    /// implementation that ignores the `in:` argument outright and resolves both against the top of
    /// the tree, because neither file exists yet so neither gets a "2" suffix. A green test about the
    /// filename said nothing about the folder, which is the whole subject.
    func testTwoFoldersMayEachHoldAProjectOfTheSameName() throws {
        let a = try ProjectStore.createFolder(named: "Scene 1", in: ProjectStore.projectsDirectory)
        let b = try ProjectStore.createFolder(named: "Scene 2", in: ProjectStore.projectsDirectory)

        let first = ProjectStore.createNewProjectURL(name: "Rough", in: a)
        let second = ProjectStore.createNewProjectURL(name: "Rough", in: b)

        XCTAssertEqual(first.deletingLastPathComponent().standardizedFileURL, a.standardizedFileURL,
                       "the project is minted in the folder it was asked for")
        XCTAssertEqual(second.deletingLastPathComponent().standardizedFileURL, b.standardizedFileURL,
                       "and so is the second, in a different one")
        XCTAssertEqual(first.lastPathComponent, "Rough.paintproj")
        XCTAssertEqual(second.lastPathComponent, "Rough.paintproj",
                       "the second is not renamed to “Rough 2” — it is in a different scene")
    }

    /// Moving onto a name that is taken keeps both, rather than replacing one with the other.
    func testMovingOntoATakenNameKeepsBothProjects() throws {
        let folder = try ProjectStore.createFolder(named: "Shots", in: ProjectStore.projectsDirectory)
        writeProject(named: "Rough", in: folder)
        let incoming = writeProject(named: "Rough", in: ProjectStore.projectsDirectory)

        let moved = try XCTUnwrap(ProjectStore.moveProject(at: incoming, into: folder))

        XCTAssertEqual(moved.lastPathComponent, "Rough 2.paintproj")
        XCTAssertEqual(Set(ProjectStore.listProjects(in: folder).map(\.name)), ["Rough", "Rough 2"])
    }

    /// Trash lookup for a project that lives in a folder: the "is there still a live project of this
    /// name" check that guards a backup history is tree-wide, so an expiring trash item cannot take
    /// a filed project's restore points with it.
    func testAnExpiringTrashItemDoesNotDestroyTheBackupsOfALiveProjectInAFolder() throws {
        let folder = try ProjectStore.createFolder(named: "Scene 4", in: ProjectStore.projectsDirectory)
        let live = writeProject(named: "Hero", in: folder)
        let id = try XCTUnwrap(ProjectBackupManager.manifestID(at: live))
        ProjectBackupManager.refreshLatestSnapshot(projectURL: live, projectID: id)
        XCTAssertEqual(ProjectBackupManager.listBackups(forProjectAt: live).count, 1,
                       "PREMISE: the live project has a restore point")

        // An older, unrelated project of the same name expires out of the trash.
        let stale = writeProject(named: "Hero", in: ProjectStore.projectsDirectory)
        _ = ProjectBackupManager.moveToTrash(stale, tag: "deleted")
        ProjectBackupManager.purgeExpiredTrash(now: Date().addingTimeInterval(60 * 24 * 60 * 60))

        XCTAssertEqual(ProjectBackupManager.listBackups(forProjectAt: live).count, 1,
                       "the filed project kept its history — a one-level liveness check would have "
                       + "called it non-existent and deleted every restore point it had")
    }

    // MARK: - Fixtures

    @discardableResult
    private func writeProject(named name: String, in directory: URL) -> URL {
        let url = ProjectStore.createNewProjectURL(name: name, in: directory)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.appendingPathComponent("images"), withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "id": UUID().uuidString,
            "layers": [["cels": [["rasterFileName": "a.png", "rasterOmitted": true]]]]
        ]
        try! JSONSerialization.data(withJSONObject: manifest)
            .write(to: url.appendingPathComponent("manifest.json"))
        try! Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            .write(to: url.appendingPathComponent("thumbnail.png"))
        return url
    }
}
