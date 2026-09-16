import XCTest

/// **A two-finger gesture that begins on the surround moves the canvas.** The owner, 2026-09-16:
/// *"I cant move the canvas when by touching outside the canvas. I suspect this one could be deep
/// and connected to many more bugs."*
///
/// It was structural rather than deep: the navigation transform — pan, pinch, rotation — was
/// mounted on `CanvasContainerView`, whose bounds are the document exactly, and `UIView.hitTest`
/// never reaches a subview for a point outside the receiver's bounds. So a touch on the black
/// around the paper hit-tested to `CanvasHostView` and reached no canvas recognizer at all
/// (`CanvasContainerView`'s doc had recorded the same fact from the grip side on 2026-09-06). The
/// transform now lives on the host — `CanvasView.Coordinator.setUpGestures(host:container:)` —
/// and the five recognizers that act on a point of the artwork stay on the container.
///
/// **Why a rotate on a tall, narrow canvas.** XCUITest's only multi-touch gestures are `pinch` and
/// `rotate`, both centred on the element they are sent to, with no way to say where the fingers
/// land — so where they land was MEASURED with the action recorder: a pinch *out* starts its two
/// fingers 5 pt apart at the element's centre, a pinch *in* starts them at the element's diagonal
/// corners (one of which is off the host, on the timeline), and a rotate starts them about 47 pt
/// either side of the centre. A 64×4096 document fits its height and leaves the paper a strip some
/// 20 pt wide down the middle of the host, so a rotate's fingers both land on the surround. Against
/// the unfixed code it turned nothing; against the fix it turns the canvas.
///
/// The quarter-turn asked for is well past `CanvasView.Coordinator.rotationSnapThreshold`, so the
/// snap to a right angle does not swallow it.
///
/// Its own class because xcodebuild distributes parallel work per test *class* (see CLAUDE.md).
final class CanvasSurroundTransformUITests: PaintUITestCase {

    func testARotationThatBeginsOnTheSurroundTransformsTheCanvas() throws {
        let app = XCUIApplication()
        app.launch()

        let newCanvas = app.buttons["gallery.newCanvasButton"]
        XCTAssertTrue(newCanvas.waitForExistence(timeout: 10))
        newCanvas.tap()

        let widthField = app.textFields["sizePicker.widthField"]
        let heightField = app.textFields["sizePicker.heightField"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 10))
        setField(widthField, to: "64")
        setField(heightField, to: "4096")
        app.buttons["sizePicker.createButton"].tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 10))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let before = readTransform(app)
        canvas.rotate(.pi / 2, withVelocity: 1.0)
        let after = readTransform(app)
        XCTAssertNotEqual(before, after,
                          "a rotate whose fingers landed on the surround moved nothing (xform \(before) -> \(after))")
    }

    private func setField(_ field: XCUIElement, to value: String) {
        field.tap()
        let currentLength = (field.value as? String)?.count ?? 0
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentLength)
        field.typeText(clear + value)
    }

    /// The `xform:` field of `canvas.host`'s accessibility label — "scale,rotation,dx,dy", the
    /// device `CanvasTransformFreezeUITests` reads for the same reason: XCUITest can read neither a
    /// recognizer's state nor a view's transform.
    private func readTransform(_ app: XCUIApplication) -> String {
        let label = app.otherElements["canvas.host"].label
        guard let field = label.split(separator: " ").first(where: { $0.hasPrefix("xform:") }) else {
            return "?(\(label))"
        }
        return String(field.dropFirst("xform:".count))
    }
}
