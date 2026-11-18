import XCTest

/// **A bucket fill the memory budget refuses says so on screen** — AUDIT-2026-11-16 §2's "the artist
/// taps something and nothing happens". Cold start, new document, a budget far too small for any
/// fill window (`-uiTestTextureBudgetBytes`, simulator-only), one tap with the bucket. What is read
/// is the banner the artist sees — its accessibility value is the case code and its label the
/// sentence — not a model value; the logic tier owns every other refusal site
/// (`MemoryBudgetLogicTests`, `WorkRefusalNoticeLogicTests`).
final class FillRefusalNoticeUITests: PaintUITestCase {

    func testABucketFillTheBudgetRefusesShowsTheNoticeOnScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestTextureBudgetBytes", "64"]
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // First tap selects the tool.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8),
                      "a refused fill must put a banner on screen instead of doing nothing")
        XCTAssertEqual(notice.value as? String, "fillNeedsMoreMemory",
                       "the banner names the refusal by its case code")
        XCTAssertTrue(notice.label.contains("Not enough memory"),
                      "and says it in words an artist reads — got \"\(notice.label)\"")
        attachScreenshot(app, "fill-refused-notice-landscape")
    }
}
