import CoreGraphics

/// **What is under a point: every kind of element's drawn shape, answered in one place.**
///
/// The text tool's re-open tap, the motion-group retagging tap and Select's Tap mode each need to know
/// which object a finger is on, and each wants the same thing from every kind: the shape the artist
/// sees, not a region near its stored coordinates. This is that — a stroke's inked width, a fill's
/// path, a text box's or a placed picture's quad — as pure functions over a display list, so the
/// question can be put to the list as it is stored (`VectorCanvas.topmostText`) or to the list as it
/// is *shown* (`CanvasManager.selectObject(at:)`, which asks the posed one).
///
/// **The point and the elements must be in the same space.** Nothing here maps anything.
enum VectorHitTest {

    /// How far beyond its drawn shape an object still answers a touch — a fingertip's worth, added to
    /// a stroke's own radius so a hairline stays tappable and to a text box's edge so a turned box is
    /// no harder to hit than an upright one.
    static let fingertip: CGFloat = 6

    /// The topmost element — the last in the display list — that `accepts` and whose drawn shape covers
    /// `point`, or nil for bare canvas.
    static func topmost(in elements: [VectorElement], at point: CGPoint, slop: CGFloat = fingertip,
                        accepting accepts: (VectorElement) -> Bool = { _ in true }) -> VectorElement? {
        elements.last { accepts($0) && covers($0, point: point, slop: slop) }
    }

    /// Whether `element`'s drawn shape covers `point`.
    ///
    /// **A stroke is its ink**: the centre line widened by the stamp radius at full pressure — the
    /// widest the stroke ever draws — and by `slop`. **An eraser mark is not an object a touch can be
    /// on**: it has no ink of its own, only a hole, and tapping the hole is tapping what shows through.
    ///
    /// **A fill is its path**, under the fill's own rule, so the hole in a ring is not the ring. A
    /// gradient is a fill. **Text is the box, not the glyphs** — tapping the hole in an "O" is tapping
    /// the text, and a glyph-exact test would make a light face nearly untappable
    /// (`VectorCanvas.topmostText` carries the argument) — and a placed picture, a video and a stream
    /// are their quads.
    static func covers(_ element: VectorElement, point: CGPoint, slop: CGFloat = fingertip) -> Bool {
        switch element {
        case .stroke(let stroke):
            guard stroke.composite == .paint, !stroke.samples.isEmpty else { return false }
            let limit = slop + StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush, size: stroke.size)
            return StrokeGeometry.distanceSquared(from: point, toPolyline: stroke.samples) <= limit * limit
        case .fill(let fill):
            return fill.cgPath?.contains(point, using: fill.evenOddFill ? .evenOdd : .winding) ?? false
        case .text(let text):
            return text.frame.contains(point, slop: slop)
        case .image(let image):
            return VectorCanvas.quad(of: image).contains(point, using: .winding)
        case .video(let video):
            return VectorCanvas.quad(of: video).contains(point, using: .winding)
        case .stream(let stream):
            return VectorCanvas.quad(of: stream).contains(point, using: .winding)
        }
    }

    /// How far an outline stands off the shape it holds, so no membership rule is ever asked a
    /// boolean question about two coincident edges — Core Graphics' `subtracting` of a path from an
    /// identical one is not guaranteed empty, and Enclosed asks exactly that.
    static let outlineMargin: CGFloat = 2

    /// **A closed path that holds the whole of `element`'s drawn shape**, standing `outlineMargin`
    /// off it — its quad for text and the placed kinds, which is exact however the box has been
    /// turned, and the box around its ink for a stroke or a fill. What a Tap selection traces: the
    /// loop that stands in for the object, which the selection's rule then reads as it reads any loop
    /// (`CanvasManager.lassoLoops(of:in:posedBy:)`). Nil for an element with no shape to hold — a
    /// stroke with no samples, an unreadable fill.
    static func outline(of element: VectorElement) -> CGPath? {
        switch element {
        case .stroke(let stroke):
            guard !stroke.samples.isEmpty else { return nil }
            var box = CGRect.null
            for sample in stroke.samples { box = box.union(CGRect(origin: sample.point, size: .zero)) }
            let reach = StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush, size: stroke.size)
            return CGPath(rect: box.insetBy(dx: -(reach + outlineMargin), dy: -(reach + outlineMargin)), transform: nil)
        case .fill(let fill):
            guard let box = fill.cgPath?.boundingBoxOfPath, !box.isNull else { return nil }
            return CGPath(rect: box.insetBy(dx: -outlineMargin, dy: -outlineMargin), transform: nil)
        case .text(let text):
            return grownQuad(through: text.frame.corners)
        case .image(let image):
            return grownQuad(through: image.corners)
        case .video(let video):
            return grownQuad(through: video.corners)
        case .stream(let stream):
            return grownQuad(through: stream.corners)
        }
    }

    /// The quad through `corners` with each corner moved `outlineMargin` further from the quad's centre.
    private static func grownQuad(through corners: [CGPoint]) -> CGPath? {
        guard corners.count == 4 else { return nil }
        let centre = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        let path = CGMutablePath()
        for (index, corner) in corners.enumerated() {
            let dx = corner.x - centre.x, dy = corner.y - centre.y
            let length = max((dx * dx + dy * dy).squareRoot(), .leastNonzeroMagnitude)
            let grown = CGPoint(x: corner.x + dx / length * outlineMargin, y: corner.y + dy / length * outlineMargin)
            if index == 0 { path.move(to: grown) } else { path.addLine(to: grown) }
        }
        path.closeSubpath()
        return path
    }
}
