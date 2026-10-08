import XCTest

/// **The colour panel shows its whole Recent strip and the whole selected palette, in landscape** —
/// the owner, 2026-10-01: *"the color picker should be extended downwards. I want both the recent and
/// color palette to be fully shown in horizontal mode. Seems you have alot of room to extend it
/// downwards too. The position of the switch also should not take up much space. I think a good place
/// to fit it can be on the top right, the same row as the previous/current color indicator."*
///
/// Nothing in the model can say whether a swatch is *reachable*: a swatch can be correct, in the tree
/// and under a scroll view's fold. So this asserts what the artist needs — every swatch is hittable
/// without touching the panel's scroll — in the orientation the owner named, with a full strip
/// (`-uiTestSeedColorHistory`) and the default palette. It runs on whatever device the run names: the
/// 13-inch Pro has the room the owner means, and the 9th-generation iPad (810 pt of landscape height)
/// is the owner's own and the one the panel must also fit.
final class ColorPanelFitUITests: PaintUITestCase {

    func testTheRecentStripAndTheWholePaletteAreHittableWithoutScrollingInLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-resetPalettes", "-uiTestSeedColorHistory"]
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.colorButton"].tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForExistence(timeout: 5),
                      "the colour button opens the panel")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "setup: the app is in landscape (\(window))")
        attachScreenshot(XCUIScreen.main, "colour-panel-landscape-\(Int(window.width))x\(Int(window.height))")

        func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        // The Recent strip: all twenty colours the seed painted with.
        for index in 0..<20 {
            let swatch = element("colorPanel.history.swatch.\(index)")
            XCTAssertTrue(swatch.exists, "Recent swatch \(index) is in the panel")
            XCTAssertTrue(swatch.isHittable, "Recent swatch \(index) is on screen without scrolling")
        }

        // The selected palette — Spectrum, twenty colours — and the cell that adds the next one.
        for index in 0..<20 {
            let swatch = element("colorPanel.swatch.\(index)")
            XCTAssertTrue(swatch.exists, "palette swatch \(index) is in the panel")
            XCTAssertTrue(swatch.isHittable, "palette swatch \(index) is on screen without scrolling")
        }
        XCTAssertTrue(element("colorPanel.addSwatchButton").isHittable,
                      "the palette's add cell is on screen too")

        // Everything above the fold stays where it was: the switch is on the current/previous row.
        XCTAssertTrue(element("colorPanel.eyedropperMode.layer").isHittable, "the eyedropper switch is on screen")
        XCTAssertTrue(element("colorPanel.currentSwatch").isHittable)
        let switchFrame = element("colorPanel.eyedropperMode.layer").frame
        let currentFrame = element("colorPanel.currentSwatch").frame
        XCTAssertEqual(switchFrame.midY, currentFrame.midY, accuracy: 24,
                       "the switch shares a row with the previous/current colour indicator")
        XCTAssertGreaterThan(switchFrame.midX, currentFrame.midX, "…at its right")
    }
}
