import XCTest

/// **The fill tool's two edge options, driven the way an artist reaches them** — from a fresh
/// document, through the fill menu, with what is *drawn* read back off the screen.
///
/// `FillMendLogicTests` and `FillBoundaryLogicTests` pin what each option does to the pixels. What
/// they cannot say is that an artist can find the option, that turning it on in the panel reaches the
/// render, and that the picture on screen changes — which is the half TODO (113) and (114) are
/// really about, and the half a model-level test has twice let ship unusable.
final class FillMendUITests: PaintUITestCase {

    private func screen(of element: XCUIElement) throws -> ScreenshotPixels {
        try XCTUnwrap(ScreenshotPixels(element.screenshot().image))
    }

    /// The native slider reports percent, while the caption reports truncated canvas pixels.
    /// Reach the physical clamp and require both normalized zero and the zero-pixel caption.
    private func setEdgeOverlapToZero(_ slider: XCUIElement, in app: XCUIApplication) {
        scrollFillPanel(app, to: slider)
        adjustSlider(slider, to: 0, tolerance: 0)
        XCTAssertEqual(slider.normalizedSliderPosition, 0,
                       "PREMISE: Edge Overlap is exactly 0% of its 0...6 px range, not a truncated subpixel value")
        XCTAssertTrue(app.staticTexts["Edge Overlap: 0 px"].exists,
                      "PREMISE: the panel exposes zero canvas pixels of Edge Overlap")
    }

    // MARK: - Mend Gaps between neighbouring fills

    /// A box with two dividers, line art on its own layer above the colour. The left cell is filled
    /// first and the middle one second, both with the option as the document starts it — **on** — and
    /// the right one after switching it off in the panel, so **the same screenshot carries both the
    /// control and the result**: the seam between the first two is closed by the default alone, and
    /// the one between the last two is the owner's *"tiny unfilled region directly under the line"*.
    /// With the line layer hidden, a pixel that is still paper is a pixel no fill covers.
    ///
    /// Edge Overlap is dragged to the bottom, and each divider is drawn three times, so the seam is several
    /// screen pixels wide rather than the sliver the default tucks under a single thin line.
    func testTheMendOptionIsOnFromAFreshDocumentAndClosesTheSeamBetweenTwoFills() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        let canvasSize = CGSize(width: 2048, height: 1024)
        XCTAssertTrue(launchIntoEditor(app, size: canvasSize))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Line art on a layer of its own, on top.
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        closeLayerRail(app)
        let paper = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        let left = Double(paper.minX + paper.width * 0.25)
        let right = Double(paper.minX + paper.width * 0.75)
        let top = Double(paper.minY + paper.height * 0.2)
        let bottom = Double(paper.minY + paper.height * 0.8)
        let middle = (top + bottom) / 2
        let dividers = [left + (right - left) / 3, left + (right - left) * 2 / 3]
        let seeds = [left + (right - left) / 6, (left + right) / 2, right - (right - left) / 6]
        drawLine(on: canvas, from: CGVector(dx: left, dy: top), to: CGVector(dx: right, dy: top))
        drawLine(on: canvas, from: CGVector(dx: right, dy: top), to: CGVector(dx: right, dy: bottom))
        drawLine(on: canvas, from: CGVector(dx: right, dy: bottom), to: CGVector(dx: left, dy: bottom))
        drawLine(on: canvas, from: CGVector(dx: left, dy: bottom), to: CGVector(dx: left, dy: top))
        // Each divider is three strokes a hair apart, so it is as wide as the seam needs to be seen and
        // **solid ink across its whole width**: two left a hairline of paper at one divider, and a mend
        // rightly never crosses paper — the seam there stayed open for a reason that had nothing to do
        // with the option under test.
        for x in dividers {
            for offset in [0.0, 0.00125, 0.0025] {
                drawLine(on: canvas, from: CGVector(dx: x + offset, dy: top), to: CGVector(dx: x + offset, dy: bottom))
            }
        }

        // The colour goes on the layer underneath.
        openLayerPanel(app)
        let colourRow = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(colourRow.waitForExistence(timeout: 5))
        colourRow.tap()
        closeLayerRail(app)

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap()   // selects the tool; the panel stays shut
        fillButton.tap()   // opens it
        let overlap = app.sliders["fillPanel.edgeOverlapSlider"]
        XCTAssertTrue(overlap.waitForExistence(timeout: 5))
        setEdgeOverlapToZero(overlap, in: app)
        fillButton.tap()   // shut, so the canvas takes the taps

        // Nobody has touched the option: the second fill meets the first under the line on the default.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: seeds[0], dy: middle)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: seeds[0], dy: middle), "The first cell fills")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: seeds[1], dy: middle)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: seeds[1], dy: middle), "The second cell fills")

        // Cold start, so the fill menu is the only place the option is reached: it reads on there, and
        // switching it off is what leaves the seam for the third fill. Another tool first, so the second
        // fill is settled — a switch flipped over a fill that is still adjustable re-runs *that* fill.
        app.buttons["toolbar.brushButton"].tap()
        fillButton.tap()   // selects the tool again
        fillButton.tap()   // opens the panel
        let mend = app.switches["fillPanel.mendGapToggle"]
        XCTAssertTrue(app.sliders["fillPanel.edgeOverlapSlider"].waitForExistence(timeout: 5), "The fill menu is open")
        scrollFillPanel(app, to: mend)
        XCTAssertTrue(mend.waitForExistence(timeout: 5), "The mend option is in the fill menu")
        XCTAssertEqual(mend.value as? String, "1", "On from a fresh document")
        // Its reach is its own slider, in this menu: live while the option is on, and 12 px by default —
        // not read off Gap Closing, whose slider is the rail's.
        let reach = app.sliders["fillPanel.mendReachSlider"]
        scrollFillPanel(app, to: reach)
        XCTAssertTrue(reach.waitForExistence(timeout: 5), "Mend Reach has a slider in the fill menu")
        XCTAssertTrue(reach.isEnabled, "…live, because the option is on")
        XCTAssertTrue(app.staticTexts["Mend Reach: 12 px"].exists, "…and reads 12 px by default")
        mend.tap()
        XCTAssertEqual(mend.value as? String, "0", "The option is off")
        XCTAssertFalse(reach.isEnabled, "…and Mend Reach does nothing while it is")
        fillButton.tap()

        canvas.coordinate(withNormalizedOffset: CGVector(dx: seeds[2], dy: middle)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: seeds[2], dy: middle), "The third cell fills")

        // Hide the line art: what is left is the colour layer, and a pixel that is still paper is one
        // no fill covers.
        openLayerPanel(app)
        let eye = app.buttons["layerPanel.row.1.visibility"]
        XCTAssertTrue(eye.waitForExistence(timeout: 5))
        eye.tap()
        closeLayerRail(app)
        Thread.sleep(forTimeInterval: 1.0)   // the canvas re-composites without the line layer

        let picture = try screen(of: canvas)
        let mended = picture.lightPixels(row: middle, from: dividers[0] - 0.007, to: dividers[0] + 0.0095)
        let unmended = picture.lightPixels(row: middle, from: dividers[1] - 0.007, to: dividers[1] + 0.0095)
        attachScreenshot(XCUIScreen.main, "mend-seams-line-art-hidden")
        XCTAssertGreaterThan(unmended, 0, "Control: with the option switched off the third fill leaves paper under the line")
        XCTAssertEqual(mended, 0, "On the default the second fill meets the first under the line — no paper left across the seam")
    }

    private struct InternalMendScene {
        let canvas: XCUIElement
        let seed: CGVector
        let attached: CGVector
        let detached: CGVector
        let caps: [(name: String, rect: CGRect)]
        let outline: CGVector
        let outside: CGVector
    }

    /// One cold document and one bucket fill. Both workflows read the colour layer with its line
    /// art hidden; the explicit reference remains on so the batch can use the same line art later.
    private func makeInternalMendScene(_ app: XCUIApplication, mendsGaps: Bool) throws -> InternalMendScene {
        let canvasSize = CGSize(width: 2048, height: 1024)
        XCTAssertTrue(launchIntoEditor(app, size: canvasSize))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        openLayerPanel(app)
        let layerList = app.tables["layerPanel.list"]
        let railIsVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard layerList.exists else { return false }
            let frame = layerList.frame
            let viewport = app.frame
            return !frame.isEmpty && viewport.contains(frame)
        }, object: layerList)
        XCTAssertEqual(XCTWaiter.wait(for: [railIsVisible], timeout: 5), .completed,
                       "PREMISE: the entire layer rail has entered the app before its row is tapped")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.isVector, true, "a fresh layer is vector")
        tapWhenHittable(app.staticTexts["layerPanel.row.0"], "The fresh vector layer's options row")
        XCTAssertTrue(app.buttons["layerOptions.rasterize"].waitForExistence(timeout: 5),
                      "the fresh vector layer's options offer Rasterize")
        attachScreenshot(XCUIScreen.main, "internal-mend-fresh-vector-options-owner-screen")
        app.buttons["layerOptions.rasterize"].tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.isVector, false)
        app.staticTexts["layerPanel.row.0"].tap() // Rasterize closes its menu.
        XCTAssertTrue(app.buttons["layerOptions.rename"].waitForExistence(timeout: 5), "the raster layer's menu is open")
        XCTAssertTrue(app.buttons["layerOptions.rasterize"].waitForNonExistence(timeout: 2))
        XCTAssertFalse(app.buttons["layerOptions.mendAllFills"].exists, "this edit is offered only on vector layers")
        app.buttons["layerOptions.close"].tap()
        addVectorLayerFromOpenPanel(app) // colour at 1
        addVectorLayerFromOpenPanel(app) // line art at 2
        closeLayerRail(app)
        setBrushSize(app, normalized: 0.025)
        app.buttons["toolbar.brushButton"].tap() // close the brushes menu left open by the size helper
        let paper = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        let left = Double(paper.minX + paper.width * 0.25)
        let right = Double(paper.minX + paper.width * 0.75)
        let top = Double(paper.minY + paper.height * 0.2)
        let bottom = Double(paper.minY + paper.height * 0.8)
        let middle = (top + bottom) / 2
        let branchStart = left + (right - left) * 0.45
        let detachedLeft = left + (right - left) * 0.18
        let detachedRight = left + (right - left) * 0.36
        let detachedRow = top + (bottom - top) * 0.32
        drawLine(on: canvas, from: CGVector(dx: left, dy: top), to: CGVector(dx: right, dy: top))
        drawLine(on: canvas, from: CGVector(dx: right, dy: top), to: CGVector(dx: right, dy: bottom))
        drawLine(on: canvas, from: CGVector(dx: right, dy: bottom), to: CGVector(dx: left, dy: bottom))
        drawLine(on: canvas, from: CGVector(dx: left, dy: bottom), to: CGVector(dx: left, dy: top))
        drawLine(on: canvas, from: CGVector(dx: branchStart, dy: middle), to: CGVector(dx: right, dy: middle))
        drawLine(on: canvas, from: CGVector(dx: detachedLeft, dy: detachedRow), to: CGVector(dx: detachedRight, dy: detachedRow))
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        closeLayerRail(app)
        setBrushColor(app, hex: "FF0000")
        XCTAssertTrue(openFillPanel(app))
        let overlap = app.sliders["fillPanel.edgeOverlapSlider"]
        setEdgeOverlapToZero(overlap, in: app)
        let mend = app.switches["fillPanel.mendGapToggle"]
        scrollFillPanel(app, to: mend)
        XCTAssertTrue(mend.waitForExistence(timeout: 5))
        let expectedToggle = mendsGaps ? "1" : "0"
        if mend.value as? String != expectedToggle { mend.tap() }
        XCTAssertEqual(mend.value as? String, expectedToggle, "the new fill uses the option set in its menu")
        app.buttons["toolbar.fillButton"].tap()
        let seed = CGVector(dx: left + (right - left) * 0.2, dy: top + (bottom - top) * 0.25)
        canvas.coordinate(withNormalizedOffset: seed).tap()
        XCTAssertTrue(waitUntil(canvas, seed, isRed), "the one new fill landed")
        app.buttons["toolbar.brushButton"].tap() // commit the adjustable fill

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap() // selected row opens its options and reference picker
        let lineReference = app.buttons["layerPanel.row.2.fillRefButton"]
        XCTAssertTrue(lineReference.waitForExistence(timeout: 5))
        if lineReference.value as? String == "1" { lineReference.tap() }
        lineReference.tap() // explicitly on, so hiding its eye cannot remove it as a reference
        XCTAssertEqual(lineReference.value as? String, "1")
        let colourReference = app.buttons["layerPanel.row.1.fillRefButton"]
        XCTAssertTrue(colourReference.waitForExistence(timeout: 5))
        if colourReference.value as? String == "1" { colourReference.tap() }
        app.buttons["layerPanel.row.2.visibility"].tap()
        app.buttons["layerOptions.close"].tap()
        closeLayerRail(app)
        // Square collars include each entire ~6 pt free cap and surrounding interior paint.
        // Their half-width is 2% of the enclosure (20.48 canvas points), well clear of its outline.
        let halfWidth = (right - left) * 0.02
        let halfHeight = halfWidth * Double(canvas.frame.width / canvas.frame.height)
        let caps = [("detached left", detachedLeft, detachedRow),
                    ("detached right", detachedRight, detachedRow),
                    ("attached free end", branchStart, middle)].map { name, x, y in
            (name: name, rect: CGRect(x: x - halfWidth, y: y - halfHeight,
                                     width: 2 * halfWidth, height: 2 * halfHeight))
        }
        let enclosure = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        for cap in caps {
            XCTAssertTrue(enclosure.contains(cap.rect), "PREMISE: \(cap.name) collar is inside the outline")
            assertAboveTheDock(app, canvas, dy: cap.rect.maxY, "the complete \(cap.name) collar")
        }
        let scene = InternalMendScene(canvas: canvas, seed: seed,
            attached: CGVector(dx: branchStart + (right - branchStart) * 0.4, dy: middle),
            detached: CGVector(dx: (detachedLeft + detachedRight) / 2, dy: detachedRow),
            caps: caps,
            outline: CGVector(dx: right, dy: top + (bottom - top) * 0.65),
            outside: CGVector(dx: right + (right - left) * 0.04, dy: middle))
        for (name, probe) in [("attached stroke", scene.attached), ("detached stroke", scene.detached),
                              ("outer outline", scene.outline), ("exterior paper", scene.outside)] {
            assertAboveTheDock(app, canvas, dy: probe.dy, "the \(name) probe")
        }
        attachScreenshot(XCUIScreen.main, "internal-mend-owner-screen")
        return scene
    }

    /// The artist's first fill already covers both internal stroke footprints with Mend ON. No
    /// layer-wide action or pre-existing destination paint can supply either patch.
    func testOneNewFillWithMendOnCoversDetachedAndAttachedInkWithoutGrowingItsOutline() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        let scene = try makeInternalMendScene(app, mendsGaps: true)
        XCTAssertTrue(waitUntil(scene.canvas, scene.attached, isRed), "one fill covers the attached interior stem")
        XCTAssertTrue(waitUntil(scene.canvas, scene.detached, isRed), "the same fill covers the detached interior stroke")
        XCTAssertTrue(isRed(rgbaPixel(of: scene.canvas, at: scene.seed)), "the original fill is still red")
        XCTAssertTrue(isWhitish(rgbaPixel(of: scene.canvas, at: scene.outline)), "the outer outline footprint stays bare")
        XCTAssertTrue(isWhitish(rgbaPixel(of: scene.canvas, at: scene.outside)), "exterior paper stays bare")
        let picture = try screen(of: scene.canvas)
        for cap in scene.caps {
            XCTAssertEqual(picture.pixelCount(in: cap.rect, matching: { !isRed($0) }), 0,
                           "one fill covers the complete \(cap.name) footprint and interior collar")
        }
        attachScreenshot(XCUIScreen.main, "mend-one-fill-on-line-art-hidden")
    }

    func testBucketOnAnotherVectorLayerCoversTheShortLineInsideADrawnCircle() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        let size = CGSize(width: 2048, height: 1024)
        XCTAssertTrue(launchIntoEditor(app, size: size))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // A roughly six-canvas-pixel brush is within the ordinary 12 px Mend Reach.
        setBrushSize(app, normalized: 0.025)
        app.buttons["toolbar.brushButton"].tap()
        let paper = visiblePaperRect(app, in: canvas, canvasSize: size)
        let host = canvas.frame
        let radiusY = paper.height * 0.28
        let radiusX = radiusY * host.height / host.width
        func point(_ x: CGFloat, _ y: CGFloat) -> CGVector {
            CGVector(dx: paper.midX + radiusX * x, dy: paper.midY + radiusY * y)
        }
        // Carry the same stroke just past its start so the freehand outline is closed.
        let circle = (0...76).map { step in
            let angle = CGFloat(step) * .pi / 36
            return logicalAppPoint(in: host, normalizedOffset: point(-cos(angle), sin(angle)))
        }
        try fingerStroke(through: circle)
        drawLine(on: canvas, from: point(-0.35, 0), to: point(0.35, 0))
        let line = point(0, 0)
        let outline = point(-1, 0)
        let seed = point(0, -0.55)
        let outside = [point(-1.15, 0), point(1.15, 0), point(0, -1.15), point(0, 1.15)]
        XCTAssertTrue(waitUntil(canvas, line, isInk), "PREMISE: a dark short line landed inside the circle")
        XCTAssertTrue(waitUntil(canvas, outline, isInk), "PREMISE: the reference circle's left edge is drawn")

        openLayerPanel(app)
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.strokes, 2,
                       "PREMISE: the outline and short line belong to one reference layer")
        addVectorLayerFromOpenPanel(app)
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.isVector, true,
                       "PREMISE: the new fill target is a different vector layer")
        closeLayerRail(app)
        setBrushColor(app, hex: "FF0000")

        let fillButton = app.buttons["toolbar.fillButton"]
        let overlap = app.sliders["fillPanel.edgeOverlapSlider"]
        let mend = app.switches["fillPanel.mendGapToggle"]
        let reach = app.sliders["fillPanel.mendReachSlider"]
        XCTAssertTrue(openFillPanel(app))
        // Zero overlap keeps the OFF control visible under the thin stroke.
        setEdgeOverlapToZero(overlap, in: app)
        scrollFillPanel(app, to: reach)
        XCTAssertTrue(app.staticTexts["Mend Reach: 12 px"].exists, "PREMISE: the reach is the default 12 px")
        XCTAssertEqual(mend.value as? String, "1", "PREMISE: Mend Gaps is on for the first bucket tap")
        fillButton.tap()
        XCTAssertTrue(overlap.waitForNonExistence(timeout: 5))

        canvas.coordinate(withNormalizedOffset: seed).tap()
        XCTAssertTrue(waitUntil(canvas, seed, isRed), "one bucket tap fills inside the reference circle")
        XCTAssertTrue(waitUntil(canvas, line, isRed), "the first fill also covers the short line")

        // The fill is above the reference, so its same live footprint reveals the line when off.
        XCTAssertTrue(openFillPanel(app))
        scrollFillPanel(app, to: mend)
        mend.tap()
        XCTAssertEqual(mend.value as? String, "0")
        fillButton.tap()
        XCTAssertTrue(overlap.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil(canvas, line, isInk), "with Mend Gaps off, the same fill leaves the line bare")
        XCTAssertTrue(isRed(rgbaPixel(of: canvas, at: seed)), "the surrounding fill remains on screen")
        attachScreenshot(XCUIScreen.main, "cross-layer-circle-mend-off")

        XCTAssertTrue(openFillPanel(app))
        scrollFillPanel(app, to: mend)
        mend.tap()
        XCTAssertEqual(mend.value as? String, "1")
        fillButton.tap()
        XCTAssertTrue(overlap.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil(canvas, line, isRed), "Mend Gaps covers the line again in the same live fill")
        app.buttons["toolbar.brushButton"].tap() // commit
        openLayerPanel(app)
        tapWhenHittable(app.buttons["layerPanel.row.0.visibility"], "Hide the reference circle and line")
        closeLayerRail(app)
        XCTAssertTrue(waitUntil(canvas, outline, isWhitish), "the hidden circle's own footprint stays unpainted")

        let upperLeft = point(-0.43, -0.08)
        let lowerRight = point(0.43, 0.08)
        let collar = CGRect(x: upperLeft.dx, y: upperLeft.dy, width: lowerRight.dx - upperLeft.dx,
                            height: lowerRight.dy - upperLeft.dy)
        let picture = try screen(of: canvas)
        attachScreenshot(XCUIScreen.main, "cross-layer-circle-mend-reference-hidden")
        XCTAssertEqual(picture.pixelCount(in: collar, matching: { !isRed($0) }), 0,
                       "the committed fill covers the complete line footprint, including both ends")
        for probe in outside {
            XCTAssertTrue(isWhitish(picture.pixel(normalizedX: probe.dx, normalizedY: probe.dy)),
                          "exterior paper stays clear around the circle")
        }
    }

    func testRecordedCircleMendsFromTheLayerUnderItsInk() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        let size = RecordedMendScene.canvasSize
        XCTAssertTrue(launchIntoEditor(app, size: size))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app) // fill target
        addVectorLayerFromOpenPanel(app) // reference ink above it
        closeLayerRail(app)
        openBrushLibrary(app)
        let opaque = app.buttons["brushPanel.brush.Opaque Round"]
        XCTAssertTrue(opaque.waitForExistence(timeout: 5))
        if !opaque.isSelected { tapWhenHittable(opaque, "Opaque Round") }
        openBrushEditor(app)
        let sizeSlider = app.sliders["brushPanel.sizeSlider"]
        adjustSlider(sizeSlider, to: 11.0 / 199, tolerance: 0.014)
        closeBrushEditor(app)
        app.buttons["toolbar.brushButton"].tap()

        let paper = paperRect(in: canvas, canvasSize: size)
        let frame = canvas.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> CGVector {
            let p = RecordedMendScene.canvasPoint(x, y)
            return onHost(paper, Double(p.x / size.width), Double(p.y / size.height))
        }
        for stroke in [RecordedMendScene.outline, RecordedMendScene.line] {
            let points = stroke.map { x, y, _ in logicalAppPoint(in: frame, normalizedOffset: at(x, y)) }
            try fingerStroke(through: points, interval: 0.032)
        }
        let center = at(644, 343)
        let seed = at(656, 255)
        let outline = at(432, 402.5)
        let exterior = at(409, 385)
        XCTAssertTrue(waitUntil(canvas, center, isInk), "the recorded line is drawn")
        XCTAssertTrue(waitUntil(canvas, outline, isInk), "the enclosing outline is drawn")
        openLayerPanel(app)
        let target = app.staticTexts["layerPanel.row.1"]
        tapWhenHittable(target, "The separate fill layer")
        closeLayerRail(app)
        setBrushColor(app, hex: "FF0000")
        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(openFillPanel(app))
        let reach = app.sliders["fillPanel.mendReachSlider"]
        scrollFillPanel(app, to: reach)
        XCTAssertTrue(app.staticTexts["Mend Reach: 12 px"].exists)
        XCTAssertEqual(app.switches["fillPanel.mendGapToggle"].value as? String, "1")
        fillButton.tap()
        canvas.coordinate(withNormalizedOffset: seed).tap()
        XCTAssertTrue(waitUntil(canvas, seed, isRed), "the first bucket tap fills the enclosed paper")
        app.buttons["toolbar.brushButton"].tap()
        openLayerPanel(app)
        tapWhenHittable(app.buttons["layerPanel.row.2.visibility"], "Hide the reference ink")
        closeLayerRail(app)
        XCTAssertTrue(waitUntil(canvas, outline, isWhitish), "the enclosing line's outer footprint stays clear")
        let picture = try screen(of: canvas)
        attachScreenshot(XCUIScreen.main, "recorded-circle-mend-reference-hidden")
        XCTAssertTrue(isRed(picture.pixel(normalizedX: center.dx, normalizedY: center.dy)),
                      "the committed fill below the line covers its body")
        XCTAssertTrue(isWhitish(picture.pixel(normalizedX: exterior.dx, normalizedY: exterior.dy)),
                      "paper beyond the enclosing circle stays clear")
    }

    /// Cold launch → saved vector fill with the option off → the vector layer action → one undo.
    /// The hidden line art remains an explicit reference, so the picture reads the fill itself.
    func testMendAllFillsIsVectorOnlyRepairsAnAttachedStemAndUndoesAsOneStep() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        let scene = try makeInternalMendScene(app, mendsGaps: false)
        XCTAssertTrue(waitUntil(scene.canvas, scene.attached, isWhitish), "PREMISE: Mend OFF leaves the attached stroke bare")
        XCTAssertTrue(waitUntil(scene.canvas, scene.detached, isWhitish), "PREMISE: Mend OFF also leaves the detached stroke bare")
        let before = try screen(of: scene.canvas)
        for cap in scene.caps {
            XCTAssertGreaterThan(before.pixelCount(in: cap.rect, matching: { isWhitish($0) }), 0,
                                 "PREMISE: Mend OFF leaves bare ink in the \(cap.name) collar")
        }
        attachScreenshot(XCUIScreen.main, "mend-all-before-line-art-hidden")

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        let action = app.buttons["layerOptions.mendAllFills"]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "the vector layer offers Mend All Fills beside Rasterize")
        XCTAssertTrue(action.isHittable)
        action.tap()
        closeLayerRail(app)
        XCTAssertTrue(waitUntil(scene.canvas, scene.attached, isRed, timeout: 20), "the action covers the attached stem")
        XCTAssertTrue(waitUntil(scene.canvas, scene.detached, isRed), "the action covers the detached stroke")
        XCTAssertTrue(isWhitish(rgbaPixel(of: scene.canvas, at: scene.outline)), "the outer outline footprint stays bare")
        XCTAssertTrue(isWhitish(rgbaPixel(of: scene.canvas, at: scene.outside)), "the outside edge stays fixed")
        let mended = try screen(of: scene.canvas)
        attachScreenshot(XCUIScreen.main, "mend-all-after-line-art-hidden")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(waitUntil(scene.canvas, scene.attached, isWhitish), "one undo restores the attached gap")
        XCTAssertTrue(waitUntil(scene.canvas, scene.detached, isWhitish), "the same undo restores the detached gap")
        XCTAssertTrue(isRed(rgbaPixel(of: scene.canvas, at: scene.seed)), "undo kept the original fill")
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertTrue(waitUntil(scene.canvas, scene.attached, isRed), "redo restores the attached stem")
        XCTAssertTrue(waitUntil(scene.canvas, scene.detached, isRed), "redo restores the detached stroke")
        let redone = try screen(of: scene.canvas)
        for (phase, picture) in [("Mend All", mended), ("redo", redone)] {
            for cap in scene.caps {
                XCTAssertEqual(picture.pixelCount(in: cap.rect, matching: { !isRed($0) }), 0,
                               "\(phase) covers the complete \(cap.name) footprint and interior collar")
            }
        }
    }

    // MARK: - (114) The extension buffer

    /// A canvas with padding, the boundary toggle on (it is by default), and a flood fill on blank
    /// paper: the colour stops at the paper's edge, and dragging the Extension Buffer slider — on the
    /// fill that is still adjustable — carries it out across the padding. The padding is grey on
    /// screen and the fill is black, so the band just inside the canvas's outer edge reads as one or
    /// the other.
    func testTheExtensionBufferSliderCarriesTheFillBoundaryIntoThePadding() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 2048, height: 2048)))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Padding first: it is the thing the buffer extends into, and a fresh canvas has none.
        app.buttons["toolbar.settingsButton"].tap()
        let padding = app.sliders["settings.paddingSlider"]
        XCTAssertTrue(padding.waitForExistence(timeout: 5))
        padding.adjust(toNormalizedSliderPosition: 0.2)
        // The padding is drawn over the artwork's ink by default (TODO (133)), veiled (TODO (180)), which
        // would dim the very band this test reads — so look at it with the cover off.
        let onTop = app.switches["settings.paddingOnTopToggle"]
        XCTAssertTrue(onTop.waitForExistence(timeout: 5))
        onTop.tap()
        XCTAssertEqual(onTop.value as? String, "0", "PREMISE: the cover is off, so ink in the padding shows")
        app.buttons["toolbar.settingsButton"].tap()
        Thread.sleep(forTimeInterval: 1.0)

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap()   // selects the tool
        fillButton.tap()   // opens the panel
        let buffer = app.sliders["fillPanel.canvasEdgeExtensionSlider"]
        XCTAssertTrue(app.sliders["fillPanel.edgeOverlapSlider"].waitForExistence(timeout: 5), "The fill menu is open")
        scrollFillPanel(app, to: buffer)
        XCTAssertTrue(buffer.waitForExistence(timeout: 5), "The extension buffer is in the fill menu")
        XCTAssertTrue(buffer.isEnabled, "…and live, because the canvas has padding and the boundary is on")
        fillButton.tap()

        // The visible canvas is the square the host letterboxes; the padding's outer 40% of itself is
        // a band on each side, so a point 1% of the visible width in from its edge is padding.
        let inPadding = onHost(paperRect(in: canvas), 0.01, 0.5)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "The flood fills the paper")
        let before = try screen(of: canvas)
        XCTAssertTrue(before.light(inPadding.dx, inPadding.dy), "With the buffer at 0 the padding is left alone")

        fillButton.tap()   // opens the panel again, still scrolled to where it was left
        XCTAssertTrue(app.sliders["fillPanel.edgeOverlapSlider"].waitForExistence(timeout: 5), "The fill menu is open")
        scrollFillPanel(app, to: buffer)
        buffer.adjust(toNormalizedSliderPosition: 1)
        fillButton.tap()
        // A wait, never an instant look: moving the paper's edge out is a new structure for the fill
        // (`MetalFillSession.Structure`), and the window grows with it, so the picture lands a press —
        // or a few — after the slider rather than a tick.
        var after = try screen(of: canvas)
        let deadline = Date().addingTimeInterval(10)
        while after.light(inPadding.dx, inPadding.dy), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            after = try screen(of: canvas)
        }
        attachScreenshot(XCUIScreen.main, "extension-buffer-at-the-padding")
        XCTAssertFalse(after.light(inPadding.dx, inPadding.dy),
                       "With the buffer at the padding's width the fill reaches out to the padded canvas's edge")
    }

    /// **The owner's November 16 case at the owner's size**: a 5000² document, the Rough Ink preset at
    /// 5 px (the slider's 0.1%), a circle and a line inside it on one layer, the fill tapped from
    /// another layer on an iPad 9 simulator in landscape with the iPad 9's memory budget — read off the
    /// screen with the reference hidden. At this size the first window's growth used to double into a
    /// 3,072² window that does not fit the budget, was worked at 0.71, and lost the mend entirely.
    ///
    /// **XCUITest cannot press a Pencil, so the pressure variation is not here**; a finger draws at one
    /// pressure and Rough Ink's own random size row makes the width vary along the line.
    /// `FillMendLogicTests.testTheOwnersRecordedRoughInkLineIsMendedOnA5000Canvas` carries the recorded
    /// pressures.
    func testRoughInkCircleAndLineOnA5000CanvasFillSolidUnderTheLineFromAnotherLayer() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestTextureBudgetBytes", "201326592"]
        let size = CGSize(width: 5000, height: 5000)
        XCTAssertTrue(launchIntoEditor(app, size: size, orientationBeforeCreatingCanvas: .landscapeLeft))
        defer { XCUIDevice.shared.orientation = .portrait }
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openBrushLibrary(app)
        let rough = app.buttons["brushPanel.brush.Rough Ink"]
        XCTAssertTrue(rough.waitForExistence(timeout: 5))
        if !rough.isSelected { tapWhenHittable(rough, "Rough Ink") }
        setBrushSize(app, normalized: 4.0 / 199)
        app.buttons["toolbar.brushButton"].tap()

        let paper = visiblePaperRect(app, in: canvas, canvasSize: size)
        let host = canvas.frame
        let radiusY = paper.height * 0.34
        let radiusX = radiusY * host.height / host.width
        func point(_ x: CGFloat, _ y: CGFloat) -> CGVector {
            CGVector(dx: paper.midX + radiusX * x, dy: paper.midY + radiusY * y)
        }
        let circle = (0...76).map { step in
            let angle = CGFloat(step) * .pi / 36
            return logicalAppPoint(in: host, normalizedOffset: point(-cos(angle), sin(angle)))
        }
        try fingerStroke(through: circle)
        let lineFrom = point(0.45, -0.45), lineTo = point(-0.4, 0.5)
        try fingerStroke(through: (0...24).map { step in
            let t = CGFloat(step) / 24
            return logicalAppPoint(in: host, normalizedOffset: CGVector(
                dx: lineFrom.dx + (lineTo.dx - lineFrom.dx) * t, dy: lineFrom.dy + (lineTo.dy - lineFrom.dy) * t))
        }, interval: 0.03)
        let seed = point(0.7, -0.1)
        let outline = point(-1, 0)
        XCTAssertTrue(waitUntil(canvas, outline, isInk), "PREMISE: the circle's left edge is drawn")

        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        closeLayerRail(app)
        setBrushColor(app, hex: "FF0000")
        XCTAssertTrue(openFillPanel(app))
        let mend = app.switches["fillPanel.mendGapToggle"]
        scrollFillPanel(app, to: mend)
        XCTAssertEqual(mend.value as? String, "1", "PREMISE: Mend Gaps is on at its default")
        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: seed).tap()
        XCTAssertTrue(waitUntil(canvas, seed, isRed, timeout: 60), "one bucket tap fills inside the circle")
        app.buttons["toolbar.brushButton"].tap() // commit
        openLayerPanel(app)
        tapWhenHittable(app.buttons["layerPanel.row.0.visibility"], "Hide the circle and line")
        closeLayerRail(app)
        XCTAssertTrue(waitUntil(canvas, outline, isWhitish, timeout: 20), "the hidden circle's own footprint stays unpainted")
        let picture = try screen(of: canvas)
        attachScreenshot(XCUIScreen.main, "rough-ink-5000-circle-and-line-reference-hidden")

        // Walk the line's middle 80%: no paper within two screen pixels either side of its centre.
        let pw = Double(picture.width), ph = Double(picture.height)
        var gaps: [Double] = []
        for step in 0...40 {
            let t = 0.1 + 0.8 * Double(step) / 40
            let cx = Double(lineFrom.dx) + Double(lineTo.dx - lineFrom.dx) * t
            let cy = Double(lineFrom.dy) + Double(lineTo.dy - lineFrom.dy) * t
            let sample = (-2...2).contains { off in
                // Perpendicular offsets, in screen pixels, along x and y alike: the line is diagonal.
                [(Double(off), 0.0), (0.0, Double(off))].contains { dx, dy in
                    isWhitish(picture.pixel(normalizedX: cx + dx / pw, normalizedY: cy + dy / ph))
                }
            }
            if sample { gaps.append(t) }
        }
        XCTAssertTrue(gaps.isEmpty, "the fill leaves paper under the line at \(gaps.count) of 41 points along it: \(gaps)")
        XCTAssertTrue(isRed(picture.pixel(normalizedX: seed.dx, normalizedY: seed.dy)), "the fill is red")
        for outside in [point(-1.2, 0), point(1.2, 0), point(0, -1.2), point(0, 1.2)] {
            XCTAssertTrue(isWhitish(picture.pixel(normalizedX: outside.dx, normalizedY: outside.dy)),
                          "paper beyond the circle stays clear")
        }
    }

}

private extension ScreenshotPixels {
    /// Every displayed native pixel center in a host-normalized rectangle, through the shared reader.
    func pixelCount(in rect: CGRect, matching matches: (RGBA) -> Bool) -> Int {
        let columns = Int(floor(Double(rect.minX) * Double(width)))..<Int(ceil(Double(rect.maxX) * Double(width)))
        let rows = Int(floor(Double(rect.minY) * Double(height)))..<Int(ceil(Double(rect.maxY) * Double(height)))
        return rows.reduce(0) { total, y in
            total + columns.filter { x in
                matches(pixel(normalizedX: (Double(x) + 0.5) / Double(width),
                              normalizedY: (Double(y) + 0.5) / Double(height)))
            }.count
        }
    }

    func light(_ dx: Double, _ dy: Double) -> Bool {
        let p = pixel(normalizedX: dx, normalizedY: dy)
        return p.r > 150 && p.g > 150 && p.b > 150
    }

    func lightPixels(row dy: Double, from x0: Double, to x1: Double, steps: Int = 400) -> Int {
        (0...steps).filter { light(x0 + (x1 - x0) * Double($0) / Double(steps), dy) }.count
    }
}
