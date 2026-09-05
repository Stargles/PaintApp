import UIKit
import CoreGraphics

/// **A brush's row in the menu is a stroke of that brush** — BRUSH.md §7.1.
///
/// *"A name tells an artist nothing about a brush and a swatch of its tip tells them little more."*
/// So this is a real `BrushStamper` walk, through the same `stampStroke` every tier funnels into,
/// over a fixed S-curve carrying a pressure ramp, into a `CGContextDabTarget` over a
/// `UIGraphicsImageRenderer` context. It is §12 stage 9's contact-sheet render at row size, which is
/// why it is here in `Engine` and not in the view that shows it.
enum BrushPreview {

    /// The stroke every preview draws: an S across the row with pressure ramping up and back down.
    ///
    /// **The shape is fixed and the pressure ramp is the point.** A straight line at constant
    /// pressure would render four of the five shipped presets as near-identical bars, because what
    /// separates them is how width and flow answer the pen — which is exactly what a ramp shows and a
    /// constant hides. The taper at both ends is what makes a `size ← pressure` row visible as a
    /// shape rather than as a number.
    ///
    /// Sampled at ~2 pt of arc, well under any brush's spacing, so the walk's own dab lattice decides
    /// where ink lands rather than this polyline's density (BRUSH.md §3.4 — the walk follows the
    /// curve, not the samples).
    static func samples(in size: CGSize) -> StrokeSamples {
        let inset = min(size.height * 0.42, size.width * 0.1)
        let x0 = inset
        let x1 = max(size.width - inset, inset + 1)
        let midY = size.height / 2
        let amplitude = max(size.height / 2 - inset, 0)

        let steps = max(Int((x1 - x0) / 2), 8)
        var points: [VectorSample] = []
        points.reserveCapacity(steps + 1)
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = x0 + (x1 - x0) * t
            // One full period of a sine is the S: down, up, back to the middle.
            let y = midY - sin(t * 2 * .pi) * amplitude
            // 0.08 at both ends, 1 in the middle — a press and a release, which is the gesture an
            // artist reads a brush by.
            let pressure = 0.08 + 0.92 * sin(t * .pi)
            points.append(VectorSample(point: CGPoint(x: x, y: y), pressure: pressure))
        }
        return StrokeSamples(points, channels: .pressureOnly)
    }

    /// How wide the preview stroke is drawn, in the row's own points.
    ///
    /// **Not the brush's own `size`, and not a constant either.** The brush's own is 4 pt for the Pen
    /// and 18 for Soft Round against a ~28 pt row: taken literally the Pen is a hairline and a
    /// 200 pt imported brush is one dab covering the row. A constant would be honest about neither.
    /// This is the brush's size clamped into the band the row can show, which is monotone — a fatter
    /// brush previews fatter — while keeping both ends legible.
    static func strokeWidth(for brush: Brush, in size: CGSize) -> CGFloat {
        let ceiling = max(size.height * 0.62, 2)
        return min(max(brush.size, 2), ceiling)
    }

    /// One preview image. Synchronous and self-contained: no document, no layer, no canvas.
    ///
    /// The seed is fixed so a brush's preview is a *function of the brush* — BRUSH.md §4's randomness
    /// is hashed by arc length rather than streamed, so one seed gives the same scatter and the same
    /// density dropout every time this is called, and a cache hit and a re-render are the same
    /// picture.
    static func render(_ brush: Brush, size: CGSize, scale: CGFloat, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            stampSample(into: CGContextDabTarget(context.cgContext), over: size, brush: brush,
                        color: color, strokeWidth: strokeWidth(for: brush, in: size),
                        opacity: brush.opacity)
        }
    }

    /// **The one sample stroke in the codebase, walked by both surfaces that show one** — a menu row
    /// (`render`, §7.1) and the editor pad's opening stroke (`BrushScratchPad`, §7.2).
    ///
    /// BRUSH.md §7.2: *"The default stroke must be the same fixed S-curve `BrushPreview` walks for
    /// §7.1's rows — one sample stroke in the codebase, not two, or a brush's row and its pad will
    /// disagree about what it looks like."*
    ///
    /// **Sharing `samples(in:)` alone would not have been enough**, which is why this exists rather
    /// than the pad calling `stampStroke` for itself: the *seed* is half of what makes a preview a
    /// function of the brush (§4's randomness is hashed by arc length, so one seed gives one scatter),
    /// and a pad whose dropout pattern differed from the row's would be the same disagreement one
    /// level down from the one the ruling names.
    ///
    /// `strokeWidth` and `opacity` are the caller's because they are the two numbers that legitimately
    /// differ: a row clamps the width into 26 points of band (`strokeWidth(for:in:)`) and the pad is
    /// **real size**, drawing at whatever the artist's own Size slider says.
    ///
    /// `offsetBy` moves the whole curve without reshaping it, which the pad needs and a row does not:
    /// `samples(in:)` fits the S to whatever extent it is handed, so a pad taller than it is wide
    /// turns the stroke into a vertical zigzag. The pad hands in a band of the curve's own
    /// proportions and offsets it to the middle — see `BrushScratchPad.stampRestingSample`.
    static func stampSample(into target: DabTarget, over size: CGSize, offsetBy offset: CGPoint = .zero,
                            brush: Brush, color: UIColor, strokeWidth: CGFloat, opacity: Double,
                            isEraser: Bool = false) {
        BrushStamper.stampStroke(into: target,
                                 samples: samples(in: size)
                                     .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y)),
                                 brush: brush,
                                 color: color,
                                 brushSize: strokeWidth,
                                 brushOpacity: opacity,
                                 isEraser: isEraser,
                                 random: DabRandom(seed: previewSeed))
    }

    /// Arbitrary and fixed — see `render`. Written down rather than 0 only so it is obvious in a
    /// diff that it is a constant and not a placeholder.
    static let previewSeed: UInt64 = 0x8B7A_5E11_0000_0001
}

/// What a cached preview is a preview *of*.
///
/// **The brush by value, which is BRUSH.md §7.1's "cache it by `BrushRef`" reached one step
/// earlier.** A `BrushRef` is `BrushPool`'s index for a brush *value*, so keying on the ref and
/// keying on the value are the same cache — except that minting a ref costs an entry in an
/// **append-only, process-wide** pool that never releases anything. A preview is rendered for a
/// brush the artist is merely *looking at*, and stage 10's editor will re-render on every tick of a
/// slider drag; interning each of those would grow the pool by hundreds of brushes nobody drew with.
/// `Brush` is `Hashable` over its whole value — the same hash `BrushPool` addresses by — so this
/// keeps the identity and drops the pool entry.
struct BrushPreviewKey: Hashable {
    let brush: Brush
    let width: Int
    let height: Int
    let scale: Int

    init(brush: Brush, size: CGSize, scale: CGFloat) {
        self.brush = brush
        // Rounded, so a row whose width jitters by a fraction of a point during layout is one entry
        // and not fifty.
        width = Int(size.width.rounded())
        height = Int(size.height.rounded())
        self.scale = Int(scale.rounded())
    }

    var size: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }
}

/// **Rendered previews, kept by brush value.**
///
/// An edited brush is a different value, so it misses and re-renders; an unedited one hits forever.
/// That is the whole caching rule and it needs no invalidation hook, which is the property BRUSH.md
/// §7.1 asked for by naming `BrushRef`.
///
/// `renderCount` is observability with nothing in the app reading it — the same job
/// `CanvasManager.sizePreviewRaiseCount` does for the size window. "An unedited brush does not
/// re-render" is only assertable by counting renders: comparing two images cannot tell a hit from a
/// second identical render, which is exactly the operand mistake CLAUDE.md's
/// "a green assertion is only as good as its two operands" section describes.
final class BrushPreviewCache {
    static let shared = BrushPreviewCache()

    private let lock = NSLock()
    private var images: [BrushPreviewKey: UIImage] = [:]
    private var renders = 0

    init() {}

    /// A cache probe. Never renders — what a SwiftUI row calls on the main thread before deciding
    /// whether it needs to go off it.
    func cached(_ key: BrushPreviewKey) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[key]
    }

    /// The image, rendering it if this brush value has not been seen at this size.
    ///
    /// Safe off the main thread: `UIGraphicsImageRenderer` is, and nothing here touches the view
    /// hierarchy. The lock is held across the render deliberately — two rows asking for the same
    /// brush at the same instant should produce one render, and a preview is ~1 ms.
    func image(for brush: Brush, size: CGSize, scale: CGFloat, color: UIColor) -> UIImage {
        let key = BrushPreviewKey(brush: brush, size: size, scale: scale)
        lock.lock()
        defer { lock.unlock() }
        if let hit = images[key] { return hit }
        let image = BrushPreview.render(brush, size: key.size, scale: CGFloat(key.scale), color: color)
        images[key] = image
        renders += 1
        return image
    }

    /// How many times this cache has actually rasterized. Tests and diagnostics only.
    var renderCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return renders
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        images.removeAll()
        renders = 0
    }
}
