import XCTest

/// Every reachable tuning excludes empty pixels, independently on every mask.
final class MaskGuardLogicTests: XCTestCase {
    func testATransparentPixelResolvesToNoCoverageAtEveryReachableTuning() {
        var mask = AlphaMask(sources: [.layer(UUID())])
        var failures = 0
        for thresholdStep in 0...80 {
            for widthStep in 0...50 {
                let threshold = 0.1 + Float(thresholdStep) * 0.01
                let width = Float(widthStep) * 0.005
                mask.setTuning(threshold: threshold, antialiasHalfWidth: width)
                if mask.coverage(forSourceAlpha: 0) != 0 { failures += 1 }
                mask.setTuning(threshold: 0.9, antialiasHalfWidth: width)
                mask.setTuning(threshold: threshold, antialiasHalfWidth: mask.antialiasHalfWidth)
                if mask.coverage(forSourceAlpha: 0) != 0 { failures += 1 }
            }
        }
        XCTAssertEqual(failures, 0)
    }

    func testNoReachableTuningProducesACoverageOutsideZeroToOne() {
        var mask = AlphaMask()
        var failures = 0
        for (threshold, width): (Float, Float) in [(0.1, 0), (0.2, 0), (0.5, 0), (0.9, 0),
                                                  (0.1, 0.25), (0.1, 0.1), (0.5, 0.5), (0.9, 0.25)] {
            mask.setTuning(threshold: threshold, antialiasHalfWidth: width)
            for byte in 0...255 {
                let coverage = mask.coverage(forSourceAlpha: Float(byte) / 255)
                if !coverage.isFinite || !(0...1).contains(coverage) { failures += 1 }
            }
        }
        XCTAssertEqual(failures, 0)
    }

    func testTheInvariantBelongsToANonInvertedMask() {
        let mask = AlphaMask()
        var inverted = mask
        inverted.invert = true
        var failures = 0
        for byte in 0...255 {
            if inverted.coverage(forSourceAlpha: Float(byte) / 255) != 1 - mask.coverage(forSourceAlpha: Float(byte) / 255) {
                failures += 1
            }
        }
        XCTAssertEqual(failures, 0)
    }

    func testTheHalfWidthYieldsInBothDirections() {
        var mask = AlphaMask()
        mask.setTuning(threshold: 0.5, antialiasHalfWidth: 0.8)
        XCTAssertEqual(mask.threshold, 0.5)
        XCTAssertLessThan(mask.antialiasHalfWidth, mask.threshold)
        mask.setTuning(threshold: 0.2, antialiasHalfWidth: mask.antialiasHalfWidth)
        XCTAssertEqual(mask.threshold, 0.2, accuracy: 1e-6)
        XCTAssertLessThan(mask.antialiasHalfWidth, mask.threshold)
    }

    func testANonFiniteWriteIsRefusedRatherThanStored() {
        var mask = AlphaMask()
        mask.setTuning(threshold: 0.4, antialiasHalfWidth: 0.05)
        mask.setTuning(threshold: .nan, antialiasHalfWidth: .infinity)
        XCTAssertEqual(mask.threshold, 0.4)
        XCTAssertEqual(mask.antialiasHalfWidth, 0.05)
    }

    func testMasksCarryIndependentTuningAndFrozenCopies() {
        var edited = AlphaMask()
        let other = AlphaMask()
        let frozen = edited
        edited.setTuning(threshold: 0.8, antialiasHalfWidth: 0.1)
        XCTAssertEqual(other.coverage(forSourceAlpha: 0.5), 1)
        XCTAssertEqual(frozen.coverage(forSourceAlpha: 0.5), 1)
        XCTAssertEqual(edited.coverage(forSourceAlpha: 0.5), 0)
    }
}
