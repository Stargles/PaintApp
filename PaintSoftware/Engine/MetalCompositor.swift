import UIKit
import Metal
import simd

// MARK: - The GPU backend
//
// §5.1's argument for Metal is per-pixel blend math over 4.2M pixels at 2048² (16.8M at 4000²), per
// node, per frame — which CoreGraphics cannot do at interactive rates. Phase 2 built the substrate
// and the flag; phase 5 is the math arriving, which is also when the substrate stopped being enough.
// This backend used to decline any request needing an intermediate buffer, and phase 4 could afford
// that because a faded group was the only way to ask for one. Blend modes make buffers ordinary, so
// declining them would have meant the GPU handling every document except the ones it exists for.
// `CompositorMetalEngine.encode` is the scratch-texture walk that replaced the bail-out.
//
// **One correction to the plan's framing, recorded because it changes what this file costs.** §5.1
// says "the infrastructure already ships: MetalFillEngine owns a device, queue, and nine compute
// pipelines" and calls the compositor "a second consumer of an existing dependency". The device,
// queue and library-loading *patterns* are indeed reusable, and are reused below. But
// `MetalFillEngine` is built entirely on `MTLBuffer`: there is no `MTLTexture` anywhere else in this
// codebase and no `texture2d` parameter in `Fill.metal`. The textures, the upload cache and the
// readback path are new machinery, not a second consumer of old machinery.
//
// What genuinely does carry over is the pixel contract, and it carries over exactly: device RGB,
// premultiplied-last, 8 bits per component, row-major, top-left origin, scale 1 — shared by
// `PixelOps`, `RasterLayerTexture`, `MetalFillEngine`'s buffers and the fill's byte round-trip.

enum MetalCompositor {

    /// Composites `request` on the GPU, or returns nil if it cannot — **the shape callers that only
    /// want a picture keep**, and now a projection of `attempt` rather than the whole story.
    /// `Compositor.composite` uses `attempt` directly, because which kind of "no" it got decides
    /// whether the CPU reference should render the frame or nothing should.
    ///
    /// Returns nil when there is no GPU, no shader library, a degenerate canvas size, an allocation
    /// this device would not make, or a working set that does not fit the device's memory budget.
    /// **It no longer declines a group that needs its own buffer**, which is phase 5's change to this
    /// file: buffers were only reachable through a faded group in phase 4, and blend modes are §5.1's
    /// entire argument for the GPU — a document that blends falling back to the CPU would mean the
    /// GPU never runs the case it exists for. See `CompositorMetalEngine.encode`.
    static func composite(_ request: RenderRequest) -> CGImage? {
        guard case .image(let image) = attempt(request) else { return nil }
        return image
    }

    /// What one attempt at a GPU composite produced — **the frame, or which kind of "no" it was.**
    ///
    /// The two kinds are not interchangeable and `Compositor.composite` has to tell them apart: one
    /// means "this device cannot run the GPU path" and wants the CPU reference, the other means "this
    /// process has no memory right now" and wants nobody to allocate anything. See the switch there,
    /// which carries the argument.
    enum Attempt {
        case image(CGImage)
        /// No GPU, no shader library, an encode that declined, or a walk that does not fit the
        /// device's static texture budget at this canvas size. The CPU reference renders it.
        case unavailable
        /// `os_proc_available_memory()` says the allocation would not survive. Nothing renders it.
        case underPressure
    }

    static func attempt(_ request: RenderRequest) -> Attempt {
        guard let engine = CompositorMetalEngine.shared else { return .unavailable }
        return engine.attempt(request)
    }
}

// MARK: - Blend modes on the GPU

extension BlendMode {

    /// The `mode` this layer or group is dispatched with.
    ///
    /// **Must match the `kBlend…` constants in `Composite.metal`, case for case.** Written out as
    /// literals on both sides rather than derived from `allCases`, because `allCases` order is a
    /// property of the declaration and a reordering there would silently repaint every document.
    /// What catches a mismatch is `CompositorParityLogicTests` compositing every mode through both
    /// backends: a wrong code renders as some *other* real mode, which no compiler would notice and
    /// a per-mode parity table cannot miss.
    var shaderCode: UInt32 {
        switch self {
        // See `coreGraphicsBlendMode` for why `clipToBelow` shares Normal's code rather than getting
        // one of its own: by the time a mode reaches a backend it has been through `compositedMode`.
        case .normal, .clipToBelow: return 0
        case .multiply:    return 1
        case .screen:      return 2
        case .overlay:     return 3
        case .add:         return 4
        case .subtract:    return 5
        case .darken:      return 6
        case .lighten:     return 7
        case .colorDodge:  return 8
        case .colorBurn:   return 9
        case .softLight:   return 10
        case .hardLight:   return 11
        case .linearLight: return 12
        case .difference:  return 13
        case .vividLight:   return 14
        case .pinLight:     return 15
        case .linearBurn:   return 16
        case .hue:          return 17
        case .saturation:   return 18
        case .color:        return 19
        case .luminosity:   return 20
        case .divide:       return 21
        case .exclusion:    return 22
        case .lighterColor: return 23
        case .darkerColor:  return 24
        }
    }
}

// MARK: - Scratch textures

/// Canvas-sized `rgba8Unorm` scratch, handed out and taken back over the course of one composite —
/// **and now held between composites too, which is the other half of what §5.3 asked for.**
///
/// This used to be a within-frame pool, allocated fresh per `composite` call, and the doc comment
/// here declined the across-frames half on the grounds that it "needs an eviction rule … and nothing
/// in the app can answer that yet: the consumer that would is §5.2's sandwich". **The sandwich
/// shipped, so that consumer now exists**, and it answered the question in a way that made the rule
/// smaller than expected rather than larger: the pool's occupancy is bounded by *nesting depth*, not
/// by layer count or by anything the artist can grow without bound, so there is no per-entry
/// eviction decision to make at all. The lifetime question left is the canvas size, and
/// `CompositorMetalEngine` answers it by holding **one pool per size** in a bounded LRU map — see
/// `pools` there for why the older "discard the whole pool when the size changes" rule was wrong.
///
/// What the change buys is measured rather than assumed: a sandwich rebuild is three composites over
/// one shared snapshot, so a per-composite pool re-allocated two canvas-sized textures three times
/// per repaint (33.6 MB at 2048², 128 MB at 4000²) for a working set that never changed.
///
/// **The contents of a reused texture are stale pixels rather than zeros, and that is the one thing
/// this makes sharper.** `acquire` never promised anything about contents and every caller already
/// fills or fully overwrites what it takes — but before this change "undefined" happened to mean a
/// fresh driver allocation, and now it means the last composite's output. So the failure mode of a
/// caller that reads before writing changes from a black region to *a previous frame showing
/// through*, which is harder to spot and easier to mistake for a caching bug elsewhere. The guard at
/// `encode`'s effect case is the live instance of that hazard and already argues it; nothing else in
/// this file reads a scratch texture it has not written, and `Composite.metal`'s four kernels all
/// write unconditionally (there is no early return in any of them).
///
/// Nesting is what the count is bounded by, not layer count: bottom-to-top evaluation holds two
/// textures per buffered level, and levels are few. `PerfBaselineTests` reports `scratchAllocated`
/// so a regression that starts allocating per group is visible as a number rather than as a stall —
/// and that number is now per *composite*, not lifetime, so a warm engine reporting 0 is the pool
/// working rather than the metric breaking.
private final class ScratchTexturePool {

    private let device: MTLDevice
    let width: Int
    let height: Int
    private var free: [MTLTexture] = []

    /// How many textures this composite created. Reset by `beginComposite`, because a lifetime total
    /// stops being the interesting number the moment the pool outlives one frame: what a reader wants
    /// to know is whether *this* frame allocated, and a warm pool's answer is 0.
    private(set) var allocatedThisComposite = 0

    /// The largest walk this pool has served, in bytes — what the upload cache's budget is subtracted
    /// from, summed over every resident size.
    ///
    /// **Per pool rather than per engine, and that is not a refinement but a requirement of the map.**
    /// One shared mark used to be reset whenever the pool was rebuilt at a new size, so it tracked
    /// whichever size composited last. With a pool per size nothing rebuilds, so a shared mark would
    /// have been set by the largest consumer and never lowered again — the 320² thumbnail would go on
    /// subtracting a 4096² canvas's walk from the upload cache's budget forever. Living on the pool
    /// makes it die with the textures it accounts for, which is what it always claimed to do.
    var highWaterBytes = 0

    init(device: MTLDevice, width: Int, height: Int) {
        self.device = device
        self.width = width
        self.height = height
    }

    func beginComposite() { allocatedThisComposite = 0 }

    /// A texture whose contents are **undefined** — see the type's note on what "undefined" now means
    /// in practice. Every caller either fills it (`compositeFill`) or writes every pixel of it
    /// (`compositeOver` writes unconditionally), so there is no clear here to pay for on a texture
    /// that is about to be overwritten anyway.
    func acquire() -> MTLTexture? {
        if let reused = free.popLast() { return reused }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared // read back on the CPU without a blit
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        allocatedThisComposite += 1
        return texture
    }

    /// Returns a texture for reuse. **Safe only because dispatches inside one
    /// `MTLComputeCommandEncoder` are serial by default** (`MTLDispatchType.serial`, which inserts
    /// the barriers between them): the next acquirer's first write is ordered after the last dispatch
    /// that read this texture, so handing the same memory to two groups in sequence cannot race. A
    /// `.concurrent` encoder would need explicit `memoryBarrier` calls here, which is worth knowing
    /// before anyone reaches for one as an optimisation.
    func release(_ texture: MTLTexture) {
        free.append(texture)
    }
}

// MARK: - The upload cache

/// One leaf's pixels on the GPU, kept between composites and keyed by **model identity**.
///
/// **This is the second attempt at this cache and the first one that can hit.** The first keyed on
/// `ObjectIdentifier` of the rendered `CGImage`, which `PixelOps.rasterize` mints fresh on every
/// call — measured at a zero hit rate and deleted, and `LayerRenderSource`'s doc comment records
/// both the measurement and the shape of a key that would work: "from the model rather than from
/// the rendered result … plus the request's quality, since `.preview` and `.full` are different
/// pixels". That key exists now. `LayerContentVersion` is exactly it, the request carries one per
/// leaf in `contentVersions`, and this type is the consumer that comment predicted.
///
/// **The pixel dimensions are in the key as well as the version**, which the prediction did not
/// mention and which is not redundant: a layer's content version does not move when the *canvas*
/// resizes, so a padding change would otherwise serve a 2048-wide texture for a 2176-wide canvas —
/// a wrong-sized `MTLTexture` read by a full-canvas dispatch, which is a garbage frame rather than a
/// stale one.
///
/// ### Why a byte budget rather than an entry count
///
/// A canvas-sized texture is 16.8 MB at 2048² and 64 MB at 4000² (§5.3), so an entry count means
/// something four times different at the two sizes and would be right at neither.
///
/// **The number itself used to be a constant — 192 MB — and that constant was tuned on a Mac.** It
/// is now whatever `CompositorBudget` leaves over after the walk's own textures are accounted for,
/// which on the 3 GB iPad the owner reported from is a very different figure from the 8 GB machine
/// the branch was measured on. See `budgetBytes`, which the engine sets per composite.
///
/// **The degradation is not graceful and that is worth stating plainly rather than discovering.** A
/// composite walks its leaves in a fixed bottom-to-top order, so a document whose leaves do not all
/// fit is the textbook LRU thrash: every leaf is evicted exactly before it is next wanted, and the
/// hit rate is 0 rather than "reduced". That is *no worse* than the uncached path this replaces —
/// the same uploads happen, plus a dictionary probe — but it is a cliff and not a slope, and
/// anybody raising the budget should know they are moving a cliff. It is also why the cache is the
/// part of the working set that is allowed to lose: everything else in the engine is something the
/// walk cannot proceed without, and this is the only piece whose absence costs nothing but time.
///
/// Not thread-safe: `CompositorMetalEngine` holds one lock across the whole of `composite` and this
/// is only ever touched from inside it.
private final class UploadCache {

    struct Key: Hashable {
        let content: LayerContentVersion
        let quality: RenderQuality
        let width: Int
        let height: Int
    }

    /// What is left of `CompositorBudget.textureBudgetBytes` once the walk's own textures are
    /// subtracted — written by the engine at the top of every composite, because the subtrahend is a
    /// property of the tree being composited and changes with it.
    ///
    /// Starts at zero rather than at some optimistic default: an unconfigured cache that holds
    /// nothing is the uncached path, and the uncached path is correct.
    var budgetBytes = 0

    private struct Entry {
        let texture: MTLTexture
        let bytes: Int
        var lastUsed: UInt64
    }

    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private var residentBytes = 0

    /// Reported by `PerfBaselineTests`. Lifetime totals, deliberately: the question they answer is
    /// "does the key hit at all", which the first attempt at this cache got wrong and which a
    /// per-composite counter would make harder rather than easier to see.
    private(set) var hits = 0
    private(set) var misses = 0

    /// Current entry count — distinct from `hits`/`misses`, which are lifetime totals and cannot say
    /// whether the cache is empty right now. For `CompositorMetalEngine.uploadCacheEntryCount`.
    var count: Int { entries.count }

    func texture(for key: Key) -> MTLTexture? {
        guard var entry = entries[key] else {
            misses += 1
            return nil
        }
        hits += 1
        clock += 1
        entry.lastUsed = clock
        entries[key] = entry
        return entry.texture
    }

    func store(_ texture: MTLTexture, for key: Key) {
        clock += 1
        let bytes = key.width * key.height * 4
        if let existing = entries.updateValue(Entry(texture: texture, bytes: bytes, lastUsed: clock),
                                              forKey: key) {
            residentBytes -= existing.bytes
        }
        residentBytes += bytes
    }

    /// Evicts down to the budget, **called at the end of a composite and never during one.**
    ///
    /// Evicting mid-walk would be the only way this could hand back a texture the encoder still
    /// refers to. It cannot happen at this call site, and a command buffer from `makeCommandBuffer()`
    /// retains its referenced resources anyway, so the ordering here is belt and braces — but it is
    /// also free, because the overshoot it permits is bounded by one snapshot's worth of leaves,
    /// which is precisely the set the composite needed resident regardless.
    func trimToBudget() {
        guard residentBytes > budgetBytes else { return }
        for key in entries.sorted(by: { $0.value.lastUsed < $1.value.lastUsed }).map(\.key) {
            guard residentBytes > budgetBytes else { return }
            if let removed = entries.removeValue(forKey: key) { residentBytes -= removed.bytes }
        }
    }

    /// Drops everything. **`purgeLocked` is the only caller now**, which is a change: a canvas resize
    /// used to call it too, on the reasoning that every key was stale at that point. That reasoning
    /// was right about staleness and wrong about what to do with it — two consumers composite the
    /// same document at two sizes (see the pool's size check), so "the size changed" is not "the
    /// other entries are dead", and `trimToBudget` reclaims them in use order without throwing away
    /// the set the next composite is about to want back.
    func removeAll() {
        entries.removeAll(keepingCapacity: true)
        residentBytes = 0
    }
}

// MARK: - Device, pipelines, and the upload cache

/// Owns the compositor's `MTLDevice`, queue and kernels — the same shape as `MetalFillEngine`, and
/// separate from it because the two share no pipelines and a failure in one should not disable the
/// other.
final class CompositorMetalEngine {

    /// Nil when there is no GPU, no shader library, or a kernel that would not build — exactly
    /// `MetalFillEngine`'s failable-singleton contract, and for the same reason: the caller has a
    /// working path without it, so there is nothing to assert about.
    static let shared = CompositorMetalEngine()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let psOver: MTLComputePipelineState
    private let psFill: MTLComputePipelineState
    private let psMask: MTLComputePipelineState
    private let psEffectMix: MTLComputePipelineState

    /// §4.4's grade, as `MetalEffects` already packaged it — **held optionally on purpose.** A library
    /// without `applyEffect` should cost the effect layers a CPU frame, not disable compositing for
    /// every document; `encode` returns false when a tree actually needs one and it is missing, which
    /// is `Compositor.composite`'s cue to render the whole frame through the reference instead.
    private let effects: EffectPipelines?

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }

        // **`makeDefaultLibrary()` reads `Bundle.main`, and in a test process that is the wrong
        // bundle.** The XCUITest runner is the main bundle; this code and its compiled
        // `default.metallib` live in `PaintSoftwareUITests.xctest`, a plug-in inside it. Asking for
        // the library by the bundle that owns *this class* resolves to the app bundle in the app and
        // to the .xctest bundle under test, so one line covers both.
        //
        // This is the whole reason the GPU has never been exercisable in the fast tier, and it is
        // worth knowing that it was two problems rather than one: `Fill.metal` was never a member of
        // the test target (still isn't, so `MetalFillEngine.shared` is still nil here), *and*
        // `MetalFillEngine` asks for its library the way that cannot work from a plug-in.
        let library = (try? device.makeDefaultLibrary(bundle: Bundle(for: CompositorMetalEngine.self)))
            ?? device.makeDefaultLibrary()
        guard let library else { return nil }

        func pipeline(_ name: String) -> MTLComputePipelineState? {
            guard let fn = library.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }
        guard let over = pipeline("compositeOver"), let fill = pipeline("compositeFill"),
              let mask = pipeline("compositeMask"), let effectMix = pipeline("compositeEffectMix")
        else { return nil }
        self.device = device
        self.queue = queue
        self.psOver = over
        self.psFill = fill
        self.psMask = mask
        self.psEffectMix = effectMix
        self.effects = EffectPipelines(device: device, library: library)

        // **The valve that makes the caches above safe to hold on a device.** Everything this engine
        // keeps between composites is a pure memoization — a cached upload is re-derivable from the
        // request that asked for it, and a pooled scratch texture is re-derivable from nothing at all
        // — so under pressure the correct move is to give all of it back and let the next frame be a
        // cold one. That trade only exists because the fallback exists: the worst case here is the
        // 258.6 ms cold composite `Compositor.backend` tabulates, not a failure.
        //
        // Registered rather than left to the OS because nothing else would free it. The upload cache
        // is bounded by its own budget and the pool by nesting depth, so neither shrinks on its own
        // when the artist switches to a different app mid-drawing — they sit at their high-water mark
        // holding up to 192 MB against a document nobody is looking at.
        //
        // Delivered on the posting thread, so this can block main for as long as a composite takes if
        // one is in flight. That is the right way round: a jettison that waits ~30 ms is cheaper than
        // the termination it is trying to avoid.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.purge()
        }

        // **The event that actually arrives.** The memory warning above is the one the owner reports
        // never firing on their device; backgrounding is the moment this doc comment already
        // describes — the artist switches apps and these caches sit at their high-water mark against
        // a document nobody is looking at. Same `purge()`, same correctness-neutral guarantee; the
        // only new cost is one cold composite (~53 ms at 2048², MEASURED, iPad 9, Metal — see
        // PERFORMANCE.md item 12) on the frame after the artist returns.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.purge()
        }
    }

    /// Drops everything held between composites. Correctness-neutral by construction — see the
    /// registration in `init` — so this is safe to call at any time and from any thread.
    func purge() {
        lock.lock()
        defer { lock.unlock() }
        purgeLocked()
    }

    /// `purge`'s body, for the caller that is already inside the lock — `attempt`, when the dynamic
    /// headroom valve closes on it. Giving the caches back is the whole of the response there:
    /// nothing else in the process is going to free 300 MB on this frame's behalf, the frame is not
    /// being rendered by anybody (a pressure decline is the one `Compositor.composite` answers with
    /// nil), and every byte held here is re-derivable by the rebuild that retries.
    private func purgeLocked() {
        uploads.removeAll()
        pools.removeAll()
        poolOrder.removeAll()
        // The intermediates go too, which they did not before `releaseIntermediates` existed — see
        // that method. They are the largest single thing this engine held that a purge could not
        // reach: 128 MiB at 4096², against a memory warning the purge exists to answer.
        effects?.releaseIntermediates()
    }

    /// The last composite's admission decision, for `PerfBaselineTests`. Nil until one has been made.
    ///
    /// Reported rather than logged because the whole failure this closes was invisible: a frame that
    /// declines looks exactly like a frame that succeeded slowly, since `Compositor.composite` hands
    /// back a correct picture either way. A test that cannot see which of the two happened cannot pin
    /// the budget rule.
    private(set) var lastAdmission: Admission?

    /// Why a composite was or was not run on the GPU.
    enum Admission: Equatable {
        case admitted
        /// The walk's own textures do not fit `CompositorBudget.textureBudgetBytes` at this canvas
        /// size on this device. Static, so the same tree at the same size always answers the same.
        case overBudget(wantedBytes: Int, budgetBytes: Int)
        /// The budget would have allowed it, but `os_proc_available_memory()` says the process cannot
        /// afford the allocation right now. Dynamic, and the reason `purgeLocked` runs with it.
        case noHeadroom(wantedBytes: Int)
    }

    /// How many scratch textures the last composite allocated. Reported by `PerfBaselineTests`;
    /// nothing in the render path reads it. **A warm engine reports 0** — see `ScratchTexturePool`.
    private(set) var lastScratchAllocated = 0

    /// The upload cache's lifetime hit and miss counts, for `PerfBaselineTests`. Read under the same
    /// lock everything else here is, so a test reading them between composites sees a settled pair.
    var uploadCacheCounts: (hits: Int, misses: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (uploads.hits, uploads.misses)
    }

    /// The upload cache's current entry count, for the backgrounding-purge test — `uploadCacheCounts`
    /// is a lifetime hit/miss pair and cannot say whether the cache is empty *right now*. Same lock.
    var uploadCacheEntryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return uploads.count
    }

    /// **Everything below is state that outlives one composite, and this is what makes that safe.**
    ///
    /// Two queues reach `Compositor.composite` today — `CanvasView.sandwichQueue` for the live canvas
    /// and `ProjectStore`'s save queue for the thumbnail — and neither knows about the other, so a
    /// save landing during a repaint would have two threads inside the pool and the cache at once.
    /// That was survivable while this type held nothing but `lastScratchAllocated` (a torn metric);
    /// it stops being survivable the moment a dictionary and a free-list are in here.
    ///
    /// Held across the *whole* of `composite` rather than around each touch of the shared state,
    /// because a texture handed out by the pool is owned by the walk until the walk gives it back —
    /// a finer lock would let a second composite acquire the accumulator the first is still writing.
    /// The cost is that two composites serialise, which they effectively did anyway: they contend for
    /// one GPU and each ends in `waitUntilCompleted`.
    private let lock = NSLock()

    /// One scratch pool per composite size, bounded at `residentPoolSizeLimit`, least recently used
    /// evicted first.
    ///
    /// **This was a single pool discarded whenever the size changed, and that rule cost the live
    /// canvas its whole working set on every autosave.** `ProjectStore`'s save thumbnail composites
    /// the same document at `thumbnailBounds` through this same engine (`ProjectStore.swift`, the
    /// `fittingWithin:` request), so a save alternates two sizes — and under the old rule each one
    /// threw the other's pool and effect intermediates away: 256 MiB of reallocation at 4096² and a
    /// cold frame for the artist immediately after, for a 320² picture nobody was drawing on. The
    /// upload cache had already been corrected for exactly this reason (see `UploadCache.removeAll`,
    /// "two consumers composite the same document at two sizes"); the pool and the intermediates were
    /// left on the old rule, and RENDER.md §4 requires them fixed before §3.6's background baker
    /// arrives as a third consumer.
    ///
    /// **The map is bounded and its total respects the same budget one walk is admitted against.**
    /// Two sizes each holding a budget's worth would be a worse bug than the one this fixes, so
    /// `makeRoom` evicts other sizes until this walk fits alongside what is left. Three is the number
    /// of consumers RENDER.md names — the live canvas at the artist's render resolution, the save
    /// thumbnail, and the baker — and `EffectPipelines.residentSizeLimit` is deliberately the same,
    /// because the engine drops that map's entry whenever it evicts a pool here.
    private var pools: [TexturePixelSize: ScratchTexturePool] = [:]
    /// Least recently used first, so `first` is the eviction victim.
    private var poolOrder: [TexturePixelSize] = []
    private let uploads = UploadCache()

    /// How many sizes' scratch pools are held at once. See `pools`.
    static let residentPoolSizeLimit = EffectPipelines.residentSizeLimit

    /// The sizes whose scratch pools are resident, least recently used first. For the tests that pin
    /// the map's bound and its survival across a second consumer's composite; nothing in the render
    /// path reads it.
    var residentPoolSizes: [TexturePixelSize] {
        lock.lock()
        defer { lock.unlock() }
        return poolOrder
    }

    /// What every resident size's walk holds between them — the number subtracted from
    /// `CompositorBudget.textureBudgetBytes` to give the upload cache its budget, and the number the
    /// map's invariant is stated in. Same lock as everything else here.
    var residentPoolHighWaterBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return residentPoolHighWaterBytesLocked()
    }

    private func residentPoolHighWaterBytesLocked(excluding excluded: TexturePixelSize? = nil) -> Int {
        poolOrder.reduce(0) { total, key in
            key == excluded ? total : total + (pools[key]?.highWaterBytes ?? 0)
        }
    }

    /// Evicts other sizes until this walk can be admitted alongside what is left — **the whole of the
    /// map's memory rule, in one place.**
    ///
    /// Two conditions, and they are different questions. The first is the map's own bound, which
    /// keeps a long session from accumulating a pool per render resolution the artist has ever
    /// selected. The second is the budget: `wanted` was already checked against it on its own, so a
    /// composite that fits can always be made to fit by giving back sizes nobody is compositing at —
    /// and that is why this evicts rather than declining. Declining a live frame because a save
    /// thumbnail is still resident would be the size map making things worse than the rule it
    /// replaced.
    ///
    /// Never evicts `size` itself: that is the pool the caller is about to use, and a limit of one
    /// would otherwise throw it away and rebuild it every frame.
    private func makeRoom(for size: TexturePixelSize, wanted: Int, budget: Int) {
        while pools[size] == nil, pools.count >= Self.residentPoolSizeLimit, evictLeastRecentlyUsedPool(other: size) {}
        while residentPoolHighWaterBytesLocked(excluding: size) + wanted > budget,
              evictLeastRecentlyUsedPool(other: size) {}
    }

    /// Drops the least recently used pool that is not `kept`, and the effect intermediates allocated
    /// beside it — the two maps are one set (see `EffectPipelines.residentSizeLimit`). False when
    /// there is nothing left to give back.
    private func evictLeastRecentlyUsedPool(other kept: TexturePixelSize) -> Bool {
        guard let victim = poolOrder.first(where: { $0 != kept }) else { return false }
        pools.removeValue(forKey: victim)
        poolOrder.removeAll { $0 == victim }
        effects?.releaseIntermediates(at: victim)
        return true
    }

    func attempt(_ request: RenderRequest) -> MetalCompositor.Attempt {
        let width = Int(request.canvasSize.width.rounded())
        let height = Int(request.canvasSize.height.rounded())
        guard width > 0, height > 0 else { return .unavailable }

        lock.lock()
        defer { lock.unlock() }

        // MARK: Admission — decided before anything is allocated
        //
        // **The branch that flipped this backend on had no such check, and that is the crash.** It
        // measured a 4096² canvas nowhere: on the simulator the working set below disappears into a
        // Mac's memory, and on an iPad 9 (3 GB shared between CPU and GPU) the same tree wants
        // 384 MiB of texture before the readback has allocated a byte. `Metal.makeTexture` does not
        // politely return nil under that pressure — jetsam kills the process first, so a nil check
        // at the allocation site is a guard that never fires.
        //
        // Refusing *here* is what makes the refusal cheap. Everything past this point allocates, and
        // a composite that discovers halfway down that it cannot finish has already spent the memory
        // it was trying not to spend.
        let canvasBytes = width * height * 4
        let walkTextures = request.tree.peakCompositeTextures
        let wanted = walkTextures * canvasBytes
        let budget = CompositorBudget.textureBudgetBytes
        guard wanted <= budget else {
            lastAdmission = .overBudget(wantedBytes: wanted, budgetBytes: budget)
            // `.unavailable`, not `.underPressure`: this is a *static* verdict about the device and
            // the canvas size, and the CPU reference is the only thing that can render this frame at
            // all. On the live canvas it should never fire, because `makeSandwichRecipe` has
            // already sized the request against the same budget — it is a request built at
            // `RenderSizing.native` (the eyedropper, `CanvasManager+Eyedropper.swift`, composites at
            // native size on purpose so a colour pick never blends in a downscale) that reaches it.
            return .unavailable
        }
        // Cold means the pool has to be built from nothing, so the whole working set is a new
        // allocation; warm means the pool and the intermediates are already resident and the only
        // new canvas-sized thing this frame will ask for is the image `readBack` hands out.
        //
        // **This is one of the two things the size map buys directly**: the live canvas's next frame
        // after a save used to be cold, because the save's own size had evicted it. It is warm now.
        let size = TexturePixelSize(width: width, height: height)
        let isCold = pools[size] == nil
        guard CompositorBudget.hasHeadroom(for: isCold ? wanted + canvasBytes : canvasBytes) else {
            lastAdmission = .noHeadroom(wantedBytes: wanted)
            // Give back what is held before declining. The CPU reference is about to composite this
            // same frame and will want a canvas-sized buffer or three of its own, and everything this
            // engine is sitting on is re-derivable — so holding it through a fallback is holding it
            // at exactly the moment it is pure cost.
            purgeLocked()
            return .underPressure
        }
        lastAdmission = .admitted

        // Ping-pong rather than one read_write accumulator: `access::read_write` on `rgba8Unorm`
        // needs the GPU family's read-write texture support, and two scratch textures cost 33.6 MB at
        // 2048² against a correctness risk on older hardware.
        //
        // Kept between composites and **kept per size** — see `pools` for what the old
        // discard-on-size-change rule cost, and for why the upload cache was corrected out of it
        // first (`UploadCache.removeAll`) while the pool and the intermediates were left behind.
        makeRoom(for: size, wanted: wanted, budget: budget)
        let pool: ScratchTexturePool
        if let existing = pools[size] {
            pool = existing
        } else {
            pool = ScratchTexturePool(device: device, width: width, height: height)
            pools[size] = pool
        }
        poolOrder.removeAll { $0 == size }
        poolOrder.append(size)

        // The cache gets what the walk does not need. It is the only part of the working set whose
        // absence costs nothing but time (see `UploadCache`), so it is the part that absorbs a tight
        // budget — at zero it simply stops hitting and every upload happens the way it did before the
        // cache existed.
        //
        // **Against the high-water mark rather than against this request, and a sandwich rebuild is
        // exactly why.** Three composites share one engine: `full` holds five textures at 4K with a
        // bloom in it, and `below` — everything under the active layer, which can be nothing at all —
        // holds two. Sizing the cache from `below`'s own need would hand it the three textures the
        // pool and the intermediates are *still* sitting on, because neither is freed between the
        // three. The mark lives on the pool and dies with it, which is the only point at which those
        // textures genuinely go away.
        //
        // **Summed over every resident size**, because every resident size is holding its textures
        // simultaneously — that is what "the total across the map respects the budget" means at the
        // one place the budget is spent.
        pool.highWaterBytes = max(pool.highWaterBytes, wanted)
        uploads.budgetBytes = max(0, budget - residentPoolHighWaterBytesLocked())
        pool.beginComposite()
        defer {
            lastScratchAllocated = pool.allocatedThisComposite
            uploads.trimToBudget()
        }

        guard var front = pool.acquire(), var back = pool.acquire(),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else { return .unavailable }
        // The accumulator pair goes back on every exit, including the failure ones — otherwise a
        // frame that declines (a missing effect pipeline, a command-buffer error) would leave two
        // canvas-sized textures stranded and the next frame would allocate two more. `front` and
        // `back` are swapped throughout the walk; which is which by now does not matter, since the
        // pool takes them as interchangeable.
        defer {
            pool.release(front)
            pool.release(back)
        }

        fillBackground(request, into: front, encoder: encoder, width: width, height: height)

        // One upload per distinct mask for this composite, not per masked node — the resolution is
        // already shared (`MaskResolver`), and re-uploading the same 4.2 MB once per layer clipped
        // to it would spend on the GPU exactly what that sharing saves on the CPU.
        var maskTextures: [ObjectIdentifier: MTLTexture] = [:]
        // `paperInBackdrop` is true only at this call — the mirror of the CPU reference's, and its
        // doc carries the reasoning. Every buffered scope inside starts from transparency.
        let encoded = encode(request.tree, of: request, front: &front, back: &back,
                             encoder: encoder, pool: pool, masks: &maskTextures,
                             width: width, height: height,
                             paperInBackdrop: request.background != nil)
        encoder.endEncoding()
        guard encoded else { return .unavailable }

        commands.commit()
        commands.waitUntilCompleted()
        guard commands.error == nil else { return .unavailable }
        guard let image = readBack(front, width: width, height: height) else { return .unavailable }
        return .image(image)
    }

    /// Encodes one bottom-to-top stack, accumulating into `front` and ping-ponging through `back`.
    ///
    /// **The mirror of `CoreGraphicsCompositor.draw`, deliberately structured the same way** — same
    /// visibility gates, same `needsOwnBuffer` question in the same place, same "a buffered group
    /// starts from transparency" rule. Two backends that agree because they were written to the same
    /// shape are cheaper to keep in agreement than two that happen to produce the same pixels, and
    /// the CPU one carries the prose explaining *why* each of those choices is what it is; this one
    /// says only what is different about doing it on a GPU.
    ///
    /// Returns false if an upload or an allocation failed, at which point `Compositor.composite`
    /// falls back to the CPU and renders the frame slowly instead of not at all.
    private func encode(_ nodes: [RenderNode], of request: RenderRequest,
                        front: inout MTLTexture, back: inout MTLTexture,
                        encoder: MTLComputeCommandEncoder, pool: ScratchTexturePool,
                        masks: inout [ObjectIdentifier: MTLTexture],
                        width: Int, height: Int, paperInBackdrop: Bool) -> Bool {
        for node in nodes {
            switch node.content {
            case .leaf(let layerIndex):
                guard node.isVisible else { continue }
                // §4.4's stack layer, reached before `sources` for the reason the CPU reference
                // gives: an effect layer has no pixels to find, only a grade over `front` — which
                // *is* "the backdrop accumulated so far in this container", since a buffered group
                // handed this walk its own accumulator.
                if let effect = node.effect {
                    // **EFFECT_BACKDROP.md §3 option A's re-walk**, the mirror of
                    // `CoreGraphicsCompositor.gradedInkOverPaper` — which carries the reasoning for
                    // the option, for the grade *replacing* what is below rather than compositing
                    // over it, and for the one consequence that is inherent to A. Same cut of the
                    // tree the sandwich's lower half uses, into a pair of this pool's textures
                    // instead of onto the canvas, so the sub-walk is this same function and there is
                    // no second implementation of anything to keep in step.
                    //
                    // Switched exhaustively on `Effect.Input` rather than tested against `.ink`, for
                    // the reason `CoreGraphicsCompositor.draw` gives at the same fork.
                    let inkBelow: [RenderNode]?
                    switch effect.input {
                    case .ink:
                        inkBelow = paperInBackdrop ? request.tree.split(atLeaf: layerIndex)?.below : nil
                    case .backdrop:
                        inkBelow = nil
                    }
                    if let below = inkBelow {
                        guard let effects,
                              let inkA = pool.acquire(), let inkB = pool.acquire() else { return false }
                        var inkFront = inkA, inkBack = inkB
                        defer {
                            pool.release(inkFront)
                            pool.release(inkBack)
                        }
                        fill(inkFront, with: SIMD4<Float>(repeating: 0), encoder: encoder,
                             width: width, height: height)
                        // `paperInBackdrop: false` inside: the buffer was just filled transparent,
                        // and it is also what terminates the recursion — a nested ink effect down
                        // here already has the ink-only input it was asking for.
                        guard encode(below, of: request, front: &inkFront, back: &inkBack,
                                     encoder: encoder, pool: pool, masks: &masks,
                                     width: width, height: height,
                                     paperInBackdrop: false) else { return false }
                        guard let graded = pool.acquire() else { return false }
                        defer { pool.release(graded) }
                        // A declined encode fails the whole walk for the reason spelled out in the
                        // backdrop path below: `graded` still holds whatever the pool last left in
                        // it, and mixing that in would put a previous frame on screen.
                        guard effects.encode(effect, source: inkFront, into: graded,
                                             encoder: encoder) else { return false }
                        // `inkFront` is dead the moment the grade has read it and `inkBack` holds a
                        // stale intermediate, so the paper-plus-graded picture is built in the pair
                        // already held rather than in a fourth texture — the same observation the
                        // group path makes about `groupBack` below.
                        fillBackground(request, into: inkBack, encoder: encoder,
                                       width: width, height: height)
                        // `.normal` at opacity 1: this is the accumulator as it would be if `below`
                        // had been replaced by the grade, not a layer being laid on anything. The
                        // node's own opacity and mask arrive once, in the `mix` beneath.
                        over(source: graded, opacity: 1, mode: .normal,
                             front: &inkBack, back: &inkFront, encoder: encoder,
                             width: width, height: height)
                        // `over` ends in a swap of the two it was given, so `inkBack` now names the
                        // paper-plus-graded result and `inkFront` the paper it was drawn onto.
                        //
                        // The same `mix` the backdrop path uses, with the mask as its coverage
                        // argument rather than clipping a copy of the graded image: opacity and the
                        // mask read as an *amount*, so at 0 this is the untouched accumulator and at
                        // 1 the replacement exactly. Source-over could not say that — it added the
                        // ink a second time, which is the defect this replaced.
                        mix(base: front, graded: inkBack,
                            coverage: maskTexture(for: node, of: request, cache: &masks),
                            opacity: node.opacity, into: back, encoder: encoder,
                            width: width, height: height)
                        swap(&front, &back)
                        continue
                    }
                    guard let effects, let scratch = pool.acquire() else { return false }
                    // **A declined encode has to fail the whole walk, not fall through to `mix`.**
                    // `encode` returns false when it could not allocate the intermediates a
                    // multi-pass effect ping-pongs through, and in that case it has written nothing
                    // — `scratch` still holds whatever the pool last left there. Mixing that in
                    // would put a previous frame's pixels on screen as though they were this
                    // effect's output: a wrong picture with no error anywhere, which is strictly
                    // worse than the black frame a hard failure gives. Returning false instead is
                    // the contract the rest of this file already runs on — the caller falls back to
                    // `CoreGraphicsCompositor`, which has no allocation to decline and computes the
                    // grade correctly, just slower.
                    guard effects.encode(effect, source: front, into: scratch, encoder: encoder) else {
                        pool.release(scratch)
                        return false
                    }
                    mix(base: front, graded: scratch,
                        coverage: maskTexture(for: node, of: request, cache: &masks),
                        opacity: node.opacity, into: back, encoder: encoder,
                        width: width, height: height)
                    swap(&front, &back)
                    pool.release(scratch)
                    continue
                }
                guard request.sources.indices.contains(layerIndex),
                      let source = request.sources[layerIndex] else { continue }
                guard let texture = upload(source, of: request, at: layerIndex) else { return false }
                // A masked leaf takes one extra dispatch and one scratch texture: the mask multiply
                // writes into `rgba8Unorm` before the composite reads it, which puts the GPU's
                // quantization at the same point as `MaskResolver.apply`'s on the CPU. Folding the
                // multiply into `compositeOver` instead would be one dispatch cheaper and would move
                // that point, which is the whole of the byte-for-byte agreement.
                var drawn = texture
                var scratch: MTLTexture?
                if let mask = maskTexture(for: node, of: request, cache: &masks) {
                    guard let clipped = pool.acquire() else { return false }
                    scratch = clipped
                    apply(mask: mask, to: texture, into: clipped, encoder: encoder,
                          width: width, height: height)
                    drawn = clipped
                }
                over(source: drawn, opacity: node.opacity, mode: node.blendMode,
                     front: &front, back: &back, encoder: encoder, width: width, height: height)
                if let scratch { pool.release(scratch) }

            case .node(let op, let inputs):
                // A hidden group is a subtree this walk does not enter, so it needs no texture to
                // gate and costs nothing to skip (§4.1).
                guard node.isVisible else { continue }
                guard node.needsOwnBuffer else {
                    // `needsOwnBuffer` is false only for `.stack`, so nothing is folding here that
                    // this loop is silently flattening — see `CompositorOp.needsOwnBuffer`.
                    for input in inputs {
                        // Straight onto the caller's accumulator, so the paper is still in it.
                        guard encode(input, of: request, front: &front, back: &back,
                                     encoder: encoder, pool: pool, masks: &masks,
                                     width: width, height: height,
                                     paperInBackdrop: paperInBackdrop) else { return false }
                    }
                    continue
                }

                guard var groupFront = pool.acquire(), var groupBack = pool.acquire() else { return false }
                defer {
                    pool.release(groupFront)
                    pool.release(groupBack)
                }
                fill(groupFront, with: SIMD4<Float>(repeating: 0), encoder: encoder,
                     width: width, height: height)
                guard fold(op, inputs, of: request, front: &groupFront, back: &groupBack,
                           encoder: encoder, pool: pool, masks: &masks,
                           width: width, height: height) else { return false }
                // §4.4's second wrapper (phase 9b), mirroring the leaf case's grade above verbatim —
                // same acquire/encode/mix/swap/release shape, just against `groupFront`/`groupBack`
                // instead of `front`/`back`. Runs immediately after the fold, before the mask-clip
                // below, because it grades the node's own just-assembled composite.
                //
                // The node's mask clips the assembled composite, never the children and never a
                // slot — the same placement the CPU reference uses and the reason a masked group
                // buffers at all. `groupBack` is free here (the fold above left the result in
                // `groupFront`), so the clip costs a dispatch and no allocation.
                //
                // **The mask-clip is skipped when this node has an effect**, and `over`'s opacity
                // below passes 1 rather than `node.opacity` in that case: `mix` below already consumed
                // both internally, the same crossfade `compositeEffectMix` does for the leaf, and
                // applying either again here would double it.
                var assembled = groupFront
                if let effect = node.effect {
                    guard let effects, let scratch = pool.acquire() else { return false }
                    guard effects.encode(effect, source: groupFront, into: scratch, encoder: encoder) else {
                        pool.release(scratch)
                        return false
                    }
                    mix(base: groupFront, graded: scratch,
                        coverage: maskTexture(for: node, of: request, cache: &masks),
                        opacity: node.opacity, into: groupBack, encoder: encoder,
                        width: width, height: height)
                    swap(&groupFront, &groupBack)
                    pool.release(scratch)
                    assembled = groupFront
                } else if let mask = maskTexture(for: node, of: request, cache: &masks) {
                    apply(mask: mask, to: groupFront, into: groupBack, encoder: encoder,
                          width: width, height: height)
                    assembled = groupBack
                }
                over(source: assembled, opacity: node.effect != nil ? 1 : node.opacity, mode: node.blendMode,
                     front: &front, back: &back, encoder: encoder, width: width, height: height)
            }
        }
        return true
    }

    /// One node's input slots, combined by its op, into `front` — the mirror of
    /// `CoreGraphicsCompositor.fold`, which carries the reasoning for why slot 0 goes straight into
    /// the accumulator and every later slot is composited on its own first.
    ///
    /// The GPU-side note is the pool: a `.mix` holds one extra texture pair live for the duration of
    /// each folded slot, on top of the node's own pair. That is still bounded by nesting rather than
    /// by slot count — the pair is released at the end of each iteration and the next slot reuses it —
    /// so a 2-input Mix costs four textures at its level, not two per slot.
    private func fold(_ op: CompositorOp, _ inputs: [[RenderNode]], of request: RenderRequest,
                      front: inout MTLTexture, back: inout MTLTexture,
                      encoder: MTLComputeCommandEncoder, pool: ScratchTexturePool,
                      masks: inout [ObjectIdentifier: MTLTexture],
                      width: Int, height: Int) -> Bool {
        for (slot, input) in inputs.enumerated() {
            guard case .mix(let mode) = op, slot > 0 else {
                // `paperInBackdrop: false` throughout `fold`, matching the CPU reference: `fold` is
                // reached only from the buffered branch, whose accumulator was just filled
                // transparent. There is no paper in here to take out again.
                guard encode(input, of: request, front: &front, back: &back, encoder: encoder,
                             pool: pool, masks: &masks, width: width, height: height,
                             paperInBackdrop: false) else { return false }
                continue
            }
            guard var slotFront = pool.acquire(), var slotBack = pool.acquire() else { return false }
            defer {
                pool.release(slotFront)
                pool.release(slotBack)
            }
            fill(slotFront, with: SIMD4<Float>(repeating: 0), encoder: encoder,
                 width: width, height: height)
            guard encode(input, of: request, front: &slotFront, back: &slotBack, encoder: encoder,
                         pool: pool, masks: &masks, width: width, height: height,
                         paperInBackdrop: false) else { return false }
            // Opacity 1: the node's own fade applies once to the finished fold, in `encode`.
            over(source: slotFront, opacity: 1, mode: mode, front: &front, back: &back,
                 encoder: encoder, width: width, height: height)
        }
        return true
    }

    /// This node's resolved mask as a single-channel texture, uploaded once per composite.
    private func maskTexture(for node: RenderNode, of request: RenderRequest,
                             cache: inout [ObjectIdentifier: MTLTexture]) -> MTLTexture? {
        guard !node.masks.isEmpty,
              let resolved = MaskResolver.coverage(for: node.masks, of: request) else { return nil }
        let key = ObjectIdentifier(resolved)
        if let hit = cache[key] { return hit }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: resolved.width, height: resolved.height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, resolved.width, resolved.height), mipmapLevel: 0,
                        withBytes: resolved.coverage, bytesPerRow: resolved.width)
        cache[key] = texture
        return texture
    }

    private func apply(mask: MTLTexture, to source: MTLTexture, into result: MTLTexture,
                       encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        encoder.setComputePipelineState(psMask)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(mask, index: 1)
        encoder.setTexture(result, index: 2)
        dispatch2D(encoder, psMask, width: width, height: height)
    }

    /// One `compositeEffectMix` dispatch: the graded backdrop mixed back over the ungraded one.
    ///
    /// Mirrors `CoreGraphicsCompositor.grade`'s second half, and the kernel carries the argument for
    /// why this is a mix rather than a composite. The caller does the swap, as it does after `over`.
    private func mix(base: MTLTexture, graded: MTLTexture, coverage: MTLTexture?, opacity: Double,
                     into result: MTLTexture, encoder: MTLComputeCommandEncoder,
                     width: Int, height: Int) {
        var opacity = Float(opacity)
        var hasCoverage: UInt32 = coverage == nil ? 0 : 1
        encoder.setComputePipelineState(psEffectMix)
        encoder.setTexture(base, index: 0)
        encoder.setTexture(graded, index: 1)
        // A declared texture argument has to be bound whether or not the kernel reads it; `base`
        // again is a texture already resident, and `hasCoverage` is what keeps it unread.
        encoder.setTexture(coverage ?? base, index: 2)
        encoder.setTexture(result, index: 3)
        encoder.setBytes(&opacity, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setBytes(&hasCoverage, length: MemoryLayout<UInt32>.stride, index: 1)
        dispatch2D(encoder, psEffectMix, width: width, height: height)
    }

    /// One `compositeOver` dispatch, and the swap that makes the result the new backdrop.
    private func over(source: MTLTexture, opacity: Double, mode: BlendMode,
                      front: inout MTLTexture, back: inout MTLTexture,
                      encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        var opacity = Float(opacity)
        var mode = mode.shaderCode
        encoder.setComputePipelineState(psOver)
        encoder.setTexture(front, index: 0)
        encoder.setTexture(source, index: 1)
        encoder.setTexture(back, index: 2)
        encoder.setBytes(&opacity, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setBytes(&mode, length: MemoryLayout<UInt32>.stride, index: 1)
        dispatch2D(encoder, psOver, width: width, height: height)
        swap(&front, &back)
    }

    /// **The canvas paper into `texture`, or a transparent clear when the request has none.**
    ///
    /// The paper covers the artwork rect, not the whole buffer — `RenderBackground.rect` carries the
    /// decision and the arithmetic; this only obeys it. A padded canvas therefore needs two writes,
    /// because the margin still has to start transparent and a pool texture arrives undefined. A
    /// canvas with no padding — the default, and every fixture — takes the single full-texture write
    /// it always did, so nothing about the common path has moved.
    ///
    /// **One function because it has two callers**, the mirror of `CoreGraphicsCompositor.fillBackground`:
    /// the top of the walk, and the ink re-walk, which lays the same paper back down under a graded
    /// ink. The premultiply below has to be the *same* expression at both sites or the two papers
    /// differ by a rounding step, which is precisely the kind of divergence the byte-for-byte parity
    /// gate exists to catch and the kind that is easiest to introduce by copying six lines.
    private func fillBackground(_ request: RenderRequest, into texture: MTLTexture,
                                encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        // Premultiplied, so the background's own alpha scales its colour.
        var background = SIMD4<Float>(repeating: 0)
        if let colour = request.background?.color {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            background = SIMD4<Float>(Float(r * a), Float(g * a), Float(b * a), Float(a))
        }
        // **The paper covers the artwork rect, not the whole buffer** — `RenderBackground.rect`
        // carries the decision and the arithmetic; this only obeys it. A padded canvas therefore
        // needs two writes, because the margin still has to start transparent and the texture
        // arrives undefined. A canvas with no padding — the default, and every fixture — takes the
        // single full-texture write it always did, so nothing about the common path has moved.
        let paper = request.background?.rect
        let whole = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        if let paper, paper != whole {
            fill(texture, with: SIMD4<Float>(repeating: 0), encoder: encoder, width: width, height: height)
            // **Edges, not an extent.** `Int(paper.width)` *truncated*, so a 64.8-px paper became a
            // 64-px fill and the column CoreGraphics antialiased was one this backend never wrote —
            // MEASURED delta 204 (`RenderBackground.rect` carries the arithmetic). `rect` is whole
            // pixels now, so these `.rounded()`s are the identity; they are here so that a rect which
            // somehow is not cannot put `gid + origin` outside the texture, which `compositeFill`
            // does not bounds-check and Metal leaves undefined rather than merely wrong.
            let x0 = max(0, min(width, Int(paper.minX.rounded())))
            let y0 = max(0, min(height, Int(paper.minY.rounded())))
            let x1 = max(x0, min(width, Int(paper.maxX.rounded())))
            let y1 = max(y0, min(height, Int(paper.maxY.rounded())))
            fill(texture, with: background, encoder: encoder,
                 width: x1 - x0, height: y1 - y0,
                 origin: SIMD2<UInt32>(UInt32(x0), UInt32(y0)))
        } else {
            fill(texture, with: background, encoder: encoder, width: width, height: height)
        }
    }

    /// Writes `colour` into a `width × height` rectangle of `texture` whose top-left is `origin`.
    ///
    /// The origin is a uniform rather than a dispatch offset because a compute grid always starts at
    /// zero. Every caller but the canvas background passes `.zero` and the whole texture's size, and
    /// for them this is the single full-texture write it has always been.
    private func fill(_ texture: MTLTexture, with colour: SIMD4<Float>,
                      encoder: MTLComputeCommandEncoder, width: Int, height: Int,
                      origin: SIMD2<UInt32> = SIMD2<UInt32>(0, 0)) {
        guard width > 0, height > 0 else { return }
        var colour = colour
        var origin = origin
        encoder.setComputePipelineState(psFill)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&colour, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setBytes(&origin, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
        dispatch2D(encoder, psFill, width: width, height: height)
    }

    private func dispatch2D(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState,
                            width: Int, height: Int) {
        let tw = min(16, pipeline.maxTotalThreadsPerThreadgroup)
        let th = min(16, max(1, pipeline.maxTotalThreadsPerThreadgroup / tw))
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
    }

    /// Reads the finished texture back as a `CGImage` in the app's standard format.
    ///
    /// The same round-trip `CanvasManager+Fill.imageFromRGBA` does for the flood fill's output, and
    /// deliberately the same constants — a byte-identical gate is decided as much by this conversion
    /// as by the arithmetic above it.
    ///
    /// **One canvas-sized copy, where this used to make two.** The previous version read into a
    /// `[UInt8]` and then handed `Data(bytes)` to the provider, and that second step copies the whole
    /// buffer again — 16.8 MB at 2048², 64 MB at 4000², per composite, and a repaint is three
    /// composites. Allocating the block once and letting the provider adopt it removes the copy
    /// without changing a byte of the result: the pixels `getBytes` writes are the pixels the
    /// `CGImage` is built on, at the same `bytesPerRow` and in the same layout.
    ///
    /// The image owns the allocation from here on — `releaseData` is what frees it, and it fires when
    /// the last reference to the provider goes. Returning nil before that hand-off happens is the one
    /// path that has to free it by hand.
    private func readBack(_ texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        let count = width * height * 4
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        texture.getBytes(bytes, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(dataInfo: nil, data: bytes, size: count,
                                            releaseData: { _, pointer, _ in
                                                UnsafeMutableRawPointer(mutating: pointer).deallocate()
                                            }) else {
            bytes.deallocate()
            return nil
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// One leaf's pixels as a texture, from `UploadCache` when the layer has not changed.
    ///
    /// **This doc comment used to say "No cache, deliberately", and the reasoning it gave was sound
    /// and is now spent.** The objection was that "the request hands out a freshly rendered `CGImage`
    /// per leaf per frame, so there is no stable identity to key on" — true of the *image*, and the
    /// first cache keyed on exactly that and was measured at a zero hit rate. It was never true of
    /// the layer. `LayerContentVersion` keys on the cel's identity and version instead, the request
    /// has carried one per leaf since phase 6, and `LayerRenderSource`'s note names this as the key
    /// that would work.
    ///
    /// The same comment recorded what the miss costs: "the upload [is] the dominant cost of a GPU
    /// composite (six canvas-sized layers is ~100 MB moved per frame)". Two things collect that,
    /// and the first is larger than the frame-to-frame case people reach for:
    ///
    /// - **One repaint is three composites.** `startSandwichRebuild` composites `full`, `below` and
    ///   `above` over one shared `sources` array, so ~200 of those ~300 MB were the same six layers
    ///   uploaded a second and a third time inside a single rebuild. That is a hit by construction,
    ///   not by luck — nothing about the artist's document can make those three disagree.
    /// - **Between repaints, one layer moves.** A rebuild follows a lift, a layer switch or a slider
    ///   tick, and every layer the artist did not touch keys the same as last time.
    ///
    /// The sandwich argument in the old comment still stands and is untouched by this: nothing here
    /// puts the compositor on the drawing path, because a dab still schedules no rebuild at all.
    ///
    /// A `nil` content version falls through to an uncached upload rather than failing. That pairing
    /// is documented as impossible in `leafSnapshots` (a leaf with pixels always carries a version),
    /// and treating it as "upload it, don't remember it" keeps a future change to that invariant a
    /// performance question instead of a black frame.
    ///
    /// Draws through a context of exactly the app's byte layout rather than trusting whatever backing
    /// store the `CGImage` happens to have, which for something out of `UIGraphicsImageRenderer` may
    /// be a different order or alignment.
    private func upload(_ source: LayerRenderSource, of request: RenderRequest,
                        at layerIndex: Int) -> MTLTexture? {
        guard request.contentVersions.indices.contains(layerIndex),
              let version = request.contentVersions[layerIndex] else {
            return Self.upload(source.image, device: device)
        }
        let key = UploadCache.Key(content: version, quality: request.quality,
                                  width: source.image.width, height: source.image.height)
        if let hit = uploads.texture(for: key) { return hit }
        guard let texture = Self.upload(source.image, device: device) else { return nil }
        uploads.store(texture, for: key)
        return texture
    }

    /// The upload itself, with no cache in front of it — what the nil-version path above wants, and
    /// what keeps the caching decision in one function rather than spread across two.
    ///
    /// The texture is `.shaderRead` only and no kernel is ever passed it as an output, which is what
    /// makes holding one across composites safe to do: a cached entry is immutable for its whole
    /// life, so two composites reading the same layer read the same bytes and neither can disturb
    /// the other.
    private static func upload(_ image: CGImage, device: MTLDevice) -> MTLTexture? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: width * 4)
        return texture
    }
}
