import XCTest
import UIKit
import SwiftUI

/// RENDER.md §5 stage 4a's pin on the **store** — one LZ4 file per bake key, and the rules that keep
/// a stale or damaged one from ever being shown as a picture.
///
/// **Every rejection here is a miss, not a failure and never a crash.** §3.3's "a stale file can
/// never be shown as fresh" is mechanical rather than assumed precisely because the reader checks
/// the magic, the format version and the digest against the key it was asked for; a document whose
/// cache directory has been half-overwritten by something else has to come back as "not baked yet",
/// which costs a re-bake, rather than as somebody else's frame.
///
/// **And a write failure is a bake failure, not a document failure** (§2.10): disk full, a read-only
/// root, a frame bigger than the whole ceiling — the caller carries on and playback shows the
/// previous picture.
@MainActor
final class FrameBakeStoreLogicTests: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameBakeStoreLogicTests-" + UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        FrameBakeStore.cachesDirectoryOverride = nil
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func store(ceiling: Int = 512 * 1024 * 1024) -> FrameBakeStore {
        FrameBakeStore(root: root, byteCeiling: ceiling)
    }

    /// A digest that is 32 bytes and nothing else — the store's tests do not need a real recipe to
    /// exercise accounting or eviction, and a synthetic key keeps those tests from failing for a
    /// reason that belongs to `FrameBakeKeyLogicTests`.
    private func syntheticKey(_ seed: UInt8) -> FrameBakeKey {
        FrameBakeKey(rawDigest: Data(repeating: seed, count: 32))
    }

    /// **Flat colour, which is what §2.8 says an anime document is made of** — big uniform runs, the
    /// thing LZ4 encodes as matches.
    private func flatColourImage(_ side: Int = 512) -> CGImage {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            UIColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.15, green: 0.16, blue: 0.22, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 40, y: 60, width: 300, height: 220))
            UIColor(red: 0.86, green: 0.35, blue: 0.32, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 180, y: 200, width: 260, height: 240))
        }.cgImage!
    }

    /// **Incompressible**, from a seeded generator so the ratio printed below is reproducible.
    /// Premultiplied-first means the alpha byte comes first in memory under `byteOrder32Little`, so
    /// it is forced opaque and the three colour bytes are left random — a random alpha would produce
    /// bytes above their own alpha, which is not a state any composite can be in.
    private func noiseImage(_ side: Int = 512) -> CGImage {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt8 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = next(); bytes[i + 1] = next(); bytes[i + 2] = next()
            bytes[i + 3] = 255
        }
        // `DecodedFrame` rather than a store helper of its own: RENDER stage 4c deleted
        // `FrameBakeStore.image(fromBGRA:)` along with the `CGImage`-returning `load`, and this is
        // now the app's one spelling of "these BGRA premultiplied-first bytes, as an image".
        return DecodedFrame(width: side, height: side, pixels: Data(bytes)).makeImage()!
    }

    private func bgra(_ image: CGImage) -> [UInt8]? { FrameBakeStore.bgraBytes(image)?.bytes }

    // MARK: - Round trip

    /// **A real composited frame, byte for byte.** The zoo goes through
    /// `FrameRecipe.composite(budgetBytes:)` — stage 3's chunked whole-frame path, which is what the
    /// baker will call — and comes back out of the store identical.
    ///
    /// Compared twice, in two channel orders. BGRA is what the file holds, so that comparison alone
    /// could pass with the channels transposed on both sides; `CanvasFixture.rgbaBytes` reads
    /// premultiplied-**last** RGBA through an independent context, so a swapped R and B would show
    /// up there and only there.
    func testARealCompositedFrameRoundTripsByteForByte() throws {
        let manager = try CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true),
              let composited = recipe.composite() else {
            return XCTFail("The zoo must composite.")
        }
        let key = FrameBakeKey(recipe: recipe, renderResolution: .full, backend: .coreGraphics)
        let store = store()
        guard case .success = store.store(composited, for: key) else {
            return XCTFail("The write must succeed into a fresh temp root.")
        }
        guard let loaded = store.loadDecoded(key)?.makeImage() else {
            return XCTFail("The frame just written must load.")
        }

        XCTAssertEqual(loaded.width, composited.width)
        XCTAssertEqual(loaded.height, composited.height)
        XCTAssertEqual(bgra(loaded), bgra(composited), "BGRA premultiplied-first must survive the round trip.")
        XCTAssertEqual(CanvasFixture.rgbaBytes(loaded), CanvasFixture.rgbaBytes(composited),
                       "RGBA read back independently — this is the assertion a channel swap fails.")
    }

    /// The file's own shape: the header is 64 bytes, it starts `PBK2`, it names both levels' sizes, and
    /// it carries the key it was written for.
    func testTheHeaderIsSixtyFourBytesAndNamesItsKeyAndBothLevels() throws {
        let key = syntheticKey(0x11)
        let store = store()
        XCTAssertEqual(store.store(flatColourImage(65), for: key).isSuccess, true)
        let file = try Data(contentsOf: store.url(for: key))

        XCTAssertGreaterThan(file.count, FrameBakeStore.headerBytes)
        XCTAssertEqual(Array(file.prefix(4)), FrameBakeStore.magic)
        XCTAssertEqual(file.subdata(in: 32..<64), key.digest, "The digest is the freshness guarantee.")
        XCTAssertEqual(Array(file.subdata(in: 28..<32)), [0, 0, 0, 0], "The reserved word must be zero.")
        let header = try XCTUnwrap(BakeFile.Header.parse(file))
        XCTAssertEqual([header.fullWidth, header.fullHeight, header.halfWidth, header.halfHeight], [65, 65, 33, 33],
                       "an odd edge keeps its last half column")
    }

    // MARK: - The raw fallback

    /// **An encoder must never make a file bigger than the pixels.** Noise does not compress, so every
    /// tile comes back with the raw bit set and the payload is the raw bytes verbatim, for both levels.
    func testIncompressibleContentIsStoredRawTileForTile() throws {
        let image = noiseImage(256)
        let key = syntheticKey(0x22)
        let store = store()
        guard case .success(let size) = store.store(image, for: key) else { return XCTFail("Write failed.") }

        let file = try Data(contentsOf: store.url(for: key))
        let header = try XCTUnwrap(BakeFile.Header.parse(file))
        let directory = try XCTUnwrap(BakeFile.Directory(
            header: header, data: file.subdata(in: FrameBakeStore.headerBytes..<header.prefixBytes)))
        XCTAssertTrue(directory.entries.allSatisfy { $0 & FrameBakeStore.rawTileBit != 0 },
                      "Noise does not compress, so every tile must be stored raw.")
        XCTAssertEqual(size, header.prefixBytes + 256 * 256 * 4 + 128 * 128 * 4,
                       "A raw file is the two levels' pixels plus the header and directory — never more.")
        XCTAssertEqual(store.loadDecoded(key)?.makeImage().flatMap { bgra($0) }, bgra(image),
                       "The raw branch must round-trip too, not only the compressed one.")
    }

    /// The flat-colour case takes the other branch, which is the branch the whole format choice
    /// rests on.
    func testFlatColourIsStoredCompressed() throws {
        let key = syntheticKey(0x23)
        let store = store()
        XCTAssertEqual(store.store(flatColourImage(), for: key).isSuccess, true)
        let file = try Data(contentsOf: store.url(for: key))
        let header = try XCTUnwrap(BakeFile.Header.parse(file))
        let directory = try XCTUnwrap(BakeFile.Directory(
            header: header, data: file.subdata(in: FrameBakeStore.headerBytes..<header.prefixBytes)))
        XCTAssertTrue(directory.entries.allSatisfy { $0 & FrameBakeStore.rawTileBit == 0 }, "every tile is LZ4")
        XCTAssertLessThan(file.count, 512 * 512 * 4, "Flat colour is runs, and runs are what LZ4 is for.")
    }

    // MARK: - The ratios §3.5 asked to be measured rather than expected

    /// §3.5 says *"the anime ratio is expected high (MEASURE it … before trusting a number)"*. This
    /// is the headless half of that measurement — a synthetic flat-colour frame and a synthetic
    /// noise frame, printed rather than asserted, because the number is evidence and not a contract.
    /// The device measurement on the owner's own document is still owed.
    func testTheCompressionRatiosAreMeasuredAndPrinted() {
        func ratio(_ image: CGImage, _ label: String) -> Double {
            guard let pixels = FrameBakeStore.bgraBytes(image),
                  let file = BakeFile.encode(bgra: pixels.bytes, width: pixels.width, height: pixels.height,
                                             digest: Data(repeating: 1, count: 32)) else { XCTFail("Unreadable."); return 0 }
            let raw = pixels.bytes.count
            let ratio = Double(raw) / Double(file.count)
            print("BAKE-RATIO \(label): \(raw) B raw → \(file.count) B stored (both levels), ratio \(String(format: "%.2f", ratio))x")
            return ratio
        }
        let flat = ratio(flatColourImage(), "flat colour 512²")
        let noise = ratio(noiseImage(), "noise 512²")
        XCTAssertGreaterThan(flat, 2, "Flat colour must at least halve, or the format choice is wrong.")
        XCTAssertLessThan(noise, 0.85, "Noise does not compress, and the half level is a quarter on top: 1 / 1.25 = 0.8.")
    }

    /// **The disk limit is `min(4 GiB, 10% of free)` with 2 GiB always left**, as a pure function of what
    /// the volume has: nothing under the reserve, the reserve binding just over it, the tenth in the
    /// middle, the cap at the top.
    func testTheDiskLimitFormula() {
        let gib = 1024 * 1024 * 1024
        XCTAssertEqual(BakeDiskLimit.bytes(capacity: 2 * gib), 0, "at the reserve there is nothing to give")
        XCTAssertEqual(BakeDiskLimit.bytes(capacity: gib), 0)
        XCTAssertEqual(BakeDiskLimit.bytes(capacity: 2 * gib + gib / 10), gib / 10, "just over it, the reserve binds")
        XCTAssertEqual(BakeDiskLimit.bytes(capacity: 3 * gib), 3 * gib / 10, "a tenth in the middle")
        XCTAssertEqual(BakeDiskLimit.bytes(capacity: 20 * gib), 2 * gib)
        XCTAssertEqual(BakeDiskLimit.bytes(capacity: 400 * gib), 4 * gib, "and never more than 4 GiB")
    }

    // MARK: - Levels and tiles

    /// A frame that spans several tiles in both directions, with an edge tile smaller than the rest.
    private func gradient(width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = UInt8(truncatingIfNeeded: x * 7 + y)
                bytes[i + 1] = UInt8(truncatingIfNeeded: y * 5)
                bytes[i + 2] = UInt8(truncatingIfNeeded: x ^ y)
                bytes[i + 3] = 255
            }
        }
        return bytes
    }

    private func decodedLevel(_ store: FrameBakeStore, _ key: FrameBakeKey, _ level: BakeLevel) throws -> DecodedFrame {
        try XCTUnwrap(store.loadDecoded(key, level: level))
    }

    /// **The full level is the frame, byte for byte, across tile boundaries** — 1100×700 is 3×2 tiles with
    /// a 76-wide and a 188-tall edge, so every seam in the scatter is crossed.
    func testTheFullLevelRoundTripsAcrossTileSeams() throws {
        let (width, height) = (1100, 700)
        let pixels = gradient(width: width, height: height)
        let key = syntheticKey(0x41)
        let store = store()
        XCTAssertTrue(store.store(pixels: (pixels, width, height), for: key).isSuccess)
        let full = try decodedLevel(store, key, .full)
        XCTAssertEqual([full.width, full.height], [width, height])
        XCTAssertEqual(Array(full.pixels), pixels)
    }

    /// **The half level is the 2×2 mean of the full one, to the byte** — computed here independently of
    /// the encoder's tile loop, on a size whose half is an odd number of pixels (so the last half column
    /// averages two pixels, not four) and which crosses a half-level tile seam (1100 / 2 = 550 > 512).
    func testTheHalfLevelIsTheBoxMeanOfTheFullLevel() throws {
        let (width, height) = (1101, 701)
        let pixels = gradient(width: width, height: height)
        let key = syntheticKey(0x42)
        let store = store()
        XCTAssertTrue(store.store(pixels: (pixels, width, height), for: key).isSuccess)
        let half = try decodedLevel(store, key, .half)
        XCTAssertEqual([half.width, half.height], [551, 351])
        var wrong = 0
        for y in 0..<half.height {
            for x in 0..<half.width {
                for channel in 0..<4 {
                    var sum = 0, count = 0
                    for dy in 0..<2 where y * 2 + dy < height {
                        for dx in 0..<2 where x * 2 + dx < width {
                            sum += Int(pixels[((y * 2 + dy) * width + x * 2 + dx) * 4 + channel]); count += 1
                        }
                    }
                    let expected = UInt8((sum + count / 2) / count)
                    if half.pixels[(y * half.width + x) * 4 + channel] != expected { wrong += 1 }
                }
            }
        }
        XCTAssertEqual(wrong, 0, "every half pixel is the rounded mean of the pixels under it")
    }

    /// **A step at fit zoom reads the half level and nothing of the full one**: the bytes the read brings
    /// in are the half level's tiles, a quarter of the full level's, and the decoded frame is a quarter
    /// the size. This is the "25 MiB, not 95" of SCHEDULER_DESIGN.md §6 S2, in the units a fast test sees.
    func testReadingTheHalfLevelTouchesAQuarterOfTheBytes() throws {
        let (width, height) = (2048, 1024)
        let key = syntheticKey(0x43)
        let store = store()
        XCTAssertTrue(store.store(pixels: (noiseBytes(width * height * 4), width, height), for: key).isSuccess)
        let half = store.readSnapshot(key, level: .half), full = store.readSnapshot(key, level: .full)
        XCTAssertEqual(full.payloadBytes, width * height * 4, "premise: noise is stored raw, so the level is its pixels")
        XCTAssertEqual(half.payloadBytes, width * height, "the half level is a quarter of the full level's bytes")
        let decoded = try XCTUnwrap(FrameBakeStore.decode(half).frame)
        XCTAssertEqual(decoded.byteCount, width * height, "and decodes to a quarter of the memory")
    }

    private func noiseBytes(_ count: Int) -> [UInt8] {
        var state: UInt64 = 0x2545F4914F6CDD1D
        return (0..<count).map { _ in
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return UInt8(truncatingIfNeeded: state >> 24)
        }
    }

    /// **A file damaged in the half level only is still rejected whole** — the directory is checked
    /// against the file's length, so a truncation anywhere is a miss for both levels.
    func testATruncationInTheHalfLevelRejectsBothLevels() throws {
        let key = syntheticKey(0x44)
        let store = store()
        XCTAssertTrue(store.store(flatColourImage(700), for: key).isSuccess)
        let file = try Data(contentsOf: store.url(for: key))
        try file.dropLast(5).write(to: store.url(for: key))
        XCTAssertNil(store.loadDecoded(key, level: .full))
        XCTAssertFalse(store.contains(key), "a rejected file is dropped from the inventory")
    }

    // MARK: - Rejection is a miss, never a picture

    private func corrupt(_ store: FrameBakeStore, _ key: FrameBakeKey, _ edit: (inout Data) -> Void) {
        guard var file = try? Data(contentsOf: store.url(for: key)) else { return XCTFail("No file.") }
        edit(&file)
        try? file.write(to: store.url(for: key))
    }

    func testRejectingOneUnreadableBakePreservesOtherDrawnFilesAndAccounting() throws {
        let store = store()
        let rejected = syntheticKey(31), retained = syntheticKey(32)
        let picture = noiseImage(8)
        guard case .success = store.store(flatColourImage(8), for: rejected),
              case .success(let retainedSize) = store.store(picture, for: retained) else {
            return XCTFail("Both tiny files must be written before rejecting one.")
        }
        try Data([0x50]).write(to: store.url(for: rejected))
        XCTAssertTrue(store.read(rejected).isUnavailable)
        XCTAssertFalse(store.contains(rejected))
        XCTAssertTrue(store.contains(retained))
        XCTAssertEqual(store.totalBytes, retainedSize)
        let decoded = try XCTUnwrap(store.loadDecoded(retained))
        let image = try XCTUnwrap(decoded.makeImage())
        XCTAssertEqual(CanvasFixture.rgbaBytes(image), CanvasFixture.rgbaBytes(picture),
                       "Rejecting a disposable file must leave other drawings byte-exact.")
        XCTAssertEqual(store.totalBytes, FrameBakeStore(root: root).totalBytes,
                       "Every same-root facade must report the same retained inventory after rejection.")
    }

    func testSameRootFacadesShareAccountingAndApplyTheirRequestedWriteCaps() throws {
        let generous = FrameBakeStore(root: root, byteCeiling: 8192)
        let narrow = FrameBakeStore(root: URL(fileURLWithPath: root.path), byteCeiling: 4096)
        let image = noiseImage(16)
        let first = syntheticKey(41)
        guard case .success(let each) = generous.store(image, for: first) else {
            return XCTFail("The first tiny image must write.")
        }
        XCTAssertEqual(narrow.totalBytes, each, "A facade opened before the write sees the same authoritative bytes.")
        XCTAssertTrue(narrow.contains(first))
        XCTAssertLessThanOrEqual(3 * each, narrow.ceiling)
        XCTAssertGreaterThan(4 * each, narrow.ceiling, "Premise: the fourth write requires the narrow cap to evict.")
        for seed in UInt8(42)...43 {
            XCTAssertTrue(generous.store(image, for: syntheticKey(seed)).isSuccess)
        }
        let newest = syntheticKey(44)
        XCTAssertTrue(narrow.store(image, for: newest).isSuccess)
        XCTAssertEqual(generous.totalBytes, 3 * each)
        XCTAssertEqual(narrow.totalBytes, generous.totalBytes)
        XCTAssertLessThanOrEqual(generous.totalBytes, narrow.ceiling)
        let refused = FrameBakeStore(root: root, byteCeiling: each - 1)
        XCTAssertEqual(refused.totalBytes, generous.totalBytes,
                       "A lower requested cap does not invent a smaller private usage total.")
        guard case .failure(.exceedsCeiling) = refused.store(image, for: syntheticKey(45)) else {
            return XCTFail("A frame above this facade's cap must refuse before evicting shared files.")
        }
        XCTAssertEqual(refused.totalBytes, 3 * each)
        let decoded = try XCTUnwrap(generous.loadDecoded(newest)?.makeImage())
        XCTAssertEqual(CanvasFixture.rgbaBytes(decoded), CanvasFixture.rgbaBytes(image))
        XCTAssertEqual(narrow.totalBytes, generous.totalBytes)
    }

    func testAReleasedRootOwnerIsNotRetainedByTheDirectoryRegistry() throws {
        let key = syntheticKey(48)
        var first: FrameBakeStore? = store()
        weak var released = first
        XCTAssertTrue(first!.store(noiseImage(8), for: key).isSuccess)
        let file = first!.url(for: key)
        first = nil
        XCTAssertNil(released)
        try FileManager.default.removeItem(at: file)
        let reopened = store()
        XCTAssertEqual(reopened.totalBytes, 0,
                       "Once all directory owners are released, a new owner inventories the real files.")
        XCTAssertFalse(reopened.contains(key), "The weak directory registry cannot retain obsolete inventory forever.")
    }

    func testAnOldInvalidReadCannotDeleteAnotherFacadesGoodReplacement() throws {
        let old = FrameBakeStore(root: root), reopened = FrameBakeStore(root: root)
        let key = syntheticKey(46)
        XCTAssertTrue(old.store(flatColourImage(8), for: key).isSuccess)
        try Data([0x50]).write(to: old.url(for: key))
        // These are the real production read/decode boundaries: no product fault flag, delay or
        // fake file implementation is needed to hold an old read while a new facade writes.
        let invalidRead = old.readSnapshot(key)
        let replacement = noiseImage(16)
        guard case .success(let size) = reopened.store(replacement, for: key) else {
            return XCTFail("The new owner must replace the damaged disposable file.")
        }
        XCTAssertTrue(FrameBakeStore.decode(invalidRead).isUnavailable)
        XCTAssertTrue(old.contains(key))
        XCTAssertTrue(reopened.contains(key))
        XCTAssertEqual(old.totalBytes, size)
        XCTAssertEqual(reopened.totalBytes, size)
        let surviving = try XCTUnwrap(old.loadDecoded(key)?.makeImage())
        XCTAssertEqual(CanvasFixture.rgbaBytes(surviving), CanvasFixture.rgbaBytes(replacement),
                       "Settling old invalid bytes must preserve the replacement's actual drawing.")
    }

    func testOverflowingDimensionsRejectATinyCorrectlyKeyedHeaderBeforeDecode() throws {
        let store = store(), key = syntheticKey(47)
        XCTAssertTrue(store.store(noiseImage(8), for: key).isSuccess)
        var header = Data(try Data(contentsOf: store.url(for: key)).prefix(FrameBakeStore.headerBytes))
        header.replaceSubrange(8..<12, with: [0xff, 0xff, 0xff, 0x3f])
        header.replaceSubrange(12..<16, with: [0xff, 0xff, 0xff, 0xff])
        header.replaceSubrange(16..<20, with: [0xfc, 0xff, 0xff, 0xff])
        header.replaceSubrange(20..<24, with: [4, 0, 0, 0])
        XCTAssertEqual(header.count, 64, "The overflow fixture owns only a header, never a huge buffer.")
        XCTAssertNil(FrameBakeStore.pixelByteCount(width: 0x3fffffff, height: 0xffffffff,
                                                  bytesPerRow: 0xfffffffc))
        try header.write(to: store.url(for: key))
        XCTAssertTrue(store.read(key).isUnavailable)
        XCTAssertFalse(store.contains(key))
        XCTAssertEqual(store.totalBytes, 0)
    }

    func testAWrongMagicIsAMiss() {
        let key = syntheticKey(0x31), store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        corrupt(store, key) { $0[0] = 0x58 }
        XCTAssertNil(store.loadDecoded(key))
    }

    func testAWrongFormatVersionIsAMiss() {
        let key = syntheticKey(0x32), store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        corrupt(store, key) { $0[4] = $0[4] &+ 1 }
        XCTAssertNil(store.loadDecoded(key))
    }

    /// **The one that matters most.** A file whose digest names another key is exactly the stale
    /// frame §3.3 says can never be shown as fresh, and the header check is what makes that
    /// mechanical rather than a promise.
    func testAFileWhoseDigestNamesAnotherKeyIsAMiss() {
        let key = syntheticKey(0x33), store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        corrupt(store, key) { $0[40] = $0[40] &+ 1 }
        XCTAssertNil(store.loadDecoded(key), "A digest mismatch must be a miss and never a picture.")
    }

    func testATruncatedFileIsAMiss() {
        let key = syntheticKey(0x34), store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        corrupt(store, key) { $0 = $0.prefix($0.count / 2) }
        XCTAssertNil(store.loadDecoded(key))
    }

    /// A payload that survives every header check and is then garbage — the case the length checks
    /// cannot catch and the decoder has to.
    func testACorruptPayloadIsAMissAndNotACrash() {
        let key = syntheticKey(0x35), store = store()
        XCTAssertEqual(store.store(flatColourImage(128), for: key).isSuccess, true)
        corrupt(store, key) { file in
            // Past the directory: the header, the tile lengths and the file's size all still agree.
            let payloadStart = BakeFile.Header.parse(file)!.prefixBytes
            for i in payloadStart..<file.count { file[i] = 0xFF }
        }
        XCTAssertNil(store.loadDecoded(key))
    }

    func testAZeroLengthFileIsAMiss() {
        let key = syntheticKey(0x36), store = store()
        try? Data().write(to: store.url(for: key))
        XCTAssertNil(store.loadDecoded(key))
    }

    func testAKeyWithNoFileIsAMiss() {
        XCTAssertNil(store().loadDecoded(syntheticKey(0x37)))
        XCTAssertFalse(store().contains(syntheticKey(0x37)))
    }

    // MARK: - Accounting, purging, eviction

    func testTheStoreCountsItsOwnBytesAndReopensKnowingThem() {
        let store = store()
        XCTAssertEqual(store.totalBytes, 0)
        var expected = 0
        for seed in UInt8(1)...UInt8(3) {
            guard case .success(let size) = store.store(flatColourImage(64), for: syntheticKey(seed)) else {
                return XCTFail("Write failed.")
            }
            expected += size
        }
        XCTAssertEqual(store.totalBytes, expected)
        // Purging is explicit, so a second store opened over the same root must find the files.
        XCTAssertEqual(FrameBakeStore(root: root).totalBytes, expected,
                       "Opening a store must not wipe what is there — §2.11's purge is a call, not an `init`.")
    }

    /// Rewriting the same key replaces the file rather than double-counting it.
    func testRewritingOneKeyDoesNotDoubleCount() {
        let store = store(), key = syntheticKey(0x41)
        guard case .success(let first) = store.store(flatColourImage(64), for: key) else { return XCTFail() }
        guard case .success(let second) = store.store(flatColourImage(64), for: key) else { return XCTFail() }
        XCTAssertEqual(first, second)
        XCTAssertEqual(store.totalBytes, second)
    }

    func testPurgeAllEmptiesTheStore() {
        let store = store()
        for seed in UInt8(1)...UInt8(4) { _ = store.store(flatColourImage(64), for: syntheticKey(seed)) }
        XCTAssertGreaterThan(store.totalBytes, 0)
        store.purgeAll()
        XCTAssertEqual(store.totalBytes, 0)
        XCTAssertFalse(store.contains(syntheticKey(1)))
        XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: root.path).count, 0)
    }

    /// **§3.5's eviction policy: farthest from the playhead goes first.** Four frames, a ceiling
    /// that holds three, and the one 40 frames away is the one that dies — not the oldest, not the
    /// largest.
    func testEvictingATruncatedFarFilePreservesTheNearDrawnSibling() throws {
        for byteCount in 0...1 {
            for explicit in [false, true] {
                let subroot = root.appendingPathComponent("truncated-\(byteCount)-explicit-\(explicit)", isDirectory: true)
                let image = noiseImage(16)
                let far = syntheticKey(51), near = syntheticKey(52), incoming = syntheticKey(53)
                let measuring = FrameBakeStore(root: subroot)
                guard case .success(let each) = measuring.store(image, for: far) else {
                    return XCTFail("The fixture must measure its actual encoded size.")
                }
                let bounded = FrameBakeStore(root: subroot, byteCeiling: 2 * each)
                XCTAssertTrue(bounded.store(image, for: near).isSuccess)
                XCTAssertEqual(bounded.totalBytes, 2 * each)
                let frames = [far.fileName: Set([100]), near.fileName: Set([0])]
                try Data(repeating: 0x50, count: byteCount).write(to: bounded.url(for: far))
                if explicit {
                    XCTAssertEqual(bounded.evict(toFree: each, playhead: 0, frames: frames), byteCount,
                                   "Report actual removed bytes even when the charged size was larger.")
                    XCTAssertFalse(bounded.contains(far))
                    XCTAssertTrue(bounded.contains(near), "Releasing the far charge already restores headroom.")
                    XCTAssertEqual(bounded.totalBytes, each)
                    XCTAssertEqual(measuring.totalBytes, each)
                }
                // The other path exercises the write's own eviction directly, without pre-evicting.
                XCTAssertTrue(bounded.store(image, for: incoming, playhead: 0, frames: frames).isSuccess)
                XCTAssertFalse(bounded.contains(far))
                XCTAssertTrue(bounded.contains(near))
                XCTAssertTrue(bounded.contains(incoming))
                XCTAssertEqual(bounded.totalBytes, 2 * each)
                XCTAssertEqual(measuring.totalBytes, 2 * each)
                XCTAssertLessThanOrEqual(bounded.totalBytes, bounded.ceiling)
                let retained = try XCTUnwrap(bounded.loadDecoded(near)?.makeImage())
                XCTAssertEqual(CanvasFixture.rgbaBytes(retained), CanvasFixture.rgbaBytes(image),
                               "Near drawing survives \(byteCount)-byte truncation, explicit eviction \(explicit).")
            }
        }
    }

    func testAWriteRefusesAdmissionWhenAProtectedFilePreventsEviction() throws {
        let image = noiseImage(16), retained = syntheticKey(54), incoming = syntheticKey(55)
        let measuring = store()
        guard case .success(let each) = measuring.store(image, for: retained) else {
            return XCTFail("The tiny fixture must measure its actual encoded size.")
        }
        let bounded = FrameBakeStore(root: root, byteCeiling: each)
        let protected = bounded.url(for: retained)
        let fm = FileManager.default
        try fm.setAttributes([.immutable: true], ofItemAtPath: protected.path)
        defer {
            do { try fm.setAttributes([.immutable: false], ofItemAtPath: protected.path) }
            catch { XCTFail("Could not release the owned fixture's immutable flag: \(error)") }
        }
        XCTAssertEqual(try fm.attributesOfItem(atPath: protected.path)[.immutable] as? NSNumber, NSNumber(value: true))
        XCTAssertThrowsError(try fm.removeItem(at: protected), "Premise: this owned file cannot be evicted.")
        guard fm.fileExists(atPath: protected.path) else { return XCTFail("Protected-file premise failed.") }
        let probe = root.appendingPathComponent("writable-parent-probe")
        try Data([0x50]).write(to: probe, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: probe), Data([0x50]), "The parent still permits a new atomic file.")
        try fm.removeItem(at: probe)

        let result = bounded.store(image, for: incoming)
        XCTAssertFalse(result.isSuccess, "Failed eviction cannot admit another frame above the requested cap.")
        if case .failure(let failure) = result { XCTAssertEqual(failure, .couldNotWrite) }
        XCTAssertFalse(fm.fileExists(atPath: bounded.url(for: incoming).path))
        XCTAssertTrue(bounded.contains(retained))
        XCTAssertEqual(bounded.totalBytes, each)
        XCTAssertEqual(measuring.totalBytes, each)
        XCTAssertLessThanOrEqual(bounded.totalBytes, bounded.ceiling)
        let surviving = try XCTUnwrap(bounded.loadDecoded(retained)?.makeImage())
        XCTAssertEqual(CanvasFixture.rgbaBytes(surviving), CanvasFixture.rgbaBytes(image))
    }

    func testEvictionDropsTheFrameFarthestFromThePlayhead() {
        let image = flatColourImage(64)
        guard case .success(let each) = FrameBakeStore(root: root).store(image, for: syntheticKey(0xFF)) else {
            return XCTFail("Could not size a file.")
        }
        try? FileManager.default.removeItem(at: root)

        let store = store(ceiling: each * 3 + each / 2)
        let near = syntheticKey(0x51), mid = syntheticKey(0x52)
        let far = syntheticKey(0x53), newcomer = syntheticKey(0x54)
        let frames: [String: Set<Int>] = [
            near.fileName: [10], mid.fileName: [16], far.fileName: [50], newcomer.fileName: [11],
        ]
        for key in [near, mid, far] {
            XCTAssertEqual(store.store(image, for: key, playhead: 10, frames: frames).isSuccess, true)
        }
        XCTAssertEqual(store.store(image, for: newcomer, playhead: 10, frames: frames).isSuccess, true)

        XCTAssertTrue(store.contains(newcomer), "The frame just written must survive its own write.")
        XCTAssertFalse(store.contains(far), "The frame 40 away is the one that goes.")
        XCTAssertTrue(store.contains(near))
        XCTAssertTrue(store.contains(mid))
        XCTAssertLessThanOrEqual(store.totalBytes, store.ceiling)
    }

    /// A file no live frame names is unreachable from this document, so it goes before anything that
    /// is — even a frame at the far end of the timeline.
    func testAFileNoFrameNamesIsEvictedFirst() {
        let image = flatColourImage(64)
        guard case .success(let each) = FrameBakeStore(root: root).store(image, for: syntheticKey(0xFE)) else {
            return XCTFail("Could not size a file.")
        }
        try? FileManager.default.removeItem(at: root)

        let store = store(ceiling: each * 2 + each / 2)
        let orphan = syntheticKey(0x61), far = syntheticKey(0x62), newcomer = syntheticKey(0x63)
        let frames: [String: Set<Int>] = [far.fileName: [900], newcomer.fileName: [0]]
        _ = store.store(image, for: orphan, playhead: 0, frames: frames)
        _ = store.store(image, for: far, playhead: 0, frames: frames)
        _ = store.store(image, for: newcomer, playhead: 0, frames: frames)

        XCTAssertFalse(store.contains(orphan), "An unreachable file has infinite distance.")
        XCTAssertTrue(store.contains(far))
        XCTAssertTrue(store.contains(newcomer))
    }

    /// A hold is one file and the map says so with a set: the distance is the nearest frame that
    /// resolves to it, so a nine-frame hold under the playhead is not evicted for its last frame's
    /// distance.
    func testAHoldIsMeasuredByItsNearestFrame() {
        let image = flatColourImage(64)
        guard case .success(let each) = FrameBakeStore(root: root).store(image, for: syntheticKey(0xFD)) else {
            return XCTFail("Could not size a file.")
        }
        try? FileManager.default.removeItem(at: root)

        let store = store(ceiling: each * 2 + each / 2)
        let hold = syntheticKey(0x71), single = syntheticKey(0x72), newcomer = syntheticKey(0x73)
        let frames: [String: Set<Int>] = [
            hold.fileName: Set(20...28), single.fileName: [60], newcomer.fileName: [21],
        ]
        for key in [hold, single] { _ = store.store(image, for: key, playhead: 22, frames: frames) }
        _ = store.store(image, for: newcomer, playhead: 22, frames: frames)

        XCTAssertTrue(store.contains(hold), "The hold covers the playhead; its distance is 0, not 6.")
        XCTAssertFalse(store.contains(single))
    }

    // MARK: - Failure is a bake failure, never a document failure

    func testAWriteIntoAnUnwritableRootFailsGracefully() {
        // A *file* where the root's parent should be, so `createDirectory` and the write both fail.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameBakeStore-blocker-" + UUID().uuidString)
        try? Data([0]).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let store = FrameBakeStore(root: blocker.appendingPathComponent("bakes", isDirectory: true))
        let result = store.store(flatColourImage(64), for: syntheticKey(0x81))
        guard case .failure(let failure) = result else {
            return XCTFail("A write into an unwritable root must fail rather than claim success.")
        }
        XCTAssertEqual(failure, .couldNotWrite)
        XCTAssertEqual(store.totalBytes, 0, "A failed write must not be counted.")
        XCTAssertNil(store.loadDecoded(syntheticKey(0x81)))
    }

    func testAFrameLargerThanTheWholeCeilingIsRefusedRatherThanEvictingEverything() {
        let store = store(ceiling: 1024)
        let survivor = syntheticKey(0x91)
        // Nothing fits, so nothing is written and nothing is destroyed trying.
        let result = store.store(noiseImage(64), for: survivor)
        guard case .failure(let failure) = result else { return XCTFail("Must refuse.") }
        guard case .exceedsCeiling = failure else { return XCTFail("Wrong failure: \(failure)") }
        XCTAssertEqual(store.totalBytes, 0)
    }

    func testAKeyWhoseDigestIsTheWrongLengthIsRefused() {
        let result = store().store(flatColourImage(64), for: FrameBakeKey(rawDigest: Data([1, 2, 3])))
        guard case .failure(.malformedKey) = result else { return XCTFail("Must refuse a short digest.") }
    }

    // MARK: - The root

    /// The default root is under Caches and carries the project and the resolution, and the override
    /// seam redirects it the way `ProjectBackupManager.rootDirectoryOverride` does.
    func testTheDefaultRootIsProjectAndResolutionScopedUnderTheOverride() {
        FrameBakeStore.cachesDirectoryOverride = root
        let projectID = UUID()
        let full = FrameBakeStore.defaultRoot(projectID: projectID, renderResolution: .full)
        let half = FrameBakeStore.defaultRoot(projectID: projectID, renderResolution: .half)
        XCTAssertNotEqual(full, half)
        XCTAssertTrue(full.path.hasPrefix(root.path), "The override must redirect the whole tree.")
        XCTAssertTrue(full.path.contains(projectID.uuidString))
        XCTAssertTrue(full.path.contains("/bakes/"))
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
}
