import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

// MARK: - VIDEO.md §5, the reader
//
// **The export path picked the conventions and this file mirrors them rather than inventing any.**
// `VideoFrameWriter` (`Engine/FrameExport.swift`) writes `kCVPixelFormatType_32BGRA` and times its
// frames as `CMTime(value: index, timescale: fps)` — an exact rational, deliberately not seconds, to
// avoid drift on a long clip — and tags no colour space, inheriting `PixelOps.deviceRGBColorSpace`.
// So this reads 32BGRA, addresses the source by exact rational (`SourceTime`), and hands back a
// `DecodedFrame`, which is the same currency the frame store already speaks. Nothing here mints a
// third pixel layout.
//
// ## The one design constraint, VIDEO.md §5
//
// *"`AVAssetReader` is a forward pipe; scrubbing backwards means tearing it down and re-seeking,
// which is the one place this feature can be slow in a way the store cannot fix. Design the reader
// around a playhead the way `BakeQueue` already is, rather than around random access."*
//
// So `VideoFrameReader` is a playhead: two samples wide, advancing forward for free and paying a
// pipe rebuild only when it is asked for an instant behind the one it holds. `seekCount` counts
// those rebuilds and is a test seam, because "a forward scrub costs no seeks" is a claim about the
// design that wall-clock time cannot make.

/// What an asset says about itself, read once when its reader opens.
struct VideoAssetInfo: Equatable {
    /// The **decoded buffer's** size — what comes out of the pipe, before `preferredTransform`.
    /// `VectorVideoElement.naturalSize` is what a placement maps, so an import that wants a
    /// phone-shot portrait clip the right way up puts the rotation in the placement rather than
    /// resampling every frame; see `rotation`.
    let decodedSize: CGSize

    /// The size a player would show, i.e. `decodedSize` through `preferredTransform`, with the sign
    /// taken off. Equal to `decodedSize` except on quarter-turn footage, where the axes swap.
    let displaySize: CGSize

    /// The track's own nominal rate. §2.3's frame-for-frame speed is this over the document's rate.
    /// Zero when the track does not claim one, which is a legal thing for a file to do.
    let nominalFrameRate: Double

    /// The whole clip's length on its own clock — what an import writes into `sourceEnd` before
    /// §2.4 clips the block to the scene.
    let duration: SourceTime

    /// The track's stored orientation. A quarter turn here is why `decodedSize` and `displaySize`
    /// can differ.
    let preferredTransform: CGAffineTransform

    /// The preferred transform's rotation, in radians, when it is a rotation (with or without a
    /// flip). This is the number an import folds into `LayerTransform.rotation` so that no pixel is
    /// resampled to stand a clip up.
    var rotation: CGFloat { atan2(preferredTransform.b, preferredTransform.a) }
}

extension SourceTime {
    /// The instant as CoreMedia spells it. Exact — the pair is the same pair, which is the whole
    /// reason `SourceTime` is a rational and not a `Double` (see its own doc comment).
    var cmTime: CMTime { CMTime(value: CMTimeValue(value), timescale: CMTimeScale(timescale)) }

    /// A CoreMedia instant as this app stores one. Nil for an invalid or indefinite time, which is
    /// what a track with no duration answers.
    init?(_ time: CMTime) {
        guard time.isValid, !time.isIndefinite, time.timescale > 0 else { return nil }
        self.init(value: time.value, timescale: time.timescale)
    }
}

// MARK: - Where an imported clip's bytes live before the first save

/// **The staging directory an import copies a picked clip into** — VIDEO.md stage 4.
///
/// A video's payload *is* a file (`VectorVideoElement`'s own doc), so an import cannot hold the
/// picked movie the way `insertImage` holds a `UIImage`: it has to put the bytes somewhere the
/// element can point at until a save copies them into the project package. The picker hands over a
/// file in a location the system deletes as soon as the transfer closure returns, so this is a copy
/// and not a reference.
///
/// **Application Support rather than Caches**, which is the whole of the choice: the system may
/// evict `Library/Caches` at any time, and until the artist saves, this copy is the *only* copy of
/// artwork they have imported. It is not user-visible, unlike `Documents`.
///
/// **Nothing sweeps it yet** — see VIDEO.md §9. A clip imported and then undone leaves its bytes
/// behind, and the safe sweep is not "delete what is old" but "delete what no open document and no
/// undo stack still names", which is a question this type cannot answer on its own.
enum VideoImportStore {

    /// Overridable so a test stages into its own directory rather than the real one, exactly as
    /// `FrameBakeStore.cachesDirectoryOverride` and `ProjectBackupManager.rootDirectoryOverride`
    /// already do.
    nonisolated(unsafe) static var directoryOverride: URL?

    static var directory: URL {
        if let directoryOverride { return directoryOverride }
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("VideoImports", isDirectory: true)
    }

    /// Puts `source` in under `name`, creating the directory if it is not there. Nil when that
    /// fails, which the import reports as a refusal rather than storing an element pointing at
    /// nothing.
    ///
    /// **`consumingSource` moves instead of copying, and a clip is why the distinction is worth a
    /// parameter.** Getting a picked movie this far already costs two copies — Photos exports it to
    /// a temporary file, and `Transferable`'s import closure must copy that before it is deleted —
    /// so a third on a half-gigabyte clip is a second of I/O and a gigabyte of transient disk for
    /// nothing. Only a caller that owns the source may pass true.
    static func stage(_ source: URL, as name: String, consumingSource: Bool = false) -> URL? {
        let fm = FileManager.default
        let root = directory
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(name)
        try? fm.removeItem(at: destination)
        do {
            if consumingSource {
                try fm.moveItem(at: source, to: destination)
            } else {
                try fm.copyItem(at: source, to: destination)
            }
        } catch {
            return nil
        }
        return destination
    }
}

// MARK: - One asset, one playhead

/// **A single video file, decoded around a playhead.**
///
/// Not thread-safe on its own: `VideoFrameSource` advances and inspects readers under its serial
/// decode lock. Its separate ownership lock may retire a reader, but never advances its playhead.
final class VideoFrameReader {

    let url: URL
    let info: VideoAssetInfo

    private let asset: AVURLAsset
    private let track: AVAssetTrack

    private var reader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?
    /// Where the live pipe was started. An instant before this cannot be answered from it, however
    /// much of it is still buffered, because everything earlier was never delivered.
    private var rangeStart: CMTime = .zero

    /// The newest sample pulled out of the pipe, and the newest one at or before the located
    /// instant. Two slots is exactly what "nearest" needs: the candidate before and the candidate
    /// after.
    private var ahead: (time: CMTime, sample: CMSampleBuffer)?
    private var behind: (time: CMTime, sample: CMSampleBuffer)?
    private var located: (time: CMTime, sample: CMSampleBuffer)?
    private var exhausted = false

    /// **How many times the forward pipe has been torn down and re-seeked** — VIDEO.md §5's cost, as
    /// a number a test can read. A forward scrub across a whole clip is one; a backward step is one
    /// more per step.
    private(set) var seekCount = 0

    /// How many samples have been pulled. A forward scrub over N source frames pulls N of them; the
    /// claim that the playhead does not re-decode what it already passed is this counter not moving.
    private(set) var sampleCount = 0

    /// Nil when the file is not there, holds no video track, or will not open.
    ///
    /// **The deprecated synchronous accessors are used on purpose.** Their replacements are `async`,
    /// and this whole path is synchronous by construction: `DerivedCelContent.render` is called from
    /// `PixelOps.parallelMap`'s workers and has nowhere to await. Blocking one of those threads on a
    /// semaphore around an async load would be the same wait with a deadlock hazard added.
    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        self.url = url
        self.asset = asset
        self.track = track
        let decoded = track.naturalSize
        let transform = track.preferredTransform
        let display = decoded.applying(transform)
        info = VideoAssetInfo(decodedSize: decoded,
                              displaySize: CGSize(width: abs(display.width), height: abs(display.height)),
                              nominalFrameRate: Double(track.nominalFrameRate),
                              duration: SourceTime(asset.duration) ?? .zero,
                              preferredTransform: transform)
    }

    deinit { reader?.cancelReading() }

    // MARK: Positioning

    /// **Moves the playhead to the source frame nearest `time` and says which one that is.**
    ///
    /// Nil when the clip has no frame at all. Otherwise the returned instant is a presentation
    /// timestamp the *file* carries, not the one that was asked for — which is what makes it usable
    /// as a cache key: two document frames that resolve to one source frame produce one timestamp
    /// and therefore one decode.
    ///
    /// **Nearest, not "the one showing".** §4.3 says nearest, and the difference is real when the
    /// document's rate and the source's do not divide: at 24 into 30 the two rules disagree on two
    /// frames in five, and "the one showing" biases every frame of a resampled clip backwards by up
    /// to a whole source frame. Nearest costs one extra sample held, which the pipe was going to
    /// deliver next anyway.
    @discardableResult
    func locate(_ time: CMTime, whileCurrent: () -> Bool = { true }) -> CMTime? {
        guard whileCurrent() else { return nil }
        if let found = position(time, whileCurrent: whileCurrent) { return found }
        guard whileCurrent() else { return nil }
        // **Nothing in the pipe at all**, which has exactly one cause: the pipe was opened past the
        // end of the clip, so `AVAssetReader` delivered no sample and there is neither a candidate
        // behind nor one ahead. Re-open at the head and walk to the tail, which holds the last
        // frame — what a block longer than its footage shows, and what a damaged `sourceEnd` past
        // the clip's own duration resolves to. It costs a walk of the clip, once.
        guard rangeStart > .zero else { located = nil; return nil }
        restart(at: .zero)
        return position(time, whileCurrent: whileCurrent)
    }

    private func position(_ time: CMTime, whileCurrent: () -> Bool) -> CMTime? {
        if reader == nil || time < rangeStart || (behind.map { time < $0.time } ?? false) {
            restart(at: time)
        }
        // Walk the pipe forward until the sample in hand is past the instant wanted. Everything
        // passed becomes `behind`, which is the newest candidate at or before `time`.
        while let next = ahead, next.time <= time {
            guard whileCurrent() else { return nil }
            behind = next
            ahead = pull()
        }
        // Both candidates in hand: whichever timestamp is closer. One of them missing is an end —
        // the head of the clip has nothing behind it and the tail has nothing ahead.
        let chosen: (time: CMTime, sample: CMSampleBuffer)?
        switch (behind, ahead) {
        case (nil, nil):
            chosen = nil
        case (let back?, nil):
            chosen = back
        case (nil, let front?):
            chosen = front
        case (let back?, let front?):
            // **A tie takes the later frame**, which is not arbitrary: `VideoFrameMap`'s own
            // `sourceFrameIndex` rounds through `Double.rounded()`, i.e. half away from zero, i.e.
            // up. Ties are reachable rather than exotic — 30 fps footage in a 24 fps document lands
            // on one every fifth frame — and the two halves of §4.3 disagreeing on them would mean a
            // test that names a source frame by arithmetic and a canvas that shows a different one.
            chosen = CMTimeCompare(CMTimeSubtract(time, back.time),
                                   CMTimeSubtract(front.time, time)) < 0 ? back : front
        }
        located = chosen
        return chosen?.time
    }

    /// The pixels of whatever `locate` last chose, converted. Nil before any successful `locate`.
    func currentFrame() -> DecodedFrame? {
        guard let located else { return nil }
        return Self.decode(located.sample)
    }

    /// `located` aliases either candidate; it does not own a third distinct sample. This counts
    /// app-held buffers only, not AVFoundation's internal reader/decoder pools.
    var retainedSampleCount: Int { (ahead == nil ? 0 : 1) + (behind == nil ? 0 : 1) }
    var retainedSampleBytes: Int {
        [ahead?.sample, behind?.sample].compactMap { $0 }.reduce(0) { bytes, sample in
            bytes + (CMSampleBufferGetImageBuffer(sample).map { CVPixelBufferGetDataSize($0) } ?? 0)
        }
    }

    // MARK: The pipe

    /// Tears the forward pipe down and opens a new one at `time`, **backing off by one frame** so
    /// that the instant asked for still has a candidate behind it — without which `locate` would
    /// answer the frame *after* a backward seek every time.
    private func restart(at time: CMTime) {
        reader?.cancelReading()
        reader = nil
        ahead = nil
        behind = nil
        located = nil
        exhausted = false
        seekCount += 1

        let rate = info.nominalFrameRate > 0 ? info.nominalFrameRate : 30
        let backoff = CMTime(seconds: 1 / rate, preferredTimescale: 600)
        let start = CMTimeMaximum(CMTimeSubtract(time, backoff), .zero)
        rangeStart = start

        guard let reader = try? AVAssetReader(asset: asset) else { exhausted = true; return }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        // We copy every buffer we keep, so the framework does not have to.
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { exhausted = true; return }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: start, duration: .positiveInfinity)
        guard reader.startReading() else { exhausted = true; return }
        self.reader = reader
        self.trackOutput = output
        ahead = pull()
    }

    /// The next sample with an image in it, or nil at the end of the pipe.
    private func pull() -> (time: CMTime, sample: CMSampleBuffer)? {
        guard !exhausted, let output = trackOutput else { return nil }
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetImageBuffer(sample) != nil else { continue }
            sampleCount += 1
            return (CMSampleBufferGetPresentationTimeStamp(sample), sample)
        }
        exhausted = true
        return nil
    }

    // MARK: Pixels

    /// One decoded sample as a `DecodedFrame`: tightly packed BGRA, alpha forced opaque.
    ///
    /// **The stride is dropped and the rows are packed**, unlike `DecodedFrame`'s own contract which
    /// allows a padded one, because a `CVPixelBuffer`'s padding belongs to the buffer pool and the
    /// buffer is released the moment the pipe moves on. Copying is not optional here — the frame
    /// outlives the sample.
    ///
    /// **The alpha byte is forced to 255 for `FrameExport.opaqueBGRA`'s stated reason, read the
    /// other way round.** H.264 carries no alpha, so the decoder's fourth byte is undefined rather
    /// than meaningful; `DecodedFrame` says its pixels are premultiplied, and premultiplied against
    /// an undefined alpha is a picture that darkens by whatever the decoder happened to leave there.
    /// Forcing it makes "opaque" true in the bytes instead of true by convention.
    static func decode(_ sample: CMSampleBuffer) -> DecodedFrame? {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let sourceStride = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, sourceStride >= width * 4,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = width * 4
        var pixels = Data(count: rowBytes * height)
        pixels.withUnsafeMutableBytes { destination in
            guard let dst = destination.bindMemory(to: UInt8.self).baseAddress else { return }
            let src = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let row = dst + y * rowBytes
                memcpy(row, src + y * sourceStride, rowBytes)
                for x in 0..<width { row[x * 4 + 3] = 255 }
            }
        }
        return DecodedFrame(width: width, height: height, pixels: pixels)
    }
}

// MARK: - Every asset the document is showing

/// **The playheads, and the decoded frames just around them** — VIDEO.md §5's two tiers, reusing the
/// ones RENDER.md already built rather than minting a third.
///
/// `DecodedFrameRing` is the in-memory tier verbatim: a byte budget rather than a count, LRU by last
/// access, and a frame larger than the whole budget refused rather than admitted over the ceiling.
/// Its own doc argues that recency of access *is* proximity to the playhead, which is as true of a
/// video scrub as it is of a bake.
///
/// **The disk tier is `FrameBakeStore` and is reached without this type knowing about it.** A
/// composited frame containing a video is stored there like any other, keyed by a `FrameBakeKey`
/// that now carries `VideoCelIdentity.cuts`. There is deliberately no second on-disk store of
/// decoded source frames: the source file *is* that store, and re-decoding it is what a seek costs.
///
/// Decode stays serial. A separate short ownership lock lets close/pressure retire residency
/// without waiting for an AVFoundation seek; an old read can finish but cannot warm its replacement.
final class VideoFrameSource {
    static let shared = VideoFrameSource()
    /// Tight copied pixels only. Reader samples and AVFoundation's internal pools are separate.
    static let defaultByteBudget = 64 * 1024 * 1024
    /// More simultaneous assets pay a seek per evicted pipe rather than retaining every decoder.
    static let defaultReaderLimit = 4

    /// A document's access, activated by its first read. Idle gallery managers keep no residency
    /// alive. Frozen render closures retain this client, not the mutable document; close is final.
    final class Client {
        private let source: VideoFrameSource
        fileprivate let id: UUID
        fileprivate init(source: VideoFrameSource, id: UUID) { self.source = source; self.id = id }
        deinit { close() }
        var isClosed: Bool { source.isClosed(id) }
        func close() { source.close(id) }
        func info(for url: URL) -> VideoAssetInfo? { source.info(client: id, for: url) }
        func read(assetURL url: URL, at time: SourceTime) -> ReadResult {
            source.read(client: id, assetURL: url, at: time)
        }
        func frame(assetURL url: URL, at time: SourceTime) -> DecodedFrame? { read(assetURL: url, at: time).frame }

        /// The real decode/landing seam: only finish can admit decoded pixels to current residency.
        func decode(assetURL url: URL, at time: SourceTime) -> Read {
            source.decode(client: id, assetURL: url, at: time)
        }
        func finish(_ read: Read) -> ReadResult { source.finish(read, client: id) }
    }

    enum ReadResult {
        case decoded(DecodedFrame)
        case missing
        /// Close/pressure retired the operation. A renderer must decline, never cache a placeholder.
        case unavailable
        var frame: DecodedFrame? {
            if case .decoded(let frame) = self { return frame }
            return nil
        }
    }

    struct Read {
        fileprivate let owner: Residency?
        fileprivate let client: UUID
        fileprivate let key: String?
        fileprivate let result: ReadResult
        fileprivate let needsInsertion: Bool
        var decodedFrame: DecodedFrame? { result.frame }
    }

    fileprivate final class Residency {
        let ring: DecodedFrameRing
        var readers: [String: VideoFrameReader] = [:]
        var recency: [String] = []
        init(ring: DecodedFrameRing) { self.ring = ring }
    }

    private let ownership = NSLock()
    private let decoding = NSLock()
    private var residency: Residency
    private var clients: [UUID: Bool] = [:] // false = idle, true = has read; absence = closed
    private let byteBudget: Int
    private let readerLimit: Int
    private var pressureToken: MemoryPressure.Token?
    private var decodes = 0

    init(byteBudget: Int = VideoFrameSource.defaultByteBudget,
         readerLimit: Int = VideoFrameSource.defaultReaderLimit) {
        self.byteBudget = max(0, byteBudget)
        self.readerLimit = max(1, readerLimit)
        residency = Residency(ring: DecodedFrameRing(byteBudget: byteBudget))
        pressureToken = MemoryPressure.register("VideoFrameSource") { [weak self] level in self?.respond(to: level) }
        MemoryPressure.startObservingSystemEvents()
    }

    func makeClient() -> Client {
        let id = UUID()
        ownership.lock(); clients[id] = false; ownership.unlock()
        return Client(source: self, id: id)
    }

    private func isClosed(_ id: UUID) -> Bool {
        ownership.lock(); defer { ownership.unlock() }
        return clients[id] == nil
    }

    private func close(_ id: UUID) {
        ownership.lock()
        guard clients.removeValue(forKey: id) != nil else { ownership.unlock(); return }
        let retired = clients.values.contains(true) ? nil : retireLocked(keepingRing: false)
        ownership.unlock()
        withExtendedLifetime(retired) {}
    }

    /// Existing memory-pressure policy: warning keeps the hottest half of decoded pixels and
    /// closes pipes; background releases both. The ring's normal admission ceiling stays unchanged.
    private func respond(to level: MemoryPressure.Level) {
        ownership.lock()
        let retired = retireLocked(keepingRing: level.trims != .background)
        ownership.unlock()
        withExtendedLifetime(retired) {}
    }

    /// Returns reader references for destruction outside the ownership lock. A running decode
    /// keeps only its own reader alive; repeated resets cannot accumulate full old reader pools.
    private func retireLocked(keepingRing: Bool) -> [String: VideoFrameReader] {
        let old = residency
        let retired = old.readers
        old.readers = [:]
        old.recency = []
        let ring: DecodedFrameRing
        if keepingRing {
            ring = old.ring
            ring.byteBudget = MemoryPressurePolicy.budget(.warning, normalBytes: byteBudget)
            ring.byteBudget = byteBudget
        } else {
            old.ring.removeAll()
            ring = DecodedFrameRing(byteBudget: byteBudget)
        }
        residency = Residency(ring: ring)
        return retired
    }

    private func begin(_ id: UUID) -> Residency? {
        ownership.lock(); defer { ownership.unlock() }
        guard clients[id] != nil else { return nil }
        clients[id] = true
        return residency
    }

    private func isCurrent(_ owner: Residency, client id: UUID) -> Bool {
        ownership.lock(); defer { ownership.unlock() }
        return residency === owner && clients[id] == true
    }

    private func info(client id: UUID, for url: URL) -> VideoAssetInfo? {
        guard let owner = begin(id) else { return nil }
        decoding.lock(); defer { decoding.unlock() }
        guard isCurrent(owner, client: id), let reader = reader(for: url, owner: owner, client: id),
              isCurrent(owner, client: id) else { return nil }
        return reader.info
    }

    /// Keep a normal read's lookup, conversion and admission in the same serial turn. Another
    /// worker cannot decode the same timestamp between conversion and admission.
    private func read(client id: UUID, assetURL url: URL, at time: SourceTime) -> ReadResult {
        decoding.lock(); defer { decoding.unlock() }
        return finish(decodeLocked(client: id, assetURL: url, at: time), client: id)
    }

    private func decode(client id: UUID, assetURL url: URL, at time: SourceTime) -> Read {
        decoding.lock(); defer { decoding.unlock() }
        return decodeLocked(client: id, assetURL: url, at: time)
    }

    private func decodeLocked(client id: UUID, assetURL url: URL, at time: SourceTime) -> Read {
        func result(_ value: ReadResult, owner: Residency? = nil, key: String? = nil,
                    insertion: Bool = false) -> Read {
            Read(owner: owner, client: id, key: key, result: value, needsInsertion: insertion)
        }
        guard let owner = begin(id) else { return result(.unavailable) }
        guard isCurrent(owner, client: id) else { return result(.unavailable) }
        guard let reader = reader(for: url, owner: owner, client: id),
              let stamp = reader.locate(time.cmTime, whileCurrent: { self.isCurrent(owner, client: id) }) else {
            return result(isCurrent(owner, client: id) ? .missing : .unavailable, owner: owner)
        }
        let key = "\(url.path)#\(stamp.value)/\(stamp.timescale)"
        if let hit = owner.ring.frame(for: key) { return result(.decoded(hit), owner: owner, key: key) }
        guard isCurrent(owner, client: id) else { return result(.unavailable) }
        guard let frame = reader.currentFrame() else { return result(.missing, owner: owner) }
        ownership.lock(); decodes += 1; ownership.unlock()
        return result(.decoded(frame), owner: owner, key: key, insertion: true)
    }

    private func finish(_ read: Read, client id: UUID) -> ReadResult {
        ownership.lock(); defer { ownership.unlock() }
        guard read.client == id, clients[id] == true, let owner = read.owner,
              residency === owner else { return .unavailable }
        if read.needsInsertion, let frame = read.result.frame, let key = read.key { owner.ring.insert(frame, for: key) }
        return read.result
    }

    /// Called under the serial decode lock. No AVFoundation work or reader destruction holds the
    /// ownership lock, so lifecycle changes cannot queue behind a seek or decoder teardown.
    private func reader(for url: URL, owner: Residency, client id: UUID) -> VideoFrameReader? {
        ownership.lock()
        guard residency === owner, clients[id] == true else { ownership.unlock(); return nil }
        if let existing = owner.readers[url.path] {
            touch(url.path, in: owner)
            ownership.unlock()
            return existing
        }
        ownership.unlock()
        guard let made = VideoFrameReader(url: url) else { return nil }
        var retired: [VideoFrameReader] = []
        ownership.lock()
        guard residency === owner, clients[id] == true else { ownership.unlock(); return nil }
        owner.readers[url.path] = made
        owner.recency.append(url.path)
        while owner.readers.count > readerLimit, let oldest = owner.recency.first {
            owner.recency.removeFirst()
            if let reader = owner.readers.removeValue(forKey: oldest) { retired.append(reader) }
        }
        ownership.unlock()
        withExtendedLifetime(retired) {}
        return made
    }

    private func touch(_ key: String, in owner: Residency) {
        guard let index = owner.recency.firstIndex(of: key), index != owner.recency.count - 1 else { return }
        owner.recency.remove(at: index)
        owner.recency.append(key)
    }

    var openReaderCount: Int { ownership.lock(); defer { ownership.unlock() }; return residency.readers.count }
    var residentBytes: Int { ownership.lock(); defer { ownership.unlock() }; return residency.ring.byteCount }
    var decodedCount: Int { ownership.lock(); defer { ownership.unlock() }; return decodes }
    /// Cached app-held sample payload only. This blocks behind decode for a consistent diagnostic;
    /// lifecycle/readiness does not. AVFoundation's internal decoder pools remain unmeasured.
    var retainedSampleCount: Int { sampleOwnership().count }
    var retainedSampleBytes: Int { sampleOwnership().bytes }
    private func sampleOwnership() -> (count: Int, bytes: Int) {
        decoding.lock(); defer { decoding.unlock() }
        ownership.lock(); let readers = Array(residency.readers.values); ownership.unlock()
        return readers.reduce((0, 0)) { ($0.0 + $1.retainedSampleCount, $0.1 + $1.retainedSampleBytes) }
    }
}
