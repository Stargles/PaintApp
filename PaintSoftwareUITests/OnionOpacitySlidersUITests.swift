import XCTest

/// **The onion-skin panel's opacity sliders, driven the way an artist drives them** — cold start, the
/// panel raised by holding the timeline's onion button, and every assertion on the slider values the
/// panel *exposes*. `OnionSkinLogicTests` owns the arithmetic; this is the proof that the sliders an
/// artist can touch are wired to it, and that the ones they cannot touch say so.
///
/// The drags start **on the thumb**, as `BrushSizeSliderUITests.dragVerticalSlider` explains a rotated
/// `Slider` needs; `adjust(toNormalizedSliderPosition:)` does not move one.
final class OnionOpacitySlidersUITests: PaintUITestCase {

    // MARK: - Driving the panel

    private func openOnionPanel(_ app: XCUIApplication) {
        let button = app.buttons["timeline.onionSkinToggle"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.press(forDuration: 0.6)
        XCTAssertTrue(app.segmentedControls["onionPanel.placementPicker"].waitForExistence(timeout: 5),
                      "the onion panel opens on a hold")
    }

    /// Raises both count sliders to their maximum, five skins a side, and waits for the five opacity
    /// sliders on each. `adjust(toNormalizedSliderPosition: 1)` is the one position XCUITest reaches
    /// reliably on these count sliders — MEASURED, 0.6 reads 4 and 0.54 reads 2 on a slider whose 3
    /// sits at 0.6, so a middle count cannot be asked for by position.
    private func showFiveSkins(_ app: XCUIApplication) {
        for side in ["previous", "next"] {
            let slider = app.sliders["onionPanel.\(side)CountSlider"]
            XCTAssertTrue(slider.waitForExistence(timeout: 5))
            slider.adjust(toNormalizedSliderPosition: 1)
            XCTAssertTrue(opacitySlider(app, side, 5).waitForExistence(timeout: 5), "five skins on the \(side) side")
        }
    }

    private func opacitySlider(_ app: XCUIApplication, _ side: String, _ slot: Int) -> XCUIElement {
        app.sliders["onionPanel.\(side).opacity\(slot)"]
    }

    private func percent(_ slider: XCUIElement) -> Int {
        Int((slider.value as? String)?.replacingOccurrences(of: "%", with: "") ?? "") ?? -1
    }

    /// Drags a slider's thumb from where it is to `target` (0...1), in the rotated frame: 1 is the
    /// bottom (zero) and 0 the top (full), with the thumb inset from each end by its own radius.
    private func drag(_ slider: XCUIElement, from: Double, to target: Double) {
        func dy(_ value: Double) -> CGFloat { CGFloat(1 - (0.16 + value * 0.68)) }
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy(from)))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy(target)))
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func drag(_ slider: XCUIElement, to target: Double) {
        drag(slider, from: Double(percent(slider)) / 100, to: target)
    }

    private func chain(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["onionPanel.linkOpacityToggle"]
    }

    /// The five sliders of one side, nearest first, as percentages.
    private func readings(_ app: XCUIApplication, _ side: String) -> [Int] {
        (1...5).map { percent(opacitySlider(app, side, $0)) }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The tests

    /// **TODO (138), cold start: the two opacity sliders are independent.** The owner: *"the user
    /// should be able to take the rightmost slider for example and adjust it, and the opacity of the
    /// left slider does not change. Vice versa with the left."* Driven in the state they were in — a
    /// fresh document, the shipped one skin a side with the link on — by dragging each side's thumb and
    /// reading **both** sliders' exposed values after, so it reds if either direction still moves the
    /// other.
    func testDraggingOneOnionOpacitySliderLeavesTheOtherSideWhereItWas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openOnionPanel(app)

        let previous = opacitySlider(app, "previous", 1)
        let next = opacitySlider(app, "next", 1)
        XCTAssertTrue(previous.waitForExistence(timeout: 5), "the previous side's slider is on the panel")
        XCTAssertTrue(next.waitForExistence(timeout: 5), "the next side's slider is on the panel")
        XCTAssertEqual(chain(app).value as? String, "on",
                       "PREMISE: linked, which is the state where one slider used to drag the other")

        let startPrevious = percent(previous), startNext = percent(next)
        XCTAssertEqual(startPrevious, startNext, "PREMISE: both sides open at the same level")
        XCTAssertGreaterThan(startPrevious, 0)

        // The right slider moves; the left one must not.
        drag(next, to: 0.9)
        XCTAssertGreaterThan(percent(next), startNext + 20, "PREMISE: the drag moved the right slider")
        XCTAssertEqual(percent(previous), startPrevious, "dragging the right slider moved the left one")

        // And the other way round.
        let movedNext = percent(next)
        drag(previous, to: 0.08)
        XCTAssertLessThan(percent(previous), startPrevious - 15, "PREMISE: the drag moved the left slider")
        XCTAssertEqual(percent(next), movedNext, "dragging the left slider moved the right one")
        attach(app, "onion-sliders-independent")
    }

    /// **TODO (138)'s follow-up, cold start: the chain links one side's two ends.** The owner: *"keep
    /// it, links one side. When it is on, the user can select the furthest left or right sliders per
    /// side and every slider in between will be linearly interpolated between the two."*
    ///
    /// Five skins a side from a fresh document, chain on. The two end sliders of each side are live and
    /// the three between them are dimmed; dragging an end moves all three onto the straight line, and
    /// the other side stays where it was. Then the chain is taken off — the inner sliders come alive
    /// without jumping, and one dragged alone leaves its neighbours — and put back on, which draws the
    /// line between the ends again.
    func testTheChainInterpolatesEachSidesInnerSlidersBetweenItsTwoEnds() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openOnionPanel(app)
        showFiveSkins(app)
        XCTAssertEqual(chain(app).value as? String, "on", "PREMISE: the chain is on by default")

        // The ends are live, the three between are not — on both sides.
        for side in ["previous", "next"] {
            XCTAssertTrue(opacitySlider(app, side, 1).isEnabled, "\(side): the nearest slider is free")
            XCTAssertTrue(opacitySlider(app, side, 5).isEnabled, "\(side): the furthest slider is free")
            for slot in 2...4 {
                XCTAssertFalse(opacitySlider(app, side, slot).isEnabled,
                               "\(side): slider \(slot) is read off the line, so it takes no touch")
            }
        }
        /// Every slider sits on the straight line between the two ends, to the rounding of a percentage.
        func assertOnTheLine(_ values: [Int], _ message: String, line: UInt = #line) {
            for slot in 1...3 {
                let expected = Double(values[0]) + Double(values[4] - values[0]) * Double(slot) / 4
                XCTAssertEqual(Double(values[slot]), expected, accuracy: 2,
                               "\(message): slider \(slot + 1) is on the line between the ends, got \(values)", line: line)
            }
        }
        let startPrevious = readings(app, "previous"), startNext = readings(app, "next")
        assertOnTheLine(startPrevious, "a fresh side")
        assertOnTheLine(startNext, "a fresh side")
        attach(app, "onion-chain-on-five-skins")

        // Drag the previous side's furthest end up: everything between follows, its nearest and the
        // other side do not.
        drag(opacitySlider(app, "previous", 5), to: 0.9)
        let afterPrevious = readings(app, "previous")
        XCTAssertGreaterThan(afterPrevious[4], startPrevious[4] + 40, "PREMISE: the furthest end moved up")
        XCTAssertEqual(afterPrevious[0], startPrevious[0], "the nearest end did not move")
        XCTAssertGreaterThan(afterPrevious[2], startPrevious[2] + 15, "the middle slider moved up with the end")
        assertOnTheLine(afterPrevious, "after dragging the previous side's furthest end")
        XCTAssertEqual(readings(app, "next"), startNext, "the other side did not move")

        // Drag the next side's nearest end down: everything between follows, and the previous side is
        // untouched.
        drag(opacitySlider(app, "next", 1), to: 0.05)
        let afterNext = readings(app, "next")
        XCTAssertLessThan(afterNext[0], startNext[0] - 15, "PREMISE: the nearest end moved down")
        XCTAssertEqual(afterNext[4], startNext[4], "the furthest end did not move")
        assertOnTheLine(afterNext, "after dragging the next side's nearest end")
        XCTAssertEqual(readings(app, "previous"), afterPrevious, "the other side did not move")
        attach(app, "onion-chain-on-ends-dragged")

        // Chain off: every slider is live, and none jumped.
        chain(app).tap()
        XCTAssertEqual(chain(app).value as? String, "off", "the chain toggled off")
        XCTAssertTrue(opacitySlider(app, "previous", 3).isEnabled, "unchained, the middle slider takes a touch")
        XCTAssertEqual(readings(app, "previous"), afterPrevious, "unchaining froze the line rather than resetting it")
        drag(opacitySlider(app, "previous", 3), to: 0.0)
        let alone = readings(app, "previous")
        XCTAssertLessThan(alone[2], afterPrevious[2] - 10, "PREMISE: the middle slider moved on its own")
        XCTAssertEqual(alone[0], afterPrevious[0], "…and left the nearest alone")
        XCTAssertEqual(alone[4], afterPrevious[4], "…and the furthest")
        XCTAssertEqual(alone[1], afterPrevious[1], "…and the one beside it")

        // Chain back on: the ends stay, everything between falls back onto the line.
        chain(app).tap()
        XCTAssertEqual(chain(app).value as? String, "on", "the chain toggled back on")
        let relinked = readings(app, "previous")
        XCTAssertEqual(relinked[0], alone[0], "re-chaining kept the nearest end")
        XCTAssertEqual(relinked[4], alone[4], "…and the furthest")
        assertOnTheLine(relinked, "re-chained")
        XCTAssertFalse(opacitySlider(app, "previous", 3).isEnabled, "…and the middle is dimmed again")
        attach(app, "onion-chain-relinked")
    }
}
