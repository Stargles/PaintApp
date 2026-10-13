import XCTest

/// **The one scheduler every live re-update goes through** — `LatestWins`, TODO (179).
///
/// Each test pins one clause of its contract on a queue of its own, with the work gated by a
/// semaphore so "while a job is in flight" is a state the test holds rather than a race it hopes to
/// win. The landings run on the main queue, which the tests spin.
@MainActor
final class LatestWinsLogicTests: XCTestCase {

    private let queue = DispatchQueue(label: "LatestWinsLogicTests.work")

    private func spin(until done: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(2)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertTrue(done(), "the condition was reached before the deadline", file: file, line: line)
    }

    /// A job whose work waits on `gate` and whose landing appends `name` to `landed`.
    private func gatedJob(_ name: String, gate: DispatchSemaphore?, minted: @escaping () -> Void = {},
                          landed: @escaping (String) -> Void) -> () -> LatestWins.Work? {
        {
            minted()
            return {
                gate?.wait()
                return { landed(name) }
            }
        }
    }

    /// **The newest of many requests is the one rendered, and the ones it replaced never are** —
    /// clause 1 — and **the last request always lands with no catch-up from the caller** — clause 4.
    func testTheNewestRequestMadeDuringAJobIsTheOnlyOneMintedAfterIt() {
        let scheduler = LatestWins(queue: queue)
        let gate = DispatchSemaphore(value: 0)
        var minted: [String] = []
        var landed: [String] = []
        scheduler.request(gatedJob("first", gate: gate, minted: { minted.append("first") }) { landed.append($0) })
        for index in 0..<10 {
            let name = "request \(index)"
            scheduler.request(gatedJob(name, gate: nil, minted: { minted.append(name) }) { landed.append($0) })
        }
        XCTAssertEqual(minted, ["first"], "nothing is minted while a job is in flight")
        XCTAssertTrue(scheduler.isBusy)
        gate.signal()
        spin { landed.count == 2 }
        XCTAssertEqual(minted, ["first", "request 9"], "only the newest waiting request was minted")
        XCTAssertEqual(landed, ["first", "request 9"], "and the last request landed, with nobody asking again")
        XCTAssertFalse(scheduler.isBusy)
        XCTAssertEqual(scheduler.landedCount, 2)
    }

    /// **Never two jobs in flight** — clause 3 — counted on the queue itself, across a burst of
    /// requests made faster than the work finishes.
    func testNeverTwoJobsInFlight() {
        let scheduler = LatestWins(queue: DispatchQueue(label: "LatestWinsLogicTests.concurrent",
                                                        attributes: .concurrent))
        let lock = NSLock()
        var running = 0, peak = 0
        var landed = 0
        for _ in 0..<40 {
            scheduler.request {
                return {
                    lock.lock(); running += 1; peak = max(peak, running); lock.unlock()
                    Thread.sleep(forTimeInterval: 0.002)
                    lock.lock(); running -= 1; lock.unlock()
                    return { landed += 1 }
                }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        }
        spin { !scheduler.isBusy }
        XCTAssertEqual(peak, 1, "a concurrent queue still saw one job at a time")
        XCTAssertGreaterThanOrEqual(landed, 1)
        XCTAssertLessThan(landed, 40, "requests made during a job coalesced rather than queued")
    }

    /// **A mint reads the model as it is when the worker frees**, not as it was at the request —
    /// clause 2. The value a request was made for is stale by the time it is minted; what it renders
    /// is the value then.
    func testAMintReadsTheModelWhenTheWorkerFrees() {
        let scheduler = LatestWins(queue: queue)
        let gate = DispatchSemaphore(value: 0)
        var model = 1
        var rendered: [Int] = []
        scheduler.request(gatedJob("first", gate: gate) { _ in })
        scheduler.request {
            let value = model
            return { { rendered.append(value) } }
        }
        model = 2
        model = 3
        gate.signal()
        spin { !rendered.isEmpty }
        XCTAssertEqual(rendered, [3], "minted against the model at the moment the worker freed")
    }

    /// **`cancel` drops the waiting request and the in-flight job's landing** — clause 5, the fill's
    /// generation rule.
    func testCancelDiscardsTheInFlightLandingAndTheWaitingRequest() {
        let scheduler = LatestWins(queue: queue)
        let gate = DispatchSemaphore(value: 0)
        var landed: [String] = []
        scheduler.request(gatedJob("in flight", gate: gate) { landed.append($0) })
        scheduler.request(gatedJob("waiting", gate: nil) { landed.append($0) })
        scheduler.cancel()
        gate.signal()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(landed, [], "neither the cancelled job nor the dropped request reached the main thread")
        XCTAssertFalse(scheduler.isBusy)
        scheduler.request(gatedJob("after", gate: nil) { landed.append($0) })
        spin { landed == ["after"] }
    }

    /// **A landing may ask again without re-entering itself** — clause 4's second half: the request
    /// it makes is minted after it returns, not inside it.
    func testALandingCanRequestAgainWithoutReentrancy() {
        let scheduler = LatestWins(queue: queue)
        var depth = 0, maxDepth = 0
        var landings = 0
        func ask() {
            scheduler.request {
                return {
                    return {
                        depth += 1; maxDepth = max(maxDepth, depth)
                        landings += 1
                        if landings < 3 { ask() }
                        depth -= 1
                    }
                }
            }
        }
        ask()
        spin { landings == 3 }
        XCTAssertEqual(maxDepth, 1, "each landing returned before the next was minted")
        XCTAssertFalse(scheduler.isBusy)
    }

    /// **A mint that answers nothing frees the worker at once**, and `isBusy` is false inside a
    /// landing that asked for nothing more — what the eyedropper's join reads from its own landing.
    func testANilMintFreesTheWorkerAndALandingIsNotBusy() {
        let scheduler = LatestWins(queue: queue)
        scheduler.request { nil }
        XCTAssertFalse(scheduler.isBusy, "nothing to do is nothing in flight")
        var busyInsideLanding: Bool?
        scheduler.request { { { busyInsideLanding = scheduler.isBusy } } }
        spin { busyInsideLanding != nil }
        XCTAssertEqual(busyInsideLanding, false)
    }

    // MARK: - Every interleaving, taken by hand

    /// **A scheduler whose every step the test takes** — no sleep, no race. The queue is serial and a
    /// job's work blocks on a gate the test opens, so "while the job is in flight" and "after the
    /// work, before the landing" are states the test sits in; the landing's hop to the main queue is
    /// delivered only when the test drains the main queue (`deliverLandings`). Every mint and landing
    /// appends to `events`, so an order is one array comparison, and `peakInFlight` is the most jobs
    /// minted and not yet released at once — the contract says one.
    @MainActor
    private final class Rig {
        let queue: DispatchQueue
        let scheduler: LatestWins
        private(set) var events: [String] = []
        /// The gates of jobs minted whose work the test has not yet opened.
        private var gates: [DispatchSemaphore] = []
        private(set) var peakInFlight = 0

        init(sharing queue: DispatchQueue? = nil) {
            let queue = queue ?? DispatchQueue(label: "LatestWinsLogicTests.rig")
            self.queue = queue
            scheduler = LatestWins(queue: queue)
        }

        var hasWorkToRelease: Bool { !gates.isEmpty }

        /// Asks for `name`. `answersNothing` is a mint with nothing to do; `inMint` and `inLanding` run
        /// inside the mint and inside the landing — where a caller asks again, or cancels.
        func request(_ name: String, answersNothing: Bool = false,
                     inMint: (() -> Void)? = nil, inLanding: (() -> Void)? = nil) {
            scheduler.request { [unowned self] in
                events.append(answersNothing ? "skip \(name)" : "mint \(name)")
                inMint?()
                if answersNothing { return nil }
                let gate = DispatchSemaphore(value: 0)
                gates.append(gate)
                peakInFlight = max(peakInFlight, gates.count)
                return {
                    gate.wait()
                    return { [unowned self] in
                        events.append("land \(name)")
                        inLanding?()
                    }
                }
            }
        }

        /// Opens the gate of every job whose work is held — one, when the contract holds. All of them, so
        /// that a scheduler that minted two does not leave the second behind the first on the serial
        /// queue with its gate shut, which would turn a wrong answer into a test that never returns.
        func openGates(file: StaticString = #filePath, line: UInt = #line) {
            guard !gates.isEmpty else {
                return XCTFail("no job is waiting to be released", file: file, line: line)
            }
            gates.forEach { $0.signal() }
            gates = []
        }

        /// Returns once everything queued has run — including, for a job whose gate is open, the hop
        /// to the main queue its work posts as it ends.
        func flushQueue() { queue.sync {} }

        /// Lets the job in flight finish its work and leaves its landing on the way to the main queue.
        func releaseWork(file: StaticString = #filePath, line: UInt = #line) {
            openGates(file: file, line: line)
            flushQueue()
        }

        /// Runs every landing posted so far, and nothing minted by them — a sentinel behind them on the
        /// main queue says when they are all done.
        func deliverLandings() { Rig.drainMainQueue() }

        static func drainMainQueue() {
            var reached = false
            DispatchQueue.main.async { reached = true }
            while !reached { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
        }

        /// Releases and lands until the scheduler is idle — and says so if it never is.
        func settle(file: StaticString = #filePath, line: UInt = #line) {
            for _ in 0..<200 where scheduler.isBusy {
                if hasWorkToRelease { releaseWork() }
                deliverLandings()
            }
            XCTAssertFalse(scheduler.isBusy, "the scheduler settled", file: file, line: line)
        }
    }

    /// **A request made while the landing is on its way to the main thread waits for it** — the work is
    /// over, the job is still in flight, and the request is neither minted early (two jobs) nor lost:
    /// the landing, when it runs, is followed by the request's mint (clause 4).
    func testARequestMadeWhileTheLandingIsOnItsWayWaitsForTheLandingThenIsMinted() {
        let rig = Rig()
        rig.request("a")
        rig.releaseWork()
        rig.request("b")
        XCTAssertEqual(rig.events, ["mint a"], "b is not minted while a's landing is still to come")
        XCTAssertTrue(rig.scheduler.isBusy)
        rig.deliverLandings()
        XCTAssertEqual(rig.events, ["mint a", "land a", "mint b"], "land before mint, and the landing woke the request")
        rig.settle()
        XCTAssertEqual(rig.events, ["mint a", "land a", "mint b", "land b"])
        XCTAssertEqual(rig.peakInFlight, 1)
    }

    /// **A request made from inside a mint waits for that mint's job** — it is stored, not minted
    /// inside the mint it came from, and the job's landing wakes it.
    func testARequestMadeFromInsideAMintWaitsForThatJobAndThenRuns() {
        let rig = Rig()
        rig.request("a", inMint: { rig.request("b") })
        XCTAssertEqual(rig.events, ["mint a"], "b was not minted inside a's mint")
        XCTAssertTrue(rig.scheduler.isBusy)
        rig.settle()
        XCTAssertEqual(rig.events, ["mint a", "land a", "mint b", "land b"])
        XCTAssertEqual(rig.peakInFlight, 1)
    }

    /// **A mint that answers nothing hands the worker to the request standing behind it, in the same
    /// turn** — and a request made from inside such a mint is that request.
    func testAMintThatAnswersNothingPassesTheWorkerOnWithoutAHop() {
        let rig = Rig()
        rig.request("skipped", answersNothing: true, inMint: { rig.request("asked from inside the skip") })
        XCTAssertEqual(rig.events, ["skip skipped", "mint asked from inside the skip"],
                       "the request made inside the skipped mint was minted in the same turn")
        rig.settle()
        XCTAssertEqual(rig.events.last, "land asked from inside the skip")
    }

    /// **The newest request answering nothing replaces an older one and leaves nothing busy** — newest
    /// wins, so nothing is drawn for the one it replaced, and nothing is left waiting.
    func testTheNewestRequestAnsweringNothingReplacesAnOlderOneAndLeavesNothingBusy() {
        let rig = Rig()
        rig.request("a")
        rig.request("older")
        rig.request("newest", answersNothing: true)
        rig.settle()
        XCTAssertEqual(rig.events, ["mint a", "land a", "skip newest"])
        XCTAssertFalse(rig.scheduler.isBusy)
    }

    /// **A cancelled job's landing is dropped, and it still wakes the request made after the cancel** —
    /// the interleaving a lost wakeup would live in. `cancel` clears the waiting request and the
    /// landing of the job in flight; the landing that does not run must still start whatever was
    /// asked since. Taken at each point the job can be in.
    func testACancelledLandingStillStartsTheRequestMadeAfterTheCancel() {
        // 1. Cancelled and asked again while the work runs.
        var rig = Rig()
        rig.request("a")
        rig.request("replaced")
        rig.scheduler.cancel()
        rig.request("after")
        XCTAssertEqual(rig.events, ["mint a"])
        rig.releaseWork()
        rig.deliverLandings()
        XCTAssertEqual(rig.events, ["mint a", "mint after"], "a's landing was dropped; its drop started the new request")
        rig.settle()
        XCTAssertEqual(rig.events, ["mint a", "mint after", "land after"])

        // 2. Cancelled while the landing is on its way, asked again before it arrives.
        rig = Rig()
        rig.request("a")
        rig.releaseWork()
        rig.scheduler.cancel()
        rig.request("after")
        rig.deliverLandings()
        XCTAssertEqual(rig.events, ["mint a", "mint after"])
        rig.settle()
        XCTAssertEqual(rig.events, ["mint a", "mint after", "land after"])

        // 3. Cancelled with nothing asked after: the job lands nowhere and the scheduler idles.
        rig = Rig()
        rig.request("a")
        rig.request("replaced")
        rig.scheduler.cancel()
        rig.releaseWork()
        rig.deliverLandings()
        XCTAssertEqual(rig.events, ["mint a"])
        XCTAssertFalse(rig.scheduler.isBusy, "the dropped landing left nothing in flight and nothing waiting")
        XCTAssertEqual(rig.scheduler.landedCount, 0)
    }

    /// **`cancel` from inside a landing drops what the landing had asked for before it** — and a request
    /// made after it, still inside the landing, is the one minted when the landing returns.
    func testACancelInsideALandingDropsWhatWasAskedBeforeItAndKeepsWhatIsAskedAfter() {
        let rig = Rig()
        rig.request("a", inLanding: {
            rig.request("asked then cancelled")
            rig.scheduler.cancel()
            rig.request("asked after the cancel")
        })
        rig.settle()
        XCTAssertEqual(rig.events, ["mint a", "land a", "mint asked after the cancel", "land asked after the cancel"])
    }

    /// **A landing that asks twice has only the last minted, after it returns** — and `isBusy` is true
    /// inside it, because something is waiting.
    func testALandingThatAsksTwiceMintsOnlyTheLastAfterItReturns() {
        let rig = Rig()
        var busyInside: Bool?
        var eventsInside: [String] = []
        rig.request("a", inLanding: {
            rig.request("first ask")
            rig.request("second ask")
            busyInside = rig.scheduler.isBusy
            eventsInside = rig.events
        })
        rig.settle()
        XCTAssertEqual(busyInside, true)
        XCTAssertEqual(eventsInside, ["mint a", "land a"], "nothing was minted inside the landing")
        XCTAssertEqual(rig.events, ["mint a", "land a", "mint second ask", "land second ask"])
    }

    /// **Two instances on one serial queue take turns and neither strands a request** — the live pair
    /// and the eyedropper's pick (`sandwichQueue`). Each mints at its own request even while the other's
    /// job holds the queue; each work runs when the queue frees; both land, and the request each made
    /// meanwhile follows its own landing.
    func testTwoInstancesSharingAQueueTakeTurnsAndBothRequestsLand() {
        let first = Rig()
        let second = Rig(sharing: first.queue)
        first.request("a1")
        second.request("b1")
        first.request("a2")
        second.request("b2")
        XCTAssertEqual(first.events, ["mint a1"])
        XCTAssertEqual(second.events, ["mint b1"], "b1 was minted while a1's job held the queue")
        // The queue holds a1's gated work and b1's behind it: both gates open before anything waits
        // on the queue, or the wait is for work still blocked.
        let rigs = [first, second]
        for _ in 0..<200 where rigs.contains(where: { $0.scheduler.isBusy }) {
            for rig in rigs where rig.hasWorkToRelease { rig.openGates() }
            first.flushQueue()
            Rig.drainMainQueue()
        }
        XCTAssertEqual(first.events, ["mint a1", "land a1", "mint a2", "land a2"])
        XCTAssertEqual(second.events, ["mint b1", "land b1", "mint b2", "land b2"])
        XCTAssertEqual(first.peakInFlight, 1)
        XCTAssertEqual(second.peakInFlight, 1)
    }

    /// **A scheduler let go of while a job is in flight lands nothing.**
    func testASchedulerReleasedWithAJobInFlightNeverLands() {
        let queue = DispatchQueue(label: "LatestWinsLogicTests.released")
        let gate = DispatchSemaphore(value: 0)
        var landed = false
        var scheduler: LatestWins? = LatestWins(queue: queue)
        scheduler?.request {
            return {
                gate.wait()
                return { landed = true }
            }
        }
        scheduler = nil
        gate.signal()
        queue.sync {}
        Rig.drainMainQueue()
        XCTAssertFalse(landed, "no landing ran after the scheduler was let go")
    }

    // MARK: - The contract as a model

    /// The contract's five clauses as a state machine small enough to read. `Contract` is the
    /// *specification* — it never looks at `LatestWins`' fields — and the test below runs it beside the
    /// real scheduler on randomly interleaved operations and compares the two after every step.
    private struct Contract {
        enum Kind { case plain, answersNothing, answersNothingAndAsks, asksInMint, asksInLanding, cancelsInLanding }
        struct Ask { let name: String; let kind: Kind }

        var waiting: Ask?
        var inFlight: Ask?
        var workDone = false
        var dropped = false
        var events: [String] = []

        var isBusy: Bool { inFlight != nil || waiting != nil }

        mutating func request(_ ask: Ask) { waiting = ask; startIfIdle() }

        mutating func cancel() {
            waiting = nil
            if inFlight != nil { dropped = true }
        }

        mutating func startIfIdle() {
            guard inFlight == nil else { return }
            while let ask = waiting {
                waiting = nil
                if ask.kind == .answersNothing { events.append("skip \(ask.name)"); continue }
                if ask.kind == .answersNothingAndAsks {
                    events.append("skip \(ask.name)")
                    waiting = Ask(name: ask.name + "'", kind: .plain)
                    continue
                }
                events.append("mint \(ask.name)")
                if ask.kind == .asksInMint { waiting = Ask(name: ask.name + "'", kind: .plain) }
                inFlight = ask; workDone = false; dropped = false
                return
            }
        }

        mutating func land() {
            guard let ask = inFlight else { return }
            inFlight = nil
            if !dropped {
                events.append("land \(ask.name)")
                if ask.kind == .asksInLanding { waiting = Ask(name: ask.name + "''", kind: .plain) }
                if ask.kind == .cancelsInLanding { waiting = nil }
            }
            startIfIdle()
        }
    }

    /// **Randomly interleaved requests, cancels, work ending and landings arriving** — a hundred and
    /// twenty seeds of forty steps, including requests made from inside a mint and a landing and a
    /// cancel inside a landing. After every step the real scheduler has minted and landed exactly what
    /// the contract says, in the same order, and answers `isBusy` as it does; and once every job's work
    /// has ended and every landing has arrived, nothing is left waiting.
    func testRandomInterleavingsFollowTheContractAndNeverStrandARequest() {
        for seed in 1...120 {
            var state = UInt64(seed) &* 0x9E3779B97F4A7C15
            func next(_ bound: Int) -> Int {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Int((state >> 33) % UInt64(bound))
            }
            let rig = Rig()
            var contract = Contract()
            var trace: [String] = []
            func ask(_ name: String, _ kind: Contract.Kind) {
                trace.append("ask \(name) \(kind)")
                contract.request(Contract.Ask(name: name, kind: kind))
                switch kind {
                case .plain: rig.request(name)
                case .answersNothing: rig.request(name, answersNothing: true)
                case .answersNothingAndAsks:
                    rig.request(name, answersNothing: true, inMint: { rig.request(name + "'") })
                case .asksInMint: rig.request(name, inMint: { rig.request(name + "'") })
                case .asksInLanding: rig.request(name, inLanding: { rig.request(name + "''") })
                case .cancelsInLanding: rig.request(name, inLanding: { rig.scheduler.cancel() })
                }
            }
            for step in 0..<40 {
                switch next(13) {
                case 0, 1: ask("p\(step)", .plain)
                case 2: ask("n\(step)", .answersNothing)
                case 3: ask("m\(step)", .asksInMint)
                case 4: ask("l\(step)", .asksInLanding)
                case 5: ask("c\(step)", .cancelsInLanding)
                case 6:
                    trace.append("cancel")
                    contract.cancel()
                    rig.scheduler.cancel()
                case 11: ask("s\(step)", .answersNothingAndAsks)
                case 7...8 where contract.inFlight != nil && !contract.workDone:
                    trace.append("work ends")
                    contract.workDone = true
                    rig.releaseWork()
                case 9...10 where contract.inFlight != nil && contract.workDone:
                    trace.append("landing arrives")
                    contract.land()
                    rig.deliverLandings()
                default: break
                }
                if rig.events != contract.events || rig.scheduler.isBusy != contract.isBusy || rig.peakInFlight > 1 {
                    return XCTFail("seed \(seed) diverged at step \(step): real \(rig.events), contract \(contract.events); "
                                   + "busy \(rig.scheduler.isBusy) vs \(contract.isBusy), peak \(rig.peakInFlight); trace \(trace)")
                }
            }
            while contract.isBusy {
                if contract.inFlight != nil, !contract.workDone { contract.workDone = true; rig.releaseWork() }
                contract.land()
                rig.deliverLandings()
            }
            XCTAssertFalse(rig.scheduler.isBusy, "seed \(seed): a request was left stranded (trace \(trace))")
            XCTAssertEqual(rig.events, contract.events, "seed \(seed): trace \(trace)")
        }
    }
}
