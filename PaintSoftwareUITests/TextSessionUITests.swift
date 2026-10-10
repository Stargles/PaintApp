import XCTest

/// **The text box's session, from a fresh document — TODO "Text follow-ups".** The owner:
/// *"Select a text, click edit text, then click anywhere on the canvas. A new textbox for some reason
/// comes up for some reason, which has entirely no reason to be there"*, and *"When I create a text,
/// then click on the board to place the box and start writing, I want to still be able to adjust the
/// things on that menu after I make the text without having to select the text again."*
///
/// Everything asserted is what is **drawn or exposed** (the `text:` field is the overlay's own state,
/// and ink is measured off screenshots of the canvas): the recipe the panel writes is exactly what a
/// panel wired to nothing would leave correct.
final class TextSessionUITests: PaintUITestCase {

    /// A tap at an absolute screen point — **points, not the host's normalised space**, because the
    /// canvas pans to keep the box clear of the keyboard.
    private func tap(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    /// A point on the paper clear of the box and of the docked panel, in screen points.
    private func awayPoint(in host: CGRect) -> CGPoint {
        CGPoint(x: host.minX + 0.20 * host.width, y: host.minY + 0.19 * host.height)
    }

    /// **The panel is there while the box is being written, and what it changes is the box.** The
    /// artist places the box and types; the font, size and colour controls are still on screen, and
    /// the size slider enlarges the words under the finger. What the artist does next: put the text
    /// down by tapping away or by picking a tool.
    func testThePanelStaysUpAfterPlacingTheBoxAndRestylesTheWordsBeingWritten() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let host = canvas.frame
        _ = writeWords("Hello", app, canvas)

        let size = app.sliders["textPanel.sizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5),
                      "the Text panel is still up once the box is placed and written in (text:\(readTextState(app)))")
        XCTAssertTrue(app.buttons["textPanel.fontButton"].exists, "…with its font control")
        attachScreenshot(app, "panel-up-while-typing")

        let words = wordsWindow(in: host)
        let before = try inkReading(canvas, in: words)
        XCTAssertGreaterThan(before.ink, 40, "PREMISE: the words are on the canvas")
        size.adjust(toNormalizedSliderPosition: 0.30)
        let bigger = try inkReading(canvas, in: words)
        XCTAssertGreaterThan(Double(bigger.ink), Double(before.ink) * 1.3,
                             "the words being written got bigger as the slider moved (ink \(before.ink) -> \(bigger.ink))")
        XCTAssertTrue(waitForTextState(app, "box", "editing"),
                      "…and it is still the open box that was restyled (text:\(readTextState(app)))")
        attachScreenshot(app, "panel-restyled-the-open-box")
    }

    /// **A tap away from the box being written puts it down and places nothing** — and the next tap
    /// places a box. The words stay where they were put; the panel stays up for the next one.
    func testATapAwayFromTheBoxBeingWrittenPutsItDownAndPlacesNothing() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let host = canvas.frame
        _ = writeWords("Hello", app, canvas)
        let words = wordsWindow(in: host)
        XCTAssertGreaterThan(try inkReading(canvas, in: words).ink, 40, "PREMISE: the words are on the canvas")

        tap(app, at: awayPoint(in: host))
        XCTAssertTrue(waitForTextState(app, "none"), "the tap put the box down (text:\(readTextState(app)))")
        // A box the tap placed would be republished on the next SwiftUI pass, so a single read right
        // after it can still say "none" — hold the question open for a moment.
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(readTextState(app), "none", "…and placed nothing under the finger")
        waitForTheKeyboardToLeave(app)
        let after = try inkReading(canvas, in: words)
        XCTAssertGreaterThan(after.ink, 40, "the words are still on the canvas, put down where they were written")
        XCTAssertTrue(app.buttons["textPanel.fontButton"].exists, "the Text panel is still up for the next box")
        attachScreenshot(app, "tap-away-put-the-box-down")

        tap(app, at: awayPoint(in: host))
        XCTAssertTrue(waitForTextState(app, "editing"), "the next tap places the next box (text:\(readTextState(app)))")
    }

    /// **The same rule when the box was re-opened from Select → Edit Text** — the owner's report. Words
    /// put down with the brush; Select, a loop round them, Edit Text; then a tap on empty canvas puts
    /// the box down and no new one comes up.
    func testATapAwayFromAnEditedBoxPlacesNoNewBox() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let host = canvas.frame
        let boxTopLeft = writeWords("Hello", app, canvas)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the box down (text:\(readTextState(app)))")
        waitForTheKeyboardToLeave(app)

        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        let words = wordsWindow(in: host)
        let written = try inkReading(canvas, in: words)
        dragInPoints(app, from: CGPoint(x: boxTopLeft.x - 0.03 * host.width, y: boxTopLeft.y - 0.015 * host.height),
                     to: CGPoint(x: boxTopLeft.x + 0.38 * host.width, y: boxTopLeft.y + 0.07 * host.height))
        let edit = app.buttons["selectPanel.editTextButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "a loop round the words offers Edit Text")
        edit.tap()
        XCTAssertTrue(waitForTextState(app, "box", "editing"), "Edit Text opens the box (text:\(readTextState(app)))")

        tap(app, at: awayPoint(in: host))
        XCTAssertTrue(waitForTextState(app, "none"), "the tap put the edited box down (text:\(readTextState(app)))")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(readTextState(app), "none", "…and no new box came up under it")
        let after = try inkReading(canvas, in: words)
        XCTAssertEqual(Double(after.ink), Double(written.ink), accuracy: Double(written.ink) * 0.15,
                       "the words are still there (ink \(written.ink) -> \(after.ink))")
        attachScreenshot(app, "edit-text-tap-away")
    }

    /// **The text's colour is picked in the app's own colour panel, and the words being written are drawn
    /// in it.** The Colour row of the Text panel is a swatch that raises `ColorPickerPanel` — the picker the
    /// brush, the paper and every effect use, with its palettes, Recent strip and eyedropper — not a
    /// system popover over the canvas. What the artist does next: the swatch reads the colour they chose,
    /// a touch outside closes the panel, and the box is still open to keep writing in.
    func testThePanelsColourSwatchRaisesTheAppsOwnPickerAndTheWordsTakeItsColour() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let host = canvas.frame
        _ = writeWords("Hello", app, canvas)
        let words = canvasWindow(wordsWindow(in: host), in: canvas)

        /// How many pixels of the words' window match `predicate`, off one screenshot.
        func count(_ predicate: (RGBA) -> Bool) throws -> Int {
            let pixel = try pixelProbe(canvas)
            var hits = 0
            for xi in 0..<320 {
                for yi in 0..<120 where predicate(pixel(words.minX + words.width * Double(xi) / 320,
                                                         words.minY + words.height * Double(yi) / 120)) {
                    hits += 1
                }
            }
            return hits
        }
        func isRedInk(_ p: RGBA) -> Bool { isRed(p) }
        func isBlackInk(_ p: RGBA) -> Bool { isInk(p) }
        let black = try settled { try count(isBlackInk) }
        XCTAssertGreaterThan(black, 40, "PREMISE: the words are black on the paper")
        XCTAssertEqual(try count(isRedInk), 0, "PREMISE: and nothing on the paper is red")

        let swatch = app.buttons["textPanel.colorSwatch"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the Text panel has a Colour swatch")
        XCTAssertEqual((swatch.value as? String)?.uppercased(), "000000", "PREMISE: the swatch reads the words' colour")
        swatch.tap()
        XCTAssertTrue(canvasMenu(app, "textColour").waitForExistence(timeout: 5),
                      "the swatch raised the app's own presentation over the canvas, not a system popover")
        let square = app.otherElements["colorPanel.svSquare"]
        XCTAssertTrue(square.waitForExistence(timeout: 5), "…and it is the app's colour panel")
        XCTAssertTrue(app.buttons["colorPanel.tab.palettes"].exists, "…with its palettes")
        attachScreenshot(app, "text-colour-panel")

        // Top right of the square is full saturation and brightness, and the panel opens on hue 0.
        dragWithinElement(square, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.98, dy: 0.02))
        // The panel covers its own swatch, so a touch that does nothing else (`tapAway`) is what closes it.
        tapAway(app)
        XCTAssertTrue(square.waitForNonExistence(timeout: 5), "a touch outside closes the panel again")
        XCTAssertTrue(waitForTextState(app, "editing"), "…and the box is still open to write in (text:\(readTextState(app)))")

        let value = swatch.value as? String ?? ""
        XCTAssertEqual(value.count, 6, "the swatch reads the colour that was picked, opaque (\(value))")
        let channels = stride(from: 0, to: 6, by: 2).map { i -> Int in
            let start = value.index(value.startIndex, offsetBy: i)
            return Int(value[start..<value.index(start, offsetBy: 2)], radix: 16) ?? -1
        }
        XCTAssertGreaterThan(channels[0], 0xE0, "…which is red (\(value))")
        XCTAssertLessThan(max(channels[1], channels[2]), 0x20, "…with no green or blue in it (\(value))")
        let deadline = Date().addingTimeInterval(10)
        var red = try count(isRedInk)
        while red <= 40, Date() < deadline { Thread.sleep(forTimeInterval: 0.4); red = try count(isRedInk) }
        XCTAssertGreaterThan(red, 40, "the words being written are drawn in the colour that was picked (red pixels \(red))")
        XCTAssertLessThan(try count(isBlackInk), black / 5, "…and no longer in black")
        attachScreenshot(app, "text-drawn-in-the-picked-colour")
    }
}
