import XCTest

/// Pure-logic tests for the brush engine's math — `BrushDynamics` pressure curves and
/// `StrokeStabilizer`'s smoothing — run as plain `XCTestCase` methods (no `XCUIApplication`, no
/// simulator gestures) so they exercise exactly the same code the app draws with, without needing a
/// real touch/pencil.
///
/// Living in `PaintSoftwareUITests` rather than a dedicated unit-test target, per this repo's
/// engine-rewrite instructions (adding a new unit-test target means `.pbxproj` target/scheme
/// surgery this effort intentionally avoids). A `bundle.ui-testing` product doesn't link against
/// the app binary the way a real unit-test target's `BUNDLE_LOADER`/`TEST_HOST` does (confirmed by
/// trying `@testable import PaintSoftware` here first: it type-checked fine but failed to *link*,
/// "symbol(s) not found for architecture arm64" — the declarations are visible via the app's
/// `.swiftmodule`, but the executable code lives only inside PaintSoftware.app's own Mach-O binary,
/// which nothing else links against). `Engine/Brush.swift` and `Engine/StrokeStabilizer.swift` are
/// therefore compiled a second time directly into *this* target too (see the project file's "Engine
/// sources shared with PaintSoftwareUITests" group and this target's Sources build phase) — both
/// files are pure Foundation/CoreGraphics with no UIKit or other app dependency, so that's a
/// harmless, ordinary multi-target-membership source file, not a fork of the logic. Their types
/// (`Brush`, `BrushDynamics`, `BrushGrain`, `StrokeStabilizer`) are consequently local to this
/// module already — no import needed (and no `@testable import PaintSoftware` either, which would
/// make every one of those names ambiguous between the two copies).
final class BrushEngineLogicTests: XCTestCase {

    // MARK: - BrushDynamics.sizeFraction

    func testSizeFractionIsFixedWhenSizePressureIsZero() {
        let dynamics = BrushDynamics(sizePressure: 0, opacityPressure: 0, minSizeFraction: 0.2)
        // sizePressure == 0 means pressure has no effect at all: fraction should be 1 regardless
        // of how light or hard the touch is.
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 1), 1, accuracy: 0.0001)
    }

    func testSizeFractionSpansMinSizeFractionToOneWhenSizePressureIsMax() {
        let dynamics = BrushDynamics(sizePressure: 1, opacityPressure: 0, minSizeFraction: 0.3)
        // sizePressure == 1: at zero pressure the stamp should shrink to exactly minSizeFraction,
        // and grow linearly up to the full 1.0 at maximum pressure.
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 0), 0.3, accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 0.5), 0.65, accuracy: 0.0001)
    }

    func testSizeFractionIncreasesMonotonicallyWithPressure() {
        let dynamics = BrushDynamics(sizePressure: 0.7, opacityPressure: 0, minSizeFraction: 0.25)
        var previous = dynamics.sizeFraction(forPressure: 0)
        for step in stride(from: 0.1, through: 1.0, by: 0.1) {
            let value = dynamics.sizeFraction(forPressure: step)
            XCTAssertGreaterThanOrEqual(value, previous, "sizeFraction should never decrease as pressure increases")
            previous = value
        }
    }

    func testSizeFractionClampsOutOfRangePressure() {
        let dynamics = BrushDynamics.default
        XCTAssertEqual(dynamics.sizeFraction(forPressure: -5), dynamics.sizeFraction(forPressure: 0), accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 5), dynamics.sizeFraction(forPressure: 1), accuracy: 0.0001)
    }

    // MARK: - BrushDynamics.opacityFraction

    func testOpacityFractionIsFixedWhenOpacityPressureIsZero() {
        let dynamics = BrushDynamics(sizePressure: 0, opacityPressure: 0, minSizeFraction: 1)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 1), 1, accuracy: 0.0001)
    }

    func testOpacityFractionTracksPressureDirectlyWhenOpacityPressureIsMax() {
        let dynamics = BrushDynamics(sizePressure: 0, opacityPressure: 1, minSizeFraction: 1)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 0.4), 0.4, accuracy: 0.0001)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 1), 1, accuracy: 0.0001)
    }

    // MARK: - BrushGrain.noiseValue

    func testGrainNoiseValueIsDeterministicForSamePoint() {
        let a = BrushGrain.noiseValue(atX: 42.5, y: 17.25, scale: 1.2, rotation: 0)
        let b = BrushGrain.noiseValue(atX: 42.5, y: 17.25, scale: 1.2, rotation: 0)
        XCTAssertEqual(a, b, "The same position must always yield the same grain value, or grain would flicker stamp to stamp")
    }

    func testGrainNoiseValueStaysWithinUnitRange() {
        for i in stride(from: 0, to: 500, by: 7) {
            let value = BrushGrain.noiseValue(atX: Double(i) * 3.1, y: Double(i) * -1.7, scale: 1.0, rotation: 0.3)
            XCTAssertGreaterThanOrEqual(value, -0.01, "noiseValue drifted below the expected ~0...1 range at sample \(i)")
            XCTAssertLessThanOrEqual(value, 1.01, "noiseValue drifted above the expected ~0...1 range at sample \(i)")
        }
    }

    // MARK: - StrokeStabilizer

    func testStabilizerWithZeroStabilizationTracksInputExactly() {
        var stabilizer = StrokeStabilizer(stabilization: 0)
        stabilizer.reset(to: CGPoint(x: 0, y: 0))
        let output = stabilizer.update(rawPoint: CGPoint(x: 100, y: 50))
        XCTAssertEqual(output.x, 100, accuracy: 0.0001, "Zero stabilization should snap straight to the raw point")
        XCTAssertEqual(output.y, 50, accuracy: 0.0001)
    }

    func testStabilizerResetSnapsExactlyToTouchDownPoint() {
        var stabilizer = StrokeStabilizer(stabilization: 0.9)
        stabilizer.reset(to: CGPoint(x: 200, y: 300))
        XCTAssertEqual(stabilizer.current?.x, 200)
        XCTAssertEqual(stabilizer.current?.y, 300)
    }

    /// Feeds the same jittery synthetic zigzag through two stabilizers — one with no smoothing, one
    /// heavily smoothed — and asserts the smoothed output has strictly lower variance around the
    /// straight-line trend than the raw input does, i.e. it actually damps the jitter out rather
    /// than just being "different."
    func testHigherStabilizationSmoothsJitterMoreThanRawInput() {
        // A straight-line trend plus a sharp zigzag jitter riding on top of it.
        var rawXs: [CGFloat] = []
        for i in 0..<40 {
            let trend: CGFloat = CGFloat(i) * 5
            let jitter: CGFloat = (i % 2 == 0) ? 8 : -8
            rawXs.append(trend + jitter)
        }

        var unsmoothed = StrokeStabilizer(stabilization: 0)
        var smoothed = StrokeStabilizer(stabilization: 0.85)
        unsmoothed.reset(to: CGPoint(x: rawXs[0], y: 0))
        smoothed.reset(to: CGPoint(x: rawXs[0], y: 0))

        var unsmoothedOutputs: [CGFloat] = []
        var smoothedOutputs: [CGFloat] = []
        for x in rawXs {
            unsmoothedOutputs.append(unsmoothed.update(rawPoint: CGPoint(x: x, y: 0)).x)
            smoothedOutputs.append(smoothed.update(rawPoint: CGPoint(x: x, y: 0)).x)
        }

        func jitterEnergy(_ values: [CGFloat]) -> CGFloat {
            // Sum of squared second differences: large for a sharp zigzag, near zero for a smooth
            // (even if still sloped) line.
            guard values.count > 2 else { return 0 }
            var total: CGFloat = 0
            for i in 1..<(values.count - 1) {
                let secondDiff = values[i + 1] - 2 * values[i] + values[i - 1]
                total += secondDiff * secondDiff
            }
            return total
        }

        let rawJitter = jitterEnergy(unsmoothedOutputs)
        let smoothedJitter = jitterEnergy(smoothedOutputs)
        XCTAssertLessThan(smoothedJitter, rawJitter, "A heavily-stabilized stroke should have far less zigzag jitter than an unsmoothed one")
    }

    /// With higher stabilization, the trailing point should lag further behind the raw input at any
    /// given step along a steady linear motion — the "trails further behind" behavior the stabilizer
    /// is meant to produce.
    func testHigherStabilizationTrailsFurtherBehindRawInput() {
        var lowStabilization = StrokeStabilizer(stabilization: 0.2)
        var highStabilization = StrokeStabilizer(stabilization: 0.8)
        lowStabilization.reset(to: .zero)
        highStabilization.reset(to: .zero)

        var lowLag: CGFloat = 0
        var highLag: CGFloat = 0
        for i in 1...20 {
            let raw = CGPoint(x: CGFloat(i) * 10, y: 0)
            let lowOutput = lowStabilization.update(rawPoint: raw)
            let highOutput = highStabilization.update(rawPoint: raw)
            lowLag = raw.x - lowOutput.x
            highLag = raw.x - highOutput.x
        }
        XCTAssertGreaterThan(highLag, lowLag, "Higher stabilization should trail further behind the raw touch than lower stabilization")
    }

    func testStabilizerEventuallyCatchesUpToAHeldStillPoint() {
        var stabilizer = StrokeStabilizer(stabilization: 0.95)
        stabilizer.reset(to: CGPoint(x: 0, y: 0))
        let target = CGPoint(x: 500, y: 500)
        var last = CGPoint(x: 0, y: 0)
        for _ in 0..<400 {
            last = stabilizer.update(rawPoint: target)
        }
        XCTAssertEqual(last.x, target.x, accuracy: 0.5, "Even maximal stabilization should converge to a held-still point given enough updates, not stall short of it forever")
        XCTAssertEqual(last.y, target.y, accuracy: 0.5)
    }
}
