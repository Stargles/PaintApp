import XCTest
import UIKit
import CoreGraphics

/// Adversarial review probes for TODO (62). Each test is a hypothesis about a way the crop could
/// lose a key silently, announce a crop that undo does not reverse, or fail to be one step. A red
/// here is a finding; a green is a refuted hypothesis and is deleted before merge.
@MainActor
final class CelSpanCropReviewLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }
    private var box: CGRect { CGRect(x: 4, y: 6, width: 16, height: 8) }

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

    private func track(_ keys: [(Int, CGFloat)]) -> TransformTrack {
        TransformTrack(keys: keys.map { TransformTrack.Key(frame: $0.0, pose: slide($0.1), interpolation: .linear) })
    }

    private func drawnCel(start: Int, length: Int) -> Cel {
        let cel = Cel(id: UUID(), startFrame: start, frameCount: length, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke())
        return cel
    }

    private func keyFrames(_ manager: CanvasManager, layer: Int = 1, cel: Int = 0) -> [Int]? {
        manager.layers[layer].cels[cel].transformTracks[TransformChannelID.cel.id]?.keys.map(\.frame)
    }

    private func croppedNotice(_ manager: CanvasManager) -> KeyframeCrop? {
        guard case .keyframesCropped(let crop)? = manager.notice?.kind else { return nil }
        return crop
    }

    private func shownDX(_ manager: CanvasManager, layer: Int = 1, atFrame frame: Int) -> CGFloat? {
        guard let index = manager.activeCelIndex(inLayer: layer, atFrame: frame) else { return nil }
        let cel = manager.layers[layer].cels[index]
        guard let pose = manager.resolvedPose(layerID: manager.layers[layer].id, celID: cel.id,
                                              channel: .cel, atFrame: frame) else { return nil }
        return pose.corners.p0.x - pose.box.minX
    }

    // MARK: - P1: the interpolation bracket is a third door, and it does not flush

    /// A `splitCel` that crops under `withInterpolationUndo` parks its crop (depth > 0) and that
    /// bracket never raises it — so it leaks to the next unrelated structure step.
    func testACropUnderTheInterpolationBracketIsNotClaimedByTheNextStep() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [drawnCel(start: 0, length: 10)]
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track([(0, 0), (12, 120)])]

        manager.withInterpolationUndo(label: .interpolate) {
            manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 5)
        }
        XCTAssertEqual(keyFrames(manager, cel: 1), [0], "Premise: the stray at 12 was cropped from the right half")
        XCTAssertNil(manager.pendingKeyframeCrop, "the step that owns the crop is on the stack; nothing may stay parked")
        XCTAssertEqual(croppedNotice(manager)?.frames, [12], "and the crop was announced against that step")

        manager.notice = nil
        XCTAssertTrue(manager.addCel(layerIndex: 1, startFrame: 20))
        XCTAssertNil(manager.notice, "an unrelated step must not announce the split's crop as its own")
    }

    /// The same door reached the way the artist reaches it: a video bake on a two-frame block that
    /// carries a legacy stray key.
    func testABakeLeavesNoCropParkedForTheNextStep() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cel-span-crop-review-\(UUID().uuidString)", isDirectory: true)
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
        XCTAssertNil(manager.pendingKeyframeCrop, "nothing may stay parked after the bake's step is recorded")
        manager.notice = nil
        XCTAssertTrue(manager.addCel(layerIndex: 1, startFrame: 30))
        XCTAssertNil(manager.notice, "an unrelated step must not announce the bake's crop as its own")
    }

    // MARK: - P2: a composite step's later, empty crop erases the earlier one's report

    /// A merge splits both layers at every boundary. The first split crops a legacy stray; the second
    /// crops nothing and `noteKeyframeCrop` replaces the parked crop with nil. The merge stays vector
    /// so no other banner covers the silence.
    func testAMergeWhoseLaterSplitCropsNothingStillReportsTheEarlierCrop() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.addVectorLayer()
        manager.layers[1].cels = [Cel(id: UUID(), startFrame: 4, frameCount: 2, raster: .empty(size: size),
                                      vector: .empty(size: size))]
        manager.layers[2].cels = [drawnCel(start: 0, length: 10)]
        manager.layers[2].cels[0].transformTracks = [TransformChannelID.cel.id: track([(0, 0), (4, 0), (12, 120)])]
        manager.currentFrame = 4
        XCTAssertEqual(shownDX(manager, layer: 2, atFrame: 8)!, 60, accuracy: 1e-9, "Premise: the stray drives frames 5..9")

        XCTAssertTrue(manager.mergeLayers(manager.layers[1].id, manager.layers[2].id))
        XCTAssertEqual(manager.layers.count, 2, "Premise: merged")
        XCTAssertEqual(shownDX(manager, layer: 1, atFrame: 8)!, 0, accuracy: 1e-9,
                       "Premise: the stray is gone and frame 8 no longer travels")
        XCTAssertEqual(croppedNotice(manager)?.frames, [12], "the crop the merge made is announced")
    }

    // MARK: - P3: a live writer mints keys outside the span

    /// Marks at 5 and 15 on a layer whose first block is 0..<10; a Move at 5 seeds the old pose on the
    /// neighbouring keyframes, and the neighbour at 15 is past the block.
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
        let keys = try XCTUnwrap(keyFrames(manager, cel: 0))
        XCTAssertTrue(keys.allSatisfy { (0..<10).contains($0) }, "every key inside 0..<10, got \(keys)")
    }

    /// The other side: the block is 10..<20 and the mark below it is at 5, so the seeded key lands
    /// at cel-local -5.
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
        let keys = try XCTUnwrap(keyFrames(manager, cel: 1))
        XCTAssertTrue(keys.allSatisfy { (0..<10).contains($0) }, "every key inside 0..<10, got \(keys)")
    }

    /// The baseline arm: a Move between marks holds the old pose; the next mark commits it and seeds
    /// the neighbours — one of which is past the block.
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
        let keys = try XCTUnwrap(keyFrames(manager, cel: 0))
        XCTAssertTrue(keys.allSatisfy { (0..<10).contains($0) }, "every key inside 0..<10, got \(keys)")
    }

    // MARK: - P4: split's left half is not cropped, on the premise that no key is below 0

    func testASplitCropsAKeyBelowZeroFromTheLeftHalfAndNamesIt() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [drawnCel(start: 10, length: 10)]
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track([(-5, -50), (0, 0), (9, 90)])]

        let crop = manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 15)
        let left = keyFrames(manager, cel: 0) ?? []
        XCTAssertTrue(left.allSatisfy { (0..<5).contains($0) }, "left half keys inside 0..<5, got \(left)")
        XCTAssertEqual(crop.frames, [5], "the key at document frame 5 went, and is named")
    }

    // MARK: - P5: one undo step per verb

    func testSplitDuplicatePasteAndSpeedEachRecordExactlyOneStep() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [drawnCel(start: 0, length: 10)]
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track([(0, 0), (4, 40), (12, 120)])]
        var count = manager.history.undoStack.count

        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 5)
        XCTAssertEqual(manager.history.undoStack.count, count + 1, "split")
        count = manager.history.undoStack.count

        manager.layers[1].cels.append(Cel(id: UUID(), startFrame: 13, frameCount: 2, raster: .empty(size: size), vector: .empty(size: size)))
        manager.duplicateCel(layerIndex: 1, celIndex: 1)   // [5,10) copied to [10,13), clamped by the wall
        XCTAssertEqual(manager.history.undoStack.count, count + 1, "duplicate")
        count = manager.history.undoStack.count

        manager.copyCel(layerIndex: 1, celIndex: 0)
        XCTAssertTrue(manager.pasteCel(layerIndex: 1, startFrame: 15))
        XCTAssertEqual(manager.history.undoStack.count, count + 1, "paste")
    }

    // MARK: - P6: duplicateLayer (BUGS.md filing) — what else it drops

    func testDuplicateLayerCarriesTheTransformationLayersPose() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        let rest = PoseQuad(restingIn: CGRect(origin: .zero, size: size))
        manager.layers[1].transform = LayerPose(pose: rest, track: TransformTrack(keys: [
            .init(frame: 0, pose: rest), .init(frame: 11, pose: slide(24))]))
        manager.duplicateLayer(at: 1)
        XCTAssertNotNil(manager.layers[2].transform, "the copy is a transformation layer too")
        XCTAssertEqual(manager.layers[2].transform?.track.keyedFrames, [0, 11])
    }

    func testDuplicateLayerCarriesEveryCelsPoseChannels() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [drawnCel(start: 0, length: 10)]
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track([(0, 0), (9, 90)])]
        manager.duplicateLayer(at: 1)
        XCTAssertEqual(keyFrames(manager, layer: 2, cel: 0), [0, 9])
    }

    // MARK: - P7: split under a stepped track

    /// With `step: 3`, the left half's last frame samples inside its re-parameterised last segment
    /// rather than at the inserted key.
    func testASplitOfASteppedTrackKeepsTheLeftHalfsLastFrame() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [drawnCel(start: 0, length: 10)]
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: TransformTrack(
            keys: [.init(frame: 0, pose: slide(0), interpolation: .linear), .init(frame: 9, pose: slide(90), interpolation: .linear)],
            step: 3)]
        let before = (0..<10).map { shownDX(manager, atFrame: $0)! }
        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 5)
        let after = (0..<10).map { shownDX(manager, atFrame: $0)! }
        XCTAssertEqual(after[4], before[4], accuracy: 1e-9, "left half's last frame; before \(before) after \(after)")
    }
}
