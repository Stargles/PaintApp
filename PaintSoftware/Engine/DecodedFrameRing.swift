import Foundation
import CoreGraphics

/// One decoded baked frame: tightly packed BGRA rows, premultiplied, alpha first.
///
/// RENDER §3.5 fixes the layout, and it is the layout for a reason rather than a taste: **BGRA
/// premultiplied-first is what Core Animation wants**, so a frame handed to a layer in it is
/// displayed with no conversion at all. The convert that costs a hitch per stroke-lift today
/// (BUGS.md) happens once, off-main, at bake time instead. The store writes these bytes and this
/// type is what comes back out of the decoder.
///
/// A value type, and deliberately: it crosses out of `DecodedFrameRing`'s lock as a copy, so
/// `makeImage()` — the expensive half — runs with no lock held while the baker keeps inserting.
/// `Data` is copy-on-write, so "a copy" is a retain.
struct DecodedFrame {

    let width: Int
    let height: Int

    /// Row stride. Kept as its own field rather than assumed to be `width * 4`: the decoder writes
    /// back whatever stride the encoder recorded in the store's header, and a texture readback can
    /// legitimately be padded.
    let bytesPerRow: Int

    /// The pixels, `bytesPerRow * height` of them at minimum.
    let pixels: Data

    var byteCount: Int { pixels.count }

    init(width: Int, height: Int, bytesPerRow: Int, pixels: Data) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }

    /// Tightly packed, `width * 4` bytes a row.
    init(width: Int, height: Int, pixels: Data) {
        self.init(width: width, height: height, bytesPerRow: width * 4, pixels: pixels)
    }

    /// The frame as a `CGImage`, **without copying the pixels**: the provider is built over the
    /// `Data` itself, so this is a retain and a header rather than a `bytesPerRow * height` memcpy.
    /// At 2048² that is 16.8 MB not moved, per displayed frame, at 24 fps.
    ///
    /// Callable from any thread and off the ring's lock — nothing here touches the ring.
    ///
    /// Nil rather than a malformed image when the dimensions and the buffer disagree, which is the
    /// shape a truncated or corrupt store file arrives in. `shouldInterpolate: false` matches every
    /// other `CGImage` this app mints from a provider (`Compositor.makeImage`,
    /// `MetalCompositor.readBack`, `MaskResolver`), and `PixelOps.deviceRGBColorSpace` is the one
    /// spelling of the space they all share.
    func makeImage() -> CGImage? {
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }
        guard pixels.count >= bytesPerRow * height else { return nil }
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: PixelOps.deviceRGBColorSpace,
                       bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The frames just ahead of the playhead, decoded and resident, under a **byte** budget.
///
/// RENDER §3.5: *"A small decoded ring holds the frames just ahead of the playhead, under a byte
/// budget rather than a count. Play never decodes on the display thread."* The scheduler decodes
/// ahead into this on its own queue; the playback tick reads out of it and displays. A miss is not
/// an error — it is §2.10, the previous picture staying up while the bake catches up.
///
/// ## Bytes, not a count
///
/// A count is not a budget when a frame's size is the artist's own knob: at the Render Resolution
/// slider's extremes one frame is 0.1 MB or 16.8 MB, so "hold eight frames" is 1 MB on one document
/// and 134 MB on another. The whole feature exists because the iPad has little memory (§1), so the
/// ceiling has to be the thing that is actually scarce.
///
/// ## Keyed by the bake key's digest, not by frame number
///
/// A hold's nine frames share one key and are therefore **one entry** — which is the entire reason
/// RENDER §3.3 leaves `frame` out of the key, and a ring keyed by frame number would throw that
/// away nine times over. It also makes staleness impossible to express: an edit moves the key, so
/// a resident entry can never be served for a frame whose key has changed. There is no invalidation
/// path in this type because there is nothing to invalidate — that is the property, not an omission.
///
/// ## Eviction is LRU by last access
///
/// Which is exactly "drop the frame furthest behind the playhead" without this type knowing what a
/// playhead is: the scheduler decodes ahead in playhead order and the tick reads in playhead order,
/// so recency of access *is* proximity to the playhead. A scrub reversal re-reads the frames behind
/// and they become recent again on their own. That is why there is no policy argument here and no
/// frame numbers at all.
///
/// ## Thread safety
///
/// The baker inserts on its own queue while the display thread reads, so every operation is taken
/// under one `NSLock` held for its whole body — the same bargain `CompositorMetalEngine` makes
/// (RENDER §4). Nothing expensive happens inside it: `frame(for:)` returns a value type and
/// `DecodedFrame.makeImage()` runs outside.
final class DecodedFrameRing {

    private let lock = NSLock()

    private var frames: [String: DecodedFrame] = [:]

    /// Digests least-recently-used first. An array rather than a heap or a linked list because the
    /// ring holds `byteBudget / frameBytes` entries — single digits to low tens at any realistic
    /// budget and frame size — so the O(n) touch is a handful of pointer moves and the alternative
    /// is bookkeeping that costs more than it saves.
    private var recency: [String] = []

    private var residentBytes = 0

    private var budget: Int

    /// - Parameter byteBudget: the ceiling. Clamped at zero; a zero budget is a legal, working
    ///   ring that holds nothing, which is what a device under memory pressure should be able to
    ///   ask for without the caller needing a second code path.
    init(byteBudget: Int) {
        budget = max(byteBudget, 0)
    }

    /// The ceiling, in bytes. **Lowering it evicts immediately** rather than at the next insert:
    /// the reason to lower it is that the memory is needed now.
    var byteBudget: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return budget
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            budget = max(newValue, 0)
            evictLocked()
        }
    }

    /// How many bytes are resident.
    var byteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return residentBytes
    }

    /// How many frames are resident. Diagnostics and tests — the budget is bytes.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }

    /// Takes `frame` in under `digest`, evicting least-recently-used entries to stay under budget.
    ///
    /// - Returns: false when the frame was **not** stored, which happens for exactly one reason:
    ///   it is larger than the whole budget. It is refused rather than admitted over the ceiling,
    ///   because the ring is an optimisation and the store is the truth — a frame too big to cache
    ///   is decoded per display instead, which is slow, where blowing the ceiling is a crash on the
    ///   device this feature exists to fit inside. A frame that merely does not fit *right now*
    ///   is stored and something older leaves.
    @discardableResult
    func insert(_ frame: DecodedFrame, for digest: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard frame.byteCount <= budget else { return false }
        removeLocked(digest)
        frames[digest] = frame
        recency.append(digest)
        residentBytes += frame.byteCount
        evictLocked()
        return true
    }

    /// The frame for `digest`, marking it most recently used. Nil is the ordinary case, not an
    /// error: RENDER §2.10 keeps the previous picture up.
    func frame(for digest: String) -> DecodedFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard let frame = frames[digest] else { return nil }
        if let index = recency.firstIndex(of: digest), index != recency.count - 1 {
            recency.remove(at: index)
            recency.append(digest)
        }
        return frame
    }

    /// Whether `digest` is resident, **without** touching its recency — so a caller can ask what
    /// is warm (the timeline's baked-frame indication, RENDER §3.7) without reordering eviction.
    func contains(_ digest: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return frames[digest] != nil
    }

    /// Drops everything. The document closing, or the store being dumped.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll()
        recency.removeAll()
        residentBytes = 0
    }

    // MARK: - Under the lock

    private func evictLocked() {
        while residentBytes > budget, let oldest = recency.first {
            removeLocked(oldest)
        }
    }

    private func removeLocked(_ digest: String) {
        guard let frame = frames.removeValue(forKey: digest) else { return }
        residentBytes -= frame.byteCount
        if let index = recency.firstIndex(of: digest) { recency.remove(at: index) }
    }
}
