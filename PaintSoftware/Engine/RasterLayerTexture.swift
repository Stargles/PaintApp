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
    /// The unscattered walk site; collectors use travel for positional tools. Pixel targets ignore it.
    func dabSite(at point: CGPoint, travel: CGPoint)
    func beginStroke()
    func endStroke()

    /// **BRUSH.md §2.11's stroke buffer, opened and closed round one stroke's whole walk.**
    ///
    /// Every dab between these two calls is laid down `.normal` at its own `flow`, into a surface of
    /// the stroke's own; `endStrokeGroup` merges that surface into the target **once**, at `opacity`
    /// and under `blendMode`. That is the whole of *"Opacity caps what the whole stroke can reach
    /// however often it crosses itself; Flow is what one stamp lays down."* — a stroke that crosses
    /// itself reaches `opacity` at the crossing and not `1 - (1 - opacity)²`, and an eraser at 50%
    /// takes away 50% wherever it went however many times it went there.
    ///
    /// **`blendMode` is the stroke's, not the dab's.** A `.multiply` brush blends against what is
    /// under the stroke rather than against its own overlaps, and `.destinationOut` — the eraser —
    /// makes the buffer a *coverage* map that is punched out in one operation.
    ///
    /// **No bounds are passed, and that is a refutation rather than an omission.** The obvious design
    /// hands the merge a conservative box derived from the samples and the brush; it cannot be made
    /// safe, because `ResponseCurve` deliberately does not clamp its output (an overshooting handle
    /// on a `size` row can exceed `Σ|amount|`), and a box that is too small does not cost memory, it
    /// **clips ink**. So the merge collects the dabs it is given, takes the union of the rectangles
    /// they actually painted, and opens its buffer over exactly that — exact by construction, on a
    /// posed walk as much as a rest one, with nothing to keep in step. The collection costs ~100
    /// bytes and one array append per dab against ~5.5 µs of drawing, which is under a part in five
    /// hundred.
    ///
    /// Groups do **not** nest, and they are not `beginStroke`/`endStroke`: those bracket a *gesture*
    /// on a persistent texture (`RasterLayerTexture.strokeCount`) and are deliberate no-ops on a
    /// `StrokeScratch`, because `VectorCanvas.applyPreview` runs several `stampStroke` calls into one
    /// scratch. A group per `stampStroke` call is exactly the right granularity there: the erase walk
    /// gets its own `.destinationOut` group and each restamp its own normal one.
    ///
    /// **`texture` is BRUSH.md §2.25's paper, and it rides the group because the group is the
    /// moment.** The owner's rule is that the texture *"uses the untextured brush as a transparency
    /// mask, then is scaled with opacity"* — so it multiplies into the finished buffer, in canvas
    /// coordinates, immediately before the one merge that applies the opacity. It is on this call
    /// rather than on a dab for exactly the reason `opacity` is: a per-dab texture would travel with
    /// the stroke, which is a sprite, which is the thing §2.4 deleted.
    func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings?)
    func endStrokeGroup()

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
    ///   and not deferrable: §6's `angle` output drives it — a base tilt, direction-follow and the
    ///   per-dab jitter, summed.
    /// - `color`, `alpha` and `blendMode` mean exactly what they mean on `stampCircle`. There is no
    ///   `hardness`: a picture's edge is in its pixels, and hardness is the round tip's procedural
    ///   falloff.
    func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                    angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode)
}

extension DabTarget {
    func dabSite(at point: CGPoint, travel: CGPoint) {}
}

/// The pixels an image dab of `diameter` turned by `angle` about `point` can touch.
///
/// The geometric half-extent on each axis is `(d/2)(|cos θ| + |sin θ|)` — exactly `d/2` unrotated
/// and `d·√2/2` at 45°, rather than the conservative `d·√2/2` everywhere. Shared, because the dirty
/// rect a stroke reports and the window a `StrokeScratch` grows both have to contain what the draw
/// actually painted, and two copies of this arithmetic are two chances for them not to.
///
/// **`resampleSpill` is why this is not just the geometry.** `.high` interpolation reconstructs from
/// a kernel wider than one texel and then covers whole pixels, so the painted box escapes the exact
/// rotated square. MEASURED **in the app** across six dab sizes × five angles at a fractional
/// centre, as the furthest painted pixel beyond the geometric bound: the geometry alone falls short
/// by up to **0.99 px**. `BrushTipLogicTests` takes that measurement and asserts containment with no
/// slack at all, so this constant is pinned rather than trusted.
///
/// **Three points is deliberately three times the measured worst, because the two ways to be wrong
/// are not symmetric.** Too large costs a slightly bigger undo patch and a slightly wider stroke
/// window. Too small deletes ink: `StrokeScratch` clips the stroke to its window, so the dab loses
/// that edge outright, and `strokeDirtyRect` sizes the undo patch, so undo leaves the edge behind on
/// the canvas.
///
/// (An earlier throwaway probe reported 2.39 px here and it was wrong — it compared the read-back's
/// y against an unflipped centre, so it measured the flip rather than the kernel. The number above
/// is the one the shipped test computes, on both axes, through the same read-back it asserts on.)
func dabImageBounds(at point: CGPoint, diameter: CGFloat, angle: CGFloat) -> CGRect {
    let resampleSpill: CGFloat = 3
    let half = diameter / 2 * (abs(cos(angle)) + abs(sin(angle))) + resampleSpill
    return CGRect(x: point.x - half, y: point.y - half, width: half * 2, height: half * 2)
}

/// The pixels one round dab can touch. `options: []` on the radial gradient paints nothing past
/// `radius`, so this is exact rather than padded — `dabImageBounds`' twin, and shared for the same
/// reason: the dirty rect a stroke reports, the window a `StrokeScratch` grows and the buffer
/// `beginStrokeGroup` merges through all have to contain what the draw actually painted.
func dabCircleBounds(at point: CGPoint, radius: CGFloat) -> CGRect {
    CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
}

/// **One stroke's dabs, held between `beginStrokeGroup` and `endStrokeGroup`** — the buffer
/// BRUSH.md §2.11 accepts, in the form that costs no pixels to decide how big it is.
///
/// `bounds` is the union of the rectangles the dabs will actually paint, so the merge's buffer is
/// exactly the stroke's own footprint and nothing is ever clipped. Every `DabTarget` that draws
/// pixels holds one of these while a group is open; the two that do not (`CollectingDabTarget`,
/// `PosedDabTarget`) have nothing to buffer.
struct StrokeGroupBuffer {
    /// What the whole stroke may reach — BRUSH.md §2.11's cap.
    let opacity: CGFloat
    /// How the finished stroke meets what is under it.
    let blendMode: CGBlendMode
    /// The paper it lays its ink through — BRUSH.md §2.25, nil for a brush with none.
    let texture: BrushTextureSettings?
    private(set) var dabs: [BrushStamper.BakedDab] = []
    /// Union of every dab's painted rectangle; `.null` while nothing has been laid.
    private(set) var bounds: CGRect = .null

    init(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings? = nil) {
        self.opacity = opacity
        self.blendMode = blendMode
        self.texture = texture
    }

    mutating func add(_ dab: BrushStamper.BakedDab, painting rect: CGRect) {
        dabs.append(dab)
        bounds = bounds.isNull ? rect : bounds.union(rect)
    }

    var isEmpty: Bool { dabs.isEmpty }
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
/// is the matrix's `flow` output — a different float on essentially every dab,
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
    /// The same three-stop radial falloff the gradient below draws, for positional brush fields.
    static func coverage(distanceFraction: CGFloat, hardness: CGFloat) -> CGFloat {
        guard distanceFraction < 1 else { return 0 }
        let core = min(1, max(0, hardness))
        return distanceFraction <= core ? 1 : (1 - distanceFraction) / (1 - core)
    }

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

    /// An editable texture's tip images are stroke workspace. Keeping them after lift would make
    /// this small per-stroke memo grow with the number of visited cels instead of the live window.
    func removeAll() { tinted.removeAll(keepingCapacity: true) }

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
    /// exact key would hit approximately never** — it is `brushSize × the matrix's size output`, which
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
/// space, which is exactly what `RasterSurface.allocate` flips its bitmap to, so a
/// dab at a given canvas point lands on the same pixels either way.
///
/// `beginStroke`/`endStroke` are no-ops. They exist on `RasterLayerTexture` to maintain
/// `strokeCount`, which is display-only bookkeeping for a *persistent* texture; a render-local
/// context has no such state and nothing reads a stroke count off it.
final class CGContextDabTarget: DabTarget {
    private let ctx: CGContext
    /// **Where this context's own `(0, 0)` sits in canvas points** — BRUSH.md §2.25's phase, and the
    /// whole of what "canvas-anchored" needs from a target.
    ///
    /// `.zero` for every caller today and the field is still not redundant: `VectorCanvas`'s render
    /// is 1:1 in the cel's own space, `BrushPreview` and `SizePreview` draw into a swatch whose
    /// origin is its own, and the number that distinguishes those two cases has to be *somewhere*.
    /// It is here rather than inferred, because a target that guessed would guess wrong the first
    /// time someone renders a strip (RENDER.md §3.8) or a tile.
    private let canvasOrigin: CGPoint
    private let gradients: DabGradientCache
    private let images: DabImageCache

    /// Dabs actually rasterized (i.e. that passed the guard below) — read by `VectorCanvas` after a
    /// render to populate `lastRenderDabCount`. A skipped stamp does no gradient work, so it is
    /// correctly excluded: this counts cost, not calls.
    private(set) var dabCount = 0

    init(_ ctx: CGContext, canvasOrigin: CGPoint = .zero,
         gradients: DabGradientCache = DabGradientCache(), images: DabImageCache = DabImageCache()) {
        self.ctx = ctx
        self.canvasOrigin = canvasOrigin
        self.gradients = gradients; self.images = images
    }

    func beginStroke() {}
    func endStroke() {}

    /// The stroke's own buffer while §2.11's group is open — see `DabTarget.beginStrokeGroup`.
    private var group: StrokeGroupBuffer?

    /// **What the group that closed most recently actually painted**, or `.null` if it painted
    /// nothing — `StrokeGroupBuffer.bounds` kept after the merge instead of thrown away with it.
    ///
    /// `VectorCanvas` reads this once per element to bound a region re-walk, and it has to be *this*
    /// number rather than one derived from the brush: BRUSH.md §12 stage 8 records that a
    /// conservative box built from `Brush.maximumDabExtent` was refuted during that stage and never
    /// shipped, because `ResponseCurve` does not clamp and so no static box is a bound. The union of
    /// the rectangles the dabs were actually handed is exact by construction, and the walk computes
    /// it anyway to size the merge's clip.
    ///
    /// **Independent of the clip in force**, which is what makes it usable as a cache: a dab is added
    /// to the group by geometry, not by whether CoreGraphics went on to paint any of it. So the value
    /// a *clipped* walk records is the same one a full walk would.
    ///
    /// Reset on `beginStrokeGroup` rather than only assigned on `endStrokeGroup`, so a caller that
    /// reads it after a draw that opened no group at all — `strokePolyline`, the `.preview` tier —
    /// gets `.null` rather than the previous stroke's answer.
    private(set) var lastGroupBounds: CGRect = .null

    func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings?) {
        group = StrokeGroupBuffer(opacity: opacity, blendMode: blendMode, texture: texture)
        lastGroupBounds = .null
    }

    /// One transparency layer over exactly the pixels the stroke painted, composited into the
    /// context under the group's own alpha and blend mode.
    ///
    /// CoreGraphics applies the global alpha, the blend mode and the clip **in force when the layer
    /// opened** to the finished layer as a whole, so this *is* the merge — there is no buffer to
    /// allocate here and nothing to composite by hand.
    func endStrokeGroup() {
        guard let group else { return }
        self.group = nil
        merge(group)
    }

    /// Shared by CGContext rendering and persistent/scratch pixel targets, preserving one native
    /// group renderer and their existing gradient/tip caches.
    func merge(_ group: StrokeGroupBuffer) {
        lastGroupBounds = group.bounds
        guard !group.isEmpty, !group.bounds.isNull else { return }
        ctx.saveGState()
        // **Integral, and that is not tidiness.** A clip on a fractional rectangle is antialiased, so
        // the group's outermost row of pixels would come out at partial coverage — MEASURED at
        // alpha 193 where 255 was drawn, which is ink lost at a seam rather than a rounding
        // difference. Rounded out to the pixel grid the clip lands between pixels and takes nothing.
        let clip = group.bounds.integral
        ctx.clip(to: clip)
        ctx.setAlpha(group.opacity)
        ctx.setBlendMode(group.blendMode)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for dab in group.dabs { draw(dab) }
        // **BRUSH.md §2.25, and this is the moment §2.4 said did not exist.** The layer now holds the
        // untextured stroke — every dab's flow, accumulated, and nothing else — which is exactly the
        // transparency mask the owner's rule names. Multiplying the paper in here and not one line
        // later is what makes the stroke's own opacity scale the *textured* result.
        BrushTextureMerge.apply(group.texture, into: ctx, over: clip, canvasOrigin: canvasOrigin)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func draw(_ dab: BrushStamper.BakedDab, into context: CGContext? = nil) {
        let ctx = context ?? self.ctx
        switch dab.tip {
        case .round(let hardness):
            gradients.stamp(into: ctx, at: dab.center, radius: dab.radius, color: dab.color,
                            alpha: dab.alpha, hardness: hardness, blendMode: dab.blendMode)
        case .image(let texture, let angle):
            images.stamp(into: ctx, texture: texture, at: dab.center, diameter: dab.radius * 2,
                         angle: angle, color: dab.color, alpha: dab.alpha, blendMode: dab.blendMode)
        }
    }

    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                     alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        guard radius > 0, alpha > 0 else { return }
        dabCount += 1
        DabProbe.record(DabProbe.Dab(center: point, radius: radius, alpha: alpha))
        let dab = BrushStamper.BakedDab(center: point, radius: radius, color: color, alpha: alpha,
                                        blendMode: blendMode, tip: .round(hardness: hardness))
        if group != nil {
            group?.add(dab, painting: dabCircleBounds(at: point, radius: radius))
            return
        }
        draw(dab)
    }

    func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                    angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
        guard diameter > 0, alpha > 0 else { return }
        dabCount += 1
        // `radius` is half the tip's side, so `DabProbe`'s two dab kinds report the same quantity:
        // the half-extent a pose scales.
        DabProbe.record(DabProbe.Dab(center: point, radius: diameter / 2, alpha: alpha, angle: angle))
        let dab = BrushStamper.BakedDab(center: point, radius: diameter / 2, color: color,
                                        alpha: alpha, blendMode: blendMode,
                                        tip: .image(texture, angle: angle))
        if group != nil {
            group?.add(dab, painting: dabImageBounds(at: point, diameter: diameter, angle: angle))
            return
        }
        draw(dab)
    }
}

/// Stable editable identity for one cel's raster tier. Immutable source versions survive eviction,
/// undo and asynchronous reads; admitted RGBA surfaces provide the mutable working window. Logical
/// content is independent of whether a context is currently resident, and unavailable input refuses.
final class RasterLayerTexture: DabTarget, RasterResidencyCandidate {
    typealias Failure = RasterResidency.Failure
    let size: CGSize
    let pixelWidth: Int
    let pixelHeight: Int
    let canvasOrigin: CGPoint
    let residency: RasterResidency
    let residencyID = UUID()
    private let lock = NSLock()
    private var surface: RasterSurface?
    private var source: RasterSource?
    private var logicalContent = false
    private var revision = 0
    private var count: Int
    private var isMidStroke = false
    private var group: StrokeGroupBuffer?
    private var dirty: CGRect?
    private var mutationFailure: Failure?
    private let dabGradients = DabGradientCache()
    private let dabImages = DabImageCache()
    private static let transparentPixel = PixelOps.transparentImage(size: CGSize(width: 1, height: 1))

    init(size: CGSize, source: RasterSource? = nil, strokeCount: Int = 0,
         canvasOrigin: CGPoint = .zero, residency: RasterResidency = .shared) {
        let clamped = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        self.size = clamped
        pixelWidth = Int(clamped.width.rounded())
        pixelHeight = Int(clamped.height.rounded())
        self.canvasOrigin = canvasOrigin
        self.residency = source?.residency ?? residency
        self.source = source
        logicalContent = source != nil
        count = strokeCount
    }

    static func empty(size: CGSize) -> RasterLayerTexture { RasterLayerTexture(size: size) }

    /// Captures foreign rendered pixels before a caller changes its document. Refusal leaves the
    /// caller's previous tier intact; construction can never silently turn paint into a blank tier.
    static func capturing(_ image: UIImage, size: CGSize, strokeCount: Int = 1,
                          canvasOrigin: CGPoint = .zero, using residency: RasterResidency = .shared)
        -> Result<RasterLayerTexture, Failure> {
        RasterSource.capture(image, using: residency).map {
            RasterLayerTexture(size: size, source: $0, strokeCount: strokeCount,
                               canvasOrigin: canvasOrigin, residency: residency)
        }
    }

    static func rendered(size: CGSize, canvasOrigin: CGPoint = .zero, using residency: RasterResidency = .shared,
                         drawing: (CGContext) -> Bool) -> Result<RasterLayerTexture, Failure> {
        RasterSurface.render(size: size, using: residency, drawing: drawing).map { surface in
            let texture = RasterLayerTexture(size: size, canvasOrigin: canvasOrigin, residency: residency)
            texture.surface = surface
            texture.logicalContent = true
            residency.register(texture)
            return texture
        }
    }

    var version: Int { lock.lock(); defer { lock.unlock() }; return revision }
    var strokeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return source?.isCertainlyTransparent == true ? 0 : count
    }

    /// Logical paint, independent of residency. Only an exact alpha proof can turn a protected PNG
    /// into blank; a missing context or an unavailable read can never do so.
    var hasContent: Bool {
        lock.lock(); defer { lock.unlock() }
        return logicalContent && source?.isCertainlyTransparent != true
    }

    /// Undo's logical retained cost does not become zero when a version moves to its backing file.
    var approximateCost: Int { hasContent ? pixelWidth * pixelHeight * 4 : 0 }
    var strokeDirtyRect: CGRect? { lock.lock(); defer { lock.unlock() }; return dirty }
    var lastMutationResult: Result<Void, Failure> {
        lock.lock(); defer { lock.unlock() }
        return mutationFailure.map(Result.failure) ?? .success(())
    }

    /// Freeze captures a version handle, never an all-document image walk. The image's provider owns
    /// its buffer if a caller extracts CGImage or gives it to Core Animation.
    func snapshot() -> RasterSource? {
        lock.lock(); defer { lock.unlock() }
        guard logicalContent, source?.isCertainlyTransparent != true else { return nil }
        if let source { return source }
        guard let surface else { preconditionFailure("A nonblank raster must own a surface or source") }
        let frozen = RasterSource.snapshot(of: surface, size: size)
        source = frozen
        return frozen
    }

    func renderToUIImage() -> Result<UIImage, Failure> {
        snapshot()?.resolveImage() ?? .success(Self.transparentPixel)
    }

    func renderIfNonEmpty() -> Result<UIImage?, Failure> {
        snapshot()?.resolveImage().map(Optional.some) ?? .success(nil)
    }

    /// Admission is outside the texture lock. No disk decode, checkpoint or eviction callback runs
    /// under a lock a background reader may need. Installation is fenced by the actual ink version.
    func prepareForEditing() -> Result<Void, Failure> {
        lock.lock()
        let expected = revision
        let held = surface
        let backing = source
        lock.unlock()
        let prepared: Result<RasterSurface, Failure>
        if let held {
            prepared = held.preparedForWrite(excluding: [residencyID])
        } else if let backing {
            // UIImage drawing can autorelease a native alias of this borrowed old version. Drain
            // that alias before returning the new owned context, rather than pinning every prior
            // undo landing until the surrounding event's pool ends.
            prepared = autoreleasepool {
                backing.resolveImage().flatMap { image in
                    RasterSurface.allocate(width: pixelWidth, height: pixelHeight,
                        using: residency, excluding: [residencyID]).flatMap { allocated in
                        allocated.mutate { context in
                            UIGraphicsPushContext(context)
                            image.draw(in: CGRect(origin: .zero, size: size))
                            UIGraphicsPopContext()
                        }.map { allocated }
                    }
                }
            }
        } else {
            prepared = RasterSurface.allocate(width: pixelWidth, height: pixelHeight,
                using: residency, excluding: [residencyID])
        }
        return prepared.flatMap { prepared in
            lock.lock()
            guard revision == expected else { lock.unlock(); return .failure(.writeNotAdmitted) }
            surface = prepared
            lock.unlock()
            residency.register(self)
            return .success(())
        }
    }

    private func mutate(_ body: (CGContext) -> Void) -> Result<Void, Failure> {
        prepareForEditing().flatMap { _ in
            lock.lock(); defer { lock.unlock() }
            guard let surface else { return .failure(.writeNotAdmitted) }
            return surface.mutate(body).map {
                source = nil
                logicalContent = true
                revision += 1
            }
        }
    }

    func copiedPatch(in rect: CGRect) -> Result<RasterSource?, Failure> {
        let clamped = rect.integral.intersection(CGRect(origin: .zero, size: size))
        guard clamped.width >= 1, clamped.height >= 1 else { return .success(nil) }
        return renderIfNonEmpty().flatMap { image in
            RasterSource.render(size: clamped.size, using: residency) { _ in
                if let image {
                    image.draw(at: CGPoint(x: -clamped.minX, y: -clamped.minY))
                }
                return true
            }.map(Optional.some)
        }
    }

    /// Undo prepares a complete private replacement first. Its history preflight can refuse while
    /// leaving both the live version and the history stacks unchanged; landing is metadata-only.
    func replacingPatch(with patch: RasterSource, at origin: CGPoint) -> Result<RasterSource?, Failure> {
        patch.resolveImage().flatMap { image in
            let prepared = makeCopy()
            return prepared.restore(patch: image, at: origin).map { prepared.snapshot() }
        }
    }

    /// A duplicate shares the immutable version and acquires its own editable surface on admission.
    func makeCopy() -> RasterLayerTexture {
        RasterLayerTexture(size: size, source: snapshot(), strokeCount: strokeCount,
                           canvasOrigin: canvasOrigin, residency: residency)
    }

    func flipped(horizontal: Bool) -> Result<RasterLayerTexture, Failure> {
        guard let source = snapshot() else {
            return .success(RasterLayerTexture(size: size, residency: residency))
        }
        return source.flipped(horizontal: horizontal).map {
            RasterLayerTexture(size: size, source: $0, strokeCount: strokeCount, residency: residency)
        }
    }

    func resized(to newSize: CGSize, placing content: CGRect) -> Result<RasterLayerTexture, Failure> {
        guard let source = snapshot() else {
            return .success(RasterLayerTexture(size: newSize, residency: residency))
        }
        return source.resized(to: newSize, placing: content).map {
            RasterLayerTexture(size: newSize, source: $0, strokeCount: strokeCount, residency: residency)
        }
    }

    func beginStroke() {
        lock.lock(); mutationFailure = nil; dirty = nil; lock.unlock()
        let admitted = prepareForEditing()
        lock.lock()
        if case .failure(let failure) = admitted { mutationFailure = failure }
        isMidStroke = true
        lock.unlock()
    }

    func endStroke() {
        lock.lock(); defer { lock.unlock() }
        guard isMidStroke else { return }
        isMidStroke = false
        if mutationFailure == nil, logicalContent { count += 1 }
        dabImages.removeAll()
    }

    func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings?) {
        lock.lock(); defer { lock.unlock() }
        group = StrokeGroupBuffer(opacity: opacity, blendMode: blendMode, texture: texture)
    }

    func endStrokeGroup() {
        lock.lock()
        let pending = group
        group = nil
        let failed = mutationFailure != nil
        lock.unlock()
        guard let pending, !failed, !pending.isEmpty, !pending.bounds.isNull else { return }
        let result = mutate { context in
            CGContextDabTarget(context, canvasOrigin: canvasOrigin, gradients: dabGradients, images: dabImages).merge(pending)
        }
        if case .failure(let failure) = result { noteFailure(failure) }
    }

    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat,
                     hardness: CGFloat, blendMode: CGBlendMode = .normal) {
        guard radius > 0, alpha > 0 else { return }
        stamp(BrushStamper.BakedDab(center: point, radius: radius, color: color, alpha: alpha,
              blendMode: blendMode, tip: .round(hardness: hardness)),
              bounds: dabCircleBounds(at: point, radius: radius))
    }

    func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                    angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
        guard diameter > 0, alpha > 0 else { return }
        stamp(BrushStamper.BakedDab(center: point, radius: diameter / 2, color: color, alpha: alpha,
              blendMode: blendMode, tip: .image(texture, angle: angle)),
              bounds: dabImageBounds(at: point, diameter: diameter, angle: angle))
    }

    private func stamp(_ dab: BrushStamper.BakedDab, bounds: CGRect) {
        lock.lock()
        guard mutationFailure == nil else { lock.unlock(); return }
        dirty = dirty?.union(bounds) ?? bounds
        if group != nil { group?.add(dab, painting: bounds); lock.unlock(); return }
        lock.unlock()
        let result = mutate { context in
            switch dab.tip {
            case .round(let hardness):
                dabGradients.stamp(into: context, at: dab.center, radius: dab.radius, color: dab.color,
                    alpha: dab.alpha, hardness: hardness, blendMode: dab.blendMode)
            case .image(let texture, let angle):
                dabImages.stamp(into: context, texture: texture, at: dab.center, diameter: dab.radius * 2,
                    angle: angle, color: dab.color, alpha: dab.alpha, blendMode: dab.blendMode)
            }
        }
        if case .failure(let failure) = result { noteFailure(failure) }
    }

    private func noteFailure(_ failure: Failure) { lock.lock(); mutationFailure = failure; lock.unlock() }
    func setStrokeCount(_ count: Int) { lock.lock(); self.count = count; lock.unlock() }

    func restore(patch: UIImage, at origin: CGPoint) -> Result<Void, Failure> {
        mutate { context in
            UIGraphicsPushContext(context)
            patch.draw(in: CGRect(origin: origin, size: patch.size), blendMode: .copy, alpha: 1)
            UIGraphicsPopContext()
        }
    }

    func composite(patch: UIImage, at origin: CGPoint, opacity: CGFloat = 1,
                   blendMode: CGBlendMode = .normal) -> Result<Void, Failure> {
        mutate { context in
            UIGraphicsPushContext(context)
            patch.draw(in: CGRect(origin: origin, size: patch.size), blendMode: blendMode, alpha: opacity)
            UIGraphicsPopContext()
        }
    }

    func erase(patch: UIImage, at origin: CGPoint, opacity: CGFloat) -> Result<Void, Failure> {
        mutate { context in
            UIGraphicsPushContext(context)
            patch.draw(in: CGRect(origin: origin, size: patch.size), blendMode: .destinationOut, alpha: opacity)
            UIGraphicsPopContext()
        }
    }

    func reset(toSource source: RasterSource?, strokeCount: Int) {
        lock.lock(); defer { lock.unlock() }
        self.source = source
        surface = nil
        logicalContent = source != nil
        count = strokeCount
        dabImages.removeAll()
        revision += 1
    }

    func clear() { reset(toSource: nil, strokeCount: 0) }

    @discardableResult
    func releaseBitmapIfFullyTransparent() -> Result<Bool, Failure> {
        renderToUIImage().map { _ in
            lock.lock(); defer { lock.unlock() }
            guard logicalContent,
                  source?.isCertainlyTransparent == true || surface?.isFullyTransparent == true else { return false }
            source = nil; surface = nil; logicalContent = false
            return true
        }
    }

    func releaseResidentPixels() -> Bool {
        guard lock.try() else { return false }
        guard !isMidStroke, let surface else { lock.unlock(); return false }
        if !logicalContent || source?.isCertainlyTransparent == true {
            self.surface = nil
            source = nil
            logicalContent = false
            lock.unlock()
            return true
        }
        if source == nil { source = RasterSource.snapshot(of: surface, size: size) }
        let source = self.source
        self.surface = nil
        lock.unlock()
        _ = source?.releaseResidentPixels()
        return true
    }

    var dabGradientCacheHits: Int { lock.lock(); defer { lock.unlock() }; return dabGradients.hits }
    var dabGradientCacheMisses: Int { lock.lock(); defer { lock.unlock() }; return dabGradients.misses }
    var dabImageCacheHits: Int { lock.lock(); defer { lock.unlock() }; return dabImages.hits }
    var dabImageCacheMisses: Int { lock.lock(); defer { lock.unlock() }; return dabImages.misses }
}
