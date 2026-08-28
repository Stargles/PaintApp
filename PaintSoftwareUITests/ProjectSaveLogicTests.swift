import XCTest
import UIKit
import SwiftUI

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

    // MARK: - The thumbnail composites the tile, not the canvas

    /// The owner's canvas, not the 64×64 the rest of this file uses: `renderSize(fitting:within:)`
    /// clamps at 1×, so a fixture smaller than the 320-point tile box makes the hint inert and every
    /// assertion below vacuous. 2048×1024 is what [TODO.md](TODO.md) records the owner animating on.
    private static let ownersCanvas = CGSize(width: 2048, height: 1024)

    /// One layer, one cel, one hard-edged rectangle covering the top-left quarter — placed at exact
    /// multiples of the 0.15625 tile scale so the two downsample paths compared below have no
    /// sub-pixel edge to disagree about. What is under test is *where the pixels are composited*, and
    /// an edge landing between two tile pixels would add a difference that is about filtering.
    private func thumbnailManager() -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = Self.ownersCanvas
        manager.addLayer()
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red,
                                                               rect: CGRect(x: 0, y: 0, width: 1024, height: 512),
                                                               size: Self.ownersCanvas))
        return manager
    }

    /// The rule, on its own. A bounding box, the canvas's aspect kept, and **never** an upscale.
    func testTheRenderSizeHintFitsTheCanvasAspectInsideTheBoxAndNeverGrowsIt() {
        let box = CGSize(width: 320, height: 320)

        XCTAssertEqual(RenderRequest.renderSize(fitting: CGSize(width: 2048, height: 1024), within: box),
                       CGSize(width: 320, height: 160),
                       "The wide dimension binds, and the aspect is the canvas's — not the box's")
        XCTAssertEqual(RenderRequest.renderSize(fitting: CGSize(width: 1024, height: 2048), within: box),
                       CGSize(width: 160, height: 320),
                       "…and the tall dimension binds on a tall canvas")
        XCTAssertEqual(RenderRequest.renderSize(fitting: CGSize(width: 4096, height: 4096), within: box),
                       box,
                       "A square canvas fills the square box")

        // A hint may only ask for less. Compositing above native invents no detail and costs more
        // than the render it would replace.
        XCTAssertEqual(RenderRequest.renderSize(fitting: CGSize(width: 64, height: 64), within: box),
                       CGSize(width: 64, height: 64),
                       "A canvas already smaller than the box is returned untouched, not stretched to fill it")

        // Whole pixels, upstream of both backends — `RenderResolution.renderSize`'s reason, and the
        // same failure it prevents: a source one pixel wider than the composite reading it.
        let odd = RenderRequest.renderSize(fitting: CGSize(width: 1001, height: 333), within: box)
        XCTAssertEqual(odd.width, odd.width.rounded(), "width is whole")
        XCTAssertEqual(odd.height, odd.height.rounded(), "height is whole")
        XCTAssertEqual(odd, CGSize(width: 320, height: 106))

        // Degenerate inputs fall back to the canvas rather than to a zero-sized texture allocation.
        XCTAssertEqual(RenderRequest.renderSize(fitting: Self.ownersCanvas, within: .zero), Self.ownersCanvas)
        XCTAssertEqual(RenderRequest.renderSize(fitting: .zero, within: box), .zero)
    }

    /// **The waste, counted rather than timed.** A save composited the whole canvas to fill a
    /// 320-point tile — 2,097,152 pixels for the 51,200 the tile occupies at the owner's canvas, on
    /// the main actor, inside every save. This asserts the size the compositor was actually asked
    /// for, which is a fact about the call and not about the machine it ran on.
    func testTheProjectThumbnailCompositesAtTileSizeRatherThanCanvasSize() {
        let manager = thumbnailManager()
        let url = projectURL(name: "Thumbnail Size")

        CompositeProbe.begin()
        saveAndWait(manager, to: url)
        let composited = CompositeProbe.end()

        XCTAssertEqual(composited, [CGSize(width: 320, height: 160)],
                       "One composite, sized to the tile. Before 2026-08-20 this was one composite at 2048×1024 — a 40× "
                       + "overdraw on the main actor, and until the scene-phase gate landed, three of them per app switch")
    }

    /// …and the tile still looks the same. The saving is only a saving if the picture survives it, so
    /// this composites the same document both ways and compares the two tiles.
    ///
    /// A mean absolute difference rather than an exact match: the two paths downsample in different
    /// places — one filters 2048×1024 down to 320×160, the other composites at 320×160 directly — and
    /// demanding byte equality between them would be asserting that two different filters agree,
    /// which is not the claim. The claim is that a gallery tile is unchanged to the eye.
    func testTheTileFromTheSizedCompositeMatchesTheTileFromTheFullOne() {
        let manager = thumbnailManager()
        let box = CGSize(width: 320, height: 320)

        guard let native = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let hinted = manager.makeRenderRequest(atFrame: 0, includeBackground: false, fittingWithin: box) else {
            return XCTFail("Both requests must build")
        }
        XCTAssertEqual(native.canvasSize, Self.ownersCanvas, "No hint means native, exactly as before")
        XCTAssertEqual(hinted.canvasSize, CGSize(width: 320, height: 160))

        guard let nativeImage = Compositor.composite(native),
              let hintedImage = Compositor.composite(hinted) else {
            return XCTFail("Both must composite")
        }
        let fromNative = ThumbnailRenderer.render(UIImage(cgImage: nativeImage, scale: 1, orientation: .up),
                                                  canvasSize: Self.ownersCanvas, thumbnailSize: box)
        let fromHinted = ThumbnailRenderer.render(UIImage(cgImage: hintedImage, scale: 1, orientation: .up),
                                                  canvasSize: Self.ownersCanvas, thumbnailSize: box)

        XCTAssertEqual(fromNative.size, fromHinted.size, "Both paths produce the same tile geometry")
        guard let a = fromNative.cgImage.flatMap(CanvasFixture.rgbaBytes),
              let b = fromHinted.cgImage.flatMap(CanvasFixture.rgbaBytes), a.count == b.count else {
            return XCTFail("Both tiles must be readable and the same shape")
        }
        let meanDifference = zip(a, b).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(a.count)
        XCTAssertLessThan(meanDifference, 2.0,
                          "The tile the artist sees is unchanged — mean channel difference \(meanDifference) of 255")
    }

    /// EFFECT_BACKDROP.md §5.3, fixed 2026-08-27: the gallery tile carries the canvas paper, not
    /// transparency. `thumbnailManager()`'s red rect covers only the top-left quarter, so the
    /// bottom-right corner is untouched artwork — before the fix that pixel was `(0,0,0,0)`
    /// (transparent, and drawn on the gallery's own black), and after it is the document's own
    /// `canvasBackgroundColor` (white by default), composited by the same `ProjectStore.save` path
    /// this file's other thumbnail tests already exercise.
    func testTheSavedThumbnailCarriesTheCanvasBackgroundNotTransparency() throws {
        let manager = thumbnailManager()
        XCTAssertEqual(manager.canvasBackgroundColor, .white, "Setup: the fixture's default paper")
        XCTAssertTrue(manager.isCanvasBackgroundVisible, "Setup: the fixture's paper is shown")
        let url = projectURL(name: "Thumbnail Background")

        saveAndWait(manager, to: url)

        let thumbnailPath = url.appendingPathComponent("thumbnail.png").path
        guard let thumbnail = UIImage(contentsOfFile: thumbnailPath), let cg = thumbnail.cgImage else {
            return XCTFail("The saved package should carry a readable thumbnail.png")
        }
        guard let bytes = CanvasFixture.rgbaBytes(cg) else {
            return XCTFail("The thumbnail should decode to RGBA bytes")
        }
        let width = cg.width, height = cg.height
        let offset = ((width - 1) + (height - 1) * width) * 4
        let corner = Array(bytes[offset..<(offset + 4)])
        XCTAssertEqual(corner, [255, 255, 255, 255],
                       "The bottom-right corner sits outside the red rect, so it should read the "
                       + "white canvas background rather than transparent (0,0,0,0) — got \(corner)")
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

    /// ARCHITECTURE_REVIEW.md finding 3: `writeAtomically`'s three failure returns used to be bare
    /// `return`s, indistinguishable from success — `completion` ran either way, so `ContentView` (and
    /// the gallery it navigates to) looked exactly the same whether the write landed or not.
    /// `onSaveFailed` is the channel that tells them apart, and this pins both directions of it: a
    /// failing write must call it, a succeeding one must not.
    ///
    /// The failure is induced by pointing the whole Projects/Backups/Trash tree at a path whose
    /// parent is a plain file rather than a directory, so every `createDirectory`/`write` under it
    /// fails with ENOTDIR. Nothing crashes — `ProjectBackupManager` and `writePackage` guard every one
    /// of those calls with `try?` — the package is just never actually written, so `validateProject`
    /// finds no manifest and `writeAtomically` takes its first failure return.
    func testAFailedSaveCallsOnSaveFailedAndASucceedingOneDoesNot() {
        let manager = makeManager()
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-blocker-\(UUID().uuidString)")
        try! Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        ProjectBackupManager.rootDirectoryOverride = blocker.appendingPathComponent("root", isDirectory: true)
        defer { ProjectBackupManager.rootDirectoryOverride = root }

        let brokenURL = ProjectStore.createNewProjectURL(name: "Unwritable")
        let failedSave = expectation(description: "ProjectStore.save completion (failing write)")
        var reportedFailure = false
        var completionRanOnFailure = false
        ProjectStore.save(manager, to: brokenURL, onSaveFailed: { reportedFailure = true }) {
            completionRanOnFailure = true
            failedSave.fulfill()
        }
        wait(for: [failedSave], timeout: 30)

        XCTAssertTrue(reportedFailure, "A save that cannot stage a valid package must call onSaveFailed")
        XCTAssertTrue(completionRanOnFailure,
                      "completion must still run on failure too — it means \"the attempt is over\", not \"it worked\", and existing callers rely on it to stop waiting")
        XCTAssertFalse(FileManager.default.fileExists(atPath: brokenURL.path),
                       "Nothing should have been swapped into the live path when staging never produced a valid package")

        // Restore a real root before proving the success side, so this half of the test is not
        // exercising the same broken tree.
        ProjectBackupManager.rootDirectoryOverride = root

        let workingURL = projectURL(name: "Writable")
        let goodSave = expectation(description: "ProjectStore.save completion (succeeding write)")
        var reportedFailureOnSuccess = false
        ProjectStore.save(manager, to: workingURL, onSaveFailed: { reportedFailureOnSuccess = true }) {
            goodSave.fulfill()
        }
        wait(for: [goodSave], timeout: 30)

        XCTAssertFalse(reportedFailureOnSuccess, "A save that actually lands on disk must not call onSaveFailed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workingURL.path), "Setup: the second save should have landed")
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

    // MARK: - Group properties, and the projects that predate them (§4.1, §10.3)

    /// Rewrites the saved manifest to look like a **pre-phase-4 save**: every folder loses the
    /// group-property keys, exactly as a project written before those fields existed would be.
    ///
    /// This is the point of doing it this way rather than asserting on the decoder. "All defaulted, so
    /// existing projects decode unchanged" is a claim about JSON that has already been written to
    /// disk, and the only way to test it honestly is to load JSON without those keys in it. A decoder
    /// read back to itself would pass while `decodeIfPresent` was `decode`.
    /// Rewrites a saved manifest into what a build from before §6.6's override wrote: no
    /// `fillReferenceOverride` key on any layer, since that build had no such field.
    private func stripFillReferenceOverridesFromSavedManifest(at url: URL,
                                                              file: StaticString = #filePath, line: UInt = #line) {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var layers = json["layers"] as? [[String: Any]] else {
            return XCTFail("The saved package should carry a manifest with a layers array", file: file, line: line)
        }
        for index in layers.indices {
            layers[index].removeValue(forKey: "fillReferenceOverride")
        }
        json["layers"] = layers
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            return XCTFail("The stripped manifest should re-encode", file: file, line: line)
        }
        try? rewritten.write(to: manifestURL)
    }

    private func stripGroupPropertiesFromSavedManifest(at url: URL,
                                                       file: StaticString = #filePath, line: UInt = #line) {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var folders = json["folders"] as? [[String: Any]] else {
            return XCTFail("The saved package should carry a manifest with a folders array", file: file, line: line)
        }
        for index in folders.indices {
            folders[index].removeValue(forKey: "opacity")
            folders[index].removeValue(forKey: "blendMode")
            folders[index].removeValue(forKey: "isIsolated")
        }
        json["folders"] = folders
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            return XCTFail("The stripped manifest should re-encode", file: file, line: line)
        }
        try? rewritten.write(to: manifestURL)
    }

    private func folder(_ manager: CanvasManager, named name: String) -> LayerFolder? {
        manager.folders.first { $0.name == name }
    }

    func testGroupPropertiesSurviveARoundTrip() {
        let manager = makeManager()
        let group = manager.addFolder(name: "Inked")
        manager.layers[0].parentFolderID = group
        manager.setFolderOpacity(group, to: 0.4)
        manager.setFolderIsolated(group, isIsolated: false)

        let url = projectURL()
        saveAndWait(manager, to: url)
        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }

        let restored = folder(reloaded, named: "Inked")
        XCTAssertEqual(restored?.opacity ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertEqual(restored?.isIsolated, false, "Pass-through is a saved choice, not a session one")
        XCTAssertEqual(restored?.blendMode, .normal)
    }

    /// The claim §4.1 makes in one line — "all defaulted, so existing projects decode unchanged" —
    /// checked against a manifest that genuinely has no such keys.
    func testAProjectSavedBeforeGroupPropertiesDecodesToTheIdentities() {
        let manager = makeManager()
        let group = manager.addFolder(name: "Inked")
        manager.layers[0].parentFolderID = group

        let url = projectURL()
        saveAndWait(manager, to: url)
        stripGroupPropertiesFromSavedManifest(at: url)

        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("A project written before phase 4 must still load")
        }
        let restored = folder(reloaded, named: "Inked")
        XCTAssertEqual(restored?.opacity ?? -1, 1, accuracy: 0.0001, "A folder with no saved opacity is opaque")
        XCTAssertEqual(restored?.isIsolated, true, "Isolated is the default (§4.2), so an old folder is one")
        XCTAssertEqual(restored?.blendMode, .normal)
    }

    /// §10.3, decided: migrate rather than load as-is.
    ///
    /// The fixture is what the old `toggleFolderVisibility` actually left on disk — the folder hidden
    /// **and** every descendant, layers and subfolders alike, independently flagged hidden by the
    /// write-through. Loaded without the migration that document renders correctly and then comes back
    /// empty the first time the artist un-hides the group, because each child is still hidden in its
    /// own right.
    func testAnOldHiddenGroupComesBackWholeWhenItIsUnhidden() {
        let manager = makeManager()
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = inner

        // Reproduce the write-through by hand: it is the behaviour this build no longer has.
        manager.toggleFolderVisibility(outer)
        for index in manager.folders.indices { manager.folders[index].isVisible = false }
        for index in manager.layers.indices where index < 2 {
            manager.layers[index].isVisible = false
        }

        let url = projectURL()
        saveAndWait(manager, to: url)
        stripGroupPropertiesFromSavedManifest(at: url)

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }
        XCTAssertEqual(folder(reloaded, named: "Outer")?.isVisible, false,
                       "The group stays hidden — that flag is the one the artist actually chose")
        XCTAssertEqual(folder(reloaded, named: "Inner")?.isVisible, true,
                       "A subfolder hidden only by the write-through is restored with the rest")
        XCTAssertTrue(reloaded.layers[0].isVisible && reloaded.layers[1].isVisible,
                      "Un-hiding the group must bring its contents back, at any depth")
        XCTAssertTrue(reloaded.layers[0].isFillReference,
                      "Fill reference comes back with visibility, since nothing ever answered for this layer by hand (§6.6)")
    }

    /// The other half, and the reason the signal is the absence of a key rather than a version number:
    /// a document this build saved must never be migrated, or a deliberately hidden layer inside a
    /// hidden group would silently come back every time the project was opened.
    func testAGroupHiddenUnderTheNewRuleIsNotMigrated() {
        let manager = makeManager()
        let group = manager.addFolder(name: "Outer")
        manager.layers[0].parentFolderID = group
        manager.layers[1].parentFolderID = group

        manager.toggleFolderVisibility(group)
        manager.toggleLayerVisibility(layerIndex: 1)   // hidden on purpose, inside a hidden group

        let url = projectURL()
        saveAndWait(manager, to: url)
        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }

        XCTAssertEqual(folder(reloaded, named: "Outer")?.isVisible, false)
        XCTAssertTrue(reloaded.layers[0].isVisible, "Untouched under the new rule: the group gates it, nothing wrote to it")
        XCTAssertFalse(reloaded.layers[1].isVisible, "And a layer hidden by hand stays hidden across a reload")
    }

    /// §4.1 says an old preset "still works, since presets snapshot both layer and folder visibility
    /// already". That is true of what it renders and not of what it leaves behind: a preset written
    /// under the write-through records every child of a hidden group as hidden, so applying one
    /// re-creates the state the migration just cleared. Fixing the document alone would mean the group
    /// comes back once and empties again the next time the artist flips views.
    func testAnOldPresetDoesNotReintroduceTheClobberedVisibility() {
        let manager = makeManager()
        let group = manager.addFolder(name: "Outer")
        manager.layers[0].parentFolderID = group
        manager.layers[1].parentFolderID = group

        // The write-through by hand, then a preset capturing it — which is what an artist who hid a
        // group and saved a view under the old build has on disk.
        manager.toggleFolderVisibility(group)
        for index in manager.layers.indices where index < 2 {
            manager.layers[index].isVisible = false
        }
        manager.addViewPreset()

        let url = projectURL()
        saveAndWait(manager, to: url)
        stripGroupPropertiesFromSavedManifest(at: url)

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }
        guard let preset = reloaded.viewPresets.first else { return XCTFail("The preset should survive the round trip") }
        XCTAssertEqual(preset.folderVisibility[group], false, "The preset still hides the group, which is its point")
        XCTAssertEqual(preset.layerVisibility[reloaded.layers[0].id], true,
                       "But not by hiding each child, which is what re-showing the group would trip over")
        XCTAssertEqual(preset.layerVisibility[reloaded.layers[1].id], true)
    }

    /// A pre-phase-4 folder that was *visible* has children carrying their own honest flags, so the
    /// migration must leave them exactly alone.
    func testAnOldVisibleGroupKeepsItsChildrensOwnVisibility() {
        let manager = makeManager()
        let group = manager.addFolder(name: "Outer")
        manager.layers[0].parentFolderID = group
        manager.layers[1].parentFolderID = group
        manager.toggleLayerVisibility(layerIndex: 1)

        let url = projectURL()
        saveAndWait(manager, to: url)
        stripGroupPropertiesFromSavedManifest(at: url)

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }
        XCTAssertEqual(folder(reloaded, named: "Outer")?.isVisible, true)
        XCTAssertTrue(reloaded.layers[0].isVisible)
        XCTAssertFalse(reloaded.layers[1].isVisible, "The migration only fires under a hidden group")
    }

    /// **What a pre-§6.6 document decodes to, asserted rather than assumed — and it is not what the
    /// build that wrote it produced.**
    ///
    /// `isFillReference` was never persisted. The old loader passed no value for it at all, so every
    /// layer in every reopened project came back `true` on the stored default — a hidden layer
    /// included, even though hiding it in-session had just set it `false`. Saving and reopening
    /// silently promoted every hidden layer back to a fill boundary; the state that survived the
    /// round trip was not the state the artist left.
    ///
    /// Deriving it fixes that by construction, so an old file now decodes to what the session that
    /// saved it actually had. **This is a deliberate behaviour change on existing documents**, in the
    /// only direction §6.6 permits, and it is here so it is a decision on the record rather than a
    /// surprise: nothing is lost, because the old value carried no information — it was `true` for
    /// every layer regardless of what the artist had done.
    func testAPreOverrideDocumentDecodesFromVisibilityRatherThanTheOldStoredDefault() throws {
        let manager = makeManager()
        manager.toggleLayerVisibility(layerIndex: 1)      // hidden, so fill-excluded in-session

        let url = projectURL()
        saveAndWait(manager, to: url)
        stripFillReferenceOverridesFromSavedManifest(at: url)   // exactly what the old build wrote

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }
        XCTAssertTrue(reloaded.layers[0].isFillReference, "A shown layer is a boundary — same answer the old build gave")
        XCTAssertFalse(reloaded.layers[1].isFillReference,
                       "A hidden one is not. The old build answered `true` here, discarding the exclusion the save had captured")
        XCTAssertNil(reloaded.layers[1].fillReferenceOverride,
                     "…and it is the default answering, not a decision invented by the loader")
    }

    /// **§6.6's fill-reference decision has to survive the round trip or it is not a decision.** The
    /// effective value never was persisted — it was recomputed from visibility at load — so writing
    /// only the override is what makes "explicit wins" true tomorrow as well as this session, and
    /// leaving the key out for an unanswered layer is what an older project already looks like.
    func testAnExplicitFillReferenceSurvivesASaveAndLoadButADefaultedOneIsRederived() throws {
        let manager = makeManager()
        manager.setFillReference(layerIndex: 0, isReference: true)
        manager.toggleLayerVisibility(layerIndex: 0)   // hidden, and still a reference by decision
        manager.toggleLayerVisibility(layerIndex: 1)   // hidden, and not by default

        let url = projectURL()
        saveAndWait(manager, to: url)

        let data = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let layerJSON = try XCTUnwrap(json["layers"] as? [[String: Any]])
        XCTAssertEqual(layerJSON[0]["fillReferenceOverride"] as? Bool, true)
        XCTAssertNil(layerJSON[1]["fillReferenceOverride"],
                     "A layer nobody answered for writes no key — absence is what \"follow the default\" is")

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }
        XCTAssertTrue(reloaded.layers[0].isFillReference, "The decision came back with the document")
        XCTAssertFalse(reloaded.layers[1].isFillReference, "And the default was re-derived from the visibility that did")
    }

    // MARK: - Compositor nodes (§4.3)

    /// A document containing a Mix node saves and loads as the same graph: the node's op, and its
    /// operands in the order they were in. A node's inputs are its ordinary children now (§4.3), so
    /// **the whole of the operand order is the containment and ranking the round trip already
    /// preserves** — which is the storage decision holding, not a gap in this test.
    func testAMixNodeRoundTripsThroughSaveAndLoadWithItsOperandsInOrder() {
        let manager = makeManager()
        let node = manager.addCompositorNode(op: .mix(.multiply), name: "Mix")
        let backdropID = manager.layers[0].id
        let overID = manager.layers[1].id
        // Backdrop first, then the layer that composites over it — dropped in that order, so a load
        // that reordered them would show up as a swap rather than as a missing child.
        manager.restackLayer(backdropID, above: .folder(node), parentFolderID: node)
        manager.restackLayer(overID, above: .folder(node), parentFolderID: node)
        XCTAssertEqual(inputLayerIDs(manager, ofNode: node), [backdropID, overID], "Setup: input 0 is the backdrop")

        let url = projectURL()
        saveAndWait(manager, to: url)
        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("The saved package should load")
        }

        XCTAssertEqual(reloaded.folders.first { $0.id == node }?.compositorRole, .node(op: .mix(.multiply)),
                       "The op is the graph — a node that came back roleless would be silently demoted to a plain group")
        XCTAssertEqual(inputLayerIDs(reloaded, ofNode: node), [backdropID, overID],
                       "Both operands come back, and in the same order — a swap here is a different picture, not a cosmetic difference")
    }

    /// **§4.3's input-slot migration, and the only test that can disprove it.** A node saved while
    /// nodes had input-slot folders is a node folder plus two children tagged
    /// `{"kind":"slot","node":…,"index":…}`. Reading that tag as *no role* has to leave the same
    /// document: a node whose two operands are those folders, **input 0 still the one that was slot
    /// 0** — because `parentFolderID` already named the node and the ranking already ran
    /// bottom-to-top.
    ///
    /// Written by saving today's shape and injecting the retired tag, rather than by hand-rolling a
    /// whole manifest: everything else about the package then really is what `ProjectStore` writes,
    /// so a failure here is the migration and not a fixture typo.
    ///
    /// **Asserts the order, not the count.** Two children in the wrong order is exactly what a
    /// migration that dropped the ranking would produce, and it passes any count-shaped assertion.
    func testANodeSavedWithInputSlotFoldersOpensWithItsOperandsInSlotOrder() {
        let manager = makeManager()
        let node = manager.addCompositorNode(op: .mix(.multiply), name: "Mix")
        let inputA = manager.addFolder(name: "Input A", parentFolderID: node)
        let inputB = manager.addFolder(name: "Input B", parentFolderID: node)
        let backdropID = manager.layers[0].id
        let overID = manager.layers[1].id
        manager.restackLayer(backdropID, above: .folder(inputA), parentFolderID: inputA)
        manager.restackLayer(overID, above: .folder(inputB), parentFolderID: inputB)

        let url = projectURL()
        saveAndWait(manager, to: url)
        tagFoldersAsInputSlotsInSavedManifest(at: url, node: node, slots: [inputA, inputB])

        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("An old document must still open — a migration that throws costs the artist the file")
        }
        XCTAssertNil(reloaded.folders.first { $0.id == inputA }?.compositorRole,
                     "A `slot` tag decodes as no role at all — the folder is ordinary now")
        XCTAssertNil(reloaded.folders.first { $0.id == inputB }?.compositorRole)
        XCTAssertEqual(reloaded.folders.first { $0.id == node }?.compositorRole, .node(op: .mix(.multiply)),
                       "The node itself is untouched by the migration")

        XCTAssertEqual(reloaded.inputs(ofNode: node).map(inputName(in: reloaded)), ["Input A", "Input B"],
                       "Slot 0 was the backdrop and input 0 is the backdrop, so the operands must come back in that order — reversed here is a different picture")
        XCTAssertEqual(inputLayerIDs(reloaded, ofNode: inputA), [backdropID],
                       "…and each old slot still holds the artwork that was in it")
        XCTAssertEqual(inputLayerIDs(reloaded, ofNode: inputB), [overID])
    }

    /// A folder written by a build that had never heard of input slots and a folder written by one
    /// that had are both ordinary folders after the load; this is the *encode* half — the retired tag
    /// is not writable, so no document saved from here on carries one.
    func testTheRetiredSlotTagIsNotWritable() throws {
        let node = FolderManifest(id: UUID(), name: "Mix", isExpanded: true, isVisible: true,
                                  compositorRole: .node(op: .mix(.screen)))
        let data = try JSONEncoder().encode(node)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let role = try XCTUnwrap(object["compositorRole"] as? [String: Any])
        XCTAssertEqual(role["kind"] as? String, "node")
        XCTAssertNil(role["index"], "The slot payload has no encoder left — `CompositorRole` is one case")
    }

    /// Rewrites a saved manifest so the named folders carry the retired `slot` tag, which is exactly
    /// what a document saved before §4.3's redesign holds.
    private func tagFoldersAsInputSlotsInSavedManifest(at url: URL, node: UUID, slots: [UUID],
                                                       file: StaticString = #filePath, line: UInt = #line) {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var folders = json["folders"] as? [[String: Any]] else {
            return XCTFail("The saved package should carry a manifest with a folders array", file: file, line: line)
        }
        var tagged = 0
        for index in folders.indices {
            guard let id = folders[index]["id"] as? String,
                  let slot = slots.firstIndex(where: { $0.uuidString == id }) else { continue }
            folders[index]["compositorRole"] = ["kind": "slot", "node": node.uuidString, "index": slot]
            tagged += 1
        }
        XCTAssertEqual(tagged, slots.count, "Fixture: every slot folder should have been found and tagged",
                       file: file, line: line)
        json["folders"] = folders
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            return XCTFail("The rewritten manifest should re-encode", file: file, line: line)
        }
        try? rewritten.write(to: manifestURL)
    }

    /// The `layers` ids held directly by a container, bottom-to-top — the operand order, read the
    /// same way the derivation reads it.
    @MainActor
    private func inputLayerIDs(_ manager: CanvasManager, ofNode nodeID: UUID) -> [UUID] {
        manager.inputs(ofNode: nodeID).compactMap { entry in
            guard case .layer(let index) = entry, manager.layers.indices.contains(index) else { return nil }
            return manager.layers[index].id
        }
    }

    @MainActor
    private func inputName(in manager: CanvasManager) -> (CanvasManager.ContainerEntry) -> String {
        { entry in
            switch entry {
            case .layer(let index): return manager.layers.indices.contains(index) ? manager.layers[index].name : "?"
            case .folder(let folder): return folder.name
            }
        }
    }

    /// **The no-migration claim, stated as the only thing that could disprove it.** A folder written
    /// before phase 8 carries no role key at all, and has to decode as an ordinary folder — including
    /// not decoding as a *failure*, which would cost the artist the whole document over a field that
    /// did not exist when they saved it.
    func testAFolderSavedBeforePhase8DecodesAsAnOrdinaryFolder() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Group","isExpanded":true,"isVisible":true,
         "opacity":0.5,"blendMode":"multiply","isIsolated":false}
        """
        let decoded = try JSONDecoder().decode(FolderManifest.self, from: Data(json.utf8))

        XCTAssertNil(decoded.compositorRole, "No role key means an ordinary folder, which is what every pre-phase-8 folder is")
        XCTAssertNil(try JSONDecoder().decode(
            FolderManifest.self,
            from: Data("""
            {"id":"\(UUID().uuidString)","name":"Input A","isExpanded":true,"isVisible":true,"opacity":1,
             "compositorRole":{"kind":"slot","node":"\(UUID().uuidString)","index":0}}
            """.utf8)).compositorRole,
            "And a retired `slot` tag also means an ordinary folder — `decodeIfSupported`, not a throw the `try?` happens to swallow")
        XCTAssertFalse(decoded.wasSavedBeforeGroupProperties,
                       "`opacity` was present, so the §10.3 migration must stay disarmed — the new field must not disturb that signal")
        XCTAssertEqual(decoded.opacity, 0.5)
        XCTAssertEqual(decoded.blendMode, .multiply)
        XCTAssertFalse(decoded.isIsolated)
    }

    /// The other half of the same claim: an untagged folder's manifest is byte-for-byte what it was,
    /// because the key is written only when there is a role to write. Were it written unconditionally,
    /// its absence would stop meaning "pre-phase-8" and there would be a migration to run after all.
    func testAnOrdinaryFolderWritesNoCompositorRoleKey() throws {
        let ordinary = FolderManifest(id: UUID(), name: "Group", isExpanded: true, isVisible: true)
        let node = FolderManifest(id: UUID(), name: "Mix", isExpanded: true, isVisible: true,
                                  compositorRole: .node(op: .mix(.screen)))

        XCTAssertFalse(try encodedKeys(of: ordinary).contains("compositorRole"))
        XCTAssertTrue(try encodedKeys(of: ordinary).contains("opacity"),
                      "`opacity` still goes out unconditionally — the §10.3 migration reads its absence, so it cannot follow `alphaMask`'s pattern")
        XCTAssertTrue(try encodedKeys(of: node).contains("compositorRole"))
    }

    // MARK: - Which scene-phase changes trigger a save

    /// Every ordered pair of phases, stated as a table rather than as the three interesting cases.
    ///
    /// The bug this replaces existed precisely because the condition was under-specified — it named
    /// two destinations and never asked where the scene had come from — so sampling the transitions
    /// that look interesting would reproduce the original mistake in the test. The expectations here
    /// are the contract; `ScenePhaseSaveGate` carries the argument for them.
    ///
    /// The two rows that matter most are the ones that used to be true and are now false:
    /// `inactive → background` is the redundant second save on the way out, and `background →
    /// inactive` is the one that landed on the return leg while the artist was watching.
    private static let saveGateMatrix: [(from: ScenePhase, to: ScenePhase, save: Bool, why: String)] = [
        // Leaving an active scene — the only phase the artist can have drawn in, so the only
        // transition that can be carrying unsaved work.
        (.active,     .inactive,   true,  "leaving leg of an app switch: the save that carries the artist's work"),
        (.active,     .background, true,  "some paths skip .inactive and background the scene directly; it must still save"),

        // Already gone. The document cannot have changed since the departure save a moment earlier.
        (.inactive,   .background, false, "second leg of the same departure — re-saves a document nothing has touched"),

        // Coming back. Nothing to write, and this is where the freeze was visible.
        (.background, .inactive,   false, "return leg: the save the owner saw as a multi-second freeze"),
        (.background, .active,     false, "direct return, skipping .inactive — equally nothing to save"),
        (.inactive,   .active,     false, "return leg's second half, e.g. dismissing Control Centre"),

        // Never delivered by onChange(of:), which fires only on a real change. Pinned anyway so the
        // predicate is total: a gate that answered "save" here would fire on any spurious republish.
        (.active,     .active,     false, "not a change"),
        (.inactive,   .inactive,   false, "not a change"),
        (.background, .background, false, "not a change"),
    ]

    func testTheSaveGateCoversEveryScenePhaseTransition() {
        for row in Self.saveGateMatrix {
            XCTAssertEqual(ScenePhaseSaveGate.shouldSave(from: row.from, to: row.to), row.save,
                           "\(row.from) -> \(row.to) should \(row.save ? "" : "not ")save: \(row.why)")
        }
    }

    /// The matrix is only the contract if it is the whole matrix — three phases means nine ordered
    /// pairs, and a row quietly dropped from the table above would take its transition's coverage
    /// with it while every remaining assertion still passed.
    func testTheSaveGateMatrixIsExhaustive() {
        let phases: [ScenePhase] = [.active, .inactive, .background]
        let covered = Set(Self.saveGateMatrix.map { "\($0.from)->\($0.to)" })
        for from in phases {
            for to in phases {
                XCTAssertTrue(covered.contains("\(from)->\(to)"), "no matrix row for \(from) -> \(to)")
            }
        }
        XCTAssertEqual(Self.saveGateMatrix.count, phases.count * phases.count)
    }

    /// The bug in its own shape: one trip out to another app and back is one save, not three.
    ///
    /// This replays the phase sequence SwiftUI actually delivers rather than asserting on the
    /// predicate directly, because the defect was never in a single decision — each of the three
    /// saves was individually defensible under the old rule. It was in what the sequence added up to.
    func testOneAppSwitchRoundTripSavesExactlyOnce() {
        let roundTrip: [ScenePhase] = [.active, .inactive, .background, .inactive, .active]
        XCTAssertEqual(savesFired(over: roundTrip), 1,
                       "an app switch and back must write once, on the way out")
    }

    /// The same journey on the paths that skip `.inactive`, and one that never leaves the foreground.
    /// Both still save exactly when they should — the fix narrows *which* transition saves, and must
    /// not narrow it to a transition some routes never deliver.
    func testTheDirectAndForegroundPathsEachSaveOnce() {
        XCTAssertEqual(savesFired(over: [.active, .background, .active]), 1,
                       "backgrounding without passing through .inactive must still save")
        XCTAssertEqual(savesFired(over: [.active, .inactive, .active]), 1,
                       "a Control Centre pull-down leaves the scene and comes back: one save, on the way out")
        XCTAssertEqual(savesFired(over: [.background, .inactive, .background]), 0,
                       "previewing a backgrounded app in the switcher never becomes active, so there is nothing to write")
    }

    /// Two round trips are two saves, not one — the gate is stateless, so a second departure with
    /// fresh work between them is not swallowed by the first.
    func testASecondDepartureSavesAgain() {
        let twice: [ScenePhase] = [.active, .inactive, .background, .inactive, .active,
                                   .inactive, .background, .inactive, .active]
        XCTAssertEqual(savesFired(over: twice), 2)
    }

    /// Counts what `ContentView`'s `onChange(of: scenePhase)` would do across a phase sequence.
    private func savesFired(over sequence: [ScenePhase]) -> Int {
        zip(sequence, sequence.dropFirst())
            .filter { ScenePhaseSaveGate.shouldSave(from: $0, to: $1) }
            .count
    }

    private func encodedKeys(of folder: FolderManifest) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(folder))
        guard let dictionary = object as? [String: Any] else { return [] }
        return Set(dictionary.keys)
    }

    // MARK: - Opening off the main thread (PERFORMANCE.md item 9(b))

    /// `loadInBackground` decodes off the main thread, and hands back the same document `load` does.
    ///
    /// **Two claims, and they fail in opposite ways.** That the decode is off main is the *whole
    /// point* of item 9(b) and is invisible to every other test in this file: revert the fan-out to a
    /// synchronous main-thread walk and every assertion about the loaded document still passes, which
    /// is exactly the shape of change that quietly comes back. `LoadProfile.decodedOnMainThread` is
    /// the flag that would not pass.
    ///
    /// That the *document* is identical is the claim the parallelism could break, and cel order is
    /// where it would break first: the fan-out is flat across the whole tree, so a layer's cels are
    /// finished in whatever order the cores get to them and are regrouped by index afterwards. Cel
    /// order is not cosmetic — `activeCelIndex` searches it and `addCel` maintains it with an explicit
    /// sort — so a shuffle would show up as the wrong drawing at a frame, some time later, with
    /// nothing to connect it to a load. Asserting the ids in order is what makes that loud now.
    func testLoadingInBackgroundDecodesOffTheMainThreadAndMatchesTheSynchronousLoad() async {
        let manager = makeManager()
        // Enough cels on one layer that order is observable rather than accidental — one cel per
        // layer would pass a shuffle.
        for start in [16, 20, 24, 28] {
            XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: start, frameCount: 2),
                          "Setup: layer 0 should take a cel at frame \(start)")
        }
        XCTAssertGreaterThan(manager.layers[0].cels.count, 4, "Setup: the ordering claim needs several cels")

        let url = projectURL()
        let written = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { written.fulfill() }
        await fulfillment(of: [written], timeout: 120)

        guard let synchronous = ProjectStore.load(from: url),
              let synchronousProfile = ProjectStore.lastLoadProfile else {
            return XCTFail("The saved package should load")
        }
        XCTAssertTrue(synchronousProfile.decodedOnMainThread,
                      "`load(from:)` is the blocking entry point — its callers read the result on the next line")

        guard let background = await ProjectStore.loadInBackground(from: url),
              let backgroundProfile = ProjectStore.lastLoadProfile else {
            return XCTFail("The saved package should also open through the background path")
        }
        XCTAssertFalse(backgroundProfile.decodedOnMainThread,
                       "`loadInBackground` exists to keep the per-cel decode off the main thread — item 9(b)")

        XCTAssertEqual(background.layers.map(\.id), synchronous.layers.map(\.id),
                       "layer order must survive the fan-out")
        for (index, pair) in zip(synchronous.layers, background.layers).enumerated() {
            XCTAssertEqual(pair.1.cels.map(\.id), pair.0.cels.map(\.id),
                           "layer \(index): cel order must survive the fan-out")
            XCTAssertEqual(pair.1.cels.map(\.startFrame), pair.0.cels.map(\.startFrame),
                           "layer \(index): cel start frames must survive the fan-out")
            XCTAssertEqual(pair.1.kind, pair.0.kind)
        }
        // The pixels, not only the bookkeeping: `makeManager` stamps ink on the first cel of the two
        // raster layers, and a decode that raced itself would most cheaply show up as a blank one.
        for layerIndex in 0..<2 {
            XCTAssertTrue(hasVisiblePixels(background.layers[layerIndex].cels[0]),
                          "layer \(layerIndex)'s stamped cel must come back with its pixels")
        }
        // The vector layer's display list is decoded on the same fan-out and is the other thing that
        // could come back empty.
        XCTAssertEqual(background.layers[2].cels[0].vector?.strokes.count,
                       synchronous.layers[2].cels[0].vector?.strokes.count)
        XCTAssertEqual(background.layers[2].cels[0].vector?.strokes.count, 1)
    }

    /// A single-cel document still loads through both paths — the fan-out runs inline below two jobs,
    /// and "the degenerate case took the other branch and broke" is the classic way that optimisation
    /// goes wrong.
    func testASingleCelDocumentLoadsThroughBothPaths() async {
        let manager = CanvasFixture.manager(layerCount: 1)
        let url = projectURL(name: "One Cel")
        let written = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { written.fulfill() }
        await fulfillment(of: [written], timeout: 120)

        XCTAssertEqual(ProjectStore.load(from: url)?.layers.first?.cels.count, 1)
        let background = await ProjectStore.loadInBackground(from: url)
        XCTAssertEqual(background?.layers.first?.cels.count, 1)
        XCTAssertEqual(background?.layers.count, 1)
    }

    // MARK: - The deferred thumbnail pass (PERFORMANCE.md item 9(c))

    /// The gallery's open does not walk every cel a second time to make thumbnails, and the pass that
    /// replaces it fills in every one.
    ///
    /// **Both halves are the test.** Deferring alone would be a regression dressed as an optimisation
    /// — a timeline of empty blocks is worse than a slower open — so "the open costs zero thumbnail
    /// rasterizes" is only worth asserting beside "and the backfill produces exactly as many as there
    /// are cels". `thumbnailRegenerationCount` is the same counter on both sides on purpose, which is
    /// what makes the two numbers comparable at all.
    func testTheGalleryOpenDefersThumbnailsAndTheBackfillFillsEveryOne() async {
        let manager = makeManager()
        for start in [16, 20, 24] {
            XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: start, frameCount: 2))
        }
        let url = projectURL()
        let written = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { written.fulfill() }
        await fulfillment(of: [written], timeout: 120)

        guard let opened = await ProjectStore.loadInBackground(from: url),
              let profile = ProjectStore.lastLoadProfile else {
            return XCTFail("The saved package should open through the gallery path")
        }
        let celCount = opened.layers.reduce(0) { $0 + $1.cels.count }
        XCTAssertGreaterThan(celCount, 4, "Setup: the deferral is only interesting with several cels")
        XCTAssertEqual(profile.thumbnailRegenerations, 0,
                       "the gallery's open must not walk every cel a second time — item 9(c)")
        XCTAssertNotNil(opened.thumbnailBackfillTask, "…and it must have started the pass that will")

        await opened.thumbnailBackfillTask?.value
        XCTAssertEqual(opened.thumbnailRegenerationCount, celCount,
                       "the backfill renders exactly one thumbnail per cel")
        for (layerIndex, layer) in opened.layers.enumerated() {
            for (celIndex, cel) in layer.cels.enumerated() {
                XCTAssertNotNil(cel.thumbnail,
                                "layer \(layerIndex) cel \(celIndex) is still on its placeholder after the backfill")
            }
        }
    }

    /// The pass leaves alone anything that already has a thumbnail — the half of the staleness guard
    /// that can be pinned without racing it.
    ///
    /// A cel the artist edits between the open and the pass gets a debounced regen of its own, and
    /// that regen's image is the newer one. If the backfill overwrote it, the artist would be looking
    /// at a picture of the drawing as it was before their stroke, indefinitely, with nothing to
    /// connect it to anything they did. So: same object, not merely an equal one.
    func testTheBackfillNeverOverwritesAThumbnailThatAlreadyExists() async {
        let manager = makeManager()
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 16, frameCount: 2))
        let url = projectURL()
        let written = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { written.fulfill() }
        await fulfillment(of: [written], timeout: 120)

        guard let opened = await ProjectStore.loadInBackground(from: url) else {
            return XCTFail("The saved package should open")
        }
        opened.thumbnailBackfillTask?.cancel()
        await opened.thumbnailBackfillTask?.value

        // Stand in for the debounced regen an edit would have scheduled.
        opened.regenerateThumbnail(layerIndex: 0, celIndex: 0)
        guard let alreadyThere = opened.layers[0].cels[0].thumbnail else {
            return XCTFail("Setup: the stand-in regen should have produced a thumbnail")
        }

        await opened.backfillMissingThumbnails()
        XCTAssertTrue(opened.layers[0].cels[0].thumbnail === alreadyThere,
                      "the backfill must not replace a thumbnail something newer already installed")
        // …and it still finishes the rest of the document.
        for (celIndex, cel) in opened.layers[0].cels.enumerated() {
            XCTAssertNotNil(cel.thumbnail, "layer 0 cel \(celIndex)")
        }
    }

    /// Running the pass twice costs nothing the second time: everything is filled, so nothing is
    /// rendered. The cheap guard against a backfill that re-renders the whole document whenever it is
    /// re-entered.
    func testASecondBackfillRendersNothing() async {
        let manager = makeManager()
        let url = projectURL()
        let written = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { written.fulfill() }
        await fulfillment(of: [written], timeout: 120)

        guard let opened = await ProjectStore.loadInBackground(from: url) else {
            return XCTFail("The saved package should open")
        }
        await opened.thumbnailBackfillTask?.value
        let afterFirst = opened.thumbnailRegenerationCount
        XCTAssertGreaterThan(afterFirst, 0, "Setup: the first pass must have rendered something")

        await opened.backfillMissingThumbnails()
        XCTAssertEqual(opened.thumbnailRegenerationCount, afterFirst,
                       "a second pass over a fully-populated document must render nothing")
    }

    // MARK: - The per-cel write runs over cores

    /// **Every cel's drawing comes back on that cel, and in that order**, after a save whose per-cel
    /// walk ran on several threads at once (`ProjectStore.writePackage`).
    ///
    /// This is the one property the fan-out could break quietly. A save that wrote the right bytes to
    /// the wrong cel, or assembled the manifest in completion order rather than in the document's,
    /// would still produce a package that validates, loads, and looks fully formed to every other
    /// test in this file — the artist would simply find their drawings shuffled between frames the
    /// next time they opened the project. Nothing here was covered before: the existing round-trip
    /// tests read `cels[0]`, and one cel per layer cannot show an ordering.
    ///
    /// Each cel carries a dot at a position derived from its own index, so "cel 7's ink is on cel 7"
    /// is checkable rather than merely "there are pixels somewhere".
    func testEveryCelsPixelsAndOrderSurviveTheParallelWrite() {
        let layerCount = 3, celsPerLayer = 5
        let manager = CanvasFixture.manager(layerCount: layerCount)
        manager.sceneFrameCount = celsPerLayer * 2

        /// Where cel `index`'s dot goes. Distinct per cel, comfortably inside the 64x64 fixture, and
        /// far enough apart that two cels' bounds cannot be confused for one another.
        func dotCentre(_ index: Int) -> CGPoint {
            CGPoint(x: 8 + CGFloat(index % celsPerLayer) * 11, y: 8 + CGFloat(index / celsPerLayer) * 11)
        }

        // Built directly rather than through `addCel`, which would refuse them: a layer's first cel
        // already spans every frame a second could start on.
        for layerIndex in 0..<layerCount {
            manager.layers[layerIndex].cels = (0..<celsPerLayer).map { celIndex in
                Cel(id: UUID(), startFrame: celIndex * 2, frameCount: 2,
                    raster: .empty(size: CanvasFixture.canvasSize))
            }
            for celIndex in 0..<celsPerLayer {
                let raster = manager.layers[layerIndex].cels[celIndex].raster
                raster.beginStroke()
                raster.stampCircle(at: dotCentre(layerIndex * celsPerLayer + celIndex), radius: 3,
                                   color: .red, alpha: 1, hardness: 1)
                raster.endStroke()
            }
        }

        let expectedIDs = manager.layers.map { $0.cels.map(\.id) }
        let expectedStarts = manager.layers.map { $0.cels.map(\.startFrame) }

        let url = projectURL(name: "Parallel Write")
        saveAndWait(manager, to: url)

        guard let reloaded = ProjectStore.load(from: url) else {
            return XCTFail("The saved package should load")
        }
        XCTAssertEqual(reloaded.layers.count, layerCount)

        for layerIndex in 0..<layerCount {
            let cels = reloaded.layers[layerIndex].cels
            XCTAssertEqual(cels.map(\.id), expectedIDs[layerIndex],
                           "Layer \(layerIndex)'s cels must come back in the order the document had them, not in the order the workers finished")
            XCTAssertEqual(cels.map(\.startFrame), expectedStarts[layerIndex],
                           "Layer \(layerIndex)'s cel timings must survive the write")

            for (celIndex, cel) in cels.enumerated() {
                guard let bounds = PixelOps.opaqueContentBounds(cel.raster.renderToUIImage()) else {
                    return XCTFail("Layer \(layerIndex) cel \(celIndex) came back empty — its PNG went somewhere else")
                }
                let centre = CGPoint(x: bounds.midX, y: bounds.midY)
                let wanted = dotCentre(layerIndex * celsPerLayer + celIndex)
                XCTAssertEqual(centre.x, wanted.x, accuracy: 2,
                               "Layer \(layerIndex) cel \(celIndex) is carrying another cel's drawing")
                XCTAssertEqual(centre.y, wanted.y, accuracy: 2,
                               "Layer \(layerIndex) cel \(celIndex) is carrying another cel's drawing")
            }
        }
    }

    // MARK: - A blank raster tier costs nothing (PERFORMANCE.md item 14)

    /// A document whose raster tier is untouched on some cels and drawn on others: layer 0 cel 0 is
    /// inked, layer 0 cel 1 is not, and the vector layer's cel never touches its raster tier at all.
    /// The owner's own package is the all-blank end of this, and mixing the two is what makes the
    /// per-cel decision visible rather than a whole-document one.
    private func mixedBlanknessManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.projectName = "Blank Tier"
        let inked = manager.layers[0].cels[0].raster
        inked.beginStroke()
        inked.stampCircle(at: CGPoint(x: 20, y: 24), radius: 6, color: .red, alpha: 1, hardness: 1)
        inked.endStroke()
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 12, frameCount: 2),
                      "Setup: layer 0 should take a second, undrawn cel at frame 12")
        manager.addVectorLayer()
        manager.layers[1].cels[0].vector?.addStroke(
            VectorStroke(brush: manager.selectedBrush,
                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                         size: 8, opacity: 1,
                         samples: [VectorSample(x: 10, y: 10, pressure: 1),
                                   VectorSample(x: 40, y: 40, pressure: 1)]))
        return manager
    }

    /// Every `<uuid>_raster.png` in the package, by file name.
    private func rasterPNGNames(at url: URL) -> Set<String> {
        let images = url.appendingPathComponent("images", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: images.path)) ?? []
        return Set(names.filter { $0.hasSuffix("_raster.png") })
    }

    /// The saved manifest's cel entries, flattened across layers, keyed by cel id — the JSON as it is
    /// on disk rather than as the encoder would hand it back, which is the only way to assert a key
    /// is genuinely absent.
    private func savedCelEntries(at url: URL,
                                 file: StaticString = #filePath, line: UInt = #line) -> [String: [String: Any]] {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let layers = json["layers"] as? [[String: Any]] else {
            XCTFail("The saved package should carry a manifest with a layers array", file: file, line: line)
            return [:]
        }
        var entries: [String: [String: Any]] = [:]
        for layer in layers {
            for cel in (layer["cels"] as? [[String: Any]]) ?? [] {
                if let id = cel["id"] as? String { entries[id] = cel }
            }
        }
        return entries
    }

    /// A canvas-sized image that is fully transparent except for one opaque pixel at `pixel` — or
    /// fully transparent if `pixel` is nil. **Exactly one pixel is the point**: the heal below decides
    /// whether to throw a bitmap away, and a check that downsampled or thumbnailed the image would
    /// round a single pixel of the artist's work out of existence.
    private func transparentImage(size: CGSize, opaquePixelAt pixel: CGPoint?) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            guard let pixel else { return }
            UIColor.red.setFill()
            ctx.fill(CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1))
        }
    }

    /// Turns a package this build wrote into one an older build would have written: the
    /// `rasterOmitted` key removed from every cel, and a real `_raster.png` put back at the name the
    /// manifest already carries. That is precisely the shape of the owner's live
    /// `Untitled 2.paintproj`, which has three cels each holding a 73,558-byte PNG whose alpha is
    /// min = max = 0.
    private func makeLegacyRasterPNGs(at url: URL, canvas: CGSize, opaquePixelAt pixel: CGPoint?,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let manifestURL = url.appendingPathComponent("manifest.json")
        let images = url.appendingPathComponent("images", isDirectory: true)
        guard let data = try? Data(contentsOf: manifestURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var layers = json["layers"] as? [[String: Any]] else {
            return XCTFail("The saved package should carry a manifest with a layers array", file: file, line: line)
        }
        let png = transparentImage(size: canvas, opaquePixelAt: pixel).pngData()
        for layerIndex in layers.indices {
            var cels = (layers[layerIndex]["cels"] as? [[String: Any]]) ?? []
            for celIndex in cels.indices {
                let omitted = cels[celIndex]["rasterOmitted"] as? Bool == true
                cels[celIndex].removeValue(forKey: "rasterOmitted")
                guard omitted, let name = cels[celIndex]["rasterFileName"] as? String, let png else { continue }
                try? png.write(to: images.appendingPathComponent(name))
            }
            layers[layerIndex]["cels"] = cels
        }
        json["layers"] = layers
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            return XCTFail("The legacy manifest should re-encode", file: file, line: line)
        }
        try? rewritten.write(to: manifestURL)
    }

    /// **(a) A cel nobody has drawn on pays for nothing.** No `_raster.png`, `rasterOmitted: true` in
    /// the manifest, and a reload that is otherwise the same document — same cels, same order, same
    /// pixels on the cel that has some.
    ///
    /// **(e) is folded in here on purpose**: the first thing asserted is that the package committed at
    /// all. `ProjectStore.writeAtomically` validates its own staged package before swapping it in, and
    /// on failure moves it to Trash and returns *while still firing the completion handler* — so a
    /// validator that had not been taught about `rasterOmitted` would make every save of this document
    /// silently do nothing, and a test that only inspected the loaded model would go on passing
    /// against a package from before the change.
    func testACelWhoseRasterTierWasNeverDrawnOnWritesNoPNGAndStillReloads() {
        let manager = mixedBlanknessManager()
        let inkedCelID = manager.layers[0].cels[0].id
        let blankCelID = manager.layers[0].cels[1].id
        let vectorCelID = manager.layers[1].cels[0].id
        let url = projectURL(name: "Blank Tier")
        saveAndWait(manager, to: url)

        // The save committed — see the doc comment. Without this the rest is vacuous.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "The save must have swapped a package into the live path, not trashed its stage")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "A package whose blank cels omit their raster PNG is intact, not damaged")

        let pngs = rasterPNGNames(at: url)
        XCTAssertEqual(pngs, ["\(inkedCelID.uuidString)_raster.png"],
                       "Only the cel with pixels pays for a raster PNG")

        let entries = savedCelEntries(at: url)
        XCTAssertNil(entries[inkedCelID.uuidString]?["rasterOmitted"],
                     "A cel that wrote its PNG must not claim the raster was omitted")
        XCTAssertEqual(entries[blankCelID.uuidString]?["rasterOmitted"] as? Bool, true)
        XCTAssertEqual(entries[vectorCelID.uuidString]?["rasterOmitted"] as? Bool, true,
                       "A vector cel's raster tier is untouched too — this is the owner's whole document")
        XCTAssertNotNil(entries[blankCelID.uuidString]?["rasterFileName"] as? String,
                        "The name the file would have had stays in the manifest — see CelManifest.rasterOmitted")

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }
        XCTAssertEqual(reloaded.layers.count, 2)
        XCTAssertEqual(reloaded.layers[0].cels.map(\.startFrame), [0, 12])
        XCTAssertEqual(reloaded.layers[0].cels.map(\.id), [inkedCelID, blankCelID])
        XCTAssertTrue(hasVisiblePixels(reloaded.layers[0].cels[0]), "the inked cel keeps its pixels")
        XCTAssertFalse(hasVisiblePixels(reloaded.layers[0].cels[1]), "the blank cel comes back transparent")
        XCTAssertEqual(reloaded.layers[1].cels[0].vector?.strokes.count, 1,
                       "the vector artwork is untouched by any of this")
        // The point of the whole change: no bitmap was allocated for the cels that had none.
        XCTAssertFalse(reloaded.layers[0].cels[1].raster.hasContent)
        XCTAssertFalse(reloaded.layers[1].cels[0].raster.hasContent)
        XCTAssertTrue(reloaded.layers[0].cels[0].raster.hasContent)
    }

    /// **(b) The artwork-loss guard.** One non-transparent pixel in a canvas of nothing is still
    /// artwork: the PNG is written, `rasterOmitted` is absent, and the pixel is in the same place
    /// after a round trip. This is the assertion that fails if the "is this cel blank?" question is
    /// ever answered by a sampled, scaled or heuristic scan instead of by the bitmap's existence.
    func testACelWithOneNonTransparentPixelKeepsItsPNGAndItsPixel() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let canvas = try XCTUnwrap(manager.canvasSize)
        let cel = manager.layers[0].cels[0]
        cel.raster.reset(to: transparentImage(size: canvas, opaquePixelAt: CGPoint(x: 41, y: 17)),
                         strokeCount: 1)
        let url = projectURL(name: "One Pixel")
        saveAndWait(manager, to: url)

        XCTAssertEqual(rasterPNGNames(at: url), ["\(cel.id.uuidString)_raster.png"],
                       "A cel with one opaque pixel writes its PNG like any other")
        XCTAssertNil(savedCelEntries(at: url)[cel.id.uuidString]?["rasterOmitted"])

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("The package should load") }
        guard let bounds = PixelOps.opaqueContentBounds(reloaded.layers[0].cels[0].raster.renderToUIImage()) else {
            return XCTFail("The single opaque pixel did not survive the round trip — this is artwork loss")
        }
        XCTAssertEqual(bounds.midX, 41.5, accuracy: 1)
        XCTAssertEqual(bounds.midY, 17.5, accuracy: 1)
        XCTAssertTrue(reloaded.layers[0].cels[0].raster.hasContent)
    }

    /// **(c) The legacy heal.** A package written before this change carries a canvas-sized fully
    /// transparent PNG for every undrawn cel. Loading one must not leave the 16 MiB bitmap resident,
    /// and — the half that makes it a heal rather than a saving — re-saving it must omit the file, so
    /// a document that exists today becomes cheap on its next open-and-save instead of paying forever.
    func testALegacyPackagesBlankRasterPNGIsDroppedOnLoadAndNotWrittenBackOut() throws {
        let manager = mixedBlanknessManager()
        let canvas = try XCTUnwrap(manager.canvasSize)
        let blankCelID = manager.layers[0].cels[1].id
        let inkedCelID = manager.layers[0].cels[0].id
        let url = projectURL(name: "Legacy Blank")
        saveAndWait(manager, to: url)
        makeLegacyRasterPNGs(at: url, canvas: canvas, opaquePixelAt: nil)

        // The fixture really is the old shape: a PNG on disk and no flag in the manifest.
        XCTAssertEqual(rasterPNGNames(at: url).count, 3, "every cel should have a PNG again")
        XCTAssertNil(savedCelEntries(at: url)[blankCelID.uuidString]?["rasterOmitted"])
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("A legacy package must load") }
        let healed = reloaded.layers[0].cels[1]
        XCTAssertFalse(healed.raster.hasContent,
                       "A transparent legacy PNG must not leave a canvas-sized bitmap resident")
        XCTAssertEqual(healed.raster.strokeCount, 0)
        XCTAssertTrue(healed.isCertainlyBlank,
                      "A cel proved pixel-blank should say so, so the onion skin can skip it")
        XCTAssertTrue(reloaded.layers[0].cels[0].raster.hasContent, "the inked cel keeps its bitmap")

        // The heal, out the other side: re-saving the reloaded document drops the file for good.
        let resaved = projectURL(name: "Legacy Blank Resaved")
        saveAndWait(reloaded, to: resaved)
        XCTAssertEqual(rasterPNGNames(at: resaved), ["\(inkedCelID.uuidString)_raster.png"],
                       "A healed cel must not write its transparent PNG back out")
        XCTAssertEqual(savedCelEntries(at: resaved)[blankCelID.uuidString]?["rasterOmitted"] as? Bool, true)
    }

    /// **(c), the counterpart, and it is the one that matters most.** The same legacy package with a
    /// single opaque pixel in each PNG keeps its bitmap and keeps the pixel. If the scan is ever made
    /// cheap by sampling or scaling, this is the test that goes red.
    func testALegacyPackageWithOneOpaquePixelKeepsItsBitmapAndItsPixel() throws {
        let manager = mixedBlanknessManager()
        let canvas = try XCTUnwrap(manager.canvasSize)
        let blankCelID = manager.layers[0].cels[1].id
        let url = projectURL(name: "Legacy Pixel")
        saveAndWait(manager, to: url)
        makeLegacyRasterPNGs(at: url, canvas: canvas, opaquePixelAt: CGPoint(x: 5, y: 60))

        guard let reloaded = ProjectStore.load(from: url) else { return XCTFail("A legacy package must load") }
        let cel = reloaded.layers[0].cels[1]
        XCTAssertEqual(cel.id, blankCelID)
        XCTAssertTrue(cel.raster.hasContent, "One opaque pixel is artwork — the bitmap must be kept")
        guard let bounds = PixelOps.opaqueContentBounds(cel.raster.renderToUIImage()) else {
            return XCTFail("The single opaque pixel was scanned away — this is artwork loss")
        }
        XCTAssertEqual(bounds.midX, 5.5, accuracy: 1)
        XCTAssertEqual(bounds.midY, 60.5, accuracy: 1)

        // And it survives the next save, which is where a mistaken heal would actually destroy it.
        let resaved = projectURL(name: "Legacy Pixel Resaved")
        saveAndWait(reloaded, to: resaved)
        XCTAssertTrue(rasterPNGNames(at: resaved).contains("\(blankCelID.uuidString)_raster.png"))
        guard let again = ProjectStore.load(from: resaved) else { return XCTFail("The re-save should load") }
        XCTAssertNotNil(PixelOps.opaqueContentBounds(again.layers[0].cels[1].raster.renderToUIImage()),
                        "The pixel must survive a second round trip too")
    }

    /// **(f) The legacy skip is untouched.** A manifest from the previous PencilKit engine has no
    /// `rasterFileName` key at all, and `CelManifest` failing to decode is what makes the gallery skip
    /// those projects rather than open them as blank documents. `rasterOmitted` was added as a
    /// separate optional key — instead of making `rasterFileName` optional, which would have been the
    /// obvious implementation — precisely so this stays true, and nothing else in the suite pins it.
    func testAPencilKitEraCelManifestWithNoRasterFileNameStillFailsToDecode() throws {
        let legacy = Data(#"{"id":"\#(UUID().uuidString)","startFrame":0,"frameCount":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CelManifest.self, from: legacy),
                             "A manifest with no rasterFileName must not decode — the gallery skips those projects")

        // And the new key on its own does not rescue it, which is the mistake worth pinning.
        let legacyWithFlag = Data(#"{"id":"\#(UUID().uuidString)","startFrame":0,"frameCount":1,"rasterOmitted":true}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CelManifest.self, from: legacyWithFlag))

        // The control: the same JSON with the key present decodes, so the assertions above are about
        // the missing key and not about the rest of the literal.
        let modern = Data(#"{"id":"\#(UUID().uuidString)","startFrame":0,"frameCount":1,"rasterFileName":"a.png","rasterOmitted":true}"#.utf8)
        let decoded = try JSONDecoder().decode(CelManifest.self, from: modern)
        XCTAssertEqual(decoded.rasterFileName, "a.png")
        XCTAssertEqual(decoded.rasterOmitted, true)
    }

    /// A cel manifest written before this change has no `rasterOmitted` key and must decode to nil —
    /// meaning "look for the file", which is what keeps every existing package loading unchanged.
    func testACelManifestWithoutTheRasterOmittedKeyDecodesAsNil() throws {
        let json = Data(#"{"id":"\#(UUID().uuidString)","startFrame":0,"frameCount":1,"rasterFileName":"a.png"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(CelManifest.self, from: json).rasterOmitted)
    }

    /// A cel that wrote its PNG writes no `rasterOmitted` key at all, so a manifest does not grow a
    /// key per cel on a document where nothing was saved. Same discipline as
    /// `testAnOrdinaryFolderWritesNoCompositorRoleKey`.
    func testACelThatWroteItsRasterWritesNoRasterOmittedKey() throws {
        let manifest = CelManifest(id: UUID(), startFrame: 0, frameCount: 1, rasterFileName: "r.png")
        let json = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
        XCTAssertFalse(json.contains("\"rasterOmitted\""))
    }
}
