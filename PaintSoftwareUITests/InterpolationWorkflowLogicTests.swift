import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for the interpolate-mode *workflow* — Phase 4 of
/// VECTOR_INTERPOLATION_IMPLEMENTATION.md.
///
/// The division of labour with `InterpolationRenderLogicTests` is deliberate: that file owns "does a
/// recipe produce the right pixels", this one owns "does the app build the right recipe, and let go
/// of it correctly". Everything here runs against a `CanvasManager` with no view and no simulator
/// gestures; the single XCUITest that drives the real gesture path lives in `TimelineAndUndoUITests`.
///
/// What is being pinned, in descending order of how expensive it is to discover later:
///
/// 1. **Mode entry never damages document content.** Entering and leaving interpolate mode is a
///    transient selection. A recipe already attached to a cel must survive it, or an artist loses
///    work by tapping the wrong button twice.
/// 2. **Generate attaches a recipe rather than baking a drawing.** An in-between is derived, never
///    stored (`PLAN.md` §4). A test that only checked "the cel now looks right" would pass just as
///    happily for the baked implementation that makes note 1 impossible.
/// 3. **Undo is one step.** Both for Generate and for a whole slider drag.
final class InterpolationWorkflowLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let brush = BrushLibrary.hardRound

    /// A manager with one raster layer (index 0, from `CanvasFixture`) and two vector layers at
    /// indices 1 and 2, each with a single cel spanning the scene.
    private func manager(vectorLayers: Int = 1) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        for _ in 0..<vectorLayers { manager.addVectorLayer() }
        return manager
    }

    private func stroke(_ points: [CGPoint], id: UUID = UUID()) -> VectorStroke {
        VectorStroke(id: id, brush: Self.brush,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) })
    }

    /// Splits a layer into three cels and draws a short bar into the first and the last, leaving the
    /// middle one empty — the shape the whole workflow is about.
    ///
    /// Assigns `cels` directly rather than calling `addCel`: `CanvasFixture.manager` gives each layer
    /// one cel spanning the whole scene, so every `addCel` inside it collides and returns false
    /// (`HANDOFF.md` §5).
    @discardableResult
    private func threeCels(_ manager: CanvasManager, layerIndex: Int,
                           aOffset: CGFloat = 0, cOffset: CGFloat = 24) -> [Cel] {
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        let cels = (0..<3).map { i in
            Cel(id: UUID(), startFrame: i * 4, frameCount: 4, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        manager.layers[layerIndex].cels = cels
        cels[0].vector?.addStroke(stroke([CGPoint(x: 10 + aOffset, y: 20),
                                          CGPoint(x: 30 + aOffset, y: 20),
                                          CGPoint(x: 30 + aOffset, y: 40)]))
        cels[2].vector?.addStroke(stroke([CGPoint(x: 10 + cOffset, y: 20),
                                          CGPoint(x: 30 + cOffset, y: 20),
                                          CGPoint(x: 30 + cOffset, y: 40)]))
        return cels
    }

    private func setReferences(_ manager: CanvasManager, layerIndex: Int, cels: [Cel]) {
        for cel in cels {
            manager.toggleInterpolationReference(celID: cel.id,
                                                 inLayer: manager.layers[layerIndex].id)
        }
    }

    // MARK: - Mode state

    func testEnteringInterpolateModeStartsWithNoReferences() {
        let manager = manager()
        manager.interpolationReferences = [CelRef(layerID: UUID(), celID: UUID())]
        manager.enterInterpolateMode()
        XCTAssertTrue(manager.isInterpolateMode)
        XCTAssertTrue(manager.interpolationReferences.isEmpty,
                      "Entering the mode starts a fresh selection rather than inheriting a stale one")
    }

    /// The property that makes the mode safe to leave: recipes are document content, the reference
    /// selection is not. An artist who taps the mode button off and on again must not find their
    /// in-betweens gone.
    func testLeavingInterpolateModeClearsTheSelectionButKeepsEveryRecipe() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))
        XCTAssertNotNil(manager.layers[1].cels[1].interpolation, "Setup: the recipe attached")

        manager.exitInterpolateMode()

        XCTAssertFalse(manager.isInterpolateMode)
        XCTAssertTrue(manager.interpolationReferences.isEmpty)
        XCTAssertNotNil(manager.layers[1].cels[1].interpolation,
                        "Leaving the mode is not an edit — the recipe stays")
    }

    func testTogglingAReferenceTwiceRemovesIt() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        let layerID = manager.layers[1].id
        manager.toggleInterpolationReference(celID: cels[0].id, inLayer: layerID)
        XCTAssertTrue(manager.isInterpolationReference(celID: cels[0].id, inLayer: layerID))
        manager.toggleInterpolationReference(celID: cels[0].id, inLayer: layerID)
        XCTAssertFalse(manager.isInterpolationReference(celID: cels[0].id, inLayer: layerID))
        XCTAssertTrue(manager.interpolationReferences.isEmpty)
    }

    /// Requirement 5: lineart and flats are one keyframe, not two, so they warp through one lattice
    /// instead of drifting apart. Grouping is by start frame.
    func testCelsOnDifferentLayersStartingOnTheSameFrameAreOneKeyframe() {
        let manager = manager(vectorLayers: 2)
        let lineart = threeCels(manager, layerIndex: 1)
        let flats = threeCels(manager, layerIndex: 2)
        setReferences(manager, layerIndex: 1, cels: [lineart[0], lineart[2]])
        setReferences(manager, layerIndex: 2, cels: [flats[0], flats[2]])

        let keyframes = manager.interpolationKeyframes
        XCTAssertEqual(keyframes.count, 2, "Four flagged cels on two layers are two keyframes")
        XCTAssertEqual(keyframes.map(\.cels.count), [2, 2])
    }

    func testKeyframesComeOutInTimeOrderWhicheverOrderTheyWereFlagged() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        setReferences(manager, layerIndex: 1, cels: [cels[2], cels[0]])
        let keyframes = manager.interpolationKeyframes
        XCTAssertEqual(keyframes.count, 2)
        XCTAssertEqual(keyframes.first?.cels.first?.celID, cels[0].id,
                       "The earlier cel is the first reference even though it was flagged second")
    }

    // MARK: - Creating a recipe

    /// The load-bearing assertion of the phase. Generate must attach a recipe and leave the cel's own
    /// display list alone: if it baked the frame instead, editing keyframe A could never update the
    /// in-between (`PLAN.md` §4's "why derived and not generate-once").
    func testGenerateAttachesARecipeAndWritesNoContentIntoTheCel() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])

        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(recipe.mode, .generate)
        XCTAssertEqual(recipe.references.count, 2)
        XCTAssertTrue(recipe.isWellFormed, "One binding, one lattice per reference")
        XCTAssertTrue(manager.layers[1].cels[1].vector?.elements.isEmpty ?? false,
                      "The in-between is derived, never stored — the cel's own display list stays empty")
    }

    /// Phase 4 creates exactly one automatic whole-layer group, and nothing needs tagging for the
    /// warp to reach every stroke: untagged content rides the recipe's first binding
    /// (`HANDOFF.md` §5.9).
    func testGenerateCreatesOneWholeFrameBindingAndTagsNothing() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1)

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(recipe.groups.count, 1)
        XCTAssertEqual(recipe.groups[0].lattices.count, 2)
        XCTAssertTrue(manager.motionGroups.isEmpty,
                      "No artist-facing MotionGroup is invented for the implicit whole-frame group")
        XCTAssertTrue(cels[0].vector?.strokes.allSatisfy { $0.motionGroupID == nil } ?? false,
                      "Phase 4 tags nothing; Phase 5 is where tagging starts")
    }

    /// Registration is what makes the second lattice mean anything. A fit that returned the rest
    /// configuration would leave `t = 0` and `t = 1` identical, and every render test downstream
    /// would still pass.
    func testRegistrationMovesTheSecondLatticeTowardTheSecondKeyframe() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1, cOffset: 24)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1)

        let binding = try XCTUnwrap(manager.layers[1].cels[1].interpolation?.groups.first)
        let rest = binding.lattices[0], fitted = binding.lattices[1]
        XCTAssertTrue(fitted.sharesTopology(with: rest),
                      "Both configurations must share topology or the interpolator cannot be built")
        let shift = zip(rest.vertices, fitted.vertices).map { $1.x - $0.x }
        let mean = shift.reduce(0, +) / CGFloat(max(shift.count, 1))
        XCTAssertGreaterThan(mean, 8,
                             "The drawing moved +24 in x; the fitted lattice should follow it, not sit still")
    }

    func testAnEmptyReferenceStillProducesAnEvaluableRecipe() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        cels[2].vector?.elements = []
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])

        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))
        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertTrue(recipe.isWellFormed,
                      "One keyframe with nothing in it is a fade, not a malformed recipe")
    }

    // MARK: - Refusals

    func testInterpolateRefusesWithFewerThanTwoKeyframes() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0]])
        XCTAssertEqual(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1),
                       .notEnoughReferences)
        XCTAssertNil(manager.layers[1].cels[1].interpolation)
    }

    /// Deriving a cel from itself is a cycle, and the evaluator would read its own output as input.
    func testInterpolateRefusesWhenTheTargetIsItselfAReference() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertEqual(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 0),
                       .targetIsAReference)
    }

    func testInterpolateRefusesOnARasterLayer() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertEqual(manager.interpolate(mode: .generate, layerIndex: 0, celIndex: 0),
                       .notAVectorLayer)
    }

    /// Reproject is built now (Phase 6 item 1), but it still refuses out loud rather than quietly
    /// behaving like Generate — `PLAN.md` §10 decision 3 says the two are never conflated, and the
    /// way they would get conflated is Reproject inventing content when the cel has none.
    ///
    /// The empty in-between is precisely the frame Generate is for.
    func testReprojectRefusesRatherThanBehavingLikeGenerate() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertEqual(manager.interpolate(mode: .reproject, layerIndex: 1, celIndex: 1),
                       .nothingToReproject)
        XCTAssertNil(manager.layers[1].cels[1].interpolation)
    }

    // MARK: - Reproject (Phase 6 item 1)

    /// A distinctly-shaped drawing of the artist's own in the middle cel. Deliberately *not* the same
    /// shape as either keyframe, so "the linework was preserved" is a claim the geometry can settle:
    /// nothing derived from A or C could produce these samples.
    @discardableResult
    private func drawSubject(into cel: Cel, at x: CGFloat = 60) -> VectorStroke {
        let s = stroke([CGPoint(x: x, y: 100), CGPoint(x: x + 18, y: 132),
                        CGPoint(x: x - 6, y: 150), CGPoint(x: x + 24, y: 168)])
        cel.vector?.addStroke(s)
        return s
    }

    private func reprojected(_ manager: CanvasManager, cels: [Cel]) -> InterpolationRecipe? {
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertNil(manager.interpolate(mode: .reproject, layerIndex: 1, celIndex: 1))
        return manager.layers[1].cels[1].interpolation
    }

    /// The whole point of Reproject: the drawing is the artist's, and only its *pose* moves
    /// (`PLAN.md` §5.5). So the recipe records `.reproject`, and the cel keeps its own strokes —
    /// unlike Generate, whose in-between is derived and never stored.
    func testReprojectKeepsTheCelsOwnDrawingAndRecordsTheMode() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        let subject = drawSubject(into: cels[1])

        let recipe = try XCTUnwrap(reprojected(manager, cels: cels))

        XCTAssertEqual(recipe.mode, .reproject)
        XCTAssertTrue(recipe.isWellFormed)
        XCTAssertEqual(recipe.groups.count, 1, "one drawing, one pose, one binding")
        XCTAssertEqual(recipe.groups[0].lattices.count, 2, "one fit per reference")
        let kept = manager.layers[1].cels[1].vector?.elements.compactMap(\.stroke) ?? []
        XCTAssertEqual(kept.map(\.id), [subject.id],
                       "the artist's linework is never replaced — only reposed")
    }

    /// The evaluation is one set at full strength, not a cross-fade. Nothing is being derived from
    /// two keyframes, so there is no second set and nothing to blend against.
    func testAReprojectedFrameIsOneSetAtFullStrengthRatherThanACrossFade() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        drawSubject(into: cels[1])
        let recipe = try XCTUnwrap(reprojected(manager, cels: cels))

        let half = try XCTUnwrap(InterpolationEvaluator.evaluate(
            recipe: recipe, at: 0.5, content: manager.interpolationContentProvider,
            subject: manager.layers[1].cels[1].vector?.elements ?? []))

        XCTAssertEqual(half.forwardWeight, 1)
        XCTAssertEqual(half.backwardWeight, 0)
        XCTAssertTrue(half.backward.isEmpty, "a reprojection has no second set")
        XCTAssertEqual(half.forward.compactMap(\.stroke).count, 1)
    }

    /// The claim the mechanism has to earn: sliding `t` **moves** the drawing, and it moves it the
    /// way the keyframes move. A's bar sits at x = 10…30 and C's at 34…54, so the motion is +24 in
    /// x; the subject is drawn elsewhere entirely and must ride that same motion rather than sit
    /// still or jump onto a keyframe's position.
    func testSlidingTMovesTheReprojectedDrawingAlongTheKeyframeMotion() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        drawSubject(into: cels[1])
        let recipe = try XCTUnwrap(reprojected(manager, cels: cels))
        let subject = manager.layers[1].cels[1].vector?.elements ?? []

        func meanX(at t: CGFloat) throws -> CGFloat {
            let e = try XCTUnwrap(InterpolationEvaluator.evaluate(
                recipe: recipe, at: t, content: manager.interpolationContentProvider,
                subject: subject))
            let xs = e.forward.compactMap(\.stroke).flatMap { $0.samples.map(\.x) }
            return xs.reduce(0, +) / CGFloat(max(1, xs.count))
        }
        let atZero = try meanX(at: 0), atOne = try meanX(at: 1), atHalf = try meanX(at: 0.5)

        XCTAssertGreaterThan(atOne, atZero + 8, "the pose slides with the keyframes' motion")
        XCTAssertEqual(atHalf, (atZero + atOne) / 2, accuracy: 6, "and it slides through the middle")
    }

    /// Reproject does **not** inherit Generate's already-interpolated refusal, and this is the
    /// decision Phase 4 left open rather than a gap: re-running it re-registers the same linework
    /// against whatever the references are now, and replaces nothing.
    func testReprojectCanBeRunAgainToPickUpChangedReferences() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        let subject = drawSubject(into: cels[1])
        XCTAssertNotNil(reprojected(manager, cels: cels))

        XCTAssertNil(manager.interpolate(mode: .reproject, layerIndex: 1, celIndex: 1),
                     "a second Reproject is how the artist picks up moved keyframes")
        XCTAssertEqual(manager.layers[1].cels[1].vector?.elements.compactMap(\.stroke).map(\.id),
                       [subject.id], "and it still has not touched the linework")
    }

    /// A cel carrying a `.generate` recipe holds no strokes of its own — an in-between is derived,
    /// never stored (`PLAN.md` §4) — so Reproject has nothing to repose and says so. Commit is what
    /// turns a generated frame into one Reproject can work on, which is how §5.5 says the two
    /// commands compose.
    func testReprojectOnAGeneratedFrameRefusesBecauseThereIsNoLineworkYet() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))

        XCTAssertEqual(manager.interpolate(mode: .reproject, layerIndex: 1, celIndex: 1),
                       .nothingToReproject)
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.mode, .generate,
                       "and the refusal left the generated recipe alone")
    }

    /// Undo of a Reproject puts the frame back the way it was — and the bracket it uses is the
    /// structural one, because unlike Generate it writes no tag onto any keyframe's strokes.
    func testReprojectIsUndoable() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        drawSubject(into: cels[1])
        XCTAssertNotNil(reprojected(manager, cels: cels))

        manager.undo()

        XCTAssertNil(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(manager.layers[1].cels[1].vector?.elements.compactMap(\.stroke).count, 1,
                       "undoing the reprojection must not take the drawing with it")
    }

    // MARK: - Editing at an in-between (Phase 6 items 2 and 3)

    /// A Generate on the middle cel, with the manager left in interpolate mode and `t` where the
    /// caller wants it.
    @discardableResult
    private func generated(_ manager: CanvasManager, cels: [Cel], t: CGFloat = 0.5) -> [Cel] {
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))
        manager.layers[1].cels[1].interpolation?.t = t
        return manager.layers[1].cels
    }

    /// A stroke as the canvas view hands one over — canvas-space samples, straight off the touch.
    private func drawn(_ points: [CGPoint], erasing: Bool = false) -> VectorStroke {
        var s = stroke(points)
        if erasing { s.composite = .erase }
        return s
    }

    /// Where a recipe's local edits actually land on screen at `t`.
    private func editSamples(_ manager: CanvasManager, at t: CGFloat) throws -> [CGPoint] {
        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        let e = try XCTUnwrap(InterpolationEvaluator.evaluate(
            recipe: recipe, at: t, content: manager.interpolationContentProvider))
        return e.localEdits.compactMap(\.stroke).flatMap { $0.samples.map(\.point) }
    }

    /// **The test `IMPLEMENTATION.md` Phase 6 names by hand**, and the one the inverse map exists to
    /// pass: draw at `t`, then move the slider, and the stroke has to **follow the motion** rather
    /// than sit still.
    ///
    /// A's bar sits at x = 10…30 and C's at 34…54, so the drawing travels +24 in x across the span.
    /// The edit is drawn at `t = 0.5` and must therefore be somewhere near the middle at 0.5, back
    /// near A's pose at 0, and near C's at 1 — moving in the same direction and by a comparable
    /// amount, which is exactly what "stored in keyframe space and re-warped" buys and what storing
    /// it at the in-between could not.
    func testAStrokeDrawnAtAnInBetweenFollowsTheMotionWhenTheSliderMoves() throws {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1))

        XCTAssertTrue(manager.recordLocalEdit(
            canvasSpaceStroke: drawn([CGPoint(x: 20, y: 28), CGPoint(x: 26, y: 32)]),
            forCel: cels[1].id, inLayer: manager.layers[1].id))

        func meanX(at t: CGFloat) throws -> CGFloat {
            let xs = try editSamples(manager, at: t).map(\.x)
            XCTAssertFalse(xs.isEmpty, "the edit must be visible at t = \(t)")
            return xs.reduce(0, +) / CGFloat(xs.count)
        }
        // Read at 0.5 and 1 only: τ = 0.5 hides the edit below the frame it was drawn at, which is
        // the next test's subject.
        let atHalf = try meanX(at: 0.5), atOne = try meanX(at: 1)
        XCTAssertGreaterThan(atOne, atHalf + 4,
                             "the edit rides the drawing's motion instead of sitting still")
    }

    /// τ = `t` (`PLAN.md` §5.4 step 4). The edit belongs to the pose it was made at, so it does not
    /// exist before it — and the comparison is one-sided, so it stays put from there on.
    func testAnEditAtAnInBetweenDoesNotExistBeforeTheFrameItWasDrawnAt() throws {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1), t: 0.6)

        XCTAssertTrue(manager.recordLocalEdit(
            canvasSpaceStroke: drawn([CGPoint(x: 20, y: 28), CGPoint(x: 26, y: 32)]),
            forCel: cels[1].id, inLayer: manager.layers[1].id))

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(recipe.localEdits.first?.stroke.visibilityThreshold, 0.6)
        XCTAssertTrue(try editSamples(manager, at: 0.4).isEmpty)
        XCTAssertFalse(try editSamples(manager, at: 0.6).isEmpty)
        XCTAssertFalse(try editSamples(manager, at: 1).isEmpty)
    }

    /// The inverse map is an inverse, not an approximation: what gets stored, re-warped at the `t`
    /// it was drawn at, comes back where the artist put it. This is the property every other claim
    /// in this section rests on, and it is the one that would fail silently — a stroke a few points
    /// off looks like a shaky hand.
    func testTheStoredEditWarpsBackToExactlyWhereItWasDrawn() throws {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1), t: 0.5)
        let points = [CGPoint(x: 18, y: 26), CGPoint(x: 24, y: 30), CGPoint(x: 28, y: 36)]

        XCTAssertTrue(manager.recordLocalEdit(canvasSpaceStroke: drawn(points),
                                              forCel: cels[1].id, inLayer: manager.layers[1].id))

        let back = try editSamples(manager, at: 0.5)
        XCTAssertEqual(back.count, points.count)
        for (drawn, evaluated) in zip(points, back) {
            XCTAssertEqual(evaluated.x, drawn.x, accuracy: 0.01)
            XCTAssertEqual(evaluated.y, drawn.y, accuracy: 0.01)
        }
    }

    /// The edit goes into the **recipe**, never into the cel's display list. An in-between is
    /// derived and never stored (`PLAN.md` §4); an edit that landed in `cel.vector` would both
    /// persist a frame meant to be recomputed and be invisible, since the view shows the evaluation
    /// rather than the canvas.
    func testAnEditAtAnInBetweenIsStoredOnTheRecipeAndNotInTheCel() throws {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1))

        XCTAssertTrue(manager.recordLocalEdit(
            canvasSpaceStroke: drawn([CGPoint(x: 20, y: 28), CGPoint(x: 26, y: 32)]),
            forCel: cels[1].id, inLayer: manager.layers[1].id))

        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.localEdits.count, 1)
        XCTAssertTrue(manager.layers[1].cels[1].vector?.elements.isEmpty ?? false,
                      "the in-between stays derived")
    }

    /// The edit is bound to the group whose lattice carries it, so a later re-registration that
    /// gives that group a different motion takes the edit with it. With one whole-frame binding
    /// there is exactly one answer, and "nil, ride the first binding" would be indistinguishable
    /// from it on screen — so the assertion is on the id itself.
    func testAnEditRecordsTheGroupWhoseLatticeCarriesIt() throws {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1))

        XCTAssertTrue(manager.recordLocalEdit(
            canvasSpaceStroke: drawn([CGPoint(x: 20, y: 28), CGPoint(x: 26, y: 32)]),
            forCel: cels[1].id, inLayer: manager.layers[1].id))

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(recipe.localEdits.first?.groupID, recipe.groups.first?.groupID)
        XCTAssertNil(recipe.localEdits.first?.stroke.motionGroupID,
                     "membership is recorded on the edit, not duplicated onto its stroke")
    }

    /// A stroke drawn well outside the group's lattice grows it by whole rings rather than being
    /// clamped onto the boundary — `PLAN.md` §5.4 step 2. The tell that clamping is *not* what
    /// happened is that the edit still evaluates back to where it was drawn: a clamped embedding
    /// folds every outside point onto the same edge and the stroke collapses.
    func testAStrokeDrawnOutsideTheLatticeGrowsItRatherThanBeingClamped() throws {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1))
        let before = try XCTUnwrap(manager.layers[1].cels[1].interpolation).groups[0].lattices[0]
        let far = [CGPoint(x: 150, y: 160), CGPoint(x: 162, y: 172)]

        XCTAssertTrue(manager.recordLocalEdit(canvasSpaceStroke: drawn(far),
                                              forCel: cels[1].id, inLayer: manager.layers[1].id))

        let after = try XCTUnwrap(manager.layers[1].cels[1].interpolation).groups[0]
        XCTAssertGreaterThan(after.lattices[0].cols, before.cols, "the lattice grew to hold it")
        XCTAssertEqual(after.lattices[0].cols, after.lattices[1].cols,
                       "and both keyframes' lattices grew together, or the topologies mismatch")
        let back = try editSamples(manager, at: 0.5)
        XCTAssertEqual(back.count, far.count)
        for (drawn, evaluated) in zip(far, back) {
            XCTAssertEqual(evaluated.x, drawn.x, accuracy: 0.5)
            XCTAssertEqual(evaluated.y, drawn.y, accuracy: 0.5)
        }
    }

    /// **Item 3's engine half: erasing at an in-between needs no eraser-specific code.** An eraser
    /// *is* a stroke (`VECTOR_ERASER_PLAN.md` §2.1), so it rides `localEdits` like any other — and
    /// `composite(_:size:quality:)` already draws local edits over the *blended* result, which is
    /// what lets it reach both keyframes' ink rather than only one set's.
    func testErasingAtAnInBetweenRecordsAnEraserStrokeLikeAnyOtherEdit() throws {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1))

        XCTAssertTrue(manager.recordLocalEdit(
            canvasSpaceStroke: drawn([CGPoint(x: 20, y: 28), CGPoint(x: 26, y: 32)], erasing: true),
            forCel: cels[1].id, inLayer: manager.layers[1].id))

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(recipe.localEdits.count, 1)
        XCTAssertEqual(recipe.localEdits.first?.stroke.composite, .erase)
        XCTAssertEqual(recipe.localEdits.first?.stroke.visibilityThreshold, 0.5,
                       "and it fades in at its own frame exactly like a paint stroke")
    }

    /// One artist action, one undo step — including the lattice growth, which is part of the same
    /// edit and would otherwise be left behind enlarging the recipe for no reason.
    func testAnEditAtAnInBetweenIsOneUndoStep() throws {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1))
        let before = try XCTUnwrap(manager.layers[1].cels[1].interpolation).groups[0].lattices[0].cols
        XCTAssertTrue(manager.recordLocalEdit(
            canvasSpaceStroke: drawn([CGPoint(x: 150, y: 160), CGPoint(x: 162, y: 172)]),
            forCel: cels[1].id, inLayer: manager.layers[1].id))

        manager.undo()

        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertTrue(recipe.localEdits.isEmpty)
        XCTAssertEqual(recipe.groups[0].lattices[0].cols, before,
                       "the growth undoes with the stroke that caused it")
    }

    /// A cel with no recipe is not an in-between, and the routing has to say so — otherwise an
    /// ordinary drawing would have its strokes diverted into a recipe that does not exist.
    func testACelWithNoRecipeIsNotEditableAsAnInBetween() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.currentFrame = cels[1].startFrame
        XCTAssertNil(manager.inBetweenCelID(inLayer: manager.layers[1].id))

        XCTAssertFalse(manager.recordLocalEdit(
            canvasSpaceStroke: drawn([CGPoint(x: 20, y: 28)]),
            forCel: cels[1].id, inLayer: manager.layers[1].id))
    }

    /// And the positive half of the same routing question, which is what the canvas view actually
    /// asks: the layer is showing an interpolated cel at the playhead.
    func testAnInterpolatedCelUnderThePlayheadIsEditableAsAnInBetween() {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1))
        manager.currentFrame = cels[1].startFrame
        XCTAssertEqual(manager.inBetweenCelID(inLayer: manager.layers[1].id), cels[1].id)
    }

    /// **The transform half of item 3 is a refusal, not a routing** (`HANDOFF.md` §5.13). Vector
    /// Move is a whole-content transform written onto the cel's own `VectorCanvas`, and an
    /// in-between's canvas is not where its pixels come from — so on one the handle box would drag
    /// a drawing that never moved. `activeCelIsInBetween` is what the three call sites check.
    func testTheWholeContentVectorTransformIsUnavailableOnAnInBetween() {
        let manager = manager()
        let cels = generated(manager, cels: threeCels(manager, layerIndex: 1))
        manager.currentLayerIndex = 1

        manager.currentFrame = cels[0].startFrame
        XCTAssertFalse(manager.activeCelIsInBetween, "a keyframe transforms as it always did")

        manager.currentFrame = cels[1].startFrame
        XCTAssertTrue(manager.activeCelIsInBetween)
    }

    /// Pressing Generate twice used to interpolate twice, replacing the first recipe — so a double
    /// tap silently threw away whatever `t` had been scrubbed to. Product owner, 2026-08-01.
    func testGenerateRefusesOnACelThatIsAlreadyInterpolated() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1))
        // A `t` a fresh recipe would never have — Generate always starts at 0.5, so this is what
        // says the second attempt left the *first* recipe in place rather than replacing it.
        manager.setInterpolationT(0.25, forCel: cels[1].id, inLayer: manager.layers[1].id)

        XCTAssertEqual(manager.interpolationRefusal(mode: .generate, layerIndex: 1, celIndex: 1),
                       .alreadyInterpolated,
                       "The button is disabled from this call, so the refusal is what greys it out")
        XCTAssertEqual(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1),
                       .alreadyInterpolated)
        let recipe = try XCTUnwrap(manager.layers[1].cels[1].interpolation)
        XCTAssertEqual(recipe.t, 0.25, accuracy: 0.001,
                       "The second Generate must leave the scrubbed timing alone")
    }

    /// Removing the recipe is how you start over — the refusal has to lift again afterwards, or
    /// Remove Interpolation would be a one-way door.
    func testRemovingTheInterpolationMakesGenerateAvailableAgain() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1)
        manager.removeInterpolation(layerIndex: 1, celIndex: 1)

        XCTAssertNil(manager.interpolationRefusal(mode: .generate, layerIndex: 1, celIndex: 1))
    }

    // MARK: - Generating from the playhead

    /// A slot with no block in it, between two references, is the ordinary way to ask for an
    /// in-between. Generate makes the block rather than refusing (product owner, 2026-08-01) —
    /// otherwise the artist has to know to add a drawing from the slot's own menu first.
    func testGenerateAtThePlayheadCreatesTheBlockWhenTheSlotIsEmpty() throws {
        let manager = manager(vectorLayers: 2)
        let cels = threeCels(manager, layerIndex: 1)
        emptyAfterFirstBlock(manager, layerIndex: 2)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])

        manager.currentLayerIndex = 2
        manager.goToFrame(6)
        XCTAssertNil(manager.interpolationTarget, "Setup: the playhead is over an empty slot")
        XCTAssertNil(manager.interpolationRefusalAtPlayhead(mode: .generate),
                     "A missing block is not a refusal — Generate makes one")

        XCTAssertNil(manager.interpolateAtPlayhead(mode: .generate))

        let at = try XCTUnwrap(manager.interpolationTarget, "A block should now exist under the playhead")
        XCTAssertEqual(at.layer, 2)
        let cel = manager.layers[2].cels[at.cel]
        XCTAssertEqual(cel.startFrame, 6)
        XCTAssertNotNil(cel.interpolation, "The new block carries the recipe")
        XCTAssertNotNil(cel.vector, "A block created on a vector layer needs its own canvas")
    }

    /// One action, one undo step — the block and the recipe arrived together, so they leave together.
    func testCreatingTheBlockAndItsRecipeIsOneUndoStep() {
        let manager = manager(vectorLayers: 2)
        let cels = threeCels(manager, layerIndex: 1)
        emptyAfterFirstBlock(manager, layerIndex: 2)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.currentLayerIndex = 2
        manager.goToFrame(6)
        manager.interpolateAtPlayhead(mode: .generate)
        XCTAssertEqual(manager.layers[2].cels.count, 2, "Setup: the block was added")

        manager.undo()

        XCTAssertEqual(manager.layers[2].cels.count, 1,
                       "One undo takes back both the block and the recipe, not just the recipe")
        XCTAssertNil(manager.interpolationTarget)
    }

    func testGenerateAtThePlayheadRefusesOnARasterLayerWithNoBlock() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2)])
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])

        manager.currentLayerIndex = 0
        manager.goToFrame(6)
        XCTAssertEqual(manager.interpolationRefusalAtPlayhead(mode: .generate), .notAVectorLayer)
        XCTAssertEqual(manager.layers[0].cels.count, 1, "A refusal must not leave a block behind")
    }

    /// Leaves `layerIndex` holding a single short block, so the frames after it are empty slots.
    private func emptyAfterFirstBlock(_ manager: CanvasManager, layerIndex: Int) {
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        manager.layers[layerIndex].cels = [
            Cel(id: UUID(), startFrame: 0, frameCount: 2, raster: .empty(size: size),
                vector: .empty(size: size))
        ]
    }

    // MARK: - Evaluating for display

    /// Moving `t` must change the frame. Together with `InterpolationRenderLogicTests`' endpoint
    /// tests this is what says the slider is wired to the evaluation rather than to nothing.
    func testTheRenderedFrameChangesWithT() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1)

        let layerID = manager.layers[1].id
        let start = try XCTUnwrap(manager.interpolatedImage(forCel: cels[1].id, inLayer: layerID, at: 0))
        let middle = try XCTUnwrap(manager.interpolatedImage(forCel: cels[1].id, inLayer: layerID, at: 0.5))
        XCTAssertNotEqual(bytes(of: start), bytes(of: middle),
                          "t = 0 and t = 0.5 must not render the same frame")
    }

    /// The recipe is by identity, so editing a keyframe changes what the in-between evaluates to
    /// with nothing to invalidate by hand (`PLAN.md` §4). This is the test that would fail if
    /// Generate had baked.
    func testEditingAKeyframeChangesTheInBetweenWithNoReInterpolation() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1)

        let layerID = manager.layers[1].id
        let before = try XCTUnwrap(manager.interpolatedImage(forCel: cels[1].id, inLayer: layerID, at: 0.5))
        cels[0].vector?.addStroke(stroke([CGPoint(x: 8, y: 50), CGPoint(x: 50, y: 50)]))
        let after = try XCTUnwrap(manager.interpolatedImage(forCel: cels[1].id, inLayer: layerID, at: 0.5))

        XCTAssertNotEqual(bytes(of: before), bytes(of: after),
                          "Adding a stroke to keyframe A must show up in the in-between")
    }

    func testACelWithNoRecipeHasNoInterpolatedImage() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        XCTAssertNil(manager.interpolatedImage(forCel: cels[1].id, inLayer: manager.layers[1].id))
    }

    /// "Not yet", not an error (`HANDOFF.md` §5.9). A recipe can be broken by editing *around* it,
    /// and the UI is supposed to fall back to the cel's own content rather than show a failure.
    func testAMalformedRecipeEvaluatesToNilRatherThanCrashing() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.layers[1].cels[1].interpolation = InterpolationRecipe(
            references: [InterpolationReference(layerID: manager.layers[1].id, celID: cels[0].id)],
            t: 0.5)
        XCTAssertNil(manager.interpolatedImage(forCel: cels[1].id, inLayer: manager.layers[1].id),
                     "One reference is not enough to interpolate between")
    }

    /// The toggle has to reach the evaluator, or item 5 is a switch that does nothing.
    func testTheThicknessFadeToggleReachesTheEvaluatorOptions() {
        let manager = manager()
        XCTAssertEqual(manager.interpolationOptions.thicknessFade, .none)
        manager.interpolationThicknessFade = true
        XCTAssertEqual(manager.interpolationOptions.thicknessFade, .weighted(exponent: 1))
    }

    // MARK: - Undo

    func testUndoOfGenerateRemovesTheRecipeInOneStep() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1)
        XCTAssertNotNil(manager.layers[1].cels[1].interpolation, "Setup")

        manager.undo()

        XCTAssertNil(manager.layers[1].cels[1].interpolation,
                     "One undo returns to the pre-interpolation state — Phase 4's definition of done")
    }

    /// A whole drag is one step, not one per tick — the trap `PLAN.md` §9 calls out by name. `t`
    /// lives in the `Cel` struct, so the plain structure bracket is enough here (`HANDOFF.md` §5).
    func testAWholeSliderDragIsOneUndoStep() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1)
        let layerID = manager.layers[1].id
        let originalT = try XCTUnwrap(manager.layers[1].cels[1].interpolation?.t)

        manager.beginInterpolationDrag()
        XCTAssertTrue(manager.isScrubbingInterpolation, "The drag selects .preview render quality")
        for step in stride(from: 0.1, through: 0.9, by: 0.1) {
            manager.setInterpolationT(CGFloat(step), forCel: cels[1].id, inLayer: layerID)
        }
        manager.commitInterpolationDrag()
        XCTAssertFalse(manager.isScrubbingInterpolation, "Release goes back to .full")
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.t ?? 0, 0.9, accuracy: 1e-9)

        manager.undo()
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.t ?? -1, originalT, accuracy: 1e-9,
                       "Nine ticks undo as one step, straight back to where the drag started")
        XCTAssertNotNil(manager.layers[1].cels[1].interpolation,
                        "Undoing the drag must not also undo the interpolation itself")
    }

    func testSettingTClampsToTheSliderRange() throws {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1)
        let layerID = manager.layers[1].id

        // `t` outside 0...1 extrapolates rather than clamping in the evaluator, because
        // `ARAPInterpolation` does — so the clamp has to be here, on the way in (`HANDOFF.md` §5.9).
        manager.setInterpolationT(2.5, forCel: cels[1].id, inLayer: layerID)
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.t ?? -1, 1, accuracy: 1e-9)
        manager.setInterpolationT(-3, forCel: cels[1].id, inLayer: layerID)
        XCTAssertEqual(manager.layers[1].cels[1].interpolation?.t ?? -1, 0, accuracy: 1e-9)
    }

    // MARK: - Onion skin

    /// Interpolate mode's onion skin is the two references, not the previous cel (`PLAN.md` §5.0
    /// step 4) — and they are tinted apart, because a twelve-frame span with both in one colour is
    /// unreadable.
    func testTheInterpolateOnionSkinShowsBothReferencesTintedApart() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        manager.currentFrame = 5

        let frames = InterpolationReferenceOnionSkinSource().frames(for: manager)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].tint, InterpolationReferenceOnionSkinSource.pastTint)
        XCTAssertEqual(frames[1].tint, InterpolationReferenceOnionSkinSource.futureTint)
    }

    func testTheInterpolateOnionSkinShowsNothingUntilTwoReferencesExist() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0]])
        XCTAssertTrue(InterpolationReferenceOnionSkinSource().frames(for: manager).isEmpty)
    }

    /// A multi-layer keyframe is one skin, not two — otherwise lineart and its flats would tint as
    /// separate references and read as four keyframes.
    func testAMultiLayerKeyframeFlattensIntoOneOnionSkinFrame() {
        let manager = manager(vectorLayers: 2)
        let lineart = threeCels(manager, layerIndex: 1)
        let flats = threeCels(manager, layerIndex: 2)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [lineart[0], lineart[2]])
        setReferences(manager, layerIndex: 2, cels: [flats[0], flats[2]])
        XCTAssertEqual(InterpolationReferenceOnionSkinSource().frames(for: manager).count, 2)
    }

    // MARK: - Helpers

    private func bytes(of image: UIImage) -> [UInt8]? {
        RasterVectorParity.premultipliedBytes(of: image,
                                              size: image.size == .zero ? CanvasFixture.canvasSize : image.size)
    }
}
