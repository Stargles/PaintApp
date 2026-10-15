import CoreGraphics
import UIKit

/// The evaluated compact gesture field. Geometry is indexed in 64-point bins; displacement is
/// evaluated only where ink or a destination pixel asks for it. Native tip masks are shared by
/// reference, so a 4096² sweep has no 134 MB displacement grid and no per-dab bitmap allocation.
final class LiquifyField {
    enum PreparedTip {
        case round(hardness: CGFloat)
        case image(mask: Int?, cosine: CGFloat, sine: CGFloat)
    }
    struct Step {
        let center: CGPoint
        let radius: CGFloat
        let alpha: CGFloat
        let tip: PreparedTip
        let travel: CGPoint
        let bounds: CGRect
        let substeps: Int
        let pushClamp: CGFloat
    }
    private struct Bin: Hashable { let x: Int; let y: Int }
    private let binSide: CGFloat = 64
    private var bins: [Bin: [Int]] = [:]
    private(set) var steps: [Step] = []
    private(set) var bounds: CGRect = .null
    private(set) var replacementBounds: CGRect = .null
    private(set) var definition: LiquifyDeformation?
    let mode: LiquifyMode
    let power: CGFloat
    let selection: CGPath?
    private var masks: [AlphaMask] = []
    private var maskIndices: [BrushTextureRef: Int] = [:]
    private var paper: (mask: Int, side: CGFloat, depth: CGFloat)?
    private var selectionEdges: [BoundarySegment] = []
    private var selectionBins: [Bin: [Int]] = [:]

    init(mode: LiquifyMode, power: Double, selection: CGPath?, texture: BrushTextureSettings?) {
        self.mode = mode; self.power = CGFloat(min(1, max(0, power)))
        self.selection = selection
        if let texture, let index = maskIndex(texture.mask) {
            paper = (index, max(BrushTextureSettings.minimumTileSize, texture.tileSize.rounded()), CGFloat(texture.depth))
        }
        indexSelectionBoundary()
    }

    convenience init(_ gesture: LiquifyDeformation) {
        self.init(mode: gesture.mode, power: gesture.power, selection: gesture.selectionPath,
                  texture: gesture.brush.texture)
        definition = gesture
        let collector = BrushStamper.CollectingDabTarget(tracksTravel: true)
        var walk = BrushStamper.LiveWalk(seed: gesture.seed)
        for sample in gesture.path.samples {
            walk.stamp(to: sample, into: collector, brush: gesture.brush, color: .white, brushSize: gesture.size)
        }
        walk.finish(into: collector, brush: gesture.brush, color: .white, brushSize: gesture.size)
        append(collector.drain())
    }

    static func replacementBounds(of dab: BrushStamper.BakedDab) -> CGRect {
        let source: CGRect
        switch dab.tip {
        case .round: source = CGRect(x: dab.center.x - dab.radius, y: dab.center.y - dab.radius, width: dab.radius * 2, height: dab.radius * 2)
        case .image(_, let angle): source = dabImageBounds(at: dab.center, diameter: dab.radius * 2, angle: angle)
        }
        // Conservative picture padding, not a displacement cap: flow can exceed one. The
        // invertible map preserves its footprint; the extra apron also covers pixel filtering.
        return source.insetBy(dx: -dab.radius * 0.08 - 1, dy: -dab.radius * 0.08 - 1).integral
    }

    func append(_ dabs: [(BrushStamper.BakedDab, CGPoint)]) {
        for (dab, travel) in dabs {
            let box: CGRect, tip: PreparedTip
            switch dab.tip {
            case .round(let hardness):
                box = CGRect(x: dab.center.x - dab.radius, y: dab.center.y - dab.radius,
                             width: dab.radius * 2, height: dab.radius * 2)
                tip = .round(hardness: min(hardness, max(0, 1 - 1 / dab.radius)))
            case .image(let ref, let angle):
                box = dabImageBounds(at: dab.center, diameter: dab.radius * 2, angle: angle)
                tip = .image(mask: maskIndex(ref), cosine: cos(angle), sine: sin(angle))
            }
            let index = steps.count
            let travelLength = hypot(travel.x, travel.y)
            steps.append(Step(center: dab.center, radius: dab.radius, alpha: dab.alpha, tip: tip,
                              travel: travel, bounds: box, substeps: substepCount(dab),
                              pushClamp: travelLength > 0 ? min(1, dab.radius * 0.08 / travelLength) : 0))
            bounds = bounds.isNull ? box : bounds.union(box)
            let replacement = Self.replacementBounds(of: dab)
            replacementBounds = replacementBounds.isNull ? replacement : replacementBounds.union(replacement)
            let reach = box.insetBy(dx: -dab.radius * 0.08 - 1, dy: -dab.radius * 0.08 - 1)
            let loX = Int(floor(reach.minX / binSide)), hiX = Int(floor(reach.maxX / binSide))
            let loY = Int(floor(reach.minY / binSide)), hiY = Int(floor(reach.maxY / binSide))
            for y in loY...hiY { for x in loX...hiX { bins[Bin(x: x, y: y), default: []].append(index) } }
        }
    }

    var isEmpty: Bool { power == 0 || steps.isEmpty || (mode == .push && steps.allSatisfy { $0.travel == .zero }) }
    var retainedByteCount: Int { steps.count * MemoryLayout<Step>.stride + bins.values.reduce(0) { $0 + $1.count * 8 } + selectionEdges.count * MemoryLayout<BoundarySegment>.stride + selectionBins.values.reduce(0) { $0 + $1.count * 8 } + masks.reduce(0) { $0 + $1.bytes.count } }

    func intersects(_ points: [CGPoint]) -> Bool {
        let region = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.001, height: 0.001))) }
        return !bounds.isNull && region.intersects(bounds)
    }

    private func permits(_ point: CGPoint) -> Bool {
        selection?.contains(point, using: VectorCanvas.lassoFillRule) ?? true
    }

    /// Sequential composition in shown space. A new step searches at the already-moved point, so
    /// the field follows the finger across bins instead of applying each input delta many times.
    struct MapResult {
        let point: CGPoint
        let evaluations: Int
    }
    func map(_ point: CGPoint) -> CGPoint { mapResult(point).point }
    func mapResult(_ point: CGPoint) -> MapResult {
        guard permits(point) else { return MapResult(point: point, evaluations: 0) }
        var result = point, next = 0, evaluations = 0
        while let i = candidate(at: result, limit: next, reverse: false) {
            let step = steps[i], h = 1 / CGFloat(step.substeps)
            for _ in 0..<step.substeps {
                evaluations += 1
                let v = velocity(step, at: result)
                if v == .zero { break }
                result.x += v.x * h; result.y += v.y * h
            }
            next = i + 1
        }
        return MapResult(point: result, evaluations: evaluations)
    }

    struct InverseResult {
        enum Failure: String { case iterationLimit, nonFinite, residual, selection }
        let point: CGPoint
        let residual: CGFloat
        let failure: Failure?
        let evaluations: Int
        var converged: Bool { failure == nil }
    }
    struct InverseSolution {
        let point: CGPoint
        let failure: InverseResult.Failure?
        let evaluations: Int
        var converged: Bool { failure == nil }
    }
    func inverse(_ point: CGPoint) -> CGPoint { inverseSolution(point).point }

    /// Production sampling reverses the identical contracting Euler submaps. Its convergence
    /// checks concern the source coordinate; it does not re-forward every destination pixel.
    func inverseSolution(_ point: CGPoint) -> InverseSolution {
        guard point.x.isFinite, point.y.isFinite else { return InverseSolution(point: point, failure: .nonFinite, evaluations: 0) }
        guard permits(point) else { return InverseSolution(point: point, failure: nil, evaluations: 0) }
        var result = point, previous = steps.count, evaluations = 0
        var solved = true
        while let i = candidate(at: result, limit: previous, reverse: true) {
            let step = steps[i], h = 1 / CGFloat(step.substeps)
            evaluations += 1
            if velocity(step, at: result) != .zero {
                for _ in 0..<step.substeps {
                    let destination = result
                    let solution = Self.inverseSubmap(at: destination, pushTravel: mode == .push ? step.travel : nil) { source in
                        let v = velocity(step, at: source)
                        return CGPoint(x: destination.x - h * v.x, y: destination.y - h * v.y)
                    }
                    evaluations += solution.evaluations
                    if solution.failure == .nonFinite {
                        return InverseSolution(point: point, failure: .nonFinite, evaluations: evaluations)
                    }
                    result = solution.point; solved = solved && solution.converged
                }
            }
            previous = i
        }
        let failure: InverseResult.Failure? = !solved ? .iterationLimit : !permits(result) ? .selection : nil
        return InverseSolution(point: result, failure: failure, evaluations: evaluations)
    }

    /// Push has one fixed travel direction per dab. Aitken extrapolation along its dominant axis
    /// can solve that scalar contraction sooner, but only an improved full 2D residual accepts it.
    /// Every evaluation, including safeguard checks, shares the ordinary 32-evaluation limit.
    static func inverseSubmap(at destination: CGPoint, pushTravel: CGPoint?,
                              iterate: (CGPoint) -> CGPoint) -> InverseSolution {
        var source = destination, cached: CGPoint?
        var evaluations = 0
        func next(_ point: CGPoint) -> CGPoint { evaluations += 1; return iterate(point) }
        func finish(_ point: CGPoint, _ failure: InverseResult.Failure? = nil) -> InverseSolution {
            InverseSolution(point: point, failure: failure, evaluations: evaluations)
        }
        while evaluations < 32 || cached != nil {
            let first = cached ?? next(source)
            cached = nil
            guard first.x.isFinite, first.y.isFinite else { return finish(destination, .nonFinite) }
            if hypot(first.x - source.x, first.y - source.y) < 0.000000000001 { return finish(first) }
            guard let pushTravel else { source = first; continue }
            guard evaluations < 32 else { return finish(first, .iterationLimit) }
            let second = next(first)
            guard second.x.isFinite, second.y.isFinite else { return finish(destination, .nonFinite) }
            if hypot(second.x - first.x, second.y - first.y) < 0.000000000001 { return finish(second) }
            guard evaluations < 32 else { return finish(second, .iterationLimit) }
            let ordinaryNext = next(second)
            guard ordinaryNext.x.isFinite, ordinaryNext.y.isFinite else { return finish(destination, .nonFinite) }
            let ordinaryResidual = hypot(ordinaryNext.x - second.x, ordinaryNext.y - second.y)
            if ordinaryResidual < 0.000000000001 { return finish(ordinaryNext) }
            let useX = abs(pushTravel.x) >= abs(pushTravel.y)
            let firstDelta = useX ? first.x - source.x : first.y - source.y
            let secondDelta = useX ? second.x - first.x : second.y - first.y
            let denominator = secondDelta - firstDelta
            if denominator != 0, evaluations < 32 {
                let proposal = CGPoint(x: source.x - (first.x - source.x) * firstDelta / denominator,
                                       y: source.y - (first.y - source.y) * firstDelta / denominator)
                if proposal.x.isFinite, proposal.y.isFinite {
                    let proposedNext = next(proposal)
                    let residual = hypot(proposedNext.x - proposal.x, proposedNext.y - proposal.y)
                    if proposedNext.x.isFinite, proposedNext.y.isFinite, residual < ordinaryResidual {
                        if residual < 0.000000000001 { return finish(proposedNext) }
                        source = proposal; cached = proposedNext; continue
                    }
                }
            }
            source = second; cached = ordinaryNext
        }
        return finish(source, .iterationLimit)
    }

    /// Optional destination-space diagnostic. A forward map can magnify sub-ULP source error by
    /// hundreds of pixels while the independently verified inverse still samples the right ink.
    func inverseResult(_ point: CGPoint) -> InverseResult {
        let solution = inverseSolution(point)
        guard solution.converged else {
            return InverseResult(point: solution.point, residual: .infinity, failure: solution.failure, evaluations: solution.evaluations)
        }
        let mapped = mapResult(solution.point)
        let residual = hypot(mapped.point.x - point.x, mapped.point.y - point.y)
        let failure: InverseResult.Failure? = (!residual.isFinite || residual >= 0.005) ? .residual : nil
        return InverseResult(point: solution.point, residual: residual, failure: failure, evaluations: solution.evaluations + mapped.evaluations)
    }

    private func bin(_ point: CGPoint) -> Bin {
        Bin(x: Int(floor(point.x / binSide)), y: Int(floor(point.y / binSide)))
    }

    private func candidate(at point: CGPoint, limit: Int, reverse: Bool) -> Int? {
        // The velocity is zero outside each fully indexed footprint. Contracting Euler submaps
        // preserve that support, so the current bin contains every potentially affecting step.
        guard let candidates = bins[bin(point)] else { return nil }
        var lo = 0, hi = candidates.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if candidates[mid] < limit { lo = mid + 1 } else { hi = mid }
        }
        if reverse { return lo > 0 ? candidates[lo - 1] : nil }
        return lo < candidates.count ? candidates[lo] : nil
    }

    private func maskIndex(_ reference: BrushTextureRef) -> Int? {
        if let index = maskIndices[reference] { return index }
        guard let image = BrushTextureStore.mask(for: reference), let mask = AlphaMask(image) else { return nil }
        let index = masks.count
        masks.append(mask); maskIndices[reference] = index
        return index
    }

    /// Velocity vanishes continuously at the footprint and selection boundary. Bounding its gradient
    /// before choosing a substep count makes the map invertible even at native image-tip edges.
    private func velocity(_ step: Step, at point: CGPoint) -> CGPoint {
        guard step.bounds.contains(point), permits(point) else { return .zero }
        let radial = CGPoint(x: point.x - step.center.x, y: point.y - step.center.y)
        let strength = coverage(step, radial: radial, at: point) * power * selectionCoverage(point)
        guard strength > 0 else { return .zero }
        let raw: CGPoint
        switch mode {
        case .push:
            let scale = step.pushClamp * strength
            return CGPoint(x: step.travel.x * scale, y: step.travel.y * scale)
        case .pinch: raw = CGPoint(x: -radial.x * 0.08, y: -radial.y * 0.08)
        case .expand: raw = CGPoint(x: radial.x * 0.08, y: radial.y * 0.08)
        case .twirl: raw = CGPoint(x: -radial.y * 0.08, y: radial.x * 0.08)
        }
        let length = hypot(raw.x, raw.y)
        let scale = length > 0 ? min(1, step.radius * 0.08 / length) * strength : 0
        return CGPoint(x: raw.x * scale, y: raw.y * scale)
    }

    private func substepCount(_ dab: BrushStamper.BakedDab) -> Int {
        let tipGradient: CGFloat
        switch dab.tip {
        case .round(let hardness):
            tipGradient = 1 / max(dab.radius * (1 - hardness), min(1, dab.radius))
        case .image(let ref, _):
            tipGradient = (maskIndices[ref].map { masks[$0].gradientBound } ?? 0) / (2 * dab.radius) + 1
        }
        let paperGradient: CGFloat
        if let paper {
            paperGradient = paper.depth * masks[paper.mask].gradientBound / paper.side
        } else { paperGradient = 0 }
        let boundaryGradient: CGFloat = selection == nil ? 0 : 1
        let velocityGradient = power * dab.alpha * ((mode == .push ? 0 : 0.16) + dab.radius * 0.08 * (tipGradient + paperGradient + boundaryGradient))
        return max(1, Int(ceil(velocityGradient / 0.2)))
    }

    private struct BoundarySegment { let a: CGPoint; let b: CGPoint; let error: CGFloat }
    private func indexSelectionBoundary() {
        guard let selection else { return }
        _ = StrokeGeometry.flattened(selection, closeSubpaths: true) { [self] current, point, error in
            guard current != point else { return }
            let index = selectionEdges.count
            selectionEdges.append(BoundarySegment(a: current, b: point, error: error))
            let apron = 1 + error
            let box = CGRect(x: min(current.x, point.x), y: min(current.y, point.y),
                             width: abs(current.x - point.x), height: abs(current.y - point.y)).insetBy(dx: -apron, dy: -apron)
            for y in Int(floor(box.minY / binSide))...Int(floor(box.maxY / binSide)) {
                for x in Int(floor(box.minX / binSide))...Int(floor(box.maxX / binSide)) {
                    selectionBins[Bin(x: x, y: y), default: []].append(index)
                }
            }
        }
    }
    private func selectionCoverage(_ point: CGPoint) -> CGFloat {
        guard selection != nil, let nearby = selectionBins[bin(point)] else { return 1 }
        let distance = nearby.reduce(CGFloat(1)) { value, index in
            let edge = selectionEdges[index]
            return min(value, max(0, sqrt(StrokeGeometry.distanceSquared(from: point, toSegment: edge.a, edge.b)) - edge.error))
        }
        return distance
    }

    private func coverage(_ step: Step, radial: CGPoint, at point: CGPoint) -> CGFloat {
        let tip: CGFloat
        switch step.tip {
        case .round(let hardness):
            tip = DabGradientCache.coverage(distanceFraction: hypot(radial.x, radial.y) / step.radius, hardness: hardness)
        case .image(let index, let cosine, let sine):
            let x = cosine * radial.x + sine * radial.y
            let y = -sine * radial.x + cosine * radial.y
            let u = x / (step.radius * 2) + 0.5, v = y / (step.radius * 2) + 0.5
            let edge = min(1, max(0, min(min(u, 1 - u), min(v, 1 - v)) * step.radius * 2))
            tip = (index.map { masks[$0].sample(x: u, y: v) } ?? 0) * edge
        }
        var grain: CGFloat = 1
        if let paper {
            let x = point.x / paper.side - floor(point.x / paper.side)
            let y = point.y / paper.side - floor(point.y / paper.side)
            grain = 1 - paper.depth * (1 - masks[paper.mask].sample(x: x, y: y, repeating: true))
        }
        return tip * step.alpha * grain
    }

    private struct AlphaMask {
        let width: Int; let height: Int
        let bytes: [UInt8]
        let gradientBound: CGFloat
        init?(_ image: CGImage) {
            width = image.width; height = image.height
            guard let rgba = CoreGraphicsCompositor.premultipliedBytes(image, width: width, height: height) else { return nil }
            let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
            bytes = alpha
            var dx = 0, dy = 0
            for y in 0..<height { for x in 0..<width {
                let value = Int(alpha[y * width + x])
                dx = max(dx, abs(value - Int(alpha[y * width + (x + 1) % width])))
                dy = max(dy, abs(value - Int(alpha[((y + 1) % height) * width + x])))
                if x == 0 || x == width - 1 { dx = max(dx, value) }
                if y == 0 || y == height - 1 { dy = max(dy, value) }
            } }
            gradientBound = CGFloat(dx * width + dy * height) / 255
        }
        func sample(x: CGFloat, y: CGFloat, repeating: Bool = false) -> CGFloat {
            guard x >= 0, y >= 0, x <= 1, y <= 1 else { return 0 }
            let px = x * CGFloat(width) - 0.5, py = y * CGFloat(height) - 0.5
            let ix = Int(floor(px)), iy = Int(floor(py)), fx = px - CGFloat(ix), fy = py - CGFloat(iy)
            func read(_ x: Int, _ y: Int) -> CGFloat {
                if repeating {
                    let wrappedX = (x % width + width) % width, wrappedY = (y % height + height) % height
                    return CGFloat(bytes[wrappedY * width + wrappedX]) / 255
                }
                guard x >= 0, x < width, y >= 0, y < height else { return 0 }
                return CGFloat(bytes[y * width + x]) / 255
            }
            return (read(ix, iy) * (1 - fx) + read(ix + 1, iy) * fx) * (1 - fy) +
                (read(ix, iy + 1) * (1 - fx) + read(ix + 1, iy + 1) * fx) * fy
        }
    }
}

extension LiquifyField {
    func mapping(_ elements: [VectorElement],
                          selectedIDs: Set<UUID>? = nil, poses: [UUID: PoseMap] = [:]) -> [VectorElement] {
        guard !isEmpty, let definition else { return elements }
        let operation = InkMaterialOperation(definition, supportBounds: replacementBounds)
        let field = self
        return elements.map { element in
            guard selectedIDs?.contains(element.id) ?? true else { return element }
            let pose = poses[element.id]
            let box = field.bounds
            let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            let pulled = pose?.inverse.map { inverse in corners.map { inverse.applied(to: $0) ?? $0 } } ?? corners
            let active = pulled.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.001, height: 0.001))) }
            func move(_ points: [CGPoint]) -> [CGPoint] {
                points.map { point in
                    let shown = pose?.applied(to: point) ?? point
                    let moved = field.map(shown)
                    return pose?.inverse?.applied(to: moved) ?? moved
                }
            }
            switch element {
            case .stroke(let stroke):
                guard VectorCanvas.materialBounds(of: stroke).intersects(active) else { return element }
                return VectorGeometryMap.liquified(element, region: active,
                    binding: InkMaterialBinding(operation: operation,
                        bridge: pose?.inverse.map { .homography($0.homography) } ?? .identity), by: move)
            case .fill(let fill):
                guard fill.cgPath?.boundingBoxOfPath.intersects(active) == true else { return element }
                return VectorGeometryMap.liquified(element, region: active,
                    binding: InkMaterialBinding(operation: operation,
                        bridge: pose?.inverse.map { .homography($0.homography) } ?? .identity), by: move)
            case .image, .video, .stream, .text: return element
            }
        }
    }

}
