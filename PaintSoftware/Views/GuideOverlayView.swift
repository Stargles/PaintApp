import UIKit

/// Draws the guide strokes bound to the frame under the playhead — Phase 7 item 2's "render only in
/// interpolate mode".
///
/// A canvas-sized overlay above every layer, not cel content, which is the whole point of a guide:
/// `PLAN.md` §6.1 makes it a **document-level object** so it can be shared across frames, and §0
/// requirement 6 makes it invisible outside interpolate mode. Neither is expressible as ink in a
/// layer, and drawing it through `setInterpolationImage` would be worse still — that seam *replaces*
/// the cel's display (`HANDOFF.md` §5, Phase 5), so a guide drawn through it would blank the frame it
/// is meant to annotate.
///
/// **Transparent to touch except on a handle**, which is `ShapeOverlayView`'s rule and is what lets
/// the canvas underneath keep drawing, filling and panning while a guide is on screen. Guide
/// *capture* stays where every other canvas gesture lives — `StrokeCanvasView`; the only touches
/// this view ever claims are the ones that land on a handle of an existing guide.
///
/// **Handles are live only while the Guide toggle is off, and they are drawn only then too.** The
/// toggle's whole promise is that a canvas drag draws a guide, with no exceptions — the artist arms
/// it, draws an arc, and it stays armed for the next one. Claiming a hitbox out of the middle of
/// that would mean a second guide started too near the first one's handle silently reshaped the
/// first instead. Disarming is what says "I am done drawing these", and that is the moment the
/// handles appear. Showing them while they cannot be grabbed would be the worse half of both.
final class GuideOverlayView: UIView {

    /// One drawn guide: the path, plus the handles that edit it.
    ///
    /// Carries the guide's `id` and each handle's **sample index** because that is all this view
    /// reports — it does no geometry. `CanvasManager.guideHandlePositions` places the handles and
    /// `GuideHandles.dragged` decides what moving one means; both are in the fast tier, and would not
    /// be if this view worked out either for itself.
    struct Guide: Equatable {
        struct Handle: Equatable {
            let sampleIndex: Int
            let position: CGPoint
        }
        let id: UUID
        let points: [CGPoint]
        let handles: [Handle]
    }

    // MARK: - Callbacks

    var onHandleDragBegan: ((UUID) -> Void)?
    /// Guide id, the sample index that handle edits, and where the finger is now — an absolute
    /// destination rather than a delta, exactly as `ShapeOverlayView` reports its own drags.
    var onHandleDragged: ((UUID, Int, CGPoint) -> Void)?
    var onHandleDragEnded: (() -> Void)?
    var onHandleDragCancelled: (() -> Void)?

    /// The committed guides to draw, in canvas coordinates.
    private var guides: [Guide] = []
    /// The guide currently under the pen, if any — drawn brighter, since it is the one being made.
    private var live: [CGPoint] = []
    /// Whether the handles are shown and grabbable — see the type comment.
    private var editable = false

    private var activeHandle: (guideID: UUID, sampleIndex: Int)?

    private static let handleRadius: CGFloat = 5
    /// How far from a handle's centre a touch still counts. Smaller than `ShapeOverlayView`'s 28,
    /// because a guide has five handles strung along a path the artist may also want to draw on,
    /// where a pending shape has a handful around content that is not editable yet.
    private static let handleReach: CGFloat = 18

    private let committedLayer = CAShapeLayer()
    private let liveLayer = CAShapeLayer()
    /// Dots at each end, so a guide reads as a *path with a direction* rather than a stray line.
    private let endpointLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        // On, and `hitTest` is the gate — the view is interactive only where a handle is.
        isUserInteractionEnabled = true
        backgroundColor = .clear

        // Dashed, and that is doing real work rather than decoration: a guide sits directly over the
        // artist's own linework, and a solid line of any colour reads as ink at a glance. A dash
        // never does.
        committedLayer.fillColor = UIColor.clear.cgColor
        committedLayer.strokeColor = UIColor.systemTeal.withAlphaComponent(0.85).cgColor
        committedLayer.lineWidth = 2
        committedLayer.lineDashPattern = [6, 4]
        committedLayer.lineJoin = .round
        committedLayer.lineCap = .round

        liveLayer.fillColor = UIColor.clear.cgColor
        liveLayer.strokeColor = UIColor.systemTeal.cgColor
        liveLayer.lineWidth = 2.5
        liveLayer.lineJoin = .round
        liveLayer.lineCap = .round

        endpointLayer.fillColor = UIColor.systemTeal.withAlphaComponent(0.9).cgColor
        endpointLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        endpointLayer.lineWidth = 1

        // White-filled and teal-ringed, the same read as `ShapeOverlayView`'s handles: a filled dot
        // in the overlay's own colour would be indistinguishable from the endpoint dots, which are
        // not draggable and mean something else.
        handleLayer.fillColor = UIColor.white.cgColor
        handleLayer.strokeColor = UIColor.systemTeal.cgColor
        handleLayer.lineWidth = 2

        layer.addSublayer(committedLayer)
        layer.addSublayer(liveLayer)
        layer.addSublayer(endpointLayer)
        layer.addSublayer(handleLayer)
    }

    // MARK: - Content

    /// Replaces everything drawn. Cheap enough to call from the coordinator's per-pass update, which
    /// is why it takes the whole set rather than diffing: a guide is tens of points and there are one
    /// or two of them.
    func update(guides newGuides: [Guide], live newLive: [CGPoint], editable newEditable: Bool) {
        guard guides != newGuides || live != newLive || editable != newEditable else { return }
        guides = newGuides
        live = newLive
        editable = newEditable
        // A guide that went away mid-drag (undo, a scrub off the in-between) must not leave a handle
        // latched, or the next touch anywhere would move a guide that is no longer on screen.
        if activeHandle.map({ hit in !newGuides.contains { $0.id == hit.guideID } }) == true {
            activeHandle = nil
        }
        redraw()
    }

    private func redraw() {
        // Implicit animations off, for the reason `ShapeOverlayView.update` documents at length: this
        // runs on every SwiftUI pass, and a quarter-second path animation restarted each time is what
        // makes an overlay lag visibly behind the pen.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let polylines = guides.map(\.points)
        committedLayer.path = path(through: polylines)
        liveLayer.path = live.count >= 2 ? path(through: [live]) : nil
        endpointLayer.path = endpointDots(for: polylines)
        handleLayer.path = editable ? handleDots(for: guides) : nil
        isHidden = guides.isEmpty && live.count < 2
    }

    private func path(through polylines: [[CGPoint]]) -> CGPath? {
        let path = CGMutablePath()
        var drew = false
        for points in polylines where points.count >= 2 {
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            drew = true
        }
        return drew ? path : nil
    }

    private func endpointDots(for polylines: [[CGPoint]]) -> CGPath? {
        let radius: CGFloat = 4
        let path = CGMutablePath()
        var drew = false
        for points in polylines where points.count >= 2 {
            for p in [points[0], points[points.count - 1]] {
                path.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius,
                                           width: radius * 2, height: radius * 2))
                drew = true
            }
        }
        return drew ? path : nil
    }

    private func handleDots(for guides: [Guide]) -> CGPath? {
        let radius = Self.handleRadius
        let path = CGMutablePath()
        var drew = false
        for guide in guides {
            for handle in guide.handles {
                path.addEllipse(in: CGRect(x: handle.position.x - radius, y: handle.position.y - radius,
                                           width: radius * 2, height: radius * 2))
                drew = true
            }
        }
        return drew ? path : nil
    }

    // MARK: - Hit testing

    /// The handle *nearest* the point, across every guide — not the first one in reach.
    /// `ShapeOverlayView` learned this the expensive way: taking the first match on overlapping
    /// hitboxes means one of them can never be grabbed at all, and five handles on a short guide
    /// overlap constantly.
    private func handle(at point: CGPoint) -> (guideID: UUID, sampleIndex: Int)? {
        var best: (hit: (guideID: UUID, sampleIndex: Int), distance: CGFloat)?
        for guide in guides {
            for handle in guide.handles {
                let distance = hypot(point.x - handle.position.x, point.y - handle.position.y)
                guard distance <= Self.handleReach else { continue }
                if best == nil || distance < best!.distance {
                    best = ((guide.id, handle.sampleIndex), distance)
                }
            }
        }
        return best?.hit
    }

    /// Claims only the handles, and only while they are shown. Everywhere else the overlay is
    /// transparent to touch, so the canvas underneath keeps receiving strokes, guide capture and
    /// two-finger gestures with a guide on screen.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard editable, !isHidden, isUserInteractionEnabled, handle(at: point) != nil else { return nil }
        return self
    }

    // MARK: - Handle dragging

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let hit = handle(at: touch.location(in: self)) else { return }
        activeHandle = hit
        onHandleDragBegan?(hit.guideID)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let hit = activeHandle, let touch = touches.first else { return }
        onHandleDragged?(hit.guideID, hit.sampleIndex, touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard activeHandle != nil else { return }
        activeHandle = nil
        onHandleDragEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard activeHandle != nil else { return }
        activeHandle = nil
        onHandleDragCancelled?()
    }
}
