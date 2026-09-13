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
        XCTAssertTrue(manager.layers[layerIndex].cels[0].vector!.setStreamFrame(id: element.id, image: image))
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

        coordinator.stateChanged(.reconnecting(lastFailure: "The computer stopped answering."), at: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: live), .reconnecting, "the connection beats the stale STATUS")
        XCTAssertEqual(StreamBarState.reconnecting.word, "Reconnecting…")

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
        XCTAssertTrue(vector.setStreamFrame(id: element.id, image: image))
        coordinator.stateChanged(.connected, at: Self.endpoint)
        coordinator.statusArrived(status(), from: Self.endpoint)
        let version = vector.version

        coordinator.stateChanged(.reconnecting(lastFailure: "The connection was dropped."), at: Self.endpoint)

        XCTAssertTrue(try XCTUnwrap(vector.streams.first).displayFrame === image, "the picture stays")
        XCTAssertEqual(vector.version, version, "and nothing was invalidated")
        XCTAssertEqual(coordinator.barState(for: try XCTUnwrap(vector.streams.first)), .reconnecting)
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
        XCTAssertTrue(coordinator.sentControlCommands.isEmpty, "Setup: nothing sent yet")

        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.pause], "the only element frozen: pause")

        // The laptop answers a pause with STATUS streaming:false; the bar says Frozen regardless.
        coordinator.statusArrived(status(streaming: false, reason: "Paused by client"), from: Self.endpoint)
        XCTAssertEqual(coordinator.barState(for: try XCTUnwrap(manager.activeStreamCel?.element)), .frozen)

        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, false))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.pause, .resume],
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
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.pause, .resume],
                       "one of two frozen: the laptop keeps sending for the other")
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: secondLayer, celIndex: 0, elementID: second.id, false))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command), [.pause, .resume, .keyframe])

        // Both frozen: pause. Then the connection drops and comes back — the pause is re-sent,
        // because the laptop the client reconnected to knows nothing of the old one.
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: layerIndex, celIndex: 0, elementID: element.id, true))
        XCTAssertTrue(manager.setStreamFrozen(layerIndex: secondLayer, celIndex: 0, elementID: second.id, true))
        XCTAssertEqual(coordinator.sentControlCommands.map(\.command).last, .pause)
        let count = coordinator.sentControlCommands.count
        coordinator.stateChanged(.reconnecting(lastFailure: "dropped"), at: Self.endpoint)
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

    // MARK: - The sandwich note

    /// The bar's note about the held picture is up exactly when the canvas at rest is the baked
    /// composite: a blend mode, a mask, an effect or a transformation layer anywhere in the
    /// document, and not for a plain stack or a dimmed layer.
    func testTheSandwichNoteFollowsWhatPutsTheCanvasOnTheComposite() throws {
        let (manager, _) = streaming()
        let layerIndex = manager.currentLayerIndex
        XCTAssertFalse(manager.streamPictureIsHeldByTheSandwich, "a flat stack: the live picture shows")

        manager.layers[layerIndex].opacity = 0.4
        XCTAssertFalse(manager.streamPictureIsHeldByTheSandwich, "a dimmed reference stays on the flat row")

        manager.layers[layerIndex].blendMode = .multiply
        XCTAssertTrue(manager.streamPictureIsHeldByTheSandwich, "a multiplied reference is on the composite")
        manager.layers[layerIndex].blendMode = .normal
        XCTAssertFalse(manager.streamPictureIsHeldByTheSandwich)

        // Another layer's blend mode engages the whole canvas, the stream layer included.
        manager.layers[0].blendMode = .screen
        XCTAssertTrue(manager.streamPictureIsHeldByTheSandwich, "any layer's blend mode holds it")
        manager.layers[0].blendMode = .normal
        XCTAssertFalse(manager.streamPictureIsHeldByTheSandwich)

        XCTAssertFalse(StreamBarState.sandwichNote.isEmpty)
        XCTAssertTrue(StreamBarState.sandwichNote.hasPrefix("Live picture pauses"), StreamBarState.sandwichNote)
    }

    /// **What the note says is true of the pixels on screen, and the pixels are what this asserts.**
    /// At rest on an engaged sandwich the canvas shows the baked frame (`FrameBaker.image(atFrame:)`,
    /// keyed on `FrameBakeKey`, which reads `committedVersion`). With the stream layer on Multiply:
    /// the bake of frame 0 is green; a red frame ticks in; the key has not moved, the baker has
    /// nothing to do, and the rest picture is **still green** — the staleness the note names. Then
    /// an ordinary edit moves the key and the next bake is red. Two operands each way, through the
    /// real baker; a version-number assertion could not tell "the key stood still" from "nobody
    /// looked".
    func testTheRestPictureOnAnEngagedSandwichHoldsWhileTheStreamMovesOnUntilAnEdit() throws {
        let (manager, element) = streaming()
        let layerIndex = manager.currentLayerIndex
        manager.layers[layerIndex].blendMode = .multiply
        XCTAssertTrue(manager.streamPictureIsHeldByTheSandwich, "Setup: the note is up")
        let vector = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        // The stream's own picture size is 1920×1080 here; frames of that size keep the fit exact.
        func frame(_ color: UIColor) -> UIImage {
            CanvasFixture.solidImage(color, rect: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     size: CGSize(width: 1920, height: 1080))
        }
        let coordinator = manager.streamCoordinator
        coordinator.onLayerNeedsRepaint = { _ in }
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
        let restBefore = try XCTUnwrap(baker.image(atFrame: 0), "the baker has frame 0")
        let centre = pixel(restBefore, 32, 32)
        XCTAssertGreaterThan(Int(centre.g), Int(centre.r) + 100, "the rest picture is the green frame (over white paper, multiplied)")

        // The stream moves on to red. The key stands still and so does the picture on screen.
        slot = (2, frame(.red))
        coordinator.tick()
        XCTAssertGreaterThan(Int(pixel(try XCTUnwrap(vector.render().cgImage), 32, 32).r), 100,
                             "Setup: the cel's own render is red now — the flat row would show it")
        manager.syncFrameBake(suspended: false)
        drain(baker)
        XCTAssertEqual(baker.currentKey(atFrame: 0), keyBefore, "a tick moves no bake key")
        let restAfterTick = pixel(try XCTUnwrap(baker.image(atFrame: 0)), 32, 32)
        XCTAssertGreaterThan(Int(restAfterTick.g), Int(restAfterTick.r) + 100,
                             "the rest picture is still green: that is what the note tells the artist")

        // An ordinary edit re-keys the frame, and the next rest picture is the red one.
        vector.setStreamFrame(id: element.id, image: frame(.red))
        vector.bumpVersion()
        manager.celContentChangedOutsideStroke(layerID: manager.layers[layerIndex].id,
                                               celID: manager.layers[layerIndex].cels[0].id)
        baker.noteDocumentChanged()
        manager.syncFrameBake(suspended: false)
        drain(baker)
        XCTAssertNotEqual(baker.currentKey(atFrame: 0), keyBefore, "an edit moves the key")
        let restAfterEdit = pixel(try XCTUnwrap(baker.image(atFrame: 0)), 32, 32)
        XCTAssertGreaterThan(Int(restAfterEdit.r), Int(restAfterEdit.g) + 100, "and the rest picture follows it")
    }
}
