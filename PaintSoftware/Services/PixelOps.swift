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

    static let deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB()

    /// `transform` applied to `0..<count` across every core, results in index order.
    ///
    /// **The one fan-out primitive for the two per-cel walks PERFORMANCE.md item 9 is about**, which
    /// are the same walk: `ProjectStore.load` decodes one cel per iteration, and `renderSources`
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
                          memoize: Bool = true, derived: DerivedCelContent? = nil) -> UIImage {
        guard memoize else {
            return rasterizeUncached(cel: cel, canvasSize: canvasSize, quality: quality, derived: derived)
        }
        let key = RasterizeKey(cel: cel, canvasSize: canvasSize, quality: quality,
                               derived: derived?.identity)
        if let hit = rasterizeCache.value(for: key) { return hit }
        let image = rasterizeUncached(cel: cel, canvasSize: canvasSize, quality: quality, derived: derived)
        rasterizeCache.store(image, for: key)
        return image
    }

    /// Identity of a flatten, drawn entirely from model state.
    ///
    /// The two `UIImage` tiers are compared by object identity rather than content because that is
    /// how they change: a fill or a bake *replaces* `fillImage`/`bakedImage` wholesale rather than
    /// drawing into them, so a new object is exactly the signal that the pixels are new.
    private struct RasterizeKey: Hashable {
        let celID: UUID
        let raster: ObjectIdentifier
        let rasterVersion: Int
        let vector: ObjectIdentifier?
        let vectorVersion: Int
        let fillImage: ObjectIdentifier?
        let bakedImage: ObjectIdentifier?
        let width: Int
        let height: Int
        let quality: RenderQuality
        /// **The seam's half of the key.** Nil for a cel that shows what it stores, which is every
        /// cel in a document using neither animation system — so an untouched document's keys are
        /// exactly the keys it had before `DerivedCelContent` existed. Type-erased because the
        /// *derivation* owns the enumeration: interpolation folds in the recipe's `t`, mode,
        /// spacing, group lattices, guides, local-edit ids and its keyframes' content versions, and
        /// a pose key will fold in the frame, and neither this type nor this file should have to
        /// learn either list. `AnyHashable` compares unequal across types, so two derivations can
        /// never collide on one entry.
        let derived: AnyHashable?

        init(cel: Cel, canvasSize: CGSize, quality: RenderQuality, derived: AnyHashable? = nil) {
            self.derived = derived
            celID = cel.id
            // **Identity *and* version, for both tiers, and the identity is the load-bearing half.**
            // A version alone is monotonic only within one object's lifetime, while a cel id outlives
            // any number of them: reopening a project rebuilds every `RasterLayerTexture` with its
            // counter back at 0 under the same cel id saved in the manifest, so a version-only key
            // could match an entry cached before the last edit and serve pre-edit pixels. Undoing a
            // cel-content change can swap in a texture object the same way. Keying on the object as
            // well makes a fresh buffer a fresh key by construction, which is cheaper to guarantee
            // than to remember to clear the cache at every point one can be replaced.
            raster = ObjectIdentifier(cel.raster)
            rasterVersion = cel.raster.version
            vector = cel.vector.map(ObjectIdentifier.init)
            // -1 rather than 0 for "no vector tier at all", so acquiring an empty one is a change.
            vectorVersion = cel.vector?.version ?? -1
            fillImage = cel.fillImage.map(ObjectIdentifier.init)
            bakedImage = cel.bakedImage.map(ObjectIdentifier.init)
            width = Int(canvasSize.width.rounded())
            height = Int(canvasSize.height.rounded())
            self.quality = quality
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

        init(limit: Int) {
            self.limit = limit
            // **Nothing dropped these before.** `clearRasterizeCache` existed for tests and its doc
            // comment said "and for a memory warning" — but no code anywhere subscribed, so the
            // largest CPU-side cache in the app was the one thing a memory warning could not reach.
            // Registered here rather than in a view or the app delegate because this is what knows it
            // is a cache: the observer's lifetime is the cache's, and both are the process's.
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.removeAll()
            }
            // The event that actually arrives — see `CompositorMetalEngine.init`'s identical addition
            // and PERFORMANCE.md item 12. This cache sits at its high-water mark against a document
            // nobody is looking at exactly as long as the memory warning above never fires; purging on
            // backgrounding instead is the same `removeAll()`, correctness-neutral, paid back as one
            // cache-cold flatten the next time each cel is touched.
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.removeAll()
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

    private static func rasterizeUncached(cel: Cel, canvasSize: CGSize, quality: RenderQuality,
                                          derived: DerivedCelContent? = nil) -> UIImage {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let strokesImage = cel.raster.renderToUIImage()
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
        let vectorImage = derived?.render(quality) ?? cel.vector?.render(quality: quality)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { _ in
            cel.bakedImage?.draw(in: bounds)
            strokesImage.draw(in: bounds)
            vectorImage?.draw(in: bounds)
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
            cel.fillImage?.draw(in: bounds)
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

    /// Renders a floating piece (with its live transform applied) into a canvas-sized image, ready
    /// to be composited over a target cel's baked image at commit time.
    static func render(floatingPiece piece: FloatingPiece, into canvasSize: CGSize) -> UIImage {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
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

    /// Flattens two canvas-sized layer images into one, each drawn at its own layer opacity — the
    /// pixel side of merging two layers together (see `CanvasManager.mergeLayers`).
    static func flatten(bottom: UIImage, bottomOpacity: Double, top: UIImage, topOpacity: Double, canvasSize: CGSize) -> UIImage {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: transparentFormat())
        return renderer.image { _ in
            bottom.draw(in: bounds, blendMode: .normal, alpha: CGFloat(bottomOpacity))
            top.draw(in: bounds, blendMode: .normal, alpha: CGFloat(topOpacity))
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
    static func contourPath(selected: [Bool], width: Int, height: Int) -> CGPath? {
        func isSelected(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return selected[y * width + x]
        }

        var edges: [IntPoint: IntPoint] = [:]
        for y in 0..<height {
            for x in 0..<width where isSelected(x, y) {
                if !isSelected(x, y - 1) { edges[IntPoint(x: x, y: y)] = IntPoint(x: x + 1, y: y) }
                if !isSelected(x + 1, y) { edges[IntPoint(x: x + 1, y: y)] = IntPoint(x: x + 1, y: y + 1) }
                if !isSelected(x, y + 1) { edges[IntPoint(x: x + 1, y: y + 1)] = IntPoint(x: x, y: y + 1) }
                if !isSelected(x - 1, y) { edges[IntPoint(x: x, y: y + 1)] = IntPoint(x: x, y: y) }
            }
        }
        guard !edges.isEmpty else { return nil }

        let path = CGMutablePath()
        var remaining = edges
        while let start = remaining.keys.first {
            var loop: [IntPoint] = [start]
            var current = start
            while let next = remaining.removeValue(forKey: current) {
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
