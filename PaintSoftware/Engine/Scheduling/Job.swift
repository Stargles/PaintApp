import Foundation

/// **The real-time class of a piece of work** — SCHEDULER.md §2. R0 is the main thread and the
/// display, and is never a job.
enum JobClass: Int, CaseIterable, Comparable, Sendable {
    /// R1: the result of what the artist just did — a frame a step asks for, a stroke landing. Firm,
    /// 100 ms on the minimum machine; never held by the touch flag.
    case answer
    /// R2: on screen soon — prefetch for the next frame, thumbnails. Soft.
    case soon
    /// R3: nobody is looking yet — bakes, saves. Parked while a touch is down.
    case later

    static func < (a: JobClass, b: JobClass) -> Bool { a.rawValue < b.rawValue }

    /// The answer's deadline (rule 8: missing it is logged as late, never waited on).
    static let answerDeadline = 0.1
}

/// **The latest-wins identity of a job**: a job submitted under a key cancels the one before it under
/// the same key, waiting or running (rule 4).
struct JobKey: Hashable, @unchecked Sendable {
    let owner: String
    let subject: AnyHashable

    init(_ owner: String, _ subject: AnyHashable = 0) {
        self.owner = owner
        self.subject = subject
    }
}

/// A job's cancel switch: set by a newer job of the same key or by `Scheduler.cancel(key:)`, read by
/// the job at its checkpoints and by the scheduler before a landing.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

/// Thrown by `JobContext.checkpoint()` when the job was cancelled: the work stops there.
struct JobCancelled: Error {}

/// **One piece of work**: off-main `work`, and `land`, which runs on the main thread with its result
/// unless the job was cancelled first. `name` is what a trace calls it (rule 8).
struct Job<Result>: @unchecked Sendable {
    let key: JobKey
    let jobClass: JobClass
    let name: String
    /// Whether what it makes is on screen now — the only R2 work that runs while a touch is down.
    var visible = false
    /// Jobs of one group run one at a time, in the order they were submitted — what a serial queue
    /// shared by several owners gave (state one of them owns, or two canvas-sized pictures never held
    /// at once). Nil for a job that shares nothing. Until the memory manager admits work by its peak
    /// (SCHEDULER_DESIGN.md §6, S4) this is the only thing keeping two renders from piling up.
    var group: AnyHashable?
    let work: (JobContext) throws -> Result
    let land: (Result) -> Void
}

/// What a running job is handed.
struct JobContext: Sendable {
    /// **The job running on this thread**, for work deep in shared code that is not handed its
    /// context — a layer's walk reads it to stop when the job is cancelled and to know whose walk it is
    /// (`VectorCanvas.rasterize`). Nil outside a job: a caller of its own, such as the bake's worker.
    @TaskLocal static var current: JobContext?

    let token: CancelToken
    let jobClass: JobClass
    fileprivate unowned(unsafe) let scheduler: Scheduler

    init(token: CancelToken, jobClass: JobClass, scheduler: Scheduler) {
        self.token = token
        self.jobClass = jobClass
        self.scheduler = scheduler
    }

    /// **Where a job may stop.** Throws `JobCancelled` once it is cancelled; a later (R3) job parks
    /// here while a touch is down or just lifted (rule 3). Call it at least every 10 ms of work.
    func checkpoint() throws {
        if token.isCancelled { throw JobCancelled() }
        if jobClass == .later { scheduler.parkWhileTouchHeld() }
        if token.isCancelled { throw JobCancelled() }
    }
}
