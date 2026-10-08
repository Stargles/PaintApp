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
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: strokeSize, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
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

    /// Two keys on the whole-cel channel: resting at frame 0, slid `dx` right at frame 8 — X's curve.
    private func animate(_ manager: CanvasManager, layerID: UUID, celID: UUID, dx: CGFloat = 24) {
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                   CanvasFixture.poseTrack(box: box, [(0, PoseQuad(restingIn: box)),
                                                                      (8, slide(dx))]))
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
        animate(manager, layerID: layerID, celID: celID, dx: 40)
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
        let posed = CanvasManager.posed(elements, through: [(.cel, PoseMap(stretch))])
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
            [(.cel, PoseMap(CGAffineTransform(translationX: 5, y: -2)))])
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
                                        through: [(.group(group), PoseMap(CGAffineTransform(translationX: 10, y: 0)))])
        XCTAssertEqual(try XCTUnwrap(posed[0].stroke).samples.first?.point.x, 10)
        XCTAssertEqual(try XCTUnwrap(posed[1].stroke).samples.first?.point.x, 0)
    }

    /// **Groups first, the cel channel last** — a character's arm swinging while the character walks.
    /// Affines do not commute, so the order has to be decided somewhere, and deciding it in
    /// `poseMappings` is what keeps it off Swift's per-process hash seed.
    func testAGroupUnderAnAnimatedCelIsCarriedByItsGroupAndThenByTheCel() throws {
        let group = UUID()
        let tracks: [String: TransformTrack] = [
            TransformChannelID.cel.id: CanvasFixture.poseTrack(box: box, [
                (0, PoseQuad(box: box, mappedBy: .init(scaleX: 2, y: 2)))]),
            TransformChannelID.group(group).id: CanvasFixture.poseTrack(box: box, [
                (0, PoseQuad(box: box, mappedBy: .init(translationX: 3, y: 0)))])
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

    // MARK: - §2.28's union

    /// A pose key is a keyframe. Both device reports behind §2.28 were the timeline and the model
    /// asking different questions, and a channel left out of this union would reproduce both.
    func testAPoseKeyIsAKeyframeOnTheLayerItsCelBelongsTo() throws {
        let (manager, layerID, celID) = fixture()
        manager.layers[1].cels[0].startFrame = 4
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        XCTAssertEqual(manager.keyframeFrames(of: target), [])

        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                   CanvasFixture.poseTrack(box: box, [(2, slide(9))]))
        XCTAssertEqual(manager.keyframeFrames(of: target), [6],
                       "Cel-local 2 on a cel starting at 4 is document frame 6")
        XCTAssertTrue(manager.keyedFrames(of: target).contains(6),
                      "…and it is a *keyed* frame, not a mark, which is what makes it a node's peer")
    }

    // MARK: - Undo

    /// One committed Move on two primed frames is one undo step, and undoing it takes the channel it
    /// created with it.
    func testAPoseCommitIsOneUndoStep() throws {
        let (manager, layerID, celID) = fixture()
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        manager.addKeys(target, atFrame: 0)
        manager.addKeys(target, atFrame: 4)
        XCTAssertEqual(manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel, restBox: box,
                                                   map: PoseMap(CGAffineTransform(translationX: 12, y: 0)),
                                                   restElements: [], movedIDs: [], atFrame: 4), .seedAndKey)
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks.count, 1)
        manager.undo()
        XCTAssertTrue(manager.layers[1].cels[0].transformTracks.isEmpty)
        manager.redo()
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks["cel"]?.keyedFrames, [0, 4])
    }

    /// Clearing a keyframe clears the pose key on it, as part of the same step — both halves, because
    /// the artist asked for the keyframe to go and leaving the key behind would take the marker off
    /// the timeline and leave the drawing moving exactly as it did.
    func testRemovingAKeyframeTakesThePoseKeyWithIt() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 8])

        manager.removeKeys(target, atFrame: 8)
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
                                                map: PoseMap(CGAffineTransform(translationX: 9, y: 0)),
                                                restElements: manager.layers[1].cels[0].vector?.elements ?? [],
                                                movedIDs: [], atFrame: 4)
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
        manager.addKeys(target, atFrame: 0)

        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel,
                                                restBox: box,
                                                map: PoseMap(CGAffineTransform(translationX: 20, y: 0)),
                                                restElements: [], movedIDs: [], atFrame: 8)
        XCTAssertEqual(route, .storedValueHoldingBaseline)
        XCTAssertEqual(manager.layers[1].cels[0].pendingPoseBaselines.count, 1,
                       "The previous value is held; nothing is keyed yet")
        XCTAssertTrue(manager.layers[1].cels[0].transformTracks.isEmpty)

        manager.addKeys(target, atFrame: 8)
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(track.keyedFrames, [0, 8])
        XCTAssertTrue(track.isAnimated)
        XCTAssertTrue(manager.layers[1].cels[0].pendingPoseBaselines.isEmpty,
                      "The held value is discarded once it has been committed")
        // Keyframe A holds the drawing 20pt back from where the geometry now sits, and B holds it
        // where it is — the owner's *"A and B are assigned the two states of that one animation"* —
        // **on X alone**: TODO (139)'s *"only the keys of things that changed are added"*.
        XCTAssertEqual(Set(track.curves.keys), [.x], "a sideways Move keys X and nothing else")
        XCTAssertEqual(track.box.midX, box.midX + 20, accuracy: 1e-9,
                       "the channel is read against the box where the baked drawing now rests")
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 0)?.value ?? 0, Double(track.box.midX) - 20, accuracy: 1e-9)
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 8)?.value ?? 0, Double(track.box.midX), accuracy: 1e-9)
    }

    /// **TODO (139)'s ruling, whole: prime two frames, change something, and both get keys — on the
    /// components that changed and no others.** *"if you prime this in two frames and then change
    /// something, then it should put down two keys like the behaviour today, but only the things that
    /// changed"*. A drag right and down keys X and Y on both primed frames; Rotation, Scale, Skew and
    /// the two keystones take nothing.
    func testPrimingTwoFramesThenMovingKeysOnlyTheChangedComponentsOnBoth() throws {
        let (manager, layerID, celID) = fixture()
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        manager.addKeys(target, atFrame: 0)
        manager.addKeys(target, atFrame: 6)
        XCTAssertEqual(manager.layers[1].keyframeMarks, [0, 6], "PREMISE: two primed frames, nothing keyed")

        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel, restBox: box,
                                                map: PoseMap(CGAffineTransform(translationX: 20, y: 7)),
                                                restElements: [], movedIDs: [], atFrame: 6)
        XCTAssertEqual(route, .seedAndKey, "standing on a primed frame with another primed: two keys")
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(Set(track.curves.keys), [.x, .y], "only the things that changed")
        XCTAssertEqual(track.curve(.x)?.keys.map(\.frame), [0, 6])
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 0)?.value ?? 0, Double(box.midX), accuracy: 1e-9,
                       "the primed frame before holds where the drawing was")
        XCTAssertEqual(track.curve(.y)?.key(atFrame: 0)?.value ?? 0, Double(box.midY), accuracy: 1e-9)
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 6)?.value ?? 0, Double(box.midX) + 20, accuracy: 1e-9,
                       "and the frame the Move was made on holds where it is now")
        XCTAssertTrue(manager.layers[1].keyframeMarks.isEmpty, "both marks are keyed now, so both marks went")
    }

    /// **Add Keys on a frame of an animated drawing primes it and keys nothing; a Move made past it
    /// keys only what it changed, and holds that on the primed frame** — TODO (139): the press used to
    /// key every animated component on the frame it marked, which put keys on components nobody
    /// touched. X keyed 0 and 8, frame 4 primed, a slide right at 6: X takes its own value at 4 and the
    /// new one at 6, and no other component takes anything.
    func testAddKeysOnAnAnimatedDrawingKeysNothingAndTheNextMoveHoldsOnlyWhatItChangesThere() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)   // X keyed at 0 and 8
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        let before = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        let shownAt4 = before.values(atTime: 4, base: before.restValues).x

        XCTAssertTrue(manager.addKeys(target, atFrame: 4), "the press primes frame 4")
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks["cel"], before, "…and keys nothing")
        XCTAssertEqual(manager.placedKeys(of: target), PlacedKeys(frames: [0, 4, 8], primed: [4]))

        let current = manager.resolvedPoseMap(layerID: layerID, celID: celID, channel: .cel, atFrame: 6)
        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel, restBox: box,
                                                map: current.concatenating(PoseMap(CGAffineTransform(
                                                    translationX: 10, y: 0))),
                                                restElements: [], movedIDs: [], atFrame: 6)
        XCTAssertEqual(route, .key)
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(Set(track.curves.keys), [.x], "a slide keys X and nothing else")
        XCTAssertEqual(track.curve(.x)?.keys.map(\.frame), [0, 4, 6, 8])
        XCTAssertEqual(track.values(atTime: 4, base: track.restValues).x, shownAt4, accuracy: 1e-9,
                       "the primed frame keeps what it showed")
        XCTAssertEqual(manager.placedKeys(of: target).primed, [], "4 is a key now, and draws as one")
    }

    /// **A turn on a channel that already keys X keys Rotation alone** — and seeds it, so the frames
    /// before the turn keep showing no turn. The auto-key arm keys a changed component that already
    /// has a curve at the playhead; one that has none is seeded onto the keyframe below, which is what
    /// a whole-pose key did for that component implicitly.
    func testATurnOnAKeyedChannelKeysRotationAloneAndSeedsItOntoTheKeyframeBefore() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)   // X keyed at 0 and 8
        let current = manager.resolvedPoseMap(layerID: layerID, celID: celID, channel: .cel, atFrame: 10)
        let centre = try XCTUnwrap(current.applied(to: CGPoint(x: box.midX, y: box.midY)))
        let turn = CGAffineTransform(translationX: -centre.x, y: -centre.y)
            .concatenating(CGAffineTransform(rotationAngle: .pi / 6))
            .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))
        let keyed = current.concatenating(PoseMap(turn))

        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel, restBox: box,
                                                map: keyed, restElements: [], movedIDs: [], atFrame: 10)
        XCTAssertEqual(route, .key)
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(Set(track.curves.keys), [.x, .rotation], "the turn keyed Rotation and touched nothing else")
        XCTAssertEqual(track.curve(.x)?.keys.map(\.frame), [0, 8], "X's keys are where they were")
        XCTAssertEqual(track.curve(.rotation)?.keys.map(\.frame), [8, 10], "Rotation seeded onto 8, keyed at 10")
        XCTAssertEqual(track.curve(.rotation)?.key(atFrame: 10)?.value ?? 0, 30, accuracy: 1e-9)
        XCTAssertEqual(track.values(atTime: 4, base: track.restValues).rotation, 0,
                       "so frame 4 still shows no turn")
    }

    /// **After a slide has created the channel, a turn about the drawing's own centre keys Rotation
    /// alone** — the cold-start sequence `KeysUITests` drives, in the model: the slide's bake moves the
    /// stored drawing, so the channel is read against the box where it now rests, and the Move box
    /// raised at a later frame turns about that box's shown centre. A channel read against the
    /// pre-move box keyed X and Y beside Rotation here — found by driving it.
    func testAfterASlideCreatesTheChannelATurnAboutTheDrawingsCentreKeysRotationAlone() throws {
        let (manager, layerID, celID) = fixture()
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        manager.addKeys(target, atFrame: 0)
        manager.addKeys(target, atFrame: 5)
        XCTAssertEqual(manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel, restBox: box,
                                                   map: PoseMap(CGAffineTransform(translationX: 20, y: 7)),
                                                   restElements: [], movedIDs: [], atFrame: 5), .seedAndKey)
        // The drawing as stored now rests 20 right and 7 down; the Move box at frame 9 is around it as
        // shown, and turns about its centre.
        let stored = CGPoint(x: box.midX + 20, y: box.midY + 7)
        let current = manager.resolvedPoseMap(layerID: layerID, celID: celID, channel: .cel, atFrame: 9)
        let pivot = try XCTUnwrap(current.applied(to: stored))
        let turn = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: -.pi / 4))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        XCTAssertEqual(manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel, restBox: box,
                                                   map: current.concatenating(PoseMap(turn)),
                                                   restElements: [], movedIDs: [], atFrame: 9), .key)
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(track.curve(.x)?.keys.map(\.frame), [0, 5], "X keeps its two keys")
        XCTAssertEqual(track.curve(.y)?.keys.map(\.frame), [0, 5], "Y keeps its two keys")
        XCTAssertEqual(track.curve(.rotation)?.keys.map(\.frame), [5, 9], "and the turn is Rotation's alone")
    }

    /// **A Move is allowed at a frame the cel is not resting at**, which reverses what this test
    /// asserted until 2026-09-03.
    ///
    /// It used to read *"the Move refusal, and it is the in-between refusal wearing a second
    /// costume"*, and it pinned the owner's bug as a feature: at every in-between of an animated
    /// object `beginVectorWholeCelMove` returned false and the app said nothing. The refusal's own
    /// argument was that the box would be measured on stored ink the canvas is not showing, which was
    /// true — so the box is measured on the posed ink now, along with the loop and the gesture.
    /// `PosedLassoMoveLogicTests` is where that is pinned; this is the direct inverse of the assertion
    /// that stood here, kept in place so the reversal is visible in one diff.
    func testMoveIsAllowedAtAFrameThePoseDoesNotRestAt() {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        manager.currentLayerIndex = 1

        manager.currentFrame = 6
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "the in-between of a pose is a frame like any other")
        XCTAssertFalse(manager.vectorFloat?.parts[0].poses.isEmpty ?? true,
                       "and the float knows it is posed, which is what makes the box and the drag land")
        manager.cancelVectorFloat()
        manager.currentFrame = 0
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "as is a frame that rests")
        XCTAssertTrue(manager.vectorFloat?.parts[0].poses.isEmpty ?? false, "…carrying nothing, there")
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
        // One key at frame 0 holding X at rest: a channel in force, resting where the box is.
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                   TransformTrack(box: box, curves: [.x: AnimationCurve(keys: [
                                       .init(frame: 0, value: Double(box.midX))])]))
        let restX = try XCTUnwrap(manager.layers[1].cels[0].vector?.elements.first?.stroke?
            .samples.first?.point.x)

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        var pose = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        pose.position.x += 15
        manager.nudgeVectorFloat(to: pose)
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks["cel"]?.keyCount, 1,
                       "A nudge writes no key — §2.5, and it is the ruling rather than a convenience")

        manager.commitVectorFloatIfNeeded()
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        XCTAssertEqual(track.keyCount, 1, "The key replaces the one on this frame")
        XCTAssertEqual(Set(track.curves.keys), [.x], "…and the slide keyed no other component")
        // Read against the channel's own box, which the drag's map is decomposed in whatever box the
        // Move box measured: X is where that box's centre is now shown.
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 0)?.value ?? 0, Double(box.midX) + 15, accuracy: 1e-6)

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
        guard !cel.transformTracks.isEmpty else { return nil }
        let pose = CanvasFixture.resolvedPose(manager, layerID: manager.layers[1].id, celID: cel.id,
                                              atFrame: frame, box: box)
        return pose.corners.p0.x - pose.box.minX
    }

    /// A `.linear` whole-cel channel over the fixture's twelve frames, written onto the cel's own
    /// storage — the field `posedCelContent` and `splitCel` both read. Linear so that "every frame
    /// shows what it showed" is exact rather than approximate across a cut.
    ///
    /// **The last key is on frame 11, the cel's last, not on 12.** It was 12 until 2026-09-11 — one
    /// past a twelve-frame span, which §3.1 then allowed and TODO (62) now crops on any span change,
    /// so a split of that fixture came back with its right half's far key removed and every frame
    /// after the cut flat. `CelSpanCropLogicTests` pins that crop; this fixture stays inside the span
    /// so these tests stay about what they were about.
    private func animateLinearly(_ manager: CanvasManager, dx travel: CGFloat = 120,
                                 lastKeyAt lastKey: Int = 11) {
        manager.layers[1].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(box: box, curves: [.x: AnimationCurve(keys: [
                .init(frame: 0, value: Double(box.midX), interpolation: .linear),
                .init(frame: lastKey, value: Double(box.midX + travel), interpolation: .linear)])])
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
            guard let now = shownDX(manager, atFrame: frame), let was = before[frame] else {
                XCTFail("frame \(frame) lost its pose across the cut")
                continue
            }
            XCTAssertEqual(now, was, accuracy: 1e-9,
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
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks["cel"]?.keyedFrames, [0, 11])
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
        // Six frames and a key on the last of them. This fixture used to shorten the cel to 6 with
        // the key still at 12 — a key outside the span, which TODO (62) now crops on the copy — so
        // the last key sits inside the span to keep this test about the copy carrying the channel;
        // `CelSpanCropLogicTests` is where the clamped-copy crop is pinned.
        manager.layers[1].cels[0].frameCount = 6
        animateLinearly(manager, lastKeyAt: 5)
        manager.holdPoseBaseline(layerID: layerID, celID: celID, channel: .cel, pose: slide(-7))

        manager.duplicateCel(layerIndex: 1, celIndex: 0)
        XCTAssertEqual(manager.layers[1].cels.count, 2)
        let copy = manager.layers[1].cels[1]
        XCTAssertEqual(copy.startFrame, 6)
        XCTAssertEqual(copy.transformTracks["cel"]?.keyedFrames, [0, 5],
                       "keys are cel-local, so they need no rebasing and none is done")
        XCTAssertEqual(copy.pendingPoseBaselines["cel"], slide(-7))
        XCTAssertNotEqual(copy.id, celID, "and it really is a different cel")
    }

    /// The fourth verb. `CopiedCel` had nowhere to put a pose channel, so copy-and-paste lost it by
    /// the same door duplicate did.
    func testCopyingAndPastingACelCarriesItsChannel() throws {
        let (manager, layerID, celID) = fixture()
        // The last key inside the span, for the reason the duplicate test above gives.
        manager.layers[1].cels[0].frameCount = 6
        animateLinearly(manager, lastKeyAt: 5)
        manager.holdPoseBaseline(layerID: layerID, celID: celID, channel: .cel, pose: slide(-3))

        manager.copyCel(layerIndex: 1, celIndex: 0)
        XCTAssertTrue(manager.pasteCel(layerIndex: 1, startFrame: 20))
        let pasted = try XCTUnwrap(manager.layers[1].cels.first { $0.startFrame == 20 })
        XCTAssertEqual(pasted.transformTracks["cel"]?.keyedFrames, [0, 5])
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
        manager.addKeys(target, atFrame: 0)
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
        manager.addKeys(target, atFrame: 0)
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
    /// `addKeys` took its neighbour list from the **two-argument** `keyframes(marks:tracks:)`,
    /// whose `poseFrames` defaulted to empty, while `keyframes(of:)` passed them — two spellings of
    /// the list §2.28 rules must have exactly one. Here the pose key at frame 4 is the *only* other
    /// keyframe, so the blind list finds no neighbour at all and the baseline is discarded with the
    /// animation it was holding.
    ///
    /// Watched failing with `addKeys`'s `placed` back on the static two-argument form: the group
    /// channel comes out with one key at frame 8, `isAnimated` false, and the drawing's old position
    /// nowhere in the document.
    func testAddingAKeyframeSeedsAHeldPoseOntoANeighbourThatIsOnlyAPoseKey() throws {
        let (manager, layerID, celID) = fixture()
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        let group = UUID()

        // The whole-cel channel is animated across frames 0 and 4 — keys placed by moving, which
        // §2.26 records as a curve and no mark, so `keyframeMarks` is empty.
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                   CanvasFixture.poseTrack(box: box, [(0, PoseQuad(restingIn: box)),
                                                                      (4, slide(30))]))
        XCTAssertEqual(manager.keyframeState(of: target).marks, [],
                       "Setup: frames 0 and 4 are keyframes by key, not by mark")
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 4])

        // A second channel holds a pose: the artist moved a group at frame 8 and has not pressed the
        // keyframe button yet.
        manager.holdPoseBaseline(layerID: layerID, celID: celID, channel: .group(group),
                                 pose: slide(-18))

        manager.addKeys(target, atFrame: 8)
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["group.\(group.uuidString)"])
        XCTAssertEqual(track.keyedFrames, [4, 8],
                       "The held pose lands on frame 4 — the nearest keyframe below, which is a pose key")
        XCTAssertTrue(track.isAnimated)
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 4)?.value ?? 0, Double(box.midX) - 18, accuracy: 1e-9,
                       "keyframe A holds where the drawing was")
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 8)?.value ?? 0, Double(box.midX), accuracy: 1e-9,
                       "and B holds where it is now")
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

    // MARK: - An animation group's identity, reached (KEYFRAMES.md §3.4)

    /// **A minted group can be renamed, and the channel list reads the new name.**
    ///
    /// `mintAnimationChannel` calls them "Group 1", "Group 2" — a count — and `poseChannelName(_:)`
    /// is what draws that over the curve in the graph editor's channel list. A document with four of
    /// them offered four rows differing by a number, so the one thing a group's identity is *for*
    /// could not be used. Asserted through `poseChannelName` rather than through the stored field,
    /// because that accessor is what the artist reads and a rename the list did not pick up would be
    /// a rename that did nothing.
    func testRenamingAnAnimationGroupChangesTheNameTheChannelListDraws() {
        let manager = CanvasManager()
        manager.canvasSize = CanvasFixture.canvasSize
        let group = AnimationGroup(displayName: "Group 1",
                                   tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.animationGroups = [group]
        XCTAssertEqual(manager.poseChannelName(.group(group.id)), "Group 1")

        XCTAssertTrue(manager.renameAnimationGroup(group.id, to: "  Left arm  "))

        XCTAssertEqual(manager.poseChannelName(.group(group.id)), "Left arm",
                       "Trimmed, and read back through the accessor the list draws with")
        manager.undo()
        XCTAssertEqual(manager.poseChannelName(.group(group.id)), "Group 1",
                       "One press, because `animationGroups` is inside the structure snapshot")
    }

    /// **A minted group's name never repeats a standing one** (`DefaultName`'s rule): with "Group 2"
    /// the survivor of a deleted "Group 1", the next group is "Group 3", where a count gave a second
    /// "Group 2" — two rows in the channel list differing by nothing.
    func testAMintedAnimationGroupIsNumberedPastTheHighestStanding() {
        let manager = CanvasManager()
        manager.canvasSize = CanvasFixture.canvasSize
        let tag = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        manager.animationGroups = [AnimationGroup(displayName: "Group 2", tagColor: tag)]

        XCTAssertEqual(manager.mintedAnimationGroup().displayName, "Group 3")
        manager.animationGroups = []
        XCTAssertEqual(manager.mintedAnimationGroup().displayName, "Group 1")
    }

    /// **An empty name is refused rather than stored.** `poseChannelName`'s fallback covers a group
    /// that is *missing*, not one that is blank, so a blank name would draw an unpickable row — which
    /// is `renameLayer`'s own rule reached one type over.
    func testAnEmptyAnimationGroupNameIsRefused() {
        let manager = CanvasManager()
        manager.canvasSize = CanvasFixture.canvasSize
        let group = AnimationGroup(displayName: "Group 1",
                                   tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.animationGroups = [group]

        XCTAssertFalse(manager.renameAnimationGroup(group.id, to: "   "))
        XCTAssertEqual(manager.poseChannelName(.group(group.id)), "Group 1")
        XCTAssertFalse(manager.canUndo, "…and refusing records no step to take back")
    }

    /// **The row-to-group accessor answers only for a group's row.** The channel list asks it to
    /// decide whether to draw a tag dot and offer Rename, and a whole-cel Move, a container pose or a
    /// grade's header must get neither — a rename control on a row with nothing to rename is the
    /// dead-control shape this feature keeps running into.
    func testOnlyAGroupsRowNamesAnAnimationGroup() {
        let manager = CanvasManager()
        manager.canvasSize = CanvasFixture.canvasSize
        let group = AnimationGroup(displayName: "Group 1",
                                   tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.animationGroups = [group]

        XCTAssertEqual(manager.animationGroup(named: .cel(.group(group.id))), group)
        XCTAssertNil(manager.animationGroup(named: .cel(.cel)))
        XCTAssertNil(manager.animationGroup(named: .container))
        XCTAssertNil(manager.animationGroup(named: nil))
        XCTAssertNil(manager.animationGroup(named: .cel(.group(UUID()))),
                     "A tag whose group has been deleted names nothing")
    }

    // MARK: - Duplicate (BUGS.md, 2026-09-11)

    /// **`duplicateLayer` dropped every cel's pose channels.** Each copied `Cel(...)` named `raster`,
    /// `bakedImage` and `vector` and not `transformTracks` or `pendingPoseBaselines`, so
    /// a duplicated layer's Move animation was silently deleted — the fourth site `duplicateCel`,
    /// `splitCel` and `pasteCel` fell through before 2026-09-02, reached through `duplicateLayer`'s
    /// own door. The fix routes the cel copy through `copyTiers(of:)`, exactly as `duplicateCel`
    /// already does.
    ///
    /// Watched failing with `copyTiers` removed from `duplicateLayer`'s cel loop (a bare `Cel(...)`
    /// with no `transformTracks:`/`pendingPoseBaselines:`): `copy.transformTracks` reads `[:]` and
    /// frame 4 renders the resting drawing — `inkBounds` at the source's *rest* position rather than
    /// its posed one, so the bounds comparison is the assertion that would go red on its own even
    /// without the channel-equality check beside it.
    func testDuplicatingALayerCarriesItsCelsMoveKeysAndRendersTheSamePoseAtAMiddleFrame() throws {
        let (manager, layerID, celID) = fixture()
        animate(manager, layerID: layerID, celID: celID)
        let source = manager.layers[1].cels[0]
        let want = PixelOps.rasterize(cel: source, canvasSize: size,
                                      derived: manager.derivedCelContent(for: source, atFrame: 4))
        let wantBounds = try XCTUnwrap(inkBounds(want), "Setup: frame 4 shows a posed drawing")

        manager.duplicateLayer(at: 1)
        XCTAssertEqual(manager.layers.count, 3, "Setup: the duplicate landed")
        let copy = manager.layers[2].cels[0]
        XCTAssertEqual(copy.transformTracks, source.transformTracks,
                       "the whole channel — keys, handles and all — travels with the copy")

        let got = PixelOps.rasterize(cel: copy, canvasSize: size,
                                     derived: manager.derivedCelContent(for: copy, atFrame: 4))
        let gotBounds = try XCTUnwrap(inkBounds(got),
                                      "the copy must still derive a posed picture at frame 4")
        XCTAssertEqual(gotBounds.minX, wantBounds.minX, accuracy: 0.5,
                       "the duplicate renders the same pose the source does at the same frame — what "
                       + "is drawn, not only what `transformTracks` stores")
    }
}
