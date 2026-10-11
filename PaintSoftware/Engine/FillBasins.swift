import Foundation

/// **Gap closing as a partition of the open paper, rather than as a morphological close** — TODO (158).
///
/// The owner, on what the close it replaces did: *"when it is turned up and the user fills a square
/// with a small opening, the feature works as intended, but also leaves the places near the edges of
/// the squares not filled in."* A close of radius r keeps the fill wherever an r-disk fits, so every
/// corner and every pocket narrower than the disk was treated as a gap, and the fill curled in from
/// them by more as the slider rose. What the artist means by a gap is narrower than that: **a place
/// where two open areas meet through a passage that is narrow compared with both.** That is a question
/// about the distance map, and this answers it there.
///
/// **The model.** Let D be each open pixel's distance to the nearest ink (`gapLevels` in Fill.metal).
/// Every local maximum of D is the middle of some open area, and flooding the paper from those maxima
/// in order of falling D — a watershed — gives every pixel to exactly one of them: its **basin**. Two
/// basins meet along the lowest ridge of D between them, and the D at the best crossing of that ridge
/// (the **saddle**) is half the width of the passage joining them. So:
///
/// - **a gap is a saddle**: two basins joined through a passage about `2·saddle` px wide, which the
///   slider seals when `2·saddle` is at most the slider's number. So every opening narrower than the
///   number seals, and none wider ever does — an even width seals at its own number and an odd one
///   at one more, since the middle pixel of an odd gap `w` wide is `(w + 1) / 2` from the ink on
///   either side, centre to centre;
/// - **an edge or a corner is not**: it has no maximum of its own, so it belongs to the basin it slopes
///   down from and fills with it at every setting. That is the ask, and it falls out of the model
///   rather than being special-cased;
/// - **the sudden jump the owner describes at a real gap** stays, and only there: it is the setting at
///   which that one saddle seals.
///
/// **A basin must be a place, not a ripple.** Hand-drawn ink makes D bumpy, and every bump is a maximum
/// with a saddle a hair below it; a shape with a wobbly outline would otherwise come apart into strips
/// at its narrow points. So a basin that meets an older one — one with a higher peak — at a saddle it
/// barely rises above is **noise** and is joined to it at every setting: it must rise at least
/// `minimumDepth` above that saddle *and* at least `minimumRatio` times it, which is a room behind a
/// door rather than a bay along a wall. The test is made once, on the full merge tree, so it does not
/// move with the slider and the partition is monotone in it: an opening that seals stays sealed at
/// every higher setting.
///
/// **Speed: the slider never re-runs any of this.** D, the basins and the merge tree depend on the ink
/// and the seed, not on the slider. They are built once per press (`init`), and each slider value is
/// a union-find over the merge tree — one entry per basin — plus a table lookup per pixel on the GPU
/// (`basinRegion`).
///
/// **Only the seed's plain fill is looked at.** The watershed runs over `inDomain` — the pixels the
/// flood reaches with no gap closing at all — so its cost is the region being filled, and it cannot
/// put paint anywhere the plain fill could not reach.
struct FillBasins {

    /// D is quantised to this many levels a pixel, so the watershed's priority queue is a bucket queue
    /// and the whole build is linear in the pixels it covers.
    static let levelsPerPixel = 4

    /// A basin is noise unless its peak rises at least this far above the saddle it first meets an
    /// older basin at, in pixels of D…
    static let minimumDepth = 1
    /// …and to at least this multiple of that saddle. 1.5 is a pocket whose widest point is half as
    /// wide again as its mouth.
    static let minimumRatio = 1.5

    /// One edge of the merge tree: the two basins it joins and the level of the saddle between them.
    struct Merge: Equatable {
        let a: Int32
        let b: Int32
        let saddle: UInt16
        /// Joined at every setting — see the type's comment on ripples.
        let isNoise: Bool
    }

    /// Each basin's highest level.
    let peaks: [UInt16]
    /// The merge tree, highest saddle first.
    let merges: [Merge]

    var basinCount: Int { peaks.count }

    /// The level at and below which a saddle is sealed: `2·D ≤ gapWidth`.
    static func sealingLevel(forGapWidth gapWidth: Float) -> Int {
        guard gapWidth >= 1 else { return -1 }
        return Int((gapWidth / 2 * Float(levelsPerPixel)).rounded(.down))
    }

    /// The farthest distance to ink, in pixels, that the cut for `gapWidth` can depend on: the saddles
    /// it may seal reach half the width, and telling a place from a ripple there reads a peak up to
    /// `minimumRatio` times as high, or `minimumDepth` above it. A distance map exact up to this is
    /// a partition exact at this setting — `FillWindow.halo` is built on it.
    static func reach(forGapWidth gapWidth: Float) -> Float {
        guard gapWidth >= 1 else { return 0 }
        let saddle = gapWidth / 2
        return max(saddle * Float(minimumRatio), saddle + Float(minimumDepth))
    }

    /// The watershed of `levels` over the pixels `inDomain` marks, written into `labels` as each pixel's
    /// basin (−1 outside the domain), and the merge tree between the basins.
    ///
    /// - Parameters:
    ///   - levels: D per pixel, in `levelsPerPixel`ths of a pixel.
    ///   - inDomain: non-zero where the plain fill reached.
    ///   - scratch: two `Int32` a pixel, overwritten — the bucket order and the queue's links.
    init(levels: UnsafePointer<UInt16>, inDomain: UnsafePointer<UInt8>, width: Int, height: Int,
         labels: UnsafeMutablePointer<Int32>, scratch: UnsafeMutablePointer<Int32>) {
        let count = width * height
        labels.update(repeating: -1, count: count)

        // Bucket the domain by level: `order` lists it level by level, lowest first.
        var counts = [Int32](repeating: 0, count: 65537)
        var highest = 0, lowest = 65535
        for i in 0..<count where inDomain[i] != 0 {
            let l = Int(levels[i])
            counts[l + 1] += 1
            highest = max(highest, l); lowest = min(lowest, l)
        }
        guard highest >= lowest else { self.peaks = []; self.merges = []; return }
        for l in 1...65536 { counts[l] += counts[l - 1] }   // counts[l] is now where level l starts
        let order = scratch
        let next = scratch + count
        var fillAt = Array(counts[0...highest])
        for i in 0..<count where inDomain[i] != 0 {
            let l = Int(levels[i])
            order[Int(fillAt[l])] = Int32(i)
            fillAt[l] += 1
        }

        // One FIFO a level, linked through `next`. FIFO within a level is what splits a plateau
        // between the basins flooding into it by distance rather than by scan order.
        var head = [Int32](repeating: -1, count: highest + 1)
        var tail = [Int32](repeating: -1, count: highest + 1)
        func push(_ p: Int, _ l: Int) {
            next[p] = -1
            if tail[l] < 0 { head[l] = Int32(p) } else { next[Int(tail[l])] = Int32(p) }
            tail[l] = Int32(p)
        }

        var peaks: [UInt16] = []
        // The highest saddle seen between each pair of basins, keyed low basin << 32 | high basin.
        var saddles: [UInt64: UInt16] = [:]
        func meet(_ a: Int32, _ b: Int32, at level: Int) {
            let key = a < b ? UInt64(a) << 32 | UInt64(b) : UInt64(b) << 32 | UInt64(a)
            let l = UInt16(level)
            if let seen = saddles[key], seen >= l { return }
            saddles[key] = l
        }

        // Every pixel above the level being flooded is labelled by the time it is reached, so an
        // unlabelled pixel left at this level after its queue runs dry is a maximum of its own.
        for level in stride(from: highest, through: lowest, by: -1) {
            var cursor = Int(counts[level])
            let end = Int(counts[level + 1])
            while true {
                while head[level] >= 0 {
                    let p = Int(head[level])
                    head[level] = next[p]
                    if head[level] < 0 { tail[level] = -1 }
                    let basin = labels[p]
                    let x = p % width
                    // 4-connected, as the flood is: a diagonal step would cross a one-pixel diagonal line.
                    @inline(__always) func visit(_ q: Int) {
                        guard inDomain[q] != 0 else { return }
                        let other = labels[q]
                        if other < 0 {
                            labels[q] = basin
                            push(q, Int(levels[q]))
                        } else if other != basin {
                            meet(basin, other, at: min(level, Int(levels[q])))
                        }
                    }
                    if x > 0 { visit(p - 1) }
                    if x < width - 1 { visit(p + 1) }
                    if p >= width { visit(p - width) }
                    if p < count - width { visit(p + width) }
                }
                while cursor < end, labels[Int(order[cursor])] >= 0 { cursor += 1 }
                guard cursor < end else { break }
                let p = Int(order[cursor])
                labels[p] = Int32(peaks.count)
                peaks.append(UInt16(level))
                push(p, level)
            }
        }

        // The merge tree: Kruskal over the saddles, highest first. When two components join, the one
        // with the lower peak is the younger, and whether it is a place or a ripple is decided here.
        let edges = saddles.map { (key: $0.key, saddle: $0.value) }.sorted { $0.saddle > $1.saddle }
        var parent = Array(Int32(0)..<Int32(peaks.count))
        let top = peaks
        func find(_ x: Int32) -> Int32 {
            var r = x
            while parent[Int(r)] != r { r = parent[Int(r)] }
            var y = x
            while parent[Int(y)] != r { let n = parent[Int(y)]; parent[Int(y)] = r; y = n }
            return r
        }
        var merges: [Merge] = []
        merges.reserveCapacity(max(0, peaks.count - 1))
        let depth = Self.minimumDepth * Self.levelsPerPixel
        for edge in edges {
            let a = Int32(edge.key >> 32), b = Int32(edge.key & 0xFFFF_FFFF)
            let ra = find(a), rb = find(b)
            guard ra != rb else { continue }
            let (older, younger) = top[Int(ra)] >= top[Int(rb)] ? (ra, rb) : (rb, ra)
            let peak = Double(top[Int(younger)]), saddle = Double(edge.saddle)
            let isPlace = peak >= saddle + Double(depth) && peak >= saddle * Self.minimumRatio
            merges.append(Merge(a: a, b: b, saddle: edge.saddle, isNoise: !isPlace))
            parent[Int(younger)] = older
        }
        self.peaks = peaks
        self.merges = merges
    }

    /// One byte a basin: 1 where the basin is joined to any of `seeds` once every opening up to
    /// `gapWidth` pixels wide is sealed, 0 elsewhere. `seeds` outside the domain (−1) reach nothing.
    func reached(from seeds: [Int32], gapWidth: Float) -> [UInt8] {
        let sealing = Self.sealingLevel(forGapWidth: gapWidth)
        var parent = Array(Int32(0)..<Int32(peaks.count))
        func find(_ x: Int32) -> Int32 {
            var r = x
            while parent[Int(r)] != r { r = parent[Int(r)] }
            var y = x
            while parent[Int(y)] != r { let n = parent[Int(y)]; parent[Int(y)] = r; y = n }
            return r
        }
        for merge in merges where merge.isNoise || Int(merge.saddle) > sealing {
            let ra = find(merge.a), rb = find(merge.b)
            if ra != rb { parent[Int(ra)] = rb }
        }
        var reachedRoots = Set<Int32>()
        for seed in seeds where seed >= 0 && Int(seed) < peaks.count { reachedRoots.insert(find(seed)) }
        var table = [UInt8](repeating: 0, count: max(1, peaks.count))
        guard !reachedRoots.isEmpty else { return table }
        for basin in 0..<peaks.count where reachedRoots.contains(find(Int32(basin))) { table[basin] = 1 }
        return table
    }
}
