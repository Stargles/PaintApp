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

    /// Emits one measurement line, **twice**: to the console, and as an `XCTAttachment` on the running
    /// test.
    ///
    /// The attachment is the one that actually works. `print` from a test goes to the *simulator's*
    /// console, not to `xcodebuild`'s stdout, and under parallel testing the run happens on a throwaway
    /// clone device that is deleted when the run ends — so by the time anyone looks, the log and the
    /// device that held it are both gone. Every number this file produces was previously readable only
    /// by attaching Xcode to the run while it happened, which is why the recorded baselines have gaps.
    ///
    /// An attachment lands in the `.xcresult` bundle, which survives the run, and comes back out with:
    ///
    /// ```
    /// xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
    /// ```
    ///
    /// `.keepAlways` matters — the default lifetime deletes attachments from passing tests, which is
    /// exactly the case a perf baseline is measured in.
    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "PERF BASELINE | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "PERF BASELINE — \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
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
        // Stage 0 asserted 1 here, because `strokeEnded` rasterized the thumbnail inline. Stage 5.2
        // routed it through the existing 400 ms debounce, so finishing a stroke now queues the regen
        // instead of paying for it — deliberately changed, and the point of the change: that
        // rasterize measured ~4.3 ms against a ~14 ms stroke. The count that matters is still
        // bounded, though, so the original regression this guarded (a regen per sample or per dab)
        // would still fail here: 500 samples must not produce 500 anything.
        XCTAssertEqual(thumbnailRegens, 0,
                       "A completed stroke should queue its thumbnail regen on the debounce, not rasterize inline. Per-sample regeneration is the specific regression this guards.")
        XCTAssertEqual(pumpDebouncedThumbnails(manager), 1,
                       "The queued regen must still actually happen once the debounce fires — deferring it must not lose it")
    }

    /// Spins the main run loop long enough for `CanvasManager`'s 400 ms thumbnail debounce to fire,
    /// and returns how many regenerations it produced. Without this a test can only observe that a
    /// regen was *deferred*, not that it was ever *performed* — which is exactly the bug a careless
    /// debounce introduces.
    @discardableResult
    private func pumpDebouncedThumbnails(_ manager: CanvasManager) -> Int {
        let before = manager.thumbnailRegenerationCount
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        return manager.thumbnailRegenerationCount - before
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

        // The cost of the rasterize itself, measured on the un-debounced entry point so the number
        // stays comparable with Stage 0's. Stage 0 measured this through `strokeEnded`, which was
        // the same thing then; 5.2 moved `strokeEnded` onto the debounce, so measuring it that way
        // now would time an enqueue and report ~0.
        let before = manager.thumbnailRegenerationCount
        let direct = measuringPeakMemory { manager.regenerateThumbnail(layerIndex: 0, celIndex: 0) }
        let directRegens = manager.thumbnailRegenerationCount - before

        let beforeStrokeEnd = manager.thumbnailRegenerationCount
        let strokeEnd = measuringPeakMemory { manager.strokeEnded(layerIndex: 0, celIndex: 0) }
        let strokeEndRegens = manager.thumbnailRegenerationCount - beforeStrokeEnd

        let beforeScheduled = manager.thumbnailRegenerationCount
        let scheduled = measuringPeakMemory {
            for _ in 0..<50 { manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0) }
        }
        let scheduledRegens = manager.thumbnailRegenerationCount - beforeScheduled

        // 50 schedules plus the strokeEnded above all name the same cel, so the whole burst
        // collapses to one render when the debounce finally fires.
        let flushedRegens = pumpDebouncedThumbnails(manager)

        report("thumbnail", [
            ("oneRegen", milliseconds(direct.seconds)),
            ("regensFromOneStrokeEnd", "\(strokeEndRegens)"),
            ("strokeEndCost", milliseconds(strokeEnd.seconds)),
            ("50xScheduleCallCost", milliseconds(scheduled.seconds)),
            ("regensFrom50Schedules", "\(scheduledRegens)"),
            ("regensAfterDebounceFires", "\(flushedRegens)"),
        ])

        XCTAssertEqual(directRegens, 1)
        XCTAssertEqual(strokeEndRegens, 0,
                       "5.2: finishing a stroke queues the regen on the debounce instead of rasterizing inline")
        XCTAssertEqual(scheduledRegens, 0,
                       "`scheduleThumbnailRegen` is debounced onto the main run loop, so 50 synchronous calls rasterize nothing on the spot")
        XCTAssertEqual(flushedRegens, 1,
                       "51 queued regens naming one cel must coalesce to exactly one render, not replay one per call")
        XCTAssertLessThan(direct.seconds, 5.0, "One 2048x2048 thumbnail rasterize taking over 5s is a catastrophic regression")
    }

    // MARK: - Stage 5 additions

    /// **How many strokes stay undoable**, which is what 5.5 is really about.
    ///
    /// `UndoHistory` trims by retained bytes, not step count, so the per-step cost *is* the undo
    /// depth. While a stroke retained two whole-canvas images, `approximateImageCost` charged
    /// `w × h × 4` twice — ~33.6 MB per stroke at 2048², ~128 MB at 4000² — so a 300 MB budget held
    /// about 8 strokes on the default canvas and **two** on a large one, regardless of how small the
    /// strokes were. This fills the budget with many small strokes and asserts they are all still
    /// undoable, which is the assertion the plan asked for: existing tests only check that undo
    /// *works*, never that history *survives*.
    func testManySmallStrokesAllStayUndoableWithinTheBudget() {
        let manager = perfManager()
        let raster = manager.layers[0].cels[0].raster
        let strokeCount = 40
        let brushSize: CGFloat = 24

        for i in 0..<strokeCount {
            autoreleasepool {
                // Small, well-separated strokes: a short 60pt dab-run, the kind of mark a user makes
                // dozens of in a row. Each covers a tiny fraction of the 2048² canvas.
                let y = 64 + CGFloat(i % 30) * 60
                let x = 64 + CGFloat(i / 30) * 400
                let samples = [BrushStamper.Sample(point: CGPoint(x: x, y: y), pressure: 0.8),
                               BrushStamper.Sample(point: CGPoint(x: x + 60, y: y), pressure: 0.8)]
                let before = (image: raster.renderToUIImage(), count: raster.strokeCount)
                raster.beginStroke()
                BrushStamper.stampStroke(into: raster, samples: samples, brush: manager.selectedBrush,
                                         color: .black, brushSize: brushSize,
                                         brushOpacity: manager.brushOpacity)
                raster.endStroke()
                let after = (image: raster.renderToUIImage(), count: raster.strokeCount)
                recordCroppedStrokeUndo(manager: manager, raster: raster, from: before, to: after)
            }
        }

        // Count the stroke steps specifically: `perfManager()`'s `addLayer` records an "Add Layer"
        // step of its own, which is real history but not what this test is measuring.
        let strokeSteps = manager.history.undoStack.filter { $0.name == "Stroke" }
        let totalCost = strokeSteps.reduce(0) { $0 + $1.cost }
        let perStroke = totalCost / max(strokeSteps.count, 1)
        let wholeCanvasCost = 2 * Int(Self.canvasSize.width) * Int(Self.canvasSize.height) * 4
        let stepsAtOldCost = manager.history.maxCost / wholeCanvasCost

        report("undo budget", [
            ("strokesRecorded", "\(strokeCount)"),
            ("strokeStepsStillUndoable", "\(strokeSteps.count)"),
            ("totalStepsIncludingAddLayer", "\(manager.history.undoStack.count)"),
            ("budget", megabytes(UInt64(manager.history.maxCost))),
            ("totalRetained", megabytes(UInt64(totalCost))),
            ("perStrokeBytes", "\(perStroke)"),
            ("wholeCanvasCostPerStroke", megabytes(UInt64(wholeCanvasCost))),
            ("stepsAtWholeCanvasCost", "\(stepsAtOldCost)"),
        ])

        XCTAssertEqual(strokeSteps.count, strokeCount,
                       "All \(strokeCount) small strokes should still be undoable. Whole-canvas snapshots would have evicted all but \(stepsAtOldCost) of them.")
        XCTAssertLessThan(perStroke, wholeCanvasCost / 4,
                          "A small stroke's undo step must cost far less than a whole-canvas pair, or the crop isn't actually shrinking what is retained")
        XCTAssertGreaterThan(strokeCount, stepsAtOldCost,
                             "This test is only meaningful if the old representation would genuinely have overflowed the budget")

        // The other end of the range, reported so the win isn't overstated: cropping helps in
        // proportion to how *localised* a stroke is, and a single sweep across the whole canvas has a
        // canvas-sized bounding box, so its step still costs roughly what every step used to.
        let sweepBefore = (image: raster.renderToUIImage(), count: raster.strokeCount)
        raster.beginStroke()
        BrushStamper.stampStroke(into: raster, samples: syntheticStroke(sampleCount: Self.sampleCount),
                                 brush: manager.selectedBrush, color: .black,
                                 brushSize: brushSize, brushOpacity: manager.brushOpacity)
        raster.endStroke()
        let sweepAfter = (image: raster.renderToUIImage(), count: raster.strokeCount)
        recordCroppedStrokeUndo(manager: manager, raster: raster, from: sweepBefore, to: sweepAfter)
        let sweepCost = manager.history.undoStack.last?.cost ?? 0

        report("undo budget, canvas-spanning stroke", [
            ("sweepStepCost", megabytes(UInt64(sweepCost))),
            ("wholeCanvasCostPerStroke", megabytes(UInt64(wholeCanvasCost))),
            ("smallStrokeBytes", "\(perStroke)"),
        ])
        XCTAssertLessThanOrEqual(sweepCost, wholeCanvasCost + 1_000_000,
                                 "Even a canvas-spanning stroke must not cost *more* than the whole-canvas pair it replaced")

        // And the history still works: unwind all of it.
        var undone = 0
        while manager.history.canUndo {
            manager.history.undo()
            undone += 1
        }
        XCTAssertEqual(undone, manager.history.redoStack.count,
                       "Every retained step should undo cleanly and land on the redo stack")
        XCTAssertGreaterThanOrEqual(undone, strokeCount,
                                    "At minimum every stroke step should have undone")
    }

    /// The crop/restore round trip is pixel-exact — undo removes the stroke completely and redo puts
    /// it back, over the whole canvas and not just inside the patch.
    ///
    /// This is the correctness half of 5.5, and the failure it guards is silent: a patch composited
    /// instead of copied would leave the stroke's ink behind on undo, and an off-by-one origin would
    /// restore it a pixel over. Both would leave "undo works" passing while the canvas is wrong.
    func testCroppedUndoRestoresTheCanvasExactly() {
        let manager = perfManager()
        let raster = manager.layers[0].cels[0].raster

        // Lay down a first stroke and keep its pixels as the reference state to return to.
        raster.beginStroke()
        BrushStamper.stampStroke(into: raster,
                                 samples: [BrushStamper.Sample(point: CGPoint(x: 200, y: 200), pressure: 1),
                                           BrushStamper.Sample(point: CGPoint(x: 400, y: 260), pressure: 1)],
                                 brush: manager.selectedBrush, color: .black,
                                 brushSize: 30, brushOpacity: 1)
        raster.endStroke()
        let reference = alphaFingerprint(raster)

        // Second stroke, recorded the way 5.5 records one.
        let before = (image: raster.renderToUIImage(), count: raster.strokeCount)
        raster.beginStroke()
        BrushStamper.stampStroke(into: raster,
                                 samples: [BrushStamper.Sample(point: CGPoint(x: 900, y: 700), pressure: 1),
                                           BrushStamper.Sample(point: CGPoint(x: 1300, y: 1100), pressure: 1)],
                                 brush: manager.selectedBrush, color: .black,
                                 brushSize: 30, brushOpacity: 1)
        raster.endStroke()
        let after = (image: raster.renderToUIImage(), count: raster.strokeCount)
        let painted = alphaFingerprint(raster)
        XCTAssertNotEqual(painted, reference, "The second stroke should actually have changed the canvas")

        recordCroppedStrokeUndo(manager: manager, raster: raster, from: before, to: after)

        manager.history.undo()
        XCTAssertEqual(alphaFingerprint(raster), reference,
                       "Undo must restore the canvas exactly, leaving none of the second stroke behind — a composited patch instead of a copied one would leave its ink")
        XCTAssertEqual(raster.strokeCount, before.count, "Undo restores the stroke count with the pixels")

        manager.history.redo()
        XCTAssertEqual(alphaFingerprint(raster), painted, "Redo must reproduce the stroke exactly")
        XCTAssertEqual(raster.strokeCount, after.count)
    }

    /// A stroke running past the canvas edge: the dirty rect is clamped, so the patch origin has to
    /// be the clamped one or the restore lands offset. Undo still has to be exact.
    func testCroppedUndoIsExactForAStrokeOverTheCanvasEdge() {
        let manager = perfManager()
        let raster = manager.layers[0].cels[0].raster
        let reference = alphaFingerprint(raster)

        let before = (image: raster.renderToUIImage(), count: raster.strokeCount)
        raster.beginStroke()
        // Starts off the top-left corner and runs inward, so the dab bounds go negative.
        BrushStamper.stampStroke(into: raster,
                                 samples: [BrushStamper.Sample(point: CGPoint(x: -20, y: -20), pressure: 1),
                                           BrushStamper.Sample(point: CGPoint(x: 120, y: 120), pressure: 1)],
                                 brush: manager.selectedBrush, color: .black,
                                 brushSize: 40, brushOpacity: 1)
        raster.endStroke()
        let after = (image: raster.renderToUIImage(), count: raster.strokeCount)
        XCTAssertNotEqual(alphaFingerprint(raster), reference, "The edge stroke should have marked the canvas")

        recordCroppedStrokeUndo(manager: manager, raster: raster, from: before, to: after)
        manager.history.undo()
        XCTAssertEqual(alphaFingerprint(raster), reference,
                       "Undo of a stroke crossing the canvas edge must still restore exactly — a patch written at the unclamped origin would land offset")
    }

    /// Mirrors `StrokeCanvasView.registerRasterUndo`'s cropped representation. `StrokeCanvasView` is a
    /// `UIView` driven by real touches, so it can't be exercised headlessly; this reproduces the same
    /// three steps (crop to the dirty rect, clamp the origin, restore with `.copy`) against the same
    /// engine API, so the engine support and the byte accounting are what's under test.
    private func recordCroppedStrokeUndo(manager: CanvasManager, raster: RasterLayerTexture,
                                         from: (image: UIImage, count: Int), to: (image: UIImage, count: Int)) {
        guard let dirty = raster.strokeDirtyRect else {
            return XCTFail("A stroke that stamped dabs must report a dirty rect")
        }
        let rect = dirty.insetBy(dx: -1, dy: -1).integral
        guard let beforePatch = PixelOps.copiedSubimage(of: from.image, in: rect),
              let afterPatch = PixelOps.copiedSubimage(of: to.image, in: rect) else {
            return XCTFail("Cropping the stroke's region should succeed")
        }
        let origin = rect.intersection(CGRect(origin: .zero, size: from.image.size)).origin
        let beforeCount = from.count, afterCount = to.count
        let cost = CanvasManager.approximateImageCost(beforePatch) + CanvasManager.approximateImageCost(afterPatch)
        manager.recordUndo(name: "Stroke", cost: cost, undo: {
            raster.restore(patch: beforePatch, at: origin)
            raster.setStrokeCount(beforeCount)
        }, redo: {
            raster.restore(patch: afterPatch, at: origin)
            raster.setStrokeCount(afterCount)
        })
    }

    /// A cheap whole-canvas content signature: per-row sums of the alpha channel. Sensitive to any
    /// pixel changing anywhere, including outside whatever region a patch covered, without holding a
    /// second full copy of the canvas to diff against.
    private func alphaFingerprint(_ raster: RasterLayerTexture) -> [Int] {
        autoreleasepool {
            guard let cg = raster.renderToUIImage().cgImage else { return [] }
            let width = cg.width, height = cg.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: PixelOps.deviceRGBColorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard ok else { return [] }
            var rows = [Int](repeating: 0, count: height)
            for y in 0..<height {
                var sum = 0
                let base = y * width * 4
                for x in 0..<width { sum += Int(bytes[base + x * 4 + 3]) }
                rows[y] = sum
            }
            return rows
        }
    }

    /// Baking a snapped shape is idempotent, which is what makes the two-finger-transform path cheap
    /// without needing a per-gesture flag to guard it.
    ///
    /// Item 5.4 of the Stage 5 plan described `commitSnappedShapeIfTransforming` as baking the shape
    /// "on every single `.changed` frame during a two-finger transform, combined with an
    /// `objectWillChange.send()` per frame", and asked for a boolean reset on `.began` so it bakes
    /// once. That is not what the code does. `commitInteractiveShape` opens with
    /// `guard shapeGestureActive, let shape = resolvedShape else { return }` and clears
    /// `shapeGestureActive` on the way through, and its `objectWillChange.send()` sits in a `defer`
    /// that is only reached past that guard — so the bake and the publish both happen exactly once
    /// however many times the frame handler calls them. `commitSnappedShapeIfTransforming`'s own
    /// guard (`isShapeInAdjustableState && isShapeConstraintEngaged`) then also fails on every later
    /// frame, since committing clears both.
    ///
    /// This test is here so that stays true. It drives the real state machine — begin a shape, lift
    /// the pen into the adjustable state, then commit 50 times the way 50 `.changed` frames would —
    /// and asserts one stroke lands, not 50. A regression that made the bake re-entrant would show up
    /// as 50 overlapping strokes on the layer and 50 undo steps, which is exactly the shape of bug
    /// the plan was worried about.
    func testCommittingASnappedShapeRepeatedlyBakesItExactlyOnce() {
        let manager = perfManager()
        manager.addVectorLayer(name: "Shape")
        manager.currentLayerIndex = manager.layers.count - 1
        let celIndex = 0
        XCTAssertNotNil(manager.layers[manager.currentLayerIndex].cels[celIndex].vector,
                        "A vector layer's cel should carry a VectorCanvas for the shape to bake into")

        let geometry = ShapeGeometry(kind: .oval,
                                     startPoint: CGPoint(x: 200, y: 200),
                                     endPoint: CGPoint(x: 800, y: 600),
                                     rotation: 0)
        var samples: [VectorSample] = []
        for step in 0..<80 {
            let t = CGFloat(step) / 79
            samples.append(VectorSample(x: 200 + 600 * t, y: 200 + 400 * t, pressure: 1))
        }
        manager.beginInteractiveShape(geometry, samples: samples)
        XCTAssertTrue(manager.shapeGestureActive)

        // The snap engages, then the pen lifts — the state `commitSnappedShapeIfTransforming`
        // requires (`isShapeInAdjustableState && isShapeConstraintEngaged`) before it will bake.
        manager.updateInteractiveShape(isConstrained: true)
        manager.endInteractiveShape()
        XCTAssertTrue(manager.isShapeInAdjustableState,
                      "Lifting the pen should leave the shape adjustable — the state a two-finger transform then bakes")

        let layerIndex = manager.currentLayerIndex
        let strokesBefore = manager.layers[layerIndex].cels[celIndex].vector?.strokes.count ?? 0
        for _ in 0..<50 { manager.commitInteractiveShape() }
        let strokesAfter = manager.layers[layerIndex].cels[celIndex].vector?.strokes.count ?? 0

        report("snapped shape commit", [
            ("commitCalls", "50"),
            ("strokesAdded", "\(strokesAfter - strokesBefore)"),
            ("shapeStillActive", "\(manager.shapeGestureActive)"),
        ])

        XCTAssertEqual(strokesAfter - strokesBefore, 1,
                       "50 commit calls must add exactly one stroke. More than one means the bake became re-entrant and every transform frame is now laying down another copy.")
        XCTAssertFalse(manager.shapeGestureActive,
                       "The first commit ends the shape gesture, which is what makes every later call a no-op")
    }

    /// `VectorCanvas.render()` — the path 5.3 changed. It used to allocate a canvas-sized throwaway
    /// `RasterLayerTexture`, stamp into it, `makeImage()` a second canvas-sized copy out, blit that
    /// in, and drop both, once per visible vector layer per invalidation. Now the strokes go straight
    /// into the renderer's own context.
    ///
    /// Memory is measured inside `autoreleasepool` for the reason `stamp` documents: without it, the
    /// canvas-sized CGImages this path materializes read as a leak that the app's run loop would
    /// never actually show.
    func testVectorLayerRenderCostAndMemory() {
        let strokeCount = 20
        var strokes: [VectorStroke] = []
        for i in 0..<strokeCount {
            let offset = CGFloat(i) * 90
            var samples: [VectorSample] = []
            for step in 0..<60 {
                let t = CGFloat(step) / 59
                samples.append(VectorSample(x: 128 + t * 1700,
                                            y: 128 + offset.truncatingRemainder(dividingBy: 1700),
                                            pressure: 0.2 + 0.8 * sin(t * .pi)))
            }
            strokes.append(VectorStroke(brush: Brush(name: "Perf", shape: .softRound, size: 24),
                                        color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                        size: 24, opacity: 1, samples: samples))
        }

        // Warm-up render: faults in the first bitmap so its cost isn't charged to the measured one.
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: strokes).render() }

        let canvas = VectorCanvas(size: Self.canvasSize, strokes: strokes)
        let baseline = residentBytes()
        let measured = measuringPeakMemory {
            autoreleasepool { _ = canvas.render() }
        }

        // A second render must be free — it is cached by version.
        let cached = measuringPeakMemory { autoreleasepool { _ = canvas.render() } }

        report("vector layer render", [
            ("strokes", "\(strokeCount)"),
            ("canvas", "\(Int(Self.canvasSize.width))x\(Int(Self.canvasSize.height))"),
            ("firstRender", milliseconds(measured.seconds)),
            ("cachedRender", milliseconds(cached.seconds)),
            ("footprintBefore", megabytes(baseline)),
            ("peakFootprint", megabytes(measured.peakBytes)),
            ("peakDelta", megabytes(measured.peakBytes > baseline ? measured.peakBytes - baseline : 0)),
        ])

        XCTAssertLessThan(measured.seconds, 10.0,
                          "Rendering 20 vector strokes taking over 10s is a catastrophic regression, not slowness")
        XCTAssertLessThan(cached.seconds, measured.seconds,
                          "The second render must come from the version cache, not re-stamp every stroke")
    }

    // MARK: - Vector eraser (plan §6/§8)

    /// The erase-heavy half of the measurement above: **200 strokes on a layer, 50 erase gestures**,
    /// committed through the real `VectorCanvas.erase(…, mode: .erase)`.
    ///
    /// A sibling of `testVectorLayerRenderCostAndMemory` rather than more code inside it, deliberately.
    /// That test's "20 strokes, first render" figure is a cross-stage series — Stage 0 through 5.3 are
    /// all recorded against it in `REFACTOR_BASELINE.md` — and folding a second, much heavier scene into
    /// the same method would change what that number means. This one measures a different thing (commit
    /// cost, not render cost) and gets its own row.
    ///
    /// What the numbers are *for*: Phase 4d added `splitCleanlyErasedStrokes`, which runs immediately
    /// after `removeFullyErasedStrokes` over the same candidate strokes. Whether those two passes should
    /// become one is a live question, and it was never going to be answerable by reading them. So the
    /// second `report` line below breaks the gesture down into the pieces a merge would and would not
    /// remove — the spatial-index rebuild each `invalidate()` forces, versus the clean-cut probe walk —
    /// because those two have very different sizes and the obvious guess about which dominates is wrong.
    func testEraseHeavyVectorLayerCostAndMemory() {
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.eraseScenePaintStrokes())
        let elementsBefore = canvas.elements.count

        // Warm-up: the first erase on a fresh canvas builds the spatial index from cold and faults in
        // the geometry, which would otherwise be charged entirely to gesture 0.
        _ = autoreleasepool {
            canvas.erase(alongPath: Self.eraseSceneGesture(0), brush: Self.eraseSceneEraserBrush,
                         size: Self.eraseSceneEraserSize, mode: .erase)
        }

        let baseline = residentBytes()
        var committed = 0
        var perGesture: [Double] = []
        let measured = measuringPeakMemory {
            for g in 1..<Self.eraseSceneGestureCount {
                autoreleasepool {
                    let start = CFAbsoluteTimeGetCurrent()
                    let changed = canvas.erase(alongPath: Self.eraseSceneGesture(g),
                                               brush: Self.eraseSceneEraserBrush,
                                               size: Self.eraseSceneEraserSize, mode: .erase)
                    perGesture.append(CFAbsoluteTimeGetCurrent() - start)
                    if changed { committed += 1 }
                }
            }
        }
        let gestures = Self.eraseSceneGestureCount - 1

        // The *trend*, which is what separates a fixed per-gesture cost from one that scales with what
        // the layer has accumulated. Every pass in `eraseHybrid` except `collectResidueGarbage` is
        // bounded by the spatial index and so should not care how many gestures came before; GC is not
        // — it rescans every retained punch against every element beneath it, on every erase. If the
        // last ten gestures cost markedly more than the first ten, that is where it is going.
        let firstTen = perGesture.prefix(10).reduce(0, +) / 10
        let lastTen = perGesture.suffix(10).reduce(0, +) / 10

        let strokes = canvas.strokes
        let paintPieces = strokes.filter { $0.composite == .paint }.count
        let punches = strokes.filter { $0.composite == .erase }.count
        let pieces = strokes.filter { $0.composite == .paint && $0.lattice != nil }.count

        // The layer the user is now looking at: 200 strokes cut into pieces, plus the punches. Rendering
        // it is the cost every later invalidation pays, so it is the number that says whether the split
        // made the layer more expensive to draw.
        let renderAfter = measuringPeakMemory { autoreleasepool { _ = canvas.render() } }

        report("erase-heavy vector layer", [
            ("paintStrokesBefore", "\(elementsBefore)"),
            ("gestures", "\(gestures)"),
            ("gesturesThatChangedTheList", "\(committed)"),
            ("totalEraseTime", milliseconds(measured.seconds)),
            ("perGesture", milliseconds(measured.seconds / Double(max(gestures, 1)))),
            ("meanOfFirstTen", milliseconds(firstTen)),
            ("meanOfLastTen", milliseconds(lastTen)),
            ("lastTenOverFirstTen", String(format: "%.2fx", lastTen / max(firstTen, 0.000_001))),
            ("elementsAfter", "\(canvas.elements.count)"),
            ("paintStrokesAfter", "\(paintPieces)"),
            ("ofWhichAreSplitPieces", "\(pieces)"),
            ("retainedPunches", "\(punches)"),
            ("renderAfterErasing", milliseconds(renderAfter.seconds)),
            ("footprintBefore", megabytes(baseline)),
            ("peakFootprint", megabytes(measured.peakBytes)),
            ("peakDelta", megabytes(measured.peakBytes > baseline ? measured.peakBytes - baseline : 0)),
        ])

        reportEraseGestureBreakdown()

        XCTAssertGreaterThan(pieces, 0,
                             "This scenario is only measuring what it claims to if the split actually fires — a 32pt eraser crossing a 24pt line squarely is the case `splitCleanlyErasedStrokes` exists for")
        XCTAssertLessThan(measured.seconds, 120.0,
                          "50 erase gestures over a 200-stroke layer taking minutes means an accidental quadratic, not slowness")
        XCTAssertLessThan(renderAfter.seconds, 30.0,
                          "Rendering the erased layer taking over 30s is a catastrophic regression, not slowness")
    }

    /// Where one gesture's time goes, in the two terms that decide whether the deletion and split
    /// passes should be merged into one.
    ///
    /// `eraseHybrid` calls `invalidate()` between the two passes, which bumps `version` and so throws
    /// away `VectorCanvas`'s cached `StrokeSpatialIndex`; the split pass then rebuilds it over every
    /// segment on the layer, and `hasResidue`'s backdrop probe rebuilds it a third time after the
    /// split's own `invalidate()`. That rebuild is the cost a merge removes. The clean-cut probe walk
    /// is the cost it does *not* remove, because `isEntirelyCovered` short-circuits on two cheap cap
    /// tests before it ever reaches `cleanCutRanges` — so for a stroke being **split** rather than
    /// deleted, the walk only ever ran once to begin with.
    private func reportEraseGestureBreakdown() {
        let strokes = Self.eraseScenePaintStrokes()
        let eraserSamples = Self.eraseSceneGesture(7)
        guard let sweep = VectorEraser.Sweep(samples: eraserSamples, brush: Self.eraseSceneEraserBrush,
                                             size: Self.eraseSceneEraserSize, mode: .erase) else {
            return XCTFail("The scenario's eraser gesture must have a footprint")
        }
        let erasers = VectorEraser.cleanCutCapsules(sweep.capsules, brush: Self.eraseSceneEraserBrush,
                                                    size: Self.eraseSceneEraserSize)

        // One index build over the whole layer — the unit `invalidate()` makes the eraser pay again.
        let indexBuild = measuringPeakMemory {
            let index = StrokeSpatialIndex()
            for (elementIndex, stroke) in strokes.enumerated() {
                index.insert(samples: stroke.samples, elementIndex: elementIndex)
            }
            _ = index.segments(near: sweep.bounds)
        }.seconds

        let index = StrokeSpatialIndex()
        for (elementIndex, stroke) in strokes.enumerated() {
            index.insert(samples: stroke.samples, elementIndex: elementIndex)
        }
        let reach = strokes.map {
            StrokeGeometry.stampRadius(forPressure: 1, brush: $0.brush, size: $0.size)
        }.max() ?? 0
        let candidates = Set(index.segments(near: sweep.bounds.insetBy(dx: -reach, dy: -reach))
            .map(\.elementIndex)).sorted()

        // What one pass over the candidates costs, split into the two things the passes actually do.
        let coverageTest = measuringPeakMemory {
            for i in candidates {
                _ = VectorEraser.isEntirelyCovered(strokes[i].samples, brush: strokes[i].brush,
                                                   size: strokes[i].size, by: erasers, sweep: sweep)
            }
        }.seconds
        let cleanWalk = measuringPeakMemory {
            for i in candidates {
                _ = VectorEraser.cleanCutRanges(in: strokes[i].samples, brush: strokes[i].brush,
                                                size: strokes[i].size, by: erasers, sweep: sweep)
            }
        }.seconds

        report("erase gesture breakdown", [
            ("layerSegments", "\(strokes.reduce(0) { $0 + max($1.samples.count - 1, 0) })"),
            ("candidateStrokes", "\(candidates.count)"),
            ("oneSpatialIndexBuild", milliseconds(indexBuild)),
            ("isEntirelyCoveredOverCandidates", milliseconds(coverageTest)),
            ("cleanCutRangesOverCandidates", milliseconds(cleanWalk)),
        ])
    }

    // MARK: - The erase-heavy scene

    private static let eraseSceneStrokeCount = 200
    private static let eraseSceneGestureCount = 50
    private static let eraseSceneEraserSize: CGFloat = 32

    /// Hard, opaque, unjittered — the gate `VectorEraser.supportsCleanCut` requires before any
    /// geometry is removed at all. A soft or partial-opacity eraser would exercise only the punch and
    /// measure none of what this test is about.
    private static let eraseSceneEraserBrush = Brush(name: "PerfEraser", shape: .hardRound, size: 32,
                                                     hardness: 1)

    /// 200 horizontal 24pt lines, in 4 columns of 50 rows 40pt apart. Wider than the rows are tall,
    /// so a vertical gesture crosses several of them squarely — the full-width crossing that
    /// `splitCleanlyErasedStrokes` cuts, rather than the shave that only the punch can express.
    private static func eraseScenePaintStrokes() -> [VectorStroke] {
        let brush = Brush(name: "PerfPaint", shape: .hardRound, size: 24, hardness: 1)
        var strokes: [VectorStroke] = []
        strokes.reserveCapacity(eraseSceneStrokeCount)
        for i in 0..<eraseSceneStrokeCount {
            let x0 = 100 + CGFloat(i / 50) * 480
            let y = 60 + CGFloat(i % 50) * 40
            var samples: [VectorSample] = []
            samples.reserveCapacity(60)
            for step in 0..<60 {
                samples.append(VectorSample(x: x0 + CGFloat(step) / 59 * 400, y: y, pressure: 1))
            }
            strokes.append(VectorStroke(brush: brush,
                                        color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                        size: 24, opacity: 1, samples: samples))
        }
        return strokes
    }

    /// Gesture `g`: a 150pt vertical drag down the middle of one column, crossing about four rows.
    /// Consecutive bands in a column abut rather than overlap, so the 50 gestures between them reach
    /// most of the layer instead of re-erasing one place — which would measure garbage collection and
    /// stacked punches rather than the split.
    private static func eraseSceneGesture(_ g: Int) -> [VectorSample] {
        let x = 100 + CGFloat(g % 4) * 480 + 200
        let y0 = 40 + CGFloat(g / 4) * 150
        return (0..<9).map { step in
            VectorSample(x: x, y: y0 + CGFloat(step) / 8 * 150, pressure: 1)
        }
    }

    /// The debounce coalesces per *cel*, not down to a single cel.
    ///
    /// `.debounce` forwards only the last element it saw, so while the subject carried the
    /// `(layerIndex, celIndex)` itself, queueing two different cels inside the 400 ms window
    /// regenerated the second and silently left the first with a stale thumbnail. 5.2 moved the
    /// identities into a pending set so the sink drains all of them; without that fix, routing the
    /// per-stroke path through the debounce would have turned a rare bug into an everyday one.
    func testDebouncedRegensCoalescePerCelRatherThanDroppingAllButTheLast() {
        let manager = perfManager()
        manager.addLayer(name: "Perf B")
        XCTAssertEqual(manager.layers.count, 2, "Fixture should have given us two layers to schedule against")

        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)
        manager.scheduleThumbnailRegen(layerIndex: 1, celIndex: 0)
        XCTAssertEqual(pumpDebouncedThumbnails(manager), 2,
                       "Two distinct cels queued inside one debounce window must both be regenerated — dropping all but the last leaves a permanently stale thumbnail")

        // And the same cel queued repeatedly still collapses to one.
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)
        manager.scheduleThumbnailRegen(layerIndex: 0, celIndex: 0)
        XCTAssertEqual(pumpDebouncedThumbnails(manager), 1,
                       "Repeated schedules for one cel should still coalesce to a single render")
    }

    /// A queued regen names a cel by identity, so a structural edit that renumbers indices in the
    /// meantime cannot make the flush render the wrong cel — it renders the right one, or nothing if
    /// that cel is gone. Deleting the *lower* layer shifts the queued layer's index from 1 to 0,
    /// which under the old index-based queue would have rendered whatever now sits at index 1.
    func testQueuedRegenFollowsTheCelThroughAnIndexShift() {
        let manager = perfManager()
        manager.addLayer(name: "Perf B")
        let targetLayerID = manager.layers[1].id

        manager.scheduleThumbnailRegen(layerIndex: 1, celIndex: 0)
        manager.deleteLayer(at: 0)
        XCTAssertEqual(manager.layers.count, 1)
        XCTAssertEqual(manager.layers[0].id, targetLayerID, "The queued layer should now be at index 0")

        XCTAssertEqual(pumpDebouncedThumbnails(manager), 1,
                       "The queued cel still exists at a new index, so its thumbnail should still be rendered")
        XCTAssertNotNil(manager.layers[0].cels[0].thumbnail,
                        "...and the thumbnail that got rendered should be the surviving cel's own")
    }

    /// A cel deleted before the debounce fires is dropped rather than rendering something arbitrary.
    func testQueuedRegenForADeletedCelIsDropped() {
        let manager = perfManager()
        manager.addLayer(name: "Perf B")

        manager.scheduleThumbnailRegen(layerIndex: 1, celIndex: 0)
        manager.deleteLayer(at: 1)
        XCTAssertEqual(pumpDebouncedThumbnails(manager), 0,
                       "A queued regen whose cel no longer exists should resolve to nothing, not render a different cel")
    }

    /// `stampCircle` memoizes its radial gradient instead of building one per dab. A cache is only
    /// worth having if it actually hits, and the hit rate here is not self-evident: the naive key
    /// (colour *and* per-dab alpha) would hit essentially never, because alpha is
    /// `brushOpacity × flow × opacityFraction(pressure)` and pressure varies continuously along a
    /// stroke. The implementation therefore keys on colour and hardness only and applies alpha via
    /// `CGContext.setAlpha`. This test measures the rate rather than trusting that reasoning — a
    /// future change that puts a per-dab term back into the key would leave every other test passing
    /// and show up only as the number printed here collapsing.
    func testDabGradientCacheHitRate() {
        let manager = perfManager()
        let texture = manager.layers[0].cels[0].raster
        let samples = syntheticStroke(sampleCount: Self.sampleCount)

        stamp(samples, into: manager)
        let hitsAfterFirst = texture.dabGradientCacheHits
        let missesAfterFirst = texture.dabGradientCacheMisses

        // A second stroke at the same brush settings should be pure hits: the entry is already there.
        stamp(samples, into: manager)
        let secondStrokeHits = texture.dabGradientCacheHits - hitsAfterFirst
        let secondStrokeMisses = texture.dabGradientCacheMisses - missesAfterFirst

        let total = texture.dabGradientCacheHits + texture.dabGradientCacheMisses
        let rate = total > 0 ? Double(texture.dabGradientCacheHits) / Double(total) : 0

        report("dab gradient cache", [
            ("dabsTotal", "\(total)"),
            ("hits", "\(texture.dabGradientCacheHits)"),
            ("misses", "\(texture.dabGradientCacheMisses)"),
            ("hitRate", String(format: "%.1f%%", rate * 100)),
            ("firstStrokeMisses", "\(missesAfterFirst)"),
            ("secondStrokeHits", "\(secondStrokeHits)"),
            ("secondStrokeMisses", "\(secondStrokeMisses)"),
        ])

        XCTAssertEqual(missesAfterFirst, 1,
                       "A stroke is one colour at one hardness, so it should miss exactly once — on its first dab — and hit for every dab after that. More than one miss means a per-dab term (alpha, radius, position) has leaked into the cache key.")
        XCTAssertEqual(secondStrokeMisses, 0,
                       "A second stroke with identical brush settings must not rebuild the gradient at all")
        XCTAssertGreaterThan(rate, 0.99,
                             "The cache exists to serve the overwhelming majority of dabs; a rate this far below 100% means it is not doing its job")
    }
}
