import AVFoundation
import XCTest
import UIKit

/// Pure-logic tests for STREAM.md §5.8's receive path — laptop → iPad — with **no socket
/// anywhere**. `ScreenStreamClient.handle` is exposed for exactly this (the same shape stage 1
/// gave `H264StreamDecoder.feed`): a hand-built `StreamFrame` goes straight in, the real routing
/// runs (`ScreenStreamCoordinator.routeReceivedFile`, wired by `startClient` on every client —
/// started or not), and the assertions read the document the way the picker's own tests do.
///
/// Every test connects through STREAM.md §6's document-level connection
/// (`documentEndpointOverride` standing in for `StreamEndpoint.lastUsed()`) rather than through a
/// stream element, because a file transfer needs a connection and nothing else — the whole point
/// of §6's new bullet is that the drop box works before any Stream Screen.
@MainActor
final class StreamFileTransferLogicTests: XCTestCase {

    private static let endpoint = StreamEndpoint(host: "laptop", port: 47301)
    private static let levels: [UInt8] = [30, 156]

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stream-file-transfer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Neither store touches the real Application Support directory during this run — the same
        // isolation `VideoImportLogicTests` already gives `VideoImportStore`.
        StreamTransferStore.directoryOverride = directory.appendingPathComponent("incoming", isDirectory: true)
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
    }

    override func tearDownWithError() throws {
        StreamTransferStore.directoryOverride = nil
        VideoImportStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - Setup

    /// A manager with §6's ambient connection to `Self.endpoint` and no stream element — a file
    /// transfer needs a connection and nothing else.
    private func connectedManager(layerCount: Int = 1) -> (manager: CanvasManager, client: ScreenStreamClient) {
        let manager = CanvasFixture.manager(layerCount: layerCount)
        manager.streamCoordinator.documentEndpointOverride = Self.endpoint
        manager.streamCoordinator.sync()
        guard let client = manager.streamCoordinator.client(for: Self.endpoint) else {
            XCTFail("sync() should have made a client for the document endpoint")
            return (manager, ScreenStreamClient(endpoint: Self.endpoint, appVersion: "0", deviceName: "test"))
        }
        return (manager, client)
    }

    private func solidPNGData(_ color: UIColor, size: CGSize = CGSize(width: 8, height: 4)) -> Data {
        let image = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else {
            XCTFail("UIGraphicsImageRenderer must produce PNG data")
            return Data()
        }
        return data
    }

    /// Sends one file through FILE_BEGIN/(CHUNK)*/END and waits for this client's own FILE_RESULT —
    /// `onFileResultSent`, not the wire, since there is no socket to read it off.
    @discardableResult
    private func send(_ bytes: Data, id: Int, name: String, kind: String, declaredSize: Int? = nil,
                      through client: ScreenStreamClient,
                      file: StaticString = #filePath, line: UInt = #line) throws -> StreamFileResult {
        let done = expectation(description: "FILE_RESULT for id \(id)")
        var result: StreamFileResult?
        client.onFileResultSent = { answer in
            guard answer.id == id else { return }
            result = answer
            done.fulfill()
        }
        client.handle(StreamFrame(.fileBegin, payload: StreamJSON.encode(
            StreamFileBegin(id: id, name: name, size: declaredSize ?? bytes.count, kind: kind))))
        if !bytes.isEmpty {
            client.handle(StreamFrame(.fileChunk, payload: StreamFileChunk(id: id, bytes: bytes).encoded))
        }
        client.handle(StreamFrame(.fileEnd, payload: StreamJSON.encode(StreamFileEnd(id: id))))
        wait(for: [done], timeout: 5)
        client.onFileResultSent = nil
        return try XCTUnwrap(result, "no FILE_RESULT for id \(id)", file: file, line: line)
    }

    /// RGBA at a pixel of a `CGImage`.
    private func pixel(_ cg: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let ctx = CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8,
                            bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let i = (y * cg.width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    private func greyClip(level: UInt8, named name: String = "clip.mp4") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try CanvasFixture.writeGreyClip(levels: [level], fps: 6, side: 64, to: url)
        return url
    }

    // MARK: - Image, into the active vector layer

    /// **An image lands exactly where the picker's own `insertImage` would** — the active vector
    /// layer when there is one, which is why this test makes one active first: a fresh insert onto
    /// no vector layer at all is `VideoImportLogicTests`' "own new layer" shape, and the video test
    /// below already covers "always its own layer" for that kind.
    func testAnImageTransferInsertsIntoTheActiveVectorLayerAndAnswersOk() throws {
        let (manager, client) = connectedManager()
        manager.addVectorLayer()
        let activeLayerID = manager.layers[manager.currentLayerIndex].id
        let layerCountBefore = manager.layers.count

        let bytes = solidPNGData(.red)
        let result = try send(bytes, id: 1, name: "ref.png", kind: "image", through: client)

        XCTAssertTrue(result.ok, "expected ok:true, got \(String(describing: result.reason))")
        XCTAssertNil(result.reason)
        XCTAssertEqual(manager.layers.count, layerCountBefore, "joins the existing vector layer")
        let layer = try XCTUnwrap(manager.layers.first { $0.id == activeLayerID })
        let vector = try XCTUnwrap(layer.cels.first?.vector)
        let element = try XCTUnwrap(vector.images.first)
        let cg = try XCTUnwrap(element.image.cgImage)
        let rgba = pixel(cg, 0, 0)
        XCTAssertGreaterThan(rgba.r, 200)
        XCTAssertLessThan(rgba.g, 50)
        XCTAssertLessThan(rgba.b, 50)
        XCTAssertEqual(rgba.a, 255)
        XCTAssertTrue(manager.isAnyPieceFloating, "exactly the picker's insert: Move-box lift included")
    }

    /// An image the file cannot actually decode as one.
    func testAnUnreadableImageIsRefusedAndInsertsNothing() throws {
        let (manager, client) = connectedManager()
        let layerCountBefore = manager.layers.count
        let garbage = Data([0x00, 0x01, 0x02, 0x03])

        let result = try send(garbage, id: 1, name: "ref.png", kind: "image", through: client)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.reason, "The image could not be read")
        XCTAssertEqual(manager.layers.count, layerCountBefore, "nothing inserted")
    }

    // MARK: - Video, always its own layer

    /// **A video makes a new layer holding one `.video`** — exactly `insertVideo`'s §2.1, whatever
    /// is active. A 64×64, one-frame, level-156 clip stands in for the laptop's own drop.
    func testAVideoTransferMakesANewLayerHoldingOneVideoWithTheRightPixels() throws {
        let (manager, client) = connectedManager()
        manager.addVectorLayer()   // active vector layer: the video must still get its own, new one
        let layerCountBefore = manager.layers.count
        let clipURL = try greyClip(level: 156)
        let bytes = try Data(contentsOf: clipURL)

        let result = try send(bytes, id: 1, name: "ref.mp4", kind: "video", through: client)

        XCTAssertTrue(result.ok, "expected ok:true, got \(String(describing: result.reason))")
        XCTAssertEqual(manager.layers.count, layerCountBefore + 1, "its own new layer")
        let layer = try XCTUnwrap(manager.layers.last)
        XCTAssertEqual(layer.kind, .vector)
        let vector = try XCTUnwrap(layer.cels.first?.vector)
        let video = try XCTUnwrap(vector.videos.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.assetURL.path),
                      "the temp file was moved into VideoImportStore, not left behind")

        let reader = try XCTUnwrap(VideoFrameReader(url: video.assetURL))
        reader.locate(.zero)
        let frame = try XCTUnwrap(reader.currentFrame())
        XCTAssertEqual(CanvasFixture.nearestLevelIndex(frame.pixels[0], in: [156]), 0,
                      "the staged file decodes to the same grey level the source clip carried")
    }

    /// A file the video pipeline cannot open at all.
    func testAnUnreadableVideoIsRefusedAndInsertsNothing() throws {
        let (manager, client) = connectedManager()
        let layerCountBefore = manager.layers.count
        let garbage = Data(repeating: 0xAB, count: 64)

        let result = try send(garbage, id: 1, name: "ref.mp4", kind: "video", through: client)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.reason, "The video could not be read")
        XCTAssertEqual(manager.layers.count, layerCountBefore, "nothing inserted")
    }

    // MARK: - Refusals STREAM.md §5.8 names explicitly

    func testAnOtherKindIsRefusedWithTheSentenceAndInsertsNothing() throws {
        let (manager, client) = connectedManager()
        let layerCountBefore = manager.layers.count

        let result = try send(Data("not a picture".utf8), id: 1, name: "notes.txt", kind: "other",
                              through: client)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.reason, "PaintApp can insert images and videos only")
        XCTAssertEqual(manager.layers.count, layerCountBefore)
    }

    /// **A second BEGIN during a transfer is refused, and the first transfer is undisturbed.**
    func testASecondBeginDuringATransferIsRefused() throws {
        let (manager, client) = connectedManager()
        let layerCountBefore = manager.layers.count
        let first = solidPNGData(.blue)

        client.handle(StreamFrame(.fileBegin, payload: StreamJSON.encode(
            StreamFileBegin(id: 1, name: "a.png", size: first.count, kind: "image"))))

        let refusalExpectation = expectation(description: "refusal for the second BEGIN")
        var refusal: StreamFileResult?
        client.onFileResultSent = { answer in
            guard answer.id == 2 else { return }
            refusal = answer
            refusalExpectation.fulfill()
        }
        client.handle(StreamFrame(.fileBegin, payload: StreamJSON.encode(
            StreamFileBegin(id: 2, name: "b.png", size: 10, kind: "image"))))
        wait(for: [refusalExpectation], timeout: 5)
        client.onFileResultSent = nil

        let refusalResult = try XCTUnwrap(refusal)
        XCTAssertFalse(refusalResult.ok)
        XCTAssertEqual(refusalResult.reason, "A transfer is already in progress")

        // The first transfer completes normally afterward.
        let done = expectation(description: "FILE_RESULT for id 1")
        var firstResult: StreamFileResult?
        client.onFileResultSent = { answer in
            guard answer.id == 1 else { return }
            firstResult = answer
            done.fulfill()
        }
        client.handle(StreamFrame(.fileChunk, payload: StreamFileChunk(id: 1, bytes: first).encoded))
        client.handle(StreamFrame(.fileEnd, payload: StreamJSON.encode(StreamFileEnd(id: 1))))
        wait(for: [done], timeout: 5)

        XCTAssertEqual(try XCTUnwrap(firstResult).ok, true, "the refused second BEGIN did not disturb the first")
        XCTAssertEqual(manager.layers.count, layerCountBefore + 1, "exactly one insert happened")
    }

    /// **Bytes received not matching FILE_END's declared size are refused, and nothing is inserted.**
    func testIncompleteBytesAreRefusedAndInsertNothing() throws {
        let (manager, client) = connectedManager()
        let layerCountBefore = manager.layers.count
        let bytes = solidPNGData(.green)

        let result = try send(bytes, id: 1, name: "ref.png", kind: "image",
                              declaredSize: bytes.count + 1000, through: client)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.reason, "The file arrived incomplete")
        XCTAssertEqual(manager.layers.count, layerCountBefore, "nothing inserted")
    }

    /// **No document open answers the sentence** — simulated by letting the manager the coordinator
    /// weakly holds go away while the coordinator (and the client it started) live on, exactly the
    /// shape `closeFrameBaker` leaves nothing: nobody kept a strong reference beyond this scope.
    func testNoDocumentOpenAnswersTheSentence() throws {
        var manager: CanvasManager? = CanvasFixture.manager(layerCount: 1)
        let coordinator = manager!.streamCoordinator
        coordinator.documentEndpointOverride = Self.endpoint
        coordinator.sync()
        let client = try XCTUnwrap(coordinator.client(for: Self.endpoint))
        manager = nil

        let result = try send(solidPNGData(.red), id: 1, name: "ref.png", kind: "image", through: client)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.reason, "No document is open on the iPad")
    }
}
