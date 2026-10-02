import XCTest

/// **The editor's layout comes back when the keyboard a text box raised goes away.** The symptom,
/// found driving Select → Edit Text: after the keyboard left, the canvas host stayed at the height the
/// keyboard had pushed it to (973 pt against 1356) and the timeline and side rail stayed a few hundred
/// points above their places, until a touch landed on a control — which was then not delivered as a
/// press. BUGS.md carried it for three weeks and two UI tests carried workarounds for it.
///
/// **The cause was where the keyboard was dismissed, not the keyboard**: ending a text session hid the
/// overlay from `CanvasView.updateUIView`, which made UIKit resign the text view *inside SwiftUI's
/// update pass* — and the hosting view's keyboard avoidance is not told to relay out from there.
/// `CanvasManager.commitInteractiveText` now drops the keyboard first, from the action that ends the
/// session. Typing is what exposed it (a keyboard dismissed before the first key did not): the keys are
/// typed here, and every leaving route is driven from a fresh document the way the artist drives it.
///
/// Each test reads the **drawn geometry** — `canvas.host`'s frame and the undo button's — rather than any
/// model value, since the model was never wrong. A hardware keyboard on the simulator raises none, which
/// skips these rather than passing them.
final class EditorKeyboardLayoutUITests: PaintUITestCase {

    private struct Geometry: Equatable {
        var host: CGRect
        var undo: CGRect
    }

    private func geometry(_ app: XCUIApplication) -> Geometry {
        Geometry(host: app.otherElements["canvas.host"].frame,
                 undo: app.buttons["sideToolbar.undoButton"].frame)
    }

    /// Whether the editor is where `then` had it, to within a point — polled, because a layout answers
    /// the keyboard's going away over an animation rather than at an instant.
    private func waitForGeometry(_ app: XCUIApplication, toBe then: Geometry, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let now = geometry(app)
            if abs(now.host.height - then.host.height) < 1, abs(now.host.minY - then.host.minY) < 1,
               abs(now.undo.minY - then.undo.minY) < 1 { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    /// Add → Add Text, a tap on the canvas, the keyboard up and still, and two letters typed. What the
    /// artist does next: put the text down, by picking a tool.
    private func typeSomeText(_ app: XCUIApplication, _ canvas: XCUIElement) throws {
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5), "PREMISE: the Add menu lists Add Text")
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "PREMISE: the text panel is up")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.20)).tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: a live text box (text:\(readTextState(app)))")
        let keyboard = app.keyboards.firstMatch
        try XCTSkipUnless(keyboard.waitForExistence(timeout: 5),
                          "a hardware keyboard is connected to this simulator, so no software keyboard rises")
        waitForTheKeyboardToStopMoving(keyboard)
        let frame = canvas.frame
        typeIntoTextBox("Hi", app, at: CGPoint(x: frame.minX + 0.56 * frame.width, y: frame.minY + 0.21 * frame.height))
    }

    /// A key tapped while the keyboard is still sliding up is tapped where it was: XCUITest reports its
    /// frame a few hundred points below the screen and refuses with "failed to scroll to visible".
    private func waitForTheKeyboardToStopMoving(_ keyboard: XCUIElement) {
        var last = keyboard.frame
        var steadyFor = 0
        let deadline = Date().addingTimeInterval(5)
        while steadyFor < 3, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            let now = keyboard.frame
            steadyFor = now == last ? steadyFor + 1 : 0
            last = now
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Leaving by picking the brush — the commonest way to put text down, and the one that left the
    /// editor compressed.
    func testTheLayoutComesBackWhenTheTextIsPutDownWithTheBrush() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let before = geometry(app)

        try typeSomeText(app, canvas)
        let during = geometry(app)
        XCTAssertLessThan(during.host.height, before.host.height - 100,
                          "PREMISE: the keyboard really did push the editor up while it was there")

        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the box down")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the keyboard is gone")
        let settled = waitForGeometry(app, toBe: before)
        attach(app, "text-put-down-with-the-brush")
        XCTAssertTrue(settled, "the editor did not come back after the text was put down: host \(before.host) -> \(during.host) -> \(geometry(app).host)")
    }

    /// Leaving by picking another tool — the same route through a different button, so a fix that
    /// lived in one toolbar action rather than in the session's end would pass the test above and not
    /// this one.
    func testTheLayoutComesBackWhenTheTextIsPutDownWithTheSelectTool() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let before = geometry(app)

        try typeSomeText(app, canvas)

        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: picking Select puts the box down")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the keyboard is gone")
        let settled = waitForGeometry(app, toBe: before)
        attach(app, "text-put-down-with-the-select-tool")
        XCTAssertTrue(settled, "the editor did not come back after the text was put down: host \(before.host) -> \(geometry(app).host)")
    }

    // MARK: - The canvas follows the box being typed in

    /// The text box on the glass, in screen points, from `canvas.host`'s `textbox:` field (the box's hull
    /// in the host's unit square) — nil when no session is up.
    private func textBox(_ app: XCUIApplication, in canvas: XCUIElement) -> CGRect? {
        let parts = readField(app, "textbox:").split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        let host = canvas.frame
        return CGRect(x: host.minX + parts[0] * host.width, y: host.minY + parts[1] * host.height,
                      width: parts[2] * host.width, height: parts[3] * host.height)
    }

    /// The canvas's vertical pan, the `dy` of `xform:` ("scale,rotation,dx,dy").
    private func verticalPan(_ app: XCUIApplication) -> Double {
        Double(readTransform(app).split(separator: ",").last ?? "") ?? .nan
    }

    /// Polls until the box on the glass stands above `limit` or the time is up — the follow animates, and
    /// the keyboard compresses the layout over its own animation, so the answer arrives, it is not
    /// instant.
    private func waitForTheBox(_ app: XCUIApplication, in canvas: XCUIElement, toStandAbove limit: () -> CGFloat,
                               timeout: TimeInterval = 8) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: CGRect?
        repeat {
            last = textBox(app, in: canvas)
            if let box = last, box.maxY <= limit() { return box }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return last
    }

    /// Add → Add Text, a tap low on the paper — a hand's width above the Text panel's top edge, the lowest
    /// the tap can land and still be on the paper — the keyboard up and still. Answers the Text panel's
    /// docked card, whose frame is the line the box has to stand above.
    private func placeABoxLow(_ app: XCUIApplication, _ canvas: XCUIElement) throws -> XCUIElement {
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5), "PREMISE: the Add menu lists Add Text")
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "PREMISE: the text panel is up")
        let card = app.otherElements["bottomDock.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "PREMISE: the Text panel is docked")
        let lowest = (card.frame.minY - 40 - canvas.frame.minY) / canvas.frame.height
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: lowest)).tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: a live text box (text:\(readTextState(app)))")
        let keyboard = app.keyboards.firstMatch
        try XCTSkipUnless(keyboard.waitForExistence(timeout: 5),
                          "a hardware keyboard is connected to this simulator, so no software keyboard rises")
        waitForTheKeyboardToStopMoving(keyboard)
        return card
    }

    /// **A box placed low is scrolled into view above the Text panel, typed into there, and the canvas
    /// goes back when the box is put down** — the owner: *"the canvas scrolls to keep the text box being
    /// typed visible above the Text panel and keyboard, and back after."* Cold from a fresh document, the
    /// artist's own sequence: Add Text, a tap low on the paper — just above the Text panel's top — and the
    /// keyboard rises and compresses the layout, which takes the box under the panel; then two letters, then
    /// the brush to put it down.
    ///
    /// What is read is what is drawn: the box's hull on the glass (`textbox:`) held against the panel's own
    /// frame (`bottomDock.card`), and the canvas's transform (`xform:`) before, during and after. What the
    /// artist does next: nothing — the words are where they can be read.
    func testTheCanvasScrollsToKeepTheBoxAboveThePanelAndBackAfter() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let before = geometry(app)
        let panBefore = verticalPan(app)
        let transformBefore = readTransform(app)

        let panel = try placeABoxLow(app, canvas)

        let lifted = try XCTUnwrap(waitForTheBox(app, in: canvas, toStandAbove: { panel.frame.minY }),
                                   "the session has a box on the glass")
        attach(app, "box-placed-low-with-the-keyboard-up")
        XCTAssertLessThanOrEqual(lifted.maxY, panel.frame.minY,
                                 "the box (bottom \(lifted.maxY)) stands above the Text panel (top \(panel.frame.minY)) "
                                 + "— the canvas scrolled to keep it in view; xform \(readTransform(app))")
        XCTAssertLessThan(verticalPan(app), panBefore, "…and it did so by panning the canvas up, as the artist does")

        typeIntoTextBox("Hi", app, at: CGPoint(x: lifted.minX + 4, y: lifted.midY))
        let typed = try XCTUnwrap(textBox(app, in: canvas))
        XCTAssertLessThanOrEqual(typed.maxY, panel.frame.minY, "still above the panel once the words are typed")
        attach(app, "words-typed-above-the-panel")

        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the box down")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the keyboard is gone")
        XCTAssertTrue(waitForGeometry(app, toBe: before), "PREMISE: the editor is back at full height")
        let deadline = Date().addingTimeInterval(6)
        while readTransform(app) != transformBefore, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        attach(app, "box-put-down-canvas-back")
        XCTAssertEqual(readTransform(app), transformBefore, "the canvas went back to where it was before the box")
    }

    /// **A pan the artist makes while typing is theirs**: the canvas is not pulled back to where it was when
    /// the box is put down, and the follow does not fight the pan while the keyboard is up.
    func testAPanMadeWhileTypingIsLeftAlone() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let transformBefore = readTransform(app)

        let panel = try placeABoxLow(app, canvas)
        XCTAssertNotNil(waitForTheBox(app, in: canvas, toStandAbove: { panel.frame.minY }))
        let followed = readTransform(app)
        XCTAssertNotEqual(followed, transformBefore, "PREMISE: the canvas followed the box")

        // The artist pans by hand, where no panel and no keyboard reaches: two fingers, 60 points right.
        let frame = canvas.frame
        let at = CGPoint(x: frame.minX + frame.width * 0.2, y: frame.minY + frame.height * 0.12)
        try twoFingerGesture(from: (CGPoint(x: at.x - 30, y: at.y), CGPoint(x: at.x + 30, y: at.y)),
                             to: (CGPoint(x: at.x + 30, y: at.y), CGPoint(x: at.x + 90, y: at.y)), stagger: 0)
        let panned = readTransform(app)
        XCTAssertNotEqual(panned, followed, "PREMISE: the artist's two fingers moved the canvas")

        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the box down")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the keyboard is gone")
        Thread.sleep(forTimeInterval: 1.0)
        // The offset, not the whole transform: its first field is the fit scale, which is the host's own
        // height divided by the paper's and moves when the keyboard leaves, pan or no pan.
        func offset(_ transform: String) -> [Substring] { Array(transform.split(separator: ",").suffix(2)) }
        XCTAssertEqual(offset(readTransform(app)), offset(panned),
                       "the canvas stays where the artist left it, not where it began (\(transformBefore))")
    }

}
