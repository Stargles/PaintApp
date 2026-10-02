import XCTest

/// **The fill tool's two edge options, driven the way an artist reaches them** — from a fresh
/// document, through the fill menu, with what is *drawn* read back off the screen.
///
/// `FillMendLogicTests` and `FillBoundaryLogicTests` pin what each option does to the pixels. What
/// they cannot say is that an artist can find the option, that turning it on in the panel reaches the
/// render, and that the picture on screen changes — which is the half TODO (113) and (114) are
/// really about, and the half a model-level test has twice let ship unusable.
final class FillMendUITests: PaintUITestCase {

    /// Brightness of one pixel of a screenshot, 0...765.
    private struct Screen {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        func light(_ dx: Double, _ dy: Double) -> Bool {
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            let o = (y * width + x) * 4
            return bytes[o] > 150 && bytes[o + 1] > 150 && bytes[o + 2] > 150
        }
        /// How many of `steps` samples across `x0...x1` on row `dy` are paper.
        func lightPixels(row dy: Double, from x0: Double, to x1: Double, steps: Int = 400) -> Int {
            (0...steps).filter { light(x0 + (x1 - x0) * Double($0) / Double(steps), dy) }.count
        }
    }

    private func screen(of element: XCUIElement) throws -> Screen {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Screen(bytes: buffer, width: width, height: height)
    }

    /// Brings a control of the open fill panel into view. The panel is a scroll view of its own that
    /// holds more than its height, and **a swipe has to start on it** — one aimed at "the first scroll
    /// view" lands on the canvas, where a vertical drag is the fill tool's own Gap Closing gesture.
    ///
    /// **Anchored on the scroll view's own frame, and in its left gutter.** The frame stays put while
    /// the rows move, where a row's frame (the title's, which an earlier version offset from) scrolls
    /// off the top and carries the swipe's start with it — onto a slider, which a drag moves rather
    /// than scrolls. The gutter holds no control at all, so the swipe scrolls whatever is under it.
    private func scrollFillPanel(_ app: XCUIApplication, to control: XCUIElement) {
        let panel = app.scrollViews.containing(.staticText, identifier: "Fill").firstMatch
        var drags = 0
        while !(control.exists && control.isHittable) && drags < 8, panel.exists {
            let frame = panel.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: frame.minX + 6, dy: frame.midY + frame.height * 0.35))
            let to = origin.withOffset(CGVector(dx: frame.minX + 6, dy: frame.midY - frame.height * 0.35))
            from.press(forDuration: 0.1, thenDragTo: to)
            drags += 1
        }
    }

    // MARK: - (113) Mend Gap to Neighbouring Fill

    /// A box with two dividers, line art on its own layer above the colour. The left cell is filled
    /// with the option off, the middle one with it still off, and the right one after switching it on
    /// in the panel — so **the same screenshot carries both the control and the result**: the seam
    /// between the first two is the owner's *"tiny unfilled region directly under the line"*, and the
    /// one between the last two is not there. With the line layer hidden, a pixel that is still paper
    /// is a pixel no fill covers.
    ///
    /// Edge Overlap is dragged to the bottom, and each divider is drawn twice, so the seam is several
    /// screen pixels wide rather than the sliver the default tucks under a single thin line.
    func testTheMendOptionInTheFillMenuClosesTheSeamBetweenTwoFills() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Line art on a layer of its own, on top.
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        closeLayerRail(app)
        let left = 0.25, right = 0.75, top = 0.3, bottom = 0.7
        let dividers = [0.4167, 0.5833]
        drawLine(on: canvas, from: CGVector(dx: left, dy: top), to: CGVector(dx: right, dy: top))
        drawLine(on: canvas, from: CGVector(dx: right, dy: top), to: CGVector(dx: right, dy: bottom))
        drawLine(on: canvas, from: CGVector(dx: right, dy: bottom), to: CGVector(dx: left, dy: bottom))
        drawLine(on: canvas, from: CGVector(dx: left, dy: bottom), to: CGVector(dx: left, dy: top))
        // Each divider is two strokes a hair apart, so it is as wide as the seam needs to be seen.
        for x in dividers {
            for offset in [0.0, 0.0025] {
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
        // `adjust` leaves a thumb-width of travel unreached, so the first pass stops short of 0.
        for _ in 0..<5 where sliderNumericValue(overlap) > 0.5 {
            overlap.adjust(toNormalizedSliderPosition: 0)
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertLessThanOrEqual(sliderNumericValue(overlap), 1, "Edge Overlap is down at the bottom, so the seam is most of the line")
        fillButton.tap()   // shut, so the canvas takes the taps

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.333, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.333, dy: 0.5), "The first cell fills")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "The second cell fills")

        // Switch the option on in the fill menu — cold start, so this is the only way it is reached.
        fillButton.tap()
        let mend = app.switches["fillPanel.mendGapToggle"]
        XCTAssertTrue(app.sliders["fillPanel.edgeOverlapSlider"].waitForExistence(timeout: 5), "The fill menu is open")
        scrollFillPanel(app, to: mend)
        XCTAssertTrue(mend.waitForExistence(timeout: 5), "The mend option is in the fill menu")
        XCTAssertEqual(mend.value as? String, "0", "Off until the artist asks")
        // Its reach is its own slider, in this menu: there from the start, dim until the option is on,
        // and 12 px by default — not read off Gap Closing, whose slider is the rail's.
        let reach = app.sliders["fillPanel.mendReachSlider"]
        scrollFillPanel(app, to: reach)
        XCTAssertTrue(reach.waitForExistence(timeout: 5), "Mend Reach has a slider in the fill menu")
        XCTAssertFalse(reach.isEnabled, "…which does nothing while the option is off")
        XCTAssertTrue(app.staticTexts["Mend Reach: 12 px"].exists, "…and reads 12 px by default")
        mend.tap()
        XCTAssertEqual(mend.value as? String, "1", "The option is on")
        XCTAssertTrue(reach.isEnabled, "Mend Reach is live once the option is on")
        fillButton.tap()

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.667, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.667, dy: 0.5), "The third cell fills")

        // Hide the line art: what is left is the colour layer, and a pixel that is still paper is one
        // no fill covers.
        openLayerPanel(app)
        let eye = app.buttons["layerPanel.row.1.visibility"]
        XCTAssertTrue(eye.waitForExistence(timeout: 5))
        eye.tap()
        closeLayerRail(app)
        Thread.sleep(forTimeInterval: 1.0)   // the canvas re-composites without the line layer

        let picture = try screen(of: canvas)
        let unmended = picture.lightPixels(row: 0.5, from: dividers[0] - 0.007, to: dividers[0] + 0.0095)
        let mended = picture.lightPixels(row: 0.5, from: dividers[1] - 0.007, to: dividers[1] + 0.0095)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "mend-seams-line-art-hidden"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertGreaterThan(unmended, 0, "Control: with the option off the first two fills leave paper under the line")
        XCTAssertEqual(mended, 0, "With it on the third fill meets the second under the line — no paper left across the seam")
    }

    // MARK: - (114) The extension buffer

    /// A canvas with padding, the boundary toggle on (it is by default), and a flood fill on blank
    /// paper: the colour stops at the paper's edge, and dragging the Extension Buffer slider — on the
    /// fill that is still adjustable — carries it out across the padding. The padding is grey on
    /// screen and the fill is black, so the band just inside the canvas's outer edge reads as one or
    /// the other.
    func testTheExtensionBufferSliderCarriesTheFillBoundaryIntoThePadding() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Padding first: it is the thing the buffer extends into, and a fresh canvas has none.
        app.buttons["toolbar.settingsButton"].tap()
        let padding = app.sliders["settings.paddingSlider"]
        XCTAssertTrue(padding.waitForExistence(timeout: 5))
        padding.adjust(toNormalizedSliderPosition: 0.2)
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
        let bounds = visibleCanvasBounds(canvas)
        let inPadding = (dx: bounds.minX + (bounds.maxX - bounds.minX) * 0.01, dy: 0.5)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "The flood fills the paper")
        let before = try screen(of: canvas)
        XCTAssertTrue(before.light(inPadding.dx, inPadding.dy), "With the buffer at 0 the padding is left alone")

        fillButton.tap()   // opens the panel again, still scrolled to where it was left
        XCTAssertTrue(app.sliders["fillPanel.edgeOverlapSlider"].waitForExistence(timeout: 5), "The fill menu is open")
        scrollFillPanel(app, to: buffer)
        buffer.adjust(toNormalizedSliderPosition: 1)
        fillButton.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let after = try screen(of: canvas)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "extension-buffer-at-the-padding"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertFalse(after.light(inPadding.dx, inPadding.dy),
                       "With the buffer at the padding's width the fill reaches out to the padded canvas's edge")
    }
}
