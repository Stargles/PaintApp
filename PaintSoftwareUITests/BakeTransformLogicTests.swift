import XCTest
import UIKit
import CoreGraphics

/// **Bake on a transformation layer — TODO (131)**: *"Add the same feature for transform layers."*
///
/// The pin, said once: **the baked document renders, at every frame, the picture the transformation
/// layer made — byte for byte.** A transformation layer poses the drawings beneath it at rasterisation,
/// so baking it means writing that pose into each cel's geometry (`VectorCanvas.baking`, the same commit
/// Bake Animation makes, so the dab walk stays in rest space and the picture does not shimmer) or
/// resampling a raster cel's pixels through it. If the two renders ever differ, the bake is wrong, and
/// nothing about the model — a count of cels, a moved rectangle — can say so first.
///
/// What makes the pin honest: the fixtures are *moved* (the transformation layer really does shift the
/// picture, asserted before the bake), they include a stroke of the fixture Pencil (the brush §4.2
/// measured re-phasing its lattice under a naive re-walk), and the layer's share of the pose is read off
/// the render walk rather than recomputed — so every mode, and every layer stacked with it, is baked by
/// the one source of what a transformation layer does.
@MainActor
final class BakeTransformLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }
    private var canvasRect: CGRect { CGRect(origin: .zero, size: size) }

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func document() -> CanvasManager { CanvasFixture.manager(layerCount: 0) }

    private func index(_ id: UUID, _ manager: CanvasManager) -> Int {
        manager.layers.firstIndex { $0.id == id } ?? -1
    }

    private func pencil(_ points: [CGPoint]) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.pencil,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 5, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
    }

    /// A vector layer holding a crisp red square and a pencil line, near the left so a 24 pt slide stays
    /// on the canvas.
    @discardableResult
    private func addInk(_ manager: CanvasManager, _ name: String, at y: CGFloat = 14) -> UUID {
        manager.addVectorLayer(name: name)
        let at = manager.layers.firstIndex { $0.name == name }!
        let vector = manager.layers[at].cels[0].vector!
        vector.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 4, y: y, width: 10, height: 10), transform: nil),
                       color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        vector.addStroke(pencil([CGPoint(x: 8, y: y + 20), CGPoint(x: 16, y: y + 20), CGPoint(x: 26, y: y + 22)]))
        return manager.layers[at].id
    }

    @discardableResult
    private func addRaster(_ manager: CanvasManager, _ name: String) -> UUID {
        manager.addLayer(name: name)
        let at = manager.layers.firstIndex { $0.name == name }!
        CanvasFixture.setBakedContent(manager, layerIndex: at,
                                      CanvasFixture.solidImage(.blue, rect: CGRect(x: 4, y: 40, width: 10, height: 10)))
        return manager.layers[at].id
    }

    /// A transformation layer posing everything beneath it by `map`, at every frame.
    @discardableResult
    private func addMove(_ manager: CanvasManager, _ map: CGAffineTransform, name: String = "Move",
                         mode: TransformLayerMode = .move) -> UUID {
        manager.addTransformLayer(name: name)
        let at = manager.layers.firstIndex { $0.name == name }!
        manager.layers[at].transform = LayerPose(pose: PoseQuad(box: canvasRect, mappedBy: map), mode: mode)
        return manager.layers[at].id
    }

    /// A transformation layer sliding by `dx` at frame `last` and resting at frame 0.
    @discardableResult
    private func addSlide(_ manager: CanvasManager, by dx: CGFloat, until last: Int = 11,
                          name: String = "Slide") -> UUID {
        manager.addTransformLayer(name: name)
        let at = manager.layers.firstIndex { $0.name == name }!
        let rest = PoseQuad(restingIn: canvasRect)
        let moved = PoseQuad(box: canvasRect, mappedBy: CGAffineTransform(translationX: dx, y: 0))
        manager.layers[at].transform = LayerPose(pose: rest, track: TransformTrack(keys: [
            .init(frame: 0, pose: rest, interpolation: .linear),
            .init(frame: last, pose: moved, interpolation: .linear)]))
        return manager.layers[at].id
    }

    private func composite(_ manager: CanvasManager, frame: Int) throws -> [UInt8] {
        PixelOps.clearRasterizeCache()
        MaskResolver.clearCache()
        let image = try XCTUnwrap(manager.makeRenderRequest(atFrame: frame, includeBackground: false)
                                    .flatMap(Compositor.composite), "the document must composite at frame \(frame)")
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    /// Every frame of the scene, composited — what the artist would scrub through.
    private func scene(_ manager: CanvasManager, frames: Range<Int> = 0..<12) throws -> [[UInt8]] {
        try frames.map { try composite(manager, frame: $0) }
    }

    /// **Two renders compared as bytes, reported as a summary rather than a dump.**
    private func assertSameScene(_ got: [[UInt8]], _ want: [[UInt8]], _ message: String,
                                 tolerance: Int = 0, file: StaticString = #filePath, line: UInt = #line) {
        guard got.count == want.count else {
            return XCTFail("\(message): \(got.count) frames against \(want.count)", file: file, line: line)
        }
        for (frame, pair) in zip(got, want).enumerated() {
            guard pair.0.count == pair.1.count else {
                return XCTFail("\(message): frame \(frame) byte counts differ", file: file, line: line)
            }
            var worst = 0, differing = 0
            for i in pair.0.indices where pair.0[i] != pair.1[i] {
                differing += 1
                worst = max(worst, abs(Int(pair.0[i]) - Int(pair.1[i])))
            }
            XCTAssertLessThanOrEqual(worst, tolerance,
                                     "\(message): frame \(frame) — \(differing) bytes differ, worst by \(worst)",
                                     file: file, line: line)
        }
    }

    private func bake(_ manager: CanvasManager, _ id: UUID,
                      file: StaticString = #filePath, line: UInt = #line) -> CanvasManager.BakePlan? {
        let outcome = manager.bakeLayer(id: id)
        guard case .baked(let plan) = outcome else {
            XCTFail("Bake must run, got \(outcome)", file: file, line: line)
            return nil
        }
        return plan
    }

    private func bounds(_ bytes: [UInt8]) -> (minX: Int, maxX: Int)? {
        var minX = Int.max, maxX = -1
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) where bytes[(y * Int(size.width) + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
            }
        }
        return maxX < 0 ? nil : (minX, maxX)
    }

    // MARK: - A static Move

    /// **A Move nobody keyed bakes in place — no new cels, no prompt.** The layer slides the drawing
    /// 24 pt right; after the bake the drawing is where it was shown, the layer is gone, and the picture
    /// is the same bytes at every frame.
    func testAStaticMoveBakesIntoTheGeometryWithNoNewCels() throws {
        let manager = document()
        let ink = addInk(manager, "Ink")
        let move = addMove(manager, CGAffineTransform(translationX: 24, y: 0))
        let before = try scene(manager)
        XCTAssertEqual(bounds(before[0])?.minX, 4 + 24, "Premise: the transformation layer really does shift the picture")

        guard case .plan(let plan) = manager.bakePlan(forLayerID: move) else { return XCTFail("Must plan") }
        XCTAssertEqual(plan.addedCels.vector + plan.addedCels.raster, 0, "A pose that never changes is one drawing")
        XCTAssertFalse(plan.needsConfirmation)

        XCTAssertNotNil(bake(manager, move))

        XCTAssertEqual(manager.layers.map(\.id), [ink], "The transformation layer is removed")
        XCTAssertEqual(manager.layers[0].cels.count, 1, "…and no cel was cut")
        XCTAssertEqual(manager.layers[0].kind, .vector, "The drawing stays a drawing")
        assertSameScene(try scene(manager), before, "the baked picture is the posed picture")
    }

    func testBakingATransformLayerIsOneUndoStepThatBringsItAndTheOldGeometryBack() throws {
        let manager = document()
        let ink = addInk(manager, "Ink")
        let move = addMove(manager, CGAffineTransform(translationX: 24, y: 0))
        let before = try scene(manager)
        let stepsBefore = manager.history.undoStack.count

        XCTAssertNotNil(bake(manager, move))
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1)

        manager.undo()
        XCTAssertEqual(manager.layers.map(\.id), [ink, move], "The transformation layer is back")
        assertSameScene(try scene(manager), before, "…and the picture is exactly what it was, moved by the layer again")
        XCTAssertEqual(bounds(try composite(manager, frame: 0))?.minX, 28,
                       "…which is the drawing at its own place, posed — not a drawing already moved and posed twice")
    }

    // MARK: - A moving transformation layer

    /// **A pose that changes every frame is a drawing every frame** — Bake Animation's rule — and each
    /// baked frame is the frame the layer rendered, byte for byte, pencil lattice included.
    func testAMovingTransformBakesOneDrawingPerFrameAndEveryFrameIsByteIdentical() throws {
        let manager = document()
        let ink = addInk(manager, "Ink")
        let slide = addSlide(manager, by: 24)
        let before = try scene(manager)
        XCTAssertNotEqual(before[0], before[11], "Premise: the picture really moves across the scene")

        guard case .plan(let plan) = manager.bakePlan(forLayerID: slide) else { return XCTFail("Must plan") }
        XCTAssertEqual(plan.addedCels.vector, 11, "Twelve distinct frames from one cel: eleven more drawings")
        XCTAssertTrue(plan.needsConfirmation, "Added drawings cost every future save, so the artist is asked")
        XCTAssertTrue(plan.confirmationMessage.contains("11 drawings"), plan.confirmationMessage)

        manager.requestBake(layerID: slide)
        XCTAssertNotNil(manager.pendingBake)
        XCTAssertEqual(manager.layers.count, 2, "Nothing is written until the artist says so")
        manager.confirmPendingBake()

        XCTAssertEqual(manager.layers.map(\.id), [ink])
        XCTAssertEqual(manager.layers[0].cels.count, 12, "One cel a frame")
        assertSameScene(try scene(manager), before, "every baked frame is the animated frame")
    }

    /// A bar that covers only some of the scene cuts the cel at its edges and leaves the other frames
    /// alone, **cel channels included**: a drawing the layer did not move keeps its own animation.
    func testABarCoveringPartOfTheSceneBakesOnlyThoseFrames() throws {
        let manager = document()
        let ink = addInk(manager, "Ink")
        let move = addMove(manager, CGAffineTransform(translationX: 24, y: 0))
        manager.layers[index(move, manager)].cels[0].startFrame = 4
        manager.layers[index(move, manager)].cels[0].frameCount = 4
        let before = try scene(manager)
        XCTAssertNotEqual(before[3], before[4], "Premise: the move starts at the bar")

        manager.requestBake(layerID: move)
        XCTAssertNotNil(manager.pendingBake, "Two cuts add two drawings")
        manager.confirmPendingBake()

        XCTAssertEqual(manager.layers[index(ink, manager)].cels.map(\.startFrame), [0, 4, 8])
        assertSameScene(try scene(manager), before, "frames outside the bar are untouched, frames inside are carried")
    }

    // MARK: - Every mode, and the layers it is stacked with

    /// **Parallax gives each layer beneath its own share**, and the bake reads each layer's share off the
    /// walk — so two layers move by different amounts and both are baked right.
    func testParallaxIsBakedByEachLayersOwnShare() throws {
        let manager = document()
        addInk(manager, "Far", at: 4)
        addInk(manager, "Near", at: 34)
        let parallax = addMove(manager, CGAffineTransform(translationX: 20, y: 0), name: "Parallax", mode: .parallax)
        let before = try scene(manager)
        let far = try composite(manager, frame: 0)
        XCTAssertNotNil(bounds(far), "Premise: something is drawn")

        XCTAssertNotNil(bake(manager, parallax))

        assertSameScene(try scene(manager), before, "each layer is carried by its own share of the move")
    }

    /// **A transformation layer above the one being baked keeps posing the baked drawings** — the bake
    /// carries only its own share, and the share is the ratio of two walks, so the upper layer's pose is
    /// neither doubled nor lost. Translation and a turn do not commute, which is why this uses both.
    func testAnotherTransformationLayerAboveKeepsPosingTheBakedDrawing() throws {
        let manager = document()
        let ink = addInk(manager, "Ink")
        let inner = addMove(manager, CGAffineTransform(translationX: 12, y: 0), name: "Inner")
        let turn = CGAffineTransform(translationX: 32, y: 32).rotated(by: 0.3).translatedBy(x: -32, y: -32)
        let outer = addMove(manager, turn, name: "Outer")
        let before = try scene(manager)

        XCTAssertNotNil(bake(manager, inner))

        XCTAssertEqual(manager.layers.map(\.id), [ink, outer], "Only the baked layer is removed")
        assertSameScene(try scene(manager), before, "the outer layer still poses the drawing the inner one moved", tolerance: 2)
    }

    /// The other order: baking the **outer** layer when an inner one sits between it and the drawing.
    /// The geometry has to carry the outer pose *conjugated* by the inner one, because the inner pose is
    /// still applied first.
    func testBakingTheOuterOfTwoTransformationLayersConjugatesItByTheInnerOne() throws {
        let manager = document()
        let ink = addInk(manager, "Ink")
        let turn = CGAffineTransform(translationX: 32, y: 32).rotated(by: 0.3).translatedBy(x: -32, y: -32)
        let inner = addMove(manager, turn, name: "Inner")
        let outer = addMove(manager, CGAffineTransform(translationX: 12, y: 0), name: "Outer")
        let before = try scene(manager)

        XCTAssertNotNil(bake(manager, outer))

        XCTAssertEqual(manager.layers.map(\.id), [ink, inner])
        assertSameScene(try scene(manager), before, "the inner turn still poses it, and the outer slide is in the geometry", tolerance: 2)
    }

    /// **A cel with its own animation and a transformation layer above it** are carried in one step, and
    /// the cel's channel is consumed — the live rig would be a lie under baked drawings.
    func testTheCelsOwnChannelIsCarriedAndConsumedWithTheLayersPose() throws {
        let manager = document()
        let ink = addInk(manager, "Ink")
        let own = PoseQuad(box: canvasRect, mappedBy: CGAffineTransform(translationX: 8, y: 0))
        manager.layers[index(ink, manager)].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                .init(frame: 0, pose: PoseQuad(restingIn: canvasRect), interpolation: .linear),
                .init(frame: 11, pose: own, interpolation: .linear)], step: 1)]
        let move = addMove(manager, CGAffineTransform(translationX: 16, y: 0))
        let before = try scene(manager)

        XCTAssertNotNil(bake(manager, move))

        let cels = manager.layers[index(ink, manager)].cels
        XCTAssertTrue(cels.allSatisfy { $0.transformTracks.isEmpty && $0.pendingPoseBaselines.isEmpty },
                      "Every baked cel's channels went with the motion")
        assertSameScene(try scene(manager), before, "the cel's animation and the layer's move are both in the geometry")
    }

    /// **A raster layer beneath is resampled through the pose**, the way the render resamples it.
    func testARasterLayerBeneathIsResampledThroughThePose() throws {
        let manager = document()
        let paint = addRaster(manager, "Paint")
        let move = addMove(manager, CGAffineTransform(translationX: 24, y: 0))
        let before = try scene(manager, frames: 0..<2)
        XCTAssertEqual(bounds(before[0])?.minX, 28, "Premise: the layer moves the pixels")

        XCTAssertNotNil(bake(manager, move))

        XCTAssertEqual(manager.layers.map(\.id), [paint])
        XCTAssertEqual(manager.layers[0].kind, .raster)
        assertSameScene(try scene(manager, frames: 0..<2), before, "the pixels are where they were shown")
    }

    // MARK: - Scope and refusals

    /// **Only what is beneath, within its group**: a drawing above the layer, and one outside its folder,
    /// keep exactly the geometry they had.
    func testOnlyTheLayersBeneathItInItsGroupAreCarried() throws {
        let manager = document()
        let outside = addInk(manager, "Outside", at: 40)
        let inside = addInk(manager, "Inside", at: 4)
        let move = addMove(manager, CGAffineTransform(translationX: 24, y: 0))
        let above = addInk(manager, "Above", at: 24)
        guard let folder = manager.groupLayers(move, with: inside) else { return XCTFail("Setup: group") }
        manager.layers[index(above, manager)].parentFolderID = folder
        let outsideBefore = manager.layers[index(outside, manager)].cels[0].vector!.elements.count

        XCTAssertNotNil(bake(manager, move))

        func firstFillX(_ id: UUID) -> CGFloat? {
            manager.layers[index(id, manager)].cels[0].vector?.elements.compactMap(\.fill).first?
                .cgPath?.boundingBoxOfPath.minX
        }
        XCTAssertEqual(firstFillX(inside), 28, "beneath it in its group: carried")
        XCTAssertEqual(firstFillX(above), 4, "above it: untouched")
        XCTAssertEqual(firstFillX(outside), 4, "outside its group: untouched")
        XCTAssertEqual(manager.layers[index(outside, manager)].cels[0].vector!.elements.count, outsideBefore)
    }

    /// A Repeat layer loops time rather than posing drawings: there is no geometry to carry it into, so
    /// Bake refuses and keeps the layer.
    func testARepeatLayerIsRefusedBecauseItLoopsTimeRatherThanMovingDrawings() {
        let manager = document()
        addInk(manager, "Ink")
        manager.addTransformLayer(name: "Loop")
        let loop = manager.layers.first { $0.name == "Loop" }!.id
        manager.layers[index(loop, manager)].transform = LayerPose(pose: PoseQuad(restingIn: canvasRect),
                                                                  mode: .repeat, repeatPeriod: 4)

        XCTAssertEqual(manager.bakeLayer(id: loop), .refused(.repeatsInTime))
        XCTAssertEqual(manager.layers.count, 2, "The layer is kept")
        guard case .bakeRefused? = manager.notice?.kind else { return XCTFail("A refusal says so") }
    }

    /// A transformation layer resting at the identity changes nothing, so there is nothing to bake in —
    /// and the layer is kept rather than silently deleted.
    func testALayerAtRestHasNothingToBake() {
        let manager = document()
        addInk(manager, "Ink")
        manager.addTransformLayer(name: "Rest")
        let rest = manager.layers.first { $0.name == "Rest" }!.id

        XCTAssertEqual(manager.bakeLayer(id: rest), .refused(.nothingToBake([])))
        XCTAssertEqual(manager.layers.count, 2)
    }

    // MARK: - The walk it reads

    /// **The walk can leave a transformation layer out**, which is how a bake finds its share without
    /// recomputing what the layer does: with it, the drawing's pose is the layer's; without it, nothing
    /// poses the drawing — and with a second layer stacked, what is left is that one's.
    func testTheRenderWalkCanLeaveOneTransformationLayerOut() {
        let manager = document()
        addInk(manager, "Ink")
        let inner = addMove(manager, CGAffineTransform(translationX: 12, y: 0), name: "Inner")
        let outer = addMove(manager, CGAffineTransform(translationX: 5, y: 0), name: "Outer")

        let both = manager.renderTreeAndPoses(atFrame: 0).poses[0]
        let withoutInner = manager.renderTreeAndPoses(atFrame: 0, excluding: inner).poses[0]
        let withoutOuter = manager.renderTreeAndPoses(atFrame: 0, excluding: outer).poses[0]

        XCTAssertEqual(both?.affine?.tx ?? 0, 17, accuracy: 1e-9, "Both poses apply")
        XCTAssertEqual(withoutInner?.affine?.tx ?? 0, 5, accuracy: 1e-9, "Without the inner one only the outer remains")
        XCTAssertEqual(withoutOuter?.affine?.tx ?? 0, 12, accuracy: 1e-9, "…and the reverse")
        manager.layers[0].isVisible = true
        XCTAssertEqual(manager.renderTreeAndPoses(atFrame: 0).poses[0]?.affine?.tx ?? 0, 17, accuracy: 1e-9,
                       "Asking without a layer changed nothing in the document")
    }
}
