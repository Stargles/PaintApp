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

    /// Reproject is stubbed in this phase and refuses out loud rather than quietly behaving like
    /// Generate. `PLAN.md` §10 decision 3 says the two are never conflated; a stub that silently
    /// generated would be exactly that conflation.
    func testReprojectRefusesRatherThanBehavingLikeGenerate() {
        let manager = manager()
        let cels = threeCels(manager, layerIndex: 1)
        manager.enterInterpolateMode()
        setReferences(manager, layerIndex: 1, cels: [cels[0], cels[2]])
        XCTAssertEqual(manager.interpolate(mode: .reproject, layerIndex: 1, celIndex: 1),
                       .reprojectNotImplemented)
        XCTAssertNil(manager.layers[1].cels[1].interpolation)
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
