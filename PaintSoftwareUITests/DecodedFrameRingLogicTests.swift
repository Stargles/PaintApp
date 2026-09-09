import XCTest
import CoreGraphics

/// `DecodedFrame` and `DecodedFrameRing` — the byte-budgeted resident cache the playback tick reads
/// from (RENDER §3.5), and the BGRA premultiplied-first frame it holds.
///
/// The claims worth pinning are the ones that are not obvious from the signatures: eviction is LRU
/// **by last access** and not by insertion, a frame bigger than the whole budget is refused rather
/// than admitted over the ceiling, lowering the budget evicts *now*, the pixel layout is the one
/// Core Animation wants rather than the one that merely round-trips, and every operation is safe to
/// call from two threads at once.
final class DecodedFrameRingLogicTests: XCTestCase {

    /// A frame of a known size, filled with a recognisable byte so a mix-up is legible.
    private func frame(bytes: Int, fill: UInt8 = 0x7F) -> DecodedFrame {
        // Sized as one row so `bytes` is exact; `makeImage` is not the point of these.
        DecodedFrame(width: bytes / 4, height: 1, bytesPerRow: bytes,
                     pixels: Data(repeating: fill, count: bytes))
    }

    // MARK: - Budget accounting

    func testAnEmptyRingHoldsNothing() {
        let ring = DecodedFrameRing(byteBudget: 1024)
        XCTAssertEqual(ring.byteCount, 0)
        XCTAssertEqual(ring.count, 0)
        XCTAssertNil(ring.frame(for: "anything"))
    }

    func testInsertingAccountsForTheBytes() {
        let ring = DecodedFrameRing(byteBudget: 4096)
        XCTAssertTrue(ring.insert(frame(bytes: 1024), for: "a"))
        XCTAssertEqual(ring.byteCount, 1024)
        XCTAssertTrue(ring.insert(frame(bytes: 512), for: "b"))
        XCTAssertEqual(ring.byteCount, 1536)
        XCTAssertEqual(ring.count, 2)
    }

    /// Re-inserting the same digest replaces rather than double-counting. Content addressing means
    /// this is the same pixels arriving twice, which happens whenever two frames of a hold are
    /// decoded before either is read.
    func testReinsertingTheSameDigestDoesNotDoubleCountTheBytes() {
        let ring = DecodedFrameRing(byteBudget: 4096)
        ring.insert(frame(bytes: 1024), for: "a")
        ring.insert(frame(bytes: 1024), for: "a")
        XCTAssertEqual(ring.byteCount, 1024)
        XCTAssertEqual(ring.count, 1)
    }

    func testADigestThatWasNeverInsertedMisses() {
        let ring = DecodedFrameRing(byteBudget: 4096)
        ring.insert(frame(bytes: 256), for: "a")
        XCTAssertNil(ring.frame(for: "b"))
        XCTAssertNil(ring.frame(for: ""))
        XCTAssertFalse(ring.contains("b"))
    }

    // MARK: - Eviction is LRU by last access

    func testATightBudgetEvictsTheOldestToMakeRoom() {
        let ring = DecodedFrameRing(byteBudget: 300)
        ring.insert(frame(bytes: 100), for: "a")
        ring.insert(frame(bytes: 100), for: "b")
        ring.insert(frame(bytes: 100), for: "c")
        XCTAssertEqual(ring.byteCount, 300)
        ring.insert(frame(bytes: 100), for: "d")
        XCTAssertEqual(ring.byteCount, 300)
        XCTAssertNil(ring.frame(for: "a"), "the oldest should have gone")
        XCTAssertNotNil(ring.frame(for: "b"))
        XCTAssertNotNil(ring.frame(for: "c"))
        XCTAssertNotNil(ring.frame(for: "d"))
    }

    /// The claim in the doc comment: **last access**, not insertion order. Reading "a" makes it the
    /// newest, so the next eviction takes "b" — which is what makes LRU mean "furthest behind the
    /// playhead" for a scheduler that reads in playhead order.
    func testReadingAFrameSavesItFromTheNextEviction() {
        let ring = DecodedFrameRing(byteBudget: 300)
        ring.insert(frame(bytes: 100), for: "a")
        ring.insert(frame(bytes: 100), for: "b")
        ring.insert(frame(bytes: 100), for: "c")
        XCTAssertNotNil(ring.frame(for: "a"))          // "a" is now the most recently used
        ring.insert(frame(bytes: 100), for: "d")
        XCTAssertNotNil(ring.frame(for: "a"), "the frame just read must not be the victim")
        XCTAssertNil(ring.frame(for: "b"), "the least recently used should have gone")
    }

    /// `contains` deliberately does not count as an access, so the timeline asking what is warm
    /// cannot change what gets evicted.
    func testContainsDoesNotTouchRecency() {
        let ring = DecodedFrameRing(byteBudget: 300)
        ring.insert(frame(bytes: 100), for: "a")
        ring.insert(frame(bytes: 100), for: "b")
        ring.insert(frame(bytes: 100), for: "c")
        XCTAssertTrue(ring.contains("a"))
        ring.insert(frame(bytes: 100), for: "d")
        XCTAssertFalse(ring.contains("a"), "contains must not have saved it")
    }

    func testOneLargeInsertEvictsAsManyAsItNeeds() {
        let ring = DecodedFrameRing(byteBudget: 400)
        for digest in ["a", "b", "c", "d"] { ring.insert(frame(bytes: 100), for: digest) }
        XCTAssertEqual(ring.count, 4)
        XCTAssertTrue(ring.insert(frame(bytes: 350), for: "big"))
        XCTAssertEqual(ring.byteCount, 350)
        XCTAssertEqual(ring.count, 1, "three of the four had to go, and the fourth as well")
        XCTAssertNotNil(ring.frame(for: "big"))
    }

    // MARK: - The ceiling is never exceeded

    /// A frame larger than the whole budget is refused. The store is the truth and the ring is an
    /// optimisation, so the cost of refusing is a slow decode; the cost of admitting it is the
    /// out-of-memory this whole feature exists to avoid.
    func testAFrameLargerThanTheWholeBudgetIsRefused() {
        let ring = DecodedFrameRing(byteBudget: 1000)
        XCTAssertFalse(ring.insert(frame(bytes: 1001), for: "huge"))
        XCTAssertEqual(ring.byteCount, 0)
        XCTAssertNil(ring.frame(for: "huge"))
    }

    /// And refusing must not be destructive: what is already resident stays.
    func testARefusedFrameDoesNotEvictWhatIsResident() {
        let ring = DecodedFrameRing(byteBudget: 1000)
        ring.insert(frame(bytes: 400), for: "a")
        ring.insert(frame(bytes: 400), for: "b")
        XCTAssertFalse(ring.insert(frame(bytes: 5000), for: "huge"))
        XCTAssertEqual(ring.byteCount, 800)
        XCTAssertNotNil(ring.frame(for: "a"))
        XCTAssertNotNil(ring.frame(for: "b"))
    }

    func testAFrameExactlyTheBudgetIsAccepted() {
        let ring = DecodedFrameRing(byteBudget: 1000)
        XCTAssertTrue(ring.insert(frame(bytes: 1000), for: "exact"))
        XCTAssertEqual(ring.byteCount, 1000)
    }

    func testAZeroBudgetRingHoldsNothingAndStillWorks() {
        let ring = DecodedFrameRing(byteBudget: 0)
        XCTAssertFalse(ring.insert(frame(bytes: 4), for: "a"))
        XCTAssertEqual(ring.byteCount, 0)
        XCTAssertNil(ring.frame(for: "a"))
    }

    // MARK: - Changing the budget

    func testLoweringTheBudgetEvictsImmediately() {
        let ring = DecodedFrameRing(byteBudget: 1000)
        for digest in ["a", "b", "c", "d"] { ring.insert(frame(bytes: 200), for: digest) }
        XCTAssertEqual(ring.byteCount, 800)
        ring.byteBudget = 400
        XCTAssertEqual(ring.byteCount, 400, "the eviction must happen on the set, not at the next insert")
        XCTAssertNil(ring.frame(for: "a"))
        XCTAssertNil(ring.frame(for: "b"))
        XCTAssertNotNil(ring.frame(for: "c"))
        XCTAssertNotNil(ring.frame(for: "d"))
    }

    func testLoweringTheBudgetToZeroEmptiesTheRing() {
        let ring = DecodedFrameRing(byteBudget: 1000)
        ring.insert(frame(bytes: 400), for: "a")
        ring.byteBudget = 0
        XCTAssertEqual(ring.byteCount, 0)
        XCTAssertEqual(ring.count, 0)
    }

    func testRaisingTheBudgetEvictsNothingAndAdmitsMore() {
        let ring = DecodedFrameRing(byteBudget: 400)
        ring.insert(frame(bytes: 400), for: "a")
        ring.byteBudget = 1200
        XCTAssertNotNil(ring.frame(for: "a"))
        XCTAssertTrue(ring.insert(frame(bytes: 800), for: "b"))
        XCTAssertEqual(ring.byteCount, 1200)
    }

    func testANegativeBudgetIsClampedToZero() {
        let ring = DecodedFrameRing(byteBudget: -5)
        XCTAssertEqual(ring.byteBudget, 0)
        ring.byteBudget = -100
        XCTAssertEqual(ring.byteBudget, 0)
    }

    func testRemoveAllDropsEverythingAndTheAccountingWithIt() {
        let ring = DecodedFrameRing(byteBudget: 4096)
        for digest in ["a", "b", "c"] { ring.insert(frame(bytes: 256), for: digest) }
        ring.removeAll()
        XCTAssertEqual(ring.byteCount, 0)
        XCTAssertEqual(ring.count, 0)
        XCTAssertNil(ring.frame(for: "a"))
        XCTAssertTrue(ring.insert(frame(bytes: 256), for: "a"), "and the ring still works after")
    }

    // MARK: - `DecodedFrame.makeImage`

    /// One pixel: BGRA premultiplied-first, byte order little — so the bytes on the wire are
    /// B, G, R, A and `[0, 0, 255, 255]` is opaque red. Drawn into a known RGBA context and read
    /// back, which is what proves the *interpretation* rather than merely the round trip.
    func testMakeImageReadsTheBytesAsBGRA() throws {
        let red = DecodedFrame(width: 1, height: 1, pixels: Data([0, 0, 255, 255]))
        let image = try XCTUnwrap(red.makeImage())
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
        let rgba = try XCTUnwrap(rgbaBytes(of: image))
        XCTAssertEqual(rgba, [255, 0, 0, 255], "BGRA 0,0,255,255 is opaque red")
    }

    /// Two pixels side by side, so a channel swizzle *and* a row/column mix-up both show. Left red,
    /// right green.
    func testMakeImageKeepsPixelsInOrderAcrossARow() throws {
        let pixels = Data([0, 0, 255, 255,      // BGRA: red
                           0, 255, 0, 255])     // BGRA: green
        let frame = DecodedFrame(width: 2, height: 1, pixels: pixels)
        let image = try XCTUnwrap(frame.makeImage())
        let rgba = try XCTUnwrap(rgbaBytes(of: image))
        XCTAssertEqual(rgba, [255, 0, 0, 255, 0, 255, 0, 255])
    }

    /// A padded stride is honoured rather than assumed away: the four bytes after each row are
    /// never read as pixels. Without `bytesPerRow` being carried, the second pixel would come out
    /// of the padding.
    func testMakeImageHonoursAPaddedRowStride() throws {
        let pixels = Data([0, 0, 255, 255,      // BGRA: red
                           1, 2, 3, 4,          // padding, must not be seen
                           0, 255, 0, 255,      // BGRA: green
                           5, 6, 7, 8])         // padding
        let frame = DecodedFrame(width: 1, height: 2, bytesPerRow: 8, pixels: pixels)
        let image = try XCTUnwrap(frame.makeImage())
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.bytesPerRow, 8)
        let rgba = try XCTUnwrap(rgbaBytes(of: image))
        // Top row first, in both buffers: `CGContext.draw` renders the image upright into the
        // context's own bitmap, so row 0 of the source is row 0 of the readback. (MEASURED — the
        // bottom-left-origin coordinate space is about *drawing* coordinates, not about which end
        // of the buffer the top row lives at, and this test asserted the flip until it ran.)
        XCTAssertEqual(rgba, [255, 0, 0, 255, 0, 255, 0, 255])
    }

    func testMakeImageCarriesTheDimensions() throws {
        let frame = DecodedFrame(width: 7, height: 5, pixels: Data(repeating: 0, count: 7 * 5 * 4))
        let image = try XCTUnwrap(frame.makeImage())
        XCTAssertEqual(image.width, 7)
        XCTAssertEqual(image.height, 5)
        XCTAssertEqual(image.bitsPerPixel, 32)
        XCTAssertEqual(image.bytesPerRow, 28)
    }

    /// A truncated buffer is what a corrupt or half-written store file arrives as. Nil, not a
    /// `CGImage` reading past its own pixels.
    func testMakeImageRefusesABufferTooSmallForItsDimensions() {
        XCTAssertNil(DecodedFrame(width: 4, height: 4, pixels: Data(repeating: 0, count: 32)).makeImage())
        XCTAssertNil(DecodedFrame(width: 0, height: 4, pixels: Data(repeating: 0, count: 64)).makeImage())
        XCTAssertNil(DecodedFrame(width: 4, height: 0, pixels: Data(repeating: 0, count: 64)).makeImage())
        XCTAssertNil(DecodedFrame(width: 4, height: 4, bytesPerRow: 8,
                                  pixels: Data(repeating: 0, count: 64)).makeImage(),
                     "a stride narrower than the row is not a frame")
    }

    /// A frame taken out of the ring is a value, so the image can be built with no lock held and
    /// the entry it came from can be evicted underneath without disturbing it.
    func testAFrameSurvivesTheRingEvictingIt() throws {
        let ring = DecodedFrameRing(byteBudget: 8)
        ring.insert(DecodedFrame(width: 1, height: 1, pixels: Data([0, 0, 255, 255])), for: "a")
        let taken = try XCTUnwrap(ring.frame(for: "a"))
        ring.removeAll()
        let image = try XCTUnwrap(taken.makeImage())
        XCTAssertEqual(try XCTUnwrap(rgbaBytes(of: image)), [255, 0, 0, 255])
    }

    // MARK: - Thread safety

    /// The baker inserts on its own queue while the display thread reads. Without the lock this
    /// mutates a `Dictionary` and an `Array` from eight threads at once, which corrupts or traps;
    /// with it, the two invariants below hold at the end of every run.
    func testConcurrentInsertsAndReadsKeepTheRingConsistent() {
        let frameBytes = 1024
        let ring = DecodedFrameRing(byteBudget: frameBytes * 16)
        let payload = frame(bytes: frameBytes)

        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for round in 0..<250 {
                let digest = "w\(worker)-\(round)"
                ring.insert(payload, for: digest)
                _ = ring.frame(for: digest)
                _ = ring.frame(for: "w\((worker + 1) % 8)-\(round)")
                _ = ring.contains(digest)
                _ = ring.byteCount
            }
        }

        XCTAssertLessThanOrEqual(ring.byteCount, frameBytes * 16, "the ceiling must have held throughout")
        // Every frame is the same size, so the byte account and the entry count must agree exactly.
        // A lost subtraction or a double-add — the shape a race takes here — breaks this.
        XCTAssertEqual(ring.byteCount, ring.count * frameBytes)
    }

    /// The budget being changed while the baker is inserting is the memory-pressure case, and it
    /// is the one that reaches `evictLocked` from two directions at once.
    func testConcurrentBudgetChangesAndInsertsKeepTheAccountingHonest() {
        let frameBytes = 512
        let ring = DecodedFrameRing(byteBudget: frameBytes * 8)
        let payload = frame(bytes: frameBytes)

        DispatchQueue.concurrentPerform(iterations: 6) { worker in
            for round in 0..<200 {
                if worker == 0 {
                    ring.byteBudget = frameBytes * (1 + round % 8)
                } else {
                    ring.insert(payload, for: "w\(worker)-\(round)")
                    _ = ring.frame(for: "w\(worker)-\(round / 2)")
                }
            }
        }

        XCTAssertEqual(ring.byteCount, ring.count * frameBytes)
        XCTAssertLessThanOrEqual(ring.byteCount, ring.byteBudget)
    }

    func testConcurrentRemoveAllDoesNotLeaveBytesBehind() {
        let ring = DecodedFrameRing(byteBudget: 64 * 1024)
        let payload = frame(bytes: 256)
        DispatchQueue.concurrentPerform(iterations: 6) { worker in
            for round in 0..<200 {
                if worker == 0 && round % 20 == 0 {
                    ring.removeAll()
                } else {
                    ring.insert(payload, for: "w\(worker)-\(round)")
                }
            }
        }
        ring.removeAll()
        XCTAssertEqual(ring.byteCount, 0)
        XCTAssertEqual(ring.count, 0)
    }

    // MARK: - Helpers

    /// The image's pixels as tightly packed RGBA premultiplied-last, which is a *different* layout
    /// from the one under test — so agreement is evidence about the bitmap info rather than about
    /// the bytes having survived a copy.
    private func rgbaBytes(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    // MARK: - The budget the document gets, and why a one-frame ring is worthless

    /// **`CanvasManager.frameRingByteBudget(forFrameBytes:)`, pinned at the owner's own device
    /// budget**, which is what makes this a statement about their iPad rather than about this Mac.
    ///
    /// MEASURED on the owner's iPad 9 in Release: with the old fixed 96 MiB constant, a two-frame
    /// 4096² document played at **15.9 fps with 0 ring hits against 83 misses**, one LZ4 decode on
    /// the display thread per flip. With the budget below it is **24.0 fps with 155 hits and 0
    /// misses**. The rule is the fix; this is the rule.
    func testTheRingBudgetHoldsTwoFramesUntilTwoFramesStopFittingTheDevice() {
        let iPad9 = 192_663_552            // `CompositorBudget.textureBudgetBytes` read off the device
        CompositorBudget.budgetOverrideBytes = iPad9
        defer { CompositorBudget.budgetOverrideBytes = nil }

        let minimum = CanvasManager.minimumFrameRingByteBudget
        func budget(_ edge: Int) -> Int {
            CanvasManager.frameRingByteBudget(forFrameBytes: edge * edge * 4)
        }

        // 2048²: two frames are 33.6 MB, far under the minimum, so the minimum stands and the ring
        // holds six. This is the size the owner draws at and it never had the defect.
        XCTAssertEqual(budget(2048), minimum,
                       "a small frame leaves the floor alone — two of them are well inside it")

        // 4096², the canvas in the owner's own trace: two frames are 134.2 MB, over the 96 MiB floor
        // and inside the device's 192 MB, so the budget is exactly the flip's working set.
        XCTAssertEqual(budget(4096), 2 * 4096 * 4096 * 4,
                       "the flip's working set is two frames and the ring must hold both")
        XCTAssertGreaterThan(budget(4096), minimum,
                             "premise: this is the regime the old constant got wrong")

        // 6000², `maxCanvasExtent`: two frames are 288 MB against a 192 MB device budget, so the
        // ring is switched off rather than left holding one. Holding one is strictly worse — the
        // flip misses either way and 144 MB is spent on nothing. MEASURED: asking for 288 MB here
        // killed the app with signal 9 on the owner's iPad.
        XCTAssertEqual(budget(6000), 0,
                       "two frames do not fit this device, so the ring holds none rather than one")

        // The boundary is a property of the rule rather than of any canvas: exactly at the ceiling
        // the ring is on, one byte past it the ring is off.
        XCTAssertEqual(CanvasManager.frameRingByteBudget(forFrameBytes: iPad9 / 2), iPad9 / 2 * 2,
                       "two frames that exactly fit are held")
        XCTAssertEqual(CanvasManager.frameRingByteBudget(forFrameBytes: iPad9 / 2 + 1), 0,
                       "one byte more and there is no useful ring to have")
    }

    /// **The behaviour the rule exists for, played out against the real ring**: a two-frame loop
    /// alternating A, B, A, B… misses *every single access* on a ring that holds one, and hits every
    /// one after the first lap on a ring that holds two.
    ///
    /// The one-frame arm is the control and it is the whole argument for the `0` above: it is not
    /// that a small ring helps a little, it is that it helps not at all while holding a frame's
    /// worth of a 3 GB device. Scaled down to bytes because the claim is about the *ratio* of budget
    /// to frame, which is what `DecodedFrameRing` is written in.
    func testAOneFrameRingMissesEveryFlipOfATwoFrameLoopAndATwoFrameRingMissesOnlyTheFirstLap() {
        let frameBytes = 1024
        let a = frame(bytes: frameBytes, fill: 0x11)
        let b = frame(bytes: frameBytes, fill: 0x22)

        func play(budget: Int, laps: Int) -> (hits: Int, misses: Int) {
            let ring = DecodedFrameRing(byteBudget: budget)
            var hits = 0, misses = 0
            for _ in 0..<laps {
                for (digest, decoded) in [("A", a), ("B", b)] {
                    if ring.frame(for: digest) != nil {
                        hits += 1
                    } else {
                        misses += 1
                        ring.insert(decoded, for: digest)
                    }
                }
            }
            return (hits, misses)
        }

        let one = play(budget: frameBytes, laps: 10)
        XCTAssertEqual(one.hits, 0, "a ring that holds one frame hits nothing at all on a two-frame loop")
        XCTAssertEqual(one.misses, 20, "every access decodes — which is the 0/83 measured on the device")

        let two = play(budget: 2 * frameBytes, laps: 10)
        XCTAssertEqual(two.misses, 2, "only the first lap of each frame")
        XCTAssertEqual(two.hits, 18, "and everything after it is resident")
    }
}
