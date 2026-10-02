import XCTest
import CoreGraphics

/// **The canvas pans itself to keep the text box being typed in view, and back** — the owner,
/// 2026-10-02. `ViewportFollow` is the rule and the session's bookkeeping, with no view and no clock;
/// `EditorKeyboardLayoutUITests` drives the same thing on the real canvas, from a fresh document, with
/// the real keyboard.
final class ViewportFollowLogicTests: XCTestCase {

    /// The part of the host above the strip the timeline and the panel cover: 1000 wide, 600 tall.
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 600)
    private let margin = ViewportFollow.margin

    private func box(top: CGFloat, height: CGFloat = 80) -> CGRect {
        CGRect(x: 300, y: top, width: 200, height: height)
    }

    // MARK: - The pan

    func testABoxThatIsInViewAsksForNoPan() {
        XCTAssertEqual(ViewportFollow.pan(toKeep: box(top: 200), within: visible), 0)
        XCTAssertEqual(ViewportFollow.pan(toKeep: box(top: margin), within: visible), 0, "touching the margin is in view")
        XCTAssertEqual(ViewportFollow.pan(toKeep: box(top: 600 - margin - 80), within: visible), 0)
    }

    /// A box under the strip is lifted by exactly what hides it and the margin — the least pan that
    /// shows it — and one above the top is brought down the same way.
    func testABoxUnderTheStripIsLiftedByTheLeastPanThatShowsIt() {
        XCTAssertEqual(ViewportFollow.pan(toKeep: box(top: 560), within: visible), 600 - margin - 640, accuracy: 1e-9)
        let lifted = box(top: 560).offsetBy(dx: 0, dy: ViewportFollow.pan(toKeep: box(top: 560), within: visible))
        XCTAssertEqual(lifted.maxY, visible.maxY - margin, accuracy: 1e-9, "its bottom stands the margin above the strip")
        XCTAssertEqual(ViewportFollow.pan(toKeep: box(top: -40), within: visible), margin + 40, accuracy: 1e-9)
    }

    /// **A box taller than the room keeps its top in view**, which is where the words start, rather than
    /// being chased down by its own bottom.
    func testABoxTallerThanTheRoomKeepsItsTop() {
        let tall = box(top: 300, height: 700)
        let moved = tall.offsetBy(dx: 0, dy: ViewportFollow.pan(toKeep: tall, within: visible))
        XCTAssertEqual(moved.minY, visible.minY + margin, accuracy: 1e-9)
    }

    /// The rule is vertical only: nothing about a strip across the bottom hides a box sideways.
    func testTheRuleReadsOnlyTheVerticalAxis() {
        let far = CGRect(x: 2000, y: 100, width: 200, height: 80)
        XCTAssertEqual(ViewportFollow.pan(toKeep: far, within: visible), 0)
    }

    // MARK: - The session

    /// **A session the artist never navigates ends with the canvas exactly where it began**, however many
    /// times the box grew and the strip moved along the way: what was added is what is given back.
    func testASessionGivesBackExactlyWhatItAdded() {
        var follow = ViewportFollow()
        var total: CGFloat = 0
        total += follow.follow(box: box(top: 560), within: visible)
        XCTAssertLessThan(total, 0, "the box was lifted")
        total += follow.follow(box: box(top: 560).offsetBy(dx: 0, dy: total), within: visible)
        XCTAssertEqual(follow.added, total, accuracy: 1e-9, "asking again for a box that is in view added nothing")
        // The keyboard rises and takes 200 off the room: the same box is lost again, lifted again.
        let compressed = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let more = follow.follow(box: box(top: 560).offsetBy(dx: 0, dy: total), within: compressed)
        XCTAssertLessThan(more, 0)
        total += more
        XCTAssertEqual(follow.end(), -total, accuracy: 1e-9, "the end gives all of it back")
        XCTAssertEqual(follow.end(), 0, "and a session that is over gives back nothing twice")
        XCTAssertEqual(follow.added, 0)
    }

    /// **A pan the artist makes while typing is theirs**: the follow stops moving the canvas, and gives
    /// nothing back at the end — "back" would undo what they did on purpose.
    func testAPanByTheArtistEndsTheFollowAndTheGivingBack() {
        var follow = ViewportFollow()
        XCTAssertLessThan(follow.follow(box: box(top: 560), within: visible), 0)
        follow.artistNavigated()
        XCTAssertEqual(follow.follow(box: box(top: 900), within: visible), 0, "the canvas is theirs now")
        XCTAssertEqual(follow.end(), 0, "and the session leaves it where they put it")
    }

    /// The artist's pan *before* the follow has moved anything still counts: a session that begins with
    /// the artist already navigating is theirs from the first answer.
    func testAnArtistWhoNavigatesBeforeTheFirstPanIsNeverFollowedAgainstTheirWill() {
        var follow = ViewportFollow()
        XCTAssertEqual(follow.follow(box: box(top: 200), within: visible), 0, "in view: nothing added")
        follow.artistNavigated()
        XCTAssertEqual(follow.follow(box: box(top: 700), within: visible), 0)
    }

    /// A navigation with no session up is not a yield: it must not leak into the next one.
    func testNavigatingBetweenSessionsDoesNotYieldTheNextOne() {
        var follow = ViewportFollow()
        follow.artistNavigated()
        XCTAssertLessThan(follow.follow(box: box(top: 560), within: visible), 0, "the new session follows")
        XCTAssertGreaterThan(follow.end(), 0)
    }

    func testEndingWithNoSessionAnswersNothing() {
        var follow = ViewportFollow()
        XCTAssertEqual(follow.end(), 0)
    }
}
