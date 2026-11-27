import ObjectiveC
import UIKit

/// **A canvas-sized picture that is repaired in place** — SCHEDULER_DESIGN.md §3.1, built in S3b.
///
/// A vector layer's picture is 95 MiB at the owner's 5000². Before this every edit to it — a stroke
/// landing, an eraser cut, an Undo — made a **new** picture: a canvas-sized bitmap, the old one
/// copied in whole, the damage cleared and re-walked. So each landed edit and each Undo held two
/// pictures of one layer for the length of a walk and copied 95 MiB to change a few hundred kilobytes.
///
/// Since `d72eb69f` the render server only ever gets window surfaces, so nothing outside the app holds a
/// picture and its pixels can change under the readers it has. This type is what makes that safe:
///
/// - **Every read of the pixels is fenced.** The `CGImage` a picture hands out reads its bytes through a
///   direct-access provider whose `getBytePointer` counts a reader in and whose `releaseBytePointer`
///   counts it out, so every CoreGraphics draw of it — a host's window draw, a composite, a bake —
///   runs between two writes, never across one.
/// - **A write is exclusive and short.** `write` waits for the readers in flight to finish (new ones wait
///   behind it), and copies a damage-sized patch in: the walk that made the patch ran beforehand into a
///   buffer of its own, so a cancelled walk leaves the picture untouched.
/// - **Each revision is a new wrapper** (`image`, an `Image` naming its revision), so an identity check
///   — `CanvasPictureView.show` — sees the new picture as new, and a reader that cares whether the
///   pixels are still the ones it was handed asks `isCurrent(_:)`.
///
/// Memory: the bytes are admitted by the one budget (`MemoryBudget`) when the picture is made and the
/// grant lives as long as the pixels — a wrapper still held after the canvas let the picture go keeps
/// it counted until the last one goes. A patch (`PixelPatch`) is admitted the same way.
nonisolated final class LayerPicture: @unchecked Sendable {

    /// **What a wrapper is a picture of**: the picture and the revision it was minted at, attached to
    /// the `UIImage` (`UIImage` cannot be subclassed from Swift).
    private final class Tag {
        let picture: LayerPicture
        let revision: Int
        init(picture: LayerPicture, revision: Int) { self.picture = picture; self.revision = revision }
    }
    private static var tagKey: UInt8 = 0

    /// The picture `image` wraps, and the revision it was minted at — nil for any other image.
    static func of(_ image: UIImage?) -> (picture: LayerPicture, revision: Int)? {
        guard let image, let tag = objc_getAssociatedObject(image, &tagKey) as? Tag else { return nil }
        return (tag.picture, tag.revision)
    }

    /// **Whether `image` still shows what it showed when it was handed out** — false only for a wrapper
    /// of a picture that has been written since. Any other image never changes.
    static func isCurrent(_ image: UIImage) -> Bool {
        guard let wrapped = of(image) else { return true }
        return wrapped.picture.revision == wrapped.revision
    }

    let width: Int
    let height: Int
    let bytesPerRow: Int
    /// Raster pixels per canvas point.
    let scale: CGFloat
    private let pixels: UnsafeMutableRawPointer
    private let grant: MemoryBudget.Grant

    /// Readers in, a writer in or waiting — every field below is guarded by it.
    private let access = NSCondition()
    private var readers = 0
    private var writing = false
    private var revisionValue = 0
    private weak var wrapper: UIImage?
    private var wrapperRevision = -1

    private init(width: Int, height: Int, scale: CGFloat, pixels: UnsafeMutableRawPointer, grant: MemoryBudget.Grant) {
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        self.scale = scale
        self.pixels = pixels
        self.grant = grant
    }

    deinit {
        free(pixels)
        grant.release()
    }

    /// **A picture drawn by `draw`** into a fresh, budget-admitted buffer — `PixelOps.drawImage`'s
    /// context exactly (sRGB, premultiplied BGRA, a flipped UIKit context made current). Nil when the
    /// bytes are refused or `draw` abandons the picture.
    static func draw(size: CGSize, scale: CGFloat = 1, _ draw: (CGContext) -> Bool) -> LayerPicture? {
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let grant = MemoryBudget.shared.admit(width * 4 * height),
              let buffer = calloc(width * 4 * height, 1) else { return nil }
        let picture = LayerPicture(width: width, height: height, scale: scale, pixels: buffer, grant: grant)
        guard let cg = Self.context(over: buffer, width: width, height: height) else { return nil }
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(cg)
        let completed = draw(cg)
        UIGraphicsPopContext()
        return completed ? picture : nil
    }

    /// The format every picture and patch is drawn in.
    fileprivate static func context(over buffer: UnsafeMutableRawPointer, width: Int, height: Int) -> CGContext? {
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return CGContext(data: buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                         space: PixelOps.sRGBColorSpace, bitmapInfo: info)
    }

    /// The picture's revision: moved by every `write`.
    var revision: Int {
        access.lock(); defer { access.unlock() }
        return revisionValue
    }

    /// **The current revision's wrapper** — one object per revision, so asking twice between two writes
    /// answers the same image.
    var image: UIImage {
        access.lock()
        defer { access.unlock() }
        if let wrapper, wrapperRevision == revisionValue { return wrapper }
        return mintLocked()
    }

    /// A new `CGImage` over the same bytes, read through the fence. Caller holds `access`.
    private func mintLocked() -> UIImage {
        var callbacks = CGDataProviderDirectCallbacks(
            version: 0,
            getBytePointer: { info in
                let picture = Unmanaged<LayerPicture>.fromOpaque(info!).takeUnretainedValue()
                picture.beginRead()
                return UnsafeRawPointer(picture.pixels)
            },
            releaseBytePointer: { info, _ in
                Unmanaged<LayerPicture>.fromOpaque(info!).takeUnretainedValue().endRead()
            },
            getBytesAtPosition: nil,
            releaseInfo: { info in Unmanaged<LayerPicture>.fromOpaque(info!).release() })
        let provider = CGDataProvider(directInfo: Unmanaged.passRetained(self).toOpaque(),
                                      size: off_t(bytesPerRow * height), callbacks: &callbacks)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                         space: PixelOps.sRGBColorSpace, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                         decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let image = UIImage(cgImage: cg, scale: scale, orientation: .up)
        objc_setAssociatedObject(image, &Self.tagKey, Tag(picture: self, revision: revisionValue), .OBJC_ASSOCIATION_RETAIN)
        wrapper = image
        wrapperRevision = revisionValue
        return image
    }

    // MARK: - The fence

    private func beginRead() {
        access.lock()
        while writing { access.wait() }   // an active writer only — see `exclusively`
        readers += 1
        access.unlock()
    }

    private func endRead() {
        access.lock()
        readers -= 1
        if readers == 0 { access.broadcast() }
        access.unlock()
    }

    /// Readers in flight — a test's view of the fence.
    var readersInFlight: Int {
        access.lock(); defer { access.unlock() }
        return readers
    }

    /// **Runs `body` with the pixels to itself**: no reader between its start and its end. Waits at
    /// most `timeout` for the readers already in — new ones are not held back while it waits, so a draw
    /// that reads the picture inside another read of it (a composite inside a draw) can never deadlock
    /// against a writer. False, with `body` not run, when they did not leave in time: something is
    /// holding the bytes, and the caller makes a new picture rather than waiting on it. Never on the main
    /// thread (rule 1).
    func exclusively(timeout: TimeInterval, _ body: () -> Void) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        access.lock()
        while writing || readers > 0 {
            if !access.wait(until: deadline) { access.unlock(); return false }
        }
        writing = true
        access.unlock()
        body()
        access.lock()
        writing = false
        access.broadcast()
        access.unlock()
        return true
    }

    // MARK: - Patches

    /// `rect` (canvas points) as whole pixels of this picture, clamped to it; nil when nothing is left.
    func pixelRect(of rect: CGRect) -> PixelRect? {
        let minX = max(0, Int((rect.minX * scale).rounded(.down))), minY = max(0, Int((rect.minY * scale).rounded(.down)))
        let maxX = min(width, Int((rect.maxX * scale).rounded(.up))), maxY = min(height, Int((rect.maxY * scale).rounded(.up)))
        guard maxX > minX, maxY > minY else { return nil }
        return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// **`patch.rect`'s pixels, copied into `patch`** — the writer keeping what it is about to replace,
    /// or a walk starting from what is there. Called inside `exclusively`, or by the one walk that may
    /// write this picture (`VectorCanvas`'s walk in flight), which no other writer can race.
    func copy(into patch: PixelPatch) {
        let rect = patch.rect
        precondition(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= width && rect.y + rect.height <= height)
        for row in 0..<rect.height {
            memcpy(patch.bytes + row * patch.bytesPerRow,
                   pixels + (rect.y + row) * bytesPerRow + rect.x * 4, patch.bytesPerRow)
        }
    }

    /// **Copies `patch` in** at its rectangle. Called inside `exclusively`; the readers see it once the
    /// writer is out, and a new wrapper once it says so (`revise()`).
    func write(_ patch: PixelPatch) {
        let rect = patch.rect
        precondition(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= width && rect.y + rect.height <= height)
        for row in 0..<rect.height {
            memcpy(pixels + (rect.y + row) * bytesPerRow + rect.x * 4,
                   patch.bytes + row * patch.bytesPerRow, patch.bytesPerRow)
        }
    }

    /// **Moves the revision** after a write that stands, and answers the new revision's wrapper. Every
    /// earlier wrapper stops being `isCurrent`.
    func revise() -> UIImage {
        access.lock()
        defer { access.unlock() }
        revisionValue += 1
        return mintLocked()
    }

    /// Bytes the picture's pixels take.
    var byteCount: Int { bytesPerRow * height }
}

/// A rectangle of whole pixels.
nonisolated struct PixelRect: Equatable, Sendable {
    let x: Int, y: Int, width: Int, height: Int
    var byteCount: Int { width * 4 * height }
}

/// **A rectangle of a picture's pixels, in a buffer of its own** — the damage a repair walks into, or
/// the pixels an edit replaced, kept for its Undo. Admitted by the one budget for as long as it lives.
nonisolated final class PixelPatch: @unchecked Sendable {
    let rect: PixelRect
    let scale: CGFloat
    let bytes: UnsafeMutableRawPointer
    let bytesPerRow: Int
    private let grant: MemoryBudget.Grant

    /// A transparent patch over `rect`, or nil when the bytes are refused.
    init?(rect: PixelRect, scale: CGFloat) {
        guard let grant = MemoryBudget.shared.admit(rect.byteCount), let bytes = calloc(rect.byteCount, 1) else { return nil }
        self.rect = rect
        self.scale = scale
        self.bytes = bytes
        self.bytesPerRow = rect.width * 4
        self.grant = grant
    }

    deinit { free(bytes) }

    var byteCount: Int { rect.byteCount }

    /// The patch's rectangle in canvas points.
    var canvasRect: CGRect {
        CGRect(x: CGFloat(rect.x) / scale, y: CGFloat(rect.y) / scale,
               width: CGFloat(rect.width) / scale, height: CGFloat(rect.height) / scale)
    }

    /// The patch as an image over its own bytes, for a draw made while the patch is held.
    var cgImage: CGImage {
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let provider = CGDataProvider(dataInfo: nil, data: bytes, size: byteCount, releaseData: { _, _, _ in })!
        return CGImage(width: rect.width, height: rect.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: PixelOps.sRGBColorSpace, bitmapInfo: CGBitmapInfo(rawValue: info),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// **Draws into the patch in canvas points**: the context is `LayerPicture.draw`'s, moved so a point
    /// of the canvas lands on the pixel it lands on in the whole picture — whole pixels only, so every
    /// dab, clip and antialiased edge falls exactly as it would there.
    func draw(_ body: (CGContext) -> Bool) -> Bool {
        guard let cg = LayerPicture.context(over: bytes, width: rect.width, height: rect.height) else { return false }
        cg.translateBy(x: 0, y: CGFloat(rect.height))
        cg.scaleBy(x: 1, y: -1)
        cg.translateBy(x: -CGFloat(rect.x), y: -CGFloat(rect.y))
        cg.scaleBy(x: scale, y: scale)
        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }
        return body(cg)
    }
}
