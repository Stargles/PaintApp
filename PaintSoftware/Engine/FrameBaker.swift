import UIKit
import SwiftUI

// MARK: - The serial baker (RENDER.md §3.6)
//
// Stage 4a and 4b built five pieces that do not touch each other: a key that names a frame's pixels
// (`FrameBakeKey`), a store that holds them (`FrameBakeStore`), a queue that says which frame is
// next (`BakeQueue`), a ring that holds the decoded frames just ahead of the playhead
// (`DecodedFrameRing`), and a recipe that turns the model into a composite off the main actor
// (`FrameRecipe`). **This file is the loop that joins them, plus the read path off it.** Stage 4d
// wired that read path to the live canvas and to playback, both through `CanvasManager.syncFrameBake`
// and `CanvasView.Coordinator.refreshBakedFull`; the ring and the digest→frames map live here because
// nothing else sees both a file name and a frame number.
//
// ## The idiom is `CanvasView.startSandwichRebuild`'s, deliberately
//
// A `@MainActor` owner, a serial `DispatchQueue`, and a hop back — the same shape the sandwich
// rebuild has used since RENDER stage 2, rather than an actor or a `Task` tree. §2.15 forbids a
// second path beside an existing one, and this *is* the existing one: mint on main in O(layers) with
// no pixel work, do every pixel on the queue, assign on the way back.
//
// **`isBaking` is mutual exclusion, not a slot**, and §3.6's *"the queue reorders, it never
// discards"* is what it is written for: every path back through `finish` clears it and kicks again,
// so a request that arrives mid-bake waits one iteration rather than evaporating, and `BakeQueue` is
// structurally incapable of losing a frame in the meantime.
//
// This paragraph used to say that behaviour was *not inherited* from `isSandwichRebuilding`, on the
// grounds that the sandwich's flag loses a declined request outright. **It does not**, and stage 4d
// checked: `finishSandwichRebuild` ends in `reconcileLayers()`, which re-derives the key from the
// model and starts the rebuild the guard declined. The two flags are one contract in two places, and
// the sandwich's is still load-bearing — the halves run on a *serial* queue, so deleting its guard
// would queue one rebuild per SwiftUI pass and hand a scrub a backlog of pictures nobody will see.

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
    private let workQueue = DispatchQueue(label: "com.paintapp.FrameBaker.bake", qos: .utility)

    /// The memory ceiling a single frame's composite may use. `ChunkedCompositor` cuts the walk to
    /// fit it (§3.4); it is a property rather than a constant so a test can force a narrow chunk
    /// width without a second code path.
    var budgetBytes: Int = CompositorBudget.textureBudgetBytes

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

    // MARK: - Scheduling state

    /// The dirty set. `private(set)` so a test can read `pendingCount` without being able to mark.
    private(set) var bakeQueue = BakeQueue()

    /// **Mutual exclusion, not a slot.** True from the moment a job is handed to `workQueue` until
    /// its result lands back on the main actor. Never two composites at once, which is what "one
    /// serial baker" means and what keeps the peak memory to one frame's chunk width.
    private(set) var isBaking = false

    /// Called on the main actor the moment the loop has nothing left — no dirty frame, and no cold
    /// frame inside the ring's lookahead — having drained and stopped rather than spun. Tests wait on
    /// it; the app does not, and a walk that failed to terminate is a hung expectation there.
    var onIdle: (() -> Void)?

    /// One consumer's interest in "a frame landed", held weakly by whoever registered it.
    private struct FrameObserver {
        weak var owner: AnyObject?
        let body: (Int) -> Void
    }

    /// Who is listening, by owner identity. See `observeFrameFinished`.
    private var frameObservers: [ObjectIdentifier: FrameObserver] = [:]

    /// **Called on the main actor after each frame the loop visits, whatever the outcome.**
    ///
    /// The read path's other half: the canvas showing a stale picture (§2.10) needs to be told the
    /// moment its own frame is ready, and the timeline's baked-frame indication (§3.7) needs to be
    /// told about every frame. A callback rather than a `@Published` counter, because publishing
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
    func observeFrameFinished(_ owner: AnyObject, _ body: @escaping (Int) -> Void) {
        frameObservers[ObjectIdentifier(owner)] = FrameObserver(owner: owner, body: body)
    }

    /// Stops `owner` listening. Not needed for correctness — a dead owner prunes itself — but a
    /// consumer that wants to stop while it is still alive has no other way to say so.
    func stopObservingFrameFinished(_ owner: AnyObject) {
        frameObservers[ObjectIdentifier(owner)] = nil
    }

    /// Reports `frame` to every live observer and forgets the dead ones.
    private func notifyFrameFinished(_ frame: Int) {
        for (id, observer) in frameObservers {
            guard observer.owner != nil else {
                frameObservers[id] = nil
                continue
            }
            observer.body(frame)
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

    /// The last thing the store refused, for a diagnostic. Cleared by `reset()`.
    private(set) var lastWriteFailure: FrameBakeStore.WriteFailure?

    // MARK: - Construction

    init(manager: CanvasManager, store: FrameBakeStore, ring: DecodedFrameRing) {
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
        guard let manager, let recipe = Self.recipe(manager, atFrame: frame) else { return nil }
        return FrameBakeKey(recipe: recipe, renderResolution: manager.renderResolution)
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

    /// The finished picture for `key`: the ring first, then the store, decoding into the ring on the
    /// way past. Nil is a miss and not an error — §2.10 keeps the previous picture up.
    ///
    /// **Ring → store → `makeImage()` is the whole chain**, and every step of it is zero-copy over
    /// one `Data`: `loadDecoded` hands back the decompressor's own buffer, the ring retains it, and
    /// `makeImage()` wraps it in a `CGDataProvider`.
    func image(for key: FrameBakeKey) -> CGImage? {
        if let resident = ring.frame(for: key.fileName) { return resident.makeImage() }
        guard let decoded = store.loadDecoded(key) else { return nil }
        ring.insert(decoded, for: key.fileName)
        return decoded.makeImage()
    }

    /// The finished picture for `frame`, or nil. The two calls above, in the order the display path
    /// wants them.
    func image(atFrame frame: Int) -> CGImage? {
        guard let key = currentKey(atFrame: frame) else { return nil }
        return image(for: key)
    }

    /// **Whether the baker holds a current file for `frame`** — the timeline's baked-frame
    /// indication (§3.7). Two dictionary lookups: no recipe, no key, no `stat`, no decode.
    ///
    /// ## This was one mint and one `stat`, and that spelling cannot serve the consumer §3.7 names
    ///
    /// The obvious body is `store.contains(currentKey(atFrame: frame))`, and that is what stood here
    /// while nothing called it. It is the right answer for **one** frame — it is what the loop does
    /// per iteration — and it is unusable for a whole ruler, which is the only thing that ever asks.
    /// A mint is `makeFrameRecipe`: a `LeafSnapshot` per visible leaf, which freezes a
    /// `VectorCanvas` or takes a raster tier's `CGContext.makeImage()`. Asking it once per frame of
    /// a 300-frame document is 300 × layers of that per redraw, and the bar redraws while the baker
    /// is running. It would cost far more than the bake it is describing.
    ///
    /// ## What "baked" means here, stated exactly, because it is not the same claim
    ///
    /// **The frame is not pending, and the baker recorded a key for it.** Those two facts together
    /// are the baker's own belief that `frame`'s current key has a file:
    ///
    /// - `keyByFrame` alone is not enough. An edit to a cel spanning frames 2–6 leaves those five
    ///   entries in place — they are only forgotten on a *failure* — so the file they name is the
    ///   picture from before the edit. The dirty bit is what says so.
    /// - The dirty bit alone is not enough either. A frame the baker has never visited is clean the
    ///   moment `markClean` runs on a write failure, and un-recorded from the start.
    ///
    /// So this is the **scheduler's** state rather than a fresh statement about the filesystem, and
    /// that is the honest thing to draw: it is the same state the canvas is in. §3.3 forbids showing
    /// a stale *file* as fresh, and nothing here does — the display path still mints its own key
    /// (`image(atFrame:)`) and a miss keeps the previous picture. This answers a different question,
    /// *"is this stretch ready to play"*, and `BakeQueue`'s own rule that over-marking dirty is
    /// always safe carries straight over: the failure this cannot have is claiming ready when it is
    /// not, and marking too much unbaked is at worst a band that clears a moment later.
    func isBaked(atFrame frame: Int) -> Bool {
        !bakeQueue.isPending(frame) && keyByFrame[frame] != nil
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
    /// so cannot be swept for: `AlphaMask`'s tuning sliders, `Compositor.backend`, a store purge.
    ///
    /// The structural sweep does carry `maskTuningGeneration` and `backend`, so calling this for
    /// those two is belt to the sweep's braces rather than the only cover.
    func markEverythingDirty() {
        if let manager { bakeQueue.frameCount = manager.sceneFrameCount }
        bakeQueue.markAllDirty()
        kick()
    }

    /// Forgets everything the baker believes: the dirty set, what is on disk, the ring. The document
    /// closing, or the store being purged underneath it.
    ///
    /// **It does not purge the store**, which is the caller's call to make (§2.11's launch dump is
    /// `FrameBakeStore.purgeAll`, invoked by the app). This only drops the bookkeeping that would
    /// otherwise claim files that are gone.
    func reset() {
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

    // MARK: - The loop

    /// Starts the loop, or does nothing if it is already running or there is nothing pending.
    ///
    /// Re-entrant and cheap: every path that could have changed what wants baking calls it, and the
    /// two guards below make a redundant call free.
    func kick() {
        guard !isBaking, !isSuspended, let manager else { return }
        bakeQueue.frameCount = manager.sceneFrameCount

        let playhead = manager.currentFrame
        guard let frame = bakeQueue.next(playhead: playhead,
                                         direction: playbackDirection,
                                         playbackRange: Self.playbackRange(of: manager),
                                         looping: manager.isLoopEnabled) else {
            // Nothing left to composite. The frames ahead of the playhead may still be cold in the
            // ring, though — see `fillRingAhead`, which is the other half of §3.5's promise that
            // play never decodes on the display thread.
            if fillRingAhead(playhead: playhead) { return }
            onIdle?()
            return
        }

        // Step 1, on the main actor and O(layers) with no pixel work — RENDER §3.2's whole seam.
        // Nothing proportional to canvas area may join these two lines.
        guard let recipe = Self.recipe(manager, atFrame: frame) else {
            // No canvas to composite into. The frame stays pending rather than being marked clean:
            // marking it would discard the request, and §3.6 says the queue never discards. The loop
            // stops here and the next `kick` — after a canvas exists — picks it up.
            onIdle?()
            return
        }
        let resolution = manager.renderResolution
        let budget = budgetBytes
        let wantsRing = Self.isWithin(ringLookahead, of: playhead, frame: frame,
                                      direction: playbackDirection)
        let frames = framesByDigest

        isBaking = true
        workQueue.async { [weak self, store] in
            // Step 2, off the main actor. Every value read here was frozen at mint time.
            let key = FrameBakeKey(recipe: recipe, renderResolution: resolution)
            let outcome: Outcome
            if store.contains(key) {
                // **The dedupe, end to end.** A dirty frame whose recomputed key already has a file
                // costs one mint and one `stat`; no composite happens at all. That is what makes a
                // nine-frame hold one file and a scrub through it free (§3.3).
                outcome = .alreadyOnDisk
            } else if let image = recipe.composite(budgetBytes: budget) {
                switch store.store(image, for: key, playhead: playhead, frames: frames) {
                case .success:
                    outcome = .baked
                case .failure(let failure):
                    outcome = .writeFailed(failure)
                }
            } else {
                outcome = .compositeFailed
            }

            // The ring is filled from the store rather than from the `CGImage` just composited, and
            // the re-read is deliberate: it is the *decode* path playback actually takes, so filling
            // the ring any other way would leave that path unexercised by every bake. One LZ4 decode
            // is single-digit milliseconds at 2048² (§3.5) and this queue is `.utility`.
            if wantsRing, outcome.isOnDisk, let decoded = store.loadDecoded(key) {
                self?.ring.insert(decoded, for: key.fileName)
            }

            Task { @MainActor in
                self?.finish(frame: frame, key: key, outcome: outcome)
            }
        }
    }

    // MARK: - Ring top-up

    /// Decodes one frame from the store into the ring, for the frames inside the lookahead the loop
    /// will never visit — and returns whether it started a job.
    ///
    /// **The loop cannot fill the ring on its own, and that gap is what this closes.** The bake job
    /// rings the frame it just wrote, so the ring is warm on the pass that *dirties* the document.
    /// Playback dirties nothing: on the second lap every frame is clean, `BakeQueue.next` answers
    /// nil, and the ring holds whatever survived from the first lap — which at a realistic budget is
    /// a handful of frames. Every tick past those would call `store.loadDecoded` from
    /// `image(for:)`, i.e. a file read and an LZ4 decode **on the display thread**, which is exactly
    /// what §3.5 rules out (*"Play never decodes on the display thread"*).
    ///
    /// `keyByFrame` rather than a fresh mint, and that is what makes this cheap enough to sit in
    /// `kick`: a frame the loop has visited and nothing has dirtied since resolves to the key
    /// recorded there, so the whole scan is dictionary lookups. A frame the baker has never seen is
    /// simply skipped — it is dirty, so the branch above this one is handling it.
    ///
    /// **One frame per call, under `isBaking`**, so this obeys the same one-job-at-a-time discipline
    /// the composite does and cannot run beside it. `finishRingFill` goes round again.
    ///
    /// ## The walk is a marker rather than a rescan, and without that it does not terminate
    ///
    /// The obvious spelling — scan from the playhead each time, fill the first frame that is not
    /// resident — spins forever the moment the lookahead is wider than the ring's byte budget, which
    /// is the ordinary case (24 frames at 8.4 MB is 200 MB against a budget of ~96). Filling
    /// `playhead + 20` evicts `playhead + 2`, the rescan finds `+2` missing, filling it evicts
    /// something else, and nothing ever converges. Worse than the spin, the ring would end up
    /// holding the *far* end of the window and not the near end, which is backwards.
    ///
    /// So the walk only ever moves outward for a given playhead, and `finishRingFill` ends it the
    /// first time the ring has no room. What that leaves resident is the nearest N frames, which is
    /// what a playhead about to walk through them wants. The marker is dropped the moment the
    /// playhead or the direction moves, so a tick re-walks — and finds the near frames already in.
    private func fillRingAhead(playhead: Int) -> Bool {
        guard ringLookahead > 0 else { return false }
        var distance = 0
        if let walk = ringWalk, walk.playhead == playhead, walk.direction == playbackDirection {
            distance = walk.nextDistance
        }
        while distance <= ringLookahead {
            let frame = playbackDirection == .forward ? playhead + distance : playhead - distance
            guard let key = keyByFrame[frame], !ring.contains(key.fileName) else {
                distance += 1
                continue
            }
            ringWalk = (playhead, playbackDirection, distance + 1)
            isBaking = true
            workQueue.async { [weak self, store] in
                let decoded = store.loadDecoded(key)
                Task { @MainActor in self?.finishRingFill(key: key, decoded: decoded) }
            }
            return true
        }
        ringWalk = (playhead, playbackDirection, ringLookahead + 1)
        return false
    }

    /// How far the top-up has already walked, and from where. See `fillRingAhead`.
    private var ringWalk: (playhead: Int, direction: BakeQueue.Direction, nextDistance: Int)?

    /// Takes one decoded frame in and goes round again — **but only if there was room for it**.
    ///
    /// `ring.count` growing is the test, and it is the honest one: `DecodedFrameRing.insert` evicts
    /// to stay under its ceiling and reports `true` either way, so a `true` that displaced something
    /// means the ring is full and everything farther from the playhead would only displace something
    /// nearer to it. It also covers the outright refusal — a frame larger than the whole budget,
    /// which that type declines by design — and a file the store no longer holds. All three end the
    /// walk for this playhead rather than the whole feature: the next tick re-walks.
    private func finishRingFill(key: FrameBakeKey, decoded: DecodedFrame?) {
        isBaking = false
        let before = ring.count
        guard let decoded, ring.insert(decoded, for: key.fileName), ring.count > before else {
            if var walk = ringWalk {
                walk.nextDistance = ringLookahead + 1
                ringWalk = walk
            }
            onIdle?()
            return
        }
        kick()
    }

    /// What one iteration did.
    private enum Outcome {
        case baked
        case alreadyOnDisk
        case writeFailed(FrameBakeStore.WriteFailure)
        case compositeFailed

        var isOnDisk: Bool {
            switch self {
            case .baked, .alreadyOnDisk: return true
            case .writeFailed, .compositeFailed: return false
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
        isBaking = false
        bakeQueue.markClean(frame)

        switch outcome {
        case .baked:
            bakedCount += 1
            record(frame: frame, key: key)
        case .alreadyOnDisk:
            dedupedCount += 1
            record(frame: frame, key: key)
        case .writeFailed(let failure):
            failedCount += 1
            lastWriteFailure = failure
            forget(frame: frame)
        case .compositeFailed:
            failedCount += 1
            forget(frame: frame)
        }

        notifyFrameFinished(frame)
        kick()
    }

    /// `frame` now resolves to `key`. Maintains both halves of the digest↔frames map.
    private func record(frame: Int, key: FrameBakeKey) {
        forget(frame: frame)
        keyByFrame[frame] = key
        framesByDigest[key.fileName, default: []].insert(frame)
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
    ///    span; this is that rule with the reference test dropped, which marks strictly more. It is
    ///    deliberate: an in-between's picture also moves when its *recipe* changes (`t`, the spacing
    ///    curve, a refitted lattice), `InterpolationRecipe` is `Codable` and not `Equatable`, and a
    ///    hand-written comparison of its fields is precisely the "which field did I forget" hazard
    ///    that a content-addressed store punishes with a wrong picture and no error. §3.3 makes the
    ///    over-marking cheap by construction: the key is the truth, so an in-between the change did
    ///    not reach has the file it had and costs one mint and no composite.
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
        bakeQueue.frameCount = manager.sceneFrameCount

        guard let previousStructure = lastStructure, let previousCels = lastCels else {
            // The first sweep. Nothing has been baked and nothing is known, so everything wants one.
            bakeQueue.markAllDirty()
            return
        }

        guard structure == previousStructure else {
            bakeQueue.markAllDirty()
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
                    touchedACel = true
                    continue
                }
                guard old != stamp else { continue }
                // Both spans: where it was, and where it is now.
                bakeQueue.markDirty(old.span)
                bakeQueue.markDirty(stamp.span)
                touchedACel = true
            }
            for old in unseen.values {
                // A cel that is gone. The frames it covered show something else now.
                bakeQueue.markDirty(old.span)
                touchedACel = true
            }
        }

        guard touchedACel else { return }
        for layer in cels {
            for stamp in layer where stamp.isDerived { bakeQueue.markDirty(stamp.span) }
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
    private struct CelStamp: Equatable {
        let id: UUID
        let start: Int
        let count: Int
        let version: LayerContentVersion
        /// Whether this cel's content is computed rather than stored — sweep tier 3.
        let isDerived: Bool

        var span: Range<Int> { start..<(start + count) }

        init(_ cel: Cel) {
            id = cel.id
            start = cel.startFrame
            count = cel.frameCount
            version = LayerContentVersion(cel: cel)
            isDerived = cel.interpolation != nil
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
    /// change. The tree is frame-invariant except for `Layer.layerEffect(atFrame:)` and
    /// `LayerFolder.resolvedEffect(atFrame:)`, and the two fields below close exactly that gap: an
    /// effect track edited so that frame 7 changes and frame 0 does not is invisible in the tree at
    /// frame 0 and plain in `effectTracks`.
    private struct StructuralStamp: Equatable {
        let tree: [RenderNode]
        /// The animated half of every layer's effect, which a single probe frame cannot see.
        let effectTracks: [[String: AnimationCurve]]
        let keyframeMarks: [[Int]]
        let canvasSize: CGSize?
        let canvasPadding: CGFloat
        let paperColor: Color
        let paperVisible: Bool
        let renderResolution: RenderResolution
        let sceneFrameCount: Int
        /// RENDER §4: both are accessors over a lock and both are fields of the bake key, so both
        /// move the picture without touching the document. Swept here so that
        /// `markEverythingDirty()` is a convenience rather than the only cover.
        let maskTuningGeneration: Int
        let backend: CompositorBackend

        @MainActor
        init(_ manager: CanvasManager) {
            tree = manager.renderTree(atFrame: 0)
            effectTracks = manager.layers.map(\.effectTracks)
            keyframeMarks = manager.layers.map(\.keyframeMarks)
            canvasSize = manager.canvasSize
            canvasPadding = manager.canvasPadding
            paperColor = manager.canvasBackgroundColor
            paperVisible = manager.isCanvasBackgroundVisible
            renderResolution = manager.renderResolution
            sceneFrameCount = manager.sceneFrameCount
            maskTuningGeneration = AlphaMask.tuningGeneration
            backend = Compositor.backend
        }
    }
}
