import XCTest
import AVFoundation
import CoreGraphics
import ImageIO
import Photos
import UIKit

/// RENDER.md §5 stage 6's pin on the **pure** half of export: which frames, what the bytes become,
/// and what the two containers actually hold when they are read back.
///
/// **Every assertion here reads a byte out of a file that was written**, rather than a value the
/// code under test also computed. The premultiplication tests in particular are written that way on
/// purpose: a premultiplied buffer stored in a container that claims straight alpha is the classic
/// silent defect — every opaque pixel is still perfect and only soft edges darken — so an assertion
/// that compared this file's own conversion against itself would pass with the conversion deleted.
/// `testPNGStoresStraightColourRatherThanPremultiplied` decodes the PNG back through ImageIO and
/// normalises by **the layout ImageIO reports**, so it is measuring the file and not this suite's
/// idea of the file.
@MainActor
final class FrameExportLogicTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameExportLogicTests-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A frame of one repeated premultiplied BGRA pixel. Bytes in memory are B, G, R, A — which is
    /// what `FrameBakeStore.bgraBytes` writes and what `DecodedFrame` documents.
    private func frame(width: Int = 4, height: Int = 4,
                       b: UInt8, g: UInt8, r: UInt8, a: UInt8) -> DecodedFrame {
        var pixels = Data(count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4 + 0] = b
            pixels[i * 4 + 1] = g
            pixels[i * 4 + 2] = r
            pixels[i * 4 + 3] = a
        }
        return DecodedFrame(width: width, height: height, pixels: pixels)
    }

    /// A frame of one repeated opaque grey. Greys are used for the movie fixtures deliberately: an
    /// H.264 round trip goes through BT.709 YUV with 4:2:0 chroma, so a saturated colour comes back
    /// shifted by more than a tolerance worth asserting, while luma survives closely.
    private func greyFrame(_ level: UInt8, width: Int = 32, height: Int = 32) -> DecodedFrame {
        frame(width: width, height: height, b: level, g: level, r: level, a: 255)
    }

    // MARK: - How long is this? (§3.9, and the two answers the model gives)

    /// **The export covers what pressing play would show, not the columns the ruler draws.** The
    /// track is laid out two screenfuls past wherever the artist has scrolled
    /// (`TimelineTrackView.Coordinator.displayedFrameCount`), and an export driven by *that* would
    /// ship frames of empty track — the exact bug `contentEndFrame` was introduced to fix for
    /// playback. The `contentEndFrame: 12` here is the document's own length and only clamps.
    func testTheExportRangeIsThePlaybackBoundsAndNotTheLaidOutTrack() {
        let range = FrameExport.frameRange(playbackStart: 0, playbackEnd: 4, contentEndFrame: 12)
        XCTAssertEqual(range, 0...4,
                       "The export covers what playback would show, not the twelve columns the ruler draws.")
    }

    /// Loop markers are intent: an artist who set them said *this is my shot*, and
    /// `playbackStartFrame`/`playbackEndFrame` already read them, so there is one account of the
    /// answer rather than a second one inside export.
    func testLoopMarkersAreTheExportRangeWhenTheArtistHasSetThem() {
        XCTAssertEqual(FrameExport.frameRange(playbackStart: 5, playbackEnd: 9, contentEndFrame: 30),
                       5...9)
    }

    /// **The clamp is not belt and braces.** `BakeQueue`'s universe is `0..<frameCount` and
    /// `markDirty` silently drops anything outside it, so a frame past the laid-out track could be
    /// asked for and never baked — an export that waits for ever rather than one that errors.
    func testTheExportRangeIsClampedIntoTheLaidOutTrack() {
        XCTAssertEqual(FrameExport.frameRange(playbackStart: -3, playbackEnd: 40, contentEndFrame: 12),
                       0...11)
    }

    func testADocumentWithNoFramesHasNothingToExport() {
        XCTAssertNil(FrameExport.frameRange(playbackStart: 0, playbackEnd: 0, contentEndFrame: 0))
    }

    // MARK: - Colour and alpha: the video side

    /// **Premultiplied BGRA reinterpreted as opaque BGRA is already the frame composited over
    /// black**, which is why the colour channels are not touched: source-over onto an opaque
    /// backdrop is `src.rgb + (1 - src.a) · backdrop`, and at `backdrop == 0` the second term
    /// vanishes exactly. H.264 carries no alpha (§3.9), so *something* has to be composited under a
    /// translucent frame, and black is the one choice that costs no arithmetic and rounds nothing.
    func testOpaqueBGRAKeepsThePremultipliedColourAndForcesAlpha() throws {
        let half = frame(b: 0, g: 0, r: 128, a: 128)
        let out = try XCTUnwrap(FrameExport.opaqueBGRA(half))
        XCTAssertEqual([out[0], out[1], out[2], out[3]], [0, 0, 128, 255],
                       "Red at half coverage over black is half red, opaque.")
    }

    /// With the paper visible — the default — every pixel is already opaque, so the conversion is
    /// the identity and the choice of backdrop is unobservable. Worth its own test because it is the
    /// case the artist is actually in.
    func testAnOpaqueFrameIsUnchangedByTheVideoConversion() throws {
        let opaque = frame(b: 10, g: 20, r: 30, a: 255)
        let out = try XCTUnwrap(FrameExport.opaqueBGRA(opaque))
        XCTAssertEqual([out[0], out[1], out[2], out[3]], [10, 20, 30, 255])
    }

    // MARK: - Colour and alpha: the PNG side

    /// Two conversions in one pass, and only one of them announces itself when it is wrong.
    /// Reordering B,G,R,A to R,G,B,A is loud — get it wrong and the picture is blue. Un-premultiplying
    /// is silent: every opaque pixel survives and only soft edges darken toward black.
    func testUnpremultipliedRGBAStraightensTheColourAndReordersIt() throws {
        let half = frame(b: 0, g: 0, r: 128, a: 128)
        let out = try XCTUnwrap(FrameExport.unpremultipliedRGBA(half))
        XCTAssertEqual([out[0], out[1], out[2], out[3]], [255, 0, 0, 128],
                       "128 stored at half coverage is a straight 255 — full red, half transparent.")
    }

    /// `a == 255` is the exact reciprocal of multiplying by one, so an opaque pixel must come back
    /// bit for bit. If it does not, the arithmetic is rounding where it has no business rounding.
    func testAnOpaquePixelSurvivesTheStraightenBitForBit() throws {
        let opaque = frame(b: 10, g: 20, r: 30, a: 255)
        let out = try XCTUnwrap(FrameExport.unpremultipliedRGBA(opaque))
        XCTAssertEqual([out[0], out[1], out[2], out[3]], [30, 20, 10, 255])
    }

    /// **The decisive one, and the one written to fail if `pngData` handed ImageIO the store's own
    /// premultiplied bytes.** The file is decoded back through ImageIO and the sample is normalised
    /// by whatever layout ImageIO *reports*, so this measures the bytes in the file rather than this
    /// suite's expectation of them. A premultiplied-as-straight PNG reads back 128 where 255 belongs
    /// — the dark fringe, as a number.
    func testPNGStoresStraightColourRatherThanPremultiplied() throws {
        let half = frame(b: 0, g: 0, r: 128, a: 128)
        let png = try XCTUnwrap(FrameExport.pngData(half), "The PNG encoder refused the frame.")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 4)

        let sample = try XCTUnwrap(Self.firstPixelAsStraightRGBA(image))
        XCTAssertEqual(sample.a, 128, "The alpha channel must survive the round trip.")
        XCTAssertEqual(sample.r, 255, accuracy: 2,
                       "Straight red is 255. Reading 128 here is the premultiplied bytes written "
                       + "into a container that claims straight alpha — the dark-fringe defect.")
        XCTAssertEqual(sample.g, 0, accuracy: 2)
        XCTAssertEqual(sample.b, 0, accuracy: 2)
    }

    /// A pixel with no coverage has no colour, and PNG stores zeroes there. Stated so the choice is
    /// a decision rather than an accident of the divide-by-zero guard.
    func testAFullyTransparentPixelStoresNoColour() throws {
        let clear = frame(b: 0, g: 0, r: 0, a: 0)
        let out = try XCTUnwrap(FrameExport.unpremultipliedRGBA(clear))
        XCTAssertEqual([out[0], out[1], out[2], out[3]], [0, 0, 0, 0])
    }

    // MARK: - The video container

    /// **An `AVAssetWriter` run, read back with an `AVAssetReader`** — §5's instruction, and it is
    /// the only way to know the movie holds what it was handed. Three frames, three grey levels, in
    /// order: the count proves nothing was dropped and the per-frame samples prove the presentation
    /// times put them in the order they were appended rather than merely in the file.
    func testAMovieRoundTripsItsFrameCountAndItsFramesInOrder() async throws {
        let url = directory.appendingPathComponent("three.mp4")
        let levels: [UInt8] = [60, 130, 200]
        let writer = try VideoFrameWriter(url: url, size: CGSize(width: 32, height: 32), fps: 24)
        for (index, level) in levels.enumerated() {
            try writer.append(greyFrame(level), at: index)
        }
        try writer.finish()
        XCTAssertEqual(writer.frameCount, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let samples = try await Self.readGreyLevels(url)
        XCTAssertEqual(samples.count, 3, "Every appended frame must be in the file.")
        for (index, level) in levels.enumerated() {
            XCTAssertEqual(Double(samples[index]), Double(level), accuracy: 14,
                           "Frame \(index) should be the grey it was handed, within one H.264 "
                           + "BT.709 round trip.")
        }
    }

    /// **Odd pixel dimensions, because the knob produces them.** Three quarters of 2049 is 1537, and
    /// H.264 codes in 16×16 macroblocks — the encoder is supposed to carry a frame-cropping
    /// rectangle for the remainder, and this asserts it does rather than assuming it. If it ever
    /// stops, the failure is a movie one or two pixels wider than the artwork, which is a wrong file
    /// with no error.
    func testAnOddSizedMovieComesBackAtItsOwnDimensions() async throws {
        let url = directory.appendingPathComponent("odd.mp4")
        let writer = try VideoFrameWriter(url: url, size: CGSize(width: 63, height: 33), fps: 24)
        try writer.append(greyFrame(120, width: 63, height: 33), at: 0)
        try writer.finish()

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 63, accuracy: 0.5)
        XCTAssertEqual(size.height, 33, accuracy: 0.5)
    }

    /// A frame that is not the size the movie was opened at is refused rather than stretched. The
    /// case is an edit landing mid-export that moves the render size; silently scaling it would be a
    /// video that changes shape halfway through, with no error.
    func testAFrameOfTheWrongSizeIsRefused() throws {
        let url = directory.appendingPathComponent("mismatch.mp4")
        let writer = try VideoFrameWriter(url: url, size: CGSize(width: 32, height: 32), fps: 24)
        XCTAssertThrowsError(try writer.append(greyFrame(100, width: 16, height: 16), at: 0)) { error in
            guard case VideoFrameWriter.Failure.wrongFrameSize = error else {
                return XCTFail("Expected a size refusal, got \(error).")
            }
        }
    }

    // MARK: - The padding cut (TODO (127))

    /// A 4×3 frame whose pixel `i` is the four bytes `i, i, i, 255` — so a byte read back says which
    /// source pixel it came from. `bytesPerRow` is wider than the pixels, as a texture readback may
    /// legitimately be: a cut that assumed `width * 4` would shear.
    private func numberedFrame(paddedRowBytes: Int = 4 * 4 + 8) -> DecodedFrame {
        var pixels = Data(count: paddedRowBytes * 3)
        for y in 0..<3 {
            for x in 0..<4 {
                let i = UInt8(y * 4 + x)
                for c in 0..<3 { pixels[y * paddedRowBytes + x * 4 + c] = i }
                pixels[y * paddedRowBytes + x * 4 + 3] = 255
            }
        }
        return DecodedFrame(width: 4, height: 3, bytesPerRow: paddedRowBytes, pixels: pixels)
    }

    /// **The cut takes the pixels it names and no others**, read as the number of the source pixel each
    /// destination pixel came from — over a strided source, which is where a sheared copy would show.
    func testACutFrameHoldsExactlyTheNamedPixels() throws {
        let cut = try XCTUnwrap(numberedFrame().cropped(to: CGRect(x: 1, y: 1, width: 2, height: 2)))
        XCTAssertEqual([cut.width, cut.height, cut.bytesPerRow], [2, 2, 8], "Tightly packed at the cut's size.")
        let source = (0..<4).map { cut.pixels[$0 * 4] }
        XCTAssertEqual(source, [5, 6, 9, 10], "Row 1 columns 1–2, then row 2 columns 1–2.")
    }

    /// Cutting nothing copies nothing — the export path calls this on every frame whether or not the
    /// artist asked for the padding, and the common case must not cost a frame-sized copy.
    func testCuttingTheWholeFrameReturnsTheFrameItself() throws {
        let whole = numberedFrame()
        let cut = try XCTUnwrap(whole.cropped(to: CGRect(x: 0, y: 0, width: 4, height: 3)))
        XCTAssertEqual(cut.pixels, whole.pixels)
        XCTAssertEqual(cut.bytesPerRow, whole.bytesPerRow, "No repack: the same frame, not a copy of it.")
    }

    /// A rect that is not wholly inside the frame, or not whole pixels, is a refusal. Clamping it would
    /// hand back a picture of a different size than the one a movie was opened for.
    func testACutOutsideTheFrameOrBetweenPixelsIsRefused() {
        let frame = numberedFrame()
        XCTAssertNil(frame.cropped(to: CGRect(x: 3, y: 0, width: 2, height: 2)), "Reaches past the right edge.")
        XCTAssertNil(frame.cropped(to: CGRect(x: -1, y: 0, width: 2, height: 2)), "Starts before the left edge.")
        XCTAssertNil(frame.cropped(to: CGRect(x: 0, y: 0, width: 0, height: 2)), "Empty.")
        XCTAssertNil(frame.cropped(to: CGRect(x: 0.5, y: 0, width: 2, height: 2)), "Between pixels.")
    }

    // MARK: - What a file is, and where Photos files it (TODO (126))

    /// **One classification for every destination**: the stream's `FILE_BEGIN` kind and Save to Photos
    /// read the same table, so a file cannot be an image to one and nothing to the other. The two an
    /// export produces, then the spellings Photos also takes, then what it has no word for.
    func testAFilesKindComesFromItsExtensionAndIsCaseBlind() {
        XCTAssertEqual(FrameExport.Kind(pathExtension: "png"), .image)
        XCTAssertEqual(FrameExport.Kind(pathExtension: "PNG"), .image)
        XCTAssertEqual(FrameExport.Kind(pathExtension: "mp4"), .video)
        for ext in ["jpg", "jpeg", "heic", "gif"] {
            XCTAssertEqual(FrameExport.Kind(pathExtension: ext), .image, ext)
        }
        for ext in ["mov", "m4v"] {
            XCTAssertEqual(FrameExport.Kind(pathExtension: ext), .video, ext)
        }
        XCTAssertEqual(FrameExport.Kind(pathExtension: "txt"), .other)
        XCTAssertEqual(FrameExport.Kind(pathExtension: ""), .other)
        XCTAssertEqual(FrameExport.Kind.image.rawValue, "image", "The raw values are the stream protocol's own words.")
        XCTAssertEqual(FrameExport.Kind.video.rawValue, "video")
    }

    /// Photos files a still as a photo and a movie as a video, and refuses anything else outright — a
    /// file with no resource type never reaches the library as something it is not.
    func testPhotosFilesAStillAsAPhotoAndAMovieAsAVideo() {
        XCTAssertEqual(PhotoLibraryDestination.resourceType(for: .image), .photo)
        XCTAssertEqual(PhotoLibraryDestination.resourceType(for: .video), .video)
        XCTAssertNil(PhotoLibraryDestination.resourceType(for: .other))
    }

    // MARK: - Names

    func testAFilenameStemSurvivesADocumentNameWithPunctuationInIt() {
        XCTAssertEqual(FrameExport.safeStem("My Scene / v2"), "My Scene - v2")
        XCTAssertEqual(FrameExport.safeStem("   "), "Animation")
        XCTAssertEqual(FrameExport.safeStem(""), "Animation")
    }

    // MARK: - Readback helpers

    /// The image's first pixel as **straight** RGBA, normalised by the layout the image itself
    /// reports. This is what makes the PNG test a measurement of the file: if ImageIO hands back a
    /// premultiplied image, this un-premultiplies it before asserting, so the assertion is about the
    /// colour the file encodes and not about the layout it happens to arrive in.
    private static func firstPixelAsStraightRGBA(_ image: CGImage)
        -> (r: Double, g: Double, b: Double, a: Double)? {
        guard let data = image.dataProvider?.data as Data?, data.count >= 4 else { return nil }
        let info = image.alphaInfo
        let little = image.bitmapInfo.contains(.byteOrder32Little)
        var c0 = Double(data[0]), c1 = Double(data[1]), c2 = Double(data[2]), c3 = Double(data[3])
        if little { swap(&c0, &c3); swap(&c1, &c2) }   // reverse the word back to big-endian order

        let r: Double, g: Double, b: Double, a: Double
        switch info {
        case .premultipliedFirst, .first, .noneSkipFirst:
            a = c0; r = c1; g = c2; b = c3
        default:
            r = c0; g = c1; b = c2; a = c3
        }
        guard a > 0 else { return (0, 0, 0, 0) }
        let premultiplied = (info == .premultipliedFirst || info == .premultipliedLast)
        let scale = premultiplied ? 255 / a : 1
        return (r * scale, g * scale, b * scale, a)
    }

    /// Every frame of the movie, as the grey level of its top-left pixel.
    private static func readGreyLevels(_ url: URL) async throws -> [UInt8] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()

        var levels: [UInt8] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                levels.append(base.assumingMemoryBound(to: UInt8.self)[0])
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        return levels
    }
}
