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
///
/// **It stands inside the part of the canvas the artist can see** — the host's bounds less the bottom
/// strip the timeline and a docked panel lie over (`coveredBottom`) — **and one rule puts it there**
/// (`centre(forKnob:awayFrom:pillSize:within:)`): on the side of the knob away from the box if the pill
/// fits there, on the box's side of the knob if it does not, and in either case no nearer an edge of
/// that area than `edgeInset`. A knob at the edge of the area is the one the pill would otherwise cover
/// or hide, and no edge is a case of its own.
final class RotationReadoutView: UIView {

    /// What the pill says, or nil while it is hidden. Published on `canvas.host`'s label
    /// (`CanvasView.Coordinator.publishCanvasState`), because the host is an accessibility element
    /// and hides this view from XCUITest like every other descendant.
    private(set) var text: String?

    /// Called whenever `text` changes — shown, changed, or hidden — and when the knob is let go, so the
    /// host's label can follow what the pill says and where it ended up. Not on every move of the
    /// pill: that is a touch-move rate, and the label is a string built from the whole canvas.
    var onChanged: (() -> Void)?

    /// How much of the host's bottom lies under chrome that is drawn over it — the timeline, and the
    /// docked panel riding on it. Set by `CanvasView` on every pass.
    var coveredBottom: CGFloat = 0

    /// Screen points from the knob's centre to the pill's nearest edge: the knob's radius and a gap.
    static let standOff: CGFloat = 17
    /// How long the pill stays after the knob is let go.
    static let lingerSeconds: TimeInterval = 1.0
    /// The nearest the pill's edge goes to an edge of the visible area.
    static let edgeInset: CGFloat = 8
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
            onChanged?()
        }
        isHidden = false

        let visible = CGRect(x: 0, y: 0, width: host.bounds.width,
                             height: max(0, host.bounds.height - coveredBottom))
        center = Self.centre(forKnob: plane.convert(knob, to: host),
                             awayFrom: plane.convert(centre, to: host),
                             pillSize: bounds.size, within: visible)
    }

    /// **Where the pill's centre goes** — the one placement rule, over screen points in the host's
    /// coordinates. `visible` is the part of the host the artist can see.
    ///
    /// The pill stands off the knob along the line from `box` through it, so it is on the side the
    /// box is not and the pen that holds the knob is not covering it. When that side has no room — a
    /// knob at the edge of `visible`, where the pill would sit on top of the knob or under the
    /// timeline — it takes the box's side of the knob instead; and whichever it ends on is held
    /// inside `visible` by `edgeInset`. A knob on its own centre has no side to be on:
    /// above it.
    static func centre(forKnob knob: CGPoint, awayFrom box: CGPoint, pillSize size: CGSize,
                       within visible: CGRect) -> CGPoint {
        let away = CGPoint(x: knob.x - box.x, y: knob.y - box.y)
        let length = hypot(away.x, away.y)
        let direction = length > 0 ? CGPoint(x: away.x / length, y: away.y / length) : CGPoint(x: 0, y: -1)
        // The pill's centre is far enough along a direction that its *edge* is `standOff` from the
        // knob whichever way that is: a pill to the side of a knob stands half its width off, one
        // above or below it half its height.
        let halfWidth = size.width / 2, halfHeight = size.height / 2
        let reach = visible.insetBy(dx: halfWidth + Self.edgeInset, dy: halfHeight + Self.edgeInset)
        func standing(_ along: CGPoint) -> CGPoint {
            let toEdge = min(halfWidth / max(abs(along.x), 1e-6), halfHeight / max(abs(along.y), 1e-6))
            return CGPoint(x: knob.x + along.x * (Self.standOff + toEdge),
                           y: knob.y + along.y * (Self.standOff + toEdge))
        }
        func fits(_ point: CGPoint) -> Bool {
            point.x >= reach.minX && point.x <= reach.maxX && point.y >= reach.minY && point.y <= reach.maxY
        }
        let wanted = fits(standing(direction)) ? standing(direction)
            : fits(standing(CGPoint(x: -direction.x, y: -direction.y)))
            ? standing(CGPoint(x: -direction.x, y: -direction.y)) : standing(direction)
        return CGPoint(x: min(max(wanted.x, reach.minX), reach.maxX),
                       y: min(max(wanted.y, reach.minY), reach.maxY))
    }

    /// The knob was let go: the pill stays `lingerSeconds`, then goes. The host's label is told where
    /// it stands, because that is the one moment the artist — or a test — reads it.
    func release() {
        guard text != nil else { return }
        onChanged?()
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
        onChanged?()
    }
}
