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
}
