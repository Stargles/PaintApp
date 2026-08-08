import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for guide strokes — Phase 7 of VECTOR_INTERPOLATION_IMPLEMENTATION.md.
///
/// A guide carries two signals out of one gesture (`PLAN.md` §6.1) and they are tested apart before
/// they are tested together, because the whole design rests on them being independent: geometry is
/// read by **arc length**, timing by **stylus time**, and neither may leak into the other.
///
/// What is being pinned, in descending order of how expensive it would be to discover later:
///
/// 1. **A guide never breaks the endpoint invariant.** `t = 0` reproduces keyframe A and `t = 1`
///    keyframe C, bit for bit, with any guide attached. Phase 1 paid a change of variables for that
///    property and every phase since has kept it; a trajectory constraint is the first thing with a
///    real opportunity to spoil it, and `chordDeviation` is shaped the way it is to make it fall out
///    rather than be guarded.
/// 2. **Speed does not move the arc, and shape does not retime the motion.** If the two signals were
///    coupled, hesitating mid-stroke would bend the path.
/// 3. **The three ways of binding a guide agree.** The model offers a binding list, a recipe list and
///    the guide's own `boundGroups`, and `GuideSet` is the one place they are reconciled.
final class InterpolationGuideLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let brush = BrushLibrary.hardRound

    /// A guide with evenly spaced timestamps — constant stylus velocity along whatever shape.
    private func guide(_ points: [CGPoint], step: TimeInterval = 0.01) -> [TimedSample] {
        points.enumerated().map {
            TimedSample(point: $1, pressure: 1, time: TimeInterval($0) * step)
        }
    }

    /// A straight left-to-right guide, 100 long.
    private func straight() -> [TimedSample] {
        guide((0...10).map { CGPoint(x: CGFloat($0) * 10, y: 0) })
    }

    /// A guide whose chord is the same 100-long horizontal run but which bows +40 in y at its
    /// midpoint. Three samples, so the arc-length midpoint *is* the apex — which keeps the expected
    /// deviation exact rather than approximate.
    private func arched() -> [TimedSample] {
        guide([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 40), CGPoint(x: 100, y: 0)])
    }

    private func path(_ samples: [TimedSample]) throws -> GuidePath {
        try XCTUnwrap(GuidePath(samples: samples))
    }

    // MARK: - GuidePath construction

    func testAPathNeedsTwoDistinctPoints() {
        XCTAssertNil(GuidePath(samples: []))
        XCTAssertNil(GuidePath(samples: [TimedSample(point: .zero, pressure: 1, time: 0)]))
    }

    /// A pen held still emits a run of coincident samples. They carry no arc, and a guide made of
    /// nothing but them is not a path — the caller has to apply *no* constraint rather than a zero
    /// one, which is why the initialiser is failable.
    func testAGuideOfCoincidentSamplesIsNotAPath() {
        let held = (0..<8).map { TimedSample(point: CGPoint(x: 5, y: 5), pressure: 1,
                                             time: TimeInterval($0) * 0.01) }
        XCTAssertNil(GuidePath(samples: held))
    }

    func testCoincidentSamplesInsideAPathAreDroppedWithoutMovingIt() throws {
        var withPauses = [TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1, time: 0)]
        for i in 1...5 {  // the pen rests at the origin, then moves off
            withPauses.append(TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1,
                                          time: TimeInterval(i) * 0.01))
        }
        withPauses.append(TimedSample(point: CGPoint(x: 100, y: 0), pressure: 1, time: 0.1))
        let p = try path(withPauses)
        XCTAssertEqual(p.length, 100, accuracy: 1e-9)
        XCTAssertEqual(p.point(atArcFraction: 0.5).x, 50, accuracy: 1e-9)
    }

    // MARK: - Geometry, read by arc length

    /// Arc length, not sample index. An unevenly *sampled* straight line still has its geometric
    /// midpoint at `u = 0.5` — the property that makes the shape independent of how the stylus was
    /// moving when it was drawn.
    func testTheMidpointIsGeometricRatherThanBySampleIndex() throws {
        // Nine samples crowded into the first tenth, then one at the far end.
        var points = (0...8).map { CGPoint(x: CGFloat($0), y: 0) }
        points.append(CGPoint(x: 100, y: 0))
        let p = try path(guide(points))
        XCTAssertEqual(p.point(atArcFraction: 0.5).x, 50, accuracy: 1e-9)
        XCTAssertEqual(p.point(atArcFraction: 0.25).x, 25, accuracy: 1e-9)
    }

    /// **The endpoint invariant, at the level of the geometry.** Zero at both ends by construction,
    /// which is what lets a guide be attached without disturbing `t = 0` or `t = 1`.
    func testChordDeviationIsExactlyZeroAtBothEnds() throws {
        let p = try path(arched())
        for u in [CGFloat(0), 1] {
            let d = p.chordDeviation(atArcFraction: u)
            XCTAssertEqual(d.dx, 0, accuracy: 1e-12)
            XCTAssertEqual(d.dy, 0, accuracy: 1e-12)
        }
    }

    /// A straight guide is a guide that says nothing, and it has to *do* nothing — otherwise every
    /// roughly-straight guide would nudge the motion by its own hand-jitter.
    func testAStraightGuideDeviatesNowhere() throws {
        let p = try path(straight())
        for u in stride(from: CGFloat(0), through: 1, by: 0.1) {
            let d = p.chordDeviation(atArcFraction: u)
            XCTAssertEqual(hypot(d.dx, d.dy), 0, accuracy: 1e-9)
        }
    }

    func testAnArchedGuideBowsTheWayItWasDrawn() throws {
        let p = try path(arched())
        let mid = p.chordDeviation(atArcFraction: 0.5)
        XCTAssertEqual(mid.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(mid.dy, 40, accuracy: 1e-9)
    }

    /// **Signal independence, geometry half.** The same shape drawn at wildly different speeds — and
    /// with a long pause in the middle — must give the identical arc. If timing leaked into the
    /// geometry, hesitating would bend the path.
    func testStylusSpeedDoesNotChangeTheArc() throws {
        let fast = try path(arched())
        let uneven = try path([
            TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1, time: 0),
            TimedSample(point: CGPoint(x: 50, y: 40), pressure: 1, time: 0.01),
            TimedSample(point: CGPoint(x: 100, y: 0), pressure: 1, time: 9.0),
        ])
        for u in stride(from: CGFloat(0), through: 1, by: 0.05) {
            let a = fast.chordDeviation(atArcFraction: u)
            let b = uneven.chordDeviation(atArcFraction: u)
            XCTAssertEqual(a.dx, b.dx, accuracy: 1e-9)
            XCTAssertEqual(a.dy, b.dy, accuracy: 1e-9)
        }
    }

    // MARK: - Timing, read by stylus clock

    func testConstantVelocityGivesAnEssentiallyLinearCurve() throws {
        let curve = try path(straight()).spacingCurve()
        XCTAssertEqual(curve.kind, .sampled)
        for tau in stride(from: CGFloat(0), through: 1, by: 0.05) {
            XCTAssertEqual(curve.eased(tau), tau, accuracy: 1e-6)
        }
    }

    /// `PLAN.md` §6.1's headline claim, and the reason the brief's idea is worth building: drawing
    /// the guide **fast at the start and slow at the end** gives ease-out with no graph editor.
    /// Most of the arc is covered early, so the curve is above the diagonal throughout.
    func testDrawingFastThenSlowlyGivesEaseOut() throws {
        let p = try path([
            TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1, time: 0),
            TimedSample(point: CGPoint(x: 25, y: 0), pressure: 1, time: 0.05),
            TimedSample(point: CGPoint(x: 50, y: 0), pressure: 1, time: 0.10),
            TimedSample(point: CGPoint(x: 75, y: 0), pressure: 1, time: 0.15),
            TimedSample(point: CGPoint(x: 100, y: 0), pressure: 1, time: 1.00),
        ])
        let curve = p.spacingCurve()
        XCTAssertGreaterThan(curve.eased(0.5), 0.6)
        for tau in stride(from: CGFloat(0.05), through: 0.95, by: 0.05) {
            XCTAssertGreaterThan(curve.eased(tau), tau - 1e-9)
        }
    }

    func testDrawingSlowlyThenFastGivesEaseIn() throws {
        let p = try path([
            TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1, time: 0),
            TimedSample(point: CGPoint(x: 25, y: 0), pressure: 1, time: 0.85),
            TimedSample(point: CGPoint(x: 50, y: 0), pressure: 1, time: 0.90),
            TimedSample(point: CGPoint(x: 75, y: 0), pressure: 1, time: 0.95),
            TimedSample(point: CGPoint(x: 100, y: 0), pressure: 1, time: 1.00),
        ])
        let curve = p.spacingCurve()
        XCTAssertLessThan(curve.eased(0.5), 0.4)
    }

    /// A spacing curve that dipped would run the in-between backwards mid-scrub. Cumulative arc
    /// length cannot decrease, so this is structural rather than a tuning matter — worth a tripwire
    /// because any future resampling of the curve could break it.
    func testTheSpacingCurveIsMonotone() throws {
        let p = try path([
            TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1, time: 0),
            TimedSample(point: CGPoint(x: 90, y: 0), pressure: 1, time: 0.2),
            TimedSample(point: CGPoint(x: 95, y: 0), pressure: 1, time: 0.9),
            TimedSample(point: CGPoint(x: 100, y: 0), pressure: 1, time: 1.0),
        ])
        let curve = p.spacingCurve()
        var previous: CGFloat = -1
        for tau in stride(from: CGFloat(0), through: 1, by: 0.02) {
            let v = curve.eased(tau)
            XCTAssertGreaterThanOrEqual(v, previous - 1e-9)
            previous = v
        }
    }

    func testTheSpacingCurveEndpointsAreExact() throws {
        let curve = try path(arched()).spacingCurve()
        XCTAssertEqual(curve.eased(0), 0, accuracy: 0)
        XCTAssertEqual(curve.eased(1), 1, accuracy: 0)
    }

    /// **A synthetic touch has no velocity, and inventing one would be worse than declining.** Every
    /// XCUITest-driven guide, and any guide replayed from a source without timestamps, arrives with
    /// all samples on one clock reading. `.linear` is the honest answer.
    func testAGuideWithNoTimingDeclinesToInventAnEasing() throws {
        let untimed = arched().map { TimedSample(point: $0.point, pressure: 1, time: 0) }
        let p = try path(untimed)
        XCTAssertEqual(p.duration, 0)
        XCTAssertEqual(p.spacingCurve().kind, .linear)
        // ...and the geometry is untouched by the missing timing, which is the point of reading the
        // two signals off different parameters.
        XCTAssertEqual(p.chordDeviation(atArcFraction: 0.5).dy, 40, accuracy: 1e-9)
    }

    // MARK: - GuideSet — reconciling the three ways to bind

    private func recipeWith(groupIDs: [UUID], recipeGuides: [UUID] = [],
                            bindingGuides: [UUID: [UUID]] = [:]) -> InterpolationRecipe {
        InterpolationRecipe(
            groups: groupIDs.map { MotionGroupBinding(groupID: $0, guideIDs: bindingGuides[$0] ?? []) },
            guideIDs: recipeGuides)
    }

    private func guideStroke(_ samples: [TimedSample], boundGroups: [UUID] = [],
                             role: GuideRole = .both) -> GuideStroke {
        GuideStroke(samples: samples,
                    interval: KeyframeInterval(start: CelRef(layerID: UUID(), celID: UUID()),
                                               end: CelRef(layerID: UUID(), celID: UUID())),
                    boundGroups: boundGroups, role: role)
    }

    func testAGuideNamedOnTheBindingDrivesThatGroupOnly() {
        let a = UUID(), b = UUID()
        let g = guideStroke(arched())
        let recipe = recipeWith(groupIDs: [a, b], bindingGuides: [a: [g.id]])
        XCTAssertEqual(GuideSet(binding: recipe.groups[0], recipe: recipe, guides: [g]).trajectories.count, 1)
        XCTAssertTrue(GuideSet(binding: recipe.groups[1], recipe: recipe, guides: [g]).isEmpty)
    }

    /// `PLAN.md` §10 decision 6's whole-frame binding: a guide on the recipe with an empty
    /// `boundGroups` drives every group, and the decision's "almost nothing" cost is exactly this —
    /// no new field, no new mechanism, just the two lists meeting.
    func testAWholeFrameGuideDrivesEveryGroup() {
        let a = UUID(), b = UUID()
        let g = guideStroke(arched(), boundGroups: [])
        let recipe = recipeWith(groupIDs: [a, b], recipeGuides: [g.id])
        for binding in recipe.groups {
            XCTAssertEqual(GuideSet(binding: binding, recipe: recipe, guides: [g]).trajectories.count, 1)
        }
    }

    func testAGuideNamingItsGroupsDrivesOnlyThose() {
        let a = UUID(), b = UUID()
        let g = guideStroke(arched(), boundGroups: [b])
        let recipe = recipeWith(groupIDs: [a, b], recipeGuides: [g.id])
        XCTAssertTrue(GuideSet(binding: recipe.groups[0], recipe: recipe, guides: [g]).isEmpty)
        XCTAssertEqual(GuideSet(binding: recipe.groups[1], recipe: recipe, guides: [g]).trajectories.count, 1)
    }

    func testRoleSplitsTheTwoSignals() {
        let a = UUID()
        let shapeOnly = guideStroke(arched(), role: .trajectory)
        let timeOnly = guideStroke(arched(), role: .timing)

        let r1 = recipeWith(groupIDs: [a], recipeGuides: [shapeOnly.id])
        let s1 = GuideSet(binding: r1.groups[0], recipe: r1, guides: [shapeOnly])
        XCTAssertEqual(s1.trajectories.count, 1)
        XCTAssertNil(s1.spacing)

        let r2 = recipeWith(groupIDs: [a], recipeGuides: [timeOnly.id])
        let s2 = GuideSet(binding: r2.groups[0], recipe: r2, guides: [timeOnly])
        XCTAssertTrue(s2.trajectories.isEmpty)
        XCTAssertNotNil(s2.spacing)
    }

    /// Two guides average rather than sum. Summing would double the swing, which reads as a bug;
    /// the mean is a path the artist can still recognise. Either way the ends stay pinned.
    func testTwoTrajectoryGuidesAverageRatherThanSum() {
        let a = UUID()
        let up = guideStroke(arched())
        let flat = guideStroke(straight())
        let recipe = recipeWith(groupIDs: [a], recipeGuides: [up.id, flat.id])
        let set = GuideSet(binding: recipe.groups[0], recipe: recipe, guides: [up, flat])
        XCTAssertEqual(set.trajectories.count, 2)
        XCTAssertEqual(set.deviation(atArcFraction: 0.5).dy, 20, accuracy: 1e-9)
        XCTAssertEqual(set.deviation(atArcFraction: 0).dy, 0, accuracy: 1e-12)
        XCTAssertEqual(set.deviation(atArcFraction: 1).dy, 0, accuracy: 1e-12)
    }

    /// Naming the same guide on both lists must not apply it twice — which, with averaging, would
    /// otherwise be silent rather than obviously wrong.
    func testAGuideNamedTwiceIsAppliedOnce() {
        let a = UUID()
        let g = guideStroke(arched())
        let recipe = recipeWith(groupIDs: [a], recipeGuides: [g.id], bindingGuides: [a: [g.id]])
        let set = GuideSet(binding: recipe.groups[0], recipe: recipe, guides: [g])
        XCTAssertEqual(set.trajectories.count, 1)
        XCTAssertEqual(set.deviation(atArcFraction: 0.5).dy, 40, accuracy: 1e-9)
    }

    func testAGuideIDWithNoGuideBehindItIsIgnored() {
        let a = UUID()
        let recipe = recipeWith(groupIDs: [a], recipeGuides: [UUID()])
        XCTAssertTrue(GuideSet(binding: recipe.groups[0], recipe: recipe, guides: []).isEmpty)
    }

    // MARK: - Through the evaluator

    private func manager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        return manager
    }

    private func stroke(_ points: [CGPoint]) -> VectorStroke {
        VectorStroke(id: UUID(), brush: Self.brush,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) })
    }

    /// A bar at x = 10…30 in keyframe A and x = 34…54 in keyframe C, generated onto the middle cel.
    @discardableResult
    private func generated(_ manager: CanvasManager) -> [Cel] {
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cels = (0..<3).map { i in
            Cel(id: UUID(), startFrame: i * 4, frameCount: 4, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        manager.layers[1].cels = cels
        cels[0].vector?.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 20),
                                          CGPoint(x: 30, y: 40)]))
        cels[2].vector?.addStroke(stroke([CGPoint(x: 34, y: 20), CGPoint(x: 54, y: 20),
                                          CGPoint(x: 54, y: 40)]))
        manager.enterInterpolateMode()
        for cel in [cels[0], cels[2]] {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: manager.layers[1].id)
        }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))
        return manager.layers[1].cels
    }

    private func forwardPoints(_ manager: CanvasManager, at t: CGFloat,
                               guides: [GuideStroke]) throws -> [CGPoint] {
        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        let e = try XCTUnwrap(InterpolationEvaluator.evaluate(
            recipe: recipe, at: t, content: manager.interpolationContentProvider, guides: guides))
        return e.forward.compactMap(\.stroke).flatMap { $0.samples.map(\.point) }
    }

    private func attach(_ guide: GuideStroke, to manager: CanvasManager) {
        manager.layers[1].cels[1].interpolation?.guideIDs = [guide.id]
    }

    /// **The invariant a trajectory constraint is most able to break, and it does not.** The frame at
    /// `t = 0` is keyframe A and at `t = 1` it is keyframe C — with a guide bowing the middle by 40
    /// points, the ends must still land on the identical samples they land on with no guide at all.
    ///
    /// This is `chordDeviation`'s whole shape justifying itself: the deviation is taken from the
    /// guide's own chord, so it is zero at both ends arithmetically rather than by a guard someone
    /// could later tidy away.
    func testAGuideLeavesBothEndpointsExactlyWhereTheyWere() throws {
        let manager = manager()
        generated(manager)
        let g = guideStroke(arched())
        attach(g, to: manager)

        for t in [CGFloat(0), 1] {
            let unguided = try forwardPoints(manager, at: t, guides: [])
            let guided = try forwardPoints(manager, at: t, guides: [g])
            XCTAssertEqual(unguided.count, guided.count)
            for (a, b) in zip(unguided, guided) {
                XCTAssertEqual(a.x, b.x, accuracy: 0)
                XCTAssertEqual(a.y, b.y, accuracy: 0)
            }
        }
    }

    /// The point of the whole feature: an arced guide makes the motion arc. At `t = 0.5` the frame
    /// sits 40 points above where the straight-line interpolation would put it — the guide's own
    /// deviation from its chord, applied as a rigid translation of the group.
    func testAnArchedGuideLiftsTheInBetweenOffTheStraightLine() throws {
        let manager = manager()
        generated(manager)
        let g = guideStroke(arched())
        attach(g, to: manager)

        let unguided = try forwardPoints(manager, at: 0.5, guides: [])
        let guided = try forwardPoints(manager, at: 0.5, guides: [g])
        XCTAssertEqual(unguided.count, guided.count)
        XCTAssertFalse(unguided.isEmpty)
        for (a, b) in zip(unguided, guided) {
            XCTAssertEqual(b.x - a.x, 0, accuracy: 1e-6)
            XCTAssertEqual(b.y - a.y, 40, accuracy: 1e-6)
        }
    }

    /// **Signal independence, timing half, measured through the real evaluation.** A `.timing` guide
    /// changes *when* the frame is along its motion and never *where* the motion goes: the guided
    /// frame at `t` has to equal the unguided frame at the eased `t`, exactly.
    func testATimingGuideRetimesTheMotionWithoutMovingThePath() throws {
        let manager = manager()
        generated(manager)
        let g = guideStroke([
            TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1, time: 0),
            TimedSample(point: CGPoint(x: 25, y: 0), pressure: 1, time: 0.05),
            TimedSample(point: CGPoint(x: 50, y: 0), pressure: 1, time: 0.10),
            TimedSample(point: CGPoint(x: 75, y: 0), pressure: 1, time: 0.15),
            TimedSample(point: CGPoint(x: 100, y: 0), pressure: 1, time: 1.00),
        ], role: .timing)
        attach(g, to: manager)

        let curve = try path(g.samples).spacingCurve()
        let eased = curve.eased(0.5)
        XCTAssertGreaterThan(eased, 0.6)  // the fixture really is ease-out

        let guided = try forwardPoints(manager, at: 0.5, guides: [g])
        let unguidedAtEased = try forwardPoints(manager, at: eased, guides: [])
        XCTAssertEqual(guided.count, unguidedAtEased.count)
        for (a, b) in zip(guided, unguidedAtEased) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-6)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
        }
    }

    /// **The precedence that makes Phase 7 item 5 buildable.** Its spacing chart retimes a frame by
    /// writing `binding.spacing`; if a guide's derived timing outranked that, dragging a dot would
    /// appear to do nothing. An explicit per-group curve wins.
    func testAnExplicitGroupSpacingOutranksAGuidesDerivedTiming() throws {
        let manager = manager()
        generated(manager)
        let g = guideStroke([
            TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1, time: 0),
            TimedSample(point: CGPoint(x: 90, y: 0), pressure: 1, time: 0.1),
            TimedSample(point: CGPoint(x: 100, y: 0), pressure: 1, time: 1.0),
        ], role: .timing)
        attach(g, to: manager)
        manager.layers[1].cels[1].interpolation?.groups[0].spacing = SpacingCurve(kind: .linear)

        let guided = try forwardPoints(manager, at: 0.5, guides: [g])
        let plainLinear = try forwardPoints(manager, at: 0.5, guides: [])
        for (a, b) in zip(guided, plainLinear) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-6)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
        }
    }

    // MARK: - The document's resolver

    /// One resolver feeds both the evaluation and `InterpolationPreviewKey`, so that a guide edit
    /// cannot change what is drawn without also changing what the memoization compares — the trap
    /// §5 records that key falling into three times.
    func testTheManagerResolvesExactlyTheGuidesARecipeNames() {
        let manager = manager()
        let a = UUID()
        let used = guideStroke(arched())
        let alsoUsed = guideStroke(straight())
        let unrelated = guideStroke(arched())
        manager.guideStrokes = [used, alsoUsed, unrelated]

        let recipe = recipeWith(groupIDs: [a], recipeGuides: [used.id],
                                bindingGuides: [a: [alsoUsed.id, used.id]])
        let resolved = manager.guides(driving: recipe)
        XCTAssertEqual(Set(resolved.map(\.id)), Set([used.id, alsoUsed.id]))
        XCTAssertEqual(resolved.count, 2, "a guide named on both lists must resolve once")
        XCTAssertTrue(manager.guides(driving: InterpolationRecipe()).isEmpty)
    }

    // MARK: - Recording a drawn guide (item 2's document half)

    /// The whole item-2 loop without the view: draw a guide, and the frame arcs. The capture path
    /// itself is `StrokeCanvasView`'s and is the one part only an XCUITest reaches.
    func testARecordedGuideBendsTheFrameItWasDrawnOn() throws {
        let manager = manager()
        generated(manager)
        manager.currentFrame = 4  // the in-between block, so `interpolationTarget` resolves to it
        manager.currentLayerIndex = 1

        let straightLine = try forwardPoints(manager, at: 0.5, guides: [])
        XCTAssertNil(manager.recordGuideStroke(samples: arched()))

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(recipe.guideIDs.count, 1)
        XCTAssertEqual(manager.guideStrokes.count, 1)

        let arcedNow = try forwardPoints(manager, at: 0.5, guides: manager.guides(driving: recipe))
        for (a, b) in zip(straightLine, arcedNow) {
            XCTAssertEqual(b.y - a.y, 40, accuracy: 1e-6)
        }
    }

    /// **A guide is a constraint on a motion, so there has to be a motion.** Storing it unbound and
    /// hoping a later Generate adopted it is the silent-no-op this feature has refused three times.
    func testAGuideOnAFrameWithNoRecipeIsRefused() {
        let manager = manager()
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        manager.layers[1].cels = [Cel(id: UUID(), startFrame: 0, frameCount: 12,
                                      raster: .empty(size: size), vector: .empty(size: size))]
        manager.currentLayerIndex = 1
        manager.currentFrame = 0

        XCTAssertEqual(manager.guideRefusal, .noInterpolationToGuide)
        XCTAssertEqual(manager.recordGuideStroke(samples: arched()), .noInterpolationToGuide)
        XCTAssertTrue(manager.guideStrokes.isEmpty)
    }

    /// One artist action, one undo step — covering the registry *and* the binding. An undo that put
    /// the guide back in the registry bound to nothing would be a leak they cannot see.
    func testUndoingAGuideRemovesBothTheGuideAndItsBinding() throws {
        let manager = manager()
        generated(manager)
        manager.currentFrame = 4
        manager.currentLayerIndex = 1
        XCTAssertNil(manager.recordGuideStroke(samples: arched()))

        manager.undo()
        XCTAssertTrue(manager.guideStrokes.isEmpty)
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.guideIDs, [])

        manager.redo()
        XCTAssertEqual(manager.guideStrokes.count, 1)
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.guideIDs.count, 1)
    }

    /// Guides are invisible outside interpolate mode (§0 requirement 6), and the overlay reads this
    /// property rather than the registry — a scene accumulates guides across every interval it has
    /// had one on, and drawing all of them at once would bury the one being worked on.
    func testGuidesAreOnlyVisibleInsideInterpolateMode() throws {
        let manager = manager()
        generated(manager)
        manager.currentFrame = 4
        manager.currentLayerIndex = 1
        XCTAssertNil(manager.recordGuideStroke(samples: arched()))
        XCTAssertEqual(manager.visibleGuideStrokes.count, 1)

        manager.exitInterpolateMode()
        XCTAssertTrue(manager.visibleGuideStrokes.isEmpty)
        XCTAssertEqual(manager.guideStrokes.count, 1, "leaving the mode hides guides, never deletes them")
    }

    /// Armed state left set turns the next ordinary gesture into something the artist did not ask
    /// for — the same trap `armedMotionGroupID` documents, and louder here because a guide does not
    /// appear in the layer at all.
    func testLeavingTheModeDisarmsGuideDrawing() {
        let manager = manager()
        manager.enterInterpolateMode()
        manager.isDrawingGuide = true
        manager.exitInterpolateMode()
        XCTAssertFalse(manager.isDrawingGuide)
    }

    /// A guide edit keeps the guide's id (`PLAN.md` §6.4 — reuse across frames is a reference, not a
    /// copy), so the resolved list has to differ by **value** or the preview would keep the stale
    /// frame. This is the assertion standing in for the fourth `InterpolationPreviewKey` bug.
    func testEditingAGuideChangesTheResolvedListWhileKeepingItsID() throws {
        let manager = manager()
        let a = UUID()
        var g = guideStroke(straight())
        manager.guideStrokes = [g]
        let recipe = recipeWith(groupIDs: [a], recipeGuides: [g.id])

        let before = manager.guides(driving: recipe)
        g.samples = arched()
        manager.updateGuideStroke(g)
        let after = manager.guides(driving: recipe)

        XCTAssertEqual(before.map(\.id), after.map(\.id), "the id is what makes reuse a reference")
        XCTAssertNotEqual(before, after, "but the value has to move, or the preview key cannot see it")
    }
}
