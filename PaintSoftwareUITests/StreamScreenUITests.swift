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

    /// **TODO.md item (101), cold start: the sheet says *why*, not "did not answer" for everything.**
    /// `127.0.0.1` refuses a TCP connect immediately when nothing listens on the port — no laptop, no
    /// Tailscale, no timeout to wait out on a real network — so **refused** is the one
    /// `StreamConnectFailure` case a simulator can drive deterministically end to end; the other three
    /// (unreachable, Local Network permission, locked) need a real address, a real permission prompt
    /// and a real streamer respectively, none of which exist in this suite — see TODO.md's own note
    /// that the permission prompt and Nearby are proved on the owner's iPad, not here.
    func testStreamScreenConnectSheetShowsTheRefusedMessageWhenNothingListens() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        app.buttons["toolbar.addButton"].tap()
        let row = app.buttons["add.streamScreenRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()

        let address = app.textFields["streamConnect.addressField"]
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        // Port first, so `canConnect` is already true once the address field's own `onSubmit`
        // fires — the address field carries `.submitLabel(.go)` for exactly this, and pressing
        // the keyboard's own Go is a more direct route to `connect()` than the nav-bar button
        // sitting behind whichever field currently holds focus.
        let port = app.textFields["streamConnect.portField"]
        setField(port, to: "59191")
        address.tap()
        let currentLength = (address.value as? String)?.count ?? 0
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentLength)
        address.typeText(clear + "127.0.0.1\n")

        // `Label(_:systemImage:)` combines its icon and the sentence into one accessibility element
        // (`StreamConnectSheet`'s own `.accessibilityElement(children: .combine)`), matched here by
        // identifier across any element type rather than guessing `staticTexts` versus `otherElements`.
        //
        // **The failure Section is the Form's own last row, and the Form is a `List`.** With Nearby
        // actually finding a real advertiser (TODO (101)'s own Info.plist fix is what makes that
        // possible at all — see `testStreamScreenSheetDrawsANearbySectionAboveTheAddressField`'s own
        // note), the extra row can push the failure Section below a `.medium` sheet's visible fold,
        // and a `List` only instantiates rows it has actually laid out — so the element may not
        // exist in the accessibility tree at all until scrolled to. Swipe the sheet up until it does.
        let failure = app.descendants(matching: .any).matching(identifier: "streamConnect.failureMessage").firstMatch
        let sheet = app.otherElements.containing(.textField, identifier: "streamConnect.addressField").firstMatch
        let deadline = Date().addingTimeInterval(20)
        while !failure.exists && Date() < deadline {
            (sheet.exists ? sheet : app.windows.firstMatch).swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(failure.exists, "a refused connect shows the failure banner")
        XCTAssertTrue(failure.label.contains("PaintStreamer"),
                      "the refused case names the streamer, not a generic \"did not answer\": \(failure.label)")
        XCTAssertFalse(app.buttons["streamConnect.openSettingsButton"].exists,
                       "the Settings button is only for the Local Network permission case")

        app.buttons["streamConnect.cancelButton"].tap()
    }

    /// The address and port fields raise a keyboard with no built-in "select all" — cleared one
    /// `delete` at a time, `LargeCanvasFillUITests`' own way of doing this to a text field.
    private func setField(_ field: XCUIElement, to value: String) {
        field.tap()
        let currentLength = (field.value as? String)?.count ?? 0
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentLength)
        field.typeText(clear + value)
    }

    /// TODO (98): the "Nearby" section — this pins that the section itself is drawn above the
    /// address field: CLAUDE.md's rule that a feature whose model is correct but whose surface was
    /// never looked at can still ship unusable.
    ///
    /// **What it finds is genuinely environment-dependent since TODO (101) added the Info.plist keys
    /// `NWBrowser` needs.** Before them the browse was silently refused by iOS with no error and no
    /// permission prompt, so the empty state (`streamConnect.nearbyEmpty`) was the only outcome this
    /// test could ever see — that used to be pinned here as *the* expected result. With the keys in
    /// place, a host that can actually reach a `_paintstream._tcp` advertiser sees a row instead of
    /// the empty state, and this build's own CI host does — the real laptop `tools/windows
    /// /streamer-remote.sh` also reaches is visible to `NWBrowser` here, over whatever route carries
    /// it. So this asserts the section renders correctly either way instead of pinning one outcome;
    /// `StreamDiscoveryLogicTests` is what actually pins the result-handling logic with no real
    /// network at all.
    func testStreamScreenSheetDrawsANearbySectionAboveTheAddressField() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        app.buttons["toolbar.addButton"].tap()
        let row = app.buttons["add.streamScreenRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let nearbyHeader = app.staticTexts["streamConnect.nearbyHeader"]
        XCTAssertTrue(nearbyHeader.waitForExistence(timeout: 10), "the Nearby section header is drawn")
        let address = app.textFields["streamConnect.addressField"]
        XCTAssertTrue(address.exists, "the address field is still reachable")
        // "Above the address field": in a Form, the earlier Section's elements precede the
        // later Section's in the accessibility tree top-to-bottom, so the header's frame must
        // sit higher on screen than the address field's.
        XCTAssertLessThan(nearbyHeader.frame.minY, address.frame.minY,
                           "Nearby is drawn above the Computer address section")

        let empty = app.staticTexts["streamConnect.nearbyEmpty"]
        let foundRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'streamConnect.nearbyRow.'")).firstMatch
        let deadline = Date().addingTimeInterval(10)
        var settled = false
        while Date() < deadline {
            if empty.exists || foundRow.exists { settled = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(settled, "Nearby should settle into either the empty state or a found laptop's row")

        app.buttons["streamConnect.cancelButton"].tap()
    }
}
