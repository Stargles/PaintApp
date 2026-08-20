import Foundation

/// Why a stroke that was already being tracked is being given up, and — the half that matters to the
/// artist — whether the ink painted so far survives it.
///
/// **This is the rule that makes dismissing a popover on `interactionBegan` safe.** Before it there
/// was exactly one way to abandon a stroke, `StrokeCanvasView.handleCancel`, and it rolled the layer
/// back to the pre-stroke snapshot with no undo step: as far as the document was concerned the
/// stroke never happened. That is correct for the case it was written for — a second finger landing
/// mid-stroke means "pan the canvas", and a stray dab left permanently on the artwork with nothing to
/// undo it was the bug that put the rollback there. It is wrong for every other way a sequence can
/// end, and the owner's 2026-08-18 report is what it costs: draw under a timeline menu, the stroke
/// runs a little way and stops, and *starting the next stroke makes the first one disappear*. The
/// first stroke was never baked — it lived only in the live buffer — and the next touch found the
/// recognizer still holding a dead one, took the rollback path meant for a two-finger pan, and threw
/// it away.
///
/// So the two are separated here, by name, with an exhaustive `switch` deciding the ink.
/// `StrokeInterruptionLogicTests` walks `allCases` against a hand-written table, so a third reason
/// added later has to state what happens to the artist's ink rather than inherit an answer.
enum StrokeGiveUp: String, CaseIterable, Hashable {

    /// **Another touch joined the live sequence and the canvas transform takes over.** The artist put
    /// a second finger down; what they asked for is a pan/pinch/rotate, not a mark. The dab or two
    /// laid down before the second finger landed is an artefact of how the gesture starts, not
    /// something anyone drew on purpose, so it is rolled back and no undo step is recorded.
    case handedOver

    /// **The sequence stopped reaching this recognizer.** The system cancelled it, or a presentation
    /// was torn down over the top of it and UIKit quietly stopped delivering — the shape of failure
    /// this repo has now recorded from three directions (`BUGS.md`'s 2026-08-16 entry, 8ae8613's
    /// stranded `reset()`, and the 2026-08-18 report's two symptoms).
    ///
    /// The artist drew a line and meant it. It stays.
    case interrupted

    /// Whether the ink already painted into the layer survives this, as a committed, undoable stroke.
    ///
    /// **Exhaustive, with no `default:`.** The failure this type exists to stop is a new abandonment
    /// path inheriting "throw the ink away" because that is what the one existing path did, and a
    /// `default:` here is precisely how that would happen.
    var inkSurvives: Bool {
        switch self {
        case .handedOver:
            // Rolled back. See the case's own doc: the alternative is a permanent, un-undoable dot
            // at the start of every two-finger pan begun from a stroke.
            return false
        case .interrupted:
            // Committed, with an undo step, exactly as a lift would have committed it. The stroke is
            // shorter than the artist intended — nothing here can recover samples UIKit never
            // delivered — but a short stroke they can undo, or draw over, beats one that vanishes the
            // moment they try again.
            return true
        }
    }
}

/// The decision `StrokeGestureRecognizer.touchesBegan` has to make when a new touch lands while a
/// stroke is *already* being tracked: is the tracked stroke still live, so this is the two-finger
/// hand-off the class was written around — or is it a corpse, left over from a sequence that stopped
/// being delivered and was never terminated?
///
/// **Today's tree cannot tell the difference, and answers "hand-off" every time.** That single
/// mis-answer is the whole of symptom 1 in the owner's report: it discards the previous stroke's ink
/// (`handedOver`), *and* it returns before `onBegin`, so the touch the artist meant as their second
/// stroke does not draw either. The third attempt is the first that works, because by then the
/// recognizer has finally reached a terminal state and been reset.
///
/// Split out of the recognizer as free functions over `Bool`s so it can be tested headlessly.
/// XCUITest cannot synthesise the sequence that reaches it — measured, every two-finger gesture the
/// suite produces arrives as a single `touchesBegan` carrying two touches, which takes the earlier
/// `touches.count == 1` guard and never gets here — so a UI test is not merely slow at this, it is
/// incapable of it.
enum StrokeInterruption {

    /// - Parameters:
    ///   - trackedTouchIsAmongArrivals: the tracked `UITouch` *object* is itself in the set that just
    ///     began. `UITouch`es are recycled by UIKit, so this means the previous sequence is long over
    ///     and its object has been handed back out for a new one. (Today this case does not even
    ///     reach the hand-off: `arrivals` filters the tracked touch out, the `arrivals.isEmpty` guard
    ///     fires, and `touchesBegan` returns having done nothing at all — a stroke that silently
    ///     refuses to start.)
    ///   - trackedTouchIsStillInTheEvent: the tracked touch is in `event.allTouches`. A touch that is
    ///     genuinely still on the glass is; one whose sequence ended without this recognizer hearing
    ///     about it is not.
    ///   - trackedTouchHasFinished: the tracked touch's own `phase` is `.ended` or `.cancelled`.
    ///     Direct evidence, when the object has not been recycled yet.
    ///
    /// Any one of the three is enough to say "orphan". They are three independent readings of the
    /// same fact and none is reliable alone — `allTouches` is documented as the event's touches
    /// rather than the window's, a recycled object reads as `.began`, and a phase read on a recycled
    /// object describes the *new* touch. Requiring all three to agree would mean answering
    /// "hand-off" whenever one of them was unavailable, which is today's behaviour and today's bug.
    static func giveUpReason(trackedTouchIsAmongArrivals: Bool,
                             trackedTouchIsStillInTheEvent: Bool,
                             trackedTouchHasFinished: Bool) -> StrokeGiveUp {
        if trackedTouchIsAmongArrivals || trackedTouchHasFinished || !trackedTouchIsStillInTheEvent {
            return .interrupted
        }
        return .handedOver
    }
}
