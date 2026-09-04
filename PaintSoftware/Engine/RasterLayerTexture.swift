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
///
/// **Two primitives, and no default implementation for either.** A tip is procedural or it is a
/// picture, and BRUSH.md §6's `BrushTip` makes exactly that split; a target that grew a default
/// `stampImage` would silently drop every square-brush dab, which is the failure this protocol is
/// shaped to make impossible to write by accident.
protocol DabTarget: AnyObject {
    func beginStroke()
    func endStroke()
    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                     alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode)

    /// **One oriented, tinted alpha stamp** — BRUSH.md §3.5's image primitive.
    ///
    /// - `texture` is *which mask*, and it is the cache key's content term. RENDER.md §3.8's trap is
    ///   three memos in this repo keyed on a buffer's size alone; naming the tip is what keeps
    ///   `DabImageCache` from being the fourth.
    /// - `diameter` is the side of the square the mask fills, before `angle` turns it — the same
    ///   number `stampCircle` receives halved, and the same number `stampApproximateSquare` took.
    ///   One scalar and not a `CGSize` because a tip's mask is square by ruling; see
    ///   `BuiltInBrushTexture`.
    /// - `angle` turns the mask about `point`, in radians, in the target's own y-down space — the
    ///   convention `CGContext.rotate(by:)` and `CGAffineTransform(rotationAngle:)` already use, and
    ///   the one `stampApproximateSquare`'s `cos`/`sin` lattice used before it. It is not optional
    ///   and not deferrable: `Brush.rotationJitter` drives it today and §6's direction-follow drives
    ///   it in stage 7.
    /// - `color`, `alpha` and `blendMode` mean exactly what they mean on `stampCircle`. There is no
    ///   `hardness`: a picture's edge is in its pixels, and hardness is the round tip's procedural
    ///   falloff.
    func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                    angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode)
}

/// The pixels an image dab of `diameter` turned by `angle` about `point` can touch.
///
/// The geometric half-extent on each axis is `(d/2)(|cos θ| + |sin θ|)` — exactly `d/2` unrotated
/// and `d·√2/2` at 45°, rather than the conservative `d·√2/2` everywhere. Shared, because the dirty
/// rect a stroke reports and the window a `StrokeScratch` grows both have to contain what the draw
/// actually painted, and two copies of this arithmetic are two chances for them not to.
///
/// **`resampleSpill` is why this is not just the geometry, and it is measured rather than assumed.**
/// `.high` interpolation reconstructs from a kernel wider than one texel, so CoreGraphics paints
/// past the quad's own edge. MEASURED over ten dab sizes × 24 angles, at a fractional centre, as the
/// furthest non-zero pixel beyond the exact bound: **2.39 px** at 16 pt, 2.38 at 40, 1.99 at 64,
/// 0.89 at 128 and 0.00 at 300 — worst where the tip is being *downscaled*, which is every dab an
/// artist actually draws. Three points covers it with the pixel-containment rounding on top.
///
/// A bound one pixel short is not a cosmetic error: `StrokeScratch` clips the stroke to its window,
/// so the dab would lose that edge outright, and `strokeDirtyRect` sizes the undo patch, so undo
/// would leave the edge behind on the canvas.
func dabImageBounds(at point: CGPoint, diameter: CGFloat, angle: CGFloat) -> CGRect {
    let resampleSpill: CGFloat = 3
    let half = diameter / 2 * (abs(cos(angle)) + abs(sin(angle))) + resampleSpill
    return CGRect(x: point.x - half, y: point.y - half, width: half * 2, height: half * 2)
}

/// **The dabs the render path actually put down** — `CompositeProbe` one level lower, for the same
/// reason and with the same shape.
///
/// A test that wants to know whether a posed frame's ink boils has exactly one honest operand: the
/// arguments `stampCircle` received while `VectorCanvas.renderLocalContent` was drawing. Everything
/// short of that is a re-derivation — a test-local copy of `VectorCanvas.stamp`'s dispatch pins the
/// copy, and `BrushStamper.DabPose.applied(to:)` copies `alpha` verbatim, so an assertion built on it
/// holds under an implementation that walks in posed space and re-derives per-dab alpha on every
/// frame instead of baking it once in rest space. KEYFRAMES.md §4.2 is a claim about which walk the
/// renderer runs, and this is where that claim is observable.
///
/// **Off by default and nearly free when off**: one relaxed `Bool` load per dab, after the guard that
/// already decides whether the dab costs a gradient at all. The lock is taken only while armed.
enum DabProbe {

    /// The four numbers a pose can move. `color`, `hardness` and `blendMode` are carried through
    /// untouched by every path here, so recording them would only make a failure harder to read.
    ///
    /// `angle` defaults to zero because a round dab is rotation-invariant and has none to record —
    /// it is what an image dab was turned by, and it is here for the same reason `radius` is: a pose
    /// changes it, so a test that wants to know whether a posed sprite stroke turns with the stroke
    /// has to be able to see it.
    struct Dab: Equatable {
        var center: CGPoint
        var radius: CGFloat
        var alpha: CGFloat
        var angle: CGFloat = 0
    }

    private static let lock = NSLock()
    /// Read outside the lock on the hot path. A stale read is harmless in both directions: the probe
    /// is armed before the render under test and read after it returns.
    private static var isArmed = false
    private static var dabs: [Dab] = []

    /// Starts recording, discarding anything held from a previous run.
    static func begin() {
        lock.lock(); defer { lock.unlock() }
        dabs = []
        isArmed = true
    }

    /// Stops recording and returns what was stamped, in draw order.
    @discardableResult
    static func end() -> [Dab] {
        lock.lock(); defer { lock.unlock() }
        isArmed = false
        let seen = dabs
        dabs = []
        return seen
    }

    /// Everything stamped since `begin()`, without stopping.
    static func observed() -> [Dab] {
        lock.lock(); defer { lock.unlock() }
        return dabs
    }

    fileprivate static func record(_ dab: Dab) {
        guard isArmed else { return }
        lock.lock(); defer { lock.unlock() }
        guard isArmed else { return }
        dabs.append(dab)
    }
}

/// Memoized radial gradients for round dabs, plus the drawing itself — the shared implementation
/// behind every `DabTarget`.
///
/// Building a dab gradient is not cheap: three `UIColor`s, three `.cgColor` bridges, a `CFArray`,
/// and a `CGGradient`. This used to happen once per dab, on the order of 100 allocations a second
/// while drawing.
///
/// **The key deliberately excludes `alpha`, and that is the whole reason the cache works.** `alpha`
/// is `brushOpacity × flow × opacityFraction(pressure)` — a different float on essentially every dab,
/// since pressure varies continuously. Keying on it would hit approximately never. Instead the entry
/// is built at full alpha and the per-dab alpha is applied by `CGContext.setAlpha`.
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

/// Memoized tinted tips for image dabs, plus the drawing itself — `DabGradientCache`'s twin, and
/// deliberately its twin down to which terms are in the key and which are applied at draw time.
///
/// Building a tinted stamp is a bitmap context, a draw, a `.sourceIn` fill and a `makeImage()` at
/// the *mask's* resolution, so it costs about the same whatever the dab it is for. MEASURED on
/// CoreGraphics with the 256² square tip, per dab, both arms at `.high`:
///
/// | dab | tint per dab + draw | cached, draw only | saved |
/// |---|---|---|---|
/// | 16 pt | 162.3 µs | 5.5 µs | 96.6% |
/// | 24 pt | 170.3 µs | 10.8 µs | 93.6% |
/// | 32 pt | 191.5 µs | 18.0 µs | 90.6% |
/// | 64 pt | 248.0 µs | 62.2 µs | 74.9% |
/// | 200 pt | 814.3 µs | 507.6 µs | 37.7% |
///
/// A 1000 pt stroke at the square preset's 15% spacing and 16 pt is ~417 dabs, so the cache is the
/// difference between 68 ms and 2.3 ms of stamping for one stroke — and a vector layer re-runs that
/// walk on every invalidation.
///
/// **The key names the tip, the colour and the dab's size *octave* — and not its angle.**
///
/// *Size is in, as a power of two, and the number that settled it was taken in the app rather than
/// in a microbenchmark.* An entry is built at the smallest power of two that covers the dab, so the
/// draw resamples by at most 2:1 and `.high` interpolation is cheap; a stroke's continuously varying
/// dab size still collapses to one entry, or two where it crosses an octave. A microbenchmark on
/// macOS CoreGraphics said this ladder was worth nothing — 5.89 vs 5.93 µs at a 16 pt dab, 624 vs
/// 623 at 200 — and **that measurement was misleading**, because macOS CG absorbs a large downscale
/// far more cheaply than the simulator's does. MEASURED in the app, over a 500-sample stroke with
/// the square preset, per dab:
///
/// | entry built at | µs / image dab | µs / round dab |
/// |---|---|---|
/// | the mask's native 256², `.high` | **76.3** | 5.6 |
/// | the mask's native 256², `.none` | 6.9 | 6.4 |
/// | **the power-of-two ladder, `.high`** | **14.2** | 6.7 |
///
/// So the ladder buys 5.4× and keeps the antialiasing that `.none` throws away. The one expensive
/// resample of the mask happens once per entry — i.e. once per stroke — instead of once per dab,
/// which is the whole of the difference. An image dab then costs about **2.1× a round one**, which
/// is what an oriented picture ought to cost against a radial gradient.
///
/// *Angle is out because bucketing it is worse on **both** counts, which refutes BRUSH.md §3.5's
/// "rotation-bucketed" as written.* On accuracy: a bucket's worst angular error is `π/N`, and the
/// corner of the largest dab the app allows sits `100·√2 = 141.4` px from its centre (the size
/// slider tops out at 200 pt and `RasterLayerTexture` is 1 px per canvas point), so holding that
/// corner inside half a pixel needs `N ≥ π·141.4/0.5 = 889` buckets. On cost, at any N at all:
/// MEASURED, a rotated-CTM draw of one cached entry beats a pre-rotated bucket blitted axis-aligned
/// at every size and every interpolation quality — 5.35 vs 122 µs at 16 pt and 485 vs 1082 at 200 pt
/// on `.high`, 4.75 vs 5.07 and 339 vs 431 on `.none`. A pre-rotated bucket has to be `√2` larger to
/// hold the turned square, so it covers twice the pixels, and N entries per colour also defeat
/// CoreGraphics' own per-image downsample cache. So the angle is applied by the CTM, exactly, and
/// stage 7's direction-follow inherits a primitive with no quantisation in it to remove.
///
/// **`alpha` is out for `DabGradientCache`'s reason, and it is exact for `DabGradientCache`'s
/// argument.** The entry is premultiplied colour × mask alpha; `CGContext.setAlpha` scales source
/// alpha, so drawing it at `α` yields `α · colour × mask`, which is what baking `α` into the entry
/// would have produced. It holds under `.destinationOut` too, where only the source alpha is read.
///
/// **Not thread-safe, by design** — the same contract `DabGradientCache` has, and the same owners.
final class DabImageCache {
    private var tinted: [Key: CGImage] = [:]
    private(set) var hits = 0
    private(set) var misses = 0

    /// Ceiling on distinct entries, as on `DabGradientCache` and for the same reason: tip, colour and
    /// size octave all change at human speed, so this is never approached, and something pathological
    /// degrades to "rebuild sometimes" rather than growing without bound. An entry is at most one
    /// 256² bitmap — 256 KB — so 32 of them is 8 MB at the ceiling, and one or two is the steady
    /// state for a stroke.
    private static let limit = 32

    /// The tip, the colour, and the entry's own pixel side. **The tip is in here because RENDER.md
    /// §3.8 says what happens when it is not**: `PixelOps.RasterizeKey`, `MaskResolver.CacheKey` and
    /// `MetalCompositor`'s `UploadCache.Key` are all keyed on a buffer's size *alone*, so two
    /// contents at one size collide and the second silently gets the first's pixels. This key has a
    /// size term too — and is not that bug, precisely because the size is not the whole key.
    /// `BrushTipLogicTests` pins that two different tips at one size are two entries.
    private struct Key: Hashable {
        let texture: BrushTextureRef
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let side: Int
    }

    /// The pixel side an entry is built at for a dab of `diameter`: the smallest power of two that
    /// is at least the dab's own size, capped at the mask's own resolution and floored at 8.
    ///
    /// **A power of two rather than the dab's exact size, because dab size varies per dab and an
    /// exact key would hit approximately never** — it is `brushSize × sizeFraction(pressure)`, which
    /// is the same continuously-varying quantity that keeps `alpha` out of `DabGradientCache`'s key.
    /// A power-of-two ladder collapses a stroke to one entry, or two where it crosses an octave.
    static func entrySide(forDiameter diameter: CGFloat, nativeSide: Int) -> Int {
        var side = 8
        while CGFloat(side) < diameter && side < nativeSide { side *= 2 }
        return min(side, max(nativeSide, 1))
    }

    /// Paints one image dab into `ctx`, at `point` in the context's current user space.
    ///
    /// A dab whose tip has no mask draws nothing — see `BrushTextureStore.mask(for:)` for why that
    /// is the honest answer rather than a substituted shape.
    func stamp(into ctx: CGContext, texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
               angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, ignoredAlpha: CGFloat = 0
        // Same contract as `DabGradientCache.stamp` — see there.
        color.getRed(&r, green: &g, blue: &b, alpha: &ignoredAlpha)
        guard let entry = entry(texture: texture, red: r, green: g, blue: b, diameter: diameter) else { return }

        ctx.saveGState()
        ctx.setBlendMode(blendMode)
        ctx.setAlpha(alpha)
        // `.high` and not `.low`: a tip is cached at its native size and a dab is usually far
        // smaller, and MEASURED, `.low` point-samples that downscale — a 16 pt dab from a 256² mask
        // comes back 255 across its whole edge, i.e. aliased, where `.high` gives 142 and 237. It
        // costs 8% at 16 pt and 19% at 200 pt, which is what a visible edge is worth.
        ctx.interpolationQuality = .high
        ctx.translateBy(x: point.x, y: point.y)
        ctx.rotate(by: angle)
        ctx.draw(entry, in: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter))
        ctx.restoreGState()
    }

    private func entry(texture: BrushTextureRef, red: CGFloat, green: CGFloat, blue: CGFloat,
                       diameter: CGFloat) -> CGImage? {
        // Probing needs the mask's resolution, and the store answers from a dictionary after the
        // first dab of the process — see `BrushTextureStore`, which is where the file read lives.
        guard let mask = BrushTextureStore.mask(for: texture), mask.width > 0 else { return nil }
        let side = Self.entrySide(forDiameter: diameter, nativeSide: mask.width)
        let key = Key(texture: texture, red: red, green: green, blue: blue, side: side)
        if let cached = tinted[key] {
            hits += 1
            return cached
        }
        misses += 1
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        // The mask's alpha becomes the destination's; `.sourceIn` then keeps that alpha and takes
        // the fill's colour, which is premultiplied colour × coverage — the entry, in one pass. The
        // one expensive resample of the mask happens here, once per stroke, rather than per dab.
        ctx.interpolationQuality = .high
        ctx.draw(mask, in: rect)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(UIColor(red: red, green: green, blue: blue, alpha: 1).cgColor)
        ctx.fill(rect)
        guard let image = ctx.makeImage() else { return nil }
        if tinted.count >= Self.limit { tinted.removeAll(keepingCapacity: true) }
        tinted[key] = image
        return image
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
    private let images = DabImageCache()

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
        DabProbe.record(DabProbe.Dab(center: point, radius: radius, alpha: alpha))
        gradients.stamp(into: ctx, at: point, radius: radius, color: color,
                        alpha: alpha, hardness: hardness, blendMode: blendMode)
    }

    func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                    angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
        guard diameter > 0, alpha > 0 else { return }
        dabCount += 1
        // `radius` is half the tip's side, so `DabProbe`'s two dab kinds report the same quantity:
        // the half-extent a pose scales.
        DabProbe.record(DabProbe.Dab(center: point, radius: diameter / 2, alpha: alpha, angle: angle))
        images.stamp(into: ctx, texture: texture, at: point, diameter: diameter, angle: angle,
                     color: color, alpha: alpha, blendMode: blendMode)
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

    /// Roughly what this texture retains, for `UndoHistory`'s byte-budgeted trimming — the
    /// `RasterLayerTexture` counterpart of `CanvasManager.approximateImageCost`, and the reason a
    /// whole-cel undo step stopped costing zero.
    ///
    /// **Zero for a blank texture, and that is the load-bearing half.** `context` is nil until the
    /// first stamp (see `ensureContext`), so a cel that has never been drawn on genuinely retains
    /// nothing whatever its canvas size claims — charging `pixelWidth × pixelHeight × 4` for one
    /// would make an empty document look like it was holding the budget. `hasContent` is the same
    /// question `makeCopy`, `flipped` and the save already ask, and it is deliberately conservative
    /// in the direction that matters: an allocated context full of transparent pixels reports true
    /// and is charged, which over-counts rather than losing a buffer that is really resident.
    ///
    /// `cachedImage` is not added on top. It is derived from `context` and dropped on every mutation,
    /// so counting it would charge a memoization that the next edit gives back anyway — the same
    /// reason `approximateImageCost` charges one image and not its `CGImage` plus its `UIImage`.
    var approximateCost: Int {
        hasContent ? pixelWidth * pixelHeight * 4 : 0
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

    /// What a tier with no bitmap renders to instead of a canvas-sized sheet of transparent pixels —
    /// `VectorCanvas.transparentPixel`'s pattern, one tier down, and for the same arithmetic.
    private static let transparentPixel = PixelOps.transparentImage(size: CGSize(width: 1, height: 1))

    /// The current pixel content, or a shared 1×1 transparent image when there is no bitmap. Always
    /// at native resolution (scale 1) — callers that need a smaller render (thumbnails) downscale
    /// this themselves, same as the existing `fillImage`/`bakedImage` path.
    ///
    /// **The blank answer is shared and memoises nothing, and that is the whole of it.** Every vector
    /// cel carries an empty raster tier, and this used to mint a canvas-sized transparent bitmap for
    /// each one and park it in `cachedImage`, which no budget bounds and no pressure hook evicts —
    /// 2.4 GB across 300 cels at 2048×1024, materialised for the whole document the moment
    /// `startThumbnailBackfill` walks it on open. Callers draw the result into a rect they already
    /// know, so a 1×1 stretched over that rect is pixel-for-pixel the same nothing.
    ///
    /// **A caller that reads the returned image's *size* must ask `hasContent` first**, which is what
    /// `PixelOps.rasterizeUncached` and `CanvasManager.commitInteractiveFill` now do — they were the
    /// only two, and both derived a canvas from this image rather than drawing into one.
    func renderToUIImage() -> UIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cachedImage { return cachedImage }
        guard let context, let cg = context.makeImage() else { return Self.transparentPixel }
        let image = UIImage(cgImage: cg, scale: 1, orientation: .up)
        cachedImage = image
        return image
    }

    /// `renderToUIImage()` for the display path, which can say "no image" in a way the drawing
    /// paths cannot — the exact twin of `VectorCanvas.renderIfNonEmpty()`, and for the same reason.
    /// A blank tier's image view is left holding nil rather than a canvas-sized sheet of
    /// transparency: Core Animation skips the layer's contents entirely, and — the point — the
    /// sheet is never minted. At 16383² that sheet is 1 GiB spent to show nothing.
    func renderIfNonEmpty() -> UIImage? {
        hasContent ? renderToUIImage() : nil
    }

    /// A copy of the pixels in `rect` (canvas point space), or nil when the rect is degenerate or
    /// off-canvas. A blank tier answers with a transparent patch of that size, which is what its
    /// pixels are.
    ///
    /// **Deliberately not memoized, and that is the whole reason this is not
    /// `PixelOps.copiedSubimage(of: renderToUIImage(), …)`.** `CGBitmapContextCreateImage` shares
    /// the context's buffer copy-on-write, so a full-canvas image left alive — which is exactly
    /// what `renderToUIImage`'s `cachedImage` memo does — makes the next stamp duplicate the whole
    /// canvas. Here the full image lives only for the length of the draw below and is gone before
    /// anything can write again, so the cost is the patch and nothing else.
    func copiedPatch(in rect: CGRect) -> UIImage? {
        let clamped = rect.integral.intersection(CGRect(origin: .zero, size: size))
        guard clamped.width >= 1, clamped.height >= 1 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let format = PixelOps.transparentFormat()
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: clamped.size, format: format).image { _ in
            guard let context, let cg = context.makeImage() else { return }
            UIImage(cgImage: cg, scale: 1, orientation: .up)
                .draw(at: CGPoint(x: -clamped.minX, y: -clamped.minY))
        }
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

    /// A new instance sized to `newSize` with this texture's whole extent re-placed into `content`
    /// (a rectangle in the *new* canvas's point space). Used by every canvas resize —
    /// `CanvasManager.setCanvasPadding` and `CanvasManager.resizeCanvas(to:mode:)`, which both
    /// go through `CanvasResizeMap.contentRect`. A blank texture (no backing bitmap yet) stays blank
    /// and free — no bitmap is allocated. Infrequent whole-canvas op, so it renders through
    /// `UIGraphicsImageRenderer` rather than the incremental stamp path.
    ///
    /// **A rectangle rather than the `offset: CGPoint` this took until CANVAS_RESIZE.md stage 1**, and
    /// that one widened parameter is the whole of the raster side of the scale mode (§2). Crop/expand
    /// passes `CGRect(origin: d, size: size)` and is byte-identical to the old behaviour: the draw
    /// rect is the source's own size, so nothing resamples. A scale passes a rect of a different size,
    /// and only then is `interpolationQuality` raised — the app otherwise sets that property exactly
    /// once, to `.none` (`CanvasManager+Fill`), and a whole-document one-shot resample is worth the
    /// milliseconds. Setting it unconditionally would change the bytes the crop/expand path produces,
    /// which is the one thing that must not move here.
    func resized(to newSize: CGSize, placing content: CGRect) -> RasterLayerTexture {
        guard hasContent else { return RasterLayerTexture(size: newSize, strokeCount: strokeCount) }
        let current = renderToUIImage()
        let resamples = content.size != size
        let placed = UIGraphicsImageRenderer(size: newSize, format: PixelOps.transparentFormat()).image { ctx in
            if resamples { ctx.cgContext.interpolationQuality = .high }
            current.draw(in: content)
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
    /// bitmap — the procedural half of the pair, `stampImage` below being the other.
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

    /// Stamps one oriented, tinted alpha stamp — `stampCircle`'s twin, and the same bookkeeping.
    func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                    angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
        guard diameter > 0, alpha > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let ctx = ensureContext() else { return }
        dabImages.stamp(into: ctx, texture: texture, at: point, diameter: diameter, angle: angle,
                        color: color, alpha: alpha, blendMode: blendMode)
        let dab = dabImageBounds(at: point, diameter: diameter, angle: angle)
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

    /// Composites `patch` over the region starting at `origin`, source-over, leaving what is already
    /// there showing through the patch's transparent pixels. The twin of `restore(patch:at:)` above
    /// and chosen by `StrokeScratch.commit(into:)`: a paint stroke's scratch holds only the stroke's
    /// own ink, and source-over is associative, so drawing it here is pixel-identical to having
    /// stamped every dab straight into this texture.
    func composite(patch: UIImage, at origin: CGPoint) {
        lock.lock()
        defer { lock.unlock() }
        guard let ctx = ensureContext() else { return }
        // ctx is flipped to top-left, so UIImage.draw lands right-side up (same as `setContents`).
        UIGraphicsPushContext(ctx)
        patch.draw(in: CGRect(origin: origin, size: patch.size))
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

    /// This texture's tinted-tip cache, on the same contract as `dabGradients` above.
    private let dabImages = DabImageCache()

    /// Instrumentation for the tinted-tip cache, read by `PerfBaselineTests`. It is worth strictly
    /// more than the gradient cache's: a tinted entry costs a whole bitmap build, MEASURED at 96.6%
    /// of a 16 pt image dab's total cost, so a key that stops matching is not a slow path but a
    /// different program.
    var dabImageCacheHits: Int { lock.lock(); defer { lock.unlock() }; return dabImages.hits }
    var dabImageCacheMisses: Int { lock.lock(); defer { lock.unlock() }; return dabImages.misses }

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
