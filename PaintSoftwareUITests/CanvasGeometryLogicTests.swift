import XCTest
import UIKit
import CoreGraphics

/// TODO.md item (13): canvas padding shares one 16k budget, and the base maximum rises.
///
/// `CanvasManager.canvasPaddingRange` is a pure function of the *live* canvas (`canvasSize` and the
/// padding already applied), so this tier reaches it directly — no simulator, no view.
///
/// Pinned here rather than left to be re-derived: `canvasSize` already **includes** padding
/// (`CanvasManager.swift`'s own doc comment, `ProjectManifest.canvasWidth`/`canvasHeight`), so the
/// budget is `canvasSize <= CanvasManager.maxCanvasExtent` and the formula's second operand must be
/// the *artwork* extent — `canvasSize - 2 * canvasPadding` — not `canvasSize` itself. Using
/// `canvasSize` there would subtract the padding already on the canvas a second time, and
/// `testCanvasPaddingRangeDoesNotDoubleCountExistingPadding` below is built to catch exactly that
/// mistake: it gives a different (and wrong) answer under the double-subtraction reading than under
/// the correct one.
final class CanvasGeometryLogicTests: XCTestCase {

    // MARK: - The named constants

    /// **Superseded 2026-09-07 by TODO.md item (31).** The signed 16-bit quarter-pixel sample
    /// coordinate (TODO.md item (8)) still addresses -8192.0...+8191.75 — a span of 16383.75 pt, not
    /// 16384 — so 16383 remains the *format's* ceiling. `SampleCodingLogicTests` still pins that,
    /// reading the live constant (`testAMaximumCanvasEncodesBothEdgesAndOnePointWiderDoesNot`). It
    /// is no longer `maxCanvasExtent`'s value: a 16383² canvas crashes on a single brushstroke on the
    /// owner's 3 GB iPad, so the bound moved from a format question to a memory one.
    func testMaxCanvasExtentIsInferredFromA3GBDeviceBudgetNotSixteenThreeEightyThree() {
        XCTAssertEqual(CanvasManager.maxCanvasExtent, 4200,
                       "INFERRED — PERFORMANCE.md §15 has the derivation and the open device check")
    }

    func testCanvasPaddingBaseUpperBoundRoseFromFiveTwelveToTenTwentyFour() {
        XCTAssertEqual(CanvasManager.canvasPaddingBaseUpperBound, 1024)
    }

    // MARK: - The arithmetic behind the memory-driven cap (TODO.md item (31))

    /// **Reproduces PERFORMANCE.md §15's derivation as an assertion, so the two cannot drift apart.**
    /// Every figure below is either MEASURED (cited to where) or INFERRED (this derivation itself,
    /// and labelled as such in both places) — PERFORMANCE.md §15 has the full working, the
    /// sensitivity table across less/more conservative variants, and the open device check that
    /// would confirm or correct the constant this pins.
    func testTheChosenCapFitsAConservativeThreeGBBudgetAndTheOldOneDidNot() {
        // MEASURED, PERFORMANCE.md §9, owner's iPad 9 (`iPad12,1`, 3 GB), 2026-09-02:
        // `os_proc_available_memory()` at rest, i.e. before any document is even open.
        let availableAtRestBytes = 1837.0 * 1024 * 1024

        // INFERRED margin: reserved for whatever is already resident by the time a real stroke
        // happens — the document's own undo history, UIKit, the layer content itself — since 1837
        // MiB was measured with nothing open at all. Half is a round, deliberately generous margin
        // and not itself a measurement, which is exactly why this whole test is INFERRED.
        let marginReserve = 0.5

        // The sandwich compositor's three canvas-sized RGBA buffers (TODO.md item (31)'s own figure,
        // cross-checked below against `SandwichRecipe`/`Compositor.swift`), plus the one more
        // `RasterLayerTexture.ensureContext` opens for the layer actually being drawn on when a
        // stroke commits — BUGS.md's memory-allocation audit, item 2: "committing one still opens
        // the cel's canvas-sized CGContext... which is the artwork's own storage and is as
        // unbudgeted as everything else here."
        let canvasSizedBuffersOnAStroke = 4.0

        // `CompositorBudget.hasHeadroom` already prices a canvas-sized texture at twice its raw byte
        // count — the readback `CGImage` plus the Core Animation copy, "none of which is freed
        // before the next composite starts" (`Compositor.swift`'s own doc comment on that function).
        // Applied here by analogy, because the path that actually composites a plain document's
        // sandwich has no budget of its own to read that multiplier from: `CompositorBudget.hasHeadroom`
        // has exactly two call sites, `MetalCompositor.swift` and `MetalFillEngine.swift`, and
        // `[RenderNode].prefersGPUCompositing` is false under four layers, so a plain few-layer
        // document's live sandwich rebuild runs on `CoreGraphicsCompositor`, unguarded, every time.
        let realismFactor = 2.0

        func bytesNeeded(atExtent extent: Double) -> Double {
            canvasSizedBuffersOnAStroke * realismFactor * extent * extent * 4 // 4 bytes/px, RGBA8
        }

        let budgetBytes = availableAtRestBytes * marginReserve

        XCTAssertLessThan(bytesNeeded(atExtent: Double(CanvasManager.maxCanvasExtent)), budgetBytes,
                          "the chosen cap should fit comfortably inside the conservative budget")

        XCTAssertGreaterThan(bytesNeeded(atExtent: 16383), budgetBytes,
                            "16383 is exactly the value this item retired because it does not fit — "
                            + "if this ever passed, the arithmetic would no longer explain the crash")

        // Cross-check against TODO.md item (31)'s own headline figure for the sandwich alone, with
        // no realism factor and no fourth buffer: "one 16383² RGBA texture is 1.07 GB; the
        // compositor's sandwich needs three, so 3.22 GB."
        let threeBuffersAtOldLimit = 3.0 * 16383.0 * 16383.0 * 4.0
        XCTAssertEqual(threeBuffersAtOldLimit / 1_000_000_000, 3.22, accuracy: 0.01,
                      "TODO.md item (31)'s own figure for the sandwich alone at the old 16383 limit")
    }

    // MARK: - The range at an ordinary canvas

    func testCanvasPaddingRangeOnOrdinaryCanvasIsTheBaseTenTwentyFour() {
        // The owner's own working size (PERFORMANCE.md §1), nowhere near the 16k budget, so the base
        // upper bound applies unclamped.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 2048, height: 1024)
        manager.canvasPadding = 0

        XCTAssertEqual(manager.canvasPaddingRange, 0...1024)
    }

    func testCanvasPaddingRangeAtASquareOrdinaryCanvasIsAlsoTheBase() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 1024, height: 1024)
        manager.canvasPadding = 0

        // (4200 - 1024) / 2 = 1588, above the 1024 base, so the base wins. (4200×4200 is now the
        // *exact*-limit fixture below, not "comfortably under" — see the note there.)
        XCTAssertEqual(manager.canvasPaddingRange, 0...1024)
    }

    // MARK: - The range shrinking as the canvas approaches the limit

    func testCanvasPaddingRangeNearTheLimitShrinksBelowTheBase() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 3700, height: 3700)
        manager.canvasPadding = 0

        // (4200 - 3700) / 2 = 250, below the 1024 base, so the budget wins.
        XCTAssertEqual(manager.canvasPaddingRange, 0...250)
    }

    func testCanvasPaddingRangeAtTheExactLimitIsZero() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 4200, height: 4200)
        manager.canvasPadding = 0

        // No room left at all: the artwork already fills the whole 4200 budget.
        XCTAssertEqual(manager.canvasPaddingRange, 0...0)
    }

    func testCanvasPaddingRangeNeverGoesNegativeBeyondTheLimit() {
        // Nothing in the app can put a canvas past `maxCanvasExtent` today, but the formula itself
        // must not produce an invalid (upper < lower) range if it ever did — a `ClosedRange` traps on
        // construction, and a trap here is a crash on opening the Actions menu. 20000 was chosen to
        // sit past the *old* 16383 bound as well as the current 4200 one, so this probe still means
        // "grossly past the limit, however the limit ever moves" rather than merely past today's.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 20000, height: 20000)
        manager.canvasPadding = 0

        XCTAssertEqual(manager.canvasPaddingRange, 0...0)
    }

    // MARK: - `canvasSize` already includes padding — the single easiest thing to get wrong here

    func testCanvasPaddingRangeDoesNotDoubleCountExistingPadding() {
        // canvasSize is at the exact limit, but 500 of each dimension is padding already applied.
        // The artwork itself is only 4200 - 2*500 = 3200, so there is exactly 500 pt of room left on
        // each side before the *canvas* (artwork + padding) would exceed 4200 — i.e. the upper bound
        // should come out to the same 500 that is already applied, not 0.
        //
        // A wrong implementation that reads `canvasSize` as the artwork extent (double-subtracting
        // the padding already on the canvas) would compute (4200 - 4200) / 2 = 0 instead.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 4200, height: 4200)
        manager.canvasPadding = 500

        XCTAssertEqual(manager.canvasPaddingRange, 0...500,
                       "canvasSize already includes the existing padding; the budget must be computed "
                       + "against the artwork extent (canvasSize - 2*canvasPadding), not canvasSize itself")
    }

    func testCanvasPaddingRangeUsesTheLargerDimensionOnANonSquareCanvas() {
        // setCanvasPadding grows both dimensions by the same delta, so a non-square canvas is bounded
        // by whichever dimension is closer to the limit — here, height.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 2048, height: 3900)
        manager.canvasPadding = 0

        // (4200 - 3900) / 2 = 150, driven by height even though width has plenty of room.
        XCTAssertEqual(manager.canvasPaddingRange, 0...150)
    }

    // MARK: - No canvas yet

    func testCanvasPaddingRangeWithNoCanvasFallsBackToTheBase() {
        let manager = CanvasManager()
        XCTAssertNil(manager.canvasSize, "fixture precondition")

        XCTAssertEqual(manager.canvasPaddingRange, 0...CanvasManager.canvasPaddingBaseUpperBound)
    }

    // MARK: - setCanvasPadding actually clamps to the live range, not the old flat 512

    func testSetCanvasPaddingClampsToTheRaisedBaseOnAnOrdinaryCanvas() {
        // No layers — `setCanvasPadding`'s per-cel resize loop is simply empty, isolating the clamp
        // arithmetic under test from the (already covered elsewhere) raster-resize path.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 2048, height: 1024)

        manager.setCanvasPadding(5000)

        XCTAssertEqual(manager.canvasPadding, 1024, "clamped to the new 1024 base, not the old 512")
    }

    func testSetCanvasPaddingClampsToTheShrunkenBudgetNearTheLimit() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 3701, height: 3701)

        manager.setCanvasPadding(5000)

        // (4200 - 3701) / 2 = 249.5. `setCanvasPadding` rounds the clamped value (load-bearing for
        // backend parity — see its own doc comment), so the range's 249.5 upper bound becomes 250
        // here, not 249.5 itself.
        XCTAssertEqual(manager.canvasPadding, 250, "clamped to the budget (rounded), not the 1024 base")
    }

    // MARK: - "Defined once in the code"

    /// Scans the app's own source (not the test target) for stray literal spellings of whatever
    /// `maxCanvasExtent` currently is. `CanvasManager.maxCanvasExtent`'s declaration is the one
    /// permitted occurrence; every other reader — `CanvasSizePickerView.maxDimension` included —
    /// must read the constant rather than spelling the number again, or a future change to the bound
    /// silently misses one of them.
    ///
    /// **Built from the live constant, not a hardcoded string, since TODO.md item (31).** The test
    /// used to spell "16383" itself, which is exactly the "silently misses it" failure this test
    /// exists to catch, one level up: item (31) changed the bound and a test still asserting the
    /// *old* number would have kept passing throughout — 16383 has nothing left to be the only
    /// spelling of. Reading `CanvasManager.maxCanvasExtent` here means the next change needs no edit
    /// to this file either.
    ///
    /// **And this test caught its own first answer.** Item (31)'s first pick was 4096, and this test
    /// went red at ten occurrences, not one: `resizeUndoCostBytes`, `TextLayout.maximumWarpTexels`,
    /// `PixelOps.maximumFloatingWarpTexels` and six more each land on 4096 independently, because it
    /// is this codebase's ordinary texture-size ceiling and has nothing to do with the canvas bound.
    /// 4200 (`CanvasManager.swift`'s own doc comment carries the full note) keeps the same derivation
    /// and margin without colliding with any of them — proof this scan does real work rather than
    /// passing by construction, found by running it rather than by reasoning about it in advance.
    func testMaxCanvasExtentIsTheOnlySpellingOfItsOwnValueInAppSource() {
        let literal = String(Int(CanvasManager.maxCanvasExtent))
        let occurrences = literalOccurrences(of: literal)

        XCTAssertEqual(occurrences.count, 1,
                       "expected exactly one literal spelling of \(literal) (CanvasManager.maxCanvasExtent's "
                       + "own declaration); found: \(occurrences)")
        XCTAssertEqual(occurrences.first?.file, "CanvasManager.swift",
                        "the one permitted spelling should be maxCanvasExtent's declaration")
    }

    /// Every bound this item has retired must be gone — a stray leftover would mean some reader
    /// still clamps to a number the app no longer honours. 512 and 8192 predate TODO.md item (13);
    /// 16383 was item (13)'s own answer and item (31) retired it in turn, 2026-09-07, down to 4200
    /// (4096 was the first answer, not a retired one — see the note above on why it moved).
    func testTheOldBoundsAreGoneFromAppSource() {
        XCTAssertTrue(literalOccurrences(of: "8192").isEmpty,
                      "the picker's old 8192 maximum should have no remaining spelling")
        XCTAssertTrue(literalOccurrences(of: "16384").isEmpty,
                      "16384 is one too large for a signed 16-bit quarter-pixel coordinate — 16383 is correct")
        XCTAssertTrue(literalOccurrences(of: "16383").isEmpty,
                      "16383 was maxCanvasExtent's value before TODO.md item (31); it crashes a 3 GB "
                      + "device on a brushstroke and should have no remaining spelling as a bound")
    }

    /// `CanvasSizePickerView.maxDimension` can't be exercised from this pure-logic tier — it is a
    /// `@State`-bearing SwiftUI `View` behind a `private` field, not a value this tier can construct
    /// and drive without a simulator. Reading its own source is the honest substitute: it must read
    /// `CanvasManager.maxCanvasExtent` rather than spelling 16383 (or the old 8192) itself, which is
    /// exactly what the two scans above already establish jointly. This test names the file
    /// explicitly so a rename or a reverted edit shows up here rather than only in the aggregate count.
    func testCanvasSizePickerReadsTheSharedConstantForItsMaximum() {
        guard let text = try? String(contentsOfFile: appSourceRoot() + "/Views/CanvasSizePickerView.swift",
                                      encoding: .utf8) else {
            XCTFail("could not read CanvasSizePickerView.swift")
            return
        }
        XCTAssertTrue(text.contains("CanvasManager.maxCanvasExtent"),
                      "CanvasSizePickerView.maxDimension should read CanvasManager.maxCanvasExtent")
    }

    // MARK: - Source scanning helpers

    private func appSourceRoot() -> String {
        // This file lives at <repo>/PaintSoftwareUITests/CanvasGeometryLogicTests.swift; the app
        // sources this item touches live at <repo>/PaintSoftware.
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        return repoRoot.appendingPathComponent("PaintSoftware").path
    }

    private struct Occurrence: CustomStringConvertible {
        let file: String
        let line: Int
        var description: String { "\(file):\(line)" }
    }

    /// Every **code** line under `PaintSoftware/` (recursively, `.swift` only, no block comments
    /// anywhere in this codebase — confirmed by grep) containing `literal` as a standalone number —
    /// not as a substring of a longer digit run, so "16383" does not also match inside some unrelated
    /// "116383x".
    ///
    /// Deliberately blind to comments: this codebase's own doc-comment style narrates old and
    /// rejected numbers in prose (this very file's header does, and so do the two edited sites' own
    /// comments — "16383, not 16384", "raised 8192 -> 16383"), and that is documentation doing its
    /// job, not a second spelling of the bound. Only the `//`-prefixed portion of a line is stripped;
    /// this codebase has no `/* */` block comments to miss.
    private func literalOccurrences(of literal: String) -> [Occurrence] {
        let root = appSourceRoot()
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        let pattern = try! NSRegularExpression(pattern: "(?<!\\d)\(literal)(?!\\d)")
        var found: [Occurrence] = []
        for case let relativePath as String in enumerator where relativePath.hasSuffix(".swift") {
            let fullPath = root + "/" + relativePath
            guard let contents = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
            for (index, line) in contents.components(separatedBy: .newlines).enumerated() {
                let codePortion = line.range(of: "//").map { String(line[line.startIndex..<$0.lowerBound]) } ?? line
                let range = NSRange(codePortion.startIndex..., in: codePortion)
                if pattern.firstMatch(in: codePortion, range: range) != nil {
                    found.append(Occurrence(file: (relativePath as NSString).lastPathComponent, line: index + 1))
                }
            }
        }
        return found
    }
}
