import XCTest
import QuartzCore
import UIKit

/// **Distort — LASSO_MOVE.md §3 stage 5, the raster floating piece.**
///
/// Four corners that move independently is a **homography**, not any affine, and this file exists
/// for the one failure the feature is most likely to ship: *a four-corner drag that looks right under
/// the finger and bakes to something else.* §5.17 records that the project has already accepted a
/// bounded version of that once — a Freeform stretch's latched bitmap is not its bake, and the latch
/// has to be dropped at every gesture end to stop the error accumulating.
///
/// **Distort's is not bounded, it is exact, and `testThePreviewMatrixAndTheBakeMatrixAreTheSameMap`
/// is the measurement.** The live preview is a `CATransform3D` whose `m14`/`m24` perform exactly the
/// projective divide `Homography.map` performs, and both are built from the one accessor
/// `FloatingPiece.homography`. There is nothing for the two to disagree about, because there is only
/// one matrix.
///
/// Pure logic, no simulator: `beginMove` / the drag types / `commitFloatingPieceIfNeeded` are the
/// seams the toolbar and the overlay drive, and driving them directly is the same sequence of calls
/// a real gesture produces. What only a running app can say — that a corner handle takes the drag,
/// that the picker is reachable, that the caption appears — is `DistortUITests`.
final class DistortLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let canvas = CanvasFixture.canvasSize      // 64 × 64

    /// A raster floating piece with an opaque `size` bitmap, centred on the canvas.
    ///
    /// Built directly rather than through `beginMove` for the geometry tests, because what they are
    /// about is the map from a *known* box onto a *known* quad — a lift's own bounds rounding would
    /// put a texel of slop between the two operands of every assertion. `testAWholeMoveEndToEnd…`
    /// drives the real lift.
    private func piece(size: CGSize = CGSize(width: 32, height: 16),
                       at centre: CGPoint = CGPoint(x: 32, y: 32),
                       mode: TransformMode = .distort) -> FloatingPiece {
        let image = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        let lift = FloatingTransform(position: centre, scaleX: 1, scaleY: 1, rotation: 0)
        return FloatingPiece(kind: .move,
                             sourceLayerID: UUID(), sourceCelID: UUID(),
                             targetLayerID: UUID(), targetCelID: UUID(),
                             pieceImage: image, baseSize: size,
                             remainderPreview: nil,
                             transform: lift, liftTransform: lift, mode: mode)
    }

    /// A trapezoid: the top edge half as wide as the bottom, in the piece's own local space.
    ///
    /// **The signature of a projective map, chosen because an affine cannot fake it.** Any affine
    /// carries the box to a *parallelogram*, whose horizontal cross-section is the same width at
    /// every height; a trapezoid's is not. So "the top band is narrower than the bottom band" is a
    /// statement no affine bake can satisfy, which is what makes the pixel assertions below a test of
    /// the warp rather than of the piece's position.
    private func trapezoid(_ piece: FloatingPiece, topInset: CGFloat = 8) -> Quad {
        var quad = Quad.rect(piece.localBox)
        quad.p0.x += topInset
        quad.p1.x -= topInset
        return quad
    }

    private func bytes(_ image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage, let raw = CanvasFixture.rgbaBytes(cg) else { return nil }
        return (raw, cg.width, cg.height)
    }

    /// How many pixels of row `y` the bake covered — the measurement the trapezoid test compares two
    /// of. Alpha, not colour: the piece is one flat black rectangle, so coverage is the only thing
    /// the warp can have changed.
    private func opaqueRun(_ image: UIImage, row y: Int, threshold: UInt8 = 128) -> Int {
        guard let (raw, width, height) = bytes(image), y >= 0, y < height else { return -1 }
        return (0..<width).reduce(0) { $0 + (raw[(y * width + $1) * 4 + 3] >= threshold ? 1 : 0) }
    }

    private func alpha(_ image: UIImage, x: Int, y: Int) -> UInt8 {
        guard let (raw, width, height) = bytes(image),
              x >= 0, y >= 0, x < width, y < height else { return 0 }
        return raw[(y * width + x) * 4 + 3]
    }

    /// Core Animation's own arithmetic: **row vectors**, `p' = p · M`, then the perspective divide.
    /// Written out here rather than borrowed from anywhere, because the whole claim of
    /// `testThePreviewMatrixAndTheBakeMatrixAreTheSameMap` is that the transposition inside
    /// `Homography.catransform3D` is the right way round — checking it against a shared helper that
    /// made the same choice would prove nothing.
    private func coreAnimationMap(_ m: CATransform3D, _ p: CGPoint) -> CGPoint? {
        let x = p.x * m.m11 + p.y * m.m21 + m.m41
        let y = p.x * m.m12 + p.y * m.m22 + m.m42
        let w = p.x * m.m14 + p.y * m.m24 + m.m44
        guard abs(w) > 1e-12 else { return nil }
        return CGPoint(x: x / w, y: y / w)
    }

    // MARK: - The seam: a piece nobody has distorted is untouched

    /// **An undistorted piece takes the affine path it always took, and the projective path would
    /// have agreed with it exactly.**
    ///
    /// This is the seam §5.17 argues every mode boundary needs: Distort has to *contain* the
    /// unmoved case rather than sit beside it, or a piece would jump the instant the picker changed.
    ///
    /// **The load-bearing assertions are the two zeros**, and they are independent facts: `g` and `h`
    /// coming out of `Homography`'s closed form as exact zeros is what makes `affine()` answer at all,
    /// and therefore what keeps `PixelOps.render`'s affine arm reachable. The corner comparison below
    /// is a **round trip** rather than a second opinion — the homography was solved to hit those very
    /// points — so it is asserting that the closed form reproduces its own correspondence, which is
    /// worth pinning and is not the same claim.
    func testAnUndistortedPieceSolvesToItsOwnAffineExactly() throws {
        var p = piece(mode: .uniform)
        p.transform.rotation = 0.4
        p.transform.scaleX = 1.4
        p.transform.scaleY = 0.7
        XCTAssertNil(p.distortQuad, "setup: nothing has been distorted")

        let homography = try XCTUnwrap(p.homography)
        XCTAssertEqual(homography.g, 0, "an unpulled box is a parallelogram, so there is no perspective row")
        XCTAssertEqual(homography.h, 0)
        XCTAssertNotNil(homography.affine(), "and it comes back as a CGAffineTransform, not a warp")

        // The bitmap's texel box onto the canvas, against the same four corners under the affine the
        // piece has always been drawn by.
        let box = CGRect(origin: .zero, size: p.baseSize)
        for (index, corner) in Quad.rect(box).points.enumerated() {
            let throughHomography = try XCTUnwrap(homography.map(corner))
            let throughAffine = p.localQuad[index].applying(p.transform.affineTransform)
            XCTAssertEqual(throughHomography.x, throughAffine.x, accuracy: 1e-9, "corner \(index) x")
            XCTAssertEqual(throughHomography.y, throughAffine.y, accuracy: 1e-9, "corner \(index) y")
        }
    }

    /// A **mirrored** piece reverses the quad's winding, and the solver has to take it — Mirror is a
    /// shipped button on the same bar and an artist can press it before or after a distort.
    ///
    /// Worth its own test because reversed winding is exactly what naive convexity and
    /// positive-weight checks get wrong, and the failure would be a piece that silently refused every
    /// corner drag after one tap of Mirror.
    func testAMirroredPieceStillSolvesAndStillDistorts() throws {
        var p = piece()
        p.transform.flipH = true
        p.transform.rotation = 0.3

        XCTAssertLessThan(p.canvasQuad.signedArea, 0, "setup: the mirror turned the quad over")
        XCTAssertTrue(p.canvasQuad.isConvex, "which is still a convex quad, just wound the other way")
        let homography = try XCTUnwrap(p.homography)
        XCTAssertTrue(homography.weightsAtBoxCorners(p.baseSize).allSatisfy { $0 > 0 },
                      "and every box corner is on the near side of the vanishing line")

        p.distortQuad = trapezoid(p)
        let distorted = try XCTUnwrap(p.homography)
        XCTAssertNotEqual(distorted.g, 0, "a pulled corner on a mirrored piece is still a real homography")
    }

    // MARK: - The preview and the bake are the same map

    /// **The test that matters most: what the finger sees and what the commit writes are one
    /// matrix.**
    ///
    /// The live drag shows the piece under `Homography.catransform3D` — Core Animation, no
    /// rasterization at all, which is LASSO_MOVE.md §4 rule 2 — and the bake warps the bitmap through
    /// the same `Homography` (`PixelOps.render(floatingPiece:into:)` → `ImageWarp.warpedImage`). Both
    /// read `FloatingPiece.homography`, so this asserts the thing that could still be wrong: that
    /// Core Animation's **row-vector** convention and `Homography`'s **column-vector** one have been
    /// reconciled, rather than merely both being present.
    ///
    /// Written the obvious way round, the artwork shears instead of foreshortening — which looks like
    /// a plausible bug in the solver rather than a transposition. Hence the two operands here: the
    /// `CATransform3D` evaluated by hand as Core Animation would, against `Homography.map`.
    ///
    /// MEASURED agreeing at **exactly zero** over the box interior by `tools/distort_seam_ab.swift`,
    /// which compiles the shipped `Quad` and `Homography` unmodified; the accuracy below is slack for
    /// the simulator's own arithmetic, not an admission of drift.
    func testThePreviewMatrixAndTheBakeMatrixAreTheSameMap() throws {
        var p = piece()
        p.transform.rotation = -0.55
        p.transform.scaleX = 1.3
        p.transform.scaleY = 0.9
        p.distortQuad = trapezoid(p)

        let homography = try XCTUnwrap(p.homography)
        XCTAssertNotEqual(homography.g, 0, "setup: the pull really is projective, so the divide is live")
        let layerMatrix = homography.catransform3D

        var worst: CGFloat = 0
        for u in stride(from: CGFloat(0), through: 1, by: 0.125) {
            for v in stride(from: CGFloat(0), through: 1, by: 0.125) {
                let source = CGPoint(x: u * p.baseSize.width, y: v * p.baseSize.height)
                let preview = try XCTUnwrap(coreAnimationMap(layerMatrix, source))
                let bake = try XCTUnwrap(homography.map(source))
                worst = max(worst, hypot(preview.x - bake.x, preview.y - bake.y))
            }
        }
        XCTAssertLessThan(worst, 1e-9,
                          "the CATransform3D the drag is shown under is the matrix the bake warps through")

        // And both land on the corners the artist actually dragged, which is the third operand: the
        // quad is what the outline and the handles are drawn from.
        let quad = p.canvasQuad
        for (index, corner) in Quad.rect(CGRect(origin: .zero, size: p.baseSize)).points.enumerated() {
            let landed = try XCTUnwrap(coreAnimationMap(layerMatrix, corner))
            XCTAssertEqual(landed.x, quad[index].x, accuracy: 1e-9, "corner \(index) x")
            XCTAssertEqual(landed.y, quad[index].y, accuracy: 1e-9, "corner \(index) y")
        }
    }

    /// **The bake really warps, and an affine could not have produced what it wrote.**
    ///
    /// The mutation this file was watched failing under: `PixelOps.render(floatingPiece:into:)`'s
    /// distort arm deleted, so the commit falls through to `concatenate(affineTransform)` and draws
    /// the plain rectangle. Both bands then measure the full 32 px and the assertion below fails with
    /// *the warp foreshortened the top edge — top 32 px, bottom 32 px*. Nothing else in the suite
    /// catches it: every geometric claim above is about matrices, and matrices are still right when
    /// the renderer ignores them.
    ///
    /// The two operands are two rows of the **baked canvas image**, four rows in from each edge of a
    /// 16 pt tall piece sitting at the canvas centre — both comfortably inside the quad, so what
    /// separates them is the map and not the clipping.
    func testTheBakedPixelsAreForeshortenedInAWayNoAffineCouldBe() throws {
        var p = piece()
        p.distortQuad = trapezoid(p)

        let baked = PixelOps.render(floatingPiece: p, into: Self.canvas)
        // The piece is 16 pt tall centred at y = 32, so it spans rows 24..40.
        let top = opaqueRun(baked, row: 27)
        let bottom = opaqueRun(baked, row: 37)
        XCTAssertGreaterThan(bottom, 24, "the untouched bottom edge is the piece's full width")
        XCTAssertLessThan(top, bottom - 6,
                          "the warp foreshortened the top edge — top \(top) px, bottom \(bottom) px")
    }

    /// **The bake put the ink where the matrix said it would**, probed point by point rather than by
    /// counting.
    ///
    /// A coverage count can be right for the wrong reason — a piece drawn in the wrong place with the
    /// right silhouette passes it. This maps the bitmap's own corners and centre through
    /// `FloatingPiece.homography` and asks the baked canvas whether there is ink there, and asks a
    /// point just outside the quad whether there is not.
    func testTheBakeLandsWhereTheHomographySaysAndNowhereElse() throws {
        var p = piece()
        p.distortQuad = trapezoid(p)
        let homography = try XCTUnwrap(p.homography)
        let baked = PixelOps.render(floatingPiece: p, into: Self.canvas)

        // Inside: the box's centre and the four points a quarter of the way in from each corner,
        // which stay clear of the bilinear skirt at the edge.
        for u in [CGFloat(0.25), 0.5, 0.75] {
            for v in [CGFloat(0.25), 0.5, 0.75] {
                let landed = try XCTUnwrap(homography.map(CGPoint(x: u * p.baseSize.width,
                                                                  y: v * p.baseSize.height)))
                XCTAssertGreaterThan(alpha(baked, x: Int(landed.x), y: Int(landed.y)), 200,
                                     "the warp should have covered (\(u), \(v)) → \(landed)")
            }
        }
        // Outside: the corner the pull vacated. Local (-16, -8) is the box's top-left, which the
        // trapezoid moved to (-8, -8); canvas (32 - 15, 32 - 7) is inside the old rectangle and
        // outside the new quad.
        XCTAssertLessThan(alpha(baked, x: 17, y: 25), 40,
                          "and left the corner the pull took away bare")
    }

    // MARK: - The drag

    /// **One corner moves, three do not** — `TextFrameDrag.distortedFrame`'s rule, and the whole of
    /// what "distort" means as against "stretch".
    func testACornerDragMovesExactlyOneCornerAndLeavesTheOtherThreeAlone() throws {
        let p = piece()
        let drag = try XCTUnwrap(FloatingDistortDrag(piece: p, corner: 1))
        let before = p.localQuad

        let moved = try XCTUnwrap(drag.quad(draggedTo: CGPoint(x: 40, y: 26)))
        XCTAssertNotEqual(moved.p1, before.p1, "the grabbed corner went where the finger is")
        XCTAssertEqual(moved.p1, CGPoint(x: 40 - 32, y: 26 - 32), "in the piece's own local space")
        XCTAssertEqual(moved.p0, before.p0)
        XCTAssertEqual(moved.p2, before.p2)
        XCTAssertEqual(moved.p3, before.p3)
    }

    /// **Pure: sixty deltas and one land in the same place.**
    ///
    /// `ObjectTransformDrag`'s property, restated for this gesture, and it is what a latched drag
    /// buys — a reference frame recomputed per delta would let a mid-drag pinch move the thing the
    /// finger is measured against.
    func testTheDragIsAFunctionOfItsFinalPointAlone() throws {
        let p = piece()
        let target = CGPoint(x: 12, y: 20)

        let once = try XCTUnwrap(FloatingDistortDrag(piece: p, corner: 0)?.quad(draggedTo: target))
        let drag = try XCTUnwrap(FloatingDistortDrag(piece: p, corner: 0))
        var last: Quad?
        for step in 1...60 {
            let t = CGFloat(step) / 60
            last = drag.quad(draggedTo: CGPoint(x: 16 + (target.x - 16) * t, y: 24 + (target.y - 24) * t))
        }
        XCTAssertEqual(try XCTUnwrap(last), once)
    }

    /// **A drag that would make an undrawable quad is refused, not clamped** — the handle sticks.
    ///
    /// Three shapes, and the middle one is why `Quad.isSimple` is checked separately from
    /// `isConvex`: dragging a corner across the diagonal produces a **bowtie**, which is what an
    /// artist actually does when they overshoot.
    ///
    /// **The mutation this test was watched failing under**: `FloatingDistortDrag.quad(draggedTo:)`'s
    /// `guard Homography.isValidQuad(...)` line deleted. All three cases then come back non-nil —
    /// *a bowtie is not a quad a homography can be drawn through* — and the drag hands the renderer a
    /// map whose weight changes sign inside the box, which is `ImageWarp`'s own "silent visual
    /// garbage rather than a crash".
    func testADragThatWouldMakeAnUndrawableQuadIsRefused() throws {
        let p = piece()
        let drag = try XCTUnwrap(FloatingDistortDrag(piece: p, corner: 0))

        XCTAssertNotNil(drag.quad(draggedTo: CGPoint(x: 26, y: 26)), "setup: a modest pull is fine")
        // Local (0, 0) is the box's centre — top-left dragged onto the diagonal collapses the quad.
        XCTAssertNil(drag.quad(draggedTo: CGPoint(x: 32, y: 32)),
                     "a corner dragged onto the centre leaves three collinear corners")
        // Past the opposite corner: p0 ends up beyond p2, which crosses edge p0→p1 over p2→p3.
        XCTAssertNil(drag.quad(draggedTo: CGPoint(x: 60, y: 48)),
                     "a bowtie is not a quad a homography can be drawn through")
        // Onto its own neighbour: zero-length edge, zero area.
        XCTAssertNil(drag.quad(draggedTo: CGPoint(x: 48, y: 24)),
                     "and neither is a quad with two corners in the same place")
    }

    /// **The same finger position produces the same *shape* whatever pose the piece is in** — which
    /// is what working in local space buys, and what makes a distort survive a later rotate or
    /// mirror unchanged.
    ///
    /// The two operands are two `Quad`s in the piece's own local space, from two pieces whose only
    /// difference is the affine: one at rest, one turned 0.7 rad, scaled and mirrored. The canvas
    /// point handed to each is that pose's own image of one local point, so the *finger* is in a
    /// different place both times and the answer must not be.
    func testADistortIsIndependentOfThePoseItWasMadeIn() throws {
        let localTarget = CGPoint(x: -4, y: -12)

        var turned = piece()
        turned.transform.rotation = 0.7
        turned.transform.scaleX = 1.6
        turned.transform.scaleY = 0.8
        turned.transform.flipH = true

        let atRest = try XCTUnwrap(FloatingDistortDrag(piece: piece(), corner: 0))
        let posed = try XCTUnwrap(FloatingDistortDrag(piece: turned, corner: 0))

        let restAnswer = try XCTUnwrap(
            atRest.quad(draggedTo: localTarget.applying(piece().transform.affineTransform)))
        let posedAnswer = try XCTUnwrap(
            posed.quad(draggedTo: localTarget.applying(turned.transform.affineTransform)))

        for index in 0..<4 {
            XCTAssertEqual(restAnswer[index].x, posedAnswer[index].x, accuracy: 1e-9, "corner \(index) x")
            XCTAssertEqual(restAnswer[index].y, posedAnswer[index].y, accuracy: 1e-9, "corner \(index) y")
        }
    }

    /// A degenerate pose has no inverse to measure the finger against, so the drag refuses to exist
    /// rather than producing a quad full of NaN. Same shape as `ObjectTransformDrag`'s centre guard.
    func testADragRefusesToExistOnADegeneratePieceOrACornerThatIsNotOne() {
        var collapsed = piece()
        collapsed.transform.scaleX = 0
        XCTAssertNil(FloatingDistortDrag(piece: collapsed, corner: 0))
        XCTAssertNil(FloatingDistortDrag(piece: piece(), corner: 4))
        XCTAssertNil(FloatingDistortDrag(piece: piece(), corner: -1))
        XCTAssertNil(FloatingDistortDrag(piece: piece(size: CGSize(width: 32, height: 0)), corner: 0))
    }

    // MARK: - What the rest of the bar does to a distorted piece

    /// **Reset gives the corners back as well as the position** — §5.16, "snap it back to where I
    /// picked it up", and a lift is always undistorted.
    ///
    /// The second assertion is the one worth having: Reset must be *pressable* on a piece whose only
    /// change is a pulled corner, or an artist who distorts and changes their mind has no way back
    /// short of undoing the whole Move.
    func testResetPutsBackTheCornersAndIsAvailableForAPulledCornerAlone() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        var p = piece()
        manager.floatingPiece = p
        XCTAssertFalse(manager.canResetFloating, "setup: nothing has been done to it yet")

        p.distortQuad = trapezoid(p)
        manager.floatingPiece = p
        XCTAssertEqual(manager.floatingPiece?.transform, manager.floatingPiece?.liftTransform,
                       "setup: the affine pose is untouched, so the quad is the only difference")
        XCTAssertTrue(manager.canResetFloating, "a pulled corner is something Reset has to put back")

        manager.resetFloating()
        XCTAssertNil(manager.floatingPiece?.distortQuad)
        XCTAssertFalse(manager.canResetFloating)
    }

    /// **Move, rotate and mirror leave a distort alone and compose on top of it**, which is what
    /// putting the quad in *local* space buys: `transform` stays the whole of the affine pose and
    /// none of those three knows the field exists.
    func testTheAffineControlsCarryADistortRatherThanDiscardingIt() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        var p = piece()
        p.distortQuad = trapezoid(p)
        manager.floatingPiece = p
        let shape = try XCTUnwrap(manager.floatingPiece?.distortQuad)

        manager.rotateFloating(eighths: 2)
        XCTAssertEqual(manager.floatingPiece?.distortQuad, shape, "Rotate 90° writes the rotation, not the corners")
        manager.mirrorFloating(horizontal: true)
        XCTAssertEqual(manager.floatingPiece?.distortQuad, shape, "and neither does Mirror")
        manager.updateFloatingPose(transform: FloatingTransform(position: CGPoint(x: 10, y: 12),
                                                                scaleX: 2, scaleY: 2, rotation: 0),
                                   distortQuad: shape)
        XCTAssertEqual(manager.floatingPiece?.distortQuad, shape)

        // And the composition is real: the canvas quad has moved and scaled with the piece while
        // keeping its shape's own signature — a top edge shorter than its bottom one.
        let quad = try XCTUnwrap(manager.floatingPiece?.canvasQuad)
        let topWidth = hypot(quad.p1.x - quad.p0.x, quad.p1.y - quad.p0.y)
        let bottomWidth = hypot(quad.p2.x - quad.p3.x, quad.p2.y - quad.p3.y)
        XCTAssertLessThan(topWidth, bottomWidth - 1, "the shape survived the affine controls")
        XCTAssertEqual(quad.centre.x, 10, accuracy: 1e-9, "and travelled with the position")
    }

    // MARK: - Who Distort is refused for, and why the bar says so

    /// **`TransformMode.isImplemented` is gone, and the caption it drove with it.**
    ///
    /// It said *"Coming soon — acts like Uniform for now"* of every float; what replaces it is a
    /// sentence about the one piece still refused. §5.14's rule is that a reader must be able to tell
    /// "not yet" from "never", and this is that rule applied to a caption: the sentence names what is
    /// missing, and `CanvasManager.distortUnavailableReason`'s doc comment names what would unblock
    /// it (KEYFRAMES.md stage 4's rest-space dab bake).
    func testDistortIsRefusedOnALassoedVectorFloatAndOnNothingElse() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertNil(manager.distortUnavailableReason, "nothing is floating, so there is nothing to refuse")

        manager.setTransformMode(.distort)
        manager.floatingPiece = piece()
        XCTAssertNil(manager.distortUnavailableReason, "a raster piece is exactly what Distort is for")

        manager.floatingPiece = nil
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        let vector = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector)
        vector.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                      size: 4, opacity: 1,
                                      samples: [VectorSample(x: 20, y: 32, pressure: 1),
                                                VectorSample(x: 44, y: 32, pressure: 1)],
                                      composite: .paint))
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "setup: a vector float")

        let reason = try XCTUnwrap(manager.distortUnavailableReason,
                                   "a lassoed drawing cannot be distorted until stroke width can follow a homography")
        XCTAssertFalse(reason.isEmpty)
        manager.setTransformMode(.uniform)
        XCTAssertNil(manager.distortUnavailableReason, "and the caption is about the mode as well as the piece")
    }

    // MARK: - End to end, through the real lift

    /// **The whole gesture through the seams the app drives**: select, `beginMove`, drag a corner,
    /// commit — and the cel ends up holding a foreshortened copy of what was lifted.
    ///
    /// The geometry tests above build a `FloatingPiece` by hand so their operands are exact. This one
    /// does not, because what it is about is the wiring: that `beginMove`'s piece can be dragged by
    /// `FloatingDistortDrag` at all, that `updateFloatingPose` lands the quad on the model, and that
    /// `commitFloatingPieceIfNeeded` reaches the warp rather than the affine draw.
    func testAWholeMoveEndToEndBakesTheDistortedShape() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black,
                                                               rect: CGRect(x: 16, y: 24, width: 32, height: 16)))
        manager.selection = Selection(path: CGPath(rect: CGRect(x: 16, y: 24, width: 32, height: 16),
                                                   transform: nil),
                                      bounds: CGRect(x: 16, y: 24, width: 32, height: 16),
                                      layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id)
        manager.setTransformMode(.distort)
        manager.beginMove()
        let lifted = try XCTUnwrap(manager.floatingPiece)
        XCTAssertNil(lifted.distortQuad, "a lift is never distorted")

        // Drag the top-left corner inward and the top-right corner inward, the way the overlay does.
        for (corner, target) in [(0, CGPoint(x: 24, y: 24)), (1, CGPoint(x: 40, y: 24))] {
            let piece = try XCTUnwrap(manager.floatingPiece)
            let drag = try XCTUnwrap(FloatingDistortDrag(piece: piece, corner: corner))
            let quad = try XCTUnwrap(drag.quad(draggedTo: target))
            manager.updateFloatingPose(transform: piece.transform, distortQuad: quad)
        }
        XCTAssertNotNil(manager.floatingPiece?.distortQuad, "the drags landed on the model")
        XCTAssertTrue(manager.canResetFloating)

        XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
        XCTAssertNil(manager.floatingPiece)

        let flattened = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: Self.canvas)
        let top = opaqueRun(flattened, row: 27)
        let bottom = opaqueRun(flattened, row: 37)
        XCTAssertGreaterThan(bottom, 24, "the untouched bottom edge kept the lifted width")
        XCTAssertLessThan(top, bottom - 6,
                          "and the committed cel holds the foreshortened shape — top \(top) px, bottom \(bottom) px")
    }

    // MARK: - The mixed state: distorted corners under a non-Distort mode

    /// **A corner drag on a distorted piece jumped the instant it began, and this is the moment it
    /// jumped in.**
    ///
    /// `setTransformMode` writes `mode` and leaves `distortQuad` alone — deliberately: Reset is the
    /// only thing that takes a distort back. So "distorted, in Uniform" is a reachable state, the
    /// grips are drawn on `canvasQuad` in every mode, and the anchor used to be latched from
    /// `Quad.rect(localBox)`. The finger was therefore on a corner of the quad while the arithmetic
    /// measured from a corner of the box, and `resizeFromAnchor` re-derived the pose from that
    /// mismatch on the first delta.
    ///
    /// **The assertion is that a drag which has not moved yet changes nothing** — press the grip,
    /// drag it to where it already is, and the piece must be exactly where it was. It is the one
    /// statement about this gesture that is true of every correct implementation and false of the
    /// shipped one, at every mode, corner and pose.
    func testACornerDragOnADistortedPieceInUniformDoesNotJumpAtTouchDown() throws {
        for mode in [TransformMode.uniform, .freeform] {
            for corner in 0..<4 {
                var subject = piece(mode: .distort)
                subject.distortQuad = trapezoid(subject)
                // What the Move bar's picker does: the mode changes, the corners stay.
                subject.mode = mode

                let grip = subject.canvasQuad[corner]
                let drag = try XCTUnwrap(FloatingResizeDrag(piece: subject, corner: corner))
                let unmoved = drag.transform(draggedTo: grip)

                XCTAssertEqual(unmoved.position.x, subject.transform.position.x, accuracy: 0.001,
                               "\(mode) corner \(corner): a drag to the grip's own position is a "
                               + "drag of zero, and must leave the piece where it is")
                XCTAssertEqual(unmoved.position.y, subject.transform.position.y, accuracy: 0.001,
                               "\(mode) corner \(corner): same, in y")
                XCTAssertEqual(unmoved.scaleX, subject.transform.scaleX, accuracy: 0.001,
                               "\(mode) corner \(corner): and must not rescale it")
                XCTAssertEqual(unmoved.scaleY, subject.transform.scaleY, accuracy: 0.001,
                               "\(mode) corner \(corner): same, in y")
            }
        }
    }

    /// And the grip **opposite** the one being dragged stays under the artist's finger-memory of it
    /// — the contract the anchor is named for, stated against the quad the grips are actually drawn
    /// from. A box-corner anchor satisfies this only for an undistorted piece.
    /// **Corner 2 is dragged and corner 0 is the anchor, and that pairing is the whole test.** The
    /// trapezoid moves the two *top* corners, so a drag of corner 0 or 1 is anchored on a corner the
    /// distort left alone and the box answer and the quad answer coincide — green under the defect.
    /// The finger also has to stay on the anchor's own side of it: crossing over is the one case
    /// where this arm deliberately moves the anchor, dropping the piece on the finger's side instead
    /// of mirroring it, exactly as the box arithmetic always did.
    func testTheOppositeGripStaysPutThroughACornerDragOnADistortedPiece() throws {
        var subject = piece(mode: .distort)
        subject.distortQuad = trapezoid(subject, topInset: 12)
        subject.mode = .freeform

        let anchorGrip = subject.canvasQuad[0]
        let drag = try XCTUnwrap(FloatingResizeDrag(piece: subject, corner: 2))
        subject.transform = drag.transform(draggedTo: CGPoint(x: 56, y: 52))

        let moved = subject.canvasQuad[0]
        XCTAssertEqual(moved.x, anchorGrip.x, accuracy: 0.001, "the anchored corner does not travel")
        XCTAssertEqual(moved.y, anchorGrip.y, accuracy: 0.001, "the anchored corner does not travel")
    }

    /// **The generalisation costs the undistorted piece nothing, and this is the proof rather than
    /// the claim.** `FloatingResizeDrag` measures against `movingLocal - anchorLocal`; for a piece
    /// with no `distortQuad` that span is `±baseWidth`/`±baseHeight`, so the whole expression has to
    /// reduce to the box arithmetic it replaced — including the crossover case, where the finger
    /// passes the anchor and the piece changes side without mirroring.
    ///
    /// The old expression is written out here rather than called, for
    /// `coreAnimationMap`'s reason: checking a formula against itself proves nothing.
    func testAnUndistortedResizeIsTheBoxArithmeticItReplaced() throws {
        let poses: [FloatingTransform] = [
            FloatingTransform(position: CGPoint(x: 32, y: 32), scaleX: 1, scaleY: 1, rotation: 0),
            FloatingTransform(position: CGPoint(x: 20, y: 44), scaleX: 1.7, scaleY: 0.6, rotation: 0.9),
            FloatingTransform(position: CGPoint(x: 40, y: 18), scaleX: 0.8, scaleY: 2.2,
                              rotation: -2.1, flipH: true, flipV: true),
        ]
        // Two of these land on the far side of the anchor, which is the crossover arm.
        let targets = [CGPoint(x: 4, y: 6), CGPoint(x: 60, y: 58), CGPoint(x: 33, y: 31),
                       CGPoint(x: -12, y: 70)]

        for pose in poses {
            for mode in [TransformMode.uniform, .freeform] {
                for corner in 0..<4 {
                    var subject = piece(mode: mode)
                    subject.transform = pose
                    let drag = try XCTUnwrap(FloatingResizeDrag(piece: subject, corner: corner))
                    for target in targets {
                        let now = drag.transform(draggedTo: target)
                        let then = Self.boxResize(subject, corner: corner, to: target)
                        XCTAssertEqual(now.scaleX, then.scaleX, accuracy: 1e-9)
                        XCTAssertEqual(now.scaleY, then.scaleY, accuracy: 1e-9)
                        XCTAssertEqual(now.position.x, then.position.x, accuracy: 1e-9)
                        XCTAssertEqual(now.position.y, then.position.y, accuracy: 1e-9)
                    }
                }
            }
        }
    }

    /// `FloatingPieceOverlayView.resizeFromAnchor` as it stood before `FloatingResizeDrag`, box
    /// anchor and all — the operand `testAnUndistortedResizeIsTheBoxArithmeticItReplaced` compares
    /// against. Correct for an undistorted piece, which is the only kind it is asked about here.
    private static func boxResize(_ piece: FloatingPiece, corner: Int, to current: CGPoint)
        -> FloatingTransform {
        let start = piece.transform
        let anchor = Quad.rect(piece.localBox)[(corner + 2) % 4].applying(start.affineTransform)
        let r = start.rotation
        let dx = current.x - anchor.x, dy = current.y - anchor.y
        let localW = dx * cos(-r) - dy * sin(-r)
        let localH = dx * sin(-r) + dy * cos(-r)
        let baseW = max(piece.baseSize.width, 1), baseH = max(piece.baseSize.height, 1)
        var updated = start
        var scaleX = max(abs(localW) / baseW, 0.02)
        var scaleY = max(abs(localH) / baseH, 0.02)
        if piece.mode != .freeform {
            let s = max(scaleX, scaleY)
            scaleX = s; scaleY = s
        }
        updated.scaleX = scaleX
        updated.scaleY = scaleY
        let localHalfW = (localW >= 0 ? 1 : -1) * scaleX * baseW / 2
        let localHalfH = (localH >= 0 ? 1 : -1) * scaleY * baseH / 2
        updated.position = CGPoint(x: anchor.x + localHalfW * cos(r) - localHalfH * sin(r),
                                   y: anchor.y + localHalfW * sin(r) + localHalfH * cos(r))
        return updated
    }

    // MARK: - The marching ants

    /// **The ants were handed a `CGAffineTransform`, which cannot express a four-corner warp at
    /// all.** `rasterFloatAntsTransform` composed the lift's inverse with the current pose and never
    /// read `distortQuad`, so a distorted piece showed the artist the overlay's correctly
    /// foreshortened dashes and an un-warped rectangle of ants over the same ink at once.
    ///
    /// Asserted where it can go wrong rather than by asking for the `.warped` label: the map has to
    /// carry each corner of the **lifted** box onto the corresponding corner of `canvasQuad`, which
    /// is the one thing the affine could not do.
    func testTheAntsMapOfADistortedPieceCarriesTheLiftBoxOntoTheDistortedQuad() throws {
        var subject = piece()
        subject.distortQuad = trapezoid(subject)

        guard case .warped(let map) = subject.antsMap else {
            return XCTFail("A distorted piece's ants map is projective; an affine cannot hold it")
        }
        XCTAssertNil(map.affine(), "and it is genuinely projective, not an affine wearing the case")

        let lifted = Quad.rect(subject.localBox).mapped(by: subject.liftTransform.affineTransform)
        for corner in 0..<4 {
            let landed = try XCTUnwrap(map.map(lifted[corner]))
            XCTAssertEqual(landed.x, subject.canvasQuad[corner].x, accuracy: 1e-6,
                           "corner \(corner) of the lifted outline lands on corner \(corner) of the quad")
            XCTAssertEqual(landed.y, subject.canvasQuad[corner].y, accuracy: 1e-6,
                           "corner \(corner), in y")
        }
    }

    /// **A piece nobody has distorted keeps the exact affine, and "exact" is load-bearing.**
    /// `setLiveSelectionTransform` decides whether to show the exterior hatch by asking whether the
    /// map `isIdentity`, so a piece resting at its lift has to produce the identity to the bit — the
    /// projective composition agrees to about 1e-13, which would hide the hatch forever.
    func testAnUndistortedPieceAtItsLiftGivesTheExactIdentity() {
        let subject = piece(mode: .uniform)
        guard case .affine(let map) = subject.antsMap else {
            return XCTFail("An undistorted piece's ants map has to stay affine")
        }
        XCTAssertTrue(map.isIdentity,
                      "and exactly the identity at the lift, or the exterior hatch never comes back")
    }

    /// The ants path itself, through the same map — the step `CALayer` cannot take for a zero-bounds
    /// shape layer, and the reason `Homography.mapped` exists.
    func testTheAntsPathIsCarriedThroughTheWarp() throws {
        var subject = piece()
        subject.distortQuad = trapezoid(subject)
        guard case .warped(let map) = subject.antsMap else { return XCTFail("projective") }

        let lifted = Quad.rect(subject.localBox).mapped(by: subject.liftTransform.affineTransform)
        let outline = CGMutablePath()
        outline.addLines(between: lifted.points)
        outline.closeSubpath()

        let warped = try XCTUnwrap(map.mapped(outline))
        var points: [CGPoint] = []
        warped.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
            default: break
            }
        }
        // **Corner by corner, not by bounding box.** A trapezoid inset symmetrically has the same
        // bounding box as the rectangle it came from, so a box comparison here would be green under
        // the identity — the exact shape of fixture that measures nothing.
        XCTAssertEqual(points.count, 4, "four corners, and the close is not one of them")
        for (index, point) in points.enumerated() {
            XCTAssertEqual(point.x, subject.canvasQuad[index].x, accuracy: 1e-6,
                           "outline corner \(index) lands on quad corner \(index)")
            XCTAssertEqual(point.y, subject.canvasQuad[index].y, accuracy: 1e-6,
                           "outline corner \(index), in y")
        }
        XCTAssertNotEqual(points[0].x, lifted.p0.x, accuracy: 1e-6,
                          "and the path really moved — the source outline is the plain lifted box")
    }
}
