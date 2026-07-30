import CoreGraphics
import Foundation

/// A uniform grid over stroke *segment* bounding boxes, so "what is near this rect?" costs the size
/// of the rect instead of the size of the layer.
///
/// This is the piece that keeps the vector eraser off the performance-intensive path. Today's
/// `VectorCanvas.erase` is O(all samples × all eraser points) with a nested loop over every stroke on
/// the layer; every eraser mode built on this index is O(segments in the eraser's swept box) instead.
/// It also serves Mode 3's intersection queries, Mode 1's coverage test and garbage collection, and
/// later liquify's affected-stroke query.
///
/// Keyed on an **opaque `elementIndex` supplied by the caller** rather than on strokes it owns: from
/// Phase 1 on, `VectorCanvas` holds one mixed display list of strokes, fills and images, and the
/// index has no business knowing which kinds exist. The caller inserts the segment geometry it wants
/// found and interprets the indices that come back.
///
/// `CoreGraphics`/`Foundation` only, like `StrokeGeometry`, so it compiles into the test target and
/// its correctness can be checked against brute force headlessly.
///
/// **Not thread-safe, and not internally locked.** `segments(near:)` mutates a per-query visit stamp
/// (see below), so it is not even safe for concurrent *reads*. That is deliberate: the index is a
/// short-lived derived cache built and queried by whichever context is editing a cel, and adding a
/// lock here would mean taking one per query on the touch path. Build one per user, or rebuild it
/// behind `VectorCanvas`'s existing lock.
final class StrokeSpatialIndex {

    /// One segment of one element: the span from `sampleIndex` to `sampleIndex + 1` of the sample run
    /// at `elementIndex`.
    struct SegmentRef: Hashable {
        var elementIndex: Int
        var sampleIndex: Int

        init(elementIndex: Int, sampleIndex: Int) {
            self.elementIndex = elementIndex
            self.sampleIndex = sampleIndex
        }
    }

    /// ~64pt cells: a couple of brush widths across, so a typical eraser query touches one to four
    /// cells while a long stroke still spreads across enough of them to be worth rejecting. Small
    /// enough to be selective, large enough that a stroke segment rarely spans more than a few.
    static let defaultCellSize: CGFloat = 64

    let cellSize: CGFloat

    /// All inserted refs, in insertion order. Buckets hold indices into this rather than copies of the
    /// refs: one shared array keeps the hot query loop reading contiguous memory, and — more
    /// importantly — gives every ref a stable slot number, which is what makes the O(1) dedup below
    /// possible without hashing.
    private var refs: [SegmentRef] = []
    /// Cell key → slots in `refs`. A segment's box usually covers one or two cells, so the per-bucket
    /// arrays stay short.
    private var buckets: [Int64: [Int32]] = [:]

    /// Per-slot "last query that already emitted this ref". A segment whose box spans several cells is
    /// reached once per cell it occupies, and a query must report it once; comparing against a
    /// monotonically increasing token deduplicates in constant time with no `Set`, no hashing, and no
    /// clearing pass between queries.
    private var visitToken: [UInt32] = []
    private var currentToken: UInt32 = 0

    init(cellSize: CGFloat = StrokeSpatialIndex.defaultCellSize) {
        // A non-positive cell size would divide by zero and put everything in one bucket; fall back
        // rather than trap, since this is a performance structure and a bad parameter should degrade,
        // not crash a drawing session.
        self.cellSize = cellSize > 0 ? cellSize : StrokeSpatialIndex.defaultCellSize
    }

    var isEmpty: Bool { refs.isEmpty }
    /// Number of segments inserted (not the number of bucket entries, which is larger).
    var count: Int { refs.count }

    func removeAll() {
        refs.removeAll(keepingCapacity: true)
        buckets.removeAll(keepingCapacity: true)
        visitToken.removeAll(keepingCapacity: true)
    }

    // MARK: - Building

    /// Indexes every segment of `samples` under `elementIndex`.
    ///
    /// `padding` inflates each segment's box — pass the stroke's maximum half-width there. Without it
    /// the index answers "whose *centerline* is near this rect", and an eraser sweeping just past a
    /// fat stroke's centerline would find nothing to erase even though it is squarely on the ink. The
    /// caller owns the value because only it knows the brush and size.
    ///
    /// A single-sample run indexes one zero-length segment (`sampleIndex == 0`), matching the lone dab
    /// it renders as; a caller walking the returned refs must therefore tolerate
    /// `sampleIndex == samples.count - 1` for such runs.
    func insert(samples: [VectorSample], elementIndex: Int, padding: CGFloat = 0) {
        guard !samples.isEmpty else { return }
        guard samples.count > 1 else {
            insert(SegmentRef(elementIndex: elementIndex, sampleIndex: 0),
                   box: box(samples[0].point, samples[0].point, padding: padding))
            return
        }
        for i in 0..<(samples.count - 1) {
            insert(SegmentRef(elementIndex: elementIndex, sampleIndex: i),
                   box: box(samples[i].point, samples[i + 1].point, padding: padding))
        }
    }

    /// Indexes every segment of a bare polyline under `elementIndex` — the eraser's own path, or any
    /// pressure-free contour.
    func insert(polyline: [CGPoint], elementIndex: Int, padding: CGFloat = 0) {
        guard !polyline.isEmpty else { return }
        guard polyline.count > 1 else {
            insert(SegmentRef(elementIndex: elementIndex, sampleIndex: 0),
                   box: box(polyline[0], polyline[0], padding: padding))
            return
        }
        for i in 0..<(polyline.count - 1) {
            insert(SegmentRef(elementIndex: elementIndex, sampleIndex: i),
                   box: box(polyline[i], polyline[i + 1], padding: padding))
        }
    }

    /// Convenience builder for a flat list of sample runs, indexed by their position in the array —
    /// the shape a caller with only strokes (a test, or a `VectorCanvas` before the Phase 1 display
    /// list lands) has on hand.
    static func build(strokes: [[VectorSample]], cellSize: CGFloat = StrokeSpatialIndex.defaultCellSize,
                      padding: CGFloat = 0) -> StrokeSpatialIndex {
        let index = StrokeSpatialIndex(cellSize: cellSize)
        for (elementIndex, samples) in strokes.enumerated() {
            index.insert(samples: samples, elementIndex: elementIndex, padding: padding)
        }
        return index
    }

    private func box(_ a: CGPoint, _ b: CGPoint, padding: CGFloat) -> CGRect {
        let minX = min(a.x, b.x) - padding, maxX = max(a.x, b.x) + padding
        let minY = min(a.y, b.y) - padding, maxY = max(a.y, b.y) + padding
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func insert(_ ref: SegmentRef, box: CGRect) {
        let slot = Int32(refs.count)
        refs.append(ref)
        visitToken.append(0)
        let (x0, y0, x1, y1) = cellRange(of: box)
        var cy = y0
        while cy <= y1 {
            var cx = x0
            while cx <= x1 {
                buckets[Self.key(cx, cy), default: []].append(slot)
                cx += 1
            }
            cy += 1
        }
    }

    // MARK: - Querying

    /// Segments whose (padded) bounding box may intersect `rect`.
    ///
    /// A **broad phase**: it may over-report — anything in a touched cell comes back, box overlap or
    /// not — and must never under-report. Callers narrow with the exact `StrokeGeometry` distance and
    /// intersection tests. Each segment appears at most once even when its box spans several cells.
    func segments(near rect: CGRect) -> [SegmentRef] {
        guard !refs.isEmpty else { return [] }
        // Wrapping the token would let a stale stamp suppress a real hit, so restart the stamps on
        // the (astronomically unlikely) wrap rather than risk a silent under-report.
        if currentToken == UInt32.max {
            for i in visitToken.indices { visitToken[i] = 0 }
            currentToken = 0
        }
        currentToken += 1
        let token = currentToken

        var result: [SegmentRef] = []
        let (x0, y0, x1, y1) = cellRange(of: rect.standardized)
        var cy = y0
        while cy <= y1 {
            var cx = x0
            while cx <= x1 {
                if let bucket = buckets[Self.key(cx, cy)] {
                    for slot in bucket {
                        let i = Int(slot)
                        guard visitToken[i] != token else { continue }
                        visitToken[i] = token
                        result.append(refs[i])
                    }
                }
                cx += 1
            }
            cy += 1
        }
        return result
    }

    // MARK: - Cell arithmetic

    /// Inclusive integer cell range covering `rect`.
    ///
    /// Non-finite coordinates are clamped rather than passed to `Int(...)`, which traps on NaN and on
    /// anything outside `Int`'s range. Stroke samples come from touch input and should never be
    /// non-finite, but a trap in a drawing session is a far worse failure than a slightly wrong
    /// broad-phase answer.
    private func cellRange(of rect: CGRect) -> (Int, Int, Int, Int) {
        (cell(rect.minX), cell(rect.minY), cell(rect.maxX), cell(rect.maxY))
    }

    private func cell(_ value: CGFloat) -> Int {
        guard value.isFinite else { return value < 0 ? Int(Int32.min) : Int(Int32.max) }
        let scaled = (value / cellSize).rounded(.down)
        if scaled <= CGFloat(Int32.min) { return Int(Int32.min) }
        if scaled >= CGFloat(Int32.max) { return Int(Int32.max) }
        return Int(scaled)
    }

    /// Packs two cell coordinates into one key. A bijection over the `Int32` range (not a hash), so
    /// distinct cells can never collide into a shared bucket and silently over-report.
    private static func key(_ cx: Int, _ cy: Int) -> Int64 {
        let x = Int64(Int32(truncatingIfNeeded: cx))
        let y = Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: cy)))
        return (x << 32) | y
    }
}
