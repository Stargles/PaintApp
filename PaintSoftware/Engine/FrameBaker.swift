import UIKit
import SwiftUI

// MARK: - The serial baker (RENDER.md §3.6)
//
// One main-actor scheduler joins content keys, the disposable disk store, the bounded decoded
// ring and frozen frame recipes. BakeQueue retains every dirty frame. LatestWins serializes each
// inspection/mint, off-main bake/read and main-thread landing, including reset/close cancellation.
// Coalescing requests to inspect the dirty set never discards a frame from it.

/// The background frame baker: one serial worker that keeps the store in step with the document.
///
/// Owns the `[String: Set<Int>]` digest→frames map that `FrameBakeStore.store` and
/// `FrameBakeStore.evict` take for playhead-distance eviction. Nothing else knows it — the store
/// sees file names and the queue sees frame numbers, and only this type sees both.
@MainActor
final class FrameBaker {

    // MARK: - Wiring

    /// **Weak, because `CanvasManager` owns this.** The baker reads the model on the
    /// main actor and nowhere else; every value it hands the worker queue was frozen at mint time
    /// (`FrameRecipe`, RENDER §3.2), so the queue holds no reference to anything the artist can edit.
    private weak var manager: CanvasManager?

    let store: FrameBakeStore
    let ring: DecodedFrameRing

    /// `qos: .utility`, one step below `sandwichQueue`'s `.userInitiated`, and that ordering is the
    /// whole of §2's *"this should not interfere with the FPS of the user interface"*: the live
    /// canvas is what the artist is looking at, and the bake is work for a play button that has not
    /// been pressed yet.
    private let jobs: LatestWins

    /// The memory ceiling a single frame's composite may use. `ChunkedCompositor` cuts the walk to
    /// fit it (§3.4); it is a property rather than a constant so a test can force a narrow chunk
    /// width without a second code path.
    var budgetBytes: Int = CompositorBudget.textureBudgetBytes

    /// **How long every composite waits first, on the worker queue** — zero on every ordinary launch,
    /// and set only by `UITestSeeds.applyBakeDelayIfRequested` (`-uiTestSlowBakeMillis`, simulator
    /// only).
    ///
    /// The owner's iPad composites a frame of one vector layer under two transformation layers in
    /// 334–365 ms (MEASURED, TODO 145) and a simulator in a few, so what the canvas shows between an
    /// edit and its bake — the wait `SandwichPresentation.live` exists for — is a window a test
    /// cannot see into on the machine it runs on. This widens it, and only it: the sleep is on
    /// `workQueue`, read at mint time with the rest of the job's values, so the main thread and the
    /// live canvas's own rebuilds are untouched.
    static var compositeDelay: TimeInterval = 0

    /// How far ahead of the playhead a baked frame is also decoded into the ring.
    ///
    /// §3.5: *"A small decoded ring holds the frames just ahead of the playhead… Play never decodes
    /// on the display thread."* Frames further away than this are on disk and nothing more; the tick
    /// that reaches one falls back to §2.10's previous picture until the ring catches up. One second
    /// at the default rate, which is what a play button pressed *now* needs resident *now*.
    var ringLookahead: Int = 24

    /// Which way the playhead is travelling — `BakeQueue`'s band 2. `.forward` during playback and
    /// at rest; `CanvasManager.syncFrameBake` sets `.backward` when the playhead moved backwards.
    var playbackDirection: BakeQueue.Direction = .forward

    /// **Which size of a baked frame the canvas draws from right now** — `.half` while the window
    /// shows the canvas at no more than half its pixels (fit zoom on a big canvas), `.full` when it is
    /// magnified past that. The canvas sets it as it zooms. Reads, the ring's top-up and a bake's own
    /// ring fill all follow it, so a step at fit zoom decodes a quarter of the bytes.
    var displayLevel: BakeLevel = .full {
        didSet {
            guard displayLevel != oldValue, !isClosed else { return }
            ringWalk = nil
            topUpRing()
        }
    }

    /// A baked frame in memory, and the size it is. A canvas that wants `.half` is handed `.full` when
    /// that is what is resident (sharper, never less); one that wants `.full` is never handed `.half`.
    struct BakedPicture {
        let image: CGImage
        let level: BakeLevel
    }

    /// **True while the artist's hand is down**, and the one thing that stops the loop starting a
    /// frame it has every other reason to start.
    ///
    /// A dab bumps `VectorCanvas.version` (`syncDirty` below reads exactly those counters), so a
    /// sweep taken mid-stroke sees the artist's frame move on *every* pass. Baking it would
    /// composite a picture the artist is in the middle of replacing — against §2's *"this should not
    /// interfere with the FPS of the user interface"*, and worse than merely wasted, because each
    /// intermediate version mints its own `PixelOps.rasterize` memo entry that nothing will ever ask
    /// for again and evicts the entries the live canvas is using.
    ///
    /// **The dirty set still accumulates while this is set** — this suspends the *loop*, it does not
    /// discard a request (§3.6). The `kick` that `CanvasManager.syncFrameBake` makes on the pass
    /// after lift is what starts the bake of the stroke that just landed; there is deliberately no
    /// `didSet` here, because that same caller always kicks and a second kick nothing reaches is the
    /// kind of half-live mechanism §2.15 rules out.
    var isSuspended = false

    // MARK: - The export's virtual playhead (RENDER §3.9, stage 6)

    /// Which frame an export is standing on, and the range it is walking.
    ///
    /// See `exportFocus` for why this is one field rather than a second queue.
    struct ExportFocus: Equatable {
        var frame: Int
        var range: ClosedRange<Int>
    }

    /// **While this is set the loop orders frames around it instead of around the artist's
    /// playhead**, and that is the whole of what stage 6 needed from the scheduler.
    ///
    /// An export walks 1..N; `BakeQueue`'s order is *"the frame the artist is on, then ahead in the
    /// play direction, then outward"*. Those look like different orders and are the same one seen
    /// from a different place to stand — which `BakeQueue` already anticipates, because `next` is a
    /// pure function of the playhead it is handed and *"an artist scrubbing the timeline therefore
    /// reorders the whole queue at no cost"*. **An export is a scrub.** So it substitutes its own
    /// cursor here and band 1 gives it the frame it is blocked on while band 2 prebakes the frames
    /// it is about to ask for.
    ///
    /// Two things follow for free rather than being built:
    ///
    ///  - The same local `playhead` is what `kick` hands to `FrameBakeStore.store(…, playhead:)`,
    ///    whose eviction policy is *"the files farthest from the playhead go first"* — so a long
    ///    export drops what it has already written rather than what it is about to read.
    ///  - `topUpRing` warms the decoded ring around the cursor, not around the artist.
    ///
    /// **Nothing about the interactive path changes**: this is nil unless an export is live, and it
    /// is `endExport`'s job to make sure that stays true even when one fails. The `range` also
    /// replaces the loop markers in band 2, because playback's range and the export's are different
    /// questions — an artist can export a document whose loop markers cover four frames of it.
    var exportFocus: ExportFocus?

    /// Points the loop at `frame` and marks it, for an export blocked on it.
    ///
    /// `frameCount` first, and that ordering is load-bearing: `BakeQueue.markDirty` clamps into
    /// `0..<frameCount`, so marking before the count is set on a baker that has never kicked drops
    /// the request silently and the export waits for a frame nothing will ever bake.
    func requestExport(frame: Int, within range: ClosedRange<Int>) {
        guard let manager else { return }
        bakeQueue.frameCount = manager.contentEndFrame
        exportFocus = ExportFocus(frame: frame, range: range)
        bakeQueue.markDirty(frame: frame)
        kick()
    }

    /// Hands the loop back to the artist's playhead. Safe to call when no export is running.
    func endExport() {
        guard exportFocus != nil else { return }
        exportFocus = nil
        kick()
    }

    // MARK: - Scheduling state

    /// The dirty set. `private(set)` so a test can read `pendingCount` without being able to mark.
    private(set) var bakeQueue = BakeQueue()

    /// **Mutual exclusion, not a slot.** True from the moment a job is handed to `workQueue` until
    /// its result lands back on the main actor. Never two composites at once, which is what "one
    /// serial baker" means and what keeps the peak memory to one frame's chunk width.
    var isBaking: Bool { jobs.isBusy }

    /// Closing detaches the model permanently; a reopened canvas gets a fresh owner.
    var isClosed: Bool { manager == nil }

    /// Called on the main actor the moment the loop has nothing left — no dirty frame, and no cold
    /// frame inside the ring's lookahead — having drained and stopped rather than spun. Tests wait on
    /// it; the app does not, and a walk that failed to terminate is a hung expectation there.
    var onIdle: (() -> Void)?

    /// What a frame-finished report says about its frame.
    enum FrameReadiness: Equatable {
        /// The loop visited it: its file is on disk, or the write failed and the frame is marked
        /// clean — either way the loop is done with it.
        case baked
        /// A ring top-up decoded its file into memory, so the next read of it is a hit.
        case resident
    }

    /// One consumer's interest in "a frame landed", held weakly by whoever registered it.
    private struct FrameObserver {
        weak var owner: AnyObject?
        let body: (Int, FrameReadiness) -> Void
    }

    /// Who is listening, by owner identity. See `observeFrameFinished`.
    private var frameObservers: [ObjectIdentifier: FrameObserver] = [:]

    /// **Called on the main actor after each frame the loop visits, whatever the outcome — and for
    /// each frame a ring top-up brings resident.**
    ///
    /// The read path's other half: the canvas showing a stale picture (§2.10) needs to be told the
    /// moment its own frame is ready — on disk after a bake, or in memory after a top-up, since
    /// during playback `image(for:)` will not decode on its behalf — and the timeline's baked-frame
    /// indication (§3.7) needs to be told about every frame. A callback rather than a `@Published` counter, because publishing
    /// would put a whole SwiftUI pass behind every bake — and a bake that is deduping finishes a
    /// frame in one mint and one `stat`, so that is hundreds of passes a second for a status light.
    ///
    /// **A registry rather than the single `var onFrameFinished` slot this was**, because stage 4d
    /// gave that slot to `CanvasView.Coordinator` and the timeline is a second consumer of the same
    /// event. Two named callbacks would be the peculiarity §2.15 rules out; one event with N
    /// listeners is the same path.
    ///
    /// **Keyed by owner and self-pruning.** Registering twice from one owner replaces rather than
    /// stacks, which is what lets both callers install unconditionally on a pass; and an entry whose
    /// owner has been deallocated is dropped the next time the baker reports a frame, so a
    /// coordinator that goes away leaves nothing behind. The `ObjectIdentifier` carries the ABA
    /// hazard `LayerContentVersion` documents — a freed owner's address reused by a new one — and
    /// here that resolves *correctly* on its own: the new owner's registration replaces the dead
    /// one's, which is exactly what was wanted.
    func observeFrameFinished(_ owner: AnyObject, _ body: @escaping (Int, FrameReadiness) -> Void) {
        frameObservers[ObjectIdentifier(owner)] = FrameObserver(owner: owner, body: body)
    }

    /// Stops `owner` listening. Not needed for correctness — a dead owner prunes itself — but a
    /// consumer that wants to stop while it is still alive has no other way to say so.
    func stopObservingFrameFinished(_ owner: AnyObject) {
        frameObservers[ObjectIdentifier(owner)] = nil
    }

    /// Reports `frame` to every live observer and forgets the dead ones.
    private func notifyFrameFinished(_ frame: Int, _ readiness: FrameReadiness) {
        for (id, observer) in frameObservers {
            guard observer.owner != nil else {
                frameObservers[id] = nil
                continue
            }
            observer.body(frame, readiness)
        }
    }

    // MARK: - What is on disk

    /// Which key each frame currently resolves to, as of the last time the baker visited it.
    private(set) var keyByFrame: [Int: FrameBakeKey] = [:]

    /// The inverse, and the reason this type owns it: **a content-addressed store holds one file for
    /// a nine-frame hold**, so "which frame is this file" is a `Set<Int>` and the store's
    /// playhead-distance eviction needs the whole map to answer "how far is the nearest".
    private(set) var framesByDigest: [String: Set<Int>] = [:]

    // MARK: - Counters, for tests and for the timeline's baked-frame indication

    /// Frames that were composited and written.
    private(set) var bakedCount = 0

    /// Frames whose recomputed key already had a file — §3.3's free clean, and the whole reason the
    /// key leaves `frame` out. A scrub through a nine-frame hold costs nine of these and no
    /// composite at all.
    private(set) var dedupedCount = 0

    /// Frames the store refused (§3.5's disk-full) or the compositor could not produce. Neither is a
    /// document failure; see `finish`.
    private(set) var failedCount = 0
    /// Bakes the one budget turned back to be tried again (`Outcome.deferred`).
    private(set) var deferredCount = 0

    /// The last thing the store refused, for a diagnostic. Cleared by `reset()`.
    private(set) var lastWriteFailure: FrameBakeStore.WriteFailure?

    // MARK: - Construction

    init(manager: CanvasManager, store: FrameBakeStore, ring: DecodedFrameRing,
         workQueue: DispatchQueue = DispatchQueue(label: "com.paintapp.FrameBaker.bake", qos: .utility)) {
        jobs = LatestWins(queue: workQueue)
        self.manager = manager
        self.store = store
        self.ring = ring
    }

    // MARK: - The read path (what stage 4d wires)

    /// The key `frame` resolves to **right now**, minted from the model.
    ///
    /// §3.3: *"The display path computes the current frame's key to find its file; a key with no file
    /// shows the previous picture and asks the scheduler for that frame first."* So this is the
    /// display path's question, and it is O(layers) with no pixel work — the same mint the loop does.
    /// It is deliberately not a lookup in `keyByFrame`, which records what the baker last saw and is
    /// therefore exactly the stale answer §3.3 forbids.
    func currentKey(atFrame frame: Int) -> FrameBakeKey? {
        PlaybackTrace.span(.bakeKeyMint) {
            guard let manager, let recipe = Self.recipe(manager, atFrame: frame) else { return nil }
            return FrameBakeKey(recipe: recipe, renderResolution: manager.renderResolution)
        }
    }

    /// **One mint, so the display path's key and the loop's key cannot disagree** — the same
    /// argument `liveCompositeSize` makes for its own two callers, and a stronger one here because
    /// disagreeing costs a file that is never read rather than a soft picture.
    ///
    /// ## `.liveComposite`, not `.native`, and that is stage 4d's correction to 4c
    ///
    /// The bake is what the live canvas shows at rest (§3.6), so it has to be **the same size** as
    /// the two halves the same canvas shows mid-stroke. Not for the picture's sake — the sandwich
    /// views are `.scaleToFill` and either size draws — but for the flatten's. `PixelOps.rasterize`
    /// is memoized on cel version **and size**, and the halves are minted at `liveCompositeSize`; a
    /// bake at `.native` would therefore flatten every cel of the document a *second* time at a
    /// second size, into the same byte-budgeted memo, and the two working sets would evict each
    /// other. PERFORMANCE §11 measures the flatten at 276 ms against an 84 ms composite, so that is
    /// the expensive half doubled — on a knob position the artist chose to make things cheaper.
    /// `MaskResolver.CacheKey` carries width and height too, so a masked document pays it twice over
    /// (`RenderSizing.liveComposite` writes that argument out in full).
    ///
    /// **So §3.6's *"served by the same worker and the same memo"* is bought by the size and not by
    /// the queue.** The memo is process-wide and keyed; sharing it needs the two mints to agree, not
    /// the two composites to run on one thread.
    ///
    /// The knob is inside `liveCompositeSize`, which is also what §2.8 wants of an export that reads
    /// these files, and what makes `FrameBakeStore.defaultRoot`'s per-resolution directory name
    /// something other than three copies of one picture. **And the knob is all that is inside it**
    /// (§2.12): the bake and the live halves share one size and neither composites below what the
    /// artist asked for. A frame too big for the budget is stripped, not shrunk —
    /// `StripedCompositor`.
    @MainActor
    private static func recipe(_ manager: CanvasManager, atFrame frame: Int) -> FrameRecipe? {
        manager.makeFrameRecipe(atFrame: frame, includeBackground: true, sizing: .liveComposite)
    }

    /// The finished picture for `key` if it is in memory — the ring, or the answer to the last read —
    /// and nil otherwise. **Never decodes** (SCHEDULER.md rule 2): a miss asks for the frame as an
    /// answer (R1, `requestRead`) and the canvas keeps the picture it has until `notifyFrameFinished`
    /// says this one is resident.
    ///
    /// **Ring → `makeImage()` is the whole chain** and zero-copy over one `Data`: `loadDecoded` hands
    /// back the decompressor's own buffer, the ring retains it, and `makeImage()` wraps it.
    ///
    /// The read is an answer, not later work, and that is S1 of SCHEDULER_DESIGN.md: it used to
    /// decode on the main thread at rest and, while the frames flipped, to wait behind the bake and
    /// behind the touch flag — the tap that stepped held its own frame back 250–500 ms (M1: the
    /// decode began 267 ms after every slow step on the iPad 9 simulator; the owner's scrub on a
    /// baked 2048×1024 scene read 0 hits in 110 flips).
    func picture(for key: FrameBakeKey, atFrame frame: Int) -> BakedPicture? {
        guard !isClosed else { return nil }
        // `value` is the ring's answer — 1 resident, 0 a miss — so a `PlaybackTrace` report carries
        // the hit rate without a second counter.
        if let resident = residentFrame(for: key) {
            return PlaybackTrace.span(.bakeRead, value: 1) {
                resident.frame.makeImage().map { BakedPicture(image: $0, level: resident.level) }
            }
        }
        PlaybackTrace.mark(.bakeRead, value: 0)
        requestRead(key, atFrame: frame)
        return nil
    }

    /// The finished picture for `frame`, or nil. The two calls above, in the order the display path
    /// wants them.
    func picture(atFrame frame: Int) -> BakedPicture? {
        guard let key = currentKey(atFrame: frame) else { return nil }
        return picture(for: key, atFrame: frame)
    }

    /// `frame`'s picture if it is in memory, asking for nothing — for a picture wanted only if it is
    /// free, such as the frame a step is leaving, whose read must not cancel the new frame's.
    func residentPicture(atFrame frame: Int) -> BakedPicture? {
        guard !isClosed, let key = currentKey(atFrame: frame), let resident = residentFrame(for: key) else { return nil }
        return resident.frame.makeImage().map { BakedPicture(image: $0, level: resident.level) }
    }

    /// The ring's name for one size of one frame.
    private func ringName(_ key: FrameBakeKey, _ level: BakeLevel) -> String { key.fileName + level.ringSuffix }

    /// The frame in memory at the wanted level, or — when `.half` is wanted — at `.full`.
    private func residentFrame(for key: FrameBakeKey) -> (frame: DecodedFrame, level: BakeLevel)? {
        let wanted = displayLevel
        for level in wanted == .half ? [BakeLevel.half, .full] : [.full] {
            let name = ringName(key, level)
            if let frame = ring.frame(for: name) ?? answered.flatMap({ $0.name == name ? $0.frame : nil }) {
                return (frame, level)
            }
        }
        return nil
    }

    // MARK: - The answer: the frame on screen, read as R1

    /// The last frame an answer read **that the ring refused** — a ring at its budget may, and the
    /// canvas asked for exactly this one.
    private var answered: (name: String, frame: DecodedFrame)?
    /// The file the answer in flight is reading, so a pass asking again does not restart it.
    private var reading: String?
    /// The answer's latest-wins key: a newer frame cancels the read of the older (rule 4).
    private var readKey: JobKey { JobKey("FrameBaker.read", ObjectIdentifier(self)) }

    /// **Reads `key`'s file off the main thread as an answer** — not held by the touch flag, not behind
    /// the bake, and cancelled by the next frame's read. A frame with no file has nothing to read:
    /// the bake has it at the head of its queue (band 1 is the playhead), and the canvas keeps the
    /// last whole picture meanwhile (owner Q1, 2026-11-25).
    private func requestRead(_ key: FrameBakeKey, atFrame frame: Int) {
        let level = displayLevel, name = ringName(key, level)
        guard reading != name else { return }
        guard store.contains(key) else {
            // A frame the loop recorded whose file is gone (evicted, or lost) is dirty again; one it
            // has not reached yet is already in its queue.
            if keyByFrame[frame] == key { recover(key) } else { kick() }
            return
        }
        reading = name
        let store = store
        Scheduler.shared.submit(Job(key: readKey, jobClass: .answer, name: "frame read", visible: true, work: { context in
            try context.checkpoint()
            return MemoryBudget.withLane(.answer) { store.read(key, level: level) }
        }, land: { [weak self] (result: FrameBakeStore.ReadResult) in
            self?.finishRead(key, level: level, atFrame: frame, result: result)
        }))
    }

    private func finishRead(_ key: FrameBakeKey, level: BakeLevel, atFrame frame: Int, result: FrameBakeStore.ReadResult) {
        guard !isClosed else { return }
        let name = ringName(key, level)
        if reading == name { reading = nil }
        if result.isUnavailable {
            recover(key)
            return
        }
        guard let decoded = result.frame else { return }
        // The ring's budget may refuse it; the frame the canvas asked for is then held here, outside
        // the ring, until the next answer — one frame, the R1 reserve SCHEDULER_DESIGN.md §3 sizes.
        answered = ring.insert(decoded, for: name, keeping: ringKept(around: frame)) ? nil : (name, decoded)
        ringWalk = nil
        for shown in (framesByDigest[key.fileName] ?? []).union([frame]) { notifyFrameFinished(shown, .resident) }
        topUpRing()
    }

    /// The scheduler's clean key remains in the shared store inventory. Timeline painting never
    /// mints a recipe, polls the filesystem or decodes pixels. Owned eviction updates inventory;
    /// actual read demand detects external removal and rejects invalid disposable files.
    func isBaked(atFrame frame: Int) -> Bool {
        guard !bakeQueue.isPending(frame), let key = keyByFrame[frame] else { return false }
        return store.contains(key)
    }

    // MARK: - Kept frames (KeptBakes)

    /// The frames kept for the package this document was opened from, that nothing has touched since:
    /// set once by `adopt`, only ever shrunk. A frame in it is baked by cloning its kept file, not by
    /// compositing. Every way a frame can change (`syncDirty`, `markEverythingDirty`, `recover`) takes
    /// it out first, so a kept picture is never put up for a frame that is no longer what was saved.
    private var adoptable: (root: URL, token: String, frames: Set<Int>)?

    /// Offers the frames kept under `token` to the loop. Called by the first baker after a package
    /// opens, before its first sweep (`CanvasManager.makeFrameBaker`).
    func adopt(root: URL, token: String) {
        let frames = KeptBakes.frames(in: root, token: token)
        adoptable = frames.isEmpty ? nil : (root, token, frames)
    }

    /// Frames adopted from kept files, for tests.
    private(set) var adoptedCount = 0

    private func dropAdoptable(_ span: Range<Int>) {
        adoptable?.frames.subtract(span)
    }

    /// **What a save keeps**: the frames this baker holds clean right now and the working file that
    /// depicts each. The sweep runs first, so an edit no pass has seen yet is not counted clean.
    func cleanFramesOnDisk() -> [(frame: Int, source: URL)] {
        syncDirty()
        return keyByFrame.compactMap { frame, key in
            !bakeQueue.isPending(frame) && store.contains(key) ? (frame, store.url(for: key)) : nil
        }
    }

    // MARK: - Dirty marking (RENDER §3.6)

    /// **The signal, and the only one.** Something in the document may have changed: work out what
    /// that reaches and start baking. `CanvasManager.syncFrameBake` is the app's caller and runs it
    /// once per canvas reconciliation pass — see there for why that is the cadence.
    ///
    /// See `syncDirty()` for what "work out" means and what it deliberately cannot see.
    func noteDocumentChanged() {
        syncDirty()
        kick()
    }

    /// Marks every frame and starts baking — for the inputs that are not in the document at all and
    /// so cannot be swept for: a backend change or a store purge. The structural sweep also carries
    /// the backend; mask tuning is an ordinary document change.
    func markEverythingDirty() {
        if let manager { bakeQueue.frameCount = manager.contentEndFrame }
        bakeQueue.markAllDirty()
        adoptable = nil
        kick()
    }

    /// Forgets everything the baker believes: the dirty set, what is on disk, the ring. The document
    /// closing, or the store being purged underneath it.
    ///
    /// **It does not purge the store**, which is the caller's call to make (§2.11's launch dump is
    /// `FrameBakeStore.purgeAll`, invoked by the app). This only drops the bookkeeping that would
    /// otherwise claim files that are gone.
    func reset() {
        jobs.cancel()
        Scheduler.shared.cancel(key: readKey)
        Scheduler.shared.cancel(key: ringKey)
        answered = nil
        reading = nil
        ringFilling = false
        bakeIsIdle = false
        ringIsIdle = false
        bakeQueue = BakeQueue()
        keyByFrame = [:]
        framesByDigest = [:]
        lastStructure = nil
        lastCels = nil
        ringWalk = nil
        bakedCount = 0
        dedupedCount = 0
        failedCount = 0
        lastWriteFailure = nil
        ring.removeAll()
    }

    /// Drops all live consumers and cancels the shared worker's landing. Frozen work already on
    /// its queue may finish, but cannot install a picture, restart the loop or notify a closed UI.
    func close() {
        manager = nil
        reset()
        exportFocus = nil
        frameObservers.removeAll()
        onIdle = nil
    }

    // MARK: - The loop

    /// Requests one inspection of the dirty set. Requests during work coalesce; the next recipe
    /// is minted only after the previous landing, using the current playhead and model.
    func kick() {
        guard !isSuspended, !isClosed else { return }
        bakeIsIdle = false
        topUpRing()
        jobs.request { [weak self] in self?.nextWork() }
    }

    /// LatestWins owns the one worker and cancellation of both bake and decode landings. The
    /// dirty queue still owns every frame; coalescing requests to inspect it discards no frame.
    private func nextWork() -> LatestWins.Work? {
        guard !isSuspended, let manager else { return nil }
        // **SCHEDULER.md rule 3: no bake starts while a touch is down or just lifted.** A bake is a
        // whole-frame composite (5.3–8.8 s at the owner's 5000² on the iPad 9) of a picture the
        // canvas is not showing while the artist edits; it looks again when the gate has settled.
        guard !Scheduler.shared.touchHeld else {
            lookAgainWhenTheGateSettles()
            return nil
        }
        bakeQueue.frameCount = manager.contentEndFrame

        // **The one substitution stage 6 makes.** With no export running this is the artist's
        // playhead and the document's loop markers, exactly as stages 4c–4f left it; with one
        // running it is the export's cursor and the export's range, and every band, the eviction
        // policy and the ring lookahead follow it without a second code path. See `exportFocus`.
        let playhead = exportFocus?.frame ?? manager.currentFrame
        let direction: BakeQueue.Direction = exportFocus == nil ? playbackDirection : .forward
        let range = exportFocus?.range ?? Self.playbackRange(of: manager)
        // An export walks its range once and stops. Looping band 2 would send it back to the
        // start, which is behind it.
        let looping = exportFocus == nil && manager.isLoopEnabled
        guard let frame = bakeQueue.next(playhead: playhead,
                                         direction: direction,
                                         playbackRange: range,
                                         looping: looping) else {
            // Nothing left to composite. The ring's own walk is not behind this loop any more
            // (`topUpRing`), so idle is both of them stopped.
            bakeIsIdle = true
            reportIdleIfDone()
            return nil
        }

        bakeIsIdle = false
        // Step 1, on the main actor and O(layers) with no pixel work — RENDER §3.2's whole seam.
        // Nothing proportional to canvas area may join these two lines.
        guard let recipe = Self.recipe(manager, atFrame: frame) else {
            // No canvas to composite into. The frame stays pending rather than being marked clean:
            // marking it would discard the request, and §3.6 says the queue never discards. The loop
            // stops here and the next `kick` — after a canvas exists — picks it up.
            onIdle?()
            return nil
        }
        let resolution = manager.renderResolution
        let budget = budgetBytes
        let delay = Self.compositeDelay
        let wantsRing = Self.isWithin(ringLookahead, of: playhead, frame: frame,
                                      direction: direction)
        let level = displayLevel
        let frames = framesByDigest
        let adopting = adoptable.flatMap { $0.frames.contains(frame) ? ($0.root, $0.token) : nil }

        return { [weak self, store] in
          // Step 2 runs as R3 (SCHEDULER.md): every canvas-sized allocation in it — the leaves'
          // renders, the composite's pictures, the decode for the ring — asks the one budget in the
          // `.later` lane, which evicts only what is kept in case and otherwise waits for room.
          MemoryBudget.withLane(.later) { () -> (() -> Void) in
            // Step 2, off the main actor. Every value read here was frozen at mint time.
            let key = FrameBakeKey(recipe: recipe, renderResolution: resolution)
            // Two frames is the step's peak: the picture and one leaf, then the picture and its BGRA
            // copy, then that copy and LZ4's output — each pair let go before the next is made.
            let frameBytes = CompositorBudget.textureBytes(for: recipe.canvasSize)
            var refusedPartWay = false
            let cached = wantsRing ? store.read(key, level: level) : nil
            var decoded = cached?.frame
            let outcome: Outcome
            if cached?.isUnavailable != true, store.contains(key) {
                // A hold reuses its content-addressed file. A decode already needed for the ring
                // rejects an unreadable file before this decision; distant frames need only stat.
                outcome = .alreadyOnDisk
            } else if let adopting, store.adopt(frame: frame, from: adopting, as: key) {
                // The frame is what the saved package holds and a kept picture of it exists.
                outcome = .adopted
            } else if !MemoryBudget.shared.waitForRoom(2 * frameBytes) {
                // R3 waits before it starts, holding nothing; still no room is a retry, not a failure.
                outcome = .deferred
            } else if let converted = PlaybackTrace.span(.bakeComposite, {
                () -> (pixels: (bytes: [UInt8], width: Int, height: Int), grant: MemoryBudget.Grant)? in
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                let refusedBefore = MemoryBudget.shared.refusals
                // The composite is converted and let go here, before the encode allocates.
                guard let image = recipe.composite(budgetBytes: budget),
                      let grant = MemoryBudget.shared.admit(image.width * image.height * 4),
                      let pixels = FrameBakeStore.bgraBytes(image) else {
                    refusedPartWay = MemoryBudget.shared.refusals != refusedBefore
                    return nil
                }
                return (pixels, grant)
            }) {
                defer { converted.grant.release() }
                switch PlaybackTrace.span(.bakeWrite, {
                    store.store(pixels: converted.pixels, for: key, playhead: playhead, frames: frames)
                }) {
                case .success:
                    outcome = .baked
                case .failure(.notAdmitted):
                    outcome = .deferred
                case .failure(let failure):
                    outcome = .writeFailed(failure)
                }
            } else {
                // Refused part-way by the one budget: the frame goes back to be baked when there is room.
                outcome = refusedPartWay ? .deferred : .compositeFailed
            }

            // The ring is filled from the store rather than from the `CGImage` just composited, and
            // the re-read is deliberate: it is the *decode* path playback actually takes, so filling
            // the ring any other way would leave that path unexercised by every bake. One LZ4 decode
            // is single-digit milliseconds at 2048² (§3.5) and this queue is `.utility`.
            if wantsRing, outcome.isOnDisk, decoded == nil, cached?.isUnavailable != false {
                decoded = store.loadDecoded(key, level: level)
            }
            return {
                PlaybackTrace.span(.renderLanded) {
                    guard let self else { return }
                    if let decoded { self.ring.insert(decoded, for: self.ringName(key, level)) }
                    self.finish(frame: frame, key: key, outcome: outcome)
                }
            }
          }
        }
    }

    private var gateRetryArmed = false

    /// One deferred `kick` however many passes find the gate closed.
    private func lookAgainWhenTheGateSettles() {
        guard !gateRetryArmed else { return }
        gateRetryArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + TouchFlag.settle) { [weak self] in
            guard let self else { return }
            self.gateRetryArmed = false
            self.kick()
        }
    }

    // MARK: - Ring top-up

    /// **Decodes the frames around the playhead into the ring, one at a time, as R2** — the frames a
    /// step or a play is about to ask for, so the read it makes is a hit and the whole frame is up on
    /// the next display frame (SCHEDULER_DESIGN.md §3, "Predictive loading").
    ///
    /// **Its own lane, not the bake's worker**: it used to run only when no frame in the scene was
    /// dirty, so during a bake it waited for the whole scene (§0). It is R2 work nobody is looking at
    /// yet, so the touch flag holds it — a scrub warms nothing but the frame under the finger, which
    /// is an answer (`requestRead`).
    ///
    /// `keyByFrame` rather than a fresh mint, so the scan is dictionary lookups: a frame the loop has
    /// visited and nothing has dirtied since resolves to the key recorded there; a frame it has never
    /// seen is dirty and the bake is handling it.
    ///
    /// **A frame is inserted keeping every nearer one** (`ringTargets`' order), so a ring that holds K
    /// frames holds the K nearest, and filling a far frame never evicts the near one it was for. A
    /// refusal ends the walk for this playhead and direction until either moves.
    private func topUpRing() {
        guard !ringFilling, ringLookahead > 0, !isSuspended, let manager else { return }
        let playhead = exportFocus?.frame ?? manager.currentFrame
        let direction: BakeQueue.Direction = exportFocus == nil ? playbackDirection : .forward
        let targets = ringTargets(around: playhead, direction: direction)
        var start = 0
        if let walk = ringWalk, walk.playhead == playhead, walk.direction == direction { start = walk.next }
        // The targets already walked still name what an insert keeps.
        let level = displayLevel
        var nearer = Set(targets.prefix(start).dropFirst().compactMap { keyByFrame[$0].map { ringName($0, level) } })
        for index in targets.indices.dropFirst(start) {
            let frame = targets[index]
            guard let key = keyByFrame[frame] else { continue }
            if ring.contains(ringName(key, level)) || ring.contains(ringName(key, .full)) {
                if index > 0 { nearer.insert(ringName(key, level)) }
                continue
            }
            guard store.contains(key) else {
                // Recorded, but its file is gone: dirty again, and the bake rebuilds it.
                recover(key)
                return
            }
            ringWalk = (playhead, direction, index + 1)
            ringFilling = true
            ringIsIdle = false
            let kept = nearer, store = store
            Scheduler.shared.submit(Job(key: ringKey, jobClass: .soon,
                                        name: "ring top-up", work: { context in
                try context.checkpoint()
                return MemoryBudget.withLane(.soon) { store.read(key, level: level) }
            }, land: { [weak self] (result: FrameBakeStore.ReadResult) in
                PlaybackTrace.span(.renderLanded) {
                    self?.finishRingFill(key: key, level: level, result: result, keeping: kept, playhead: playhead, direction: direction)
                }
            }))
            return
        }
        ringWalk = (playhead, direction, targets.count)
        ringIsIdle = true
        reportIdleIfDone()
    }

    /// **The frames worth holding decoded, nearest first** — the playhead's own, then one ahead and —
    /// stopped — one behind (a step goes either way), then on ahead through the lookahead. Distance is
    /// play's own walk (`BakeQueue.step`), wrap included: on the last frame of a loop the frame one
    /// ahead is the loop's first.
    private func ringTargets(around playhead: Int, direction: BakeQueue.Direction) -> [Int] {
        guard let manager else { return [] }
        let range = exportFocus?.range ?? Self.playbackRange(of: manager)
        let low = max(range?.lowerBound ?? 0, 0)
        let high = min(range?.upperBound ?? manager.contentEndFrame - 1, manager.contentEndFrame - 1)
        guard low <= high else { return [playhead] }
        let looping = exportFocus == nil && manager.isLoopEnabled
        let reach = min(ringLookahead, high - low)
        var targets = [playhead]
        var frame = playhead
        for _ in 0..<reach {
            guard let next = BakeQueue.step(from: frame, low: low, high: high, direction: direction,
                                            looping: looping) else { break }
            frame = next
            if !targets.contains(next) { targets.append(next) }
            if targets.count == 2, !manager.isPlaying, exportFocus == nil,
               let behind = BakeQueue.step(from: playhead, low: low, high: high,
                                           direction: direction == .forward ? .backward : .forward, looping: looping),
               !targets.contains(behind) {
                targets.append(behind)
            }
        }
        return targets
    }

    /// The ring entries nearer `frame` than whatever is inserted for it — what an answer keeps.
    private func ringKept(around frame: Int) -> Set<String> {
        let level = displayLevel
        return Set(ringTargets(around: frame, direction: playbackDirection).dropFirst().compactMap { keyByFrame[$0].map { ringName($0, level) } })
    }

    private var ringKey: JobKey { JobKey("FrameBaker.ring", ObjectIdentifier(self)) }
    /// A top-up's decode is in flight.
    private var ringFilling = false
    /// **How far the walk has gone, and from where** — it only ever moves outward for one playhead and
    /// direction, which is what makes it terminate when the ring is narrower than the targets: a far
    /// frame inserted may evict a near one, and a walk that rescanned from the playhead would decode
    /// the two in turn for ever. Dropped when anything else changes the ring, and moved past the end
    /// by a refusal.
    private var ringWalk: (playhead: Int, direction: BakeQueue.Direction, next: Int)?
    /// The two halves of idle: the bake loop has no frame, and the ring walk has nothing to decode.
    private var bakeIsIdle = false
    private var ringIsIdle = false

    /// `onIdle` once the bake and the ring walk have stopped and no answer is being read.
    private func reportIdleIfDone() {
        guard bakeIsIdle, ringIsIdle, !ringFilling, reading == nil else { return }
        onIdle?()
    }

    /// Takes one decoded frame in and walks on — **but only if the ring took it**. A missing or
    /// invalid file requeues the frames sharing it; a refusal by the ring's budget ends the walk for
    /// this playhead. A frame that landed is announced to every frame it serves: a canvas that missed
    /// on it is showing the previous picture and is waiting to be told this one is resident.
    private func finishRingFill(key: FrameBakeKey, level: BakeLevel, result: FrameBakeStore.ReadResult, keeping kept: Set<String>,
                                playhead: Int, direction: BakeQueue.Direction) {
        ringFilling = false
        guard !isClosed else { return }
        if result.isUnavailable {
            recover(key)
            return
        }
        guard let decoded = result.frame, ring.insert(decoded, for: ringName(key, level), keeping: kept) else {
            ringWalk = (playhead, direction, Int.max)
            ringIsIdle = true
            reportIdleIfDone()
            return
        }
        for frame in framesByDigest[key.fileName] ?? [] { notifyFrameFinished(frame, .resident) }
        topUpRing()
    }

    /// What one iteration did.
    private enum Outcome {
        case baked
        case alreadyOnDisk
        /// Made from a kept file (`KeptBakes.adopt`) — no composite.
        case adopted
        case writeFailed(FrameBakeStore.WriteFailure)
        case compositeFailed
        /// The one budget had no room for it (SCHEDULER.md rule 5): still dirty, tried again shortly.
        case deferred

        var isOnDisk: Bool {
            switch self {
            case .baked, .alreadyOnDisk, .adopted: return true
            case .writeFailed, .compositeFailed, .deferred: return false
            }
        }
    }

    /// Back on the main actor: record what happened, release the lock, and go round again.
    ///
    /// **A failure marks the frame clean too, and that is the non-spinning choice rather than a
    /// shrug.** §3.5 makes disk-full a bake failure and not a document failure: the store stops
    /// writing and playback falls back to stale frames (§2.10). Leaving the frame pending would put
    /// the loop in a tight cycle re-compositing a frame it cannot write — burning exactly the CPU
    /// §2's *"no lagspikes"* is about — while the picture would be no better for it. The dirty bit is
    /// a scheduling hint (§3.3) and this one has been spent; the next edit to reach that frame
    /// re-raises it, and the *key* still says truthfully that there is no file.
    private func finish(frame: Int, key: FrameBakeKey, outcome: Outcome) {
        adoptable?.frames.remove(frame)
        // **The document can move while a composite is in flight, and clearing the bit regardless
        // would discard the edit that moved it.** `kick` mints the key on the main actor and then
        // hops to `workQueue`, so an edit landing in between is an edit this bake did not see. It
        // cannot announce itself either: `BakeQueue.next` does not consume, so the frame is still
        // dirty, and `syncDirty`'s `markDirty` on an already-dirty frame is a no-op — the sweep does
        // its job and leaves no trace of having done it. Re-minting here is the same O(layers) the
        // display path pays per redraw, against a composite that has just run, so it is free at this
        // point in the loop.
        //
        // **Only when something reached disk**, and only on a key that mints. A frame whose write or
        // composite failed is marked clean as it always was: re-dirtying a frame that cannot be baked
        // is a spin, and the failure is already counted and reported.
        if case .deferred = outcome {
            deferredCount += 1
            ringWalk = nil
            lookAgainWhenTheGateSettles()
            return
        }
        let current = currentKey(atFrame: frame)
        if outcome.isOnDisk, let current, current != key {
            bakeQueue.markDirty(frame..<(frame + 1))
        } else {
            bakeQueue.markClean(frame)
        }

        switch outcome {
        case .baked:
            bakedCount += 1
            record(frame: frame, key: key)
        case .alreadyOnDisk:
            dedupedCount += 1
            record(frame: frame, key: key)
        case .adopted:
            adoptedCount += 1
            record(frame: frame, key: key)
        case .writeFailed(let failure):
            failedCount += 1
            lastWriteFailure = failure
            forget(frame: frame)
        case .compositeFailed:
            failedCount += 1
            forget(frame: frame)
        case .deferred:
            break
        }

        // A bake that reached the ring inserted around nothing in particular; the walk re-settles.
        ringWalk = nil
        notifyFrameFinished(frame, .baked)
        kick()
    }

    /// `frame` now resolves to `key`. Maintains both halves of the digest↔frames map.
    private func record(frame: Int, key: FrameBakeKey) {
        forget(frame: frame)
        keyByFrame[frame] = key
        framesByDigest[key.fileName, default: []].insert(frame)
    }

    /// A real store miss invalidates every frame sharing the file. Ring budget/allocation refusals
    /// never call this: they keep a valid disk picture clean and merely stop the resident walk.
    private func recover(_ key: FrameBakeKey) {
        let frames = framesByDigest[key.fileName] ?? []
        for frame in frames {
            forget(frame: frame)
            bakeQueue.markDirty(frame: frame)
            adoptable?.frames.remove(frame)
        }
        ringWalk = nil
        kick()
    }

    /// Drops whatever `frame` used to resolve to, and the digest entry with it once no frame names it.
    private func forget(frame: Int) {
        guard let previous = keyByFrame.removeValue(forKey: frame) else { return }
        let name = previous.fileName
        framesByDigest[name]?.remove(frame)
        if framesByDigest[name]?.isEmpty == true { framesByDigest[name] = nil }
    }

    /// What playback actually cycles through — `BakeQueue`'s band 2, and **not** `0...frameCount-1`,
    /// which that type's doc comment calls out as a real defect rather than a simplification.
    private static func playbackRange(of manager: CanvasManager) -> ClosedRange<Int>? {
        let low = manager.playbackStartFrame, high = manager.playbackEndFrame
        return low <= high ? low...high : nil
    }

    /// Whether `frame` is inside the lookahead window in the direction of travel. The playhead's own
    /// frame counts, because that is the one a tick reads first.
    private static func isWithin(_ lookahead: Int, of playhead: Int, frame: Int,
                                 direction: BakeQueue.Direction) -> Bool {
        let ahead = direction == .forward ? frame - playhead : playhead - frame
        return ahead >= 0 && ahead <= lookahead
    }

    // MARK: - The sweep

    /// What the baker last saw of the document's shape.
    private var lastStructure: StructuralStamp?
    /// What it last saw of every layer's cels, by `layers` index.
    private var lastCels: [[CelStamp]]?

    /// **Which frames a change reached — §2.16, and the reason this stage exists.**
    ///
    /// ## There is no push funnel that knows a frame, and this is what there is instead
    ///
    /// The obvious hook does not exist. `CanvasManager.beginCanvasEdit()` is a chokepoint but the
    /// wrong one — it runs *before* an edit and bakes pending transients, so it cannot know what the
    /// edit is about to touch. `recordUndo` is documented as *"the shared entry point every call site
    /// funnels through"* and has seventeen of them, but the undo and redo *closures* it stores do not
    /// go through it, so replaying a step would reach no frame. `objectWillChange` fires for tool and
    /// brush state that reaches no pixel, and misses the mutations that matter most: a dab lands in
    /// `VectorCanvas`/`RasterLayerTexture`, which are classes, so `@Published var layers` is never
    /// written and nothing is published at all.
    ///
    /// The one thing every content edit does reach is the tier object's own version counter —
    /// `VectorCanvas.invalidate()` and `RasterLayerTexture`'s four bumps — and `LayerContentVersion`
    /// already reads exactly those. So the seam is a **sweep**, not a hook: compare the document's
    /// cel layout against the layout the baker last saw, and dirty the difference. It is O(layers +
    /// cels) of integer and pointer comparison with no pixel work, it catches undo and redo and every
    /// mutation site that does not exist yet for free, and it is RENDER §0's missing *"inversion of
    /// `Cel.startFrame`/`frameCount` into a frame → dirty map"*.
    ///
    /// ## Three tiers, and two of them are coarse on purpose
    ///
    /// 1. **A cel whose content or span moved dirties `[startFrame, endFrame)`** — both its old span
    ///    and its new one, since a cel that slid along the timeline changed the picture at the frames
    ///    it left as well as the ones it arrived at. This is the exact tier and the one §2.16 is
    ///    about.
    /// 2. **Any structural change dirties every frame.** §3.6 rules that outright — *"a structural
    ///    edit (order, folder, mask, blend, effect track) dirties every frame"* — so the coarseness
    ///    here is the ruling rather than a compromise. See `StructuralStamp`.
    /// 3. **Any cel change also dirties every interpolated cel's span.** §3.6's precise rule is that
    ///    an in-between whose `InterpolatedCelIdentity.references` name the edited cel dirties its own
    ///    span; this is that rule with the reference test dropped, which marks strictly more. §3.3
    ///    makes the over-marking cheap by construction: the key is the truth, so an in-between the
    ///    change did not reach has the file it had and costs one mint and no composite.
    ///
    ///    **This tier is about a *referenced* cel moving, and it cannot cover an in-between's own
    ///    recipe** — retiming one moves no other cel, so `touchedACel` stays false and the gate below
    ///    returns before this loop runs. The recipe is stamped in `CelStamp` instead, where tier 1
    ///    marks exactly the in-between's own span.
    func syncDirty() {
        guard let manager else { return }
        let structure = StructuralStamp(manager)
        let cels = Self.celStamps(manager)
        defer {
            lastStructure = structure
            lastCels = cels
        }

        // Before any marking: a range clamps against `frameCount`, so a scene that just grew must be
        // told so or the new frames are dropped on the floor.
        bakeQueue.frameCount = manager.contentEndFrame

        guard let previousStructure = lastStructure, let previousCels = lastCels else {
            // The first sweep. Nothing has been baked and nothing is known, so everything wants one.
            bakeQueue.markAllDirty()
            return
        }

        guard structure == previousStructure else {
            bakeQueue.markAllDirty()
            adoptable = nil
            return
        }

        var touchedACel = false
        for layerIndex in 0..<max(cels.count, previousCels.count) {
            let now = layerIndex < cels.count ? cels[layerIndex] : []
            let before = layerIndex < previousCels.count ? previousCels[layerIndex] : []
            // Keyed by cel id rather than by position: inserting a cel renumbers every one after it,
            // and a positional diff would call all of them changed.
            var unseen = [UUID: CelStamp](before.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            for stamp in now {
                guard let old = unseen.removeValue(forKey: stamp.id) else {
                    // A cel that did not exist last time.
                    bakeQueue.markDirty(stamp.span)
                    dropAdoptable(stamp.span)
                    touchedACel = true
                    continue
                }
                guard old != stamp else { continue }
                // Both spans: where it was, and where it is now.
                bakeQueue.markDirty(old.span)
                bakeQueue.markDirty(stamp.span)
                dropAdoptable(old.span)
                dropAdoptable(stamp.span)
                touchedACel = true
            }
            for old in unseen.values {
                // A cel that is gone. The frames it covered show something else now.
                bakeQueue.markDirty(old.span)
                dropAdoptable(old.span)
                touchedACel = true
            }
        }

        guard touchedACel else { return }
        for layer in cels {
            for stamp in layer where stamp.isDerived {
                bakeQueue.markDirty(stamp.span)
                dropAdoptable(stamp.span)
            }
        }
    }

    // MARK: - The two stamps

    /// One cel, as much of it as decides the picture and none of what does not.
    ///
    /// `LayerContentVersion` is the content half and is reused rather than re-derived: it already
    /// names the raster tier by identity *and* version, the vector tier the same way, and the fill
    /// and baked tiers by identity — which is every place a dab, an erase, a fill or a paste can
    /// land. Its `effect` and `valueFill` fields stay nil here because those are layer-level and
    /// belong to `StructuralStamp`; its `derived` field stays nil because an in-between is covered by
    /// tier 3 of the sweep instead.
    ///
    /// **`Cel.transformTracks` is the one content field `LayerContentVersion` cannot supply, so it is
    /// carried here in full.** A pose is a *derivation*: the picture is `posedCelContent`'s, and the
    /// identity naming it reaches `LayerContentVersion.derived` only when a caller resolves the
    /// derivation, which this sweep does not — resolving every cel's pose on every pass would cost a
    /// `poseMappings` per cel to answer what the stored tracks already answer. Comparing the tracks is
    /// strictly coarser than comparing the resolved maps and exactly as safe: a track that did not
    /// move resolves to maps that did not move, and §3.3 makes the over-marking one mint and no
    /// composite. Tier 3 cannot stand in for this either — `isDerived` is `interpolation != nil`, and
    /// a posed cel stores its own ink.
    ///
    /// **`pendingPoseBaselines` is deliberately not here.** It is §2.27's authoring state between two
    /// marks, read by the writer that commits the next mark and by nothing that renders, so it reaches
    /// no pixel and dirtying a span for it would schedule a bake that produces the file it already has.
    private struct CelStamp: Equatable {
        let id: UUID
        let start: Int
        let count: Int
        let version: LayerContentVersion
        /// Whether this cel's content is computed rather than stored — sweep tier 3.
        let isDerived: Bool
        /// The pose channels animating this cel's own ink — KEYFRAMES.md stage 5.
        let poses: [String: TransformTrack]
        /// **The in-between's recipe, whole**, for `poses`' reason and one stronger: `t`, the spacing
        /// curve and a refitted lattice each move the picture and none of them touches a tier object,
        /// so a retime is invisible to every other field here. `InterpolationRecipe.Content-
        /// Fingerprint` decides what counts, beside the identity the bake key is minted from, rather
        /// than a second list of recipe fields kept here.
        let recipe: InterpolationRecipe.ContentFingerprint?

        var span: Range<Int> { start..<(start + count) }

        init(_ cel: Cel) {
            id = cel.id
            start = cel.startFrame
            count = cel.frameCount
            version = LayerContentVersion(cel: cel)
            isDerived = cel.interpolation != nil
            poses = cel.transformTracks
            recipe = cel.interpolation?.contentFingerprint
        }
    }

    private static func celStamps(_ manager: CanvasManager) -> [[CelStamp]] {
        manager.layers.map { $0.cels.map(CelStamp.init) }
    }

    /// Everything about the document that is not a cel's own content — §3.6's *"structural edit"*,
    /// and the whole of it in one `Equatable` value.
    ///
    /// **`renderTree(atFrame:)` carries most of it, and that is why this is short rather than a
    /// hand-listed inventory of `Layer`'s fields.** The tree is the model's own projection of layer
    /// order, folder nesting, opacity, visibility, blend mode, isolation and the resolved masks, it
    /// is already `Equatable` because `CanvasView.SandwichKey` compares whole trees on every SwiftUI
    /// pass, and it is what the bake key itself encodes. A field added to `Layer` that reaches a
    /// pixel reaches the tree, and therefore reaches this, with no edit here.
    ///
    /// **Frame 0, fixed, rather than the playhead**, so that scrubbing does not read as a structural
    /// change. The tree is frame-invariant except for `Layer.layerEffect(atFrame:)`,
    /// `LayerFolder.resolvedEffect(atFrame:)` and `Layer.opacity(atFrame:)`, and the track fields
    /// below close exactly that gap: a curve edited so that frame 7 changes and frame 0 does not is
    /// invisible in the tree at frame 0 and plain in the dictionary.
    /// A container pose as much of it as reaches a pixel: the stored base, the whole track, the
    /// mode, the shake's seed and period and the repeat's period — and not the baseline, for
    /// `StructuralStamp.containerPoses`' reason. **The seed and period are here because the rotate
    /// test found the pose missing**: the noise is a pure function of `(seed, period, frame)`
    /// (TRANSFORM_LAYER.md §5.4), so a re-rolled seed changes every frame's bytes with nothing in the
    /// tree to say so, and a stamp without it would serve the old shake off the display path
    /// forever. `FrameBakerLogicTests` drops each and expects red.
    private struct ContainerPoseStamp: Equatable {
        let pose: PoseQuad
        let track: TransformTrack
        let mode: TransformLayerMode
        let shakeSeed: UInt64
        let shakePeriod: Int
        /// §5.5's loop length — which frames beneath show which source frame, and nothing in the
        /// tree says so either.
        let repeatPeriod: Int

        init(_ pose: LayerPose) {
            self.pose = pose.pose
            track = pose.track
            mode = pose.mode
            shakeSeed = pose.shakeSeed
            shakePeriod = pose.shakePeriod
            repeatPeriod = pose.repeatPeriod
        }
    }

    private struct StructuralStamp: Equatable {
        let tree: [RenderNode]
        /// The animated half of every layer's **and every folder's** effect, which a single probe
        /// frame cannot see. Layers first, then folders, in each array's own order — the two are
        /// concatenated rather than kept as four fields because nothing here reads them, it only
        /// compares them, and `LayerFolder.effectTracks` is `Layer.effectTracks`'s twin in every
        /// observable respect. A folder's grade is carried by no `LayerContentVersion`, so this is
        /// the only place an animated one can be seen at all.
        let effectTracks: [[String: AnimationCurve]]
        /// **The same gap, for the same reason, on TODO (21)'s second channel kind.** An opacity
        /// curve edited so that frame 7 changes and frame 0 does not is invisible in a tree sampled
        /// at frame 0 — `Layer.opacity(atFrame:)` is a third frame-dependent term beside the two
        /// named above — so without this the baker keeps serving the frames it has and the artist's
        /// fade never appears in playback. Layers then folders, `effectTracks`' shape exactly.
        let channelTracks: [[String: AnimationCurve]]
        let keyframeMarks: [[Int]]
        /// **The container poses, which reach no tree at all** — KEYFRAMES §4.4 emits a pose
        /// *alongside* the tree so that it never reaches the compositor, which is right for the
        /// render and was a hole here: a transform layer's box moved after the first sweep dirtied
        /// nothing, and the sandwich's display key then missed on every frame with no bake ever
        /// scheduled to fill it. TRANSFORM_LAYER.md's modes made it plain — a Rotate layer at a
        /// constant speed re-poses every frame with no track to be seen, so `channelTracks` above
        /// could not catch it either — and `TransformLayerModesUITests` caught it on the canvas.
        /// Layers only — a folder poses nothing (TODO (71)). The pose's `baseline` is left out: it is
        /// §2.27's authoring state between two marks and reaches no pixel.
        let containerPoses: [ContainerPoseStamp?]
        /// **The scalars the modes read as stored bases** — `Layer.rotateSpeed`, the three shake
        /// amplitudes, and `parallaxShare` on both homes (a folder is one item beneath a Parallax
        /// layer). Their *curves* ride `channelTracks`; the typed numbers live in these fields and
        /// nowhere the tree can see.
        let rotateSpeeds: [Double]
        let parallaxShares: [Double?]
        let shakeAmplitudes: [[Double]]
        let canvasSize: CGSize?
        let canvasPadding: CGFloat
        /// **Guides, by value.** They are named from a recipe by id and edited in place keeping it,
        /// which is why `InterpolatedCelIdentity` compares them by value too — and they live on the
        /// document rather than on any cel, so no `CelStamp` can hold them. One guide reaches every
        /// in-between that binds it, which is §3.6's own definition of a structural edit.
        let guides: [GuideStroke]
        let paperColor: Color
        let paperVisible: Bool
        let renderResolution: RenderResolution
        let contentEndFrame: Int
        /// A process setting that moves the picture without touching the document. Swept here too,
        /// so explicit dirtying is a convenience rather than the only cover.
        let backend: CompositorBackend

        @MainActor
        init(_ manager: CanvasManager) {
            tree = manager.renderTree(atFrame: 0)
            effectTracks = manager.layers.map(\.effectTracks) + manager.folders.map(\.effectTracks)
            channelTracks = manager.layers.map(\.channelTracks) + manager.folders.map(\.channelTracks)
            keyframeMarks = manager.layers.map(\.keyframeMarks) + manager.folders.map(\.keyframeMarks)
            containerPoses = manager.layers.map { $0.layerTransform.map(ContainerPoseStamp.init) }
            rotateSpeeds = manager.layers.map(\.rotateSpeed)
            parallaxShares = manager.layers.map(\.parallaxShare) + manager.folders.map(\.parallaxShare)
            shakeAmplitudes = manager.layers.map { [$0.shakeX, $0.shakeY, $0.shakeRotation] }
            canvasSize = manager.canvasSize
            canvasPadding = manager.canvasPadding
            guides = manager.guideStrokes
            paperColor = manager.canvasBackgroundColor
            paperVisible = manager.isCanvasBackgroundVisible
            renderResolution = manager.renderResolution
            contentEndFrame = manager.contentEndFrame
            backend = Compositor.backend
        }
    }
}
