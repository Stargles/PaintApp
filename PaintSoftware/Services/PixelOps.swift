import UIKit
import SwiftUI

/// Pixel-level image processing that backs the Select & Move tool. "Select a region and
/// move/resize/rotate/fill/clear it" is inherently a raster operation (this is how Procreate works
/// — it's fully raster under the hood), which the whole engine now is end to end. These helpers
/// are the bridge: whenever a selection-based edit touches a cel, its current content (baked image
/// + live strokes) gets flattened into a plain `UIImage` — see `Cel.bakedImage`.
enum PixelOps {
    static func transparentFormat(scale: CGFloat = 1) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        return format
    }

    /// A fully transparent image of `size`, at scale 1.
    ///
    /// One spelling for what several call sites were writing as a bare renderer with an empty body,
    /// and the app's answer to "the pixels that were not there": a blank
    /// `RasterLayerTexture.renderToUIImage()` hands back a 1×1 of this, and an undo patch for a
    /// region of a tier that had no bitmap is one of these at the patch's own size.
    static func transparentImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: transparentFormat()).image { _ in }
    }

    static let deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB()

    /// `transform` applied to `0..<count` across every core, results in index order.
    ///
    /// **The one fan-out primitive for the two per-cel walks PERFORMANCE.md item 9 is about**, which
    /// are the same walk: `ProjectStore.load` decodes one cel per iteration, and `FrameRecipe.resolveSources`
    /// rasterizes one. Both were serial, both are embarrassingly parallel — no iteration reads what
    /// another writes — and the second was MEASURED at 78.2 ms on the main actor for six layers at
    /// 2048×1024 on a playback tick, which was the largest main-thread term on that tick. With this
    /// in place the same test reads **~22 ms** (MEASURED 2026-08-20; PERFORMANCE.md item 4b carries
    /// the re-taken table and the three unchanged composites that calibrate it).
    ///
    /// **What this does and does not buy, stated plainly.** It shortens wall clock by spreading the
    /// work over cores. It does **not** move the work off the calling thread — `concurrentPerform`
    /// blocks its caller and in fact recruits it as one of the workers, so a main-actor caller is
    /// still blocked, for a fraction of what it was. Getting off the main thread entirely is a
    /// separate change with a separate risk (`ProjectStore.loadInBackground`), and conflating the two
    /// would have made this primitive look like it did something it does not.
    ///
    /// **Every tier the two callers touch is already documented as reachable off-main**, which is why
    /// this is safe rather than merely plausible: `RasterLayerTexture` serialises on its own `NSLock`,
    /// `VectorCanvas.render()` says in its own header that a background queue reaches it, the
    /// `rasterizeCache` is lock-guarded, and `Compositor.composite` has run `UIGraphicsImageRenderer`
    /// on `sandwichQueue` since the sandwich landed. What this adds is concurrency *between* cels, and
    /// two different cels share no mutable state at all.
    ///
    /// Below two iterations there is nothing to distribute and the dispatch is pure overhead, so the
    /// call runs inline — which also keeps a one-layer document exactly as it was.
    static func parallelMap<T>(_ count: Int, _ transform: (Int) -> T) -> [T] {
        guard count > 1 else { return count == 1 ? [transform(0)] : [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        // An autorelease pool per iteration, for `PerfBaselineTests.stamp`'s reason one tier up: each
        // of these produces a canvas-sized `UIImage` (8 MiB at 2048×1024), and without a pool per
        // worker thread they accumulate until the enclosing pool drains — which for a 32-cel document
        // is a quarter of a gigabyte of temporaries that the serial version never held at once.
        DispatchQueue.concurrentPerform(iterations: count) { index in
            autoreleasepool { (buffer + index).initialize(to: transform(index)) }
        }
        let results = Array(UnsafeBufferPointer(start: buffer, count: count))
        buffer.deinitialize(count: count)
        buffer.deallocate()
        return results
    }

    /// A genuinely independent copy of `rect` out of `image`, in UIKit top-left coordinates.
    ///
    /// **Not** `CGImage.cropping(to:)`: that returns an image which keeps a reference to the original
    /// image's pixel data, so the parent buffer stays alive and a "crop" retains just as much memory
    /// as the whole thing. This renders into a fresh buffer of exactly `rect.size`, which is the
    /// entire point when the caller is shrinking what an undo step holds on to.
    ///
    /// `preferredRange = .standard` matters for the same reason: left at `.automatic`, a wide-colour
    /// device backs the new buffer with 16 bits per component and the patch costs twice what the
    /// caller's byte accounting says it does.
    ///
    /// Returns nil for an empty or fully out-of-bounds rect.
    static func copiedSubimage(of image: UIImage, in rect: CGRect) -> UIImage? {
        let bounds = CGRect(origin: .zero, size: image.size)
        let clamped = rect.integral.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        let format = transparentFormat()
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: clamped.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -clamped.origin.x, y: -clamped.origin.y))
        }
    }

    static func uiColor(from color: Color, opacity: Double = 1.0) -> UIColor {
        color.resolvedUIColor(opacity: opacity)
    }

    /// Flattens a cel's fill-tool wash, baked raster content, and live strokes into one
    /// canvas-sized image — the full stack a select/move/fill-selection/clear op should treat as
    /// "the cel's pixels".
    /// `quality` reaches only the vector tier, which is the only one with a cheaper mode to offer:
    /// `RasterLayerTexture` has a single rendering. Defaulted to `.full` so the ~10 existing callers
    /// are unchanged — it is threaded through for `RenderRequest`, whose §9.1 contract is to carry a
    /// quality, and a quality the snapshot then ignored would be a field that lies.
    ///
    /// **Memoized per cel version (§5.2).** The two tiers underneath already cache — `renderToUIImage`
    /// per `RasterLayerTexture.version`, `VectorCanvas.render` per its own — but the *flatten* did
    /// not, so every call paid a canvas-sized `UIGraphicsImageRenderer` and up to four full-canvas
    /// draws. That was measured as the expensive half of a composite: six layers at 2048² cost 276 ms
    /// to snapshot against 84 ms to actually composite. §5.2 names this memo as the fix and notes it
    /// "helps every consumer rather than only the live path", which is why it lives here rather than
    /// in `makeRenderRequest`.
    ///
    /// This is **not** the texture cache phase 2 deleted. That one keyed on the identity of a
    /// `UIImage` this function mints fresh every call, so it could never hit and was measured never
    /// hitting. The key here comes from the model instead, exactly as that post-mortem prescribed:
    /// cel id, both tier versions, both image identities, size and quality. It adds no new trust —
    /// those versions are already what the two caches below it rely on.
    /// `memoize: false` renders without reading or writing the shared cache, for a caller that keeps
    /// its own — `OnionSkinRasterCache`, which asks for a cel at a *reduced* size.
    ///
    /// **It exists because this cache evicts FIFO under a shared byte budget**, and its entries are
    /// canvas-sized: 64 MiB each at 4096². Ten small onion-skin entries pushed through it would walk
    /// ten of the compositor's out in insertion order, trading a stall on the ghost for a stall on
    /// the artwork. The alternative — a second copy of `rasterizeUncached`'s draw order living in the
    /// onion skin — is the "two compositing implementations drift" mistake this file's own header
    /// warns about, one tier down. One flag is cheaper than either.
    ///
    /// **`derived` is the `ContentProvider` seam** (VECTOR_INTERPOLATION item 18, KEYFRAMES §8): the
    /// content a cel *shows* when it is not the content it *stores*. Nil — the default, and what
    /// every caller passed before the seam existed — is exactly today's behaviour, so the change is
    /// opt-in call site by call site. Resolved by the caller rather than by a provider held here,
    /// because this function runs on `parallelMap`'s worker threads and resolving a provider reads
    /// the document; see `DerivedCelContent.render`.
    ///
    /// **Its identity is in the memo key and that is not optional.** The moment this can return
    /// different pixels for one `Cel`, a key built only from the cel's stored tiers is a key that
    /// cannot tell them apart — and the symptom is silence, because the caches *above* this one
    /// (`CanvasView.SandwichKey`, which compares the whole node tree) rebuild happily from the stale
    /// entry. KEYFRAMES §4.5, "pin this on day one".
    static func rasterize(cel: Cel, canvasSize: CGSize, quality: RenderQuality = .full,
                          memoize: Bool = true, derived: DerivedCelContent? = nil,
                          pose: PoseMap? = nil) -> UIImage {
        let identity = FrozenCel.Identity(cel: cel, derived: derived?.identity, pose: pose)
        guard memoize else {
            return rasterizeUncached(FrozenCel(cel: cel, identity: identity, derived: derived,
                                               pose: pose, quality: quality),
                                     canvasSize: canvasSize, quality: quality)
        }
        let key = RasterizeKey(cel: identity, canvasSize: canvasSize, quality: quality, window: nil)
        if let hit = rasterizeCache.value(for: key) { return hit }
        // Frozen only after the memo has missed, so a hit never touches either tier — the tiers'
        // own memos are not free to fill (`RasterLayerTexture.renderToUIImage` pins the context's
        // buffer copy-on-write) and a warm flatten has no business filling them.
        let image = rasterizeUncached(FrozenCel(cel: cel, identity: identity, derived: derived,
                                                pose: pose, quality: quality),
                                      canvasSize: canvasSize, quality: quality)
        rasterizeCache.store(image, for: key)
        return image
    }

    /// The same flatten over values a caller froze earlier — `FrameRecipe`'s half of this function,
    /// and the reason the two cannot draw a cel differently from each other.
    ///
    /// **Through the same memo, keyed exactly as the live path keys it**, which is not an
    /// optimisation but the correctness rule: the live canvas and the bake must hit the same entries
    /// or an unchanged cel is flattened twice. `FrozenCel.Identity` is what makes that literal —
    /// there is one key type and one field list, built either from a live `Cel` or from the frozen
    /// copy of the same fields.
    /// **`window` is RENDER.md §3.8's strip.** Nil is a whole frame and every caller but the strip
    /// driver passes nil, so this is the identity everywhere it always was. Non-nil renders the same
    /// cel at the same *frame* scale into a `canvasSize` buffer that is a band of it — a translated
    /// CTM, not a smaller drawing, so a strip of a cel is byte-identical to that band of the whole.
    static func rasterize(_ frozen: FrozenCel, canvasSize: CGSize, quality: RenderQuality,
                          window: StripWindow? = nil) -> UIImage {
        let key = RasterizeKey(cel: frozen.identity, canvasSize: canvasSize, quality: quality,
                               window: window)
        if let hit = rasterizeCache.value(for: key) { return hit }
        let image = rasterizeUncached(frozen, canvasSize: canvasSize, quality: quality, window: window)
        rasterizeCache.store(image, for: key)
        return image
    }

    /// One cel's render inputs, frozen — every value `rasterizeUncached` draws, owned outright, plus
    /// the identity those values have.
    ///
    /// **Why a cel copy is not a freeze, which is the whole point of this type.** `Cel` is a struct,
    /// but `cel.raster` is a `RasterLayerTexture` *class* and `cel.vector` a `VectorCanvas` *class*.
    /// While the flatten is synchronous on the main actor no artist edit can interleave with it — the
    /// atomicity `renderSources` used to defend by staying there — but the moment it is not, a `Cel`
    /// copy still points at the live tiers and the next dab tears the frame. So the two class tiers
    /// are read here, once, and the two `UIImage` tiers are held by reference because a fill or a
    /// bake *replaces* them wholesale rather than drawing into them: holding the reference **is** the
    /// freeze for those.
    ///
    /// Building one costs at most what `rasterizeUncached` used to do inline — one memoized
    /// `renderToUIImage()` and one `VectorCanvas.freeze` — so nothing on the live path pays for the
    /// existence of the bake path.
    ///
    /// **What it does cost is one copy-on-write duplication, transiently, and RENDER.md §3.2 names
    /// it as the price.** `renderToUIImage()`'s image shares the tier's `CGContext` buffer
    /// copy-on-write, and until this type existed the only thing retaining it was
    /// `RasterLayerTexture.cachedImage`, which the next stamp drops *before* it writes — so the write
    /// was in place. A recipe in flight is a second retainer, so a stamp landing while one is
    /// unresolved duplicates the canvas. That window is one composite long, it is bounded at one
    /// buffer per raster leaf being edited, and it is what "the expensive state is already
    /// copy-on-write" buys: the alternative is `ProjectStore.SaveSnapshot`'s eager copy of every cel,
    /// which is the cost this stage removes.
    struct FrozenCel {

        /// Identity of a flatten, drawn entirely from model state.
        ///
        /// The two `UIImage` tiers are compared by object identity rather than content because that
        /// is how they change: a fill or a bake *replaces* `fillImage`/`bakedImage` wholesale rather
        /// than drawing into them, so a new object is exactly the signal that the pixels are new.
        struct Identity: Hashable {
            let celID: UUID
            let raster: ObjectIdentifier
            let rasterVersion: Int
            let vector: ObjectIdentifier?
            let vectorVersion: Int
            let fillImage: ObjectIdentifier?
            let bakedImage: ObjectIdentifier?
            /// **The seam's half of the key.** Nil for a cel that shows what it stores, which is
            /// every cel in a document using neither animation system — so an untouched document's
            /// keys are exactly the keys it had before `DerivedCelContent` existed. Type-erased
            /// because the *derivation* owns the enumeration: interpolation folds in the recipe's
            /// `t`, mode, spacing, group lattices, guides, local-edit ids and its keyframes' content
            /// versions, and a pose key will fold in the frame, and neither this type nor this file
            /// should have to learn either list. `AnyHashable` compares unequal across types, so two
            /// derivations can never collide on one entry.
            let derived: AnyHashable?
            /// **KEYFRAMES §4.4's container pose, as `PoseMap.encoded`** — what a transformation
            /// layer above this leaf, or a posed folder around it, resolved to at this frame. Six
            /// numbers for an affine pose and nine for a keystone (§8 stage 5b).
            ///
            /// **`derived` does not imply it, which is why this is here.** A vector cel folds the
            /// same pose into its derivation identity; a cel whose ink is in the raster tier has no
            /// derivation at all, and is posed below by the CTM instead (§2.12: raster resamples,
            /// vector re-poses). Without this field every frame of a move over a raster layer is one
            /// key, and the memo serves frame one's pixels for all of them — §4.5's trap in the exact
            /// form it describes, since `SandwichKey` compares the whole tree and rebuilds happily
            /// from the stale entry.
            let pose: [CGFloat]?

            init(cel: Cel, derived: AnyHashable?, pose: PoseMap? = nil) {
                self.derived = derived
                self.pose = pose.map(\.encoded)
                celID = cel.id
                // **Identity *and* version, for both tiers, and the identity is the load-bearing
                // half.** A version alone is monotonic only within one object's lifetime, while a
                // cel id outlives any number of them: reopening a project rebuilds every
                // `RasterLayerTexture` with its counter back at 0 under the same cel id saved in the
                // manifest, so a version-only key could match an entry cached before the last edit
                // and serve pre-edit pixels. Undoing a cel-content change can swap in a texture
                // object the same way. Keying on the object as well makes a fresh buffer a fresh key
                // by construction, which is cheaper to guarantee than to remember to clear the cache
                // at every point one can be replaced.
                raster = ObjectIdentifier(cel.raster)
                rasterVersion = cel.raster.version
                vector = cel.vector.map(ObjectIdentifier.init)
                // -1 rather than 0 for "no vector tier at all", so acquiring an empty one is a change.
                vectorVersion = cel.vector?.version ?? -1
                fillImage = cel.fillImage.map(ObjectIdentifier.init)
                bakedImage = cel.bakedImage.map(ObjectIdentifier.init)
            }
        }

        let identity: Identity
        let bakedImage: UIImage?
        /// The raster tier's pixels, or nil where it holds no bitmap at all — the skip
        /// `rasterizeUncached` has always made, taken at freeze time so the answer cannot change
        /// under the draw. Every vector cel has an empty raster tier, so nil is the common case.
        let strokesImage: UIImage?
        let vector: VectorCanvas.Frozen?
        let fillImage: UIImage?
        /// Already values-only and thread-safe by its own contract — see `DerivedCelContent.render`.
        let derived: DerivedCelContent?
        /// **§4.4's container pose, applied to the *stored* tiers** — see `Identity.pose` for why it
        /// is not implied by `derived`, and `rasterizeUncached` for where it is spent.
        let pose: PoseMap?

        init(cel: Cel, identity: Identity, derived: DerivedCelContent?,
             pose: PoseMap? = nil, quality: RenderQuality) {
            self.identity = identity
            self.derived = derived
            self.pose = pose
            bakedImage = cel.bakedImage
            fillImage = cel.fillImage
            strokesImage = cel.raster.hasContent ? cel.raster.renderToUIImage() : nil
            // Frozen even when `derived` will replace it: the thunk answers nil for a recipe that
            // is not evaluable yet, and the fallback is this tier (see `rasterizeUncached`).
            vector = cel.vector?.freeze(quality: quality)
        }

        init(cel: Cel, derived: DerivedCelContent?, pose: PoseMap? = nil,
             quality: RenderQuality) {
            self.init(cel: cel, identity: Identity(cel: cel, derived: derived?.identity, pose: pose),
                      derived: derived, pose: pose, quality: quality)
        }
    }

    private struct RasterizeKey: Hashable {
        let cel: FrozenCel.Identity
        let width: Int
        let height: Int
        let quality: RenderQuality
        /// **Where in the frame this flatten is a band of** — nil for the whole frame, which is
        /// every entry anything but RENDER.md §3.8's strip driver mints.
        ///
        /// **Without it two strips of equal height collide on one entry.** The rest of this key is
        /// the cel's identity and the buffer's *size*, and a plan's strips are all the same size but
        /// the last — so the second strip of a frame would be served the first strip's pixels, and
        /// the picture would be one band repeated down the canvas with no error anywhere. That is
        /// the same family as the memo trap KEYFRAMES §4.5 names (a pose key the memo cannot see),
        /// reached through the one field nobody thought a flatten needed.
        let window: StripWindow?

        init(cel: FrozenCel.Identity, canvasSize: CGSize, quality: RenderQuality,
             window: StripWindow?) {
            self.cel = cel
            width = Int(canvasSize.width.rounded())
            height = Int(canvasSize.height.rounded())
            self.quality = quality
            self.window = window
        }
    }

    /// The entry ceiling on `rasterizeCache` below, a named constant because something outside this
    /// file has to be able to ask **how many canvas-sized flattens that cache can actually hold** —
    /// see `OnionSkinBudget.cachedSourceCount(for:resolution:sharedBudgetBytes:)`, which needs it to
    /// answer whether an onion-skin window at Full fits, since at Full the onion skin caches through
    /// here rather than through its own store. Read-only; the cache is still the only writer.
    static let sharedRasterizeEntryLimit = 24

    /// Small and bounded on purpose: one canvas-sized image is 16.8 MB at 2048² and 64 MB at 4000²
    /// (§5.3), so this holds a working set — the layers of the current frame, plus the neighbours a
    /// scrub touches — and not a history. Evicts in insertion order, which for a cache read in
    /// bottom-to-top stack order is near enough to LRU to not be worth the bookkeeping.
    ///
    /// **The entry count alone was not a bound, and on a 4K canvas it was not close to one.** Twenty
    /// four entries is 403 MB at 2048² and **1.61 GB at 4096²** — more than a 3 GB iPad's whole
    /// process limit, from a cache whose stated job is to hold "a working set". Nor is it hard to
    /// fill: the key carries `rasterVersion`, so every stroke the artist finishes mints a fresh entry
    /// and the one it supersedes stays until twenty-three more have been drawn. The byte budget below
    /// is what actually bounds it; the entry count is kept as a second ceiling for small canvases,
    /// where 24 canvas-sized images is a sane working set and the bytes would never bind.
    ///
    /// **It borrows `CompositorBudget.textureBudgetBytes` rather than inventing a second number**, and
    /// that is the right relationship rather than a shortcut: this is the CPU-side twin of the GPU's
    /// upload cache — the same canvas-sized flattens, one memo away from being uploaded — so the two
    /// should scale with the device on the same rule. It does mean the pair can hold twice the budget
    /// between them, which is accounted for: the budget is one sixteenth of the device precisely so
    /// that the whole compositing subsystem is about one eighth of it.
    private static let rasterizeCache = RasterizeCache(limit: sharedRasterizeEntryLimit)

    private final class RasterizeCache {
        private let limit: Int
        private var entries: [RasterizeKey: (image: UIImage, bytes: Int)] = [:]
        private var order: [RasterizeKey] = []
        private var residentBytes = 0
        private let lock = NSLock()
        private var pressureToken: MemoryPressure.Token?

        init(limit: Int) {
            self.limit = limit
            // **Nothing dropped these before.** `clearRasterizeCache` existed for tests and its doc
            // comment said "and for a memory warning" — but no code anywhere subscribed, so the
            // largest CPU-side cache in the app was the one thing a memory warning could not reach.
            // Registered here rather than in a view or the app delegate because this is what knows it
            // is a cache: the responder's lifetime is the cache's, and both are the process's.
            //
            // **One seam rather than two `UIApplication` notifications** — RENDER.md §2.6, and
            // BUGS.md's census item 6, which counts six caches each naming the same two constants.
            // `MemoryPressure` owns the subscription now; this owns the response.
            //
            // **A warning trims and does not clear, which is a change.** Dropping the whole memo is
            // right for a backgrounded app and wrong for a live one: the entries this cache is most
            // likely to be asked for next are the ones it stored most recently, so halving under
            // `MemoryPressurePolicy` gives the bytes back and leaves the current frame's flattens in
            // place, where `removeAll()` charged the artist a full re-flatten on the exact turn the
            // device was struggling.
            MemoryPressure.startObservingSystemEvents()
            pressureToken = MemoryPressure.register("PixelOps.rasterizeCache") { [weak self] level in
                self?.trim(toBytes: MemoryPressurePolicy.budget(level, normalBytes: CompositorBudget.textureBudgetBytes))
            }
        }

        func value(for key: RasterizeKey) -> UIImage? {
            lock.lock(); defer { lock.unlock() }
            return entries[key]?.image
        }

        func store(_ image: UIImage, for key: RasterizeKey) {
            lock.lock(); defer { lock.unlock() }
            let bytes = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
            if let replaced = entries.updateValue((image, bytes), forKey: key) {
                residentBytes -= replaced.bytes
            } else {
                order.append(key)
            }
            residentBytes += bytes
            // The byte budget first, then the count. Never evicts the entry just stored, however far
            // over budget one image on its own puts this: the caller is about to return it either
            // way, and a cache that refuses to hold a single canvas is a cache that has stopped
            // memoizing the thing it exists for.
            let budget = CompositorBudget.textureBudgetBytes
            while order.count > 1, order.count > limit || residentBytes > budget {
                let evicted = order.removeFirst()
                if let removed = entries.removeValue(forKey: evicted) { residentBytes -= removed.bytes }
            }
        }

        func removeAll() {
            lock.lock(); defer { lock.unlock() }
            entries.removeAll(); order.removeAll(); residentBytes = 0
        }

        /// Evicts oldest-first until the cache holds at most `bytes` — the memory-pressure response,
        /// and the only place `removeAll()`'s wholesale drop is *not* what happens.
        ///
        /// **No "never evict the entry just stored" exemption here**, unlike `store`. That rule exists
        /// so a caller's own return value is memoized however large it is; nothing is being returned
        /// on this path, and a device asking for memory is not the moment to keep an entry that on its
        /// own exceeds what it is being asked to fit into.
        func trim(toBytes bytes: Int) {
            lock.lock(); defer { lock.unlock() }
            while residentBytes > bytes, !order.isEmpty {
                let evicted = order.removeFirst()
                if let removed = entries.removeValue(forKey: evicted) { residentBytes -= removed.bytes }
            }
        }

        var bytesResident: Int {
            lock.lock(); defer { lock.unlock() }
            return residentBytes
        }
    }

    /// Drops every memoized flatten. For tests that need to measure the uncached cost, and for a
    /// memory warning — which now actually calls it; see `RasterizeCache.init`.
    static func clearRasterizeCache() { rasterizeCache.removeAll() }

    /// What the flatten memo is holding, for `PerfBaselineTests`. Nothing in the render path reads it.
    static var rasterizeCacheBytes: Int { rasterizeCache.bytesResident }

    /// **A container pose's raster tiers, rasterised flat and carried onto the pose's quad** —
    /// KEYFRAMES.md §2.12's *"a transform layer resamples raster content below it"* with the resample
    /// spelled projectively, since §8 stage 5b lets that pose be a keystone.
    ///
    /// **Two allocations rather than one, and that is inherent rather than sloppy.** An affine pose
    /// is a CTM, so CoreGraphics resamples straight into the destination context; a homography has no
    /// CTM, so the tiers have to exist as pixels *before* they can be warped. That is the same
    /// trade-off `TextLayout.warpedGlyphs` accepts, and it is paid only by a cel actually underneath
    /// a keystoned transformation layer.
    ///
    /// **The destination is clipped to the frame first**, `render(floatingPiece:into:)`'s own rule:
    /// pixels outside are the ones the caller's context is about to clip away, and allocating them
    /// was never anything but cost. `maximumFloatingWarpTexels` is what bounds the rest.
    ///
    /// The caller has already applied the strip window's shift to the CTM, so both the source frame
    /// and the returned destination are in the *frame's* own coordinates.
    private static func warpedPosedTiers(frame: CGRect, through homography: Homography,
                                         drawing draw: () -> Void) -> (image: UIImage, destination: CGRect)? {
        guard frame.width >= 1, frame.height >= 1,
              let quad = PoseInterpolation.mapped(Quad.rect(frame), through: homography) else { return nil }
        let destination = quad.boundingBox.integral.intersection(frame.integral)
        guard destination.width >= 1, destination.height >= 1 else { return nil }
        // Scale 1, which is the format the caller's own renderer uses — the raster tiers are bitmaps
        // that carry their own resolution and `RenderQuality` reaches only the vector tier, so a
        // second scale here would resample the tiers twice.
        let flat = UIGraphicsImageRenderer(bounds: frame, format: transparentFormat())
            .image { _ in draw() }
        guard let source = flat.cgImage, source.width > 0 else { return nil }
        // Source **texels per frame point**, measured off the bitmap rather than assumed to be the
        // format's scale — the renderer rounds its pixel size, so the two differ by up to a texel on a
        // frame whose points are not whole texels. `render(floatingPiece:into:)` measures it the same
        // way and for the same reason.
        let sourceScale = CGFloat(source.width) / frame.width
        guard let warped = ImageWarp.warpedImage(source: source, sourceScale: sourceScale,
                                                 boxSize: frame.size, homography: homography,
                                                 destination: destination,
                                                 maximumDestinationTexels: maximumFloatingWarpTexels)
        else { return nil }
        return (UIImage(cgImage: warped, scale: 1, orientation: .up), destination)
    }

    private static func rasterizeUncached(_ cel: FrozenCel, canvasSize: CGSize,
                                          quality: RenderQuality,
                                          window: StripWindow? = nil) -> UIImage {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        // **The rect every tier is drawn into.** Without a window it is the buffer, which is what
        // this function has always done. With one it is the *frame*, shifted so that the window's
        // top-left lands at the buffer's — the same drawing at the same scale, seen through a hole.
        // CoreGraphics clips it to the context, so nothing outside the band is rasterized and the
        // strip costs a strip's memory rather than a frame's.
        let content = window.map {
            CGRect(origin: CGPoint(x: -$0.origin.x, y: -$0.origin.y), size: $0.frameSize)
        } ?? bounds
        // **The raster tier is skipped outright when it holds no bitmap**, rather than drawn as a
        // sheet of transparency. Every vector cel has an empty raster tier, so this is the common
        // case and not the odd one, and the draw it removes is a full-canvas blit of nothing. The
        // test is `FrozenCel.strokesImage` being nil, taken when the cel was frozen.
        //
        // A vector cel's live strokes/images live in `vector` (rendered to a native-res image),
        // not in `raster` — include it so fill, select/move, and cross-layer fill references treat
        // a vector layer's content as pixels just like a raster layer's.
        //
        // **Derived content *replaces* that tier rather than stacking above it**, which matters for
        // exactly one of the two recipe modes. A `.generate` in-between stores no display list at
        // all, so either order looks the same; a `.reproject` one keeps the artist's own strokes in
        // `vector` and the evaluation is those same strokes *re-posed*, so drawing both would show
        // the drawing twice — once where it was drawn and once where it moved to.
        //
        // A nil answer from the thunk is "not yet" (a recipe mid-edit is not evaluable), and falls
        // back to the stored tier rather than to a hole.
        let vectorImage = cel.derived?.render(quality) ?? cel.vector?.render(quality: quality)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { context in
            // **KEYFRAMES §2.12's raster half, and it is the *other* currency from the vector one.**
            // A transformation layer *re-poses* vector objects — `cel.derived` above already holds
            // ink stamped at the posed position, so `vectorImage` must not be touched here — and
            // *resamples* raster content, which is what this CTM is. The owner ruled the difference
            // inherent rather than a defect to chase: "a raster layer softens under a push-in while
            // the vector layer beside it stays sharp".
            //
            // **The window is handled by translating rather than by the `content` rect**, because a
            // rect offset only composes with the pose the way it does with the identity. Drawing an
            // image into `content` maps a frame point p to p − origin; what a posed strip wants is
            // pose(p) − origin, so the shift goes on the CTM outside the pose and the draw is into
            // the frame's own rect. With no pose this branch is not taken at all, so every existing
            // caller's bytes are the bytes they were.
            //
            // **The projective arm is a warp and not a CTM, which is KEYFRAMES.md §8 stage 5b's raster
            // half.** CoreGraphics has no projective CTM at all, so a keystoned container pose is
            // rasterised flat and carried onto its quad by `ImageWarp` — the same call
            // `render(floatingPiece:into:)` and `TextLayout.warpedGlyphs` already make. The affine arm
            // below is untouched and stays a `concatenate`, so **every document that has never held a
            // keystone renders byte for byte what it rendered**: `PoseMap` demotes an affine
            // homography before it gets here, so `.projective` is a fact about the pose rather than
            // about which initialiser ran.
            let posedTiers: (() -> Void) -> Void = { draw in
                guard let pose = cel.pose else { return draw() }
                context.cgContext.saveGState()
                if let window { context.cgContext.translateBy(x: -window.origin.x, y: -window.origin.y) }
                switch pose {
                case .affine(let transform):
                    context.cgContext.concatenate(transform)
                    draw()
                case .projective(let homography):
                    let frame = CGRect(origin: .zero, size: window?.frameSize ?? canvasSize)
                    if let warped = Self.warpedPosedTiers(frame: frame, through: homography,
                                                          drawing: draw) {
                        warped.image.draw(in: warped.destination)
                    }
                }
                context.cgContext.restoreGState()
            }
            // The rect the posed tiers draw into: the frame in its own coordinates, since the shift
            // above has already moved the origin. Identical to `content` when there is no window.
            let frameRect = CGRect(origin: .zero, size: window?.frameSize ?? canvasSize)
            posedTiers {
                cel.bakedImage?.draw(in: cel.pose == nil ? content : frameRect)
                cel.strokesImage?.draw(in: cel.pose == nil ? content : frameRect)
            }
            vectorImage?.draw(in: content)
            // **`fillImage` is last, and that is the whole of LASSO_FILL.md §2a on the preview side.**
            // A fill covers everything already on the cel, so the live preview has to stack the way
            // the commit will (`commitInteractiveFill` composites the preview over the raster tier) or
            // the artist watches the picture rearrange itself when they lift the pencil.
            //
            // Only the *live* preview is ever in this tier: every commit path passes `newFill: nil`
            // (see `registerUndoableCelChange`), so a cel at rest has `fillImage == nil` and nothing
            // else that flattens a cel — thumbnails, onion skin, export, Move's lift, the merge — sees
            // any difference from this line at all.
            //
            // It also settles a disagreement that predates the fill ruling: `LayerHostView` has stacked
            // `fillImageView` above `bakedImageView` since the fill preview became a recolour preview,
            // while this drew it below. The two now agree, in the one order the commit produces.
            posedTiers { cel.fillImage?.draw(in: cel.pose == nil ? content : frameRect) }
        }
    }

    // `compositeCanvas` lived here: a flat walk of `layers` that drew each visible layer's active cel
    // at its own opacity, always `.normal`, for the project thumbnail. It is deleted rather than
    // deprecated — LAYER_COMPOSITING.md §5.2, phase 3 — because the whole argument of §1 is that two
    // compositing implementations drift, and a second one kept "just for thumbnails" is exactly how
    // that starts. `Compositor.composite` is the one path now; `ProjectStore.SaveSnapshot` calls it.
    //
    // The flat walk itself survives as `CompositorParityLogicTests.flatWalkComposite`, where it is
    // the oracle rather than an implementation: the tree walk is required to reproduce it byte for
    // byte, and freezing it in the test is what keeps that claim meaningful now that nothing in the
    // app performs it.

    /// Finds the bounding rect (in point space, assuming scale 1 — which everything here renders at)
    /// of all non-transparent pixels in the image. Returns nil if the image has no visible content.
    ///
    /// Scans through an unsafe pointer rather than subscripting the array: this runs synchronously on
    /// the main thread when the Move tool engages, and a canvas-sized image is several million
    /// pixels — enough for the bounds-checked version to be a visible hang in a debug build.
    static func opaqueContentBounds(_ image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: width * 4, space: deviceRGBColorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        pixels.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for y in 0..<height {
                let row = base + y * width * 4
                // Narrow the horizontal search to what's still unknown: once a row's pixels all sit
                // inside the running [minX, maxX] span they can't widen it, so only the edges matter.
                var x = 0
                var rowHasContent = false
                while x < width {
                    if row[x * 4 + 3] > 0 {
                        rowHasContent = true
                        if x < minX { minX = x }
                        break
                    }
                    x += 1
                }
                guard rowHasContent else { continue }
                var right = width - 1
                while right > maxX {
                    if row[right * 4 + 3] > 0 { maxX = right; break }
                    right -= 1
                }
                if y < minY { minY = y }
                maxY = y
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: CGFloat(minX), y: CGFloat(minY),
                      width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    }

    /// Splits a canvas-sized image into the pixels inside `path` ("piece") and the same image with
    /// that region cleared to transparent ("remainder"), both still canvas-sized.
    static func maskedPiece(image: UIImage, path: CGPath) -> (piece: UIImage, remainder: UIImage) {
        let bounds = CGRect(origin: .zero, size: image.size)
        let format = transparentFormat()

        let piece = UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
            ctx.cgContext.saveGState()
            ctx.cgContext.addPath(path)
            ctx.cgContext.clip()
            image.draw(in: bounds)
            ctx.cgContext.restoreGState()
        }
        let remainder = UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
            image.draw(in: bounds)
            ctx.cgContext.setBlendMode(.clear)
            ctx.cgContext.addPath(path)
            ctx.cgContext.fillPath()
        }
        return (piece, remainder)
    }

    /// Crops a canvas-sized (scale-1) image to `rect`, in the same point space it was rendered at.
    static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let pixelRect = CGRect(x: rect.origin.x * image.scale, y: rect.origin.y * image.scale,
                                width: rect.width * image.scale, height: rect.height * image.scale).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// The most destination texels a distorted piece's warp may write, per axis.
    ///
    /// `TextLayout.maximumWarpDestinationTexels`' number and its argument, restated for the second
    /// consumer rather than reached across a `View`-adjacent file: `ImageWarp.warpedImage` holds three
    /// `w × h × 4` buffers of the destination at once, so 4096 is 3 × 64 MiB on top of the
    /// canvas-sized flatten and composite the bake already pays. It is not a refusal — past the cap
    /// the warp is rasterised smaller and drawn up into the full rectangle — and the clip to the
    /// canvas below comes first, so on a canvas of 4096² or less it never binds at all.
    static let maximumFloatingWarpTexels: CGFloat = 4096

    /// Renders a floating piece (with its live transform applied) into a canvas-sized image, ready
    /// to be composited over a target cel's baked image at commit time.
    ///
    /// **Two arms, and the affine one is untouched.** A piece nobody has distorted takes the
    /// `concatenate`-and-draw it always took, bit for bit — which matters more than it looks, because
    /// the projective solver *would* have answered for it: an undistorted quad comes back with `g`
    /// and `h` at exactly zero and its corners within 4.5e-13 of the affine's own answer
    /// (`tools/distort_seam_ab.swift`, MEASURED 2026-09-02). Routing it through the warp anyway would
    /// trade CoreGraphics' resampler for `ImageWarp`'s bilinear one on every existing Move, which is
    /// a change to shipped output for no gain.
    static func render(floatingPiece piece: FloatingPiece, into canvasSize: CGSize) -> UIImage {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        // **The distort arm, and it is the same matrix the live preview was shown under** — see
        // `FloatingPiece.homography`, which both read. `destination` is clipped to the canvas first,
        // because pixels outside it are the ones the composite is about to throw away and allocating
        // them was never anything but cost (`TextLayout.warpedGlyphs`' own rule).
        if piece.distortQuad != nil, let source = piece.pieceImage.cgImage,
           piece.baseSize.width > 0, source.width > 0, let homography = piece.homography {
            // Source **texels per box point**, taken from the bitmap rather than from
            // `pieceImage.scale` — `crop` rounds its pixel rectangle to `.integral`, so the two differ
            // by up to a texel on a piece whose bounds are not whole pixels. `TextLayout.warpedGlyphs`
            // measures it the same way and for the same reason.
            let sourceScale = CGFloat(source.width) / piece.baseSize.width
            let destination = piece.canvasQuad.boundingBox.integral.intersection(bounds.integral)
            if destination.width >= 1, destination.height >= 1,
               let warped = ImageWarp.warpedImage(
                source: source, sourceScale: sourceScale, boxSize: piece.baseSize,
                homography: homography, destination: destination,
                maximumDestinationTexels: maximumFloatingWarpTexels) {
                return renderer.image { _ in
                    UIImage(cgImage: warped, scale: 1, orientation: .up).draw(in: destination)
                }
            }
        }
        return renderer.image { ctx in
            ctx.cgContext.saveGState()
            ctx.cgContext.concatenate(piece.transform.affineTransform)
            let half = CGSize(width: piece.baseSize.width / 2, height: piece.baseSize.height / 2)
            let drawRect = CGRect(x: -half.width, y: -half.height, width: piece.baseSize.width, height: piece.baseSize.height)
            piece.pieceImage.draw(in: drawRect)
            ctx.cgContext.restoreGState()
        }
    }

    /// A `newSize` copy of a canvas-sized image with its whole extent re-placed into `content` (a
    /// rectangle in the *new* canvas's point space), used by every canvas resize (see
    /// `CanvasManager.resizeCanvas(to:mode:)`) for a cel's `fillImage`/`bakedImage`.
    ///
    /// The rectangle, and the conditional `interpolationQuality`, are exactly
    /// `RasterLayerTexture.resized(to:placing:)`'s — read that one's doc comment for why. The two are
    /// separate functions only because one owns a `RasterLayerTexture` and the other a `UIImage`;
    /// they must keep drawing into the same rectangle or a cel's three raster tiers land in three
    /// places (`RasterLayerTexture.flippedImage`'s comment states that rule for the flip).
    static func resizedCanvasImage(_ image: UIImage, to newSize: CGSize, placing content: CGRect) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: newSize), format: transparentFormat())
        let resamples = content.size != image.size
        return renderer.image { ctx in
            if resamples { ctx.cgContext.interpolationQuality = .high }
            image.draw(in: content)
        }
    }

    /// Draws `overlay` on top of `base` (or on transparent if `base` is nil), both canvas-sized.
    static func compositeOver(base: UIImage?, overlay: UIImage) -> UIImage {
        let bounds = CGRect(origin: .zero, size: overlay.size)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { _ in
            base?.draw(in: bounds)
            overlay.draw(in: bounds)
        }
    }

    /// Flat color fill inside `path`, composited over `base` (canvas-sized).
    static func fill(base: UIImage, path: CGPath, color: UIColor) -> UIImage {
        let bounds = CGRect(origin: .zero, size: base.size)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { ctx in
            base.draw(in: bounds)
            ctx.cgContext.setFillColor(color.cgColor)
            ctx.cgContext.addPath(path)
            ctx.cgContext.fillPath()
        }
    }

    /// Composites `overlay` over `base` (or over transparent if `base` is nil), but only inside
    /// `path` — pixels outside stay exactly as `base` was. Used to keep a brush/eraser stroke or a
    /// flood-fill result from touching pixels outside the active selection when outside interaction
    /// is denied (see `CanvasManager.allowsPaintingOutsideSelection`): `overlay` is the tentative
    /// result, `base` the pre-edit content, so anything drawn outside `path` is discarded rather than
    /// applied.
    static func maskedComposite(base: UIImage?, overlay: UIImage, insidePath path: CGPath) -> UIImage {
        let bounds = CGRect(origin: .zero, size: overlay.size)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { ctx in
            base?.draw(in: bounds)
            ctx.cgContext.saveGState()
            ctx.cgContext.addPath(path)
            ctx.cgContext.clip()
            overlay.draw(in: bounds)
            ctx.cgContext.restoreGState()
        }
    }

    /// Clears the pixels inside `path` to transparent, over `base` (canvas-sized).
    static func clear(base: UIImage, path: CGPath) -> UIImage {
        let bounds = CGRect(origin: .zero, size: base.size)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { ctx in
            base.draw(in: bounds)
            ctx.cgContext.setBlendMode(.clear)
            ctx.cgContext.addPath(path)
            ctx.cgContext.fillPath()
        }
    }

    // MARK: - Automatic (magic wand) selection

    private struct IntPoint: Hashable { var x: Int; var y: Int }

    /// Flood-fills from `point` (canvas point space) across pixels within `tolerance` (0...1 fraction
    /// of the 0-255 channel range) of the starting pixel's color, 4-connected, then traces the
    /// boundary of the filled region into a `CGPath` usable both for the marching-ants overlay and
    /// for masking. Runs against `image` rendered at scale 1, so pixel coordinates equal point
    /// coordinates.
    static func floodFillMask(image: UIImage, point: CGPoint, tolerance: Double) -> CGPath? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: width * 4, space: deviceRGBColorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // `image` is a canvas-point-sized image rendered at scale 1, but its cgImage's pixel
        // dimensions can still differ slightly from the CGPoint-space width/height passed in via
        // `image.size` if scale != 1; since every caller here renders at scale 1, size == pixel count.
        let px = Int(point.x.rounded(.down)), py = Int(point.y.rounded(.down))
        guard px >= 0, px < width, py >= 0, py < height else { return nil }

        func colorAt(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
        }
        let target = colorAt(px, py)
        let tol = tolerance * 255.0
        func matches(_ x: Int, _ y: Int) -> Bool {
            let c = colorAt(x, y)
            return abs(Double(c.0 - target.0)) <= tol && abs(Double(c.1 - target.1)) <= tol &&
                   abs(Double(c.2 - target.2)) <= tol && abs(Double(c.3 - target.3)) <= tol
        }

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(px, py)]
        visited[py * width + px] = true
        while let (x, y) = stack.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let idx = ny * width + nx
                if !visited[idx], matches(nx, ny) {
                    visited[idx] = true
                    stack.append((nx, ny))
                }
            }
        }

        return contourPath(selected: visited, width: width, height: height)
    }

    /// Traces the boundary of a boolean pixel mask into a (possibly multi-loop) `CGPath`, by
    /// collecting every unit edge between a selected pixel and a non-selected neighbor and
    /// stitching those edges into closed loops. Enclosed unselected regions ("holes") fall out of
    /// this naturally as their own loop with opposite winding, so a nonzero-winding fill/clip
    /// correctly punches a hole for them.
    ///
    /// **A vertex can start *two* boundary edges, so the store has to be a multimap.** Where the
    /// selected region touches itself corner to corner — a 2x2 checkerboard, `(x, y)` and
    /// `(x+1, y+1)` selected with the other two clear — the shared corner is the start of one edge
    /// from each of those pixels. One out-edge per vertex keeps whichever was written second; the
    /// walk below then dead-ends there, `loop.count > 2` discards every edge it had already
    /// consumed, and `CGContext.fillPath` closes the resulting open subpath with a **straight
    /// line**. That is the straight-edged holes and wedges of TODO (44): the artist's *earlier*
    /// fill is what visibly breaks, because committing a second fill is what bakes the first one's
    /// GPU mask through this function for the first time. One dropped edge is not a small error —
    /// two 50x50 squares meeting at a corner lose 1 of their 400 edges, and with it 2,152 px of the
    /// 5,000 px they cover in the worst walk order measured.
    ///
    /// With the multimap, correctness is not a matter of degree: every boundary edge leaves one
    /// vertex and enters another, in- and out-degree are equal at every vertex, so by the Euler
    /// argument every walk returns to where it started and no subpath is ever left open.
    ///
    /// **Loops start in the raster order the edges were found in, not the dictionary's.**
    /// `IntPoint`'s `Hashable` is Swift's, whose hash seed is randomised per process, so
    /// `remaining.keys.first` made one mask trace to a different path on every launch of the app.
    /// `starts` makes the output a function of the mask alone. It is also *faster* — 495 ms against
    /// 751 ms on a 1024x1024 mask with 47k such vertices, measured in a standalone `swiftc -O` port
    /// of these lines on the Mac — because `Dictionary.keys.first` rescans from bucket zero on every
    /// loop.
    ///
    /// **At a shared corner the walk stays on the pixel it arrived on** instead of crossing to the
    /// diagonal one, which keeps the region 4-connected — the connectivity `floodFillMask` floods
    /// with — and yields two simple loops that touch, rather than one figure-of-eight through the
    /// corner. Both fill identically under either rule; the simple loops are the better input for
    /// the boolean path ops that `VectorCanvas` splits a fill with. It is a tidiness rule and not a
    /// guarantee: a walk that has to *begin* at a shared corner has no arrival direction to answer
    /// from, so a mask riddled with them still traces some self-touching loops.
    static func contourPath(selected: [Bool], width: Int, height: Int) -> CGPath? {
        func isSelected(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return selected[y * width + x]
        }

        var edges: [IntPoint: [IntPoint]] = [:]
        var starts: [IntPoint] = []
        func addEdge(from tail: IntPoint, to head: IntPoint) {
            if edges[tail] == nil {
                edges[tail] = [head]
                starts.append(tail)
            } else {
                edges[tail]?.append(head)
            }
        }
        for y in 0..<height {
            for x in 0..<width where isSelected(x, y) {
                if !isSelected(x, y - 1) { addEdge(from: IntPoint(x: x, y: y), to: IntPoint(x: x + 1, y: y)) }
                if !isSelected(x + 1, y) { addEdge(from: IntPoint(x: x + 1, y: y), to: IntPoint(x: x + 1, y: y + 1)) }
                if !isSelected(x, y + 1) { addEdge(from: IntPoint(x: x + 1, y: y + 1), to: IntPoint(x: x, y: y + 1)) }
                if !isSelected(x - 1, y) { addEdge(from: IntPoint(x: x, y: y + 1), to: IntPoint(x: x, y: y)) }
            }
        }
        guard !edges.isEmpty else { return nil }

        let path = CGMutablePath()
        var remaining = edges
        for start in starts where remaining[start] != nil {
            var loop: [IntPoint] = [start]
            var current = start
            var heading: (dx: Int, dy: Int)?
            while let outgoing = remaining[current], !outgoing.isEmpty {
                // The only vertex with a choice is a shared corner, where the two out-edges point
                // opposite ways and the arrival is perpendicular to both — so exactly one of them
                // turns towards the pixel the walk came in on, and that is the one with a positive
                // cross product against the heading (y grows downwards here).
                var choice = outgoing.count - 1
                if outgoing.count > 1, let heading {
                    for (index, head) in outgoing.enumerated()
                    where heading.dx * (head.y - current.y) - heading.dy * (head.x - current.x) > 0 {
                        choice = index
                        break
                    }
                }
                let next = outgoing[choice]
                if outgoing.count == 1 {
                    remaining.removeValue(forKey: current)
                } else {
                    remaining[current]?.remove(at: choice)
                }
                heading = (next.x - current.x, next.y - current.y)
                current = next
                if current == start { break }
                loop.append(current)
            }
            guard loop.count > 2 else { continue }
            let simplified = simplifyCollinear(loop)
            let points = simplified.map { CGPoint(x: $0.x, y: $0.y) }
            path.addLines(between: points)
            path.closeSubpath()
        }
        return path
    }

    /// Drops points that lie on a straight run between their neighbors, so long straight edges of
    /// the flood-filled region become one segment instead of one point per pixel.
    private static func simplifyCollinear(_ points: [IntPoint]) -> [IntPoint] {
        let n = points.count
        guard n > 2 else { return points }
        var result: [IntPoint] = []
        for i in 0..<n {
            let prev = points[(i - 1 + n) % n]
            let curr = points[i]
            let next = points[(i + 1) % n]
            let d1x = curr.x - prev.x, d1y = curr.y - prev.y
            let d2x = next.x - curr.x, d2y = next.y - curr.y
            if d1x * d2y - d1y * d2x != 0 {
                result.append(curr)
            }
        }
        return result.isEmpty ? points : result
    }

    // MARK: - Fill mask to vector path

    /// Converts a premultiplied-last RGBA byte buffer (e.g. the output of `MetalFillSession.fill`)
    /// into a closed `CGPath` by thresholding the alpha channel to produce a boolean mask and then
    /// tracing its contour. Used to create `VectorFillElement` geometry from the GPU flood fill.
    ///
    /// - Parameter minimumAlpha: the alpha at which a pixel counts as inside. 1 — any alpha at all —
    ///   is right for the bucket fill, whose output is a hard-edged region painted at one uniform
    ///   opacity. It is *wrong* for the lasso fill, which carries a coverage ramp along the artwork's
    ///   antialiased fringe (LASSO_FILL.md §6 step 6): tracing at `> 0` there would push the contour
    ///   out to the full threshold band. `CanvasManager.commitInteractiveFill` passes half the
    ///   gesture's opacity, which is the fringe's midpoint.
    static func pathFromAlphaMask(bytes: [UInt8], width: Int, height: Int,
                                  minimumAlpha: UInt8 = 1) -> CGPath? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        let mask = (0..<(width * height)).map { bytes[$0 * 4 + 3] >= minimumAlpha }
        return contourPath(selected: mask, width: width, height: height)
    }
}
