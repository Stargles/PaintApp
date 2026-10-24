import XCTest

/// Pure-logic tests for STREAM.md §5.8's send path — iPad → laptop — with **no socket anywhere**.
///
/// A completion transport drives the real serialized writer/disk pump without a socket. Its
/// completion can stall or fail, unlike an observer pretending the whole file was sent. Responses
/// use the same exposed frame handler as the receive tests.
final class StreamFileSendLogicTests: XCTestCase {

    private static let endpoint = StreamEndpoint(host: "laptop", port: 47301)

    private var directory: URL!
    private var client: ScreenStreamClient!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stream-file-send-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        client = ScreenStreamClient(endpoint: Self.endpoint, appVersion: "1", deviceName: "test-ipad")
        client.writeFrameOverride = { _, _, completed in completed(nil) }
    }

    override func tearDownWithError() throws {
        client = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    /// A file of exactly `bytes` bytes, an incrementing pattern rather than all-zero, so a chunk
    /// boundary landing in the wrong place would show up as the wrong count rather than passing by
    /// accident on indistinguishable content.
    private func makeFile(bytes: Int, named name: String = "export.mp4") throws -> URL {
        let url = directory.appendingPathComponent(name)
        var data = Data(capacity: bytes)
        for i in 0 ..< bytes { data.append(UInt8(truncatingIfNeeded: i)) }
        try data.write(to: url)
        return url
    }

    private enum SentFrame: Equatable {
        case begin(StreamFileBegin)
        case chunk(id: Int, byteCount: Int)
        case end(StreamFileEnd)
    }

    // MARK: - Chunking arithmetic

    /// **700 KiB → FILE_BEGIN, three FILE_CHUNKs of 256/256/188 KiB, FILE_END** —
    /// `ScreenStreamClient.fileChunkSize` is 256 KiB (§3's cap), and 700 = 256 + 256 + 188.
    func testA700KiBFileIsSentAsBeginThreeChunksAndEndWithMatchingIDs() throws {
        let totalBytes = 700 * 1024
        let url = try makeFile(bytes: totalBytes)

        var frames: [SentFrame] = []
        let sawEnd = expectation(description: "FILE_END written")
        client.onFrameSent = { type, payload in
            switch type {
            case .fileBegin:
                guard let begin = StreamJSON.decode(StreamFileBegin.self, from: payload) else { return }
                frames.append(.begin(begin))
            case .fileChunk:
                guard let chunk = StreamFileChunk(payload: payload) else { return }
                frames.append(.chunk(id: chunk.id, byteCount: chunk.bytes.count))
            case .fileEnd:
                guard let end = StreamJSON.decode(StreamFileEnd.self, from: payload) else { return }
                frames.append(.end(end))
                sawEnd.fulfill()
            default:
                break
            }
        }

        let resultReceived = expectation(description: "FILE_RESULT")
        var outcome: StreamFileReceiveOutcome?
        client.sendFile(url: url, kind: "video", onProgress: { _, _ in }, completion: { result in
            outcome = result
            resultReceived.fulfill()
        })

        wait(for: [sawEnd], timeout: 5)
        guard case .begin(let begin) = frames.first else {
            return XCTFail("expected FILE_BEGIN first, got \(frames)")
        }
        XCTAssertEqual(begin.name, "export.mp4")
        XCTAssertEqual(begin.size, totalBytes)
        XCTAssertEqual(begin.kind, "video")

        let chunks = frames.compactMap { frame -> (id: Int, byteCount: Int)? in
            if case .chunk(let id, let byteCount) = frame { return (id, byteCount) }
            return nil
        }
        XCTAssertEqual(chunks.map(\.byteCount), [256 * 1024, 256 * 1024, 188 * 1024])
        XCTAssertTrue(chunks.allSatisfy { $0.id == begin.id }, "every chunk names the same transfer")

        guard case .end(let end) = frames.last else {
            return XCTFail("expected FILE_END last, got \(frames)")
        }
        XCTAssertEqual(end.id, begin.id)
        XCTAssertEqual(frames.count, 5, "BEGIN, three CHUNKs, END")

        // Play the laptop's answer back in — nothing else will, with no socket.
        client.handle(StreamFrame(.fileResult, payload: StreamJSON.encode(
            StreamFileResult(id: begin.id, ok: true, reason: nil))))
        wait(for: [resultReceived], timeout: 5)
        XCTAssertEqual(outcome, .ok)
    }

    // MARK: - The result sentence

    /// **The laptop's `ok:false, reason:` becomes the completion's own refusal, sentence and all.**
    func testALaptopRefusalCarriesItsReasonThrough() throws {
        let url = try makeFile(bytes: 10)
        var beginID: Int?
        let sawBegin = expectation(description: "FILE_BEGIN written")
        client.onFrameSent = { type, payload in
            guard type == .fileBegin, let begin = StreamJSON.decode(StreamFileBegin.self, from: payload)
            else { return }
            beginID = begin.id
            sawBegin.fulfill()
        }

        let resultReceived = expectation(description: "FILE_RESULT")
        var outcome: StreamFileReceiveOutcome?
        client.sendFile(url: url, kind: "image", onProgress: { _, _ in }, completion: { result in
            outcome = result
            resultReceived.fulfill()
        })

        wait(for: [sawBegin], timeout: 5)
        let id = try XCTUnwrap(beginID)

        client.handle(StreamFrame(.fileResult, payload: StreamJSON.encode(
            StreamFileResult(id: id, ok: false, reason: "The image could not be read"))))
        wait(for: [resultReceived], timeout: 5)
        XCTAssertEqual(outcome, .refused("The image could not be read"))
    }

    // MARK: - One at a time

    /// **A second `sendFile` while one is running is refused without touching the wire**, and the
    /// first transfer is unaffected.
    func testASecondSendWhileOneIsRunningIsRefused() throws {
        let url = try makeFile(bytes: 10)
        let firstDone = expectation(description: "first result")
        var firstOutcome: StreamFileReceiveOutcome?
        client.sendFile(url: url, kind: "image", onProgress: { _, _ in }, completion: { result in
            firstOutcome = result
            firstDone.fulfill()
        })

        let secondDone = expectation(description: "second refused immediately")
        var secondOutcome: StreamFileReceiveOutcome?
        client.sendFile(url: url, kind: "image", onProgress: { _, _ in }, completion: { result in
            secondOutcome = result
            secondDone.fulfill()
        })
        wait(for: [secondDone], timeout: 5)
        XCTAssertEqual(secondOutcome, .refused("A transfer is already in progress"))

        // The first send used the client's first outgoing id (1) — the refused second never
        // consumed one — so this resolves the first transfer and leaves nothing dangling.
        client.handle(StreamFrame(.fileResult, payload: StreamJSON.encode(
            StreamFileResult(id: 1, ok: true, reason: nil))))
        wait(for: [firstDone], timeout: 5)
        XCTAssertEqual(firstOutcome, .ok, "the refused second attempt did not disturb the first")
    }
    func testAStalledChunkKeepsOnlyOneWriteAndStopSettlesWithoutReadingTheTail() throws {
        let url = try makeFile(bytes: 700 * 1024)
        let stalled = expectation(description: "first actual chunk write stalled")
        var release: ((Error?) -> Void)?
        var frames: [(StreamMessageType, Data)] = []
        client.writeFrameOverride = { type, payload, completed in
            frames.append((type, payload))
            if type == .fileChunk {
                if release == nil { release = completed; stalled.fulfill() }
            }
            else { completed(nil) }
        }
        var progress: [Int] = [], outcomes: [StreamFileReceiveOutcome] = []
        client.sendFile(url: url, kind: "video", onProgress: { count, _ in progress.append(count) }) { result in
            outcomes.append(result)
        }
        wait(for: [stalled], timeout: 5)
        for _ in 0 ..< 100 { client.pause(); client.resume() }
        client.pause(); client.requestKeyframe()
        // The refusal is a queue barrier after all controls; none may allocate another wire write.
        let barrier = expectation(description: "client queue remains responsive")
        var second: StreamFileReceiveOutcome?
        client.sendFile(url: url, kind: "video", onProgress: { _, _ in }) { result in
            second = result; barrier.fulfill()
        }
        wait(for: [barrier], timeout: 5)
        XCTAssertEqual(second, .refused("A transfer is already in progress"))
        XCTAssertEqual(frames.map { $0.0 }, [.fileBegin, .fileChunk])
        XCTAssertEqual(frames.last?.1.count, 4 + 256 * 1024)
        XCTAssertTrue(progress.isEmpty, "Bytes count as sent only after actual completion")
        let stopped = expectation(description: "stop joined client work")
        client.stop { stopped.fulfill() }
        wait(for: [stopped], timeout: 5)
        XCTAssertEqual(outcomes, [.refused("The connection was lost.")])
        release?(nil) // A late old-run callback cannot read/send another chunk or finish twice.
        let drained = expectation(description: "late callback drained")
        client.stop { drained.fulfill() }
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(outcomes.count, 1)
    }

    func testAnActualWriteErrorRefusesAndStopsBeforeReadingOrSendingTheNextChunk() throws {
        let url = try makeFile(bytes: 700 * 1024)
        let stalled = expectation(description: "first chunk admitted")
        var release: ((Error?) -> Void)?
        var types: [StreamMessageType] = [], outcomes: [StreamFileReceiveOutcome] = []
        client.writeFrameOverride = { type, _, completed in
            types.append(type)
            if type == .fileChunk, release == nil { release = completed; stalled.fulfill() }
            else { completed(nil) }
        }
        client.sendFile(url: url, kind: "video", onProgress: { _, _ in }) { outcomes.append($0) }
        wait(for: [stalled], timeout: 5)
        release?(CocoaError(.fileWriteUnknown))
        let stopped = expectation(description: "write result processed before explicit stop")
        client.stop { stopped.fulfill() }
        wait(for: [stopped], timeout: 5)
        XCTAssertEqual(types, [.fileBegin, .fileChunk], "A failed write may not advance the disk pump")
        XCTAssertEqual(outcomes, [.refused("The connection was lost.")])
    }

}
