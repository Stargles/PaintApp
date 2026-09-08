import XCTest
import UIKit

/// **What an undo costs while a render is in flight** — the owner's lag spike, isolated.
///
/// > *"When I try to lay strokes down and undo it, I am met with a lot of lagspikes and stutter when
/// > the brush is lifted. … the canvas size should not ever impede on main thread lag."*
///
/// Their document is 6000×6000 — `CanvasManager.maxCanvasExtent` exactly, 36 megapixels — on a 3 GB
/// iPad 9. The `ActionRecorder` trace they sent stamps a `touch` line with the `UITouch`'s hardware
/// timestamp and the `model`/`recognizer` line that follows it with `CACurrentMediaTime()`, both on
/// one clock, so the gap between them is main-thread latency measured rather than inferred:
/// **110, 130, 170, 180 and 220 ms around the undo taps, against a 20 ms median across the file.**
///
/// The mechanism was `VectorCanvas.lock`. It was held across `renderLocked`, an O(canvas-pixel)
/// rasterize dispatched to a background queue by `StrokeCanvasView.startVectorRender` — and
/// `restoreElements(_:changedInk:)`, which `CanvasManager.undo()` reaches synchronously from the
/// two-finger tap, took the same lock. So an undo waited out whatever render was running, and that
/// wait is a function of the canvas's area and of nothing the artist can see.
///
/// **PERFORMANCE.md §11.11a's "undo is 0.44–7.84 ms on the main thread" is true as measured and was
/// never a bound on what the artist waits.** `UndoRepairBench` times one press, waits, times the
/// next; it structurally cannot race a press against a live render, so the number it reports is the
/// uncontended one. This file measures the contended one, which is the one the owner felt.
///
/// **Both operands, and the second is what makes the first mean anything.** Timing a restore proves
/// nothing unless the render it was supposed to be blocked by was genuinely still running when the
/// restore returned — a render that finished first would give a fast restore under the old code too.
/// So every arm asserts `renderStillRunning` before it asserts a duration, and reports the render's
/// own wall clock beside the restore's.
///
/// **MEASURED, this fixture, iPad Pro 13-inch M4 simulator, iOS 26.5, Debug, one slot under
/// `simlock`** — the same binary either side of `VectorLayer.swift`'s lock narrowing, everything else
/// identical:
///
/// | | undo, render in flight | that render | render still running |
/// |---|---|---|---|
/// | 6000², before | **25.57 ms** | 29.7 ms | no |
/// | 6000², after | **1.70 ms** | 29.7 ms | yes |
/// | 3000², before | 3.46 ms | 9.9 ms | no |
/// | 3000², after | 1.18 ms | 9.0 ms | yes |
///
/// Uncontended, for scale: 1.15 ms before, 2.43 ms after — one measurement each, so the difference
/// between those two is noise and the point is that the contended figure has joined them.
///
/// **The before row's undo is the render's whole remainder** — 29.7 ms of render, a 5 ms head start,
/// 25.57 ms of undo — and its `renderStillRunning` came back *false* for that reason rather than
/// because the fixture missed: the undo did not return until the render had finished. That pairing,
/// a false flag beside a duration that matches the render, is the defect's signature and is what the
/// assertion messages below tell you to read in that order. The two renders are 29.7 ms either side,
/// which is what says the rows differ by where the waiting went and not by how much work there was.
///
/// **And the before rows are the owner's sentence in two numbers**: 3.46 ms at 3000², 25.57 ms at
/// 6000², same strokes, same edit — 7.4x the press for 4x the area. The after rows are 1.18 and
/// 1.70. *"The canvas size should not ever impede on main thread lag."*
///
/// Not a `…LogicTests` file, deliberately: CLAUDE.md's fast-tier selector is
/// `LogicTests$|CharacterizationTests$|^PerfBaselineTests$`, and a wall-clock assertion must never be
/// in a tier that runs under parallel clones. Run it by name:
///
/// ```
/// PAINTAPP_BENCH=1 SIMLOCK_SLOTS=1 tools/simlock.sh xcodebuild test \
///   -project PaintSoftware.xcodeproj -scheme PaintSoftware \
///   -destination 'platform=iOS Simulator,id=<udid>' \
///   -only-testing:PaintSoftwareUITests/UndoContentionBench \
///   -parallel-testing-enabled NO -derivedDataPath build/DerivedData
/// ```
final class UndoContentionBench: XCTestCase {

    /// Opt-in for `UndoRepairBench`'s reason: this renders multi-megapixel cels repeatedly.
    ///
    /// **The teardown flag is CLAUDE.md's `PlaybackTickBench` lesson**: `tearDown` runs even when
    /// `setUpWithError` throws `XCTSkip`, so anything torn down here has to be gated past the guard.
    /// Nothing is, today — this is a note for whoever adds the first stored fixture.
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "UndoContentionBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
    }

    // MARK: - The scene
    //
    // The owner's own canvas extent, so the number is theirs rather than a scaled guess.
    // `CanvasManager.maxCanvasExtent` is 6000; the smaller arm is here to show the cost is the
    // area's, which is the half of the complaint that says "the canvas size should not ever impede".

    private static let brush = Brush(name: "Contention", tip: .round, size: 18,
                                     dab: BrushDabSettings(spacing: 0.3))

    private static func stroke(_ index: Int, canvas: CGSize) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset: CGFloat = 64
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        var samples = StrokeSamples(channels: .pressureOnly)
        for step in 0..<32 {
            let t = CGFloat(step) / 31
            samples.append(VectorSample(x: x0 + cos(angle) * t * 380,
                                        y: y0 + sin(angle) * t * 380,
                                        pressure: 0.3 + 0.7 * t))
        }
        return VectorStroke(brush: brush, color: CodableColor(red: 0.1, green: 0.1, blue: 0.1,
                                                              alpha: 1),
                            size: 18, opacity: 1, samples: samples, composite: .paint,
                            seed: UInt64(index &+ 1))
    }

    // MARK: - One arm

    private struct Arm {
        let renderSeconds: Double
        let restoreSeconds: Double
        let renderStillRunning: Bool
    }

    /// Lays `strokes` on a `size` canvas, memoizes it, appends one more, then starts the background
    /// render of that append and times an undo against it — the owner's exact sequence, in the exact
    /// two calls the app makes (`StrokeCanvasView.startVectorRender`'s
    /// `render(quality:ifStillAtVersion:)`, and `registerVectorUndo`'s `restoreElements`).
    private func measureContendedUndo(size: CGSize, strokes: Int) -> Arm {
        let before: [VectorElement] = (0..<strokes).map { .stroke(Self.stroke($0, canvas: size)) }
        let canvas = VectorCanvas(size: size, elements: before)
        // Warm: the memo and the incremental base, so the raced render is the append path a pen-up
        // actually takes rather than a cold full walk. It is *still* canvas-sized work — the base is
        // blitted into a fresh canvas-sized context — which is the point.
        _ = canvas.render()
        canvas.addStroke(Self.stroke(strokes, canvas: size))
        let version = canvas.version

        let entered = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        var renderSeconds = 0.0
        DispatchQueue.global(qos: .userInitiated).async {
            entered.signal()
            let t0 = CACurrentMediaTime()
            _ = canvas.render(quality: .full, ifStillAtVersion: version)
            renderSeconds = CACurrentMediaTime() - t0
            finished.signal()
        }
        // `entered` says the thread is about to call, not that it is inside the walk. The sleep is
        // what makes the overlap real, and it is a compromise in both directions: too short and the
        // restore lands before the render has planned, too long and a small canvas's render is over
        // before the restore starts. MEASURED at 15 ms it was over: the 3000² arm reported
        // `renderStillRunning: NO`, i.e. it measured nothing, which is exactly what the flag is for.
        entered.wait()
        Thread.sleep(forTimeInterval: 0.005)

        let t0 = CACurrentMediaTime()
        canvas.restoreElements(before, changedInk: nil)
        let restoreSeconds = CACurrentMediaTime() - t0
        // **Taken before the join**: this is the operand that says the restore was actually racing
        // something. Without it a fast restore proves only that the render had already finished.
        //
        // A `DispatchSemaphore` is a counter, so a poll that succeeds has *consumed* the signal and
        // must not be followed by another `wait()` — that is a hang, and it is the one this file's
        // first draft had.
        let stillRunning = finished.wait(timeout: .now()) == .timedOut
        if stillRunning { finished.wait() }
        return Arm(renderSeconds: renderSeconds, restoreSeconds: restoreSeconds,
                   renderStillRunning: stillRunning)
    }

    private func report(_ label: String, _ arm: Arm) {
        print(String(format: "[UndoContentionBench] %@: render %.1f ms, undo %.2f ms, "
                     + "render still running when the undo returned: %@",
                     label, arm.renderSeconds * 1000, arm.restoreSeconds * 1000,
                     arm.renderStillRunning ? "yes" : "NO — this arm measured nothing"))
    }

    /// The uncontended baseline, so the contended arms have something honest to be compared with.
    /// This is the shape `UndoRepairBench` measures and PERFORMANCE.md §11.11a reports.
    func testWhatAnUndoCostsWithNothingRendering() {
        let size = CGSize(width: 6000, height: 6000)
        let before: [VectorElement] = (0..<300).map { .stroke(Self.stroke($0, canvas: size)) }
        let canvas = VectorCanvas(size: size, elements: before)
        _ = canvas.render()
        canvas.addStroke(Self.stroke(300, canvas: size))
        _ = canvas.render()               // let it finish, so nothing is in flight

        let t0 = CACurrentMediaTime()
        canvas.restoreElements(before, changedInk: nil)
        let seconds = CACurrentMediaTime() - t0
        print(String(format: "[UndoContentionBench] 6000² uncontended: undo %.2f ms", seconds * 1000))
        XCTAssertLessThan(seconds, 0.100,
                          "an undo with nothing to contend against took \(seconds * 1000) ms; this "
                          + "arm is the O(element-count) bookkeeping alone and is not what this "
                          + "file is about")
    }

    /// **The owner's canvas.** 6000×6000 is `CanvasManager.maxCanvasExtent` and is what `Test1` is.
    func testAnUndoDoesNotWaitOutARenderOnTheOwnersCanvas() {
        let arm = measureContendedUndo(size: CGSize(width: 6000, height: 6000), strokes: 300)
        report("6000² contended", arm)
        // **The ratio is the assertion that actually catches the defect, and the absolute one below
        // is the artist-facing claim.** MEASURED against the pre-fix `VectorLayer.swift` on this same
        // fixture: undo **25.57 ms** against a render of **29.7 ms**, i.e. the whole remainder of the
        // render after this method's 5 ms head start. That is under 50 ms, so on a machine this fast
        // the absolute bound does not see it at all — it is sized for the owner's iPad, where the
        // same render is hundreds of milliseconds.
        XCTAssertLessThan(arm.restoreSeconds, arm.renderSeconds / 3,
                          "the undo cost \(arm.restoreSeconds * 1000) ms against a render of "
                          + "\(arm.renderSeconds * 1000) ms; an undo that scales with the render is "
                          + "an undo that is waiting for it, which is `VectorCanvas.lock` covering "
                          + "the pixels again")
        XCTAssertLessThan(arm.restoreSeconds, 0.050,
                          "the undo took \(arm.restoreSeconds * 1000) ms while a render of "
                          + "\(arm.renderSeconds * 1000) ms was walking")
        // **A false flag here has two readings and the duration above tells them apart**, so read
        // them in that order rather than reaching for the fixture. Either the render outran a fixture
        // that is now too small for this machine — in which case the two assertions above passed —
        // or **the restore waited the render out**, which is the defect, and then this is not the
        // first red on the list. The pre-fix run reported exactly that pairing.
        XCTAssertTrue(arm.renderStillRunning,
                      "the render was over when the undo returned. If the assertions above passed, "
                      + "this fixture no longer overlaps and wants more strokes or a bigger canvas; "
                      + "if they failed, the undo blocked until the render finished and the flag is "
                      + "the symptom rather than the fixture")
    }

    /// **The same fixture at a quarter of the area**, which is the half of the owner's sentence that
    /// says *"the canvas size should not ever impede on main thread lag"*.
    ///
    /// **The claim is made on the two render durations, not on the two undo durations**, and that is
    /// deliberate rather than a weakening. The strokes are identical between the arms, so the dabs
    /// are identical; whatever the renders differ by is the buffer, and if the render tracks the area
    /// while the undo does not then the undo has stopped being a function of the canvas. Asserting it
    /// the other way round — comparing two undo durations of a few milliseconds each — would be
    /// asserting on scheduler noise.
    func testTheRendersCostFollowsTheCanvasAreaAndTheUndosDoesNot() {
        let big = measureContendedUndo(size: CGSize(width: 6000, height: 6000), strokes: 300)
        let small = measureContendedUndo(size: CGSize(width: 3000, height: 3000), strokes: 300)
        report("6000² contended", big)
        report("3000² contended", small)
        // Required on the big arm, which is the owner's canvas and the one the headline rests on.
        // Reported on the small arm: at a quarter of the area its render can legitimately be over
        // before the restore starts, and that is a fact about the fixture rather than a failure.
        XCTAssertTrue(big.renderStillRunning,
                      "the 6000² arm was not racing a live render, so it measured nothing")
        XCTAssertGreaterThan(big.renderSeconds, small.renderSeconds * 2,
                             "the 6000² render took \(big.renderSeconds * 1000) ms against the "
                             + "3000² render's \(small.renderSeconds * 1000) ms on identical "
                             + "strokes — four times the area is supposed to cost roughly four "
                             + "times the render, and if it does not then this fixture is not "
                             + "measuring the canvas-sized buffer it was built to")
        XCTAssertLessThan(big.restoreSeconds, 0.050,
                          "the 6000² undo took \(big.restoreSeconds * 1000) ms")
        XCTAssertLessThan(small.restoreSeconds, 0.050,
                          "the 3000² undo took \(small.restoreSeconds * 1000) ms")
    }
}
