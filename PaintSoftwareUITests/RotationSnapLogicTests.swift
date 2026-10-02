import XCTest
import CoreGraphics

/// **A finger on the glass makes a turn land on a round angle, and the angle reads out in degrees** —
/// TODO (151), the owner's *"Remember the behaviour where if a user creates a line smartshape and then
/// presses their finger, it snaps in 15 degree increments? make it so the user can also do that when
/// rotating any rotate node. Also have a degree indicator when a rotate node is selected. (Example:
/// 23.72°)"*
///
/// The rule is `RotationAngle`, the smart-shape line's own 15° and nothing else; what a *joined touch*
/// means is `PrecisionDrag`'s, and the pipelines it reaches are `ObjectTransformDrag` (both knobs on a
/// vector Move box) and `TextFrameDrag`. The raster Move box's knob and the smart shape's knob are
/// driven through the real overlays by `RotationSnapUITests`.
final class RotationSnapLogicTests: XCTestCase {

    private let fifteen = CGFloat.pi / 12
    private func degrees(_ radians: CGFloat) -> CGFloat { radians * 180 / .pi }
    private func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    private func assertOnTheGrid(_ angle: CGFloat, _ message: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let steps = angle / fifteen
        XCTAssertEqual(steps, steps.rounded(), accuracy: 1e-9,
                       "\(message): \(degrees(angle))° is not a multiple of 15°", file: file, line: line)
    }

    // MARK: - The rule

    func testAnAngleLandsOnTheNearestMultipleOfFifteenDegrees() {
        XCTAssertEqual(RotationAngle.snapIncrement, radians(15), accuracy: 1e-12)
        for (given, expected) in [(0, 0), (7, 0), (8, 15), (22, 15), (23, 30), (-8, -15), (-7, 0),
                                  (89, 90), (181, 180), (-170, -165)] as [(CGFloat, CGFloat)] {
            XCTAssertEqual(degrees(RotationAngle.snapped(radians(given))), expected, accuracy: 1e-9,
                           "\(given)° snaps to \(expected)°")
        }
    }

    /// **The smart-shape line asks the same function** — its snap used to be a private copy with the
    /// same increment, and a line and a knob must never disagree about what a round angle is.
    func testTheSmartShapeLineSnapsToTheSameGrid() {
        for angle in stride(from: CGFloat(-170), through: 170, by: 13) {
            let end = CGPoint(x: 100 + 120 * cos(radians(angle)), y: 100 + 120 * sin(radians(angle)))
            let line = ShapeGeometry(kind: .line, startPoint: CGPoint(x: 100, y: 100), endPoint: end)
            let snapped = line.constrained
            let drawn = atan2(snapped.endPoint.y - snapped.startPoint.y, snapped.endPoint.x - snapped.startPoint.x)
            XCTAssertEqual(drawn, RotationAngle.snapped(radians(angle)), accuracy: 1e-9,
                           "a line drawn at \(angle)° is held at the grid angle `RotationAngle` names")
        }
    }

    func testTheReadoutIsDegreesToTwoDecimalsInTheRangeAnArtistReads() {
        XCTAssertEqual(RotationAngle.readout(radians(23.72)), "23.72°", "the owner's own example")
        XCTAssertEqual(RotationAngle.readout(0), "0.00°")
        XCTAssertEqual(RotationAngle.readout(-0.00001), "0.00°", "never -0.00°")
        XCTAssertEqual(RotationAngle.readout(radians(-15)), "-15.00°", "anticlockwise reads negative")
        XCTAssertEqual(RotationAngle.readout(radians(725)), "5.00°", "whole turns are folded away")
        XCTAssertEqual(RotationAngle.readout(radians(-540)), "180.00°", "−180° and 180° are one angle, read as 180°")
        XCTAssertEqual(RotationAngle.readout(radians(180)), "180.00°")
        XCTAssertEqual(RotationAngle.readout(radians(359.999)), "0.00°", "a hair under a full turn reads as upright")
    }

    /// The knob stands off the top edge, so it straight above the centre is the box upright.
    func testABoxAngleIsReadOffTheKnobTheWayTheKnobStandsOffTheTopEdge() {
        let c = CGPoint(x: 50, y: 50)
        func angle(_ knob: CGPoint, snapping: Bool = false) -> CGFloat {
            degrees(RotationAngle.boxAngle(forKnobAt: knob, about: c, snapping: snapping))
        }
        XCTAssertEqual(angle(CGPoint(x: 50, y: 0)), 0, accuracy: 1e-9, "above: upright")
        XCTAssertEqual(angle(CGPoint(x: 100, y: 50)), 90, accuracy: 1e-9, "to the right: a quarter clockwise")
        XCTAssertEqual(RotationAngle.readout(RotationAngle.boxAngle(forKnobAt: CGPoint(x: 0, y: 50), about: c, snapping: false)),
                       "-90.00°", "to the left: a quarter anticlockwise")
        let off = CGPoint(x: 50 + 80 * sin(radians(17)), y: 50 - 80 * cos(radians(17)))
        XCTAssertEqual(angle(off), 17, accuracy: 1e-9)
        XCTAssertEqual(angle(off, snapping: true), 15, accuracy: 1e-9, "17° snaps to 15°")
    }

    // MARK: - What a joined touch means, by the handle

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// **On a knob it snaps and never slows**: the point is the pen's own, to the bit, and the turn is
    /// the one asked to land on the grid.
    func testATouchThatJoinsAKnobDragSnapsTheTurnAndLeavesThePointAlone() {
        var drag = PrecisionDrag(startingAt: p(10, 10), touchesDown: 1, turns: true)
        XCTAssertEqual(drag.point(for: p(40, 30), touchesDown: 1), p(40, 30))
        XCTAssertFalse(drag.snapsAngle, "the pen alone turns freely")
        XCTAssertEqual(drag.point(for: p(90, 60), touchesDown: 2), p(90, 60),
                       "a finger lands: the point is still the pen's, not a fifth of it")
        XCTAssertTrue(drag.snapsAngle)
        XCTAssertFalse(drag.isPrecise, "a knob is never slowed")
        XCTAssertEqual(drag.point(for: p(95, 65), touchesDown: 1), p(95, 65))
        XCTAssertFalse(drag.snapsAngle, "the finger lifts: the turn is free again")
    }

    /// **The baseline still decides which touch counts** — a hand already resting on the glass when
    /// the knob was taken must not snap every turn.
    func testARestingPalmDoesNotSnapTheTurnButAFingerLandingAfterItDoes() {
        var drag = PrecisionDrag(startingAt: .zero, touchesDown: 2, turns: true)
        _ = drag.point(for: p(10, 0), touchesDown: 2)
        XCTAssertFalse(drag.snapsAngle, "the palm was there first")
        _ = drag.point(for: p(20, 0), touchesDown: 1)       // the palm lifts
        _ = drag.point(for: p(30, 0), touchesDown: 2)       // a finger lands where it was
        XCTAssertTrue(drag.snapsAngle)
    }

    /// Every handle that is not a knob keeps (146)'s rule exactly: slowed, and never asking for a snap.
    func testAHandleThatDoesNotTurnIsSlowedAndNeverSnaps() {
        var drag = PrecisionDrag(startingAt: .zero, touchesDown: 1)
        _ = drag.point(for: .zero, touchesDown: 2)
        XCTAssertEqual(drag.point(for: p(50, 0), touchesDown: 2).x, 10, accuracy: 1e-9)
        XCTAssertTrue(drag.isPrecise)
        XCTAssertFalse(drag.snapsAngle)
    }

    func testOnlyTheTwoKnobsTurn() {
        for handle in ObjectTransformFrame.Handle.allCases {
            XCTAssertEqual(handle.turns, handle == .rotation || handle == .boxRotation, "\(handle)")
        }
    }

    // MARK: - The vector Move box: both knobs land the angle the box is drawn at

    private func box(rotation: CGFloat = 0, boxAngle: CGFloat = 0) -> ObjectTransformFrame {
        ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 200, y: 200), scale: 1, rotation: rotation),
                             contentSize: CGSize(width: 100, height: 60), boxAngle: boxAngle)
    }

    /// The point on the ray `bearing` degrees clockwise of straight up from the box's centre.
    private func pen(at bearing: CGFloat, from centre: CGPoint = CGPoint(x: 200, y: 200),
                     radius: CGFloat = 120) -> CGPoint {
        CGPoint(x: centre.x + radius * sin(radians(bearing)), y: centre.y - radius * cos(radians(bearing)))
    }

    func testTheGreenKnobLandsTheBoxOnTheGridAndTheFreeTurnDoesNot() {
        let frame = box()
        let knob = frame.rotationHandlePosition(offset: 36)
        let drag = ObjectTransformDrag(frame: frame, handle: .rotation, at: knob)
        let free = drag.pose(draggedTo: pen(at: 20))
        XCTAssertEqual(degrees(free.transform.rotation), 20, accuracy: 1e-9, "PREMISE: unsnapped it follows the pen")
        let snapped = drag.pose(draggedTo: pen(at: 20), snapsRotation: true)
        XCTAssertEqual(degrees(snapped.transform.rotation), 15, accuracy: 1e-9)
        XCTAssertEqual(snapped.boxAngle, 0, "the green knob turns the ink, not the hand angle")
    }

    /// **A box that is already at 7° is found at 15° and 30°, not at 22° and 37°** — the angle the
    /// artist sees is the one that lands on the grid, whatever the turn began from.
    func testTheTurnLandsTheAngleTheBoxIsDrawnAtNotTheSweep() {
        let frame = box(rotation: radians(7))
        let knob = frame.rotationHandlePosition(offset: 36)
        let drag = ObjectTransformDrag(frame: frame, handle: .rotation, at: knob)
        // The pen sweeps 20° clockwise of where the knob was: the box would be drawn at 27°.
        let snapped = drag.pose(draggedTo: pen(at: 7 + 20), snapsRotation: true)
        XCTAssertEqual(degrees(snapped.transform.rotation), 30, accuracy: 1e-9)
        assertOnTheGrid(ObjectTransformFrame(transform: snapped.transform, contentSize: frame.contentSize,
                                             boxAngle: snapped.boxAngle).drawnAngle, "the drawn box")
    }

    /// With a hand-turned box under the ink the drawn angle is rotation + box angle, and that sum is
    /// what lands on the grid for either knob.
    func testBothKnobsLandTheDrawnAngleWhenTheBoxHasBeenTurnedByHand() {
        let frame = box(rotation: radians(5), boxAngle: radians(10))        // drawn at 15°
        // The green knob: 15° + 22° = 37°, held at 30° (not at 37° and not at a sweep of 22°).
        let green = ObjectTransformDrag(frame: frame, handle: .rotation,
                                        at: frame.rotationHandlePosition(offset: 36))
        let greenPose = green.pose(draggedTo: pen(at: 37), snapsRotation: true)
        XCTAssertEqual(degrees(greenPose.transform.rotation + greenPose.boxAngle), 30, accuracy: 1e-9)
        XCTAssertEqual(greenPose.boxAngle, radians(10), accuracy: 1e-12, "the hand angle is untouched")

        // The yellow knob stands off the bottom, so its bearing from the centre is the box's + 180°.
        let yellow = ObjectTransformDrag(frame: frame, handle: .boxRotation,
                                         at: frame.boxRotationHandlePosition(offset: 36))
        let yellowPose = yellow.pose(draggedTo: pen(at: 37 + 180), snapsRotation: true)
        XCTAssertEqual(degrees(yellowPose.transform.rotation + yellowPose.boxAngle), 30, accuracy: 1e-9)
        XCTAssertEqual(yellowPose.transform, frame.transform, "the ink is not touched by the box-only knob")
    }

    func testAHandleThatDoesNotTurnIgnoresTheSnap() {
        let frame = box()
        let corner = frame.corners[2]
        let drag = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: corner)
        let there = CGPoint(x: corner.x + 40, y: corner.y + 25)
        XCTAssertEqual(drag.pose(draggedTo: there, snapsRotation: true).transform,
                       drag.pose(draggedTo: there).transform)
        let body = ObjectTransformDrag(frame: frame, handle: .body, at: frame.centre)
        XCTAssertEqual(body.pose(draggedTo: there, snapsRotation: true).transform,
                       body.pose(draggedTo: there).transform)
    }

    // MARK: - The text box

    private func upright(centre: CGPoint = CGPoint(x: 200, y: 200),
                         size: CGSize = CGSize(width: 120, height: 40)) -> TextFrame {
        TextFrame(origin: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2),
                  size: size, autoSize: false)
    }

    func testTheTextKnobLandsTheBoxOnTheGrid() throws {
        let frame = upright()
        let drag = try XCTUnwrap(TextFrameDrag(frame: frame, handle: .rotation))
        let target = pen(at: 17)
        let free = try XCTUnwrap(drag.clampedFrame(draggedTo: target))
        XCTAssertEqual(degrees(free.rotation), 17, accuracy: 1e-9, "PREMISE: unsnapped it follows the pen")
        let snapped = try XCTUnwrap(drag.clampedFrame(draggedTo: target, snapsRotation: true))
        XCTAssertEqual(degrees(snapped.rotation), 15, accuracy: 1e-9)
        XCTAssertEqual(snapped.size, frame.size, "turning is not sizing")
    }

    /// A box that has been given perspective turns rigidly about its centre, and lands on the grid by
    /// the same rule.
    func testTheTextKnobLandsAWarpedBoxOnTheGridToo() throws {
        var frame = upright(size: CGSize(width: 160, height: 60))
        let o = frame.corners[0]
        frame.corners = [o, CGPoint(x: o.x + 160, y: o.y + 22),
                         CGPoint(x: o.x + 160, y: o.y + 38), CGPoint(x: o.x, y: o.y + 60)]
        frame.mode = .projective
        XCTAssertTrue(frame.needsBoxSpaceSizing, "PREMISE: this takes the warped path")
        let drag = try XCTUnwrap(TextFrameDrag(frame: frame, handle: .rotation))
        let snapped = try XCTUnwrap(drag.clampedFrame(draggedTo: pen(at: 41, from: frame.centre), snapsRotation: true))
        XCTAssertEqual(degrees(snapped.rotation), 45, accuracy: 1e-9)
        assertOnTheGrid(snapped.rotation, "the warped box")
    }

    func testASizingGripIgnoresTheSnap() throws {
        let frame = upright()
        let drag = try XCTUnwrap(TextFrameDrag(frame: frame, handle: .bottomRight))
        let there = CGPoint(x: 290, y: 250)
        XCTAssertEqual(drag.clampedFrame(draggedTo: there, snapsRotation: true)?.corners,
                       drag.clampedFrame(draggedTo: there)?.corners)
    }

    // MARK: - Where the pill stands

    /// **The pill stays where the artist can see it** — the follow-up to TODO (151): the canvas host
    /// extends beneath the timeline and the docked panel, and a pill beside a knob near their edge was
    /// drawn behind them. `RotationReadoutView.centre(forKnob:awayFrom:pillSize:within:)` is the one
    /// rule, so these are its operands: where the pill goes against the box, against the edge of the
    /// visible area, and against a knob that is past it.
    private let pill = CGSize(width: 64, height: 28)
    private let glass = CGRect(x: 0, y: 0, width: 1000, height: 450)

    private func pillRect(_ centre: CGPoint) -> CGRect {
        CGRect(x: centre.x - pill.width / 2, y: centre.y - pill.height / 2, width: pill.width, height: pill.height)
    }

    /// With room, the pill is on the side of the knob away from the box, its edge `standOff` off the
    /// knob — above a knob that stands above its box, below one that stands below.
    func testThePillStandsOffTheKnobOnTheSideAwayFromTheBox() {
        let above = RotationReadoutView.centre(forKnob: CGPoint(x: 500, y: 200), awayFrom: CGPoint(x: 500, y: 300),
                                               pillSize: pill, within: glass)
        XCTAssertEqual(above.x, 500, accuracy: 1e-9)
        XCTAssertEqual(above.y, 200 - RotationReadoutView.standOff - pill.height / 2, accuracy: 1e-9,
                       "a knob above its box has the pill above it")
        let below = RotationReadoutView.centre(forKnob: CGPoint(x: 500, y: 300), awayFrom: CGPoint(x: 500, y: 200),
                                               pillSize: pill, within: glass)
        XCTAssertEqual(below.y, 300 + RotationReadoutView.standOff + pill.height / 2, accuracy: 1e-9,
                       "…and a knob below its box has it below")
    }

    /// **A knob at the edge of the visible area gets the pill on the box's side of it** — clamped
    /// instead, the pill would sit on top of the knob and the finger on it. Two readings of one knob:
    /// the same stand-off with room (above), and none (below the glass's last 40 points).
    func testAKnobAtTheEdgeOfTheVisibleAreaGetsThePillOnTheBoxsSideOfIt() {
        let knob = CGPoint(x: 500, y: glass.maxY - 10)
        let centre = RotationReadoutView.centre(forKnob: knob, awayFrom: CGPoint(x: 500, y: knob.y - 100),
                                                pillSize: pill, within: glass)
        XCTAssertEqual(centre.y, knob.y - RotationReadoutView.standOff - pill.height / 2, accuracy: 1e-9,
                       "the pill is over the knob, a stand-off clear of it, not clamped across it")
        XCTAssertLessThanOrEqual(pillRect(centre).maxY, glass.maxY - RotationReadoutView.edgeInset,
                                 "and inside the visible area")
    }

    /// **A knob beyond the visible area — under the timeline — still gets a pill, at its edge.** Neither
    /// side of the knob has room, so the rule falls back to the clamp: the pill is where the artist can
    /// read it, nearest the knob they are holding.
    func testAKnobUnderTheTimelineGetsAPillAtTheEdgeOfWhatIsVisible() {
        let centre = RotationReadoutView.centre(forKnob: CGPoint(x: 500, y: 600), awayFrom: CGPoint(x: 500, y: 520),
                                                pillSize: pill, within: glass)
        XCTAssertEqual(pillRect(centre).maxY, glass.maxY - RotationReadoutView.edgeInset, accuracy: 1e-9)
    }

    /// **For every knob on and around the glass the pill is inside the visible area** — a sweep, because
    /// the rule's claim is about all of them: the four edges and the corners are not cases of their
    /// own. The box is taken at the glass's middle, and knobs run from the host's corner to well under
    /// the timeline.
    func testThePillIsInsideTheVisibleAreaForEveryKnobPosition() {
        let inner = glass.insetBy(dx: RotationReadoutView.edgeInset, dy: RotationReadoutView.edgeInset)
        for x in stride(from: CGFloat(-50), through: 1050, by: 50) {
            for y in stride(from: CGFloat(-50), through: 700, by: 25) {
                let centre = RotationReadoutView.centre(forKnob: CGPoint(x: x, y: y),
                                                        awayFrom: CGPoint(x: 500, y: 225),
                                                        pillSize: pill, within: glass)
                XCTAssertTrue(inner.contains(pillRect(centre)),
                              "the pill for a knob at (\(x), \(y)) stands at \(pillRect(centre))")
            }
        }
    }

    /// **The view holds the pill above what covers the host's bottom** — the wiring from
    /// `coveredBottom` to the rule. The control is the same knob with nothing covering the host, which
    /// puts the pill in the strip the timeline would occupy.
    func testThePillViewStandsAboveTheStripTheTimelineCovers() {
        func pillFrame(covered: CGFloat) -> CGRect {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
            let view = RotationReadoutView()
            host.addSubview(view)
            view.coveredBottom = covered
            view.show(angle: .pi / 12, knob: CGPoint(x: 500, y: 640), centre: CGPoint(x: 500, y: 560), in: host)
            return view.frame
        }
        XCTAssertGreaterThan(pillFrame(covered: 0).maxY, 450, "PREMISE: uncovered, the pill stands where the timeline would be")
        XCTAssertLessThanOrEqual(pillFrame(covered: 250).maxY, 450 - RotationReadoutView.edgeInset,
                                 "covered, it stands above the covered strip")
    }
}
