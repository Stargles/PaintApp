import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for the transform channel against a real document — KEYFRAMES.md stage 5.
///
/// Three things are pinned here and the order is by how expensive each is to discover later.
///
/// 1. **§4.5's caching trap, in its exact form.** The instant one `Cel` can produce two pictures, the
///    flatten memo's key stops being an identity — and the failure is invisible in the obvious place,
///    because `SandwichKey` compares the whole node tree and rebuilds the composite dutifully *from
///    the stale flatten underneath*. `testTwoFramesOfOnePosedCelAreTwoCacheEntries` and
///    `testAPosedFrameIsNotServedFromTheRestingFlatten` are the two halves;
///    `testAnUnchangedPosedFrameIsStillServedFromTheMemo` is what stops either passing for the wrong
///    reason, since a key that is unique per call would satisfy both and cache nothing.
/// 2. **Ink goes through `mapping(_:throughStretch:)`.** §8 is emphatic that there are two per-frame
///    mapped-stroke paths and only one carries LASSO_MOVE.md §5.17's width rule. Getting it wrong is
///    invisible until someone looks at ink weight, so the weight is what is asserted.
/// 3. **Nothing changes for a document nobody has keyframed.** The routing rule's `.storedValue` arm
///    is the safety property the whole feature is shaped around, and it is asserted directly rather
///    than assumed.
/// The class is `@MainActor` because `ProjectStore.save`/`load` are, and the round-trip test below
/// needs `wait(for:)` to spin the run loop so the completion handler's main-actor hop can run.
@MainActor
final class TransformChannelLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }

    override func setUp() {
        super.setUp()
        PixelOps.clearRasterizeCache()
    }

    // MARK: - Fixtures

    private func stroke(_ points: [CGPoint], size strokeSize: CGFloat = 6) -> VectorStroke {
        VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: strokeSize, opacity: 1,
                     samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) })
    }

    /// A manager with a vector layer (index 1) holding one cel over frames 0..<12, with a short bar
    /// drawn near the left edge.
    private func fixture() -> (manager: CanvasManager, layerID: UUID, celID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 12, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[1].cels = [cel]
        return (manager, manager.layers[1].id, cel.id)
    }

    private var box: CGRect { CGRect(x: 4, y: 6, width: 16, height: 8) }

    private func slide(_ dx: CGFloat) -> PoseQuad {
        PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: dx, y: 0))
    }

    /// Two keys on the whole-cel channel: resting at frame 0, slid `dx` right at frame 8.
    private func animate(_ manager: CanvasManager, layerID: UUID, celID: UUID, dx: CGFloat = 24) {
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 0, pose: PoseQuad(restingIn: box))
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 8, pose: slide(dx))
    }

    private func bytes(_ image: UIImage) -> Data { image.pngData() ?? Data() }

    private func inkBounds(_ image: UIImage) -> CGRect? { PixelOps.opaqueContentBounds(image) }

    // MARK: - The derivation

    /// A cel with no pose channel derives nothing, which is what makes this free in every document
    /// that has never been keyframed — one `isEmpty` on the path every rasterize of every cel takes.
    func testACelWithNoPoseChannelDerivesNothing() {
        let (manager, _, _) = fixture()
        XCTAssertNil(manager.derivedCelContent(for: manager.layers[1].cels[0], atFrame: 4))
    }

    /// And a channel whose pose *resolves to resting* at this frame derives nothing either — the
    /// distinction `TransformTrack.mapping` draws, reached from the document side. Frame 0 holds the
    /// rest pose, so it costs what an unkeyframed document costs.
    func testARestingFrameOfAnAnimatedCelStillDerivesNothing() {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        XCTAssertNil(manager.derivedCelContent(for: manager.layers[1].cels[0], atFrame: 0))
        XCTAssertNotNil(manager.derivedCelContent(for: manager.layers[1].cels[0], atFrame: 4))
    }

    /// **§4.5's trap.** The posed frame's pixels must not be the resting cel's pixels, and the flatten
    /// memo must not hand back the resting ones for the posed frame.
    func testAPosedFrameIsNotServedFromTheRestingFlatten() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let cel = manager.layers[1].cels[0]

        // Warm the memo with the resting frame first, which is the order that produces the defect.
        let resting = PixelOps.rasterize(cel: cel, canvasSize: size,
                                         derived: manager.derivedCelContent(for: cel, atFrame: 0))
        let posed = PixelOps.rasterize(cel: cel, canvasSize: size,
                                       derived: manager.derivedCelContent(for: cel, atFrame: 8))
        let restBounds = try XCTUnwrap(inkBounds(resting))
        let posedBounds = try XCTUnwrap(inkBounds(posed))
        XCTAssertEqual(posedBounds.minX - restBounds.minX, 24, accuracy: 1.5,
                       "The posed frame shows the drawing 24pt to the right of where the cel stores it")
    }

    /// **§4.5's trap at the pixel level, between two frames that are *both* posed.**
    ///
    /// The test above it compares a resting frame against a posed one, and those two differ in
    /// whether a derivation exists at all — so it survives a poisoned identity and pins "a posed frame
    /// shows posed pixels" rather than the cache key. **That was found by mutation, not by reading**:
    /// dropping the resolved maps from `PosedCelIdentity` left it green. Two posed frames whose maps
    /// differ is the case where the key is the only thing standing between the artist and the wrong
    /// picture, and this is that case in pixels.
    func testTwoDifferentlyPosedFramesDoNotShareOneFlatten() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let cel = manager.layers[1].cels[0]

        let early = PixelOps.rasterize(cel: cel, canvasSize: size,
                                       derived: manager.derivedCelContent(for: cel, atFrame: 2))
        let late = PixelOps.rasterize(cel: cel, canvasSize: size,
                                      derived: manager.derivedCelContent(for: cel, atFrame: 8))
        let earlyBounds = try XCTUnwrap(inkBounds(early))
        let lateBounds = try XCTUnwrap(inkBounds(late))
        XCTAssertGreaterThan(lateBounds.minX - earlyBounds.minX, 12,
                             "Frame 8 is 24pt along a linear span and frame 2 is 6pt — one flatten cannot be both")
    }

    /// **The mutation target, and the field it names is `maps`.** Two frames of one cel whose poses
    /// differ are two cache entries; delete the resolved maps from `PosedCelIdentity` and these two
    /// become one, at which point the test above serves the resting pixels for the posed frame.
    ///
    /// **This is deliberately not a *frame* field, and that is stage 5's one departure from §8's
    /// prescription** — see `CanvasManager.posedCelContent` for the argument. The pin has to be on
    /// what the render reads, and what it reads is the map.
    func testTwoFramesOfOnePosedCelAreTwoCacheEntries() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let cel = manager.layers[1].cels[0]
        let a = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: 4)?.identity)
        let b = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: 8)?.identity)
        XCTAssertNotEqual(a, b)

        XCTAssertNotEqual(LayerContentVersion(cel: cel, derived: a),
                          LayerContentVersion(cel: cel, derived: b),
                          "The other key §4.5 names — MaskResolver's — has to move too")
    }

    /// **The other direction, and it is what stops the test above passing for the wrong reason.** Two
    /// frames a *held* pose covers are the same picture and must share one entry: a key that carried
    /// the frame outright would mint a second entry for every frame of a hold, which is the exact cost
    /// §8's parenthesis warns about for interpolation's identity, arriving by the other door.
    func testAnUnchangedPosedFrameIsStillServedFromTheMemo() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let cel = manager.layers[1].cels[0]
        // Frames 9 and 11 are both past the last key, so the constant hold gives them one pose.
        let a = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: 9)?.identity)
        let b = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: 11)?.identity)
        XCTAssertEqual(a, b, "One pose is one picture, however many frames hold it")
    }

    /// Editing the curve at a fixed frame moves the identity — the half a frame field could never
    /// have covered, and the reason the resolved map is what the key carries.
    func testMovingAKeyMovesTheIdentityAtAFrameThatDidNotChange() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let before = try XCTUnwrap(manager.derivedCelContent(for: manager.layers[1].cels[0],
                                                             atFrame: 4)?.identity)
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 8, pose: slide(40))
        let after = try XCTUnwrap(manager.derivedCelContent(for: manager.layers[1].cels[0],
                                                            atFrame: 4)?.identity)
        XCTAssertNotEqual(before, after)
    }

    /// §2.18: a derived in-between carries no object channels. A cel with a recipe takes the
    /// interpolation arm and its pose tracks are ignored — refused at the reader as well as at the
    /// writer, so the app cannot reach storage that renders nothing.
    func testAnInterpolatedCelIgnoresAPoseChannel() {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        manager.layers[1].cels[0].interpolation = InterpolationRecipe(mode: .reproject)
        // Not nil, because the recipe derives; the assertion is that the *pose* is not what it is.
        XCTAssertEqual(manager.transformWrite(layerID: layerID, celID: celID, channel: .cel,
                                              atFrame: 4), .storedValue,
                       "The writer refuses an object channel on an in-between")
    }

    // MARK: - The ink

    /// **§8's width rule, which is the whole reason `mapping(_:throughStretch:)` is the arm.** A 4:1
    /// stretch scales ink by `sqrt(|det|)` — 2 — not by 4 and not by 1.
    /// `InterpolationEvaluator.warped` would have scaled by `thicknessFade` alone, which is right for
    /// a lattice warp and wrong for a pose, and nothing about the picture would say so.
    func testPosedInkTakesTheAreaRootOfTheMapAsItsWidth() throws {
        let elements: [VectorElement] = [.stroke(stroke([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
                                                        size: 8))]
        let stretch = CGAffineTransform(scaleX: 4, y: 1)
        let posed = CanvasManager.posed(elements, through: [(.cel, stretch)])
        let after = try XCTUnwrap(posed.first?.stroke)
        XCTAssertEqual(after.size, 8 * 2, accuracy: 1e-9, "sqrt(|det|) of a 4:1 stretch is 2")
        XCTAssertEqual(after.samples.last?.point.x ?? 0, 40, accuracy: 1e-6, "and the spine follows the map")
    }

    /// A pure move must not change ink weight at all — `sqrt(|det|)` is 1, and
    /// `mapping(_:throughStretch:)` guards on `k != 1` so the stored number stays bit-identical
    /// rather than multiplied by a 1.0 that rounding might not be.
    func testAPureMoveLeavesInkWeightBitIdentical() throws {
        let elements: [VectorElement] = [.stroke(stroke([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
                                                        size: 7.3))]
        let posed = CanvasManager.posed(elements, through:
            [(.cel, CGAffineTransform(translationX: 5, y: -2))])
        XCTAssertEqual(try XCTUnwrap(posed.first?.stroke).size, 7.3)
    }

    /// **A group channel carries its members and nothing else**, which is the whole of §2.11's
    /// membership rule reaching the renderer.
    func testAGroupChannelMovesOnlyItsMembers() throws {
        let group = UUID()
        let tagged = VectorElement.stroke(stroke([CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0)]))
            .taggedForAnimation(group)
        let untagged = VectorElement.stroke(stroke([CGPoint(x: 0, y: 8), CGPoint(x: 4, y: 8)]))
        let posed = CanvasManager.posed([tagged, untagged],
                                        through: [(.group(group), CGAffineTransform(translationX: 10, y: 0))])
        XCTAssertEqual(try XCTUnwrap(posed[0].stroke).samples.first?.point.x, 10)
        XCTAssertEqual(try XCTUnwrap(posed[1].stroke).samples.first?.point.x, 0)
    }

    /// **Groups first, the cel channel last** — a character's arm swinging while the character walks.
    /// Affines do not commute, so the order has to be decided somewhere, and deciding it in
    /// `poseMappings` is what keeps it off Swift's per-process hash seed.
    func testAGroupUnderAnAnimatedCelIsCarriedByItsGroupAndThenByTheCel() throws {
        let group = UUID()
        let tracks: [String: TransformTrack] = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(box: box, mappedBy: .init(scaleX: 2, y: 2)))]),
            TransformChannelID.group(group).id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(box: box, mappedBy: .init(translationX: 3, y: 0)))])
        ]
        let mappings = CanvasManager.poseMappings(tracks, atCelLocalFrame: 0)
        XCTAssertEqual(mappings.count, 2)
        XCTAssertEqual(mappings.last?.0, .cel, "The cel channel is the outer transform")

        let member = VectorElement.stroke(stroke([CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0)]))
            .taggedForAnimation(group)
        let posed = CanvasManager.posed([member], through: mappings)
        // Translate by 3 and then scale by 2 is 8; scale first would be 5.
        XCTAssertEqual(try XCTUnwrap(posed[0].stroke).samples.first?.point.x ?? 0, 8, accuracy: 1e-9)
    }

    /// **Grain travels with the ink under this channel** — KEYFRAMES.md §2.16, delivered by stage 4's
    /// rest-space dab bake (§4.2's *"grain is the real one"*).
    ///
    /// ## This test asserted the artifact until stage 4, and its operands were a proxy
    ///
    /// It used to sample `grainAlphaMultiplier` at the stroke's own **samples**, at rest and posed,
    /// and require the two arrays to differ — with a note saying it was *"meant to go red when stage 4
    /// lands"*. **It did not go red, and could not have.** `grainAlphaMultiplier` is a function of
    /// canvas position, so it differs at two different positions under any construction whatever;
    /// asserting that is asserting the definition of a noise field, not the behaviour of the ink. And
    /// `posed` still maps a stroke's samples after stage 4 — it must, because §4.2 says
    /// `resolveSources` hands on a *posed display list* and every bounds and preview reader believes
    /// those points.
    ///
    /// What actually changed is one level down, and it is where the pixels are: the walk now happens
    /// in **rest space** and the pose maps only each finished dab, so the multiplier is read at the
    /// rest stamp point and folded into the dab's alpha before it reaches any `DabTarget`. So the
    /// right operands are the **dab alphas** across two poses of one stroke — which is exactly what
    /// `stampCircle` receives, and therefore exactly what the artist sees. That is the rewrite, and
    /// the lesson is CLAUDE.md's own: a green assertion is only as good as its two operands, and a
    /// *red* one is too.
    ///
    /// `RestSpaceDabBakeLogicTests` carries the 24-frame form and the measurement (24 distinct alpha
    /// sequences before, one after). This keeps the channel-level statement beside the channel.
    ///
    /// Only `.pencil` among the five built-ins enables grain, so this is the whole of the exposure;
    /// §4.2 names `.square`'s sub-lattice as the other baked-walk artifact.
    func testGrainTravelsWithTheInkUnderAPose() throws {
        let brush = BrushLibrary.pencil
        XCTAssertTrue(brush.grain.isEnabled, "Setup: the pencil is the one built-in that grains")

        let points = (0..<8).map { CGPoint(x: CGFloat($0) * 3, y: 10) }
        let elements: [VectorElement] = [.stroke(VectorStroke(
            id: UUID(), brush: brush,
            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
            size: 6, opacity: 1,
            samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) }))]

        /// The dabs one posed display list actually stamps — the walk `VectorCanvas.stamp` runs,
        /// reached through the same `restWalk` the renderer reads.
        func dabs(_ list: [VectorElement]) throws -> [BrushStamper.BakedDab] {
            let stroke = try XCTUnwrap(list.first?.stroke)
            let sink = BrushStamper.CollectingDabTarget()
            let walk = stroke.restWalk
            let target: DabTarget = walk.map { BrushStamper.PosedDabTarget(sink, pose: $0.pose) } ?? sink
            BrushStamper.stampStroke(
                into: target,
                samples: (walk?.samples ?? stroke.samples).map {
                    BrushStamper.Sample(point: $0.point, pressure: $0.pressure)
                },
                brush: stroke.brush, color: stroke.uiColor, brushSize: walk?.size ?? stroke.size,
                brushOpacity: stroke.opacity, seed: BrushStamper.seed(for: stroke.id))
            return sink.dabs
        }

        let rest = try dabs(elements)
        let near = try dabs(CanvasManager.posed(elements, through: [(.cel, .init(translationX: 17, y: 5))]))
        let far = try dabs(CanvasManager.posed(elements, through: [(.cel, .init(translationX: 41, y: -9))]))

        XCTAssertGreaterThan(Set(rest.map(\.alpha)).count, 3,
                             "Setup: the grain is varying dab to dab, or there is nothing to hold still")
        XCTAssertEqual(near.map(\.alpha), rest.map(\.alpha),
                       "the multiplier is baked at the rest stamp point, so it rides with the mark")
        XCTAssertEqual(far.map(\.alpha), rest.map(\.alpha))
        XCTAssertNotEqual(near.map(\.center), far.map(\.center),
                          "and the ink itself did move, or the equality above is vacuous")
    }

    // MARK: - §2.28's union

    /// A pose key is a keyframe. Both device reports behind §2.28 were the timeline and the model
    /// asking different questions, and a channel left out of this union would reproduce both.
    func testAPoseKeyIsAKeyframeOnTheLayerItsCelBelongsTo() throws {
        let (manager, layerID, celID) = fixture()
        manager.layers[1].cels[0].startFrame = 4
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        XCTAssertEqual(manager.keyframeFrames(of: target), [])

        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 2, pose: slide(9))
        XCTAssertEqual(manager.keyframeFrames(of: target), [6],
                       "Cel-local 2 on a cel starting at 4 is document frame 6")
        XCTAssertTrue(manager.keyframes(of: target).keyed.contains(6),
                      "A pose key has landed, so the marker draws filled rather than hollow")
    }

    // MARK: - Undo

    /// One pose key is one undo step, and undoing it takes the channel with it.
    func testAPoseKeyIsOneUndoStep() {
        let (manager, layerID, celID) = fixture()
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 4, pose: slide(12))
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks.count, 1)
        manager.undo()
        XCTAssertTrue(manager.layers[1].cels[0].transformTracks.isEmpty)
        manager.redo()
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks["cel"]?.keys.count, 1)
    }

    /// Clearing a keyframe clears the pose key on it, as part of the same step — both halves, because
    /// the artist asked for the keyframe to go and leaving the key behind would take the marker off
    /// the timeline and leave the drawing moving exactly as it did.
    func testRemovingAKeyframeTakesThePoseKeyWithIt() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 8])

        manager.removeKeyframe(target, atFrame: 8)
        XCTAssertEqual(manager.keyframeFrames(of: target), [0])
        manager.undo()
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 8], "One press brings both halves back")
    }

    // MARK: - Routing

    /// **The safety property.** On a document with no keyframes a Move is a Move: the route is
    /// `.storedValue`, nothing is written, and no animation group is minted.
    func testAMoveOnADocumentWithNoKeyframesWritesNoChannel() {
        let (manager, layerID, celID) = fixture()
        XCTAssertEqual(manager.transformWrite(layerID: layerID, celID: celID, channel: nil, atFrame: 4),
                       .storedValue)
        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel,
                                                restBox: box,
                                                map: CGAffineTransform(translationX: 9, y: 0),
                                                restElements: manager.layers[1].cels[0].vector?.elements ?? [],
                                                atFrame: 4)
        XCTAssertEqual(route, .storedValue)
        XCTAssertTrue(manager.layers[1].cels[0].transformTracks.isEmpty)
        XCTAssertTrue(manager.animationGroups.isEmpty)
    }

    /// §2.27's canonical story, in pose currency. A mark at 0, a Move at 8 (which bakes, and holds the
    /// pose that puts the drawing back where it was), then a mark at 8 — and the pair is an animation
    /// with keyframe A holding where it started.
    func testAMarkAMoveAndASecondMarkProduceAnAnimation() throws {
        let (manager, layerID, celID) = fixture()
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        manager.addKeyframe(target, atFrame: 0)

        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel,
                                                restBox: box,
                                                map: CGAffineTransform(translationX: 20, y: 0),
                                                restElements: [], atFrame: 8)
        XCTAssertEqual(route, .storedValueHoldingBaseline)
        XCTAssertEqual(manager.layers[1].cels[0].pendingPoseBaselines.count, 1,
                       "The previous value is held; nothing is keyed yet")
        XCTAssertTrue(manager.layers[1].cels[0].transformTracks.isEmpty)

        manager.addKeyframe(target, atFrame: 8)
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(track.keys.map(\.frame), [0, 8])
        XCTAssertTrue(track.isAnimated)
        XCTAssertTrue(manager.layers[1].cels[0].pendingPoseBaselines.isEmpty,
                      "The held value is discarded once it has been committed")
        // Keyframe A holds the drawing 20pt back from where the geometry now sits, and B holds it
        // where it is — the owner's *"A and B are assigned the two states of that one animation"*.
        XCTAssertEqual(track.keys[0].pose.corners.p0.x - box.minX, -20, accuracy: 1e-9)
        XCTAssertTrue(track.keys[1].pose.isIdentity)
    }

    /// **The Move refusal, and it is the in-between refusal wearing a second costume.** At a frame the
    /// cel is not resting at, the box would be measured on stored ink the canvas is not showing.
    func testMoveIsRefusedAtAFrameThePoseDoesNotRestAt() {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        manager.currentLayerIndex = 1
        XCTAssertTrue(manager.celPoseIsResting(layerIndex: 1, celIndex: 0, atFrame: 0))
        XCTAssertFalse(manager.celPoseIsResting(layerIndex: 1, celIndex: 0, atFrame: 6))

        manager.currentFrame = 6
        XCTAssertFalse(manager.beginVectorWholeCelMove(), "Refused where the box would be out of register")
        manager.currentFrame = 0
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "and allowed where it is in register")
        manager.cancelVectorFloat()
    }

    /// **§2.5's write-at-commit, driven through the real gesture rather than through the writer.**
    /// Lift, nudge, commit — and the key lands at the commit, not at the nudge.
    ///
    /// The `.key` arm is the one that takes the bake back: the cel holds one drawing in its rest
    /// position and the keys hold the poses, so the display list must come back to where it was while
    /// the pose records where the artist put it.
    func testACommittedMoveOnAnAnimatedCelWritesAPoseAndTakesTheBakeBack() throws {
        let (manager, layerID, celID) = fixture()
        manager.currentLayerIndex = 1
        manager.currentFrame = 0
        // One key at frame 0 holding the rest pose: a channel in force, resting where the box is.
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 0, pose: PoseQuad(restingIn: box))
        let restX = try XCTUnwrap(manager.layers[1].cels[0].vector?.elements.first?.stroke?
            .samples.first?.point.x)

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        var pose = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        pose.position.x += 15
        manager.nudgeVectorFloat(to: pose)
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks["cel"]?.keys.count, 1,
                       "A nudge writes no key — §2.5, and it is the ruling rather than a convenience")

        manager.commitVectorFloatIfNeeded()
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(track.keys.count, 1, "The key replaces the one on this frame")
        // **Against the pose's *own* box, which is the float's measured ink bounds rather than this
        // file's fixture rectangle.** The first draft compared to the fixture and read 14 for a 15pt
        // drag — the difference being `MoveBoxInk`'s half-a-stroke-width padding, which is exactly the
        // reason a pose stores the box it was measured against instead of assuming one.
        let key = track.keys[0].pose
        XCTAssertEqual(key.corners.p0.x - key.box.minX, 15, accuracy: 1e-6)

        let afterX = try XCTUnwrap(manager.layers[1].cels[0].vector?.elements.first?.stroke?
            .samples.first?.point.x)
        XCTAssertEqual(afterX, restX, accuracy: 1e-9,
                       "The bake is taken back: the cel stores one drawing, in its rest position")
    }

    // MARK: - Cel operations

    /// The pose whichever cel covers `frame` shows there, through the shipped accessors — so a test
    /// can ask "what does the document show at frame *n*" across an operation that replaces the cel
    /// the frame belonged to.
    private func shownDX(_ manager: CanvasManager, atFrame frame: Int) -> CGFloat? {
        guard let index = manager.activeCelIndex(inLayer: 1, atFrame: frame) else { return nil }
        let cel = manager.layers[1].cels[index]
        guard let pose = manager.resolvedPose(layerID: manager.layers[1].id, celID: cel.id,
                                              channel: .cel, atFrame: frame) else { return nil }
        return pose.corners.p0.x - pose.box.minX
    }

    /// A `.linear` whole-cel channel over the fixture's twelve frames, written onto the cel's own
    /// storage — the field `posedCelContent` and `splitCel` both read. Linear so that "every frame
    /// shows what it showed" is exact rather than approximate across a cut.
    private func animateLinearly(_ manager: CanvasManager, dx travel: CGFloat = 120) {
        manager.layers[1].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 12, pose: slide(travel), interpolation: .linear)])
        ]
    }

    /// **`splitCel` carries the animation across the cut** — KEYFRAMES.md §3.1's rule, from the
    /// document side.
    ///
    /// **The assertion is what the artist sees at every frame, not the key lists.** §3.1 asks for the
    /// value to be *continuous across the cut*, so the operand is the pose each frame resolves to
    /// before and after — read through `activeCelIndex` and `resolvedPose`, because the second half is
    /// a cel with an id that did not exist a moment ago.
    ///
    /// Watched failing with `splitCel`'s two `transformTracks:` lines removed: **twelve** of these
    /// twelve frames come back nil, because the memberwise `Cel(...)` defaults the field to `[:]` and
    /// the surviving half is assigned `[:]` as well.
    func testSplittingAnAnimatedCelKeepsEveryFrameShowingWhatItShowed() {
        let (manager, _, _) = fixture()
        animateLinearly(manager)
        let before = (0..<12).map { shownDX(manager, atFrame: $0) }
        XCTAssertEqual(before.compactMap { $0 }.count, 12, "Setup: every frame is posed to begin with")

        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 5)
        XCTAssertEqual(manager.layers[1].cels.count, 2)
        XCTAssertFalse(manager.layers[1].cels[0].transformTracks.isEmpty, "the left half keeps its channel")
        XCTAssertFalse(manager.layers[1].cels[1].transformTracks.isEmpty, "and so does the right")

        for frame in 0..<12 {
            let now = shownDX(manager, atFrame: frame)
            XCTAssertNotNil(now, "frame \(frame) still has a pose")
            XCTAssertEqual(now!, before[frame]!, accuracy: 1e-9,
                           "frame \(frame) shows the pose it showed before the cut")
        }
    }

    /// Undoing the split gives the animation back as one channel on one cel, since the split is one
    /// structural step and the tracks ride inside it.
    func testUndoingASplitRestoresTheOneChannel() {
        let (manager, _, _) = fixture()
        animateLinearly(manager)
        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 5)
        manager.undo()
        XCTAssertEqual(manager.layers[1].cels.count, 1)
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks["cel"]?.keys.map(\.frame), [0, 12])
    }

    /// **`duplicateCel` copies the animation with the drawing.** `Cel.transformTracks`' own doc
    /// comment claimed the channel *"rides the cel through move, split, duplicate and paste for
    /// free"*; three of those four verbs build a fresh `Cel`, and a memberwise initialiser defaults an
    /// unmentioned field to `[:]`, so the claim was false and the animation was silently deleted.
    ///
    /// The held baseline travels too — §2.27's state *between* keyframe A and keyframe B, which a copy
    /// made in that gap must not drop any more than a save may.
    ///
    /// Watched failing with `duplicateCel`'s two arguments removed: `transformTracks` on the copy is
    /// empty and this reads `nil` against `[0, 12]`.
    func testDuplicatingAnAnimatedCelCopiesItsChannelAndItsHeldBaseline() throws {
        let (manager, layerID, celID) = fixture()
        animateLinearly(manager)
        manager.layers[1].cels[0].frameCount = 6
        manager.holdPoseBaseline(layerID: layerID, celID: celID, channel: .cel, pose: slide(-7))

        manager.duplicateCel(layerIndex: 1, celIndex: 0)
        XCTAssertEqual(manager.layers[1].cels.count, 2)
        let copy = manager.layers[1].cels[1]
        XCTAssertEqual(copy.startFrame, 6)
        XCTAssertEqual(copy.transformTracks["cel"]?.keys.map(\.frame), [0, 12],
                       "keys are cel-local, so they need no rebasing and none is done")
        XCTAssertEqual(copy.pendingPoseBaselines["cel"], slide(-7))
        XCTAssertNotEqual(copy.id, celID, "and it really is a different cel")
    }

    /// The fourth verb. `CopiedCel` had nowhere to put a pose channel, so copy-and-paste lost it by
    /// the same door duplicate did.
    func testCopyingAndPastingACelCarriesItsChannel() throws {
        let (manager, layerID, celID) = fixture()
        animateLinearly(manager)
        manager.layers[1].cels[0].frameCount = 6
        manager.holdPoseBaseline(layerID: layerID, celID: celID, channel: .cel, pose: slide(-3))

        manager.copyCel(layerIndex: 1, celIndex: 0)
        XCTAssertTrue(manager.pasteCel(layerIndex: 1, startFrame: 20))
        let pasted = try XCTUnwrap(manager.layers[1].cels.first { $0.startFrame == 20 })
        XCTAssertEqual(pasted.transformTracks["cel"]?.keys.map(\.frame), [0, 12])
        XCTAssertEqual(pasted.pendingPoseBaselines["cel"], slide(-3))
    }

    // MARK: - The held baseline and undo

    /// **One Move is one press of Undo, and the held pose goes back with the geometry.**
    ///
    /// `holdPoseBaseline` writes a **persisted** field (§3.5) and used to record nothing, on the
    /// argument that *"the bake it rides beside is already a step that snapshots the cel"*. The bake
    /// beside it is `registerVectorFloatNudgeUndo`, which restores `vector.elements`,
    /// `float.frame.*` and `selection` — and nothing on the `Cel`. So the artist could Move between
    /// two marks, press Undo, watch the drawing come back, and keep a baseline describing a move that
    /// no longer existed; the next keyframe press then seeded an animation out of it.
    ///
    /// Driven through the real gesture — lift, nudge, commit — because the defect is precisely that
    /// the baseline is written *after* the nudge's own step is on the stack, and a test that called
    /// `holdPoseBaseline` with an empty history could not see it.
    ///
    /// Watched failing with `holdPoseBaseline`'s `history.extendLast` block removed: the geometry
    /// returns and `pendingPoseBaselines` still holds one entry.
    func testUndoingAMoveTakesTheHeldPoseBackWithTheGeometry() throws {
        let (manager, layerID, celID) = fixture()
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        manager.currentLayerIndex = 1
        // A mark at frame 0 and the playhead at 8: one keyframe, not standing on it, which is the
        // `.storedValueHoldingBaseline` arm.
        manager.currentFrame = 0
        manager.addKeyframe(target, atFrame: 0)
        manager.currentFrame = 8

        let restX = try XCTUnwrap(manager.layers[1].cels[0].vector?.elements.first?.stroke?
            .samples.first?.point.x)
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        var pose = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        pose.position.x += 15
        manager.nudgeVectorFloat(to: pose)
        manager.commitVectorFloatIfNeeded()

        XCTAssertEqual(manager.layers[1].cels[0].pendingPoseBaselines.count, 1,
                       "Setup: the Move held a baseline, or there is nothing here to take back")
        XCTAssertTrue(manager.layers[1].cels[0].transformTracks.isEmpty, "and keyed nothing yet")

        manager.undo()
        let afterX = try XCTUnwrap(manager.layers[1].cels[0].vector?.elements.first?.stroke?
            .samples.first?.point.x)
        XCTAssertEqual(afterX, restX, accuracy: 1e-9, "one press gives the geometry back")
        XCTAssertTrue(manager.layers[1].cels[0].pendingPoseBaselines.isEmpty,
                      "and the same press gives the held pose back — a phantom baseline here seeds an "
                      + "animation out of a move the artist undid")

        manager.redo()
        XCTAssertEqual(manager.layers[1].cels[0].pendingPoseBaselines.count, 1,
                       "and redo puts both halves back, or the fold is one-directional")
    }

    /// The other half of "one press": the fold must not cost a *second* one. A Move that holds a
    /// baseline is still one nudge and therefore one step on the stack.
    func testHoldingAPoseBaselineCostsNoUndoStepOfItsOwn() throws {
        let (manager, _, _) = fixture()
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        manager.currentLayerIndex = 1
        manager.currentFrame = 0
        manager.addKeyframe(target, atFrame: 0)
        manager.currentFrame = 8
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        var pose = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        pose.position.x += 15
        manager.nudgeVectorFloat(to: pose)
        manager.commitVectorFloatIfNeeded()
        XCTAssertEqual(manager.history.undoStack.count, 1,
                       "one nudge, one step — LASSO_MOVE.md §5.5")
    }

    // MARK: - §2.28's union, from the writers' side

    /// **A pose key is a neighbour for the seed arm**, which is device report 2 of §2.28 in pose
    /// currency: *"I have 3 keyframes and only slider A is being controlled. I go to keyframe 3 and
    /// modify slider B. It starts from keyframe 1 to 3, skipping 2."*
    ///
    /// `addKeyframe` took its neighbour list from the **two-argument** `keyframes(marks:tracks:)`,
    /// whose `poseFrames` defaulted to empty, while `keyframes(of:)` passed them — two spellings of
    /// the list §2.28 rules must have exactly one. Here the pose key at frame 4 is the *only* other
    /// keyframe, so the blind list finds no neighbour at all and the baseline is discarded with the
    /// animation it was holding.
    ///
    /// Watched failing with `addKeyframe`'s `placed` back on the static two-argument form: the group
    /// channel comes out with one key at frame 8, `isAnimated` false, and the drawing's old position
    /// nowhere in the document.
    func testAddingAKeyframeSeedsAHeldPoseOntoANeighbourThatIsOnlyAPoseKey() throws {
        let (manager, layerID, celID) = fixture()
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        let group = UUID()

        // The whole-cel channel is animated across frames 0 and 4 — keys placed by moving, which
        // §2.26 records as a curve and no mark, so `keyframeMarks` is empty.
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 0, pose: PoseQuad(restingIn: box))
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 4, pose: slide(30))
        XCTAssertEqual(manager.keyframeState(of: target).marks, [],
                       "Setup: frames 0 and 4 are keyframes by key, not by mark")
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 4])

        // A second channel holds a pose: the artist moved a group at frame 8 and has not pressed the
        // keyframe button yet.
        manager.holdPoseBaseline(layerID: layerID, celID: celID, channel: .group(group),
                                 pose: slide(-18))

        manager.addKeyframe(target, atFrame: 8)
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["group.\(group.uuidString)"])
        XCTAssertEqual(track.keys.map(\.frame), [4, 8],
                       "The held pose lands on frame 4 — the nearest keyframe below, which is a pose key")
        XCTAssertTrue(track.isAnimated)
        XCTAssertEqual(track.keys[0].pose, slide(-18), "keyframe A holds where the drawing was")
        XCTAssertTrue(track.keys[1].pose.isIdentity, "and B holds where it is now")
        XCTAssertTrue(manager.layers[1].cels[0].pendingPoseBaselines.isEmpty)
    }

    // MARK: - Persistence

    /// §3.5's track sidecar, end to end. A pose channel and a held baseline both have to survive a
    /// save — the baseline especially, because it is the state *between* keyframe A and keyframe B and
    /// that gap is exactly what a save can land in.
    func testPoseChannelsAndHeldBaselinesSurviveASaveAndReload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("transform-channel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: root)
        }

        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        manager.holdPoseBaseline(layerID: layerID, celID: celID, channel: .cel, pose: slide(-7))
        let group = AnimationGroup(displayName: "Arm",
                                   tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.animationGroups = [group]

        let url = root.appendingPathComponent("round-trip.paintproj", isDirectory: true)
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)

        XCTAssertTrue(ProjectBackupManager.validateProject(at: url),
                      "The validator has to know about the animation sidecar it now names (§3.5)")
        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let cel = try XCTUnwrap(reloaded.layers.first { $0.id == layerID }?.cels.first)
        XCTAssertEqual(cel.transformTracks["cel"],
                       manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(cel.pendingPoseBaselines["cel"], slide(-7))
        XCTAssertEqual(reloaded.animationGroups, [group])
    }

    // MARK: - What the live canvas shows

    /// **The live canvas showed a posed cel its *resting* ink, and this is the seam that says so.**
    ///
    /// `CanvasView.Coordinator.updateInterpolationPreviews` is the only call site in the app that
    /// pushes a derived image onto the live `strokeView`, and it decided which cels get one by
    /// asking `cel.interpolation != nil` — a test for *one* of the two derivation sources. A cel
    /// animated purely by a transform key took the no-recipe exit, so this file's whole feature was
    /// invisible while scrubbing even though every export of the same frames moved: the bake path
    /// (`leafSnapshots`) asks `derivedCelContent`, and the two paths disagreed with nothing between
    /// them. `CanvasView.swift` is not in this target, so the decision moved to `livePreview` where
    /// it can be asserted; the view is a `switch` over these three cases and nothing else.
    ///
    /// The assertion is on the **picture**, not on the case label: `.derived` carrying the resting
    /// image would satisfy a label check and is exactly the failure being pinned.
    func testTheLiveCanvasShowsAPoseOnlyCelItsPosedPicture() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let cel = manager.layers[1].cels[0]
        XCTAssertNil(cel.interpolation, "The premise: this cel is animated by a pose and nothing else")

        guard case .derived(let derived) = manager.livePreview(forCel: cel, atFrame: 8) else {
            return XCTFail("A pose-only cel has to reach the live canvas as a derived picture. "
                           + "Anything else is the canvas drawing the cel's resting ink at every "
                           + "frame of a move the export animates.")
        }
        let posed = try XCTUnwrap(derived.render(.full))
        let resting = try XCTUnwrap(cel.vector?.render(quality: .full))
        let posedBounds = try XCTUnwrap(inkBounds(posed))
        let restingBounds = try XCTUnwrap(inkBounds(resting))
        XCTAssertEqual(posedBounds.minX - restingBounds.minX, 24, accuracy: 1.5,
                       "Frame 8 holds the slid key, so the live picture is the drawing 24pt right "
                       + "of where the cel stores it")
    }

    /// The other direction, and it is what stops the test above passing for the wrong reason: an
    /// ordinary cel must still leave the slot to the tinted motion-group overlay, which shares it.
    /// "Always derive" would satisfy the test above and blank the tint.
    func testAnOrdinaryCelLeavesTheLiveSlotToTheMotionGroupTint() {
        let (manager, _, _) = fixture()
        guard case .motionGroupTint = manager.livePreview(forCel: manager.layers[1].cels[0],
                                                          atFrame: 4) else {
            return XCTFail("A cel with neither a recipe nor a pose derives nothing, and the same "
                           + "seam carries the motion-group tint for it")
        }
    }

    /// **The property the old recipe-first guard was written to protect, kept and now pinned.** A
    /// cel that *has* a recipe and derives nothing — here because the document has no canvas size —
    /// is a cel with nothing to *render*, not a cel with nothing to *derive*, so it clears the slot
    /// rather than being handed to the tint arm. Asking the derivation first only works because
    /// this case is sorted out afterwards.
    func testACelWhoseRecipeDerivesNothingClearsTheSlotRatherThanTintingIt() {
        let (manager, layerID, celID) = fixture()
        manager.layers[1].cels[0].interpolation =
            InterpolationRecipe(references: [InterpolationReference(layerID: layerID, celID: celID)],
                                t: 0.5)
        manager.canvasSize = nil
        guard case .cleared = manager.livePreview(forCel: manager.layers[1].cels[0], atFrame: 4) else {
            return XCTFail("A recipe that derives nothing must not reach the motion-group tint arm")
        }
    }
}
