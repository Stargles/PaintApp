import XCTest

/// **Cold-start reachability for TODO (77)** — the owner's report was *"going out of the canvas to
/// gallery then back resets a bunch of things, like your brush size and opacity, the frame you are
/// on, etc."*, and `EditorStateLogicTests` proves the manifest and the preferences round-trip a
/// value without proving an artist ever reaches either. This drives the trip: a new document, four
/// things changed the way the artist changes them, out to the gallery, back in, and each read off
/// the screen rather than off the model.
final class EditorStateRoundTripUITests: PaintUITestCase {

    /// The rail's Size/Opacity sliders are `SideToolbar.VerticalSlider`s — see
    /// `BrushSizeSliderUITests.dragVerticalSlider` for why a drag has to start on the thumb: **0 is
    /// the visual top** (maximum) and **1 the bottom** (minimum).
    private func dragVerticalSlider(_ slider: XCUIElement, fromNormalizedDy from: CGFloat, toNormalizedDy to: CGFloat) {
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// The `xform:` field of `canvas.host`'s accessibility label — "scale,rotation,dx,dy", the one
    /// place the navigation transform is legible to a test (`CanvasTransformFreezeUITests`).
    private func readTransform(_ app: XCUIApplication) -> String {
        let label = app.otherElements["canvas.host"].label
        guard let field = label.split(separator: " ").first(where: { $0.hasPrefix("xform:") }) else {
            return "?(\(label))"
        }
        return String(field.dropFirst("xform:".count))
    }

    private func readBadge(_ app: XCUIApplication, _ identifier: String) -> String {
        app.otherElements[identifier].value as? String ?? "?"
    }

    func testBrushSizeOpacityFrameAndZoomAreWhatTheyWereAfterTheGalleryRoundTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "PREMISE: the canvas is up")
        let sizeSlider = app.sliders["sideToolbar.brushSizeSlider"]
        let opacitySlider = app.sliders["sideToolbar.brushOpacitySlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5), "PREMISE: the brush tool is the default, so its rail is up")
        XCTAssertTrue(opacitySlider.exists, "PREMISE: and the opacity slider beside it")
        let defaultSize = readBadge(app, "sideToolbar.brushSizeReadout")
        let defaultOpacity = readBadge(app, "sideToolbar.brushOpacityReadout")
        let defaultTransform = readTransform(app)
        XCTAssertEqual(defaultOpacity, "100%", "PREMISE: a fresh launch starts from the default tools")

        // 1. Size: the default sits at the bottom of the rail; drag the thumb up to the middle.
        dragVerticalSlider(sizeSlider, fromNormalizedDy: 1.0, toNormalizedDy: 0.5)
        let size = readBadge(app, "sideToolbar.brushSizeReadout")
        XCTAssertNotEqual(size, defaultSize, "PREMISE: the size slider moved (\(size))")

        // 2. Opacity: 100% sits at the top; drag the thumb down to the middle.
        dragVerticalSlider(opacitySlider, fromNormalizedDy: 0.02, toNormalizedDy: 0.5)
        let opacity = readBadge(app, "sideToolbar.brushOpacityReadout")
        XCTAssertNotEqual(opacity, "100%", "PREMISE: the opacity slider moved (\(opacity))")

        // 3. Frame: scrub the ruler a few frames to the right.
        let ruler = app.otherElements["timeline.ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        let rulerStart = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        rulerStart.press(forDuration: 0.2, thenDragTo: rulerStart.withOffset(CGVector(dx: 150, dy: 0)),
                         withVelocity: .slow, thenHoldForDuration: 0.2)
        let frame = try XCTUnwrap(readFrameLabel(app)).current
        XCTAssertGreaterThan(frame, 1, "PREMISE: the playhead moved off the first frame")

        // 4. Zoom: a two-finger pinch on the canvas.
        canvas.pinch(withScale: 2.0, velocity: 1.5)
        let transform = readTransform(app)
        XCTAssertNotEqual(transform, defaultTransform, "PREMISE: the canvas zoomed (\(transform))")

        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "1-before-leaving-to-the-gallery"
        before.lifetime = .keepAlways
        add(before)

        // Out, and back in — the round trip the owner described.
        let tile = saveEditorAndReturnToGallery(app)
        tile.tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 15),
                      "Tapping the tile reopens the document in the editor")
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5), "The brush tool comes back with its rail")

        XCTAssertEqual(readBadge(app, "sideToolbar.brushSizeReadout"), size,
                       "The brush size is what the artist left it at, not the preset's")
        XCTAssertEqual(readBadge(app, "sideToolbar.brushOpacityReadout"), opacity,
                       "The brush opacity too")
        XCTAssertEqual(readFrameLabel(app)?.current, frame,
                       "The document reopens on the frame the artist was on")
        XCTAssertEqual(readTransform(app), transform,
                       "…and at the zoom they had, to the four decimals the label prints")

        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "2-reopened-from-the-gallery"
        after.lifetime = .keepAlways
        add(after)
    }
}
