import XCTest
import UIKit
import CoreGraphics

/// **Adding a selection to an animation group, taking one out, and moving one between two** — TODO
/// (21)'s membership editing, ruled 2026-09-10.
///
/// > *"stay where it looks like on screen for animation groups. […] Along with that, the ability to
/// > add new selections to an animation group (not only from another animation group) and remove
/// > selections from groups will be useful."* — the owner, 2026-09-10.
///
/// ## The two operands every positional test here compares, stated once
///
/// **Where the drawing renders at the frame the artist is standing on, before the edit, against where
/// it renders there after it** — those must be *equal*, and that is the ruling.
///
/// **And where it renders at some *other* frame, before against after** — those must *differ*, and
/// without that second pair every test in this file would pass against an implementation that did
/// nothing at all. That is the whole of why each test reads two frames.
///
/// Both are taken from `displayed(_:at:)` below, which runs the same derivation the renderer runs —
/// `CanvasManager.poseMappings` into `CanvasManager.posed` — and asks it for geometry instead of
/// pixels. **Not the stored list**, which is the operand that would be wrong: the whole point of this
/// feature is that the stored geometry *changes* while the picture does not, so a test that read
/// `vector.elements` at the current frame would assert the opposite of the requirement.
///
/// ## The fixture, and what each number in it is for
///
/// Two animated groups whose motions are on **different axes**, which is what makes "it follows the
/// new group now" a one-number reading rather than an argument: Group A slides +24 in x over the cel's
/// first twelve frames, Group B slides +18 in y over the same twelve. So a stroke that changes group
/// stops travelling sideways and starts travelling down, and no arithmetic slip can turn one into the
/// other.
///
/// **Group A has two members and Group B has one**, deliberately: A's second member is what makes
/// *"the half of the group that stayed behind did not move"* an assertion with something in it, and
/// B's single member is what makes the empty-group edge reachable by removing it.
///
/// **The playhead sits at cel-local frame 6**, halfway, so every channel is mid-blend rather than on a
/// key — the frame at which a compensation that quietly used a key's pose instead of the resolved one
/// would be wrong by half.
///
/// Pure logic, no simulator.
final class AnimationGroupMembershipLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// The reference box the poses are measured against. Only a frame of reference —
    /// `Homography(rect:to:)` recovers the same affine from any non-degenerate one.
    private var box: CGRect { CGRect(x: 2, y: 2, width: 60, height: 60) }

    /// The frame the artist is standing on in every test below, and the one whose picture must not
    /// change. Halfway along both channels.
    private let playhead = 6

    private struct Fixture {
        var manager: CanvasManager
        var layerIndex: Int
        var vector: VectorCanvas
        var groupA: UUID
        var groupB: UUID
        var s1: UUID     // Group A, y 20 — the one that changes group
        var s4: UUID     // Group A, y 30 — the member that stays behind
        var s2: UUID     // Group B, y 20
        var s3: UUID     // no group at all
    }

    private func stroke(from a: CGPoint, to b: CGPoint, group: UUID? = nil,
                        size: CGFloat = 4) -> VectorStroke {
        var stroke = VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(),
                                  size: size, opacity: 1,
                                  samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                                            VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2,
                                                         pressure: 1),
                                            VectorSample(x: b.x, y: b.y, pressure: 1)])
        stroke.animationGroupID = group
        return stroke
    }

    /// A translating group channel: rest at cel-local 0, `by` at cel-local 12, linear between.
    private func animate(_ manager: CanvasManager, _ layerIndex: Int, _ group: UUID,
                         name: String, by: CGVector) {
        manager.animationGroups.append(AnimationGroup(id: group, displayName: name,
                                                      tagColor: black()))
        manager.layers[layerIndex].cels[0].transformTracks[TransformChannelID.group(group).id] =
            TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 12,
                                   pose: PoseQuad(box: box,
                                                  mappedBy: .init(translationX: by.dx, y: by.dy)),
                                   interpolation: .linear)])
    }

    private func fixture() -> Fixture {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        manager.layers[layerIndex].cels[0].startFrame = 0
        manager.layers[layerIndex].cels[0].frameCount = 16
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        let groupA = UUID(), groupB = UUID()
        animate(manager, layerIndex, groupA, name: "Group A", by: CGVector(dx: 24, dy: 0))
        animate(manager, layerIndex, groupB, name: "Group B", by: CGVector(dx: 0, dy: 18))

        let s1 = stroke(from: CGPoint(x: 4, y: 20), to: CGPoint(x: 12, y: 20), group: groupA)
        let s4 = stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 12, y: 30), group: groupA)
        let s2 = stroke(from: CGPoint(x: 30, y: 20), to: CGPoint(x: 38, y: 20), group: groupB)
        let s3 = stroke(from: CGPoint(x: 50, y: 20), to: CGPoint(x: 58, y: 20))
        for element in [s1, s4, s2, s3] { vector.addStroke(element) }
        manager.currentFrame = playhead
        return Fixture(manager: manager, layerIndex: layerIndex, vector: vector,
                       groupA: groupA, groupB: groupB,
                       s1: s1.id, s4: s4.id, s2: s2.id, s3: s3.id)
    }

    // MARK: - Reading the document

    /// A rectangular loop, installed as the selection directly rather than through `finishSelection`,
    /// which clamps to the canvas — `PartialAnimationGroupMoveLogicTests` does the same and for the
    /// same reason.
    private func select(_ f: Fixture, _ rect: CGRect) {
        let path = CGPath(rect: rect, transform: nil)
        f.manager.selection = Selection(path: path, bounds: rect,
                                        layerID: f.manager.layers[f.layerIndex].id,
                                        celID: f.manager.layers[f.layerIndex].cels[0].id)
    }

    /// **The loop that catches S1 where it *looks* at the playhead** — x 13…27 at y 16…24.
    ///
    /// S1 is stored at x 4…12 and Group A is showing it at x 16…24 on frame 6, so this rectangle
    /// contains none of the stored geometry and all of the displayed geometry. That is deliberate and
    /// is LASSO_MOVE.md §5.27's rule pinned in the fixture: a lasso means what it means **on screen**,
    /// and an implementation that skipped the per-element pull-back would catch nothing here.
    private var loopOverS1AsItLooks: CGRect { CGRect(x: 13, y: 16, width: 14, height: 8) }

    /// The same loop over S3, which is in no group and therefore is where it is stored.
    private var loopOverS3: CGRect { CGRect(x: 47, y: 16, width: 14, height: 8) }

    /// The loop over S2, where Group B is showing it at the playhead — y 25…33 rather than 16…24.
    private var loopOverS2AsItLooks: CGRect { CGRect(x: 27, y: 25, width: 14, height: 8) }

    /// **What the artist is looking at**: every sample of one element, carried through exactly the
    /// mappings the renderer carries it through (`CanvasManager.posedCelContent` calls
    /// `posed(_:through:)` with these), asked for its geometry instead of its pixels.
    ///
    /// Returns nil when the element is not on the cel at all, which is a fixture failure rather than a
    /// behaviour and is why every caller unwraps it with a message.
    private func displayed(_ f: Fixture, _ id: UUID, at frame: Int) -> [CGPoint]? {
        let cel = f.manager.layers[f.layerIndex].cels[0]
        let mappings = CanvasManager.poseMappings(cel.transformTracks,
                                                  atCelLocalFrame: frame - cel.startFrame)
        let posed = CanvasManager.posed(cel.vector?.elements ?? [], through: mappings)
        guard let element = posed.first(where: { $0.id == id }), let stroke = element.stroke
        else { return nil }
        return stroke.samples.map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// The stored geometry of one element — the operand for a round trip, and deliberately *not* the
    /// operand for "did the picture change".
    private func stored(_ f: Fixture, _ id: UUID) -> [CGPoint]? {
        guard let stroke = f.vector.elements.first(where: { $0.id == id })?.stroke else { return nil }
        return stroke.samples.map { CGPoint(x: $0.x, y: $0.y) }
    }

    private func group(_ f: Fixture, _ id: UUID) -> UUID? {
        f.vector.elements.first { $0.id == id }?.animationGroupID
    }

    /// Two point lists compared elementwise to a tolerance. `XCTAssertEqual`'s `accuracy` arm takes
    /// scalars only, and every number here is the far end of a pose blend and a matrix inversion —
    /// comparing them for bit equality would pin floating point rather than behaviour.
    ///
    /// Every assertion carries the caller's `message` **and the index**, because a bare
    /// `XCTAssertEqual failed` inside a shared helper names neither the element nor the reason.
    private func assertPoints(_ actual: [CGPoint]?, _ expected: [CGPoint], accuracy: CGFloat = 1e-6,
                              _ message: String, file: StaticString = #filePath,
                              line: UInt = #line) {
        guard let actual else {
            XCTFail("\(message) — the element is not on the cel at all", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.count, expected.count,
                       "\(message) — sample count", file: file, line: line)
        guard actual.count == expected.count else { return }
        for (index, pair) in zip(actual, expected).enumerated() {
            XCTAssertEqual(pair.0.x, pair.1.x, accuracy: accuracy,
                           "\(message) — x of sample \(index)", file: file, line: line)
            XCTAssertEqual(pair.0.y, pair.1.y, accuracy: accuracy,
                           "\(message) — y of sample \(index)", file: file, line: line)
        }
    }

    private func points(_ xs: [CGFloat], y: CGFloat) -> [CGPoint] {
        xs.map { CGPoint(x: $0, y: y) }
    }

    // MARK: - Move: one group to another

    /// **A drawing moved from one animated group to another is exactly where it was on this frame, and
    /// somewhere else on every other.**
    ///
    /// The operands, in order:
    ///
    ///  1. S1's displayed samples at frame 6 **before** the edit against the same **after** — equal.
    ///     This is the owner's ruling and it is the assertion the whole feature exists for.
    ///  2. S1's displayed samples at frame 12 before against after — different, and specifically
    ///     Group B's motion rather than Group A's: it has stopped travelling in x and started
    ///     travelling in y. Without this an implementation that returned `true` and wrote nothing
    ///     would pass assertion 1.
    ///  3. S4's displayed samples at both frames, before against after — equal at both. S4 is the half
    ///     of Group A the loop did not catch, and this is what says the edit reached one element and
    ///     not the channel.
    ///  4. The stored `animationGroupID`, which is what actually changed.
    func testMovingADrawingBetweenGroupsKeepsItWhereItLooksAndChangesWhereItGoes() throws {
        let f = fixture()
        // Frame 6: Group A shows S1 at +12 in x; Group B shows S2 at +9 in y.
        let before6 = try XCTUnwrap(displayed(f, f.s1, at: 6), "fixture: S1 is on the cel")
        assertPoints(before6, points([16, 20, 24], y: 20),
                     "fixture: Group A shows S1 twelve to the right at the halfway frame")
        assertPoints(displayed(f, f.s1, at: 12), points([28, 32, 36], y: 20),
                     "fixture: and twenty-four to the right at the far key")

        select(f, loopOverS1AsItLooks)
        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.existing(f.groupB)),
                      "the loop holds S1 where it looks, so the edit goes through")

        // (1) The ruling.
        assertPoints(displayed(f, f.s1, at: 6), before6,
                     "S1 has not moved on the frame the artist is standing on")
        // (2) …and it is following Group B now: down eighteen at the far key, not right twenty-four.
        assertPoints(displayed(f, f.s1, at: 12), points([16, 20, 24], y: 29),
                     "S1 travels in y with Group B at the far key, where it used to travel in x")
        assertPoints(displayed(f, f.s1, at: 0), points([16, 20, 24], y: 11),
                     "and at the near key it is where Group B's rest pose puts it")
        // (3) The half of Group A the loop did not catch is untouched at both frames.
        assertPoints(displayed(f, f.s4, at: 6), points([16, 20, 24], y: 30),
                     "S4 stayed in Group A and is still where Group A puts it at the playhead")
        assertPoints(displayed(f, f.s4, at: 12), points([28, 32, 36], y: 30),
                     "…and at the far key, so the edit touched an element and not the channel")
        // (4) What actually changed.
        XCTAssertEqual(group(f, f.s1), f.groupB, "S1 is in Group B now")
        XCTAssertEqual(group(f, f.s4), f.groupA, "and S4 is still in Group A")
        XCTAssertEqual(f.manager.notice?.code, "animationGroupMoved",
                       "an edit whose only visible effect is that nothing moved has to say what it did")
    }

    /// **A loop drawn where the ink is *stored* rather than where it looks catches nothing** —
    /// LASSO_MOVE.md §5.27, and the narrowing that makes the test above mean what it says.
    ///
    /// Two operands: the verb's own answer (false), and S1's displayed samples at the playhead before
    /// against after (equal, because nothing happened). The first alone would pass against a verb that
    /// refused everything.
    func testALoopWhereTheInkIsStoredRatherThanShownCatchesNothing() throws {
        let f = fixture()
        let before = try XCTUnwrap(displayed(f, f.s1, at: 6), "fixture: S1 is on the cel")
        select(f, CGRect(x: 1, y: 16, width: 14, height: 8))   // S1's *stored* x 4…12

        XCTAssertFalse(f.manager.setAnimationGroupOfSelection(.existing(f.groupB)),
                       "the loop is over bare paper at this frame, so there is nothing to re-group")
        XCTAssertEqual(group(f, f.s1), f.groupA, "S1 is still in Group A")
        assertPoints(displayed(f, f.s1, at: 6), before, "and nothing moved")
    }

    // MARK: - Add: untagged ink into a group

    /// **Ink in no group at all joins one, stays where it looks, and starts following it.**
    ///
    /// This is the half of the owner's ask that the item used *not* to be about — *"the ability to add
    /// new selections to an animation group (not only from another animation group)"*.
    ///
    /// Operands: S3 at frame 6 before against after (equal); S3 at frame 12 before against after
    /// (different — it used to sit still at every frame, and now it travels Group A's +24).
    func testUntaggedInkAddedToAnAnimatedGroupStaysPutHereAndTravelsThere() throws {
        let f = fixture()
        let before6 = try XCTUnwrap(displayed(f, f.s3, at: 6), "fixture: S3 is on the cel")
        assertPoints(before6, points([50, 54, 58], y: 20), "fixture: S3 is in no group and sits still")
        assertPoints(displayed(f, f.s3, at: 12), points([50, 54, 58], y: 20),
                     "fixture: …at every frame, which is what makes the after-reading mean something")

        select(f, loopOverS3)
        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.existing(f.groupA)),
                      "untagged ink can join a group")

        assertPoints(displayed(f, f.s3, at: 6), before6,
                     "S3 has not moved on the frame the artist is standing on")
        assertPoints(displayed(f, f.s3, at: 12), points([62, 66, 70], y: 20),
                     "and it travels Group A's remaining twelve between here and the far key")
        assertPoints(stored(f, f.s3), points([38, 42, 46], y: 20),
                     "which it does by having been rewritten twelve to the left in rest space")
        XCTAssertEqual(group(f, f.s3), f.groupA, "S3 is in Group A")
        XCTAssertEqual(f.manager.notice?.code, "animationGroupJoined")
    }

    // MARK: - Remove: out of a group

    /// **A drawing taken out of its group stands still where it stood.**
    ///
    /// Operands: S1 at frame 6 before against after (equal); S1 at frames 0 and 12 before against
    /// after (different — it used to travel Group A's whole +24 and now it does not move at all).
    func testRemovingADrawingFromItsGroupLeavesItStandingWhereItStood() throws {
        let f = fixture()
        let before6 = try XCTUnwrap(displayed(f, f.s1, at: 6), "fixture: S1 is on the cel")
        select(f, loopOverS1AsItLooks)

        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.none), "a selection can leave its group")

        assertPoints(displayed(f, f.s1, at: 6), before6, "S1 is where it was on this frame")
        assertPoints(displayed(f, f.s1, at: 0), before6,
                     "and it is in the same place at the near key, where Group A used to hold it back")
        assertPoints(displayed(f, f.s1, at: 12), before6,
                     "and at the far key, where Group A used to have carried it twelve further")
        XCTAssertNil(group(f, f.s1), "S1 is in no group")
        XCTAssertEqual(group(f, f.s4), f.groupA, "and Group A still has the member it had")
        XCTAssertEqual(f.manager.notice?.code, "animationGroupLeft")
    }

    /// **The last member leaving keeps the group and keeps its track** — the empty-group edge, decided.
    ///
    /// The alternative is to delete the registry entry and the channel once nothing is in them, and it
    /// destroys an authored animation on a verb the artist reached for to move one drawing. Keeping it
    /// is `Layer.valueFill`'s asymmetry (§3.5) and it is what makes the round trip below exact.
    ///
    /// Operands: the registry's contents and the channel's key count, before against after — both
    /// unchanged — against the membership, which is what changed.
    func testRemovingTheLastMemberKeepsTheGroupAndItsTrack() throws {
        let f = fixture()
        let keysBefore = f.manager.layers[f.layerIndex].cels[0]
            .transformTracks[TransformChannelID.group(f.groupB).id]?.keys.count
        XCTAssertEqual(keysBefore, 2, "fixture: Group B is animated")

        select(f, loopOverS2AsItLooks)
        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.none))

        XCTAssertNil(group(f, f.s2), "Group B has no members on this cel now")
        XCTAssertTrue(f.manager.animationGroups.contains { $0.id == f.groupB },
                      "and the group is still in the registry, so the artist can put something back in it")
        XCTAssertEqual(f.manager.layers[f.layerIndex].cels[0]
            .transformTracks[TransformChannelID.group(f.groupB).id]?.keys.count, 2,
                       "and its animation is still there, inert rather than destroyed")
    }

    /// **Out and back in at the same frame is the identity, exactly.**
    ///
    /// This is the property that makes keeping an emptied group the right decision rather than merely
    /// the cautious one: `g · G(F) · G(F)⁻¹` is `g`, so a mistaken remove costs nothing even if the
    /// artist re-adds by hand instead of pressing Undo.
    ///
    /// Operands: S1's **stored** samples before the pair of edits against after them. Stored rather
    /// than displayed on purpose — displayed is equal after the remove alone, so it could not tell a
    /// round trip from a single edit.
    func testRemovingAndReAddingAtTheSameFrameIsTheIdentity() throws {
        let f = fixture()
        let restBefore = try XCTUnwrap(stored(f, f.s1), "fixture: S1 is on the cel")

        select(f, loopOverS1AsItLooks)
        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.none), "out")
        XCTAssertNotEqual(stored(f, f.s1)?.first?.x, restBefore.first?.x,
                          "the remove really did rewrite the stored geometry")
        // The loop has not moved, and neither has the drawing on screen, so it still catches S1.
        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.existing(f.groupA)), "and back in")

        assertPoints(stored(f, f.s1), restBefore,
                     "S1's rest geometry is exactly what it was before the pair of edits")
        XCTAssertEqual(group(f, f.s1), f.groupA, "and it is back in Group A")
    }

    // MARK: - The edges the ruling left open

    /// **A fresh group is minted only when the edit actually goes through.**
    ///
    /// Operands: `animationGroups.count` across an edit that catches nothing (unchanged) and across one
    /// that lands (+1). The first alone would pass against a verb that never minted at all, and the
    /// second alone against one that minted before every refusal.
    func testANewGroupIsMintedOnlyWhenTheEditGoesThrough() throws {
        let f = fixture()
        let before = f.manager.animationGroups.count

        select(f, CGRect(x: 1, y: 55, width: 6, height: 6))   // bare paper
        XCTAssertFalse(f.manager.setAnimationGroupOfSelection(.newGroup))
        XCTAssertEqual(f.manager.animationGroups.count, before,
                       "a loop that caught nothing must not leave a group nothing can reach")

        select(f, loopOverS3)
        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.newGroup))
        XCTAssertEqual(f.manager.animationGroups.count, before + 1, "and one that lands mints one")
        XCTAssertEqual(group(f, f.s3), f.manager.animationGroups.last?.id,
                       "with the caught ink in it")
        // A fresh group has no track on this cel, so there is nothing to compensate for and the
        // geometry is untouched — which is the correct answer and not a missing feature.
        assertPoints(stored(f, f.s3), points([50, 54, 58], y: 20),
                     "joining a group that is not animated rewrites no geometry")
    }

    /// **A group that poses nothing on this cel gets a different sentence, and it is the one that says
    /// what to do next.**
    ///
    /// *"It follows Group 3 on the others"* is true of a group that goes nowhere and useless, which is
    /// the shape of an answer that sends the artist to the source. New Group always lands here, so it
    /// is the commonest state this feature produces.
    ///
    /// Operands: the notice's code after joining a group with **no** track against the code after
    /// joining one **with** a track, in one document over the same loop. Either alone would pass
    /// against a message that never varies.
    func testJoiningAGroupThatAnimatesNothingHereSaysWhatToDoNext() throws {
        let f = fixture()
        select(f, loopOverS3)

        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.newGroup))
        XCTAssertEqual(f.manager.notice?.code, "animationGroupJoinedStaticGroup",
                       "a fresh group poses nothing, and the sentence has to say so")
        XCTAssertTrue(f.manager.notice?.message.contains("keyframe") ?? false,
                      "…and name the step that makes it animate (read \"\(f.manager.notice?.message ?? "nil")\")")

        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.existing(f.groupA)))
        XCTAssertEqual(f.manager.notice?.code, "animationGroupMoved",
                       "and a group that does pose this cel gets the ordinary sentence")
    }

    /// **An edit that cannot keep a placed image where it looks is refused whole** — the second edge,
    /// and "whole" is the load-bearing word.
    ///
    /// Group B is given a **keystone** key, so the compensation for joining it is projective. A placed
    /// image stores six numbers and a mirror bit where a homography needs eight
    /// (`VectorCanvas.posing(_:through:)`'s two declining kinds), so there is nowhere for the
    /// perspective residue to live.
    ///
    /// Operands: the loop's *other* element — an ordinary stroke that the compensation could perfectly
    /// well have carried — before against after. It must be untouched, because a membership edit
    /// applied to some of the loop and not the rest is a corrupted document.
    func testAnEditAPlacedImageCannotFollowIsRefusedWholeAndTouchesNothing() throws {
        let f = fixture()
        // A keystone on Group B, replacing its translation.
        let keystone = Quad(CGPoint(x: 20, y: 2), CGPoint(x: 44, y: 2),
                            CGPoint(x: 62, y: 62), CGPoint(x: 2, y: 62))
        f.manager.layers[f.layerIndex].cels[0]
            .transformTracks[TransformChannelID.group(f.groupB).id] = TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(box: box, corners: keystone))])
        XCTAssertTrue(PoseMap(PoseQuad(box: box, corners: keystone))?.isProjective ?? false,
                      "fixture: Group B's pose is genuinely a keystone")

        f.vector.addImage(VectorImageElement(
            image: CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                            size: CGSize(width: 6, height: 6)),
            transform: LayerTransform(position: CGPoint(x: 54, y: 20), scale: 1, rotation: 0)))

        let strokeBefore = try XCTUnwrap(stored(f, f.s3), "fixture: S3 is on the cel")
        select(f, loopOverS3)     // catches S3 and the photo sitting on top of it
        XCTAssertFalse(f.manager.setAnimationGroupOfSelection(.existing(f.groupB)),
                       "the loop holds a kind the compensation cannot carry")
        XCTAssertEqual(f.manager.notice?.code, "animationGroupEditRefused",
                       "and a refusal the artist cannot see is the defect, not the refusal")
        assertPoints(stored(f, f.s3), strokeBefore,
                     "the stroke beside the photo was not re-grouped either — never a partial edit")
        XCTAssertNil(group(f, f.s3), "and it carries no tag from the refused edit")
    }

    // MARK: - What must not break

    /// **One membership edit is one undo step, and it puts both stores back.**
    ///
    /// Every key on both tracks changes meaning the moment membership does, so an undo that restored
    /// the geometry and left the tag — or the other way round — would leave a document whose drawing
    /// and whose animation disagree. `StructureSnapshot` cannot be that record: it copies `layers` by
    /// value and `Cel.vector` is a class, so it shares the live canvas and restores no element.
    ///
    /// Operands: the stored geometry, the tag, and the registry — each before the edit against after
    /// one press of Undo.
    func testAMembershipEditIsOneUndoStepThatPutsGeometryTagAndRegistryBack() throws {
        let f = fixture()
        let restBefore = try XCTUnwrap(stored(f, f.s3), "fixture: S3 is on the cel")
        let groupsBefore = f.manager.animationGroups.count

        select(f, loopOverS3)
        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.newGroup))
        XCTAssertTrue(f.manager.canUndo, "the edit is on the history")

        f.manager.undo()
        assertPoints(stored(f, f.s3), restBefore, "one press puts the geometry back")
        XCTAssertNil(group(f, f.s3), "…and the tag")
        XCTAssertEqual(f.manager.animationGroups.count, groupsBefore, "…and the registry")

        f.manager.redo()
        XCTAssertEqual(group(f, f.s3), f.manager.animationGroups.last?.id,
                       "and redo puts all three back the other way")
    }

    /// **§2.28's union is not a function of membership, and this pins it rather than assuming it.**
    ///
    /// A membership edit writes no track — that is the design — so the union of the explicit marks and
    /// every frame a channel keys on is bit-for-bit what it was. Three device reports were the two
    /// halves of that union diverging, and the way this feature could have produced a fourth is by
    /// patching one of the lists.
    ///
    /// Operands: `keyframeFrames(of:)` before the edit against after it.
    func testAMembershipEditLeavesTheKeyframeUnionExactlyAsItWas() throws {
        let f = fixture()
        let target = KeyframeTarget.layer(id: f.manager.layers[f.layerIndex].id)
        let before = f.manager.keyframeFrames(of: target)
        XCTAssertEqual(before, [0, 12], "fixture: the two group channels key the same two frames")

        select(f, loopOverS1AsItLooks)
        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.existing(f.groupB)))
        XCTAssertEqual(f.manager.keyframeFrames(of: target), before,
                       "a membership edit writes no track, so the union it feeds cannot move")
    }

    /// **§2.29 survives, and this is the door out of it.**
    ///
    /// The owner's 2026-09-03 ruling refuses a *Move* that catches part of an animated group. That
    /// refusal is about a Move and not about membership — and membership editing is the sanctioned way
    /// to do what it refuses, which is only true if the same loop that the Move rejects is one this
    /// verb accepts.
    ///
    /// Operands: the Move's answer and notice against the membership edit's, on **one** loop over
    /// **one** fixture — so a rule that had quietly widened to cover both would fail here rather than
    /// being argued about.
    func testTheLoopAMoveRefusesForTearingAGroupIsOneMembershipEditingAccepts() throws {
        let f = fixture()
        select(f, loopOverS1AsItLooks)

        XCTAssertFalse(f.manager.beginVectorLassoMove(),
                       "half of an animated group is not a Move this app will make")
        XCTAssertEqual(f.manager.notice?.kind, .onlyPartOfAnAnimationGroup,
                       "and it says so")
        XCTAssertTrue(f.manager.notice?.message.contains("Animation Group") ?? false,
                      "and names where the artist can do it instead")

        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.existing(f.groupB)),
                      "the same loop is a membership edit the app will make")
        XCTAssertEqual(group(f, f.s1), f.groupB)
        XCTAssertEqual(group(f, f.s4), f.groupA, "with the rest of Group A left alone")
    }

    // MARK: - The readout

    /// **The Select panel's readout names what the loop actually caught.**
    ///
    /// It is what an XCUITest reads off the control as a *value*, so it has to resolve rather than
    /// echo. Operands: the caught set's tags against the string, over the four answers there are.
    func testTheReadoutNamesWhatTheLoopCaught() throws {
        let f = fixture()
        XCTAssertEqual(f.manager.selectionAnimationGroupName, "—",
                       "with no selection there is nothing to name")

        select(f, loopOverS1AsItLooks)
        XCTAssertEqual(f.manager.selectionAnimationGroupName, "Group A",
                       "the loop holds one group's ink")

        select(f, loopOverS3)
        XCTAssertEqual(f.manager.selectionAnimationGroupName, "No Group",
                       "…and here, ink in none")

        select(f, CGRect(x: 13, y: 16, width: 40, height: 20))   // S1 (shown) and S2 (shown) together
        XCTAssertEqual(f.manager.selectionAnimationGroupName, "Mixed",
                       "…and here, two groups at once, which is a real answer and not a failure")
    }

    /// **The readout follows the edit**, which is the one thing a memo can get wrong — a stale entry
    /// would leave the panel naming the group the ink used to be in.
    ///
    /// Operands: the readout before the edit against after it, on the same loop and the same frame, so
    /// the only input that moved is the one the memo keys on (`vectorVersion`).
    func testTheReadoutFollowsTheEditRatherThanTheMemo() throws {
        let f = fixture()
        select(f, loopOverS1AsItLooks)
        XCTAssertEqual(f.manager.selectionAnimationGroupName, "Group A", "fixture: read once, so the memo is warm")

        XCTAssertTrue(f.manager.setAnimationGroupOfSelection(.existing(f.groupB)))
        XCTAssertEqual(f.manager.selectionAnimationGroupName, "Group B",
                       "the memo is keyed on the vector version, which the edit bumps")
    }

    /// **A selection drawn on another layer leaves the control unavailable rather than live-and-inert.**
    ///
    /// A `Selection` is stamped with the cel it was drawn on and outlives a layer switch, so *"there is
    /// a selection"* and *"this verb can act on it"* are different questions. Before this test the
    /// panel gated its chips on the first, which would have left every one of them tappable and silent
    /// — the *"a refusal with no notice"* defect reached through a third door.
    ///
    /// Operands: `selectionAnimationGroup` with the selection's own layer active against the same
    /// selection with a different layer active, and the verb's own answer in the second state. All
    /// three read the same `Selection`, so what moved is the playhead's layer and nothing else.
    func testASelectionFromAnotherLayerLeavesTheControlUnavailableRatherThanInert() throws {
        let f = fixture()
        select(f, loopOverS1AsItLooks)
        XCTAssertEqual(f.manager.selectionAnimationGroup, .one(f.groupA),
                       "fixture: on its own layer the loop resolves to Group A")

        f.manager.currentLayerIndex = 0     // the raster layer the fixture made first
        XCTAssertEqual(f.manager.selectionAnimationGroup, .unavailable,
                       "the loop belongs to a cel that is not the one under the playhead")
        XCTAssertFalse(f.manager.setAnimationGroupOfSelection(.existing(f.groupB)),
                       "…and the verb bails on exactly that, which is why the control must be dim")
        XCTAssertEqual(group(f, f.s1), f.groupA, "so nothing was re-grouped")
    }

    /// **The control refuses on a layer it cannot act on, and says why** — the shape
    /// `recolorUnavailableReason` uses, and for its reason: a control that does nothing says why.
    ///
    /// Operands: the reason on a raster layer (non-nil) against the reason on the vector layer beside
    /// it (nil), in one document, so a sentence that had become unconditional would fail.
    func testTheControlSaysWhyItIsOffOnALayerThatHoldsNoElements() throws {
        let f = fixture()
        XCTAssertNil(f.manager.animationGroupEditUnavailableReason,
                     "the vector layer the fixture is standing on is fine")
        f.manager.currentLayerIndex = 0     // the raster layer `CanvasFixture.manager` made
        XCTAssertNotNil(f.manager.animationGroupEditUnavailableReason,
                        "a raster cel has pixels and no elements, so there is no membership to edit")
        XCTAssertEqual(f.manager.selectionAnimationGroupName, "—",
                       "and the readout says nothing rather than naming a group")
    }
}
