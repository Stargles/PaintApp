import CoreGraphics
import Foundation

/// One input sample of a vector stroke, in the stroke's own canvas-point space at draw time.
struct VectorSample: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var pressure: CGFloat
    var point: CGPoint { CGPoint(x: x, y: y) }
}

/// The geometry of a smart shape — a line, rectangle, or oval defined by two opposing anchor points
/// plus a rotation about their midpoint.
///
/// Deliberately *only* geometry: the brush/colour/size a shape is drawn with belongs to the gesture
/// that produced it (see `CanvasManager`'s shape-gesture state), not here. Keeping this a
/// dependency-free value type (CoreGraphics and nothing else) is what lets `ShapeDetector` and this
/// file compile into the test target as well as the app, so the detection and stroke-collapsing math
/// can be tested as pure logic without a simulator.
///
/// The outline parameterisation (`pointOnOutline` / `outlineParameter`) is the core of
/// stroke collapsing: it gives every shape a single `u ∈ [0, 1]` coordinate running along its
/// outline, so a freehand stroke and the shape it snapped to can be compared position-for-position.
struct ShapeGeometry: Equatable {

    enum Kind: String, CaseIterable {
        case line
        case rectangle
        case oval
    }

    var kind: Kind
    /// Line: the first endpoint. Rectangle/oval: one corner of the unrotated bounding box.
    var startPoint: CGPoint
    /// Line: the second endpoint. Rectangle/oval: the opposing corner.
    var endPoint: CGPoint
    /// Rotation about `center`, applied on top of the unrotated geometry above.
    var rotation: CGFloat

    init(kind: Kind, startPoint: CGPoint, endPoint: CGPoint, rotation: CGFloat = 0) {
        self.kind = kind
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.rotation = rotation
    }

    // MARK: - Derived geometry

    /// Midpoint of the two anchors — also the centre of `boundingRect`, and the pivot `rotation`
    /// turns about.
    var center: CGPoint {
        CGPoint(x: (startPoint.x + endPoint.x) / 2, y: (startPoint.y + endPoint.y) / 2)
    }

    /// The unrotated bounding box of the two anchors.
    var boundingRect: CGRect {
        CGRect(x: min(startPoint.x, endPoint.x), y: min(startPoint.y, endPoint.y),
               width: abs(endPoint.x - startPoint.x), height: abs(endPoint.y - startPoint.y))
    }

    /// A closed shape's outline wraps around; a line's has two distinct ends. Drives whether the
    /// collapsed stroke closes its loop and whether pressure interpolates across the seam.
    var isClosed: Bool { kind != .line }

    /// `rotation` about `center` as an affine transform. Everything that needs to place this shape in
    /// canvas space goes through here, so the preview, the handles, and the baked stroke can't drift.
    var rotationTransform: CGAffineTransform {
        guard rotation != 0 else { return .identity }
        let c = center
        return CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: rotation)
            .translatedBy(x: -c.x, y: -c.y)
    }

    /// The outline as a path, before `rotation`.
    var cgPath: CGPath {
        switch kind {
        case .line:
            let path = CGMutablePath()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            return path
        case .rectangle:
            return CGPath(rect: boundingRect, transform: nil)
        case .oval:
            return CGPath(ellipseIn: boundingRect, transform: nil)
        }
    }

    /// The outline as a path, rotated into canvas space — what the user actually sees.
    var rotatedCGPath: CGPath {
        guard rotation != 0 else { return cgPath }
        var t = rotationTransform
        return cgPath.copy(using: &t) ?? cgPath
    }

    // MARK: - Outline parameterisation

    /// Total length of the outline: a line's length, a rectangle's perimeter, an oval's
    /// circumference (Ramanujan's approximation, well under 1% error for any realistic aspect).
    var outlineLength: CGFloat {
        switch kind {
        case .line:
            return hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        case .rectangle:
            let r = boundingRect
            return 2 * (r.width + r.height)
        case .oval:
            let r = boundingRect
            let a = r.width / 2, b = r.height / 2
            return .pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
        }
    }

    /// The point at outline parameter `u ∈ [0, 1]`, in the shape's *unrotated* frame.
    ///
    /// Lines run start→end. Rectangles run clockwise from the top-left corner. Ovals run from
    /// angle −π through +π, so `u = 0` and `u = 1` meet at the same place and the seam closes.
    func pointOnOutline(at u: CGFloat) -> CGPoint {
        let u = max(0, min(1, u))
        switch kind {
        case .line:
            return CGPoint(x: startPoint.x + (endPoint.x - startPoint.x) * u,
                           y: startPoint.y + (endPoint.y - startPoint.y) * u)
        case .rectangle:
            let r = boundingRect
            let d = u * 2 * (r.width + r.height)
            if d <= r.width { return CGPoint(x: r.minX + d, y: r.minY) }
            if d <= r.width + r.height { return CGPoint(x: r.maxX, y: r.minY + (d - r.width)) }
            if d <= 2 * r.width + r.height {
                return CGPoint(x: r.maxX - (d - r.width - r.height), y: r.maxY)
            }
            return CGPoint(x: r.minX, y: r.maxY - (d - 2 * r.width - r.height))
        case .oval:
            let r = boundingRect
            let angle = u * 2 * .pi - .pi
            return CGPoint(x: r.midX + (r.width / 2) * cos(angle),
                           y: r.midY + (r.height / 2) * sin(angle))
        }
    }

    /// Inverse of `pointOnOutline`: where along the outline `point` (unrotated frame) projects,
    /// as `u ∈ [0, 1]`.
    func outlineParameter(of point: CGPoint) -> CGFloat {
        switch kind {
        case .line:
            let dx = endPoint.x - startPoint.x, dy = endPoint.y - startPoint.y
            let len2 = dx * dx + dy * dy
            guard len2 > 0 else { return 0 }
            return max(0, min(1, ((point.x - startPoint.x) * dx + (point.y - startPoint.y) * dy) / len2))
        case .rectangle:
            let r = boundingRect
            let perimeter = 2 * (r.width + r.height)
            guard perimeter > 0 else { return 0 }
            return Self.clockwisePerimeterDistance(of: point, in: r) / perimeter
        case .oval:
            let r = boundingRect
            // Normalising by each radius maps the ellipse to a unit circle first, so the parameter
            // matches `pointOnOutline`'s angle even on a very eccentric oval.
            let rx = max(r.width / 2, 0.0001), ry = max(r.height / 2, 0.0001)
            let angle = atan2((point.y - r.midY) / ry, (point.x - r.midX) / rx)
            return max(0, min(1, (angle + .pi) / (2 * .pi)))
        }
    }

    /// Clockwise distance from `rect`'s top-left corner to the perimeter point nearest `point`,
    /// matching the walk order `pointOnOutline` uses for rectangles.
    private static func clockwisePerimeterDistance(of point: CGPoint, in rect: CGRect) -> CGFloat {
        let toLeft = abs(point.x - rect.minX), toRight = abs(point.x - rect.maxX)
        let toTop = abs(point.y - rect.minY), toBottom = abs(point.y - rect.maxY)
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        let nearest = min(min(toLeft, toRight), min(toTop, toBottom))
        if nearest == toTop { return x - rect.minX }
        if nearest == toRight { return rect.width + (y - rect.minY) }
        if nearest == toBottom { return rect.width + rect.height + (rect.maxX - x) }
        return 2 * rect.width + rect.height + (rect.maxY - y)
    }

    // MARK: - Handle dragging

    /// Which corner of `boundingRect` a resize handle sits on.
    ///
    /// Declared here rather than on `ShapeOverlayView` so the drag math below can live in this
    /// dependency-free file — which is what makes it unit-testable without a simulator. The overlay
    /// typealiases straight to these, so its callback signatures are unchanged.
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Which edge of `boundingRect` a resize handle sits on. On an oval these are the axis handles.
    enum Edge {
        case top, bottom, left, right
    }

    /// Where the handle diagonally opposite `corner` sits **in canvas space** — on the glass, where
    /// the artist can see it. This is the point a corner drag has to hold still.
    ///
    /// It is not the same as the opposite corner of `boundingRect`: that is a *local* coordinate, and
    /// `rotationTransform` pivots about a centre that a corner drag moves. Pinning the local one
    /// leaves the anchor travelling across the canvas by (I − R(θ))·(C − C′) every frame, which the
    /// drag then feeds back into itself — the owner's "weird movement".
    func canvasAnchor(opposite corner: Corner) -> CGPoint {
        let r = boundingRect
        let local: CGPoint
        switch corner {
        case .topLeft:     local = CGPoint(x: r.maxX, y: r.maxY)
        case .topRight:    local = CGPoint(x: r.minX, y: r.maxY)
        case .bottomLeft:  local = CGPoint(x: r.maxX, y: r.minY)
        case .bottomRight: local = CGPoint(x: r.minX, y: r.minY)
        }
        return local.applying(rotationTransform)
    }

    /// Where the axis handle opposite `edge` sits in canvas space — the node an axis drag holds.
    /// Same argument as `canvasAnchor(opposite:)` for corners.
    func canvasAnchor(opposite edge: Edge) -> CGPoint {
        let r = boundingRect
        let local: CGPoint
        switch edge {
        case .top:    local = CGPoint(x: r.midX, y: r.maxY)
        case .bottom: local = CGPoint(x: r.midX, y: r.minY)
        case .left:   local = CGPoint(x: r.maxX, y: r.midY)
        case .right:  local = CGPoint(x: r.minX, y: r.midY)
        }
        return local.applying(rotationTransform)
    }

    /// The geometry produced by dragging `corner` to `point` (a raw touch location in canvas space):
    /// the dragged corner follows the touch while the diagonally opposite corner stays **fixed on
    /// screen**. `rotation` is carried through unchanged — a corner drag resizes, it doesn't turn.
    ///
    /// The anchor is a canvas position, not a local one, and everything else is derived from it: the
    /// touch is measured from the anchor and rotated into the shape's own axes (`v`), which gives the
    /// new half-extents directly, and the new centre is placed back through R(θ) from the anchor. The
    /// anchor's canvas position is invariant by construction. Anchoring in the local frame instead is
    /// the bug this replaces — see `canvasAnchor(opposite:)`.
    ///
    /// Crossing the anchor **flips** rather than inverting: `abs` on each component keeps the rect
    /// well-formed and mirrors it through the anchor, which is the shipped behaviour
    /// `testDraggingACornerPastTheAnchorFlipsRatherThanInverting` pins. Note that at the instant of
    /// the crossing the anchor stops being the *opposite* corner and becomes the dragged one's near
    /// neighbour, which is why callers latch `anchor` at touch-down: recomputing it per frame would
    /// jump to a different point the moment the drag crossed over.
    func draggingCorner(_ corner: Corner, to point: CGPoint, anchor: CGPoint? = nil) -> ShapeGeometry {
        let a = anchor ?? canvasAnchor(opposite: corner)
        let d = CGPoint(x: point.x - a.x, y: point.y - a.y)
        let ci = cos(-rotation), si = sin(-rotation)
        // The touch in the shape's own axes, measured from the anchor.
        let v = CGPoint(x: d.x * ci - d.y * si, y: d.x * si + d.y * ci)
        let hw = abs(v.x) / 2, hh = abs(v.y) / 2
        let cf = cos(rotation), sf = sin(rotation)
        let mid = CGPoint(x: (v.x / 2) * cf - (v.y / 2) * sf,
                          y: (v.x / 2) * sf + (v.y / 2) * cf)
        // The new centre, back in canvas axes: half of `v`, rotated, out from the anchor.
        let nc = CGPoint(x: a.x + mid.x, y: a.y + mid.y)
        var result = self
        result.startPoint = CGPoint(x: nc.x - hw, y: nc.y - hh)
        result.endPoint = CGPoint(x: nc.x + hw, y: nc.y + hh)
        return result
    }

    /// The geometry produced by dragging the `edge` handle to `point` (canvas space).
    ///
    /// **An oval's axis drag obeys one rule, and everything else is derived from it: the node
    /// diametrically opposite the one being dragged stays fixed on the canvas.** With the anchor
    /// pinned and the dragged node under the touch, the segment between the two carries both facts an
    /// axis handle can express — its *length* is the axis extent, and its *direction* is the shape's
    /// rotation. So a drag stretches and turns at once, and neither is bolted on: they are two
    /// readings of the same segment. The owner asked for exactly this ("dragging an oval stretches it
    /// in the direction, but I also want it to be able to rotate; the rule is just that the opposite
    /// node across the ellipse is anchored"), and it is the same model the rectangle's corner drag
    /// already uses — an anchor latched at touch-down, the dragged handle on the touch.
    ///
    /// Two earlier behaviours are still deliberately gone. It transformed about the **centre** (the
    /// owner: the oval "treats the center as the transformation origin instead of the opposite side
    /// node"), which is what this anchoring replaces. And it took rotation from the *finger's bearing
    /// about the centre* while separately resizing about that same centre — two different pivots
    /// fighting over one drag, which is why it felt like a wrench. Rotation here is not a second
    /// gesture read off the touch; it is the anchor-to-touch direction, which is the only direction
    /// the axis can have once both of its ends are known.
    ///
    /// The perpendicular half-axis is carried through unchanged, so a drag lengthens one axis and
    /// turns the shape without fattening it. Rotation is measured per-handle, because the four
    /// handles sit on different ends of two different axes: `.right`/`.left` are the ends of the
    /// local +x axis (canvas direction `(cos θ, sin θ)`), `.bottom`/`.top` the ends of the local +y
    /// axis (`(−sin θ, cos θ)`), and dragging the near end rather than the far one reverses the
    /// segment. An ellipse is symmetric under a half turn, so the π difference between a handle and
    /// its opposite is a difference in `rotation`'s value only, never in the shape drawn.
    ///
    /// A touch landing exactly on the anchor has no direction to read, so it collapses the axis and
    /// keeps the rotation the shape already had rather than snapping it to an arbitrary angle.
    ///
    /// Every other kind moves just that one edge of the bounding box, in the shape's local frame, and
    /// leaves `rotation` alone. That branch is currently unreachable from the UI — `ShapeOverlayView`
    /// gives rectangles four corner handles and no mid-edge ones.
    func draggingEdge(_ edge: Edge, to point: CGPoint, anchor: CGPoint? = nil) -> ShapeGeometry {
        let r = boundingRect
        var result = self
        if kind == .oval {
            let a = anchor ?? canvasAnchor(opposite: edge)
            let d = CGPoint(x: point.x - a.x, y: point.y - a.y)
            let length = hypot(d.x, d.y)
            // Half the dragged axis is half the anchor→touch segment; the other axis is untouched.
            let hw = (edge == .left || edge == .right) ? length / 2 : r.width / 2
            let hh = (edge == .top || edge == .bottom) ? length / 2 : r.height / 2
            // The centre is the segment's midpoint, which is what puts the anchor and the touch on
            // opposite ends of it.
            let nc = CGPoint(x: a.x + d.x / 2, y: a.y + d.y / 2)
            let theta: CGFloat
            if length > 1e-9 {
                switch edge {
                case .right:  theta = atan2(d.y, d.x)     // anchor is the left node: +x axis
                case .left:   theta = atan2(-d.y, -d.x)   // anchor is the right node: −x axis
                case .bottom: theta = atan2(-d.x, d.y)    // anchor is the top node: +y axis
                case .top:    theta = atan2(d.x, -d.y)    // anchor is the bottom node: −y axis
                }
            } else {
                theta = rotation
            }
            result.startPoint = CGPoint(x: nc.x - hw, y: nc.y - hh)
            result.endPoint = CGPoint(x: nc.x + hw, y: nc.y + hh)
            result.rotation = theta
            return result
        }
        let localPoint = point.applying(rotationTransform.inverted())
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch edge {
        case .top:    minY = localPoint.y
        case .bottom: maxY = localPoint.y
        case .left:   minX = localPoint.x
        case .right:  maxX = localPoint.x
        }
        result.startPoint = CGPoint(x: min(minX, maxX), y: min(minY, maxY))
        result.endPoint = CGPoint(x: max(minX, maxX), y: max(minY, maxY))
        return result
    }

    // MARK: - Follow-the-finger dragging

    /// The reference frame captured the first time a freshly-detected shape starts following the
    /// finger that drew it (the pen is still down after hold-detection fired). Every later sample is
    /// measured against this, which is what makes the drag *relative*.
    struct FollowFrame: Equatable {
        /// Bearing from the shape's centre to the finger at capture time.
        var angle: CGFloat
        /// Distance from the shape's centre to the finger at capture time.
        var radius: CGFloat
        var halfWidth: CGFloat
        var halfHeight: CGFloat
        /// The shape's *own* rotation at capture time — the finger's bearing change is added on top
        /// of this, never used in its place. Using it in its place is a bug that shipped once: a
        /// shape detected at an angle snapped back to axis-aligned the instant the finger moved.
        var rotation: CGFloat
    }

    /// Captures the frame for a follow-the-finger drag starting at `point`.
    func followFrame(startingAt point: CGPoint) -> FollowFrame {
        let c = center
        return FollowFrame(angle: atan2(point.y - c.y, point.x - c.x),
                           radius: hypot(point.x - c.x, point.y - c.y),
                           halfWidth: abs(endPoint.x - startPoint.x) / 2,
                           halfHeight: abs(endPoint.y - startPoint.y) / 2,
                           rotation: rotation)
    }

    /// The geometry produced by the finger having moved to `point`, given the frame captured when
    /// the drag began: the finger's angle about the centre sets rotation, and its distance sets a
    /// uniform scale. The centre itself is fixed, so the shape grows and turns about the spot it
    /// was detected at rather than chasing the finger.
    ///
    /// Only meaningful for rectangles and ovals — a line follows its endpoint directly.
    func following(_ point: CGPoint, from frame: FollowFrame) -> ShapeGeometry {
        let c = center
        let deltaRotation = atan2(point.y - c.y, point.x - c.x) - frame.angle
        let scale = frame.radius > 0 ? hypot(point.x - c.x, point.y - c.y) / frame.radius : 1
        let halfWidth = frame.halfWidth * scale
        let halfHeight = frame.halfHeight * scale
        var result = self
        result.startPoint = CGPoint(x: c.x - halfWidth, y: c.y - halfHeight)
        result.endPoint = CGPoint(x: c.x + halfWidth, y: c.y + halfHeight)
        result.rotation = frame.rotation + deltaRotation
        return result
    }

    // MARK: - Two-finger constraint

    /// The shape as drawn while the two-finger constraint is engaged: a line snaps to 15°
    /// increments, a rectangle/oval becomes a square/circle about its own centre.
    ///
    /// One implementation shared by the on-screen preview and the commit path — when these were
    /// separate, a snapped shape previewed snapped but baked unsnapped.
    var constrained: ShapeGeometry {
        switch kind {
        case .line:
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let snapped = Self.snapAngle(angle, toIncrement: .pi / 12)
            let distance = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
            var result = self
            result.endPoint = CGPoint(x: startPoint.x + cos(snapped) * distance,
                                      y: startPoint.y + sin(snapped) * distance)
            return result
        case .rectangle, .oval:
            let r = boundingRect
            let side = max(r.width, r.height)
            var result = self
            result.startPoint = CGPoint(x: r.midX - side / 2, y: r.midY - side / 2)
            result.endPoint = CGPoint(x: r.midX + side / 2, y: r.midY + side / 2)
            return result
        }
    }

    /// Snaps an angle (radians) to the nearest multiple of `increment`.
    static func snapAngle(_ angle: CGFloat, toIncrement increment: CGFloat) -> CGFloat {
        guard increment > 0 else { return angle }
        return (angle / increment).rounded() * increment
    }
}
