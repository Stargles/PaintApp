import Foundation

/// **Which size of a baked frame** — SCHEDULER_DESIGN.md §3, "Tiers": every bake file holds the frame
/// twice, whole and at half the width and height, so a step at fit zoom decodes a quarter of the bytes
/// (25 MiB, not 95 MiB, at 5000²) and the canvas can always put a whole-canvas picture on screen
/// without waiting for the big one.
nonisolated enum BakeLevel: Int, CaseIterable {
    case full = 0
    case half = 1

    /// This level's size for a frame whose full size is `width`×`height`: half rounds up, so an odd
    /// edge keeps its last column.
    func size(fullWidth width: Int, fullHeight height: Int) -> (width: Int, height: Int) {
        switch self {
        case .full: return (width, height)
        case .half: return ((width + 1) / 2, (height + 1) / 2)
        }
    }

    /// The decoded ring names one frame's two sizes apart.
    var ringSuffix: String { self == .full ? "" : "@half" }
}

/// **The bytes of a bake file (`FrameBakeStore`'s format version 2), as pure functions** — the layout,
/// the tile codec and the box filter, with no file, lock or budget in them so the fast tier reaches
/// every branch. The store owns where a file lives and what it may hold; this owns what is in it.
nonisolated enum BakeFile {

    /// What the 64-byte header says.
    struct Header: Equatable {
        let fullWidth: Int
        let fullHeight: Int
        let digest: Data

        var halfWidth: Int { BakeLevel.half.size(fullWidth: fullWidth, fullHeight: fullHeight).width }
        var halfHeight: Int { BakeLevel.half.size(fullWidth: fullWidth, fullHeight: fullHeight).height }

        func size(of level: BakeLevel) -> (width: Int, height: Int) {
            level.size(fullWidth: fullWidth, fullHeight: fullHeight)
        }

        func columns(of level: BakeLevel) -> Int {
            (size(of: level).width + FrameBakeStore.tileSide - 1) / FrameBakeStore.tileSide
        }

        func rows(of level: BakeLevel) -> Int {
            (size(of: level).height + FrameBakeStore.tileSide - 1) / FrameBakeStore.tileSide
        }

        func tileCount(of level: BakeLevel) -> Int { columns(of: level) * rows(of: level) }

        /// Where tile `index` of `level` sits in the level, and how big it is (edge tiles are smaller).
        func tileRect(_ index: Int, of level: BakeLevel) -> (x: Int, y: Int, width: Int, height: Int) {
            let side = FrameBakeStore.tileSide
            let columns = columns(of: level), whole = size(of: level)
            let x = (index % columns) * side, y = (index / columns) * side
            return (x, y, min(side, whole.width - x), min(side, whole.height - y))
        }

        /// Entries before this level's in the directory.
        func firstEntry(of level: BakeLevel) -> Int { level == .full ? 0 : tileCount(of: .full) }

        var directoryBytes: Int { 4 * (tileCount(of: .full) + tileCount(of: .half)) }

        var prefixBytes: Int { FrameBakeStore.headerBytes + directoryBytes }

        func encoded() -> Data {
            var data = Data(capacity: FrameBakeStore.headerBytes)
            data.append(contentsOf: FrameBakeStore.magic)
            data.appendLE(FrameBakeStore.formatVersion)
            data.appendLE(UInt16(0))
            data.appendLE(UInt32(fullWidth))
            data.appendLE(UInt32(fullHeight))
            data.appendLE(UInt32(halfWidth))
            data.appendLE(UInt32(halfHeight))
            data.appendLE(UInt32(FrameBakeStore.tileSide))
            data.appendLE(UInt32(0))
            data.append(digest)
            return data
        }

        /// The header in the first `headerBytes` of `data`, or nil for anything this build did not
        /// write: another magic or version, a tile side it does not use, sizes that do not agree with
        /// each other, or a size whose arithmetic overflows.
        static func parse(_ data: Data) -> Header? {
            guard data.count >= FrameBakeStore.headerBytes,
                  Array(data.prefix(4)) == FrameBakeStore.magic,
                  data.readLE(at: 4) as UInt16 == FrameBakeStore.formatVersion,
                  data.readLE(at: 6) as UInt16 == 0,
                  data.readLE(at: 24) as UInt32 == UInt32(FrameBakeStore.tileSide) else { return nil }
            let width = Int(data.readLE(at: 8) as UInt32), height = Int(data.readLE(at: 12) as UInt32)
            guard width > 0, height > 0, width <= maxSide, height <= maxSide,
                  Int(data.readLE(at: 16) as UInt32) == (width + 1) / 2,
                  Int(data.readLE(at: 20) as UInt32) == (height + 1) / 2 else { return nil }
            return Header(fullWidth: width, fullHeight: height,
                          digest: data.subdata(in: data.startIndex + 32..<data.startIndex + 64))
        }
    }

    /// The longest side a header may claim: far past any canvas, and small enough that the arithmetic
    /// below cannot overflow on a corrupt file.
    static let maxSide = 1 << 16

    /// The tile directory: every tile's stored length and whether it is stored raw.
    struct Directory: Equatable {
        let header: Header
        let entries: [UInt32]

        init?(header: Header, data: Data) {
            guard data.count == header.directoryBytes else { return nil }
            self.header = header
            entries = (0..<data.count / 4).map { data.readLE(at: $0 * 4) as UInt32 }
        }

        init(header: Header, entries: [UInt32]) {
            self.header = header
            self.entries = entries
        }

        func length(of tile: Int, in level: BakeLevel) -> Int {
            Int(entries[header.firstEntry(of: level) + tile] & ~FrameBakeStore.rawTileBit)
        }

        func isRaw(_ tile: Int, in level: BakeLevel) -> Bool {
            entries[header.firstEntry(of: level) + tile] & FrameBakeStore.rawTileBit != 0
        }

        /// The stored bytes of one level: where they start in the file and how many.
        func payload(of level: BakeLevel) -> Range<Int> {
            let full = (0..<header.tileCount(of: .full)).reduce(0) { $0 + length(of: $1, in: .full) }
            let start = header.prefixBytes + (level == .full ? 0 : full)
            let count = (0..<header.tileCount(of: level)).reduce(0) { $0 + length(of: $1, in: level) }
            return start..<(start + count)
        }

        /// The size the whole file must be: a file that is not exactly this is truncated or padded.
        var fileLength: Int { header.prefixBytes + payload(of: .full).count + payload(of: .half).count }

        /// A tile's bytes are sane: stored raw means exactly its pixels, and no stored length is zero.
        var isConsistent: Bool {
            for level in BakeLevel.allCases {
                for tile in 0..<header.tileCount(of: level) {
                    let rect = header.tileRect(tile, of: level)
                    let length = length(of: tile, in: level)
                    guard length > 0 else { return false }
                    if isRaw(tile, in: level), length != rect.width * rect.height * 4 { return false }
                }
            }
            return true
        }
    }

    // MARK: - Encoding

    /// The whole file for one frame, or nil for a degenerate size. `bgra` is the frame as the store
    /// writes it (`FrameBakeStore.bgraBytes`): tightly packed, premultiplied, alpha first. Peak
    /// memory beyond the input is the output and one tile's two buffers: the half level is filtered
    /// tile by tile from the full pixels and never held whole.
    @_optimize(speed)
    static func encode(bgra: [UInt8], width: Int, height: Int, digest: Data) -> Data? {
        guard width > 0, height > 0, width <= maxSide, height <= maxSide,
              bgra.count == width * height * 4, digest.count == 32 else { return nil }
        let header = Header(fullWidth: width, fullHeight: height, digest: digest)
        var entries: [UInt32] = []
        entries.reserveCapacity(header.tileCount(of: .full) + header.tileCount(of: .half))
        var payload = Data()
        let side = FrameBakeStore.tileSide
        var tile = [UInt8](repeating: 0, count: side * side * 4)
        var packed = [UInt8](repeating: 0, count: side * side * 4)

        bgra.withUnsafeBufferPointer { source in
            for level in BakeLevel.allCases {
                for index in 0..<header.tileCount(of: level) {
                    let rect = header.tileRect(index, of: level)
                    let count = rect.width * rect.height * 4
                    tile.withUnsafeMutableBufferPointer { destination in
                        switch level {
                        case .full:
                            copyRows(from: source, stride: width * 4, x: rect.x, y: rect.y,
                                     width: rect.width, height: rect.height, to: destination)
                        case .half:
                            halve(from: source, fullWidth: width, fullHeight: height,
                                  x: rect.x, y: rect.y, width: rect.width, height: rect.height, to: destination)
                        }
                    }
                    let written = tile.withUnsafeBufferPointer { raw in
                        packed.withUnsafeMutableBufferPointer { out in
                            LZ4Block.encode(UnsafeRawBufferPointer(start: raw.baseAddress, count: count),
                                            into: UnsafeMutableRawBufferPointer(start: out.baseAddress, count: count))
                        }
                    }
                    if written > 0, written < count {
                        payload.append(contentsOf: packed[0..<written])
                        entries.append(UInt32(written))
                    } else {
                        payload.append(contentsOf: tile[0..<count])
                        entries.append(UInt32(count) | FrameBakeStore.rawTileBit)
                    }
                }
            }
        }
        var file = header.encoded()
        file.reserveCapacity(header.prefixBytes + payload.count)
        for entry in entries { file.appendLE(entry) }
        file.append(payload)
        return file
    }

    @_optimize(speed)
    private static func copyRows(from source: UnsafeBufferPointer<UInt8>, stride: Int, x: Int, y: Int,
                                 width: Int, height: Int, to destination: UnsafeMutableBufferPointer<UInt8>) {
        guard let src = source.baseAddress, let dst = destination.baseAddress else { return }
        for row in 0..<height {
            memcpy(dst + row * width * 4, src + (y + row) * stride + x * 4, width * 4)
        }
    }

    /// One tile of the half level: each half pixel is the mean of the (up to four) full pixels under
    /// it, per channel. The pixels are premultiplied, so the mean of premultiplied values is the
    /// premultiplied mean — no unpremultiply round trip. An odd edge averages the pixels it has.
    @_optimize(speed)
    private static func halve(from source: UnsafeBufferPointer<UInt8>, fullWidth: Int, fullHeight: Int,
                              x: Int, y: Int, width: Int, height: Int,
                              to destination: UnsafeMutableBufferPointer<UInt8>) {
        guard let src = source.baseAddress, let dst = destination.baseAddress else { return }
        for row in 0..<height {
            let fy = (y + row) * 2
            let rows = min(2, fullHeight - fy)
            for column in 0..<width {
                let fx = (x + column) * 2
                let columns = min(2, fullWidth - fx)
                let count = rows * columns
                var sums: (Int, Int, Int, Int) = (0, 0, 0, 0)
                for dy in 0..<rows {
                    for dx in 0..<columns {
                        let p = src + ((fy + dy) * fullWidth + fx + dx) * 4
                        sums.0 += Int(p[0]); sums.1 += Int(p[1]); sums.2 += Int(p[2]); sums.3 += Int(p[3])
                    }
                }
                let out = dst + (row * width + column) * 4
                let half = count / 2
                out[0] = UInt8((sums.0 + half) / count)
                out[1] = UInt8((sums.1 + half) / count)
                out[2] = UInt8((sums.2 + half) / count)
                out[3] = UInt8((sums.3 + half) / count)
            }
        }
    }

    // MARK: - Decoding

    /// Decodes `level` into `destination`, tightly packed (`width * 4` a row). `payload` is exactly
    /// `directory.payload(of: level)` — the level's bytes and no others. False on any tile that does
    /// not decode to its size.
    @_optimize(speed)
    static func decode(level: BakeLevel, directory: Directory, payload: Data,
                       into destination: UnsafeMutableRawBufferPointer) -> Bool {
        let header = directory.header
        let whole = header.size(of: level)
        guard let base = destination.baseAddress, destination.count == whole.width * whole.height * 4,
              payload.count == directory.payload(of: level).count else { return false }
        let side = FrameBakeStore.tileSide
        var scratch = [UInt8](repeating: 0, count: side * side * 4)
        var offset = 0
        for index in 0..<header.tileCount(of: level) {
            let rect = header.tileRect(index, of: level)
            let length = directory.length(of: index, in: level)
            let count = rect.width * rect.height * 4
            let ok: Bool = payload.withUnsafeBytes { all in
                let stored = UnsafeRawBufferPointer(rebasing: all[offset..<(offset + length)])
                if directory.isRaw(index, in: level) {
                    guard length == count else { return false }
                    scatter(stored, rect: rect, stride: whole.width * 4, to: base)
                    return true
                }
                return scratch.withUnsafeMutableBytes { out in
                    guard LZ4Block.decode(stored, into: UnsafeMutableRawBufferPointer(rebasing: out[0..<count])) else {
                        return false
                    }
                    scatter(UnsafeRawBufferPointer(rebasing: out[0..<count]), rect: rect,
                            stride: whole.width * 4, to: base)
                    return true
                }
            }
            guard ok else { return false }
            offset += length
        }
        return true
    }

    @_optimize(speed)
    private static func scatter(_ tile: UnsafeRawBufferPointer, rect: (x: Int, y: Int, width: Int, height: Int),
                                stride: Int, to base: UnsafeMutableRawPointer) {
        guard let src = tile.baseAddress else { return }
        for row in 0..<rect.height {
            memcpy(base + (rect.y + row) * stride + rect.x * 4, src + row * rect.width * 4, rect.width * 4)
        }
    }
}

// MARK: - Little-endian fields

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Byte-wise rather than `load(fromByteOffset:)`, which traps on an unaligned address and would
    /// turn a corrupt file into a crash — the one thing a read promises never to do.
    func readLE<T: FixedWidthInteger>(at offset: Int) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size {
            value |= T(self[startIndex + offset + i]) << (8 * i)
        }
        return value
    }
}
