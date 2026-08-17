import XCTest

/// End-to-end coverage for the pencil-only-mode fix to the Select tool's lasso/rectangle/automatic
/// gestures — the third hole in `CanvasManager.pencilOnlyDrawing` gating, after `fillPress` and
/// `catchAll` (see `CanvasView`'s "Which of these reject a finger" doc comment). `SelectionOverlayView`
/// used plain `UIPanGestureRecognizer`/`UITapGestureRecognizer`, whose `@objc` action never receives a
/// `UITouch`, so nothing there could ask whether the touch was a finger — the same shape of hole the
/// two prior fixes closed, now closed a third time with `TouchTypePanGestureRecognizer`/
/// `TouchTypeTapGestureRecognizer`.
///
/// This needs a live gesture, not just the extracted tie-break logic `SelectionOverlayLogicTests`
/// covers headlessly: the actual defect was that no recognizer *could* see the touch type at all,
/// which only a real touch delivered through the recognizer's own `touchesBegan` can prove is fixed.
/// XCUITest cannot synthesize a pencil touch (see CLAUDE.md), but that is not a limitation here — its
/// synthetic touches are exactly `.direct` (finger), which is the one type the reported bug is about.
///
/// In its own class, split from `ToolsAndSelectionUITests`/`SelectionAndMoveUITests`, so this one
/// short test doesn't lengthen an already-heavy class (CLAUDE.md's cost model is per-class, not
/// per-test).
final class SelectionPencilOnlyUITests: PaintUITestCase {

    /// Sets "Fingers Can Paint" to the requested state via the Actions menu, tapping only if it
    /// isn't already there. `pencilOnlyDrawing` persists in `UserDefaults` across app launches (see
    /// `CanvasManager.pencilOnlyDefaultsKey`) and nothing resets it between test runs the way
    /// `-resetGallery` resets project data, so this reads the toggle's actual current state rather
    /// than assuming a fresh-install default — otherwise a run that stops mid-test on a failure
    /// would leave the next run starting from the wrong state on the same simulator.
    ///
    /// Phrased in the UI as the state the artist chooses ("fingers can paint"), inverted from the
    /// `pencilOnlyDrawing` flag it sets (see `ActionsMenu.pencilOnlyToggle`'s doc comment) — so
    /// `fingersCanPaint == false` means pencil-only mode is on.
    private func setFingersCanPaint(_ app: XCUIApplication, to fingersCanPaint: Bool) {
        app.buttons["toolbar.actionsButton"].tap()
        let toggle = app.switches["actions.fingersCanPaintToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let wantValue = fingersCanPaint ? "1" : "0"
        if toggle.value as? String != wantValue {
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, wantValue)
        }
        app.buttons["toolbar.actionsButton"].tap() // close the panel
    }

    /// The reported bug, reproduced directly: with pencil-only mode on, a one-finger lasso drag over
    /// the canvas must not create a selection. Then, as a self-check that the test can actually detect
    /// a selection at all (not just always seeing "no selection" some other way), the same drag with
    /// pencil-only mode off is asserted *to* create one.
    func testLassoIgnoresAFingerWhilePencilOnlyModeIsOn() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        setFingersCanPaint(app, to: false) // pencil-only mode on

        app.buttons["toolbar.selectButton"].tap()
        let lassoMode = app.buttons["selectPanel.mode.lasso"]
        XCTAssertTrue(lassoMode.waitForExistence(timeout: 5))
        lassoMode.tap()

        let fillButton = app.buttons["selectPanel.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        XCTAssertFalse(fillButton.isEnabled, "no selection should exist yet")

        // A one-finger lasso drag — XCUITest's synthetic touches are `.direct` (finger); a real pencil
        // touch cannot be synthesized, but the bug is specifically about finger input being wrongly
        // accepted, so this is exactly the case that needs covering.
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.25), to: CGVector(dx: 0.55, dy: 0.42))

        XCTAssertFalse(fillButton.isEnabled,
                       "a finger drag must not create a selection while pencil-only mode is on — this is the reported bug")

        // Self-check: the same gesture, same mode, pencil-only mode off, does create a selection —
        // proving the assertion above is actually exercising the gesture path, not failing to detect
        // a selection some other way (e.g. `dragOnCanvas` landing off-canvas).
        setFingersCanPaint(app, to: true) // pencil-only mode off
        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(lassoMode.waitForExistence(timeout: 5))
        lassoMode.tap()
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.25), to: CGVector(dx: 0.55, dy: 0.42))
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        XCTAssertTrue(fillButton.isEnabled, "with pencil-only mode off, the same finger drag should create a selection")
    }
}
