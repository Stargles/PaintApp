import CoreGraphics
import XCTest

/// **The decoder against a real H.264 clip, through the real framing, with no network** —
/// STREAM.md §7 stage 1's *"logic tests decode the fixture through the real framing"*.
///
/// `Fixtures/stream-testsrc-640x360.h264` is sixty frames of ffmpeg's `testsrc` colour bars at
/// 640×360, Annex-B, two IDRs each preceded by SPS and PPS, encoded by `h264_videotoolbox` with one
/// slice per frame. The test splits it into access units itself, wraps each as a VIDEO payload,
/// runs the bytes through `StreamFraming` exactly as a socket would deliver them, parses them back
/// and feeds the decoder — so a change to the wire format, the AU parser or the NAL handling reddens
/// here before it can reach a laptop.
///
/// VideoToolbox decodes H.264 in software in the simulator, so this runs in the fast tier.
final class H264StreamDecoderLogicTests: XCTestCase {

    // MARK: - The fixture

    private func fixtureBytes() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: H264StreamDecoderLogicTests.self)
            .url(forResource: "stream-testsrc-640x360", withExtension: "h264"),
                                "The fixture must be in the test bundle's resources (project.pbxproj)")
        return try Data(contentsOf: url)
    }

    /// **The test's own AU splitter.** A slice NAL (1 or 5) ends an access unit; the non-VCL NALs
    /// before it — SPS, PPS, SEI — belong to it. That is the whole rule for a one-slice-per-frame
    /// encoder, and `testTheFixtureIsWhatItClaimsToBe` pins that the fixture is one, so a
    /// multi-slice clip could not slip through as a "60 frames decoded" that is really 120 halves.
    private func accessUnits(in annexB: Data) -> [(isKeyframe: Bool, bytes: Data)] {
        var units: [(Bool, Data)] = []
        var pending = Data()
        var pendingIsKeyframe = false
        for nal in H264StreamDecoder.splitAnnexB(annexB) {
            guard let first = nal.first else { continue }
            pending.append(contentsOf: [0, 0, 0, 1])
            pending.append(nal)
            switch first & 0x1F {
            case 5:
                pendingIsKeyframe = true
                fallthrough
            case 1:
                units.append((pendingIsKeyframe, pending))
                pending = Data()
                pendingIsKeyframe = false
            default:
                continue
            }
        }
        return units
    }

    /// Through the wire: each AU as a VIDEO frame, all of them as one byte stream, parsed back.
    private func wireFrames(from units: [(isKeyframe: Bool, bytes: Data)]) throws -> [StreamVideoPayload] {
        var wire = Data()
        for (index, unit) in units.enumerated() {
            let payload = StreamVideoPayload(isKeyframe: unit.isKeyframe,
                                             presentationTimeMicroseconds: UInt64(index) * 33_333,
                                             accessUnit: unit.bytes)
            wire.append(StreamFraming.encode(.video, payload: payload.encoded))
        }
        var parser = StreamFraming.Parser()
        // In pieces, as a socket would hand them over.
        var offset = 0
        var frames: [StreamFrame] = []
        while offset < wire.count {
            let end = min(offset + 1500, wire.count)
            parser.append(wire[offset ..< end])
            frames.append(contentsOf: try parser.drain())
            offset = end
        }
        return try frames.map { frame in
            XCTAssertEqual(frame.messageType, .video)
            return try XCTUnwrap(StreamVideoPayload(payload: frame.payload))
        }
    }

    /// RGBA at a pixel of the slot's image.
    private func sample(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (bytes[0], bytes[1], bytes[2])
    }

    // MARK: - Tests

    /// The fixture is sixty one-slice frames with two IDRs, each led by SPS and PPS. Everything
    /// below assumes this shape, so it is pinned rather than trusted.
    func testTheFixtureIsWhatItClaimsToBe() throws {
        let nals = H264StreamDecoder.splitAnnexB(try fixtureBytes())
        var counts: [UInt8: Int] = [:]
        for nal in nals { counts[nal[nal.startIndex] & 0x1F, default: 0] += 1 }
        XCTAssertEqual(counts[7], 2, "two SPS")
        XCTAssertEqual(counts[8], 2, "two PPS")
        XCTAssertEqual(counts[5], 2, "two IDR slices")
        XCTAssertEqual(counts[1], 58, "fifty-eight non-IDR slices")
        let units = accessUnits(in: try fixtureBytes())
        XCTAssertEqual(units.count, 60, "one slice per frame, sixty frames")
        XCTAssertTrue(units[0].isKeyframe && units[30].isKeyframe, "IDRs at 0 and 30")
        XCTAssertEqual(units.filter(\.isKeyframe).count, 2)
    }

    /// **At least 55 of the 60 frames decode, the picture is 640×360, and it is not black.**
    /// `testsrc` is colour bars: three pixels across the top band read as three different colours,
    /// which a decoder that produced a blank buffer — or the placeholder — could not satisfy.
    func testTheFixtureDecodesThroughTheRealFramingToAColourBarPicture() throws {
        let decoder = H264StreamDecoder()
        var arrivals = 0
        let arrivalsLock = NSLock()
        decoder.onFrame = { arrivalsLock.lock(); arrivals += 1; arrivalsLock.unlock() }

        for payload in try wireFrames(from: accessUnits(in: try fixtureBytes())) {
            decoder.feed(payload)
        }
        decoder.finishPendingDecodes()
        // VideoToolbox's asynchronous path can hand the last frames back a moment after the wait
        // returns; give it up to a second to settle rather than asserting on a race.
        let deadline = Date().addingTimeInterval(1)
        while decoder.decodedFrameCount < 60, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }

        XCTAssertGreaterThanOrEqual(decoder.decodedFrameCount, 55,
                                    "decoded \(decoder.decodedFrameCount) of 60; errors: \(decoder.decodeErrorCount)")
        XCTAssertEqual(decoder.latestFrameIndex, decoder.decodedFrameCount, "the slot counts every frame")
        arrivalsLock.lock(); let arrived = arrivals; arrivalsLock.unlock()
        XCTAssertEqual(arrived, decoder.decodedFrameCount, "onFrame fires once per decoded frame")
        XCTAssertEqual(decoder.latestFrameSize, CGSize(width: 640, height: 360))

        let image = try XCTUnwrap(decoder.latestCGImage(), "the slot must hand out a picture")
        XCTAssertEqual(image.width, 640)
        XCTAssertEqual(image.height, 360)
        // testsrc's top band is vertical colour bars; sample three bars well apart.
        let a = sample(image, x: 40, y: 20), b = sample(image, x: 320, y: 20), c = sample(image, x: 600, y: 20)
        XCTAssertTrue(a != b || b != c, "three bars must not read as one colour: \(a) \(b) \(c)")
        XCTAssertTrue(a != b && b != c && a != c, "and all three should differ: \(a) \(b) \(c)")
        let brightest = [a, b, c].map { max($0.r, $0.g, $0.b) }.max() ?? 0
        XCTAssertGreaterThan(brightest, 100, "a black picture would fail here")
    }

    /// The memo: two reads of one frame convert once, and a new frame is a new image.
    func testTheSlotMemoizesTheImagePerFrame() throws {
        let decoder = H264StreamDecoder()
        let payloads = try wireFrames(from: accessUnits(in: try fixtureBytes()))
        decoder.feed(payloads[0])
        decoder.finishPendingDecodes()
        let deadline = Date().addingTimeInterval(1)
        while decoder.decodedFrameCount < 1, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let first = try XCTUnwrap(decoder.latestCGImage())
        XCTAssertTrue(decoder.latestCGImage() === first, "the same frame is the same image")
        for payload in payloads[1 ..< 5] { decoder.feed(payload) }
        decoder.finishPendingDecodes()
        let later = Date().addingTimeInterval(1)
        while decoder.decodedFrameCount < 5, Date() < later { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertFalse(decoder.latestCGImage() === first, "a newer frame is a new image")
    }

    /// **Nothing decodes before a keyframe, and a keyframe is asked for.** Feed the P-frames after
    /// the first IDR without it: the slot stays empty, the decoder reports once that it needs a
    /// keyframe, and the moment the second IDR arrives it decodes again.
    func testFramesBeforeAKeyframeAreDroppedAndAKeyframeIsRequestedOnce() throws {
        let decoder = H264StreamDecoder()
        var requests = 0
        let lock = NSLock()
        decoder.onNeedsKeyframe = { lock.lock(); requests += 1; lock.unlock() }
        let payloads = try wireFrames(from: accessUnits(in: try fixtureBytes()))

        // The SPS/PPS ride with the IDR at 0, so give the decoder its parameter sets through a
        // payload holding *only* those NALs, then P-frames with no IDR.
        let parameterSets = H264StreamDecoder.splitAnnexB(payloads[0].accessUnit)
            .filter { ($0[$0.startIndex] & 0x1F) == 7 || ($0[$0.startIndex] & 0x1F) == 8 }
        var setsOnly = Data()
        for nal in parameterSets { setsOnly.append(contentsOf: [0, 0, 0, 1]); setsOnly.append(nal) }
        decoder.feed(StreamVideoPayload(isKeyframe: false, presentationTimeMicroseconds: 0, accessUnit: setsOnly))
        for payload in payloads[1 ..< 10] { decoder.feed(payload) }
        decoder.finishPendingDecodes()
        XCTAssertEqual(decoder.decodedFrameCount, 0, "no IDR yet, nothing may decode")
        lock.lock(); let asked = requests; lock.unlock()
        XCTAssertEqual(asked, 1, "one request per gap, not one per dropped frame")

        for payload in payloads[30 ..< 40] { decoder.feed(payload) }
        decoder.finishPendingDecodes()
        let deadline = Date().addingTimeInterval(1)
        while decoder.decodedFrameCount < 10, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertGreaterThanOrEqual(decoder.decodedFrameCount, 8, "the second IDR restarts decoding")
    }

    /// The pure helpers: Annex-B splitting handles both start-code lengths and AVCC framing writes
    /// the length prefix big-endian.
    func testAnnexBSplittingAndAVCCFraming() {
        let stream = Data([0, 0, 0, 1, 0x67, 0xAA, 0xBB,
                           0, 0, 1, 0x68, 0xCC,
                           0, 0, 0, 1, 0x65, 0x01, 0x02, 0x03])
        let nals = H264StreamDecoder.splitAnnexB(stream)
        XCTAssertEqual(nals, [Data([0x67, 0xAA, 0xBB]), Data([0x68, 0xCC]), Data([0x65, 0x01, 0x02, 0x03])])
        let avcc = [UInt8](H264StreamDecoder.avcc([Data([0x65, 0x01, 0x02, 0x03])]))
        XCTAssertEqual(avcc, [0, 0, 0, 4, 0x65, 0x01, 0x02, 0x03])
        XCTAssertEqual(H264StreamDecoder.splitAnnexB(Data([1, 2, 3])), [], "no start code, no NAL")
    }
}
