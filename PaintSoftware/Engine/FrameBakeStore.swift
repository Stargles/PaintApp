import UIKit
import Compression

// MARK: - The store (RENDER.md §3.5)
//
// The app's first on-disk derived store: one file per bake key, content-addressed by the key's
// SHA-256, holding one frame's BGRA premultiplied rows compressed with LZ4.
//
// **Where it lives, and why not inside the project package.** The default root is
// `Library/Caches/PaintApp/bakes/<projectID>/<renderResolution>/`, which RENDER §2.11 dumps at
// launch. A bake the artist chooses to *keep* goes to `Documents/Projects/<Name>.paintbake/`
// **beside** the `.paintproj` package and never inside it: every save rebuilds the package through
// a staging directory and `ProjectStore.writeAtomically` swaps it over the live one, while
// `ProjectBackupManager.validateProject` gates that swap on manifest-named files — so an unlisted
// bake file inside the package is a file the next save drops, or worse, a file that fails
// validation and sends a perfectly good project to auto-repair. Stage 4a builds only the cache
// root; the reason is written down here so nobody moves it later.
//
// **Purging is an explicit call, not behaviour in `init`.** §2.11 says the bake is dumped between
// launches, and the app makes that true by calling `purgeAll()` at launch. Doing it in `init` would
// make the type unable to open a store over files that already exist, which is what every test in
// `FrameBakeStoreLogicTests` does and what a *kept* bake will need in stage 6.

/// One frame's pixels on disk, named by its `FrameBakeKey`.
///
/// A plain type over a root rather than a singleton: the app hands it the cache directory, a test
/// hands it a temp directory, and stage 6's kept bake hands it a `.paintbake` folder. The override
/// seam matches `ProjectBackupManager.rootDirectoryOverride` rather than inventing a second idiom.
///
/// A `final class` because byte accounting is mutable state two queues touch — the baker writes
/// while the display path reads — and everything below takes one lock.
final class FrameBakeStore {

    // MARK: - Format

    /// **Bumped whenever the bytes on disk change meaning.** It is in the header *and* in the bake
    /// key, which is belt and braces on purpose: the key means an old file is never even looked for,
    /// and the header means one that is looked for anyway is rejected rather than decoded as
    /// something it is not.
    static let formatVersion: UInt16 = 1

    /// `PBK1`.
    static let magic: [UInt8] = [0x50, 0x42, 0x4B, 0x31]

    /// **64 bytes, not the 32 §3.5 wrote.** A SHA-256 digest alone fills 32, so the original number
    /// left no room for the width, height, stride, sizes and flags the same sentence asked for.
    /// Little-endian throughout:
    ///
    /// | offset | size | field |
    /// |---|---|---|
    /// | 0 | 4 | magic `PBK1` |
    /// | 4 | 2 | format version |
    /// | 6 | 2 | flags — bit 0 set = LZ4 payload, clear = stored raw |
    /// | 8 | 4 | pixel width |
    /// | 12 | 4 | pixel height |
    /// | 16 | 4 | bytes per row |
    /// | 20 | 4 | uncompressed payload bytes |
    /// | 24 | 4 | compressed payload bytes |
    /// | 28 | 4 | reserved, zero |
    /// | 32 | 32 | key digest |
    static let headerBytes = 64

    /// Bit 0 of the flags word.
    static let flagCompressed: UInt16 = 1

    /// **`COMPRESSION_LZ4_RAW`, and this is a correction to §3.5's `COMPRESSION_LZ4`.** Apple's
    /// `COMPRESSION_LZ4` wraps the stream in its own `bv41` block framing, which no other LZ4
    /// decoder reads — and §3.5's stated reason for choosing LZ4 at all is that "the format is
    /// portable to any platform with an LZ4 decoder, which is all of them". `_RAW` is the standard
    /// raw block, whose only extra requirement is knowing the uncompressed size before decoding,
    /// and the header above already carries it. So the portable choice costs nothing here.
    private static let algorithm = COMPRESSION_LZ4_RAW

    // MARK: - Roots

    /// Overrides the directory holding `PaintApp/bakes/…`. Nil (the default) is the app's real
    /// Caches directory; logic tests point it at a per-test temp folder. Same seam and same shape as
    /// `ProjectBackupManager.rootDirectoryOverride`.
    nonisolated(unsafe) static var cachesDirectoryOverride: URL?

    static var cachesDirectory: URL {
        cachesDirectoryOverride ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var bakesRootDirectory: URL {
        cachesDirectory.appendingPathComponent("PaintApp", isDirectory: true)
            .appendingPathComponent("bakes", isDirectory: true)
    }

    /// §3.5's default root. The resolution is a path component rather than a key field alone so that
    /// switching the knob does not have to walk every file to decide what is stale — though the key
    /// carries it too, because `affordableSize` can land two knob positions on one buffer.
    static func defaultRoot(projectID: UUID, renderResolution: RenderResolution) -> URL {
        bakesRootDirectory
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(renderResolution.rawValue, isDirectory: true)
    }

    // MARK: - State

    let root: URL

    /// What this store may hold on disk. A write that would exceed it evicts first (§3.5).
    let byteCeiling: Int

    private let lock = NSLock()
    private var bytesOnDisk = 0

    /// **Why a write can fail, and none of these is a document failure** (§2.10, §3.5): the bake
    /// stops, the caller carries on, and playback shows the previous picture.
    enum WriteFailure: Error, Equatable {
        /// The image could not be read as BGRA — a degenerate size, or no context.
        case unreadableImage
        /// One frame is larger than the whole ceiling. Evicting everything would not help.
        case exceedsCeiling(needed: Int, ceiling: Int)
        /// The filesystem refused: full, read-only, or gone.
        case couldNotWrite
        /// A key whose digest is not 32 bytes — the header has a fixed field for it, so there is
        /// nowhere to put a longer one and no way to compare a shorter one on the way back.
        case malformedKey
    }

    init(root: URL, byteCeiling: Int = FrameBakeStore.defaultByteCeiling) {
        self.root = root
        self.byteCeiling = byteCeiling
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        bytesOnDisk = Self.measure(root)
    }

    /// 512 MiB. A number rather than a fraction of the device, because §2.6 forbids a budget
    /// hard-coded to an iPad and a *disk* ceiling has no portable device signal to read. The caller
    /// passes its own where it knows better.
    static let defaultByteCeiling = 512 * 1024 * 1024

    /// What the store is holding, in bytes, right now.
    var totalBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return bytesOnDisk
    }

    func url(for key: FrameBakeKey) -> URL {
        root.appendingPathComponent(key.fileName + ".pbk", isDirectory: false)
    }

    func contains(_ key: FrameBakeKey) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key).path)
    }

    // MARK: - Writing

    /// Writes one frame. Returns the file's size on success.
    ///
    /// `playhead` and `frames` are §3.5's eviction policy: when the write would take the store past
    /// its ceiling, the files **farthest from the playhead** go first. `frames` maps a file name to
    /// the frames that resolve to it — a content-addressed store holds one file for a nine-frame
    /// hold, so "which frame is this" is a set and the distance is the nearest member. A file the
    /// map does not name is unreachable from the current document and is evicted before anything
    /// that is.
    @discardableResult
    func store(_ image: CGImage,
               for key: FrameBakeKey,
               playhead: Int = 0,
               frames: [String: Set<Int>] = [:]) -> Result<Int, WriteFailure> {
        guard key.digest.count == 32 else { return .failure(.malformedKey) }
        guard let pixels = Self.bgraBytes(image) else { return .failure(.unreadableImage) }

        let rawCount = pixels.bytes.count
        var flags: UInt16 = 0
        var payload = pixels.bytes
        if let compressed = Self.compress(pixels.bytes), compressed.count < rawCount {
            payload = compressed
            flags |= Self.flagCompressed
        }
        // An encoder must never make a file bigger than the pixels: if LZ4 did not shrink this
        // frame — noise, or a photograph — the raw bytes go down with the flag clear and the reader
        // takes the other branch.

        var file = Data(capacity: Self.headerBytes + payload.count)
        file.append(contentsOf: Self.magic)
        file.appendLE(Self.formatVersion)
        file.appendLE(flags)
        file.appendLE(UInt32(pixels.width))
        file.appendLE(UInt32(pixels.height))
        file.appendLE(UInt32(pixels.width * 4))
        file.appendLE(UInt32(rawCount))
        file.appendLE(UInt32(payload.count))
        file.appendLE(UInt32(0))
        file.append(key.digest)
        assert(file.count == Self.headerBytes)
        file.append(contentsOf: payload)

        let size = file.count
        guard size <= byteCeiling else {
            return .failure(.exceedsCeiling(needed: size, ceiling: byteCeiling))
        }

        let destination = url(for: key)
        let existing = Self.size(of: destination)
        evict(toFree: size - existing, playhead: playhead, frames: frames, keeping: key)

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try file.write(to: destination, options: .atomic)
        } catch {
            return .failure(.couldNotWrite)
        }
        lock.lock()
        bytesOnDisk += size - existing
        lock.unlock()
        return .success(size)
    }

    // MARK: - Reading

    /// The frame this key names, or nil.
    ///
    /// **Every rejection is a miss and never a picture** — a wrong magic, a format version this
    /// build does not write, a digest naming some other key, a truncated file, a decode that comes
    /// up short. That is what makes §3.3's "a stale file can never be shown as fresh" mechanical:
    /// the caller asks for a key, and either gets that key's pixels or gets nothing and re-bakes.
    ///
    /// **`DecodedFrame` rather than `CGImage`, and there is no `CGImage` spelling beside it.** There
    /// was one until RENDER stage 4c — a `load(_:) -> CGImage?` that decoded into a `[UInt8]`, built a
    /// `CGContext` over it and called `makeImage()`, which is a second canvas-sized copy and a
    /// re-encode of bytes that were already exactly what Core Animation wants. `DecodedFrame.makeImage()`
    /// wraps the same `Data` in a `CGDataProvider` and copies nothing, and the ring it feeds
    /// (`DecodedFrameRing`) holds `DecodedFrame`s rather than images by design — so a store that
    /// answered in `CGImage` could not fill the ring at all without decoding twice. §2.15: the
    /// superseded path is deleted rather than kept beside the new one.
    func loadDecoded(_ key: FrameBakeKey) -> DecodedFrame? {
        guard let file = try? Data(contentsOf: url(for: key)),
              file.count >= Self.headerBytes,
              Array(file.prefix(4)) == Self.magic,
              file.readLE(at: 4) as UInt16 == Self.formatVersion else { return nil }

        let flags: UInt16 = file.readLE(at: 6)
        let width = Int(file.readLE(at: 8) as UInt32)
        let height = Int(file.readLE(at: 12) as UInt32)
        let bytesPerRow = Int(file.readLE(at: 16) as UInt32)
        let rawCount = Int(file.readLE(at: 20) as UInt32)
        let payloadCount = Int(file.readLE(at: 24) as UInt32)
        let digest = file.subdata(in: 32..<64)

        // The digest is the whole freshness guarantee, so it is checked before anything is decoded.
        guard digest == key.digest else { return nil }
        guard width > 0, height > 0,
              bytesPerRow == width * 4,
              rawCount == height * bytesPerRow,
              payloadCount > 0,
              file.count == Self.headerBytes + payloadCount else { return nil }

        let payload = file.subdata(in: Self.headerBytes..<(Self.headerBytes + payloadCount))
        let raw: Data
        if flags & Self.flagCompressed != 0 {
            guard let decoded = Self.decompress(payload, to: rawCount) else { return nil }
            raw = decoded
        } else {
            guard payloadCount == rawCount else { return nil }
            raw = payload
        }
        return DecodedFrame(width: width, height: height, bytesPerRow: bytesPerRow, pixels: raw)
    }

    // MARK: - Purging and eviction

    /// **§2.11's launch dump, for every document at once** — what `PaintApp.init` calls.
    ///
    /// Static rather than per-store because at launch no store exists yet: the bakes of documents
    /// the artist is not about to open are exactly the ones with nobody to purge them, and building
    /// one `FrameBakeStore` per directory found on disk would create the directory it is about to
    /// delete. One `removeItem` on the root does it.
    ///
    /// The *keep-beside-the-project* option §2.11 also names is stage 6 and is deliberately not
    /// here; this root is the Caches copy, which is the one the ruling says is dumped by default.
    static func purgeEverything() {
        try? FileManager.default.removeItem(at: bakesRootDirectory)
    }

    /// The same dump for one store's own corner, for a document that is closing or being re-rooted.
    func purgeAll() {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
        lock.lock()
        bytesOnDisk = Self.measure(root)
        lock.unlock()
    }

    /// Drops files, farthest from the playhead first, until at least `bytes` of headroom exists
    /// under the ceiling. Returns how many bytes it actually freed.
    ///
    /// `keeping` is the frame currently being written — it is the one file that must survive its own
    /// write, and §2.10 makes it the highest priority in the queue as well.
    @discardableResult
    func evict(toFree bytes: Int,
               playhead: Int,
               frames: [String: Set<Int>],
               keeping: FrameBakeKey? = nil) -> Int {
        lock.lock()
        let current = bytesOnDisk
        lock.unlock()
        let overshoot = current + bytes - byteCeiling
        guard overshoot > 0 else { return 0 }

        let fm = FileManager.default
        let keptName = keeping?.fileName
        var candidates: [(url: URL, size: Int, distance: Int)] = []
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.deletingPathExtension().lastPathComponent
            guard name != keptName else { continue }
            let size = Self.size(of: url)
            guard size > 0 else { continue }
            // A file no live frame names is unreachable from this document and goes first.
            let distance = frames[name]?.map { abs($0 - playhead) }.min() ?? Int.max
            candidates.append((url, size, distance))
        }
        // Farthest first; ties broken by name so the order is deterministic rather than the
        // directory's.
        candidates.sort {
            $0.distance != $1.distance ? $0.distance > $1.distance
                                       : $0.url.lastPathComponent > $1.url.lastPathComponent
        }

        var freed = 0
        for candidate in candidates where freed < overshoot {
            guard (try? fm.removeItem(at: candidate.url)) != nil else { continue }
            freed += candidate.size
        }
        lock.lock()
        bytesOnDisk -= freed
        lock.unlock()
        return freed
    }

    // MARK: - Pixels

    /// **BGRA premultiplied-first, tightly packed** — `bytesPerRow == width * 4` whatever
    /// CoreGraphics would have chosen for its own alignment.
    ///
    /// That layout is what Core Animation wants, so the convert that costs a hitch per stroke-lift
    /// today (BUGS.md, `CanvasView.swift:1531-1535`) happens once, off-main, at bake time. Tight
    /// packing is §2.6: a platform whose natural row alignment is 64 bytes would otherwise compress
    /// its padding and report a different ratio for the same picture.
    static func bgraBytes(_ image: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (bytes, width, height)
    }

    // MARK: - LZ4

    /// Nil when the encoder declines — which for `_RAW` is what incompressible input looks like, and
    /// is the caller's cue to store the pixels as they are.
    static func compress(_ raw: [UInt8]) -> [UInt8]? {
        guard !raw.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: raw.count)
        let written = raw.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, raw.count,
                                          src.baseAddress!, raw.count, nil, algorithm)
            }
        }
        guard written > 0, written < raw.count else { return nil }
        return Array(out[0..<written])
    }

    /// Nil on anything short of `expected` bytes, which is what a truncated or corrupt payload
    /// produces. The size comes from the header, which is what a raw LZ4 block needs and does not
    /// carry itself.
    ///
    /// **`Data` out, not `[UInt8]`.** `DecodedFrame` holds `Data` so that `makeImage()` can hand the
    /// same allocation straight to a `CGDataProvider`; returning an array here would put an
    /// `Array` → `Data` copy of the whole frame between the decoder and the ring, which at 2048² is
    /// 16.8 MB moved per frame at 24 fps for no reason at all.
    static func decompress(_ payload: Data, to expected: Int) -> Data? {
        guard expected > 0, !payload.isEmpty else { return nil }
        var out = Data(count: expected)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            guard let destination = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return payload.withUnsafeBytes { src -> Int in
                guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destination, expected, base, payload.count, nil, algorithm)
            }
        }
        return written == expected ? out : nil
    }

    // MARK: - Disk arithmetic

    private static func size(of url: URL) -> Int {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return values.fileSize ?? 0
    }

    private static func measure(_ root: URL) -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + size(of: $1) }
    }
}

// MARK: - Little-endian header fields

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Byte-wise rather than `load(fromByteOffset:)`, which traps on an unaligned address and would
    /// turn a corrupt file into a crash — the one thing `load(_:)` promises never to do.
    func readLE<T: FixedWidthInteger>(at offset: Int) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size {
            value |= T(self[startIndex + offset + i]) << (8 * i)
        }
        return value
    }
}
