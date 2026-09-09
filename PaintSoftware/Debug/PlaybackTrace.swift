import Foundation
import QuartzCore

/// **What a frame of playback actually spends, on the device, broken down by phase.**
///
/// ## Why this exists
///
/// `ActionRecorder` could say that the playhead moved and nothing else. The owner's report of
/// 2026-09-08 — an ordinary two-frame document playing at ~5 fps on their iPad 9 — was diagnosable
/// only because `currentFrame` happens to be a logged model key, so the *interval* between flips was
/// recoverable and nothing about the *cost inside* one was. Two passes then argued about which of
/// four candidate costs it was, on a Mac, and shipped a fix that changed the device number by
/// nothing at all (PERFORMANCE.md §16, §17). A recording that explains itself is what stops that
/// happening a third time.
///
/// ## The one measurement that makes it a diagnosis rather than a list
///
/// Summing named spans answers *"what did the code I instrumented cost"*, which is the question that
/// keeps giving the wrong answer here: on this path the dominant cost is not in any function this
/// app wrote. So the runloop is measured too, by two observers rather than one:
///
/// - `.afterWaiting` starts a **main-thread busy** span — everything the main thread does between
///   two waits, whether or not it is inside an instrumented call.
/// - `.beforeWaiting` at order `1_999_000` marks the instant **before** Core Animation's own commit
///   observer (which registers at order 2_000_000), and a second `.beforeWaiting` at order
///   `2_100_000` marks the instant after it.
///
/// So `caCommit` is measured directly rather than inferred, and `unattributed` — busy minus every
/// named span minus the commit — is the honest name for whatever is left. A phase table whose
/// biggest row is `unattributed` is a table that has not found the cost yet, and says so.
///
/// ## Cost when off
///
/// One `Bool` load per call site. `isOn` is a plain static, read before anything else happens, and
/// every entry point returns immediately on false. Nothing is allocated, no lock is taken, and no
/// observer is installed until `start()`.
final class PlaybackTrace: @unchecked Sendable {

    // MARK: - The switch

    /// **Read on every instrumented call and written only by `start`/`stop`.** A plain static rather
    /// than a computed property or an actor-isolated field so that the off case is a load and a
    /// branch: this sits inside `refreshDisplay` and the frame-bake read path, both of which run on
    /// every SwiftUI pass of an idle canvas.
    nonisolated(unsafe) private(set) static var isOn = false

    static let shared = PlaybackTrace()

    // MARK: - Phases

    /// **One case per cost a frame flip can carry, and each is here because something measured it.**
    ///
    /// The names are the report's keys, so they are short and stable — a recording read six months
    /// from now is compared against one taken today by these strings.
    enum Phase: String, CaseIterable {
        /// **The anchor every interval in a report is measured between.** During playback it is
        /// `CanvasManager.tickPlayback`'s frame flip; in `PlaybackProbe`'s edit mode it is the
        /// instant one measured operation — a stroke commit, an undo press — begins. One case
        /// rather than two because the report machinery below asks the same question of both:
        /// *how did the main thread spend the interval that followed this?*
        case tick
        /// `CanvasView.updateUIView`, whole — every `Coordinator` pass the editor makes, of which
        /// `reconcile` is one. The gap between the two is the overlays.
        case updateUIView
        /// `CanvasView.Coordinator.reconcileLayers`, whole.
        case reconcile
        /// `updateOnionSkin` — the ghost of the neighbouring frames.
        case onionSkin
        /// `OnionSkinSource.frames(for:)` — gathering and reducing the neighbouring cels.
        case onionFrames
        /// `OnionSkinFrame.composite` — flattening those frames into the one displayed image. A
        /// skin-sized `UIGraphicsImageRenderer` and one draw per skin, on the main thread.
        case onionComposite
        /// `OnionSkinClip.mask` — the Behind placement's two skin-sized draws.
        case onionClip
        /// `CanvasManager.onionSkinInkToSubtract` — the reduced render of the artist's *own* layer
        /// that the Behind placement subtracts. It misses its memo on every edit, so this is the
        /// per-stroke half of the onion skin's cost where `onionComposite` is the per-flip half.
        case onionInk
        /// `resolveLiveMask` inside `updateOnionSkin` — §6.4's coverage for the current layer.
        case onionMask
        /// `updateInterpolationPreviews` — TODO (53)'s posed and interpolated pictures.
        case derivedPreview
        /// `CanvasManager.renderTree(atFrame:)`, which `reconcileLayers` derives once a pass.
        case renderTree
        /// The dirty sweep and the baker kick — `CanvasManager.syncFrameBake`.
        case syncBake
        /// `updateSandwich`, whole: the key, the bake read, and the view assignments.
        case updateSandwich
        /// `CanvasView.Coordinator.makeSandwichKey` — O(layers) content versions.
        case sandwichKey
        /// `FrameBaker.currentKey(atFrame:)` — the recipe mint plus the digest.
        case bakeKeyMint
        /// `FrameBaker.image(for:)`, whole. `value` is 1 for a ring hit and 0 for a store read, so
        /// the ring's hit rate is recoverable from the report without a second counter.
        case bakeRead
        /// `FrameBakeStore.loadDecoded` — the file read and the LZ4 decode. RENDER §3.5 rules that
        /// play never does this on the display thread, so `onMain` is the assertion this carries.
        case storeDecode
        /// `DecodedFrame.makeImage()` plus the `UIImage` wrap.
        case bakeImageWrap
        /// One canvas-sized vector rasterize — `VectorCanvas.render`. The flat row's per-layer,
        /// per-flip cost, and the thing the composite path exists to stop paying.
        case vectorRasterize
        /// A sandwich half-pair composite, off the main thread.
        case sandwichComposite
        /// The baker compositing one frame, off the main thread.
        case bakeComposite
        /// The baker encoding and writing one frame.
        case bakeWrite
        /// `CanvasManager.flushPendingThumbnailRegens` — the 400 ms debounced cel thumbnail.
        case thumbnailFlush
        /// `CanvasManager.undo()` / `redo()`, the press itself on the main actor.
        case undoPress
        /// Core Animation's commit, measured between the two `beforeWaiting` observers.
        case caCommit
        /// The main thread busy between two runloop waits. The denominator for everything above.
        case mainBusy
    }

    // MARK: - Records

    /// One span or mark. A value, appended under the lock and never mutated afterwards.
    private struct Event {
        let phase: Phase
        let start: CFTimeInterval
        let end: CFTimeInterval
        let value: Int
        let onMain: Bool
    }

    private let lock = NSLock()
    private var events: [Event] = []
    private var startedAt: CFTimeInterval = 0

    /// **A ceiling, so a probe left running cannot become the memory bug it is measuring.** At the
    /// rates this records — a few dozen events a flip — 200,000 is well over an hour of playback.
    /// Past it the recorder stops appending rather than dropping the beginning: the first minute of
    /// a run is the part with the transient in it.
    private static let eventCeiling = 200_000
    private var overflowed = false

    // MARK: - Lifecycle

    /// Arms the recorder and installs the two runloop observers. Idempotent.
    ///
    /// **Main thread only**, because the observers are added to the main runloop and because
    /// `isOn` has no memory barrier — arming it from one thread while another is mid-span would be
    /// a span with one end.
    @MainActor
    func start() {
        guard !Self.isOn else { return }
        lock.lock()
        events.removeAll(keepingCapacity: true)
        overflowed = false
        startedAt = CACurrentMediaTime()
        lock.unlock()
        installObservers()
        Self.isOn = true
    }

    /// Disarms and removes the observers. The events stay until the next `start()`.
    @MainActor
    func stop() {
        guard Self.isOn else { return }
        Self.isOn = false
        removeObservers()
    }

    // MARK: - Recording

    /// Times `body` and records it as `phase`. Returns whatever `body` returns.
    ///
    /// **The `isOn` test is outside the timing calls**, so an unarmed build pays a load, a branch
    /// and the closure call the optimiser is free to inline away — not two `CACurrentMediaTime`s.
    @inline(__always)
    static func span<T>(_ phase: Phase, value: Int = 0, _ body: () throws -> T) rethrows -> T {
        guard isOn else { return try body() }
        let start = CACurrentMediaTime()
        defer { shared.append(phase, start: start, end: CACurrentMediaTime(), value: value) }
        return try body()
    }

    /// A zero-duration event — the tick, and anything else that is an instant rather than a span.
    @inline(__always)
    static func mark(_ phase: Phase, value: Int = 0) {
        guard isOn else { return }
        let now = CACurrentMediaTime()
        shared.append(phase, start: now, end: now, value: value)
    }

    private func append(_ phase: Phase, start: CFTimeInterval, end: CFTimeInterval, value: Int) {
        let onMain = Thread.isMainThread
        lock.lock()
        if events.count < Self.eventCeiling {
            events.append(Event(phase: phase, start: start, end: end, value: value, onMain: onMain))
        } else {
            overflowed = true
        }
        lock.unlock()
    }

    // MARK: - The runloop observers

    private var busyObserver: CFRunLoopObserver?
    private var preCommitObserver: CFRunLoopObserver?
    private var postCommitObserver: CFRunLoopObserver?
    /// When the main thread last woke. Main-thread only, so no lock.
    private var busySince: CFTimeInterval?
    private var preCommitAt: CFTimeInterval?

    /// Core Animation's transaction-commit observer registers on the main runloop at
    /// `kCFRunLoopBeforeWaiting` with order 2_000_000. Bracketing it is what turns "the rest of the
    /// time" into a named row.
    private static let caCommitObserverOrder: CFIndex = 2_000_000

    @MainActor
    private func installObservers() {
        let loop = CFRunLoopGetMain()

        let busy = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.afterWaiting.rawValue, true, -2_000_000
        ) { [weak self] _, _ in
            self?.busySince = CACurrentMediaTime()
        }
        let pre = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, true, Self.caCommitObserverOrder - 1_000
        ) { [weak self] _, _ in
            self?.preCommitAt = CACurrentMediaTime()
        }
        let post = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, true, Self.caCommitObserverOrder + 100_000
        ) { [weak self] _, _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if let pre = self.preCommitAt {
                self.append(.caCommit, start: pre, end: now, value: 0)
                self.preCommitAt = nil
            }
            if let since = self.busySince {
                self.append(.mainBusy, start: since, end: now, value: 0)
                self.busySince = nil
            }
        }

        for observer in [busy, pre, post] {
            guard let observer else { continue }
            CFRunLoopAddObserver(loop, observer, CFRunLoopMode.commonModes)
        }
        busyObserver = busy
        preCommitObserver = pre
        postCommitObserver = post
    }

    @MainActor
    private func removeObservers() {
        let loop = CFRunLoopGetMain()
        for observer in [busyObserver, preCommitObserver, postCommitObserver] {
            guard let observer else { continue }
            CFRunLoopRemoveObserver(loop, observer, CFRunLoopMode.commonModes)
        }
        busyObserver = nil
        preCommitObserver = nil
        postCommitObserver = nil
        busySince = nil
        preCommitAt = nil
    }

    // MARK: - The report

    /// One phase's shape across the run. Milliseconds throughout, because the budget this is read
    /// against — 41.7 ms at 24 fps — is in milliseconds.
    struct PhaseSummary {
        let phase: String
        let count: Int
        let onMainCount: Int
        let totalMs: Double
        let meanMs: Double
        let p50Ms: Double
        let p90Ms: Double
        let maxMs: Double
    }

    /// One flip: when it happened, which frame it landed on, and how the main thread spent the
    /// interval that followed it.
    struct TickSummary {
        let frame: Int
        let atSeconds: Double
        let intervalMs: Double
        let mainBusyMs: Double
        let phaseMs: [String: Double]
        let ringHits: Int
        let ringMisses: Int
        /// **The individual main-thread stalls, in order, as (offset from the anchor, duration).**
        /// A per-interval total cannot answer *"the ms per frame flicker **twice** after I lift the
        /// brush"* — one 120 ms stall and four 30 ms ones sum the same and are different bugs. Only
        /// spans at or over `burstFloorMs` are listed, so an idle interval carries none.
        let bursts: [(atMs: Double, ms: Double)]
    }

    /// A main-thread stall the artist could plausibly see, in milliseconds. One 60 Hz frame is
    /// 16.7 ms; this is a little over half of one, so a listed burst is at minimum a dropped frame's
    /// worth of work and the list stays short enough to read.
    static let burstFloorMs = 10.0

    struct Report {
        let seconds: Double
        let eventCount: Int
        let overflowed: Bool
        let ticks: [TickSummary]
        let phases: [PhaseSummary]
    }

    /// **What the main thread did since the last call, emptying the buffer as it goes.**
    ///
    /// `ActionRecorder`'s spelling, where `report()` is `PlaybackProbe`'s, and the two never run in
    /// one process: `start()` has exactly one owner per launch — the probe when `-playbackProbe` is
    /// armed, the recorder otherwise. Draining is the point rather than an optimisation. A recording
    /// is minutes long and a report over the whole of it would sort every event on every flush; a
    /// window is the last two seconds, which is also the thing a reader of a JSONL file wants beside
    /// the touches that produced it.
    ///
    /// `ringHits`/`ringMisses` come out of `bakeRead`'s value, and a non-zero `vectorRasterize`
    /// count is the operational form of *"the canvas is not showing the bake"* — a canvas that is
    /// engaged rasterizes nothing per flip (PERFORMANCE.md §16.2), so the count answers the question
    /// without the recorder needing a reference to `CanvasManager`, which by design it does not have.
    func drainWindow() -> (phases: [PhaseSummary], ringHits: Int, ringMisses: Int) {
        lock.lock()
        let events = self.events
        self.events.removeAll(keepingCapacity: true)
        overflowed = false
        lock.unlock()
        guard !events.isEmpty else { return ([], 0, 0) }

        var hits = 0, misses = 0
        for event in events where event.phase == .bakeRead {
            event.value == 1 ? (hits += 1) : (misses += 1)
        }
        return (Self.summarize(events), hits, misses)
    }

    /// One `PhaseSummary` per phase present in `events`, ordered by total time descending.
    private static func summarize(_ events: [Event]) -> [PhaseSummary] {
        var summaries: [PhaseSummary] = []
        for phase in Phase.allCases {
            let matching = events.filter { $0.phase == phase }
            guard !matching.isEmpty else { continue }
            let durations = matching.map { ($0.end - $0.start) * 1000 }.sorted()
            let total = durations.reduce(0, +)
            summaries.append(PhaseSummary(phase: phase.rawValue,
                                          count: matching.count,
                                          onMainCount: matching.filter(\.onMain).count,
                                          totalMs: total,
                                          meanMs: total / Double(durations.count),
                                          p50Ms: percentile(durations, 0.50),
                                          p90Ms: percentile(durations, 0.90),
                                          maxMs: durations.last ?? 0))
        }
        return summaries.sorted { $0.totalMs > $1.totalMs }
    }

    /// Builds the report from whatever has been recorded. Safe to call after `stop()`.
    func report() -> Report {
        lock.lock()
        let events = self.events
        let startedAt = self.startedAt
        let overflowed = self.overflowed
        lock.unlock()

        let sorted = events.sorted { $0.start < $1.start }
        let ticks = sorted.enumerated().filter { $0.element.phase == .tick }

        var tickSummaries: [TickSummary] = []
        for (position, entry) in ticks.enumerated() {
            let (index, tick) = entry
            let nextStart = position + 1 < ticks.count ? ticks[position + 1].element.start : .infinity
            var phaseMs: [String: Double] = [:]
            var busy = 0.0
            var hits = 0, misses = 0
            var bursts: [(atMs: Double, ms: Double)] = []
            // Attributed by start time to the tick that most recently preceded it, which is what
            // makes an off-main span (a bake composite, a store decode on the baker's queue) land in
            // the interval it was actually running through rather than in the one that started it.
            var cursor = index
            while cursor < sorted.count, sorted[cursor].start < nextStart {
                let event = sorted[cursor]
                let isThisTick = cursor == index
                cursor += 1
                guard event.phase != .tick || isThisTick else { continue }
                let ms = (event.end - event.start) * 1000
                phaseMs[event.phase.rawValue, default: 0] += ms
                if event.phase == .mainBusy {
                    busy += ms
                    if ms >= Self.burstFloorMs {
                        bursts.append((atMs: (event.start - tick.start) * 1000, ms: ms))
                    }
                }
                if event.phase == .bakeRead { event.value == 1 ? (hits += 1) : (misses += 1) }
            }
            let interval = nextStart.isFinite ? (nextStart - tick.start) * 1000 : 0
            tickSummaries.append(TickSummary(frame: tick.value,
                                             atSeconds: tick.start - startedAt,
                                             intervalMs: interval,
                                             mainBusyMs: busy,
                                             phaseMs: phaseMs,
                                             ringHits: hits, ringMisses: misses,
                                             bursts: bursts))
        }

        let summaries = Self.summarize(sorted)

        let span = (sorted.last?.end ?? startedAt) - startedAt
        return Report(seconds: span, eventCount: events.count, overflowed: overflowed,
                      ticks: tickSummaries, phases: summaries)
    }

    /// Nearest-rank on a sorted array. Empty is 0 rather than a trap — a report is a diagnostic and
    /// must not be the thing that crashes the run it is describing.
    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((q * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}
