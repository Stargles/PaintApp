import UIKit
import XCTest


/// The Move tool's on-canvas box, asserted headlessly — the two defects the owner reported on their
/// iPad on 2026-08-21, and the geometry that fixes them.
///
/// > *"Move is extremely slow, reducing FPS to 5fps."*
/// > *"The move nodes' size doesn't stay constant to the screen, and right now they don't seem to
/// > respond to touch."*
///
/// **The second is one defect, not two.** `TransformHandleView` drew a 24×24 grip inside
/// `CanvasView`'s transformed `container`, so 24 was 24 *canvas* points: at the zoom that fits a
/// 2048×1024 document on an iPad 9 that is roughly 14 screen points of dot **and 14 screen points of
/// touch target**. `ADD_TEXT.md` §1 predicted exactly this and told the text overlay not to copy it.
/// The tests under "Zoom invariance" below are the direct regression: they assert the drawn size and
/// the reach in *screen* points across a 32× range of zoom, and the pre-port code fails both ends.
///
/// **Identities and invariants, never a screenful of coordinates**, in `TextTransformLogicTests`'
/// idiom: *the centre did not move*, *sixty deltas and one delta agree*, *the nearer of two
/// overlapping grips wins*. Each is false for a plausible wrong implementation and true for any
/// correct one.
///
/// The geometry lives on `ObjectTransformFrame`/`ObjectTransformDrag` rather than inside
/// `ObjectTransformOverlayView`, which is the only reason any of it is reachable from here.
final class ObjectTransformLogicTests: XCTestCase {

    private static let epsilon: CGFloat = 1e-9
    /// Loose enough for accumulated trig, tight enough that a genuinely moved corner cannot hide
    /// under it — the boxes here are hundreds of points across.
    private static let loose: CGFloat = 1e-6

    // MARK: - Fixtures

    /// An upright box, 400×300, centred at (1000, 500) on the owner's 2048×1024 canvas.
    private func upright(scale: CGFloat = 1, rotation: CGFloat = 0) -> ObjectTransformFrame {
        ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                       scale: scale, rotation: rotation),
                             contentSize: CGSize(width: 400, height: 300))
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint,
                             accuracy: CGFloat = ObjectTransformLogicTests.loose,
                             _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, message, file: file, line: line)
    }

    private func position(of handle: ObjectTransformFrame.Handle,
                          in frame: ObjectTransformFrame,
                          rotationOffset: CGFloat = 36) -> CGPoint? {
        frame.handleLayout(rotationOffset: rotationOffset).first { $0.handle == handle }?.position
    }

    // MARK: - Where the handles are

    func testCornerHandlesSitOnTheTransformedCorners() {
        let frame = upright()
        let corners = frame.corners
        assertPoint(corners[0], CGPoint(x: 800, y: 350), "top-left")
        assertPoint(corners[1], CGPoint(x: 1200, y: 350), "top-right")
        assertPoint(corners[2], CGPoint(x: 1200, y: 650), "bottom-right")
        assertPoint(corners[3], CGPoint(x: 800, y: 650), "bottom-left")

        let layout = frame.handleLayout(rotationOffset: 36)
        assertPoint(position(of: .topLeft, in: frame)!, corners[0])
        assertPoint(position(of: .topRight, in: frame)!, corners[1])
        assertPoint(position(of: .bottomRight, in: frame)!, corners[2])
        assertPoint(position(of: .bottomLeft, in: frame)!, corners[3])
        XCTAssertEqual(layout.count, 6, "four corners, the green rotation knob and the yellow box knob")
    }

    func testTheCornersFollowScaleAndRotation() {
        // A half turn puts the box's own top-left at the bottom right of the screen, which is what
        // keeps a grip attached to the corner the artist grabbed rather than to a screen direction.
        let turned = upright(rotation: .pi)
        assertPoint(turned.corners[0], CGPoint(x: 1200, y: 650))
        assertPoint(turned.corners[2], CGPoint(x: 800, y: 350))

        let doubled = upright(scale: 2)
        assertPoint(doubled.corners[0], CGPoint(x: 600, y: 200))
        assertPoint(doubled.corners[2], CGPoint(x: 1400, y: 800))
        // Scale is about the centre, so the centre is the one point that does not move.
        assertPoint(doubled.centre, upright().centre)
    }

    /// The drift guard the whole split exists for: the positions the overlay *draws* and the
    /// positions it *hits* are one function, so a probe on a drawn handle must find that handle.
    func testTheHitTestReadsExactlyTheLayoutThatIsDrawn() {
        for rotation in [CGFloat(0), 0.4, CGFloat.pi / 2, 2.7] {
            for scale in [CGFloat(0.3), 1, 3] {
                let frame = upright(scale: scale, rotation: rotation)
                for entry in frame.handleLayout(rotationOffset: 36) {
                    XCTAssertEqual(frame.handle(nearest: entry.position, reach: 1, rotationOffset: 36),
                                   entry.handle,
                                   "a probe on the drawn position of \(entry.handle) must find it "
                                   + "(scale \(scale), rotation \(rotation))")
                }
            }
        }
    }

    func testTheRotationKnobStandsOffTheTopEdgeAtAnyRotation() {
        for rotation in [CGFloat(0), 0.7, CGFloat.pi / 2, CGFloat.pi, -1.2] {
            let frame = upright(rotation: rotation)
            let knob = position(of: .rotation, in: frame, rotationOffset: 36)!
            let topCentre = CGPoint(x: (frame.corners[0].x + frame.corners[1].x) / 2,
                                    y: (frame.corners[0].y + frame.corners[1].y) / 2)
            XCTAssertEqual(hypot(knob.x - topCentre.x, knob.y - topCentre.y), 36, accuracy: Self.loose,
                           "the knob stands off by the offset it was given, at rotation \(rotation)")
            // And it stands off *away* from the centre, not into the artwork.
            XCTAssertGreaterThan(hypot(knob.x - frame.centre.x, knob.y - frame.centre.y),
                                 hypot(topCentre.x - frame.centre.x, topCentre.y - frame.centre.y))
        }
    }

    /// One offset drives both knobs, so a zero omits both and leaves the four corners.
    func testAZeroOffsetOmitsBothKnobsEntirely() {
        XCTAssertEqual(upright().handleLayout(rotationOffset: 0).count, 4)
    }

    func testAnEmptyBoxDrawsAndHitsNothing() {
        let empty = ObjectTransformFrame(transform: .identity, contentSize: .zero)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.handleLayout(rotationOffset: 36).isEmpty)
        XCTAssertNil(empty.target(at: .zero, reach: 22, rotationOffset: 36))
    }

    // MARK: - Hit testing

    func testTheNearerOfTwoOverlappingTargetsWins() {
        // A box small enough on screen that a single finger covers both top corners: 20 canvas
        // points wide against a 22-point reach. First-match would answer with whichever the layout
        // happened to list first, and cost such a box most of its handles.
        let small = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 100, y: 100),
                                                                   scale: 1, rotation: 0),
                                         contentSize: CGSize(width: 20, height: 20))
        let topLeft = small.corners[0], topRight = small.corners[1]
        XCTAssertLessThan(hypot(topRight.x - topLeft.x, topRight.y - topLeft.y), 2 * 22,
                          "the fixture only tests what it claims to if the two targets really overlap")

        let nearerTheLeft = CGPoint(x: topLeft.x + 4, y: topLeft.y)
        XCTAssertEqual(small.target(at: nearerTheLeft, reach: 22, rotationOffset: 36), .topLeft)
        let nearerTheRight = CGPoint(x: topRight.x - 4, y: topRight.y)
        XCTAssertEqual(small.target(at: nearerTheRight, reach: 22, rotationOffset: 36), .topRight)
    }

    func testAProbeBeyondReachFindsNothing() {
        let frame = upright()
        let corner = frame.corners[0]
        // Outward along the diagonal, so it is outside the box as well as out of reach — otherwise
        // the answer would legitimately be the move band.
        let outside = CGPoint(x: corner.x - 30, y: corner.y - 30)
        XCTAssertNil(frame.handle(nearest: outside, reach: 22, rotationOffset: 36))
        XCTAssertNil(frame.target(at: outside, reach: 22, rotationOffset: 36))
    }

    func testAGripBeatsTheMoveBandWhereTheyOverlap() {
        let frame = upright()
        // Just inside the top-left corner: within the box, and within reach of the grip.
        let inside = CGPoint(x: frame.corners[0].x + 3, y: frame.corners[0].y + 3)
        XCTAssertTrue(frame.contains(inside))
        XCTAssertEqual(frame.target(at: inside, reach: 22, rotationOffset: 36), .topLeft,
                       "a grip must win where it overlaps the band, or the corners of a small box "
                       + "would only ever move it")
    }

    func testTheBoxItselfIsTheMoveBandAndEverythingElseDeclinesTheTouch() {
        let frame = upright()
        XCTAssertEqual(frame.target(at: frame.centre, reach: 22, rotationOffset: 36), .body)
        XCTAssertTrue(frame.contains(CGPoint(x: 850, y: 400)))
        XCTAssertFalse(frame.contains(CGPoint(x: 700, y: 400)), "left of the box")
        XCTAssertFalse(frame.contains(CGPoint(x: 1000, y: 900)), "below the box")
        // The discipline that lets pan and pinch keep working while the box is up.
        XCTAssertNil(frame.target(at: CGPoint(x: 60, y: 60), reach: 22, rotationOffset: 36))
    }

    func testContainmentFollowsTheBoxThroughARotation() {
        let turned = upright(rotation: .pi / 4)
        // A point that is inside the upright box and outside the turned one: near the top-right
        // corner, which a 45-degree turn swings well past the box's own short axis.
        let probe = CGPoint(x: 1190, y: 360)
        XCTAssertTrue(upright().contains(probe))
        XCTAssertFalse(turned.contains(probe))
        // The centre is inside at every rotation.
        XCTAssertTrue(turned.contains(turned.centre))
    }

    func testADegenerateTransformCannotBeHitRatherThanCrashing() {
        let collapsed = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 10, y: 10),
                                                                       scale: 0, rotation: 0),
                                             contentSize: CGSize(width: 40, height: 40))
        XCTAssertFalse(collapsed.contains(CGPoint(x: 10, y: 10)))
    }

    // MARK: - Zoom invariance — the direct regression for (d)

    /// A grip is chrome. It belongs to the screen, not to the drawing, so it is 14 points across at
    /// 0.3× zoom and at 8×.
    ///
    /// **Asserted against the layers that ship**, via `drawnChrome`, rather than against the
    /// constants they are computed from: the defect this replaces set a perfectly correct 24 and
    /// then drew it in the wrong coordinate space, which a constants-based test would have passed.
    func testHandlesAreTheSameSizeOnScreenAtEveryZoom() {
        let view = ObjectTransformOverlayView(frame: CGRect(x: 0, y: 0, width: 2048, height: 1024))
        for canvasScale in [CGFloat(0.125), 0.3, 0.5, 1, 2, 4] {
            view.update(isActive: true, frame: upright(), canvasScale: canvasScale)
            let chrome = view.drawnChrome
            XCTAssertEqual(chrome.handles.count, 6, "six grips at \(canvasScale)×")
            for entry in chrome.handles {
                XCTAssertEqual(entry.frame.width * canvasScale, 14, accuracy: 1e-9,
                               "\(entry.handle) is 14 screen points at \(canvasScale)×")
                XCTAssertEqual(entry.frame.height * canvasScale, 14, accuracy: 1e-9,
                               "\(entry.handle) is square at \(canvasScale)×")
            }
            XCTAssertEqual(chrome.outlineWidth * canvasScale, 1.5, accuracy: 1e-9,
                           "the outline is 1.5 screen points at \(canvasScale)×")
        }
    }

    /// The half the owner actually noticed. A target that shrinks with the artwork is a target no
    /// fingertip can find, and "they don't seem to respond to touch" is what that looks like.
    func testAHandleIsHittableAtTheSameScreenDistanceAtEveryZoom() {
        let view = ObjectTransformOverlayView(frame: CGRect(x: 0, y: 0, width: 2048, height: 1024))
        for canvasScale in [CGFloat(0.125), 0.3, 0.5, 1, 2, 4] {
            let frame = upright()
            view.update(isActive: true, frame: frame, canvasScale: canvasScale)
            let corner = frame.corners[0]
            // Outward along the diagonal from the top-left grip, at a fixed distance *on screen*.
            func probe(screenPoints: CGFloat) -> CGPoint {
                let canvasPoints = screenPoints / canvasScale / CGFloat(2).squareRoot()
                return CGPoint(x: corner.x - canvasPoints, y: corner.y - canvasPoints)
            }
            XCTAssertEqual(view.target(at: probe(screenPoints: 18)), .topLeft,
                           "18 screen points out is inside the 22-point reach at \(canvasScale)×")
            XCTAssertNil(view.target(at: probe(screenPoints: 30)),
                         "30 screen points out is beyond the 22-point reach at \(canvasScale)×")
        }
    }

    func testTheReachAndTheKnobOffsetAreScreenConstants() {
        let view = ObjectTransformOverlayView(frame: .zero)
        for canvasScale in [CGFloat(0.125), 1, 4] {
            view.canvasScale = canvasScale
            XCTAssertEqual(view.handleReach * canvasScale, 22, accuracy: 1e-9)
            XCTAssertEqual(view.rotationOffset * canvasScale, 36, accuracy: 1e-9)
        }
    }

    /// A pinch can land mid-drag. The chrome resizes; the box does not move, because the drag's
    /// reference frame is latched in `ObjectTransformDrag` and nothing here can reach it.
    func testAScaleChangeMidDragResizesTheChromeAndMovesNothingElse() {
        let view = ObjectTransformOverlayView(frame: CGRect(x: 0, y: 0, width: 2048, height: 1024))
        let frame = upright()
        view.update(isActive: true, frame: frame, canvasScale: 1)
        let before = view.drawnChrome.handles.first { $0.handle == .topLeft }!

        let drag = ObjectTransformDrag(frame: frame, handle: .topLeft, at: frame.corners[0])
        let answerBefore = drag.transform(draggedTo: CGPoint(x: 700, y: 300))

        view.canvasScale = 4
        let after = view.drawnChrome.handles.first { $0.handle == .topLeft }!

        XCTAssertEqual(after.frame.width, before.frame.width / 4, accuracy: 1e-9, "the dot resized")
        assertPoint(CGPoint(x: after.frame.midX, y: after.frame.midY),
                    CGPoint(x: before.frame.midX, y: before.frame.midY),
                    "and it is still centred on the same corner")
        XCTAssertTrue(view.isActive, "the drag is the same drag; only the chrome changed size")
        XCTAssertEqual(drag.transform(draggedTo: CGPoint(x: 700, y: 300)), answerBefore,
                       "the latched drag answers the same after the zoom as before it")
    }

    func testDeactivatingClearsTheChrome() {
        let view = ObjectTransformOverlayView(frame: CGRect(x: 0, y: 0, width: 2048, height: 1024))
        view.update(isActive: true, frame: upright(), canvasScale: 1)
        XCTAssertTrue(view.isActive)
        view.update(isActive: false, frame: upright(), canvasScale: 1)
        XCTAssertFalse(view.isActive)
        XCTAssertTrue(view.isHidden)
        XCTAssertTrue(view.drawnChrome.handles.isEmpty)
        XCTAssertNil(view.target(at: CGPoint(x: 1000, y: 500)), "a hidden box claims no touches")
        XCTAssertNil(view.hitTest(CGPoint(x: 1000, y: 500), with: nil))
    }

    func testAnActiveBoxClaimsItsTargetsAndDeclinesEverythingElse() {
        let view = ObjectTransformOverlayView(frame: CGRect(x: 0, y: 0, width: 2048, height: 1024))
        view.update(isActive: true, frame: upright(), canvasScale: 1)
        XCTAssertNotNil(view.hitTest(CGPoint(x: 1000, y: 500), with: nil), "the move band")
        XCTAssertNotNil(view.hitTest(CGPoint(x: 800, y: 350), with: nil), "a corner grip")
        XCTAssertNil(view.hitTest(CGPoint(x: 60, y: 60), with: nil),
                     "bare canvas falls through, so pan and pinch keep working while the box is up")
    }

    // MARK: - One drag

    /// `TextFrameDrag`'s property, and the reason the whole starting transform is latched: sixty
    /// deltas and one delta land in the same place, so a drag cannot accumulate rounding and cannot
    /// be re-based by anything that happens mid-gesture.
    func testSixtyDeltasAndOneDeltaAgree() {
        for handle in [ObjectTransformFrame.Handle.body, .topLeft, .rotation] {
            let frame = upright()
            let start = CGPoint(x: 810, y: 360)
            let end = CGPoint(x: 1140, y: 265)
            let drag = ObjectTransformDrag(frame: frame, handle: handle, at: start)

            let oneShot = drag.transform(draggedTo: end)
            var last = frame.transform
            for step in 1...60 {
                let t = CGFloat(step) / 60
                last = drag.transform(draggedTo: CGPoint(x: start.x + (end.x - start.x) * t,
                                                         y: start.y + (end.y - start.y) * t))
            }
            assertPoint(last.position, oneShot.position, "\(handle) position")
            XCTAssertEqual(last.scale, oneShot.scale, accuracy: Self.loose, "\(handle) scale")
            XCTAssertEqual(last.rotation, oneShot.rotation, accuracy: Self.loose, "\(handle) rotation")
        }
    }

    func testTheMoveBandCarriesTheLayerByTheTouchDelta() {
        let frame = upright()
        let drag = ObjectTransformDrag(frame: frame, handle: .body, at: CGPoint(x: 900, y: 400))
        let moved = drag.transform(draggedTo: CGPoint(x: 950, y: 380))
        assertPoint(moved.position, CGPoint(x: 1050, y: 480))
        XCTAssertEqual(moved.scale, frame.transform.scale, "a move changes nothing else")
        XCTAssertEqual(moved.rotation, frame.transform.rotation)
    }

    func testACornerScalesAboutTheCentreAndTurnsNothing() {
        let frame = upright()
        // Grab the bottom-right corner and pull it twice as far from the centre.
        let corner = frame.corners[2]
        let centre = frame.centre
        let doubled = CGPoint(x: centre.x + (corner.x - centre.x) * 2,
                              y: centre.y + (corner.y - centre.y) * 2)
        let drag = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: corner)
        let scaled = drag.transform(draggedTo: doubled)
        XCTAssertEqual(scaled.scale, 2, accuracy: Self.loose)
        assertPoint(scaled.position, centre, "the centre is what a scale holds still")
        XCTAssertEqual(scaled.rotation, frame.transform.rotation)
    }

    func testTheKnobTurnsAboutTheCentreAndScalesNothing() {
        let frame = upright()
        let centre = frame.centre
        let drag = ObjectTransformDrag(frame: frame, handle: .rotation,
                                       at: CGPoint(x: centre.x, y: centre.y - 200))
        // A quarter turn clockwise: from straight up to straight right.
        let turned = drag.transform(draggedTo: CGPoint(x: centre.x + 200, y: centre.y))
        XCTAssertEqual(turned.rotation, .pi / 2, accuracy: Self.loose)
        assertPoint(turned.position, centre, "the centre is what a rotation holds still")
        XCTAssertEqual(turned.scale, frame.transform.scale)
    }

    func testAGrabOnTheCentreCannotSendTheLayerToInfinity() {
        let frame = upright()
        // Half a point from the centre: no radius to scale against, and a division that would send
        // the layer off the canvas on the first pixel of movement.
        let drag = ObjectTransformDrag(frame: frame, handle: .topLeft,
                                       at: CGPoint(x: frame.centre.x + 0.5, y: frame.centre.y))
        XCTAssertEqual(drag.transform(draggedTo: CGPoint(x: 1900, y: 900)), frame.transform)
    }

    func testScaleCannotBeDraggedBelowItsFloor() {
        let frame = upright()
        let drag = ObjectTransformDrag(frame: frame, handle: .topLeft, at: frame.corners[0])
        // A hair off the centre: the ratio is essentially zero.
        let collapsed = drag.transform(draggedTo: CGPoint(x: frame.centre.x, y: frame.centre.y + 0.001))
        XCTAssertEqual(collapsed.scale, ObjectTransformDrag.minimumScale, accuracy: Self.epsilon)
    }

    func testTheAnchorIsLatchedAtTheCentreTheDragStartedFrom() {
        let frame = upright()
        let drag = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: frame.corners[2])
        assertPoint(drag.anchor, frame.centre)
        XCTAssertEqual(drag.start, frame.transform)
    }

    // MARK: - Freeform (Move stage 3a)

    /// **A Freeform corner pulls one axis and leaves the other where it was.** The 400×300 box's
    /// bottom-right corner dragged three times as far from the centre *horizontally only* comes back
    /// 1200×300 — which is `aspect == 3` (three times as wide as tall for the same artwork) with the
    /// area factor `sqrt(3)` in `scale`.
    ///
    /// The split is the point: `LayerTransform` has one scale, so a pose that stretched only one axis
    /// had nowhere to be stored, which is why the Move bar's picker was raster-only until this stage.
    ///
    /// Watched failing with the corner arm forced back to the uniform one and `axisScales` made to
    /// ignore the aspect — `main`'s behaviour reached through this stage's API: *("1.0") is not equal
    /// to ("3.0")* on the aspect, and, further down, *("742.16") is not equal to ("300.0") — the axis
    /// the finger did not pull is untouched*. The uniform arm takes the ratio of the two *radii*, so
    /// pulling sideways grows the box vertically by 2.47× as well.
    func testAFreeformCornerStretchesOnlyTheAxisTheFingerPulled() {
        let frame = upright()
        let centre = frame.centre
        let corner = frame.corners[2]                       // bottom-right, (1200, 650)
        let pulled = CGPoint(x: centre.x + (corner.x - centre.x) * 3, y: corner.y)
        let drag = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: corner, freeform: true)
        let pose = drag.pose(draggedTo: pulled)

        XCTAssertEqual(pose.aspect, 3, accuracy: Self.loose, "three times as wide as it is tall")
        XCTAssertEqual(pose.transform.scale, sqrt(3), accuracy: Self.loose,
                       "and the area factor is the geometric mean of the two axis scales")

        let stretched = ObjectTransformFrame(transform: pose.transform, contentSize: frame.contentSize,
                                             aspect: pose.aspect)
        assertPoint(stretched.corners[2], pulled, "the corner arrives under the finger")
        assertPoint(stretched.centre, centre, "and the centre is still what a scale holds still")
        XCTAssertEqual(stretched.corners[1].x - stretched.corners[0].x, 1200, accuracy: Self.loose)
        XCTAssertEqual(stretched.corners[3].y - stretched.corners[0].y, 300, accuracy: Self.loose,
                       "the axis the finger did not pull is untouched")
    }

    /// **Freeform contains Uniform rather than sitting beside it.** Drag a corner along the box's own
    /// diagonal — both axes growing by the same factor — and Freeform produces the pose Uniform would
    /// have: the same scale, and an aspect that has not moved.
    ///
    /// This is the seam an artist would otherwise fall through, and it is why `scale` holds the
    /// *geometric mean* rather than one axis: any other split makes the same visible gesture mean two
    /// different things depending on which segment of the picker is lit.
    ///
    /// It is an invariant rather than a coordinate, so it is true of any correct split — every
    /// symmetric mean of two equal numbers is that number. What it fails against is an arm that is
    /// not a superset of the uniform one at all: watched failing with the stretch measured from the
    /// touch-down point instead of from the anchor (the shape of the *raster* corner arm, which
    /// anchors the opposite corner), *("1.0") is not equal to ("2.0")*.
    func testAFreeformDragAlongTheDiagonalIsTheUniformDrag() {
        let frame = upright()
        let centre = frame.centre
        let corner = frame.corners[2]
        let doubled = CGPoint(x: centre.x + (corner.x - centre.x) * 2,
                              y: centre.y + (corner.y - centre.y) * 2)
        let free = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: corner, freeform: true)
        let fixed = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: corner)

        let pose = free.pose(draggedTo: doubled)
        XCTAssertEqual(pose.transform.scale, fixed.transform(draggedTo: doubled).scale, accuracy: Self.epsilon)
        XCTAssertEqual(pose.aspect, 1, "a diagonal drag changes the size and not the shape")
    }

    /// The stretch is measured in the **box's** axes, not the screen's — so a piece the artist has
    /// already turned stretches along the edges they can see. Same reason the rotation arm measures
    /// its angles about the anchor rather than about the origin.
    ///
    /// The box is turned a quarter turn, so its own +x axis points down the screen; pulling the
    /// corner *downwards* is therefore a pull along the box's width.
    ///
    /// Watched failing with the corner arm forced back to the uniform one: *("1.0") is not equal to
    /// ("3.0")*.
    func testAFreeformStretchFollowsTheBoxsOwnAxesThroughARotation() {
        let frame = upright(rotation: .pi / 2)
        let centre = frame.centre
        let corner = frame.corners[2]
        // The corner's offset from the centre, in the box's own axes, is (+200, +150); a quarter turn
        // maps that to canvas (-150, +200). Tripling the box's *x* means tripling the canvas y term.
        let pulled = CGPoint(x: centre.x - 150, y: centre.y + 600)
        let drag = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: corner, freeform: true)
        let pose = drag.pose(draggedTo: pulled)

        XCTAssertEqual(pose.aspect, 3, accuracy: Self.loose,
                       "pulling down a box turned on its side stretches its width, not its height")
        XCTAssertEqual(pose.transform.rotation, frame.transform.rotation, "and turns nothing")
    }

    /// **The owner's ruling, 2026-08-26: *"a Freeform stretch survives a switch to Uniform — 3:1 stays
    /// 3:1 and scales from there."*** It falls out of the split rather than needing a rule: the
    /// uniform arm writes `scale` and never touches `aspect`, so a stretched box scaled up stays the
    /// same shape.
    ///
    /// Watched failing with `axisScales` ignoring the aspect: *("1385.64") is not equal to ("2400.0")*
    /// — the box comes back square and `sqrt(3)`× too small, which is the pre-stage behaviour.
    func testAUniformDragLeavesAFreeformStretchWhereItIs() {
        let stretched = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                                       scale: sqrt(3), rotation: 0),
                                             contentSize: CGSize(width: 400, height: 300),
                                             aspect: 3)
        let corner = stretched.corners[2]
        let centre = stretched.centre
        let doubled = CGPoint(x: centre.x + (corner.x - centre.x) * 2,
                              y: centre.y + (corner.y - centre.y) * 2)
        let pose = ObjectTransformDrag(frame: stretched, handle: .bottomRight, at: corner)
            .pose(draggedTo: doubled)

        XCTAssertEqual(pose.aspect, 3, accuracy: Self.epsilon, "3:1 stays 3:1")
        XCTAssertEqual(pose.transform.scale, 2 * sqrt(3), accuracy: Self.loose, "and scales from there")
        let after = ObjectTransformFrame(transform: pose.transform, contentSize: stretched.contentSize,
                                         aspect: pose.aspect)
        XCTAssertEqual(after.corners[1].x - after.corners[0].x, 2400, accuracy: Self.loose)
        XCTAssertEqual(after.corners[3].y - after.corners[0].y, 600, accuracy: Self.loose)
    }

    /// A stretched box hit-tests its **stretched** interior. `contains` maps the point back through
    /// the pose, so a point that was inside the square box and is outside the stretched one is
    /// declined — otherwise the move band would answer for empty canvas beside a narrowed piece.
    ///
    /// Watched failing with `axisScales` made to ignore the aspect: both halves go red at once, which
    /// is the point — the box would draw stretched and hit-test square.
    func testAStretchedBoxHitTestsTheShapeItDraws() {
        var frame = upright()
        frame.aspect = 4                                  // 800 wide, 150 tall
        XCTAssertTrue(frame.contains(CGPoint(x: 1380, y: 500)), "well inside the widened box")
        XCTAssertFalse(frame.contains(CGPoint(x: 1000, y: 620)),
                       "and outside the narrowed one, though the unstretched box contained it")
        XCTAssertTrue(upright().contains(CGPoint(x: 1000, y: 620)), "fixture precondition")
    }

    /// Neither axis can be collapsed on its own — `minimumScale` is applied per axis before the pose
    /// is derived, so a corner dragged onto the box's own centre line leaves a piece the artist can
    /// still grab rather than an invisible sliver.
    ///
    /// Watched failing with the corner arm forced back to the uniform one: *("1.8") is not equal to
    /// ("0.02")* — one radius ratio floors both axes together or neither.
    func testAFreeformCornerCannotCollapseEitherAxis() {
        let frame = upright()
        let drag = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: frame.corners[2],
                                       freeform: true)
        // Dragged back onto the centre in x, and out to 3× in y.
        let pose = drag.pose(draggedTo: CGPoint(x: frame.centre.x, y: frame.centre.y + 450))
        let axes = ObjectTransformFrame.axisScales(scale: pose.transform.scale, aspect: pose.aspect)
        XCTAssertEqual(axes.x, ObjectTransformDrag.minimumScale, accuracy: Self.loose)
        XCTAssertEqual(axes.y, 3, accuracy: Self.loose, "and the other axis is unaffected by the floor")
    }

    /// **Nothing switched Freeform on where nobody asked for it.**
    ///
    /// The trap this feature was warned about is `allowedHandles`, which defaults to *all cases* — so
    /// a new grip turns itself on everywhere, the whole-layer box included. Freeform sidesteps it by
    /// adding no grip at all, and pays the same tax on the two defaults it *did* add: an
    /// `ObjectTransformFrame` built the way the whole-layer Move box builds one is unstretched, and a
    /// drag built the way `CanvasView`'s whole-layer arm builds one is uniform. Both matter because
    /// `VectorCanvas.setTransform` stores a similarity — a stretched whole layer has nowhere to go,
    /// and would be silently discarded at the gesture's end.
    ///
    /// Watched failing with `freeform:`'s default flipped to `true`: *XCTAssertFalse failed — a drag
    /// that did not ask for Freeform does not get it*, and *("10.5") is not equal to ("1.0")* on the
    /// aspect. **Two tests written years before this one went red with it** —
    /// `testACornerScalesAboutTheCentreAndTurnsNothing` and `testScaleCannotBeDraggedBelowItsFloor` —
    /// so the whole-layer box was already partly defended; this states the rule outright.
    func testTheWholeLayerBoxIsUnstretchedAndItsDragIsUniform() {
        let frame = ObjectTransformFrame(transform: LayerTransform(position: .zero, scale: 1, rotation: 0),
                                         contentSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(frame.aspect, 1, "a box nobody stretched is square")
        XCTAssertEqual(frame.axisScales.x, frame.axisScales.y, "and its two axes are one number")
        let drag = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: frame.corners[2])
        XCTAssertFalse(drag.isFreeform, "and a drag that did not ask for Freeform does not get it")
        XCTAssertEqual(drag.pose(draggedTo: CGPoint(x: 900, y: 100)).aspect, 1)
    }

    // MARK: - The box-only knob (Move stage 3b, phase 1)
    //
    // A second knob that turns the handle box alone, leaving the drawing exactly where it is —
    // LASSO_MOVE.md §5.19–21, TODO item (20). The whole feature is the claim that `boxAngle` is
    // *chrome*: it moves the outline, the six grips and the hit test, and reaches no geometry at
    // all. The tests below assert both halves of that, and `LassoMoveLogicTests`'
    // `testANonZeroBoxAngleChangesNoSampleAndNoPixel` asserts the half that would cost artwork.

    private func turned(_ boxAngle: CGFloat, rotation: CGFloat = 0,
                        scale: CGFloat = 1) -> ObjectTransformFrame {
        ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                       scale: scale, rotation: rotation),
                             contentSize: CGSize(width: 400, height: 300), aspect: 1,
                             boxAngle: boxAngle)
    }

    /// **The mirror image of `testTheKnobTurnsAboutTheCentreAndScalesNothing`, and the feature's
    /// whole point.** The same finger sweep that the green knob turns the drawing with turns the box
    /// alone here — and `transform` comes back *bit for bit* what it went in as, not merely equal to
    /// within a tolerance. A "rotate by zero" that wrote `start.rotation + 0` would pass an
    /// approximate comparison and still be a leak, because `applyToVectorFloat` would then see a
    /// changed pose and re-map every lifted element through it.
    ///
    /// Watched failing with the `.boxRotation` arm writing `turned.rotation` the way `.rotation`
    /// does: *("1.5707963267948966") is not equal to ("0.0") — the drawing must not turn*, and the
    /// box angle left at zero.
    func testTheBoxKnobTurnsTheBoxAndLeavesTheTransformBitForBit() {
        let frame = upright()
        let centre = frame.centre
        // Grabbed below the box and swept a quarter turn — the same sweep the green knob's test makes
        // above the box, so the two tests differ only in which grip the finger was on.
        let drag = ObjectTransformDrag(frame: frame, handle: .boxRotation,
                                       at: CGPoint(x: centre.x, y: centre.y + 200))
        let pose = drag.pose(draggedTo: CGPoint(x: centre.x - 200, y: centre.y))

        XCTAssertEqual(pose.boxAngle, .pi / 2, accuracy: Self.loose, "the box turned a quarter turn")
        XCTAssertEqual(pose.transform, frame.transform,
                       "and the drawing's transform is bit-for-bit what it was")
        XCTAssertEqual(pose.transform.rotation, frame.transform.rotation, "the drawing must not turn")
        XCTAssertEqual(pose.aspect, frame.aspect, "nor stretch")
        // Sixty deltas and one delta agree, the property every other arm has.
        var last = frame.boxAngle
        for step in 1...60 {
            let t = CGFloat(step) / 60
            last = drag.pose(draggedTo: CGPoint(x: centre.x - 200 * t,
                                                y: centre.y + 200 - 200 * t)).boxAngle
        }
        XCTAssertEqual(last, pose.boxAngle, accuracy: Self.loose, "sixty deltas land where one does")
    }

    /// **The other direction, and it is the one that keeps the lift invariant alive.** Every arm that
    /// is *not* the box knob passes the box angle straight through — so an artist who hand-fits the
    /// box and then moves, scales, turns or stretches the piece keeps their fit, and no arm can
    /// quietly straighten it.
    ///
    /// Watched failing with every arm's `boxAngle:` argument deleted so the field fell back to a
    /// default: *("0.0") is not equal to ("0.6") +/- ("1e-06") — topLeft, freeform false*, sixteen
    /// times over — every corner in both modes, the move band and the green knob — and it took
    /// `testTheGreenKnobTurnsTheDrawingAndCarriesTheHandFittedBoxWithIt` down with it.
    ///
    /// **That mutation no longer compiles, and that is the better outcome.** `Pose.boxAngle` carries
    /// no default precisely so a dropped pass-through is a build error rather than a red test; this
    /// test is the second line, kept because the *first* line only guards construction and this one
    /// guards the arithmetic that fills it in.
    func testEveryOtherArmPassesTheBoxAngleThroughUnchanged() {
        let frame = turned(0.6)
        let start = CGPoint(x: 1120, y: 620)
        let end = CGPoint(x: 940, y: 380)
        for handle in ObjectTransformFrame.Handle.allCases where handle != .boxRotation {
            for freeform in [false, true] {
                let drag = ObjectTransformDrag(frame: frame, handle: handle, at: start,
                                               freeform: freeform)
                XCTAssertEqual(drag.pose(draggedTo: end).boxAngle, 0.6, accuracy: Self.loose,
                               "\(handle), freeform \(freeform)")
            }
        }
    }

    /// The green knob turns the drawing; the box goes with it, because the box is drawn at
    /// `transform.rotation + boxAngle` and only the first term moved. A hand-fitted box therefore
    /// stays fitted through a rotation of the ink, which is the behaviour that makes the fit worth
    /// making.
    func testTheGreenKnobTurnsTheDrawingAndCarriesTheHandFittedBoxWithIt() {
        let frame = turned(0.6)
        let centre = frame.centre
        let drag = ObjectTransformDrag(frame: frame, handle: .rotation,
                                       at: CGPoint(x: centre.x, y: centre.y - 200))
        let pose = drag.pose(draggedTo: CGPoint(x: centre.x + 200, y: centre.y))
        XCTAssertEqual(pose.transform.rotation, .pi / 2, accuracy: Self.loose, "the drawing turned")
        XCTAssertEqual(pose.boxAngle, 0.6, accuracy: Self.loose, "and the hand-fit rode along")

        // The corners of the pose: turned by the sum, so the box kept its offset from the ink.
        let after = ObjectTransformFrame(transform: pose.transform, contentSize: frame.contentSize,
                                         aspect: pose.aspect, boxAngle: pose.boxAngle)
        let sumOnly = ObjectTransformFrame(transform: LayerTransform(position: centre, scale: 1,
                                                                     rotation: .pi / 2 + 0.6),
                                           contentSize: frame.contentSize)
        assertPoint(after.corners[0], sumOnly.corners[0], "the box is drawn at the sum of the two")
        // Fixture precondition: the hand-fit is visible, i.e. it is not the box the ink alone gives.
        let inkOnly = ObjectTransformFrame(transform: pose.transform, contentSize: frame.contentSize)
        XCTAssertGreaterThan(hypot(after.corners[0].x - inkOnly.corners[0].x,
                                   after.corners[0].y - inkOnly.corners[0].y), 1)
    }

    /// **Everything the box draws and hits follows the box angle**, because `projected`, `local`,
    /// `corners`, both knob positions and `handleLayout` all read one private `drawnAngle` and none
    /// of them reads `transform.rotation` any more.
    ///
    /// Asserted as an *identity* rather than as coordinates: a box turned by `φ` with the ink
    /// straight is the same box as one turned by `φ` with the ink, for every drawn purpose. That is
    /// false for any implementation that routed some of the five through the sum and some through
    /// `transform.rotation`.
    ///
    /// Watched failing with `local(_:)` left reading `-transform.rotation` while `projected` read the
    /// sum — **the corners agree and containment disagrees**, which is the box drawn in one place and
    /// hit in another, exactly the defect the single-source-of-truth discipline exists to prevent:
    /// *("true") is not equal to ("false") — containment of (1190.0, 360.0) at 0.4*, and beside it
    /// *("Optional(…Handle.body)") is not equal to ("nil") — target at (1190.0, 360.0), 0.4*, i.e. a
    /// touch on bare canvas outside the visible box would have grabbed the move band. It is the only
    /// test in the suite that goes red for it.
    func testTheDrawnBoxAndTheHitBoxBothFollowTheBoxAngle() {
        for angle in [CGFloat(0.4), CGFloat.pi / 2, 2.7, -1.2] {
            let byBox = turned(angle)
            let byInk = upright(rotation: angle)
            for i in 0..<4 {
                assertPoint(byBox.corners[i], byInk.corners[i], "corner \(i) at \(angle)")
            }
            assertPoint(byBox.rotationHandlePosition(offset: 36),
                        byInk.rotationHandlePosition(offset: 36), "green knob at \(angle)")
            assertPoint(byBox.boxRotationHandlePosition(offset: 36),
                        byInk.boxRotationHandlePosition(offset: 36), "yellow knob at \(angle)")
            for probe in [CGPoint(x: 1190, y: 360), CGPoint(x: 1000, y: 620), CGPoint(x: 830, y: 470),
                          CGPoint(x: 700, y: 400), byBox.centre] {
                XCTAssertEqual(byBox.contains(probe), byInk.contains(probe),
                               "containment of \(probe) at \(angle)")
                XCTAssertEqual(byBox.target(at: probe, reach: 22, rotationOffset: 36),
                               byInk.target(at: probe, reach: 22, rotationOffset: 36),
                               "target at \(probe), \(angle)")
            }
            // And the drift guard, restated on a turned box: a probe on a drawn grip finds it.
            for entry in byBox.handleLayout(rotationOffset: 36) {
                XCTAssertEqual(byBox.handle(nearest: entry.position, reach: 1, rotationOffset: 36),
                               entry.handle, "\(entry.handle) at box angle \(angle)")
            }
        }
    }

    /// The yellow knob stands off the **bottom** edge — away from the artwork, and exactly opposite
    /// the green one, at every angle the box can be drawn at.
    ///
    /// **`XCTUnwrap`, not `!`, and that is not style.** The neighbouring knob test force-unwraps, and
    /// a mutation that dropped `.boxRotation` from `handleLayout` turned that into a `fatalError`
    /// which **killed the test runner 15 tests into a 118-test suite** — four legitimate failures
    /// reported, the rest of the run simply gone. A truncated run reads like a short one, which is
    /// the banner-versus-count trap arriving through a third door. One nil handle should fail one
    /// test.
    func testTheBoxKnobStandsOffTheBottomEdgeOppositeTheGreenOne() throws {
        let poses: [(rotation: CGFloat, boxAngle: CGFloat)] =
            [(0, 0), (0.7, 0), (0, 0.7), (1.2, -2.0), (CGFloat.pi, 0.3)]
        for (rotation, boxAngle) in poses {
            let frame = turned(boxAngle, rotation: rotation)
            let knob = try XCTUnwrap(position(of: .boxRotation, in: frame))
            let corners = frame.corners
            let bottomCentre = CGPoint(x: (corners[2].x + corners[3].x) / 2,
                                       y: (corners[2].y + corners[3].y) / 2)
            XCTAssertEqual(hypot(knob.x - bottomCentre.x, knob.y - bottomCentre.y), 36,
                           accuracy: Self.loose, "stands off by its offset (\(rotation), \(boxAngle))")
            XCTAssertGreaterThan(hypot(knob.x - frame.centre.x, knob.y - frame.centre.y),
                                 hypot(bottomCentre.x - frame.centre.x,
                                       bottomCentre.y - frame.centre.y),
                                 "and away from the centre, not into the artwork")
            // Diametrically opposite the green knob: the two offsets are negations, so the box's
            // centre is the midpoint of the two knobs.
            let green = try XCTUnwrap(position(of: .rotation, in: frame))
            assertPoint(CGPoint(x: (green.x + knob.x) / 2, y: (green.y + knob.y) / 2), frame.centre,
                        "the centre is the midpoint of the two knobs")
        }
    }

    /// **The two knobs cannot land under one finger, at any zoom or any box size** — the concern
    /// that put them on opposite edges rather than side by side. Their separation is
    /// `height + 2·offset`, so it is at least `2·offset`; the offset is 36 screen points and the
    /// reach 22, so the gap is at least `72/22 = 3.27` reaches however small the box is drawn.
    ///
    /// Asserted through the shipping view at a thumbnail zoom on a 20×20 box, where the four
    /// *corners* genuinely do all cover one finger — which is what makes the fixture a real test of
    /// the nearest-within-reach rule rather than of a box nothing overlaps in.
    func testTheTwoKnobsStayDistinguishableAtAThumbnailZoom() {
        let view = ObjectTransformOverlayView(frame: CGRect(x: 0, y: 0, width: 2048, height: 1024))
        for canvasScale in [CGFloat(0.125), 0.3, 1] {
            let frame = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                                       scale: 1, rotation: 0),
                                             contentSize: CGSize(width: 20, height: 20),
                                             aspect: 1, boxAngle: 0.5)
            view.update(isActive: true, frame: frame, canvasScale: canvasScale)
            let green = frame.rotationHandlePosition(offset: view.rotationOffset)
            let yellow = frame.boxRotationHandlePosition(offset: view.rotationOffset)
            XCTAssertGreaterThan(hypot(green.x - yellow.x, green.y - yellow.y), 2 * view.handleReach,
                                 "the two knobs are more than a finger apart at \(canvasScale)×")
            XCTAssertLessThan(hypot(frame.corners[0].x - frame.corners[1].x,
                                    frame.corners[0].y - frame.corners[1].y), 2 * view.handleReach,
                              "fixture precondition: this box's corners really do overlap")
            XCTAssertEqual(view.target(at: green), .rotation, "at \(canvasScale)×")
            XCTAssertEqual(view.target(at: yellow), .boxRotation, "at \(canvasScale)×")
        }
    }

    /// **`boxAngle == 0` is the frame that existed before this field did, to the bit.** `drawnAngle`
    /// is `transform.rotation + 0`, which is `transform.rotation` exactly — no `sin`/`cos` of a sum,
    /// no reassociation — so every box in the app that nobody has turned draws and hits precisely
    /// where it always did.
    ///
    /// The same discipline `axisScales` states for `aspect == 1`, and it is checked with `==` rather
    /// than an accuracy for the same reason: a tolerance would hide a rewrite that changed the
    /// arithmetic while leaving the answer close.
    func testAZeroBoxAngleIsBitIdenticalToTheFrameBeforeItExisted() {
        for rotation in [CGFloat(0), 0.4, CGFloat.pi / 2, 2.7, -1.2] {
            for scale in [CGFloat(0.3), 1, 3] {
                let explicit = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                                              scale: scale, rotation: rotation),
                                                    contentSize: CGSize(width: 400, height: 300),
                                                    aspect: 1, boxAngle: 0)
                let defaulted = upright(scale: scale, rotation: rotation)
                XCTAssertEqual(explicit, defaulted, "the default is zero (\(scale), \(rotation))")
                for i in 0..<4 {
                    XCTAssertEqual(explicit.corners[i].x, defaulted.corners[i].x)
                    XCTAssertEqual(explicit.corners[i].y, defaulted.corners[i].y)
                }
                XCTAssertEqual(explicit.rotationHandlePosition(offset: 36).x,
                               defaulted.rotationHandlePosition(offset: 36).x)
                XCTAssertEqual(explicit.rotationHandlePosition(offset: 36).y,
                               defaulted.rotationHandlePosition(offset: 36).y)
                // And a drag latched from it answers the same, which is what reaches the model.
                let drag = ObjectTransformDrag(frame: explicit, handle: .bottomRight,
                                               at: explicit.corners[2])
                XCTAssertEqual(drag.startBoxAngle, 0)
                XCTAssertEqual(drag.pose(draggedTo: CGPoint(x: 1400, y: 800)).transform,
                               ObjectTransformDrag(frame: defaulted, handle: .bottomRight,
                                                   at: defaulted.corners[2])
                                   .pose(draggedTo: CGPoint(x: 1400, y: 800)).transform)
            }
        }
    }

    /// A collapsed box refuses the box knob's touch the same way it refuses every other, because
    /// `local(_:)` guards on the axis scales and the knob's position rides on `projected`. The knob
    /// is emitted (it is a point, not an area) and simply sits on the collapsed centre.
    func testADegenerateBoxIsNoWorseWithTheBoxKnobThanWithout() {
        let collapsed = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 10, y: 10),
                                                                       scale: 0, rotation: 0),
                                             contentSize: CGSize(width: 40, height: 40),
                                             aspect: 1, boxAngle: 0.8)
        XCTAssertFalse(collapsed.contains(CGPoint(x: 10, y: 10)))
        XCTAssertEqual(collapsed.handleLayout(rotationOffset: 36).count, 6)
    }

    // MARK: - The stretch axis (Move stage 3b, phase 2)
    //
    // A stretch made about a hand-turned box records the axis it was made about — LASSO_MOVE.md
    // §5.20 — which is what un-greys Freeform. The map becomes `R(ρ+φ)·S·R(−φ)`, a rotation on both
    // sides of the scale, which is the singular value decomposition of a general 2×2; with the
    // position that is six numbers and exactly a general affine. `boxAngle` is still chrome: it says
    // where the box is *now*, and `stretchAxis` says where it was when a stretch was made.

    /// The linear part of a pose's map, read out of the shipping `affine` so the tests below compare
    /// against matrices they built themselves rather than against a second copy of the expression.
    /// Position and pivot cancel out of `a`/`b`/`c`/`d` entirely.
    private func linear(of pose: ObjectTransformDrag.Pose) -> CGAffineTransform {
        VectorCanvas.affine(from: pose.transform, aspect: pose.aspect,
                            stretchAxis: pose.stretchAxis, pivot: .zero)
    }

    private func assertLinear(_ actual: CGAffineTransform, _ expected: CGAffineTransform,
                              accuracy: CGFloat = ObjectTransformLogicTests.loose,
                              _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.a, expected.a, accuracy: accuracy, "a — " + message, file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, "b — " + message, file: file, line: line)
        XCTAssertEqual(actual.c, expected.c, accuracy: accuracy, "c — " + message, file: file, line: line)
        XCTAssertEqual(actual.d, expected.d, accuracy: accuracy, "d — " + message, file: file, line: line)
    }

    /// **`stretchAxis == 0` is the map that existed before the field did, to the bit** — the claim the
    /// whole generalisation rests on, and the reason no existing document, call site or test changes.
    /// The expected value is the old expression *written out here*, so this is a statement about the
    /// map that shipped rather than a call to the new one.
    ///
    /// **And the second reduction, which is the one that is easy to get wrong**: at `aspect == 1` the
    /// axis is a no-op for *any* φ, because a scalar commutes with a rotation. `affine` states that
    /// as a branch rather than computing `R(ρ+φ)·s·R(−φ)` and hoping; computing it leaves a
    /// similarity that is only nearly one, and `applyToVectorFloat` dispatches on `aspect != 1`
    /// exactly while `mapping(_:throughSimilarity:)` asserts the shape it is handed. Both guards in
    /// `LassoMoveLogicTests` — the zero-delta nudge and the non-zero box angle — depend on it.
    func testAZeroStretchAxisIsTheMapThatExistedBeforeItDid() {
        let pivot = CGPoint(x: 37, y: -11)
        for rotation in [CGFloat(0), 0.4, CGFloat.pi / 2, 2.7, -1.2] {
            for scale in [CGFloat(0.3), 1, 3] {
                for aspect in [CGFloat(1), 3, 1.0 / 3.0, 0.77] {
                    let t = LayerTransform(position: CGPoint(x: 1000, y: 500), scale: scale,
                                           rotation: rotation)
                    let s = ObjectTransformFrame.axisScales(scale: scale, aspect: aspect)
                    let before = CGAffineTransform.identity
                        .translatedBy(x: t.position.x, y: t.position.y)
                        .rotated(by: t.rotation)
                        .scaledBy(x: s.x, y: s.y)
                        .translatedBy(x: -pivot.x, y: -pivot.y)
                    let note = "\(rotation), \(scale), \(aspect)"
                    XCTAssertEqual(VectorCanvas.affine(from: t, aspect: aspect, stretchAxis: 0,
                                                       pivot: pivot), before, note)
                    guard aspect == 1 else { continue }
                    for axis in [CGFloat(0.6), -1.3, 2.2] {
                        XCTAssertEqual(VectorCanvas.affine(from: t, aspect: 1, stretchAxis: axis,
                                                           pivot: pivot), before,
                                       "an unstretched pose ignores its axis — \(note), \(axis)")
                    }
                }
            }
        }
    }

    /// **A stretch on a turned box pulls along the box's *visible* axes**, and the expected answer is
    /// arithmetic done by hand rather than a second call into the code under test.
    ///
    /// The 400×300 box is turned a quarter turn by the yellow knob alone, so the drawing is still
    /// upright and the box's own +x axis points *down* the screen. Pulling the bottom-right grip
    /// three times as far down therefore triples the box's **width**, and the map it implies is
    /// `R(π/2)·diag(3,1)·R(−π/2)`, which is `diag(1, 3)` — canvas x untouched, canvas y tripled.
    ///
    /// Phase 1 measured this drag from `start.rotation`, the *ink's* angle, which here is 0 — so it
    /// would have read the same finger movement as a pull along the box's height and stretched the
    /// drawing in the direction the artist did not point. That is what phase 1's caption refused
    /// rather than doing, and what the recorded axis replaces.
    func testAStretchOnATurnedBoxPullsAlongTheBoxsVisibleAxes() {
        let frame = turned(.pi / 2)
        let centre = frame.centre
        let (cw, ch) = (frame.contentSize.width, frame.contentSize.height)
        // The grip's offset from the centre is (+cw/2, +ch/2) in the box's own axes; a quarter turn
        // maps that to canvas (−ch/2, +cw/2). Tripling the box's x means tripling the canvas y term.
        let pulled = CGPoint(x: centre.x - ch / 2, y: centre.y + 3 * cw / 2)
        let drag = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: frame.corners[2],
                                       freeform: true)
        let pose = drag.pose(draggedTo: pulled)

        XCTAssertEqual(pose.aspect, 3, accuracy: Self.loose, "three times as wide as it is tall")
        XCTAssertEqual(pose.transform.scale, sqrt(3), accuracy: Self.loose)
        XCTAssertEqual(pose.stretchAxis, .pi / 2, accuracy: Self.epsilon,
                       "and it recorded the axis it was made about")
        XCTAssertEqual(pose.transform.rotation, 0, accuracy: Self.epsilon, "the drawing did not turn")
        XCTAssertEqual(pose.boxAngle, .pi / 2, accuracy: Self.epsilon, "nor did the box")

        assertLinear(linear(of: pose), CGAffineTransform(scaleX: 1, y: 3),
                     "canvas x is untouched and canvas y is tripled")
        // And the grip arrives under the finger, which is the half an artist would notice first.
        let after = ObjectTransformFrame(transform: pose.transform, contentSize: frame.contentSize,
                                         aspect: pose.aspect, boxAngle: pose.boxAngle,
                                         stretchAxis: pose.stretchAxis)
        assertPoint(after.corners[2], pulled)
    }

    /// **Two stretches about two different axes compose into the product matrix** — the composition
    /// problem, and the SVD round trip that answers it, asserted against a matrix this test
    /// multiplies out itself.
    ///
    /// Stretch a straight box 3:1 along its own x; turn the box 45° with the yellow knob; stretch it
    /// twice as wide along *that* axis. `(scale, aspect, rotation, stretchAxis)` cannot hold two
    /// stretches about two axes as written, so `ObjectTransformFrame.decompose` reads the pose back
    /// out of `R(45°)·diag(2,1)·R(−45°) · diag(3,1)`.
    ///
    /// **Three hand-computed numbers, and the first is the honest consequence.** That product is
    /// `[[4.5, 0.5], [1.5, 1.5]]`, whose polar factor is a rotation of `atan2(1, 6) = 0.16515` rad:
    /// composing two stretches about different axes *genuinely turns the ink*, so
    /// `transform.rotation` genuinely moves and the box turns with it. `sqrt(|det|)` is `sqrt(6)`,
    /// and the two singular values are `hypot(3, 0.5) ± hypot(1.5, 1)`.
    func testTwoStretchesAboutDifferentAxesComposeIntoTheProductMatrix() {
        // 3:1 along the box's own x, on a box nobody has turned: aspect 3, scale √3, axis 0.
        let first = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                                   scale: sqrt(3), rotation: 0),
                                         contentSize: CGSize(width: 400, height: 300),
                                         aspect: 3, boxAngle: .pi / 4, stretchAxis: 0)
        XCTAssertEqual(first.axisScales.x, 3, accuracy: Self.loose, "fixture precondition")
        XCTAssertEqual(first.axisScales.y, 1, accuracy: Self.loose)

        // The grip's offset in the box's own axes is (600, 150); doubling the x term is the drag.
        let root = CGFloat(2).squareRoot()
        let centre = first.centre
        let pulled = CGPoint(x: centre.x + (1200 - 150) / root, y: centre.y + (1200 + 150) / root)
        let pose = ObjectTransformDrag(frame: first, handle: .bottomRight, at: first.corners[2],
                                       freeform: true).pose(draggedTo: pulled)

        let expected = CGAffineTransform.identity
            .scaledBy(x: 3, y: 1)
            .concatenating(CGAffineTransform.identity
                .rotated(by: .pi / 4).scaledBy(x: 2, y: 1).rotated(by: -.pi / 4))
        assertLinear(linear(of: pose), expected, "the pose is the product of the two stretches")

        XCTAssertEqual(pose.transform.rotation, atan2(CGFloat(1), CGFloat(6)), accuracy: Self.loose,
                       "two stretches about different axes turn the ink, and the pose says so")
        XCTAssertEqual(pose.transform.scale, sqrt(6), accuracy: Self.loose,
                       "the area factor is the root of the product of the two determinants")
        let axes = ObjectTransformFrame.axisScales(scale: pose.transform.scale, aspect: pose.aspect)
        XCTAssertEqual(axes.x, hypot(CGFloat(3), 0.5) + hypot(CGFloat(1.5), 1), accuracy: Self.loose)
        XCTAssertEqual(axes.y, hypot(CGFloat(3), 0.5) - hypot(CGFloat(1.5), 1), accuracy: Self.loose)
        XCTAssertEqual(pose.boxAngle, .pi / 4, "and the hand-fitted box is untouched by all of it")
    }

    /// **A stretch about the axis the piece was last stretched about needs no decomposition at all**,
    /// and takes the arithmetic this arm had before phase 2 — two diagonal matrices multiplied. The
    /// composed answer agrees with it, which is what makes the fast arm an optimisation of the slow
    /// one rather than a second rule.
    func testAStretchAboutTheRecordedAxisComposesWithoutTurningAnything() {
        for axis in [CGFloat(0), 0.9, -2.1] {
            let frame = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                                       scale: sqrt(3), rotation: 0.35),
                                             contentSize: CGSize(width: 400, height: 300),
                                             aspect: 3, boxAngle: axis, stretchAxis: axis)
            let centre = frame.centre
            let axes = frame.axisScales
            let beta = frame.transform.rotation + axis
            // Double the box's x, in the box's own axes, turned out into canvas space by hand.
            let (bx, by) = (2 * axes.x * 200, axes.y * 150)
            let pulled = CGPoint(x: centre.x + bx * cos(beta) - by * sin(beta),
                                 y: centre.y + bx * sin(beta) + by * cos(beta))
            let pose = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: frame.corners[2],
                                           freeform: true).pose(draggedTo: pulled)

            XCTAssertEqual(pose.transform.rotation, 0.35,
                           "a stretch about the recorded axis turns nothing — axis \(axis)")
            XCTAssertEqual(pose.stretchAxis, axis, "and records the same axis again")
            let after = ObjectTransformFrame.axisScales(scale: pose.transform.scale,
                                                        aspect: pose.aspect)
            XCTAssertEqual(after.x, 2 * axes.x, accuracy: Self.loose, "axis \(axis)")
            XCTAssertEqual(after.y, axes.y, accuracy: Self.loose,
                           "and the axis the finger did not pull is untouched — axis \(axis)")
        }
    }

    /// **§5.17 survives the extra angle untouched: a stretch scales the ink by `sqrt(|det|)`, and a
    /// rotation has determinant 1.** So neither `stretchAxis` nor `rotation` can change a stroke's
    /// width — only the two axis scales can — and `VectorCanvas.mapping(_:throughStretch:)`, which
    /// reads exactly that number, is untouched by phase 2.
    func testTheDeterminantAndThereforeTheInkWidthIgnoresTheStretchAxis() {
        for aspect in [CGFloat(1), 3, 0.4] {
            for scale in [CGFloat(0.5), 2] {
                let t = LayerTransform(position: CGPoint(x: 1000, y: 500), scale: scale, rotation: 1.1)
                let base = VectorCanvas.affine(from: t, aspect: aspect, stretchAxis: 0, pivot: .zero)
                let expected = abs(base.a * base.d - base.b * base.c)
                XCTAssertEqual(expected, scale * scale, accuracy: Self.loose, "fixture precondition")
                for axis in [CGFloat(0.3), -1.4, 2.9] {
                    let m = VectorCanvas.affine(from: t, aspect: aspect, stretchAxis: axis, pivot: .zero)
                    XCTAssertEqual(abs(m.a * m.d - m.b * m.c), expected, accuracy: Self.loose,
                                   "\(aspect), \(scale), \(axis)")
                }
            }
        }
    }

    /// **Every arm that is not the Freeform corner passes the stretch axis through unchanged** — the
    /// mirror of `testEveryOtherArmPassesTheBoxAngleThroughUnchanged`, and the reason a hand-fitted
    /// stretch survives a move, a uniform scale, either knob, and a Freeform drag that changes
    /// nothing.
    ///
    /// **`Pose.stretchAxis` carries no default**, so a dropped pass-through is a build error rather
    /// than a red test; this is the second line, guarding the arithmetic the compiler cannot see.
    func testEveryOtherArmPassesTheStretchAxisThroughUnchanged() {
        let frame = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                                   scale: 1, rotation: 0),
                                         contentSize: CGSize(width: 400, height: 300),
                                         aspect: 3, boxAngle: 0.6, stretchAxis: 0.6)
        let start = CGPoint(x: 1120, y: 620)
        let end = CGPoint(x: 940, y: 380)
        for handle in ObjectTransformFrame.Handle.allCases {
            for freeform in [false, true] {
                // The one gesture that is *allowed* to write it is a Freeform corner, and on this
                // frame it writes the same 0.6 back — the box is turned to the axis of the stretch.
                let drag = ObjectTransformDrag(frame: frame, handle: handle, at: start,
                                               freeform: freeform)
                XCTAssertEqual(drag.pose(draggedTo: end).stretchAxis, 0.6, accuracy: Self.loose,
                               "\(handle), freeform \(freeform)")
            }
        }
    }

    /// **The green knob turns a stretched piece rigidly, and that is arithmetic rather than a
    /// choice.** The map is `R(ρ+φ)·S·R(−φ)`, so adding δ to ρ pre-multiplies the whole thing by
    /// `R(δ)`: the piece turns about its centre carrying whatever stretch it has, instead of the
    /// stretch being re-aimed under it.
    ///
    /// Watched failing with the `.rotation` arm made to add its sweep to `stretchAxis` as well — the
    /// plausible wrong reading of "the box's axes turn with the box".
    func testTheGreenKnobTurnsAStretchedPieceRigidly() {
        let frame = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                                   scale: sqrt(3), rotation: 0),
                                         contentSize: CGSize(width: 400, height: 300),
                                         aspect: 3, boxAngle: 0, stretchAxis: 0)
        let centre = frame.centre
        let before = VectorCanvas.affine(from: frame.transform, aspect: frame.aspect,
                                         stretchAxis: frame.stretchAxis, pivot: .zero)
        let drag = ObjectTransformDrag(frame: frame, handle: .rotation,
                                       at: CGPoint(x: centre.x, y: centre.y - 200))
        let pose = drag.pose(draggedTo: CGPoint(x: centre.x + 200, y: centre.y))

        XCTAssertEqual(pose.transform.rotation, .pi / 2, accuracy: Self.loose)
        XCTAssertEqual(pose.stretchAxis, 0, "the axis the stretch was made about did not move")
        assertLinear(linear(of: pose),
                     before.concatenating(CGAffineTransform(rotationAngle: .pi / 2)),
                     "the whole map is pre-multiplied by the turn")
    }

    // MARK: - The box's own centre (Move stage 3b, phase 3)
    //
    // Phase 3 makes the box's size — and therefore its centre — a live function of `boxAngle`
    // (LASSO_MOVE.md §5.22): the tight box around a diagonal is not centred where the loose
    // axis-aligned one was, so the box has to be able to sit off the transform's own position.
    // `ObjectTransformFrame.contentOffset` is where that lives. These two tests are the *frame's*
    // half of it; `LassoMoveLogicTests` measures the fit itself against real ink.

    /// **Every drawn and hit part of the box moves with `contentOffset`, and the anchor does not.**
    ///
    /// The offset is in the box's own local units, so it is added before the scale and the rotation —
    /// which is the difference between a box that stays attached to its ink when the artist turns or
    /// scales it and one that slides across the screen. The assertion is therefore not "the corners
    /// moved by the offset" but "the corners moved by the offset *carried through the projection*",
    /// which is the same thing as saying the offset box is the un-offset box of a shifted piece of
    /// content: `projected(u + offset) == projectedWithOffset(u)` for every `u`.
    ///
    /// **The second half is the load-bearing one.** `centre` is `transform.position`, and it is what
    /// `ObjectTransformDrag` latches as its `anchor` — the point a corner drag scales about and both
    /// knobs turn about. It has to stay the *geometry's* fixed point, because that is the point
    /// `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` holds still: a drag anchored on the drawn
    /// box's centre instead would scale the ink about a point the map does not hold, and the artist's
    /// drawing would slide out from under a corner they were only resizing.
    func testTheContentOffsetMovesEveryDrawnPartOfTheBoxAndNotTheAnchor() {
        let offset = CGPoint(x: -30, y: 17)
        for (scale, rotation, boxAngle) in [(CGFloat(1), CGFloat(0), CGFloat(0)),
                                            (2.5, 0.7, 0), (0.4, 0, 1.3), (1.6, -0.9, 0.45)] {
            let plain = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 1000, y: 500),
                                                                       scale: scale, rotation: rotation),
                                             contentSize: CGSize(width: 400, height: 300),
                                             boxAngle: boxAngle)
            var shifted = plain
            shifted.contentOffset = offset
            let note = "scale \(scale), rotation \(rotation), boxAngle \(boxAngle)"

            // The projection, and therefore the corners, the two knobs and the move band, all of
            // which are `projected` one call down.
            for u in [CGPoint.zero, CGPoint(x: 200, y: -150), CGPoint(x: -37, y: 96)] {
                assertPoint(shifted.projected(u),
                            plain.projected(CGPoint(x: u.x + offset.x, y: u.y + offset.y)),
                            "the offset rides inside the projection — \(note)")
            }
            for (index, corner) in shifted.corners.enumerated() {
                assertPoint(corner, plain.projected(CGPoint(x: (index == 0 || index == 3 ? -200 : 200) + offset.x,
                                                            y: (index < 2 ? -150 : 150) + offset.y)),
                            "corner \(index) — \(note)")
            }
            // Both knobs stand off the box they belong to, so they move by the same canvas delta the
            // box's own middle did.
            let travel = CGPoint(x: shifted.projected(.zero).x - plain.projected(.zero).x,
                                 y: shifted.projected(.zero).y - plain.projected(.zero).y)
            for (which, a, b) in [("green", shifted.rotationHandlePosition(offset: 36),
                                   plain.rotationHandlePosition(offset: 36)),
                                  ("yellow", shifted.boxRotationHandlePosition(offset: 36),
                                   plain.boxRotationHandlePosition(offset: 36))] {
                assertPoint(a, CGPoint(x: b.x + travel.x, y: b.y + travel.y),
                            "the \(which) knob rides with the box — \(note)")
            }

            // The move band follows the drawn box rather than the transform's position: the box's own
            // middle is inside it, a point half way out to a corner is inside it, and — on an offset
            // this large against a 400×300 box — a point three box-widths the other way is not.
            XCTAssertTrue(shifted.contains(shifted.projected(.zero)),
                          "the band is under the box it draws — \(note)")
            XCTAssertTrue(shifted.contains(shifted.projected(CGPoint(x: 100, y: -75))),
                          "and covers its interior — \(note)")
            XCTAssertFalse(shifted.contains(plain.projected(CGPoint(x: 0, y: -600))),
                           "and not what is outside it — \(note)")
            // Straddling the box's own edge, which is what says the *inverse* carries the offset too
            // and not only the forward projection: without the subtraction in `local`, the point
            // inside reads as `199 + offset` and falls out of a 400×300 box.
            XCTAssertTrue(shifted.contains(shifted.projected(CGPoint(x: 199, y: 149))),
                          "just inside its own corner — \(note)")
            XCTAssertFalse(shifted.contains(shifted.projected(CGPoint(x: 201, y: 151))),
                           "and just outside it — \(note)")

            // And the anchor — the whole point of the separation.
            assertPoint(shifted.centre, plain.centre, accuracy: 0,
                        "`centre` is the transform's position, offset or no offset — \(note)")
            let drag = ObjectTransformDrag(frame: shifted, handle: .boxRotation,
                                           at: shifted.projected(.zero))
            assertPoint(drag.anchor, shifted.transform.position, accuracy: 0,
                        "and a drag turns about the geometry's fixed point — \(note)")
        }
    }

    /// **`contentOffset == .zero` is the frame that existed before this field did, to the bit** — the
    /// same claim `boxAngle == 0` makes one field up, and it is worth an assertion for the same
    /// reason: the default is what every call site outside the Move box's re-fit takes, so a
    /// projection that had gained a rounding step would move every text handle and every whole-layer
    /// grip in the app by it.
    func testAZeroContentOffsetIsBitIdenticalToTheFrameBeforeItExisted() {
        for (scale, rotation, boxAngle, aspect) in [(CGFloat(1), CGFloat(0), CGFloat(0), CGFloat(1)),
                                                    (0.37, 2.1, -0.8, 3), (4, -1.1, 0.6, 0.25)] {
            let frame = ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 811, y: -47),
                                                                       scale: scale, rotation: rotation),
                                             contentSize: CGSize(width: 400, height: 300),
                                             aspect: aspect, boxAngle: boxAngle)
            XCTAssertEqual(frame.contentOffset, .zero, "the default")
            let note = "scale \(scale), rotation \(rotation), boxAngle \(boxAngle), aspect \(aspect)"
            let s = ObjectTransformFrame.axisScales(scale: scale, aspect: aspect)
            for u in [CGPoint.zero, CGPoint(x: 200, y: -150), CGPoint(x: -37.5, y: 96.25)] {
                // The projection written out here rather than called into, so a change to both at
                // once cannot pass this.
                let r = rotation + boxAngle
                let x = u.x * s.x, y = u.y * s.y
                let expected = CGPoint(x: 811 + x * cos(r) - y * sin(r),
                                       y: -47 + x * sin(r) + y * cos(r))
                assertPoint(frame.projected(u), expected, accuracy: 0, "\(u) — \(note)")
            }
        }
    }

    // MARK: - Reading a pose back out of a matrix

    /// **The decomposition is the inverse of the map, over a sweep of every pose the box can hold.**
    /// The matrix is built here out of `rotated`/`scaledBy` primitives rather than through `affine`,
    /// so the two are not the same expression checked against itself.
    ///
    /// **The matrix is what is asserted, and the axis only where it exists.** A square pose has no
    /// principal axis at all — every direction is one — so which angle comes back is arbitrary and
    /// carries no information; what must hold either way is that the four numbers rebuild the matrix
    /// they were read from. `2×2` is in the sweep for exactly that case.
    func testTheDecompositionRoundTripsEveryPose() {
        for rotation in [CGFloat(0), 0.4, -1.2, 2.7] {
            for axis in [CGFloat(0), 0.6, -1.9] {
                for (x, y) in [(CGFloat(3), CGFloat(1)), (1, 3), (0.4, 2.5), (2, 2)] {
                    let m = CGAffineTransform.identity
                        .rotated(by: rotation + axis)
                        .scaledBy(x: x, y: y)
                        .rotated(by: -axis)
                    guard let d = ObjectTransformFrame.decompose(m, preferringAxisNear: axis) else {
                        return XCTFail("a positive-determinant map decomposes — \(rotation), \(axis)")
                    }
                    let note = "\(rotation), \(axis), \(x)×\(y)"
                    XCTAssertEqual(d.rotation, rotation, accuracy: Self.loose, note)
                    XCTAssertEqual(d.x, x, accuracy: Self.loose, note)
                    XCTAssertEqual(d.y, y, accuracy: Self.loose, note)
                    if x != y {
                        XCTAssertEqual(d.stretchAxis, axis, accuracy: Self.loose, note)
                    }
                    assertLinear(CGAffineTransform.identity
                        .rotated(by: d.rotation + d.stretchAxis)
                        .scaledBy(x: d.x, y: d.y)
                        .rotated(by: -d.stretchAxis), m, "rebuilt — " + note)
                }
            }
        }
    }

    /// **A similarity comes back with a zero axis and its own angle**, which is the case that keeps
    /// `aspect == 1 ⟹ the axis is a no-op` true from both directions. `atan2(0, 0)` is 0 by
    /// accident; this is the same 0 on purpose, and the guard above it says so.
    func testASimilarityDecomposesToItsOwnRotationAndNoAxis() {
        for rotation in [CGFloat(0), 0.4, -1.2] {
            for scale in [CGFloat(0.25), 1, 4] {
                let m = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
                guard let d = ObjectTransformFrame.decompose(m, preferringAxisNear: 1.3) else {
                    return XCTFail("a similarity decomposes")
                }
                XCTAssertEqual(d.rotation, rotation, accuracy: Self.loose)
                XCTAssertEqual(d.stretchAxis, 0, "and it is not the axis it was asked to prefer")
                XCTAssertEqual(d.aspect, 1, "exactly 1, not nearly — the dispatch is an == comparison")
                XCTAssertEqual(d.scale, scale, accuracy: Self.loose)
            }
        }
    }

    /// **The two representations of one matrix, and the branch is chrome.**
    /// `R(u)·diag(s₁,s₂)·R(−v)` and `R(u+π/2)·diag(s₂,s₁)·R(−v−π/2)` are the same matrix — the choice
    /// is only which of the box's two axes is called "x". So `preferringAxisNear` can change the
    /// aspect from 3 to ⅓ and the drawn box from wide to tall **without changing the map by one bit**,
    /// which is why the drag asks for the axis it started from: a delta that moves nothing must not
    /// flip the box under the finger.
    func testThePreferredAxisChoosesTheDrawnBoxAndNeverTheMap() {
        let m = CGAffineTransform.identity.rotated(by: 0.5).scaledBy(x: 3, y: 1).rotated(by: -0.5)
        guard let near = ObjectTransformFrame.decompose(m, preferringAxisNear: 0.5),
              let far = ObjectTransformFrame.decompose(m, preferringAxisNear: 0.5 + .pi / 2) else {
            return XCTFail("both decompose")
        }
        XCTAssertEqual(near.x, 3, accuracy: Self.loose)
        XCTAssertEqual(near.y, 1, accuracy: Self.loose)
        XCTAssertEqual(near.stretchAxis, 0.5, accuracy: Self.loose)
        XCTAssertEqual(far.x, 1, accuracy: Self.loose, "the other branch names the short axis first")
        XCTAssertEqual(far.y, 3, accuracy: Self.loose)
        XCTAssertEqual(far.stretchAxis, 0.5 + .pi / 2, accuracy: Self.loose)
        XCTAssertEqual(near.rotation, far.rotation, accuracy: Self.epsilon,
                       "and the rotation is an invariant of the matrix, not of the branch")

        for d in [near, far] {
            let rebuilt = CGAffineTransform.identity
                .rotated(by: d.rotation + d.stretchAxis)
                .scaledBy(x: d.x, y: d.y)
                .rotated(by: -d.stretchAxis)
            assertLinear(rebuilt, m, "both branches rebuild the same matrix")
        }
    }

    /// **A reflection and a collapse are refused rather than answered.** This arrangement has no
    /// signed axis — `aspect` is a ratio and `axisScales` takes its square root — so a negative
    /// determinant has nowhere to go, and letting it come back as a rotation would turn a mirror into
    /// a spin. A reflection is `VectorFloat.mirror`'s job and rides in front of the map.
    ///
    /// `det = q² − r²` in the decomposition's own terms, so `y > 0` *is* `det > 0`; the two cases
    /// below are the same guard reached from either side of zero.
    func testTheDecompositionRefusesAReflectionAndACollapse() {
        let reflection = CGAffineTransform.identity.rotated(by: 0.4).scaledBy(x: -2, y: 3)
        XCTAssertLessThan(reflection.a * reflection.d - reflection.b * reflection.c, 0,
                          "fixture precondition")
        XCTAssertNil(ObjectTransformFrame.decompose(reflection, preferringAxisNear: 0))
        XCTAssertNil(ObjectTransformFrame.decompose(CGAffineTransform(scaleX: 3, y: 0),
                                                    preferringAxisNear: 0),
                     "a collapsed axis has no pose either")
        XCTAssertNil(ObjectTransformFrame.decompose(.init(scaleX: 0, y: 0), preferringAxisNear: 0))
        // …and a near-singular one still answers, so the refusal is a real boundary and not a
        // tolerance: an axis 400 times shorter than the other is a sliver the artist can still grab.
        let sliver = CGAffineTransform.identity.rotated(by: 0.4).scaledBy(x: 4, y: 0.01)
        guard let d = ObjectTransformFrame.decompose(sliver, preferringAxisNear: 0) else {
            return XCTFail("a positive determinant, however small, has a pose")
        }
        XCTAssertEqual(d.aspect, 400, accuracy: 1e-3)
        XCTAssertEqual(d.rotation, 0.4, accuracy: Self.loose)
    }

    // MARK: - The live drag, expressed to Core Animation

    /// The claim the whole (c) fix rests on: assigning this affine to the already-rendered image
    /// layer puts every pixel where a re-render at `current` would have put it.
    ///
    /// Asserted as a **mapping**, not as a matrix, because `UIView.transform` is applied about the
    /// view's centre and the conjugation that accounts for that is silently correct for a pure
    /// translation and wrong for every scale and every rotation.
    func testTheLiveViewTransformShowsWhatARerenderWouldHave() {
        let size = CGSize(width: 2048, height: 1024)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let probes = [CGPoint(x: 0, y: 0), CGPoint(x: 2048, y: 1024), centre,
                      CGPoint(x: 300, y: 800), CGPoint(x: 1700, y: 120)]

        let bases: [CGAffineTransform] = [
            .identity,
            CGAffineTransform(translationX: 120, y: -40),
            CGAffineTransform(rotationAngle: 0.6).concatenating(CGAffineTransform(translationX: 30, y: 70))
        ]
        let currents: [CGAffineTransform] = [
            CGAffineTransform(translationX: 55, y: -90),
            CGAffineTransform(scaleX: 1.8, y: 1.8),
            CGAffineTransform(rotationAngle: -1.1),
            CGAffineTransform(scaleX: 0.4, y: 0.4)
                .concatenating(CGAffineTransform(rotationAngle: 2.2))
                .concatenating(CGAffineTransform(translationX: 400, y: 200))
        ]

        for base in bases {
            for current in currents {
                let view = LiveLayerTransform.viewTransform(from: base, to: current, inBoundsOfSize: size)
                let delta = base.inverted().concatenating(current)
                for probe in probes {
                    // What UIKit does with a view transform: about the centre, not about the origin.
                    let shown = CGPoint(x: centre.x + view.a * (probe.x - centre.x) + view.c * (probe.y - centre.y) + view.tx,
                                        y: centre.y + view.b * (probe.x - centre.x) + view.d * (probe.y - centre.y) + view.ty)
                    assertPoint(shown, probe.applying(delta), accuracy: 1e-6,
                                "a pixel drawn at \(probe) under the base must land where the "
                                + "re-render would have put it")
                }
            }
        }
    }

    func testTheLiveViewTransformIsIdentityWhenNothingHasMovedYet() {
        let t = CGAffineTransform(rotationAngle: 0.9).concatenating(CGAffineTransform(translationX: 5, y: 5))
        let view = LiveLayerTransform.viewTransform(from: t, to: t,
                                                    inBoundsOfSize: CGSize(width: 2048, height: 1024))
        XCTAssertEqual(view.a, 1, accuracy: 1e-9)
        XCTAssertEqual(view.d, 1, accuracy: 1e-9)
        XCTAssertEqual(view.tx, 0, accuracy: 1e-6)
        XCTAssertEqual(view.ty, 0, accuracy: 1e-6)
    }

    func testACollapsedBaseShowsThePictureUnmovedRatherThanCollapsed() {
        let degenerate = CGAffineTransform(scaleX: 0, y: 0)
        XCTAssertEqual(LiveLayerTransform.viewTransform(from: degenerate,
                                                        to: CGAffineTransform(translationX: 10, y: 10),
                                                        inBoundsOfSize: CGSize(width: 100, height: 100)),
                       .identity)
    }

    // MARK: - What a transform costs the model — the other half of (c)

    private func inkedCanvas(size: CGSize = CGSize(width: 2048, height: 1024)) -> VectorCanvas {
        var strokes: [VectorStroke] = []
        for row in 0..<8 {
            let y = CGFloat(60 + row * 110)
            let samples = StrokeSamples(stride(from: CGFloat(80), through: size.width - 80, by: 20)
                .map { VectorSample(x: $0, y: y, pressure: 1) }, channels: .pressureOnly)
            strokes.append(VectorStroke(brush: Brush(name: "MoveProbe", tip: .round, size: 24),
                                        color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                        size: 24, opacity: 1, samples: samples))
        }
        return VectorCanvas(size: size, strokes: strokes)
    }

    private func probeStroke(from a: CGPoint, to b: CGPoint) -> VectorStroke {
        VectorStroke(brush: Brush(name: "MoveProbe", tip: .round, size: 24),
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 24, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)])
    }

    /// `setTransform` moves the layer's content in canvas space and leaves it exactly where it was
    /// in the layer's own local space — so it must move `version` (the display really is stale) and
    /// must not move `contentVersion`.
    func testATransformIsStaleForTheDisplayAndNotForTheContent() {
        let canvas = inkedCanvas()
        let version = canvas.version, content = canvas.contentVersion

        canvas.setTransform(CGAffineTransform(translationX: 40, y: 40))
        XCTAssertGreaterThan(canvas.version, version, "the rendered picture moved")
        XCTAssertEqual(canvas.contentVersion, content, "the layer's own geometry did not")

        canvas.addStroke(probeStroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30)))
        XCTAssertGreaterThan(canvas.contentVersion, content, "an edit moves both")
    }

    /// The countable half of the (c) fix: a Move drag asked for `localContentBounds()` on every
    /// delta, and every one of those answers was a canvas-sized rasterize plus a multi-megapixel
    /// alpha scan of a value the transform cannot change.
    ///
    /// Asserted on a **count** rather than on wall-clock time, in
    /// `testPreviewIsSubstantiallyCheaperThanFull`'s idiom — a millisecond taken on this Mac is the
    /// least trustworthy number available (`PERFORMANCE.md` §6), and "did it rasterize" is a fact
    /// that does not need one.
    func testTheLocalContentBoundsMemoSurvivesATransform() {
        let canvas = inkedCanvas()
        let bounds = canvas.localContentBounds()
        XCTAssertNotNil(bounds)
        XCTAssertEqual(canvas.localContentBoundsRasterizations, 1, "the first answer has to rasterize")
        _ = canvas.localContentBounds()
        XCTAssertEqual(canvas.localContentBoundsRasterizations, 1, "and the second must not")

        canvas.setTransform(CGAffineTransform(rotationAngle: 0.3).concatenating(
            CGAffineTransform(translationX: 90, y: -20)))
        let after = canvas.localContentBounds()
        XCTAssertEqual(canvas.localContentBoundsRasterizations, 1,
                       "the bounds are memoized on `contentVersion`, which a transform does not move")
        XCTAssertEqual(after, bounds, "and they are the same bounds, because local space did not move")

        // Sixty samples of a drag, which is what the pre-branch code charged sixty rasterizes for.
        for step in 1...60 {
            canvas.setTransform(CGAffineTransform(translationX: CGFloat(step), y: 0))
            _ = canvas.localContentBounds()
        }
        XCTAssertEqual(canvas.localContentBoundsRasterizations, 1,
                       "a whole drag must cost no rasterize at all")
    }

    func testAnEditDoesDropTheLocalContentBoundsMemo() {
        let canvas = inkedCanvas()
        let before = canvas.localContentBounds()
        XCTAssertEqual(canvas.localContentBoundsRasterizations, 1)

        canvas.addStroke(probeStroke(from: CGPoint(x: 1900, y: 980), to: CGPoint(x: 1960, y: 1000)))
        let after = canvas.localContentBounds()
        XCTAssertEqual(canvas.localContentBoundsRasterizations, 2, "an edit has to be re-measured")
        XCTAssertNotEqual(after, before, "and the new ink is inside the new box")
    }
}
