/// **Whether a finger or pencil is on the glass, or lifted less than `settle` ago** — SCHEDULER.md rule
/// 3's switch. A pure value over the scheduler's clock; `Scheduler` holds one under its lock.
///
/// It is fed the window's one touch count (`ModifierHoldHost`), pencil and fingers alike. A count that
/// never comes back to zero cannot hold work for ever: past `stuckAfter` with no change it is taken as
/// a missed end and stops holding.
///
/// **It holds R3 and the R2 work nobody is looking at, never R1**: the touch is usually what asked for
/// the answer, and a frame step's read held by its own tap waited 250–500 ms (SCHEDULER_DESIGN.md §0).
struct TouchFlag: Equatable {
    /// How long after the last touch lifts later work keeps waiting.
    static let settle = 0.25
    /// A count unchanged this long is taken to be stranded, not a hand at rest.
    static let stuckAfter = 10.0

    private(set) var touchesDown = 0
    private var lastChange = -Double.infinity
    private var lastLift = -Double.infinity

    /// The window's touch count changed.
    mutating func touches(_ count: Int, at time: Double) {
        if count == 0, touchesDown > 0 { lastLift = time }
        touchesDown = count
        lastChange = time
    }

    /// Whether later work waits at `time`.
    func isHeld(at time: Double) -> Bool {
        if touchesDown > 0 { return time - lastChange < Self.stuckAfter }
        return time - lastLift < Self.settle
    }

    /// When the hold next ends of its own accord, if a touch is not down — the moment held work is
    /// looked at again.
    func releases(after time: Double) -> Double? {
        if touchesDown > 0 { return lastChange + Self.stuckAfter }
        let end = lastLift + Self.settle
        return end > time ? end : nil
    }
}
