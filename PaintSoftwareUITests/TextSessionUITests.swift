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
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height,
                             "PREMISE: the edited-text workflow is drawn in landscape")
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
        XCTAssertGreaterThan(written.ink, 40, "PREMISE: visible text is present before reopening")
        attachScreenshot(XCUIScreen.main, "text-edit-1-before-reopening")
        dragInPoints(app, from: CGPoint(x: boxTopLeft.x - 0.03 * host.width, y: boxTopLeft.y - 0.015 * host.height),
                     to: CGPoint(x: boxTopLeft.x + 0.38 * host.width, y: boxTopLeft.y + 0.07 * host.height))
        let edit = app.buttons["selectPanel.editTextButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "a loop round the words offers Edit Text")
        edit.tap()
        XCTAssertTrue(waitForTextState(app, "box", "editing"), "Edit Text opens the box (text:\(readTextState(app)))")
        attachScreenshot(XCUIScreen.main, "text-edit-2-overlay-open")

        tap(app, at: awayPoint(in: host))
        XCTAssertTrue(waitForTextState(app, "none"), "the tap put the edited box down (text:\(readTextState(app)))")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(readTextState(app), "none", "…and no new box came up under it")
        let after = try inkReading(canvas, in: words)
        XCTAssertEqual(Double(after.ink), Double(written.ink), accuracy: Double(written.ink) * 0.15,
                       "the words are still there (ink \(written.ink) -> \(after.ink))")
        attachScreenshot(XCUIScreen.main, "edit-text-tap-away")
    }

    /// **The text's colour is picked in the app's own colour panel, and the words being written are drawn
    /// in it.** The Colour row of the Text panel is a swatch that raises `ColorPickerPanel` — the picker the
    /// brush, the paper and every effect use, with its palettes, Recent strip and eyedropper — not a
    /// system popover over the canvas. What the artist does next: the swatch reads the colour they chose,
    /// a touch outside closes the panel, and the box is still open to keep writing in.
    func testThePanelsColourSwatchRaisesTheAppsOwnPickerAndTheWordsTakeItsColour() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height,
                             "PREMISE: the owner colour workflow is actually landscape")
        func currentRepairCount() throws -> Int {
            app.buttons["toolbar.settingsButton"].tap()
            let caught = app.staticTexts["recorder.freezesCaught"]
            XCTAssertTrue(caught.waitForExistence(timeout: 5), "PREMISE: Settings exposes the durable repair count")
            let number = caught.label.components(separatedBy: ": ").last ?? ""
            let count = try XCTUnwrap(Int(number), "PREMISE: the durable repair count is numeric (\(caught.label))")
            app.buttons["toolbar.settingsButton"].tap()
            return count
        }
        let repairsBefore = try currentRepairCount()
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let host = canvas.frame
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5), "PREMISE: Add offers a text box")
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5),
                      "PREMISE: the Text panel is up before placement")
        let size = app.sliders["textPanel.sizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5), "PREMISE: the existing Text size control is available")
        size.adjust(toNormalizedSliderPosition: 0.30)
        let topLeft = CGPoint(x: host.minX + Self.wordsOffset.dx * host.width,
                              y: host.minY + Self.wordsOffset.dy * host.height)
        canvas.coordinate(withNormalizedOffset: Self.wordsOffset).tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: the public placement opens text editing")
        typeIntoTextBox("Hello", app,
                        at: CGPoint(x: topLeft.x + 0.01 * host.width, y: topLeft.y + 0.01 * host.height))
        let space = app.keys["space"]
        XCTAssertTrue(space.waitForExistence(timeout: 5), "PREMISE: the live software keyboard exposes Space")
        space.tap()
        typeIntoTextBox("Kevin", app, at: .zero)
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: both words remain in the same live text box")
        let paper = visiblePaperRect(app, in: canvas)
        let visible = CGRect(x: host.minX + paper.minX * host.width,
                             y: host.minY + paper.minY * host.height,
                             width: paper.width * host.width, height: paper.height * host.height)
        let window = wordsWindow(in: host).intersection(visible)
        XCTAssertFalse(window.isEmpty, "PREMISE: the colour sample is visible paper, not a black margin")
        assertAboveTheDock(app, canvas, dy: (window.maxY - host.minY) / host.height, "the colour sample")
        let words = canvasWindow(window, in: canvas)

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
        XCTAssertGreaterThan(black, 40, "PREMISE: both words are black on the paper")
        XCTAssertEqual(try count(isRedInk), 0, "PREMISE: and nothing on the paper is red")

        // Place a caret in the actual visible gap between the two words, then tap that caret to open
        // UIKit's edit menu. A selected-word menu omits Select All on this iPad.
        let ink = try inkReading(canvas, in: window)
        XCTAssertGreaterThan(ink.ink, 40, "PREMISE: the text is visibly drawn before selection")
        let boxValues = readField(app, "textbox:").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(boxValues.count, 4, "PREMISE: the live text exposes its drawn box")
        let box = CGRect(x: host.minX + CGFloat(boxValues[0]) * host.width,
                         y: host.minY + CGFloat(boxValues[1]) * host.height,
                         width: CGFloat(boxValues[2]) * host.width,
                         height: CGFloat(boxValues[3]) * host.height)
        let sample = canvasWindow(window, in: canvas)
        let pixels = try pixelProbe(canvas)
        var inkColumns = [Bool](repeating: false, count: 320)
        for xi in 0..<320 {
            let x = sample.minX + sample.width * Double(xi) / 320
            inkColumns[xi] = (0..<120).contains { yi in
                isInk(pixels(x, sample.minY + sample.height * Double(yi) / 120))
            }
        }
        let firstInkColumn = try XCTUnwrap(inkColumns.firstIndex(of: true), "PREMISE: sampled text has a first glyph column")
        let lastInkColumn = try XCTUnwrap(inkColumns.lastIndex(of: true), "PREMISE: sampled text has a last glyph column")
        var interwordGap: Range<Int>?
        var column = firstInkColumn
        while column <= lastInkColumn {
            if inkColumns[column] { column += 1; continue }
            let start = column
            while column <= lastInkColumn && !inkColumns[column] { column += 1 }
            let gap = start..<column
            if gap.count > (interwordGap?.count ?? 0) { interwordGap = gap }
        }
        let gap = try XCTUnwrap(interwordGap, "PREMISE: the two drawn words have a measured gap")
        XCTAssertGreaterThanOrEqual(gap.count, 2, "PREMISE: the measured word gap is wider than sampling error")
        let gapColumn = (gap.lowerBound + gap.upperBound) / 2
        let gapX = sample.minX + sample.width * Double(gapColumn) / 320
        let caretPoint = CGPoint(x: host.minX + gapX * host.width, y: box.midY)
        XCTAssertGreaterThan(box.width, 48, "PREMISE: the enlarged text box spans beyond two horizontal grip radii")
        XCTAssertGreaterThan(box.height, 48, "PREMISE: the enlarged text box spans beyond two vertical grip radii")
        let gripCenters = [
            CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.maxX, y: box.midY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.midX, y: box.maxY),
            CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.minX, y: box.midY),
            CGPoint(x: box.midX, y: box.minY - 36)
        ]
        let nearestGrip = gripCenters.map { hypot(caretPoint.x - $0.x, caretPoint.y - $0.y) }.min() ?? 0
        XCTAssertGreaterThan(nearestGrip, 22,
                             "PREMISE: the measured interword caret point clears all eight resize grips and the 36pt rotation grip; nearest is \(nearestGrip)pt")
        assertAboveTheDock(app, canvas, dy: (caretPoint.y - host.minY) / host.height,
                           "the public caret placement")
        let caret = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: caretPoint.x, dy: caretPoint.y))
        caret.tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: tapping the gap places a caret in the live editor")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "PREMISE: placing the caret keeps the software keyboard active")
        caret.tap()
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5),
                      "PREMISE: the caret's native edit menu offers Select All")
        guard selectAll.exists else { return }
        XCTAssertTrue(selectAll.isHittable, "PREMISE: Select All is visible and hittable in the native edit menu")
        attachScreenshot(XCUIScreen.main, "text-select-all-native-menu-open")
        selectAll.tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: Select All leaves the text editor active")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "PREMISE: Select All keeps the same software keyboard available")
        XCTAssertFalse(app.staticTexts["recorder.flightNotice"].waitForExistence(timeout: 3),
                       "PREMISE: no stranded-recognizer repair notice appears during its four-second display window")
        XCTAssertGreaterThan(try count(isBlackInk), 40,
                             "PREMISE: Select All leaves the words visibly drawn while editing remains active")
        attachScreenshot(XCUIScreen.main, "text-select-all-before-colour")

        let swatch = app.buttons["textPanel.colorSwatch"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the Text panel has a Colour swatch")
        XCTAssertEqual((swatch.value as? String)?.uppercased(), "000000", "PREMISE: the swatch reads the words' colour")
        swatch.tap()
        XCTAssertTrue(canvasMenu(app, "textColour").waitForExistence(timeout: 5),
                      "the swatch raised the app's own presentation over the canvas, not a system popover")
        let square = app.otherElements["colorPanel.svSquare"]
        XCTAssertTrue(square.waitForExistence(timeout: 5), "…and it is the app's colour panel")
        XCTAssertTrue(app.buttons["colorPanel.tab.palettes"].exists, "…with its palettes")
        attachScreenshot(XCUIScreen.main, "text-colour-panel")

        // Top right of the square is full saturation and brightness, and the panel opens on hue 0.
        dragWithinElement(square, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.98, dy: 0.02))
        // The panel covers its own swatch, so a touch that does nothing else (`tapAway`) is what closes it.
        tapAway(app)
        XCTAssertTrue(square.waitForNonExistence(timeout: 5), "a touch outside closes the panel again")
        XCTAssertTrue(waitForTextState(app, "editing"), "…and the box is still open to write in (text:\(readTextState(app)))")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "PREMISE: the software keyboard remains open after picking colour")

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
        XCTAssertGreaterThan(red, 40, "the whole selected text window shows the picked colour (red pixels \(red))")
        XCTAssertLessThan(try count(isBlackInk), black / 5, "…and no selected words remain black")
        attachScreenshot(XCUIScreen.main, "text-drawn-in-the-picked-colour")
        XCTAssertEqual(try currentRepairCount(), repairsBefore,
                       "the durable canvas repair count did not change during text selection and recolouring")
    }

    /// A public selection survives a live colour change: the next key replaces the word, rather
    /// than inserting before it. Measure while editing; ending the session may undo its follow pan.
    func testRestylingASelectedWordKeepsTheSelectionForTheNextTypedReplacement() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft), "setup: a brand-new document")
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height,
                             "PREMISE: the selection workflow is actually landscape")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let host = canvas.frame
        let transform = readTransform(app)
        XCTAssertFalse(transform.isEmpty, "PREMISE: the effective canvas transform is exposed")
        // Set size while the control is exposed: the software keyboard covers this row later.
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5), "PREMISE: Add offers a text box")
        addText.tap()
        let size = app.sliders["textPanel.sizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5), "PREMISE: text size is available before placement")
        size.adjust(toNormalizedSliderPosition: 0.30)
        let boxTopLeft = CGPoint(x: host.minX + Self.wordsOffset.dx * host.width,
                                 y: host.minY + Self.wordsOffset.dy * host.height)
        canvas.coordinate(withNormalizedOffset: Self.wordsOffset).tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: the public placement opens text editing")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "PREMISE: this control requires the software keyboard, not a paste longpress")
        let letter = "w"
        XCTAssertTrue(app.keys[letter].exists || app.keys[letter.uppercased()].exists,
                      "PREMISE: a real W/w software key is available")
        let inside = CGPoint(x: boxTopLeft.x + 0.01 * host.width, y: boxTopLeft.y + 0.01 * host.height)
        typeIntoTextBox(letter, app, at: inside)
        XCTAssertEqual(readTransform(app), transform, "PREMISE: typing here does not pan the paper")
        XCTAssertEqual(canvas.frame, host, "PREMISE: the host geometry stays fixed")

        let paper = visiblePaperRect(app, in: canvas)
        let visible = CGRect(x: host.minX + paper.minX * host.width,
                             y: host.minY + paper.minY * host.height,
                             width: paper.width * host.width, height: paper.height * host.height)
        let words = wordsWindow(in: host).intersection(visible)
        XCTAssertFalse(words.isEmpty, "PREMISE: the words have a visible paper window")
        assertAboveTheDock(app, canvas, dy: (words.maxY - host.minY) / host.height, "the words window")
        let single = try inkReading(canvas, in: words)
        XCTAssertGreaterThan(single.ink, 0, "PREMISE: the actual single glyph is drawn in black")
        let glyphWidth = single.right - single.topLeft.x
        XCTAssertGreaterThan(glyphWidth, 0, "PREMISE: the single glyph has a measured width")
        let near = CGRect(x: single.topLeft.x, y: words.minY, width: glyphWidth * 2, height: words.height)
        let far = CGRect(x: single.right + glyphWidth, y: words.minY, width: glyphWidth, height: words.height)
        let exterior = CGRect(x: single.topLeft.x - glyphWidth * 2, y: words.minY,
                              width: glyphWidth, height: words.height)
        XCTAssertTrue(words.contains(far.insetBy(dx: -glyphWidth, dy: 0)),
                      "PREMISE: the far band and another glyph of trailing room fit on visible paper")
        XCTAssertTrue(visible.contains(exterior), "PREMISE: untouched paper beside the word is visible")

        // Reuse the shared displayed-orientation pixel probe, not a second screenshot reader.
        func count(in rect: CGRect, matching predicate: (RGBA) -> Bool) throws -> Int {
            let pixel = try pixelProbe(canvas)
            let window = canvasWindow(rect, in: canvas)
            var hits = 0
            for xi in 0..<320 {
                for yi in 0..<120 where predicate(pixel(window.minX + window.width * Double(xi) / 320,
                                                         window.minY + window.height * Double(yi) / 120)) {
                    hits += 1
                }
            }
            return hits
        }
        XCTAssertEqual(try count(in: far, matching: { !isWhitish($0) }), 0,
                       "PREMISE: the single glyph leaves the entire measured far band white")
        XCTAssertEqual(try count(in: exterior, matching: { !isWhitish($0) }), 0,
                       "PREMISE: untouched exterior paper starts white")
        typeIntoTextBox(String(repeating: letter, count: 3), app, at: inside)
        XCTAssertEqual(readTransform(app), transform, "PREMISE: the four-glyph word does not pan the paper")
        XCTAssertEqual(canvas.frame, host, "PREMISE: the host geometry stays fixed while typing")
        XCTAssertGreaterThan(try settled { try count(in: far, matching: { isInk($0) }) }, 0,
                             "PREMISE: the actual old word occupies the far band")
        let word = try inkReading(canvas, in: words)
        XCTAssertLessThan(word.right + glyphWidth, words.maxX,
                          "PREMISE: the old word and another glyph fit without clipping")
        attachScreenshot(XCUIScreen.main, "text-selection-word-before")

        // The upper-left point is inside a 22 pt grip target. Use actual word ink that clears
        // every grip on the public, upright textbox hull; the midpoint can hit an edge grip too.
        let bounds = readField(app, "textbox:").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(bounds.count, 4, "PREMISE: the live text box exposes its actual drawn hull")
        let box = CGRect(x: host.minX + CGFloat(bounds[0]) * host.width,
                         y: host.minY + CGFloat(bounds[1]) * host.height,
                         width: CGFloat(bounds[2]) * host.width, height: CGFloat(bounds[3]) * host.height)
        XCTAssertFalse(box.isEmpty, "PREMISE: the drawn text hull is nonempty")
        let grips = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.midX, y: box.minY),
                     CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.midY),
                     CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.midX, y: box.maxY),
                     CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.minX, y: box.midY)]
        // Each origin/extent is rounded to four normalized decimals: a far corner can err by
        // at most .0001 of each host dimension. The rotation grip is 36 pt outside this fresh box.
        let requiredClearance = 22 + 0.0001 * hypot(host.width, host.height)
        let wordPixels = try pixelProbe(canvas)
        let wordWindow = canvasWindow(words, in: canvas)
        var selectionPoint: CGPoint?
        var clearance: CGFloat = 0
        for xi in 0..<320 {
            for yi in 0..<120 {
                let x = wordWindow.minX + wordWindow.width * Double(xi) / 320
                let y = wordWindow.minY + wordWindow.height * Double(yi) / 120
                guard isInk(wordPixels(x, y)) else { continue }
                let point = CGPoint(x: host.minX + x * host.width, y: host.minY + y * host.height)
                guard box.contains(point) else { continue }
                let distance = grips.map { hypot(point.x - $0.x, point.y - $0.y) }.min() ?? 0
                if distance > clearance {
                    clearance = distance
                    selectionPoint = point
                }
            }
        }
        XCTAssertGreaterThan(clearance, requiredClearance,
                             "PREMISE: actual word ink has a point outside every text-grip target")
        let pressPoint = try XCTUnwrap(selectionPoint, "PREMISE: a measured glyph-interior selection point")
        assertAboveTheDock(app, canvas, dy: (pressPoint.y - host.minY) / host.height, "the selection taps")
        // A public double-tap selects this single contiguous four-glyph word
        // through the native UITextView.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: pressPoint.x, dy: pressPoint.y)).doubleTap()
        attachScreenshot(XCUIScreen.main, "text-selection-public-edit-menu")
        XCTAssertTrue(app.menuItems["Cut"].waitForExistence(timeout: 5),
                      "PREMISE: the public edit menu exposes a nonempty selection")
        attachScreenshot(XCUIScreen.main, "text-selection-selected-word")

        // DrawingView binds this toolbar picker to activeEditColor, which restyles the live text.
        openColorPanel(app)
        let square = app.otherElements["colorPanel.svSquare"]
        dragWithinElement(square, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.98, dy: 0.02))
        closeColorPanel(app)
        let swatch = app.buttons["toolbar.colorButton"]
        let value = try XCTUnwrap(swatch.value as? String, "PREMISE: the live text exposes its picked colour")
        XCTAssertEqual(value.count, 6, "PREMISE: the text colour has three actual channels")
        let channels = stride(from: 0, to: 6, by: 2).map { i -> Int in
            let start = value.index(value.startIndex, offsetBy: i)
            return Int(value[start..<value.index(start, offsetBy: 2)], radix: 16) ?? -1
        }
        XCTAssertGreaterThan(channels[0], 0xE0, "PREMISE: the live text colour is red (\(value))")
        XCTAssertGreaterThanOrEqual(min(channels[1], channels[2]), 0, "PREMISE: the text colour channels parse")
        XCTAssertLessThan(max(channels[1], channels[2]), 0x20, "PREMISE: the text colour has little green/blue")
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: colour restyling keeps the text editor focused")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "PREMISE: the same software keyboard remains")
        // Shift may have changed since the first auto-capitalized glyph; this is the same W/w key.
        let replacement = app.keys[letter].exists ? app.keys[letter] : app.keys[letter.uppercased()]
        XCTAssertTrue(replacement.exists && replacement.isHittable,
                      "PREMISE: the SAME physical W/w key is actually hittable, without refocusing")
        XCTAssertEqual(readTransform(app), transform, "PREMISE: restyling does not move the measured picture")
        XCTAssertEqual(canvas.frame, host, "PREMISE: restyling keeps the host geometry")
        XCTAssertGreaterThan(try settled { try count(in: far, matching: { isRed($0) }) }, 0,
                             "PREMISE: the selected old word is actually drawn red in the far band")
        attachScreenshot(XCUIScreen.main, "text-selection-restyled")

        XCTAssertTrue(tapWhenHittable(replacement, "The same replacement letter"),
                      "PREMISE: the replacement key was delivered without another editor touch")
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: the replacement is still being edited")
        let drawn = try settled {
            [try count(in: near, matching: { isRed($0) }),
             try count(in: far, matching: { isRed($0) }),
             try count(in: exterior, matching: { !isWhitish($0) })]
        }
        XCTAssertEqual(readTransform(app), transform, "PREMISE: replacement keeps the measured picture in place")
        XCTAssertEqual(canvas.frame, host, "PREMISE: replacement keeps the host geometry")
        XCTAssertGreaterThan(drawn[0], 0, "the replacement is drawn in red near the original single glyph")
        XCTAssertEqual(drawn[1], 0, "the selected old word is gone: no red remains in its measured far band")
        XCTAssertEqual(drawn[2], 0, "the replacement leaves untouched exterior paper white")
        attachScreenshot(XCUIScreen.main, "text-selection-replaced-while-editing")
    }


    /// The independently qualified writer uses the real font400 -> whole-cel Move2x route.
    /// Opening its current package is a cold public workflow, with no app seed or stored geometry edits.
    func testAColdScaledAutoSizedLabelClosesUnchangedAndStillAcceptsARealTextEdit() throws {
        let requested = ProcessInfo.processInfo.environment["PAINTAPP_TEXT_AUTOSIZE_STAGE_UUID"]
        try XCTSkipUnless(requested != nil, "Requires the actual Move/current-writer fixture and the external storage observer")
        let nonce = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(requested))).uuidString
        let folderName = "Text Auto Size \(nonce)"
        let title = "Auto Sized 800 \(nonce)"
        let stage = try ExternalUIStage(nonce: nonce, directoryPrefix: "text-autosize-cold", context: folderName)
        let app = XCUIApplication()
        app.terminate()
        try stage.announce("prepare")
        let prepared = try stage.awaitMessage("prepared.ack")
        XCTAssertEqual(prepared.data, Data("\(nonce)|prepared|\(folderName)\n".utf8),
                       "PREMISE: the observer owns this nonce before the first app launch")
        addTeardownBlock {
            self.returnFromOwnedTextFolderToRoot(app, folderName: folderName)
        }
        app.launchArguments = []
        app.launch()
        let window = rotateDevice(app, to: .landscapeLeft)
        XCTAssertEqual(window.size, CGSize(width: 1080, height: 810), "PREMISE: the artist's landscape window")
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 15))
        app.buttons["gallery.newFolderButton"].tap()
        let name = app.textFields["gallery.folderRenameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.typeText("\(folderName)\n")
        let folder = app.buttons["gallery.folderTile.\(folderName)"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.tap()
        app.terminate()
        try stage.announce("ready-to-stage")
        let staged = try stage.awaitMessage("staged.ack")
        XCTAssertEqual(staged.data, Data("\(nonce)|staged|\(folderName)\n".utf8),
                       "PREMISE: only the qualified actual-writer package was staged")
        app.launch()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "PREMISE: the current package is reachable through Gallery")
        tile.tap()
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        closeLayerRail(app)
        let host = canvas.frame
        let transform = readTransform(app)
        func viewport() throws -> [Double] {
            let values = readTransform(app).split(separator: ",").compactMap { Double($0) }.filter(\.isFinite)
            XCTAssertEqual(values.count, 4, "PREMISE: the viewport exposes four finite values")
            return try XCTUnwrap(values.count == 4 ? values : nil)
        }
        let originalViewport = try viewport()
        let paper = visiblePaperRect(app, in: canvas, canvasSize: CGSize(width: 1400, height: 1200))
        let sample = paper.insetBy(dx: paper.width * 0.03, dy: paper.height * 0.02)
        let columns = 240, rows = 120
        func picture() throws -> [Bool] {
            let probe = try settledProbe(canvas, window: sample)
            var bits: [Bool] = []
            bits.reserveCapacity(columns * rows)
            for y in 0..<rows {
                for x in 0..<columns {
                    bits.append(probe(sample.minX + sample.width * (Double(x) + 0.5) / Double(columns),
                                      sample.minY + sample.height * (Double(y) + 0.5) / Double(rows)))
                }
            }
            return bits
        }
        let before = try picture()
        let hits = before.indices.filter { before[$0] }
        XCTAssertGreaterThan(hits.count, 40, "PREMISE: the cold-opened scaled label has real drawn letters")
        let minX = try XCTUnwrap(hits.map { $0 % columns }.min())
        let maxX = try XCTUnwrap(hits.map { $0 % columns }.max())
        let minY = try XCTUnwrap(hits.map { $0 / columns }.min())
        let maxY = try XCTUnwrap(hits.map { $0 / columns }.max())
        let hull = CGRect(x: host.minX + (sample.minX + sample.width * Double(minX) / Double(columns)) * host.width,
                          y: host.minY + (sample.minY + sample.height * Double(minY) / Double(rows)) * host.height,
                          width: sample.width * Double(maxX - minX + 1) / Double(columns) * host.width,
                          height: sample.height * Double(maxY - minY + 1) / Double(rows) * host.height)
        assertBelowTheToolbar(app, canvas, dy: (hull.minY - 10 - host.minY) / host.height,
                              "The measured scaled label and its selection margin")
        assertAboveTheDock(app, canvas, dy: (hull.maxY + 10 - host.minY) / host.height,
                           "The measured scaled label and its selection margin")
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertFalse(undo.isEnabled, "PREMISE: a cold-opened package has no prior document Undo")
        attachScreenshot(XCUIScreen.main, "text-autosize-01-cold-actual-move800")
        func editText() throws -> CGRect {
            app.buttons["toolbar.addButton"].tap()
            let addText = app.buttons["add.addTextRow"]
            XCTAssertTrue(addText.waitForExistence(timeout: 5), "Add offers the existing Text tool")
            addText.tap()
            XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5),
                          "The Text panel is up before reopening the measured glyph")
            tap(app, at: CGPoint(x: hull.minX + 10, y: hull.minY + 10))
            XCTAssertTrue(waitForTextState(app, "box", "editing"))
            let editingViewport = try viewport()
            XCTAssertEqual(canvas.frame, host, "Text follow leaves the measured host in place")
            XCTAssertEqual(editingViewport[0], originalViewport[0], "Text follow changes no scale")
            XCTAssertEqual(editingViewport[1], originalViewport[1], "Text follow changes no rotation")
            // The panel follows a tall box by panning the whole canvas. Transport the independent
            // pre-edit glyph by that measured pan, never by the box being tested or a warm-up edit.
            return hull.offsetBy(dx: editingViewport[2] - originalViewport[2],
                                 dy: editingViewport[3] - originalViewport[3])
        }
        _ = try editText()
        attachScreenshot(XCUIScreen.main, "text-autosize-02-unchanged-editor")
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"))
        waitForTheKeyboardToLeave(app)
        XCTAssertEqual(canvas.frame, host, "closing the editor restores the same measured host")
        // ViewportFollow.end gives its pan back when no artist navigation occurred. Compare the
        // exact mask only after that existing closed-session contract, not through resampled pans.
        XCTAssertEqual(readTransform(app), transform, "the ended, unnavigated text session gives its follow pan back")
        XCTAssertTrue(try picture() == before, "closing unchanged scaled point text preserves the exact sampled glyph picture and hull")
        XCTAssertFalse(undo.isEnabled, "opening and closing unchanged scaled point text adds no document Undo")
        attachScreenshot(XCUIScreen.main, "text-autosize-03-closed-unchanged")
        let editingHull = try editText()
        let inside = CGPoint(x: editingHull.midX, y: editingHull.midY)
        tap(app, at: inside)
        typeIntoTextBox("w", app, at: inside)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"))
        waitForTheKeyboardToLeave(app)
        XCTAssertEqual(readTransform(app), transform, "the real text edit returns to the measured viewport")
        XCTAssertTrue(try picture() != before, "new words still change the actual drawn label")
        XCTAssertTrue(undo.isEnabled, "the real edit creates a document Undo")
        attachScreenshot(XCUIScreen.main, "text-autosize-04-real-edit-drawn")
        undo.tap()
        XCTAssertTrue(try picture() == before, "one Undo restores the original cold-opened glyph picture")
        XCTAssertFalse(undo.isEnabled, "the real edit is exactly one step; unchanged editing left no hidden step")
        attachScreenshot(XCUIScreen.main, "text-autosize-05-real-edit-undone")
        returnFromOwnedTextFolderToRoot(app, folderName: folderName)
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 15))
        app.terminate()
        try stage.announce("restored-and-saved")
        let verified = try stage.awaitMessage("verified.ack")
        XCTAssertEqual(verified.data, Data("\(nonce)|verified|\(folderName)\n".utf8),
                       "the observer verified raw800, original auto-size frame/identity and removed only the owned fixture")
        try stage.announce("complete")
    }
    /// Only the authenticated stage's private folder is navigated; an abort must not leave its
    /// app-wide Gallery path behind. Teardown adds no assertions that could mask the first failure.
    private func returnFromOwnedTextFolderToRoot(_ app: XCUIApplication, folderName: String) {
        guard app.state == .runningForeground else { return }
        let gallery = app.buttons["gallery.newCanvasButton"]
        if !gallery.exists {
            let galleryButton = app.buttons["toolbar.galleryButton"]
            guard galleryButton.exists && galleryButton.isEnabled && galleryButton.isHittable else { return }
            galleryButton.tap()
        }
        guard gallery.waitForExistence(timeout: 15) else { return }
        let breadcrumb = app.staticTexts["gallery.breadcrumbPath"]
        let back = app.buttons["gallery.breadcrumbBack"]
        guard app.state == .runningForeground,
              breadcrumb.exists && breadcrumb.label == "Projects / \(folderName)",
              back.exists && back.isEnabled && back.isHittable else { return }
        back.tap()
        _ = breadcrumb.waitForNonExistence(timeout: 5)
    }

}
