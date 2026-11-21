import CoreGraphics
import UIKit

/// Current-window support for vector mending. It records the canonical renderer's primitive clip
/// bounds, never brush math; physical ink and current SOURCE are classified by the fill session.
enum VectorMendSupport {
    enum Failure: Error, Equatable {
        case invalidWindow
        case exceedsBudget
        case exceedsWork
        case cancelled
    }

    struct Admission {
        let bytes: Int
        let work: Int
    }

    struct Span: Equatable {
        let start: UInt32
        let count: UInt32
    }

    /// Bit 31 distinguishes a boundary which must be physical OPEN AND SOURCE. An untagged
    /// support/verified continuation cell may be physical INK OR SOURCE. Synthetic path walls
    /// are not physical ink. The eventual GPU reader must use the reference-RGBA classifier.
    struct Contact: Equatable {
        static let openBit: UInt32 = 1 << 31
        let start: UInt32
        let count: UInt32
        var index: Int { Int(start & ~Self.openBit) }
        var requiresOpen: Bool { start & Self.openBit != 0 }
    }

    struct Patch {
        let contactStart: UInt32
        let contactCount: UInt32
        let spanStart: UInt32
        let spanCount: UInt32
        /// A construction failure protects this target; it never makes an empty accepting patch.
        let unknown: UInt32
    }

    struct Packet {
        let width: Int
        let height: Int
        let patches: [Patch]
        let contacts: [Contact]
        /// Conservative canonical support; never a claim of physical painted coverage. Patch span
        /// offsets address these rows. The final consumer must also require actual reference INK.
        let canonicalCoverage: [Span]
        var retainedBytes: Int {
            [UndoBudget.payloadBytes(count: patches.capacity, stride: MemoryLayout<Patch>.stride),
             UndoBudget.payloadBytes(count: contacts.capacity, stride: MemoryLayout<Contact>.stride),
             UndoBudget.payloadBytes(count: canonicalCoverage.capacity, stride: MemoryLayout<Span>.stride),
             96].reduce(0, UndoBudget.addingCost)
        }
    }

    fileprivate struct Dab {
        let bounds: CGRect
        let parameter: CGFloat?
    }

    fileprivate struct StrokeWork {
        let neighbourVisits: Int

        // Each corner reads two neighbours. Segment tangents test both corners and can read
        // two more neighbours. A direction read can also fall back to two more neighbours.
        var cornerSearches: Int { 2 * neighbourVisits }
        var tangentSearches: Int { 3 * cornerSearches }
        var direction: Int { 2 + tangentSearches + cornerSearches }
        var flattenedSegment: Int { 1 + tangentSearches + StrokePath.maximumSubdivisions }
    }

    fileprivate struct Captured {
        struct Sampling {
            let plan: ImageWarp.RasterScaleSupport
            let nativeTransform: CGAffineTransform
        }
        let walk: VectorStrokeRenderWalk
        let work: StrokeWork
        let dabs: [Dab]
        let blendMode: CGBlendMode
        let transform: CGAffineTransform
        var sampling: Sampling? = nil
    }

    /// Request-scoped canonical capture. Window retries remap these already captured bounds;
    /// neither a completed session nor a document retains this owner or its frozen input list.
    struct Preparation {
        fileprivate let captured: [Captured]
        fileprivate let unknown: [CGRect]
        let sourceSize: CGSize
    }

    static func prepare(_ reference: Reference, meter: inout Meter,
                        isCurrent: () -> Bool) throws(Failure) -> Preparation {
        guard isCurrent() else { throw .cancelled }
        try meter.visit(reference.constructionWork)
        guard let (inputs, unknown) = reference.geometry() else { throw .invalidWindow }
        // The returned unknown array shares the original reserved container, whose capacity
        // can exceed its current count. Admit that real owner while capture/input values coexist.
        try meter.retain(1, stride: reference.retainedBytes)
        let groups = try capture(inputs, meter: &meter, isCurrent: isCurrent)
        return Preparation(captured: groups, unknown: unknown,
                           sourceSize: CGSize(width: reference.width, height: reference.height))
    }

    static func produce(_ preparation: Preparation, in window: FillWindow, meter: inout Meter,
                        isCurrent: () -> Bool) throws(Failure) -> Packet {
        guard isCurrent() else { throw .cancelled }
        if preparation.captured.isEmpty {
            return Packet(width: window.workingWidth, height: window.workingHeight,
                          patches: [], contacts: [], canonicalCoverage: [])
        }
        guard preparation.sourceSize == window.canvasSize,
              let sampling = ImageWarp.RasterScaleSupport(sourceSize: preparation.sourceSize,
                destination: CGRect(x: 0, y: 0, width: window.workingWidth, height: window.workingHeight),
                inverseTexelMap: Homography(window.transform.inverted())) else { throw .invalidWindow }
        try meter.retainArray(Captured.self, count: preparation.captured.count)
        try meter.visit(preparation.captured.count)
        var groups: [Captured] = []; groups.reserveCapacity(preparation.captured.count)
        for group in preparation.captured {
            groups.append(Captured(walk: group.walk, work: group.work, dabs: group.dabs, blendMode: group.blendMode,
                transform: group.transform.concatenating(window.transform),
                sampling: .init(plan: sampling, nativeTransform: group.transform)))
        }
        try meter.checkCapacity(groups, chargedCount: groups.count)
        var rows = 0
        try meter.visit(preparation.unknown.count, times: 2)
        for rect in preparation.unknown {
            let mapped = try sampling.influencedOutput(by: rect) { () throws(Failure) in try meter.visit(1) }
            if !mapped.isNull { rows = UndoBudget.addingCost(rows, Int(mapped.height)) }
        }
        guard rows < Int(UInt32.max) else { throw .exceedsBudget }
        try meter.retainArray(Span.self, count: rows)
        var unknown: [Span] = []; unknown.reserveCapacity(rows)
        for rect in preparation.unknown {
            guard isCurrent() else { throw .cancelled }
            let mapped = try sampling.influencedOutput(by: rect) { () throws(Failure) in try meter.visit(1) }
            guard !mapped.isNull else { continue }
            try meter.visit(Int(mapped.height))
            for y in Int(mapped.minY)..<Int(mapped.maxY) {
                unknown.append(Span(start: UInt32(y * window.workingWidth + Int(mapped.minX)), count: UInt32(mapped.width)))
            }
        }
        try meter.checkCapacity(unknown, chargedCount: rows)
        return try packet(groups, unknownCoverage: unknown, width: window.workingWidth,
                          height: window.workingHeight, meter: &meter, isCurrent: isCurrent)
    }

    private static func supportBounds(_ dab: Dab, group: Captured, window: CGRect,
                                      meter: inout Meter) throws(Failure) -> CGRect {
        let raw = dab.bounds
        guard raw.minX.isFinite, raw.minY.isFinite, raw.width.isFinite, raw.height.isFinite else { throw .invalidWindow }
        if let sampling = group.sampling {
            return try sampling.plan.influencedOutput(by: raw.integral.applying(sampling.nativeTransform).integral) {
                () throws(Failure) in try meter.visit(1)
            }.intersection(window)
        }
        return raw.integral.applying(group.transform).integral.intersection(window)
    }

    private struct Curve: Equatable {
        let p0: CGPoint, p1: CGPoint, m0: CGPoint, m1: CGPoint
        func point(_ u: CGFloat) -> CGPoint {
            StrokePath.hermite(p1: p0, p2: p1, m1: m0, m2: m1, u: u)
        }
        func derivative(_ u: CGFloat) -> CGPoint {
            StrokePath.hermiteDerivative(p1: p0, p2: p1, m1: m0, m2: m1, u: u)
        }
        /// A cubic's projected derivative is quadratic. Its minimum is at an endpoint or its
        /// single interior minimum; no samples or angle tolerance stand in for monotonicity.
        func increases(along axis: CGPoint) -> Bool {
            let c = dot(m0, axis)
            let end = dot(m1, axis)
            let mid = dot(derivative(0.5), axis)
            let a = 2 * (end + c - 2 * mid)
            let b = end - c - a
            var minimum = min(c, end)
            if a > 0 {
                let u = -b / (2 * a)
                if u > 0 && u < 1 { minimum = min(minimum, a * u * u + b * u + c) }
            }
            return minimum.isFinite && minimum > StrokeGeometry.epsilon
        }
    }

    private struct Trace {
        let knots: [CGPoint]
        let transform: CGAffineTransform
        let curves: [Curve]
        let creases: [Bool]
        let point: CGPoint
        let range: ClosedRange<CGFloat>
        var end: CGFloat { CGFloat(curves.count) }
        func at(_ parameter: CGFloat) -> CGPoint {
            guard !curves.isEmpty else { return point }
            let index = min(curves.count - 1, max(0, Int(parameter.rounded(.down))))
            return curves[index].point(min(1, max(0, parameter - CGFloat(index))))
        }
        func correspondence(to other: Trace) -> Int8 {
            guard knots.count == other.knots.count else { return 0 }
            if curves.isEmpty { return point == other.point ? 1 : 0 }
            guard transform == other.transform else { return 0 }
            if knots == other.knots && creases == other.creases && range == other.range { return 1 }
            guard range.lowerBound == end - other.range.upperBound,
                  range.upperBound == end - other.range.lowerBound else { return 0 }
            guard knots.elementsEqual(other.knots.reversed()) else { return 0 }
            guard creases.elementsEqual(other.creases.reversed()) else { return 0 }
            return -1
        }
        func isRegular(in range: ClosedRange<CGFloat>, along axis: CGPoint, meter: inout Meter) throws(Failure) -> Bool {
            guard !curves.isEmpty else { return true }
            let first = max(0, Int(range.lowerBound.rounded(.down)))
            let last = min(curves.count - 1, Int(range.upperBound.rounded(.up)) - 1)
            guard first <= last else { return false }
            try meter.visit(last - first + 1, times: 2)
            if first < last && ((first + 1)...last).contains(where: { creases[$0] }) { return false }
            return (first...last).allSatisfy { curves[$0].increases(along: axis) }
        }
    }

    private struct Chart {
        let range: ClosedRange<CGFloat>
        let axis: CGPoint?
        let low: CGFloat?
        let high: CGFloat?
        func contains(_ point: CGPoint, halo: CGFloat = 0) -> Bool {
            guard let axis else { return true }
            let s = dot(point, axis)
            return (low.map { s >= $0 - halo } ?? true)
                && (high.map { s <= $0 + halo } ?? true)
        }

        /// A horizontal span intersects a projected strip in a single interval. Search the
        /// transitions using the same projection as contains, including rounding at its edges.
        func clip(_ row: Range<Int>, width: Int, halo: CGFloat = 0, meter: inout Meter) throws(Failure) -> Range<Int> {
            guard let axis, !row.isEmpty else { return row }
            let descending = axis.x < 0
            let from = descending ? high : low
            let to = descending ? low : high
            func firstIndex(in indices: Range<Int>, where predicate: (CGFloat) -> Bool,
                            meter: inout Meter) throws(Failure) -> Int {
                guard !indices.isEmpty else { return indices.lowerBound }
                // The predicate is monotone along a row, so its two ends settle a row that lies wholly
                // inside or wholly outside the strip — nearly every row of a neighbouring dab — in two
                // reads instead of a bisection; only a row the strip's gate crosses is searched. The
                // answer is the one the bisection alone gives. MEASURED on the owner's Rough Ink case
                // (5000², 1,920² window) the certificate's work was past the 64 M limit and is 55 M.
                try meter.visit(1)
                if predicate(dot(pixelCenter(indices.lowerBound, width: width), axis)) { return indices.lowerBound }
                try meter.visit(1)
                guard predicate(dot(pixelCenter(indices.upperBound - 1, width: width), axis)) else {
                    return indices.upperBound
                }
                var low = indices.lowerBound + 1, high = indices.upperBound - 1
                while low < high {
                    try meter.visit(1)
                    let mid = low + (high - low) / 2
                    if predicate(dot(pixelCenter(mid, width: width), axis)) { high = mid }
                    else { low = mid + 1 }
                }
                return low
            }
            var start = row.lowerBound, end = row.upperBound
            if let from {
                let bound = descending ? from + halo : from - halo
                start = try firstIndex(in: row, where: { descending ? $0 <= bound : $0 >= bound }, meter: &meter)
            }
            if let to {
                let bound = descending ? to - halo : to + halo
                end = try firstIndex(in: start..<end, where: { descending ? $0 < bound : $0 > bound }, meter: &meter)
            }
            return start..<end
        }
    }

    private struct Address { let group: Int, dab: Int }
    /// Canonical curves and CGContext primitives use cell centres, not integer cell indices.
    private static func pixelCenter(x: Int, y: Int) -> CGPoint {
        CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
    }
    private static func pixelCenter(_ index: Int, width: Int) -> CGPoint {
        pixelCenter(x: index % width, y: index / width)
    }
    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.x + a.y * b.y }
    private static func vector(_ p: CGPoint, by t: CGAffineTransform) -> CGPoint {
        CGPoint(x: t.a * p.x + t.c * p.y, y: t.b * p.x + t.d * p.y)
    }

    private static func trace(_ captured: Captured, meter: inout Meter) throws(Failure) -> Trace? {
        guard !captured.dabs.isEmpty else { return nil }
        let walk = captured.walk
        let pose: CGAffineTransform
        if let resolved = walk.pose {
            guard let affine = resolved.map.affine() else { return nil }
            pose = affine
        } else { pose = .identity }
        let transform = pose.concatenating(captured.transform)
        let path = StrokePath(points: walk.samples.positions)
        guard let first = path.points.first else { return nil }
        try meter.retainArray(Curve.self, count: path.points.count)
        try meter.retainArray(Bool.self, count: path.points.count)
        try meter.visit(path.points.count, times: 8 + captured.work.cornerSearches)
        try meter.visit(path.points.count - 1, times: captured.work.tangentSearches)
        var curves: [Curve] = [], creases: [Bool] = []
        curves.reserveCapacity(max(0, path.points.count - 1)); creases.reserveCapacity(path.points.count)
        for i in path.points.indices {
            creases.append(StrokePath.isCorner(at: i, count: path.points.count, point: { path.points[$0] }))
            if i + 1 < path.points.count {
                let (m0, m1) = path.tangents(segment: i)
                curves.append(Curve(p0: path.points[i].applying(transform),
                    p1: path.points[i + 1].applying(transform),
                    m0: vector(m0, by: transform), m1: vector(m1, by: transform)))
            }
        }
        let range = walk.visibleRange ?? 0...path.domainEnd
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              range.lowerBound >= 0, range.upperBound <= path.domainEnd else { return nil }
        try meter.checkCapacity(curves, chargedCount: path.points.count)
        try meter.checkCapacity(creases, chargedCount: path.points.count)
        return Trace(knots: path.points, transform: transform, curves: curves, creases: creases,
                     point: first.applying(transform), range: range)
    }

    private static func chart(_ trace: Trace, parameter: CGFloat?, spans: ArraySlice<Span>,
                              width: Int, meter: inout Meter) throws(Failure) -> Chart? {
        guard let parameter, trace.range.contains(parameter), !spans.isEmpty else { return nil }
        if trace.curves.isEmpty { return Chart(range: trace.range, axis: nil, low: nil, high: nil) }
        let segment = min(trace.curves.count - 1, max(0, Int(parameter.rounded(.down))))
        let derivative = trace.curves[segment].derivative(parameter - CGFloat(segment))
        let length = hypot(derivative.x, derivative.y)
        guard length.isFinite, length > StrokeGeometry.epsilon else { return nil }
        let axis = CGPoint(x: derivative.x / length, y: derivative.y / length)
        guard trace.curves[segment].increases(along: axis) else { return nil }
        var low = CGFloat.infinity, high = -CGFloat.infinity
        for span in spans {
            try meter.visit(Int(span.count))
            for i in Int(span.start)..<Int(span.start + span.count) {
                let s = dot(pixelCenter(i, width: width), axis)
                low = min(low, s); high = max(high, s)
            }
        }
        // Pixel centres plus their full eight-neighbour closed cells occupy 1.5 L1 units.
        // Two gives the artificial cut a half-cell clearance from that entire ring.
        let halo = 2 * (abs(axis.x) + abs(axis.y))
        low -= halo; high += halo
        // Prove only the regular parameter interval needed to reach the two local cuts. Walking
        // the entire monotone stroke for every dab would turn a long ordinary line quadratic.
        var first = segment, last = segment
        while CGFloat(first) > trace.range.lowerBound && dot(trace.at(CGFloat(first)), axis) >= low {
            try meter.visit(1)
            guard first > 0, !trace.creases[first], trace.curves[first - 1].increases(along: axis) else { break }
            first -= 1
        }
        while CGFloat(last + 1) < trace.range.upperBound && dot(trace.at(CGFloat(last + 1)), axis) <= high {
            try meter.visit(1)
            guard last + 1 < trace.curves.count, !trace.creases[last + 1],
                  trace.curves[last + 1].increases(along: axis) else { break }
            last += 1
        }
        let range = max(CGFloat(first), trace.range.lowerBound)...min(CGFloat(last + 1), trace.range.upperBound)
        let hasLowGate = dot(trace.at(range.lowerBound), axis) < low
        let hasHighGate = dot(trace.at(range.upperBound), axis) > high
        guard hasLowGate || range.lowerBound == trace.range.lowerBound,
              hasHighGate || range.upperBound == trace.range.upperBound else { return nil }
        return Chart(range: range, axis: axis, low: hasLowGate ? low : nil, high: hasHighGate ? high : nil)
    }

    /// The canonical renderer supplies actual resolved primitives after scatter/pose/dropout.
    /// Retain only their shared clip bounds and pending native parameter; no colors, tips or images
    /// are retained or redrawn. A pose which drops a primitive cannot shift the later metadata.
    private nonisolated final class Capture: DabTarget {
        var dabs: [Dab] = []
        var blendMode: CGBlendMode = .normal
        private var parameter: CGFloat?
        init(capacity: Int) { dabs.reserveCapacity(capacity) }
        func beginStroke() {}
        func endStroke() {}
        func endStrokeGroup() {}
        func dabSite(at point: CGPoint, travel: CGPoint, parameter: CGFloat?) { self.parameter = parameter }
        func beginStrokeGroup(opacity: CGFloat, blendMode: CGBlendMode, texture: BrushTextureSettings?) {
            self.blendMode = blendMode
        }
        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            dabs.append(Dab(bounds: dabCircleBounds(at: point, radius: radius), parameter: parameter))
        }
        func stampImage(_ texture: BrushTextureRef, at point: CGPoint, diameter: CGFloat,
                        angle: CGFloat, color: UIColor, alpha: CGFloat, blendMode: CGBlendMode) {
            dabs.append(Dab(bounds: dabImageBounds(at: point, diameter: diameter, angle: angle), parameter: parameter))
        }
    }

    struct Meter {
        let admission: Admission
        var bytes = 0
        var work = 0
        mutating func retain(_ count: Int, stride: Int) throws(Failure) {
            let (amount, overflow) = count.multipliedReportingOverflow(by: stride)
            let (total, sumOverflow) = bytes.addingReportingOverflow(amount)
            guard count >= 0, stride >= 0, !overflow, !sumOverflow,
                  total <= admission.bytes else { throw .exceedsBudget }
            bytes = total
        }
        mutating func visit(_ count: Int, times: Int = 1) throws(Failure) {
            let (count, productOverflow) = count.multipliedReportingOverflow(by: times)
            guard !productOverflow, times >= 0 else { throw .exceedsWork }
            let (total, overflow) = work.addingReportingOverflow(count)
            guard count >= 0, !overflow, total <= admission.work else { throw .exceedsWork }
            work = total
        }
        /// A container has its own header/rounding allowance, even when it holds one byte.
        /// Reserve before allocation; a thousand small arrays pay a thousand allowances instead
        /// of competing for a fixed global slack pool. Payload growth remains charged separately.
        mutating func retainArray<T>(_ type: T.Type, count: Int) throws(Failure) {
            let before = bytes
            try retain(count, stride: 2 * MemoryLayout<T>.stride)
            try retain(1, stride: 32 + 16)
            // This seam precedes a container's reservation, never a pixel/visit or spare-slot
            // append. Zero-count headers allocate no payload; their later growth pays here.
            guard count == 0 || CompositorBudget.hasHeadroom(for: bytes - before) else { throw .exceedsBudget }
        }
        func checkCapacity<T>(_ array: [T], chargedCount: Int) throws(Failure) {
            try checkCapacity(array.capacity, stride: MemoryLayout<T>.stride,
                              chargedCount: chargedCount, chargedStride: 2 * MemoryLayout<T>.stride)
        }
        /// Validate bytes, not element counts: Array<Bool>.reserveCapacity(2) can own16bytes.
        /// The16byte addition was admitted once by retainArray (or the memo's header charge).
        /// This bounds owned logical payload/capacity, not allocator metadata or process RSS.
        func checkCapacity(_ capacity: Int, stride: Int, chargedCount: Int, chargedStride: Int) throws(Failure) {
            let (actual, overflow) = capacity.multipliedReportingOverflow(by: stride)
            let (payload, payloadOverflow) = chargedCount.multipliedReportingOverflow(by: chargedStride)
            let (allowance, allowanceOverflow) = payload.addingReportingOverflow(16)
            guard capacity >= 0, chargedCount >= 0, !overflow, !payloadOverflow,
                  !allowanceOverflow, actual <= allowance else { throw .exceedsBudget }
        }
    }

    /// Conservative preflight bounds the walk before it allocates a collector: spacing has the
    /// shared one-point floor, and at most one extra site per segment covers roundoff/carry.
    private static func capture(_ inputs: [Input], meter: inout Meter,
                                isCurrent: () -> Bool = { true }) throws(Failure) -> [Captured] {
        typealias Recipe = (walk: VectorStrokeRenderWalk, capacity: Int, work: StrokeWork)
        var recipes: [Recipe] = []
        try meter.retainArray(Recipe.self, count: inputs.count)
        try meter.retainArray(Captured.self, count: inputs.count)
        recipes.reserveCapacity(inputs.count)
        var upperDabs = 0
        for input in inputs {
            guard isCurrent() else { throw .cancelled }
            // A derived placement can materialize both native runs while resolving the shared
            // recipe. Admit that worst case before asking effectiveWalk; borrowed rest/retained
            // buffers need no additional storage, so this allowance is deliberately conservative.
            let sampleStart = meter.bytes
            try meter.retain(input.stroke.samples.count, stride: 2 * MemoryLayout<VectorSample>.stride)
            try meter.retain(input.stroke.lattice?.samples.count ?? 0, stride: 2 * MemoryLayout<VectorSample>.stride)
            if input.stroke.restWalk == nil, input.stroke.placement != nil {
                guard CompositorBudget.hasHeadroom(for: meter.bytes - sampleStart) else { throw .exceedsBudget }
            }
            let walk = VectorStrokeRenderWalk(input.stroke)
            if input.stroke.opacity <= 0 || walk.samples.isEmpty {
                recipes.append((walk, 0, StrokeWork(neighbourVisits: 0)))
                continue
            }
            let path = StrokePath(points: walk.samples.positions)
            try meter.visit(path.points.count)
            guard let neighbourVisits = path.distinctNeighbourVisitLimit else { throw .invalidWindow }
            let work = StrokeWork(neighbourVisits: neighbourVisits)
            let segments = path.points.count - 1
            try meter.visit(segments, times: work.flattenedSegment)
            let length = path.arcLength(to: path.domainEnd)
            guard length.isFinite, length >= 0, length < CGFloat(Int.max / 2) else { throw .exceedsWork }
            let (upper, overflow) = Int(length.rounded(.up)).addingReportingOverflow(max(1, walk.samples.count))
            let (sum, sumOverflow) = upperDabs.addingReportingOverflow(upper)
            guard !overflow, !sumOverflow else { throw .exceedsWork }
            try admitStampWork(work, segments: segments, sites: upper, brush: input.stroke.brush,
                               size: walk.size, meter: &meter)
            upperDabs = sum
            recipes.append((walk, upper, work))
        }
        try meter.visit(upperDabs)
        let captureStart = meter.bytes
        try meter.retain(upperDabs, stride: 2 * MemoryLayout<Dab>.stride)
        // All collectors coexist; admit their forthcoming payload together, not once per dab.
        guard CompositorBudget.hasHeadroom(for: meter.bytes - captureStart) else { throw .exceedsBudget }
        var captured: [Captured] = []
        captured.reserveCapacity(inputs.count)
        for (input, recipe) in zip(inputs, recipes) {
            guard isCurrent() else { throw .cancelled }
            let (walk, capacity, work) = recipe
            try meter.retainArray(Dab.self, count: 0) // its payload was precharged in upperDabs
            let target = Capture(capacity: capacity)
            if capacity > 0 {
                autoreleasepool { walk.stamp(into: target, isEraser: input.stroke.composite == .erase) }
            }
            guard target.dabs.count <= capacity else { throw .exceedsBudget }
            try meter.checkCapacity(target.dabs, chargedCount: capacity)
            captured.append(Captured(walk: walk, work: work, dabs: target.dabs,
                                     blendMode: target.blendMode, transform: input.transform))
        }
        try meter.checkCapacity(recipes, chargedCount: inputs.count)
        try meter.checkCapacity(captured, chargedCount: inputs.count)
        return captured
    }

    /// Reserve the full replay walk, including sites suppressed by the visible range or density.
    private static func admitStampWork(_ work: StrokeWork, segments: Int, sites: Int, brush: Brush,
                                       size: CGFloat, meter: inout Meter) throws(Failure) {
        try meter.visit(segments, times: work.flattenedSegment) // advance
        try meter.visit(sites, times: work.direction) // frame passed to stampDab
        var readsTaper = false
        var readsDirection = brush.dab.angle.directionFollow != 0
        if readsDirection { try meter.visit(sites, times: work.direction) }
        func admitInput(_ input: BrushInput) throws(Failure) {
            switch input {
            case .taper: readsTaper = true
            case .direction:
                readsDirection = true
                try meter.visit(sites, times: work.direction)
            default: break
            }
        }
        for row in brush.modulations.rows {
            // This scan and replay's two input queries (construct and check each input list).
            try meter.visit(1, times: 5)
            try meter.visit(row.modules.count, times: 5)
            try meter.visit(sites) // the row's input and fixed evaluation
            try meter.visit(sites, times: row.modules.count)
            try admitInput(row.input)
            for module in row.modules {
                if let input = module.scaleInput { try admitInput(input) }
            }
        }
        if readsTaper && size > 0 { try meter.visit(segments, times: work.flattenedSegment) }
        if readsDirection && segments > 0 {
            // Build the heading's arc table and locate its two anchors. Each anchor resolves
            // a parameter by flattening one segment, then reads the tangent at that parameter.
            try meter.visit(segments, times: work.flattenedSegment + 3)
            try meter.visit(2, times: work.flattenedSegment + work.direction)
        }
    }

    private struct GroupPair: Hashable { let a: Int, b: Int }

    private static func correspondence(_ a: Int, _ b: Int, captured: [Captured], traces: [Trace?],
                                       memo: inout [GroupPair: Int8], meter: inout Meter) throws(Failure) -> Int8 {
        guard captured[a].blendMode == .normal, captured[b].blendMode == .normal,
              let ta = traces[a], let tb = traces[b] else { return 0 }
        if a == b { return 1 }
        let key = GroupPair(a: min(a, b), b: max(a, b))
        if let value = memo[key] { return value }
        try meter.visit(max(1, ta.curves.count), times: 3)
        // Charge hash-table capacity/entry overhead before an encountered pair is retained.
        try meter.retain(1, stride: 128)
        let value = ta.correspondence(to: tb)
        memo[key] = value
        return value
    }

    private static func spanBounds(_ spans: ArraySlice<Span>, width: Int) -> CGRect {
        var bounds = CGRect.null
        for span in spans {
            bounds = bounds.union(CGRect(x: Int(span.start) % width, y: Int(span.start) / width,
                                         width: Int(span.count), height: 1))
        }
        return bounds
    }

    private static func intersection(_ span: Span, with bounds: CGRect, width: Int) -> Range<Int> {
        let y = Int(span.start) / width
        guard !bounds.isNull, CGFloat(y) >= bounds.minY, CGFloat(y) < bounds.maxY else { return 0..<0 }
        let first = max(Int(span.start), y * width + max(0, Int(bounds.minX)))
        let end = min(Int(span.start + span.count), y * width + min(width, Int(bounds.maxX)))
        return first..<max(first, end)
    }

    /// The exact union of clipped dab rows. A word handles up to 64 adjacent cells, so
    /// overlap, insertion and cleanup are bounded by the rows the certificate actually visits.
    private struct SupportRows {
        let width: Int
        let stride: Int
        var words: [UInt64]

        init(width: Int, height: Int, meter: inout Meter) throws(Failure) {
            self.width = width
            stride = (width + 63) / 64
            let count = stride * height
            try meter.retainArray(UInt64.self, count: count)
            try meter.visit(count)
            words = [UInt64](repeating: 0, count: count)
            try meter.checkCapacity(words, chargedCount: count)
        }

        private func wordIndices(_ row: Range<Int>) -> ClosedRange<Int> {
            let y = row.lowerBound / width
            let x = row.lowerBound % width
            return (y * stride + (x >> 6))...(y * stride + ((x + row.count - 1) >> 6))
        }

        private func mask(_ index: Int, in row: Range<Int>) -> UInt64 {
            let wordX = (index % stride) << 6
            let lower = max(0, (row.lowerBound % width) - wordX)
            let upper = min(64, (row.lowerBound % width) + row.count - wordX)
            return (UInt64.max << lower) & (UInt64.max >> (64 - upper))
        }

        mutating func insert(_ row: Range<Int>, meter: inout Meter) throws(Failure) -> Bool {
            guard !row.isEmpty else { return false }
            let indices = wordIndices(row)
            try meter.visit(indices.count)
            var changed = false
            for index in indices {
                let before = words[index]
                words[index] |= mask(index, in: row)
                changed = changed || words[index] != before
            }
            return changed
        }

        func intersects(_ row: Range<Int>, meter: inout Meter) throws(Failure) -> Bool {
            guard !row.isEmpty else { return false }
            let indices = wordIndices(row)
            try meter.visit(indices.count)
            for index in indices where words[index] & mask(index, in: row) != 0 { return true }
            return false
        }

        func touches(_ row: Range<Int>, height: Int, meter: inout Meter) throws(Failure) -> Bool {
            guard !row.isEmpty else { return false }
            let y = row.lowerBound / width, offset = row.lowerBound % width
            let left = max(0, offset - 1), right = min(width, offset + row.count + 1)
            for otherY in max(0, y - 1)...min(height - 1, y + 1) {
                let start = otherY * width
                if try intersects((start + left)..<(start + right), meter: &meter) { return true }
            }
            return false
        }

        mutating func clear(_ box: CGRect, meter: inout Meter) throws(Failure) {
            let first = Int(box.minX) >> 6, last = (Int(box.maxX) - 1) >> 6
            try meter.visit(last - first + 1, times: Int(box.height))
            for y in Int(box.minY)..<Int(box.maxY) {
                let base = y * stride
                for x in first...last { words[base + x] = 0 }
            }
        }

        /// A contact word has core support or an 8-neighbour of core support. Halo
        /// members may carry ink; all other boundary cells must be open and SOURCE.
        func forEachContact(in box: CGRect, chart: Chart, height: Int, meter: inout Meter,
                            _ body: (Contact) -> Void) throws(Failure) {
            let firstX = Int(box.minX) >> 6, lastX = (Int(box.maxX) - 1) >> 6
            let firstY = Int(box.minY), lastY = Int(box.maxY) - 1
            func coreWord(x: Int, y: Int, meter: inout Meter) throws(Failure) -> UInt64 {
                guard x >= 0, x < stride, y >= 0, y < height else { return 0 }
                try meter.visit(1)
                let value = words[y * stride + x]
                guard value != 0 else { return 0 }
                let row = y * width
                let wordX = x << 6
                let domain = (row + wordX)..<(row + min(width, wordX + 64))
                let clipped = try chart.clip(domain, width: width, meter: &meter)
                return clipped.isEmpty ? 0 : value & mask(y * stride + x, in: clipped)
            }
            for y in firstY...lastY {
                // Rolling OR of the three rows around y. Adjacent words supply the
                // two carry bits for the horizontal dilation.
                func vertical(_ x: Int, meter: inout Meter) throws(Failure) -> UInt64 {
                    let middle = try coreWord(x: x, y: y, meter: &meter)
                    let above = try coreWord(x: x, y: y - 1, meter: &meter)
                    let below = try coreWord(x: x, y: y + 1, meter: &meter)
                    return middle | above | below
                }
                var current: UInt64 = 0
                var next = try vertical(firstX, meter: &meter)
                for x in firstX...lastX {
                    let previous = current
                    current = next
                    next = try vertical(x + 1, meter: &meter)
                    let first = x << 6
                    let valid = UInt64.max >> max(0, first + 64 - width)
                    let dilated = (current | (current << 1) | (current >> 1)
                        | (previous >> 63) | (next << 63)) & valid
                    var required = dilated & ~words[y * stride + x]
                    var remaining = dilated
                    while remaining != 0 {
                        try meter.visit(1)
                        let low = remaining.trailingZeroBitCount
                        let isOpen = required & (1 << low) != 0
                        let role = (isOpen ? required : remaining & ~required) >> low
                        let length = (~role).trailingZeroBitCount
                        let run = (UInt64.max >> (64 - length)) << low
                        let start = UInt32(y * width + first + low) | (isOpen ? Contact.openBit : 0)
                        body(Contact(start: start, count: UInt32(length)))
                        remaining &= ~run
                        required &= ~run
                    }
                }
            }
        }
    }

    private static func certify(_ captured: [Captured], addresses: [Address], spans: [Span],
                                unknownCoverage: [Span], width: Int, height: Int,
                                patches: inout [Patch], contacts: inout [Contact],
                                meter: inout Meter,
                                isCurrent: () -> Bool) throws(Failure) {
        try meter.retainArray(Trace?.self, count: captured.count)
        var traces: [Trace?] = []; traces.reserveCapacity(captured.count)
        for group in captured { traces.append(try trace(group, meter: &meter)) }
        let (entryCount, overflow) = addresses.count.addingReportingOverflow(unknownCoverage.count)
        guard !overflow, entryCount < Int(Int32.max), addresses.count < Int(UInt32.max) else { throw .exceedsBudget }
        try meter.retainArray(CGRect.self, count: entryCount)
        try meter.retainArray(UInt32.self, count: entryCount)
        try meter.retainArray(UInt32.self, count: addresses.count)
        var bounds: [CGRect] = []; bounds.reserveCapacity(entryCount)
        let index = StrokeSpatialIndex(cellSize: 16)
        for patch in patches {
            try meter.visit(Int(patch.spanCount))
            bounds.append(spanBounds(spans[Int(patch.spanStart)..<Int(patch.spanStart + patch.spanCount)], width: width))
        }
        for span in unknownCoverage {
            bounds.append(CGRect(x: Int(span.start) % width, y: Int(span.start) / width,
                                 width: Int(span.count), height: 1))
        }
        for i in bounds.indices {
            guard let cells = index.insertionCellCount(for: bounds[i]) else { throw .exceedsWork }
            try meter.visit(cells)
            // Each occupied cell can introduce a dictionary bucket, capacity slack and its slot.
            try meter.retain(cells, stride: 128)
            try meter.retain(1, stride: 128)
            index.insert(bounds: bounds[i], elementIndex: i)
        }
        var seen = [UInt32](repeating: 0, count: entryCount)
        var included = [UInt32](repeating: 0, count: addresses.count)
        var queryToken: UInt32 = 0
        try meter.retain(1, stride: 128) // memo header + capacity rounding, before first insertion
        var memo: [GroupPair: Int8] = [:]
        // Contacts start empty with one prepaid container allowance. Paid slots, rather than
        // allocator capacity or logical count, own each amortized reservation below.
        var paidContactCapacity = 0
        var members = try SupportRows(width: width, height: height, meter: &meter)
        var dirty = CGRect.null
        for target in addresses.indices {
            guard isCurrent() else { throw .cancelled }
            if !dirty.isNull { try members.clear(dirty, meter: &meter) }
            dirty = .null
            let token = UInt32(target + 1)
            let address = addresses[target], old = patches[target]
            let targetSpans = spans[Int(old.spanStart)..<Int(old.spanStart + old.spanCount)]
            guard let trace = traces[address.group],
                  captured[address.group].blendMode == .normal,
                  let chart = try chart(trace, parameter: captured[address.group].dabs[address.dab].parameter,
                                        spans: targetSpans, width: width, meter: &meter) else { continue }
            let halo = chart.axis.map { 2 * (abs($0.x) + abs($0.y)) } ?? 0
            // Every component of C seeds the same support queue. An admitted neighbouring bound
            // contributes its entire intersection with the strip/halo, not just the overlap found.
            func include(_ candidate: Int, meter: inout Meter) throws(Failure) -> Bool {
                included[candidate] = token
                let patch = patches[candidate]
                var minX = width, maxX = 0, minY = height, maxY = 0
                var changed = false
                for span in spans[Int(patch.spanStart)..<Int(patch.spanStart + patch.spanCount)] {
                    try meter.visit(1)
                    let start = Int(span.start)
                    let row = start..<(start + Int(span.count))
                    let accepted = try chart.clip(row, width: width, halo: halo, meter: &meter)
                    guard !accepted.isEmpty else { continue }
                    if try members.insert(accepted, meter: &meter) { changed = true }
                    let x = accepted.lowerBound % width, y = start / width
                    minX = min(minX, x); maxX = max(maxX, x + accepted.count)
                    minY = min(minY, y); maxY = max(maxY, y + 1)
                }
                if minX < maxX {
                    dirty = dirty.union(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
                }
                return changed
            }
            guard try include(target, meter: &meter) else { continue }
            var unknown = false
            var grew = true
            // One query per support expansion sweep, not one query for each overlapping dab.
            // Revisit candidates if the exact union gains cells, including growth inside the
            // same rectangle. At a fixed point every contributor touching the union was checked.
            while grew && !unknown {
                grew = false
                let search = dirty.insetBy(dx: -1, dy: -1)
                if queryToken == UInt32.max {
                    try meter.visit(seen.count)
                    for i in seen.indices { seen[i] = 0 }
                    queryToken = 0
                }
                queryToken += 1
                let query = queryToken
                try index.forEachCandidate(near: search,
                    visitCell: { () throws(Failure) in try meter.visit(1) }) { (ref) throws(Failure) in
                    try meter.visit(1)
                    let i = ref.elementIndex
                    guard !unknown, seen[i] != query else { return }
                    seen[i] = query
                    if i < addresses.count && included[i] == token { return }
                    guard bounds[i].intersects(search) else { return }
                    if i >= addresses.count {
                        let span = unknownCoverage[i - addresses.count]
                        let local = intersection(span, with: dirty, width: width)
                        if try members.intersects(local, meter: &meter) { unknown = true }
                        return
                    }
                    let other = addresses[i]
                    let match = try correspondence(address.group, other.group, captured: captured,
                                                   traces: traces, memo: &memo, meter: &meter)
                    let parameter = captured[other.group].dabs[other.dab].parameter
                    let mapped = parameter.map { match < 0 ? trace.end - $0 : $0 }
                    let cohort = match != 0 && (mapped.map { trace.range.contains($0) } ?? false)
                    let patch = patches[i]
                    let candidateSpans = spans[Int(patch.spanStart)..<Int(patch.spanStart + patch.spanCount)]
                    var overlaps = false
                    for span in candidateSpans {
                        try meter.visit(1)
                        let local = intersection(span, with: dirty, width: width)
                        if try members.intersects(local, meter: &meter) { overlaps = true; break }
                    }
                    var touches = overlaps
                    if cohort && !touches {
                        let expanded = dirty.insetBy(dx: -1, dy: -1)
                        for span in candidateSpans {
                            try meter.visit(1)
                            let local = intersection(span, with: expanded, width: width)
                            let clipped = try chart.clip(local, width: width, halo: halo, meter: &meter)
                            if try members.touches(clipped, height: height, meter: &meter) { touches = true; break }
                        }
                    }
                    guard cohort, touches, let mapped else {
                        if overlaps { unknown = true }
                        return
                    }
                    // The cuts stay fixed. A wider touching cohort dab can originate just beyond
                    // the initial segment-rounded chart interval; prove its intervening regular
                    // continuation instead of treating that artificial interval as a foreign join.
                    let extended = min(chart.range.lowerBound, mapped)...max(chart.range.upperBound, mapped)
                    // A site exactly on a crease is not a continuation, even when it is the
                    // newly extended interval's endpoint rather than an interior knot.
                    let atInteriorCrease = mapped > 0 && mapped < trace.end
                        && mapped == mapped.rounded() && trace.creases[Int(mapped)]
                    var admitted = !atInteriorCrease
                    if admitted, let axis = chart.axis, let otherTrace = traces[other.group] {
                        admitted = try trace.isRegular(in: extended, along: axis, meter: &meter)
                        if admitted {
                            let range = match < 0 ? (trace.end - extended.upperBound)...(trace.end - extended.lowerBound) : extended
                            let direction = match < 0 ? CGPoint(x: -axis.x, y: -axis.y) : axis
                            admitted = try otherTrace.isRegular(in: range, along: direction, meter: &meter)
                        }
                    }
                    if admitted {
                        if try include(i, meter: &meter) { grew = true }
                    } else if overlaps { unknown = true }
                }
            }
            if unknown || dirty.isNull { continue }
            for span in targetSpans {
                let start = Int(span.start)
                let left = start % width - 1, right = left + Int(span.count) + 1, y = start / width
                try meter.visit(4)
                if !chart.contains(pixelCenter(x: left, y: y - 1))
                    || !chart.contains(pixelCenter(x: right, y: y - 1))
                    || !chart.contains(pixelCenter(x: left, y: y + 1))
                    || !chart.contains(pixelCenter(x: right, y: y + 1)) {
                    unknown = true
                    break
                }
            }
            if unknown { continue }
            let contactStart = contacts.count
            let contactBounds = dirty.insetBy(dx: -1, dy: -1)
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            // The GPU rejects any runtime contact on the outer working rim. A core cell
            // already on that rim has no complete contact neighbourhood and is also protected.
            var additions = 0
            try members.forEachContact(in: contactBounds, chart: chart, height: height, meter: &meter) {
                _ in additions += 1
            }
            let (total, totalOverflow) = contacts.count.addingReportingOverflow(additions)
            guard !totalOverflow, total <= Int(UInt32.max) else { throw .exceedsBudget }
            if total > paidContactCapacity {
                if total > contacts.capacity {
                    let (doubled, reservationOverflow) = paidContactCapacity.multipliedReportingOverflow(by: 2)
                    guard !reservationOverflow else { throw .exceedsBudget }
                    let reservation = max(total, max(1, doubled))
                    // Keep both payloads/headers charged during native reallocation and copy.
                    try meter.retainArray(Contact.self, count: reservation)
                    try meter.visit(contacts.count)
                    contacts.reserveCapacity(reservation)
                    try meter.checkCapacity(contacts, chargedCount: reservation)
                    let (oldPayload, payloadOverflow) = paidContactCapacity.multipliedReportingOverflow(
                        by: 2 * MemoryLayout<Contact>.stride)
                    let (oldCharge, chargeOverflow) = oldPayload.addingReportingOverflow(32 + 16)
                    guard !payloadOverflow, !chargeOverflow, oldCharge <= meter.bytes else { throw .exceedsBudget }
                    meter.bytes -= oldCharge
                    paidContactCapacity = reservation
                } else {
                    // Allocator rounding already supplied enough room; no new buffer or copy.
                    try meter.retain(total - paidContactCapacity, stride: 2 * MemoryLayout<Contact>.stride)
                    try meter.checkCapacity(contacts, chargedCount: total)
                    paidContactCapacity = total
                }
            }
            try members.forEachContact(in: contactBounds, chart: chart, height: height, meter: &meter) {
                contacts.append($0)
            }
            patches[target] = Patch(contactStart: UInt32(contactStart), contactCount: UInt32(contacts.count - contactStart),
                                    spanStart: old.spanStart, spanCount: old.spanCount, unknown: unknown ? 1 : 0)
        }
        try meter.checkCapacity(traces, chargedCount: captured.count)
        try meter.checkCapacity(bounds, chargedCount: entryCount)
        try meter.checkCapacity(seen, chargedCount: entryCount)
        try meter.checkCapacity(included, chargedCount: addresses.count)
        try meter.checkCapacity(contacts, chargedCount: paidContactCapacity)
        try meter.checkCapacity(memo.capacity, stride: MemoryLayout<(GroupPair, Int8)>.stride,
                                chargedCount: memo.count, chargedStride: 128)
    }

    /// Canonical integral bounds are potential-support supersets, not a second alpha renderer.
    /// Complete contributor/contact checks can only protect extra ink; final physical INK prevents
    /// rectangle-only paper or synthetic path walls from becoming painted eligibility.
    static func produce(_ reference: Reference, admission: Admission) throws(Failure) -> Packet {
        if let packet = reference.preparedPacket {
            guard packet.retainedBytes <= admission.bytes, admission.work >= 0 else { throw .exceedsBudget }
            return packet
        }
        let width = reference.width, height = reference.height
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow, count < Int(Contact.openBit),
              width <= 16_383, height <= 16_383 else { throw .invalidWindow }
        var meter = Meter(admission: admission)
        try meter.visit(reference.constructionWork)
        let (inputs, unknownCoverage) = try reference.resolve(meter: &meter)
        if inputs.isEmpty {
            return Packet(width: width, height: height, patches: [], contacts: [], canonicalCoverage: [])
        }
        let captured = try capture(inputs, meter: &meter)
        return try packet(captured, unknownCoverage: unknownCoverage, width: width, height: height,
                          meter: &meter, isCurrent: { true })
    }

    private static func packet(_ captured: [Captured], unknownCoverage: [Span], width: Int, height: Int,
                               meter: inout Meter, isCurrent: () -> Bool) throws(Failure) -> Packet {
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow, count < Int(Contact.openBit),
              width <= 16_383, height <= 16_383 else { throw .invalidWindow }
        // These growing containers pay one header/rounding allowance now; every later append
        // retains its existing doubled payload charge before growth.
        try meter.retainArray(Patch.self, count: 0)
        try meter.retainArray(Span.self, count: 0)
        try meter.retainArray(Address.self, count: 0)
        try meter.retainArray(Contact.self, count: 0)
        let window = CGRect(x: 0, y: 0, width: width, height: height)
        var patchCount = 0, rowCount = 0
        for group in captured {
            for dab in group.dabs {
                try meter.visit(1)
                guard isCurrent() else { throw .cancelled }
                let bounds = try supportBounds(dab, group: group, window: window, meter: &meter)
                let rows = bounds.isNull || bounds.isEmpty ? 0 : Int(bounds.height)
                let (nextRows, rowOverflow) = rowCount.addingReportingOverflow(rows)
                let (nextPatch, patchOverflow) = patchCount.addingReportingOverflow(1)
                guard !rowOverflow, !patchOverflow, nextRows <= Int(UInt32.max),
                      nextPatch < Int(UInt32.max) else { throw .exceedsBudget }
                rowCount = nextRows; patchCount = nextPatch
            }
        }
        let rowStart = meter.bytes
        try meter.retain(rowCount, stride: MemoryLayout<Span>.stride * 2)
        try meter.retain(patchCount, stride: 2 * (MemoryLayout<Patch>.stride + MemoryLayout<Address>.stride))
        guard CompositorBudget.hasHeadroom(for: meter.bytes - rowStart) else { throw .exceedsBudget }
        var patches: [Patch] = [], spans: [Span] = [], addresses: [Address] = []
        patches.reserveCapacity(patchCount); spans.reserveCapacity(rowCount); addresses.reserveCapacity(patchCount)
        try meter.checkCapacity(patches, chargedCount: patchCount)
        try meter.checkCapacity(spans, chargedCount: rowCount)
        try meter.checkCapacity(addresses, chargedCount: patchCount)
        for (groupIndex, group) in captured.enumerated() {
            for (dabIndex, dab) in group.dabs.enumerated() {
                try meter.visit(1)
                guard isCurrent() else { throw .cancelled }
                let bounds = try supportBounds(dab, group: group, window: window, meter: &meter)
                let start = spans.count
                if !bounds.isNull, !bounds.isEmpty {
                    try meter.visit(Int(bounds.height))
                    for y in Int(bounds.minY)..<Int(bounds.maxY) {
                        spans.append(Span(start: UInt32(y * width + Int(bounds.minX)), count: UInt32(bounds.width)))
                    }
                }
                patches.append(Patch(contactStart: 0, contactCount: 0, spanStart: UInt32(start),
                                     spanCount: UInt32(spans.count - start), unknown: 1))
                addresses.append(Address(group: groupIndex, dab: dabIndex))
            }
        }
        var contacts: [Contact] = []
        try certify(captured, addresses: addresses, spans: spans, unknownCoverage: unknownCoverage,
                    width: width, height: height, patches: &patches, contacts: &contacts,
                    meter: &meter, isCurrent: isCurrent)
        try meter.checkCapacity(patches, chargedCount: patches.count)
        try meter.checkCapacity(spans, chargedCount: spans.count)
        try meter.checkCapacity(addresses, chargedCount: addresses.count)
        return Packet(width: width, height: height, patches: patches, contacts: contacts,
                      canonicalCoverage: spans)
    }
}
