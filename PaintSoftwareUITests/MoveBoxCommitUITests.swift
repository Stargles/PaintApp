import XCTest

/// **The Move box's tap-away commit, from both sides.** The owner, 2026-09-07:
///
/// > *"Sometimes I am using the move tool and I click a node on the box to resize. When I let go of
/// > the node after I am done, the move unexpectedly bakes. This is not intended behaviour, it is
/// > not supposed to bake when the pen is lifted."*
///
/// And again on 2026-09-15, recorded twice: a pencil on the rotation knob, 27 pt of travel, the
/// float gone on release (`recording-20260915-040910`, `recording-20260915-215123`).
///
/// The tap-away is a `UITapGestureRecognizer`, which does not fail on movement, so a grip drag
/// arrives at it as a tap. The 2026-09-08 fix read the touch-down point instead of the release
/// point — and still read it at `.ended`, against chrome the drag had just moved. The fix is that
/// whether a touch is a tap *away* is decided at touch-down, in
/// `CanvasView.Coordinator.gestureRecognizer(_:shouldReceive:)`, and a touch that lands on the box's
/// chrome is never offered to the recognizer at all.
///
/// **`testDraggingTheRotationKnobLeavesTheBoxUp` is the defect.** The knob sits 36 pt clear of the
/// body on a circle about the box's centre and follows the finger round it, so a sideways drag
/// leaves the touch-down point past the grip's 22 pt reach and on no chrome — the one grip whose
/// drag cannot be mistaken for a tap that stayed on the box. The 2026-09-08 pass concluded the
/// defect was unreachable from XCUITest after sweeping *corner* drags, which grow the box over the
/// touch-down point and so never commit; the knob is what makes it reachable, and this goes red
/// with the touch-down decision removed.
///
/// **`testAFlickThatBeginsOnBarePaperStillSettlesTheBox` is the other direction**, which is the
/// risk the fix itself carries: deciding at touch-down could have stopped the tap-away working at
/// all, and that would be the worse bug — the artist would have no way to put a move down but the
/// Move button.
///
/// A small class on purpose — CLAUDE.md's cost model distributes per test *class*, and the file is
/// named for the class so a triage selector built from either name resolves.
final class MoveBoxCommitUITests: PaintUITestCase {

    /// A drag short and quick enough that `UITapGestureRecognizer` still calls it a tap.
    ///
    /// **`PaintUITestCase.dragOnCanvas` cannot be used for this**: it presses 0.15 s, travels at
    /// `.slow` (100 pt/s) and holds 0.1 s — the better part of a second, which no tap recognizer
    /// accepts.
    private func flickOnCanvas(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "no canvas to flick on")
        canvas.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.02,
                   thenDragTo: canvas.coordinate(withNormalizedOffset: to),
                   withVelocity: .fast,
                   thenHoldForDuration: 0)
    }

    /// **A touch that begins on bare paper still settles the box, and it still does so when it
    /// moves.** Both halves matter. The commit is a `UITapGestureRecognizer`, so it fires on a touch
    /// that travelled as well as on a still one, and the fix changes which end of that travel the
    /// decision is read from — so a fix that read the begin point *wrongly* (a stale latch, a
    /// coordinate converted from the wrong view) would leave the artist unable to put a move down by
    /// tapping away. Only this says it did not.
    func testAFlickThatBeginsOnBarePaperStillSettlesTheBox() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        dragOnCanvas(app, from: CGVector(dx: 0.500, dy: 0.22), to: CGVector(dx: 0.530, dy: 0.78))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move raised no box, so there is nothing here to settle")

        // Well away from the box, which hugs a stroke drawn down the middle of the paper.
        let host = canvas.frame
        let start = CGVector(dx: 0.30, dy: 0.45)
        flickOnCanvas(app, from: start, to: CGVector(dx: start.dx + 35 / host.width, dy: start.dy))

        // `waitForExistence` is the wrong tool for a disappearance — it returns true at once for an
        // element that is still on screen. This waits for the absence.
        wait(for: [expectation(for: NSPredicate(format: "exists == false"),
                               evaluatedWith: app.buttons["moveBar.doneButton"])],
             timeout: 5)
    }

    /// THE DEFECT. Grab the green rotation knob, drag it sideways a little, let go: the box stays up.
    func testDraggingTheRotationKnobLeavesTheBoxUp() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // A stroke straight down the middle: its box is tall and narrow, and its rotation knob
        // sits `ObjectTransformOverlayView.rotationHandleScreenOffset` (36 pt) above the box's
        // top edge, on the stroke's own x. The box's top is the stroke's top plus half a brush
        // width, so landing a few points below the knob's nominal place keeps the touch inside
        // the knob's 22 pt reach and well clear of the top-middle grip 36 pt below it.
        let strokeTop: CGFloat = 0.30
        dragOnCanvas(app, from: CGVector(dx: 0.5, dy: strokeTop), to: CGVector(dx: 0.5, dy: 0.70))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move raised no box, so there is no knob to drag")

        let host = canvas.frame
        let knob = CGVector(dx: 0.5, dy: strokeTop - 32 / host.height)
        flickOnCanvas(app, from: knob, to: CGVector(dx: knob.dx + 40 / host.width, dy: knob.dy))

        // The commit's own animation stands the bar down inside a fraction of a second; a bar that
        // is still there after a whole one was never committed.
        let stillUp = expectation(for: NSPredicate(format: "exists == false"),
                                  evaluatedWith: app.buttons["moveBar.doneButton"])
        stillUp.isInverted = true
        wait(for: [stillUp], timeout: 1.5)
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists,
                      "THE DEFECT: letting go of the rotation knob baked the move")
    }

    /// **A touch on the box is a touch on the canvas, and closes an open top-bar dropdown the way
    /// every other one does.** Before the touch-down decision above, the box's chrome reached the
    /// tap-away as a tap and `handleMoveBoxCommit` closed the dropdown at *release*, by accident;
    /// refusing the chrome to the tap took that with it, and a review of the change found the
    /// dropdown standing over the canvas through a whole grip drag. `Coordinator.moveBoxTouchDown`
    /// closes it at touch-down now, and the box stays up — the other test's guarantee, re-checked
    /// here because the closing call and the commit used to be the same line.
    func testDraggingAGripClosesAnOpenTopBarDropdown() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let strokeTop: CGFloat = 0.30
        dragOnCanvas(app, from: CGVector(dx: 0.5, dy: strokeTop), to: CGVector(dx: 0.5, dy: 0.70))

        // **The dropdown first, the box second, and that order is the only one that keeps both.**
        // Opening a top-bar dropdown runs `toggle(_:)` -> `commitAllInteractiveState()`, which
        // commits a float — so raising the box first and the dropdown second bakes the box. Tapping
        // Move runs `toggleMove`, which does not touch `activePanel`, so raising the box while the
        // dropdown is already open leaves the dropdown standing over a live box, which is the state
        // the finding needs.
        app.buttons["toolbar.actionsButton"].tap()
        let dropdownRow = app.buttons["actions.exportRow"]
        XCTAssertTrue(dropdownRow.waitForExistence(timeout: 5), "PREMISE: the Actions dropdown has to be open")

        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move raised no box, so there is no grip to drag")
        XCTAssertTrue(dropdownRow.exists,
                      "PREMISE: raising the box must have left the dropdown open (it is a top-row dropdown)")

        // Grab a grip and let go without moving far — a touch that lands on the box, which is what
        // has to close the dropdown. (A knob flick would also do, but this keeps to a plain grip.)
        let host = canvas.frame
        let topGrip = CGVector(dx: 0.5, dy: strokeTop)
        flickOnCanvas(app, from: topGrip, to: CGVector(dx: topGrip.dx + 12 / host.width, dy: topGrip.dy))

        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: dropdownRow)],
             timeout: 3)
        XCTAssertFalse(dropdownRow.exists,
                       "THE GAP: touching the Move box with the Actions dropdown open left the dropdown standing")
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists,
                      "closing the dropdown must not have baked the move")
    }
}
