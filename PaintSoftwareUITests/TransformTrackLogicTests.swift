import XCTest
import CoreGraphics

/// Pure-logic tests for one pose channel's storage and evaluation — KEYFRAMES.md §3.1, §3.2 and
/// §2.10, and TODO (139): **one curve per component, each keyed independently of the others.**
///
/// The channel is eight `AnimationCurve`s against one rest box, so what is pinned here is what the
/// channel adds on top of a curve: that the components stay independent under every edit, that a
/// write keys only what changed, that a component with no curve shows the base, and that a resting
/// channel costs the document nothing.
final class TransformTrackLogicTests: XCTestCase {

    private let box = CGRect(x: 10, y: 10, width: 40, height: 20)
    private var rest: PoseComponents.Values { .resting(in: box) }

    /// A channel whose X curve holds `pairs` as offsets from the box's rest centre.
    private func xTrack(_ pairs: [(Int, Double)],
                        interpolation: AnimationCurve.Interpolation = .linear,
                        step: Int = 1) -> TransformTrack {
        TransformTrack(box: box, curves: [.x: AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: Double(box.midX) + $0.1, interpolation: interpolation)
        }, step: step)])
    }

    /// How far right of rest the channel shows the drawing at `frame` — read off the map, which is
    /// what a renderer is handed.
    private func dx(_ track: TransformTrack, at frame: Int) -> Double? {
        guard let map = track.mapping(atCelLocalFrame: frame) else {
            return track.isEmpty ? nil : 0
        }
        return Double(map.applied(to: CGPoint(x: box.midX, y: box.midY))!.x - box.midX)
    }

    // MARK: - Storage

    /// An empty curve is never stored: a component with no keys is a component with no curve, which
    /// shows the base, and storing an empty one would list a channel that animates nothing.
    func testAnEmptyCurveIsNeverStored() {
        var t = TransformTrack(box: box, curves: [.x: AnimationCurve(), .y: AnimationCurve(keys: [.init(frame: 0, value: 3)])])
        XCTAssertEqual(Set(t.curves.keys), [.y])
        t.setCurve(nil, for: .y)
        XCTAssertTrue(t.isEmpty)
        t.setCurve(AnimationCurve(keys: [.init(frame: 2, value: 1)]), for: .rotation)
        t.setCurve(AnimationCurve(), for: .rotation)
        XCTAssertTrue(t.isEmpty, "an empty curve written is a removal")
    }

    /// The strict predicate, per component: the channel is an animation when some component's curve
    /// is one.
    func testAChannelIsAnAnimationOnlyWhenSomeComponentMoves() {
        XCTAssertFalse(TransformTrack(box: box).isAnimated)
        XCTAssertFalse(xTrack([(0, 12)]).isAnimated, "One key is a hold, not an animation")
        XCTAssertFalse(xTrack([(0, 12), (8, 12)]).isAnimated, "Two equal values animate nothing")
        XCTAssertTrue(xTrack([(0, 0), (8, 12)]).isAnimated)
    }

    /// Every frame some component keys, once — what the timeline draws a diamond on.
    func testKeyedFramesAreTheUnionOfEveryComponentsKeys() {
        var t = xTrack([(8, 80), (0, 0)])
        t.setCurve(AnimationCurve(keys: [.init(frame: 4, value: 30), .init(frame: 8, value: 0)]), for: .rotation)
        XCTAssertEqual(t.keyedFrames, [0, 4, 8])
        XCTAssertEqual(t.keyCount, 4)
    }

    /// Removing the keys on a frame takes every component's key there and drops a component left
    /// with none.
    func testRemovingAFrameTakesEveryComponentsKeyAndDropsEmptiedCurves() {
        var t = xTrack([(0, 0), (8, 80)])
        t.setCurve(AnimationCurve(keys: [.init(frame: 8, value: 30)]), for: .rotation)
        t.removeKeys(atFrame: 8)
        XCTAssertEqual(t.curve(.x)?.keys.map(\.frame), [0])
        XCTAssertNil(t.curve(.rotation), "a component left with no key is no longer stored")
    }

    // MARK: - Independence — TODO (139)

    /// **Keying X leaves Y's keys untouched** — the owner's *"fully independent from each other"*.
    /// A sideways change over a channel already keying Y at other frames writes X alone, and X takes
    /// no key on Y's frames either: they are keyframes of the target, but not primed ones, so they are
    /// no reason to put a key on X (`AnimationCurve.keyed`).
    func testKeyingXLeavesYsKeysUntouched() {
        var t = TransformTrack(box: box, curves: [
            .x: AnimationCurve(keys: [.init(frame: 0, value: rest.x), .init(frame: 8, value: rest.x + 10)]),
            .y: AnimationCurve(keys: [.init(frame: 2, value: rest.y), .init(frame: 6, value: rest.y - 5)])
        ])
        let yBefore = t.curve(.y)
        var old = t.values(atTime: 4, base: rest)
        var new = old
        new.x += 20
        XCTAssertEqual(t.key(new, over: old, atFrame: 4, placed: PlacedKeys(frames: [0, 2, 6, 8], primed: [])), [.x])
        XCTAssertEqual(t.curve(.y), yBefore, "Y's keys are exactly where they were")
        XCTAssertEqual(t.curve(.x)?.keys.map(\.frame), [0, 4, 8])

        // And the other way round: a change to Y at a frame X keys leaves X's key value alone.
        old = t.values(atTime: 8, base: rest)
        new = old
        new.y += 7
        let xBefore = t.curve(.x)
        XCTAssertEqual(t.key(new, over: old, atFrame: 8, placed: PlacedKeys(frames: [0, 2, 4, 6, 8], primed: [])), [.y])
        XCTAssertEqual(t.curve(.x), xBefore)
    }

    /// **Retiming one component's key moves only it** — the graph editor writes a whole curve per
    /// row, and a row is one component.
    func testRetimingOneComponentsKeyMovesOnlyThatComponent() {
        var t = TransformTrack(box: box, curves: [
            .x: AnimationCurve(keys: [.init(frame: 0, value: rest.x), .init(frame: 8, value: rest.x + 10)]),
            .rotation: AnimationCurve(keys: [.init(frame: 0, value: 0), .init(frame: 8, value: 45)])
        ])
        var x = t.curve(.x)!
        var moved = x.key(atFrame: 8)!
        x.removeKey(atFrame: 8)
        moved.frame = 11
        x.setKey(moved)
        t.setCurve(x, for: .x)
        XCTAssertEqual(t.curve(.x)?.keys.map(\.frame), [0, 11])
        XCTAssertEqual(t.curve(.rotation)?.keys.map(\.frame), [0, 8], "rotation still keys frame 8")
        XCTAssertEqual(t.values(atTime: 8, base: rest).rotation, 45, accuracy: 1e-12)
        XCTAssertLessThan(t.values(atTime: 8, base: rest).x, rest.x + 10, "X is still on its way at 8")
    }

    /// A component with no curve shows the base at every frame — rest for a cel channel.
    func testAComponentWithNoCurveShowsTheBase() {
        let t = xTrack([(0, 0), (8, 80)])
        for frame in 0...8 {
            let values = t.values(atTime: Double(frame), base: rest)
            XCTAssertEqual(values.y, rest.y)
            XCTAssertEqual(values.rotation, 0)
            XCTAssertEqual(values.scaleX, 1)
            XCTAssertEqual(values.perspectiveX, 0)
        }
    }

    // MARK: - Writing what changed

    /// **A component with a curve is keyed at the frame; one without is seeded** — the old value on
    /// the neighbouring keyframes, the new one here — so the frames either side keep what they
    /// showed. That is what a whole-pose key used to do for the component implicitly.
    func testAnUncurvedComponentIsSeededAndACurvedOneIsKeyed() {
        var t = xTrack([(0, 0), (6, 30)])
        let old = t.values(atTime: 10, base: rest)
        var new = old
        new.x += 5
        new.rotation = 30
        let written = t.key(new, over: old, atFrame: 10, placed: PlacedKeys(frames: [0, 6], primed: []))
        XCTAssertEqual(written, [.x, .rotation])
        XCTAssertEqual(t.curve(.x)?.keys.map(\.frame), [0, 6, 10], "X keyed at the frame alone")
        XCTAssertEqual(t.curve(.rotation)?.keys.map(\.frame), [6, 10], "rotation seeded onto the keyframe below")
        XCTAssertEqual(t.values(atTime: 0, base: rest).rotation, 0, "so frame 0 still shows no turn")
        XCTAssertEqual(t.values(atTime: 10, base: rest).rotation, 30, accuracy: 1e-12)
    }

    /// Nothing changed is nothing written — not even a key re-stating a value.
    func testAWriteThatChangesNothingKeysNothing() {
        var t = xTrack([(0, 0), (6, 30)])
        let before = t
        let values = t.values(atTime: 3, base: rest)
        XCTAssertEqual(t.key(values, over: values, atFrame: 3, placed: PlacedKeys(frames: [0, 6], primed: [])), [])
        XCTAssertEqual(t, before)
    }

    /// **A turn through ±180° is keyed the short way round.** `decompose` reports an angle in
    /// `(−180°, 180°]`; a channel wound to 170° turned by 20° more must be keyed at 190°, not at
    /// −170°, which would spin it back through 340°.
    func testATurnPastHalfAWayIsKeyedTheShortWayRound() {
        var t = TransformTrack(box: box, curves: [.rotation: AnimationCurve(keys: [.init(frame: 0, value: 170)])])
        let old = t.values(atTime: 4, base: rest)
        var new = old
        new.rotation = -170
        XCTAssertEqual(t.key(new, over: old, atFrame: 4, placed: PlacedKeys(frames: [0], primed: [])), [.rotation])
        XCTAssertEqual(t.curve(.rotation)?.key(atFrame: 4)?.value ?? 0, 190, accuracy: 1e-9)
    }

    /// **An animated component edited past a primed frame holds that frame's value, and only it
    /// does** — TODO (139): priming keys nothing, so the hold Add Keys used to make for every
    /// component is made at the edit, for the component that changed. X keyed 0 and 8, frame 4
    /// primed, X moved at 6: X takes its own value at 4 and the new one at 6, so frames 0–4 show what
    /// they showed, and Y — unchanged — takes nothing.
    func testAnAnimatedComponentEditedPastAPrimedFrameHoldsItThereAndNothingElseIsKeyed() {
        var t = xTrack([(0, 0), (8, 80)])
        let shownAt4 = t.values(atTime: 4, base: rest).x
        let old = t.values(atTime: 6, base: rest)
        var new = old
        new.x += 25
        XCTAssertEqual(t.key(new, over: old, atFrame: 6, placed: PlacedKeys(frames: [0, 4, 8], primed: [4])), [.x])
        XCTAssertEqual(t.curve(.x)?.keys.map(\.frame), [0, 4, 6, 8])
        XCTAssertEqual(t.values(atTime: 4, base: rest).x, shownAt4, accuracy: 1e-9,
                       "the primed frame keeps the value it showed")
        XCTAssertEqual(t.curve(.x)?.key(atFrame: 6)?.value ?? 0, new.x, accuracy: 1e-9)
        XCTAssertEqual(Set(t.curves.keys), [.x], "Y did not change and takes no key")
    }

    // MARK: - Evaluation

    /// A `.linear` segment walks from one key's value to the next, and the endpoints are the keys.
    func testALinearSegmentWalksFromOneKeyToTheNext() {
        let t = xTrack([(0, 0), (8, 80)])
        XCTAssertEqual(dx(t, at: 0), 0)
        XCTAssertEqual(dx(t, at: 4)!, 40, accuracy: 1e-9)
        XCTAssertEqual(dx(t, at: 8)!, 80, accuracy: 1e-9)
    }

    /// **Decision 2**: outside the first and last key a curve is a constant hold, so a drawing moved
    /// by a channel stays where the last key put it.
    func testOutsideTheKeysTheValueIsHeldRatherThanExtrapolated() {
        let t = xTrack([(4, 0), (8, 80)])
        XCTAssertEqual(dx(t, at: 0), 0)
        XCTAssertEqual(dx(t, at: -20), 0)
        XCTAssertEqual(dx(t, at: 40)!, 80, accuracy: 1e-9)
    }

    /// One key is a hold everywhere.
    func testASingleKeyHoldsAtEveryFrame() {
        let t = xTrack([(3, 25)])
        for frame in -5...20 { XCTAssertEqual(dx(t, at: frame)!, 25, accuracy: 1e-9) }
    }

    /// An empty channel has no map — *this cel stores what it shows*, which is "no derivation".
    func testAnEmptyChannelHasNoMapping() {
        XCTAssertNil(TransformTrack(box: box).mapping(atCelLocalFrame: 0))
    }

    /// §2.10, per curve: evaluate, then hold for `step` frames anchored at frame 0.
    func testAStepOfTwoHoldsTheValueForPairsOfFrames() {
        let t = xTrack([(0, 0), (8, 80)], step: 2)
        XCTAssertEqual(dx(t, at: 2)!, 20, accuracy: 1e-9)
        XCTAssertEqual(dx(t, at: 3)!, 20, accuracy: 1e-9, "Frame 3 quantises down onto 2")
        XCTAssertEqual(dx(t, at: 5)!, 40, accuracy: 1e-9)
    }

    /// A `.constant` segment holds its start value and steps at the next key.
    func testAConstantSegmentHoldsAndThenSteps() {
        let t = xTrack([(0, 0), (8, 80)], interpolation: .constant)
        XCTAssertEqual(dx(t, at: 7), 0)
        XCTAssertEqual(dx(t, at: 8)!, 80, accuracy: 1e-9)
    }

    /// **An overshooting handle carries a component past its key** — a curve's decision 1, which a
    /// pose component now inherits directly.
    func testAFreeHandleCarriesTheDrawingPastTheKeyItIsHeadingFor() {
        let t = TransformTrack(box: box, curves: [.x: AnimationCurve(keys: [
            AnimationCurve.Key(frame: 0, value: rest.x,
                               outHandle: AnimationCurve.Handle(deltaFrames: 5, deltaValue: 320), tangentMode: .free),
            AnimationCurve.Key(frame: 10, value: rest.x + 80,
                               inHandle: AnimationCurve.Handle(deltaFrames: -5, deltaValue: 320), tangentMode: .free)
        ])])
        let travelled = (0...10).compactMap { dx(t, at: $0) }
        XCTAssertGreaterThan(travelled.max() ?? 0, 160, "the drawing sails past its mark")
        XCTAssertEqual(travelled.first, 0)
        XCTAssertEqual(travelled.last!, 80, accuracy: 1e-9)
    }

    /// **The predicate the whole derivation hangs off.** A channel whose keys all hold rest values —
    /// what a seed writes before anything has been moved — must cost the document nothing.
    func testARestingChannelProducesNoMappingAndThereforeNoDerivation() {
        let resting = xTrack([(0, 0), (8, 0)])
        XCTAssertNil(resting.mapping(atCelLocalFrame: 0))
        XCTAssertNil(resting.mapping(atCelLocalFrame: 4))

        let moving = xTrack([(0, 0), (8, 80)])
        XCTAssertNil(moving.mapping(atCelLocalFrame: 0), "Frame 0's key is the rest value")
        XCTAssertNotNil(moving.mapping(atCelLocalFrame: 1))
    }

    /// **At every key the channel shows the pose it was keyed with** — what the whole-pose model this
    /// replaced returned bit for bit, and what eight independent curves return to floating point: a
    /// key holds each component's value, and recomposing the eight is `decompose`'s inverse. One
    /// fixture holds every kind of pose a Move makes, keystone included.
    func testAtEveryKeyTheChannelShowsThePoseItWasKeyedWith() throws {
        let centre = CGPoint(x: box.midX, y: box.midY)
        let turn = CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: 0.7)
            .translatedBy(x: -centre.x, y: -centre.y)
        let poses: [(frame: Int, pose: PoseQuad)] = [
            (0, PoseQuad(restingIn: box)),
            (3, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 31, y: -12))),
            (6, PoseQuad(box: box, mappedBy: turn.concatenating(CGAffineTransform(scaleX: 1.6, y: 0.7)))),
            (9, PoseQuad(box: box, mappedBy: CGAffineTransform(a: 1, b: 0, c: 0.4, d: 1, tx: 5, ty: 2))),
            (12, PoseQuad(box: box, corners: Quad(CGPoint(x: 16, y: 10), CGPoint(x: 44, y: 10),
                                                  CGPoint(x: 50, y: 30), CGPoint(x: 10, y: 30)))),
        ]
        let track = CanvasFixture.poseTrack(box: box, poses)
        for (frame, pose) in poses {
            let shown: [CGPoint]
            if let map = track.mapping(atCelLocalFrame: frame) {
                shown = try Quad.rect(box).points.map { try XCTUnwrap(map.applied(to: $0)) }
            } else {
                shown = Quad.rect(box).points
            }
            for (a, b) in zip(shown, pose.corners.points) {
                XCTAssertEqual(a.x, b.x, accuracy: 1e-6, "frame \(frame)")
                XCTAssertEqual(a.y, b.y, accuracy: 1e-6, "frame \(frame)")
            }
        }
        XCTAssertEqual(track.mapping(atCelLocalFrame: 12)?.isProjective, true, "the keystone key is a keystone")
    }

    // MARK: - Splitting and cropping, per component

    /// **§3.1's rule for `splitCel`**, on each component: every frame of the original span shows what
    /// it showed, read out of whichever half covers it, and the components split independently.
    func testSplittingAChannelLeavesEveryFrameShowingWhatItShowed() {
        var whole = xTrack([(0, 0), (12, 120)])
        whole.setCurve(AnimationCurve(keys: [.init(frame: 2, value: 0, interpolation: .linear),
                                             .init(frame: 9, value: 70)]), for: .rotation)
        let (left, right) = whole.split(atCelLocalFrame: 5)

        for frame in 0..<5 {
            let w = whole.values(atTime: Double(frame), base: rest)
            let l = left.values(atTime: Double(frame), base: rest)
            XCTAssertEqual(l.x, w.x, accuracy: 1e-9, "left half X, frame \(frame)")
            XCTAssertEqual(l.rotation, w.rotation, accuracy: 1e-9, "left half rotation, frame \(frame)")
        }
        for frame in 5..<13 {
            let w = whole.values(atTime: Double(frame), base: rest)
            let r = right.values(atTime: Double(frame - 5), base: rest)
            XCTAssertEqual(r.x, w.x, accuracy: 1e-9, "right half X, frame \(frame)")
            XCTAssertEqual(r.rotation, w.rotation, accuracy: 1e-9, "right half rotation, frame \(frame)")
        }
        XCTAssertEqual(left.curve(.x)?.keys.map(\.frame), [0, 4], "the inserted key is the left half's last frame")
        XCTAssertEqual(right.curve(.x)?.keys.map(\.frame), [0, 7])
        XCTAssertEqual(left.curve(.rotation)?.keys.map(\.frame), [2, 4], "each component splits on its own keys")
        XCTAssertEqual(right.curve(.rotation)?.keys.map(\.frame), [0, 4])
        XCTAssertEqual(left.box, box)
        XCTAssertEqual(right.box, box)
    }

    /// The inserted key inherits the interpolation of the segment it lands in.
    func testSplittingAHoldLeavesAHoldOnBothSides() {
        let held = xTrack([(0, 0), (12, 120)], interpolation: .constant)
        let (left, right) = held.split(atCelLocalFrame: 5)
        XCTAssertEqual(dx(left, at: 4), 0)
        XCTAssertEqual(dx(right, at: 6), 0, "still holding one frame before the step")
        XCTAssertEqual(dx(right, at: 7)!, 120, accuracy: 1e-9, "and stepping on the key, as before")
    }

    /// A key on the cut is carried across whole, handles and all.
    func testAKeyOnTheCutKeepsItsHandles() {
        let authored = AnimationCurve.Key(frame: 6, value: rest.x + 60,
                                          inHandle: AnimationCurve.Handle(deltaFrames: -3, deltaValue: 4),
                                          outHandle: AnimationCurve.Handle(deltaFrames: 3, deltaValue: -4),
                                          tangentMode: .free, interpolation: .constant)
        var x = xTrack([(0, 0), (12, 120)]).curve(.x)!
        x.setKey(authored)
        let (left, right) = TransformTrack(box: box, curves: [.x: x]).split(atCelLocalFrame: 6)
        XCTAssertEqual(left.curve(.x)?.keys.map(\.frame), [0, 5])
        var rebased = authored
        rebased.frame = 0
        XCTAssertEqual(right.curve(.x)?.key(atFrame: 0), rebased)
    }

    /// TODO (62)'s crop, per component: the keys past the span go, each component's edge gains the
    /// value it showed there, and what went is reported per component.
    func testCroppingReportsWhatEachComponentLost() {
        var t = xTrack([(0, 0), (10, 100)])
        t.setCurve(AnimationCurve(keys: [.init(frame: 2, value: 0), .init(frame: 3, value: 9)]), for: .rotation)
        let (kept, discarded) = t.cropped(toFrameCount: 6)
        XCTAssertEqual(discarded, [.x: [10]], "rotation keeps both its keys, so it lost nothing")
        XCTAssertEqual(kept.curve(.x)?.keys.map(\.frame), [0, 5])
        XCTAssertEqual(kept.curve(.x)?.key(atFrame: 5)?.value ?? 0, rest.x + 50, accuracy: 1e-9)
        XCTAssertEqual(kept.curve(.rotation), t.curve(.rotation))
    }

    // MARK: - Persistence

    /// Everything the artist authored survives the round trip exactly, per component.
    func testAChannelRoundTripsThroughItsSidecarFormat() throws {
        var t = xTrack([(0, 0), (6, 60)], step: 3)
        t.setCurve(AnimationCurve(keys: [
            AnimationCurve.Key(frame: 12, value: 0.25,
                               inHandle: AnimationCurve.Handle(deltaFrames: -2, deltaValue: 0.3),
                               outHandle: AnimationCurve.Handle(deltaFrames: 2, deltaValue: -0.3),
                               tangentMode: .free, interpolation: .constant)]), for: .perspectiveX)
        let data = try JSONEncoder().encode(CelAnimationData(tracks: ["cel": t]))
        let back = try JSONDecoder().decode(CelAnimationData.self, from: data)
        XCTAssertEqual(back.tracks["cel"], t)
    }

    // MARK: - Channel ids

    /// The id format is the `effectTracks` idiom — `"<prefix>.<rest>"`.
    func testChannelIDsRoundTripAndAnUnknownOneIsIgnoredRatherThanTrapped() {
        let group = UUID()
        XCTAssertEqual(TransformChannelID(id: TransformChannelID.cel.id), .cel)
        XCTAssertEqual(TransformChannelID(id: TransformChannelID.group(group).id), .group(group))
        XCTAssertNil(TransformChannelID(id: "group.not-a-uuid"))
        XCTAssertNil(TransformChannelID(id: "somethingFromALaterVersion"))
    }
}
