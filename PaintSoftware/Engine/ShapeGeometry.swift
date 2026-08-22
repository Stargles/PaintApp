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

    enum Kind: String, CaseIterable, Codable {
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

    /// Where on the outline the artist's pen started, in the same `u ∈ [0, 1)` every other method
    /// here speaks. A *material* coordinate: it labels a point of the ink in the shape's own
    /// unrotated frame, so `rotation` edits, axis drags, the follow-the-finger scale and the
    /// two-finger snap all carry the drawn portion along without knowing it exists.
    var spanStart: CGFloat = 0

    /// Signed fraction of the outline the pen turned through: `|spanSweep| ∈ (0, 1]`, and the sign
    /// is the direction it was drawn in. `1` is a whole outline and is what everything defaults to,
    /// which is why a shape built without a span behaves exactly as it did before spans existed.
    ///
    /// Deliberately *not* a pair of endpoints. An interval on a closed curve has no canonical start,
    /// and two wrapped parameters cannot tell a 20° arc from a 340° one nor say which way it runs;
    /// `(start, signed sweep)` carries seam-crossing, direction and overshoot in one encoding
    /// because this is a difference of *unwrapped* parameters and is never reduced mod 1.
    var spanSweep: CGFloat = 1

    init(kind: Kind, startPoint: CGPoint, endPoint: CGPoint, rotation: CGFloat = 0,
         spanStart: CGFloat = 0, spanSweep: CGFloat = 1) {
        self.kind = kind
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.rotation = rotation
        self.spanStart = spanStart
        self.spanSweep = spanSweep
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
    /// circumference.
    ///
    /// The oval branch integrates rather than approximating. It used Ramanujan's formula, which is
    /// fine for a whole ellipse and says nothing at all about a portion of one — and now that a
    /// stroke may have drawn only a portion, one implementation has to serve both. Simpson over the
    /// smooth integrand is *more* accurate than Ramanujan anyway (measured: identical at 1:1,
    /// 1.7e-4 relative at 3.75:1, 2.8e-3 at 20:1, with Simpson the accurate one).
    var outlineLength: CGFloat {
        switch kind {
        case .line:
            return hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        case .rectangle:
            let r = boundingRect
            return 2 * (r.width + r.height)
        case .oval:
            let r = boundingRect
            return Self.ellipseArcLength(a: r.width / 2, b: r.height / 2, startTurn: 0, sweep: 1)
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

    // MARK: - The drawn portion of the outline
    //
    // A stroke that followed an oval part of the way round leaves ink on part of that oval. There is
    // no second kind of shape for that and no flag saying "this one is an arc": there is an ellipse,
    // and there is how far round it the pen turned. `spanStart`/`spanSweep` are that number, and
    // everything below is that number *used* — never tested. At the defaults `(0, 1)` every
    // expression here reduces to the whole-outline one it replaced, character for character.

    /// Arc length of the drawn portion of the outline.
    var spanLength: CGFloat {
        switch kind {
        case .line, .rectangle:
            // Both parameterise by arc length, so the drawn fraction *is* the length fraction.
            return abs(spanSweep) * outlineLength
        case .oval:
            let r = boundingRect
            return Self.ellipseArcLength(a: r.width / 2, b: r.height / 2,
                                         startTurn: spanStart, sweep: spanSweep)
        }
    }

    /// The point at `s ∈ [0, 1]` along the *drawn* arc, in the shape's unrotated frame.
    ///
    /// The wrap is conditional, and that is what lets `pointOnOutline` stay untouched. With
    /// `spanStart ∈ [0, 1)` and `spanSweep ∈ [−1, 1]`, `u` lies in `(−1, 2)`, so one subtraction of
    /// `floor(u)` always suffices — and at the defaults `u = s ∈ [0, 1]` never trips it at all, so
    /// `u = 1` still lands on the seam rather than being folded back to `u = 0`. An unconditional
    /// modulo would fold it, and a line's far endpoint would collapse onto its near one.
    func pointOnSpan(at s: CGFloat) -> CGPoint {
        let t = max(0, min(1, s))
        var u = spanStart + spanSweep * t
        if u < 0 || u > 1 { u -= floor(u) }
        return pointOnOutline(at: u)
    }

    /// Where along the *drawn* arc `point` (unrotated frame) falls, as `s ∈ [0, 1]`. Inverse of
    /// `pointOnSpan` on the drawn portion.
    ///
    /// A point lying *outside* the drawn portion clamps to the far end rather than the near one.
    /// That cannot arise from a detected shape — the measured span is the min/max envelope of the
    /// stroke's own unwrapped trace and so contains every one of its samples by construction — only
    /// from a hand-built geometry.
    func spanParameter(of point: CGPoint) -> CGFloat {
        let u = outlineParameter(of: point)
        let sign: CGFloat = spanSweep < 0 ? -1 : 1
        var d = (u - spanStart) * sign
        if d < 0 || d > 1 { d -= floor(d) }
        return max(0, min(1, d / max(abs(spanSweep), 1e-6)))
    }

    /// The period, in units of the drawn arc's own parameter `s`, over which a pressure profile
    /// repeats — which is how the pressure walk wraps a full loop and clamps an open one without
    /// asking which it is holding.
    ///
    /// A whole closed outline gives 1, so the profile's last entry sits one period behind its first
    /// and the seam interpolates. A line gives 1e30, so the wrap partner is unreachably far away and
    /// the interpolation weight saturates at the end value — the clamp, arrived at rather than
    /// branched to. A quarter arc gives 4: the partner is three units away in `s` and contributes
    /// under 1%, so the ends behave as open without anything having tested for it. (1e30 and not
    /// `.infinity`, which would make the ratio `inf/inf` and hence `NaN`; not
    /// `.greatestFiniteMagnitude`, to leave overflow headroom.)
    var pressurePeriod: CGFloat { isClosed ? 1 / max(abs(spanSweep), 1e-6) : 1e30 }

    /// Arc length of the ellipse with semi-axes `a`, `b` over `sweep` turns of *eccentric* angle
    /// starting at `startTurn` turns, by composite Simpson over `∫√(a²sin²t + b²cos²t) dt`.
    ///
    /// 32 panels; the integrand is smooth and periodic, so this is accurate to far better than the
    /// sub-point precision anything here needs, and one implementation serves both the whole outline
    /// and a portion of it. Cost is 32 `sqrt`/`sin`/`cos` per call, called once per accepted
    /// candidate and once per collapse — unmeasurable beside stamping the stroke onto a raster.
    private static func ellipseArcLength(a: CGFloat, b: CGFloat,
                                         startTurn: CGFloat, sweep: CGFloat) -> CGFloat {
        guard a > 0 || b > 0, sweep != 0 else { return 0 }
        let panels = 32
        let h = sweep / CGFloat(panels)
        // `u` is in turns and `pointOnOutline` reads eccentric angle `2πu − π`, so `dt = 2π du`.
        func speed(_ u: CGFloat) -> CGFloat {
            let t = u * 2 * .pi - .pi
            let sx = a * sin(t), sy = b * cos(t)
            return 2 * .pi * (sx * sx + sy * sy).squareRoot()
        }
        var total = speed(startTurn) + speed(startTurn + sweep)
        for i in 1..<panels {
            let weight: CGFloat = i % 2 == 0 ? 2 : 4
            total += weight * speed(startTurn + h * CGFloat(i))
        }
        return abs(total * h / 3)
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
    ///
    /// **That flip is orientation-*reversing*, and a span would notice.** `abs` mirrors the box
    /// through the anchor, so a drawn portion would need `spanSweep` negated and `spanStart`
    /// reflected — unlike `draggingEdge`, whose crossing is a half turn and needs only half a turn
    /// of `spanStart`. No such code is written here, deliberately: ovals have no corner handles
    /// (`ShapeOverlayView.handleLayout` gives them four axis handles and a rotation knob), and every
    /// kind that *can* reach this path carries the default `(0, 1)`, which mirroring leaves alone.
    /// Speculative code on an unreachable path that no test can exercise is a worse trap than a
    /// named gap — so if oval corner handles are ever added, the mirror correction belongs here.
    ///
    /// **`anchor` has no default, and that is the whole point.** Passing `nil` re-derives it from the
    /// shape *this* frame, which is correct for a single call and wrong for every frame after the
    /// first once a drag crosses over: `corner` then names a handle that is no longer the one under
    /// the finger, so `canvasAnchor(opposite:)` returns the finger's own corner and the rectangle
    /// walks along behind it — the owner's "it pushes the opposite edge", measured at 128 pt of travel
    /// over twenty frames and a rect frozen at 12 pt wide
    /// (`testACornerDragWithoutALatchedAnchorWalksTheOppositeEdge`). There is no way to recover the
    /// latched point from `(self, corner, point)` alone — a touch far outside the rect is nearer some
    /// corner other than the dragged one, so "opposite the nearest corner" disagrees with the label —
    /// so the only fix is that every call site states which it means. A silent default is what let
    /// this ship.
    func draggingCorner(_ corner: Corner, to point: CGPoint, anchor: CGPoint?) -> ShapeGeometry {
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
    ///
    /// `anchor` keeps its default here where `draggingCorner`'s is gone, and the asymmetry is
    /// measured rather than stylistic: an axis drag *rewrites* `rotation` to the anchor→touch bearing,
    /// so the anchor lands back on the same local node every frame and re-deriving it per frame is a
    /// fixed point — sixty unlatched frames at four rotations move it 0.0000 pt. A corner drag carries
    /// `rotation` through unchanged and relabels which corner is which when it flips, so the same
    /// re-derivation walks the shape across the canvas. Latching is still what the UI does for both.
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
            // A drag taken through its own anchor flips `theta` by exactly π, because `d` reverses
            // while staying on the same line. The paragraph above says that costs nothing — "the π
            // difference between a handle and its opposite is a difference in `rotation`'s value
            // only, never in the shape drawn" — and that sentence stops being true the moment a
            // span exists. Half a turn of the frame sends a fixed local `u` to the antipodal point:
            //     centre + R(θ+π)·P(u) = centre − R(θ)·P(u) = centre + R(θ)·P(u + ½)
            // so the ink would teleport across the ellipse mid-gesture — measured at 157 to 240 pt
            // on a 120 × 70. Half a turn of `spanStart` is the exact inverse, not an approximation,
            // so this is a change of chart and the geometry drawn stays continuous through the
            // crossing. It relies on frame-to-frame continuity of the drag, which the latched-anchor
            // design already relies on.
            if cos(rotation) * cos(theta) + sin(rotation) * sin(theta) < 0 {
                let halfTurned = result.spanStart + 0.5
                result.spanStart = halfTurned - halfTurned.rounded(.down)
            }
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

    // MARK: - Dragging the outline itself

    /// Shortest distance from `point` (canvas space) to the outline **as it is drawn** — i.e. the
    /// rotated outline, the one the artist can see and is aiming at.
    ///
    /// Measured against the *whole* outline rather than the drawn span: `rotatedCGPath` is what
    /// `ShapeOverlayView` strokes as its blue guide, and it traces the whole shape even when the
    /// artist only drew a quarter of it. Aiming at what is on screen is the point.
    ///
    /// The probe is carried into the shape's own unrotated frame first, which turns every branch
    /// below into an axis-aligned problem — the same move `draggingEdge` makes, for the same reason.
    func distanceToOutline(from point: CGPoint) -> CGFloat {
        let local = rotation == 0 ? point : point.applying(rotationTransform.inverted())
        switch kind {
        case .line:
            return Self.distance(from: local, toSegment: startPoint, endPoint)
        case .rectangle:
            let r = boundingRect
            let tl = CGPoint(x: r.minX, y: r.minY), tr = CGPoint(x: r.maxX, y: r.minY)
            let br = CGPoint(x: r.maxX, y: r.maxY), bl = CGPoint(x: r.minX, y: r.maxY)
            // The boundary, not the filled box: the interior of a rectangle is not its outline, and
            // claiming it would stop the artist drawing inside a pending shape.
            return min(min(Self.distance(from: local, toSegment: tl, tr),
                           Self.distance(from: local, toSegment: tr, br)),
                       min(Self.distance(from: local, toSegment: br, bl),
                           Self.distance(from: local, toSegment: bl, tl)))
        case .oval:
            return Self.distance(from: local, toEllipseIn: boundingRect)
        }
    }

    /// Whether `point` is close enough to the outline to grab it.
    ///
    /// `reach` is a **canvas**-point radius, and the caller is expected to have divided its
    /// screen-point constant by `canvasScale` before handing it over — the split
    /// `ObjectTransformFrame.handleLayout` states: the view owns the constant, the geometry owns the
    /// direction. An outline is a hairline, so a reach that shrank with the artwork would make the
    /// whole shape ungrabbable the moment the artist zoomed out, which is `ADD_TEXT.md` §1's bug.
    func isOnOutline(_ point: CGPoint, within reach: CGFloat) -> Bool {
        distanceToOutline(from: point) <= reach
    }

    /// The geometry produced by dragging the outline from `grabPoint` to `point`: every control
    /// point moves by that one delta and **nothing else changes** — same size, same rotation, same
    /// drawn span.
    ///
    /// `self` is the geometry latched when the finger went down, not the live one, which is
    /// `ObjectTransformDrag`'s discipline: measuring each delta against the answer the previous delta
    /// produced is stable until a mid-drag pinch-zoom moves the reference frame under the gesture.
    /// Driving it with one delta or sixty gives the same answer for the same final point.
    ///
    /// `center` is the midpoint of the two anchors, so it translates with them and
    /// `rotationTransform` — which pivots about it — comes along untouched. That is why a rotated
    /// shape does not unwind as it moves.
    func draggingBody(to point: CGPoint, from grabPoint: CGPoint) -> ShapeGeometry {
        let dx = point.x - grabPoint.x, dy = point.y - grabPoint.y
        var result = self
        result.startPoint = CGPoint(x: startPoint.x + dx, y: startPoint.y + dy)
        result.endPoint = CGPoint(x: endPoint.x + dx, y: endPoint.y + dy)
        return result
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        guard length2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Distance from `p` to the ellipse inscribed in `rect`, both in the same unrotated frame.
    ///
    /// Closed form for this is a quartic, and the usual alternative — Newton on Eberly's root-finding
    /// form — needs special cases at both axes, at the centre, and on a circle. A coarse angular scan
    /// followed by a golden-section refinement of the winning bracket has none of those: it converges
    /// unconditionally, degrades gracefully on a degenerate ellipse, and can never return less than
    /// the scan already proved reachable. It costs a few hundred trig evaluations, paid once per
    /// touch-down against a budget of one frame.
    private static func distance(from p: CGPoint, toEllipseIn rect: CGRect) -> CGFloat {
        let a = rect.width / 2, b = rect.height / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        guard a > 0 || b > 0 else { return hypot(p.x - c.x, p.y - c.y) }
        func distance(atAngle t: CGFloat) -> CGFloat {
            hypot(p.x - (c.x + a * cos(t)), p.y - (c.y + b * sin(t)))
        }
        let steps = 256
        let step = 2 * CGFloat.pi / CGFloat(steps)
        var bestIndex = 0, coarse = CGFloat.greatestFiniteMagnitude
        for i in 0..<steps {
            let d = distance(atAngle: CGFloat(i) * step)
            if d < coarse { coarse = d; bestIndex = i }
        }
        // The true minimum lies in the bracket either side of the winning sample, and inside one
        // 1.4° window the distance is unimodal for any ellipse worth drawing.
        var lo = CGFloat(bestIndex - 1) * step, hi = CGFloat(bestIndex + 1) * step
        let invPhi = (CGFloat(5).squareRoot() - 1) / 2
        var x1 = hi - invPhi * (hi - lo), x2 = lo + invPhi * (hi - lo)
        var f1 = distance(atAngle: x1), f2 = distance(atAngle: x2)
        for _ in 0..<40 {
            if f1 < f2 {
                hi = x2; x2 = x1; f2 = f1
                x1 = hi - invPhi * (hi - lo); f1 = distance(atAngle: x1)
            } else {
                lo = x1; x1 = x2; f1 = f2
                x2 = lo + invPhi * (hi - lo); f2 = distance(atAngle: x2)
            }
        }
        // `coarse` is a distance to a point that really is on the ellipse, so it is a valid upper
        // bound whatever the refinement did — the `min` is what makes a non-unimodal bracket safe
        // rather than merely unlikely.
        return min(coarse, min(f1, f2))
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

/// Nothing persists a `ShapeGeometry` today — it is live gesture state, and what reaches disk is the
/// baked `VectorStroke`, a flat list of samples with no shape identity at all. The conformance is
/// written now anyway so that the day a live shape is autosaved, or shapes become re-editable, this
/// is a decode and not a migration.
///
/// `init(from:)`/`encode(to:)` live in an extension so declaring them doesn't suppress the
/// memberwise initialiser every call site builds with — the `VectorStroke` idiom. And the decoder is
/// hand-written rather than synthesised because **synthesised `Decodable` ignores property
/// defaults**: a record written before spans existed has no `spanSweep` key, and the synthesised
/// version would throw rather than read it as the whole outline it described.
extension ShapeGeometry: Codable {

    enum CodingKeys: String, CodingKey {
        case kind, startPoint, endPoint, rotation, spanStart, spanSweep
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        startPoint = try c.decode(CGPoint.self, forKey: .startPoint)
        endPoint = try c.decode(CGPoint.self, forKey: .endPoint)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        // A record written before partial ovals existed described a whole one.
        spanStart = try c.decodeIfPresent(CGFloat.self, forKey: .spanStart) ?? 0
        spanSweep = try c.decodeIfPresent(CGFloat.self, forKey: .spanSweep) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(startPoint, forKey: .startPoint)
        try c.encode(endPoint, forKey: .endPoint)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(spanStart, forKey: .spanStart)
        try c.encode(spanSweep, forKey: .spanSweep)
    }
}
