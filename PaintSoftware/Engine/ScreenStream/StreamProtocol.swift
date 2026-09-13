import Foundation

// MARK: - paintstream/1 — STREAM.md §3
//
// One TCP connection, every message a frame: `u8 type`, `u32 length` (big-endian, payload bytes),
// then the payload. JSON payloads are UTF-8 objects. Unknown types are skipped by length, never
// fatal. This file is the codec and nothing else — it touches no socket and no decoder, so the
// logic tier can drive it byte by byte (`StreamFramingLogicTests`).

/// The message types `paintstream/1` defines. A raw `UInt8` on the wire; a value this build has no
/// case for is carried through `StreamFrame.type` and skipped by the client.
nonisolated enum StreamMessageType: UInt8 {
    case hello = 0x01
    case status = 0x02
    case video = 0x03
    case control = 0x04
    case fileBegin = 0x10
    case fileChunk = 0x11
    case fileEnd = 0x12
    case fileResult = 0x13
    case ping = 0x20
    case pong = 0x21
}

/// One frame off the wire, before its type is interpreted. `type` is the raw byte so an unknown
/// message is representable — the parser's contract is *"skip it, never fail"*.
nonisolated struct StreamFrame: Equatable {
    var type: UInt8
    var payload: Data

    init(type: UInt8, payload: Data = Data()) {
        self.type = type
        self.payload = payload
    }

    init(_ type: StreamMessageType, payload: Data = Data()) {
        self.init(type: type.rawValue, payload: payload)
    }

    /// The typed message, or nil for a type this build does not know.
    var messageType: StreamMessageType? { StreamMessageType(rawValue: type) }
}

/// The framing: `encode` writes one frame, `Parser` reads them back out of a byte stream that
/// arrives in whatever pieces TCP delivers.
nonisolated enum StreamFraming {
    /// The five-byte header: type plus big-endian length.
    static let headerLength = 5

    /// **The most a single payload may claim.** A length past this is not a message this protocol
    /// could send — a 1080p keyframe is under a megabyte — so the parser treats it as a corrupt
    /// stream rather than waiting forever for bytes that will never come. 64 MiB leaves a wide
    /// margin over the largest FILE_CHUNK (256 KiB) and any conceivable video frame.
    static let maximumPayloadLength = 64 << 20

    static func encode(_ frame: StreamFrame) -> Data {
        var out = Data(capacity: headerLength + frame.payload.count)
        out.append(frame.type)
        let length = UInt32(frame.payload.count).bigEndian
        withUnsafeBytes(of: length) { out.append(contentsOf: $0) }
        out.append(frame.payload)
        return out
    }

    static func encode(_ type: StreamMessageType, payload: Data = Data()) -> Data {
        encode(StreamFrame(type, payload: payload))
    }

    /// Accumulates bytes and hands back whole frames. A frame whose payload has not fully arrived
    /// waits — `next()` answers nil and the bytes stay — and a length past
    /// `maximumPayloadLength` throws `Failure.oversizedPayload`, after which the parser is empty
    /// and the connection is the caller's to drop.
    struct Parser {
        enum Failure: Error, Equatable {
            case oversizedPayload(claimed: Int)
        }

        private var buffer = Data()

        init() {}

        /// Bytes this parser is holding that have not yet formed a whole frame.
        var pendingByteCount: Int { buffer.count }

        mutating func append(_ data: Data) {
            buffer.append(data)
        }

        /// The next whole frame, or nil while the buffer holds less than one.
        mutating func next() throws -> StreamFrame? {
            guard buffer.count >= StreamFraming.headerLength else { return nil }
            let type = buffer[buffer.startIndex]
            let lengthBytes = buffer[buffer.startIndex + 1 ..< buffer.startIndex + 5]
            let length = lengthBytes.reduce(0) { ($0 << 8) | Int($1) }
            guard length <= StreamFraming.maximumPayloadLength else {
                buffer.removeAll()
                throw Failure.oversizedPayload(claimed: length)
            }
            let total = StreamFraming.headerLength + length
            guard buffer.count >= total else { return nil }
            let payloadStart = buffer.startIndex + StreamFraming.headerLength
            let payload = Data(buffer[payloadStart ..< payloadStart + length])
            buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + total)
            return StreamFrame(type: type, payload: payload)
        }

        /// Every whole frame the buffer holds, in order.
        mutating func drain() throws -> [StreamFrame] {
            var frames: [StreamFrame] = []
            while let frame = try next() { frames.append(frame) }
            return frames
        }
    }
}

// MARK: - Payloads

/// HELLO, both directions: the first message each way.
nonisolated struct StreamHello: Codable, Equatable {
    /// The protocol version this build speaks. A HELLO carrying another number closes the connection
    /// with a sentence on both screens (§3's rules).
    static let protocolVersion = 1

    var proto: Int
    var app: String
    var version: String
    var name: String

    /// This app's own greeting.
    static func fromThisApp(version: String, deviceName: String) -> StreamHello {
        StreamHello(proto: protocolVersion, app: "PaintApp", version: version, name: deviceName)
    }
}

/// STATUS, laptop → iPad: what is being sent, at what size, and whether it is being sent at all.
nonisolated struct StreamStatus: Codable, Equatable {
    struct Source: Codable, Equatable {
        /// `"monitor"`, `"window"` or `"none"`.
        var kind: String
        var name: String
        var id: String?

        init(kind: String, name: String, id: String? = nil) {
            self.kind = kind
            self.name = name
            self.id = id
        }
    }

    var source: Source
    var width: Int
    var height: Int
    var fps: Double
    var codec: String
    var streaming: Bool
    /// Why `streaming` is false, when it is: no source picked, paused, the window closed.
    var reason: String?

    init(source: Source, width: Int, height: Int, fps: Double, codec: String = "h264",
         streaming: Bool, reason: String? = nil) {
        self.source = source
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.streaming = streaming
        self.reason = reason
    }

    /// What the stage-2 bar prints beside the state, and what `VectorStreamElement.sourceLabel`
    /// stores: the source's name, or its kind when it has none.
    var sourceLabel: String {
        source.name.isEmpty ? source.kind : source.name
    }
}

/// VIDEO, laptop → iPad: `u8 flags` (bit 0 = keyframe), `u64 pts_us`, then one H.264 access unit in
/// Annex-B form. A keyframe's SPS and PPS ride inside the same payload.
nonisolated struct StreamVideoPayload: Equatable {
    static let headerLength = 9

    var isKeyframe: Bool
    var presentationTimeMicroseconds: UInt64
    var accessUnit: Data

    init(isKeyframe: Bool, presentationTimeMicroseconds: UInt64, accessUnit: Data) {
        self.isKeyframe = isKeyframe
        self.presentationTimeMicroseconds = presentationTimeMicroseconds
        self.accessUnit = accessUnit
    }

    /// Nil for a payload shorter than its own header.
    init?(payload: Data) {
        guard payload.count >= Self.headerLength else { return nil }
        let flags = payload[payload.startIndex]
        var pts: UInt64 = 0
        for offset in 1 ... 8 { pts = (pts << 8) | UInt64(payload[payload.startIndex + offset]) }
        isKeyframe = flags & 0x01 != 0
        presentationTimeMicroseconds = pts
        accessUnit = Data(payload[(payload.startIndex + Self.headerLength)...])
    }

    var encoded: Data {
        var out = Data(capacity: Self.headerLength + accessUnit.count)
        out.append(isKeyframe ? 0x01 : 0x00)
        let pts = presentationTimeMicroseconds.bigEndian
        withUnsafeBytes(of: pts) { out.append(contentsOf: $0) }
        out.append(accessUnit)
        return out
    }
}

/// CONTROL, iPad → laptop.
nonisolated enum StreamControlCommand: String, Codable, Equatable {
    case pause, resume, keyframe

    private struct Envelope: Codable { var cmd: StreamControlCommand }

    var encoded: Data {
        // A three-field-free object cannot fail to encode; the `try?` is for the type checker.
        (try? JSONEncoder().encode(Envelope(cmd: self))) ?? Data()
    }

    init?(payload: Data) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: payload) else { return nil }
        self = envelope.cmd
    }
}

/// FILE_BEGIN, both directions. Stage 4 builds the transfer; stage 1 parses it only to refuse it
/// politely (`StreamFileResult.notSupportedYet`).
nonisolated struct StreamFileBegin: Codable, Equatable {
    var id: Int
    var name: String
    var size: Int
    /// `"image"`, `"video"` or `"other"`.
    var kind: String
}

/// FILE_END, both directions.
nonisolated struct StreamFileEnd: Codable, Equatable {
    var id: Int
}

/// FILE_RESULT, both directions: `ok`, and a `reason` the sender shows to the person when not.
nonisolated struct StreamFileResult: Codable, Equatable {
    var id: Int
    var ok: Bool
    var reason: String?

    /// Stage 1's answer to every FILE_BEGIN — the transfer is stage 4, and the fake streamer's
    /// `--send` gets a clean sentence rather than silence.
    static func notSupportedYet(id: Int) -> StreamFileResult {
        StreamFileResult(id: id, ok: false, reason: "Not supported yet")
    }
}

/// JSON helpers with the one shape every payload here uses.
nonisolated enum StreamJSON {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}
