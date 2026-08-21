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
