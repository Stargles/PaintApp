import XCTest
import UIKit
import Darwin

/// The **pre-refactor performance baseline**: drives synthetic strokes through the real brush
/// pipeline and records wall-clock, peak resident memory, and thumbnail-regeneration count.
///
/// Written for Stage 0 of the CanvasManager/CanvasView decomposition so the later performance stage
/// has "before" numbers to compare against. That stage's session will not have this session's test
/// output, so the numbers measured here are also written into the Stage 0 commit message and
/// `SESSION_LOG.md`.
///
/// **These are not tight perf assertions.** Simulator timings swing by large factors with host
/// load, so every assertion here is a generous order-of-magnitude ceiling whose only job is to
/// catch a catastrophic regression (a 10x blow-up, an accidental O(n²), a per-sample thumbnail
/// rasterize). The real output is the `PERF BASELINE` lines printed to the test log — read those,
/// don't tighten these.
///
/// What is being measured is the pipeline the app actually draws with: `StrokeStabilizer` smoothing
/// the raw samples, then `BrushStamper.stampStroke` spacing-interpolating and stamping them into
/// the cel's `RasterLayerTexture`, then `CanvasManager.strokeEnded` regenerating the thumbnail. It
/// deliberately does not include UIKit touch delivery or `CADisplayLink` presentation, which no
/// headless harness can reproduce faithfully.
///
/// See `CanvasManagerTestSupport.swift` for why this compiles as a plain unit test inside the UI
/// test target.
final class PerfBaselineTests: XCTestCase {

    /// The app's real default canvas — measuring against the 64x64 fixture the other tests use
    /// would make the numbers meaningless.
    private static let canvasSize = CGSize(width: 2048, height: 2048)

    /// One "typical stroke": a long diagonal drag across most of the canvas. 500 samples is roughly
    /// what a ~2s Pencil stroke delivers at 240 Hz with coalescing.
    private static let sampleCount = 500

    // MARK: - Measurement plumbing

    /// Resident size of this process, in bytes. `phys_footprint` is what iOS actually holds a
    /// process to (it counts compressed and IOKit-mapped memory), so it is the number worth
    /// baselining rather than `resident_size`.
    private func residentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// Runs `body` on the calling thread while a background thread samples memory every ~2 ms,
    /// returning the wall-clock duration and the highest footprint seen (including before/after
    /// readings, so a stroke shorter than one polling interval still yields a sane number).
    private func measuringPeakMemory(_ body: () -> Void) -> (seconds: Double, peakBytes: UInt64) {
        let peak = Atomic(residentBytes())
        let stop = Atomic(false)
        let sampler = Thread { [self] in
            while !stop.value {
                let sample = residentBytes()
                peak.mutate { $0 = Swift.max($0, sample) }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        sampler.qualityOfService = .userInitiated
        sampler.start()

        let start = CFAbsoluteTimeGetCurrent()
        body()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        stop.value = true
        let final = residentBytes()
        peak.mutate { $0 = Swift.max($0, final) }
        // Give the sampler a moment to notice; it holds no state the test needs afterwards.
        Thread.sleep(forTimeInterval: 0.01)
        return (elapsed, peak.value)
    }

    /// Minimal lock-guarded box — the sampler thread and the test thread both touch these.
    private final class Atomic<Value> {
        private let lock = NSLock()
        private var storage: Value
        init(_ value: Value) { storage = value }
        var value: Value {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); storage = newValue; lock.unlock() }
        }
        /// One locked read-modify-write, so the sampler thread can't lose a sample to the test
        /// thread between a separate get and set.
        func mutate(_ transform: (inout Value) -> Void) {
            lock.lock()
            transform(&storage)
            lock.unlock()
        }
    }

    // MARK: - Fixtures

    private func perfManager() -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = Self.canvasSize
        manager.addLayer(name: "Perf")
        return manager
    }

    /// A diagonal sweep with a pressure ramp, stabilized exactly as live drawing stabilizes it.
    /// `passes` zig-zags corner to corner that many times, multiplying the stroke's *path length*
    /// without changing its sample count — the two turn out to be independent knobs on cost, which
    /// is what `testStrokeCostTracksPathLengthNotSampleCount` below is about.
    private func syntheticStroke(sampleCount: Int, passes: Int = 1,
                                 stabilization: CGFloat = 0.5) -> [BrushStamper.Sample] {
        let size = Self.canvasSize
        let inset: CGFloat = 128
        var stabilizer = StrokeStabilizer(stabilization: stabilization)
        stabilizer.reset(to: CGPoint(x: inset, y: inset))

        var samples: [BrushStamper.Sample] = []
        samples.reserveCapacity(sampleCount)
        for step in 0..<sampleCount {
            let t = CGFloat(step) / CGFloat(max(sampleCount - 1, 1))
            // Walk the diagonal `passes` times, reversing direction each leg.
            let travelled = t * CGFloat(passes)
            let leg = min(floor(travelled), CGFloat(passes) - 1)
            let withinLeg = travelled - leg
            let along = leg.truncatingRemainder(dividingBy: 2) == 0 ? withinLeg : 1 - withinLeg
            let raw = CGPoint(x: inset + (size.width - 2 * inset) * along,
                              y: inset + (size.height - 2 * inset) * along)
            // Pressure ramps up and back down across the stroke, so the size/opacity dynamics and
            // the spacing interpolation both get exercised rather than running at a constant stamp.
            let pressure = 0.15 + 0.85 * sin(t * .pi)
            samples.append(BrushStamper.Sample(point: stabilizer.update(rawPoint: raw), pressure: pressure))
        }
        return samples
    }

    /// One stroke, wrapped in an autorelease pool.
    ///
    /// The pool is not a measurement trick — it is what makes the number *faithful*. Finishing a
    /// stroke regenerates the thumbnail, which calls `RasterLayerTexture.renderToUIImage()` and so
    /// materializes a fresh canvas-sized CGImage (16 MB at 2048x2048). In the app the run loop
    /// drains that every turn; in a test method, without a pool, the temporaries pile up until the
    /// method returns and "memory per stroke" reads as a linear leak that does not exist at
    /// runtime. Measured both ways while writing this: 20 strokes grew ~322 MB unpooled and ~0 MB
    /// pooled.
    private func stamp(_ samples: [BrushStamper.Sample], into manager: CanvasManager, brushSize: CGFloat = 24) {
        autoreleasepool {
            BrushStamper.stampStroke(into: manager.layers[0].cels[0].raster,
                                     samples: samples,
                                     brush: manager.selectedBrush,
                                     color: .black,
                                     brushSize: brushSize,
                                     brushOpacity: manager.brushOpacity)
            manager.strokeEnded(layerIndex: 0, celIndex: 0)
        }
    }

    private func report(_ label: String, _ pairs: [(String, String)]) {
        print("PERF BASELINE | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  "))
    }

    private func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func milliseconds(_ seconds: Double) -> String {
        String(format: "%.1f ms", seconds * 1000)
    }

    // MARK: - The baseline

    /// (a) wall-clock per stroke, (b) peak resident memory during it, (c) thumbnail regenerations.
    func testSyntheticStrokeBaseline() {
        let manager = perfManager()
        let samples = syntheticStroke(sampleCount: Self.sampleCount)

        // One warm-up stroke: first touch of the cel allocates and faults in the 2048x2048 backing
        // bitmap, which would otherwise be charged entirely to the measured stroke.
        stamp(samples, into: manager)

        let thumbnailsBefore = manager.thumbnailRegenerationCount
        let baselineBytes = residentBytes()
        let measured = measuringPeakMemory { stamp(samples, into: manager) }
        let thumbnailRegens = manager.thumbnailRegenerationCount - thumbnailsBefore

        report("single stroke", [
            ("samples", "\(Self.sampleCount)"),
            ("canvas", "\(Int(Self.canvasSize.width))x\(Int(Self.canvasSize.height))"),
            ("wallClock", milliseconds(measured.seconds)),
            ("perSample", milliseconds(measured.seconds / Double(Self.sampleCount))),
            ("footprintBefore", megabytes(baselineBytes)),
            ("peakFootprint", megabytes(measured.peakBytes)),
            ("peakDelta", megabytes(measured.peakBytes > baselineBytes ? measured.peakBytes - baselineBytes : 0)),
            ("thumbnailRegens", "\(thumbnailRegens)"),
        ])

        // Generous ceilings only — see the note at the top of this file.
        XCTAssertLessThan(measured.seconds, 10.0,
                          "A single 500-sample stroke taking over 10s means something is catastrophically wrong, not merely slow")
        XCTAssertLessThan(measured.peakBytes, 3_000_000_000,
                          "Peak footprint for one stroke on a 2048x2048 canvas should stay well under 3 GB")
        XCTAssertEqual(thumbnailRegens, 1,
                       "One completed stroke must trigger exactly one thumbnail rasterize. Per-sample regeneration is the specific regression this guards.")
    }

    /// What a stroke costs is set by how many *dabs* get stamped, and `stampStroke` derives that
    /// from path length ÷ brush spacing — not from how many samples the input happened to carry.
    /// Feeding the same path at 250 and at 1000 samples therefore costs nearly the same.
    ///
    /// Worth having as an explicit test rather than a footnote: it is the reason a naive
    /// "optimization" that thins incoming samples buys nothing, and it means Stage 5 should compare
    /// strokes of equal path length or the comparison is meaningless.
    func testStrokeCostTracksPathLengthNotSampleCount() {
        let manager = perfManager()
        let sparse = syntheticStroke(sampleCount: 250)
        let dense = syntheticStroke(sampleCount: 1000)

        stamp(sparse, into: manager)   // warm-up

        let sparseTime = measuringPeakMemory { stamp(sparse, into: manager) }.seconds
        let denseTime = measuringPeakMemory { stamp(dense, into: manager) }.seconds
        let ratio = denseTime / max(sparseTime, 0.000_001)

        report("same path, 250 vs 1000 samples", [
            ("sparse", milliseconds(sparseTime)),
            ("dense", milliseconds(denseTime)),
            ("ratio", String(format: "%.2fx", ratio)),
        ])

        XCTAssertLessThan(ratio, 3.0,
                          "4x the samples over the same path should cost about the same, because the dab count is unchanged")
    }

    /// The scaling that does matter: 4x the path length is 4x the dabs, so it should cost roughly
    /// 4x. A quadratic blow-up — re-walking the accumulated stroke per segment, say — would show up
    /// here as a far larger ratio while leaving the sample-count test above untouched.
    func testStrokeCostScalesRoughlyLinearlyWithPathLength() {
        let manager = perfManager()
        let short = syntheticStroke(sampleCount: 500, passes: 1)
        let long = syntheticStroke(sampleCount: 500, passes: 4)

        stamp(short, into: manager)   // warm-up

        let shortTime = measuringPeakMemory { stamp(short, into: manager) }.seconds
        let longTime = measuringPeakMemory { stamp(long, into: manager) }.seconds
        let ratio = longTime / max(shortTime, 0.000_001)

        report("scaling 1x -> 4x path length", [
            ("short", milliseconds(shortTime)),
            ("long", milliseconds(longTime)),
            ("ratio", String(format: "%.2fx", ratio)),
            ("idealRatio", "4.00x"),
        ])

        XCTAssertLessThan(ratio, 40,
                          "4x the path costing more than 40x the time indicates superlinear behavior, not simulator noise")
    }

    /// Repeated strokes into the same cel must not accumulate memory — the texture is reused in
    /// place, so footprint should plateau rather than climb with stroke count.
    func testRepeatedStrokesIntoOneCelDoNotAccumulateMemory() {
        let manager = perfManager()
        let samples = syntheticStroke(sampleCount: 200)

        for _ in 0..<5 { stamp(samples, into: manager) }   // warm-up + plateau
        let settled = residentBytes()

        var peak = settled
        var totalSeconds = 0.0
        let strokeCount = 20
        for _ in 0..<strokeCount {
            let measured = measuringPeakMemory { stamp(samples, into: manager) }
            totalSeconds += measured.seconds
            peak = max(peak, measured.peakBytes)
        }
        let after = residentBytes()

        report("20 x 200-sample strokes", [
            ("meanWallClock", milliseconds(totalSeconds / Double(strokeCount))),
            ("footprintSettled", megabytes(settled)),
            ("peakFootprint", megabytes(peak)),
            ("footprintAfter", megabytes(after)),
            ("growth", megabytes(after > settled ? after - settled : 0)),
            ("thumbnailRegens", "\(manager.thumbnailRegenerationCount)"),
        ])

        XCTAssertLessThan(after, settled + 200_000_000,
                          "20 strokes into one already-allocated cel should not add hundreds of MB — that would mean each stroke retains a canvas-sized buffer past its autorelease pool")
    }

    /// The thumbnail path is the expensive part of finishing a stroke (it rasterizes the whole cel),
    /// so it gets its own number. `scheduleThumbnailRegen` is the debounced entry point the app uses
    /// for drags; it must not rasterize synchronously on every call.
    func testThumbnailRegenerationCostAndDebouncing() {
        let manager = perfManager()
        let samples = syntheticStroke(sampleCount: Self.sampleCount)
        stamp(samples, into: manager)

        let before = manager.thumbnailRegenerationCount
        let direct = measuringPeakMemory { manager.strokeEnded(layerIndex: 0, celIndex: 0) }
        let directRegens = manager.thumbnailRegenerationCount - before

        let beforeScheduled = manager.thumbnailRegenerationCount
        let scheduled = measuringPeakMemory {
            for _ in 0..<50 { manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0) }
        }
        let scheduledRegens = manager.thumbnailRegenerationCount - beforeScheduled

        report("thumbnail", [
            ("oneRegen", milliseconds(direct.seconds)),
            ("regensFromOneStrokeEnd", "\(directRegens)"),
            ("50xScheduleCallCost", milliseconds(scheduled.seconds)),
            ("regensFrom50Schedules", "\(scheduledRegens)"),
        ])

        XCTAssertEqual(directRegens, 1)
        XCTAssertEqual(scheduledRegens, 0,
                       "`scheduleThumbnailRegen` is debounced onto the main run loop, so 50 synchronous calls rasterize nothing on the spot")
        XCTAssertLessThan(direct.seconds, 5.0, "One 2048x2048 thumbnail rasterize taking over 5s is a catastrophic regression")
    }
}
