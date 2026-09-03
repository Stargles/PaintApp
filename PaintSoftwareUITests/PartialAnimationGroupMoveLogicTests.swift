import XCTest
import UIKit
import CoreGraphics

/// **A Move may not tear an animation group in half** — the owner's ruling of 2026-09-03: *"Lets say
/// animation A is a movement of a selection to a location. Now if you select half of the selection,
/// then it shouldn't allow you to move it because that would break things."*
///
/// ## The defect these tests were written against
///
/// A group's members are carried by **one** pose channel, so a key written for it moves every one of
/// them. `existingAnimationChannel` reuses a group as soon as every element the lasso *caught* shares
/// it, and never asked whether the group had members the loop had missed. So a half-lasso of an
/// animated group routed straight onto that group's channel, and `commitTransformPose`'s `.key` arm
/// then put the pre-lift display list back (`keyPoseRestoringRest`) and keyed the whole thing. The
/// artist dragged half a drawing and all of it moved, with nothing said. The agent that built posed
/// Move flagged it and left it; this is the refusal the owner ruled for.
///
/// ## What every test here has to assert, and why the `Bool` alone would not do it
///
/// The old path **returned true and then moved the whole group**, so a test that read only
/// `beginVectorLassoMove()`'s answer would go green against code that refuses *and* moves. Every test
/// below therefore drives the whole gesture the artist's finger makes — lift, nudge, commit — and
/// asserts on **where the drawing is**, at the frames either side as well as at the playhead. The
/// three calls are unconditional in both worlds: a refused lift leaves `vectorFloat` nil and the two
/// that follow are no-ops, so the geometry is what tells the two apart rather than the control flow.
///
/// Pure logic, no simulator.
final class PartialAnimationGroupMoveLogicTests: XCTestCase {

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

    private func stroke(from a: CGPoint, to b: CGPoint, group: UUID? = nil,
                        size: CGFloat = 4) -> VectorStroke {
        var stroke = VectorStroke(id: UUID(), brush: BrushLibrary.hardRound, color: black(),
                                  size: size, opacity: 1,
                                  samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                                            VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2,
                                                         pressure: 1),
                                            VectorSample(x: b.x, y: b.y, pressure: 1)])
        stroke.animationGroupID = group
        return stroke
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

    /// **The whole gesture, driven whether or not the lift took.** A refused lift leaves no float, so
    /// `nudgeVectorFloat` and `commitVectorFloatIfNeeded` are no-ops — which is exactly what makes
    /// this safe to call unconditionally and is what lets one shape of test cover the refusal and the
    /// non-refusals alike.
    @discardableResult
    private func lassoMove(_ manager: CanvasManager, dx: CGFloat) -> Bool {
        let lifted = manager.beginVectorLassoMove()
        manager.nudgeVectorFloat(to: movedBy(manager, dx: dx, dy: 0))
        manager.commitVectorFloatIfNeeded()
        return lifted
    }

    /// The reference box the poses below are measured against. Only a frame of reference —
    /// `Homography(rect:to:)` recovers the same affine from any non-degenerate one.
    private var box: CGRect { CGRect(x: 4, y: 26, width: 56, height: 8) }

    /// A **group** channel that slides its members `dx` to the right between cel-local 0 and 12. Key 0
    /// is the rest pose, so the playhead at frame 0 is on a keyframe and the channel resolves to the
    /// identity there — which is the plainest state to read a "did anything move" assertion in.
    private func animateGroup(_ manager: CanvasManager, _ layerIndex: Int, _ group: UUID,
                              dx: CGFloat) {
        manager.animationGroups.append(AnimationGroup(id: group, displayName: "Group 1",
                                                      tagColor: black()))
        manager.layers[layerIndex].cels[0].transformTracks = [
            TransformChannelID.group(group).id: TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 12, pose: PoseQuad(box: box,
                                                             mappedBy: .init(translationX: dx, y: 0)),
                                   interpolation: .linear)])
        ]
    }

    /// The same shape on the **cel** channel, which carries every element on the cel. The narrowing
    /// `testAPartialLassoOnACelAnimatedDrawingIsNotRefused` exists to pin.
    private func animateCel(_ manager: CanvasManager, _ layerIndex: Int, dx: CGFloat) {
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

    /// What the artist is actually looking at on this cel at `frame` — the same derivation the
    /// renderer takes (`CanvasManager.posedCelContent` calls `posed(_:through:)` with these
    /// mappings), asked for its geometry instead of its pixels.
    private func displayedXs(_ manager: CanvasManager, _ layerIndex: Int, at frame: Int) -> [CGFloat] {
        let cel = manager.layers[layerIndex].cels[0]
        let mappings = CanvasManager.poseMappings(cel.transformTracks,
                                                  atCelLocalFrame: frame - cel.startFrame)
        return sampleXs(CanvasManager.posed(cel.vector?.elements ?? [], through: mappings))
    }

    /// Two coordinate lists compared elementwise to a tolerance. `XCTAssertEqual`'s `accuracy` arm
    /// takes scalars only, and every number here is the far end of a pose blend and a matrix
    /// inversion — comparing them for bit equality would pin floating point rather than behaviour.
    private func assertXs(_ actual: [CGFloat], _ expected: [CGFloat], accuracy: CGFloat = 1e-6,
                          _ message: String = "", file: StaticString = #filePath,
                          line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, message, file: file, line: line)
        guard actual.count == expected.count else { return }
        for (index, pair) in zip(actual, expected).enumerated() {
            XCTAssertEqual(pair.0, pair.1, accuracy: accuracy, "\(message) [\(index)]",
                           file: file, line: line)
        }
    }

    /// **Two strokes in one animated group, and a third outside it.**
    ///
    /// The third is load-bearing rather than scenery: without it a lasso around both members is a
    /// lasso around the whole cel, and `existingAnimationChannel` answers `.cel` for that before it
    /// ever looks at a group — so the "the whole group moves" test would be measuring the cel channel
    /// instead of the group it names.
    ///
    /// Rest x: A 6/14/22, B 40/48/56, C 70/78/86, all at y 30 with a 4 pt stroke.
    private func groupFixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas,
                                    group: UUID) {
        let (manager, layerIndex, vector) = fixture()
        let group = UUID()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30), group: group))
        vector.addStroke(stroke(from: CGPoint(x: 40, y: 30), to: CGPoint(x: 56, y: 30), group: group))
        vector.addStroke(stroke(from: CGPoint(x: 70, y: 30), to: CGPoint(x: 86, y: 30)))
        animateGroup(manager, layerIndex, group, dx: 40)
        manager.currentFrame = 0
        return (manager, layerIndex, vector, group)
    }

    private var restXs: [CGFloat] { [6, 14, 22, 40, 48, 56, 70, 78, 86] }

    /// A loop around stroke A alone — half of the animated group.
    private var halfTheGroup: CGPath { loop(CGRect(x: 0, y: 20, width: 30, height: 20)) }
    /// A loop around A and B, the whole group, with C outside it.
    private var allOfTheGroup: CGPath { loop(CGRect(x: 0, y: 20, width: 62, height: 20)) }
    /// A loop around C alone, which is in no group at all.
    private var theUntaggedStroke: CGPath { loop(CGRect(x: 64, y: 20, width: 28, height: 20)) }

    // MARK: - The refusal

    /// **Half an animated group refuses, and the group has not moved afterwards.**
    ///
    /// The last three assertions are the ones with teeth. Against the code as it stood the lift
    /// *succeeded*, so `XCTAssertFalse` alone would be a test of the return value rather than of the
    /// document: the `.key` arm then restored the rest geometry and wrote a pose key of `+25` onto the
    /// group's channel at frame 0, which moves **both** members. Reading the displayed geometry at
    /// frame 0 is what catches that, and reading it at frame 12 is what catches a refusal that
    /// nonetheless damaged the far key.
    func testALassoOverHalfAnAnimatedGroupRefusesAndTheGroupHasNotMoved() throws {
        let (manager, layerIndex, vector, group) = groupFixture()
        select(manager, layerIndex, halfTheGroup)

        XCTAssertFalse(lassoMove(manager, dx: 25),
                       "half of an animated group is not a Move this app will make")
        XCTAssertEqual(manager.notice?.kind, .onlyPartOfAnAnimationGroup,
                       "a refusal the artist cannot see is the defect, not the refusal")
        XCTAssertNil(manager.vectorFloat, "and nothing was lifted")

        assertXs(sampleXs(vector.elements), restXs, "the stored drawing is untouched")
        assertXs(displayedXs(manager, layerIndex, at: 0), restXs,
                 "…and so is what the artist is looking at — this is where the whole group used to move")
        assertXs(displayedXs(manager, layerIndex, at: 12),
                 [46, 54, 62, 80, 88, 96, 70, 78, 86],
                 "and the animation the group already had is exactly as it was")
        XCTAssertEqual(manager.layers[layerIndex].cels[0]
            .transformTracks[TransformChannelID.group(group).id]?.keys.count, 2,
                       "no key was written")
    }

    /// **A loop drawn *through* a member of an animated group refuses too** — the same tear reached by
    /// a narrower door, and the reason the rule is asked against the **post-split** display list.
    ///
    /// Under `.cutting` the lasso splits the stroke into two fresh elements and carries the group tag
    /// onto both (`piece(of:)` copies the parent whole), so the group ends up with a member the loop
    /// did not catch. Asked against the *pre-split* list instead, the ids would be the parent's, the
    /// caught set would be the whole group, and the Move would go ahead and key the channel — moving
    /// the half that stayed behind. So this test is what pins which list the predicate reads.
    func testALoopDrawnThroughAMemberOfAnAnimatedGroupRefusesAndSplitsNothing() throws {
        let (manager, layerIndex, vector) = fixture()
        let group = UUID()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 66, y: 30), group: group))
        animateGroup(manager, layerIndex, group, dx: 40)
        manager.currentFrame = 0
        manager.selectionMembership = .cutting
        select(manager, layerIndex, halfTheGroup)

        XCTAssertFalse(lassoMove(manager, dx: 25))
        XCTAssertEqual(manager.notice?.kind, .onlyPartOfAnAnimationGroup)
        XCTAssertEqual(vector.elements.count, 1,
                       "the split is computed before the check and installed after it, so a refusal cuts nothing")
        assertXs(sampleXs(vector.elements), [6, 36, 66], "and the stroke is where it was")
        // **The assertion that carries this test, and the two above it do not.** The `.key` arm puts
        // the pre-lift list back, so under the old behaviour the stored geometry and the element
        // count read exactly as they do here — the tear is invisible in the *rest* list and lives
        // entirely in the key the commit wrote. This is where it shows: a key of +25 at frame 0 would
        // display the whole stroke, the half that stayed behind included, at 31/61/91.
        assertXs(displayedXs(manager, layerIndex, at: 0), [6, 36, 66],
                 "the drawing has not moved, which is the thing the refusal is for")
        assertXs(displayedXs(manager, layerIndex, at: 12), [46, 76, 106],
                 "with its animation intact")
    }

    // MARK: - The non-refusals, which is where a too-broad rule does its damage

    /// **The whole group lassoed moves, and moves as one.**
    ///
    /// This is the artist's way out of the refusal above, so it has to work — and it is the first
    /// thing a predicate stated one notch too wide ("this Move touches an animated group") would
    /// break. The `.key` arm is what runs here: the drag is taken back out of the geometry and
    /// written onto the channel as a pose at the playhead, which is why the stored list is at rest
    /// and the *displayed* one carries the move.
    func testTheWholeAnimatedGroupLassoedMovesAndTheUntaggedStrokeStaysPut() throws {
        let (manager, layerIndex, vector, group) = groupFixture()
        select(manager, layerIndex, allOfTheGroup)

        XCTAssertTrue(lassoMove(manager, dx: 25), "the whole group is a Move the artist may make")
        XCTAssertNil(manager.notice, "and nothing is refused")

        assertXs(displayedXs(manager, layerIndex, at: 0),
                 [31, 39, 47, 65, 73, 81, 70, 78, 86],
                 "both members carry the drag, and the stroke outside the group does not")
        assertXs(displayedXs(manager, layerIndex, at: 12),
                 [46, 54, 62, 80, 88, 96, 70, 78, 86],
                 "and the far keyframe is where it always was")
        XCTAssertEqual(manager.layers[layerIndex].cels[0]
            .transformTracks[TransformChannelID.group(group).id]?.keys.count, 2,
                       "the key at the playhead was replaced, not added to")
    }

    /// **Ink in no animation group moves, on a cel where a group is animated beside it.**
    ///
    /// The stroke the loop catches carries no tag, so it tears nothing — and a rule that asked "is
    /// anything on this cel animated" rather than "is a group being torn" would refuse it.
    ///
    /// Asserted on the **stored** geometry: this Move mints a channel of its own for the untagged
    /// stroke and takes `.seedAndKey`, which leaves the drag baked where it was made. What matters is
    /// that C travelled and A and B did not.
    func testALassoOverInkInNoAnimationGroupMovesAndLeavesTheGroupAlone() throws {
        let (manager, layerIndex, vector, _) = groupFixture()
        select(manager, layerIndex, theUntaggedStroke)

        XCTAssertTrue(lassoMove(manager, dx: 25))
        XCTAssertNil(manager.notice)

        assertXs(sampleXs(vector.elements), [6, 14, 22, 40, 48, 56, 95, 103, 111],
                 "the untagged stroke moved and the group's two members did not")
        assertXs(displayedXs(manager, layerIndex, at: 12),
                 [46, 54, 62, 80, 88, 96, 70, 78, 86],
                 "and the group's animation still says what it said")
        // C reads 70/78/86 at frame 12 rather than 95/103/111, and that is `.seedAndKey` doing its
        // job rather than a leak: the untagged stroke had no channel, so the commit made one and
        // seeded the *pre-move* pose onto the neighbouring keyframe. What this test is about is the
        // two numbers either side of it — A and B carry their own group's +40 and nothing else.
    }

    /// **Move with no lasso still moves the whole cel, animated group and all.**
    ///
    /// `liftWholeCel` returns every id on the cel, so this lift contains every group's membership by
    /// construction and the rule cannot fire — but `beginVectorWholeCelMove` asks it anyway, so that
    /// there is one statement of the rule rather than two that can drift apart. This test is what
    /// makes that call site honest: broaden the predicate and this goes red.
    func testAWholeCelMoveWithNoLassoStillMovesTheAnimatedGroup() throws {
        let (manager, _, vector, _) = groupFixture()
        manager.selection = nil

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 25, dy: 0))
        XCTAssertTrue(manager.commitVectorFloatIfNeeded())
        XCTAssertNil(manager.notice)

        assertXs(sampleXs(vector.elements), restXs.map { $0 + 25 },
                 "every element on the cel travelled, which is what Move with no selection means")
    }

    /// **A partial lasso on a cel-animated drawing is not refused** — the narrowing this rule needs,
    /// and the one a predicate stated over *channels* rather than over *groups* would get wrong.
    ///
    /// `TransformChannelID.cel`'s membership is every element on the cel, so "the lasso caught some
    /// but not all of a channel's members" would make an animated cel refuse every lasso drawn on it.
    /// It would also be protecting nothing: `existingAnimationChannel` answers `.cel` only for a Move
    /// that carries the whole list, so a partial lasso here mints a group of its own and nests inside
    /// the cel move — a character's arm swinging while the character walks.
    func testAPartialLassoOnACelAnimatedDrawingIsNotRefused() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30)))
        vector.addStroke(stroke(from: CGPoint(x: 40, y: 30), to: CGPoint(x: 56, y: 30)))
        animateCel(manager, layerIndex, dx: 40)
        manager.currentFrame = 0
        select(manager, layerIndex, halfTheGroup)

        XCTAssertTrue(lassoMove(manager, dx: 25), "a cel channel is not a group and carries no membership question")
        XCTAssertNil(manager.notice)
        assertXs(sampleXs(vector.elements), [31, 39, 47, 40, 48, 56],
                 "only the lassoed stroke travelled")
        XCTAssertEqual(manager.animationGroups.count, 1,
                       "and it got a group of its own, nested inside the cel's move")
    }
}
