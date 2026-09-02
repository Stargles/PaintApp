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

    private func store(ceiling: Int = FrameBakeStore.defaultByteCeiling) -> FrameBakeStore {
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
        return FrameBakeStore.image(fromBGRA: bytes, width: side, height: side, bytesPerRow: side * 4)!
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
    func testARealCompositedFrameRoundTripsByteForByte() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true),
              let composited = recipe.composite() else {
            return XCTFail("The zoo must composite.")
        }
        let key = FrameBakeKey(recipe: recipe, renderResolution: .full,
                               maskTuningGeneration: 0, backend: .coreGraphics)
        let store = store()
        guard case .success = store.store(composited, for: key) else {
            return XCTFail("The write must succeed into a fresh temp root.")
        }
        guard let loaded = store.load(key) else { return XCTFail("The frame just written must load.") }

        XCTAssertEqual(loaded.width, composited.width)
        XCTAssertEqual(loaded.height, composited.height)
        XCTAssertEqual(bgra(loaded), bgra(composited), "BGRA premultiplied-first must survive the round trip.")
        XCTAssertEqual(CanvasFixture.rgbaBytes(loaded), CanvasFixture.rgbaBytes(composited),
                       "RGBA read back independently — this is the assertion a channel swap fails.")
    }

    /// The file's own shape: the header is 64 bytes, it starts `PBK1`, and it carries the key it was
    /// written for.
    func testTheHeaderIsSixtyFourBytesAndNamesItsKey() {
        let key = syntheticKey(0x11)
        let store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        guard let file = try? Data(contentsOf: store.url(for: key)) else { return XCTFail("No file.") }

        XCTAssertGreaterThan(file.count, FrameBakeStore.headerBytes)
        XCTAssertEqual(Array(file.prefix(4)), FrameBakeStore.magic)
        XCTAssertEqual(file.subdata(in: 32..<64), key.digest, "The digest is the freshness guarantee.")
        XCTAssertEqual(Array(file.subdata(in: 28..<32)), [0, 0, 0, 0], "The reserved word must be zero.")
    }

    // MARK: - The raw fallback

    /// **An encoder must never make a file bigger than the pixels.** Noise does not compress, so the
    /// flag bit comes back clear and the payload is the raw bytes verbatim.
    func testIncompressibleContentIsStoredRawWithTheFlagClear() {
        let image = noiseImage(256)
        let key = syntheticKey(0x22)
        let store = store()
        guard case .success(let size) = store.store(image, for: key) else { return XCTFail("Write failed.") }

        guard let file = try? Data(contentsOf: store.url(for: key)) else { return XCTFail("No file.") }
        let flags = UInt16(file[6]) | (UInt16(file[7]) << 8)
        XCTAssertEqual(flags & FrameBakeStore.flagCompressed, 0,
                       "Noise does not compress, so the payload must be stored raw.")

        let rawPixels = 256 * 256 * 4
        XCTAssertEqual(size, FrameBakeStore.headerBytes + rawPixels,
                       "A raw file is exactly the pixels plus one header — never more.")
        XCTAssertEqual(store.load(key).flatMap { bgra($0) }, bgra(image),
                       "The raw branch must round-trip too, not only the compressed one.")
    }

    /// The flat-colour case takes the other branch, which is the branch the whole format choice
    /// rests on.
    func testFlatColourIsStoredCompressed() {
        let key = syntheticKey(0x23)
        let store = store()
        XCTAssertEqual(store.store(flatColourImage(), for: key).isSuccess, true)
        guard let file = try? Data(contentsOf: store.url(for: key)) else { return XCTFail("No file.") }
        let flags = UInt16(file[6]) | (UInt16(file[7]) << 8)
        XCTAssertEqual(flags & FrameBakeStore.flagCompressed, FrameBakeStore.flagCompressed)
        XCTAssertLessThan(file.count, 512 * 512 * 4,
                          "Flat colour is runs, and runs are what LZ4 is for.")
    }

    // MARK: - The ratios §3.5 asked to be measured rather than expected

    /// §3.5 says *"the anime ratio is expected high (MEASURE it … before trusting a number)"*. This
    /// is the headless half of that measurement — a synthetic flat-colour frame and a synthetic
    /// noise frame, printed rather than asserted, because the number is evidence and not a contract.
    /// The device measurement on the owner's own document is still owed.
    func testTheCompressionRatiosAreMeasuredAndPrinted() {
        func ratio(_ image: CGImage, _ label: String) -> Double {
            guard let pixels = FrameBakeStore.bgraBytes(image) else { XCTFail("Unreadable."); return 0 }
            let raw = pixels.bytes.count
            let stored = FrameBakeStore.compress(pixels.bytes)?.count ?? raw
            let ratio = Double(raw) / Double(stored)
            print("BAKE-RATIO \(label): \(raw) B raw → \(stored) B stored, ratio \(String(format: "%.2f", ratio))x")
            return ratio
        }
        let flat = ratio(flatColourImage(), "flat colour 512²")
        let noise = ratio(noiseImage(), "noise 512²")
        XCTAssertGreaterThan(flat, 2, "Flat colour must at least halve, or the format choice is wrong.")
        XCTAssertLessThan(noise, 1.05, "Noise must not compress; that is what the raw fallback is for.")
    }

    // MARK: - Rejection is a miss, never a picture

    private func corrupt(_ store: FrameBakeStore, _ key: FrameBakeKey, _ edit: (inout Data) -> Void) {
        guard var file = try? Data(contentsOf: store.url(for: key)) else { return XCTFail("No file.") }
        edit(&file)
        try? file.write(to: store.url(for: key))
    }

    func testAWrongMagicIsAMiss() {
        let key = syntheticKey(0x31), store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        corrupt(store, key) { $0[0] = 0x58 }
        XCTAssertNil(store.load(key))
    }

    func testAWrongFormatVersionIsAMiss() {
        let key = syntheticKey(0x32), store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        corrupt(store, key) { $0[4] = $0[4] &+ 1 }
        XCTAssertNil(store.load(key))
    }

    /// **The one that matters most.** A file whose digest names another key is exactly the stale
    /// frame §3.3 says can never be shown as fresh, and the header check is what makes that
    /// mechanical rather than a promise.
    func testAFileWhoseDigestNamesAnotherKeyIsAMiss() {
        let key = syntheticKey(0x33), store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        corrupt(store, key) { $0[40] = $0[40] &+ 1 }
        XCTAssertNil(store.load(key), "A digest mismatch must be a miss and never a picture.")
    }

    func testATruncatedFileIsAMiss() {
        let key = syntheticKey(0x34), store = store()
        XCTAssertEqual(store.store(flatColourImage(64), for: key).isSuccess, true)
        corrupt(store, key) { $0 = $0.prefix($0.count / 2) }
        XCTAssertNil(store.load(key))
    }

    /// A payload that survives every header check and is then garbage — the case the length checks
    /// cannot catch and the decoder has to.
    func testACorruptPayloadIsAMissAndNotACrash() {
        let key = syntheticKey(0x35), store = store()
        XCTAssertEqual(store.store(flatColourImage(128), for: key).isSuccess, true)
        corrupt(store, key) { file in
            for i in FrameBakeStore.headerBytes..<file.count { file[i] = 0xFF }
        }
        XCTAssertNil(store.load(key))
    }

    func testAZeroLengthFileIsAMiss() {
        let key = syntheticKey(0x36), store = store()
        try? Data().write(to: store.url(for: key))
        XCTAssertNil(store.load(key))
    }

    func testAKeyWithNoFileIsAMiss() {
        XCTAssertNil(store().load(syntheticKey(0x37)))
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
        XCTAssertLessThanOrEqual(store.totalBytes, store.byteCeiling)
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
        XCTAssertNil(store.load(syntheticKey(0x81)))
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
