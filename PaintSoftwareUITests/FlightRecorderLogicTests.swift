import XCTest

/// The flight recorder's two pure halves: `CanvasWedgeDetector`, replayed against real recordings of
/// the canvas freeze and of a healthy canvas, and `FlightRing`'s two bounds.
///
/// **The detector is tested against the evidence it was written from**, read off the repo's own
/// `docs/bug-evidence/` through `#filePath` — the same route `CanvasPresentationLogicTests` takes to
/// the app's source:
///
/// - `canvas-freeze-2026-09-23.jsonl` — the owner's recording of the frozen canvas, TODO (110),
///   verbatim. It starts after the wedge: every touch binds `canvas.touchCounter` and none of pan,
///   pinch or rotation.
/// - `canvas-freeze-sim-popover-wedge.jsonl` — the freeze reproduced on the simulator (a value layer,
///   a `.popover` up, a two-finger drag), touch lines only. It starts healthy, so it holds the
///   transition as well as the wedge.
/// - `canvas-freeze-sim-healthy.jsonl` — a healthy canvas that contains the one shape a naive rule
///   would fire on: a finger stroke, then a second finger landing on it, which binds none of the
///   three because the stroke's `.began` already failed them.
final class FlightRecorderLogicTests: XCTestCase {

    // MARK: - The detector, against the recordings

    func testTheDetectorTripsOnTheOwnersRecordingOfTheFrozenCanvas() throws {
        let trips = try replay("canvas-freeze-2026-09-23.jsonl")
        XCTAssertEqual(trips.count, 1, "the owner's frozen canvas must be detected, and exactly once")
        XCTAssertEqual(trips.first?.touch, 3, """
            The second touch sequence of the owner's recording is the proof — the first stranded \
            sequence alone is one observation — so the detector trips on touch 3, 0.96 s in.
            """)
    }

    func testTheDetectorTripsOnTheSimulatorWedgeAndNotBeforeIt() throws {
        let trips = try replay("canvas-freeze-sim-popover-wedge.jsonl")
        XCTAssertEqual(trips.count, 1, "the reproduced wedge must be detected, and exactly once")
        let transition = try XCTUnwrap(try lastSequenceStartBindingPan("canvas-freeze-sim-popover-wedge.jsonl"),
                                       "PREMISE: the fixture starts healthy — it holds the transition")
        XCTAssertGreaterThan(trips[0].time, transition, "it trips after the last healthy sequence, not during the healthy part")
    }

    func testTheDetectorStaysQuietOnAHealthyCanvasWhereASecondFingerJoinsAStroke() throws {
        let lines = try touchLines("canvas-freeze-sim-healthy.jsonl")
        XCTAssertTrue(lines.contains { $0.phase == "began" && !$0.startsSequence
                                        && $0.bound.contains(CanvasWedgeDetector.canvasMarker)
                                        && CanvasWedgeDetector.transformRecognizers.isDisjoint(with: $0.bound) },
                      "PREMISE: the fixture holds a joining finger bound to none of pan/pinch/rotation")
        XCTAssertEqual(try replay("canvas-freeze-sim-healthy.jsonl").count, 0,
                       "a healthy canvas must never be reported as wedged")
    }

    // MARK: - The detector's rule, stated

    /// Once per wedge, and a healthy sequence re-arms it: the owner may keep trying to pan for a
    /// minute, and that is one freeze and one file, not thirty.
    func testTheDetectorFiresOncePerWedgeAndRearmsOnAHealthySequence() {
        var detector = CanvasWedgeDetector()
        let stranded = ["canvas.touchCounter", "_UISystemGestureGateGestureRecognizer"]
        let healthy = stranded + ["canvas.pan", "canvas.pinch", "canvas.rotation"]

        XCTAssertFalse(detector.touchBegan(startsSequence: true, boundRecognizers: stranded), "one stranded sequence is one observation")
        XCTAssertTrue(detector.touchBegan(startsSequence: true, boundRecognizers: stranded), "the second trips it")
        XCTAssertFalse(detector.touchBegan(startsSequence: true, boundRecognizers: stranded), "…once")
        XCTAssertFalse(detector.touchBegan(startsSequence: true, boundRecognizers: healthy), "a healthy sequence re-arms it")
        XCTAssertFalse(detector.touchBegan(startsSequence: true, boundRecognizers: stranded))
        XCTAssertTrue(detector.touchBegan(startsSequence: true, boundRecognizers: stranded), "and the next wedge is a new one")
    }

    /// A touch off the canvas host, or one that joins a sequence already running, is no evidence
    /// either way — neither counts, neither re-arms.
    func testTouchesThatDoNotStartACanvasSequenceAreIgnored() {
        var detector = CanvasWedgeDetector()
        let stranded = ["canvas.touchCounter"]
        XCTAssertFalse(detector.touchBegan(startsSequence: true, boundRecognizers: stranded))
        XCTAssertFalse(detector.touchBegan(startsSequence: false, boundRecognizers: stranded), "a joining finger does not count")
        XCTAssertFalse(detector.touchBegan(startsSequence: true, boundRecognizers: ["UIScrollViewPanGestureRecognizer"]),
                       "a touch on the timeline does not count")
        XCTAssertEqual(detector.strandedSequences, 1, "…and neither re-armed it")
        XCTAssertTrue(detector.touchBegan(startsSequence: true, boundRecognizers: stranded))
    }

    // MARK: - The ring

    func testTheRingKeepsOnlyTheWindowAndNeverMoreThanItsCapacity() {
        var ring = FlightRing<Int>(capacity: 4, window: 90)
        for second in 0..<6 { ring.append(second, at: Double(second) * 30) }
        // Six appended into four slots: 0 and 1 are overwritten. At t = 150 the window reaches back to
        // exactly 60, so 2 is kept at its edge; a second later it is not.
        XCTAssertEqual(ring.elements(asOf: 150).map(\.element), [2, 3, 4, 5])
        XCTAssertEqual(ring.elements(asOf: 151).map(\.element), [3, 4, 5], "older than the window is dropped")
        XCTAssertEqual(ring.count, 4, "the capacity is the other bound")
    }

    func testAnEmptyRingReadsEmpty() {
        XCTAssertTrue(FlightRing<Int>(capacity: 8, window: 90).elements(asOf: 0).isEmpty)
    }

    // MARK: - Replaying a recording

    private struct TouchLine {
        let time: Double
        let touch: Int
        let phase: String
        let startsSequence: Bool
        let bound: Set<String>
    }

    /// The detector's trips over a recording, as (touch id, time).
    private func replay(_ fixture: String) throws -> [(touch: Int, time: Double)] {
        var detector = CanvasWedgeDetector()
        return try touchLines(fixture).compactMap { line in
            guard line.phase == "began",
                  detector.touchBegan(startsSequence: line.startsSequence, boundRecognizers: Array(line.bound)) else { return nil }
            return (line.touch, line.time)
        }
    }

    private func lastSequenceStartBindingPan(_ fixture: String) throws -> Double? {
        try touchLines(fixture).last { $0.phase == "began" && $0.startsSequence && $0.bound.contains("canvas.pan") }?.time
    }

    /// Every touch line, with whether a `began` started a sequence reconstructed the way the live
    /// tap decides it: nothing else was down when it landed.
    private func touchLines(_ fixture: String) throws -> [TouchLine] {
        let url = try evidence(fixture)
        var down: Set<Int> = []
        var lines: [TouchLine] = []
        for raw in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
            guard let object, object["event"] as? String == "touch",
                  let phase = object["phase"] as? String, let touch = object["touch"] as? Int,
                  let time = object["t"] as? Double else { continue }
            let bound = Set((object["grNames"] as? String)?.split(separator: ",").map(String.init) ?? [])
            let starts = phase == "began" && down.isEmpty
            if phase == "began" { down.insert(touch) } else if phase == "ended" || phase == "cancelled" { down.remove(touch) }
            lines.append(TouchLine(time: time, touch: touch, phase: phase, startsSequence: starts, bound: bound))
        }
        XCTAssertFalse(lines.isEmpty, "\(fixture) has no touch lines — the replay would pass for reading nothing")
        return lines
    }

    private func evidence(_ fixture: String) throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/bug-evidence/\(fixture)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(url.path) is not readable from here — expected only on a physical device")
        }
        return url
    }
}
