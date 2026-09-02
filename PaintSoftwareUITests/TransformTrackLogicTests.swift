import XCTest
import CoreGraphics

/// Pure-logic tests for one pose channel's storage and evaluation — KEYFRAMES.md §3.1, §3.2 and
/// §2.10, build-order stage 5.
///
/// `PoseInterpolationLogicTests` covers what happens *between* two poses. This covers which two, and
/// when: the cel-local time base, the timing spine over pose indices, the constant hold at both ends,
/// the step, and the invariant that decides whether the cel has a derivation at all.
final class TransformTrackLogicTests: XCTestCase {

    private let box = CGRect(x: 10, y: 10, width: 40, height: 20)

    private func moved(_ dx: CGFloat, _ dy: CGFloat = 0) -> PoseQuad {
        PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: dx, y: dy))
    }

    private func track(_ pairs: [(Int, CGFloat)],
                       interpolation: AnimationCurve.Interpolation = .linear,
                       step: Int = 1) -> TransformTrack {
        TransformTrack(keys: pairs.map { TransformTrack.Key(frame: $0.0, pose: moved($0.1),
                                                            interpolation: interpolation) },
                       step: step)
    }

    private func dx(_ pose: PoseQuad?) -> CGFloat? { pose.map { $0.corners.p0.x - box.minX } }

    // MARK: - Storage

    /// `AnimationCurve`'s decision 4, restated: at most one key per frame, sorted, and `setKey`
    /// replaces rather than appends. The timing spine is built **by index**, so a duplicate frame
    /// would make two indices name one moment and the blend would have nowhere to go.
    func testKeysAreSortedAndUniqueByFrame() {
        var t = TransformTrack(keys: [TransformTrack.Key(frame: 8, pose: moved(8)),
                                      TransformTrack.Key(frame: 0, pose: moved(0)),
                                      TransformTrack.Key(frame: 8, pose: moved(80))])
        XCTAssertEqual(t.keys.map(\.frame), [0, 8])
        XCTAssertEqual(dx(t.key(atFrame: 8)?.pose), 80, "Among keys on one frame the later one wins")

        t.setKey(TransformTrack.Key(frame: 4, pose: moved(4)))
        XCTAssertEqual(t.keys.map(\.frame), [0, 4, 8])
        t.removeKey(atFrame: 4)
        XCTAssertEqual(t.keys.map(\.frame), [0, 8])
    }

    /// The strict predicate. Two keys holding the same pose is a channel **in force** and not an
    /// animation — the distinction §2.23's surviving half exists for, and the reason routing asks a
    /// different question from the channel list.
    func testATrackIsAnAnimationOnlyWhenTwoKeysDisagree() {
        XCTAssertFalse(TransformTrack().isAnimated)
        XCTAssertFalse(track([(0, 12)]).isAnimated, "One key is a hold, not an animation")
        XCTAssertFalse(track([(0, 12), (8, 12)]).isAnimated, "Two equal poses animate nothing")
        XCTAssertTrue(track([(0, 0), (8, 12)]).isAnimated)
    }

    // MARK: - Evaluation

    /// The spine is an `AnimationCurve` over pose *indices*, so a `.linear` segment between two poses
    /// blends them linearly — and the endpoints come back as the authored keys.
    func testALinearSegmentWalksFromOnePoseToTheNext() {
        let t = track([(0, 0), (8, 80)])
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 0)), 0)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 4))!, 40, accuracy: 1e-9)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 8)), 80)
    }

    /// **Decision 2 arrives for free rather than as a special case**: outside the first and last key
    /// the curve is a constant hold, so a drawing moved by a track stays where the last key put it.
    /// Linear extrapolation here would carry it off the canvas over a long cel with nothing on screen
    /// to explain it.
    func testOutsideTheKeysThePoseIsHeldRatherThanExtrapolated() {
        let t = track([(4, 0), (8, 80)])
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 0)), 0)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: -20)), 0)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 40)), 80)
    }

    /// One key is a hold everywhere, which is what makes a single authored pose a legal state — it is
    /// exactly what the `.seedAndKey` arm produces before a second keyframe exists.
    func testASingleKeyHoldsAtEveryFrame() {
        let t = track([(3, 25)])
        for frame in -5...20 { XCTAssertEqual(dx(t.pose(atCelLocalFrame: frame)), 25) }
    }

    /// An empty channel has no pose, which is not the same as a resting one: nil means *this cel
    /// stores what it shows*, and it is what `mapping(atCelLocalFrame:)` turns into "no derivation".
    func testAnEmptyTrackHasNoPoseAtAll() {
        XCTAssertNil(TransformTrack().pose(atCelLocalFrame: 0))
        XCTAssertNil(TransformTrack().mapping(atCelLocalFrame: 0))
    }

    /// §2.10. Evaluate, then hold for `step` frames, anchored at frame **0 of the track's own base**
    /// rather than at the first key — `AnimationCurve.step`'s rule, so two channels on twos step on
    /// the same frames whatever the parity of their first keys.
    func testAStepOfTwoHoldsThePoseForPairsOfFrames() {
        let t = track([(0, 0), (8, 80)], step: 2)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 2))!, 20, accuracy: 1e-9)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 3))!, 20, accuracy: 1e-9,
                       "Frame 3 quantises down onto 2")
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 4))!, 40, accuracy: 1e-9)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 5))!, 40, accuracy: 1e-9)
    }

    /// A `.constant` segment holds its start pose and steps at the next key — the hold that lets an
    /// artist put a drawing somewhere and leave it there for a run of frames without the in-betweens
    /// sliding.
    func testAConstantSegmentHoldsAndThenSteps() {
        let t = track([(0, 0), (8, 80)], interpolation: .constant)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 7)), 0)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 8)), 80)
    }

    /// Three keys, and the segment the spine picks is the one the frame is in — the arithmetic that
    /// would go wrong if the fractional index were clamped to `0...1` instead of split into a pair
    /// and a fraction.
    func testThreeKeysResolveIntoTheRightPair() {
        let t = track([(0, 0), (4, 40), (12, 0)])
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 2))!, 20, accuracy: 1e-9)
        XCTAssertEqual(dx(t.pose(atCelLocalFrame: 8))!, 20, accuracy: 1e-9,
                       "Half way back down the second segment, not half way along the first")
    }

    /// **The predicate the whole derivation hangs off.** A track whose keys all hold the rest pose —
    /// which is what §2.27's seeding writes before anything has been moved — must cost the document
    /// nothing at all, because a non-nil answer here is a canvas-sized render and two extra cache
    /// entries per frame (§4.5).
    func testARestingChannelProducesNoMappingAndThereforeNoDerivation() {
        let resting = TransformTrack(keys: [TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box)),
                                            TransformTrack.Key(frame: 8, pose: PoseQuad(restingIn: box))])
        XCTAssertNil(resting.mapping(atCelLocalFrame: 0))
        XCTAssertNil(resting.mapping(atCelLocalFrame: 4))
        XCTAssertNil(resting.mapping(atCelLocalFrame: 8))

        let moving = track([(0, 0), (8, 80)])
        XCTAssertNil(moving.mapping(atCelLocalFrame: 0), "Frame 0's key is the rest pose")
        XCTAssertNotNil(moving.mapping(atCelLocalFrame: 1))
    }

    /// The frames a channel keys on, which `CanvasManager.keyframes(of:)` folds into §2.28's union
    /// after adding the cel's `startFrame`. Cel-local here, deliberately: the track rides its cel
    /// precisely because it does not know where the cel starts.
    func testKeyedFramesAreCelLocalAndAscending() {
        XCTAssertEqual(track([(8, 80), (0, 0), (4, 40)]).keyedFrames, [0, 4, 8])
    }

    // MARK: - Persistence

    /// §3.5. Field-presence versioning: a track written before a field existed decodes to its
    /// default, and everything the artist authored survives the round trip exactly.
    func testATrackRoundTripsThroughItsSidecarFormat() throws {
        var t = track([(0, 0), (6, 60)], step: 3)
        t.setKey(TransformTrack.Key(frame: 12, pose: moved(20, 5),
                                    inHandle: AnimationCurve.Handle(deltaFrames: -2, deltaValue: 0.3),
                                    outHandle: AnimationCurve.Handle(deltaFrames: 2, deltaValue: -0.3),
                                    tangentMode: .free, interpolation: .constant))
        let data = try JSONEncoder().encode(CelAnimationData(tracks: ["cel": t]))
        let back = try JSONDecoder().decode(CelAnimationData.self, from: data)
        XCTAssertEqual(back.tracks["cel"], t)
    }

    /// A sidecar with no `baselines` key at all — which is every one written before §2.27's held pose
    /// existed — loads with the animation intact and no held pose, rather than failing the cel.
    func testASidecarWithoutBaselinesLoadsTheAnimationAnyway() throws {
        let json = #"{"tracks":{"cel":{"step":1,"keys":[]}}}"#
        let back = try JSONDecoder().decode(CelAnimationData.self, from: Data(json.utf8))
        XCTAssertEqual(back.tracks.count, 1)
        XCTAssertTrue(back.baselines.isEmpty)
    }

    // MARK: - Channel ids

    /// The id format is the `effectTracks` idiom — `"<prefix>.<rest>"` — so a transform channel lands
    /// in the grouping `TimelineGraphChannelList.groupID(ofParameterID:)` already reads.
    func testChannelIDsRoundTripAndAnUnknownOneIsIgnoredRatherThanTrapped() {
        let group = UUID()
        XCTAssertEqual(TransformChannelID(id: TransformChannelID.cel.id), .cel)
        XCTAssertEqual(TransformChannelID(id: TransformChannelID.group(group).id), .group(group))
        XCTAssertNil(TransformChannelID(id: "group.not-a-uuid"))
        XCTAssertNil(TransformChannelID(id: "somethingFromALaterVersion"))
    }
}
