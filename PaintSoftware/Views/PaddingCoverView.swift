import UIKit

/// TODO (133) — the canvas padding drawn **over** the artwork's ink: the whole canvas buffer minus
/// the artwork rect, filled with the margin's grey. With it up, anything drawn into the margin is
/// covered, so the artwork's edge is the edge of the grey however the strokes cross it.
///
/// A `CAShapeLayer` rather than a view with a `draw(_:)` or four edge strips: the canvas can be
/// 4096² and a drawn view would carry a backing store of that size to paint four thin bars, and a
/// shape is one even-odd path whatever the padding is. It takes no touches — the artist draws into
/// the margin through it, exactly as they do with it down.
final class PaddingCoverView: UIView {

    /// The margin's grey — one definition for this and for the backdrop under the paper
    /// (`CanvasView.makeUIView`), so the margin reads the same whichever of the two is showing it.
    static let tint = UIColor(white: 0.85, alpha: 1)

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
        shapeLayer.fillColor = Self.tint.cgColor
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
