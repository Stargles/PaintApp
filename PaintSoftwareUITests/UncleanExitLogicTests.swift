import XCTest
import SwiftUI

/// The crash catcher's decisions and files — `UncleanExitWatch`, the ring persistence in `ActionRecorder`
/// and `DiagnosticPayloadSink`'s writer — against temporary folders, never the app's own.
final class UncleanExitLogicTests: XCTestCase {

    private var root: URL!
    private var watch: UncleanExitWatch!
    private var recordings: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("unclean-\(UUID().uuidString)")
        watch = UncleanExitWatch(directory: root.appendingPathComponent("watch"))
        recordings = root.appendingPathComponent("Recordings")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func crashFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("crash-") }
    }

    // MARK: - The decision

    func testOnlyARunLastSeenInTheForegroundIsACrash() {
        XCTAssertTrue(UncleanExitWatch.endedUncleanly(lastMark: .foreground))
        XCTAssertFalse(UncleanExitWatch.endedUncleanly(lastMark: .away), "a suspended app iOS reclaims is not a crash")
        XCTAssertFalse(UncleanExitWatch.endedUncleanly(lastMark: nil), "a first launch is not a crash")
    }

    func testOnlyActiveAndBackgroundMoveTheMark() {
        XCTAssertEqual(UncleanExitWatch.mark(for: .active), .foreground)
        XCTAssertEqual(UncleanExitWatch.mark(for: .background), .away)
        XCTAssertNil(UncleanExitWatch.mark(for: .inactive), "a system sheet or the switcher says nothing about leaving")
    }

    func testTheMarkRoundTripsThroughItsFile() {
        XCTAssertNil(watch.lastMark())
        watch.write(.foreground)
        XCTAssertEqual(watch.lastMark()?.mark, .foreground)
        watch.write(.away)
        XCTAssertEqual(watch.lastMark()?.mark, .away)
    }

    // MARK: - The launch check

    func testALaunchAfterDeathInTheForegroundSavesACrashRecordingWithTheRing() throws {
        watch.write(.foreground, at: Date(timeIntervalSince1970: 1_000))
        try FileManager.default.createDirectory(at: watch.directory, withIntermediateDirectories: true)
        try Data("{\"t\":0,\"event\":\"header\"}\n{\"t\":1.5,\"event\":\"note\",\"text\":\"the last stroke\"}\n".utf8)
            .write(to: watch.ringURL)

        let url = try XCTUnwrap(watch.consumeLaunch(into: recordings))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("crash-"))
        XCTAssertEqual(url.pathExtension, "jsonl")
        let lines = try String(contentsOf: url).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3, "our header, then the ring's two lines")
        XCTAssertTrue(lines[0].contains("\"mode\":\"crash\""))
        XCTAssertTrue(lines[0].contains("ended while the app was in the foreground"))
        XCTAssertTrue(lines[2].contains("the last stroke"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: watch.ringURL.path), "the ring is consumed")
        XCTAssertEqual(watch.lastMark()?.mark, .away, "the same death is never reported twice")
        XCTAssertNil(watch.consumeLaunch(into: recordings))
        XCTAssertEqual(crashFiles().count, 1)
    }

    func testACrashBeforeAnyRingWasWrittenStillLeavesAReport() throws {
        watch.write(.foreground)
        let url = try XCTUnwrap(watch.consumeLaunch(into: recordings))
        XCTAssertEqual(try String(contentsOf: url).split(separator: "\n").count, 1)
    }

    func testALaunchAfterABackgroundEndReportsNothingAndDropsTheStaleRing() throws {
        watch.write(.away)
        try Data("stale\n".utf8).write(to: watch.ringURL)
        XCTAssertNil(watch.consumeLaunch(into: recordings))
        XCTAssertTrue(crashFiles().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: watch.ringURL.path))
    }

    func testAFirstLaunchReportsNothing() {
        XCTAssertNil(watch.consumeLaunch(into: recordings))
        XCTAssertTrue(crashFiles().isEmpty)
    }

    // MARK: - The ring on disk

    @MainActor
    func testThePersistedRingIsWrittenOnlyWhenEventsArrivedAndPromotesToTheCrashFile() throws {
        let recorder = ActionRecorder.shared
        let wasFlying = ActionRecorder.isFlying
        defer { ActionRecorder.isFlying = wasFlying }
        ActionRecorder.isFlying = true
        recorder.note("persisted-\(UUID().uuidString)")
        let marker = "after-the-last-persist-\(UUID().uuidString)"
        recorder.note(marker)

        func persist() {
            let done = expectation(description: "ring written")
            recorder.persistRing(to: watch.ringURL) { done.fulfill() }
            wait(for: [done], timeout: 5)
        }
        persist()
        let text = try String(contentsOf: watch.ringURL)
        XCTAssertTrue(text.contains(marker))
        XCTAssertTrue(text.hasPrefix("{\"t\":0,\"event\":\"header\""), "the ring file carries the build that wrote it")

        try FileManager.default.removeItem(at: watch.ringURL)
        persist()
        XCTAssertFalse(FileManager.default.fileExists(atPath: watch.ringURL.path), "nothing new, nothing written")

        recorder.note("one more")
        persist()
        XCTAssertTrue(FileManager.default.fileExists(atPath: watch.ringURL.path))

        watch.write(.foreground)
        let crash = try XCTUnwrap(watch.consumeLaunch(into: recordings))
        XCTAssertTrue(try String(contentsOf: crash).contains(marker), "the last 90 s survive into the crash file")
    }

    /// MEASURED, printed: what persisting a full ring costs. The main thread's share is the snapshot
    /// (the call itself); the rest runs on the watch's queue. A timing figure, so no gate here.
    @MainActor
    func testPersistRingCost() throws {
        let recorder = ActionRecorder.shared
        let wasFlying = ActionRecorder.isFlying
        defer { ActionRecorder.isFlying = wasFlying }
        ActionRecorder.isFlying = true
        for index in 0..<5000 { recorder.note("event \(index) with some ordinary text in it") }
        var mainMs: [Double] = [], totalMs: [Double] = []
        for round in 0..<5 {
            recorder.note("bump \(round)")
            let done = expectation(description: "written \(round)")
            let start = CACurrentMediaTime()
            recorder.persistRing(to: watch.ringURL) { done.fulfill() }
            mainMs.append((CACurrentMediaTime() - start) * 1000)
            wait(for: [done], timeout: 10)
            totalMs.append((CACurrentMediaTime() - start) * 1000)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: watch.ringURL.path)[.size] as? Int) ?? 0
        print("PERSIST-RING-COST main-thread ms \(mainMs.map { String(format: "%.2f", $0) }) end-to-end ms \(totalMs.map { String(format: "%.2f", $0) }) bytes \(size)")
    }

    // MARK: - MetricKit

    func testADiagnosticPayloadBecomesOneJSONLine() throws {
        let pretty = Data("{\n  \"crashDiagnostics\": [\n    {\"callStackTree\": {\"x\": 1}}\n  ]\n}".utf8)
        let url = try XCTUnwrap(DiagnosticPayloadSink.write(json: pretty, into: recordings, at: Date()))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("metrickit-"))
        XCTAssertEqual(url.pathExtension, "jsonl")
        let lines = try String(contentsOf: url).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertNil(DiagnosticPayloadSink.write(json: Data("not json".utf8), into: recordings, at: Date()))
    }
}
