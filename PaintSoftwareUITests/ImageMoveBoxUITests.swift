import XCTest

/// **A picture's Move box is the picture** — TODO (120), the owner's *"when moving an image, right now
/// the move box is vastly bigger than the actual bounding box of the image itself."*
///
/// `PlacedImageShapeLogicTests` owns the measurement: that `MoveBoxInk` reads a placed rectangle by its
/// four corners. What it cannot say is whether the box **on the glass** is the rectangle the picture is
/// drawn in — the overlay is `CALayer`s, so nothing but a published number can tell a test where it
/// is (`CanvasView.Coordinator.publishCanvasState`'s `movebox:` field), and nothing but the pixels can
/// say where the picture is. Both are read in the host's unit square, so they compare directly.
///
/// **The picture is a wide one on purpose.** A box that circumscribed a picture was a *square*, and a
/// square picture would have hidden half of the error — its box was only 1.41× too big on each side,
/// where a 4:1 picture's was 4× too tall.
final class ImageMoveBoxUITests: PaintUITestCase {

    /// The box as `x,y,w,h` in the host's unit square, or nil while there is none.
    private func moveBox(_ app: XCUIApplication) -> CGRect? {
        let field = readField(app, "movebox:")
        let parts = field.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// The box once it has stopped moving — **three reads 0.3 s apart that agree**. The box is up
    /// before the canvas has been fitted to its host, and until then it is published in the
    /// unfitted container's coordinates; the first non-nil reading is a real box in the wrong place.
    private func settledMoveBox(_ app: XCUIApplication, timeout: TimeInterval = 10) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        var agreeing = 0
        var last: CGRect?
        while Date() < deadline {
            let now = moveBox(app)
            agreeing = (now != nil && now == last) ? agreeing + 1 : 0
            last = now
            if agreeing >= 3 { return now }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return nil
    }

    /// The black rectangle's bounds in the host's unit square, measured off a screenshot of `window`.
    ///
    /// **A window rather than the whole host**, because the host extends under the toolbar, the Move
    /// bar and the timeline, whose dark glyphs would read as ink. The caller names the box's own
    /// rectangle grown by a margin, so a picture that stuck out of its box would still be found —
    /// and one far smaller than its box is measured as it is.
    private func inkBounds(_ probe: (Double, Double) -> Bool, in window: CGRect) throws -> CGRect {
        var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0
        let columns = 800, rows = 800
        for xi in 0...columns {
            for yi in 0...rows {
                let x = window.minX + window.width * Double(xi) / Double(columns)
                let y = window.minY + window.height * Double(yi) / Double(rows)
                guard probe(x, y) else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX < maxX, minY < maxY else { throw XCTSkip("no ink found in \(window)") }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **An imported wide picture arrives in a box that hugs it.** From a fresh document: the import
    /// lifts the picture into the Move box (TODO (34)), the box is read off the canvas's published
    /// state, and the picture is measured off a screenshot of the same canvas. The two rectangles
    /// have to agree to within the outline's own width and the antialiased edge.
    ///
    /// What the artist does next is drag the picture by the box — the same box, now the right size to
    /// grab, to turn about the picture's own centre and to scale from its own corners.
    func testAnImportedWidePictureIsHeldInABoxTheSizeOfThePicture() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedImage"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let box = try XCTUnwrap(settledMoveBox(app), "the import lifts the picture into a Move box — "
                                + "canvas.host says \(canvas.label)")

        let margin = 0.06
        let window = box.insetBy(dx: -margin, dy: -margin)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let probe = try settledProbe(canvas, window: window)
        let picture = try inkBounds(probe, in: window)
        attachScreen("image-move-box")
        let numbers = XCTAttachment(string: "box \(box)\npicture \(picture)")
        numbers.name = "box-and-picture"
        numbers.lifetime = .keepAlways
        add(numbers)

        XCTAssertGreaterThan(picture.width / picture.height, 3.5,
                             "setup: the seeded picture is 4:1 and is drawn that shape")
        let tolerance = 0.012
        XCTAssertEqual(box.minX, picture.minX, accuracy: tolerance, "left edge: box \(box) picture \(picture)")
        XCTAssertEqual(box.maxX, picture.maxX, accuracy: tolerance, "right edge: box \(box) picture \(picture)")
        XCTAssertEqual(box.minY, picture.minY, accuracy: tolerance, "top edge: box \(box) picture \(picture)")
        XCTAssertEqual(box.maxY, picture.maxY, accuracy: tolerance, "bottom edge: box \(box) picture \(picture)")
    }
}
