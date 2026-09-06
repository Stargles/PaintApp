import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Export (RENDER.md §3.9)
//
// **This file composites nothing, and that is the feature.** RENDER §2.1: *"A background baker that
// composites frames to disk, and an export that reads those files. Export re-renders nothing."*
// Every stage before this one — the bake key, the LZ4 store, the chunked and striped compositors,
// the scheduler — exists so that the code below can be a `for` loop over files. Nothing here
// reaches `Compositor`, `ChunkedCompositor`, `StripedCompositor` or `FrameRecipe`; the only pixel
// source is `DecodedFrame`, which is what came out of the store.
//
// What *is* here is the two conversions that a container needs and the frame store does not do:
// premultiplied BGRA into an opaque video frame, and premultiplied BGRA into an un-premultiplied
// PNG. Both are byte-exact and both have a pixel test, because a premultiplied buffer handed to a
// consumer expecting straight alpha is the classic silent defect — soft edges come back with dark
// fringes and nothing errors.

/// Namespace for the pure half of export: which frames, and what the bytes become.
///
/// Every member is a free function over values, so the whole of it runs headless in the logic tier
/// with no canvas, no baker and no simulator UI.
enum FrameExport {

    // MARK: - How long is this?

    /// The frames a video export covers.
    ///
    /// **`playbackStartFrame...playbackEndFrame`, which is what pressing play would show** — and
    /// that choice is between three different answers the model already gives, none of which is
    /// interchangeable with another:
    ///
    ///  - **`contentEndFrame` is right about content and blind to intent.** It is where the drawing
    ///    ends, and it is what `playbackEndFrame` falls back to when no loop marker is set. But an
    ///    artist who has placed loop markers has said *this is my shot*, and `playbackEndFrame`
    ///    already reads them.
    ///  - So the answer is the pair of playback bounds, which resolves to `0...contentEndFrame - 1`
    ///    with no markers and to the marked range with them. **The artist exports what they were
    ///    watching**, and there is one account of "how long is this" rather than a second one here.
    ///
    /// There used to be a third candidate, `CanvasManager.sceneFrameCount`, and it was wrong: a
    /// stored high-water mark that only ever rose, so a two-frame animation reported 12 and an export
    /// driven by it shipped ten frames of empty track. It is gone (TODO 50) and the two above are all
    /// there is.
    ///
    /// It is then clamped into `0..<contentEndFrame`, which is not belt and braces: `BakeQueue`'s
    /// universe is exactly that range and `markDirty` silently drops anything outside it, so a
    /// frame past the end of the scene could be asked for and never baked — an export that waits
    /// forever, and a playhead parked out there is an ordinary thing. Clamping here makes that
    /// unreachable rather than merely unlikely.
    ///
    /// Nil when the document lays out no frames at all.
    static func frameRange(playbackStart: Int,
                           playbackEnd: Int,
                           contentEndFrame: Int) -> ClosedRange<Int>? {
        guard contentEndFrame > 0 else { return nil }
        let ceiling = contentEndFrame - 1
        let low = min(max(min(playbackStart, playbackEnd), 0), ceiling)
        let high = min(max(max(playbackStart, playbackEnd), low), ceiling)
        return low...high
    }

    // MARK: - Colour and alpha

    /// One decoded frame as **opaque** BGRA: the same bytes, with the alpha channel forced to 255.
    ///
    /// ## Why the colour channels are not touched, and why that is exactly right rather than lazy
    ///
    /// The store holds BGRA **premultiplied**. H.264 carries no alpha (§3.9), so a frame with any
    /// transparency in it has to be composited over *something* before it is encoded, and the
    /// choice of that something is the only decision here.
    ///
    /// Source-over onto an opaque backdrop is `out = src.rgb + (1 - src.a) · backdrop` when `src`
    /// is premultiplied. Take the backdrop to be **black** and the second term vanishes: `out =
    /// src.rgb`, exactly, with no arithmetic, no division and no rounding. **Premultiplied BGRA
    /// reinterpreted as opaque BGRA is already the frame composited over black.** So the conversion
    /// is one byte per pixel and it is exact, which is the property that matters — an
    /// un-premultiply here (`c · 255 / a`) would round every soft edge for no gain, since the
    /// encoder is about to throw the alpha away regardless.
    ///
    /// **When the paper is visible — the default — this is unobservable**: every pixel of the
    /// composite is already `a == 255` and forcing it changes nothing at all. It is only reachable
    /// with the paper hidden, which is the artist asking for transparency in a container that has
    /// none, and black is the honest answer there.
    ///
    /// The alpha byte is forced rather than left alone because the same buffer is read back by
    /// `AVAssetReader` as `kCVPixelFormatType_32BGRA` in the tests, and a channel the codec ignores
    /// must not be the reason a pixel assertion passes or fails. It also states the over-black
    /// claim in the bytes instead of leaving it to the encoder's discretion.
    ///
    /// Nil when the frame's own dimensions and buffer disagree — a truncated store file.
    static func opaqueBGRA(_ frame: DecodedFrame) -> Data? {
        guard frame.width > 0, frame.height > 0, frame.bytesPerRow >= frame.width * 4,
              frame.pixels.count >= frame.bytesPerRow * frame.height else { return nil }
        var out = frame.pixels
        out.withUnsafeMutableBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<frame.height {
                let row = base + y * frame.bytesPerRow
                for x in 0..<frame.width { row[x * 4 + 3] = 255 }
            }
        }
        return out
    }

    /// One decoded frame as tightly packed, **un-premultiplied** RGBA — what PNG stores.
    ///
    /// ## Two conversions in one pass, and the second is the one that goes wrong quietly
    ///
    /// The store's layout is B, G, R, A in memory with the colour premultiplied. PNG is R, G, B, A
    /// with the colour **straight**. Reordering is obvious and self-announcing: get it wrong and
    /// the picture is blue where it should be red. Un-premultiplying is neither — write the
    /// premultiplied bytes into a file that claims straight alpha and every fully opaque pixel is
    /// still perfect, so the whole picture looks right except that soft edges and translucent ink
    /// are darkened toward black. That is a defect nobody sees on a screenshot and everybody sees
    /// when the frame is laid over a light background, which is what a PNG with alpha is *for*.
    ///
    /// `c · 255 / a`, rounded to nearest and clamped: `a` is the exact reciprocal of what was
    /// multiplied in, so an opaque pixel is unchanged bit for bit, and the clamp catches the
    /// pathological case of a stored `c > a` (which premultiplication cannot produce but a corrupt
    /// file can). `a == 0` is a pixel with no colour at all; PNG stores 0 there, and the choice is
    /// unobservable through the alpha channel.
    ///
    /// Nil on the same disagreement `opaqueBGRA` refuses.
    static func unpremultipliedRGBA(_ frame: DecodedFrame) -> Data? {
        guard frame.width > 0, frame.height > 0, frame.bytesPerRow >= frame.width * 4,
              frame.pixels.count >= frame.bytesPerRow * frame.height else { return nil }
        var out = Data(count: frame.width * frame.height * 4)
        out.withUnsafeMutableBytes { destination in
            frame.pixels.withUnsafeBytes { source in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else { return }
                for y in 0..<frame.height {
                    let inRow = src + y * frame.bytesPerRow
                    let outRow = dst + y * frame.width * 4
                    for x in 0..<frame.width {
                        let b = inRow[x * 4 + 0], g = inRow[x * 4 + 1]
                        let r = inRow[x * 4 + 2], a = inRow[x * 4 + 3]
                        outRow[x * 4 + 0] = straighten(r, a)
                        outRow[x * 4 + 1] = straighten(g, a)
                        outRow[x * 4 + 2] = straighten(b, a)
                        outRow[x * 4 + 3] = a
                    }
                }
            }
        }
        return out
    }

    /// One premultiplied channel back to straight. Rounded to nearest, clamped, and 0 where the
    /// pixel has no coverage.
    private static func straighten(_ channel: UInt8, _ alpha: UInt8) -> UInt8 {
        guard alpha > 0 else { return 0 }
        guard alpha < 255 else { return channel }
        let value = (Int(channel) * 255 + Int(alpha) / 2) / Int(alpha)
        return UInt8(min(value, 255))
    }

    /// One decoded frame as PNG bytes, with alpha.
    ///
    /// **The `CGImage` is built over the un-premultiplied buffer above with
    /// `CGImageAlphaInfo.last`, not handed to ImageIO premultiplied.** ImageIO does un-premultiply
    /// on its way into a PNG, but that is a property of a framework rather than of this file, and
    /// it is invisible when it stops being true: the failure mode is a slightly dark fringe, not an
    /// error. Doing the arithmetic here makes it something a test can read a byte of.
    ///
    /// `CGImage` accepts un-premultiplied alpha from a data provider (unlike `CGBitmapContext`,
    /// whose supported-format list does not include it) — which is why this route is a provider and
    /// never a context.
    static func pngData(_ frame: DecodedFrame) -> Data? {
        guard let straight = unpremultipliedRGBA(frame) else { return nil }
        guard let provider = CGDataProvider(data: straight as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let image = CGImage(width: frame.width, height: frame.height,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: frame.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString,
                                                                 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - Names

    /// A filename stem safe on every filesystem this app reaches, built from a document name.
    ///
    /// Deliberately conservative — letters, digits, space, dash and underscore survive and
    /// everything else becomes `-` — because the result is handed to the share sheet and can end up
    /// on a Windows volume, in a mail attachment, or in a URL. Empty in, or nothing left after the
    /// filter, gives `Animation`.
    static func safeStem(_ name: String) -> String {
        let kept = name.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            if scalar == " " || scalar == "-" || scalar == "_" { return Character(scalar) }
            return "-"
        }
        let trimmed = String(kept).trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
        return trimmed.isEmpty ? "Animation" : String(trimmed.prefix(60))
    }
}

// MARK: - The video container

/// Writes decoded baked frames into an H.264 `.mp4` (RENDER §3.9), one frame at a time.
///
/// **Not `@MainActor` and never called from it.** Every method here does canvas-area work — a
/// per-row copy into a `CVPixelBuffer` and then the encoder — and §3.1's whole rule is that nothing
/// proportional to canvas area runs on the main thread. `FrameExportSession` owns one of these on
/// its own queue.
///
/// ## Why an `AVAssetWriter` and not a frame-sequence trick
///
/// §2.7 leaves container and codec to the session, and §3.9 already picked: H.264 in `.mp4` at the
/// document's fps, no alpha. That is the format every phone, editor and web page reads. The one
/// thing this class refuses to do is *lie* about it: when VideoToolbox declines a size — and it
/// will, well below the 16383² canvas maximum — the error comes back naming the size rather than
/// being papered over by a silent downscale, which §2.12 forbids in the strongest terms it has.
final class VideoFrameWriter {

    /// What can go wrong, in the artist's terms rather than in `AVFoundation`'s.
    enum Failure: Error, Equatable {
        /// The writer would not start — almost always the pixel dimensions, since VideoToolbox has
        /// a hard ceiling well below this app's canvas maximum.
        case couldNotStart(String)
        /// A frame would not encode.
        case couldNotAppend(frame: Int)
        /// A frame's stored bytes do not describe a picture of the size the movie was opened at.
        case wrongFrameSize(expected: CGSize, got: CGSize)
        /// The file would not close.
        case couldNotFinish(String)
        /// No pixel buffer pool — the adaptor refused the format.
        case noPixelBuffer
    }

    let url: URL
    let size: CGSize
    let fps: Int

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var started = false
    private var appended = 0

    /// How many frames have been written.
    var frameCount: Int { appended }

    /// - Parameters:
    ///   - url: where the `.mp4` goes. Overwritten if it exists.
    ///   - size: the frame size, in pixels. §2.8 makes this the Render Resolution knob's own size,
    ///     which is whatever the store's frames are — it is read off the first decoded frame rather
    ///     than recomputed, so the movie cannot disagree with the pixels going into it.
    ///   - fps: the document's frame rate.
    init(url: URL, size: CGSize, fps: Int) throws {
        self.url = url
        self.size = size
        self.fps = max(fps, 1)
        try? FileManager.default.removeItem(at: url)
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw Failure.couldNotStart(error.localizedDescription)
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width.rounded()),
            AVVideoHeightKey: Int(size.height.rounded())
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        // False, and it must be: this is a file-to-file transcode with no clock in it. Real-time
        // mode lets the encoder drop frames to keep up, which for an export is data loss.
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width.rounded()),
                kCVPixelBufferHeightKey as String: Int(size.height.rounded())
            ])
        guard writer.canAdd(input) else {
            throw Failure.couldNotStart("The encoder refused a \(Int(size.width))×\(Int(size.height)) movie.")
        }
        writer.add(input)
    }

    /// Appends one frame at `index` frames from the start.
    ///
    /// The presentation time is `index / fps` as an exact rational (`CMTime(value: index,
    /// timescale: fps)`), never a `Double`: at 24 fps a `Double` seconds value accumulates a
    /// rounding error that shows up as a duration one frame short on a long export.
    func append(_ frame: DecodedFrame, at index: Int) throws {
        let expected = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard CGFloat(frame.width) == expected.width, CGFloat(frame.height) == expected.height else {
            throw Failure.wrongFrameSize(expected: expected,
                                         got: CGSize(width: frame.width, height: frame.height))
        }
        if !started {
            guard writer.startWriting() else {
                throw Failure.couldNotStart(writer.error?.localizedDescription
                                            ?? "The encoder refused a \(frame.width)×\(frame.height) movie.")
            }
            writer.startSession(atSourceTime: .zero)
            started = true
        }
        guard let opaque = FrameExport.opaqueBGRA(frame) else {
            throw Failure.wrongFrameSize(expected: expected,
                                         got: CGSize(width: frame.width, height: frame.height))
        }
        guard let pool = adaptor.pixelBufferPool else { throw Failure.noPixelBuffer }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let pixelBuffer = buffer else { throw Failure.noPixelBuffer }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { throw Failure.noPixelBuffer }
        // Row by row, because the pool's stride is its own business — it is aligned up to whatever
        // the hardware wants and is routinely wider than `width * 4`. A single memcpy of the whole
        // buffer produces a picture that shears progressively down the frame.
        let destinationStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        opaque.withUnsafeBytes { source in
            guard let src = source.bindMemory(to: UInt8.self).baseAddress else { return }
            let dst = base.assumingMemoryBound(to: UInt8.self)
            let rowBytes = frame.width * 4
            for y in 0..<frame.height {
                memcpy(dst + y * destinationStride, src + y * frame.bytesPerRow, rowBytes)
            }
        }

        // `expectsMediaDataInRealTime == false` still does not promise the input is ready on the
        // first ask — the encoder has a bounded queue. Spin on the flag rather than dropping the
        // frame, which is what a real-time writer would do.
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }
        let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
        guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
            throw Failure.couldNotAppend(frame: index)
        }
        appended += 1
    }

    /// Closes the file. Blocks until the writer is done, which is what a caller on its own queue
    /// wants and what the logic tier can assert against.
    func finish() throws {
        guard started else { throw Failure.couldNotFinish("No frames were written.") }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed {
            throw Failure.couldNotFinish(writer.error?.localizedDescription ?? "The movie would not close.")
        }
    }
}
