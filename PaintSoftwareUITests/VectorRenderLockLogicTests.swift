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
///    as a side effect; `rasterizeLock` does it on purpose. Without it a pen-up walks twice — the
///    display path and the compositor's snapshot both — for twice the dabs and two canvas-sized
///    buffers alive at once, which at 6000² is 288 MB on a 3 GB iPad.
///
/// **On the first test's operands.** It is concurrent, so it can fail to *provoke* the race on a run;
/// what it cannot do is go red when the code is right, because both sides of its assertion are
/// produced by shipped code from one display list — the canvas's own memoized answer against a cold
/// canvas built from the same elements, `IncrementalAppendLogicTests`' comparison exactly. A green
/// here is therefore weak evidence and a red is strong evidence, which is the safe direction for a
/// test in a tier that runs constantly. It carries no wall-clock assertion at all; the timing claim
/// lives in `UndoContentionBench`, where CLAUDE.md says it belongs.
final class VectorRenderLockLogicTests: XCTestCase {

    // MARK: - The scene
    //
    // 256×192 with a few dozen overlapping strokes: big enough that a walk takes long enough to be
    // raced on a simulator, small enough for a tier that runs constantly.

    private static let canvasSize = CGSize(width: 256, height: 192)

    private static func brush() -> Brush {
        Brush(name: "Lock", tip: .round, size: 8, dab: BrushDabSettings(spacing: 0.25))
    }

    private static func stroke(_ index: Int) -> VectorStroke {
        let x = 12 + CGFloat((index * 17) % 200)
        let y = 16 + CGFloat((index * 31) % 150)
        let samples = StrokeSamples((0..<10).map { step -> VectorSample in
            let t = CGFloat(step) / 9
            return VectorSample(x: x + t * 40, y: y + sin(t * .pi) * 22,
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

    // MARK: - Comparing two renders

    /// The raw bytes of an image's own backing bitmap. `IncrementalAppendLogicTests.rawPixels`'
    /// reason for not normalising through a third context applies here unchanged: both operands come
    /// out of the same `UIGraphicsImageRenderer` format, and re-drawing them would hide a difference
    /// rather than reveal one.
    private func rawPixels(_ image: UIImage) -> Data? {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data else { return nil }
        return data as Data
    }

    /// **A cold canvas built from `elements`, which cannot take any fast path** — a fresh canvas has
    /// no memo, no incremental base and no region base, so this is the full walk by construction and
    /// is the only honest reference for what a display list is supposed to look like.
    private func coldRender(of elements: [VectorElement]) -> UIImage {
        let cold = VectorCanvas(size: Self.canvasSize, elements: elements)
        let image = cold.render()
        XCTAssertEqual(cold.rasterizations, 1,
                       "the reference arm must have rasterized exactly once — if it did not, it is "
                       + "not the cold full walk this comparison needs")
        return image
    }

    // MARK: - 1. A walk whose inputs moved is not installed

    func testAnUndoLandingDuringARenderNeverLeavesTheMemoShowingTheUndoneStroke() {
        let base = Self.elements(36)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: base)
        // The memo and the incremental base, so the raced render takes the append path — which is the
        // path a pen-up actually takes and the one an undo actually interrupts.
        _ = canvas.render()

        for round in 0..<40 {
            // Forward edit: one more stroke, declared as an append exactly as `addStroke` does.
            canvas.addStroke(Self.stroke(200 + round))
            let after = canvas.elements
            let version = canvas.version

            // The background render of `version`, racing the undo below. `ifStillAtVersion:` is what
            // `StrokeCanvasView.startVectorRender` uses, so this is the shipped call.
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = canvas.render(quality: .full, ifStillAtVersion: version)
                finished.signal()
            }

            // The undo, on this thread, exactly as `registerVectorUndo`'s closure spells it.
            canvas.restoreElements(base, changedInk: nil)
            finished.wait()

            // **The assertion, and both its operands are shipped code drawing one list.** Whatever
            // the memo holds now must be the picture of the elements the canvas holds now. A walk of
            // `after` installed under the version `base` was restored at would show the undone
            // stroke, and that is exactly the difference this catches.
            let live = canvas.render()
            let cold = coldRender(of: base)
            guard let a = rawPixels(live), let b = rawPixels(cold) else {
                return XCTFail("round \(round): no bitmap to compare")
            }
            XCTAssertEqual(a, b, "round \(round): the canvas's own render disagrees with a cold walk "
                           + "of the elements it currently holds — a render planned before the undo "
                           + "was installed after it, so the memo is a picture of \(after.count) "
                           + "elements filed under a version that has \(base.count)")
            if a != b { return }   // one report is enough; forty would bury it
        }
    }

    /// The same guarantee from the other end of the class: an edit that is *not* an append, so the
    /// raced render is a region repair rather than an append, and the install has to refuse a
    /// `paintedBounds` table measured against a list that has since been replaced.
    func testARestoreLandingDuringARepairNeverLeavesStaleFootprintsBehind() {
        let base = Self.elements(36)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: base)
        _ = canvas.render()

        var longer = base
        longer.append(.stroke(Self.stroke(900)))

        for round in 0..<30 {
            // A region-declaring restore in each direction, which is what puts a `regionBase` up and
            // makes the next render the repair path.
            canvas.restoreElements(longer, changedInk: CGRect(x: 8, y: 8, width: 120, height: 90))
            let version = canvas.version
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = canvas.render(quality: .full, ifStillAtVersion: version)
                finished.signal()
            }
            canvas.restoreElements(base, changedInk: CGRect(x: 8, y: 8, width: 120, height: 90))
            finished.wait()

            let live = canvas.render()
            let cold = coldRender(of: base)
            guard let a = rawPixels(live), let b = rawPixels(cold) else {
                return XCTFail("round \(round): no bitmap to compare")
            }
            XCTAssertEqual(a, b, "round \(round): a repair planned before the restore was installed "
                           + "after it — either its pixels or the footprints it measured, both of "
                           + "which are claims about a display list this canvas no longer holds")
            if a != b { return }
        }
    }

    // MARK: - 2. Two threads asking for one picture stamp it once

    /// **Deterministic whether or not the two calls actually overlap**, which is what makes it a
    /// usable fast-tier test: if they overlap, `rasterizeLock` makes the second wait and find the
    /// memo; if they do not, the second finds the memo anyway. Either way exactly one walk happens.
    /// The mutation that reddens it is removing `rasterizeLock`, and *that* mutation only reds when
    /// the two do overlap — so the barrier below is there to make the overlap likely rather than to
    /// make the assertion true.
    func testTwoThreadsAskingForOnePictureStampItOnce() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: Self.elements(48))
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
                       + "`rasterizeLock` exists so the second waits and reads the memo the first "
                       + "installed, which is what keeps a pen-up to one canvas-sized buffer")
        XCTAssertNotNil(images[0], "the first render returned nothing")
        XCTAssertNotNil(images[1], "the second render returned nothing")
        XCTAssertTrue(images[0] === images[1],
                      "the two threads got different image objects, so the memo was not shared even "
                      + "though only one walk ran")
    }

    // MARK: - 3. The narrowed lock still answers the questions it was narrowed around

    /// A render running does not stop a *reader* either, and this is the cheapest possible statement
    /// of it: `elements`, `version` and `cachedRender()` are all O(1)-ish acquisitions of the state
    /// lock, and none of them may be behind a canvas-sized walk. Asserted structurally — the reads
    /// happen and are self-consistent — rather than in milliseconds, which is `UndoContentionBench`'s
    /// job.
    func testTheStateAccessorsStayAnswerableWhileARenderIsWalking() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: Self.elements(48))
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
            XCTAssertEqual(canvas.elements.count, 48, "the display list changed under a read")
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
