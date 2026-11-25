/// **The scheduler's two windows onto the machine it runs on** — SCHEDULER_DESIGN.md §2's one seam.
///
/// The core (`Scheduler`, `TouchFlag`, `LanePolicy`) is Swift standard library and Foundation value
/// types only, so it carries to another platform with another executor. On Apple the two are
/// `Platform/AppleExecutor.swift` and `Platform/AppleMachine.swift`, the only files that may spell a
/// dispatch queue, a thread or `sysctl` for the scheduler (`tools/check-scheduling-seam.py`); in a logic
/// test both are virtual, with a clock the test moves (`VirtualExecutor`).

/// Where work runs, and the clock the scheduler reads.
protocol Executor: AnyObject, Sendable {
    /// Seconds on a monotonic clock.
    var now: Double { get }
    /// Runs `body` on a worker at the class's priority (SCHEDULER.md §2: R1 above R2 above R3).
    func run(_ jobClass: JobClass, _ body: @escaping @Sendable () -> Void)
    /// Runs `body` on the main thread, after whatever is running there now.
    func main(_ body: @escaping @Sendable () -> Void)
    /// Runs `body` on the main thread `seconds` from now.
    func main(after seconds: Double, _ body: @escaping @Sendable () -> Void)
    /// Holds the calling worker for `seconds` — a later job parked at a checkpoint (rule 3).
    func park(_ seconds: Double)
}

/// What the machine has, read from it and never assumed (AGENTS.md: the iPad 9 is the minimum, not
/// the target). The minimum machine, the A13, is 2 fast and 4 efficient cores.
protocol Machine: Sendable {
    var fastCores: Int { get }
    var efficientCores: Int { get }
}

/// **How many jobs of each class may run at once** — SCHEDULER_DESIGN.md §2's lanes table, as a pure
/// function of the machine and the moment, so a test can walk it on any core count.
///
/// - R1: one job at a time — the answer the artist is waiting for gets the cores it needs, and a
///   second different-key answer waits for it rather than splitting them.
/// - R2: one, and only work on screen (`visible`), while a touch is down or just lifted; two otherwise.
/// - R3: none while a touch is down or just lifted — a running one parks at its next checkpoint; one
///   while an answer runs; otherwise every core but one, which stays the pencil's, the main
///   thread's and the window server's.
enum LanePolicy {
    static func capacity(of jobClass: JobClass, touchHeld: Bool, answersRunning: Int, machine: Machine) -> Int {
        switch jobClass {
        case .answer: return 1
        case .soon: return touchHeld ? 1 : 2
        case .later:
            if touchHeld { return 0 }
            if answersRunning > 0 { return 1 }
            return max(1, machine.fastCores + machine.efficientCores - 1)
        }
    }
}
