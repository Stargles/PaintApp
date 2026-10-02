import UIKit

/// **The angle a held rotate handle has its box at, drawn beside the handle** — TODO (151), the
/// owner's *"have a degree indicator when a rotate node is selected. (Example: 23.72°)"*.
///
/// One pill for the whole canvas, in `CanvasHostView` above the canvas plane, driven by whichever
/// overlay's knob is held (`ObjectTransformOverlayView`, `FloatingPieceOverlayView`,
/// `TextTransformOverlayView`, `ShapeOverlayView`). **It sits in screen space, not in the canvas
/// plane** — a label inside the plane would be scaled and turned with the artist's zoom and canvas
/// rotation like the artwork, where chrome belongs to the screen (the handles divide their sizes by
/// `canvasScale` for the same reason). The overlay hands over the knob and the box's centre in its own
/// coordinates and this converts them, so it does not care how the plane is transformed.
///
/// **The overlay reads the angle off the model it was just handed**, not off the finger: the same
/// number the box is drawn at, with every snap and clamp already applied, so the readout cannot say
/// one thing while the box does another. It stands off the knob on the side away from the box, where
/// the pen that holds the knob is not covering it.
///
/// **It stays a moment after the knob is let go** (`lingerSeconds`), so the artist can read what the
/// turn landed on without holding the pen still. A drag that begins in that moment takes the pill over.
final class RotationReadoutView: UIView {

    /// What the pill says, or nil while it is hidden. Published on `canvas.host`'s label
    /// (`CanvasView.Coordinator.publishCanvasState`), because the host is an accessibility element
    /// and hides this view from XCUITest like every other descendant.
    private(set) var text: String?

    /// Called whenever `text` changes — shown, changed, or hidden — so the host's label can follow.
    var onTextChanged: (() -> Void)?

    /// Screen points from the knob's centre to the pill's nearest edge: the knob's radius and a gap.
    private static let standOff: CGFloat = 17
    /// How long the pill stays after the knob is let go.
    static let lingerSeconds: TimeInterval = 1.0
    private static let edgeInset: CGFloat = 8
    private static let padding = CGSize(width: 10, height: 5)

    private let label = UILabel()
    private var pendingHide: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layer.cornerRadius = 9
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows `angle` beside the knob. `knob` and `centre` are in `plane`'s coordinates — the overlay's
    /// own — and the pill stands off the knob along the line from the centre through it.
    func show(angle: CGFloat, knob: CGPoint, centre: CGPoint, in plane: UIView) {
        guard let host = superview else { return }
        pendingHide?.cancel()
        pendingHide = nil

        let readout = RotationAngle.readout(angle)
        if readout != text {
            text = readout
            label.text = readout
            label.sizeToFit()
            bounds = CGRect(origin: .zero, size: CGSize(width: label.bounds.width + 2 * Self.padding.width,
                                                        height: label.bounds.height + 2 * Self.padding.height))
            label.center = CGPoint(x: bounds.midX, y: bounds.midY)
            onTextChanged?()
        }
        isHidden = false

        let knobOnScreen = plane.convert(knob, to: host)
        let centreOnScreen = plane.convert(centre, to: host)
        let away = CGPoint(x: knobOnScreen.x - centreOnScreen.x, y: knobOnScreen.y - centreOnScreen.y)
        let length = hypot(away.x, away.y)
        // A knob on its own centre has no side to be on: above it.
        let direction = length > 0 ? CGPoint(x: away.x / length, y: away.y / length) : CGPoint(x: 0, y: -1)
        // The pill's centre is far enough along `direction` that its *edge* is `standOff` from the knob
        // whichever way that is: a pill to the side of a knob stands half its width off, one above or
        // below it half its height.
        let halfWidth = bounds.width / 2, halfHeight = bounds.height / 2
        let toEdge = min(halfWidth / max(abs(direction.x), 1e-6), halfHeight / max(abs(direction.y), 1e-6))
        let wanted = CGPoint(x: knobOnScreen.x + direction.x * (Self.standOff + toEdge),
                             y: knobOnScreen.y + direction.y * (Self.standOff + toEdge))
        let reach = host.bounds.insetBy(dx: bounds.width / 2 + Self.edgeInset,
                                        dy: bounds.height / 2 + Self.edgeInset)
        center = CGPoint(x: min(max(wanted.x, reach.minX), reach.maxX),
                         y: min(max(wanted.y, reach.minY), reach.maxY))
    }

    /// The knob was let go: the pill stays `lingerSeconds`, then goes.
    func release() {
        guard text != nil else { return }
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerSeconds, execute: work)
    }

    /// Gone now — the overlay that was showing it has stood down.
    func hide() {
        pendingHide?.cancel()
        pendingHide = nil
        isHidden = true
        guard text != nil else { return }
        text = nil
        onTextChanged?()
    }
}
