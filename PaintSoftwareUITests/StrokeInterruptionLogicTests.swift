import XCTest

/// `StrokeGiveUp` and `StrokeInterruption.giveUpReason` — the two halves of "this stroke is not
/// going to reach its lift", and the one question the artist actually feels: **does the ink stay?**
///
/// **This file is written to fail on omission**, the way `ToolLogicTests` is, and for the same
/// reason. The defect it guards is not a wrong branch; it is a *third* abandonment reason added
/// later that inherits "throw the ink away" because that is what the one original path did.
/// `StrokeGiveUp.inkSurvives` is an exhaustive `switch` with no `default:`, so a new case cannot
/// compile without stating an answer — and `testEveryGiveUpReasonStatesWhetherTheInkSurvives` walks
/// `allCases` against a table written here by hand, so a new case cannot be *added* without somebody
/// stating the answer twice, in two files, on purpose.
///
/// **Why this is a logic test and not a UI test, measured rather than assumed.** The path into
/// `giveUpReason` is `StrokeGestureRecognizer.touchesBegan` finding a touch already tracked. XCUITest
/// cannot produce it: every two-finger gesture the harness synthesises arrives as a *single*
/// `touchesBegan` carrying two touches, which the recognizer's earlier `touches.count == 1` guard
/// catches, so the tracked-touch branch is never entered at all. A UI test here is not slow, it is
/// incapable — which is exactly why the decision was lifted out of the recognizer into free
/// functions over `Bool`s.
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

    // MARK: - Reading the three signals

    /// All eight combinations of the three readings, with the reason each one is what it is.
    ///
    /// The shape to notice is that **seven of the eight are `.interrupted`**: any one of the three
    /// signals saying "orphan" is enough, because none of them is reliable alone. `allTouches` is
    /// documented as the *event's* touches rather than the window's; a `UITouch` object recycled by
    /// UIKit reads as `.began`; and a phase read on a recycled object describes the new touch, not
    /// the old one. Requiring agreement would mean answering "hand-off" whenever one signal happened
    /// to be unavailable — which is today's behaviour and today's bug.
    private let combinations: [(amongArrivals: Bool, stillInEvent: Bool, hasFinished: Bool,
                                expected: StrokeGiveUp, why: String)] = [
        (false, true, false, .handedOver,
         "The only hand-off: the tracked touch is not among the arrivals, is still in the event, and "
         + "has not finished — i.e. a finger genuinely still on the glass while a second one lands."),
        (false, true, true, .interrupted,
         "Still in the event but its own phase says ended/cancelled: direct evidence of a corpse."),
        (false, false, false, .interrupted,
         "Gone from the event entirely. A touch still on the glass is in `event.allTouches`; one "
         + "whose sequence ended without this recognizer hearing about it is not."),
        (false, false, true, .interrupted, "Two signals agree it is over."),
        (true, true, false, .interrupted,
         "The tracked object is itself among the arrivals — UIKit recycled it, so the previous "
         + "sequence is long over. Its phase reading `.began` describes the *new* touch."),
        (true, true, true, .interrupted, "Recycled, and the phase agrees."),
        (true, false, false, .interrupted, "Recycled and absent from the event."),
        (true, false, true, .interrupted, "All three signals say orphan."),
    ]

    func testEveryCombinationOfTheThreeReadings() {
        XCTAssertEqual(combinations.count, 8, "Three Bools have eight combinations; state all of them")
        var seen = Set<String>()
        for combination in combinations {
            let key = "\(combination.amongArrivals)\(combination.stillInEvent)\(combination.hasFinished)"
            XCTAssertTrue(seen.insert(key).inserted, "Combination \(key) is listed twice")

            let actual = StrokeInterruption.giveUpReason(
                trackedTouchIsAmongArrivals: combination.amongArrivals,
                trackedTouchIsStillInTheEvent: combination.stillInEvent,
                trackedTouchHasFinished: combination.hasFinished)
            XCTAssertEqual(actual, combination.expected, """
                giveUpReason(amongArrivals: \(combination.amongArrivals), \
                stillInEvent: \(combination.stillInEvent), \
                hasFinished: \(combination.hasFinished)) should be \(combination.expected). \
                \(combination.why)
                """)
        }
    }

    /// The rule in one line, asserted separately from the table so that rewriting the table cannot
    /// take it with it: **any one signal is enough.**
    func testAnySingleSignalIsEnoughToCallItInterrupted() {
        XCTAssertEqual(StrokeInterruption.giveUpReason(trackedTouchIsAmongArrivals: true,
                                                       trackedTouchIsStillInTheEvent: true,
                                                       trackedTouchHasFinished: false), .interrupted)
        XCTAssertEqual(StrokeInterruption.giveUpReason(trackedTouchIsAmongArrivals: false,
                                                       trackedTouchIsStillInTheEvent: true,
                                                       trackedTouchHasFinished: true), .interrupted)
        XCTAssertEqual(StrokeInterruption.giveUpReason(trackedTouchIsAmongArrivals: false,
                                                       trackedTouchIsStillInTheEvent: false,
                                                       trackedTouchHasFinished: false), .interrupted)
    }

    /// The two-finger pan the class was written around still has to work, and this is the assertion
    /// that stops the fix being "return `.interrupted`". A recognizer that answered `.interrupted`
    /// for a live second finger would commit an undo step for every pan-dab and, worse, take the
    /// terminal-state path on a sequence that is still going.
    func testALiveSecondFingerIsStillAHandOff() {
        XCTAssertEqual(StrokeInterruption.giveUpReason(trackedTouchIsAmongArrivals: false,
                                                       trackedTouchIsStillInTheEvent: true,
                                                       trackedTouchHasFinished: false), .handedOver)
    }

    /// **The known cost, recorded so it stays known.** The touch that *discovers* the corpse spends
    /// itself doing so: `touchesBegan` gives the previous stroke up and returns, leaving the
    /// recognizer in a terminal state that receives nothing further until UIKit resets it. So an
    /// interrupted stroke costs the artist one swallowed touch — the *third* attempt is the first
    /// that draws, not the second.
    ///
    /// What is assertable headlessly is the half that decides it: the discovery reads `.interrupted`,
    /// which is the branch that returns. Binding the new touch instead would mean driving `state`
    /// from `.changed`/`.ended` back to `.began`, which is not a documented transition and whose
    /// failure mode is "drawing stops working" rather than "drawing is delayed by one touch".
    ///
    /// If this ever stops being true — if a later change makes the discovering touch draw — this test
    /// is where to come and say so, rather than discovering it as a surprise.
    func testTheTouchThatDiscoversACorpseIsSpentDiscoveringIt() {
        // The everyday shape of the discovery: UIKit handed the tracked touch's object back out for
        // the new touch, so it arrives among `touches`.
        XCTAssertEqual(StrokeInterruption.giveUpReason(trackedTouchIsAmongArrivals: true,
                                                       trackedTouchIsStillInTheEvent: true,
                                                       trackedTouchHasFinished: false),
                       .interrupted,
                       "This is the branch that commits the old stroke and returns without starting a new one")
    }
}
