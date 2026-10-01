import XCTest
import SwiftUI
import UIKit
import CoreGraphics

/// **What is drawn on a layer lands where it was drawn, whatever poses the layer** — TODO (124):
///
/// > *"put a move layer on top of a normal vector layer. When the user lays down a stroke, that stroke
/// > does not get put down where the user wants it, because the move layer on top moves it in
/// > compositing. Make it so the stroke the user lays down is properly transformed so whatever they
/// > draw accurately reflects the position the stroke gets set in."*
///
/// `CanvasManager.inkPose(forLayerID:)` is the one answer every input surface reads, so the first
/// half of this file pins that it *is* the map the canvas shows the layer through — the render walk's
/// container pose for one, two stacked and a Parallax layer, with the cel's own channel composed
/// under it — and the second half drives each tool's own commit through it and asks where the result
/// is **shown**, i.e. the stored geometry posed back through the render's own composition
/// (`posed(_:through:inheriting:)`). Each of those goes red if its pull-back is deleted, because the
/// stored geometry is then shown a pose away from where it was made. `StrokeCanvasView`, which is not
/// in this target, is driven by `InkUnderTransformUITests`.
@MainActor
final class InkPoseLogicTests: XCTestCase {

    private static let size = CGSize(width: 256, height: 256)
    private static var box: CGRect { CGRect(origin: .zero, size: size) }

    /// A vector layer (index 0, active) under one transformation layer posed by `transform`.
    private func layerUnderMove(_ transform: CGAffineTransform,
                                mode: TransformLayerMode = .move) -> (manager: CanvasManager, ink: Int) {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addVectorLayer(name: "ink")
        manager.addTransformLayer(name: "move")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box, mappedBy: transform), mode: mode)
        manager.currentLayerIndex = 0
        return (manager, 0)
    }

    private func assertSame(_ a: CGPoint?, _ b: CGPoint, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("no point: \(message)", file: file, line: line) }
        XCTAssertEqual(a.x, b.x, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-6, message, file: file, line: line)
    }

    /// Where the canvas shows `element` of the active layer's cel: the render's own composition.
    private func shown(_ element: VectorElement, in manager: CanvasManager, layer: Int) -> VectorElement {
        let cel = manager.layers[layer].cels[0]
        let walk = manager.renderTreeAndPoses(atFrame: manager.currentFrame)
        let mappings = CanvasManager.poseMappings(cel.transformTracks,
                                                  atCelLocalFrame: manager.currentFrame - cel.startFrame)
        return CanvasManager.posed([element], through: mappings, inheriting: walk.poses[layer])[0]
    }

    // MARK: - The map

    func testALayerNothingPosesTakesInkAtRest() {
        let manager = CanvasManager()
        manager.canvasSize = Self.size
        manager.addVectorLayer()
        XCTAssertNil(manager.inkPose(forLayerID: manager.layers[0].id))
    }

    /// The render walk's own container pose, read rather than recomputed, and its inverse is the
    /// map from where the pen is to where the ink is stored.
    func testAMoveLayerAboveIsTheMapTheInkIsShownThrough() {
        let fx = layerUnderMove(CGAffineTransform(translationX: 40, y: -12))
        let pose = fx.manager.inkPose(forLayerID: fx.manager.layers[fx.ink].id)
        XCTAssertEqual(pose, fx.manager.layerPoses(atFrame: 0)[fx.ink], "not the render's own map")
        assertSame(pose?.inverse?.applied(to: CGPoint(x: 100, y: 100)), CGPoint(x: 60, y: 112),
                   "the pen's point is not pulled back to where the ink has to be stored")
    }

    /// **Two transformation layers stacked**: the lower one moves the ink and the upper one carries
    /// the result — inner first. A turn and a slide do not commute, so the reversed order maps the
    /// test point somewhere else entirely.
    func testTwoStackedTransformLayersComposeInnerFirst() {
        let manager = CanvasManager()
        manager.canvasSize = Self.size
        manager.addVectorLayer(name: "ink")
        manager.addTransformLayer(name: "lower")
        manager.addTransformLayer(name: "upper")
        XCTAssertEqual(manager.layers.map(\.name), ["ink", "lower", "upper"], "the fixture's premise")
        let slide = CGAffineTransform(translationX: 30, y: 0)
        let turn = CGAffineTransform(translationX: 128, y: 128).rotated(by: .pi / 2)
            .translatedBy(x: -128, y: -128)
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box, mappedBy: slide), mode: .move)
        manager.layers[2].transform = LayerPose(pose: PoseQuad(box: Self.box, mappedBy: turn), mode: .move)
        let pose = manager.inkPose(forLayerID: manager.layers[0].id)
        let p = CGPoint(x: 10, y: 20)
        assertSame(pose?.applied(to: p), p.applying(slide).applying(turn),
                   "the lower layer's slide is not applied before the upper layer's turn")
        assertSame(pose?.inverse?.applied(to: pose?.applied(to: p) ?? .zero), p, "no round trip")
    }

    /// **Parallax gives each item its own share**, so the ink map is per layer: the item nearest the
    /// parallax layer takes all of a 100-point move and the one beneath it half (two items).
    func testParallaxHandsEachLayerItsOwnShareOfTheMove() {
        let manager = CanvasManager()
        manager.canvasSize = Self.size
        manager.addVectorLayer(name: "ink")
        manager.addVectorLayer(name: "front")
        manager.addTransformLayer(name: "move")
        XCTAssertEqual(manager.layers.map(\.name), ["ink", "front", "move"], "the fixture's premise")
        manager.layers[2].transform = LayerPose(pose: PoseQuad(box: Self.box,
                                                               mappedBy: CGAffineTransform(translationX: 100, y: 0)),
                                                mode: .parallax)
        let back = manager.inkPose(forLayerID: manager.layers[0].id)?.affine
        let front = manager.inkPose(forLayerID: manager.layers[1].id)?.affine
        XCTAssertEqual(front?.tx ?? 0, 100, accuracy: 1e-9, "the nearest item takes the whole move")
        XCTAssertEqual(back?.tx ?? 0, 50, accuracy: 1e-9, "the item behind takes its own share")
    }

    /// **The cel's own channel composes under the container pose** — the order `posed` uses for an
    /// element no group claims, which is every mark not drawn yet.
    func testTheCelChannelIsAppliedBeforeTheContainerPose() {
        let fx = layerUnderMove(CGAffineTransform(translationX: 0, y: 25))
        let celTurn = CGAffineTransform(translationX: 128, y: 128).rotated(by: .pi / 2)
            .translatedBy(x: -128, y: -128)
        fx.manager.layers[fx.ink].cels[0].transformTracks[TransformChannelID.cel.id] =
            TransformTrack(keys: [.init(frame: 0, pose: PoseQuad(box: Self.box, mappedBy: celTurn))])
        let pose = fx.manager.inkPose(forLayerID: fx.manager.layers[fx.ink].id)
        let p = CGPoint(x: 10, y: 20)
        assertSame(pose?.applied(to: p), p.applying(celTurn).applying(CGAffineTransform(translationX: 0, y: 25)),
                   "the cel's turn is not applied under the Move layer's slide")
    }

    // MARK: - Every tool's commit, asked where the canvas shows it

    /// A stroke made in canvas points and written through the inverse is shown exactly where it was
    /// made, at the width it was made — under a slide, a turn and a scale at once.
    func testAStrokeWrittenThroughTheInverseIsShownWhereItWasDrawn() throws {
        let move = CGAffineTransform(translationX: 30, y: 10).rotated(by: 0.3).scaledBy(x: 1.5, y: 1.5)
        let fx = layerUnderMove(move)
        let pose = fx.manager.inkPose(forLayerID: fx.manager.layers[fx.ink].id)
        let drawn = VectorStroke(brush: BrushLibrary.roundHard,
                                 color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 12,
                                 opacity: 1, samples: StrokeSamples(points: [CGPoint(x: 40, y: 50),
                                                                             CGPoint(x: 120, y: 90)]))
        let stored = try XCTUnwrap(CanvasManager.inLayerSpace(.stroke(drawn), shownThrough: pose)?.stroke)
        XCTAssertNotEqual(stored.samples.positions, drawn.samples.positions, "nothing was pulled back")
        let onScreen = try XCTUnwrap(shown(.stroke(stored), in: fx.manager, layer: fx.ink).stroke)
        for (a, b) in zip(onScreen.samples.positions, drawn.samples.positions) {
            assertSame(a, b, "a stored point is not shown where the pen put it")
        }
        XCTAssertEqual(onScreen.size, drawn.size, accuracy: 1e-6, "the mark is not shown at the size drawn")
    }

    /// **The smart shape, committed a frame change later**: the outline is in canvas points and is
    /// written through the pose it was drawn under.
    func testASmartShapeUnderAMoveLayerLandsWhereItsOutlineWas() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: -50, y: 20))
        let start = CGPoint(x: 60, y: 120), end = CGPoint(x: 200, y: 120)
        let samples = (0...10).map { i -> VectorSample in
            let t = CGFloat(i) / 10
            return VectorSample(x: start.x + (end.x - start.x) * t, y: start.y, pressure: 1)
        }
        fx.manager.beginInteractiveShape(ShapeGeometry(kind: .line, startPoint: start, endPoint: end),
                                         samples: samples)
        fx.manager.endInteractiveShape()
        fx.manager.commitInteractiveShape()
        let stored = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.elements.last?.stroke,
                                   "the shape committed nothing")
        let onScreen = try XCTUnwrap(shown(.stroke(stored), in: fx.manager, layer: fx.ink).stroke)
        let ys = onScreen.samples.positions.map(\.y)
        XCTAssertEqual(ys.min() ?? 0, 120, accuracy: 0.5, "the line is not shown on the row it was drawn on")
        XCTAssertEqual(ys.max() ?? 0, 120, accuracy: 0.5)
        XCTAssertEqual(onScreen.samples.positions.map(\.x).min() ?? 0, 60, accuracy: 1.5,
                       "the line is not shown starting where it was drawn")
    }

    /// **Text placed by a tap** is edited where the artist sees it and stored through the inverse, so
    /// its box is shown at the tap.
    func testTextPlacedUnderAMoveLayerIsShownAtTheTap() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 35, y: 15))
        fx.manager.selectedTool = .text
        let tap = CGPoint(x: 90, y: 70)
        fx.manager.beginTextSession(at: tap)
        fx.manager.updateTextString("Hi")
        fx.manager.commitInteractiveText()
        let stored = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.elements.compactMap(\.text).first,
                                   "the session committed no text")
        let onScreen = try XCTUnwrap(shown(.text(stored), in: fx.manager, layer: fx.ink).text)
        assertSame(onScreen.frame.corners.first, tap, "the box is not shown at the tap")
    }

    /// **A loop drawn round the ink where it is shown** catches it: the container pose reaches the
    /// per-element pull-back the lasso, the Move box and every nudge all read.
    func testALassoRoundTheShownInkPullsBackOntoTheStoredInk() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 80, y: 0))
        let vector = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector)
        vector.addStroke(VectorStroke(brush: BrushLibrary.roundHard,
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 6,
                                      opacity: 1, samples: StrokeSamples(points: [CGPoint(x: 40, y: 40),
                                                                                  CGPoint(x: 60, y: 40)])))
        let element = try XCTUnwrap(vector.elements.last)
        let shownLoop = CGPath(rect: CGRect(x: 110, y: 30, width: 40, height: 20), transform: nil)
        let maps = fx.manager.celPoseMaps(vector.elements, layerID: fx.manager.layers[fx.ink].id,
                                          celID: fx.manager.layers[fx.ink].cels[0].id, atFrame: 0)
        let loops = CanvasManager.lassoLoops(shownLoop, posedBy: maps)
        XCTAssertTrue(loops.path(for: element.id).contains(CGPoint(x: 50, y: 40)),
                      "the loop round the shown ink does not reach the ink where it is stored")
    }

    /// **The universal eraser** reaches every layer at once, so its gesture is in canvas points and
    /// each target takes it through its own pose.
    func testAUniversalEraserReachesEachLayerThroughItsOwnPose() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 25, y: 0))
        let target = try XCTUnwrap(fx.manager.universalEraseTargets().first)
        XCTAssertEqual(target.pose, fx.manager.inkPose(forLayerID: fx.manager.layers[fx.ink].id))
        let own = try XCTUnwrap(target.inOwnSpace(StrokeSamples(points: [CGPoint(x: 75, y: 9)]), size: 8))
        assertSame(own.run.positions.first, CGPoint(x: 50, y: 9), "the eraser is not taken into the layer")
        XCTAssertEqual(own.size, 8, accuracy: 1e-9)
    }

    /// **A fill tapped on the shown picture floods the region the tap is shown in.** A hollow box at
    /// rest, slid 100 points right by a Move layer: the tap inside the box *as shown* is outside it
    /// at rest, so without the pull-back the flood takes the paper around the box instead.
    func testAFillTappedInsideTheShownBoxFillsTheBox() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addLayer(name: "ink")
        manager.addTransformLayer(name: "move")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box,
                                                               mappedBy: CGAffineTransform(translationX: 100, y: 0)),
                                                mode: .move)
        manager.currentLayerIndex = 0
        manager.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        let ring = UIGraphicsImageRenderer(size: Self.size, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setStroke()
            ctx.cgContext.setLineWidth(4)
            ctx.cgContext.stroke(CGRect(x: 30, y: 30, width: 60, height: 60))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ring)

        manager.beginInteractiveFill(at: CGPoint(x: 160, y: 60))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { done.fulfill() }
        wait(for: [done], timeout: 6)
        manager.commitInteractiveFill()

        let cg = try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
        func red(_ x: Int, _ y: Int) -> Bool {
            let i = (y * cg.width + x) * 4
            return bytes[i + 3] > 200 && bytes[i] > 200 && bytes[i + 1] < 60
        }
        XCTAssertTrue(red(60, 60), "the box the tap is shown in was not filled")
        XCTAssertFalse(red(160, 60), "the paper beside the box was filled instead")
    }

    // MARK: - Pixels: a raster lasso and its Move, asked where the canvas shows them

    /// **A pixel layer holding a 40-point black square at (20, 100), under a Move layer that slides it
    /// 80 points right** — so the artist sees it at (100, 100), and a loop drawn round it there is
    /// round pixels that are stored 80 points to the left of the loop. A bystander square at (100, 20)
    /// is shown at (180, 20), outside any loop drawn round the first.
    private func pixelsUnderMove() -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addLayer(name: "ink")
        manager.addTransformLayer(name: "move")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box,
                                                               mappedBy: CGAffineTransform(translationX: 80, y: 0)),
                                                mode: .move)
        manager.currentLayerIndex = 0
        let ink = UIGraphicsImageRenderer(size: Self.size, format: PixelOps.transparentFormat()).image { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(x: 20, y: 100, width: 40, height: 40))
            context.cgContext.fill(CGRect(x: 100, y: 20, width: 30, height: 30))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ink)
        return manager
    }

    /// A loop round the square **as the artist sees it**, on the layer's current cel.
    private func selectShownSquare(_ manager: CanvasManager) {
        let loop = CGRect(x: 90, y: 90, width: 60, height: 60)
        manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop,
                                      layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id)
    }

    /// Whether a pixel of a layer's *stored* picture is inked.
    private func storedInk(_ manager: CanvasManager, layer: Int = 0, _ x: Int, _ y: Int) -> Bool {
        let image = PixelOps.rasterize(cel: manager.layers[layer].cels[0], canvasSize: Self.size)
        guard let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return false }
        return bytes[(y * cg.width + x) * 4 + 3] > 200
    }

    private func nudgeFloat(_ manager: CanvasManager, dx: CGFloat) throws {
        var transform = try XCTUnwrap(manager.floatingPiece?.transform, "nothing floats")
        transform.position.x += dx
        manager.updateFloatingPose(transform: transform, distortQuad: nil)
    }

    /// **The raster Move lifts what the loop is round and puts it down where it is dropped.** Lifted
    /// from the stored pixels the loop catches nothing (the ink is 80 points to its left), and set
    /// down by writing the piece's canvas position into the layer it lands 80 points from where it was
    /// let go — both halves of that are what the pose-aware lift and landing exist to prevent.
    func testARasterMoveUnderAMoveLayerLiftsWhatIsShownAndLandsWhereItIsDropped() throws {
        let manager = pixelsUnderMove()
        selectShownSquare(manager)

        manager.beginMove()
        let piece = try XCTUnwrap(manager.floatingPiece, "Move lifted nothing")
        XCTAssertNotNil(PixelOps.opaqueContentBounds(piece.pieceImage),
                        "the loop is round the shown ink and the piece it lifted is empty")
        let hole = try XCTUnwrap(piece.remainderPreview)
        XCTAssertEqual(PixelOps.opaqueContentBounds(hole), CGRect(x: 100, y: 20, width: 30, height: 30),
                       "the hole is not the lifted ink and nothing else: the cel should keep only the bystander, where it is stored")

        try nudgeFloat(manager, dx: 30)
        manager.commitFloatingPieceIfNeeded()

        XCTAssertFalse(storedInk(manager, 30, 120), "the square is still where it was stored")
        XCTAssertTrue(storedInk(manager, 70, 120),
                      "dropped 30 points right of where it was shown, the square is not stored 30 right of where it was")
        XCTAssertFalse(storedInk(manager, 150, 120), "the drop was written at the pen's own coordinates, a pose away")
        XCTAssertTrue(storedInk(manager, 110, 30), "what the loop was not round moved: it is no longer stored where it was")
        XCTAssertFalse(storedInk(manager, 190, 30), "what the loop was not round was carried a pose along with the cel's remainder")
    }

    /// **Duplicate copies what the loop is round onto a new layer, and the new layer is shown under
    /// the same Move layer** — so a copy let go in place is shown exactly over the original.
    func testADuplicateUnderAMoveLayerLandsOverTheOriginal() throws {
        let manager = pixelsUnderMove()
        selectShownSquare(manager)

        manager.beginDuplicate()
        XCTAssertEqual(manager.layers.count, 3, "the copy's layer was not added")
        manager.commitFloatingPieceIfNeeded()

        let copy = try XCTUnwrap(manager.layers.firstIndex { $0.id != manager.layers[0].id && $0.kind == .raster })
        XCTAssertTrue(storedInk(manager, layer: copy, 30, 120), "the copy is not stored where the original is")
        XCTAssertFalse(storedInk(manager, layer: copy, 110, 120), "the copy was written at the pen's own coordinates")
        XCTAssertTrue(storedInk(manager, layer: 0, 30, 120), "a copy took the original with it")
    }

    /// **To New Layer cuts in the layer's own space**: the piece leaves the source and arrives where it
    /// was stored, and so is shown where it was.
    func testToNewLayerUnderAMoveLayerCutsWhatTheLoopIsRoundAndNothingElse() throws {
        let manager = pixelsUnderMove()
        selectShownSquare(manager)

        manager.moveSelectionToNewLayer()

        let source = try XCTUnwrap(manager.layers.firstIndex { $0.name == "ink" })
        let moved = try XCTUnwrap(manager.layers.firstIndex { $0.kind == .raster && $0.name != "ink" })
        XCTAssertFalse(storedInk(manager, layer: source, 30, 120), "the source kept what the loop is round")
        XCTAssertTrue(storedInk(manager, layer: moved, 30, 120), "the new layer did not get it")
    }

    /// **Clear and Fill reach the stored pixels through the loop pulled back**, not through the loop as
    /// drawn, which is 80 points from them.
    func testClearAndFillOnARasterSelectionUnderAMoveLayerActWhereTheLoopIsShown() throws {
        let cleared = pixelsUnderMove()
        selectShownSquare(cleared)
        cleared.clearSelectionPixels()
        XCTAssertFalse(storedInk(cleared, 30, 120), "Clear missed the ink the loop is round")

        let filled = pixelsUnderMove()
        filled.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        filled.brushOpacity = 1
        selectShownSquare(filled)
        filled.fillSelection()
        XCTAssertTrue(storedInk(filled, 40, 95), "Fill painted nowhere the loop is shown")
        XCTAssertFalse(storedInk(filled, 140, 95), "Fill painted at the pen's own coordinates, a pose away")
    }

    /// **Fill on a vector selection** goes through the same pull-back: the element it lays down is
    /// shown where the loop was drawn, not a pose away from it.
    func testFillOnAVectorSelectionUnderAMoveLayerIsShownInsideTheLoop() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 80, y: 0))
        let loop = CGRect(x: 110, y: 30, width: 40, height: 20)
        fx.manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop,
                                         layerID: fx.manager.layers[fx.ink].id,
                                         celID: fx.manager.layers[fx.ink].cels[0].id)
        fx.manager.fillSelection()
        let element = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.elements.last, "Fill laid nothing down")
        let onScreen = try XCTUnwrap(shown(element, in: fx.manager, layer: fx.ink).fill?.cgPath)
        let box = onScreen.boundingBoxOfPath
        XCTAssertEqual(box.minX, loop.minX, accuracy: 1, "the fill is not shown inside the loop")
        XCTAssertEqual(box.width, loop.width, accuracy: 1)
        XCTAssertEqual(box.minY, loop.minY, accuracy: 1)
    }

    /// **The wand reads what is shown**, so the region it selects is where the artist tapped.
    func testTheMagicWandUnderAMoveLayerSelectsTheShownSquare() throws {
        let manager = pixelsUnderMove()
        manager.finishAutomaticSelection(at: CGPoint(x: 120, y: 120))
        let bounds = try XCTUnwrap(manager.selection?.bounds, "the wand selected nothing")
        XCTAssertEqual(bounds.minX, 100, accuracy: 1.5, "the selection is not where the square is shown")
        XCTAssertEqual(bounds.width, 40, accuracy: 1.5)
    }
}
