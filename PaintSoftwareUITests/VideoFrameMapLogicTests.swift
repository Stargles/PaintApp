import AVFoundation
import XCTest
import UIKit

/// Pure-logic tests for VIDEO.md §4.3 — the frame map, the bake-key component it produces, and the
/// third branch of `CanvasManager.derivedCelContent` that reads both.
///
/// **The map is arithmetic and is tested as arithmetic.** It takes no asset, no decoder and no
/// document, so the first half of this suite is `VideoFrameMap` against numbers: a clip keeps its
/// real-world duration, frame-for-frame shows every source frame once, and a crop stored in source
/// time (§4.1) is untouched by a speed change or by a change of the document's own rate.
///
/// **The second half is the bake key**, and it is §4.5's trap arriving through the video door.
/// `FrameBakeKey` is a hand-written encoder whose no-`default:` rule turns a new enum *case* into a
/// compile error — and a new stored *property* into nothing at all. `VideoCelIdentity.cuts` is
/// exactly such a property: without it every document frame of a video block encodes identically,
/// the content-addressed store resolves the whole block to one file, and the first frame's picture
/// is served for all of them with no error anywhere. The pair of tests below is the pin, and the
/// control beside it — an ordinary hold still being one file — is what stops the pin passing for the
/// wrong reason.
///
/// **The third half is pixels**, because a map nothing reads is a map that cannot be wrong. Those
/// tests render a real cel at a real frame and read the grey back, so the assertion's two operands
/// are the number the arithmetic names and the picture the decoder produced — computed by different
/// code, which is the only thing that makes agreeing between them mean something.
@MainActor
final class VideoFrameMapLogicTests: XCTestCase {

    /// Six flat greys, 42 apart — see `CanvasFixture.writeGreyClip` for why that spacing.
    private static let levels: [UInt8] = [30, 72, 114, 156, 198, 240]

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-map-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - Fixtures

    private func element(sourceStart: SourceTime = .zero,
                         sourceEnd: SourceTime = SourceTime(value: 1, timescale: 1),
                         speed: Double = 1,
                         assetURL: URL? = nil,
                         naturalSize: CGSize = CGSize(width: 64, height: 64)) -> VectorVideoElement {
        let url = assetURL ?? directory.appendingPathComponent("absent.mp4")
        return VectorVideoElement(assetURL: url, assetFileName: url.lastPathComponent,
                                  naturalSize: naturalSize,
                                  sourceStart: sourceStart, sourceEnd: sourceEnd, speed: speed,
                                  transform: LayerTransform(position: CGPoint(x: 32, y: 32),
                                                            scale: 1, rotation: 0))
    }

    // MARK: - §4.3, the forward map

    /// **§2.3's default: a clip plays at correct real-world speed and duration.** A one-second 30 fps
    /// clip in a 24 fps document occupies 24 frames — one second — and the last of them shows the
    /// last source frame rather than running out three frames early.
    ///
    /// The two ends are asserted together on purpose: a map that was merely *scaled* wrongly would
    /// still put frame 0 at source frame 0.
    func testAThirtyFpsClipKeepsItsRealWorldDurationInATwentyFourFpsDocument() {
        let clip = element(sourceEnd: SourceTime(value: 1, timescale: 1))
        XCTAssertEqual(VideoFrameMap.frameCount(of: clip, documentFPS: 24), 24,
                       "A second of footage is a second of timeline.")

        let first = VideoFrameMap.sourceTime(of: clip, atDocumentFrame: 0, celStartFrame: 0,
                                             documentFPS: 24)
        XCTAssertEqual(VideoFrameMap.sourceFrameIndex(at: first, sourceFPS: 30), 0)

        let last = VideoFrameMap.sourceTime(of: clip, atDocumentFrame: 23, celStartFrame: 0,
                                            documentFPS: 24)
        XCTAssertEqual(VideoFrameMap.sourceFrameIndex(at: last, sourceFPS: 30), 29,
                       "The 24th document frame must reach the 30th source frame, not the 24th — "
                       + "otherwise the clip is playing slow and losing its tail.")
    }

    /// **§2.3's frame-for-frame setting, and VIDEO.md §4.3 has the formula inverted.**
    ///
    /// The document says `speed = sourceFPS / documentFPS`; the map's own definition gives
    /// `documentFPS / sourceFPS`, and this test is what says so in behaviour rather than in prose:
    /// at 0.8 every one of the thirty source frames is shown exactly once, over thirty document
    /// frames. At the documented 1.25 the same clip would land on source frames 0, 2, 3, 5, … and
    /// show fewer than half of them, which is the opposite of what the setting is named for.
    func testFrameForFrameShowsEverySourceFrameExactlyOnce() {
        let speed = VideoFrameMap.frameForFrameSpeed(sourceFPS: 30, documentFPS: 24)
        XCTAssertEqual(speed, 0.8, accuracy: 1e-12)

        let clip = element(sourceEnd: SourceTime(value: 1, timescale: 1), speed: speed)
        XCTAssertEqual(VideoFrameMap.frameCount(of: clip, documentFPS: 24), 30,
                       "Thirty source frames, one per document frame, is a thirty-frame block.")

        var seen: [Int] = []
        for frame in 0..<30 {
            let time = VideoFrameMap.sourceTime(of: clip, atDocumentFrame: frame, celStartFrame: 0,
                                                documentFPS: 24)
            seen.append(VideoFrameMap.sourceFrameIndex(at: time, sourceFPS: 30))
        }
        XCTAssertEqual(seen, Array(0..<30),
                       "Frame-for-frame means each source frame once, in order, with none repeated "
                       + "and none skipped.")
    }

    /// **At `speed == 1` the map is exact and cannot drift**, which is the property `SourceTime`
    /// being a rational buys and the reason it is not a `Double` of seconds. Asserted at frame
    /// 100,000 — over an hour of timeline — by *equality* against the rational it should be, not by
    /// a tolerance.
    func testTheMapIsExactAtSpeedOneHoweverLongTheClip() {
        let clip = element(sourceEnd: SourceTime(value: 7200, timescale: 1))
        let time = VideoFrameMap.sourceTime(of: clip, atDocumentFrame: 100_000, celStartFrame: 0,
                                            documentFPS: 24)
        XCTAssertEqual(time, SourceTime(value: 100_000, timescale: 24))
        XCTAssertEqual(time.seconds, 100_000.0 / 24.0, accuracy: 1e-12)
    }

    /// The cel's own start frame is the origin, so a block moved along the timeline shows the same
    /// footage rather than scrubbing itself.
    func testTheBlocksOwnStartFrameIsTheOrigin() {
        let clip = element(sourceEnd: SourceTime(value: 10, timescale: 1))
        let atHead = VideoFrameMap.sourceTime(of: clip, atDocumentFrame: 40, celStartFrame: 40,
                                              documentFPS: 24)
        XCTAssertEqual(atHead, clip.sourceStart)
        let later = VideoFrameMap.sourceTime(of: clip, atDocumentFrame: 52, celStartFrame: 40,
                                             documentFPS: 24)
        XCTAssertEqual(later, SourceTime(value: 12, timescale: 24))
    }

    // MARK: - §4.1, why the crop lives in source time

    /// **§4.1's whole argument, as a test.** A crop written in source time is untouched by a speed
    /// change — the footage shown is the same footage, and only the block's length moves. A crop
    /// stored in document frames would have had to be rewritten here, and §2.5 changes the block's
    /// length on purpose, so the two would interact and the artist's crop would drift.
    func testACropSurvivesASpeedChange() {
        var clip = element(sourceStart: SourceTime(value: 12, timescale: 30),
                           sourceEnd: SourceTime(value: 300, timescale: 30))
        let start = clip.sourceStart, end = clip.sourceEnd
        XCTAssertEqual(VideoFrameMap.frameCount(of: clip, documentFPS: 24), 230)

        clip.speed = 2
        XCTAssertEqual(clip.sourceStart, start, "A speed change must not touch the crop.")
        XCTAssertEqual(clip.sourceEnd, end)
        XCTAssertEqual(VideoFrameMap.frameCount(of: clip, documentFPS: 24), 115,
                       "§2.5: at 2x the block halves — same footage, half the frames.")
        XCTAssertEqual(VideoFrameMap.sourceTime(of: clip, atDocumentFrame: 0, celStartFrame: 0,
                                                documentFPS: 24),
                       start,
                       "And the head of the block is still the head of the crop.")
        // The block's last frame reaches the end of the crop to within what a whole number of frames
        // can promise. 9.6 s at 2x is 115.2 document frames; the block is 115, its last frame is
        // index 114, and 115.2 − 114 = 1.2 steps of footage are left over. That leftover is in
        // [0.5, 1.5) by construction — half from `frameCount`'s rounding and one from the last frame
        // being at `n − 1` — so 1.5 is the bound, and it is a bound rather than a value because the
        // fraction depends on the crop.
        let shortfall = end.secondsSince(VideoFrameMap.sourceTime(of: clip, atDocumentFrame: 114,
                                                                  celStartFrame: 0, documentFPS: 24))
        XCTAssertGreaterThan(shortfall, 0, "The last frame of the block is inside the crop.")
        XCTAssertLessThan(shortfall / (clip.speed / 24), 1.5,
                          "The last frame of the halved block still reaches the end of the crop, to "
                          + "within the frame the block length's rounding costs.")
    }

    /// The same separation against the *document's* rate, which §4.1 names beside the speed change.
    /// The crop is bytes on disk and does not move; the block's length is derived and does.
    func testACropIsUntouchedByTheDocumentsOwnFrameRate() {
        let clip = element(sourceStart: SourceTime(value: 12, timescale: 30),
                           sourceEnd: SourceTime(value: 300, timescale: 30))
        XCTAssertEqual(VideoFrameMap.frameCount(of: clip, documentFPS: 24), 230)
        XCTAssertEqual(VideoFrameMap.frameCount(of: clip, documentFPS: 12), 115)
        XCTAssertEqual(clip.sourceStart, SourceTime(value: 12, timescale: 30))
        XCTAssertEqual(clip.sourceEnd, SourceTime(value: 300, timescale: 30))
    }

    /// A block longer than its footage holds the last frame of the crop rather than running past
    /// it — reachable through §2.4's outward drag and through a speed change that shortens the
    /// footage before §2.5 has rewritten the block.
    func testTheMapHoldsTheEndOfTheCropRatherThanRunningPastIt() {
        let clip = element(sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 4))
        let inside = VideoFrameMap.sourceTime(of: clip, atDocumentFrame: 3, celStartFrame: 0,
                                              documentFPS: 24)
        XCTAssertEqual(inside, SourceTime(value: 3, timescale: 24))
        for frame in 6...20 {
            XCTAssertEqual(VideoFrameMap.sourceTime(of: clip, atDocumentFrame: frame,
                                                    celStartFrame: 0, documentFPS: 24),
                           clip.sourceEnd,
                           "Frame \(frame) is past the crop and must hold its last instant.")
        }
    }

    /// `SourceTime` normalises, so two spellings of one instant are one value and order is by value
    /// rather than by numerator. Both halves matter: the clamp above and the ring's keys both rely
    /// on it.
    func testSourceTimesCompareByValueRatherThanBySpelling() {
        XCTAssertEqual(SourceTime(value: 2, timescale: 4), SourceTime(value: 1, timescale: 2))
        XCTAssertFalse(SourceTime(value: 2, timescale: 4) < SourceTime(value: 1, timescale: 2))
        XCTAssertTrue(SourceTime(value: 1, timescale: 3) < SourceTime(value: 1, timescale: 2))
        XCTAssertTrue(SourceTime(value: 999, timescale: 1000) < SourceTime(value: 1, timescale: 1))
    }

    // MARK: - The bake-key component (§4.5, VIDEO.md §5)

    /// **The pin.** Two document frames of one video block are two pictures, so they must be two
    /// files on disk. Everything else about them is identical — one cel, one `LayerContentVersion`,
    /// one tree — so the only thing that can move the digest is `VideoCelIdentity.cuts`.
    ///
    /// **MEASURED by mutation**: deleting the four lines that encode `cuts` from
    /// `VideoCelIdentity.encodeForBakeKey` makes this test fail with two equal digests, while the
    /// control below stays green. That is the failure mode this component exists to prevent, and it
    /// is invisible without this assertion — a content-addressed store has no key to compare after
    /// the lookup, so it would simply serve frame 0's picture for the whole block.
    func testTwoFramesOfOneVideoBlockAreTwoDigests() throws {
        let url = try writeClip(fps: 24)
        let manager = try managerShowingAVideo(asset: url, speed: 1)
        let first = try digest(manager, frame: 0)
        let second = try digest(manager, frame: 4)
        XCTAssertNotEqual(first, second,
                          "A video is the first content that varies across the frames one cel spans, "
                          + "so its block cannot be one file the way a hold is.")
    }

    /// **The control, and it is what stops the pin above passing for the wrong reason.** RENDER.md
    /// §3.3 leaves `frame` out of the key precisely so a nine-frame hold is one file; if the video
    /// component had been implemented by putting `frame` into the key instead, the test above would
    /// pass and this one would fail.
    func testEveryFrameOfAnOrdinaryHoldIsStillOneDigest() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 9)])
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 4, y: 4,
                                                                                  width: 20, height: 20)))
        XCTAssertEqual(try digest(manager, frame: 0), try digest(manager, frame: 6))
    }

    /// **And the digest moves with the *cut*, not with the frame.** Two document frames past the end
    /// of the crop clamp to one source instant, show one picture, and must therefore be one file. A
    /// key carrying the frame number would call them two.
    func testTwoFramesResolvingToOneSourceInstantAreOneDigest() throws {
        let url = try writeClip(fps: 24)
        // A crop two source frames long inside a block eight document frames long: everything from
        // document frame 2 onwards holds the crop's last instant.
        let manager = try managerShowingAVideo(asset: url, speed: 1,
                                               sourceEnd: SourceTime(value: 2, timescale: 24),
                                               blockLength: 8)
        XCTAssertEqual(try digest(manager, frame: 5), try digest(manager, frame: 7))
        XCTAssertNotEqual(try digest(manager, frame: 0), try digest(manager, frame: 7))
    }

    // MARK: - The derivation, in pixels

    /// **The map, the reader and the render, end to end.** A 24 fps clip in a 24 fps document at
    /// speed 1: document frame k shows source frame k, and the canvas says so.
    ///
    /// The assertion's two operands are computed by different code — the grey the decoder produced,
    /// and the index the arithmetic names — so agreeing between them is a claim about the app rather
    /// than a definition.
    func testEachDocumentFrameShowsTheSourceFrameTheMapNames() throws {
        let url = try writeClip(fps: 24)
        let manager = try managerShowingAVideo(asset: url, speed: 1)
        for frame in 0..<Self.levels.count {
            XCTAssertEqual(try shownSourceFrame(manager, atFrame: frame), frame,
                           "Document frame \(frame) should show source frame \(frame).")
        }
    }

    /// **§2.3's resampling, on the canvas.** Six frames of 30 fps footage in a 24 fps document:
    /// source frame 2 is dropped, because 24 document frames cannot show 30 source frames. The
    /// expected list is computed from the map rather than typed out, and then *also* stated
    /// literally — a list that only came from the map would agree with any map whatever.
    func testAThirtyFpsClipResamplesToTheDocumentRate() throws {
        let url = try writeClip(fps: 30)
        let manager = try managerShowingAVideo(asset: url, speed: 1)
        let clip = try XCTUnwrap(videoElement(in: manager))

        var byArithmetic: [Int] = []
        for frame in 0..<5 {
            let time = VideoFrameMap.sourceTime(of: clip, atDocumentFrame: frame, celStartFrame: 0,
                                                documentFPS: 24)
            byArithmetic.append(VideoFrameMap.sourceFrameIndex(at: time, sourceFPS: 30))
        }
        XCTAssertEqual(byArithmetic, [0, 1, 3, 4, 5],
                       "Frame 2 of the source is dropped and the 2.5 tie rounds up — which is the "
                       + "rule `VideoFrameReader` breaks ties by too.")

        for frame in 0..<5 {
            XCTAssertEqual(try shownSourceFrame(manager, atFrame: frame), byArithmetic[frame],
                           "Document frame \(frame) on the canvas disagrees with the map.")
        }
    }

    /// A cel with no video has no video derivation, so every document that never imported one pays
    /// one memoized `Bool` and takes the path it always took.
    func testACelWithNoVideoHasNoVideoDerivation() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = manager.layers[1].cels[0]
        XCTAssertNil(manager.videoCelContent(for: cel, atFrame: 0))
        XCTAssertNil(manager.derivedCelContent(for: cel, atFrame: 0),
                     "And nothing else picks it up either — the untouched path is unchanged.")
        XCTAssertFalse(try XCTUnwrap(cel.vector).holdsVideo)
    }

    /// **A video whose asset is gone still draws stage 2's placeholder**, which is RENDER §2.10's
    /// rule applied to a source file: the artist sees where the video is rather than a hole where it
    /// was. The derivation exists (so the pose arm is not silently taking over) and it renders
    /// something opaque in the middle of the canvas.
    func testAVideoWhoseAssetWillNotOpenStillDrawsItsPlaceholder() throws {
        let missing = directory.appendingPathComponent("gone.mp4")
        let manager = try managerShowingAVideo(asset: missing, speed: 1)
        let cel = manager.layers[1].cels[0]
        let derived = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: 0),
                                    "A video cel derives whether or not its asset opens.")
        let image = try XCTUnwrap(derived.render(.full))
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(image.cgImage)))
        let centre = ((32 * 64) + 32) * 4
        XCTAssertGreaterThan(bytes[centre + 3], 0, "The placeholder covers the video's own rect.")
    }

    // MARK: - Support

    private func writeClip(fps: Int, named name: String = "clip.mp4") throws -> URL {
        let url = directory.appendingPathComponent("\(fps)-\(name)")
        try CanvasFixture.writeGreyClip(levels: Self.levels, fps: fps, side: 64, to: url)
        return url
    }

    /// A 24 fps document whose second layer is a vector layer holding one video that covers the
    /// whole canvas.
    private func managerShowingAVideo(asset: URL, speed: Double,
                                      sourceEnd: SourceTime = SourceTime(value: 1, timescale: 1),
                                      blockLength: Int = 12) throws -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.fps = 24
        manager.addVectorLayer()
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: blockLength)])
        let canvas = VectorCanvas(size: CanvasFixture.canvasSize)
        manager.layers[1].cels[0].vector = canvas
        canvas.elements = [.video(element(sourceEnd: sourceEnd, speed: speed, assetURL: asset))]
        canvas.bumpVersion()
        return manager
    }

    private func videoElement(in manager: CanvasManager) -> VectorVideoElement? {
        manager.layers[1].cels[0].vector?.elements.compactMap(\.video).first
    }

    /// The source frame the canvas is actually showing at `frame`, read off the rendered pixels.
    private func shownSourceFrame(_ manager: CanvasManager, atFrame frame: Int) throws -> Int {
        let cel = manager.layers[1].cels[0]
        let derived = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: frame),
                                    "A video cel must derive at every frame of its block.")
        let image = try XCTUnwrap(derived.render(.full))
        let grey = try XCTUnwrap(CanvasFixture.greyAt(image, x: 32, y: 32),
                                 "The video covers the canvas, so its centre pixel is opaque.")
        return CanvasFixture.nearestLevelIndex(grey, in: Self.levels)
    }

    private func digest(_ manager: CanvasManager, frame: Int) throws -> String {
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: frame, quality: .full,
                                                           includeBackground: true, sizing: .native))
        return FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0,
                            backend: .coreGraphics,
                            formatVersion: FrameBakeStore.formatVersion).fileName
    }
}
