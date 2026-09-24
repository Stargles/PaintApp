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
///
/// **Since TODO.md item (86), `maxCanvasExtent` is a function of the running device, not a literal**
/// (`CanvasManager.swift`'s own doc comment on it carries the derivation). Every padding-range test
/// below reads `CanvasManager.maxCanvasExtent` rather than spelling a number, so they stay correct
/// however that function's constants are tuned; `testMaxCanvasExtentWithNoDeviceSignalFallsBackToTheReferenceIPadsBudget`
/// pins the one fact the others lean on — that with no live device signal (the simulator this whole
/// tier runs on) it comes out to exactly 6000, the same number item (31) shipped.
final class CanvasGeometryLogicTests: XCTestCase {

    override func tearDown() {
        CanvasManager.deviceMemoryBudgetOverrideBytes = nil
        super.tearDown()
    }

    // MARK: - The named constants

    func testCanvasPaddingBaseUpperBoundRoseFromFiveTwelveToTenTwentyFour() {
        XCTAssertEqual(CanvasManager.canvasPaddingBaseUpperBound, 1024)
    }

    /// **The fact every other test in this file leans on.** `CanvasManager.maxCanvasExtent` reads
    /// `os_proc_available_memory()` in production; on the simulator (every host this suite runs on)
    /// that answers 0 — "no information," per `CompositorBudget`'s own doc comment on the same call —
    /// so `deviceMemoryBudgetBytes` falls back to the reference iPad's own MEASURED ceiling
    /// (PERFORMANCE.md §15.5, 1850 MiB) instead. `testMaxCanvasExtentAtTheReferenceBudgetReproduces6000`
    /// below pins that the *formula* reproduces 6000 at that budget; this pins that the *ambient*,
    /// no-override property actually reaches it through the fallback, which is the path every other
    /// test in this file that still spells "6000" is implicitly depending on.
    func testMaxCanvasExtentWithNoDeviceSignalFallsBackToTheReferenceIPadsBudget() {
        XCTAssertEqual(CanvasManager.maxCanvasExtent, 6000)
    }

    // MARK: - TODO.md item (86): the ceiling is a function of the device

    /// Reproduces PERFORMANCE.md §22.2's three `PlaybackProbe` rows — a graded document (a blend
    /// mode, so the sandwich engages) mid-stroke, `phys_footprint` peak above an at-rest baseline —
    /// as assertions against `CanvasManager.gradedWorkingSetBytes(atExtent:)`, so the fit and the
    /// measurement it comes from cannot drift apart unnoticed. The fit is a *line*, not an interpolation
    /// through the three points, so it does not reproduce any of them exactly — 10% is generous
    /// headroom over the worst of the three (§22.2's own table: 6.7%, 6.9%, 2.2%).
    func testGradedWorkingSetFitReproducesThePerformanceMdMeasurements() {
        let mib = 1024.0 * 1024.0
        let cases: [(extent: Double, measuredMiB: Double)] = [(6000, 1089), (7000, 1811), (8192, 2363)]
        for (extent, measuredMiB) in cases {
            let fitMiB = CanvasManager.gradedWorkingSetBytes(atExtent: extent) / mib
            let tolerance = measuredMiB * 0.10
            XCTAssertEqual(fitMiB, measuredMiB, accuracy: tolerance,
                           "the fit at \(extent)² should stay within 10% of PERFORMANCE.md §22.2's own "
                           + "measured \(measuredMiB) MiB")
        }
    }

    /// **The number item (31)/(86) already shipped, reproduced by the formula rather than spelled
    /// again.** `deviceMemoryBudgetBytes` is the reference iPad's own MEASURED ceiling
    /// (PERFORMANCE.md §15.5); this is `maxCanvasExtent(deviceMemoryBudgetBytes:)` called directly,
    /// with no dependence on the ambient no-signal fallback the way the "with no device signal" test
    /// above is.
    func testMaxCanvasExtentAtTheReferenceBudgetReproduces6000() {
        XCTAssertEqual(CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: 1850 * 1024 * 1024), 6000)
    }

    /// The owner's own test case: *"running the paint app on a better ipad or another device should
    /// not necessarily limit the canvas size to 6k, only whatever is best."* Twice the reference
    /// iPad's own budget must not merely stay at 6000 — it must be strictly larger, and (since the
    /// fit's fixed term is not zero) not simply double either.
    func testMaxCanvasExtentGrowsOnADeviceWithMoreMemory() {
        let reference = CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: 1850 * 1024 * 1024)
        let doubled = CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: 2 * 1850 * 1024 * 1024)
        XCTAssertGreaterThan(doubled, reference,
                             "a device with twice the memory budget must get a larger ceiling")
        XCTAssertNotEqual(doubled, 2 * reference,
                          "the fit's fixed term means the relationship is areal, not linear in the extent")
    }

    /// Monotonic across an order of magnitude either side of the reference — no dip anywhere the
    /// owner's "whatever is best" could land on.
    func testMaxCanvasExtentIsMonotonicNonDecreasingInTheDeviceBudget() {
        let budgetsMiB: [Double] = [200, 462.5, 925, 1850, 2939, 3700, 5000, 7400, 14800, 29600]
        var previous: CGFloat = 0
        for mib in budgetsMiB {
            let extent = CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: mib * 1024 * 1024)
            XCTAssertGreaterThanOrEqual(extent, previous, "\(mib) MiB should not yield a smaller ceiling "
                                        + "than a lower budget did")
            previous = extent
        }
    }

    /// No amount of device memory buys past the coordinate format's own ceiling — TODO.md item (8)'s
    /// signed 16-bit quarter-pixel sample addresses -8192.0...+8191.75, a span of 16383.75 pt.
    func testMaxCanvasExtentClampsToTheFormatCeilingOnAHugeBudget() {
        let extent = CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: 1_000_000 * 1024 * 1024)
        XCTAssertEqual(extent, CanvasManager.formatExtentCeiling)
    }

    /// A non-positive budget passed directly to the pure function is a floor, not "no signal" — that
    /// substitution is `deviceMemoryBudgetBytes`'s job (below), so the formula itself must not solve
    /// for a negative or zero extent.
    func testMaxCanvasExtentFloorsOnANonPositiveBudget() {
        XCTAssertEqual(CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: 0),
                       CanvasManager.minimumCanvasExtent)
        XCTAssertEqual(CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: -1),
                       CanvasManager.minimumCanvasExtent)
    }

    /// **Why the rounding step doesn't just round to the nearest multiple that happens to fit better.**
    /// One `maxCanvasExtentRoundingStep` past the chosen extent, the fit's predicted cost must already
    /// exceed the margin the reference budget allows — otherwise the rounding (not the margin) would be
    /// the reason a larger step was left on the table, and the two would be lying about which one is
    /// doing the work.
    func testOneRoundingStepUpNoLongerFitsTheReferenceMargin() {
        let budget = 1850.0 * 1024 * 1024
        let chosen = CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes: budget)
        let nextStep = chosen + CanvasManager.maxCanvasExtentRoundingStep
        let allowance = CanvasManager.gradedWorkingSetBudgetFraction * budget
        XCTAssertGreaterThan(CanvasManager.gradedWorkingSetBytes(atExtent: Double(nextStep)), allowance,
                             "the next clean step up should already be past what the margin allows")
    }

    // MARK: - The range at an ordinary canvas

    func testCanvasPaddingRangeOnOrdinaryCanvasIsTheBaseTenTwentyFour() {
        // The owner's own working size (PERFORMANCE.md §1), nowhere near the device's memory budget,
        // so the base upper bound applies unclamped.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 2048, height: 1024)
        manager.canvasPadding = 0

        XCTAssertEqual(manager.canvasPaddingRange, 0...1024)
    }

    func testCanvasPaddingRangeAtASquareOrdinaryCanvasIsAlsoTheBase() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 1024, height: 1024)
        manager.canvasPadding = 0

        // (maxCanvasExtent - 1024) / 2 is comfortably above the 1024 base on any device this formula
        // can produce (the smallest is `minimumCanvasExtent`, 1024, and even that clears this), so the
        // base wins. (maxCanvasExtent×maxCanvasExtent is the *exact*-limit fixture below, not
        // "comfortably under" — see the note there.)
        XCTAssertEqual(manager.canvasPaddingRange, 0...1024)
    }

    // MARK: - The range shrinking as the canvas approaches the limit

    func testCanvasPaddingRangeNearTheLimitShrinksBelowTheBase() {
        let limit = CanvasManager.maxCanvasExtent
        let manager = CanvasManager()
        let artworkExtent = limit - 500
        manager.canvasSize = CGSize(width: artworkExtent, height: artworkExtent)
        manager.canvasPadding = 0

        // (limit - artworkExtent) / 2 = 250, below the 1024 base, so the budget wins.
        XCTAssertEqual(manager.canvasPaddingRange, 0...((limit - artworkExtent) / 2))
    }

    func testCanvasPaddingRangeAtTheExactLimitIsZero() {
        let limit = CanvasManager.maxCanvasExtent
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: limit, height: limit)
        manager.canvasPadding = 0

        // No room left at all: the artwork already fills the whole budget.
        XCTAssertEqual(manager.canvasPaddingRange, 0...0)
    }

    func testCanvasPaddingRangeNeverGoesNegativeBeyondTheLimit() {
        // Nothing in the app can put a canvas past `maxCanvasExtent` today, but the formula itself
        // must not produce an invalid (upper < lower) range if it ever did — a `ClosedRange` traps on
        // construction, and a trap here is a crash on opening the Actions menu. `formatExtentCeiling`
        // (16383, TODO.md item (8)'s own hard top) plus a margin sits past every extent
        // `maxCanvasExtent` can produce on any budget, so this probe still means "grossly past the
        // limit, however the limit ever moves."
        let manager = CanvasManager()
        let past = CanvasManager.formatExtentCeiling + 4000
        manager.canvasSize = CGSize(width: past, height: past)
        manager.canvasPadding = 0

        XCTAssertEqual(manager.canvasPaddingRange, 0...0)
    }

    // MARK: - `canvasSize` already includes padding — the single easiest thing to get wrong here

    func testCanvasPaddingRangeDoesNotDoubleCountExistingPadding() {
        // canvasSize is at the exact limit, but 500 of each dimension is padding already applied.
        // The artwork itself is only limit - 2*500, so there is exactly 500 pt of room left on each
        // side before the *canvas* (artwork + padding) would exceed the limit — i.e. the upper bound
        // should come out to the same 500 that is already applied, not 0.
        //
        // A wrong implementation that reads `canvasSize` as the artwork extent (double-subtracting
        // the padding already on the canvas) would compute (limit - limit) / 2 = 0 instead.
        let limit = CanvasManager.maxCanvasExtent
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: limit, height: limit)
        manager.canvasPadding = 500

        XCTAssertEqual(manager.canvasPaddingRange, 0...500,
                       "canvasSize already includes the existing padding; the budget must be computed "
                       + "against the artwork extent (canvasSize - 2*canvasPadding), not canvasSize itself")
    }

    func testCanvasPaddingRangeUsesTheLargerDimensionOnANonSquareCanvas() {
        // setCanvasPadding grows both dimensions by the same delta, so a non-square canvas is bounded
        // by whichever dimension is closer to the limit — here, height.
        let limit = CanvasManager.maxCanvasExtent
        let manager = CanvasManager()
        let height = limit - 300
        manager.canvasSize = CGSize(width: 2048, height: height)
        manager.canvasPadding = 0

        // (limit - height) / 2 = 150, driven by height even though width has plenty of room.
        XCTAssertEqual(manager.canvasPaddingRange, 0...((limit - height) / 2))
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
        let limit = CanvasManager.maxCanvasExtent
        let manager = CanvasManager()
        let artworkExtent = limit - 499
        manager.canvasSize = CGSize(width: artworkExtent, height: artworkExtent)

        manager.setCanvasPadding(9000)

        // (limit - artworkExtent) / 2 = 249.5. `setCanvasPadding` rounds the clamped value
        // (load-bearing for backend parity — see its own doc comment), so the range's 249.5 upper
        // bound becomes 250 here, not 249.5 itself.
        XCTAssertEqual(manager.canvasPadding, 250, "clamped to the budget (rounded), not the 1024 base")
    }

    // MARK: - "Defined once in the code"

    /// Every bound this item has retired must be gone — a stray leftover would mean some reader still
    /// clamps to a number the app no longer honours. 512 and 8192 predate TODO.md item (13); 16384 is
    /// one too large for the signed 16-bit quarter-pixel coordinate and was never a bound at all.
    ///
    /// **16383 is deliberately not checked here any more.** It was item (13)'s own answer and item
    /// (31) retired it as `maxCanvasExtent`'s *value* on 2026-09-07 — but TODO.md item (86) gave it a
    /// legitimate second job: `CanvasManager.formatExtentCeiling` clamps the device-derived formula at
    /// the coordinate format's own hard top, which is exactly this number for exactly the reason
    /// `SampleCodingLogicTests` already pins. A live occurrence of "16383" in app source is correct
    /// again, at that one named site.
    func testTheOldBoundsAreGoneFromAppSource() {
        XCTAssertTrue(literalOccurrences(of: "8192").isEmpty,
                      "the picker's old 8192 maximum should have no remaining spelling")
        XCTAssertTrue(literalOccurrences(of: "16384").isEmpty,
                      "16384 is one too large for a signed 16-bit quarter-pixel coordinate — 16383 is correct")
    }

    /// `CanvasSizePickerView.maxDimension` can't be exercised from this pure-logic tier — it is a
    /// `@State`-bearing SwiftUI `View` behind a `private` field, not a value this tier can construct
    /// and drive without a simulator. Reading its own source is the honest substitute: it must read
    /// `CanvasManager.maxCanvasExtent` rather than spelling a number itself. This test names the file
    /// explicitly so a rename or a reverted edit shows up here rather than only in an aggregate count.
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
