import XCTest
import CoreGraphics

/// Pure-logic tests for `VectorEraser` — the per-mode geometry of Phase 2 of
/// `VECTOR_ERASER_PLAN.md`, sitting on top of the `StrokeGeometry` primitives
/// `StrokeGeometryLogicTests` already covers.
///
/// Same arrangement as that file: `VectorEraser.swift` is compiled into this target as well as the
/// app, so its types are local to this module — no `@testable import PaintSoftware`, which would make
/// every name ambiguous between the two copies.
///
/// The four tests named `…RegressionOfDefectN` are the four defects the pre-Phase-2 implementation
/// had (plan §4). Each fails against that implementation by construction, which is the only way to
/// know the rewrite actually bought something.
final class VectorEraserLogicTests: XCTestCase {

    // MARK: - Helpers

    private func samples(_ points: [(CGFloat, CGFloat)], pressure: CGFloat = 0.5) -> [VectorSample] {
        points.map { VectorSample(x: $0.0, y: $0.1, pressure: pressure) }
    }

    /// A horizontal run from `(0, 0)` to `(100, 0)` sampled every 10 points, so parametric position
    /// `p` sits at `x == 10p` and an expected cut reads directly off the geometry.
    private var horizontalRun: [VectorSample] {
        samples((0...10).map { (CGFloat($0) * 10, 0) })
    }

    /// `BrushDynamics.fixed` makes `sizeFraction` exactly 1 at any pressure, so the eraser's radius
    /// is exactly `size / 2` and a failure can only come from the geometry under test.
    private func fixedBrush(size: CGFloat = 10) -> Brush {
        Brush(name: "test", shape: .hardRound, size: size, dynamics: .fixed)
    }

    private func sweep(_ points: [(CGFloat, CGFloat)], size: CGFloat,
                       mode: VectorEraserMode = .cutPoints) -> VectorEraser.Sweep {
        guard let sweep = VectorEraser.Sweep(samples: samples(points), brush: fixedBrush(size: size),
                                            size: size, mode: mode) else {
            preconditionFailure("a non-empty gesture always has a footprint")
        }
        return sweep
    }

    /// `cutRanges` emits one range per segment it walks, so abutting pieces of a single cut arrive
    /// separately. Merging is what `splitStroke` does with them anyway, and it is the merged form a
    /// test can state an expectation about.
    private func mergedCuts(in run: [VectorSample], _ sweep: VectorEraser.Sweep) -> [ClosedRange<CGFloat>] {
        StrokeGeometry.mergedCuts(VectorEraser.cutRanges(in: run, sweep: sweep),
                                  clampedTo: 0...CGFloat(run.count - 1))
    }

    private func assertCut(_ cuts: [ClosedRange<CGFloat>], _ low: CGFloat, _ high: CGFloat,
                           accuracy: CGFloat = 1e-3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(cuts.count, 1, "expected exactly one merged span", file: file, line: line)
        guard let cut = cuts.first else { return }
        XCTAssertEqual(cut.lowerBound, low, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(cut.upperBound, high, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Sweep

    func testSweepContainsIsTheEraserFootprintNotItsTouchPoints() {
        // Two touch samples 100 apart with a radius-10 nib. The midpoint is 50 from either sample and
        // yet squarely under the swept capsule.
        let s = sweep([(0, 0), (100, 0)], size: 20)
        XCTAssertTrue(s.contains(CGPoint(x: 50, y: 0)))
        XCTAssertTrue(s.contains(CGPoint(x: 50, y: 9.9)))
        XCTAssertFalse(s.contains(CGPoint(x: 50, y: 10.1)))
        XCTAssertFalse(s.contains(CGPoint(x: -10.1, y: 0)))
    }

    func testSweepOfNoSamplesHasNoFootprint() {
        XCTAssertNil(VectorEraser.Sweep(samples: [], brush: fixedBrush(), size: 10, mode: .cutPoints))
    }

    // MARK: - Segment/rect clipping

    func testClipParametersNarrowsToTheOverlap() {
        let rect = CGRect(x: 40, y: -10, width: 20, height: 20)
        let clip = VectorEraser.clipParameters(of: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), to: rect)
        XCTAssertEqual(clip?.0 ?? -1, 0.4, accuracy: 1e-9)
        XCTAssertEqual(clip?.1 ?? -1, 0.6, accuracy: 1e-9)
    }

    func testClipParametersRejectsAMiss() {
        let rect = CGRect(x: 40, y: 50, width: 20, height: 20)
        XCTAssertNil(VectorEraser.clipParameters(of: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), to: rect))
    }

    func testClipParametersKeepsAWhollyContainedSegment() {
        let rect = CGRect(x: -10, y: -10, width: 200, height: 20)
        let clip = VectorEraser.clipParameters(of: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), to: rect)
        XCTAssertEqual(clip?.0 ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(clip?.1 ?? -1, 1, accuracy: 1e-9)
    }

    // MARK: - Modes 1 and 2: cut along the footprint

    func testSquareCrossingCutsExactlyTheFootprintWidth() {
        // A radius-10 dab centred at x == 50 covers x ∈ [40, 60], i.e. parameters 4...6.
        assertCut(mergedCuts(in: horizontalRun, sweep([(50, 0)], size: 20)), 4, 6)
    }

    func testCutBoundariesLandOffSampleWhereTheFootprintEdgeIs() {
        // Deliberately chosen so neither edge coincides with a stored sample: a radius-7 dab at
        // x == 55 covers x ∈ [48, 62] → parameters 4.8...6.2. The pre-Phase-2 implementation could
        // only ever cut at whole samples, so this is the "ragged edge" defect stated numerically.
        assertCut(mergedCuts(in: horizontalRun, sweep([(55, 0)], size: 14)), 4.8, 6.2)
    }

    func testAMissCutsNothing() {
        XCTAssertTrue(mergedCuts(in: horizontalRun, sweep([(50, 100)], size: 20)).isEmpty)
    }

    func testAGrazeOutsideTheStrokeCutsNothing() {
        // Radius 10, centred 10.5 away from the centreline: the footprint reaches 10, so it misses.
        XCTAssertTrue(mergedCuts(in: horizontalRun, sweep([(50, 10.5)], size: 20)).isEmpty)
    }

    func testFullCoverageRemovesTheWholeStroke() {
        let cuts = mergedCuts(in: horizontalRun, sweep([(50, 0)], size: 400))
        assertCut(cuts, 0, 10)
        XCTAssertTrue(StrokeGeometry.splitStroke(horizontalRun, removing: cuts).isEmpty)
    }

    func testACrossingSplitsTheStrokeInTwoAtTheFootprintEdges() {
        let cuts = mergedCuts(in: horizontalRun, sweep([(50, 0)], size: 20))
        let runs = StrokeGeometry.splitStroke(horizontalRun, removing: cuts)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.first?.last?.x ?? -1, 40, accuracy: 1e-3)
        XCTAssertEqual(runs.last?.first?.x ?? -1, 60, accuracy: 1e-3)
    }

    func testInterpolatedBoundaryCarriesThePressureTheStrokeHadThere() {
        // Pressure ramps 0 → 1 across the run, so the boundary at parameter 4.8 must arrive at 0.48
        // rather than snapping to a stored sample's 0.4 or 0.5.
        let ramped = (0...10).map { VectorSample(x: CGFloat($0) * 10, y: 0, pressure: CGFloat($0) / 10) }
        let cuts = mergedCuts(in: ramped, sweep([(55, 0)], size: 14))
        let runs = StrokeGeometry.splitStroke(ramped, removing: cuts)
        XCTAssertEqual(runs.first?.last?.pressure ?? -1, 0.48, accuracy: 1e-3)
    }

    func testALoneDabIsHitOrMissed() {
        let dab = samples([(50, 0)])
        XCTAssertTrue(StrokeGeometry.splitStroke(dab, removing: mergedCuts(in: dab, sweep([(50, 0)], size: 20))).isEmpty)
        XCTAssertEqual(StrokeGeometry.splitStroke(dab, removing: mergedCuts(in: dab, sweep([(100, 0)], size: 20))).count, 1)
    }

    /// A stationary finger emits coincident samples, so a stroke can carry zero-length segments with
    /// no extent to probe. The cut must still come out as one span covering them — the degenerate
    /// parameters lie *inside* the erased region, and fragmenting there would leave a sliver of a
    /// stroke sitting in the middle of the hole the user just made.
    func testRepeatedSamplesDoNotFragmentTheCut() {
        let run = samples([(0, 0), (50, 0), (50, 0), (50, 0), (100, 0)])
        assertCut(mergedCuts(in: run, sweep([(50, 0)], size: 20)), 0.8, 3.2)
        XCTAssertEqual(StrokeGeometry.splitStroke(run, removing: mergedCuts(in: run, sweep([(50, 0)], size: 20))).count, 2)
    }

    // MARK: - The four pre-Phase-2 defects

    /// Defect 1 — point-to-point distance. A small nib dragged between two coarsely-sampled touches
    /// existed only *at* those touches, so a stroke crossing the gap survived untouched.
    func testCoarseEraserSamplingStillCutsBetweenThem_regressionOfDefect1() {
        let vertical = samples((-5...5).map { (50, CGFloat($0) * 10) })
        // Touches at x == 0 and x == 100 only; the stroke crosses at x == 50, exactly halfway.
        let cuts = mergedCuts(in: vertical, sweep([(0, 0), (100, 0)], size: 20))
        assertCut(cuts, 4, 6)
    }

    /// Defect 2 — cuts landed at sample granularity. Covered numerically by
    /// `testCutBoundariesLandOffSampleWhereTheFootprintEdgeIs`; this states the user-visible half:
    /// the two surviving ends sit at the eraser's edge, not at whichever samples happened to be near.
    func testCutEdgesFollowTheEraserNotTheSampleGrid_regressionOfDefect2() {
        let runs = StrokeGeometry.splitStroke(horizontalRun,
                                              removing: mergedCuts(in: horizontalRun, sweep([(55, 0)], size: 14)))
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.first?.last?.x ?? -1, 48, accuracy: 1e-2)
        XCTAssertEqual(runs.last?.first?.x ?? -1, 62, accuracy: 1e-2)
    }

    /// Defect 3 — a coarse stroke was judged at its vertices, so a small nib between two distant
    /// samples either erased the whole span or nothing at all. Here the nearest stored sample is
    /// 100 points from the eraser and the cut must still land.
    func testCoarseStrokeIsCutWhereTheNibActuallyPassed_regressionOfDefect3() {
        let coarse = samples([(0, 0), (200, 0)])
        // Radius-5 nib at x == 100 covers x ∈ [95, 105] → parameters 0.475...0.525.
        assertCut(mergedCuts(in: coarse, sweep([(100, 0)], size: 10)), 0.475, 0.525)
    }

    /// Defect 4 — cost. Not a timing assertion (those are `PerfBaselineTests`' job); this pins the
    /// *mechanism* the speed-up rests on, that a segment nowhere near the eraser is rejected by the
    /// box clip before a single containment test runs.
    func testSegmentsOutsideTheSweptBoxAreRejectedByTheClip_regressionOfDefect4() {
        let s = sweep([(50, 0)], size: 20)
        XCTAssertNil(VectorEraser.clipParameters(of: CGPoint(x: 0, y: 500), CGPoint(x: 100, y: 500),
                                                 to: s.bounds))
    }

    // MARK: - Mode 3: cut to intersection

    private func crossing(atX x: CGFloat) -> (points: [CGPoint], tolerance: CGFloat) {
        ([CGPoint(x: x, y: -20), CGPoint(x: x, y: 20)], 0)
    }

    func testCutsBetweenTheTwoBracketingCrossings() {
        let cuts = VectorEraser.cutToIntersection(in: horizontalRun, at: 5,
                                                  others: [crossing(atX: 30), crossing(atX: 70)])
        assertCut(cuts, 3, 7, accuracy: 1e-9)
    }

    func testIgnoresCrossingsBeyondTheNearestOnesOnEachSide() {
        let cuts = VectorEraser.cutToIntersection(
            in: horizontalRun, at: 5,
            others: [crossing(atX: 10), crossing(atX: 30), crossing(atX: 70), crossing(atX: 90)])
        assertCut(cuts, 3, 7, accuracy: 1e-9)
    }

    func testClampsToTheStrokeEndWhereThereIsNoCrossing() {
        assertCut(VectorEraser.cutToIntersection(in: horizontalRun, at: 5, others: [crossing(atX: 30)]),
                  3, 10, accuracy: 1e-9)
        assertCut(VectorEraser.cutToIntersection(in: horizontalRun, at: 5, others: [crossing(atX: 70)]),
                  0, 7, accuracy: 1e-9)
    }

    /// Clip Studio's *erase whole line* mode, arriving for free: clamping both ends of "the span
    /// between the neighbouring crossings" when there are no crossings is the whole stroke.
    func testAStrokeWithNoCrossingsIsDeletedWhole() {
        let cuts = VectorEraser.cutToIntersection(in: horizontalRun, at: 5, others: [])
        assertCut(cuts, 0, 10, accuracy: 1e-9)
        XCTAssertTrue(StrokeGeometry.splitStroke(horizontalRun, removing: cuts).isEmpty)
    }

    /// Width-aware, as Clip Studio is: two lines whose ink visibly touches read as crossed to the
    /// user even though their centrelines miss. The near line stops 2 points short of the stroke.
    func testNearContactCountsAsACrossingWithinTolerance() {
        let near = ([CGPoint(x: 30, y: -20), CGPoint(x: 30, y: -2)], CGFloat(5))
        assertCut(VectorEraser.cutToIntersection(in: horizontalRun, at: 5, others: [near]), 3, 10)
    }

    func testNearContactOutsideToleranceIsNotACrossing() {
        let far = ([CGPoint(x: 30, y: -20), CGPoint(x: 30, y: -2)], CGFloat(1))
        assertCut(VectorEraser.cutToIntersection(in: horizontalRun, at: 5, others: [far]), 0, 10)
    }

    // MARK: - Mode 3: the gesture driver (Phase 3)
    //
    // Phase 2 shipped the geometry above and resolved it once, on lift, against the gesture's first
    // sample. Phase 3 is the gesture semantics on top: cut on touch-**down**, re-query per crossing so
    // one drag across three lines cuts three spans, and one undo entry for the whole drag.
    //
    // These drive a real `VectorCanvas` through exactly the loop `StrokeCanvasView` runs — resolve at
    // `cutting: driver.isArmed`, feed the outcome back — so what is under test is the shipped rule
    // rather than a paraphrase of it. The view itself is not in this target; the latch was factored
    // into `VectorEraser.IntersectionDriver` precisely so this could be checked here.

    /// A vertical line at `x`, running well past both rails so a cut leaves a stub at each end.
    private func verticalLine(atX x: CGFloat) -> VectorStroke {
        VectorStroke(brush: fixedBrush(size: 4), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 4, opacity: 1, samples: samples([(x, 20), (x, 180)], pressure: 1))
    }

    /// A horizontal rail at `y`, spanning the whole width, so it crosses every vertical line.
    private func rail(atY y: CGFloat) -> VectorStroke {
        VectorStroke(brush: fixedBrush(size: 4), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 4, opacity: 1, samples: samples([(0, y), (200, y)], pressure: 1))
    }

    /// Three vertical lines at x = 30/60/90, each crossed by rails at y = 40 and y = 140. An eraser at
    /// y = 90 is squarely between the rails, so a cut on any vertical removes its middle and leaves
    /// two stubs — 5 strokes to start, 8 once all three are cut.
    private func laddersCanvas() -> VectorCanvas {
        VectorCanvas(size: CGSize(width: 200, height: 200),
                     strokes: [verticalLine(atX: 30), verticalLine(atX: 60), verticalLine(atX: 90),
                               rail(atY: 40), rail(atY: 140)])
    }

    /// One position pumped through the canvas and the driver, exactly as `StrokeCanvasView
    /// .resolveIntersectionCut` does.
    @discardableResult
    private func pump(_ canvas: VectorCanvas, _ driver: inout VectorEraser.IntersectionDriver,
                      to point: CGPoint, nib: CGFloat = 6) -> VectorEraser.CutOutcome {
        let outcome = canvas.cutToIntersection(atCanvasPoint: point, pressure: 1,
                                               brush: fixedBrush(size: nib), size: nib,
                                               cutting: driver.isArmed)
        driver.accept(outcome)
        return outcome
    }

    /// The headline Phase 3 behaviour. One drag across three lines cuts three spans — which the
    /// lift-time implementation could not do at all, since it resolved a single target against the
    /// gesture's first sample and ignored everything the drag went on to touch.
    func testOneDragAcrossThreeLinesCutsThreeSpans() {
        let canvas = laddersCanvas()
        var driver = VectorEraser.IntersectionDriver()
        XCTAssertEqual(canvas.strokes.count, 5)

        for x in stride(from: CGFloat(10), through: 110, by: 5) {
            pump(canvas, &driver, to: CGPoint(x: x, y: 90))
        }

        // Each vertical lost its middle span and became two stubs; both rails are untouched.
        XCTAssertEqual(canvas.strokes.count, 8)
        XCTAssertTrue(driver.didCut)
        for x in [CGFloat(30), 60, 90] {
            let stubs = canvas.strokes.filter { $0.samples.allSatisfy { abs($0.x - x) < 0.001 } }
            XCTAssertEqual(stubs.count, 2, "the line at x = \(x) should be in two pieces")
        }
    }

    /// Touch-**down**, not lift: the very first position of the gesture has already cut.
    func testTheFirstPositionOfTheGestureCuts() {
        let canvas = laddersCanvas()
        var driver = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(canvas, &driver, to: CGPoint(x: 30, y: 90)), .cut)
        XCTAssertEqual(canvas.strokes.count, 6)
    }

    /// The reason the driver latches at all, stated as a test.
    ///
    /// Mode 3 removes the span between the target's *neighbouring crossings*, and those can sit right
    /// under the finger — here the tip is 2 points below the rail it just cut back to. Resolving again
    /// at the same position finds the surviving stub, whose only crossing is at its own endpoint and
    /// therefore brackets nothing, so the stub is deleted whole. Repeat per touch sample and a
    /// stationary finger eats the line. The second half of this test is that exact runaway, which is
    /// what makes the first half evidence rather than a coincidence.
    func testTheLatchStopsAStationaryTipFromEatingTheSurvivingStub() {
        let tip = CGPoint(x: 30, y: 42)

        let latched = VectorCanvas(size: CGSize(width: 200, height: 200),
                                   strokes: [verticalLine(atX: 30), rail(atY: 40), rail(atY: 140)])
        var driver = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(latched, &driver, to: tip), .cut)
        // Still over the stub, so the driver stays disarmed and the second resolve reports rather
        // than removes.
        XCTAssertEqual(pump(latched, &driver, to: tip), .unchanged)
        XCTAssertFalse(driver.isArmed)
        XCTAssertEqual(latched.strokes.count, 4, "cut vertical (2 stubs) + 2 rails")

        // Same two positions with the latch defeated: the stub goes too.
        let unlatched = VectorCanvas(size: CGSize(width: 200, height: 200),
                                     strokes: [verticalLine(atX: 30), rail(atY: 40), rail(atY: 140)])
        let nib = fixedBrush(size: 6)
        unlatched.cutToIntersection(atCanvasPoint: tip, pressure: 1, brush: nib, size: 6)
        unlatched.cutToIntersection(atCanvasPoint: tip, pressure: 1, brush: nib, size: 6)
        XCTAssertEqual(unlatched.strokes.count, 3, "the stub under the tip was deleted whole")
    }

    /// Leaving the ink re-arms, which is what makes "per crossing" mean per crossing rather than per
    /// touch sample.
    func testLeavingTheInkRearmsTheDriver() {
        let canvas = laddersCanvas()
        var driver = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(canvas, &driver, to: CGPoint(x: 30, y: 90)), .cut)
        XCTAssertFalse(driver.isArmed)
        XCTAssertEqual(pump(canvas, &driver, to: CGPoint(x: 45, y: 90)), .missed)
        XCTAssertTrue(driver.isArmed)
    }

    /// `cutting: false` has to be a pure query — the driver uses it on every disarmed sample, so if it
    /// mutated, the latch would be worse than useless.
    func testResolvingWithCuttingFalseNeverMutates() {
        let canvas = laddersCanvas()
        let before = canvas.strokes.map(\.id)
        let outcome = canvas.cutToIntersection(atCanvasPoint: CGPoint(x: 30, y: 90), pressure: 1,
                                               brush: fixedBrush(size: 6), size: 6, cutting: false)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(canvas.strokes.map(\.id), before)
    }

    /// A gesture that never touches anything reports so, so its owner can skip registering an undo
    /// step that would undo nothing.
    func testADragOverEmptySpaceCutsNothing() {
        let canvas = laddersCanvas()
        var driver = VectorEraser.IntersectionDriver()
        for y in stride(from: CGFloat(80), through: 100, by: 5) {
            XCTAssertEqual(pump(canvas, &driver, to: CGPoint(x: 150, y: y)), .missed)
        }
        XCTAssertFalse(driver.didCut)
        XCTAssertEqual(canvas.strokes.count, 5)
    }
}
