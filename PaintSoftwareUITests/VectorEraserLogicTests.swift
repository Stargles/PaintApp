import XCTest
import CoreGraphics

/// Pure-logic tests for `VectorEraser` — the per-mode geometry, sitting on top of the
/// `StrokeGeometry` primitives `StrokeGeometryLogicTests` already covers.
///
/// Same arrangement as that file: `VectorEraser.swift` is compiled into this target as well as the
/// app, so its types are local to this module — no `@testable import PaintSoftware`, which would make
/// every name ambiguous between the two copies.
///
/// The four tests named `…RegressionOfDefectN` are the four defects the earlier point-sampled
/// implementation had. Each fails against that implementation by construction, which is the only
/// way to know the rewrite actually bought something.
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
        // x == 55 covers x ∈ [48, 62] → parameters 4.8...6.2. A sample-granularity implementation
        // could only ever cut at whole samples, so this is the "ragged edge" defect stated numerically.
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

    // MARK: - The four defects a sample-granularity eraser had

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

    // MARK: - Mode 3: the gesture driver
    //
    // Gesture semantics on top of the geometry above: cut on touch-**down**, re-query per crossing
    // so one drag across three lines cuts three spans, and one undo entry for the whole drag.
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
        let resolved = canvas.cutToIntersection(atCanvasPoint: point, brush: fixedBrush(size: nib), size: nib,
                                                suppressing: driver.suppressed)
        driver.accept(resolved.outcome, underTip: resolved.underTip)
        return resolved.outcome
    }

    /// One drag across three lines cuts three spans — which a lift-time-only implementation could
    /// not do at all, since it resolves a single target against the gesture's first sample and
    /// ignores everything the drag went on to touch.
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
    /// under the finger. Resolving again at the same position finds the surviving piece, whose only
    /// contact is at its own endpoint and therefore brackets nothing, so the piece is deleted whole.
    /// Repeat per touch sample and a stationary finger eats the line. The second half of this test is
    /// that exact runaway, which is what makes the first half evidence rather than a coincidence.
    ///
    /// The geometry is a *near* contact, not a crossing, and that is deliberate: since 2026-08-18 a
    /// crossing under the tip is not an obstacle, so a cut made against a crossing always ends outside
    /// the footprint and a surviving piece cannot still be under it. A near contact is reported at the
    /// midpoint of the gap between the two centrelines, which can sit outside the footprint while the
    /// cut it produces — on this stroke's own centreline — sits inside. That is where a stationary tip
    /// can still chew, and the whole reason the latch survives the redesign.
    func testTheLatchStopsAStationaryTipFromEatingTheSurvivingPiece() {
        // Rail's ink stops 6pt short of the run; both are 8 wide, so the width-aware tolerance is 8
        // and they read as touching. Contact point (50, 97); cut boundary (50, 100).
        func canvas() -> VectorCanvas {
            VectorCanvas(size: CGSize(width: 200, height: 200), strokes: [
                VectorStroke(brush: fixedBrush(size: 8), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                             size: 8, opacity: 1, samples: samples([(0, 100), (100, 100)], pressure: 1)),
                VectorStroke(brush: fixedBrush(size: 8), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                             size: 8, opacity: 1, samples: samples([(50, 60), (50, 94)], pressure: 1))])
        }
        // 4.5pt radius: 5.0 from the contact point (an obstacle) and 4.0 from the cut boundary (under
        // the tip). One position, both sides of the rule.
        let tip = CGPoint(x: 54, y: 100)

        let latched = canvas()
        var driver = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(latched, &driver, to: tip, nib: 9), .cut)
        XCTAssertEqual(latched.strokes.count, 2)
        XCTAssertEqual(latched.strokes[0].samples.last?.x ?? -1, 50, accuracy: 0.01,
                       "the run is cut back to where the rail's ink reaches it")
        // Still over the surviving piece, so it stays suppressed and the second resolve reports
        // rather than removes.
        XCTAssertEqual(pump(latched, &driver, to: tip, nib: 9), .unchanged)
        XCTAssertEqual(latched.strokes.count, 2)
        XCTAssertEqual(latched.strokes[0].samples.last?.x ?? -1, 50, accuracy: 0.01)

        // Same two positions with the latch defeated: the piece goes too.
        let unlatched = canvas()
        let nib = fixedBrush(size: 9)
        unlatched.cutToIntersection(atCanvasPoint: tip, brush: nib, size: 9)
        unlatched.cutToIntersection(atCanvasPoint: tip, brush: nib, size: 9)
        XCTAssertEqual(unlatched.strokes.count, 1, "the piece under the tip was deleted whole")
    }

    /// Leaving the ink re-arms, which is what makes "per crossing" mean per crossing rather than per
    /// touch sample.
    func testLeavingTheInkRearmsTheDriver() {
        let canvas = laddersCanvas()
        var driver = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(canvas, &driver, to: CGPoint(x: 30, y: 90)), .cut)
        XCTAssertEqual(pump(canvas, &driver, to: CGPoint(x: 45, y: 90)), .missed)
        XCTAssertTrue(driver.suppressed.isEmpty, "nothing under the tip re-arms every stroke")
    }

    /// Suppressing everything has to be a pure query — the driver suppresses whatever it is sitting on
    /// on every sample, so if a suppressed resolve mutated, the latch would be worse than useless.
    func testResolvingWithEverythingSuppressedNeverMutates() {
        let canvas = laddersCanvas()
        let before = canvas.strokes.map(\.id)
        let resolved = canvas.cutToIntersection(atCanvasPoint: CGPoint(x: 30, y: 90), brush: fixedBrush(size: 6), size: 6,
                                                suppressing: Set(before))
        XCTAssertEqual(resolved.outcome, .unchanged)
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

    // MARK: - Mode 3: the stub, measured in points
    //
    // The owner, on device, 2026-08-18: *"I want it to erase the lines right at the point that the line
    // crosses the center of another line, but in many cases it leaves stubs."*
    //
    // Every Mode-3 test above spaces its samples 10 points apart — wider than any width-aware
    // tolerance — and that is the only reason none of them caught this. A real stroke arrives sampled
    // every point or two, while the tolerance is the sum of two brush half-widths, 10 to 20 points, and
    // in that regime `StrokeGeometry.intersections(between:and:tolerance:)` used to spray roughly one
    // "crossing" per sample across the whole tolerance disk around a real one. The bracket then took
    // the entry nearest the touch and the erase stopped short by `tolerance / sin(angle)`.
    //
    // These assert the *distance in points* between the cut and the true crossing. "Did it cut" was
    // already green; "how far short" is the entire bug.

    /// A run from `(0, 0)` to `(200, 0)` sampled every `spacing` points, crossed at `(70, 0)` by a
    /// straight line `degrees` off it, and a touch at `x = 40`. Answers how far the cut boundary lands
    /// from the true crossing — the length of the stub the owner reported.
    private func stubLength(crossingAt degrees: CGFloat, tolerance: CGFloat,
                            spacing: CGFloat = 1) -> CGFloat {
        let run = samples(stride(from: CGFloat(0), through: 200, by: spacing).map { ($0, CGFloat(0)) })
        let radians = degrees * .pi / 180
        var crosser: [CGPoint] = []
        var along: CGFloat = -120
        while along <= 120 {
            crosser.append(CGPoint(x: 70 + cos(radians) * along, y: sin(radians) * along))
            along += spacing
        }
        guard let touch = StrokeGeometry.closestPoint(onPolyline: run, to: CGPoint(x: 40, y: 0)),
              let cut = VectorEraser.cutToIntersection(in: run, at: touch.parameter,
                                                       others: [(crosser, tolerance)]).first,
              let boundary = StrokeGeometry.interpolatedSample(in: run, at: cut.upperBound)
        else { return .infinity }
        return abs(boundary.x - 70)
    }

    /// Measured against the implementation this replaced, same six configurations: 10.0, 18.0, 22.0,
    /// 29.0 and 29.0 points of stub, and 0.0 only for the `tolerance == 0` control that skips the
    /// tolerant path entirely. Shallow crossings are far worse than square ones — the stub is
    /// `tolerance / sin(angle)` — which is why the owner said *"in many cases"* rather than "always".
    func testTheCutLandsOnTheCrossingAtRealisticSampleDensity() {
        for (degrees, tolerance) in [(CGFloat(90), CGFloat(10)), (90, 18), (26, 10), (11, 10), (11, 18)] {
            XCTAssertEqual(stubLength(crossingAt: degrees, tolerance: tolerance), 0, accuracy: 0.01,
                           "a \(degrees)° crossing at tolerance \(tolerance) left a stub")
        }
    }

    /// Same, three points between samples — a quick stroke rather than a slow one — where the crossing
    /// falls *between* two samples rather than on one. 19.25 points of stub before.
    func testTheCutLandsOnTheCrossingAtCoarseSampleDensityToo() {
        XCTAssertEqual(stubLength(crossingAt: 26, tolerance: 10, spacing: 3), 0, accuracy: 0.01)
        XCTAssertEqual(stubLength(crossingAt: 90, tolerance: 18, spacing: 3), 0, accuracy: 0.01)
    }

    /// Two lines running alongside each other with no crossing anywhere — the one case where "the
    /// closest approach" is not a place, since every position along the shared run is equally close.
    /// The cut stops where the run begins, on the side the eraser came from, instead of swallowing all
    /// 80 points of it. Symmetric from either side, and the same answer either way round.
    func testAParallelOverlapIsCutBackToWhereTheLinesPartCompany() {
        let run = samples((0...200).map { (CGFloat($0), CGFloat(0)) })
        let alongside = (60...140).map { CGPoint(x: CGFloat($0), y: 2) }
        assertCut(VectorEraser.cutToIntersection(in: run, at: 180, others: [(alongside, 10)]),
                  140, 200, accuracy: 0.01)
        assertCut(VectorEraser.cutToIntersection(in: run, at: 20, others: [(alongside, 10)]),
                  0, 60, accuracy: 0.01)
    }

    // MARK: - Mode 3: the eraser's size is the selection radius
    //
    // The owner, same report: *"the eraser brush size should be the radius around which everything is
    // erased. For example if I erase the section where two lines intersect, it should erase both of
    // them (up to any other lines they hit)."* Two rulings — the footprint picks the victims, and a
    // crossing inside the footprint is not something to stop at.
    //
    // **Assumption, taken because the owner has not been asked yet**: a stroke is taken when its
    // *centreline* passes under the footprint, not merely when its ink does. That makes the circle the
    // user sees exactly the rule; the cost is a thick line left alone when the eraser clips its edge.

    private func nib(at point: CGPoint, size: CGFloat) -> VectorEraser.Sweep {
        guard let sweep = VectorEraser.Sweep(samples: [VectorSample(x: point.x, y: point.y, pressure: 1)],
                                             brush: fixedBrush(size: size), size: size,
                                             mode: .cutToIntersection) else {
            preconditionFailure("a one-sample gesture always has a footprint")
        }
        return sweep
    }

    private func stroke(_ points: [(CGFloat, CGFloat)], size: CGFloat = 4) -> VectorStroke {
        VectorStroke(brush: fixedBrush(size: size),
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: size, opacity: 1, samples: samples(points, pressure: 1))
    }

    /// The geometry half of ruling (b): the cut runs *through* a crossing the eraser is sitting on and
    /// stops at the next one outside it. Stopping at the covered crossing would leave exactly the ink
    /// the user aimed at.
    func testACrossingUnderTheEraserIsNotAnObstacle() {
        let run = samples((0...200).map { (CGFloat($0), CGFloat(0)) })
        let others = [((-40...40).map { CGPoint(x: 70, y: CGFloat($0)) }, CGFloat(4)),
                      ((-40...40).map { CGPoint(x: 130, y: CGFloat($0)) }, CGFloat(4))]
        assertCut(VectorEraser.cutToIntersection(in: run, at: 70, others: others,
                                                 footprint: nib(at: CGPoint(x: 70, y: 0), size: 20)),
                  0, 130, accuracy: 0.01)
        // A pinpoint tip a point off the same crossing stops at it — the r = 0 limit, and what every
        // bracket test above asserts by passing no footprint at all.
        assertCut(VectorEraser.cutToIntersection(in: run, at: 71, others: others,
                                                 footprint: nib(at: CGPoint(x: 71, y: 0), size: 1)),
                  70, 130, accuracy: 0.01)
    }

    /// The owner's own example. Two lines crossing at (100, 100), each also crossing a neighbour
    /// further out; one tap on the crossing takes **both** lines, each back to its own neighbours.
    /// Before this change the tap cut one line — the nearest centreline — and stopped at the crossing.
    func testAWideEraserOnACrossingCutsBothLinesBackToTheirOwnNeighbours() {
        let canvas = VectorCanvas(size: CGSize(width: 200, height: 200), strokes: [
            stroke([(20, 100), (180, 100)]),        // the horizontal through the crossing
            stroke([(100, 20), (100, 180)]),        // the vertical through the crossing
            stroke([(60, 20), (60, 180)]),          // the horizontal's neighbours
            stroke([(140, 20), (140, 180)]),
            stroke([(20, 60), (180, 60)]),          // the vertical's neighbours
            stroke([(20, 140), (180, 140)])])
        var driver = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(canvas, &driver, to: CGPoint(x: 100, y: 100), nib: 20), .cut)

        XCTAssertEqual(canvas.strokes.count, 8, "two victims in two pieces each, four neighbours intact")
        let horizontals = canvas.strokes.filter { $0.samples.allSatisfy { abs($0.y - 100) < 0.01 } }
        let verticals = canvas.strokes.filter { $0.samples.allSatisfy { abs($0.x - 100) < 0.01 } }
        XCTAssertEqual(horizontals.count, 2, "the horizontal should be in two pieces")
        XCTAssertEqual(verticals.count, 2, "the vertical should be in two pieces")
        XCTAssertEqual(horizontals.first?.samples.last?.x ?? -1, 60, accuracy: 0.01)
        XCTAssertEqual(horizontals.last?.samples.first?.x ?? -1, 140, accuracy: 0.01)
        XCTAssertEqual(verticals.first?.samples.last?.y ?? -1, 60, accuracy: 0.01)
        XCTAssertEqual(verticals.last?.samples.first?.y ?? -1, 140, accuracy: 0.01)
    }

    /// The same tap with nothing else on the canvas. Neither line has a crossing outside the tip, so
    /// "the span between the neighbouring crossings" is each line entire and both go. That is the
    /// existing whole-line rule reached by two strokes at once, and the biggest behavioural jump in
    /// this change: with a 50-point eraser it can take a stray line the circle merely grazes.
    func testAWideEraserOnALoneCrossingDeletesBothLines() {
        let canvas = VectorCanvas(size: CGSize(width: 200, height: 200), strokes: [
            stroke([(20, 100), (180, 100)]), stroke([(100, 20), (100, 180)])])
        var driver = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(canvas, &driver, to: CGPoint(x: 100, y: 100), nib: 20), .cut)
        XCTAssertEqual(canvas.strokes.count, 0)
    }

    /// Which strokes the circle takes, pinned from both sides. A 40-wide line carries 20 points of ink
    /// either side of its centreline; a 10-point radius at `y = 125` covers ink from 115 to 120 and is
    /// still 25 points from the centreline, so the line is left alone. At `y = 108` the centreline is
    /// inside and the line goes.
    func testAStrokeIsTakenByItsCentrelineNotByItsInk() {
        func thickLine() -> VectorCanvas {
            VectorCanvas(size: CGSize(width: 200, height: 200),
                         strokes: [stroke([(0, 100), (200, 100)], size: 40)])
        }
        let grazed = thickLine()
        var first = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(grazed, &first, to: CGPoint(x: 100, y: 125), nib: 20), .missed)
        XCTAssertEqual(grazed.strokes.count, 1)

        let taken = thickLine()
        var second = VectorEraser.IntersectionDriver()
        XCTAssertEqual(pump(taken, &second, to: CGPoint(x: 100, y: 108), nib: 20), .cut)
        XCTAssertEqual(taken.strokes.count, 0)
    }

    /// The selection radius is the brush **size**, full stop — a pressure-sensitive brush selects
    /// exactly what a fixed one of the same size does.
    ///
    /// This is the owner's sentence taken literally: *"the eraser brush size should be the radius
    /// around which everything is erased."* Modes 1 and 2 lay down a hole that *is* ink and should
    /// thin under a light pencil; Mode 3's footprint is a selection, and one that quietly shrank with
    /// pressure would erase a different amount every pass with nothing on screen to explain it — and
    /// would make the footprint ring, drawn at full size, a promise the cut does not keep.
    ///
    /// Every other Mode-3 test here uses `dynamics: .fixed`, which is precisely why none of them can
    /// see this: with a fixed brush there is no pressure term to leak. `StrokeInput` reports pressure
    /// 1 for a finger and `force / maximumPossibleForce` for a pencil, so a leak here would have been
    /// invisible in the simulator and shown up only on the owner's own iPad.
    func testTheSelectionRadiusIsTheBrushSizeWhateverThePressureDynamicsSay() {
        // At half pressure this brush stamps a dab 0.6x its nominal size — radius 6, not 10. The
        // centrelines below sit 8 points from the tip: inside the size-derived radius, outside the
        // pressure-derived one, so the two rules give opposite answers on every stroke here.
        let dynamic = Brush(name: "pressure-sensitive", shape: .hardRound, size: 20,
                            dynamics: BrushDynamics(sizePressure: 1, opacityPressure: 0,
                                                    minSizeFraction: 0.2))
        XCTAssertEqual(StrokeGeometry.stampRadius(forPressure: 1, brush: dynamic, size: 20), 10, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.stampRadius(forPressure: 0.5, brush: dynamic, size: 20), 6, accuracy: 1e-9)

        func canvas() -> VectorCanvas {
            VectorCanvas(size: CGSize(width: 200, height: 200),
                         strokes: [stroke([(20, 108), (180, 108)]), stroke([(60, 20), (60, 180)]),
                                   stroke([(140, 20), (140, 180)])])
        }
        func survivors(_ brush: Brush) -> [String] {
            let live = canvas()
            let resolved = live.cutToIntersection(atCanvasPoint: CGPoint(x: 100, y: 100),
                                                  brush: brush, size: 20)
            XCTAssertEqual(resolved.outcome, .cut, "a centreline 8pt away is inside a radius of 10")
            return live.strokes.map { stroke in
                stroke.samples.map { String(format: "%.2f,%.2f", Double($0.x), Double($0.y)) }
                    .joined(separator: " ")
            }.sorted()
        }
        XCTAssertEqual(survivors(dynamic), survivors(fixedBrush(size: 20)))
        XCTAssertEqual(survivors(dynamic).count, 4, "the horizontal in two pieces + two uprights")
    }

    /// Victims are bracketed against the display list as it was, then spliced — so two lines cut in the
    /// same tap each see the other's original geometry, and the answer does not depend on which index
    /// they happen to sit at. The splice runs in descending index for the same reason: an ascending one
    /// would shift every later index by the pieces it just inserted.
    func testVictimsAreCutAgainstPristineGeometryWhateverOrderTheySitIn() {
        func survivors(victimsFirst: Bool) -> [String] {
            let victims = [stroke([(20, 100), (180, 100)]), stroke([(100, 20), (100, 180)])]
            let neighbours = [stroke([(60, 20), (60, 180)]), stroke([(140, 20), (140, 180)]),
                              stroke([(20, 60), (180, 60)]), stroke([(20, 140), (180, 140)])]
            let canvas = VectorCanvas(size: CGSize(width: 200, height: 200),
                                      strokes: victimsFirst ? victims + neighbours : neighbours + victims)
            var driver = VectorEraser.IntersectionDriver()
            pump(canvas, &driver, to: CGPoint(x: 100, y: 100), nib: 20)
            return canvas.strokes.map { stroke in
                stroke.samples.map { String(format: "%.2f,%.2f", Double($0.x), Double($0.y)) }.joined(separator: " ")
            }.sorted()
        }
        XCTAssertEqual(survivors(victimsFirst: true), survivors(victimsFirst: false))
        XCTAssertEqual(survivors(victimsFirst: true).count, 8)
    }

    /// Why the latch had to become a *set*. A wide footprint in a dense drawing is almost never over
    /// nothing at all, and the pre-2026-08-18 driver re-armed only when it was: one bit for the whole
    /// gesture, cleared by `.missed`. Here a hairpin passes under the tip on both of its arms, so
    /// cutting the near arm leaves the far one under the tip for the rest of the drag — the single bit
    /// never sees `.missed` again and the four uprights are never reached. Remembering ids instead
    /// suppresses the hairpin, which is already dealt with, and cuts each upright as the tip arrives.
    ///
    /// The second half is that failure, emulated against the same canvas and the same path, so the
    /// first half is evidence rather than an assertion about a straw man.
    func testAWideDragCutsEveryLineItReachesWhereOneLatchBitCutsOne() {
        func hairpinCanvas() -> VectorCanvas {
            VectorCanvas(size: CGSize(width: 200, height: 200),
                         strokes: [stroke([(10, 85), (150, 85), (150, 95), (10, 95)])]
                                + [CGFloat(30), 60, 90, 120].map { stroke([($0, 20), ($0, 180)]) }
                                + [stroke([(0, 40), (200, 40)]), stroke([(0, 140), (200, 140)])])
        }
        let path = stride(from: CGFloat(22), through: 127, by: 5).map { CGPoint(x: $0, y: 90) }

        let canvas = hairpinCanvas()
        var driver = VectorEraser.IntersectionDriver()
        for point in path { pump(canvas, &driver, to: point, nib: 50) }
        XCTAssertTrue(driver.didCut)
        XCTAssertEqual(canvas.strokes.count, 11, "hairpin remnant + four uprights in two pieces + two rails")
        for x in [CGFloat(30), 60, 90, 120] {
            XCTAssertEqual(canvas.strokes.filter { $0.samples.allSatisfy { abs($0.x - x) < 0.01 } }.count, 2,
                           "the upright at x = \(x) should be in two pieces")
        }

        // One bit for the whole gesture: disarm on anything but `.missed`, and a disarmed sample
        // suppresses everything — which is exactly what the old `cutting: false` did.
        let single = hairpinCanvas()
        var armed = true
        for point in path {
            let resolved = single.cutToIntersection(atCanvasPoint: point, brush: fixedBrush(size: 50), size: 50,
                                                    suppressing: armed ? [] : Set(single.strokes.map(\.id)))
            armed = resolved.outcome == .missed
        }
        XCTAssertEqual(single.strokes.count, 8, "one bit goes dead after the first position and never re-arms")
    }
}
