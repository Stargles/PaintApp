import XCTest
import UIKit
import CoreGraphics

/// **An animation group moves whole, and on its own** — the second half of the owner's 2026-09-03
/// rule, *if a Move would damage an existing animation, it does not happen, and it says why.*
/// `PartialAnimationGroupMoveLogicTests` is the first half (a group carried in halves); this is a
/// group carried whole but **not alone**, which is the other way the same sentence fails.
///
/// ## The defect these tests were written against
///
/// `existingAnimationChannel` reuses a group only when **every** carried element shares one, so a
/// selection spanning two groups answers nil and `commitPoseFromFloat` falls through to
/// `mintAnimationChannel` — which **overwrites** `animationGroupID` on every carried element with
/// the fresh group's id. From that moment `VectorElement.isMoved(by: .group(old))` is false for all
/// of them, so the two tracks still sitting on the cel claim no elements and pose nothing. Two
/// animations silently stop existing. Nothing looks wrong at the frame the Move was made on — the
/// ink keeps moving, under the new channel, from wherever the drag left it — and the loss shows up
/// only when the artist scrubs, with nothing on screen pointing back at the Move.
///
/// **And two whole groups is not the only door.** The mint does not care what the *other* carried
/// ink is, only that the carried set is not one group exactly, so **one whole group carried beside
/// ink in no group at all** loses that group's animation in precisely the same way — a four-element
/// drawing is enough. Both are `AnimationGroupHarm.notAlone`, one case rather than two, because the
/// artist's way out of them is the same: loop around just one group.
///
/// ## What every test here has to assert, and why the `Bool` alone would not do it
///
/// The old path **returned true and then destroyed two animations**, so a test reading only
/// `beginVectorLassoMove()`'s answer would go green against code that refuses *and* mutates. Every
/// test below drives the whole gesture the artist's finger makes — lift, nudge, commit — and then
/// reads three independent things the mint would have changed: **where the drawing is** (stored and
/// displayed, at the frames either side as well as at the playhead), **which group each element
/// still claims**, and **how many groups the document has**. The tags are the assertion with the
/// most teeth: the mint's whole damage is a field write, and it is invisible in the geometry at the
/// frame the Move was made on.
///
/// Pure logic, no simulator.
final class TwoAnimationGroupMoveLogicTests: XCTestCase {

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
        var stroke = VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(),
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
    /// `nudgeVectorFloat` and `commitVectorFloatIfNeeded` are no-ops — which is what lets one shape of
    /// test cover the refusals and the non-refusals alike.
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

    /// **Registers a group and gives it a channel that slides its members `dx` right between
    /// cel-local 0 and 12, without disturbing the tracks already there.**
    ///
    /// Merged into `transformTracks` rather than assigned over it, which is the one difference from
    /// `PartialAnimationGroupMoveLogicTests`' otherwise identical helper and is the whole point of
    /// this file: a document with **two** animated groups on one cel is the fixture, and a helper
    /// that overwrote would quietly leave it with one.
    ///
    /// Key 0 is the rest pose, so the playhead at frame 0 is on a keyframe and both channels resolve
    /// to the identity there — the plainest state to read a "did anything move" assertion in.
    private func animateGroup(_ manager: CanvasManager, _ layerIndex: Int, _ group: UUID,
                              named name: String, dx: CGFloat) {
        manager.animationGroups.append(AnimationGroup(id: group, displayName: name,
                                                      tagColor: black()))
        manager.layers[layerIndex].cels[0]
            .transformTracks[TransformChannelID.group(group).id] = TransformTrack(keys: [
                TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
                TransformTrack.Key(frame: 12, pose: PoseQuad(box: box,
                                                             mappedBy: .init(translationX: dx, y: 0)),
                                   interpolation: .linear)])
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

    /// **Which group each element on the cel claims, in display order** — the field
    /// `mintAnimationChannel` overwrites, and therefore the reading that catches the defect at the
    /// frame the Move was made on, where the geometry alone cannot.
    private func tags(_ vector: VectorCanvas) -> [UUID?] { vector.elements.map(\.animationGroupID) }

    private func keyCount(_ manager: CanvasManager, _ layerIndex: Int,
                          _ channel: TransformChannelID) -> Int? {
        manager.layers[layerIndex].cels[0].transformTracks[channel.id]?.keys.count
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

    /// **Two animated groups on one cel, and a third stroke in neither.**
    ///
    /// The third is load-bearing rather than scenery, for the reason the whole-cel narrowing exists:
    /// without it a loop around both groups is a loop around the **whole cel**, which
    /// `existingAnimationChannel` answers `.cel` for before it ever looks at a group — so the
    /// refusal test would be measuring the cel channel and could not go red.
    ///
    /// Rest x: A 6/14/22 (group A, +40 by frame 12), B 40/48/56 (group B, +20 by frame 12),
    /// C 70/78/86 (no group), all at y 30 with a 4 pt stroke. The two `dx` differ so an assertion
    /// cannot pass by reading one group's animation where the other's was meant.
    private func twoGroupFixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas,
                                       groupA: UUID, groupB: UUID) {
        let (manager, layerIndex, vector) = fixture()
        let groupA = UUID(), groupB = UUID()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30), group: groupA))
        vector.addStroke(stroke(from: CGPoint(x: 40, y: 30), to: CGPoint(x: 56, y: 30), group: groupB))
        vector.addStroke(stroke(from: CGPoint(x: 70, y: 30), to: CGPoint(x: 86, y: 30)))
        animateGroup(manager, layerIndex, groupA, named: "Group 1", dx: 40)
        animateGroup(manager, layerIndex, groupB, named: "Group 2", dx: 20)
        manager.currentFrame = 0
        return (manager, layerIndex, vector, groupA, groupB)
    }

    private var restXs: [CGFloat] { [6, 14, 22, 40, 48, 56, 70, 78, 86] }
    /// The two animations, read at the far keyframe: A carries +40 and B carries +20, and C neither.
    private var animatedXs: [CGFloat] { [46, 54, 62, 60, 68, 76, 70, 78, 86] }

    /// A loop around A and B — both groups whole, with C left outside so this is not the whole cel.
    private var bothGroups: CGPath { loop(CGRect(x: 0, y: 20, width: 62, height: 20)) }
    /// A loop around A alone, which is one whole group and nothing else.
    private var groupAAlone: CGPath { loop(CGRect(x: 0, y: 20, width: 30, height: 20)) }
    /// A loop around C alone, which is in no group at all.
    private var theUntaggedStroke: CGPath { loop(CGRect(x: 64, y: 20, width: 28, height: 20)) }
    /// A loop around every element on the cel — the lasso's door onto the `.cel` channel.
    private var everything: CGPath { loop(CGRect(x: 0, y: 20, width: 96, height: 20)) }

    // MARK: - The refusal

    /// **A lasso over two whole animated groups refuses, and both animations are still there.**
    ///
    /// Against the code as it stood the lift *succeeded*: `existingAnimationChannel` answered nil for
    /// the mixed selection, `commitPoseFromFloat` fell through to `mintAnimationChannel`, and every
    /// carried element was re-tagged to a third group. Both original tracks then claimed nothing.
    ///
    /// The three readings after the notice are what make this a test of the document rather than of
    /// a return value, and **the tags are the one that cannot be faked**: the mint takes the
    /// `.seedAndKey` arm, which leaves the drag baked, so the geometry at frame 0 looks like a Move
    /// that worked. What is gone is the pair of tracks, and the only evidence at this frame is which
    /// group each element claims.
    func testALassoOverTwoWholeAnimatedGroupsRefusesAndBothAnimationsSurvive() throws {
        let (manager, layerIndex, vector, groupA, groupB) = twoGroupFixture()
        select(manager, layerIndex, bothGroups)

        XCTAssertFalse(lassoMove(manager, dx: 25),
                       "two animations at once is not a Move this app will make")
        XCTAssertEqual(manager.notice?.kind, .animationGroupNotAlone,
                       "a refusal the artist cannot see is the defect, not the refusal")
        XCTAssertNil(manager.vectorFloat, "and nothing was lifted")

        XCTAssertEqual(tags(vector), [groupA, groupB, nil],
                       "every element still claims the group it claimed — this is what the mint overwrote")
        XCTAssertEqual(manager.animationGroups.count, 2, "and no third group was minted")
        assertXs(sampleXs(vector.elements), restXs, "the stored drawing is untouched")
        assertXs(displayedXs(manager, layerIndex, at: 0), restXs,
                 "…and so is what the artist is looking at")
        assertXs(displayedXs(manager, layerIndex, at: 12), animatedXs,
                 "both animations say exactly what they said — this is where the loss used to show up")
        XCTAssertEqual(keyCount(manager, layerIndex, .group(groupA)), 2, "no key was written to A")
        XCTAssertEqual(keyCount(manager, layerIndex, .group(groupB)), 2, "nor to B")
    }

    /// **One whole group carried beside ink in no group refuses too** — the same mint through a
    /// narrower door, and the reason `AnimationGroupHarm.notAlone` is one case rather than a count of
    /// groups.
    ///
    /// `existingAnimationChannel` builds a `Set` of the carried elements' `animationGroupID`, so an
    /// untagged element contributes `nil` and the set has two members exactly as two groups would.
    /// The route falls through, the mint runs, and the one group that *was* animated is overwritten.
    /// A predicate written for "two or more groups" would let this through, and the fixture that
    /// proves it is four strokes.
    ///
    /// The fourth stroke is what stops the loop being the whole cel, which would take the `.cel` arm
    /// and mint nothing.
    func testALassoOverAWholeGroupAndInkOutsideItRefusesAndTheAnimationSurvives() throws {
        let (manager, layerIndex, vector) = fixture()
        let group = UUID()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 22, y: 30), group: group))
        vector.addStroke(stroke(from: CGPoint(x: 30, y: 30), to: CGPoint(x: 46, y: 30)))
        vector.addStroke(stroke(from: CGPoint(x: 70, y: 30), to: CGPoint(x: 86, y: 30)))
        animateGroup(manager, layerIndex, group, named: "Group 1", dx: 40)
        manager.currentFrame = 0
        select(manager, layerIndex, loop(CGRect(x: 0, y: 20, width: 52, height: 20)))

        XCTAssertFalse(lassoMove(manager, dx: 25),
                       "an animated group carried with ink it does not own is the same mint")
        XCTAssertEqual(manager.notice?.kind, .animationGroupNotAlone)
        XCTAssertEqual(tags(vector), [group, nil, nil], "the group still owns its stroke")
        XCTAssertEqual(manager.animationGroups.count, 1, "and nothing was minted over it")
        assertXs(sampleXs(vector.elements), [6, 14, 22, 30, 38, 46, 70, 78, 86],
                 "nothing moved")
        assertXs(displayedXs(manager, layerIndex, at: 12), [46, 54, 62, 30, 38, 46, 70, 78, 86],
                 "and the animation still says what it said")
    }

    // MARK: - The non-refusals, which is where a too-broad rule does its damage

    /// **One whole group still moves, on a drawing where a second group is animated beside it.**
    ///
    /// This is the artist's way out of the refusal above — the thing the notice tells them to do — so
    /// it has to work, and it is the first thing a predicate stated as *"more than one animated group
    /// is on this cel"* rather than *"…is inside this loop"* would break.
    ///
    /// The `.key` arm runs: the drag is taken back out of the geometry and written onto A's own
    /// channel as a pose at the playhead, which is why the stored list is at rest and only the
    /// displayed one carries the move.
    func testOneWholeGroupStillMovesWhileASecondGroupIsAnimatedBesideIt() throws {
        let (manager, layerIndex, vector, groupA, groupB) = twoGroupFixture()
        select(manager, layerIndex, groupAAlone)

        XCTAssertTrue(lassoMove(manager, dx: 25), "one whole group is a Move the artist may make")
        XCTAssertNil(manager.notice, "and nothing is refused")

        XCTAssertEqual(tags(vector), [groupA, groupB, nil], "no re-tagging happened")
        XCTAssertEqual(manager.animationGroups.count, 2, "the existing channel was extended, not replaced")
        assertXs(sampleXs(vector.elements), restXs, "the `.key` arm takes the bake back out")
        assertXs(displayedXs(manager, layerIndex, at: 0),
                 [31, 39, 47, 40, 48, 56, 70, 78, 86],
                 "A carries the drag at the playhead, and B and C do not")
        assertXs(displayedXs(manager, layerIndex, at: 12), animatedXs,
                 "and the far keyframe of both animations is where it always was")
        XCTAssertEqual(keyCount(manager, layerIndex, .group(groupA)), 2,
                       "the key at the playhead was replaced, not added to")
        XCTAssertEqual(keyCount(manager, layerIndex, .group(groupB)), 2, "and B was not touched")
    }

    /// **Move with no lasso still moves a drawing that holds two animated groups — the trap in this
    /// rule, and the reason it is stated with a whole-cel escape rather than as a count of groups.**
    ///
    /// A whole-cel lift carries every element, so it carries both groups whole and *not alone*: the
    /// second half of the rule reads as failed, and a predicate that stopped there would refuse Move
    /// with no selection on **every animated document**. It is allowed because
    /// `existingAnimationChannel` answers `.cel` for exactly this Move — nothing is minted, no tag is
    /// rewritten, and both groups travel whole nested inside the cel's own move, which is a character
    /// walking with both arms still swinging.
    ///
    /// The `.seedAndKey` arm runs here (the cel channel has no curve yet), so the drag stays baked in
    /// the stored list — which is what makes "every element travelled" readable at all.
    func testAWholeCelMoveOnADrawingWithTwoAnimatedGroupsStillMoves() throws {
        let (manager, layerIndex, vector, groupA, groupB) = twoGroupFixture()
        manager.selection = nil

        XCTAssertTrue(manager.beginVectorWholeCelMove(),
                      "Move with no selection must not be refused by a rule about lassoing two groups")
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 25, dy: 0))
        XCTAssertTrue(manager.commitVectorFloatIfNeeded())
        XCTAssertNil(manager.notice)

        assertXs(sampleXs(vector.elements), restXs.map { $0 + 25 },
                 "every element on the cel travelled, which is what Move with no selection means")
        XCTAssertEqual(tags(vector), [groupA, groupB, nil], "and neither group was re-tagged")
        XCTAssertEqual(manager.animationGroups.count, 2, "nor was a third minted")
        XCTAssertEqual(keyCount(manager, layerIndex, .group(groupA)), 2)
        XCTAssertEqual(keyCount(manager, layerIndex, .group(groupB)), 2)
    }

    /// **A lasso drawn around everything is the same Move by the other door, and is allowed for the
    /// same reason.** This is the exact boundary of the whole-cel escape: one stroke fewer inside the
    /// loop and it is the refusal at the top of this file.
    func testALassoAroundEveryElementOnACelWithTwoAnimatedGroupsIsNotRefused() throws {
        let (manager, layerIndex, vector, groupA, groupB) = twoGroupFixture()
        select(manager, layerIndex, everything)

        XCTAssertTrue(lassoMove(manager, dx: 25),
                      "a loop around the whole cel is the cel channel, not two groups")
        XCTAssertNil(manager.notice)
        assertXs(sampleXs(vector.elements), restXs.map { $0 + 25 })
        XCTAssertEqual(tags(vector), [groupA, groupB, nil])
        XCTAssertEqual(manager.animationGroups.count, 2)
    }

    /// **Ink in no group still moves on a two-group drawing, and mints a group of its own.**
    ///
    /// The loop catches nothing that belongs to an animation, so it damages none — and a rule asked
    /// as *"is more than one group animated here"* rather than *"what is this Move carrying"* would
    /// refuse it. The mint is correct here and is the behaviour the whole routing rule is built on:
    /// this Move is the first thing that ever animated that stroke.
    func testALassoOverInkInNoGroupStillMovesAndMintsAThirdGroup() throws {
        let (manager, layerIndex, vector, groupA, groupB) = twoGroupFixture()
        select(manager, layerIndex, theUntaggedStroke)

        XCTAssertTrue(lassoMove(manager, dx: 25))
        XCTAssertNil(manager.notice)
        XCTAssertEqual(manager.animationGroups.count, 3,
                       "the untagged stroke got a channel of its own")
        XCTAssertEqual(Array(tags(vector).prefix(2)), [groupA, groupB],
                       "and the two that were already animated kept their groups")
        assertXs(sampleXs(vector.elements), [6, 14, 22, 40, 48, 56, 95, 103, 111],
                 "only the untagged stroke travelled")
        assertXs(displayedXs(manager, layerIndex, at: 12), [46, 54, 62, 60, 68, 76, 70, 78, 86],
                 "and both existing animations still say what they said")
    }

    /// **The channel lift is untouched by this rule, which is the third door and the one that asks
    /// for nothing.**
    ///
    /// `beginVectorChannelMove` lifts `isMoved(by:)`'s membership — every member of one group and no
    /// other ink — so it fails neither half of *a group moves whole, and on its own*, on a document
    /// with any number of groups. It does not call the guard, and this test is what makes that
    /// omission honest rather than an oversight: raise the box over B's channel on a drawing that
    /// holds two, drag it, and B's animation is the only one that changes.
    func testAChannelMoveOnADrawingWithTwoAnimatedGroupsLiftsAndMovesOnlyThatGroup() throws {
        let (manager, layerIndex, vector, groupA, groupB) = twoGroupFixture()

        XCTAssertTrue(manager.beginVectorChannelMove(.group(groupB)),
                      "a channel lift carries exactly one group's membership")
        XCTAssertEqual(manager.vectorFloat?.insideIDs.count, 1, "and only that group's ink")
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 25, dy: 0))
        XCTAssertTrue(manager.commitVectorFloatIfNeeded())
        XCTAssertNil(manager.notice)

        XCTAssertEqual(tags(vector), [groupA, groupB, nil])
        XCTAssertEqual(manager.animationGroups.count, 2)
        assertXs(sampleXs(vector.elements), restXs, "the `.key` arm takes the bake back out")
        assertXs(displayedXs(manager, layerIndex, at: 0),
                 [6, 14, 22, 65, 73, 81, 70, 78, 86],
                 "B carries the drag at the playhead and A does not")
        assertXs(displayedXs(manager, layerIndex, at: 12), animatedXs,
                 "and neither far keyframe moved")
    }
}
