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

    // MARK: - What the repair finds not at rest

    /// A recognizer a test can leave anywhere: `state` is writable only from inside a subclass, and
    /// `numberOfTouches` — what UIKit says it is still tracking — can only be moved by real touches,
    /// so it is overridden.
    private final class Driven: UIGestureRecognizer {
        var held = 0
        override var numberOfTouches: Int { held }
        func settle(in state: UIGestureRecognizer.State) { self.state = state }
    }

    /// The stranded canvas's flight file names what was replaced; this is what it adds — every
    /// recognizer under the window out of `.possible` or still holding a touch, wherever in the tree
    /// it hangs, named by what the file already calls it.
    func testTheCensusListsEveryRecognizerNotAtRestAndNoneAtRest() {
        let window = UIView()
        let canvas = UIView()
        window.addSubview(canvas)
        let pan = Driven(target: nil, action: nil)
        pan.name = "canvas.pan"
        canvas.addGestureRecognizer(pan)
        let gate = Driven(target: nil, action: nil)
        window.addGestureRecognizer(gate)
        let pinch = Driven(target: nil, action: nil)
        pinch.name = "canvas.pinch"
        canvas.addGestureRecognizer(pinch)

        XCTAssertEqual(WindowEventTap.unquietRecognizers(under: window), [], "PREMISE: nothing is out of place yet")

        pan.settle(in: .began)
        gate.settle(in: .ended)
        let census = WindowEventTap.unquietRecognizers(under: window)
        XCTAssertEqual(census.count, 2, "the one on the subview and the one on the root, not the resting pinch: \(census)")
        XCTAssertTrue(census.contains("canvas.pan began touches:0 on UIView"), "\(census)")
        XCTAssertTrue(census.contains("Driven ended touches:0 on UIView"),
                      "an unnamed recognizer is known by its class, as everywhere else in the file: \(census)")
    }

    /// A recognizer UIKit has back in `.possible` but believes is still being touched is the other
    /// way a canvas gets stuck, and the only one `numberOfTouches` shows.
    func testTheCensusListsARecognizerAtRestThatStillCountsATouch() {
        let view = UIView()
        let counting = Driven(target: nil, action: nil)
        counting.name = "canvas.pinch"
        counting.held = 2
        view.addGestureRecognizer(counting)
        XCTAssertEqual(WindowEventTap.unquietRecognizers(under: view), ["canvas.pinch possible touches:2 on UIView"])
    }

    // MARK: - What a stranded canvas's flight carries (BUGS.md, "The canvas's recognizers strand…")

    private func touchSample(phase: String, touchID: Int, object: AnyObject, moves: Int?) -> TouchSample {
        TouchSample(time: 1, phase: phase, type: "direct", touchID: touchID, object: ObjectIdentifier(object), moves: moves,
                    target: nil, targetClass: "none", hitClass: "StrokeCanvasView", role: "other", label: nil,
                    depth: 0, resolution: "none", normalized: .zero, window: .zero, windowNormalized: .zero,
                    concurrent: 1, isPencil: false, force: 0, maxForce: 0, altitude: 0, azimuth: 0,
                    coalescedAway: nil, touchViewClass: nil, boundRecognizers: nil)
    }

    /// A line as the recorder encodes it and a reader parses it — the encoder under test, not a
    /// restatement of its field list.
    private func parsed(_ event: String, _ fields: [(String, ActionRecorder.JSONValue)]) throws -> [String: Any] {
        let line = ActionRecorder.line(event, fields, at: 1.5)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], line)
    }

    /// **`moves` is on the line a touch ends or is cancelled on, and only there** — it is a total, and
    /// a total on a `began` or a `moved` would be a count of nothing yet.
    func testOnlyAnEndedOrCancelledTouchLineCarriesItsMoves() throws {
        let touch = NSObject()
        for phase in ["began", "moved"] {
            let line = try parsed("touch", ActionRecorder.touchFields(touchSample(phase: phase, touchID: 4, object: touch, moves: nil)))
            XCTAssertNil(line["moves"], "a \(phase) line has no move count")
        }
        for phase in ["ended", "cancelled"] {
            let line = try parsed("touch", ActionRecorder.touchFields(touchSample(phase: phase, touchID: 4, object: touch, moves: 7)))
            XCTAssertEqual(line["moves"] as? Int, 7, "a \(phase) line carries the touch's total")
        }
        let still = try parsed("touch", ActionRecorder.touchFields(touchSample(phase: "ended", touchID: 5, object: touch, moves: 0)))
        XCTAssertEqual(still["moves"] as? Int, 0, "a touch that never moved says so — 0 is an answer, absence is not")
    }

    /// **`touch` numbers sequences and `uid` is the `UITouch` object**, so the pair says what neither
    /// does alone: one object under two sequence numbers is UIKit handing a touch back (the cancel and
    /// reissue shape, H7); two objects under one reader's eye are two fingers.
    func testTheTouchObjectsIdentityIsOnEveryLineAndSeparatesObjectFromSequence() throws {
        let one = NSObject(), another = NSObject()
        let first = try parsed("touch", ActionRecorder.touchFields(touchSample(phase: "cancelled", touchID: 370, object: one, moves: 0)))
        let reissued = try parsed("touch", ActionRecorder.touchFields(touchSample(phase: "began", touchID: 372, object: one, moves: nil)))
        let other = try parsed("touch", ActionRecorder.touchFields(touchSample(phase: "began", touchID: 371, object: another, moves: nil)))

        XCTAssertEqual(first["uid"] as? String, ActionRecorder.shortObject(ObjectIdentifier(one)))
        XCTAssertEqual(first["uid"] as? String, reissued["uid"] as? String, "one object, two sequences, one uid")
        XCTAssertNotEqual(first["touch"] as? Int, reissued["touch"] as? Int, "…and two sequence numbers")
        XCTAssertNotEqual(first["uid"] as? String, other["uid"] as? String, "another object is another uid")
    }

    /// The count is on the line only for a recognizer the file follows the touches of; the line of a
    /// touch count moving on its own is the same state on both sides.
    func testARecognizerLineCarriesTheTouchesItWasAskedFor() throws {
        let recognizer = NSObject()
        let counted = try parsed("recognizer", ActionRecorder.recognizerFields(
            name: "canvas.pan", object: ObjectIdentifier(recognizer), from: .failed, to: .failed, source: "sweep:e", touches: 0))
        XCTAssertEqual(counted["touches"] as? Int, 0, "0 is the finding that matters: failed, and nothing left to wait for")
        XCTAssertEqual(counted["from"] as? String, "failed")
        XCTAssertEqual(counted["to"] as? String, "failed")
        XCTAssertEqual(counted["src"] as? String, "sweep:e")

        let uncounted = try parsed("recognizer", ActionRecorder.recognizerFields(
            name: "canvas.twoFingerTap", object: ObjectIdentifier(recognizer), from: .possible, to: .failed, source: "sweep:b", touches: nil))
        XCTAssertNil(uncounted["touches"], "a recognizer the file does not follow has no count on its line")
    }

    /// **Every flight header names the repair count**, so two flights from two builds set side by side
    /// say how often each build had caught a freeze by then — and a recording's header too, since the
    /// count is a fact about the build and not about the trigger.
    func testEveryHeaderCarriesTheRepairCount() throws {
        let url = URL(fileURLWithPath: "/tmp/flight-test.jsonl")
        let flight = try headerFields(
            ActionRecorder.headerLine(canvasSize: nil, projectName: "T", tap: nil, url: url, freezesCaught: 12,
                                      flight: [("trigger", .str("stranded"))]))
        XCTAssertEqual(flight["canvasFreezesCaught"] as? Int, 12)
        XCTAssertEqual(flight["mode"] as? String, "flight")

        let recording = try headerFields(ActionRecorder.headerLine(canvasSize: nil, projectName: "T", tap: nil, url: url, freezesCaught: 0))
        XCTAssertEqual(recording["canvasFreezesCaught"] as? Int, 0, "a build that has caught none says 0, not nothing")
    }

    private func headerFields(_ line: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], line)
    }

    // MARK: - The sweep says which event it followed, and follows touches

    func testASweepIsTaggedWithTheLettersOfTheTouchPhasesTheEventCarried() {
        typealias Phases = WindowEventTap.EventPhases
        XCTAssertEqual(Phases.began.tag, "b")
        XCTAssertEqual(Phases.ended.tag, "e")
        XCTAssertEqual(Phases([.began, .ended]).tag, "be", "an event that began one touch and ended another")
        XCTAssertEqual(Phases([.cancelled, .moved, .began]).tag, "bmc", "always in the order b, m, e, c")
        XCTAssertEqual(Phases(UITouch.Phase.stationary), [], "a resting finger is no phase to tag by")
        XCTAssertEqual(Phases(UITouch.Phase.moved), .moved)
    }

    func testTheFileFollowsTheTouchesOfTheTransformRecognizersAndTheStrokeRecognizersOnly() {
        for name in ["canvas.pan", "canvas.pinch", "canvas.rotation", "stroke.66A8F2C1"] {
            XCTAssertTrue(WindowEventTap.followsTouchCount(named: name), name)
        }
        for name in ["canvas.twoFingerTap", "canvas.threeFingerTap", "canvas.touchCounter", "canvas.fillPress", "timeline.rulerScrub"] {
            XCTAssertFalse(WindowEventTap.followsTouchCount(named: name), name)
        }
    }

    /// **What a sweep writes about a followed recognizer, through the real tap, the ring and a saved
    /// file**: its state change with the touches UIKit says it holds, and — the finding a stranded
    /// pan's flight needs, *failed holding two touches* against *ended holding none* — the count moving
    /// on its own, in the sweep of the event it dropped in. A recognizer the file does not follow gets
    /// its state change without a count, and nothing for its touches. A sweep that finds nothing new
    /// writes nothing.
    ///
    /// The two are named for this test rather than `canvas.pan` and `canvas.twoFingerTap`: the ring is
    /// the recorder's own and holds whatever an earlier test left in it, so a line is this test's by
    /// its name. `followsTouchCount`'s table is the test above. (`Driven` is settled in `.began` and
    /// `.ended`: UIKit puts a recognizer set to `.failed` with no real touch behind it straight back
    /// to `.possible`.)
    func testASweepWritesAFollowedRecognizersStateWithItsTouchesAndTheCountMovingOnItsOwn() throws {
        guard let window = WindowEventTap.activeWindow() else { throw XCTSkip("no window in the test process to install the tap on") }
        let canvas = UIView(frame: window.bounds)
        let followed = Driven(target: nil, action: nil)
        followed.name = "stroke.sweeptest"
        let unfollowed = Driven(target: nil, action: nil)
        unfollowed.name = "canvas.sweeptest.tap"
        canvas.addGestureRecognizer(followed)
        canvas.addGestureRecognizer(unfollowed)
        window.addSubview(canvas)

        let tap = WindowEventTap()
        let wasFlying = ActionRecorder.isFlying
        defer {
            tap.uninstall()
            canvas.removeFromSuperview()
            ActionRecorder.isFlying = wasFlying
        }
        guard tap.install().interceptedClass != nil else { throw XCTSkip("the tap could not intercept this window") }
        ActionRecorder.isFlying = true

        followed.held = 2
        followed.settle(in: .began)
        unfollowed.settle(in: .began)
        tap.sweepRecognizerStates(after: .began)      // both begin; the followed one holds two touches
        followed.held = 1
        tap.sweepRecognizerStates(after: .ended)      // one finger lifts: the count moves, the state does not
        followed.held = 0
        followed.settle(in: .ended)
        unfollowed.held = 3
        tap.sweepRecognizerStates(after: [.ended, .cancelled])   // the last lift: the state moves with the count
        tap.sweepRecognizerStates(after: .ended)      // nothing changed: nothing written

        let lines = try savedFlightLines().filter { $0["event"] as? String == "recognizer" }
        let followedLines = lines.filter { $0["name"] as? String == "stroke.sweeptest" }
        let unfollowedLines = lines.filter { $0["name"] as? String == "canvas.sweeptest.tap" }

        func summary(_ line: [String: Any]) -> String {
            "\(line["from"] ?? "?")>\(line["to"] ?? "?") \(line["src"] ?? "?") touches:\(line["touches"] ?? "-")"
        }
        XCTAssertEqual(followedLines.map(summary), [
            "possible>began sweep:b touches:2",
            "began>began sweep:e touches:1",
            "began>ended sweep:ec touches:0",
        ], "state and touches while the state moves, the touches alone when only they move, and no fourth line for the quiet sweep")

        XCTAssertEqual(unfollowedLines.map(summary), ["possible>began sweep:b touches:-"],
                       "a recognizer the file does not follow: its state change, no count, and nothing when only its touches moved")
    }

    /// Saves the flight ring the way the Settings row does and reads the file back — its header is
    /// checked on the way, because the header is the other half of what a stranded flight carries.
    private func savedFlightLines() throws -> [[String: Any]] {
        let saved = try XCTUnwrap(ActionRecorder.shared.saveFlight(trigger: "test"))
        addTeardownBlock { try? FileManager.default.removeItem(at: saved) }
        let written = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: saved.path) },
                                  evaluatedWith: saved)
        wait(for: [written], timeout: 5)
        let text = try String(contentsOf: saved, encoding: .utf8)
        let lines = try text.split(separator: "\n").map {
            try XCTUnwrap(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any], String($0))
        }
        XCTAssertEqual(lines.first?["canvasFreezesCaught"] as? Int, AppSettings.standard.canvasRepairCount,
                       "the saved flight's header names the repair count of the moment")
        XCTAssertEqual(lines.first?["trigger"] as? String, "test")
        return lines
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
