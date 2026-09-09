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
        /// `celThumbnailImage` — one cel's pixels, inside the flush above. The *render* half of
        /// §11.11c's change, separated from what installing the result costs.
        case thumbnailRender
        /// `PixelOps.rasterize` inside the thumbnail render — the flatten, which walks the cel's
        /// elements and is therefore O(ink) even though its output is bounded at 480².
        case thumbnailFlatten
        /// `ThumbnailRenderer.render` — the 480² tile down to 120².
        case thumbnailDownsample
        /// `installThumbnail` — the two writes that put a rendered tile on `@Published layers`.
        /// **A separate row because `Layer` and `Cel` are structs**: the write copies the layer's
        /// whole cel array, so this is the row that grows with the *document* rather than with the
        /// canvas, and the owner's bar names cels explicitly.
        case thumbnailInstall
        /// `CanvasView.updateUIView`'s chrome half — every overlay update from
        /// `updateActiveLayerAndTool` down, summed. Named because `updateUIView` minus `reconcile`
        /// minus `onionSkin` used to be a remainder a reader had to compute.
        case overlays
        /// `reconcileLayersNow`'s per-layer loop — the visibility/alpha/content sweep that runs once
        /// per layer on every SwiftUI pass, `refreshDisplayIfStale` included.
        case layerHostRows
        /// `TimelineTrackView.updateUIView`, whole — the *second* `UIViewRepresentable` a canvas
        /// pass drives, and one nothing had ever timed.
        case timelineTrack
        /// `TimelineLayoutKey.make` — O(layers × cels), and it reads every cel's thumbnail address,
        /// which is what makes a thumbnail install raise a full track rebuild.
        case timelineKey
        /// The track's rebuild branch: every row, every block view, the ruler's CoreText. Taken only
        /// when `timelineKey` says something moved.
        case timelineRebuild
        /// `LayerStackListView.updateUIView`, whole — the third representable.
        case layerListReload
        /// `DrawingView.body`.
        case bodyDrawing
        /// `AnimationTimeline.body`.
        case bodyTimeline
        /// `LayerPanel.body`.
        case bodyLayerPanel
        /// `TopToolbar.body` and `SideToolbar.body`, together: they are one chrome and neither is
        /// separately actionable.
        case bodyToolbars
        /// `CanvasManager.undo()` / `redo()`, the press itself on the main actor.
        case undoPress
        /// The probe's own stroke commit — `addStroke`, the undo registration, the thumbnail
        /// schedule and the publish. The commit half of what `undoPress` is for the undo half, so
        /// that "the operation" and "the pass it raises" are two rows for all three of the owner's
        /// symptoms rather than for two of them.
        case editCommit
        /// **The main-thread half of an off-thread render landing.** `finishVectorRender`,
        /// `finishOnionRebuild` and `FrameBaker.finish` all hop back to the main actor to install
        /// what a queue produced, and each runs as its own main-queue block inside `sourcePhase` —
        /// so before this row they were exactly the shape of cost a phase table cannot see: our
        /// code, on the main thread, in no instrumented call.
        case renderLanded
        /// Every `draw(_:)` this app implements on the editing path — all five are the timeline
        /// track's (its gridlines, its ruler's CoreText, its blocks). They run at `CALayer` display
        /// time, which is inside `sourcePhase` and after the last `updateUIView` has returned, so
        /// without this row they are invisible to the report by construction.
        case viewDraw
        /// Core Animation's commit, measured between the two `beforeWaiting` observers.
        case caCommit
        /// **The runloop's *source* half of one wake-up** — everything from `afterWaiting` to the
        /// first `beforeWaiting` observer: input sources, timers, `CADisplayLink`, and every block
        /// `DispatchQueue.main.async` has queued. A `PlaybackProbe` operation and the SwiftUI pass
        /// it raises are both in here.
        ///
        /// Structural rather than a cost of its own: with `observerPhase` and `caCommit` it
        /// **partitions** `mainBusy` exactly, so an unattributed remainder can be placed in one of
        /// three halves of the runloop instead of merely being large. Excluded from the attribution
        /// union for that reason — counting it would make every report read 100% attributed while
        /// naming nothing.
        case sourcePhase
        /// **The runloop's *observer* half** — the first `beforeWaiting` observer to Core Animation's
        /// own at order 2,000,000. UIKit's layout pass, `CALayer.display` and every `draw(_:)` this
        /// app implements run here, after the last `updateUIView` has returned and before anything
        /// reaches the screen. Structural, and excluded from attribution, exactly as `sourcePhase`.
        case observerPhase
        /// The main thread busy between two runloop waits. The denominator for everything above.
        ///
        /// **`value` carries the main thread's own CPU microseconds across the same window**, taken
        /// from `thread_info`. Wall clock minus that is time the main thread held the runloop
        /// without running on a core — blocked on a lock, or descheduled — and this app does
        /// ~300 ms of background render work per edit on a two-big-core A13, so the difference
        /// between *"a cost nobody has instrumented"* and *"the main thread could not get a core"*
        /// is a question the report has to be able to answer. It is the same trap the whole file is
        /// built against: a real, reproducible number about the wrong thing.
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

    /// The calling thread's user + system CPU time, in seconds. `mach_thread_self` hands back a
    /// send right, so it is deallocated here — a port leaked once per runloop turn would be this
    /// file's own version of the bug it exists to find.
    static func threadCPUSeconds() -> Double {
        var info = thread_basic_info()
        // `THREAD_BASIC_INFO_COUNT` is a C macro and does not import into Swift; the count is the
        // struct's size in `integer_t`s, which is what the macro spells out.
        var count = mach_msg_type_number_t(
            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6
            + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
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
    private var preWaitObserver: CFRunLoopObserver?
    private var preCommitObserver: CFRunLoopObserver?
    private var postCommitObserver: CFRunLoopObserver?
    /// When the main thread last woke. Main-thread only, so no lock.
    private var busySince: CFTimeInterval?
    /// The main thread's CPU seconds when it last woke — see `Phase.mainBusy`'s `value`.
    private var busyCPUSince: Double?
    /// When this wake-up stopped running sources and started running `beforeWaiting` observers.
    private var preWaitAt: CFTimeInterval?
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
            self?.busyCPUSince = Self.threadCPUSeconds()
        }
        // **First in the `beforeWaiting` order, so it marks where the sources stop and the
        // observers start.** Everything UIKit and SwiftUI do to lay out and draw a pass runs between
        // this and Core Animation's commit; without this mark that whole half of a stall is a gap in
        // the report with no name, which is what it was until 2026-09-09.
        let preWait = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, true, -2_000_000
        ) { [weak self] _, _ in
            guard let self, let since = self.busySince else { return }
            let now = CACurrentMediaTime()
            self.append(.sourcePhase, start: since, end: now, value: 0)
            self.preWaitAt = now
        }
        let pre = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, true, Self.caCommitObserverOrder - 1_000
        ) { [weak self] _, _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if let waitStart = self.preWaitAt {
                self.append(.observerPhase, start: waitStart, end: now, value: 0)
                self.preWaitAt = nil
            }
            self.preCommitAt = now
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
                let cpu = Self.threadCPUSeconds() - (self.busyCPUSince ?? Self.threadCPUSeconds())
                self.append(.mainBusy, start: since, end: now,
                            value: Int((cpu * 1_000_000).rounded()))
                self.busySince = nil
                self.busyCPUSince = nil
            }
        }

        for observer in [busy, preWait, pre, post] {
            guard let observer else { continue }
            CFRunLoopAddObserver(loop, observer, CFRunLoopMode.commonModes)
        }
        busyObserver = busy
        preWaitObserver = preWait
        preCommitObserver = pre
        postCommitObserver = post
    }

    @MainActor
    private func removeObservers() {
        let loop = CFRunLoopGetMain()
        for observer in [busyObserver, preWaitObserver, preCommitObserver, postCommitObserver] {
            guard let observer else { continue }
            CFRunLoopRemoveObserver(loop, observer, CFRunLoopMode.commonModes)
        }
        busyObserver = nil
        preWaitObserver = nil
        preCommitObserver = nil
        postCommitObserver = nil
        busySince = nil
        busyCPUSince = nil
        preWaitAt = nil
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
        /// Of `mainBusyMs`, the part the main thread actually spent on a core.
        let mainCpuMs: Double
        let phaseMs: [String: Double]
        let ringHits: Int
        let ringMisses: Int
        /// **Main-thread busy this interval that no named span covers**, in milliseconds.
        ///
        /// Not "busy minus the sum of the phases": spans nest — `renderTree` is inside `reconcile`
        /// is inside `updateUIView` — so a sum triple-counts and can exceed the busy it is a share
        /// of. This is `mainBusy` minus the **union of the intervals** every main-thread span
        /// occupies, which is the same number a flame graph would call the self time of everything
        /// this app did not instrument, and it is correct whatever the nesting turns out to be.
        ///
        /// It is the row this whole file exists to force into the open: a report whose largest term
        /// is this one has not found the cost yet, and says so instead of implying an answer from
        /// whichever named span happens to be biggest.
        let unattributedMs: Double
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

    /// **The three phases that partition `mainBusy` rather than explaining it.** They are measured
    /// the same way and printed in the same table, but counting them as *attributed* would make
    /// every report read 100% explained while naming nothing — see `sourcePhase`.
    static let structuralPhases: Set<Phase> = [.mainBusy, .sourcePhase, .observerPhase]

    struct Report {
        let seconds: Double
        let eventCount: Int
        let overflowed: Bool
        let ticks: [TickSummary]
        let phases: [PhaseSummary]
        /// The whole run's version of `TickSummary.unattributedMs`, and the three numbers it is
        /// derived from, so a reader can check the arithmetic rather than trust it.
        let mainBusyMs: Double
        /// Of `mainBusyMs`, the part spent on a core rather than blocked or descheduled.
        let mainCpuMs: Double
        let attributedMs: Double
        let unattributedMs: Double
    }

    /// **The total length of `spans`' union, clipped to `windows`.** Both arrays are (start, end)
    /// pairs in `CACurrentMediaTime`'s clock.
    ///
    /// The union rather than the sum is the whole point — see `TickSummary.unattributedMs`. It is
    /// also why this is a free function over intervals instead of arithmetic on `PhaseSummary`:
    /// summaries have lost the timestamps by the time they exist.
    private static func coveredMs(_ spans: [(Double, Double)],
                                  within windows: [(Double, Double)]) -> Double {
        guard !spans.isEmpty, !windows.isEmpty else { return 0 }
        var merged: [(Double, Double)] = []
        for span in spans.sorted(by: { $0.0 < $1.0 }) where span.1 > span.0 {
            if var last = merged.last, span.0 <= last.1 {
                last.1 = max(last.1, span.1)
                merged[merged.count - 1] = last
            } else {
                merged.append(span)
            }
        }
        var total = 0.0
        for window in windows {
            for span in merged where span.1 > window.0 && span.0 < window.1 {
                total += min(span.1, window.1) - max(span.0, window.0)
            }
        }
        return total * 1000
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
            var busy = 0.0, cpu = 0.0
            var hits = 0, misses = 0
            var bursts: [(atMs: Double, ms: Double)] = []
            // Attributed by start time to the tick that most recently preceded it, which is what
            // makes an off-main span (a bake composite, a store decode on the baker's queue) land in
            // the interval it was actually running through rather than in the one that started it.
            var cursor = index
            var busyWindows: [(Double, Double)] = []
            var namedSpans: [(Double, Double)] = []
            while cursor < sorted.count, sorted[cursor].start < nextStart {
                let event = sorted[cursor]
                let isThisTick = cursor == index
                cursor += 1
                guard event.phase != .tick || isThisTick else { continue }
                let ms = (event.end - event.start) * 1000
                phaseMs[event.phase.rawValue, default: 0] += ms
                if event.phase == .mainBusy {
                    busy += ms
                    cpu += Double(event.value) / 1000
                    busyWindows.append((event.start, event.end))
                    if ms >= Self.burstFloorMs {
                        bursts.append((atMs: (event.start - tick.start) * 1000, ms: ms))
                    }
                } else if event.onMain, event.phase != .tick,
                          !Self.structuralPhases.contains(event.phase) {
                    // `caCommit` counts as attributed: it is measured, not inferred, and calling
                    // Core Animation's own commit "unattributed" would be the one wrong answer this
                    // remainder must never give.
                    namedSpans.append((event.start, event.end))
                }
                if event.phase == .bakeRead { event.value == 1 ? (hits += 1) : (misses += 1) }
            }
            let interval = nextStart.isFinite ? (nextStart - tick.start) * 1000 : 0
            let covered = Self.coveredMs(namedSpans, within: busyWindows)
            tickSummaries.append(TickSummary(frame: tick.value,
                                             atSeconds: tick.start - startedAt,
                                             intervalMs: interval,
                                             mainBusyMs: busy,
                                             mainCpuMs: cpu,
                                             phaseMs: phaseMs,
                                             ringHits: hits, ringMisses: misses,
                                             unattributedMs: max(busy - covered, 0),
                                             bursts: bursts))
        }

        let summaries = Self.summarize(sorted)

        let busyWindows = sorted.filter { $0.phase == .mainBusy }.map { ($0.start, $0.end) }
        let namedSpans = sorted.filter { $0.onMain && $0.phase != .tick
                                             && !Self.structuralPhases.contains($0.phase) }
            .map { ($0.start, $0.end) }
        let busyMs = busyWindows.reduce(0.0) { $0 + ($1.1 - $1.0) } * 1000
        let cpuMs = sorted.filter { $0.phase == .mainBusy }
            .reduce(0.0) { $0 + Double($1.value) } / 1000
        let attributed = Self.coveredMs(namedSpans, within: busyWindows)

        let span = (sorted.last?.end ?? startedAt) - startedAt
        return Report(seconds: span, eventCount: events.count, overflowed: overflowed,
                      ticks: tickSummaries, phases: summaries,
                      mainBusyMs: busyMs, mainCpuMs: cpuMs, attributedMs: attributed,
                      unattributedMs: max(busyMs - attributed, 0))
    }

    /// **One main-thread stall, opened up: what ran inside it, in order, with the gaps left in.**
    ///
    /// A phase table says *how much* is unattributed; it cannot say *where*. These two are different
    /// diagnoses and only the second is actionable — 20 ms of nothing **before** the first
    /// instrumented call is SwiftUI deciding what to update, the same 20 ms **after** the last one is
    /// UIKit laying out and Core Animation displaying, and they have no fix in common.
    ///
    /// Only *top-level* spans are listed — a span wholly inside another is its parent's business —
    /// so the gaps between consecutive entries are real uninstrumented time rather than an artefact
    /// of nesting.
    struct BurstDetail {
        let atSeconds: Double
        let ms: Double
        /// `(phase, offset from the burst's start in ms, duration in ms)`, in order.
        let spans: [(phase: String, atMs: Double, ms: Double)]
        /// Uninstrumented milliseconds before the first span, between spans, and after the last.
        let leadMs: Double
        let gapMs: Double
        let tailMs: Double
        /// This stall's own `sourcePhase` / `observerPhase` / `caCommit` split, which partitions
        /// `ms` — so a large `tailMs` can be read as *"UIKit laid out and drew"* rather than left
        /// as *"something happened after our last span"*.
        let sourceMs: Double
        let observerMs: Double
        let commitMs: Double
        /// Of `ms`, the part the main thread spent on a core.
        let cpuMs: Double
    }

    /// The `count` longest main-thread bursts of the run, opened up. Bounded because a report is
    /// read by a person: the longest dozen is a diagnosis, and every burst is a log file.
    func longestBursts(_ count: Int = 40) -> [BurstDetail] {
        lock.lock()
        let events = self.events
        lock.unlock()
        let sorted = events.sorted { $0.start < $1.start }
        let busy = sorted.filter { $0.phase == .mainBusy }
            .sorted { ($0.end - $0.start) > ($1.end - $1.start) }
            .prefix(count)

        return busy.map { window in
            let inside = sorted.filter {
                $0.onMain && $0.phase != .tick && !Self.structuralPhases.contains($0.phase)
                    && $0.start >= window.start && $0.end <= window.end && $0.end > $0.start
            }
            // Top level = not contained in an earlier, longer span. `inside` is start-ordered, so a
            // container always precedes what it contains.
            var top: [Event] = []
            for event in inside where !top.contains(where: { $0.start <= event.start && $0.end >= event.end }) {
                top.append(event)
            }
            var lead = 0.0, gap = 0.0, tail = 0.0
            if let first = top.first, let last = top.last {
                lead = (first.start - window.start) * 1000
                tail = (window.end - last.end) * 1000
                var cursor = first.end
                for event in top.dropFirst() {
                    if event.start > cursor { gap += (event.start - cursor) * 1000 }
                    cursor = max(cursor, event.end)
                }
            } else {
                lead = (window.end - window.start) * 1000
            }
            func structural(_ phase: Phase) -> Double {
                sorted.filter { $0.phase == phase && $0.start >= window.start - 0.0005
                                && $0.end <= window.end + 0.0005 }
                    .reduce(0.0) { $0 + ($1.end - $1.start) } * 1000
            }
            return BurstDetail(atSeconds: window.start - startedAt,
                               ms: (window.end - window.start) * 1000,
                               spans: top.map { (phase: $0.phase.rawValue,
                                                 atMs: ($0.start - window.start) * 1000,
                                                 ms: ($0.end - $0.start) * 1000) },
                               leadMs: lead, gapMs: gap, tailMs: tail,
                               sourceMs: structural(.sourcePhase),
                               observerMs: structural(.observerPhase),
                               commitMs: structural(.caCommit),
                               cpuMs: Double(window.value) / 1000)
        }
    }

    /// Nearest-rank on a sorted array. Empty is 0 rather than a trap — a report is a diagnostic and
    /// must not be the thing that crashes the run it is describing.
    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((q * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}
