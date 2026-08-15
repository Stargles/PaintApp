import UIKit
import SwiftUI
import Combine
import QuartzCore

/// Records what the artist actually did — every touch, every gesture-recognizer state change, every
/// model change it caused — into one greppable JSONL file the owner can hand back to us.
///
/// **Why this exists.** Debugging this app from the outside means an agent poking a simulator and
/// guessing; the runs are slow and most of them are void. The artist has the bug in their hands and
/// can reproduce it in four seconds. This turns those four seconds into a file with two readers in
/// mind, and the format is a compromise struck deliberately for both:
///
/// 1. **A human or agent diagnosing the bug.** Touches alone say nothing about *why* the canvas
///    stopped panning, so app internals are interleaved on the same clock: recognizer transitions,
///    the answer `shouldRequireFailureOf` gave and who it named, tool/frame/layer changes, and the
///    canvas transform. Cause sits next to effect instead of being inferred.
/// 2. **Mechanical conversion into an XCUITest** (`tools/recording2xcuitest.py`). That is the reason
///    every touch is recorded against an **accessibility identifier plus a normalised offset inside
///    that element**, not against screen coordinates. Coordinates do not survive a different device,
///    a rotated canvas, or a relaid-out toolbar; `app.buttons["toolbar.selectButton"]` does.
///
/// **Off by default and free when off.** See `isCapturing` for exactly what executes on the drawing
/// path while recording is off — the answer is one static `Bool` load per hook site, and nothing at
/// all inside `UIWindow.sendEvent`, because the interception is *uninstalled* rather than switched
/// off (see `WindowEventTap`).
///
/// Rejected alternative: **screen recording plus a log**. It is what the owner has today in effect,
/// and it costs a human watching a video frame by frame trying to line "the canvas froze here" up
/// against a console. It also cannot be replayed: nothing in a video names the element that was
/// tapped. The file this writes converts to a test; a video never will.
///
/// Rejected alternative: **instrumenting each control** (a `.onTapGesture` beside every button, a
/// callback in every panel). It would have been a hundred edit sites across every view in the app,
/// each one a chance to change behaviour, and it would still have missed the canvas — where the
/// interesting bugs are. `sendEvent` is one edit site that sees all of them.
final class ActionRecorder: ObservableObject {
    static let shared = ActionRecorder()

    // MARK: - The drawing-path gate

    /// The one thing the drawing path reads while recording is off.
    ///
    /// A plain stored `Bool`, deliberately **not** the `@Published isRecording` below: reading a
    /// `@Published` property goes through its property wrapper and drags `ObservableObject` into
    /// call sites like `StrokeGestureRecognizer.touchesMoved`, which run per touch sample. This is a
    /// single static load, and every hook in the app is written as
    /// `ActionRecorder.ifRecording { ... }` so the *arguments* — the interpolated strings, the point
    /// conversions — are never built either.
    ///
    /// **What executes on the drawing path when recording is off, exhaustively:** one load-and-branch
    /// at each of the hook sites in `StrokeGestureRecognizer.transition(to:)`,
    /// `CanvasView.Coordinator.applyTransform`, `gestureRecognizer(_:shouldRequireFailureOf:)`, and
    /// the `didSet`s on `CanvasManager`. Nothing else: `UIWindow.sendEvent` is the app's own
    /// unmodified implementation (the interception is installed on `start()` and removed on
    /// `stop()`), no target-actions are attached to any recognizer, no timer is scheduled, no buffer
    /// is allocated, and this object's `init` runs at most once and stores nothing.
    static var isCapturing = false

    /// Runs `body` only while recording, handing it the recorder. Written as a non-escaping closure
    /// so that when recording is off the closure body — string interpolation, coordinate conversion,
    /// dictionary building — is never evaluated and never allocates.
    @inline(__always)
    static func ifRecording(_ body: (ActionRecorder) -> Void) {
        guard isCapturing else { return }
        body(shared)
    }

    // MARK: - Published state (UI only — never read from the drawing path)

    @Published private(set) var isRecording = false
    /// Events written so far. Refreshed **on the flush tick, not per event** — a `@Published` write
    /// per touch sample would re-run every SwiftUI body in the editor for each of them, which is the
    /// exact cost this app's architecture spends its comments avoiding (§5.2). The counter therefore
    /// lags by up to `flushInterval`; that is fine for "is it alive and going up".
    @Published private(set) var eventCount = 0
    /// Recording wall-clock length, refreshed on the same tick as `eventCount`.
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recordings: [Recording] = []
    /// Surfaced in the Actions menu when something could not be set up — an unwritable Documents
    /// directory, or a window whose `sendEvent` could not be intercepted. Never fails silently: a
    /// recorder that quietly records nothing is worse than no recorder.
    @Published private(set) var problem: String?

    // MARK: - Recording session state

    private var writer: RecordingWriter?
    /// Internal, not private: `StrokeGestureRecognizer` reports its own transitions through
    /// `recognizerTransition(_:to:source:)` below, which needs the tap's registry to keep the sweep
    /// from writing the same transition twice.
    private(set) var tap: WindowEventTap?
    private var flushTimer: Timer?
    /// Monotonic (`CACurrentMediaTime`, i.e. uptime — unaffected by clock changes) start instant.
    /// Every `t` in the file is seconds since this. `UITouch.timestamp` shares this time base, which
    /// is why touch events carry the *hardware* time rather than the time we got round to logging.
    private(set) var startTime: CFTimeInterval = 0
    private var writtenEvents = 0

    private init() {}

    // MARK: - Start / stop

    /// Begins a recording. `canvasSize` is only for the header — the recorder holds no reference to
    /// `CanvasManager`, so nothing here can keep a closed project alive.
    func start(canvasSize: CGSize?, projectName: String) {
        guard !isRecording else { return }
        problem = nil

        let url: URL
        do {
            url = try Self.newRecordingURL()
        } catch {
            problem = "Couldn't create the recordings folder: \(error.localizedDescription)"
            return
        }
        guard let writer = RecordingWriter(url: url) else {
            problem = "Couldn't open \(url.lastPathComponent) for writing."
            return
        }

        self.writer = writer
        startTime = CACurrentMediaTime()
        writtenEvents = 0
        eventCount = 0
        elapsed = 0

        // The tap goes in before the header is written so the header can report which window class
        // was actually intercepted — a detail that matters the day SwiftUI stops handing us a plain
        // `UIWindow` and the file arrives with no touches in it.
        let tap = WindowEventTap()
        let tapReport = tap.install()
        self.tap = tap

        write(Self.headerLine(canvasSize: canvasSize, projectName: projectName, tap: tapReport, url: url))

        // Recording is live from here: the gate flips only once both the writer and the tap are up,
        // so a hook can never fire into a nil writer.
        Self.isCapturing = true
        isRecording = true

        if tapReport.interceptedClass == nil {
            problem = "Touches are NOT being recorded — \(tapReport.note). App state still is."
        }

        // Runloop-mode `.common` so the timer keeps ticking while a scroll or a drag is tracking;
        // the default mode would stall exactly during the gestures being recorded.
        let timer = Timer(timeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    func stop() {
        guard isRecording else { return }
        // Gate first: every hook in the app becomes a no-op before anything is torn down, so a
        // touch already in flight cannot reach a half-closed writer.
        Self.isCapturing = false
        isRecording = false

        write(line("recordingStopped", [("events", .int(writtenEvents + 1)), ("seconds", .num(CACurrentMediaTime() - startTime))]))

        flushTimer?.invalidate()
        flushTimer = nil
        tap?.uninstall()
        tap = nil
        writer?.close()
        writer = nil

        eventCount = writtenEvents
        elapsed = 0
        refreshRecordings()
    }

    /// Flush cadence, and the cadence at which the UI counter catches up. Two seconds is a
    /// deliberate compromise: long enough that a 20 Hz stroke costs one write instead of sixty, short
    /// enough that a crash mid-repro — which is one of the things worth recording — loses at most two
    /// seconds off the end of the file. JSONL is what makes that loss survivable: the truncated file
    /// is still valid up to its last newline.
    private static let flushInterval: TimeInterval = 2

    private func tick() {
        guard isRecording else { return }
        writer?.flush()
        eventCount = writtenEvents
        elapsed = CACurrentMediaTime() - startTime
        // Layers come and go mid-recording, and each new one brings a `StrokeGestureRecognizer` that
        // has to be watched. Re-scanning here rather than per event keeps the discovery walk off the
        // drawing path entirely — the cost is that a recognizer created mid-recording is unwatched
        // for up to `flushInterval`, which is invisible next to a human's reaction time.
        tap?.rescanRecognizers()
    }

    // MARK: - Event emitters
    //
    // Every one of these is called from inside `ifRecording`, so none of them needs its own guard —
    // and none of them may be made cheap-to-call-always, because that is what would put string
    // building back on the drawing path.

    /// Seconds since recording start, the `t` on every line. Takes an explicit instant so touch
    /// events can carry `UITouch.timestamp` (when the hardware saw it) rather than when we logged it.
    func stamp(_ absolute: CFTimeInterval) -> Double { absolute - startTime }
    var now: Double { CACurrentMediaTime() - startTime }

    func model(_ key: String, _ value: String) {
        write(line("model", [("key", .str(key)), ("value", .str(value))], at: now))
    }

    /// A gesture recognizer changed state. **The single most valuable signal in the file**: the bug
    /// this was built for is the canvas transform recognizers waiting forever on a stroke recognizer
    /// that never reaches a terminal state, and that is only visible as an absence — a `.began` with
    /// no `.ended`/`.failed`/`.cancelled` after it. `source` says how we noticed (see
    /// `WindowEventTap.sweepRecognizerStates`), because the three routes have different blind spots
    /// and knowing which one caught a transition tells you whether the ordering is exact.
    func recognizer(_ name: String, object: ObjectIdentifier, from: UIGestureRecognizer.State, to: UIGestureRecognizer.State, source: String) {
        write(line("recognizer", [
            ("name", .str(name)),
            ("obj", .str(Self.shortObject(object))),
            ("from", .str(Self.stateName(from))),
            ("to", .str(Self.stateName(to))),
            ("src", .str(source))
        ], at: now))
    }

    /// The answer `CanvasView.Coordinator.gestureRecognizer(_:shouldRequireFailureOf:)` gave, and
    /// which recognizer it named. A `true` here is the edge that can deadlock the transform gestures,
    /// so it is recorded on every call rather than only when it changes — the interesting case is a
    /// `true` pointing at a recognizer that the `recognizer` lines show never terminating.
    func failureRequirement(asker: String, other: String, answer: Bool) {
        write(line("requireFailure", [
            ("asker", .str(asker)),
            ("other", .str(other)),
            ("answer", .bool(answer))
        ], at: now))
    }

    func transform(committedScale: CGFloat, committedRotation: CGFloat, committedOffset: CGSize,
                   liveScale: CGFloat, liveRotation: CGFloat, liveOffset: CGSize,
                   appliedScale: CGFloat, appliedRotation: CGFloat, appliedOffset: CGSize) {
        write(line("transform", [
            ("scale", .num(appliedScale)), ("rot", .num(appliedRotation)),
            ("dx", .num(appliedOffset.width)), ("dy", .num(appliedOffset.height)),
            ("cScale", .num(committedScale)), ("cRot", .num(committedRotation)),
            ("cdx", .num(committedOffset.width)), ("cdy", .num(committedOffset.height)),
            ("lScale", .num(liveScale)), ("lRot", .num(liveRotation)),
            ("ldx", .num(liveOffset.width)), ("ldy", .num(liveOffset.height))
        ], at: now))
    }

    /// One touch sample. Field order is fixed and put the replay-relevant fields first on purpose:
    /// the file is read by eye as often as by a parser, and `phase`/`type`/`target` are what a human
    /// scans for.
    func touch(_ s: TouchSample) {
        var fields: [(String, JSONValue)] = [
            ("phase", .str(s.phase)),
            ("type", .str(s.type)),
            ("touch", .int(s.touchID)),
            ("target", s.target.map { JSONValue.str($0) } ?? .null),
            ("role", .str(s.role)),
            ("nx", .num(s.normalized.x)), ("ny", .num(s.normalized.y)),
            ("depth", .int(s.depth)),
            ("via", .str(s.resolution)),
            ("hitClass", .str(s.hitClass)),
            ("targetClass", .str(s.targetClass)),
            ("wx", .num(s.window.x)), ("wy", .num(s.window.y)),
            ("wnx", .num(s.windowNormalized.x)), ("wny", .num(s.windowNormalized.y)),
            ("down", .int(s.concurrent))
        ]
        if let label = s.label, !label.isEmpty { fields.append(("label", .str(label))) }
        // Pencil geometry, always, for `.pencil` touches. `.pencil` vs `.direct` is load-bearing for
        // the bugs being chased (pencil-only mode gating a finger out, palm rejection racing a
        // stroke), and it is also the one thing XCUITest flatly cannot replay — the converter has to
        // shout about it rather than silently emit a finger tap, which is why it is never elided.
        if s.isPencil {
            fields.append(("force", .num(s.force)))
            fields.append(("maxForce", .num(s.maxForce)))
            fields.append(("altitude", .num(s.altitude)))
            fields.append(("azimuth", .num(s.azimuth)))
        }
        if let dropped = s.coalescedAway, dropped > 0 {
            fields.append(("skipped", .int(dropped)))
        }
        write(line("touch", fields, at: s.time))
    }

    /// Reports a transition for a recognizer whose source we own — today only
    /// `StrokeGestureRecognizer`, which assigns `state` directly and so can say *exactly* when it
    /// changed, ahead of both the action message and the post-event sweep. Routed through the tap so
    /// the registry's idea of "last state" stays in step and the sweep doesn't repeat it.
    func recognizerTransition(_ recognizer: UIGestureRecognizer, to newState: UIGestureRecognizer.State, source: String) {
        tap?.noteTransition(recognizer, to: newState, source: source)
    }

    /// The name a recognizer is known by in the file. Used by the `requireFailure` hook, which names
    /// two recognizers rather than logging one's state.
    func nameFor(_ recognizer: UIGestureRecognizer) -> String {
        tap?.displayName(for: recognizer) ?? String(describing: type(of: recognizer))
    }

    /// A free-text marker. Not wired to any UI today; kept because the first thing anyone wants when
    /// reading someone else's recording is "which of these is the moment it went wrong".
    func note(_ text: String) {
        write(line("note", [("text", .str(text))], at: now))
    }

    // MARK: - Line building
    //
    // Hand-built rather than `JSONEncoder`/`JSONSerialization`, for three reasons that all matter
    // here: field order is stable (so `grep`, `diff` and a human's eye all work on the file),
    // there is no per-event `Encodable` boxing or dictionary allocation on the drawing path, and
    // floats are emitted rounded rather than as 17 significant digits of noise.

    enum JSONValue {
        case str(String)
        case num(CGFloat)
        case int(Int)
        case bool(Bool)
        case null
    }

    private func line(_ event: String, _ fields: [(String, JSONValue)], at t: Double? = nil) -> String {
        var out = "{\"t\":"
        out += Self.number(CGFloat(t ?? now))
        out += ",\"event\":\""
        out += event
        out += "\""
        for (key, value) in fields {
            out += ",\""
            out += key
            out += "\":"
            switch value {
            case .str(let s): out += "\"" + Self.escape(s) + "\""
            case .num(let n): out += Self.number(n)
            case .int(let i): out += String(i)
            case .bool(let b): out += b ? "true" : "false"
            case .null: out += "null"
            }
        }
        out += "}"
        return out
    }

    /// Two decimal places, and finite. Two is enough to place a touch inside a 44 pt hit target and
    /// to see a scale settle; more turns every line into unreadable float dust. Non-finite values are
    /// coerced to 0 rather than emitted — `NaN` is not valid JSON and would break the parser on the
    /// far end, which is the one failure mode a debugging artefact must not have.
    static func number(_ value: CGFloat) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (Double(value) * 100).rounded() / 100
        return rounded == rounded.rounded() && abs(rounded) < 1e15
            ? String(Int(rounded))
            : String(rounded)
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 2)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    /// A short, stable handle for an object — enough to tell two recognizers of the same class apart
    /// across the whole file, without printing a raw pointer that reads as a security smell and means
    /// nothing to a reader.
    static func shortObject(_ id: ObjectIdentifier) -> String {
        String(UInt(bitPattern: id.hashValue) & 0xFFFFFF, radix: 16)
    }

    static func stateName(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible: return "possible"
        case .began: return "began"
        case .changed: return "changed"
        case .ended: return "ended"      // == .recognized
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        @unknown default: return "state\(state.rawValue)"
        }
    }

    private func write(_ line: String) {
        writtenEvents += 1
        writer?.append(line)
    }

    // MARK: - Header

    private static func headerLine(canvasSize: CGSize?, projectName: String, tap: WindowEventTap.InstallReport, url: URL) -> String {
        var fields: [(String, JSONValue)] = [
            ("schema", .int(1)),
            ("app", .str(AppVersion.versionString)),
            ("build", .str(buildDateString())),
            // No git SHA: this project generates its Info.plist from build settings and has no run
            // script phase, so there is nowhere to put one without adding a build phase to
            // `project.pbxproj` — a change that would run on every build and would collide with the
            // other sessions working this repo. `app` + `build` pin the binary well enough to find
            // the commit from `git log`, which is what the SHA was wanted for.
            ("git", .str("unavailable — see ActionRecorder.headerLine")),
            ("device", .str(deviceModelIdentifier())),
            ("os", .str(UIDevice.current.systemVersion)),
            ("project", .str(projectName)),
            ("file", .str(url.lastPathComponent)),
            ("startedAt", .str(ISO8601DateFormatter().string(from: Date())))
        ]
        if let canvasSize {
            fields.append(("canvasW", .num(canvasSize.width)))
            fields.append(("canvasH", .num(canvasSize.height)))
        }
        if let window = WindowEventTap.activeWindow() {
            fields.append(("windowW", .num(window.bounds.width)))
            fields.append(("windowH", .num(window.bounds.height)))
            fields.append(("scale", .num(window.screen.scale)))
        }
        fields.append(("windowClass", .str(tap.originalClass ?? "none")))
        fields.append(("touchCapture", .str(tap.interceptedClass == nil ? "OFF — \(tap.note)" : "on")))
        return ActionRecorder.shared.line("header", fields, at: 0)
    }

    /// The executable's own modification date — the closest thing to a build stamp available without
    /// a build phase. Enough to answer "is this recording from the build I shipped them?".
    private static func buildDateString() -> String {
        guard let exe = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: exe.path),
              let date = attrs[.modificationDate] as? Date else { return "unknown" }
        return ISO8601DateFormatter().string(from: date)
    }

    /// `iPad12,1` rather than "iPad" — `UIDevice.model` cannot tell a 9th-generation iPad from an
    /// M4 Pro, and the difference decides whether a 120 Hz pencil rate is even possible.
    private static func deviceModelIdentifier() -> String {
        #if targetEnvironment(simulator)
        let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown"
        return "Simulator/\(simulated)"
        #else
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw -> String in
            let bytes = raw.prefix(while: { $0 != 0 })
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? UIDevice.current.model : machine
        #endif
    }

    // MARK: - Files on disk

    /// One recording on disk, for the Actions-menu list.
    struct Recording: Identifiable, Hashable {
        let url: URL
        let size: Int
        let created: Date
        var id: URL { url }
        var name: String { url.lastPathComponent }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
    }

    /// `Documents/Recordings/`. A subfolder rather than loose files in `Documents`: the app's own
    /// projects live in `Documents` too (see `ProjectBackupManager.rootDirectory`), and with
    /// `UIFileSharingEnabled` on, the artist now *sees* that folder in Files.app. Recordings mixed in
    /// with their artwork would be an invitation to delete the wrong thing.
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    private static func newRecordingURL() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return directory.appendingPathComponent("recording-\(formatter.string(from: Date())).jsonl")
    }

    func refreshRecordings() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        recordings = urls
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                return Recording(url: url,
                                 size: values?.fileSize ?? 0,
                                 created: values?.creationDate ?? .distantPast)
            }
            .sorted { $0.created > $1.created }
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
        refreshRecordings()
    }
}

// MARK: - The writer

/// Buffers JSONL lines in memory and writes them out in batches on a background queue.
///
/// **Nothing here touches the filesystem on the drawing path.** A three-second stroke at the
/// coalesced 20 Hz is roughly sixty lines; writing each one would be sixty `write(2)` calls
/// interleaved with brush stamping, on the one path this whole app is built to keep clear (see
/// CLAUDE.md and the §5.2 sandwich comments in `CanvasView`). Instead each event appends UTF-8 bytes
/// to an in-memory `Data` — no syscall, no allocation beyond the buffer's amortised growth — and the
/// buffer is handed to a serial queue when it passes `flushThreshold` or when the two-second timer
/// fires, whichever comes first.
///
/// Rejected alternative: writing straight through with `FileHandle.write` and letting the kernel's
/// page cache absorb it. It very nearly works, and it fails exactly where it matters — the write is
/// still a syscall with an unbounded tail latency, and a 30 ms hitch during a stroke would show up in
/// the recording as a gap in the very data being recorded, making the recorder a source of the
/// symptom it exists to explain.
private final class RecordingWriter {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "paintapp.actionrecorder.write", qos: .utility)
    private var buffer = Data(capacity: 64 * 1024)

    /// 32 KB is about two minutes of idle app-state events, or about twenty seconds of continuous
    /// drawing at the coalesced rate — so in practice the timer is what flushes, and this is the
    /// backstop that keeps a frantic repro from growing the buffer without bound.
    private static let flushThreshold = 32 * 1024

    init?(url: URL) {
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { return nil }
        self.handle = handle
    }

    func append(_ line: String) {
        buffer.append(contentsOf: line.utf8)
        buffer.append(0x0A)
        if buffer.count >= Self.flushThreshold { flush() }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        let payload = buffer
        buffer.removeAll(keepingCapacity: true)
        queue.async { [handle] in
            try? handle.write(contentsOf: payload)
        }
    }

    func close() {
        flush()
        queue.async { [handle] in
            try? handle.synchronize()
            try? handle.close()
        }
    }
}
