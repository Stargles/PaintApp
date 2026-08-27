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

    /// The size `autoSize` should give the box for this recipe: exactly what the string measures,
    /// never wrapped, floored so an empty box is still a visible target and still tall enough to
    /// hold a caret.
    ///
    /// **Stage 1's cap at the canvas's right edge is gone, and its removal is the point.** A
    /// point-text box is supposed to grow rightward forever; stage 1 capped it because with no
    /// handles there was no way to drag a runaway box back, so the overflow became a wrap. Stage 4
    /// builds the handles, so the reason expired and the cap went with it — a title laid across a
    /// canvas and beyond it is a normal thing to type, and re-wrapping it at an edge the artist
    /// cannot see reads as the app rewriting their layout.
    ///
    /// Nothing bounds the returned width now, and nothing needs to: the only cost that scales with
    /// it is the live overlay's glyph bitmap, and `TextOverlayView.glyphContentsScale` caps that in
    /// *texels* rather than in points (ADD_TEXT.md §4 rule 1) — which is the bound that actually
    /// holds, since it survives a zoom as well as a long string.
    static func autoSize(for recipe: TextRecipe, font: UIFont) -> CGSize {
        let unwrapped = measure(recipe, font: font, maxWidth: nil).size
        return CGSize(width: max(unwrapped.width, minimumBoxWidth),
                      height: max(unwrapped.height, font.lineHeight))
    }

    /// Wide enough that an empty box is a visible target rather than a hairline, in canvas points.
    ///
    /// Defined as `TextFrame.minimumExtent` rather than beside it as a second literal: the smallest
    /// box auto-size can make and the smallest a handle drag can make are one figure, and two spellings
    /// of one number is the kind of thing that drifts.
    static let minimumBoxWidth: CGFloat = TextFrame.minimumExtent

    /// The floor under `renderBox`'s backing scale. Not zero — a zero-scale renderer produces an
    /// empty image and a caller that divided by it would produce a NaN — and low enough that the
    /// texel cap, not this, is what a very wide box actually meets.
    static let minimumRenderScale: CGFloat = 0.05

    // MARK: - Rasterizing

    /// The bake. One canvas-sized transparent image with the recipe's glyphs drawn into the frame's
    /// box, ready for `PixelOps.compositeOver`.
    ///
    /// **One canvas-sized allocation, once, at commit** — ADD_TEXT.md §4 rule 7, and identical in
    /// shape and cost to a fill commit, which is already accepted. Nothing in the *live* path calls
    /// this: the live overlay is a `UITextView` at text-box size, which is rule 1.
    ///
    /// **Stage 4 draws through `TextFrame.affineTransform`**, so a box the artist has rotated or
    /// sized bakes turned, with no bitmap and no resampling anywhere — CoreText lays the glyphs out
    /// in the box's own coordinates and CoreGraphics carries them through one concatenated matrix.
    /// For an upright frame that matrix *is* the translate stage 1 wrote, which is why this
    /// generalisation changed no stage-1 pixel.
    ///
    /// **Stage 5 replaced the fallback branch with the warp.** A frame with no affine map is now
    /// either `.projective` — glyphs rasterised at box size and carried through `warpHomography` (or
    /// its scalar Swift twin) onto the quad — or genuinely collapsed, in which case the stage 1
    /// bounding-box draw is still the honest approximation and is still what happens.
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
            if let transform = frame.affineTransform {
                cg.concatenate(transform)
                draw(recipe, font: font, boxSize: frame.size, clip: !frame.autoSize, into: cg)
            } else if drawWarped(recipe, frame: frame,
                                 clip: CGRect(origin: .zero, size: canvasSize), library: library) {
                // Nothing more: the warp drew itself, in canvas coordinates, above — and inside the
                // canvas, which is the only part of it this image will ever show.
            } else {
                cg.translateBy(x: box.minX, y: box.minY)
                draw(recipe, font: font, boxSize: box.size, clip: !frame.autoSize, into: cg)
            }
            cg.restoreGState()
        }
    }

    // MARK: - Warping

    /// The supersample ceiling on a warp's source bitmap. Past 3× the artist cannot see the
    /// difference and the backing store is the square of it — ADD_TEXT.md §1's cap on the live
    /// overlay's `contentsScale`, reused for the bake because it is the same trade.
    static let maximumWarpSupersample: CGFloat = 3

    /// And the absolute one, in texels on the longest side. §4 rule 1: "capped absolutely at
    /// 4096×4096 texels even fully supersampled". A cap in *points* is not a cap at all once
    /// `autoSize` can grow a title as wide as the string.
    static let maximumWarpTexels: CGFloat = 4096

    /// The same 4096, on the warp's **destination**, and it is a second bound rather than the same
    /// one restated.
    ///
    /// `maximumWarpTexels` bounds the glyph bitmap the warp reads. This bounds what it writes, and
    /// the destination is where the memory actually is: `ImageWarp.warpedImage` holds three
    /// `w × h × 4` buffers of it at once, on top of the canvas-sized flatten and composite the bake
    /// already pays for. At 4096 that is 3 × 64 MiB against ADD_TEXT.md §4 rule 6's 192 MiB, which
    /// is why the clip to the canvas below comes first and this only catches what is left.
    ///
    /// **Not a refusal.** Past the cap the warp is rasterised smaller and drawn up into the full
    /// rectangle, so an artist who has stretched a title across a 4096² canvas gets softer glyphs
    /// rather than a jetsam — and, at or below 4096², gets exactly what stage 5 shipped, since the
    /// clipped destination cannot exceed the canvas and the canvas cannot exceed the cap.
    static let maximumWarpDestinationTexels: CGFloat = 4096

    /// How many source texels per canvas point a warp's glyph bitmap should carry, so the densest
    /// part of the destination is not resampled up from too little.
    ///
    /// The densest part is a *corner* — `Homography.maximumCornerScale` says why — which is exactly
    /// the property that makes a strongly foreshortened quad affordable: the near edge asks for the
    /// detail and the far edge, which is where most of the area went, costs nothing extra.
    static func warpSourceScale(boxSize: CGSize, homography: Homography) -> CGFloat {
        let wanted = max(1, min(homography.maximumCornerScale(ofBox: boxSize), maximumWarpSupersample))
        let longest = max(boxSize.width, boxSize.height, 1)
        return max(minimumRenderScale, min(wanted, maximumWarpTexels / longest))
    }

    /// The recipe's glyphs carried onto the frame's quad: the image, and the canvas rectangle it
    /// covers.
    ///
    /// **One box-sized raster, one warp over the quad's bounding box.** Neither is canvas-sized, and
    /// neither happens more than once per commit — ADD_TEXT.md §4 rule 7. §2's rejected alternative,
    /// a CPU resample as the *live* path, is the one this must not become: it is called from the bake
    /// and from the vector flatten, never from a gesture.
    ///
    /// `sourceScale` is read back off the rendered image rather than taken from what was asked for,
    /// because `UIGraphicsImageRenderer` rounds its pixel dimensions and a half-texel of disagreement
    /// between the two would be a half-texel shift in every warped glyph.
    ///
    /// **`clip` is the destination's memory bound and it is not optional.** ADD_TEXT.md §2 predicted
    /// this exact failure when it rejected the CPU resample — *"'the destination is the quad's bbox,
    /// never the canvas' is not a bound; a title across a 4096 canvas has a bbox approaching canvas
    /// size"* — and one corner dragged off-canvas makes it far worse than that: a quad corner at
    /// (50 000, 50 000) is a bounding box of 2.5 billion points, which is hundreds of megabytes on a
    /// device ADD_TEXT.md §4 rule 6 budgets at 192 MiB before jetsam. Intersecting with what the
    /// caller can actually show is **lossless** — a texel outside the destination context can never
    /// be seen and can never be saved, so nothing is being traded away for the bound. It is required
    /// rather than defaulted so a fourth call site cannot forget it; the two that exist pass the
    /// canvas rectangle and the context's own clip.
    ///
    /// Nil when the intersection is empty — a box dragged entirely off-canvas. The caller then falls
    /// through to its bounding-box draw, which is harmless precisely because that draw lands inside
    /// the same bounding box that just failed to meet the clip, and CoreGraphics clips it away.
    static func warpedGlyphs(recipe: TextRecipe, frame: TextFrame, clip: CGRect,
                             library: FontLibrary = .shared) -> (image: UIImage, destination: CGRect)? {
        guard !recipe.string.isEmpty, let homography = frame.homography else { return nil }
        let destination = frame.boundingBox.integral.intersection(clip.integral)
        guard destination.width >= 1, destination.height >= 1 else { return nil }
        let scale = warpSourceScale(boxSize: frame.size, homography: homography)
        guard let source = renderBox(recipe: recipe, boxSize: frame.size, clip: !frame.autoSize,
                                     scale: scale, library: library)?.cgImage,
              source.width > 0, source.height > 0 else { return nil }
        let sourceScale = CGFloat(source.width) / frame.size.width
        guard let warped = ImageWarp.warpedImage(
            source: source, sourceScale: sourceScale, boxSize: frame.size, homography: homography,
            destination: destination,
            maximumDestinationTexels: maximumWarpDestinationTexels) else { return nil }
        return (UIImage(cgImage: warped, scale: 1, orientation: .up), destination)
    }

    /// Draws the warped glyphs into the *current UIKit graphics context* at their canvas position,
    /// and reports whether it had anything to draw.
    ///
    /// Shared by the raster bake and the vector flatten so the two cannot come to disagree about
    /// where a warped box lands — the same discipline that made `draw` internal in stage 3, one level
    /// up. `UIImage.draw(in:)` rather than `CGContext.draw(_:in:)` because both callers are inside a
    /// `UIGraphicsImageRenderer`, whose context is already y-flipped for UIKit; the CoreGraphics call
    /// would put the text upside down.
    ///
    /// **`clip` is what the destination is allowed to cost** — see `warpedGlyphs`. A caller holding a
    /// `CGContext` and no canvas size passes `cg.boundingBoxOfClipPath`, which is the same statement
    /// made by the context itself: pixels outside the clip are the ones CoreGraphics is about to
    /// throw away, so allocating them was never anything but cost.
    @discardableResult
    static func drawWarped(_ recipe: TextRecipe, frame: TextFrame, clip: CGRect,
                           library: FontLibrary = .shared) -> Bool {
        guard let warped = warpedGlyphs(recipe: recipe, frame: frame, clip: clip,
                                        library: library) else { return false }
        warped.image.draw(in: warped.destination)
        return true
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
    ///
    /// **A `scale` below 1 is honoured, and stage 4 is what made that matter.** It used to be
    /// floored at 1, which was harmless while `autoSize` capped a box at the canvas's right edge and
    /// silently stopped bounding anything the moment that cap was removed: a point-text box now
    /// grows as wide as the string, and a floor of 1 would turn a very long title into a bitmap as
    /// many pixels across as it is points. The caller's cap is expressed in *texels* precisely so it
    /// can ask for less than one pixel per point, which is ADD_TEXT.md §4 rule 1 — "capped absolutely
    /// at 4096×4096 texels even fully supersampled" — and a floor at 1 defeated it.
    static func renderBox(recipe: TextRecipe, boxSize: CGSize, clip: Bool, scale: CGFloat,
                          library: FontLibrary = .shared) -> UIImage? {
        guard !recipe.string.isEmpty, boxSize.width > 0, boxSize.height > 0 else { return nil }
        let font = library.resolve(recipe.font, size: recipe.typography.clamped.pointSize).font
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        format.scale = max(minimumRenderScale, scale)
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: boxSize), format: format)
        return renderer.image { context in
            draw(recipe, font: font, boxSize: boxSize, clip: clip, into: context.cgContext)
        }
    }

    /// Draws into `cg` with the box's top-left at the current origin, y increasing downward.
    ///
    /// The one place CoreText's y-up convention is flipped for drawing — `measure` flips it for
    /// reading. Two flips in one file, both stated, rather than a flip per call site.
    ///
    /// **Internal rather than private, and that is the whole of stage 3's rasterizer story.**
    /// `render` (the raster bake), `renderBox` (the live overlay's bitmap) and
    /// `VectorCanvas.draw(text:into:quality:)` (the vector flatten) are three destinations for one
    /// set of glyphs, and every one of them arrives here. `ADD_TEXT.md` §2's closing warning is that
    /// a shared *transform* does not make two rasterizers agree; sharing the rasterizer is what does,
    /// and a vector path that laid its own text out would be the second one this design exists to
    /// prevent.
    static func draw(_ recipe: TextRecipe, font: UIFont, boxSize: CGSize, clip: Bool,
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

// MARK: - Measure-only

/// Where a placed text object's ink actually lands on the canvas, and **nothing that rasterizes**.
///
/// Split out from `TextLayout` under its own name because the distinction is the point rather than
/// tidiness: this is what the display list's *geometry* queries call, from inside
/// `VectorCanvas`'s non-reentrant lock, on paths (`collectResidueGarbage`, `hasContentBeneath`) that
/// run per eraser commit. A helper that quietly reached for `renderBox` there would put a bitmap
/// allocation inside a lock on the eraser's path, which is the shape of the 53.8 ms trap `BUGS.md`
/// records. Everything here is CoreText measurement — one framesetter pass, no context, no image.
///
/// Nothing is cached, for `TextLayout`'s own stated reason: the object stores a recipe and never a
/// result, a measurement is well under a millisecond at text-box size, and a stale one is a bug that
/// survives a font change.
enum TextMeasure {

    /// The canvas-space rectangle the element's glyphs cover, or nil when it has no ink at all.
    ///
    /// Line boxes rather than glyph outlines — the union of each line's (ascent + descent) band over
    /// its typographic width, offset to the frame. That is a superset of the true outline and a
    /// subset of the frame, which is the honest direction for both callers: a `contentBounds` that
    /// under-reported would let the garbage collector drop an `.erase` punch that was still hiding
    /// something, and the visible result of that is ink reappearing where the artist erased it.
    ///
    /// **Exact while the frame is upright, conservative once it is not.** A rotated or distorted
    /// frame (stages 4-5) falls back to `frame.boundingBox`, because its line boxes are measured in
    /// box-local space and mapping them through the frame's map is the homography stage 5 introduces.
    /// Larger is the safe side, and the fallback is stated here rather than silently wrong later.
    static func inkBounds(of element: VectorTextElement, library: FontLibrary = .shared) -> CGRect? {
        let recipe = element.recipe
        guard !recipe.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let frame = element.frame
        let box = frame.boundingBox
        guard box.width > 0, box.height > 0 else { return nil }
        guard frame.isUprightTranslation else { return box }

        let font = library.resolve(recipe.font, size: recipe.typography.clamped.pointSize).font
        // A sized box wraps and clips into its own width; a pristine one was grown to fit and never
        // wraps. Same pair of answers `TextLayout.render` hands `clip:`.
        let metrics = TextLayout.measure(recipe, font: font,
                                         maxWidth: frame.autoSize ? nil : frame.size.width)
        var ink: CGRect?
        for line in metrics.lines where line.width > 0 {
            let rect = CGRect(x: line.baselineOrigin.x,
                              y: line.baselineOrigin.y - line.ascent,
                              width: line.width,
                              height: line.ascent + line.descent)
            ink = ink.map { $0.union(rect) } ?? rect
        }
        guard var result = ink else { return nil }
        // A sized box hides what runs past it (`ADD_TEXT.md` §5.3, "overflow clips"), so ink outside
        // it is not on the canvas and must not be claimed as a backdrop.
        if !frame.autoSize {
            let local = CGRect(origin: .zero, size: frame.size)
            guard result.intersects(local) else { return nil }
            result = result.intersection(local)
        }
        return result.offsetBy(dx: box.minX, dy: box.minY)
    }
}
