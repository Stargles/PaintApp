import UIKit
import XCTest

/// **A transform grip drawn past the edge of the canvas has to receive a touch there** — TODO item
/// (48), the owner's 2026-09-05 report:
///
/// > *"right now I cannot grab a move node that is outside of the canvas. If the box is too big to
/// > fit on the canvas, then I got to first move the box to bring one of the nodes inside the
/// > canvas and then tap that node to scale it down."*
///
/// and the clarification that settles the design:
///
/// > *"the move handle right now goes off the canvas, thats fine. I just want to be able to adjust
/// > it which right now I cant."*
///
/// So the grip's **position** is correct and untouched, and nothing here asserts one. What was
/// wrong is the *reach*, and the reach is decided by `CanvasContainerView.hitTest`: `CanvasView`'s
/// zoom/pan container has `bounds` exactly the size of the document, and `UIView.hitTest` refuses
/// to recurse into subviews for a point outside the receiver's own bounds. Both transform overlays
/// were already written to accept such a point — `ObjectTransformOverlayView.hitTest`'s doc comment
/// says *"A grip can sit outside this view's bounds … containment in `bounds` is deliberately not
/// consulted"* — and neither was ever asked.
///
/// **Every assertion here is on what the hit test answers, never on where a handle is drawn.** A
/// test on the drawn frame passes today, before any of this, which is exactly the vacuous pin
/// CLAUDE.md's "a green assertion is only as good as its two operands" section is about.
///
/// The two overlays do not share code and are tested separately: `ObjectTransformOverlayView` is
/// the vector float's box and answers with *itself*, `FloatingPieceOverlayView` is the raster
/// float's **and the container-pose box's** — both are `FloatingPiece` kinds through one view — and
/// answers with a `TransformHandleView` subview.
final class OffCanvasHandleLogicTests: XCTestCase {

    /// The owner's working document, so "outside the canvas" means what it means on their iPad.
    private static let canvas = CGSize(width: 2048, height: 1024)
    private static let centre = CGPoint(x: 1024, y: 512)

    /// A box three thousand points across on a two-thousand-point canvas: every corner, every edge
    /// grip and both knobs are off the document. This is the state the owner describes — a
    /// selection scaled too large to fit — and before this fix nothing in it could be grabbed.
    private static let oversizeContent = CGSize(width: 3000, height: 1600)
    /// The top-left corner of that box, in canvas points: 1024 − 1500, 512 − 800.
    private static let oversizeTopLeft = CGPoint(x: -476, y: -288)
    /// A point on the same box's *body*, off the canvas and far from every grip.
    private static let oversizeBodyOffCanvas = CGPoint(x: -300, y: 100)

    /// The same box's **left edge** grip: 1024 − 1500, 512. Shown in Freeform, hidden in Uniform.
    private static let oversizeLeftEdge = CGPoint(x: -476, y: 512)

    /// A box that fits, for the regression half: nothing about the ordinary case may change.
    private static let insideContent = CGSize(width: 400, height: 300)
    private static let insideTopLeft = CGPoint(x: 824, y: 362)

    // MARK: - Fixtures

    private func container() -> CanvasContainerView {
        let view = CanvasContainerView()
        view.bounds = CGRect(origin: .zero, size: Self.canvas)
        return view
    }

    /// The vector float's box, live, pinned to the container the way `CanvasView.makeUIView` pins it.
    @discardableResult
    private func vectorBox(in container: CanvasContainerView,
                           contentSize: CGSize) -> ObjectTransformOverlayView {
        let overlay = ObjectTransformOverlayView()
        overlay.frame = container.bounds
        container.addSubview(overlay)
        overlay.update(isActive: true,
                       frame: ObjectTransformFrame(
                           transform: LayerTransform(position: Self.centre, scale: 1, rotation: 0),
                           contentSize: contentSize),
                       canvasScale: 1)
        return overlay
    }

    /// The raster float's box, live. `.freeform` so the edge grips are shown too, which is the mode
    /// with the most handles off the canvas.
    @discardableResult
    private func rasterBox(in container: CanvasContainerView,
                           baseSize: CGSize,
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

    /// Guards every off-canvas assertion below against the one way they could all pass vacuously:
    /// a point that turned out to be *inside* the canvas after all.
    private func assertOffCanvas(_ point: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(CGRect(origin: .zero, size: Self.canvas).contains(point),
                       "\(point) is inside the canvas, so this test is not about off-canvas reach",
                       file: file, line: line)
    }

    // MARK: - The vector float's box

    func testAGripOffTheCanvasIsReachedOnTheVectorBox() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let overlay = vectorBox(in: container, contentSize: Self.oversizeContent)
        // The premise, asserted rather than assumed: this really is the top-left grip's point.
        XCTAssertEqual(overlay.target(at: Self.oversizeTopLeft), .topLeft)
        XCTAssertTrue(container.hitTest(Self.oversizeTopLeft, with: nil) === overlay,
                      "a corner grip past the canvas edge is unreachable")
    }

    /// The exclusion that keeps the fix from costing anything: the *body* of an oversized box covers
    /// the whole surround, and claiming it would take every off-canvas touch rather than the grips
    /// the owner asked to reach.
    func testTheBoxBodyOffTheCanvasIsNobodys() {
        assertOffCanvas(Self.oversizeBodyOffCanvas)
        let container = container()
        let overlay = vectorBox(in: container, contentSize: Self.oversizeContent)
        XCTAssertEqual(overlay.target(at: Self.oversizeBodyOffCanvas), .body,
                       "the fixture point is not on the box body, so this asserts nothing")
        XCTAssertNil(container.hitTest(Self.oversizeBodyOffCanvas, with: nil))
    }

    func testAPointOffTheCanvasAndOffTheBoxIsNobodys() {
        let far = CGPoint(x: -2000, y: -2000)
        assertOffCanvas(far)
        let container = container()
        let overlay = vectorBox(in: container, contentSize: Self.oversizeContent)
        XCTAssertNil(overlay.target(at: far))
        XCTAssertNil(container.hitTest(far, with: nil))
    }

    func testADeactivatedVectorBoxClaimsNothingOffTheCanvas() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let overlay = vectorBox(in: container, contentSize: Self.oversizeContent)
        overlay.deactivate()
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    /// The regression half. A grip inside the document went through `super.hitTest` before this
    /// change and must still.
    func testANonInteractiveVectorBoxClaimsNothingOffTheCanvas() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let overlay = vectorBox(in: container, contentSize: Self.oversizeContent)
        overlay.isUserInteractionEnabled = false
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    func testAHiddenVectorBoxClaimsNothingOffTheCanvas() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let overlay = vectorBox(in: container, contentSize: Self.oversizeContent)
        overlay.isHidden = true
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    func testAGripInsideTheCanvasStillReachesTheVectorBox() {
        XCTAssertTrue(CGRect(origin: .zero, size: Self.canvas).contains(Self.insideTopLeft))
        let container = container()
        let overlay = vectorBox(in: container, contentSize: Self.insideContent)
        XCTAssertEqual(overlay.target(at: Self.insideTopLeft), .topLeft)
        XCTAssertTrue(container.hitTest(Self.insideTopLeft, with: nil) === overlay)
    }

    // MARK: - The raster float's box (and the container-pose box, which is the same view)

    func testAGripOffTheCanvasIsReachedOnTheRasterBox() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let overlay = rasterBox(in: container, baseSize: Self.oversizeContent)
        let hit = container.hitTest(Self.oversizeTopLeft, with: nil)
        XCTAssertTrue(hit is TransformHandleView, "got \(String(describing: hit)) — not a grip")
        XCTAssertTrue(hit?.superview === overlay)
        // The grip, not the overlay: `TransformOverlayView.point(inside:)` is unconditionally true,
        // so answering with the overlay would be answering every off-canvas point.
        XCTAssertFalse(hit === overlay)
    }

    func testTheRasterBoxsTotalClaimDoesNotLeakOffTheCanvas() {
        assertOffCanvas(Self.oversizeBodyOffCanvas)
        let container = container()
        rasterBox(in: container, baseSize: Self.oversizeContent)
        XCTAssertNil(container.hitTest(Self.oversizeBodyOffCanvas, with: nil),
                     "the tap-away commit now owns the black surround")
    }

    /// A grip that is **hidden** is not a grip. Freeform shows the four edge handles and Uniform
    /// hides them without moving them, so the same point has to answer differently in the two
    /// modes — and asserting both is what stops this passing because the point was simply wrong.
    func testAnEdgeGripOffTheCanvasFollowsTheModeThatHidesIt() {
        assertOffCanvas(Self.oversizeLeftEdge)
        let freeform = container()
        rasterBox(in: freeform, baseSize: Self.oversizeContent, mode: .freeform)
        XCTAssertTrue(freeform.hitTest(Self.oversizeLeftEdge, with: nil) is TransformHandleView)

        let uniform = container()
        rasterBox(in: uniform, baseSize: Self.oversizeContent, mode: .uniform)
        XCTAssertNil(uniform.hitTest(Self.oversizeLeftEdge, with: nil),
                     "a grip Uniform hides is draggable off the canvas")
    }

    func testANonInteractiveRasterBoxClaimsNothingOffTheCanvas() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let overlay = rasterBox(in: container, baseSize: Self.oversizeContent)
        overlay.isUserInteractionEnabled = false
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    func testADismissedRasterBoxClaimsNothingOffTheCanvas() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let overlay = rasterBox(in: container, baseSize: Self.oversizeContent)
        overlay.update(nil, isInteractive: false)
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    /// Inside the canvas the raster overlay's claim is total — every touch is its, including the
    /// tap that commits. That is `FloatingPieceOverlayView`'s stated design and this change must
    /// not have narrowed it.
    func testTheRasterBoxStillClaimsEveryPointInsideTheCanvas() {
        let container = container()
        let overlay = rasterBox(in: container, baseSize: Self.insideContent)
        let awayFromEveryGrip = CGPoint(x: 40, y: 40)
        XCTAssertTrue(CGRect(origin: .zero, size: Self.canvas).contains(awayFromEveryGrip))
        XCTAssertTrue(container.hitTest(awayFromEveryGrip, with: nil) === overlay)
    }

    // MARK: - The container's own gates

    /// A container that is not taking touches hands out nothing, off-canvas included. `super.hitTest`
    /// answers nil for *two* reasons — the point is outside, or this view is disabled — and only the
    /// first is the one the fallback is for.
    func testADisabledContainerHandsOutNoOffCanvasGrip() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        vectorBox(in: container, contentSize: Self.oversizeContent)
        container.isUserInteractionEnabled = false
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    func testAHiddenRasterOverlayHandsOutNoOffCanvasGrip() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let overlay = rasterBox(in: container, baseSize: Self.oversizeContent)
        overlay.isHidden = true
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    /// Front to back, the order UIKit itself would ask in — asserted rather than assumed, because
    /// "whichever `subviews` happens to yield first" is the same answer on a one-overlay fixture and
    /// the wrong one the moment there are two.
    func testTheFrontmostOverlayWinsAnOffCanvasGrip() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        let behind = vectorBox(in: container, contentSize: Self.oversizeContent)
        rasterBox(in: container, baseSize: Self.oversizeContent)
        let hit = container.hitTest(Self.oversizeTopLeft, with: nil)
        XCTAssertTrue(hit is TransformHandleView, "the box behind answered")
        XCTAssertFalse(hit === behind)
    }

    /// `OffCanvasHandleHitTesting` takes the point in **the overlay's own** coordinates, and every
    /// overlay `CanvasView` adds happens to be pinned edge-to-edge to a container whose
    /// `bounds.origin` is zero — so the conversion is the identity there and a missing one would
    /// never show. This fixture offsets the overlay, which is the only way the contract is a
    /// statement rather than a coincidence.
    func testTheOverlayIsAskedInItsOwnCoordinates() {
        let container = container()
        let overlay = ObjectTransformOverlayView()
        overlay.frame = CGRect(x: 100, y: 50, width: Self.canvas.width, height: Self.canvas.height)
        container.addSubview(overlay)
        overlay.update(isActive: true,
                       frame: ObjectTransformFrame(
                           transform: LayerTransform(position: Self.centre, scale: 1, rotation: 0),
                           contentSize: Self.oversizeContent),
                       canvasScale: 1)
        let inContainer = CGPoint(x: Self.oversizeTopLeft.x + 100, y: Self.oversizeTopLeft.y + 50)
        assertOffCanvas(inContainer)
        XCTAssertTrue(container.hitTest(inContainer, with: nil) === overlay)
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil),
                     "the overlay was asked in the container's coordinates, not its own")
    }

    func testAHiddenContainerHandsOutNoOffCanvasGrip() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        vectorBox(in: container, contentSize: Self.oversizeContent)
        container.isHidden = true
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    func testAnInvisibleContainerHandsOutNoOffCanvasGrip() {
        assertOffCanvas(Self.oversizeTopLeft)
        let container = container()
        vectorBox(in: container, contentSize: Self.oversizeContent)
        container.alpha = 0
        XCTAssertNil(container.hitTest(Self.oversizeTopLeft, with: nil))
    }

    /// A plain `UIView` container is the state this fix replaces, and the assertion is what makes
    /// the subclass load-bearing rather than decorative: put the same live overlay under a bare
    /// `UIView` and the same off-canvas grip is unreachable again.
    func testABareContainerIsWhatTheDefectWas() {
        assertOffCanvas(Self.oversizeTopLeft)
        let bare = UIView()
        bare.bounds = CGRect(origin: .zero, size: Self.canvas)
        let overlay = ObjectTransformOverlayView()
        overlay.frame = bare.bounds
        bare.addSubview(overlay)
        overlay.update(isActive: true,
                       frame: ObjectTransformFrame(
                           transform: LayerTransform(position: Self.centre, scale: 1, rotation: 0),
                           contentSize: Self.oversizeContent),
                       canvasScale: 1)
        XCTAssertEqual(overlay.target(at: Self.oversizeTopLeft), .topLeft)
        XCTAssertNil(bare.hitTest(Self.oversizeTopLeft, with: nil))
    }
}
