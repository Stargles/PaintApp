import XCTest

/// **The rules the timeline panel's size is** — TODO (169). `TimelineRulerUITests` is what says the
/// panel on screen follows them; this says they are rules.
///
/// Relationships, not constants, wherever a constant would only repeat the one under test: the default
/// is a share of the window until it reaches its ceiling, it is never unusable and never taller than a
/// drag may take it, and it never shrinks as the window grows.
final class TimelinePanelSizeLogicTests: XCTestCase {

    /// The owner's iPad in landscape (790 pt of editor under a 20 pt inset) against a fixed 375 pt: the
    /// whole point of the item is that a short window gets *less* than the ceiling.
    func testAShortWindowOpensBelowTheCeilingAtItsShare() {
        for available in [600.0, 700.0, 790.0, 834.0] {
            let height = TimelinePanelSize.defaultHeight(in: available)
            XCTAssertEqual(height, available * TimelinePanelSize.defaultShare, accuracy: 1e-9, "at \(available)")
            XCTAssertLessThan(height, TimelinePanelSize.openingCeiling, "at \(available)")
        }
    }

    /// A window with room to spare is not given more — the 13-inch iPad in portrait stays where it was.
    func testATallWindowStopsAtTheCeiling() {
        for available in [1100.0, 1356.0, 2000.0] {
            XCTAssertEqual(TimelinePanelSize.defaultHeight(in: available), TimelinePanelSize.openingCeiling,
                           "at \(available)")
        }
    }

    /// The default grows with the window and then holds: a taller window never opens a *shorter* panel.
    func testTheDefaultNeverShrinksAsTheWindowGrows() {
        var previous = TimelinePanelSize.defaultHeight(in: 0)
        for available in stride(from: 0.0, through: 2000.0, by: 10.0) {
            let height = TimelinePanelSize.defaultHeight(in: available)
            XCTAssertGreaterThanOrEqual(height, previous, "went from \(previous) to \(height) at \(available)")
            previous = height
        }
    }

    /// Whatever the window, a panel that opens is usable and is not past the point a drag may take it
    /// to — so `AnimationTimeline` never has to clamp a default.
    func testTheDefaultIsAlwaysUsableAndAlwaysDraggable() {
        for available in stride(from: 0.0, through: 2000.0, by: 7.0) {
            let height = TimelinePanelSize.defaultHeight(in: available)
            XCTAssertGreaterThanOrEqual(height, TimelinePanelSize.minExpandedHeight, "at \(available)")
            XCTAssertLessThanOrEqual(height, TimelinePanelSize.maxHeight(in: available), "at \(available)")
        }
    }

    /// The drag's ceiling leaves the top toolbar room, and a window too short for that still keeps a
    /// usable panel rather than a negative one.
    func testTheDragCeilingLeavesRoomAboveAndNeverGoesUnusable() {
        XCTAssertEqual(TimelinePanelSize.maxHeight(in: 790), 790 - 64)
        XCTAssertEqual(TimelinePanelSize.maxHeight(in: 100), TimelinePanelSize.minExpandedHeight)
    }
}
