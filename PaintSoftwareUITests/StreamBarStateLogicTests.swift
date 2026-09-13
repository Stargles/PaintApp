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

    /// **A connection nothing names yet is not paused.** Between the sheet's connect and its insert
    /// no element names the endpoint, and "no elements" is not "every element frozen" — the
    /// stage-2 drive caught a `pause`/`resume` pair four milliseconds apart on every connect,
    /// each a pipeline restart on the laptop. Here the element is undone rather than not yet
    /// inserted; the client is the same client either way.
    func testAConnectionNoElementNamesIsNotPaused() throws {
        let (manager, _) = streaming()
        let coordinator = manager.streamCoordinator
        manager.undo()   // the insert: the element is gone, the client object is not
        XCTAssertTrue(coordinator.referencedEndpoints.isEmpty, "Setup: nothing names the endpoint")
        XCTAssertTrue(coordinator.activeEndpoints.contains(Self.endpoint), "Setup: the client is still there")

        coordinator.stateChanged(.connected, at: Self.endpoint)
        coordinator.statusArrived(status(), from: Self.endpoint)

        XCTAssertTrue(coordinator.sentControlCommands.isEmpty,
                      "nothing to freeze, nothing to pause: \(coordinator.sentControlCommands.map(\.command))")
        manager.redo()
        XCTAssertTrue(coordinator.sentControlCommands.isEmpty, "and the element coming back needs no resume")
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
}
