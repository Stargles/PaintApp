import XCTest

/// Pure-logic tests for `VersionRetention`, the age schedule that decides which saved versions of a
/// scene survive. No files, no clock: synthetic dates against a fixed `now`. `ProjectBackupManager`
/// applies the result to a folder on disk, and `BackupManagerLogicTests` covers that half.
/// `Services/VersionRetention.swift` is compiled directly into this test bundle (same pattern as
/// `ProjectBackupManager`), and is pure Foundation so that's possible.
final class VersionRetentionLogicTests: XCTestCase {

    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400

    /// Slots are multiples of their width since the epoch, so this instant has a known place in every
    /// one of them: 5½ minutes into its ten-minute slot, 45½ into its hour, 12¾ hours into its day
    /// and 3½ days into its week. A version's age, read against those, says which slot it is in.
    private lazy var now = Date(timeIntervalSince1970: 2960 * 7 * day + 3 * day + 12 * hour + 45 * minute + 30)

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func version(_ id: String, ago seconds: TimeInterval) -> VersionRetention.Version {
        VersionRetention.Version(id: id, date: ago(seconds))
    }

    /// Three versions made a moment ago, which take the always-kept places and nothing else.
    private lazy var newest = [version("n1", ago: 30), version("n2", ago: 20), version("n3", ago: 10)]

    private func kept(_ versions: [VersionRetention.Version]) -> Set<String> {
        VersionRetention.keep(versions, now: now)
    }

    // MARK: - The edges

    func testNothingToKeepWhenThereAreNoVersions() {
        XCTAssertEqual(kept([]), [])
    }

    /// The last restore point of a scene is never a candidate, however old it is.
    func testALoneVersionIsKeptHoweverOldItIs() {
        XCTAssertEqual(kept([version("only", ago: 400 * day)]), ["only"])
    }

    func testTheNewestThreeAreKeptWhateverTheirAgeAndSlot() {
        let old = (1...5).map { version("v\($0)", ago: 200 * day - TimeInterval($0) * 5) }
        XCTAssertEqual(kept(old), ["v3", "v4", "v5"], "three, and no more, outside every band")
    }

    /// A scene untouched for two months and then saved: the old history is not wiped for being old,
    /// it is only no longer protected by a band.
    func testAGapOfDaysLeavesTheNewestThreeAndDropsTheRest() {
        let versions = [version("now", ago: 0), version("a", ago: 60 * day), version("b", ago: 60 * day + hour),
                        version("c", ago: 60 * day + 2 * hour)]
        XCTAssertEqual(kept(versions), ["now", "a", "b"])
    }

    // MARK: - The bands, one at a time

    /// Each ten-minute slot of the last hour keeps its first version. Slot 0 began 5½ minutes ago,
    /// slot 1 15½, slot 2 25½.
    func testTheTenMinuteBandKeepsTheFirstVersionOfEachSlot() {
        let versions = newest + [
            version("c-first", ago: 5 * minute), version("c-last", ago: 1 * minute),        // slot 0
            version("b-first", ago: 15 * minute), version("b-last", ago: 14 * minute),      // slot 1
            version("a-first", ago: 25 * minute), version("a-last", ago: 24 * minute),      // slot 2
        ]
        XCTAssertEqual(kept(versions), ["n1", "n2", "n3", "c-first", "b-first", "a-first"])
    }

    /// Past the hour only the hourly band is left. The current hour began 45½ minutes ago.
    func testTheHourlyBandKeepsTheFirstVersionOfEachHour() {
        let versions = newest + [
            version("h1-first", ago: 90 * minute), version("h1-last", ago: 60 * minute),
            version("h2-first", ago: 150 * minute), version("h2-last", ago: 120 * minute),
        ]
        XCTAssertEqual(kept(versions), ["n1", "n2", "n3", "h1-first", "h2-first"])
    }

    /// Past the day only the daily band is left. Today began 12¾ hours ago.
    func testTheDailyBandKeepsTheFirstVersionOfEachDay() {
        let versions = newest + [
            version("d1-first", ago: 26 * hour), version("d1-last", ago: 25 * hour),
            version("d2-first", ago: 50 * hour), version("d2-last", ago: 40 * hour),
        ]
        XCTAssertEqual(kept(versions), ["n1", "n2", "n3", "d1-first", "d2-first"])
    }

    /// Past a week only the weekly band is left, and past four weeks nothing is. This week began
    /// 3½ days ago, so the previous one is days 3½ to 10½ back.
    func testTheWeeklyBandKeepsTheFirstVersionOfEachOfFourWeeksAndNoMore() {
        let versions = newest + [
            version("w1-first", ago: 9 * day), version("w1-last", ago: 8 * day),
            version("w2-first", ago: 15 * day), version("w2-last", ago: 12 * day),
            version("w3-first", ago: 23 * day), version("w3-last", ago: 20 * day),
            version("beyond", ago: 26 * day),
        ]
        XCTAssertEqual(kept(versions), ["n1", "n2", "n3", "w1-first", "w2-first", "w3-first"])
    }

    /// A slot starts on its boundary: the boundary second is in the slot it opens, and the second
    /// before it is in the one it closes. Slot 0 began exactly 5½ minutes ago.
    func testASlotOpensOnItsBoundary() {
        let versions = newest + [
            version("opens-slot-0", ago: 5.5 * minute),
            version("closes-slot-1", ago: 5.5 * minute + 1),
            version("opens-slot-1", ago: 15.5 * minute),
        ]
        XCTAssertEqual(kept(versions), ["n1", "n2", "n3", "opens-slot-0", "opens-slot-1"])
    }

    // MARK: - Bursts

    /// **The shape of 2026-10-10.** A build read the scene wrong and autosaved, and every launch
    /// stashed the previous, already-broken state: five versions in nine minutes. The first of them
    /// is the last good copy, and it must outlast the others — keeping the newest of a stretch
    /// instead would have dropped it on the fourth.
    func testTheFirstOfABurstOutlastsTheBadSavesAfterIt() {
        var versions = (1...5).map { version("day\($0)", ago: TimeInterval($0) * day + 3 * hour) }
        for step in 0..<6 {
            let date = now.addingTimeInterval(TimeInterval(step) * 108)
            versions.append(VersionRetention.Version(id: "burst\(step)", date: date))
            let survivors = VersionRetention.keep(versions, now: date)
            versions = versions.filter { survivors.contains($0.id) }
        }
        XCTAssertEqual(Set(versions.map(\.id)),
                       ["day1", "day2", "day3", "day4", "day5", "burst0", "burst3", "burst4", "burst5"],
                       "the good copy (burst0) and the newest three survive, the history before it is untouched, and burst1 and burst2 go")
    }

    /// Versions made in the same second still have an order, so the oldest of them is a definite one:
    /// collision counters sort numerically, not as text.
    func testVersionsOfOneInstantAreOrderedByTheirCounters() {
        let ids = ["auto-X", "auto-X-2", "auto-X-3", "auto-X-4", "auto-X-10"]
        let versions = ids.map { VersionRetention.Version(id: $0, date: ago(60)) }
        XCTAssertEqual(kept(versions), ["auto-X", "auto-X-3", "auto-X-4", "auto-X-10"],
                       "the first, and the last three by counter: -3, -4 and -10")
    }

    // MARK: - Dates that are wrong

    /// A version dated after `now` — a clock that was set forward when it was made — counts as now.
    /// Left in the future, each one would sit alone in a slot of its own and nothing would ever thin
    /// them; counted as now they share the current slots like any burst, and a genuine version
    /// beside them is untouched.
    func testVersionsFromTheFutureCountAsNowAndAreThinnedLikeAnyBurst() {
        let future = (1...20).map { VersionRetention.Version(id: "f\($0)", date: now.addingTimeInterval(TimeInterval($0) * hour)) }
        XCTAssertEqual(kept(future + [version("genuine", ago: 30 * minute)]), ["f1", "f18", "f19", "f20", "genuine"])
    }

    // MARK: - The whole schedule

    /// Applying the schedule again changes nothing.
    func testKeepingIsIdempotent() {
        var seed: UInt64 = 7
        func next() -> TimeInterval {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return TimeInterval(seed >> 33) / TimeInterval(1 << 31)
        }
        let versions = (0..<300).map { version("v\($0)", ago: next() * 40 * day) }
        let once = kept(versions)
        XCTAssertEqual(kept(versions.filter { once.contains($0.id) }), once)
        XCTAssertLessThan(once.count, versions.count)
    }

    /// A save every seven minutes for sixty days, thinned after each one the way the app does it:
    /// the count stays inside the schedule's 44 the whole way, and the survivors reach back through
    /// every band instead of piling up in the last few minutes.
    func testAStreamOfSavesStaysInsideTheScheduleAndReachesBackAMonth() {
        var live: [VersionRetention.Version] = []
        var most = 0
        var date = ago(60 * day)
        var number = 0
        while date <= now {
            live.append(VersionRetention.Version(id: "v\(number)", date: date))
            let survivors = VersionRetention.keep(live, now: date)
            live = live.filter { survivors.contains($0.id) }
            most = max(most, live.count)
            date = date.addingTimeInterval(7 * minute)
            number += 1
        }
        XCTAssertLessThanOrEqual(most, 44, "3 newest + 6 ten-minute + 24 hourly + 7 daily + 4 weekly")
        XCTAssertGreaterThanOrEqual(live.count, 36, "and a long-worked scene fills nearly all of it")
        let ages = live.map { now.timeIntervalSince($0.date) }
        XCTAssertGreaterThan(ages.max() ?? 0, 21 * day, "the oldest survivor is weeks back")
        XCTAssertLessThanOrEqual(ages.filter { $0 < hour }.count, 3 + 6, "the last hour holds the newest three and a version a slot")
    }
}
