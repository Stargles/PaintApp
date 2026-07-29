import UIKit

/// One slot in the layer stack: a raster fill layer (bucket-fill output for the current cel, pinned
/// edge-to-edge), and a drawable stroke canvas on top — so fill color always sits visually behind
/// that layer's own ink strokes. (Inserted photos are vector-layer content — see `VectorCanvas` —
/// and render as part of `strokeView`'s vector display, not a dedicated image view here.)
final class LayerHostView: UIView {
    let fillImageView = UIImageView()
    /// Raster content "baked" into this layer's active cel by a select/move/fill/clear operation
    /// (see `Cel.bakedImage`), or the transient "hole" preview while that cel's content is lifted
    /// into a floating piece. Sits above `fillImageView`, below `strokeView`'s live strokes.
    let bakedImageView = UIImageView()
    let strokeView = StrokeCanvasView()

    init() {
        super.init(frame: .zero)

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

        // `fillImageView` now shows the *live* fill-tool preview (committed fills are baked into
        // `bakedImage`), so it sits ABOVE `bakedImageView` — a recolour preview has to draw over the
        // existing baked content it's replacing — and below `strokeView`'s live ink.
        addSubview(bakedImageView)
        addSubview(fillImageView)
        addSubview(strokeView)
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
}
