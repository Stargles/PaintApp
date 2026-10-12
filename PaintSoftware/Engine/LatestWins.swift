import Dispatch

/// **Every live re-update in the app goes through one of these** — TODO (179): the newest request
/// wins, at most one job is in flight, and its result lands on the main thread before the next job is
/// minted. So a control the artist drags as fast as they like is drawn as fast as the device can draw
/// it, and no faster: the rate falls to what one job costs, the queue never holds a backlog of
/// pictures nobody will see, and the picture of the *last* request always lands.
///
/// **One job is a mint and a render.** `request` is handed a *mint* — a closure the main thread runs
/// against the model as it is when the worker comes free, which reads whatever the job needs and
/// answers the off-main work, or nil when there is nothing to do. The work runs on `queue` and
/// answers the *landing*, which runs on the main thread. Minting late rather than at the request is
/// what keeps a stale request from ever costing a render: during a scrub a pass requests at display
/// rate, and only the request standing when the worker frees is minted.
///
/// The contract, every clause of which a hand-rolled coalescer in this app relied on before they were
/// folded onto this one:
///
/// 1. `request` is O(1) on the main thread. A request made while busy replaces any request still
///    waiting, so one closure is held at most.
/// 2. **A mint runs only while nothing is in flight**, so it reads the model once per job, never once
///    per request.
/// 3. **One job in flight per instance.** Instances may share a serial queue, and then serialise
///    against each other too — the live pair and the eyedropper's pick share `sandwichQueue` so that
///    two canvas-sized composites are never held at once.
/// 4. **Land before mint**: the landing runs, and then the waiting request (if any) is minted. The
///    main thread holds at most one landing per instance, and the last request always lands — no
///    caller writes a catch-up of its own. A request made *from* a landing waits for the landing to
///    return, so a landing may ask again without re-entering itself.
/// 5. `cancel` drops the waiting request and the in-flight job's landing.
///
/// Main-actor and Dispatch only — no UIKit — so it lives in `Engine/` and is compiled into the test
/// target, where `LatestWinsLogicTests` pins every clause on a queue of its own.
@MainActor
final class LatestWins {

    /// The off-main half of one job: runs on the queue, and answers what lands on the main thread.
    typealias Work = () -> Landing
    /// The main-thread half of one job — the result put where the artist sees it.
    typealias Landing = () -> Void

    private let queue: DispatchQueue
    /// The newest request not yet minted.
    private var waiting: (() -> Work?)?
    private var inFlight = false
    /// True while a mint or a landing runs, so a request either makes waits for it to return rather
    /// than re-entering it (clause 4).
    private var isInCallback = false
    /// Moved by `cancel`; a landing minted under an older value is dropped.
    private var generation = 0

    /// **How many jobs have landed** — counted after the landing ran, cancelled ones excluded. What a
    /// probe reads as the rate the preview actually achieved, and what a test spins on.
    private(set) var landedCount = 0

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Whether a job is in flight or a request is waiting for one — the question a caller asks before
    /// it settles something the job's landing will still change. False *inside* a landing that asked
    /// for nothing more, so the landing itself may settle.
    var isBusy: Bool { inFlight || waiting != nil }

    /// Asks for a job. Replaces any request still waiting; minted now if nothing is in flight.
    func request(_ mint: @escaping () -> Work?) {
        waiting = mint
        startIfIdle()
    }

    /// Drops the waiting request, and the landing of the job in flight. The job itself runs to the
    /// end — work on a queue cannot be taken back — but nothing it produced reaches the main thread.
    func cancel() {
        waiting = nil
        generation &+= 1
    }

    private func startIfIdle() {
        guard !inFlight, !isInCallback else { return }
        while let mint = waiting {
            waiting = nil
            // A mint that answers nothing (the request no longer applies) frees the worker at once;
            // one that asked again from inside itself is minted on the next turn of this loop.
            isInCallback = true
            let minted = mint()
            isInCallback = false
            guard let work = minted else { continue }
            inFlight = true
            let generation = self.generation
            queue.async { [weak self] in
                let landing = work()
                DispatchQueue.main.async { self?.land(landing, minted: generation) }
            }
            return
        }
    }

    private func land(_ landing: Landing, minted: Int) {
        inFlight = false
        if minted == generation {
            isInCallback = true
            landing()
            isInCallback = false
            landedCount += 1
        }
        startIfIdle()
    }
}
