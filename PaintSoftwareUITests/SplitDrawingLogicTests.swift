import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for VIDEO.md §8 stage 1 — the Split Drawing row in the cel menu, which is
/// `AnimationTimeline.swift`'s `.block` arm calling `CanvasManager.splitCel` for the first time
/// anywhere in the app, gated by `CanvasManager.canSplitCel`.
///
/// `splitCel` already had incidental coverage from `TransformChannelLogicTests` and
/// `InterpolatedCelCopyLogicTests`, both of which call it as a means to another end. Nothing pinned
/// the verb's own behavior on an ordinary drawing, and nothing at all pinned the gate — which lived
/// nowhere but a view's `if` statement until this file, exactly what CLAUDE.md's "a rule a view holds
/// is a rule the fast tier cannot see" is about.
final class SplitDrawingLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }

    override func setUp() {
        super.setUp()
        PixelOps.clearRasterizeCache()
    }

    // MARK: - Fixtures

    private func stroke(_ points: [CGPoint]) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
    }

    /// A manager with a vector layer (index 1) holding one cel over frames 3..<10 (`startFrame: 3,
    /// frameCount: 7`), carrying a real stroke. The span starts away from frame 0 on purpose — a
    /// `cut - cel.startFrame` bug would still pass a fixture that starts at 0, because 0 is its own
    /// identity element.
    private func fixture() -> (manager: CanvasManager, layerID: UUID, celID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: 3, frameCount: 7, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 20)]))
        manager.layers[1].cels = [cel]
        return (manager, manager.layers[1].id, cel.id)
    }

    private var box: CGRect { CGRect(x: 4, y: 6, width: 16, height: 8) }

    /// Two keys on the whole-cel channel — enough to make `transformTracks` non-empty, which is all
    /// the gate reads. The pose values themselves are not asserted on here.
    private func linearTrack() -> TransformTrack {
        TransformTrack(keys: [
            TransformTrack.Key(frame: 0, pose: PoseQuad(restingIn: box), interpolation: .linear),
            TransformTrack.Key(frame: 6, pose: PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 12, y: 0)),
                               interpolation: .linear)
        ])
    }

    /// The picture a cel shows from its own storage — what `splitCel`'s copy has to reproduce for
    /// "both halves hold the drawing" to mean anything beyond frame arithmetic.
    private func picture(_ cel: Cel) -> UIImage {
        PixelOps.rasterize(cel: cel, canvasSize: size)
    }

    private func bytes(_ image: UIImage) -> Data { image.pngData() ?? Data() }

    // MARK: - The verb, on an ordinary cel

    /// The verb itself, pinned on real content rather than on the index algebra alone: a cel
    /// spanning 3..<10, split at 6, becomes 3..<6 and 6..<10 — and **both halves show the same
    /// drawing the original cel showed**, not merely a cel of the right length.
    ///
    /// If this went red on the frame numbers alone the code could still be wrong in the way
    /// `InterpolatedCelCopyLogicTests` documents happened before: a `Cel(...)` built with a field
    /// defaulted away. The byte comparison is what a frame-count-only assertion would have missed.
    func testSplittingAnOrdinaryCelProducesTwoCelsBothHoldingTheDrawing() {
        let (manager, _, _) = fixture()
        let wantBytes = bytes(picture(manager.layers[1].cels[0]))
        XCTAssertFalse(wantBytes.isEmpty, "Setup: the fixture actually draws something")

        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 6)

        let cels = manager.layers[1].cels.sorted { $0.startFrame < $1.startFrame }
        XCTAssertEqual(cels.count, 2)
        XCTAssertEqual(cels[0].startFrame, 3)
        XCTAssertEqual(cels[0].frameCount, 3, "3..<6")
        XCTAssertEqual(cels[1].startFrame, 6)
        XCTAssertEqual(cels[1].frameCount, 4, "6..<10")

        XCTAssertEqual(bytes(picture(cels[0])), wantBytes, "left half holds the drawing")
        XCTAssertEqual(bytes(picture(cels[1])), wantBytes, "right half holds the same drawing")
    }

    /// One undo step restores one cel — the original span, with the drawing back, not just a cel of
    /// the right frame range.
    func testUndoingASplitRestoresOneCelWithTheDrawingIntact() {
        let (manager, _, _) = fixture()
        let wantBytes = bytes(picture(manager.layers[1].cels[0]))

        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 6)
        XCTAssertEqual(manager.layers[1].cels.count, 2, "Setup: the split happened")

        manager.undo()

        XCTAssertEqual(manager.layers[1].cels.count, 1)
        let restored = manager.layers[1].cels[0]
        XCTAssertEqual(restored.startFrame, 3)
        XCTAssertEqual(restored.frameCount, 7)
        XCTAssertEqual(bytes(picture(restored)), wantBytes, "the drawing is back, not just the frame range")
    }

    // MARK: - The gate: where the menu row is offered

    /// Every frame strictly inside the cel is offered; both edges and everything outside are not —
    /// the same boundary `splitCel`'s own guard enforces, asserted here as the predicate the menu row
    /// actually reads rather than as an inline `if`.
    func testCanSplitCelIsTrueOnlyStrictlyInsideTheCel() {
        let (manager, _, _) = fixture()
        for frame in [0, 1, 2, 3] {
            XCTAssertFalse(manager.canSplitCel(layerIndex: 1, celIndex: 0, atFrame: frame),
                           "frame \(frame) is at or before the start")
        }
        for frame in [4, 5, 6, 7, 8, 9] {
            XCTAssertTrue(manager.canSplitCel(layerIndex: 1, celIndex: 0, atFrame: frame),
                          "frame \(frame) is strictly inside 3..<10")
        }
        for frame in [10, 11, 12] {
            XCTAssertFalse(manager.canSplitCel(layerIndex: 1, celIndex: 0, atFrame: frame),
                           "frame \(frame) is at or past the end")
        }
    }

    /// A one-frame cel has no frame strictly between its own edges, so it can never be split — no
    /// special-case code needed for it, and this is what pins that the interior check alone does the
    /// job the brief asks for.
    func testCanSplitCelRefusesAOneFrameCel() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        manager.layers[1].cels = [Cel(id: UUID(), startFrame: 5, frameCount: 1, raster: .empty(size: size),
                                      vector: .empty(size: size))]
        for frame in 3...7 {
            XCTAssertFalse(manager.canSplitCel(layerIndex: 1, celIndex: 0, atFrame: frame),
                           "a one-frame cel has no frame strictly between its own edges")
        }
    }

    /// VIDEO.md §2.8 reads as a scope fence, not a safety claim — the owner's *"you dont need to add
    /// that functionality in"* says the verb wasn't worth building for a keyframed cel, not that
    /// splitting one is wrong. `testSplittingAKeyframedCelKeepsEveryFrameShowingThePoseItShowed`
    /// below is the proof it already was; this is the shallow half of that finding, at the gate a
    /// keyframed cel does **not** get excluded by.
    func testCanSplitCelAllowsAKeyframedCel() {
        let (manager, _, _) = fixture()
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: linearTrack()]

        XCTAssertTrue(manager.canSplitCel(layerIndex: 1, celIndex: 0, atFrame: 6),
                     "a pose channel does not exclude an otherwise-interior frame")
    }

    /// And the opposite must hold too: an interpolated in-between is **not** excluded by
    /// `canSplitCel`. VIDEO.md §7 is explicit that `splitCel` carries the recipe to both halves on
    /// purpose — a gate that also refused an in-between would contradict the verb it exists to guard.
    func testCanSplitCelAllowsAnInterpolatedCel() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cels = (0..<3).map { i in
            Cel(id: UUID(), startFrame: i * 4, frameCount: 4, raster: .empty(size: size), vector: .empty(size: size))
        }
        manager.layers[1].cels = cels
        cels[0].vector?.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 20)]))
        cels[2].vector?.addStroke(stroke([CGPoint(x: 34, y: 20), CGPoint(x: 54, y: 20)]))
        let layerID = manager.layers[1].id
        manager.enterInterpolateMode()
        for cel in [cels[0], cels[2]] {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: layerID)
        }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1),
                     "Setup: Generate must attach a recipe")
        manager.exitInterpolateMode()
        XCTAssertNotNil(manager.layers[1].cels[1].interpolation, "Setup: the middle cel carries the recipe")
        XCTAssertTrue(manager.layers[1].cels[1].transformTracks.isEmpty, "Setup: no pose channel is involved here")

        XCTAssertTrue(manager.canSplitCel(layerIndex: 1, celIndex: 1, atFrame: 6),
                     "an in-between at an interior frame is not excluded by interpolation alone")
    }

    // MARK: - Keyframe-animated cels: the proof the gate is built on

    /// **This is the test the keyframed-cel gate decision rests on**, and `canSplitCel` allows a
    /// keyframed cel *because* this passes, not the other way round — the question was open before
    /// this test was run, and this is what closed it. `splitCel` already ran
    /// `TransformTrack.split(atCelLocalFrame:)` on every channel regardless of what the menu's gate
    /// said; what was unproven was whether that machinery is trustworthy enough for the gate to rely
    /// on.
    ///
    /// `linearTrack()`'s two keys sit at local frames 0 and 6; the cut (absolute frame 7, cel-local
    /// 4) lands inside that segment, on neither key — so `TransformTrack.split` has to *synthesise*
    /// an interpolated pose on both sides of the boundary rather than relocate an existing key, and
    /// the surviving key at local 6 has to be relocated to local 2 in the right half. That is the
    /// specific risk: a key at cel-local N has to land at N−cut in the right half, and both halves
    /// need a correct pose exactly at the cut or the animation visibly jumps there. It passes: every
    /// frame's resolved pose, boundary included, comes back unchanged, which is why the gate does
    /// not exclude `transformTracks`. Had it gone red, the right fix would have been to leave
    /// `canSplitCel` refusing a keyframed cel and mark this `throw XCTSkip(...)` rather than delete
    /// it, so the next attempt starts from a known-red proof instead of no proof at all.
    func testSplittingAKeyframedCelKeepsEveryFrameShowingThePoseItShowed() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: 3, frameCount: 10, raster: .empty(size: size),
                      vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 20)]))
        manager.layers[1].cels = [cel]
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: linearTrack()]

        func shownDX(_ frame: Int) -> CGFloat? {
            guard let index = manager.activeCelIndex(inLayer: 1, atFrame: frame) else { return nil }
            let c = manager.layers[1].cels[index]
            guard let pose = manager.resolvedPose(layerID: manager.layers[1].id, celID: c.id,
                                                  channel: .cel, atFrame: frame) else { return nil }
            return pose.corners.p0.x - pose.box.minX
        }

        let before = (3...12).map { shownDX($0) }
        XCTAssertEqual(before.compactMap { $0 }.count, 10, "Setup: every frame is posed to begin with")

        manager.splitCel(layerIndex: 1, celIndex: 0, atFrame: 7)
        XCTAssertEqual(manager.layers[1].cels.count, 2, "Setup: the split happened")

        for (offset, frame) in Array(3...12).enumerated() {
            guard let now = shownDX(frame), let was = before[offset] else {
                XCTFail("frame \(frame) lost its pose across the cut")
                continue
            }
            XCTAssertEqual(now, was, accuracy: 1e-9,
                           "frame \(frame) shows the pose it showed before the cut, boundary included")
        }
    }
}
