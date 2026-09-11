import XCTest

/// **From a fresh document: draw, place a text object, undo it, redo it, delete it by emptying it,
/// undo that — and at every step what is *drawn* is asserted, not what is stored.** The cold-start
/// reachability test for TODO (41)'s second box, which bounded the undo and redo of a pristine
/// (`autoSize`) text object by a measurement of its glyph ink instead of the whole cel.
///
/// Every press below now goes through `VectorCanvas.restoreElements` with a rectangle read off the
/// text object itself, so the pixels this test looks at are exactly the pixels a wrong rectangle
/// would corrupt: a too-small one leaves a ghost of the old glyphs where the text used to be, and a
/// repair that skipped the strokes under it would take the stroke with it. Both are read off the
/// screen, in screen coordinates, the way the fill and eraser tests read theirs through `rgbaPixel`.
///
/// **Two routes to the same departure**, because the app has two. Undoing the *add* is the
/// commonest one (the owner's "undoing and redoing while there are a lot of strokes"); emptying the
/// box in a re-edit is how an artist deletes a label, and since this pass that commit is registered as
/// an add/remove swap rather than a rewrite — the id leaves the list, it is not rewritten under —
/// so its undo is bounded the same way.
final class TextUndoFootprintUITests: PaintUITestCase {

    func testUndoingAndRedoingATextObjectRedrawsItAndLeavesTheStrokesAlone() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // **Every pixel below is read in screen coordinates fixed here, before the keyboard has
        // ever been up.** The software keyboard compresses the editor's layout (the timeline moves up
        // over the lower canvas) and on this simulator the layout does not come back once the keyboard
        // has gone, so `canvas.host`'s frame — and with it every host-normalised coordinate — is not
        // the same thing after a text session as before it. The canvas *content* stays where it was
        // on screen, anchored at the host's top-left, which is what makes a screen coordinate the
        // stable one. The text also goes in the upper half of the canvas for the same reason.
        let host = canvas.frame
        func screenPoint(_ v: CGVector) -> CGPoint {
            CGPoint(x: host.minX + v.dx * host.width, y: host.minY + v.dy * host.height)
        }
        // **The undo and redo buttons are pressed wherever they are drawn, found by looking, and
        // pressed again if the press was swallowed.** They sit at the bottom of the side toolbar,
        // which the keyboard pushes up, and MEASURED over four runs of this test (recordings in the
        // xcresults of 2026-09-11; BUGS.md carries it): once the software keyboard has gone the
        // editor's layout **stays compressed** — a black band where the keyboard was, the timeline
        // and the rail's buttons a few hundred points above their places — **until the next touch on
        // a control, which restores the layout and is not delivered as a press.** So the first undo
        // after typing does nothing, whether it is tapped through its element (whose accessibility
        // frame reports the compressed geometry) or at its drawn position. The press below goes to
        // whichever of the two candidate points has the icon's light pixels on the rail's black, and
        // is repeated until the history's state says it took: undo enables redo, redo disables it.
        let undoAt = Self.centre(of: app.buttons["sideToolbar.undoButton"])
        let redoAt = Self.centre(of: app.buttons["sideToolbar.redoButton"])
        XCTAssertNotNil(undoAt, "PREMISE: the undo button is on screen")
        XCTAssertNotNil(redoAt, "PREMISE: the redo button is on screen")
        guard let undoAt, let redoAt else { return }
        let redoButton = app.buttons["sideToolbar.redoButton"]
        func pressUndo() {
            press(app, "sideToolbar.undoButton", drawnAt: undoAt, tookEffectWhen: { redoButton.isEnabled })
        }
        func pressRedo() {
            press(app, "sideToolbar.redoButton", drawnAt: redoAt, tookEffectWhen: { !redoButton.isEnabled })
        }

        // 1. Strokes first, in the top-left of the visible canvas, well away from where the text
        //    will go. What the artist does next: pick up the brush and draw — it is the default tool.
        let p = safeOutsideCornerPoint(canvas)
        let q = CGVector(dx: p.dx + 0.12, dy: p.dy)
        drawLine(on: canvas, from: p, to: q)
        let strokeProbe = screenPoint(CGVector(dx: p.dx + 0.06, dy: p.dy))
        XCTAssertTrue(waitUntilInk(around: strokeProbe, radius: 2),
                      "PREMISE: the stroke is on screen before any text is placed")

        // 2. Add Text, tap the canvas, type, and leave by picking the brush — which is what commits
        //    the session (`TopToolbar.selectBrushToolAndTogglePanel` runs `commitAllInteractiveState`).
        //    What the artist does next: Actions → Add Text, tap where the words go, type them.
        let boxOrigin = CGVector(dx: 0.62, dy: 0.32)
        placeText("Hello", app, on: canvas, at: boxOrigin)
        waitForTheLayoutToSettle(app, canvas, restoring: host)
        let textRegion = Self.regionUnderTheWords(from: screenPoint(boxOrigin), hostWidth: host.width)
        XCTAssertTrue(waitUntilInk(in: textRegion),
                      "PREMISE: committing the text puts glyph pixels on the canvas under the box")
        XCTAssertTrue(hasInk(around: strokeProbe, radius: 2), "PREMISE: placing text leaves the stroke alone")

        // 3. Undo removes the words and only the words. What the artist does next: press undo.
        pressUndo()
        XCTAssertTrue(waitUntilBlank(in: textRegion),
                      "Undoing the text left ink where the words were — the departure's rectangle "
                      + "did not cover its own glyphs")
        XCTAssertTrue(hasInk(around: strokeProbe, radius: 2),
                      "Undoing the text took the stroke with it — the repair redrew the wrong picture")

        // 4. Redo puts them back. What the artist does next: press redo.
        pressRedo()
        XCTAssertTrue(waitUntilInk(in: textRegion), "Redoing the text did not draw the words again")
        XCTAssertTrue(hasInk(around: strokeProbe, radius: 2), "Redoing the text took the stroke with it")

        // 5. Delete the label the way an artist does: reopen it and empty it. What the artist does
        //    next: Actions → Add Text, tap the words, delete them, pick the brush. The reopening tap
        //    is a screen coordinate too, since the host's frame may have moved under the keyboard.
        let wordsOnScreen = screenPoint(boxOrigin)
        reopenText(app, at: CGPoint(x: wordsOnScreen.x + host.width * 0.02, y: wordsOnScreen.y + host.width * 0.012))
        deleteCharacters(5, app, at: wordsOnScreen)
        leaveTextForTheBrush(app)
        waitForTheLayoutToSettle(app, canvas, restoring: host)
        XCTAssertTrue(waitUntilBlank(in: textRegion), "Emptying the box did not remove the words from the canvas")
        XCTAssertTrue(hasInk(around: strokeProbe, radius: 2), "Emptying the box took the stroke with it")

        // 6. Undo the deletion: the words are drawn again, the stroke is still there.
        pressUndo()
        XCTAssertTrue(waitUntilInk(in: textRegion),
                      "Undoing the deletion did not draw the words again — the arrival's rectangle "
                      + "did not cover its own glyphs")
        XCTAssertTrue(hasInk(around: strokeProbe, radius: 2), "Undoing the deletion took the stroke with it")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "text redrawn after undoing its deletion, stroke intact"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Driving the text tool

    /// Actions → Add Text, a tap on the canvas, the string typed, the brush picked to commit.
    ///
    /// The tap is right of centre for `CanvasTransformFreezeUITests.placeATextBox`'s measured reason:
    /// the text panel drops down over the *left* of the canvas, and a tap that lands on it places
    /// nothing and leaves a green test measuring an ordinary canvas.
    private func placeText(_ string: String, _ app: XCUIApplication, on canvas: XCUIElement,
                           at origin: CGVector) {
        openAddText(app)
        canvas.coordinate(withNormalizedOffset: origin).tap()
        XCTAssertTrue(waitForTextState(app, "editing"),
                      "PREMISE: the canvas tap has to put a live, focused text box on screen "
                      + "(text:\(readTextState(app)))")
        let frame = canvas.frame
        type(string, app, at: CGPoint(x: frame.minX + (origin.dx + 0.01) * frame.width,
                                      y: frame.minY + (origin.dy + 0.01) * frame.height))
        leaveTextForTheBrush(app)
    }

    /// A screen point as an `XCUICoordinate`, through the app's own frame.
    private static func coordinate(_ app: XCUIApplication, at point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    private static func centre(of element: XCUIElement) -> CGPoint? {
        guard element.waitForExistence(timeout: 5) else { return nil }
        let frame = element.frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Taps `identifier`'s control at whichever of two candidate points its icon is actually drawn —
    /// the point it occupied before any keyboard came up, or the point its accessibility frame
    /// reports now — and again, up to three times, until `tookEffectWhen` says the press landed. See
    /// the note in the test body for why neither point alone is reliable and why a press can be
    /// swallowed outright.
    private func press(_ app: XCUIApplication, _ identifier: String, drawnAt before: CGPoint,
                       tookEffectWhen tookEffect: () -> Bool) {
        for attempt in 1...3 {
            let now = Self.centre(of: app.buttons[identifier]) ?? before
            let candidates = [before, now]
            let lit = candidates.first { brightPixels(around: $0, radius: 8) > 0 }
            XCTAssertNotNil(lit, "\(identifier) is drawn at neither \(before) nor \(now) — nothing to press")
            Self.coordinate(app, at: lit ?? before).tap()
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if tookEffect() { return }
                Thread.sleep(forTimeInterval: 0.2)
            }
            let note = XCTAttachment(string: "\(identifier): press \(attempt) at \(lit ?? before) was swallowed")
            note.name = "swallowed press"
            note.lifetime = .keepAlways
            add(note)
        }
        XCTFail("\(identifier) did not take effect in three presses")
    }

    /// **`app.typeText` cannot reach the editor**, for the reason `CanvasTransformFreezeUITests`
    /// records: `canvas.host` is an accessibility element in its own right and hides its subtree,
    /// so XCUITest sees nothing with keyboard focus and refuses to synthesise the keystrokes. What it
    /// *can* reach is the software keyboard, which is a window of its own — so the string is typed
    /// key by key when the keyboard is up, and pasted through the edit menu (another window of its
    /// own) when a hardware keyboard is connected and no software keyboard appears.
    private func type(_ string: String, _ app: XCUIApplication, at insideTheBox: CGPoint) {
        if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            for character in string {
                // The keyboard shows whichever case its shift state has, and auto-capitalisation
                // shifts it for the first letter; either case draws the same glyph shapes for this
                // test's purpose, so take the key that is there.
                let exact = app.keys[String(character)]
                let other = app.keys[character.isUppercase ? String(character).lowercased()
                                                            : String(character).uppercased()]
                let key = exact.waitForExistence(timeout: 2) ? exact : other
                XCTAssertTrue(key.waitForExistence(timeout: 3), "the software keyboard has a \(character) key")
                key.tap()
            }
            return
        }
        UIPasteboard.general.string = string
        Self.coordinate(app, at: insideTheBox).press(forDuration: 1.0)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5),
                      "no software keyboard and no Paste menu — nothing this test can reach types into the box")
        paste.tap()
    }

    /// Deletes `count` characters the same two ways `type` types them.
    private func deleteCharacters(_ count: Int, _ app: XCUIApplication, at insideTheBox: CGPoint) {
        if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            let key = app.keys["delete"]
            XCTAssertTrue(key.waitForExistence(timeout: 3), "the software keyboard has a delete key")
            for _ in 0..<count { key.tap() }
            return
        }
        Self.coordinate(app, at: insideTheBox).press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "the edit menu offers Select All")
        selectAll.tap()
        let cut = app.menuItems["Cut"]
        XCTAssertTrue(cut.waitForExistence(timeout: 5), "the edit menu offers Cut on a selection")
        cut.tap()
    }

    /// Actions → Add Text, then a tap *on the words*, which reopens the object rather than placing
    /// a second one over it (`CanvasManager.beginTextSession`'s vector arm). The tap lands a little
    /// inside the box's top-left, where the first glyph is.
    private func reopenText(_ app: XCUIApplication, at screenPoint: CGPoint) {
        openAddText(app)
        Self.coordinate(app, at: screenPoint).tap()
        XCTAssertTrue(waitForTextState(app, "editing"),
                      "PREMISE: tapping the words reopens the text object for editing "
                      + "(text:\(readTextState(app)))")
    }

    private func openAddText(_ app: XCUIApplication) {
        app.buttons["toolbar.actionsButton"].tap()
        let addText = app.buttons["actions.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5), "PREMISE: Actions lists Add Text")
        XCTAssertTrue(addText.isEnabled, "PREMISE: Add Text is available on the default layer")
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5),
                      "PREMISE: Add Text opens the text settings panel")
    }

    /// Picking the brush is what ends a text session; the `text:` field going to "none" is what
    /// says the commit landed.
    private func leaveTextForTheBrush(_ app: XCUIApplication) {
        let brushButton = app.buttons["toolbar.brushButton"]
        XCTAssertTrue(brushButton.waitForExistence(timeout: 5))
        brushButton.tap()
        XCTAssertTrue(waitForTextState(app, "none"),
                      "PREMISE: leaving text mode for the brush commits the session "
                      + "(text:\(readTextState(app)))")
    }

    /// **A tap synthesised while the keyboard is still leaving lands where a control *was*.** The
    /// software keyboard compresses the editor's layout and its dismissal animates the layout back;
    /// XCUITest reads a button's frame and then taps a point, and the undo button at the bottom of
    /// the side toolbar moves a few hundred points during that animation — MEASURED: an undo tapped
    /// one second after leaving text mode did nothing at all, and the recording showed the layout
    /// still settling. So wait for the keyboard to be gone and the host's frame to be back where it
    /// started before pressing anything. Not an assertion: a layout that stays compressed is a
    /// different defect, reported rather than failed here, and the screen-coordinate probes still
    /// read the right pixels either way.
    private func waitForTheLayoutToSettle(_ app: XCUIApplication, _ canvas: XCUIElement, restoring host: CGRect) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let frame = canvas.frame
            let settled = app.keyboards.count == 0
                && abs(frame.minY - host.minY) < 1 && abs(frame.height - host.height) < 1
            if settled { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        let note = XCTAttachment(string: "canvas.host's accessibility frame did not return to \(host) within 10 s "
                                 + "of the keyboard leaving; it reads \(canvas.frame), keyboards: "
                                 + "\(app.keyboards.count); undo button reads "
                                 + "\(app.buttons["sideToolbar.undoButton"].frame)")
        note.name = "layout after the keyboard"
        note.lifetime = .keepAlways
        add(note)
    }

    /// The `text:` field of `canvas.host`'s label — "none" / "box" / "editing". See
    /// `CanvasView.publishCanvasState`.
    private func readTextState(_ app: XCUIApplication) -> String {
        let label = app.otherElements["canvas.host"].label
        guard let field = label.split(separator: " ").first(where: { $0.hasPrefix("text:") }) else {
            return "?(\(label))"
        }
        return String(field.dropFirst("text:".count))
    }

    private func waitForTextState(_ app: XCUIApplication, _ accepted: String...) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if accepted.contains(readTextState(app)) { return true }
        } while Date() < deadline
        return false
    }

    // MARK: - Reading what is drawn

    /// The patch of screen the words land in: the box's top-left is the tap, the words run right
    /// and down from it, and 64 pt of system type on a 2048-point canvas that fills the host's width
    /// is `64 / 2048` of that width tall. Inset a little from the corner so the region is inside the
    /// glyphs' own extent even if the box's edge lands a pixel off.
    private static func regionUnderTheWords(from origin: CGPoint, hostWidth: CGFloat) -> CGRect {
        let pointsPerCanvasPoint = hostWidth / 2048
        return CGRect(x: origin.x + 8 * pointsPerCanvasPoint, y: origin.y + 8 * pointsPerCanvasPoint,
                      width: 100 * pointsPerCanvasPoint, height: 56 * pointsPerCanvasPoint)
    }

    /// How many pixels in `region` — in screen points — are not paper-white.
    private func inkPixels(in region: CGRect) -> Int {
        let shot = XCUIScreen.main.screenshot().image
        guard let cgImage = shot.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        let scale = CGFloat(width) / shot.size.width
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x0 = max(0, Int(region.minX * scale)), x1 = min(width, Int(region.maxX * scale))
        let y0 = max(0, Int(region.minY * scale)), y1 = min(height, Int(region.maxY * scale))
        var count = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let o = y * bytesPerRow + x * 4
                if !(buffer[o] > 240 && buffer[o + 1] > 240 && buffer[o + 2] > 240) { count += 1 }
            }
        }
        return count
    }

    /// How many pixels within `radius` of `point` are light — a white glyph on the rail's black.
    private func brightPixels(around point: CGPoint, radius: CGFloat) -> Int {
        let shot = XCUIScreen.main.screenshot().image
        guard let cgImage = shot.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        let scale = CGFloat(width) / shot.size.width
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x0 = max(0, Int((point.x - radius) * scale)), x1 = min(width, Int((point.x + radius) * scale))
        let y0 = max(0, Int((point.y - radius) * scale)), y1 = min(height, Int((point.y + radius) * scale))
        var count = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let o = y * bytesPerRow + x * 4
                if buffer[o] > 150 && buffer[o + 1] > 150 && buffer[o + 2] > 150 { count += 1 }
            }
        }
        return count
    }

    private func hasInk(around point: CGPoint, radius: CGFloat) -> Bool {
        inkPixels(in: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)) > 0
    }

    /// Polls, because every one of these renders lands off the main thread a moment after the press.
    private func waitUntilInk(in region: CGRect, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if inkPixels(in: region) > 20 { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func waitUntilInk(around point: CGPoint, radius: CGFloat, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasInk(around: point, radius: radius) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func waitUntilBlank(in region: CGRect, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if inkPixels(in: region) == 0 { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }
}
