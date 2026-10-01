import XCTest
import CoreGraphics
import Combine

/// **A touch beside the pen makes a Move-box drag a fifth as fast** — TODO (146), the owner's *"if the
/// user presses a finger onto the canvas while moving the box with their pen, it makes the move more
/// precise, like 5x less than the pen's movement. This should work with recording movement too."*
///
/// XCUITest cannot synthesise a Pencil, so the rule is a pure value (`PrecisionDrag`) and everything
/// that can be said about it is said here: the rate, the re-anchoring that keeps the box from
/// jumping, which touch counts, that every handle reads the slowed point, and that a take over a
/// transformation layer's box survives the finger and records the slowed path.
/// `MoveBoxPrecisionUITests` drives the same rule through the real overlays with a finger standing in
/// for the pen.
@MainActor
final class MoveBoxPrecisionLogicTests: XCTestCase {

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private func assertPoint(_ actual: CGPoint, _ x: CGFloat, _ y: CGFloat, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, x, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(actual.y, y, accuracy: 1e-9, message, file: file, line: line)
    }

    // MARK: - The rate

    /// The owner's number, and on both axes.
    func testAnotherTouchSlowsTheDragToAFifthOnBothAxes() {
        XCTAssertEqual(PrecisionDrag.slowdown, 5, "the owner's *5x less*")
        var drag = PrecisionDrag(startingAt: point(100, 200), touchesDown: 1)
        _ = drag.point(for: point(100, 200), touchesDown: 2)   // the second touch lands, pen still
        assertPoint(drag.point(for: point(150, 140), touchesDown: 2), 110, 188,
                    "50 right and 60 up is 10 right and 12 up")
        XCTAssertTrue(drag.isPrecise)
    }

    /// **Nobody slowed the drag, so nothing changed — to the bit.** A drag with no second touch hands
    /// back the pen's own point, which is what keeps every drag in the app exactly what it was.
    func testADragNobodySlowedReturnsThePensOwnPointExactly() {
        var drag = PrecisionDrag(startingAt: point(0.1, 0.3), touchesDown: 1)
        for raw in [point(0.1 + 1e-13, 0.3), point(123.456789, 98.7654321), point(-5, 0.7)] {
            XCTAssertEqual(drag.point(for: raw, touchesDown: 1), raw)
        }
        XCTAssertFalse(drag.isPrecise)
    }

    // MARK: - Re-anchoring: a touch landing or lifting changes the rate and never the position

    /// **A finger landing while the pen is held still slows the very next movement**, rather than
    /// letting its first step through at full speed: the re-base is at the previous point, not at the
    /// one that revealed the change.
    func testAFingerLandingWhileThePenIsStillSlowsTheNextMovement() {
        var drag = PrecisionDrag(startingAt: point(100, 100), touchesDown: 1)
        assertPoint(drag.point(for: point(120, 100), touchesDown: 1), 120, 100, "full speed so far")
        // The finger lands; no event arrives. The pen's next report is 50 further on.
        assertPoint(drag.point(for: point(170, 100), touchesDown: 2), 130, 100,
                    "120 + 50/5 — the whole step is slowed, none of it jumps")
    }

    /// **Lifting the finger resumes full speed from where the slowed box is, with no jump either.**
    func testLiftingTheFingerResumesFullSpeedFromWhereTheBoxIs() {
        var drag = PrecisionDrag(startingAt: point(100, 100), touchesDown: 1)
        _ = drag.point(for: point(100, 100), touchesDown: 2)
        let slowed = drag.point(for: point(200, 100), touchesDown: 2)
        assertPoint(slowed, 120, 100, "100 right is 20")
        // Lifted, pen still at 200: the point does not move.
        assertPoint(drag.point(for: point(200, 100), touchesDown: 1), 120, 100,
                    "the lift changes the rate, not the position")
        assertPoint(drag.point(for: point(230, 100), touchesDown: 1), 150, 100,
                    "…and the next 30 are the pen's own")
    }

    /// Landing and lifting any number of times keeps the box continuous — the sum of every segment at
    /// its own rate, which is the one fact a re-anchoring bug breaks.
    func testRepeatedLandingsAndLiftsAddUpSegmentByTheirOwnRate() {
        var drag = PrecisionDrag(startingAt: .zero, touchesDown: 1)
        var raw: CGFloat = 0
        var expected: CGFloat = 0
        for (step, touches) in [(40, 1), (100, 2), (25, 1), (50, 2), (10, 1)] as [(CGFloat, Int)] {
            // The touch count changes *before* the segment is travelled, as it does in the app.
            raw += step
            expected += touches == 2 ? step / 5 : step
            assertPoint(drag.point(for: point(raw, 0), touchesDown: touches), expected, 0,
                        "after travelling \(step) with \(touches) touch(es) down")
        }
    }

    // MARK: - Which touch counts

    /// **A hand already resting when the drag began is not the gesture** — the shape snap's rule. A
    /// palm must not make every drag a fifth as fast.
    func testATouchAlreadyDownWhenTheDragBeganDoesNotSlowIt() {
        var drag = PrecisionDrag(startingAt: point(0, 0), touchesDown: 2)   // pen, and a resting palm
        assertPoint(drag.point(for: point(50, 0), touchesDown: 2), 50, 0, "the palm is the baseline")
        XCTAssertFalse(drag.isPrecise)
        assertPoint(drag.point(for: point(100, 0), touchesDown: 3), 60, 0,
                    "a finger joining the palm is the gesture")
    }

    /// **The baseline ratchets down and never up**: a palm that lifts mid-drag must not leave the
    /// finger that lands afterwards uncounted.
    func testAPalmThatLiftsMidDragLeavesTheNextFingerCounted() {
        var drag = PrecisionDrag(startingAt: .zero, touchesDown: 2)
        _ = drag.point(for: point(10, 0), touchesDown: 1)        // the palm lifts
        assertPoint(drag.point(for: point(20, 0), touchesDown: 1), 20, 0, "pen alone, full speed")
        assertPoint(drag.point(for: point(70, 0), touchesDown: 2), 30, 0,
                    "a finger lands where the palm was: that is precision")
    }

    /// The dragging touch counts as one of the touches at the start, whatever its type — which is what
    /// lets a finger-driven drag with a second finger stand in for the pen in the UI test.
    func testAFingerDraggedBoxIsSlowedByASecondFingerJustAsAPenIs() {
        var drag = PrecisionDrag(startingAt: .zero, touchesDown: 1)
        assertPoint(drag.point(for: point(30, 0), touchesDown: 1), 30, 0, "one finger: full speed")
        assertPoint(drag.point(for: point(80, 0), touchesDown: 2), 40, 0, "two: a fifth")
    }

    // MARK: - Every handle reads the slowed point

    private func boxFrame() -> ObjectTransformFrame {
        ObjectTransformFrame(transform: LayerTransform(position: CGPoint(x: 200, y: 200), scale: 1, rotation: 0),
                             contentSize: CGSize(width: 100, height: 60))
    }

    /// **The body moves a fifth as far**, through the drag the overlays really use.
    func testTheBodyOfTheBoxMovesAFifthAsFarUnderPrecision() {
        let frame = boxFrame()
        let start = point(200, 200)
        var precision = PrecisionDrag(startingAt: start, touchesDown: 1)
        let drag = ObjectTransformDrag(frame: frame, handle: .body, at: start)

        _ = precision.point(for: start, touchesDown: 2)
        let slowed = drag.pose(draggedTo: precision.point(for: point(300, 150), touchesDown: 2)).transform
        let plain = drag.pose(draggedTo: point(300, 150)).transform
        XCTAssertEqual(slowed.position.x - 200, (plain.position.x - 200) / 5, accuracy: 1e-9)
        XCTAssertEqual(slowed.position.y - 200, (plain.position.y - 200) / 5, accuracy: 1e-9)
    }

    /// **The turn and the scale are slowed too**, with no handle told about it — the point they read
    /// is the slowed one. A quarter turn of the pen about the box turns it by far less than a quarter;
    /// a corner pulled 100 points out grows the box far less than it would have.
    func testTheTurnAndTheScaleAreSlowedBecauseTheyReadTheSamePoint() {
        let frame = boxFrame()
        let knob = frame.rotationHandlePosition(offset: 36)
        var turning = PrecisionDrag(startingAt: knob, touchesDown: 1)
        let turn = ObjectTransformDrag(frame: frame, handle: .rotation, at: knob)
        _ = turning.point(for: knob, touchesDown: 2)
        let penAfter = point(knob.x + 120, knob.y + 120)
        let plainTurn = abs(turn.pose(draggedTo: penAfter).transform.rotation)
        let slowedTurn = abs(turn.pose(draggedTo: turning.point(for: penAfter, touchesDown: 2)).transform.rotation)
        XCTAssertGreaterThan(plainTurn, 0.5, "PREMISE: the unslowed pen turns the box a long way")
        XCTAssertLessThan(slowedTurn, plainTurn / 3, "the slowed pen turns it far less")

        let corner = frame.corners[2]
        var pulling = PrecisionDrag(startingAt: corner, touchesDown: 1)
        let scale = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: corner)
        _ = pulling.point(for: corner, touchesDown: 2)
        let penOut = point(corner.x + 100, corner.y + 100)
        let plainGrowth = scale.pose(draggedTo: penOut).transform.scale - 1
        let slowedGrowth = scale.pose(draggedTo: pulling.point(for: penOut, touchesDown: 2)).transform.scale - 1
        XCTAssertGreaterThan(plainGrowth, 0.5, "PREMISE: the unslowed pen grows the box a long way")
        XCTAssertEqual(slowedGrowth, plainGrowth / 5, accuracy: plainGrowth * 0.05,
                       "a corner pulled along its diagonal grows the box a fifth as much")
    }

    // MARK: - Recording

    private let moverIndex = 1

    private final class FakeClock { var now: TimeInterval = 1_000 }

    /// A document whose layer 1 is a transformation layer with room for a take, and a clock the test
    /// owns — `MoveBoxRecordingLogicTests`' own fixture.
    private func movingDocument() -> (manager: CanvasManager, clock: FakeClock) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addTransformLayer()
        CanvasFixture.setCelLayout(manager, layerIndex: moverIndex, [(start: 0, length: 240)])
        manager.currentLayerIndex = moverIndex
        let clock = FakeClock()
        manager.playbackNow = { clock.now }
        return (manager, clock)
    }

    /// **A finger landing beside the pen mid-take leaves the take running, and the take records the
    /// slowed path** — *"this should work with recording movement too."*
    ///
    /// The finger arrives as the canvas sees it (`canvasInteractionBegan(mayContinueTake:
    /// mayBeATransform: true)` from the catch-all a transformation layer has, then the touch count
    /// going to two), and the pen's reports go through `PrecisionDrag` as the overlay does. Three
    /// operands: the take is still recording and playing after the finger, no interaction was
    /// announced (which is what would close a panel), and the last pose the take holds is where the
    /// slowed path ends — 100 of full-speed travel and 100 more at a fifth is 120, not 200.
    func testAFingerBesideThePenMidTakeKeepsTheTakeAndRecordsTheSlowedPath() throws {
        let (manager, clock) = movingDocument()
        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove(), "Setup: the Move box came up")
        manager.canvasTouchCountChanged(1)                       // the pen lands on the box
        XCTAssertTrue(manager.beginMoveBoxTake(), "Setup: the landing started the take")
        let centre = CGPoint(x: CanvasFixture.canvasSize.width / 2, y: CanvasFixture.canvasSize.height / 2)
        var drag = PrecisionDrag(startingAt: centre, touchesDown: 1)

        func pen(to travelled: CGFloat, touches: Int, at time: TimeInterval) {
            clock.now = time
            manager.tickPlayback()
            let point = drag.point(for: CGPoint(x: centre.x + travelled, y: centre.y), touchesDown: touches)
            manager.updateFloatingPose(transform: FloatingTransform(position: point, scaleX: 1, scaleY: 1,
                                                                    rotation: 0),
                                       distortQuad: nil)
        }

        for i in 1...10 { pen(to: CGFloat(i) * 10, touches: 1, at: 1_000 + 0.1 * Double(i)) }

        var interactions = 0
        let subscription = manager.interactionBegan.sink { interactions += 1 }
        manager.canvasTouchCountChanged(2)                       // the finger lands beside the pen
        manager.canvasInteractionBegan(mayContinueTake: manager.recordingOwnsMoveBox, mayBeATransform: true)
        XCTAssertTrue(manager.isRecording, "A finger beside the pen is not the end of the take")
        XCTAssertTrue(manager.isPlaying, "…nor of the playback that times it")
        XCTAssertEqual(interactions, 0, "…and is not an interaction, so no panel closes under the pen")

        for i in 11...20 { pen(to: CGFloat(i) * 10, touches: 2, at: 1_000 + 0.1 * Double(i)) }
        manager.canvasTouchCountChanged(1)
        manager.stopRecording()
        subscription.cancel()

        let track = try XCTUnwrap(manager.layers[moverIndex].layerTransform).track
        XCTAssertTrue(track.isAnimated, "PREMISE: the take landed a curve")
        let last = try XCTUnwrap(track.keys.last)
        let travelled = try XCTUnwrap(PoseComponents.decompose(last.pose)).x - Double(centre.x)
        XCTAssertEqual(travelled, 120, accuracy: 1.0,
                       "100 points at full speed and 100 at a fifth is 120; an unslowed take would hold 200")
    }
}
