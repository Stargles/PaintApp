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
/// **TODO (47) added a fourth and fifth hole here, not a fourth class.** `handleMoveBoxCommit`
/// (vector) and `FloatingPieceOverlayView.handleTapOutside` (raster) each committed a floating Move
/// on *any* tap away from the box, finger included — the owner's report. Both are the same shape of
/// defect as the three above (a touch-type decision needing a real gesture to prove), so they live
/// here rather than starting a fifth small class — CLAUDE.md's later cost-model entries found that
/// splitting further stopped paying for itself once the roster grew past ~150 classes.
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

    /// **TODO (47), the vector half.** The owner: *"when you are moving an object with pen only draw
    /// on and then tap somewhere else on the canvas with your hand, it bakes the move. It should only
    /// do that when the pen is tapped."* `handleMoveBoxCommit` used to run on a plain
    /// `UITapGestureRecognizer` with no touch-type gate at all — settling a float writes nothing, so
    /// the reasoning went, pencil-only mode has no stake in it. That is the same shape of exemption
    /// `handleEyedropperPress` considered and rejected for the pick tool: a gesture can be gated for
    /// what it *leads to* rather than for what it draws, and ending a Move's adjustable state is
    /// exactly that.
    ///
    /// **Why the toggle flips before Move, not after.** `TopToolbar.toggle(_:)` — what opens the
    /// Actions menu `setFingersCanPaint` uses — calls `commitAllInteractiveState()` before it does
    /// anything else, so opening that menu while a piece is floating bakes it on the way in. Flipping
    /// the preference is only safe here when nothing is floating yet, which is why Move is engaged
    /// *after* the toggle rather than before.
    ///
    /// **Move with no selection, not a lasso.** On the default vector layer this lifts the whole cel
    /// through `beginVectorWholeCelMove`, boxed to the lifted *geometry* rather than the canvas rect
    /// (`ObjectTransformFrame`), so a short stroke leaves plenty of canvas outside the box for the tap
    /// below to land on — confirmed by hand in the simulator before writing this down, since
    /// `testMoveWithNoSelectionLiftsWholeLayerAndCommits` shows the *raster* arm of the same button
    /// behaves oppositely (it rasterizes the whole cel, so there is no outside to tap — see the raster
    /// twin of this test for how that one gets a box smaller than the canvas instead).
    func testAFingerTapAwayLeavesAVectorMoveFloatingWhilePencilOnlyModeIsOn() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setFingersCanPaint(app, to: true) // pencil-only mode off, so this finger stroke is accepted

        // A short stroke on the default (vector) layer, well clear of the tap-away point below.
        dragOnCanvas(app, from: CGVector(dx: 0.2, dy: 0.2), to: CGVector(dx: 0.35, dy: 0.2))

        setFingersCanPaint(app, to: false) // pencil-only mode on — safe: nothing is floating yet

        let doneButton = app.buttons["moveBar.doneButton"]
        app.buttons["toolbar.moveButton"].tap() // Move with no selection lifts the whole cel
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "setup: Move should lift the stroke")

        // A finger tap far from the box — XCUITest's synthetic touches are always `.direct` (finger).
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42)).tap()

        XCTAssertTrue(doneButton.exists,
                      "a finger tap elsewhere must not bake the Move while pencil-only mode is on — this is the reported bug")

        // Self-check: turning pencil-only mode back off opens the Actions menu, which bakes the
        // still-floating piece as a side effect (the same chokepoint every tool switch goes through),
        // putting the stroke back in place so Move can lift it again. The identical tap this time,
        // pencil-only mode off, should bake it — proving the assertion above actually exercises the
        // tap-away-commit path rather than failing to detect a commit some other way.
        setFingersCanPaint(app, to: true)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "setup: Move should lift the stroke a second time")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42)).tap()
        XCTAssertTrue(doneButton.waitForNonExistence(timeout: 5),
                      "self-check: with pencil-only mode off, the same finger tap should bake the Move")
    }

    /// The raster twin of the test above. `FloatingPieceOverlayView.handleTapOutside` carried the
    /// identical hole — a plain `UITapGestureRecognizer`, gated on nothing — for the raster floating
    /// piece, fixed the same way via a mirrored `pencilOnlyDrawing` property pushed down every
    /// `updateFloatingOverlay()` pass.
    ///
    /// **Needs an actual selection, unlike the vector test.** Move with no selection on a *raster*
    /// layer rasterizes the whole cel (`CanvasManager.beginMove`), so the lifted piece is exactly the
    /// canvas rect and there is no "outside" left to tap — confirmed by hand in the simulator: the tap
    /// landed inside the box every time. `testMoveWithNoSelectionLiftsWholeLayerAndCommits` already
    /// documents that this is the raster arm's normal shape, not a bug. So this test rectangle-selects
    /// the stroke first, the same setup `testRectangleSelectThenFillBakesPixels` uses, which gives the
    /// lifted piece a box smaller than the canvas the way a lassoed vector float already has one.
    ///
    /// **The toggle flips over a live selection, not a live float**, and that is deliberate: a
    /// selection is not one of the four things `commitAllInteractiveState()` resolves (fill, shape,
    /// text, float), so opening the Actions menu to flip the preference leaves it standing — only
    /// *engaging Move* has to wait until after the flip.
    func testAFingerTapAwayLeavesARasterMoveFloatingWhilePencilOnlyModeIsOn() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setFingersCanPaint(app, to: true) // pencil-only mode off, so the setup below can use a finger

        addRasterLayer(app)
        dragOnCanvas(app, from: CGVector(dx: 0.2, dy: 0.2), to: CGVector(dx: 0.35, dy: 0.2))

        app.buttons["toolbar.selectButton"].tap()
        let rectangleMode = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()
        dragOnCanvas(app, from: CGVector(dx: 0.15, dy: 0.12), to: CGVector(dx: 0.4, dy: 0.28))

        setFingersCanPaint(app, to: false) // pencil-only mode on — safe: a selection is live, no float

        let doneButton = app.buttons["moveBar.doneButton"]
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "setup: Move should lift the selection")

        // A finger tap far from the box — well outside the selected rectangle, still on the canvas.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42)).tap()

        XCTAssertTrue(doneButton.exists,
                      "a finger tap elsewhere must not bake the raster Move while pencil-only mode is on")

        // Self-check, the same shape as the vector test: flipping the preference back off bakes the
        // still-floating piece (no selection survives a bake, so a fresh one is drawn), and the
        // identical tap this time, pencil-only mode off, should commit it.
        setFingersCanPaint(app, to: true)
        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()
        dragOnCanvas(app, from: CGVector(dx: 0.15, dy: 0.12), to: CGVector(dx: 0.4, dy: 0.28))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "setup: Move should lift the selection a second time")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42)).tap()
        XCTAssertTrue(doneButton.waitForNonExistence(timeout: 5),
                      "self-check: with pencil-only mode off, the same finger tap should bake the Move")
    }
}
