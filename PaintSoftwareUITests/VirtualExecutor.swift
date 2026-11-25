import Foundation

/// **The scheduler's executor in a logic test**: a clock the test moves, workers that run only when
/// the test says, and a main thread that is a queue the test drains. Every rule of SCHEDULER.md is
/// then a deterministic walk on any core count (SCHEDULER_DESIGN.md §2, "Testing").
final class VirtualExecutor: Executor, @unchecked Sendable {

    struct Machine: PaintSoftwareUITests.Machine {
        let fastCores: Int
        let efficientCores: Int
    }

    private(set) var clock = 1000.0
    var now: Double { clock }

    /// Started work, oldest first, not yet run.
    private(set) var workers: [(jobClass: JobClass, body: () -> Void)] = []
    private var mains: [(at: Double, order: Int, body: () -> Void)] = []
    private var order = 0
    /// Called as each worker is started, with its class — where a test checks what may start.
    var onStart: ((JobClass) -> Void)?

    func run(_ jobClass: JobClass, _ body: @escaping @Sendable () -> Void) {
        onStart?(jobClass)
        workers.append((jobClass, body))
    }

    func main(_ body: @escaping @Sendable () -> Void) { main(after: 0, body) }

    func main(after seconds: Double, _ body: @escaping @Sendable () -> Void) {
        order += 1
        mains.append((clock + seconds, order, body))
    }

    /// A parked worker's time passes on the test's clock.
    func park(_ seconds: Double) { clock += seconds }

    /// Runs the `index`th started worker to its end.
    func runWorker(_ index: Int = 0) {
        let worker = workers.remove(at: index)
        worker.body()
    }

    /// Runs every main-thread block due by now, including ones those blocks add.
    func drainMain() {
        while let next = mains.enumerated().filter({ $0.element.at <= clock })
                .min(by: { ($0.element.at, $0.element.order) < ($1.element.at, $1.element.order) }) {
            mains.remove(at: next.offset)
            next.element.body()
        }
    }

    /// Moves the clock on and runs what fell due.
    func advance(_ seconds: Double) {
        clock += seconds
        drainMain()
    }
}
