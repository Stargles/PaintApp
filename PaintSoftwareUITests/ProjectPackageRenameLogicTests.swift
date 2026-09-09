import XCTest
import UIKit

/// **A project's folder is named after the project** — TODO (57) part 2.
///
/// The owner, 2026-09-08, looking at their own iPad in Files: *"Folder names are Untitled.paintproj
/// but does not change when the project name is changed."* They had the cause exactly right.
/// `ProjectStore.createNewProjectURL` runs **once**, on a document's very first save, and until this
/// item nothing had ever re-derived the directory name from the title again — so every project the
/// artist named after creating it kept the name it was born with, forever.
///
/// Two things rename a package now, and the suite is organised around the difference:
///
///  1. **The save**, on the narrow question — *did the title change in this save?* That is the
///     owner's complaint stated exactly, and it is what the first block below drives, end to end,
///     through the shipped `ProjectStore.save`.
///  2. **The launch pass**, on the broad one — *is this stem an acceptable rendering of the title
///     today?* It exists for the backlog: a project retitled under a build that shipped before this
///     one has no change event left for the save to catch. The fixture for that population is
///     `retitleOnDisk`, which rewrites the manifest's `name` and leaves the folder alone — which is
///     precisely what the old build did.
///
/// **Every assertion about a surviving project is about the artist's ink**, not about a package that
/// loads. `decodeCel` gives a vector layer an empty `VectorCanvas` when its payload cannot be read,
/// so `XCTAssertNotNil` on the canvas is green against total loss of the drawing.
@MainActor
final class ProjectPackageRenameLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-rename-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        // **The registry is process-wide and has no `noteClosed`** — see `PackageRenameGate`. Without
        // this an earlier suite's saves would leave packages registered and the launch pass would
        // decline to rename them here, which is a green test that measured nothing.
        PackageRenameGate.resetForTesting()
    }

    override func tearDownWithError() throws {
        PackageRenameGate.resetForTesting()
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Fixtures

    /// The two sample coordinates the fixture stroke is drawn through. Named, so that "the ink
    /// survived" is an assertion about *these two points* rather than about a count.
    private static let inkStart = CGPoint(x: 21, y: 43)
    private static let inkEnd = CGPoint(x: 65, y: 87)

    /// A document with one vector cel carrying a real stroke.
    private func makeManager(titled title: String) -> CanvasManager {
        let manager = CanvasManager()
        manager.projectName = title
        manager.addVectorLayer(name: "Ink")
        let vectorLayer = manager.layers.count - 1
        let canvas = manager.layers[vectorLayer].cels[0].vector
        XCTAssertNotNil(canvas, "Setup: a vector layer's first cel should carry a VectorCanvas")
        canvas?.addStroke(VectorStroke(
            brush: manager.selectedBrush,
            color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: 8, opacity: 1,
            samples: [VectorSample(x: Self.inkStart.x, y: Self.inkStart.y, pressure: 1),
                      VectorSample(x: Self.inkEnd.x, y: Self.inkEnd.y, pressure: 1)]))
        return manager
    }

    /// One save, waited on. Returns where the package actually landed, which since (57) part 2 is not
    /// necessarily where it was aimed.
    ///
    /// **`manager.projectURL` is what it reads afterwards, deliberately.** That property is the app's
    /// only in-memory holder of the bundle URL, `ProjectStore.save` updates it on the main actor
    /// before `completion` runs, and `ContentView.saveIfNeeded` reads it as the target of the *next*
    /// save — so a helper that returned the URL it passed in would hide the exact defect this suite
    /// is here to pin.
    @discardableResult
    private func save(_ manager: CanvasManager, to url: URL,
                      file: StaticString = #filePath, line: UInt = #line) -> URL {
        // As `ContentView.saveIfNeeded` does: the property is set before the save, and the save is
        // what moves it.
        manager.projectURL = url
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
        let landed = manager.projectURL ?? url
        XCTAssertTrue(FileManager.default.fileExists(atPath: landed.path),
                      "Setup: the save should have landed a package at \(landed.lastPathComponent)",
                      file: file, line: line)
        return landed
    }

    /// A saved project, in this build's layout, whose folder already matches its title.
    private func savedProject(titled title: String) -> (manager: CanvasManager, url: URL) {
        let manager = makeManager(titled: title)
        let url = save(manager, to: ProjectStore.createNewProjectURL(name: title))
        return (manager, url)
    }

    /// **Retitles a package the way a build that shipped before (57) part 2 did**: the manifest's
    /// `name` changes and the directory keeps the name it was born with.
    ///
    /// This is the fixture for the launch pass, and it is the whole population the pass exists for —
    /// every project the owner ever renamed. Written as surgery on the on-disk JSON rather than by
    /// saving through the app, because saving through the app is exactly the thing that now fixes it.
    private func retitleOnDisk(at url: URL, to title: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return XCTFail("fixture: \(url.lastPathComponent) should carry a readable manifest.json",
                           file: file, line: line)
        }
        json["name"] = title
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            return XCTFail("fixture: the retitled manifest should re-encode", file: file, line: line)
        }
        try? rewritten.write(to: manifestURL, options: .atomic)
    }

    /// The `.paintproj` directory names directly inside `Projects/`, in the case the filesystem
    /// reports — which is the only way to see a case-only rename at all.
    private func packageNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: ProjectBackupManager.projectsDirectory.path)) ?? [])
            .filter { $0.hasSuffix(".paintproj") }
            .sorted()
    }

    /// The ink, read back out of a loaded document — the two sample points the fixture drew.
    private func assertInkSurvived(at url: URL, _ context: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("\(context): the package at \(url.lastPathComponent) should load at all",
                           file: file, line: line)
        }
        let canvases = reloaded.layers.compactMap { $0.cels.first?.vector }
        guard let canvas = canvases.first(where: { !$0.strokes.isEmpty }) else {
            return XCTFail("\(context): some vector cel should still carry the stroke the fixture drew "
                           + "— an empty VectorCanvas is what an unreadable payload also produces",
                           file: file, line: line)
        }
        guard let stroke = canvas.strokes.first, stroke.samples.count == 2 else {
            return XCTFail("\(context): the surviving stroke should still have both of its samples",
                           file: file, line: line)
        }
        // TODO (8) stores samples quantised, so the comparison is to within half a quantum.
        let quantum = PackedSampleRun.quantum / 2
        XCTAssertEqual(stroke.samples[0].x, Self.inkStart.x, accuracy: quantum,
                       "\(context): the stroke's first sample x is where the artist put it",
                       file: file, line: line)
        XCTAssertEqual(stroke.samples[0].y, Self.inkStart.y, accuracy: quantum,
                       "\(context): the stroke's first sample y is where the artist put it",
                       file: file, line: line)
        XCTAssertEqual(stroke.samples[1].x, Self.inkEnd.x, accuracy: quantum,
                       "\(context): the stroke's last sample x is where the artist put it",
                       file: file, line: line)
        XCTAssertEqual(stroke.samples[1].y, Self.inkEnd.y, accuracy: quantum,
                       "\(context): the stroke's last sample y is where the artist put it",
                       file: file, line: line)
    }

    // MARK: - (a) The owner's complaint, driven through the shipped save

    /// The headline. Retitle a saved project and save it: the folder follows, the old name is gone,
    /// and the drawing is still the drawing.
    func testRetitlingAProjectMakesItsFolderFollowAndTheInkSurvives() {
        let (manager, original) = savedProject(titled: "Boat")
        XCTAssertEqual(original.lastPathComponent, "Boat.paintproj",
                       "Setup: the first save names the folder after the title, as it always did")

        manager.projectName = "Seagull"
        let landed = save(manager, to: original)

        XCTAssertEqual(landed.lastPathComponent, "Seagull.paintproj",
                       "the folder is named after the project, which is the whole ask")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path),
                       "and the old name is gone rather than left beside it as a second copy")
        XCTAssertEqual(packageNames(), ["Seagull.paintproj"],
                       "exactly one package remains, got \(packageNames())")
        assertInkSurvived(at: landed, "after a retitle-and-save")
    }

    /// The other half of the same behaviour, and the one that keeps this out of every other suite in
    /// the bundle: a save that did not retitle anything renames nothing.
    func testASaveThatDidNotRetitleAnythingLeavesTheFolderAlone() {
        let (manager, original) = savedProject(titled: "Boat")
        // A hand-picked URL whose stem is nothing like the title — which is what forty-odd existing
        // tests do, and what a broad rule applied on the save path would have renamed under them.
        let odd = ProjectBackupManager.projectsDirectory.appendingPathComponent("Damaged.paintproj")
        XCTAssertTrue(ProjectBackupManager.cloneItem(at: original, to: odd),
                      "Setup: a package filed under a name that does not match its title")

        let manager2 = makeManager(titled: "Boat")
        let landed = save(manager2, to: odd)

        XCTAssertEqual(landed, odd,
                       "the save asks whether the title changed in *this* save, not whether the stem "
                       + "is a good rendering of it — the broad question belongs to the launch pass")
        _ = manager
    }

    // MARK: - (b) The four names a title can produce that a folder name cannot

    /// A title with a path separator used to create a **real subfolder** and file the project inside
    /// it, permanently — a rename never moves a project between folders, so nothing could ever bring
    /// it back. Part 1 closed that on the first-save path; this is the rename path.
    func testATitleWithAPathSeparatorCannotEscapeIntoASubfolder() {
        let (manager, original) = savedProject(titled: "Boat")

        manager.projectName = "Boat/Race: Two"
        let landed = save(manager, to: original)

        XCTAssertEqual(landed.lastPathComponent, "Boat Race  Two.paintproj",
                       "both `/` and `:` become spaces, got \(landed.lastPathComponent)")
        XCTAssertEqual(landed.deletingLastPathComponent().path,
                       ProjectBackupManager.projectsDirectory.path,
                       "and the project stays at the top of Projects/ rather than inside a folder "
                       + "the separator invented")
        XCTAssertTrue(ProjectStore.listFolders(in: ProjectBackupManager.projectsDirectory).isEmpty,
                      "no sub-folder was created, got "
                      + "\(ProjectStore.listFolders(in: ProjectBackupManager.projectsDirectory).map(\.name))")
        assertInkSurvived(at: landed, "after a retitle containing a path separator")
    }

    /// An empty title is a thing an artist can type — the Scene field has no validation at all — and
    /// an empty path component is a thing the filesystem cannot hold.
    func testAnEmptyTitleFallsBackToUntitledRatherThanAnUnnamedFolder() {
        let (manager, original) = savedProject(titled: "Boat")

        manager.projectName = "   "
        let landed = save(manager, to: original)

        XCTAssertEqual(landed.lastPathComponent, "Untitled.paintproj",
                       "whitespace trims to nothing, and nothing falls back to Untitled")
        assertInkSurvived(at: landed, "after a retitle to an empty string")
    }

    /// A long title, bounded in **both** units. Sixty `Character`s can be many hundreds of UTF-8
    /// bytes, and 255 bytes is what the filesystem enforces on a path component — with `Trash`
    /// appending `__<tag>__<yyyyMMdd-HHmmss>` to it later.
    func testAVeryLongTitleBecomesAFolderNameTheFilesystemAccepts() {
        let (manager, original) = savedProject(titled: "Boat")

        manager.projectName = String(repeating: "Seagull ", count: 60)
        let landed = save(manager, to: original)
        let stem = landed.deletingPathExtension().lastPathComponent

        XCTAssertLessThanOrEqual(stem.count, ProjectPackageName.maximumStemCharacters,
                                 "the stem is bounded in characters, got \(stem.count)")
        XCTAssertLessThanOrEqual(stem.utf8.count, ProjectPackageName.maximumStemBytes,
                                 "and in bytes, which is the bound the filesystem actually enforces")
        XCTAssertFalse(stem.hasSuffix(" "),
                       "truncation must not expose a trailing space, got \"\(stem)\"")
        XCTAssertTrue(FileManager.default.fileExists(atPath: landed.path),
                      "and the filesystem accepted the name that produced")
        assertInkSurvived(at: landed, "after a retitle to a 480-character title")
    }

    /// **The case-only retitle, which the naive rule gets wrong in a way that is invisible until you
    /// look at Files.** iOS's APFS volume folds case, so `fileExists` says `Boat.paintproj` is taken
    /// the moment `boat.paintproj` exists — and a disambiguation loop that believed it would rename
    /// the artist's project to "Boat 2" for changing one letter to a capital.
    func testACaseOnlyRetitleRenamesInPlaceRatherThanDisambiguatingItself() {
        let (manager, original) = savedProject(titled: "boat")
        XCTAssertEqual(original.lastPathComponent, "boat.paintproj", "Setup: lower case on disk")

        manager.projectName = "Boat"
        let landed = save(manager, to: original)

        XCTAssertEqual(packageNames(), ["Boat.paintproj"],
                       "one package, renamed in place and in the artist's own case — not two, and "
                       + "not \"Boat 2\", got \(packageNames())")
        assertInkSurvived(at: landed, "after a case-only retitle")
    }

    // MARK: - (c) Two projects that want the same name

    /// Titles have no uniqueness rule anywhere in the app — two projects may share one freely — but
    /// directory names must be distinct. Both projects have to survive that, with their own ink.
    func testTwoProjectsWithTheSameTitleGetDistinctFoldersAndBothKeepTheirInk() {
        let (first, firstURL) = savedProject(titled: "Boat")
        let (second, secondURL) = savedProject(titled: "Kite")

        second.projectName = "Boat"
        let secondLanded = save(second, to: secondURL)

        XCTAssertEqual(secondLanded.lastPathComponent, "Boat 2.paintproj",
                       "the second project takes the next free rendering of the shared title")
        XCTAssertEqual(packageNames(), ["Boat 2.paintproj", "Boat.paintproj"],
                       "and both projects are still on disk, got \(packageNames())")
        XCTAssertNotEqual(ProjectBackupManager.manifestID(at: firstURL),
                          ProjectBackupManager.manifestID(at: secondLanded),
                          "two projects, two manifest ids — the gallery lists rows by that id")
        assertInkSurvived(at: firstURL, "the first project after the second took its title")
        assertInkSurvived(at: secondLanded, "the second project under its disambiguated name")
        _ = first
    }

    /// **"Boat 2" must not be renamed to "Boat" and back forever.** The disambiguation is invisible
    /// to a plain equality check, so without this clause the launch pass would rename the second
    /// project on every single launch — to "Boat", which is taken, hence "Boat 2" again — and write
    /// its backup marker each time.
    func testADisambiguatedFolderIsRecognisedAsThisTitleAndLeftAlone() {
        let (_, firstURL) = savedProject(titled: "Boat")
        let (second, secondURL) = savedProject(titled: "Kite")
        second.projectName = "Boat"
        let secondLanded = save(second, to: secondURL)
        XCTAssertEqual(secondLanded.lastPathComponent, "Boat 2.paintproj", "Setup: disambiguated")

        // The launch pass asks the broad question, which is the one that could ping-pong.
        PackageRenameGate.resetForTesting()
        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertTrue(report.renamed.isEmpty,
                      "neither package is renamed on a launch that changed nothing, got \(report.renamed)")
        XCTAssertEqual(packageNames(), ["Boat 2.paintproj", "Boat.paintproj"],
                       "and both keep the names they had, got \(packageNames())")
        XCTAssertNil(ProjectPackageName.reconciled(secondLanded, title: "Boat",
                                                   projectID: ProjectBackupManager.manifestID(at: secondLanded)),
                     "stated directly as a property of the rule: \"Boat 2\" is already a rendering "
                     + "of \"Boat\"")
        _ = firstURL
    }

    // MARK: - (d) The backlog: every project the owner already renamed

    /// The population this item exists for. A build that shipped before (57) part 2 wrote the new
    /// title into the manifest and left the folder alone; the launch pass is the only thing that will
    /// ever catch up with it, because there is no "the title changed in this save" event left.
    func testTheLaunchPassRenamesAFolderThatStoppedMatchingItsTitle() {
        let (_, url) = savedProject(titled: "Boat")
        retitleOnDisk(at: url, to: "Seagull")
        // A fresh launch: nothing is open.
        PackageRenameGate.resetForTesting()

        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertEqual(report.renamed, ["Seagull.paintproj"],
                       "the pass reports the new name, got \(report.renamed)")
        XCTAssertEqual(packageNames(), ["Seagull.paintproj"],
                       "the folder on disk follows the title, got \(packageNames())")
        assertInkSurvived(at: ProjectBackupManager.projectsDirectory
                            .appendingPathComponent("Seagull.paintproj"),
                          "after the launch pass renamed the folder")
    }

    /// **The fork the reviewers found, and the thing that makes it impossible.**
    ///
    /// The launch pass walks the library on a detached task while the artist opens a project and
    /// retitles it. If the pass renames that package from the *stale* title it read, and the save
    /// then lands the artist's edits at a name computed from the *new* title, the library holds two
    /// packages carrying one manifest id — and `ProjectSummary` is `Identifiable` by that id, so the
    /// gallery's `ForEach` gets two rows with one identity and one of them may never draw.
    ///
    /// **Three names, because the fork needs three.** The package is filed under `Boat` while its
    /// manifest already says `Seagull` — a project retitled under a pre-(57) build, which is the only
    /// population the pass has work in. The pass, left to itself, would rename it to `Seagull`; the
    /// artist, retitling again in this session, saves it as `Kite`. Two packages, one manifest id,
    /// and nothing in the app ever reconciles them.
    ///
    /// Asserted in three parts: the pass declines, the registry is *why* it declined, and the save's
    /// own rename lands on exactly one package rather than beside the pass's.
    func testTheLaunchPassWillNotRenameAPackageThisProcessHasOpenAndForkIt() {
        let (manager, url) = savedProject(titled: "Boat")
        retitleOnDisk(at: url, to: "Seagull")
        // The artist opened it, so the in-memory title is the one the manifest holds.
        manager.projectName = "Seagull"
        XCTAssertTrue(PackageRenameGate.isOpen(url),
                      "Setup: opening or saving a package registers it — the artist has this one open")
        XCTAssertNotNil(ProjectPackageName.reconciled(url, title: "Seagull",
                                                      projectID: ProjectBackupManager.manifestID(at: url)),
                        "Setup: and the pass genuinely has a rename to decline — the rule says this "
                        + "folder should be called Seagull")

        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertTrue(report.renamed.isEmpty,
                      "the pass leaves an open package's directory alone, got \(report.renamed)")
        XCTAssertEqual(packageNames(), ["Boat.paintproj"],
                       "so the name the save is about to compute from is still the one it knows")

        // The artist retitles again and saves. This is the save whose target the pass could have
        // diverged from.
        manager.projectName = "Kite"
        let landed = save(manager, to: url)

        XCTAssertEqual(packageNames(), ["Kite.paintproj"],
                       "exactly one package, under the artist's newest title — not one at Seagull "
                       + "and one at Kite sharing a manifest id, got \(packageNames())")
        assertInkSurvived(at: landed, "after the save renamed a package the pass had declined")
    }

    /// The honest cost of that refusal, stated rather than left to be discovered: a package the
    /// artist merely *opened* — without retitling it — keeps its stale name for the rest of the
    /// session, because the save's trigger is the change and there was none. The next launch, with
    /// nothing open, catches up.
    func testAnOpenPackageThatWasNotRetitledCatchesUpOnTheNextLaunch() {
        let (manager, url) = savedProject(titled: "Boat")
        retitleOnDisk(at: url, to: "Seagull")
        manager.projectName = "Seagull"

        ProjectPackageLayout.tidyEveryProject()
        let landed = save(manager, to: url)
        XCTAssertEqual(landed.lastPathComponent, "Boat.paintproj",
                       "this session leaves it where it is: the pass will not rename an open package "
                       + "and the save saw no retitle")

        // A new launch: nothing is open.
        PackageRenameGate.resetForTesting()
        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertEqual(report.renamed, ["Seagull.paintproj"],
                       "and the very next launch catches up, got \(report.renamed)")
        assertInkSurvived(at: ProjectBackupManager.projectsDirectory
                            .appendingPathComponent("Seagull.paintproj"),
                          "after the following launch renamed it")
    }

    /// `origin.name` is `backupDirectory(forProjectAt:)`'s fallback for a package whose manifest has
    /// become unreadable — the one case where the primary manifest-id lookup cannot answer — and it
    /// records the package's filename at the moment a backup slot was minted. A rename that did not
    /// carry it would strand a project's entire version history exactly when it is needed.
    func testARenameCarriesTheBackupFolderMarkerWithIt() throws {
        let (_, url) = savedProject(titled: "Boat")
        let projectID = try XCTUnwrap(ProjectBackupManager.manifestID(at: url))
        let marker = ProjectBackupManager.backupsDirectory(projectID: projectID)
            .appendingPathComponent("origin.name")
        XCTAssertEqual(try? String(contentsOf: marker, encoding: .utf8), "Boat.paintproj",
                       "Setup: the marker names the package as it was saved")

        retitleOnDisk(at: url, to: "Seagull")
        PackageRenameGate.resetForTesting()
        ProjectPackageLayout.tidyEveryProject()

        XCTAssertEqual(try? String(contentsOf: marker, encoding: .utf8), "Seagull.paintproj",
                       "the marker follows the rename, written before the move rather than after it")
    }

    /// A kill between the directory rename and the sidecar moves is a real on-disk state — the pass
    /// runs on a detached task and iOS may background the app at any point in it — and it is the row
    /// of `tidy`'s own resume table that (57) part 2 adds. Both halves are asserted: the package
    /// opens whole in that state, **and** a second run finishes it.
    func testAPackageKilledAfterTheRenameButBeforeTheSidecarMovesIsFinishedByTheNextRun() throws {
        let (_, url) = savedProject(titled: "Boat")
        retitleOnDisk(at: url, to: "Seagull")

        // The state a kill after step 5 leaves: the new directory name, sidecars still wherever they
        // were, manifest untouched.
        let renamed = ProjectBackupManager.projectsDirectory.appendingPathComponent("Seagull.paintproj")
        try FileManager.default.moveItem(at: url, to: renamed)

        assertInkSurvived(at: renamed, "mid-pass, killed just after the directory rename")

        PackageRenameGate.resetForTesting()
        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertTrue(report.renamed.isEmpty,
                      "the second run has no rename left to do — it is idempotent, got \(report.renamed)")
        XCTAssertEqual(packageNames(), ["Seagull.paintproj"],
                       "and does not mint a third name, got \(packageNames())")
        assertInkSurvived(at: renamed, "after the pass re-ran over a half-finished package")
    }

    // MARK: - (e) Every in-session holder of the old URL

    /// **`CanvasManager.projectURL` is the app's only in-memory holder of the bundle URL**, and a
    /// rename that did not update it is worse than no rename at all.
    ///
    /// `ContentView.saveIfNeeded` reads that property as the target of the *next* save. Left stale,
    /// the next save stages beside the new name, finds nothing at the old one to stash
    /// (`stashLiveProjectForSave` returns true trivially when the path does not exist), and renames
    /// its staged package **into the old path** — resurrecting the folder the artist renamed away
    /// from, as a second project.
    func testTheNextSaveGoesToTheNewFolderRatherThanResurrectingTheOldName() {
        let (manager, original) = savedProject(titled: "Boat")
        manager.projectName = "Seagull"
        let landed = save(manager, to: original)
        XCTAssertEqual(manager.projectURL, landed,
                       "the save updates the only in-memory holder before its completion runs, so "
                       + "the gallery it hands to has already been told where the project is")

        // Exactly what ContentView does next: save to whatever `projectURL` now says.
        let second = save(manager, to: manager.projectURL ?? original)

        XCTAssertEqual(second.lastPathComponent, "Seagull.paintproj", "the second save stays put")
        XCTAssertEqual(packageNames(), ["Seagull.paintproj"],
                       "and no package reappears under the old name, got \(packageNames())")
        assertInkSurvived(at: second, "after a second save following a rename")
    }

    /// A small consequence worth pinning because it is the first time Recently Deleted reads
    /// correctly: `moveToTrash` names its entry from the *directory* stem, which since (57) is the
    /// title rather than whatever the project was called on the day it was created.
    func testADeletedProjectLandsInTheTrashUnderItsTitle() {
        let (manager, original) = savedProject(titled: "Boat")
        manager.projectName = "Seagull"
        let landed = save(manager, to: original)

        let trashed = ProjectBackupManager.moveToTrash(landed, tag: "deleted")

        XCTAssertTrue(trashed?.lastPathComponent.hasPrefix("Seagull__deleted__") == true,
                      "Recently Deleted names the project by its title, got "
                      + "\(trashed?.lastPathComponent ?? "nothing")")
    }
}
