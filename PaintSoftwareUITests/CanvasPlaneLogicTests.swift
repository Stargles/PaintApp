import UIKit
import XCTest

/// **Outside the paper is still canvas** — TODO (121), and `CanvasPlaneView`'s one rule.
///
/// > *"whatever is outside the canvas still should be counted, as if the canvas does extend further,
/// > with the only difference being the stuff outside the border just isnt rendered."*
///
/// Every assertion here asks UIKit's own `hitTest`, on the real overlay classes, pinned to a
/// container the way `CanvasView.makeUIView` pins them — and asks it twice: once for a point on the
/// paper and once for the same kind of point off it. **The claim under test is that the two answers
/// are the same**, so each off-paper assertion has its on-paper twin beside it, and
/// `assertOffCanvas` guards the one way they could agree vacuously (a "far" point that turned out
/// to be on the paper after all).
///
/// The rows the owner named: a smart-shape line's far node (their first repro), a Move box's grip
/// (the patch this replaces), a full-plane claimant standing for the active layer's stroke view (a
/// stroke started outside), and the container itself, which carries the navigation transform (a pan
/// from the grey) and every other canvas recognizer.
final class CanvasPlaneLogicTests: XCTestCase {

    /// The owner's working document, so "outside the canvas" means what it means on their iPad.
    private static let canvas = CGSize(width: 2048, height: 1024)
    private static let centre = CGPoint(x: 1024, y: 512)

    /// A box three thousand points across on a two-thousand-point canvas: every corner, every edge
    /// grip and both knobs are off the document.
    private static let oversizeContent = CGSize(width: 3000, height: 1600)
    /// The top-left corner of that box, in canvas points: 1024 − 1500, 512 − 800.
    private static let oversizeTopLeft = CGPoint(x: -476, y: -288)
    /// A point on the same box's *body*, off the canvas and far from every grip.
    private static let oversizeBodyOffCanvas = CGPoint(x: -300, y: 100)
    /// The same box's **left edge** grip: 1024 − 1500, 512. Shown in Freeform, hidden in Uniform.
    private static let oversizeLeftEdge = CGPoint(x: -476, y: 512)

    /// A box that fits, for the on-paper twin of each row.
    private static let insideContent = CGSize(width: 400, height: 300)
    private static let insideTopLeft = CGPoint(x: 824, y: 362)

    /// Far from the paper and from every box below.
    private static let farOff = CGPoint(x: -2000, y: -2000)

    // MARK: - Fixtures

    private func container() -> CanvasPlaneView {
        let view = CanvasPlaneView()
        view.bounds = CGRect(origin: .zero, size: Self.canvas)
        return view
    }

    /// The vector float's box, live, pinned to the container the way `CanvasView.makeUIView` pins it.
    @discardableResult
    private func vectorBox(in container: UIView, contentSize: CGSize) -> ObjectTransformOverlayView {
        let overlay = ObjectTransformOverlayView()
        overlay.frame = container.bounds
        container.addSubview(overlay)
        overlay.update(isActive: true,
                       frame: ObjectTransformFrame(
                           transform: LayerTransform(position: Self.centre, scale: 1, rotation: 0),
                           contentSize: contentSize),
                       canvasScale: 1, distorting: false)
        return overlay
    }

    /// The raster float's box — which is also the transformation layer's container-pose box — live.
    /// `.freeform` so the edge grips are shown too.
    @discardableResult
    private func rasterBox(in container: UIView, baseSize: CGSize,
                           mode: TransformMode = .freeform) -> FloatingPieceOverlayView {
        let overlay = FloatingPieceOverlayView()
        overlay.frame = container.bounds
        container.addSubview(overlay)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.black.setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let pose = FloatingTransform(position: Self.centre, scaleX: 1, scaleY: 1, rotation: 0)
        let piece = FloatingPiece(kind: .move,
                                  sourceLayerID: UUID(), sourceCelID: UUID(),
                                  targetLayerID: UUID(), targetCelID: UUID(),
                                  pieceImage: image, baseSize: baseSize,
                                  remainderPreview: nil,
                                  transform: pose, liftTransform: pose, mode: mode)
        overlay.update(piece, isInteractive: true)
        return overlay
    }

    /// A pending smart-shape line, adjustable, the state `CanvasView.Coordinator.updateShapeOverlay`
    /// leaves the overlay in once the pen lifts.
    @discardableResult
    private func pendingLine(in container: UIView, from start: CGPoint, to end: CGPoint) -> ShapeOverlayView {
        let overlay = ShapeOverlayView()
        overlay.frame = container.bounds
        container.addSubview(overlay)
        overlay.isActive = true
        overlay.canvasScale = 1
        overlay.update(shape: ShapeGeometry(kind: .line, startPoint: start, endPoint: end),
                       previewImage: nil, showHandles: true)
        overlay.isUserInteractionEnabled = true
        return overlay
    }

    /// A view that claims the whole plane by inheriting the rule and overriding nothing — the shape
    /// of the active layer's `StrokeCanvasView` and of a capturing `SelectionOverlayView`, neither of
    /// which this target compiles.
    @discardableResult
    private func wholePlaneClaimant(in container: UIView) -> CanvasPlaneView {
        let view = CanvasPlaneView()
        view.frame = container.bounds
        container.addSubview(view)
        return view
    }

    private func assertOffCanvas(_ point: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(CGRect(origin: .zero, size: Self.canvas).contains(point),
                       "\(point) is on the paper, so this row is not about the outside",
                       file: file, line: line)
    }

    // MARK: - The plane itself: a pan, a fill tap, a tap-away that begins on the grey

    /// The container is where every canvas recognizer lives, so a touch it takes off the paper is a
    /// touch the navigation transform, the fill press and the Move box's tap-away all see. Before
    /// TODO (121) this answered nil — the touch fell to the host, which carried the transform alone.
    func testTheContainerTakesATouchAnywhereInThePlane() {
        assertOffCanvas(Self.farOff)
        let plane = container()
        XCTAssertTrue(plane.hitTest(Self.farOff, with: nil) === plane)
        XCTAssertTrue(plane.hitTest(Self.centre, with: nil) === plane)
    }

    /// **The stroke started outside the canvas**, at hit-test level: the view a stroke is drawn on
    /// takes the touch out there as it does on the paper.
    func testAWholePlaneClaimantTakesATouchOffThePaper() {
        assertOffCanvas(Self.farOff)
        let plane = container()
        let strokeSurface = wholePlaneClaimant(in: plane)
        XCTAssertTrue(plane.hitTest(Self.farOff, with: nil) === strokeSurface)
        XCTAssertTrue(plane.hitTest(Self.centre, with: nil) === strokeSurface)
    }

    /// **The rule is the class, and this row is what makes it load-bearing**: the same document-sized
    /// child as a bare `UIView` refuses every point off the paper, which is the defect every
    /// per-feature patch was working round. The touch still reaches the plane itself, so it is not
    /// lost — it is simply not the child's.
    func testADocumentSizedViewOutsideTheRuleIsWhatTheDefectWas() {
        assertOffCanvas(Self.farOff)
        let plane = container()
        let bare = UIView()
        bare.frame = plane.bounds
        plane.addSubview(bare)
        XCTAssertTrue(plane.hitTest(Self.centre, with: nil) === bare)
        XCTAssertTrue(plane.hitTest(Self.farOff, with: nil) === plane,
                      "a bare document-sized view took a touch off the paper")
    }

    /// A container that is not taking touches hands out nothing, on the paper or off it.
    func testAHiddenDisabledOrInvisibleContainerTakesNothing() {
        assertOffCanvas(Self.oversizeTopLeft)
        for disable in [{ (v: UIView) in v.isHidden = true },
                        { (v: UIView) in v.isUserInteractionEnabled = false },
                        { (v: UIView) in v.alpha = 0 }] {
            let plane = container()
            vectorBox(in: plane, contentSize: Self.oversizeContent)
            wholePlaneClaimant(in: plane)
            disable(plane)
            XCTAssertNil(plane.hitTest(Self.oversizeTopLeft, with: nil))
            XCTAssertNil(plane.hitTest(Self.centre, with: nil))
        }
    }

    // MARK: - A smart-shape line half off the canvas (the owner's first repro)

    /// The owner: *"If you make a line half inside the canvas half outside, make that into a smart
    /// shape, then try to move the node sitting outside the canvas, it does not let you."* The
    /// overlay always claimed that node; the container never asked it.
    func testASmartShapeNodeOffTheCanvasIsTheShapes() {
        let inside = CGPoint(x: 1024, y: 400)
        let outside = CGPoint(x: 1024, y: -120)
        assertOffCanvas(outside)
        let plane = container()
        wholePlaneClaimant(in: plane)
        let shape = pendingLine(in: plane, from: inside, to: outside)
        XCTAssertEqual(shape.target(at: outside), .end, "the fixture point is not the far node")
        XCTAssertEqual(shape.target(at: inside), .start)
        XCTAssertTrue(plane.hitTest(outside, with: nil) === shape, "the node off the canvas is unreachable")
        XCTAssertTrue(plane.hitTest(inside, with: nil) === shape)
    }

    /// And off the shape it is the canvas's, there as on the paper: a stroke beside a pending shape
    /// is a stroke, wherever it starts.
    func testOffTheShapeTheTouchFallsToThePlaneOffThePaperToo() {
        let outside = CGPoint(x: 1024, y: -120)
        let plane = container()
        let strokeSurface = wholePlaneClaimant(in: plane)
        pendingLine(in: plane, from: CGPoint(x: 1024, y: 400), to: outside)
        let besideOff = CGPoint(x: 300, y: -120)
        let besideOn = CGPoint(x: 300, y: 600)
        assertOffCanvas(besideOff)
        XCTAssertTrue(plane.hitTest(besideOff, with: nil) === strokeSurface)
        XCTAssertTrue(plane.hitTest(besideOn, with: nil) === strokeSurface)
    }

    // MARK: - The vector float's box

    func testAVectorBoxGripOffTheCanvasIsTheBoxs() {
        assertOffCanvas(Self.oversizeTopLeft)
        let plane = container()
        let overlay = vectorBox(in: plane, contentSize: Self.oversizeContent)
        XCTAssertEqual(overlay.target(at: Self.oversizeTopLeft), .topLeft)
        XCTAssertTrue(plane.hitTest(Self.oversizeTopLeft, with: nil) === overlay)

        let onPaper = container()
        let small = vectorBox(in: onPaper, contentSize: Self.insideContent)
        XCTAssertEqual(small.target(at: Self.insideTopLeft), .topLeft)
        XCTAssertTrue(onPaper.hitTest(Self.insideTopLeft, with: nil) === small)
    }

    /// **The body counts out there too.** The patch this replaces excluded it, so a box scaled past
    /// the paper could be scaled from the grey but not moved from it — the asymmetry the owner calls
    /// "tagged on". On the paper a touch on the body moves the box; off it, now, the same.
    func testAVectorBoxBodyOffTheCanvasIsTheBoxs() {
        assertOffCanvas(Self.oversizeBodyOffCanvas)
        let plane = container()
        let overlay = vectorBox(in: plane, contentSize: Self.oversizeContent)
        XCTAssertEqual(overlay.target(at: Self.oversizeBodyOffCanvas), .body,
                       "the fixture point is not on the box body, so this asserts nothing")
        XCTAssertTrue(plane.hitTest(Self.oversizeBodyOffCanvas, with: nil) === overlay)
    }

    /// Away from the box the touch is the plane's, where `handleMoveBoxCommit` — the tap away that
    /// puts the box down — lives, on the paper and off it alike.
    func testAwayFromTheVectorBoxTheTouchIsThePlanes() {
        assertOffCanvas(Self.farOff)
        let plane = container()
        let overlay = vectorBox(in: plane, contentSize: Self.insideContent)
        XCTAssertNil(overlay.target(at: Self.farOff))
        XCTAssertTrue(plane.hitTest(Self.farOff, with: nil) === plane)
        XCTAssertTrue(plane.hitTest(CGPoint(x: 40, y: 40), with: nil) === plane)
    }

    func testADeactivatedHiddenOrDisabledVectorBoxClaimsNothingOffTheCanvas() {
        assertOffCanvas(Self.oversizeTopLeft)
        for disable in [{ (o: ObjectTransformOverlayView) in o.deactivate() },
                        { (o: ObjectTransformOverlayView) in o.isHidden = true },
                        { (o: ObjectTransformOverlayView) in o.isUserInteractionEnabled = false }] {
            let plane = container()
            let overlay = vectorBox(in: plane, contentSize: Self.oversizeContent)
            disable(overlay)
            XCTAssertTrue(plane.hitTest(Self.oversizeTopLeft, with: nil) === plane)
        }
    }

    // MARK: - The raster float's box (and the transformation layer's container-pose box)

    func testARasterBoxGripOffTheCanvasIsAGrip() {
        assertOffCanvas(Self.oversizeTopLeft)
        let plane = container()
        let overlay = rasterBox(in: plane, baseSize: Self.oversizeContent)
        let hit = plane.hitTest(Self.oversizeTopLeft, with: nil)
        XCTAssertTrue(hit is TransformHandleView, "got \(String(describing: hit)) — not a grip")
        XCTAssertTrue(hit?.superview === overlay)
    }

    /// The raster box's claim is total on the paper — every touch is its, including the tap that
    /// commits — and now it is total off it, which is the same rule rather than a new one.
    func testTheRasterBoxsTotalClaimIsTheSameOnAndOffThePaper() {
        assertOffCanvas(Self.oversizeBodyOffCanvas)
        let plane = container()
        let overlay = rasterBox(in: plane, baseSize: Self.insideContent)
        XCTAssertTrue(plane.hitTest(CGPoint(x: 40, y: 40), with: nil) === overlay)
        XCTAssertTrue(plane.hitTest(Self.oversizeBodyOffCanvas, with: nil) === overlay)
        XCTAssertTrue(plane.hitTest(Self.farOff, with: nil) === overlay)
    }

    /// A grip that is **hidden** is not a grip, off the paper as on it: Uniform hides the four edge
    /// grips without moving them, so the same point answers the grip in Freeform and the box's
    /// outline — its move — in Uniform.
    func testAnEdgeGripOffTheCanvasFollowsTheModeThatHidesIt() {
        assertOffCanvas(Self.oversizeLeftEdge)
        let freeform = container()
        rasterBox(in: freeform, baseSize: Self.oversizeContent, mode: .freeform)
        XCTAssertTrue(freeform.hitTest(Self.oversizeLeftEdge, with: nil) is TransformHandleView)

        let uniform = container()
        let box = rasterBox(in: uniform, baseSize: Self.oversizeContent, mode: .uniform)
        let hit = uniform.hitTest(Self.oversizeLeftEdge, with: nil)
        XCTAssertFalse(hit is TransformHandleView, "a grip Uniform hides is draggable off the canvas")
        XCTAssertTrue(hit?.isDescendant(of: box) == true, "the box's own body did not take the touch")
    }

    func testADismissedRasterBoxClaimsNothingOffTheCanvas() {
        assertOffCanvas(Self.oversizeTopLeft)
        let plane = container()
        let overlay = rasterBox(in: plane, baseSize: Self.oversizeContent)
        overlay.update(nil, isInteractive: false)
        XCTAssertTrue(plane.hitTest(Self.oversizeTopLeft, with: nil) === plane)
    }

    /// Front to back, off the paper exactly as on it: UIKit's own z-order decides, because nothing
    /// off the paper is decided anywhere else any more.
    func testTheFrontmostOverlayWinsOffThePaperAsOnIt() {
        assertOffCanvas(Self.oversizeTopLeft)
        let plane = container()
        let behind = vectorBox(in: plane, contentSize: Self.oversizeContent)
        rasterBox(in: plane, baseSize: Self.oversizeContent)
        let hit = plane.hitTest(Self.oversizeTopLeft, with: nil)
        XCTAssertTrue(hit is TransformHandleView, "the box behind answered")
        XCTAssertFalse(hit === behind)
    }
    // MARK: - The raster tier: the outside run of a stroke is counted, only not rendered

    /// **A raster stroke started off the paper lays exactly the pixels the same stroke lays on a
    /// canvas that really does extend that far** — the owner's sentence, taken literally on the tier
    /// where it is least obvious, because a raster cel has no pixels out there to hold anything.
    ///
    /// The two operands are one stroke drawn twice: onto this canvas starting 60 pt off its left
    /// edge, and onto a canvas 64 pt wider on that side with every sample shifted by the same 64, so
    /// the whole stroke is on the paper. Cropped back to the original canvas the pictures must agree
    /// to the byte. That holds only if the live walk carries its spacing, pressure and rhythm through
    /// the outside run and the scratch merely drops the dabs that land nowhere: a walk restarted at
    /// the edge, samples clamped to the canvas, or a dab straddling the edge thrown away whole would
    /// each move the ink that is visible.
    func testARasterStrokeStartedOffThePaperDrawsWhatAnExtendedCanvasWould() throws {
        let canvas = CGSize(width: 256, height: 128)
        let margin: CGFloat = 64
        let brush = BrushLibrary.roundHard
        let raw: [VectorSample] = (0...160).map { i in
            let t = CGFloat(i) / 160
            return VectorSample(x: -60 + 280 * t, y: 64 + 30 * sin(t * 3), pressure: 0.3 + 0.6 * t,
                                deltaTime: 1 / 120)
        }
        func draw(_ samples: [VectorSample], on size: CGSize) -> RasterLayerTexture {
            let scratch = StrokeScratch(canvasSize: size, role: .additive, opacity: 1,
                                        blendMode: brush.stroke.blendMode.cgBlendMode, texture: brush.texture)
            var walk = BrushStamper.LiveWalk(seed: 0x121)
            for sample in samples {
                walk.stamp(to: sample, into: scratch, brush: brush, color: .black, brushSize: 18)
            }
            walk.finish(into: scratch, brush: brush, color: .black, brushSize: 18)
            let texture = RasterLayerTexture.empty(size: size)
            scratch.commit(into: texture)
            return texture
        }
        XCTAssertLessThan(raw[0].x, 0, "the stroke starts on the paper, so this measures nothing")

        let here = draw(raw, on: canvas).renderToUIImage()
        let wider = draw(raw.map { var shifted = $0; shifted.x += margin; return shifted },
                         on: CGSize(width: canvas.width + margin, height: canvas.height))
        let extended = try XCTUnwrap(wider.copiedPatch(in: CGRect(origin: CGPoint(x: margin, y: 0), size: canvas)))
        let report = try XCTUnwrap(RasterVectorParity.report(raster: here, vector: extended, size: canvas))
        XCTAssertGreaterThan(RasterVectorParity.report(raster: here, vector: RasterLayerTexture.empty(size: canvas)
                                                        .renderToUIImage(), size: canvas)?.differingPixelCount ?? 0,
                             500, "the stroke left no ink on the paper, so the comparison is vacuous")
        XCTAssertEqual(report.differingPixelCount, 0,
                       "the visible ink differs from the extended canvas's: max \(report.maxChannelDelta)/255 "
                       + "over \(report.differingPixelCount) px")
    }
}
