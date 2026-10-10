import XCTest

/// **Nothing in the editor moves for the keyboard** — the owner, 2026-10-10, on the iPad in landscape:
/// *"the keyboard comes up, and for some reason the entire screen gets shifted up. Since the title is on the
/// top of the screen, it disappears and I cannot see what I am writing."* SwiftUI squeezed the editor into
/// what the keyboard left, and an editor taller than that overflowed it centred, so the top of the screen
/// went off the top. `ContentView` now keeps the keyboard out of every layout; the keyboard is drawn over
/// the bottom of the screen and moves nothing.
///
/// **The one exception is the canvas, and only for the text tool:** a box being typed into is panned clear
/// of the keyboard — the canvas's own view pan, never the document's — and the canvas goes back when the box
/// is put down.
///
/// Each test reads the **drawn geometry** — the frames of controls and of the canvas host, the text box's
/// hull, the canvas's transform — rather than any model value, since the model was never wrong. All of it in
/// landscape, the orientation the report named. A hardware keyboard on the simulator raises none, which
/// skips these rather than passing them.
final class EditorKeyboardLayoutUITests: PaintUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// Every control the artist reads or reaches, by identifier — the frames the keyboard must not move.
    private static let landmarks = ["timeline.projectNameField", "toolbar.brushButton", "toolbar.layersButton",
                                    "sideToolbar.undoButton", "timeline.frameLabel", "canvas.host"]

    private func landmarkFrames(_ app: XCUIApplication) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: Self.landmarks.map { ($0, app.descendants(matching: .any)[$0].frame) })
    }

    private func launch() -> (app: XCUIApplication, canvas: XCUIElement) {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "PREMISE: the app is in landscape (\(window))")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        return (app, canvas)
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

    /// The software keyboard, up and still — or the test is skipped, because a hardware keyboard is
    /// connected to this simulator and none rises.
    private func softwareKeyboard(_ app: XCUIApplication) throws -> XCUIElement {
        let keyboard = app.keyboards.firstMatch
        try XCTSkipUnless(keyboard.waitForExistence(timeout: 5),
                          "a hardware keyboard is connected to this simulator, so no software keyboard rises")
        let deadline = Date().addingTimeInterval(5)
        while keyboard.frame.height < 200, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        waitForTheKeyboardToStopMoving(keyboard)
        XCTAssertGreaterThan(keyboard.frame.height, 200, "PREMISE: a real software keyboard is up (\(keyboard.frame))")
        return keyboard
    }

    // MARK: - Nothing moves for the keyboard

    /// **The owner's report, cold from a fresh document:** the scene's name tapped, the keyboard up and
    /// still, then the name typed and committed. The name's field, the toolbars, the timeline and the canvas
    /// stand exactly where they stood, and the name is on screen above the keyboard where it can be read.
    /// What the artist does next: types the name where they can see it.
    func testRenamingTheSceneMovesNothingOnScreen() throws {
        let (app, _) = launch()
        let before = landmarkFrames(app)
        let field = app.textFields["timeline.projectNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        field.tap()
        let keyboard = try softwareKeyboard(app)
        attachScreenshot(app, "renaming-the-scene-in-landscape")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(field.frame) && field.isHittable,
                      "the name being typed into is on screen (\(field.frame) in \(window))")
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY, "…and above the keyboard")
        XCTAssertEqual(landmarkFrames(app), before, "nothing on screen moved for the keyboard")

        field.typeText("Moonrise\n")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "Return put the keyboard away")
        XCTAssertEqual(field.value as? String, "Moonrise")
        XCTAssertEqual(landmarkFrames(app), before, "…and nothing moved back, because nothing had moved")
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
        _ = try softwareKeyboard(app)
        let frame = canvas.frame
        typeIntoTextBox("Hi", app, at: CGPoint(x: frame.minX + 0.56 * frame.width, y: frame.minY + 0.21 * frame.height))
    }

    /// Typing into the text tool's box moves no control either, and leaving by picking the brush or the
    /// select tool — the two ways text is commonly put down, which reach the end of the session through
    /// different buttons — leaves them where they were.
    private func assertTextMovesNothing(leavingBy button: String) throws {
        let (app, canvas) = launch()
        let before = landmarkFrames(app)

        try typeSomeText(app, canvas)
        XCTAssertEqual(landmarkFrames(app), before, "nothing moved while the text was typed")

        app.buttons[button].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: \(button) puts the box down")
        waitForTheKeyboardToLeave(app)
        attachScreenshot(app, "text-put-down-with-\(button)")
        XCTAssertEqual(landmarkFrames(app), before, "…and nothing moved when it was put down")
    }

    func testTypingTextMovesNothingAndPuttingItDownWithTheBrushLeavesTheEditorAsItWas() throws {
        try assertTextMovesNothing(leavingBy: "toolbar.brushButton")
    }

    func testTypingTextMovesNothingAndPuttingItDownWithTheSelectToolLeavesTheEditorAsItWas() throws {
        try assertTextMovesNothing(leavingBy: "toolbar.selectButton")
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

    /// Polls until the box on the glass stands above `limit` or the time is up — the follow animates over
    /// the keyboard's own slide, so the answer arrives, it is not instant.
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

    /// The timeline taken down to its bar, so that the keyboard, and not the timeline and the panel riding
    /// on it, is what covers the most of the paper.
    private func collapseTheTimeline(_ app: XCUIApplication) {
        let collapse = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5), "PREMISE: the timeline has a collapse chevron")
        collapse.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Add → Add Text, a tap on the paper a hand's width above the Text panel's top edge — the lowest the
    /// tap can land and still be on the paper, and **below where the keyboard's top is about to be** (the
    /// timeline is collapsed first) — and the keyboard up and still. Answers the panel's docked card and
    /// the keyboard, whose frames are the lines the box has to stand above.
    private func placeABoxBelowTheKeyboardsTop(_ app: XCUIApplication, _ canvas: XCUIElement) throws
        -> (card: XCUIElement, keyboard: XCUIElement) {
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
        let keyboard = try softwareKeyboard(app)
        XCTAssertLessThan(keyboard.frame.minY, card.frame.minY - 40,
                          "PREMISE: the keyboard (top \(keyboard.frame.minY)) reaches higher than the place the box "
                          + "was put (\(card.frame.minY - 40)), so only the keyboard can take it out of view")
        return (card, keyboard)
    }

    /// **A box placed below where the keyboard will reach is panned up above it, typed into there, and the
    /// canvas goes back when the box is put down** — the owner: *"for writing text, the keyboard may block
    /// you from seeing what you are writing too, so … a shift up feature."* Cold from a fresh document, the
    /// artist's own sequence: Add Text, a tap low on the paper, and the keyboard rises over the lower part of
    /// the screen without moving anything in it; the box would be under it, so the canvas pans — the editor
    /// does not — and the box stands in view; two letters; then the brush to put it down.
    ///
    /// What is read is what is drawn: the box's hull on the glass (`textbox:`) held against the keyboard's
    /// frame, the canvas's transform (`xform:`) before, during and after, and the editor's landmarks, which
    /// stay put throughout. What the artist does next: nothing — the words are where they can be read.
    func testTheCanvasPansToKeepTheBoxAboveTheKeyboardAndBackAfter() throws {
        let (app, canvas) = launch()
        collapseTheTimeline(app)
        let landmarksBefore = landmarkFrames(app)
        let transformBefore = readTransform(app)
        let panBefore = verticalPan(app)

        let (_, keyboard) = try placeABoxBelowTheKeyboardsTop(app, canvas)

        let lifted = try XCTUnwrap(waitForTheBox(app, in: canvas, toStandAbove: { keyboard.frame.minY }),
                                   "the session has a box on the glass")
        attachScreenshot(app, "box-placed-low-with-the-keyboard-up")
        XCTAssertLessThanOrEqual(lifted.maxY, keyboard.frame.minY,
                                 "the box (bottom \(lifted.maxY)) stands above the keyboard (top \(keyboard.frame.minY)) "
                                 + "— the canvas panned to keep it in view; xform \(readTransform(app))")
        XCTAssertLessThan(verticalPan(app), panBefore, "…and it did so by panning the canvas up, as the artist does")
        XCTAssertEqual(landmarkFrames(app), landmarksBefore, "…while nothing in the editor moved, the host included")

        typeIntoTextBox("Hi", app, at: CGPoint(x: lifted.minX + 4, y: lifted.midY))
        let typed = try XCTUnwrap(textBox(app, in: canvas))
        XCTAssertLessThanOrEqual(typed.maxY, keyboard.frame.minY, "still above the keyboard once the words are typed")
        attachScreenshot(app, "words-typed-above-the-keyboard")

        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the box down")
        waitForTheKeyboardToLeave(app)
        let deadline = Date().addingTimeInterval(6)
        while readTransform(app) != transformBefore, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        attachScreenshot(app, "box-put-down-canvas-back")
        XCTAssertEqual(readTransform(app), transformBefore, "the canvas went back to where it was before the box")
    }

    /// **A view change the artist makes while typing is theirs**: the canvas is not pulled back to where it was
    /// when the box is put down, and the follow does not fight the artist's own pinch while the keyboard is up.
    func testAPinchMadeWhileTypingIsLeftAlone() throws {
        let (app, canvas) = launch()
        collapseTheTimeline(app)
        let transformBefore = readTransform(app)

        let (_, keyboard) = try placeABoxBelowTheKeyboardsTop(app, canvas)
        XCTAssertNotNil(waitForTheBox(app, in: canvas, toStandAbove: { keyboard.frame.minY }))
        let followed = readTransform(app)
        XCTAssertNotEqual(followed, transformBefore, "PREMISE: the canvas followed the box")

        canvas.pinch(withScale: 1.4, velocity: 1.5)
        let pinched = readTransform(app)
        XCTAssertNotEqual(pinched, followed, "PREMISE: the artist's two fingers moved the canvas")

        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the box down")
        waitForTheKeyboardToLeave(app)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(readTransform(app), pinched,
                       "the canvas stays where the artist left it, not where it began (\(transformBefore))")
    }

}
