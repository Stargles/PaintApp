import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for **what a copy of a derived cel is** — the ruling of 2026-09-03.
///
/// The defect: `duplicateCel`, `copyCel`/`pasteCel` and `splitCel` carried a cel's pose channels but
/// not its `interpolation` recipe. A `.generate` in-between **stores nothing** — its picture is
/// computed — so a copy of one came out **blank**, and one `splitCel` gave an in-between beside a
/// blank cel because the surviving half is mutated in place while the new half is a fresh `Cel`.
///
/// The ruling: duplicate and paste **flatten** the in-between into a still that stops following its
/// keyframes; split **carries the recipe to both halves**, because it makes no copy at all.
///
/// **Every assertion here is pixels, and that is deliberate.** The obvious test — "the copy's
/// `interpolation` is nil" — is true of the blank cel this bug produced for the whole of its life,
/// so it could not have gone red at any point during it. `testACopiedInBetweenStopsFollowingTheDrawingsItCameFrom`
/// is the one that would also pass on the old code (a blank stays blank under any edit), and it is
/// here for the *other* half of the ruling: paired with the two "not blank, and the same bytes" tests
/// above it, the pair distinguishes a flattened still from both a blank and a carried recipe, which
/// no single one of the three can do alone.
final class InterpolatedCelCopyLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }

    /// The shared flatten memo is keyed on model state, so a test that edits a keyframe and looks
    /// again must start cold — and must clear it *between* the two looks as well, or "the copy did
    /// not change" is a statement about a cache hit rather than about the copy.
    override func setUp() {
        super.setUp()
        PixelOps.clearRasterizeCache()
    }

    // MARK: - Fixtures

    private func stroke(_ points: [CGPoint]) -> VectorStroke {
        VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
    }

    /// Layer 1 (vector) with three cels: a bar at the left over frames 0..<4, **nothing at all** over
    /// 4..<6, and the same bar 24pt to the right over 8..<12. The middle cel carries a `.generate`
    /// recipe at `t`, so everything it shows it derives.
    ///
    /// Two frames long rather than four so `duplicateCel` — which lands at the source's `endFrame` —
    /// has somewhere to put the copy. `clampedCelLength` returns nil against a neighbour starting at
    /// exactly the end frame, and duplicate is then a silent no-op, which would read as a failure of
    /// the ruling rather than of the fixture.
    private func interpolated(t: CGFloat = 0.5) throws
    -> (manager: CanvasManager, cels: [Cel], layerID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cels = (0..<3).map { i in
            Cel(id: UUID(), startFrame: i * 4, frameCount: 4, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        manager.layers[1].cels = cels
        cels[0].vector?.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 20),
                                          CGPoint(x: 30, y: 40)]))
        cels[2].vector?.addStroke(stroke([CGPoint(x: 34, y: 20), CGPoint(x: 54, y: 20),
                                          CGPoint(x: 54, y: 40)]))
        let layerID = manager.layers[1].id
        manager.enterInterpolateMode()
        for cel in [cels[0], cels[2]] {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: layerID)
        }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1),
                     "Setup: Generate must attach a recipe")
        manager.layers[1].cels[1].interpolation?.t = t
        manager.exitInterpolateMode()
        manager.layers[1].cels[1].frameCount = 2
        // **A fixture that has stopped working is a failure, not a skip** — CelContentProviderLogicTests
        // learned that from eleven skips reading as green.
        XCTAssertNotNil(manager.layers[1].cels[1].interpolation,
                        "Setup: the middle cel must carry the recipe every test here is about")
        return (manager, cels, layerID)
    }

    /// The picture the document actually shows for `cel` — literally the call a thumbnail, the onion
    /// skin and an export make, rather than a second implementation of it.
    private func shown(_ manager: CanvasManager, _ cel: Cel) -> UIImage {
        PixelOps.rasterize(cel: cel, canvasSize: size,
                           derived: manager.derivedCelContent(for: cel, atFrame: cel.startFrame))
    }

    /// The picture a cel shows out of its **own storage**, with no derivation offered — what a copy
    /// has to be able to produce on its own for the ruling to hold.
    private func stored(_ cel: Cel) -> UIImage {
        PixelOps.rasterize(cel: cel, canvasSize: size)
    }

    private func bytes(of image: UIImage) -> Data { image.pngData() ?? Data() }

    private func isBlank(_ image: UIImage) -> Bool { PixelOps.opaqueContentBounds(image) == nil }

    // MARK: - Duplicate and paste flatten

    /// **The defect, and the fix, in one test.** Before the ruling this copy was a blank cel.
    ///
    /// Watched failing with `duplicateCel` restored to `raster: source.raster.makeCopy(), … vector:
    /// source.vector?.makeCopy()` — the copy comes back blank and both the `isBlank` and the byte
    /// comparison go red.
    func testDuplicatingAnInBetweenCopiesThePictureItShowedRatherThanBlank() throws {
        let (manager, _, _) = try interpolated()
        let want = shown(manager, manager.layers[1].cels[1])
        XCTAssertFalse(isBlank(want), "Setup: the in-between shows a picture to begin with")

        manager.duplicateCel(layerIndex: 1, celIndex: 1)
        XCTAssertEqual(manager.layers[1].cels.count, 4, "Setup: the copy had room to land")
        let copy = try XCTUnwrap(manager.layers[1].cels.first { $0.startFrame == 6 })

        PixelOps.clearRasterizeCache()
        let got = stored(copy)
        XCTAssertFalse(isBlank(got), "a duplicate of an in-between is not blank")
        XCTAssertEqual(bytes(of: got), bytes(of: want),
                       "and it is the same picture, now stored rather than derived")
        XCTAssertNil(manager.derivedCelContent(for: copy, atFrame: copy.startFrame),
                     "which is what 'stops following the two drawings it derives from' means")
    }

    /// The same for the copy/paste pair. The flatten happens in `copyCel`, which is why `CopiedCel`
    /// needs no `interpolation` field: the clipboard is a snapshot, and a recipe naming other cels is
    /// the one thing a snapshot cannot capture by copying it.
    ///
    /// Watched failing with `copyCel` restored to snapshotting `source`'s tiers directly: the pasted
    /// cel is blank.
    func testCopyingAndPastingAnInBetweenPlantsThePictureRatherThanBlank() throws {
        let (manager, _, _) = try interpolated()
        let want = shown(manager, manager.layers[1].cels[1])
        XCTAssertFalse(isBlank(want), "Setup: the in-between shows a picture to begin with")

        manager.copyCel(layerIndex: 1, celIndex: 1)
        XCTAssertTrue(manager.pasteCel(layerIndex: 1, startFrame: 20))
        let pasted = try XCTUnwrap(manager.layers[1].cels.first { $0.startFrame == 20 })

        PixelOps.clearRasterizeCache()
        let got = stored(pasted)
        XCTAssertFalse(isBlank(got), "a paste of an in-between is not blank")
        XCTAssertEqual(bytes(of: got), bytes(of: want))
        XCTAssertNil(manager.derivedCelContent(for: pasted, atFrame: pasted.startFrame))
    }

    /// **A still, not a second in-between.** Redrawing a keyframe moves the cel that derives from it
    /// and must not reach the copy.
    ///
    /// The control half is what makes this worth running: it asserts the *source* did move, so a
    /// document in which nothing follows anything cannot satisfy it.
    ///
    /// **The copy is read through `shown`, not `stored`, and the difference is the whole test.**
    /// `stored` offers no derivation, so it would report the baked still whatever the copy carried —
    /// green under the ruling *and* green under the alternative the owner rejected, which is a
    /// fixture measuring its own arguments. `shown` asks the document what it displays, so a copy
    /// that still derives is a copy that visibly follows.
    ///
    /// Watched failing with `interpolation: source.interpolation` added to `duplicateCel`'s `Cel(...)`
    /// beside the flatten: the copy tracks the redrawn keyframe and `copyAfter` differs from
    /// `copyBefore`.
    func testACopiedInBetweenStopsFollowingTheDrawingsItCameFrom() throws {
        let (manager, cels, _) = try interpolated()
        manager.duplicateCel(layerIndex: 1, celIndex: 1)
        let copyID = try XCTUnwrap(manager.layers[1].cels.first { $0.startFrame == 6 }?.id)
        func copyNow() throws -> Data {
            bytes(of: shown(manager, try XCTUnwrap(manager.layers[1].cels.first { $0.id == copyID })))
        }

        PixelOps.clearRasterizeCache()
        let copyBefore = try copyNow()
        let sourceBefore = bytes(of: shown(manager, manager.layers[1].cels[1]))

        // Redraw the first keyframe somewhere else entirely.
        cels[0].vector?.addStroke(stroke([CGPoint(x: 8, y: 50), CGPoint(x: 56, y: 50)]))

        PixelOps.clearRasterizeCache()
        let sourceAfter = bytes(of: shown(manager, manager.layers[1].cels[1]))
        XCTAssertNotEqual(sourceAfter, sourceBefore,
                          "Control: the in-between itself does still follow its keyframes")
        XCTAssertEqual(try copyNow(), copyBefore,
                       "the copy is a still: redrawing a keyframe cannot reach it")
    }

    /// **Pose is dropped by the flatten, and the picture proves the flatten never applied it.**
    ///
    /// A cel can hold both a recipe and pose channels — `interpolate` does not refuse a recipe on a
    /// posed cel, though the pose *writer* refuses the reverse (§2.18) — and on such a cel the recipe
    /// wins and the tracks are inert, because `derivedCelContent` takes the interpolation arm and
    /// never reaches `posedCelContent`. So there is no doubled pose to fear; the hazard runs the other
    /// way, and carrying the tracks onto a copy that no longer has a recipe would make them newly
    /// live, animating a copy whose source stood still.
    ///
    /// The byte assertion is what says the bake is un-posed: `want` is taken through the interpolation
    /// arm with a 30pt translation sitting unread on the cel.
    ///
    /// Watched failing with `transformTracks: cel.transformTracks, pendingPoseBaselines:
    /// cel.pendingPoseBaselines` restored to `flattenedStill`'s `CopyTiers`: the two `isEmpty`
    /// assertions go red, and so do both frames of the `derivedCelContent` loop.
    func testAFlattenedCopyCarriesNoPoseChannelAndDerivesNothingAtAnyFrame() throws {
        let (manager, _, _) = try interpolated()
        let box = CGRect(x: 4, y: 6, width: 16, height: 8)
        manager.layers[1].cels[1].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 2, pose: PoseQuad(box: box,
                                                            mappedBy: CGAffineTransform(translationX: 30, y: 0)),
                                   interpolation: .linear)])
        ]
        manager.layers[1].cels[1].pendingPoseBaselines = [TransformChannelID.cel.id: PoseQuad(restingIn: box)]
        let want = bytes(of: shown(manager, manager.layers[1].cels[1]))

        manager.duplicateCel(layerIndex: 1, celIndex: 1)
        let copy = try XCTUnwrap(manager.layers[1].cels.first { $0.startFrame == 6 })
        XCTAssertTrue(copy.transformTracks.isEmpty, "a still does not animate")
        XCTAssertTrue(copy.pendingPoseBaselines.isEmpty, "and holds no pose waiting to be committed")
        for frame in copy.startFrame..<copy.endFrame {
            XCTAssertNil(manager.derivedCelContent(for: copy, atFrame: frame),
                         "the copy shows what it stores at frame \(frame), and derives nothing there")
        }

        PixelOps.clearRasterizeCache()
        XCTAssertEqual(bytes(of: stored(copy)), want,
                       "and what it stores is the un-posed in-between the artist was looking at")
    }

    /// **The regression this ruling could most easily have caused, and it is a *posed* cel that says
    /// so rather than a plain one.** A cel copied as a picture has lost every editable stroke on it,
    /// and an animated one has lost every frame of its animation but the first.
    ///
    /// **The subject is posed deliberately, because the plain case cannot go red.** The gate in
    /// `flattenedStill` is `cel.interpolation != nil`, and for a cel with neither a recipe nor a pose
    /// channel `derivedCelContent` answers nil anyway — so deleting that gate changes nothing for a
    /// plain cel and a test built on one is green under the defect it is written against. **Measured:
    /// with the gate removed, the plain-cel version of this test passed 7/7.** A pose channel is the
    /// *other* derivation source, so it is the only fixture on which the gate is load-bearing: without
    /// it, `derivedCelContent` takes the pose arm, the copy is baked at `startFrame`, and the
    /// animation is deleted.
    ///
    /// **And the pose has to be non-resting at frame 0, which cost this test a second measured miss.**
    /// `TransformTrack.mapping(atCelLocalFrame:)` answers nil for an identity pose, so a channel whose
    /// first key is the rest pose derives nothing *at the one frame `flattenedStill` reads* — and the
    /// first posed version of this test, keyed rest→slid and asserting its setup at frame 1, passed
    /// 7/7 with the gate removed just as the plain-cel version had. **Assert the setup at the frame
    /// the code under test actually reads**, not at one that merely proves the channel exists.
    ///
    /// Watched failing with `flattenedStill`'s `cel.interpolation != nil` guard removed: the copy's
    /// display list is empty, its `bakedImage` is a flatten of one frame, and its channel is gone —
    /// all three assertions red.
    func testDuplicatingAPosedCelCopiesItsGeometryAndItsChannelRatherThanFlatteningIt() throws {
        let (manager, cels, _) = try interpolated()
        manager.layers[1].cels[0].frameCount = 2
        let box = CGRect(x: 4, y: 6, width: 16, height: 8)
        func slid(_ dx: CGFloat) -> PoseQuad {
            PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: dx, y: 0))
        }
        manager.layers[1].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: slid(10), interpolation: .linear),
                TransformTrack.Key(frame: 2, pose: slid(30), interpolation: .linear)])
        ]
        let posed = manager.layers[1].cels[0]
        XCTAssertNotNil(manager.derivedCelContent(for: posed, atFrame: posed.startFrame),
                        "Setup: a posed cel derives its picture at its start frame too, which is the "
                        + "one frame the gate is asked about")

        manager.duplicateCel(layerIndex: 1, celIndex: 0)
        let copy = try XCTUnwrap(manager.layers[1].cels.first { $0.startFrame == 2 })

        XCTAssertEqual(cels[0].vector?.elements.count, 1, "Setup: the keyframe stores one stroke")
        XCTAssertEqual(copy.vector?.elements.count, 1,
                       "a cel that is not an in-between is copied as geometry, not as a picture of it")
        XCTAssertNil(copy.bakedImage, "and nothing is baked into it")
        XCTAssertEqual(copy.transformTracks[TransformChannelID.cel.id]?.keys.map(\.frame), [0, 2],
                       "and its animation rides along, which a flatten would have deleted")
    }

    // MARK: - Split carries the recipe

    /// **Both halves of a split in-between are the same in-between.** A split makes no copy, so the
    /// flatten ruling does not apply to it; the two halves derive from the same pair at the same `t`,
    /// and the picture at every frame is unchanged by the cut.
    ///
    /// Watched failing with `interpolation: cel.interpolation` removed from `splitCel`'s `Cel(...)`:
    /// the right half derives nothing, `XCTUnwrap` fails, and flattening it gives a blank.
    func testSplittingAnInBetweenLeavesAnInBetweenOnBothSidesOfTheCut() throws {
        let (manager, _, _) = try interpolated()
        manager.layers[1].cels[1].frameCount = 4
        let want = bytes(of: shown(manager, manager.layers[1].cels[1]))
        XCTAssertFalse(isBlank(shown(manager, manager.layers[1].cels[1])),
                       "Setup: the whole in-between shows a picture")

        manager.splitCel(layerIndex: 1, celIndex: 1, atFrame: 6)
        XCTAssertEqual(manager.layers[1].cels.count, 4)
        let halves = [("left", manager.layers[1].cels[1]), ("right", manager.layers[1].cels[2])]
        XCTAssertEqual(halves.map { $0.1.startFrame }, [4, 6], "Setup: the cut landed where it was asked to")

        PixelOps.clearRasterizeCache()
        for (name, half) in halves {
            let derived = try XCTUnwrap(manager.derivedCelContent(for: half, atFrame: half.startFrame),
                                        "the \(name) half still derives a picture")
            let got = PixelOps.rasterize(cel: half, canvasSize: size, derived: derived)
            XCTAssertFalse(isBlank(got), "the \(name) half is not blank")
            XCTAssertEqual(bytes(of: got), want, "the \(name) half shows what the whole cel showed")
        }
    }

    /// The half that is not new keeps the original cel id, so a recipe elsewhere in the document that
    /// references the split cel still resolves — which is why nothing needs retargeting across a cut.
    func testTheSurvivingHalfOfASplitKeepsTheCelIdReferencesAreHeldBy() throws {
        let (manager, _, _) = try interpolated()
        manager.layers[1].cels[1].frameCount = 4
        let wasID = manager.layers[1].cels[1].id

        manager.splitCel(layerIndex: 1, celIndex: 1, atFrame: 6)
        XCTAssertEqual(manager.layers[1].cels[1].id, wasID)
        XCTAssertNotEqual(manager.layers[1].cels[2].id, wasID)
    }
}
