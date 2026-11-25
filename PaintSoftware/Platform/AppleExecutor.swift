import Foundation
import QuartzCore

/// **The scheduler's workers and clock on Apple platforms** — the one file in the scheduler's seam
/// that may spell a dispatch queue or a thread (SCHEDULER_DESIGN.md §2, `tools/check-scheduling-seam.py`).
///
/// QoS by class: R1 `.userInitiated`, R2 and R3 `.utility`. `.userInteractive` is the main thread's
/// alone. The lanes' capacities are the scheduler's (`LanePolicy`), so the global queues here only
/// ever see as many jobs as the machine has room for.
final class AppleExecutor: Executor {
    var now: Double { CACurrentMediaTime() }

    func run(_ jobClass: JobClass, _ body: @escaping @Sendable () -> Void) {
        let qos: DispatchQoS.QoSClass
        switch jobClass {
        case .answer: qos = .userInitiated
        case .soon, .later: qos = .utility
        }
        DispatchQueue.global(qos: qos).async(execute: body)
    }

    func main(_ body: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: body)
    }

    func main(after seconds: Double, _ body: @escaping @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    func park(_ seconds: Double) {
        // A composite run on the main thread — a test, an export's synchronous path — passes straight
        // through: main never waits (rule 1).
        guard !Thread.isMainThread else { return }
        Thread.sleep(forTimeInterval: seconds)
    }
}

extension Scheduler {
    /// The app's scheduler.
    static let shared = Scheduler(executor: AppleExecutor(), machine: AppleMachine())
}
