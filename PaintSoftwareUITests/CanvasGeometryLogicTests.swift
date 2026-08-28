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

    func testMaxCanvasExtentIsSixteenThreeEightyThreeNotSixteenThreeEightyFour() {
        // A signed 16-bit quarter-pixel sample coordinate (TODO.md item (8)) addresses
        // -8192.0...+8191.75 — a span of 16383.75 pt, not 16384 — so with the encoding origin at the
        // canvas centre, 16383 is the largest dimension that encodes without clamping a quarter-pixel
        // inside the artwork on two edges.
        XCTAssertEqual(CanvasManager.maxCanvasExtent, 16383)
    }

    func testCanvasPaddingBaseUpperBoundRoseFromFiveTwelveToTenTwentyFour() {
        XCTAssertEqual(CanvasManager.canvasPaddingBaseUpperBound, 1024)
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
        manager.canvasSize = CGSize(width: 4096, height: 4096)
        manager.canvasPadding = 0

        // (16383 - 4096) / 2 = 6143.5, well above the 1024 base, so the base wins.
        XCTAssertEqual(manager.canvasPaddingRange, 0...1024)
    }

    // MARK: - The range shrinking as the canvas approaches 16k

    func testCanvasPaddingRangeNearTheLimitShrinksBelowTheBase() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 16000, height: 16000)
        manager.canvasPadding = 0

        // (16383 - 16000) / 2 = 191.5, below the 1024 base, so the budget wins.
        XCTAssertEqual(manager.canvasPaddingRange, 0...191.5)
    }

    func testCanvasPaddingRangeAtTheExactLimitIsZero() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 16383, height: 16383)
        manager.canvasPadding = 0

        // No room left at all: the artwork already fills the whole 16383 budget.
        XCTAssertEqual(manager.canvasPaddingRange, 0...0)
    }

    func testCanvasPaddingRangeNeverGoesNegativeBeyondTheLimit() {
        // Nothing in the app can put a canvas past `maxCanvasExtent` today, but the formula itself
        // must not produce an invalid (upper < lower) range if it ever did — a `ClosedRange` traps on
        // construction, and a trap here is a crash on opening the Actions menu.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 20000, height: 20000)
        manager.canvasPadding = 0

        XCTAssertEqual(manager.canvasPaddingRange, 0...0)
    }

    // MARK: - `canvasSize` already includes padding — the single easiest thing to get wrong here

    func testCanvasPaddingRangeDoesNotDoubleCountExistingPadding() {
        // canvasSize is at the exact limit, but 500 of each dimension is padding already applied
        // (canvasPadding = 500, matching this item's own worked example). The artwork itself is only
        // 16383 - 2*500 = 15383, so there is exactly 500 pt of room left on each side before the
        // *canvas* (artwork + padding) would exceed 16383 — i.e. the upper bound should come out to
        // the same 500 that is already applied, not 0.
        //
        // A wrong implementation that reads `canvasSize` as the artwork extent (double-subtracting
        // the padding already on the canvas) would compute (16383 - 16383) / 2 = 0 instead.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 16383, height: 16383)
        manager.canvasPadding = 500

        XCTAssertEqual(manager.canvasPaddingRange, 0...500,
                       "canvasSize already includes the existing padding; the budget must be computed "
                       + "against the artwork extent (canvasSize - 2*canvasPadding), not canvasSize itself")
    }

    func testCanvasPaddingRangeUsesTheLargerDimensionOnANonSquareCanvas() {
        // setCanvasPadding grows both dimensions by the same delta, so a non-square canvas is bounded
        // by whichever dimension is closer to the limit — here, height.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 2048, height: 16000)
        manager.canvasPadding = 0

        // (16383 - 16000) / 2 = 191.5, driven by height even though width has plenty of room.
        XCTAssertEqual(manager.canvasPaddingRange, 0...191.5)
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
        manager.canvasSize = CGSize(width: 16000, height: 16000)

        manager.setCanvasPadding(5000)

        // `setCanvasPadding` rounds the clamped value (load-bearing for backend parity — see its own
        // doc comment), so the range's 191.5 upper bound becomes 192 here, not 191.5 itself.
        XCTAssertEqual(manager.canvasPadding, 192, "clamped to the budget (rounded), not the 1024 base")
    }

    // MARK: - "Defined once in the code"

    /// Scans the app's own source (not the test target) for stray literal spellings of the 16383
    /// bound. `CanvasManager.maxCanvasExtent`'s declaration is the one permitted occurrence; every
    /// other reader — `CanvasSizePickerView.maxDimension` included — must read the constant rather
    /// than spelling the number again, or a future change to the bound silently misses one of them.
    func testMaxCanvasExtentIsTheOnlySpellingOfSixteenThreeEightyThreeInAppSource() {
        let occurrences = literalOccurrences(of: "16383")

        XCTAssertEqual(occurrences.count, 1,
                       "expected exactly one literal spelling of 16383 (CanvasManager.maxCanvasExtent's "
                       + "own declaration); found: \(occurrences)")
        XCTAssertEqual(occurrences.first?.file, "CanvasManager.swift",
                        "the one permitted spelling should be maxCanvasExtent's declaration")
    }

    /// The old flat 512 ceiling and 8192 picker maximum must both be gone — a stray leftover would
    /// mean some reader still clamps to the number this item retired.
    func testTheOldBoundsAreGoneFromAppSource() {
        XCTAssertTrue(literalOccurrences(of: "8192").isEmpty,
                      "the picker's old 8192 maximum should have no remaining spelling")
        XCTAssertTrue(literalOccurrences(of: "16384").isEmpty,
                      "16384 is one too large for a signed 16-bit quarter-pixel coordinate — 16383 is correct")
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
