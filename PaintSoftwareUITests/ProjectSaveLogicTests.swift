import XCTest
import UIKit

/// Pure-logic tests for `ProjectStore.save`'s off-the-main-actor write (Stage 4.2), run against a
/// per-test temp directory via `ProjectBackupManager.rootDirectoryOverride` — no app launch, no
/// simulator gestures. `Services/ProjectStore.swift` is compiled directly into this test bundle (see
/// `BackupManagerLogicTests`' header for why `@testable import` can't be used here), so `save` and
/// `load` are called for real rather than simulated.
///
/// What these exist to protect: `save` now snapshots `@MainActor` state synchronously and then does
/// the PNG encoding, JSON encoding and all file I/O on a background queue. Two properties have to
/// survive that.
///
/// 1. The package is still **fully formed** when the write completes — the snapshot must actually
///    carry everything `writePackage` used to read off the live `CanvasManager`. A field left out of
///    `SaveSnapshot` would silently save an incomplete project, which no existing test would catch.
/// 2. The **atomicity guarantee from session 34** still holds: at any instant during a save, what is
///    on disk is either the complete old package or the complete new one, never a partial one.
///    Staging to a temp path and swapping by rename is what provides this, and running those steps on
///    another thread must not weaken it. A reader racing the write is now genuinely possible, where
///    before the main-thread save made it impossible, so it is worth pinning directly.
///
/// The class is `@MainActor` because `save`/`load` are; `wait(for:)` spins the run loop, which is
/// what lets the completion handler's main-actor hop run.
@MainActor
final class ProjectSaveLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("project-save-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Helpers

    /// A project with enough shape to make an incomplete snapshot visible: two raster layers with
    /// actual stamped pixels, a vector layer holding a real stroke (so the `VectorCanvas` copy and its
    /// JSON payload are exercised), a second cel on the bottom layer, and non-default scalars on the
    /// manager itself so a dropped field shows up as a changed value rather than a coincidental match.
    private func makeManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.projectName = "Async Save"
        manager.fps = 18
        manager.sceneFrameCount = 14
        manager.canvasPadding = 7

        for layerIndex in 0..<2 {
            let raster = manager.layers[layerIndex].cels[0].raster
            raster.beginStroke()
            raster.stampCircle(at: CGPoint(x: 20 + layerIndex * 10, y: 24), radius: 6,
                               color: .red, alpha: 1, hardness: 1)
            raster.endStroke()
        }

        // A second cel on layer 0, so the per-cel loop writes more than one raster per layer.
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 12, frameCount: 2),
                      "Setup: layer 0 should take a second cel at frame 12")

        manager.addVectorLayer()
        let vectorCanvas = manager.layers[2].cels[0].vector
        XCTAssertNotNil(vectorCanvas, "Setup: a vector layer's cel should carry a VectorCanvas")
        vectorCanvas?.addStroke(VectorStroke(brush: manager.selectedBrush,
                                            color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                            size: 8, opacity: 1,
                                            samples: [VectorSample(x: 10, y: 10, pressure: 1),
                                                      VectorSample(x: 40, y: 40, pressure: 1)]))
        return manager
    }

    private func projectURL(name: String = "Async Save") -> URL {
        ProjectStore.createNewProjectURL(name: name)
    }

    /// Saves and blocks until the background write has finished, so assertions afterwards run against
    /// a package that is provably complete.
    private func saveAndWait(_ manager: CanvasManager, to url: URL) {
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    /// The whole point of the staged-write-then-rename design: whatever is on disk at `url` right now
    /// is either nothing at all or a *complete, loadable* package. Never a half-written one.
    ///
    /// Deliberately does not assert which of the two it is — that would be a race, since the
    /// background write may or may not have landed by the time a test looks. The invariant that holds
    /// either way is the one worth asserting.
    private func assertNeverPartial(at url: URL, _ context: String) {
        guard FileManager.default.fileExists(atPath: url.path) else { return } // nothing swapped in yet
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "\(context): a package visible at the live path must pass integrity validation — a partial one is exactly what the atomic swap exists to prevent")
        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("\(context): a package that validates should also load")
        }
        XCTAssertFalse(reloaded.layers.isEmpty, "\(context): a complete package has at least one layer")
        for layer in reloaded.layers {
            XCTAssertFalse(layer.cels.isEmpty, "\(context): every layer in a complete package has at least one cel")
        }
    }

    private func hasVisiblePixels(_ cel: Cel) -> Bool {
        PixelOps.opaqueContentBounds(cel.raster.renderToUIImage()) != nil
    }

    // MARK: - Fully-formed package

    /// The baseline: everything the snapshot carries makes it to disk and comes back. If a field were
    /// dropped from `SaveSnapshot` while moving the write off main, this is what catches it.
    func testSaveThenReloadProducesAFullyFormedPackage() {
        let manager = makeManager()
        let url = projectURL()

        saveAndWait(manager, to: url)

        XCTAssertTrue(ProjectBackupManager.validateProject(at: url), "The written package should pass integrity validation")
        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("The saved package should load")
        }

        XCTAssertEqual(reloaded.projectID, manager.projectID)
        XCTAssertEqual(reloaded.projectName, "Async Save")
        XCTAssertEqual(reloaded.fps, 18)
        XCTAssertEqual(reloaded.sceneFrameCount, 14)
        XCTAssertEqual(reloaded.canvasPadding, 7)
        XCTAssertEqual(reloaded.canvasSize, CanvasFixture.canvasSize)

        XCTAssertEqual(reloaded.layers.count, 3, "All three layers should survive the round trip")
        XCTAssertEqual(reloaded.layers.map(\.kind), [.raster, .raster, .vector],
                       "Layer kinds should round-trip, including the vector layer")
        XCTAssertEqual(reloaded.layers[0].cels.count, 2, "Layer 0's second cel should survive")
        XCTAssertEqual(reloaded.layers[0].cels.map(\.startFrame).sorted(), [0, 12])

        XCTAssertTrue(hasVisiblePixels(reloaded.layers[0].cels[0]),
                      "The stamped raster content should come back as pixels, not a blank cel")
        XCTAssertTrue(hasVisiblePixels(reloaded.layers[1].cels[0]),
                      "The second raster layer's content should come back too")
        XCTAssertEqual(reloaded.layers[2].cels[0].vector?.strokes.count, 1,
                       "The vector layer's stroke should round-trip through its JSON payload")
    }

    /// The specific race the async write introduces: a caller that reloads the project the instant
    /// `save` returns. It must never observe a partially written package — and once the completion
    /// handler has fired, the package must be there in full.
    ///
    /// Note what is *not* asserted: that the immediate reload finds nothing. The background write
    /// could legitimately finish before the next statement on main, so pinning that would be flaky.
    /// The reload is still performed, because performing it is what exercises the race.
    func testReloadingImmediatelyAfterSaveNeverSeesAPartialPackage() {
        let manager = makeManager()
        let url = projectURL()

        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }

        // No waiting: this is the reload-immediately case.
        assertNeverPartial(at: url, "Reload racing a first save")

        wait(for: [finished], timeout: 30)

        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "Once the completion handler has run, the package must be complete on disk — this is the contract callers rely on instead of racing the write")
        XCTAssertEqual(ProjectStore.load(from: url)?.layers.count, 3)
    }

    /// The session-34 guarantee under the async write, in its harder form: overwriting an existing
    /// project. At every instant there must be a complete package at the live path — the old one until
    /// the rename, the new one after — so a reader that arrives mid-save can never be handed a mix of
    /// the two.
    func testResavingOverAnExistingProjectNeverExposesAPartialPackage() {
        let manager = makeManager()
        let url = projectURL()
        saveAndWait(manager, to: url)
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url), "Setup: the first save should be complete")

        manager.addLayer()
        manager.projectName = "Async Save"   // keep the same package path
        let finished = expectation(description: "second save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }

        // Mid-save: whichever version is visible, it must be a whole one.
        assertNeverPartial(at: url, "Reload racing a re-save")

        wait(for: [finished], timeout: 30)
        XCTAssertEqual(ProjectStore.load(from: url)?.layers.count, 4,
                       "After completion the reload should see the new version, with the added layer")
    }

    /// Pins the contract `ContentView.returnToGallery` depends on: by the time the completion handler
    /// runs, the package is already on disk and loadable, and the handler runs on the main thread (it
    /// drives `@State`, and the gallery re-lists projects from disk in a one-shot `onAppear`).
    ///
    /// Also pins the actual point of moving the write off the main actor: `save` returns to its caller
    /// *before* the write finishes. `callerResumed` is set on the line after the `save` call, so a
    /// completion that observed it as `false` would mean the encode-and-write ran to completion inside
    /// `save` — i.e. still blocking the caller, which is the bug this replaced. This is deterministic
    /// rather than timing-based: the completion hops back to the main actor, so it cannot run until
    /// this test method yields at `wait(for:)`.
    func testSaveReturnsBeforeTheWriteFinishesAndCompletesOnTheMainThread() {
        let manager = makeManager()
        let url = projectURL()

        let finished = expectation(description: "ProjectStore.save completion")
        var callerResumed = false
        var callerHadResumedWhenCompletionRan = false
        var wasMainThread = false
        var validatedInsideCompletion = false
        ProjectStore.save(manager, to: url) {
            callerHadResumedWhenCompletionRan = callerResumed
            wasMainThread = Thread.isMainThread
            validatedInsideCompletion = ProjectBackupManager.validateProject(at: url)
            finished.fulfill()
        }
        callerResumed = true
        wait(for: [finished], timeout: 30)

        XCTAssertTrue(callerHadResumedWhenCompletionRan,
                      "save() must return to its caller before the write completes — encoding a multi-layer project inline is what used to block the UI for seconds")
        XCTAssertTrue(wasMainThread, "The completion handler must run on the main thread — callers use it to drive UI state")
        XCTAssertTrue(validatedInsideCompletion, "The package must already be complete when the completion handler runs, not shortly after")
    }

    /// A save leaves the previous version recoverable rather than destroyed — the other half of the
    /// session-34 design (`stashLiveProjectForSave`), which the move off main routes through
    /// unchanged. Guards against a future "optimisation" that deletes the live package before the
    /// rename now that the two steps are on a background queue.
    func testResavingKeepsTheOldVersionAsARestorePoint() {
        let manager = makeManager()
        let url = projectURL()
        saveAndWait(manager, to: url)

        manager.addLayer()
        saveAndWait(manager, to: url)

        let backups = ProjectBackupManager.listBackups(forProjectAt: url)
        XCTAssertFalse(backups.isEmpty, "Saving over a project should leave at least one restore point behind")
    }
}
