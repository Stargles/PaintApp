import XCTest

/// **The timeline's ruler: pinned, in seconds when zoomed out, and the panel taller** — TODO (122):
///
/// > *"the animation timeline shows the frame number in the top row. When there are a lot of layers,
/// > this top row should still remain on the top and not disappear when scrolling down. When the
/// > timeline is zoomed out it should display seconds instead of frames. Also make it around 1.5x
/// > taller."*
///
/// `TimelineRulerLabelsLogicTests` owns what the ruler *decides*; this owns whether the artist can see
/// it. The ruler's accessibility value is the labels it is drawing (`TimelineRulerLabels.encode`),
/// computed from the same plan the draw loop reads, so "the ruler says seconds" is a question asked of
/// what is on screen and not of a stored flag. Every test starts from a new document.
final class TimelineRulerUITests: PaintUITestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func rulerValue(_ app: XCUIApplication) -> String {
        app.otherElements["timeline.ruler"].value as? String ?? "<no value>"
    }

    /// The labels a ruler value lists, without its unit.
    private func labels(of value: String) -> [String] {
        guard let colon = value.firstIndex(of: ":") else { return [] }
        return value[value.index(after: colon)...].split(separator: ",").map(String.init)
    }

    // MARK: - Pinned

    /// **The frame row stays on top while the rows scroll under where it was.** The panel is shrunk first
    /// so a handful of layers overflow it — the artist's case is many layers, and this is the same
    /// geometry with fewer taps — and the rows are then scrolled by dragging the name column. The ruler's
    /// top edge must not move, the rows must (the premise: something scrolled), and the ruler must still
    /// be reachable and still be labelling frames.
    func testTheRulerStaysOnTopWhileTheLayersScrollUnderIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        for _ in 0..<6 { addVectorLayer(app) }
        dragTimelineGrabHandle(app, by: -170)

        let ruler = app.otherElements["timeline.ruler"]
        let panel = app.otherElements["timeline.panel"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let row = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let rulerTop = ruler.frame.minY
        let rowTop = row.frame.minY
        attach(app, "01-before-scroll")
        XCTAssertGreaterThanOrEqual(rulerTop, panel.frame.minY, "The ruler is inside the timeline panel")

        // Seven layers at 36 pt a row overflow the shrunken panel by well over 100 pt.
        // …by dragging an empty stretch of the track, well right of the first cel.
        let empty = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: ruler.frame.minX + 540, dy: panel.frame.minY + panel.frame.height * 0.8))
        empty.press(forDuration: 0.05, thenDragTo: empty.withOffset(CGVector(dx: 0, dy: -100)),
                    withVelocity: .default, thenHoldForDuration: 0.1)

        attach(app, "02-after-scroll")
        XCTAssertLessThan(row.frame.minY, rowTop - 20,
                          "PREMISE: the rows scrolled — row 1 was at \(rowTop) and is at \(row.frame.minY)")
        XCTAssertEqual(ruler.frame.minY, rulerTop, accuracy: 0.5,
                       "The ruler did not scroll with them")
        XCTAssertTrue(ruler.isHittable, "…and is still there to scrub")
        XCTAssertTrue(rulerValue(app).hasPrefix("frames:1,2,3"),
                      "…still counting frames from the first one: \(rulerValue(app))")
    }

    // MARK: - Frames or seconds

    /// **Zoomed in it counts frames; pinched out it counts seconds; pinched back in, frames again** — and
    /// the seconds follow the document's frame rate. The pinch is on the first cel block, the way an
    /// artist pinches the timeline, and the frame rate is changed through its own panel.
    func testPinchedOutTheRulerCountsSecondsFromTheDocumentsFrameRate() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5))
        XCTAssertTrue(rulerValue(app).hasPrefix("frames:1,2,3"),
                      "A new document opens zoomed in far enough to number its frames: \(rulerValue(app))")

        cel.pinch(withScale: 0.2, velocity: -2)
        let atTwentyFour = rulerValue(app)
        XCTAssertTrue(atTwentyFour.hasPrefix("seconds:0s,1s,2s"),
                      "Pinched out, the ruler counts seconds, from 0: \(atTwentyFour)")

        let rate = app.buttons["timeline.frameRateButton"]
        rate.tap()
        let twelve = app.buttons["frameRate.preset.12"]
        XCTAssertTrue(twelve.waitForExistence(timeout: 3))
        twelve.tap()
        rate.tap()
        let atTwelve = rulerValue(app)
        XCTAssertTrue(atTwelve.hasPrefix("seconds:0s,1s,2s"), "Still seconds at 12 fps: \(atTwelve)")
        XCTAssertGreaterThan(labels(of: atTwelve).count, labels(of: atTwentyFour).count,
                             "Twelve frames to a second puts more seconds in the same window than twenty-four: "
                             + "\(atTwelve) against \(atTwentyFour)")

        app.otherElements["timeline.cel.0.0"].pinch(withScale: 4, velocity: 3)
        XCTAssertTrue(rulerValue(app).hasPrefix("frames:"),
                      "Pinched back in far enough, the numbers fit their columns again: \(rulerValue(app))")
    }

    // MARK: - Taller

    /// **The panel opens 1.5× the height it used to** — 250 pt, so 375 — and the canvas above it is still
    /// a canvas. Read off the panel's own frame (`timeline.panel`), which is what the artist sees.
    func testTheTimelineOpensOneAndAHalfTimesTaller() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let panel = app.otherElements["timeline.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(panel.frame.height, 250 * 1.5, accuracy: 2,
                       "A new document opens its timeline 1.5× the 250 pt it was")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(canvas.frame.height, 400, "The canvas keeps room to draw in")
        XCTAssertLessThanOrEqual(app.otherElements["timeline.ruler"].frame.minY, panel.frame.maxY,
                                 "The ruler is inside the panel, not pushed off the bottom of it")
    }
}
