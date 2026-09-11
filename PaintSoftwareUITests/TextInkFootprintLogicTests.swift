import XCTest
import UIKit
import CoreGraphics

/// **Every non-transparent pixel a pristine text object puts on a vector cel is inside the rectangle
/// its departure declares** — `VectorCanvas.derivedFootprint(of:lowestResolution:)`'s `autoSize` arm,
/// the second box of TODO (41).
///
/// A **sized** text box clips its own glyphs, so its stored frame bounds its ink by proof. A
/// **pristine** box was grown by `CTFramesetterSuggestFrameSizeWithConstraints`, a *typographic*
/// extent that glyph ink runs past by whatever a font's italic overhang, swashes or accents care to,
/// and a departure has no escape check behind it: a rectangle that misses those pixels is a ghost of
/// the old glyphs, permanently, where one that is too large is only slow. So the bound is a
/// *measurement* — `TextMeasure.glyphOutlineBounds(of:)`, `CTLineGetImageBounds` on the frame the
/// flatten draws — padded by the rasteriser's own overshoot past the outline
/// (`TextMeasure.glyphRasterOvershoot`, a device-pixel figure), and this file is the proof that the
/// padded rectangle holds. **It rasterises and checks pixels**: the element is drawn by the shipped
/// flatten, every pixel with any alpha is walked, and each one has to fall inside the rectangle the
/// shipped press declares. Nothing here reads the bound off a formula and compares it to another
/// formula.
///
/// **The three operands that keep this from being green by accident.** (1) The fixture asserts the
/// string actually painted — a face that draws nothing for a string would pass any bound. (2) The ink
/// must stay off the image's own border, so the canvas is not clipping an escape out of sight. (3)
/// The rectangle is read from `lastDamage` after a real `restoreElements` press, so the route under
/// test is the shipped one — a mutation that sends `autoSize` back to `.everything` fails here on the
/// `.region` check; one that shrinks the overshoot by one pixel fails the spare-pixel check on Zapfino
/// and a hundred cases beside it; one that shrinks it by two fails the pixel walk itself, on Zapfino
/// upright at 48 pt first (its "Q" reaches 1.04 px past its outline at native resolution).
///
/// **The reduced-resolution arm is the half that makes the pad a device-pixel figure.** The canvas
/// keeps one below-native picture (`reducedRender`) with its own region base, and a repair there
/// runs at that slot's resolution, where one pixel of overshoot is `1/resolution` canvas points. The
/// sweep renders at the reduced resolution *first*, so the slot is standing when the press declares
/// its rectangle — the order the shipped thumbnail path takes — and then checks the reduced picture's
/// pixels against the rectangle scaled and snapped exactly as `repairClip` snaps it.
final class TextInkFootprintLogicTests: XCTestCase {

    // MARK: - The fixture

    /// Room around the box for glyphs that reach past it. Ink is asserted off the border, so a
    /// margin that turns out too small reads as a failure rather than as a clipped escape.
    private static func margin(for pointSize: CGFloat) -> CGFloat { pointSize * 1.5 + 32 }

    private static func recipe(_ string: String, font: FontDescriptor, pointSize: CGFloat) -> TextRecipe {
        TextRecipe(string: string, font: font, typography: Typography(pointSize: pointSize),
                   color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), opacity: 1)
    }

    /// A pristine box laid out the way the app lays one out — `TextLayout.autoSize` for its size —
    /// turned by `rotation` about its own top-left and placed so its bounding box sits `margin`
    /// inside a canvas built to fit it.
    private static func fixture(_ recipe: TextRecipe, rotation: CGFloat)
    -> (canvas: VectorCanvas, element: VectorTextElement)? {
        let font = TextLayout.resolvedFont(for: recipe).font
        let size = TextLayout.autoSize(for: recipe, font: font)
        let u = CGVector(dx: cos(rotation), dy: sin(rotation))
        let v = CGVector(dx: -sin(rotation), dy: cos(rotation))
        let corners = TextFrame.corners(origin: .zero, u: u, v: v, width: size.width, height: size.height)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let margin = margin(for: recipe.typography.pointSize)
        let shifted = corners.map { CGPoint(x: $0.x - minX + margin, y: $0.y - minY + margin) }
        let frame = TextFrame(size: size, corners: shifted, mode: .affine, autoSize: true)
        let element = VectorTextElement(recipe: recipe, frame: frame)
        let canvasSize = CGSize(width: ceil(maxX - minX + 2 * margin), height: ceil(maxY - minY + 2 * margin))
        return (VectorCanvas(size: canvasSize, elements: [.text(element)]), element)
    }

    // MARK: - Reading pixels

    /// The integer box of every pixel with any alpha at all, in the image's own pixels, or nil for a
    /// blank image. The bytes are copied into a known RGBA8 layout first so no assumption is made
    /// about the renderer's byte order.
    private func inkBox(_ image: UIImage) -> (box: CGRect?, width: Int, height: Int) {
        guard let cg = image.cgImage else { return (nil, 0, 0) }
        let width = cg.width, height = cg.height
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return (nil, width, height)
        }
        context.interpolationQuality = .none
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, maxX = -1, minY = height, maxY = -1
        buffer.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                let row = y * bytesPerRow
                for x in 0..<width where p[row + x * 4 + 3] != 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0 else { return (nil, width, height) }
        // A bitmap context's row 0 is the top of the picture and so is UIKit's y = 0, so no flip.
        return (CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1), width, height)
    }

    /// `rect` in canvas points as the device-pixel clip `repairClip` would make of it at
    /// `resolution`: snapped *out* to whole pixels.
    private func snappedClip(_ rect: CGRect, resolution: CGFloat) -> CGRect {
        let minX = (rect.minX * resolution).rounded(.down)
        let minY = (rect.minY * resolution).rounded(.down)
        return CGRect(x: minX, y: minY,
                      width: (rect.maxX * resolution).rounded(.up) - minX,
                      height: (rect.maxY * resolution).rounded(.up) - minY)
    }

    // MARK: - The check

    /// How far the ink reached past the declared rectangle on its worst side, in device pixels
    /// (0 when contained); how far it reached past the *unpadded* outline bounds, which is the
    /// number the overshoot constant is set from; and the declared rectangle. Nil when the case
    /// could not be measured at all — the fixture failures are reported inside.
    ///
    /// `reach` is `outlineEdge − inkPixelIndex` on the worst side, in device pixels: the ink's
    /// outermost pixel *index* against the outline's edge, so a reach of 1.04 means the outline
    /// starts inside pixel 87 and a pixel with ink exists at index 86. The clip is
    /// `floor(outlineEdge − pad)`, so a pad `p` holds exactly when `p > reach − 1` on every case.
    @discardableResult
    private func assertInkInsideDeclaredRectangle(
        _ recipe: TextRecipe, rotation: CGFloat, resolution: CGFloat, _ what: String,
        file: StaticString = #filePath, line: UInt = #line
    ) -> (escape: CGFloat, reach: CGFloat, declared: CGRect)? {
        guard let (canvas, element) = Self.fixture(recipe, rotation: rotation) else {
            XCTFail("\(what): could not build a frame", file: file, line: line)
            return nil
        }
        // The standing picture — native, or the reduced slot — is rendered *before* the press, which
        // is the order the artist's undo takes: the picture is there, the object departs, and the
        // rectangle has to cover what the picture still shows.
        let image = resolution >= 1 ? canvas.render() : canvas.render(quality: .full, resolution: resolution)
        let ink = inkBox(image)
        guard let box = ink.box else {
            XCTFail("\(what): fixture precondition — the string painted no pixel at all, so there is "
                    + "nothing to bound", file: file, line: line)
            return nil
        }
        XCTAssertTrue(box.minX > 0 && box.minY > 0 && box.maxX < CGFloat(ink.width)
                      && box.maxY < CGFloat(ink.height),
                      "\(what): ink touches the image border at \(box) in \(ink.width)x\(ink.height) — "
                      + "the canvas may be clipping an escape out of sight; widen the fixture's margin",
                      file: file, line: line)

        canvas.restoreElements([], changedInk: nil)
        guard case .region(let declared) = canvas.lastDamage else {
            XCTFail("\(what): the departure declared \(canvas.lastDamage) — a pristine text object is "
                    + "bounded by its measured glyph ink since TODO (41), so a departing one must "
                    + "declare a rectangle", file: file, line: line)
            return nil
        }
        let clip = snappedClip(declared, resolution: resolution)
        let escape = max(clip.minX - box.minX, clip.minY - box.minY,
                         box.maxX - clip.maxX, box.maxY - clip.maxY, 0)
        XCTAssertEqual(escape, 0,
                       "\(what): ink pixels \(box) reach \(escape) px outside the declared rectangle "
                       + "\(declared) (snapped to \(clip) at resolution \(resolution)) — a departure "
                       + "repaired inside that rectangle would leave a ghost of those pixels",
                       file: file, line: line)
        // The outline itself, in device pixels, against the ink's outermost pixel indices.
        let outline = TextMeasure.glyphOutlineBounds(of: element)
        // On the near sides the clip is `floor(edge − pad)` and holds iff `pad > edge − index − 1`;
        // on the far sides it is `ceil(edge + pad)` and holds iff `pad > lastIndex − edge`, which
        // with `box.maxX = lastIndex + 1` is the same `pad > reach − 1` once `reach` is written as
        // `box.maxX − edge`. One inequality for all four sides.
        let reach = max(outline.minX * resolution - box.minX,
                        outline.minY * resolution - box.minY,
                        box.maxX - outline.maxX * resolution,
                        box.maxY - outline.maxY * resolution)
        // **The spare pixel.** Containment above holds iff `pad > reach − 1`; this holds iff
        // `pad > reach`, which is the same statement with one whole pixel of cover left over — the
        // margin `glyphRasterOvershoot`'s doc records the constant as carrying. Red here means the
        // rasteriser is reaching further than it did when the constant was set: the picture is still
        // right, and the constant needs re-measuring before it is not. A pad one pixel smaller fails
        // this on Zapfino upright at 48 pt (reach 1.04) and on every case that reaches past a pixel.
        XCTAssertLessThan(reach, TextMeasure.glyphRasterOvershoot,
                          String(format: "%@: ink reaches %.2f px past the glyph outline, against an "
                                 + "overshoot allowance of %.0f px — the whole-pixel cover the constant "
                                 + "was set with is gone; re-measure it", what, reach,
                                 TextMeasure.glyphRasterOvershoot),
                          file: file, line: line)
        return (escape, reach, declared)
    }

    // MARK: - What is swept

    /// Every face the app's font picker can hand a document, as the descriptor the document stores.
    private static func everyFace() -> [(name: String, descriptor: FontDescriptor)] {
        var out: [(String, FontDescriptor)] = []
        for group in FontLibrary.shared.groups() {
            for family in group.families {
                for face in FontLibrary.shared.faces(inFamily: family, packID: group.packID) {
                    out.append((face.postScriptName, face.descriptor))
                }
            }
        }
        return out
    }

    /// Faces chosen for reaching furthest past their typographic box: swash scripts, italics with
    /// long tails, a chalk face whose edges are ragged, the system face in all four styles, and the
    /// emoji font by way of the system face.
    private static let overhangFaces: [FontDescriptor] = [
        FontDescriptor(familyName: "System", isBold: false, isItalic: false),
        FontDescriptor(familyName: "System", isBold: true, isItalic: true),
        FontDescriptor(familyName: "Zapfino", faceName: "Zapfino"),
        FontDescriptor(familyName: "Snell Roundhand", faceName: "SnellRoundhand-Bold", isBold: true),
        FontDescriptor(familyName: "Savoye LET", faceName: "SavoyeLetPlain"),
        FontDescriptor(familyName: "Times New Roman", faceName: "TimesNewRomanPS-BoldItalicMT",
                       isBold: true, isItalic: true),
        FontDescriptor(familyName: "Georgia", faceName: "Georgia-Italic", isItalic: true),
        FontDescriptor(familyName: "Baskerville", faceName: "Baskerville-SemiBoldItalic", isItalic: true),
        FontDescriptor(familyName: "Chalkduster", faceName: "Chalkduster"),
        FontDescriptor(familyName: "Bradley Hand", faceName: "BradleyHandITCTT-Bold", isBold: true),
        FontDescriptor(familyName: "Party LET", faceName: "PartyLetPlain"),
        FontDescriptor(familyName: "Noteworthy", faceName: "Noteworthy-Bold", isBold: true),
    ]

    /// Strings chosen for the ways glyph ink leaves its line box: descender tails, italic overhang on
    /// the first and last glyph, accented capitals above the ascent, combining marks, emoji, a
    /// trailing space, an empty line in the middle, and a ligature.
    private static let overhangStrings: [(label: String, string: String)] = [
        ("tails", "Qfjy gpq"),
        ("italic f and J", "fJf"),
        ("accented capitals", "ÂÊÑ Ç Ŵ"),
        ("combining marks", "e\u{0301}A\u{0302}n\u{0303}"),
        ("emoji", "😀🎨 ok"),
        ("trailing space", "trailing "),
        ("empty middle line", "first\n\nthird"),
        ("ligatures and swash", "ffi Th Qu"),
    ]

    /// Small enough that a glyph is a few pixels at a quarter resolution, and large enough that a
    /// swash reaches tens of points past its box.
    private static let overhangSizes: [CGFloat] = [12, 40, 120]
    /// Upright, and turned past a right angle so both axes of the box's map are negative.
    private static let overhangRotations: [CGFloat] = [0, 2.3]
    /// Native, the coarsest `RenderResolution` the artist can pick, and a thumbnail-like quarter.
    private static let resolutions: [CGFloat] = [1, 0.5, 0.25]

    private func attach(_ name: String, _ lines: [String]) {
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - The sweeps

    /// **Every face the picker exposes, one overhanging string, upright, native resolution.** The
    /// broad sweep: a face whose declared glyph bounds lie would fail here whatever else passed.
    func testEveryFaceTheAppExposesIsBoundedUpright() {
        let faces = Self.everyFace()
        XCTAssertGreaterThan(faces.count, 50, "the picker exposes \(faces.count) faces — this "
                             + "simulator's font list is not the one the sweep was written against")
        var report: [String] = []
        var worst: (escape: CGFloat, name: String) = (0, "")
        var furthest: (reach: CGFloat, name: String) = (-.infinity, "")
        for face in faces {
            autoreleasepool {
                let recipe = Self.recipe("Qfjy ÂÊÑ", font: face.descriptor, pointSize: 48)
                guard let r = assertInkInsideDeclaredRectangle(recipe, rotation: 0, resolution: 1,
                                                              "\(face.name) 48pt upright") else { return }
                if r.escape > worst.escape { worst = (r.escape, face.name) }
                if r.reach > furthest.reach { furthest = (r.reach, face.name) }
                report.append(String(format: "%@: reach past outline %.2f px, declared %@",
                                     face.name, r.reach, "\(r.declared.integral)"))
            }
        }
        report.insert(String(format: "faces swept: %d; worst escape %.2f px on %@; furthest reach past the "
                             + "outline %.2f px on %@ (a pad p holds iff p > reach - 1)",
                             faces.count, worst.escape, worst.name, furthest.reach, furthest.name), at: 0)
        attach("every face, upright, native", report)
    }

    /// **The overhang faces against the overhang strings, at three sizes, three rotations and two
    /// resolutions.** The reduced arm is rendered first so the slot is standing at the press, which
    /// is the thumbnail path's order and the one that decides the pad's unit.
    func testOverhangStringsAreBoundedAcrossSizesRotationsAndResolutions() {
        var report: [String] = []
        var worst: (escape: CGFloat, what: String) = (0, "")
        var furthest: (reach: CGFloat, what: String) = (-.infinity, "")
        var byResolution: [CGFloat: (reach: CGFloat, what: String)] = [:]
        var cases = 0
        for font in Self.overhangFaces {
            for entry in Self.overhangStrings {
                for size in Self.overhangSizes {
                    for rotation in Self.overhangRotations {
                        for resolution in Self.resolutions {
                            autoreleasepool {
                                let what = "\(font.faceName ?? font.familyName) \(entry.label) \(size)pt "
                                    + "rot \(rotation) res \(resolution)"
                                let recipe = Self.recipe(entry.string, font: font, pointSize: size)
                                guard let r = assertInkInsideDeclaredRectangle(
                                    recipe, rotation: rotation, resolution: resolution, what) else { return }
                                cases += 1
                                if r.escape > worst.escape { worst = (r.escape, what) }
                                if r.reach > furthest.reach { furthest = (r.reach, what) }
                                if r.reach > (byResolution[resolution]?.reach ?? -.infinity) {
                                    byResolution[resolution] = (r.reach, what)
                                }
                                if r.reach > 1 {
                                    report.append(String(format: "%@: reach past outline %.2f px", what, r.reach))
                                }
                            }
                        }
                    }
                }
            }
        }
        report.insert(String(format: "cases: %d; worst escape %.2f px on %@; furthest reach past the outline "
                             + "%.2f px on %@ (a pad p holds iff p > reach - 1)",
                             cases, worst.escape, worst.what, furthest.reach, furthest.what), at: 0)
        for (resolution, entry) in byResolution.sorted(by: { $0.key > $1.key }) {
            report.insert(String(format: "  at resolution %.2f: furthest reach %.2f px on %@",
                                 resolution, entry.reach, entry.what), at: 1)
        }
        attach("overhang sweep", report)
    }

    /// **The two arms the affine map does not cover.** A `.projective` frame that still carries the
    /// `autoSize` bit (only a hand-edited document can — a distort drag clears it — and the bound has
    /// to hold for one anyway) draws through the warp, whose ink is inside the quad's integral
    /// bounding box by construction; a frame with a collapsed `size` and a real bounding box has no
    /// map at all and draws through the bounding-box fallback. Both are answered by the union of the
    /// two, and both are checked here against pixels.
    func testTheWarpAndCollapsedArmsAreBoundedToo() {
        let recipe = Self.recipe("Qfjy ÂÊÑ", font: FontDescriptor(familyName: "Zapfino", faceName: "Zapfino"),
                                 pointSize: 40)
        let font = TextLayout.resolvedFont(for: recipe).font
        let size = TextLayout.autoSize(for: recipe, font: font)

        // A quad with one corner pulled in, which is what the distort handle makes.
        let margin = Self.margin(for: 40)
        let warped = [CGPoint(x: margin, y: margin),
                      CGPoint(x: margin + size.width, y: margin + 18),
                      CGPoint(x: margin + size.width - 30, y: margin + size.height + 12),
                      CGPoint(x: margin, y: margin + size.height)]
        let warpedFrame = TextFrame(size: size, corners: warped, mode: .projective, autoSize: true)
        XCTAssertNil(warpedFrame.affineTransform, "fixture precondition: a distorted quad has no affine map")
        XCTAssertNotNil(warpedFrame.homography, "fixture precondition: a distorted quad has a homography")
        check(VectorTextElement(recipe: recipe, frame: warpedFrame),
              canvasSize: CGSize(width: size.width + 2 * margin, height: size.height + 2 * margin),
              "projective autoSize box")

        // A stored size of zero under real corners — decodable, and the one shape that reaches the
        // bounding-box draw.
        let collapsedFrame = TextFrame(size: .zero,
                                       corners: TextFrame.uprightCorners(origin: CGPoint(x: margin, y: margin),
                                                                         size: size),
                                       mode: .affine, autoSize: true)
        XCTAssertNil(collapsedFrame.affineTransform, "fixture precondition: a zero size has no affine map")
        XCTAssertNil(collapsedFrame.homography, "fixture precondition: a zero size has no homography")
        check(VectorTextElement(recipe: recipe, frame: collapsedFrame),
              canvasSize: CGSize(width: size.width + 2 * margin, height: size.height + 2 * margin),
              "collapsed-size autoSize box")
    }

    private func check(_ element: VectorTextElement, canvasSize: CGSize, _ what: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        for resolution in Self.resolutions {
            let canvas = VectorCanvas(size: canvasSize, elements: [.text(element)])
            let image = resolution >= 1 ? canvas.render() : canvas.render(quality: .full, resolution: resolution)
            let ink = inkBox(image)
            guard let box = ink.box else {
                XCTFail("\(what) at \(resolution): fixture precondition — nothing painted", file: file, line: line)
                continue
            }
            XCTAssertTrue(box.minX > 0 && box.minY > 0 && box.maxX < CGFloat(ink.width)
                          && box.maxY < CGFloat(ink.height),
                          "\(what) at \(resolution): ink touches the border at \(box)", file: file, line: line)
            canvas.restoreElements([], changedInk: nil)
            guard case .region(let declared) = canvas.lastDamage else {
                XCTFail("\(what) at \(resolution): declared \(canvas.lastDamage), not a rectangle",
                        file: file, line: line)
                continue
            }
            let clip = snappedClip(declared, resolution: resolution)
            XCTAssertTrue(clip.contains(box),
                          "\(what) at \(resolution): ink \(box) escapes the declared \(declared) "
                          + "(snapped \(clip))", file: file, line: line)
        }
    }

    // MARK: - The measurement itself

    /// **The rectangle the press declares is the measured outline plus the overshoot, and nothing
    /// else** — pinned so the pad cannot silently become a different formula. At native resolution
    /// the pad is the overshoot itself; with a half-resolution slot standing it is twice that in
    /// canvas points, because the overshoot is a device-pixel figure.
    func testTheDeclaredRectangleIsTheOutlinePaddedForTheLowestStandingResolution() {
        let recipe = Self.recipe("Overhang fjQ", font: .system, pointSize: 64)
        for resolution in Self.resolutions {
            guard let (canvas, element) = Self.fixture(recipe, rotation: 0.3) else { return XCTFail("no fixture") }
            _ = resolution >= 1 ? canvas.render() : canvas.render(quality: .full, resolution: resolution)
            canvas.restoreElements([], changedInk: nil)
            guard case .region(let declared) = canvas.lastDamage else { return XCTFail("not a region") }
            let outline = TextMeasure.glyphOutlineBounds(of: element)
            XCTAssertFalse(outline.isNull, "the string has ink")
            let pad = TextMeasure.glyphRasterOvershoot / resolution
            let expected = outline.insetBy(dx: -pad, dy: -pad)
            XCTAssertEqual(declared.minX, expected.minX, accuracy: 1e-6, "minX at resolution \(resolution)")
            XCTAssertEqual(declared.minY, expected.minY, accuracy: 1e-6, "minY at resolution \(resolution)")
            XCTAssertEqual(declared.maxX, expected.maxX, accuracy: 1e-6, "maxX at resolution \(resolution)")
            XCTAssertEqual(declared.maxY, expected.maxY, accuracy: 1e-6, "maxY at resolution \(resolution)")
        }
    }

    /// **A string of nothing but spaces declares a null rectangle rather than the cel**: the flatten
    /// draws it (the string is not empty) and it paints nowhere, which is what `.null` means. The
    /// operand that says the press *did* run through the text arm is that the picture is blank.
    func testAStringOfSpacesPaintsNowhereAndDeclaresNoRectangle() {
        let recipe = Self.recipe("   ", font: .system, pointSize: 64)
        guard let (canvas, element) = Self.fixture(recipe, rotation: 0) else { return XCTFail("no fixture") }
        XCTAssertNil(inkBox(canvas.render()).box, "spaces paint nothing")
        XCTAssertTrue(TextMeasure.glyphOutlineBounds(of: element).isNull, "spaces have no outline")
        canvas.restoreElements([], changedInk: nil)
        // Nothing arrives and the one departure paints nowhere: the union is null, which the canvas
        // declares as a null region — not `.everything`.
        guard case .region(let declared) = canvas.lastDamage else {
            return XCTFail("a blank departure declared \(canvas.lastDamage)")
        }
        XCTAssertTrue(declared.isNull, "declared \(declared) for a departure that painted nothing")
    }

    /// **`glyphOutlineBounds` is exact about the outline**: the union of every glyph's own path
    /// bounds, at the positions the line puts them, in the same canvas space. This is the claim the
    /// header's "CoreGraphics widens hairlines" paragraph rests on — the pad exists for the raster,
    /// not for the measurement.
    func testTheOutlineBoundsAreTheUnionOfTheGlyphPaths() {
        let recipe = Self.recipe("Qfjy ÂÊÑ", font: FontDescriptor(familyName: "Zapfino", faceName: "Zapfino"),
                                 pointSize: 48)
        guard let (_, element) = Self.fixture(recipe, rotation: 0) else { return XCTFail("no fixture") }
        let measured = TextMeasure.glyphOutlineBounds(of: element)

        let font = TextLayout.resolvedFont(for: recipe).font
        let attributed = TextLayout.attributedString(recipe, font: font)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let laidOut = TextLayout.layout(framesetter, recipe: recipe, font: font, boxSize: element.frame.size)
        let lines = (CTFrameGetLines(laidOut.frame) as? [CTLine]) ?? []
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(laidOut.frame, CFRange(location: 0, length: 0), &origins)
        var union = CGRect.null
        for (index, line) in lines.enumerated() {
            for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let runFont = attributes[kCTFontAttributeName] else { continue }
                let ctFont = runFont as! CTFont
                for i in 0..<count {
                    guard let path = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) else { continue }
                    let b = path.boundingBox
                    guard !b.isNull, !b.isEmpty else { continue }
                    let x = laidOut.rect.minX + origins[index].x + positions[i].x
                    let yUp = laidOut.rect.minY + origins[index].y + positions[i].y
                    union = union.union(CGRect(x: x + b.minX, y: element.frame.size.height - (yUp + b.maxY),
                                               width: b.width, height: b.height))
                }
            }
        }
        let expected = union.offsetBy(dx: element.frame.boundingBox.minX, dy: element.frame.boundingBox.minY)
        XCTAssertEqual(measured.minX, expected.minX, accuracy: 0.01)
        XCTAssertEqual(measured.minY, expected.minY, accuracy: 0.01)
        XCTAssertEqual(measured.maxX, expected.maxX, accuracy: 0.01)
        XCTAssertEqual(measured.maxY, expected.maxY, accuracy: 0.01)
    }
}
