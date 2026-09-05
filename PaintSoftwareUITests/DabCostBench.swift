import XCTest
import UIKit

/// **What one dab costs to compute** — the constant PERFORMANCE.md §11.2 is built on, isolated so it
/// can be re-taken whenever the dab path changes.
///
/// §11.2 MEASURED **3.16 µs a dab** on the owner's iPad and **2.40 µs** in the simulator, over a 480×
/// range of stroke counts, and the whole cost model of the incremental append rests on that being a
/// straight line. BRUSH.md §12 stage 7 puts a modulation matrix on the per-dab path, which is exactly
/// the kind of change that could move it — so this exists to answer "did it?" with a number rather
/// than an opinion.
///
/// **Not a `*LogicTests` file, deliberately**: the fast tier's selector is
/// `LogicTests$|CharacterizationTests$|^PerfBaselineTests$`, so this is not swept into it and cannot
/// contribute a timing flake to a gate. Run it by name:
///
/// ```
/// SIMLOCK_SLOTS=1 tools/simlock.sh xcodebuild test -project PaintSoftware.xcodeproj \
///   -scheme PaintSoftware -destination 'platform=iOS Simulator,id=<udid>' \
///   -only-testing:PaintSoftwareUITests/DabCostBench \
///   -parallel-testing-enabled NO -derivedDataPath build/DerivedData
/// ```
///
/// **It measures the walk, not the rasterizer.** The sink is a `CollectingDabTarget`, so what is timed
/// is the march, the sensor funnel and the matrix — the part stage 7 changed — and not
/// CoreGraphics' gradient fill, which dominates a real render and would swamp the signal. §11.2's own
/// number is the whole re-walk including rasterization, so these are *comparable across builds of this
/// bench* rather than directly against 3.16; the ratio between two builds is the finding.
///
/// A single loose assertion, three orders of magnitude clear of the number, so a busy machine cannot
/// turn a measurement into a red.
final class DabCostBench: XCTestCase {

    private static let canvas = CGSize(width: 2048, height: 2048)

    /// One stroke of the shape §11.2 used: a zig-zag long enough to carry a few hundred dabs.
    private static func stroke(index: Int) -> StrokeSamples {
        var samples: [VectorSample] = []
        let originY = CGFloat(index % 64) * 30 + 20
        for step in 0..<24 {
            let t = CGFloat(step)
            samples.append(VectorSample(x: 40 + t * 80,
                                        y: originY + (step % 2 == 0 ? 0 : 60),
                                        pressure: 0.3 + 0.7 * (t / 23),
                                        deltaTime: step == 0 ? 0 : 0.008,
                                        tiltAltitude: .pi / 3,
                                        tiltAzimuth: CGFloat(step) * 0.2))
        }
        return StrokeSamples(samples, channels: .captured)
    }

    private func measureWalk(_ label: String, brush: Brush, strokes: Int = 400) {
        let corpus = (0..<strokes).map { Self.stroke(index: $0) }
        // One warm pass, so the first-touch allocation faulting §11.2's own first two rows are made of
        // is not what gets reported.
        var dabs = 0
        for samples in corpus {
            let sink = BrushStamper.CollectingDabTarget()
            BrushStamper.stampStroke(into: sink, samples: samples, brush: brush, color: .black,
                                     brushSize: 20, brushOpacity: 1, random: DabRandom(seed: 7))
            dabs += sink.dabs.count
        }
        let start = CFAbsoluteTimeGetCurrent()
        var counted = 0
        for samples in corpus {
            let sink = BrushStamper.CollectingDabTarget()
            BrushStamper.stampStroke(into: sink, samples: samples, brush: brush, color: .black,
                                     brushSize: 20, brushOpacity: 1, random: DabRandom(seed: 7))
            counted += sink.dabs.count
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let perDab = elapsed / Double(counted) * 1_000_000
        print("DABCOST \(label): \(counted) dabs in \(String(format: "%.1f", elapsed * 1000)) ms "
              + "= \(String(format: "%.3f", perDab)) µs/dab")
        XCTAssertLessThan(perDab, 500, "\(label) — a loose sanity bound, not the measurement")
        XCTAssertGreaterThan(dabs, 0)
    }

    /// **What BRUSH.md §2.11's per-stroke buffer costs**, which §13 recorded as unmeasured.
    ///
    /// Two arms over the *same* dabs, into the *same* kind of canvas-sized `RasterLayerTexture`: one
    /// through `stampStroke`, which brackets the walk in a group and so merges it through one
    /// transparency layer; one replaying the dabs it laid, straight in, with no group at all. The
    /// difference between the two is the whole of what the ruling costs — a `CGContext` buffer the
    /// size of the stroke's own painted box, plus the collection of a few hundred `BakedDab`s.
    ///
    /// It is printed rather than asserted against a threshold, for the reason the file header gives:
    /// a timing gate on a shared machine is a flake, and the finding is the *ratio*.
    func testWhatTheStrokeGroupCosts() {
        let brush = BrushLibrary.hardRound
        let corpus = (0..<200).map { Self.stroke(index: $0) }

        func time(grouped: Bool) -> (seconds: Double, dabs: Int) {
            var dabs = 0
            let start = CFAbsoluteTimeGetCurrent()
            for samples in corpus {
                autoreleasepool {
                    let texture = RasterLayerTexture(size: Self.canvas)
                    if grouped {
                        BrushStamper.stampStroke(into: texture, samples: samples, brush: brush,
                                                 color: .black, brushSize: 20, brushOpacity: 0.5,
                                                 random: DabRandom(seed: 7))
                    } else {
                        let walk = BrushStamper.bake(samples: samples, brush: brush, color: .black,
                                                     brushSize: 20, brushOpacity: 0.5,
                                                     random: DabRandom(seed: 7))
                        for dab in walk.dabs {
                            guard case .round(let hardness) = dab.tip else { continue }
                            texture.stampCircle(at: dab.center, radius: dab.radius, color: dab.color,
                                                alpha: dab.alpha, hardness: hardness,
                                                blendMode: dab.blendMode)
                        }
                        dabs += walk.dabs.count
                    }
                }
            }
            return (CFAbsoluteTimeGetCurrent() - start, dabs)
        }

        _ = time(grouped: true)          // warm
        let direct = time(grouped: false)
        let grouped = time(grouped: true)
        let strokes = Double(corpus.count)
        print("DABCOST stroke group: \(corpus.count) strokes at \(direct.dabs / corpus.count) dabs each — "
              + "direct \(String(format: "%.1f", direct.seconds * 1000)) ms, "
              + "grouped \(String(format: "%.1f", grouped.seconds * 1000)) ms, "
              + "overhead \(String(format: "%.1f", (grouped.seconds - direct.seconds) / strokes * 1_000_000)) µs a stroke "
              + "(\(String(format: "%.0f", (grouped.seconds / direct.seconds - 1) * 100))%)")
        XCTAssertGreaterThan(direct.dabs, 0)
    }

    /// The shipped preset, walked as the app walks it. **This is the number to compare across builds**:
    /// two rows of §6's matrix, resolved per dab, where before §12 stage 7 there were two hardcoded
    /// linear blends.
    func testAShippedPresetsPerDabCost() {
        measureWalk("hardRound (2 rows)", brush: BrushLibrary.hardRound)
    }


    /// **The whole re-walk, rasterization included** — the quantity PERFORMANCE.md §11.2's 3.16 µs
    /// (device) / 2.40 µs (simulator) actually names. The `measureWalk` numbers above exclude
    /// CoreGraphics and are for attributing *within* the walk; this one is comparable across builds
    /// **and** to §11.2's own figure.
    func testTheWholeReWalkIncludingRasterization() {
        let corpus = (0..<200).map { Self.stroke(index: $0) }
        let brush = BrushLibrary.hardRound
        func pass() -> (dabs: Int, seconds: Double) {
            let texture = RasterLayerTexture(size: Self.canvas)
            let start = CFAbsoluteTimeGetCurrent()
            for samples in corpus {
                BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: .black,
                                         brushSize: 20, brushOpacity: 1, random: DabRandom(seed: 7))
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let sink = BrushStamper.CollectingDabTarget()
            for samples in corpus {
                BrushStamper.stampStroke(into: sink, samples: samples, brush: brush, color: .black,
                                         brushSize: 20, brushOpacity: 1, random: DabRandom(seed: 7))
            }
            return (sink.dabs.count, elapsed)
        }
        _ = pass()                                   // warm
        let (dabs, seconds) = pass()
        let perDab = seconds / Double(dabs) * 1_000_000
        print("DABCOST re-walk with rasterization: \(dabs) dabs in "
              + "\(String(format: "%.1f", seconds * 1000)) ms = \(String(format: "%.3f", perDab)) µs/dab")
        XCTAssertLessThan(perDab, 500)
    }

    /// The floor: a brush with no rows at all, which is what the matrix costs when nothing modulates.
    func testABrushWithNoModulationsAtAll() {
        var plain = BrushLibrary.hardRound
        plain.dab.size = 1
        plain.dab.flow = 1
        plain.modulations = BrushModulations()
        measureWalk("no rows", brush: plain)
    }

    /// **Attribution: one row, no curve.** The gap between this and `no rows` is what a row costs
    /// before any curve arithmetic — the sensor read, the closure call and whatever ARC traffic
    /// iterating `[BrushModulation]` produces.
    func testOneRowWithNoCurve() {
        var one = BrushLibrary.hardRound
        one.dab.size = 1
        one.dab.flow = 1
        one.modulations = BrushModulations([BrushModulation(.size, .pressure, amount: -0.4)])
        measureWalk("one row, linear curve", brush: one)
    }

    /// **Attribution: two rows, no curves.** Against `hardRound (2 rows)`, whose size row carries a
    /// two-key ramp, this isolates what `AnimationCurve.evaluate` costs on the hot path.
    func testTwoRowsWithNoCurves() {
        var two = BrushLibrary.hardRound
        two.dab.size = 0.6
        two.dab.flow = 0.9
        two.modulations = BrushModulations([BrushModulation(.size, .pressure, amount: 0.4),
                                            BrushModulation(.flow, .pressure, amount: 0.1)])
        measureWalk("two rows, linear curves", brush: two)
    }

    /// A heavily modulated brush — six rows across five sensors — so the marginal cost of a row is
    /// visible rather than inferred.
    func testAHeavilyModulatedBrush() {
        var loaded = BrushLibrary.hardRound
        loaded.modulations = BrushModulations(loaded.modulations.rows + [
            BrushModulation(.scatter, .velocity, amount: 0.3),
            BrushModulation(.spacing, .tiltAngle, amount: 0.05),
            BrushModulation(.size, .random(.scatterAngle, .plain(2)), amount: 0.1),
            BrushModulation(.hardness, .tiltDirection, amount: -0.2)
        ])
        measureWalk("six rows", brush: loaded)
    }

    /// §2.18's dropout, which adds a draw and a comparison per dab and *removes* dabs — so the cost is
    /// reported per dab actually stamped, which is what an artist pays for.
    func testADensityBrush() {
        var sparse = BrushLibrary.hardRound
        sparse.dab.density = 0
        sparse.dab.densityWavelength = 3.5
        sparse.modulations = BrushModulations(sparse.modulations.rows + [.densityFromPressure()])
        measureWalk("density dropout", brush: sparse)
    }

    /// **BRUSH.md §2.28's chain, and this is the number the ruling was accepted on.**
    ///
    /// `Brush.dabValues` was one pass over a flat array of *(input, curve, amount, second)* rows; a
    /// chain makes it a nested walk, and §2.28 says plainly that the cost *"is unmeasured and must be
    /// measured, not assumed"*. Six chains carrying **eleven modules between them**, which is far more
    /// than any shipped preset and more than an artist is likely to build: compare it against
    /// `six rows` above, whose chains carry one module each.
    func testAHeavilyChainedBrush() {
        var chained = BrushLibrary.hardRound
        chained.modulations = BrushModulations([
            BrushModulation(.size, .pressure,
                            modules: [.curveRamp(.ramp(from: 0.4, to: 1)),
                                      .scale(.random(.scatterAngle, .plain(2))),
                                      .curveRamp(.threshold(knee: 0.4))],
                            amount: 0.4),
            BrushModulation(.flow, .pressure,
                            modules: [.curveRamp(.ramp(from: 0.2, to: 1)), .scale(.velocity)],
                            amount: 0.1),
            BrushModulation(.scatter, .velocity,
                            modules: [.scale(.random(.scatterAngle, .plain(1)))], amount: 0.3),
            BrushModulation(.spacing, .tiltAngle,
                            modules: [.curveRamp(.threshold(knee: 0.5))], amount: 0.05),
            BrushModulation(.hardness, .tiltDirection,
                            modules: [.scale(.pressure), .curveRamp(.ramp(from: 0, to: 1))],
                            amount: -0.2),
            BrushModulation(.hue, .random(.scatterAngle, .plain(3)),
                            modules: [.scale(.taper)], amount: 0.1)
        ])
        measureWalk("six chains, eleven modules", brush: chained)
    }

    /// **§2.28's octaves, which are the one part of the chain that costs a *hash* rather than a
    /// multiply.** Each octave is one more `DabRandom.unit` — a splitmix64 avalanche pair and a
    /// smoothstep — so this is the marginal cost of a scale the artist asked for. Three brushes, so
    /// the slope is visible rather than inferred: one octave, four, and the eight the type caps at.
    func testAMultiOctaveRandomiser() {
        for octaves in [1, 4, BrushRandomiser.maximumOctaves] {
            var noisy = BrushLibrary.hardRound
            noisy.modulations = BrushModulations(noisy.modulations.rows + [
                BrushModulation(.size, .random(.scatterAngle,
                                               BrushRandomiser(wavelength: 3.5, octaves: octaves)),
                                amount: 0.2)
            ])
            measureWalk("randomiser, \(octaves) octave\(octaves == 1 ? "" : "s")", brush: noisy)
        }
    }

    /// §6's colour outputs, which are the one thing on this path that can defeat a dab cache — see
    /// `BrushColorShift`. Timed on the walk, so what is reported here is the shift arithmetic alone;
    /// the cache cost lands in the rasterizer and is stated in PERFORMANCE.md rather than measured here.
    func testAColourJitteringBrush() {
        var jittering = BrushLibrary.hardRound
        jittering.modulations = BrushModulations(jittering.modulations.rows + [
            BrushModulation(.hue, .random(.scatterAngle, .plain(1)), amount: 0.2)
        ])
        measureWalk("colour jitter", brush: jittering)
    }
}
