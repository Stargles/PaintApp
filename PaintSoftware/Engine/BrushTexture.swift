import UIKit
import CoreGraphics

/// **A tip's alpha mask is square, and that is a ruling rather than an accident of the first
/// asset.** BRUSH.md §3.5's image primitive carries one number for a dab's size, `DabPose` scales
/// it with one multiply, and `StrokeScratch` bounds it with one `abs`. A tip free to be 512×64
/// would put an aspect ratio into all three, and into `BakedDab`, for a shape the artist can
/// express anyway by leaving the mask's margins transparent — which is also what Procreate's
/// square Shape Sources do. §12 stage 5's import path letterboxes a non-square PNG into a square
/// mask; nothing downstream of here ever asks a tip how wide it is.
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
/// **Both arms are load-bearing now, and `.imported` is not built ahead of its use.** BRUSH.md
/// §12 stage 3 requires the built-in square to load "through the same path an imported texture
/// will use", which is a claim about there being one path — testable only against a second arm
/// that actually resolves a file. Stage 5's `BrushTip.stamp(BrushTextureRef)` is then this type
/// with a `Codable` conformance and nothing else.
enum BrushTextureRef: Hashable {
    /// A tip committed to the app bundle.
    case builtIn(BuiltInBrushTexture)
    /// A PNG under `BrushLibrary.customBrushesDirectory` — what §12 stage 5 points
    /// `Brush.customTextureFileName` at.
    case imported(fileName: String)
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
