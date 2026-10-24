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
/// Same-root stores share one weakly held directory owner. File I/O and inventory updates serialize;
/// metadata-only readiness uses its own short lock, independently of pixel reads and decompression.
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
    /// carries it too, because two knob positions can round to one buffer on a small canvas.
    static func defaultRoot(projectID: UUID, renderResolution: RenderResolution) -> URL {
        bakesRootDirectory
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(renderResolution.rawValue, isDirectory: true)
    }

    // MARK: - State

    let root: URL

    /// This facade's write ceiling (§3.5). Each accepted write evicts against this limit; another
    /// facade may request a larger cap, so shared totalBytes can exceed a smaller facade's cap.
    let byteCeiling: Int

    /// All facades for the same directory share one I/O and inventory owner, including a freshly
    /// loaded CanvasManager while an older baker still owes frozen work. Facades retain their
    /// requested per-write ceiling; totalBytes always reports this shared directory's usage.
    private let owner: Root

    fileprivate enum FileID: Hashable {
        case bake(FrameBakeKey)
        case other(String)
    }

    fileprivate final class Root {
        struct Entry { let size: Int; let revision: UInt64 }
        let url: URL
        let io = NSLock()
        private let metadata = NSLock()
        private var files: [FileID: Entry]
        private var bytes: Int
        private var revision: UInt64 = 0
        private var reads = 0

        init(_ url: URL) {
            self.url = url
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let sizes = FrameBakeStore.inventory(url)
            files = sizes.mapValues { Entry(size: $0, revision: 0) }
            bytes = sizes.values.reduce(0, +)
        }

        var totalBytes: Int {
            metadata.lock(); defer { metadata.unlock() }
            return bytes
        }

        var readCount: Int {
            metadata.lock(); defer { metadata.unlock() }
            return reads
        }

        func noteRead() {
            metadata.lock(); defer { metadata.unlock() }
            reads += 1
        }

        func entry(_ name: FileID) -> Entry? {
            metadata.lock(); defer { metadata.unlock() }
            return files[name]
        }

        /// Called only while I/O ownership is held. Metadata readers never wait on file access or
        /// decompression; they see each complete inventory update under this short separate lock.
        func replaceInventory(_ sizes: [FileID: Int]) {
            metadata.lock(); defer { metadata.unlock() }
            revision &+= 1
            files = sizes.mapValues { Entry(size: $0, revision: revision) }
            bytes = sizes.values.reduce(0, +)
        }

        func record(_ name: FileID, size: Int?) {
            metadata.lock(); defer { metadata.unlock() }
            bytes -= files[name]?.size ?? 0
            revision &+= 1
            if let size, size > 0 {
                files[name] = Entry(size: size, revision: revision)
                bytes += size
            } else {
                files[name] = nil
            }
        }
    }

    private final class WeakRoot {
        weak var value: Root?
        init(_ value: Root) { self.value = value }
    }
    private static let rootsLock = NSLock()
    private static var roots: [URL: WeakRoot] = [:]

    private static func rootOwner(_ url: URL) -> Root {
        rootsLock.lock(); defer { rootsLock.unlock() }
        roots = roots.filter { $0.value.value != nil }
        if let existing = roots[url]?.value { return existing }
        let owner = Root(url)
        roots[url] = WeakRoot(owner)
        return owner
    }

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
        self.root = URL(fileURLWithPath: root.standardizedFileURL.path, isDirectory: true)
        self.byteCeiling = byteCeiling
        owner = Self.rootOwner(self.root)
    }

    /// 512 MiB. A number rather than a fraction of the device, because §2.6 forbids a budget
    /// hard-coded to an iPad and a *disk* ceiling has no portable device signal to read. The caller
    /// passes its own where it knows better.
    static let defaultByteCeiling = 512 * 1024 * 1024

    /// What the store is holding, in bytes, right now.
    var totalBytes: Int {
        owner.totalBytes
    }

    func url(for key: FrameBakeKey) -> URL {
        root.appendingPathComponent(key.fileName + ".pbk", isDirectory: false)
    }

    func contains(_ key: FrameBakeKey) -> Bool {
        owner.entry(.bake(key)) != nil
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

        owner.io.lock()
        defer { owner.io.unlock() }
        let destination = url(for: key)
        let existing = owner.entry(.bake(key))?.size ?? 0
        evictLocked(toFree: size - existing, playhead: playhead, frames: frames, keeping: key)

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try file.write(to: destination, options: .atomic)
        } catch {
            return .failure(.couldNotWrite)
        }
        owner.record(.bake(key), size: size)
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
    /// A missing/invalid disposable file can be rebuilt; a refused allocation cannot be repaired
    /// by recompositing the same pixels. Ring admission is a separate decision after this read.
    enum ReadResult {
        case decoded(DecodedFrame)
        case unavailable
        case allocationRefused

        var frame: DecodedFrame? {
            if case .decoded(let frame) = self { return frame }
            return nil
        }

        var isUnavailable: Bool {
            if case .unavailable = self { return true }
            return false
        }
    }

    func loadDecoded(_ key: FrameBakeKey) -> DecodedFrame? { read(key).frame }

    /// Owned bytes from one file read. Keeping the revision with the bytes prevents a decode of
    /// old invalid data from deleting a good replacement written while the decode was running.
    struct ReadSnapshot {
        fileprivate let owner: Root
        fileprivate let key: FrameBakeKey
        fileprivate let revision: UInt64?
        fileprivate let file: Data?
    }

    var fileReadCount: Int { owner.readCount }

    func readSnapshot(_ key: FrameBakeKey) -> ReadSnapshot {
        owner.io.lock(); defer { owner.io.unlock() }
        owner.noteRead()
        return ReadSnapshot(owner: owner, key: key,
                            revision: owner.entry(.bake(key))?.revision,
                            file: try? Data(contentsOf: url(for: key)))
    }

    func read(_ key: FrameBakeKey) -> ReadResult {
        PlaybackTrace.span(.storeDecode) { Self.decode(readSnapshot(key)) }
    }

    static func decode(_ snapshot: ReadSnapshot) -> ReadResult {
        do {
            guard let file = snapshot.file else { throw ReadFailure.invalid }
            let decoded = try decodeFile(file, key: snapshot.key)
            settle(snapshot, decodedSize: file.count)
            return .decoded(decoded)
        } catch ReadFailure.allocationRefused {
            return .allocationRefused
        } catch {
            settle(snapshot, decodedSize: nil)
            return .unavailable
        }
    }

    private static func settle(_ snapshot: ReadSnapshot, decodedSize: Int?) {
        let owner = snapshot.owner
        let url = owner.url.appendingPathComponent(snapshot.key.fileName + ".pbk")
        owner.io.lock(); defer { owner.io.unlock() }
        guard owner.entry(.bake(snapshot.key))?.revision == snapshot.revision else { return }
        if let decodedSize {
            owner.record(.bake(snapshot.key), size: decodedSize)
        } else {
            try? FileManager.default.removeItem(at: url)
            let remaining = size(of: url)
            owner.record(.bake(snapshot.key), size: remaining > 0 ? remaining : nil)
        }
    }

    private enum ReadFailure: Error { case invalid, allocationRefused }

    private static func decodeFile(_ file: Data, key: FrameBakeKey) throws -> DecodedFrame {
        guard file.count >= Self.headerBytes,
              Array(file.prefix(4)) == Self.magic,
              file.readLE(at: 4) as UInt16 == Self.formatVersion else { throw ReadFailure.invalid }

        let flags: UInt16 = file.readLE(at: 6)
        let width = Int(file.readLE(at: 8) as UInt32)
        let height = Int(file.readLE(at: 12) as UInt32)
        let bytesPerRow = Int(file.readLE(at: 16) as UInt32)
        let rawCount = Int(file.readLE(at: 20) as UInt32)
        let payloadCount = Int(file.readLE(at: 24) as UInt32)
        let digest = file.subdata(in: 32..<64)

        guard digest == key.digest,
              let expectedBytes = pixelByteCount(width: width, height: height, bytesPerRow: bytesPerRow),
              rawCount == expectedBytes,
              payloadCount > 0,
              file.count == Self.headerBytes + payloadCount else { throw ReadFailure.invalid }

        let payload = file.subdata(in: Self.headerBytes..<(Self.headerBytes + payloadCount))
        let raw: Data
        if flags & Self.flagCompressed != 0 {
            raw = try Self.decompressChecked(payload, to: rawCount)
        } else {
            guard payloadCount == rawCount else { throw ReadFailure.invalid }
            raw = payload
        }
        return DecodedFrame(width: width, height: height, bytesPerRow: bytesPerRow, pixels: raw)
    }

    /// Header arithmetic is checked before allocating or attempting any payload decompression.
    static func pixelByteCount(width: Int, height: Int, bytesPerRow: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let row = width.multipliedReportingOverflow(by: 4)
        let total = height.multipliedReportingOverflow(by: bytesPerRow)
        guard !row.overflow, !total.overflow, row.partialValue == bytesPerRow else { return nil }
        return total.partialValue
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
        owner.io.lock()
        defer { owner.io.unlock() }
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
        owner.replaceInventory(Self.inventory(root))
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
        owner.io.lock()
        defer { owner.io.unlock() }
        return evictLocked(toFree: bytes, playhead: playhead, frames: frames, keeping: keeping)
    }

    @discardableResult
    private func evictLocked(toFree bytes: Int, playhead: Int,
                             frames: [String: Set<Int>], keeping: FrameBakeKey?) -> Int {
        func needsSpace() -> Bool {
            let projected = owner.totalBytes.addingReportingOverflow(bytes)
            return projected.overflow || projected.partialValue > byteCeiling
        }
        guard needsSpace() else { return 0 }

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
        for candidate in candidates {
            // Releasing a truncated file drops its formerly charged size, which can exceed the
            // physical bytes just removed. Headroom follows inventory; the return value follows I/O.
            guard needsSpace() else { break }
            guard (try? fm.removeItem(at: candidate.url)) != nil else { continue }
            freed += candidate.size
            owner.record(Self.fileID(candidate.url), size: nil)
        }
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
    ///
    /// **`Data(count:)` traps when the host refuses the bytes** — Foundation's initialiser is a
    /// `fatalError` on a nil `malloc`, and that is the trap the owner's iPad logged on the bake queue
    /// (`Data.init(count:)` under `loadDecoded`, 2026-09-08) while a canvas-sized frame was being
    /// decoded with no memory left. So the frame's bytes come from `malloc` directly and a refusal
    /// is a nil answer: the caller treats it as a miss, and `MemoryPressure` is told
    /// (`.allocationRefused`) so the caches trim and the artist hears why.
    static func decompress(_ payload: Data, to expected: Int) -> Data? {
        try? decompressChecked(payload, to: expected)
    }

    private static func decompressChecked(_ payload: Data, to expected: Int) throws -> Data {
        guard expected > 0, !payload.isEmpty else { throw ReadFailure.invalid }
        guard let bytes = malloc(expected) else {
            MemoryPressure.signal(.allocationRefused)
            throw ReadFailure.allocationRefused
        }
        var out = Data(bytesNoCopy: bytes, count: expected, deallocator: .free)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            guard let destination = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return payload.withUnsafeBytes { src -> Int in
                guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destination, expected, base, payload.count, nil, algorithm)
            }
        }
        guard written == expected else { throw ReadFailure.invalid }
        return out
    }

    // MARK: - Disk arithmetic

    private static func size(of url: URL) -> Int {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return values.fileSize ?? 0
    }

    /// Parse canonical bake filenames once when enumerating the directory. Hot readiness looks
    /// up the already-owned digest directly; it never constructs URLs or formats hex strings.
    private static func fileID(_ url: URL) -> FileID {
        let name = url.lastPathComponent
        let hex = Array(name.utf8)
        guard hex.count == 68, name.hasSuffix(".pbk") else { return .other(name) }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 97...102: return c - 87
            default: return nil
            }
        }
        var bytes = Data(capacity: 32)
        for index in stride(from: 0, to: 64, by: 2) {
            guard let high = nibble(hex[index]), let low = nibble(hex[index + 1]) else { return .other(name) }
            bytes.append((high << 4) | low)
        }
        return .bake(FrameBakeKey(rawDigest: bytes))
    }

    private static func inventory(_ root: URL) -> [FileID: Int] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return Dictionary(uniqueKeysWithValues: urls.map { (fileID($0), size(of: $0)) })
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
