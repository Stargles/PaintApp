import XCTest

/// **SCHEDULER.md's rules, walked on a virtual executor** (SCHEDULER_DESIGN.md §2, "Testing"): the touch
/// flag, the lanes on several machines, latest-wins, cancellation and the answer deadline — and a
/// 2,000-step random storm that holds every rule at once.
final class SchedulerLogicTests: XCTestCase {

    private var executor: VirtualExecutor!
    private var scheduler: Scheduler!

    private func make(fast: Int = 2, efficient: Int = 4) {
        executor = VirtualExecutor()
        scheduler = Scheduler(executor: executor, machine: VirtualExecutor.Machine(fastCores: fast, efficientCores: efficient))
    }

    override func setUp() {
        super.setUp()
        make()
    }

    private func job(_ key: JobKey, _ jobClass: JobClass, visible: Bool = false,
                     work: @escaping (JobContext) throws -> Int = { _ in 1 }, land: @escaping (Int) -> Void = { _ in }) -> Job<Int> {
        Job(key: key, jobClass: jobClass, name: "\(key.owner)", visible: visible, work: work, land: land)
    }

    // MARK: - The touch flag (rule 3)

    func testTheFlagHoldsWhileATouchIsDownAndForTheSettleAfter() {
        var flag = TouchFlag()
        XCTAssertFalse(flag.isHeld(at: 0), "never touched: nothing held")
        flag.touches(1, at: 10)
        XCTAssertTrue(flag.isHeld(at: 15), "a touch held 5 s holds")
        flag.touches(0, at: 16)
        XCTAssertTrue(flag.isHeld(at: 16 + TouchFlag.settle - 0.05), "inside the settle")
        XCTAssertFalse(flag.isHeld(at: 16 + TouchFlag.settle + 0.05), "past the settle")
        XCTAssertEqual(flag.releases(after: 16), 16 + TouchFlag.settle)
    }

    func testAStrandedCountStopsHoldingAfterTenSeconds() {
        var flag = TouchFlag()
        flag.touches(2, at: 0)
        XCTAssertTrue(flag.isHeld(at: TouchFlag.stuckAfter - 0.5))
        XCTAssertFalse(flag.isHeld(at: TouchFlag.stuckAfter + 0.5), "a count unchanged for 10 s is a missed end")
    }

    // MARK: - The answer is never held by the touch that asked for it

    func testAnAnswerStartsWhileTheTouchThatAskedForItIsDown() {
        scheduler.touches(1)
        var landed = 0
        scheduler.submit(job(JobKey("frame"), .answer, land: { _ in landed += 1 }))
        XCTAssertEqual(executor.workers.count, 1, "R1 starts at once under a touch (a step's read waited 250–500 ms for its own tap)")
        executor.runWorker()
        executor.drainMain()
        XCTAssertEqual(landed, 1)
    }

    func testLaterWorkWaitsForTheTouchToSettleAndThenStartsOnItsOwn() {
        scheduler.touches(1)
        scheduler.submit(job(JobKey("bake"), .later))
        XCTAssertTrue(executor.workers.isEmpty, "R3 does not start under a touch")
        scheduler.touches(0)
        XCTAssertTrue(executor.workers.isEmpty, "nor in the settle after it")
        executor.advance(TouchFlag.settle + 0.01)
        XCTAssertEqual(executor.workers.map(\.jobClass), [.later], "the settle's end starts it with no other prompt")
    }

    func testUnderATouchOnlyVisibleSoonWorkRuns() {
        scheduler.touches(1)
        scheduler.submit(job(JobKey("prefetch"), .soon))
        scheduler.submit(job(JobKey("thumbnail on screen"), .soon, visible: true))
        XCTAssertEqual(executor.workers.count, 1, "the visible R2 job alone")
        scheduler.touches(0)
        executor.advance(TouchFlag.settle + 0.01)
        XCTAssertEqual(executor.workers.count, 2, "the other once the hand is off")
    }

    func testARunningLaterJobParksAtItsCheckpointUntilTheTouchSettles() {
        var passed = 0
        scheduler.submit(job(JobKey("bake"), .later, work: { context in
            try context.checkpoint(); passed += 1
            self.scheduler.touches(1)
            self.scheduler.touches(0)
            let parkedFrom = self.executor.now
            try context.checkpoint(); passed += 1
            XCTAssertGreaterThanOrEqual(self.executor.now - parkedFrom, TouchFlag.settle - Scheduler.parkInterval,
                                        "parked through the settle")
            return passed
        }))
        executor.runWorker()
        XCTAssertEqual(passed, 2)
    }

    // MARK: - Latest wins (rule 4)

    func testANewerJobOfTheSameKeyCancelsTheOneRunningAndOnlyTheNewerLands() {
        var landed: [Int] = []
        scheduler.submit(job(JobKey("frame"), .answer, work: { _ in 1 }, land: { landed.append($0) }))
        XCTAssertEqual(executor.workers.count, 1)
        scheduler.submit(job(JobKey("frame"), .answer, work: { _ in 2 }, land: { landed.append($0) }))
        XCTAssertEqual(executor.workers.count, 1, "one answer at a time: the newer waits for a slot")
        executor.runWorker()
        executor.drainMain()
        XCTAssertEqual(executor.workers.count, 1, "the slot freed starts the newer")
        executor.runWorker()
        executor.drainMain()
        XCTAssertEqual(landed, [2], "the older's landing is dropped: a stale frame never reaches the screen")
        XCTAssertEqual(scheduler.stats.cancelled, 1)
    }

    func testAWaitingJobReplacedByANewerOneNeverStarts() {
        scheduler.touches(1)
        var ran: [Int] = []
        scheduler.submit(job(JobKey("prefetch"), .soon, work: { _ in ran.append(1); return 1 }))
        scheduler.submit(job(JobKey("prefetch"), .soon, work: { _ in ran.append(2); return 2 }))
        scheduler.touches(0)
        executor.advance(1)
        while !executor.workers.isEmpty { executor.runWorker() }
        XCTAssertEqual(ran, [2])
    }

    func testACancelledJobStopsAtItsNextCheckpoint() {
        var reached = 0
        let token = scheduler.submit(job(JobKey("walk"), .answer, work: { context in
            for _ in 0..<10 {
                try context.checkpoint()
                reached += 1
                if reached == 3 { self.scheduler.cancel(key: JobKey("walk")) }
            }
            return reached
        }, land: { _ in XCTFail("a cancelled job never lands") }))
        executor.runWorker()
        executor.drainMain()
        XCTAssertEqual(reached, 3)
        XCTAssertTrue(token.isCancelled)
    }

    // MARK: - Lanes by machine (rule 6)

    func testLanesFollowTheMachine() {
        for (fast, efficient) in [(1, 0), (2, 4), (4, 4), (8, 0)] {
            let machine = VirtualExecutor.Machine(fastCores: fast, efficientCores: efficient)
            XCTAssertEqual(LanePolicy.capacity(of: .answer, touchHeld: true, answersRunning: 0, machine: machine), 1)
            XCTAssertEqual(LanePolicy.capacity(of: .later, touchHeld: true, answersRunning: 0, machine: machine), 0)
            XCTAssertEqual(LanePolicy.capacity(of: .later, touchHeld: false, answersRunning: 1, machine: machine), 1)
            XCTAssertEqual(LanePolicy.capacity(of: .later, touchHeld: false, answersRunning: 0, machine: machine),
                           max(1, fast + efficient - 1), "idle: every core but one, on \(fast)+\(efficient)")
            XCTAssertEqual(LanePolicy.capacity(of: .soon, touchHeld: true, answersRunning: 0, machine: machine), 1)
            XCTAssertEqual(LanePolicy.capacity(of: .soon, touchHeld: false, answersRunning: 0, machine: machine), 2)
        }
    }

    func testIdleLaterWorkFillsAllButOneCore() {
        make(fast: 2, efficient: 4)
        for index in 0..<8 { scheduler.submit(job(JobKey("bake", index), .later)) }
        XCTAssertEqual(executor.workers.count, 5, "the minimum machine: one core left for the pencil")
    }

    // MARK: - The deadline (rule 8)

    func testALateAnswerIsCountedAndStillLands() {
        var landed = false
        scheduler.submit(job(JobKey("frame"), .answer, land: { _ in landed = true }))
        executor.advance(0.15)
        executor.runWorker()
        executor.drainMain()
        XCTAssertTrue(landed, "late is a count, never a refusal")
        XCTAssertEqual(scheduler.stats.lateAnswers, 1)
        XCTAssertEqual(scheduler.stats.lastAnswer?.waitedMs, 150)
    }

    // MARK: - The storm

    func testAStormOfJobsTouchesAndTimeHoldsEveryRule() {
        for machine in [(1, 0), (2, 4), (4, 4), (8, 0)] {
            make(fast: machine.0, efficient: machine.1)
            var random = SplitMix(seed: UInt64(machine.0 * 10 + machine.1))
            var touches = 0
            var landings: [Int: Int] = [:]
            var superseded = Set<Int>()
            var newestByKey: [JobKey: Int] = [:]
            var submitted = 0
            executor.onStart = { [unowned self] jobClass in
                if jobClass == .later { XCTAssertFalse(self.scheduler.touchHeld, "no R3 starts with a touch down") }
            }
            for _ in 0..<2000 {
                switch random.next() % 6 {
                case 0, 1:
                    let id = submitted
                    submitted += 1
                    let key = JobKey("k", Int(random.next() % 4))
                    if let older = newestByKey[key] { superseded.insert(older) }
                    newestByKey[key] = id
                    let jobClass = JobClass(rawValue: Int(random.next() % 3))!
                    scheduler.submit(Job(key: key, jobClass: jobClass, name: "storm", visible: random.next() % 2 == 0,
                                         work: { context in try context.checkpoint(); return id },
                                         land: { landed in
                                             XCTAssertFalse(superseded.contains(landed), "a cancelled job never lands")
                                             landings[landed, default: 0] += 1 }))
                case 2:
                    touches = touches == 0 ? Int(1 + random.next() % 2) : 0
                    scheduler.touches(touches)
                case 3:
                    executor.advance(Double(random.next() % 300) / 1000)
                default:
                    if !executor.workers.isEmpty { executor.runWorker(Int(random.next() % UInt64(executor.workers.count))) }
                    executor.drainMain()
                }
            }
            scheduler.touches(0)
            for _ in 0..<500 {
                executor.advance(0.5)
                while !executor.workers.isEmpty { executor.runWorker(); executor.drainMain() }
            }
            XCTAssertTrue(landings.values.allSatisfy { $0 == 1 }, "at most one landing per job")
            let unfinished = (0..<submitted).filter { landings[$0] == nil && !superseded.contains($0) }
            XCTAssertEqual(unfinished, [], "every job lands or is cancelled, on \(machine.0)+\(machine.1)")
        }
    }
}

/// A seeded generator, so a storm that fails fails the same way again.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
