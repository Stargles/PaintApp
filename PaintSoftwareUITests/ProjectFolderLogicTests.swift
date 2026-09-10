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

    // MARK: - Restoring to the folder it was deleted from — TODO (36)'s last line

    /// **The origin is not stored anywhere — it is where the entry is.** A project deleted from
    /// `Projects/Scene 3/Shot 1/` lands at `Trash/Scene 3/Shot 1/`, and the second assertion here is
    /// the design's whole claim: there is no marker file, no sidecar, nothing beside the entry that
    /// could ever say something different from where the entry actually sits.
    func testATrashedProjectIsFiledUnderTheFolderPathItCameFrom() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 3", in: ProjectStore.projectsDirectory)
        let shot = try ProjectStore.createFolder(named: "Shot 1", in: scene)
        let project = writeProject(named: "Hero", in: shot)

        XCTAssertNotNil(ProjectBackupManager.moveToTrash(project, tag: "deleted"))

        let listed = ProjectBackupManager.listTrash()
        XCTAssertEqual(listed.count, 1, "the entry is listed even though it is two folders down")
        XCTAssertEqual(listed.first?.originComponents, ["Scene 3", "Shot 1"],
                       "and it knows the folder path it came from")
        XCTAssertEqual(listed.first?.originDisplay, "Projects / Scene 3 / Shot 1",
                       "said in the breadcrumb's own words, which is what the row draws")

        // Nothing but the entry itself lives under the mirror — the property that makes a second
        // opinion impossible rather than merely unlikely.
        let mirror = ProjectBackupManager.trashDirectory
            .appendingPathComponent("Scene 3").appendingPathComponent("Shot 1")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: mirror.path).count, 1,
                       "the mirror folder holds the package and no marker file beside it")
    }

    /// **The item.** Restore puts the project back in the folder it was deleted from, and the last
    /// assertion is the behaviour this replaces: the shipped build moved it to
    /// `Projects/Hero.paintproj`, the top of the tree, whatever folder it had been filed in.
    func testRestoringPutsAProjectBackInTheFolderItWasDeletedFrom() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 3", in: ProjectStore.projectsDirectory)
        let shot = try ProjectStore.createFolder(named: "Shot 1", in: scene)
        let project = writeProject(named: "Hero", in: shot)
        let id = try XCTUnwrap(ProjectBackupManager.manifestID(at: project))
        let trashURL = try XCTUnwrap(ProjectBackupManager.moveToTrash(project, tag: "deleted"))

        let restore = try XCTUnwrap(ProjectBackupManager.restoreFromTrash(trashURL))

        XCTAssertEqual(restore.url.deletingLastPathComponent().standardizedFileURL,
                       shot.standardizedFileURL,
                       "the project is back inside Scene 3 / Shot 1")
        XCTAssertEqual(restore.url.lastPathComponent, "Hero.paintproj", "under its own name")
        XCTAssertEqual(ProjectBackupManager.manifestID(at: restore.url), id,
                       "and it is the same project, not an empty package of the same name")
        XCTAssertEqual(restore.origin, ["Scene 3", "Shot 1"])
        XCTAssertNil(restore.notice, "a restore that landed where it was asked to says nothing")

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ProjectStore.projectsDirectory.appendingPathComponent("Hero.paintproj").path),
                       "and nothing was left at the top of the tree — which is exactly where the "
                       + "shipped build put it, and the whole of what this closes")
        XCTAssertEqual(ProjectBackupManager.allProjectPackages().count, 1,
                       "one project came back, not two")
    }

    /// **Requirement: an entry written by the shipped build carries no origin at all, and must still
    /// restore.** It is a package sitting at `Trash/` itself, exactly the name the owner's device
    /// produced on 2026-09-07. It restores to the top of the tree — and that is its *correct* origin
    /// rather than a fallback, so nothing is said about it. No migration rewrites it; there is
    /// nothing to rewrite.
    func testAnEntryFromTheShippedBuildRestoresToTheTopOfTheTreeWithNothingToExplain() throws {
        let project = writeProject(named: "Untitled 2", in: ProjectStore.projectsDirectory)
        let legacy = ProjectBackupManager.trashDirectory
            .appendingPathComponent("Untitled 2__deleted__20260907-233207.paintproj")
        try FileManager.default.moveItem(at: project, to: legacy)

        let listed = ProjectBackupManager.listTrash()
        XCTAssertEqual(listed.first?.displayName, "Untitled 2", "PREMISE: the old name still parses")
        XCTAssertEqual(listed.first?.originComponents, [],
                       "an entry with no folder above it came from the top of the tree")

        let restore = try XCTUnwrap(ProjectBackupManager.restoreFromTrash(legacy))
        XCTAssertEqual(restore.url.deletingLastPathComponent().standardizedFileURL,
                       ProjectStore.projectsDirectory.standardizedFileURL,
                       "it restores to the top of the tree, as it always did")
        XCTAssertEqual(restore.url.lastPathComponent, "Untitled 2.paintproj")
        XCTAssertNil(restore.missingOriginFolder,
                     "the top of the tree is where it belongs, so nothing was missing")
        XCTAssertNil(restore.notice, "and the artist is told nothing, because nothing happened to it")
    }

    /// **Requirement: the origin folder is gone by the time the restore happens.** Deleting a folder
    /// is the ordinary way that happens — it trashes every project under it and then removes the
    /// folder itself. The project comes back at the top of the tree, and the artist is *told*, which
    /// is the difference between this and the defect it replaces.
    func testAMissingOriginFolderPutsTheProjectAtTheTopOfTheTreeAndSaysSo() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 9", in: ProjectStore.projectsDirectory)
        writeProject(named: "Rough", in: scene)
        XCTAssertEqual(ProjectStore.deleteFolder(at: scene), 1, "PREMISE: the folder's project was trashed")
        XCTAssertFalse(ProjectBackupManager.isDirectory(scene), "PREMISE: and the folder itself is gone")

        let entry = try XCTUnwrap(ProjectBackupManager.listTrash().first)
        XCTAssertEqual(entry.originComponents, ["Scene 9"], "PREMISE: the entry still knows where it was")

        let restore = try XCTUnwrap(ProjectBackupManager.restoreFromTrash(entry.url))
        XCTAssertEqual(restore.url.deletingLastPathComponent().standardizedFileURL,
                       ProjectStore.projectsDirectory.standardizedFileURL,
                       "with nowhere to put it back, it goes to the top of the tree")
        XCTAssertFalse(ProjectBackupManager.isDirectory(scene),
                       "and the folder the artist deleted is not silently recreated under them")
        XCTAssertEqual(restore.missingOriginFolder, "Scene 9")
        let notice = try XCTUnwrap(restore.notice,
                                   "a restore that could not go home has to say so — going quietly "
                                   + "to the top of the tree is the defect this item exists to fix")
        XCTAssertTrue(notice.contains("Scene 9"), "and it names the folder, not just the fact: \(notice)")
    }

    /// **Requirement: something is already sitting at the origin under that name.** Never overwrite.
    /// The incumbent's own manifest id, read after the restore, is what "was not overwritten" means —
    /// a `fileExists` check would pass just as happily over a clobbered package.
    func testARestoreNeverOverwritesAProjectAlreadySittingAtTheOrigin() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 3", in: ProjectStore.projectsDirectory)
        let original = writeProject(named: "Boat", in: scene)
        let originalID = try XCTUnwrap(ProjectBackupManager.manifestID(at: original))
        let trashURL = try XCTUnwrap(ProjectBackupManager.moveToTrash(original, tag: "deleted"))

        // The artist made a new project of the same name in the same folder meanwhile.
        let incumbent = writeProject(named: "Boat", in: scene)
        let incumbentID = try XCTUnwrap(ProjectBackupManager.manifestID(at: incumbent))
        XCTAssertEqual(incumbent.lastPathComponent, "Boat.paintproj", "PREMISE: it took the free name")
        XCTAssertNotEqual(incumbentID, originalID, "PREMISE: they are two different projects")

        let restore = try XCTUnwrap(ProjectBackupManager.restoreFromTrash(trashURL))

        XCTAssertEqual(ProjectBackupManager.manifestID(at: incumbent), incumbentID,
                       "the project that was already there is untouched — this is the assertion that "
                       + "fails if the restore clobbered it, where a fileExists check would not")
        XCTAssertEqual(restore.url.lastPathComponent, "Boat 2.paintproj",
                       "and the restored one takes the next free name in the same folder")
        XCTAssertEqual(ProjectBackupManager.manifestID(at: restore.url), originalID,
                       "which is the project that was in the trash")
        XCTAssertEqual(restore.renamedTo, "Boat 2")
        let notice = try XCTUnwrap(restore.notice, "and the artist is told its name changed")
        XCTAssertTrue(notice.contains("Boat 2"), "by name: \(notice)")
        XCTAssertEqual(ProjectBackupManager.allProjectPackages(in: scene).count, 2,
                       "two projects in the folder, which is the point")
    }

    /// Two projects of one name, deleted from two folders. They are two rows — `TrashItem.id` used to
    /// be the filename, and two identical filenames in a `ForEach` is a row that never draws — and
    /// each goes back to its own folder rather than both landing in one.
    func testTwoProjectsOfOneNameFromTwoFoldersAreTwoRowsAndGoBackSeparately() throws {
        let a = try ProjectStore.createFolder(named: "Scene A", in: ProjectStore.projectsDirectory)
        let b = try ProjectStore.createFolder(named: "Scene B", in: ProjectStore.projectsDirectory)
        let fromA = try XCTUnwrap(ProjectBackupManager.moveToTrash(writeProject(named: "Rough", in: a), tag: "deleted"))
        let fromB = try XCTUnwrap(ProjectBackupManager.moveToTrash(writeProject(named: "Rough", in: b), tag: "deleted"))

        let listed = ProjectBackupManager.listTrash()
        XCTAssertEqual(listed.count, 2, "both are listed")
        XCTAssertEqual(Set(listed.map(\.id)).count, 2,
                       "under two identities — a shared one is a gallery row that never draws")

        XCTAssertEqual(try XCTUnwrap(ProjectBackupManager.restoreFromTrash(fromA)).origin, ["Scene A"])
        XCTAssertEqual(try XCTUnwrap(ProjectBackupManager.restoreFromTrash(fromB)).origin, ["Scene B"])
        XCTAssertEqual(ProjectBackupManager.allProjectPackages(in: a).count, 1, "one came back to Scene A")
        XCTAssertEqual(ProjectBackupManager.allProjectPackages(in: b).count, 1, "and one to Scene B")
    }

    /// A mirror folder is bookkeeping, not a record: an empty one would say a project came from
    /// somewhere while holding no project. Swept when the last entry leaves, whether by restore or by
    /// the seven-day purge.
    func testAMirrorFolderIsSweptWhenItsLastEntryLeaves() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 3", in: ProjectStore.projectsDirectory)
        let first = try XCTUnwrap(ProjectBackupManager.moveToTrash(writeProject(named: "One", in: scene), tag: "deleted"))
        _ = try XCTUnwrap(ProjectBackupManager.moveToTrash(writeProject(named: "Two", in: scene), tag: "deleted"))
        let mirror = ProjectBackupManager.trashDirectory.appendingPathComponent("Scene 3")
        XCTAssertTrue(ProjectBackupManager.isDirectory(mirror), "PREMISE: the mirror is there")

        _ = ProjectBackupManager.restoreFromTrash(first)
        XCTAssertTrue(ProjectBackupManager.isDirectory(mirror),
                      "one entry left, so the mirror stays — sweeping it would strand the other")

        ProjectBackupManager.purgeExpiredTrash(now: Date(timeIntervalSinceNow: 8 * 24 * 60 * 60))
        XCTAssertTrue(ProjectBackupManager.listTrash().isEmpty, "PREMISE: the purge emptied the trash")
        XCTAssertFalse(ProjectBackupManager.isDirectory(mirror), "and the mirror went with it")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            atPath: ProjectBackupManager.trashDirectory.path), [], "leaving the trash actually empty")
    }

    /// **Requirement: the library root changed since the delete.** Nothing stores an absolute path —
    /// the origin is a position inside `Trash/`, which the migration carries as one piece — so a
    /// project trashed in the app container and restored after the artist adopted a folder in Files
    /// still lands in its own scene.
    func testAnOriginSurvivesTheWholeLibraryMovingToAnotherRoot() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 3", in: ProjectStore.projectsDirectory)
        let project = writeProject(named: "Hero", in: scene)
        XCTAssertNotNil(ProjectBackupManager.moveToTrash(project, tag: "deleted"))

        // `Relocated` sits beside Projects/Backups/Trash rather than inside one, so the migration
        // never sees it as an item to carry.
        let newRoot = root.appendingPathComponent("Relocated", isDirectory: true)
        try FileManager.default.createDirectory(at: newRoot, withIntermediateDirectories: true)
        let report = ProjectLibraryMigration.migrate(from: root, to: newRoot)
        XCTAssertTrue(report.failed.isEmpty, "PREMISE: the whole library moved: \(report.failed)")
        ProjectBackupManager.rootDirectoryOverride = newRoot

        let entry = try XCTUnwrap(ProjectBackupManager.listTrash().first)
        XCTAssertEqual(entry.originComponents, ["Scene 3"],
                       "the origin is the same folder path in the new root, because it is not a path "
                       + "at all — it is where the entry sits inside Trash")

        let restore = try XCTUnwrap(ProjectBackupManager.restoreFromTrash(entry.url))
        XCTAssertEqual(restore.url.standardizedFileURL,
                       newRoot.appendingPathComponent("Projects/Scene 3/Hero.paintproj").standardizedFileURL,
                       "and it restores into the new root's own Scene 3")
        XCTAssertNil(restore.notice)
    }

    /// **Requirement: awkward names.** A folder name is copied into the mirror verbatim, so anything
    /// the filesystem already accepted as a folder is accepted again — there is no encoding step to
    /// get wrong, no `/` to escape, and no length added to any single component (the one thing a
    /// 255-byte path component actually enforces). `__` is in there on purpose: it is the trash
    /// name's own field separator, which a filename-encoded origin would have had to escape.
    func testAwkwardFolderNamesSurviveTheRoundTripBecauseNothingIsEncoded() throws {
        let awkward = #"Scène "Nuit" __ 50% 🎬"#
        let long = String(repeating: "é", count: 60)
        let outer = try ProjectStore.createFolder(named: awkward, in: ProjectStore.projectsDirectory)
        let inner = try ProjectStore.createFolder(named: long, in: outer)
        let project = writeProject(named: "Hero", in: inner)
        let trashURL = try XCTUnwrap(ProjectBackupManager.moveToTrash(project, tag: "deleted"))

        XCTAssertEqual(ProjectBackupManager.listTrash().first?.originComponents, [awkward, long],
                       "the components are the folder names themselves, unaltered")
        XCTAssertEqual(trashURL.lastPathComponent.utf8.count,
                       "Hero__deleted__20260101-000000.paintproj".utf8.count,
                       "and the entry's own filename carries no origin, so it did not grow by one byte")

        let restore = try XCTUnwrap(ProjectBackupManager.restoreFromTrash(trashURL))
        XCTAssertEqual(restore.url.deletingLastPathComponent().standardizedFileURL,
                       inner.standardizedFileURL, "and it goes back into the folder it came from")
        XCTAssertNil(restore.notice)
    }

    /// A project outside `Projects/` altogether has no origin to mirror, and a delete must not fail
    /// for want of one. `restoreBackup` trashes packages by URL, so this is reachable rather than
    /// hypothetical.
    func testAProjectFromOutsideTheTreeIsTrashedAtTheTopAndRestoresThere() throws {
        let outside = root.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let project = writeProject(named: "Stray", in: outside)

        let trashURL = try XCTUnwrap(ProjectBackupManager.moveToTrash(project, tag: "deleted"))
        XCTAssertEqual(trashURL.deletingLastPathComponent().standardizedFileURL,
                       ProjectBackupManager.trashDirectory.standardizedFileURL,
                       "no mirror could be made, so it sits at the top of the trash")
        XCTAssertNil(ProjectBackupManager.folderComponents(of: outside, under: ProjectStore.projectsDirectory),
                     "which is what 'not under Projects/' answers, rather than an empty path")

        let restore = try XCTUnwrap(ProjectBackupManager.restoreFromTrash(trashURL))
        XCTAssertEqual(restore.url.deletingLastPathComponent().standardizedFileURL,
                       ProjectStore.projectsDirectory.standardizedFileURL)
        XCTAssertNil(restore.notice)
    }

    /// A restore that could not happen answers nil, and the trash keeps what it had. The gallery's
    /// Restore button used to discard this result, so a refusal looked exactly like a success and
    /// then like a project that had vanished — the discarded-`Bool` shape this repo has a filed bug
    /// for. It says so on screen now; **what this test pins is the nil, not the sentence**, because
    /// nothing in a logic test can make the filesystem refuse a move the way a real one would.
    func testARestoreThatCannotHappenAnswersNilAndTakesNothingWithIt() throws {
        let scene = try ProjectStore.createFolder(named: "Scene 3", in: ProjectStore.projectsDirectory)
        let real = try XCTUnwrap(ProjectBackupManager.moveToTrash(writeProject(named: "Kept", in: scene), tag: "deleted"))
        let ghost = real.deletingLastPathComponent().appendingPathComponent("NotThere__deleted__20260101-000000.paintproj")

        XCTAssertNil(ProjectBackupManager.restoreFromTrash(ghost),
                     "a restore of something that is not there refuses rather than reporting success")
        XCTAssertEqual(ProjectBackupManager.listTrash().map(\.displayName), ["Kept"],
                       "and the entry that is there is untouched")
        XCTAssertTrue(ProjectBackupManager.isDirectory(
            ProjectBackupManager.trashDirectory.appendingPathComponent("Scene 3")),
                      "including its mirror, which a refusal must not sweep out from under it")
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
