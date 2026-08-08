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
/// **Transparent to touch, always.** `hitTest` returns nil unconditionally, so guide *capture* stays
/// where every other canvas gesture lives — `StrokeCanvasView` — and this view only ever displays.
/// Item 2's editable handles are the reason that is worth stating rather than assuming: when they
/// land they follow `ShapeOverlayView`'s pattern of claiming only the handle hitboxes, and the
/// unconditional nil here becomes a `handleKind(at:) != nil` test. Until then nothing here competes
/// for a touch.
final class GuideOverlayView: UIView {

    /// The committed guides to draw, in canvas coordinates.
    private var guides: [[CGPoint]] = []
    /// The guide currently under the pen, if any — drawn brighter, since it is the one being made.
    private var live: [CGPoint] = []

    private let committedLayer = CAShapeLayer()
    private let liveLayer = CAShapeLayer()
    /// Dots at each end, so a guide reads as a *path with a direction* rather than a stray line.
    private let endpointLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        isUserInteractionEnabled = false
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

        layer.addSublayer(committedLayer)
        layer.addSublayer(liveLayer)
        layer.addSublayer(endpointLayer)
    }

    // MARK: - Content

    /// Replaces everything drawn. Cheap enough to call from the coordinator's per-pass update, which
    /// is why it takes the whole set rather than diffing: a guide is tens of points and there are one
    /// or two of them.
    func update(guides newGuides: [[CGPoint]], live newLive: [CGPoint]) {
        guard guides != newGuides || live != newLive else { return }
        guides = newGuides
        live = newLive
        redraw()
    }

    private func redraw() {
        // Implicit animations off, for the reason `ShapeOverlayView.update` documents at length: this
        // runs on every SwiftUI pass, and a quarter-second path animation restarted each time is what
        // makes an overlay lag visibly behind the pen.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        committedLayer.path = path(through: guides)
        liveLayer.path = live.count >= 2 ? path(through: [live]) : nil
        endpointLayer.path = endpointDots(for: guides)
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

    /// Never claims a touch. See the type comment — capture lives in `StrokeCanvasView`, and the
    /// handles that will want a hitbox are not built yet.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
