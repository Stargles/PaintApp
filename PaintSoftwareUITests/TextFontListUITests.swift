import XCTest

/// **TODO (115) — the font list shows each font in itself.** The owner: *"When adding text and
/// selecting the font, I currently have no idea what the fonts look like. Make the fonts font in the
/// selector menu the actual font."*
///
/// XCUITest cannot read a glyph, so each row exposes the PostScript name of the face it is **drawn
/// in** as its accessibility value (`FontFamilyList.row`) — the value is read off the same
/// `FontLibrary.previewFont` the row's font comes from, so a list drawn in the system face throughout
/// reads the system face on every row and goes red here. The screenshot attached is the other half:
/// the artist's own view of it.
final class TextFontListUITests: PaintUITestCase {

    func testEveryRowOfTheFontListIsDrawnInItsOwnFace() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")

        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()
        let fontButton = app.buttons["textPanel.fontButton"]
        XCTAssertTrue(fontButton.waitForExistence(timeout: 5), "PREMISE: the text panel is up")
        XCTAssertEqual(fontButton.value as? String, "System", "the panel opens on the system font")
        fontButton.tap()

        // The rows the list shows first: the system face, then the Serif families — chosen by asking
        // the same library the app asks, so the test names no family the device might not ship.
        let groups = FontLibrary.shared.groups()
        let families = groups.prefix(2).flatMap { group in group.families.prefix(3).map { ($0, group.packID) } }
        XCTAssertGreaterThanOrEqual(families.count, 3, "PREMISE: the device ships fonts to list")

        var faces: [String] = []
        for (family, packID) in families {
            let row = app.buttons["textPanel.font.\(family)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "the list has a row for \(family)")
            let drawnIn = try XCTUnwrap(row.value as? String, "\(family)'s row exposes the face it is drawn in")
            let expected = FontLibrary.shared.previewFont(inFamily: family, packID: packID, size: 20).fontName
            XCTAssertEqual(drawnIn, expected, "\(family)'s row is drawn in \(expected), not in another face")
            faces.append(drawnIn)
        }
        XCTAssertEqual(Set(faces).count, faces.count,
                       "no two of these families share a face — a list drawn in one font throughout would")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "font-list-in-own-faces"
        shot.lifetime = .keepAlways
        add(shot)

        // Choosing a row picks the family and closes the list.
        let (family, _) = try XCTUnwrap(families.last)
        app.buttons["textPanel.font.\(family)"].tap()
        XCTAssertTrue(app.buttons["textPanel.font.\(family)"].waitForNonExistence(timeout: 5), "choosing a row closes the list")
        XCTAssertEqual(fontButton.value as? String, family, "…and the panel shows the family picked")
    }
}
