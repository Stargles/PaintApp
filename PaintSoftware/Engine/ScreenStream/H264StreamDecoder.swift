import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import UIKit

/// **Annex-B H.264 in, the newest decoded picture out** — STREAM.md §5.2's decoder.
///
/// One instance per `ScreenStreamClient`. Access units arrive through `feed(_:)` on whatever queue
/// the client reads its socket on; everything after that runs on this decoder's own serial queue,
/// so a slow decode never holds up the socket and nothing here ever touches the main thread. The
/// output is a **latest-frame slot**: one `CVPixelBuffer` behind a lock, newest wins, so a consumer
/// that reads at 30 Hz while frames arrive at 60 sees the current picture and never a queue.
///
/// ## What it does with each NAL
///
/// - **SPS (7) and PPS (8)** are kept. When either changes, the `CMVideoFormatDescription` is rebuilt
///   through `CMVideoFormatDescriptionCreateFromH264ParameterSets` and the `VTDecompressionSession`
///   with it — which is how a source switch on the laptop (a different window, a different size)
///   lands without a reconnect.
/// - **AUD (9), SEI (6) and everything that is not a slice** are dropped. The session is built with
///   the parameter sets in the format description, and a coded-slice-only sample is what
///   VideoToolbox is happiest with.
/// - **Slices (1 and 5)** are re-framed as AVCC — a four-byte big-endian length before each NAL —
///   into one `CMSampleBuffer` per access unit and handed to `VTDecompressionSessionDecodeFrame`.
///
/// ## Keyframes
///
/// Nothing decodes until an IDR (5) has been seen: a P-frame against no reference is garbage at
/// best and a decoder error at worst. A decode error flips the decoder back into that state, drops
/// every AU until the next IDR, and calls `onNeedsKeyframe` once so the client can ask the laptop
/// for one — §3's *"a decode error requests a keyframe and drops AUs until one arrives"*.
///
/// ## The slot's image
///
/// `latestCGImage()` converts the slot's buffer with `VTCreateCGImageFromCVPixelBuffer`, memoized
/// on the frame's index so two reads of one frame convert once. Where that conversion is *called*
/// from is the coordinator's decision, not this type's; STREAM.md §8 leaves open whether it should
/// become a texture path, and the coordinator's own doc carries the measurement.
nonisolated final class H264StreamDecoder {

    /// Which NAL unit types this decoder hands to VideoToolbox.
    private enum NALType: UInt8 {
        case sliceNonIDR = 1
        case sliceIDR = 5
        case sei = 6
        case sps = 7
        case pps = 8
        case aud = 9
    }

    private let queue = DispatchQueue(label: "PaintSoftware.ScreenStream.decode", qos: .userInitiated)

    // Decoder state — queue-confined.
    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var awaitingKeyframe = true
    private var needsKeyframeReported = false

    // The slot — lock-confined.
    private let slotLock = NSLock()
    private var latestBuffer: CVPixelBuffer?
    private var latestIndex = 0
    private var cachedImage: (index: Int, image: CGImage)?
    private var decodedCount = 0
    private var errorCount = 0

    /// Called on the decode queue once per decoded frame, after the slot has been updated. The
    /// coordinator arms its coalesced tick from here; it must not do work of its own.
    var onFrame: (() -> Void)?

    /// Called on the decode queue when a decode error or a missing reference means the stream
    /// cannot continue without a keyframe. Fires once per gap, not once per dropped AU.
    var onNeedsKeyframe: (() -> Void)?

    init() {}

    deinit {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
    }

    // MARK: - Input

    /// One access unit, Annex-B, exactly as the VIDEO payload carries it. Returns immediately; the
    /// work runs on the decode queue.
    func feed(_ video: StreamVideoPayload) {
        queue.async { [weak self] in
            self?.decode(accessUnit: video.accessUnit,
                         presentationTime: CMTime(value: CMTimeValue(video.presentationTimeMicroseconds),
                                                  timescale: 1_000_000))
        }
    }

    /// Forgets the parameter sets and the session, and waits for the next IDR. Called by the client
    /// on every reconnect — no session state survives one (§3).
    func reset() {
        queue.async { [weak self] in
            guard let self else { return }
            self.tearDownSession()
            self.sps = nil
            self.pps = nil
            self.formatDescription = nil
            self.awaitingKeyframe = true
            self.needsKeyframeReported = false
        }
    }

    /// Blocks until every access unit fed so far has been decoded or dropped. **For tests**, which
    /// feed a whole clip and then ask the slot; the app never waits on the decoder.
    func finishPendingDecodes() {
        queue.sync {
            if let session { VTDecompressionSessionWaitForAsynchronousFrames(session) }
        }
    }

    // MARK: - Output

    /// How many frames have landed in the slot since the decoder was made.
    var decodedFrameCount: Int {
        slotLock.lock(); defer { slotLock.unlock() }
        return decodedCount
    }

    /// How many access units VideoToolbox refused.
    var decodeErrorCount: Int {
        slotLock.lock(); defer { slotLock.unlock() }
        return errorCount
    }

    /// The index of the frame in the slot — 0 before the first, then one more per decoded frame. A
    /// consumer compares it with the index it last drew, so a tick that arrives before a new frame
    /// costs nothing.
    var latestFrameIndex: Int {
        slotLock.lock(); defer { slotLock.unlock() }
        return latestIndex
    }

    /// The slot's pixel size, or nil before the first frame.
    var latestFrameSize: CGSize? {
        slotLock.lock(); defer { slotLock.unlock() }
        guard let buffer = latestBuffer else { return nil }
        return CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
    }

    /// The newest decoded picture as a `CGImage`, or nil before the first frame. Converted with
    /// `VTCreateCGImageFromCVPixelBuffer` and memoized per frame index. Safe from any thread.
    func latestCGImage() -> CGImage? { latestImage()?.image }

    /// The newest decoded picture together with its frame index, read under one lock so the index
    /// a caller records is the index of the picture it was handed — a second acquisition would let
    /// a frame land between the two and pair the older picture with the newer number. **One
    /// `CGImage` per frame index**: two reads of one frame hand back the same object, which is what
    /// lets a consumer tell "the frame I already hold" from a new one by identity.
    func latestImage() -> (index: Int, image: CGImage)? {
        slotLock.lock()
        defer { slotLock.unlock() }
        guard let buffer = latestBuffer else { return nil }
        if let cached = cachedImage, cached.index == latestIndex { return cached }
        var image: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        guard status == noErr, let image else { return nil }
        cachedImage = (latestIndex, image)
        return (latestIndex, image)
    }

    // MARK: - Decoding (queue-confined)

    private func decode(accessUnit: Data, presentationTime: CMTime) {
        let nals = Self.splitAnnexB(accessUnit)
        guard !nals.isEmpty else { return }

        var parameterSetsChanged = false
        var slices: [Data] = []
        var hasIDR = false
        for nal in nals {
            guard let first = nal.first else { continue }
            switch NALType(rawValue: first & 0x1F) {
            case .sps:
                if sps != nal { sps = nal; parameterSetsChanged = true }
            case .pps:
                if pps != nal { pps = nal; parameterSetsChanged = true }
            case .sliceIDR:
                hasIDR = true
                slices.append(nal)
            case .sliceNonIDR:
                slices.append(nal)
            case .sei, .aud, .none:
                continue
            }
        }

        if parameterSetsChanged, let sps, let pps {
            rebuildSession(sps: sps, pps: pps)
        }
        guard let session, let formatDescription else { return }
        guard !slices.isEmpty else { return }

        if hasIDR {
            awaitingKeyframe = false
            needsKeyframeReported = false
        } else if awaitingKeyframe {
            reportNeedsKeyframe()
            return
        }

        guard let sample = Self.makeSampleBuffer(slices: slices, format: formatDescription,
                                                 presentationTime: presentationTime) else {
            return
        }
        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &infoFlags
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard let self else { return }
            if status == noErr, let imageBuffer {
                self.publish(imageBuffer)
            } else {
                self.noteDecodeError()
            }
        }
        if status != noErr {
            noteDecodeError()
        }
    }

    /// Runs on VideoToolbox's callback thread: put the frame in the slot and say so.
    private func publish(_ buffer: CVPixelBuffer) {
        slotLock.lock()
        latestBuffer = buffer
        latestIndex += 1
        decodedCount += 1
        slotLock.unlock()
        onFrame?()
    }

    private func noteDecodeError() {
        slotLock.lock()
        errorCount += 1
        slotLock.unlock()
        // Back onto the queue: the callback thread must not touch queue-confined state.
        queue.async { [weak self] in
            guard let self else { return }
            self.awaitingKeyframe = true
            self.reportNeedsKeyframe()
        }
    }

    private func reportNeedsKeyframe() {
        guard !needsKeyframeReported else { return }
        needsKeyframeReported = true
        onNeedsKeyframe?()
    }

    private func rebuildSession(sps: Data, pps: Data) {
        tearDownSession()
        formatDescription = nil
        var description: CMVideoFormatDescription?
        let status: OSStatus = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let pointers: [UnsafePointer<UInt8>] = [
                    spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                    ppsBytes.bindMemory(to: UInt8.self).baseAddress!,
                ]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2,
                    parameterSetPointers: pointers, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &description)
            }
        }
        guard status == noErr, let description else { return }
        formatDescription = description

        // BGRA so `VTCreateCGImageFromCVPixelBuffer` is a straight wrap rather than a colour
        // conversion, and so a later `CVMetalTextureCache` path (STREAM.md §8) gets a single-plane
        // texture. The decoder pays the YUV→RGB conversion once per frame on its own thread.
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var created: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault, formatDescription: description,
            decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil, decompressionSessionOut: &created)
        guard sessionStatus == noErr, let created else { return }
        VTSessionSetProperty(created, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = created
        // A new session has no reference picture; the IDR that carried these parameter sets is in
        // this same access unit, so this is cleared again a few lines down the caller.
        awaitingKeyframe = true
    }

    private func tearDownSession() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }

    // MARK: - Byte-stream helpers (pure, static, tested)

    /// Splits an Annex-B byte stream into its NAL units, start codes removed. Accepts both the
    /// three- and four-byte start code; a trailing zero before a four-byte code belongs to the
    /// code, not to the NAL before it.
    static func splitAnnexB(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [Int] = []
        var i = 0
        let n = bytes.count
        while i + 2 < n {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                starts.append(i + 3)
                i += 3
            } else {
                i += 1
            }
        }
        guard !starts.isEmpty else { return [] }
        var nals: [Data] = []
        for (k, start) in starts.enumerated() {
            var end = k + 1 < starts.count ? starts[k + 1] - 3 : n
            // The zero of a four-byte start code trails the previous NAL; strip it. Also any
            // trailing zero bytes (trailing_zero_8bits), which are not part of the NAL either.
            while end > start, bytes[end - 1] == 0 { end -= 1 }
            if end > start { nals.append(Data(bytes[start ..< end])) }
        }
        return nals
    }

    /// The NALs as one AVCC access unit: a four-byte big-endian length before each.
    static func avcc(_ nals: [Data]) -> Data {
        var out = Data(capacity: nals.reduce(0) { $0 + 4 + $1.count })
        for nal in nals {
            let length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: length) { out.append(contentsOf: $0) }
            out.append(nal)
        }
        return out
    }

    private static func makeSampleBuffer(slices: [Data], format: CMVideoFormatDescription,
                                         presentationTime: CMTime) -> CMSampleBuffer? {
        let avccData = avcc(slices)
        var blockBuffer: CMBlockBuffer?
        let count = avccData.count
        // A malloc'd copy owned by the block buffer: `CMBlockBufferCreateWithMemoryBlock` with a
        // nil block allocates and the bytes are copied in with `CMBlockBufferReplaceDataBytes`.
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: count, flags: 0, blockBufferOut: &blockBuffer)
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        status = avccData.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer,
                                          offsetIntoDestination: 0, dataLength: count)
        }
        guard status == kCMBlockBufferNoErr else { return nil }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: presentationTime,
                                        decodeTimeStamp: .invalid)
        var sizes = [count]
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sizes, sampleBufferOut: &sample)
        guard status == noErr else { return nil }
        return sample
    }
}
