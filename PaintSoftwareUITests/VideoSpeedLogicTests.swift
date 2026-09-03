import AVFoundation
import XCTest
import UIKit

/// Pure-logic tests for VIDEO.md §2.5 — Adjust Speed.
///
/// **The ruling is that the block's length is the thing that changes.** *"At 2x the block halves:
/// same footage, half the frames, and the block's length continues to mean its duration. Later cels
/// do not move — the timeline does not ripple."* So every test here asserts two operands that are
/// computed by different code: the frames the block now occupies, and the footage the crop still
/// names. A speed change that moved the crop would be a retime, and §4.1 stores the crop in source
/// time precisely so the two cannot interact.
///
/// **§2.3's frame-for-frame is a speed, and this suite is where the corrected formula is exercised
/// against a real clip.** VIDEO.md §4.3 gives it as `sourceFPS / documentFPS`; it is
/// `documentFPS / sourceFPS`, and the block a frame-for-frame setting produces is exactly as long as
/// the clip has frames, which is what "every source frame shown, one per document frame" means.
@MainActor
final class VideoSpeedLogicTests: XCTestCase {

    private static let levels: [UInt8] = [30, 72, 114, 156, 198, 240]

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-speed-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
    }

    override func tearDownWithError() throws {
        VideoImportStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - §2.5

    /// **The ruling, verbatim.** At 2x the block halves and the footage is untouched; at 0.5x it
    /// doubles. The crop is the same two instants throughout, which is the assertion that says this
    /// is a speed change and not a retime.
    func testDoublingTheSpeedHalvesTheBlockAndLeavesTheFootageAlone() throws {
        let manager = try documentShowingAClip(frames: 24, blockLength: 12)
        let crop = (start: try video(manager).sourceStart, end: try video(manager).sourceEnd)

        manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: 2)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 6)
        XCTAssertEqual(try video(manager).speed, 2)
        XCTAssertEqual(try video(manager).sourceStart, crop.start, "Same footage.")
        XCTAssertEqual(try video(manager).sourceEnd, crop.end)

        manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: 0.5)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 24)
        XCTAssertEqual(try video(manager).sourceStart, crop.start)
        XCTAssertEqual(try video(manager).sourceEnd, crop.end)
    }

    /// **And the timeline does not ripple.** A block behind the one being slowed down stays exactly
    /// where it is — so the block takes the room it has and its crop is rewritten to match, which is
    /// a crop rather than an overlap. Two cels covering one frame would make `activeCelIndex` pick
    /// between them arbitrarily, which is a layer that renders one of two drawings at random.
    func testSlowingAClipDownDoesNotPushTheBlockBehindIt() throws {
        let manager = try documentShowingAClip(frames: 24, blockLength: 6)
        manager.layers[1].cels.append(Cel(id: UUID(), startFrame: 10, frameCount: 4,
                                          raster: .empty(size: CanvasFixture.canvasSize)))
        let neighbour = manager.layers[1].cels[1]

        manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: 0.5)

        XCTAssertEqual(manager.layers[1].cels[1].startFrame, neighbour.startFrame,
                       "Later cels do not move.")
        XCTAssertEqual(manager.layers[1].cels[1].frameCount, neighbour.frameCount)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 10,
                       "The block takes the ten frames there are, not the twelve it wanted.")
        XCTAssertEqual(VideoFrameMap.frameCount(of: try video(manager), documentFPS: 24), 10,
                       "And the crop follows it, so the block and the footage still agree.")
        assertNoOverlappingCels(manager, layerIndex: 1)
    }

    /// The block's length after a speed change *is* §4.3's inverse — asserted against the map rather
    /// than against a number typed here, so the two cannot drift, and against a typed number as well,
    /// so the pair is not merely self-consistent.
    func testTheNewBlockLengthIsTheFrameMapsInverse() throws {
        let manager = try documentShowingAClip(frames: 24, blockLength: 12)
        for speed in CanvasManager.videoSpeedChoices {
            manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: speed)
            let expected = VideoFrameMap.frameCount(of: try video(manager), documentFPS: 24)
            XCTAssertEqual(manager.layers[1].cels[0].frameCount, expected,
                           "At \(speed)x the block should be \(expected) frames.")
        }
        manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: 4)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 3, "Half a second at 4x is three frames.")
    }

    // MARK: - §2.3's frame-for-frame

    /// **Every source frame shown, one per document frame** — so the block is as long as the clip
    /// has frames, and the canvas shows frame *k* of the source on document frame *k*.
    ///
    /// A 30 fps clip in a 24 fps document plays frame-for-frame at 0.8, which is slower than real
    /// time. VIDEO.md §4.3's `sourceFPS / documentFPS` would give 1.25 and show fewer than half the
    /// frames, which is the opposite of what the setting is named for.
    func testFrameForFrameShowsEverySourceFrameOnceOnTheCanvas() throws {
        let manager = try documentShowingAClip(frames: 6, fps: 30)
        let speed = try XCTUnwrap(manager.frameForFrameVideoSpeed(layerIndex: 1, celIndex: 0))
        XCTAssertEqual(speed, 24.0 / 30.0, accuracy: 1e-9)

        manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: speed)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 6,
                       "Six source frames, one per document frame, is a six-frame block.")
        for frame in 0..<6 {
            XCTAssertEqual(try shownSourceFrame(manager, atFrame: frame), frame,
                           "Document frame \(frame) should show source frame \(frame).")
        }
    }

    /// The setting is offered by its number rather than by a mode, which is why it is a speed at all
    /// (§2.3) — and it is simply absent when the clip does not say what rate it runs at.
    func testFrameForFrameIsNilForACelHoldingNoVideo() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        XCTAssertNil(manager.frameForFrameVideoSpeed(layerIndex: 1, celIndex: 0))
        XCTAssertNil(manager.videoSpeed(layerIndex: 1, celIndex: 0))
        XCTAssertFalse(manager.celHoldsVideo(layerIndex: 1, celIndex: 0))
    }

    // MARK: - Undo, and the refusals

    /// One step, covering the element and the block both — which needs `StructureSnapshot.videoCrops`
    /// to carry `speed`, because `layers` is copied by value and `Cel.vector` is a class.
    func testUndoingASpeedChangeRestoresTheSpeedAsWellAsTheBlock() throws {
        let manager = try documentShowingAClip(frames: 24, blockLength: 12)
        manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: 2)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 6)

        manager.undo()
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 12)
        XCTAssertEqual(try video(manager).speed, 1,
                       "An undo that gave the frames back and kept the speed would be a stretch.")
    }

    /// A speed of zero or a negative one is not a speed. Refused rather than clamped, because there
    /// is no sensible frame to show at either and a silent clamp would put the block at a length the
    /// artist did not ask for.
    func testANonPositiveSpeedIsRefused() throws {
        let manager = try documentShowingAClip(frames: 24, blockLength: 12)
        for bad in [0.0, -1.0, Double.nan, Double.infinity] {
            manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: bad)
            XCTAssertEqual(try video(manager).speed, 1)
            XCTAssertEqual(manager.layers[1].cels[0].frameCount, 12)
        }
    }

    /// Setting the speed a video already has changes nothing at all — no version bump, no undo step —
    /// so tapping the checked row in the menu is inert rather than a no-op edit on the stack.
    func testSettingTheSpeedItAlreadyHasIsInert() throws {
        let manager = try documentShowingAClip(frames: 24, blockLength: 12)
        let vector = try XCTUnwrap(manager.layers[1].cels[0].vector)
        let version = vector.version
        manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: 1)
        XCTAssertEqual(vector.version, version)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 12)
    }

    // MARK: - Support

    private func documentShowingAClip(frames: Int, fps: Int = 24,
                                      blockLength: Int? = nil) throws -> CanvasManager {
        let url = directory.appendingPathComponent("clip-\(frames)-\(fps).mp4")
        let levels = (0..<frames).map { Self.levels[$0 % Self.levels.count] }
        try CanvasFixture.writeGreyClip(levels: levels, fps: fps, side: 64, to: url)

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
