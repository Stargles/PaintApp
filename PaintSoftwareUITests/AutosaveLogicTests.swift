import XCTest
import UIKit

/// TODO (76): the autosave's clock, and the incremental save it fires — `ProjectStore.PackageLedger`.
///
/// The clock tests are pure. The store tests save a real package twice and read the counters and
/// the bytes, because what an incremental save must never do is write different bytes for a cel
/// nobody touched — and the way to know is to compare the file it cloned with the file it would
/// have encoded.
@MainActor
final class AutosaveLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autosave-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - The clock

    func testAnEditIsDueAfterTheSettleAndNotBefore() {
        var clock = AutosaveClock(settle: 2.5, ceiling: 30)
        XCTAssertNil(clock.dueAt, "Nothing edited, nothing due")
        XCTAssertFalse(clock.hasUnsavedEdits)

        clock.noteEdit(at: 100)
        XCTAssertEqual(clock.dueAt, 102.5)
        XCTAssertTrue(clock.hasUnsavedEdits)
        XCTAssertFalse(clock.fire(at: 102.4, held: false), "Not due yet")
        XCTAssertTrue(clock.fire(at: 102.5, held: false), "Due exactly at the settle")
        XCTAssertNil(clock.dueAt, "A fire forgets the edits it carries")
        XCTAssertFalse(clock.fire(at: 200, held: false), "Nothing left to save")
    }

    func testEveryEditPushesTheSettleBackAndNoneOfThemMovesTheCeiling() {
        var clock = AutosaveClock(settle: 2.5, ceiling: 30)
        clock.noteEdit(at: 0)
        clock.noteEdit(at: 2)
        XCTAssertEqual(clock.dueAt, 4.5, "The settle runs from the last edit")

        // A stroke every two seconds for half a minute never lets the settle expire — and the
        // ceiling is what saves the session anyway.
        for t in stride(from: 4.0, through: 28, by: 2) { clock.noteEdit(at: t) }
        XCTAssertEqual(clock.dueAt, 30, "The ceiling runs from the first unsaved edit")
        clock.noteEdit(at: 29.9)
        XCTAssertEqual(clock.dueAt, 30, "A late edit does not push the ceiling")
        XCTAssertFalse(clock.fire(at: 29.99, held: false))
        XCTAssertTrue(clock.fire(at: 30, held: false))

        // After the ceiling fires, the next edit starts a fresh ceiling from itself.
        clock.noteEdit(at: 31)
        XCTAssertEqual(clock.dueAt, 33.5)
    }

    func testAHeldFireKeepsTheDueTimeSoTheReleaseLetsItThrough() {
        var clock = AutosaveClock(settle: 2.5, ceiling: 30)
        clock.noteEdit(at: 0)
        XCTAssertFalse(clock.fire(at: 10, held: true), "Mid-stroke, mid-drag, playing: not now")
        XCTAssertEqual(clock.dueAt, 2.5, "The hold changes nothing about what is owed")
        XCTAssertTrue(clock.hasUnsavedEdits)
        XCTAssertTrue(clock.fire(at: 10.1, held: false), "The moment the hold lifts, it is due")
    }

    func testASaveForAnotherReasonClearsWhatIsOwed() {
        var clock = AutosaveClock(settle: 2.5, ceiling: 30)
        clock.noteEdit(at: 0)
        clock.noteSaved()
        XCTAssertNil(clock.dueAt, "The artist's own exit save carried everything")
        XCTAssertFalse(clock.fire(at: 100, held: false))
    }

    func testAnEditNotedAfterAFireIsOwedToTheNextSave() {
        var clock = AutosaveClock(settle: 2.5, ceiling: 30)
        clock.noteEdit(at: 0)
        XCTAssertTrue(clock.fire(at: 5, held: false))
        // The save fired at 5 is still writing when this edit lands: it is not in that snapshot,
        // and the clock has already forgotten the edits that were — so this one is new.
        clock.noteEdit(at: 5.1)
        XCTAssertEqual(clock.dueAt, 7.6, "Carried by the next save, on its own settle")
    }

    // MARK: - The incremental save

    /// Two raster cels with ink and one vector cel — three pixel tiers the ledger can tell apart.
    private func makeManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.projectName = "Autosave"
        for layerIndex in 0..<2 {
            stamp(manager, layerIndex: layerIndex, at: CGPoint(x: 20 + layerIndex * 10, y: 24))
        }
        manager.addVectorLayer()
        manager.layers[2].cels[0].vector?.addStroke(
            VectorStroke(brush: manager.selectedBrush,
                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                         size: 8, opacity: 1,
                         samples: [VectorSample(x: 10, y: 10, pressure: 1),
                                   VectorSample(x: 40, y: 40, pressure: 1)]))
        return manager
    }

    private func stamp(_ manager: CanvasManager, layerIndex: Int, at point: CGPoint) {
        let raster = manager.layers[layerIndex].cels[0].raster
        raster.beginStroke()
        raster.stampCircle(at: point, radius: 6, color: .red, alpha: 1, hardness: 1)
        raster.endStroke()
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL, intent: SaveIntent = .artist) {
        let finished = expectation(description: "ProjectStore.save completion")
        let decision = ProjectStore.save(manager, to: url, intent: intent) { finished.fulfill() }
        if decision == .ask { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    private func rasterBytes(of manager: CanvasManager, layerIndex: Int, in package: URL) -> Data? {
        let cel = manager.layers[layerIndex].cels[0]
        return try? Data(contentsOf: package.appendingPathComponent("images")
                             .appendingPathComponent("\(cel.id.uuidString)_raster.png"))
    }

    private func drawingBytes(of manager: CanvasManager, layerIndex: Int, in package: URL) -> Data? {
        let cel = manager.layers[layerIndex].cels[0]
        return try? Data(contentsOf: ProjectPackageLayout.resolve(
            ProjectPackageLayout.recordedName(for: .drawing, cel: cel.id), in: package))
    }

    private func profile(file: StaticString = #filePath, line: UInt = #line) -> ProjectStore.SaveProfile? {
        let profile = ProjectStore.lastSaveProfile
        XCTAssertNotNil(profile, "Every save publishes a profile", file: file, line: line)
        return profile
    }

    func testAnUnchangedCelIsClonedNotReEncodedAndItsBytesAreTheBytesItHad() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")

        saveAndWait(manager, to: url)
        let first = try XCTUnwrap(profile())
        XCTAssertEqual(first.pngsEncoded, 2, "The first save of a session encodes every raster cel")
        XCTAssertEqual(first.pngsReused, 0)
        XCTAssertEqual(manager.packageLedger.landedAt, url, "The ledger names the package it described")
        let layer0Before = try XCTUnwrap(rasterBytes(of: manager, layerIndex: 0, in: url))
        let layer1Before = try XCTUnwrap(rasterBytes(of: manager, layerIndex: 1, in: url))
        let drawingBefore = try XCTUnwrap(drawingBytes(of: manager, layerIndex: 2, in: url))

        // One cel changes; two are exactly what they were.
        stamp(manager, layerIndex: 0, at: CGPoint(x: 44, y: 44))
        saveAndWait(manager, to: url)
        let second = try XCTUnwrap(profile())
        XCTAssertEqual(second.pngsEncoded, 1, "Only the cel whose texture version moved is encoded")
        XCTAssertEqual(second.pngsReused, 1, "The other raster cel is cloned out of the live package")
        XCTAssertFalse(second.encodedOnMainThread)

        XCTAssertNotEqual(rasterBytes(of: manager, layerIndex: 0, in: url), layer0Before,
                          "The edited cel's PNG carries the new dot")
        XCTAssertEqual(rasterBytes(of: manager, layerIndex: 1, in: url), layer1Before,
                       "The cloned cel's PNG is byte for byte the file the previous save wrote")
        XCTAssertEqual(drawingBytes(of: manager, layerIndex: 2, in: url), drawingBefore,
                       "The vector cel's display list was cloned too")

        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "An incrementally written package names only files it contains")
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let dot = CanvasFixture.rgbaBytes(try XCTUnwrap(reloaded.layers[0].cels[0].raster.renderToUIImage().cgImage))
        XCTAssertNotNil(dot)
        XCTAssertGreaterThan(dot?[(44 * 64 + 44) * 4 + 3] ?? 0, 0,
                             "The reloaded document has the second dot at (44, 44) on layer 0")
        XCTAssertEqual(reloaded.layers[2].cels[0].vector?.elements.count, 1,
                       "The reloaded vector cel has its stroke")
    }

    func testTheSecondSaveOfAnUntouchedDocumentEncodesNothing() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        saveAndWait(manager, to: url)
        saveAndWait(manager, to: url)
        let profile = try XCTUnwrap(profile())
        XCTAssertEqual(profile.pngsEncoded, 0, "Nothing moved, nothing is encoded")
        XCTAssertEqual(profile.pngsReused, 2)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
        XCTAssertNotNil(ProjectStore.load(from: url))
    }

    func testAReopenedDocumentStartsItsSessionWithAFullWrite() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        saveAndWait(manager, to: url)
        saveAndWait(manager, to: url)
        XCTAssertEqual(try XCTUnwrap(profile()).pngsReused, 2, "Setup: the session is incremental by now")

        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertNil(reopened.packageLedger.landedAt, "A new CanvasManager is a new ledger")
        saveAndWait(reopened, to: url)
        let profile = try XCTUnwrap(profile())
        XCTAssertEqual(profile.pngsEncoded, 2, "New textures, no stamps to match: everything encodes")
        XCTAssertEqual(profile.pngsReused, 0)
    }

    func testACelWhoseFileHasGoneFromTheLivePackageIsReEncodedRatherThanTrusted() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        saveAndWait(manager, to: url)

        // The ledger still says layer 1's PNG is on disk. It is not.
        let cel = manager.layers[1].cels[0]
        let missing = url.appendingPathComponent("images").appendingPathComponent("\(cel.id.uuidString)_raster.png")
        try FileManager.default.removeItem(at: missing)

        saveAndWait(manager, to: url)
        let profile = try XCTUnwrap(profile())
        XCTAssertEqual(profile.pngsEncoded, 1, "The cel that would not clone falls back to the encode")
        XCTAssertEqual(profile.pngsReused, 1, "The cel that would still clones")
        XCTAssertTrue(FileManager.default.fileExists(atPath: missing.path), "…and the file is back")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
    }

    func testAnEditMadeWhileASaveIsInFlightIsCarriedByTheNextSave() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        saveAndWait(manager, to: url)

        // The snapshot is synchronous and the write is not: this dot lands after the snapshot of
        // the save below and before its landing, which is exactly "during a save".
        let landed = expectation(description: "save in flight lands")
        ProjectStore.save(manager, to: url) { landed.fulfill() }
        stamp(manager, layerIndex: 1, at: CGPoint(x: 50, y: 12))
        wait(for: [landed], timeout: 30)
        let during = try XCTUnwrap(profile())
        XCTAssertEqual(during.pngsEncoded, 0, "That save carried the document as it was when it started")

        saveAndWait(manager, to: url)
        let after = try XCTUnwrap(profile())
        XCTAssertEqual(after.pngsEncoded, 1, "The next save encodes exactly the cel edited in flight")
        XCTAssertEqual(after.pngsReused, 1)
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let bytes = CanvasFixture.rgbaBytes(try XCTUnwrap(reloaded.layers[1].cels[0].raster.renderToUIImage().cgImage))
        XCTAssertGreaterThan(bytes?[(12 * 64 + 50) * 4 + 3] ?? 0, 0, "The in-flight dot is on disk now")
    }

    func testTheFirstSaveOfASessionMintsARestorePointAndLaterOnesRefreshTheRollingSlot() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        func slots() -> (auto: Int, rolling: Bool) {
            let backups = ProjectBackupManager.listBackups(forProjectAt: url)
            return (backups.filter { $0.label == "Before save" }.count,
                    backups.contains { $0.label == "Before last save" && $0.isValid })
        }

        saveAndWait(manager, to: url)      // nothing on disk yet: nothing to stash
        XCTAssertEqual(slots().auto, 0)
        XCTAssertFalse(slots().rolling)

        // Reopen: a new session, whose first save stashes what it found as "Before save".
        let session = try XCTUnwrap(ProjectStore.load(from: url))
        stamp(session, layerIndex: 0, at: CGPoint(x: 30, y: 30))
        saveAndWait(session, to: url)
        XCTAssertEqual(slots().auto, 1, "The session's opening state is a rotated restore point")
        XCTAssertFalse(slots().rolling)

        // Every later save in the session — the autosave's case — replaces one rolling slot.
        stamp(session, layerIndex: 0, at: CGPoint(x: 10, y: 50))
        saveAndWait(session, to: url)
        stamp(session, layerIndex: 1, at: CGPoint(x: 10, y: 50))
        saveAndWait(session, to: url)
        XCTAssertEqual(slots().auto, 1, "Thirty-second autosaves do not rotate the opening state away")
        XCTAssertTrue(slots().rolling, "…and the state before the last save is one valid restore point")
    }

    func testAVersionSlotWriteNeitherReusesNorRecords() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        saveAndWait(manager, to: url)
        XCTAssertEqual(manager.packageLedger.landedAt, url)

        // A damaged, unanswered document: an automatic save goes to the version history, and must
        // not clone out of the live package it is leaving alone — nor claim to describe it.
        var damage = ProjectLoadDamage()
        damage.add(ProjectLoadDamage.LayerDamage(layerName: "Ink", brushStrokes: 1))
        manager.loadDamage = damage
        saveAndWait(manager, to: url, intent: .automatic)
        let profile = try XCTUnwrap(profile())
        XCTAssertEqual(profile.pngsEncoded, 2, "A version slot is written whole")
        XCTAssertEqual(profile.pngsReused, 0)
        XCTAssertTrue(ProjectBackupManager.listBackups(forProjectAt: url).contains { $0.label == "Unsaved changes" })
    }
}
