import XCTest

/// **Can an artist reach Parallax, Rotate, Shake and Repeat from a fresh document, and does the
/// canvas show what the mode promises?** — TRANSFORM_LAYER.md §5.2–§5.5, §8's rows 2–5, driven the
/// way the artist drives them with no prior state: `+` → Transform Layer → its row → Mode → the mode
/// → the mode's own controls → the box or the playhead → the picture.
///
/// `TransformLayerModesLogicTests` owns the arithmetic. What it cannot say, and what this file is for:
///
///  * that **the mode is reachable at all** — the picker lists it, picking it puts the mode's rows on
///    the panel (the item list with its 100/75/50/25, the speed field with its frames-per-turn line),
///    and the Move row still raises the box;
///  * that **what is drawn is the mode**: four bands of ink on four layers move 100/75/50/25 of the
///    box's drag, measured off the canvas; a bar right of centre is drawn *below* centre six frames
///    into a 15°/frame spin — turned about the box's centre, not slid; a band under a Shake layer
///    is drawn somewhere else on the first frames of the bar, the same somewhere else every time the
///    playhead comes back (ruling 9's determinism, off the screen), somewhere new after Re-roll, and
///    back where it was after one undo; three drawings on frames 1–3 under a Repeat of 3 show frame
///    2's picture on frame 5, the timeline ghosts the repeated frames, and ink drawn on frame 5
///    appears on frame 2 (ruling 13) — and Bake on that Repeat layer turns the loop into a drawing on
///    every frame that draws the same pictures, with one Undo looping again.
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
    /// margins, which read as black on this device (`paperRect` says why).
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

    /// **The paper's edges in host-normalised coordinates, found by walking out from the host's
    /// centre**, not estimated from the host's aspect and not the extent of every whitish pixel.
    /// `canvas.host` is the whole screen under the toolbars: its screenshot carries the left rail's
    /// white knobs and the top bar's white circle, so a whitish-extent scan reads 0.03…0.97 across;
    /// `paperRect` assumes a square canvas filling the shorter side, which this document
    /// is not; and **the canvas re-fits when the layer rail opens and closes**, so two screenshots
    /// are only comparable in coordinates relative to the paper each one shows. The paper is one
    /// solid white rectangle with the host's centre inside it, so its edges are where whitish stops
    /// along the centre row and the centre column.
    ///
    /// **This is the *visible* paper, and its bottom edge is the timeline panel's top, not the
    /// paper's.** The panel overlays the host's lower part (375 pt on the suite's portrait iPad, which
    /// covers the paper's lower third), so the centre of this rectangle is not the centre of the
    /// canvas — the canvas is centred on the host (`CanvasView.Coordinator.baseCenter`), and that is
    /// where a box turns about. A measurement that depends on the canvas's centre takes it from the
    /// host's own centre, `(0.5, 0.5)` in these coordinates, and never from this rectangle's.
    private func paperBounds(_ pixels: (bytes: [UInt8], width: Int, height: Int)) -> (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
        let (buf, w, h) = pixels
        func whitish(_ x: Int, _ y: Int) -> Bool {
            let o = y * w * 4 + x * 4
            return buf[o] > 235 && buf[o + 1] > 235 && buf[o + 2] > 235
        }
        // **Never along the centre row or column, because the ink is there.** A walk stops at the
        // first non-white pixel, and both tests below put ink on the centre row (and, after the
        // turn, on the centre column), so the walk that found the paper before drawing lost half of
        // it afterwards. The paper's top and left tenths carry no ink in either test: the vertical
        // extent is provisionally read down the centre column, the horizontal extent is read along
        // the row a tenth of the way down, and the vertical extent is then re-read down the column
        // a tenth of the way in.
        func run(_ fixed: Int, alongX: Bool) -> (Int, Int)? {
            let limit = alongX ? w : h
            var lo = limit / 2, hi = limit / 2
            let at: (Int) -> Bool = alongX ? { whitish($0, fixed) } : { whitish(fixed, $0) }
            guard at(lo) else { return nil }
            while lo > 0, at(lo - 1) { lo -= 1 }
            while hi < limit - 1, at(hi + 1) { hi += 1 }
            return (lo, hi)
        }
        guard let (y0, y1) = run(w / 2, alongX: false),
              let (minX, maxX) = run(y0 + (y1 - y0) / 10, alongX: true),
              let (minY, maxY) = run(minX + (maxX - minX) / 10, alongX: false)
        else { return nil }
        return (Double(minX) / Double(w), Double(maxX) / Double(w), Double(minY) / Double(h), Double(maxY) / Double(h))
    }

    /// A host-normalised point as a fraction of the paper — (0.5, 0.5) is the box's centre whatever
    /// the rail has done to the layout.
    private func paperRelative(_ p: CGPoint, in paper: (minX: Double, maxX: Double, minY: Double, maxY: Double)) -> (u: Double, v: Double) {
        ((Double(p.x) - paper.minX) / (paper.maxX - paper.minX), (Double(p.y) - paper.minY) / (paper.maxY - paper.minY))
    }

    /// The host-normalised region covering paper-relative rows `v0…v1`, inset 4% from the paper's
    /// sides so the probe never reads the margin.
    private func paperRegion(_ paper: (minX: Double, maxX: Double, minY: Double, maxY: Double), v0: Double, v1: Double)
        -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let w = paper.maxX - paper.minX, h = paper.maxY - paper.minY
        return (paper.minX + 0.04 * w, paper.maxX - 0.04 * w, paper.minY + v0 * h, paper.minY + v1 * h)
    }

    /// The host-normalised point at paper-relative `(u, v)`.
    private func hostPoint(_ paper: (minX: Double, maxX: Double, minY: Double, maxY: Double), u: Double, v: Double) -> CGVector {
        CGVector(dx: paper.minX + u * (paper.maxX - paper.minX), dy: paper.minY + v * (paper.maxY - paper.minY))
    }

    /// The paper as the canvas shows it right now — a fresh capture and its walk, failing the test
    /// rather than guessing when the host's centre is not on the paper.
    private func currentPaper(_ canvas: XCUIElement, _ what: String) -> (pixels: (bytes: [UInt8], width: Int, height: Int), paper: (minX: Double, maxX: Double, minY: Double, maxY: Double))? {
        guard let pixels = canvasPixels(canvas), let paper = paperBounds(pixels) else {
            XCTFail("\(what): could not find the paper from the host's centre")
            return nil
        }
        return (pixels, paper)
    }

    /// The rail is a toggle, and Done sometimes leaves it up and sometimes not — so this asks rather
    /// than taps blind, and every measurement below is taken with it down.
    ///
    /// **Not `list.exists` alone, since TODO (64).** A picked mode's settings now dock at the bottom
    /// of the screen (`TransformSettingsBar`) and suppress the whole rail while they are up —
    /// `EffectSettingsBar`'s own rule — so `layerPanel.list` is briefly absent even though
    /// `toolbar.layersButton` is still what closes everything down: it toggles `activePanel`, and the
    /// docked bar reads that through `DrawingView.transformBeingEdited` regardless of whether the
    /// rail or the bar is what is actually on screen. `layerOptions.close` is on screen whenever any
    /// options sub-panel is — the list, a sub-menu, or a docked bar — so checking for either keeps
    /// this one call site correct under all three.
    private func closeRail(_ app: XCUIApplication) {
        let list = app.tables["layerPanel.list"]
        if list.exists || app.buttons["layerOptions.close"].exists {
            app.buttons["toolbar.layersButton"].tap()
            _ = list.waitForNonExistence(timeout: 5)
        }
    }

    /// **Opens the settings bar `pickMode` leaves a row for** — TODO (64): a picked mode's rows dock
    /// at the bottom of the screen now, behind the "<Mode> Settings ▸" row, the way a grade's knobs
    /// already dock behind "Effect Settings ▸". `layerOptions.subMenuTitle` is the bar's own signal
    /// that it is actually up, `optionsSubMenuHeader`'s shared header.
    private func openTransformSettings(_ app: XCUIApplication) {
        let row = app.buttons["layerOptions.transformSettings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The picked mode's settings row is on the panel")
        row.tap()
        XCTAssertTrue(app.staticTexts["layerOptions.subMenuTitle"].waitForExistence(timeout: 5),
                     "the mode's settings dock at the bottom of the screen")
    }

    /// **Back, from the settings bar to the rail** — needed wherever a test has to reach a rail-only
    /// row (`layerOptions.transformMove`) after reading the bar, since the bar stands the whole rail
    /// down while it is up.
    private func backFromTransformSettings(_ app: XCUIApplication) {
        let back = app.buttons["layerOptions.subMenuBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back returns to the rail")
        back.tap()
        XCTAssertTrue(app.buttons["layerOptions.transformMove"].waitForExistence(timeout: 5),
                     "…with the Move row there again")
    }

    /// A short vertical band of ink at `x`, `y` — seven passes so it is a band rather than a hairline
    /// the probe steps over.
    private func drawBand(on canvas: XCUIElement, x: Double, y: Double, halfHeight: Double = 0.03) {
        for i in 0..<7 {
            let px = x + Double(i) * 0.004
            drawLine(on: canvas, from: CGVector(dx: px, dy: y - halfHeight), to: CGVector(dx: px, dy: y + halfHeight))
        }
    }

    /// The modes §8 has shipped, which the picker must list — and no other.
    private static let shippedModes = ["move", "parallax", "rotate", "shake", "repeat"]

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
        for shipped in Self.shippedModes {
            XCTAssertTrue(app.buttons["layerOptions.transformMode.\(shipped)"].exists, "The picker lists \(shipped)")
        }
        item.tap()
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        XCTAssertEqual(modeButton.value as? String, mode, "the pick reached the model and the row reports it")
    }

    /// Puts the playhead on `frame` (1-based, as the label prints it) by tapping the transform
    /// layer's bar; a synthetic tap lands a frame off now and then, so it nudges until the label agrees.
    ///
    /// **Never taps a frame the playhead is already on**: a second tap on the selected cel raises
    /// the cel menu (that is how `TransformLayerSpanUITests` marks a keyframe), and a menu over the
    /// paper is dark pixels the probe would read as ink. If one comes up anyway it is dismissed by
    /// tapping the frame label, which does nothing else.
    private func scrub(_ app: XCUIApplication, toFrame frame: Int, total: Int) {
        let cel = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "The transform layer's bar is on the timeline")
        var dx = (Double(frame) - 0.5) / Double(total)
        for _ in 0..<6 {
            if readFrameLabel(app)?.current == frame { break }
            cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            guard let read = readFrameLabel(app) else { continue }
            if read.current == frame { break }
            dx += read.current < frame ? 0.5 / Double(total) : -0.5 / Double(total)
        }
        let menu = app.buttons["timeline.menu.Add Keys"]
        if menu.exists {
            app.staticTexts["timeline.frameLabel"].tap()
            _ = menu.waitForNonExistence(timeout: 3)
        }
        XCTAssertEqual(readFrameLabel(app)?.current, frame, "the playhead is on frame \(frame)")
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
        guard let blank = currentPaper(canvas, "at launch") else { return }

        // Four bands on four layers, bottom to top: the born layer, then three more. Each band sits
        // at its own paper row so the probe can tell them apart after they move by different amounts.
        let rows = [0.2, 0.4, 0.6, 0.8]
        let u = 0.3
        func band(_ v: Double) {
            let at = hostPoint(blank.paper, u: u, v: v)
            drawBand(on: canvas, x: Double(at.dx), y: Double(at.dy))
        }
        band(rows[0])
        for row in rows.dropFirst() {
            openLayerPanel(app)
            addVectorLayerFromOpenPanel(app)
            closeRail(app)
            band(row)
        }
        guard let before = currentPaper(canvas, "before the drag") else { return }
        let startColumns = rows.map { v in
            inkCentroid(before.pixels, in: paperRegion(before.paper, v0: v - 0.06, v1: v + 0.06))
                .map { paperRelative($0, in: before.paper).u }
        }
        XCTAssertEqual(startColumns.compactMap { $0 }.count, 4, "Sanity: all four bands landed, read \(startColumns)")

        // The layer itself, from the + menu, then its options: Mode → Parallax.
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        pickMode(app, layerIndex: 4, mode: "parallax")

        // TODO (64): the item list is behind the settings row now, docked at the bottom of the screen.
        openTransformSettings(app)

        // **What the panel exposes**: the four items at their positional defaults, nearest first,
        // each slider and field drawn at the share its row says.
        let list = app.descendants(matching: .any)["layerOptions.parallaxItems"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Parallax puts the item list on the panel")
        let listed = (list.value as? String ?? "").split(separator: "|").map(String.init)
        XCTAssertEqual(listed.count, 4, "four items beneath the layer, read \(listed)")
        XCTAssertEqual(listed.map { $0.split(separator: "=").last.map(String.init) ?? "" }, ["100", "75", "50", "25"],
                       "the owner's defaults, top to bottom, none of them typed: \(listed)")
        let backSlider = app.sliders["layerOptions.parallaxItem.3.slider"]
        XCTAssertTrue(backSlider.exists, "…each with a slider of its own")
        XCTAssertEqual(backSlider.value as? String, "25", "…drawn at the share the row says, not at the key path's 100")
        XCTAssertEqual(app.textFields["layerOptions.parallaxItem.3.field"].value as? String, "25")
        attachScreenshot(app, "1-parallax-item-list")

        // Back to the rail: the Move row lives there, not in the settings bar.
        backFromTransformSettings(app)

        // The verb: the Move row raises the box, and the drag moves every band live. The rail is up
        // and the canvas has re-fitted beside it, so the drag is measured against the paper as it
        // is *now*.
        let moveRow = app.buttons["layerOptions.transformMove"]
        XCTAssertTrue(moveRow.waitForExistence(timeout: 5), "The Move row is still the way to the box")
        moveRow.tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move raised the box")
        guard let lifted = currentPaper(canvas, "with the box up") else { return }
        let start = canvas.coordinate(withNormalizedOffset: hostPoint(lifted.paper, u: 0.45, v: 0.5))
        let end = canvas.coordinate(withNormalizedOffset: hostPoint(lifted.paper, u: 0.75, v: 0.5))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        app.buttons["moveBar.doneButton"].tap()
        closeRail(app)
        attachScreenshot(app, "2-parallax-after-the-drag")

        // **What is drawn**: each band moved by its share of what the top band moved, in paper units.
        guard let after = currentPaper(canvas, "after the drag") else { return }
        var shifts: [Double] = []
        for (i, v) in rows.enumerated() {
            guard let was = startColumns[i],
                  let now = inkCentroid(after.pixels, in: paperRegion(after.paper, v0: v - 0.06, v1: v + 0.06))
                      .map({ paperRelative($0, in: after.paper).u }) else {
                return XCTFail("Band \(i) was lost after the drag")
            }
            shifts.append(now - was)
        }
        let top = shifts[3]
        XCTAssertGreaterThan(top, 0.12, "the nearest band followed the box a good way (paper widths): \(shifts)")
        XCTAssertLessThan(top, 0.36, "…and no further than the 0.3 the box was dragged: \(shifts)")
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
        guard let blank = currentPaper(canvas, "at launch") else { return }
        guard let total = readFrameLabel(app)?.total else { return XCTFail("No frame label") }
        attachScreenshot(app, "0-launch")

        // A band 0.15 of the paper right of the middle of what is visible — near enough the centre
        // that a quarter turn lands it well clear of the timeline panel, which covers the paper's
        // lower third.
        let at = hostPoint(blank.paper, u: 0.65, v: 0.5)
        drawBand(on: canvas, x: Double(at.dx), y: Double(at.dy), halfHeight: 0.04)
        attachScreenshot(app, "0-band-drawn")
        guard let rest = currentPaper(canvas, "after drawing"),
              let restInk = inkCentroid(rest.pixels, in: paperRegion(rest.paper, v0: 0.04, v1: 0.96)) else {
            return XCTFail("The band did not land: paper at launch \(blank.paper), drawn at \(at)")
        }
        let restCentroid = paperRelative(restInk, in: rest.paper)
        XCTAssertEqual(restCentroid.u, 0.65, accuracy: 0.04, "Sanity: the band is right of centre")
        XCTAssertEqual(restCentroid.v, 0.5, accuracy: 0.04, "Sanity: …where it was aimed")

        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        pickMode(app, layerIndex: 1, mode: "rotate")

        // TODO (64): the speed field is behind the settings row now, docked at the bottom of the screen.
        openTransformSettings(app)

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
        attachScreenshot(app, "1-rotate-speed-typed")
        closeRail(app)

        // At the bar's first frame nothing has turned yet.
        scrub(app, toFrame: 1, total: total)
        attachScreenshot(app, "1b-at-frame-1")
        guard let first = currentPaper(canvas, "at the first frame"),
              let atFirst = inkCentroid(first.pixels, in: paperRegion(first.paper, v0: 0.04, v1: 0.96))
                  .map({ paperRelative($0, in: first.paper) }) else {
            return XCTFail("The band vanished at the first frame")
        }
        XCTAssertEqual(atFirst.u, restCentroid.u, accuracy: 0.03,
                       "frame 1: the band is where it was drawn (paper \(first.paper), rest paper \(rest.paper))")
        XCTAssertEqual(atFirst.v, restCentroid.v, accuracy: 0.03)

        // Six frames in: a quarter turn clockwise about the box's centre — which is the canvas's, and
        // the canvas is centred on the host, so it is the host's own centre — puts what was to the
        // right of it directly below it, as far below as it was to the right. Worked in the capture's
        // own pixels, where that is a rotation of the vector from the centre; the visible paper's
        // centre is not the canvas's (`paperBounds`), and its fractions would not turn.
        scrub(app, toFrame: 7, total: total)
        let width = Double(rest.pixels.width), height = Double(rest.pixels.height)
        let fromCentre = (x: (Double(restInk.x) - 0.5) * width, y: (Double(restInk.y) - 0.5) * height)
        let expected = CGPoint(x: 0.5 - fromCentre.y / width, y: 0.5 + fromCentre.x / height)
        // The tolerance is 0.04 of the paper's width, which is what it was when it was 0.04 of the paper.
        let tolerance = 0.04 * (rest.paper.maxX - rest.paper.minX)
        func misses(_ read: CGPoint) -> (x: Double, y: Double) {
            (Double(read.x - expected.x), Double(read.y - expected.y) * height / width)
        }
        // The posed frame reaches the canvas through the compositor a beat after the scrub, so the
        // probe is repeated until the picture settles — and reports the last reading if it never does.
        var atSeventh = restInk
        let deadline = Date().addingTimeInterval(8)
        repeat {
            guard let turned = currentPaper(canvas, "at the seventh frame"),
                  let read = inkCentroid(turned.pixels, in: paperRegion(turned.paper, v0: 0.04, v1: 0.96)) else {
                return XCTFail("The band vanished at the seventh frame")
            }
            atSeventh = read
            if abs(misses(read).x) < tolerance, abs(misses(read).y) < tolerance { break }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        attachScreenshot(app, "2-rotate-six-frames-in")
        XCTAssertEqual(misses(atSeventh).x, 0, accuracy: tolerance,
                       "frame 7: the band is on the centre column — turned about the box's centre, not slid "
                       + "(read \(atSeventh), expected \(expected))")
        XCTAssertEqual(misses(atSeventh).y, 0, accuracy: tolerance,
                       "frame 7: …and below it, as far below as it was to the right "
                       + "(read \(atSeventh), expected \(expected))")
    }

    // MARK: - Shake

    /// The band's paper-relative centroid at each of `frames`, scrubbing to each in turn. Every
    /// read is repeated until two consecutive captures agree, because a posed frame reaches the
    /// canvas through the compositor a beat after the scrub.
    private func bandColumns(_ app: XCUIApplication, canvas: XCUIElement, frames: [Int], total: Int,
                             _ what: String) -> [Double]? {
        var columns: [Double] = []
        for frame in frames {
            scrub(app, toFrame: frame, total: total)
            var last: Double?
            var settled: Double?
            let deadline = Date().addingTimeInterval(8)
            repeat {
                guard let paper = currentPaper(canvas, "\(what), frame \(frame)"),
                      let read = inkCentroid(paper.pixels, in: paperRegion(paper.paper, v0: 0.15, v1: 0.96))
                          .map({ paperRelative($0, in: paper.paper).u }) else {
                    XCTFail("\(what): the band vanished at frame \(frame)")
                    return nil
                }
                if let last, abs(last - read) < 0.002 { settled = read; break }
                last = read
                Thread.sleep(forTimeInterval: 0.3)
            } while Date() < deadline
            guard let settled else { XCTFail("\(what): frame \(frame) never settled"); return nil }
            columns.append(settled)
        }
        return columns
    }

    /// **A band left of and above the centre, a transform layer above, Mode → Shake, type 300 into
    /// Shake X, and the band is drawn somewhere else on the bar's first frames — the same somewhere
    /// else when the playhead comes back, somewhere new after Re-roll, and back where it was after
    /// one undo** — §5.4 and §2 ruling 9, all of it off the screen. The amplitude field is the
    /// exposed operand (its readout echoes it); the seed is never read, only its consequences. Four
    /// frames are read rather than one so the "moved" and "re-rolled" checks do not hang on a single
    /// noise sample that could, one time in twenty, be near zero.
    ///
    /// The band starts at paper (0.3, 0.3) and 300 points is under 0.15 of a 2048-point paper, so
    /// however the noise falls the band never reaches the centre column or the top tenth — the two
    /// lines `paperBounds` walks to find the paper.
    func testShakeJoltsTheInkTheSameWayEveryTimeUntilReRolledAndUndoBringsTheOldShakeBack() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let blank = currentPaper(canvas, "at launch") else { return }
        guard let total = readFrameLabel(app)?.total else { return XCTFail("No frame label") }

        let at = hostPoint(blank.paper, u: 0.3, v: 0.3)
        drawBand(on: canvas, x: Double(at.dx), y: Double(at.dy), halfHeight: 0.04)
        guard let rest = currentPaper(canvas, "after drawing"),
              let restU = inkCentroid(rest.pixels, in: paperRegion(rest.paper, v0: 0.15, v1: 0.96))
                  .map({ paperRelative($0, in: rest.paper).u }) else {
            return XCTFail("The band did not land")
        }
        XCTAssertEqual(restU, 0.3, accuracy: 0.04, "Sanity: the band is left of centre")

        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        pickMode(app, layerIndex: 1, mode: "shake")

        // TODO (64): the amplitude fields are behind the settings row now, docked at the bottom of
        // the screen.
        openTransformSettings(app)

        // **What the panel exposes**: three amplitude fields, a speed slider and Re-roll.
        let field = app.textFields["layerOptions.shakeX.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Shake puts the Shake X field on the panel")
        XCTAssertTrue(app.textFields["layerOptions.shakeY.field"].exists, "…and Shake Y")
        XCTAssertTrue(app.textFields["layerOptions.shakeRotation.field"].exists, "…and Rotate Shake")
        XCTAssertTrue(app.sliders["layerOptions.shakePeriod.slider"].exists, "…and how fast")
        XCTAssertTrue(app.buttons["layerOptions.shakeReroll"].exists, "…and Re-roll")
        XCTAssertEqual(app.sliders["layerOptions.shakePeriod.slider"].value as? String, "1", "a new jolt every frame to begin with")
        field.tap()
        field.typeText("300\n")
        let readout = app.staticTexts["layerOptions.shakeXReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertTrue(readout.label.hasPrefix("300"), "the readout echoes the typed amplitude: \(readout.label)")
        attachScreenshot(app, "1-shake-amplitude-typed")
        closeRail(app)

        // **What is drawn**: on the bar's first four frames the band is somewhere else — 300 points
        // of a 2048-point canvas is up to a seventh of the paper — and the same somewhere else when
        // the playhead comes back to the first frame.
        let frames = [1, 2, 3, 4]
        guard let first = bandColumns(app, canvas: canvas, frames: frames, total: total, "first pass") else { return }
        attachScreenshot(app, "2-shake-frame-4")
        XCTAssertTrue(first.contains { abs($0 - restU) > 0.01 },
                      "the band moved on at least one of the first four frames: \(first) against rest \(restU)")
        // Two frames suffice for the determinism check (the noise either re-rolls per render or it
        // does not); four are read where a single near-zero sample could hide a real difference.
        guard let again = bandColumns(app, canvas: canvas, frames: Array(frames.prefix(2)), total: total, "second pass") else { return }
        for (a, b) in zip(first, again) {
            XCTAssertEqual(a, b, accuracy: 0.004, "the same frame draws the same picture on the way back: \(first) vs \(again)")
        }

        // Re-roll: a new shake. The panel is reached through the layer's row again, and the settings
        // bar through its row again — a fresh options panel starts with it closed (TODO (64)).
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        openTransformSettings(app)
        let reroll = app.buttons["layerOptions.shakeReroll"]
        XCTAssertTrue(reroll.waitForExistence(timeout: 5), "the settings bar reopens on the shake rows")
        reroll.tap()
        closeRail(app)
        guard let rerolled = bandColumns(app, canvas: canvas, frames: frames, total: total, "after re-roll") else { return }
        attachScreenshot(app, "3-shake-rerolled-frame-4")
        XCTAssertTrue(zip(first, rerolled).contains { abs($0 - $1) > 0.01 },
                      "Re-roll drew a different picture on at least one frame: \(first) vs \(rerolled)")

        // One undo: the old shake, exactly.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        guard let restored = bandColumns(app, canvas: canvas, frames: Array(frames.prefix(2)), total: total, "after undo") else { return }
        attachScreenshot(app, "4-shake-undone-frame-4")
        for (a, b) in zip(first, restored) {
            XCTAssertEqual(a, b, accuracy: 0.004, "one undo brings the old shake back: \(first) vs \(restored)")
        }
    }

    // MARK: - Repeat

    /// The born layer's block whose value starts at `start` — the array index moves under a split,
    /// so the block is found by what it says rather than by where it is.
    private func bornCel(_ app: XCUIApplication, startingAt start: Int) -> XCUIElement? {
        for celIndex in 0..<16 {
            let cel = app.otherElements["timeline.cel.0.\(celIndex)"]
            guard cel.exists, let value = cel.value as? String else { continue }
            if value.split(separator: ",").first.map(String.init) == "\(start)" { return cel }
        }
        return nil
    }

    /// Every block on the born layer as `"start,length"`, in frame order.
    private func bornBlocks(_ app: XCUIApplication) -> [String] {
        (0..<16).map { app.otherElements["timeline.cel.0.\($0)"] }
            .filter(\.exists)
            .compactMap { $0.value as? String }
            .sorted { (Int($0.split(separator: ",")[0]) ?? 0) < (Int($1.split(separator: ",")[0]) ?? 0) }
    }

    /// Taps frame `frame` (0-based) of the born layer's block starting at `start`, which selects the
    /// layer and moves the playhead — `handleTapOnCel`'s first stage.
    private func tapBornLayer(_ app: XCUIApplication, blockStartingAt start: Int, frame: Int) {
        guard let cel = bornCel(app, startingAt: start),
              let value = cel.value as? String, let length = Int(value.split(separator: ",")[1]) else {
            return XCTFail("No block on the born layer starting at \(start)")
        }
        cel.coordinate(withNormalizedOffset: CGVector(dx: (Double(frame - start) + 0.5) / Double(length), dy: 0.5)).tap()
        XCTAssertEqual(readFrameLabel(app)?.current, frame + 1, "the tap put the playhead on frame \(frame + 1)")
    }

    /// Splits the born layer's block starting at `start` at frame `frame`, through the cel menu:
    /// one tap selects the frame, a second on the same spot opens the menu, Split Drawing cuts.
    private func splitBornLayer(_ app: XCUIApplication, blockStartingAt start: Int, atFrame frame: Int) {
        tapBornLayer(app, blockStartingAt: start, frame: frame)
        guard let cel = bornCel(app, startingAt: start),
              let value = cel.value as? String, let length = Int(value.split(separator: ",")[1]) else { return }
        cel.coordinate(withNormalizedOffset: CGVector(dx: (Double(frame - start) + 0.5) / Double(length), dy: 0.5)).tap()
        let split = app.buttons["timeline.menu.Split Drawing"]
        XCTAssertTrue(split.waitForExistence(timeout: 5), "the second tap opens the block's menu")
        split.tap()
        XCTAssertTrue(bornCel(app, startingAt: frame)?.waitForExistence(timeout: 5) == true, "the cut left a block starting at \(frame)")
    }

    /// The band's paper-relative column inside paper rows `v0…v1`, repeated until two consecutive
    /// captures agree; nil when the region holds no ink after the deadline.
    private func settledColumn(_ canvas: XCUIElement, v0: Double, v1: Double, _ what: String) -> Double? {
        var last: Double?
        let deadline = Date().addingTimeInterval(8)
        repeat {
            guard let paper = currentPaper(canvas, what) else { return nil }
            let read = inkCentroid(paper.pixels, in: paperRegion(paper.paper, v0: v0, v1: v1))
                .map { paperRelative($0, in: paper.paper).u }
            if let read, let last, abs(last - read) < 0.002 { return read }
            last = read
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return last
    }

    /// **Three drawings on frames 1, 2 and 3 of a fresh document, a transform layer above, Mode →
    /// Repeat, typed to 3** — the born layer's twelve-frame block is cut twice through the cel menu so
    /// the three frames are three drawings; the period field is the exposed operand (pre-filled to 12,
    /// where the held third drawing ends, then typed to 3). Returns the band column each drawing was
    /// drawn at and the document's frame count, with the rail closed and the playhead on frame 3.
    private func threeDrawingsUnderARepeatOfThree(_ app: XCUIApplication, canvas: XCUIElement)
        -> (columns: [Double], total: Int)? {
        guard let total = readFrameLabel(app)?.total else {
            XCTFail("No frame label")
            return nil
        }
        XCTAssertEqual(total, 12, "Premise: a new document is twelve frames")

        // Three blocks: [0,1), [1,2), [2,12).
        splitBornLayer(app, blockStartingAt: 0, atFrame: 1)
        splitBornLayer(app, blockStartingAt: 1, atFrame: 2)
        XCTAssertEqual(bornCel(app, startingAt: 0)?.value as? String, "0,1")
        XCTAssertEqual(bornCel(app, startingAt: 1)?.value as? String, "1,1")
        XCTAssertEqual(bornCel(app, startingAt: 2)?.value as? String, "2,10")

        // A band on each of the first three frames at its own column, all on row 0.3 — off the
        // centre column and the top tenth, which is where `paperBounds` walks.
        let columns = [0.2, 0.4, 0.7]
        for (frame, u) in columns.enumerated() {
            tapBornLayer(app, blockStartingAt: frame, frame: frame)
            guard let paper = currentPaper(canvas, "frame \(frame + 1) before drawing") else { return nil }
            let at = hostPoint(paper.paper, u: u, v: 0.3)
            drawBand(on: canvas, x: Double(at.dx), y: Double(at.dy), halfHeight: 0.04)
            let read = settledColumn(canvas, v0: 0.15, v1: 0.45, "frame \(frame + 1) after drawing")
            XCTAssertEqual(read ?? -1, u, accuracy: 0.03, "Sanity: frame \(frame + 1)'s band is at \(u)")
        }
        attachScreenshot(app, "1-three-drawings")

        // The layer, from +, then Mode → Repeat. The period is pre-filled from where the drawings
        // beneath end — the third block is held to 12 — and typed to 3.
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        pickMode(app, layerIndex: 1, mode: "repeat")

        // TODO (64): the period field is behind the settings row now, docked at the bottom of the screen.
        openTransformSettings(app)
        let field = app.textFields["layerOptions.repeatPeriod.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Repeat puts the period field on the panel")
        XCTAssertEqual(field.value as? String, "12", "pre-filled from where the drawings beneath end")
        field.tap()
        field.typeText("3\n")
        let readout = app.staticTexts["layerOptions.repeatPeriodReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertEqual(readout.label, "3 frames", "the readout echoes the typed length")
        attachScreenshot(app, "2-repeat-period-typed")
        closeRail(app)
        return (columns, total)
    }

    /// **Three drawings on frames 1, 2 and 3, a transform layer above, Mode → Repeat, type 3, and
    /// frame 5 shows frame 2's picture; the timeline ghosts the repeated frames; and a line drawn on
    /// frame 5 appears on frame 2** — §5.5 and rulings 11–13, off the screen.
    func testRepeatShowsFrameTwoOnFrameFiveGhostsTheLoopAndRedirectsInkToTheFrameItRepeats() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (columns, total) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }

        // **What the timeline exposes**: the born layer's row ghosts frames 4–12, one frame each.
        let ghosts = app.otherElements["timeline.repeatGhosts.0"]
        XCTAssertTrue(ghosts.waitForExistence(timeout: 5), "the repeated frames are ghosted on the drawing's row")
        XCTAssertTrue((ghosts.value as? String ?? "").hasPrefix("3,1|4,1|5,1|6,1"),
                      "frames 4, 5, 6, 7… each show an earlier drawing: \(String(describing: ghosts.value))")

        // **What is drawn**: frame 5 is frame 2's picture (the band at 0.4), not the held third
        // drawing's (0.7); frame 4 is frame 1's.
        scrub(app, toFrame: 5, total: total)
        let atFive = settledColumn(canvas, v0: 0.15, v1: 0.45, "at frame 5")
        XCTAssertEqual(atFive ?? -1, columns[1], accuracy: 0.03, "frame 5 shows frame 2's drawing, not the block sitting under the playhead")
        scrub(app, toFrame: 4, total: total)
        XCTAssertEqual(settledColumn(canvas, v0: 0.15, v1: 0.45, "at frame 4") ?? -1, columns[0], accuracy: 0.03, "frame 4 shows frame 1's")
        attachScreenshot(app, "3-frame-5-shows-frame-2")

        // **Ruling 13**: a second band drawn on frame 5, lower down, lands on frame 2 — and not on
        // frame 3. The born layer is selected by tapping its held block at frame 5.
        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        guard let paper = currentPaper(canvas, "frame 5 before the redirected stroke") else { return }
        let lower = hostPoint(paper.paper, u: 0.55, v: 0.65)
        drawBand(on: canvas, x: Double(lower.dx), y: Double(lower.dy), halfHeight: 0.04)
        XCTAssertEqual(settledColumn(canvas, v0: 0.5, v1: 0.8, "frame 5 after drawing") ?? -1, 0.55, accuracy: 0.03,
                       "the new band shows on frame 5 itself")
        scrub(app, toFrame: 2, total: total)
        XCTAssertEqual(settledColumn(canvas, v0: 0.5, v1: 0.8, "at frame 2") ?? -1, 0.55, accuracy: 0.03,
                       "…and on frame 2, the drawing it repeats")
        XCTAssertEqual(settledColumn(canvas, v0: 0.15, v1: 0.45, "at frame 2, upper") ?? -1, columns[1], accuracy: 0.03,
                       "frame 2's own band is still there")
        attachScreenshot(app, "4-ink-from-frame-5-on-frame-2")
        scrub(app, toFrame: 3, total: total)
        XCTAssertNil(settledColumn(canvas, v0: 0.5, v1: 0.8, "at frame 3"), "frame 3 did not receive it")
    }

    func testRepeatedSelectionClearChangesTheSourceDrawingAndOneUndoRestoresItsInk() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (columns, total) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }
        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        XCTAssertEqual(settledColumn(canvas, v0: 0.15, v1: 0.45, "repeated source before Clear") ?? -1,
                       columns[1], accuracy: 0.03)
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        XCTAssertEqual(settledColumn(canvas, v0: 0.15, v1: 0.45, "source with Select open") ?? -1,
                       columns[1], accuracy: 0.03, "PREMISE: the source band is visible above the Select dock")
        guard let paper = currentPaper(canvas, "source selection") else { return }
        let start = hostPoint(paper.paper, u: 0.30, v: 0.08)
        let end = hostPoint(paper.paper, u: 0.50, v: 0.65)
        let host = canvas.frame
        dragInPoints(app, from: CGPoint(x: host.minX + start.dx * host.width, y: host.minY + start.dy * host.height),
                     to: CGPoint(x: host.minX + end.dx * host.width, y: host.minY + end.dy * host.height))
        // Read black artwork inside the loop, away from its blue/white selection border.
        let inkStart = hostPoint(paper.paper, u: 0.32, v: 0.15)
        let inkEnd = hostPoint(paper.paper, u: 0.48, v: 0.45)
        let inkWindow = CGRect(x: inkStart.dx, y: inkStart.dy,
                               width: inkEnd.dx - inkStart.dx, height: inkEnd.dy - inkStart.dy)
        let clear = app.buttons["selectPanel.clearButton"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertFalse(try repeatedInkPicture(canvas, in: inkWindow).contains(true),
                       "Clear removes the source band shown on frame five")
        attachScreenshot(XCUIScreen.main, "repeat-writers-1-clear-on-frame-five")
        scrub(app, toFrame: 1, total: total)
        XCTAssertFalse(try repeatedInkPicture(canvas, in: inkWindow).contains(true),
                       "the original frame two drawing owns the Clear")
        app.buttons["sideToolbar.undoButton"].tap()
        let restored = try repeatedInkPicture(canvas, in: inkWindow)
        XCTAssertTrue(restored.contains(true), "one Undo restores the source band")
        let restoredColumns = restored.enumerated().filter { $0.element }.map { CGFloat($0.offset % 48) }
        let restoredX = inkWindow.minX + inkWindow.width * restoredColumns.reduce(0, +)
            / CGFloat(max(1, restoredColumns.count)) / 48
        XCTAssertEqual((Double(restoredX) - paper.paper.minX) / (paper.paper.maxX - paper.paper.minX),
                       columns[1], accuracy: 0.03, "Undo restores the source band's original column")
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertFalse(try repeatedInkPicture(canvas, in: inkWindow).contains(true), "Redo clears the source band again")
        scrub(app, toFrame: 2, total: total)
        guard let otherPaper = currentPaper(canvas, "other drawing after Clear") else { return }
        let otherStart = hostPoint(otherPaper.paper, u: columns[2] - 0.03, v: 0.15)
        let otherEnd = hostPoint(otherPaper.paper, u: columns[2] + 0.03, v: 0.45)
        let otherWindow = CGRect(x: otherStart.dx, y: otherStart.dy,
                                 width: otherEnd.dx - otherStart.dx, height: otherEnd.dy - otherStart.dy)
        let other = try repeatedInkPicture(canvas, in: otherWindow)
        XCTAssertTrue(other.contains(true), "Clear leaves the raw playhead's other drawing intact")
        let otherColumns = other.enumerated().filter { $0.element }.map { CGFloat($0.offset % 48) }
        let otherX = otherWindow.minX + otherWindow.width * otherColumns.reduce(0, +)
            / CGFloat(max(1, otherColumns.count)) / 48
        XCTAssertEqual((Double(otherX) - otherPaper.paper.minX) / (otherPaper.paper.maxX - otherPaper.paper.minX),
                       columns[2], accuracy: 0.03, "the other drawing keeps its original column")
        attachScreenshot(XCUIScreen.main, "repeat-writers-2-other-drawing-kept")
    }

    func testRepeatedMoveChangesTheOriginalDrawingAndOneUndoRestoresItsVisibleBand() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        XCTAssertEqual(app.windows.firstMatch.frame.size, CGSize(width: 1080, height: 810))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (_, total) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }
        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        guard let paper = currentPaper(canvas, "repeated band before Move") else { return }
        let start = hostPoint(paper.paper, u: 0.30, v: 0.08)
        let end = hostPoint(paper.paper, u: 0.50, v: 0.65)
        dragOnCanvas(app, from: start, to: end)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move lifts the shown source band")
        guard let movingPaper = currentPaper(canvas, "source Move box") else { return }
        let box = try XCTUnwrap(settledMoveBox(app), "the shown source has an exposed Move hull")
        let delta = CGFloat(0.15 * (movingPaper.paper.maxX - movingPaper.paper.minX))
        dragOnCanvas(app, from: CGVector(dx: box.midX, dy: box.midY),
                     to: CGVector(dx: box.midX + delta, dy: box.midY))
        attachScreenshot(XCUIScreen.main, "repeat-move-source-band-under-the-box")
        app.buttons["moveBar.doneButton"].tap()
        guard let donePaper = currentPaper(canvas, "after repeated Move") else { return }
        let oldStart = hostPoint(donePaper.paper, u: 0.34, v: 0.15)
        let oldEnd = hostPoint(donePaper.paper, u: 0.46, v: 0.45)
        let newStart = hostPoint(donePaper.paper, u: 0.50, v: 0.15)
        let newEnd = hostPoint(donePaper.paper, u: 0.60, v: 0.45)
        let oldWindow = CGRect(x: oldStart.dx, y: oldStart.dy, width: oldEnd.dx - oldStart.dx, height: oldEnd.dy - oldStart.dy)
        let movedWindow = CGRect(x: newStart.dx, y: newStart.dy, width: newEnd.dx - newStart.dx, height: newEnd.dy - newStart.dy)
        XCTAssertFalse(try repeatedInkPicture(canvas, in: oldWindow).contains(true), "shown ink leaves its original column")
        XCTAssertTrue(try repeatedInkPicture(canvas, in: movedWindow).contains(true), "shown source follows the drag")
        scrub(app, toFrame: 1, total: total)
        XCTAssertFalse(try repeatedInkPicture(canvas, in: oldWindow).contains(true))
        XCTAssertTrue(try repeatedInkPicture(canvas, in: movedWindow).contains(true), "the original drawing owns Move")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(try repeatedInkPicture(canvas, in: oldWindow).contains(true), "one Undo restores source ink")
        XCTAssertFalse(try repeatedInkPicture(canvas, in: movedWindow).contains(true))
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertTrue(try repeatedInkPicture(canvas, in: movedWindow).contains(true))
        scrub(app, toFrame: 2, total: total)
        XCTAssertEqual(settledColumn(canvas, v0: 0.15, v1: 0.45, "other drawing after Move") ?? -1,
                       0.7, accuracy: 0.03, "the raw playhead's drawing was not edited")
        attachScreenshot(XCUIScreen.main, "repeat-move-original-source-and-other-drawing")
    }

    func testRepeatedDuplicateCopiesTheShownSourceAndEachUndoReversesItsNudgeThenItsLayer() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        XCTAssertEqual(app.windows.firstMatch.frame.size, CGSize(width: 1080, height: 810))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (_, total) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }
        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        guard let paper = currentPaper(canvas, "repeated band before Duplicate") else { return }
        dragOnCanvas(app, from: hostPoint(paper.paper, u: 0.30, v: 0.08),
                     to: hostPoint(paper.paper, u: 0.50, v: 0.65))
        app.buttons["selectPanel.duplicateButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Duplicate lifts the shown band")
        let destination = app.otherElements["timeline.cel.1.1"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "the copy has the source drawing's frame span")
        XCTAssertEqual(destination.value as? String, "1,1")
        guard let movingPaper = currentPaper(canvas, "source Duplicate box") else { return }
        let box = try XCTUnwrap(settledMoveBox(app), "the copied source has an exposed Move hull")
        let delta = CGFloat(0.15 * (movingPaper.paper.maxX - movingPaper.paper.minX))
        dragOnCanvas(app, from: CGVector(dx: box.midX, dy: box.midY),
                     to: CGVector(dx: box.midX + delta, dy: box.midY))
        attachScreenshot(XCUIScreen.main, "repeat-duplicate-source-band-and-live-copy")
        app.buttons["moveBar.doneButton"].tap()
        guard let donePaper = currentPaper(canvas, "after repeated Duplicate") else { return }
        let originalStart = hostPoint(donePaper.paper, u: 0.34, v: 0.15)
        let originalEnd = hostPoint(donePaper.paper, u: 0.46, v: 0.45)
        let copyStart = hostPoint(donePaper.paper, u: 0.50, v: 0.15)
        let copyEnd = hostPoint(donePaper.paper, u: 0.60, v: 0.45)
        let originalWindow = CGRect(x: originalStart.dx, y: originalStart.dy, width: originalEnd.dx - originalStart.dx, height: originalEnd.dy - originalStart.dy)
        let copyWindow = CGRect(x: copyStart.dx, y: copyStart.dy, width: copyEnd.dx - copyStart.dx, height: copyEnd.dy - copyStart.dy)
        XCTAssertTrue(try repeatedInkPicture(canvas, in: originalWindow).contains(true), "original remains")
        XCTAssertTrue(try repeatedInkPicture(canvas, in: copyWindow).contains(true), "copy contains the shown source ink")
        scrub(app, toFrame: 1, total: total)
        XCTAssertTrue(try repeatedInkPicture(canvas, in: originalWindow).contains(true))
        XCTAssertTrue(try repeatedInkPicture(canvas, in: copyWindow).contains(true), "the copied span belongs to source frame two")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertFalse(try repeatedInkPicture(canvas, in: copyWindow).contains(true), "first Undo reverses the nudge")
        XCTAssertTrue(try repeatedInkPicture(canvas, in: originalWindow).contains(true))
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertFalse(destination.exists, "second Undo removes the copied layer")
        XCTAssertTrue(try repeatedInkPicture(canvas, in: originalWindow).contains(true), "source survives both Undos")
        app.buttons["sideToolbar.redoButton"].tap()
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertTrue(try repeatedInkPicture(canvas, in: copyWindow).contains(true))
        attachScreenshot(XCUIScreen.main, "repeat-duplicate-source-copy-restored")
    }

    func testRasterDuplicateOnARepeatedFrameStaysThereAfterDoneAndOneUndoRemovesOnlyItsCopy() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        XCTAssertEqual(app.windows.firstMatch.frame.size, CGSize(width: 1080, height: 810))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (_, total) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }
        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        openLayerPanel(app)
        XCTAssertTrue(tapWhenHittable(app.staticTexts["layerPanel.row.0"], "the source drawing's layer options"))
        let rasterize = app.buttons["layerOptions.rasterize"]
        XCTAssertTrue(rasterize.waitForExistence(timeout: 5))
        rasterize.tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.isVector, false, "the public Rasterize command made the source raster")
        closeRail(app)
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        guard let paper = currentPaper(canvas, "repeated raster band before Duplicate") else { return }
        dragOnCanvas(app, from: hostPoint(paper.paper, u: 0.30, v: 0.08),
                     to: hostPoint(paper.paper, u: 0.50, v: 0.65))
        app.buttons["selectPanel.duplicateButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5))
        let destination = app.otherElements["timeline.cel.2.0"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "the independent root copy is above the root Repeat")
        XCTAssertEqual(destination.value as? String, "4,1", "the copy starts where Duplicate was pressed and keeps the one-frame source duration")
        guard let movingPaper = currentPaper(canvas, "raster Duplicate box") else { return }
        let box = try XCTUnwrap(settledMoveBox(app))
        let delta = CGFloat(0.15 * (movingPaper.paper.maxX - movingPaper.paper.minX))
        dragOnCanvas(app, from: CGVector(dx: box.midX, dy: box.midY),
                     to: CGVector(dx: box.midX + delta, dy: box.midY))
        app.buttons["moveBar.doneButton"].tap()
        XCTAssertEqual(readFrameLabel(app)?.current, 5)
        guard let donePaper = currentPaper(canvas, "raster Duplicate after Done") else { return }
        func window(_ left: Double, _ right: Double) -> CGRect {
            let a = hostPoint(donePaper.paper, u: left, v: 0.15)
            let b = hostPoint(donePaper.paper, u: right, v: 0.45)
            return CGRect(x: a.dx, y: a.dy, width: b.dx - a.dx, height: b.dy - a.dy)
        }
        let original = window(0.34, 0.46), copied = window(0.50, 0.60)
        XCTAssertTrue(try repeatedInkPicture(canvas, in: original).contains(true), "the source drawing stays on the glass")
        XCTAssertTrue(try repeatedInkPicture(canvas, in: copied).contains(true), "the independent raster copy survives Done on frame five")
        attachScreenshot(XCUIScreen.main, "raster-repeat-duplicate-current-frame-owner-landscape")
        scrub(app, toFrame: 1, total: total)
        XCTAssertTrue(try repeatedInkPicture(canvas, in: original).contains(true), "the source frame remains unchanged")
        XCTAssertFalse(try repeatedInkPicture(canvas, in: copied).contains(true), "the independent copy was not placed on its source frame")
        scrub(app, toFrame: 4, total: total)
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertFalse(destination.exists, "one Undo removes the raster copy and its landing")
        XCTAssertTrue(try repeatedInkPicture(canvas, in: original).contains(true))
        XCTAssertFalse(try repeatedInkPicture(canvas, in: copied).contains(true))
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertEqual(destination.value as? String, "4,1")
        XCTAssertTrue(try repeatedInkPicture(canvas, in: copied).contains(true), "Redo restores the visible current-frame copy")
        attachScreenshot(XCUIScreen.main, "raster-repeat-duplicate-restored-owner-landscape")
    }

    @MainActor
    func testRepeatedCutPastesTheSourceInkAndEachArtworkUndoReversesOneAction() throws {
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        defer { pasteboard.items = savedItems }
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        XCTAssertEqual(app.windows.firstMatch.frame.size, CGSize(width: 1080, height: 810),
                       "PREMISE: clipboard workflow is drawn at the owner's landscape size")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (_, total) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }
        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        guard let paper = currentPaper(canvas, "before repeated Cut") else { return }
        let start = hostPoint(paper.paper, u: 0.30, v: 0.08)
        let end = hostPoint(paper.paper, u: 0.50, v: 0.65)
        let host = canvas.frame
        dragInPoints(app, from: CGPoint(x: host.minX + start.dx * host.width, y: host.minY + start.dy * host.height),
                     to: CGPoint(x: host.minX + end.dx * host.width, y: host.minY + end.dy * host.height))
        let inkStart = hostPoint(paper.paper, u: 0.32, v: 0.15)
        let inkEnd = hostPoint(paper.paper, u: 0.48, v: 0.45)
        let inkWindow = CGRect(x: inkStart.dx, y: inkStart.dy,
                               width: inkEnd.dx - inkStart.dx, height: inkEnd.dy - inkStart.dy)
        let before = try repeatedInkPicture(canvas, in: inkWindow)
        XCTAssertTrue(before.contains(true), "PREMISE: the selected source band is visibly black")
        app.buttons["toolbar.actionsButton"].tap()
        let cut = app.buttons["actions.cutRow"]
        XCTAssertTrue(cut.waitForExistence(timeout: 5))
        cut.tap()
        app.buttons["toolbar.actionsButton"].tap()
        XCTAssertFalse(try repeatedInkPicture(canvas, in: inkWindow).contains(true),
                       "Cut clears the repeated source drawing")
        attachScreenshot(XCUIScreen.main, "repeat-clipboard-1-cut-source-frame-five")
        scrub(app, toFrame: 1, total: total)
        XCTAssertFalse(try repeatedInkPicture(canvas, in: inkWindow).contains(true),
                       "the original frame two owns the Cut")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertEqual(try repeatedInkPicture(canvas, in: inkWindow), before, "one Undo reverses the artwork Cut")
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertFalse(try repeatedInkPicture(canvas, in: inkWindow).contains(true))
        scrub(app, toFrame: 4, total: total)
        app.buttons["toolbar.actionsButton"].tap()
        let paste = app.buttons["actions.pasteRow"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowPaste = springboard.alerts.buttons["Allow Paste"]
        if allowPaste.waitForExistence(timeout: 5) { allowPaste.tap() }
        app.buttons["toolbar.actionsButton"].tap()
        guard let pastedPaper = currentPaper(canvas, "after source Paste") else { return }
        let pastedStart = hostPoint(pastedPaper.paper, u: 0.35, v: 0.10)
        let pastedEnd = hostPoint(pastedPaper.paper, u: 0.65, v: 0.65)
        let pastedWindow = CGRect(x: pastedStart.dx, y: pastedStart.dy,
                                  width: pastedEnd.dx - pastedStart.dx, height: pastedEnd.dy - pastedStart.dy)
        let pasted = try repeatedInkPicture(canvas, in: pastedWindow)
        XCTAssertTrue(pasted.contains(true), "Paste draws the actual band copied by Cut, rather than an empty raw drawing")
        attachScreenshot(XCUIScreen.main, "repeat-clipboard-2-actual-source-pasted")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertFalse(try repeatedInkPicture(canvas, in: pastedWindow).contains(true), "one Undo removes only the pasted picture")
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertEqual(try repeatedInkPicture(canvas, in: pastedWindow), pasted)
    }

    private func repeatedInkPicture(_ canvas: XCUIElement, in requestedWindow: CGRect? = nil) throws -> [Bool] {
        let window = requestedWindow ?? wordsWindow(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let probe = try settledProbe(canvas, window: window, timeout: 8)
        return (0..<24).flatMap { y in (0..<48).map { x in
            probe(window.minX + window.width * Double(x) / 48,
                  window.minY + window.height * Double(y) / 24)
        } }
    }

    func testRepeatedSelectionOffersAndEditsTheShownSourceTextThroughHistory() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (_, total) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }
        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        _ = writeWords("Hi", app, canvas)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"))
        waitForTheKeyboardToLeave(app)
        let before = try repeatedInkPicture(canvas)
        XCTAssertTrue(before.contains(true), "the source label is actually drawn on the repeated frame")
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        let host = canvas.frame
        dragInPoints(app, from: CGPoint(x: host.minX + 0.50 * host.width, y: host.minY + 0.145 * host.height),
                     to: CGPoint(x: host.minX + 0.88 * host.width, y: host.minY + 0.24 * host.height))
        let edit = app.buttons["selectPanel.editTextButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Select offers the text that Repeat actually shows")
        XCTAssertEqual(edit.label, "Edit Text")
        attachScreenshot(app, "repeat-selection-1-edit-offered-for-source-words")
        edit.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForTextState(app, "box", "editing"), "Edit opens the source label")
        let size = app.sliders["textPanel.sizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.adjust(toNormalizedSliderPosition: 0.22)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"))
        waitForTheKeyboardToLeave(app)
        let edited = try repeatedInkPicture(canvas)
        XCTAssertTrue(edited.contains(true))
        XCTAssertNotEqual(edited, before, "Edit changes the actual source letters")
        attachScreenshot(app, "repeat-selection-2-source-words-edited")
        scrub(app, toFrame: 2, total: total)
        XCTAssertEqual(try repeatedInkPicture(canvas), edited, "the edit belongs to the source drawing")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertEqual(try repeatedInkPicture(canvas), before, "one Undo restores the source label")
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertEqual(try repeatedInkPicture(canvas), edited)
        scrub(app, toFrame: 3, total: total)
        XCTAssertFalse(try repeatedInkPicture(canvas).contains(true), "the other cel received no hidden text")
        attachScreenshot(app, "repeat-selection-3-other-cel-unchanged")
    }

    func testRepeatedTextIsWrittenAndReopenedOnTheShownSourceDrawing() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (_, total) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }
        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        func picture() throws -> [Bool] { try repeatedInkPicture(canvas) }
        XCTAssertFalse(try picture().contains(true), "PREMISE: the high words window is clear of all three brush bands")
        let topLeft = writeWords("Hi", app, canvas)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"))
        waitForTheKeyboardToLeave(app)
        let first = try picture()
        XCTAssertTrue(first.contains(true), "the new letters are drawn on the repeated frame itself")
        attachScreenshot(app, "repeat-text-1-written-on-frame-five")
        scrub(app, toFrame: 2, total: total)
        XCTAssertEqual(try picture(), first, "the same letters belong to the source drawing on frame two")
        attachScreenshot(app, "repeat-text-2-source-frame-two")
        scrub(app, toFrame: 3, total: total)
        XCTAssertFalse(try picture().contains(true), "the held drawing under the playhead received no text")

        tapBornLayer(app, blockStartingAt: 2, frame: 4)
        app.buttons["toolbar.addButton"].tap()
        let text = app.buttons["add.addTextRow"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        let inside = CGPoint(x: topLeft.x + 0.01 * canvas.frame.width,
                             y: topLeft.y + 0.01 * canvas.frame.height)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: inside.x, dy: inside.y)).tap()
        XCTAssertTrue(waitForTextState(app, "box", "editing"), "the text tool reopens the source label where Repeat draws it")
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"))
        waitForTheKeyboardToLeave(app)
        XCTAssertEqual(try picture(), first, "a no-op re-edit neither changes nor duplicates the repeated label")

        app.buttons["toolbar.addButton"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: inside.x, dy: inside.y)).tap()
        XCTAssertTrue(waitForTextState(app, "box", "editing"))
        if readTextState(app) != "editing" {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: inside.x, dy: inside.y)).tap()
        }
        typeIntoTextBox("o", app, at: inside)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"))
        waitForTheKeyboardToLeave(app)
        let edited = try picture()
        XCTAssertTrue(edited.contains(true))
        XCTAssertNotEqual(edited, first, "the re-edit changes actual repeated letters")
        scrub(app, toFrame: 2, total: total)
        XCTAssertEqual(try picture(), edited, "edited letters remain on the original source drawing")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertEqual(try picture(), first, "one Undo restores the source label before typing")
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertEqual(try picture(), edited)
        attachScreenshot(app, "repeat-text-3-edited-source-after-history")
        scrub(app, toFrame: 3, total: total)
        XCTAssertFalse(try picture().contains(true), "the other drawing is still unchanged after re-edit and history")
    }

    /// **Bake on the Repeat layer writes the loop out as drawings the artist can see on the timeline,
    /// draws the same pictures, and one Undo loops again** — (131)'s follow-up, driven from a fresh
    /// document: three drawings on frames 1–3 under a Repeat of 3 (the test above), then the layer's
    /// own menu → Bake → the prompt that says what it writes → Bake. The born layer's row, which held
    /// three blocks, holds twelve one-frame blocks; the Repeat layer and its ghost band are gone; and
    /// frames 4, 5, 6, 8 and 12 draw drawings 1, 2, 3, 2 and 3 off the canvas with nothing looping them.
    func testBakingTheRepeatLayerWritesTheLoopAsDrawingsOnTheTimelineAndOneUndoLoopsAgain() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let (columns, _) = threeDrawingsUnderARepeatOfThree(app, canvas: canvas) else { return }
        XCTAssertEqual(bornBlocks(app), ["0,1", "1,1", "2,10"], "Premise: three drawings, the third held")
        XCTAssertTrue(app.otherElements["timeline.repeatGhosts.0"].waitForExistence(timeout: 5),
                      "Premise: the loop is ghosted over them")

        // The Repeat layer's own menu offers Bake.
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The Repeat layer is the second row")
        row.tap()
        let bake = app.buttons["layerOptions.bake"]
        if !bake.waitForExistence(timeout: 3) { row.tap() }
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "A Repeat layer offers Bake")
        bake.tap()

        // It writes drawings, so it says how many and asks first.
        let ask = app.alerts.firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "A bake that adds drawings asks first")
        let sentence = ask.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(sentence.contains("9 drawings"), "It says how many it adds: \(sentence)")
        XCTAssertTrue(sentence.contains("undone"), "…and that it can be undone: \(sentence)")
        attachScreenshot(app, "3-the-prompt")
        ask.buttons["Bake"].tap()
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForNonExistence(timeout: 5), "The Repeat layer is gone")
        closeRail(app)

        // **What the timeline exposes**: a real block on every frame, and no ghosts.
        XCTAssertTrue(app.otherElements["timeline.cel.0.11"].waitForExistence(timeout: 8), "The loop was written out")
        XCTAssertEqual(bornBlocks(app), (0..<12).map { "\($0),1" }, "One drawing on each of the twelve frames")
        XCTAssertFalse(app.otherElements["timeline.repeatGhosts.0"].exists, "Nothing is looped now, so nothing is ghosted")

        // **What is drawn**: the loop's pictures, from drawings that are really there.
        for frame in [3, 4, 5, 7, 11] {
            tapBornLayer(app, blockStartingAt: frame, frame: frame)
            XCTAssertEqual(settledColumn(canvas, v0: 0.15, v1: 0.45, "frame \(frame + 1) after the bake") ?? -1,
                           columns[frame % 3], accuracy: 0.03,
                           "frame \(frame + 1) draws drawing \(frame % 3 + 1), now a drawing of its own")
        }
        attachScreenshot(app, "4-after-the-bake")

        // One press of Undo brings the Repeat layer, its ghosts and the three drawings back.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.otherElements["timeline.repeatGhosts.0"].waitForExistence(timeout: 8), "Undo loops again")
        XCTAssertTrue(app.otherElements["timeline.cel.0.11"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(bornBlocks(app), ["0,1", "1,1", "2,10"], "…over the three drawings it hid")
    }
}
