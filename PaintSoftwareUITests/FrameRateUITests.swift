import XCTest

/// The frame-rate control, driven — KEYFRAMES.md §2.7, stage 7.
///
/// **This class exists because the model being right is not the bar.** Three features shipped to the
/// owner's iPad in one pass that could not be used at all, every one with a green fast tier and every
/// assertion in the suite on a *stored value*. `FrameRateLogicTests` is that half and it is complete;
/// what it cannot see is whether an artist can reach the control at all, and one of those three
/// features had an entry point that required state only that entry point could create.
///
/// So each test here starts from a **cold launch into a new document** and touches nothing the artist
/// could not touch. Three tests, kept few on purpose: what the control *decides* is headless and in
/// two seconds, and a class that drove twenty-three taps down to the floor would pay minutes to pin
/// arithmetic the fast tier already holds.
final class FrameRateUITests: PaintUITestCase {

    /// **Cold-start reachability, and §2.22's both-bars rule in the same test.**
    ///
    /// The rate readout lived in `miniToolbar` alone until stage 7 — so an artist who dragged the
    /// timeline shut could not see the document's frame rate, let alone change it. That is precisely
    /// the asymmetry §2.22 warns of (*"a button added to one is invisible in the other"*), and the
    /// only way to observe it is to collapse the bar and look.
    func testTheFrameRateControlIsReachableFromAColdStartInBothTimelineStates() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Setup: a brand-new document, no prior state")

        let button = app.buttons["timeline.frameRateButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "A new document shows its frame rate in the expanded bar")
        XCTAssertEqual(button.label, "24 fps", "…and a new document starts at 24")

        let collapse = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        collapse.tap()

        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "…and it is still there once the timeline is collapsed (§2.22)")
    }

    /// **The whole loop, from a cold start: open the panel, change the rate, watch the bar change.**
    ///
    /// The last assertion is the one that matters and it is deliberately on the *bar*, not on the
    /// panel: a keyframes feature already shipped here where a drag wrote the right number and
    /// nothing moved, because every assertion in the suite was on the value and the value was never
    /// wrong. This one fails if the readout stops following the model while the model stays correct.
    func testChangingTheRateFromThePanelChangesWhatTheTimelineShows() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let button = app.buttons["timeline.frameRateButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.label, "24 fps", "Setup: the rate before the artist touches anything")

        button.tap()

        let readout = app.descendants(matching: .any)["frameRate.value"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5), "The tap opens the frame-rate panel")
        XCTAssertEqual(readout.value as? String, "24")

        let minus = app.buttons["frameRate.decrement"]
        XCTAssertTrue(minus.waitForExistence(timeout: 3))
        minus.tap()
        XCTAssertEqual(readout.value as? String, "23", "The stepper moves the rate")

        // §2.7 is about taking the document *below* 24, so the preset that does it in one tap is
        // what an artist reaches for. 12 is twos.
        let twelve = app.buttons["frameRate.preset.12"]
        XCTAssertTrue(twelve.waitForExistence(timeout: 3), "The presets are on the panel")
        twelve.tap()
        XCTAssertEqual(readout.value as? String, "12")

        // Close the panel by tapping its own button again, then read the bar — which is the artist's
        // own view of the document's rate and the operand this test exists for.
        button.tap()
        XCTAssertTrue(app.buttons["timeline.frameRateButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["timeline.frameRateButton"].label, "12 fps",
                       "The timeline reads back the rate the artist set — not the 24 it was built with")
    }

    /// **The refusal is visible before it is made.**
    ///
    /// `stepFPS` refuses at the ends, but a refusal an artist only discovers by pressing a live-looking
    /// button is this repo's own filed defect (a `Bool` returned and discarded; a refusal with no
    /// notice). The arrow greys out, and this is the assertion that fails if it stops.
    ///
    /// Driven at the **ceiling** rather than the floor because 60 is one preset tap away and 1 is
    /// twenty-three stepper taps: same rule, same code path, one second instead of thirty.
    ///
    /// **`isEnabled` is exposed, not drawn, and that gap is not hypothetical here.** This test was
    /// green on the first build against a panel where the disabled plus was still painted full blue:
    /// a `.foregroundColor(.blue)` on the enclosing `HStack` beat the control's own dimming, so
    /// XCUITest saw a disabled button and the artist saw a live one. The tint is per-arrow now and
    /// comes from the same `canIncreaseFPS` that disables it. Nothing XCUITest can read is a colour,
    /// so the greying itself was confirmed by driving the panel and looking at the screenshot; what
    /// this test holds is the half a machine can check.
    func testTheFrameRatePanelRefusesVisiblyAtTheEndOfItsRange() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let button = app.buttons["timeline.frameRateButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let plus = app.buttons["frameRate.increment"]
        let minus = app.buttons["frameRate.decrement"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        XCTAssertTrue(plus.isEnabled, "Setup: at 24 there is room in both directions")
        XCTAssertTrue(minus.isEnabled)

        let sixty = app.buttons["frameRate.preset.60"]
        XCTAssertTrue(sixty.waitForExistence(timeout: 3))
        sixty.tap()

        XCTAssertEqual(app.descendants(matching: .any)["frameRate.value"].value as? String, "60")
        XCTAssertFalse(plus.isEnabled, "At the top of the range the plus arrow says so by greying out")
        XCTAssertTrue(minus.isEnabled, "…while the direction that still has room stays live")
    }
}
