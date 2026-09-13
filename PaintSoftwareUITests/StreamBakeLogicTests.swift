import XCTest
import UIKit

/// Pure-logic tests for **Bake Frame** and **Freeze** — STREAM.md §2.4, §5.4 and §5.5 — driven
/// with no socket: the frame arrives through `ScreenStreamCoordinator.frameSourceOverride` and
/// `tick()`, exactly as `StreamInsertLogicTests` drives the tick.
///
/// The document is the brief's own: **four frames, one cel**, and a bake on the second frame must
/// give [1] [2] [3–4] with only [2] changed. Frames are 0-based in code, so that is a bake at
/// frame 1 of a cel spanning [0, 4). Every shape assertion is paired with one on *pixels* — the
/// baked cel's picture through the real compositor, against a stream that has since moved on to a
/// different colour — because a bake whose model is right and whose picture is the placeholder is
/// the kind of green this suite exists to refuse.
@MainActor
final class StreamBakeLogicTests: XCTestCase {

    private static let size = CanvasFixture.canvasSize   // 64 × 64
    private static let endpoint = StreamEndpoint(host: "laptop", port: 47301)

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        super.tearDown()
    }

    // MARK: - Fixture

    private struct Fixture {
        let manager: CanvasManager
        let layerIndex: Int
        let streamID: UUID
        var layer: Layer { manager.layers[layerIndex] }
        var cels: [Cel] { layer.cels }
        /// `[start, end)` of every cel, in order — what the timeline shows.
        var spans: [Range<Int>] { cels.map { $0.startFrame ..< $0.endFrame } }
    }

    private func status(width: Int = 8, height: Int = 4) -> StreamStatus {
        StreamStatus(source: StreamStatus.Source(kind: "window", name: "Blender"),
                     width: width, height: height, fps: 30, streaming: true)
    }

    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 8, height: 4)) -> CGImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }.cgImage!
    }

    /// One vector layer holding one stream in one cel spanning `[0, frames)`, committed out of the
    /// Move box, with the frame source parked on `color` at `index`. `feed` moves the source.
    private func fixture(frames: Int = 4, color: UIColor = .green) -> Fixture {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 0
        let element = manager.insertStream(host: Self.endpoint.host, port: Self.endpoint.port,
                                           status: status())
        manager.commitVectorFloatIfNeeded()
        let layerIndex = manager.layers.count - 1
        manager.layers[layerIndex].cels[0].frameCount = frames
        let fixture = Fixture(manager: manager, layerIndex: layerIndex, streamID: element!.id)
        feed(fixture, color: color, index: 1)
        return fixture
    }

    /// Parks the frame source on `color` at `index` and runs one tick.
    private func feed(_ fixture: Fixture, color: UIColor, index: Int) {
        let image = solidImage(color)
        fixture.manager.streamCoordinator.onLayerNeedsRepaint = { _ in }
        fixture.manager.streamCoordinator.frameSourceOverride = { endpoint in
            endpoint == Self.endpoint ? (index, image) : nil
        }
        fixture.manager.streamCoordinator.tick()
    }

    private func bake(_ fixture: Fixture, atFrame frame: Int, file: StaticString = #filePath,
                      line: UInt = #line) -> CanvasManager.StreamBakeOutcome {
        guard let celIndex = fixture.manager.activeCelIndex(inLayer: fixture.layerIndex, atFrame: frame) else {
            XCTFail("No cel at frame \(frame)", file: file, line: line)
            return .refused(.notOnStreamCel)
        }
        return fixture.manager.bakeStreamFrame(layerIndex: fixture.layerIndex, celIndex: celIndex,
                                               atFrame: frame)
    }

    /// The one element on the cel at `frame`, as a stream or an image.
    private func element(_ fixture: Fixture, atFrame frame: Int) -> VectorElement? {
        guard let celIndex = fixture.manager.activeCelIndex(inLayer: fixture.layerIndex, atFrame: frame),
              let vector = fixture.cels[celIndex].vector, vector.elements.count == 1 else { return nil }
        return vector.elements[0]
    }

    /// RGBA at a canvas point of the whole document composited at `frame` through the real
    /// compositor — what the artist would see on that frame, not what a cel stores.
    private func compositedPixel(_ fixture: Fixture, atFrame frame: Int, x: Int, y: Int,
                                 file: StaticString = #filePath, line: UInt = #line)
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard let request = fixture.manager.makeRenderRequest(atFrame: frame, includeBackground: false),
              let cg = Compositor.composite(request) else {
            XCTFail("The compositor must render frame \(frame)", file: file, line: line)
            return (0, 0, 0, 0)
        }
        XCTAssertEqual(cg.width, Int(Self.size.width), "native sizing", file: file, line: line)
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    private func assertGreen(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.a, 255, "\(what): opaque", file: file, line: line)
        XCTAssertGreaterThan(Int(p.g), Int(p.r) + 100, "\(what): green", file: file, line: line)
        XCTAssertGreaterThan(Int(p.g), Int(p.b) + 100, "\(what): green", file: file, line: line)
    }

    private func assertRed(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ what: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.a, 255, "\(what): opaque", file: file, line: line)
        XCTAssertGreaterThan(Int(p.r), Int(p.g) + 100, "\(what): red", file: file, line: line)
        XCTAssertGreaterThan(Int(p.r), Int(p.b) + 100, "\(what): red", file: file, line: line)
    }

    // MARK: - The shape (STREAM.md §2.4)

    /// **Four frames, one cel, on frame 2 → [1] [2] [3–4], and only [2] changes.** The middle cel
    /// holds one image with the stream's placement and a fresh id; the neighbours hold the
    /// original stream, id and all; the playhead stays.
    func testABakeOnTheSecondFrameSplitsIntoThreeCelsAndOnlyTheMiddleOneChanges() throws {
        let f = fixture()
        XCTAssertEqual(f.spans, [0..<4], "Setup: one four-frame cel")
        let stream = try XCTUnwrap(element(f, atFrame: 1)?.stream)
        f.manager.currentFrame = 1
        let stepsBefore = f.manager.history.undoStack.count

        XCTAssertEqual(bake(f, atFrame: 1), .baked)

        XCTAssertEqual(f.spans, [0..<1, 1..<2, 2..<4], "[1] [2] [3–4]")
        XCTAssertEqual(f.manager.currentFrame, 1, "the playhead stays on the baked frame")
        XCTAssertEqual(f.manager.history.undoStack.count, stepsBefore + 1, "one undo step")

        let image = try XCTUnwrap(element(f, atFrame: 1)?.image, "[2] holds one placed image")
        XCTAssertEqual(image.transform, stream.transform, "the same placement")
        XCTAssertEqual(image.aspect, stream.aspect)
        XCTAssertEqual(image.stretchAxis, stream.stretchAxis)
        XCTAssertEqual(image.mirrored, stream.mirrored)
        XCTAssertEqual(image.naturalSize, stream.naturalSize, "the snapshot is the stream's own size")
        XCTAssertNotEqual(image.id, stream.id, "the image is minted fresh")

        let left = try XCTUnwrap(element(f, atFrame: 0)?.stream, "[1] still holds the stream")
        let right = try XCTUnwrap(element(f, atFrame: 3)?.stream, "[3–4] still holds the stream")
        XCTAssertEqual(left.id, stream.id, "the left neighbour is the block's own canvas, untouched")
        XCTAssertEqual(right.id, stream.id, "the right neighbour is splitCel's copy, ids verbatim")
        XCTAssertEqual(left.host, stream.host)
        XCTAssertEqual(right.host, stream.host)
    }

    /// Bake on frame 1 → [1] [2–4]: one cut, behind the frame.
    func testABakeOnTheFirstFrameCutsOnceBehindIt() throws {
        let f = fixture()
        XCTAssertEqual(bake(f, atFrame: 0), .baked)
        XCTAssertEqual(f.spans, [0..<1, 1..<4], "[1] [2–4]")
        XCTAssertNotNil(element(f, atFrame: 0)?.image, "[1] is the image")
        XCTAssertNotNil(element(f, atFrame: 2)?.stream, "[2–4] is the stream")
    }

    /// Bake on frame 4 → [1–3] [4]: one cut, in front of the frame.
    func testABakeOnTheLastFrameCutsOnceInFrontOfIt() throws {
        let f = fixture()
        XCTAssertEqual(bake(f, atFrame: 3), .baked)
        XCTAssertEqual(f.spans, [0..<3, 3..<4], "[1–3] [4]")
        XCTAssertNotNil(element(f, atFrame: 1)?.stream, "[1–3] is the stream")
        XCTAssertNotNil(element(f, atFrame: 3)?.image, "[4] is the image")
    }

    /// A one-frame cel is the swap alone: no cut, one cel, the image where the stream was.
    func testABakeOnAOneFrameCelIsTheSwapAlone() throws {
        let f = fixture(frames: 1)
        XCTAssertEqual(f.spans, [0..<1], "Setup")
        XCTAssertEqual(bake(f, atFrame: 0), .baked)
        XCTAssertEqual(f.spans, [0..<1], "still one cel")
        XCTAssertNotNil(element(f, atFrame: 0)?.image)
        XCTAssertTrue(f.cels[0].vector!.streams.isEmpty, "the stream is gone from the cel")
    }

    /// A second bake on frame 3 after the first → [1] [2] [3] [4].
    func testASecondBakeOnTheThirdFrameGivesFourCels() throws {
        let f = fixture()
        XCTAssertEqual(bake(f, atFrame: 1), .baked)
        XCTAssertEqual(bake(f, atFrame: 2), .baked)
        XCTAssertEqual(f.spans, [0..<1, 1..<2, 2..<3, 3..<4], "[1] [2] [3] [4]")
        XCTAssertNotNil(element(f, atFrame: 0)?.stream)
        XCTAssertNotNil(element(f, atFrame: 1)?.image)
        XCTAssertNotNil(element(f, atFrame: 2)?.image)
        XCTAssertNotNil(element(f, atFrame: 3)?.stream)
    }

    // MARK: - Undo

    /// Undo puts the single stream cel back — one cel, one stream — and the stream keeps ticking in
    /// it afterwards: the coordinator finds the element again and a newer frame reaches the picture.
    func testUndoRestoresTheSingleStreamCelAndTheStreamKeepsTicking() throws {
        let f = fixture()
        let stream = try XCTUnwrap(element(f, atFrame: 1)?.stream)
        XCTAssertEqual(bake(f, atFrame: 1), .baked)
        XCTAssertEqual(f.spans, [0..<1, 1..<2, 2..<4], "Setup: baked")

        f.manager.undo()

        XCTAssertEqual(f.spans, [0..<4], "one cel again")
        let restored = try XCTUnwrap(element(f, atFrame: 1)?.stream, "one stream again")
        XCTAssertEqual(restored.id, stream.id)
        XCTAssertNotNil(restored.displayFrame, "with the picture it had")

        // A newer frame, red, reaches the restored cel through the tick.
        f.manager.currentFrame = 1
        feed(f, color: .red, index: 2)
        assertRed(compositedPixel(f, atFrame: 1, x: 32, y: 32), "after undo the stream is live again")

        f.manager.redo()
        XCTAssertEqual(f.spans, [0..<1, 1..<2, 2..<4], "redo bakes again")
        assertGreen(compositedPixel(f, atFrame: 1, x: 32, y: 32), "the redone bake holds the green snapshot")
    }

    // MARK: - What is drawn

    /// **The baked frame holds its picture while the stream moves on.** Green is fed, frame 2 is
    /// baked, then red is fed: frame 2 composites green (the snapshot) and frames 1 and 3 composite
    /// red (the stream, live). Two operands that differ, through the real compositor.
    func testTheBakedCelKeepsItsPictureWhileTheNeighboursFollowTheStream() throws {
        let f = fixture(color: .green)
        XCTAssertEqual(bake(f, atFrame: 1), .baked)
        assertGreen(compositedPixel(f, atFrame: 1, x: 32, y: 32), "the bake is the green frame")

        // The stream goes red. The tick feeds the cel at the current frame, so visit both neighbours.
        f.manager.currentFrame = 0
        feed(f, color: .red, index: 2)
        f.manager.currentFrame = 3
        feed(f, color: .red, index: 2)

        assertRed(compositedPixel(f, atFrame: 0, x: 32, y: 32), "[1] follows the stream")
        assertRed(compositedPixel(f, atFrame: 3, x: 32, y: 32), "[3–4] follows the stream")
        assertGreen(compositedPixel(f, atFrame: 1, x: 32, y: 32), "[2] is baked and holds green")
        XCTAssertEqual(compositedPixel(f, atFrame: 1, x: 2, y: 2).a, 0, "and nothing outside the rect")
    }

    /// The two split copies share one element id, and the tick still feeds both — the drawn-frame
    /// memo is keyed by cel. The cel at frame 3 was copied holding green; a red frame at the same
    /// slot index the cel at frame 0 already drew must still reach it.
    func testTheTickFeedsBothSplitCopiesOfTheStream() throws {
        let f = fixture(color: .green)
        XCTAssertEqual(bake(f, atFrame: 1), .baked)
        f.manager.currentFrame = 0
        feed(f, color: .red, index: 2)
        assertRed(compositedPixel(f, atFrame: 0, x: 32, y: 32), "Setup: [1] drew slot 2")
        // Same slot index, other cel. A memo keyed on the element alone would skip this.
        f.manager.currentFrame = 3
        feed(f, color: .red, index: 2)
        assertRed(compositedPixel(f, atFrame: 3, x: 32, y: 32), "[3–4] drew slot 2 too")
    }

    // MARK: - Refusals

    /// No picture yet — the placeholder is not a frame — is refused before anything is touched,
    /// with the sentence the artist reads.
    func testNoFrameYetIsRefusedWithAMessageAndNothingChanges() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 0
        XCTAssertNotNil(manager.insertStream(host: "laptop", port: 47301, status: status()))
        manager.commitVectorFloatIfNeeded()
        let layerIndex = manager.layers.count - 1
        manager.layers[layerIndex].cels[0].frameCount = 4
        let stepsBefore = manager.history.undoStack.count

        let outcome = manager.bakeStreamFrame(layerIndex: layerIndex, celIndex: 0, atFrame: 1)

        XCTAssertEqual(outcome, .refused(.noFrameYet))
        XCTAssertEqual(manager.layers[layerIndex].cels.count, 1, "no split")
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore, "no step")
        XCTAssertEqual(CanvasManager.StreamBakeRefusal.noFrameYet.phrase, "No picture from the computer yet")
        let notice = CanvasNotice(.streamBakeRefused(.noFrameYet))
        XCTAssertEqual(notice.message, "No picture from the computer yet")
        XCTAssertEqual(notice.code, "streamBakeRefused")
        XCTAssertNil(notice.actionTitle, "nothing a button could do")
    }

    /// A cel with no stream, and a frame outside the cel, are `.notOnStreamCel`.
    func testACelWithNoStreamIsRefused() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.layers.count - 1
        XCTAssertEqual(manager.bakeStreamFrame(layerIndex: layerIndex, celIndex: 0, atFrame: 0),
                       .refused(.notOnStreamCel))
        let f = fixture()
        XCTAssertEqual(f.manager.bakeStreamFrame(layerIndex: f.layerIndex, celIndex: 0, atFrame: 9),
                       .refused(.notOnStreamCel), "frame 9 is outside [0, 4)")
        XCTAssertEqual(f.spans, [0..<4], "nothing changed")
    }

    // MARK: - Freeze (STREAM.md §5.4)

    /// Freeze holds the picture: a newer frame does not reach a frozen element, and a bake while
    /// frozen bakes the frozen picture. Unfreeze lets the next frame through. Neither is an undo
    /// step.
    func testFreezeHoldsThePictureAndBakeBakesTheFrozenOne() throws {
        let f = fixture(color: .green)
        let stream = try XCTUnwrap(element(f, atFrame: 0)?.stream)
        let stepsBefore = f.manager.history.undoStack.count

        XCTAssertTrue(f.manager.setStreamFrozen(layerIndex: f.layerIndex, celIndex: 0,
                                                elementID: stream.id, true))
        XCTAssertEqual(f.manager.history.undoStack.count, stepsBefore, "freeze is not an undo step")
        XCTAssertTrue(try XCTUnwrap(element(f, atFrame: 0)?.stream).isFrozen)
        XCTAssertFalse(f.manager.setStreamFrozen(layerIndex: f.layerIndex, celIndex: 0,
                                                 elementID: stream.id, true), "already frozen: no change")

        feed(f, color: .red, index: 2)
        assertGreen(compositedPixel(f, atFrame: 0, x: 32, y: 32), "frozen: the red frame did not land")

        XCTAssertEqual(bake(f, atFrame: 1), .baked)
        assertGreen(compositedPixel(f, atFrame: 1, x: 32, y: 32), "the bake is the frozen green")

        // Unfreeze the cel at frame 0 — the bake left it frozen — and the red frame lands.
        XCTAssertTrue(f.manager.setStreamFrozen(layerIndex: f.layerIndex, celIndex: 0,
                                                elementID: stream.id, false))
        XCTAssertEqual(f.manager.history.undoStack.count, stepsBefore + 1, "only the bake was a step")
        f.manager.currentFrame = 0
        feed(f, color: .red, index: 3)
        assertRed(compositedPixel(f, atFrame: 0, x: 32, y: 32), "unfrozen: the next frame lands")
    }

    /// Freezing invalidates nothing: neither version moves, so no memo is dropped and the bake
    /// is not re-keyed for a picture that did not change.
    func testFreezeMovesNeitherVersion() throws {
        let f = fixture()
        let vector = try XCTUnwrap(f.cels[0].vector)
        let stream = try XCTUnwrap(vector.streams.first)
        let version = vector.version
        let committed = vector.committedVersion
        XCTAssertTrue(f.manager.setStreamFrozen(layerIndex: f.layerIndex, celIndex: 0,
                                                elementID: stream.id, true))
        XCTAssertEqual(vector.version, version)
        XCTAssertEqual(vector.committedVersion, committed)
    }

    // MARK: - The snapshot's size

    /// A decoded frame whose pixel size disagrees with the STATUS-reported size is resampled to the
    /// reported size, so the placed image's rect is the rect the stream drew into.
    func testASnapshotIsResampledToTheStreamsOwnSizeWhenTheyDisagree() {
        let frame = UIImage(cgImage: solidImage(.green, size: CGSize(width: 16, height: 8)))
        let same = CanvasManager.streamSnapshot(frame, fitting: CGSize(width: 16, height: 8))
        XCTAssertTrue(same === frame, "the same object when nothing needs doing")
        let fitted = CanvasManager.streamSnapshot(frame, fitting: CGSize(width: 8, height: 4))
        XCTAssertEqual(fitted.size, CGSize(width: 8, height: 4))
        XCTAssertEqual(fitted.scale, 1)
    }
}
