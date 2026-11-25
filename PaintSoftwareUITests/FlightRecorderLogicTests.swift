import XCTest

/// The flight recorder's two pure halves — `CanvasTouchAudit`, which says the canvas stopped answering a
/// hand, and `FlightRing`'s two bounds — and what its files carry.
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

    /// **A recording says what the tool was set to** — the November 16 recording of a Fill that left a gap
    /// under a Rough Ink line held no brush, size, pressure or Fill setting, so which brush and whether Mend
    /// Gaps was on could not be read from it. The settings are written when recording starts, again when
    /// they change (at the edge of the touch that changed them), and a snapshot rides on every canvas
    /// touch-began.
    @MainActor
    func testARecordingCarriesTheToolSettingsAtStartOnChangeAndOnEveryCanvasTouchBegan() throws {
        let recorder = ActionRecorder.shared
        try XCTSkipIf(recorder.isRecording, "an existing recording owns the recorder")
        recorder.refreshRecordings()
        let known = Set(recorder.recordings.map(\.url))
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 5000, height: 5000)
        manager.addVectorLayer()
        manager.addVectorLayer()
        manager.selectedTool = .pen
        manager.selectPreset(BrushLibrary.roughInk, for: .brush)
        manager.setSizeSliderPosition(0, of: .brush) // the slider's bottom: 0.1% of 5000
        recorder.toolSettingsProvider = { [weak manager] in manager?.recorderToolSettings() ?? [] }
        var created: [URL] = []
        defer {
            recorder.toolSettingsProvider = nil
            recorder.stop()
            for url in created { try? FileManager.default.removeItem(at: url) }
            recorder.refreshRecordings()
        }
        func touch(_ phase: String, id: Int, target: String?) -> TouchSample {
            TouchSample(time: CACurrentMediaTime(), phase: phase, type: "pencil", touchID: id,
                        object: ObjectIdentifier(manager), moves: nil, target: target, targetClass: "CanvasHostView",
                        hitClass: "StrokeCanvasView", role: "other", label: nil, depth: 0, resolution: "view",
                        normalized: .zero, window: .zero, windowNormalized: .zero, concurrent: 1, isPencil: true,
                        force: 1, maxForce: 4, altitude: 0, azimuth: 0, coalescedAway: nil, touchViewClass: nil,
                        boundRecognizers: nil)
        }
        recorder.start(canvasSize: manager.canvasSize, projectName: "tool-settings")
        recorder.touch(touch("began", id: 1, target: "canvas.host"))
        recorder.touch(touch("ended", id: 1, target: "canvas.host"))
        // The artist picks Fill, turns Mend Gaps off, and taps: the change lands at the touch's edge.
        manager.selectedTool = .fill
        manager.setFillMendsGaps(false)
        recorder.touch(touch("began", id: 2, target: "canvas.host"))
        recorder.touch(touch("ended", id: 2, target: "canvas.host"))
        recorder.stop()
        recorder.refreshRecordings()
        let url = try XCTUnwrap(Set(recorder.recordings.map(\.url)).subtracting(known).first)
        created.append(url)
        let text = String(decoding: try recordingBytes(at: url, containing: "recordingStopped"), as: UTF8.self)
        let lines = text.split(separator: "\n").map(String.init)
        let settings = lines.filter { $0.contains("\"event\":\"toolSettings\"") }
        let atTouch = lines.filter { $0.contains("\"event\":\"toolAtTouch\"") }

        XCTAssertEqual(settings.count, 2, "once at the start, once when Fill replaced the brush — not per touch: \(settings)")
        let start = try XCTUnwrap(settings.first)
        for expected in ["\"reason\":\"start\"", "\"tool\":\"pen\"", "\"brush\":\"Rough Ink\"",
                         "0.1% = 5 px", "size<-pressurex1", "flow<-pressurex0.1", "\"opacity\":\"100%\"",
                         "\"targetLayer\":\"1 "] {
            XCTAssertTrue(start.contains(expected), "the start line names \(expected): \(start)")
        }
        let fill = try XCTUnwrap(settings.last)
        for expected in ["\"tool\":\"fill\"", "\"mendGaps\":false", "\"mendReach\":\"12\"", "\"edgeOverlap\":\"2\"",
                         "\"fillType\":\"flood\"", "\"references\":\"2 of 2:", "\"targetLayer\""] {
            XCTAssertTrue(fill.contains(expected), "the Fill line names \(expected): \(fill)")
        }
        XCTAssertEqual(atTouch.count, 2, "every canvas touch-began carries a snapshot")
        guard atTouch.count == 2 else { return }
        XCTAssertTrue(atTouch[0].contains("brush=Rough Ink") && atTouch[0].contains("size=0.1% = 5 px"), "\(atTouch[0])")
        XCTAssertTrue(atTouch[1].contains("tool=fill") && atTouch[1].contains("mendGaps=off") && atTouch[1].contains("mendReach=12"),
                      "\(atTouch[1])")
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

    @MainActor
    func testUndoPictureMatchesOnlyTheRestoredCelOwnerAndExactDocumentVersionAcrossWindows() {
        let trace = PlaybackTrace.shared
        trace.start()
        defer { trace.stop() }

        let layer = UUID(), cel = UUID(), canvas = UUID()
        func assign(layerID: UUID = layer, celID: UUID = cel, vectorID: UUID = canvas,
                    version: Int = 12, source: PlaybackTrace.UndoPictureSource = .deferred) {
            trace.committedBaseAssigned(layerID: layerID, celID: celID, vectorID: vectorID,
                                        documentVersion: version, source: source)
        }
        trace.traceUndo {
            trace.vectorStrokeRestored(layerID: layer, celID: cel, vectorID: canvas, documentVersion: 12)
        }
        let pressWindow = trace.drainWindow()
        XCTAssertEqual(pressWindow.phases.first { $0.phase == "undoPress" }?.count, 1)
        XCTAssertTrue(pressWindow.undoPictures.isEmpty, "the press alone is not a committed picture")

        assign(layerID: UUID())
        assign(celID: UUID())
        assign(vectorID: UUID())
        assign(version: 11)
        assign(version: 13)
        XCTAssertTrue(trace.drainWindow().undoPictures.isEmpty, "a different owner or revision cannot finish the sample")
        assign()
        assign(source: .cached)
        let pictures = trace.drainWindow().undoPictures
        XCTAssertEqual(pictures.count, 1, "the first exact assignment consumes this press")
        XCTAssertEqual(pictures.first?.target.documentVersion, 12)
        XCTAssertEqual(pictures.first?.source, .deferred)
        XCTAssertGreaterThanOrEqual(pictures.first?.pressToBaseMs ?? -1,
                                    pictures.first?.pressToRestoreMs ?? 0)
    }

    @MainActor
    func testUndoPictureFromAnOlderPressOrRecordingDoesNotFinishLater() {
        let trace = PlaybackTrace.shared
        trace.start()
        defer { trace.stop() }

        let layer = UUID(), cel = UUID(), canvas = UUID()
        func restore() {
            trace.vectorStrokeRestored(layerID: layer, celID: cel, vectorID: canvas, documentVersion: 1)
        }
        func assign() {
            trace.committedBaseAssigned(layerID: layer, celID: cel, vectorID: canvas,
                                        documentVersion: 1, source: .empty)
        }
        trace.traceUndo { restore() }
        trace.traceUndo {}
        assign()
        XCTAssertTrue(trace.drainWindow().undoPictures.isEmpty, "an unrelated subsequent press supersedes the pending one")

        trace.traceUndo { restore() }
        trace.stop()
        trace.start()
        restore()
        assign()
        XCTAssertTrue(trace.report().undoPictures.isEmpty, "a fresh recording cannot inherit a pending press")

        trace.traceUndo { restore() }
        assign()
        XCTAssertEqual(trace.report().undoPictures.first?.source, .empty)
    }

    // MARK: - The canvas audit

    private let canvas = NSObject()

    private func reading(count: Int = 2, fingers: Int = 2, isAtRest: Bool = false, writes: Int = 10,
                         refusals: Int = 3) -> CanvasTouchAudit.Reading {
        .init(source: ObjectIdentifier(canvas), count: count, fingers: fingers, isAtRest: isAtRest, writes: writes, refusals: refusals)
    }

    private func contact(_ id: Int, _ x: CGFloat, _ y: CGFloat = 0, heard: Bool = true) -> CanvasTouchAudit.Contact {
        .init(id: id, point: CGPoint(x: x, y: y), isHeard: heard)
    }

    /// A pair that moves `deltas` along and lifts; what the audit says of it, all told.
    private func runPair(deltas: [(CGFloat, CGFloat)] = [(28, 28), (45, 45)], fingers: Int = 2, writes: Int = 10,
                         refusals: Int = 3, third: Bool = false) -> [CanvasTouchAudit.Finding] {
        var audit = CanvasTouchAudit()
        var findings: [CanvasTouchAudit.Finding?] = []
        findings.append(audit.observe([contact(1, 0)], landed: [1], windowIsClear: false, reading(count: 1, fingers: 1)))
        findings.append(audit.observe([contact(1, 0), contact(2, 100)], landed: [2], windowIsClear: false, reading(fingers: fingers)))
        for (a, b) in deltas {
            findings.append(audit.observe([contact(1, a), contact(2, 100 + b)], landed: [], windowIsClear: false,
                                          reading(fingers: fingers)))
        }
        if third {
            findings.append(audit.observe([contact(1, 90), contact(2, 190), contact(3, 300)], landed: [3], windowIsClear: false,
                                          reading(count: 3, fingers: 3, writes: writes, refusals: refusals)))
        }
        findings.append(audit.observe([], landed: [], windowIsClear: true,
                                      reading(count: 0, fingers: 0, isAtRest: true, writes: writes, refusals: refusals)))
        return findings.compactMap { $0 }
    }

    func testAPairThatMovedAndAViewThatDidNotIsAFinding() {
        XCTAssertEqual(runPair(), [.unmoved(first: 1, second: 2, travel: 45, samples: 2)])
        XCTAssertEqual(runPair(deltas: [(-15, 15), (-24, 24)]), [.unmoved(first: 1, second: 2, travel: 48, samples: 2)],
                       "spreading counts as much as travelling")
        XCTAssertEqual(runPair(third: true), [.unmoved(first: 1, second: 2, travel: 45, samples: 2)],
                       "a third finger ends the watch on the pair, and it is still the finding it was")
        XCTAssertEqual(runPair(deltas: [(1, 1), (2, 2)]), [], "an ordinary tap")
        XCTAssertEqual(runPair(deltas: [(8, 8), (16, 16)]), [], "a drift short of a gesture")
        XCTAssertEqual(runPair(deltas: [(28, 28), (28, 28)]), [], "one movement and then a rest")
        XCTAssertEqual(runPair(writes: 11), [], "the view moved")
        XCTAssertEqual(runPair(refusals: 4), [], "a drag turned it down")
        XCTAssertEqual(runPair(fingers: 0), [], "two palms move nothing")
    }

    func testALandingTheCanvasNeverHeardIsAFindingOnce() {
        var audit = CanvasTouchAudit()
        XCTAssertEqual(audit.observe([contact(7, 0, heard: false)], landed: [7], windowIsClear: false, reading(count: 0, fingers: 0)),
                       .unheard(touch: 7))
        XCTAssertNil(audit.observe([contact(7, 0, heard: false), contact(8, 50, heard: false)], landed: [8], windowIsClear: false,
                                   reading(count: 0, fingers: 0)), "one finding a sequence")
        XCTAssertNil(audit.observe([], landed: [], windowIsClear: true, reading(count: 0, fingers: 0, isAtRest: true)))
        XCTAssertEqual(audit.observe([contact(9, 0, heard: false)], landed: [9], windowIsClear: false, reading(count: 0, fingers: 0)),
                       .unheard(touch: 9), "and the next sequence is its own")
    }

    func testACanvasStillHoldingATouchWhenEveryTouchIsGoneIsAFinding() {
        var audit = CanvasTouchAudit()
        XCTAssertNil(audit.observe([contact(1, 0)], landed: [1], windowIsClear: false, reading(count: 1, fingers: 1)))
        XCTAssertEqual(audit.observe([], landed: [], windowIsClear: true, reading(count: 1, fingers: 1)), .held(count: 1))
        XCTAssertNil(audit.observe([], landed: [], windowIsClear: true, reading(count: 0, fingers: 0, isAtRest: true)))
    }

    // MARK: - What a finding says was not at rest

    // MARK: - What the repair finds not at rest

    /// A recognizer a test can leave anywhere: `state` is writable only from inside a subclass, and
    /// `numberOfTouches` — what UIKit says it is still tracking — can only be moved by real touches,
    /// so it is overridden.
    private final class Driven: UIGestureRecognizer {
        var held = 0
        override var numberOfTouches: Int { held }
        func settle(in state: UIGestureRecognizer.State) { self.state = state }
    }

    /// Every recognizer under the window out of `.possible` or still holding a touch, wherever in the
    /// tree it hangs, named by what the file already calls it.
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

    // MARK: - What a flight's lines carry

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

    private func headerFields(_ line: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], line)
    }

    // MARK: - The sweep says which event it followed

    func testASweepIsTaggedWithTheLettersOfTheTouchPhasesTheEventCarried() {
        typealias Phases = WindowEventTap.EventPhases
        XCTAssertEqual(Phases.began.tag, "b")
        XCTAssertEqual(Phases.ended.tag, "e")
        XCTAssertEqual(Phases([.began, .ended]).tag, "be", "an event that began one touch and ended another")
        XCTAssertEqual(Phases([.cancelled, .moved, .began]).tag, "bmc", "always in the order b, m, e, c")
        XCTAssertEqual(Phases(UITouch.Phase.stationary), [], "a resting finger is no phase to tag by")
        XCTAssertEqual(Phases(UITouch.Phase.moved), .moved)
    }

    /// **What a sweep writes, through the real tap, the ring and a saved file**: a recognizer's state when
    /// it changed, tagged with the event it changed in, and nothing when nothing did. The recognizer is
    /// named for this test: the ring is the recorder's own and holds whatever an earlier test left in it.
    /// (`Driven` is settled in `.began` and `.ended`: UIKit puts a recognizer set to `.failed` with no
    /// real touch behind it straight back to `.possible`.)
    func testASweepWritesAStateThatChangedAndTheEventItChangedIn() throws {
        guard let window = WindowEventTap.activeWindow() else { throw XCTSkip("no window in the test process to install the tap on") }
        let canvas = UIView(frame: window.bounds)
        let driven = Driven(target: nil, action: nil)
        driven.name = "canvas.sweeptest"
        canvas.addGestureRecognizer(driven)
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

        driven.settle(in: .began)
        tap.sweepRecognizerStates(after: .began)
        tap.sweepRecognizerStates(after: .ended)      // nothing changed: nothing written
        driven.settle(in: .ended)
        tap.sweepRecognizerStates(after: [.ended, .cancelled])

        let lines = try savedFlightLines().filter { $0["name"] as? String == "canvas.sweeptest" }
        XCTAssertEqual(lines.map { "\($0["from"] ?? "?")>\($0["to"] ?? "?") \($0["src"] ?? "?")" },
                       ["possible>began sweep:b", "began>ended sweep:ec"])
    }

    /// Saves the flight ring the way the Settings row does and reads the file back.
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
        XCTAssertEqual(lines.first?["trigger"] as? String, "test")
        return lines
    }

    // MARK: - A finding saves its own flight

    @MainActor
    func testAFindingSavesItsFlightByItselfAndSaysNothingOnScreen() throws {
        let recorder = ActionRecorder.shared
        let wasFlying = ActionRecorder.isFlying
        let wasCapturing = ActionRecorder.isCapturing
        ActionRecorder.isFlying = true
        ActionRecorder.isCapturing = false
        recorder.startFlight(canvasSize: CGSize(width: 300, height: 300), projectName: "audit-test-source")
        recorder.refreshRecordings()
        let known = Set(recorder.recordings.map(\.url))
        var created: [URL] = []
        defer {
            for url in created { try? FileManager.default.removeItem(at: url) }
            recorder.refreshRecordings()
            ActionRecorder.isFlying = wasFlying
            ActionRecorder.isCapturing = wasCapturing
        }
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
        let marker = "audit-" + UUID().uuidString
        recorder.canvasMissed(.unmoved(first: 11, second: 12, travel: 45, samples: 2), notAtRest: [marker])
        recorder.canvasMissed(.unheard(touch: 1567), notAtRest: [marker])
        recorder.canvasMissed(.held(count: 1), notAtRest: [marker])
        // The pending item itself writes the flight: no project switch and no Save Last 90 Seconds.
        let first = try waitForFlight(count: 1)
        let lines = try readLines(in: first, containing: marker)
        XCTAssertEqual(lines.first?["trigger"] as? String, "canvas")
        XCTAssertEqual(lines.first?["project"] as? String, "audit-test-source")
        XCTAssertNil(recorder.flightNotice, "a diagnosis is nothing the artist can act on")
        let misses = lines.filter { $0["event"] as? String == "canvasMiss" && $0["notAtRest"] as? String == marker }
        XCTAssertEqual(misses.compactMap { $0["kind"] as? String }, ["unmoved", "unheard", "held"], "three findings, one file")
        XCTAssertEqual(misses.first?["touch"] as? Int, 11)
        XCTAssertEqual(misses.first?["partner"] as? Int, 12)
        XCTAssertEqual(misses.first?["travel"] as? Double, 45)
        XCTAssertEqual(misses.first?["samples"] as? Int, 2)

        recorder.canvasMissed(.held(count: 2), notAtRest: [marker + "-next"])
        // Switching before the delay keeps the outgoing project's context.
        recorder.startFlight(canvasSize: CGSize(width: 200, height: 200), projectName: "audit-test-next")
        let afterSwitch = try waitForFlight(count: 2, excluding: [first])
        XCTAssertEqual(try readLines(in: afterSwitch, containing: marker + "-next").first?["project"] as? String, "audit-test-source")

        // The cancelled pending timer must leave the two files alone after its deadline.
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
}
