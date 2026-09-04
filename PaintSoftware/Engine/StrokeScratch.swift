import UIKit
import CoreGraphics

/// The live-stroke drawing surface, sized to the stroke instead of to the canvas.
///
/// **Why this exists: a 16383² canvas is 1 GiB per RGBA buffer and the iPad has ~1.4 GiB before
/// jetsam.** Every live stroke used to open a `RasterLayerTexture` at `canvasSize` on touch-down,
/// materialise its full-canvas `CGContext` on the first dab, and mint a full-canvas `makeImage()`
/// per touch-move batch — which is copy-on-write, so the *next* dab duplicated the whole thing.
/// Two touch-moves into a stroke the live set was several canvases. The artist's report was
/// "a 16k by 16k canvas crashes when you draw something", and every term in that arithmetic is
/// canvas *area* against a stroke that touches a few thousand pixels.
///
/// So the scratch is a **window**: a rectangle in canvas point space that starts at the first dab
/// and grows to contain the stroke, clamped to the canvas. Nothing here is proportional to canvas
/// area — the peak is the stroke's own bounding box plus its growth margin.
///
/// **Growth is geometric per axis, and it has to be — on both counts.** Outsetting by a fixed pad
/// would reallocate every time the pen left the window, which is O(n²) copying over a long stroke.
/// So an axis the stroke has left is outset by half of *that axis's* own extent (floored at
/// `minimumPad`): it at least doubles, the box's area at least doubles with it, and the total
/// copying over a stroke is O(final area) rather than O(area × reallocations). An axis the stroke
/// has **not** left is not outset at all — it needs no headroom, and the guarantee above is already
/// paid by the axis that moved. That is what keeps a straight line's window a band as wide as the
/// line rather than a square as big as its length. The gesture that made the case is one screen inch
/// of pen travel at 16383², MEASURED on the owner's iPad 9 at **8617×8611 — 283.1 MB** round a stroke
/// whose own box is 54 KB; simulating both rules over that gesture gives **8639×134, 4.42 MB**
/// (PERFORMANCE §9 item 1, which also records that the width still overshoots the ink about
/// threefold because an outset grows both sides of the axis). A stroke that really does cross the
/// whole canvas ends up with a canvas-sized window, which is correct rather than a failure: that
/// stroke's dirty rect *is* the canvas.
///
/// **The two roles are the same distinction `VectorScratchRole` draws, and they decide how the
/// window reaches the screen as well as how it commits.** `.additive` holds only this stroke's own
/// ink and is composited *over* the layer's picture, so the layer's picture stays on screen
/// underneath and the commit is a source-over draw. `.replacing` starts from a copy of the layer's
/// own picture cropped to the window, takes `.destinationOut` punches out of it, and *stands in for*
/// the layer's picture inside the window — so the display has to hide the layer's picture there
/// (`StrokeCanvasView.showScratch` punches it out) and the commit is a `.copy` of the window's
/// final pixels. An erase cannot be expressed as something drawn on top, which is the whole reason
/// there are two roles and not one.
final class StrokeScratch: DabTarget {

    /// What the window's pixels mean, and therefore how they are shown and how they commit.
    enum Role {
        /// This stroke's ink and nothing else, over the layer's own picture.
        case additive
        /// The layer's picture with this stroke applied to it. `backdrop` is the picture it starts
        /// from — canvas-sized and already resident (it is what is on screen), never rendered a
        /// second time for this. **Nil is a legitimate empty start**, not a missing one: a layer
        /// with no bitmap yet has nothing to copy and nothing to erase.
        case replacing(backdrop: UIImage?)
    }

    let canvasSize: CGSize
    let role: Role

    /// Whether the window stands in for the layer's own picture inside `windowRect`, rather than
    /// sitting over it. Read by the display to decide whether to punch the base out.
    var replacesBase: Bool {
        if case .replacing = role { return true }
        return false
    }

    /// The window's rectangle in canvas point space — integral, and clamped to the canvas.
    /// `.null` until the first dab, which is what makes a touch that never moves cost nothing.
    private(set) var windowRect: CGRect = .null

    private var window: RasterLayerTexture?

    /// The dirty rect accumulated by windows this stroke has already outgrown. The live window's
    /// own `strokeDirtyRect` is unioned onto it by `dirtyRect`; reallocation folds one into the
    /// other, so a stroke that grows its window three times still reports the union of every dab.
    private var carriedDirtyRect: CGRect?

    /// Smallest margin a growth leaves around the dabs that forced it. Large enough that ordinary
    /// pen travel between reallocations is many samples, small enough to be noise next to any
    /// canvas worth worrying about.
    private static let minimumPad: CGFloat = 64

    init(canvasSize: CGSize, role: Role) {
        self.canvasSize = canvasSize
        self.role = role
    }

    // MARK: - Reading

    /// The window's pixels, or nil before the first dab lands.
    var image: UIImage? { window?.renderToUIImage() }

    /// Union of every dab this stroke has laid, in canvas point space — what the raster undo step
    /// crops its before/after patches to, and the measure of what this class exists to bound.
    var dirtyRect: CGRect? {
        guard let live = window?.strokeDirtyRect else { return carriedDirtyRect }
        let offset = live.offsetBy(dx: windowRect.minX, dy: windowRect.minY)
        return carriedDirtyRect?.union(offset) ?? offset
    }

    /// Pixels the window is actually holding. Nothing in the app reads this; it is the number the
    /// logic tests assert against, because "bounded by the stroke and not by the canvas" is a claim
    /// about exactly this quantity.
    var windowPixelCount: Int {
        guard let window else { return 0 }
        return window.pixelWidth * window.pixelHeight
    }

    // MARK: - DabTarget

    /// No-ops. `BrushStamper.stampStroke` brackets its walk with these to maintain a *persistent*
    /// texture's stroke count; a scratch is thrown away at lift and nothing counts strokes on it.
    /// They must stay no-ops rather than forwarding: `VectorCanvas.applyPreview` runs a fresh
    /// `stampStroke` per preview edit, and forwarding `beginStroke` would clear the window's dirty
    /// rect part-way through a stroke.
    func beginStroke() {}
    func endStroke() {}

    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                     alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        guard radius > 0, alpha > 0 else { return }
        // `options: []` on the dab's radial gradient paints nothing past `radius`, so this is the
        // exact bound — the same rectangle `RasterLayerTexture.stampCircle` accumulates.
        let dab = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        guard let window = window(containing: dab) else { return }
        window.stampCircle(at: CGPoint(x: point.x - windowRect.minX, y: point.y - windowRect.minY),
                           radius: radius, color: color, alpha: alpha, hardness: hardness,
                           blendMode: blendMode)
    }

    func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                    angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
        guard diameter > 0, alpha > 0 else { return }
        // A turned square reaches further than an unturned one — up to `diameter · √2 / 2` at 45° —
        // and the window has to contain the pixels, not the nominal size. `dabImageBounds` is the
        // same function `RasterLayerTexture.stampImage` accumulates its dirty rect with, so the
        // window and the dirty rect cannot disagree about what a dab covered.
        let dab = dabImageBounds(at: point, diameter: diameter, angle: angle)
        guard let window = window(containing: dab) else { return }
        window.stampImage(texture, at: CGPoint(x: point.x - windowRect.minX, y: point.y - windowRect.minY),
                          diameter: diameter, angle: angle, color: color, alpha: alpha,
                          blendMode: blendMode)
    }

    // MARK: - Selection clip

    /// Drops everything this stroke put outside `path` (canvas space), restoring what was there
    /// before — the window-space form of what the raster commit used to do with a canvas-sized
    /// `PixelOps.maskedComposite`.
    ///
    /// For `.additive` "what was there before" is nothing, since the window holds only this
    /// stroke's ink; for `.replacing` it is the backdrop, which is why the clip has to redraw it
    /// rather than merely clearing.
    func clip(to path: CGPath) {
        guard let window, !windowRect.isNull else { return }
        let current = window.renderToUIImage()
        carriedDirtyRect = dirtyRect
        let clipped = UIGraphicsImageRenderer(size: windowRect.size, format: PixelOps.transparentFormat()).image { ctx in
            let cg = ctx.cgContext
            // Into canvas space for the whole block, so `path` needs no transform of its own.
            cg.translateBy(x: -windowRect.minX, y: -windowRect.minY)
            backdrop?.draw(at: .zero)
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            current.draw(at: windowRect.origin)
            cg.restoreGState()
        }
        self.window = RasterLayerTexture(size: windowRect.size, image: clipped)
    }

    // MARK: - Commit

    /// Writes the window into `texture` at its own origin. The one place the two roles' arithmetic
    /// differs: `.additive` composites (source-over of this stroke's ink is associative with what is
    /// already there, so this is exactly what stamping into the texture directly would have done),
    /// `.replacing` copies (the window already holds the final pixels for its region, alpha
    /// included — a source-over draw could not take ink away).
    func commit(into texture: RasterLayerTexture) {
        guard let image, !windowRect.isNull else { return }
        switch role {
        case .additive:
            texture.composite(patch: image, at: windowRect.origin)
        case .replacing(let backdrop):
            // An eraser over a tier with no bitmap takes nothing away, and writing transparency
            // into it would materialise the canvas-sized context this class exists to avoid.
            guard backdrop != nil || texture.hasContent else { return }
            texture.restore(patch: image, at: windowRect.origin)
        }
    }

    // MARK: - The window

    private var backdrop: UIImage? {
        if case .replacing(let backdrop) = role { return backdrop }
        return nil
    }

    /// The window enlarged if necessary to contain `rect`, or nil when `rect` lies entirely off the
    /// canvas — off-canvas pixels are storable nowhere and displayable nowhere, so a dab there is
    /// dropped rather than growing the box to reach it.
    private func window(containing rect: CGRect) -> RasterLayerTexture? {
        // Rounded the way `RasterLayerTexture` rounds its own size, so the window's pixel grid is
        // the cel's pixel grid: an integral origin is what makes a dab land on exactly the pixels it
        // would have landed on stamped straight into the cel, sub-pixel phase included.
        let canvas = CGRect(origin: .zero, size: CGSize(width: canvasSize.width.rounded(),
                                                        height: canvasSize.height.rounded()))
        // `rect` itself is never clamped — a dab pressed against the edge has a circle that pokes
        // past it — but `windowRect` always is (`next` below is `.intersection(canvas)`), and
        // nothing off-canvas is storable or displayable. So the containment test has to compare
        // against the part of `rect` that could ever land in the window, or a dab straddling any
        // edge would fail `contains` forever and rebuild on every single one of them.
        let onCanvas = rect.intersection(canvas)
        // Checked before the fast path rather than after: `CGRect.contains(.null)` is true, so a
        // dab that has drifted entirely off-canvas would otherwise pass containment against
        // whatever window already exists instead of being dropped.
        guard !onCanvas.isNull else { return nil }
        if let window, windowRect.contains(onCanvas) { return window }
        let wanted = windowRect.isNull ? rect : windowRect.union(rect)
        let held = windowRect.isNull ? CGSize.zero : windowRect.size
        let next = wanted.insetBy(dx: -Self.pad(held: held.width, wanted: wanted.width),
                                  dy: -Self.pad(held: held.height, wanted: wanted.height))
            .integral.intersection(canvas)
        guard next.width >= 1, next.height >= 1 else { return nil }
        let grown = RasterLayerTexture(size: next.size, image: contents(for: next))
        carriedDirtyRect = dirtyRect
        windowRect = next
        window = grown
        return grown
    }

    /// How far one axis is outset when the window is rebuilt. `held` is what that axis measures now
    /// (zero before the first dab), `wanted` what it has to measure to contain the union.
    ///
    /// **Zero for an axis the union did not exceed**, which is the whole difference between a band
    /// and a square: a horizontal stroke never leaves the window vertically, so its height is
    /// whatever the first dab set and stays there. Nothing is given up by that — the reallocation
    /// was forced by the *other* axis, that axis at least doubles, so the box's area at least
    /// doubles and the amortisation the class comment argues for is already paid.
    ///
    /// Half of `held` rather than of `wanted` when it does grow, so a fast pen that jumps far past
    /// the window in one batch gets its jump plus half the old box rather than half the new one —
    /// still at least a doubling of the axis, without paying for headroom the size of the leap.
    private static func pad(held: CGFloat, wanted: CGFloat) -> CGFloat {
        guard wanted > held else { return 0 }
        return max(minimumPad, held / 2)
    }

    /// What a freshly grown window starts life holding: the backdrop under it, then whatever the
    /// window it replaces had already accumulated, copied over the top.
    ///
    /// `.copy` rather than a source-over draw, and for both roles: the old window's alpha is the
    /// answer for its own region in either role — for `.replacing` because a punch is *lower* alpha
    /// than the backdrop it came out of and source-over would put the backdrop straight back, and
    /// for `.additive` because there is nothing underneath to preserve anyway.
    private func contents(for rect: CGRect) -> UIImage? {
        let previous = window?.renderToUIImage()
        guard backdrop != nil || previous != nil else { return nil }
        return UIGraphicsImageRenderer(size: rect.size, format: PixelOps.transparentFormat()).image { _ in
            backdrop?.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
            if let previous, !windowRect.isNull {
                previous.draw(at: CGPoint(x: windowRect.minX - rect.minX, y: windowRect.minY - rect.minY),
                              blendMode: .copy, alpha: 1)
            }
        }
    }
}
