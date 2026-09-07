import XCTest

/// **The defect TODO (36) exists to prevent, asserted rather than assumed.**
///
/// The owner, 2026-09-07: *"Every time a test build gets uploaded to Ipad currently, everything is
/// wiped."* On the same day a measurement pass wiped the app container on their iPad and destroyed
/// `AnimationTest` with no recovery. So the test that matters is not "the picker works" — it is
/// **a reinstall takes the container and does not take the chosen folder**, and the first half of
/// that has to be asserted too, or the second half is a claim about nothing.
///
/// A reinstall is modelled as what it physically is: the app's container directory is replaced with
/// an empty one, and `UserDefaults` goes with it (the defaults plist lives in
/// `Library/Preferences`, inside the container). `appFolderOverride` and `defaults` are the two
/// seams that make that expressible without an actual install, and both are restored in `tearDown`
/// — a bookmark left in `UserDefaults.standard` would outlive the run exactly as
/// `CanvasManager.renderResolution` did when it cost a later fast tier 15 reds.
///
/// `ProjectBackupManager.rootDirectoryOverride` is held **nil** throughout, deliberately: it is the
/// hook every other suite uses to escape the container, and leaving it set here would mean the thing
/// under test — `documentsDirectory` consulting `ProjectLocation` — was never exercised at all.
final class ProjectLocationLogicTests: XCTestCase {

    private var scratch: URL!
    private var container: URL!
    private var external: URL!
    private var suiteName: String!
    private var savedOverride: URL?

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-location-tests-\(UUID().uuidString)", isDirectory: true)
        container = scratch.appendingPathComponent("Container", isDirectory: true)
        external = scratch.appendingPathComponent("OnMyIPad", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)

        suiteName = "project-location-tests-\(UUID().uuidString)"
        ProjectLocation.defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        ProjectLocation.appFolderOverride = container
        savedOverride = ProjectBackupManager.rootDirectoryOverride
        ProjectBackupManager.rootDirectoryOverride = nil
        ProjectLocation.resetForTesting()
    }

    override func tearDownWithError() throws {
        ProjectLocation.resetForTesting()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        ProjectLocation.defaults = .standard
        ProjectLocation.appFolderOverride = nil
        ProjectBackupManager.rootDirectoryOverride = savedOverride
        try? FileManager.default.removeItem(at: scratch)
        scratch = nil; container = nil; external = nil
    }

    // MARK: - The regression this feature exists for

    /// **A reinstall destroys a project saved inside the app, and leaves one in a chosen folder
    /// untouched — and re-choosing that folder brings the whole library back.**
    ///
    /// Three assertions, and the first is the one that makes the other two mean something: without
    /// it, "the file is still there" could be true of an implementation that never wrote anything
    /// into the container in the first place.
    ///
    /// The third is the honest part of the answer. **The bookmark does not survive a reinstall** —
    /// `UserDefaults` is inside the container that was just replaced — so the app comes back not
    /// knowing where the library is. What survives is the artwork, which is the whole ask; the
    /// recovery is one trip through the picker, and this pins that it is *only* one trip and that
    /// nothing has to be imported, re-named or repaired afterwards.
    func testAProjectInAChosenFolderSurvivesAReinstallAndOneInsideTheAppDoesNot() throws {
        // Baseline: the default location is the container, and a project written there is inside it.
        XCTAssertEqual(ProjectBackupManager.documentsDirectory.standardizedFileURL,
                       container.standardizedFileURL,
                       "PREMISE: with no folder chosen the library is the app's own container")
        let doomed = writeProject(named: "Doomed")
        XCTAssertTrue(doomed.path.hasPrefix(container.path),
                      "PREMISE: it really is inside the container")

        // Choose a folder outside the container, as the artist would.
        let adoption = try ProjectLocation.adopt(external)
        XCTAssertEqual(adoption.status, .chosen(external))
        let survivor = writeProject(named: "Survivor")
        XCTAssertFalse(survivor.path.hasPrefix(container.path),
                       "a project saved after the move is not in the container at all")

        // Both projects are now in the chosen folder: `Doomed` was migrated out.
        XCTAssertEqual(Set(ProjectStore.listProjects().map(\.name)), ["Doomed", "Survivor"])

        simulateReinstall()

        // 1. The defect: anything the container held is gone.
        XCTAssertFalse(FileManager.default.fileExists(atPath: doomed.path),
                       "a reinstall replaces the container — this is the failure being prevented")
        XCTAssertTrue(ProjectStore.listProjects().isEmpty,
                      "and the fresh install opens on an empty gallery, having forgotten the folder")

        // 2. The fix: the artwork is untouched where the artist put it.
        XCTAssertTrue(FileManager.default.fileExists(atPath: survivor.path),
                      "the project in the chosen folder is still on disk after the reinstall")

        // 3. The recovery: one trip through the picker and the library is back, whole.
        let recovered = try ProjectLocation.adopt(external)
        XCTAssertEqual(recovered.status, .chosen(external))
        XCTAssertEqual(Set(ProjectStore.listProjects().map(\.name)), ["Doomed", "Survivor"],
                       "re-choosing the same folder restores every project, including the one that "
                       + "was migrated out of the container before the reinstall")
    }

    /// The saves themselves land outside the container, not merely the listing. A relocation that
    /// only changed where the gallery *looked* would pass the test above while every new stroke
    /// still went into the container.
    func testWritesGoToTheChosenFolderRatherThanTheContainer() throws {
        _ = try ProjectLocation.adopt(external)
        let url = ProjectStore.createNewProjectURL(name: "Written")
        XCTAssertTrue(url.path.hasPrefix(external.path), "createNewProjectURL follows the root")
        XCTAssertEqual(ProjectBackupManager.backupsRootDirectory.deletingLastPathComponent()
                        .standardizedFileURL, external.standardizedFileURL,
                       "and so do the backups — a safety net left in the container would protect the "
                       + "artist against everything except the thing that actually happened")
        XCTAssertEqual(ProjectBackupManager.trashDirectory.deletingLastPathComponent()
                        .standardizedFileURL, external.standardizedFileURL,
                       "and so does the trash")
    }

    // MARK: - A failure to re-resolve is a sentence

    /// **The folder is gone at launch: the app opens, and it says what happened in words.**
    ///
    /// Both halves are asserted because either alone is a defect. Reporting without falling back is
    /// an app that will not open; falling back without reporting is the dangerous one — the artist
    /// draws all day into the container this feature exists to escape and is never told.
    func testAFolderThatIsGoneAtLaunchIsNamedInASentenceRatherThanSwallowed() throws {
        _ = try ProjectLocation.adopt(external)
        _ = writeProject(named: "Away")

        // The drive is unplugged / the folder deleted in Files, and the app is launched again.
        try FileManager.default.removeItem(at: external)
        ProjectLocation.resetForTesting()
        let status = ProjectLocation.resolveOnLaunch()

        guard case let .unavailable(name, _) = status else {
            return XCTFail("a missing folder must report .unavailable, got \(status)")
        }
        XCTAssertEqual(name, "OnMyIPad", "the sentence names the folder the artist chose")
        let problem = try XCTUnwrap(status.problem, "there is a sentence to show")
        XCTAssertTrue(problem.contains("OnMyIPad"), "and it names the folder: \(problem)")
        XCTAssertTrue(problem.lowercased().contains("inside the app"),
                      "and it says where work is going meanwhile: \(problem)")

        XCTAssertEqual(ProjectLocation.currentRoot.standardizedFileURL,
                       container.standardizedFileURL,
                       "the app still works, from the container")
        XCTAssertTrue(ProjectLocation.hasChosenFolder,
                      "and it has not forgotten the folder — reconnecting the drive is enough")
    }

    /// A resolvable folder the app cannot write into is reported too, and differently. This is the
    /// branch a `startAccessingSecurityScopedResource()` refusal lands in, and the reason it is
    /// probed by writing rather than read off that call's `Bool` (which is false for any URL that
    /// was never security-scoped, including every folder in these tests).
    func testAFolderThatCannotBeWrittenIntoIsReportedRatherThanUsed() throws {
        _ = try ProjectLocation.adopt(external)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: external.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: external.path) }

        ProjectLocation.resetForTesting()
        let status = ProjectLocation.resolveOnLaunch()
        guard case .unavailable = status else {
            return XCTFail("a read-only folder must report .unavailable, got \(status)")
        }
        XCTAssertNotNil(status.problem)
        XCTAssertEqual(ProjectLocation.currentRoot.standardizedFileURL,
                       container.standardizedFileURL)
    }

    /// A healthy folder resolves back from its bookmark on the next launch with nothing said.
    func testAHealthyFolderResolvesAgainAtTheNextLaunchWithNoProblemToReport() throws {
        _ = try ProjectLocation.adopt(external)
        _ = writeProject(named: "Kept")

        ProjectLocation.resetForTesting()
        let status = ProjectLocation.resolveOnLaunch()
        XCTAssertEqual(status, .chosen(external))
        XCTAssertNil(status.problem, "nothing is wrong, so nothing is said")
        XCTAssertEqual(ProjectStore.listProjects().map(\.name), ["Kept"])
    }

    /// Reverting brings the library home and forgets the bookmark.
    func testRevertingCarriesTheLibraryBackIntoTheAppAndForgetsTheFolder() throws {
        _ = try ProjectLocation.adopt(external)
        _ = writeProject(named: "Coming Home")

        _ = ProjectLocation.revertToAppFolder()

        XCTAssertEqual(ProjectLocation.status, .appFolder)
        XCTAssertFalse(ProjectLocation.hasChosenFolder)
        XCTAssertEqual(ProjectStore.listProjects().map(\.name), ["Coming Home"],
                       "the gallery is not empty afterwards — the projects came back with it")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: external.appendingPathComponent("Projects/Coming Home.paintproj").path),
                       "and the folder was emptied rather than left holding a stale second copy")
    }

    // MARK: - Migration

    func testMigrationCarriesEveryProjectAndLeavesNothingBehind() throws {
        for name in ["A", "B", "C"] { _ = writeProject(named: name) }
        _ = try ProjectLocation.adopt(external)

        XCTAssertEqual(Set(ProjectStore.listProjects().map(\.name)), ["A", "B", "C"])
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            atPath: container.appendingPathComponent("Projects").path)) ?? []
        XCTAssertEqual(leftovers, [], "the container's Projects folder is empty afterwards")
    }

    /// **Interrupted between the verified copy and the source removal, the next attempt finishes the
    /// job instead of repeating or duplicating it.** This is the resume path, and the state it
    /// resumes from is exactly what a kill at that instant leaves: a complete copy at the
    /// destination and a complete original at the source.
    func testAMigrationInterruptedAfterTheCopyIsFinishedRatherThanRepeated() throws {
        let source = writeProject(named: "Half Moved")
        let destinationProjects = external.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationProjects, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source,
                                         to: destinationProjects.appendingPathComponent("Half Moved.paintproj"))

        let report = ProjectLibraryMigration.migrate(from: container, to: external)

        XCTAssertEqual(report.alreadyThere, ["Projects/Half Moved.paintproj"],
                       "the copy already there was adopted, not copied again")
        XCTAssertEqual(report.moved, [], "and nothing was copied twice")
        XCTAssertEqual(report.renamed, [], "and it was not filed as a second project")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path),
                       "the source was removed, finishing the interrupted move")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destinationProjects.path),
                       ["Half Moved.paintproj"], "one project, not two")
    }

    /// **A different project of the same name at the destination is never clobbered.** The artist
    /// picked a folder they were already using; a migration that overwrote what was there would
    /// destroy work to move work.
    func testAMigrationNeverOverwritesSomethingDifferentAtTheDestination() throws {
        let source = writeProject(named: "Clash")
        let destinationProjects = external.appendingPathComponent("Projects", isDirectory: true)
        let existing = destinationProjects.appendingPathComponent("Clash.paintproj")
        try FileManager.default.createDirectory(at: existing.appendingPathComponent("images"),
                                                withIntermediateDirectories: true)
        try "not the same project".data(using: .utf8)!
            .write(to: existing.appendingPathComponent("marker.txt"))

        let report = ProjectLibraryMigration.migrate(from: container, to: external)

        XCTAssertEqual(report.renamed, ["Projects/Clash.paintproj"])
        XCTAssertEqual(try String(contentsOf: existing.appendingPathComponent("marker.txt"),
                                  encoding: .utf8), "not the same project",
                       "what was already there is byte-for-byte untouched")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationProjects.appendingPathComponent("Clash 2.paintproj").path),
                      "and the incoming project arrived beside it under a free name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        _ = source
    }

    /// **A copy that cannot be made leaves the source exactly where it is.** The invariant is that
    /// every project is complete in at least one root at every instant, and the only way to keep it
    /// is for a failed copy to abandon the destination rather than the source.
    func testACopyThatCannotBeMadeLeavesTheSourceAlone() throws {
        let source = writeProject(named: "Unmovable")
        // A destination that will not take a write is the one failure this test can cause on demand,
        // and it exercises the same abandon-the-destination path a kill mid-copy does.
        let destinationProjects = external.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationProjects, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: destinationProjects.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: destinationProjects.path) }

        let report = ProjectLibraryMigration.migrate(from: container, to: external)

        XCTAssertEqual(report.failed, ["Projects/Unmovable.paintproj"])
        XCTAssertEqual(report.moved, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "the project is still where it was — a failed copy must never be a deletion")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: source),
                      "and it is still whole, not half-consumed by the attempt")
    }

    /// **A damaged package migrates, and must.** This is a refutation of this file's own first
    /// design: gating the move on `validateProject` reads as caution and is the opposite, because a
    /// damaged project is one the gallery still lists with a Restore-from-Backup button, and the
    /// trash is full of packages that are damaged precisely because that is why they were trashed.
    /// Leaving those in the container is leaving them to the next reinstall.
    func testADamagedProjectIsCarriedRatherThanStrandedInTheContainer() throws {
        let damaged = writeProject(named: "Damaged")
        try Data("not json".utf8).write(to: damaged.appendingPathComponent("manifest.json"))
        XCTAssertFalse(ProjectBackupManager.validateProject(at: damaged),
                       "PREMISE: the package no longer validates")

        let report = ProjectLibraryMigration.migrate(from: container, to: external)

        XCTAssertEqual(report.moved, ["Projects/Damaged.paintproj"])
        XCTAssertEqual(report.failed, [], "a damaged project is not a failed migration")
        XCTAssertFalse(FileManager.default.fileExists(atPath: damaged.path))
        let moved = external.appendingPathComponent("Projects/Damaged.paintproj")
        XCTAssertEqual(try String(contentsOf: moved.appendingPathComponent("manifest.json"),
                                  encoding: .utf8), "not json",
                       "carried faithfully, damage and all, for the repair pass to find at the new root")
    }

    /// A staged husk from a killed run is swept, not adopted and not carried.
    func testAStagedHuskFromAKilledRunIsSweptRatherThanTreatedAsAProject() throws {
        _ = writeProject(named: "Real")
        let destinationProjects = external.appendingPathComponent("Projects", isDirectory: true)
        let husk = destinationProjects.appendingPathComponent(
            ProjectLibraryMigration.stagingPrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: husk, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: husk.appendingPathComponent("partial.png"))

        _ = ProjectLibraryMigration.migrate(from: container, to: external)

        XCTAssertFalse(FileManager.default.fileExists(atPath: husk.path),
                       "the abandoned copy is gone")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destinationProjects.path),
                       ["Real.paintproj"])
    }

    /// The backups and the trash travel too. A relocation that moved only `Projects/` would leave
    /// every restore point in the container, so the first bad save after a move would have nothing
    /// to fall back on.
    func testTheBackupsAndTrashMoveWithTheProjects() throws {
        _ = writeProject(named: "Backed Up")
        let backupDir = ProjectBackupManager.backupsDirectory(projectID: UUID())
        try Data([9]).write(to: backupDir.appendingPathComponent("origin.name"))
        let trashed = ProjectBackupManager.trashDirectory.appendingPathComponent("Old__deleted__1.paintproj")
        try FileManager.default.createDirectory(at: trashed, withIntermediateDirectories: true)

        _ = try ProjectLocation.adopt(external)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: external.appendingPathComponent("Backups/\(backupDir.lastPathComponent)/origin.name").path),
                      "the backup slot moved")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: external.appendingPathComponent("Trash/Old__deleted__1.paintproj").path),
                      "and so did the trash")
    }

    /// `census` is what "verified" means, so it is worth pinning that it actually walks into a
    /// package rather than counting it as one item.
    func testTheCensusWalksIntoAPackageRatherThanCountingItAsOneItem() throws {
        let project = writeProject(named: "Counted")
        let census = ProjectLibraryMigration.census(of: project)
        XCTAssertGreaterThan(census.files, 1, "a package is a directory of files, and all of them count")
        XCTAssertGreaterThan(census.bytes, 0)

        let copy = scratch.appendingPathComponent("copy.paintproj")
        try FileManager.default.copyItem(at: project, to: copy)
        XCTAssertTrue(ProjectLibraryMigration.matches(source: project, destination: copy))

        try FileManager.default.removeItem(at: copy.appendingPathComponent("manifest.json"))
        XCTAssertFalse(ProjectLibraryMigration.matches(source: project, destination: copy),
                       "a copy missing one file does not verify")
    }

    // MARK: - Fixtures

    /// A minimal package that `ProjectBackupManager.validateProject` accepts: a manifest naming one
    /// cel whose raster was omitted, plus the `images/` directory the validator expects to walk.
    @discardableResult
    private func writeProject(named name: String) -> URL {
        let url = ProjectStore.createNewProjectURL(name: name)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.appendingPathComponent("images"), withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "id": UUID().uuidString,
            "layers": [["cels": [["rasterFileName": "a.png", "rasterOmitted": true]]]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: manifest)
        try! data.write(to: url.appendingPathComponent("manifest.json"))
        try! Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            .write(to: url.appendingPathComponent("thumbnail.png"))
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "fixture precondition: the package validates")
        return url
    }

    /// **What a reinstall physically is**: the container directory is replaced by an empty one, and
    /// `UserDefaults` goes with it — the defaults plist lives in `Library/Preferences` *inside* the
    /// container. Modelling only the first half would be modelling a wipe that leaves the app
    /// knowing where its library is, which is not the thing that happens.
    private func simulateReinstall() {
        ProjectLocation.resetForTesting()
        try? FileManager.default.removeItem(at: container)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        ProjectLocation.defaults = UserDefaults(suiteName: suiteName)!
        ProjectLocation.resolveOnLaunch()
    }
}
