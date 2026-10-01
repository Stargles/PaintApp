import Foundation

/// **Whether a finger that has just landed on the canvas is an edit or the first finger of two.**
///
/// A canvas touch is not an interaction the instant it lands: a hand lands the two fingers of a pan
/// or a pinch 10–20 ms apart (`recording-20260923-200911`), so the first reaches the canvas **alone**,
/// indistinguishable from the tap or stroke it is not. Acting on it would close the open panel and
/// stop the playhead before the second finger arrived to say so (the owner's TODO (117) and (130)).
/// The batched `pinch` that XCUITest synthesises lands both touches in one event and never shows
/// this; `staggeredTwoFingerDrag` does.
///
/// So a lone finger is **watched** for `window` before it is believed. If a second touch joins in
/// that time it was the start of a transform, and none of the consequences happen. If the window
/// runs out with it still alone, or it lifts first, it was an edit or a tap and they happen then —
/// 80 ms late, which no artist can see. A pencil cannot be half of a two-finger transform, so it
/// never waits: `CanvasManager.canvasInteractionBegan(mayBeATransform: false)` is the immediate path
/// and does not come through here.
///
/// **A pure state machine with no clock of its own.** `CanvasManager` owns the timer and calls
/// `windowElapsed()`, which is what lets `CanvasTouchSettleLogicTests` walk every ordering of a
/// landing, a second touch, a lift and a timeout without a simulator or a sleep.
struct CanvasTouchSettle {

    /// How long a lone finger is watched: four times the 10–20 ms a hand's two fingers land apart, so
    /// the second is seen, and short enough that the delay to a tap's effect is not.
    static let window: TimeInterval = 0.08

    /// What a watched landing will do once it settles. The one thing a second landing for the same
    /// finger can still change about it (several recognizers see one touch and each reports it).
    struct Landing: Equatable {
        /// Whether a live recording take may carry on through this touch — see
        /// `CanvasManager.canvasInteractionBegan`.
        var mayContinueTake: Bool
    }

    /// What the owner of the clock must do next.
    enum Verdict: Equatable {
        case nothing
        /// A lone finger is now being watched: hold what its consequences would stop, start the window.
        case watch
        /// It was an edit or a tap: run its consequences now.
        case settled(Landing)
        /// A second touch joined, so it is a transform's. Nothing it landed with happens.
        case transform
    }

    /// The finger being watched, or nil when none is.
    private(set) var watching: Landing?

    /// Touches currently on the canvas, as `TouchCountRecognizer` last reported them.
    private(set) var touchesDown = 0

    /// A finger landed that might be the first of two.
    mutating func fingerLanded(mayContinueTake: Bool) -> Verdict {
        // Not alone, so not the first of anything: a third finger, or a finger beside a pencil.
        if touchesDown >= 2 { return .nothing }
        if var landing = watching {
            // The same finger, reported by a second recognizer. The stricter answer wins: if either
            // says this touch ends a take, it does.
            landing.mayContinueTake = landing.mayContinueTake && mayContinueTake
            watching = landing
            return .nothing
        }
        watching = Landing(mayContinueTake: mayContinueTake)
        return .watch
    }

    /// The canvas's touch count changed — fed from the host's `TouchCountRecognizer`, which sees
    /// every finger however it lands.
    mutating func touchCountChanged(to total: Int) -> Verdict {
        touchesDown = total
        guard let landing = watching else { return .nothing }
        if total >= 2 {
            watching = nil
            return .transform
        }
        if total == 0 {
            // The lone finger lifted without a companion: it was a tap.
            watching = nil
            return .settled(landing)
        }
        return .nothing
    }

    /// The watch window ran out with nothing joining the finger.
    mutating func windowElapsed() -> Verdict {
        guard let landing = watching else { return .nothing }
        watching = nil
        return .settled(landing)
    }

    /// An immediate (pencil) landing took over: whatever was being watched is superseded by it, since
    /// it runs every consequence the watched finger would have.
    mutating func supersede() {
        watching = nil
    }
}
