import XCTest
import UIKit
import CoreGraphics

/// **Keys outside a cel's span are cropped, as one undo step that says what it discarded** — TODO
/// (62), settled 2026-09-10 with the objection in front of the owner (*"you'd lengthen the cel again
/// and find the animation gone"*): keys beyond a cel's span are deleted, shortening a cel crops the
/// keys past its new end, and a cel lengthened again after the crop does **not** get them back except
/// by undo.
///
/// Three things are pinned here, in order of how much damage each would do unpinned.
///
/// 1. **Which tracks the crop touches, and which it must not.** Only `Cel.transformTracks` is stored
///    on a cel in cel-local frames (KEYFRAMES.md §3.1's first row). `Layer.effectTracks`,
///    `Layer.channelTracks`, `Layer.keyframeMarks` and a transformation layer's `Layer.transform.track`
///    are on the layer in absolute document frames, apply at every frame of the document whether or
///    not the layer has a block there (`RenderTree` reads `layerTransform` with no cel gate), and are
///    therefore not "keys on a cel" at all. The no-op is pinned so a future "fix" cannot start
///    cropping document-frame tracks — that would be the silent loss this item exists to prevent,
///    reached through the other door.
/// 2. **Every verb that can shorten a span crops, from inside the undo step it already had.** The
///    two handles, split, a clamped duplicate and paste, and a video speed change. Each returns what
///    went, and the handle drags recompute from the gesture baseline so an out-and-back drag within
///    one gesture reports nothing.
/// 3. **The artist is told.** `CanvasNotice.keyframesCropped` carries the crop, is raised once when
///    the step lands, names the frames in the ruler's own 1-based numbers, and says undo brings them
///    back — which is asserted rather than assumed.
///
/// A fourth section, from the 2026-09-11 review, pins the three places the first pass left open:
/// a bracket that parked a crop and never raised it, a composite step whose later empty crop erased
/// an earlier one's report, and a writer that was still minting keys outside the span.
///
/// Mutation notes are on each test: what was broken to watch it go red.
///
/// `@MainActor` for `makeFrameRecipe`'s sake in the bake-key test; everything else is plain model.
@MainActor
final class CelSpanCropLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }
    private var box: CGRect { CGRect(x: 4, y: 6, width: 16, height: 8) }

    // MARK: - Fixtures

    private func stroke() -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: StrokeSamples([VectorSample(x: 6, y: 10, pressure: 1),
                                             VectorSample(x: 18, y: 10, pressure: 1)],
                                            channels: .pressureOnly))
    }

    private func slide(_ dx: CGFloat) -> PoseQuad {
        PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: dx, y: 0))
    }

    /// A `.linear` whole-cel channel: one key per `(celLocalFrame, dx)` pair. Linear so that "the
    /// pose at a frame the span still covers is unchanged" is exact rather than approximate.
    private func track(_ keys: [(Int, CGFloat)]) -> TransformTrack {
        TransformTrack(keys: keys.map { TransformTrack.Key(frame: $0.0, pose: slide($0.1), interpolation: .linear) })
    }

    /// A manager with a vector layer (index 1) holding one drawn cel over `start ..< start + length`,
    /// its whole-cel channel keyed at cel-local frames 0, 4 and 9 — the brief's own fixture.
    private func fixture(start: Int = 0, length: Int = 10,
                         keys: [(Int, CGFloat)] = [(0, 0), (4, 40), (9, 90)]) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: start, frameCount: length, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke())
        manager.layers[1].cels = [cel]
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track(keys)]
        return manager
    }

    private func keyFrames(_ manager: CanvasManager, cel: Int = 0) -> [Int]? {
        manager.layers[1].cels[cel].transformTracks[TransformChannelID.cel.id]?.keys.map(\.frame)
    }

    /// The x-offset the whole-cel channel shows at an **absolute** frame, or nil if unposed there.
    private func shownDX(_ manager: CanvasManager, atFrame frame: Int, layer: Int = 1) -> CGFloat? {
        guard let index = manager.activeCelIndex(inLayer: layer, atFrame: frame) else { return nil }
        let cel = manager.layers[layer].cels[index]
        guard let pose = manager.resolvedPose(layerID: manager.layers[layer].id, celID: cel.id,
                                              channel: .cel, atFrame: frame) else { return nil }
        return pose.corners.p0.x - pose.box.minX
    }

    /// The right-handle drag as the timeline performs it: one bracket, the verb on every `.changed`,
    /// one commit — so the undo step and the notice are the ones the artist gets.
    private func dragRightEdge(_ manager: CanvasManager, through ends: [Int], cel: Int = 0) {
        manager.beginStructureGesture()
        for end in ends { manager.resizeCelRightEdge(layerIndex: 1, celIndex: cel, newEndFrame: end) }
        manager.commitStructureGesture(label: .resizeFrame)
    }

    private func dragLeftEdge(_ manager: CanvasManager, through starts: [Int], cel: Int = 0) {
        manager.beginStructureGesture()
        for start in starts { manager.resizeCelLeftEdge(layerIndex: 1, celIndex: cel, newStartFrame: start) }
        manager.commitStructureGesture(label: .resizeFrame)
    }

    private func croppedNotice(_ manager: CanvasManager) -> KeyframeCrop? {
        guard case .keyframesCropped(let crop)? = manager.notice?.kind else { return nil }
        return crop
    }

    // MARK: - The right edge

    /// **The brief's own case.** Keys at 0, 4, 9 on a ten-frame cel; shorten to 6; keys 0 and 4
    /// remain and the return value names frame 9.
    ///
    /// Watched failing with `resizeCelRightEdge`'s `cropPoseKeysToSpan()` call removed: the keys read
    /// `[0, 4, 9]` and the crop is empty.
    func testShorteningACelFromTheRightCropsTheKeysPastItsNewEnd() {
        let manager = fixture()
        let crop = manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 6)

        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 6)
        XCTAssertEqual(keyFrames(manager), [0, 4], "the keys inside the new span stay")
        XCTAssertEqual(crop.frames, [9], "and the one past it is named, in absolute frames")
        XCTAssertEqual(crop.count, 1)
        XCTAssertEqual(crop.discarded, [TransformChannelID.cel.id: [9]], "attributed to its channel")
    }

    /// **The boundary is `frameCount`, and a key on it is outside.** A cel whose end is dragged to 9
    /// covers frames 0...8, so a key at 9 is one past its last frame and goes; dragged to 10 it
    /// stays. The off-by-one that keeps a key on the frame *after* the block is the one a `>` would
    /// make, and no other test here shortens to exactly a key's frame.
    ///
    /// Watched failing with `cropped(toFrameCount:)`'s `>=` changed to `>`: the first crop is empty.
    func testAKeyOnTheFrameJustPastTheNewEndIsOutside() {
        let manager = fixture()
        XCTAssertEqual(manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 9).frames, [9])
        XCTAssertEqual(keyFrames(manager), [0, 4])

        let again = fixture()
        XCTAssertTrue(again.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 10).isEmpty)
        XCTAssertEqual(keyFrames(again), [0, 4, 9], "a key on the last frame the block covers is inside")
    }

    /// The frames the span still covers show what the artist would expect of a curve that lost its
    /// last key: the pose at frame 4 is what it was, and frame 5 — which used to be a quarter of the
    /// way from key 4 to key 9 — now holds key 4's pose. That is what "cropped" means for the picture,
    /// and it is the change the bake has to see (`testTheBakeKeySeesTheCrop`).
    func testTheRemainingFramesResolveAgainstTheKeysThatRemain() {
        let manager = fixture()
        XCTAssertEqual(shownDX(manager, atFrame: 5)!, 50, accuracy: 1e-9, "Premise: frame 5 was mid-travel")
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 6)
        XCTAssertEqual(shownDX(manager, atFrame: 4)!, 40, accuracy: 1e-9)
        XCTAssertEqual(shownDX(manager, atFrame: 5)!, 40, accuracy: 1e-9,
                       "held at the last key that survived, not at a pose the cel no longer knows")
    }

    /// **One undo step.** Through the gesture bracket the timeline uses: the undo stack grows by
    /// exactly one, and one press brings back the key at 9 *and* the ten-frame span together.
    ///
    /// Watched failing with the crop moved out of the verb into a second `withStructureUndo` after
    /// the commit: the stack grew by two and the first undo restored the key on a six-frame cel.
    func testUndoRestoresTheKeyAndTheSpanInOneStep() {
        let manager = fixture()
        let before = manager.history.undoStack.count
        dragRightEdge(manager, through: [8, 6])
        XCTAssertEqual(keyFrames(manager), [0, 4], "Premise: the drag cropped")
        XCTAssertEqual(manager.history.undoStack.count, before + 1, "one gesture, one step")

        manager.undo()
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 10, "the span is back")
        XCTAssertEqual(keyFrames(manager), [0, 4, 9], "and the key with it, in the same press")
        XCTAssertEqual(shownDX(manager, atFrame: 9)!, 90, accuracy: 1e-9)

        manager.redo()
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 6)
        XCTAssertEqual(keyFrames(manager), [0, 4], "redo takes both away again")
    }

    /// **The ruling's hard half.** Shorten, then lengthen again as a second edit: the key at 9 stays
    /// gone. The owner chose this with the objection in front of them; it is pinned so nobody "fixes"
    /// it by holding a shadow copy.
    func testLengtheningAgainAfterACommittedCropDoesNotBringTheKeyBack() {
        let manager = fixture()
        dragRightEdge(manager, through: [6])
        XCTAssertEqual(croppedNotice(manager)?.frames, [9], "Premise: the shortening said so")
        manager.notice = nil   // the banner's timer, which the view owns
        dragRightEdge(manager, through: [10])
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 10)
        XCTAssertEqual(keyFrames(manager), [0, 4], "the key at 9 is gone until undo")
        XCTAssertEqual(shownDX(manager, atFrame: 9)!, 40, accuracy: 1e-9, "frame 9 holds key 4's pose")
        XCTAssertNil(croppedNotice(manager), "lengthening removed nothing, so it says nothing")
    }

    /// **But within one gesture, a drag past a key and back is not a crop.** The handles recompute
    /// the whole result from the gesture baseline on every `.changed` — the neighbours' positions
    /// already did, and the tracks now do too — so the committed state is the ten-frame cel with all
    /// three keys, and no notice is raised.
    ///
    /// Watched failing with `transformTracks = baselineCel.transformTracks` removed from the verb:
    /// the second `.changed` found the key already gone and the commit reported `[0, 4]`.
    func testADragPastAKeyAndBackWithinOneGestureKeepsIt() {
        let manager = fixture()
        dragRightEdge(manager, through: [8, 6, 5, 8, 10])
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 10)
        XCTAssertEqual(keyFrames(manager), [0, 4, 9])
        XCTAssertNil(croppedNotice(manager), "nothing was discarded at the commit, so nothing is said")
    }

    /// **Only the committed state is reported.** A drag that passes 9 and settles at 8 reports the
    /// key at 9 alone, not every key it passed on the way.
    func testTheNoticeReportsTheCommittedCropNotEveryChangedEvent() {
        let manager = fixture()
        dragRightEdge(manager, through: [5, 3, 8])
        XCTAssertEqual(keyFrames(manager), [0, 4])
        XCTAssertEqual(croppedNotice(manager)?.frames, [9])
    }

    // MARK: - The left edge

    /// **A left-edge resize crops the head and leaves the tail where it was.** Keys are cel-local, so
    /// when the origin moves from 10 to 15 every key's local number drops by 5: the keys at 0 and 4
    /// (document frames 10 and 14) fall below 0 and go; the key at 9 (document 19) becomes local 4
    /// and stays — and the pose at document frame 19 is exactly what it was. That is the video crop's
    /// reading of this edge (`writeVideoCrop(anchoredAt: .tail)`): what the block shows at a document
    /// frame it still covers does not change because its head was trimmed.
    ///
    /// Watched failing with `shiftingKeysBy:` passed as 0: the keys read `[0, 4]` — the animation slid
    /// five frames later in the document and the key at 19 was cropped as if it were at 24.
    func testShorteningACelFromTheLeftCropsTheKeysBeforeItsNewStart() {
        let manager = fixture(start: 10)
        XCTAssertEqual(shownDX(manager, atFrame: 19)!, 90, accuracy: 1e-9, "Premise")
        XCTAssertEqual(shownDX(manager, atFrame: 16)!, 60, accuracy: 1e-9, "Premise")

        let crop = manager.resizeCelLeftEdge(layerIndex: 1, celIndex: 0, newStartFrame: 15)

        XCTAssertEqual(manager.layers[1].cels[0].startFrame, 15)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 5)
        XCTAssertEqual(keyFrames(manager), [4], "the key at document 19 is now cel-local 4")
        XCTAssertEqual(crop.frames, [10, 14], "the two the edge passed, in absolute frames")
        XCTAssertEqual(shownDX(manager, atFrame: 19)!, 90, accuracy: 1e-9, "frame 19 is unchanged")
        XCTAssertEqual(shownDX(manager, atFrame: 16)!, 90, accuracy: 1e-9,
                       "frame 16 holds the one key left, since the one before it is gone")
    }

    /// Lengthening from the left crops nothing and shifts the keys the other way, so the drawing's
    /// motion stays on the document frames it was on and the new frames at the front hold the first
    /// key's pose (`AnimationCurve`'s decision 2).
    func testLengtheningFromTheLeftShiftsTheKeysAndCropsNothing() {
        let manager = fixture(start: 10)
        let crop = manager.resizeCelLeftEdge(layerIndex: 1, celIndex: 0, newStartFrame: 6)
        XCTAssertTrue(crop.isEmpty)
        XCTAssertEqual(keyFrames(manager), [4, 8, 13], "every key moved up by the four frames added")
        XCTAssertEqual(shownDX(manager, atFrame: 14)!, 40, accuracy: 1e-9, "document frame 14 unchanged")
        XCTAssertEqual(shownDX(manager, atFrame: 7)!, 0, accuracy: 1e-9, "the new head holds the first key")
    }

    /// The left handle through its gesture: one step, undo restores origin and keys together, and an
    /// out-and-back drag keeps everything.
    func testTheLeftHandleIsOneStepAndOutAndBackKeepsTheKeys() {
        let manager = fixture(start: 10)
        let before = manager.history.undoStack.count
        dragLeftEdge(manager, through: [12, 15])
        XCTAssertEqual(keyFrames(manager), [4])
        XCTAssertEqual(croppedNotice(manager)?.frames, [10, 14])
        XCTAssertEqual(manager.history.undoStack.count, before + 1)
        manager.undo()
        XCTAssertEqual(manager.layers[1].cels[0].startFrame, 10)
        XCTAssertEqual(keyFrames(manager), [0, 4, 9])

        manager.notice = nil
        dragLeftEdge(manager, through: [15, 12, 10])
        XCTAssertEqual(keyFrames(manager), [0, 4, 9], "out and back within one gesture")
        XCTAssertNil(croppedNotice(manager))
    }

    /// A predecessor shoved earlier by the resize keeps its keys: its origin moves and its keys are
    /// numbered from it, so nothing of its is outside its span and nothing of its is reported.
    func testAPushedNeighbourKeepsEveryKey() {
        let manager = fixture(start: 10)
        let neighbour = Cel(id: UUID(), startFrame: 4, frameCount: 6, raster: .empty(size: size),
                            vector: .empty(size: size))
        manager.layers[1].cels.insert(neighbour, at: 0)
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track([(0, 0), (5, 50)])]

        let crop = manager.resizeCelLeftEdge(layerIndex: 1, celIndex: 1, newStartFrame: 7)
        XCTAssertEqual(manager.layers[1].cels[0].startFrame, 1, "Premise: the neighbour was pushed")
        XCTAssertEqual(keyFrames(manager, cel: 0), [0, 5], "and carries its keys with it")
        XCTAssertTrue(crop.isEmpty, "lengthening the resized cel cropped nothing either")
    }

    // MARK: - Split

    /// **A split leaves no key outside either half.** Keys at 0 and 9 on ten frames, cut at 5: the
    /// left half ends on a synthesised key at its last frame (4), the right half starts on one at
    /// its first (0), nothing is cropped, and every frame still shows what it showed. Until
    /// 2026-09-11 the left half kept a key at 5 — one past its own span — which this ruling forbids.
    ///
    /// Watched failing with `split`'s left insertion put back at `cut`: the crop reports frame 5 and
    /// the left keys read `[0]`, which then stops the drawing dead at frame 0's pose.
    func testASplitLeavesEveryKeyInsideItsHalfAndEveryFrameUnchanged() {
        let manager = fixture(keys: [(0, 0), (9, 90)])
        let before = (0..<10).map { shownDX(manager, atFrame: $0) }
        let crop = manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 5)

        XCTAssertTrue(crop.isEmpty, "a split under the current rule discards nothing")
        XCTAssertEqual(keyFrames(manager, cel: 0), [0, 4])
        XCTAssertEqual(keyFrames(manager, cel: 1), [0, 4])
        for (cel, count) in [(0, 5), (1, 5)] {
            for key in manager.layers[1].cels[cel].transformTracks.values.flatMap(\.keys) {
                XCTAssertTrue((0..<count).contains(key.frame), "cel \(cel) key at \(key.frame) is inside 0..<\(count)")
            }
        }
        for frame in 0..<10 {
            XCTAssertEqual(shownDX(manager, atFrame: frame)!, before[frame]!, accuracy: 1e-9,
                           "frame \(frame) shows what it showed")
        }
        XCTAssertNil(croppedNotice(manager))
    }

    /// A document written while §3.1 still held keys outside a span carries them until something
    /// touches the cel. A split is that something: the stray goes, and it is named.
    func testASplitCropsAStrayKeyALegacyDocumentCarriedAndNamesIt() {
        let manager = fixture(keys: [(0, 0), (12, 120)])   // 12 is two past a ten-frame cel
        let crop = manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 5)
        XCTAssertEqual(crop.frames, [12])
        XCTAssertEqual(keyFrames(manager, cel: 0), [0, 4])
        XCTAssertEqual(keyFrames(manager, cel: 1), [0],
                       "the stray went right as local 7, past a five-frame half, and only the cut key remains")
        XCTAssertEqual(croppedNotice(manager)?.frames, [12], "raised, since splitCel records its own step")
        manager.undo()
        XCTAssertEqual(keyFrames(manager), [0, 12], "one undo, and the legacy key is back as it was")
    }

    // MARK: - Copies clamped shorter than their source

    /// `duplicateCel` lands at the source's end and is clamped to the room before the next block. A
    /// copy shorter than its source arrives with the source's later keys outside its own span; they
    /// go, the source keeps all of its own, and the banner names them at the *copy's* frames.
    ///
    /// Watched failing with `duplicateCel`'s `cropPoseKeysToSpan()` removed: the copy's keys read
    /// `[0, 4, 9]` on a five-frame cel.
    func testADuplicateClampedShorterThanItsSourceIsCroppedAndSaysSo() {
        let manager = fixture()
        let wall = Cel(id: UUID(), startFrame: 15, frameCount: 3, raster: .empty(size: size),
                       vector: .empty(size: size))
        manager.layers[1].cels.append(wall)

        let crop = manager.duplicateCel(layerIndex: 1, celIndex: 0)
        XCTAssertEqual(manager.layers[1].cels.count, 3)
        let copy = manager.layers[1].cels[1]
        XCTAssertEqual(copy.startFrame, 10)
        XCTAssertEqual(copy.frameCount, 5, "Premise: clamped by the wall at 15")
        XCTAssertEqual(keyFrames(manager, cel: 1), [0, 4])
        XCTAssertEqual(keyFrames(manager, cel: 0), [0, 4, 9], "the source is untouched")
        XCTAssertEqual(crop.frames, [19], "10 + 9: where the copy would have had it")
        XCTAssertEqual(croppedNotice(manager)?.frames, [19])
        manager.undo()
        XCTAssertEqual(manager.layers[1].cels.count, 2, "one step takes the copy away whole")
    }

    /// The same through the clipboard. `pasteCel` keeps its `Bool`, so the report is the notice.
    func testAPasteClampedShorterThanTheClipboardIsCroppedAndSaysSo() throws {
        let manager = fixture()
        let wall = Cel(id: UUID(), startFrame: 24, frameCount: 3, raster: .empty(size: size),
                       vector: .empty(size: size))
        manager.layers[1].cels.append(wall)
        manager.copyCel(layerIndex: 1, celIndex: 0)

        XCTAssertTrue(manager.pasteCel(layerIndex: 1, startFrame: 20))
        let pasted = try XCTUnwrap(manager.layers[1].cels.first { $0.startFrame == 20 })
        XCTAssertEqual(pasted.frameCount, 4, "Premise: clamped by the wall at 24")
        XCTAssertEqual(pasted.transformTracks[TransformChannelID.cel.id]?.keys.map(\.frame), [0],
                       "4 and 9 are past a four-frame cel")
        XCTAssertEqual(croppedNotice(manager)?.frames, [24, 29])
        XCTAssertEqual(manager.copiedCel?.transformTracks[TransformChannelID.cel.id]?.keys.map(\.frame),
                       [0, 4, 9], "the clipboard keeps everything for the next paste")
    }

    /// A full-length copy discards nothing and raises nothing — the common case has to stay silent.
    func testAFullLengthDuplicateSaysNothing() {
        let manager = fixture()
        let crop = manager.duplicateCel(layerIndex: 1, celIndex: 0)
        XCTAssertTrue(crop.isEmpty)
        XCTAssertEqual(keyFrames(manager, cel: 1), [0, 4, 9])
        XCTAssertNil(manager.notice)
    }

    // MARK: - The tracks the crop must not touch

    /// **A layer-level track is untouched by any span change, and that is by construction rather
    /// than by exemption.** `channelTracks` (opacity), `effectTracks`, `keyframeMarks` and a
    /// transformation layer's own pose track are stored on the layer in absolute document frames and
    /// apply at every frame whether or not the layer has a block there — so there is no span for a key
    /// of theirs to be outside of. The ask is a no-op for them, pinned so a future "fix" cannot start
    /// cropping document-frame tracks.
    ///
    /// Watched failing with a deliberate `channelTracks` filter added beside the crop: the opacity
    /// keys read `[0]` and `keyframeFrames` lost frame 9.
    func testLayerLevelTracksAndMarksAreUntouchedByEverySpanChange() {
        let manager = fixture()
        let layerID = manager.layers[1].id
        let opacity = AnimationCurve(keys: [.init(frame: 0, value: 1), .init(frame: 9, value: 0.2)])
        manager.layers[1].channelTracks = [TargetChannel.opacity.id: opacity]
        manager.layers[1].effectTracks = ["blur.radius": AnimationCurve(keys: [.init(frame: 0, value: 0), .init(frame: 11, value: 8)])]
        manager.layers[1].keyframeMarks = [8]
        let framesBefore = manager.keyframeFrames(of: .layer(id: layerID))
        XCTAssertEqual(framesBefore, [0, 4, 8, 9], "Premise: marks, opacity keys and pose keys all count")

        // A transformation layer of its own, with a block it could be said to "ride".
        manager.addValueLayer()
        manager.layers[2].fill = nil
        manager.layers[2].cels = [Cel(id: UUID(), startFrame: 0, frameCount: 12, raster: .empty(size: size))]
        let rest = PoseQuad(restingIn: CGRect(origin: .zero, size: size))
        manager.layers[2].transform = LayerPose(pose: rest, track: TransformTrack(keys: [
            .init(frame: 0, pose: rest), .init(frame: 11, pose: slide(24))]))

        var crop = manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 6)
        crop.merge(manager.resizeCelLeftEdge(layerIndex: 1, celIndex: 0, newStartFrame: 2))
        crop.merge(manager.resizeCelRightEdge(layerIndex: 2, celIndex: 0, newEndFrame: 4))
        crop.merge(manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 4))

        XCTAssertEqual(crop.discarded.keys.sorted(), [TransformChannelID.cel.id],
                       "only the cel's own channel ever appears in a crop")
        XCTAssertEqual(manager.layers[1].channelTracks[TargetChannel.opacity.id]?.keys.map(\.frame), [0, 9])
        XCTAssertEqual(manager.layers[1].effectTracks["blur.radius"]?.keys.map(\.frame), [0, 11])
        XCTAssertEqual(manager.layers[1].keyframeMarks, [8], "a mark is the layer's, not the cel's, and it stays")
        XCTAssertEqual(manager.layers[2].transform?.track.keyedFrames, [0, 11],
                       "a transformation layer's keys are in document frames and do not ride its block")
        XCTAssertTrue(manager.keyframeFrames(of: .layer(id: layerID)).contains(8),
                      "the timeline still draws the mark, on a frame no block of this layer covers")
        XCTAssertTrue(manager.keyframeFrames(of: .layer(id: layerID)).contains(9),
                      "and the opacity key at 9, likewise")
    }

    /// Deleting a cel takes its keys with it and can leave none outside anything; the layer's own
    /// tracks stay. Moving a block moves its keys with it and crops nothing.
    func testDeleteAndMoveLeaveNoKeyOutsideAndCropNothing() {
        let manager = fixture()
        let layerID = manager.layers[1].id
        manager.layers[1].channelTracks = [TargetChannel.opacity.id: AnimationCurve(keys: [.init(frame: 0, value: 1), .init(frame: 9, value: 0)])]
        manager.addBlankCelAfter(layerIndex: 1, celIndex: 0, length: 2)

        manager.moveCel(layerIndex: 1, celIndex: 0, newStartFrame: 0)
        XCTAssertEqual(keyFrames(manager), [0, 4, 9])
        XCTAssertNil(manager.notice)

        manager.deleteCel(layerIndex: 1, celIndex: 0)
        XCTAssertEqual(manager.layers[1].cels.count, 1)
        XCTAssertTrue(manager.layers[1].cels[0].transformTracks.isEmpty, "the survivor never had a channel")
        XCTAssertEqual(manager.keyframeFrames(of: .layer(id: layerID)), [0, 9], "the opacity keys are the layer's")
        XCTAssertNil(croppedNotice(manager), "a delete is not a crop and does not say it was")
    }

    // MARK: - The video speed row

    /// A faster clip is a shorter block, and a shorter block crops its keys — the one span change
    /// that is not a handle or a cut. The clip is a real file so `setVideoSpeed`'s own guard passes.
    func testAFasterVideoSpeedCropsTheKeysPastTheShorterBlock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cel-span-crop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
        defer {
            VideoImportStore.directoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("clip.mp4")
        try CanvasFixture.writeGreyClip(levels: (0..<24).map { UInt8(30 + $0 * 8) }, fps: 24, side: 64, to: url)

        let manager = CanvasFixture.manager(layerCount: 1)
        manager.fps = 24
        XCTAssertTrue(manager.insertVideo(at: url))
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 12)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 12, "Premise")
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track([(0, 0), (4, 40), (9, 90)])]

        manager.setVideoSpeed(layerIndex: 1, celIndex: 0, to: 2)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 6, "Premise: 2x halves the block")
        XCTAssertEqual(keyFrames(manager), [0, 4])
        XCTAssertEqual(croppedNotice(manager)?.frames, [9])
        manager.undo()
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 12)
        XCTAssertEqual(keyFrames(manager), [0, 4, 9], "one step, speed and keys together")
    }

    // MARK: - What the artist reads

    /// The sentence: count, frames in the ruler's 1-based numbers, and the way back.
    func testTheNoticeNamesTheCountAndTheFramesAsTheRulerShowsThem() {
        var one = KeyframeCrop()
        one.record(channel: "cel", frames: [9])
        XCTAssertEqual(CanvasNotice(.keyframesCropped(one)).message,
                       "1 keyframe outside the block's new length was removed (frame 10). Undo brings it back.")
        XCTAssertEqual(CanvasNotice(.keyframesCropped(one)).code, "keyframesCropped")
        XCTAssertNil(CanvasNotice(.keyframesCropped(one)).actionTitle, "undo is on the toolbar, as for every report")

        var many = KeyframeCrop()
        many.record(channel: "cel", frames: [4, 9])
        many.record(channel: "group.\(UUID().uuidString)", frames: [9, 11])
        XCTAssertEqual(many.count, 4)
        XCTAssertEqual(many.frames, [4, 9, 11], "two channels keyed on 9 lose two keys and name one frame")
        XCTAssertEqual(CanvasNotice(.keyframesCropped(many)).message,
                       "4 keyframes outside the block's new length were removed (frames 5, 10 and 12). Undo brings them back.")
    }

    /// **The notice is raised when the step lands, not before, and only once.** Through the gesture
    /// bracket: nothing during the drag, one banner at the commit, carrying the committed crop.
    ///
    /// Watched failing with `flushPendingKeyframeCrop()` removed from `commitStructureGesture`: no
    /// banner at all.
    func testTheNoticeArrivesWithTheCommitAndNotDuringTheDrag() {
        let manager = fixture()
        manager.beginStructureGesture()
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 6)
        XCTAssertNil(manager.notice, "mid-drag there is no step yet, so 'undo brings it back' would be false")
        manager.commitStructureGesture(label: .resizeFrame)
        XCTAssertEqual(croppedNotice(manager)?.frames, [9])
        XCTAssertTrue(manager.history.canUndo, "and the step it promises is on the stack")
    }

    /// **A cancelled drag reports nothing, then or later.** The verb parked a crop during the drag;
    /// the cancel recorded no step, so that crop has no step to belong to — and it must not be
    /// claimed by the next unrelated step, which would announce a crop that never happened.
    ///
    /// Watched failing with `pendingKeyframeCrop = nil` removed from `cancelStructureGesture`: the
    /// `addCel` below raises the resize's crop as its own.
    func testACancelledDragReportsNothingThenOrLater() {
        let manager = fixture()
        manager.beginStructureGesture()
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 6)
        manager.cancelStructureGesture()
        XCTAssertNil(manager.notice)
        XCTAssertNil(manager.pendingKeyframeCrop)

        XCTAssertTrue(manager.addCel(layerIndex: 1, startFrame: 20))
        XCTAssertNil(manager.notice, "an unrelated step later does not inherit the cancelled drag's crop")
    }

    /// A bare call outside any bracket registers no undo step, so it raises nothing: the sentence
    /// would be a lie there. The verb's return value is its whole report, and it is what every test
    /// above that calls a handle verb directly reads.
    func testABareVerbCallOutsideAnyBracketReturnsTheCropAndRaisesNoNotice() {
        let manager = fixture()
        let crop = manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 6)
        XCTAssertEqual(crop.frames, [9])
        XCTAssertNil(manager.notice)
        XCTAssertNil(manager.pendingKeyframeCrop, "nothing is parked for a later, unrelated step to claim")
    }

    // MARK: - The bake sees it

    /// **A cropped key changes the picture at frames inside the span, and the bake key says so.**
    /// Frame 5 used to be a quarter of the way from key 4 to key 9; with 9 gone it holds key 4's pose,
    /// which is a different derivation and therefore a different `FrameBakeKey`. Frame 0 rests in
    /// both documents and its key does not move — the control that says the change is the crop's.
    func testTheBakeKeySeesTheCrop() throws {
        let manager = fixture()
        func key(_ frame: Int) throws -> FrameBakeKey {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: frame, includeBackground: true))
            return FrameBakeKey(recipe: recipe, renderResolution: manager.renderResolution)
        }
        let at5 = try key(5)
        let at0 = try key(0)
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: 6)
        XCTAssertNotEqual(try key(5), at5, "frame 5 draws a different pose now, and the bake must re-mint it")
        XCTAssertEqual(try key(0), at0, "frame 0 draws what it drew")
    }

    // MARK: - What the review found open (2026-09-11)

    /// A cel of `length` frames at `start`, drawn, with no channel.
    private func drawnCel(start: Int, length: Int) -> Cel {
        let cel = Cel(id: UUID(), startFrame: start, frameCount: length, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke())
        return cel
    }

    /// **`withInterpolationUndo` is a third door, and a door that parks must raise.** It lifts
    /// `structureUndoDepth`, so a `splitCel` under it parks its crop; until the review it never
    /// flushed, and the crop leaked to the next unrelated step — which announced it as its own and
    /// promised an undo that would not have brought the key back.
    ///
    /// Watched failing with `flushPendingKeyframeCrop()` removed from `withInterpolationUndo`: the
    /// crop stays parked, the split says nothing, and `addCel` raises it.
    func testACropUnderTheInterpolationBracketIsAnnouncedThereAndNotByTheNextStep() {
        let manager = fixture(keys: [(0, 0), (12, 120)])   // a legacy stray at 12
        manager.withInterpolationUndo(label: .interpolate) {
            manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 5)
        }
        XCTAssertEqual(keyFrames(manager, cel: 1), [0], "Premise: the stray at 12 was cropped from the right half")
        XCTAssertNil(manager.pendingKeyframeCrop, "the step that owns the crop is on the stack; nothing stays parked")
        XCTAssertEqual(croppedNotice(manager)?.frames, [12], "announced against that step")

        manager.notice = nil
        XCTAssertTrue(manager.addCel(layerIndex: 1, startFrame: 20))
        XCTAssertNil(manager.notice, "an unrelated step does not announce the split's crop as its own")
    }

    /// The same door as the artist reaches it: a video bake splits the block once per frame under
    /// `withInterpolationUndo`. On a two-frame block carrying a legacy stray the one split crops it.
    func testABakeAnnouncesItsOwnCropAndLeavesNothingParked() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cel-span-crop-bake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
        defer {
            VideoImportStore.directoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("clip.mp4")
        try CanvasFixture.writeGreyClip(levels: (0..<6).map { UInt8(30 + $0 * 30) }, fps: 24, side: 64, to: url)

        let manager = CanvasFixture.manager(layerCount: 1)
        manager.fps = 24
        XCTAssertTrue(manager.insertVideo(at: url))
        let start = manager.layers[1].cels[0].startFrame
        manager.resizeCelRightEdge(layerIndex: 1, celIndex: 0, newEndFrame: start + 2)
        XCTAssertEqual(manager.layers[1].cels[0].frameCount, 2, "Premise")
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track([(0, 0), (2, 20)])]

        guard case .baked = manager.bakeVideoToCels(layerIndex: 1, celIndex: 0) else {
            return XCTFail("Premise: the bake ran")
        }
        XCTAssertNil(manager.pendingKeyframeCrop, "nothing stays parked once the bake's step is recorded")
        XCTAssertEqual(croppedNotice(manager)?.frames, [start + 2], "the bake's own step says what its split cropped")
        manager.notice = nil
        XCTAssertTrue(manager.addCel(layerIndex: 1, startFrame: 30))
        XCTAssertNil(manager.notice, "an unrelated step does not announce the bake's crop as its own")
    }

    /// **A discrete step accumulates its crops; only a gesture replaces.** A merge splits both layers
    /// at every boundary the pair has. The first split here crops a legacy stray; the second crops
    /// nothing — and until the review `noteKeyframeCrop` replaced the parked crop with nil, so the
    /// key went and the banner did not. The merge stays vector, so no other banner covers it.
    ///
    /// Watched failing with `noteKeyframeCrop` replacing at every depth: the notice is nil.
    func testAMergeWhoseLaterSplitCropsNothingStillReportsTheEarlierCrop() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.addVectorLayer()
        manager.layers[1].cels = [Cel(id: UUID(), startFrame: 4, frameCount: 2, raster: .empty(size: size),
                                      vector: .empty(size: size))]
        manager.layers[2].cels = [drawnCel(start: 0, length: 10)]
        manager.layers[2].cels[0].transformTracks = [TransformChannelID.cel.id: track([(0, 0), (4, 0), (12, 120)])]
        manager.currentFrame = 4
        XCTAssertEqual(shownDX(manager, atFrame: 8, layer: 2)!, 60, accuracy: 1e-9, "Premise: the stray drives frames 5..9")

        XCTAssertTrue(manager.mergeLayers(manager.layers[1].id, manager.layers[2].id))
        XCTAssertEqual(manager.layers.count, 2, "Premise: merged")
        XCTAssertEqual(shownDX(manager, atFrame: 8)!, 0, accuracy: 1e-9,
                       "Premise: the stray is gone and frame 8 no longer travels")
        XCTAssertEqual(croppedNotice(manager)?.frames, [12], "the crop the merge made is announced")
    }

    /// **The mark workflow seeds neighbours inside the block, and only there.** Marks at 5 and 15 on
    /// a layer whose first block is 0..<10: a Move at 5 takes the `.seedAndKey` arm, and the nearest
    /// keyframe above the playhead is on the *next* block. Until the review it was seeded anyway, as a
    /// key at cel-local 15 on a ten-frame cel — outside the span the moment it was written, and
    /// cropped by the next resize with a banner naming a frame the artist never keyed on this block.
    ///
    /// Watched failing with the span filter removed from `seedAndKeyPose`: keys `[5, 15]`, and
    /// frame 9 reads -8, on its way back to a pose the block never reaches.
    func testAMoveSeededFromAMarkPastTheBlockKeysInsideItsOwnSpan() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [drawnCel(start: 0, length: 10), drawnCel(start: 10, length: 10)]
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 5))
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 15))
        let layerID = manager.layers[1].id
        let celID = manager.layers[1].cels[0].id

        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel,
                                                restBox: box,
                                                map: PoseMap(CGAffineTransform(translationX: 20, y: 0)),
                                                restElements: [], atFrame: 5)
        XCTAssertEqual(route, .seedAndKey, "Premise")
        XCTAssertEqual(keyFrames(manager, cel: 0), [5], "the neighbour on the next block is not this block's")
        XCTAssertEqual(shownDX(manager, atFrame: 9)!, 0, accuracy: 1e-9,
                       "the drawing stays where the artist put it to the block's end")
        XCTAssertTrue(manager.layers[1].cels[1].transformTracks.isEmpty, "and the next block was not touched")
    }

    /// The other side of the same fence: the block is 10..<20, the mark below the playhead is at 5,
    /// and the seeded key landed at cel-local -5 — the "no stored key is below 0" premise that
    /// `splitCel`'s left-half crop was once deleted on.
    ///
    /// Watched failing with the filter removed: keys `[-5, 5]`, frame 10 reads -10.
    func testAMoveSeededFromAMarkBeforeTheBlockKeysInsideItsOwnSpan() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [drawnCel(start: 0, length: 10), drawnCel(start: 10, length: 10)]
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 5))
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 15))
        let layerID = manager.layers[1].id
        let celID = manager.layers[1].cels[1].id

        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel,
                                                restBox: box,
                                                map: PoseMap(CGAffineTransform(translationX: 20, y: 0)),
                                                restElements: [], atFrame: 15)
        XCTAssertEqual(route, .seedAndKey, "Premise")
        XCTAssertEqual(keyFrames(manager, cel: 1), [5], "cel-local 5 is document 15; nothing below 0")
        XCTAssertEqual(shownDX(manager, atFrame: 10)!, 0, accuracy: 1e-9, "the block's first frame holds the key")
    }

    /// The baseline arm through the same fence: a Move between marks holds the old pose, the next
    /// mark commits it onto the nearest keyframes either side — and the one above is on the next
    /// block.
    ///
    /// Watched failing with the filter removed from `poseDeltaForKeyframe`: keys `[2, 7, 15]`.
    func testAHeldPoseCommittedByAMarkKeysInsideItsOwnSpan() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [drawnCel(start: 0, length: 10), drawnCel(start: 10, length: 10)]
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 1))
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 2))
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 15))
        let layerID = manager.layers[1].id
        let celID = manager.layers[1].cels[0].id

        let route = manager.commitTransformPose(layerID: layerID, celID: celID, channel: .cel,
                                                restBox: box,
                                                map: PoseMap(CGAffineTransform(translationX: 20, y: 0)),
                                                restElements: [], atFrame: 5)
        XCTAssertEqual(route, .storedValueHoldingBaseline, "Premise")
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 7))
        XCTAssertEqual(keyFrames(manager, cel: 0), [2, 7], "the old pose on the mark below, the new on the mark; nothing past the block")
    }

    /// **The left half is cropped too.** A key below 0 — which the writer above used to mint, and
    /// which a document saved before the fence may still carry — stays below 0 in the left half of a
    /// split, and the crop there was deleted once as unreachable. It goes, and it is named.
    ///
    /// Watched failing with the left half's `cropPoseKeysToSpan()` removed from `splitCel`: the left
    /// keys read `[-5, 0, 4]` and the crop is empty.
    func testASplitCropsAKeyBelowZeroFromTheLeftHalfAndNamesIt() {
        let manager = fixture(start: 10, keys: [(-5, -50), (0, 0), (9, 90)])
        let crop = manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 15)
        XCTAssertEqual(keyFrames(manager, cel: 0), [0, 4])
        XCTAssertEqual(keyFrames(manager, cel: 1), [0, 4])
        XCTAssertEqual(crop.frames, [5], "10 + (-5): the document frame the key sat on, before the block")
        XCTAssertEqual(croppedNotice(manager)?.frames, [5])
        manager.undo()
        XCTAssertEqual(keyFrames(manager), [-5, 0, 9], "one undo brings the split and the key back together")
    }
}
