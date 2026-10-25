import CoreGraphics
import UIKit

/// Current-window support for vector mending. It records the canonical renderer's primitive clip
/// bounds, never brush math; physical ink and current SOURCE are classified by the fill session.
enum VectorMendSupport {
    enum Failure: Error, Equatable {
        case invalidWindow
        case exceedsBudget
        case exceedsWork
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
    }

    private struct Dab {
        let bounds: CGRect
        let parameter: CGFloat?
    }

    private struct Captured {
        let walk: VectorStrokeRenderWalk
        let dabs: [Dab]
        let blendMode: CGBlendMode
        let transform: CGAffineTransform
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
        // Distinct-neighbour searches can cross a whole stationary run at each knot.
        try meter.visit(path.points.count, times: path.points.count)
        try meter.visit(path.points.count, times: 8)
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
    private final class Capture: DabTarget {
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
            try retain(count, stride: 2 * MemoryLayout<T>.stride)
            try retain(1, stride: 32 + 16)
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
    private static func capture(_ inputs: [Input], meter: inout Meter) throws(Failure) -> [Captured] {
        var recipes: [(VectorStrokeRenderWalk, Int)] = []
        try meter.retainArray((VectorStrokeRenderWalk, Int).self, count: inputs.count)
        try meter.retainArray(Captured.self, count: inputs.count)
        recipes.reserveCapacity(inputs.count)
        var upperDabs = 0
        for input in inputs {
            // A derived placement can materialize both native runs while resolving the shared
            // recipe. Admit that worst case before asking effectiveWalk; borrowed rest/retained
            // buffers need no additional storage, so this allowance is deliberately conservative.
            try meter.retain(input.stroke.samples.count, stride: 2 * MemoryLayout<VectorSample>.stride)
            try meter.retain(input.stroke.lattice?.samples.count ?? 0, stride: 2 * MemoryLayout<VectorSample>.stride)
            let walk = VectorStrokeRenderWalk(input.stroke)
            if input.stroke.opacity <= 0 { recipes.append((walk, 0)); continue }
            // Admit repeated-position neighbour searches as well as the shared <=64 subdivisions;
            // samples*64 alone is not a work bound for a long stationary pressure run.
            try meter.visit(walk.samples.count, times: walk.samples.count)
            try meter.visit(max(1, walk.samples.count), times: 64)
            let path = StrokePath(points: walk.samples.positions)
            let length = path.arcLength(to: path.domainEnd)
            guard length.isFinite, length >= 0, length < CGFloat(Int.max / 2) else { throw .exceedsWork }
            let (upper, overflow) = Int(length.rounded(.up)).addingReportingOverflow(max(1, walk.samples.count))
            let (sum, sumOverflow) = upperDabs.addingReportingOverflow(upper)
            guard !overflow, !sumOverflow else { throw .exceedsWork }
            upperDabs = sum
            recipes.append((walk, upper))
        }
        try meter.visit(upperDabs)
        try meter.retain(upperDabs, stride: 2 * MemoryLayout<Dab>.stride)
        var captured: [Captured] = []
        captured.reserveCapacity(inputs.count)
        for (input, recipe) in zip(inputs, recipes) {
            let (walk, capacity) = recipe
            try meter.visit(capacity, times: max(1, walk.samples.count))
            try meter.retainArray(Dab.self, count: 0) // its payload was precharged in upperDabs
            let target = Capture(capacity: capacity)
            if capacity > 0 {
                autoreleasepool { walk.stamp(into: target, isEraser: input.stroke.composite == .erase) }
            }
            guard target.dabs.count <= capacity else { throw .exceedsBudget }
            try meter.checkCapacity(target.dabs, chargedCount: capacity)
            captured.append(Captured(walk: walk, dabs: target.dabs,
                                     blendMode: target.blendMode, transform: input.transform))
        }
        try meter.checkCapacity(recipes, chargedCount: inputs.count)
        try meter.checkCapacity(captured, chargedCount: inputs.count)
        return captured
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

    private static func certify(_ captured: [Captured], addresses: [Address], spans: [Span],
                                unknownCoverage: [Span], width: Int, height: Int,
                                patches: inout [Patch], contacts: inout [Contact],
                                support: inout [UInt8], meter: inout Meter) throws(Failure) {
        try meter.retainArray(Trace?.self, count: captured.count)
        var traces: [Trace?] = []; traces.reserveCapacity(captured.count)
        for group in captured { traces.append(try trace(group, meter: &meter)) }
        let (entryCount, overflow) = addresses.count.addingReportingOverflow(unknownCoverage.count)
        guard !overflow, entryCount < Int(Int32.max), addresses.count < Int(UInt32.max) else { throw .exceedsBudget }
        try meter.retainArray(CGRect.self, count: entryCount)
        try meter.retainArray(UInt32.self, count: entryCount)
        try meter.retainArray(UInt32.self, count: addresses.count)
        try meter.retainArray(Int.self, count: addresses.count)
        var bounds: [CGRect] = []; bounds.reserveCapacity(entryCount)
        let index = StrokeSpatialIndex()
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
        var queue: [Int] = []; queue.reserveCapacity(addresses.count)
        var queryToken: UInt32 = 0
        try meter.retain(1, stride: 128) // memo header + capacity rounding, before first insertion
        var memo: [GroupPair: Int8] = [:]
        // Contacts start empty with one prepaid container allowance. Paid slots, rather than
        // allocator capacity or logical count, own each amortized reservation below.
        var paidContactCapacity = 0
        var dirty = CGRect.null
        for target in addresses.indices {
            if !dirty.isNull {
                try meter.visit(Int(dirty.width), times: Int(dirty.height))
                for y in Int(dirty.minY)..<Int(dirty.maxY) {
                    for x in Int(dirty.minX)..<Int(dirty.maxX) { support[y * width + x] = 0 }
                }
            }
            dirty = .null; queue.removeAll(keepingCapacity: true)
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
            func include(_ candidate: Int, meter: inout Meter) throws(Failure) {
                included[candidate] = token
                let patch = patches[candidate]
                for span in spans[Int(patch.spanStart)..<Int(patch.spanStart + patch.spanCount)] {
                    try meter.visit(Int(span.count))
                    for i in Int(span.start)..<Int(span.start + span.count) {
                        let point = pixelCenter(i, width: width)
                        guard chart.contains(point, halo: halo) else { continue }
                        support[i] = chart.contains(point) ? 1 : 2
                        dirty = dirty.union(CGRect(x: i % width, y: i / width, width: 1, height: 1))
                    }
                }
                queue.append(candidate)
            }
            try include(target, meter: &meter)
            var unknown = false, head = 0
            while head < queue.count && !unknown {
                let candidate = queue[head]; head += 1
                if queryToken == UInt32.max {
                    try meter.visit(seen.count)
                    for i in seen.indices { seen[i] = 0 }
                    queryToken = 0
                }
                queryToken += 1
                let query = queryToken
                try index.forEachCandidate(near: bounds[candidate].insetBy(dx: -1, dy: -1),
                    visitCell: { () throws(Failure) in try meter.visit(1) }) { (ref) throws(Failure) in
                    try meter.visit(1)
                    let i = ref.elementIndex
                    guard !unknown, seen[i] != query else { return }
                    seen[i] = query
                    if i < addresses.count && included[i] == token { return }
                    guard bounds[i].intersects(dirty.insetBy(dx: -1, dy: -1)) else { return }
                    if i >= addresses.count {
                        let span = unknownCoverage[i - addresses.count]
                        let local = intersection(span, with: dirty, width: width)
                        try meter.visit(local.count)
                        if local.contains(where: { support[$0] != 0 }) { unknown = true }
                        return
                    }
                    let other = addresses[i]
                    let match = try correspondence(address.group, other.group, captured: captured,
                                                   traces: traces, memo: &memo, meter: &meter)
                    let parameter = captured[other.group].dabs[other.dab].parameter
                    let mapped = parameter.map { match < 0 ? trace.end - $0 : $0 }
                    let cohort = match != 0 && (mapped.map { trace.range.contains($0) } ?? false)
                    let patch = patches[i]
                    var touches = false, overlaps = false
                    for span in spans[Int(patch.spanStart)..<Int(patch.spanStart + patch.spanCount)] {
                        let local = intersection(span, with: cohort ? dirty.insetBy(dx: -1, dy: -1) : dirty, width: width)
                        try meter.visit(local.count, times: cohort ? 9 : 1)
                        for p in local {
                            guard chart.contains(pixelCenter(p, width: width), halo: halo) else { continue }
                            if support[p] != 0 { overlaps = true }
                            if cohort {
                                let x = p % width, y = p / width
                                for dy in -1...1 { for dx in -1...1 {
                                    let qx = x + dx, qy = y + dy
                                    if qx >= 0, qy >= 0, qx < width, qy < height,
                                       support[qy * width + qx] != 0 { touches = true }
                                } }
                            }
                        }
                        if overlaps && (touches || !cohort) { break }
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
                    if admitted { try include(i, meter: &meter) }
                    else if overlaps { unknown = true }
                }
            }
            if unknown || dirty.isNull { continue }
            for span in targetSpans {
                try meter.visit(Int(span.count), times: 9)
                for i in Int(span.start)..<Int(span.start + span.count) {
                    let x = i % width, y = i / width
                    for dy in -1...1 { for dx in -1...1 {
                        if !chart.contains(pixelCenter(x: x + dx, y: y + dy)) { unknown = true }
                    } }
                }
            }
            if unknown { continue }
            let contactStart = contacts.count
            let contactBounds = dirty.insetBy(dx: -1, dy: -1)
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            try meter.visit(Int(dirty.width) * Int(dirty.height), times: 9)
            for y in Int(dirty.minY)..<Int(dirty.maxY) {
                for x in Int(dirty.minX)..<Int(dirty.maxX) {
                    let i = y * width + x
                    guard support[i] & 3 == 1 else { continue }
                    support[i] |= 8
                    for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                        let qx = x + dx, qy = y + dy
                        guard qx >= 0, qy >= 0, qx < width, qy < height else { unknown = true; continue }
                        let q = qy * width + qx
                        if support[q] & 3 == 1 { continue }
                        // Halo support has the same full contributor closure as T. Keep its low
                        // membership bits while accumulating obligations; OPEN always wins.
                        let gate = support[q] & 3 == 2 && !chart.contains(pixelCenter(x: qx, y: qy))
                        support[q] |= gate ? 8 : 4
                    } }
                }
            }
            // Count the finished row runs before growing storage. Implicit Array.append growth
            // doubles an old allocator-rounded capacity, not the logical count we prepaid.
            // Both row passes and amortized copying are admitted; no per-patch array is retained.
            func forEachContact(_ body: (Contact) -> Void) {
                for y in Int(contactBounds.minY)..<Int(contactBounds.maxY) {
                    var x = Int(contactBounds.minX)
                    while x < Int(contactBounds.maxX) {
                        let flags = support[y * width + x] & 12
                        if flags == 0 { x += 1; continue }
                        let open = flags & 4 != 0
                        let start = x
                        repeat { x += 1 } while x < Int(contactBounds.maxX)
                            && (support[y * width + x] & 12 != 0)
                            && (support[y * width + x] & 4 != 0) == open
                        body(Contact(start: UInt32(y * width + start) | (open ? Contact.openBit : 0),
                                     count: UInt32(x - start)))
                    }
                }
            }
            try meter.visit(Int(contactBounds.width), times: Int(contactBounds.height))
            var additions = 0
            forEachContact { _ in additions += 1 }
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
            try meter.visit(Int(contactBounds.width), times: Int(contactBounds.height))
            forEachContact { contacts.append($0) }
            patches[target] = Patch(contactStart: UInt32(contactStart), contactCount: UInt32(contacts.count - contactStart),
                                    spanStart: old.spanStart, spanCount: old.spanCount, unknown: unknown ? 1 : 0)
            dirty = contactBounds

        }
        try meter.checkCapacity(traces, chargedCount: captured.count)
        try meter.checkCapacity(bounds, chargedCount: entryCount)
        try meter.checkCapacity(seen, chargedCount: entryCount)
        try meter.checkCapacity(included, chargedCount: addresses.count)
        try meter.checkCapacity(queue, chargedCount: addresses.count)
        try meter.checkCapacity(contacts, chargedCount: paidContactCapacity)
        try meter.checkCapacity(memo.capacity, stride: MemoryLayout<(GroupPair, Int8)>.stride,
                                chargedCount: memo.count, chargedStride: 128)
    }

    /// Canonical integral bounds are potential-support supersets, not a second alpha renderer.
    /// Complete contributor/contact checks can only protect extra ink; final physical INK prevents
    /// rectangle-only paper or synthetic path walls from becoming painted eligibility.
    static func produce(_ reference: Reference, admission: Admission) throws(Failure) -> Packet {
        let width = reference.width, height = reference.height
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow, count < Int(Contact.openBit),
              width <= 16_383, height <= 16_383 else { throw .invalidWindow }
        var meter = Meter(admission: admission)
        let (inputs, unknownCoverage) = try reference.resolve(meter: &meter)
        try meter.retainArray(UInt8.self, count: count)
        // These growing containers pay one header/rounding allowance now; every later append
        // retains its existing doubled payload charge before growth.
        try meter.retainArray(Patch.self, count: 0)
        try meter.retainArray(Span.self, count: 0)
        try meter.retainArray(Address.self, count: 0)
        try meter.retainArray(Contact.self, count: 0)
        let captured = try capture(inputs, meter: &meter)
        let window = CGRect(x: 0, y: 0, width: width, height: height)
        var support = [UInt8](repeating: 0, count: count)
        var patchCount = 0, rowCount = 0
        for group in captured {
            for dab in group.dabs {
                try meter.visit(1)
                let raw = dab.bounds
                guard raw.minX.isFinite, raw.minY.isFinite, raw.width.isFinite, raw.height.isFinite else {
                    throw .invalidWindow
                }
                let bounds = raw.integral.applying(group.transform).integral.intersection(window)
                let rows = bounds.isNull || bounds.isEmpty ? 0 : Int(bounds.height)
                let (nextRows, rowOverflow) = rowCount.addingReportingOverflow(rows)
                let (nextPatch, patchOverflow) = patchCount.addingReportingOverflow(1)
                guard !rowOverflow, !patchOverflow, nextRows <= Int(UInt32.max),
                      nextPatch < Int(UInt32.max) else { throw .exceedsBudget }
                rowCount = nextRows; patchCount = nextPatch
            }
        }
        try meter.retain(rowCount, stride: MemoryLayout<Span>.stride * 2)
        try meter.retain(patchCount, stride: 2 * (MemoryLayout<Patch>.stride + MemoryLayout<Address>.stride))
        var patches: [Patch] = [], spans: [Span] = [], addresses: [Address] = []
        patches.reserveCapacity(patchCount); spans.reserveCapacity(rowCount); addresses.reserveCapacity(patchCount)
        try meter.checkCapacity(patches, chargedCount: patchCount)
        try meter.checkCapacity(spans, chargedCount: rowCount)
        try meter.checkCapacity(addresses, chargedCount: patchCount)
        for (groupIndex, group) in captured.enumerated() {
            for (dabIndex, dab) in group.dabs.enumerated() {
                try meter.visit(1)
                let raw = dab.bounds
                guard raw.minX.isFinite, raw.minY.isFinite, raw.width.isFinite, raw.height.isFinite else {
                    throw .invalidWindow
                }
                let bounds = dab.bounds.integral.applying(group.transform).integral.intersection(window)
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
                    support: &support, meter: &meter)
        try meter.checkCapacity(support, chargedCount: count)
        try meter.checkCapacity(patches, chargedCount: patches.count)
        try meter.checkCapacity(spans, chargedCount: spans.count)
        try meter.checkCapacity(addresses, chargedCount: addresses.count)
        return Packet(width: width, height: height, patches: patches, contacts: contacts,
                      canonicalCoverage: spans)
    }
}
