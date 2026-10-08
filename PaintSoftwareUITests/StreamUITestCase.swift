import XCTest

/// **The shared front of the stream UI tests**: a `FakeLaptopStreamer` standing in for the computer,
/// the stream committed on a fresh document through the Add menu the way an artist does it, and the
/// canvas read back off a screenshot. Every pixel a test reads went through the app's own framing,
/// H.264 decode, redraw tick and presentation; `streamBar.stateLabel`'s value says what the artist is
/// told, and a test that reads only the picture could pass against a bar that lies, and one that
/// reads only the bar against a picture that has stopped.
class StreamUITestCase: PaintUITestCase {

    var laptop: FakeLaptopStreamer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        laptop = try FakeLaptopStreamer()
    }

    override func tearDown() {
        laptop?.stop()
        laptop = nil
        super.tearDown()
    }

    // MARK: - Setup

    /// Gallery → New Canvas → Add → Stream Screen → Connect → the Move box's Done: the stream layer
    /// is on the canvas, active, and its bar is up. Returns the canvas.
    @discardableResult
    func launchWithALiveStream(_ app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor",
                      file: file, line: line)
        connectStream(app, file: file, line: line)
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), file: file, line: line)
        return canvas
    }

    /// The Add menu's Stream Screen row, the address and the port typed, Connect, and the Move box
    /// the insert lifts the stream into committed — the bar is what shows then.
    func connectStream(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["toolbar.addButton"].tap()
        let row = app.buttons["add.streamScreenRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Stream Screen is a row of the Add menu", file: file, line: line)
        row.tap()
        let port = app.textFields["streamConnect.portField"]
        XCTAssertTrue(port.waitForExistence(timeout: 10), "the row opens the connect sheet", file: file, line: line)
        setField(port, to: String(laptop.port))
        let address = app.textFields["streamConnect.addressField"]
        setField(address, to: "127.0.0.1")
        app.buttons["streamConnect.connectButton"].tap()

        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 20),
                      "a successful connect inserts the stream and lifts it into the Move box", file: file, line: line)
        done.tap()
        XCTAssertTrue(app.staticTexts["streamBar.stateLabel"].waitForExistence(timeout: 10),
                      "committing the box leaves the stream bar up", file: file, line: line)
    }

    /// The field is cleared one `delete` at a time — `StreamScreenUITests.setField`'s way.
    private func setField(_ field: XCUIElement, to value: String) {
        field.tap()
        let currentLength = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentLength) + value)
    }

    // MARK: - Reading

    enum Colour: String {
        case red, green, blue
        /// What a stream frame multiplied over black ink reads.
        case black

        func matches(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
            let (r, g, b) = (Int(p.r), Int(p.g), Int(p.b))
            switch self {
            case .red: return r > 170 && g < 110 && b < 110
            case .green: return g > 130 && r < 110 && b < 110
            case .blue: return b > 170 && r < 110 && g < 110
            case .black: return r < 70 && g < 70 && b < 70
            }
        }
    }

    func centre(_ canvas: XCUIElement) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)
    }

    /// Polls until the canvas's centre is `colour`, and says what it was instead when it never is.
    @discardableResult
    func waitForPicture(_ colour: Colour, on canvas: XCUIElement, timeout: TimeInterval = 10,
                        _ message: String = "",
                        file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var last = centre(canvas)
        while Date() < deadline {
            last = centre(canvas)
            if let last, colour.matches(last) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("The canvas never showed \(colour.rawValue); its centre reads \(String(describing: last)). \(message)",
                file: file, line: line)
        return false
    }

    /// Asserts the canvas's centre is **not** `colour` for the whole of `seconds` — the held-still
    /// counterpart of `waitForPicture`, for a frozen stream.
    func assertPictureStays(not colour: Colour, on canvas: XCUIElement, seconds: TimeInterval,
                            _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let pixel = centre(canvas), colour.matches(pixel) {
                XCTFail("The canvas showed \(colour.rawValue) when it should not have. \(message)", file: file, line: line)
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// The word the bar's state label carries as its accessibility value (`StreamBar.stateCode`).
    func barState(_ app: XCUIApplication) -> String {
        (app.staticTexts["streamBar.stateLabel"].value as? String) ?? "?"
    }

    func waitForBarState(_ app: XCUIApplication, _ state: String, timeout: TimeInterval = 10,
                         file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if barState(app) == state { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("The bar never reached \"\(state)\" (it says \"\(barState(app))\")", file: file, line: line)
    }

    /// Waits for a condition on the laptop's side — what the iPad has asked of it.
    func waitForTheLaptop(_ timeout: TimeInterval = 10, _ message: String, file: StaticString = #filePath,
                          line: UInt = #line, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Timed out: \(message)", file: file, line: line)
    }
}
