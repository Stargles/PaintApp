import XCTest

/// **From a fresh document: draw two lines, lasso one, drag the Select panel's Size slider — and what
/// is *drawn* changes while the finger is still down; lift, undo once, and the line is drawn back at
/// its old width with the other line untouched throughout.** TODO (42)'s cold-start reachability
/// test, `RewriteUndoFootprintUITests`' shape: every step below asserts pixels read off the screen,
/// never a stored value.
///
/// The second test is the colour arm: the swatch opens the app's one colour picker **on the lassoed
/// line's own colour** rather than the palette's, the line follows the picker while it is still up,
/// and dismissing the picker is the one undo step.
///
/// **What the artist does next, at every step, is in the comments** — CLAUDE.md's fourth rule. No
/// step's answer is "read the source": the band appears the moment a loop is drawn, the controls
/// read their current values off the loop, and dragging one is the whole gesture.
final class SelectionEditUITests: PaintUITestCase {

    // MARK: - Size, live

    func testDraggingTheSizeSliderOverALassoedLineChangesWhatIsDrawnLiveAndUndoPutsItBack() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                     dy: paper.minY + (paper.maxY - paper.minY) * dy)
        }

        // 1. Red, thin. What the artist does next: pick a colour, pick a size, draw two lines.
        //    The brush editor's slider runs 1…200, so 0.05 is a line of ten-odd points — thin
        //    enough that the Select panel's own 1…50 slider has room to make it fat.
        setBrushColour(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.05)
        let l1 = (from: at(0.12, 0.22), to: at(0.38, 0.22))
        let l2 = (from: at(0.60, 0.22), to: at(0.86, 0.22))
        drawLine(on: canvas, from: l1.from, to: l1.to)
        drawLine(on: canvas, from: l2.from, to: l2.to)
        let l1Mid = at(0.25, 0.22), l2Mid = at(0.73, 0.22)
        // A probe a little above each line's centre — paper at the drawn width, ink once the line is
        // fat. 0.008 of the paper's height is ~8 screen points on this simulator, where the canvas
        // is shown at half scale; the drawn line is ~6 screen points wide (a 3-point radius) and
        // the drag takes it to ~47 canvas points (a 12-point radius).
        let l1Above = at(0.25, 0.22 - 0.008), l2Above = at(0.73, 0.22 - 0.008)
        XCTAssertTrue(waitUntil(canvas, l1Mid, isRed), "PREMISE: the first red line is on screen")
        XCTAssertTrue(waitUntil(canvas, l2Mid, isRed), "PREMISE: the second red line is on screen")
        XCTAssertTrue(isPaper(rgba(canvas, l1Above)), "PREMISE: just above the first line is paper at the drawn width")
        XCTAssertTrue(isPaper(rgba(canvas, l2Above)), "PREMISE: just above the second line is paper")

        // 2. Lasso the first line. What the artist does next: tap Select, tap Rectangle, drag a loop.
        //    The band appears with the loop: Colour, Brush, Size, Opacity, each reading the line.
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the Select panel offers Rectangle")
        rectangle.tap()
        XCTAssertFalse(app.sliders["selectPanel.sizeSlider"].exists,
                       "before a loop is drawn there is nothing to edit, and the band is not up")
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        let slider = app.sliders["selectPanel.sizeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "drawing a loop raises the Size slider")
        XCTAssertTrue(slider.isEnabled, "the loop caught a stroke on a vector layer, so Size is live")
        let readoutBefore = slider.value as? String ?? ""
        XCTAssertTrue(readoutBefore.hasSuffix(" pt"), "the slider reads the line's own width: \"\(readoutBefore)\"")
        XCTAssertFalse(readoutBefore.contains("Mixed"), "one line, one width — not Mixed")
        let sizeBefore = Double(readoutBefore.replacingOccurrences(of: " pt", with: "")) ?? 0
        XCTAssertTrue(sizeBefore > 0 && sizeBefore < 25, "PREMISE: the line is thin (\(readoutBefore)), so the drag has room")
        let swatch = app.buttons["selectPanel.colourSwatch"]
        XCTAssertTrue(swatch.exists, "the band has the colour swatch")
        XCTAssertTrue((swatch.value as? String ?? "").uppercased().hasPrefix("FF0000"),
                      "the swatch shows the line's own red, not the palette's: \(swatch.value ?? "nil")")
        attach(app, "1-loop-drawn-band-reads-the-line")

        // 3. Drag Size up and HOLD, sampling the screen from another thread while the finger is
        //    still down. What the artist does next: put a finger on the Size slider and drag right.
        let fraction = max(0, min(1, (sizeBefore - 1) / 49))
        let track = slider.frame
        let thumbInset: CGFloat = 14
        let thumbX = track.minX + thumbInset + CGFloat(fraction) * (track.width - 2 * thumbInset)
        let thumb = slider.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: thumbX - track.minX, dy: track.height / 2))
        let target = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))

        let canvasFrame = canvas.frame
        let probeAbove = CGPoint(x: canvasFrame.minX + canvasFrame.width * l1Above.dx,
                                 y: canvasFrame.minY + canvasFrame.height * l1Above.dy)
        let probeOther = CGPoint(x: canvasFrame.minX + canvasFrame.width * l2Above.dx,
                                 y: canvasFrame.minY + canvasFrame.height * l2Above.dy)
        let sampler = MidGestureSampler(points: [probeAbove, probeOther])
        sampler.start()
        thumb.press(forDuration: 0.4, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 5.0)
        let returned = CFAbsoluteTimeGetCurrent()
        let taken = sampler.stop()
        // **Only samples whose screenshot was complete two seconds before `press` returned count as
        // mid-drag.** The lift is the commit, whose render lands within milliseconds, and `press`
        // returns well *after* the lift — MEASURED at ~0.6 s on this simulator, by a mutation that
        // deferred every tick to the commit and still passed this test with a half-second margin:
        // its timeline read paper at −1.00 s and red at −0.53 s. Two seconds off a five-second hold
        // leaves three seconds of samples that can only have been taken with the finger down.
        let samples = taken.filter { $0.finished < returned - 2.0 }.map(\.pixels)
        let timeline = taken.map { String(format: "%+.2fs above=%@ other=%@", $0.finished - returned,
                                          $0.pixels[0].map { "\($0)" } ?? "nil", $0.pixels[1].map { "\($0)" } ?? "nil") }
        let trace = XCTAttachment(string: timeline.joined(separator: "\n"))
        trace.name = "mid-drag samples, seconds relative to press returning"
        trace.lifetime = .keepAlways
        add(trace)
        let readoutAfter = slider.value as? String ?? ""
        XCTAssertNotEqual(readoutAfter, readoutBefore, "the drag did not move the slider — the thumb was not where the test grabbed")
        XCTAssertTrue(samples.count > 0, "the screen could not be sampled while the finger was down "
                      + "(\(taken.count) samples, none finished two seconds before the press returned)")
        XCTAssertTrue(samples.contains { isRed($0[0]) },
                      "while the finger was still on the slider, the pixel above the lassoed line never "
                      + "turned red — the size change did not reach the screen before lift "
                      + "(\(samples.count) mid-drag samples)")
        XCTAssertTrue(samples.allSatisfy { isPaper($0[1]) },
                      "the line outside the loop grew while the finger was down")
        attach(app, "2-after-lift-first-line-fat")

        // 4. After lift: the first line is fat, the second is not.
        XCTAssertTrue(waitUntil(canvas, l1Above, isRed), "after lift the first line is drawn wider")
        XCTAssertTrue(isRed(rgba(canvas, l1Mid)), "and still red at its centre")
        XCTAssertTrue(isPaper(rgba(canvas, l2Above)), "the second line kept its width")
        XCTAssertTrue(isRed(rgba(canvas, l2Mid)), "and its ink")

        // 5. Undo once. What the artist does next: press undo — the whole drag is one step.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(waitUntil(canvas, l1Above, isPaper),
                      "one undo did not draw the first line back at its old width — the drag was more "
                      + "than one step, or the repair missed the rectangle")
        XCTAssertTrue(isRed(rgba(canvas, l1Mid)), "the line is still there, at its old width")
        XCTAssertTrue(isPaper(rgba(canvas, l2Above)) && isRed(rgba(canvas, l2Mid)),
                      "the second line never changed")
        XCTAssertFalse(undo.isEnabled && app.buttons["sideToolbar.redoButton"].isEnabled == false,
                       "sanity: undo left a step to redo")
        attach(app, "3-undone-first-line-thin-again")
    }

    // MARK: - Colour, from the line's own colour

    func testTheColourSwatchOpensThePickerOnTheLinesOwnColourAndTheLineFollowsItLive() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                     dy: paper.minY + (paper.maxY - paper.minY) * dy)
        }

        // 1. A red line, and the palette left on red — so a picker that opened on the palette's
        //    colour and one that opened on the line's would agree, which is why the palette is then
        //    moved to green before the loop: the swatch has to show red *against* a green palette.
        setBrushColour(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.6)
        drawLine(on: canvas, from: at(0.12, 0.22), to: at(0.38, 0.22))
        drawLine(on: canvas, from: at(0.60, 0.22), to: at(0.86, 0.22))
        let l1Mid = at(0.25, 0.22), l2Mid = at(0.73, 0.22)
        XCTAssertTrue(waitUntil(canvas, l1Mid, isRed), "PREMISE: the first red line is on screen")
        XCTAssertTrue(waitUntil(canvas, l2Mid, isRed), "PREMISE: the second red line is on screen")
        setBrushColour(app, hex: "00FF00")

        // 2. Lasso the first line and tap the swatch. What the artist does next: Select, Rectangle,
        //    loop, tap the swatch — the picker opens on red, the line's colour, not the palette's green.
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        let swatch = app.buttons["selectPanel.colourSwatch"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the loop raised the colour swatch")
        XCTAssertTrue((swatch.value as? String ?? "").uppercased().hasPrefix("FF0000"),
                      "the swatch is the line's red against a green palette: \(swatch.value ?? "nil")")
        swatch.tap()
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5), "the swatch opens the app's colour picker")
        XCTAssertEqual((hexField.value as? String ?? "").uppercased(), "FF0000",
                       "the picker opened on the line's own colour — \"defaulting to the current color\"")
        XCTAssertFalse(app.sliders["colorPanel.opacitySlider"].exists,
                       "no alpha slider: only the hue travels, and Opacity has its own control in the band")
        attach(app, "1-picker-open-on-the-lines-red")

        // 3. Type blue while the picker is still up: the line follows it live.
        setHexField(app, hexField, to: "0000FF")
        XCTAssertTrue(waitUntil(canvas, l1Mid, isBlue),
                      "with the picker still open the lassoed line did not turn blue — the colour is not live")
        XCTAssertTrue(isRed(rgba(canvas, l2Mid)), "the line outside the loop stayed red")
        XCTAssertTrue(hexField.exists, "PREMISE: the picker is still up while the line changed")
        attach(app, "2-line-blue-while-the-picker-is-still-up")

        // 4. Dismiss the picker — a tap on the band's Size label, outside the popover — and that is
        //    the one undo step. What the artist does next: tap away, press undo.
        app.staticTexts["Size"].firstMatch.tap()
        XCTAssertTrue(hexField.waitForNonExistence(timeout: 5), "tapping outside closes the picker")
        XCTAssertTrue(isBlue(rgba(canvas, l1Mid)), "the line keeps the picked colour after the picker closes")
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(waitUntil(canvas, l1Mid, isRed), "one undo puts the line's red back")
        XCTAssertTrue(isRed(rgba(canvas, l2Mid)), "and the other line never moved")
        attach(app, "3-undone-red-again")
    }

    // MARK: - Sampling the screen while a gesture is in flight

    /// Reads screen pixels from a background thread while the test's main thread is blocked inside a
    /// synchronous `press(forDuration:thenDragTo:…)`. `XCUIScreen.main.screenshot()` is what makes
    /// that possible: it asks the device for its framebuffer rather than resolving any element, so it
    /// does not contend with the gesture being synthesised. Points are in screen coordinates.
    private final class MidGestureSampler {
        typealias Sample = (finished: CFAbsoluteTime, pixels: [RGBA?])
        private let points: [CGPoint]
        private var stopped = false
        private var samples: [Sample] = []
        private let lock = NSLock()
        private let group = DispatchGroup()

        init(points: [CGPoint]) { self.points = points }

        func start() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { group.leave() }
                while true {
                    lock.lock(); let done = stopped; lock.unlock()
                    if done { return }
                    let image = XCUIScreen.main.screenshot().image
                    let finished = CFAbsoluteTimeGetCurrent()
                    let read = points.map { Self.pixel(in: image, at: $0) }
                    lock.lock(); samples.append((finished, read)); lock.unlock()
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }

        func stop() -> [Sample] {
            lock.lock(); stopped = true; lock.unlock()
            group.wait()
            return samples
        }

        private static func pixel(in image: UIImage, at point: CGPoint) -> RGBA? {
            guard let cg = image.cgImage else { return nil }
            let scale = image.scale
            let x = Int(point.x * scale), y = Int(point.y * scale)
            guard x >= 0, y >= 0, x < cg.width, y < cg.height else { return nil }
            var buffer = [UInt8](repeating: 0, count: 4)
            guard let context = CGContext(data: &buffer, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return (buffer[0], buffer[1], buffer[2], buffer[3])
        }
    }

    // MARK: - Driving the colour swatch

    private func setBrushColour(_ app: XCUIApplication, hex: String) {
        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5), "the toolbar has a colour swatch")
        colorButton.tap()
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5), "the colour panel has a hex field")
        setHexField(app, hexField, to: hex)
        colorButton.tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForNonExistence(timeout: 5),
                      "the colour panel must be closed before the canvas is touched")
    }

    // MARK: - Reading the canvas

    private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    private func rgba(_ canvas: XCUIElement, _ point: CGVector) -> RGBA? {
        rgbaPixel(of: canvas, dx: point.dx, dy: point.dy)
    }

    private func isRed(_ p: RGBA?) -> Bool { p.map { $0.r > 150 && $0.g < 100 && $0.b < 100 } ?? false }
    private func isBlue(_ p: RGBA?) -> Bool { p.map { $0.b > 150 && $0.r < 100 && $0.g < 100 } ?? false }
    private func isPaper(_ p: RGBA?) -> Bool { p.map { $0.r > 235 && $0.g > 235 && $0.b > 235 } ?? false }

    private func waitUntil(_ canvas: XCUIElement, _ point: CGVector, _ test: (RGBA?) -> Bool,
                           timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if test(rgba(canvas, point)) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
