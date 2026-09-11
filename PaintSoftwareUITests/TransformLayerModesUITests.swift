import XCTest

/// **Can an artist reach Parallax and Rotate from a fresh document, and does the canvas show what
/// the mode promises?** — TRANSFORM_LAYER.md §5.2 and §5.3, §8's rows 2 and 3, driven the way the
/// artist drives them with no prior state: `+` → Transform Layer → its row → Mode → the mode → the
/// mode's own controls → the box or the playhead → the picture.
///
/// `TransformLayerModesLogicTests` owns the arithmetic. What it cannot say, and what this file is for:
///
///  * that **the mode is reachable at all** — the picker lists it, picking it puts the mode's rows on
///    the panel (the item list with its 100/75/50/25, the speed field with its frames-per-turn line),
///    and the Move row still raises the box;
///  * that **what is drawn is the mode**: four bands of ink on four layers move 100/75/50/25 of the
///    box's drag, measured off the canvas; a bar right of centre is drawn *below* centre six frames
///    into a 15°/frame spin — turned about the box's centre, not slid.
///
/// The assertions are on screenshots of `canvas.host` and on the panel's exposed values, never on
/// anything stored. A small class on purpose (CLAUDE.md's cost model: per test *class*).
final class TransformLayerModesUITests: PaintUITestCase {

    // MARK: - Reading the canvas

    /// The canvas' pixels as flat RGBA, top-left origin, with its size — one capture, every probe.
    private func canvasPixels(_ canvas: XCUIElement) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = canvas.screenshot().image.cgImage else { return nil }
        let w = cg.width, h = cg.height, bpr = w * 4
        var buf = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (buf, w, h)
    }

    /// The centre of gravity of the ink inside `region` (normalised to the host), as a normalised
    /// point — or nil when the region holds no ink. `region` keeps the probe off the letterbox
    /// margins, which read as black on this device (`visibleCanvasBounds` says why).
    private func inkCentroid(_ pixels: (bytes: [UInt8], width: Int, height: Int),
                             in region: (minX: Double, maxX: Double, minY: Double, maxY: Double)) -> CGPoint? {
        let (buf, w, h) = pixels
        let x0 = max(0, Int(region.minX * Double(w))), x1 = min(w - 1, Int(region.maxX * Double(w)))
        let y0 = max(0, Int(region.minY * Double(h))), y1 = min(h - 1, Int(region.maxY * Double(h)))
        guard x1 > x0, y1 > y0 else { return nil }
        var sx = 0.0, sy = 0.0, n = 0.0
        for y in y0...y1 {
            for x in x0...x1 {
                let o = y * w * 4 + x * 4
                if Int(buf[o]) + Int(buf[o + 1]) + Int(buf[o + 2]) < 400 { sx += Double(x); sy += Double(y); n += 1 }
            }
        }
        guard n > 0 else { return nil }
        return CGPoint(x: sx / n / Double(w), y: sy / n / Double(h))
    }

    /// The canvas's own centre and inset bounds in host-normalised coordinates — the box's centre,
    /// since a transform layer's box is the canvas.
    private func canvasFrame(_ canvas: XCUIElement) -> (centre: CGPoint, inset: (minX: Double, maxX: Double, minY: Double, maxY: Double)) {
        let b = visibleCanvasBounds(canvas)
        let pad = 0.03
        return (CGPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2),
                (b.minX + pad, b.maxX - pad, b.minY + pad, b.maxY - pad))
    }

    /// A short vertical band of ink at `x`, `y` — seven passes so it is a band rather than a hairline
    /// the probe steps over.
    private func drawBand(on canvas: XCUIElement, x: Double, y: Double, halfHeight: Double = 0.03) {
        for i in 0..<7 {
            let px = x + Double(i) * 0.004
            drawLine(on: canvas, from: CGVector(dx: px, dy: y - halfHeight), to: CGVector(dx: px, dy: y + halfHeight))
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Opens the options of the layer at `index` (the row must be the active one) and picks `mode`
    /// from its Mode picker. Reads the picker's value back, which is the exposed operand.
    private func pickMode(_ app: XCUIApplication, layerIndex: Int, mode: String) {
        let row = app.staticTexts["layerPanel.row.\(layerIndex)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The transform layer's row is on the rail")
        row.tap()
        let modeButton = app.buttons["layerOptions.transformModeButton"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5), "A transform layer's options open on its mode picker")
        XCTAssertEqual(modeButton.value as? String, "move", "…in Move to begin with")
        modeButton.tap()
        let item = app.buttons["layerOptions.transformMode.\(mode)"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The picker lists \(mode)")
        XCTAssertFalse(app.buttons["layerOptions.transformMode.shake"].exists,
                       "…and not a mode that has not shipped — a row that does nothing is a refusal with no notice")
        item.tap()
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        XCTAssertEqual(modeButton.value as? String, mode, "the pick reached the model and the row reports it")
    }

    /// Puts the playhead on `frame` (1-based, as the label prints it) by tapping the transform
    /// layer's bar; a synthetic tap lands a frame off now and then, so it nudges until the label agrees.
    private func scrub(_ app: XCUIApplication, toFrame frame: Int, total: Int) {
        let cel = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "The transform layer's bar is on the timeline")
        var dx = (Double(frame) - 0.5) / Double(total)
        for _ in 0..<6 {
            cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            guard let read = readFrameLabel(app) else { continue }
            if read.current == frame { return }
            dx += read.current < frame ? 0.5 / Double(total) : -0.5 / Double(total)
        }
        XCTFail("Could not put the playhead on frame \(frame): label reads \(String(describing: readFrameLabel(app)))")
    }

    // MARK: - Parallax

    /// **Four drawings, a transform layer above, Mode → Parallax, drag the box, and the four bands
    /// move 100/75/50/25 of the drag** — the owner's own numbers, measured off the canvas. The item
    /// list is read first (the exposed operand: four items at their defaults, top to bottom), then
    /// the box is dragged from the Move row, and each band's ink is located before and after.
    func testParallaxMovesFourLayersByTheirSharesOfTheBoxDrag() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let frame = canvasFrame(canvas)

        // Four bands on four layers, bottom to top: the born layer, then three more. Each band sits
        // at its own row so the probe can tell them apart after they move by different amounts.
        let rows = [frame.centre.y - 0.18, frame.centre.y - 0.06, frame.centre.y + 0.06, frame.centre.y + 0.18]
        let x = 0.30
        drawBand(on: canvas, x: x, y: rows[0])
        for row in rows.dropFirst() {
            openLayerPanel(app)
            addVectorLayerFromOpenPanel(app)
            app.buttons["toolbar.layersButton"].tap()
            drawBand(on: canvas, x: x, y: row)
        }
        guard let before = canvasPixels(canvas) else { return XCTFail("Could not read the canvas") }
        let regions = rows.map { (minX: frame.inset.minX, maxX: frame.inset.maxX, minY: $0 - 0.04, maxY: $0 + 0.04) }
        let startColumns = regions.map { inkCentroid(before, in: $0)?.x }
        XCTAssertEqual(startColumns.compactMap { $0 }.count, 4, "Sanity: all four bands landed, read \(startColumns)")

        // The layer itself, from the + menu, then its options: Mode → Parallax.
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        pickMode(app, layerIndex: 4, mode: "parallax")

        // **What the panel exposes**: the four items at their positional defaults, nearest first.
        let list = app.otherElements["layerOptions.parallaxItems"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Parallax puts the item list on the panel")
        let listed = (list.value as? String ?? "").split(separator: "|").map(String.init)
        XCTAssertEqual(listed.count, 4, "four items beneath the layer, read \(listed)")
        XCTAssertEqual(listed.map { $0.split(separator: "=").last.map(String.init) ?? "" }, ["100", "75", "50", "25"],
                       "the owner's defaults, top to bottom, none of them typed: \(listed)")
        XCTAssertTrue(app.sliders["layerOptions.parallaxItem.3.slider"].exists, "…each with a slider of its own")
        attach(app, "1-parallax-item-list")

        // The verb: the Move row raises the box, and the drag moves every band live.
        let moveRow = app.buttons["layerOptions.transformMove"]
        XCTAssertTrue(moveRow.waitForExistence(timeout: 5), "The Move row is still the way to the box")
        moveRow.tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move raised the box")
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: frame.centre.y))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: frame.centre.y))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        app.buttons["moveBar.doneButton"].tap()
        app.buttons["toolbar.layersButton"].tap()   // the rail down, so the probe sees only canvas
        attach(app, "2-parallax-after-the-drag")

        // **What is drawn**: each band moved by its share of what the top band moved.
        guard let after = canvasPixels(canvas) else { return XCTFail("Could not read the canvas after the drag") }
        var shifts: [Double] = []
        for (i, region) in regions.enumerated() {
            guard let was = startColumns[i], let now = inkCentroid(after, in: region)?.x else {
                return XCTFail("Band \(i) was lost after the drag")
            }
            shifts.append(now - was)
        }
        let top = shifts[3]
        XCTAssertGreaterThan(top, 0.08, "the nearest band followed the box a good way: shifts \(shifts)")
        XCTAssertEqual(shifts[2] / top, 0.75, accuracy: 0.08, "the second band moved three quarters: \(shifts)")
        XCTAssertEqual(shifts[1] / top, 0.50, accuracy: 0.08, "the third band moved half: \(shifts)")
        XCTAssertEqual(shifts[0] / top, 0.25, accuracy: 0.08, "the back band moved a quarter: \(shifts)")
    }

    // MARK: - Rotate

    /// **A bar right of centre, a transform layer above, Mode → Rotate, type 15, scrub six frames in,
    /// and the bar is drawn below centre** — turned 90° about the box's centre, not slid. The speed
    /// field is the exposed operand (the readout and the frames-per-turn line echo it), the playhead
    /// is the timeline's own, and the picture is measured off the canvas at the first frame (nothing
    /// turned) and at the seventh (a quarter turn).
    func testRotateTurnsTheInkAQuarterTurnSixFramesIntoTheBar() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let frame = canvasFrame(canvas)
        guard let total = readFrameLabel(app)?.total else { return XCTFail("No frame label") }

        // A band a fixed distance right of the centre, on the centre row.
        let reach = 0.16
        drawBand(on: canvas, x: frame.centre.x + reach, y: frame.centre.y, halfHeight: 0.04)
        guard let rest = canvasPixels(canvas), let restCentroid = inkCentroid(rest, in: frame.inset) else {
            return XCTFail("The band did not land")
        }
        let w = Double(rest.width), h = Double(rest.height)
        // In pixels, where the ink sits relative to the box's centre — the operand the turn acts on.
        let dxPx = (restCentroid.x - frame.centre.x) * w
        let dyPx = (restCentroid.y - frame.centre.y) * h
        XCTAssertGreaterThan(dxPx, 0.08 * w, "Sanity: the band is right of centre")
        XCTAssertEqual(abs(dyPx), 0, accuracy: 0.03 * h, "Sanity: …on the centre row")

        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        pickMode(app, layerIndex: 1, mode: "rotate")

        // **The speed, typed** — the owner's "you input the rotation speed". 15°/frame is a quarter
        // turn in six frames and, at the document's fps, one turn every 24 frames.
        let field = app.textFields["layerOptions.rotateSpeed.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Rotate puts the speed field on the panel")
        field.tap()
        field.typeText("15\n")
        let readout = app.staticTexts["layerOptions.rotateSpeedReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertTrue(readout.label.hasPrefix("15.0°"), "the readout echoes the typed speed: \(readout.label)")
        let caption = app.staticTexts["layerOptions.rotateSpeedCaption"]
        XCTAssertTrue(caption.label.contains("24.0 frames"), "…and says how long one turn takes: \(caption.label)")
        attach(app, "1-rotate-speed-typed")
        app.buttons["toolbar.layersButton"].tap()   // the rail down

        // At the bar's first frame nothing has turned yet.
        scrub(app, toFrame: 1, total: total)
        guard let first = canvasPixels(canvas), let atFirst = inkCentroid(first, in: frame.inset) else {
            return XCTFail("The band vanished at the first frame")
        }
        XCTAssertEqual(atFirst.x, restCentroid.x, accuracy: 0.02, "frame 1: the band is where it was drawn")
        XCTAssertEqual(atFirst.y, restCentroid.y, accuracy: 0.02)

        // Six frames in: a quarter turn clockwise puts what was to the right of centre below it.
        scrub(app, toFrame: 7, total: total)
        guard let turned = canvasPixels(canvas), let atSeventh = inkCentroid(turned, in: frame.inset) else {
            return XCTFail("The band vanished at the seventh frame")
        }
        attach(app, "2-rotate-six-frames-in")
        let expectedX = frame.centre.x + (-dyPx) / w
        let expectedY = frame.centre.y + dxPx / h
        XCTAssertEqual(atSeventh.x, expectedX, accuracy: 0.03,
                       "frame 7: the band is on the centre column — turned about the box's centre, not slid")
        XCTAssertEqual(atSeventh.y, expectedY, accuracy: 0.03,
                       "frame 7: …and below it, as far below as it was to the right")
    }
}
