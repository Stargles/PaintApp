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
nonisolated final class FrameBakeStore {

    // MARK: - Format (version 2: tiles and two levels)

    /// **Bumped whenever the bytes on disk change meaning.** It is in the header *and* in the bake
    /// key, which is belt and braces on purpose: the key means an old file is never even looked for,
    /// and the header means one that is looked for anyway is rejected rather than decoded as
    /// something it is not.
    ///
    /// **Version 2 replaced version 1 outright and nothing reads version 1.** A bake file is a cache
    /// (RENDER.md §2.11): a file this build cannot read is a miss and the frame is baked again, so
    /// there is no repair pass and no second decoder. The launch dump (`purgeEverything`) removes the
    /// files an earlier build left.
    static let formatVersion: UInt16 = 2

    /// `PBK2`.
    static let magic: [UInt8] = [0x50, 0x42, 0x4B, 0x32]

    /// The side of a tile, in pixels (SCHEDULER_DESIGN.md §3: "tiled LZ4, 512×512 tiles"). A tile is
    /// compressed alone, so a reader holds one tile's scratch and a later window read needs only the
    /// tiles it shows.
    static let tileSide = 512

    /// **64 bytes, then the tile directory, then the payload.** Little-endian throughout:
    ///
    /// | offset | size | field |
    /// |---|---|---|
    /// | 0 | 4 | magic `PBK2` |
    /// | 4 | 2 | format version |
    /// | 6 | 2 | reserved, zero |
    /// | 8 | 4 | full level width |
    /// | 12 | 4 | full level height |
    /// | 16 | 4 | half level width (`ceil(width / 2)`) |
    /// | 20 | 4 | half level height |
    /// | 24 | 4 | tile side |
    /// | 28 | 4 | reserved, zero |
    /// | 32 | 32 | key digest |
    ///
    /// The directory is one `UInt32` per tile, the full level's tiles row by row and then the half
    /// level's: the low 31 bits are the stored length, bit 31 is set when the tile is stored raw
    /// because LZ4 did not shrink it. The payload is the tiles in the same order, so a level's
    /// bytes are one contiguous range — a step at fit zoom reads the half level and never the full.
    /// Tiles are BGRA premultiplied-first, tightly packed.
    static let headerBytes = 64

    /// Bit 31 of a directory entry.
    static let rawTileBit: UInt32 = 0x8000_0000

    /// **`COMPRESSION_LZ4_RAW`, and this is a correction to §3.5's `COMPRESSION_LZ4`.** Apple's
    /// `COMPRESSION_LZ4` wraps the stream in its own `bv41` block framing, which no other LZ4
    /// decoder reads — and §3.5's stated reason for choosing LZ4 at all is that "the format is
    /// portable to any platform with an LZ4 decoder, which is all of them". `_RAW` is the standard
    /// raw block, whose only extra requirement is knowing the uncompressed size before decoding,
    /// and a tile's size follows from its place in the level.

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

    /// This facade's own write ceiling, or nil for the disk limit (`BakeDiskLimit`). Each accepted
    /// write evicts against the ceiling; another facade may request a larger one, so shared
    /// `totalBytes` can exceed a smaller facade's.
    private let explicitCeiling: Int?

    /// All facades for the same directory share one I/O and inventory owner, including a freshly
    /// loaded CanvasManager while an older baker still owes frozen work. Facades retain their
    /// requested per-write ceiling; totalBytes always reports this shared directory's usage.
    private let owner: Root

    fileprivate enum FileID: Hashable {
        case bake(FrameBakeKey)
        case other(String)
    }

    fileprivate nonisolated final class Root {
        struct Entry { let size: Int; let revision: UInt64 }
        let url: URL
        let io = NSLock()
        private let metadata = NSLock()
        private var files: [FileID: Entry]
        private var bytes: Int
        private var revision: UInt64 = 0
        private var reads = 0
        /// Free disk plus what this root holds, as last read; `Int.max` until the first read answers.
        private var capacityBytes = Int.max

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

        var capacity: Int {
            metadata.lock(); defer { metadata.unlock() }
            return capacityBytes
        }

        /// Reads the volume again (a store opening, a write failing). A volume that cannot say
        /// leaves the figure as it was.
        func refreshCapacity() {
            guard let read = BakeDiskLimit.capacity(at: url, held: totalBytes) else { return }
            metadata.lock(); defer { metadata.unlock() }
            capacityBytes = read
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

    private nonisolated final class WeakRoot {
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
        /// The one budget (`MemoryBudget`) had no room to encode it now — try again later.
        case notAdmitted
        /// A key whose digest is not 32 bytes — the header has a fixed field for it, so there is
        /// nowhere to put a longer one and no way to compare a shorter one on the way back.
        case malformedKey
    }

    /// - Parameter byteCeiling: nil (the app) takes the disk limit — `min(4 GiB, 10% of free disk)`,
    ///   read from the machine now and again when a write fails; a test passes its own.
    init(root: URL, byteCeiling: Int? = nil) {
        self.root = URL(fileURLWithPath: root.standardizedFileURL.path, isDirectory: true)
        explicitCeiling = byteCeiling
        owner = Self.rootOwner(self.root)
        if byteCeiling == nil { owner.refreshCapacity() }
    }

    /// What one write may take the store to: the explicit ceiling, else the disk limit as last read.
    var ceiling: Int { explicitCeiling ?? BakeDiskLimit.bytes(capacity: owner.capacity) }

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
        // The BGRA copy, admitted by the one budget for as long as it is held.
        guard let converting = MemoryBudget.shared.admit(image.width * image.height * 4) else {
            return .failure(.notAdmitted)
        }
        defer { converting.release() }
        guard let pixels = Self.bgraBytes(image) else { return .failure(.unreadableImage) }
        return store(pixels: pixels, for: key, playhead: playhead, frames: frames)
    }

    /// `store(_:)` from pixels already converted — what the bake calls, having let the composite go
    /// first, so its peak is two frames (the BGRA copy and LZ4's output) rather than three.
    func store(pixels: (bytes: [UInt8], width: Int, height: Int),
               for key: FrameBakeKey,
               playhead: Int = 0,
               frames: [String: Set<Int>] = [:]) -> Result<Int, WriteFailure> {
        guard key.digest.count == 32 else { return .failure(.malformedKey) }
        // The file's bytes are at most the frame's own (a tile LZ4 does not shrink goes down raw),
        // admitted for the encode; the half level is filtered a tile at a time and never held whole.
        guard let encoding = MemoryBudget.shared.admit(pixels.bytes.count) else { return .failure(.notAdmitted) }
        defer { encoding.release() }
        guard let file = BakeFile.encode(bgra: pixels.bytes, width: pixels.width, height: pixels.height,
                                         digest: key.digest) else { return .failure(.unreadableImage) }

        let size = file.count
        guard size <= ceiling else {
            return .failure(.exceedsCeiling(needed: size, ceiling: ceiling))
        }

        owner.io.lock()
        defer { owner.io.unlock() }
        let destination = url(for: key)
        let existing = owner.entry(.bake(key))?.size ?? 0
        let delta = size - existing
        evictLocked(toFree: delta, playhead: playhead, frames: frames, keeping: key)
        guard !needsSpace(adding: delta) else {
            if explicitCeiling == nil { owner.refreshCapacity() }
            return .failure(.couldNotWrite)
        }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try file.write(to: destination, options: .atomic)
        } catch {
            if explicitCeiling == nil { owner.refreshCapacity() }
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

    func loadDecoded(_ key: FrameBakeKey, level: BakeLevel = .full) -> DecodedFrame? { read(key, level: level).frame }

    /// What one file read found: the level's stored bytes and the directory that says how to decode
    /// them, with the revision of the inventory entry they came from. Keeping the revision with the
    /// bytes prevents a decode of old invalid data from deleting a good replacement written while the
    /// decode was running.
    struct ReadSnapshot {
        fileprivate let owner: Root
        fileprivate let key: FrameBakeKey
        fileprivate let level: BakeLevel
        fileprivate let revision: UInt64?
        fileprivate let found: (directory: BakeFile.Directory, payload: Data, fileSize: Int)?

        /// Bytes the read brought in from disk — the level's tiles, not the file.
        var payloadBytes: Int { found?.payload.count ?? 0 }
    }

    var fileReadCount: Int { owner.readCount }

    /// Reads `level` of `key`'s file: the header and directory, then that level's contiguous range and
    /// nothing else — a step at fit zoom never touches the full level's bytes.
    func readSnapshot(_ key: FrameBakeKey, level: BakeLevel = .full) -> ReadSnapshot {
        owner.io.lock(); defer { owner.io.unlock() }
        owner.noteRead()
        return ReadSnapshot(owner: owner, key: key, level: level,
                            revision: owner.entry(.bake(key))?.revision,
                            found: Self.readLevel(at: url(for: key), key: key, level: level))
    }

    func read(_ key: FrameBakeKey, level: BakeLevel = .full) -> ReadResult {
        FrameStepCensus.decodeStarted(onMain: Thread.isMainThread)
        return PlaybackTrace.span(.storeDecode) { Self.decode(readSnapshot(key, level: level)) }
    }

    private static func readLevel(at url: URL, key: FrameBakeKey,
                                  level: BakeLevel) -> (directory: BakeFile.Directory, payload: Data, fileSize: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headerBytes),
              let header = BakeFile.Header.parse(head), header.digest == key.digest,
              let directoryData = try? handle.read(upToCount: header.directoryBytes),
              let directory = BakeFile.Directory(header: header, data: directoryData), directory.isConsistent,
              let end = try? handle.seekToEnd(), Int(end) == directory.fileLength else { return nil }
        let range = directory.payload(of: level)
        guard (try? handle.seek(toOffset: UInt64(range.lowerBound))) != nil,
              let payload = try? handle.read(upToCount: range.count), payload.count == range.count else { return nil }
        return (directory, payload, Int(end))
    }

    static func decode(_ snapshot: ReadSnapshot) -> ReadResult {
        do {
            guard let found = snapshot.found else { throw ReadFailure.invalid }
            let decoded = try decodeLevel(found.directory, level: snapshot.level, payload: found.payload)
            settle(snapshot, decodedSize: found.fileSize)
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

    /// **The frame's bytes come from `malloc` directly and a refusal is a nil answer.** `Data(count:)`
    /// traps when the host refuses the bytes — Foundation's initialiser is a `fatalError` on a nil
    /// `malloc`, and that is the trap the owner's iPad logged on the bake queue (`Data.init(count:)`
    /// under `loadDecoded`, 2026-09-08) while a canvas-sized frame was being decoded with no memory
    /// left. The caller treats a refusal as a miss, and `MemoryPressure` is told (`.allocationRefused`)
    /// so the caches trim and the artist hears why. Admitted by the one budget, and charged for as
    /// long as the pixels live — the ring, the screen or a playback tick may hold them after the ring
    /// lets go. `DecodedFrame` rather than `CGImage`: `makeImage()` wraps the same `Data` in a
    /// `CGDataProvider` and copies nothing.
    private static func decodeLevel(_ directory: BakeFile.Directory, level: BakeLevel, payload: Data) throws -> DecodedFrame {
        let size = directory.header.size(of: level)
        guard let count = pixelByteCount(width: size.width, height: size.height, bytesPerRow: size.width * 4) else {
            throw ReadFailure.invalid
        }
        guard let grant = MemoryBudget.shared.admit(count) else {
            MemoryPressure.signal(.allocationRefused)
            throw ReadFailure.allocationRefused
        }
        guard let bytes = malloc(count) else {
            grant.release()
            MemoryPressure.signal(.allocationRefused)
            throw ReadFailure.allocationRefused
        }
        var out = Data(bytesNoCopy: bytes, count: count, deallocator: .custom { pointer, _ in
            free(pointer)
            grant.release()
        })
        let decoded = out.withUnsafeMutableBytes { BakeFile.decode(level: level, directory: directory, payload: payload, into: $0) }
        guard decoded else { throw ReadFailure.invalid }
        return DecodedFrame(width: size.width, height: size.height, bytesPerRow: size.width * 4, pixels: out)
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
        guard needsSpace(adding: bytes) else { return 0 }

        let fm = FileManager.default
        let keptName = keeping?.fileName
        var candidates: [(url: URL, size: Int, distance: Int)] = []
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.deletingPathExtension().lastPathComponent
            guard name != keptName else { continue }
            let size = Self.size(of: url)
            // Zero-byte files can still carry their old inventory charge after external truncation.
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
            guard needsSpace(adding: bytes) else { break }
            guard (try? fm.removeItem(at: candidate.url)) != nil else { continue }
            freed += candidate.size
            owner.record(Self.fileID(candidate.url), size: nil)
        }
        return freed
    }

    /// Used under the root's I/O ownership, both while evicting and before admitting the write.
    /// Physical bytes removed are reporting only; authoritative inventory decides headroom.
    private func needsSpace(adding bytes: Int) -> Bool {
        let projected = owner.totalBytes.addingReportingOverflow(bytes)
        return projected.overflow || projected.partialValue > ceiling
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
