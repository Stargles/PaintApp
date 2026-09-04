import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for guide strokes.
///
/// A guide carries two signals out of one gesture, and they are tested apart before
/// they are tested together, because the whole design rests on them being independent: geometry is
/// read by **arc length**, timing by **stylus time**, and neither may leak into the other.
///
/// What is being pinned, in descending order of how expensive it would be to discover later:
///
/// 1. **A guide never breaks the endpoint invariant.** `t = 0` reproduces keyframe A and `t = 1`
///    keyframe C, bit for bit, with any guide attached. A trajectory constraint is the first thing
///    with a real opportunity to spoil that, and `chordDeviation` is shaped the way it is to make it
///    fall out rather than be guarded.
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

    /// The headline claim, and the reason the whole feature is worth building: drawing
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

    /// The whole-frame binding: a guide on the recipe with an empty
    /// `boundGroups` drives every group, at almost no cost — no new field, no new mechanism, just the
    /// two lists meeting.
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
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
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

    /// A guide edit keeps the guide's id — reuse across frames is a reference, not a
    /// copy — so the resolved list has to differ by **value** or the preview would keep the stale
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

    // MARK: - Editable handles (item 2's other half)

    /// A straight guide sampled finely enough that a sample lands on every quarter of the handle
    /// falloff radius — which is what lets the kernel's shape be asserted on real indices rather
    /// than by restating the formula.
    private func dense() -> [TimedSample] {
        guide((0...40).map { CGPoint(x: CGFloat($0) * 2.5, y: 0) })
    }

    /// A guide long enough for the full set gets one handle per requested position, each **on a
    /// sample** and in path order, with the two ends pinned to the real ends.
    ///
    /// Sitting on a sample is what makes a dragged handle land exactly under the finger; placing
    /// them at abstract arc fractions would leave each one short by however far the nearest sample
    /// was, and the gap would grow as the drag lengthened the arc.
    func testHandlesSitOnSamplesInOrderWithTheEndsPinned() {
        let samples = straight()
        let indices = GuideHandles.indices(in: samples)

        XCTAssertEqual(indices.count, GuideHandles.count)
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, samples.count - 1)
        XCTAssertEqual(indices, indices.sorted())
        XCTAssertEqual(Set(indices).count, indices.count, "no two handles on one sample")
    }

    /// Handles are placed by **arc length**, not by sample index — the same parameterisation the
    /// trajectory is read on. On a path whose samples bunch at one end, index-spacing would put four
    /// of the five handles inside the bunch.
    func testHandlesAreSpacedByArcLengthRatherThanBySampleIndex() throws {
        // Half the samples crammed into the first tenth of the path — a pen that started slowly.
        // Spacing by index would put three of the five handles inside that tenth.
        let bunched = guide((0...10).map { CGPoint(x: CGFloat($0), y: 0) }
                            + (1...10).map { CGPoint(x: 10 + CGFloat($0) * 9, y: 0) })
        let positions = GuideHandles.positions(in: bunched)

        XCTAssertEqual(positions.count, GuideHandles.count)
        for (i, p) in positions.enumerated() {
            XCTAssertEqual(p.x, 100 * CGFloat(i) / CGFloat(GuideHandles.count - 1), accuracy: 6,
                           "handle \(i) should sit at its arc-length station, not its index's")
        }
    }

    /// Nothing to grab on something that is not a path, rather than five handles stacked on one
    /// point — the same answer `GuidePath`'s failable initialiser gives for the same input.
    func testAGuideWithNoArcOffersNoHandles() {
        XCTAssertTrue(GuideHandles.indices(in: []).isEmpty)
        XCTAssertTrue(GuideHandles.indices(in: guide([CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)])).isEmpty)
    }

    /// The handle goes exactly where it was put — no falloff rounding, no drift.
    func testAHandleLandsExactlyWhereItWasDragged() throws {
        let samples = straight()
        let index = try XCTUnwrap(GuideHandles.indices(in: samples).dropFirst().first)
        let destination = CGPoint(x: 25, y: -60)

        let moved = GuideHandles.dragged(samples, index: index, to: destination)
        XCTAssertEqual(moved[index].x, destination.x, accuracy: 1e-9)
        XCTAssertEqual(moved[index].y, destination.y, accuracy: 1e-9)
    }

    /// **Dragging one handle moves no other handle.** The falloff radius is exactly the arc distance
    /// between neighbours and the kernel is zero there, so the five behave as independent controls
    /// rather than a set that shoves each other around. Change the radius and this is what breaks.
    func testDraggingAHandleMovesNoOtherHandle() throws {
        let samples = straight()
        let indices = GuideHandles.indices(in: samples)
        let grabbed = indices[2]

        let moved = GuideHandles.dragged(samples, index: grabbed, to: CGPoint(x: 50, y: 70))
        for index in indices where index != grabbed {
            XCTAssertEqual(moved[index].x, samples[index].x, accuracy: 1e-9)
            XCTAssertEqual(moved[index].y, samples[index].y, accuracy: 1e-9)
        }
    }

    /// The consequence that matters most: the ends are handles too, so reshaping the middle of an
    /// arc leaves the chord alone — and the chord is what `chordDeviation` measures against. Without
    /// it, nudging the middle of a guide would quietly re-aim where the whole motion starts and ends.
    func testAnInteriorDragLeavesTheChordExactlyWhereItWas() throws {
        let dense = self.dense()
        let indices = GuideHandles.indices(in: dense)

        let moved = GuideHandles.dragged(dense, index: indices[2], to: CGPoint(x: 50, y: 40))
        XCTAssertEqual(moved[0].point, dense[0].point)
        XCTAssertEqual(moved[moved.count - 1].point, dense[dense.count - 1].point)
    }

    /// The neighbourhood comes along, and smoothly. The kernel is a raised cosine, so the sample
    /// **half a radius** from the handle moves half as far — a property of that curve rather than of
    /// this fixture. A linear falloff would agree here and leave a visible corner where the edit
    /// stops, which on a dashed overlay reads as a badly drawn guide rather than as an edit.
    func testTheNeighbourhoodFollowsUnderASmoothFalloff() throws {
        let dense = self.dense()  // 41 samples, 2.5 apart, so a sample sits at every quarter-radius
        let indices = GuideHandles.indices(in: dense)
        let grabbed = indices[2]
        let radiusInSamples = (indices[3] - grabbed)

        let moved = GuideHandles.dragged(dense, index: grabbed, to: CGPoint(x: dense[grabbed].x, y: 40))
        XCTAssertEqual(moved[grabbed + radiusInSamples / 2].y, 20, accuracy: 1e-6)

        // Monotone from the handle out to its neighbour: no bump, no reversal.
        for i in grabbed..<indices[3] {
            XCTAssertGreaterThanOrEqual(moved[i].y, moved[i + 1].y - 1e-9)
        }
    }

    /// Geometry only. The timestamps are what the easing is derived from, and rewriting them to keep
    /// the old curve across a reshape would invent timing the artist never drew.
    func testAHandleDragCarriesTimingAndPressureThrough() throws {
        let samples = straight()
        let moved = GuideHandles.dragged(samples, index: 5, to: CGPoint(x: 50, y: 99))

        XCTAssertEqual(moved.count, samples.count)
        XCTAssertEqual(moved.map(\.time), samples.map(\.time))
        XCTAssertEqual(moved.map(\.pressure), samples.map(\.pressure))
    }

    // MARK: - Handles through the document

    private func soleGuide(_ manager: CanvasManager) throws -> GuideStroke {
        try XCTUnwrap(manager.guideStrokes.first)
    }

    /// A guide on the in-between, ready to have its handles pulled.
    ///
    /// Sampled finely (`dense`) so the handles land on their arc stations exactly, which makes the
    /// deformed path symmetric about the middle handle and the expected deviation exact. A coarse
    /// guide works identically — the snapping is simply off-centre, and then the arithmetic a test
    /// would have to assert is no longer worth reading.
    private func guidedFrame() -> CanvasManager {
        let manager = manager()
        generated(manager)
        manager.currentFrame = 4
        manager.currentLayerIndex = 1
        manager.recordGuideStroke(samples: dense())
        return manager
    }

    /// **A drag is a pure function of the geometry at touch-down.** Three moves in one gesture give
    /// the same path as one move straight to the last position — because the manager re-derives from
    /// the touch-down samples rather than nudging what it produced last time. Applying deltas
    /// compounds the falloff, so the same drag made slowly (more touch samples) would bend the guide
    /// further than one made quickly.
    func testMovesWithinOneDragDoNotCompound() throws {
        let manager = guidedFrame()
        let guide0 = try soleGuide(manager)
        let index = GuideHandles.indices(in: guide0.samples)[2]
        let destination = CGPoint(x: 50, y: 60)

        manager.beginGuideHandleDrag(guideID: guide0.id)
        manager.dragGuideHandle(sampleIndex: index, to: CGPoint(x: 50, y: 20))
        manager.dragGuideHandle(sampleIndex: index, to: CGPoint(x: 50, y: 45))
        manager.dragGuideHandle(sampleIndex: index, to: destination)
        manager.commitGuideHandleDrag()

        let expected = GuideHandles.dragged(guide0.samples, index: index, to: destination)
        XCTAssertEqual(try soleGuide(manager).samples, expected)
    }

    /// One gesture, one undo step — the same bracket the `t` slider
    /// uses. A step per touch sample would make undo useless exactly where the artist is fiddling.
    ///
    /// The single `undo()` has to put the geometry back *and* leave the guide itself in place, which
    /// is what distinguishes "one step for the drag" from "no step at all".
    func testAWholeHandleDragIsOneUndoStep() throws {
        let manager = guidedFrame()
        let before = try soleGuide(manager)
        let index = GuideHandles.indices(in: before.samples)[2]

        manager.beginGuideHandleDrag(guideID: before.id)
        for y in stride(from: CGFloat(10), through: 60, by: 10) {
            manager.dragGuideHandle(sampleIndex: index, to: CGPoint(x: 50, y: y))
        }
        manager.commitGuideHandleDrag()
        XCTAssertNotEqual(try soleGuide(manager).samples, before.samples)

        manager.undo()
        XCTAssertEqual(try soleGuide(manager).samples, before.samples)
        XCTAssertEqual(manager.guideStrokes.count, 1, "one undo is the drag, not the guide")

        manager.redo()
        XCTAssertNotEqual(try soleGuide(manager).samples, before.samples)
    }

    /// A tap on a handle is not an edit. Recording a step that restores identical geometry makes the
    /// artist press undo twice to get anywhere — so the commit drops the gesture instead, and the one
    /// undo left is the guide's own creation.
    func testAHandleDragThatMovedNothingRecordsNoStep() throws {
        let manager = guidedFrame()
        let before = try soleGuide(manager)

        manager.beginGuideHandleDrag(guideID: before.id)
        manager.commitGuideHandleDrag()

        manager.undo()
        XCTAssertTrue(manager.guideStrokes.isEmpty, "the only step should be the guide's creation")
    }

    /// A second finger landing mid-drag puts the guide back exactly as it was and records nothing —
    /// the same answer a half-drawn stroke gets, and it must not leave the gesture snapshot behind
    /// for whichever drag commits next.
    func testCancellingAHandleDragRestoresTheGuideAndRecordsNothing() throws {
        let manager = guidedFrame()
        let before = try soleGuide(manager)
        let index = GuideHandles.indices(in: before.samples)[2]

        manager.beginGuideHandleDrag(guideID: before.id)
        manager.dragGuideHandle(sampleIndex: index, to: CGPoint(x: 50, y: 60))
        manager.cancelGuideHandleDrag()
        XCTAssertEqual(try soleGuide(manager).samples, before.samples)

        manager.undo()
        XCTAssertTrue(manager.guideStrokes.isEmpty, "a cancelled drag leaves nothing to undo")
    }

    /// A move that arrives with no drag in flight does nothing. The overlay can only send one after
    /// `touchesBegan` claimed a handle, but the guide can vanish under it — an undo, or a scrub off
    /// the in-between — and reshaping a guide the artist can no longer see would be unexplainable.
    func testAHandleMoveOutsideADragIsIgnored() throws {
        let manager = guidedFrame()
        let before = try soleGuide(manager)

        manager.dragGuideHandle(sampleIndex: 5, to: CGPoint(x: 50, y: 60))
        XCTAssertEqual(try soleGuide(manager).samples, before.samples)
    }

    // MARK: - Link and duplicate (item 7)

    /// A scene with **two** interpolated frames, which is the premise requirement 7 is about: an arc
    /// drawn once on one interval, fetched onto the next.
    ///
    /// Five cels four frames apart — keyframes at 0, 8 and 16, in-betweens generated at 4 and 12.
    /// Returns the manager sitting on the *second* in-between, with a guide already on the first.
    private func twoIntervals() throws -> CanvasManager {
        let manager = manager()
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cels = (0..<5).map { i in
            Cel(id: UUID(), startFrame: i * 4, frameCount: 4, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        manager.layers[1].cels = cels
        for (index, x) in [(0, CGFloat(10)), (2, 34), (4, 58)] {
            cels[index].vector?.addStroke(stroke([CGPoint(x: x, y: 20), CGPoint(x: x + 20, y: 20),
                                                  CGPoint(x: x + 20, y: 40)]))
        }
        manager.enterInterpolateMode()
        manager.currentLayerIndex = 1

        for cel in [cels[0], cels[2]] {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: manager.layers[1].id)
        }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))
        manager.currentFrame = 4
        manager.recordGuideStroke(samples: arched())

        for cel in [cels[0], cels[2]] {   // swap the pair over to the second interval
            manager.toggleInterpolationReference(celID: cel.id, inLayer: manager.layers[1].id)
        }
        for cel in [cels[2], cels[4]] {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: manager.layers[1].id)
        }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 3))
        manager.currentFrame = 12
        return manager
    }

    /// A guide on one interval is offered to the next, and is not offered to the interval that
    /// already has it — the library is "what you could fetch", not "everything that exists".
    func testAGuideFromAnotherIntervalIsOfferedAndItsOwnFrameIsNot() throws {
        let manager = try twoIntervals()
        let existing = try soleGuide(manager)
        XCTAssertTrue(manager.visibleGuideStrokes.isEmpty, "the second in-between has none yet")
        XCTAssertEqual(manager.linkableGuideStrokes.map(\.id), [existing.id])

        XCTAssertNil(manager.linkGuideStroke(id: existing.id))
        XCTAssertEqual(manager.visibleGuideStrokes.map(\.id), [existing.id])
        XCTAssertTrue(manager.linkableGuideStrokes.isEmpty, "already here, so no longer on offer")
    }

    /// **Link is a reference**: reshape the arc on either frame
    /// and both move. Fix a walk cycle's arc once and every frame of the walk follows.
    func testALinkedGuideIsOneGuideInTwoPlaces() throws {
        let manager = try twoIntervals()
        let existing = try soleGuide(manager)
        XCTAssertNil(manager.linkGuideStroke(id: existing.id))
        XCTAssertEqual(manager.guideStrokes.count, 1, "a link copies nothing")

        // Reshape it from the frame that fetched it.
        let index = GuideHandles.indices(in: existing.samples)[1]
        manager.beginGuideHandleDrag(guideID: existing.id)
        manager.dragGuideHandle(sampleIndex: index, to: CGPoint(x: 25, y: -70))
        manager.commitGuideHandleDrag()

        let edited = try soleGuide(manager)
        XCTAssertNotEqual(edited.samples, existing.samples)
        for cel in manager.layers[1].cels where cel.interpolation?.guideIDs.contains(existing.id) == true {
            let recipe = try XCTUnwrap(cel.interpolation)
            XCTAssertEqual(manager.guides(driving: recipe), [edited],
                           "both intervals read the one guide, so both moved")
        }
    }

    /// **Duplicate is a copy**: same arc, new identity, and editing one leaves the other alone.
    func testADuplicatedGuideIsIndependentOfItsSource() throws {
        let manager = try twoIntervals()
        let source = try soleGuide(manager)
        XCTAssertNil(manager.duplicateGuideStroke(id: source.id))
        XCTAssertEqual(manager.guideStrokes.count, 2)

        let copy = try XCTUnwrap(manager.visibleGuideStrokes.first)
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.samples, source.samples)

        let index = GuideHandles.indices(in: copy.samples)[1]
        manager.beginGuideHandleDrag(guideID: copy.id)
        manager.dragGuideHandle(sampleIndex: index, to: CGPoint(x: 25, y: -70))
        manager.commitGuideHandleDrag()

        XCTAssertEqual(manager.guideStrokes.first { $0.id == source.id }?.samples, source.samples,
                       "the source is untouched — that is the difference from a link")
    }

    /// A copy is authored *here*, and binds whole-frame rather than inheriting group bindings that
    /// may name no group in this recipe — the silent no-op this feature keeps declining.
    func testADuplicateTakesThisIntervalAndBindsWholeFrame() throws {
        let manager = try twoIntervals()
        let sourceID = try soleGuide(manager).id
        manager.guideStrokes[0].boundGroups = [UUID()]   // a group that is not in this recipe
        manager.guideStrokes[0].role = .timing

        XCTAssertNil(manager.duplicateGuideStroke(id: sourceID))
        let copy = try XCTUnwrap(manager.visibleGuideStrokes.first)
        XCTAssertTrue(copy.boundGroups.isEmpty, "whole-frame, like a freshly drawn guide")
        XCTAssertEqual(copy.role, .timing, "which signal it carries is a property of the drawing")

        let recipe = try XCTUnwrap(manager.layers[1].cels[3].interpolation)
        XCTAssertEqual(copy.interval.start, recipe.references.first?.cels.first)
        XCTAssertEqual(copy.interval.end, recipe.references.last?.cels.last)
    }

    /// The chip says when a guide is shared, because that is exactly what makes a handle drag on it
    /// move a frame the artist is not looking at.
    func testAChipSaysWhetherAGuideIsShared() throws {
        let manager = try twoIntervals()
        let existing = try soleGuide(manager)

        XCTAssertNil(manager.duplicateGuideStroke(id: existing.id))
        XCTAssertEqual(manager.guideChips.map(\.isShared), [false], "a copy is this frame's alone")

        XCTAssertNil(manager.linkGuideStroke(id: existing.id))
        let chips = manager.guideChips
        XCTAssertEqual(chips.map(\.number), [1, 2])
        XCTAssertEqual(chips.map(\.isShared), [false, true])
    }

    /// Fetching the same guide twice would leave a duplicate id on the recipe and, with two entries
    /// in the trajectory average, halve nothing — a no-op is the honest answer.
    func testLinkingAGuideThatIsAlreadyHereChangesNothing() throws {
        let manager = try twoIntervals()
        let existing = try soleGuide(manager)
        XCTAssertNil(manager.linkGuideStroke(id: existing.id))
        let before = manager.layers[1].cels[3].interpolation?.guideIDs

        XCTAssertNil(manager.linkGuideStroke(id: existing.id))
        XCTAssertEqual(manager.layers[1].cels[3].interpolation?.guideIDs, before)
    }

    /// One artist action, one undo step — and for duplicate that has to cover the registry *and* the
    /// binding, or undo leaves a guide nobody can see bound to nothing.
    func testLinkAndDuplicateAreEachOneUndoStep() throws {
        let manager = try twoIntervals()
        let existing = try soleGuide(manager)

        XCTAssertNil(manager.linkGuideStroke(id: existing.id))
        manager.undo()
        XCTAssertTrue(manager.visibleGuideStrokes.isEmpty)
        XCTAssertEqual(manager.guideStrokes.count, 1, "undoing a link deletes nothing")

        XCTAssertNil(manager.duplicateGuideStroke(id: existing.id))
        manager.undo()
        XCTAssertEqual(manager.guideStrokes.count, 1)
        XCTAssertTrue(manager.visibleGuideStrokes.isEmpty)
    }

    /// Same refusal as drawing one: a guide is a constraint on a motion, so there has to be a motion.
    func testFetchingAGuideOntoAFrameWithNoRecipeIsRefused() throws {
        let manager = try twoIntervals()
        let existing = try soleGuide(manager)
        manager.currentFrame = 0   // a keyframe: content, no recipe

        XCTAssertTrue(manager.linkableGuideStrokes.isEmpty)
        XCTAssertEqual(manager.linkGuideStroke(id: existing.id), .noInterpolationToGuide)
        XCTAssertEqual(manager.duplicateGuideStroke(id: existing.id), .noInterpolationToGuide)
        XCTAssertEqual(manager.guideStrokes.count, 1)
    }

    // MARK: - The spacing chart (item 5)

    /// A finger somewhere near the guide has to read as a position *along* it. Round-tripping through
    /// `point(atArcFraction:)` is the property that makes a dot drag land where it was aimed.
    func testTheNearestArcFractionInvertsThePointLookup() throws {
        let p = try path(arched())
        for u in stride(from: CGFloat(0), through: 1, by: 0.05) {
            XCTAssertEqual(p.arcFraction(nearest: p.point(atArcFraction: u)), u, accuracy: 1e-6)
        }
    }

    /// Off the path, the answer is the projection — and past either end it clamps, so a drag that
    /// overshoots parks on the keyframe rather than wrapping around.
    func testAPointOffThePathProjectsOntoIt() throws {
        let p = try path(straight())
        XCTAssertEqual(p.arcFraction(nearest: CGPoint(x: 30, y: 500)), 0.3, accuracy: 1e-6)
        XCTAssertEqual(p.arcFraction(nearest: CGPoint(x: -900, y: -900)), 0, accuracy: 1e-9)
        XCTAssertEqual(p.arcFraction(nearest: CGPoint(x: 900, y: 900)), 1, accuracy: 1e-9)
    }

    /// The chart of a linear curve is evenly spaced — the animator's chart for an unaccelerated move.
    /// Five frames means two pinned keyframes and three draggable in-betweens.
    func testAChartOfALinearCurveIsEvenlySpaced() {
        let chart = SpacingChart(curve: .linear, frames: 5)
        XCTAssertEqual(chart.stops, [0, 0.25, 0.5, 0.75, 1])
        XCTAssertEqual(Array(chart.draggable), [1, 2, 3])
    }

    /// The chart reads whatever curve is in force, so what the artist first sees is what they already
    /// have — a guide's own stylus timing included. Ease-out bunches the late frames.
    func testAChartReadsTheCurveItWasBuiltFrom() throws {
        let easeOut = SpacingChart(curve: SpacingCurve(kind: .easeOut), frames: 5)
        XCTAssertEqual(easeOut.stops.first, 0)
        XCTAssertEqual(easeOut.stops.last, 1)
        for i in 1..<easeOut.stops.count {
            XCTAssertGreaterThan(easeOut.stops[i], easeOut.stops[i - 1])
        }
        // Past the halfway point in time, ease-out is already past halfway along the motion.
        XCTAssertGreaterThan(easeOut.stops[2], 0.5)
    }

    /// **The round trip is exact**, which is what stops the dots creeping every time one is touched:
    /// the curve a chart means is `.sampled` at the chart's own stops, and reading a chart back off
    /// that curve samples it at exactly those inputs.
    func testAChartRoundTripsThroughItsCurve() {
        let chart = SpacingChart(curve: SpacingCurve(kind: .easeInOut), frames: 7)
            .moving(2, to: 0.1)
            .moving(4, to: 0.9)
        XCTAssertEqual(SpacingChart(curve: chart.curve, frames: 7).stops, chart.stops)
    }

    /// A dot goes where it is put, and only that dot moves.
    func testMovingAStopMovesOnlyThatStop() {
        let chart = SpacingChart(curve: .linear, frames: 5)
        let moved = chart.moving(2, to: 0.3)
        XCTAssertEqual(moved.stops, [0, 0.25, 0.3, 0.75, 1])
    }

    /// **The motion can never be made to run backwards.** Dragging past a neighbour parks the frame
    /// *on* it — a hold, which is a real thing to want — rather than reordering the frames, which is
    /// not. A chart that dipped would run the in-between backwards mid-scrub.
    func testAStopCannotBeDraggedPastItsNeighbours() {
        let chart = SpacingChart(curve: .linear, frames: 5)
        XCTAssertEqual(chart.moving(2, to: -5).stops[2], 0.25, accuracy: 1e-9)
        XCTAssertEqual(chart.moving(2, to: 5).stops[2], 0.75, accuracy: 1e-9)
    }

    /// The keyframes are where they are by definition, so their stops are not offered.
    func testTheEndStopsArePinnedAndNotDraggable() {
        let chart = SpacingChart(curve: .linear, frames: 5)
        XCTAssertEqual(chart.moving(0, to: 0.5).stops, chart.stops)
        XCTAssertEqual(chart.moving(4, to: 0.5).stops, chart.stops)
        XCTAssertTrue(SpacingChart(curve: .linear, frames: 2).draggable.isEmpty)
    }

    /// The dots sit on the guide, at the arc fraction each frame reaches — which is the same
    /// parameter the trajectory constraint is read on, so the chart shows where the motion actually
    /// is rather than a separate diagram of it.
    func testTheDotsSitOnTheGuideWhereEachFrameLands() throws {
        let p = try path(straight())
        let positions = SpacingChart(curve: .linear, frames: 5).positions(on: p)
        XCTAssertEqual(positions.map(\.x), [0, 25, 50, 75, 100])
    }

    // MARK: - The chart through the document

    /// The chart's stop count is the **timeline's** in-between frames, not a fixed number — that is
    /// what "each in-between frame" means to the artist. `generated` puts its
    /// keyframes at frames 0 and 8, so the chart is nine stops: two pinned keyframes and seven
    /// in-betweens to place.
    func testTheChartSpansTheKeyframesOwnFrames() throws {
        let manager = guidedFrame()
        let guide0 = try soleGuide(manager)
        let chart = try XCTUnwrap(manager.spacingChart(forGuide: guide0.id))
        XCTAssertEqual(chart.stops.count, 9)
        XCTAssertEqual(Array(chart.draggable), [1, 2, 3, 4, 5, 6, 7])
    }

    /// A guide's own stylus timing is what the chart starts from — the chart is a view of the easing
    /// in force, not a second store of it.
    func testTheChartStartsFromTheGuidesOwnTiming() throws {
        let manager = manager()
        generated(manager)
        manager.currentFrame = 4
        manager.currentLayerIndex = 1
        // Fast then slow: most of the arc is covered early, which is ease-out.
        manager.recordGuideStroke(samples: [
            TimedSample(point: CGPoint(x: 0, y: 0), pressure: 1, time: 0),
            TimedSample(point: CGPoint(x: 80, y: 0), pressure: 1, time: 0.02),
            TimedSample(point: CGPoint(x: 100, y: 0), pressure: 1, time: 0.2),
        ])
        let chart = try XCTUnwrap(manager.spacingChart(forGuide: try soleGuide(manager).id))
        XCTAssertGreaterThan(chart.stops[2], 0.5, "an ease-out chart is past halfway at the midpoint")
    }

    /// **The precedence item 5 depends on**: a dot the artist placed by hand outranks the velocity
    /// they happened to draw the arc at, because it is written to `binding.spacing`. Without that,
    /// the guide's derived timing would overwrite every retime on the next evaluation.
    func testADotDragOutranksTheGuidesDerivedTiming() throws {
        let manager = guidedFrame()
        let guide0 = try soleGuide(manager)

        manager.beginGuideSpacingDrag(guideID: guide0.id)
        manager.dragGuideSpacingStop(index: 4, to: 0.6)   // the middle frame, halfway through in time
        manager.commitGuideSpacingDrag()

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        let written = try XCTUnwrap(recipe.groups.first?.spacing ?? recipe.spacing)
        XCTAssertEqual(written.eased(0.5), 0.6, accuracy: 1e-6)
        XCTAssertEqual(manager.spacingChart(forGuide: guide0.id)?.stops[4] ?? 0, 0.6, accuracy: 1e-6)
    }

    /// Retiming a frame moves the drawing at that `t`, which is the whole point — and it moves it
    /// *along the guide*, since the trajectory is read at the eased parameter.
    func testRetimingAFrameMovesTheInBetween() throws {
        let manager = guidedFrame()
        let guide0 = try soleGuide(manager)
        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        let before = try forwardPoints(manager, at: 0.5, guides: manager.guides(driving: recipe))

        manager.beginGuideSpacingDrag(guideID: guide0.id)
        manager.dragGuideSpacingStop(index: 4, to: 0.6)
        manager.commitGuideSpacingDrag()

        let after = try forwardPoints(manager, at: 0.5,
                                      guides: manager.guides(driving: try XCTUnwrap(
                                        manager.layers[1].cels[1].interpolation)))
        XCTAssertNotEqual(before.map(\.x), after.map(\.x),
                          "the frame should now sit 60% of the way along the motion")
    }

    /// One gesture, one undo step — the same bracket as the handles and the `t` slider.
    func testAWholeSpacingDragIsOneUndoStep() throws {
        let manager = guidedFrame()
        let guide0 = try soleGuide(manager)
        let before = try XCTUnwrap(manager.layers[1].cels[1].interpolation).groups.first?.spacing

        manager.beginGuideSpacingDrag(guideID: guide0.id)
        for v in stride(from: CGFloat(0.45), through: 0.6, by: 0.05) {
            manager.dragGuideSpacingStop(index: 4, to: v)
        }
        manager.commitGuideSpacingDrag()
        XCTAssertNotEqual(manager.layers[1].cels[1].interpolation?.groups.first?.spacing, before)

        manager.undo()
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.groups.first?.spacing, before)
        XCTAssertEqual(manager.guideStrokes.count, 1, "one undo is the drag, not the guide")
    }

    /// A drag is a pure function of the chart at touch-down. Reading the chart back mid-drag would
    /// read the curve the drag itself just wrote, and each move would compound the last.
    func testMovesWithinOneSpacingDragDoNotCompound() throws {
        let manager = guidedFrame()
        let guide0 = try soleGuide(manager)

        manager.beginGuideSpacingDrag(guideID: guide0.id)
        manager.dragGuideSpacingStop(index: 4, to: 0.45)
        manager.dragGuideSpacingStop(index: 4, to: 0.6)
        manager.dragGuideSpacingStop(index: 4, to: 0.55)
        manager.commitGuideSpacingDrag()

        XCTAssertEqual(manager.spacingChart(forGuide: guide0.id)?.stops[4] ?? 0, 0.55, accuracy: 1e-6)
    }

    /// A tap on a dot is not a retime, and a second finger mid-drag puts the easing back.
    func testASpacingDragThatMovedNothingOrWasCancelledRecordsNoStep() throws {
        let manager = guidedFrame()
        let guide0 = try soleGuide(manager)

        manager.beginGuideSpacingDrag(guideID: guide0.id)
        manager.commitGuideSpacingDrag()

        manager.beginGuideSpacingDrag(guideID: guide0.id)
        manager.dragGuideSpacingStop(index: 4, to: 0.6)
        manager.cancelGuideSpacingDrag()
        XCTAssertNil(manager.layers[1].cels[1].interpolation?.groups.first?.spacing)

        manager.undo()
        XCTAssertTrue(manager.guideStrokes.isEmpty, "the only step should be the guide's creation")
    }

    /// The smallest chart that means anything: keyframes two frames apart, one in-between to place.
    func testTheSmallestChartHasOneDraggableFrame() throws {
        let manager = manager()
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cels = (0..<3).map { i in
            Cel(id: UUID(), startFrame: i, frameCount: 1, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        manager.layers[1].cels = cels
        cels[0].vector?.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 20)]))
        cels[2].vector?.addStroke(stroke([CGPoint(x: 34, y: 20), CGPoint(x: 54, y: 20)]))
        manager.enterInterpolateMode()
        for cel in [cels[0], cels[2]] {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: manager.layers[1].id)
        }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))
        manager.currentFrame = 1
        manager.currentLayerIndex = 1
        manager.recordGuideStroke(samples: dense())

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(manager.interpolationFrameSpan(of: recipe), 3)
        let chart = try XCTUnwrap(manager.spacingChart(forGuide: try soleGuide(manager).id))
        XCTAssertEqual(Array(chart.draggable), [1])
    }

    /// No span, no chart. A recipe whose references collapse to one keyframe has no motion to lay
    /// frames along, and drawing an empty overlay for it would be a control that does nothing.
    func testAChartNeedsRoomForAnInBetween() throws {
        let manager = guidedFrame()
        let guideID = try soleGuide(manager).id
        XCTAssertNotNil(manager.spacingChart(forGuide: guideID))

        let references = try XCTUnwrap(manager.layers[1].cels[1].interpolation).references
        manager.layers[1].cels[1].interpolation?.references = Array(references.prefix(1))
        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertNil(manager.interpolationFrameSpan(of: recipe))
        XCTAssertNil(manager.spacingChart(forGuide: guideID))
    }

    /// Leaving the mode puts the overlay back on the shape editor, which is where an artist who has
    /// never pressed the button expects to be.
    func testLeavingTheModeResetsTheSpacingEditor() {
        let manager = manager()
        manager.enterInterpolateMode()
        manager.isEditingGuideSpacing = true
        manager.exitInterpolateMode()
        XCTAssertFalse(manager.isEditingGuideSpacing)
    }

    /// The loop item 2 exists to close: pull a handle, and the in-between moves. The handle positions
    /// the overlay draws come from the same place the drag writes to, so what is grabbed is what is
    /// seen.
    func testDraggingAHandleBendsTheInBetween() throws {
        let manager = guidedFrame()
        let guide0 = try soleGuide(manager)
        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        let flat = try forwardPoints(manager, at: 0.5, guides: manager.guides(driving: recipe))

        let handles = manager.guideHandlePositions(for: guide0)
        XCTAssertEqual(handles.count, GuideHandles.count)
        let middle = handles[2]
        XCTAssertEqual(middle.position, guide0.samples[middle.sampleIndex].point)

        manager.beginGuideHandleDrag(guideID: guide0.id)
        manager.dragGuideHandle(sampleIndex: middle.sampleIndex,
                                to: CGPoint(x: middle.position.x, y: middle.position.y + 40))
        manager.commitGuideHandleDrag()

        let bent = try forwardPoints(manager, at: 0.5, guides: manager.guides(driving: recipe))
        for (a, b) in zip(flat, bent) {
            XCTAssertEqual(b.y - a.y, 40, accuracy: 1e-4)
            XCTAssertEqual(b.x, a.x, accuracy: 1e-4)
        }
    }
}
