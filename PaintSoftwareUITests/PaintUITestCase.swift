import XCTest

/// Shared setup and helpers for the XCUITest suites. Split out of the original
/// single PaintSoftwareUITests class so the ~60 UI tests live in several classes:
/// XCTest parallelises by class, so one class meant one worker and no speedup.
///
/// Helpers are internal rather than private only because subclasses now live in
/// other files; they are otherwise unchanged.
class PaintUITestCase: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Whether this test has launched the app through `launchIntoEditor` yet — XCTest makes a fresh
    /// instance per test method, so this is per test. See `launchIntoEditor` for what it gates.
    private var hasLaunchedIntoEditor = false

    /// "off" / "rest" / "live" / "stroke" — which rendering path the live canvas is on, published on
    /// `canvas.host`'s label from `SandwichPresentation`.
    ///
    /// The label carries a second, space-separated field (`entries:`) that `midStrokeEntries` reads;
    /// only the first token is the state.
    ///
    /// **Here rather than in one suite** since RENDER.md stage 4d: "rest" now means *the bake for
    /// this frame has landed*, so it is the answer two suites ask for rather than one.
    func sandwichState(_ app: XCUIApplication) -> String {
        let label = app.otherElements["canvas.host"].label
        guard let first = label.split(separator: " ").first, first.hasPrefix("sandwich:") else {
            return "?(\(label))"
        }
        return String(first.dropFirst("sandwich:".count))
    }

    /// Waits until the canvas reports `state`, and asserts it got there.
    ///
    /// **Every assertion that the canvas is at "rest" is a wait since RENDER.md stage 4d**, and the
    /// reason is the same one `waitForPixel` already gives for pixels: the picture at rest is now the
    /// **baked** frame, produced by `FrameBaker` on a `.utility` queue and read back off disk, so
    /// lift no longer snaps the canvas back inside the same turn. §2.13 rules that acceptable in the
    /// owner's own words — *"a canvas that shows the previous composite for a split second after
    /// pen-up is acceptable, provided the main thread never freezes"* — and MEASURED on the iOS 26.5
    /// simulator at the app's default 2048² canvas it is **0.40 s after a stroke and 0.024 s after a
    /// frame step**. An instant `XCTAssertEqual` against "rest" is therefore a race that reads as a
    /// broken renderer; it fails with "stroke", which is exactly what a bake that never arrived also
    /// looks like.
    ///
    /// **"off" is not waited for and must not be**: disengaging is synchronous (it is a branch in
    /// `updateSandwich`, not a composite), so a wait there would hide a canvas that took a moment to
    /// give up the compositor.
    @discardableResult
    func waitForSandwichState(_ app: XCUIApplication, _ state: String,
                              timeout: TimeInterval = 20,
                              _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if sandwichState(app) == state { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("The canvas never reached \"\(state)\" (it is \"\(sandwichState(app))\"). \(message)",
                file: file, line: line)
        return false
    }

    /// Sets the active layer's blend mode through the options panel, leaving the panel closed.
    ///
    /// Shared for `sandwichState`'s reason: a blending leaf is the cheapest document Core Animation
    /// cannot draw, so it is how any suite gets the compositor — and now the bake — onto the canvas.
    func setBlendMode(_ app: XCUIApplication, layerIndex: Int, to mode: String) {
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.\(layerIndex)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap() // select
        row.tap() // open options
        app.buttons["layerOptions.blendModeButton"].tap()
        let item = app.buttons["layerOptions.blendMode.\(mode)"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        app.buttons["layerOptions.close"].tap()
        app.buttons["toolbar.layersButton"].tap()
    }

    // MARK: - The timeline's baked-frame bar

    /// `timeline.bakeBar` — its accessibility value is `TimelineBakeBar.encode`'s string, and `""` is a
    /// scene whose every frame is baked.
    func bakeBar(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["timeline.bakeBar"]
    }

    func bakeBarValue(_ app: XCUIApplication) -> String {
        bakeBar(app).value as? String ?? "?"
    }

    /// Polls until the bar's value satisfies `predicate`, and returns the value that satisfied it.
    ///
    /// A deadline rather than an instant read, for `waitForSandwichState`'s reason: the bar clears
    /// on `FrameBaker`'s frame-finished callback, which arrives when a `.utility` worker has written
    /// a file, and it is throttled to ten updates a second on top of that
    /// (`TimelineBakeBar.refreshInterval`). No sleep in the loop — the window this is hunting is a
    /// few hundred milliseconds and an XCUITest query already costs tens of them.
    @discardableResult
    func waitForBakeBar(_ app: XCUIApplication, timeout: TimeInterval = 30,
                        where predicate: (String) -> Bool) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let value = bakeBarValue(app)
            if predicate(value) { return value }
        }
        return nil
    }

    /// Gallery -> New Canvas -> Create Canvas (default 2048x2048), landing in the editor.
    /// Also serves as the regression test for the launch-time freeze: if that bug ever
    /// comes back, `waitForExistence` below times out and the test fails.
    @discardableResult
    func launchIntoEditor(_ app: XCUIApplication) -> Bool {
        // The artist's tools outlive a launch since TODO (77); a test that opens a new document
        // and reads the default brush wants the defaults, not the last test's slider position.
        if !app.launchArguments.contains("-resetEditorPreferences") {
            app.launchArguments.append("-resetEditorPreferences")
        }
        // **And so does the brush library, which is a file the brush editor writes** — `setBrushSize`
        // does, from fourteen suites — and whose edited default the next launch adopts
        // (`CanvasManager.adoptLibrarySelections`). Without this, every later test on the simulator
        // draws with the last editor test's brush: MEASURED 2026-09-25, `ColorWheelsUITests`' 0.9
        // size turned three unrelated tests red that each pass alone. Only a test's *first* launch:
        // relaunching inside one test is how `BrushEditorUITests` proves an edit outlives the process.
        if !hasLaunchedIntoEditor && !app.launchArguments.contains("-resetBrushLibrary") {
            app.launchArguments.append("-resetBrushLibrary")
        }
        hasLaunchedIntoEditor = true
        app.launch()

        let newCanvas = app.buttons["gallery.newCanvasButton"]
        guard newCanvas.waitForExistence(timeout: 10) else { return false }
        newCanvas.tap()

        let createButton = app.buttons["sizePicker.createButton"]
        guard createButton.waitForExistence(timeout: 10) else { return false }
        createButton.tap()

        let frameLabel = app.staticTexts["timeline.frameLabel"]
        return frameLabel.waitForExistence(timeout: 10)
    }

    /// One space-separated field of `canvas.host`'s accessibility label, with its `prefix` removed, or
    /// `?(label)` when it is not there. XCUITest can read neither a recognizer's state nor a view's
    /// transform, so `CanvasView.Coordinator.publishCanvasState` writes what a test needs to ask —
    /// `xform:`, `text:`, `shape:`, `sandwich:` — onto that one label.
    func readField(_ app: XCUIApplication, _ prefix: String) -> String {
        let label = app.otherElements["canvas.host"].label
        guard let field = label.split(separator: " ").first(where: { $0.hasPrefix(prefix) }) else {
            return "?(\(label))"
        }
        return String(field.dropFirst(prefix.count))
    }

    // MARK: - The text tool

    /// The `text:` field of `canvas.host`'s label — "none" / "box" / "editing". See
    /// `CanvasView.publishCanvasState`.
    func readTextState(_ app: XCUIApplication) -> String {
        readField(app, "text:")
    }

    /// Polls `text:` rather than reading it once: placing a box is a SwiftUI state change and the
    /// label is republished on the pass that follows it, so a single read straight after the tap can
    /// legitimately still say "none".
    func waitForTextState(_ app: XCUIApplication, _ accepted: String...) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if accepted.contains(readTextState(app)) { return true }
        } while Date() < deadline
        return false
    }

    /// **`app.typeText` cannot reach the editor**, for the reason `CanvasTransformFreezeUITests`
    /// records: `canvas.host` is an accessibility element in its own right and hides its subtree,
    /// so XCUITest sees nothing with keyboard focus and refuses to synthesise the keystrokes. What it
    /// *can* reach is the software keyboard, which is a window of its own — so the string is typed
    /// key by key when the keyboard is up, and pasted through the edit menu (another window of its
    /// own) when a hardware keyboard is connected and no software keyboard appears.
    func typeIntoTextBox(_ string: String, _ app: XCUIApplication, at insideTheBox: CGPoint) {
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
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: insideTheBox.x, dy: insideTheBox.y))
            .press(forDuration: 1.0)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5),
                      "no software keyboard and no Paste menu — nothing this test can reach types into the box")
        paste.tap()
    }


    /// The `xform:` field — "scale,rotation,dx,dy" — which moves exactly when the canvas does.
    func readTransform(_ app: XCUIApplication) -> String {
        readField(app, "xform:")
    }

    /// Parses the "Frame N/M" label into (current, total), both 1-based as displayed.
    func readFrameLabel(_ app: XCUIApplication) -> (current: Int, total: Int)? {
        let label = app.staticTexts["timeline.frameLabel"]
        guard label.waitForExistence(timeout: 5) else { return nil }
        let text = label.label
        let parts = text.replacingOccurrences(of: "Frame ", with: "").split(separator: "/")
        guard parts.count == 2, let current = Int(parts[0]), let total = Int(parts[1]) else { return nil }
        return (current, total)
    }

    /// Parses a cel block's accessibilityValue, formatted as "startFrame,frameCount" with an
    /// optional trailing ",ref" while the block is an interpolation reference.
    ///
    /// The suffix is tolerated rather than required: every timeline test predates it and reads a
    /// two-part value, and interpolate mode is the only thing that ever adds a third.
    func readCel(_ app: XCUIApplication, layerIndex: Int, celIndex: Int) -> (start: Int, length: Int)? {
        let cel = app.otherElements["timeline.cel.\(layerIndex).\(celIndex)"]
        guard cel.waitForExistence(timeout: 5), let value = cel.value as? String else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count >= 2, let start = Int(parts[0]), let length = Int(parts[1]) else { return nil }
        return (start, length)
    }

    /// Whether a cel block is currently flagged as an interpolation reference — the yellow
    /// highlight, which is not otherwise reachable from XCUITest.
    func readCelIsReference(_ app: XCUIApplication, layerIndex: Int, celIndex: Int) -> Bool {
        let cel = app.otherElements["timeline.cel.\(layerIndex).\(celIndex)"]
        guard cel.waitForExistence(timeout: 5), let value = cel.value as? String else { return false }
        return value.hasSuffix(",ref")
    }

    /// Reads a layer panel row's accessibilityValue, which is the stroke count of that
    /// layer's cel at the current frame (see LayerRow.strokeCount).
    func readLayerStrokeCount(_ app: XCUIApplication, layerIndex: Int) -> Int? {
        let row = app.staticTexts["layerPanel.row.\(layerIndex)"]
        guard row.waitForExistence(timeout: 5), let value = row.value as? String else { return nil }
        return Int(value)
    }

    /// Whether a layer's active cel still has a separate `Cel.bakedImage` tier (see
    /// `LayerRow.hasBakedImage`) — expected `false` for every settled (non-transient) cel: Fill,
    /// Clear, Move, Duplicate, Rasterize, and Merge all land their result in `Cel.raster` directly
    /// (the tier the eraser stamps into), never leaving content in `bakedImage` — see
    /// `CanvasManager.registerUndoableCelChange`'s doc comment. This marker exists as a regression
    /// guard for exactly that "ghost layer" bug, not as the tool's normal success signal (use
    /// `readLayerStrokeCount` for that).
    func readHasBakedImage(_ app: XCUIApplication, layerIndex: Int) -> Bool? {
        let marker = app.otherElements["layerPanel.row.\(layerIndex).hasBaked"]
        guard marker.waitForExistence(timeout: 5), let value = marker.value as? String else { return nil }
        return value == "1"
    }

    /// **Whether a timeline block is drawing a picture, and a wait rather than a read.**
    ///
    /// `CelBlockView.setThumbnail` writes "1" or "0" into the block's tile element, which is the only
    /// way to ask this from XCUITest: the view is hidden when the tile is nil and a hidden view still
    /// resolves, so `exists` reports the same thing either way (MEASURED — an assertion built on it
    /// passed with the whole install deleted).
    ///
    /// A wait because a tile is 400 ms behind the edit that dirtied it by construction
    /// (`CanvasManager`'s debounce) and is then rendered off the main thread.
    func tileState(_ app: XCUIApplication, layerIndex: Int, celIndex: Int) -> String? {
        app.images["timeline.cel.\(layerIndex).\(celIndex).tile"].value as? String
    }

    func waitForTile(_ app: XCUIApplication, layerIndex: Int, celIndex: Int,
                     timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if tileState(app, layerIndex: layerIndex, celIndex: celIndex) == "1" { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Drags a straight line on the canvas between two normalized offsets of `canvas.host` — used to
    /// draw a rectangle selection (Select tool, Rectangle mode) or to draw a stroke.
    func dragOnCanvas(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: from)
        let end = canvas.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// **The artist's whole gesture for an Add-menu object** (TODO (149)): tap Add, tap `row` — which
    /// primes the object and closes the menu — then press on the canvas at `from` and drag to `to`, the
    /// pen that places it and sizes it. `primedName` is what the Add icon announces while it is primed
    /// (`PrimedObject.name`); both ends of the gesture assert it, so a fixture that reached the canvas
    /// without priming, or left the object primed after placing it, fails here and not three assertions
    /// later. Offsets are normalised in `canvas.host`, as `dragOnCanvas`'s are.
    func placeFromTheAddMenu(_ app: XCUIApplication, row: String, primedName: String,
                             from: CGVector, to: CGVector) {
        app.buttons["toolbar.addButton"].tap()
        let button = app.buttons[row]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "the Add menu lists \(row)")
        XCTAssertTrue(button.isEnabled, "\(row) is available on a fresh document")
        button.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 5), "choosing \(row) closes the Add menu")
        XCTAssertEqual(primedObjectName(app), primedName, "\(row) primed the pen, and the Add icon says so")
        dragOnCanvas(app, from: from, to: to)
        XCTAssertEqual(primedObjectName(app), "", "the lift placed it, so nothing is primed any more")
    }

    /// What the Add icon announces: the name of the object primed for the pen, or "" when none is.
    func primedObjectName(_ app: XCUIApplication) -> String {
        app.buttons["toolbar.addButton"].value as? String ?? ""
    }

    /// Drags the element with the given accessibility identifier by `totalDelta` points in one
    /// motion. XCUITest's synthetic drags can undershoot their intended distance by a
    /// timing-dependent amount (a harness quirk — verified by direct instrumentation that the
    /// app's pan recognizer receives and applies every touch-moved event it's sent), so callers
    /// should request more distance than the minimum needed and assert with a tolerance.
    func performDrag(_ app: XCUIApplication, identifier: String, totalDelta: CGFloat) {
        let element = app.otherElements[identifier]
        guard element.waitForExistence(timeout: 5) else { return }
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: totalDelta, dy: 0))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    /// A single straight-line PencilKit stroke between two normalized points on `element`.
    func drawLine(on element: XCUIElement, from: CGVector, to: CGVector) {
        let start = element.coordinate(withNormalizedOffset: from)
        let end = element.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// One pixel as `rgbaPixel` reads it.
    typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    /// Rasterizes `element`'s own on-screen content (not the whole app screenshot) into a flat RGBA8
    /// buffer, top-left origin, so individual pixels can be inspected by fraction-of-element position.
    /// Goes through an explicit CGContext (rather than trusting the screenshot's native byte order) for
    /// the same reason FloodFillEngine does: it removes any ambiguity about pixel format.
    func rgbaPixel(of element: XCUIElement, dx: Double, dy: Double) -> RGBA? {
        guard let cgImage = element.screenshot().image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // No flip: drawing the screenshot's (top-down) cgImage into a default bitmap context lands its
        // top row at buffer row 0, so buffer[dy] reads the pixel that's visually at dy. (The old
        // translate/scale(-1) here silently read the vertical mirror — undetectable on the centred /
        // color-only probes every earlier test used, but wrong for off-center position checks.)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let x = min(max(Int(dx * Double(width)), 0), width - 1)
        let y = min(max(Int(dy * Double(height)), 0), height - 1)
        let offset = y * bytesPerRow + x * bytesPerPixel
        return (buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
    }

    func rgbaPixel(of element: XCUIElement, at point: CGVector) -> RGBA? {
        rgbaPixel(of: element, dx: point.dx, dy: point.dy)
    }

    func isWhitish(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return pixel.r > 240 && pixel.g > 240 && pixel.b > 240
    }

    /// Dark: the pixel a stroke leaves on white paper, and not the black letterbox margin's absence of one.
    func isInk(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return pixel.r < 100 && pixel.g < 100 && pixel.b < 100
    }

    func isRed(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return pixel.r > 150 && pixel.g < 100 && pixel.b < 100
    }

    func isBlue(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return pixel.b > 150 && pixel.r < 100 && pixel.g < 100
    }

    /// Polls the pixel at `point` on `canvas` until `matches` accepts it, and returns that pixel — **nil
    /// when the deadline passes, never the last reading**. Every render the editor does after a gesture
    /// or a model change lands off the main thread a moment later, so a read of what the canvas shows is
    /// a wait, never an instant look; and `XCTAssertNotNil(waitForPixel(…))` asserts that the canvas
    /// *came to show it*. (A copy that handed back whatever it last read made ten such assertions that
    /// could not go red.) A caller that prints the reading on failure takes a fresh `probe` in its message.
    @discardableResult
    func waitForPixel(_ canvas: XCUIElement, at point: CGVector, timeout: TimeInterval = 10,
                      matches: (RGBA) -> Bool) -> RGBA? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let pixel = rgbaPixel(of: canvas, at: point), matches(pixel) { return pixel }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    /// `waitForPixel`, as the yes/no a plain assertion wants.
    func waitUntil(_ canvas: XCUIElement, _ point: CGVector, _ test: (RGBA?) -> Bool,
                   timeout: TimeInterval = 10) -> Bool {
        waitForPixel(canvas, at: point, timeout: timeout) { test($0) } != nil
    }

    /// One canvas pixel as whole numbers, with `==` so `settled` can compare two reads. A fixture that
    /// asks something of a colour in particular (how blue, which red) adds it in a `private extension`.
    struct RGB: Equatable, CustomStringConvertible {
        let r: Int, g: Int, b: Int
        var sum: Int { r + g + b }
        var description: String { "(r: \(r), g: \(g), b: \(b))" }
    }

    /// The pixel at `dx`, `dy` of `canvas`; black where there is no screenshot to read.
    func probe(_ canvas: XCUIElement, dx: Double, dy: Double) -> RGB {
        let p = rgbaPixel(of: canvas, dx: dx, dy: dy)
        return RGB(r: Int(p?.r ?? 0), g: Int(p?.g ?? 0), b: Int(p?.b ?? 0))
    }

    /// `probe` at a normalized point of the host.
    func probe(_ canvas: XCUIElement, at point: CGVector) -> RGB {
        probe(canvas, dx: point.dx, dy: point.dy)
    }

    /// Reads until two consecutive reads agree, so a probe taken while the render is still landing off
    /// the main thread is not the number the test reasons about (`settledProbe` is the same wait for a
    /// whole region's fingerprint).
    func settled<T: Equatable>(timeout: TimeInterval = 4, _ read: () throws -> T) rethrows -> T {
        var last: T?
        let deadline = Date().addingTimeInterval(timeout)
        var current = try read()
        while Date() < deadline {
            if current == last { return current }
            last = current
            usleep(150_000)
            current = try read()
        }
        return current
    }

    /// The fill runs off-main-thread (see CanvasManager.beginInteractiveFill), so polls the given point on
    /// `element` until it's no longer whitish (i.e. the fill landed) or `timeout` elapses.
    @discardableResult
    func waitUntilFilled(_ element: XCUIElement, dx: Double, dy: Double, timeout: TimeInterval = 15) -> Bool {
        waitUntil(element, CGVector(dx: dx, dy: dy), { !isWhitish($0) }, timeout: timeout)
    }

    /// A point safely inside the paper, inset a further 10% of it from the top-left corner — clear of
    /// the letterbox margin (which reads solid black, so a normalized probe like (0.05, 0.05) can land
    /// in it) and, for this test suite's shapes, all drawn no closer than 30% from any edge, of any
    /// drawn lineart, while still being far from the canvas center.
    func safeOutsideCornerPoint(_ canvas: XCUIElement) -> CGVector {
        onHost(paperRect(in: canvas), 0.1, 0.1)
    }

    // MARK: - Where the paper can be seen

    /// **The top edge, in `canvas.host` fractions, of whatever stands over the lower paper right now** —
    /// the timeline panel, and the docked card riding on it when one is up (`bottomDock.card`).
    ///
    /// The canvas extends *beneath* both (`BottomDock.coveredBottom`), so a host fraction below this is
    /// the chrome's pixel, not the picture's: a probe there reads a dark card and calls it "the effect
    /// did nothing". The panel opens 375 pt tall and a settings card stands up to ~300 pt above it, so
    /// on a portrait iPad the middle of the host is under the card.
    func dockTop(_ app: XCUIApplication, _ canvas: XCUIElement) -> Double {
        let host = canvas.frame
        let panel = app.otherElements["timeline.panel"]
        var top = panel.exists ? panel.frame.minY : host.maxY
        let card = app.descendants(matching: .any)["bottomDock.card"].firstMatch
        if card.exists { top = min(top, card.frame.minY) }
        return Double((top - host.minY) / host.height)
    }

    /// The part of the paper no chrome covers: `paperRect`, cut off where the timeline panel (and a
    /// docked card, if one is up) begins. In host fractions, like `paperRect`.
    ///
    /// **This is where a touch or a probe goes; `paperRect` is where the document is.** Choose where to put
    /// ink and where to tap from this, measured *after* the chrome the test will stand up is up; convert
    /// between host and canvas coordinates against `paperRect`, whose extent they are in.
    func visiblePaperRect(_ app: XCUIApplication, in canvas: XCUIElement) -> CGRect {
        var paper = paperRect(in: canvas)
        paper.size.height = max(0, min(paper.maxY, CGFloat(dockTop(app, canvas))) - paper.minY)
        return paper
    }

    /// A point in the host above whatever stands over its lower part, `x` of the way across and `y` of
    /// the way down from the host's top edge to the dock's (`dockTop`, measured now) — for a gesture that
    /// is about the canvas as a whole and not the paper, such as a pan or a pinch, and must not land on
    /// the timeline or a docked card. The rails stand at the sides, so keep `x` clear of them.
    func aboveTheDock(_ app: XCUIApplication, _ canvas: XCUIElement, x: Double, y: Double) -> CGVector {
        CGVector(dx: x, dy: dockTop(app, canvas) * y)
    }

    /// **The host row to put ink on when a docked card will stand over the picture while it is read** —
    /// a quarter of the way down the paper, which is above any card the dock builds
    /// (`BottomDock.maxScrollHeight` caps its scrolling region) on this device. Call
    /// `assertAboveTheDock` once the card is up: that is what makes the row *measured* rather than
    /// believed, and what turns a future taller card into a message instead of a vacuous probe.
    func rowAboveTheDock(_ canvas: XCUIElement) -> Double {
        let paper = paperRect(in: canvas)
        return Double(paper.minY + paper.height * 0.25)
    }

    /// Fails, naming `what`, when host row `dy` is under the timeline or a docked card.
    func assertAboveTheDock(_ app: XCUIApplication, _ canvas: XCUIElement, dy: Double, _ what: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let top = dockTop(app, canvas)
        XCTAssertLessThan(dy, top, "\(what): host row \(dy) is under the dock, whose top edge is at \(top) — "
                          + "a pixel read there is the card's or the timeline's, not the picture's", file: file, line: line)
    }

    /// Swipes to delete a layer panel row at the given absolute layer index, tapping the
    /// "Delete" action revealed by the swipe.
    func swipeDeleteLayerRow(_ app: XCUIApplication, layerIndex: Int) {
        revealSwipeActions(app, layerIndex: layerIndex)
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
    }

    /// Shared body for the off-center containment tests: draws a closed square at `squareRect` (all
    /// coordinates fractions of the **visible** paper, `visiblePaperRect` — the timeline covers the
    /// paper's lower part, so a fraction of the whole host puts a lower square's edge under the panel),
    /// fills at `insideProbe`, and asserts the interior fills while `outsideProbe` (a point well outside
    /// the square, still on real canvas content) stays blank.
    func runOffCenterFillContainmentTest(
        squareRect: (minX: Double, maxX: Double, minY: Double, maxY: Double),
        insideProbe: (dx: Double, dy: Double),
        outsideProbe: (dx: Double, dy: Double)
    ) throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let paper = visiblePaperRect(app, in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: Double(paper.minX) + Double(paper.width) * dx, dy: Double(paper.minY) + Double(paper.height) * dy)
        }
        let x0 = squareRect.minX, x1 = squareRect.maxX, y0 = squareRect.minY, y1 = squareRect.maxY
        assertAboveTheDock(app, canvas, dy: at(x0, y1).dy, "The square's bottom edge")
        drawLine(on: canvas, from: at(x0, y0), to: at(x1, y0)) // top
        drawLine(on: canvas, from: at(x1, y0), to: at(x1, y1)) // right
        drawLine(on: canvas, from: at(x1, y1), to: at(x0, y1)) // bottom
        drawLine(on: canvas, from: at(x0, y1), to: at(x0, y0)) // left

        let inside = at(insideProbe.dx, insideProbe.dy), outside = at(outsideProbe.dx, outsideProbe.dy)
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: inside.dx, dy: inside.dy)), "Square's interior should still be blank paper before filling")

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // First tap selects the fill tool; its menu stays closed.

        canvas.coordinate(withNormalizedOffset: inside).tap()

        XCTAssertTrue(waitUntilFilled(canvas, dx: inside.dx, dy: inside.dy), "Tapping inside the off-center square should color its interior")

        // The discriminator: a point in the opposite quadrant, far outside the drawn square. If the fill
        // read the reference mirrored, the seed landed in open space and the fill leaked out here.
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: outside.dx, dy: outside.dy)), "Fill of an off-center square must stay contained — leaking here means the reference was rasterized mirrored")
    }

    /// Shared body: selects the fill tool (a single tap, which also switches the left rail's sliders to
    /// gap-closing / threshold / edge-overlap); optionally opens the panel and nudges
    /// `selectAxisPanelSliderID` so that setting becomes the drag axis, then closes the panel again;
    /// reads `sliderID`'s value (left-rail sliders are reliable to *read*), then press-drags horizontally
    /// on the canvas from `from` to `to` and checks the slider moved in the expected direction — proving
    /// the drag adjusts the selected setting live.
    func runInteractiveFillDragTest(
        sliderID: String,
        selectAxisPanelSliderID: String? = nil,
        from: CGVector,
        to: CGVector,
        expectRaised: Bool,
        what: String
    ) throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // Selects the fill tool; the left rail's sliders become gap-closing / threshold / edge-overlap.

        if let selectAxisPanelSliderID {
            // Moving a slider selects its setting as the drag axis. Do it on the panel's horizontal slider
            // (reliable) and nudge it low so the following drag has headroom, then close the panel so the
            // canvas drag isn't intercepted by it.
            fillButton.tap() // Open the Fill panel.
            let axisSlider = app.sliders[selectAxisPanelSliderID]
            XCTAssertTrue(axisSlider.waitForExistence(timeout: 5))
            axisSlider.adjust(toNormalizedSliderPosition: 0.1)
            fillButton.tap() // Close the Fill panel.
        }

        let slider = app.sliders[sliderID]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let before = sliderNumericValue(slider)

        // Press on the canvas and drag horizontally. Both endpoints sit on the left/center of the canvas,
        // clear of the 300pt trailing settings panel, so the drag lands on the fill gesture not the panel.
        let start = canvas.coordinate(withNormalizedOffset: from)
        let end = canvas.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)

        let after = sliderNumericValue(slider)
        if expectRaised {
            XCTAssertGreaterThan(after, before, "\(what) (slider \(before) -> \(after))")
        } else {
            XCTAssertLessThan(after, before, "\(what) (slider \(before) -> \(after))")
        }
    }

    /// These sliders surface their raw value to accessibility (e.g. "8", "40", "2", "6") rather than a
    /// percentage; parse whichever form appears so tests can compare positions on the same slider.
    func sliderNumericValue(_ slider: XCUIElement) -> Double {
        guard let text = slider.value as? String,
              let value = Double(text.replacingOccurrences(of: "%", with: "")) else { return -1 }
        return value
    }

    /// Polls the given point until it reads (or stops reading) whitish, since fill/undo re-render off the
    /// main thread. Returns whether the target state was reached before `timeout`.
    @discardableResult
    func waitUntilBlank(_ element: XCUIElement, dx: Double, dy: Double, timeout: TimeInterval = 10) -> Bool {
        waitUntil(element, CGVector(dx: dx, dy: dy), isWhitish, timeout: timeout)
    }

    /// Drags the element with the given accessibility identifier's own drag gesture from one
    /// normalized offset to another in one motion — used for the color panel's custom SV
    /// square/hue bar, which are plain SwiftUI views (not native sliders), so
    /// `adjust(toNormalizedSliderPosition:)` doesn't apply to them.
    func dragWithinElement(_ element: XCUIElement, from: CGVector, to: CGVector) {
        let start = element.coordinate(withNormalizedOffset: from)
        let end = element.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Reads a layer row's ".vector" marker, formatted "isVector,paintStrokes,erasePunches" (see
    /// `LayerRowModel`). `strokes` counts `.paint` strokes only: Mode 1 commits by *appending* an
    /// `.erase` punch, so against a single combined total "the stroke was
    /// cut in two" and "a punch was added over it" are the same number, and the distinction is the
    /// entire thing the vector-eraser tests are checking.
    func readVectorMarker(_ app: XCUIApplication, layerIndex: Int) -> (isVector: Bool, strokes: Int, erases: Int)? {
        let marker = app.otherElements["layerPanel.row.\(layerIndex).vector"]
        guard marker.waitForExistence(timeout: 5), let value = marker.value as? String else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 3, let v = Int(parts[0]), let n = Int(parts[1]), let e = Int(parts[2]) else { return nil }
        return (v == 1, n, e)
    }

    /// Adds a vector layer through the layer panel's add menu (a long-press opens the kind menu) and
    /// closes the panel again, leaving the new layer active at array index 1.
    func addVectorLayer(_ app: XCUIApplication) {
        app.buttons["toolbar.layersButton"].tap()
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.2)
        let vectorItem = app.buttons["Vector Layer"]
        XCTAssertTrue(vectorItem.waitForExistence(timeout: 5), "The add menu should offer a Vector Layer option")
        vectorItem.tap()
        app.buttons["toolbar.layersButton"].tap()
    }

    /// The mirror of `addVectorLayer`, for the tests that are about the **raster tier itself** — the
    /// "ghost layer" guards, the shape-bake path, the eraser reaching committed pixels. Vector is the
    /// default kind now (PLAN §8), so raster has to be asked for by name; rewriting those tests to
    /// read the vector marker instead would quietly retarget what they guard.
    func addRasterLayer(_ app: XCUIApplication) {
        app.buttons["toolbar.layersButton"].tap()
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.2)
        let rasterItem = app.buttons["Raster Layer"]
        XCTAssertTrue(rasterItem.waitForExistence(timeout: 5), "The add menu should offer a Raster Layer option")
        rasterItem.tap()
        app.buttons["toolbar.layersButton"].tap()
    }

    /// **A filled block on a raster layer, lifted into the raster Move box** — the setup
    /// `DistortUITests` made its own and every raster-box test since has repeated. A rectangle is
    /// selected over the right of the canvas and filled, then Move lifts it. Answers the block's
    /// measured top-left in the host's unit square, which is what the box's own geometry is read from:
    /// the box has no published frame, but the piece it carries is drawn where the box is.
    func liftAFilledBlockIntoTheRasterMoveBox(_ app: XCUIApplication, on canvas: XCUIElement) throws -> CGPoint {
        addRasterLayer(app)
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
        return filled
    }

    /// Opens the layer panel, reads the vector marker, and closes it again — the panel overlays the
    /// canvas, so tests that alternate between drawing and counting need it shut in between.
    func vectorMarkerViaPanel(_ app: XCUIApplication, layerIndex: Int) -> (isVector: Bool, strokes: Int, erases: Int)? {
        app.buttons["toolbar.layersButton"].tap()
        let marker = readVectorMarker(app, layerIndex: layerIndex)
        app.buttons["toolbar.layersButton"].tap()
        return marker
    }

    /// Clears the hex field and types a new value, submitting with Return. Factored out because the
    /// clear-then-type dance (XCUIElement has no select-all-and-replace) is easy to get subtly wrong.
    func setHexField(_ app: XCUIApplication, _ hexField: XCUIElement, to value: String) {
        hexField.tap()
        if let currentValue = hexField.value as? String {
            hexField.typeText(String(repeating: "\u{8}", count: currentValue.count))
        }
        hexField.typeText(value)
        app.keyboards.buttons["Return"].tap()
    }

    /// Opens the colour panel and waits for its default (Square) tab to actually be up — `colorPanel.
    /// svSquare`'s existence, not just `toolbar.colorButton`'s tap — before returning. **Not optional**:
    /// the panel slides in (`DrawingView`'s `.move(edge: .top)` transition), and a tab bar tap fired
    /// before that settles can land on a button whose on-screen position is still mid-animation, tapping
    /// nothing.
    func openColorPanel(_ app: XCUIApplication) {
        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5), "The toolbar's colour button")
        colorButton.tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForExistence(timeout: 5),
                      "The colour panel's default tab should be up before it is touched")
    }

    /// Closes the colour panel through the toolbar's colour button and waits for it to be gone —
    /// **not optional**: the panel is a dropdown over the right of the canvas, and the next stroke runs
    /// straight under it, so an unconfirmed close puts the drag on the hue bar instead of the paper and
    /// repaints the brush a colour nothing asked for. `tab` is whatever element of the tab the test was
    /// just using (the default is the Square tab's), for a tab that does not have a square to wait on.
    func closeColorPanel(_ app: XCUIApplication, whileShowing tab: XCUIElement? = nil) {
        app.buttons["toolbar.colorButton"].tap()
        XCTAssertTrue((tab ?? app.otherElements["colorPanel.svSquare"]).waitForNonExistence(timeout: 5),
                      "The colour panel must be closed before the canvas is touched")
    }

    /// Sets the brush colour through the toolbar's colour panel and closes it again, confirmed gone
    /// before returning (`closeColorPanel`).
    func setBrushColor(_ app: XCUIApplication, hex: String) {
        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5), "The toolbar's colour button")
        colorButton.tap()
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5), "The colour panel's hex field")
        setHexField(app, hexField, to: hex)
        closeColorPanel(app)
    }

    /// Back to black through the SV square rather than the hex field: the field needs the keyboard, and
    /// a second visit to it mid-test is a focus race the pick has nothing to do with. Bottom-left of the
    /// square is saturation 0, brightness 0 — black, whatever the hue happens to be.
    func returnTheBrushToBlack(_ app: XCUIApplication) {
        openColorPanel(app)
        dragWithinElement(app.otherElements["colorPanel.svSquare"],
                          from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.0, dy: 1.0))
        closeColorPanel(app)
    }

    func brushIsSelected(_ app: XCUIApplication) -> Bool {
        app.buttons["toolbar.brushButton"].isSelected
    }

    func openLayerPanel(_ app: XCUIApplication) {
        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()
    }

    /// Shuts the layer rail, and the options panel hanging off it, leaving the canvas clear.
    ///
    /// **An effect layer's settings bar is on screen *with* the rail since TODO (118)** — it is there
    /// because the layer is selected, and the rail is how another is — where it used to stand the rail
    /// down for as long as it was up. A test that reads the artwork's pixels or taps the canvas shuts
    /// the rail itself, and the bar surviving that is the point rather than a convenience.
    func closeLayerRail(_ app: XCUIApplication) {
        let layersButton = app.buttons["toolbar.layersButton"]
        if layersButton.isSelected { layersButton.tap() }
    }

    /// Adds a vector layer through the panel's "+" menu, with the panel **already open** — the
    /// replacement for the bare `addButton.tap()` that used to do this in one gesture.
    ///
    /// **The "+" no longer adds anything by itself.** It carried a `primaryAction` that made a plain
    /// tap mean `addVectorLayer`, which left the list of kinds reachable only by press-and-hold; the
    /// owner's complaint was that the button spawned a kind they had not asked for behind an
    /// affordance nothing advertised. With the closure gone, SwiftUI's default `Menu` behaviour
    /// applies and *any* tap opens the list, so every add is now two taps: the "+", then the kind.
    ///
    /// Vector because that is the kind the primaryAction used to pick, so every caller that was
    /// written against the one-tap shortcut keeps the document it was written for. Callers that want
    /// another kind have a helper per kind below.
    ///
    /// The long-pressing helpers below were not rewritten to tap: a long press opens the menu now as
    /// it did before (it is only the *tap* whose meaning changed), so leaving them alone keeps this
    /// commit's diff to the sites whose behaviour actually moved.
    func addVectorLayerFromOpenPanel(_ app: XCUIApplication) {
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let item = app.buttons["layerPanel.addVectorButton"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The add menu should offer a Vector Layer option")
        item.tap()
    }

    /// The panel's "+" is a plain Menu, so a press-and-hold opens it and the Folder item can be
    /// tapped. (A plain tap opens it too, since the `primaryAction` that used to claim the tap for
    /// `addVectorLayer` is gone — see `addVectorLayerFromOpenPanel`.)
    func addFolderFromAddMenu(_ app: XCUIApplication) {
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.0)
        let folderItem = app.buttons["layerPanel.addFolderButton"]
        XCTAssertTrue(folderItem.waitForExistence(timeout: 5))
        folderItem.tap()
    }

    /// Same menu, one item further down: §4.3's compositor node arrives from the "+" the way a
    /// folder does, because it *is* one — a folder whose children are its input slots.
    func addMixNodeFromAddMenu(_ app: XCUIApplication) {
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.0)
        let nodeItem = app.buttons["layerPanel.addMixNodeButton"]
        XCTAssertTrue(nodeItem.waitForExistence(timeout: 5))
        nodeItem.tap()
    }

    /// §4.4's effect layer — a leaf that grades the backdrop beneath it and holds no pixels of its
    /// own — **created the only way it can be now: as a value layer, then flipped into effect mode.**
    ///
    /// There is no "Effect Layer" item in the add menu any more, and this helper's two-step shape is
    /// the point rather than an inconvenience worked around. The effect layer stopped being a
    /// `LayerKind` of its own and became a *mode* of `.value`, told apart by whether `Layer.effect` is
    /// present; a menu entry for it would have been a second way to create one kind, differing only
    /// in which mode it arrived in, and an artist who picked the wrong one would have had to delete
    /// the layer and start again rather than flip the picker already sitting in its options.
    ///
    /// So the route is: add the value layer, open its options, and pick a grade from the Mode row.
    /// **Brightness / Contrast** because it is what the retired menu item created — the identity
    /// instance, so a document built by this helper is the same document the old one built.
    ///
    /// Leaves the layer's options panel **open**, exactly as the picker leaves it. Callers that want
    /// the canvas clear should close the panel, which is what the row-based helpers above also expect.
    func addEffectLayerFromAddMenu(_ app: XCUIApplication) {
        addValueLayerFromAddMenu(app)

        // The new layer is active the moment it lands, so one tap on its row opens options rather
        // than merely selecting it — the same two-meanings-of-a-tap the value-layer test relies on.
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The add menu should have created a second layer")
        row.tap()

        // One row, not two: a value layer's grades live in its Blend Mode menu below the blends
        // (`LayerPanel.blendOrEffectRow`), which is the owner's merge of the old Mode row into this
        // one. The identifiers are the blend row's for that reason.
        let modeButton = app.buttons["layerOptions.blendModeButton"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5),
                      "A value layer's options should offer the Blend Mode row that chooses between its two modes")
        modeButton.tap()

        // `effectMenuSlug(.brightnessContrast(…))` — "Brightness / Contrast" lower-cased with the
        // punctuation stripped. Quoting the slug rather than the label for the reason the slug exists:
        // it survives a rewording of the visible name.
        let item = app.buttons["layerOptions.blendMode.brightnesscontrast"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The Blend Mode menu should list the effect catalogue")
        item.tap()
    }

    /// Same menu again, for §4.5's value layer — one flat colour across the canvas.
    func addValueLayerFromAddMenu(_ app: XCUIApplication) {
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "The layer panel's + button must be on screen")
        addButton.press(forDuration: 1.0)
        let item = app.buttons["layerPanel.addValueButton"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The + menu should list Value Layer")
        item.tap()
    }

    /// Same menu again, for the transformation layer — TRANSFORM_LAYER.md §2 ruling 2's kind of its
    /// own. Until 2026-09-11 a transformation layer was reached by adding a value layer and picking
    /// Transform from its Blend Mode row; that entry is gone, and this is the whole of the route now.
    func addTransformLayerFromAddMenu(_ app: XCUIApplication) {
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "The layer panel's + button must be on screen")
        addButton.press(forDuration: 1.0)
        let item = app.buttons["layerPanel.addTransformButton"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The + menu should list Transform Layer")
        item.tap()
    }

    /// Returns to the gallery (saving the project) and waits for its tile to appear.
    ///
    /// **`toolbar.galleryButton`, not `square.grid.2x2`.** This read the *implicit* identifier
    /// SwiftUI derives from `Image(systemName:)` until 2026-09-07, when `ed7c8f4` gave the gallery
    /// button the explicit identifier its seven toolbar neighbours already carried — and an explicit
    /// identifier replaces the implicit one, so this lookup silently stopped matching anything. Two
    /// `GalleryRecoveryUITests` and `EraserAndPersistenceUITests`' save/reload round trip went red
    /// together, all three of them here at line 563 and none of them anywhere near the persistence
    /// code they exist to guard. Never reach a control by a glyph name: it is not an identifier the
    /// app promises, and depending on the *absence* of one makes adding one a breaking change.
    @discardableResult
    func saveEditorAndReturnToGallery(_ app: XCUIApplication) -> XCUIElement {
        let galleryButton = app.buttons["toolbar.galleryButton"]
        XCTAssertTrue(galleryButton.waitForExistence(timeout: 5),
                      "The editor's toolbar should carry the route back to the gallery")
        galleryButton.tap()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "The saved project should show up in the gallery")
        return tile
    }

    func layerCell(_ app: XCUIApplication, layerIndex: Int) -> XCUIElement {
        app.tables["layerPanel.list"].cells.containing(.staticText, identifier: "layerPanel.row.\(layerIndex)").element
    }

    func folderCell(_ app: XCUIApplication, named name: String) -> XCUIElement {
        app.tables["layerPanel.list"].cells.containing(.staticText, identifier: "layerPanel.folder.\(name)").element
    }

    /// Which folder a layer row reports belonging to ("" when top level).
    func rowFolder(_ app: XCUIApplication, layerIndex: Int) -> String {
        app.otherElements["layerPanel.row.\(layerIndex).folder"].value as? String ?? "?"
    }

    /// Drags a row leftward to expose its swipe actions. A plain `swipeLeft()` is a fast flick that
    /// the table sometimes misses, so this drags deliberately instead.
    func revealSwipeActions(_ app: XCUIApplication, layerIndex: Int) {
        let row = app.staticTexts["layerPanel.row.\(layerIndex)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let cell = layerCell(app, layerIndex: layerIndex)
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Press and hold past the 0.5s lift, then drag. `dropDY` picks the band of the destination row:
    /// 0.5 lands *on* it (into a folder / group with a layer), 0.95 lands below it.
    func dragRow(_ source: XCUIElement, onto target: XCUIElement, dropDY: CGFloat) {
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.9,
                   thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dropDY)),
                   withVelocity: .slow, thenHoldForDuration: 0.6)
    }

    /// Draws a stroke and keeps the finger down at the end of it, which is the smart-shape gesture.
    ///
    /// **This no longer produces a shape, and cannot be made to.** `ShapeHoldClock` decides the hold
    /// from `UITouch.timestamp` — newest sample minus newest *moving* sample — so it needs a pen that
    /// keeps reporting while stationary. A real pencil does (measured on the owner's iPad: ~59
    /// events/second through a 4.4 s stationary hold). **XCUITest's synthetic touch does not, and the
    /// `thenHoldForDuration` below contributes nothing whatsoever**: the same gesture with the hold
    /// set to 0.0 s, 1.5 s and 3.0 s delivered 134 / 136 / 136 samples spanning 2.218 / 2.217 /
    /// 2.217 s of pen time — identical, i.e. the drag and only the drag. A 3.0 s *leading* press is
    /// event-free the same way. Across all of them the clock's greatest accumulated stillness was
    /// 0.000 s.
    ///
    /// It is not a velocity or a threshold that can be tuned around, either. XCUITest emits a move
    /// only when the interpolated position changes (~0.5 pt quantum), so within one gesture the
    /// spacing between samples is uniform — there is no way to say "travel, *then* be still" in a
    /// single touch, and the public API has no multi-segment single-touch gesture. A drag slow enough
    /// to read as still reads as still from its first sample, and fires the hold on a two-point
    /// stroke that detects as nothing.
    ///
    /// So callers get a freehand stroke, not a shape. Every test using this helper that still passes
    /// passes because it asserts something a freehand stroke satisfies too (ink present, one stroke
    /// recorded); the two that genuinely needed the pending shape are skipped and named in BUGS.md.
    /// **Do not "fix" this by weakening the clock** — the device data says the clock is right.
    func drawAndHoldShape(on canvas: XCUIElement, from: CGVector, to: CGVector) {
        let start = canvas.coordinate(withNormalizedOffset: from)
        let end = canvas.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.5)
    }

    /// Bakes a shape sitting in the adjustable state, without drawing anything.
    ///
    /// Switching tools is a canvas edit, so it commits whatever is transient — and unlike touching
    /// the canvas it adds no ink of its own. Touching the canvas *also* commits the shape (that is
    /// the point of `testDrawingOverAPendingShapeCommitsItAndDrawsInOneTouch`), but it commits it
    /// and then draws the stroke the touch asked for, so it is no use to a caller that wants to
    /// count exactly what the shape itself laid down.
    func commitPendingShape(on app: XCUIApplication) {
        app.buttons["toolbar.eraserButton"].tap()
        app.buttons["toolbar.brushButton"].tap()
    }

    // MARK: - The brushes menu and the brush editor

    /// Taps a brush row once it is actually hittable.
    ///
    /// **The wait is the assertion, not a sleep.** A row's preview stroke is rendered off the main
    /// thread and written into the row when it arrives (`BrushPreviewRow`), so for the first tens of
    /// milliseconds after the menu opens the list is being rebuilt under XCUITest's snapshot and a
    /// tap resolves no hit point at all — `Computed hit point {-1, -1}`, on a row whose frame is
    /// right there in the tree. A finger is unaffected; the harness is not. Asserting the row
    /// *becomes* hittable says the thing worth saying — the artist can reach this row — and says it
    /// without a fixed delay.
    @discardableResult
    func tapWhenHittable(_ element: XCUIElement, _ message: String = "") -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(message.isEmpty ? "Element" : message): never appeared")
            return false
        }
        guard element.wait(for: \.isHittable, toEqual: true, timeout: 5) else {
            XCTFail("\(message.isEmpty ? "Element" : message): appeared but never became tappable")
            return false
        }
        element.tap()
        return true
    }

    /// Opens a stroke tool's **brushes menu** — the two-column library, BRUSH.md §7.1.
    ///
    /// The toolbar button is select-then-toggle (`TopToolbar.selectBrushToolAndTogglePanel`), so
    /// reaching the menu from an arbitrary starting tool takes one tap to select and one to open, and
    /// only one if that tool was already active. Probing for the menu itself is what makes this work
    /// from either state.
    func openBrushLibrary(_ app: XCUIApplication, tool: String = "brush") {
        let prefix = tool == "eraser" ? "eraserPanel" : "brushPanel"
        let library = app.scrollViews["\(prefix).groupList"]
        let button = app.buttons["toolbar.\(tool)Button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        if library.waitForExistence(timeout: 3) { return }
        button.tap()
        XCTAssertTrue(library.waitForExistence(timeout: 5), "The \(tool) library should open")
    }

    /// Opens the **brush editor** — where every brush parameter lives as of BRUSH.md §2.20, and where
    /// this suite's Size / Opacity / Stabilization / Spacing sliders moved to.
    ///
    /// The gesture is §2.20's: one tap selects a brush, a second tap on the *already selected* one
    /// opens the editor. The selected row is found by its `.isSelected` trait rather than by name, so
    /// a caller need not know which brush the document happens to have picked.
    func openBrushEditor(_ app: XCUIApplication, tool: String = "brush") {
        let prefix = tool == "eraser" ? "eraserPanel" : "brushPanel"
        let sizeSlider = app.sliders["\(prefix).sizeSlider"]
        if sizeSlider.exists { return }
        openBrushLibrary(app, tool: tool)

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "\(prefix).brush."))
        guard let selected = rows.allElementsBoundByIndex.first(where: { $0.isSelected }) else {
            XCTFail("Exactly one brush row must read as selected — that highlight is what makes §2.20's second tap unambiguous")
            return
        }
        tapWhenHittable(selected, "The selected brush's row")
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5),
                      "A second tap on the selected brush should open the editor")
    }

    /// Sets a stroke tool's diameter through the editor's Size slider (range 1...200 — see
    /// `BrushEditorScreen`), and **closes the editor again**, leaving the brushes menu open.
    ///
    /// **The close is not tidiness; it is what BRUSH.md §2.24 forces.** The editor covers the whole
    /// screen now, so a caller that set a size and then drew on `canvas.host` — which is what every
    /// caller of this does — would be drawing on the editor. Leaving the *menu* open preserves what
    /// those callers rely on next: the first canvas touch dismisses it (`CanvasManager
    /// .interactionBegan`), which is the behaviour they assert.
    func setBrushSize(_ app: XCUIApplication, tool: String = "brush", normalized: CGFloat) {
        let prefix = tool == "eraser" ? "eraserPanel" : "brushPanel"
        openBrushEditor(app, tool: tool)
        let slider = app.sliders["\(prefix).sizeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: normalized)
        closeBrushEditor(app, tool: tool)
    }

    /// Closes the full-screen editor with its Done chevron, back to the brushes menu.
    func closeBrushEditor(_ app: XCUIApplication, tool: String = "brush") {
        let prefix = tool == "eraser" ? "eraserPanel" : "brushPanel"
        guard app.sliders["\(prefix).sizeSlider"].exists else { return }
        tapWhenHittable(app.buttons["\(prefix).editorBack"], "The editor's Done chevron")
        XCTAssertTrue(app.sliders["\(prefix).sizeSlider"].waitForNonExistence(timeout: 5),
                      "Done must take the editor down")
    }

    // MARK: - The Move box on the glass

    /// The Move box as `x,y,w,h` in `canvas.host`'s unit square — `CanvasView.Coordinator
    /// .publishCanvasState`'s `movebox:` field, in the units `inkProbe` reads the canvas in — or nil
    /// while no box is up.
    func moveBox(_ app: XCUIApplication) -> CGRect? {
        let parts = readField(app, "movebox:").split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// The box once it has stopped moving — **three reads 0.3 s apart that agree**. The box is up
    /// before the canvas has been fitted to its host, and after a drag it is published on the pass
    /// that follows, so a single read can be a real box in the wrong place.
    func settledMoveBox(_ app: XCUIApplication, timeout: TimeInterval = 10) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        var agreeing = 0
        var last: CGRect?
        while Date() < deadline {
            let now = moveBox(app)
            agreeing = (now != nil && now == last) ? agreeing + 1 : 0
            last = now
            if agreeing >= 3 { return now }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return nil
    }

    // MARK: - The paper on the glass

    /// The paper's rect in the host's unit square: a square document (`launchIntoEditor` takes the
    /// 2048×2048 default) letterboxed across a host that is not, as a centred square of side
    /// `min(w, h)` with black surround. **Measure against this rather than against the host** whenever
    /// "on the paper" is the subject — a normalized offset that turned out to be off it makes every
    /// assertion vacuous.
    func paperRect(in canvas: XCUIElement) -> CGRect {
        let frame = canvas.frame
        let side = min(frame.width, frame.height)
        return CGRect(x: (frame.width - side) / 2, y: (frame.height - side) / 2,
                      width: side, height: side).applying(
                        CGAffineTransform(scaleX: 1 / frame.width, y: 1 / frame.height))
    }

    /// A point given in fractions of the **paper** (which may be negative — off it), as host fractions.
    func onHost(_ paper: CGRect, _ x: Double, _ y: Double) -> CGVector {
        CGVector(dx: paper.minX + paper.width * x, dy: paper.minY + paper.height * y)
    }

    /// How many of 201 evenly spaced paper columns along one row, over `span` of the paper's width,
    /// read as ink.
    func inkColumnCount(_ probe: (Double, Double) -> Bool, _ paper: CGRect, row: Double,
                        span: ClosedRange<Double>) -> Int {
        (0...200).map { span.lowerBound + (span.upperBound - span.lowerBound) * Double($0) / 200 }
            .filter { probe(paper.minX + paper.width * $0, paper.minY + paper.height * row) }.count
    }

    /// A drag that starts on `from`, holds still long enough for a drag-start to be armed, and travels
    /// `paperDX` of the paper's width at a finger's pace — dozens of touch-moves.
    func dragAcross(_ canvas: XCUIElement, from: CGVector, paperDX: Double, paper: CGRect) {
        let start = canvas.coordinate(withNormalizedOffset: from)
        let points = paper.width * canvas.frame.width * paperDX
        start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: points, dy: 0)),
                    withVelocity: XCUIGestureVelocity(240), thenHoldForDuration: 0.3)
    }

    // MARK: - Reading ink off the canvas

    /// One screenshot of the canvas, as a "what colour is at this normalized point" probe.
    ///
    /// One screenshot for the whole scan: `rgbaPixel` takes a fresh one per call, and the readings below
    /// are hundreds of points each. No flip, for `rgbaPixel`'s reason: the screenshot's cgImage is
    /// top-down, so buffer row 0 is the row the artist sees at the top.
    func pixelProbe(_ canvas: XCUIElement) throws -> (Double, Double) -> RGBA {
        let image = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return { dx, dy in
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            let offset = y * width * 4 + x * 4
            return (buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
        }
    }

    /// One screenshot of the canvas, as an "is there ink at this normalized point" probe.
    ///
    /// **Ink is *dark*, not merely "not white", and that distinction cost `DistortUITests` two runs.** The
    /// canvas is letterboxed inside a black `canvas.host`, so a not-white test answers `true` for
    /// every pixel of the margin — which made `inkTopLeft` return the search window's own corner, put
    /// every subsequent gesture off the paper entirely, and read exactly like an overlay that was
    /// ignoring touches. Both operands of a probe have to be the two things you meant to compare.
    func inkProbe(_ canvas: XCUIElement) throws -> (Double, Double) -> Bool {
        let pixel = try pixelProbe(canvas)
        return { self.isInk(pixel($0, $1)) }
    }

    /// A probe taken once the canvas has stopped changing — **two consecutive readings that agree**,
    /// or the last one at the deadline.
    ///
    /// **"The canvas at rest" is becoming an *eventual* state rather than an immediate one.** The
    /// bake-wiring work serves the resting canvas from a baked frame that arrives after the gesture
    /// (MEASURED 0.40 s after a stroke, 0.024 s after a frame step), so a screenshot taken on the
    /// line after `Done` can catch the frame before the commit landed. Waiting for *stability* rather
    /// than for the answer is what keeps that from turning into a test that passes by retrying until
    /// it likes what it sees: the assertions below still run once, against whatever settled.
    ///
    /// `window` is the region of the host, in normalized units, that the fingerprint samples — the
    /// part of the picture the caller is about to measure. The default is `DistortUITests`' right
    /// half; a test whose ink lives elsewhere names its own.
    func settledProbe(_ canvas: XCUIElement,
                      window: CGRect = CGRect(x: 0.45, y: 0.15, width: 0.45, height: 0.40),
                      timeout: TimeInterval = 6) throws -> (Double, Double) -> Bool {
        // A coarse fingerprint of the region the piece lives in — cheap to compare, and it changes
        // whenever the artwork under it does.
        func fingerprint(_ probe: (Double, Double) -> Bool) -> [Bool] {
            (0..<24).flatMap { yi in (0..<24).map { xi in
                probe(window.minX + window.width * Double(xi) / 24,
                      window.minY + window.height * Double(yi) / 24)
            } }
        }
        var probe = try inkProbe(canvas)
        var previous = fingerprint(probe)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let next = try inkProbe(canvas)
            let current = fingerprint(next)
            probe = next
            if current == previous { return probe }
            previous = current
        }
        return probe
    }

    /// How wide the ink is along one row, in normalized units, over a window known to contain it.
    func inkedWidth(_ probe: (Double, Double) -> Bool, row dy: Double,
                            from x0: Double = 0.50, to x1: Double = 0.90) -> Double {
        let steps = 300
        let hits = (0...steps).filter { probe(x0 + (x1 - x0) * Double($0) / Double(steps), dy) }.count
        return (x1 - x0) * Double(hits) / Double(steps)
    }

    /// The top-left corner of the inked block, measured rather than assumed.
    ///
    /// **XCUITest's synthetic drags undershoot by a timing-dependent amount** (`performDrag`'s own
    /// note), so the selection rectangle a test asks for is not the one it gets — and the corner grip
    /// is `TransformHandleView`'s fixed 24×24 in *canvas* points inside a container scaled to the
    /// screen, i.e. under ten screen points across at the default canvas size. That is BUGS.md's
    /// shrink-with-zoom entry arriving on a second tool, exactly as LASSO_MOVE.md §6 predicts, and it
    /// leaves no margin for aiming at a coordinate the drag never reached. Measuring the block that
    /// actually landed removes the whole class of miss, and needs no accessibility affordance —
    /// `canvas.host` is an accessibility element in its own right, which hides every descendant, so a
    /// grip inside it cannot be addressed by identifier at all (`Coordinator.publishCanvasState`'s
    /// own note records the same wall for the text editor).
    func inkTopLeft(_ probe: (Double, Double) -> Bool,
                            in window: CGRect) throws -> CGPoint {
        var minX = 1.0, minY = 1.0
        let steps = 300
        for xi in 0...steps {
            for yi in 0...steps where yi % 3 == 0 {
                let x = window.minX + window.width * Double(xi) / Double(steps)
                let y = window.minY + window.height * Double(yi) / Double(steps)
                guard probe(x, y) else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
            }
        }
        guard minX < 1, minY < 1 else { throw XCTSkip("no ink found in \(window)") }
        return CGPoint(x: minX, y: minY)
    }


    /// How tall the ink is down one column, in normalized units — `inkedWidth`'s transpose, and the
    /// measurement a horizontal line's *thickness* needs.
    func inkedHeight(_ probe: (Double, Double) -> Bool, column dx: Double,
                             from y0: Double = 0.05, to y1: Double = 0.55) -> Double {
        let steps = 500
        let hits = (0...steps).filter { probe(dx, y0 + (y1 - y0) * Double($0) / Double(steps)) }.count
        return (y1 - y0) * Double(hits) / Double(steps)
    }

    /// Unfolds the Select panel's edit band — Colour, Brush, Size, Opacity — which since TODO (90)
    /// sits behind the action row's Edit icon rather than taking a row of its own. A selection must
    /// already be up: the icon is disabled without one, like every other tab in that row.
    func openSelectionEditBand(_ app: XCUIApplication) {
        let edit = app.buttons["selectPanel.editDisclosure"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the Select panel's action row carries the Edit icon")
        XCTAssertTrue(edit.isEnabled, "a selection is up, so the Edit icon is live")
        if edit.value as? String != "expanded" { edit.tap() }
        XCTAssertEqual(edit.value as? String, "expanded", "pressing Edit unfolds the band")
    }

    /// Keeps a screenshot in the test's result bundle, so a run can be looked at and not only read — the
    /// bar for a visible feature is that someone saw it. `subject` is the app, one element of it (the
    /// canvas) or `XCUIScreen.main`; `lifetime` is `.keepAlways` unless a suite that attaches a great many
    /// asks to keep only the failures'.
    func attachScreenshot(_ subject: XCUIScreenshotProviding, _ name: String,
                          lifetime: XCTAttachment.Lifetime = .keepAlways) {
        let shot = XCTAttachment(screenshot: subject.screenshot())
        shot.name = name
        shot.lifetime = lifetime
        add(shot)
    }

    // MARK: - Measuring in screen points (shared by the text editor's UI tests)
    //
    // **Everything is in absolute screen points, converted to `canvas.host`'s normalised space only at
    // the instant of a reading.** Once the software keyboard is up the editor's *accessibility* frame
    // shrinks (973 pt against 1356 here) while the picture stays exactly where it was, so a normalised
    // coordinate means two different screen points before and after — which is how this test's first
    // drafts aimed a drag 100 pt above the words and measured the Text panel's card as ink. Points are
    // the one currency that does not move.

    /// `rect` (screen points) as a window of `canvas.host`'s own frame *now*.
    func canvasWindow(_ rect: CGRect, in canvas: XCUIElement) -> CGRect {
        let frame = canvas.frame
        return CGRect(x: (rect.minX - frame.minX) / frame.width, y: (rect.minY - frame.minY) / frame.height,
                      width: rect.width / frame.width, height: rect.height / frame.height)
    }

    /// What the words look like inside `rect`: where the ink starts, where it ends, and how much of it
    /// there is — all in screen points, off one settled screenshot.
    func inkReading(_ canvas: XCUIElement, in rect: CGRect) throws -> (topLeft: CGPoint, right: CGFloat, ink: Int) {
        let frame = canvas.frame
        let win = canvasWindow(rect, in: canvas)
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
    func dragInPoints(_ app: XCUIApplication, from: CGPoint, to: CGPoint) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: from.x, dy: from.y))
            .press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: to.x, dy: to.y)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// **A tap synthesised while the keyboard is still leaving lands where a control *was*.** The
    /// editor is laid out above the software keyboard and its dismissal animates the layout back;
    /// XCUITest reads a button's frame and then taps a point, and the undo button at the bottom of
    /// the side toolbar moves a few hundred points during that animation — MEASURED: an undo tapped
    /// one second after leaving text mode did nothing at all, and the recording showed the layout
    /// still settling. So wait for the keyboard to be gone and the host's frame to be back where it
    /// started before pressing anything — and fail if it never is, since a layout that stays
    /// compressed is the defect `EditorKeyboardLayoutUITests` pins.
    func waitForTheLayoutToSettle(_ app: XCUIApplication, _ canvas: XCUIElement, restoring host: CGRect) {
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

    // MARK: - Writing words

    /// **Where the first words go, and why it is high.** With the keyboard up the editor is laid out
    /// above it and the docked Text panel covers the lower part of the visible paper — MEASURED, from
    /// 0.24 of the host's height down — so a box placed lower than that is written under its own menu
    /// and a pixel probe reads the panel's dark card instead of the words.
    static let wordsOffset = CGVector(dx: 0.55, dy: 0.16)

    /// The words' window on the host, in screen points — above the Text panel's top edge, so a probe
    /// measures ink and not the panel's dark card.
    func wordsWindow(in host: CGRect) -> CGRect {
        CGRect(x: host.minX + 0.45 * host.width, y: host.minY + 0.145 * host.height,
               width: 0.54 * host.width, height: 0.09 * host.height)
    }

    /// Add → Add Text, a tap where the words go (`wordsOffset`) and `string` typed into the box — the
    /// box left open, the keyboard up. Returns the point (screen points) the box's top-left sits at.
    func writeWords(_ string: String, _ app: XCUIApplication, _ canvas: XCUIElement) -> CGPoint {
        let offset = Self.wordsOffset
        let host = canvas.frame
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5), "PREMISE: the Add menu lists Add Text")
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "PREMISE: the text panel is up")
        let topLeft = CGPoint(x: host.minX + offset.dx * host.width, y: host.minY + offset.dy * host.height)
        canvas.coordinate(withNormalizedOffset: offset).tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: a live text box (text:\(readTextState(app)))")
        typeIntoTextBox(string, app, at: CGPoint(x: topLeft.x + 0.01 * host.width, y: topLeft.y + 0.01 * host.height))
        return topLeft
    }

    // MARK: - The timeline's size

    /// Drags the timeline's grab handle up by `points` — down for a negative number — and answers how far
    /// the timeline's own top edge actually travelled, which is not `points`, because XCUITest's
    /// synthetic drags undershoot (`performDrag`'s note) and because the height is clamped.
    @discardableResult
    func dragTimelineGrabHandle(_ app: XCUIApplication, by points: CGFloat) -> CGFloat {
        let handle = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let before = handle.frame.minY
        // An empty stretch of the top bar, between the left group of buttons and the transport: the whole
        // bar is the grab handle, and a drag that begins on a button presses it — beside the collapse
        // chevron that opens the frame-rate panel, at the bar's centre it starts playback.
        let panel = app.otherElements["timeline.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.width * 0.32, dy: panel.frame.minY + 34))
        start.press(forDuration: 0.2,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: -points)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        return before - app.buttons["timeline.collapseButton"].frame.minY
    }

    // MARK: - Staggered multi-touch

    /// **Two fingers, each travelling from where it lands to its own end point** — a pinch, a drag, or
    /// both at once, which is the one shape XCUITest's public `pinch` cannot make (it holds the
    /// centroid still).
    ///
    /// Both touches go through the event synthesiser XCUITest's own gestures are built on
    /// (`XCPointerEventPath`, `XCSynthesizedEventRecord` in XCUIAutomation), reached by selector
    /// because it is not public API; a missing class or selector is an `XCTSkip` naming it rather than
    /// a crash. `a` lands first and `b` lands `stagger` seconds later, in a separate touch event —
    /// XCUITest's public multi-touch gestures deliver both touches in a *single* `touchesBegan`
    /// (`CanvasTransformFreezeUITests`' header has the measurement), so every recognizer that asks
    /// "is this touch one of a batch?" answers yes and the first finger is never seen alone. The
    /// owner's recordings say a real hand never does that: `recording-20260923-200911` puts its two
    /// fingers down 10–20 ms apart, in two events, on every gesture in the file.
    ///
    /// - Parameters:
    ///   - from, to: where each finger lands and where it lifts, in screen points.
    ///   - stagger: how long after `a` the second finger lands.
    ///   - duration: how long the travel takes, after the second finger is down.
    ///   - steps: how many intermediate positions each finger reports on the way.
    func twoFingerGesture(from: (a: CGPoint, b: CGPoint), to: (a: CGPoint, b: CGPoint),
                          stagger: TimeInterval = 0.02, duration: TimeInterval = 0.6,
                          steps: Int = 12) throws {
        var paths: [AnyObject] = []
        for (origin, destination, down) in [(from.a, to.a, 0.0), (from.b, to.b, stagger)] {
            let path = try SynthesizedTouch.path(at: origin, offset: down)
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                try SynthesizedTouch.move(path, to: CGPoint(x: origin.x + (destination.x - origin.x) * t,
                                                            y: origin.y + (destination.y - origin.y) * t),
                                          at: stagger + duration * t)
            }
            try SynthesizedTouch.lift(path, at: stagger + duration + 0.02)
            paths.append(path)
        }
        try SynthesizedTouch.synthesize(paths, named: "two-finger gesture")
    }

    /// **A pinch in the upper-left of `element`, where no docked panel and no rail's menu reaches.**
    /// `XCUIElement.pinch` straddles the element's middle, and the canvas element is the whole window:
    /// with a tall panel docked above the timeline (Text, the colour wheels, an effect's settings) or the
    /// layer rail's menus open, the middle of it is *theirs*, one of the two fingers lands on one of
    /// them, and the canvas never sees a pinch. A test that is about the canvas moving while such a panel
    /// is up pinches where none is — halfway up the space above the dock (`aboveTheDock`), left of the
    /// rail. Both fingers land in one event, as `pinch` lands them.
    func pinchAboveTheDock(_ app: XCUIApplication, _ element: XCUIElement, scale: CGFloat) throws {
        let centre = element.coordinate(withNormalizedOffset: aboveTheDock(app, element, x: 0.16, y: 0.5)).screenPoint
        let spread: CGFloat = 40
        try twoFingerGesture(from: (CGPoint(x: centre.x - spread, y: centre.y), CGPoint(x: centre.x + spread, y: centre.y)),
                             to: (CGPoint(x: centre.x - spread * scale, y: centre.y),
                                  CGPoint(x: centre.x + spread * scale, y: centre.y)),
                             stagger: 0, duration: 0.5)
    }

    /// **A two-finger pan above the dock, whose fingers land in two separate touch events `stagger` seconds
    /// apart — the way a hand lands on glass, and the one shape `pinch`/`rotate` cannot make.** Both
    /// fingers start left of the rail, in the space above the dock (`aboveTheDock`), and travel `delta`
    /// points together.
    func panAboveTheDock(_ app: XCUIApplication, _ canvas: XCUIElement, stagger: TimeInterval,
                         delta: CGVector = CGVector(dx: 60, dy: 40)) throws {
        func end(_ start: CGPoint) -> CGPoint { CGPoint(x: start.x + delta.dx, y: start.y + delta.dy) }
        let start = (a: canvas.coordinate(withNormalizedOffset: aboveTheDock(app, canvas, x: 0.10, y: 0.25)).screenPoint,
                     b: canvas.coordinate(withNormalizedOffset: aboveTheDock(app, canvas, x: 0.22, y: 0.5)).screenPoint)
        try twoFingerGesture(from: start, to: (end(start.a), end(start.b)), stagger: stagger, duration: 0.4, steps: 8)
    }

    /// **One finger drags while a second lands on the glass beside it** — the shape of TODO (146)'s
    /// gesture with a finger standing in for the pen, since XCUITest cannot synthesise a Pencil.
    ///
    /// The dragging finger sits still until 0.3 s and then travels `delta` over `travel` seconds. The
    /// second finger lands (`holdLandsAt`) *after the drag has begun* and *before it has moved* — the
    /// order in which a hand presses to steady a pen — and rests, drifting by `holdDrift` over the same
    /// stretch as a resting finger does and as a two-finger pan is made of, so a drag that is meant to
    /// own the canvas is tested against both. `holding` nil is the control: the same drag with nothing
    /// beside it.
    ///
    /// **The second finger lifts first, and that is not tidiness.** The synthesiser builds each event as
    /// an array of positions indexed by finger, so a finger that lifts while an earlier-indexed one is
    /// still down shifts the survivor into the lifted one's slot, and UIKit sees one touch jump across
    /// the screen rather than one end and one continue — MEASURED here: the dragging touch's location
    /// leapt to the other finger's the moment the first lifted, and the box followed it. A real hand
    /// does not do that; the synthesiser does. For the same reason a finger that lands *before* the
    /// dragging one cannot be driven faithfully — the touch the overlay is handed is replaced mid-drag.
    ///
    /// - Parameters:
    ///   - from: where the dragging finger lands, normalised within `element`.
    ///   - holding: where the second lands, normalised within `element`; nil for none.
    func dragWithAFingerHeldBeside(_ element: XCUIElement, from: CGVector, delta: CGVector,
                                   holding: CGVector?, holdDrift: CGVector = .zero,
                                   holdLandsAt: TimeInterval = 0.1, travel: TimeInterval = 1.0) throws {
        let begin = 0.3, steps = 20
        let origin = element.coordinate(withNormalizedOffset: from).screenPoint
        let dragging = try SynthesizedTouch.path(at: origin, offset: 0)
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            try SynthesizedTouch.move(dragging, to: CGPoint(x: origin.x + delta.dx * t, y: origin.y + delta.dy * t),
                                      at: begin + travel * t)
        }
        let heldLifts = begin + travel + 0.05
        guard let holding else {
            try SynthesizedTouch.lift(dragging, at: heldLifts)
            try SynthesizedTouch.synthesize([dragging], named: "one-finger drag")
            return
        }
        let rest = element.coordinate(withNormalizedOffset: holding).screenPoint
        let held = try SynthesizedTouch.path(at: rest, offset: holdLandsAt)
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            try SynthesizedTouch.move(held, to: CGPoint(x: rest.x + holdDrift.dx * t, y: rest.y + holdDrift.dy * t),
                                      at: begin + travel * t)
        }
        try SynthesizedTouch.lift(held, at: heldLifts)
        try SynthesizedTouch.lift(dragging, at: heldLifts + 0.2)
        try SynthesizedTouch.synthesize([dragging, held], named: "drag with a finger held beside")
    }

    /// **One finger through `points`, in order** — the stroke shapes the public drag cannot make: a pen
    /// that lands and wanders before it commits to a direction, one that lifts with a hook. Each point
    /// is reported `interval` seconds after the one before, by the synthesiser the gestures above use,
    /// and the call returns once the finger has lifted.
    func fingerStroke(through points: [CGPoint], interval: TimeInterval = 0.02) throws {
        guard let first = points.first else { return }
        let path = try SynthesizedTouch.path(at: first, offset: 0)
        for (index, point) in points.enumerated().dropFirst() {
            try SynthesizedTouch.move(path, to: point, at: Double(index) * interval)
        }
        try SynthesizedTouch.lift(path, at: Double(points.count) * interval)
        try SynthesizedTouch.synthesize([path], named: "one-finger stroke")
    }

    /// **Closes whatever presentation is open with a touch that does nothing else** — the middle of the
    /// widest empty stretch of the top toolbar, measured from the bar as it is laid out.
    ///
    /// Every presentation over the canvas is an `AnchoredMenu`, and the touch that closes one goes on
    /// to do what it was aimed at (`AnchoredMenuRouter`), so a tap on a tool button would close the
    /// menu *and* switch the tool, and a tap on the canvas would draw.
    ///
    /// **Measured rather than a fixed point, because "empty" is a fact about the bar's layout and
    /// SwiftUI hit-tests a finger with a radius.** This tapped the window's top centre until TODO
    /// (102)-(104) widened the bar's leading group, which left the Move icon's edge 20 pt from that
    /// point — inside the radius. Every "tap away" became a Move: the lift stood the effect bar down
    /// (`bottomDock`), and the tests calling this lost a swatch or a Close button a mile from the bar.
    /// The clearance assertion turns the next layout change that crowds the gap into a sentence.
    func tapAway(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard let tree = try? app.snapshot() else {
            XCTFail("tapAway: could not snapshot the app to find the top toolbar", file: file, line: line)
            return
        }
        func flattened(_ node: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            [node] + node.children.flatMap(flattened)
        }
        let nodes = flattened(tree)
        guard let anchor = nodes.first(where: { $0.identifier == "toolbar.galleryButton" })?.frame else {
            XCTFail("tapAway: no `toolbar.galleryButton` on screen, so there is no top toolbar to tap", file: file, line: line)
            return
        }
        // Buttons and the scene's name field: the name sits in the middle of the bar, so a gap measured
        // without it would be the one it stands in.
        let rowButtons = nodes
            .filter { ($0.elementType == .button || $0.elementType == .textField)
                && $0.frame.midY > anchor.minY && $0.frame.midY < anchor.maxY }
            .map(\.frame)
            .sorted { $0.minX < $1.minX }
        let gaps = zip(rowButtons, rowButtons.dropFirst()).map { (from: $0.maxX, to: $1.minX) }
        guard let widest = gaps.max(by: { $0.to - $0.from < $1.to - $1.from }) else {
            XCTFail("tapAway: the top toolbar row holds fewer than two buttons", file: file, line: line)
            return
        }
        let clearance = (widest.to - widest.from) / 2
        XCTAssertGreaterThanOrEqual(clearance, Self.tapAwayClearance, """
            tapAway: the top toolbar's widest gap (x \(widest.from)–\(widest.to)) leaves only \(clearance) pt \
            to the nearest icon, inside SwiftUI's touch radius — a tap there would press that icon
            """, file: file, line: line)
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: (widest.from + widest.to) / 2, dy: anchor.midY))
            .tap()
    }

    /// **A menu `CanvasPresentationHost` draws, by the case it carries** — `layerBlendMenu`,
    /// `brushRowMenu`, … (`CanvasPresentation`'s raw values). Queried across every element type,
    /// because what XCUITest calls an accessibility container is SwiftUI's business and not something
    /// a test should be pinning. It is how a test asserts a menu is **on screen** rather than that a
    /// flag is set: a menu whose rows exist but whose card does not has been presented some other way.
    func canvasMenu(_ app: XCUIApplication, _ presentation: String) -> XCUIElement {
        app.descendants(matching: .any)["canvasPresentation.\(presentation)"].firstMatch
    }

    /// How far `tapAway`'s touch must land from any top-toolbar icon: a touch 20 pt off the Move
    /// icon's edge MEASURED as a Move press, so the margin is the 44 pt minimum touch target.
    private static let tapAwayClearance: CGFloat = 44
}

/// The selector-level plumbing behind `twoFingerGesture`. Every object here is created through
/// `alloc`/`init…` read off the runtime and handed back `Unmanaged` so ARC makes no assumption about
/// ownership it cannot see; the few objects it leaks per gesture are a test process's to lose.
private enum SynthesizedTouch {
    static func path(at point: CGPoint, offset: Double) throws -> AnyObject {
        let object = try allocate("XCPointerEventPath")
        let selector = NSSelectorFromString("initForTouchAtPoint:offset:")
        typealias Init = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Unmanaged<AnyObject>
        return unsafeBitCast(try implementation(object, selector), to: Init.self)(object, selector, point, offset)
            .takeUnretainedValue()
    }

    static func move(_ path: AnyObject, to point: CGPoint, at offset: Double) throws {
        let selector = NSSelectorFromString("moveToPoint:atOffset:")
        typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
        unsafeBitCast(try implementation(path, selector), to: Move.self)(path, selector, point, offset)
    }

    static func lift(_ path: AnyObject, at offset: Double) throws {
        let selector = NSSelectorFromString("liftUpAtOffset:")
        typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
        unsafeBitCast(try implementation(path, selector), to: Lift.self)(path, selector, offset)
    }

    /// One record carrying every path, synthesised synchronously: the call returns once the last
    /// touch has lifted, so the caller reads the app's state after the whole gesture.
    static func synthesize(_ paths: [AnyObject], named name: String) throws {
        let record = try allocate("XCSynthesizedEventRecord")
        let initSelector = NSSelectorFromString("initWithName:interfaceOrientation:")
        typealias Init = @convention(c) (AnyObject, Selector, NSString, Int) -> Unmanaged<AnyObject>
        let orientation = XCUIDevice.shared.orientation.isLandscape
            ? (XCUIDevice.shared.orientation == .landscapeLeft ? 3 : 4) : 1
        let made = unsafeBitCast(try implementation(record, initSelector), to: Init.self)(
            record, initSelector, name as NSString, orientation).takeUnretainedValue()

        let addSelector = NSSelectorFromString("addPointerEventPath:")
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let add = unsafeBitCast(try implementation(made, addSelector), to: Add.self)
        for path in paths { add(made, addSelector, path) }

        let runSelector = NSSelectorFromString("synthesizeWithError:")
        typealias Run = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Unmanaged<NSError>?>?) -> Bool
        var error: Unmanaged<NSError>?
        guard unsafeBitCast(try implementation(made, runSelector), to: Run.self)(made, runSelector, &error) else {
            XCTFail("the event synthesiser refused the gesture: \(error?.takeUnretainedValue().localizedDescription ?? "no error given")")
            return
        }
    }

    private static func allocate(_ className: String) throws -> AnyObject {
        guard let cls = NSClassFromString(className),
              let method = class_getClassMethod(cls, NSSelectorFromString("alloc")) else {
            throw XCTSkip("\(className) is not available in this XCUIAutomation")
        }
        typealias Alloc = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
        return unsafeBitCast(method_getImplementation(method), to: Alloc.self)(cls, NSSelectorFromString("alloc"))
            .takeUnretainedValue()
    }

    private static func implementation(_ object: AnyObject, _ selector: Selector) throws -> IMP {
        guard let cls = object_getClass(object), class_respondsToSelector(cls, selector),
              let imp = class_getMethodImplementation(cls, selector) else {
            throw XCTSkip("\(String(describing: object_getClass(object))) does not answer \(selector)")
        }
        return imp
    }
}
