import XCTest

/// The one UI-level check for the undo/redo `CanvasNotice`: that a real undo/redo tap actually
/// raises the banner on screen. Everything about *which* label a given action maps to, the
/// "Undid "/"Redid " phrasing, the silence-on-empty-stack rule and the replace-not-queue behaviour
/// is `HistoryNoticeLogicTests`' job, run headlessly against `CanvasManager` directly — this file
/// exists only to prove the wiring from a real gesture through to a real view reaches the screen at
/// all, which the logic tier cannot see.
final class HistoryNoticeUITests: PaintUITestCase {

    /// Draws one stroke, taps `sideToolbar.undoButton` (the same control every other undo/redo UI
    /// test in this suite drives — `TimelineAndUndoUITests`, `FillUITests`, `VectorEraserUITests` —
    /// rather than the two/three-finger canvas tap gesture `CanvasView.Coordinator` also wires to
    /// the same `CanvasManager.undo()`/`redo()`: a synthesized `tap(withNumberOfTaps:numberOfTouches:)`
    /// did not reliably reach that gesture recognizer in this simulator, so the toolbar button —
    /// already this suite's established route to undo/redo — is the reliable one),
    /// and confirms the transient banner appears naming an undo. Mirrors
    /// `testTheModePickerCreatesAnEffectLayerAStrokeCannotLandOn`'s pattern of asserting the
    /// accessibility *value* (the case code) rather than the sentence, for the same reason: a
    /// rewording of `HistoryActionLabel.brushStroke.phrase` must not break this test.
    func testUndoButtonShowsHistoryNotice() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3))

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "Undo should be available immediately after a stroke")
        undo.tap()

        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5),
                      "Undoing the stroke just drawn should raise the transient banner naming it")
        XCTAssertEqual(notice.value as? String, "historyUndo",
                       "The banner names the direction by `CanvasNotice.code`, not by its wording")

        // And it clears on its own — the whole point of `CanvasNotice` over the old modal alerts —
        // rather than sitting on screen requiring a tap. 2.6s duration plus slack for the fade.
        let goneExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notice)
        XCTAssertEqual(XCTWaiter().wait(for: [goneExpectation], timeout: 4), .completed,
                       "The history notice must dismiss itself without a tap")

        // Redo shows the twin notice — same button-driven pattern, other direction.
        let redo = app.buttons["sideToolbar.redoButton"]
        XCTAssertTrue(redo.isEnabled, "Redo should be available after undoing the stroke")
        redo.tap()

        let redoNotice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(redoNotice.waitForExistence(timeout: 5),
                      "Redoing the stroke should raise the transient banner naming it")
        XCTAssertEqual(redoNotice.value as? String, "historyRedo")
    }
}
