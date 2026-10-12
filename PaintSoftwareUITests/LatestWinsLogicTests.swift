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
}
