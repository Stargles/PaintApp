import Foundation

/// Decides when the smart-shape hold gesture has completed, from the **pen's own clock** rather than
/// the app's.
///
/// The question is "has the pen been physically still for 0.8 s?" That is a fact about the pen, and
/// `UITouch.timestamp` is the pen's hardware clock — a main-thread stall cannot affect it. So the
/// decision is a subtraction between two touch timestamps and nothing else: the newest sample seen,
/// minus the newest sample that actually moved.
///
/// **What this replaces, and why the replacement is not a better threshold but no threshold.** The
/// hold used to be a wall-clock `Timer`: arm 0.8 s, re-arm on every move, fire if it ever elapsed.
/// A `Timer` does not tick while the main thread is stalled — it fires once, late — so wall clock
/// could not tell "the pen was parked for 0.8 s" from "the app was frozen for 0.8 s while the pen
/// kept drawing". The popover teardown at `AnimationTimeline`'s `interactionBegan` sink produces
/// exactly the second, and the artist's stroke was replaced by a smart line built from its own
/// opening samples. The first fix attempt measured *awake* time by rejecting tick gaps longer than a
/// tuned constant; that was rejected on review, correctly — it infers "the app froze" from "the app
/// went quiet", its value is fitted to one bug report rather than derived, and it needs re-tuning per
/// device while failing silently in both directions.
///
/// Under this design the bug is not caught, it is **unrepresentable**. Walk the cases:
///  * *Pen parked, app healthy.* Still samples keep arriving; `newestSampleTime` advances,
///    `lastMovedSampleTime` does not, the difference reaches 0.8 → fires. Correct.
///  * *App stalls a second while the pen keeps drawing.* The tick fires late, but both timestamps
///    are still from before the stall and are ~0 apart → does not fire. Then the catch-up batch is
///    processed — no samples are lost, every move path consumes `event.coalescedTouches(for:)` — its
///    samples moved, so `lastMovedSampleTime` advances → still does not fire. Correct twice, and the
///    app never has to *infer* what the pen did while it was blind: the samples say so.
///  * *App stalls while the pen is genuinely parked.* The backlog's timestamps span the stall, so
///    after catch-up the difference is a true 0.8 → fires, slightly late. Correct, and arguably what
///    is wanted: the artist did hold still.
///
/// A `Timer` is still what *asks* the question periodically. What changed is that it no longer
/// answers it — its own firing time is not an input to the decision.
///
/// **The one assumption, and it is the only way this design fails: a pencil held still must keep
/// delivering `touchesMoved`.** If a parked pen goes completely silent, `newestSampleTime` stops
/// advancing and the hold never completes at all. Believed safe — hand tremor plus a digitizer that
/// reports while in contact — but *not measured*, and the simulator cannot measure it because it has
/// no pencil. What settles it: an `ActionRecorder` capture of a pencil held still on the canvas for
/// two seconds (CLAUDE.md), reading the `"event":"touch","phase":"moved"` lines during the still
/// period — those carry `touch.timestamp`, the same clock this type runs on. Samples continuing at
/// roughly digitizer rate confirms it; a run that stops dead is the falsification, and the answer
/// then is a measured "the pen goes silent after N ms", not a wall-clock threshold brought back.
///
/// Dependency-free (Foundation only, and every time is supplied by the caller) for the same reason
/// `StrokeStabilizer` is: it compiles into the test target, so the decision is testable headlessly.
/// That matters more here than usual — the failure is a main-thread stall, which XCUITest cannot
/// synthesise at all, but as a sequence of (timestamp, moved) pairs "wall clock jumped and sample
/// time did not" is just data.
struct ShapeHoldClock {
    /// How still the pen must be, on its own clock, for the gesture to complete.
    static let holdInterval: TimeInterval = 0.8

    /// How often the caller is expected to ask. Only the resolution of the answer, never part of it.
    static let tickInterval: TimeInterval = 0.1

    /// `UITouch.timestamp` of the newest sample seen at all — including the ones too small to count
    /// as movement, which are precisely what a parked pen delivers.
    private(set) var newestSampleTime: TimeInterval?

    /// `UITouch.timestamp` of the newest sample that travelled far enough to count as not-holding.
    private(set) var lastMovedSampleTime: TimeInterval?

    /// One touch sample. `moved` is the caller's existing "further than the micro-move threshold"
    /// decision — kept there because it is a distance in the caller's coordinate space, and this type
    /// deliberately knows nothing about geometry.
    mutating func sample(at time: TimeInterval, moved: Bool) {
        newestSampleTime = time
        // The first sample seeds both: a stroke has only just started, so there is no stillness yet.
        if moved || lastMovedSampleTime == nil { lastMovedSampleTime = time }
    }

    /// Has the pen been still for `holdInterval` of its own time? Nil-safe: before the first sample
    /// there is nothing to be still about, and a stroke that never moves never gets past
    /// `fireShapeDetection`'s three-sample minimum anyway.
    var isHoldComplete: Bool {
        guard let newest = newestSampleTime, let lastMoved = lastMovedSampleTime else { return false }
        return newest - lastMoved >= Self.holdInterval
    }

    /// Stillness accumulated so far, on the pen's clock. For tests and for a recorder line.
    var stillDuration: TimeInterval {
        guard let newest = newestSampleTime, let lastMoved = lastMovedSampleTime else { return 0 }
        return newest - lastMoved
    }
}
