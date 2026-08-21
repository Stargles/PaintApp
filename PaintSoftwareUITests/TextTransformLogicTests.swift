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

    // MARK: - Support

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
