import CoreGraphics

/// The shared nonlinear mapping seam for vector ink. Channels, parent dab walks and Distort
/// residues travel together; interpolation owns its fading separately.
enum VectorGeometryMap {
    static func stroke(_ stroke: VectorStroke, densify: Bool = false, region: CGRect? = nil,
                       by map: ([CGPoint]) -> [CGPoint]) -> VectorStroke {
        let divided = densify ? StrokeGeometry.subdivision(stroke.samples, maxSpacing: 1, followingCurve: true, region: region) : nil
        let samples = divided.map { StrokeSamples($0.samples, channels: stroke.samples.channels) } ?? stroke.samples
        let moved = map(samples.positions)
        guard moved.count == samples.count else { return stroke }
        // A brush whose rectangle passed near a curve but moved none of it does not rewrite ink.
        if densify, moved == samples.positions { return stroke }
        var result = stroke
        var i = -1
        result.samples = samples.replacingPositions({ _ in i += 1; return moved[i] }, angleRotation: 0)
        if let divided {
            result.sampleVisibilityThresholds = VectorCanvas.remapped(stroke.sampleVisibilityThresholds, onto: divided.parameters)
        }
        // A nonlinear map cannot keep the old stored rest spine. Keep the Distort residue: clearing
        // it would replace variable keystone widths with the stroke's widest footprint everywhere.
        result.placement = result.placement?.withoutStoredGeometry
        result.restWalk = nil
        if var lattice = result.lattice {
            let parent = densify ? StrokeGeometry.subdivision(lattice.samples, maxSpacing: 1, followingCurve: true, region: region) : nil
            let parentSamples = parent.map { StrokeSamples($0.samples, channels: lattice.samples.channels) } ?? lattice.samples
            let movedParent = map(parentSamples.positions)
            if movedParent.count == parentSamples.count {
                var j = -1
                let old = lattice
                lattice.samples = parentSamples.replacingPositions({ _ in j += 1; return movedParent[j] }, angleRotation: 0)
                if let divided, let parent {
                    lattice.parameters = divided.parameters.map { parent.newParameter(for: old.parentParameter(of: $0)) }
                }
                result.lattice = lattice
            }
        }
        // Nonlinear geometry must survive its first save without the ordinary quarter-point
        // packing changing the spine or rephasing the matching parent dab walk.
        return moved != samples.positions ? result.markedPrecise() : result
    }

    static func fill(_ fill: VectorFillElement, densify: Bool = false, region: CGRect? = nil,
                     by map: ([CGPoint]) -> [CGPoint]) -> VectorFillElement {
        guard let path = fill.cgPath else { return fill }
        let moved = densify ? densePath(path, region: region, by: map) : self.path(path, by: map)
        if densify, moved === path { return fill }
        return fill.reshaped(to: moved, paint: fill.paint.mapped(by: { map([$0]).first }) ?? fill.paint)
    }

    /// Local nonlinear mapping keeps untouched path commands, including control points, exact.
    /// A control point inside the field does not imply that its actual curve enters the field.
    private static func densePath(_ path: CGPath, region: CGRect?, by map: ([CGPoint]) -> [CGPoint]) -> CGPath {
        let result = CGMutablePath()
        var current = CGPoint.zero, start = CGPoint.zero, changed = false
        func mapped(_ points: [CGPoint]) -> [CGPoint] {
            let moved = map(points)
            guard moved.count == points.count else { return points }
            changed = changed || moved != points
            return moved
        }
        func divided(_ points: [CGPoint]) -> [CGPoint] {
            StrokeGeometry.subdivision(StrokeSamples(points: points), maxSpacing: 1, region: region).samples.map(\.point)
        }
        func line(to end: CGPoint) {
            let points = divided([current, end]), moved = mapped(points)
            if moved == points { result.addLine(to: end) }
            else { for point in moved.dropFirst() { result.addLine(to: point) } }
            current = end
        }
        func curve(_ segment: CGPath, unchanged: () -> Void, end: CGPoint) {
            guard let flat = StrokeGeometry.flattened(segment) else { unchanged(); current = end; return }
            var points: [CGPoint] = []
            flat.applyWithBlock { raw in
                if raw.pointee.type == .moveToPoint || raw.pointee.type == .addLineToPoint { points.append(raw.pointee.points[0]) }
            }
            let touches = region.map { box in
                zip(points, points.dropFirst()).contains { StrokeGeometry.clippedSegment($0, $1, to: box) != nil }
            } ?? true
            guard touches else { unchanged(); current = end; return }
            let dense = divided(points), moved = mapped(dense)
            if moved == dense { unchanged() }
            else { for point in moved.dropFirst() { result.addLine(to: point) } }
            current = end
        }
        path.applyWithBlock { raw in
            let item = raw.pointee
            switch item.type {
            case .moveToPoint: current = item.points[0]; start = current; result.move(to: mapped([current])[0])
            case .addLineToPoint: line(to: item.points[0])
            case .addQuadCurveToPoint:
                let c = item.points[0], end = item.points[1], segment = CGMutablePath()
                segment.move(to: current); segment.addQuadCurve(to: end, control: c)
                curve(segment, unchanged: { result.addQuadCurve(to: end, control: c) }, end: end)
            case .addCurveToPoint:
                let a = item.points[0], b = item.points[1], end = item.points[2], segment = CGMutablePath()
                segment.move(to: current); segment.addCurve(to: end, control1: a, control2: b)
                curve(segment, unchanged: { result.addCurve(to: end, control1: a, control2: b) }, end: end)
            case .closeSubpath: if current != start { line(to: start) }; result.closeSubpath()
            @unknown default: break
            }
        }
        return changed ? result : path
    }

    static func path(_ path: CGPath, by map: ([CGPoint]) -> [CGPoint]) -> CGPath {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            for i in 0..<pointCount(of: element.pointee.type) {
                points.append(element.pointee.points[i])
            }
        }
        let moved = map(points)
        guard moved.count == points.count, moved != points else { return path }

        let result = CGMutablePath()
        var next = 0
        path.applyWithBlock { element in
            let type = element.pointee.type
            let taken = pointCount(of: type)
            defer { next += taken }
            switch type {
            case .moveToPoint:
                result.move(to: moved[next])
            case .addLineToPoint:
                result.addLine(to: moved[next])
            case .addQuadCurveToPoint:
                result.addQuadCurve(to: moved[next + 1], control: moved[next])
            case .addCurveToPoint:
                result.addCurve(to: moved[next + 2], control1: moved[next], control2: moved[next + 1])
            case .closeSubpath:
                result.closeSubpath()
            @unknown default:
                break
            }
        }
        return result
    }

    static func pointCount(of type: CGPathElementType) -> Int {
        switch type {
        case .moveToPoint, .addLineToPoint: return 1
        case .addQuadCurveToPoint: return 2
        case .addCurveToPoint: return 3
        case .closeSubpath: return 0
        @unknown default: return 0
        }
    }

}

extension VectorElement {
    /// The geometry a Liquify tick can change; all paint properties remain with the element.
    func hasSameGeometry(as other: VectorElement) -> Bool {
        guard id == other.id else { return false }
        switch (self, other) {
        case (.stroke(let a), .stroke(let b)):
            return a.samples == b.samples && a.lattice == b.lattice && a.placement == b.placement
                && a.sampleVisibilityThresholds == b.sampleVisibilityThresholds
        case (.fill(let a), .fill(let b)):
            return a.pathData == b.pathData && a.paint == b.paint
        case (.image, .image), (.text, .text), (.video, .video), (.stream, .stream): return true
        default: return false
        }
    }
}
