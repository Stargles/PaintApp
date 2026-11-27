import UIKit

/// One slot in the layer stack: baked raster content at the bottom, a drawable stroke canvas over it,
/// and the live fill preview **on top** — a fill covers everything already on the layer, including that
/// layer's own ink (LASSO_FILL.md §2a). (Inserted photos are vector-layer content — see `VectorCanvas` —
/// and render as part of `strokeView`'s vector display, not a dedicated image view here.)
final class LayerHostView: CanvasPlaneView {
    /// Raster content "baked" into this layer's active cel by a select/move/fill/clear operation
    /// (see `Cel.bakedImage`), or the transient "hole" preview while that cel's content is lifted
    /// into a floating piece. The **bottom** of the three, below `strokeView`'s live strokes and
    /// below the fill's preview.
    let bakedImageView = CanvasPictureView()
    private(set) var displayedBakedSource: RasterSource?
    let strokeView = StrokeCanvasView()

    /// **The live fill's plane: the layer's own space, posed** (`shownPose`). Its bounds are the host's
    /// with the anchor at the origin, so the pose is its transform about the canvas origin; the fill's
    /// surface inside it is placed in the layer's own space, where a fill is worked out.
    private let fillPlane = LayerFillView()

    init() {
        super.init(frame: .zero)

        // Set on every view a canvas touch can hit-test into, for the reason spelled out in
        // `StrokeCanvasView.init`. `strokeView` covers itself; this covers the case where it is
        // interaction-disabled and the touch lands here instead.
        isMultipleTouchEnabled = true

        // Sized with the host in `layoutSubviews`; anchored at the origin, so a pose is the plane's
        // transform and not the pose conjugated about its centre.
        fillPlane.isUserInteractionEnabled = false
        fillPlane.layer.anchorPoint = .zero
        fillPlane.layer.position = .zero

        bakedImageView.isUserInteractionEnabled = false
        bakedImageView.isHidden = true
        bakedImageView.layer.anchorPoint = .zero
        bakedImageView.layer.position = .zero

        strokeView.backgroundColor = .clear
        strokeView.isOpaque = false
        strokeView.translatesAutoresizingMaskIntoConstraints = false

        // The whole layer stack is magnified via a CGAffineTransform scale on the container (see
        // Coordinator.applyTransform), not by re-rasterizing at a higher resolution. Both of the
        // host's whole-canvas pictures reach the screen as the window (`CanvasPictureView`), drawn
        // nearest-neighbour when magnified, so pixels stay crisp at high zoom, and filtered when shrunk:
        // the canvas opens at `fitScale`, and unfiltered minification loses thin ink outright —
        // MEASURED (BUGS.md, PERFORMANCE.md §9 item 2, 2026-09-02), the default 5-point brush left 800
        // pixels of ink at 2048² and **zero** at 4096², 8192² and 12288². The fill's surface sets
        // its own (`WindowSurfaceView.init`).

        // `fillPlane` shows the *live* fill-tool preview (a committed fill is flattened into the
        // cel's `raster` tier), and it is **the topmost of the three**: LASSO_FILL.md §2a — a fill
        // covers everything already on the layer, earlier fills and this layer's own ink alike. The
        // preview has to stack the way `commitInteractiveFill` will, or the picture rearranges itself
        // when the artist lifts the pencil. `PixelOps.rasterizeUncached` draws the same three tiers in
        // this same order, which is what keeps the live canvas and every flatten of it agreeing.
        //
        // Being above `strokeView` costs nothing in touch handling: the plane takes no touches, so it
        // is invisible to hit-testing and the stroke canvas underneath still receives the first touch
        // of every stroke.
        addSubview(bakedImageView)
        addSubview(strokeView)
        addSubview(fillPlane)
        NSLayoutConstraint.activate([
            strokeView.topAnchor.constraint(equalTo: topAnchor),
            strokeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            strokeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            strokeView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func installBaked(source: RasterSource?, image: UIImage?) {
        displayedBakedSource = source
        bakedImageView.show(image)
        bakedImageView.isHidden = image == nil
    }

    /// A pan, zoom or turn of the canvas: both of the host's whole-canvas pictures draw what the
    /// window now shows of them (`CanvasPictureView`).
    func windowMoved() {
        bakedImageView.windowMoved()
        strokeView.windowMoved()
    }

    /// The layers this host's pictures are on screen in — where the host already draws its ink.
    var drawnLayers: [CALayer] { [bakedImageView.drawnLayer, strokeView.drawnLayer].compactMap { $0 } }

    /// Runs when a draw of either picture reaches the screen.
    var onWindowShown: (() -> Void)? {
        didSet {
            bakedImageView.onShown = onWindowShown
            strokeView.onWindowShown = onWindowShown
        }
    }

    @discardableResult
    func showFill(_ render: CanvasManager.FillRenderResult?, clip: CGPath?) -> Bool {
        fillPlane.showFill(render, clip: clip)
    }

    func holdCommittedFill(_ preview: FillPreview, render: CanvasManager.FillRenderResult,
                           clip: CGPath?, at version: Int) {
        let contents = fillPlane.contentsForLanding(preview, render: render, clip: clip)
        // Both representations span the same rect in the layer's ink plane, even at a reduced scale.
        strokeView.holdUnlandedWindow(contents, rect: preview.rect, at: version)
    }

    /// The accepted ink and backing placements belong to the same installed base. Ordinary cel
    /// channels move native ink only; stored pixel tiers retain their container placement.
    var contentPlacement: CelContentPlacement {
        get { strokeView.contentPlacement }
        set {
            guard newValue != strokeView.contentPlacement else { return }
            strokeView.contentPlacement = newValue
            let ink = newValue.ink.flatMap { $0.inverse == nil ? nil : $0 }
            let backing = newValue.backing.flatMap { $0.inverse == nil ? nil : $0 }
            fillPlane.layer.transform = ink?.layerTransform ?? CATransform3DIdentity
            bakedImageView.layer.transform = backing?.layerTransform ?? CATransform3DIdentity
            bakedImageView.windowMoved()
            alignContentMasks()
        }
    }

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
    /// **The stroke view is told, because blanking is not only a mask — it is permission to stop
    /// rendering.** A canvas-sized vector rasterize for a host that draws nothing is the whole of
    /// TODO (53) reached through the base slot rather than the derived one, and it is what playback
    /// was spending: see `DeferredVectorRender.Step.blankedByTheComposite` and
    /// `CanvasManager.sandwichEngagesOnCanvas`. Pushed down rather than read up so that the stroke
    /// view owns one answer instead of reaching into its superview for it.
    func setBlanked(_ blanked: Bool) {
        if blanked {
            if layer.mask !== blankingMask { layer.mask = blankingMask }
        } else if layer.mask === blankingMask {
            layer.mask = nil
        }
        hostContentVisibilityChanged()
    }

    /// **Hiding a layer is the other way a host stops drawing, and it costs the same rasterize.**
    /// `CanvasView.reconcileLayers` sets this from `isLayerEffectivelyVisible` and then, a few lines
    /// later in the same pass, hands the host the cel that covers the current frame — so before this
    /// observer existed a hidden layer paid a full canvas-sized vector render on every frame step,
    /// for pixels `isHidden` throws away. That is the owner's TODO (58): *"this is even after hiding
    /// all layers so that the canvas is pretty much a blank white sheet"*, MEASURED by them at 313 ms
    /// a frame at 6000².
    ///
    /// An observer rather than a call in `reconcileLayers` because `isHidden` has other writers —
    /// UIKit's own, and any future one — and the invariant is *"the stroke view knows whether it is
    /// visible"*, not *"one call site remembers to say so"*.
    override var isHidden: Bool {
        didSet { hostContentVisibilityChanged() }
    }

    /// The one answer the stroke view needs, from the two things that can produce it.
    private func hostContentVisibilityChanged() {
        let blanked = isBlanked || isHidden
        if blanked { installBaked(source: nil, image: nil) }
        strokeView.hostBlankingChanged(to: blanked)
    }

    /// **Whether this host is currently rendering nothing because the composite is drawing it** —
    /// the state `setBlanked` last put it in, read off the same field rather than mirrored into a
    /// `Bool` beside it.
    ///
    /// `CanvasView.updateInterpolationPreviews` is the reader: a derived cel's picture costs a
    /// canvas-sized rasterize, and producing one for a host that renders nothing is the whole of
    /// TODO (53). Asking the mask rather than a cached flag is what stops the two answers drifting —
    /// "this host draws itself" and "this host needs a picture" are one condition, and a second copy
    /// of it is what would go stale on the pass where blanking is declined (`updateSandwich`'s trap
    /// 1 returns before blanking when nothing has landed to blank in favour of).
    var isBlanked: Bool { layer.mask === blankingMask }

    // MARK: - The alpha mask, for §6.4's live stroke

    /// The three views that hold this layer's own pixels, and therefore the three that a mask has to
    /// clip. Ordered as they are stacked, which is only for reading — `contentMasks` pairs with this
    /// by index and nothing else depends on the order.
    private var maskedContentViews: [UIView] { [bakedImageView, strokeView, fillPlane] }

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
    private var backingReplacementHole: CGPath?

    func setBackingReplacementHole(_ hole: CGPath?) {
        if backingReplacementHole == nil, hole == nil { return }
        backingReplacementHole = hole
        alignContentMasks()
    }

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

        alignContentMasks()
    }

    /// Where a canvas-sized mask sits in `view`'s own coordinates: the host's bounds, shifted back by
    /// the view's origin — which is zero for the two pinned views and the pose's offset for
    /// `fillPlane`.
    private func maskFrame(for view: UIView) -> CGRect {
        bounds.offsetBy(dx: -view.frame.minX, dy: -view.frame.minY)
    }

    private func alignContentMasks() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (index, pair) in zip(maskedContentViews, contentMasks).enumerated() {
            let (view, mask) = pair
            let hole = index == 0 ? backingReplacementHole : nil
            guard contentMaskImage != nil || hole != nil else {
                if view.layer.mask === mask { view.layer.mask = nil }
                mask.contents = nil; mask.mask = nil
                continue
            }
            mask.contents = contentMaskImage
            mask.backgroundColor = contentMaskImage == nil ? UIColor.white.cgColor : nil
            if index == 0 {
                mask.anchorPoint = .zero
                mask.position = .zero
                mask.bounds = bounds
                // The layer alpha mask lives in shown canvas space; backing pixels live at rest.
                mask.transform = contentMaskImage == nil ? CATransform3DIdentity
                    : (contentPlacement.backing?.inverse?.layerTransform ?? CATransform3DIdentity)
            } else { mask.frame = maskFrame(for: view) }
            if let hole {
                let path = CGMutablePath()
                path.addRect(bounds)
                path.addPath(contentMaskImage == nil ? (contentPlacement.backing?.inverse?.mapped(hole) ?? hole) : hole)
                let clip = (mask.mask as? CAShapeLayer) ?? CAShapeLayer()
                clip.fillRule = .evenOdd
                clip.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
                clip.frame = bounds
                clip.path = path
                mask.mask = clip
            } else { mask.mask = nil }
            if view.layer.mask !== mask { view.layer.mask = mask }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillPlane.bounds = bounds
        bakedImageView.bounds = bounds
        // The mask layers are not in the view hierarchy, so autolayout does not reach them. Canvas
        // size is fixed for a document's life and a stroke cannot outlive it, so this is belt and
        // braces rather than a live resize path — but a mask frozen at the zero frame it was created
        // with would hide the layer entirely, which is too quiet a failure to leave to reasoning.
        alignContentMasks()
    }
}
