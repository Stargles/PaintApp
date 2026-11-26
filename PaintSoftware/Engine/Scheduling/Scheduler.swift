import Foundation

/// **The one place work is admitted to the machine** — SCHEDULER.md, built as SCHEDULER_DESIGN.md §2.
///
/// Three lanes beside the main thread (`JobClass`), each with a capacity `LanePolicy` sets from the
/// machine and the moment; a touch flag (`TouchFlag`) that holds later work and never an answer; a
/// cancel token per job, and latest-wins by `JobKey` (rule 4). A job's `work` runs on a worker the
/// `Executor` provides; its `land` runs on the main thread unless the job was cancelled first, so a
/// stale result never reaches the screen. An answer that lands more than
/// `JobClass.answerDeadline` after it was asked for is counted as late — counted, never waited on
/// (rule 8).
///
/// Platform-free: the clock, the workers and the main thread are the executor's. The app's instance
/// is `Scheduler.shared` (`Platform/AppleExecutor.swift`); a logic test builds one over a
/// `VirtualExecutor` and walks every rule on any core count.
///
/// What S1 put on it: the frame a step asks for (R1) and the decoded-frame prefetch ahead of the
/// playhead (R2), `FrameBaker`; and the touch flag every R3 checkpoint parks on. The other producers
/// move onto it in S3–S7 (SCHEDULER_DESIGN.md §6).
final class Scheduler: @unchecked Sendable {

    /// What a trace and a test read off the scheduler.
    struct Stats: Equatable {
        var started = 0
        var landed = 0
        /// Jobs dropped because a newer one of their key, or `cancel(key:)`, came first.
        var cancelled = 0
        /// Answers that landed past `JobClass.answerDeadline` after they were asked for.
        var lateAnswers = 0
        /// The late answers by job name — which kind of answer missed, for the gate's trace.
        var lateByName: [String: Int] = [:]
        /// The last answer to land: its name, and how long it waited and ran, in ms.
        var lastAnswer: (name: String, waitedMs: Int, ranMs: Int)?

        /// `name=count,…` of the late answers, or `none` — a trace field (spaces become underscores).
        var lateField: String {
            let parts = lateByName.sorted { $0.key < $1.key }
                .map { "\($0.key.replacingOccurrences(of: " ", with: "_"))=\($0.value)" }
            return parts.isEmpty ? "none" : parts.joined(separator: ",")
        }

        static func == (a: Stats, b: Stats) -> Bool {
            a.started == b.started && a.landed == b.landed && a.cancelled == b.cancelled
                && a.lateAnswers == b.lateAnswers && a.lateByName == b.lateByName && a.lastAnswer?.name == b.lastAnswer?.name
                && a.lastAnswer?.waitedMs == b.lastAnswer?.waitedMs && a.lastAnswer?.ranMs == b.lastAnswer?.ranMs
        }
    }

    /// How often a parked later job looks at the touch flag again.
    static let parkInterval = 0.02

    let executor: Executor
    let machine: Machine

    private let lock = NSCondition()
    private var touch = TouchFlag()
    private var waiting: [JobClass: [Pending]] = [:]
    private var running: [JobClass: Int] = [:]
    /// The groups with a job running — a group's next job waits for it (`Job.group`).
    private var runningGroups: Set<AnyHashable> = []
    /// The newest job's token for each key, waiting or running.
    private var tokens: [JobKey: CancelToken] = [:]
    /// The moment a look at held work is already arranged for.
    private var releaseLookAt: Double?
    private var counters = Stats()

    init(executor: Executor, machine: Machine) {
        self.executor = executor
        self.machine = machine
    }

    /// A job erased to what the lanes need.
    private struct Pending {
        let key: JobKey
        let jobClass: JobClass
        let name: String
        let visible: Bool
        let group: AnyHashable?
        let token: CancelToken
        let submittedAt: Double
        /// Runs the work; answers the landing, or nil when it stopped at a cancelled checkpoint.
        let perform: (JobContext) -> (() -> Void)?
    }

    // MARK: - Jobs

    /// **Queues `job`**, cancelling any job of the same key — still waiting (it never starts) or
    /// running (it stops at its next checkpoint, and its landing is dropped). Any thread.
    @discardableResult
    func submit<Result>(_ job: Job<Result>) -> CancelToken {
        let token = CancelToken()
        let pending = Pending(key: job.key, jobClass: job.jobClass, name: job.name, visible: job.visible,
                              group: job.group, token: token, submittedAt: executor.now, perform: { context in
            // Any throw is a stop: `checkpoint()` throws only once the job is cancelled.
            do {
                let result = try job.work(context)
                return { job.land(result) }
            } catch {
                return nil
            }
        })
        lock.lock()
        dropLocked(job.key)
        tokens[job.key] = token
        waiting[job.jobClass, default: []].append(pending)
        lock.unlock()
        pump()
        return token
    }

    /// Cancels the job under `key`, waiting or running. Any thread.
    func cancel(key: JobKey) {
        lock.lock()
        dropLocked(key)
        lock.unlock()
    }

    /// **Holds the calling thread until no job of `group` is waiting or running.** A job of the group
    /// that is cancelled while waiting counts as gone. This is the one wait the scheduler offers, and
    /// it is main-thread-hostile: it exists for the fill commit's contract (`beginCanvasEdit` must read a
    /// canvas the pending fill is already part of) and for tests that need the work finished.
    func waitUntilIdle(group: AnyHashable) {
        lock.lock()
        while runningGroups.contains(group) || waiting.values.contains(where: { $0.contains { $0.group == group } }) {
            lock.wait()
        }
        lock.unlock()
    }

    private func dropLocked(_ key: JobKey) {
        guard let token = tokens.removeValue(forKey: key) else { return }
        token.cancel()
        for jobClass in JobClass.allCases {
            if let index = waiting[jobClass]?.firstIndex(where: { $0.token === token }) {
                waiting[jobClass]?.remove(at: index)
                counters.cancelled += 1
                lock.broadcast()
            }
        }
    }

    var stats: Stats {
        lock.lock(); defer { lock.unlock() }
        return counters
    }

    // MARK: - The touch flag (rule 3)

    /// The window's touch count changed. Main thread.
    func touches(_ count: Int) {
        lock.lock()
        touch.touches(count, at: executor.now)
        lock.unlock()
        pump()
    }

    /// Whether a touch is down or lifted less than `TouchFlag.settle` ago.
    var touchHeld: Bool {
        lock.lock(); defer { lock.unlock() }
        return touch.isHeld(at: executor.now)
    }

    /// **The R3 checkpoint's wait**: returns at once while no touch holds later work, and otherwise
    /// holds the calling worker until none does. Later work outside a job — the bake's strips, until
    /// S6 puts the bake on a lane — parks here too.
    func parkWhileTouchHeld() {
        while touchHeld { executor.park(Self.parkInterval) }
    }

    // MARK: - The lanes

    /// Starts every waiting job its lane has room for, highest class first.
    private func pump() {
        var starts: [Pending] = []
        lock.lock()
        let now = executor.now
        let held = touch.isHeld(at: now)
        for jobClass in JobClass.allCases {
            let capacity = LanePolicy.capacity(of: jobClass, touchHeld: held,
                                               answersRunning: running[.answer, default: 0], machine: machine)
            while running[jobClass, default: 0] < capacity,
                  let index = waiting[jobClass]?.firstIndex(where: {
                      (!held || jobClass != .soon || $0.visible) && !($0.group.map(runningGroups.contains) ?? false)
                  }) {
                let pending = waiting[jobClass]!.remove(at: index)
                running[jobClass, default: 0] += 1
                if let group = pending.group { runningGroups.insert(group) }
                counters.started += 1
                starts.append(pending)
            }
        }
        // Work the touch is holding is looked at again the moment the hold ends of its own accord.
        let heldWork = held && !(waiting[.soon, default: []].isEmpty && waiting[.later, default: []].isEmpty)
        var lookAt: Double?
        if heldWork, let release = touch.releases(after: now), releaseLookAt.map({ $0 > release }) ?? true {
            releaseLookAt = release
            lookAt = release
        }
        lock.unlock()
        if let lookAt {
            executor.main(after: max(0, lookAt - now)) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                if self.releaseLookAt == lookAt { self.releaseLookAt = nil }
                self.lock.unlock()
                self.pump()
            }
        }
        for pending in starts {
            executor.run(pending.jobClass) { [weak self] in self?.execute(pending) }
        }
    }

    private func execute(_ pending: Pending) {
        let startedAt = executor.now
        let context = JobContext(token: pending.token, jobClass: pending.jobClass, scheduler: self)
        let landing = pending.token.isCancelled ? nil : pending.perform(context)
        let ranFor = executor.now - startedAt
        lock.lock()
        running[pending.jobClass, default: 0] -= 1
        if let group = pending.group { runningGroups.remove(group) }
        lock.broadcast()
        lock.unlock()
        pump()
        executor.main { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.tokens[pending.key] === pending.token { self.tokens[pending.key] = nil }
            guard let landing, !pending.token.isCancelled else {
                self.counters.cancelled += 1
                self.lock.unlock()
                return
            }
            self.counters.landed += 1
            if pending.jobClass == .answer {
                let total = self.executor.now - pending.submittedAt
                if total > JobClass.answerDeadline {
                    self.counters.lateAnswers += 1
                    self.counters.lateByName[pending.name, default: 0] += 1
                }
                self.counters.lastAnswer = (pending.name, Int(((startedAt - pending.submittedAt) * 1000).rounded()),
                                            Int((ranFor * 1000).rounded()))
            }
            self.lock.unlock()
            landing()
        }
    }
}
