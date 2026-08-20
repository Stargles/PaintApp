import CoreGraphics
import CoreText
import UIKit

/// Turning a `TextRecipe` into glyphs — measurement, line metrics, and the one rasterizer the bake
/// uses.
///
/// **Nothing here is cached, and that is the design.** ADD_TEXT.md §1's rule is that the object
/// stores a recipe and never a result; this type is the "never a result" half made concrete. A
/// measurement is cheap (CoreText into a text-box-sized layout is well under a millisecond on an
/// A13, §4.3), a stale one is a bug that survives a font change, and there is no third option that
/// is both fast and correct.
///
/// Every entry point takes the `UIFont` rather than the `FontDescriptor`, so the resolution walk —
/// and the substitution report that comes with it — happens once at the call site instead of being
/// silently repeated per measurement. `resolvedFont(for:)` is the one convenience that does both.
enum TextLayout {

    // MARK: - Attributes

    /// CoreText's view of a recipe. The single place typography turns into attributes, so the
    /// measurement, the on-canvas `UITextView` and the bake cannot disagree about what a slider
    /// means.
    ///
    /// **Tracking is `.kern`, and the string's last character is deliberately excluded from it.**
    /// `.kern` adds its advance *after* every character it is applied to, so applying it to the
    /// whole string leaves a trailing gap the width of one tracking step — which is invisible on a
    /// left-aligned line and visibly wrong on a centred or right-aligned one, because the gap is
    /// inside the measured width the alignment is computed from. Excluding the final character is
    /// the standard fix. It is not a complete one: a *wrapped* line still ends in a kerned
    /// character, so its trailing gap survives. Stage 1 accepts that; the complete fix is per-line
    /// and belongs with the line-editing work, not here.
    static func attributedString(_ recipe: TextRecipe, font: UIFont) -> NSAttributedString {
        let typography = recipe.typography.clamped
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = nsAlignment(typography.alignment)
        paragraph.lineHeightMultiple = typography.lineHeightMultiple
        paragraph.lineSpacing = typography.lineSpacing
        paragraph.paragraphSpacing = typography.paragraphSpacing
        paragraph.lineBreakMode = .byWordWrapping

        let color = UIColor(red: CGFloat(recipe.color.red), green: CGFloat(recipe.color.green),
                            blue: CGFloat(recipe.color.blue),
                            alpha: CGFloat(recipe.color.alpha) * CGFloat(recipe.opacity))

        let attributed = NSMutableAttributedString(
            string: recipe.string,
            attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: color]
        )
        if typography.tracking != 0, attributed.length > 0 {
            attributed.addAttribute(.kern, value: typography.tracking,
                                    range: NSRange(location: 0, length: attributed.length - 1))
        }
        return attributed
    }

    static func nsAlignment(_ alignment: Typography.Alignment) -> NSTextAlignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        }
    }

    /// The font a recipe asks for, plus whether it is the font it asked for. One line at every call
    /// site that needs both, so nobody resolves without looking at the answer.
    static func resolvedFont(for recipe: TextRecipe, library: FontLibrary = .shared) -> FontResolution {
        library.resolve(recipe.font, size: recipe.typography.clamped.pointSize)
    }

    // MARK: - Measurement

    /// One laid-out line, in **box coordinates with y increasing downward** — UIKit's convention,
    /// not CoreText's. The flip happens here, once, rather than at three call sites that would each
    /// get it subtly differently.
    struct Line: Equatable {
        /// Range in the recipe's string.
        var range: NSRange
        /// Where the line's baseline starts, measured from the box's top-left. `x` already carries
        /// the alignment offset, which is what makes alignment testable without rendering.
        var baselineOrigin: CGPoint
        /// The line's typographic width — for a justified line other than the last, the box width.
        var width: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
    }

    struct Metrics: Equatable {
        /// The layout's own size: the widest line by the height of everything. What `autoSize`
        /// writes into `TextFrame.size`.
        var size: CGSize
        var lines: [Line]
    }

    /// Lays the recipe out, wrapping at `maxWidth` when one is given and never wrapping when it is
    /// nil (a `nil` width is a point-text box that grows to the right; `TextFrame.autoSize`).
    ///
    /// Returns zero metrics for an empty string rather than a one-line-tall empty box. A box with
    /// nothing in it bakes nothing, and the caller that wants a caret-height empty box asks the
    /// font for its line height directly.
    static func measure(_ recipe: TextRecipe, font: UIFont, maxWidth: CGFloat? = nil) -> Metrics {
        let attributed = attributedString(recipe, font: font)
        guard attributed.length > 0 else { return Metrics(size: .zero, lines: []) }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint = CGSize(width: maxWidth ?? CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)
        var fitRange = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraint, &fitRange)

        // The path is a hair taller than the suggested height. CoreText drops a line that does not
        // fit *entirely* inside the path, and `suggested.height` comes back rounded to a value that
        // is occasionally a fraction short of what the frame then needs — which silently loses the
        // last line. One extra point costs nothing and closes it.
        let boxWidth = maxWidth ?? ceil(suggested.width)
        let boxHeight = ceil(suggested.height) + 1
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight), transform: nil)
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        let ctLines = (CTFrameGetLines(ctFrame) as? [CTLine]) ?? []
        var origins = [CGPoint](repeating: .zero, count: ctLines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)

        var lines: [Line] = []
        lines.reserveCapacity(ctLines.count)
        var widest: CGFloat = 0
        for (index, ctLine) in ctLines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
            let ctRange = CTLineGetStringRange(ctLine)
            // CoreText's origins are y-up from the bottom of the path; UIKit wants y-down from its
            // top. The baseline is the origin, so the flip is the path height minus it.
            let baseline = CGPoint(x: origins[index].x, y: boxHeight - origins[index].y)
            lines.append(Line(range: NSRange(location: ctRange.location, length: ctRange.length),
                              baselineOrigin: baseline, width: width, ascent: ascent, descent: descent))
            widest = max(widest, width)
        }

        // The measured size is the suggestion, not the sum of the line boxes: CoreText's suggestion
        // already accounts for `lineHeightMultiple`, `lineSpacing` and `paragraphSpacing`, and
        // re-deriving it from the line list is a second implementation of the same arithmetic that
        // would drift from the first.
        let size = CGSize(width: maxWidth ?? max(widest, suggested.width), height: suggested.height)
        return Metrics(size: size, lines: lines)
    }

    /// The size `autoSize` should give the box for this recipe, bounded so a very long line cannot
    /// run off the canvas and out of reach.
    ///
    /// **The bound is a Stage 1 pragmatic one, and it is a decision worth naming**: a point-text box
    /// is supposed to grow rightward forever, but with no handles yet (Stage 4) there is no way to
    /// bring one back once it has left the canvas. Capping at the canvas's right edge turns the
    /// runaway into a wrap, which is visible and recoverable. Once handles exist the cap can go.
    static func autoSize(for recipe: TextRecipe, font: UIFont, originX: CGFloat,
                         canvasSize: CGSize) -> CGSize {
        let available = max(minimumBoxWidth, canvasSize.width - originX)
        let unwrapped = measure(recipe, font: font, maxWidth: nil).size
        if unwrapped.width <= available {
            return CGSize(width: max(unwrapped.width, minimumBoxWidth), height: max(unwrapped.height, font.lineHeight))
        }
        let wrapped = measure(recipe, font: font, maxWidth: available).size
        return CGSize(width: available, height: max(wrapped.height, font.lineHeight))
    }

    /// Wide enough that an empty box is a visible target rather than a hairline, in canvas points.
    static let minimumBoxWidth: CGFloat = 24

    // MARK: - Rasterizing

    /// The bake. One canvas-sized transparent image with the recipe's glyphs drawn into the frame's
    /// box, ready for `PixelOps.compositeOver`.
    ///
    /// **One canvas-sized allocation, once, at commit** — ADD_TEXT.md §4 rule 7, and identical in
    /// shape and cost to a fill commit, which is already accepted. Nothing in the *live* path calls
    /// this: the live overlay is a `UITextView` at text-box size, which is rule 1.
    ///
    /// Stage 1 draws with a translate and no resampling at all, because every Stage 1 frame is
    /// `isUprightTranslation`. A frame that is not — which only Stages 4-5 can produce — is drawn
    /// through its own bounding box for now, so the code is honest about being Stage 1 rather than
    /// silently drawing the wrong thing; Stage 5 replaces this branch with the `warpHomography`
    /// kernel and its scalar Swift twin.
    static func render(recipe: TextRecipe, frame: TextFrame, canvasSize: CGSize,
                       library: FontLibrary = .shared) -> UIImage? {
        guard !recipe.string.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let box = frame.boundingBox
        guard box.width > 0, box.height > 0 else { return nil }

        let font = library.resolve(recipe.font, size: recipe.typography.clamped.pointSize).font

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        // Canvas pixels, not screen pixels: the destination is the cel's raster, which is
        // `canvasSize` texels regardless of the device's scale factor.
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: canvasSize), format: format)

        return renderer.image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: box.minX, y: box.minY)
            draw(recipe, font: font, boxSize: box.size, clip: !frame.autoSize, into: cg)
            cg.restoreGState()
        }
    }

    /// The same glyphs at *box* size rather than canvas size — the live overlay's bitmap.
    ///
    /// **The live preview and the bake share this drawing code, which is the only reason they
    /// agree.** ADD_TEXT.md §2's closing warning is that a shared *transform* does not make two
    /// rasterizers identical; sharing the rasterizer itself is what does. Stage 1 can have that
    /// outright, because there is no warp yet: both paths are CoreText into a CGContext with a
    /// translate, differing only in scale. Stage 5's `CATransform3D` preview is where the divergence
    /// §4 records as an open risk actually starts.
    ///
    /// `scale` is backing pixels per canvas point. The caller caps it; see
    /// `TextOverlayView.glyphContentsScale`.
    static func renderBox(recipe: TextRecipe, boxSize: CGSize, clip: Bool, scale: CGFloat,
                          library: FontLibrary = .shared) -> UIImage? {
        guard !recipe.string.isEmpty, boxSize.width > 0, boxSize.height > 0 else { return nil }
        let font = library.resolve(recipe.font, size: recipe.typography.clamped.pointSize).font
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        format.scale = max(1, scale)
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: boxSize), format: format)
        return renderer.image { context in
            draw(recipe, font: font, boxSize: boxSize, clip: clip, into: context.cgContext)
        }
    }

    /// Draws into `cg` with the box's top-left at the current origin, y increasing downward.
    ///
    /// The one place CoreText's y-up convention is flipped for drawing — `measure` flips it for
    /// reading. Two flips in one file, both stated, rather than a flip per call site.
    private static func draw(_ recipe: TextRecipe, font: UIFont, boxSize: CGSize, clip: Bool,
                             into cg: CGContext) {
        let attributed = attributedString(recipe, font: font)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        cg.saveGState()
        // A sized box clips; a pristine one has been grown to fit and has nothing to clip. That is
        // ADD_TEXT.md §5.3 — "overflow clips" — and the reason `autoSize` is a stored bit.
        if clip { cg.clip(to: CGRect(origin: .zero, size: boxSize)) }
        cg.translateBy(x: 0, y: boxSize.height)
        cg.scaleBy(x: 1, y: -1)
        cg.textMatrix = .identity
        let path = CGPath(rect: CGRect(origin: .zero, size: boxSize), transform: nil)
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(ctFrame, cg)
        cg.restoreGState()
    }
}
