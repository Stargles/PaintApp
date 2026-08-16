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

    /// Gallery -> New Canvas -> Create Canvas (default 2048x2048), landing in the editor.
    /// Also serves as the regression test for the launch-time freeze: if that bug ever
    /// comes back, `waitForExistence` below times out and the test fails.
    @discardableResult
    func launchIntoEditor(_ app: XCUIApplication) -> Bool {
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

    /// Drags a straight line on the canvas between two normalized offsets of `canvas.host` — used to
    /// draw a rectangle selection (Select tool, Rectangle mode) or to draw a stroke.
    func dragOnCanvas(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: from)
        let end = canvas.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
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

    /// Rasterizes `element`'s own on-screen content (not the whole app screenshot) into a flat RGBA8
    /// buffer, top-left origin, so individual pixels can be inspected by fraction-of-element position.
    /// Goes through an explicit CGContext (rather than trusting the screenshot's native byte order) for
    /// the same reason FloodFillEngine does: it removes any ambiguity about pixel format.
    func rgbaPixel(of element: XCUIElement, dx: Double, dy: Double) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
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

    func isWhitish(_ pixel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)?) -> Bool {
        guard let pixel else { return false }
        return pixel.r > 240 && pixel.g > 240 && pixel.b > 240
    }

    /// The fill runs off-main-thread (see CanvasManager.beginInteractiveFill), so polls the given point on
    /// `element` until it's no longer whitish (i.e. the fill landed) or `timeout` elapses.
    @discardableResult
    func waitUntilFilled(_ element: XCUIElement, dx: Double, dy: Double, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isWhitish(rgbaPixel(of: element, dx: dx, dy: dy)) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// The canvas is always rendered as a square (2048x2048 by default) scaled to fit and centered
    /// within `canvas.host`'s own element frame. On this iPad simulator that frame is *not* square
    /// (portrait-ish, taller than wide), so the canvas content is vertically letterboxed: there's a
    /// margin above and below the actual square canvas that belongs to the view's own background,
    /// not to any layer's content. A normalized probe point like (0.05, 0.05) can land in that
    /// margin instead of on real canvas content — confirmed empirically (see BUGS.md's fill
    /// containment / letterbox investigation): on a completely blank, freshly-created canvas with
    /// nothing drawn or filled, (0.05,0.05) already reads solid black, and the margin only clears
    /// past roughly dx/dy ~0.19 on this device's frame proportions. Returns the normalized bounding
    /// box of the actual canvas content within `canvas`'s frame, so tests can build "definitely on
    /// real content" probe points instead of guessing a magic constant that happens to work for one
    /// specific frame size.
    func visibleCanvasBounds(_ canvas: XCUIElement) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let frame = canvas.frame
        guard frame.width > 0, frame.height > 0 else { return (0, 1, 0, 1) }
        if frame.width < frame.height {
            let marginFrac = Double((frame.height - frame.width) / (2 * frame.height))
            return (0, 1, marginFrac, 1 - marginFrac)
        } else if frame.height < frame.width {
            let marginFrac = Double((frame.width - frame.height) / (2 * frame.width))
            return (marginFrac, 1 - marginFrac, 0, 1)
        }
        return (0, 1, 0, 1)
    }

    /// A point safely inside the visible (non-letterboxed) canvas content, inset a further 10% of
    /// that visible region from the top-left corner — comfortably away from both the letterbox
    /// margin and (for this test suite's shapes, all drawn no closer than 30% from any edge) any
    /// drawn lineart, while still being far from the canvas center.
    func safeOutsideCornerPoint(_ canvas: XCUIElement) -> CGVector {
        let bounds = visibleCanvasBounds(canvas)
        let dx = bounds.minX + (bounds.maxX - bounds.minX) * 0.1
        let dy = bounds.minY + (bounds.maxY - bounds.minY) * 0.1
        return CGVector(dx: dx, dy: dy)
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
    /// coordinates normalized within `canvas.host`, chosen to sit inside the visible, non-letterboxed
    /// canvas region), fills at `insideProbe`, and asserts the interior fills while `outsideProbe`
    /// (a point well outside the square, still on real canvas content) stays blank.
    func runOffCenterFillContainmentTest(
        squareRect: (minX: Double, maxX: Double, minY: Double, maxY: Double),
        insideProbe: (dx: Double, dy: Double),
        outsideProbe: (dx: Double, dy: Double)
    ) throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let x0 = squareRect.minX, x1 = squareRect.maxX, y0 = squareRect.minY, y1 = squareRect.maxY
        drawLine(on: canvas, from: CGVector(dx: x0, dy: y0), to: CGVector(dx: x1, dy: y0)) // top
        drawLine(on: canvas, from: CGVector(dx: x1, dy: y0), to: CGVector(dx: x1, dy: y1)) // right
        drawLine(on: canvas, from: CGVector(dx: x1, dy: y1), to: CGVector(dx: x0, dy: y1)) // bottom
        drawLine(on: canvas, from: CGVector(dx: x0, dy: y1), to: CGVector(dx: x0, dy: y0)) // left

        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: insideProbe.dx, dy: insideProbe.dy)), "Square's interior should still be blank paper before filling")

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // First tap selects the fill tool; its menu stays closed.

        canvas.coordinate(withNormalizedOffset: CGVector(dx: insideProbe.dx, dy: insideProbe.dy)).tap()

        XCTAssertTrue(waitUntilFilled(canvas, dx: insideProbe.dx, dy: insideProbe.dy), "Tapping inside the off-center square should color its interior")

        // The discriminator: a point in the opposite quadrant, far outside the drawn square. If the fill
        // read the reference mirrored, the seed landed in open space and the fill leaked out here.
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: outsideProbe.dx, dy: outsideProbe.dy)), "Fill of an off-center square must stay contained — leaking here means the reference was rasterized mirrored")
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
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isWhitish(rgbaPixel(of: element, dx: dx, dy: dy)) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
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

    func brushIsSelected(_ app: XCUIApplication) -> Bool {
        app.buttons["toolbar.brushButton"].isSelected
    }

    func openLayerPanel(_ app: XCUIApplication) {
        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()
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
        // (`LayerPanel.valueBlendModeRow`), which is the owner's merge of the old Mode row into this
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
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.0)
        let item = app.buttons["layerPanel.addValueButton"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// Returns to the gallery (saving the project) and waits for its tile to appear.
    @discardableResult
    func saveEditorAndReturnToGallery(_ app: XCUIApplication) -> XCUIElement {
        let galleryButton = app.buttons["square.grid.2x2"]
        XCTAssertTrue(galleryButton.waitForExistence(timeout: 5))
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

    /// Draws a stroke and keeps the finger down at the end of it, which is the smart-shape gesture:
    /// the hold timer fires ~0.8s after the finger stops, the freehand stroke is replaced by the
    /// detected shape, and lifting leaves it in the adjustable state.
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

}
