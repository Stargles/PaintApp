import UIKit
import XCTest

/// `ADD_TEXT.md` stage 4 — rotate, independent-axis scale, and handles that are the right size —
/// asserted headlessly.
///
/// **Identities and invariants, never measured glyph widths.** `TextLayoutLogicTests` states the
/// reason and it applies with more force here: "this string is 412.5 points wide" is a claim about a
/// font file Apple revises, not about this code. So the assertions below are of the form *the
/// opposite corner did not move*, *the centre did not move*, *the rotation survived*, *sixty deltas
/// and one delta agree* — each of which is false for a plausible wrong implementation and true for
/// any correct one, whatever the metrics happen to be.
///
/// The geometry under test lives on `TextFrame` and `TextFrameDrag` rather than inside
/// `TextTransformOverlayView`, which is the only reason it is reachable from here.
/// `ShapeOverlayView`'s header records why that split exists: the corner-drag arithmetic used to be
/// written out inline in `CanvasView`'s callbacks, "where nothing could unit-test it".
final class TextTransformLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 200, height: 200)
    /// Loose enough for the accumulated trig of a rotate-then-resize, tight enough that a genuinely
    /// moved corner cannot hide under it — the boxes here are ~100 points across.
    private static let epsilon: CGFloat = 1e-6

    // MARK: - Fixtures

    private func recipe(_ string: String = "Label", pointSize: CGFloat = 24) -> TextRecipe {
        TextRecipe(string: string, font: .system, typography: Typography(pointSize: pointSize))
    }

    /// An axis-aligned box centred on the canvas.
    private func upright(size: CGSize = CGSize(width: 100, height: 40),
                         centre: CGPoint = CGPoint(x: 100, y: 100),
                         autoSize: Bool = false) -> TextFrame {
        TextFrame(origin: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2),
                  size: size, autoSize: autoSize)
    }

    /// `frame` turned by `angle` about its own centre — the fixture every "on a rotated box"
    /// assertion below starts from. Built by rotating the corners directly rather than through
    /// `TextFrameDrag`, so a test of the drag cannot be satisfied by the drag's own bug.
    private func turned(_ frame: TextFrame, by angle: CGFloat) -> TextFrame {
        let c = frame.centre
        let cosA = cos(angle), sinA = sin(angle)
        var turned = frame
        turned.corners = frame.corners.map { corner in
            let dx = corner.x - c.x, dy = corner.y - c.y
            return CGPoint(x: c.x + dx * cosA - dy * sinA, y: c.y + dx * sinA + dy * cosA)
        }
        return turned
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint,
                             accuracy: CGFloat = TextTransformLogicTests.epsilon,
                             _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, message, file: file, line: line)
    }

    /// The canvas point `local` (in the box's own coordinates) maps to, using the frame's basis.
    private func canvasPoint(_ frame: TextFrame, _ local: CGPoint) throws -> CGPoint {
        let basis = try XCTUnwrap(frame.basis)
        return CGPoint(x: basis.origin.x + basis.u.dx * local.x + basis.v.dx * local.y,
                       y: basis.origin.y + basis.u.dy * local.x + basis.v.dy * local.y)
    }

    // MARK: - Anchor-preserving resize, on a rotated box

    /// **The assertion stage 4 exists for.** A resize written against the frame's *bounding
    /// rectangle* — the obvious wrong implementation, and the one every earlier stage's code was
    /// shaped like — passes every upright case and walks the far corner across the canvas the moment
    /// the box is turned. So the box here is turned, at an angle that is not a multiple of 90°, and
    /// the claim is the one the artist would notice: the corner you are not holding does not move.
    func testResizingARotatedBoxHoldsTheOppositeCornerStill() throws {
        let start = turned(upright(), by: .pi / 6)
        let anchorBefore = start[.bottomRight]

        for handle in [TextFrame.Handle.topLeft, .top, .left] {
            let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: handle))
            for target in [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 150), CGPoint(x: 190, y: 30)] {
                let resized = drag.frame(draggedTo: target)
                assertPoint(resized[.bottomRight], anchorBefore,
                            "Dragging \(handle) must not move the corner diagonally opposite it.")
            }
        }
    }

    /// Dragging a *corner* puts that corner under the finger — the identity that says the drag is
    /// solving the right problem and not merely holding something else still.
    ///
    /// Stated only for targets that keep both extents above the minimum, because the clamp is
    /// deliberately allowed to break it; `testAResizeClampsAtTheMinimumRatherThanFlippingTheBox`
    /// covers the other side.
    func testACornerDragPutsThatCornerUnderTheFinger() throws {
        let start = turned(upright(), by: .pi / 6)
        let corners: [(TextFrame.Handle, TextFrame.Corner)] = [
            (.topLeft, .topLeft), (.topRight, .topRight),
            (.bottomRight, .bottomRight), (.bottomLeft, .bottomLeft)
        ]
        for (handle, corner) in corners {
            let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: handle))
            // Reached by walking out from the anchor along the box's own axes, so the target is
            // guaranteed to be on the far side of it and well clear of the minimum.
            let basis = try XCTUnwrap(start.basis)
            let sx: CGFloat = (handle == .topRight || handle == .bottomRight) ? 1 : -1
            let sy: CGFloat = (handle == .bottomLeft || handle == .bottomRight) ? 1 : -1
            let target = CGPoint(x: drag.anchor.x + basis.u.dx * 70 * sx + basis.v.dx * 55 * sy,
                                 y: drag.anchor.y + basis.u.dy * 70 * sx + basis.v.dy * 55 * sy)
            let resized = drag.frame(draggedTo: target)
            assertPoint(resized[corner], target, "\(handle) should follow the finger exactly.")
            XCTAssertEqual(resized.size.width, 70, accuracy: Self.epsilon)
            XCTAssertEqual(resized.size.height, 55, accuracy: Self.epsilon)
        }
    }

    /// A resize is a resize, not a re-orientation: the box's axes come out of the drag pointing where
    /// they went in. Without this, `resized(to:)`'s old `uprightCorners` rebuild would pass every
    /// "opposite corner" test above and still snap the box straight.
    func testResizingPreservesTheBoxesRotation() throws {
        let angle = CGFloat.pi / 6
        let start = turned(upright(), by: angle)
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .bottomRight))
        let resized = drag.frame(draggedTo: CGPoint(x: 180, y: 170))
        XCTAssertEqual(resized.rotation, angle, accuracy: 1e-9)
    }

    /// **Independent-axis scale**, which is what the eight sizing grips buy over four. An edge grip
    /// moves one extent and freezes the other — for type that is the common ask, since "set the wrap
    /// width and leave the height alone" is not expressible with corners only.
    func testAnEdgeHandleSizesOneAxisAndFreezesTheOther() throws {
        let start = turned(upright(), by: .pi / 5)
        let basis = try XCTUnwrap(start.basis)

        let widthDrag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .right))
        let widened = widthDrag.frame(draggedTo: CGPoint(x: widthDrag.anchor.x + basis.u.dx * 160,
                                                         y: widthDrag.anchor.y + basis.u.dy * 160))
        XCTAssertEqual(widened.size.width, 160, accuracy: Self.epsilon)
        XCTAssertEqual(widened.size.height, start.size.height, accuracy: Self.epsilon,
                       "An edge grip freezes the axis it is not on.")

        let heightDrag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .bottom))
        let taller = heightDrag.frame(draggedTo: CGPoint(x: heightDrag.anchor.x + basis.v.dx * 90,
                                                         y: heightDrag.anchor.y + basis.v.dy * 90))
        XCTAssertEqual(taller.size.height, 90, accuracy: Self.epsilon)
        XCTAssertEqual(taller.size.width, start.size.width, accuracy: Self.epsilon)
    }

    /// Dragging a grip past its own anchor and out the other side clamps at the minimum instead of
    /// mirroring the box. Text that reads backwards is never what the artist meant by overshooting,
    /// and a negative extent is the shape of a NaN a few frames later.
    func testAResizeClampsAtTheMinimumRatherThanFlippingTheBox() throws {
        let angle = CGFloat.pi / 6
        let start = turned(upright(), by: angle)
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .topLeft))
        let basis = try XCTUnwrap(start.basis)
        // 50 points *beyond* the anchor along both of the box's own axes.
        let overshoot = CGPoint(x: drag.anchor.x + basis.u.dx * 50 + basis.v.dx * 50,
                                y: drag.anchor.y + basis.u.dy * 50 + basis.v.dy * 50)
        let clamped = drag.frame(draggedTo: overshoot)
        XCTAssertEqual(clamped.size.width, TextFrame.minimumExtent, accuracy: Self.epsilon)
        XCTAssertEqual(clamped.size.height, TextFrame.minimumExtent, accuracy: Self.epsilon)
        XCTAssertEqual(clamped.rotation, angle, accuracy: 1e-9,
                       "Clamped, not mirrored — a flip would show up here as a half-turn.")
        assertPoint(clamped[.bottomRight], drag.anchor,
                    "Even clamped, the anchor is still the anchor.")
    }

    // MARK: - Rotation about the box centre

    func testRotationTurnsTheBoxAboutItsOwnCentre() throws {
        let start = upright()
        let centreBefore = start.centre
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .rotation))

        // Straight right of the centre. The knob stands off the *top* edge, so "the knob is to the
        // right" is a quarter turn clockwise — the `+ π/2` in `TextFrameDrag.rotated`.
        let turned = drag.frame(draggedTo: CGPoint(x: centreBefore.x + 100, y: centreBefore.y))
        assertPoint(turned.centre, centreBefore, "A rotation pivots; it does not travel.")
        XCTAssertEqual(turned.rotation, .pi / 2, accuracy: 1e-9)

        let basis = try XCTUnwrap(turned.basis)
        XCTAssertEqual(basis.width, start.size.width, accuracy: Self.epsilon,
                       "A rotation is not a resize.")
        XCTAssertEqual(basis.height, start.size.height, accuracy: Self.epsilon)
        XCTAssertEqual(turned.size, start.size)
    }

    /// Dragging the knob back to straight up returns the box to where it started, corner for corner.
    /// A rotation that is not invertible is a rotation that is quietly accumulating something.
    func testRotatingBackToUprightRestoresTheOriginalQuad() throws {
        let start = upright()
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .rotation))
        let straightUp = CGPoint(x: start.centre.x, y: start.centre.y - 100)
        let restored = drag.frame(draggedTo: straightUp)
        for corner in TextFrame.Corner.allCases {
            assertPoint(restored[corner], start[corner], accuracy: 1e-9)
        }
    }

    /// **Rotation does not clear `autoSize`, and resizing does.** Stage 4's sketch says "the first
    /// handle drag" sets the bit, but turning a box is not sizing it: a pristine box that has been
    /// tilted still has to go on growing as the artist types, or the first character after the tilt
    /// is clipped by a 24-point box for a reason nobody could name.
    func testRotationLeavesAutoSizeAloneWhileAResizeClearsIt() throws {
        let pristine = upright(autoSize: true)
        let rotation = try XCTUnwrap(TextFrameDrag(frame: pristine, handle: .rotation))
        XCTAssertTrue(rotation.frame(draggedTo: CGPoint(x: 180, y: 100)).autoSize)

        for handle in TextFrame.Handle.allCases where handle.isResize {
            let drag = try XCTUnwrap(TextFrameDrag(frame: pristine, handle: handle))
            XCTAssertFalse(drag.frame(draggedTo: CGPoint(x: 170, y: 160)).autoSize,
                           "\(handle) is a resize, and a box you sized wraps (ADD_TEXT.md §1).")
        }
    }

    // MARK: - The latch

    /// The frame a drag produces is a function of the **latched** quad and the current point, and of
    /// nothing else — so sixty deltas along a path and one delta straight to its end agree exactly.
    ///
    /// This is what stops a long drag accumulating rounding, and it is the half of ADD_TEXT.md §1's
    /// latch rule that can be stated without a second finger.
    func testSixtyDeltasAndOneDeltaAgree() throws {
        let start = turned(upright(), by: .pi / 7)
        let target = CGPoint(x: 25, y: 175)
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .topLeft))

        let straight = drag.frame(draggedTo: target)
        var walked = start
        let from = start[.topLeft]
        for step in 1...60 {
            let t = CGFloat(step) / 60
            walked = drag.frame(draggedTo: CGPoint(x: from.x + (target.x - from.x) * t,
                                                   y: from.y + (target.y - from.y) * t))
        }
        for corner in TextFrame.Corner.allCases {
            assertPoint(walked[corner], straight[corner], accuracy: 1e-9)
        }
    }

    /// The other half, through the model: something that changes the frame **mid-drag** does not
    /// move the reference the drag is measured against.
    ///
    /// The mid-drag event here is a keystroke, because a pristine box regrows on one and that regrow
    /// rewrites `size` and `corners` — the exact hazard ADD_TEXT.md §1 describes for a pinch. A drag
    /// that re-read the live frame each delta would come out of this with the *regrown* extents.
    /// They come back on lift, where `endTextHandleDrag` re-runs the measurement.
    func testAMidDragChangeToTheFrameDoesNotMoveTheReference() throws {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 20, y: 20))
        manager.updateTextString("Hi")
        let latched = manager.textFrame
        XCTAssertTrue(latched.autoSize, "Fixture check — only a pristine box regrows on a keystroke.")

        manager.beginTextHandleDrag(.rotation)
        manager.dragTextHandle(to: CGPoint(x: 150, y: 40))

        let longer = String(repeating: "much longer ", count: 6)
        manager.updateTextString(longer)
        let regrown = manager.textFrame.size
        XCTAssertGreaterThan(regrown.width, latched.size.width,
                             "Fixture check — the keystroke really did resize the box mid-drag.")

        manager.dragTextHandle(to: CGPoint(x: 150, y: 60))
        XCTAssertEqual(manager.textFrame.size.width, latched.size.width, accuracy: Self.epsilon,
                       "The drag is measured against the quad latched at touch-down, not the live one.")

        manager.endTextHandleDrag()
        XCTAssertEqual(manager.textFrame.size.width, regrown.width, accuracy: 0.5,
                       "And the measurement catches up on lift, so nothing typed is lost.")
    }

    // MARK: - Handle geometry

    /// Every grip sits on the transformed quad — corners on corners, edge grips on edge midpoints —
    /// and the rotation knob stands off the top edge along the box's **own** up direction, so it
    /// stays over the top of the text at any angle instead of swinging into the artwork.
    func testHandleLayoutSitsOnTheTransformedCorners() throws {
        let frame = turned(upright(), by: .pi / 3)
        let offset: CGFloat = 20
        let layout = Dictionary(uniqueKeysWithValues: frame.handleLayout(rotationOffset: offset)
            .map { ($0.handle, $0.position) })
        XCTAssertEqual(layout.count, TextFrame.Handle.allCases.count)

        assertPoint(try XCTUnwrap(layout[.topLeft]), frame[.topLeft])
        assertPoint(try XCTUnwrap(layout[.topRight]), frame[.topRight])
        assertPoint(try XCTUnwrap(layout[.bottomRight]), frame[.bottomRight])
        assertPoint(try XCTUnwrap(layout[.bottomLeft]), frame[.bottomLeft])

        let basis = try XCTUnwrap(frame.basis)
        assertPoint(try XCTUnwrap(layout[.top]), try canvasPoint(frame, CGPoint(x: basis.width / 2, y: 0)))
        assertPoint(try XCTUnwrap(layout[.bottom]),
                    try canvasPoint(frame, CGPoint(x: basis.width / 2, y: basis.height)))
        assertPoint(try XCTUnwrap(layout[.left]), try canvasPoint(frame, CGPoint(x: 0, y: basis.height / 2)))
        assertPoint(try XCTUnwrap(layout[.right]),
                    try canvasPoint(frame, CGPoint(x: basis.width, y: basis.height / 2)))

        let topMid = try XCTUnwrap(layout[.top])
        let knob = try XCTUnwrap(layout[.rotation])
        assertPoint(knob, CGPoint(x: topMid.x - basis.v.dx * offset, y: topMid.y - basis.v.dy * offset),
                    "The knob stands off along the box's own -y, not the canvas's.")
    }

    /// The anchor a drag holds still is the point diametrically opposite the grip — including for the
    /// edge grips, where "opposite corner" is not the whole answer.
    func testEveryHandlesAnchorIsThePointOppositeIt() throws {
        let frame = turned(upright(), by: .pi / 4)
        let opposite: [TextFrame.Handle: TextFrame.Handle] = [
            .topLeft: .bottomRight, .topRight: .bottomLeft,
            .bottomRight: .topLeft, .bottomLeft: .topRight,
            .top: .bottom, .bottom: .top, .left: .right, .right: .left
        ]
        let layout = Dictionary(uniqueKeysWithValues: frame.handleLayout(rotationOffset: 20)
            .map { ($0.handle, $0.position) })
        for (handle, other) in opposite {
            assertPoint(try XCTUnwrap(frame.anchor(for: handle)), try XCTUnwrap(layout[other]),
                        "\(handle)'s anchor is \(other).")
        }
        assertPoint(try XCTUnwrap(frame.anchor(for: .rotation)), frame.centre,
                    "The knob pivots about the centre, which does not move either.")
    }

    /// **Nearest-within-reach, not first-match.** On a box smaller than the 44 pt target a corner and
    /// both of its neighbouring edge grips are all inside reach at once; first-match would return
    /// whichever the layout happened to list first and cost the box most of its handles.
    ///
    /// The discriminating point is a hair off the *top* grip on a 20-point box: `.topLeft` is listed
    /// first and is comfortably within reach, so a first-match search returns it and this fails.
    func testHitTestingPicksTheNearestHandleWhenTwoOverlap() throws {
        let small = upright(size: CGSize(width: 20, height: 20), centre: CGPoint(x: 110, y: 110))
        let reach: CGFloat = 22          // the 44 pt HIG target at 1× canvas scale

        let layout = Dictionary(uniqueKeysWithValues: small.handleLayout(rotationOffset: 30)
            .map { ($0.handle, $0.position) })
        let topMid = try XCTUnwrap(layout[.top])
        XCTAssertLessThanOrEqual(hypot(topMid.x - small[.topLeft].x, topMid.y - small[.topLeft].y), reach,
                                 "Fixture check — the two targets really do overlap, or the test proves nothing.")

        XCTAssertEqual(small.handle(nearest: CGPoint(x: topMid.x + 0.5, y: topMid.y),
                                    reach: reach, rotationOffset: 30), .top)
        XCTAssertEqual(small.handle(nearest: CGPoint(x: small[.topLeft].x - 0.5, y: small[.topLeft].y),
                                    reach: reach, rotationOffset: 30), .topLeft)
        XCTAssertEqual(small.handle(nearest: try XCTUnwrap(layout[.rotation]),
                                    reach: reach, rotationOffset: 30), .rotation,
                       "The knob is reachable too, standing off well clear of the eight.")
    }

    func testHitTestingIgnoresAnythingOutOfReach() {
        let frame = upright()
        XCTAssertNil(frame.handle(nearest: CGPoint(x: 100, y: 100), reach: 10, rotationOffset: 30),
                     "The middle of a 100×40 box is not within 10 points of any of its grips.")
        XCTAssertNil(frame.handle(nearest: CGPoint(x: 400, y: 400), reach: 22, rotationOffset: 30))
    }

    /// A zero stand-off omits the knob rather than stacking it on the `.top` grip, which is what the
    /// overlay would otherwise do at a scale where the offset rounds away.
    func testAZeroStandOffOmitsTheRotationKnob() {
        let layout = upright().handleLayout(rotationOffset: 0)
        XCTAssertEqual(layout.count, 8)
        XCTAssertFalse(layout.contains { $0.handle == .rotation })
    }

    // MARK: - The frame as a map

    /// `affineTransform` is the map from the layout box's own coordinates onto the quad — the affine
    /// half of ADD_TEXT.md §1's homography, and the matrix all three drawing paths concatenate.
    func testTheAffineTransformMapsTheLayoutBoxOntoTheQuad() throws {
        let frame = turned(upright(), by: .pi / 6)
        let t = try XCTUnwrap(frame.affineTransform)
        let w = frame.size.width, h = frame.size.height
        assertPoint(CGPoint(x: 0, y: 0).applying(t), frame[.topLeft])
        assertPoint(CGPoint(x: w, y: 0).applying(t), frame[.topRight])
        assertPoint(CGPoint(x: w, y: h).applying(t), frame[.bottomRight])
        assertPoint(CGPoint(x: 0, y: h).applying(t), frame[.bottomLeft])
    }

    /// For an upright frame it is exactly the translate stages 1-3 wrote by hand, which is why
    /// generalising the three drawing paths onto it changed no pixel any of them already produced.
    func testTheAffineTransformOfAnUprightFrameIsATranslate() throws {
        let frame = upright()
        let t = try XCTUnwrap(frame.affineTransform)
        XCTAssertEqual(t, CGAffineTransform(translationX: frame[.topLeft].x, y: frame[.topLeft].y))
    }

    /// A quad no affine map covers answers nil rather than approximating one. That is what keeps
    /// stage 5's `.projective` an additive case instead of a silent wrong answer: the drawing paths
    /// fall back to the bounding box and say so, and stage 5 replaces *that* branch.
    func testANonParallelogramHasNoAffineTransform() {
        var skewed = upright()
        skewed.corners[2].x += 30          // pull one corner out of the parallelogram
        XCTAssertNil(skewed.affineTransform)

        var projective = upright()
        projective.mode = .projective
        XCTAssertNil(projective.affineTransform,
                     "`.projective` is stage 5's, and an affine matrix for it would be a lie.")

        XCTAssertNil(TextFrame(origin: .zero, size: .zero).affineTransform)
    }

    /// `resized(to:)` is what `autoSize` calls on every keystroke. It used to rebuild the corners
    /// through `uprightCorners`, so a turned box snapped straight the moment the artist typed.
    func testAutoSizeRegrowthKeepsTheBoxTurned() throws {
        let angle = CGFloat.pi / 6
        let start = turned(upright(autoSize: true), by: angle)
        let regrown = start.resized(to: CGSize(width: 260, height: 40))
        XCTAssertEqual(regrown.rotation, angle, accuracy: 1e-9)
        assertPoint(regrown[.topLeft], start[.topLeft],
                    "It grows from its top-left, along its own axes.")
        let basis = try XCTUnwrap(regrown.basis)
        XCTAssertEqual(basis.width, 260, accuracy: Self.epsilon)
    }

    // MARK: - Undo

    /// **A handle drag registers nothing on the history stack, and that is a departure from stage 4's
    /// sketch.** The sketch said one `recordUndo` per drag; a session already registers exactly one
    /// step for everything that happened inside it, and a second step for the drag would be a *dead*
    /// entry — undo mid-session commits the session and reverts that, leaving the drag's step
    /// underneath, where pressing undo again restores a frame into a session that no longer exists.
    ///
    /// What the sketch was guarding against is `setVectorTransform`'s shape: a step per *delta*.
    /// That is what the loop below rules out.
    func testAHandleDragRegistersNoHistoryStepOfItsOwn() {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 20, y: 20))
        manager.updateTextString("Label")
        let before = manager.history.undoStack.count

        manager.beginTextHandleDrag(.bottomRight)
        for step in 1...60 {
            manager.dragTextHandle(to: CGPoint(x: 100 + CGFloat(step), y: 90 + CGFloat(step) / 2))
        }
        manager.endTextHandleDrag()

        XCTAssertEqual(manager.history.undoStack.count, before,
                       "Not one step per delta, and not one on lift either — the session's own step "
                       + "is what carries the frame.")
    }

    /// And the session that contained the drag registers exactly one step, whether the drag was one
    /// delta or sixty. This is "one undo step per drag" as the session model can honestly state it.
    func testASessionContainingADragRegistersExactlyOneStepHoweverManyDeltas() {
        for deltaCount in [1, 60] {
            let manager = manager()
            manager.beginTextSession(at: CGPoint(x: 20, y: 20))
            manager.updateTextString("Label")
            let before = manager.history.undoStack.count

            manager.beginTextHandleDrag(.bottomRight)
            for step in 1...deltaCount {
                let t = CGFloat(step) / CGFloat(deltaCount)
                manager.dragTextHandle(to: CGPoint(x: 100 + 60 * t, y: 90 + 40 * t))
            }
            manager.endTextHandleDrag()
            manager.commitInteractiveText()

            XCTAssertEqual(manager.history.undoStack.count, before + 1,
                           "\(deltaCount) deltas still bakes as one 'Add Text'.")
        }
    }

    /// Undo after a drag-and-commit puts the cel back the way it was — the step is real, not merely
    /// present.
    func testUndoingAfterADragRestoresAnEmptyCel() {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 20, y: 20))
        manager.textRecipe.typography.pointSize = 40
        manager.updateTextString("Label")
        manager.beginTextHandleDrag(.bottomRight)
        manager.dragTextHandle(to: CGPoint(x: 180, y: 150))
        manager.endTextHandleDrag()
        manager.commitInteractiveText()
        XCTAssertGreaterThan(coveredPixelCount(manager), 0)

        manager.undo()
        XCTAssertEqual(coveredPixelCount(manager), 0)
    }

    // MARK: - `autoSize` through the model

    func testTheFirstResizeDragClearsAutoSizeAndItDoesNotComeBack() {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 20, y: 20))
        manager.updateTextString("Hi")
        XCTAssertTrue(manager.textFrame.autoSize, "A box nobody has resized grows to fit.")

        manager.beginTextHandleDrag(.bottomRight)
        manager.dragTextHandle(to: CGPoint(x: 150, y: 120))
        manager.endTextHandleDrag()
        XCTAssertFalse(manager.textFrame.autoSize)
        let sized = manager.textFrame.size

        manager.updateTextString(String(repeating: "very much longer ", count: 8))
        XCTAssertFalse(manager.textFrame.autoSize,
                       "Illustrator's point-text-becomes-area-text moment is one-way.")
        XCTAssertEqual(manager.textFrame.size, sized,
                       "From here the box you set is the box the text wraps into (§5.3).")
    }

    func testADragMarksTheSessionUnadjustableUntilTheFingerLifts() {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 20, y: 20))
        manager.updateTextString("Hi")
        XCTAssertTrue(manager.isTextInAdjustableState)

        manager.beginTextHandleDrag(.right)
        XCTAssertFalse(manager.isTextInAdjustableState,
                       "A finger on a grip is the same state as a finger on the box — the panel's "
                       + "sliders are for a box nobody is holding.")
        manager.endTextHandleDrag()
        XCTAssertTrue(manager.isTextInAdjustableState)
    }

    /// A degenerate frame has no axes to size along, so the drag declines rather than producing
    /// NaNs. Declining is visible as a handle that does nothing; a NaN is visible three frames later
    /// as a canvas that has vanished.
    func testADragOnADegenerateFrameIsRefused() {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 20, y: 20))
        manager.textFrame = TextFrame(origin: CGPoint(x: 20, y: 20), size: .zero)
        manager.beginTextHandleDrag(.bottomRight)
        XCTAssertNil(manager.textHandleDrag)
        XCTAssertFalse(manager.textFingerDown)
    }

    // MARK: - It actually draws turned

    /// The bake goes through `TextFrame.affineTransform`, so a quarter-turned box lands as a tall
    /// narrow column of ink where the upright one is a wide short band.
    ///
    /// Asserted as the aspect *flipping* rather than as any measured extent — a 90° turn exchanges
    /// the two axes, and that is true of every font. A bake still drawing through the bounding box
    /// would put both in the same wide band and fail.
    func testAQuarterTurnedBoxBakesTallRatherThanWide() throws {
        let box = CGSize(width: 120, height: 30)
        let flat = upright(size: box, centre: CGPoint(x: 100, y: 100))
        let turnedFrame = turned(flat, by: .pi / 2)

        let words = recipe("MMMMMM", pointSize: 24)
        let uprightInk = try XCTUnwrap(inkBounds(of: words, frame: flat))
        let turnedInk = try XCTUnwrap(inkBounds(of: words, frame: turnedFrame))

        XCTAssertGreaterThan(uprightInk.width, uprightInk.height)
        XCTAssertGreaterThan(turnedInk.height, turnedInk.width,
                             "A quarter turn exchanges the box's two axes; drawing through the "
                             + "bounding box would not.")
        XCTAssertLessThanOrEqual(turnedInk.width, box.height + 2,
                                 "And the column is no wider than the box is tall.")
    }

    // MARK: - Stage 5: the seam with the new solver

    /// **The claim stage 5's entry makes, measured rather than assumed.** ADD_TEXT.md §3 stage 5:
    /// *"`affine()` on the new solver is expected to return the same matrix for every quad stage 4
    /// can make, and `Homography` only has to cover the ones it cannot."*
    ///
    /// Every quad stage 4 can make is `TextFrame.corners(origin:u:v:width:height:)` over some
    /// rotation, some pair of extents and some origin — that one function is where all four of
    /// stage 4's paths (resize, rotate, auto-size regrow, initial placement) build their corners. So
    /// the sweep is over its inputs: 36 rotations × 4 widths × 4 heights × 3 origins = 1728 frames.
    ///
    /// Two things are asserted, and the first is the one that would actually break a drawing path:
    /// the two must **agree about whether there is an affine map at all**, because a disagreement
    /// there is a box that silently stops drawing as glyphs and starts drawing as a resampled bitmap.
    /// Then the matrices themselves, to 1e-12.
    ///
    /// **They are not bit-identical, and that is a finding worth stating rather than hiding behind a
    /// loose accuracy.** Measured worst element difference over the whole sweep: **1.1e-16** — one
    /// ULP at magnitude 1. The cause is that the box prescale is a multiply by `1/w` in the solver
    /// (`H = M · diag(1/w, 1/h, 1)`) and a divide by `w` in `affineTransform`, and `x * (1/w)` and
    /// `x / w` are not the same double. Nothing downstream can see 1e-16 of a canvas point.
    func testTheSolversAffineMatchesStageFoursForEveryQuadItCanMake() throws {
        var compared = 0, worst: CGFloat = 0
        for degrees in stride(from: 0, through: 350, by: 10) {
            for width in [24, 61.3, 300, 1997] as [CGFloat] {
                for height in [24, 41.7, 120, 880] as [CGFloat] {
                    for origin in [-500, 0, 137.25] as [CGFloat] {
                        let angle = CGFloat(degrees) * .pi / 180
                        let u = CGVector(dx: cos(angle), dy: sin(angle))
                        let v = CGVector(dx: -sin(angle), dy: cos(angle))
                        var frame = upright(size: CGSize(width: width, height: height))
                        frame.corners = TextFrame.corners(origin: CGPoint(x: origin, y: origin / 2),
                                                          u: u, v: v, width: width, height: height)

                        let stageFour = frame.affineTransform
                        let solved = frame.homography?.affine()
                        XCTAssertEqual(stageFour == nil, solved == nil,
                                       "The two disagree about whether \(width)×\(height) at \(degrees)° "
                                       + "has an affine map at all.")
                        guard let stageFour, let solved else { continue }
                        compared += 1
                        for (got, want) in zip([solved.a, solved.b, solved.c, solved.d, solved.tx, solved.ty],
                                               [stageFour.a, stageFour.b, stageFour.c, stageFour.d,
                                                stageFour.tx, stageFour.ty]) {
                            worst = max(worst, abs(got - want))
                            XCTAssertEqual(got, want, accuracy: 1e-12)
                        }
                    }
                }
            }
        }
        XCTAssertEqual(compared, 1728, "Every quad in the sweep must have had an affine map.")
        print("MEASURED seam: \(compared) stage-4 quads, worst element difference \(worst).")
    }

    /// And the other half of the seam, which is what makes the first half worth having: the quads
    /// stage 4 *cannot* make are exactly the ones `affineTransform` refuses and the solver covers.
    func testTheSolverCoversTheQuadStageFourRefuses() throws {
        var skewed = upright()
        skewed.corners[2].x += 30          // pull one corner out of the parallelogram
        skewed.mode = .projective
        XCTAssertNil(skewed.affineTransform, "Stage 4 has no matrix for this, by construction.")
        let homography = try XCTUnwrap(skewed.homography, "And stage 5 has one.")
        XCTAssertNil(homography.affine(), "A real perspective term, not a parallelogram in disguise.")
        for (index, corner) in [CGPoint(x: 0, y: 0), CGPoint(x: skewed.size.width, y: 0),
                                CGPoint(x: skewed.size.width, y: skewed.size.height),
                                CGPoint(x: 0, y: skewed.size.height)].enumerated() {
            assertPoint(try XCTUnwrap(homography.map(corner)), skewed.corners[index], accuracy: 1e-9)
        }
    }

    // MARK: - Stage 5: four independent corners

    /// A distort drag puts the corner under the finger and **leaves the other three exactly where
    /// they were** — which is the whole difference from stage 4's corner drag, where all four move.
    func testADistortDragMovesOnlyTheCornerUnderTheFinger() throws {
        let start = upright(size: CGSize(width: 120, height: 60))
        for handle in [TextFrame.Handle.topLeft, .topRight, .bottomRight, .bottomLeft] {
            let corner = try XCTUnwrap(handle.corner)
            let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: handle, distort: true))
            XCTAssertTrue(drag.isDistort)
            // Outwards along the diagonal from the box's centre, which never crosses another corner.
            let centre = start.centre
            let held = start[corner]
            let target = CGPoint(x: held.x + (held.x - centre.x) * 0.4,
                                 y: held.y + (held.y - centre.y) * 0.4)
            let moved = try XCTUnwrap(drag.distortedFrame(draggedTo: target))
            assertPoint(moved[corner], target, "\(handle) must follow the finger exactly.")
            for other in TextFrame.Corner.allCases where other != corner {
                assertPoint(moved[other], start[other], accuracy: 1e-12,
                            "\(handle) moved corner \(other), which a distort must not.")
            }
            XCTAssertEqual(moved.size, start.size, "A distort changes the codomain, never the box.")
        }
    }

    /// The edge grips and the rotation knob are **not** distortable in either mode — "four
    /// independent corner handles" means four, and an edge midpoint has no corner to move.
    func testOnlyTheFourCornersCanDistort() {
        let start = upright()
        for handle in [TextFrame.Handle.top, .right, .bottom, .left, .rotation] {
            XCTAssertNil(handle.corner, "\(handle) does not sit on a corner.")
            let drag = TextFrameDrag(frame: start, handle: handle, distort: true)
            XCTAssertEqual(drag?.isDistort, false,
                           "\(handle) asked to distort must fall back to its stage-4 behaviour.")
        }
    }

    /// A distort that leaves the quad a parallelogram — sliding one corner exactly along the
    /// direction that keeps the opposite edges parallel — must come back out `.affine`.
    ///
    /// **The mode is derived from the corners, not asserted by the gesture**, and this is why: an
    /// unconditional `.projective` would make `affineTransform` refuse a quad it can express, and the
    /// box would lose the native, unresampled drawing path for no visible reason.
    func testADistortThatLandsOnAParallelogramComesBackAffine() throws {
        let start = upright(size: CGSize(width: 120, height: 60))
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .bottomRight, distort: true))
        // The parallelogram condition is p2 == p1 + p3 − p0.
        let parallelogram = CGPoint(x: start[.topRight].x + start[.bottomLeft].x - start[.topLeft].x,
                                    y: start[.topRight].y + start[.bottomLeft].y - start[.topLeft].y)
        let unchanged = try XCTUnwrap(drag.distortedFrame(draggedTo: parallelogram))
        XCTAssertEqual(unchanged.mode, .affine)
        XCTAssertNotNil(unchanged.affineTransform)

        let pulled = try XCTUnwrap(drag.distortedFrame(draggedTo: CGPoint(x: parallelogram.x + 40,
                                                                          y: parallelogram.y + 10)))
        XCTAssertEqual(pulled.mode, .projective)
        XCTAssertNil(pulled.affineTransform, "A projective frame has no affine matrix, by definition.")
        XCTAssertNotNil(pulled.homography)
    }

    /// A distort clears `autoSize`, the way stage 4's eight sizing grips do — a box the artist has
    /// shaped by hand is authoritative from then on.
    func testADistortClearsAutoSize() throws {
        let start = upright(size: CGSize(width: 120, height: 60), autoSize: true)
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .bottomRight, distort: true))
        let moved = try XCTUnwrap(drag.distortedFrame(draggedTo: CGPoint(x: 200, y: 190)))
        XCTAssertFalse(moved.autoSize)
    }

    /// **Clamping holds the last valid quad, through the real model path.**
    ///
    /// `HomographyLogicTests` pins the predicate; this pins that `CanvasManager.dragTextHandle`
    /// actually obeys it — the frame after a refused delta is the frame from the last accepted one,
    /// not the starting frame and not a quad with the corner under the finger.
    func testARefusedDistortHoldsTheLastValidQuad() throws {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 40, y: 60))
        manager.updateTextString("Wall")
        manager.textCornerMode = .distort
        manager.beginTextHandleDrag(.bottomRight)

        // A legal move first, so "the last valid quad" is not the starting one.
        let opposite = manager.textFrame[.topLeft]
        let legal = CGPoint(x: opposite.x + 160, y: opposite.y + 120)
        manager.dragTextHandle(to: legal)
        let held = manager.textFrame
        assertPoint(held[.bottomRight], legal, accuracy: 1e-9)

        // Then straight through the opposite corner and out the other side, which is a bowtie.
        manager.dragTextHandle(to: CGPoint(x: opposite.x - 200, y: opposite.y - 150))
        XCTAssertEqual(manager.textFrame.corners, held.corners,
                       "A refused delta must leave the last valid quad standing.")
        manager.endTextHandleDrag()
    }

    /// A distort drag registers no history step of its own, exactly as stage 4's drags do not — the
    /// session's single step covers everything inside it, and a second one underneath it would be a
    /// dead entry the artist has to press through.
    func testADistortDragRegistersNoHistoryStepOfItsOwn() {
        let manager = manager()
        manager.beginTextSession(at: CGPoint(x: 40, y: 60))
        manager.updateTextString("Wall")
        manager.textCornerMode = .distort
        let depth = manager.history.undoStack.count
        manager.beginTextHandleDrag(.bottomRight)
        for step in 1...30 {
            manager.dragTextHandle(to: CGPoint(x: 150 + CGFloat(step), y: 140 + CGFloat(step) / 2))
        }
        manager.endTextHandleDrag()
        XCTAssertEqual(manager.history.undoStack.count, depth,
                       "A drag records nothing; the session's own commit is the one step.")
    }

    // MARK: - Stage 5: typing in a distorted box happens flat

    /// **ADD_TEXT.md §5.2, the owner's ruling, as geometry**: the editing box is flat — no
    /// perspective — but it keeps the rotation and it stays where the warped box was.
    ///
    /// The three assertions are the three ways a plausible implementation gets this wrong: snapping
    /// to axis-aligned (loses a rotation the artist can see), keeping the perspective (defeats the
    /// point), and re-placing at the origin (the box jumps across the canvas when you tap into it).
    func testTheFlatEditingBoxKeepsTheRotationAndDropsThePerspective() throws {
        var warped = turned(upright(size: CGSize(width: 160, height: 60)), by: .pi / 6)
        warped.corners[1].x += 26
        warped.corners[1].y -= 18
        warped.mode = .projective
        XCTAssertNil(warped.affineTransform)

        let flat = warped.flattenedForEditing
        XCTAssertEqual(flat.mode, .affine)
        XCTAssertNotNil(flat.affineTransform, "The whole point is that the caret gets an affine map.")
        XCTAssertEqual(flat.size, warped.size)

        // Still turned: the box's own +x axis is not the canvas's.
        let basis = try XCTUnwrap(flat.basis)
        XCTAssertGreaterThan(abs(basis.u.dy), 0.1, "A flattened box must not snap to axis-aligned.")

        // And still where it was: the flat box's centre is the warped box's own centre carried
        // through the map, which is not the same as the quad's corner average but is within a box's
        // own width of it.
        let warpedCentre = try XCTUnwrap(warped.homography?.map(CGPoint(x: warped.size.width / 2,
                                                                        y: warped.size.height / 2)))
        assertPoint(flat.centre, warpedCentre, accuracy: 1e-9,
                    "The flat box is centred on the warped box's own middle.")
    }

    /// An `.affine` frame is returned unchanged — stage 4's behaviour (you edit in place under the
    /// affine transform, rotated caret and all) has to survive stage 5 untouched.
    func testAnAffineFrameIsNotFlattenedAtAll() {
        let turnedFrame = turned(upright(), by: .pi / 5)
        XCTAssertEqual(turnedFrame.flattenedForEditing, turnedFrame)
    }

    // MARK: - Stage 5: it actually bakes warped

    /// The bake goes through the warp, not through the bounding box: a strongly foreshortened box
    /// puts most of its ink in the half where the quad is wide, and almost none in the half where it
    /// has narrowed.
    ///
    /// Asserted as an inequality between the two halves rather than as any measured extent — a
    /// bounding-box fallback draws the same glyphs in both halves and fails, and the claim is true of
    /// every font.
    func testAForeshortenedBoxBakesItsInkIntoTheWideEnd() throws {
        let words = recipe("MMMMMMMM", pointSize: 20)
        var frame = TextFrame(origin: CGPoint(x: 20, y: 40), size: CGSize(width: 160, height: 60),
                              autoSize: false)
        // Left edge full height, right edge squeezed to a sliver about its own middle.
        frame.corners = [CGPoint(x: 20, y: 40), CGPoint(x: 180, y: 62),
                         CGPoint(x: 180, y: 78), CGPoint(x: 20, y: 100)]
        frame.mode = .projective
        XCTAssertNil(frame.affineTransform)
        XCTAssertNotNil(frame.homography)

        let image = try XCTUnwrap(TextLayout.render(recipe: words, frame: frame,
                                                    canvasSize: Self.canvasSize))
        let cg = try XCTUnwrap(image.cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
        let width = Int(Self.canvasSize.width), height = Int(Self.canvasSize.height)
        var left = 0, right = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4 + 3
                guard bytes.indices.contains(index), bytes[index] > 0 else { continue }
                if x < 100 { left += 1 } else { right += 1 }
            }
        }
        XCTAssertGreaterThan(left + right, 0, "The warp put no ink on the canvas at all.")
        XCTAssertGreaterThan(left, right,
                             "A foreshortened box has more ink in its wide end; a bounding-box "
                             + "fallback would spread it evenly.")
    }

    // MARK: - Stage 5: the other five grips, on a quad that has perspective

    /// **A sizing grip on a warped box grows the box *along the wall*, and does not lie the
    /// perspective flat.**
    ///
    /// What this replaces looked like nothing and was the worst kind of bug: `resized(towards:)`
    /// rebuilds all four corners from `basis`, which is the frame's two edge *directions*, so it can
    /// only describe a parallelogram. Handed a warped quad it returned the parallelogram nearest it —
    /// the wall of text lay down flat, the far corner jumped — while leaving `mode` still saying
    /// `.projective` over a quad that no longer was. Nudging the wrap width to fix a line break
    /// destroyed the perspective, and there was no undo step of its own to get it back.
    ///
    /// The claims are geometric rather than numeric, so they are true of any correct implementation:
    ///
    /// - **The anchor edge does not move at all.** Dragging `.right` holds the box's `x = 0` edge, and
    ///   that edge is corners 0 and 3 whatever the perspective.
    /// - **The moved edge slides along the quad's own edge lines.** The box-space line `y = 0` maps to
    ///   the line through corners 0 and 1, so a wider box's new corner 1 stays on it — and, the
    ///   discriminating half, its new corner 2 stays on the line through corners 3 and 2, which on a
    ///   warped quad is a *different direction*. The flatten put corner 2 on the first line's
    ///   direction instead, which is exactly how the far corner jumped.
    /// - **The perspective survives**: the quad is still not a parallelogram and the mode is still
    ///   `.projective`, so the frame keeps the drawing path it had.
    func testASizingGripOnAWarpedBoxGrowsItAlongTheWallRatherThanFlatteningIt() throws {
        let start = try warped()
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .right))
        XCTAssertFalse(drag.isDistort, "An edge grip is a resize in both corner modes.")

        // Out past the right edge, along the direction the top edge runs.
        let target = CGPoint(x: start[.topRight].x + 70, y: start[.topRight].y + 24)
        let sized = try XCTUnwrap(drag.clampedFrame(draggedTo: target))

        assertPoint(sized[.topLeft], start[.topLeft], accuracy: 1e-9, "the held edge moved")
        assertPoint(sized[.bottomLeft], start[.bottomLeft], accuracy: 1e-9, "the held edge moved")
        XCTAssertGreaterThan(sized.size.width, start.size.width, "The grip has to have sized something.")
        XCTAssertEqual(sized.size.height, start.size.height, accuracy: 1e-9,
                       "An edge grip freezes the axis it is not on, in both modes.")

        assertDistanceToLine(sized[.topRight], start[.topLeft], start[.topRight], accuracy: 1e-6,
                             "corner 1 left the top edge's own line")
        assertDistanceToLine(sized[.bottomRight], start[.bottomLeft], start[.bottomRight], accuracy: 1e-6,
                             "corner 2 left the bottom edge's own line — the flatten's signature")

        XCTAssertEqual(sized.mode, .projective, "A resize along the wall does not remove the wall.")
        let quad = try XCTUnwrap(sized.quad)
        XCTAssertFalse(quad.isParallelogram(tolerance: 1e-3),
                       "The resize flattened the quad, which is the bug this replaced.")

        // And the two edge directions genuinely differ on this fixture, or the assertion above is
        // satisfied by any implementation at all.
        let top = CGVector(dx: start[.topRight].x - start[.topLeft].x,
                           dy: start[.topRight].y - start[.topLeft].y)
        let bottom = CGVector(dx: start[.bottomRight].x - start[.bottomLeft].x,
                              dy: start[.bottomRight].y - start[.bottomLeft].y)
        let cross = abs(top.dx * bottom.dy - top.dy * bottom.dx)
        XCTAssertGreaterThan(cross, 100, "The fixture's opposite edges are parallel, so it discriminates nothing.")
    }

    /// **The grip does not jump under the finger at touch-down**, and that is arithmetic rather than
    /// luck: the box-space line `x = w` maps onto the line through corners 1 and 2, so the `.right`
    /// grip's own canvas position — the midpoint of that segment — inverts to exactly the width it
    /// started from.
    ///
    /// Worth its own test because it is the property a composition through `H⁻¹` can get wrong in a way
    /// nothing else here would catch: a drag that reads the grip's position through the *basis* would
    /// come back with a different extent, and the box would visibly twitch the instant it was touched.
    /// Both horizontal grips and both vertical ones, since they read different halves of the map.
    ///
    /// It also pins the latched **anchor**, which moved to the homography for the same reason:
    /// `Basis` decomposes onto two edge *directions*, so on a warped quad it reports the point the box
    /// would have had with the perspective taken out — which is not a point on the quad at all.
    /// MEASURED on this fixture: for `.left` the basis answer sits 8.2 pt off the quad's right edge
    /// and for `.top` 17.2 pt off its bottom edge.
    func testAnEdgeGripOnAWarpedBoxDoesNotMoveTheBoxWhenDraggedToItsOwnPosition() throws {
        let start = try warped()
        let layout = start.handleLayout(rotationOffset: 0)
        // The quad edge each grip's anchor has to sit on: the one diametrically opposite it.
        let oppositeEdge: [TextFrame.Handle: (TextFrame.Corner, TextFrame.Corner)] =
            [.right: (.bottomLeft, .topLeft), .left: (.topRight, .bottomRight),
             .top: (.bottomLeft, .bottomRight), .bottom: (.topLeft, .topRight)]
        for handle in [TextFrame.Handle.right, .left, .top, .bottom] {
            let position = try XCTUnwrap(layout.first { $0.handle == handle }?.position)
            let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: handle))
            let edge = try XCTUnwrap(oppositeEdge[handle])
            assertDistanceToLine(drag.anchor, start[edge.0], start[edge.1], accuracy: 1e-6,
                                 "\(handle)'s anchor is not on the edge it holds still")
            let unmoved = try XCTUnwrap(drag.clampedFrame(draggedTo: position),
                                        "\(handle): a drag to the grip's own position was refused.")
            XCTAssertEqual(unmoved.size.width, start.size.width, accuracy: 1e-6, "\(handle) width")
            XCTAssertEqual(unmoved.size.height, start.size.height, accuracy: 1e-6, "\(handle) height")
            for corner in TextFrame.Corner.allCases {
                assertPoint(unmoved[corner], start[corner], accuracy: 1e-6,
                            "\(handle) moved corner \(corner) before the finger did")
            }
        }
    }

    /// **The knob turns a warped quad rigidly**, which is what keeps its perspective exactly: turning
    /// the four corners is `R · H`, whose third row is `H`'s third row unchanged.
    ///
    /// Stage 4's `rotated(towards:)` rebuilt the quad from `basis.width`/`basis.height` along two
    /// perpendicular axes, so on a warped quad it did not turn the box — it replaced it with an
    /// upright rectangle of roughly the right extents, at the new angle. The identities here are the
    /// ones that separates the two: **every pairwise distance between corners survives** a rigid turn
    /// and none of them survives a rebuild, and turning back restores the quad exactly.
    func testTheKnobOnAWarpedBoxTurnsTheQuadRigidlyAndIsInvertible() throws {
        let start = try warped()
        let centre = start.centre
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .rotation))

        // The knob stands off the top edge, so "straight up from the centre" is the box as it is and
        // this asks for a further 40°.
        func knobPoint(at angle: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + 80 * cos(angle - .pi / 2), y: centre.y + 80 * sin(angle - .pi / 2))
        }
        let basis = try XCTUnwrap(start.basis)
        let started = atan2(basis.u.dy, basis.u.dx)
        let turned = try XCTUnwrap(drag.clampedFrame(draggedTo: knobPoint(at: started + 40 * .pi / 180)))

        assertPoint(turned.centre, centre, accuracy: 1e-6, "a rotation pivots without travelling")
        XCTAssertEqual(turned.size, start.size, "Turning a box is not sizing it.")
        XCTAssertEqual(turned.mode, .projective, "A rigid turn cannot remove the perspective.")
        for a in TextFrame.Corner.allCases {
            for b in TextFrame.Corner.allCases where b.rawValue > a.rawValue {
                let before = hypot(start[a].x - start[b].x, start[a].y - start[b].y)
                let after = hypot(turned[a].x - turned[b].x, turned[a].y - turned[b].y)
                XCTAssertEqual(after, before, accuracy: 1e-6,
                               "\(a)–\(b) changed length, so the quad was rebuilt rather than turned.")
            }
        }
        XCTAssertNotEqual(turned.corners, start.corners, "Nothing turned at all.")

        // And back, through a second drag latched on the turned frame.
        let back = try XCTUnwrap(TextFrameDrag(frame: turned, handle: .rotation))
        let restored = try XCTUnwrap(back.clampedFrame(draggedTo: knobPoint(at: started)))
        for corner in TextFrame.Corner.allCases {
            assertPoint(restored[corner], start[corner], accuracy: 1e-6, "corner \(corner) after turning back")
        }
    }

    /// A sizing grip on a warped box is **clamped like a distort is**, through the same predicate.
    ///
    /// This is why `CanvasManager.dragTextHandle` now asks one optional for all nine grips instead of
    /// branching on `if drag.isDistort`: the distort used to be the only gesture that could make an
    /// invalid quad, and it is not any more. Growing the box towards the vanishing line eventually
    /// carries its far corner past it, and the grip has to feel like it sticks rather than flipping
    /// the wall through the horizon.
    ///
    /// **It is a narrower failure than it sounds, and the fixture is chosen to reach it at all.** For
    /// a quad foreshortened the other way, `H⁻¹` carries the whole visible half-plane onto the box's
    /// own positive half-plane, so no finite finger position can produce an invalid box and the
    /// refusal is unreachable. MEASURED on the fixture below: 24 of 41 steps along the ray are
    /// accepted and the last 17 refused, so what the loop ends holding is the last quad before the
    /// crossing — not the starting one, which is the difference between clamping and cancelling.
    func testARefusedResizeOnAWarpedBoxAlsoHoldsTheLastValidQuad() throws {
        let start = try warped()
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .right))
        var held = start
        var refusals = 0, accepted = 0
        // Out along the top edge and away, until the far corner crosses the vanishing line.
        for step in 0...40 {
            let t = CGFloat(step) / 40
            let target = CGPoint(x: start[.topRight].x + 2_000 * t, y: start[.topRight].y - 40 * t)
            if let next = drag.clampedFrame(draggedTo: target) { held = next; accepted += 1 }
            else { refusals += 1 }
        }
        XCTAssertGreaterThan(refusals, 0, "The path never left the valid set, so nothing was clamped.")
        XCTAssertGreaterThan(accepted, 1, "And it has to accept something first, or nothing was held.")
        XCTAssertGreaterThan(held.size.width, start.size.width, "The held quad is not the starting one.")
        let quad = try XCTUnwrap(held.quad)
        XCTAssertTrue(Homography.isValidQuad(quad, boxSize: held.size), "What is held must itself be valid.")

        // And `frame(draggedTo:)`, the total form, means the same thing as the optional one rather
        // than something different — it falls back to the latched frame, never to a refused quad.
        let refused = CGPoint(x: start[.topRight].x + 2_000, y: start[.topRight].y - 40)
        XCTAssertNil(drag.clampedFrame(draggedTo: refused))
        XCTAssertEqual(drag.frame(draggedTo: refused).corners, start.corners)
    }

    /// **`warpMagnification` is exactly 1 for every `.affine` frame, however it is turned** — the
    /// number `TextOverlayView` multiplies its backing store by.
    ///
    /// Not "1 to within a rounding": the guard that makes it exact is a mode test rather than an
    /// arithmetic one, and that is the whole point. `maximumCornerScale` is `√|det J|`, which on a
    /// rotated affine frame is `√(cos²θ + sin²θ)` — 1 to within an ULP, not 1 — and the caller's
    /// `max(1, …)` clamps the low side only, so the ULP survives into `contentsScale` and rounds a
    /// glyph bitmap up by a texel on some angles and not others. **MEASURED with the guard removed,
    /// on the 300×120 box below: 87 of these 3600 angles come out above 1**, by an ULP —
    /// `1.0000000000000002` — which is enough to carry a `contentsScale` of `2.0000000000000004` into
    /// `UIGraphicsImageRenderer` and round the bitmap up to 601 texels where the same box unrotated
    /// takes 600.
    ///
    /// So this sweeps 3600 angles and asserts the exact value, which is the only assertion that can
    /// tell the two apart. A comment on the old property claimed it was 1 for every frame stages 1-4
    /// could make; it was not, and this is what would have said so.
    func testWarpMagnificationIsExactlyOneForAnAffineFrameAtEveryAngle() {
        let box = upright(size: CGSize(width: 300, height: 120))
        var above = 0
        for tenths in 0..<3600 {
            let frame = turned(box, by: CGFloat(tenths) / 10 * .pi / 180)
            XCTAssertEqual(frame.mode, .affine, "The fixture must stay affine or it proves nothing.")
            if frame.warpMagnification != 1 { above += 1 }
        }
        XCTAssertEqual(above, 0,
                       "\(above) of 3600 rotated affine frames want a magnified backing store, which "
                       + "is an ULP of trig rather than a foreshortening.")

        // And it is still the real number where there *is* a foreshortening to compensate for.
        let wall = try? warped()
        XCTAssertGreaterThan(wall?.warpMagnification ?? 0, 1,
                             "A foreshortened box's near corner genuinely needs more texels than it has points.")
    }

    // MARK: - Support

    /// A genuinely `.projective` frame: an upright box with one corner pulled out of the plane,
    /// through the real distort drag so the fixture cannot disagree with the gesture that makes one.
    private func warped() throws -> TextFrame {
        let start = upright(size: CGSize(width: 120, height: 60), centre: CGPoint(x: 100, y: 100),
                            autoSize: false)
        let drag = try XCTUnwrap(TextFrameDrag(frame: start, handle: .bottomRight, distort: true))
        // Down and out, which puts the vanishing line on the *positive* side of the box in both axes
        // — the one arrangement in which a sizing grip can be pushed past it and refused. Pulled the
        // other way the inverse map is a bijection of the visible half-plane onto the box's, and no
        // finite finger position can produce an invalid quad at all.
        let frame = try XCTUnwrap(drag.distortedFrame(draggedTo: CGPoint(x: 190, y: 175)))
        XCTAssertEqual(frame.mode, .projective, "The fixture is not warped, so nothing below is tested.")
        return frame
    }

    /// `point` sits on the line through `a` and `b`, to `accuracy` canvas points.
    private func assertDistanceToLine(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint,
                                      accuracy: CGFloat, _ message: String = "",
                                      file: StaticString = #filePath, line: UInt = #line) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return XCTFail("degenerate line", file: file, line: line) }
        let distance = abs(dx * (point.y - a.y) - dy * (point.x - a.x)) / length
        XCTAssertEqual(distance, 0, accuracy: accuracy, message, file: file, line: line)
    }

    /// A canvas with one raster layer and an empty undo stack. `addLayer()` registers a structural
    /// step of its own, so without the `removeAll()` every depth assertion above would be counting
    /// the fixture's step — `TextBakeCharacterizationTests` states the same reason.
    private func manager() -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = Self.canvasSize
        manager.addLayer()
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return manager
    }

    private func coveredPixelCount(_ manager: CanvasManager) -> Int {
        guard let celIndex = manager.activeCelIndex(inLayer: 0, atFrame: manager.currentFrame) else {
            XCTFail("No cel to read")
            return 0
        }
        let cel = manager.layers[0].cels[celIndex]
        let image = PixelOps.rasterize(cel: cel, canvasSize: Self.canvasSize, memoize: false)
        guard let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return 0 }
        return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] > 0 ? 1 : 0) }
    }

    /// The canvas-space rectangle the baked glyphs actually cover, read off the rendered alpha.
    private func inkBounds(of recipe: TextRecipe, frame: TextFrame) -> CGRect? {
        guard let image = TextLayout.render(recipe: recipe, frame: frame, canvasSize: Self.canvasSize),
              let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return nil }
        let width = Int(Self.canvasSize.width), height = Int(Self.canvasSize.height)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4 + 3
                guard bytes.indices.contains(index), bytes[index] > 0 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
