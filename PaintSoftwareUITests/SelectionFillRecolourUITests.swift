import XCTest
import UIKit

/// **A filled selection recoloured from the Select panel never shows the paper through the edit while
/// the picker is open** — the owner's report of 2026-10-12, on the iPad 9: *"Made a selection, clicked
/// on fill, then clicked on edit and tried to change the color inside the selection. Lots of
/// flickering."*
///
/// The edit is held off the document (TODO (173)) for as long as the picker is open: the cel's base is
/// punched out under a window, and the window's picture is drawn off the main thread into one of two
/// surfaces the render server shows (`StrokeCanvasView.showHeldEdit`, `WindowSurfaceView`). So at every
/// moment between the first tick and the lift the artist must be looking at *the fill in some colour*:
/// the base while the first picture is still being drawn (the window is drawn when the picker opens,
/// over the list as it stands, before any tick), then the newest picture that has landed — never the
/// paper, which is what the punched hole shows when a picture is not on top of it, and never an older
/// colour once a newer one has been seen.
///
/// **How it is made deterministic.** Not by sampling a synthesised drag, whose synchronous call leaves
/// the number of screen reads to the host's speed (the test it replaces needed ten and read three on a
/// loaded machine). The ticks are palette swatch taps, one tick each, and **every wait is for a colour
/// to land, not for time**: the screen is read continuously from another thread, and the test moves on
/// when the picture it asked for is the one on screen. What is asserted is a property of *every* read
/// taken meanwhile. The only thing time does is the one seam, `-uiTestSlowWindowDrawMillis`, which
/// makes each draw take 2.5 s, so that the stretch between a tick being asked for and its picture
/// landing — a few milliseconds on this host, hundreds on the iPad — is long enough to be read for
/// certain, whatever the speed of the read: the test asserts it read in it, and fails by saying so
/// when it did not rather than passing on nothing.
///
/// **What it cannot show, and the simulator is why.** The owner's flicker is the surface being redrawn
/// while the render server still shows it (`WindowSurfaceView.present`'s wait). On this simulator the
/// render server did not show the retired surface in any arrangement tried — a window from a sixth of
/// the canvas to nine-tenths of it, draws of 0.3 to 1 s, a main thread held busy after every swap — so
/// no screen read can see that hazard here, and **`WindowSurfaceViewLogicTests` pins the wait instead**,
/// at the level where it is deterministic (a surface with a use count is not drawn into). The owner's
/// iPad is the confirmation still owed. What this test does catch is the rest of the arrangement going
/// wrong around it: the hole punched before the first picture has landed, a picture taken off the
/// surface between ticks, an older picture shown after a newer one.
///
/// Cold start, the artist's way, in the suite's orientation: a red brush, Select → Rectangle, a loop on
/// the paper, Fill; Edit → the colour swatch → the picker's palette. Nothing here depends on how the
/// iPad's window sits on the screen (the simulator's windowed apps place it differently from launch to
/// launch): every point is derived from a frame read in this run.
final class SelectionFillRecolourUITests: PaintUITestCase {

    /// How long each window draw takes (`-uiTestSlowWindowDrawMillis`).
    private static let drawSeconds = 2.5

    /// Spectrum's blue, green, purple and orange — four picks the screen tells apart from red, from
    /// paper and from each other. The test reads each swatch's own value before using it.
    private static let picks: [(index: Int, hex: String)] = [(8, "2196F3"), (6, "4CAF50"), (10, "9C27B0"), (4, "FF9800")]

    /// The colour of a read: 0 is the fill as it was painted (red), `n` is the n-th pick, nil is
    /// anything else — the paper, the hatching, a half-drawn picture.
    private func level(of pixel: RGBA?) -> Int? {
        guard let pixel else { return nil }
        func near(_ rgb: (Int, Int, Int)) -> Bool {
            abs(Int(pixel.r) - rgb.0) < 14 && abs(Int(pixel.g) - rgb.1) < 14 && abs(Int(pixel.b) - rgb.2) < 14
        }
        if near((255, 0, 0)) { return 0 }
        for (offset, pick) in Self.picks.enumerated() {
            let value = Int(pick.hex, radix: 16) ?? 0
            if near(((value >> 16) & 255, (value >> 8) & 255, value & 255)) { return offset + 1 }
        }
        return nil
    }

    func testRecolouringAFilledSelectionNeverShowsThePaperThroughTheEdit() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowWindowDrawMillis", "\(Int(Self.drawSeconds * 1000))"]
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // 1. Red, Select → Rectangle, a loop across the upper paper, Fill; Edit → the swatch → the picker.
        setBrushColor(app, hex: "FF0000")
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        let visible = visiblePaperRect(app, in: canvas)
        let loop = (x0: 0.1, y0: 0.1, x1: 0.9, y1: 0.5)
        dragOnCanvas(app, from: onHost(visible, loop.x0, loop.y0), to: onHost(visible, loop.x1, loop.y1))
        let fill = app.buttons["selectPanel.fillButton"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5), "the loop raised the Select panel's Fill")
        fill.tap()
        openSelectionEditBand(app)
        let swatch = app.buttons["selectPanel.colourSwatch"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the loop raised the colour swatch")

        // 2. A grid of points over the loop, read from another thread from here on — before the picker
        //    opens, when the fill is on screen under nothing but the Select panel and the timeline, which
        //    the loop stays above. The points that read red are on the fill.
        let host = canvas.frame
        func screen(_ v: CGVector) -> CGPoint {
            CGPoint(x: host.minX + host.width * v.dx, y: host.minY + host.height * v.dy)
        }
        var grid: [CGPoint] = []
        for fx in stride(from: 0.06, through: 0.94, by: 0.11) {
            for fy in stride(from: 0.12, through: 0.88, by: 0.19) {
                grid.append(screen(onHost(visible, loop.x0 + (loop.x1 - loop.x0) * fx,
                                          loop.y0 + (loop.y1 - loop.y0) * fy)))
            }
        }
        let sampler = MidGestureSampler(points: grid, interval: 0)
        sampler.start()
        let before = waitForSample(sampler, timeout: 30) { _ in true }
        let onTheFill = grid.indices.filter { level(of: before?.pixels[$0]) == 0 }
        XCTAssertGreaterThanOrEqual(onTheFill.count, 12,
                                    "PREMISE: the fill reads red where it is read (\(onTheFill.count) of \(grid.count) points; "
                                    + "first read \(String(describing: before?.pixels)))")

        // 3. The picker opens, which begins the edit's session — and the window is drawn then too, over
        //    the list as it stands, so the base has to stay on screen through that draw as well. Once it
        //    has landed (the draw's 2.5 s and a second's grace) the points still red are the ones the
        //    picker does not cover.
        let opened = CFAbsoluteTimeGetCurrent()
        swatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["canvasPresentation.selectionColour"].firstMatch
            .waitForExistence(timeout: 5), "the swatch opens the picker")
        var swatches: [XCUIElement] = []
        for pick in Self.picks {
            let element = app.otherElements["colorPanel.swatch.\(pick.index)"]
            XCTAssertTrue(element.exists, "PREMISE: the picker lists palette swatch \(pick.index)")
            XCTAssertEqual(element.value as? String, pick.hex, "PREMISE: swatch \(pick.index) is \(pick.hex)")
            swatches.append(element)
        }
        Thread.sleep(forTimeInterval: max(0, opened + Self.drawSeconds + 1 - CFAbsoluteTimeGetCurrent()))
        let settled = sampler.latest
        let clear = onTheFill.filter { level(of: settled?.pixels[$0]) == 0 }
        XCTAssertGreaterThanOrEqual(clear.count, 6,
                                    "PREMISE: the fill reads red where it is read, clear of the picker (\(clear.count) of "
                                    + "\(onTheFill.count) points; settled read \(String(describing: settled?.pixels)))")
        attachScreenshot(XCUIScreen.main, "1-picker-open-over-the-filled-selection")

        /// The one level every clear point reads in a sample, or nil when they disagree or any is not a colour.
        func uniformLevel(_ sample: MidGestureSampler.Sample) -> Int? {
            let levels = Set(clear.map { level(of: sample.pixels[$0]) })
            return levels.count == 1 ? levels.first ?? nil : nil
        }
        func waitForLevel(atLeast target: Int) -> Bool {
            waitForSample(sampler, timeout: 40) { (uniformLevel($0) ?? -1) >= target } != nil
        }

        // 4. Tick one alone: its picture takes 2.5 s to draw, and the base must be on screen meanwhile.
        //    Then ticks two, three and four in quick succession: the second is drawn at once, the third
        //    is asked for during that draw and the fourth replaces it, so the picture drawn after the
        //    second lands — into the surface the first one just left — is the newest, and the third
        //    is never drawn at all.
        let t0 = opened
        var taps: [CFAbsoluteTime] = []
        func tick(_ index: Int) {
            swatches[index].tap()
            taps.append(CFAbsoluteTimeGetCurrent())
        }
        tick(0)
        XCTAssertTrue(waitForLevel(atLeast: 1), "the first tick's picture never reached the screen")
        tick(1)
        tick(2)
        tick(3)
        XCTAssertTrue(waitForLevel(atLeast: Self.picks.count), "the newest tick's picture never reached the screen")
        let reads = sampler.stop()
        attachScreenshot(XCUIScreen.main, "1-the-last-tick-held")

        // 5. What every read said, from the picker opening on.
        let timeline = reads.filter { $0.finished >= opened }
        func pixels(_ sample: MidGestureSampler.Sample) -> String {
            clear.map { sample.pixels[$0].map { "\($0.r),\($0.g),\($0.b)" } ?? "-" }.joined(separator: " ")
        }
        let note = XCTAttachment(string: "(seconds from the picker opening) ticks at " + taps.map { String(format: "%.2f", $0 - t0) }.joined(separator: ", ")
                                 + "\n" + timeline.map { sample in
            String(format: "%.2f ", sample.finished - t0)
                + (uniformLevel(sample).map { "level \($0)" } ?? "NOT ONE COLOUR: " + pixels(sample))
        }.joined(separator: "\n"))
        note.name = "what the fill read, from the picker opening on"
        note.lifetime = .keepAlways
        add(note)

        if let bad = timeline.first(where: { uniformLevel($0) == nil }) {
            XCTFail("the fill read as something other than one of its colours \(String(format: "%.2f", bad.finished - t0)) s "
                    + "in, with the edit held — the paper through the hole, or half a picture (\(pixels(bad)))")
            return
        }
        let levels = timeline.compactMap(uniformLevel)
        XCTAssertEqual(levels, levels.sorted(),
                       "an older colour came back after a newer one had been on screen (levels read, in order: \(levels))")
        XCTAssertEqual(levels.last, Self.picks.count, "the screen ends on the newest tick's picture")

        // 6. **Reads that fell while a picture was on screen and the next was still being drawn** — the
        //    base while the first draws, the first picture while the second does, the second while the
        //    last does — each more than once, or the loop above has asserted nothing about the stretch
        //    this test exists for.
        for shown in [0, 1, 2] {
            let dwelling = levels.filter { $0 == shown }.count
            XCTAssertGreaterThanOrEqual(
                dwelling, 2,
                "PREMISE: the screen was read \(dwelling) times with level \(shown) on it while the next picture was being "
                + "drawn — the host is too slow to read inside a \(Self.drawSeconds) s draw (levels read: \(levels))")
        }
    }

    /// Polls `sampler` until its newest sample satisfies `accepted`, and returns that sample; nil when
    /// the deadline passes — never the last reading, as `waitForPixel`.
    private func waitForSample(_ sampler: MidGestureSampler, timeout: TimeInterval,
                               _ accepted: (MidGestureSampler.Sample) -> Bool) -> MidGestureSampler.Sample? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let latest = sampler.latest, accepted(latest) { return latest }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }
}
