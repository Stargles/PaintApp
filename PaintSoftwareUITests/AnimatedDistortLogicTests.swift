import XCTest
import UIKit
import CoreGraphics

/// **Pure-logic tests for the animated Distort** — KEYFRAMES.md §8 stage 5b, TODO item (12)'s last
/// piece: a genuinely projective quad keyed across frames.
///
/// ## What is new here, and what is deliberately not
///
/// The *unkeyed* projective ink shipped on 2026-09-06 and `InkDistortLogicTests` pins it — the per-dab
/// `localScale`, the persisted `VectorStroke.distort`, the rest walk. Nothing here re-asserts any of
/// that. What stage 5b added is the path between a **key** and that renderer, and it is exactly five
/// things: a key that stores a keystone rather than its affine part, two render reads that answer a
/// `PoseMap` rather than a linearisation, a blend that carries the perspective row, cache keys wide
/// enough to tell two keystones apart, and a container float that is no longer refused.
///
/// ## Every number below is MEASURED on one quad, and it is the same quad throughout
///
/// A 400x300 box whose top edge is pulled in to 120 pt — `keystone` below. On it:
///
///  * the linearisation at the box centre, which is what `PoseQuad.affineOrLinearised` answered until
///    this stage, puts the two **bottom corners 164.4 px** from where the homography puts them;
///  * local scale spans **0.300 to 1.826** across the box, a **6.09x** range, against a single scalar
///    of 0.572 at the centre — 218% wrong at the far end (§8 reports 8.5x and 315% on its own,
///    harder quad, which is the same phenomenon measured somewhere else);
///  * a blend at `t = 0.5` that **dropped** the perspective row lands the bottom-right corner
///    **166.7 px** away from where the shipped blend lands it.
///
/// Those three numbers are what make the assertions below measurements rather than definitions: an
/// assertion that merely held wherever a homography is not an affine would be true of the arithmetic
/// and not of this app.
///
/// `@MainActor` because the document-level arms drive `CanvasManager`.
@MainActor
final class AnimatedDistortLogicTests: XCTestCase {

    // MARK: - The one quad

    /// The rest box. Larger than `CanvasFixture.canvasSize` on purpose: the pose arithmetic below is
    /// pure and takes no canvas, and a 400x300 box is where §8's own figures were taken.
    private let box = CGRect(x: 0, y: 0, width: 400, height: 300)

    /// The top edge pulled in to 120 pt — a strong keystone, and the quad every measured number in
    /// this file's header was taken on.
    private var keystone: Quad {
        Quad(CGPoint(x: 140, y: 0), CGPoint(x: 260, y: 0),
             CGPoint(x: 400, y: 300), CGPoint(x: 0, y: 300))
    }

    private var keystonePose: PoseQuad { PoseQuad(box: box, corners: keystone) }
    private var restingPose: PoseQuad { PoseQuad(restingIn: box) }

    private func stroke(_ points: [CGPoint], size strokeSize: CGFloat = 6) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: strokeSize, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: - Storage: a key holds the keystone, not its affine part

    /// **The whole of "store a genuinely projective quad".** `PoseQuad` has held four free corners
    /// since stage 5 (§2.14, *"from day one, so Distort costs no migration"*), so this is a test that
    /// the *writer* uses them — `commitTransformPose` built its key with `PoseQuad(box:mappedBy:)`,
    /// which takes a `CGAffineTransform` and therefore could not express a keystone at all.
    ///
    /// Mutate `commitTransformPose` back to the affine initialiser and this goes red on the first
    /// assertion; nothing else in the suite notices, which is why it is here.
    func testACommittedDistortKeysTheKeystoneRatherThanItsAffinePart() throws {
        let (manager, layerID, celID) = animatedFixture()
        let map = try XCTUnwrap(PoseMap(keystonePose))
        XCTAssertTrue(map.isProjective, "Fixture: the map being committed is genuinely a keystone")

        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel,
                                                restBox: box, map: map,
                                                restElements: manager.layers[1].cels[0].vector?.elements ?? [],
                                                atFrame: 4)
        XCTAssertEqual(route, .key, "Fixture: an already-animated channel takes the auto-key arm")

        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks["cel"])
        let key = try XCTUnwrap(track.key(atFrame: 4))
        XCTAssertNil(key.pose.affine, "The stored key is a keystone and not any affine")
        XCTAssertEqual(key.pose.map?.isProjective, true)
        // The four corners are the artist's, to the bit the solver can recover them.
        for (stored, wanted) in zip(key.pose.corners.points, keystone.points) {
            XCTAssertEqual(distance(stored, wanted), 0, accuracy: 1e-6)
        }
    }

    /// **A keystoned key survives a save and a reload**, which costs nothing to check and is the one
    /// claim §2.14 made in advance: eight doubles were always on the wire, so the format did not move.
    func testAKeystonedKeySurvivesTheWireUnflattened() throws {
        let track = TransformTrack(keys: [TransformTrack.Key(frame: 0, pose: restingPose),
                                          TransformTrack.Key(frame: 8, pose: keystonePose)])
        let decoded = try JSONDecoder().decode(TransformTrack.self,
                                               from: try JSONEncoder().encode(track))
        let key = try XCTUnwrap(decoded.key(atFrame: 8))
        XCTAssertNil(key.pose.affine, "A reload must not flatten the keystone")
        for (stored, wanted) in zip(key.pose.corners.points, keystone.points) {
            XCTAssertEqual(distance(stored, wanted), 0, accuracy: 1e-9)
        }
    }

    // MARK: - The two render reads

    /// **`TransformTrack.mapping(atCelLocalFrame:)`, the first of stage 5b's two render reads.**
    ///
    /// It answered `PoseQuad.affineOrLinearised`, so a keystoned channel rendered as its linearisation
    /// at the box centre. The second assertion is the one that makes this a measurement: the map the
    /// channel now answers disagrees with that linearisation by **164.4 px** at the box's own bottom
    /// corner, so a reader that quietly went back to it cannot pass.
    func testTheCelChannelsRenderReadAnswersTheKeystoneAndNotItsLinearisation() throws {
        let track = TransformTrack(keys: [TransformTrack.Key(frame: 0, pose: keystonePose)])
        let map = try XCTUnwrap(track.mapping(atCelLocalFrame: 3), "A single key holds at every frame")
        XCTAssertTrue(map.isProjective)
        XCTAssertNil(map.affine)

        let corner = CGPoint(x: 0, y: 300)
        let exact = try XCTUnwrap(map.applied(to: corner))
        XCTAssertEqual(distance(exact, corner), 0, accuracy: 1e-6,
                       "The bottom edge is fixed by this quad, so the exact map leaves it alone")
        let linearised = try XCTUnwrap(map.homography.linearised(at: CGPoint(x: box.midX, y: box.midY)))
        XCTAssertEqual(distance(corner.applying(linearised), exact), 164.43, accuracy: 0.05,
                       "…and the approximation this stage deleted was 164 px out at that same corner")
    }

    /// **`LayerPose.mapping(atFrame:)`, the second render read** — §4.4's container, and the accessor
    /// whose linearisation `distortUnavailableReason` used to name as its reason for refusing Distort
    /// on a transformation layer.
    func testTheContainersRenderReadAnswersAKeystoneToo() throws {
        var pose = LayerPose(pose: keystonePose)
        let stored = try XCTUnwrap(pose.mapping(atFrame: 0))
        XCTAssertTrue(stored.isProjective, "The stored base carries a keystone")

        pose.track = TransformTrack(keys: [TransformTrack.Key(frame: 0, pose: restingPose),
                                           TransformTrack.Key(frame: 8, pose: keystonePose)])
        XCTAssertNil(pose.mapping(atFrame: 0),
                     "A resting key still costs the leaves beneath it no derivation at all")
        let keyed = try XCTUnwrap(pose.mapping(atFrame: 8))
        XCTAssertTrue(keyed.isProjective, "…and the track wins over the base, keystone and all")
    }

    /// **An affine pose is still an affine map, and it is the same one.** Without this every
    /// assertion above is satisfied by a mutation that made *everything* projective — which would
    /// change the composition arithmetic of every document ever made (see `PoseMap`'s own header for
    /// the 78.5% figure).
    func testAnAffinePoseIsStillAnAffineMapAndTheSameOne() throws {
        let slid = CGAffineTransform(translationX: 17, y: -4).rotated(by: 0.3)
        let track = TransformTrack(keys: [TransformTrack.Key(frame: 0,
                                                            pose: PoseQuad(box: box, mappedBy: slid))])
        let map = try XCTUnwrap(track.mapping(atCelLocalFrame: 0))
        XCTAssertFalse(map.isProjective)
        let recovered = try XCTUnwrap(map.affine)
        XCTAssertEqual(recovered.a, slid.a, accuracy: 1e-9)
        XCTAssertEqual(recovered.b, slid.b, accuracy: 1e-9)
        XCTAssertEqual(recovered.c, slid.c, accuracy: 1e-9)
        XCTAssertEqual(recovered.d, slid.d, accuracy: 1e-9)
        XCTAssertEqual(recovered.tx, slid.tx, accuracy: 1e-6)
        XCTAssertEqual(recovered.ty, slid.ty, accuracy: 1e-6)
    }

    // MARK: - The ink actually goes through it

    /// **The keystone reaches the ink**, which is the claim a `PoseMap` that stopped at the accessor
    /// would not make. `CanvasManager.posed` is the one function every posed frame's display list is
    /// built by, and it chooses between `VectorCanvas.posing(_:through: CGAffineTransform)` and the
    /// `Homography` overload.
    ///
    /// The sample chosen is the box's bottom-left corner, which this quad holds **fixed** — so the
    /// right answer is a round number the reader can check by eye, and the wrong one is 164 px away.
    func testPosedInkFollowsTheKeystonePointForPoint() throws {
        let bottom = stroke([CGPoint(x: 0, y: 300), CGPoint(x: 400, y: 300)])
        let map = try XCTUnwrap(keystonePose.map)
        let posed = CanvasManager.posed([.stroke(bottom)], through: [(.cel, map)])
        let after = try XCTUnwrap(posed.first?.stroke)
        let positions = after.samples.positions
        XCTAssertEqual(distance(positions[0], CGPoint(x: 0, y: 300)), 0, accuracy: 1e-6)
        XCTAssertEqual(distance(positions[positions.count - 1], CGPoint(x: 400, y: 300)), 0,
                       accuracy: 1e-6)

        // …and the same stroke through the approximation this stage deleted lands 164 px away, so a
        // pose path that flattened would fail here rather than merely looking slightly wrong.
        let linearised = try XCTUnwrap(map.homography.linearised(at: CGPoint(x: box.midX, y: box.midY)))
        XCTAssertEqual(distance(CGPoint(x: 0, y: 300).applying(linearised), positions[0]),
                       164.43, accuracy: 0.05)
    }

    /// **The posed stroke carries a *projective* rest walk**, which is what gives every dab its own
    /// `localScale` instead of one scalar for the whole mark (§4.2, stage 4's bake).
    ///
    /// The `affine() == nil` is the assertion about this app; the 6.09x span beside it is what says
    /// the distinction is worth anything on this quad — a walk carrying an affine would report one
    /// scale at both ends by construction.
    func testAPosedKeystoneAttachesAProjectiveWalkSoEveryDabScalesOnItsOwn() throws {
        let down = stroke([CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 300)])
        let map = try XCTUnwrap(keystonePose.map)
        let posed = CanvasManager.posed([.stroke(down)], through: [(.cel, map)])
        let walk = try XCTUnwrap(try XCTUnwrap(posed.first?.stroke).restWalk)
        XCTAssertNil(walk.pose.map.affine(),
                     "The walk carries the homography, so `PosedDabTarget` asks it per dab")
        let top = try XCTUnwrap(walk.pose.map.localScale(at: CGPoint(x: 200, y: 0)))
        let bottom = try XCTUnwrap(walk.pose.map.localScale(at: CGPoint(x: 200, y: 300)))
        XCTAssertEqual(top, 0.300, accuracy: 0.002)
        XCTAssertEqual(bottom, 1.8257, accuracy: 0.002)
        XCTAssertEqual(bottom / top, 6.086, accuracy: 0.02,
                       "No single scalar is right across this mark, which is why stage 4 came first")
    }

    // MARK: - The blend (§2.15, §4.3)

    /// **The perspective row is lerped, and this is the arithmetic that says so.**
    ///
    /// `PoseInterpolation.blend` factors each pose as affine × pure-projective and lerps the
    /// projective part. MEASURED: with keyframe A resting, the blend's own perspective row is
    /// **exactly** `t` times keyframe B's, at every `t`. An implementation that dropped the row would
    /// report zero here — and would still pass every existing test in `PoseInterpolationLogicTests`,
    /// because every pose that file blends is affine.
    ///
    /// **This stage found the blend already carrying it**, which refutes stage 5b's own brief. What
    /// was missing was any test: the row was written in 2026-09-02's factored construction and had
    /// never been exercised, because nothing could author a projective key.
    func testTheBlendLerpsThePerspectiveRowRatherThanDroppingIt() throws {
        let end = try XCTUnwrap(PoseInterpolation.factored(try XCTUnwrap(keystonePose.homography)))
        XCTAssertNotEqual(end.h, 0, "Fixture: this quad's perspective row is live")

        for t in [CGFloat(0.25), 0.5, 0.75] {
            let mid = try XCTUnwrap(PoseInterpolation.blend(restingPose, keystonePose, t: t))
            let factored = try XCTUnwrap(PoseInterpolation.factored(try XCTUnwrap(mid.homography)))
            XCTAssertEqual(factored.h / (t * end.h), 1, accuracy: 1e-9,
                           "at t = \(t) the row is t times the key's, not zero and not the key's")
            XCTAssertEqual(factored.g, 0, accuracy: 1e-12, "and this quad has no g to carry")
        }
    }

    /// **What dropping the row would actually look like**, in pixels rather than in matrix entries —
    /// the same blend rebuilt from its own affine factor with `g` and `h` zeroed.
    ///
    /// MEASURED at `t = 0.5`: the bottom-right corner moves **166.7 px**. That is the number that
    /// makes the row worth carrying, and it is more than half the box's height.
    func testABlendThatDroppedTheRowWouldMissTheCornerBy166Pixels() throws {
        let mid = try XCTUnwrap(PoseInterpolation.blend(restingPose, keystonePose, t: 0.5))
        XCTAssertNil(mid.affine, "The in-between of a resting key and a keystone is itself a keystone")

        let factored = try XCTUnwrap(PoseInterpolation.factored(try XCTUnwrap(mid.homography)))
        let flattened = Homography(a: factored.linear.a, b: factored.linear.b, c: factored.translation.dx,
                                   d: factored.linear.c, e: factored.linear.d, f: factored.translation.dy,
                                   g: 0, h: 0, i: 1)
        let without = try XCTUnwrap(PoseQuad(box: mid.box, mappedThrough: flattened))
        XCTAssertEqual(distance(mid.corners.p2, without.corners.p2), 166.68, accuracy: 0.05)
        XCTAssertEqual(distance(mid.corners.p3, without.corners.p3), 107.08, accuracy: 0.05)
        // The two top corners are where the affine factor already puts them, which is what "the row
        // is the *only* difference" means and is why the two figures above are not four.
        XCTAssertEqual(distance(mid.corners.p0, without.corners.p0), 0, accuracy: 1e-6)
        XCTAssertEqual(distance(mid.corners.p1, without.corners.p1), 0, accuracy: 1e-6)
    }

    /// Two keystones blend to a keystone, and the in-between is a real one rather than either end
    /// held — §9.1's validity clamp answers the nearer *key*, so a pose that is neither says the
    /// blend ran.
    func testTwoKeystonesBlendToAThirdRatherThanSnappingToEitherKey() throws {
        let other = PoseQuad(box: box, corners: Quad(CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0),
                                                     CGPoint(x: 300, y: 300), CGPoint(x: 100, y: 300)))
        XCTAssertNil(other.affine, "Fixture: both keys are keystones")
        let mid = try XCTUnwrap(PoseInterpolation.blend(keystonePose, other, t: 0.5))
        XCTAssertNil(mid.affine)
        XCTAssertNotEqual(mid, keystonePose)
        XCTAssertNotEqual(mid, other)
        XCTAssertTrue(mid.isValid, "and a scrub between two valid keys draws something drawable")
    }

    // MARK: - `PoseMap`'s composition invariant

    /// **The reason `PoseMap` is two cases and not one `Homography`**, asserted in both directions.
    ///
    /// The first half is the invariant: an affine composed with an affine is exactly
    /// `CGAffineTransform.concatenating`, bit for bit, so every document that has never held a
    /// keystone renders what it rendered. The second half is the fixture that makes the first worth
    /// having — the 3×3 spelling of the same product genuinely differs, because CoreGraphics fuses
    /// its multiply-adds and `Homography.*` does not. Drop the affine arm of `concatenating` and the
    /// first half goes red.
    func testAffinePosesComposeThroughCoreGraphicsBitForBit() {
        var differed = 0
        var seed = SystemRandomNumberGenerator()
        for _ in 0..<2_000 {
            func r() -> CGFloat { CGFloat.random(in: -3...3, using: &seed) }
            let a = CGAffineTransform(a: r(), b: r(), c: r(), d: r(), tx: r() * 100, ty: r() * 100)
            let b = CGAffineTransform(a: r(), b: r(), c: r(), d: r(), tx: r() * 100, ty: r() * 100)
            guard let composed = PoseMap(a).concatenating(PoseMap(b)).affine else {
                return XCTFail("An affine composed with an affine is an affine")
            }
            XCTAssertEqual(composed, a.concatenating(b))
            if (Homography(b) * Homography(a)).affine() != a.concatenating(b) { differed += 1 }
        }
        XCTAssertGreaterThan(differed, 1_000, """
            Fixture: the 3x3 spelling of this product is not bit-identical to CoreGraphics's own, \
            which is the whole reason the affine arm exists. If this ever reaches 0 the arm has \
            stopped buying anything and can go.
            """)
    }

    /// A keystone anywhere in a chain takes the whole chain projective, and the composition is the
    /// product rather than either factor — the arithmetic `posed(_:through:inheriting:)` relies on
    /// when a cel channel sits under a keystoned transformation layer.
    func testAKeystoneAnywhereInAChainCarriesTheWholeChain() throws {
        let slide = PoseMap(CGAffineTransform(translationX: 40, y: 0))
        let keyed = try XCTUnwrap(PoseMap(keystonePose))
        let composed = slide.concatenating(keyed)
        XCTAssertTrue(composed.isProjective)
        let start = CGPoint(x: 0, y: 300)
        let viaChain = try XCTUnwrap(composed.applied(to: start))
        let byHand = try XCTUnwrap(keyed.applied(to: try XCTUnwrap(slide.applied(to: start))))
        XCTAssertEqual(distance(viaChain, byHand), 0, accuracy: 1e-9,
                       "slide first, then the keystone — the order `posed` composes in")
    }

    // MARK: - The cache keys (§4.5, through stage 5b's door)

    /// **Two keystones that share an affine factor must not share a cache entry.**
    ///
    /// §4.5's trap is that the instant one `Cel` can produce two pictures, a key that cannot tell
    /// them apart hands the first frame's pixels to every frame of the move — and `SandwichKey`
    /// rebuilds the composite dutifully from the stale flatten, so nothing looks broken anywhere a
    /// reader would look. Every pose key in the app encodes `PoseMap.encoded`; drop `g`, `h` and `i`
    /// from it and these two poses become one entry.
    ///
    /// The pair is built as `A · P(0, h)` for two different `h`, so their affine factors are equal by
    /// construction rather than by luck.
    func testTwoKeystonesSharingAnAffineFactorEncodeDifferently() throws {
        let affine = Homography(CGAffineTransform(scaleX: 1.4, y: 0.9).translatedBy(x: 12, y: 3))
        func pose(_ h: CGFloat) throws -> PoseQuad {
            let projective = Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: 0, h: h, i: 1)
            return try XCTUnwrap(PoseQuad(box: box, mappedThrough: affine * projective))
        }
        let first = try XCTUnwrap(PoseMap(try pose(-0.0012)))
        let second = try XCTUnwrap(PoseMap(try pose(-0.0023)))
        XCTAssertTrue(first.isProjective)
        XCTAssertTrue(second.isProjective)
        XCTAssertEqual(first.encoded.count, 9, "A keystone is nine numbers")
        XCTAssertEqual(PoseMap(CGAffineTransform.identity).encoded.count, 6, "…and an affine is six")
        // The fixture's own premise, checked rather than asserted in prose: the two maps have the
        // **same affine factor** and differ only in the perspective row, so a key that stored six
        // numbers taken from that factor would hand them one entry.
        let factoredFirst = try XCTUnwrap(PoseInterpolation.factored(first.homography))
        let factoredSecond = try XCTUnwrap(PoseInterpolation.factored(second.homography))
        for (a, b) in [(factoredFirst.linear.a, factoredSecond.linear.a),
                       (factoredFirst.linear.b, factoredSecond.linear.b),
                       (factoredFirst.linear.c, factoredSecond.linear.c),
                       (factoredFirst.linear.d, factoredSecond.linear.d),
                       (factoredFirst.translation.dx, factoredSecond.translation.dx),
                       (factoredFirst.translation.dy, factoredSecond.translation.dy)] {
            XCTAssertEqual(a, b, accuracy: 1e-6, "Fixture: one affine factor, two perspective rows")
        }
        XCTAssertNotEqual(factoredFirst.h, factoredSecond.h)
        XCTAssertNotEqual(first.encoded, second.encoded,
                          "…and the encoding is the whole map, so the two are two entries")

        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 12,
                      raster: .empty(size: CanvasFixture.canvasSize))
        XCTAssertNotEqual(LayerContentVersion(cel: cel, pose: first),
                          LayerContentVersion(cel: cel, pose: second),
                          "…and the leaf version a composite is keyed on tells them apart")
    }

    // MARK: - The container float (§4.4), which used to be refused

    /// **Distort is no longer refused on a transformation layer, and it is still refused for a
    /// photo.** Both halves, because deleting the whole accessor would satisfy the first.
    ///
    /// The refusal it replaces named `PoseQuad.affineOrLinearised` as its reason and was worse than
    /// it read: the mode picker stayed live, the corner drag wrote `distortQuad`, the outline
    /// foreshortened under the finger and the canvas did not follow.
    func testDistortIsNoLongerRefusedOnATransformationLayerAndIsStillRefusedForAPhoto() throws {
        let manager = transformLayerFixture()
        manager.setTransformMode(.distort)
        XCTAssertTrue(manager.beginContainerPoseMove(), "Fixture: a container float comes up")
        XCTAssertEqual(manager.floatingPiece?.kind, .containerPose)
        XCTAssertNil(manager.distortUnavailableReason,
                     "The bar has nothing left to say about a transformation layer")

        XCTAssertTrue(manager.commitFloatingPieceIfNeeded())

        // …and the *kind* refusal is untouched: a float carrying a placed image still says so.
        let withPhoto = CanvasFixture.manager(layerCount: 1)
        withPhoto.addVectorLayer()
        let vector = try XCTUnwrap(withPhoto.layers[withPhoto.currentLayerIndex].cels[0].vector)
        vector.addStroke(stroke([CGPoint(x: 8, y: 8), CGPoint(x: 40, y: 8)]))
        vector.addImage(VectorImageElement(
            image: CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                            size: CGSize(width: 6, height: 6)),
            transform: LayerTransform(position: CGPoint(x: 20, y: 30), scale: 1, rotation: 0)))
        withPhoto.setTransformMode(.distort)
        XCTAssertTrue(withPhoto.beginVectorWholeCelMove())
        XCTAssertNotNil(withPhoto.distortUnavailableReason,
                        "A float carrying a placed image is still refused, and by kind")
    }

    /// **A container Distort reaches the stored pose.** The drag writes `distortQuad`; the preview
    /// and the commit both go through `CanvasManager.containerPose(_:movedBy:)`, which took the
    /// *affine* delta and silently dropped the residue until this stage.
    ///
    /// The second assertion is what a reader can check: the pose's own top edge is where the artist
    /// pulled the box's top edge to, and a foreshortening that had been flattened would leave it a
    /// parallelogram.
    func testAContainerFloatsDistortReachesTheStoredPose() throws {
        let manager = transformLayerFixture()
        let at = try XCTUnwrap(manager.layers.firstIndex { $0.layerTransform != nil })
        manager.setTransformMode(.distort)
        XCTAssertTrue(manager.beginContainerPoseMove())

        let piece = try XCTUnwrap(manager.floatingPiece)
        let local = piece.localBox
        // The top edge pulled in by a quarter of the box's width on each side — the same shape as
        // this file's own quad, in the float's local space.
        let pulled = Quad(CGPoint(x: local.minX + local.width / 4, y: local.minY),
                          CGPoint(x: local.maxX - local.width / 4, y: local.minY),
                          CGPoint(x: local.maxX, y: local.maxY),
                          CGPoint(x: local.minX, y: local.maxY))
        manager.updateFloatingPose(transform: piece.transform, distortQuad: pulled)

        let posed = try XCTUnwrap(manager.layers[at].layerTransform?.pose)
        XCTAssertNil(posed.affine, "The stored container pose is a keystone")
        XCTAssertEqual(posed.map?.isProjective, true)
        let width = posed.corners.p1.x - posed.corners.p0.x
        XCTAssertEqual(width, local.width / 2, accuracy: 0.5,
                       "The pose's top edge is half the box wide, which is where the corner went")
        XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
        XCTAssertNil(try XCTUnwrap(manager.layers[at].layerTransform).pose.affine,
                     "…and the commit keeps it rather than flattening on the way out")
    }

    // MARK: - Cold start: can an artist get here at all

    /// **From a document with nothing in it, in the order the artist presses things** — CLAUDE.md's
    /// *"a feature whose only entry point requires state only that entry point can create"*, asked of
    /// this stage.
    ///
    /// Draw, mark a keyframe, scrub, Move, pick Distort, pull a corner, let go, mark again. No step
    /// constructs a track, a channel or a pose by hand; every one is a call the shipped UI makes.
    /// What comes out is a two-key animation whose in-between is a keystone.
    func testAnArtistCanKeyADistortAcrossTwoFramesFromAColdDocument() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let at = manager.currentLayerIndex
        let vector = try XCTUnwrap(manager.layers[at].cels[0].vector)
        vector.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 20),
                                 CGPoint(x: 50, y: 44)], size: 4))
        let layerID = manager.layers[at].id
        let celID = manager.layers[at].cels[0].id
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: at))

        // 1. A keyframe mark at frame 0 — §2.26's first step, a bare mark in time.
        manager.currentFrame = 0
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 0))
        XCTAssertTrue(manager.layers[at].cels[0].transformTracks.isEmpty,
                      "A mark on its own writes no channel")

        // 2. Scrub, raise the Move box, choose Distort, pull the top-left corner.
        manager.currentFrame = 8
        manager.setTransformMode(.distort)
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "Move is reachable with no selection")
        let float = try XCTUnwrap(manager.vectorFloat)
        XCTAssertNil(manager.distortUnavailableReason, "…and Distort is offered on this float")
        var quad = float.frame.localQuad
        quad[0] = CGPoint(x: quad.p0.x + float.contentSize.width * 0.35, y: quad.p0.y)
        manager.nudgeVectorFloat(to: float.frame.transform,
                                 distort: .some(BoxDistort(quad: quad, boxSize: float.contentSize,
                                                           boxOffset: float.frame.contentOffset,
                                                           boxAngle: 0)))

        // 3. Let go. §2.5's write-at-commit: with one mark behind the playhead this holds the pose
        //    that puts the drawing back, rather than keying anything yet.
        XCTAssertTrue(manager.commitVectorFloatIfNeeded())
        let held = try XCTUnwrap(manager.layers[at].cels[0].pendingPoseBaselines["cel"])
        XCTAssertNil(held.affine, "The held baseline is the inverse keystone, not its affine part")

        // 4. The second mark commits it, and the pair is an animation.
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 8))
        let track = try XCTUnwrap(manager.layers[at].cels[0].transformTracks["cel"])
        XCTAssertEqual(track.keys.count, 2)
        XCTAssertTrue(track.isAnimated)
        XCTAssertNil(try XCTUnwrap(track.key(atFrame: 0)).pose.affine,
                     "Keyframe A holds where the drawing was — a keystone, because the Move was one")

        // 5. And a scrub between them shows a keystone rather than a parallelogram.
        let between = try XCTUnwrap(track.mapping(atCelLocalFrame: 4))
        XCTAssertTrue(between.isProjective, "The in-between the artist scrubs to is a real keystone")
        XCTAssertNotNil(manager.derivedCelContent(for: manager.layers[at].cels[0], atFrame: 4),
                        "…and the frame has a derivation, which is what puts it on screen")
        XCTAssertEqual(manager.layers[at].id, layerID)
        XCTAssertEqual(manager.layers[at].cels[0].id, celID)
    }

    // MARK: - Fixtures

    /// A vector layer at index 1 with one cel, one stroke, and a cel channel already animated — so
    /// `commitTransformPose` takes the `.key` arm rather than the routing rule's other three.
    private func animatedFixture() -> (manager: CanvasManager, layerID: UUID, celID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 12,
                      raster: .empty(size: CanvasFixture.canvasSize),
                      vector: .empty(size: CanvasFixture.canvasSize))
        cel.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[1].cels = [cel]
        let layerID = manager.layers[1].id
        manager.setTransformPoseKey(layerID: layerID, celID: cel.id, channel: .cel,
                                    atCelLocalFrame: 0, pose: PoseQuad(restingIn: box))
        manager.setTransformPoseKey(layerID: layerID, celID: cel.id, channel: .cel,
                                    atCelLocalFrame: 8,
                                    pose: PoseQuad(box: box, mappedBy: .init(translationX: 5, y: 0)))
        return (manager, layerID, cel.id)
    }

    /// A vector layer with a transformation layer above it, current — §4.4's fixture, reduced to the
    /// two layers these tests need.
    private func transformLayerFixture() -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = CanvasFixture.canvasSize
        manager.addVectorLayer(name: "ink")
        manager.addValueLayer(name: "mover")
        let at = manager.layers.count - 1
        manager.setLayerTransform(layerIndex: at, to: manager.restingContainerPose)
        manager.currentLayerIndex = at
        return manager
    }
}
