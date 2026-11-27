import XCTest
import UIKit
import CoreGraphics

/// **What `VectorCanvas` promises now that its lock does not cover the pixels.**
///
/// `render(quality:)` used to hold `VectorCanvas.lock` across `renderLocked` — an O(canvas-pixel)
/// rasterize — while `restoreElements(_:changedInk:)`, which undo and redo reach synchronously on the
/// main thread, took the same lock. So an undo tap blocked for as long as whatever background render
/// happened to be running, and that render's cost is the canvas's area: MEASURED on the owner's
/// iPad 9 at 6000×6000, 110–220 ms between the finger leaving the glass and the app noticing, against
/// 10–20 ms for the taps in the same trace that raced nothing.
///
/// The walk is now a pure function of a snapshot (`RenderPlan` → `walk` → `install`), taken and
/// installed under the lock with the pixels drawn outside it. That buys the responsiveness
/// `UndoContentionBench` measures, and it costs two guarantees the single lock used to give for free.
/// **These are those two guarantees**, and neither is about wall clock:
///
/// 1. **A walk whose inputs moved under it must not be installed.** Otherwise the memo would hold a
///    picture of one display list under another one's `version`, and every later reader — the
///    display, the compositor's `Frozen`, a thumbnail — would show ink the artist has already undone.
///    That is the mechanism behind *"sometimes, brushstrokes that I layed down dissapear"* pointed the
///    other way, and it is the one way this change could draw something wrong rather than merely late.
/// 2. **Two threads asking for one picture still stamp it once.** The old lock serialized rasterizes
///    as a side effect; the walk turn (`walkInFlight`) does it on purpose: a second request joins the
///    walk in flight. Without it a pen-up walks twice — the display path and the compositor's
///    snapshot both — for twice the dabs and two writers of one picture.
/// 3. **But an answer never waits behind later work's walk** (SCHEDULER_DESIGN.md §2): a request of a
///    higher class cancels the walk in flight and walks itself, which a lock across the walk — the
///    `rasterizeLock` this replaced — could not do.
///
/// **On the race tests' operands, because the first draft of them had none.** Both sides of the
/// picture assertion are produced by shipped code from one display list — the canvas's own memoized
/// answer against a cold canvas built from the elements it currently holds, `IncrementalAppendLogicTests`'
/// comparison exactly — so neither can go red when the code is right, and there is no wall-clock
/// assertion anywhere in this file. But a race test that never provokes its race asserts nothing at
/// all, and this one did not: at 256×192 with 36 strokes the walk finished in under a millisecond, the
/// edit on this thread always won, the render came back nil as superseded, and **every test here
/// passed with the version gate deleted from `install`**. `race(on:atVersion:editing:)` is the repair:
/// a deliberate head start, and `canvas.rasterizations` read either side as the operand that says the
/// render really did read the old list before the edit replaced it. `racedRounds` is asserted, so a
/// fixture that stops overlapping reports itself instead of passing quietly.
///
/// The timing claim lives in `UndoContentionBench`, where CLAUDE.md says it belongs.
///
/// **MUTATION-TESTED, and the record is here because two of the four attempts found the *test* wrong
/// rather than the code.** Against `VectorLayer.swift`:
///
/// * **`install`'s version gate deleted** → both race tests red on round 0, at 2,420 and 2,536 bytes
///   differing with worst 217/255. It took three fixtures to get there: at 256×192 the render was
///   superseded before it walked, at 768×576 it finished inside the head start, and both of those
///   passed. The window and the `race` operand are what they are because of those two greens.
/// * **The walk turn's join deleted** (S3b; it was `rasterizeLock`) → `testTwoThreadsAskingForOnePictureStampItOnce`
///   red at `rasterizations` 2 against 1, and on the two threads holding different image objects.
/// * **The whole change reverted** (i.e. the lock held across the walk again) → `UndoContentionBench`
///   red, with the undo taking the render's entire remainder.
///
/// The seam tolerance in `assertSamePixels` also comes from a mutation run: with the lock that
/// serialized walks gone, the post-race render took the repair path and differed from the cold walk by 125 bytes at
/// worst 2/255 — PERFORMANCE.md §11.11's measured seam, not a defect, and a zero-tolerance compare
/// would have called it one.
final class VectorRenderLockLogicTests: XCTestCase {

    // MARK: - The scene
    //
    // **1600×1200 with 160 overlapping strokes, and the size is load-bearing rather than arbitrary.**
    // The raced render is the *append* path — the one a pen-up takes — and an append's whole cost is
    // the canvas-sized base blit, so the canvas is what decides whether there is a window to land an
    // edit in at all. This file has now had two drafts whose window was too small to hit: at 256×192
    // the render was superseded before it started, and at 768×576 it *finished* inside the head
    // start. Both passed with the version gate deleted from `install`. The blit here is 7.7 MB
    // against a 0.5 ms head start, and `race` measures the overlap rather than assuming it.

    private static let canvasSize = CGSize(width: 1600, height: 1200)

    /// How long this thread lets the background render walk before it edits under it. Not an
    /// assertion and not a duration anything is compared against — it is the head start that makes
    /// the interleaving happen at all, and `racedRounds` checks that it worked rather than assuming.
    private static let headStart: TimeInterval = 0.0005

    private static func brush() -> Brush {
        Brush(name: "Lock", tip: .round, size: 8, dab: BrushDabSettings(spacing: 0.25))
    }

    private static func stroke(_ index: Int) -> VectorStroke {
        let x = 12 + CGFloat((index * 37) % 680)
        let y = 16 + CGFloat((index * 53) % 520)
        let samples = StrokeSamples((0..<10).map { step -> VectorSample in
            let t = CGFloat(step) / 9
            return VectorSample(x: x + t * 60, y: y + sin(t * .pi) * 34,
                                pressure: 0.35 + 0.65 * t)
        }, channels: .pressureOnly)
        return VectorStroke(brush: brush(),
                            color: CodableColor(red: Double(index % 5) / 5, green: 0.3, blue: 0.6,
                                                alpha: 1),
                            size: 8, opacity: 0.85, samples: samples,
                            composite: .paint, seed: UInt64(index &+ 1))
    }

    private static func elements(_ n: Int) -> [VectorElement] {
        (0..<n).map { .stroke(stroke($0)) }
    }

    /// **A stroke that takes a while to stamp** — the raced append. An append repairs the base in place
    /// now and walks only the new mark, so the window an edit can land in is the mark's own walk: a
    /// long, dense one, so the walk outlasts the head start.
    private static func heavyStroke(_ index: Int) -> VectorStroke {
        let samples = StrokeSamples((0..<2000).map { step -> VectorSample in
            let t = CGFloat(step) / 1999
            return VectorSample(x: 40 + t * 1500, y: 600 + sin(t * 40 * .pi) * 500, pressure: 0.5 + 0.5 * t)
        }, channels: .pressureOnly)
        return VectorStroke(brush: Brush(name: "Heavy", tip: .round, size: 40, dab: BrushDabSettings(spacing: 0.02)),
                            color: CodableColor(red: 0.2, green: 0.5, blue: 0.1, alpha: 1),
                            size: 40, opacity: 0.85, samples: samples, composite: .paint, seed: UInt64(index &+ 7))
    }

    // MARK: - Comparing two renders

    /// The raw bytes of an image's own backing bitmap. `IncrementalAppendLogicTests.rawPixels`'
    /// reason for not normalising through a third context applies here unchanged: both operands come
    /// out of the same `UIGraphicsImageRenderer` format, and re-drawing them would hide a difference
    /// rather than reveal one.
    private func rawPixels(_ image: UIImage) -> Data? {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data else { return nil }
        return data as Data
    }

    /// Two renders show the same picture, and **say how they differ when they do not**.
    ///
    /// `XCTAssertEqual` on two `Data`s prints each one's byte *count*, so a real difference reports
    /// as `("1769472 bytes") is not equal to ("1769472 bytes")` — a failure that names neither the
    /// element nor the reason, which is the diagnosis CLAUDE.md asks every shared assertion to give.
    ///
    /// **The tolerance is one rounding unit and it is not slack, it is the difference between these
    /// two operands.** The live arm here may have got its pixels from a *region repair*, and
    /// PERFORMANCE.md §11.11 measures a repaired picture against a cold full walk at **worst 1 out of
    /// 255**, along the seam where the clip's integral edge falls: a repair redraws its rectangle
    /// from the bottom of the stack and composes its seam with the previous repair's. A zero-tolerance
    /// compare between a repair and a cold walk is therefore an assertion that can go red against
    /// correct code, and this one did — 125 of 1,769,472 bytes, worst 2/255, on a run where the
    /// timing happened to put the post-race render on the repair path.
    ///
    /// **`maxDelta` and not a count, because the thing being caught is not subtle.** A stale install
    /// puts a whole extra stroke in the picture: thousands of bytes at deltas up to the ink's own
    /// alpha. Bounding the *depth* of the difference separates those two cases with two orders of
    /// magnitude to spare, and bounding the count would not — a seam's byte count scales with the
    /// clip's perimeter, which is a property of the fixture rather than of correctness.
    private func assertSamePixels(_ live: UIImage, _ cold: UIImage, _ what: String,
                                  maxDelta: Int = 2,
                                  file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let a = rawPixels(live), let b = rawPixels(cold) else {
            XCTFail("\(what): no bitmap to compare", file: file, line: line)
            return false
        }
        guard a.count == b.count else {
            XCTFail("\(what): byte counts differ (\(a.count) vs \(b.count))", file: file, line: line)
            return false
        }
        if a == b { return true }
        var worst = 0, worstIndex = -1, differing = 0
        a.withUnsafeBytes { ra in
            b.withUnsafeBytes { rb in
                let pa = ra.bindMemory(to: UInt8.self), pb = rb.bindMemory(to: UInt8.self)
                for i in 0..<pa.count {
                    let delta = abs(Int(pa[i]) - Int(pb[i]))
                    if delta > 0 { differing += 1 }
                    if delta > worst { worst = delta; worstIndex = i }
                }
            }
        }
        if worst <= maxDelta { return true }
        XCTFail("\(what): \(differing) of \(a.count) bytes differ, worst \(worst)/255 at byte "
                + "\(worstIndex) — past the \(maxDelta)/255 a repair's seam can account for, so "
                + "this is ink rather than rounding", file: file, line: line)
        return false
    }

    /// **A cold canvas built from `elements`, which cannot take any fast path** — a fresh canvas has
    /// no memo, no incremental base and no region base, so this is the full walk by construction and
    /// is the only honest reference for what a display list is supposed to look like.
    private func coldRender(of elements: [VectorElement]) throws -> UIImage {
        let cold = VectorCanvas(size: Self.canvasSize, elements: elements)
        let image = (try XCTUnwrap(cold.render()))
        XCTAssertEqual(cold.rasterizations, 1,
                       "the reference arm must have rasterized exactly once — if it did not, it is "
                       + "not the cold full walk this comparison needs")
        return image
    }

    // MARK: - 1. A walk whose inputs moved is not installed

    /// One round of the race: start the render of `version`, let it get into the walk, then run
    /// `edit` on this thread under it. Returns whether the render actually walked.
    ///
    /// **`rasterizations` read across the edit is the operand that says the race happened**, and it
    /// has to be read across the edit rather than around the whole thing. The counter moves in
    /// `install`; `install` is reached only by a plan that saw `version`, which the edit is about to
    /// move. So a round where it moves **after `edit()` returned** is a round where the render read
    /// the old list before the edit and tried to install after it — the entire interleaving under
    /// test, in one comparison.
    ///
    /// Reading it around the whole round instead is the weaker claim that *a* walk happened, and it
    /// is satisfied by a render that started and finished inside the head start. That is not a
    /// hypothetical: it is what this file did at 768×576, where it passed with the version gate
    /// deleted.
    private func race(on canvas: VectorCanvas, atVersion version: Int,
                      editing edit: () -> Void) -> Bool {
        let entered = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            entered.signal()
            _ = canvas.render(quality: .full, ifStillAtVersion: version)
            finished.signal()
        }
        entered.wait()
        Thread.sleep(forTimeInterval: Self.headStart)
        edit()
        let atEdit = canvas.rasterizations
        finished.wait()
        return canvas.rasterizations > atEdit
    }

    func testAnUndoLandingDuringARenderNeverLeavesTheMemoShowingTheUndoneStroke() throws {
        let base = Self.elements(160)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: base)
        // The memo and the incremental base, so the raced render takes the append path — which is the
        // path a pen-up actually takes and the one an undo actually interrupts.
        _ = canvas.render()

        var racedRounds = 0
        for round in 0..<8 {
            // Forward edit: one more stroke, declared as an append exactly as `addStroke` does.
            canvas.addStroke(Self.heavyStroke(900 + round))
            let after = canvas.elements.count
            // The undo, on this thread, exactly as `registerVectorUndo`'s closure spells it, run
            // under a background `render(quality:ifStillAtVersion:)` — the call
            // `StrokeCanvasView.startVectorRender` makes.
            if race(on: canvas, atVersion: canvas.version,
                    editing: { canvas.restoreElements(base, changedInk: nil) }) { racedRounds += 1 }

            // **The assertion, and both its operands are shipped code drawing one list.** Whatever
            // the memo holds now must be the picture of the elements the canvas holds now. A walk of
            // the longer list installed under the version `base` was restored at would show the
            // undone stroke, and that is exactly the difference this catches.
            // One report is enough; eight would bury it.
            guard assertSamePixels((try XCTUnwrap(canvas.render())), try coldRender(of: base),
                                   "round \(round): the canvas's own render disagrees with a cold "
                                   + "walk of the elements it currently holds — a render planned "
                                   + "before the undo was installed after it, so the memo is a "
                                   + "picture of \(after) elements filed under a version that has "
                                   + "\(base.count)") else { return }
        }
        XCTAssertGreaterThan(racedRounds, 0,
                             "no round actually raced: in every one of them the render either never "
                             + "walked or had already installed by the time the undo returned, so "
                             + "this test asserted nothing about an install landing on a moved "
                             + "canvas. Widen the window — see `canvasSize` and `headStart`")
    }

    /// The same guarantee from the other end of the class: an edit that is *not* an append, so the
    /// raced render is a region repair rather than an append, and the install has to refuse a
    /// `paintedBounds` table measured against a list that has since been replaced.
    func testARestoreLandingDuringARepairNeverLeavesStaleFootprintsBehind() throws {
        let base = Self.elements(160)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: base)
        _ = canvas.render()

        var longer = base
        longer.append(.stroke(Self.stroke(1900)))
        let damage = CGRect(x: 8, y: 8, width: 300, height: 240)

        var racedRounds = 0
        for round in 0..<8 {
            // A region-declaring restore in each direction, which is what puts a `regionBase` up and
            // makes the next render the repair path.
            canvas.restoreElements(longer, changedInk: damage)
            if race(on: canvas, atVersion: canvas.version,
                    editing: { canvas.restoreElements(base, changedInk: damage) }) { racedRounds += 1 }

            guard assertSamePixels((try XCTUnwrap(canvas.render())), try coldRender(of: base),
                                   "round \(round): a repair planned before the restore was "
                                   + "installed after it — either its pixels or the footprints it "
                                   + "measured, both of which are claims about a display list this "
                                   + "canvas no longer holds") else { return }
        }
        XCTAssertGreaterThan(racedRounds, 0, "no round actually raced — see the sibling test")
    }

    // MARK: - 2. Two threads asking for one picture stamp it once

    /// **Deterministic whether or not the two calls actually overlap**, which is what makes it a
    /// usable fast-tier test: if they overlap, the walk turn makes the second join the first and find
    /// the memo; if they do not, the second finds the memo anyway. Either way exactly one walk happens.
    /// The mutation that reddens it is removing the join, and *that* mutation only reds when the two
    /// do overlap — so the barrier below is there to make the overlap likely rather than to make the
    /// assertion true.
    func testTwoThreadsAskingForOnePictureStampItOnce() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: Self.elements(160))
        let version = canvas.version
        XCTAssertEqual(canvas.rasterizations, 0, "the fixture must start with nothing memoized")

        let barrier = DispatchSemaphore(value: 0)
        let done = DispatchGroup()
        var images: [UIImage?] = [nil, nil]
        let seat = NSLock()
        for slot in 0..<2 {
            DispatchQueue.global(qos: .userInitiated).async(group: done) {
                barrier.wait()
                let image = canvas.render(quality: .full, ifStillAtVersion: version)
                seat.lock(); images[slot] = image; seat.unlock()
            }
        }
        barrier.signal(); barrier.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 30), .success, "both renders must finish")

        XCTAssertEqual(canvas.rasterizations, 1,
                       "two requests for one version stamped the cel \(canvas.rasterizations) times; "
                       + "the walk turn exists so the second joins and reads the memo the first "
                       + "installed, which is what keeps a pen-up to one walk")
        XCTAssertNotNil(images[0], "the first render returned nothing")
        XCTAssertNotNil(images[1], "the second render returned nothing")
        XCTAssertTrue(images[0] === images[1],
                      "the two threads got different image objects, so the memo was not shared even "
                      + "though only one walk ran")
    }

    /// **An answer pre-empts a bake's walk of the same cel instead of waiting behind it** — the third
    /// promise. A later (R3) caller starts a long walk; an answer (R1) arrives while it runs. The answer
    /// must cancel it and walk itself (`walksPreempted`), and the bake's caller must then join that walk
    /// and come back with its picture — one walk installed, one picture shared. Under the lock this
    /// replaced the answer waited for the whole of the bake's walk (SCHEDULER_DESIGN.md §0, "An Undo can
    /// wait on a bake").
    ///
    /// Mutation that reddens it: drop the cancel in `enterWalk` — `walksPreempted` stays 0.
    func testAnAnswerPreemptsALaterWalkOfTheSameCel() throws {
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: Self.elements(160) + (0..<6).map { .stroke(Self.heavyStroke($0)) })
        let version = canvas.version
        let laterDone = DispatchSemaphore(value: 0)
        var laterImage: UIImage?
        DispatchQueue.global(qos: .utility).async {
            laterImage = MemoryBudget.withLane(.later) { canvas.render(quality: .full, ifStillAtVersion: version) }
            laterDone.signal()
        }
        let deadline = Date().addingTimeInterval(10)
        while !canvas.hasWalkInFlight, Date() < deadline { Thread.sleep(forTimeInterval: 0.0002) }
        XCTAssertTrue(canvas.hasWalkInFlight, "PREMISE: the later walk must be running when the answer arrives")
        let answer = MemoryBudget.withLane(.answer) { canvas.render(quality: .full, ifStillAtVersion: version) }
        XCTAssertEqual(laterDone.wait(timeout: .now() + 30), .success, "the later caller must come back")
        XCTAssertEqual(canvas.walksPreempted, 1,
                       "the answer did not cancel the later walk it found in flight — it waited behind it")
        XCTAssertNotNil(answer, "the answer came back with no picture")
        XCTAssertTrue(answer === laterImage,
                      "the pre-empted caller did not join the answer's walk: it walked again or got nothing")
        XCTAssertEqual(canvas.rasterizations, 1, "one walk is installed; the cancelled one stopped before it")
    }

    // MARK: - 3. The narrowed lock still answers the questions it was narrowed around

    /// A render running does not stop a *reader* either, and this is the cheapest possible statement
    /// of it: `elements`, `version` and `cachedRender()` are all O(1)-ish acquisitions of the state
    /// lock, and none of them may be behind a canvas-sized walk. Asserted structurally — the reads
    /// happen and are self-consistent — rather than in milliseconds, which is `UndoContentionBench`'s
    /// job.
    func testTheStateAccessorsStayAnswerableWhileARenderIsWalking() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: Self.elements(160))
        let version = canvas.version
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = canvas.render(quality: .full, ifStillAtVersion: version)
            finished.signal()
        }
        // Hammer the accessors for the life of the render. The claim is that they answer at all and
        // answer consistently, not that they answer quickly.
        //
        // **The polling wait consumes the signal, so there is no second `wait()` after this loop** —
        // an earlier draft had one and hung forever on exactly the run where the render finished
        // first, which is every run. A `DispatchSemaphore` is a counter, not a latch.
        var reads = 0
        var landed = false
        while !landed {
            landed = finished.wait(timeout: .now() + 0.001) == .success
            XCTAssertEqual(canvas.elements.count, 160, "the display list changed under a read")
            XCTAssertGreaterThanOrEqual(canvas.version, version, "the version went backwards")
            _ = canvas.cachedRender()
            reads += 1
            if reads > 30_000 {
                XCTFail("the render never landed after \(reads) reads — a reader is starving it, "
                        + "which is the failure mode a narrowed lock is supposed to remove")
                return
            }
        }
        XCTAssertEqual(canvas.rasterizations, 1, "the render did not happen, so nothing was raced")
    }
}
