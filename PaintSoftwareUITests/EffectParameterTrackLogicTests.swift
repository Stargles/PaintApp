import XCTest
import UIKit
import SwiftUI

/// **One animated channel, end to end** — KEYFRAMES.md §8 stage 2.
///
/// Stage 0 made the render tree a function of the frame and left `Layer.layerEffect(atFrame:)`
/// returning a constant. Stage 1 gave every effect parameter a stable address and a read/write lens.
/// This stage joins the two: a `[EffectParameter.id: AnimationCurve]` on the layer, in **absolute
/// document frames** (§2.4), resolved by `Effect.resolved(atFrame:through:)` on every render.
///
/// **What this file is for is proving the five things stage 2 exists to prove before any UI is built
/// on them** — storage, evaluation, invalidation, undo and save/load — plus the two refusals that
/// keep the stage honest: which parameter kinds are in scope, and the rule that a target's tracks are
/// **exactly** the channels its current grade can drive, so that changing the grade takes the rest
/// with it. The save/load half lives in `ProjectSaveLogicTests`, against a real
/// package rather than a hand-built manifest; the two-sided frame-invariance claim lives in
/// `RenderTreeCharacterizationTests`, where the pin it replaced was.
///
/// `@MainActor` because `makeRenderRequest` is; the backend is pinned to CoreGraphics for
/// `EffectLayerLogicTests`' reason, so a pixel assertion is about the grade rather than about which
/// backend the machine happened to pick.
@MainActor
final class EffectParameterTrackLogicTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// The layer index `addValueLayer` leaves the grade on in `gradedManager` below.
    private let gradeIndex = 1

    private let brightnessID = "brightnessContrast.brightness"

    /// An opaque grey floor under a value layer in effect mode — `EffectLayerLogicTests`' smallest
    /// document in which a grade is a number you can write down, reused so a pixel assertion here can
    /// be read against the ones there.
    private func gradedManager(
        _ effect: Effect = .brightnessContrast(Effect.BrightnessContrast(brightness: 1))
    ) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(
            manager, layerIndex: 0,
            CanvasFixture.solidImage(UIColor(white: 128.0 / 255, alpha: 1),
                                     rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        manager.addValueLayer(effect: effect)
        return manager
    }

    /// A straight-line curve through `(frame, value)` pairs. `.linear` rather than the `.bezier`
    /// default so the midpoint of a segment is a number this file can state rather than one it would
    /// have to derive — `AnimationCurveLogicTests` is where the interpolant itself is pinned.
    private func linear(_ pairs: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    /// **Hand-typed for `EffectParameterCharacterizationTests`' reason**: `Effect` cannot be
    /// `CaseIterable`, so nothing in this suite would notice a fourteenth effect. Fourteen entries
    /// over thirteen cases, both blurs listed.
    private static let everyMenuEntry: [Effect] = [
        .brightnessContrast(Effect.BrightnessContrast()),
        .levels(Effect.Levels()),
        .curves(Effect.Curves()),
        .hsvShift(Effect.HSVShift()),
        .gradientMap(Effect.GradientMap()),
        .posterize(Effect.Posterize()),
        .blur(Effect.Blur(radius: 8)),
        .blur(Effect.Blur(radius: 12, angleDegrees: 0, isDirectional: true)),
        .sharpen(Effect.Sharpen(radius: 3, amount: 1)),
        .bloom(Effect.Bloom()),
        .sobel(Effect.Sobel()),
        .outline(Effect.Outline(width: 2)),
        .chromaticAberration(Effect.ChromaticAberration(offsetX: 3, offsetY: 0)),
        .noise(Effect.Noise(amount: 0.08)),
    ]

    private func brightness(_ manager: CanvasManager, atFrame frame: Int) -> Double? {
        guard case .brightnessContrast(let params)? = manager.layers[gradeIndex].layerEffect(atFrame: frame)
        else { return nil }
        return params.brightness
    }

    // MARK: - Evaluation

    /// At the keys, between them, and outside them — the whole of what a channel is asked for.
    ///
    /// The last assertion is the one that is easy to leave out and expensive to get wrong: resolution
    /// **derives**, it does not write back. The stored `effect` is still exactly what the artist typed
    /// after any number of frames have been drawn, because a resolver that mutated the model would
    /// make the value at frame 7 depend on which frames had been visited on the way there.
    func testAKeyedParameterIsItsKeysAtThemAndTweensBetweenThem() {
        let manager = gradedManager()
        XCTAssertTrue(manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                                      to: linear([(0, 1.0), (10, 2.0)])),
                      "Brightness is a continuous Double, so the writer takes it")

        XCTAssertEqual(brightness(manager, atFrame: 0) ?? .nan, 1.0, accuracy: 1e-9, "At the first key")
        XCTAssertEqual(brightness(manager, atFrame: 10) ?? .nan, 2.0, accuracy: 1e-9, "At the last key")
        XCTAssertEqual(brightness(manager, atFrame: 5) ?? .nan, 1.5, accuracy: 1e-9,
                       "Halfway along a linear segment")
        XCTAssertEqual(brightness(manager, atFrame: 2) ?? .nan, 1.2, accuracy: 1e-9, "And a fifth along it")

        // `AnimationCurve` decision 2: a constant hold outside the outermost keys, never an
        // extrapolation. That is what makes a *layer* channel — asked at every frame of the document,
        // including frames this layer has no block on — safe to ask anywhere.
        XCTAssertEqual(brightness(manager, atFrame: -30) ?? .nan, 1.0, accuracy: 1e-9, "Held before the first key")
        XCTAssertEqual(brightness(manager, atFrame: 4000) ?? .nan, 2.0, accuracy: 1e-9, "Held after the last")

        XCTAssertEqual(manager.layers[gradeIndex].effect,
                       .brightnessContrast(Effect.BrightnessContrast(brightness: 1)),
                       "Resolution derives a value for a frame; it never writes one back into the model")
    }

    /// **A document nobody has animated is bit-for-bit the document it was**, which is the claim every
    /// existing test in the suite is silently resting on now that the accessor does work.
    ///
    /// Swept over all fourteen menu entries rather than one, because the guard that makes it true is a
    /// single `tracks.isEmpty` at the top of `Effect.resolved(atFrame:through:)` and a mistake there
    /// would be a mistake for every effect at once.
    func testALayerWithNoTrackResolvesToItsStoredEffectAtEveryFrame() {
        for effect in Self.everyMenuEntry {
            let manager = gradedManager(effect)
            XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty, "Fixture premise: no track")
            for frame in [-7, 0, 1, 11, 12, 4000] {
                XCTAssertEqual(manager.layers[gradeIndex].layerEffect(atFrame: frame), effect,
                               "\(effect.displayName) at frame \(frame): an untracked grade is the stored one")
            }
        }
    }

    /// The step (§2.10) rides through the resolver untouched, because it is a property of the curve
    /// rather than of the channel — evaluated then held, so a grade on twos steps on even frames.
    func testAChannelOnTwosHoldsItsValueForTwoFrames() {
        let manager = gradedManager()
        var curve = linear([(0, 1.0), (8, 2.0)])
        curve.step = 2
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID, to: curve)

        XCTAssertEqual(brightness(manager, atFrame: 2) ?? .nan, 1.25, accuracy: 1e-9)
        XCTAssertEqual(brightness(manager, atFrame: 3) ?? .nan, 1.25, accuracy: 1e-9,
                       "Frame 3 holds frame 2's value — the run is anchored at 0 of the curve's own base")
        XCTAssertEqual(brightness(manager, atFrame: 4) ?? .nan, 1.5, accuracy: 1e-9, "And steps at 4")
    }

    // MARK: - Scope: which parameter kinds this stage drives

    /// **The nine parameters stage 2 refuses, listed by name.**
    ///
    /// A test rather than a comment because the alternative to refusing them is worse than not
    /// shipping them: a `.stepped` field driven by a `Double` curve renders as a staircase the graph
    /// editor never drew, and `outline.color` — `.continuous`, and therefore the one that looks free —
    /// would store, evaluate, write *nothing* through `EffectCaseLens.compound`'s identity lens, and
    /// render exactly as it did before. See `EffectParameter.isScalarAnimatable`, which names each.
    func testExactlyTheContinuousScalarParametersAreAnimatableAtThisStage() {
        var animatable: Set<String> = []
        var refused: Set<String> = []
        for effect in Self.everyMenuEntry {
            for parameter in effect.parameters {
                if parameter.isScalarAnimatable { animatable.insert(parameter.id) } else { refused.insert(parameter.id) }
            }
        }

        XCTAssertEqual(refused.sorted(), [
            "blur.directional",     // .stepped — rewrites the pass list from two entries to one
            "bloom.input",          // .stepped — decides whether the compositor performs a sub-walk
            "curves.points",        // .componentwise — a variable-length list wants a channel each
            "gradientMap.stops",    // .componentwise — likewise
            "noise.monochrome",     // .stepped — half of `true` is not a boolean
            "noise.seed",           // .stepped — a seed is not a quantity
            "outline.color",        // .continuous but compound: the lens is the identity. The trap.
            "posterize.levels",     // .stepped — three levels and four have nothing between them
            "posterize.screen",     // .stepped — half a Bayer screen is not a screen
        ].sorted(), "The refusals are a decision, and each one is refused for its own reason")

        XCTAssertEqual(animatable.count, 24,
                       "24 of the 33 descriptors are continuous Doubles — `EffectCaseLens.double`'s own count")
        XCTAssertTrue(animatable.isDisjoint(with: refused), "A parameter is in exactly one of the two")
        XCTAssertEqual(animatable.count + refused.count, 33, "And every descriptor is in one of them")
    }

    /// **The refusal is at the writer, not only at the resolver**, so a track that would render as
    /// nothing cannot be stored in the first place. Three doors, all closed.
    func testTheWriterRefusesEveryTrackThisStageCouldNotRender() {
        let noise = gradedManager(.noise(Effect.Noise(amount: 0.08)))
        XCTAssertFalse(noise.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "noise.seed",
                                                     to: linear([(0, 1), (10, 900)])),
                       "A `.stepped` UInt32 is not drivable by a Double curve")
        XCTAssertTrue(noise.layers[gradeIndex].effectTracks.isEmpty, "And nothing was stored")
        XCTAssertTrue(noise.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "noise.amount",
                                                   to: linear([(0, 0), (10, 0.4)])),
                      "…while the continuous knob on the same effect is taken")

        let outline = gradedManager(.outline(Effect.Outline(width: 2)))
        XCTAssertFalse(outline.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "outline.color",
                                                       to: linear([(0, 0), (10, 1)])),
                       "`outline.color` is continuous and compound — the one that looks free and is not")

        let blur = gradedManager(.blur(Effect.Blur(radius: 4)))
        XCTAssertFalse(blur.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "bloom.intensity",
                                                    to: linear([(0, 0), (10, 1)])),
                       "An id that is not a parameter of the grade this layer is running")

        XCTAssertFalse(blur.setEffectParameterTrack(layerIndex: 0, parameterID: brightnessID,
                                                    to: linear([(0, 0), (10, 1)])),
                       "A raster layer is not grading, so it has no parameter to address")
        XCTAssertTrue(blur.layers[0].effectTracks.isEmpty)
    }

    // MARK: - A grade's channels do not outlive the grade

    /// **The artist keys a bloom, changes their mind, and picks a blur** — the curve goes with the
    /// bloom, because nothing on a blur addresses `bloom.intensity` and a channel the timeline cannot
    /// show is a channel the document has no business carrying.
    ///
    /// Three assertions, and the third is the one an artist would notice: the tracks are gone, the
    /// blur is a blur at every frame, and coming back to a bloom finds the bloom the picker built at
    /// its own default rather than a value some invisible curve describes.
    func testChangingTheEffectDestroysTheTracksTheNewGradeCannotDrive() {
        let manager = gradedManager(.bloom(Effect.Bloom()))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "bloom.intensity",
                                        to: linear([(0, 0.5), (10, 3.0)]))

        manager.setLayerEffect(layerIndex: gradeIndex, to: .blur(Effect.Blur(radius: 4)))
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty,
                      "The curve does not survive the effect change — nothing addresses `bloom.intensity` now")
        for frame in [0, 5, 10, 99] {
            XCTAssertEqual(manager.layers[gradeIndex].layerEffect(atFrame: frame),
                           .blur(Effect.Blur(radius: 4)),
                           "frame \(frame): a blur is a blur at every frame")
        }

        manager.setLayerEffect(layerIndex: gradeIndex, to: .bloom(Effect.Bloom()))
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty,
                      "…and coming back does not resurrect it")
        guard case .bloom(let params)? = manager.layers[gradeIndex].layerEffect(atFrame: 10) else {
            return XCTFail("The layer is grading with a bloom again")
        }
        XCTAssertEqual(params.intensity, Effect.Bloom().intensity, accuracy: 1e-9,
                       "The bloom is the one the picker built, not the one the destroyed curve described")
    }

    /// **Levels → Curves destroys the track, and `Effect.kindCode` cannot see that it should.** That
    /// field is a GPU dispatch code and merges the two cases — both answer 0, as `.blur` and
    /// `.sharpen` both answer 7 — so a clear written as "did the kind change" keeps `levels.gamma`
    /// here and would be green on every other pair in the catalogue.
    ///
    /// The rule is by parameter id instead, and `curves` has exactly one parameter (`curves.points`,
    /// which is `.componentwise` and takes no scalar track at all), so the surviving set is empty by
    /// construction rather than by the two names happening to differ.
    func testChangingBetweenTwoEffectsThatShareAKindCodeStillDestroysTheTrack() {
        let manager = gradedManager(.levels(Effect.Levels()))
        XCTAssertTrue(manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "levels.gamma",
                                                      to: linear([(0, 1.0), (10, 2.0)])),
                      "Fixture premise: a levels gamma takes a track")
        XCTAssertEqual(Effect.levels(Effect.Levels()).kindCode, Effect.curves(Effect.Curves()).kindCode,
                       "Fixture premise: these two are indistinguishable to `kindCode`, which is the trap")

        manager.setLayerEffect(layerIndex: gradeIndex, to: .curves(Effect.Curves()))
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty,
                      "A curves grade has no `levels.gamma`, whatever the dispatch code says")
    }

    /// **Gaussian and Directional Blur are one `.blur`, so flipping between them keeps the curves** —
    /// the trap on the other side of the same decision. `EffectCatalog.isCurrent` compares
    /// `displayName`, which splits `.blur` in two by `Blur.isDirectional`, so a clear written against
    /// *it* would destroy `blur.radius` and `blur.angle` for a toggle the artist reads as one setting
    /// of one effect.
    ///
    /// Parameter ids do not split: `Effect.parameters` lists all three of `.blur`'s under either
    /// spelling, so the filter keeps both curves and the flip costs nothing. Asserted through the
    /// resolver as well as through the dictionary, because a track that survives storage and no longer
    /// drives anything is the failure this stage exists to make impossible.
    func testFlippingBlurBetweenGaussianAndDirectionalKeepsItsTracks() {
        let manager = gradedManager(.blur(Effect.Blur(radius: 4)))
        XCTAssertTrue(manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "blur.radius",
                                                      to: linear([(0, 4.0), (10, 20.0)])))
        XCTAssertTrue(manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "blur.angle",
                                                      to: linear([(0, 0.0), (10, 90.0)])))

        manager.setLayerEffect(layerIndex: gradeIndex,
                               to: .blur(Effect.Blur(radius: 4, angleDegrees: 0, isDirectional: true)))
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks.keys.sorted(), ["blur.angle", "blur.radius"],
                       "One `.blur` under two names — the artist flipped a toggle, not effects")

        guard case .blur(let params)? = manager.layers[gradeIndex].layerEffect(atFrame: 10) else {
            return XCTFail("The layer is still grading with a blur")
        }
        XCTAssertEqual(params.radius, 20.0, accuracy: 1e-9, "…and both curves still drive it")
        XCTAssertEqual(params.angleDegrees, 90.0, accuracy: 1e-9)
        XCTAssertTrue(params.isDirectional)
    }

    /// **One undo step brings the grade and its channels back together.** The clear rides
    /// `withStructureUndo`'s existing snapshot — `effectTracks` is a field on `Layer`, so the bracket
    /// that already captures `layers` restores it for free — rather than `setEffectParameterTrack`'s
    /// own `recordUndo`, which would record a second step.
    ///
    /// Two steps is not merely untidy: undo once would put the bloom back with its animation still
    /// gone, which is a state the artist can reach and cannot tell from data loss.
    func testUndoingAnEffectChangeRestoresTheTracksItDestroyed() {
        let manager = gradedManager(.bloom(Effect.Bloom()))
        let curve = linear([(0, 0.5), (10, 3.0)])
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "bloom.intensity", to: curve)

        manager.setLayerEffect(layerIndex: gradeIndex, to: .blur(Effect.Blur(radius: 4)))
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty)

        manager.undo()
        XCTAssertEqual(manager.layers[gradeIndex].effect, .bloom(Effect.Bloom()),
                       "One step, so the grade is back…")
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks["bloom.intensity"], curve,
                       "…and the curve came back in the same one, whole")
    }

    /// **Picking a blend mode on a graded layer clears the grade, so it clears the tracks too.** The
    /// second of the two layer-side doors to a grade change, and the one no test would have covered by
    /// accident: `setLayerBlendMode` writes `effect = nil` directly rather than calling
    /// `setLayerEffect`, so the rule has to be spelled there as well and this is what says it is.
    func testPickingABlendModeOnAGradedLayerDestroysItsTracks() {
        let manager = gradedManager(.bloom(Effect.Bloom()))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "bloom.intensity",
                                        to: linear([(0, 0.5), (10, 3.0)]))

        manager.setLayerBlendMode(layerIndex: gradeIndex, to: .multiply)
        XCTAssertNil(manager.layers[gradeIndex].effect, "Fixture premise: the blend pick cleared the grade")
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty,
                      "A layer that is no longer grading holds no channels for a grade")
    }

    // MARK: - Undo

    /// One step per write, and the step is the *track's*, not the document structure's.
    ///
    /// The replacement case is the half worth having: undoing an edit to a curve that already existed
    /// has to restore the previous curve, not clear the channel, which is the mistake a writer that
    /// stored only "there was no track" would make.
    func testWritingReplacingAndClearingATrackAreEachOneUndoStep() {
        let manager = gradedManager()
        let first = linear([(0, 1.0), (10, 2.0)])
        let second = linear([(0, 1.0), (4, 0.5), (10, 3.0)])

        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID, to: first)
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty, "Undo takes the whole channel back")
        manager.redo()
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID], first, "And redo brings it back")

        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID, to: second)
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID], second)
        manager.undo()
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID], first,
                       "Undoing a replacement restores the previous curve, not the absence of one")

        manager.redo()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID, to: nil)
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty)
        manager.undo()
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID], second,
                       "Clearing is undoable like any other write")
    }

    /// A write that changes nothing records nothing — the rule every setter in `CanvasManager`
    /// follows, and the one an auto-keying slider re-writing the value already under the playhead hits
    /// constantly. An empty curve is the same state as no curve, deliberately: a channel that exists
    /// and animates nothing would show up in a channel list and do nothing.
    func testAWriteThatChangesNothingRecordsNoStep() {
        let manager = gradedManager()
        let curve = linear([(0, 1.0), (10, 2.0)])
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID, to: curve)
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        XCTAssertFalse(manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID, to: curve),
                       "The same curve again is not a change")
        XCTAssertFalse(manager.canUndo, "…so there is nothing to undo")

        XCTAssertFalse(manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "brightnessContrast.contrast",
                                                       to: AnimationCurve()),
                       "An empty curve on an unkeyed channel is the state it is already in")
        XCTAssertFalse(manager.canUndo)
    }

    /// The undo closures address the layer **by id**, so an edit that survives a restack comes back to
    /// the right layer. `withStructureUndo`'s whole-array restore is what hides this everywhere else;
    /// a narrow write path has to do it itself.
    func testUndoFindsTheLayerAfterItsIndexHasMoved() {
        let manager = gradedManager()
        let gradeID = manager.layers[gradeIndex].id
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))

        manager.deleteLayer(at: 0)
        XCTAssertEqual(manager.layers.firstIndex { $0.id == gradeID }, 0,
                       "Fixture premise: the graded layer is no longer at the index its track was written at")

        manager.undo()   // the delete
        manager.undo()   // the track
        XCTAssertTrue(manager.layers.first { $0.id == gradeID }?.effectTracks.isEmpty ?? false,
                      "The track's undo found its layer by id rather than by the index it was written at")
    }

    // MARK: - Invalidation (§4.1's "this is free" claim, checked rather than trusted)

    /// **§4.1 says invalidation needs no new plumbing. It does not, and this is why.**
    ///
    /// Both cache keys carry the resolved `[RenderNode]` *and* the per-layer `LayerContentVersion`,
    /// and `RenderNode.effect` and `LayerContentVersion.effect` are each compared verbatim. Because
    /// both are built from `layerEffect(atFrame:)`, a keyed grade moves them on its own.
    ///
    /// **The bake key carries no `frame` at all** (RENDER.md §3.3 — a nine-frame hold is one file),
    /// which is what makes this test say what it means rather than passing on the frame number. Two
    /// keys derived at two frames of a document with no track are therefore *equal*, and the control
    /// at the bottom asserts exactly that; the claim being made is that the resolved grade, and not
    /// the frame, is what moves the key. That matters because the frame is not in every cache —
    /// `MaskResolver`'s is keyed on these content versions and carries no tree and no frame at all,
    /// so a version that failed to move would go on serving coverage resolved under the old grade
    /// wherever the grade reshapes alpha.
    func testAKeyedGradeMovesTheCacheKeyEvenWithTheFrameHeldEqual() {
        let manager = gradedManager(.blur(Effect.Blur(radius: 2)))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "blur.radius",
                                        to: linear([(0, 2), (10, 40)]))

        func versions(atFrame frame: Int) -> [LayerContentVersion?] {
            manager.layers.indices.map { index -> LayerContentVersion? in
                guard let celIndex = manager.activeCelIndex(inLayer: index, atFrame: frame) else { return nil }
                return LayerContentVersion(cel: manager.layers[index].cels[celIndex],
                                           valueFill: manager.layers[index].valueFill,
                                           effect: manager.layers[index].layerEffect(atFrame: frame))
            }
        }
        // Through the app's own mint rather than a hand-built value: a stand-in that assembles the
        // key its own way is not testing the builder the app uses, which is how the derivation came
        // to be missing from `SandwichKey` in the first place.
        func key(derivedAt frame: Int, _ document: CanvasManager = manager) -> FrameBakeKey? {
            document.makeFrameRecipe(atFrame: frame, includeBackground: true, sizing: .liveComposite)
                .map { FrameBakeKey(recipe: $0, renderResolution: document.renderResolution) }
        }

        XCTAssertNotEqual(manager.renderTree(atFrame: 0), manager.renderTree(atFrame: 10),
                          "`RenderNode.effect` is the resolved grade, so the tree itself moves")
        XCTAssertNotEqual(versions(atFrame: 0), versions(atFrame: 10),
                          "…and so does the content version, which is the key `MaskResolver` uses and which carries no frame")
        XCTAssertNotNil(key(derivedAt: 0), "Fixture needs a canvas size")
        XCTAssertNotEqual(key(derivedAt: 0), key(derivedAt: 10),
                          "So the bake key moves for the grade, and it cannot be the frame number: "
                          + "`FrameBakeKey` has no frame field")

        let untracked = gradedManager(.blur(Effect.Blur(radius: 2)))
        XCTAssertEqual(untracked.renderTree(atFrame: 0), untracked.renderTree(atFrame: 10),
                       "And a document with no track derives one tree, which is the other half of the claim")
        XCTAssertEqual(key(derivedAt: 0, untracked), key(derivedAt: 10, untracked),
                       "…so its two frames are one file, which is what says the assertion above "
                       + "measured the grade rather than the frame")
    }

    /// The end of the wire: two frames of the same document composite to **different pixels**.
    ///
    /// Everything above is about values and keys; this is the only assertion here that would fail if
    /// the resolved effect stopped reaching a backend. Brightness rather than a blur so the expected
    /// byte is CSS Filter Effects Level 1 arithmetic on a flat grey and not a convolution.
    func testTheCompositeItselfDiffersBetweenTwoFramesOfAnAnimatedGrade() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 1.5)]))

        func centrePixel(atFrame frame: Int) -> [Int] {
            guard let image = manager.makeRenderRequest(atFrame: frame, includeBackground: false)
                .flatMap(Compositor.composite),
                  let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
            let offset = (32 + 32 * image.width) * 4
            return bytes[offset..<(offset + 4)].map(Int.init)
        }

        // `brightness(1)` is the identity, so frame 0 is the untouched floor.
        XCTAssertEqual(centrePixel(atFrame: 0), [128, 128, 128, 255],
                       "At the first key the grade is the identity and the floor is what it was")
        // `brightness(1.5)` on 128/255, clamped once, back to a byte: round(128 * 1.5) = 192.
        XCTAssertEqual(centrePixel(atFrame: 10), [192, 192, 192, 255],
                       "At the last key the same document composites to the graded value")
        XCTAssertEqual(centrePixel(atFrame: 5), [160, 160, 160, 255],
                       "And an in-between frame is the tweened grade, rendered")
    }

    // MARK: - Presence, which a parameter track must never touch

    /// **`CanvasManager.compositorSizeGate`'s expiry note has not been spent, and this is the pin.**
    ///
    /// That gate counts `node.effect != nil` over a tree derived at `currentFrame`, and it is safe
    /// only for as long as no track can turn an effect on or off at a frame. A *parameter* track
    /// changes values; presence is decided by `Layer.layerEffect`, which reads `kind` and `effect` and
    /// knows nothing about a track, and `Effect.resolved(atFrame:through:)` has no arm that can return
    /// nil. Both halves are asserted: the gate's own two numbers, and the accessor underneath it.
    func testNoParameterTrackCanMakeAGradeAppearOrDisappearAtAFrame() {
        let manager = gradedManager()
        // A curve that passes through the identity and through zero, which is as close as a parameter
        // channel can come to "no effect" — and it is still an effect.
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (5, 0.0), (10, 2.0)]))

        for frame in [-4, 0, 5, 10, 900] {
            XCTAssertNotNil(manager.layers[gradeIndex].layerEffect(atFrame: frame),
                            "frame \(frame): a value of zero is a grade that does something, not an absent grade")
            XCTAssertNil(manager.layers[0].layerEffect(atFrame: frame),
                         "frame \(frame): and a raster layer never acquires one")
        }

        // The two numbers the compositor's memory arithmetic is built from — `chunkSources`'
        // divisor and `affordableRows`' — read `node.effect != nil` for *presence* and never a
        // parameter out of it. So they must be the same at every frame, or a chunk width and a strip
        // height would become functions of where the playhead happens to be sitting.
        let atZero = manager.renderTree(atFrame: 0)
        for frame in [1, 5, 10, 11] {
            let tree = manager.renderTree(atFrame: frame)
            XCTAssertEqual(tree.peakCompositeTextures, atZero.peakCompositeTextures,
                           "frame \(frame): the walk's texture peak must not become a function of the playhead")
            XCTAssertEqual(tree.uploadableLeafCount, atZero.uploadableLeafCount, "frame \(frame)")
        }
    }

    /// A track written by hand onto a layer that is not grading reaches nothing — the second half of
    /// the presence guarantee, from the other direction. Only a hand-written manifest can produce this
    /// state: the writer refuses it at the door (above) and the mode picker clears it on the way out.
    /// So it is worth pinning that the *reader* is safe too, rather than resting on two doors that a
    /// future edit could open.
    ///
    /// **The plant happens after the mode flip, and that ordering is the point.** Written before it,
    /// the flip to flat colour would clear the value layer's track and this test would pass because
    /// there was nothing left to resolve rather than because the resolver refused it.
    func testATrackOnALayerThatIsNotGradingResolvesToNothing() {
        let manager = gradedManager()
        manager.setLayerEffect(layerIndex: gradeIndex, to: nil)
        manager.layers[0].effectTracks[brightnessID] = linear([(0, 1.0), (10, 2.0)])
        manager.layers[gradeIndex].effectTracks[brightnessID] = linear([(0, 1.0), (10, 2.0)])

        for frame in [0, 5, 10] {
            XCTAssertNil(manager.layers[0].layerEffect(atFrame: frame), "A raster layer has no grade to resolve")
            XCTAssertNil(manager.layers[gradeIndex].layerEffect(atFrame: frame),
                         "Nor does a value layer the artist put back into flat-colour mode")
        }
    }

    // MARK: - Folders (§2.21, stage 2b) — the same channel, on the other grade home

    /// A graded folder holding one inked layer. `effect` on a `LayerFolder` is legal on an ordinary
    /// group as well as on a compositor node (`setNodeEffect`), so this is a plain folder — the shape
    /// an artist reaches by grading a group they already had.
    private func gradedFolderManager(
        _ effect: Effect = .brightnessContrast(Effect.BrightnessContrast(brightness: 1))
    ) -> (manager: CanvasManager, folderID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(
            manager, layerIndex: 0,
            CanvasFixture.solidImage(UIColor(white: 128.0 / 255, alpha: 1),
                                     rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        let group = manager.addFolder(name: "Graded group")
        manager.restackLayer(manager.layers[0].id, above: .folder(group), parentFolderID: group)
        manager.setNodeEffect(group, to: effect)
        return (manager, group)
    }

    private func folder(_ manager: CanvasManager, _ id: UUID) -> LayerFolder? {
        manager.folders.first { $0.id == id }
    }

    private func folderBrightness(_ manager: CanvasManager, _ id: UUID, atFrame frame: Int) -> Double? {
        guard case .brightnessContrast(let params)? = folder(manager, id)?.resolvedEffect(atFrame: frame)
        else { return nil }
        return params.brightness
    }

    /// **§2.21, in one assertion each: at the keys, between them, and outside them.**
    ///
    /// This is `testAKeyedParameterIsItsKeysAtThemAndTweensBetweenThem` with the grade on a folder
    /// instead of a layer, and the point of running it twice is exactly that the answers must be
    /// indistinguishable. The ruling is about sameness — the alternative the owner refused was a
    /// slider that keys in the layer panel and silently refuses on a node — so a divergence here is
    /// the ruling not being implemented, whatever the numbers say individually.
    ///
    /// The last assertion is the one that is easy to leave out: resolution **derives**, and the stored
    /// `effect` is still what the artist typed after any number of frames have been drawn.
    func testAKeyedFolderParameterIsItsKeysAtThemAndTweensBetweenThem() {
        let (manager, group) = gradedFolderManager()
        XCTAssertTrue(manager.setEffectParameterTrack(folderID: group, parameterID: brightnessID,
                                                      to: linear([(0, 1.0), (10, 2.0)])),
                      "A folder's grade takes a track exactly as a layer's does")

        XCTAssertEqual(folderBrightness(manager, group, atFrame: 0) ?? .nan, 1.0, accuracy: 1e-9)
        XCTAssertEqual(folderBrightness(manager, group, atFrame: 10) ?? .nan, 2.0, accuracy: 1e-9)
        XCTAssertEqual(folderBrightness(manager, group, atFrame: 5) ?? .nan, 1.5, accuracy: 1e-9,
                       "Halfway along a linear segment is the midpoint of its two keys")
        XCTAssertEqual(folderBrightness(manager, group, atFrame: -8) ?? .nan, 1.0, accuracy: 1e-9,
                       "Before the first key the curve holds flat, so a folder with no block anywhere "
                       + "near this frame still answers — which is what an absolute-frame channel is for")
        XCTAssertEqual(folderBrightness(manager, group, atFrame: 900) ?? .nan, 2.0, accuracy: 1e-9)

        XCTAssertEqual(folder(manager, group)?.effect,
                       .brightnessContrast(Effect.BrightnessContrast(brightness: 1)),
                       "The stored grade is untouched: resolving derives a value, it does not write one back")
    }

    /// A folder nobody has keyed resolves to its stored grade at every frame — the half that keeps
    /// every existing document byte-identical in behaviour, and the guard at the top of
    /// `Effect.resolved(atFrame:through:)` is the whole of it.
    func testAFolderWithNoTrackResolvesToItsStoredEffectAtEveryFrame() {
        let (manager, group) = gradedFolderManager(.blur(Effect.Blur(radius: 6)))
        for frame in [-3, 0, 7, 400] {
            XCTAssertEqual(folder(manager, group)?.resolvedEffect(atFrame: frame),
                           .blur(Effect.Blur(radius: 6)),
                           "frame \(frame): no track means the stored constant, as it always did")
        }
    }

    /// **The refusals are the writer's, on the folder door as much as the layer one.** Storing a track
    /// that renders as nothing is the failure stage 2 made impossible; §2.21 must not reopen it on the
    /// other grade home. `EffectParameter.isScalarAnimatable` is one property consulted from both
    /// overloads, so this is checking the door is wired, not re-deriving which nine are refused —
    /// `testExactlyTheContinuousScalarParametersAreAnimatableAtThisStage` owns that list.
    func testTheFolderWriterRefusesEveryTrackThisStageCouldNotRender() {
        let (noise, noiseGroup) = gradedFolderManager(.noise(Effect.Noise(amount: 0.08)))
        XCTAssertFalse(noise.setEffectParameterTrack(folderID: noiseGroup, parameterID: "noise.seed",
                                                     to: linear([(0, 1), (10, 900)])),
                       "A `.stepped` UInt32 is not drivable by a Double curve, on a folder either")
        XCTAssertEqual(folder(noise, noiseGroup)?.effectTracks.isEmpty, true, "And nothing was stored")
        XCTAssertTrue(noise.setEffectParameterTrack(folderID: noiseGroup, parameterID: "noise.amount",
                                                    to: linear([(0, 0), (10, 0.4)])),
                      "…while the continuous knob on the same effect is taken")

        let (outline, outlineGroup) = gradedFolderManager(.outline(Effect.Outline(width: 2)))
        XCTAssertFalse(outline.setEffectParameterTrack(folderID: outlineGroup, parameterID: "outline.color",
                                                       to: linear([(0, 0), (10, 1)])),
                       "`outline.color` is continuous and compound — the one that looks free and is not")

        let (blur, blurGroup) = gradedFolderManager(.blur(Effect.Blur(radius: 4)))
        XCTAssertFalse(blur.setEffectParameterTrack(folderID: blurGroup, parameterID: "bloom.intensity",
                                                    to: linear([(0, 0), (10, 1)])),
                       "An id that is not a parameter of the grade this folder is running")

        let plain = blur.addFolder(name: "Ungraded")
        XCTAssertFalse(blur.setEffectParameterTrack(folderID: plain, parameterID: brightnessID,
                                                    to: linear([(0, 0), (10, 1)])),
                       "A folder with no grade has no parameter to address")
        XCTAssertFalse(blur.setEffectParameterTrack(folderID: UUID(), parameterID: brightnessID,
                                                    to: linear([(0, 0), (10, 1)])),
                       "…and neither does a folder id that is not in the document")
    }

    /// One step per write on a folder too, and the replacement case is the half worth having: undoing
    /// an edit to a curve that already existed must restore the previous curve, not clear the channel.
    ///
    /// The last block is the folder's version of `testUndoFindsTheLayerAfterItsIndexHasMoved`. A
    /// folder is addressed by id in the signature rather than only inside the closures, so there is no
    /// index to go stale — but `folders` is still an array whose *positions* move, and the write
    /// re-resolves the id on every call rather than capturing one.
    func testWritingReplacingAndClearingAFolderTrackAreEachOneUndoStep() {
        let (manager, group) = gradedFolderManager()
        let first = linear([(0, 1.0), (10, 2.0)])
        let second = linear([(0, 1.0), (4, 0.5), (10, 3.0)])

        manager.setEffectParameterTrack(folderID: group, parameterID: brightnessID, to: first)
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertEqual(folder(manager, group)?.effectTracks.isEmpty, true, "Undo takes the whole channel back")
        manager.redo()
        XCTAssertEqual(folder(manager, group)?.effectTracks[brightnessID], first, "And redo brings it back")

        manager.setEffectParameterTrack(folderID: group, parameterID: brightnessID, to: second)
        manager.undo()
        XCTAssertEqual(folder(manager, group)?.effectTracks[brightnessID], first,
                       "Undoing a replacement restores the previous curve, not the absence of one")

        manager.redo()
        manager.setEffectParameterTrack(folderID: group, parameterID: brightnessID, to: nil)
        XCTAssertEqual(folder(manager, group)?.effectTracks.isEmpty, true)
        manager.undo()
        XCTAssertEqual(folder(manager, group)?.effectTracks[brightnessID], second,
                       "Clearing is undoable like any other write")

        manager.history.removeAll()
        manager.refreshUndoRedoState()
        XCTAssertFalse(manager.setEffectParameterTrack(folderID: group, parameterID: brightnessID, to: second),
                       "The same curve again is not a change…")
        XCTAssertFalse(manager.canUndo, "…so there is nothing to undo")

        // A second folder inserted ahead of the graded one, so its position in `folders` is not the
        // one its track was written at.
        manager.setEffectParameterTrack(folderID: group, parameterID: brightnessID, to: first)
        _ = manager.addFolder(name: "Later")
        XCTAssertGreaterThan(manager.folders.count, 1, "Fixture premise: `folders` has moved on")
        manager.undo()   // the folder add
        manager.undo()   // the track
        XCTAssertEqual(folder(manager, group)?.effectTracks[brightnessID], second,
                       "The track's undo found its folder by id, not by a captured position")
    }

    /// **The tree carries the folder's resolved grade, so every cache with a tree in its key moves.**
    /// `RenderNode.effect` is filled from `resolvedEffect(atFrame:)` (`RenderTree.renderNodes`), and
    /// `RenderNode` is `Equatable` over it — the same one-line claim §4.1 makes for the layer form, on
    /// the node form, checked rather than assumed.
    func testAKeyedFolderGradeMakesTheTreeDifferBetweenTwoFrames() {
        let (manager, group) = gradedFolderManager(.blur(Effect.Blur(radius: 2)))
        manager.setEffectParameterTrack(folderID: group, parameterID: "blur.radius",
                                        to: linear([(0, 2), (10, 40)]))

        let atZero = manager.renderTree(atFrame: 0)
        let atTen = manager.renderTree(atFrame: 10)
        XCTAssertNotEqual(atZero, atTen, "A keyed folder grade is a different grade at a different frame")
        XCTAssertEqual(atZero.first { $0.id == group }?.effect, .blur(Effect.Blur(radius: 2)))
        XCTAssertEqual(atTen.first { $0.id == group }?.effect, .blur(Effect.Blur(radius: 40)))

        let (untracked, _) = gradedFolderManager(.blur(Effect.Blur(radius: 2)))
        XCTAssertEqual(untracked.renderTree(atFrame: 0), untracked.renderTree(atFrame: 10),
                       "And a document with no track derives one tree, which is the other half of the claim")
    }

    /// **The cache that had no way to see a folder's grade, and now does** — `MaskResolver`'s.
    ///
    /// Its key is per-*layer* `LayerContentVersion`s gathered from `stack.leafLayerIndices`, plus the
    /// masks; a folder is not a leaf, so a grade on the folder a mask names was invisible to it. That
    /// was written down as a KNOWN GAP when the folder grade shipped and left for a later pass on the
    /// grounds that it needed an artist to edit the grade before it bit. **§2.21 is what made it
    /// urgent**: a folder track changes that grade with no edit at all, on every frame of playback,
    /// which is a different failure to look at.
    ///
    /// A blur is the grade because it is one of the five `reshapesCoverage` names — the coverage this
    /// cache holds really is a different shape at the two frames, so serving the first for the second
    /// is visibly wrong rather than theoretically wrong. The identity assertion is the one that fails
    /// on the unfixed code: the cache would hand back the very same `ResolvedMask` object.
    func testAKeyedFolderGradeInvalidatesTheMaskResolverCache() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.white,
                                                               rect: CGRect(x: 8, y: 8, width: 24, height: 48)))
        let group = manager.addFolder(name: "Mask source")
        manager.restackLayer(manager.layers[0].id, above: .folder(group), parentFolderID: group)
        manager.setNodeEffect(group, to: .blur(Effect.Blur(radius: 1)))
        XCTAssertTrue(manager.setEffectParameterTrack(folderID: group, parameterID: "blur.radius",
                                                      to: linear([(0, 1), (10, 24)])),
                      "Fixture premise: the folder's blur radius takes a track")

        let mask = AlphaMask(sources: [.folder(group)])
        guard let masked = manager.layers.firstIndex(where: { $0.parentFolderID == nil }) else {
            return XCTFail("Fixture premise: one layer is still outside the folder to be masked")
        }
        manager.layers[masked].alphaMask = mask

        guard let atZero = manager.makeRenderRequest(atFrame: 0, includeBackground: false)
            .flatMap({ MaskResolver.coverage(for: [mask], of: $0) }) else {
            return XCTFail("The mask must resolve at frame 0")
        }
        guard let atTen = manager.makeRenderRequest(atFrame: 10, includeBackground: false)
            .flatMap({ MaskResolver.coverage(for: [mask], of: $0) }) else {
            return XCTFail("The mask must resolve at frame 10")
        }

        XCTAssertFalse(atZero === atTen,
                       "A folder grade resolved at a different frame is a different key — the same object "
                       + "back means the cache cannot see the folder's grade at all")
        XCTAssertNotEqual(atZero.coverage, atTen.coverage,
                          "…and the coverage really is a different shape, because a blur reshapes alpha")
    }

    /// **A folder parameter track cannot turn a grade on or off either**, which is the second half of
    /// the promise `CanvasManager.compositorSizeGate` rests on — that gate counts `node.effect != nil`
    /// over a tree derived at `currentFrame`, and a *folder* node is exactly what it counts.
    ///
    /// Presence on a folder is `effect != nil` outright, decided one line above the resolver, and
    /// `Effect.resolved(atFrame:through:)` has no arm that returns nil. So the guarantee is the same
    /// one and rests on the same code; stage 2b did not spend it any more than stage 2 did.
    func testNoFolderParameterTrackCanMakeAGradeAppearOrDisappearAtAFrame() {
        let (manager, group) = gradedFolderManager()
        manager.setEffectParameterTrack(folderID: group, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (5, 0.0), (10, 2.0)]))

        for frame in [-4, 0, 5, 10, 900] {
            XCTAssertNotNil(folder(manager, group)?.resolvedEffect(atFrame: frame),
                            "frame \(frame): a value of zero is a grade that does something, not an absent grade")
        }

        // The two numbers the compositor's memory arithmetic is built from — `chunkSources`'
        // divisor and `affordableRows`' — read `node.effect != nil` for *presence* and never a
        // parameter out of it. So they must be the same at every frame, or a chunk width and a strip
        // height would become functions of where the playhead happens to be sitting.
        let atZero = manager.renderTree(atFrame: 0)
        for frame in [1, 5, 10, 11] {
            let tree = manager.renderTree(atFrame: frame)
            XCTAssertEqual(tree.peakCompositeTextures, atZero.peakCompositeTextures,
                           "frame \(frame): the walk's texture peak must not become a function of the playhead")
            XCTAssertEqual(tree.uploadableLeafCount, atZero.uploadableLeafCount, "frame \(frame)")
        }
    }

    /// The folder half of "a grade's channels do not outlive the grade": keyed on a bloom, switched to
    /// a blur, the curve is gone and flipping back does not find it.
    ///
    /// Here for `LayerFolder.effectTracks`' own reason rather than for symmetry's sake — the two homes
    /// are written by two different setters, so the folder's clear could have been forgotten
    /// independently, and the artist meets one slider in both places.
    func testAFolderTrackIsDestroyedWhenTheGradeChanges() {
        let (manager, group) = gradedFolderManager(.bloom(Effect.Bloom()))
        manager.setEffectParameterTrack(folderID: group, parameterID: "bloom.intensity",
                                        to: linear([(0, 0.5), (10, 3.0)]))

        manager.setNodeEffect(group, to: .blur(Effect.Blur(radius: 4)))
        XCTAssertEqual(folder(manager, group)?.effectTracks.isEmpty, true,
                       "The curve does not survive the effect change")
        for frame in [0, 5, 10, 99] {
            XCTAssertEqual(folder(manager, group)?.resolvedEffect(atFrame: frame), .blur(Effect.Blur(radius: 4)),
                           "frame \(frame): a blur is a blur at every frame")
        }

        manager.setNodeEffect(group, to: .bloom(Effect.Bloom()))
        XCTAssertEqual(folder(manager, group)?.effectTracks.isEmpty, true,
                       "…and coming back does not resurrect it")
        guard case .bloom(let params)? = folder(manager, group)?.resolvedEffect(atFrame: 10) else {
            return XCTFail("The folder is grading with a bloom again")
        }
        XCTAssertEqual(params.intensity, Effect.Bloom().intensity, accuracy: 1e-9,
                       "The bloom is the one the picker built, not the one the destroyed curve described")
    }

    /// **Picking a Mix blend on a graded node clears the grade, so it clears the tracks too** — the
    /// fourth and last door to a grade change, and the folder half of
    /// `testPickingABlendModeOnAGradedLayerDestroysItsTracks`.
    ///
    /// A node rather than an ordinary group, because `setMixBlendMode` refuses anything that is not
    /// already a node: an ordinary folder the artist made must not acquire an op by being asked about
    /// one. `setNodeEffect` is what reshapes the op to `.stack` on the way in, which is the pair of
    /// setters "each clearing what the other set" seen from the grade's side.
    func testPickingAMixBlendOnAGradedNodeDestroysItsTracks() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let node = manager.addCompositorNode(op: .mix(.multiply), name: "Mix")
        manager.restackLayer(manager.layers[0].id, above: .folder(node), parentFolderID: node)
        manager.setNodeEffect(node, to: .bloom(Effect.Bloom()))
        XCTAssertTrue(manager.setEffectParameterTrack(folderID: node, parameterID: "bloom.intensity",
                                                      to: linear([(0, 0.5), (10, 3.0)])),
                      "Fixture premise: the node's bloom intensity takes a track")

        manager.setMixBlendMode(node, to: .screen)
        XCTAssertNil(folder(manager, node)?.effect, "Fixture premise: the blend pick cleared the grade")
        XCTAssertEqual(folder(manager, node)?.effectTracks.isEmpty, true,
                       "A node that folds two inputs holds no channels for a grade it no longer runs")
    }
}
