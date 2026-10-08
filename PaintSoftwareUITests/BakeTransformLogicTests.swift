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
///
/// **A Repeat is the same pin with a different carrier**: it poses nothing, it shows each layer beneath at
/// an earlier frame, so baking it writes the replayed frames out as drawings — and the baked document
/// must still render every frame of the bar byte for byte.
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
        manager.layers[at].transform = LayerPose(pose: rest, track: CanvasFixture.poseTrack([(0, rest), (last, moved)], interpolation: .linear))
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
            TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, PoseQuad(restingIn: canvasRect)), (11, own)], interpolation: .linear, step: 1)]
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

    // MARK: - A Repeat layer

    /// A vector layer holding one drawing per `(start, length)` block, the drawing in block `i` a red
    /// square at x = 4 + 12·i, so every drawing is told apart on the canvas.
    @discardableResult
    private func addDrawings(_ manager: CanvasManager, _ name: String, blocks: [(start: Int, length: Int)]) -> UUID {
        manager.addVectorLayer(name: name)
        let at = manager.layers.firstIndex { $0.name == name }!
        manager.layers[at].cels = blocks.enumerated().map { i, block in
            let vector = VectorCanvas.empty(size: size)
            vector.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 4 + 12 * CGFloat(i), y: 14, width: 8, height: 10), transform: nil),
                           color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
            return Cel(id: UUID(), startFrame: block.start, frameCount: block.length, raster: .empty(size: size), vector: vector)
        }
        return manager.layers[at].id
    }

    /// A Repeat layer of `period` frames whose bar covers `bar`.
    @discardableResult
    private func addLoop(_ manager: CanvasManager, period: Int, bar: Range<Int> = 0..<12, name: String = "Loop") -> UUID {
        manager.addTransformLayer(name: name)
        let at = manager.layers.firstIndex { $0.name == name }!
        manager.layers[at].transform = LayerPose(pose: PoseQuad(restingIn: canvasRect), mode: .repeat, repeatPeriod: period)
        CanvasFixture.setCelLayout(manager, layerIndex: at, [(start: bar.lowerBound, length: bar.count)])
        return manager.layers[at].id
    }

    /// Three drawings on frames 0, 1 and 2 — the third held to the end of the scene — under a Repeat of
    /// `period`, the picture §5.5's tests use.
    private func walkerUnderALoop(period: Int = 3, bar: Range<Int> = 0..<12)
        -> (manager: CanvasManager, walker: UUID, loop: UUID) {
        let manager = document()
        let walker = addDrawings(manager, "Walker", blocks: [(0, 1), (1, 1), (2, 10)])
        return (manager, walker, addLoop(manager, period: period, bar: bar))
    }

    private func layout(_ manager: CanvasManager, _ id: UUID) -> [[Int]] {
        CanvasFixture.celLayout(manager, layerIndex: index(id, manager)).map { [$0.start, $0.length] }
    }

    /// Bakes `loop` and says how many cels `layer` gained, which the plan has to have said first.
    private func bakeCountingCels(_ manager: CanvasManager, loop: UUID, layer: UUID,
                                  file: StaticString = #filePath, line: UInt = #line) -> (planned: Int, actual: Int)? {
        guard case .plan(let plan) = manager.bakePlan(forLayerID: loop) else {
            XCTFail("The loop must plan", file: file, line: line)
            return nil
        }
        let before = manager.layers[index(layer, manager)].cels.count
        guard bake(manager, loop, file: file, line: line) != nil else { return nil }
        return (plan.addedCels.vector + plan.addedCels.raster, manager.layers[index(layer, manager)].cels.count - before)
    }

    /// **Baking a Repeat writes every looped frame out as a drawing, and the scene is the same bytes.**
    /// The walker's third drawing is held across the loop's first cycle, so the loop hides most of it;
    /// a background held under the whole bar already shows the same cel on every frame and is left alone.
    func testBakingARepeatWritesTheLoopedFramesAsDrawingsAndEveryFrameIsByteIdentical() throws {
        let manager = document()
        let background = addDrawings(manager, "Background", blocks: [(0, 12)])
        manager.layers[index(background, manager)].opacity = 0.5
        let walker = addDrawings(manager, "Walker", blocks: [(0, 1), (1, 1), (2, 10)])
        let loop = addLoop(manager, period: 3)
        let before = try scene(manager)
        XCTAssertNotEqual(before[0], before[1], "Premise: the drawings differ")
        XCTAssertEqual(before[3], before[0], "Premise: the loop shows frame 0 again on frame 3")
        XCTAssertEqual(before[4], before[1], "…and frame 1 on frame 4")
        let backgroundCels = manager.layers[index(background, manager)].cels.map(\.id)

        guard case .plan(let plan) = manager.bakePlan(forLayerID: loop) else { return XCTFail("Must plan") }
        XCTAssertEqual(plan.addedCels.vector, 9, "Three drawings become twelve: one a frame")
        XCTAssertTrue(plan.needsConfirmation)
        XCTAssertTrue(plan.confirmationMessage.contains("9 drawings"), plan.confirmationMessage)
        XCTAssertEqual(plan.layers.map(\.name), ["Walker"], "The background already shows what the loop shows")

        manager.requestBake(layerID: loop)
        XCTAssertNotNil(manager.pendingBake, "Writing drawings costs every future save, so the artist is asked")
        XCTAssertEqual(manager.layers.count, 3, "Nothing is written until the artist says so")
        manager.confirmPendingBake()

        XCTAssertEqual(manager.layers.map(\.id), [background, walker], "The Repeat layer is gone")
        XCTAssertEqual(layout(manager, walker), (0..<12).map { [$0, 1] }, "One cel on every looped frame")
        XCTAssertEqual(manager.layers[index(background, manager)].cels.map(\.id), backgroundCels, "The background was not touched")
        assertSameScene(try scene(manager), before, "every baked frame is the looped frame")
    }

    func testOneUndoBringsTheLoopAndTheDrawingsItHidBack() throws {
        let fx = walkerUnderALoop()
        let layoutBefore = layout(fx.manager, fx.walker)
        let before = try scene(fx.manager)
        let steps = fx.manager.history.undoStack.count

        XCTAssertNotNil(bake(fx.manager, fx.loop))
        XCTAssertEqual(fx.manager.history.undoStack.count, steps + 1, "One step, however many drawings it wrote")

        fx.manager.undo()
        XCTAssertEqual(fx.manager.layers.map(\.id), [fx.walker, fx.loop], "The Repeat layer is back")
        XCTAssertEqual(layout(fx.manager, fx.walker), layoutBefore, "…and so are the drawings, as they were")
        assertSameScene(try scene(fx.manager), before, "…looping again")
    }

    /// **A drawing that holds across the loop is one cel, not one per frame** — the cut rule is Bake's
    /// own (`bakeSegments`): consecutive looped frames showing one drawing are one run, across a cycle's
    /// end too.
    func testADrawingHeldAcrossTheLoopStaysOneCelPerRun() throws {
        let manager = document()
        let held = addDrawings(manager, "Held", blocks: [(0, 4), (4, 2)])
        let loop = addLoop(manager, period: 6, bar: 0..<18)
        let before = try scene(manager, frames: 0..<18)
        XCTAssertEqual(before[6], before[0], "Premise: the loop is running")

        let counted = bakeCountingCels(manager, loop: loop, layer: held)
        XCTAssertEqual(layout(manager, held), [[0, 4], [4, 2], [6, 4], [10, 2], [12, 4], [16, 2]],
                       "Each hold is one cel, four drawings from two")
        XCTAssertEqual(counted?.planned, counted?.actual, "The plan counted the cels the bake made")
        assertSameScene(try scene(manager, frames: 0..<18), before, "the held frames render as the loop did")
    }

    /// **What the loop hid under its bar is replaced, and what lies past the bar is kept.** The drawing on
    /// frames 6–8 is never shown while the loop runs; after the bake those frames show the loop's.
    func testWhatTheLoopHidIsReplacedAndWhatLiesPastItsBarIsKept() throws {
        let manager = document()
        let walker = addDrawings(manager, "Walker", blocks: [(0, 1), (1, 1), (2, 1), (6, 3), (9, 2)])
        let loop = addLoop(manager, period: 3, bar: 0..<9)
        let before = try scene(manager)
        XCTAssertEqual(before[7], before[1], "Premise: frame 7 shows frame 1, not the hidden drawing on 6–8")
        XCTAssertNotEqual(before[9], before[0], "Premise: past the bar the drawing at 9 is shown")
        let past = manager.layers[index(walker, manager)].cels.last!.id

        let counted = bakeCountingCels(manager, loop: loop, layer: walker)
        XCTAssertEqual(layout(manager, walker), (0..<9).map { [$0, 1] } + [[9, 2]], "The hidden drawing is gone")
        XCTAssertEqual(manager.layers[index(walker, manager)].cels.last?.id, past, "The drawing past the bar is the same cel")
        XCTAssertEqual(counted?.planned, counted?.actual)
        assertSameScene(try scene(manager), before, "the hidden drawing does not reappear")
    }

    /// **A drawing across the bar's edges is cut at them**, and the plan counted the pieces: the third
    /// drawing runs from frame 2 to 12, the bar ends at 8.
    func testADrawingAcrossTheBarsEdgesIsCutThere() throws {
        let fx = walkerUnderALoop(bar: 0..<8)
        let before = try scene(fx.manager)
        XCTAssertEqual(before[8], before[2], "Premise: past the bar the third drawing holds")

        let counted = bakeCountingCels(fx.manager, loop: fx.loop, layer: fx.walker)
        XCTAssertEqual(layout(fx.manager, fx.walker), (0..<8).map { [$0, 1] } + [[8, 4]],
                       "Frames 3–7 are drawings of their own; the hold resumes past the bar")
        XCTAssertEqual(counted?.planned, 6)
        XCTAssertEqual(counted?.planned, counted?.actual)
        assertSameScene(try scene(fx.manager), before, "the bar's edges are where the loop's did")
    }

    /// **Pixels are copied, not shared**: a raster layer beneath gets a texture of its own on every
    /// looped cel, so a stroke on one frame does not appear on another.
    func testARasterLayerBeneathIsCopiedFrameByFrame() throws {
        let manager = document()
        manager.addLayer(name: "Paint")
        let paint = manager.layers.firstIndex { $0.name == "Paint" }!
        CanvasFixture.setCelLayout(manager, layerIndex: paint, [(start: 0, length: 1), (start: 1, length: 1), (start: 2, length: 10)])
        for (frame, x) in [(0, 4), (1, 20), (2, 36)] {
            CanvasFixture.setBakedContent(manager, layerIndex: paint, frame: frame,
                                          CanvasFixture.solidImage(.blue, rect: CGRect(x: x, y: 40, width: 10, height: 10)))
        }
        let loop = addLoop(manager, period: 3)
        let before = try scene(manager)
        XCTAssertEqual(before[4], before[1], "Premise: the loop is running")

        let id = manager.layers[paint].id
        let counted = bakeCountingCels(manager, loop: loop, layer: id)
        let cels = manager.layers[index(id, manager)].cels
        XCTAssertEqual(manager.layers[index(id, manager)].kind, .raster)
        XCTAssertEqual(cels.map(\.startFrame), Array(0..<12))
        XCTAssertFalse(cels[3].raster === cels[0].raster, "A copy has a texture of its own")
        XCTAssertEqual(counted?.planned, counted?.actual)
        assertSameScene(try scene(manager), before, "the pixels are where the loop showed them")
    }

    /// **A drawing a pose channel animates is copied with its keys**, whole, and renders as it did — the
    /// cel's channels are numbered from its own first frame, so a copy placed at the start of a cycle
    /// plays the same motion.
    func testAnAnimatedDrawingIsCopiedWithItsMotion() throws {
        let manager = document()
        let sprite = addDrawings(manager, "Sprite", blocks: [(0, 4)])
        let moved = PoseQuad(box: canvasRect, mappedBy: CGAffineTransform(translationX: 24, y: 0))
        manager.layers[index(sprite, manager)].cels[0].transformTracks = [
            TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, PoseQuad(restingIn: canvasRect)), (3, moved)], interpolation: .linear, step: 1)]
        let loop = addLoop(manager, period: 4)
        let before = try scene(manager)
        XCTAssertNotEqual(before[0], before[3], "Premise: the sprite moves within its cycle")
        XCTAssertEqual(before[5], before[1], "…and the loop plays that motion again")

        let counted = bakeCountingCels(manager, loop: loop, layer: sprite)
        let cels = manager.layers[index(sprite, manager)].cels
        XCTAssertEqual(layout(manager, sprite), [[0, 4], [4, 4], [8, 4]])
        XCTAssertTrue(cels.allSatisfy { !$0.transformTracks.isEmpty }, "Each cycle's drawing carries the motion")
        XCTAssertEqual(counted?.planned, counted?.actual)
        assertSameScene(try scene(manager), before, "the motion is the same on every cycle")
    }

    /// **A loop that begins partway into an animated drawing cannot be written out exactly** — the copy
    /// would need the keys cut at that frame — so that drawing is left as it was, said so, and the rest bakes.
    func testALoopThatBeginsPartwayIntoAnAnimatedDrawingLeavesItAsItWas() throws {
        let manager = document()
        let sprite = addDrawings(manager, "Sprite", blocks: [(0, 8)])
        let moved = PoseQuad(box: canvasRect, mappedBy: CGAffineTransform(translationX: 24, y: 0))
        manager.layers[index(sprite, manager)].cels[0].transformTracks = [
            TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, PoseQuad(restingIn: canvasRect)), (7, moved)], interpolation: .linear, step: 1)]
        let loop = addLoop(manager, period: 3, bar: 2..<12)

        XCTAssertEqual(manager.bakeLayer(id: loop),
                       .refused(.nothingToBake([CanvasManager.BakeLeftover(name: "Sprite", reason: .animatedDrawing)])))
        XCTAssertEqual(manager.layers.count, 2, "The Repeat layer is kept")

        let walker = addDrawings(manager, "Walker", blocks: [(2, 1), (3, 1), (4, 10)])
        manager.restackLayer(loop, above: .layer(walker), parentFolderID: nil)
        guard case .baked(let plan) = manager.bakeLayer(id: loop) else { return XCTFail("The walker bakes") }
        XCTAssertEqual(plan.leftovers, [CanvasManager.BakeLeftover(name: "Sprite", reason: .animatedDrawing)])
        XCTAssertEqual(manager.layers[index(sprite, manager)].cels.count, 1, "The animated drawing is untouched")
        guard case .bakedWithLeftovers? = manager.notice?.kind else { return XCTFail("The leftover is said") }
    }

    /// **An animated drawing held across a cycle's end would have to be cut there**, and a cut re-eases
    /// the segment it passes through — so it is left as it was, and said so, rather than written out
    /// moving a little differently.
    func testAnAnimatedDrawingHeldAcrossTheLoopIsLeftAsItWas() throws {
        let manager = document()
        let sprite = addDrawings(manager, "Sprite", blocks: [(0, 12)])
        let moved = PoseQuad(box: canvasRect, mappedBy: CGAffineTransform(translationX: 24, y: 0))
        manager.layers[index(sprite, manager)].cels[0].transformTracks = [
            TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, PoseQuad(restingIn: canvasRect)), (11, moved)], interpolation: .bezier, step: 1)]
        let loop = addLoop(manager, period: 4)

        XCTAssertEqual(manager.bakeLayer(id: loop),
                       .refused(.nothingToBake([CanvasManager.BakeLeftover(name: "Sprite", reason: .animatedDrawing)])))
        XCTAssertEqual(manager.layers[index(sprite, manager)].cels.count, 1, "Not cut")
    }

    // MARK: - What a loop repeats besides drawings

    /// A fade-in over the layer's first three frames — what a loop repeats and a drawing cannot carry.
    private func fadeIn(_ manager: CanvasManager, _ id: UUID) {
        manager.layers[index(id, manager)].channelTracks[TargetChannel.opacity.id] =
            AnimationCurve(keys: [.init(frame: 0, value: 0.2), .init(frame: 2, value: 1)])
    }

    private func hide(_ manager: CanvasManager, _ ids: UUID...) {
        for id in ids { manager.layers[index(id, manager)].isVisible = false }
    }

    /// A frame composited with the hidden layer `id` shown for the one render.
    private func composite(_ manager: CanvasManager, frame: Int, showing id: UUID) throws -> [UInt8] {
        manager.layers[index(id, manager)].isVisible = true
        defer { manager.layers[index(id, manager)].isVisible = false }
        return try composite(manager, frame: frame)
    }

    /// The opacity the top-level node of layer `id` has at `frame` — what the walk, with the loop, draws.
    private func walkedOpacity(_ manager: CanvasManager, _ id: UUID, atFrame frame: Int) -> Double? {
        manager.renderTree(atFrame: frame).first { $0.id == id }?.opacity
    }

    private func leftover(_ name: String) -> CanvasManager.BakeLeftover {
        CanvasManager.BakeLeftover(name: name, reason: .loopsMoreThanDrawings)
    }

    /// **"Bake the rest."** A layer whose fade the loop repeats is left exactly as it was, said so, and
    /// the layer beside it that the loop only re-shows bakes — byte for byte, over the whole bar. The
    /// Repeat layer goes all the same (as an effect layer does with a layer it left), so the left layer
    /// stops looping.
    func testALayerTheLoopRepeatsMoreOfIsLeftAsItWasAndTheRestBakes() throws {
        let manager = document()
        let fader = addDrawings(manager, "Fader", blocks: [(0, 1), (1, 1), (2, 10)])
        fadeIn(manager, fader)
        let walker = addDrawings(manager, "Walker", blocks: [(0, 1), (1, 1), (2, 10)])
        let loop = addLoop(manager, period: 3)
        XCTAssertEqual(walkedOpacity(manager, fader, atFrame: 3) ?? -1, 0.2, accuracy: 1e-9,
                       "Premise: the loop repeats the fade")
        let faderCels = manager.layers[index(fader, manager)].cels.map(\.id)
        let faderFade = manager.layers[index(fader, manager)].channelTracks
        hide(manager, fader)
        let before = try scene(manager)
        XCTAssertEqual(before[4], before[1], "Premise: the loop runs under the hidden layer")
        let loopedFrameThree = try composite(manager, frame: 3, showing: fader)

        guard case .plan(let plan) = manager.bakePlan(forLayerID: loop) else { return XCTFail("The walker bakes") }
        XCTAssertEqual(plan.layers.map(\.name), ["Walker"])
        XCTAssertEqual(plan.leftovers, [leftover("Fader")])
        XCTAssertNotNil(bake(manager, loop))

        XCTAssertEqual(manager.layers.map(\.id), [fader, walker], "Only the Repeat layer is gone")
        XCTAssertEqual(layout(manager, walker), (0..<12).map { [$0, 1] })
        XCTAssertEqual(manager.layers[index(fader, manager)].cels.map(\.id), faderCels, "The left layer's drawings are untouched")
        XCTAssertEqual(manager.layers[index(fader, manager)].channelTracks, faderFade, "…and so is its fade")
        guard case .bakedWithLeftovers(let said)? = manager.notice?.kind else { return XCTFail("The leftover is said") }
        XCTAssertEqual(said, [leftover("Fader")])
        XCTAssertTrue(manager.notice?.message.contains("Fader") == true, manager.notice?.message ?? "no notice")
        assertSameScene(try scene(manager), before, "the layer that baked renders what the loop showed")
        XCTAssertNotEqual(try composite(manager, frame: 3, showing: fader), loopedFrameThree,
                          "The Repeat is gone, so the layer it left no longer loops")
    }

    /// **Nothing bakeable is still a refusal**, and it names the layer — the Repeat layer is kept.
    func testWhenNoLayerCanTakeTheLoopTheBakeIsRefusedAndNamesThem() throws {
        let fx = walkerUnderALoop()
        fadeIn(fx.manager, fx.walker)
        XCTAssertEqual(walkedOpacity(fx.manager, fx.walker, atFrame: 3) ?? -1, 0.2, accuracy: 1e-9,
                       "Premise: the loop repeats the fade")
        let before = try scene(fx.manager)

        let refused = fx.manager.bakeLayer(id: fx.loop)
        XCTAssertEqual(refused, .refused(.nothingToBake([leftover("Walker")])))
        XCTAssertEqual(fx.manager.layers.count, 2, "The Repeat layer is kept")
        guard case .bakeRefused(let refusal)? = fx.manager.notice?.kind else { return XCTFail("A refusal says so") }
        XCTAssertTrue(refusal.phrase.contains("Walker"), "The refusal names the layer: \(refusal.phrase)")
        assertSameScene(try scene(fx.manager), before, "nothing changed")
    }

    /// **A group's own fade reaches every layer in it, and a layer's fade reaches only that layer.** The
    /// "Fading" group is keyed, so both its layers are left; in the "Plain" group only the layer whose own
    /// opacity is keyed is, and its neighbour bakes with the layer outside any group.
    func testAGroupsOwnFadeReachesEveryLayerInItButNotItsNeighbours() throws {
        let manager = document()
        let blocks = [(start: 0, length: 1), (start: 1, length: 1), (start: 2, length: 10)]
        let inFading = [addDrawings(manager, "FadeOne", blocks: blocks), addDrawings(manager, "FadeTwo", blocks: blocks)]
        let steady = addDrawings(manager, "Steady", blocks: blocks)
        let ownFade = addDrawings(manager, "OwnFade", blocks: blocks)
        let outside = addDrawings(manager, "Outside", blocks: blocks)
        fadeIn(manager, ownFade)
        let loop = addLoop(manager, period: 3)

        let fading = manager.addFolder(name: "Fading")
        let plain = manager.addFolder(name: "Plain")
        for id in inFading { manager.layers[index(id, manager)].parentFolderID = fading }
        for id in [steady, ownFade] { manager.layers[index(id, manager)].parentFolderID = plain }
        for group in [fading, plain] { manager.restackFolder(group, above: .bottom, parentFolderID: nil) }
        let fadingAt = manager.folders.firstIndex { $0.id == fading }!
        manager.folders[fadingAt].channelTracks[TargetChannel.opacity.id] =
            AnimationCurve(keys: [.init(frame: 0, value: 0.2), .init(frame: 2, value: 1)])
        hide(manager, inFading[0], inFading[1], ownFade)
        let before = try scene(manager)
        XCTAssertEqual(before[4], before[1], "Premise: the loop reaches into the groups")

        guard case .plan(let plan) = manager.bakePlan(forLayerID: loop) else { return XCTFail("The others bake") }
        XCTAssertEqual(Set(plan.layers.map(\.name)), ["Steady", "Outside"])
        XCTAssertEqual(plan.leftovers.map(\.name).sorted(), ["FadeOne", "FadeTwo", "OwnFade"])
        XCTAssertTrue(plan.leftovers.allSatisfy { $0.reason == .loopsMoreThanDrawings })
        XCTAssertNotNil(bake(manager, loop))
        XCTAssertEqual(layout(manager, steady), (0..<12).map { [$0, 1] })
        XCTAssertEqual(layout(manager, outside), (0..<12).map { [$0, 1] })
        XCTAssertEqual(layout(manager, ownFade), [[0, 1], [1, 1], [2, 10]], "Left as it was")
        XCTAssertEqual(layout(manager, inFading[0]), [[0, 1], [1, 1], [2, 10]], "Left as it was")
        assertSameScene(try scene(manager), before, "the layers that baked render what the loop showed")
    }

    /// **A Move the loop repeats is more than drawings too** — the Slide under the Repeat is read at the
    /// first cycle's frames, so the layer it slides is posed differently with the loop than without it.
    /// That layer is left; the one above the Slide, which it never moved, bakes — and a grade the Slide
    /// moves is not named, because a grade is moved by nothing.
    func testALayerAMoveTheLoopRepeatsSlidesIsLeftAsItWas() throws {
        let manager = document()
        let slid = addDrawings(manager, "Slid", blocks: [(0, 1), (1, 1), (2, 10)])
        manager.addValueLayer(effect: .hsvShift(Effect.HSVShift(hueDegrees: 120)), name: "Grade")
        addSlide(manager, by: 24)
        let steady = addDrawings(manager, "Steady", blocks: [(0, 1), (1, 1), (2, 10)])
        let loop = addLoop(manager, period: 3)
        XCTAssertEqual(manager.layers.map(\.name), ["Slid", "Grade", "Slide", "Steady", "Loop"],
                       "Premise: the Slide is between")
        hide(manager, slid)
        let before = try scene(manager)
        XCTAssertEqual(before[4], before[1], "Premise: the loop is running")

        guard case .plan(let plan) = manager.bakePlan(forLayerID: loop) else { return XCTFail("Steady bakes") }
        XCTAssertEqual(plan.layers.map(\.name), ["Steady"])
        XCTAssertEqual(plan.leftovers, [leftover("Slid")], "The Slide itself holds no drawing, so only the layer it moves is named")
        XCTAssertNotNil(bake(manager, loop))
        XCTAssertEqual(layout(manager, steady), (0..<12).map { [$0, 1] })
        XCTAssertEqual(layout(manager, slid), [[0, 1], [1, 1], [2, 10]], "Left as it was")
        assertSameScene(try scene(manager), before, "the layer the Slide does not move renders what the loop showed")
    }

    /// **A Move that holds still is nothing the loop repeats**, so the layer under it bakes whole and the
    /// Move layer stays.
    func testAMoveThatHoldsStillUnderTheLoopDoesNotStopTheBake() throws {
        let manager = document()
        let walker = addDrawings(manager, "Walker", blocks: [(0, 1), (1, 1), (2, 10)])
        let move = addMove(manager, CGAffineTransform(translationX: 12, y: 0))
        let loop = addLoop(manager, period: 3)
        let before = try scene(manager)
        XCTAssertEqual(before[4], before[1], "Premise: the loop is running, under a Move")

        XCTAssertNotNil(bake(manager, loop))
        XCTAssertEqual(manager.layers.map(\.id), [walker, move])
        XCTAssertEqual(layout(manager, walker), (0..<12).map { [$0, 1] })
        XCTAssertNil(manager.notice, "Nothing was left, so nothing is said")
        assertSameScene(try scene(manager), before, "still moved, and still looped")
    }

    /// **A grade the loop carries past its bar is more than drawings, and is named**: the drawings under
    /// it still bake, and it is the grade that stops. (A grade has no drawing of its own to write out.)
    func testAGradeTheLoopKeepsOnPastItsBarIsNamedWhileTheDrawingsUnderItBake() throws {
        let manager = document()
        let walker = addDrawings(manager, "Walker", blocks: [(0, 1), (1, 1), (2, 10)])
        manager.addValueLayer(effect: .hsvShift(Effect.HSVShift(hueDegrees: 120)), name: "Grade")
        let grade = manager.layers.firstIndex { $0.name == "Grade" }!
        CanvasFixture.setCelLayout(manager, layerIndex: grade, [(start: 0, length: 3)])
        let loop = addLoop(manager, period: 3)
        hide(manager, manager.layers[grade].id)
        let before = try scene(manager)
        XCTAssertEqual(before[4], before[1], "Premise: the loop is running")

        guard case .plan(let plan) = manager.bakePlan(forLayerID: loop) else { return XCTFail("The walker bakes") }
        XCTAssertEqual(plan.layers.map(\.name), ["Walker"])
        XCTAssertEqual(plan.leftovers, [leftover("Grade")])
        XCTAssertNotNil(bake(manager, loop))
        XCTAssertEqual(layout(manager, walker), (0..<12).map { [$0, 1] })
        assertSameScene(try scene(manager), before, "the drawings render what the loop showed")
    }

    /// A layer whose only drawing the loop hid, and showed nothing in, keeps one blank cel — a layer
    /// is never left with none.
    func testALayerWhoseOnlyDrawingTheLoopHidKeepsOneBlankCel() throws {
        let manager = document()
        let stray = addDrawings(manager, "Stray", blocks: [(6, 3)])
        let loop = addLoop(manager, period: 3)
        let before = try scene(manager)
        XCTAssertNil(bounds(before[7]), "Premise: the loop shows nothing at frame 7")

        let counted = bakeCountingCels(manager, loop: loop, layer: stray)
        XCTAssertEqual(layout(manager, stray), [[3, 1]])
        XCTAssertTrue(manager.layers[index(stray, manager)].cels[0].isCertainlyBlank, "…and it is blank")
        XCTAssertEqual(counted?.planned, counted?.actual)
        assertSameScene(try scene(manager), before, "still nothing")
    }

    /// A flat colour's block is what gates it, so a block shorter than the loop is written out too — and
    /// its three looped cycles are one run, one cel.
    func testAFlatColourWhoseBlockIsShorterThanTheLoopIsExtended() throws {
        let manager = document()
        manager.addValueLayer(name: "Tint")
        let tint = manager.layers.firstIndex { $0.name == "Tint" }!
        CanvasFixture.setCelLayout(manager, layerIndex: tint, [(start: 0, length: 3)])
        let loop = addLoop(manager, period: 3)
        let before = try scene(manager)
        XCTAssertEqual(before[8], before[1], "Premise: the loop keeps the colour on past its block")

        let id = manager.layers[tint].id
        XCTAssertNotNil(bake(manager, loop))
        XCTAssertEqual(layout(manager, id), [[0, 3], [3, 9]])
        XCTAssertEqual(manager.layers[index(id, manager)].kind, .value)
        assertSameScene(try scene(manager), before, "the colour is on as long as the loop kept it")
    }

    /// **Layers in a folder beneath the loop are looped by the same walk.**
    func testALayerInAFolderBeneathTheLoopIsWrittenOut() throws {
        let fx = walkerUnderALoop()
        let folder = fx.manager.addFolder(name: "G")
        fx.manager.layers[index(fx.walker, fx.manager)].parentFolderID = folder
        fx.manager.restackFolder(folder, above: .bottom, parentFolderID: nil)
        let before = try scene(fx.manager)
        XCTAssertEqual(before[4], before[1], "Premise: the loop reaches into the folder")

        XCTAssertNotNil(bake(fx.manager, fx.loop))
        XCTAssertEqual(layout(fx.manager, fx.walker), (0..<12).map { [$0, 1] })
        XCTAssertEqual(fx.manager.layers[index(fx.walker, fx.manager)].parentFolderID, folder, "It stays in its folder")
        assertSameScene(try scene(fx.manager), before, "the folder's picture is the loop's")
    }

    /// A layer under another Repeat is read at a frame the walk composes twice: it is left as it was, and
    /// said so, rather than written out wrong.
    func testALayerUnderAnotherRepeatIsLeftAsItWas() throws {
        let manager = document()
        addDrawings(manager, "Walker", blocks: [(0, 1), (1, 1), (2, 10)])
        addLoop(manager, period: 2, name: "Inner")
        let outer = addLoop(manager, period: 5, name: "Outer")

        XCTAssertEqual(manager.bakeLayer(id: outer),
                       .refused(.nothingToBake([CanvasManager.BakeLeftover(name: "Walker", reason: .underARepeat("Inner"))])))
        XCTAssertEqual(manager.layers.count, 3)
    }

    /// A loop that never goes round again (its period is its bar) has nothing to write, and is kept.
    func testALoopThatNeverRepeatsHasNothingToBake() {
        let fx = walkerUnderALoop(period: 12)
        XCTAssertEqual(fx.manager.bakeLayer(id: fx.loop), .refused(.nothingToBake([])))
        XCTAssertEqual(fx.manager.layers.count, 2)
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
