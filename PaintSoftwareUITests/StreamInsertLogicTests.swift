import XCTest
import UIKit

/// Pure-logic tests for `CanvasManager.insertStream(host:port:status:)` and the coordinator's tick
/// — STREAM.md §5.3 and §5.7, with no socket anywhere.
///
/// `insertStream` takes an already-built `StreamStatus`, which is what lets the verb be tested
/// headlessly; the tick is driven through `ScreenStreamCoordinator.frameSourceOverride`, a
/// per-endpoint image source standing in for a decoder's slot, and asserted on what is *drawn*
/// rather than on a flag — a tick that wrote nothing to the picture would fail the pixel read.
@MainActor
final class StreamInsertLogicTests: XCTestCase {

    private static let size = CanvasFixture.canvasSize   // 64 × 64

    private func status(width: Int = 1920, height: Int = 1080, name: String = "Blender") -> StreamStatus {
        StreamStatus(source: StreamStatus.Source(kind: "window", name: name),
                     width: width, height: height, fps: 30, streaming: true)
    }

    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 8, height: 4)) -> CGImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }.cgImage!
    }

    /// RGBA at a canvas point of a render.
    private func pixel(_ image: UIImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard let cg = image.cgImage else { return (0, 0, 0, 0) }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / Self.size.width
        let px = Int(CGFloat(x) * scale), py = Int(CGFloat(y) * scale)
        let i = (py * width + px) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// The new layer's one cel and its canvas, or a failure.
    private func streamCel(_ manager: CanvasManager, file: StaticString = #filePath,
                           line: UInt = #line) -> (cel: Cel, vector: VectorCanvas, stream: VectorStreamElement)? {
        guard let layer = manager.layers.last, layer.kind == .vector, layer.cels.count == 1,
              let vector = layer.cels[0].vector, let stream = vector.streams.first else {
            XCTFail("Expected the last layer to be a vector layer with one cel holding one stream",
                    file: file, line: line)
            return nil
        }
        return (layer.cels[0], vector, stream)
    }

    // MARK: - The insert

    /// **Its own new vector layer, one cel from the current frame to the end of the scene, one
    /// stream element fitted to the canvas.** The fixture's scene is twelve frames; standing on
    /// frame 4 gives a cel [4, 12).
    func testInsertMakesANewLayerWithOneCelFromTheCurrentFrameToTheEndOfTheScene() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 4
        let scene = manager.contentEndFrame
        XCTAssertEqual(scene, 12, "Setup: the fixture's scene is twelve frames")
        let before = manager.layers.count

        let element = try XCTUnwrap(manager.insertStream(host: "laptop", port: 47301, status: status()))

        XCTAssertEqual(manager.layers.count, before + 1, "one new layer")
        let (cel, vector, stream) = try XCTUnwrap(streamCel(manager))
        XCTAssertEqual(cel.startFrame, 4, "from the current frame")
        XCTAssertEqual(cel.frameCount, 8, "to the end of the scene")
        XCTAssertEqual(cel.endFrame, scene)
        XCTAssertEqual(manager.contentEndFrame, scene, "the insert never lengthens the timeline")
        XCTAssertEqual(vector.elements.count, 1)
        XCTAssertEqual(stream.id, element.id)
        XCTAssertEqual(stream.host, "laptop")
        XCTAssertEqual(stream.port, 47301)
        XCTAssertEqual(stream.sourceLabel, "Blender")
        XCTAssertEqual(stream.naturalSize, CGSize(width: 1920, height: 1080), "the laptop's size")
        XCTAssertFalse(stream.isFrozen)
        XCTAssertNil(stream.displayFrame, "no frame yet")
        XCTAssertTrue(vector.holdsStream)
    }

    /// The fit is `insertVideo`'s: centred, 80% of the canvas along the tighter axis, the laptop's
    /// aspect kept. 1920×1080 on a 64×64 canvas is width-bound: 64 × 0.8 / 1920.
    func testTheElementIsFittedToTheCanvasLikeAVideo() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertNotNil(manager.insertStream(host: "laptop", port: 47301, status: status()))
        let (_, _, stream) = try XCTUnwrap(streamCel(manager))
        XCTAssertEqual(stream.transform.position, CGPoint(x: 32, y: 32), "centred")
        XCTAssertEqual(stream.transform.scale, 64 * 0.8 / 1920, accuracy: 1e-9)
        XCTAssertEqual(stream.transform.rotation, 0)
        XCTAssertEqual(stream.aspect, 1)
        XCTAssertFalse(stream.mirrored)
        // And a tall source is height-bound.
        let tall = CanvasFixture.manager(layerCount: 1)
        XCTAssertNotNil(tall.insertStream(host: "laptop", port: 47301, status: status(width: 600, height: 1200)))
        XCTAssertEqual(try XCTUnwrap(streamCel(tall)).stream.transform.scale, 64 * 0.8 / 1200, accuracy: 1e-9)
    }

    /// A playhead past the end of the scene gets a one-frame cel at the playhead — the artist asked
    /// for a stream on the frame they are looking at.
    func testAPlayheadPastTheSceneGetsAOneFrameCelThere() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 20
        XCTAssertNotNil(manager.insertStream(host: "laptop", port: 47301, status: status()))
        let (cel, _, _) = try XCTUnwrap(streamCel(manager))
        XCTAssertEqual(cel.startFrame, 20)
        XCTAssertEqual(cel.frameCount, 1)
    }

    /// **Always its own layer**, even with a vector layer active — `insertVideo`'s §2.1 teeth.
    func testASecondInsertMakesASecondLayerAndLeavesTheFirstAlone() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertNotNil(manager.insertStream(host: "laptop", port: 47301, status: status()))
        manager.commitVectorFloatIfNeeded()
        let firstLayerID = try XCTUnwrap(manager.layers.last).id
        let count = manager.layers.count

        XCTAssertNotNil(manager.insertStream(host: "other", port: 47302, status: status(name: "Screen 2")))

        XCTAssertEqual(manager.layers.count, count + 1)
        let first = try XCTUnwrap(manager.layers.first { $0.id == firstLayerID })
        XCTAssertEqual(try XCTUnwrap(first.cels[0].vector).streams.count, 1, "the first layer is untouched")
        XCTAssertEqual(try XCTUnwrap(streamCel(manager)).stream.host, "other")
        XCTAssertEqual(manager.streamCoordinator.referencedEndpoints,
                       [StreamEndpoint(host: "laptop", port: 47301), StreamEndpoint(host: "other", port: 47302)])
    }

    /// A status with no picture size is refused: nothing to fit, no layer added.
    func testAStatusWithNoSizeIsRefused() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let count = manager.layers.count
        XCTAssertNil(manager.insertStream(host: "laptop", port: 47301, status: status(width: 0, height: 0)))
        XCTAssertEqual(manager.layers.count, count)
    }

    // MARK: - The Move box

    /// **The element arrives held in the Move box** — `ImportedImageMoveBoxLogicTests`' shape: the
    /// float carries exactly the new element and nothing else.
    func testTheElementIsInTheMoveBoxAfterInsert() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let element = try XCTUnwrap(manager.insertStream(host: "laptop", port: 47301, status: status()))
        let float = try XCTUnwrap(manager.vectorFloat, "A stream must arrive in the Move box")
        XCTAssertEqual(float.parts[0].insideIDs, [element.id], "the box holds exactly the stream")
        XCTAssertEqual(float.parts[0].layerID, try XCTUnwrap(manager.layers.last).id)
        let (_, vector, _) = try XCTUnwrap(streamCel(manager))
        XCTAssertEqual(vector.suppressedElementIDs, [element.id], "lifted out of the layer's own render")
        XCTAssertTrue(manager.commitVectorFloatIfNeeded(), "and the box commits like any Move")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
    }

    // MARK: - Undo

    /// Undo takes the element away and the coordinator's endpoint set with it; redo brings both back.
    func testUndoRemovesTheElementAndTheEndpoint() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertNotNil(manager.insertStream(host: "laptop", port: 47301, status: status()))
        manager.commitVectorFloatIfNeeded()
        let (_, vector, _) = try XCTUnwrap(streamCel(manager))
        XCTAssertEqual(manager.streamCoordinator.referencedEndpoints.count, 1)

        manager.undo()
        XCTAssertTrue(vector.streams.isEmpty, "the insert is one step")
        XCTAssertTrue(manager.streamCoordinator.referencedEndpoints.isEmpty)
        manager.redo()
        XCTAssertEqual(vector.streams.count, 1)
        XCTAssertEqual(manager.streamCoordinator.referencedEndpoints.count, 1)
    }

    // MARK: - The tick

    /// A manager with a committed stream on frame 0..12, a frame source that answers `image` at
    /// `index`, and the two repaint closures counting.
    private func tickFixture(image: CGImage, index: Int = 1)
        -> (manager: CanvasManager, vector: VectorCanvas, stream: VectorStreamElement,
            repaints: () -> Int, floatRepaints: () -> Int) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 0
        _ = manager.insertStream(host: "laptop", port: 47301, status: status(width: 8, height: 4))
        manager.commitVectorFloatIfNeeded()
        let (_, vector, stream) = streamCel(manager)!
        var repaints = 0
        var floatRepaints = 0
        let coordinator = manager.streamCoordinator
        coordinator.onLayerNeedsRepaint = { _ in repaints += 1 }
        coordinator.onFloatNeedsRepaint = { _ in floatRepaints += 1 }
        coordinator.frameSourceOverride = { endpoint in
            endpoint.host == "laptop" ? (index, image) : nil
        }
        return (manager, vector, stream, { repaints }, { floatRepaints })
    }

    /// **A tick puts the frame on the element and the picture changes.** Rendered and sampled: the
    /// stream's rect is centred at (32, 32); before the tick it is the grey placeholder, after it is
    /// solid green.
    func testATickDeliversTheFrameAndThePictureChanges() throws {
        let fixture = tickFixture(image: solidImage(.green))
        let before = pixel(fixture.vector.render(), 32, 32)
        XCTAssertEqual(Int(before.g), Int(before.r), accuracy: 8, "the placeholder is grey")

        fixture.manager.streamCoordinator.tick()

        XCTAssertEqual(fixture.repaints(), 1, "the layer host is asked to repaint once")
        XCTAssertEqual(fixture.floatRepaints(), 0)
        XCTAssertNotNil(try XCTUnwrap(fixture.vector.streams.first).displayFrame)
        let after = pixel(fixture.vector.render(), 32, 32)
        XCTAssertEqual(after.a, 255)
        XCTAssertGreaterThan(Int(after.g), Int(after.r) + 100, "the green frame reached the canvas")
        XCTAssertEqual(pixel(fixture.vector.render(), 2, 2).a, 0, "and nothing outside the rect")
    }

    /// A second tick on the same frame index does nothing: no write, no repaint.
    func testATickOnAnUnchangedFrameIsFree() {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.manager.streamCoordinator.tick()
        let version = fixture.vector.version
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.repaints(), 1, "the second tick found nothing new")
        XCTAssertEqual(fixture.vector.version, version)
    }

    /// The bake key stays still across ticks: `committedVersion` does not move, so nothing is
    /// re-baked to disk thirty times a second.
    func testATickDoesNotMoveTheCommittedVersion() {
        let fixture = tickFixture(image: solidImage(.green))
        let committed = fixture.vector.committedVersion
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.vector.committedVersion, committed)
        XCTAssertNotNil(fixture.vector.streams.first?.displayFrame, "the frame did land")
    }

    /// **No tick while playing** — STREAM.md §2.9.
    func testNoTickWhilePlaying() {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.manager.play()
        XCTAssertTrue(fixture.manager.isPlaying, "Setup")
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.repaints(), 0)
        XCTAssertNil(fixture.vector.streams.first?.displayFrame)
        fixture.manager.stopPlayback()
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.repaints(), 1, "and it resumes on stop")
    }

    /// A hidden layer is not fed; showing it again is.
    func testAHiddenLayerIsNotFed() throws {
        let fixture = tickFixture(image: solidImage(.green))
        let index = try XCTUnwrap(fixture.manager.layers.indices.last)
        fixture.manager.layers[index].isVisible = false
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.repaints(), 0)
        fixture.manager.layers[index].isVisible = true
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.repaints(), 1)
    }

    /// A cel that is not the one at the current frame is not fed.
    func testACelNotAtTheCurrentFrameIsNotFed() {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.manager.currentFrame = 20   // past the cel's [0, 12)
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.repaints(), 0)
    }

    /// A frozen element is not fed — stage 2's Freeze reads this flag; the tick honours it now.
    func testAFrozenElementIsNotFed() throws {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.vector.elements = fixture.vector.elements.map { element in
            guard case .stream(var stream) = element else { return element }
            stream.isFrozen = true
            return .stream(stream)
        }
        fixture.vector.bumpVersion()
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.repaints(), 0)
        XCTAssertNil(try XCTUnwrap(fixture.vector.streams.first).displayFrame)
    }

    /// **While the Move box holds the element, the tick refreshes the float and not the host** —
    /// the frame is written for the commit, the layer's memo is left alone.
    func testATickWhileTheElementFloatsRefreshesTheFloatNotTheHost() throws {
        let fixture = tickFixture(image: solidImage(.green))
        XCTAssertTrue(fixture.manager.beginVectorMove(ofElementIDs: [fixture.stream.id]))
        let version = fixture.vector.version
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.floatRepaints(), 1)
        XCTAssertEqual(fixture.repaints(), 0)
        XCTAssertEqual(fixture.vector.version, version, "the layer's own picture did not change")
        XCTAssertNotNil(try XCTUnwrap(fixture.vector.streams.first).displayFrame, "held for the commit")
        fixture.manager.commitVectorFloatIfNeeded()
        let after = pixel(fixture.vector.render(), 32, 32)
        XCTAssertGreaterThan(Int(after.g), Int(after.r) + 100, "the commit draws the newest frame")
    }

    // MARK: - STATUS

    /// A STATUS rewrites the element's size and label as a committed change, and leaves the
    /// placement where it was.
    func testAStatusUpdatesTheSizeAndLabelAndNotThePlacement() throws {
        let fixture = tickFixture(image: solidImage(.green))
        let committed = fixture.vector.committedVersion
        let placement = fixture.stream.transform

        fixture.manager.streamCoordinator.statusArrived(status(width: 1280, height: 720, name: "Screen 2"),
                                                        from: StreamEndpoint(host: "laptop", port: 47301))

        let stream = try XCTUnwrap(fixture.vector.streams.first)
        XCTAssertEqual(stream.naturalSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(stream.sourceLabel, "Screen 2")
        XCTAssertEqual(stream.transform, placement, "the placement stays")
        XCTAssertGreaterThan(fixture.vector.committedVersion, committed, "a size is a document change")
        XCTAssertEqual(fixture.manager.streamCoordinator.status(for: StreamEndpoint(host: "laptop", port: 47301))?.width, 1280)
    }

    /// A STATUS for another endpoint touches nothing.
    func testAStatusForAnotherEndpointTouchesNothing() throws {
        let fixture = tickFixture(image: solidImage(.green))
        let committed = fixture.vector.committedVersion
        fixture.manager.streamCoordinator.statusArrived(status(width: 1280, height: 720),
                                                        from: StreamEndpoint(host: "elsewhere", port: 1))
        XCTAssertEqual(try XCTUnwrap(fixture.vector.streams.first).naturalSize, CGSize(width: 8, height: 4))
        XCTAssertEqual(fixture.vector.committedVersion, committed)
    }

    // MARK: - Close

    /// Closing the document stops every client and forgets every status.
    func testStopAllForgetsEverything() {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.manager.streamCoordinator.statusArrived(status(), from: StreamEndpoint(host: "laptop", port: 47301))
        fixture.manager.closeFrameBaker()
        XCTAssertTrue(fixture.manager.streamCoordinator.activeEndpoints.isEmpty)
        XCTAssertNil(fixture.manager.streamCoordinator.status(for: StreamEndpoint(host: "laptop", port: 47301)))
    }
}
