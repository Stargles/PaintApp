import XCTest
import UIKit
import CoreGraphics

/// **Move, on a frame where the drawing is not where it is stored** — the owner's report of
/// 2026-09-03: *"There seems to be a bug when trying to move an object from A to B, then try to
/// select it in an inbetween, it does not let you. If it is a keyframe, then reselecting that object
/// and moving it [works]."*
///
/// That was two defects standing one behind the other, and fixing either alone is worse than fixing
/// neither.
///
/// 1. **The refusal.** `activeVectorMoveTarget` guarded on `celPoseIsResting` and returned nil, and
///    both lifts turned that into a bare `return false` — no notice, no message, a button that does
///    nothing. Every in-between of an animated object is a non-resting frame, so Move was dead on all
///    of them.
/// 2. **The rest-space blindness underneath it.** `VectorCanvas.elements` holds the drawing at rest
///    and `CanvasManager.posed(_:through:)` is what the artist is looking at. Relaxing (1) without
///    (2) trades a silent no-op for a silently *wrong* selection: a loop drawn around visible ink
///    tests against geometry that is somewhere else, so it catches the wrong elements — or, as
///    `testALoopAroundThePosedInkCatchesItAndALoopAroundWhereItRestsDoesNot` shows, exactly the
///    inverse of what the artist drew around.
///
/// **Every test here goes red against the code as it stood before this pass**, and the two halves go
/// red for different reasons — (1)'s tests refuse to lift at all, (2)'s lift and catch the wrong ink.
/// The pre-existing `TransformChannelLogicTests.testMoveIsRefusedAtAFrameThePoseDoesNotRestAt` pinned
/// (1) *as a feature*; it is replaced rather than deleted, by the test of the same shape one file
/// over that now asserts the lift succeeds.
///
/// Pure logic, no simulator: `beginVectorWholeCelMove` / `beginVectorLassoMove` / `nudgeVectorFloat`
/// / `commitVectorFloatIfNeeded` are the seams the toolbar and the transform overlay drive.
final class PosedLassoMoveLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// A manager with a raster layer at 0 and an **active vector layer at 1**, whose cel spans frames
    /// 0..<16 so there is room either side of a pose key.
    private func fixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        manager.layers[layerIndex].cels[0].startFrame = 0
        manager.layers[layerIndex].cels[0].frameCount = 16
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    private func stroke(from a: CGPoint, to b: CGPoint, size: CGFloat = 4) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: size, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)])
    }

    private func loop(_ rect: CGRect) -> CGPath { CGPath(rect: rect, transform: nil) }

    private func select(_ manager: CanvasManager, _ layerIndex: Int, _ path: CGPath) {
        manager.selection = Selection(path: path, bounds: path.boundingBoxOfPath,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
    }

    private func movedBy(_ manager: CanvasManager, dx: CGFloat, dy: CGFloat) -> LayerTransform {
        guard var transform = manager.vectorFloat?.frame.transform else { return .identity }
        transform.position = CGPoint(x: transform.position.x + dx, y: transform.position.y + dy)
        return transform
    }

    /// The reference box every pose in this file is measured against. Only a frame of reference —
    /// `Homography(rect:to:)` recovers the same affine from any non-degenerate one.
    private var box: CGRect { CGRect(x: 4, y: 24, width: 32, height: 12) }

    /// A cel channel that slides the drawing `dx` to the right between cel-local 0 and 12, **linearly**
    /// so an in-between is a plain fraction of the travel and this file's arithmetic is hand-checkable.
    private func animate(_ manager: CanvasManager, _ layerIndex: Int, dx: CGFloat) {
        manager.layers[layerIndex].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 12, pose: PoseQuad(box: box,
                                                             mappedBy: .init(translationX: dx, y: 0)),
                                   interpolation: .linear)])
        ]
    }

    /// The x of every stroke sample in a display list, in order — the cheapest honest reading of
    /// "where is the drawing".
    private func sampleXs(_ elements: [VectorElement]) -> [CGFloat] {
        elements.compactMap(\.stroke).flatMap { $0.samples.map(\.x) }
    }

    private func sampleYs(_ elements: [VectorElement]) -> [CGFloat] {
        elements.compactMap(\.stroke).flatMap { $0.samples.map(\.y) }
    }

    /// Two coordinate lists compared elementwise to a tolerance. `XCTAssertEqual`'s `accuracy` arm
    /// takes scalars only, and every number in this file is the far end of a pose blend, a matrix
    /// inversion and a conjugation — comparing them for bit equality would pin floating point rather
    /// than behaviour.
    private func assertXs(_ actual: [CGFloat], _ expected: [CGFloat], accuracy: CGFloat = 1e-6,
                          _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, message, file: file, line: line)
        guard actual.count == expected.count else { return }
        for (index, pair) in zip(actual, expected).enumerated() {
            XCTAssertEqual(pair.0, pair.1, accuracy: accuracy,
                           "\(message) [\(index)]", file: file, line: line)
        }
    }

    /// What the artist is actually looking at on this cel at this frame — the same derivation the
    /// renderer takes (`CanvasManager.posedCelContent` calls `posed(_:through:)` with these mappings),
    /// asked for its geometry instead of its pixels.
    private func displayed(_ manager: CanvasManager, _ layerIndex: Int) -> [VectorElement] {
        let cel = manager.layers[layerIndex].cels[0]
        let mappings = CanvasManager.poseMappings(cel.transformTracks,
                                                  atCelLocalFrame: manager.currentFrame - cel.startFrame)
        return CanvasManager.posed(cel.vector?.elements ?? [], through: mappings)
    }

    /// The map the cel channel resolves to at the playhead, asserted rather than assumed — every
    /// number below is measured off this, so a change in `PoseInterpolation` shows up here as a
    /// precondition failure instead of as a mysterious off-by-a-few somewhere downstream.
    private func celMap(_ manager: CanvasManager, _ layerIndex: Int) throws -> CGAffineTransform {
        let cel = manager.layers[layerIndex].cels[0]
        return try XCTUnwrap(cel.transformTracks[TransformChannelID.cel.id]?
            .mapping(atCelLocalFrame: manager.currentFrame - cel.startFrame))
    }

    // MARK: - The refusal that is gone

    /// **Move lifts at an in-between of a pose, and its box is around the drawing on screen.**
    ///
    /// The first assertion is the owner's report directly: before this pass `beginVectorWholeCelMove`
    /// returned false here and said nothing.
    ///
    /// The second is why the refusal existed and why removing it alone would not have been enough.
    /// `activeVectorMoveTarget`'s deleted comment made the argument itself — *"the artist would be
    /// dragging a box that is not around the drawing they can see"* — because `MoveBoxInk` was
    /// measured on `vector.elements`, which is the drawing at **rest**. So this pins the box's centre
    /// against the posed position, and it goes red both against the old refusal (nothing lifts) and
    /// against a relaxation that forgot to move the measurement (`pivot.x` short by the whole pose).
    func testAWholeCelMoveLiftsAtAPosedInBetweenAndItsBoxIsAroundTheDrawingOnScreen() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        animate(manager, layerIndex, dx: 40)
        manager.currentFrame = 6

        let map = try celMap(manager, layerIndex)
        XCTAssertEqual(map.tx, 20, accuracy: 1e-6, "Setup: half way along a 40pt linear slide")
        XCTAssertEqual(map.ty, 0, accuracy: 1e-6)
        let rest = try XCTUnwrap(CanvasManager.localBounds(of: vector.elements))

        XCTAssertTrue(manager.beginVectorWholeCelMove(),
                      "Move at an in-between of a pose used to refuse, and to say nothing about it")
        let float = try XCTUnwrap(manager.vectorFloat)
        XCTAssertEqual(float.pivot.x, rest.midX + 20, accuracy: 1e-6,
                       "the handles go around the drawing the artist can see, not around where it is stored")
        XCTAssertEqual(float.pivot.y, rest.midY, accuracy: 1e-6)
        XCTAssertEqual(float.contentSize.width, rest.width, accuracy: 1e-6,
                       "…and a pure translation changes the box's size by nothing")
        manager.cancelVectorFloat()
    }

    /// **A cel whose pose *rests* at this frame carries no pose on its float**, so every consumer of
    /// `VectorFloat.poses` takes its empty fast path.
    ///
    /// Not a definition: it is `TransformTrack.mapping`'s "nil for a resting pose" rule reaching all
    /// the way through `celPoseMaps` to the float, which is what keeps a document that has been
    /// keyframed but is sitting on its first key byte-for-byte the document it was.
    func testAFloatLiftedWhereThePoseRestsCarriesNoPoseAtAll() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        animate(manager, layerIndex, dx: 40)
        manager.currentFrame = 0

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        let float = try XCTUnwrap(manager.vectorFloat)
        XCTAssertTrue(float.poses.isEmpty, "frame 0 holds the rest pose, so there is nothing to carry")
        let rest = try XCTUnwrap(CanvasManager.localBounds(of: float.elementsBeforeLift))
        XCTAssertEqual(float.pivot.x, rest.midX, accuracy: 1e-9)
        manager.cancelVectorFloat()
    }

    /// **A document with no pose channel at all carries none either** — the safety property, checked
    /// at the float rather than assumed from the one above.
    func testAFloatOnAnUnkeyframedCelCarriesNoPose() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        manager.currentFrame = 5

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        XCTAssertTrue(try XCTUnwrap(manager.vectorFloat).poses.isEmpty)
        manager.cancelVectorFloat()
    }

    // MARK: - Which space the loop is asked in

    /// **A loop around the posed ink catches it; a loop around where that ink is *stored* catches
    /// nothing.** The membership half of the defect, and the pair is what makes it a statement about
    /// *space* rather than about *catching*.
    ///
    /// The stroke rests over x 6…22 and the pose slides it 20pt right, so on screen it is over
    /// x 26…42. The two loops below are disjoint and each contains exactly one of those spans. Three
    /// distinguishable outcomes:
    ///
    ///  * **Before this pass** — the first `beginVectorLassoMove` returns false, because Move refused
    ///    a posed frame outright.
    ///  * **With the refusal relaxed and nothing else** — the answers come back *swapped*: the loop
    ///    the artist drew around their drawing catches nothing and the loop drawn over blank paper
    ///    lifts the stroke. That is the silently-wrong selection the two fixes have to land together
    ///    to avoid, and it is strictly worse than the refusal.
    ///  * **Now** — as written.
    func testALoopAroundThePosedInkCatchesItAndALoopAroundWhereItRestsDoesNot() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        animate(manager, layerIndex, dx: 40)
        manager.currentFrame = 6
        XCTAssertEqual(try celMap(manager, layerIndex).tx, 20, accuracy: 1e-6, "Setup")
        assertXs(sampleXs(displayed(manager, layerIndex)), [26, 34, 42],
                 "Setup: this is where the drawing is on screen")

        select(manager, layerIndex, loop(CGRect(x: 24, y: 10, width: 24, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove(),
                      "a loop around the ink the artist can see has to catch that ink")
        XCTAssertEqual(manager.vectorFloat?.insideIDs.count, 1)
        manager.cancelVectorFloat()

        select(manager, layerIndex, loop(CGRect(x: 2, y: 10, width: 22, height: 40)))
        XCTAssertFalse(manager.beginVectorLassoMove(),
                       "and a loop over blank paper catches nothing, however much stored geometry sits under it")
        XCTAssertNil(manager.vectorFloat)
    }

    /// The same question asked of the *cut*, which is the arm that changes geometry rather than
    /// merely classifying it: a loop across the middle of the posed ink splits the stroke where the
    /// artist drew the line, and both halves come back in **rest** coordinates.
    ///
    /// The split has to happen on stored geometry — a stroke cut in posed space would have to be
    /// mapped back sample by sample — which is why the loop is pulled back rather than the ink pushed
    /// forward. This is what pins that the pull-back is exact and not merely approximately placed.
    func testACutAtAPosedFrameFallsWhereTheArtistDrewItAndLeavesRestCoordinatesBehind() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        animate(manager, layerIndex, dx: 40)
        manager.currentFrame = 6
        assertXs(sampleXs(displayed(manager, layerIndex)), [26, 34, 42], "Setup")

        // A loop covering the right two of the three posed samples (34 and 42) and not the left one.
        select(manager, layerIndex, loop(CGRect(x: 30, y: 10, width: 30, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        let float = try XCTUnwrap(manager.vectorFloat)

        XCTAssertEqual(vector.elements.count, 2, "one stroke in, two out")
        let inside = sampleXs(vector.elements.filter { float.insideIDs.contains($0.id) })
        let outside = sampleXs(vector.elements.filter { !float.insideIDs.contains($0.id) })
        // `membershipRuns` bisects the crossing and gives it to both halves, so each run carries it.
        XCTAssertEqual(inside.first ?? .nan, 10, accuracy: 1e-4,
                       "the cut fell at the loop's edge pulled back into rest space — canvas 30 less the 20pt pose")
        XCTAssertEqual(inside.last ?? .nan, 22, accuracy: 1e-9,
                       "and the travelling half runs to the far end of the stroke")
        XCTAssertEqual(outside.first ?? .nan, 6, accuracy: 1e-9)
        XCTAssertEqual(outside.last ?? .nan, 10, accuracy: 1e-4)
        manager.cancelVectorFloat()
    }

    // MARK: - Which space the gesture is in

    /// **A drag moves the drawing on screen by exactly the drag**, on a cel whose pose is a *scale* —
    /// which is the case that tells a conjugated delta apart from a raw one.
    ///
    /// Rest geometry `r` is shown at `r·P`; dropping it at `r·P·D` means storing `r·P·D·P⁻¹`
    /// (`CanvasManager.restDelta`). Under a 2× pose a raw `D` of 30pt would store 30 and *display* 60,
    /// so the drawing would run away from the finger at twice its speed — which is exactly the class
    /// of wrongness the old refusal was protecting against and the reason relaxing it is not a
    /// one-line change. A pure *translation* pose cannot see this at all, because a translation
    /// commutes with a translation; that is why this fixture scales.
    func testANudgeAtAPosedFrameMovesTheDrawingOnScreenByExactlyTheGesture() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 12), to: CGPoint(x: 14, y: 12)))
        // One key, held constant across the cel: the map is exactly 2× about the canvas origin at
        // every frame, with no interpolation in the way.
        manager.layers[layerIndex].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(box: box, mappedBy: .init(scaleX: 2, y: 2)))])
        ]
        manager.currentFrame = 4
        let map = try celMap(manager, layerIndex)
        XCTAssertEqual(map.a, 2, accuracy: 1e-6, "Setup: a 2× pose, not a translation")
        XCTAssertEqual(map.tx, 0, accuracy: 1e-6)

        let before = sampleXs(displayed(manager, layerIndex))
        assertXs(before, [12, 20, 28], "Setup: the drawing on screen is twice where it rests")

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 30, dy: 0))

        assertXs(sampleXs(displayed(manager, layerIndex)), before.map { $0 + 30 },
                 "the ink follows the finger; a raw delta would have moved it 60")
        assertXs(sampleYs(displayed(manager, layerIndex)), [24, 24, 24],
                 "and nothing moved on the other axis")
        assertXs(sampleXs(vector.elements), [21, 25, 29],
                 "what is *stored* is the conjugate — half the screen delta under a 2× pose")
        manager.cancelVectorFloat()
    }

    // MARK: - What a committed Move at an in-between means

    /// **A committed Move at an in-between of an animated channel writes a pose key on that frame**,
    /// leaves the stored drawing exactly where it was, and leaves the keys either side alone.
    ///
    /// **This is KEYFRAMES.md §2.27 rather than a choice made here**, and the owner's own words settle
    /// it: *"if the current frame is a keyframe, then the value gets updated on that keyframe. If it
    /// isnt a current keyframe the drag creates a keyframe at that frame. This only happens when the
    /// value is already being animated."* An object moved from A to B is an animated channel by
    /// construction, so a Move at an in-between of it takes `KeyframeControl.Write.key` — the arm that
    /// already existed and that `activeVectorMoveTarget`'s refusal made unreachable at every frame
    /// where a pose is actually doing something. The alternative — editing the rest geometry, so the
    /// object moves at *every* frame — is not on the table: §2.5 ruled that the cel holds one drawing
    /// in its rest position and the keys hold the poses, which is what `.key` implements by taking the
    /// bake back.
    ///
    /// **The key is the composition, not the gesture.** At frame 6 the channel already maps by +20;
    /// dragging 9pt further means the frame's pose is +29, because what the artist moved was the ink
    /// at its posed position. Writing the raw +9 would snap the drawing 20pt left the instant they let
    /// go — visible, and the reason this asserts the number rather than merely that a key exists.
    func testACommitAtAPosedInBetweenKeysThatFrameWithTheComposedPose() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        animate(manager, layerIndex, dx: 40)
        manager.currentFrame = 6
        XCTAssertEqual(try celMap(manager, layerIndex).tx, 20, accuracy: 1e-6, "Setup")
        let restBefore = sampleXs(vector.elements)

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 9, dy: 0))
        XCTAssertTrue(manager.commitVectorFloatIfNeeded())

        let track = try XCTUnwrap(manager.layers[layerIndex].cels[0]
            .transformTracks[TransformChannelID.cel.id])
        XCTAssertEqual(track.keys.map(\.frame), [0, 6, 12],
                       "the drag created a keyframe at the frame it happened on (§2.27)")
        assertXs(sampleXs(vector.elements), restBefore,
                 "and took the bake back: the cel still holds one drawing in its rest position (§2.5)")
        XCTAssertEqual(try celMap(manager, layerIndex).tx, 29, accuracy: 1e-6,
                       "the key holds where the artist left it — the pose it already had plus the drag")
        assertXs(sampleXs(displayed(manager, layerIndex)), restBefore.map { $0 + 29 },
                 "which is to say the drawing did not move when they let go")

        // Asked of the keys rather than of `celMap`, because a resting pose resolves to *no* mapping
        // at all (`TransformTrack.mapping`'s nil-for-resting rule) and "no answer" is the assertion.
        XCTAssertTrue(try XCTUnwrap(track.key(atFrame: 0)).pose.isIdentity,
                      "keyframe A is untouched — it still rests")
        manager.currentFrame = 12
        XCTAssertEqual(try celMap(manager, layerIndex).tx, 40, accuracy: 1e-6, "and so is keyframe B")
    }

    /// The whole of it end to end, in the owner's own order: animate A→B, scrub to an in-between,
    /// move the object, and it is still one animation — three keys, one channel, one drawing.
    ///
    /// It exists beside the test above because that one asks about the *model* and this one asks the
    /// question the report asked: after the move, is the object where it was put on every frame it
    /// was not moved on?
    func testMovingAnObjectAtAnInBetweenLeavesTheFramesEitherSideWhereTheyWere() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        animate(manager, layerIndex, dx: 40)

        manager.currentFrame = 6
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 0, dy: -7))
        XCTAssertTrue(manager.commitVectorFloatIfNeeded())

        assertXs(sampleYs(displayed(manager, layerIndex)), [23, 23, 23],
                 "the frame that was moved holds the move")
        assertXs(sampleXs(displayed(manager, layerIndex)), [26, 34, 42],
                 "…and holds its horizontal travel, because the drag was vertical")
        manager.currentFrame = 0
        assertXs(sampleXs(displayed(manager, layerIndex)), [6, 14, 22], "keyframe A is where it was")
        assertXs(sampleYs(displayed(manager, layerIndex)), [30, 30, 30], "…on both axes")
        manager.currentFrame = 12
        assertXs(sampleXs(displayed(manager, layerIndex)), [46, 54, 62], "and so is keyframe B")
        assertXs(sampleYs(displayed(manager, layerIndex)), [30, 30, 30])
        // **The frames between the keys are not asserted, and that is a finding rather than a gap.**
        // Placing a key at 6 re-parameterises the segments either side of it — the timing spine gains
        // an index and the new key begins a `.bezier` segment where a `.linear` one used to run
        // through — so frame 9's x measures 38.5 where the two-key curve put it at 36. That is what
        // authoring a keyframe *means*; asserting the old easing would pin the absence of the key the
        // artist just made.
    }

    /// **Undoing a Move at an in-between walks back the way it was made: the key first, then the
    /// drag.** Two presses, and the intermediate state is a real one rather than a torn half.
    ///
    /// §5.5 rules one undo step per *nudge*, and §2.5 puts the pose write at the *commit*, so a
    /// one-drag Move is two steps by construction. The property that matters is that neither press
    /// leaves the document incoherent: the first takes the key and the geometry it restored back
    /// together (`keyPoseRestoringRest` records them as one entry precisely so an undo cannot leave
    /// the key without the drawing), landing on exactly the state the drag left; the second takes the
    /// drag. Asserted here because posing the float is what made this path reachable at an in-between
    /// at all, and a half-undone pose channel is invisible until an artist scrubs.
    func testUndoingAMoveAtAnInBetweenWalksBackTheKeyThenTheDrag() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        animate(manager, layerIndex, dx: 40)
        manager.currentFrame = 6
        let restBefore = sampleXs(vector.elements)

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 9, dy: 0))
        XCTAssertTrue(manager.commitVectorFloatIfNeeded())
        XCTAssertEqual(manager.layers[layerIndex].cels[0]
            .transformTracks[TransformChannelID.cel.id]?.keys.count, 3)

        manager.undo()
        XCTAssertEqual(manager.layers[layerIndex].cels[0]
            .transformTracks[TransformChannelID.cel.id]?.keys.map(\.frame), [0, 12],
                       "the first press takes the key back")
        assertXs(sampleXs(vector.elements), restBefore.map { $0 + 9 },
                 "…together with the rest geometry the key's arm had restored, so this is the state the drag left")

        manager.undo()
        assertXs(sampleXs(vector.elements), restBefore, "the second press takes the drag")
        assertXs(sampleXs(displayed(manager, layerIndex)), restBefore.map { $0 + 20 },
                 "so the drawing is exactly where it was before the Move")
        XCTAssertNil(manager.vectorFloat, "and the float went with it — the first nudge carries the lift")
    }

    // MARK: - The other silent refusal

    /// **An interpolated in-between still refuses, and now it says so.**
    ///
    /// A derived cel has no display list of its own to split and the write would land on a
    /// `VectorCanvas` the displayed image is not computed from, so the refusal is right and stays.
    /// What was wrong is that it was invisible: `TopToolbar.toggleMove` guarded and returned, and so
    /// did `activeVectorMoveTarget`, and the artist got a button that did nothing. That is §5.24's own
    /// argument — a tool that does nothing and says nothing reads as broken — and it arrived in the
    /// same report as the pose refusal beside it.
    func testMoveOnAnInterpolatedInBetweenRefusesOutLoud() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        manager.layers[layerIndex].cels[0].interpolation = InterpolationRecipe(references: [], t: 0.5)

        XCTAssertFalse(manager.beginVectorWholeCelMove())
        XCTAssertNil(manager.vectorFloat)
        XCTAssertEqual(manager.notice?.kind, .cannotMoveDerivedFrame,
                       "a refusal the artist cannot see is the defect, not the refusal")

        manager.notice = nil
        select(manager, layerIndex, loop(CGRect(x: 2, y: 10, width: 56, height: 40)))
        XCTAssertFalse(manager.beginVectorLassoMove(), "and the lasso arm goes through the same door")
        XCTAssertEqual(manager.notice?.kind, .cannotMoveDerivedFrame)
    }

    // MARK: - What a cut owes an animation group

    /// **Both halves of a cut fill keep the parent's animation group.**
    ///
    /// A stroke's halves get it for free — `piece(of:)` copies the parent value whole — but a fill's
    /// halves are rebuilt from four fields, so before this pass a lasso that cut a fill dropped it out
    /// of the channel that was animating it. Nothing went red and nothing was drawn wrong at the frame
    /// of the cut; the fill simply stopped moving with everything around it. §3.4 rules membership to
    /// be a field on the element for exactly the reason this breaks it: a fresh id is what tells two
    /// halves apart, and the group is what says they are still the same drawing.
    func testBothHalvesOfACutFillKeepTheAnimationGroupTheParentWasIn() throws {
        let (_, _, vector) = fixture()
        let group = UUID()
        var fill = VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 40, height: 40),
                                                  transform: nil),
                                     color: black())
        fill.animationGroupID = group
        vector.elements = [.fill(fill)]

        let split = try XCTUnwrap(vector.splitForLassoMove(
            insideLocalPath: loop(CGRect(x: 24, y: 0, width: 40, height: 64))))
        XCTAssertEqual(split.elements.count, 2, "Setup: the loop actually cut it")
        XCTAssertEqual(Set(split.elements.compactMap { $0.fill?.animationGroupID }), [group],
                       "a cut piece is still the same drawing, and still in the same animation")
        XCTAssertEqual(Set(split.elements.map(\.id)).count, 2, "…while still being two elements")
    }
}
