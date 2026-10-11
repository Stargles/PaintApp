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
        attachScreenshot(app, "01-seven-layers-in-a-short-panel")
        XCTAssertGreaterThanOrEqual(rulerTop, panel.frame.minY, "The ruler is inside the timeline panel")

        // Seven layers at 36 pt a row overflow the shrunken panel by well over 100 pt.
        // …by dragging an empty stretch of the track, well right of the first cel.
        let empty = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: ruler.frame.minX + 540, dy: panel.frame.minY + panel.frame.height * 0.8))
        empty.press(forDuration: 0.05, thenDragTo: empty.withOffset(CGVector(dx: 0, dy: -100)),
                    withVelocity: .default, thenHoldForDuration: 0.1)

        attachScreenshot(app, "02-scrolled-and-the-ruler-is-still-on-top")
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

        attachScreenshot(app, "03-zoomed-in-frames")
        cel.pinch(withScale: 0.2, velocity: -2)
        attachScreenshot(app, "04-pinched-out-seconds-at-24")
        let atTwentyFour = rulerValue(app)
        XCTAssertTrue(atTwentyFour.hasPrefix("seconds:0s,1s,2s"),
                      "Pinched out, the ruler counts seconds, from 0: \(atTwentyFour)")

        let rate = app.buttons["timeline.frameRateButton"]
        rate.tap()
        let twelve = app.buttons["frameRate.preset.12"]
        XCTAssertTrue(twelve.waitForExistence(timeout: 3))
        twelve.tap()
        rate.tap()
        attachScreenshot(app, "05-seconds-at-12")
        let atTwelve = rulerValue(app)
        XCTAssertTrue(atTwelve.hasPrefix("seconds:0s,1s,2s"), "Still seconds at 12 fps: \(atTwelve)")
        XCTAssertGreaterThan(labels(of: atTwelve).count, labels(of: atTwentyFour).count,
                             "Twelve frames to a second puts more seconds in the same window than twenty-four: "
                             + "\(atTwelve) against \(atTwentyFour)")

        app.otherElements["timeline.cel.0.0"].pinch(withScale: 4, velocity: 3)
        XCTAssertTrue(rulerValue(app).hasPrefix("frames:"),
                      "Pinched back in far enough, the numbers fit their columns again: \(rulerValue(app))")
    }

    // MARK: - The timeline's size

    /// The panel's height once it has stopped moving — a rotation re-lays the editor out over a few frames.
    private func settledHeight(of panel: XCUIElement) -> CGFloat {
        var last = panel.frame.height
        var steadyFor = 0
        let deadline = Date().addingTimeInterval(5)
        while steadyFor < 3, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            let now = panel.frame.height
            steadyFor = now == last ? steadyFor + 1 : 0
            last = now
        }
        return last
    }

    /// **A new document's timeline is about a third of the window tall** — TODO (169), the owner: *"the
    /// timeline's default height is a fraction of the window, not a fixed 375 pt"*. Read off the panel's
    /// own frame (`timeline.panel`), which is what the artist sees, in landscape — the orientation the
    /// owner holds the iPad in, where the window is the shortest (810 pt on their 9th generation) and a
    /// fixed 375 pt was nearly half of it.
    ///
    /// **The bounds are the ruling, not `TimelinePanelSize`'s own constant**, so a change to that constant
    /// that leaves the share outside a third-ish fails here rather than agreeing with itself.
    func testTheTimelineOpensAtAboutAThirdOfTheWindowInLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "PREMISE: the app is in landscape (\(window))")
        let panel = app.otherElements["timeline.panel"]
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let height = settledHeight(of: panel)
        attachScreenshot(app, "timeline-default-landscape-\(Int(window.width))x\(Int(window.height))")

        let share = height / canvas.frame.height
        XCTAssertEqual(share, 0.35, accuracy: 0.02,
                       "The panel is \(height) pt of a \(canvas.frame.height) pt window — \(share) of it")
        XCTAssertLessThan(height, 375, "Shorter than the fixed height it replaces, so the canvas gains room")
        XCTAssertLessThanOrEqual(app.otherElements["timeline.ruler"].frame.minY, panel.frame.maxY,
                                 "The ruler is inside the panel, not pushed off the bottom of it")
    }

    /// **A window with room to spare keeps the 375 pt it had, so the 13-inch iPad is where it was.** The
    /// untouched default is a share of the window *until it reaches that ceiling*, and follows the window
    /// when it turns: a portrait iPad is taller than it needs to be for the paper, which is as wide as the
    /// window, so a larger share there would only cover more of the picture.
    func testTheDefaultFollowsTheWindowThroughARotationAndStopsAt375() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let panel = app.otherElements["timeline.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let landscape = settledHeight(of: panel)

        rotateDevice(app, to: .portrait)
        let portrait = settledHeight(of: panel)
        attachScreenshot(app, "timeline-default-portrait")
        // The 9th-generation iPad is 1060 pt of editor in portrait — 371 at its share, 4 short of the ceiling.
        XCTAssertEqual(portrait, 375, accuracy: 6,
                       "In portrait the window is tall enough for the ceiling (landscape was \(landscape))")
        XCTAssertGreaterThan(portrait, landscape, "The panel the artist never touched is re-derived for the new window")
    }

    /// **A height the artist dragged is theirs: it stays the same number of points through a rotation.**
    /// The rows are a fixed 34 pt each, so "how many layers I can see" is what they chose, and it does
    /// not change with the window. (It is not kept between launches — it never was.)
    func testAHeightTheArtistDraggedSurvivesARotation() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let panel = app.otherElements["timeline.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let before = settledHeight(of: panel)

        let grew = dragTimelineGrabHandle(app, by: 60)
        XCTAssertGreaterThan(grew, 20, "PREMISE: the drag made the panel taller")
        let dragged = settledHeight(of: panel)
        XCTAssertEqual(dragged - before, grew, accuracy: 2, "The panel is as tall as the drag left it")

        rotateDevice(app, to: .portrait)
        XCTAssertEqual(settledHeight(of: panel), dragged, accuracy: 2,
                       "Dragged to \(dragged) pt in landscape, still that tall in portrait")
    }

    /// **The Text card leaves paper to look at**, in landscape on the owner's iPad (810 pt). With the
    /// timeline at a fixed 375 pt the card and the timeline between them left ~90 pt of the 810 under the
    /// top bar. Measured from the paper's own geometry: the stretch between the top bar and whatever is
    /// standing over the lower part (`dockTop`), in points.
    func testTheTextCardLeavesPaperAboveItInLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "PREMISE: the text card is up")
        _ = settledHeight(of: app.otherElements["timeline.panel"])
        let card = app.descendants(matching: .any)["bottomDock.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        attachScreenshot(app, "text-card-landscape")

        let host = canvas.frame
        let clearPaper = CGFloat(dockTop(app, canvas) - toolbarBottom(app, canvas)) * host.height
        let timeline = app.otherElements["timeline.panel"].frame.height
        let note = XCTAttachment(string: "text card, landscape editor \(Int(host.width))x\(Int(host.height)): timeline \(timeline), card \(card.frame.height), paper clear of both \(clearPaper)")
        note.name = "measured"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThanOrEqual(clearPaper, 170,
                                    "Between the top bar and the Text card there are \(clearPaper) pt of paper to look at")
    }
}
