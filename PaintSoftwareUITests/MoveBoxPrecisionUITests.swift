import XCTest

/// **A touch beside the dragging pen makes the Move box a fifth as fast, on the real overlays** —
/// TODO (146). XCUITest cannot synthesise a Pencil, so a finger stands in for the pen and a second
/// finger for the one the owner presses: the rule is touch-type-agnostic on purpose
/// (`PrecisionDrag`), and `MoveBoxPrecisionLogicTests` owns the rule itself and the take. What this
/// file asserts is what only the overlays can: **the touch counter reaches the drag**, **the drag does
/// not jump**, **the finger that makes a drag precise
/// does not also pan the canvas or put the box down when it lifts**, and **the same holds on the
/// raster Move box**, whose pans are a different mechanism from the vector box's raw touches.
///
/// **What this cannot drive, and says so:** the pen. Whether a real Pencil's `UITouch` reaches the
/// host's `TouchCountRecognizer` while it rests on the overlay is the one link left unproven by a
/// finger — the shape snap's own capture says it does (`counter:1/0`), and nothing here contradicts
/// it. A device check is a pen on a box and a finger beside it.
final class MoveBoxPrecisionUITests: PaintUITestCase {

    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **The picture's box, dragged three times: alone, with a finger landing beside it after the drag
    /// began and drifting as a resting finger does, and with one that rests perfectly still.** The first
    /// is the control — and the proof that the baseline is read correctly, since a count that is off by
    /// one would slow it. The second is the owner's gesture, and a drift is what a two-finger pan is
    /// made of. The third lifts as a tap, which is what commits a box when nothing is dragging it.
    ///
    /// **A finger already down when the drag begins (a resting palm) is not driven here**, and not for
    /// want of trying: the event synthesiser re-issues a touch's identity when a second finger lands
    /// first, so the dragging touch is replaced mid-drag and what the overlay sees is not what a hand
    /// does. That rule — the baseline, and its ratchet — is `MoveBoxPrecisionLogicTests`'.
    func testAFingerPressedBesideAVectorBoxDragMakesItAFifthAsFarAndLeavesTheCanvasAlone() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedImage"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = try XCTUnwrap(settledMoveBox(app), "the import lifts the picture into a Move box")
        let transform = readTransform(app)

        // Down from the box's centre, 150 points on a host that is about a thousand high.
        let centre = CGVector(dx: start.midX, dy: start.midY)
        let drag = CGVector(dx: 0, dy: 150)
        let aside = CGVector(dx: 0.12, dy: 0.30)
        let drift = CGVector(dx: 30, dy: 20)

        // 1. Control: nothing beside the drag.
        try dragWithAFingerHeldBeside(canvas, from: centre, delta: drag, holding: nil)
        let afterControl = try XCTUnwrap(settledMoveBox(app), "the control drag leaves the box up")
        let controlTravel = afterControl.minY - start.minY
        XCTAssertGreaterThan(controlTravel, 0.10,
                             "PREMISE: an unaccompanied drag is not slowed (it travelled \(controlTravel))")

        // 2. A finger lands beside the drag after it began, and drifts as a resting finger does.
        let from = CGVector(dx: afterControl.midX, dy: afterControl.midY)
        try dragWithAFingerHeldBeside(canvas, from: from, delta: drag, holding: aside, holdDrift: drift)
        attachScreen("vector-after-the-precise-drag")
        let afterPrecise = try XCTUnwrap(settledMoveBox(app),
                                         "the box is still up: the finger that lifted away from it did not commit it")
        let preciseTravel = afterPrecise.minY - afterControl.minY
        XCTAssertEqual(readTransform(app), transform,
                       "the finger that slowed the drag did not pan the canvas: it is where it was (\(canvas.label))")
        XCTAssertEqual(preciseTravel / controlTravel, 0.2, accuracy: 0.06, canvas.label +
                       " the same drag with a finger beside it moves the box a fifth as far "
                       + "(\(preciseTravel) against \(controlTravel))")
        XCTAssertEqual(afterPrecise.width, afterControl.width, accuracy: 0.002,
                       "…and it is still the same box")
        XCTAssertEqual(readTransform(app), transform,
                       "…and the finger that slowed the drag did not pan the canvas: it is where it was")


        // 3. The same, with the second finger resting perfectly still and lifting as a tap — the case
        // that would put the box down under the pen if the tap-away were still offered the touch.
        let third = CGVector(dx: afterPrecise.midX, dy: afterPrecise.midY)
        try dragWithAFingerHeldBeside(canvas, from: third, delta: drag, holding: aside)
        let afterStill = try XCTUnwrap(settledMoveBox(app),
                                       "the box is still up: a finger that lifts as a tap away from it did not commit it")
        XCTAssertEqual((afterStill.minY - afterPrecise.minY) / controlTravel, 0.2, accuracy: 0.06,
                       "…and it was slowed just the same")
        attachScreen("vector-box-after-the-three-drags")
    }

    /// **The same on the raster Move box**, which is the recordable one's mechanism: ten pans on a
    /// total-claim overlay rather than raw touches. A filled block is selected and lifted, and its
    /// ink is measured off the canvas before and after each drag — the box has no published frame,
    /// but the piece it carries is drawn where the box is.
    func testAFingerPressedBesideARasterBoxDragMakesItAFifthAsFar() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        addRasterLayer(app)

        // `DistortUITests`' own set-up, so the geometry is the one that already drives this box.
        app.buttons["toolbar.selectButton"].tap()
        let rectangleMode = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()
        dragOnCanvas(app, from: CGVector(dx: 0.55, dy: 0.22), to: CGVector(dx: 0.80, dy: 0.40))
        let fillButton = app.buttons["selectPanel.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap()
        let filled = try inkTopLeft(try settledProbe(canvas),
                                    in: CGRect(x: 0.50, y: 0.19, width: 0.36, height: 0.27))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move lifts the filled block")
        attachScreen("raster-before-the-drags")

        let window = CGRect(x: 0.40, y: 0.16, width: 0.55, height: 0.50)
        func top() throws -> CGPoint {
            try inkTopLeft(try settledProbe(canvas, window: window), in: window)
        }
        let start = try top()
        let transform = readTransform(app)
        // Inside the block, the way `DistortUITests` grabs its band.
        let centre = CGVector(dx: filled.x + 0.16, dy: filled.y + 0.09)
        let drag = CGVector(dx: 0, dy: 150)

        try dragWithAFingerHeldBeside(canvas, from: centre, delta: drag, holding: nil)
        attachScreen("raster-after-the-control-drag")
        let afterControl = try top()
        let controlTravel = afterControl.y - start.y
        XCTAssertGreaterThan(controlTravel, 0.05,
                             "PREMISE: an unaccompanied drag moves the piece (it travelled \(controlTravel))")

        try dragWithAFingerHeldBeside(canvas, from: CGVector(dx: centre.dx, dy: centre.dy + controlTravel),
                                      delta: drag, holding: CGVector(dx: 0.20, dy: 0.60),
                                      holdDrift: CGVector(dx: 30, dy: 20))
        let afterPrecise = try top()
        let preciseTravel = afterPrecise.y - afterControl.y
        XCTAssertEqual(preciseTravel / controlTravel, 0.2, accuracy: 0.07,
                       "with a finger beside it the piece moves a fifth as far "
                       + "(\(preciseTravel) against \(controlTravel))")
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists,
                      "the finger that lifted away from the box did not bake the piece")
        XCTAssertEqual(readTransform(app), transform, "…and it did not pan the canvas")

        // The finger that rests perfectly still lifts as a tap: with nothing dragging the piece that
        // is what bakes it.
        try dragWithAFingerHeldBeside(canvas,
                                      from: CGVector(dx: centre.dx, dy: centre.dy + controlTravel + preciseTravel),
                                      delta: drag, holding: CGVector(dx: 0.20, dy: 0.60))
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists,
                      "a still finger lifting as a tap away from the box did not bake the piece")
        attachScreen("raster-box-after-the-three-drags")
    }
}
