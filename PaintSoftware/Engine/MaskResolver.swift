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

        let sourceStacks = stacksRead(by: masks, of: request)
        let key = CacheKey(masks: masks, width: width, height: height, window: request.window,
                           quality: request.quality,
                           versions: contentVersions(in: sourceStacks, of: request),
                           sourceStacks: sourceStacks)
        if let hit = cache.value(for: key) { return hit }
        guard let resolved = resolveUncached(masks, of: request, width: width, height: height) else { return nil }
        cache.store(resolved, for: key)
        return resolved
    }

    /// **`image`'s alpha, as a coverage** — the amount an `.ink` source resolves to, for a caller that
    /// holds the pixels and no document to resolve them from: `CanvasManager.mergeContribution`
    /// baking a vector layer's grade through its own ink (TODO (92)). No threshold, for
    /// `MaskSource.ink`'s reason; the bytes are read through the same conversion both compositors
    /// use, so the coverage is the alpha the walk would have composited.
    static func coverage(fromAlphaOf image: CGImage) -> ResolvedMask? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let bytes = CoreGraphicsCompositor.premultipliedBytes(image, width: width, height: height)
        else { return nil }
        var coverage = [UInt8](repeating: 0, count: width * height)
        for pixel in coverage.indices { coverage[pixel] = bytes[pixel * 4 + 3] }
        return ResolvedMask(width: width, height: height, coverage: coverage)
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

    /// Coverage bytes this is holding — the byte budget's counterpart to `cacheEntryCount`, and what
    /// `MemoryBudgetLogicTests` reads to assert the bound is bytes rather than entries. Nothing in
    /// the render path reads it; `PixelOps.rasterizeCacheBytes` is the same instrument next door.
    static var cacheBytes: Int { cache.bytesResident }

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

    /// One mask: the union of its clip sources' alpha, put through §6.3's threshold — and, unioned
    /// with that, its amount sources' alpha as it is.
    ///
    /// **Two unions rather than one, since TODO (92).** A `.layer` or `.folder` source is a shape a
    /// clip is cut from, and the cut is the threshold table below; an `.ink` source *is* the coverage
    /// (`MaskSource.isAmount`), so it joins after the table, inverted the plain way if the mask asks.
    /// A mask of clip sources alone runs exactly the path it always ran, byte for byte; a mask of one
    /// ink source — the only kind the render tree mints — is that source's alpha, untouched.
    private static func resolve(_ mask: AlphaMask, of request: RenderRequest,
                                width: Int, height: Int) -> [UInt8]? {
        var union = [UInt8](repeating: 0, count: width * height)
        var resolvedAnyClip = false
        var amounts: [UInt8]?
        let colourTable = mask.colours.map(ColourKeyTableEntry.init)
        // Bounded and local to this resolution. A flat patch converts once rather than per pixel;
        // photographic sources cannot grow an unbudgeted dictionary over the whole canvas.
        var colourMemo: [UInt32: UInt8] = [:]
        let memoLimit = 4096

        for source in mask.sources {
            // A source naming something that is not in the document contributes no alpha rather than
            // failing the mask — §6.6's "a deleted source is dropped", seen from the render side.
            guard let stack = request.maskStacks[source] else { continue }
            // `window` carries: under RENDER.md §3.8 a mask resolves over the strip's own band, out
            // of the same windowed sources the walk composites from, and a graded node inside the
            // stack has to know where that band sits for the same reason the outer walk does.
            let sourceRequest = RenderRequest(tree: stack, sources: request.sources,
                                              contentVersions: request.contentVersions,
                                              maskStacks: request.maskStacks,
                                              frame: request.frame, canvasSize: request.canvasSize,
                                              background: nil, quality: request.quality,
                                              window: request.window)
            // Always the CPU reference, whichever backend asked — see this file's header.
            guard let composite = CoreGraphicsCompositor.composite(sourceRequest),
                  let bytes = CoreGraphicsCompositor.premultipliedBytes(composite, width: width, height: height)
            else { continue }
            if source.isAmount {
                var amount = amounts ?? [UInt8](repeating: 0, count: width * height)
                for pixel in 0..<(width * height) {
                    amount[pixel] = max(amount[pixel], bytes[pixel * 4 + 3])
                }
                amounts = amount
                continue
            }
            resolvedAnyClip = true
            for pixel in 0..<(width * height) {
                let offset = pixel * 4
                let alpha = bytes[offset + 3]
                if colourTable.isEmpty {
                    union[pixel] = max(union[pixel], alpha)
                } else if alpha > 0 {
                    let packed = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                        | UInt32(bytes[offset + 2]) << 16 | UInt32(alpha) << 24
                    let coverage: UInt8
                    if let hit = colourMemo[packed] {
                        coverage = hit
                    } else {
                        let lab = ColorMath.rgbToOklab(r: Double(bytes[offset]) / Double(alpha),
                                                       g: Double(bytes[offset + 1]) / Double(alpha),
                                                       b: Double(bytes[offset + 2]) / Double(alpha))
                        let colour = SIMD3(Float(lab.L), Float(lab.a), Float(lab.b))
                        let membership = colourTable.reduce(Float(0)) { max($0, $1.weight(for: colour)) }
                        coverage = UInt8((membership * Float(alpha)).rounded(.toNearestOrEven))
                        if colourMemo.count < memoLimit { colourMemo[packed] = coverage }
                    }
                    union[pixel] = max(union[pixel], coverage)
                }
            }
        }
        // An enabled mask whose every source failed to resolve is not a mask that hides everything;
        // it is no mask (§6.6). Inverting nothing is still nothing, which is why this returns before
        // the threshold rather than after it.
        guard resolvedAnyClip || amounts != nil else { return nil }

        if resolvedAnyClip {
            // The threshold is a function of one alpha byte, so 256 answers cover the canvas. Worth
            // the table: this runs over 4.2M pixels at 2048².
            let table: [UInt8] = (0...255).map { alpha in
                if !colourTable.isEmpty { return mask.invert ? 255 - UInt8(alpha) : UInt8(alpha) }
                return UInt8((min(max(mask.coverage(forSourceAlpha: Float(alpha) / 255), 0), 1) * 255).rounded(.toNearestOrEven))
            }
            for pixel in union.indices { union[pixel] = table[Int(union[pixel])] }
        }
        if let amounts {
            for pixel in union.indices {
                union[pixel] = max(union[pixel], mask.invert ? 255 - amounts[pixel] : amounts[pixel])
            }
        }
        return union
    }

    /// Every source dependency, including masks on sources and on their descendants. A source's
    /// mask can read a leaf outside its subtree; stopping at the first subtree misses that leaf's edits.
    private static func stacksRead(by masks: [AlphaMask], of request: RenderRequest) -> [[RenderNode]] {
        var pending = masks.flatMap(\.sources)
        var visited: Set<MaskSource> = []
        var stacks: [MaskSource: [RenderNode]] = [:]
        func dependencies(in nodes: [RenderNode]) -> [MaskSource] {
            nodes.flatMap { node -> [MaskSource] in
                let own = node.masks.flatMap(\.sources)
                if case .node(_, let inputs) = node.content { return own + inputs.flatMap(dependencies) }
                return own
            }
        }
        while let source = pending.popLast() {
            guard visited.insert(source).inserted, let stack = request.maskStacks[source] else { continue }
            stacks[source] = stack
            pending.append(contentsOf: dependencies(in: stack))
        }
        return stacks.keys.sorted {
            if $0.id != $1.id { return $0.id.uuidString < $1.id.uuidString }
            return String(describing: $0) < String(describing: $1)
        }.compactMap { stacks[$0] }
    }

    private static func contentVersions(in stacks: [[RenderNode]],
                                        of request: RenderRequest) -> [LayerContentVersion?] {
        Set(stacks.flatMap(\.leafLayerIndices)).sorted().map { index in
            request.contentVersions.indices.contains(index) ? request.contentVersions[index] : nil
        }
    }

    // MARK: - The cache

    /// Masks and the complete source dependency graph, by model value. The trees include folder
    /// opacity, masks and grades as resolved for this frame; leaf versions include their actual ink.
    private struct CacheKey: Hashable {
        let masks: [AlphaMask]
        let width: Int
        let height: Int
        /// **Which band of the frame this coverage is** — nil for a whole frame, and RENDER.md
        /// §3.8's strip otherwise. `PixelOps.RasterizeKey.window` carries the argument at length and
        /// it is the same one: a plan's strips are all the same size but the last, so a key holding
        /// only the size would serve the second strip the first strip's coverage.
        let window: StripWindow?
        let quality: RenderQuality
        let versions: [LayerContentVersion?]
        let sourceStacks: [[RenderNode]]

        /// RenderNode carries Equatable effects. Hashing the count is enough for buckets; synthesized
        /// equality still compares every source tree, including nested masks and folder opacity.
        func hash(into hasher: inout Hasher) {
            hasher.combine(masks)
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(window)
            hasher.combine(quality)
            hasher.combine(versions)
            hasher.combine(sourceStacks.count)
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
    /// **A second ceiling now, not the bound** — `cacheBudgetBytes` below is what bounds this, exactly
    /// as `PixelOps.sharedRasterizeEntryLimit` is a second ceiling beside that cache's byte budget.
    /// Eight canvas-sized coverage buffers is 16 MiB at the owner's 2048x1024 and **128 MiB at
    /// 4096²**, two thirds of a 3 GB iPad's whole texture budget, held by a cache of masks — which is
    /// the asymmetry BUGS.md recorded on 2026-08-20 and RENDER.md §5 stage 7 came back for.
    static let cacheEntryLimit = 8

    /// **What this cache may hold, in bytes** — an eighth of `CompositorBudget.textureBudgetBytes`.
    ///
    /// **The fraction is derived rather than picked, which is what BUGS.md's entry said was missing.**
    /// A coverage buffer is one byte per pixel where a flatten is four, so an eighth of the texture
    /// budget buys this cache *half* as many canvas-sized entries as `PixelOps.rasterizeCache` gets
    /// from the whole of it — and half is the right ratio because a frame carries at most one mask per
    /// masked node and many more flattens than masked nodes. On the owner's iPad 9 that is 23 MiB,
    /// so the entry count of 8 (16 MiB at their canvas) still binds and nothing about their documents
    /// changes; at 4096² it is 11 entries' worth of budget against entries of 16 MiB apiece, so the
    /// bytes bind at one entry and the 128 MiB is gone.
    ///
    /// Borrowed from `CompositorBudget` rather than invented for the reason `PixelOps` gives: these
    /// are the same working set seen through different channels, and two numbers that must move
    /// together should be one number.
    static var cacheBudgetBytes: Int { CompositorBudget.textureBudgetBytes / 8 }

    /// Evicts in insertion order, as `PixelOps.rasterizeCache` does and for the same reason.
    private static let cache = MaskCache(limit: cacheEntryLimit)

    private final class MaskCache {
        private let limit: Int
        private var entries: [CacheKey: ResolvedMask] = [:]
        private var order: [CacheKey] = []
        private var residentBytes = 0
        private let lock = NSLock()
        private var pressureToken: MemoryPressure.Token?

        init(limit: Int) {
            self.limit = limit
            // **Nothing dropped these before**, exactly as nothing dropped `PixelOps`'s rasterize
            // memo before that one was wired: `clearCache`'s doc comment said "and for a memory
            // warning" while every caller in the tree was a test. Registered in the cache's own
            // initialiser rather than in a view or the app delegate, because this is what knows it is
            // a cache: the responder's lifetime is the cache's, and both are the process's.
            //
            // **Through `MemoryPressure` rather than two `UIApplication` notifications** — RENDER.md
            // §2.6 and BUGS.md's census item 6, which counts six caches each naming the same two
            // constants. A warning halves and a background clears; see `MemoryPressurePolicy` for why
            // those differ, and `PixelOps.RasterizeCache.init` for the identical registration.
            //
            // Correctness-neutral by construction: a `ResolvedMask` is derived from the masks and the
            // content versions in the key, so dropping one costs the resolution again and nothing
            // else.
            MemoryPressure.startObservingSystemEvents()
            pressureToken = MemoryPressure.register("MaskResolver.cache") { [weak self] level in
                self?.trim(toBytes: MemoryPressurePolicy.budget(level, normalBytes: MaskResolver.cacheBudgetBytes))
            }
        }

        func value(for key: CacheKey) -> ResolvedMask? {
            lock.lock(); defer { lock.unlock() }
            return entries[key]
        }

        /// **The byte budget first, then the count** — `PixelOps.RasterizeCache.store`'s rule
        /// verbatim, including its `order.count > 1` guard: a cache that refuses to hold a single
        /// coverage buffer has stopped memoizing the thing it exists for, and at 4096² one entry
        /// alone is 16 MiB against a 23 MiB budget on the owner's device.
        func store(_ mask: ResolvedMask, for key: CacheKey) {
            lock.lock(); defer { lock.unlock() }
            let bytes = mask.coverage.count
            if let replaced = entries.updateValue(mask, forKey: key) {
                residentBytes -= replaced.coverage.count
            } else {
                order.append(key)
            }
            residentBytes += bytes
            let budget = MaskResolver.cacheBudgetBytes
            while order.count > 1, order.count > limit || residentBytes > budget {
                let evicted = order.removeFirst()
                if let removed = entries.removeValue(forKey: evicted) { residentBytes -= removed.coverage.count }
            }
        }

        func removeAll() {
            lock.lock(); defer { lock.unlock() }
            entries.removeAll(); order.removeAll(); residentBytes = 0
        }

        /// Evicts oldest-first until the cache holds at most `bytes` — the memory-pressure response.
        /// No "keep the newest whatever it costs" exemption, for `PixelOps`' reason: nothing is being
        /// returned on this path.
        func trim(toBytes bytes: Int) {
            lock.lock(); defer { lock.unlock() }
            while residentBytes > bytes, !order.isEmpty {
                let evicted = order.removeFirst()
                if let removed = entries.removeValue(forKey: evicted) { residentBytes -= removed.coverage.count }
            }
        }

        var entryCount: Int {
            lock.lock(); defer { lock.unlock() }
            return entries.count
        }

        var bytesResident: Int {
            lock.lock(); defer { lock.unlock() }
            return residentBytes
        }
    }
}
