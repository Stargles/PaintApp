import UIKit
import CoreGraphics

/// Persistent raster backing store for one cel's live brush strokes, at canvas-native resolution.
///
/// This replaces `PKDrawing`: instead of vector stroke geometry re-rasterized at whatever zoom
/// happens to be current — the confirmed, unfixable source of this app's ink-blurs-when-zoomed
/// bug, since PencilKit strokes stay vector-smooth at any magnification unlike the app's other
/// raster tiers (see BUGS.md, 2026-07-21) — every stamp is rasterized once, directly, at native
/// canvas resolution. Zooming in on the result is then a plain nearest-neighbor pixel zoom, the
/// same fix already applied to `fillImage`/`bakedImage`.
///
/// IMPLEMENTATION: a persistent CoreGraphics bitmap context that each stamp draws into
/// *incrementally* — only the pixels under the stamp are touched (O(stamp area)), the whole canvas
/// is never re-rendered per stamp. The context is created lazily (a blank cel holds no bitmap and
/// costs no memory) and flipped to UIKit top-left coordinates so its output `UIImage` is
/// orientation-identical to everything the rest of the app produces via `UIGraphicsImageRenderer`
/// (fill/baked/thumbnail), which is what keeps FloodFillEngine/PixelOps/persistence working
/// unchanged against `Cel.raster`.
///
/// PERFORMANCE NOTE: stamping is now O(stamp area) on the CPU, which is fine for real drawing. The
/// remaining cost is `renderToUIImage()` doing an O(canvas) `makeImage()` when a fresh image is
/// actually needed (a display refresh, a thumbnail, a fill reference) — cached per `version` so it
/// happens at most once per change, not once per stamp. Replacing this whole store with a
/// persistent `MTLTexture` + GPU-batched stamping (keeping this exact public API so no caller
/// changes) is Worker A's deliverable: it eliminates even that per-frame CPU copy by letting the
/// GPU draw the texture directly. The public API here (`renderToUIImage`, `stamp`, `beginStroke`/
/// `endStroke`, `makeCopy`, `flipped`, `reset`/`clear`) is the seam every other piece of the engine
/// and the rest of the app depends on — keep it stable even as the internals change.
final class RasterLayerTexture {
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
    /// `renderToUIImage()` on a background queue — without this, a stroke landing on that layer mid-
    /// fill could mutate the `CGContext` while the background thread is concurrently calling
    /// `makeImage()` on it (see BUGS.md). `ensureContext()`/`setContents()` are internal helpers only
    /// ever called from a method that already holds this lock (or, for `setContents` from `init`,
    /// before the instance is shared with any other thread), so they don't lock themselves —
    /// otherwise this non-reentrant lock would deadlock.
    private let lock = NSLock()

    /// Thread-safe check of whether this texture has any backing bitmap at all, used by `makeCopy`/
    /// `flipped`/`resized` to skip work for a still-blank texture without racing `context` directly.
    private var hasContent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return context != nil
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
    }

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
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, ignoredAlpha: CGFloat = 0
        // Contract: `color` is always an already-resolved color by the time it reaches getRed — see
        // Utilities/ColorConversion.swift. Every stamp arrives via `BrushStamper`, which is only
        // ever handed colors that have been through that resolution (the live brush color, or a
        // `CodableColor` rebuilt from components extracted the same way), so this reads a concrete,
        // non-dynamic color rather than one whose components depend on the ambient trait collection.
        color.getRed(&r, green: &g, blue: &b, alpha: &ignoredAlpha)
        let coreFraction = max(0, min(hardness, 1))
        guard let gradient = dabGradient(red: r, green: g, blue: b, coreFraction: coreFraction) else { return }

        ctx.saveGState()
        ctx.setBlendMode(blendMode)
        // The per-dab alpha, applied here rather than baked into the gradient's stops — see
        // `dabGradient` for why that is both equivalent and the thing that makes the cache work.
        ctx.setAlpha(alpha)
        // options: [] means nothing is painted beyond endRadius, so this only touches the disc under
        // the stamp — the incremental, O(stamp area) behavior that keeps drawing fast.
        ctx.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [])
        ctx.restoreGState()
        cachedImage = nil
        version += 1
    }

    /// Memoized radial gradients for `stampCircle`, keyed by everything the gradient's *shape*
    /// depends on. Building one is not cheap — three `UIColor`s, three `.cgColor` bridges, a
    /// `CFArray`, and a `CGGradient` — and `stampCircle` used to build a fresh one for every dab,
    /// which is on the order of 100 allocations a second while drawing.
    ///
    /// **The key deliberately excludes `alpha`, and that is the whole reason the cache works.**
    /// `alpha` reaches `stampCircle` from `BrushStamper.stampDab` as
    /// `brushOpacity × flow × opacityFraction(pressure)`, times a per-position grain multiplier for
    /// a pencil — i.e. a different float on essentially every dab, since pressure varies
    /// continuously along a stroke. Keying on it would hit approximately never. Instead the entry
    /// is built at full alpha and the per-dab alpha is applied by `CGContext.setAlpha`.
    ///
    /// That substitution is exact, not an approximation. All three stops carry the *same* RGB and
    /// differ only in alpha, so the gradient never interpolates color — under either premultiplied
    /// or unpremultiplied interpolation the result is constant RGB with linearly interpolated
    /// alpha. Baking `α` into the stops yields alpha `α` across the core and `α·(1-s)` through the
    /// falloff; a full-alpha gradient under `setAlpha(α)` yields `1` and `1·(1-s)` scaled by `α` —
    /// the same two functions. CG's global alpha multiplies *source* alpha, so this holds for
    /// `.destinationOut` erasing (`dst·(1 - src_a·α)`) as well as for `.normal` painting.
    ///
    /// What is left in the key — color and hardness — is fixed for the entire duration of any one
    /// stroke, so the steady-state hit rate is one miss per stroke and a hit for every dab after it.
    private var dabGradients: [DabGradientKey: CGGradient] = [:]

    /// Instrumentation for the gradient cache, read by `PerfBaselineTests`. The item that added the
    /// cache called for measuring the real hit rate rather than assuming one, and an unmeasured
    /// cache whose key silently stops matching is indistinguishable from no cache at all.
    private(set) var dabGradientCacheHits = 0
    private(set) var dabGradientCacheMisses = 0

    private struct DabGradientKey: Hashable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let coreFraction: CGFloat
    }

    /// Ceiling on distinct cached gradients. Colour and hardness change at human speed (a palette
    /// tap, a slider drag), so this is never approached in normal drawing; it exists so that
    /// something pathological — a rainbow brush stamping a new colour per dab — degrades to
    /// "rebuild sometimes" rather than growing a dictionary without bound. Eviction is a wholesale
    /// clear because there is no access-ordering worth maintaining at this size.
    private static let dabGradientCacheLimit = 32

    /// Caller must already hold `lock` — this touches `dabGradients` and the counters, and the lock
    /// is non-reentrant. Same convention as `ensureContext()`/`setContents()`.
    private func dabGradient(red: CGFloat, green: CGFloat, blue: CGFloat, coreFraction: CGFloat) -> CGGradient? {
        let key = DabGradientKey(red: red, green: green, blue: blue, coreFraction: coreFraction)
        if let cached = dabGradients[key] {
            dabGradientCacheHits += 1
            return cached
        }
        dabGradientCacheMisses += 1
        let colors = [
            UIColor(red: red, green: green, blue: blue, alpha: 1).cgColor,
            UIColor(red: red, green: green, blue: blue, alpha: 1).cgColor,
            UIColor(red: red, green: green, blue: blue, alpha: 0).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: PixelOps.deviceRGBColorSpace,
                                        colors: colors,
                                        locations: [0, coreFraction, 1]) else { return nil }
        if dabGradients.count >= Self.dabGradientCacheLimit { dabGradients.removeAll(keepingCapacity: true) }
        dabGradients[key] = gradient
        return gradient
    }

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
