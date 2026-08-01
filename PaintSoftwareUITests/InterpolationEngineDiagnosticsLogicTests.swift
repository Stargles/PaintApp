import XCTest
import CoreGraphics

/// Phase 4.7 — the product owner's four failing test drawings, pinned as motion assertions.
///
/// `HANDOFF.md` §8 items 27–30 are four two-keyframe drawings of one to three strokes that the
/// engine gets wrong. This class is the record of *what* it gets wrong, in numbers, and it is
/// deliberately split in two halves:
///
/// - **The acceptance tests** (`testCase27…` … `testCase30…`) describe the motion an animator would
///   accept. They are wrapped in `XCTExpectFailure`, so the suite stays green while the engine is
///   still wrong, and turns **red the moment one starts passing** — which is precisely when someone
///   should come back here, delete the wrapper, and claim the fix. Do not "fix" a red one by
///   loosening the threshold; the thresholds are derived from the target geometry, not from what the
///   engine currently produces.
/// - **The characterisation tests** pass *today*. They pin the measured root causes, so a later
///   change that alters the mechanism fails here first and loudly, rather than silently moving the
///   failure somewhere else.
///
/// Why motion and not pixels: the existing render tests would pass on all four broken outputs. A
/// stroke that spins 180° while travelling still lands on the target, still differs from keyframe A,
/// and still reproduces both endpoints exactly. Only the *path between* them is wrong, so only a
/// test that samples the path can see it.
final class InterpolationEngineDiagnosticsLogicTests: XCTestCase {

    // MARK: - Fixtures: the product owner's four drawings

    private func polyline(_ a: CGPoint, _ b: CGPoint, samples: Int = 24) -> [CGPoint] {
        (0...samples).map { i in
            let u = CGFloat(i) / CGFloat(samples)
            return CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
        }
    }

    /// An open "C": an arc from +130° to −130°, so it opens toward +x.
    private func cShape(centre: CGPoint, radius: CGFloat, samples: Int = 48) -> [CGPoint] {
        (0...samples).map { i in
            let angle = (130 - 260 * CGFloat(i) / CGFloat(samples)) * .pi / 180
            return CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        }
    }

    // MARK: - Motion measures
    //
    // Each of these describes something an animator would name while watching the in-between, which
    // is the bar `IMPLEMENTATION.md` Phase 4.7 sets: "pass criteria that describe the motion".

    private func arcLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Peak deviation from the polyline's own chord, divided by that chord — "how bent is it",
    /// scale-free, so a shape that grows does not read as a shape that curves.
    private func bendRatio(_ points: [CGPoint]) -> CGFloat {
        guard let a = points.first, let b = points.last else { return 0 }
        let cx = b.x - a.x, cy = b.y - a.y
        let chord = hypot(cx, cy)
        guard chord > 1e-9 else { return 0 }
        return points.map { abs(cx * (a.y - $0.y) - (a.x - $0.x) * cy) / chord }.max()! / chord
    }

    /// Cosine between the stroke's opening tangent now and at rest. Negative means the stroke has
    /// been turned back on itself — the "180° flip" in items 27 and 30, expressed as one number.
    private func openingTangentAgreement(_ warped: [CGPoint], rest: [CGPoint]) -> CGFloat {
        guard warped.count > 1, rest.count > 1 else { return 1 }
        let w = CGPoint(x: warped[1].x - warped[0].x, y: warped[1].y - warped[0].y)
        let r = CGPoint(x: rest[1].x - rest[0].x, y: rest[1].y - rest[0].y)
        let denominator = hypot(w.x, w.y) * hypot(r.x, r.y)
        guard denominator > 1e-12 else { return 1 }
        return (w.x * r.x + w.y * r.y) / denominator
    }

    // MARK: - Driving the engine the way `registerWholeFrameGroup` does

    /// Mirrors `CanvasManager.latticeCellSize(covering:)` — roughly ten cells across the longer side.
    private func cellSize(covering points: [CGPoint]) -> CGFloat {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
        else { return 32 }
        return max(max(maxX - minX, maxY - minY) / 10, 8)
    }

    private struct Registration {
        var rest: Lattice
        var fitted: Lattice
        var embedding: LatticeEmbedding
        var source: [CGPoint]
        var result: ARAPRegistration.Result
    }

    /// Exactly the path `registerWholeFrameGroup` takes: a rest lattice over keyframe A, fitted to
    /// keyframe C's point cloud.
    private func register(source: [CGPoint], target: [CGPoint]) -> Registration {
        let rest = Lattice(covering: source, targetCellSize: cellSize(covering: source), padding: 1)
        let result = ARAPRegistration.fit(lattice: rest, source: source,
                                          target: PointCloudIndex(target))
        return Registration(rest: rest, fitted: result.lattice,
                            embedding: rest.restConfiguration.embedInRest(source),
                            source: source, result: result)
    }

    /// Where keyframe A's geometry sits at time `t`, through the same interpolator the evaluator uses.
    private func warp(_ registration: Registration, at t: CGFloat) -> [CGPoint] {
        guard let interpolator = ARAPInterpolation.Interpolator(
            from: registration.rest.restConfiguration, to: registration.fitted) else {
            XCTFail("A and C must share topology — the fit returns the same grid it was given")
            return registration.source
        }
        return interpolator.lattice(at: t).warp(registration.embedding)
    }

    // MARK: - Acceptance: the motion an animator would accept
    //
    // All four are expected failures today. See the class comment before touching a threshold.

    /// §8 item 27 — a short vertical line becoming a large offset C.
    ///
    /// **Do not assert the flip itself: it is a coin toss.** The first version of this test asserted
    /// that the opening tangent stays positive, and it *failed on the simulator while flipping on a
    /// native optimised build of the same engine on the same input*. That is not flakiness to be
    /// papered over — it is the finding. The upright and flipped fits score identically (see
    /// `testA180DegreeFitScoresIdenticallyToTheUprightOneOnALine`), so which one wins is decided by
    /// the last bits of a floating-point comparison, and that differs between builds.
    ///
    /// So the acceptance criterion is the one an engine can actually be held to: the objective must
    /// *prefer* the upright fit by a margin big enough that arithmetic noise cannot flip it. Today
    /// the margin is zero to six decimal places.
    func testCase27_TheObjectiveDecisivelyPrefersTheUprightFit() {
        XCTExpectFailure("Phase 4.7: upright and flipped tie exactly, so the winner is arbitrary")

        let source = polyline(CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 320))
        let target = PointCloudIndex(cShape(centre: CGPoint(x: 480, y: 400), radius: 160))

        func residual(seededAt degrees: CGFloat) -> CGFloat {
            let seed = ARAPRegistration.bootstrap(source: source, target: target.points,
                                                  angle: degrees * .pi / 180)
            let fit = ARAPRegistration.similarityICP(source: source, target: target, initial: seed)
            return ARAPRegistration.meanDistance(source: source, target: target, under: fit)
        }

        let upright = residual(seededAt: 45), flipped = residual(seededAt: 135)
        XCTAssertGreaterThan(abs(upright - flipped), 0.5,
            "upright scores \(upright) and flipped \(flipped) — nothing in the objective separates them")
    }

    /// §8 items 28/29 — a vertical line becoming a C that encompasses it.
    ///
    /// The animator's requirement is that the line *bends*. It is allowed to grow — the C is genuinely
    /// longer — but by t = 1 it has to have acquired most of the target's curvature. Measured today:
    /// bend ratio 0.34 against the target's 1.07, while arc length triples. That is the "it grew and
    /// faded instead of bending" report, as a number.
    func testCase29_LineIntoEncompassingCActuallyBends() {
        XCTExpectFailure("Phase 4.7: the tier-1 similarity spends the motion on scale, not curvature")

        let target = cShape(centre: CGPoint(x: 400, y: 400), radius: 200)
        let registration = register(
            source: polyline(CGPoint(x: 400, y: 320), CGPoint(x: 400, y: 480)),
            target: target)

        let achieved = bendRatio(warp(registration, at: 1))
        let wanted = bendRatio(target)
        XCTAssertGreaterThan(achieved, wanted * 0.6,
            "at t=1 the stroke bends \(achieved) against the C's own \(wanted) — it is still nearly straight")
    }

    /// §8 item 30 — two vertical lines becoming one between them.
    ///
    /// The animator's requirement is that the pair arrives *on* the single line and still spans it.
    /// Measured today: the fit collapses the source to scale 0.15, so at t = 1 the drawing covers 51
    /// points of the target's 200 — a quarter-height smudge sitting on the middle of the line.
    func testCase30_TwoLinesMergeOntoTheSingleLineAndStillSpanIt() {
        XCTExpectFailure("Phase 4.7: a free scale collapses the source onto the target's centre")

        let target = polyline(CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 400))
        let registration = register(
            source: polyline(CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 400))
                  + polyline(CGPoint(x: 500, y: 200), CGPoint(x: 500, y: 400)),
            target: target)

        let warped = warp(registration, at: 1)
        let ys = warped.map(\.y)
        let span = ys.max()! - ys.min()!
        let targetSpan = target.map(\.y).max()! - target.map(\.y).min()!
        XCTAssertGreaterThan(span, targetSpan * 0.8,
            "at t=1 the merged drawing spans \(span) of the target's \(targetSpan) — it has collapsed")
    }

    // §8 item 28 — registration cost — is deliberately **not** pinned here.
    //
    // A wall-clock assertion in this tier measures the wrong thing: tests build unoptimised, so a
    // 121-sample fit that takes 0.6s in an optimised build took **598 seconds** here. That is a
    // ten-minute test whose threshold says nothing about what an artist experiences, and it would
    // have made the "run this constantly" fast tier unusable.
    //
    // The cost curve is measured instead by `deploy/interp-registration-benchmark`, an optimised
    // standalone harness over the same engine sources — see `HANDOFF.md` §5 for the numbers and for
    // the verified fix. This is the one Phase 4.7 item whose pin is a benchmark rather than a test,
    // and it is called out here so nobody adds the slow version back.

    // MARK: - Characterisation: the measured root causes
    //
    // These pass today. They are the evidence behind the four above, and a tripwire on the mechanism.

    /// **The rotation hypothesis, made precise.** `HANDOFF.md` item 27 guessed that "rotation is a
    /// lower minimum than deformation". It is sharper than that: for a straight-line source the
    /// point-cloud residual is *exactly invariant* under a 180° turn, because a line segment maps onto
    /// itself. There is no lower minimum to prefer — the two solutions tie, and the multi-start picks
    /// between them on floating-point noise. No rotation *penalty* can fix a tie; only a term that
    /// distinguishes the two ends of a stroke can.
    func testA180DegreeFitScoresIdenticallyToTheUprightOneOnALine() {
        let source = polyline(CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 320))
        let target = PointCloudIndex(cShape(centre: CGPoint(x: 480, y: 400), radius: 160))

        func residual(seededAt degrees: CGFloat) -> CGFloat {
            let seed = ARAPRegistration.bootstrap(source: source, target: target.points,
                                                  angle: degrees * .pi / 180)
            let fit = ARAPRegistration.similarityICP(source: source, target: target, initial: seed)
            return ARAPRegistration.meanDistance(source: source, target: target, under: fit)
        }

        XCTAssertEqual(residual(seededAt: 45), residual(seededAt: 135), accuracy: 1e-6,
                       "the upright and flipped fits are indistinguishable to the objective")
    }

    /// **Item 29's open question, answered: it is not the cross-fade fallback.** The report read the
    /// grow-and-fade as the evaluator degrading to a cross-fade. It is not — the ARAP solve runs and
    /// reports `refined`. The motion is wrong inside the warp path, which needs a different fix from
    /// a fallback that fired too eagerly.
    func testTheGrowAndFadeCaseIsNotTheCrossFadeFallback() {
        let registration = register(
            source: polyline(CGPoint(x: 400, y: 320), CGPoint(x: 400, y: 480)),
            target: cShape(centre: CGPoint(x: 400, y: 400), radius: 200))

        XCTAssertTrue(registration.result.refined,
                      "the elastic solve ran — this is the warp path, not the degenerate fallback")
        XCTAssertGreaterThan(arcLength(warp(registration, at: 1)),
                             arcLength(registration.source) * 2,
                             "and what it spent the motion on was growth")
    }

    /// **Mean residual does not detect the collapse, which is why nothing caught this earlier.**
    /// The two-lines-into-one fit scores a mean residual of a few points — by that measure an
    /// excellent fit — while covering a quarter of the target. Any future gate on registration
    /// quality has to measure *coverage*, not distance-to-nearest: piling the source onto the middle
    /// of the target is exactly how you win on distance-to-nearest.
    func testMeanResidualLooksGoodOnTheCollapsedFit() {
        let target = polyline(CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 400))
        let registration = register(
            source: polyline(CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 400))
                  + polyline(CGPoint(x: 500, y: 200), CGPoint(x: 500, y: 400)),
            target: target)

        XCTAssertLessThan(registration.result.meanResidual, 10,
                          "the residual reports a good fit")
        XCTAssertLessThan(registration.result.similarity.scale, 0.5,
                          "while the similarity has shrunk the drawing to a fraction of its size")
    }

    /// **Locking the scale is not the fix.** `ARAPRegistration.similarity`'s own comment warns that a
    /// free scale can collapse a partial match, and `fit` does not pass `allowScale: false`. Passing
    /// it does not rescue item 30 — it trades a collapse for a 90° turn at more than triple the
    /// residual. Recorded so the next session does not spend time on the one-line version of the fix.
    func testLockingTheScaleTradesTheCollapseForADifferentWrongAnswer() {
        let source = polyline(CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 400))
                   + polyline(CGPoint(x: 500, y: 200), CGPoint(x: 500, y: 400))
        let target = PointCloudIndex(polyline(CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 400)))

        let free = ARAPRegistration.similarityICP(source: source, target: target, allowScale: true)
        let rigid = ARAPRegistration.similarityICP(source: source, target: target, allowScale: false)

        XCTAssertLessThan(free.scale, 0.5, "the free fit collapses")
        XCTAssertGreaterThan(
            ARAPRegistration.meanDistance(source: source, target: target, under: rigid),
            ARAPRegistration.meanDistance(source: source, target: target, under: free) * 2,
            "and the rigid one is markedly worse by the same measure, rather than better")
    }
}
