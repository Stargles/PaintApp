import XCTest

/// Pure-logic tests for `paintstream/1`'s framing and payloads — STREAM.md §3, `StreamProtocol.swift`.
///
/// No socket anywhere: `StreamFraming.encode` writes bytes and `StreamFraming.Parser` reads them
/// back, and the properties §3 promises are each one test — every message type round-trips, a
/// stream split at arbitrary byte boundaries reassembles, an unknown type is skipped rather than
/// fatal, and a truncated frame waits rather than fails.
final class StreamFramingLogicTests: XCTestCase {

    // MARK: - Round trips

    /// Every type §3 names, with a payload that is not empty, through the encoder and back.
    func testEveryMessageTypeRoundTrips() throws {
        let types: [StreamMessageType] = [.hello, .status, .video, .control, .fileBegin, .fileChunk,
                                          .fileEnd, .fileResult, .ping, .pong]
        var parser = StreamFraming.Parser()
        var sent: [StreamFrame] = []
        for (index, type) in types.enumerated() {
            let frame = StreamFrame(type, payload: Data(repeating: UInt8(index + 1), count: index * 7))
            sent.append(frame)
            parser.append(StreamFraming.encode(frame))
        }
        let received = try parser.drain()
        XCTAssertEqual(received, sent, "every frame comes back with its type and its exact payload")
        XCTAssertEqual(parser.pendingByteCount, 0, "nothing is left over")
    }

    /// The header is exactly five bytes: the type, then the length big-endian.
    func testTheHeaderIsTypeThenBigEndianLength() {
        let bytes = [UInt8](StreamFraming.encode(.video, payload: Data(repeating: 0xAB, count: 0x0001_0203)))
        XCTAssertEqual(bytes[0], 0x03)
        XCTAssertEqual(Array(bytes[1 ..< 5]), [0x00, 0x01, 0x02, 0x03])
        XCTAssertEqual(bytes.count, 5 + 0x0001_0203)
    }

    /// A zero-length payload is a five-byte frame — PING and PONG.
    func testAnEmptyPayloadIsFiveBytes() throws {
        var parser = StreamFraming.Parser()
        parser.append(StreamFraming.encode(.ping))
        parser.append(StreamFraming.encode(.pong))
        XCTAssertEqual(try parser.drain(), [StreamFrame(.ping), StreamFrame(.pong)])
    }

    // MARK: - Chunking

    /// **A byte stream cut at every possible boundary reassembles to the same frames.** TCP
    /// delivers whatever it delivers; the parser must not care where a read ended.
    func testFramesSplitAcrossArbitraryChunkBoundariesReassemble() throws {
        let frames = [
            StreamFrame(.hello, payload: Data("{\"proto\":1}".utf8)),
            StreamFrame(.video, payload: Data((0 ..< 300).map { UInt8($0 & 0xFF) })),
            StreamFrame(.ping),
            StreamFrame(.status, payload: Data("{}".utf8)),
        ]
        let wire = frames.map(StreamFraming.encode).reduce(Data(), +)
        for chunk in [1, 2, 3, 5, 7, 64, 301, wire.count] {
            var parser = StreamFraming.Parser()
            var received: [StreamFrame] = []
            var offset = 0
            while offset < wire.count {
                let end = min(offset + chunk, wire.count)
                parser.append(wire[offset ..< end])
                received.append(contentsOf: try parser.drain())
                offset = end
            }
            XCTAssertEqual(received, frames, "chunk size \(chunk)")
            XCTAssertEqual(parser.pendingByteCount, 0, "chunk size \(chunk) left bytes behind")
        }
    }

    /// A frame whose payload has not all arrived is not a frame yet: `next()` answers nil and the
    /// bytes stay for the next append.
    func testATruncatedFrameWaitsRatherThanFailing() throws {
        let whole = StreamFraming.encode(.video, payload: Data(repeating: 0x5A, count: 40))
        var parser = StreamFraming.Parser()
        parser.append(whole[0 ..< 3])
        XCTAssertNil(try parser.next(), "three bytes is less than a header")
        XCTAssertEqual(parser.pendingByteCount, 3)
        parser.append(whole[3 ..< 20])
        XCTAssertNil(try parser.next(), "a header and part of the payload is not a frame")
        XCTAssertEqual(parser.pendingByteCount, 20)
        parser.append(whole[20...])
        XCTAssertEqual(try parser.next(), StreamFrame(.video, payload: Data(repeating: 0x5A, count: 40)))
        XCTAssertNil(try parser.next())
    }

    /// **An unknown type is skipped by its length and the frame after it still arrives.** A newer
    /// laptop may send a message this build has no case for; §3 says that is never fatal.
    func testAnUnknownTypeIsSkippedAndTheNextFrameStillArrives() throws {
        var parser = StreamFraming.Parser()
        parser.append(StreamFraming.encode(StreamFrame(type: 0x7F, payload: Data(repeating: 1, count: 33))))
        parser.append(StreamFraming.encode(.pong))
        let frames = try parser.drain()
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].type, 0x7F)
        XCTAssertNil(frames[0].messageType, "the parser carries it; the client is what skips it")
        XCTAssertEqual(frames[0].payload.count, 33, "skipped by exactly its own length")
        XCTAssertEqual(frames[1], StreamFrame(.pong))
    }

    /// A length no message could have is a corrupt stream, and the parser says so rather than
    /// waiting forever for sixty-five gigabytes.
    func testAnAbsurdLengthIsAnErrorRatherThanAnEndlessWait() {
        var parser = StreamFraming.Parser()
        parser.append(Data([0x03, 0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertThrowsError(try parser.next()) { error in
            XCTAssertEqual(error as? StreamFraming.Parser.Failure,
                           .oversizedPayload(claimed: 0xFFFF_FFFF))
        }
        XCTAssertEqual(parser.pendingByteCount, 0, "the buffer is dropped with the connection")
    }

    // MARK: - Payloads

    func testHelloRoundTripsAndCarriesTheProtocolVersion() {
        let hello = StreamHello.fromThisApp(version: "1.2", deviceName: "Kevin's iPad")
        XCTAssertEqual(hello.proto, StreamHello.protocolVersion)
        XCTAssertEqual(hello.app, "PaintApp")
        let decoded = StreamJSON.decode(StreamHello.self, from: StreamJSON.encode(hello))
        XCTAssertEqual(decoded, hello)
    }

    /// STATUS as the laptop spells it in §3, byte for byte.
    func testStatusDecodesTheLaptopsSpelling() throws {
        let json = """
        {"source":{"kind":"window","name":"Blender","id":"0x1234"},"width":1920,"height":1080,
         "fps":30,"codec":"h264","streaming":true}
        """
        let status = try XCTUnwrap(StreamJSON.decode(StreamStatus.self, from: Data(json.utf8)))
        XCTAssertEqual(status.source.kind, "window")
        XCTAssertEqual(status.source.name, "Blender")
        XCTAssertEqual(status.width, 1920)
        XCTAssertEqual(status.height, 1080)
        XCTAssertEqual(status.fps, 30)
        XCTAssertTrue(status.streaming)
        XCTAssertNil(status.reason)
        XCTAssertEqual(status.sourceLabel, "Blender")
    }

    /// A STATUS with no source picked has a reason and no name, and the label falls back to the kind.
    func testStatusWithNoSourceCarriesAReason() throws {
        let json = """
        {"source":{"kind":"none","name":""},"width":0,"height":0,"fps":0,"codec":"h264",
         "streaming":false,"reason":"No source picked"}
        """
        let status = try XCTUnwrap(StreamJSON.decode(StreamStatus.self, from: Data(json.utf8)))
        XCTAssertFalse(status.streaming)
        XCTAssertEqual(status.reason, "No source picked")
        XCTAssertEqual(status.sourceLabel, "none")
    }

    /// VIDEO's nine-byte header: flags, then the presentation time big-endian, then the AU.
    func testVideoPayloadRoundTripsItsHeader() throws {
        let au = Data([0, 0, 0, 1, 0x65, 0x88, 0x84])
        let payload = StreamVideoPayload(isKeyframe: true, presentationTimeMicroseconds: 0x0102_0304_0506_0708,
                                         accessUnit: au)
        let bytes = [UInt8](payload.encoded)
        XCTAssertEqual(bytes[0], 0x01)
        XCTAssertEqual(Array(bytes[1 ..< 9]), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(Data(bytes[9...]), au)
        XCTAssertEqual(StreamVideoPayload(payload: payload.encoded), payload)
        XCTAssertNil(StreamVideoPayload(payload: Data([1, 2, 3])), "shorter than its header")
        let plain = StreamVideoPayload(isKeyframe: false, presentationTimeMicroseconds: 7, accessUnit: au)
        XCTAssertEqual([UInt8](plain.encoded)[0], 0x00)
    }

    func testControlCommandsSpellTheirNames() {
        XCTAssertEqual(String(data: StreamControlCommand.keyframe.encoded, encoding: .utf8), "{\"cmd\":\"keyframe\"}")
        XCTAssertEqual(StreamControlCommand(payload: Data("{\"cmd\":\"pause\"}".utf8)), .pause)
        XCTAssertEqual(StreamControlCommand(payload: Data("{\"cmd\":\"resume\"}".utf8)), .resume)
        XCTAssertNil(StreamControlCommand(payload: Data("{\"cmd\":\"dance\"}".utf8)))
    }

    /// STREAM.md §5.8, stage 4: FILE_RESULT round-trips both an acceptance and a refusal with its
    /// sentence, and FILE_BEGIN decodes the laptop's JSON exactly.
    func testFileResultRoundTripsOkAndARefusalSentence() {
        let ok = StreamFileResult(id: 7, ok: true, reason: nil)
        XCTAssertEqual(StreamJSON.decode(StreamFileResult.self, from: StreamJSON.encode(ok)), ok)
        let refused = StreamFileResult(id: 7, ok: false, reason: "The image could not be read")
        XCTAssertEqual(StreamJSON.decode(StreamFileResult.self, from: StreamJSON.encode(refused)), refused)
        let begin = StreamJSON.decode(StreamFileBegin.self,
                                      from: Data("{\"id\":7,\"name\":\"ref.mp4\",\"size\":12,\"kind\":\"video\"}".utf8))
        XCTAssertEqual(begin, StreamFileBegin(id: 7, name: "ref.mp4", size: 12, kind: "video"))
    }

    /// FILE_CHUNK's own header: `u32 id` big-endian, then the bytes — not JSON, so a chunk does not
    /// pay base64 on top of a video-sized transfer.
    func testFileChunkRoundTripsItsHeader() throws {
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02])
        let chunk = StreamFileChunk(id: 0x0102_0304, bytes: bytes)
        let encoded = [UInt8](chunk.encoded)
        XCTAssertEqual(Array(encoded[0 ..< 4]), [1, 2, 3, 4])
        XCTAssertEqual(Data(encoded[4...]), bytes)
        XCTAssertEqual(StreamFileChunk(payload: chunk.encoded), chunk)
        XCTAssertNil(StreamFileChunk(payload: Data([1, 2, 3])), "shorter than its header")
    }
}
