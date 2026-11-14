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

    func testSharedRecordingFilenameIsUniqueAtOneWallClockInstantForBothPrefixes() {
        let date = Date(timeIntervalSinceReferenceDate: 1_234)
        for prefix in ["flight", "recording"] {
            let first = ActionRecorder.recordingFilename(prefix: prefix, at: date)
            let second = ActionRecorder.recordingFilename(prefix: prefix, at: date)
            XCTAssertNotEqual(first, second)
            XCTAssertEqual(first.dropLast(43), second.dropLast(43), "same prefix and exact wall-clock timestamp")
            XCTAssertTrue(first.hasPrefix(prefix + "-"))
            XCTAssertTrue(first.hasSuffix(".jsonl"))
            XCTAssertNotNil(UUID(uuidString: String(first.dropLast(6).suffix(36))))
            XCTAssertNotNil(UUID(uuidString: String(second.dropLast(6).suffix(36))))
        }
    }

    @MainActor
    func testSuccessiveFlightSavesPreserveBothFilesAndContents() throws {
        let recorder = ActionRecorder.shared
        var created: [URL] = []
        defer { for url in created { try? FileManager.default.removeItem(at: url) }; recorder.refreshRecordings() }
        let first = try XCTUnwrap(recorder.saveFlight(trigger: "filename-first"))
        created.append(first)
        let firstBytes = try recordingBytes(at: first, containing: "filename-first")
        let second = try XCTUnwrap(recorder.saveFlight(trigger: "filename-second"))
        created.append(second)
        let secondBytes = try recordingBytes(at: second, containing: "filename-second")
        XCTAssertNotEqual(first, second, "successive flight dumps have distinct identities")
        XCTAssertEqual(try Data(contentsOf: first), firstBytes, "the second save cannot replace the first diagnostic")
        XCTAssertNotEqual(firstBytes, secondBytes)
        XCTAssertTrue(String(decoding: firstBytes, as: UTF8.self).contains("filename-first"))
        XCTAssertTrue(String(decoding: secondBytes, as: UTF8.self).contains("filename-second"))
        XCTAssertTrue(first.lastPathComponent.hasPrefix("flight-"))
        XCTAssertEqual(first.pathExtension, "jsonl")
    }

    @MainActor
    func testSuccessiveActionRecordingsPreserveBothFilesAndContents() throws {
        let recorder = ActionRecorder.shared
        try XCTSkipIf(recorder.isRecording, "an existing recording owns the recorder")
        recorder.refreshRecordings()
        var known = Set(recorder.recordings.map(\.url))
        var created: [URL] = []
        defer { recorder.stop(); for url in created { try? FileManager.default.removeItem(at: url) }; recorder.refreshRecordings() }
        var saved: [Data] = []
        for name in ["filename-first-take", "filename-second-take"] {
            recorder.start(canvasSize: CGSize(width: 64, height: 64), projectName: name)
            XCTAssertTrue(recorder.isRecording)
            recorder.note(name)
            recorder.stop()
            recorder.refreshRecordings()
            let fresh = Set(recorder.recordings.map(\.url)).subtracting(known)
            XCTAssertEqual(fresh.count, 1, "each actual start/stop creates a new file")
            let url = try XCTUnwrap(fresh.first)
            created.append(url)
            known.insert(url)
            let bytes = try recordingBytes(at: url, containing: "recordingStopped")
            saved.append(bytes)
            XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains(name))
            XCTAssertTrue(url.lastPathComponent.hasPrefix("recording-"))
            XCTAssertEqual(url.pathExtension, "jsonl")
        }
        XCTAssertEqual(created.count, 2)
        XCTAssertNotEqual(created[0], created[1])
        XCTAssertEqual(try Data(contentsOf: created[0]), saved[0], "starting another take cannot truncate the earlier one")
        XCTAssertNotEqual(saved[0], saved[1])
    }

    /// Wait for the existing asynchronous writer's terminal content, rather than mistaking file
    /// existence (created before its first flush) for a completed recording.
    @MainActor
    private func recordingBytes(at url: URL, containing marker: String) throws -> Data {
        let ready = expectation(for: NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: url) else { return false }
            return String(decoding: data, as: UTF8.self).contains(marker)
        }, evaluatedWith: url)
        wait(for: [ready], timeout: 10)
        return try Data(contentsOf: url)
    }

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

    private func touchSample(phase: String, touchID: Int, object: AnyObject, moves: Int? = nil,
                             time: Double = 1, point: CGPoint = .zero, down: Int = 1, bound: [String]? = nil,
                             type: String = "direct") -> TouchSample {
        TouchSample(time: time, phase: phase, type: type, touchID: touchID, object: ObjectIdentifier(object), moves: moves,
                    target: nil, targetClass: "none", hitClass: "StrokeCanvasView", role: "other", label: nil,
                    depth: 0, resolution: "none", normalized: .zero, window: point, windowNormalized: .zero,
                    concurrent: down, isPencil: false, force: 0, maxForce: 0, altitude: 0, azimuth: 0,
                    coalescedAway: nil, touchViewClass: nil, boundRecognizers: bound)
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

    // MARK: - Automatic navigation evidence

    @MainActor
    func testNavigationSnapshotReadsCurrentTransformAndRecognizerAttachment() throws {
        let recorder = ActionRecorder.shared
        let wasFlying = ActionRecorder.isFlying
        defer { ActionRecorder.isFlying = wasFlying }
        ActionRecorder.isFlying = true
        let plane = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let pinch = Driven()
        plane.addGestureRecognizer(pinch)
        let marker = "test-fresh-pose-" + UUID().uuidString
        var delivery = Array(repeating: CanvasNavigationGesture.Delivery(), count: CanvasNavigationGesture.allCases.count)
        recorder.canvasNavigationSnapshot(edge: marker + ":start", touch: 10, container: plane, writes: 0,
                                          pan: nil, pinch: pinch, rotation: nil, delivery: delivery)
        plane.transform = CGAffineTransform(rotationAngle: 0.5).scaledBy(x: 1.75, y: 1.75)
        plane.center = CGPoint(x: 234, y: 187)
        pinch.settle(in: .began)
        pinch.held = 2
        delivery[CanvasNavigationGesture.pinch.rawValue].changed = 1
        delivery[CanvasNavigationGesture.pinch.rawValue].writes = 1
        recorder.canvasNavigationSnapshot(edge: marker + ":moving", touch: 10, container: plane, writes: 1,
                                          pan: nil, pinch: pinch, rotation: nil, delivery: delivery)
        let lines = try savedFlightLines().filter { ($0["edge"] as? String)?.hasPrefix(marker) == true }
        XCTAssertEqual(lines.count, 2)
        let start = try XCTUnwrap(lines.first)
        let moving = try XCTUnwrap(lines.last)
        XCTAssertEqual(start["scale"] as? Double, 1)
        XCTAssertEqual(start["cx"] as? Double, 200)
        XCTAssertEqual(moving["scale"] as? Double, 1.75)
        XCTAssertEqual(moving["rot"] as? Double, 0.5)
        XCTAssertEqual(moving["cx"] as? Double, 234)
        XCTAssertEqual(moving["cy"] as? Double, 187)
        XCTAssertEqual(moving["canvas.pinch.state"] as? String, "began")
        XCTAssertEqual(moving["canvas.pinch.touches"] as? Int, 2)
        XCTAssertEqual(moving["canvas.pinch.view"] as? String, moving["canvas"] as? String)
        XCTAssertEqual(moving["canvas.pinch.changed"] as? Int, 1)
        XCTAssertEqual(moving["canvas.pinch.writes"] as? Int, 1)
        XCTAssertTrue(moving["canvas.rotation.obj"] is NSNull)
    }

    func testNavigationMissDistinguishesCancelReissueFromComparableLiftAndHealthyReissue() throws {
        XCTAssertNil(runReissue(interruption: "ended", lostNavigation: true, end: CGPoint(x: 851, y: 220.5)))
        XCTAssertNil(runReissue(interruption: "cancelled", lostNavigation: false, end: CGPoint(x: 851, y: 220.5)))
        XCTAssertNil(runReissue(interruption: "cancelled", lostNavigation: true, end: CGPoint(x: 708, y: 369)))
        let miss = try XCTUnwrap(runReissue(interruption: "cancelled", lostNavigation: true, end: CGPoint(x: 851, y: 220.5)))
        XCTAssertEqual(miss.kind, "cancelReissue")
        XCTAssertEqual(miss.touch, 3694)
        XCTAssertEqual(miss.cancelledTouch, 3693)
        XCTAssertEqual(miss.survivor, 3692)
        XCTAssertEqual(miss.lost, ["canvas.pinch", "canvas.rotation"])
        XCTAssertEqual(miss.travel, hypot(149, 148.5), accuracy: 0.001)
        XCTAssertEqual(miss.moves, 17)
    }

    func testFreshMissingContactThatGetsAHealthyPartnerDoesNotSave() {
        let object = NSObject(), other = NSObject()
        let counter = CanvasWedgeDetector.canvasMarker
        var miss = CanvasNavigationMiss()
        let first = touchSample(phase: "began", touchID: 1, object: object, bound: [counter])
        let second = touchSample(phase: "began", touchID: 2, object: other, down: 2, bound: [counter, "canvas.pan"])
        XCTAssertNil(miss.observe([first], startsSequence: true))
        XCTAssertNil(miss.observe([second], startsSequence: false))
        XCTAssertNil(miss.observe([touchSample(phase: "ended", touchID: 1, object: object, moves: 8)], startsSequence: false))
    }

    private func runReissue(interruption: String, lostNavigation: Bool, end: CGPoint) -> CanvasNavigationMiss.Finding? {
        let survivor = NSObject(), cancelled = NSObject(), reissued = NSObject()
        let counter = CanvasWedgeDetector.canvasMarker
        let all = [counter, "canvas.pan", "canvas.pinch", "canvas.rotation", "stroke.test"]
        let new = lostNavigation ? [counter, "canvas.pan"] : Array(all.dropLast())
        var miss = CanvasNavigationMiss()
        XCTAssertNil(miss.observe([
            touchSample(phase: "began", touchID: 3692, object: survivor, time: 85.88, point: CGPoint(x: 701, y: 457), down: 2, bound: all),
            touchSample(phase: "began", touchID: 3693, object: cancelled, time: 85.88, point: CGPoint(x: 702, y: 369), down: 2, bound: all)
        ], startsSequence: true))
        XCTAssertNil(miss.observe([
            touchSample(phase: interruption, touchID: 3693, object: cancelled, moves: 0, time: 85.93, point: CGPoint(x: 702, y: 369))
        ], startsSequence: false))
        XCTAssertNil(miss.observe([
            touchSample(phase: "began", touchID: 3694, object: reissued, time: 85.94, point: CGPoint(x: 702, y: 369), down: 2, bound: new)
        ], startsSequence: false))
        let finding = miss.observe([
            touchSample(phase: "ended", touchID: 3694, object: reissued, moves: 17, time: 86.27, point: end)
        ], startsSequence: false)
        XCTAssertNil(miss.observe([
            touchSample(phase: "ended", touchID: 3692, object: survivor, moves: 21, time: 86.27, point: CGPoint(x: 813, y: 574.5), down: 0)
        ], startsSequence: false), "one episode contributes one finding")
        return finding
    }

    func testBoundPairNeedsRepeatedIntentionalMotionWithoutNavigationWritesOrPolicyRefusals() throws {
        let pan = try XCTUnwrap(runBoundPair())
        XCTAssertEqual(pan.kind, "boundWithoutApplication")
        XCTAssertEqual(pan.touch, 11)
        XCTAssertEqual(pan.lost, [])
        XCTAssertEqual(pan.motion?.partner, 12)
        XCTAssertEqual(pan.motion?.centroidTravel, 45)
        XCTAssertEqual(pan.motion?.relativeTravel, 0)
        XCTAssertEqual(pan.motion?.samples, 2)
        XCTAssertEqual(pan.moves, 13)
        let pinch = try XCTUnwrap(runBoundPair(deltas: [(0, 0), (-15, 15), (-24, 24)]))
        XCTAssertEqual(pinch.motion?.centroidTravel, 0)
        XCTAssertEqual(pinch.motion?.relativeTravel, 48)

        XCTAssertNil(runBoundPair(deltas: [(0, 0), (1, 1), (2, 2)]), "ordinary taps stay quiet")
        XCTAssertNil(runBoundPair(deltas: [(0, 0), (28, 28), (28, 28)]), "a held position is only one motion sample")
        XCTAssertNil(runBoundPair(writes: 1), "a real navigation write before lift is sufficient")
        XCTAssertNil(runBoundPair(refusals: 1), "an intentional policy refusal is sufficient")
        XCTAssertNil(runBoundPair(plainLandings: [12]), "an overlay or menu at either landing precludes diagnosis")
        XCTAssertNil(runBoundPair(secondType: "pencil"), "a Pencil is not the second finger")
        XCTAssertNil(runBoundPair(secondDelay: 0.12), "a late arrival is not a fresh pair")
        XCTAssertNil(runBoundPair(interveningPhase: "began"), "a third contact on or off the canvas invalidates the pair")
        XCTAssertNil(runBoundPair(interveningPhase: "cancelled"), "a cancelled and reissued contact takes the other path")
    }

    private func runBoundPair(deltas: [(Double, Double)] = [(0, 0), (28, 28), (45, 45)],
                              writes: Int = 0, refusals: Int = 0, plainLandings: Set<Int> = [11, 12],
                              secondType: String = "direct", secondDelay: Double = 0.02,
                              interveningPhase: String? = nil) -> CanvasNavigationMiss.Finding? {
        let host = NSObject(), first = NSObject(), second = NSObject(), other = NSObject()
        let source = ObjectIdentifier(host)
        let bound = [CanvasWedgeDetector.canvasMarker] + CanvasNavigationGesture.allCases.map(\.name)
        let before = CanvasNavigationMiss.Activity(source: source, writes: 10, refusals: 3)
        var detector = CanvasNavigationMiss()
        XCTAssertNil(detector.observe([
            touchSample(phase: "began", touchID: 11, object: first, time: 1, bound: bound)
        ], startsSequence: true, plainLandings: plainLandings.intersection([11])))
        XCTAssertNil(detector.observe([
            touchSample(phase: "began", touchID: 12, object: second, time: 1 + secondDelay, down: 2, bound: bound, type: secondType)
        ], startsSequence: false, plainLandings: plainLandings.intersection([12])))
        func positions(_ a: Double, _ b: Double) -> (CanvasNavigationMiss.Position, CanvasNavigationMiss.Position) {
            (.init(id: 11, point: CGPoint(x: 70 + a, y: 100)), .init(id: 12, point: CGPoint(x: 160 + b, y: 100)))
        }
        let initial = positions(0, 0)
        detector.startBoundPair(initial.0, initial.1, at: 1.03, activity: before)
        for (index, delta) in deltas.enumerated() {
            let points = positions(delta.0, delta.1)
            let time = 1.1 + Double(index) * 0.06
            if detector.shouldSampleBoundPair(at: time, interval: 0.05) {
                detector.sampleBoundPair(points.1, points.0, at: time, activity: before)
            }
        }
        if let interveningPhase {
            let id = interveningPhase == "cancelled" ? 12 : 13
            XCTAssertNil(detector.observe([
                touchSample(phase: interveningPhase, touchID: id, object: other, time: 1.31)
            ], startsSequence: false, activity: before))
            if interveningPhase == "cancelled" {
                XCTAssertNil(detector.observe([
                    touchSample(phase: "began", touchID: 13, object: other, time: 1.32, down: 2, bound: bound)
                ], startsSequence: false, plainLandings: [13]))
                detector.startBoundPair(initial.0, .init(id: 13, point: initial.1.point), at: 1.32, activity: before)
                XCTAssertFalse(detector.isWatchingBoundPair, "even a fully bound replacement cannot rearm this detector")
            }
        }
        let after = CanvasNavigationMiss.Activity(source: source, writes: 10 + writes, refusals: 3 + refusals)
        return detector.observe([
            touchSample(phase: "ended", touchID: 11, object: first, moves: 13, time: 1.45)
        ], startsSequence: false, activity: after)
    }

    @MainActor
    func testNavigationMissesAutomaticallySaveWithoutManualRecording() throws {
        let recorder = ActionRecorder.shared
        let wasFlying = ActionRecorder.isFlying
        let wasCapturing = ActionRecorder.isCapturing
        ActionRecorder.isFlying = true
        ActionRecorder.isCapturing = false
        recorder.startFlight(canvasSize: CGSize(width: 300, height: 300), projectName: "navigation-test-source")
        recorder.refreshRecordings()
        let known = Set(recorder.recordings.map(\.url))
        var created: [URL] = []
        defer {
            for url in created { try? FileManager.default.removeItem(at: url) }
            recorder.refreshRecordings()
            ActionRecorder.isFlying = wasFlying
            ActionRecorder.isCapturing = wasCapturing
        }
        let marker = "test-no-motion-" + UUID().uuidString
        func newFlights() -> Set<URL> { Set(recorder.recordings.map(\.url)).subtracting(known) }
        func waitForFlight(count: Int, excluding: Set<URL> = []) throws -> URL {
            let saved = expectation(for: NSPredicate { _, _ in newFlights().count == count }, evaluatedWith: recorder)
            wait(for: [saved], timeout: 5)
            let all = newFlights()
            created = Array(all)
            return try XCTUnwrap(all.subtracting(excluding).first)
        }
        func readLines(in url: URL, containing marker: String) throws -> [[String: Any]] {
            let data = try recordingBytes(at: url, containing: marker)
            return try String(decoding: data, as: UTF8.self).split(separator: "\n").map { try headerFields(String($0)) }
        }
        let object = NSObject()
        var miss = CanvasNavigationMiss()
        let bound = [CanvasWedgeDetector.canvasMarker]
        let plane = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let delivery = Array(repeating: CanvasNavigationGesture.Delivery(), count: CanvasNavigationGesture.allCases.count)
        var now = CACurrentMediaTime()

        let began = touchSample(phase: "began", touchID: 1567, object: object, time: now, bound: bound)
        recorder.touch(began)
        XCTAssertNil(miss.observe([began], startsSequence: true))
        recorder.canvasNavigationSnapshot(edge: marker + ":begin", touch: 1567, container: plane, writes: 0,
                                          pan: nil, pinch: nil, rotation: nil, delivery: delivery)
        now += 0.01
        let ended = touchSample(phase: "ended", touchID: 1567, object: object, moves: 19, time: now,
                                point: CGPoint(x: 120, y: 0), down: 0)
        recorder.touch(ended)
        let finding = try XCTUnwrap(miss.observe([ended], startsSequence: false))
        recorder.canvasNavigationSnapshot(edge: marker + ":lift", touch: 1567, container: plane, writes: 0,
                                          pan: nil, pinch: nil, rotation: nil, delivery: delivery)
        recorder.canvasNavigationMissed(finding)
        let second = touchSample(phase: "began", touchID: 1568, object: object, bound: bound)
        XCTAssertNil(miss.observe([second], startsSequence: true))
        XCTAssertNil(miss.observe([touchSample(phase: "ended", touchID: 1568, object: object, moves: 0)],
                                 startsSequence: false), "consecutive fresh misses are one diagnostic episode")

        let partial = try XCTUnwrap(runReissue(interruption: "cancelled", lostNavigation: true, end: CGPoint(x: 851, y: 220.5)))
        recorder.canvasNavigationMissed(partial)
        recorder.canvasNavigationMissed(try XCTUnwrap(runBoundPair()))
        // The pending item itself writes the first flight. There is no project switch, manual
        // Save Last 90 Seconds, or repair callback to land it for the recorder.
        let first = try waitForFlight(count: 1)
        let lines = try readLines(in: first, containing: marker)
        let missedLine = lines.first { $0["event"] as? String == "canvasNavigationMiss" && $0["touch"] as? Int == 1567 }
        XCTAssertEqual(lines.first?["trigger"] as? String, "navigation")
        XCTAssertEqual(lines.first?["project"] as? String, "navigation-test-source")
        let snapshots = lines.filter { ($0["edge"] as? String)?.hasPrefix(marker) == true }
        XCTAssertEqual(snapshots.count, 2)
        for key in ["scale", "cx", "cy", "rot", "writes", "canvas.pan.changed", "canvas.pinch.changed", "canvas.rotation.changed"] {
            let begin = try XCTUnwrap(snapshots.first?[key] as? Double, key)
            XCTAssertEqual(snapshots.last?[key] as? Double, begin, key)
        }
        XCTAssertEqual(snapshots.last?["writes"] as? Int, 0)
        XCTAssertEqual(missedLine?["event"] as? String, "canvasNavigationMiss")
        XCTAssertEqual(missedLine?["kind"] as? String, "freshMissing")
        XCTAssertEqual(missedLine?["touch"] as? Int, 1567)
        XCTAssertEqual(missedLine?["travel"] as? Double, 120)
        XCTAssertEqual(missedLine?["moves"] as? Int, 19)

        let reissue = lines.first { $0["event"] as? String == "canvasNavigationMiss" && $0["touch"] as? Int == 3694 }
        XCTAssertEqual(reissue?["kind"] as? String, "cancelReissue")
        XCTAssertEqual(reissue?["lost"] as? String, "canvas.pinch,canvas.rotation")
        XCTAssertEqual(reissue?["survivor"] as? Int, 3692)
        XCTAssertEqual(reissue?["moves"] as? Int, 17)
        let boundMiss = try XCTUnwrap(lines.first { $0["kind"] as? String == "boundWithoutApplication" })
        XCTAssertEqual(boundMiss["partner"] as? Int, 12)
        XCTAssertEqual(boundMiss["centroidTravel"] as? Double, 45)
        XCTAssertEqual(boundMiss["relativeTravel"] as? Double, 0)
        XCTAssertEqual(boundMiss["motionSamples"] as? Int, 2)

        recorder.canvasNavigationMissed(partial)
        // Switching before the diagnostic delay preserves the outgoing project context.
        recorder.startFlight(canvasSize: CGSize(width: 200, height: 200), projectName: "navigation-test-next")
        let afterSwitch = try waitForFlight(count: 2, excluding: [first])
        let switchedLines = try readLines(in: afterSwitch, containing: "cancelReissue")
        XCTAssertEqual(switchedLines.first?["project"] as? String, "navigation-test-source")

        // The canceled pending timer must leave the two files alone after its deadline.
        let duplicate = expectation(for: NSPredicate { _, _ in newFlights().count > 2 }, evaluatedWith: recorder)
        duplicate.isInverted = true
        wait(for: [duplicate], timeout: 0.35)
        created = Array(newFlights())
        XCTAssertEqual(created.count, 2)
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
