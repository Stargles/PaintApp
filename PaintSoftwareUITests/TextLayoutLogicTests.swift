import CoreText
import UIKit
import XCTest

/// `TextLayout` — the CoreText half of `ADD_TEXT.md` stage 1. Tracking, line height, line and
/// paragraph spacing, alignment, and wrapping, each asserted against a fixed expectation.
///
/// **What "fixed expectation" means here, because it is the design of the whole file.** The obvious
/// test — "this string in this font at this size is 412.5 points wide" — is a claim about a font
/// file that Apple ships and revises, not about this code, and it fails on the next OS update for a
/// reason nobody can act on. Every assertion below is instead an *identity* that holds whatever the
/// font is:
///
///   * tracking adds exactly `t × (characters − 1)` to a line's width, because `attributedString`
///     applies `.kern` to every character but the last;
///   * every one of the four spacing knobs moves the gap between two baselines by exactly the
///     amount it was changed by, and moves nothing else;
///   * the alignments put a line's leading edge at 0, at `box − width`, and at `(box − width)/2`;
///   * a justified line that is not the last fills the box exactly.
///
/// Those are the properties the settings panel's sliders promise, they are what a bake has to
/// reproduce, and they are checkable to a fraction of a point on any font the device happens to have.
///
/// Headless: `TextLayout`, `TextObject` and `FontLibrary` are UIKit/CoreText only and compile into
/// this target through the project file's "App sources shared with PaintSoftwareUITests" group.
final class TextLayoutLogicTests: XCTestCase {

    /// The system font, which is the one face iOS is guaranteed to have. Nothing below depends on
    /// its metrics — see the class comment.
    private func font(_ size: CGFloat = 48) -> UIFont {
        SystemFontProvider.systemFont(size: size, bold: false, italic: false)
    }

    private func recipe(_ string: String, _ typography: Typography = Typography()) -> TextRecipe {
        TextRecipe(string: string, typography: typography)
    }

    /// Gap between two consecutive baselines, in points. The quantity every spacing knob acts on,
    /// and the one that can be asserted exactly.
    private func baselineGap(_ metrics: TextLayout.Metrics, _ first: Int = 0) -> CGFloat {
        guard metrics.lines.count > first + 1 else { return .nan }
        return metrics.lines[first + 1].baselineOrigin.y - metrics.lines[first].baselineOrigin.y
    }

    // MARK: - The empty case

    func testAnEmptyStringMeasuresToNothingAtAll() {
        let metrics = TextLayout.measure(recipe(""), font: font())
        XCTAssertEqual(metrics.size, .zero)
        XCTAssertTrue(metrics.lines.isEmpty,
                      "An empty box bakes nothing. A one-line-tall empty layout would give the bake "
                      + "a destination rectangle for zero glyphs.")
    }

    // MARK: - Tracking

    /// The exact claim `attributedString` makes: `.kern` on every character but the last, so a line
    /// of `n` characters grows by `t × (n − 1)`.
    func testTrackingWidensALineByExactlyOneStepPerGapBetweenCharacters() {
        let string = "AAAAAAAA"                       // 8 characters, 7 gaps
        let gaps = CGFloat(string.count - 1)
        let plain = TextLayout.measure(recipe(string), font: font()).size.width
        for step in [CGFloat(2), 5, 12] {
            let tracked = TextLayout.measure(recipe(string, Typography(tracking: step)), font: font()).size.width
            XCTAssertEqual(tracked - plain, step * gaps, accuracy: 0.01,
                           "Tracking of \(step) over \(Int(gaps)) gaps must widen the line by exactly "
                           + "\(step * gaps). A different multiple means `.kern` reached the wrong range "
                           + "— applying it to the final character too leaves a trailing gap that "
                           + "centred and right-aligned text then lays out around.")
        }
    }

    func testNegativeTrackingTightensByTheSameRule() {
        let string = "MMMM"
        let plain = TextLayout.measure(recipe(string), font: font()).size.width
        let tight = TextLayout.measure(recipe(string, Typography(tracking: -3)), font: font()).size.width
        XCTAssertEqual(plain - tight, 3 * CGFloat(string.count - 1), accuracy: 0.01)
    }

    func testTrackingDoesNotChangeTheHeightOfASingleLine() {
        let plain = TextLayout.measure(recipe("Hxyg"), font: font()).size.height
        let tracked = TextLayout.measure(recipe("Hxyg", Typography(tracking: 30)), font: font()).size.height
        XCTAssertEqual(plain, tracked, accuracy: 0.01,
                       "Tracking is horizontal. A height that moved means it reached the paragraph style.")
    }

    // MARK: - Line height and line spacing

    /// `lineHeightMultiple` scales the natural line height, so the baseline-to-baseline distance
    /// scales with it. Asserted as a ratio, which is what makes it a claim about the multiplier
    /// rather than about the font's own leading.
    func testLineHeightMultipleScalesTheDistanceBetweenBaselines() {
        let text = "one\ntwo\nthree"
        let single = baselineGap(TextLayout.measure(recipe(text), font: font()))
        XCTAssertGreaterThan(single, 0)
        for multiple in [CGFloat(1.5), 2, 2.5] {
            let scaled = baselineGap(TextLayout.measure(
                recipe(text, Typography(lineHeightMultiple: multiple)), font: font()))
            XCTAssertEqual(scaled, single * multiple, accuracy: 0.5,
                           "A line-height multiple of \(multiple) must put the baselines \(multiple)× "
                           + "as far apart. This is the slider's whole meaning.")
        }
    }

    /// `lineSpacing` is *extra points* between lines, on top of whatever the multiple produced — so
    /// it adds, and adds exactly.
    func testLineSpacingAddsItsOwnPointsBetweenBaselines() {
        let text = "one\ntwo\nthree"
        let base = baselineGap(TextLayout.measure(recipe(text), font: font()))
        for extra in [CGFloat(6), 18, 40] {
            let spaced = baselineGap(TextLayout.measure(
                recipe(text, Typography(lineSpacing: extra)), font: font()))
            XCTAssertEqual(spaced - base, extra, accuracy: 0.5,
                           "Line spacing of \(extra) must open the baselines by exactly \(extra).")
        }
    }

    func testLineHeightAndLineSpacingCompose() {
        let text = "one\ntwo"
        let both = baselineGap(TextLayout.measure(
            recipe(text, Typography(lineHeightMultiple: 2, lineSpacing: 10)), font: font()))
        let multipleOnly = baselineGap(TextLayout.measure(
            recipe(text, Typography(lineHeightMultiple: 2)), font: font()))
        XCTAssertEqual(both - multipleOnly, 10, accuracy: 0.5,
                       "The two knobs are independent: spacing adds after the multiple has scaled.")
    }

    func testTallerLinesMakeATallerLayout() {
        let text = "one\ntwo\nthree"
        let short = TextLayout.measure(recipe(text), font: font()).size.height
        let tall = TextLayout.measure(recipe(text, Typography(lineHeightMultiple: 2)), font: font()).size.height
        XCTAssertGreaterThan(tall, short,
                             "The measured size is what `autoSize` writes into the box. If it does not "
                             + "grow with the line height, raising the slider pushes text out of its "
                             + "own outline.")
    }

    // MARK: - Paragraph spacing

    /// The knob that distinguishes a *paragraph* break from a line break. It must open the gap after
    /// a newline and leave every other gap alone — which is the half a "did the height grow" test
    /// would not catch.
    func testParagraphSpacingOpensTheGapAfterANewlineAndNoOther() {
        // Two paragraphs, the first of them long enough to wrap. The line index the newline falls on
        // is found rather than assumed: how many lines a fixture wraps into is exactly the kind of
        // font-dependent number this file refuses to hard-code (see the class comment).
        let text = "aaa aaa aaa aaa aaa aaa\nbbb"
        let width: CGFloat = 150
        let newline = (text as NSString).range(of: "\n").location

        let plain = TextLayout.measure(recipe(text), font: font(28), maxWidth: width)
        let spaced = TextLayout.measure(recipe(text, Typography(paragraphSpacing: 30)),
                                        font: font(28), maxWidth: width)
        XCTAssertEqual(spaced.lines.count, plain.lines.count,
                       "Paragraph spacing moves lines apart; it does not re-break them.")

        guard let breakIndex = plain.lines.firstIndex(where: { NSLocationInRange(newline, $0.range) }),
              breakIndex > 0 else {
            return XCTFail("The fixture needs the first paragraph to wrap before the newline; it "
                           + "produced \(plain.lines.count) lines with the break at "
                           + "\(String(describing: plain.lines.firstIndex { NSLocationInRange(newline, $0.range) })).")
        }

        XCTAssertEqual(baselineGap(spaced, 0), baselineGap(plain, 0), accuracy: 0.5,
                       "A wrap inside a paragraph is not a paragraph break, so paragraph spacing "
                       + "must not touch it.")
        XCTAssertEqual(baselineGap(spaced, breakIndex) - baselineGap(plain, breakIndex), 30,
                       accuracy: 0.5,
                       "The gap across the newline must open by exactly the paragraph spacing.")
    }

    // MARK: - Alignment

    /// Each alignment puts a short line's leading edge at a stated place inside a wide box. The
    /// arithmetic is the alignment's definition, and it is what the segmented picker promises.
    func testEachAlignmentPlacesALineWhereItsNameSays() {
        let box: CGFloat = 600
        let cases: [(Typography.Alignment, (CGFloat) -> CGFloat)] = [
            (.left, { _ in 0 }),
            (.right, { width in box - width }),
            (.center, { width in (box - width) / 2 })
        ]
        for (alignment, expected) in cases {
            let metrics = TextLayout.measure(recipe("short", Typography(alignment: alignment)),
                                             font: font(), maxWidth: box)
            let line = try? XCTUnwrap(metrics.lines.first)
            guard let line else { return }
            XCTAssertLessThan(line.width, box, "The fixture must be a line narrower than the box.")
            XCTAssertEqual(line.baselineOrigin.x, expected(line.width), accuracy: 0.5,
                           "\(alignment.displayName) alignment put the line at \(line.baselineOrigin.x) "
                           + "in a \(box)-wide box; it belongs at \(expected(line.width)).")
        }
    }

    /// Justified is the one alignment that changes a line's *width* rather than its position: every
    /// line but the last is stretched to fill the box.
    func testJustifiedLinesFillTheBoxExceptTheLast() {
        let box: CGFloat = 300
        let metrics = TextLayout.measure(
            recipe("the quick brown fox jumped over the lazy dog", Typography(alignment: .justified)),
            font: font(28), maxWidth: box)
        XCTAssertGreaterThanOrEqual(metrics.lines.count, 3, "The fixture needs several lines.")
        for line in metrics.lines.dropLast() {
            XCTAssertEqual(line.width, box, accuracy: 1.0,
                           "A justified line other than the last fills its box.")
            XCTAssertEqual(line.baselineOrigin.x, 0, accuracy: 0.5)
        }
        XCTAssertLessThan(metrics.lines.last!.width, box,
                          "The last line of a justified paragraph is not stretched — that is what "
                          + "keeps a two-word final line from becoming a row of islands.")
    }

    /// Alignment is a property of the *document*, so `.natural` — which resolves against the user
    /// interface language — is deliberately absent from the enum. Stated as a test because an enum
    /// case is the easiest thing in the world to add without thinking about it.
    func testAlignmentOffersExactlyTheFourDocumentAlignments() {
        XCTAssertEqual(Set(Typography.Alignment.allCases.map(\.rawValue)),
                       ["left", "center", "right", "justified"],
                       "`.natural` must not appear here: it resolves against the device's UI "
                       + "language, so the same document would lay out differently on two iPads.")
    }

    // MARK: - Wrapping

    func testAWideBoxKeepsOneLineAndANarrowOneWrapsIt() {
        let text = "the quick brown fox jumped over the lazy dog"
        let wide = TextLayout.measure(recipe(text), font: font(24), maxWidth: 4000)
        XCTAssertEqual(wide.lines.count, 1)

        let narrow = TextLayout.measure(recipe(text), font: font(24), maxWidth: 200)
        XCTAssertGreaterThan(narrow.lines.count, 1)
        for line in narrow.lines {
            XCTAssertLessThanOrEqual(line.width, 200 + 0.5,
                                     "No line may exceed the box it was wrapped into — that is the "
                                     + "whole of what wrapping is.")
        }
    }

    func testWrappingSplitsAtWordsAndKeepsEveryCharacter() {
        let text = "alpha beta gamma delta"
        let metrics = TextLayout.measure(recipe(text), font: font(30), maxWidth: 180)
        XCTAssertGreaterThan(metrics.lines.count, 1)
        let covered = metrics.lines.reduce(0) { $0 + $1.range.length }
        XCTAssertEqual(covered, (text as NSString).length,
                       "Every character belongs to exactly one line. A short count is a line CoreText "
                       + "dropped because the frame path was a fraction too short — the bug the +1 in "
                       + "`measure` exists to close.")
        XCTAssertEqual(metrics.lines.first?.range.location, 0)
    }

    func testAnUnconstrainedMeasurementNeverWraps() {
        let text = String(repeating: "wide ", count: 40)
        let metrics = TextLayout.measure(recipe(text), font: font(), maxWidth: nil)
        XCTAssertEqual(metrics.lines.count, 1,
                       "A point-text box grows to the right rather than wrapping — `TextFrame.autoSize`.")
        XCTAssertGreaterThan(metrics.size.width, 1000)
    }

    func testExplicitNewlinesAlwaysBreakEvenInAWideBox() {
        let metrics = TextLayout.measure(recipe("a\nb\nc"), font: font(), maxWidth: 4000)
        XCTAssertEqual(metrics.lines.count, 3)
    }

    // MARK: - Auto-size

    /// `autoSize` grows the box to exactly what the string measures.
    func testAutoSizeGrowsToFitAShortString() {
        let size = TextLayout.autoSize(for: recipe("Title"), font: font())
        let measured = TextLayout.measure(recipe("Title"), font: font()).size
        XCTAssertEqual(size.width, measured.width, accuracy: 0.5)
        XCTAssertGreaterThan(size.height, 0)
    }

    /// **Stage 4 removed Stage 1's cap at the canvas's right edge**, and this is the test that used
    /// to assert it. Stage 1 wrapped a runaway box there because with no handles there was no way to
    /// drag one back; stage 4 builds the handles, so the reason expired.
    ///
    /// Asserted as an identity rather than as a width: the box is *one line tall* and *as wide as
    /// the unwrapped measurement*, whatever that measurement happens to be in this year's system
    /// font. A cap of any kind would show up as a second line.
    func testAutoSizeGrowsPastTheCanvasEdgeNowThatHandlesExist() {
        let long = String(repeating: "wide ", count: 60)
        let size = TextLayout.autoSize(for: recipe(long), font: font(40))
        let unwrapped = TextLayout.measure(recipe(long), font: font(40), maxWidth: nil)
        XCTAssertEqual(unwrapped.lines.count, 1, "Fixture check — the string has no newline to break on.")
        XCTAssertEqual(size.width, unwrapped.size.width, accuracy: 0.5,
                       "A point-text box grows rightward forever; stage 4's handles are how it comes back.")
        XCTAssertGreaterThan(size.width, 2048,
                             "Fixture check — the string is wider than any canvas this app defaults to, "
                             + "so a surviving canvas-edge cap would fail the assertion above.")
        XCTAssertEqual(size.height, unwrapped.size.height, accuracy: 0.5,
                       "Having grown rather than wrapped, it is still one line tall.")
    }

    func testAnEmptyBoxIsStillTallEnoughToShowACaret() {
        let size = TextLayout.autoSize(for: recipe(""), font: font(60))
        XCTAssertGreaterThanOrEqual(size.height, font(60).lineHeight - 0.5,
                                    "A box with nothing typed into it yet has to be tall enough to "
                                    + "hold the caret, or the artist places one and sees a hairline.")
        XCTAssertGreaterThanOrEqual(size.width, TextLayout.minimumBoxWidth)
    }

    /// The cap that replaced the canvas-edge one, and the reason removing it is safe: the *live*
    /// cost of a very wide box is its glyph bitmap, and `renderBox` is asked for that bitmap in
    /// texels rather than in points. A scale below 1 has to be honoured or the caller cannot express
    /// the cap at all — it was floored at 1 until stage 4, which was invisible only while `autoSize`
    /// bounded the box in points.
    func testRenderBoxHonoursABackingScaleBelowOne() throws {
        let box = CGSize(width: 800, height: 200)
        let image = try XCTUnwrap(TextLayout.renderBox(recipe: recipe("Title"), boxSize: box,
                                                       clip: false, scale: 0.25))
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cg.width, 200, "800 points at 0.25 backing pixels per point.")
        XCTAssertEqual(cg.height, 50)
    }

    // MARK: - A box shorter than its own text

    /// The pre-fix drawing path, spelled out so the tests below can ask what it did: CoreText laid
    /// out in the box's own rectangle, which is what `draw` handed it until the blackout was found.
    /// Kept here rather than reached for in `TextLayout`, because what it characterises is the *old*
    /// behaviour and the point is that the shipping code no longer does it.
    private func linesInTheBoxsOwnRectangle(_ recipe: TextRecipe, _ font: UIFont,
                                            _ boxSize: CGSize) -> Int {
        let framesetter = CTFramesetterCreateWithAttributedString(
            TextLayout.attributedString(recipe, font: font))
        let path = CGPath(rect: CGRect(origin: .zero, size: boxSize), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return CFArrayGetCount(CTFrameGetLines(frame))
    }

    private func layoutRect(_ recipe: TextRecipe, _ font: UIFont, _ boxSize: CGSize) -> CGRect {
        let framesetter = CTFramesetterCreateWithAttributedString(
            TextLayout.attributedString(recipe, font: font))
        return TextLayout.layout(framesetter, recipe: recipe, font: font, boxSize: boxSize).rect
    }

    /// The rows of a rendered box that carry ink, top-down in the image's own coordinates. Nil when
    /// the box drew nothing whatsoever — which is the bug, so it is worth its own answer rather than
    /// an empty range.
    private func inkRows(_ image: UIImage) -> ClosedRange<Int>? {
        guard let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return nil }
        var first = Int.max, last = -1
        for y in 0..<cg.height {
            let inked = (0..<cg.width).contains { bytes[(y * cg.width + $0) * 4 + 3] > 8 }
            if inked { first = min(first, y); last = max(last, y) }
        }
        return last >= 0 ? first...last : nil
    }

    /// **`firstLineLayoutHeight` is CoreText's own threshold, not a guess at it.** One point over it
    /// the line survives; one point under it CoreText drops the line entirely and the box draws
    /// nothing at all — which is the whole mechanism of the reported blackout.
    ///
    /// Asserted as that identity rather than as a number, across the two typography knobs that make
    /// the raw font metric the wrong answer: `lineHeightMultiple` and `lineSpacing` reach 3× and
    /// 80 pt, so a floor of `font.lineHeight` would be short by a factor of three at the top of the
    /// range. The last assertion is what says so out loud.
    func testTheFirstLineHeightIsTheHeightCoreTextItselfStopsDroppingTheLineAt() {
        let cases: [(String, Typography)] = [
            ("default", Typography()),
            ("tall lines", Typography(lineHeightMultiple: 3, lineSpacing: 60)),
            ("tight lines", Typography(lineHeightMultiple: 0.5)),
            ("tracked", Typography(tracking: 20)),
        ]
        for (name, typography) in cases {
            let text = recipe("Hxyg", typography)
            let needed = TextLayout.firstLineLayoutHeight(text, font: font(64), maxWidth: 400)
            XCTAssertEqual(linesInTheBoxsOwnRectangle(text, font(64), CGSize(width: 400, height: needed)), 1,
                           "\(name): a box as tall as `firstLineLayoutHeight` must hold the first line.")
            XCTAssertEqual(linesInTheBoxsOwnRectangle(text, font(64), CGSize(width: 400, height: needed - 2)), 0,
                           "\(name): two points under it, CoreText drops the line — and a frame with "
                           + "no lines in it draws nothing at all. That is the blackout.")
        }
        let tall = TextLayout.firstLineLayoutHeight(recipe("Hxyg", Typography(lineHeightMultiple: 3)),
                                                    font: font(64), maxWidth: 400)
        XCTAssertGreaterThan(tall, font(64).lineHeight * 2,
                             "At a 3× line height the first line needs far more room than the font's "
                             + "own metric reports. `font.lineHeight` is not the floor, which is why "
                             + "this is measured through `measure` instead.")
    }

    /// **The no-op half, made structural rather than hoped for.** A box that can hold its text is
    /// laid out in exactly the rectangle stage 1 laid it out in, so the glyphs it produces are the
    /// same bytes to the last one — there is no second code path for it to drift down.
    func testABoxThatAlreadyFitsIsStillLaidOutInItsOwnRectangle() {
        let text = recipe("Hello world")
        for box in [CGSize(width: 400, height: 300), CGSize(width: 900, height: 90),
                    CGSize(width: 120, height: 2000)] {
            XCTAssertEqual(layoutRect(text, font(64), box), CGRect(origin: .zero, size: box),
                           "A box that fits must be handed CoreText unchanged.")
        }
    }

    /// The owner's report: *"it is invisible when the box is too small for the text"*. A box shorter
    /// than one line of its own text used to produce a CoreText frame with zero lines in it.
    func testABoxTooShortForItsFirstLineIsLaidOutTallerAndKeepsTheLine() {
        let text = recipe("Hello world")
        let needed = TextLayout.firstLineLayoutHeight(text, font: font(64), maxWidth: 400)
        let box = CGSize(width: 400, height: TextFrame.minimumExtent)
        XCTAssertEqual(linesInTheBoxsOwnRectangle(text, font(64), box), 0,
                       "Fixture check — the old path really does drop everything at this size, so "
                       + "the assertions below are about the fix and not about a box that was fine.")
        let rect = layoutRect(text, font(64), box)
        XCTAssertEqual(rect.height, needed, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, box.height, accuracy: 0.001,
                       "The taller rectangle shares the box's TOP edge — the context is y-up here, so "
                       + "its `maxY` is the top. Anchored at the origin instead, the surplus would "
                       + "hang above the box and the clip would leave a sliver of glyph bottoms.")
    }

    /// **Shortening a box crops what it draws; it does not blank it and it does not move it.**
    ///
    /// The sharpest form of the whole fix, and font-independent: the short box's pixels are the tall
    /// box's top rows, byte for byte. A blackout fails it (no ink), and so does the naive fix that
    /// anchors the taller layout rectangle at the origin (ink, in the wrong place).
    func testShorteningABoxCropsItsRenderRatherThanBlankingIt() throws {
        let text = recipe("Hello world")
        let width: CGFloat = 500
        let needed = TextLayout.firstLineLayoutHeight(text, font: font(64), maxWidth: width)
        let shortHeight = (needed / 2).rounded(.down)

        let tall = try XCTUnwrap(TextLayout.renderBox(recipe: text,
                                                      boxSize: CGSize(width: width, height: needed * 2),
                                                      clip: true, scale: 1))
        let short = try XCTUnwrap(TextLayout.renderBox(recipe: text,
                                                       boxSize: CGSize(width: width, height: shortHeight),
                                                       clip: true, scale: 1))
        let tallBytes = try XCTUnwrap(CanvasFixture.rgbaBytes(XCTUnwrap(tall.cgImage)))
        let shortBytes = try XCTUnwrap(CanvasFixture.rgbaBytes(XCTUnwrap(short.cgImage)))
        let shortImage = try XCTUnwrap(short.cgImage)

        XCTAssertNotNil(inkRows(short),
                        "A box half a line tall drew nothing at all — the blackout the owner reported.")
        XCTAssertEqual(inkRows(short)?.lowerBound, inkRows(tall)?.lowerBound,
                       "The glyphs must start on the same row they would in a box that fits. A row of "
                       + "0 here is the origin-anchored fix showing glyph bottoms instead of tops.")
        let rowBytes = shortImage.width * 4
        for row in 0..<shortImage.height {
            let start = row * rowBytes
            XCTAssertEqual(Array(shortBytes[start..<(start + rowBytes)]),
                           Array(tallBytes[start..<(start + rowBytes)]),
                           "Row \(row) of the short box differs from row \(row) of the tall one. "
                           + "Shrinking the box may only take rows away.")
        }
    }

    /// The live overlay, the raster bake and the vector flatten are three destinations for one
    /// rasterizer (`TextLayout.draw`), so one fix covers all three — this is the pin on that, taken
    /// at the one seam every one of them crosses.
    func testTheSameShortBoxDrawsInkThroughTheCanvasSizedBakeToo() throws {
        var frame = TextFrame(origin: CGPoint(x: 20, y: 20),
                              size: CGSize(width: 400, height: TextFrame.minimumExtent))
        frame.autoSize = false
        let image = try XCTUnwrap(TextLayout.render(recipe: recipe("Hello world"), frame: frame,
                                                    canvasSize: CGSize(width: 600, height: 300)))
        XCTAssertNotNil(inkRows(image),
                        "The bake goes through the same `draw`, so it blanked for the same reason.")
    }

    // MARK: - Resolution

    func testAResolvedFontCarriesTheRecipesPointSize() {
        let resolution = TextLayout.resolvedFont(for: recipe("x", Typography(pointSize: 137)))
        XCTAssertEqual(resolution.font.pointSize, 137)
    }

    func testAnOutOfRangePointSizeIsClampedBeforeItReachesTheFont() {
        let resolution = TextLayout.resolvedFont(for: recipe("x", Typography(pointSize: 1_000_000)))
        XCTAssertEqual(resolution.font.pointSize, Typography.pointSizeRange.upperBound,
                       "A hand-edited document must not be able to ask CoreText for a million-point "
                       + "font — the layout it produces is measured in screens.")
    }
}
