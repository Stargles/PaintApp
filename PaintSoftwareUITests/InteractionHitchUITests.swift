import XCTest

/// Scratch repro of the owner's November 17 reports: strokes and pans on a 5000² document of five
/// vector layers, with the action recorder's main-thread measurement on.
final class InteractionHitchUITests: PaintUITestCase {

    private let canvasSize = CGSize(width: 5000, height: 5000)

    /// The owner's scene shape, Rough Ink in hand, with the recorder running.
    private func openOwnersScene(brush normalized: CGFloat) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        return (app, openOwnersScene(brush: normalized, app: app))
    }

    private func openOwnersScene(brush normalized: CGFloat, app: XCUIApplication) -> XCUIElement {
        app.launchArguments += ["-uiTestTextureBudgetBytes", "201326592"]
        XCTAssertTrue(launchIntoEditor(app, size: canvasSize, orientationBeforeCreatingCanvas: .landscapeLeft))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openBrushLibrary(app)
        let inking = app.buttons["brushPanel.group.Inking"]
        XCTAssertTrue(inking.waitForExistence(timeout: 5))
        tapWhenHittable(inking, "Inking group")
        let rough = app.buttons["brushPanel.brush.Rough Ink"]
        XCTAssertTrue(rough.waitForExistence(timeout: 5))
        if !rough.isSelected { tapWhenHittable(rough, "Rough Ink") }
        setBrushSize(app, normalized: normalized)
        app.buttons["toolbar.brushButton"].tap()

        let visible = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(visible, dx, dy) }
        for layer in 0..<5 {
            if layer > 0 { addVectorLayer(app) }
            for s in 0..<6 {
                let y = 0.10 + Double(s) * 0.14
                drawLine(on: canvas, from: at(0.05 + Double(layer) * 0.02, y), to: at(0.95, y + 0.05))
            }
        }
        Thread.sleep(forTimeInterval: 3)

        let settings = app.buttons["toolbar.settingsButton"]
        settings.tap()
        let toggle = app.buttons["recorder.toggle"]
        scrollSettings(app, to: toggle)
        tapWhenHittable(toggle, "Record my actions")
        settings.tap()
        return canvas
    }

    private func stopRecording(_ app: XCUIApplication) {
        let settings = app.buttons["toolbar.settingsButton"]
        settings.tap()
        let toggle = app.buttons["recorder.toggle"]
        scrollSettings(app, to: toggle)
        tapWhenHittable(toggle, "Stop recording actions")
    }

    /// Screen points for fractions of the paper between the toolbar and the dock, worked out once so
    /// nothing during a burst asks the app for an accessibility snapshot — those run on the app's
    /// main thread and would be measured as stalls.
    private func paperPoints(_ app: XCUIApplication, _ canvas: XCUIElement) -> (Double, Double) -> CGPoint {
        let host = canvas.frame
        let top = toolbarBottom(app, hostFrame: host) + 0.04, bottom = dockTop(app, hostFrame: host) - 0.04
        return { x, y in
            CGPoint(x: host.minX + host.width * x, y: host.minY + host.height * (top + (bottom - top) * y))
        }
    }

    func testStrokesAndPansOnFiveVectorLayersAtTheOwnersSize() throws {
        let (app, canvas) = openOwnersScene(brush: 5.0 / 199)
        defer { XCUIDevice.shared.orientation = .portrait }
        let pt = paperPoints(app, canvas)
        print("HITCH-BURST-START \(Date().timeIntervalSince1970)")
        for i in 0..<12 {
            let y = 0.15 + Double(i % 6) * 0.13
            let points = (0...40).map { k -> CGPoint in
                let t = Double(k) / 40
                return pt(0.15 + 0.6 * t, y + 0.05 * sin(t * 9))
            }
            try fingerStroke(through: points, interval: 1.0 / 60)
            let d: CGFloat = i % 2 == 0 ? 80 : -80
            let a = pt(0.3, 0.45), b = pt(0.45, 0.55)
            try twoFingerGesture(from: (a, b), to: (CGPoint(x: a.x + d, y: a.y + d / 2), CGPoint(x: b.x + d, y: b.y + d / 2)),
                                 stagger: 0.02, duration: 0.5, steps: 30)
        }
        print("HITCH-BURST-END \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 2)
        stopRecording(app)
    }

    /// **A lifted stroke never leaves the screen on its way into the layer's picture.** Strokes in
    /// quick succession, each watched by screenshot from its lift until well after its base lands.
    func testAFinishedStrokeStaysOnScreenUntilItsBaseLands() throws {
        let (app, canvas) = openOwnersScene(brush: 0.4)
        defer { XCUIDevice.shared.orientation = .portrait }
        let pt = paperPoints(app, canvas)
        var report: [String] = []
        var worst = 1.0
        func shot() -> ScreenshotPixels? { ScreenshotPixels(XCUIScreen.main.screenshot().image) }
        for i in 0..<6 {
            let y = 0.12 + Double(i) * 0.15
            let middle = pt(0.5, y)
            let probes = stride(from: -40.0, through: 40.0, by: 2).flatMap { dx in
                stride(from: -8.0, through: 8.0, by: 2).map { CGPoint(x: middle.x + dx, y: middle.y + $0) }
            }
            // What the paper there looked like before the stroke: the fixture's own lines cross it.
            guard let before = shot() else { return XCTFail("no screenshot") }
            let baseline = probes.map { before.pixel(at: $0) }
            func changed(_ now: ScreenshotPixels) -> Int {
                zip(probes, baseline).filter { point, old in
                    guard let a = now.pixel(at: point), let b = old else { return false }
                    return abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b)) > 90
                }.count
            }
            try fingerStroke(through: (0...20).map { pt(0.30 + 0.4 * Double($0) / 20, y) }, interval: 1.0 / 60)
            let lifted = Date()
            var counts: [(Double, Int)] = []
            while Date().timeIntervalSince(lifted) < 2.5 {
                guard let now = shot() else { continue }
                counts.append((Date().timeIntervalSince(lifted), changed(now)))
            }
            let final = counts.last?.1 ?? 0
            // **Only the samples from the first one that shows the stroke on.** A big brush stamps its
            // live dabs on the main thread (the 'mainStall's in the recording: `DabImageCache.stamp`,
            // ~380 ms), so the stroke is simply not drawn yet for a screenshot taken just after the
            // finger lifted — that is first-appearance latency, a different thing from a stroke that
            // was on screen leaving it. A dip is a sample below half of the landed ink *after* one at
            // or above it.
            let firstShown = counts.firstIndex { final > 0 && $0.1 * 2 >= final } ?? counts.count
            let shown = Array(counts.dropFirst(firstShown))
            let low = shown.min { $0.1 < $1.1 } ?? (0.0, 0)
            let share = final > 0 ? (shown.isEmpty ? 0 : Double(low.1) / Double(final)) : 0
            worst = min(worst, share)
            report.append("stroke \(i): final=\(final) min=\(low.1) at +\(String(format: "%.2f", low.0))s "
                          + "samples=\(counts.count) [\(counts.map { String(format: "%.2f:%d", $0.0, $0.1) }.joined(separator: " "))]")
            if final <= 20 { report.append("PREMISE: stroke \(i) changed only \(final) probes once landed") }
        }
        print("FLICKER " + report.joined(separator: "\nFLICKER "))
        stopRecording(app)
        XCTAssertGreaterThanOrEqual(worst, 0.5, "a finished stroke left the screen between its lift and its base:\n"
                                    + report.joined(separator: "\n"))
    }

    /// **What the screen shows live stays until the base that matches it is up** — quick strokes,
    /// then one eraser pass across all of them, at the owner's shape with the layer render slowed to
    /// the iPad's pace. Every screenshot from the first stroke to well after the erase is read; ink
    /// that dips and comes back, or erased ink that comes back and goes, fails.
    func testLiveInkAndErasedInkHoldUntilTheMatchingBaseLands() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowVectorRenderMillis", "300"]
        let canvas = openOwnersScene(brush: 0.15, app: app)
        defer { XCUIDevice.shared.orientation = .portrait }
        let pt = paperPoints(app, canvas)
        func shot() -> ScreenshotPixels? { ScreenshotPixels(XCUIScreen.main.screenshot().image) }
        let rows = [0.2, 0.35, 0.5, 0.65]
        let probes = rows.map { y in stride(from: 0.40, through: 0.60, by: 0.01).map { pt($0, y) } }
        guard let before = shot() else { return XCTFail("no screenshot") }
        let baseline = probes.map { $0.map { before.pixel(at: $0) } }
        func inked(_ now: ScreenshotPixels) -> [Int] {
            zip(probes, baseline).map { row, old in
                zip(row, old).filter { point, was in
                    guard let a = now.pixel(at: point), let b = was else { return false }
                    return abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b)) > 90
                }.count
            }
        }
        var timeline: [(String, [Int])] = []
        func watch(_ label: String, for seconds: TimeInterval) {
            let start = Date()
            repeat { if let now = shot() { timeline.append((label, inked(now))) } }
            while Date().timeIntervalSince(start) < seconds
        }
        for (i, y) in rows.enumerated() {
            try fingerStroke(through: (0...16).map { pt(0.30 + 0.4 * Double($0) / 16, y) }, interval: 1.0 / 60)
            watch("stroke \(i)", for: 0.35)
        }
        watch("strokes settle", for: 2.0)
        app.buttons["toolbar.eraserButton"].tap()
        let erase = stride(from: 0.0, through: 1.0, by: 1.0 / 24).map { t in pt(0.5 + 0.02 * sin(t * 20), 0.12 + 0.66 * t) }
        try fingerStroke(through: erase, interval: 1.0 / 60)
        watch("erase", for: 2.5)
        stopRecording(app)

        let lines = timeline.map { "\($0.0): \($0.1.map(String.init).joined(separator: ","))" }
        print("HANDOFF " + lines.joined(separator: "\nHANDOFF "))
        // A row is "up" at >= half its settled ink, "down" below a fifth of it.
        var failures: [String] = []
        for row in rows.indices {
            let settled = timeline.last { $0.0 == "strokes settle" }?.1[row] ?? 0
            guard settled > 4 else { failures.append("PREMISE: row \(row) never inked (\(settled))"); continue }
            let series = timeline.prefix { $0.0 != "erase" }.map { $0.1[row] }
            if let up = series.firstIndex(where: { $0 * 2 >= settled }),
               let gap = series[up...].firstIndex(where: { $0 * 5 < settled }) {
                failures.append("row \(row): ink was up, then gone at sample \(gap), then back")
            }
            let erased = timeline.drop { $0.0 != "erase" }.map { $0.1[row] }
            if let gone = erased.firstIndex(where: { $0 * 5 < settled }),
               let back = erased[gone...].firstIndex(where: { $0 * 2 >= settled }) {
                failures.append("row \(row): erased ink came back at erase sample \(back)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n") + "\n" + lines.joined(separator: "\n"))
    }

    private func scrollSettings(_ app: XCUIApplication, to control: XCUIElement) {
        let menu = app.scrollViews.containing(.staticText, identifier: "Settings").firstMatch
        for _ in 0..<8 where !control.isHittable && menu.exists {
            let frame = menu.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: frame.minX + 6, dy: frame.midY + frame.height * 0.35))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: frame.minX + 6, dy: frame.midY - frame.height * 0.35)))
        }
    }
}
