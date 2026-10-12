import UIKit

/// TODO (133) — the canvas padding drawn **over** the artwork's ink: the whole canvas buffer minus
/// the artwork rect, filled with a translucent veil of the margin's grey (TODO (180)). With it up,
/// ink drawn into the margin shows through, dimmed, and the artwork's edge is the edge of the grey
/// however the strokes cross it. Over an empty margin the veil is grey over the same grey, so the
/// margin reads exactly as it does with the cover down.
///
/// A `CAShapeLayer` rather than a view with a `draw(_:)` or four edge strips: the canvas can be
/// 4096² and a drawn view would carry a backing store of that size to paint four thin bars, and a
/// shape is one even-odd path whatever the padding is. It takes no touches — the artist draws into
/// the margin through it, exactly as they do with it down.
final class PaddingCoverView: UIView {

    /// The margin's grey, **opaque**: the backdrop under the paper (`CanvasView.makeUIView`) and the
    /// backdrop a held frame is drawn on (`CanvasView.Coordinator.mintHeldFrame`), which replaces
    /// the canvas and so must not let what is behind it show.
    static let marginGrey = UIColor(white: 0.85, alpha: 1)

    /// How much of the ink under the cover is hidden by it. Half: the ink is plainly there, and the
    /// margin is plainly not artwork.
    static let veilOpacity: CGFloat = 0.5

    /// The cover's own colour — `marginGrey` at `veilOpacity`, so over the backdrop's `marginGrey` an
    /// empty margin is the same grey with the cover up or down.
    static let veil = marginGrey.withAlphaComponent(veilOpacity)

    override class var layerClass: AnyClass { CAShapeLayer.self }

    private var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }

    /// How far the artwork rect sits inside the bounds on every side, in canvas points.
    var inset: CGFloat = 0 {
        didSet { if inset != oldValue { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shapeLayer.fillColor = Self.veil.cgColor
        shapeLayer.fillRule = .evenOdd
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(rect: bounds.insetBy(dx: inset, dy: inset)))
        shapeLayer.path = path.cgPath
    }
}
