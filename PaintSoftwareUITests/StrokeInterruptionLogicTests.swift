import XCTest

/// `StrokeGiveUp` — what happens to a stroke that is not going to reach its lift, and the one question
/// the artist actually feels: **does the ink stay?** Which of the two reasons it is, is
/// `CanvasTouchCore`'s to say (`CanvasTouchCoreLogicTests`).
///
/// **This file is written to fail on omission**, the way `ToolLogicTests` is, and for the same
/// reason. The defect it guards is not a wrong branch; it is a *third* abandonment reason added
/// later that inherits "throw the ink away" because that is what the one original path did.
/// `StrokeGiveUp.inkSurvives` is an exhaustive `switch` with no `default:`, so a new case cannot
/// compile without stating an answer — and `testEveryGiveUpReasonStatesWhetherTheInkSurvives` walks
/// `allCases` against a table written here by hand, so a new case cannot be *added* without somebody
/// stating the answer twice, in two files, on purpose.
final class StrokeInterruptionLogicTests: XCTestCase {

    // MARK: - The ink rule

    /// Every reason's answer, stated once, here.
    ///
    /// Adding a case to `StrokeGiveUp` without adding it below fails the count assertion, and the
    /// message is addressed to whoever is reading it in that moment.
    private let expectedInkSurvives: [StrokeGiveUp: Bool] = [
        // A second finger landed and the canvas transform is taking the sequence. The dab or two
        // already down is an artefact of how a two-finger gesture starts, not a mark anyone drew, so
        // it rolls back with no undo step. Committing it instead would put a permanent, un-undoable
        // dot at the start of every pan begun from a stroke — the bug that put the rollback there.
        .handedOver: false,
        // The sequence simply stopped being delivered: a presentation torn down over the canvas, the
        // app backgrounded, the system taking the touch. The artist drew a line and meant it. It
        // commits, with an undo step, exactly as a lift would have committed it.
        .interrupted: true,
    ]

    func testEveryGiveUpReasonStatesWhetherTheInkSurvives() {
        XCTAssertEqual(StrokeGiveUp.allCases.count, expectedInkSurvives.count, """
            A case has been added to `StrokeGiveUp` without an entry in `expectedInkSurvives`. \
            Decide whether the ink already painted into the layer survives the new reason as a \
            committed, undoable stroke (`true`) or is rolled back with no undo step (`false`), then \
            say so in `StrokeGiveUp.inkSurvives` and in the table above. Inheriting `false` is how a \
            stroke drawn under a timeline menu came to vanish the moment the artist started the next \
            one.
            """)

        for reason in StrokeGiveUp.allCases {
            guard let expected = expectedInkSurvives[reason] else {
                XCTFail("\(reason) has no stated answer — see the message on the count assertion")
                continue
            }
            XCTAssertEqual(reason.inkSurvives, expected, "\(reason).inkSurvives must be \(expected)")
        }
    }

    /// The owner's 2026-08-18 report, named. Redundant against the sweep above by design: the sweep
    /// says the table is complete, this says what the table has to contain, so an edit that rewrites
    /// the table cannot quietly take the reported defect's fix with it.
    func testAnInterruptedStrokeKeepsItsInk() {
        XCTAssertTrue(StrokeGiveUp.interrupted.inkSurvives, """
            "The stroke goes for only a certain amount and then stops responding... when the user \
            then starts another stroke, the first stroke disappears." That is this flag being false.
            """)
    }

    /// …and the other direction, which is the assertion that stops the fix being "return true".
    /// Committing every abandonment would put an un-undoable dab at the start of every two-finger
    /// pan begun from a stroke, which is the bug the rollback path was written for in the first place.
    func testAHandedOverStrokeIsStillRolledBack() {
        XCTAssertFalse(StrokeGiveUp.handedOver.inkSurvives,
                       "A second finger means pan, not paint — the dab so far is not a mark anyone drew")
        XCTAssertTrue(StrokeGiveUp.allCases.contains { !$0.inkSurvives },
                      "At least one reason has to roll back, or the rollback path is dead code")
        XCTAssertTrue(StrokeGiveUp.allCases.contains { $0.inkSurvives },
                      "…and at least one has to commit, or nothing changed")
    }

    /// The raw values are written into `ActionRecorder` captures, so a recording from the owner's
    /// iPad can say *which* give-up ran. Pinned because renaming a case is otherwise free and would
    /// silently invalidate every capture taken before it.
    func testRawValuesAreStableBecauseRecordingsCarryThem() {
        XCTAssertEqual(StrokeGiveUp.handedOver.rawValue, "handedOver")
        XCTAssertEqual(StrokeGiveUp.interrupted.rawValue, "interrupted")
    }
}
