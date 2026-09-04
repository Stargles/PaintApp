import UIKit
import CoreGraphics

/// **A tip's alpha mask is square, and that is a ruling rather than an accident of the first
/// asset.** BRUSH.md §3.5's image primitive carries one number for a dab's size, `DabPose` scales
/// it with one multiply, and `StrokeScratch` bounds it with one `abs`. A tip free to be 512×64
/// would put an aspect ratio into all three, and into `BakedDab`, for a shape the artist can
/// express anyway by leaving the mask's margins transparent — which is also what Procreate's
/// square Shape Sources do. `BrushTipImport` letterboxes a non-square PNG into a square mask on the
/// way in; nothing downstream of here ever asks a tip how wide it is.
///
/// The named tips are the ones committed to the app bundle. §12 stage 9 replaces this file's single
/// case with the generated set, and does it by adding cases here — the loader, the cache and the
/// primitive do not move.
enum BuiltInBrushTexture: String, Hashable, CaseIterable {

    /// **The square brush's tip.** A 256×256 straight-alpha RGBA PNG: black throughout, alpha 255
    /// inside an axis-aligned square inset by 2 px, alpha 0 in the 2 px border.
    ///
    /// The border is not padding — it is what a rotated or downscaled draw antialiases *into*.
    /// MEASURED at `.high` interpolation, a 16 pt dab turned 0.4 rad comes back with edge alphas of
    /// 142 and 237 against a saturated core; the same draw from a border-less mask comes back 255
    /// across the whole span, i.e. aliased. 2/256 is 0.78% of the tip, which is 1.6 px at the app's
    /// largest brush (200 pt) and 0.13 px at 16 pt.
    ///
    /// Reproducing it is eleven lines and no dependencies: fill a 256×256 RGBA byte buffer with
    /// `(0, 0, 0, 0)`, set alpha to 255 where `2 <= x < 254 && 2 <= y < 254`, and write it through
    /// `CGImage` + `CGImageDestination` as `CGImageAlphaInfo.last` (straight, not premultiplied).
    case square

    /// The PNG's basename in the app bundle. The `brushtip-` prefix exists because a synchronized
    /// root group flattens `Resources/` into the bundle root, where a file called `square.png`
    /// would be one artist's icon away from a collision.
    var resourceName: String { "brushtip-\(rawValue)" }
}

/// **Which alpha mask a dab stamps, and the name its cache entry is keyed on.**
///
/// RENDER.md §3.8 records three memos in this repo keyed on a buffer's *size*, each of which
/// silently serves one content's pixels for another's at a matching size. `DabImageCache` is the
/// fourth cache of that family and this type is why it is not the fourth bug: the key names the
/// tip, so two tips can never be the same entry however alike their dimensions.
///
/// **Both arms are load-bearing, and neither is built ahead of its use.** BRUSH.md §12 stage 3
/// required the built-in square to load "through the same path an imported texture will use", which
/// is a claim about there being one path — testable only against a second arm that actually
/// resolves a file. Stage 5 made that arm the artist's: `BrushTip.stamp(BrushTextureRef)` is the
/// whole of a brush's shape, and an imported PNG reaches the renderer by being one of these.
enum BrushTextureRef: Hashable {
    /// A tip committed to the app bundle.
    case builtIn(BuiltInBrushTexture)
    /// A PNG under `BrushLibrary.customBrushesDirectory`, written by `BrushTipImport`.
    case imported(fileName: String)
}

extension BuiltInBrushTexture: Codable {}

extension BrushTextureRef: Codable {
    private enum CodingKeys: String, CodingKey { case builtIn, imported }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtIn(let tip): try container.encode(tip, forKey: .builtIn)
        case .imported(let fileName): try container.encode(fileName, forKey: .imported)
        }
    }

    /// One key present, and which key it is *is* the case. Strict on anything else, for the reason
    /// `BrushTip`'s own decoder is: there is no earlier spelling of this to be tolerant of, so a
    /// container with neither key is a corrupt file rather than an old one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let tip = try container.decodeIfPresent(BuiltInBrushTexture.self, forKey: .builtIn) {
            self = .builtIn(tip)
        } else if let fileName = try container.decodeIfPresent(String.self, forKey: .imported) {
            self = .imported(fileName: fileName)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath,
                                      debugDescription: "A brush texture is either builtIn or imported"))
        }
    }
}

/// **Every tip's alpha mask, loaded once per process.**
///
/// A mask is colour-independent, small (256² is 256 KB), and decoding one costs a file read plus a
/// PNG decode — so it is cached here rather than in `DabImageCache`, which holds the *tinted*
/// result and therefore has one entry per colour. Splitting the two is what keeps a palette change
/// from re-reading the disk.
///
/// **Thread-safe, unlike the per-dab caches.** Masks are loaded off whichever thread stamps first —
/// live drawing is on main, a bake or an export is not — and unlike `DabGradientCache` this is not
/// on the hot path: after the first dab of the first stroke every call is a dictionary hit under an
/// uncontended lock.
enum BrushTextureStore {

    private static let lock = NSLock()
    /// `nil` for a ref whose file is missing, cached as a negative so a broken import costs one
    /// failed read rather than one per dab.
    private static var masks: [BrushTextureRef: CGImage?] = [:]

    /// The tip's alpha mask, or nil when its file is missing or undecodable.
    ///
    /// A nil answer draws nothing, which is the honest failure for a tip whose PNG the artist
    /// deleted — the same shape `FontLibrary` gives a missing face. It is *not* a silent one: the
    /// dab is skipped rather than substituted, so a stroke that loses its tip disappears instead of
    /// turning into some other brush.
    static func mask(for ref: BrushTextureRef) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = masks[ref] { return cached }
        let loaded = load(ref)
        masks[ref] = loaded
        return loaded
    }

    private static func load(_ ref: BrushTextureRef) -> CGImage? {
        guard let url = url(for: ref), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)?.cgImage
    }

    /// The one resolution step, and the whole of what "the same path an imported texture will use"
    /// means: two ways to name a file, one way to read it.
    ///
    /// `Bundle(for:)` rather than `Bundle.main` because this file is compiled into the UI-test
    /// target as well as the app — CLAUDE.md's "an app source a logic test touches is compiled a
    /// second time" — and there `Bundle.main` is the XCUITest *runner*, which carries none of the
    /// app's resources. `Bundle(for:)` answers the bundle the code itself came from in both.
    static func url(for ref: BrushTextureRef) -> URL? {
        switch ref {
        case .builtIn(let tip):
            return Bundle(for: BrushTextureBundleToken.self).url(forResource: tip.resourceName, withExtension: "png")
        case .imported(let fileName):
            return BrushLibrary.customBrushesDirectory.appendingPathComponent(fileName)
        }
    }
}

/// Nothing but an address for `Bundle(for:)`. `BrushTextureStore` is an enum and enums have no
/// class to ask.
final class BrushTextureBundleToken {}

/// **The artist's own PNG, turned into a tip.** BRUSH.md §12 stage 5's import half.
///
/// Everything downstream of `BrushTextureRef` reads a mask's **alpha** as the dab's coverage — that
/// is what `DabImageCache` tints and what the committed square is. So the one rule this type exists
/// to enforce is that *a file under `BrushLibrary.customBrushesDirectory` is a mask*, in exactly the
/// sense the built-in square is, whatever the artist picked. The renderer then has one meaning for a
/// tip's pixels rather than two, and `BuiltInBrushTexture.square`'s own description doubles as the
/// specification for every import.
///
/// Three things happen on the way in, and each is a ruling rather than a convenience:
///
/// 1. **Square, by `BuiltInBrushTexture`'s ruling.** A non-square picture is letterboxed into a
///    square mask with transparent margins, because a dab's size is one scalar everywhere below
///    `stampImage` and an aspect ratio would put a second number into `DabPose`, `BakedDab` and the
///    dirty-rect bound for a shape the artist can express by leaving the margins clear anyway.
/// 2. **256², at a 2 px transparent border** — the same as the committed square, and the border for
///    the same reason it has one: it is what a rotated or downscaled draw antialiases *into*. A
///    photo letterboxed edge-to-edge would alias along whichever side filled the frame. 256 is also
///    what every §3.5 measurement was taken at, and what bounds `BrushTextureStore`'s resident cost
///    — a 12 MP import held at source resolution would be 48 MB of mask.
/// 3. **An opaque picture is read as ink-on-white, not as a solid square.** This is the one
///    inference here, and without it the feature is unusable for the format artists' stamps
///    actually come in: `.abr`-style stamps and everything scanned are grayscale with no alpha
///    channel at all, and a photo picked out of Photos is opaque by construction. Read as alpha,
///    every one of them is a filled square — the brush draws a block whatever the picture was.
///    Read as `1 - luminance` they are the stamp the artist sees, which is also what Procreate's
///    Shape Source does with an imported image and what a `.abr` brush's grayscale means.
///
///    **The test is on the pixels rather than on the file's metadata**: alpha is examined inside the
///    letterbox, and only a picture that is opaque *there* is read by luminance. A PNG that carries
///    real transparency keeps its alpha, so the rule cannot silently invert a mask that was already
///    a mask.
enum BrushTipImport {

    /// The pixel side every imported mask is normalised to — `BuiltInBrushTexture.square`'s.
    static let maskSide = 256
    /// The transparent margin left around the picture, in mask pixels. `BuiltInBrushTexture.square`
    /// carries the measurement for why it is not padding.
    static let border = 2

    enum Failure: Error {
        /// The picked item could not be drawn at all.
        case unreadableImage
        /// It could be drawn and every pixel of the result is clear — a white-on-white scan, or a
        /// blank page. Named rather than folded into the above because the artist can act on it,
        /// and because a brush that silently draws nothing is the failure this stage is most likely
        /// to ship: it looks exactly like a broken renderer.
        case blankMask
        case couldNotWrite(Error)
    }

    /// Normalises `image`, writes it under `BrushLibrary.customBrushesDirectory`, and answers the
    /// tip that stamps it. The whole of what "importing a brush" means, in one call, so the import
    /// UI holds no part of the rule.
    static func importTip(from image: UIImage) throws -> BrushTip {
        guard let data = UIImage(cgImage: try mask(from: image)).pngData() else {
            throw Failure.unreadableImage
        }
        let fileName = "custom-\(UUID().uuidString).png"
        do {
            try data.write(to: BrushLibrary.customBrushesDirectory.appendingPathComponent(fileName))
        } catch {
            throw Failure.couldNotWrite(error)
        }
        return .stamp(.imported(fileName: fileName))
    }

    /// The normalisation itself, with no filesystem in it: `image` as a square straight-alpha mask.
    ///
    /// It throws rather than answering nil because the two ways to have no mask are not the same
    /// news for the artist — "that would not open" and "that is blank" call for different fixes —
    /// and a nil that means both is exactly the collapse `BrushTip` removed from the model.
    static func mask(from image: UIImage) throws -> CGImage {
        let side = maskSide
        guard image.size.width > 0, image.size.height > 0 else { throw Failure.unreadableImage }
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.unreadableImage }
        ctx.interpolationQuality = .high
        let fit = letterbox(width: image.size.width, height: image.size.height)
        // Flipped to UIKit's top-left space so `UIImage.draw` lands the picture the way the artist
        // saw it — orientation metadata included, which `image.cgImage` alone would drop.
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        image.draw(in: fit)
        UIGraphicsPopContext()

        guard let raw = ctx.data else { throw Failure.unreadableImage }
        let bytes = raw.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let byLuminance = isOpaque(bytes, side: side, inside: fit)
        var inked = false
        for i in stride(from: 0, to: side * side * 4, by: 4) {
            let a = Int(bytes[i + 3])
            var coverage = a
            if byLuminance, a > 0 {
                // The buffer is premultiplied, so un-premultiply before taking the picture's own
                // luminance, then re-apply the draw's own coverage at the letterbox edge.
                let luminance = (299 * Int(bytes[i]) + 587 * Int(bytes[i + 1]) + 114 * Int(bytes[i + 2])) / 1000
                coverage = (255 - luminance * 255 / a) * a / 255
            }
            coverage = max(0, min(coverage, 255))
            bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0
            bytes[i + 3] = UInt8(coverage)
            if coverage > 0 { inked = true }
        }
        guard inked else { throw Failure.blankMask }
        guard let mask = ctx.makeImage() else { throw Failure.unreadableImage }
        return mask
    }

    /// The rect, in the mask's own top-left space, that `image` is drawn into: the largest
    /// aspect-preserving fit inside the bordered square, centred.
    static func letterbox(width: CGFloat, height: CGFloat) -> CGRect {
        let inner = CGFloat(maskSide - 2 * border)
        let k = min(inner / width, inner / height)
        let w = width * k, h = height * k
        return CGRect(x: (CGFloat(maskSide) - w) / 2, y: (CGFloat(maskSide) - h) / 2, width: w, height: h)
    }

    /// Whether the drawn picture carries no transparency of its own, judged **inside** the letterbox
    /// and inset by two pixels so the resample's own antialiased boundary is not mistaken for the
    /// artist's alpha. A degenerate fit answers false, which keeps the alpha as it stands — the
    /// conservative direction, since misreading a real mask as opaque would invert it.
    private static func isOpaque(_ bytes: UnsafeMutablePointer<UInt8>, side: Int, inside fit: CGRect) -> Bool {
        let box = fit.insetBy(dx: 2, dy: 2).intersection(CGRect(x: 0, y: 0, width: side, height: side))
        guard box.width >= 1, box.height >= 1 else { return false }
        for y in Int(box.minY.rounded(.up))..<Int(box.maxY.rounded(.down)) {
            for x in Int(box.minX.rounded(.up))..<Int(box.maxX.rounded(.down)) {
                if bytes[(y * side + x) * 4 + 3] != 255 { return false }
            }
        }
        return true
    }
}
