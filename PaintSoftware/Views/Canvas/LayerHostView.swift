import UIKit

/// One slot in the layer stack: baked raster content at the bottom, a drawable stroke canvas over it,
/// and the live fill preview pinned edge-to-edge **on top** — a fill covers everything already on the
/// layer, including that layer's own ink (LASSO_FILL.md §2a). (Inserted photos are vector-layer
/// content — see `VectorCanvas` — and render as part of `strokeView`'s vector display, not a
/// dedicated image view here.)
final class LayerHostView: UIView {
    let fillImageView = UIImageView()
    /// Raster content "baked" into this layer's active cel by a select/move/fill/clear operation
    /// (see `Cel.bakedImage`), or the transient "hole" preview while that cel's content is lifted
    /// into a floating piece. The **bottom** of the three, below `strokeView`'s live strokes and
    /// below `fillImageView`'s preview.
    let bakedImageView = UIImageView()
    let strokeView = StrokeCanvasView()

    init() {
        super.init(frame: .zero)

        // Set on every view a canvas touch can hit-test into, for the reason spelled out in
        // `StrokeCanvasView.init`. `strokeView` covers itself; this covers the case where it is
        // interaction-disabled and the touch lands here instead.
        isMultipleTouchEnabled = true

        // The fill raster is always rendered at exactly canvasSize (see FloodFillEngine), matching this
        // view's bounds 1:1, so a plain stretch-to-fill can't introduce any resampling blur at the edges.
        fillImageView.contentMode = .scaleToFill
        fillImageView.translatesAutoresizingMaskIntoConstraints = false

        bakedImageView.isUserInteractionEnabled = false
        bakedImageView.isHidden = true
        bakedImageView.translatesAutoresizingMaskIntoConstraints = false

        strokeView.backgroundColor = .clear
        strokeView.isOpaque = false
        strokeView.translatesAutoresizingMaskIntoConstraints = false

        // The whole layer stack is magnified via a CGAffineTransform scale on the container (see
        // Coordinator.applyTransform), not by re-rasterizing at a higher resolution — Core Animation's
        // default magnificationFilter (.linear) would bilinearly blur these raster layers' textures as
        // the user zooms in. Nearest-neighbor keeps pixels crisp/blocky at high zoom instead. strokeView
        // sets this on its own internal image view (see StrokeCanvasView.init).
        fillImageView.layer.magnificationFilter = .nearest
        bakedImageView.layer.magnificationFilter = .nearest

        // `fillImageView` shows the *live* fill-tool preview (a committed fill is flattened into the
        // cel's `raster` tier), and it is **the topmost of the three**: LASSO_FILL.md §2a — a fill
        // covers everything already on the layer, earlier fills and this layer's own ink alike. The
        // preview has to stack the way `commitInteractiveFill` will, or the picture rearranges itself
        // when the artist lifts the pencil. `PixelOps.rasterizeUncached` draws the same three tiers in
        // this same order, which is what keeps the live canvas and every flatten of it agreeing.
        //
        // Being above `strokeView` costs nothing in touch handling: `UIImageView` is
        // `isUserInteractionEnabled == false` by default, so it is invisible to hit-testing and the
        // stroke canvas underneath still receives the first touch of every stroke.
        addSubview(bakedImageView)
        addSubview(strokeView)
        addSubview(fillImageView)
        NSLayoutConstraint.activate([
            fillImageView.topAnchor.constraint(equalTo: topAnchor),
            fillImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fillImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bakedImageView.topAnchor.constraint(equalTo: topAnchor),
            bakedImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bakedImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bakedImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            strokeView.topAnchor.constraint(equalTo: topAnchor),
            strokeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            strokeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            strokeView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Blanking, for §5.2's sandwich

    /// An empty mask layer. A mask with no contents has alpha 0 everywhere — including outside its
    /// own (zero) bounds — so the host renders nothing at all while it is installed. Allocated once
    /// and reused: `CanvasView.updateUIView` runs on every SwiftUI pass, and a `CALayer` per pass
    /// would be an allocation per render of the whole editor.
    private lazy var blankingMask = CALayer()

    /// Hides this host's pixels while §5.2's sandwich draws them instead, **without hiding the view
    /// from hit-testing**.
    ///
    /// `isHidden` and `alpha` are both wrong here and they fail silently. `UIView.hitTest` returns
    /// nil for any view that is hidden, has `alpha < 0.01`, or has interaction disabled, so a blanked
    /// *active* host would never receive the first touch of a stroke and the artist's stroke would
    /// simply not happen — no error, no mark. (`UIView.alpha` and `CALayer.opacity` are the same
    /// backing property, so neither is an escape from that.) A mask is: UIKit's hit-testing does not
    /// consult `layer.mask` at all, so the host stays fully touchable while rendering nothing.
    ///
    /// `LayerUITests.testAStrokeStillLandsWhileTheSandwichIsEngaged` is the regression guard — it is
    /// what fails if this is ever "simplified" back into `isHidden`.
    func setBlanked(_ blanked: Bool) {
        if blanked {
            if layer.mask !== blankingMask { layer.mask = blankingMask }
        } else if layer.mask === blankingMask {
            layer.mask = nil
        }
    }

    // MARK: - The alpha mask, for §6.4's live stroke

    /// The three views that hold this layer's own pixels, and therefore the three that a mask has to
    /// clip. Ordered as they are stacked, which is only for reading — `contentMasks` pairs with this
    /// by index and nothing else depends on the order.
    private var maskedContentViews: [UIView] { [bakedImageView, strokeView, fillImageView] }

    /// One mask layer per content view. **Three, not one shared**: `CALayer.mask` takes ownership the
    /// way a superlayer does, so assigning a single layer to three masks would move it to the third
    /// and silently leave the other two unmasked.
    private lazy var contentMasks: [CALayer] = maskedContentViews.map { _ in
        let mask = CALayer()
        // The mask is canvas-sized and so are these views' bounds, so it is a 1:1 blit — and nearest
        // is what keeps it agreeing with the composite under zoom, since `full` reaches the screen
        // through image views that magnify the same way (`makeSandwichView`). Bilinear here would
        // soften the clip edge against a composite that keeps it crisp.
        mask.magnificationFilter = .nearest
        return mask
    }

    /// What is masking this host's content right now — held so the many SwiftUI passes that change
    /// nothing are an identity check rather than a Core Animation write.
    private var contentMaskImage: CGImage?

    /// Clips this layer's own pixels to `image`'s alpha for as long as it is installed — §6.4's live
    /// feedback, and the reason `ResolvedMask.makeMaskImage()` exists.
    ///
    /// **Deliberately not `layer.mask`, which `setBlanked` owns.** Installing both there would leave
    /// whichever ran second holding the slot: blanking would eat the mask, or the mask would unblank
    /// a host the sandwich is drawing for — and either way silently, since a `CALayer.mask` reports
    /// nothing about being replaced. Two slots, two owners, no ordering rule to remember.
    ///
    /// **All three content views rather than `strokeView` alone.** Mid-stroke this host is the only
    /// thing drawing the active layer — it is in neither sandwich half — so its baked and fill tiers
    /// are as unclipped as its live ink until they are masked too. Masking only the ink would fix the
    /// stroke and leave baked content popping out from under the clip on the same first touch.
    ///
    /// Implicit animation is off: this is installed on a stroke's first touch, and Core Animation's
    /// default would fade the clip in over a quarter second while the artist draws through it.
    func setContentMask(_ image: CGImage?) {
        guard contentMaskImage !== image else { return }
        contentMaskImage = image

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (view, mask) in zip(maskedContentViews, contentMasks) {
            if let image {
                mask.contents = image
                mask.frame = bounds
                if view.layer.mask !== mask { view.layer.mask = mask }
            } else {
                if view.layer.mask === mask { view.layer.mask = nil }
                mask.contents = nil
            }
        }
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The mask layers are not in the view hierarchy, so autolayout does not reach them. Canvas
        // size is fixed for a document's life and a stroke cannot outlive it, so this is belt and
        // braces rather than a live resize path — but a mask frozen at the zero frame it was created
        // with would hide the layer entirely, which is too quiet a failure to leave to reasoning.
        guard contentMaskImage != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for mask in contentMasks where mask.frame != bounds { mask.frame = bounds }
        CATransaction.commit()
    }
}
