import XCTest

/// **The half of stage 3a that only a real device run can answer: the gesture.**
///
/// `KeyframeControlLogicTests` pins every decision this stage makes that is a function of values —
/// what a tap keys, what a slider edit writes, when the button dims. None of that proves an 0.8 s hold
/// *works*, and none of it can: `Views/AnimationTimeline.swift` and `Views/KeyframeButton.swift` are
/// not compiled into this target at all, so a headless test cannot see the recognizers, the button, or
/// the resize drag they sit inside. This file is small on purpose — three tests over one control — and
/// it exists for exactly the three claims that need a finger.
///
/// **Its own class**, per CLAUDE.md's cost model: `xcodebuild` distributes parallel work per test
/// *class*, so a short class starts immediately rather than queueing behind a long one.
final class AnimateModeUITests: PaintUITestCase {

    /// `KeyframeButtonView` is a `UIView` carrying `.button` traits rather than a `UIButton`, and
    /// XCUITest's element-type mapping for that is not something to bet a suite on — matched by
    /// identifier across every type instead.
    private func keyframeButton(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "timeline.keyframeButton").firstMatch
    }

    /// Comfortably past `KeyframeControl.holdDuration`, and derived from it rather than typed, so
    /// changing the ruling's 0.8 cannot leave this test pressing for too little.
    private var holdPress: TimeInterval { KeyframeControl.holdDuration + 0.4 }

    /// **The ruling, end to end**: hold enters, hold again leaves, and the mode is loud while it is on.
    ///
    /// `animate.summary` and `animate.exit` are `AnimateBar`, which is the discoverability half of
    /// §2.1 — the one previous tap-versus-hold split in this app was reverted by the owner as
    /// undiscoverable, so the strip being on screen is part of the feature rather than decoration.
    func testHoldingTheKeyframeButtonEntersAndLeavesAnimateMode() {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let button = keyframeButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The keyframe button is in the timeline strip")
        XCTAssertEqual(button.value as? String, "off|0",
                       "A fresh document animates nothing, so the tap is refused and the button is dimmed")

        button.press(forDuration: holdPress)
        XCTAssertTrue(app.buttons["animate.exit"].waitForExistence(timeout: 5),
                      "0.8 s enters Animate mode and the strip says so")
        XCTAssertTrue(app.staticTexts["animate.summary"].exists)
        XCTAssertEqual(button.value as? String, "on|0")

        button.press(forDuration: holdPress)
        XCTAssertFalse(app.buttons["animate.exit"].waitForExistence(timeout: 2),
                       "Holding again leaves the mode — the button is a toggle, not a one-way door")
        XCTAssertEqual(button.value as? String, "off|0")
    }

    /// **The other half of §2.1's split, and the one a naive implementation gets wrong.** Stacking a
    /// tap and a long press on one control without arbitrating them lets both fire on a slow tap;
    /// `KeyframeButtonView` makes the tap `require(toFail:)` the hold, so a tap can never toggle the
    /// mode. The tap on a fresh document also has nothing to key, so this doubles as the pin that a
    /// refused tap changes nothing at all.
    func testTappingTheKeyframeButtonDoesNotEnterAnimateMode() {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let button = keyframeButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        XCTAssertFalse(app.buttons["animate.exit"].waitForExistence(timeout: 2),
                       "A tap inserts a key; it does not toggle the mode")
        XCTAssertEqual(button.value as? String, "off|0")
    }

    /// **The hold must not also resize the timeline**, which is the hazard `KeyframeControl`'s two
    /// distance constants exist to remove: the whole top bar carries
    /// `simultaneousGesture(resizeGesture)`, so a press that drifts is a panel drag as well as a hold.
    ///
    /// Measured across an enter *and* a leave, so the mode is back where it started and a moved play
    /// button can only mean the panel changed height. `timeline.collapseButton` exists solely in the
    /// expanded mini toolbar, so its survival is the second, coarser half of the same claim: a resize
    /// large enough to collapse the panel would take it away.
    func testHoldingTheKeyframeButtonDoesNotResizeTheTimeline() {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let play = app.buttons["timeline.playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        let before = play.frame

        let button = keyframeButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.press(forDuration: holdPress)
        XCTAssertTrue(app.buttons["animate.exit"].waitForExistence(timeout: 5), "Premise: the hold landed")
        button.press(forDuration: holdPress)
        XCTAssertFalse(app.buttons["animate.exit"].waitForExistence(timeout: 2), "Premise: and it landed again")

        XCTAssertTrue(app.buttons["timeline.collapseButton"].exists,
                      "The timeline is still expanded — a resize did not ride the hold")
        XCTAssertEqual(play.frame.origin.y, before.origin.y, accuracy: 1,
                       "…and it is still exactly as tall")
    }
}
