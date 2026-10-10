import XCTest
import UIKit

/// Pure-logic tests for `CanvasManager.insertStream(host:port:status:)` and the coordinator's tick
/// — STREAM.md §5.3 and §5.7, with no socket anywhere.
///
/// `insertStream` takes an already-built `StreamStatus`, which is what lets the verb be tested
/// headlessly; the tick is driven through `ScreenStreamCoordinator.frameSourceOverride`, a
/// per-endpoint image source standing in for a decoder's slot, and asserted on what is *drawn*
/// rather than on a flag — a tick that wrote nothing to the picture would fail the pixel read.
/// TODO (96)'s two sentences are the "not on screen" section: a cel the artist is not looking at
/// is written all the same, so coming back to it finds the newest picture without another frame.
@MainActor
final class StreamInsertLogicTests: XCTestCase {

    private static let size = CanvasFixture.canvasSize   // 64 × 64

    /// A temp store for the baker the dirty-sweep test builds.
    private let bakeRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("StreamInsertLogicTests-" + UUID().uuidString, isDirectory: true)

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: bakeRoot)
        Compositor.backend = Compositor.defaultBackend
        super.tearDown()
    }

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
    /// `index`, and the present closure counting.
    private func tickFixture(image: CGImage, index: Int = 1)
        -> (manager: CanvasManager, vector: VectorCanvas, stream: VectorStreamElement,
            presents: () -> Int, slot: (Int, CGImage) -> Void) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 0
        _ = manager.insertStream(host: "laptop", port: 47301, status: status(width: 8, height: 4))
        manager.commitVectorFloatIfNeeded()
        let (_, vector, stream) = streamCel(manager)!
        var presents = 0
        var slot = (index, image)
        let coordinator = manager.streamCoordinator
        coordinator.onStreamFrame = { _, _ in presents += 1 }
        coordinator.frameSourceOverride = { endpoint in
            endpoint.host == "laptop" ? slot : nil
        }
        return (manager, vector, stream, { presents }, { slot = ($0, $1) })
    }

    /// Whether a render of `vector` is `color` at the stream's centre (32, 32).
    private func centreIs(_ color: UIColor, _ vector: VectorCanvas) -> Bool {
        let p = pixel(vector.render(), 32, 32)
        switch color {
        case .green: return Int(p.g) > Int(p.r) + 100 && p.a == 255
        case .red: return Int(p.r) > Int(p.g) + 100 && p.a == 255
        default: return false
        }
    }

    /// **A tick puts the frame on the element, the picture changes, and the element is presented.**
    /// Rendered and sampled: the stream's rect is centred at (32, 32); before the tick it is the
    /// grey placeholder, after it is solid green.
    func testATickDeliversTheFrameAndThePictureChanges() throws {
        let fixture = tickFixture(image: solidImage(.green))
        let before = pixel(fixture.vector.render(), 32, 32)
        XCTAssertEqual(Int(before.g), Int(before.r), accuracy: 8, "the placeholder is grey")

        fixture.manager.streamCoordinator.tick()

        XCTAssertEqual(fixture.presents(), 1, "the displayed element is presented once")
        XCTAssertNotNil(try XCTUnwrap(fixture.vector.streams.first).displayFrame)
        XCTAssertTrue(centreIs(.green, fixture.vector), "the green frame reached the canvas")
        XCTAssertEqual(pixel(fixture.vector.render(), 2, 2).a, 0, "and nothing outside the rect")
    }

    /// A second tick on the same frame index does nothing: no write, no present.
    func testATickOnAnUnchangedFrameIsFree() {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.manager.streamCoordinator.tick()
        let version = fixture.vector.version
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.presents(), 1, "the second tick found nothing new")
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

    /// **Sixty frames cost no canvas-sized render and hold no more memo than one** — TODO (97)'s
    /// engine half. The tick writes the element and damages the memo's region; nothing here walks
    /// the canvas, and the damaged memo is held as one base for the repair, not one per frame.
    /// Each iteration in its own pool, so the count is of what a frame leaves behind, not of what
    /// the loop has not released yet (CLAUDE.md's growth-measurement rule).
    func testSixtyFramesRasterizeNothingAndHoldOneMemo() {
        let fixture = tickFixture(image: solidImage(.green))
        _ = fixture.vector.render()
        let rasterizations = fixture.vector.rasterizations
        let bytes = fixture.vector.cachedImageBytes
        for index in 2...61 {
            autoreleasepool {
                fixture.slot(index, solidImage(index.isMultiple(of: 2) ? .red : .green))
                fixture.manager.streamCoordinator.tick()
            }
        }
        XCTAssertEqual(fixture.presents(), 60, "every new frame was presented")
        XCTAssertEqual(fixture.vector.rasterizations, rasterizations, "and none was rasterized")
        XCTAssertEqual(fixture.vector.cachedImageBytes, bytes, "the memo held for the repair is one picture")
    }

    /// **No tick while playing** — STREAM.md §2.9.
    func testNoTickWhilePlaying() {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.manager.play()
        XCTAssertTrue(fixture.manager.isPlaying, "Setup")
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.presents(), 0)
        XCTAssertNil(fixture.vector.streams.first?.displayFrame)
        fixture.manager.stopPlayback()
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.presents(), 1, "and it resumes on stop")
    }

    // MARK: - TODO (96): a cel that is not on screen still gets the frame

    /// **A cel on another frame is written and not presented, and the frame change onto it finds
    /// the newest picture.** The owner's first sentence: *"The stream does not reload when the
    /// computer updated while on a different frame, and then the frame changes onto the one with
    /// the stream."* Green lands on screen; the artist leaves; the laptop moves to red; the artist
    /// comes back to a red cel without a further frame having to arrive.
    func testTheFrameChangeOntoAStreamCelFindsTheNewestPicture() {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.manager.streamCoordinator.tick()
        XCTAssertTrue(centreIs(.green, fixture.vector), "Setup: green on screen")

        fixture.manager.currentFrame = 20   // past the cel's [0, 12)
        fixture.slot(2, solidImage(.red))
        let version = fixture.vector.version
        fixture.manager.streamCoordinator.tick()

        XCTAssertEqual(fixture.presents(), 1, "the away tick presented nothing")
        XCTAssertGreaterThan(fixture.vector.version, version, "but the cel's picture is stale and says so")
        XCTAssertTrue(centreIs(.red, fixture.vector), "and it holds red")

        fixture.manager.currentFrame = 0
        XCTAssertTrue(centreIs(.red, fixture.vector), "the frame change finds red with no tick at all")
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.presents(), 1, "the same frame is not presented again")
    }

    /// **After Bake Frame the cels either side share one picture**, so a frame written while the
    /// artist is on one side is what they find on the other — the split copies the element and the
    /// copy's `StreamPicture` is the same box. Both canvases' memos are told, or the far cel would
    /// hold the newest picture in its element and an old one in its memo.
    func testTheCelsEitherSideOfABakeShareThePicture() throws {
        let fixture = tickFixture(image: solidImage(.green))
        fixture.manager.streamCoordinator.tick()
        let layerIndex = try XCTUnwrap(fixture.manager.layers.indices.last)
        XCTAssertEqual(fixture.manager.bakeStreamFrame(layerIndex: layerIndex, celIndex: 0, atFrame: 5), .baked)
        let cels = fixture.manager.layers[layerIndex].cels
        XCTAssertEqual(cels.count, 3, "Setup: [0–4] [5] [6–11]")
        let far = try XCTUnwrap(cels[2].vector)
        _ = far.render()
        let farVersion = far.version

        fixture.slot(2, solidImage(.red))
        fixture.manager.streamCoordinator.tick()

        XCTAssertTrue(try XCTUnwrap(far.streams.first).displayFrame === fixture.vector.streams.first?.displayFrame,
                      "one picture between the two cels")
        XCTAssertGreaterThan(far.version, farVersion, "the far cel's memo was told")
        XCTAssertTrue(centreIs(.red, far), "and draws red when the artist gets there")
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
        XCTAssertEqual(fixture.presents(), 0)
        XCTAssertNil(try XCTUnwrap(fixture.vector.streams.first).displayFrame)
    }

    /// **While the Move box holds the element, the tick presents it and leaves the layer's memo
    /// alone** — the frame is written for the commit, the float's surface shows it meanwhile.
    func testATickWhileTheElementFloatsPresentsItAndNotTheMemo() throws {
        let fixture = tickFixture(image: solidImage(.green))
        XCTAssertTrue(fixture.manager.beginVectorMove(ofElementIDs: [fixture.stream.id]))
        let version = fixture.vector.version
        fixture.manager.streamCoordinator.tick()
        XCTAssertEqual(fixture.presents(), 1)
        XCTAssertEqual(fixture.vector.version, version, "the layer's own picture did not change")
        XCTAssertNotNil(try XCTUnwrap(fixture.vector.streams.first).displayFrame, "held for the commit")
        fixture.manager.commitVectorFloatIfNeeded()
        XCTAssertTrue(centreIs(.green, fixture.vector), "the commit draws the newest frame")
    }

    // MARK: - TODO (156): a layer nobody can see is not fed

    /// A layer made invisible one of the two ways the artist can: its own switch, or a hidden folder
    /// above it.
    private func hide(_ index: Int, in manager: CanvasManager, viaFolder: Bool) {
        guard viaFolder else {
            manager.layers[index].isVisible = false
            return
        }
        let folderID = manager.addFolder()
        manager.layers[index].parentFolderID = folderID
        if let folder = manager.folders.firstIndex(where: { $0.id == folderID }) {
            manager.folders[folder].isVisible = false
        }
    }

    private func show(_ index: Int, in manager: CanvasManager) {
        manager.layers[index].parentFolderID = nil
        manager.layers[index].isVisible = true
    }

    private func makeBaker(_ manager: CanvasManager) -> FrameBaker {
        FrameBaker(manager: manager, store: FrameBakeStore(root: bakeRoot),
                   ring: DecodedFrameRing(byteBudget: 1 << 20))
    }

    /// Runs the baker's own loop to a stop — `noteDocumentChanged` is the call the app makes, so the
    /// sweep and the kick are the real ones — and returns when it has nothing left.
    private func bakeEverything(_ baker: FrameBaker) {
        let idle = expectation(description: "the bake queue drains")
        var fulfilled = false
        baker.onIdle = {
            guard !fulfilled else { return }
            fulfilled = true
            idle.fulfill()
        }
        baker.noteDocumentChanged()
        wait(for: [idle], timeout: 60)
        baker.onIdle = nil
    }

    private func pending(_ baker: FrameBaker, _ manager: CanvasManager) -> [Int] {
        (0..<manager.contentEndFrame).filter { baker.bakeQueue.isPending($0) }
    }

    /// Spins the main run loop until `condition` holds — the armed tick and settle are timers.
    private func waitUntil(_ what: String, timeout: TimeInterval = 3, file: StaticString = #filePath,
                           line: UInt = #line, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), "Timed out waiting for: \(what)", file: file, line: line)
    }

    /// **A frame written to a layer nobody can see changes no picture, and it used to cost the most
    /// expensive thing the stream does.** The owner, 2026-10-10: *"weird lagspikes randomly where I
    /// can see the first 16 or so frames turn orange momentarily, with 0 input."* The stream sat on a
    /// hidden layer; the laptop's screen kept changing; and every pause in that motion settled the
    /// frame onto the cel (`commitStreamFrames`), which the dirty sweep read as an edit to the cel's
    /// whole span. So a hidden layer is not written at all — by its own switch or a folder above it —
    /// and keeps the picture it had.
    func testAHiddenStreamLayerIsNotWritten() throws {
        for viaFolder in [false, true] {
            let fixture = tickFixture(image: solidImage(.green))
            fixture.manager.streamCoordinator.tick()
            XCTAssertTrue(centreIs(.green, fixture.vector), "Setup: green on screen")
            let index = try XCTUnwrap(fixture.manager.layers.indices.last)
            hide(index, in: fixture.manager, viaFolder: viaFolder)
            fixture.slot(2, solidImage(.red))
            let version = fixture.vector.version

            fixture.manager.streamCoordinator.tick()

            XCTAssertEqual(fixture.vector.version, version,
                           "a layer nobody can see is not repainted (viaFolder: \(viaFolder))")
            XCTAssertTrue(centreIs(.green, fixture.vector), "and keeps the picture it had")
            XCTAssertEqual(fixture.presents(), 1, "and presents nothing: only the visible tick did")
        }
    }

    /// **The settle of a hidden layer commits nothing and dirties no frame** — the owner's symptom at
    /// the model: a frame the sweep marks pending is a frame the timeline's bake bar draws orange.
    /// Driven through the real `FrameBaker.syncDirty`, with a visible layer as the control that the
    /// sweep does see a commit, so the hidden case's empty answer is not the sweep being blind.
    func testAHiddenStreamLayersSettleDirtiesNoFrame() throws {
        for viaFolder in [false, true] {
            let fixture = tickFixture(image: solidImage(.green))
            let manager = fixture.manager
            let baker = makeBaker(manager)
            let index = try XCTUnwrap(manager.layers.indices.last)

            manager.streamCoordinator.tick()
            XCTAssertTrue(fixture.vector.holdsUncommittedStreamFrame, "Setup: a frame the bake lacks")
            hide(index, in: manager, viaFolder: viaFolder)
            // Baked in the hidden state, so the hiding itself — a structural edit — is absorbed before
            // the settle is judged.
            bakeEverything(baker)
            XCTAssertEqual(pending(baker, manager), [], "Setup: every frame baked")
            fixture.slot(2, solidImage(.red))
            manager.streamCoordinator.tick()
            let committed = fixture.vector.committedVersion
            var published = 0
            let sink = manager.objectWillChange.sink { published += 1 }

            manager.streamCoordinator.settle()
            baker.syncDirty()

            XCTAssertEqual(fixture.vector.committedVersion, committed, "nothing was committed (viaFolder: \(viaFolder))")
            XCTAssertEqual(published, 0, "and nothing was published: no SwiftUI pass, no thumbnail")
            XCTAssertEqual(pending(baker, manager), [], "so no frame is unbaked")
            sink.cancel()
        }

        let control = tickFixture(image: solidImage(.green))
        let baker = makeBaker(control.manager)
        control.manager.streamCoordinator.tick()
        bakeEverything(baker)
        XCTAssertEqual(pending(baker, control.manager), [], "Setup: every frame baked")
        control.manager.streamCoordinator.settle()
        baker.syncDirty()
        XCTAssertEqual(pending(baker, control.manager), Array(0..<control.manager.contentEndFrame),
                       "CONTROL: a visible stream's settle dirties the cel's whole span, as it must")
    }

    /// **Showing the layer again is the edge that feeds it** — the newest picture reaches it, and the
    /// settle puts that picture into the bake, with no frame arriving from the laptop to carry either.
    /// This is TODO (96)'s *"same with hidden streams made visible"*, kept: the layer is written when
    /// it is shown instead of thirty times a second while it is not.
    func testShowingAHiddenStreamLayerFeedsItTheNewestPictureAndSettlesIt() throws {
        for viaFolder in [false, true] {
            let fixture = tickFixture(image: solidImage(.green))
            let coordinator = fixture.manager.streamCoordinator
            coordinator.settleInterval = 0.05
            coordinator.tick()
            let index = try XCTUnwrap(fixture.manager.layers.indices.last)
            hide(index, in: fixture.manager, viaFolder: viaFolder)
            coordinator.sync()
            fixture.slot(2, solidImage(.red))
            coordinator.tick()
            XCTAssertTrue(centreIs(.green, fixture.vector), "Setup: the hidden layer did not follow the laptop")
            let committed = fixture.vector.committedVersion

            show(index, in: fixture.manager)
            coordinator.sync()

            waitUntil("the pass that shows the layer wrote the newest picture") { centreIs(.red, fixture.vector) }
            waitUntil("and its settle put that picture into the bake") {
                fixture.vector.committedVersion > committed
            }
            XCTAssertFalse(fixture.vector.holdsUncommittedStreamFrame)
        }
    }

    /// **While no stream layer is fed the decoder stops waking the main thread** — a moving screen
    /// sends thirty frames a second, each a main-queue hop and a coalesced tick, to a canvas that can
    /// draw none of them. MEASURED 2026-10-10 in the simulator (Debug) against a hidden stream on a
    /// moving source: 1,492 main run-loop wake-ups in 22 s before this change, 97 after — the 97 are
    /// the recorder's own flush.
    func testTheDecoderStopsAnnouncingFramesWhileNoStreamLayerIsFed() throws {
        let fixture = tickFixture(image: solidImage(.green))
        let coordinator = fixture.manager.streamCoordinator
        let index = try XCTUnwrap(fixture.manager.layers.indices.last)
        coordinator.sync()
        let decoder = try XCTUnwrap(coordinator.client(for: StreamEndpoint(host: "laptop", port: 47301))).decoder
        XCTAssertTrue(decoder.announcesFrames, "a visible stream layer wants every frame")

        fixture.manager.layers[index].isVisible = false
        coordinator.sync()
        XCTAssertFalse(decoder.announcesFrames, "hidden")

        fixture.manager.layers[index].isVisible = true
        coordinator.sync()
        XCTAssertTrue(decoder.announcesFrames, "shown again")

        fixture.manager.play()
        coordinator.sync()
        XCTAssertFalse(decoder.announcesFrames, "playing: the bake is what plays")
        fixture.manager.stopPlayback()
        coordinator.sync()
        XCTAssertTrue(decoder.announcesFrames, "and it listens again when playback stops")
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
