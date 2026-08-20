import XCTest

/// `GalleryOpenState` — the two rules a loading spinner creates, both of which fail silently.
///
/// The spinner itself is a view and is not what these test. What they pin is that a frozen-looking
/// gallery cannot be made to start two loads, and that every load ends — including the one that
/// fails. `ProjectStore.load` returns nil for a package whose manifest will not decode, and a state
/// machine that released the gallery only on success would answer a *damaged file* with a spinner
/// that never stops, which reads to the artist as the hang the spinner was added to explain.
final class GalleryOpenLogicTests: XCTestCase {

    private let first = UUID()
    private let second = UUID()

    func testAFreshGalleryIsIdleAndShowsNoSpinner() {
        let state = GalleryOpenState()
        XCTAssertFalse(state.isBusy)
        XCTAssertNil(state.openingProjectID)
        XCTAssertFalse(state.isOpening(first), "Nothing is opening, so no tile is spinning")
    }

    func testBeginningALoadClaimsTheGalleryForThatProjectAlone() {
        var state = GalleryOpenState()
        XCTAssertTrue(state.begin(first), "The first tap starts a load")
        XCTAssertTrue(state.isBusy)
        XCTAssertEqual(state.openingProjectID, first)
        XCTAssertTrue(state.isOpening(first), "The tapped tile spins…")
        XCTAssertFalse(state.isOpening(second), "…and its neighbour does not")
    }

    /// Rule 1. A stalled app invites a second tap, and two loads means two `CanvasManager`s built at
    /// once with whichever finishes last winning — a lottery between two projects rather than a slow
    /// open of one.
    func testASecondTapWhileLoadingIsRefused() {
        var state = GalleryOpenState()
        XCTAssertTrue(state.begin(first))

        XCTAssertFalse(state.begin(second), "A different project cannot start while one is loading")
        XCTAssertFalse(state.begin(first), "…and neither can a second tap on the same one")
        XCTAssertEqual(state.openingProjectID, first,
                       "The refused taps changed nothing — the first load still owns the gallery")
    }

    /// Rule 2, in the shape that matters: `finish` is not conditional on success, so the damaged-file
    /// path releases the gallery exactly as the happy path does.
    func testFinishingReleasesTheGalleryWhetherOrNotTheLoadSucceeded() {
        var state = GalleryOpenState()
        XCTAssertTrue(state.begin(first))
        state.finish()

        XCTAssertFalse(state.isBusy, "A load that returned nil must still hand the gallery back")
        XCTAssertNil(state.openingProjectID)
        XCTAssertFalse(state.isOpening(first))
        XCTAssertTrue(state.begin(second), "…and the next tap works, on any project")
    }

    func testFinishingTwiceIsHarmless() {
        var state = GalleryOpenState()
        XCTAssertTrue(state.begin(first))
        state.finish()
        state.finish()
        XCTAssertFalse(state.isBusy)
    }

    /// The whole journey, in the order `GalleryView.open` runs it, twice — because the defect a
    /// stateless guard would have is not visible in one pass.
    func testTwoConsecutiveOpensEachRunOnce() {
        var state = GalleryOpenState()
        var loadsStarted = 0

        for project in [first, second, first] {
            // Two taps per project, which is what a frozen screen actually gets.
            for _ in 0..<2 where state.begin(project) {
                loadsStarted += 1
            }
            state.finish()
        }
        XCTAssertEqual(loadsStarted, 3, "Three projects tapped twice each is three loads, not six")
    }
}
