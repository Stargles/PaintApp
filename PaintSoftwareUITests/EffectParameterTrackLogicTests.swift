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
/// keep the stage honest: which parameter kinds are in scope, and what a track that no longer
/// addresses anything does. The save/load half lives in `ProjectSaveLogicTests`, against a real
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

    // MARK: - A track whose parameter is no longer there

    /// **The artist keys a bloom, changes their mind, and picks a blur.** Decided: the orphaned curve
    /// is **kept and inert** — not deleted, and not applied to anything else.
    ///
    /// Inert falls out of the resolver walking *the effect's* descriptor table and looking each entry
    /// up in the track dictionary, rather than the other way round; nothing keyed `bloom.intensity`
    /// can reach a blur, and the ids being `"<case>.<field>"` means `blur.radius` and `bloom.radius`
    /// are two addresses rather than one shared name.
    ///
    /// Kept is the choice, and it is `Layer.valueFill`'s asymmetry for the third time: a picker that
    /// silently destroyed the other mode's setting is the one thing a picker must not do. The cost is
    /// one inert dictionary entry; the alternative loses an authored curve to a dropdown, and the
    /// artist finds out one flip later.
    func testATrackForAParameterTheCurrentEffectDoesNotHaveIsKeptAndIgnored() {
        let manager = gradedManager(.bloom(Effect.Bloom()))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "bloom.intensity",
                                        to: linear([(0, 0.5), (10, 3.0)]))

        manager.setLayerEffect(layerIndex: gradeIndex, to: .blur(Effect.Blur(radius: 4)))
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks.keys.sorted(), ["bloom.intensity"],
                       "The curve survives the effect change")
        for frame in [0, 5, 10, 99] {
            XCTAssertEqual(manager.layers[gradeIndex].layerEffect(atFrame: frame),
                           .blur(Effect.Blur(radius: 4)),
                           "frame \(frame): a blur is a blur at every frame — the orphaned curve reaches nothing")
        }

        manager.setLayerEffect(layerIndex: gradeIndex, to: .bloom(Effect.Bloom()))
        guard case .bloom(let params)? = manager.layers[gradeIndex].layerEffect(atFrame: 10) else {
            return XCTFail("The layer is grading with a bloom again")
        }
        XCTAssertEqual(params.intensity, 3.0, accuracy: 1e-9,
                       "…and going back finds the animation where the artist left it")
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
    /// follows, and the one an Animate mode re-writing the value already under the playhead will hit
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
    /// **The keys also carry `frame`, which is why the obvious test would be vacuous** — two keys at
    /// two frames differ whatever the tree says. So the frame is held *equal* below and the tree and
    /// contents are derived at two different frames, which isolates the claim actually being made:
    /// the resolved grade, not merely the frame number, is what moves the key. That matters because
    /// the frame is not in every cache — `MaskResolver`'s is keyed on these content versions and
    /// carries no tree and no frame at all, so a version that failed to move would go on serving
    /// coverage resolved under the old grade wherever the grade reshapes alpha.
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
        // The frame field is pinned to 0 in both, so nothing below can pass because of it.
        func key(derivedAt frame: Int) -> SandwichFullKey {
            SandwichFullKey(tree: manager.renderTree(atFrame: frame), frame: 0,
                            contents: versions(atFrame: frame), renderResolution: .full,
                            canvasBackgroundColor: manager.canvasBackgroundColor,
                            isCanvasBackgroundVisible: manager.isCanvasBackgroundVisible)
        }

        XCTAssertNotEqual(manager.renderTree(atFrame: 0), manager.renderTree(atFrame: 10),
                          "`RenderNode.effect` is the resolved grade, so the tree itself moves")
        XCTAssertNotEqual(versions(atFrame: 0), versions(atFrame: 10),
                          "…and so does the content version, which is the key `MaskResolver` uses and which carries no frame")
        XCTAssertNotEqual(key(derivedAt: 0), key(derivedAt: 10),
                          "So the sandwich key moves for the grade, not merely for the frame number")

        let untracked = gradedManager(.blur(Effect.Blur(radius: 2)))
        XCTAssertEqual(untracked.renderTree(atFrame: 0), untracked.renderTree(atFrame: 10),
                       "And a document with no track derives one tree, which is the other half of the claim")
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

        manager.currentFrame = 0
        let atZero = manager.compositorSizeGate
        for frame in [1, 5, 10, 11] {
            manager.currentFrame = frame
            XCTAssertEqual(manager.compositorSizeGate.nativeTextures, atZero.nativeTextures,
                           "The resize dialog's admission gate must not become a function of the playhead")
            XCTAssertEqual(manager.compositorSizeGate.sandwichTextures, atZero.sandwichTextures)
        }
    }

    /// A track written by hand onto a layer that is not grading reaches nothing — the second half of
    /// the presence guarantee, from the other direction. Only a hand-written manifest or a kind flip
    /// can produce this state, since the writer refuses it (above), so it is worth pinning that the
    /// *reader* is safe too rather than relying on the door.
    func testATrackOnALayerThatIsNotGradingResolvesToNothing() {
        let manager = gradedManager()
        manager.layers[0].effectTracks[brightnessID] = linear([(0, 1.0), (10, 2.0)])
        manager.layers[gradeIndex].effectTracks[brightnessID] = linear([(0, 1.0), (10, 2.0)])
        manager.setLayerEffect(layerIndex: gradeIndex, to: nil)

        for frame in [0, 5, 10] {
            XCTAssertNil(manager.layers[0].layerEffect(atFrame: frame), "A raster layer has no grade to resolve")
            XCTAssertNil(manager.layers[gradeIndex].layerEffect(atFrame: frame),
                         "Nor does a value layer the artist put back into flat-colour mode")
        }
    }

    // MARK: - Folders, which §9 question 3 has not ruled on

    /// **`LayerFolder.resolvedEffect(atFrame:)` is still constant, deliberately.** §2.4 puts keys on
    /// the layer and says nothing about a folder; §9 question 3 is the open one. Pinned so that
    /// whoever answers it has to change a test that says why rather than discovering the gap.
    func testAFolderEffectIsStillConstantAtEveryFrame() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let group = manager.addFolder(name: "Graded group")
        manager.restackLayer(manager.layers[0].id, above: .folder(group), parentFolderID: group)
        manager.setNodeEffect(group, to: .brightnessContrast(Effect.BrightnessContrast(brightness: 1.2)))

        guard let folder = manager.folders.first(where: { $0.id == group }) else {
            return XCTFail("The folder is in the document")
        }
        for frame in [-3, 0, 7, 400] {
            XCTAssertEqual(folder.resolvedEffect(atFrame: frame), folder.effect,
                           "frame \(frame): folder effects are not animatable, and that is KEYFRAMES §9 question 3, unruled")
        }
    }
}
