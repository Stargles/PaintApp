import XCTest
import UIKit
import AVFoundation

/// Pure-logic tests for VIDEO.md §8 stage 8 — `CanvasManager.bakeVideoToCels`, the verb behind the
/// timeline's "Bake to Images" row.
///
/// **Reachability is asked of the real verbs, not assumed.** `testAFreshDocumentReachesBakeOnlyAfterAnActualImport`
/// walks a brand-new document through `CanvasManager.insertVideo` — the same call the artist's own
/// `PhotosPicker` flow makes — rather than splicing a `VectorVideoElement` into `layers` by hand,
/// which is exactly the shortcut CLAUDE.md's "drive it before you call it done" section names as
/// the way three earlier features shipped unusable while every test on them stayed green.
///
/// **Every clip is generated at test time** with the app's own `VideoFrameWriter`, mirroring
/// `VideoFrameReaderLogicTests`: a flat grey frame names its own index, so a decoded picture can be
/// told apart from its neighbours by one pixel rather than by trusting that *something* arrived.
@MainActor
final class VideoBakeLogicTests: XCTestCase {

    private static let levels: [UInt8] = [40, 90, 140, 190, 230, 255]

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-bake-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
    }

    override func tearDownWithError() throws {
        VideoImportStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - Fixtures

    private func clip(named name: String = "clip", frames: Int = VideoBakeLogicTests.levels.count) throws -> URL {
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).mp4")
        let levels = (0..<frames).map { Self.levels[$0 % Self.levels.count] }
        try CanvasFixture.writeGreyClip(levels: levels, fps: 24, side: 64, to: url)
        return url
    }

    private static var levelsCount: Int { levels.count }

    /// `CanvasFixture.celLayout` returns `[(start: Int, length: Int)]`, and a bare tuple is not
    /// `Equatable` — every existing use of it compares `.map(\.start)` and `.map(\.length)`
    /// separately. This folds both into one `[[Int]]` so a "nothing changed" assertion can be one
    /// line instead of two.
    private func layoutFingerprint(_ manager: CanvasManager, layerIndex: Int = 0) -> [[Int]] {
        CanvasFixture.celLayout(manager, layerIndex: layerIndex).map { [$0.start, $0.length] }
    }

    /// A stroke to plant alongside a video, exactly `VideoElementLogicTests`' own
    /// `managerHoldingAVideo` fixture does — "the stroke so a dropped video has something beside it
    /// to fail to take with it", read here as "something beside it whose id a bake must not repeat".
    private func stroke() -> VectorStroke {
        VectorStroke(brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                     size: 6, opacity: 1,
                     samples: [VectorSample(x: 4, y: 4, pressure: 1),
                               VectorSample(x: 40, y: 40, pressure: 1)])
    }

    /// The one video element on `manager`'s newest (vector) layer, cel 0 — the shape every
    /// `insertVideo` call produces.
    private func importedVideo(_ manager: CanvasManager) throws -> (layerIndex: Int, video: VectorVideoElement) {
        let layerIndex = manager.layers.count - 1
        let video = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector?.videos.first)
        return (layerIndex, video)
    }

    // MARK: - Cold-start reachability

    /// **The chain a real artist walks, with no step skipped and no state hand-built.** A fresh
    /// document cannot bake anything — there is no video anywhere yet — and the *only* thing that
    /// changes that is the same `insertVideo` call the Actions menu's `PhotosPicker` handler makes.
    /// If reaching Bake ever came to need some *other* precondition only Bake itself could create,
    /// this is the test that would catch it going stale.
    func testAFreshDocumentReachesBakeOnlyAfterAnActualImport() throws {
        let manager = CanvasFixture.manager(layerCount: 1)

        switch manager.bakeVideoToCels(layerIndex: 0, celIndex: 0) {
        case .baked: XCTFail("A fresh document's only cel holds no video and must refuse.")
        case .refused(let reason): XCTAssertEqual(reason, .noVideo)
        }

        XCTAssertTrue(manager.insertVideo(at: try clip()),
                      "Setup: the real import verb should succeed on a fresh document.")

        let (layerIndex, _) = try importedVideo(manager)
        switch manager.bakeVideoToCels(layerIndex: layerIndex, celIndex: 0) {
        case .baked(let cels): XCTAssertEqual(cels, Self.levelsCount)
        case .refused(let reason): XCTFail("Bake should now be reachable, refused: \(reason)")
        }
    }

    // MARK: - Correctness

    /// **The two operands are the baked picture and the source frame it was supposed to come
    /// from** — not "did some cel appear", which would pass even if every cel showed frame 0.
    func testBakingWritesOneCelPerFrameEachShowingItsOwnDecodedPicture() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, originalVideo) = try importedVideo(manager)

        guard case .baked(let cels) = manager.bakeVideoToCels(layerIndex: layerIndex, celIndex: 0) else {
            return XCTFail("Setup: bake should succeed on a freshly imported clip.")
        }
        XCTAssertEqual(cels, Self.levelsCount)
        XCTAssertEqual(manager.layers[layerIndex].cels.count, Self.levelsCount)

        let ordered = manager.layers[layerIndex].cels.sorted { $0.startFrame < $1.startFrame }
        for (index, cel) in ordered.enumerated() {
            XCTAssertEqual(cel.startFrame, index, "Cel \(index) starts at the wrong document frame.")
            XCTAssertEqual(cel.frameCount, 1, "Cel \(index) should be exactly one document frame long.")
            let elements = try XCTUnwrap(cel.vector).elements
            XCTAssertEqual(elements.count, 1, "Cel \(index) should hold exactly the baked image.")
            guard case .image(let image) = elements[0] else {
                return XCTFail("Cel \(index) still holds a \(elements[0]), not an image.")
            }
            XCTAssertNotEqual(image.id, originalVideo.id, "The image must not reuse the video's id.")
            let grey = try XCTUnwrap(CanvasFixture.greyAt(image.image, x: 32, y: 32),
                                     "Cel \(index)'s picture should have an opaque pixel to read.")
            XCTAssertEqual(CanvasFixture.nearestLevelIndex(grey, in: Self.levels), index,
                          "Cel \(index) shows level \(grey), the wrong source frame's picture.")
            // The placement carries over untouched — same rectangle, same picture, just no longer
            // decoded live.
            XCTAssertEqual(image.transform.position, originalVideo.transform.position)
            XCTAssertEqual(image.transform.scale, originalVideo.transform.scale, accuracy: 1e-9)
        }
    }

    /// **Every id is fresh, video-turned-image and passthrough ink alike** — KEYFRAMES.md §6's rule,
    /// and the one a naive "just re-crop and keep copying" implementation would violate silently:
    /// nothing renders wrong when six cels share one stroke's id, but anything keyed by it (a
    /// motion-group lookup, `LayerContentVersion`'s identity) would alias the six together.
    func testBakingMintsFreshIdsForEveryElementItWrites() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, _) = try importedVideo(manager)

        let canvas = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        let plantedStroke = stroke()
        canvas.elements.append(.stroke(plantedStroke))
        canvas.bumpVersion()

        guard case .baked = manager.bakeVideoToCels(layerIndex: layerIndex, celIndex: 0) else {
            return XCTFail("Setup: bake should succeed.")
        }

        var allIDs: [UUID] = []
        for cel in manager.layers[layerIndex].cels {
            let elements = try XCTUnwrap(cel.vector).elements
            XCTAssertEqual(elements.count, 2, "Each cel should carry the image and the passenger stroke.")
            allIDs.append(contentsOf: elements.map(\.id))
            guard let carriedStroke = elements.compactMap(\.stroke).first else {
                return XCTFail("The stroke beside the video should still be there, id aside.")
            }
            XCTAssertEqual(carriedStroke.color, plantedStroke.color, "Only the id should have changed.")
            XCTAssertEqual(carriedStroke.samples.positions, plantedStroke.samples.positions)
        }
        XCTAssertFalse(allIDs.contains(plantedStroke.id), "The planted stroke's own id must not survive.")
        XCTAssertEqual(Set(allIDs).count, allIDs.count,
                      "Every element across every baked cel must have a distinct id.")
    }

    // MARK: - Undo, in one step

    /// **The exact case a naive `withStructureUndo` gets wrong**: `splitCel` never copies the left
    /// half's canvas, so the first of the resulting cels mutates the *same* `VectorCanvas` object
    /// the block had before baking. A snapshot-only undo restores the cel array's shape correctly
    /// while leaving that shared object's content baked — which reads as a passing "cel count is
    /// back to 1" and a silently wrong drawing underneath it. This asserts the content, not just
    /// the count.
    func testUndoingABakeRestoresTheOriginalVideoCelExactly() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, originalVideo) = try importedVideo(manager)
        let originalCelID = manager.layers[layerIndex].cels[0].id
        let costBefore = manager.layers[layerIndex].cels.count

        guard case .baked(let cels) = manager.bakeVideoToCels(layerIndex: layerIndex, celIndex: 0),
              cels > 1 else {
            return XCTFail("Setup: bake should split the block into more than one cel.")
        }
        XCTAssertEqual(manager.layers[layerIndex].cels.count, cels)

        manager.undo()

        XCTAssertEqual(manager.layers[layerIndex].cels.count, costBefore,
                       "Undo should collapse every split cel back into one, in a single press.")
        let restored = manager.layers[layerIndex].cels[0]
        XCTAssertEqual(restored.id, originalCelID)
        let elements = try XCTUnwrap(restored.vector).elements
        XCTAssertEqual(elements.count, 1)
        guard case .video(let video) = elements[0] else {
            return XCTFail("Undo left a \(elements[0]) where the original video belongs.")
        }
        XCTAssertEqual(video.id, originalVideo.id)
        XCTAssertEqual(video.assetFileName, originalVideo.assetFileName)
        XCTAssertEqual(video.sourceStart, originalVideo.sourceStart)
        XCTAssertEqual(video.sourceEnd, originalVideo.sourceEnd)

        manager.redo()
        XCTAssertEqual(manager.layers[layerIndex].cels.count, cels,
                       "Redo should bring every baked cel back in the same one press.")
        guard case .image = try XCTUnwrap(manager.layers[layerIndex].cels
            .sorted { $0.startFrame < $1.startFrame }[0].vector).elements.first else {
            return XCTFail("Redo should restore the baked image, not the video.")
        }
    }

    // MARK: - Refusals are visible, not swallowed

    func testBakeRefusesACelWithNoVideoAndTouchesNothing() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let before = layoutFingerprint(manager)

        switch manager.bakeVideoToCels(layerIndex: 0, celIndex: 0) {
        case .baked: XCTFail("An ordinary raster cel holds no video and must refuse.")
        case .refused(let reason): XCTAssertEqual(reason, .noVideo)
        }

        XCTAssertEqual(layoutFingerprint(manager), before, "A refusal must leave the timeline untouched.")
    }

    /// **An asset that will not open** — a video whose file is simply gone, which
    /// `VideoImportLogicTests`' own sentence about `ProjectStore.load` says already happens to a
    /// missing PNG and applies here the same way. Built directly rather than through `insertVideo`
    /// (which would refuse the missing file itself, never getting an element onto the canvas at
    /// all) — this is a fixture for a *refusal path*, not a claim that this is how an artist reaches
    /// it.
    func testBakeRefusesAnUnreadableAssetAndTouchesNothing() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.layers.count - 1
        let missing = directory.appendingPathComponent("never-written-\(UUID().uuidString).mp4")
        let video = VectorVideoElement(assetURL: missing, assetFileName: missing.lastPathComponent,
                                       naturalSize: CGSize(width: 64, height: 64),
                                       sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 1),
                                       speed: 1, transform: LayerTransform(position: .zero, scale: 1, rotation: 0))
        let canvas = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        canvas.elements = [.video(video)]
        canvas.bumpVersion()
        let before = layoutFingerprint(manager, layerIndex: layerIndex)

        switch manager.bakeVideoToCels(layerIndex: layerIndex, celIndex: 0) {
        case .baked: XCTFail("A video whose file was never written must refuse.")
        case .refused(let reason): XCTAssertEqual(reason, .unreadableAsset)
        }

        XCTAssertEqual(layoutFingerprint(manager, layerIndex: layerIndex), before)
        XCTAssertEqual(try XCTUnwrap(manager.layers[layerIndex].cels[0].vector).elements.count, 1,
                       "A refusal must not have touched the element either.")
    }

    /// **This refutes what this file assumed on the first pass, and says so rather than hiding it.**
    /// The plan was: push `sourceStart`/`sourceEnd` far past the clip's real duration and expect
    /// `.noDecodableFrames`, reading `VideoFrameReader`'s doc — "a pipe opened past the end delivers
    /// nothing at all" — as "every such query comes back nil". MEASURED instead: bake **succeeds**,
    /// producing one cel per document frame, every one showing the clip's *last* frame. The reader's
    /// own "nearest sample" rule degrades gracefully past the end rather than failing outright —
    /// consistent with RENDER §2.10's "keep the previous picture, never a hard failure" philosophy
    /// applied one level down, inside the reader itself.
    ///
    /// **`.noDecodableFrames` is therefore defensive code with no test proving it fires against a
    /// real asset.** `VideoFrameWriter.finish()` itself throws on zero appended frames
    /// (`Failure.couldNotFinish("No frames were written.")`), so a *valid, openable* file with
    /// nothing in it is not constructible with the tools at hand — the only asset that reaches
    /// `.noDecodableFrames` in practice would be one that opens its container but fails on every
    /// sample read, which is a corruption this fixture cannot manufacture. The guard stays in
    /// `bakeVideoToCels` as a safety net; this test pins what actually happens on the input this
    /// stage's own brief named ("no frames in range"), rather than asserting the refusal this file
    /// originally guessed at and never observed.
    func testACropFarPastTheClipsDurationBakesTheLastFrameRatherThanRefusing() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertTrue(manager.insertVideo(at: try clip()))
        let (layerIndex, _) = try importedVideo(manager)

        let canvas = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        var elements = canvas.elements
        guard case .video(var video) = elements[0] else { return XCTFail("Setup: expected a video.") }
        video.sourceStart = SourceTime(value: 999, timescale: 1)
        video.sourceEnd = SourceTime(value: 1000, timescale: 1)
        elements[0] = .video(video)
        canvas.elements = elements
        canvas.bumpVersion()

        guard case .baked(let cels) = manager.bakeVideoToCels(layerIndex: layerIndex, celIndex: 0) else {
            return XCTFail("MEASURED behavior was a successful bake — see the doc comment above.")
        }
        XCTAssertEqual(cels, Self.levelsCount)
        for cel in manager.layers[layerIndex].cels {
            let elements = try XCTUnwrap(cel.vector).elements
            guard case .image(let image) = elements.first else {
                return XCTFail("Every resulting cel should still hold an image, just the wrong frame.")
            }
            let grey = try XCTUnwrap(CanvasFixture.greyAt(image.image, x: 32, y: 32))
            XCTAssertEqual(CanvasFixture.nearestLevelIndex(grey, in: Self.levels), Self.levelsCount - 1,
                          "A far-future crop should decode the clip's last frame, repeatedly.")
        }
    }
}
