import XCTest
import SwiftUI
import UIKit
import CoreGraphics

/// **What happens when a second fill starts before the first one has finished.** The owner, on
/// device, 2026-08-19: *"Using the fill tool more than once breaks it sometimes. I think it has to
/// do something with it being in the transient state, then another thing is filled, and it doesnt
/// bake the first one properly before going to the second."* Their reading is exactly right, and
/// the window they are describing is real: `beginInteractiveFill` composites the reference, uploads
/// a GPU session and runs the flood on `fillQueue`, then publishes the preview back with a
/// `DispatchQueue.main.async`. A tap that lands before that hop runs used to break three ways at
/// once, and each of the three has a test below.
///
/// **There are two windows, not one, and 2026-08-21 is when the second one surfaced.** The owner
/// again, on the lasso: *"that bug is present in the lasso... currently I havent found the normal
/// fill to do it though."* Everything in the first half of this file forces *"rendered, hop to main
/// not run yet"*, which is one runloop turn wide. The tests under "one window further back" force
/// *"not rendered at all"*, which is the entire GPU pass — and a lasso session's pass is several
/// times a bucket tap's, which is the whole of why one mode reproduces it and the other does not.
/// The mechanism is shared; only the exposure is the lasso's.
///
/// **The interleavings here are forced, not waited for.** "Sometimes" is what makes a race ship, and
/// a test that hopes to lose a race is worth nothing in either direction — it can pass on broken
/// code and fail on correct code. Two primitives do all the work, and both are exact:
///
///  - **`manager.fillQueue.sync {}`** runs after everything already enqueued, so it means *"the GPU
///    render has finished"*. The hop it queued to main provably has **not** run, because XCTest
///    bodies run on the main thread and nothing has pumped the run loop. That is the window in which
///    the artist's first fill exists as pixels but not as document state.
///  - **A semaphore block on `fillQueue`** holds the serial queue, so work enqueued behind it can be
///    ordered deliberately. That is how a *superseded* worker is made to run after the gesture that
///    replaced it, which is what happens on device whenever the second tap lands while the first
///    flood is still on the GPU.
///
/// Everything drives the real `CanvasManager` and the real `MetalFillSession`; nothing is mocked.
/// See `FillBoundaryLogicTests` for why the fill's Metal pipeline runs headlessly at all.
final class FillGestureRestartLogicTests: XCTestCase {

    // MARK: - Scene

    /// `CanvasFixture.canvasSize` is 64x64, and the whole scene is two compartments that answer to
    /// *different* seed colours — which is the discriminator every test here turns on.
    ///
    /// A tap at `onTheSquare` samples green and floods the square; a tap at `onThePaper` samples
    /// transparent paper and floods everything else. Pair either seed with the *other* tap's sampled
    /// colour — which is precisely what a superseded worker did — and the seed pixel is a wall, so
    /// `floodInit` plants nothing and the result is empty. An empty region is therefore the exact
    /// signature of a fill rendered against the wrong session, and it cannot be confused with a fill
    /// that merely landed somewhere unexpected.
    private static let square = CGRect(x: 40, y: 40, width: 20, height: 20)
    private static let onTheSquare = CGPoint(x: 50, y: 50)
    private static let onThePaper = CGPoint(x: 5, y: 5)

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
    private static let blue = Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)

    private func sceneManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.green, rect: Self.square))
        manager.brushColor = Self.red
        return manager
    }

    // MARK: - Reading the document back

    private func celIndex(_ manager: CanvasManager) throws -> Int {
        try XCTUnwrap(manager.activeCelIndex(inLayer: 0, atFrame: manager.currentFrame))
    }

    /// The alpha of the live preview's region buffer at a canvas pixel — the bytes
    /// `commitInteractiveFill` bakes, and what `isPointInPendingFill` hit-tests.
    private func previewAlpha(_ manager: CanvasManager, _ point: CGPoint) throws -> UInt8 {
        let bytes = try XCTUnwrap(manager.fillLastRegionRGBA, "No fill has been previewed at all")
        let w = manager.fillLastRegionW
        return bytes[(Int(point.y) * w + Int(point.x)) * 4 + 3]
    }

    /// The committed pixel at a canvas point, read out of the cel's `raster` tier — the one place a
    /// raster commit is allowed to land (see `registerUndoableCelChange`).
    private func bakedPixel(_ manager: CanvasManager, _ point: CGPoint) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let cel = manager.layers[0].cels[try celIndex(manager)]
        let cg = try XCTUnwrap(cel.raster.renderToUIImage().cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
        let i = (Int(point.y) * cg.width + Int(point.x)) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// Pumps the main run loop long enough for a `fillQueue` render's main-thread hop to land — the
    /// same helper `LassoFillLogicTests` uses. Deliberately absent from the middle of every sequence
    /// below: not settling is the bug.
    private func settle(_ seconds: TimeInterval = 0.5) {
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// Runs a tap-and-lift, then waits for `fillQueue` **without** pumping main. On return the flood
    /// has run and its preview has not been installed: the exact state a second tap arrives in.
    private func tapAndRenderWithoutPublishing(_ manager: CanvasManager, at point: CGPoint) {
        manager.beginInteractiveFill(at: point)
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
    }

    private func rectangleLoop(_ rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
        path.closeSubpath()
        return path
    }

    // MARK: - (a) The first fill must not be dropped

    /// **The owner's sentence, tested literally: the first fill has to bake before the second one
    /// starts.** `beginInteractiveFill` calls `beginCanvasEdit()`, whose whole job is to settle the
    /// transient fill — but it settled it by asking `guard cel.fillImage != nil`, and `fillImage` is
    /// written by the render's hop to main. So for as long as that hop was outstanding the answer was
    /// "nothing was previewed", and a fill that had already been computed was thrown away in silence:
    /// no pixels, no undo entry, no message.
    ///
    /// The fixture check in the middle is what makes this a race test rather than a fill test — it
    /// asserts the window is genuinely open before the second tap is made.
    func testASecondTapBakesTheFirstFillInsteadOfDroppingIt() throws {
        let manager = sceneManager()
        let before = manager.history.undoStack.count

        tapAndRenderWithoutPublishing(manager, at: Self.onTheSquare)
        XCTAssertNil(manager.layers[0].cels[try celIndex(manager)].fillImage,
                     "Fixture check: the render is done and its preview has not reached the main thread")

        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: Self.onThePaper)   // the second tap, inside the window

        XCTAssertEqual(manager.history.undoStack.count, before + 1,
                       "The first fill baked as its own undo step on the way into the second")
        let pixel = try bakedPixel(manager, Self.onTheSquare)
        XCTAssertGreaterThan(pixel.r, 200, "…and its pixels are in the cel: red over the green square")
        XCTAssertLessThan(pixel.g, 60)
        XCTAssertEqual(pixel.a, 255)
    }

    /// `beginInteractiveLassoFill` has the same shape and had the same exposure — it publishes
    /// through the same `drainFillWork`, so a second loop drawn before the first one's hop landed
    /// dropped it identically. One undo step per loop, not one per pair.
    func testASecondLassoBakesTheFirstOne() throws {
        let manager = sceneManager()
        let before = manager.history.undoStack.count

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 30, y: 30, width: 32, height: 32)))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        XCTAssertNil(manager.layers[0].cels[try celIndex(manager)].fillImage,
                     "Fixture check: rendered, not yet published")

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 2, y: 2, width: 24, height: 24)))

        XCTAssertEqual(manager.history.undoStack.count, before + 1, "The first loop baked")
        XCTAssertGreaterThan(try bakedPixel(manager, Self.onTheSquare).r, 200, "…onto the square it enclosed")
    }

    /// The counterweight to both of the above, and the reason they cannot be satisfied by baking
    /// whatever happens to be lying around: a loop that encloses nothing still commits nothing and
    /// still pushes no undo entry (LASSO_FILL.md §7.1), *including* when a second gesture is what
    /// triggers its commit. The commit path now has a second source of bytes, and this is what keeps
    /// that source honest — an empty result stores none.
    func testASecondGestureStillDoesNotBakeAnEmptyLasso() {
        let manager = CanvasFixture.manager(layerCount: 1)   // blank paper: nothing to enclose
        let before = manager.history.undoStack.count

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 24, height: 24)))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        manager.beginInteractiveFill(at: Self.onThePaper)

        XCTAssertEqual(manager.history.undoStack.count, before, "Nothing was recorded for the empty loop")
    }

    // MARK: - (b)/(c) A superseded worker must not speak for the gesture that replaced it

    /// **The second fill has to be rendered by the second fill's own session.**
    ///
    /// The forced interleaving is the one the device produces when the second tap lands mid-flood: a
    /// worker belonging to gesture 1 runs *after* gesture 2 has started. It used to read `fillPending`
    /// — now gesture 2's request — book `fillRendered` against it, and render it against gesture 1's
    /// session, gesture 1's reference composite and gesture 1's sampled colour. Two failures fall out
    /// of that one step: gesture 2's own worker then finds `key == fillRendered` and returns having
    /// drawn nothing at all, and what the artist is left looking at is a flood from the new point
    /// judged against the old picture.
    ///
    /// Both are settled by one assertion, because of how the scene is built: the tap is on paper and
    /// gesture 1 sampled green, so the stale pairing plants no seed and paints an empty region. A
    /// preview that covers the paper can only have come from gesture 2's own session.
    func testTheSecondFillRendersAgainstItsOwnSessionAndSeed() throws {
        let manager = sceneManager()
        tapAndRenderWithoutPublishing(manager, at: Self.onTheSquare)

        // Hold the serial queue so the next two workers can be ordered deliberately.
        let gate = DispatchSemaphore(value: 0)
        manager.fillQueue.async { gate.wait() }
        // A gesture-1 worker, queued behind the gate: this is the one that must not speak later.
        manager.setFillSetting(.gapClosing, 5)

        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: Self.onThePaper)   // the second tap
        manager.endInteractiveFill()

        gate.signal()
        manager.fillQueue.sync {}   // stale worker, session teardown and gesture 2's worker all run
        settle()

        XCTAssertGreaterThan(try previewAlpha(manager, Self.onThePaper), 0,
                             "The paper the second tap asked for is filled")
        XCTAssertGreaterThan(try previewAlpha(manager, CGPoint(x: 20, y: 20)), 0, "…all of it")
        XCTAssertEqual(try previewAlpha(manager, Self.onTheSquare), 0,
                       "…and the square is a wall to it, not part of the flood")
    }

    /// **A gesture that has been replaced says nothing about the canvas it no longer describes.**
    ///
    /// The publish hop guarded only on `fillGestureActive` — *some* fill is live — which the gesture
    /// that replaced it has just set true. So a superseded render installed itself as the current
    /// preview, overwrote `fillLastRegionRGBA` (the bytes the commit bakes), and raised its own
    /// message over somebody else's fill. An empty lasso makes that visible in one value: the loop
    /// enclosed nothing, so its hop carries LASSO_FILL.md §7's *"nothing enclosed"* — and it used to
    /// arrive attached to a bucket fill that had plainly filled something.
    func testASupersededGestureDoesNotPublishOntoTheOneThatReplacedIt() throws {
        let manager = CanvasFixture.manager(layerCount: 1)   // blank paper: the loop encloses nothing

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 24, height: 24)))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}   // the empty result exists; its hop to main is still queued

        manager.beginInteractiveFill(at: CGPoint(x: 40, y: 40))
        manager.endInteractiveFill()
        settle()

        XCTAssertNil(manager.notice, "The retired loop does not report onto the fill that replaced it")
        XCTAssertNil(manager.lassoFillDiagnostic, "…nor tint a canvas it is no longer describing")
        XCTAssertNotNil(manager.layers[0].cels[try celIndex(manager)].fillImage,
                        "…and the new fill's own preview stands")
    }

    // MARK: - The ordinary case, unchanged

    /// The guard against fixing a race by breaking the feature: two taps with the run loop pumped
    /// between them are two fills, two undo steps, and two regions each painted where it was asked
    /// for. Every assertion above is about the window; this one is about there being no window.
    func testTwoUnhurriedFillsEachBakeAndEachLandWhereTheyWereTapped() throws {
        let manager = sceneManager()
        let before = manager.history.undoStack.count

        manager.beginInteractiveFill(at: Self.onTheSquare)
        manager.endInteractiveFill()
        settle()
        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: Self.onThePaper)
        manager.endInteractiveFill()
        settle()
        manager.commitInteractiveFill()

        XCTAssertEqual(manager.history.undoStack.count, before + 2, "One undo step per fill")
        let onSquare = try bakedPixel(manager, Self.onTheSquare)
        XCTAssertGreaterThan(onSquare.r, 200, "The first fill is red where it was tapped")
        XCTAssertLessThan(onSquare.b, 60)
        let onPaper = try bakedPixel(manager, Self.onThePaper)
        XCTAssertGreaterThan(onPaper.b, 200, "…and the second is blue where it was")
        XCTAssertLessThan(onPaper.r, 60)
    }

    // MARK: - (a) again, one window further back: the render that has not happened yet

    /// **The second window, and the one the owner is looking at on the lasso.** Everything above
    /// forces *"rendered, hop to main not run"*, which is a single runloop turn wide. This forces
    /// *"not rendered at all"*, which is the whole GPU pass — and against `commitInteractiveFill` as
    /// it stood, the first loop was dropped in silence exactly as it was before the generation fix:
    /// `fillLastRegionRGBA` is nil because no hop has run, `fillRenderedRegion` is nil because no
    /// worker has stored anything, so the commit had no pixels from either source and returned.
    ///
    /// **The owner, on device 2026-08-21: "that bug is present in the lasso... currently I havent
    /// found the normal fill to do it though." The mechanism is shared and the exposure is not.**
    /// `testATapWhoseFloodHasNotRunYetStillBakes` below drives the identical interleaving through
    /// the bucket fill and fails identically without the fix, so nothing here is lasso-only. What is
    /// lasso-only is how long the window stays open: a lasso session derives a ring mask and its
    /// reference colours over the whole canvas on the CPU before it starts, then runs
    /// `encodeWallsAndClose` — two JFA distance transforms — *once per reference colour*, and floods
    /// both in lockstep. A bucket tap does one wall pass and one flood. The artist cannot out-run a
    /// tap; drawing the next loop while the last one is still on the GPU is ordinary use.
    ///
    /// **The gate is signalled off a background queue, and that is not decoration.** The fix waits on
    /// `fillQueue` from the main thread, so a gate signalled from the test body — which is the main
    /// thread — would park there for ever. Signalling it from elsewhere keeps the interleaving just
    /// as forced (gesture 1's worker provably has not run when gesture 2 begins) while leaving the
    /// wait a wait rather than a deadlock.
    func testASecondLassoBakesAFirstLoopThatHasNotRenderedYet() throws {
        let manager = sceneManager()
        let before = manager.history.undoStack.count

        let gate = DispatchSemaphore(value: 0)
        manager.fillQueue.async { gate.wait() }
        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 30, y: 30, width: 32, height: 32)))
        manager.endInteractiveFill()
        XCTAssertNil(manager.fillRenderedRegion,
                     "Fixture check: the first loop's worker is still queued — nothing rendered anywhere")

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { gate.signal() }
        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 2, y: 2, width: 24, height: 24)))

        XCTAssertEqual(manager.history.undoStack.count, before + 1,
                       "The first loop baked as its own undo step rather than being dropped")
        XCTAssertGreaterThan(try bakedPixel(manager, Self.onTheSquare).r, 200,
                             "…and its pixels are in the cel: red over the square it enclosed")
    }

    /// The same interleaving on the bucket fill. It is here to say what the lasso test cannot: the
    /// hole is in `commitInteractiveFill`, not on the lasso path, so the fix is one guard in one
    /// place rather than a second mechanism that means the same thing. Both fail on the parent
    /// commit; only the lasso one is reachable at the speeds an artist works at.
    func testATapWhoseFloodHasNotRunYetStillBakes() throws {
        let manager = sceneManager()
        let before = manager.history.undoStack.count

        let gate = DispatchSemaphore(value: 0)
        manager.fillQueue.async { gate.wait() }
        manager.beginInteractiveFill(at: Self.onTheSquare)
        manager.endInteractiveFill()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { gate.signal() }
        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: Self.onThePaper)

        XCTAssertEqual(manager.history.undoStack.count, before + 1, "The first tap baked")
        XCTAssertGreaterThan(try bakedPixel(manager, Self.onTheSquare).r, 200, "…where it was tapped")
    }

    /// The counterweight, and the one that keeps the wait from being bought with §7.1: a loop that
    /// enclosed nothing still records nothing, *including* when the gesture that commits it had to
    /// wait for its render to exist. An empty result stores no bytes, so the new wait produces the
    /// same nil the old code read by accident — for the right reason this time.
    func testWaitingForAnUnrenderedLoopStillDoesNotBakeAnEmptyOne() {
        let manager = CanvasFixture.manager(layerCount: 1)   // blank paper: nothing to enclose
        let before = manager.history.undoStack.count

        let gate = DispatchSemaphore(value: 0)
        manager.fillQueue.async { gate.wait() }
        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 24, height: 24)))
        manager.endInteractiveFill()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { gate.signal() }
        manager.beginInteractiveFill(at: Self.onThePaper)

        XCTAssertEqual(manager.history.undoStack.count, before, "Nothing was recorded for the empty loop")
    }

    /// The lasso's own version of `testTheSecondFillRendersAgainstItsOwnSessionAndSeed` — a
    /// superseded *lasso* worker running after a *lasso* replaced it, where the existing test had a
    /// bucket fill on at least one side of the pair. **A control: it passes on the parent commit
    /// too**, and it is here because the owner's report named the lasso and the honest answer is
    /// that (b) and (c) were already covered there; only (a) was not. The loops enclose different
    /// squares, so "which session rendered this" is legible in one pixel.
    func testASecondLassoRendersAgainstItsOwnLoop() throws {
        let manager = twoSquareScene()

        manager.beginInteractiveLassoFill(path: rectangleLoop(Self.loopA))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}   // rendered, not yet published

        let gate = DispatchSemaphore(value: 0)
        manager.fillQueue.async { gate.wait() }
        manager.setFillSetting(.gapClosing, 5)   // a gesture-1 worker, queued behind the gate

        manager.brushColor = Self.blue
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { gate.signal() }
        manager.beginInteractiveLassoFill(path: rectangleLoop(Self.loopB))
        manager.endInteractiveFill()

        manager.fillQueue.sync {}
        settle()

        XCTAssertGreaterThan(try previewAlpha(manager, Self.onSquare2), 0,
                             "The square the second loop enclosed is filled")
        XCTAssertEqual(try previewAlpha(manager, Self.onTheSquare), 0,
                       "…and the first loop's square is not part of it")
    }

    /// A second scene, for the tests that need the two gestures to enclose *different* things:
    /// `sceneManager`'s single square cannot distinguish "loop B rendered" from "loop A's render
    /// installed itself". `loopA`/`loopB` are drawn on clean paper around one square each, so each
    /// loop's collar reads paper, stops at its own square, and fills exactly that square.
    private static let square2 = CGRect(x: 6, y: 6, width: 20, height: 20)
    private static let onSquare2 = CGPoint(x: 16, y: 16)
    private static let loopA = CGRect(x: 34, y: 34, width: 28, height: 28)
    private static let loopB = CGRect(x: 2, y: 2, width: 28, height: 28)

    private func twoSquareScene() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        let art = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize,
                                          format: PixelOps.transparentFormat()).image { ctx in
            UIColor.green.setFill()
            ctx.cgContext.fill(Self.square)
            ctx.cgContext.fill(Self.square2)
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, art)
        manager.brushColor = Self.red
        return manager
    }
}
