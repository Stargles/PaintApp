import UIKit

// MARK: - Resolving a mask (§6.2, §6.3)
//
// A mask is a list of sources; this is where that becomes pixels. Composite each source's subtree,
// take its alpha, `max` across them for the union, then the §6.3 threshold test — and hand the
// result to whichever backend is drawing.
//
// **Resolution always runs through the CoreGraphics reference, on both backends, and that is what
// makes byte-for-byte agreement reachable rather than lucky.** The threshold is a step function with
// a narrow ramp across it, so a source alpha that differed between the backends by the one channel
// step §11 measured for the blend modes would land on opposite sides of it and produce a mask that
// differs by far more than one step. One resolution, shared, removes the question: the GPU path
// differs from the CPU path only in the compositing that phase 2 and phase 5 already measured.
//
// The multiply that *applies* a mask does run in both places, and it is written twice on purpose —
// once as a kernel, once as the same float expression in the same order on the CPU (see
// `apply(_:to:)`). Mimicking the shader's arithmetic term for term is what keeps `round-to-nearest-
// even` landing on the same byte, the same trick `CoreGraphicsCompositor.drawHandRolled` uses.

/// One resolved mask: a coverage byte per pixel, 0 = hidden, 255 = shown.
///
/// A reference type, and `Equatable` by identity rather than by content — a canvas-sized array
/// compared on every SwiftUI pass would be its own performance bug, and identity is the right answer
/// anyway because a resolution that comes back from the cache *is* the same mask.
final class ResolvedMask {

    let width: Int
    let height: Int
    /// `width * height` bytes, row-major, top-left origin — the same layout as any one channel of
    /// the app's premultiplied RGBA.
    let coverage: [UInt8]

    fileprivate init(width: Int, height: Int, coverage: [UInt8]) {
        self.width = width
        self.height = height
        self.coverage = coverage
    }

    /// The mask as an image whose **alpha channel** is the coverage — what `CALayer.mask` wants.
    ///
    /// §6.4's live feedback is phase 6b's work, and this is the seam it hangs off: the mask is static
    /// for a stroke's duration, so the stroke view carries this as its layer mask and Core Animation
    /// applies the same alpha multiply the compositor does, in hardware, exactly. Note the mask goes
    /// on `host.strokeView` — `LayerHostView.layer.mask` is taken, by phase 5b's blanking.
    ///
    /// White premultiplied by coverage, so it reads correctly whether a consumer looks at alpha or at
    /// luminance. **A method rather than a cached `lazy var`**: one `ResolvedMask` is shared by every
    /// layer using it and read from the sandwich's off-main rebuild, so a stored property filled in
    /// on first access is a data race waiting for the phase that adds the second caller. Building it
    /// costs one canvas-sized pass, paid once per stroke; a consumer that wants it more often than
    /// that should hold it itself.
    func makeMaskImage() -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let value = coverage[pixel]
            for channel in 0..<4 { bytes[pixel * 4 + channel] = value }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

extension ResolvedMask: Equatable {
    static func == (lhs: ResolvedMask, rhs: ResolvedMask) -> Bool { lhs === rhs }
}

enum MaskResolver {

    /// The coverage `masks` resolve to together, or nil when they clip nothing.
    ///
    /// **Cached once per distinct mask and shared by every layer using it** (§6.1) — the key is the
    /// masks themselves plus the content versions of the layers they read, so two layers clipped the
    /// same way hit the same entry and cost one resolution between them. That is the whole reason
    /// non-destructive masking is *cheaper* than baking: the coverage is shared, while baked pixels
    /// would be per layer and would have to be retained by undo on top.
    ///
    /// More than one mask is an intersection, applied as a product of coverages — see
    /// `RenderNode.masks` for when a node carries two.
    static func coverage(for masks: [AlphaMask], of request: RenderRequest) -> ResolvedMask? {
        guard !masks.isEmpty else { return nil }
        let width = Int(request.canvasSize.width.rounded())
        let height = Int(request.canvasSize.height.rounded())
        guard width > 0, height > 0 else { return nil }

        let key = CacheKey(masks: masks, width: width, height: height, quality: request.quality,
                           versions: contentVersions(readBy: masks, of: request),
                           nodeEffects: nodeEffects(readBy: masks, of: request),
                           tuningGeneration: AlphaMask.tuningGeneration)
        if let hit = cache.value(for: key) { return hit }
        guard let resolved = resolveUncached(masks, of: request, width: width, height: height) else { return nil }
        cache.store(resolved, for: key)
        return resolved
    }

    /// Multiplies `image`'s alpha by `mask` — the mask applied, and the only thing "applying a mask"
    /// ever means here (§6.1: never baked, always this, at draw time).
    ///
    /// **The arithmetic mirrors `compositeMask` in `Composite.metal` term for term**, including the
    /// order of the operations and `.toNearestOrEven`, which is the rule Metal's float→unorm8
    /// conversion uses. Written that way rather than as the equivalent integer expression because the
    /// two backends have to agree to the byte and IEEE single precision is what they can both promise
    /// — the same reasoning `drawHandRolled` gives for the blend modes it computes by hand.
    ///
    /// Premultiplied input, so all four channels scale: a premultiplied pixel at half coverage is
    /// the same colour at half the coverage, whereas scaling alpha alone would brighten it.
    static func apply(_ mask: ResolvedMask, to image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width == mask.width, height == mask.height,
              var bytes = CoreGraphicsCompositor.premultipliedBytes(image, width: width, height: height)
        else { return nil }

        for pixel in 0..<(width * height) {
            let m = Float(mask.coverage[pixel]) / 255
            guard m < 1 else { continue }   // full coverage is the identity, exactly
            guard m > 0 else {
                // …and no coverage is transparent, exactly. Worth the branch rather than four
                // multiplies by zero: outside the mask is most of the canvas in most documents.
                for channel in 0..<4 { bytes[pixel * 4 + channel] = 0 }
                continue
            }
            for channel in 0..<4 {
                let offset = pixel * 4 + channel
                let value = Float(bytes[offset]) / 255
                bytes[offset] = UInt8((min(max(value * m, 0), 1) * 255).rounded(.toNearestOrEven))
            }
        }
        return CoreGraphicsCompositor.makeImage(fromPremultiplied: bytes, width: width, height: height)
    }

    /// Drops every resolved mask. For tests that need to measure an uncached resolution, and for
    /// memory pressure — nothing here is state, so throwing it away only costs time.
    ///
    /// **The pressure half of that sentence is now true.** It was not until 2026-08-20: every
    /// call site in the repo was a test, so a warning reached the Metal caches and the flatten memo
    /// and stepped around this one entirely while the comment said otherwise. `MaskCache.init`
    /// subscribes now — to backgrounding as well as to the warning, which is the event that actually
    /// arrives — see the note there, and `PixelOps.RasterizeCache.init`, which is the same defect
    /// found and fixed one file earlier.
    static func clearCache() { cache.removeAll() }

    /// How many resolved masks this is holding, for the tests. Nothing in the render path reads it —
    /// `PixelOps.rasterizeCacheBytes` and `CompositorMetalEngine.uploadCacheEntryCount` are the same
    /// instrument on the caches either side of this one.
    static var cacheEntryCount: Int { cache.entryCount }

    // MARK: - Resolution

    private static func resolveUncached(_ masks: [AlphaMask], of request: RenderRequest,
                                        width: Int, height: Int) -> ResolvedMask? {
        var product: [UInt8]?
        for mask in masks {
            guard let one = resolve(mask, of: request, width: width, height: height) else { continue }
            guard var accumulated = product else {
                product = one
                continue
            }
            // Two masks on one node intersect, and a product of coverages is what that means.
            for index in accumulated.indices {
                let combined = Float(accumulated[index]) / 255 * (Float(one[index]) / 255)
                accumulated[index] = UInt8((combined * 255).rounded(.toNearestOrEven))
            }
            product = accumulated
        }
        guard let product else { return nil }
        return ResolvedMask(width: width, height: height, coverage: product)
    }

    /// One mask: the union of its sources' alpha, put through §6.3's threshold.
    private static func resolve(_ mask: AlphaMask, of request: RenderRequest,
                                width: Int, height: Int) -> [UInt8]? {
        var union = [UInt8](repeating: 0, count: width * height)
        var resolvedAnySource = false

        for source in mask.sources {
            // A source naming something that is not in the document contributes no alpha rather than
            // failing the mask — §6.6's "a deleted source is dropped", seen from the render side.
            guard let stack = request.maskStacks[source] else { continue }
            let sourceRequest = RenderRequest(tree: stack, sources: request.sources,
                                              contentVersions: request.contentVersions,
                                              maskStacks: request.maskStacks,
                                              frame: request.frame, canvasSize: request.canvasSize,
                                              background: nil, quality: request.quality)
            // Always the CPU reference, whichever backend asked — see this file's header.
            guard let composite = CoreGraphicsCompositor.composite(sourceRequest),
                  let bytes = CoreGraphicsCompositor.premultipliedBytes(composite, width: width, height: height)
            else { continue }
            resolvedAnySource = true
            for pixel in 0..<(width * height) {
                union[pixel] = max(union[pixel], bytes[pixel * 4 + 3])
            }
        }
        // An enabled mask whose every source failed to resolve is not a mask that hides everything;
        // it is no mask (§6.6). Inverting nothing is still nothing, which is why this returns before
        // the threshold rather than after it.
        guard resolvedAnySource else { return nil }

        // The threshold is a function of one alpha byte, so 256 answers cover the canvas. Worth the
        // table: this runs over 4.2M pixels at 2048².
        let table: [UInt8] = (0...255).map { alpha in
            UInt8((min(max(mask.coverage(forSourceAlpha: Float(alpha) / 255), 0), 1) * 255).rounded(.toNearestOrEven))
        }
        for pixel in union.indices { union[pixel] = table[Int(union[pixel])] }
        return union
    }

    /// The content versions of exactly the layers these masks read, so an edit somewhere else in the
    /// document does not invalidate a mask that cannot have changed.
    private static func contentVersions(readBy masks: [AlphaMask],
                                        of request: RenderRequest) -> [LayerContentVersion?] {
        var indices: [Int] = []
        for mask in masks {
            for source in mask.sources {
                guard let stack = request.maskStacks[source] else { continue }
                indices.append(contentsOf: stack.leafLayerIndices)
            }
        }
        // Sorted and de-duplicated so two masks naming the same sources in different orders produce
        // the same key and therefore share the entry.
        return Set(indices).sorted().map { index in
            request.contentVersions.indices.contains(index) ? request.contentVersions[index] : nil
        }
    }

    /// **The grades carried by the *node* forms in the stacks these masks read** — the other half of
    /// what "the model this coverage was resolved from" means, and until 2026-08-29 it was missing.
    ///
    /// `contentVersions` above is indexed by *layer*, gathered from `stack.leafLayerIndices`, so it
    /// covers a grading **layer** inside a mask source's subtree (that is `LayerContentVersion.effect`)
    /// and cannot see a grading **folder** at all, because a folder is not a leaf. But a mask source
    /// naming a folder resolves that folder's whole node through `CoreGraphicsCompositor.composite`,
    /// which applies `RenderNode.effect` — so a grade that reshapes alpha (`reshapesCoverage`: outline,
    /// blur, bloom, Sobel, sharpen) genuinely changes the coverage this cache holds, and nothing in the
    /// key moved when it changed. This closes that.
    ///
    /// **It was a real defect before a keyframe could animate one, and §2.21 is what made it urgent
    /// rather than what caused it.** Editing a folder's grade by hand already served stale coverage
    /// until something else evicted the entry; a folder effect *track* makes it fire on every frame of
    /// playback, with no edit at all, which is the difference between a bug an artist hits once and one
    /// they cannot look away from.
    ///
    /// **Node grades and not the whole `[RenderNode]`.** Putting the stacks' trees in the key would
    /// also invalidate on every structural change to them, which is strictly more invalidation for a
    /// hazard nothing has demonstrated; the grade is the field that is both frame-varying and invisible
    /// to `versions`. A nil is appended for an ungraded node so the *count* of node forms is pinned too,
    /// which is what makes a grade being removed from one node of several a different key.
    ///
    /// Sources are de-duplicated and ordered by id for `contentVersions`' reason: two masks naming the
    /// same sources in different orders must produce one key and share the entry.
    private static func nodeEffects(readBy masks: [AlphaMask], of request: RenderRequest) -> [Effect?] {
        var sources: Set<MaskSource> = []
        for mask in masks { sources.formUnion(mask.sources) }
        guard !sources.isEmpty else { return [] }

        var effects: [Effect?] = []
        for source in sources.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let stack = request.maskStacks[source] else { continue }
            collectNodeEffects(in: stack, into: &effects)
        }
        return effects
    }

    /// Depth first, node before its inputs — the same walk shape `collectMaskSources` makes, so the
    /// order is the tree's and therefore deterministic where a dictionary's would not be.
    private static func collectNodeEffects(in nodes: [RenderNode], into effects: inout [Effect?]) {
        for node in nodes {
            guard case .node(_, let inputs) = node.content else { continue }
            effects.append(node.effect)
            for input in inputs { collectNodeEffects(in: input, into: &effects) }
        }
    }

    // MARK: - The cache

    /// **Keyed on the model, never on the rendered result.** §9.1's original `contentVersion` keyed
    /// on the `CGImage` that `PixelOps.rasterize` mints fresh every call and was deleted in phase 2
    /// after being measured at a zero hit rate; `LayerContentVersion` is the key that post-mortem
    /// prescribed, carried on the request so this cache and §5.2's sandwich share one answer.
    ///
    /// The masks themselves are in the key rather than the masked node's id, which is the difference
    /// between "cached per distinct mask" and "cached per masked layer" — ten layers clipped to the
    /// same shape resolve it once.
    ///
    /// **The gap this comment used to describe is closed** — a *folder's* grade is in the key now, as
    /// `nodeEffects`, and that method carries the argument. It was documented here as a KNOWN GAP from
    /// phase 9b until 2026-08-29 and prescribed its own fix ("putting the stacks' node grades in this
    /// key rather than extending a per-layer version"), which is exactly what landed when KEYFRAMES.md
    /// §2.21 gave a folder's grade a keyframe track and turned an edit-time staleness into a per-frame
    /// one. The live canvas was never affected either way: `CanvasView.SandwichKey` compares whole
    /// `[RenderNode]` trees and so has always seen both grade forms.
    private struct CacheKey: Hashable {
        let masks: [AlphaMask]
        let width: Int
        let height: Int
        let quality: RenderQuality
        let versions: [LayerContentVersion?]
        /// The grades on the node forms inside the mask sources' stacks — see `nodeEffects(readBy:of:)`.
        let nodeEffects: [Effect?]
        // MASK-TUNE: `AlphaMask.threshold`/`.antialiasHalfWidth` are statics, not stored properties,
        // so `masks` above cannot see a change to either — without this field the cache would keep
        // serving a `ResolvedMask` computed under the old value. See `AlphaMask.tuningGeneration`'s
        // doc comment. Costs nothing in a document nobody has tuned, where the generation stays 0.
        let tuningGeneration: Int

        /// **Hand-written, and only to skip `nodeEffects`** — `LayerContentVersion.hash(into:)`'s trick
        /// for `LayerContentVersion.effect`, needed here for the same reason and stated there at
        /// length: `Effect` is `Equatable` but not `Hashable`, and conforming it plus its thirteen
        /// payload structs would buy nothing but bucket spread. Hashing may collide; **equality** is
        /// what decides a cache hit, and `==` is synthesized over every field including this one.
        func hash(into hasher: inout Hasher) {
            hasher.combine(masks)
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(quality)
            hasher.combine(versions)
            hasher.combine(nodeEffects.count)
            hasher.combine(tuningGeneration)
        }
    }

    /// How many resolved masks this cache holds. **A named constant because something outside this
    /// file has to be able to ask** — `MemoryBudgetLogicTests` asserts the app's five memory budgets
    /// against one another (PERFORMANCE.md item 13), and a budget stated only as a literal buried in
    /// an initialiser cannot appear in that table. The same reason `PixelOps.sharedRasterizeEntryLimit`
    /// is public; read-only, and the cache below is still the only user.
    ///
    /// Small on purpose: a coverage buffer is 1 byte per pixel — 2.1 MB at the owner's 2048x1024,
    /// 4.2 MB at 2048² and 16 MB at 4000² — and a document with more than a handful of distinct masks
    /// in one frame is not the case worth holding memory for.
    ///
    /// **Entries and not bytes, unlike the two large caches, and that is a deliberate difference
    /// rather than an oversight.** `PixelOps.rasterizeCache` and `CompositorMetalEngine`'s upload
    /// cache both carry byte budgets because their entries are canvas-sized RGBA — 64 MiB apiece at
    /// 4096², where counting entries stops being a bound. A coverage buffer is a quarter of that per
    /// pixel and the count is eight, so at the owner's canvas this whole cache is ~16 MiB against
    /// 192 MiB apiece for those two. At 4096² it would be ~128 MiB, which is the figure PERFORMANCE.md
    /// item 6 flagged as 4K arithmetic; if a future session works at that size routinely, a byte
    /// budget borrowed from `CompositorBudget` the way `PixelOps` borrows one is the shape of the fix.
    static let cacheEntryLimit = 8

    /// Evicts in insertion order, as `PixelOps.rasterizeCache` does and for the same reason.
    private static let cache = MaskCache(limit: cacheEntryLimit)

    private final class MaskCache {
        private let limit: Int
        private var entries: [CacheKey: ResolvedMask] = [:]
        private var order: [CacheKey] = []
        private let lock = NSLock()

        init(limit: Int) {
            self.limit = limit
            // **Nothing dropped these before**, exactly as nothing dropped `PixelOps`'s rasterize
            // memo before that one was wired: `clearCache`'s doc comment said "and for a memory
            // warning" while every caller in the tree was a test. Two instances of one defect from
            // one cause, so this block is that file's verbatim, down to where it lives — registered
            // in the cache's own initialiser rather than in a view or the app delegate, because this
            // is what knows it is a cache. The observer's lifetime is the cache's, and both are the
            // process's, so there is nothing to remove and no ordering to get wrong.
            //
            // Correctness-neutral by construction: a `ResolvedMask` is derived from the masks and the
            // content versions in the key, so dropping one costs the resolution again and nothing
            // else. The bytes are modest at the canvas the owner works at — 8 entries × 1 byte per
            // pixel is ≤16 MiB at 2048×1024 (INFERRED) — and closing the lie is the point rather than
            // the recovery.
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.removeAll()
            }
            // **The event that actually arrives** — `PixelOps.RasterizeCache.init` and
            // `CompositorMetalEngine.init` both carry this line for the reason PERFORMANCE.md item 12
            // records: the memory warning never fires on the owner's device, so a cache that drops
            // only on one sits at its high-water mark against a document nobody is looking at for as
            // long as the app is backgrounded. Same `removeAll()`, same correctness-neutral
            // guarantee, paid back as one cold resolve per mask when the artist comes back.
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.removeAll()
            }
        }

        func value(for key: CacheKey) -> ResolvedMask? {
            lock.lock(); defer { lock.unlock() }
            return entries[key]
        }

        func store(_ mask: ResolvedMask, for key: CacheKey) {
            lock.lock(); defer { lock.unlock() }
            if entries.updateValue(mask, forKey: key) == nil { order.append(key) }
            while order.count > limit {
                entries.removeValue(forKey: order.removeFirst())
            }
        }

        func removeAll() {
            lock.lock(); defer { lock.unlock() }
            entries.removeAll(); order.removeAll()
        }

        var entryCount: Int {
            lock.lock(); defer { lock.unlock() }
            return entries.count
        }
    }
}
