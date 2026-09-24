import XCTest

/// **Cold-start reachability for Actions → Stream Screen** — STREAM.md §7 stage 1's "a cold-start
/// XCUITest reaches the sheet from a new document", and CLAUDE.md's rule that a feature whose
/// only entry point cannot be reached from a fresh document is not finished whatever its model
/// says.
///
/// From the gallery: New Canvas → Create → Actions → Add → the Stream Screen row → the sheet with an
/// address field, a port field prefilled with 47301 and a Connect button (TODO (100) moved Stream
/// Screen under the "Add" submenu; the row and the sheet it opens are unchanged). **It does not
/// connect** — there is no laptop in the suite, and `StreamInsertLogicTests` covers everything past the sheet
/// with a status built by hand. What it also pins: Connect is disabled while the address is empty,
/// and enabled once one is typed, so the artist is never looking at a button that does nothing.
///
/// Its own class rather than a row in `ToolPanelsUITests`, against that file's own advice, because
/// the sheet is the whole of a new feature's front door and a red here should name it.
final class StreamScreenUITests: PaintUITestCase {

    func testStreamScreenIsReachableFromANewDocumentAndOpensTheConnectSheet() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        // TODO (103): Stream Screen is a row of the "Add" menu, its own top-bar icon since.
        app.buttons["toolbar.addButton"].tap()
        let row = app.buttons["add.streamScreenRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Stream Screen is a row in the Add menu")
        XCTAssertTrue(row.isEnabled, "…and a document with a canvas can host a stream")
        row.tap()

        let address = app.textFields["streamConnect.addressField"]
        XCTAssertTrue(address.waitForExistence(timeout: 5), "the row opens the connect sheet")
        let port = app.textFields["streamConnect.portField"]
        XCTAssertTrue(port.exists, "with a port field")
        XCTAssertEqual(port.value as? String, "47301", "prefilled with paintstream/1's port")
        let connect = app.buttons["streamConnect.connectButton"]
        XCTAssertTrue(connect.exists, "and a Connect button")

        if (address.value as? String ?? "").isEmpty || address.value as? String == "Computer's address" {
            XCTAssertFalse(connect.isEnabled, "Connect is disabled until there is an address to connect to")
            address.tap()
            address.typeText("desktop-cbr0fl6")
            XCTAssertTrue(connect.waitForExistence(timeout: 2))
            XCTAssertTrue(connect.isEnabled, "and enabled once one is typed")
        } else {
            // A previous run on this simulator left an address in `UserDefaults`; the prefill is
            // the feature working, and Connect must already be enabled on it.
            XCTAssertTrue(connect.isEnabled, "a prefilled address enables Connect")
        }

        app.buttons["streamConnect.cancelButton"].tap()
        XCTAssertFalse(address.waitForExistence(timeout: 2), "Cancel closes the sheet without connecting")
    }

    /// TODO (98): the "Nearby" section — cold start, no laptop reachable from the simulator (no
    /// network at all in CI), so the only thing this can and does pin is that the section itself
    /// is drawn above the address field: CLAUDE.md's rule that a feature whose model is correct
    /// but whose surface was never looked at can still ship unusable. The empty state
    /// (`streamConnect.nearbyEmpty`) is the expected result off-network, not a fallback being
    /// tolerated — `StreamDiscoveryLogicTests` covers what happens once `NWBrowser` actually finds
    /// something.
    func testStreamScreenSheetDrawsANearbySectionAboveTheAddressField() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        app.buttons["toolbar.addButton"].tap()
        let row = app.buttons["add.streamScreenRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let nearbyHeader = app.staticTexts["streamConnect.nearbyHeader"]
        XCTAssertTrue(nearbyHeader.waitForExistence(timeout: 5), "the Nearby section header is drawn")
        let address = app.textFields["streamConnect.addressField"]
        XCTAssertTrue(address.exists, "the address field is still reachable")
        // "Above the address field": in a Form, the earlier Section's elements precede the
        // later Section's in the accessibility tree top-to-bottom, so the header's frame must
        // sit higher on screen than the address field's.
        XCTAssertLessThan(nearbyHeader.frame.minY, address.frame.minY,
                           "Nearby is drawn above the Computer address section")

        let empty = app.staticTexts["streamConnect.nearbyEmpty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "off-network, the empty state is what Nearby shows")

        app.buttons["streamConnect.cancelButton"].tap()
    }
}
