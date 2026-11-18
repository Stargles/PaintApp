import Foundation
import QuartzCore

/// **SCHEDULER.md rule 3's switch: whether a finger or pencil is on the glass, or lifted less than
/// `settle` ago — and the checkpoint that later work waits at while it is.**
///
/// The owner's recording of 2026-11-17 showed the frame bake compositing a whole 5000² frame (5.3–8.8 s
/// on the iPad 9) at the same time as every long main-thread pass while they drew and panned. The bake
/// is work nobody is looking at while the artist edits — the canvas shows the layers themselves then —
/// so it waits: a bake does not start while this is closed, and a bake already running stops at its
/// next checkpoint (`checkpoint()`, between leaves and between strips) until it opens again. A worker
/// that declines to start while it is closed looks again `settle` later; nothing here calls back.
///
/// **What feeds it is the window's one touch counter** (`ModifierHoldHost`'s `window.touchCounter`),
/// which counts every touch on the window, pencil and fingers alike, and is the counter the snap
/// constraint already trusts. **A count that never comes back to zero cannot pause work for ever**:
/// past `stuckAfter` with no change in the count the gate treats the count as stranded and opens.
///
/// Thread-safe; written on the main thread, read anywhere. Stage 2 of SCHEDULER.md replaces the ad
/// hoc readers with its lanes, and this stays the one "is a touch down" flag those lanes read.
final class InteractionGate: @unchecked Sendable {

    static let shared = InteractionGate()

    /// How long after the last touch lifts later work keeps waiting — SCHEDULER.md rule 3.
    static let settle: CFTimeInterval = 0.25
    /// A count unchanged this long is taken to be stranded (a missed end), not a hand at rest.
    static let stuckAfter: CFTimeInterval = 10
    /// How long a waiting worker sleeps between looks: the gate opens at most this late.
    static let pollInterval: TimeInterval = 0.02

    private let lock = NSLock()
    private var touchesDown = 0
    private var lastChange: CFTimeInterval = -.infinity
    private var lastLift: CFTimeInterval = -.infinity

    /// The clock, replaceable so a logic test can walk the rule without sleeping.
    var now: () -> CFTimeInterval = CACurrentMediaTime

    /// The window's touch count changed. Main thread.
    func touchesChanged(to count: Int) {
        let time = now()
        lock.lock()
        if count == 0, touchesDown > 0 { lastLift = time }
        touchesDown = count
        lastChange = time
        lock.unlock()
    }

    /// Whether later work should wait now.
    var isClosed: Bool {
        let time = now()
        lock.lock()
        defer { lock.unlock() }
        return closedLocked(at: time)
    }

    private func closedLocked(at time: CFTimeInterval) -> Bool {
        if touchesDown > 0 { return time - lastChange < Self.stuckAfter }
        return time - lastLift < Self.settle
    }

    /// **The R3 checkpoint.** Returns at once while the gate is open; while it is closed, blocks the
    /// calling worker until it opens. Never waits on the main thread (rule 1): a composite run there —
    /// a test, an export's synchronous path — passes straight through.
    func checkpoint() {
        guard !Thread.isMainThread else { return }
        while isClosed { Thread.sleep(forTimeInterval: Self.pollInterval) }
    }
}
