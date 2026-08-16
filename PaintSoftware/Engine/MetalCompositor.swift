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

    /// Composites `request` on the GPU, or returns nil if it cannot. `Compositor.composite` treats
    /// nil as "use the CPU reference", so every nil here is a slower frame rather than a missing one.
    ///
    /// Returns nil when there is no GPU, no shader library, a degenerate canvas size, or an
    /// allocation this device would not make. **It no longer declines a group that needs its own
    /// buffer**, which is phase 5's change to this file: buffers were only reachable through a faded
    /// group in phase 4, and blend modes are §5.1's entire argument for the GPU — a document that
    /// blends falling back to the CPU would mean the GPU never runs the case it exists for. See
    /// `CompositorMetalEngine.encode`.
    static func composite(_ request: RenderRequest) -> CGImage? {
        CompositorMetalEngine.shared?.composite(request)
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
/// eviction decision to make at all. The only lifetime question left is the canvas size, and
/// `CompositorMetalEngine` answers it by discarding the whole pool when that changes — the same rule
/// `EffectPipelines.intermediates` already uses for its ping-pong pair, and for the same reason: a
/// canvas has one size at a time.
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
/// something four times different at the two sizes and would be right at neither. The budget below
/// holds eleven layers at 2048² and three at 4000², chosen so an ordinary document caches whole and
/// a large one degrades toward today's behaviour rather than toward an eviction of the app.
///
/// **The degradation is not graceful and that is worth stating plainly rather than discovering.** A
/// composite walks its leaves in a fixed bottom-to-top order, so a document whose leaves do not all
/// fit is the textbook LRU thrash: every leaf is evicted exactly before it is next wanted, and the
/// hit rate is 0 rather than "reduced". That is *no worse* than the uncached path this replaces —
/// the same uploads happen, plus a dictionary probe — but it is a cliff and not a slope, and
/// anybody raising the budget should know they are moving a cliff.
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

    /// 192 MB. See the type's note for how this converts into layers at each canvas size, and for
    /// what going one layer over it costs.
    private static let budgetBytes = 192 * 1024 * 1024

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
        guard residentBytes > Self.budgetBytes else { return }
        for key in entries.sorted(by: { $0.value.lastUsed < $1.value.lastUsed }).map(\.key) {
            guard residentBytes > Self.budgetBytes else { return }
            if let removed = entries.removeValue(forKey: key) { residentBytes -= removed.bytes }
        }
    }

    /// Drops everything. The canvas resizing is what calls this — every key is stale at that point
    /// (the dimensions are in it), so the entries could only sit there holding memory until the LRU
    /// noticed, and the LRU would notice by evicting *live* entries first.
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
    private var pool: ScratchTexturePool?
    private let uploads = UploadCache()

    func composite(_ request: RenderRequest) -> CGImage? {
        let width = Int(request.canvasSize.width.rounded())
        let height = Int(request.canvasSize.height.rounded())
        guard width > 0, height > 0 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        // Ping-pong rather than one read_write accumulator: `access::read_write` on `rgba8Unorm`
        // needs the GPU family's read-write texture support, and two scratch textures cost 33.6 MB at
        // 2048² against a correctness risk on older hardware.
        //
        // Kept between composites now, and discarded outright when the canvas size changes rather
        // than kept per size: a canvas has one size at a time, so a second pool could only ever be
        // dead weight — `EffectPipelines.intermediates` makes the same call for the same reason. The
        // upload cache goes with it, because its keys carry the dimensions and so every entry in it
        // is unreachable from this moment on.
        let pool: ScratchTexturePool
        if let existing = self.pool, existing.width == width, existing.height == height {
            pool = existing
        } else {
            pool = ScratchTexturePool(device: device, width: width, height: height)
            self.pool = pool
            uploads.removeAll()
        }
        pool.beginComposite()
        defer {
            lastScratchAllocated = pool.allocatedThisComposite
            uploads.trimToBudget()
        }

        guard var front = pool.acquire(), var back = pool.acquire(),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else { return nil }
        // The accumulator pair goes back on every exit, including the failure ones — otherwise a
        // frame that declines (a missing effect pipeline, a command-buffer error) would leave two
        // canvas-sized textures stranded and the next frame would allocate two more. `front` and
        // `back` are swapped throughout the walk; which is which by now does not matter, since the
        // pool takes them as interchangeable.
        defer {
            pool.release(front)
            pool.release(back)
        }

        // Premultiplied, so the background's own alpha scales its colour — and a nil background is a
        // transparent clear rather than a skipped step, since a scratch texture arrives undefined.
        var background = SIMD4<Float>(repeating: 0)
        if let colour = request.background?.color {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            background = SIMD4<Float>(Float(r * a), Float(g * a), Float(b * a), Float(a))
        }
        fill(front, with: background, encoder: encoder, width: width, height: height)

        // One upload per distinct mask for this composite, not per masked node — the resolution is
        // already shared (`MaskResolver`), and re-uploading the same 4.2 MB once per layer clipped
        // to it would spend on the GPU exactly what that sharing saves on the CPU.
        var maskTextures: [ObjectIdentifier: MTLTexture] = [:]
        let encoded = encode(request.tree, of: request, front: &front, back: &back,
                             encoder: encoder, pool: pool, masks: &maskTextures,
                             width: width, height: height)
        encoder.endEncoding()
        guard encoded else { return nil }

        commands.commit()
        commands.waitUntilCompleted()
        guard commands.error == nil else { return nil }
        return readBack(front, width: width, height: height)
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
                        width: Int, height: Int) -> Bool {
        for node in nodes {
            switch node.content {
            case .leaf(let layerIndex):
                guard node.isVisible else { continue }
                // §4.4's stack layer, reached before `sources` for the reason the CPU reference
                // gives: an effect layer has no pixels to find, only a grade over `front` — which
                // *is* "the backdrop accumulated so far in this container", since a buffered group
                // handed this walk its own accumulator.
                if let effect = node.effect {
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
                        guard encode(input, of: request, front: &front, back: &back,
                                     encoder: encoder, pool: pool, masks: &masks,
                                     width: width, height: height) else { return false }
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
                guard encode(input, of: request, front: &front, back: &back, encoder: encoder,
                             pool: pool, masks: &masks, width: width, height: height) else { return false }
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
                         pool: pool, masks: &masks, width: width, height: height) else { return false }
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

    private func fill(_ texture: MTLTexture, with colour: SIMD4<Float>,
                      encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        var colour = colour
        encoder.setComputePipelineState(psFill)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&colour, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
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
    /// is documented as impossible in `renderSources` (a leaf with pixels always carries a version),
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
