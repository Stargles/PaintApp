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

        clock.noteDeferred(at: 10)
        XCTAssertEqual(clock.dueAt, 12.5, "A failed attempt waits one settle instead of spinning on the expired due time")
        XCTAssertTrue(clock.hasUnsavedEdits, "The failed snapshot and the newer edit are still owed")
        XCTAssertFalse(clock.fire(at: 12.49, held: false))
        clock.noteEdit(at: 12)
        XCTAssertEqual(clock.dueAt, 14.5, "An edit after refusal still gets its ordinary settle")
        for t in stride(from: 14.0, through: 38, by: 2) { clock.noteEdit(at: t) }
        XCTAssertEqual(clock.dueAt, 40, "Further edits cannot postpone the deferred window beyond the existing ceiling")
        XCTAssertTrue(clock.fire(at: 40, held: false))
    }

    func testDeferredFeedbackBelongsToTheFollowedDocumentAndEveryAttemptFinishes() {
        let driver = AutosaveDriver()
        defer { driver.stop() }
        let first = CanvasFixture.manager(layerCount: 1)
        let second = CanvasFixture.manager(layerCount: 1)
        driver.follow(first, isHeld: { true }, save: {})
        driver.saveStarted()
        let beforeDeferral = Date.timeIntervalSinceReferenceDate
        driver.saveDeferred(for: first)
        let afterDeferral = Date.timeIntervalSinceReferenceDate
        XCTAssertGreaterThanOrEqual(driver.clock.dueAt ?? 0, beforeDeferral + 2.5,
                                    "A deferred attempt re-arms the existing settle window")
        XCTAssertLessThanOrEqual(driver.clock.dueAt ?? .infinity, afterDeferral + 2.5)
        driver.saveFinished(for: first)
        XCTAssertEqual(driver.savesInFlight, 0, "A synchronously deferred attempt is balanced once")

        driver.saveStarted()
        driver.follow(second, isHeld: { true }, save: {})
        driver.saveDeferred(for: first)
        XCTAssertNil(driver.clock.dueAt, "An old failed attempt cannot create work for the newly opened document")
        XCTAssertTrue(second.addLayer(), "PREMISE: a real edit in the new document is owed independently")
        let secondDue = driver.clock.dueAt
        driver.saveFinished(for: first)
        XCTAssertEqual(driver.savesInFlight, 0, "An old completion still releases its in-flight hold")
        XCTAssertEqual(driver.clock.dueAt, secondDue, "Finishing an old document does not clear or move a new edit")
        driver.saveStarted()
        XCTAssertTrue(second.addLayer(), "PREMISE: the current document can be edited during its own save")
        let editedDuringSave = driver.clock.dueAt
        driver.saveFinished(for: second)
        XCTAssertEqual(driver.clock.dueAt, editedDuringSave, "A successful completion leaves edits made during the write owed")
        driver.stop()
        driver.saveDeferred(for: second)
        XCTAssertNil(driver.clock.dueAt, "Closing a document drops its retry eligibility")
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
            VectorStroke(brush: manager.toolProfiles.brush.preset,
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
        let decision = ProjectStore.save(manager, to: url, intent: intent) { _ in finished.fulfill() }
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
        let dot = CanvasFixture.rgbaBytes(try XCTUnwrap(try reloaded.layers[0].cels[0].raster.renderToUIImage().get().cgImage))
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

    func testAReopenedDocumentWritesProtectedSourcesAndStartsANewLedger() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        let originalPixels = try (0..<2).map { index in
            try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(
                try manager.layers[index].cels[0].raster.renderToUIImage().get().cgImage)))
        }
        saveAndWait(manager, to: url)
        let originalPNGs = try (0..<2).map { try XCTUnwrap(rasterBytes(of: manager, layerIndex: $0, in: url)) }
        saveAndWait(manager, to: url)
        XCTAssertEqual(try XCTUnwrap(profile()).pngsReused, 2, "Setup: the session is incremental by now")

        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertNil(reopened.packageLedger.landedAt, "A new CanvasManager is a new ledger")
        for index in 0..<2 {
            let cel = reopened.layers[index].cels[0]
            XCTAssertNil(reopened.packageLedger.entry(for: cel.id))
            let source = try XCTUnwrap(cel.raster.snapshot())
            let checkpoint = try source.prepareForSave().get()
            XCTAssertFalse(checkpoint.encoded, "PREMISE: observing an already durable source must not encode a checkpoint")
            let backing = checkpoint.backing
            XCTAssertFalse(backing.url.standardizedFileURL.path.hasPrefix(url.standardizedFileURL.path + "/"),
                           "A reopened source owns its compressed bytes outside the live package")
            let sourceIsReadable = FileManager.default.isReadableFile(atPath: backing.url.path)
            XCTAssertTrue(sourceIsReadable,
                          "The protected PNG exists and is readable before its bytes are compared")
            guard sourceIsReadable else { return }
            XCTAssertEqual(try Data(contentsOf: backing.url), originalPNGs[index])
        }
        saveAndWait(reopened, to: url)
        let profile = try XCTUnwrap(profile())
        XCTAssertEqual(profile.pngsEncoded, 0, "Already protected sources require no PNG encoder")
        XCTAssertEqual(profile.pngsReused, 2, "Both immutable PNG resources are copied into the complete new package")
        XCTAssertEqual(reopened.packageLedger.landedAt, url)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
        let saved = try XCTUnwrap(ProjectStore.load(from: url))
        for index in 0..<2 {
            XCTAssertNotNil(reopened.packageLedger.entry(for: reopened.layers[index].cels[0].id))
            XCTAssertEqual(try XCTUnwrap(rasterBytes(of: saved, layerIndex: index, in: url)), originalPNGs[index])
            let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(
                try saved.layers[index].cels[0].raster.renderToUIImage().get().cgImage)))
            XCTAssertEqual(pixels, originalPixels[index], "The first save after reopening preserves the actual drawing")
        }
        XCTAssertEqual(saved.layers[2].cels[0].vector?.elements.count, 1)
    }

    func testAMissingLivePNGIsRestoredFromItsProtectedSource() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        let originalPixels = try (0..<2).map { index in
            try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(
                try manager.layers[index].cels[0].raster.renderToUIImage().get().cgImage)))
        }
        saveAndWait(manager, to: url)
        let originalPNGs = try (0..<2).map { try XCTUnwrap(rasterBytes(of: manager, layerIndex: $0, in: url)) }

        // The live package file can disappear without changing this immutable source version.
        let cel = manager.layers[1].cels[0]
        let missing = url.appendingPathComponent("images").appendingPathComponent("\(cel.id.uuidString)_raster.png")
        let source = try XCTUnwrap(cel.raster.snapshot())
        let checkpoint = try source.prepareForSave().get()
        XCTAssertFalse(checkpoint.encoded, "PREMISE: observing an already durable source must not encode a checkpoint")
        let backing = checkpoint.backing
        XCTAssertNotEqual(backing.url.standardizedFileURL, missing.standardizedFileURL)
        XCTAssertFalse(backing.url.standardizedFileURL.path.hasPrefix(url.standardizedFileURL.path + "/"))
        XCTAssertEqual(try Data(contentsOf: backing.url), originalPNGs[1])
        try FileManager.default.removeItem(at: missing)
        XCTAssertEqual(try Data(contentsOf: backing.url), originalPNGs[1], "Deleting the live file does not delete the protected source")

        saveAndWait(manager, to: url)
        let profile = try XCTUnwrap(profile())
        XCTAssertEqual(profile.pngsEncoded, 0, "A missing live clone falls back to the existing immutable PNG")
        XCTAssertEqual(profile.pngsReused, 2, "One live-package clone and one protected-source copy preserve both cels")
        XCTAssertTrue(FileManager.default.fileExists(atPath: missing.path), "…and the file is back")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
        XCTAssertEqual(manager.packageLedger.landedAt, url)
        let saved = try XCTUnwrap(ProjectStore.load(from: url))
        for index in 0..<2 {
            XCTAssertEqual(try XCTUnwrap(rasterBytes(of: saved, layerIndex: index, in: url)), originalPNGs[index])
            let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(
                try saved.layers[index].cels[0].raster.renderToUIImage().get().cgImage)))
            XCTAssertEqual(pixels, originalPixels[index], "Recovery restores the drawing, not just a valid PNG header")
        }
        XCTAssertEqual(saved.layers[2].cels[0].vector?.elements.count, 1)
    }

    func testAnEditMadeWhileASaveIsInFlightIsCarriedByTheNextSave() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        saveAndWait(manager, to: url)

        // The snapshot is synchronous and the write is not: this dot lands after the snapshot of
        // the save below and before its landing, which is exactly "during a save".
        let driver = AutosaveDriver()
        defer { driver.stop() }
        driver.follow(manager, isHeld: { true }, save: {})
        driver.saveStarted()
        let landed = expectation(description: "save in flight lands")
        ProjectStore.save(manager, to: url) { _ in
            driver.saveFinished(for: manager)
            landed.fulfill()
        }
        stamp(manager, layerIndex: 1, at: CGPoint(x: 50, y: 12))
        XCTAssertTrue(manager.addLayer(), "PREMISE: an actual manager edit occurs after the synchronous snapshot")
        XCTAssertTrue(driver.clock.hasUnsavedEdits, "The real edit during the write remains owed")
        let dueDuringSave = driver.clock.dueAt
        wait(for: [landed], timeout: 30)
        XCTAssertEqual(driver.clock.dueAt, dueDuringSave,
                       "Landing the older snapshot must not clear or reset an edit made during its write")
        let during = try XCTUnwrap(profile())
        XCTAssertEqual(during.pngsEncoded, 0, "That save carried the document as it was when it started")

        saveAndWait(manager, to: url)
        let after = try XCTUnwrap(profile())
        XCTAssertEqual(after.pngsEncoded, 1, "The next save encodes exactly the cel edited in flight")
        XCTAssertEqual(after.pngsReused, 1)
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let bytes = CanvasFixture.rgbaBytes(try XCTUnwrap(try reloaded.layers[1].cels[0].raster.renderToUIImage().get().cgImage))
        XCTAssertGreaterThan(bytes?[(12 * 64 + 50) * 4 + 3] ?? 0, 0, "The in-flight dot is on disk now")
    }

    /// A temporary write failure must not make the open document wait for another edit to be saved.
    /// The binding reports failure through the same driver feedback as ContentView.
    func testAFailedAutosaveLandsAfterTheWriteObstructionClearsWithoutAnotherEdit() throws {
        let manager = makeManager()
        let expected = try XCTUnwrap(CanvasFixture.rgbaBytes(
            try XCTUnwrap(try manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)))
        XCTAssertTrue(expected.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 },
                      "PREMISE: actual raster ink must survive the recovered save")
        let blocker = root.appendingPathComponent("retry-blocker-\(UUID().uuidString)")
        try Data([1]).write(to: blocker)
        let parent = blocker.appendingPathComponent("project", isDirectory: true)
        let url = parent.appendingPathComponent("Retry.paintproj")
        let firstAttempt = expectation(description: "the first real write attempt finished")
        let recoveredAttempt = expectation(description: "an automatic later write attempt finished")
        var attempts = 0
        var firstFailed = false
        var obstructionRemovalError: String?
        let driver = AutosaveDriver()
        defer { driver.stop() }
        driver.follow(manager, isHeld: { [weak driver] in (driver?.savesInFlight ?? 1) > 0 }, save: { [weak driver] in
            guard let driver else { return }
            attempts += 1
            let attempt = attempts
            driver.saveStarted()
            _ = ProjectStore.save(manager, to: url, intent: .automatic) { landed in
                driver.saveFinished(for: manager)
                if landed == nil { driver.saveDeferred(for: manager) }
                if attempt == 1 {
                    firstFailed = landed == nil
                    // Only the test-owned filesystem changes; no second document edit is made.
                    do {
                        try FileManager.default.removeItem(at: blocker)
                        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                    } catch {
                        obstructionRemovalError = String(describing: error)
                    }
                    firstAttempt.fulfill()
                } else {
                    recoveredAttempt.fulfill()
                }
            }
        })
        XCTAssertTrue(manager.addLayer(), "PREMISE: one real history edit arms the autosave")
        let historyAfterTheOnlyEdit = manager.history.undoStack.count
        let firstStatus = XCTWaiter.wait(for: [firstAttempt], timeout: 30)
        XCTAssertEqual(firstStatus, .completed, "PREMISE: observe the actual failed write, not an absent timer")
        XCTAssertTrue(firstFailed, "PREMISE: ENOTDIR refused the real staged package")
        XCTAssertNil(obstructionRemovalError, "PREMISE: the same destination is now writable")
        let firstLanded = FileManager.default.fileExists(atPath: url.path)
        XCTAssertFalse(firstLanded, "PREMISE: the failed attempt did not land a package")
        guard firstStatus == .completed, firstFailed, obstructionRemovalError == nil, !firstLanded else { return }

        // The wait itself cannot fail the test: the outcome is what actually reached disk afterwards.
        _ = XCTWaiter.wait(for: [recoveredAttempt], timeout: 10)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "Once writes are possible, autosave must land the owed drawing without another edit")
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let actual = try XCTUnwrap(CanvasFixture.rgbaBytes(
            try XCTUnwrap(try reloaded.layers[0].cels[0].raster.renderToUIImage().get().cgImage)))
        XCTAssertEqual(actual, expected, "The recovered package contains the original raster drawing")
        XCTAssertEqual(manager.history.undoStack.count, historyAfterTheOnlyEdit,
                       "Filesystem recovery and saving do not fabricate another document edit")
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

    func testAVersionSlotCopiesProtectedSourcesWithoutChangingTheLiveLedger() throws {
        let manager = makeManager()
        let url = ProjectStore.createNewProjectURL(name: "Autosave")
        let originalPixels = try (0..<2).map { index in
            try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(
                try manager.layers[index].cels[0].raster.renderToUIImage().get().cgImage)))
        }
        saveAndWait(manager, to: url)
        XCTAssertEqual(manager.packageLedger.landedAt, url)
        let originalManifest = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let originalPNGs = try (0..<2).map { try XCTUnwrap(rasterBytes(of: manager, layerIndex: $0, in: url)) }
        let originalDrawing = try XCTUnwrap(drawingBytes(of: manager, layerIndex: 2, in: url))
        for index in 0..<2 {
            let source = try XCTUnwrap(manager.layers[index].cels[0].raster.snapshot())
            let checkpoint = try source.prepareForSave().get()
            XCTAssertFalse(checkpoint.encoded, "PREMISE: observing an already durable source must not encode a checkpoint")
            let backing = checkpoint.backing
            XCTAssertFalse(backing.url.standardizedFileURL.path.hasPrefix(url.standardizedFileURL.path + "/"))
            XCTAssertEqual(try Data(contentsOf: backing.url), originalPNGs[index])
        }

        // A damaged, unanswered document writes a standalone version without borrowing or replacing the live ledger.
        var damage = ProjectLoadDamage()
        damage.add(ProjectLoadDamage.LayerDamage(layerName: "Ink", brushStrokes: 1))
        manager.loadDamage = damage
        saveAndWait(manager, to: url, intent: .automatic)
        let profile = try XCTUnwrap(profile())
        XCTAssertEqual(profile.pngsEncoded, 0, "Protected immutable sources need no new PNG encode for a version slot")
        XCTAssertEqual(profile.pngsReused, 2, "The complete version copies both protected PNG resources")
        XCTAssertTrue(ProjectBackupManager.listBackups(forProjectAt: url).contains { $0.label == "Unsaved changes" })
        let version = try XCTUnwrap(ProjectBackupManager.listBackups(forProjectAt: url).first { $0.label == "Unsaved changes" })
        XCTAssertNotEqual(version.url, url)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: version.url))
        XCTAssertEqual(manager.packageLedger.landedAt, url, "Writing aside does not publish a version-slot URL into the live ledger")
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.json")), originalManifest)
        XCTAssertEqual(try XCTUnwrap(drawingBytes(of: manager, layerIndex: 2, in: url)), originalDrawing)
        let saved = try XCTUnwrap(ProjectStore.load(from: version.url))
        for index in 0..<2 {
            XCTAssertEqual(try XCTUnwrap(rasterBytes(of: manager, layerIndex: index, in: url)), originalPNGs[index],
                           "A version save leaves the live package's raster bytes untouched")
            XCTAssertEqual(try XCTUnwrap(rasterBytes(of: saved, layerIndex: index, in: version.url)), originalPNGs[index])
            let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(
                try saved.layers[index].cels[0].raster.renderToUIImage().get().cgImage)))
            XCTAssertEqual(pixels, originalPixels[index], "The standalone version reopens with the original drawing")
        }
        XCTAssertEqual(saved.layers[2].cels[0].vector?.elements.count, 1)
    }
}
