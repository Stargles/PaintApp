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
    /// keyframe C's point cloud — with the 1:1 arc-length correspondence when `strokes` names the
    /// two frames' strokes and they pair, and without it otherwise.
    private func register(source: [CGPoint], target: [CGPoint],
                          strokes: (source: [[CGPoint]], target: [[CGPoint]])? = nil) -> Registration {
        let rest = Lattice(covering: source, targetCellSize: cellSize(covering: source), padding: 1)
        let correspondence = strokes.map {
            ARAPRegistration.StrokeCorrespondence(source: $0.source, target: $0.target)
        }
        let result = ARAPRegistration.fit(lattice: rest, source: source,
                                          target: PointCloudIndex(target),
                                          correspondence: correspondence)
        return Registration(rest: rest, fitted: result.lattice,
                            embedding: rest.restConfiguration.embedInRest(source),
                            source: source, result: result)
    }

    /// Fraction of the target that has some part of the warped stroke within `tolerance` — the
    /// **coverage** metric §5 says any quality gate needs, since mean residual rewards piling the
    /// source up. Measured against the polyline's segments rather than its samples: a stroke that
    /// has been stretched five times over carries its samples 35 points apart, and sampling-based
    /// coverage would score continuous ink as a dotted line.
    private func inkCoverage(of target: [CGPoint], by warped: [CGPoint],
                             tolerance: CGFloat = 12) -> CGFloat {
        guard !target.isEmpty, warped.count > 1 else { return 0 }
        func distance(_ q: CGPoint) -> CGFloat {
            var best = CGFloat.infinity
            for (a, b) in zip(warped, warped.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let squared = dx * dx + dy * dy
                let u = squared > 1e-12
                    ? max(0, min(1, ((q.x - a.x) * dx + (q.y - a.y) * dy) / squared)) : 0
                let ex = a.x + dx * u - q.x, ey = a.y + dy * u - q.y
                best = min(best, ex * ex + ey * ey)
            }
            return best.squareRoot()
        }
        return CGFloat(target.filter { distance($0) <= tolerance }.count) / CGFloat(target.count)
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
    /// **The original version of this test asserted something no engine can deliver, and finding
    /// that out is the result.** It asked the point-cloud objective to prefer the upright fit "by a
    /// margin big enough that arithmetic noise cannot flip it". But the margin is not merely small,
    /// it is *identically zero*: a straight line segment maps exactly onto itself under a half turn,
    /// so for any fit `F` the fit `F ∘ turn` sends the source onto the very same point set and
    /// scores the same to the last bit (`testA180DegreeFitScoresIdenticallyToTheUprightOneOnALine`
    /// still pins this, and it is a proof, not a measurement — it holds with the scale free or
    /// locked, at every restart count, for any objective that only sees the two clouds). The two
    /// assertions were direct contradictions; one of them had to be wrong, and it was this one.
    ///
    /// So the criterion becomes the one that survives a tie, and it is closer to what the product
    /// owner actually reported: the line must **bend into the C instead of spinning**, whichever way
    /// the tie falls. That is asserted here twice over — once on the drawing as made, and once with
    /// keyframe C's stroke recorded in the opposite direction, which is the input that flips the
    /// choice. Both branches have to clear the same bar, so nothing here can be flipped by a build.
    ///
    /// Measured: bend 0.907 and 0.910 against the C's own 1.072, ink coverage 0.959 both ways. The
    /// point-cloud path, for comparison, manages bend 0.159 and coverage 0.31.
    func testCase27_TheLineBendsIntoTheCWhicheverWayTheTieFalls() {
        let source = polyline(CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 320))
        let drawn = cShape(centre: CGPoint(x: 480, y: 400), radius: 160)

        for target in [drawn, drawn.reversed()] {
            let registration = register(source: source, target: target,
                                        strokes: (source: [source], target: [target]))
            let warped = warp(registration, at: 1)

            XCTAssertGreaterThan(bendRatio(warped), bendRatio(target) * 0.6,
                "at t=1 the stroke bends \(bendRatio(warped)) against the C's own \(bendRatio(target))")
            XCTAssertGreaterThan(inkCoverage(of: target, by: warped), 0.8,
                "and it covers \(inkCoverage(of: target, by: warped)) of the C — it landed *on* it")
        }
    }

    /// §8 items 28/29 — a vertical line becoming a C that encompasses it.
    ///
    /// The animator's requirement is that the line *bends*. It is allowed to grow — the C is genuinely
    /// longer — but by t = 1 it has to have acquired most of the target's curvature. Measured before
    /// Phase 4.7: bend ratio 0.34 against the target's 1.07, while arc length tripled. That was the
    /// "it grew and faded instead of bending" report, as a number.
    ///
    /// The 1:1 arc-length correspondence is what fixes it, and nothing else did: rigidity was swept
    /// 2.0 → 0.01 and moved the bend by 0.02, because this is a *correspondence* failure and not a
    /// stiffness one. Nearest-point matching gives a short straight source no reason to wrap around
    /// a long curved target — the pulls from the two sides of the arc cancel. Measured now: bend
    /// 0.985 against the C's 1.072, arc length 853 of 907, and the threshold below is Session 10's
    /// own, untouched.
    func testCase29_LineIntoEncompassingCActuallyBends() {
        let target = cShape(centre: CGPoint(x: 400, y: 400), radius: 200)
        let source = polyline(CGPoint(x: 400, y: 320), CGPoint(x: 400, y: 480))
        let registration = register(source: source, target: target,
                                    strokes: (source: [source], target: [target]))

        let warped = warp(registration, at: 1)
        let achieved = bendRatio(warped)
        let wanted = bendRatio(target)
        XCTAssertGreaterThan(achieved, wanted * 0.6,
            "at t=1 the stroke bends \(achieved) against the C's own \(wanted) — it is still nearly straight")
        XCTAssertGreaterThan(inkCoverage(of: target, by: warped), 0.8,
            "and it has to land on the C, not merely curve somewhere near it")
    }

    /// §8 item 30 — two vertical lines becoming one between them.
    ///
    /// The animator's requirement is that the pair arrives *on* the single line and still spans it.
    /// Measured today: the fit collapses the source to scale 0.15, so at t = 1 the drawing covers 51
    /// points of the target's 200 — a quarter-height smudge sitting on the middle of the line.
    /// **Fixed by `allowScale: false` + `icpRestarts: 1`** (§8 item 32). Nothing about the *merge*
    /// was solved — this is a 2:1 pairing, so it takes the point-cloud path, not the 1:1
    /// correspondence path — but the collapse that made it unwatchable is gone: the span went from
    /// 51 to 194.6 of the target's 200. Honest merging of unmatched content is §8 item 34's
    /// per-vertex visibility thresholds, still unbuilt.
    func testCase30_TwoLinesMergeOntoTheSingleLineAndStillSpanIt() {
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
    ///
    /// This still holds and always will — it is the reason `icpRestarts` is 1 (stop offering the
    /// flipped seed) and the reason `testCase27` asserts what survives the tie rather than which way
    /// it falls. Do not read a passing run here as "the flip is fixed": it says the flip is still
    /// free, and the engine simply never goes looking for it.
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
    ///
    /// Locking the scale (§8 item 32) took the *grow* half away — the stroke used to triple in
    /// length, and now reaches 265 of its own 160 — but it left the failure that mattered: at the
    /// point-cloud tier it still barely bends. That is what the correspondence path fixes, and it is
    /// why the two changes had to land in that order rather than either alone.
    func testTheGrowAndFadeCaseNoLongerGrowsButStillWillNotBend() {
        let target = cShape(centre: CGPoint(x: 400, y: 400), radius: 200)
        let registration = register(
            source: polyline(CGPoint(x: 400, y: 320), CGPoint(x: 400, y: 480)),
            target: target)

        XCTAssertTrue(registration.result.refined,
                      "the elastic solve ran — this is the warp path, not the degenerate fallback")
        XCTAssertLessThan(arcLength(warp(registration, at: 1)),
                          arcLength(registration.source) * 2,
                          "the scale is locked, so it no longer buys its residual with growth")
        XCTAssertLessThan(bendRatio(warp(registration, at: 1)), 0.3,
                          "and with no correspondence it is still nearly straight")
    }

    /// **Mean residual is a lying metric, which is why nothing caught this earlier.** Fitted with a
    /// free scale, two vertical lines onto one between them score a mean residual of a few points —
    /// by that measure an excellent fit — while shrinking to a seventh of their size. Piling the
    /// source onto the middle of the target is precisely how you win on distance-to-nearest.
    ///
    /// The fit itself no longer does this (`allowScale: false`), so this drives the free-scale path
    /// directly. **Any future gate on registration quality has to measure coverage**, not
    /// distance-to-nearest — §8 items 32, 36 and 37 all need the same metric.
    func testMeanResidualStillLooksGoodOnAFitThatHasCollapsed() {
        let source = polyline(CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 400))
                   + polyline(CGPoint(x: 500, y: 200), CGPoint(x: 500, y: 400))
        let target = PointCloudIndex(polyline(CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 400)))

        let collapsed = ARAPRegistration.similarityICP(source: source, target: target,
                                                       allowScale: true)

        XCTAssertLessThan(collapsed.scale, 0.5, "the free fit shrinks the drawing to a fraction")
        XCTAssertLessThan(ARAPRegistration.meanDistance(source: source, target: target,
                                                        under: collapsed), 20,
                          "and the residual calls that a good fit anyway")
    }

    /// **Locking the scale *alone* is not the fix.** `ARAPRegistration.similarity`'s own comment
    /// warns that a free scale can collapse a partial match, and taking the warning on its own —
    /// without also dropping the multi-start — trades the collapse for a different wrong answer at
    /// more than triple the residual. That is why §8 item 32 is one decision about two flags, and
    /// this pins the half-fix so it cannot be applied by accident in either direction.
    func testLockingTheScaleAloneTradesTheCollapseForADifferentWrongAnswer() {
        let source = polyline(CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 400))
                   + polyline(CGPoint(x: 500, y: 200), CGPoint(x: 500, y: 400))
        let target = PointCloudIndex(polyline(CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 400)))

        // Explicitly eight restarts: this pins the *half*-fix — the old multi-start still in place,
        // only the scale locked — so it keeps meaning what it says after the defaults moved to one.
        let free = ARAPRegistration.similarityICP(source: source, target: target, restarts: 8,
                                                  allowScale: true)
        let rigid = ARAPRegistration.similarityICP(source: source, target: target, restarts: 8,
                                                   allowScale: false)

        XCTAssertLessThan(free.scale, 0.5, "the free fit collapses")
        XCTAssertGreaterThan(
            ARAPRegistration.meanDistance(source: source, target: target, under: rigid),
            ARAPRegistration.meanDistance(source: source, target: target, under: free) * 2,
            "and the rigid one is markedly worse by the same measure, rather than better")
    }

    /// **The direction bit reads geometry, and reports a tie when the geometry has nothing to say.**
    ///
    /// This is the part of the correspondence that most looks like the refuted tangent term (§5) and
    /// is not it. That term treated the artist's drawn direction as *evidence*, and lost — it left
    /// case 27 flipped and broke case 29, which the plain objective got right, because between two
    /// independently drawn keyframes the second stroke's direction is arbitrary. Here geometry
    /// decides whenever it has anything to say, and drawn order only settles what geometry calls a
    /// draw.
    ///
    /// Both halves matter, so both are asserted: a hook separates its two directions completely, and
    /// a straight stroke does not separate them at all.
    func testTheDirectionBitReadsAnAsymmetricStrokeAndTiesOnAStraightOne() {
        let hook = (0..<20).map { i -> CGPoint in
            let u = CGFloat(i) / 19
            return u < 0.7 ? CGPoint(x: 100 + u * 200, y: 100)
                           : CGPoint(x: 240, y: 100 + (u - 0.7) * 260)
        }
        let moved = Similarity(angle: 0.4, scale: 1.2, translation: CGPoint(x: 60, y: 30))
        let hookTarget = hook.map(moved.applied(to:))

        func bit(_ source: [[CGPoint]], _ target: [[CGPoint]]) -> (reversed: Bool, gap: CGFloat) {
            let correspondence = ARAPRegistration.StrokeCorrespondence(source: source, target: target)
            let alignment = ARAPRegistration.similarityICP(
                source: source.flatMap { $0 }, target: PointCloudIndex(target.flatMap { $0 }))
            let scored = ARAPRegistration.directionScores(correspondence, under: alignment)[0]
            return (scored.reversed, abs(scored.forward - scored.backward))
        }

        let same = bit([hook], [hookTarget])
        XCTAssertFalse(same.reversed, "the target runs the same way; nothing to reverse")
        XCTAssertGreaterThan(same.gap, 1, "and it says so with a real margin, not a coin toss")

        let flipped = bit([hook], [hookTarget.reversed()])
        XCTAssertTrue(flipped.reversed, "recorded backwards, the geometry says so plainly")
        XCTAssertGreaterThan(flipped.gap, 1)

        // A straight stroke fits itself exactly in *both* directions, so the two scores are equal
        // and the drawn order stands. This is the case that broke when the margin was expressed as
        // a fraction of the forward score instead of the stroke's length — see `directionMargin`.
        let straight = polyline(CGPoint(x: 0, y: 0), CGPoint(x: 55, y: 0))
        let straightTarget = straight.map(moved.applied(to:))
        for target in [straightTarget, straightTarget.reversed()] {
            let scored = bit([straight], [target])
            XCTAssertFalse(scored.reversed, "a straight stroke carries no direction evidence")
            XCTAssertLessThan(scored.gap, 1e-6, "and the two directions score identically")
        }
    }

    /// **The correspondence is only taken 1:1, and case 30 is what "not 1:1" looks like.**
    ///
    /// Two strokes becoming one is the N:M case, which stays deferred (§8 item 33) — neither paper
    /// solves it algorithmically, and Phase 5's grouping UI is the mechanism the literature actually
    /// uses. So this pairing is refused and registration falls back to the point-cloud path, which
    /// after §8 item 32 is good enough to watch even though nothing about the *merge* is solved.
    func testAMismatchedStrokeCountRefusesTheCorrespondenceRatherThanGuessing() {
        let two = ARAPRegistration.StrokeCorrespondence(
            source: [polyline(CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 400)),
                     polyline(CGPoint(x: 500, y: 200), CGPoint(x: 500, y: 400))],
            target: [polyline(CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 400))])
        XCTAssertFalse(two.isPairable, "2 → 1 is the deferred N:M case")
        XCTAssertTrue(ARAPRegistration.arcLengthConstraints(two, under: .identity).isEmpty,
                      "and it produces no constraints, which is what selects the fallback path")

        let degenerate = ARAPRegistration.StrokeCorrespondence(
            source: [[CGPoint(x: 1, y: 1)]], target: [polyline(.zero, CGPoint(x: 10, y: 0))])
        XCTAssertFalse(degenerate.isPairable, "a single point is not a stroke to pair along")
    }
}
