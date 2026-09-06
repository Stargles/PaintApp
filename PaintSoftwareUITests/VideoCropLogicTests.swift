import AVFoundation
import XCTest
import UIKit

/// Pure-logic tests for VIDEO.md §2.2 — dragging either edge of a video's block crops it.
///
/// **"Not a retime and not a stretch"** is the ruling, and it is what most of these assertions are
/// about: the footage inside the block plays at the same speed and the same instants, and what
/// changes is how much of it there is. A stretch would keep `sourceStart`/`sourceEnd` and change
/// `speed`; a retime would keep the block and move the footage. Neither happens here.
///
/// **The drift test is the one that would have caught the obvious implementation.**
/// `resizeCelLeftEdge` and `resizeCelRightEdge` recompute neighbour pushes from `gestureSnapshot`
/// rather than from the live model, because a version that read the live model ratcheted and could
/// not be dragged back. A crop written as `sourceEnd += delta` would have exactly that bug, and the
/// snapshot could not have saved it: `StructureSnapshot` copies `[Layer]` by value and `Cel.vector`
/// is a **class**, so the baseline shares the live canvas and a "baseline crop" read through it is
/// the crop the last tick wrote. The crop is a pure function of the block's length instead, and
/// `testACropDraggedOutAndBackLandsWhereItStarted` is what says so.
@MainActor
final class VideoCropLogicTests: XCTestCase {

    private static let levels: [UInt8] = [30, 72, 114, 156, 198, 240]

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-crop-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
    }

    override func tearDownWithError() throws {
        VideoImportStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - §2.2, both edges

    /// The right edge dragged in: the head is untouched and the tail follows the block.
    func testDraggingTheRightEdgeInCropsTheTail() throws {
        let manager = try documentShowingAClip(frames: 30)
        XCTAssertEqual(try video(manager).sourceStart, .zero)

        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 6)

        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 6)
        XCTAssertEqual(try video(manager).sourceStart, .zero, "The head does not move on this edge.")
        XCTAssertEqual(try video(manager).sourceEnd, SourceTime(value: 6, timescale: 24))
        XCTAssertEqual(try video(manager).speed, 1, "A crop is not a retime.")
    }

    /// **§2.4's "up to the full duration".** Dragging the right edge out reveals more footage until
    /// there is none left, and then the crop stops rather than claiming frames the file does not
    /// have. The block is allowed to keep growing — §4.3's clamp holds the last frame — because
    /// walling the drag off would make a video block behave unlike every other block on the timeline.
    func testDraggingTheRightEdgeOutRevealsMoreUpToTheClipsDuration() throws {
        let manager = try documentShowingAClip(frames: 30)
        let scene = manager.contentEndFrame
        XCTAssertEqual(try video(manager).sourceEnd, SourceTime(value: Int64(scene), timescale: 24),
                       "It arrived clipped to the scene (§2.4).")

        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 20)
        XCTAssertEqual(try video(manager).sourceEnd, SourceTime(value: 20, timescale: 24),
                       "Twenty frames of block is twenty frames of footage while there is footage.")

        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 60)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 60)
        XCTAssertEqual(try video(manager).sourceEnd.seconds, 30.0 / 24.0, accuracy: 0.05,
                       "Past the end of the clip the crop stops at the clip's own duration.")
    }

    /// **The left edge crops the head**, which is the half §2.2 spells out because it is the
    /// surprising one — and the canvas is what says it happened: after cropping four frames off the
    /// head, the block's first frame shows the clip's *fifth* frame.
    func testDraggingTheLeftEdgeCropsTheHead() throws {
        let manager = try documentShowingAClip(frames: 30, blockLength: 6)
        XCTAssertEqual(try shownSourceFrame(manager, atFrame: 0), 0)
        let end = try video(manager).sourceEnd

        manager.resizeCelLeftEdge(layerIndex: 1, celIndex: 0, newStartFrame: 4)

        let cel = manager.layers[1].cels[0]
        XCTAssertEqual(cel.startFrame, 4)
        XCTAssertEqual(cel.frameCount, 2, "The right edge is where it was.")
        XCTAssertEqual(try video(manager).sourceEnd, end, "So the tail of the crop is too.")
        XCTAssertEqual(try video(manager).sourceStart, SourceTime(value: 4, timescale: 24),
                       "And the head has moved forward by exactly the four frames the drag took.")
        XCTAssertEqual(try shownSourceFrame(manager, atFrame: 4), 4,
                       "The block's own first frame now shows the clip's fifth.")
    }

    /// The head cannot be cropped before the start of the file. A block dragged out further left
    /// than there is footage holds the first frame, which is §4.3's clamp doing the work.
    func testTheHeadCannotBeCroppedBeforeTheStartOfTheFile() throws {
        let manager = try documentShowingAClip(frames: 30, blockLength: 4)
        manager.moveCel(layerIndex: 1, celIndex: 0, newStartFrame: 8)
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 12)

        manager.resizeCelLeftEdge(layerIndex: 1, celIndex: 0, newStartFrame: 0)
        XCTAssertEqual(manager.layers[1].cels[0].startFrame, 0)
        XCTAssertEqual(try video(manager).sourceStart, .zero,
                       "There is nothing before the first frame to reveal.")
        XCTAssertEqual(try shownSourceFrame(manager, atFrame: 0), 0)
    }

    // MARK: - The drift

    /// **A crop drag that goes out and comes back lands exactly where it started.** This is the
    /// property `resizeCelRightEdge`'s own header spends a paragraph on for neighbours, and it is
    /// bought here by arithmetic rather than by a baseline — the crop is a pure function of the
    /// block's length and the end the drag is not moving.
    func testACropDraggedOutAndBackLandsWhereItStarted() throws {
        let manager = try documentShowingAClip(frames: 30)
        let scene = manager.contentEndFrame
        let original = VideoCrop(of: try video(manager))

        manager.beginStructureGesture()
        for end in [9, 3, 18, 25, 7, scene] {
            manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: end)
        }
        manager.commitStructureGesture(label: .resizeFrame)

        XCTAssertEqual(manager.layers[1].cels[0].frameCount, scene)
        XCTAssertEqual(VideoCrop(of: try video(manager)), original,
                       "Six ticks of one drag, ending where it began, must leave the crop where it "
                       + "began — a crop written as a running delta would have ratcheted.")
    }

    /// **And an undo puts it back**, which `StructureSnapshot` could not do until it carried the crop
    /// itself: it copies `[Layer]` by value and `Cel.vector` is a class, so restoring the block's
    /// length would otherwise have left the new crop in place — a retime nobody asked for, made out
    /// of an undo.
    func testUndoingACropDragRestoresTheCropAndNotJustTheBlock() throws {
        let manager = try documentShowingAClip(frames: 30)
        let scene = manager.contentEndFrame
        let original = VideoCrop(of: try video(manager))

        manager.beginStructureGesture()
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 5)
        manager.commitStructureGesture(label: .resizeFrame)
        XCTAssertNotEqual(VideoCrop(of: try video(manager)), original)

        manager.undo()
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, scene)
        XCTAssertEqual(VideoCrop(of: try video(manager)), original)
    }

    // MARK: - §7, Split Drawing

    /// **VIDEO.md §7's second row.** Splitting a video cel gives two blocks that between them show
    /// the same footage once: the left half's crop ends where the right half's begins, at the cut's
    /// own source time.
    ///
    /// The canvas is what says it, not the fields: the right half's first frame shows the source
    /// frame the left half was about to. Asserting the crops alone would pass against a split that
    /// wrote two crops nothing reads.
    func testSplittingAVideoCropsEachHalfToItsOwnSpan() throws {
        let manager = try documentShowingAClip(frames: 30, blockLength: 6)
        let whole = VideoCrop(of: try video(manager))

        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 4)

        XCTAssertEqual(manager.layers[1].cels.count, 2)
        let left = manager.layers[1].cels[0]
        let right = manager.layers[1].cels[1]
        XCTAssertEqual(left.startFrame, 0)
        XCTAssertEqual(left.frameCount, 4)
        XCTAssertEqual(right.startFrame, 4)
        XCTAssertEqual(right.frameCount, 2)

        let leftVideo = try XCTUnwrap(left.vector?.videos.first)
        let rightVideo = try XCTUnwrap(right.vector?.videos.first)
        XCTAssertEqual(leftVideo.sourceStart, whole.start, "The left half keeps the head.")
        XCTAssertEqual(rightVideo.sourceEnd, whole.end, "The right half keeps the tail.")
        XCTAssertEqual(leftVideo.sourceEnd, rightVideo.sourceStart,
                       "And they meet at the cut, so no footage is shown twice or lost.")
        XCTAssertEqual(leftVideo.assetFileName, rightVideo.assetFileName,
                       "One asset file — the split is a crop, not a re-encode.")

        XCTAssertEqual(try shownSourceFrame(manager, atFrame: 4), 4,
                       "The right half's first frame is the one the left half was about to show.")
    }

    /// And Split Drawing on an ordinary cel is exactly what it was — the crop writer is a no-op on
    /// one memoized `Bool`, so nothing about stage 5 reached the verb's existing behaviour.
    func testSplittingAnOrdinaryCelIsUnchanged() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 8)])
        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 3)
        XCTAssertEqual(CanvasFixture.celLayout(manager, layerIndex: 1).map { [$0.start, $0.length] },
                       [[0, 3], [3, 5]])
    }

    // MARK: - What a crop is not

    /// **Being shoved along the timeline is not being cropped.** A block pushed by its neighbour's
    /// drag keeps its length, so it keeps its footage — only the cel whose edge was dragged is
    /// re-cropped.
    func testABlockPushedByItsNeighbourKeepsItsFootage() throws {
        let manager = try documentShowingAClip(frames: 30, blockLength: 6)
        // A silent cel in front of it, so the video block is something a drag can push.
        manager.moveCel(layerIndex: 1, celIndex: 0, newStartFrame: 6)
        manager.layers[1].cels.insert(Cel(id: UUID(), startFrame: 0, frameCount: 6,
                                          raster: .empty(size: CanvasFixture.canvasSize)), at: 0)
        let videoCelIndex = 1
        let original = VideoCrop(of: try XCTUnwrap(manager.layers[1].cels[videoCelIndex].vector?.videos.first))

        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 10)

        let pushed = manager.layers[1].cels[videoCelIndex]
        XCTAssertEqual(pushed.startFrame, 10, "It was pushed.")
        XCTAssertEqual(pushed.frameCount, 6, "Keeping its length.")
        XCTAssertEqual(VideoCrop(of: try XCTUnwrap(pushed.vector?.videos.first)), original,
                       "And therefore its footage.")
    }

    /// A cel with no video is untouched by the crop writer, which is what makes stage 5 free for
    /// every document that has never imported one.
    func testResizingAnOrdinaryCelWritesNoCrop() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let vector = try XCTUnwrap(manager.layers[1].cels[0].vector)
        let version = vector.version
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 4)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 4)
        XCTAssertEqual(vector.version, version, "Nothing in the canvas changed, so nothing bumped.")
    }

    // MARK: - Support

    /// A 24 fps document holding one imported clip, optionally trimmed to `blockLength` first so a
    /// test has room to drag in both directions.
    private func documentShowingAClip(frames: Int, blockLength: Int? = nil) throws -> CanvasManager {
        let url = directory.appendingPathComponent("clip-\(frames).mp4")
        let levels = (0..<frames).map { Self.levels[$0 % Self.levels.count] }
        try CanvasFixture.writeGreyClip(levels: levels, fps: 24, side: 64, to: url)

        let manager = CanvasFixture.manager(layerCount: 1)
        manager.fps = 24
        XCTAssertTrue(manager.insertVideo(at: url))
        if let blockLength {
            manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: blockLength)
        }
        return manager
    }

    private func video(_ manager: CanvasManager) throws -> VectorVideoElement {
        try XCTUnwrap(manager.layers[1].cels[0].vector?.videos.first)
    }

    private func shownSourceFrame(_ manager: CanvasManager, atFrame frame: Int) throws -> Int {
        let cel = manager.layers[1].cels[0]
        let derived = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: frame))
        let image = try XCTUnwrap(derived.render(.full))
        let grey = try XCTUnwrap(CanvasFixture.greyAt(image, x: 32, y: 32))
        return CanvasFixture.nearestLevelIndex(grey, in: Self.levels)
    }
}
