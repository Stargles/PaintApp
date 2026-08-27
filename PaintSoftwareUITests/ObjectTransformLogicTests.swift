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
        XCTAssertEqual(layout.count, 5, "four corners and the rotation knob")
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

    func testAZeroOffsetOmitsTheKnobEntirely() {
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
            XCTAssertEqual(chrome.handles.count, 5, "five grips at \(canvasScale)×")
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
            let samples = stride(from: CGFloat(80), through: size.width - 80, by: 20)
                .map { VectorSample(x: $0, y: y, pressure: 1) }
            strokes.append(VectorStroke(brush: Brush(name: "MoveProbe", shape: .softRound, size: 24),
                                        color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                        size: 24, opacity: 1, samples: samples))
        }
        return VectorCanvas(size: size, strokes: strokes)
    }

    private func probeStroke(from a: CGPoint, to b: CGPoint) -> VectorStroke {
        VectorStroke(brush: Brush(name: "MoveProbe", shape: .softRound, size: 24),
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
