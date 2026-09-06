import SwiftUI
import XCTest

/// **The two rules the bottom dock's geometry is** — TODO item (49). `OptionsPanelUITests` is what
/// says the panels on screen obey them; this is what says the rules are rules.
///
/// **Every assertion here is a relationship, never a constant.** `bottomInset(clearing: 250) == 258`
/// would pass against any implementation that happened to add the same number I just typed and is
/// exactly the vacuous pin CLAUDE.md's "a green assertion is only as good as its two operands"
/// section is about. What is asserted instead is that the dock moves **one-for-one** with the
/// timeline, that it is always strictly above it, and that the width gives its margins back before
/// it gives up any width and then stops.
final class BottomDockLogicTests: XCTestCase {

    // MARK: - Riding the timeline

    /// The whole of the owner's second half: *"make it move with the timeline expansion … the menu
    /// should follow it up to always be on top of the timeline."* One-for-one, at every height —
    /// which is false for the 100pt constant this replaced, false for any fraction of the height,
    /// and false for a clamp.
    func testTheDockMovesOneForOneWithTheTimeline() {
        for (low, high) in [(48.0, 130.0), (130.0, 250.0), (250.0, 700.0), (0.0, 1.0)] {
            let rise = BottomDock.bottomInset(clearing: high) - BottomDock.bottomInset(clearing: low)
            XCTAssertEqual(rise, high - low, accuracy: 1e-9,
                           "a timeline that grew by \(high - low) moved the dock by \(rise)")
        }
    }

    /// Strictly above, not merely level: the dock's own bottom edge has to clear the timeline's top
    /// edge or the two are drawn on the same line.
    func testTheDockClearsTheTimelineAtEveryHeight() {
        for height in [0.0, 48.0, 130.0, 250.0, 512.0, 1024.0] {
            XCTAssertGreaterThan(BottomDock.bottomInset(clearing: height), height,
                                 "the dock is inside the timeline at height \(height)")
        }
    }

    /// The default document's numbers, as the one worked example — and stated as the defect it
    /// fixes rather than as an expected value. The dock used to sit at a hard 100 against a
    /// timeline 250 tall, i.e. 150 points *under* it.
    func testTheDefaultTimelineNoLongerSwallowsTheDock() {
        let collapsed = BottomDock.bottomInset(clearing: 48)
        let resting = BottomDock.bottomInset(clearing: 250)
        XCTAssertLessThan(collapsed, 100, "a collapsed timeline should let the dock sit lower than the old constant")
        XCTAssertGreaterThan(resting, 100, "a resting timeline used to be 150 points taller than the dock's inset")
    }

    /// A timeline reporting nothing yet — the first frame, before any layout pass — must not push
    /// the dock off the bottom of the screen.
    func testAnUnmeasuredTimelineStillLeavesTheGap() {
        XCTAssertEqual(BottomDock.bottomInset(clearing: 0), BottomDock.timelineGap, accuracy: 1e-9)
        XCTAssertEqual(BottomDock.bottomInset(clearing: -40), BottomDock.timelineGap, accuracy: 1e-9,
                       "a negative report is a measurement bug, not an instruction to overhang")
    }

    // MARK: - The width

    /// Never wider than the room it is given, never narrower than a panel can lay out in, and never
    /// wider than it wants to be. The three together are the function; each alone is satisfied by a
    /// constant.
    func testTheWidthStaysInsideItsThreeBounds() {
        for available in stride(from: 320.0, through: 1600.0, by: 20.0) {
            let width = BottomDock.width(in: available)
            XCTAssertGreaterThanOrEqual(width, BottomDock.minimumWidth, "at \(available)")
            XCTAssertLessThanOrEqual(width, BottomDock.preferredWidth, "at \(available)")
            if width > BottomDock.minimumWidth {
                XCTAssertLessThanOrEqual(width + 2 * BottomDock.sideMargin, available,
                                         "the card and its margins overflow the canvas at \(available)")
            }
        }
    }

    /// It gives the margins back before it gives up any width, and only then starts shrinking —
    /// which is what makes the middle regime a regime rather than a cliff between two constants.
    func testTheWidthNeverShrinksAsTheRoomGrows() {
        var previous = BottomDock.width(in: 300)
        for available in stride(from: 300.0, through: 1600.0, by: 10.0) {
            let width = BottomDock.width(in: available)
            XCTAssertGreaterThanOrEqual(width, previous, "the card got narrower going from \(available - 10) to \(available)")
            previous = width
        }
    }

    /// Both ends of the middle regime, so the assertion above cannot be satisfied by a function that
    /// is flat everywhere: below the knee the width tracks the room, above it the width is the
    /// preference.
    func testTheWidthTracksTheRoomBelowTheKneeAndStopsAboveIt() {
        let knee = BottomDock.preferredWidth + 2 * BottomDock.sideMargin
        XCTAssertEqual(BottomDock.width(in: knee), BottomDock.preferredWidth, accuracy: 1e-9)
        XCTAssertEqual(BottomDock.width(in: knee + 400), BottomDock.preferredWidth, accuracy: 1e-9)
        let cramped = knee - 200
        XCTAssertEqual(BottomDock.width(in: cramped), cramped - 2 * BottomDock.sideMargin, accuracy: 1e-9)
        XCTAssertLessThan(BottomDock.width(in: cramped), BottomDock.preferredWidth)
    }

    /// The floor is a floor: below it the card stops shrinking and overhangs its margins rather than
    /// clipping its own controls.
    func testTheWidthStopsAtTheFloor() {
        let floorRoom = BottomDock.minimumWidth + 2 * BottomDock.sideMargin
        XCTAssertEqual(BottomDock.width(in: floorRoom), BottomDock.minimumWidth, accuracy: 1e-9)
        XCTAssertEqual(BottomDock.width(in: floorRoom - 300), BottomDock.minimumWidth, accuracy: 1e-9)
    }

    /// **The flatness cost the sliders nothing** — the claim `BottomDock.inlineSliderTravel` and
    /// `EffectSettingsBar.sliderRow` both make, and the reason `preferredWidth` is 760 rather than
    /// something rounder.
    ///
    /// The 532 is not a restatement of anything under test: it is what the **two-line** row gave at
    /// the bar's old 560 width, a fact about the layout that was replaced. Widen the label column or
    /// narrow the card and this reds, which is the whole point of it.
    func testFoldingTheSliderRowOntoOneLineCostItNoTravel() {
        XCTAssertGreaterThanOrEqual(BottomDock.inlineSliderTravel, 532,
                                    String(format: "a one-line row leaves %.0f points of travel where "
                                           + "the two-line row at 560 wide left 532",
                                           BottomDock.inlineSliderTravel))
    }

    /// And the travel is a real division of the card, not a number that happens to be large: the two
    /// columns and the padding either side account for the rest of it exactly.
    func testTheSliderRowsColumnsAccountForTheWholeCard() {
        let parts = BottomDock.inlineSliderTravel
            + BottomDock.sliderLabelWidth + BottomDock.sliderReadoutWidth
            + 2 * BottomDock.rowSpacing + 2 * BottomDock.rowHorizontalPadding
        XCTAssertEqual(parts, BottomDock.preferredWidth, accuracy: 1e-9)
    }

    // MARK: - The preference that carries the anchor

    /// `reduce` takes the **largest** report, not the last. Both the interpolate strip and the panel
    /// sit inside the measured subtree in interpolate mode, and a `reduce` that overwrote would hand
    /// the dock whichever of them SwiftUI happened to visit last.
    func testTheTimelineHeightPreferenceKeepsTheLargestReport() {
        var value = TimelineOccupiedHeightKey.defaultValue
        TimelineOccupiedHeightKey.reduce(value: &value) { 250 }
        TimelineOccupiedHeightKey.reduce(value: &value) { 44 }
        XCTAssertEqual(value, 250, accuracy: 1e-9)
        TimelineOccupiedHeightKey.reduce(value: &value) { 700 }
        XCTAssertEqual(value, 700, accuracy: 1e-9)
    }

    func testAnUnreportedTimelineIsZeroRatherThanSomeGuess() {
        XCTAssertEqual(TimelineOccupiedHeightKey.defaultValue, 0, accuracy: 1e-9)
    }
}
