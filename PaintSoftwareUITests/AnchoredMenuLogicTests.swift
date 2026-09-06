import XCTest
import CoreGraphics

/// The arithmetic and the rule behind TODO (39)'s anchored menus, pinned without a simulator.
///
/// **Why these are worth having rather than leaning on the UI test.** `MenuInterruptionUITests`
/// proves the one case an artist meets — a menu above a control near the bottom of the screen, and a
/// drag that goes through. Every *other* branch below needs a contrived layout to reach at all: a
/// menu with no room above it, one wider than the screen, one taller than the screen. A device test
/// for those would be a fixture built to force a branch, which is the shape this repo has repeatedly
/// found measuring nothing. These are the same branches at their own level, where the operands are
/// two numbers and neither of them can be secretly equal.
final class AnchoredMenuLogicTests: XCTestCase {

    /// An iPad Pro 13" in portrait, which is where every one of these menus is used.
    private let screen = CGRect(x: 0, y: 0, width: 1032, height: 1376)

    // MARK: - Placement: the ordinary case

    /// The case every one of the four menus actually hits: a control in the timeline's mini toolbar
    /// near the bottom of the screen, with the whole canvas free above it.
    func testAMenuWithRoomAboveSitsAboveItsAnchorSeparatedByTheGap() {
        let anchor = CGRect(x: 88, y: 1126, width: 24, height: 24)
        let frame = AnchoredMenuPlacement.frame(anchor: anchor,
                                                menuSize: CGSize(width: 380, height: 640),
                                                bounds: screen)

        XCTAssertEqual(frame.maxY, anchor.minY - AnchoredMenuPlacement.gap, accuracy: 0.001, """
            A menu with room above it must sit above its anchor, its bottom edge one `gap` clear of \
            the anchor's top. This is the placement every timeline menu gets.
            """)
        XCTAssertEqual(frame.minY, 480, accuracy: 0.001,
                       "1126 - 6 - 640 = 480, stated as a number so a changed gap is visible here")
    }

    func testAMenuIsCentredOnItsAnchorWhenThereIsRoomEitherSide() {
        let anchor = CGRect(x: 480, y: 1126, width: 40, height: 24)
        let frame = AnchoredMenuPlacement.frame(anchor: anchor,
                                                menuSize: CGSize(width: 200, height: 100),
                                                bounds: screen)

        XCTAssertEqual(frame.midX, anchor.midX, accuracy: 0.001,
                       "with room on both sides the menu is centred on what it belongs to")
        XCTAssertEqual(frame.minX, 400, accuracy: 0.001, "500 - 200/2")
    }

    // MARK: - Placement: the edges

    /// The onion-skin button is the leftmost control in the mini toolbar and its panel is 380 wide,
    /// so this is not a hypothetical: centring it would put roughly half the panel off-screen.
    func testAMenuOverhangingTheLeadingEdgeIsClampedToTheMargin() {
        let anchor = CGRect(x: 88, y: 1126, width: 24, height: 24)
        let frame = AnchoredMenuPlacement.frame(anchor: anchor,
                                                menuSize: CGSize(width: 380, height: 200),
                                                bounds: screen)

        XCTAssertEqual(frame.minX, AnchoredMenuPlacement.margin, accuracy: 0.001, """
            Centred on x=100 a 380-wide menu starts at -90. It has to be clamped to the margin \
            instead, or the artist reads a panel with its left third off the screen.
            """)
    }

    func testAMenuOverhangingTheTrailingEdgeIsClampedInside() {
        let anchor = CGRect(x: 1000, y: 1126, width: 24, height: 24)
        let frame = AnchoredMenuPlacement.frame(anchor: anchor,
                                                menuSize: CGSize(width: 380, height: 200),
                                                bounds: screen)

        XCTAssertEqual(frame.maxX, screen.maxX - AnchoredMenuPlacement.margin, accuracy: 0.001,
                       "the far edge is clamped the same way the near one is")
        XCTAssertLessThan(frame.minX, anchor.midX,
                          "and it is the menu that moved, not the anchor")
    }

    /// **The clamp order, which is a decision and not an accident.** A menu wider than the screen
    /// cannot be placed satisfyingly; the question is which edge is sacrificed. Applying the
    /// trailing clamp last would leave the *leading* edge off-screen — the edge every one of these
    /// menus reads from, since their labels and icons are leading-aligned.
    func testAMenuWiderThanTheScreenKeepsItsLeadingEdgeVisible() {
        let anchor = CGRect(x: 500, y: 1126, width: 24, height: 24)
        let frame = AnchoredMenuPlacement.frame(anchor: anchor,
                                                menuSize: CGSize(width: 1200, height: 200),
                                                bounds: screen)

        XCTAssertEqual(frame.minX, AnchoredMenuPlacement.margin, accuracy: 0.001, """
            A menu too wide to fit must start at the leading margin and overflow to the trailing \
            side. Clamping in the other order puts its first column off-screen, which is the half \
            an artist actually reads.
            """)
    }

    /// Nothing in the timeline hits this today — the panel is at the bottom of the screen — but the
    /// branch exists so that a menu anchored high (a future toolbar, a rotated layout) does not
    /// simply vanish upward.
    func testAMenuWithNoRoomAboveItGoesBelowItsAnchor() {
        let anchor = CGRect(x: 480, y: 12, width: 40, height: 28)
        let frame = AnchoredMenuPlacement.frame(anchor: anchor,
                                                menuSize: CGSize(width: 200, height: 300),
                                                bounds: screen)

        XCTAssertEqual(frame.minY, anchor.maxY + AnchoredMenuPlacement.gap, accuracy: 0.001, """
            With no room above, the menu goes below by the same gap rather than being clamped \
            against the top of the screen on top of its own anchor.
            """)
        XCTAssertGreaterThan(frame.minY, anchor.maxY, "and it is genuinely below, not overlapping")
    }

    /// A menu taller than the space it has — the onion-skin panel is 640 points tall, so a timeline
    /// dragged up to most of the screen reaches this.
    func testAMenuThatFitsNeitherSideKeepsItsTopOnScreen() {
        let shortScreen = CGRect(x: 0, y: 0, width: 1032, height: 300)
        let anchor = CGRect(x: 480, y: 140, width: 40, height: 20)
        let frame = AnchoredMenuPlacement.frame(anchor: anchor,
                                                menuSize: CGSize(width: 200, height: 400),
                                                bounds: shortScreen)

        XCTAssertEqual(frame.minY, AnchoredMenuPlacement.margin, accuracy: 0.001, """
            A menu too tall for either side must keep its **top** on screen and run off the bottom. \
            Its first rows are the ones the artist needs; a menu clamped the other way shows its \
            footer and hides its title.
            """)
    }

    // MARK: - Dismissal

    private let menu = CGRect(x: 100, y: 400, width: 300, height: 200)

    func testATouchOutsideTheMenuDismissesIt() {
        XCTAssertTrue(AnchoredMenuDismissal.shouldDismiss(touchAt: CGPoint(x: 700, y: 900),
                                                          menuFrame: menu,
                                                          toggleControlFrame: nil), """
            THE FIX (TODO (39)): a touch that lands away from the menu closes it. Under `.popover` \
            this decision belonged to a screen-covering gate that also swallowed the gesture.
            """)
    }

    func testATouchInsideTheMenuDoesNotDismissIt() {
        XCTAssertFalse(AnchoredMenuDismissal.shouldDismiss(touchAt: CGPoint(x: 250, y: 500),
                                                           menuFrame: menu,
                                                           toggleControlFrame: nil),
                       "using a control in the menu must not close the menu out from under the finger")
    }

    /// **The exemption that stops the fix eating itself.** Onion skin, interpolate and the graph
    /// channel list each hang off a button that toggles them. This rule runs on touch-*down* and the
    /// button's `toggle()` runs on touch-*up*, so without the exemption a tap on the button would
    /// close the menu here and reopen it a moment later, and the menu could never be dismissed from
    /// the control that raised it.
    func testATouchOnTheControlThatTogglesTheMenuIsLeftToThatControl() {
        let button = CGRect(x: 88, y: 1126, width: 24, height: 24)
        XCTAssertFalse(AnchoredMenuDismissal.shouldDismiss(touchAt: CGPoint(x: 100, y: 1138),
                                                           menuFrame: menu,
                                                           toggleControlFrame: button), """
            A touch on the button that owns this menu must be left alone, or the button's own \
            `toggle()` reopens what this just closed and the menu becomes impossible to shut.
            """)
    }

    /// The control for the one above: the same point, with no toggle declared, *is* a dismissal —
    /// so the assertion above is about the exemption and not about the point being somewhere
    /// harmless.
    func testTheSamePointDismissesWhenNoToggleControlIsDeclared() {
        XCTAssertTrue(AnchoredMenuDismissal.shouldDismiss(touchAt: CGPoint(x: 100, y: 1138),
                                                          menuFrame: menu,
                                                          toggleControlFrame: nil),
                      "CONTROL: without the exemption this point closes the menu like any other")
    }

    /// The cel-block menu passes no toggle control on purpose — the block it hangs off does not open
    /// or close it — so a drag that starts on the block dismisses like a drag anywhere else. This
    /// pins that a touch *outside both* is unambiguous either way.
    func testATouchOutsideBothTheMenuAndItsToggleDismissesIt() {
        let button = CGRect(x: 88, y: 1126, width: 24, height: 24)
        XCTAssertTrue(AnchoredMenuDismissal.shouldDismiss(touchAt: CGPoint(x: 700, y: 1200),
                                                          menuFrame: menu,
                                                          toggleControlFrame: button),
                      "the exemption is the toggle's own rect, not a blanket amnesty for the toolbar")
    }

    /// A menu that has appeared but not yet been measured reports an empty frame for one pass. It
    /// must not dismiss then, or the touch that is still down from opening it closes it again and
    /// the artist sees a menu that never appears.
    func testAMenuThatHasNotBeenLaidOutYetIsNotDismissed() {
        XCTAssertFalse(AnchoredMenuDismissal.shouldDismiss(touchAt: CGPoint(x: 700, y: 900),
                                                           menuFrame: .zero,
                                                           toggleControlFrame: nil),
                       "an unmeasured menu answers 'not yet', not 'anywhere is outside me'")
    }
}
