import XCTest

/// **The graph editor band, from a real tap** — KEYFRAMES.md §11.3, stage D2.
///
/// Deliberately one small class of its own rather than a few methods added to `TimelineAndUndoUITests`
/// or `LayerPanelUITests`. `xcodebuild` distributes parallel work per test **class**, so a class is
/// indivisible and the longest one sets the whole suite's critical path — which today is
/// `LayerPanelUITests` at 515 s against a 22.3 min run (CLAUDE.md's cost model). Two tests hung off
/// one of those classes cost the suite their whole runtime; the same two in a class of their own cost
/// it nothing, because a spare clone runs them beside the long one.
///
/// **What is left for this tier and what is not.** Everything the band *draws* — the axis, the
/// clipping, the colours, the sampling density — is `TimelineGraphBandLogicTests`, run headlessly
/// against `TimelineGraphBand`, because XCUITest can see neither a `CGContext` nor a colour. This
/// file exists to prove the one thing the logic tier cannot: that the wiring from a real finger on a
/// real button through `CanvasManager`, `TimelineRowLayout`, `TimelineLayoutKey` and the UIKit
/// coordinator puts a band on the screen and takes it away again.
final class GraphEditorUITests: PaintUITestCase {

    /// The band opens on the selected layer, is visible, and closes.
    ///
    /// It is asserted on a *fresh* document, which animates nothing — so the band comes up reading
    /// `"empty"`, and that is the state being pinned rather than a shortcoming of the fixture. A
    /// band that opened on a layer with no animation and came up blank would leave the artist
    /// looking for a curve that was never there; saying `empty` is the answer, and it is also what
    /// makes this test independent of the several minutes of gestures it would take to author a
    /// curve through the settings bar.
    func testTheGraphEditorButtonOpensAndClosesTheBand() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let button = app.buttons["timeline.graphEditorButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "The keyframe button became the graph editor toggle — §11.3, ask 3's tail")

        let band = app.otherElements["timeline.graphBand"]
        XCTAssertFalse(band.exists, "Closed until it is asked for")

        button.tap()
        XCTAssertTrue(band.waitForExistence(timeout: 5),
                      "A tap opens the band under the selected layer")
        XCTAssertEqual(band.value as? String, "empty",
                       "A band on a layer that animates nothing says so rather than coming up blank")

        button.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: band)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed,
                       "The same button closes it — it is a toggle, not a one-way door")
    }

    /// **The band grows the row it opens under, and the pinned name column takes the same growth.**
    ///
    /// This is the failure `TimelineRowLayout` exists to make impossible and the one thing about it
    /// no logic test can see: the two columns are laid out by two different files, one SwiftUI and
    /// one UIKit, and a band only one of them knows about shifts every track down while the names
    /// stay put — so a name labels the layer above the one it belongs to.
    ///
    /// **It also pins the trap that comes with routing the band through the row's height**: the name
    /// cell grows too, and a name left centred in the taller cell floats down beside the middle of
    /// the curves instead of labelling the cel blocks it is the name of. Both halves are one
    /// measurement — a name and its track still sharing a horizontal band of screen — taken on the
    /// expanded row and on the row below it.
    func testOpeningTheBandKeepsEveryNameLinedUpWithItsTrack() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // A second layer, so there is a row *below* the expanded one to be pushed down. It lands on
        // top of the stack and selected, so the band opens on row 0 and layer 0 is the row beneath.
        addVectorLayer(app)

        let openName = app.staticTexts["timeline.layerName.1"]
        let openTrack = app.otherElements["timeline.cel.1.0"]
        let lowerName = app.staticTexts["timeline.layerName.0"]
        let lowerTrack = app.otherElements["timeline.cel.0.0"]
        for element in [openName, openTrack, lowerName, lowerTrack] {
            XCTAssertTrue(element.waitForExistence(timeout: 5))
        }

        func agree(_ name: XCUIElement, _ track: XCUIElement) -> Bool {
            abs(name.frame.midY - track.frame.midY) < 12
        }
        XCTAssertTrue(agree(openName, openTrack), "Fixture: the two columns start in register")
        XCTAssertTrue(agree(lowerName, lowerTrack))
        let before = lowerTrack.frame.midY

        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(app.otherElements["timeline.graphBand"].waitForExistence(timeout: 5))

        XCTAssertGreaterThan(lowerTrack.frame.midY, before + 40,
                             "The band opened on the top layer, so the row under it moved down")
        XCTAssertTrue(agree(lowerName, lowerTrack),
                      "…and its name moved with it — both columns lay out from one TimelineRowLayout")
        XCTAssertTrue(agree(openName, openTrack),
                      "The expanded row's name stays on its blocks rather than sliding down the band")
    }
}
