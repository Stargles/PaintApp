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
    ///
    /// **MEASURED, not inferred, since the device run of 2026-09-07** (PERFORMANCE.md §15.5): on the
    /// owner's iPad 9 a fresh single-layer document survived a canvas-crossing stroke at 12000 and
    /// was killed at 13000, and 6000 is half of that smaller boundary.
    func testMaxCanvasExtentIsMeasuredFromTheOwnersIPadNotInferred() {
        XCTAssertEqual(CanvasManager.maxCanvasExtent, 6000,
                       "MEASURED — PERFORMANCE.md §15 has the device run this comes from")
    }

    func testCanvasPaddingBaseUpperBoundRoseFromFiveTwelveToTenTwentyFour() {
        XCTAssertEqual(CanvasManager.canvasPaddingBaseUpperBound, 1024)
    }

    // MARK: - The arithmetic behind the memory-driven cap (TODO.md item (31))

    /// **Reproduces PERFORMANCE.md §15's *measurement* as an assertion, so the two cannot drift
    /// apart.** Every figure below is MEASURED on the owner's iPad 9 (`iPad12,1`, A13, 3 GB, iOS
    /// 26.5.2), Release, 2026-09-07, one labelled app launch per canvas size, `ExtentProbe` sampling
    /// `phys_footprint` and `os_proc_available_memory()` every 250 ms and `fsync`ing each line so the
    /// sample before a jetsam kill survives it.
    ///
    /// **This test replaced an INFERRED one and would have failed against it**, which is the point:
    /// the old version asserted `8 · 4 · S²` against half of 1837 MiB and 6000 does not fit that at
    /// all (1099 MiB against 918.5). The arithmetic was too pessimistic for the case it was aimed
    /// at — see PERFORMANCE.md §15.6 for how far, and in which direction.
    func testTheChosenCapFitsTheMeasuredDeviceCeilingWithAnUnmeasuredSandwichOnTop() {
        // MEASURED: `phys_footprint + os_proc_available_memory()` was 1850 MiB in every one of the
        // nineteen labelled launches, at every canvas size. That constancy is what makes it the
        // device's own ceiling rather than an estimate.
        let ceilingBytes = 1850.0 * 1024 * 1024

        // MEASURED peak `phys_footprint`, Condition B — four layers each inked, undo history behind
        // them, then one canvas-crossing stroke. The two anchors either side of the cap.
        let workedPeakAt5486 = 617.0 * 1024 * 1024
        let workedPeakAt6500 = 856.7 * 1024 * 1024

        /// The worked-document peak at `extent`, linearly interpolated in **pixel count** (which is
        /// what the cost scales with) between the two measured anchors.
        func measuredWorkedPeakBytes(atExtent extent: Double) -> Double {
            let low = 5486.0 * 5486.0, high = 6500.0 * 6500.0
            let t = (extent * extent - low) / (high - low)
            return workedPeakAt5486 + t * (workedPeakAt6500 - workedPeakAt5486)
        }

        // NOT measured, and this is the whole margin: every document in that run was plain — no
        // blend mode, no adjustment layer, no mask, no folder — so a graded frame's sandwich is on
        // top of the figures above. `SandwichRecipe` composites `below` and `above` as two
        // full-frame requests over one shared resolve (three canvas-sized buffers), and
        // `CompositorBudget.hasHeadroom` prices a canvas-sized texture at twice its raw bytes (the
        // readback `CGImage` plus the Core Animation copy).
        func unmeasuredSandwichBytes(atExtent extent: Double) -> Double { 3 * 2 * 4 * extent * extent }

        func totalBytes(atExtent extent: Double) -> Double {
            measuredWorkedPeakBytes(atExtent: extent) + unmeasuredSandwichBytes(atExtent: extent)
        }

        // **The rule that picks the number**: the *measured* peak must stay under 40% of the ceiling,
        // so that the majority of the device's memory is still free for the path the run did not
        // exercise. At 6000 that peak is 733 MiB, 39.6%.
        let measuredShareAllowed = 0.40
        XCTAssertLessThan(measuredWorkedPeakBytes(atExtent: Double(CanvasManager.maxCanvasExtent)),
                          measuredShareAllowed * ceilingBytes,
                          "the cap must leave the majority of the device ceiling free for the "
                          + "compositing path the device run did not exercise")

        // And this is why the cap is 6000 and not the next round number up. 6500's own measured peak
        // is 857 MiB, 46.3% — and 857 plus the same sandwich is 1824 MiB against an 1850 MiB
        // ceiling. It *fits*, by 26 MiB, which is a boundary rather than a margin.
        XCTAssertGreaterThan(measuredWorkedPeakBytes(atExtent: 6500), measuredShareAllowed * ceilingBytes,
                             "6500 is the size this bound was chosen against")

        // The second half of the rule: the sandwich the run never engaged has to fit in what is left.
        XCTAssertLessThan(totalBytes(atExtent: Double(CanvasManager.maxCanvasExtent)), ceilingBytes,
                          "measured peak plus a full un-measured sandwich must still fit the ceiling")

        // MEASURED, Condition A — a fresh single-layer document and one canvas-crossing stroke:
        // 12000 survived at a peak of 1768.3 MiB (82 MiB short of the ceiling) and 13000 was killed.
        // The cap is below half of the largest survivor, in extent.
        XCTAssertLessThanOrEqual(Double(CanvasManager.maxCanvasExtent), 12000.0 / 2,
                                 "the cap should sit at or under half the smaller measured boundary")

        // 16383 is the value item (31) retired, and the run reproduced the owner's own report of it:
        // killed 6.6 s after the stroke, at 1767.9 MiB with 82.1 MiB left. Not asserted here — that
        // is a fact about the device, and an assertion built from the two numbers this comment names
        // would be true of arithmetic rather than of this codebase. What *is* asserted is that the
        // cap sits under half the smaller measured boundary, which does go red if the cap moves.
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

        // (6000 - 1024) / 2 = 2488, above the 1024 base, so the base wins. (6000×6000 is the
        // *exact*-limit fixture below, not "comfortably under" — see the note there.)
        XCTAssertEqual(manager.canvasPaddingRange, 0...1024)
    }

    // MARK: - The range shrinking as the canvas approaches the limit

    func testCanvasPaddingRangeNearTheLimitShrinksBelowTheBase() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 5500, height: 5500)
        manager.canvasPadding = 0

        // (6000 - 5500) / 2 = 250, below the 1024 base, so the budget wins.
        XCTAssertEqual(manager.canvasPaddingRange, 0...250)
    }

    func testCanvasPaddingRangeAtTheExactLimitIsZero() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 6000, height: 6000)
        manager.canvasPadding = 0

        // No room left at all: the artwork already fills the whole 6000 budget.
        XCTAssertEqual(manager.canvasPaddingRange, 0...0)
    }

    func testCanvasPaddingRangeNeverGoesNegativeBeyondTheLimit() {
        // Nothing in the app can put a canvas past `maxCanvasExtent` today, but the formula itself
        // must not produce an invalid (upper < lower) range if it ever did — a `ClosedRange` traps on
        // construction, and a trap here is a crash on opening the Actions menu. 20000 was chosen to
        // sit past the *old* 16383 bound as well as the current 6000 one, so this probe still means
        // "grossly past the limit, however the limit ever moves" rather than merely past today's.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 20000, height: 20000)
        manager.canvasPadding = 0

        XCTAssertEqual(manager.canvasPaddingRange, 0...0)
    }

    // MARK: - `canvasSize` already includes padding — the single easiest thing to get wrong here

    func testCanvasPaddingRangeDoesNotDoubleCountExistingPadding() {
        // canvasSize is at the exact limit, but 500 of each dimension is padding already applied.
        // The artwork itself is only 6000 - 2*500 = 5000, so there is exactly 500 pt of room left on
        // each side before the *canvas* (artwork + padding) would exceed 6000 — i.e. the upper bound
        // should come out to the same 500 that is already applied, not 0.
        //
        // A wrong implementation that reads `canvasSize` as the artwork extent (double-subtracting
        // the padding already on the canvas) would compute (6000 - 6000) / 2 = 0 instead.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 6000, height: 6000)
        manager.canvasPadding = 500

        XCTAssertEqual(manager.canvasPaddingRange, 0...500,
                       "canvasSize already includes the existing padding; the budget must be computed "
                       + "against the artwork extent (canvasSize - 2*canvasPadding), not canvasSize itself")
    }

    func testCanvasPaddingRangeUsesTheLargerDimensionOnANonSquareCanvas() {
        // setCanvasPadding grows both dimensions by the same delta, so a non-square canvas is bounded
        // by whichever dimension is closer to the limit — here, height.
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 2048, height: 5700)
        manager.canvasPadding = 0

        // (6000 - 5700) / 2 = 150, driven by height even though width has plenty of room.
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
        manager.canvasSize = CGSize(width: 5501, height: 5501)

        manager.setCanvasPadding(9000)

        // (6000 - 5501) / 2 = 249.5. `setCanvasPadding` rounds the clamped value (load-bearing for
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
    /// 4200 kept the same derivation and margin without colliding with any of them — proof this scan
    /// does real work rather than passing by construction, found by running it rather than by
    /// reasoning about it in advance. The device run of 2026-09-07 then moved the bound to **6000**,
    /// which was put through the same scan before being adopted: zero collisions
    /// (`CanvasManager.swift`'s own doc comment carries the note).
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
    /// 16383 was item (13)'s own answer and item (31) retired it in turn, 2026-09-07 — first to 4200
    /// by arithmetic and then to 6000 by measurement on the owner's iPad (4096 was the first answer,
    /// not a retired one — see the note above on why it moved).
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
