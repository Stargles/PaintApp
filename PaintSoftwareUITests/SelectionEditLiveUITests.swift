import XCTest

/// **A recolour follows the finger without a document write per tick, and lands without a flash** —
/// TODO (173), from a new document. The owner's iPad 9 lost its render server twice in a minute
/// recolouring fills with Select's Edit: every colour tick was a document write, and a document write
/// is a bake, a live pair, an onion skin and a canvas-sized picture for Core Animation, ten times a
/// second. `LiveElementEditLogicTests` pins the model (a tick writes nothing, the window's picture is
/// the written canvas's); this pins what the artist sees of it.
///
/// **On a document the compositor draws** (a blending layer), because that is where the canvas rests
/// on a baked frame with the old colours in it and where a tick used to re-bake it — the owner's
/// document, and `FillSliderLiveUITests`' arrangement for the same reason.
final class SelectionEditLiveUITests: PaintUITestCase {

    /// Two red lines, the first lassoed — the geometry `SelectionEditUITests` reads its colour test off.
    private struct Scene {
        let canvas: XCUIElement
        let l1Mid: CGVector, l2Mid: CGVector, l1Clear: CGVector
        let screenProbe: (CGVector) -> CGPoint
    }

    private func openThePicker(_ app: XCUIApplication, blending: Bool) throws -> (Scene, XCUIElement) {
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        // 1. Two red lines — the Select panel's own geometry, so the picker has room beside the first.
        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.6)
        drawLine(on: canvas, from: at(0.12, 0.22), to: at(0.38, 0.22))
        drawLine(on: canvas, from: at(0.60, 0.22), to: at(0.86, 0.22))
        let l1Mid = at(0.25, 0.22), l2Mid = at(0.73, 0.22)
        XCTAssertTrue(waitUntil(canvas, l1Mid, isRed), "PREMISE: the first red line is on screen")
        XCTAssertTrue(waitUntil(canvas, l2Mid, isRed), "PREMISE: the second red line is on screen")
        if blending {
            setBlendMode(app, layerIndex: 0, to: "multiply")
            XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 20,
                                               "Setup: a blending layer puts the canvas on the baked frame"))
        }

        // 2. Lasso the first line, Edit, the swatch — what the artist does next at every step.
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        openSelectionEditBand(app)
        let swatch = app.buttons["selectPanel.colourSwatch"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the loop raised the colour swatch")
        swatch.tap()
        let picker = app.descendants(matching: .any)["canvasPresentation.selectionColour"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the swatch opens the picker")

        // The part of the first line right of the picker is the line's own; read there.
        let host = canvas.frame
        let lineEndX = host.minX + host.width * CGFloat(at(0.38, 0.22).dx)
        XCTAssertLessThan(picker.frame.maxX + 12, lineEndX,
                          "PREMISE: some of the line is clear of the picker (picker \(picker.frame))")
        let l1Clear = CGVector(dx: Double((picker.frame.maxX + lineEndX) / 2 - host.minX) / Double(host.width),
                               dy: at(0.25, 0.22).dy)
        let scene = Scene(canvas: canvas, l1Mid: l1Mid, l2Mid: l2Mid, l1Clear: l1Clear,
                          screenProbe: { CGPoint(x: host.minX + host.width * $0.dx,
                                                 y: host.minY + host.height * $0.dy) })
        return (scene, picker)
    }

    /// The two lines, each a strip of its own, as flat RGBA8 — cropped to the paper, so the timeline's
    /// thumbnail (regenerated on a debounce, and legitimately different between two moments) is not
    /// in the comparison, and to *between* the selection's edges, so the loop's marching ants are not
    /// either: both move between any two shots. `UnlandedInkUITests.canvasBytes`' reasoning.
    private func lineBytes(_ canvas: XCUIElement) -> [UInt8] {
        guard let cg = canvas.screenshot().image.cgImage else { return [] }
        let paper = paperRect(in: canvas)
        func strip(_ x: ClosedRange<Double>) -> [UInt8] {
            let region = CGRect(x: CGFloat(cg.width) * (paper.minX + x.lowerBound * paper.width),
                                y: CGFloat(cg.height) * (paper.minY + 0.18 * paper.height),
                                width: CGFloat(cg.width) * (x.upperBound - x.lowerBound) * paper.width,
                                height: CGFloat(cg.height) * 0.08 * paper.height)
            guard let cropped = cg.cropping(to: region) else { return [] }
            return CanvasFixture.rgbaBytes(cropped) ?? []
        }
        return strip(0.10...0.40) + strip(0.58...0.88)
    }

    // MARK: - Following the finger

    /// **The picker's ring, dragged for four seconds: the line turns while the finger is down, almost
    /// no SwiftUI pass reaches the canvas, and the line outside the loop never moved.**
    ///
    /// Operands: the line's pixel sampled from another thread mid-drag (XCUITest's drag is
    /// synchronous, so an expectation built before it cannot fire during it), against red; the
    /// canvas's own `passes:` and `moves:` counters across the drag — `moves` is the held picture
    /// reaching the host, `passes` is what each tick used to be one of.
    func testDraggingThePickerOnABlendingDocumentRecoloursLiveWithoutAPassPerTick() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let (scene, picker) = try openThePicker(app, blending: true)
        XCTAssertTrue(waitForSandwichState(app, "live", timeout: 20,
                                           "the open picker engages the live pair, so the first tick has a host to draw in"))
        attachScreenshot(app, "1-picker-open-on-a-blending-document")

        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "the picker's hue ring")
        Thread.sleep(forTimeInterval: 1)
        let passesBefore = try XCTUnwrap(Int(readField(app, "passes:")), "the canvas publishes `passes:`")
        let movesBefore = try XCTUnwrap(Int(readField(app, "moves:")), "the canvas publishes `moves:`")

        let f = ring.frame
        let centre = CGPoint(x: f.midX, y: f.midY)
        let radius = min(f.width, f.height) * 0.42
        func point(_ angle: Double) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: centre.x - f.minX + radius * cos(angle), dy: centre.y - f.minY + radius * sin(angle)))
        }
        let sampler = MidGestureSampler(points: [scene.screenProbe(scene.l1Clear), scene.screenProbe(scene.l2Mid)])
        sampler.start()
        let start = Date()
        var angle = 0.0
        while Date().timeIntervalSince(start) < 4 {
            point(angle).press(forDuration: 0.05, thenDragTo: point(angle + 1.2), withVelocity: .slow,
                               thenHoldForDuration: 0.05)
            angle += 1.2
        }
        let returned = CFAbsoluteTimeGetCurrent()
        let taken = sampler.stop()

        let passes = try XCTUnwrap(Int(readField(app, "passes:"))) - passesBefore
        let moves = try XCTUnwrap(Int(readField(app, "moves:"))) - movesBefore
        XCTAssertGreaterThanOrEqual(moves, 3, "the held picture reached the host \(moves) times across the drag")
        XCTAssertLessThanOrEqual(passes, 2, "\(passes) SwiftUI passes reached the canvas across the drag — "
                                 + "a tick that writes the document is one pass each")
        let midDrag = taken.filter { $0.finished < returned - 1.0 }.map(\.pixels)
        XCTAssertFalse(midDrag.isEmpty, "the screen could not be sampled while the finger was down")
        XCTAssertTrue(midDrag.contains { ($0[0]).map { !isRed($0) && !isWhitish($0) } ?? false },
                      "while the finger was still on the ring the line never changed colour — the held "
                      + "picture did not reach the screen (\(midDrag.count) mid-drag samples)")
        XCTAssertTrue(midDrag.allSatisfy { isRed($0[1]) },
                      "the line outside the loop changed colour while the finger was down")
        attachScreenshot(app, "2-after-the-drag-before-lift")

        // 3. Lift. What the artist does next: tap away — one undo step.
        let hexField = app.textFields["colorPanel.hexField"]
        let pickedHex = hexField.value as? String ?? ""
        tapAway(app)
        XCTAssertTrue(hexField.waitForNonExistence(timeout: 5), "tapping outside closes the picker")
        XCTAssertFalse(isRed(rgbaPixel(of: scene.canvas, at: scene.l1Mid)),
                       "the line keeps the picked colour (\(pickedHex)) after the picker closes")
        XCTAssertTrue(isRed(rgbaPixel(of: scene.canvas, at: scene.l2Mid)), "and the other line never moved")
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(waitUntil(scene.canvas, scene.l1Mid, isRed), "one undo puts the line's red back")
        attachScreenshot(app, "3-undone")
    }

    // MARK: - Landing

    /// **At lift the picked colour is on screen before the render of the written list lands.** The
    /// render is slowed (`-uiTestSlowVectorRenderMillis`) so the window between the commit and the new
    /// base is long enough for a screenshot; the window's last picture stands in for it as held ink,
    /// and when the base lands and the held picture retires the canvas does not change.
    ///
    /// Operands: the line's pixel right after the picker closes, against the colour it started as;
    /// then the whole canvas before and after the base lands.
    ///
    /// Mutation caught: taking the window down without holding its picture (`takeDownHeldEdit` with
    /// `landing: false`) leaves the old red on screen for the length of the render — the first
    /// assertion goes red.
    func testTheLastTicksPictureStaysUpUntilTheRenderOfTheWrittenListLands() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSlowVectorRenderMillis", "3000"]
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let (scene, _) = try openThePicker(app, blending: false)
        // The drawing's own renders are slow too; let them land so the base is the red one.
        Thread.sleep(forTimeInterval: 10)

        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5))
        setHexField(app, hexField, to: "0000FF")
        XCTAssertTrue(waitUntil(scene.canvas, scene.l1Clear, isBlue),
                      "with the picker still open the lassoed line turns blue")
        tapAway(app)
        XCTAssertTrue(hexField.waitForNonExistence(timeout: 5), "tapping outside closes the picker")
        // The picker is gone and the written list's render is still sleeping: what the artist sees is
        // held ink.
        let held = lineBytes(scene.canvas)
        attachScreenshot(app, "1-picker-closed-render-still-pending")
        XCTAssertTrue(isBlue(rgbaPixel(of: scene.canvas, at: scene.l1Mid)),
                      "the line is blue at the moment the picker closes, before the base has re-rendered — "
                      + "the old red is showing through a window that went away too early")
        XCTAssertTrue(isRed(rgbaPixel(of: scene.canvas, at: scene.l2Mid)), "and the other line never moved")

        Thread.sleep(forTimeInterval: 10)
        attachScreenshot(app, "2-after-the-render-landed")
        let landed = lineBytes(scene.canvas)
        let worst = worstChannelDifference(held, landed)
        XCTAssertLessThanOrEqual(worst, 8,
                                 "the canvas must not change when the base takes the picture over from the held "
                                 + "ink — the artist should not be able to tell which is drawing (worst channel \(worst))")
        XCTAssertTrue(isBlue(rgbaPixel(of: scene.canvas, at: scene.l1Mid)), "and the line is still blue")
    }
}
