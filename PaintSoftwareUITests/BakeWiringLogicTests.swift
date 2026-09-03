import XCTest
import UIKit
import SwiftUI

/// RENDER.md §5 stage 4d's pin on **the wiring** — the seam between the document and the baker,
/// which stages 4a–4c deliberately left unbuilt.
///
/// `FrameBakerLogicTests` owns the loop itself: which frames a change reaches, what a dedupe costs,
/// what a write failure does. This file owns the four things stage 4d decided and nothing else:
///
/// 1. **the size the bake mints at**, which is what lets the bake and the live canvas's two halves
///    share one `PixelOps.rasterize` memo — `testTheBakeMintsAtTheSizeTheLiveCanvasComposites` is
///    the one this file exists for, and the mutation MEASURED red below is the deletion of
///    `FrameBaker.recipe`'s `sizing:` argument;
/// 2. **the suspension**, so the loop does not composite the artist's frame once per dab;
/// 3. **the re-root**, so the Render Resolution knob does not leave the document baking into the
///    previous resolution's directory;
/// 4. **the ring top-up**, which is the half of §3.5's *"play never decodes on the display thread"*
///    that the loop cannot supply on its own, because playback dirties nothing.
///
/// Every fixture is on a temp `cachesDirectoryOverride` and forces `.coreGraphics` in `setUp`,
/// restoring `Compositor.defaultBackend` — not the literal — in `tearDown`, for the reason
/// `ChunkedCompositeLogicTests` writes out.
@MainActor
final class BakeWiringLogicTests: XCTestCase {

    private var caches: URL!
    private var storedResolution: String?

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        caches = FileManager.default.temporaryDirectory
            .appendingPathComponent("BakeWiringLogicTests-" + UUID().uuidString, isDirectory: true)
        FrameBakeStore.cachesDirectoryOverride = caches
        // **`CanvasManager.renderResolution` writes through to `UserDefaults` on every set**, so it
        // is process-wide state and not a property of the manager under test. This suite is the only
        // one in the repo that moves it, and the first run of it moved the *next* suite's fixtures
        // to half resolution — `FrameBakerLogicTests` composited at 32² and reported it as a
        // failure of the code under test. Exactly the trap `Compositor.backend` is restored for two
        // lines above, reached through a different door: restore what was there, not a literal.
        storedResolution = UserDefaults.standard.string(forKey: CanvasManager.renderResolutionDefaultsKey)
        // …and *pinned*, not merely restored. Every fixture below sizes a ring or a buffer in
        // frames, and the number of bytes in a frame is `liveCompositeSize` — which is the knob. A
        // suite that inherited whatever the last run of it happened to leave in this simulator's
        // container would size its ring against one resolution and its document against another; the
        // first draft of this file did exactly that and reported a 2-frame ring holding 8.
        UserDefaults.standard.set(RenderResolution.full.rawValue,
                                  forKey: CanvasManager.renderResolutionDefaultsKey)
    }

    override func tearDown() {
        if let storedResolution {
            UserDefaults.standard.set(storedResolution, forKey: CanvasManager.renderResolutionDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        }
        FrameBakeStore.cachesDirectoryOverride = nil
        try? FileManager.default.removeItem(at: caches)
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        CompositeProbe.end()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A document whose every frame is a different picture, so every frame is its own bake key —
    /// `FrameBakerLogicTests` carries the argument for why a document made of holds cannot count
    /// frames.
    private func perFrameDocument(frames: Int) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, (0..<frames).map { (start: $0, length: 1) })
        manager.sceneFrameCount = frames
        for frame in 0..<frames {
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: frame,
                                          CanvasFixture.solidImage(.red, rect: CGRect(x: frame * 2, y: 0,
                                                                                      width: 10, height: 10)))
        }
        return manager
    }

    /// Runs the baker to a stop. `onIdle` is the loop's own "nothing left", so waiting on it waits on
    /// exactly the thing under test — and, since the ring top-up runs inside the same loop, a walk
    /// that failed to terminate would surface here as a timeout rather than as a wrong number.
    private func drain(_ baker: FrameBaker, timeout: TimeInterval = 60) {
        var settled = false
        let idle = expectation(description: "the baker drains and the loop stops")
        baker.onIdle = {
            guard !settled else { return }
            settled = true
            idle.fulfill()
        }
        baker.kick()
        wait(for: [idle], timeout: timeout)
        baker.onIdle = nil
    }

    private func composites(_ body: () -> Void) -> Int {
        CompositeProbe.begin()
        body()
        return CompositeProbe.end().count
    }

    /// One frame's decoded bytes at the fixture canvas, for sizing a ring in frames rather than in a
    /// number that would have to be re-derived if the fixture moved.
    private static var frameBytes: Int {
        Int(CanvasFixture.canvasSize.width * CanvasFixture.canvasSize.height) * 4
    }

    // MARK: - 1. The size, which is the whole of the boundary this stage drew

    /// **The bake and the live canvas's two halves must mint at one size, and this is that.**
    ///
    /// Not for the picture's sake — the sandwich views are `.scaleToFill` and either size draws —
    /// but for the flatten's. `PixelOps.rasterize` is memoized on cel version **and size**, and so is
    /// `MaskResolver.CacheKey`; a bake minted at `.native` while the halves are minted at
    /// `liveCompositeSize` would flatten every cel of the document a second time at a second size,
    /// into the same byte-budgeted memo, and the two working sets would evict each other. §11
    /// measures the flatten at 276 ms against an 84 ms composite, so that is the expensive half
    /// doubled — on the knob position the artist chose in order to make things *cheaper*.
    ///
    /// **The knob is what makes the two sizes differ, so the knob is what the fixture moves.** At
    /// `.full` on a 64² canvas the two spellings agree by coincidence and the test would pass with
    /// the defect present, which is the shape of assertion CLAUDE.md warns about: check that the two
    /// operands are the two things you meant to compare.
    ///
    /// **MEASURED red** by deleting `sizing: .liveComposite` from `FrameBaker.recipe` — the digest
    /// assertion fails first, and the baked image comes back 64×64 where 32×32 was wanted.
    func testTheBakeMintsAtTheSizeTheLiveCanvasComposites() {
        let manager = perFrameDocument(frames: 1)
        manager.renderResolution = .half
        let baker = manager.frameBaker
        baker.noteDocumentChanged()

        guard let halves = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 0) else {
            return XCTFail("Fixture needs a canvas size")
        }
        let live = halves.canvasSize
        XCTAssertEqual(live, CGSize(width: 32, height: 32),
                       "Premise: at half the knob the live canvas composites into half the buffer, "
                       + "so `.native` and `.liveComposite` are two different answers here")

        // The key is the exact statement of the claim: it carries `canvasSize`, so two mints that
        // disagreed about the buffer are two different files on disk for one frame.
        guard let liveRecipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true,
                                                       sizing: .liveComposite),
              let nativeRecipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true,
                                                         sizing: .native) else {
            return XCTFail("Fixture needs a canvas size")
        }
        let liveKey = FrameBakeKey(recipe: liveRecipe, renderResolution: manager.renderResolution)
        let nativeKey = FrameBakeKey(recipe: nativeRecipe, renderResolution: manager.renderResolution)
        XCTAssertNotEqual(liveKey, nativeKey,
                          "Premise: the two sizings are two keys, so the assertion below can tell them apart")
        XCTAssertEqual(baker.currentKey(atFrame: 0), liveKey,
                       "The baker's display-path key is the live canvas's own size")
        XCTAssertNotEqual(baker.currentKey(atFrame: 0), nativeKey)

        // …and end to end: the pixels the canvas is handed at rest are that size too.
        drain(baker)
        XCTAssertEqual(baker.image(atFrame: 0)?.width, Int(live.width),
                       "The baked frame is the picture the canvas shows at rest, so it is the canvas's size")
        XCTAssertEqual(baker.image(atFrame: 0)?.height, Int(live.height))
    }

    // MARK: - 2. The suspension

    /// **A sweep taken while the artist's hand is down marks the frame and composites nothing.**
    ///
    /// A dab lands in `VectorCanvas`, whose version counter is exactly what `syncDirty` reads, so a
    /// mid-stroke pass sees the artist's frame move every time. Baking it would composite a picture
    /// the artist is halfway through replacing, at `.utility`, against the one gesture §2 says must
    /// not be interfered with — and each intermediate version would mint a `PixelOps.rasterize` memo
    /// entry nothing will ever ask for again, evicting the entries the live canvas is using.
    ///
    /// `isBaking` is the synchronous witness: `kick` sets it before it dispatches, so reading it on
    /// the line after `syncFrameBake` asks "did a composite start" with no waiting and no flake.
    func testASweepWhileTheHandIsDownMarksTheFrameAndStartsNoComposite() {
        let manager = perFrameDocument(frames: 4)
        let baker = manager.frameBaker

        manager.syncFrameBake(suspended: true)
        XCTAssertFalse(baker.isBaking, "The hand is down: nothing may start")
        XCTAssertEqual(baker.bakeQueue.pendingCount, 4,
                       "…and the dirty set still accumulates. Suspension holds the loop, it does not "
                       + "discard a request (§3.6)")

        // A second pass mid-stroke — the shape a dab's cel spawn produces — changes neither answer.
        manager.syncFrameBake(suspended: true)
        XCTAssertFalse(baker.isBaking)
        XCTAssertEqual(baker.bakeQueue.pendingCount, 4)
    }

    /// …and lift is what starts it. The frames the stroke reached were marked all along.
    func testLiftIsWhatStartsTheBakeTheStrokeAskedFor() {
        let manager = perFrameDocument(frames: 4)
        let baker = manager.frameBaker
        manager.syncFrameBake(suspended: true)
        // **`CompositeProbe` cannot be the control here, and this line used to pretend it was.** It
        // was `composites { }` over an *empty block*, whose zero is a fact about the empty closure
        // and not about suspension. Moving the suspended pass inside the window does not fix it
        // either, and that is the part worth writing down: `kick` dispatches to `workQueue`, so a
        // *synchronous* probe window sees nothing whether a job was dispatched or not — MEASURED
        // 2026-09-02 by forcing `isSuspended = false` in `syncFrameBake`, which left such a window
        // at zero and the test green.
        //
        // `isBaking` is the witness, exactly as this file's §2 header says: `kick` sets it on the
        // line before the dispatch, so it answers with no waiting and no flake.
        XCTAssertFalse(baker.isBaking, "Control: the hand is down, so no job may be in flight")

        manager.syncFrameBake(suspended: false)
        XCTAssertTrue(baker.isBaking, "Lift releases the loop on the very pass that reports it")
        drain(baker)
        XCTAssertEqual(baker.bakedCount, 4, "…and the four frames the sweep had been holding are baked")
    }

    // MARK: - 3. Direction, and the re-root

    /// §3.6's band 2 is *"frames ahead of the playhead in the play direction"*, and a scrub backwards
    /// is a direction. Equal leaves it alone: a pass that did not move the playhead says nothing
    /// about which way the artist is going.
    func testAScrubBackwardsTellsTheBakerWhichWayItIsGoing() {
        let manager = perFrameDocument(frames: 8)
        manager.currentFrame = 5
        manager.syncFrameBake(suspended: true)
        XCTAssertEqual(manager.frameBaker.playbackDirection, .forward)

        manager.currentFrame = 2
        manager.syncFrameBake(suspended: true)
        XCTAssertEqual(manager.frameBaker.playbackDirection, .backward)

        manager.syncFrameBake(suspended: true)
        XCTAssertEqual(manager.frameBaker.playbackDirection, .backward,
                       "A pass that did not move the playhead is not a change of direction")
    }

    /// **The knob is a path component** (`FrameBakeStore.defaultRoot`), so moving it has to move the
    /// store — and the baker with it, because `FrameBakeStore.root` is a `let`.
    ///
    /// The identity assertion is the load-bearing one: `CanvasView.Coordinator` installs
    /// `onFrameFinished` on *a* baker, so a re-root that nothing notices would leave the canvas
    /// never being told its frames had landed. That is why the coordinator compares by identity
    /// rather than installing once.
    func testMovingTheResolutionKnobRerootsTheStoreAndTheBakerWithIt() {
        let manager = perFrameDocument(frames: 2)
        let first = manager.frameBaker
        manager.syncFrameBake(suspended: true)
        XCTAssertTrue(manager.frameBaker === first, "A pass that changed nothing rebuilds nothing")
        XCTAssertEqual(first.store.root.lastPathComponent, manager.renderResolution.rawValue)
        XCTAssertEqual(manager.renderResolution, .full, "Setup: `setUp` pins the knob")

        manager.renderResolution = .half
        manager.syncFrameBake(suspended: true)
        XCTAssertFalse(manager.frameBaker === first, "A different root is a different store")
        XCTAssertEqual(manager.frameBaker.store.root.lastPathComponent, RenderResolution.half.rawValue)
        XCTAssertEqual(manager.frameBaker.store.root.deletingLastPathComponent().lastPathComponent,
                       manager.projectID.uuidString,
                       "…under the same project, which is the other half of `defaultRoot`")
    }

    // MARK: - 4. The ring top-up

    /// **§3.5: *"Play never decodes on the display thread."* The loop alone cannot keep that
    /// promise, and this is the gap it leaves.**
    ///
    /// A bake job rings the frame it has just written, so the ring is warm for whatever the pass
    /// that *dirtied* the document reached. Playback dirties nothing: on the second lap every frame
    /// is clean, `BakeQueue.next` answers nil, and every tick past the handful of frames that
    /// survived would call `store.loadDecoded` from `FrameBaker.image(for:)` — a file read and an
    /// LZ4 decode on the display thread.
    ///
    /// The fixture is the playback case exactly: bake everything, move the playhead past the
    /// lookahead the bake filled, and ask whether the frame under it is resident. **It is a decode
    /// and never a composite**, which the probe asserts — the frame is on disk already and §3.3's
    /// dedupe would not even be reached, since the queue is empty.
    func testTheFrameThePlayheadMovesToIsRingedWithNoCompositeAtAll() {
        let manager = perFrameDocument(frames: 8)
        let baker = manager.frameBaker
        baker.ringLookahead = 2
        baker.noteDocumentChanged()
        drain(baker)
        XCTAssertEqual(baker.bakedCount, 8, "Setup: every frame is on disk")

        guard let farKey = baker.currentKey(atFrame: 6) else { return XCTFail("Needs a canvas") }
        XCTAssertFalse(baker.ring.contains(farKey.fileName),
                       "Setup: frame 6 is four past a lookahead of 2, so the bake did not ring it")

        manager.currentFrame = 6
        let count = composites { drain(baker) }
        XCTAssertEqual(count, 0, "Nothing is dirty. A top-up is a decode, never a composite")
        XCTAssertTrue(baker.ring.contains(farKey.fileName),
                      "The frame the playhead moved to is resident, so the tick that reads it reads memory")
    }

    /// **The walk terminates when the ring is narrower than the lookahead, which is the ordinary
    /// case and the one the obvious spelling cannot survive.**
    ///
    /// Scan-from-the-playhead-each-time spins forever the moment the window does not fit: filling a
    /// far frame evicts a near one, the rescan finds the near one missing, and nothing converges.
    /// 24 frames at 8.4 MB is 200 MB against a ring budget of 96, so that is not a corner. The
    /// assertion is that `drain` returns at all — a walk that did not terminate is a timeout here
    /// rather than a wrong number — plus the ring staying inside its budget while it happens.
    func testTheTopUpTerminatesWhenTheRingIsNarrowerThanTheLookahead() {
        let manager = perFrameDocument(frames: 8)
        let baker = FrameBaker(manager: manager,
                               store: FrameBakeStore(root: caches.appendingPathComponent("narrow")),
                               ring: DecodedFrameRing(byteBudget: 2 * Self.frameBytes))
        baker.ringLookahead = 8
        baker.noteDocumentChanged()
        drain(baker, timeout: 30)
        XCTAssertEqual(baker.bakedCount, 8)

        // Every frame is clean now, so this drain is the top-up walk and nothing else.
        let count = composites { drain(baker, timeout: 30) }
        XCTAssertEqual(count, 0)
        XCTAssertLessThanOrEqual(baker.ring.count, 2, "The ring holds what it can hold and no more")
        XCTAssertLessThanOrEqual(baker.ring.byteCount, 2 * Self.frameBytes)
    }

    // MARK: - 5. The document closing

    /// **`FrameBaker.reset()`'s real caller, added when BUGS.md's reading of it found none.**
    /// `CanvasManager.closeFrameBaker()` is what `ContentView.returnToGallery` calls on the way back
    /// to the gallery — the document is off screen, but `ContentView` keeps the manager in `@State`
    /// rather than discarding it, so without this the baker's bookkeeping and ring would sit resident
    /// for a document nobody is looking at.
    ///
    /// **MEASURED red** by deleting the `frameBaker.reset()` call from `closeFrameBaker` (making it a
    /// no-op): `keyByFrame` and the ring both stay populated and the two assertions below fail.
    func testClosingTheFrameBakerForgetsItsBookkeepingAndRingButNotTheBaker() {
        let manager = perFrameDocument(frames: 4)
        let baker = manager.frameBaker
        manager.syncFrameBake(suspended: false)
        drain(baker)
        XCTAssertEqual(baker.bakedCount, 4, "Setup: everything is baked")
        XCTAssertGreaterThan(baker.ring.count, 0, "Setup: the bake that just ran left the ring warm")

        manager.closeFrameBaker()

        XCTAssertTrue(baker.keyByFrame.isEmpty,
                      "The bookkeeping a document no longer on screen has no use for is gone")
        XCTAssertEqual(baker.ring.count, 0, "…and so is the decoded-frame ring it was holding idle")
        XCTAssertTrue(manager.frameBaker === baker,
                      "Closing forgets what the baker believes; it does not replace the baker — a "
                      + "swap here would leave whatever installed itself as the old instance's "
                      + "`onFrameFinished` never told the new one's frames landed")
    }
}
