import XCTest
import UIKit

/// Pure-logic tests for **what the stream bar shows and when** — STREAM.md §5.4, §5.6 and §5.7 —
/// with no socket and no SwiftUI: `CanvasManager.activeStreamCel` is the bar's whole reason to be
/// on screen, `ScreenStreamCoordinator.barState(for:)` is its word, and `sentControlCommands` is
/// the `pause` / `resume` / `keyframe` the Freeze toggle sends the laptop.
///
/// **The bar is shown by state, not by a panel case**, and the first test here is the cold-start
/// reachability one CLAUDE.md asks for: from a new document with no prior state, can an artist
/// reach the bar? The answer has to be "insert a stream and commit the box" and nothing else.
@MainActor
final class StreamBarStateLogicTests: XCTestCase {

    private static let endpoint = StreamEndpoint(host: "laptop", port: 47301)

    private var caches: URL!
    private var storedResolution: String?

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        caches = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamBarStateLogicTests-" + UUID().uuidString, isDirectory: true)
        FrameBakeStore.cachesDirectoryOverride = caches
        // Pinned and restored, `BakeWiringLogicTests`' reason: the knob writes through to
        // `UserDefaults`, and the baked frame below is sized by it.
        storedResolution = UserDefaults.standard.string(forKey: CanvasManager.renderResolutionDefaultsKey)
        UserDefaults.standard.set(RenderResolution.full.rawValue, forKey: CanvasManager.renderResolutionDefaultsKey)
    }

    override func tearDown() {
        if let storedResolution {
            UserDefaults.standard.set(storedResolution, forKey: CanvasManager.renderResolutionDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        }
        FrameBakeStore.cachesDirectoryOverride = nil
        try? FileManager.default.removeItem(at: caches)
        Compositor.backend = Compositor.defaultBackend
        super.tearDown()
    }

    /// Runs the baker to a stop — `BakeWiringLogicTests.drain`.
    private func drain(_ baker: FrameBaker, timeout: TimeInterval = 60) {
        var settled = false
        let idle = expectation(description: "the baker drains and the loop stops")
        baker.onIdle = {
            guard !settled else { return }
            settled = true
            idle.fulfill()
        }
        baker.kick()
        wait(for: [idle], timeout: timeout)
        baker.onIdle = nil
    }

    /// RGBA at a canvas point of a baked frame.
    private func pixel(_ cg: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    private func status(streaming: Bool = true, reason: String? = nil, name: String = "Blender") -> StreamStatus {
        StreamStatus(source: StreamStatus.Source(kind: "window", name: name),
                     width: 1920, height: 1080, fps: 30, streaming: streaming, reason: reason)
    }

    /// A manager standing on frame 0 with one committed stream layer active.
    private func streaming() -> (manager: CanvasManager, element: VectorStreamElement) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 0
        let element = manager.insertStream(host: Self.endpoint.host, port: Self.endpoint.port, status: status())!
        manager.commitVectorFloatIfNeeded()
        return (manager, element)
    }

    // MARK: - When the bar is up (STREAM.md §5.7)

    /// **Cold start: no bar on a fresh document, a bar once a stream is inserted and committed.**
    /// The Move box holds the element straight after the insert, and `DrawingView` gives the Move
    /// bar precedence then — but the *state* is already answerable, which is what this pins.
    func testTheBarIsReachableFromANewDocumentByInsertingAStream() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertNil(manager.activeStreamCel, "a raster layer shows no stream bar")
        manager.addVectorLayer()
        XCTAssertNil(manager.activeStreamCel, "an empty vector layer shows no stream bar")

        let element = try XCTUnwrap(manager.insertStream(host: "laptop", port: 47301, status: status()))
        XCTAssertTrue(manager.isAnyPieceFloating, "the insert lifts the element into the Move box")
        let active = try XCTUnwrap(manager.activeStreamCel, "the state answers as soon as the layer exists")
        XCTAssertEqual(active.element.id, element.id)
        XCTAssertEqual(active.layerIndex, manager.currentLayerIndex)

        manager.commitVectorFloatIfNeeded()
        XCTAssertFalse(manager.isAnyPieceFloating)
        XCTAssertEqual(manager.activeStreamCel?.element.id, element.id, "and after the commit the bar is what shows")
    }

    /// The bar follows the playhead and the active layer: off the cel's span, or on another layer,
    /// there is no bar.
    func testTheBarFollowsThePlayheadAndTheActiveLayer() throws {
        let (manager, element) = streaming()
        let layerIndex = manager.currentLayerIndex
        XCTAssertEqual(manager.activeStreamCel?.element.id, element.id)

        manager.currentFrame = 20   // past the cel's [0, 12)
        XCTAssertNil(manager.activeStreamCel, "no cel at the playhead, no bar")
        manager.currentFrame = 5
        XCTAssertEqual(manager.activeStreamCel?.element.id, element.id, "back inside the span")

        manager.currentLayerIndex = 0   // the fixture's raster layer
        XCTAssertNil(manager.activeStreamCel, "another layer, no bar")
        manager.currentLayerIndex = layerIndex
        XCTAssertNotNil(manager.activeStreamCel)
    }

    /// After a bake the bar is up on the stream cels either side and down on the baked one.
    func testAfterABakeTheBarIsDownOnTheBakedFrameAndUpEitherSide() throws {
        let (manager, element) = streaming()
        let layerIndex = manager.currentLayerIndex
        manager.layers[layerIndex].cels[0].frameCount = 4
        let image = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 4),
                                             size: CGSize(width: 8, height: 4))
        XCTAssertTrue(manager.layers[layerIndex].cels[0].vector!.setStreamFrame(id: element.id, image: image, index: 1))
        XCTAssertEqual(manager.bakeStreamFrame(layerIndex: layerIndex, celIndex: 0, atFrame: 1), .baked)

        manager.currentFrame = 0
        XCTAssertNotNil(manager.activeStreamCel, "[1] holds the stream")
        manager.currentFrame = 1
        XCTAssertNil(manager.activeStreamCel, "[2] holds an image now — no bar")
        manager.currentFrame = 2
        XCTAssertNotNil(manager.activeStreamCel, "[3–4] holds the stream")
    }

    // MARK: - The word (STREAM.md §5.6)

    /// Every word, in precedence order: Frozen beats the connection, the connection beats STATUS.
    func testTheStateWordFollowsTheConnectionThenTheStatusAndFrozenWinsOverBoth() throws {
        let (manager, element) = streaming()
        let coordinator = manager.streamCoordinator
        let live = try XCTUnwrap(manager.activeStreamCel?.element)

        // Nothing heard yet: the fixture never starts a client, so there is no transition at all.
        XCTAssertEqual(coordinator.barState(for: live), .connecting)
        XCTAssertEqual(StreamBarState.connecting.word, "Connecting…")

        coordinator.stateChanged(.connecting, at: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: live), .connecting)

        coordinator.stateChanged(.connected, at: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: live), .connecting, "HELLO alone is not a picture; STATUS is")

        coordinator.statusArrived(status(), from: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: live), .live)
        XCTAssertEqual(StreamBarState.live.word, "Live")

        coordinator.statusArrived(status(streaming: false, reason: "The window was closed"), from: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: live), .notStreaming(reason: "The window was closed"))
        XCTAssertEqual(coordinator.barState(for: live).word, "Not streaming — The window was closed")

        coordinator.statusArrived(status(streaming: false), from: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: live).word, "Not streaming — no source is picked",
                       "a STATUS with no reason still gets a sentence")

        coordinator.stateChanged(.reconnecting(lastFailure: .other("The computer stopped answering.")), at: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: live), .reconnecting(detail: "The computer stopped answering."),
                       "the connection beats the stale STATUS")
        XCTAssertEqual(StreamBarState.reconnecting(detail: "The computer stopped answering.").word,
                       "Reconnecting… The computer stopped answering.")

        // Frozen wins over everything.
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: manager.currentLayerIndex, celIndex: 0,
                                              elementID: element.id, true))
        let frozen = try XCTUnwrap(manager.activeStreamCel?.element)
        XCTAssertTrue(frozen.isFrozen)
        XCTAssertEqual(coordinator.barState(for: frozen), .frozen)
        XCTAssertEqual(StreamBarState.frozen.word, "Frozen")
        coordinator.stateChanged(.connected, at: Self.endpoint)
        coordinator.statusArrived(status(), from: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: frozen), .frozen, "still frozen while live")
    }

    /// A disconnect leaves the picture exactly where it was — §2.8's "keeps showing the last
    /// picture" — and only the word changes.
    func testADisconnectLeavesTheLastPictureOnTheElement() throws {
        let (manager, element) = streaming()
        let coordinator = manager.streamCoordinator
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        let image = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 4),
                                             size: CGSize(width: 8, height: 4))
        XCTAssertTrue(vector.setStreamFrame(id: element.id, image: image, index: 1))
        coordinator.stateChanged(.connected, at: Self.endpoint)
        coordinator.statusArrived(status(), from: Self.endpoint)
        let version = vector.version

        coordinator.stateChanged(.reconnecting(lastFailure: .other("The connection was dropped.")), at: Self.endpoint)

        XCTAssertTrue(try XCTUnwrap(vector.streams.first).displayFrame === image, "the picture stays")
        XCTAssertEqual(vector.version, version, "and nothing was invalidated")
        XCTAssertEqual(coordinator.barState(for: try XCTUnwrap(vector.streams.first)),
                       .reconnecting(detail: "The connection was dropped."))
    }

    // MARK: - Freeze and the laptop (STREAM.md §5.4)

    /// **Every element on a connection frozen → `pause`; the first unfreeze → `resume`**, and an
    /// unfreeze on a connection that was not paused asks for a keyframe instead.
    func testFreezingEveryElementPausesTheLaptopAndTheFirstUnfreezeResumesIt() throws {
        let (manager, element) = streaming()
        let coordinator = manager.streamCoordinator
        let layerIndex = manager.currentLayerIndex
        coordinator.stateChanged(.connected, at: Self.endpoint)
        coordinator.statusArrived(status(), from: Self.endpoint)
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume],
                       "Setup: a connection's first reconcile states the wish — an element wants pictures")

        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume, .pause],
                       "the only element frozen: pause")

        // The laptop answers a pause with STATUS streaming:false; the bar says Frozen regardless.
        coordinator.statusArrived(status(streaming: false, reason: "Paused by client"), from: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: try XCTUnwrap(manager.activeStreamCel?.element)), .frozen)

        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, false))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume, .pause, .resume],
                       "the first unfreeze resumes, and asks for no second keyframe — resume carries one")
        XCTAssertEqual(coordinator.barState(for: try XCTUnwrap(manager.activeStreamCel?.element)), .live,
                       "the lifted pause is not reported as Not streaming while the laptop's STATUS is in flight")

        // A second stream layer on the same laptop: freezing one of two pauses nothing, and
        // unfreezing it asks for a keyframe rather than a resume.
        manager.currentFrame = 0
        let second = try XCTUnwrap(manager.insertStream(host: Self.endpoint.host, port: Self.endpoint.port,
                                                        status: status(name: "Screen 2")))
        manager.commitVectorFloatIfNeeded()
        let secondLayer = manager.currentLayerIndex
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: secondLayer, celIndex: 0, elementID: second.id, true))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume, .pause, .resume],
                       "one of two frozen: the laptop keeps sending for the other")
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: secondLayer, celIndex: 0, elementID: second.id, false))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume, .pause, .resume, .keyframe])

        // Both frozen: pause. Then the connection drops and comes back — the pause is re-sent,
        // because the laptop the client reconnected to knows nothing of the old one.
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: secondLayer, celIndex: 0, elementID: second.id, true))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command).last, .pause)
        let count = coordinator.sentControlCommands.count
        coordinator.stateChanged(.reconnecting(lastFailure: .other("dropped")), at: Self.endpoint)
        coordinator.stateChanged(.connected, at: Self.endpoint)
        XCTAssertEqual(coordinator.sentControlCommands.count, count + 1)
        XCTAssertEqual(coordinator.sentControlCommands.last?.command, .pause, "re-sent on reconnect")
    }

    /// **The sheet's own connect-to-insert window still does not flap.** Between `connect(to:)`
    /// being called and the element it is about to insert landing, nothing names the endpoint yet —
    /// the stage-2 drive caught a `pause`/`resume` pair four milliseconds apart on every connect,
    /// each a pipeline restart on the laptop. `pendingConnects` is exactly that window, and
    /// `connect(to:)` is the only thing that populates it, so a client `sync()`/`insertStream` made
    /// is never in it. `b07984d`'s fix for this stays; only its blast radius narrows in stage 4 —
    /// see `testAConnectionNoElementNamesIsNowPaused` below for what changed.
    func testAConnectionStillBeingConnectedIsNotPausedMidConnect() async throws {
        let manager = CanvasFixture.manager(layerCount: 1)   // startsClients == false: no real socket
        let coordinator = manager.streamCoordinator
        let task = Task { try await coordinator.connect(to: Self.endpoint) }
        // **`Task { }` only schedules its body — it runs none of it inline with this call**, unlike
        // a synchronous closure. `connect(to:)`'s own continuation registers only once that body
        // actually gets a turn on the main actor, so yield until it has: `client(for:)` becomes
        // non-nil as part of the same synchronous burst that registers `pendingConnects` (both run
        // before `withCheckedThrowingContinuation` suspends), so its arrival is the signal that the
        // window this test is about has opened. Skipping this and calling `statusArrived` right
        // away resolves nothing (`connect`'s continuation is not registered yet) and then hangs
        // forever at `task.value`, because `connect`'s continuation registers *after* — the shape
        // that cost a stuck simulator run once already.
        var yields = 0
        while coordinator.client(for: Self.endpoint) == nil {
            await Task.yield()
            yields += 1
            if yields > 10_000 {
                XCTFail("connect(to:) never registered its client")
                return
            }
        }
        XCTAssertTrue(coordinator.referencedEndpoints.isEmpty, "Setup: no element names it yet")

        coordinator.stateChanged(.connected, at: Self.endpoint)
        XCTAssertTrue(coordinator.sentControlCommands.isEmpty,
                      "about to be claimed by the sheet's own insert: no pause, or the stage-2 flap is back")

        coordinator.statusArrived(status(), from: Self.endpoint)
        _ = try await task.value
        XCTAssertTrue(coordinator.sentControlCommands.isEmpty, "resolving the connect is not an insert either")
    }

    /// **STREAM.md §6, stage 4: a connection nothing names any more is paused, not left alone.**
    /// This is the rule `b07984d` (stage 2) did not need and stage 4 adds — read that commit's
    /// message and this file's old test (now split in two) before changing it again. The document's
    /// *ambient* connection (`documentEndpointOverride`, standing in for `sync()`'s real
    /// `StreamEndpoint.lastUsed()` read) can sit connected with no stream element for the rest of a
    /// session, and it must read as paused so the laptop is not encoding for a canvas nobody is
    /// showing — pausing costs nothing else, since FILE_* still flows on a paused connection.
    func testAConnectionNoElementNamesIsNowPaused() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let coordinator = manager.streamCoordinator
        coordinator.documentEndpointOverride = Self.endpoint
        coordinator.sync()
        XCTAssertTrue(coordinator.activeEndpoints.contains(Self.endpoint), "Setup: sync() made the client")
        XCTAssertTrue(coordinator.referencedEndpoints.isEmpty, "Setup: no element names it")

        coordinator.stateChanged(.connected, at: Self.endpoint)
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.pause],
                       "nothing needs pictures from it: paused")

        // Adding a stream element on that same endpoint: resume.
        manager.currentFrame = 0
        let element = try XCTUnwrap(manager.insertStream(host: Self.endpoint.host, port: Self.endpoint.port,
                                                          status: status()))
        manager.commitVectorFloatIfNeeded()
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.pause, .resume],
                       "an element now wants pictures from it")

        // Removing it again: pause, once more.
        let layerIndex = manager.currentLayerIndex
        manager.deleteLayer(at: layerIndex)
        coordinator.sync()
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.pause, .resume, .pause],
                       "nothing names it again: paused again — \(element.id)")
    }

    // MARK: - A connection states its wish (TODO (112))

    /// **The first reconcile on every connection says what this end wants, either way** — the
    /// laptop's pause can outlive the connection that asked for it (an iPad locked in the background,
    /// a Wi-Fi drop: the socket dies and the laptop never hears a `resume`), and a new connection
    /// cannot see that. An iPad that assumed the laptop started unpaused left the stream on "Paused"
    /// until something happened to re-state the wish.
    func testEveryConnectionStatesItsWishSoAStalePauseOnTheLaptopCannotOutliveTheConnection() throws {
        let (manager, _) = streaming()
        let coordinator = manager.streamCoordinator
        coordinator.stateChanged(.connected, at: Self.endpoint)
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume],
                       "an element wants pictures: the first connect resumes, whatever state the laptop is in")

        // The app is backgrounded (pause), the socket dies while it sleeps, the iPad wakes and
        // reconnects. The laptop may still hold the pause; this end says resume.
        coordinator.stateChanged(.reconnecting(lastFailure: .other("dropped")), at: Self.endpoint)
        coordinator.stateChanged(.connected, at: Self.endpoint)
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume, .resume],
                       "a new connection resumes again, because nothing asked on the old one reached it")
    }

    /// **A wish this end could not deliver is not a wish it has asked.** `ScreenStreamClient.send` drops
    /// a command with no live connection, so a pause noted down while the socket was reconnecting
    /// stood in for one the laptop never heard — and the next connection, finding its wish already
    /// "asked", said nothing to a laptop that still held an older pause. MEASURED in
    /// `StreamLiveUITests.testALaptopThatStillHoldsAnOldPauseIsToldToResumeOnTheNewConnection`.
    func testAWishMadeWhileTheConnectionIsDownIsStatedWhenItComesBack() throws {
        let (manager, element) = streaming()
        let coordinator = manager.streamCoordinator
        let layerIndex = manager.currentLayerIndex
        coordinator.stateChanged(.connected, at: Self.endpoint)
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume])

        coordinator.stateChanged(.reconnecting(lastFailure: .other("dropped")), at: Self.endpoint)
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        coordinator.sync()
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume],
                       "nothing is said, and nothing is recorded as said, to a laptop this end is not connected to")

        coordinator.stateChanged(.connected, at: Self.endpoint)
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.resume, .pause],
                       "the wish made while the socket was down is stated the moment there is one")
    }

    // MARK: - The tick after it stood down (TODO (112))

    /// **The tick is armed by a frame's arrival alone, so the end of playback arms one.** Frames that
    /// land while the animation plays are held in the decoder's slot with no tick to carry them; a
    /// laptop whose screen then sits still sends no further frame, and the canvas would keep a picture
    /// the computer no longer shows until its screen next changed.
    func testTheTickIsArmedWhenPlaybackStopsSoAFrameThatLandedMeanwhileIsShown() throws {
        let (manager, _) = streaming()
        let coordinator = manager.streamCoordinator
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        let frame = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 4),
                                             size: CGSize(width: 8, height: 4))
        coordinator.frameSourceOverride = { endpoint in
            endpoint == Self.endpoint ? (1, frame.cgImage!) : nil
        }
        manager.play()
        defer { manager.stopPlayback() }
        XCTAssertTrue(manager.isPlaying, "Setup")
        coordinator.sync()   // a canvas pass while playing: the tick stands down
        coordinator.tick()
        XCTAssertNil(try XCTUnwrap(vector.streams.first).displayFrame, "Setup: nothing is written while playing")

        manager.stopPlayback()
        coordinator.sync()   // the pass playback's stop raises

        let shown = expectation(description: "the armed tick writes the frame that landed while playing")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            if vector.streams.first?.displayFrame != nil { shown.fulfill() }
        }
        wait(for: [shown], timeout: 2)
        poll.invalidate()
    }

    // MARK: - What the bar says about the picture

    /// The note is up exactly when the canvas is not the computer's whole picture: the compositor
    /// draws it (a blend mode, a mask, an effect, a transformation layer anywhere in the document —
    /// the stream is drawn live but plain), or a pose moves the stream (it holds). A plain stack and
    /// a dimmed layer have nothing to add; a frozen stream is exact and says nothing.
    func testThePictureNoteSaysWhyTheCanvasIsNotTheComputersWholePicture() throws {
        let (manager, element) = streaming()
        let layerIndex = manager.currentLayerIndex
        XCTAssertNil(manager.activeStreamPictureNote, "a flat stack: the canvas is the computer's picture")

        manager.layers[layerIndex].opacity = 0.4
        XCTAssertNil(manager.activeStreamPictureNote, "a dimmed reference stays on the flat row")

        manager.layers[layerIndex].blendMode = .multiply
        XCTAssertEqual(manager.activeStreamPictureNote, .drawnPlain, "a multiplied reference is on the composite")
        manager.layers[layerIndex].blendMode = .normal
        XCTAssertNil(manager.activeStreamPictureNote)

        // Another layer's blend mode engages the whole canvas, the stream layer included.
        manager.layers[0].blendMode = .screen
        XCTAssertEqual(manager.activeStreamPictureNote, .drawnPlain, "any layer's blend mode puts the canvas on the composite")

        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        XCTAssertNil(manager.activeStreamPictureNote, "a frozen stream is the exact picture")
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, false))
        XCTAssertEqual(manager.activeStreamPictureNote, .drawnPlain)
        manager.layers[0].blendMode = .normal

        // A transformation layer that moves the stream: its picture holds.
        manager.addTransformLayer()
        let size = CanvasFixture.canvasSize
        let box = CGRect(origin: .zero, size: size)
        let moving = PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 8, y: 0))
        manager.layers[manager.layers.count - 1].cels = [Cel(id: UUID(), startFrame: 0, frameCount: 12,
                                                                raster: .empty(size: size))]
        manager.layers[manager.layers.count - 1].transform = LayerPose(
            pose: PoseQuad(restingIn: box),
            track: TransformTrack(keys: [.init(frame: 0, pose: PoseQuad(restingIn: box)),
                                         .init(frame: 11, pose: moving)]))
        manager.currentLayerIndex = layerIndex
        manager.currentFrame = 6    // mid-move: the walk poses the stream's cel here, and not at the key's rest
        XCTAssertEqual(manager.activeStreamPictureNote, .heldByAPose, "a moved stream cannot be drawn live")
        XCTAssertEqual(manager.liveStreamLayerIndices(), [], "and it joins no live pair")

        XCTAssertFalse(StreamPictureNote.drawnPlain.sentence.isEmpty)
        XCTAssertNotEqual(StreamPictureNote.drawnPlain.sentence, StreamPictureNote.heldByAPose.sentence)
    }

    /// **Which streams the canvas draws live**: visible, unfrozen, shown at this frame, unposed.
    func testTheLiveStreamsAreTheVisibleUnfrozenUnposedOnes() throws {
        let (manager, element) = streaming()
        let layerIndex = manager.currentLayerIndex
        XCTAssertEqual(manager.liveStreamLayerIndices(), [layerIndex], "a stream on a visible layer")

        manager.layers[layerIndex].isVisible = false
        XCTAssertEqual(manager.liveStreamLayerIndices(), [], "a hidden layer has nothing to draw")
        manager.layers[layerIndex].isVisible = true
        XCTAssertEqual(manager.liveStreamLayerIndices(), [layerIndex], "and shown again it is live with no further word")

        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        XCTAssertEqual(manager.liveStreamLayerIndices(), [], "a frozen stream is the document's picture")
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, false))

        manager.currentFrame = 20   // past the cel's [0, 12)
        XCTAssertEqual(manager.liveStreamLayerIndices(), [], "no cel at the playhead")
        manager.currentFrame = 3
        XCTAssertEqual(manager.liveStreamLayerIndices(), [layerIndex])

        manager.play()
        defer { manager.stopPlayback() }
        XCTAssertEqual(manager.liveStreamLayerIndices(), [], "while the animation plays the bake carries the picture (§2.9)")
    }

    /// **The pair's middle**: the active layer alone until a stream is live, then every leaf from the
    /// lowest of the two to the highest — so a stroke finds its host already drawing, and the stream's
    /// frames find theirs.
    func testTheHostRunIsTheActiveLayerAloneUntilAStreamIsLiveAndThenTheSpanBetween() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentFrame = 0
        _ = manager.insertStream(host: Self.endpoint.host, port: Self.endpoint.port, status: status())
        manager.commitVectorFloatIfNeeded()
        let stream = manager.currentLayerIndex
        manager.addLayer()
        manager.addLayer()
        let top = manager.currentLayerIndex
        func run() -> [Int] { manager.liveHostRun(tree: manager.renderTree(atFrame: 0)) }

        XCTAssertEqual(manager.layers.count, 4)
        manager.currentLayerIndex = top
        XCTAssertEqual(run(), Array(stream ... top), "the stream below the active layer: both and what lies between")
        manager.currentLayerIndex = 0
        XCTAssertEqual(run(), Array(0 ... stream), "the active layer below the stream")
        manager.currentLayerIndex = stream
        XCTAssertEqual(run(), [stream], "the stream is the active layer: the run is that one layer")

        // Not live: the run is what it always was.
        let element = try XCTUnwrap(manager.layers[stream].cels[0].vector?.streams.first)
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: stream, celIndex: 0, elementID: element.id, true))
        manager.currentLayerIndex = top
        XCTAssertEqual(run(), [top], "a frozen stream joins nothing: the active layer alone")
    }

    /// A stream going live, frozen or hidden moves the sandwich's key, so a pair minted for one cut is
    /// never taken for the other's.
    func testTheSandwichKeyFollowsTheLiveStreams() throws {
        let (manager, element) = streaming()
        let layerIndex = manager.currentLayerIndex
        let live = manager.sandwichKey(atFrame: 0, activeLayerIndex: 0)
        XCTAssertEqual(live.liveStreamLayers, [layerIndex])
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        let frozen = manager.sandwichKey(atFrame: 0, activeLayerIndex: 0)
        XCTAssertEqual(frozen.liveStreamLayers, [])
        XCTAssertNotEqual(live, frozen)
    }

    /// **Freeze is exact on a canvas the compositor draws.** A frame arrives on `version` alone, so
    /// the bake of the frame holds whichever picture it was last baked with — a tick moves no key —
    /// and Freeze would show an older picture than the one the artist froze on. It moves
    /// `committedVersion`, so the next bake is the frozen frame. Through the real baker, two operands
    /// each way: the rest picture before the freeze is the old green, after it the red the artist saw.
    func testFreezingOnAnEngagedCanvasBakesTheFrameTheArtistFrozeOn() throws {
        let (manager, element) = streaming()
        let layerIndex = manager.currentLayerIndex
        manager.layers[layerIndex].blendMode = .multiply
        let vector = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        // The stream's own picture size is 1920×1080 here; frames of that size keep the fit exact.
        func frame(_ color: UIColor) -> UIImage {
            CanvasFixture.solidImage(color, rect: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     size: CGSize(width: 1920, height: 1080))
        }
        let coordinator = manager.streamCoordinator
        var slot: (Int, UIImage) = (1, frame(.green))
        coordinator.frameSourceOverride = { endpoint in
            endpoint == Self.endpoint ? (slot.0, slot.1.cgImage!) : nil
        }
        coordinator.tick()
        XCTAssertNotNil(try XCTUnwrap(vector.streams.first).displayFrame, "Setup: green ticked in")

        let baker = manager.frameBaker
        baker.noteDocumentChanged()
        manager.syncFrameBake(suspended: false)
        drain(baker)
        let keyBefore = try XCTUnwrap(baker.currentKey(atFrame: 0))
        let restBefore = pixel(try XCTUnwrap(baker.image(atFrame: 0), "the baker has frame 0"), 32, 32)
        XCTAssertGreaterThan(Int(restBefore.g), Int(restBefore.r) + 100,
                             "the rest picture is the green frame (over white paper, multiplied)")

        // The stream moves on to red. A tick moves no bake key: the baked picture cannot carry a frame.
        slot = (2, frame(.red))
        coordinator.tick()
        XCTAssertGreaterThan(Int(pixel(try XCTUnwrap(vector.render().cgImage), 32, 32).r), 100,
                             "Setup: the cel's own render is red now")
        manager.syncFrameBake(suspended: false)
        drain(baker)
        XCTAssertEqual(baker.currentKey(atFrame: 0), keyBefore, "a tick moves no bake key")
        let restAfterTick = pixel(try XCTUnwrap(baker.image(atFrame: 0)), 32, 32)
        XCTAssertGreaterThan(Int(restAfterTick.g), Int(restAfterTick.r) + 100, "so the bake is still green")

        // Freeze: the frozen frame is the document's now, and the next bake is red.
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        baker.noteDocumentChanged()
        manager.syncFrameBake(suspended: false)
        drain(baker)
        XCTAssertNotEqual(baker.currentKey(atFrame: 0), keyBefore, "freezing re-keys the frame")
        let restAfterFreeze = pixel(try XCTUnwrap(baker.image(atFrame: 0)), 32, 32)
        XCTAssertGreaterThan(Int(restAfterFreeze.r), Int(restAfterFreeze.g) + 100, "and the bake is the frame frozen on")
    }

    // MARK: - The ping-pong fix (STREAM.md §3/§6): one client per laptop

    /// **The reported bug's own shape**: the document's ambient last-used connection and a stream
    /// element name the same physical laptop under two different `StreamEndpoint` spellings — one
    /// the Tailscale IP, the other the MagicDNS name a Nearby row or a typed address gave it. Before
    /// either HELLO lands, that is genuinely two sockets (nothing can tell them apart yet); once
    /// both reveal the same machine id, they must collapse onto one client, or the single-client
    /// server evicts one of them forever.
    func testTwoEndpointsResolvingToOneMachineIdShareOneClient() throws {
        let manager = CanvasFixture.manager(layerCount: 1)   // startsClients == false: no real socket
        let coordinator = manager.streamCoordinator
        let ambient = StreamEndpoint(host: "desktop-cbr0fl6", port: 47301)
        let spelled = StreamEndpoint(host: "100.104.85.111", port: 47301)
        coordinator.documentEndpointOverride = ambient
        coordinator.sync()
        manager.currentFrame = 0
        _ = try XCTUnwrap(manager.insertStream(host: spelled.host, port: spelled.port, status: status()))
        manager.commitVectorFloatIfNeeded()
        coordinator.sync()

        let ambientClient = try XCTUnwrap(coordinator.client(for: ambient))
        let spelledClient = try XCTUnwrap(coordinator.client(for: spelled))
        XCTAssertFalse(ambientClient === spelledClient, "Setup: two sockets — neither HELLO has arrived yet")

        let machineID = "MACHINE-GUID-1"
        func hello() -> StreamFrame {
            StreamFrame(.hello, payload: StreamJSON.encode(
                StreamHello(proto: StreamHello.protocolVersion, app: "PaintStreamer", version: "1.0",
                           name: "desktop-cbr0fl6", machineID: machineID)))
        }
        ambientClient.handle(hello())
        coordinator.stateChanged(.connected, at: ambient)
        XCTAssertFalse(try XCTUnwrap(coordinator.client(for: spelled)) === ambientClient,
                      "Setup: the other spelling has not connected yet — nothing to collapse onto it")

        spelledClient.handle(hello())
        coordinator.stateChanged(.connected, at: spelled)

        let survivor = try XCTUnwrap(coordinator.client(for: spelled))
        XCTAssertTrue(survivor === (try XCTUnwrap(coordinator.client(for: ambient))),
                     "both spellings now share the one client the second HELLO's machine id matched")

        // The shared client's own callback always reports under whichever endpoint it was
        // started for (here, `spelled`) — the *other* spelling's bar must still read it, or it
        // would freeze at whatever it last showed the moment before the fold.
        coordinator.statusArrived(status(), from: spelled)
        let element = try XCTUnwrap(manager.activeStreamCel?.element)
        XCTAssertEqual(element.host, spelled.host, "Setup: the stream element names the spelled endpoint")
        XCTAssertEqual(coordinator.barState(for: element), .live)
    }

    // MARK: - The ping-pong fix: an evicted client does not fight back

    /// The server evicts a client by sending this exact STATUS reason over the wire before
    /// closing the socket (`ProtocolServer.ReplacedByAnotherConnectionReason`). The client must
    /// recognize it as distinct from an ordinary drop: state lands on `.replaced`, never
    /// `.reconnecting` — the only way to know `fail(_:)`, which always arms a retry timer, was
    /// not the path taken.
    func testAReplacedStatusParksTheClientRatherThanReconnecting() {
        let client = ScreenStreamClient(endpoint: StreamEndpoint(host: "laptop", port: 47301),
                                        appVersion: "1.0", deviceName: "iPad")
        client.handle(StreamFrame(.hello, payload: StreamJSON.encode(
            StreamHello(proto: StreamHello.protocolVersion, app: "PaintStreamer", version: "1.0", name: "desktop"))))
        XCTAssertEqual(client.state, .connected, "Setup")

        client.handle(StreamFrame(.status, payload: StreamJSON.encode(
            StreamStatus(source: StreamStatus.Source(kind: "none", name: ""), width: 0, height: 0, fps: 0,
                        streaming: false, reason: ScreenStreamClient.replacedByAnotherConnectionReason))))

        XCTAssertEqual(client.state, .replaced(reason: ScreenStreamClient.replacedByAnotherConnectionReason))
    }

    /// An ordinary STATUS whose `reason` merely happens to mention being replaced (a coincidence,
    /// or a future unrelated wording) must not trip this — matched verbatim, not by pattern.
    func testAnUnrelatedStatusReasonDoesNotParkTheClient() {
        let client = ScreenStreamClient(endpoint: StreamEndpoint(host: "laptop", port: 47301),
                                        appVersion: "1.0", deviceName: "iPad")
        client.handle(StreamFrame(.hello, payload: StreamJSON.encode(
            StreamHello(proto: StreamHello.protocolVersion, app: "PaintStreamer", version: "1.0", name: "desktop"))))

        client.handle(StreamFrame(.status, payload: StreamJSON.encode(
            StreamStatus(source: StreamStatus.Source(kind: "none", name: ""), width: 0, height: 0, fps: 0,
                        streaming: false, reason: "The window was closed"))))

        XCTAssertEqual(client.state, .connected, "an ordinary STATUS never moves the connection state")
    }

    /// The bar reads a replaced connection as "Paused — another connection took the stream,"
    /// never as an ordinary reconnect: the artist did not cause this, and the word must not
    /// suggest the client is about to retry on its own, because it is not (STREAM.md's fix for
    /// "even two real devices never ping-pong").
    func testTheBarReadsAReplacedConnectionAsPausedByOtherNotReconnecting() throws {
        let (manager, element) = streaming()
        let coordinator = manager.streamCoordinator
        coordinator.stateChanged(.connected, at: Self.endpoint)
        coordinator.statusArrived(status(), from: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: element), .live, "Setup")

        coordinator.stateChanged(.replaced(reason: ScreenStreamClient.replacedByAnotherConnectionReason),
                                 at: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: element), .pausedByOther)
        XCTAssertEqual(StreamBarState.pausedByOther.word, "Paused — another connection took the stream")
    }
}
