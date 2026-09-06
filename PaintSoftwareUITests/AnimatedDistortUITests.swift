import XCTest

/// **An animated Distort, driven the way the artist drives it** — KEYFRAMES.md §8 stage 5b.
///
/// `AnimatedDistortLogicTests` owns the arithmetic: that the key stores a keystone, that both render
/// reads answer a projective map, that the blend carries the perspective row. Three things it cannot
/// say, and all three are what this file is for:
///
///  * that the **Distort segment is offered** on a float raised over a cel that carries pose keys —
///    the caption arm has been wrong about a whole tier twice now (a lassoed drawing until
///    2026-09-06, a transformation layer until stage 5b), and only a running bar can answer it;
///  * that **the keyframe workflow and the Move box meet** — mark, scrub, Move, Distort, Done, mark.
///    Every step is a different view and the model cannot see whether an artist can get from one to
///    the next;
///  * that a **scrubbed in-between shows a keystone on the canvas**. That is the whole feature, and
///    the measurement is one an affine cannot fake: two lines of the same length end up **different
///    lengths**, which every affine map there is leaves equal. If the blend dropped the perspective
///    row, or if a render read went back to the linearisation, the in-between would show two lines
///    of one length and this goes red.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class AnimatedDistortUITests: PaintUITestCase {

    /// One screenshot of the canvas, as an "is there dark ink at this normalized point" probe.
    /// `DistortUITests.inkProbe`'s twin — dark rather than not-white, because the canvas is
    /// letterboxed inside a black host and a not-white test answers `true` for the whole margin.
    private func inkProbe(_ canvas: XCUIElement) throws -> (Double, Double) -> Bool {
        let image = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return { dx, dy in
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            let offset = y * width * 4 + x * 4
            return buffer[offset] < 100 && buffer[offset + 1] < 100 && buffer[offset + 2] < 100
        }
    }

    /// A probe taken once the canvas has stopped changing — two consecutive fingerprints that agree,
    /// or the last one at the deadline. The resting canvas is served from a baked frame that arrives
    /// *after* the gesture, so a screenshot on the next line can catch the frame before the commit.
    private func settledProbe(_ canvas: XCUIElement,
                              timeout: TimeInterval = 6) throws -> (Double, Double) -> Bool {
        func fingerprint(_ probe: (Double, Double) -> Bool) -> [Bool] {
            (0..<24).flatMap { yi in (0..<24).map { xi in
                probe(0.15 + 0.75 * Double(xi) / 24, 0.10 + 0.40 * Double(yi) / 24)
            } }
        }
        var probe = try inkProbe(canvas)
        var previous = fingerprint(probe)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let next = try inkProbe(canvas)
            let current = fingerprint(next)
            probe = next
            if current == previous { return probe }
            previous = current
        }
        return probe
    }

    /// **Every inked row of the canvas, as `(y, leftmost x, width)`** — one scan, and the only
    /// geometry this file measures.
    ///
    /// **A row that spans essentially the whole window is the letterbox, not ink.** The canvas is
    /// centred inside a black `canvas.host`, so the bands around it read as ink to a darkness probe —
    /// seven solid rows across the top, measured. Skipping them by width rather than by a hardcoded
    /// margin is what stops the scan reporting the *window's own corner*, which is what a not-ink
    /// answer looks like and what cost `DistortUITests` two runs through the same door.
    ///
    /// **Every row, not every third.** A single brush stroke here is about **0.002** of the
    /// screenshot's height, so a three-row stride steps straight over it and the scan reports an
    /// empty canvas with a line plainly on it. That cost this file two runs of its own.
    private func inkedRows(_ probe: (Double, Double) -> Bool,
                           from y0: Double = 0.02, to y1: Double = 0.75)
        -> [(y: Double, left: Double, width: Double)] {
        let rowSteps = 600, columnSteps = 320
        var rows: [(y: Double, left: Double, width: Double)] = []
        for i in 0...rowSteps {
            let y = y0 + (y1 - y0) * Double(i) / Double(rowSteps)
            let hits = (0...columnSteps).filter { probe(0.05 + 0.90 * Double($0) / Double(columnSteps), y) }
            guard let first = hits.first, let last = hits.last else { continue }
            let width = 0.90 * Double(last - first) / Double(columnSteps)
            guard width < 0.85 else { continue }   // a solid row is the letterbox
            rows.append((y, 0.05 + 0.90 * Double(first) / Double(columnSteps), width))
        }
        return rows
    }

    /// **The two drawn lines, each as its full horizontal extent** — the only geometry this file
    /// measures.
    ///
    /// Two lines the same length become two lines of *different* lengths under a foreshortening and
    /// stay the same length under every affine there is, so the ratio between these two numbers is
    /// the whole assertion.
    ///
    /// **The extent across a cluster's rows, not the widest single row.** A scrubbed in-between sits
    /// a fraction of a degree off level — MEASURED at 0.5-0.7° on this pair of keys, which is the
    /// factored blend's own arithmetic and not a defect — and a line one stroke thick that is tilted
    /// by a degree occupies **no single row of the screenshot**: the per-row reading collapsed a
    /// 0.47-long line into fifteen 0.03-long slices and read as a drawing that had gone. Taking the
    /// cluster's min-left to max-right is level-tolerant and reads the same number on a level line.
    ///
    /// The rows fall into two clusters because the drawing is two lines; the gap between them is by
    /// far the largest gap in the list, so splitting there needs no threshold.
    private func inkLines(_ probe: (Double, Double) -> Bool)
        -> (top: (y: Double, left: Double, width: Double),
            bottom: (y: Double, left: Double, width: Double))? {
        let rows = inkedRows(probe)
        guard rows.count > 1 else { return nil }
        var split = 1
        var widest = 0.0
        for i in 1..<rows.count where rows[i].y - rows[i - 1].y > widest {
            widest = rows[i].y - rows[i - 1].y
            split = i
        }
        func line(_ cluster: ArraySlice<(y: Double, left: Double, width: Double)>)
            -> (y: Double, left: Double, width: Double)? {
            guard let left = cluster.map(\.left).min(),
                  let right = cluster.map({ $0.left + $0.width }).max(),
                  let y = cluster.map(\.y).min() else { return nil }
            return (y, left, right - left)
        }
        guard let top = line(rows[..<split]), let bottom = line(rows[split...]) else { return nil }
        return (top, bottom)
    }

    /// Moves the playhead by tapping the cel block, and raises its menu with a second tap.
    private func markKeyframe(_ app: XCUIApplication, onCelAt dx: Double) {
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5))
        let target = cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
        target.tap()
        target.tap()
        let add = app.buttons["timeline.menu.Add Keyframe"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "The second tap raises the cel menu")
        add.tap()
    }

    private func scrub(_ app: XCUIApplication, toCelFraction dx: Double) {
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5))
        cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    private func attach(_ canvas: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: canvas.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **Mark, scrub, Move, Distort, Done, mark — and every frame between the two marks shows a
    /// keystone.**
    ///
    /// The gesture is §2.26/§2.27's own workflow with a Distort in the middle of it, and the
    /// assertion is on the *in-between*, not on either key: a constant-width line drawn flat becomes
    /// visibly thicker at one end at frame 6, which no affine map of it can be. That is
    /// simultaneously a test of the writer (the key kept the keystone), the blend (the perspective
    /// row survived) and the render read (the channel handed the renderer a homography), and it fails
    /// if any one of the three flattens.
    ///
    /// **The wedge at the in-between is also strictly milder than at the key**, which is what stops
    /// this passing for the wrong reason: a track that simply held keyframe B's pose everywhere would
    /// satisfy the first assertion and not the second.
    func testAKeyedDistortShowsAKeystoneAtEveryFrameBetweenTheTwoMarks() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // **Two parallel lines the same length**, on the default vector layer so they lift as
        // geometry rather than as pixels. Two lines rather than one because the measurement is their
        // *lengths*: a foreshortening makes the far one shorter and every affine there is leaves them
        // equal, so the pair is an operand no affine can fake. (A single line's *thickness* would do
        // the same job in principle and not in practice — a stroke is about 0.002 of this
        // screenshot's height, which is four samples to measure a change in.)
        dragOnCanvas(app, from: CGVector(dx: 0.20, dy: 0.20), to: CGVector(dx: 0.85, dy: 0.20))
        dragOnCanvas(app, from: CGVector(dx: 0.20, dy: 0.42), to: CGVector(dx: 0.85, dy: 0.42))
        let drawn = try settledProbe(canvas)
        let flat = try XCTUnwrap(inkLines(drawn), "setup: there is ink on the canvas")
        attach(canvas, "1-two-flat-lines-at-frame-0")
        XCTAssertGreaterThan(flat.top.width, 0.30, "setup: the top line is most of the way across")
        XCTAssertEqual(flat.top.width, flat.bottom.width, accuracy: 0.03,
                       String(format: "setup: and the two are the same length before anything "
                              + "distorts them — top %.3f, bottom %.3f",
                              flat.top.width, flat.bottom.width))

        // Keyframe A: a bare mark at the first frame — §2.26's first step.
        markKeyframe(app, onCelAt: 0.04)
        XCTAssertTrue(app.otherElements["timeline.keyMarkers.0"].waitForExistence(timeout: 5),
                      "the mark is on the timeline where the artist can see it")

        // Scrub to the far end of the block, raise the Move box, and pick Distort.
        scrub(app, toCelFraction: 0.95)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move with no selection floats the whole drawing")
        let caption = app.staticTexts["moveBar.modeCaption"]
        let distort = app.buttons["Distort"]
        XCTAssertTrue(distort.waitForExistence(timeout: 5), "the mode picker offers Distort")
        distort.tap()
        XCTAssertFalse(caption.waitForExistence(timeout: 2),
                       "and a drawing on a keyframed cel is not one of the things it declines")

        // Pull the box's top-left grip inward along the top edge. The top line shortens and the
        // bottom one does not, which is a keystone and not any affine of two parallel lines.
        let top = try XCTUnwrap(inkLines(try settledProbe(canvas))?.top,
                                "the box hugs the ink, so its top grips are on the top line's own "
                                + "ends — measured, because a synthetic drag undershoots and the "
                                + "grip is under ten screen points across")
        // **Both top corners, inward by the same amount — a *symmetric* keystone.** Pulling one
        // corner alone is a keystone too, and it was the first thing this test tried; the trouble is
        // what it does to the in-between rather than to the key. An asymmetric quad's affine factor
        // carries a shear, `Matrix2x2.polar` reports a shear as a rotation (which
        // `PoseComponentsLogicTests` pins in as many words), and §4.3's factored blend therefore
        // *turns* the drawing on its way between the two keys — MEASURED as a 43-row diagonal streak
        // where two horizontal lines were expected. That is the shipped blend behaving as §4.3 says
        // it should, and it makes "how long is each line" the wrong ruler. A symmetric pull has a
        // pure scale for its affine factor, so the in-between stays level and the only thing moving
        // is the foreshortening this test is about.
        dragOnCanvas(app, from: CGVector(dx: top.left, dy: top.y),
                     to: CGVector(dx: top.left + 0.09, dy: top.y))
        dragOnCanvas(app, from: CGVector(dx: top.left + top.width, dy: top.y),
                     to: CGVector(dx: top.left + top.width - 0.09, dy: top.y))
        XCTAssertTrue(app.buttons["moveBar.resetButton"].isEnabled,
                      "a pulled corner is a change Reset has to be able to put back")
        app.buttons["moveBar.doneButton"].tap()

        let keyed = try XCTUnwrap(inkLines(try settledProbe(canvas)))
        let atB = (top: keyed.top.width, bottom: keyed.bottom.width)
        attach(canvas, "2-keystone-at-keyframe-B")
        XCTAssertLessThan(atB.top, atB.bottom - 0.05, String(format: """
            setup: the committed drawing is a keystone — top %.3f, bottom %.3f
            """, atB.top, atB.bottom))

        // Keyframe B: the second mark commits §2.27's held pose and makes the pair an animation.
        markKeyframe(app, onCelAt: 0.95)

        // …and the frame halfway between them is a *partial* keystone: the top line is shorter than
        // the bottom one, and by less than at B.
        scrub(app, toCelFraction: 0.5)
        let between = try XCTUnwrap(inkLines(try settledProbe(canvas)))
        let mid = (top: between.top.width, bottom: between.bottom.width)
        attach(canvas, "3-in-between-at-the-midpoint")

        XCTAssertGreaterThan(mid.bottom, 0.20, "the drawing is still on the canvas at the in-between")
        XCTAssertLessThan(mid.top, mid.bottom - 0.02, String(format: """
            The scrubbed in-between shows two lines of one length, so the keystone was flattened \
            somewhere between the key and the canvas — top %.3f, bottom %.3f
            """, mid.top, mid.bottom))
        // MEASURED on this document: the two lines differ by **0.112** of the canvas at the
        // midpoint and by **0.197** at keyframe B, against **0.000** where the artist drew them. A
        // track that held B's pose everywhere would read 0.197 at both, and one that flattened the
        // keystone would read 0.000 at both.
        XCTAssertLessThan(mid.bottom - mid.top, atB.bottom - atB.top, String(format: """
            The in-between is exactly as keystoned as keyframe B, so the track is holding B's pose \
            rather than blending toward it — mid %.3f, B %.3f
            """, mid.bottom - mid.top, atB.bottom - atB.top))
    }
}
