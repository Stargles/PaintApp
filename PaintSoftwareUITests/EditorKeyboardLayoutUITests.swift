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
}
