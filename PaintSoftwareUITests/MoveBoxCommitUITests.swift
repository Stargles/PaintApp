import XCTest

/// **The Move box's tap-away commit, and the one half of it a test here can hold.** The owner,
/// 2026-09-07:
///
/// > *"Sometimes I am using the move tool and I click a node on the box to resize. When I let go of
/// > the node after I am done, the move unexpectedly bakes. This is not intended behaviour, it is
/// > not supposed to bake when the pen is lifted."*
///
/// The fix is that a tap's identity is decided where it **began** —
/// `TouchTypeTapGestureRecognizer.firstTouchLocationInWindow`, which carries the whole argument.
///
/// **The defect itself is not reachable from XCUITest, and this file exists partly to record that
/// so the next session does not spend the runs again.** Several runs were spent trying, each
/// mutating the fix back out and expecting red; all of them stayed green. The reproducing gesture is
/// squeezed from both sides and neither bound is knowable from the source:
///
///  * travel far enough and `UITapGestureRecognizer`'s undocumented movement slop fails the
///    sequence, so nothing reaches `handleMoveBoxCommit` at all and the mutation survives;
///  * travel little enough and XCUITest's own drag undershoot — `PaintUITestCase.performDrag`
///    records that synthetic drags *"undershoot their intended distance by a timing-dependent
///    amount"* — lands the release back inside the grip's 22 pt reach
///    (`ObjectTransformOverlayView.handleScreenReach`), which is also not a commit.
///
/// A sweep of 30 / 45 / 60 / 75 / 90 pt found no travel in between that commits, and a screenshot
/// attachment confirmed the flick grabs the intended grip on the intended box — so this is a
/// property of the harness, not of the fixture. The owner's own gesture is 25.2 pt over 230 ms with
/// a **pencil**, and CLAUDE.md already records that XCUITest cannot synthesise a pencil at all.
/// **So the fix is verified on the device and pinned nowhere.** The premise underneath it is pinned
/// headlessly by
/// `ObjectTransformLogicTests.testAUniformCornerDragLeavesTheFingerOffTheBoxOnceItsBearingTurns`.
///
/// What *is* held here is the other direction, which is the risk the fix itself introduces: reading
/// the begin point instead of the release point could have stopped the tap-away working at all, and
/// that would be the worse bug — the artist would have no way to put a move down but the Move
/// button.
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
}
