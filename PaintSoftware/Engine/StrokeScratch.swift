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
/// **The three roles are the same distinction `VectorScratchRole` draws, and they decide how the
/// window reaches the screen as well as how it commits.** `.additive` holds only this stroke's own
/// ink and is composited *over* the layer's picture, so the layer's picture stays on screen
/// underneath and the commit is a source-over draw at the stroke's own opacity. `.subtractive` holds
/// this stroke's own **removal coverage** and *stands in for* the layer's picture inside the window,
/// so the display has to hide the layer's picture there (`StrokeCanvasView.showScratch` punches it
/// out) and the commit is one `.destinationOut` merge of that coverage at the stroke's opacity.
/// `.replacing` is the odd one out and is now the cut preview's alone: its window genuinely holds a
/// *picture*, several `stampStroke` calls deep (`VectorCanvas.applyPreview` erases and then restamps
/// caps into it), so it starts from a copy of the layer's own pixels and commits by replacing them.
///
/// **`.subtractive` is BRUSH.md §2.11's eraser and the arithmetic is exact.** N `.destinationOut`
/// dabs at `aᵢ` punched one at a time leave `∏(1 - aᵢ)` — a number no cap can be applied to, because
/// the punching already happened. A coverage window accumulates the same dabs source-over to
/// `A = 1 - ∏(1 - aᵢ)` and one punch at the stroke's opacity `o` leaves `1 - o·A`. At `o == 1` those
/// are the same number; below it, only the second obeys *"a 50% eraser removes exactly 50% wherever
/// the stroke goes, however often it crosses back over itself"*.
final class StrokeScratch: DabTarget {

    /// What the window's pixels mean, and therefore how they are shown and how they commit.
    enum Role {
        /// This stroke's ink and nothing else, over the layer's own picture.
        case additive
        /// This stroke's **removal coverage** and nothing else — BRUSH.md §2.11's eraser. `backdrop`
        /// is the layer's own picture, used to *show* the removal (the coverage punched out of a crop
        /// of it) and to decide whether there is anything to remove at all; the window itself never
        /// holds a pixel of it. **Nil is a legitimate empty start**: a layer with no bitmap yet has
        /// nothing to erase.
        case subtractive(backdrop: UIImage?)
        /// The layer's picture with this stroke applied to it. `backdrop` is the picture it starts
        /// from — canvas-sized and already resident (it is what is on screen), never rendered a
        /// second time for this. **Nil is a legitimate empty start**, not a missing one: a layer
        /// with no bitmap yet has nothing to copy and nothing to erase.
        ///
        /// **No longer the eraser's role.** It was, until §12 stage 8; what is left is Mode 2's cut
        /// preview, where one window holds an erase walk *and* the restamped end caps and so is a
        /// picture rather than a coverage map.
        case replacing(backdrop: UIImage?)
    }

    let canvasSize: CGSize
    let role: Role

    /// **The stroke's own opacity — BRUSH.md §2.11's cap, applied once when the window merges.**
    /// Stored rather than passed to `commit`, because the display needs the same number (`.additive`
    /// shows the window at this alpha, `.subtractive` punches the backdrop with it) and two callers
    /// each supplying it is two chances for the picture under the pen and the ink that lands to
    /// disagree.
    let opacity: CGFloat
    /// How the finished stroke meets the layer. `.normal` for everything but a brush carrying a blend
    /// mode; the eraser's punch is `.subtractive`'s own arithmetic rather than a mode carried here.
    let blendMode: CGBlendMode

    /// Whether the window stands in for the layer's own picture inside `windowRect`, rather than
    /// sitting over it. Read by the display to decide whether to punch the base out.
    var replacesBase: Bool {
        switch role {
        case .additive: return false
        case .subtractive, .replacing: return true
        }
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

    init(canvasSize: CGSize, role: Role, opacity: CGFloat = 1, blendMode: CGBlendMode = .normal) {
        self.canvasSize = canvasSize
        self.role = role
        self.opacity = opacity
        self.blendMode = blendMode
    }

    // MARK: - Reading

    /// **What the display shows for this window**, or nil before the first dab lands.
    ///
    /// For `.additive` and `.replacing` that is the window's own pixels. For `.subtractive` the
    /// window holds *coverage*, which is not a picture of anything — so the removal is drawn as a
    /// removal: the backdrop under the window, with the coverage punched out of it at the stroke's
    /// opacity. That is the same arithmetic `commit` performs against the cel, one crop wide, which
    /// is what makes the ink that lands the ink that was under the pen.
    var image: UIImage? {
        guard let window, !windowRect.isNull else { return nil }
        guard case .subtractive(let backdrop) = role else { return window.renderToUIImage() }
        // Memoized on the window's own version, exactly as `RasterLayerTexture.renderToUIImage` is
        // memoized on it. `StrokeCanvasView.refreshDisplay` asks for this once per SwiftUI pass and
        // several of those can land between two dabs; without the memo each one would be a fresh
        // window-sized composite, and the view's identity check (`scratchView.image !== image`)
        // would never hit either.
        if let cached = punchedImage, cachedPunchVersion == window.version { return cached }
        let coverage = window.renderToUIImage()
        let punched = UIGraphicsImageRenderer(size: windowRect.size, format: PixelOps.transparentFormat()).image { _ in
            backdrop?.draw(at: CGPoint(x: -windowRect.minX, y: -windowRect.minY))
            coverage.draw(at: .zero, blendMode: .destinationOut, alpha: opacity)
        }
        punchedImage = punched
        cachedPunchVersion = window.version
        return punched
    }

    /// `.subtractive`'s display image and the window version it was built from. Nil for every other
    /// role, which never mints one.
    private var punchedImage: UIImage?
    private var cachedPunchVersion: Int = -1

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

    /// **A group held here rather than forwarded, because the window can move under it.**
    ///
    /// `RasterLayerTexture` merges a group by opening a transparency layer on its own bitmap — and a
    /// dab outside the current window *replaces* that bitmap with a larger one (`window(containing:)`),
    /// which would throw the open layer and everything drawn into it away. So the dabs are collected
    /// in canvas space here, the window is grown once to contain all of them, and only then is the
    /// group opened on the window that is going to keep them. Nothing is buffered outside a group,
    /// which is the live walk's whole path: it stamps straight through, and the merge is `commit`.
    private var group: StrokeGroupBuffer?

    func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode) {
        group = StrokeGroupBuffer(opacity: opacity, blendMode: blendMode)
    }

    func endStrokeGroup() {
        guard let group else { return }
        self.group = nil
        guard !group.isEmpty, !group.bounds.isNull,
              let window = window(containing: group.bounds) else { return }
        let offset = CGPoint(x: -windowRect.minX, y: -windowRect.minY)
        window.beginStrokeGroup(opacity: group.opacity, blendMode: group.blendMode)
        for dab in group.dabs {
            let point = CGPoint(x: dab.center.x + offset.x, y: dab.center.y + offset.y)
            switch dab.tip {
            case .round(let hardness):
                window.stampCircle(at: point, radius: dab.radius, color: dab.color, alpha: dab.alpha,
                                   hardness: hardness, blendMode: dab.blendMode)
            case .image(let texture, let angle):
                window.stampImage(texture, at: point, diameter: dab.radius * 2, angle: angle,
                                  color: dab.color, alpha: dab.alpha, blendMode: dab.blendMode)
            }
        }
        window.endStrokeGroup()
    }

    func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                     alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
        guard radius > 0, alpha > 0 else { return }
        // `options: []` on the dab's radial gradient paints nothing past `radius`, so this is the
        // exact bound — the same rectangle `RasterLayerTexture.stampCircle` accumulates.
        let bounds = dabCircleBounds(at: point, radius: radius)
        if group != nil {
            group?.add(BrushStamper.BakedDab(center: point, radius: radius, color: color,
                                             alpha: alpha, blendMode: blendMode,
                                             tip: .round(hardness: hardness)), painting: bounds)
            return
        }
        guard let window = window(containing: bounds) else { return }
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
        let bounds = dabImageBounds(at: point, diameter: diameter, angle: angle)
        if group != nil {
            group?.add(BrushStamper.BakedDab(center: point, radius: diameter / 2, color: color,
                                             alpha: alpha, blendMode: blendMode,
                                             tip: .image(texture, angle: angle)), painting: bounds)
            return
        }
        guard let window = window(containing: bounds) else { return }
        window.stampImage(texture, at: CGPoint(x: point.x - windowRect.minX, y: point.y - windowRect.minY),
                          diameter: diameter, angle: angle, color: color, alpha: alpha,
                          blendMode: blendMode)
    }

    // MARK: - Selection clip

    /// Drops everything this stroke put outside `path` (canvas space), restoring what was there
    /// before — the window-space form of what the raster commit used to do with a canvas-sized
    /// `PixelOps.maskedComposite`.
    ///
    /// For `.additive` and `.subtractive` "what was there before" is nothing, since the window holds
    /// only this stroke's own ink or its own removal coverage; for `.replacing` it is the backdrop,
    /// which is why the clip has to redraw it rather than merely clearing.
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
        punchedImage = nil
    }

    // MARK: - Commit

    /// **Writes the window into `texture` at its own origin — and this is BRUSH.md §2.11's merge.**
    /// The one place the three roles' arithmetic differs:
    ///
    /// - `.additive` composites this stroke's ink at the stroke's own opacity and blend mode. That
    ///   is the cap: the window already holds the sum of the dabs' flow, however often they crossed,
    ///   and one draw at `opacity` is what stops the crossing reaching further than the stroke may.
    /// - `.subtractive` punches the coverage out at the same opacity, which is the identical
    ///   statement for the eraser — see the type comment for why one punch of the sum is not the sum
    ///   of the punches.
    /// - `.replacing` copies (its window already holds the final pixels for its region, alpha
    ///   included — a source-over draw could not take ink away). It commits nothing today: the cut
    ///   preview it belongs to is a preview, and the cut itself is vector geometry.
    func commit(into texture: RasterLayerTexture) {
        guard !windowRect.isNull else { return }
        switch role {
        case .additive:
            guard let image else { return }
            texture.composite(patch: image, at: windowRect.origin, opacity: opacity,
                              blendMode: blendMode)
        case .subtractive(let backdrop):
            // An eraser over a tier with no bitmap takes nothing away, and writing transparency
            // into it would materialise the canvas-sized context this class exists to avoid.
            guard backdrop != nil || texture.hasContent else { return }
            // The window's own pixels, which are the coverage — *not* `image`, which is the picture
            // of the removal that the display shows.
            guard let coverage = window?.renderToUIImage() else { return }
            texture.erase(patch: coverage, at: windowRect.origin, opacity: opacity)
        case .replacing(let backdrop):
            guard backdrop != nil || texture.hasContent else { return }
            guard let image else { return }
            texture.restore(patch: image, at: windowRect.origin)
        }
    }

    // MARK: - The window

    /// The picture a window of this role *starts from*, which is `.replacing`'s alone.
    ///
    /// **`.subtractive` carries a backdrop and it is deliberately not this one.** That window holds
    /// removal coverage, so seeding it with the layer's pixels — or redrawing them under a clip, or
    /// copying them into a grown window — would make the coverage a picture and the punch punch
    /// itself. Its backdrop is read only where a *picture* is wanted: `image`, and `commit`'s
    /// is-there-anything-to-erase guard.
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
        // A fresh texture starts at version 0, so the memo has to be dropped by hand rather than
        // trusted to notice — see `image`.
        punchedImage = nil
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
