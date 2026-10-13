import XCTest
import UIKit

/// **A drag on the colour picker redraws the shape under the finger and nothing else** — TODO (183), from a
/// new document, the artist's way.
///
/// The owner's recording of Select → Fill → Edit → Colour had the main thread busy for 1,468 ms of a
/// two-second drag, nearly all of it SwiftUI rebuilding the picker: every tick wrote four `@State`s on the
/// panel, so every tick re-evaluated the whole panel — the Recent grid and the palette (thirty swatches,
/// each with its own context-menu presentation and long-press) and the hex field — before the shape under
/// the finger moved. `PickerColor` holds the colour now and the shapes read it; the two grids are
/// `Equatable` sections. This pins what that buys, from the artist's side, at the two places the picker
/// lives: Select's Colour (the held-edit path of TODO (173)/(179)) and the brush's colour panel (a host
/// that rebuilds the panel on every tick, because the brush's colour is published by the editor).
///
/// **Counted, because wall clock is not what a test can pin.** `canvas.host` publishes what the picker
/// has evaluated (`ColorPickerPasses`): ticks of the drag, panel bodies, and the Recent / palette sections
/// — the grids a tick must not rebuild. They are read either side of a drag, as `passes:` is, and the
/// drag is one continuous synthesised touch (`fingerStroke`) so the count is of a real gesture and not
/// of ten taps.
final class ColorPickerLiveUITests: PaintUITestCase {

    /// A counter from `canvas.host`'s label.
    private func count(_ app: XCUIApplication, _ field: String) -> Int {
        Int(readField(app, field)) ?? -1
    }

    private struct Counts { let ticks: Int, panel: Int, sections: Int, passes: Int }

    private func counts(_ app: XCUIApplication) -> Counts {
        Counts(ticks: count(app, "pickerTicks:"), panel: count(app, "pickerPanel:"),
               sections: count(app, "pickerSections:"), passes: count(app, "passes:"))
    }

    /// One finger round a circle in `element`, as a single continuous gesture the app sees as a drag:
    /// `laps` times round, at `fraction` of the way from the middle to the nearest edge.
    ///
    /// The circle is built in screen points through where `element`'s middle and a step along each of its
    /// axes land (`XCUICoordinate.screenPoint`), so it is the same drag whichever way the device is held.
    private func dragRound(_ element: XCUIElement, fraction: CGFloat, laps: Int = 3, pointsPerLap: Int = 30) throws {
        let frame = element.frame
        let radius = min(frame.width, frame.height) / 2 * fraction
        func screen(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: dx, dy: dy)).screenPoint
        }
        let origin = screen(0, 0), alongX = screen(100, 0), alongY = screen(0, 100)
        let points = (0..<(laps * pointsPerLap)).map { step -> CGPoint in
            let angle = 0.6 + 2 * Double.pi * Double(step) / Double(pointsPerLap)
            let dx = radius * CGFloat(cos(angle)), dy = radius * CGFloat(sin(angle))
            return CGPoint(x: origin.x + (alongX.x - origin.x) * dx / 100 + (alongY.x - origin.x) * dy / 100,
                           y: origin.y + (alongX.y - origin.y) * dx / 100 + (alongY.y - origin.y) * dy / 100)
        }
        try fingerStroke(through: points, interval: 0.05)
    }

    /// **The counts as they stand once the picker has settled, read off a label that is current.**
    /// `canvas.host` is republished by a pass over the canvas, so a read straight after the picker opens (or
    /// a tab is switched) can be older than the grids' first evaluation, and a delta from it would count
    /// the picker being built. One short lap first: its ticks raise the passes that republish the label.
    private func countsAfterAWarmUpLap(_ app: XCUIApplication, _ shape: XCUIElement) throws -> Counts {
        try dragRound(shape, fraction: 0.5, laps: 1, pointsPerLap: 12)
        Thread.sleep(forTimeInterval: 1.0)
        return counts(app)
    }

    /// `#RRGGBB` from an accessibility value, as three bytes.
    private func bytes(ofHex hex: String) -> (r: Int, g: Int, b: Int)? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count >= 6, let value = Int(digits.prefix(6), radix: 16) else { return nil }
        return (value >> 16 & 255, value >> 8 & 255, value & 255)
    }

    // MARK: - Select → Fill → Edit → Colour (the owner's recording)

    /// Red brush, Select → Rectangle, a loop over the right half of the paper, Fill; Edit → the colour
    /// swatch → the picker's Classic square dragged round for ~10 s. The grids are not rebuilt, the panel
    /// is not rebuilt, the editor is not raised a pass — and the fill under the picker is, at the end of
    /// it, the colour the picker's own swatch shows, so the ticks went somewhere.
    func testDraggingTheSelectionColourPickerRebuildsNothingButTheShape() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setBrushColor(app, hex: "FF0000")
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        let visible = visiblePaperRect(app, in: canvas)
        dragOnCanvas(app, from: onHost(visible, 0.52, 0.12), to: onHost(visible, 0.94, 0.9))
        let fill = app.buttons["selectPanel.fillButton"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5), "the loop raised the Select panel's Fill")
        fill.tap()
        openSelectionEditBand(app)
        let swatch = app.buttons["selectPanel.colourSwatch"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the loop raised the colour swatch")
        swatch.tap()
        let picker = app.descendants(matching: .any)["canvasPresentation.selectionColour"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the swatch opens the picker")
        let square = app.otherElements["colorPanel.svSquare"]
        XCTAssertTrue(square.waitForExistence(timeout: 5), "the picker's Classic square")
        attachScreenshot(app, "1-picker-open-over-the-filled-selection")

        // Where the fill can be read: clear of the picker.
        let host = canvas.frame
        func screen(_ v: CGVector) -> CGPoint {
            CGPoint(x: host.minX + host.width * v.dx, y: host.minY + host.height * v.dy)
        }
        let probes = [(0.62, 0.3), (0.72, 0.45), (0.82, 0.3), (0.66, 0.65), (0.84, 0.7), (0.75, 0.55)]
            .map { screen(onHost(visible, $0.0, $0.1)) }
            .filter { !picker.frame.insetBy(dx: -8, dy: -8).contains($0) }
        XCTAssertGreaterThanOrEqual(probes.count, 2, "PREMISE: part of the fill is in view beside the picker")

        let before = try countsAfterAWarmUpLap(app, square)
        try dragRound(square, fraction: 0.6)
        // Let the last tick's picture land before anything is read.
        Thread.sleep(forTimeInterval: 1.0)
        let after = counts(app)
        attachScreenshot(app, "2-after-the-drag")

        let ticks = after.ticks - before.ticks
        XCTAssertGreaterThanOrEqual(ticks, 40, "PREMISE: the drag reached the picker's square (\(ticks) ticks)")
        XCTAssertEqual(after.sections - before.sections, 0,
                       "the Recent grid and the palette were rebuilt \(after.sections - before.sections) times across "
                       + "\(ticks) ticks — every tick of the drag was re-evaluating thirty swatches")
        XCTAssertLessThanOrEqual(after.panel - before.panel, 3,
                                 "the panel's body ran \(after.panel - before.panel) times across \(ticks) ticks — "
                                 + "the panel is reading the colour the drag moves")
        XCTAssertLessThanOrEqual(after.passes - before.passes, 3,
                                 "\(after.passes - before.passes) SwiftUI passes reached the canvas across the drag — "
                                 + "a held edit writes nothing until the lift")

        // The ticks went somewhere: the fill is the colour the picker's swatch shows.
        let shown = try XCTUnwrap(app.otherElements["colorPanel.currentSwatch"].value as? String, "the swatch's value")
        let want = try XCTUnwrap(bytes(ofHex: shown), "the swatch value is a hex (\(shown))")
        XCTAssertFalse(want.r > 200 && want.g < 60 && want.b < 60, "PREMISE: the drag moved the colour off the red it started on (\(shown))")
        let read = readScreenNow(probes)
        for pixel in read {
            guard let pixel else { XCTFail("a probe could not be read"); continue }
            XCTAssertEqual(Int(pixel.r), want.r, accuracy: 24, "the fill's red channel is the swatch's (\(shown))")
            XCTAssertEqual(Int(pixel.g), want.g, accuracy: 24, "the fill's green channel is the swatch's (\(shown))")
            XCTAssertEqual(Int(pixel.b), want.b, accuracy: 24, "the fill's blue channel is the swatch's (\(shown))")
        }
    }

    // MARK: - The Wheel tab, and the ring

    /// The Wheel tab is the shading that used to be re-issued every tick: the ring dragged round, then the
    /// triangle. The grids and the panel are as still as they were for the square.
    func testDraggingTheWheelAndItsRingRebuildsNothingButTheShapes() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        openColorPanel(app)
        app.buttons["colorPanel.tab.triangle"].tap()
        let triangle = app.otherElements["colorPanel.triangle"]
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(triangle.waitForExistence(timeout: 5), "the Wheel tab's triangle")
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "…and its ring")

        let startHex = try XCTUnwrap(app.otherElements["colorPanel.currentSwatch"].value as? String)
        let before = try countsAfterAWarmUpLap(app, ring)
        try dragRound(ring, fraction: 0.86, laps: 2)
        try dragRound(triangle, fraction: 0.3, laps: 2)
        Thread.sleep(forTimeInterval: 1.0)
        let after = counts(app)
        attachScreenshot(app, "wheel-after-the-drags")

        let ticks = after.ticks - before.ticks
        XCTAssertGreaterThanOrEqual(ticks, 40, "PREMISE: the drags reached the ring and the triangle (\(ticks) ticks)")
        XCTAssertEqual(after.sections - before.sections, 0,
                       "the Recent grid and the palette were rebuilt across \(ticks) ticks of the wheel")
        XCTAssertNotEqual(app.otherElements["colorPanel.currentSwatch"].value as? String, startHex,
                          "PREMISE: the drags moved the colour")
    }

    // MARK: - The brush's colour panel

    /// The brush's colour is published on its own object (`BrushColorState`, TODO (179)), so a tick
    /// re-evaluates the panel's host and the swatches that show the colour — not the editor: the canvas
    /// is raised no pass across the drag, and the toolbar's swatch follows the panel. The grids are
    /// `Equatable` sections, so the panel's body runs and its swatches do not. (Panel bodies are not
    /// bounded here: this host re-evaluates the panel by design, so it follows an eyedropper pick.)
    func testDraggingTheBrushColourPanelDoesNotRebuildTheSwatchGrids() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        openColorPanel(app)
        let square = app.otherElements["colorPanel.svSquare"]
        let startHex = try XCTUnwrap(app.otherElements["colorPanel.currentSwatch"].value as? String)
        attachScreenshot(app, "brush-panel-open")

        let before = try countsAfterAWarmUpLap(app, square)
        try dragRound(square, fraction: 0.6)
        Thread.sleep(forTimeInterval: 1.0)
        let after = counts(app)
        attachScreenshot(app, "brush-panel-after-the-drag")

        let ticks = after.ticks - before.ticks
        XCTAssertGreaterThanOrEqual(ticks, 40, "PREMISE: the drag reached the square (\(ticks) ticks)")
        XCTAssertEqual(after.sections - before.sections, 0,
                       "the Recent grid and the palette were rebuilt \(after.sections - before.sections) times across "
                       + "\(ticks) ticks of the brush's colour panel")
        XCTAssertNotEqual(app.otherElements["colorPanel.currentSwatch"].value as? String, startHex,
                          "PREMISE: the drag moved the colour")
        XCTAssertLessThanOrEqual(after.passes - before.passes, 2,
                                 "\(after.passes - before.passes) SwiftUI passes reached the canvas across \(ticks) ticks "
                                 + "of the brush's colour — the editor re-evaluated for a colour two swatches show")
        // And the colour reached the brush: the toolbar's swatch, then a stroke.
        let shown = try XCTUnwrap(app.otherElements["colorPanel.currentSwatch"].value as? String)
        XCTAssertEqual(app.buttons["toolbar.colorButton"].value as? String, shown,
                       "the toolbar's swatch is the colour the panel last showed")
        closeColorPanel(app)
        let canvas = app.otherElements["canvas.host"]
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        let ink = try XCTUnwrap(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5), "a pixel on the stroke")
        let want = try XCTUnwrap(bytes(ofHex: shown))
        XCTAssertEqual(Int(ink.r), want.r, accuracy: 24, "the stroke is the colour the panel last showed (\(shown))")
        XCTAssertEqual(Int(ink.g), want.g, accuracy: 24)
        XCTAssertEqual(Int(ink.b), want.b, accuracy: 24)
    }
}
