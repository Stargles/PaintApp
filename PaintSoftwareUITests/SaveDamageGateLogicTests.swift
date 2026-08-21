import XCTest
import UIKit
import SwiftUI

/// Pure-logic tests for the owner's 2026-08-21 ruling on saving a project that opened with something
/// unreadable: **prompt once, then remember.**
///
/// Run against a per-test temp directory via `ProjectBackupManager.rootDirectoryOverride`, with real
/// packages written by `ProjectStore.save`, damaged on disk by hand, and reopened by
/// `ProjectStore.load` — no app launch and no simulator gestures. `Services/ProjectStore.swift`,
/// `Services/SaveDamageGate.swift` and `Engine/VectorLayer.swift` are compiled directly into this
/// test bundle (see `BackupManagerLogicTests`' header for why `@testable import` can't be used in
/// this target).
///
/// **The damage is made by editing the JSON, not by constructing a `DecodeReport`.** A test that
/// hands the gate a hand-built report proves the gate branches correctly and proves nothing about
/// whether a damaged file on disk ever reaches it — which is the half that did not exist before this
/// branch, since the report used to die in a log line inside `decodeCel`. So every case here starts
/// from bytes.
///
/// The class is `@MainActor` because `save`/`load` are; `wait(for:)` spins the run loop, which is what
/// lets the completion handler's main-actor hop run.
@MainActor
final class SaveDamageGateLogicTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-damage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        ProjectBackupManager.maxAutosaveBackupsPerProject = 5
        ProjectBackupManager.maxUnsavedBackupsPerProject = 5
    }

    override func tearDownWithError() throws {
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    // MARK: - Fixtures

    /// One raster layer and one vector layer carrying two real strokes and a fill, so the saved
    /// package has a `<cel>_vector.json` with a display list long enough to damage one entry of and
    /// still have survivors.
    private func makeManager(vectorLayerName: String = "Ink") -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.projectName = "Damaged"
        manager.addVectorLayer()
        manager.layers[1].name = vectorLayerName
        manager.layers[1].hasCustomName = true

        let canvas = manager.layers[1].cels[0].vector
        XCTAssertNotNil(canvas, "Setup: a vector layer's cel should carry a VectorCanvas")
        canvas?.addStroke(stroke(from: CGPoint(x: 4, y: 4), to: CGPoint(x: 30, y: 30), brush: manager.selectedBrush))
        canvas?.addStroke(stroke(from: CGPoint(x: 8, y: 40), to: CGPoint(x: 40, y: 8), brush: manager.selectedBrush))
        return manager
    }

    private func stroke(from a: CGPoint, to b: CGPoint, brush: Brush) -> VectorStroke {
        VectorStroke(brush: brush,
                     color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                     size: 6, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)])
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL,
                             intent: SaveIntent = .artist,
                             file: StaticString = #filePath, line: UInt = #line) -> SaveDecision {
        let finished = expectation(description: "ProjectStore.save completion")
        let decision = ProjectStore.save(manager, to: url, intent: intent) { finished.fulfill() }
        if decision == .ask {
            finished.fulfill() // nothing was dispatched; the expectation is not what this case is about
        }
        wait(for: [finished], timeout: 30)
        return decision
    }

    /// A project on disk, saved and settled, with its vector payload ready to be damaged.
    private func writtenProject(vectorLayerName: String = "Ink") -> URL {
        let manager = makeManager(vectorLayerName: vectorLayerName)
        let url = ProjectStore.createNewProjectURL(name: "Damaged")
        XCTAssertEqual(saveAndWait(manager, to: url), .write, "Setup: a clean project saves normally")
        return url
    }

    private func vectorPayloadURL(in projectURL: URL) throws -> URL {
        let images = projectURL.appendingPathComponent("images", isDirectory: true)
        let contents = try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)
        let payloads = contents.filter { $0.lastPathComponent.hasSuffix("_vector.json") }
        XCTAssertEqual(payloads.count, 1, "Setup: exactly one vector cel was written")
        return try XCTUnwrap(payloads.first)
    }

    /// Rewrites the persisted display list, so a test states its damage in the file's own terms.
    private func rewriteElements(at payloadURL: URL, _ mutate: (inout [[String: Any]]) -> Void) throws {
        let data = try Data(contentsOf: payloadURL)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var elements = try XCTUnwrap(object["elements"] as? [[String: Any]])
        mutate(&elements)
        object["elements"] = elements
        try JSONSerialization.data(withJSONObject: object).write(to: payloadURL)
    }

    /// A stroke this build knows how to read and cannot: the discriminator is intact and the payload
    /// is nonsense. This is *damage* — the artist drew it and it is gone.
    private func breakFirstStroke(in projectURL: URL) throws {
        try rewriteElements(at: try vectorPayloadURL(in: projectURL)) { elements in
            elements[0] = ["kind": "stroke", "stroke": ["not": "a stroke"]]
        }
    }

    /// An element written by a build that has a feature this one does not. **Not damage** — see
    /// `ProjectLoadDamage`. `"video"` is the sentinel `VectorCanvasDataLogicTests` already uses, for
    /// its reason: a sentinel has to be a kind nothing implements.
    private func insertUnknownKind(in projectURL: URL) throws {
        try rewriteElements(at: try vectorPayloadURL(in: projectURL)) { elements in
            elements.append(["kind": "video", "video": ["fileName": "clip.mov"]])
        }
    }

    /// Bytes of the whole package, keyed by relative path — the way to say "the project file was not
    /// touched" without trusting a modification date.
    private func packageBytes(at url: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return result }
        for case let file as URL in walker {
            guard let data = try? Data(contentsOf: file) else { continue }
            result[file.path.replacingOccurrences(of: url.path, with: "")] = data
        }
        return result
    }

    // MARK: - The gate itself

    /// The whole ruling as a truth table, with no file system in the way. Every other test in this
    /// file exists to prove the inputs reach here honestly.
    func testTheGateAsksOnlyAnArtistSaveOnlyOnceAndOnlyWhenDamaged() {
        let clean = ProjectLoadDamage()
        var damaged = ProjectLoadDamage()
        damaged.add(ProjectLoadDamage.LayerDamage(layerName: "Ink", brushStrokes: 1))

        XCTAssertEqual(SaveDamageGate.decide(damage: clean, answered: false, intent: .artist), .write,
                       "A clean document never asks — this is every ordinary save in the app")
        XCTAssertEqual(SaveDamageGate.decide(damage: clean, answered: false, intent: .automatic), .write)

        XCTAssertEqual(SaveDamageGate.decide(damage: damaged, answered: false, intent: .artist), .ask,
                       "The first artist-initiated save on a damaged document is the one prompt the ruling allows")
        XCTAssertEqual(SaveDamageGate.decide(damage: damaged, answered: false, intent: .automatic), .writeAside,
                       "An automatic save never blocks: it writes a version and leaves the project alone")

        XCTAssertEqual(SaveDamageGate.decide(damage: damaged, answered: true, intent: .artist), .write,
                       "'Then remember' — answered once, and the document saves normally forever after")
        XCTAssertEqual(SaveDamageGate.decide(damage: damaged, answered: true, intent: .automatic), .write)
    }

    // MARK: - The control: a clean project is untouched by any of this

    /// **Without this, a prompt that never fires passes every other test in the file for free.**
    func testACleanProjectReportsNoDamageAndSavesExactlyAsBefore() throws {
        let url = writtenProject()
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        XCTAssertFalse(reopened.loadDamage.isDamaged, "A project that opened whole has nothing to report")
        XCTAssertEqual(reopened.loadDamage.layers, [], "…and nothing per-layer either")
        XCTAssertEqual(reopened.loadDamage.summary, "", "A clean load has no sentence to say")
        XCTAssertFalse(reopened.damagedSaveAnswered, "Nothing has been asked, so nothing has been answered")

        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .artist), .write,
                       "An artist save on a clean project writes the project, with no question asked")
        XCTAssertTrue(ProjectBackupManager.validateProject(at: url))
    }

    // MARK: - What counts as unreadable

    func testAMalformedStrokeIsCountedAgainstTheLayerTheArtistNamedIt() throws {
        let url = writtenProject(vectorLayerName: "Ink")
        try breakFirstStroke(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        XCTAssertTrue(reopened.loadDamage.isDamaged)
        XCTAssertEqual(reopened.loadDamage.layers.count, 1, "Only the vector layer lost anything")
        let layer = try XCTUnwrap(reopened.loadDamage.layers.first)
        XCTAssertEqual(layer.layerName, "Ink", "The layer is named the way the layer panel names it")
        XCTAssertEqual(layer.brushStrokes, 1, "The discriminator survived, so the loss can be named as a stroke")
        XCTAssertEqual(layer.unnamed, 0, "…and therefore does not fall back to the anonymous bucket")
        XCTAssertEqual(layer.total, 1)

        // The rest of the cel is still there, which is the property `ADD_TEXT.md` stage 2 bought and
        // this branch must not spend: one unreadable entry costs that entry.
        let survivors = try XCTUnwrap(reopened.layers[1].cels[0].vector).elements
        XCTAssertEqual(survivors.count, 1, "The second stroke loaded fine")
    }

    /// The ruling pinned in the direction it is easiest to get wrong. An element this build has no
    /// case for is a *newer file in an older binary*: expected, benign, nothing was on screen to lose,
    /// and the artist has no action to take. Prompting on it would mean a banner at every open of a
    /// file that is working exactly as designed.
    func testAnUnknownKindFromANewerBuildIsNotDamageAndDoesNotAsk() throws {
        let url = writtenProject()
        try insertUnknownKind(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        XCTAssertFalse(reopened.loadDamage.isDamaged,
                       "Forward compatibility working as designed is not damage and must never prompt")
        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .artist), .write,
                       "…so the save proceeds without a question")
    }

    /// The two live side by side in one file, and the counting has to tell them apart there too —
    /// otherwise a project with any version gap at all would drag its malformed entries into silence,
    /// or its benign ones into a prompt.
    func testAMalformedEntryBesideAnUnknownOneCountsOnlyTheMalformedOne() throws {
        let url = writtenProject()
        try rewriteElements(at: try vectorPayloadURL(in: url)) { elements in
            elements[0] = ["kind": "stroke", "stroke": ["not": "a stroke"]]
            elements.append(["kind": "video", "video": ["fileName": "clip.mov"]])
        }
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        XCTAssertEqual(reopened.loadDamage.itemCount, 1,
                       "One malformed stroke is one loss; the unknown kind beside it is not counted")
        XCTAssertEqual(reopened.loadDamage.layers.first?.brushStrokes, 1)
    }

    /// A vector payload that is not a payload at all costs the cel every mark on it — the largest of
    /// the three losses, and the one `validateProject` cannot catch, because the file is *present*.
    func testAVectorPayloadThatWillNotParseIsCountedAsAWholeDrawing() throws {
        let url = writtenProject()
        try Data("this is not a vector payload".utf8).write(to: try vectorPayloadURL(in: url))
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        let layer = try XCTUnwrap(reopened.loadDamage.layers.first)
        XCTAssertEqual(layer.drawings, 1)
        XCTAssertEqual(reopened.loadDamage.summary,
                       "1 whole drawing on the Ink layer could not be read when this project opened.")
    }

    // MARK: - Which saves prompt

    func testAnArtistSaveOnADamagedProjectAsksAndWritesNothing() throws {
        let url = writtenProject()
        try breakFirstStroke(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        let before = packageBytes(at: url)

        var completionRan = false
        let decision = ProjectStore.save(reopened, to: url, intent: .artist) { completionRan = true }

        XCTAssertEqual(decision, .ask, "The first artist save on a damaged document asks")
        XCTAssertFalse(completionRan,
                       "…and holds its completion, so the editor stays put instead of jumping to the gallery")
        XCTAssertEqual(packageBytes(at: url), before,
                       "Nothing at all is written while the question is open — this is the whole ruling")
    }

    /// The rule the design is arranged around: a modal over an app being backgrounded is unacceptable
    /// and may not even be presentable, and refusing the save would lose the artist's last edits to
    /// the next jetsam kill. So it writes — somewhere else.
    func testAnAutomaticSaveNeverBlocksAndNeverPromptsOnADamagedProject() throws {
        let url = writtenProject()
        try breakFirstStroke(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        let before = packageBytes(at: url)

        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .automatic), .writeAside,
                       "Backgrounding is never allowed to stop and ask")
        XCTAssertEqual(packageBytes(at: url), before,
                       "…and it does not overwrite the damaged original either, since nobody has ruled on it")
        XCTAssertFalse(reopened.damagedSaveAnswered,
                       "An automatic save is not an answer — the artist is still owed the question")

        let versions = ProjectBackupManager.listBackups(forProjectAt: url)
        XCTAssertEqual(versions.filter { $0.label == "Unsaved changes" }.count, 1,
                       "The work landed in the project's own version history, where the gallery already shows it")
    }

    // MARK: - Then remember

    func testOnceAnsweredNeitherThisSaveNorTheNextOneAsksAgain() throws {
        let url = writtenProject()
        try breakFirstStroke(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(ProjectStore.save(reopened, to: url, intent: .artist), .ask, "Setup: the first save asks")

        // What "Save Anyway" does, and the order matters: answered first, then the save.
        reopened.damagedSaveAnswered = true
        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .artist), .write)
        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .artist), .write,
                       "A prompt on every save would be worse than no prompt at all")
        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .automatic), .write,
                       "…and an autosave after the answer is an ordinary save again")
    }

    /// Why "remember" does not need to be persisted: Save Anyway rewrites the package *without* the
    /// entries it could not read, so the next load of that project reports clean and there is nothing
    /// left to ask about. A relaunch cannot lose a warning that no longer applies.
    func testSavingAnywayHealsTheDocumentSoAReopenHasNothingToAsk() throws {
        let url = writtenProject()
        try breakFirstStroke(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertTrue(reopened.loadDamage.isDamaged, "Setup")

        reopened.damagedSaveAnswered = true
        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .artist), .write)

        let afterAnswer = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertFalse(afterAnswer.loadDamage.isDamaged,
                       "The damaged entry is no longer in the file, so a fresh launch has nothing to report")
        XCTAssertFalse(afterAnswer.damagedSaveAnswered,
                       "…and the in-memory answer is gone with the old document, which is exactly right")
    }

    /// The other half: a *cancel* leaves the damage on disk, so the next open asks again. The artist
    /// declined to decide, and a document that is still broken has to keep being a question.
    func testCancellingLeavesTheDamageOnDiskSoTheNextOpenAsksAgain() throws {
        let url = writtenProject()
        try breakFirstStroke(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(ProjectStore.save(reopened, to: url, intent: .artist), .ask, "Setup: the first save asks")

        // What "Cancel" does — the same save with the automatic destination.
        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .automatic), .writeAside)

        let nextSession = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertTrue(nextSession.loadDamage.isDamaged)
        XCTAssertEqual(ProjectStore.save(nextSession, to: url, intent: .artist), .ask)
    }

    // MARK: - What Cancel actually does with the artist's work

    /// **Cancel cannot mean "lose the artist's edits."** It means "do not overwrite the original" —
    /// and this asserts where the work goes instead, because a promise about a path nobody checked is
    /// how the original silent-loss bug happened in the first place.
    func testCancelKeepsTheOriginalAndTheEditsAreRecoverableFromTheVersionHistory() throws {
        let url = writtenProject()
        try breakFirstStroke(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        let originalBytes = packageBytes(at: url)
        let layersBefore = reopened.layers.count

        // An edit made after the damaged open, which is the thing that must survive.
        let idsBefore = Set(reopened.layers.map(\.id))
        reopened.addLayer()
        let addedIndex = try XCTUnwrap(reopened.layers.firstIndex { !idsBefore.contains($0.id) })
        reopened.layers[addedIndex].name = "Drawn After Opening"
        reopened.layers[addedIndex].hasCustomName = true

        XCTAssertEqual(saveAndWait(reopened, to: url, intent: .automatic), .writeAside)

        XCTAssertEqual(packageBytes(at: url), originalBytes,
                       "The project file is byte-for-byte what it was — that is what Cancel promised")

        let aside = try XCTUnwrap(ProjectBackupManager.listBackups(forProjectAt: url)
            .first { $0.label == "Unsaved changes" })
        XCTAssertTrue(aside.isValid, "A version the artist cannot restore is not a place to put their work")
        let recovered = try XCTUnwrap(ProjectStore.load(from: aside.url))
        XCTAssertEqual(recovered.layers.count, layersBefore + 1)
        XCTAssertTrue(recovered.layers.contains { $0.name == "Drawn After Opening" },
                      "The edit made after the damaged open is in the recovered package")
    }

    /// Rotation applies to these slots too, so an artist who keeps backgrounding a damaged project
    /// without ever answering cannot grow its history without bound.
    func testUnsavedChangeSlotsRotate() throws {
        ProjectBackupManager.maxUnsavedBackupsPerProject = 2
        let url = writtenProject()
        try breakFirstStroke(in: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        for _ in 0..<4 {
            XCTAssertEqual(saveAndWait(reopened, to: url, intent: .automatic), .writeAside)
        }
        XCTAssertEqual(ProjectBackupManager.listBackups(forProjectAt: url).filter { $0.label == "Unsaved changes" }.count, 2)
    }

    // MARK: - What the banner says

    func testTheSentenceIsCountsAndLayerNamesRatherThanDecoderVocabulary() {
        var one = ProjectLoadDamage()
        one.add(ProjectLoadDamage.LayerDamage(layerName: "Ink", brushStrokes: 1))
        XCTAssertEqual(one.summary, "1 brush stroke on the Ink layer could not be read when this project opened.")

        var mixed = ProjectLoadDamage()
        mixed.add(ProjectLoadDamage.LayerDamage(layerName: "Ink", brushStrokes: 2, fills: 1))
        XCTAssertEqual(mixed.summary,
                       "2 brush strokes and 1 fill on the Ink layer could not be read when this project opened.")

        var two = ProjectLoadDamage()
        two.add(ProjectLoadDamage.LayerDamage(layerName: "Ink", brushStrokes: 2))
        two.add(ProjectLoadDamage.LayerDamage(layerName: "Colour", drawings: 1))
        XCTAssertEqual(two.summary,
                       "2 brush strokes on the Ink layer and 1 whole drawing on the Colour layer could not be read when this project opened.")

        var many = ProjectLoadDamage()
        many.add(ProjectLoadDamage.LayerDamage(layerName: "Ink", brushStrokes: 2))
        many.add(ProjectLoadDamage.LayerDamage(layerName: "Colour", fills: 1))
        many.add(ProjectLoadDamage.LayerDamage(layerName: "Shadow", images: 3))
        many.add(ProjectLoadDamage.LayerDamage(layerName: "Highlight", texts: 1))
        XCTAssertEqual(many.summary,
                       "2 brush strokes on the Ink layer, 1 fill on the Colour layer and 4 more items on 2 other layers could not be read when this project opened.")
        XCTAssertEqual(many.itemCount, 7)
    }

    /// An entry broken at its own discriminator has no noun, and inventing one would be a claim the
    /// file cannot support. It is still counted, because the artist lost it either way.
    func testAMarkWhoseKindIsAlsoUnreadableIsCountedWithoutBeingNamed() throws {
        let url = writtenProject()
        try rewriteElements(at: try vectorPayloadURL(in: url)) { elements in
            elements[0] = ["stroke": ["not": "a stroke"]] // no `kind` at all
        }
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))

        let layer = try XCTUnwrap(reopened.loadDamage.layers.first)
        XCTAssertEqual(layer.unnamed, 1)
        XCTAssertEqual(layer.brushStrokes, 0)
        XCTAssertEqual(reopened.loadDamage.summary,
                       "1 mark on the Ink layer could not be read when this project opened.")
    }
}
