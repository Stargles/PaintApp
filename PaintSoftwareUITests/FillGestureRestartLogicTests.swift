import XCTest
import SwiftUI
import UIKit
import CoreGraphics

/// **What happens when a second fill starts before the first one has finished.** The owner, on
/// device, 2026-08-19: *"Using the fill tool more than once breaks it sometimes. I think it has to
/// do something with it being in the transient state, then another thing is filled, and it doesnt
/// bake the first one properly before going to the second."* Their reading is exactly right, and
/// the window they are describing is real: `beginInteractiveFill` composites the reference, uploads
/// a GPU session and runs the flood on the fill lane, then lands the preview back on the main thread
/// (`CanvasManager.fillRenders`). A tap that lands before that hop runs used to break three ways at
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
///  - **`manager.waitForFillWork()`** runs after everything already enqueued, so it means *"the GPU
///    render has finished"*. The hop it queued to main provably has **not** run, because XCTest
///    bodies run on the main thread and nothing has pumped the run loop. That is the window in which
///    the artist's first fill exists as pixels but not as document state.
///  - **A semaphore block on the fill lane** holds the serial queue, so work enqueued behind it can be
///    ordered deliberately. That is how a *superseded* render is made to run after the gesture that
///    replaced it, which is what happens on device whenever the second tap lands while the first
///    gesture's next render is still waiting for the GPU.
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
    /// it lies in no basin and the result is empty. An empty region is therefore the exact
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
        let render = try XCTUnwrap(manager.fillLastRender, "No fill has been previewed at all")
        XCTAssertTrue(render.window.rect.contains(point), "the preview's window \(render.window.rect) does not cover \(point)")
        let pixel = render.window.workingPixel(of: point)
        return render.bytes[(pixel.y * render.window.workingWidth + pixel.x) * 4 + 3]
    }

    /// The committed pixel at a canvas point, read out of the cel's `raster` tier — the one place a
    /// raster commit is allowed to land (see `registerUndoableCelChange`).
    private func bakedPixel(_ manager: CanvasManager, _ point: CGPoint) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let cel = manager.layers[0].cels[try celIndex(manager)]
        let cg = try XCTUnwrap(try cel.raster.renderToUIImage().get().cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
        let i = (Int(point.y) * cg.width + Int(point.x)) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// Pumps the main run loop long enough for a the fill lane render's main-thread hop to land — the
    /// same helper `LassoFillLogicTests` uses. Deliberately absent from the middle of every sequence
    /// below: not settling is the bug.
    private func settle(_ seconds: TimeInterval = 0.5) {
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// Runs a tap-and-lift, then waits for the fill lane **without** pumping main. On return the flood
    /// has run and its preview has not been installed: the exact state a second tap arrives in.
    private func tapAndRenderWithoutPublishing(_ manager: CanvasManager, at point: CGPoint) {
        manager.beginInteractiveFill(at: point)
        manager.endInteractiveFill()
        manager.waitForFillWork()
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
    /// transient fill — but it settled it by asking whether a preview was shown, and the preview is
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
        XCTAssertNil(manager.liveFill?.preview,
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

    /// `beginInteractiveLassoFill` has the same shape and had the same exposure — it renders
    /// through the same `renderFill`, so a second loop drawn before the first one's landing ran
    /// dropped it identically. One undo step per loop, not one per pair.
    func testASecondLassoBakesTheFirstOne() throws {
        let manager = sceneManager()
        let before = manager.history.undoStack.count

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 30, y: 30, width: 32, height: 32)))
        manager.endInteractiveFill()
        manager.waitForFillWork()
        XCTAssertNil(manager.liveFill?.preview, "Fixture check: rendered, not yet published")

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
        manager.waitForFillWork()
        manager.beginInteractiveFill(at: Self.onThePaper)

        XCTAssertEqual(manager.history.undoStack.count, before, "Nothing was recorded for the empty loop")
    }

    /// **Three taps inside one turn of the main thread bake the first two, in order.** The second tap
    /// bakes the first (its render is done, its landing not run); the third arrives while the second
    /// has not rendered at all, so it is queued (owner ruling, Nov 26) and begins once the second's
    /// picture lands and bakes it. Each gesture gets renders of its own (`CanvasManager.fillRenders`)
    /// so the second tap's render is on the fill lane the moment it begins, though the first tap's
    /// landing still holds the one job a gesture's renders may have in flight.
    func testThreeTapsInOneTurnBakeTheFirstTwo() throws {
        let manager = sceneManager()
        let before = manager.history.undoStack.count

        tapAndRenderWithoutPublishing(manager, at: Self.onTheSquare)   // rendered, its landing not run
        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: Self.onThePaper)              // bakes the first
        manager.endInteractiveFill()
        XCTAssertEqual(manager.history.undoStack.count, before + 1, "The second tap baked the first")
        manager.beginInteractiveFill(at: Self.onTheSquare)             // queued behind the second
        manager.endInteractiveFill()
        XCTAssertEqual(manager.queuedFills.count, 1, "The third tap waits for the second's picture, not the thread")
        for _ in 0..<3 { manager.waitForFillWork(); settle() }

        XCTAssertEqual(manager.history.undoStack.count, before + 2, "The first two taps baked, one step each")
        XCTAssertGreaterThan(try bakedPixel(manager, Self.onTheSquare).r, 200, "The first is red on the square")
        let onPaper = try bakedPixel(manager, Self.onThePaper)
        XCTAssertGreaterThan(onPaper.b, 200, "…and the second blue on the paper, rather than dropped")
        XCTAssertEqual(onPaper.a, 255)
        XCTAssertTrue(manager.fillGestureActive, "…and the third is the live fill")
    }

    // MARK: - (b)/(c) A superseded worker must not speak for the gesture that replaced it

    /// **The second fill has to be rendered by the second fill's own session.**
    ///
    /// The forced interleaving is the one the device produces when the second tap lands while the
    /// first gesture's next render is queued: a render belonging to gesture 1 runs *after* gesture 2
    /// has started. Rendering there pairs gesture 2's seed — or gesture 1's, against gesture 2's
    /// session — with the wrong reference composite and the wrong sampled colour, and what the artist
    /// is left looking at is a flood from the new point judged against the old picture.
    ///
    /// Settled by one assertion, because of how the scene is built: the tap is on paper and gesture 1
    /// sampled green, so the stale pairing plants no seed and paints an empty region. A preview that
    /// covers the paper can only have come from gesture 2's own session.
    func testTheSecondFillRendersAgainstItsOwnSessionAndSeed() throws {
        let manager = sceneManager()
        manager.beginInteractiveFill(at: Self.onTheSquare)
        manager.endInteractiveFill()
        settle()   // the first render lands, so the gesture's next one is minted the moment it is asked for

        // Hold the serial queue so the next two renders can be ordered deliberately.
        let gate = DispatchSemaphore(value: 0)
        manager.fillWork { gate.wait() }
        // A gesture-1 render, queued behind the gate: this is the one that must not speak later.
        manager.setFillGapClosing(5)

        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: Self.onThePaper)   // the second tap
        manager.endInteractiveFill()

        gate.signal()
        manager.waitForFillWork()   // stale worker, session teardown and gesture 2's worker all run
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
    /// preview, overwrote `fillLastRender` (the bytes the commit bakes), and raised its own
    /// message over somebody else's fill. An empty lasso makes that visible in one value: the loop
    /// enclosed nothing, so its hop carries LASSO_FILL.md §7's *"nothing enclosed"* — and it used to
    /// arrive attached to a bucket fill that had plainly filled something.
    func testASupersededGestureDoesNotPublishOntoTheOneThatReplacedIt() throws {
        let manager = CanvasFixture.manager(layerCount: 1)   // blank paper: the loop encloses nothing

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 24, height: 24)))
        manager.endInteractiveFill()
        manager.waitForFillWork()   // the empty result exists; its hop to main is still queued

        manager.beginInteractiveFill(at: CGPoint(x: 40, y: 40))
        manager.endInteractiveFill()
        settle()

        XCTAssertNil(manager.notice, "The retired loop does not report onto the fill that replaced it")
        XCTAssertNil(manager.lassoFillDiagnostic, "…nor tint a canvas it is no longer describing")
        XCTAssertNotNil(manager.liveFill?.preview, "…and the new fill's own preview stands")
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

    // MARK: - (a) again, one window further back: the render that has not happened yet — queued

    /// **The second window, and the owner's ruling for it (Nov 26): a second Fill tap while the first
    /// fill is still drawing is queued — no pause, it lands right after the first, never dropped.**
    /// Everything above forces *"rendered, hop to main not run"*, which is a single runloop turn wide.
    /// This forces *"not rendered at all"*, which is the whole GPU pass: `fillLastRender` is nil because
    /// no hop has run, `fillRenderedRegion` is nil because no worker has stored anything, so there is
    /// nothing to bake. The commit used to *wait* on the main thread for the render (the last rule-1
    /// wait on main, SCHEDULER.md); now the tap waits instead (`CanvasManager.queuedFills`).
    ///
    /// **The gate is never signalled before the second tap returns, and that is the assertion that
    /// main does not wait**: a main thread parked on the fill lane would park here for ever, behind a
    /// gate only this thread opens. Then the gate opens, the first fill's picture lands and bakes it,
    /// and the queued tap begins against a canvas the first fill is part of.
    ///
    /// Mutation that reddens it: `queueFillIfTheLiveOneIsDrawing` answering false — the second tap then
    /// starts at once and retires the first gesture, which never bakes.
    func testASecondTapWhileTheFirstIsDrawingIsQueuedAndLandsAfterIt() throws {
        let manager = sceneManager()
        let before = manager.history.undoStack.count

        let gate = DispatchSemaphore(value: 0)
        manager.fillWork { gate.wait() }
        manager.beginInteractiveFill(at: Self.onTheSquare)
        manager.endInteractiveFill()
        XCTAssertNil(manager.fillRenderedRegion, "Fixture check: the first tap's worker is still queued")

        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: Self.onThePaper)   // returns: main did not wait on the gate
        manager.endInteractiveFill()
        XCTAssertEqual(manager.queuedFills.count, 1, "the second tap is queued behind the drawing fill")
        XCTAssertEqual(manager.history.undoStack.count, before, "nothing baked yet: there was nothing to bake")

        gate.signal()
        manager.waitForFillWork()
        settle()
        manager.waitForFillWork()
        settle()

        XCTAssertTrue(manager.queuedFills.isEmpty, "the queued tap began")
        XCTAssertEqual(manager.history.undoStack.count, before + 1, "the first fill baked as its own step")
        XCTAssertGreaterThan(try bakedPixel(manager, Self.onTheSquare).r, 200, "…red, where it was tapped")
        XCTAssertTrue(manager.fillGestureActive, "the second fill is the live one now")
        XCTAssertTrue(manager.commitInteractiveFill())
        let onPaper = try bakedPixel(manager, Self.onThePaper)
        XCTAssertGreaterThan(onPaper.b, 200, "the second fill landed after the first, in its own colour")
        XCTAssertEqual(try bakedPixel(manager, Self.onTheSquare).r, 255,
                       "…and read a canvas the first was part of: it did not flood over the red square")
    }

    /// **Three taps while the first is drawing land in the order they were made**, each in the colour
    /// it was made in, each its own undo step, none dropped.
    ///
    /// Mutation that reddens it: `landQueuedFills` taking the newest tap first (`removeLast`).
    func testTapsQueuedBehindADrawingFillLandInOrder() throws {
        let manager = twoSquareScene()
        let before = manager.history.undoStack.count
        let gate = DispatchSemaphore(value: 0)
        manager.fillWork { gate.wait() }
        manager.brushColor = Self.red
        manager.beginInteractiveFill(at: Self.onTheSquare)
        manager.endInteractiveFill()
        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: Self.onSquare2)
        manager.endInteractiveFill()
        manager.brushColor = Self.red
        manager.beginInteractiveFill(at: Self.onSquare2)   // over the blue the second tap lays
        manager.endInteractiveFill()
        XCTAssertEqual(manager.queuedFills.count, 2, "both later taps queued")
        gate.signal()
        for _ in 0..<4 { manager.waitForFillWork(); settle() }
        XCTAssertTrue(manager.queuedFills.isEmpty, "every queued tap began")
        XCTAssertTrue(manager.commitInteractiveFill())
        XCTAssertEqual(manager.history.undoStack.count, before + 3, "three fills, three steps")
        XCTAssertGreaterThan(try bakedPixel(manager, Self.onTheSquare).r, 200, "the first tap's square is red")
        let second = try bakedPixel(manager, Self.onSquare2)
        XCTAssertGreaterThan(second.r, 200, "the third tap, red, landed last — over the second's blue")
        XCTAssertLessThan(second.b, 50, "…so the second, blue, landed before it")
    }

    /// The counterweight: a loop that enclosed nothing still records nothing (LASSO_FILL.md §7.1),
    /// *including* when the tap queued behind it is what bakes it. An empty result stores no bytes.
    func testAQueuedTapStillDoesNotBakeAnEmptyLoopBeforeIt() {
        let manager = CanvasFixture.manager(layerCount: 1)   // blank paper: nothing to enclose
        let before = manager.history.undoStack.count

        let gate = DispatchSemaphore(value: 0)
        manager.fillWork { gate.wait() }
        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 24, height: 24)))
        manager.endInteractiveFill()
        manager.beginInteractiveFill(at: Self.onThePaper)
        manager.endInteractiveFill()
        gate.signal()
        for _ in 0..<2 { manager.waitForFillWork(); settle() }

        XCTAssertEqual(manager.history.undoStack.count, before, "Nothing was recorded for the empty loop")
        XCTAssertTrue(manager.queuedFills.isEmpty, "the tap behind it began")
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
        settle()   // landed, so the gesture's next render is minted the moment it is asked for

        let gate = DispatchSemaphore(value: 0)
        manager.fillWork { gate.wait() }
        manager.setFillGapClosing(5)   // a gesture-1 render, queued behind the gate

        manager.brushColor = Self.blue
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { gate.signal() }
        manager.beginInteractiveLassoFill(path: rectangleLoop(Self.loopB))
        manager.endInteractiveFill()

        manager.waitForFillWork()
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
