import UIKit

/// **What every handle drag on the canvas shares, once per canvas** — pushed down by `CanvasView` to
/// the four overlays that have a handle to hold (`ObjectTransformOverlayView`,
/// `FloatingPieceOverlayView`, `TextTransformOverlayView`, `ShapeOverlayView`), so the rule has one
/// source and wiring it is one assignment each.
final class HandleDragAssist {

    /// How many touches are on the canvas right now, the dragging one included — the host's
    /// `TouchCountRecognizer`, which sees every touch however it landed. A touch that joins mid-drag
    /// is what slows the drag or snaps a turn (`PrecisionDrag`, TODO (146), (151)).
    ///
    /// The touch asked about is counted whether or not the counter has heard of it, which is how the
    /// baseline is taken at the drag's own touch-down (`TouchCountRecognizer.activeCount(including:)`);
    /// nil asks for the count as it stands.
    var touchesDown: (UITouch?) -> Int = { _ in 0 }

    /// The one pill for the whole canvas, which says what angle a held knob has its box at
    /// (`RotationReadoutView`, TODO (151)).
    weak var readout: RotationReadoutView?
}

/// **One handle drag in flight on one overlay** — which handle, the touch that owns it, what a touch
/// that joins it does to it, and the angle pill that goes with a turn. The overlay holds one of these
/// from touch-down to the end of the drag and nothing else about the glass: a second touch on the view
/// neither starts another drag nor moves this one.
///
/// **What a joined touch does depends on the handle** (`Precision`): a handle that moves or sizes the
/// box has its point slowed to a fifth, one that turns it has its turn rounded to
/// `RotationAngle.snapIncrement`, and a handle with neither (a smart shape's corner, say) is read at
/// the pen's own pace. The drag asks `PrecisionDrag` for the pen's *effective* point and every
/// consumer downstream reads that, so no handle has to know.
///
/// **The pill belongs to the drags that turn.** It is one view shared by every overlay, so only a
/// drag that is turning shows it, lets it linger when the knob is let go (`finish`), and takes it down
/// when its overlay stands down (`abandon`).
///
/// For `FloatingPieceOverlayView`, whose drags are read from pan recognizers, the handle *is* the pan
/// and the touch is the one that landed on it.
struct HandleDrag<Handle> {

    /// What a touch that joins the drag does to it.
    enum Precision {
        /// Nothing: the handle is read at the pen's own pace.
        case unassisted
        /// The handle moves or sizes the box, so its point is slowed.
        case slowsPoint
        /// The handle turns the box, so its turn lands on a round angle.
        case snapsAngle
    }

    /// The handle the drag is on.
    let handle: Handle
    /// Whether the handle turns the box — the drags that read their angle out.
    let turns: Bool
    private weak var touch: UITouch?
    private var precision: PrecisionDrag?
    private let assist: HandleDragAssist

    /// - Parameters:
    ///   - point: where the drag began, which is also where its effective point starts.
    ///   - touch: the touch that began it, counted in the baseline whether or not the counter has
    ///     heard of it yet.
    init(_ handle: Handle, touch: UITouch?, at point: CGPoint, precision kind: Precision,
         assist: HandleDragAssist) {
        self.handle = handle
        self.touch = touch
        self.assist = assist
        turns = kind == .snapsAngle
        precision = kind == .unassisted
            ? nil : PrecisionDrag(startingAt: point, touchesDown: assist.touchesDown(touch), turns: turns)
    }

    // MARK: - The touch

    /// Whether the touch is still on the glass.
    var isLive: Bool {
        guard let touch else { return false }
        return touch.phase != .ended && touch.phase != .cancelled
    }

    /// The dragging touch, if it is among `touches`.
    func touch(in touches: Set<UITouch>) -> UITouch? {
        guard let touch, touches.contains(touch) else { return nil }
        return touch
    }

    /// Whether touches that ended or were cancelled end the drag: its touch is among them, or it is
    /// no longer anywhere to be found — in which case there is nothing left for the drag to follow.
    func ends(with touches: Set<UITouch>) -> Bool {
        touch.map(touches.contains) ?? true
    }

    // MARK: - The point

    /// The point the drag acts on for the pen's current position `raw`: its own while nothing has
    /// joined, a fifth of its travel while a touch has joined a handle that moves or sizes the box.
    mutating func advance(to raw: CGPoint) -> CGPoint {
        guard var drag = precision else { return raw }
        let point = drag.point(for: raw, touchesDown: assist.touchesDown(nil))
        precision = drag
        return point
    }

    /// Whether, as of the last point advanced to, a touch has joined a handle that turns the box — so
    /// the turn is to land on a round angle (`RotationAngle.snapped`).
    var snapsAngle: Bool { precision?.snapsAngle ?? false }

    // MARK: - The pill

    /// Shows `angle` beside the knob held, while this drag turns the box. `knob` and `centre` are in
    /// `plane`'s coordinates — the overlay's own.
    func showAngle(_ angle: CGFloat, knob: CGPoint, centre: CGPoint, in plane: UIView) {
        assist.readout?.show(angle: angle, knob: knob, centre: centre, in: plane)
    }

    /// The knob was let go: the pill stays a moment so the artist can read what the turn landed on.
    func finish() {
        if turns { assist.readout?.release() }
    }

    /// The overlay stood down under the drag: the pill goes now.
    func abandon() {
        if turns { assist.readout?.hide() }
    }
}
