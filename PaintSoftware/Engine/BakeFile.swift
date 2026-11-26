import Foundation
import Accelerate

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

    /// The whole file for one frame, or nil for a degenerate size or a resample that failed. `bgra` is
    /// the frame as the store writes it (`FrameBakeStore.bgraBytes`): tightly packed, premultiplied,
    /// alpha first. **Peak memory beyond the input is the output and a few tiles' buffers — nothing
    /// proportional to the canvas**: the half level is resampled one tile at a time (`halfTile`), because
    /// `vImageScale` needs an intermediate of source height × destination width × 4 bytes (47.7 MiB at
    /// 5000², MEASURED with `kvImageGetTempBufferSize`) that no budget is asked about.
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
        var scratch = [UInt8](repeating: 0, count: (side + 2 * halfMargin) * (side + 2 * halfMargin) * 4)
        var failed = false

        bgra.withUnsafeBufferPointer { full in
            for level in BakeLevel.allCases {
                for index in 0..<header.tileCount(of: level) {
                    let rect = header.tileRect(index, of: level)
                    let count = rect.width * rect.height * 4
                    tile.withUnsafeMutableBufferPointer { destination in
                        switch level {
                        case .full:
                            copyRows(from: full, stride: width * 4, x: rect.x, y: rect.y,
                                     width: rect.width, height: rect.height, to: destination)
                        case .half:
                            failed = failed || !halfTile(of: full, width: width, height: height, rect: rect,
                                                         halfSize: (header.halfWidth, header.halfHeight),
                                                         scratch: &scratch, into: destination)
                        }
                    }
                    if failed { return }
                    let written = tile.withUnsafeBufferPointer { raw in
                        packed.withUnsafeMutableBufferPointer { out in
                            LZ4Block.encode(UnsafeRawBufferPointer(start: raw.baseAddress, count: count),
                                            into: UnsafeMutableRawBufferPointer(start: out.baseAddress, count: count))
                        }
                    }
                    // `Data.append(_:count:)` is one memcpy; appending an array slice is a byte loop that
                    // costs seconds a frame in a Debug build.
                    if written > 0, written < count {
                        packed.withUnsafeBufferPointer { payload.append($0.baseAddress!, count: written) }
                        entries.append(UInt32(written))
                    } else {
                        tile.withUnsafeBufferPointer { payload.append($0.baseAddress!, count: count) }
                        entries.append(UInt32(count) | FrameBakeStore.rawTileBit)
                    }
                }
            }
        }
        guard !failed else { return nil }
        var file = header.encoded()
        file.reserveCapacity(header.prefixBytes + payload.count)
        for entry in entries { file.appendLE(entry) }
        file.append(payload)
        return file
    }

    private static func copyRows(from source: UnsafeBufferPointer<UInt8>, stride: Int, x: Int, y: Int,
                                 width: Int, height: Int, to destination: UnsafeMutableBufferPointer<UInt8>) {
        guard let src = source.baseAddress, let dst = destination.baseAddress else { return }
        for row in 0..<height {
            memcpy(dst + row * width * 4, src + (y + row) * stride + x * 4, width * 4)
        }
    }

    /// Half-level pixels resampled beyond a tile on each side, so a tile's edge is made from the same
    /// neighbours the whole frame's resample would use: `vImageScale`'s Lanczos kernel reaches 3
    /// destination pixels at most, and a tile that met its own border without them would show a seam.
    static let halfMargin = 8

    /// One tile of the half level — the frame at half the width and height, premultiplied BGRA —
    /// resampled from the source rows and columns it covers plus `halfMargin` each side (clamped to
    /// the frame), at the speed of Accelerate in every build configuration (a hand-written box filter
    /// was exact and took 3.5 s a 4096² frame in a Debug build, where the playcheck gate and every test
    /// run). The scale is exactly 2:1 except at an odd last row or column, which keeps its own pixels
    /// like any other edge. `scratch` holds the margin-wide result; `vImageScale`'s own intermediate is
    /// that region's height × width × 4 bytes, about 2 MiB.
    private static func halfTile(of bgra: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                                 rect: (x: Int, y: Int, width: Int, height: Int),
                                 halfSize half: (width: Int, height: Int),
                                 scratch: inout [UInt8], into destination: UnsafeMutableBufferPointer<UInt8>) -> Bool {
        guard let source = bgra.baseAddress, let out = destination.baseAddress else { return false }
        let dx0 = max(0, rect.x - halfMargin), dx1 = min(half.width, rect.x + rect.width + halfMargin)
        let dy0 = max(0, rect.y - halfMargin), dy1 = min(half.height, rect.y + rect.height + halfMargin)
        let sx0 = 2 * dx0, sx1 = min(width, 2 * dx1), sy0 = 2 * dy0, sy1 = min(height, 2 * dy1)
        let dw = dx1 - dx0, dh = dy1 - dy0
        guard dw > 0, dh > 0, sx1 > sx0, sy1 > sy0, scratch.count >= dw * dh * 4 else { return false }
        let status: vImage_Error = scratch.withUnsafeMutableBytes { region in
            var from = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source + (sy0 * width + sx0) * 4),
                                     height: vImagePixelCount(sy1 - sy0), width: vImagePixelCount(sx1 - sx0),
                                     rowBytes: width * 4)
            var to = vImage_Buffer(data: region.baseAddress, height: vImagePixelCount(dh),
                                   width: vImagePixelCount(dw), rowBytes: dw * 4)
            return vImageScale_ARGB8888(&from, &to, nil, vImage_Flags(kvImageHighQualityResampling))
        }
        guard status == kvImageNoError else { return false }
        scratch.withUnsafeBytes { region in
            for row in 0..<rect.height {
                memcpy(out + row * rect.width * 4,
                       region.baseAddress! + ((rect.y - dy0 + row) * dw + (rect.x - dx0)) * 4, rect.width * 4)
            }
        }
        return true
    }

    // MARK: - Decoding

    /// Decodes `level` into `destination`, tightly packed (`width * 4` a row). `payload` is exactly
    /// `directory.payload(of: level)` — the level's bytes and no others. False on any tile that does
    /// not decode to its size.
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
