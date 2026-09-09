import XCTest
import UIKit

/// **Where a project's files live, and that moving them loses nothing** — TODO (57) part 1.
///
/// The owner, 2026-09-08, browsing their own iPad: *"There is a json file for the layers im guessing
/// that contains the strokes. Why is this file under the images folder?"* So the per-cel JSON now
/// lives in `drawings/`, and every package written before that keeps working — which is the half that
/// needs pinning, because the failure mode is silent. A reader that cannot find a moved sidecar does
/// not throw; it falls through `decodeCel`'s `?? .empty` and the artist's ink is simply gone.
///
/// The suite is built around three questions:
///
///  1. **The new layout is actually on disk** — the drawing is under `drawings/` and there is no JSON
///     under `images/`, asserted against the bytes rather than against the model.
///  2. **The old layout still opens, with its ink** — a package mechanically reverted to the
///     pre-(57) shape loads with the *sample coordinates the artist drew*, not merely a non-nil
///     canvas. A vector layer always gets an empty `VectorCanvas` when its payload cannot be read
///     (`decodeCel`'s `if vector == nil, layerKind == .vector` arm), so `XCTAssertNotNil` here would
///     be green against total data loss.
///  3. **The migration is crash-safe at every step boundary** — each row of `tidy`'s own resume table
///     is left on disk deliberately and then both re-loaded and re-run, because "it is idempotent" is
///     a claim about the second run and nothing but a second run tests it.
///
/// `Services/ProjectPackageLayout.swift`, `ProjectStore.swift` and `ProjectBackupManager.swift` are
/// compiled directly into this bundle (see `BackupManagerLogicTests`' header for why
/// `@testable import` cannot be used), so every function below is the shipped one.
@MainActor
final class ProjectPackageLayoutLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-layout-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Fixtures

    /// The two sample coordinates the fixture stroke is drawn through. Named so the assertion that
    /// the ink survived a migration is about *these two points* rather than about a count.
    private static let inkStart = CGPoint(x: 12, y: 34)
    private static let inkEnd = CGPoint(x: 56, y: 78)

    /// A document with one vector cel carrying a real stroke and a real pose channel, so a save
    /// writes both a `drawing` and an `animation` sidecar.
    private func makeManager() -> CanvasManager {
        let manager = CanvasManager()
        manager.projectName = "Layout"
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
        // A pose channel, so the `animation` sidecar is written too — KEYFRAMES.md §3.5. Two keys,
        // because one key is not a channel anybody would author.
        let box = CGRect(x: 0, y: 0, width: 64, height: 64)
        manager.layers[vectorLayer].cels[0].transformTracks["cel"] = TransformTrack(keys: [
            TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
            TransformTrack.Key(frame: 8, pose: PoseQuad(restingIn: box.offsetBy(dx: 20, dy: 0)),
                               interpolation: .linear)
        ])
        return manager
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL,
                             file: StaticString = #filePath, line: UInt = #line) {
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Setup: the save should have landed a package at \(url.lastPathComponent)",
                      file: file, line: line)
    }

    /// A saved package, in this build's layout.
    private func savedProject(named name: String = "Layout") -> URL {
        let url = ProjectStore.createNewProjectURL(name: name)
        saveAndWait(makeManager(), to: url)
        return url
    }

    private func manifestJSON(at url: URL,
                              file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            XCTFail("the package at \(url.lastPathComponent) should carry a readable manifest.json",
                    file: file, line: line)
            return [:]
        }
        return json
    }

    /// Every cel entry in a package's manifest, flattened across layers — the JSON as it is on disk,
    /// which is the only way to assert what a *name* says rather than what the decoder makes of it.
    private func celEntries(at url: URL,
                            file: StaticString = #filePath, line: UInt = #line) -> [[String: Any]] {
        guard let layers = manifestJSON(at: url, file: file, line: line)["layers"] as? [[String: Any]] else {
            XCTFail("the manifest at \(url.lastPathComponent) should carry a layers array",
                    file: file, line: line)
            return []
        }
        return layers.flatMap { ($0["cels"] as? [[String: Any]]) ?? [] }
    }

    private func names(in directory: String, at url: URL) -> [String] {
        let dir = url.appendingPathComponent(directory, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    /// The three manifest keys the migration moves, paired with the role that owns each. One list so
    /// every fixture and assertion below walks the same three and none of them can quietly walk two.
    private static let movedFields: [(key: String, role: ProjectPackageLayout.Role)] = [
        ("vectorFileName", .drawing), ("animationFileName", .animation),
        ("interpolationFileName", .interpolation)
    ]

    /// **Turns a package this build wrote into one an older build would have written**: every JSON
    /// sidecar back under `images/` at its `_vector` / `_anim` / `_interp` name, the manifest naming
    /// it bare, and no `drawings/` directory at all.
    ///
    /// The `makeLegacyRasterPNGs` pattern from `ProjectSaveLogicTests`, and for its reason: starting
    /// from a real save and mechanically reverting it is how the fixture stays a *package this app
    /// once produced*, where hand-authoring old JSON would drift from it silently.
    @discardableResult
    private func makeLegacyLayout(at url: URL,
                                  file: StaticString = #filePath, line: UInt = #line) -> Int {
        let fm = FileManager.default
        var json = manifestJSON(at: url, file: file, line: line)
        guard var layers = json["layers"] as? [[String: Any]] else {
            XCTFail("fixture: the saved manifest should carry a layers array", file: file, line: line)
            return 0
        }
        let images = url.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: images, withIntermediateDirectories: true)
        var moved = 0
        for layerIndex in layers.indices {
            var cels = (layers[layerIndex]["cels"] as? [[String: Any]]) ?? []
            for celIndex in cels.indices {
                guard let idString = cels[celIndex]["id"] as? String,
                      let celID = UUID(uuidString: idString) else {
                    XCTFail("fixture: every saved cel entry should carry an id", file: file, line: line)
                    continue
                }
                for (key, role) in Self.movedFields {
                    guard let recorded = cels[celIndex][key] as? String, recorded.contains("/") else { continue }
                    let source = ProjectPackageLayout.resolve(recorded, in: url)
                    let legacy = ProjectPackageLayout.legacyName(for: role, cel: celID)
                    do {
                        try fm.moveItem(at: source, to: images.appendingPathComponent(legacy))
                    } catch {
                        XCTFail("fixture: \(recorded) should move back to images/\(legacy): \(error)",
                                file: file, line: line)
                        continue
                    }
                    cels[celIndex][key] = legacy
                    moved += 1
                }
            }
            layers[layerIndex]["cels"] = cels
        }
        json["layers"] = layers
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            XCTFail("fixture: the legacy manifest should re-encode", file: file, line: line)
            return moved
        }
        try? rewritten.write(to: url.appendingPathComponent("manifest.json"))
        try? fm.removeItem(at: url.appendingPathComponent(ProjectPackageLayout.Role.drawing.directory,
                                                          isDirectory: true))
        XCTAssertGreaterThan(moved, 0,
                             "fixture: the saved package should have had sidecars to push back under images/",
                             file: file, line: line)
        return moved
    }

    /// The ink, read back out of a loaded document — the two sample points the fixture drew.
    ///
    /// **Sample coordinates, not "a canvas exists".** A `.vector` layer whose payload could not be
    /// read still comes back with an empty `VectorCanvas`, so nil-checking the canvas is green
    /// against total loss of the drawing; and TODO (8) stores samples quantised, so the comparison is
    /// to within half a quantum rather than exact.
    private func assertInkSurvived(at url: URL, _ context: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("\(context): the package should load at all", file: file, line: line)
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
        let quantum = PackedSampleRun.quantum / 2
        XCTAssertEqual(stroke.samples[0].x, Self.inkStart.x, accuracy: quantum,
                       "\(context): the stroke's first sample x is where the artist put it", file: file, line: line)
        XCTAssertEqual(stroke.samples[0].y, Self.inkStart.y, accuracy: quantum,
                       "\(context): the stroke's first sample y is where the artist put it", file: file, line: line)
        XCTAssertEqual(stroke.samples[1].x, Self.inkEnd.x, accuracy: quantum,
                       "\(context): the stroke's last sample x is where the artist put it", file: file, line: line)
        XCTAssertEqual(stroke.samples[1].y, Self.inkEnd.y, accuracy: quantum,
                       "\(context): the stroke's last sample y is where the artist put it", file: file, line: line)

        // The pose channel is the other half of what a lost sidecar costs, and it is the half nothing
        // else in the suite would notice: `decodeCel`'s animation branch has no else arm, so a miss
        // leaves an empty map with no log line at all.
        let tracks = reloaded.layers.compactMap { $0.cels.first }.flatMap { $0.transformTracks.values }
        XCTAssertEqual(tracks.first?.keys.count, 2,
                       "\(context): the cel's pose channel should still carry both of its keys — a "
                       + "missing animation sidecar loads as an empty map and says nothing",
                       file: file, line: line)
    }

    // MARK: - (a) A fresh save puts the JSON where the owner asked for it

    func testAFreshSaveWritesTheDrawingUnderDrawingsAndNoJSONUnderImages() throws {
        let url = savedProject()

        let drawings = names(in: ProjectPackageLayout.Role.drawing.directory, at: url)
        // Matched against the cel's own id rather than by "has no dash" — a UUID is four dashes long,
        // which is exactly the kind of near-miss that makes a filename filter quietly wrong.
        let celID = try XCTUnwrap(celEntries(at: url).compactMap { $0["id"] as? String }.first,
                                  "the saved manifest should name a cel")
        XCTAssertTrue(drawings.contains("\(celID).json"),
                      "drawings/ holds the cel's drawing as <celID>.json, got \(drawings)")
        XCTAssertTrue(drawings.contains("\(celID)-animation.json"),
                      "drawings/ holds the cel's pose channels as <celID>-animation.json, got \(drawings)")

        XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }, [],
                       "no JSON is left under images/ — that is the owner's complaint, stated as an "
                       + "assertion about the bytes on disk")
    }

    /// And the manifest records the new address, which is the whole of the format version: a `/` in a
    /// field that already existed, rather than a new key or a number.
    func testTheManifestRecordsTheSidecarAsAPackageRelativePath() throws {
        let url = savedProject()
        let cels = celEntries(at: url)
        let drawing = try XCTUnwrap(cels.compactMap { $0["vectorFileName"] as? String }.first,
                                    "the saved manifest should name a vector payload")
        XCTAssertTrue(drawing.hasPrefix("drawings/"),
                      "the manifest records the drawing package-relative, got \(drawing)")
        let celID = try XCTUnwrap(cels.compactMap { $0["id"] as? String }.first)
        XCTAssertTrue(drawing.hasSuffix("\(celID).json") || drawing.contains(celID),
                      "the recorded name is still derived from the cel id, got \(drawing)")
        // Every PNG name is untouched by (57) — that is a decision, not an accident, so it is pinned.
        for cel in cels {
            let raster = try XCTUnwrap(cel["rasterFileName"] as? String)
            XCTAssertFalse(raster.contains("/"),
                           "PNG names stay bare — only the three JSON roles carry a path, got \(raster)")
        }
    }

    /// **The lazy-directory half of the sweep.** A pure-vector document — the owner's own — used to
    /// ship an empty `images/` beside its content, which is the next question they would have asked.
    func testAVectorOnlyDocumentWritesNoImagesDirectoryAtAll() {
        let url = savedProject()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("images", isDirectory: true).path),
            "nothing in this document is a pixel, so it gets no images/ — the fixture draws only "
            + "vector ink and never touches a raster tier")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("drawings", isDirectory: true).path),
            "and it does get the one directory it has content for")
    }

    /// The other direction, so the test above cannot pass by creating no directories at all.
    func testARasterDocumentStillGetsItsImagesDirectory() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let raster = manager.layers[0].cels[0].raster
        raster.beginStroke()
        raster.stampCircle(at: CGPoint(x: 20, y: 20), radius: 6, color: .red, alpha: 1, hardness: 1)
        raster.endStroke()
        let url = ProjectStore.createNewProjectURL(name: "Raster")
        saveAndWait(manager, to: url)

        XCTAssertTrue(names(in: "images", at: url).contains { $0.hasSuffix("_raster.png") },
                      "a drawn raster tier writes its PNG into images/, got \(names(in: "images", at: url))")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("drawings", isDirectory: true).path),
            "and a raster-only document gets no drawings/ — every content directory is lazy")
    }

    /// **The accepted one-way break, asserted so it cannot be un-noticed** — BUGS.md carries the
    /// sentence and the rule that comes with it.
    ///
    /// A build older than (57) resolves `vectorFileName` as `images/<name>`, with no awareness of a
    /// slash. This is that arithmetic, done here rather than left as prose: the path such a build
    /// would compute does not exist, so it falls through `decodeCel`'s `?? .empty` and the cel's ink
    /// loads blank. No scheme avoids it — the manifest field is one string, so it either names the old
    /// address (and the JSON has not left `images/`, which is the whole ask) or it names the new one.
    /// If anyone ever adds a compatibility shim, this test is what tells them it worked.
    func testAnOlderBuildJoiningTheNameToImagesFindsNothing() throws {
        let url = savedProject()
        let recorded = try XCTUnwrap(celEntries(at: url).compactMap { $0["vectorFileName"] as? String }.first)
        let asAnOldBuildWouldJoinIt = url.appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(recorded)

        XCTAssertFalse(FileManager.default.fileExists(atPath: asAnOldBuildWouldJoinIt.path),
                       "images/\(recorded) is what a pre-(57) build looks for, and it is not there — "
                       + "such a build opens this package with every drawing blank. Accepted, one-way, "
                       + "and the reason no worktree may install an older commit over a device that "
                       + "has run this one; the preupdate- clone in Backups/ is the way back")
        // And the address this build uses is the one that is actually there, so the break is about
        // the old resolver rather than about a file that failed to get written.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: ProjectPackageLayout.resolve(recorded, in: url).path),
            "the drawing itself is present at the address this build records")
    }

    // MARK: - (b) A package in the old layout still opens, with its ink

    func testAPackageInTheOldLayoutLoadsWithItsStrokesIntact() {
        let url = savedProject()
        makeLegacyLayout(at: url)

        // The premise, asserted before the fix is: the sidecars really are back under images/ and the
        // manifest really does name them bare. Without this the test below could be green against a
        // fixture that changed nothing.
        XCTAssertTrue(names(in: "images", at: url).contains { $0.hasSuffix("_vector.json") },
                      "Setup: the legacy fixture puts the drawing back under images/_vector.json")
        for cel in celEntries(at: url) {
            let drawing = cel["vectorFileName"] as? String
            XCTAssertEqual(drawing?.contains("/"), false,
                           "Setup: a legacy manifest names its sidecar bare, got \(drawing ?? "nil")")
        }

        assertInkSurvived(at: url, "a package in the pre-(57) layout")
    }

    /// And the validator agrees, which is the gate every save and the launch repair pass run through.
    func testAPackageInTheOldLayoutStillValidates() {
        let url = savedProject()
        makeLegacyLayout(at: url)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "a legacy package is intact, not damaged — calling it damaged would make "
                      + "repairCorruptedProjects restore over a perfectly good project")
    }

    // MARK: - (c) The migration, and its crash-resume table row by row

    func testTheMigrationMovesEverySidecarOutOfImagesAndRewritesTheManifest() {
        let url = savedProject()
        let pushedBack = makeLegacyLayout(at: url)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url),
                       "a legacy package is tidied")

        XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }, [],
                       "every JSON sidecar has left images/")
        XCTAssertEqual(names(in: "drawings", at: url).count, pushedBack,
                       "and all \(pushedBack) of them arrived in drawings/")
        for cel in celEntries(at: url) {
            for (key, _) in Self.movedFields {
                guard let recorded = cel[key] as? String else { continue }
                XCTAssertTrue(recorded.hasPrefix("drawings/"),
                              "the manifest's \(key) now names the new address, got \(recorded)")
                XCTAssertTrue(FileManager.default.fileExists(
                    atPath: ProjectPackageLayout.resolve(recorded, in: url).path),
                    "and \(recorded) is actually there")
            }
        }
        assertInkSurvived(at: url, "a migrated package")
    }

    /// **Row 1 of the resume table: killed after a sidecar moved, before the manifest was rewritten.**
    /// The file is at `drawings/` and the manifest still names it bare — which is the state the
    /// resolver's whole probe order exists for.
    func testAMigrationKilledBeforeTheManifestRewriteStillLoadsWholeAndIsFinishedNextRun() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)

        // Move the files exactly as `tidy` would and leave the manifest alone — the interruption.
        let images = url.appendingPathComponent("images", isDirectory: true)
        let drawings = url.appendingPathComponent("drawings", isDirectory: true)
        try FileManager.default.createDirectory(at: drawings, withIntermediateDirectories: true)
        var movedByHand = 0
        for cel in celEntries(at: url) {
            let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
            for (key, role) in Self.movedFields {
                guard let recorded = cel[key] as? String, !recorded.contains("/") else { continue }
                try FileManager.default.moveItem(
                    at: images.appendingPathComponent(recorded),
                    to: ProjectPackageLayout.resolve(ProjectPackageLayout.recordedName(for: role, cel: celID),
                                                     in: url))
                movedByHand += 1
            }
        }
        XCTAssertGreaterThan(movedByHand, 0, "Setup: the interruption should have moved something")

        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "a package caught between the move and the manifest rewrite is intact, not "
                      + "damaged — if the validator said otherwise, repairCorruptedProjects would "
                      + "restore over it and tidy's own step-0 guard would refuse to finish the job")
        assertInkSurvived(at: url, "a package caught between the move and the manifest rewrite")

        // The next launch finishes it: nothing left to move, so the pass reports nothing to do, and
        // the package is still whole either way.
        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .unchanged,
                       "the files are already at their new address, so a re-run has nothing to move")
        assertInkSurvived(at: url, "the same package after the pass re-ran")
    }

    /// **Row 2: killed between two moves** — some sidecars moved, some still under `images/`, the
    /// manifest naming the old address for all of them. Every file resolves, and the next run moves
    /// the rest.
    func testAMigrationKilledBetweenTwoMovesIsFinishedByTheNextRun() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)

        // Move exactly one sidecar by hand, then stop.
        let cel = try XCTUnwrap(celEntries(at: url).first { $0["vectorFileName"] is String })
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
        let bare = try XCTUnwrap(cel["vectorFileName"] as? String)
        let drawings = url.appendingPathComponent("drawings", isDirectory: true)
        try FileManager.default.createDirectory(at: drawings, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: url.appendingPathComponent("images", isDirectory: true).appendingPathComponent(bare),
            to: ProjectPackageLayout.resolve(ProjectPackageLayout.recordedName(for: .drawing, cel: celID),
                                             in: url))
        XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }.count, 1,
                       "Setup: one sidecar moved and one is still under images/")

        assertInkSurvived(at: url, "a package split across both addresses")

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url),
                       "the next run finishes what is left")
        XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }, [],
                       "and images/ is clear of JSON afterwards")
        assertInkSurvived(at: url, "the finished package")
    }

    /// **Row 4: a third run changes nothing.** Idempotence is a claim about the second and third
    /// runs, and nothing but running it again tests it.
    func testTidyIsIdempotentAndAFullyTidyPackageIsUnchanged() {
        let url = savedProject()
        makeLegacyLayout(at: url)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .tidied(url), "the first run migrates")
        let afterFirst = manifestJSON(at: url)
        let namesAfterFirst = names(in: "drawings", at: url)

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .unchanged, "the second run has nothing to do")
        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .unchanged, "and neither does the third")
        XCTAssertEqual(names(in: "drawings", at: url), namesAfterFirst,
                       "drawings/ holds exactly what the first run put there")
        XCTAssertEqual(NSDictionary(dictionary: manifestJSON(at: url)), NSDictionary(dictionary: afterFirst),
                       "and the manifest is byte-for-byte the one the first run wrote")
        assertInkSurvived(at: url, "a package tidied three times")
    }

    /// **A sidecar at both addresses is left entirely alone.** A rename cannot produce that state, so
    /// something outside this flow wrote one of them, and the conservative answer is to touch
    /// neither — not to move, not to delete, not to rewrite the manifest.
    func testASidecarPresentAtBothAddressesIsNotTouchedAtEither() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)

        let cel = try XCTUnwrap(celEntries(at: url).first { $0["vectorFileName"] is String })
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
        let bare = try XCTUnwrap(cel["vectorFileName"] as? String)
        let legacyURL = url.appendingPathComponent("images", isDirectory: true).appendingPathComponent(bare)
        let newURL = ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .drawing, cel: celID), in: url)
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let intruder = Data("{\"elements\":[]}".utf8)
        try intruder.write(to: newURL)
        let legacyBytes = try Data(contentsOf: legacyURL)

        ProjectPackageLayout.tidy(packageAt: url)

        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytes,
                       "the file at the old address is byte-for-byte what it was")
        XCTAssertEqual(try Data(contentsOf: newURL), intruder,
                       "and whatever was at the new address is byte-for-byte what it was")
        XCTAssertEqual(celEntries(at: url).compactMap { $0["vectorFileName"] as? String }.first, bare,
                       "and the manifest still names the old address, because that is the one that "
                       + "holds the drawing this package was saved with")
    }

    /// **The compare-and-swap, which is the one step in the migration that can destroy data.** A save
    /// landing a whole new package at this path while the sidecars were being moved leaves a manifest
    /// that is already in the new layout; writing our stale bytes over it would lose the artist's last
    /// edits.
    /// **The staleness has to come from the caller, or this test measures nothing.** The first
    /// version of it changed the manifest and then called `tidy` — but `tidy` reads the manifest at
    /// the instant it is called, so the compare-and-swap was handed two copies of the same value and
    /// the test passed with the guard deleted. A mutation of that one line is what found it. So the
    /// rewrite is driven directly, with bytes that really are the ones a pass read *before* the save
    /// landed.
    func testAManifestThatChangedUnderTheMigrationIsNotOverwritten() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)
        let manifestURL = url.appendingPathComponent("manifest.json")

        // What the pass read when it started, and the rewrite it computed from it.
        let stale = try Data(contentsOf: manifestURL)
        let bare = try XCTUnwrap(celEntries(at: url).compactMap { $0["vectorFileName"] as? String }.first)
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(
            celEntries(at: url).first { $0["vectorFileName"] is String }?["id"] as? String)))
        let rewrites = [(old: bare, new: ProjectPackageLayout.recordedName(for: .drawing, cel: celID))]

        // A save lands a whole new package at this path while the sidecars are being moved. Its
        // manifest is already in the new layout and carries edits the pass has never seen.
        var json = manifestJSON(at: url)
        json["name"] = "Renamed By A Save"
        let fresh = try JSONSerialization.data(withJSONObject: json)
        try fresh.write(to: manifestURL)
        XCTAssertNotEqual(fresh, stale,
                          "Setup: the save really did change the manifest under the migration")

        ProjectPackageLayout.rewriteManifest(at: manifestURL, in: url,
                                             originalBytes: stale, rewrites: rewrites)

        XCTAssertEqual(try Data(contentsOf: manifestURL), fresh,
                       "the save's manifest is byte-for-byte the one on disk — the migration abandons "
                       + "its rewrite rather than writing bytes it read before the save landed, which "
                       + "is the only step in this pass that can destroy the artist's last edits")
        XCTAssertEqual(manifestJSON(at: url)["name"] as? String, "Renamed By A Save",
                       "and the edit the save carried is still there")
    }

    /// The other direction, so the test above cannot pass by a rewrite that never does anything: with
    /// the bytes it was given still on disk, the surgery lands.
    func testTheRewriteCommitsWhenTheManifestIsStillTheOneThePassRead() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)
        let manifestURL = url.appendingPathComponent("manifest.json")
        let cel = try XCTUnwrap(celEntries(at: url).first { $0["vectorFileName"] is String })
        let celID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(cel["id"] as? String)))
        let bare = try XCTUnwrap(cel["vectorFileName"] as? String)
        let relative = ProjectPackageLayout.recordedName(for: .drawing, cel: celID)

        // Move the file as `tidy` would, so the rewritten manifest names something that is there.
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("drawings", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: url.appendingPathComponent("images", isDirectory: true).appendingPathComponent(bare),
            to: ProjectPackageLayout.resolve(relative, in: url))

        ProjectPackageLayout.rewriteManifest(at: manifestURL, in: url,
                                             originalBytes: try Data(contentsOf: manifestURL),
                                             rewrites: [(old: bare, new: relative)])

        XCTAssertEqual(celEntries(at: url).compactMap { $0["vectorFileName"] as? String }.first, relative,
                       "the manifest names the new address")
        assertInkSurvived(at: url, "a package whose manifest the rewrite committed")
    }

    /// A package the manifest cannot be read from is the repair pass's business, and `tidy` must not
    /// touch it — it has no title, no cel ids and no way to know what any file on disk is.
    func testTidySkipsADamagedPackageWithoutTouchingIt() throws {
        let url = savedProject()
        makeLegacyLayout(at: url)
        let before = names(in: "images", at: url)
        try Data("corrupted".utf8).write(to: url.appendingPathComponent("manifest.json"))

        XCTAssertEqual(ProjectPackageLayout.tidy(packageAt: url), .skippedDamaged,
                       "a package whose manifest will not decode is skipped")
        XCTAssertEqual(names(in: "images", at: url), before,
                       "and nothing under images/ moved")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: url.appendingPathComponent("drawings", isDirectory: true).path),
            "not even the destination directory is created")
    }

    /// The whole-library pass, which is what actually runs at launch.
    func testTheLaunchPassTidiesEveryProjectAndReportsWhatItDid() {
        let first = savedProject(named: "One")
        let second = savedProject(named: "Two")
        makeLegacyLayout(at: first)
        makeLegacyLayout(at: second)
        let alreadyTidy = savedProject(named: "Three")

        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertEqual(Set(report.tidied), ["One.paintproj", "Two.paintproj"],
                       "both legacy packages were tidied, got \(report.tidied)")
        XCTAssertEqual(report.unchanged, 1, "and the one already in the new layout was left alone")
        XCTAssertEqual(report.skippedDamaged, 0, "nothing was damaged")
        XCTAssertGreaterThan(report.movedFiles, 0, "the pass reports how many sidecars it moved")
        XCTAssertTrue(report.duplicateProjectIDs.isEmpty,
                      "three distinct projects carry three distinct manifest ids")
        for url in [first, second, alreadyTidy] {
            XCTAssertEqual(names(in: "images", at: url).filter { $0.hasSuffix(".json") }, [],
                           "\(url.lastPathComponent) has no JSON under images/ afterwards")
            assertInkSurvived(at: url, url.lastPathComponent)
        }
    }

    /// The backstop the reviewers asked for: two packages sharing one manifest id make the gallery's
    /// `ForEach` draw two rows with one identity, and one of them may simply never appear. Nothing in
    /// this item can produce that shape — it renames no package directory — but the walk is already
    /// there and the check is one dictionary insert.
    func testTheLaunchPassNoticesTwoPackagesSharingOneManifestID() throws {
        let original = savedProject(named: "Original")
        let twin = ProjectBackupManager.projectsDirectory.appendingPathComponent("Twin.paintproj")
        XCTAssertTrue(ProjectBackupManager.cloneItem(at: original, to: twin),
                      "Setup: the fork is modelled by cloning a package under a second name")

        let report = ProjectPackageLayout.tidyEveryProject()

        XCTAssertEqual(report.duplicateProjectIDs.count, 1,
                       "the pass names the id two packages share rather than letting the gallery "
                       + "silently drop one of the rows forever")
    }

    // MARK: - The resolver's probe order, stated directly

    /// **Probe the address the migration moves *from* first, and the address it moves *to* second.**
    /// That order is the whole race proof: `tidy` only ever moves old→new, `rename(2)` is atomic, so a
    /// miss at `images/` proves the move completed and the second probe hits. Asserted here as a
    /// property of the function, because every caller depends on it and none of them states it.
    func testTheResolverProbesTheOldAddressFirstThenTheNew() throws {
        let fm = FileManager.default
        let package = root.appendingPathComponent("Probe.paintproj", isDirectory: true)
        let cel = UUID()
        let bare = ProjectPackageLayout.legacyName(for: .drawing, cel: cel)
        let images = package.appendingPathComponent("images", isDirectory: true)
        let drawings = package.appendingPathComponent("drawings", isDirectory: true)
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try fm.createDirectory(at: drawings, withIntermediateDirectories: true)

        // Neither address occupied: the answer is the *old* one, so a caller's "missing" diagnostics
        // name where a legacy manifest says the file should be.
        XCTAssertEqual(ProjectPackageLayout.existingURL(named: bare, role: .drawing, cel: cel, in: package),
                       images.appendingPathComponent(bare),
                       "with the file nowhere, a bare moved name resolves to its old address")

        // Only the new address occupied — the post-migration, pre-manifest-rewrite state.
        let moved = ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .drawing, cel: cel), in: package)
        try Data("new".utf8).write(to: moved)
        XCTAssertEqual(ProjectPackageLayout.existingURL(named: bare, role: .drawing, cel: cel, in: package),
                       moved, "a miss at images/ falls through to drawings/")

        // Both occupied — impossible from a rename, and the old one wins, which is what makes the
        // resolver agree with `tidy`'s refusal to touch either.
        try Data("old".utf8).write(to: images.appendingPathComponent(bare))
        XCTAssertEqual(ProjectPackageLayout.existingURL(named: bare, role: .drawing, cel: cel, in: package),
                       images.appendingPathComponent(bare),
                       "the address the migration moves from is probed first")

        // A slashed name is package-relative and has no alternate at all.
        let slashed = ProjectPackageLayout.recordedName(for: .animation, cel: cel)
        XCTAssertEqual(ProjectPackageLayout.existingURL(named: slashed, role: .animation, cel: cel, in: package),
                       ProjectPackageLayout.resolve(slashed, in: package),
                       "a slashed name is taken at its word")

        // A video: the current address first, then the one an old package used, because nothing
        // migrates a clip — its name lives inside the payload, not the manifest.
        let clip = "scene.mp4"
        try Data("clip".utf8).write(to: images.appendingPathComponent(clip))
        XCTAssertEqual(ProjectPackageLayout.existingURL(named: clip, role: .video, in: package),
                       images.appendingPathComponent(clip),
                       "a clip an older package left in images/ still resolves")
        let videos = package.appendingPathComponent("videos", isDirectory: true)
        try fm.createDirectory(at: videos, withIntermediateDirectories: true)
        try Data("clip".utf8).write(to: videos.appendingPathComponent(clip))
        XCTAssertEqual(ProjectPackageLayout.existingURL(named: clip, role: .video, in: package),
                       videos.appendingPathComponent(clip),
                       "and videos/ wins once the clip is there, because that is the common case")
    }

    // MARK: - The stem a title produces

    /// The first-save naming defect, stated as the cases that used to reach the filesystem verbatim.
    func testTheStemNeverProducesAPathAFolderNameCannotBe() {
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "Boat/Race"), "Boat Race",
                       "a separator in a title used to create a real subfolder and file the project inside it")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "10:30 take"), "10 30 take",
                       "a colon is replaced for sanitizedFolderName's reason")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "...hidden"), "hidden",
                       "every leading dot is stripped, not just the first — one left behind is a "
                       + "folder invisible in Files, which is where the owner found this item")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "Scene."), "Scene",
                       "and a trailing dot goes too")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "   "), "Untitled",
                       "a title of nothing still has to name a folder")
        XCTAssertEqual(ProjectPackageName.stem(forTitle: "/"), "Untitled",
                       "and so does one that sanitises down to nothing")
    }

    /// **Truncation is by UTF-8 bytes, not by `Character` count**, which is the bound the filesystem
    /// actually enforces: sixty ZWJ emoji `Character`s are many hundreds of bytes, and the trash name
    /// appends about forty-five more to whatever this returns.
    func testTheStemIsBoundedInBytesAsWellAsInCharacters() {
        let long = String(repeating: "a", count: 400)
        let plain = ProjectPackageName.stem(forTitle: long)
        XCTAssertEqual(plain.count, ProjectPackageName.maximumStemCharacters,
                       "a plain long title is cut at the character cap")

        let emoji = String(repeating: "👨‍👩‍👧‍👦", count: 60)
        let cut = ProjectPackageName.stem(forTitle: emoji)
        XCTAssertLessThanOrEqual(cut.utf8.count, ProjectPackageName.maximumStemBytes,
                                 "sixty family emoji are \(emoji.utf8.count) bytes, and the stem has "
                                 + "to fit a path component with room for Trash's own suffix")
        XCTAssertFalse(cut.isEmpty, "and it is not cut to nothing")
        XCTAssertEqual(cut, String(cut.prefix(cut.count)),
                       "the cut lands on a Character boundary, never mid-sequence")
    }

    /// The defect end to end: the title reaches the filesystem through `createNewProjectURL`, and it
    /// must not be able to name a directory outside the folder it was given.
    func testANewProjectsFirstSaveCannotCreateAStraySubfolder() {
        let url = ProjectStore.createNewProjectURL(name: "Boat/Race")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       ProjectBackupManager.projectsDirectory.standardizedFileURL,
                       "the package lands directly in Projects/, not inside a folder the title invented")
        XCTAssertEqual(url.lastPathComponent, "Boat Race.paintproj",
                       "and it is named for the sanitised title")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ProjectBackupManager.projectsDirectory.appendingPathComponent("Boat").path),
            "no stray 'Boat' directory is created — a project filed there could never be moved back, "
            + "because a rename never moves a project between folders")
    }
}
