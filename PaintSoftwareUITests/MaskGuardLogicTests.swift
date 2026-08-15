import XCTest

/// §6.3's guard: `AlphaMask.antialiasHalfWidth` is kept strictly below `AlphaMask.threshold`, so a
/// fully transparent pixel always resolves to no coverage at all.
///
/// **The bug this closes.** `coverage(forSourceAlpha:)` ramps between `threshold ±
/// antialiasHalfWidth`. Nothing used to stop the half-width reaching or passing the threshold, and
/// the shipped sliders reach it easily — the half-width runs to 0.25 while the threshold floors at
/// 0.1, so more than half of that slider's travel drove the ramp's low end to or below zero. At
/// threshold 0.1 / half-width 0.25 a zero-alpha pixel resolved to 55/255: **every pixel on the
/// canvas** picked up partial coverage, and a mask that does not fully hide the empty parts of its
/// source is not hiding anything. It was unreachable in practice only because nobody opened the
/// tuning harness; the mask menu (`LayerPanel.maskMenu`) is what puts that slider in an artist's
/// hands, so the guard has to exist before the menu ships.
///
/// **What these assert is the invariant, not the clamp.** "The slider stops at 0.09" is a fact about
/// one widget and one range, and a test of it would keep passing against a `coverage` rewritten to
/// divide differently, or fail for nothing the day the range moves. The property the guard exists to
/// protect is `coverage(forSourceAlpha: 0) == 0` — at every combination of the two constants the UI
/// can reach, whichever of them was written last.
final class MaskGuardLogicTests: XCTestCase {

    /// The sliders' own ranges (`MaskTuningSection`), which are what "reachable" means here.
    private let thresholdRange: ClosedRange<Float> = 0.1...0.9
    private let halfWidthRange: ClosedRange<Float> = 0.0...0.25

    /// The mask under test is deliberately **not inverted** — see
    /// `testTheInvariantBelongsToANonInvertedMask`.
    private let mask = AlphaMask(sources: [.layer(UUID())])

    private var savedThreshold: Float = 0
    private var savedHalfWidth: Float = 0

    override func setUp() {
        super.setUp()
        savedThreshold = AlphaMask.threshold
        savedHalfWidth = AlphaMask.antialiasHalfWidth
    }

    override func tearDown() {
        // Restored through the one writer, so the pair lands in a legal state in a single step
        // regardless of which order the two would otherwise have been assigned in.
        AlphaMask.setTuning(threshold: savedThreshold, antialiasHalfWidth: savedHalfWidth)
        super.tearDown()
    }

    private func threshold(step: Int, of steps: Int) -> Float {
        thresholdRange.lowerBound
            + (thresholdRange.upperBound - thresholdRange.lowerBound) * Float(step) / Float(steps)
    }

    private func halfWidth(step: Int, of steps: Int) -> Float {
        halfWidthRange.lowerBound
            + (halfWidthRange.upperBound - halfWidthRange.lowerBound) * Float(step) / Float(steps)
    }

    // MARK: - The invariant

    /// The sweep. Every combination of the two slider ranges, written in **both orders**, because
    /// they are two different ways to break the invariant and the guard clamps them in different
    /// arms: raising the half-width past a fixed threshold, and lowering the threshold under a
    /// half-width already set high.
    ///
    /// Failures are collected rather than asserted per combination: 16,000 `XCTAssert` calls cost
    /// more than the arithmetic they check, and the first few offending pairs are what a reader
    /// needs anyway.
    func testATransparentPixelResolvesToNoCoverageAtEveryReachableTuning() {
        let thresholdSteps = 80, halfWidthSteps = 50
        var failures: [String] = []

        for t in 0...thresholdSteps {
            for h in 0...halfWidthSteps {
                let wantedThreshold = threshold(step: t, of: thresholdSteps)
                let wantedHalfWidth = halfWidth(step: h, of: halfWidthSteps)

                // Direction 1 — the half-width is raised against a threshold already in place.
                AlphaMask.threshold = wantedThreshold
                AlphaMask.antialiasHalfWidth = wantedHalfWidth
                record(&failures, wantedThreshold, wantedHalfWidth, "half-width raised last")

                // Direction 2 — the half-width is set with room to spare (threshold at the top of
                // its range, which clears the whole half-width range), and *then* the threshold is
                // dropped underneath it. Without the first write this arm would silently test the
                // same thing direction 1 does, since the half-width would already have been clamped.
                AlphaMask.threshold = thresholdRange.upperBound
                AlphaMask.antialiasHalfWidth = wantedHalfWidth
                AlphaMask.threshold = wantedThreshold
                record(&failures, wantedThreshold, wantedHalfWidth, "threshold lowered last")
            }
        }

        XCTAssertEqual(failures.count, 0,
                       "A fully transparent pixel must resolve to zero coverage at every tuning the "
                       + "sliders can reach. First failures: \(failures.prefix(5).joined(separator: "; "))")
    }

    private func record(_ failures: inout [String], _ wantedThreshold: Float, _ wantedHalfWidth: Float,
                        _ direction: String) {
        let coverage = mask.coverage(forSourceAlpha: 0)
        guard coverage != 0 else { return }
        failures.append("wanted (\(wantedThreshold), \(wantedHalfWidth)) \(direction) -> settled at "
                        + "(\(AlphaMask.threshold), \(AlphaMask.antialiasHalfWidth)), coverage \(coverage)")
    }

    /// The same sweep's other half: no tuning may produce a coverage that is not a number in `0...1`.
    ///
    /// A **zero** half-width stays legal — the slider's range starts there and it is the hard boolean
    /// edge §6.3 describes — and it is the one that makes the ramp's divisor zero, so `alpha ==
    /// threshold` divides 0 by 0. A NaN there is not a wrong picture, it is a trap: `MaskResolver`
    /// narrows the coverage into a `UInt8`, and `UInt8(Float.nan)` is a runtime crash.
    func testNoReachableTuningProducesACoverageOutsideZeroToOne() {
        var failures: [String] = []
        let tunings: [(Float, Float)] = [
            (0.1, 0), (0.2, 0), (0.5, 0), (0.9, 0),          // the zero-width band, where 0/0 lives
            (0.1, 0.25), (0.1, 0.1), (0.5, 0.5), (0.9, 0.25) // half-width at or past the threshold
        ]
        for (wantedThreshold, wantedHalfWidth) in tunings {
            AlphaMask.setTuning(threshold: wantedThreshold, antialiasHalfWidth: wantedHalfWidth)
            for byte in 0...255 {
                let coverage = mask.coverage(forSourceAlpha: Float(byte) / 255)
                if coverage.isNaN || coverage < 0 || coverage > 1 {
                    failures.append("(\(wantedThreshold), \(wantedHalfWidth)) at alpha \(byte) -> \(coverage)")
                }
            }
        }
        XCTAssertEqual(failures.count, 0,
                       "Coverage must stay a number in 0...1 for every source alpha. "
                       + "First failures: \(failures.prefix(5).joined(separator: "; "))")
    }

    /// Why the sweep uses a mask that is not inverted: inversion is applied *after* the threshold, so
    /// `coverage(forSourceAlpha: 0) == 1` on an inverted mask is the feature rather than the bug —
    /// "show me everything the source does not cover" has to cover the empty pixels. The invariant is
    /// stated on the un-inverted mask, and inversion's job is to be exactly its complement.
    func testTheInvariantBelongsToANonInvertedMask() {
        var inverted = mask
        inverted.invert = true
        AlphaMask.setTuning(threshold: 0.1, antialiasHalfWidth: 0.01)

        XCTAssertEqual(mask.coverage(forSourceAlpha: 0), 0)
        XCTAssertEqual(inverted.coverage(forSourceAlpha: 0), 1)
        for byte in 0...255 {
            let alpha = Float(byte) / 255
            XCTAssertEqual(inverted.coverage(forSourceAlpha: alpha),
                           1 - mask.coverage(forSourceAlpha: alpha), accuracy: 1e-6)
        }
    }

    // MARK: - The mechanism

    /// The clamp itself, stated once in each direction so a failure of the sweep above is easy to
    /// localise. This is the *implementation* the sweep is deliberately independent of — if a later
    /// change moves the guard somewhere else, these two are the tests to delete, and the sweep is the
    /// one that still has to pass.
    func testTheHalfWidthYieldsInBothDirections() {
        AlphaMask.threshold = 0.5
        AlphaMask.antialiasHalfWidth = 0.4
        XCTAssertEqual(AlphaMask.threshold, 0.5, "The threshold is the number the artist did not touch")
        XCTAssertLessThan(AlphaMask.antialiasHalfWidth, AlphaMask.threshold,
                          "Raising the half-width past the threshold parks it just under")

        AlphaMask.threshold = 0.2
        XCTAssertEqual(AlphaMask.threshold, 0.2, accuracy: 1e-6)
        XCTAssertLessThan(AlphaMask.antialiasHalfWidth, AlphaMask.threshold,
                          "Lowering the threshold under the half-width pulls the half-width down with it")
    }

    /// A tuning write still invalidates the mask cache, whether or not the guard changed the value
    /// the caller asked for — `MaskResolver.CacheKey` can only see these two constants through
    /// `tuningGeneration` (see its doc comment), and a clamped write is still a write.
    func testAClampedWriteStillBumpsTheTuningGeneration() {
        let before = AlphaMask.tuningGeneration
        AlphaMask.antialiasHalfWidth = 10   // far outside anything legal
        XCTAssertGreaterThan(AlphaMask.tuningGeneration, before)
        XCTAssertLessThan(AlphaMask.antialiasHalfWidth, AlphaMask.threshold)
    }

    /// A non-finite write is a caller bug, and the guard answers it by keeping the last good value
    /// rather than poisoning every coverage byte in the document with a NaN.
    func testANonFiniteWriteIsRefusedRatherThanStored() {
        AlphaMask.setTuning(threshold: 0.4, antialiasHalfWidth: 0.05)
        AlphaMask.threshold = .nan
        AlphaMask.antialiasHalfWidth = .infinity
        XCTAssertEqual(AlphaMask.threshold, 0.4, accuracy: 1e-6)
        XCTAssertLessThan(AlphaMask.antialiasHalfWidth, AlphaMask.threshold)
        XCTAssertEqual(mask.coverage(forSourceAlpha: 0), 0)
    }
}
