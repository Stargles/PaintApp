import UIKit

/// Draws the guide strokes bound to the frame under the playhead — render only in interpolate mode.
///
/// A canvas-sized overlay above every layer, not cel content, which is the whole point of a guide:
/// it's a **document-level object** so it can be shared across frames, and invisible outside
/// interpolate mode. Neither is expressible as ink in a layer, and drawing it through
/// `setInterpolationImage` would be worse still — that seam *replaces* the cel's display, so a guide
/// drawn through it would blank the frame it is meant to annotate.
///
/// **Transparent to touch except on a handle**, which is `ShapeOverlayView`'s rule and is what lets
/// the canvas underneath keep drawing, filling and panning while a guide is on screen. Guide
/// *capture* stays where every other canvas gesture lives — `StrokeCanvasView`; the only touches
/// this view ever claims are the ones that land on a handle of an existing guide.
///
/// **Grips are live only while the Guide toggle is off, and they are drawn only then too.** The
/// toggle's whole promise is that a canvas drag draws a guide, with no exceptions — the artist arms
/// it, draws an arc, and it stays armed for the next one. Claiming a hitbox out of the middle of
/// that would mean a second guide started too near the first one's handle silently reshaped the
/// first instead. Disarming is what says "I am done drawing these", and that is the moment the grips
/// appear. Showing them while they cannot be grabbed would be the worse half of both.
///
/// **One editor at a time**, `Editing` says which. Shape handles and spacing dots both live on the
/// same polyline, so offering both at once would put two different meanings under one touch; they
/// are separate controls, and the bar is where the artist picks.
final class GuideOverlayView: UIView {

    /// Which editor the grips belong to — and therefore what dragging one means.
    enum Editing: Equatable {
        /// Guides are drawn, nothing is grabbable.
        case none
        /// Item 2: reshape the path. `Grip.index` is a **sample index**.
        case handles
        /// Item 5: retime a frame. `Grip.index` is a **spacing-chart stop**.
        case spacing
    }

    /// One drawn guide: the path, plus whatever grips the active editor puts on it.
    ///
    /// Carries the guide's `id` and each grip's index because that is all this view reports — it does
    /// no geometry of its own. `CanvasManager.guideHandlePositions` and `spacingChart(forGuide:)`
    /// place the grips and `GuideHandles.dragged` / `SpacingChart.moving` decide what moving one
    /// means; all of it is in the fast tier, and none of it would be if this view worked any of it out.
    struct Guide: Equatable {
        struct Grip: Equatable {
            /// A sample index under `.handles`, a chart stop under `.spacing`.
            let index: Int
            let position: CGPoint
        }
        let id: UUID
        let points: [CGPoint]
        let grips: [Grip]
    }

    // MARK: - Callbacks

    /// Every callback carries the `Editing` mode **captured at touch-down** rather than letting the
    /// receiver re-read it. The bar can be tapped mid-drag, and a gesture that began as a reshape and
    /// committed as a retime would be silent — the same reasoning as `StrokeCanvasView`'s
    /// `guideStartTime` and `inBetweenCelID`.
    var onGripDragBegan: ((UUID, Editing) -> Void)?
    /// Guide id, the mode, the grip's index, and where the finger is now — an absolute destination
    /// rather than a delta, exactly as `ShapeOverlayView` reports its own drags.
    var onGripDragged: ((UUID, Editing, Int, CGPoint) -> Void)?
    var onGripDragEnded: ((Editing) -> Void)?
    var onGripDragCancelled: ((Editing) -> Void)?

    /// The committed guides to draw, in canvas coordinates.
    private var guides: [Guide] = []
    /// The guide currently under the pen, if any — drawn brighter, since it is the one being made.
    private var live: [CGPoint] = []
    /// Which editor is offered — see the type comment.
    private var editing: Editing = .none

    private var activeGrip: (guideID: UUID, index: Int, editing: Editing)?

    private static let gripRadius: CGFloat = 5
    /// How far from a grip's centre a touch still counts. Smaller than `ShapeOverlayView`'s 28,
    /// because a guide's grips are strung along a path the artist may also want to draw on, where a
    /// pending shape has a handful around content that is not editable yet.
    private static let gripReach: CGFloat = 18

    private let committedLayer = CAShapeLayer()
    private let liveLayer = CAShapeLayer()
    /// Dots at each end, so a guide reads as a *path with a direction* rather than a stray line.
    private let endpointLayer = CAShapeLayer()
    private let gripLayer = CAShapeLayer()

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

        // White-filled and ringed, the same read as `ShapeOverlayView`'s handles: a filled dot in the
        // overlay's own colour would be indistinguishable from the endpoint dots, which are not
        // draggable and mean something else. The ring colour is what tells the two editors apart —
        // set in `redraw`, since it changes with the mode.
        gripLayer.fillColor = UIColor.white.cgColor
        gripLayer.lineWidth = 2

        layer.addSublayer(committedLayer)
        layer.addSublayer(liveLayer)
        layer.addSublayer(endpointLayer)
        layer.addSublayer(gripLayer)
    }

    // MARK: - Content

    /// Replaces everything drawn. Cheap enough to call from the coordinator's per-pass update, which
    /// is why it takes the whole set rather than diffing: a guide is tens of points and there are one
    /// or two of them.
    func update(guides newGuides: [Guide], live newLive: [CGPoint], editing newEditing: Editing) {
        guard guides != newGuides || live != newLive || editing != newEditing else { return }
        guides = newGuides
        live = newLive
        editing = newEditing
        // A guide that went away mid-drag (undo, a scrub off the in-between) must not leave a grip
        // latched, or the next touch anywhere would move a guide that is no longer on screen.
        if activeGrip.map({ hit in !newGuides.contains { $0.id == hit.guideID } }) == true {
            activeGrip = nil
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
        gripLayer.path = editing == .none ? nil : gripDots(for: guides)
        // Teal for geometry, matching the path it reshapes; amber for timing, which is not a
        // statement about where the line goes and should not read as one.
        gripLayer.strokeColor = (editing == .spacing ? UIColor.systemOrange : UIColor.systemTeal).cgColor
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

    private func gripDots(for guides: [Guide]) -> CGPath? {
        let radius = Self.gripRadius
        let path = CGMutablePath()
        var drew = false
        for guide in guides {
            for grip in guide.grips {
                path.addEllipse(in: CGRect(x: grip.position.x - radius, y: grip.position.y - radius,
                                           width: radius * 2, height: radius * 2))
                drew = true
            }
        }
        return drew ? path : nil
    }

    // MARK: - Hit testing

    /// The grip *nearest* the point, across every guide — not the first one in reach.
    /// `ShapeOverlayView` learned this the expensive way: taking the first match on overlapping
    /// hitboxes means one of them can never be grabbed at all, and grips on a short guide overlap
    /// constantly.
    private func grip(at point: CGPoint) -> (guideID: UUID, index: Int)? {
        var best: (hit: (guideID: UUID, index: Int), distance: CGFloat)?
        for guide in guides {
            for grip in guide.grips {
                let distance = hypot(point.x - grip.position.x, point.y - grip.position.y)
                guard distance <= Self.gripReach else { continue }
                if best == nil || distance < best!.distance {
                    best = ((guide.id, grip.index), distance)
                }
            }
        }
        return best?.hit
    }

    /// Claims only the grips, and only while they are shown. Everywhere else the overlay is
    /// transparent to touch, so the canvas underneath keeps receiving strokes, guide capture and
    /// two-finger gestures with a guide on screen.
    /// **The ownership half of `hitTest`, asked on its own.** `hitTest` answers two questions at
    /// once — *is this touch mine* and *which view of mine is hit* — and only the first is the
    /// arbitration this canvas gets wrong. Split out, it is what `CanvasView.Coordinator.canvasChrome(at:)`
    /// asks to build `CanvasTouchInputs.chrome`, so the five overlays' claims reach the one function
    /// that says who owns a touch instead of each being re-derived by whoever needs to know. The
    /// geometry stays here, untouched.
    ///
    /// **`editing` in place of an `isActive` flag is the one thing that makes this overlay
    /// different**, and it is why a guide grip turns up in more of `CanvasTouchOwner`'s
    /// owned-by-more-than-one rows than anything else: guide editing is a mode none of the four
    /// inputs to that type can see, so the model has to treat a guide claim as reachable in every
    /// state.
    func claimsTouch(at point: CGPoint) -> Bool {
        editing != .none && !isHidden && isUserInteractionEnabled && grip(at: point) != nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard claimsTouch(at: point) else { return nil }
        return self
    }

    // MARK: - Grip dragging

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let hit = grip(at: touch.location(in: self)) else { return }
        activeGrip = (hit.guideID, hit.index, editing)
        onGripDragBegan?(hit.guideID, editing)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let hit = activeGrip, let touch = touches.first else { return }
        onGripDragged?(hit.guideID, hit.editing, hit.index, touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let hit = activeGrip else { return }
        activeGrip = nil
        onGripDragEnded?(hit.editing)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard let hit = activeGrip else { return }
        activeGrip = nil
        onGripDragCancelled?(hit.editing)
    }
}
