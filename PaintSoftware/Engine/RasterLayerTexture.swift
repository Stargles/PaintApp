import UIKit
import CoreGraphics

/// Anything `BrushStamper` can lay dabs onto.
///
/// Exists so a stroke can be stamped straight into a `CGContext` someone else owns, not only into a
/// `RasterLayerTexture` that owns its own bitmap. `VectorCanvas.renderLocalContent` needs this: it
/// used to allocate a whole throwaway canvas-sized `RasterLayerTexture` (~16 MB at 2048², ~64 MB at
/// 4000²) per visible vector layer per invalidation just to stamp into it and copy the result out.
/// A thin wrapper over the renderer's own context removes that allocation and copy while keeping
/// `BrushStamper` the single source of truth for how a stroke rasterizes.
protocol DabTarget: AnyObject {
    func beginStroke()
    func endStroke()
    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                     alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode)
}

/// Memoized radial gradients for round dabs, plus the drawing itself — the shared implementation
/// behind every `DabTarget`.
///
/// Building a dab gradient is not cheap: three `UIColor`s, three `.cgColor` bridges, a `CFArray`,
/// and a `CGGradient`. This used to happen once per dab, on the order of 100 allocations a second
/// while drawing.
///
/// **The key deliberately excludes `alpha`, and that is the whole reason the cache works.** `alpha`
/// is `brushOpacity × flow × opacityFraction(pressure)` times a per-position grain multiplier — a
/// different float on essentially every dab, since pressure varies continuously. Keying on it would
/// hit approximately never. Instead the entry is built at full alpha and the per-dab alpha is applied
/// by `CGContext.setAlpha`.
///
/// That substitution is exact, not an approximation: all three stops carry the *same* RGB and differ
/// only in alpha, so the gradient never interpolates colour. Baking `α` into the stops yields alpha
/// `α` across the core and `α·(1-s)` through the falloff; a full-alpha gradient under `setAlpha(α)`
/// yields the same two functions scaled by `α`. CG's global alpha multiplies *source* alpha, so this
/// holds for `.destinationOut` erasing as well as `.normal` painting. `BrushEngineLogicTests` pins
/// the resulting alpha profile so the equivalence can't silently drift.
///
/// What is left in the key — colour and hardness — is fixed for the duration of any one stroke, so
/// the steady-state hit rate is one miss per stroke and a hit for every dab after it.
///
/// **Not thread-safe, by design.** Each owner serializes access its own way: `RasterLayerTexture`
/// only touches its cache while holding its `NSLock`, and `CGContextDabTarget` is created and used
/// inside a single render call. Adding a lock here would put one on the hottest path in the app for
/// no benefit.
final class DabGradientCache {
    private var gradients: [Key: CGGradient] = [:]
    private(set) var hits = 0
    private(set) var misses = 0

    /// Ceiling on distinct cached gradients. Colour and hardness change at human speed (a palette
    /// tap, a slider drag), so this is never approached in normal drawing; it exists so something
    /// pathological — a rainbow brush stamping a new colour per dab — degrades to "rebuild
    /// sometimes" rather than growing a dictionary without bound. Eviction is a wholesale clear
    /// because there is no access-ordering worth maintaining at this size.
    private static let limit = 32

    private struct Key: Hashable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let coreFraction: CGFloat
    }

    /// Paints one round dab into `ctx`, at `point` in the context's current user space.
    func stamp(into ctx: CGContext, at point: CGPoint, radius: CGFloat, color: UIColor,
               alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, ignoredAlpha: CGFloat = 0
        // Contract: `color` is always an already-resolved color by the time it reaches getRed — see
        // Utilities/ColorConversion.swift. Every stamp arrives via `BrushStamper`, which is only
        // ever handed colors that have been through that resolution (the live brush color, or a
        // `CodableColor` rebuilt from components extracted the same way), so this reads a concrete,
        // non-dynamic color rather than one whose components depend on the ambient trait collection.
        color.getRed(&r, green: &g, blue: &b, alpha: &ignoredAlpha)
        let coreFraction = max(0, min(hardness, 1))
        guard let gradient = gradient(red: r, green: g, blue: b, coreFraction: coreFraction) else { return }

        ctx.saveGState()
        ctx.setBlendMode(blendMode)
        // The per-dab alpha, applied here rather than baked into the gradient's stops — see above for
        // why that is both equivalent and the thing that makes the cache work.
        ctx.setAlpha(alpha)
        // options: [] means nothing is painted beyond endRadius, so this only touches the disc under
        // the stamp — the incremental, O(stamp area) behavior that keeps drawing fast.
        ctx.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                               endCenter: point, endRadius: radius, options: [])
        ctx.restoreGState()
    }

    private func gradient(red: CGFloat, green: CGFloat, blue: CGFloat, coreFraction: CGFloat) -> CGGradient? {
        let key = Key(red: red, green: green, blue: blue, coreFraction: coreFraction)
        if let cached = gradients[key] {
            hits += 1
            return cached
        }
        misses += 1
        let colors = [
            UIColor(red: red, green: green, blue: blue, alpha: 1).cgColor,
            UIColor(red: red, green: green, blue: blue, alpha: 1).cgColor,
            UIColor(red: red, green: green, blue: blue, alpha: 0).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: PixelOps.deviceRGBColorSpace,
                                        colors: colors,
                                        locations: [0, coreFraction, 1]) else { return nil }
        if gradients.count >= Self.limit { gradients.removeAll(keepingCapacity: true) }
        gradients[key] = gradient
        return gradient
    }
}

/// A `DabTarget` that stamps into a `CGContext` it does not own — used by
/// `VectorCanvas.renderLocalContent` to stamp into a `UIGraphicsImageRenderer`'s own context.
///
/// Coordinates need no adjustment: a `UIGraphicsImageRenderer` context is already in UIKit top-left
/// space, which is exactly what `RasterLayerTexture.ensureContext()` flips its own bitmap to, so a
/// dab at a given canvas point lands on the same pixels either way.
///
/// `beginStroke`/`endStroke` are no-ops. They exist on `RasterLayerTexture` to maintain
/// `strokeCount`, which is display-only bookkeeping for a *persistent* texture; a render-local
/// context has no such state and nothing reads a stroke count off it.
final class CGContextDabTarget: DabTarget {
    private let ctx: CGContext
    private let gradients = DabGradientCache()

    /// Dabs actually rasterized (i.e. that passed the guard below) — read by `VectorCanvas` after a
    /// render to populate `lastRenderDabCount`. A skipped stamp does no gradient work, so it is
    /// correctly excluded: this counts cost, not calls.
    private(set) var dabCount = 0

    init(_ ctx: CGContext) { self.ctx = ctx }

    func beginStroke() {}
    func endStroke() {}

    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                     alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        guard radius > 0, alpha > 0 else { return }
        dabCount += 1
        gradients.stamp(into: ctx, at: point, radius: radius, color: color,
                        alpha: alpha, hardness: hardness, blendMode: blendMode)
    }
}

/// Persistent raster backing store for one cel's live brush strokes, at canvas-native resolution.
///
/// This replaces `PKDrawing`: instead of vector stroke geometry re-rasterized at whatever zoom is
/// current (PencilKit strokes stay vector-smooth at any magnification, unlike this app's other
/// raster tiers, which caused an ink-blurs-when-zoomed bug — see BUGS.md), every stamp is rasterized
/// once, directly, at native canvas resolution. Zooming in is then a plain nearest-neighbor pixel
/// zoom, same as `fillImage`/`bakedImage`.
///
/// IMPLEMENTATION: a persistent CoreGraphics bitmap context that each stamp draws into
/// *incrementally* — only the pixels under the stamp are touched (O(stamp area)), the whole canvas
/// is never re-rendered per stamp. The context is created lazily (a blank cel holds no bitmap) and
/// flipped to UIKit top-left coordinates so its output `UIImage` matches everything else the app
/// produces via `UIGraphicsImageRenderer`, keeping FloodFillEngine/PixelOps/persistence unchanged
/// against `Cel.raster`.
///
/// PERFORMANCE: stamping is O(stamp area) on the CPU. The remaining cost is `renderToUIImage()`
/// doing an O(canvas) `makeImage()` when a fresh image is actually needed — cached per `version` so
/// it happens at most once per change, not once per stamp. The public API here (`renderToUIImage`,
/// `stamp`, `beginStroke`/`endStroke`, `makeCopy`, `flipped`, `reset`/`clear`) is the seam every
/// other piece of the engine depends on — keep it stable even if the internals move to GPU.
final class RasterLayerTexture: DabTarget {
    let size: CGSize
    let pixelWidth: Int
    let pixelHeight: Int
    private(set) var version: Int = 0
    private(set) var strokeCount: Int
    private var isMidStroke = false

    /// The persistent bitmap. `nil` means "fully transparent, nothing drawn yet" — created on the
    /// first stamp or the first time content is loaded, so blank cels are free.
    private var context: CGContext?
    /// Memoized `renderToUIImage()` result, invalidated (set to nil) on every mutation via `version`.
    private var cachedImage: UIImage?

    /// Guards `context`/`cachedImage`. Live strokes call `stampCircle` on the main thread, but a
    /// fill's reference composite (`CanvasManager.performFill`) reads a reference layer's texture via
    /// `renderToUIImage()` on a background queue — without this a stroke landing on that layer mid-
    /// fill could mutate the `CGContext` while the background thread concurrently calls `makeImage()`
    /// on it. `ensureContext()`/`setContents()` are internal helpers only ever called from a method
    /// that already holds this lock, so they don't lock themselves — this lock is non-reentrant.
    private let lock = NSLock()

    /// Thread-safe check of whether this texture has any backing bitmap at all, used by `makeCopy`/
    /// `flipped`/`resized` to skip work for a still-blank texture without racing `context` directly,
    /// and by the save (`ProjectStore.SaveSnapshot.CelContent`) to decide whether a cel's raster tier
    /// is worth a PNG at all.
    ///
    /// **This is a question about the bitmap existing, never about the pixels in it, and the
    /// asymmetry is the whole safety argument.** `context` is the only pixel store on this class
    /// (`cachedImage` is derived from it and never written into), it is created in exactly one place
    /// (`ensureContext`), and the only thing that ever puts it back to nil is
    /// `releaseBitmapIfFullyTransparent()` below, which proves transparency byte by byte first. So
    /// `false` here means "no pixels" *by construction* rather than by convention — the direction
    /// that cannot lose artwork. The converse is deliberately not claimed: an allocated context
    /// holding nothing but transparent pixels reports `true`, and a save conservatively writes it.
    var hasContent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return context != nil
    }

    /// Drops the backing bitmap if — and only if — an exact scan proves every pixel's alpha is zero,
    /// answering whether it did. Returns false without touching anything when there is no bitmap or
    /// any pixel is non-transparent.
    ///
    /// **This exists for one caller: `ProjectStore.decodeCel` healing a legacy package.** Packages
    /// written before the save learned to omit a blank cel's PNG carry a canvas-sized fully
    /// transparent `_raster.png` for every cel. Loading one materialises a 16 MiB `CGContext` at the
    /// owner's 2048², and — because the save writes back whatever the texture holds — the project
    /// would go on paying for it on every save forever. Healing it at the moment of decode is what
    /// lets an existing document become cheap without the artist doing anything.
    ///
    /// **Exact, with an early exit, and never a downsample.** A single opaque pixel anywhere in a
    /// 2048² image has to survive, and a scaled or thumbnailed check would average it away — so this
    /// walks the context's own bytes, which are a known format (`premultipliedLast`, 8 bits per
    /// component), and returns the moment it sees a non-zero alpha.
    ///
    /// The row-at-a-time `memcmp` is a *fast path only, and it can never be the thing that decides
    /// artwork is absent*: a row of all-zero bytes has all-zero alphas, so it is skipped; any row that
    /// differs from zero for any reason falls through to the per-pixel alpha loop, which is the actual
    /// answer. That keeps the scan exact while making the common case one `memcmp` per row rather than
    /// four million bounds-checked subscripts.
    ///
    /// **Safe to nil `context` only because of when it is called.** Everywhere else in this class the
    /// nil→non-nil transition is one-way, and code elsewhere leans on that. Here the texture was built
    /// moments ago inside `decodeCel`, nothing else has a reference to it yet, and the scan has just
    /// proved there is nothing to lose.
    @discardableResult
    func releaseBitmapIfFullyTransparent() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let ctx = context, let base = ctx.data else { return false }
        let bytesPerRow = ctx.bytesPerRow
        let width = ctx.width, height = ctx.height
        let rowBytes = width * 4
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let zeroRow = [UInt8](repeating: 0, count: rowBytes)
        for row in 0..<height {
            let rowStart = bytes + row * bytesPerRow
            let allZero = zeroRow.withUnsafeBytes { memcmp(rowStart, $0.baseAddress!, rowBytes) == 0 }
            if allZero { continue }
            // `premultipliedLast` puts alpha in the 4th byte of each pixel — see `Self.bitmapInfo`.
            for column in 0..<width where rowStart[column * 4 + 3] != 0 {
                return false
            }
        }
        context = nil
        cachedImage = nil
        return true
    }

    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    init(size: CGSize, image: UIImage? = nil, strokeCount: Int = 0) {
        let clamped = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        self.size = clamped
        self.pixelWidth = Int(clamped.width.rounded())
        self.pixelHeight = Int(clamped.height.rounded())
        self.strokeCount = strokeCount
        if image != nil { setContents(image) }
    }

    static func empty(size: CGSize) -> RasterLayerTexture {
        RasterLayerTexture(size: size)
    }

    /// Wraps already-rendered content (e.g. loaded from a saved project's PNG), at canvas-native
    /// resolution. `strokeCount` is a display-only heuristic here — a flattened bitmap can't
    /// recover the original stroke count — callers pass 1 for non-empty content, 0 for empty.
    static func load(from image: UIImage, size: CGSize, strokeCount: Int = 1) -> RasterLayerTexture {
        RasterLayerTexture(size: size, image: image, strokeCount: strokeCount)
    }

    // MARK: - Backing context

    private func ensureContext() -> CGContext? {
        if let context { return context }
        guard let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: PixelOps.deviceRGBColorSpace, bitmapInfo: Self.bitmapInfo) else { return nil }
        // Flip to UIKit top-left coordinates: input points are in canvas point space (y-down,
        // top-left origin), and this also makes `makeImage()` produce a UIImage whose orientation
        // matches `UIGraphicsImageRenderer` output — the convention every other image in the app
        // already uses, so downstream pixel reads (FloodFillEngine/PixelOps) stay consistent.
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: 1, y: -1)
        context = ctx
        return ctx
    }

    /// Replaces the entire bitmap with `image`'s pixels (or clears to transparent when nil). Used
    /// by load and by undo/redo restoring a snapshot — not on the per-stamp hot path.
    private func setContents(_ image: UIImage?) {
        let full = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        guard let image else {
            context?.clear(full)
            return
        }
        guard let ctx = ensureContext() else { return }
        ctx.clear(full)
        // ctx is flipped to top-left, so UIImage.draw composites right-side up.
        UIGraphicsPushContext(ctx)
        image.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
    }

    // MARK: - Reading

    /// The current pixel content, or a fully transparent canvas-sized image if nothing's been
    /// drawn yet. Always at native resolution (scale 1) — callers that need a smaller render
    /// (thumbnails) downscale this themselves, same as the existing `fillImage`/`bakedImage` path.
    func renderToUIImage() -> UIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cachedImage { return cachedImage }
        let image: UIImage
        if let context, let cg = context.makeImage() {
            image = UIImage(cgImage: cg, scale: 1, orientation: .up)
        } else {
            image = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in }
        }
        cachedImage = image
        return image
    }

    /// An independent duplicate: same pixels and stroke count, but its own identity, so drawing
    /// into one instance never affects the other. Needed anywhere a `Cel` used to rely on
    /// `PKDrawing`'s value semantics (duplicating/splitting a cel) — this is a class, not a struct,
    /// for the mutable-persistent-buffer performance reasons described above, so those call sites
    /// now need an explicit copy instead of getting one for free. A blank texture copies for free.
    func makeCopy() -> RasterLayerTexture {
        guard hasContent else { return RasterLayerTexture(size: size, strokeCount: strokeCount) }
        return RasterLayerTexture(size: size, image: renderToUIImage(), strokeCount: strokeCount)
    }

    /// The single implementation of canvas-flip geometry: `image` mirrored about the centre of a
    /// `canvasSize` canvas. A canvas flip has to move all three raster tiers — this texture (the
    /// live-stroke tier) plus the cel's `fillImage` and `bakedImage` — in exact lockstep, or content
    /// lands on the wrong side of the canvas relative to the rest. Both `flipped(horizontal:)` below
    /// and `CanvasManager.flipCanvas` route through here so there is only one translate+scale to keep
    /// in step. Infrequent (whole-canvas op), so it renders through `UIGraphicsImageRenderer` rather
    /// than the incremental path.
    static func flippedImage(_ image: UIImage, canvasSize: CGSize, horizontal: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            if horizontal {
                ctx.cgContext.translateBy(x: canvasSize.width, y: 0)
                ctx.cgContext.scaleBy(x: -1, y: 1)
            } else {
                ctx.cgContext.translateBy(x: 0, y: canvasSize.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
            }
            image.draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }

    /// A new instance with this texture's pixels flipped about the canvas center.
    func flipped(horizontal: Bool) -> RasterLayerTexture {
        guard hasContent else { return RasterLayerTexture(size: size, strokeCount: strokeCount) }
        let flipped = Self.flippedImage(renderToUIImage(), canvasSize: size, horizontal: horizontal)
        return RasterLayerTexture(size: size, image: flipped, strokeCount: strokeCount)
    }

    /// A new instance sized to `newSize` with this texture's pixels re-placed at `offset` (canvas
    /// point space), used by the canvas-padding resize (see `CanvasManager.setCanvasPadding`): growing
    /// the padding shifts existing content by a positive offset so it stays centred; shrinking uses a
    /// negative offset, cropping whatever falls outside the new bounds. A blank texture (no backing
    /// bitmap yet) stays blank and free — no bitmap is allocated. Infrequent whole-canvas op, so it
    /// renders through `UIGraphicsImageRenderer` rather than the incremental stamp path.
    func resized(to newSize: CGSize, offset: CGPoint) -> RasterLayerTexture {
        guard hasContent else { return RasterLayerTexture(size: newSize, strokeCount: strokeCount) }
        let current = renderToUIImage()
        let placed = UIGraphicsImageRenderer(size: newSize, format: PixelOps.transparentFormat()).image { _ in
            current.draw(in: CGRect(origin: offset, size: size))
        }
        return RasterLayerTexture(size: newSize, image: placed, strokeCount: strokeCount)
    }

    // MARK: - Stroke lifecycle (called by the drawing surface, e.g. StrokeCanvasView)

    func beginStroke() {
        isMidStroke = true
        lock.lock()
        _strokeDirtyRect = nil
        lock.unlock()
    }

    /// Union of every dab laid down since `beginStroke()`, in canvas point space, or nil if nothing
    /// has been stamped. This is what lets the undo system store a *crop* of the before/after state
    /// instead of two whole canvases — see `StrokeCanvasView.registerRasterUndo`.
    ///
    /// Deliberately only cleared by `beginStroke()`, never by `reset(to:)`. `StrokeCanvasView`'s
    /// selection-clipped path calls `reset` mid-stroke with a whole-canvas composite, but that
    /// composite is the pre-stroke image everywhere outside the clip, so the net change is still
    /// contained in this rect; clearing it there would lose the accumulated region and undo would
    /// leave pixels behind.
    var strokeDirtyRect: CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return _strokeDirtyRect
    }
    private var _strokeDirtyRect: CGRect?

    /// Stamps a single round dot at `point` (canvas point space) directly into the persistent
    /// bitmap — the one shared primitive every built-in brush shape stamps with today. Per-shape
    /// differentiation (square, textured/custom stamps) and grain modulation are layered on top of
    /// this by the brush engine (Worker B) and the real renderer (Worker A), not implemented here.
    ///
    /// - Parameters:
    ///   - color: the brush's pure color; any alpha on `color` itself is ignored in favor of `alpha`.
    ///   - alpha: effective per-stamp opacity (already folding in brush opacity/flow/pressure).
    ///   - hardness: 0...1, edge falloff — 0 is fully soft/feathered, 1 is a hard-edged disc.
    ///   - blendMode: `.normal` to paint, `.destinationOut` to erase (alpha controls erase strength).
    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode = .normal) {
        guard radius > 0, alpha > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let ctx = ensureContext() else { return }
        dabGradients.stamp(into: ctx, at: point, radius: radius, color: color,
                           alpha: alpha, hardness: hardness, blendMode: blendMode)
        // `options: []` on the radial gradient paints nothing past `radius`, so the dab's bounding
        // box is exactly this — no need to pad for spill.
        let dab = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        _strokeDirtyRect = _strokeDirtyRect?.union(dab) ?? dab
        cachedImage = nil
        version += 1
    }

    /// Restores the stroke count on its own, for undo/redo paths that put pixels back with
    /// `restore(patch:at:)` rather than replacing the whole bitmap through `reset(to:strokeCount:)`.
    /// `strokeCount` is a display-only count, but it has to travel with the pixels or the layer
    /// panel's "empty cel" state drifts out of step with what is actually drawn.
    func setStrokeCount(_ count: Int) {
        strokeCount = count
    }

    /// Writes `patch` back over the region starting at `origin`, replacing those pixels outright
    /// rather than compositing onto them. Undo/redo of a stroke uses this to put back just the
    /// region the stroke touched.
    ///
    /// `.copy` is essential, not a micro-optimisation: the patch carries alpha, and a source-over
    /// draw would leave any existing ink showing through the patch's transparent pixels — so undoing
    /// a stroke would fail to remove it. `.copy` makes the patch's alpha authoritative.
    func restore(patch: UIImage, at origin: CGPoint) {
        lock.lock()
        defer { lock.unlock() }
        guard let ctx = ensureContext() else { return }
        let rect = CGRect(origin: origin, size: patch.size)
        // ctx is flipped to top-left, so UIImage.draw lands right-side up (same as `setContents`).
        UIGraphicsPushContext(ctx)
        patch.draw(in: rect, blendMode: .copy, alpha: 1)
        UIGraphicsPopContext()
        cachedImage = nil
        version += 1
    }

    /// This texture's gradient cache. Only ever touched from a method already holding `lock`, which
    /// is what serializes it — see `DabGradientCache`, which is deliberately not thread-safe itself.
    private let dabGradients = DabGradientCache()

    /// Instrumentation for the gradient cache, read by `PerfBaselineTests`. The item that added the
    /// cache called for measuring the real hit rate rather than assuming one, and an unmeasured
    /// cache whose key silently stops matching is indistinguishable from no cache at all.
    var dabGradientCacheHits: Int { lock.lock(); defer { lock.unlock() }; return dabGradients.hits }
    var dabGradientCacheMisses: Int { lock.lock(); defer { lock.unlock() }; return dabGradients.misses }

    func endStroke() {
        guard isMidStroke else { return }
        isMidStroke = false
        strokeCount += 1
    }

    // MARK: - Undo / clear

    /// Replaces the content wholesale — used by undo/redo restoring a pre-stroke snapshot, and by
    /// `clear()`. `nil` resets to a fully transparent canvas.
    func reset(to image: UIImage?, strokeCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        setContents(image)
        self.strokeCount = strokeCount
        cachedImage = nil
        version += 1
    }

    func clear() {
        reset(to: nil, strokeCount: 0)
    }
}
