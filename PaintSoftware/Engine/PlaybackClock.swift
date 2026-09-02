import Foundation

/// How many frames playback owes the wall clock, and how it is paid.
///
/// The playhead's position during playback is **derived from elapsed time**, never accumulated from
/// tick counts. The clock records the wall time playback started (`epoch`) and how many frames have
/// already been handed out (`framesConsumed`); a tick asks how many frames are *due* by now and
/// takes the difference. Three properties fall out of that and none of them can be had from a
/// repeating timer's own firing:
///
///  * **A late tick skips rather than stretches.** If the main thread is busy for 100 ms at 24 fps,
///    two or three frames come due at once and `take` returns them together. The old design
///    advanced by one per fire, so a stalled app played the animation in slow motion.
///  * **The clock does not drift.** `framesDue` is measured from the epoch every time, so a tick
///    that arrives 3 ms late does not push the next one 3 ms later still. A timer at `1/fps` with
///    per-fire increments accumulates every one of those milliseconds.
///  * **The frame rate is read at derivation time, not at play time.** `fps` is an argument to
///    `framesDue`, so changing it takes effect on the next tick. The old design captured
///    `1.0 / fps` into the timer's interval when play was pressed and could not see a change at all.
///
/// The type knows nothing about loop ranges, scene length or where playback stops — that is
/// `CanvasManager.advancePlayback(by:)`, which folds a frame count into the animation's own bounds.
/// This only answers "how many frames of time have passed".
///
/// Foundation only, and every time is supplied by the caller (RENDER §2.6, portability): no
/// `CADisplayLink`, no `CACurrentMediaTime`, nothing that ties the clock to one OS. That is also what
/// makes it testable headlessly — a test hands it numbers instead of sleeping.
struct PlaybackClock {

    /// Wall time at which the frame playback is counting from was shown.
    private(set) var epoch: TimeInterval

    /// Frames already handed out since `epoch`. The subtrahend that makes `take` drift-free.
    private(set) var framesConsumed: Int = 0

    init(startedAt now: TimeInterval) {
        epoch = now
    }

    /// How many frames *should* have elapsed since the epoch by `now`, at `fps`.
    ///
    /// Clamped rather than trapping: `Int(_:)` on a `Double` larger than `Int.max` is a runtime trap
    /// in Swift, and the elapsed term is attacker-free but not bounded — a system clock change can
    /// hand this an arbitrary number.
    func framesDue(at now: TimeInterval, fps: Int) -> Int {
        let elapsed = max(0, now - epoch)
        let raw = (elapsed * Double(max(fps, 1))).rounded(.down)
        guard raw.isFinite, raw < Double(Int.max / 2) else { return Int.max / 2 }
        return Int(raw)
    }

    /// The frames owed at `now`, taken. Returns 0 when the tick arrived before the next frame was
    /// due, which is the normal case for a tick source that oversamples the frame rate.
    mutating func take(at now: TimeInterval, fps: Int) -> Int {
        let due = framesDue(at: now, fps: fps)
        defer { framesConsumed = max(due, framesConsumed) }
        return max(due - framesConsumed, 0)
    }

    /// Restarts the count from `now` without handing out a frame.
    ///
    /// This is what a mid-playback frame-rate change does: the playhead must not jump, so the new
    /// rate applies to time from here on rather than being applied retroactively to the whole
    /// elapsed span. The sub-frame remainder of the old rate is dropped with the old epoch — at most
    /// one frame interval, once per change, and paying it back would mean carrying a fraction whose
    /// only effect is to make the first frame after a rate change slightly early.
    mutating func rebase(at now: TimeInterval) {
        epoch = now
        framesConsumed = 0
    }
}
