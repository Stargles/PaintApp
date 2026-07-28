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
