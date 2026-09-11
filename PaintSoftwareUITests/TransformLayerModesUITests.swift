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
///    appears on frame 2 (ruling 13).
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

    /// **The paper's edges in host-normalised coordinates, found by walking out from the host's
    /// centre**, not estimated from the host's aspect and not the extent of every whitish pixel.
    /// `canvas.host` is the whole screen under the toolbars: its screenshot carries the left rail's
    /// white knobs and the top bar's white circle, so a whitish-extent scan reads 0.03…0.97 across;
    /// `visibleCanvasBounds` assumes a square canvas filling the shorter side, which this document
    /// is not; and **the canvas re-fits when the layer rail opens and closes**, so two screenshots
    /// are only comparable in coordinates relative to the paper each one shows. The paper is one
    /// solid white rectangle with the host's centre inside it, so its edges are where whitish stops
    /// along the centre row and the centre column.
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
    private func closeRail(_ app: XCUIApplication) {
        let list = app.tables["layerPanel.list"]
        if list.exists {
            app.buttons["toolbar.layersButton"].tap()
            _ = list.waitForNonExistence(timeout: 5)
        }
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
        let menu = app.buttons["timeline.menu.Add Keyframe"]
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
        attach(app, "1-parallax-item-list")

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
        attach(app, "2-parallax-after-the-drag")

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
        attach(app, "0-launch")

        // A band a quarter of the paper right of its centre, on the centre row.
        let at = hostPoint(blank.paper, u: 0.75, v: 0.5)
        drawBand(on: canvas, x: Double(at.dx), y: Double(at.dy), halfHeight: 0.04)
        attach(app, "0-band-drawn")
        guard let rest = currentPaper(canvas, "after drawing"),
              let restCentroid = inkCentroid(rest.pixels, in: paperRegion(rest.paper, v0: 0.04, v1: 0.96))
                  .map({ paperRelative($0, in: rest.paper) }) else {
            return XCTFail("The band did not land: paper at launch \(blank.paper), drawn at \(at)")
        }
        XCTAssertEqual(restCentroid.u, 0.75, accuracy: 0.04, "Sanity: the band is right of centre")
        XCTAssertEqual(restCentroid.v, 0.5, accuracy: 0.04, "Sanity: …on the centre row")
        // The paper's aspect, which is what a quarter turn trades width for height by.
        let aspect = (rest.paper.maxX - rest.paper.minX) * Double(rest.pixels.width)
            / ((rest.paper.maxY - rest.paper.minY) * Double(rest.pixels.height))

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
        closeRail(app)

        // At the bar's first frame nothing has turned yet.
        scrub(app, toFrame: 1, total: total)
        attach(app, "1b-at-frame-1")
        guard let first = currentPaper(canvas, "at the first frame"),
              let atFirst = inkCentroid(first.pixels, in: paperRegion(first.paper, v0: 0.04, v1: 0.96))
                  .map({ paperRelative($0, in: first.paper) }) else {
            return XCTFail("The band vanished at the first frame")
        }
        XCTAssertEqual(atFirst.u, restCentroid.u, accuracy: 0.03,
                       "frame 1: the band is where it was drawn (paper \(first.paper), rest paper \(rest.paper))")
        XCTAssertEqual(atFirst.v, restCentroid.v, accuracy: 0.03)

        // Six frames in: a quarter turn clockwise puts what was to the right of centre below it —
        // as far below, in canvas units, as it was to the right.
        scrub(app, toFrame: 7, total: total)
        let expectedU = 0.5 - (restCentroid.v - 0.5) / aspect
        let expectedV = 0.5 + (restCentroid.u - 0.5) * aspect
        // The posed frame reaches the canvas through the compositor a beat after the scrub, so the
        // probe is repeated until the picture settles — and reports the last reading if it never does.
        var atSeventh = atFirst
        let deadline = Date().addingTimeInterval(8)
        repeat {
            guard let turned = currentPaper(canvas, "at the seventh frame"),
                  let read = inkCentroid(turned.pixels, in: paperRegion(turned.paper, v0: 0.04, v1: 0.96))
                      .map({ paperRelative($0, in: turned.paper) }) else {
                return XCTFail("The band vanished at the seventh frame")
            }
            atSeventh = read
            if abs(read.u - expectedU) < 0.04, abs(read.v - expectedV) < 0.04 { break }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        attach(app, "2-rotate-six-frames-in")
        XCTAssertEqual(atSeventh.u, expectedU, accuracy: 0.04,
                       "frame 7: the band is on the centre column — turned about the box's centre, not slid")
        XCTAssertEqual(atSeventh.v, expectedV, accuracy: 0.04,
                       "frame 7: …and below it, as far below as it was to the right (aspect \(aspect))")
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
        attach(app, "1-shake-amplitude-typed")
        closeRail(app)

        // **What is drawn**: on the bar's first four frames the band is somewhere else — 300 points
        // of a 2048-point canvas is up to a seventh of the paper — and the same somewhere else when
        // the playhead comes back to the first frame.
        let frames = [1, 2, 3, 4]
        guard let first = bandColumns(app, canvas: canvas, frames: frames, total: total, "first pass") else { return }
        attach(app, "2-shake-frame-4")
        XCTAssertTrue(first.contains { abs($0 - restU) > 0.01 },
                      "the band moved on at least one of the first four frames: \(first) against rest \(restU)")
        // Two frames suffice for the determinism check (the noise either re-rolls per render or it
        // does not); four are read where a single near-zero sample could hide a real difference.
        guard let again = bandColumns(app, canvas: canvas, frames: Array(frames.prefix(2)), total: total, "second pass") else { return }
        for (a, b) in zip(first, again) {
            XCTAssertEqual(a, b, accuracy: 0.004, "the same frame draws the same picture on the way back: \(first) vs \(again)")
        }

        // Re-roll: a new shake. The panel is reached through the layer's row again.
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let reroll = app.buttons["layerOptions.shakeReroll"]
        XCTAssertTrue(reroll.waitForExistence(timeout: 5), "the options reopen on the shake rows")
        reroll.tap()
        closeRail(app)
        guard let rerolled = bandColumns(app, canvas: canvas, frames: frames, total: total, "after re-roll") else { return }
        attach(app, "3-shake-rerolled-frame-4")
        XCTAssertTrue(zip(first, rerolled).contains { abs($0 - $1) > 0.01 },
                      "Re-roll drew a different picture on at least one frame: \(first) vs \(rerolled)")

        // One undo: the old shake, exactly.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        guard let restored = bandColumns(app, canvas: canvas, frames: Array(frames.prefix(2)), total: total, "after undo") else { return }
        attach(app, "4-shake-undone-frame-4")
        for (a, b) in zip(first, restored) {
            XCTAssertEqual(a, b, accuracy: 0.004, "one undo brings the old shake back: \(first) vs \(restored)")
        }
    }

    // MARK: - Repeat

    /// The born layer's block whose value starts at `start` — the array index moves under a split,
    /// so the block is found by what it says rather than by where it is.
    private func bornCel(_ app: XCUIApplication, startingAt start: Int) -> XCUIElement? {
        for celIndex in 0..<6 {
            let cel = app.otherElements["timeline.cel.0.\(celIndex)"]
            guard cel.exists, let value = cel.value as? String else { continue }
            if value.split(separator: ",").first.map(String.init) == "\(start)" { return cel }
        }
        return nil
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

    /// **Three drawings on frames 1, 2 and 3, a transform layer above, Mode → Repeat, type 3, and
    /// frame 5 shows frame 2's picture; the timeline ghosts the repeated frames; and a line drawn on
    /// frame 5 appears on frame 2** — §5.5 and rulings 11–13, off the screen. The born layer's
    /// twelve-frame block is cut twice through the cel menu so the three frames are three drawings;
    /// the period field is the exposed operand (pre-filled to 12, where the held third drawing ends,
    /// then typed to 3); the ghost band's value is read off the born layer's row.
    func testRepeatShowsFrameTwoOnFrameFiveGhostsTheLoopAndRedirectsInkToTheFrameItRepeats() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        guard let total = readFrameLabel(app)?.total else { return XCTFail("No frame label") }
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
            guard let paper = currentPaper(canvas, "frame \(frame + 1) before drawing") else { return }
            let at = hostPoint(paper.paper, u: u, v: 0.3)
            drawBand(on: canvas, x: Double(at.dx), y: Double(at.dy), halfHeight: 0.04)
            let read = settledColumn(canvas, v0: 0.15, v1: 0.45, "frame \(frame + 1) after drawing")
            XCTAssertEqual(read ?? -1, u, accuracy: 0.03, "Sanity: frame \(frame + 1)'s band is at \(u)")
        }
        attach(app, "1-three-drawings")

        // The layer, from +, then Mode → Repeat. The period is pre-filled from where the drawings
        // beneath end — the third block is held to 12 — and typed to 3.
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        pickMode(app, layerIndex: 1, mode: "repeat")
        let field = app.textFields["layerOptions.repeatPeriod.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Repeat puts the period field on the panel")
        XCTAssertEqual(field.value as? String, "12", "pre-filled from where the drawings beneath end")
        field.tap()
        field.typeText("3\n")
        let readout = app.staticTexts["layerOptions.repeatPeriodReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertEqual(readout.label, "3 frames", "the readout echoes the typed length")
        attach(app, "2-repeat-period-typed")
        closeRail(app)

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
        attach(app, "3-frame-5-shows-frame-2")

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
        attach(app, "4-ink-from-frame-5-on-frame-2")
        scrub(app, toFrame: 3, total: total)
        XCTAssertNil(settledColumn(canvas, v0: 0.5, v1: 0.8, "at frame 3"), "frame 3 did not receive it")
    }
}
