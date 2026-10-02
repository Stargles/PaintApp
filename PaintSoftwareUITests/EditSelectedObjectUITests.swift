import XCTest

/// **TODO (116) — Select → Edit Text, from a fresh document.** The owner: *"When I select a textbox
/// with the select tool, there should be another edit option to edit the text, which will bring up
/// the text menu, and I can change it in real time. It also should bring up the move box for that
/// text where I can move it."*
///
/// The journey, and what the artist does next at each step: Add → Add Text, tap where the words go and
/// type them, tap the brush to put the box down; tap Select, pick Rectangle and drag a loop around the
/// words; tap **Edit Text**; the text panel is up and the box is on the canvas with its grips — change
/// the size and the words change under the finger; drag the box by its edge and the words move; tap
/// the brush to put it down.
///
/// Every assertion is about what is **drawn**: ink measured off screenshots of the canvas, since the
/// stored recipe is exactly what a panel wired to nothing would leave correct.
/// `EditSelectedObjectLogicTests` holds the dispatch and the model.
final class EditSelectedObjectUITests: PaintUITestCase {

    // MARK: - Measuring in screen points
    //
    // **Everything is in absolute screen points, converted to `canvas.host`'s normalised space only at
    // the instant of a reading.** Once the software keyboard is up the editor's *accessibility* frame
    // shrinks (973 pt against 1356 here) while the picture stays exactly where it was, so a normalised
    // coordinate means two different screen points before and after — which is how this test's first
    // drafts aimed a drag 100 pt above the words and measured the Text panel's card as ink. Points are
    // the one currency that does not move.

    /// `rect` (screen points) as a window of `canvas.host`'s own frame *now*.
    private func window(_ rect: CGRect, in canvas: XCUIElement) -> CGRect {
        let frame = canvas.frame
        return CGRect(x: (rect.minX - frame.minX) / frame.width, y: (rect.minY - frame.minY) / frame.height,
                      width: rect.width / frame.width, height: rect.height / frame.height)
    }

    /// What the words look like inside `rect`: where the ink starts, where it ends, and how much of it
    /// there is — all in screen points, off one settled screenshot.
    private func reading(_ canvas: XCUIElement, in rect: CGRect) throws -> (topLeft: CGPoint, right: CGFloat, ink: Int) {
        let frame = canvas.frame
        let win = window(rect, in: canvas)
        let probe = try settledProbe(canvas, window: win)
        let tl = try inkTopLeft(probe, in: win)
        var right = win.minX, ink = 0
        let columns = 320, rows = 120
        for xi in 0..<columns {
            let x = win.minX + win.width * Double(xi) / Double(columns)
            for yi in 0..<rows where probe(x, win.minY + win.height * Double(yi) / Double(rows)) {
                right = max(right, x)
                ink += 1
            }
        }
        return (CGPoint(x: frame.minX + tl.x * frame.width, y: frame.minY + tl.y * frame.height),
                frame.minX + right * frame.width, ink)
    }

    /// A drag between two screen points — `dragOnCanvas`'s press-and-drag, aimed in points.
    private func drag(_ app: XCUIApplication, from: CGPoint, to: CGPoint) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: from.x, dy: from.y))
            .press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: to.x, dy: to.y)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// Waits for the keyboard to be gone **and the host's frame to be back where it started** — the
    /// editor is laid out above the software keyboard and its dismissal animates the layout back, and
    /// everything measured or aimed in that window is in a layout that is about to move. Fails if it
    /// never comes back: that is the defect `EditorKeyboardLayoutUITests` pins.
    private func waitForTheLayoutToSettle(_ app: XCUIApplication, _ canvas: XCUIElement, restoring host: CGRect) {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let frame = canvas.frame
            if app.keyboards.count == 0 && abs(frame.minY - host.minY) < 1 && abs(frame.height - host.height) < 1 {
                Thread.sleep(forTimeInterval: 0.6)
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("canvas.host's frame did not return to \(host) within 15 s of the keyboard leaving; it reads "
                + "\(canvas.frame), keyboards: \(app.keyboards.count)")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSelectEditTextReopensTheBoxChangesItLiveAndMovesIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let host = canvas.frame

        // 1. Put some words on the canvas: Add → Add Text, tap, type, brush.
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "PREMISE: the text panel is up")
        let origin = CGVector(dx: 0.55, dy: 0.30)
        // The box's top-left is the point that was tapped (`beginTextSession(at:)`), which is what lets
        // step 5 aim at the box's edge without reading the box.
        let boxTopLeft = CGPoint(x: host.minX + origin.dx * host.width, y: host.minY + origin.dy * host.height)
        canvas.coordinate(withNormalizedOffset: origin).tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: a live text box (text:\(readTextState(app)))")
        typeIntoTextBox("Hello", app, at: CGPoint(x: boxTopLeft.x + 0.01 * host.width, y: boxTopLeft.y + 0.01 * host.height))
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the box down (text:\(readTextState(app)))")

        // 2. Select tool → Rectangle. **Before measuring anything**: the editor was laid out above the
        //    keyboard that has just gone, and its dismissal is still animating the layout back.
        waitForTheLayoutToSettle(app, canvas, restoring: host)
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()

        // **Above the text panel's top edge (0.336 of the host), and below the black margin over the
        // paper (0.14)**: the panel is a dark card and a dark pixel is "ink" to the probe, so a window
        // that reached it would measure the card.
        let words = CGRect(x: host.minX + 0.45 * host.width, y: host.minY + 0.18 * host.height,
                           width: 0.54 * host.width, height: 0.15 * host.height)
        let before = try reading(canvas, in: words)
        XCTAssertGreaterThan(before.ink, 40, "PREMISE: the words are on the canvas")
        attach(app, "words-placed")

        // A loop around the words: Edit Text is offered, titled for it.
        XCTAssertFalse(app.buttons["selectPanel.editTextButton"].exists, "nothing is selected yet")
        drag(app, from: CGPoint(x: before.topLeft.x - 0.05 * host.width, y: before.topLeft.y - 0.04 * host.height),
             to: CGPoint(x: before.topLeft.x + 0.38 * host.width, y: before.topLeft.y + 0.10 * host.height))
        let edit = app.buttons["selectPanel.editTextButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "a loop around the words offers an Edit entry")
        XCTAssertEqual(edit.label, "Edit Text", "titled for what it will open")
        XCTAssertFalse(app.buttons["selectPanel.editGradientButton"].exists, "the loop caught no gradient, so no Edit Gradient")
        attach(app, "select-offers-edit-text")

        // 3. Edit Text: the text panel, and the box with its grips on the canvas.
        edit.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "Edit Text brings up the text panel")
        XCTAssertTrue(waitForTextState(app, "box", "editing"),
                      "…and the box is on the canvas, a live session on those words (text:\(readTextState(app)))")
        XCTAssertFalse(app.buttons["selectPanel.editTextButton"].exists, "the Select panel stood aside")
        attach(app, "edit-text-box-and-panel")

        // 4. Change it live: the size slider enlarges the words under the finger.
        let size = app.sliders["textPanel.sizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.adjust(toNormalizedSliderPosition: 0.22)
        let bigger = try reading(canvas, in: words)
        XCTAssertGreaterThan(Double(bigger.ink), Double(before.ink) * 1.3,
                             "the words got bigger as the slider moved (ink \(before.ink) -> \(bigger.ink))")
        XCTAssertEqual(bigger.topLeft.x, before.topLeft.x, accuracy: 6, "…about the same corner: the box grew in place")
        attach(app, "edit-text-resized-live")

        // 5. Move it: the move band is the 22 pt ring just outside the box, and the grips sit on its
        //    corners and the midpoints of its sides — so the band is aimed at 10 pt above the top edge
        //    a quarter of the way along, clear of both, which a drag would otherwise resize with.
        let boxWidth = bigger.right - boxTopLeft.x
        let start = CGPoint(x: boxTopLeft.x + 0.25 * boxWidth, y: boxTopLeft.y - 10)
        let delta = CGVector(dx: 0.10 * host.width, dy: -0.05 * host.height)
        drag(app, from: start, to: CGPoint(x: start.x + delta.dx, y: start.y + delta.dy))
        let moved = try reading(canvas, in: words)
        XCTAssertGreaterThan(moved.topLeft.x - bigger.topLeft.x, 0.04 * host.width,
                             "the words moved right (\(bigger.topLeft.x) -> \(moved.topLeft.x))")
        XCTAssertLessThan(moved.topLeft.y - bigger.topLeft.y, -0.02 * host.height,
                          "…and up (\(bigger.topLeft.y) -> \(moved.topLeft.y))")
        attach(app, "edit-text-moved")

        // 6. Put it down: the brush commits the session, and the words stay where they were left.
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"))
        let final = try reading(canvas, in: words)
        XCTAssertEqual(final.topLeft.x, moved.topLeft.x, accuracy: 8, "committed where it was moved to")
        XCTAssertEqual(final.topLeft.y, moved.topLeft.y, accuracy: 8)
        XCTAssertGreaterThan(Double(final.ink), Double(before.ink) * 1.3, "…and at the size it was changed to")
    }

    /// **One button per kind, from a fresh document** — the owner, 2026-10-01: a loop that catches a
    /// text box and a gradient offers *"Edit Text" and "Edit Gradient" side by side, each opening its
    /// own panel.* A gradient over the artwork, words on top of it, a loop round the words: both
    /// buttons are in the Select panel, Edit Gradient opens the gradient's card and not the text
    /// panel (the words are on top, which is what a topmost-wins entry would have opened), and — with
    /// the loop still up — Edit Text opens the words' panel with their box on the canvas.
    func testALoopRoundTextOverAGradientOffersEditTextAndEditGradientEachOpeningItsOwnPanel() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let host = canvas.frame

        // 1. The gradient: Add → Linear Gradient, then Done.
        app.buttons["toolbar.addButton"].tap()
        let gradientRow = app.buttons["add.linearGradientRow"]
        XCTAssertTrue(gradientRow.waitForExistence(timeout: 5))
        gradientRow.tap()
        let gradientDone = app.buttons["gradientPanel.doneButton"]
        XCTAssertTrue(gradientDone.waitForExistence(timeout: 5), "PREMISE: the gradient's card is up")
        gradientDone.tap()
        XCTAssertTrue(gradientDone.waitForNonExistence(timeout: 5), "PREMISE: …and closed")

        // 2. The words, on top of it: Add → Add Text, tap, type, brush.
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "PREMISE: the text panel is up")
        let boxTopLeft = CGPoint(x: host.minX + 0.55 * host.width, y: host.minY + 0.30 * host.height)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.30)).tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: a live text box (text:\(readTextState(app)))")
        typeIntoTextBox("Hello", app, at: CGPoint(x: boxTopLeft.x + 0.01 * host.width, y: boxTopLeft.y + 0.01 * host.height))
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the box down (text:\(readTextState(app)))")
        waitForTheLayoutToSettle(app, canvas, restoring: host)

        // 3. Select → Rectangle, a loop round the words — which the gradient under them is under too.
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        XCTAssertFalse(app.buttons["selectPanel.editTextButton"].exists, "nothing is selected yet")
        XCTAssertFalse(app.buttons["selectPanel.editGradientButton"].exists, "…so neither entry is offered")
        drag(app, from: CGPoint(x: boxTopLeft.x - 0.05 * host.width, y: boxTopLeft.y - 0.04 * host.height),
             to: CGPoint(x: boxTopLeft.x + 0.38 * host.width, y: boxTopLeft.y + 0.10 * host.height))

        // 4. Both entries, side by side, each titled for what it opens.
        let editText = app.buttons["selectPanel.editTextButton"]
        let editGradient = app.buttons["selectPanel.editGradientButton"]
        XCTAssertTrue(editText.waitForExistence(timeout: 5), "the loop caught the words, so Edit Text is offered")
        XCTAssertTrue(editGradient.exists, "…and the gradient under them, so Edit Gradient is offered beside it")
        XCTAssertEqual(editText.label, "Edit Text")
        XCTAssertEqual(editGradient.label, "Edit Gradient")
        XCTAssertLessThan(editText.frame.minX, editGradient.frame.minX, "Text first, then Gradient — a fixed order")
        XCTAssertEqual(editText.frame.midY, editGradient.frame.midY, accuracy: 2, "side by side in one row")
        attach(app, "select-offers-both-edit-entries")

        // 5. Edit Gradient opens the gradient's own card on the gradient — not the words' panel.
        editGradient.tap()
        let angle = app.sliders["gradientPanel.angleSlider"]
        XCTAssertTrue(angle.waitForExistence(timeout: 5), "Edit Gradient opens the gradient panel")
        XCTAssertEqual(angle.value as? String, "0", "on the gradient that was caught")
        XCTAssertFalse(app.buttons["textPanel.fontButton"].exists, "…and not the text panel, though the words are on top")
        XCTAssertTrue(waitForTextState(app, "none"), "no text session was opened (text:\(readTextState(app)))")
        attach(app, "edit-gradient-opened")
        app.buttons["gradientPanel.doneButton"].tap()
        XCTAssertTrue(angle.waitForNonExistence(timeout: 5))

        // 6. The loop is still up. Back to Select, and Edit Text opens the words' panel and box.
        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(editText.waitForExistence(timeout: 5), "the loop outlived the gradient's card")
        editText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "Edit Text brings up the text panel")
        XCTAssertTrue(waitForTextState(app, "box", "editing"),
                      "…with a live session on the words (text:\(readTextState(app)))")
        XCTAssertFalse(app.sliders["gradientPanel.angleSlider"].exists, "…and not the gradient's card")
        attach(app, "edit-text-opened")
    }
}
