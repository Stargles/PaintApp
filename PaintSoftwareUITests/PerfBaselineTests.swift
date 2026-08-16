import XCTest
import UIKit
import Darwin

/// The **performance baseline**: drives synthetic strokes through the real brush
/// pipeline and records wall-clock, peak resident memory, and thumbnail-regeneration count.
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

    /// **An empty vector layer must be free**, which is the prerequisite for vector becoming the
    /// default layer kind: every new layer is empty, and `StrokeCanvasView.vectorCanvas`'s `didSet`
    /// renders it the moment it is reconciled into the view tree. Before the early-out that render
    /// produced and retained a canvas-sized sheet of transparent pixels per layer — 16.8 MB each at
    /// this canvas size, which the default flip would have multiplied by every layer in every new
    /// project.
    ///
    /// `StrokeCanvasView` is a view and so is not compiled into this target (see
    /// `CanvasManagerTestSupport`), so the test drives the exact call its `refreshDisplay` now makes
    /// rather than the view itself. The canvases are held in an array for the whole measurement
    /// because *retention* is the claim — a peak reading would be satisfied by a bitmap that was
    /// allocated and then dropped.
    ///
    /// The non-empty control is not decoration: eight canvases retaining nothing proves nothing
    /// unless the same measurement can see eight that do. It runs the *same* shape — same count,
    /// same call — with one stroke per canvas, so the two readings are directly comparable.
    ///
    /// **`phys_footprint` cannot carry this assertion, and that is the interesting part.** It counts
    /// pages the process holds, not bytes it has live, and by the time this test runs its process
    /// has churned dozens of canvas-sized bitmaps through the tests above it — so the allocator
    /// satisfies 134 MB of fresh renders entirely out of its free pool and the reading moves by
    /// 360 KB. Two earlier drafts of this test failed on exactly that, in both directions. What is
    /// asserted instead is the retained *bitmap* itself, which is what "retains a canvas-sized
    /// allocation" actually means and is exact. The footprint is still reported, as an observation.
    func testEmptyVectorLayersRetainNothingWhenTheDisplayRefreshes() {
        let layerCount = 8
        let canvasBytes = Int(Self.canvasSize.width * Self.canvasSize.height) * 4

        // Warm-up: the first render of either kind faults in shared renderer machinery that would
        // otherwise be charged to whichever measurement ran first.
        _ = autoreleasepool { VectorCanvas.empty(size: Self.canvasSize).renderIfNonEmpty() }
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: [Self.emptyLayerProbeStroke()]).render() }

        let footprintBefore = residentBytes()
        var empties: [VectorCanvas] = []
        for _ in 0..<layerCount {
            let canvas = VectorCanvas.empty(size: Self.canvasSize)
            XCTAssertNil(canvas.renderIfNonEmpty(),
                         "The display path must get nil for an empty canvas, so the image view holds no image at all")
            XCTAssertFalse(canvas.hasCachedImage,
                           "And nothing is memoized, so eviction never spends its budget on a canvas that cost nothing")
            empties.append(canvas)
        }
        var loaded: [VectorCanvas] = []
        for _ in 0..<layerCount {
            let canvas = VectorCanvas(size: Self.canvasSize, strokes: [Self.emptyLayerProbeStroke()])
            XCTAssertNotNil(canvas.renderIfNonEmpty(), "Content still renders through the same call")
            loaded.append(canvas)
        }

        let emptyBytes = empties.reduce(0) { $0 + Self.retainedBitmapBytes($1) }
        let loadedBytes = loaded.reduce(0) { $0 + Self.retainedBitmapBytes($1) }

        report("empty vector layer retention", [
            ("layersPerSide", "\(layerCount)"),
            ("canvas", "\(Int(Self.canvasSize.width))x\(Int(Self.canvasSize.height))"),
            ("oneCanvas", megabytes(UInt64(canvasBytes))),
            ("retainedByEmptyLayers", megabytes(UInt64(emptyBytes))),
            ("retainedByLoadedLayers", megabytes(UInt64(loadedBytes))),
            ("footprintDelta", megabytes(Self.growth(from: footprintBefore, to: residentBytes()))),
        ])

        XCTAssertLessThan(emptyBytes, canvasBytes,
                          "Eight empty vector layers must together retain less than a single canvas. Before the early-out each held a full one — 8 x 16.8 MB here, 8 x 64 MB at 4000² — and that is what makes vector safe to default to.")
        XCTAssertGreaterThan(loadedBytes, canvasBytes * layerCount / 2,
                             "The control must retain its canvas-sized renders, or the assertion above is measuring nothing")

        // The contract the ~10 non-display callers rely on: `render()` stays non-optional, and its
        // empty answer is a shared 1x1 that every one of them stretches into a rect it already knows.
        let empty = VectorCanvas.empty(size: Self.canvasSize)
        let placeholder = empty.render()
        XCTAssertEqual(placeholder.size, CGSize(width: 1, height: 1))
        XCTAssertTrue(empty.render() === placeholder, "And every caller gets the same one image")

        // Stretched over the canvas rect it is the transparent sheet it replaced, pixel for pixel.
        let stretched = UIGraphicsImageRenderer(size: Self.canvasSize, format: PixelOps.transparentFormat()).image { _ in
            placeholder.draw(in: CGRect(origin: .zero, size: Self.canvasSize))
        }
        XCTAssertNil(PixelOps.opaqueContentBounds(stretched),
                     "A stretched 1x1 transparent pixel must leave no opaque pixel anywhere — this is what makes it a visual no-op at every draw-into-a-fixed-rect call site")
        XCTAssertNil(empty.localContentBounds(), "And an empty canvas still bounds to nothing")
    }

    /// Bytes of bitmap a canvas is holding on to once rendered — the allocation an empty layer must
    /// not have. Read off `cgImage` rather than inferred from the canvas size, so a render that
    /// quietly went back to producing a full sheet is caught by its actual width and height.
    private static func retainedBitmapBytes(_ canvas: VectorCanvas) -> Int {
        guard let cg = canvas.render().cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

    /// Footprint can fall as well as rise between two readings (the allocator returns pages, other
    /// threads settle), and an unsigned subtraction that goes negative traps.
    private static func growth(from baseline: UInt64, to current: UInt64) -> UInt64 {
        current > baseline ? current - baseline : 0
    }

    /// One short stroke — enough to make a canvas non-empty and force a real render, without the
    /// cost of the 20-stroke scene the measurement below uses.
    private static func emptyLayerProbeStroke() -> VectorStroke {
        let samples = (0..<20).map { step in
            VectorSample(x: 128 + CGFloat(step) * 40, y: 128, pressure: 1)
        }
        return VectorStroke(brush: Brush(name: "Probe", shape: .softRound, size: 24),
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: 24, opacity: 1, samples: samples)
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

    // MARK: - The compositor (LAYER_COMPOSITING.md §5.3)

    /// A stack of `layerCount` layers, each carrying one canvas-sized baked image at a different
    /// offset so the composite has real overlap to resolve rather than a single opaque cover.
    @MainActor
    private func compositorManager(layerCount: Int) -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = Self.canvasSize
        for index in 0..<layerCount {
            manager.addLayer(name: "Layer \(index)")
            let inset = CGFloat(index) * 64
            let image = UIGraphicsImageRenderer(size: Self.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
                UIColor(hue: CGFloat(index) / CGFloat(layerCount), saturation: 0.8, brightness: 0.9, alpha: 0.6).setFill()
                ctx.cgContext.fill(CGRect(x: inset, y: inset,
                                          width: Self.canvasSize.width - 2 * inset,
                                          height: Self.canvasSize.height - 2 * inset))
            }
            manager.layers[index].cels[0].bakedImage = image
        }
        return manager
    }

    /// **What one composited frame costs at the app's real canvas size**, split into the two halves
    /// that §9.1 separated: the `@MainActor` snapshot, and the pure composite.
    ///
    /// The split is the number worth having. The snapshot is main-thread work and cannot move; the
    /// composite is pure and could go to §9.2's background renderer, or be cached by §5.2's sandwich.
    /// Which of the two dominates is what decides whether either is worth building — so this reports
    /// both rather than one total.
    ///
    /// **First measurement, for whoever reads this next: the snapshot dominates, and the GPU loses.**
    /// Six layers at 2048² came in at snapshot 276 ms, CPU composite 84 ms, GPU composite 1189 ms.
    /// The snapshot number is the interesting one — it is six `PixelOps.rasterize` calls building
    /// canvas-sized images, it happens on the main actor, and it is more than three times the cost of
    /// compositing what it produces. Any optimisation that targets the composite before the snapshot
    /// is aimed at the smaller half.
    ///
    /// The GPU figure is **simulator-bound and should not be read as a verdict on Metal**: the
    /// simulator does not model a real GPU's bandwidth, and with no upload cache this uploads ~100 MB
    /// per frame. It is recorded so the number exists, not because it predicts a device.
    @MainActor
    func testCompositeCostAndMemoryAtCanvasResolution() {
        let manager = compositorManager(layerCount: 6)

        var request: RenderRequest?
        let snapshot = measuringPeakMemory { request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) }
        guard let request else { return XCTFail("The perf manager must produce a request") }

        Compositor.backend = .coreGraphics
        var cpuImage: CGImage?
        let cpu = measuringPeakMemory { autoreleasepool { cpuImage = Compositor.composite(request) } }

        Compositor.backend = .metal
        var gpuImage: CGImage?
        let gpu = measuringPeakMemory { autoreleasepool { gpuImage = Compositor.composite(request) } }
        Compositor.backend = .coreGraphics

        report("compositor, 6 layers at 2048x2048", [
            ("snapshot", milliseconds(snapshot.seconds)),
            ("compositeCPU", milliseconds(cpu.seconds)),
            ("compositeGPU", milliseconds(gpu.seconds)),
            ("gpuAvailable", "\(CompositorMetalEngine.shared != nil)"),
            ("peakSnapshot", megabytes(snapshot.peakBytes)),
            ("peakCPU", megabytes(cpu.peakBytes)),
            ("peakGPU", megabytes(gpu.peakBytes)),
        ])

        XCTAssertNotNil(cpuImage, "The CPU reference must always render")
        XCTAssertEqual(cpuImage?.width, Int(Self.canvasSize.width))
        if CompositorMetalEngine.shared != nil {
            XCTAssertNotNil(gpuImage, "With a device present the GPU backend must render a 6-layer flat stack")
        }
        // Order-of-magnitude ceilings, in this file's house style — read the reported numbers, do not
        // tighten these. A composited frame is a handful of canvas-sized draws; seconds means
        // something has gone structurally wrong, not that the host was busy.
        XCTAssertLessThan(snapshot.seconds, 10.0, "Snapshotting six cels should not take seconds")
        XCTAssertLessThan(cpu.seconds, 10.0, "One 6-layer 2048x2048 composite taking over 10s is a catastrophic regression")
    }

    /// Composite cost must track the number of layers, not blow up on them — the check that would
    /// catch an accidental per-layer canvas allocation or an O(n²) walk once groups start nesting.
    @MainActor
    func testCompositeCostGrowsRoughlyLinearlyWithLayerCount() {
        Compositor.backend = .coreGraphics
        func composite(layerCount: Int) -> Double {
            let manager = compositorManager(layerCount: layerCount)
            guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else { return 0 }
            return measuringPeakMemory { autoreleasepool { _ = Compositor.composite(request) } }.seconds
        }

        let two = composite(layerCount: 2)
        let eight = composite(layerCount: 8)
        let ratio = two > 0 ? eight / two : 0

        report("compositor scaling", [
            ("twoLayers", milliseconds(two)),
            ("eightLayers", milliseconds(eight)),
            ("ratio", String(format: "%.2f", ratio)),
        ])

        // 4x the layers should cost on the order of 4x, not 16x. Generous because simulator timings
        // swing hard and the fixed per-composite cost (one canvas-sized renderer) flatters small n.
        XCTAssertLessThan(ratio, 12.0,
                          "4x the layers costing \(String(format: "%.1f", ratio))x suggests per-layer allocation or an O(n²) walk")
    }

    /// Nesting every layer in folders must not change what a composite costs, because a group that
    /// carries nothing does not get its own buffer (`RenderNode.needsOwnBuffer`, which both backends
    /// read). Phase 4 gave folders a real opacity, a blend mode and an isolation flag, and this test
    /// is what says the defaults are still free. If it regresses, someone has started allocating per
    /// group — which §5.3 forbids and which would also break the byte-identity
    /// `CompositorParityLogicTests` pins.
    ///
    /// **What the other side of that branch costs, measured once and recorded here rather than
    /// pinned by a test of its own: six *faded* levels — one canvas-sized intermediate each — came in
    /// at 1071.7 ms, against the 46.0 ms nested and 41.6 ms flat this test reports.** Roughly 25x a
    /// whole flat composite, which is the number §5.3's texture pool is sized by ("~2–3 live textures
    /// per nesting depth, and depth is small") and a second argument for §5.2's sandwich caching
    /// composites rather than recomputing them.
    ///
    /// **That measurement did have a test, for about an hour, and it was removed rather than kept:**
    /// leaving ~400 MB of intermediates behind in the runner process made
    /// `InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` — which times two
    /// sub-5 ms renders and asserts a 4x ratio — fail every time they shared a process, and pass in
    /// 0.073 s when they did not. A perf case that destabilises a neighbour costs this project more
    /// than the number is worth (see CLAUDE.md on triaging mystery failures); the number is above,
    /// and the guard that matters is the free path this test already holds.
    ///
    /// Peak memory here is process footprint, so it carries whatever the runner touched before — it
    /// is a smoke alarm, not a per-composite figure, and it is not comparable between runs.
    @MainActor
    func testNestingLayersInFoldersDoesNotChangeCompositeCost() {
        Compositor.backend = .coreGraphics
        let flat = compositorManager(layerCount: 6)
        guard let flatRequest = flat.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("The perf manager must produce a request")
        }
        let flatCost = measuringPeakMemory { autoreleasepool { _ = Compositor.composite(flatRequest) } }

        let nested = compositorManager(layerCount: 6)
        var parent: UUID?
        for index in 0..<6 {
            parent = nested.addFolder(name: "Depth \(index)", parentFolderID: parent)
            nested.layers[index].parentFolderID = parent
        }
        guard let nestedRequest = nested.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("The perf manager must produce a request")
        }
        let nestedCost = measuringPeakMemory { autoreleasepool { _ = Compositor.composite(nestedRequest) } }

        report("compositor, six levels of nesting", [
            ("flat", milliseconds(flatCost.seconds)),
            ("nested", milliseconds(nestedCost.seconds)),
            ("peakFlat", megabytes(flatCost.peakBytes)),
            ("peakNested", megabytes(nestedCost.peakBytes)),
        ])

        XCTAssertLessThan(nestedCost.seconds, max(flatCost.seconds * 6, 10.0),
                          "Six levels of transparent nesting should cost about what a flat stack costs")
    }

    // MARK: - What the live canvas actually pays (LAYER_COMPOSITING.md §5.2)

    /// The 6-layer stack with one §4.4 effect layer over it — `compositorManager`'s fixture is a stack
    /// of flat rectangles and **never sets `node.effect`**, so every number above it is a number about
    /// blending only. Nothing in this file measured a grade at all before this fixture.
    @MainActor
    private func gradedCompositorManager(layerCount: Int, effect: Effect) -> CanvasManager {
        let manager = compositorManager(layerCount: layerCount)
        manager.addValueLayer(effect: effect)
        return manager
    }

    /// Warms `CompositorMetalEngine.shared` before a `.metal` measurement.
    ///
    /// The engine is a lazy failable singleton that builds four compute pipelines (plus
    /// `EffectPipelines`' fifth) in its initialiser, and `MTLDevice.makeComputePipelineState` is the
    /// expensive half of that. Paid once per process and never again, so charging it to whichever
    /// composite happened to be first would report a startup cost as a frame cost — which is the
    /// mistake `testCompositeCostAndMemoryAtCanvasResolution`'s 1189 ms GPU figure quietly contains.
    /// The 64² request is deliberately tiny: it is here to touch the singleton, not to move bytes.
    @MainActor
    private func warmTheGPU() {
        let warm = CanvasManager()
        warm.canvasSize = CGSize(width: 64, height: 64)
        warm.addLayer(name: "Warm")
        guard let request = warm.makeRenderRequest(atFrame: 0, includeBackground: true) else { return }
        _ = MetalCompositor.composite(request)
    }

    /// **What one live-canvas repaint costs**, which is not what any test above measures.
    ///
    /// `CanvasView.startSandwichRebuild` composites *three* requests per rebuild — `full`, `below`,
    /// `above` — off the main thread, and a rebuild is what a lift, a layer switch, an opacity nudge or
    /// an effect-slider tick each schedule. So the artist's felt latency is three composites, not one,
    /// and the three share one `sources` array (see `makeSandwichRequests`), which is exactly the
    /// sharing a per-leaf upload cache on the GPU side can convert into two free composites.
    ///
    /// Reported per backend so the flag flip has a before and an after. **Simulator numbers are
    /// directional only** — the simulator's GPU is not the iPad's and does not model its bandwidth —
    /// so read the ratio's sign, not its magnitude, and never quote these as device figures.
    ///
    /// **First measurement, Debug on the simulator, before any of this pass's changes: cpu 61.0 ms,
    /// gpuCold 485.7 ms, gpuWarm 491.8 ms.** Cold and warm being the same number to within noise is
    /// the finding, not an aside: it says the GPU path keeps *nothing* between composites, so three
    /// composites over one shared `sources` array pay the ~100 MB upload three times over. On a stack
    /// with no effect in it the CPU is 8x faster here, which is what makes step 2 the prerequisite for
    /// the flag flip rather than an optimisation on top of it.
    ///
    /// **After the upload cache and the reused pool: cpu 74.6 ms, gpuCold 258.6 ms, gpuWarm 31.3 ms**,
    /// with `scratchAllocated` at 0 and eleven cache hits per warm rebuild (six leaves for `full`,
    /// three for `below`, two for `above`). Warm is 15.7x the old figure and 2.4x the CPU — and warm
    /// is the state the live canvas is in, because a rebuild follows an edit to *one* layer. Cold
    /// still loses to the CPU, which is the honest shape of this: the GPU wins every frame after the
    /// first one at a given canvas size.
    @MainActor
    func testSandwichRebuildCostOnBothBackends() {
        let manager = compositorManager(layerCount: 6)
        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 3) else {
            return XCTFail("The perf manager must produce a sandwich")
        }

        func rebuild() -> Double {
            measuringPeakMemory {
                autoreleasepool {
                    _ = Compositor.composite(requests.full)
                    _ = Compositor.composite(requests.below)
                    _ = Compositor.composite(requests.above)
                }
            }.seconds
        }

        Compositor.backend = .coreGraphics
        let cpu = rebuild()
        warmTheGPU()
        Compositor.backend = .metal
        // Twice: the first pass fills whatever the engine caches between composites and the second is
        // the steady state, which is the state a stroke-lift rebuild is actually in — every layer but
        // the one just drawn on is unchanged. Both are reported because the gap between them *is* the
        // cache's value, and a cold number alone would understate a warm path or flatter a broken one.
        let gpuCold = rebuild()
        let gpuWarm = rebuild()
        Compositor.backend = .coreGraphics

        report("sandwich rebuild, 6 layers at 2048x2048 (3 composites)", [
            ("cpu", milliseconds(cpu)),
            ("gpuCold", milliseconds(gpuCold)),
            ("gpuWarm", milliseconds(gpuWarm)),
            ("gpuAvailable", "\(CompositorMetalEngine.shared != nil)"),
            ("scratchAllocated", "\(CompositorMetalEngine.shared?.lastScratchAllocated ?? -1)"),
            ("uploadHits", "\(CompositorMetalEngine.shared?.uploadCacheCounts.hits ?? -1)"),
            ("uploadMisses", "\(CompositorMetalEngine.shared?.uploadCacheCounts.misses ?? -1)"),
        ])

        // Ceiling only, in this file's house style — read the reported numbers, do not tighten this.
        XCTAssertLessThan(cpu, 30.0, "Three CPU composites of a flat 6-layer stack taking half a minute is structural")
    }

    /// **What each render-resolution setting is worth**, so the Actions menu's three options can be
    /// described to an artist in time rather than in percentages.
    ///
    /// Compositing is per-pixel almost everywhere, so the naive prediction is that cost tracks area —
    /// 0.56x at 75% and 0.25x at half. It will not land there exactly, and the gap is the interesting
    /// part: the fixed costs per composite (the command buffer, the encoder, the `CGImage` hand-off)
    /// do not shrink with the canvas, and at reduced sizes the *snapshot* — `PixelOps.rasterize`
    /// drawing native-resolution tiers down into a smaller context — is doing resampling it did not
    /// have to do at full. Measured on the same fixture, backend held to the app's default.
    ///
    /// **Measured three times, Debug on the simulator, because one run of this is not worth quoting:**
    /// full 46.0 / 116.9 / 38.1 ms, threeQuarter 28.8 / 29.3 / 32.0, half 12.9 / 12.2 / 13.1. The two
    /// reduced settings are steady to within a millisecond or two and `full` swings by 3x, which is
    /// the useful thing this told us and not a defect in the measurement: at full resolution the
    /// rebuild is long enough to collide with whatever else the host is doing, and at half it is short
    /// enough not to. Read it as **half ≈ a third of full, three-quarters ≈ two-thirds** and do not
    /// quote the per-run ratios, which range from 0.10 to 0.34 for the same setting.
    @MainActor
    func testRenderResolutionScalesRebuildCost() {
        let manager = compositorManager(layerCount: 6)
        warmTheGPU()
        // Named, not inherited — see `testWhereAWarmCompositeSpendsItself`, where trusting the global
        // silently measured the wrong backend because cases run in name order and its predecessors
        // write `.coreGraphics` back.
        Compositor.backend = Compositor.defaultBackend

        func rebuild(at resolution: RenderResolution) -> Double {
            manager.renderResolution = resolution
            guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 3) else { return 0 }
            func once() {
                autoreleasepool {
                    _ = Compositor.composite(requests.full)
                    _ = Compositor.composite(requests.below)
                    _ = Compositor.composite(requests.above)
                }
            }
            once()  // warm: each resolution is its own set of cache keys, by pixel dimensions
            return measuringPeakMemory { once() }.seconds
        }

        let full = rebuild(at: .full)
        let threeQuarter = rebuild(at: .threeQuarter)
        let half = rebuild(at: .half)
        // Removing the key rather than writing `.full` back — see `SandwichLogicTests.tearDown`, which
        // carries what this leak looked like when it was not cleaned up. `defer` would be tidier and
        // is wrong here: `rebuild` is what writes it, so the restore has to outlive all three calls
        // and there is no scope that ends between them.
        UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        Compositor.backend = Compositor.defaultBackend

        report("render resolution, 6 layers at 2048x2048 (3 composites)", [
            ("full", milliseconds(full)),
            ("threeQuarter", milliseconds(threeQuarter)),
            ("half", milliseconds(half)),
            ("threeQuarterRatio", String(format: "%.2f", full > 0 ? threeQuarter / full : 0)),
            ("halfRatio", String(format: "%.2f", full > 0 ? half / full : 0)),
            ("backend", "\(Compositor.backend)"),
        ])

        // The setting has to actually do something — a picker that changes no pixel count is worse
        // than no picker. Deliberately loose: the claim is "half resolution is cheaper than full",
        // not a ratio the simulator's timings could ever hold to.
        XCTAssertLessThan(half, max(full, 0.001),
                          "Half resolution composites a quarter of the pixels and must not cost more")
    }

    /// **Where a warm GPU composite actually spends itself — the number that decides whether
    /// scissoring dispatches to a dirty rectangle is worth building.**
    ///
    /// The intuition behind dirty rectangles is unarguable in the abstract: a stroke touches a small
    /// region and compositing the whole canvas for it is waste. But it only pays if the per-pixel
    /// dispatches are where the time goes, and after the upload cache landed that stopped being
    /// obvious — a composite still pays a *fixed* toll no scissor can reduce: one `compositeFill`, a
    /// command buffer, `waitUntilCompleted`, and a full-canvas `getBytes` into a `CGImage` the view
    /// layer can show.
    ///
    /// So this separates the two by measuring the same canvas at two layer counts and reading the
    /// line. Cost is `intercept + layers · slope`: the slope is one `compositeOver` dispatch and is
    /// exactly what a scissor shrinks, and the intercept is the per-composite floor that a scissor
    /// cannot touch at all — it would take *rendering into a displayable surface instead of reading
    /// back* to move that.
    ///
    /// Both counts are measured warm, because cold would measure the uploads instead and every leaf
    /// in the live canvas is warm by the second rebuild.
    ///
    /// ### Measured twice per backend, Debug on the simulator, and the answer is not close
    ///
    /// | | CoreGraphics | | Metal | |
    /// |---|---|---|---|---|
    /// | one layer | 9.0 ms | 9.0 ms | 12.0 ms | 11.8 ms |
    /// | eight layers | 73.7 ms | 58.1 ms | 17.8 ms | 13.9 ms |
    /// | **per-layer slope** | **9.2 ms** | **7.0 ms** | **0.8 ms** | **0.3 ms** |
    /// | fixed intercept | −0.3 ms | 2.0 ms | 11.2 ms | 11.5 ms |
    /// | fixed share of six layers | 0% | 5% | 69% | 86% |
    ///
    /// **The two backends have opposite shapes, and that is the finding.** CoreGraphics is ~8 ms per
    /// layer with no floor worth speaking of, so its cost is the document; Metal is a ~11.4 ms floor
    /// with a slope at or near the noise, so its cost is the *frame*. Seven extra canvas-sized layers
    /// cost the GPU between two and six milliseconds and cost the CPU another fifty.
    ///
    /// That floor is the command buffer round-trip plus the 16.8 MB `getBytes` and the `CGImage`
    /// built on it — everything that happens once per composite regardless of what is in it.
    ///
    /// **So scissoring dispatches to a dirty rectangle would target 14–31% of the cost.** That is the
    /// finding, and it is the opposite of what the idea promises: the waste is real, but it is not in
    /// the per-pixel maths any more — the upload cache already removed the part that scaled with the
    /// document. What is left is a per-frame toll that a smaller dispatch region does not reduce,
    /// because the frame still ends by moving a whole canvas across the CPU/GPU boundary so a
    /// `UIImageView` can show it. Removing *that* — compositing into a surface the view layer can
    /// display directly, rather than reading back — is where the next real win is, and it would make
    /// a dirty rectangle worth revisiting afterwards rather than before.
    ///
    /// **The ratio is simulator-bound; the shape of the argument is not.** A simulator models neither
    /// an iPad's GPU bandwidth nor its submit latency, so do not quote 86% as a device figure. What
    /// carries over is that a full-canvas per-pixel dispatch on an M-series GPU is a fraction of a
    /// millisecond while a 16.8 MB readback and a `CGImage` allocation are real CPU work at any
    /// canvas size. Confirming it on the device is a profile, not a guess, and is worth doing before
    /// anybody spends a phase on scissoring.
    @MainActor
    func testWhereAWarmCompositeSpendsItself() {
        warmTheGPU()

        func cost(layerCount: Int, on backend: CompositorBackend) -> Double {
            Compositor.backend = backend
            return cost(layerCount: layerCount)
        }

        func cost(layerCount: Int) -> Double {
            let manager = compositorManager(layerCount: layerCount)
            guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else { return 0 }
            func once() { autoreleasepool { _ = Compositor.composite(request) } }
            once()  // warm: fills the upload cache for this fixture's leaves
            // Averaged over several, because at these durations one run is mostly host noise — the
            // whole point here is a slope between two numbers, and a slope amplifies whatever error
            // is in either end of it.
            let runs = 5
            return measuringPeakMemory { for _ in 0..<runs { once() } }.seconds / Double(runs)
        }

        // **Both backends, and the backend is set explicitly rather than inherited.** Every other case
        // in this section ends by writing `.coreGraphics` back into the global, and cases run in name
        // order — so a test that merely trusted "the app's default" measured whichever backend its
        // alphabetical predecessor happened to leave behind. That is not hypothetical: this case was
        // written that way and reported `backend=coreGraphics` with a 9% fixed share, the exact
        // opposite conclusion to the one it draws, and the only reason it was caught is that `report`
        // prints the backend. Anything here that depends on the global has to name it.
        for backend in [CompositorBackend.coreGraphics, .metal] {
            let one = cost(layerCount: 1, on: backend)
            let eight = cost(layerCount: 8, on: backend)
            let slope = (eight - one) / 7
            let intercept = one - slope
            // What fraction of the fixture the rest of this section uses is floor rather than
            // per-layer work — i.e. the share a perfectly scissored dispatch would leave exactly
            // where it is.
            let sixLayer = intercept + 6 * slope
            let fixedShare = sixLayer > 0 ? intercept / sixLayer : 0

            report("warm composite decomposition at 2048x2048, \(backend)", [
                ("oneLayer", milliseconds(one)),
                ("eightLayers", milliseconds(eight)),
                ("perLayerSlope", milliseconds(slope)),
                ("fixedIntercept", milliseconds(intercept)),
                ("fixedShareOfSixLayers", String(format: "%.0f%%", fixedShare * 100)),
            ])

            // No assertion on the split — it is a design input, not a contract, and the honest ceiling
            // on it is the same one every case here uses.
            XCTAssertLessThan(eight, 30.0,
                              "Eight warm \(backend) composites of a flat stack taking half a minute is structural")
        }
        Compositor.backend = Compositor.defaultBackend
    }

    /// **What a grade costs a composite**, on each backend, for a one-pass effect and a two-pass one.
    ///
    /// The split is the point. `brightnessContrast` is one dispatch over the canvas and resolves
    /// entirely into `Effect.params`, so it measures the *wrapper* — snapshot the backdrop, grade every
    /// pixel, mix it back. `blur` is two passes with 2·(3σ)+1 taps each, so it measures what a
    /// neighbourhood kernel adds on top: this is the effect whose dirty-rect dilation is a radius
    /// rather than zero, and the effect a scissored dispatch has to be conservative about.
    ///
    /// **The CPU grade is `EffectReference` at `-Onone` and legitimately costs seconds** — it is the
    /// oracle the shader is measured against and is documented as slow on purpose
    /// (`CoreGraphicsCompositor.grade`). That is exactly why the blur half is gated: a two-pass
    /// convolution over 4.2M pixels in unoptimised Swift is a minute of runner time and a large peak,
    /// which is the profile CLAUDE.md records as destabilising whatever shares the process. The
    /// one-pass half stays ungated because it is the number that has to exist for the flag flip to be
    /// defensible at all.
    ///
    /// **First measurement, Debug on the simulator: cpuUngraded 38.1 ms, cpuGraded 7069.1 ms,
    /// gpuUngraded 255.7 ms, gpuGraded 247.3 ms.** So one effect layer costs the CPU backend **7.0
    /// seconds** and costs the GPU backend *nothing measurable* — the grade delta on the GPU came out
    /// at −8.4 ms, which is one extra dispatch over a texture that is already resident, lost in the
    /// noise of the uploads around it. That single pair of numbers is the whole case for the flag:
    /// the flat-stack comparison favours the CPU 38 against 256, and any document carrying an
    /// adjustment layer reverses it by a factor of 28.
    ///
    /// **After the upload cache, with both backends warm: cpuUngraded 43.9 ms, cpuGraded 7047.5 ms,
    /// gpuUngraded 21.0 ms, gpuGraded 18.8 ms.** The flat-stack comparison has flipped too — the GPU
    /// is now ahead on the case it used to lose — and the graded comparison is 375x. There is no
    /// remaining document shape among this file's fixtures where the CPU backend is the faster one.
    @MainActor
    func testEffectCompositeCostOnBothBackends() {
        let onePass = gradedCompositorManager(
            layerCount: 6, effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1.2, contrast: 1.5)))
        guard let plainRequest = compositorManager(layerCount: 6).makeRenderRequest(atFrame: 0, includeBackground: true),
              let gradedRequest = onePass.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("The perf manager must produce a request")
        }

        func cost(_ request: RenderRequest) -> Double {
            measuringPeakMemory { autoreleasepool { _ = Compositor.composite(request) } }.seconds
        }

        Compositor.backend = .coreGraphics
        let cpuPlain = cost(plainRequest)
        let cpuGraded = cost(gradedRequest)
        warmTheGPU()
        Compositor.backend = .metal
        // **Both GPU figures are warm, and the pairing is the point of the test.** The two fixtures
        // are separate `CanvasManager`s, so their cels are different objects and one does not warm
        // the other's entries — measuring the graded one warm against the plain one cold would
        // report the upload cache as though it were the grade, with the sign that flatters the GPU.
        // A discarded run apiece puts both on the same footing, which is the footing the live canvas
        // is in: a rebuild follows an edit to one layer, not to a document nobody has opened.
        _ = cost(plainRequest)
        let gpuPlain = cost(plainRequest)
        _ = cost(gradedRequest)
        let gpuGraded = cost(gradedRequest)
        Compositor.backend = .coreGraphics

        report("one-pass effect over 6 layers at 2048x2048", [
            ("cpuUngraded", milliseconds(cpuPlain)),
            ("cpuGraded", milliseconds(cpuGraded)),
            ("cpuGradeDelta", milliseconds(cpuGraded - cpuPlain)),
            ("gpuUngraded", milliseconds(gpuPlain)),
            ("gpuGraded", milliseconds(gpuGraded)),
            ("gpuGradeDelta", milliseconds(gpuGraded - gpuPlain)),
            ("gpuAvailable", "\(CompositorMetalEngine.shared != nil)"),
        ])

        XCTAssertLessThan(cpuGraded, 60.0,
                          "One canvas-sized grade past a minute is a structural regression, not -Onone")
    }

    /// The multi-pass half of the case above — see its doc comment for why this one is gated.
    ///
    /// ```
    /// xcodebuild test … -only-testing:PaintSoftwareUITests/PerfBaselineTests/testMultiPassEffectCompositeCostOnBothBackends \
    ///   PAINT_PERF_HEAVY=1
    /// ```
    @MainActor
    func testMultiPassEffectCompositeCostOnBothBackends() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINT_PERF_HEAVY"] != nil,
                          "Heavy: a two-pass convolution over 4.2M pixels through EffectReference at -Onone")
        let blurred = gradedCompositorManager(layerCount: 6, effect: .blur(Effect.Blur(radius: 8)))
        guard let request = blurred.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("The perf manager must produce a request")
        }

        func cost() -> (seconds: Double, peakBytes: UInt64) {
            measuringPeakMemory { autoreleasepool { _ = Compositor.composite(request) } }
        }

        Compositor.backend = .coreGraphics
        let cpu = cost()
        warmTheGPU()
        Compositor.backend = .metal
        _ = cost()
        let gpu = cost()
        Compositor.backend = .coreGraphics

        report("two-pass blur (r=8) over 6 layers at 2048x2048", [
            ("cpu", milliseconds(cpu.seconds)),
            ("gpu", milliseconds(gpu.seconds)),
            ("peakCPU", megabytes(cpu.peakBytes)),
            ("peakGPU", megabytes(gpu.peakBytes)),
            ("gpuAvailable", "\(CompositorMetalEngine.shared != nil)"),
        ])

        XCTAssertLessThan(cpu.seconds, 300.0,
                          "A radius-8 separable blur past five minutes means the pass list is not separable any more")
    }

    // MARK: - Alpha masks (LAYER_COMPOSITING.md §6)

    /// The 6-layer stack above, with layer 0 turned into a mask *shape* — the left half of the canvas
    /// — and every layer above it clipped to it.
    ///
    /// A half-canvas shape rather than the full-canvas rect `compositorManager` would otherwise give
    /// layer 0, because the two halves exercise the two branches `MaskResolver.apply` short-circuits
    /// on: covered pixels take the identity path, clear ones take the zeroing path, and only the
    /// antialiased band across the edge (§6.3) reaches the four multiplies. A mask that covered
    /// everything would measure the cheapest of the three and read as a verdict on all of them.
    ///
    /// One `AlphaMask` value shared by every masked layer, which is not a shortcut — §6.1 caches the
    /// coverage per *distinct mask*, so this is the shape a real document takes when several layers
    /// clip to one shape, and it is what makes "resolve once, apply per node" the thing being timed.
    @MainActor
    private func maskedCompositorManager(layerCount: Int, masked: Bool) -> CanvasManager {
        let manager = compositorManager(layerCount: layerCount)
        manager.layers[0].cels[0].bakedImage = UIGraphicsImageRenderer(
            size: Self.canvasSize, format: PixelOps.transparentFormat()
        ).image { ctx in
            UIColor.black.setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: Self.canvasSize.width / 2, height: Self.canvasSize.height))
        }
        guard masked else { return manager }
        let mask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        for index in 1..<layerCount { manager.layers[index].alphaMask = mask }
        return manager
    }

    /// **What a mask costs a composite at the app's real canvas size** — the number nobody had, since
    /// `MaskResolver` shipped measured only against the 64² fixtures (`MaskParityLogicTests`).
    ///
    /// `MaskResolver.apply` is a per-pixel CPU pass over 4.2M pixels and it runs **once per masked
    /// node per composite**, uncached, while the resolution above it is cached and shared. So the two
    /// halves scale differently and the report separates them: `resolveCold` is paid once when a mask
    /// source's content version moves, `applyOnce` is paid by every clipped node on every frame. A
    /// composite is measured masked and unmasked over the same stack so the delta is attributable to
    /// the mask rather than to the stack.
    ///
    /// Warm and cold are both reported because §5.2's sandwich makes them different frames rather
    /// than different runs: drawing on a layer that is *clipped* leaves the source untouched and the
    /// coverage cached, while drawing on the layer that *is* the mask source invalidates it every
    /// dab.
    ///
    /// **Measured, five masked nodes at 2048², Debug on the simulator:** unmasked composite 49.9 ms,
    /// masked 10173.7 ms warm and 19249.1 ms cold; `resolveCold` 1143.7 ms, `applyOnce` 1532.4 ms,
    /// `makeMaskImage` 2458.1 ms; peak 295.5 MB unmasked against 614.9 MB masked. **A mask is 200x
    /// the cost of the whole composite it clips**, and the multiply — not the resolution — is where
    /// it goes.
    ///
    /// **Almost all of that is `-Onone`, and the scheme's Run configuration is Debug**, so it is what
    /// the iPad build does today rather than a test-only artifact. The two loops, extracted verbatim
    /// and compiled standalone at 2048² on this Mac: `apply` 1969.5 ms → 31.9 ms and `makeMaskImage`
    /// 3166.9 ms → 7.2 ms across `-Onone`/`-O`, a 62x and a 440x. The `-Onone` figures land within
    /// 30% of what this case reports, which is what says the extraction measures the same work. So
    /// the optimised cost of a mask is ~32 ms per clipped node per composite — real, worth knowing
    /// before §5.2 rebuilds a sandwich per dab, and nothing like a 200x.
    ///
    /// **Not in the fast tier**, and the gate rather than the deletion `testNestingLayersInFolders…`
    /// chose because this number wants re-measuring whenever `apply` is touched. 36 s and a 615 MB
    /// peak is the same profile that made a ~400 MB neighbour fail
    /// `InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` whenever the two
    /// shared a runner process. Run it deliberately:
    ///
    /// ```
    /// xcodebuild test … -only-testing:PaintSoftwareUITests/PerfBaselineTests/testMaskedCompositeCostAtCanvasResolution \
    ///   PAINT_PERF_HEAVY=1
    /// ```
    ///
    /// Ceilings only, in this file's house style — read the reported numbers, do not tighten these.
    @MainActor
    func testMaskedCompositeCostAtCanvasResolution() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINT_PERF_HEAVY"] != nil,
                          "Heavy: ~36 s and a 615 MB peak, which destabilises whatever shares the runner process")
        Compositor.backend = .coreGraphics
        let maskedCount = 5

        let plain = maskedCompositorManager(layerCount: maskedCount + 1, masked: false)
        guard let plainRequest = plain.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("The perf manager must produce a request")
        }
        let unmasked = measuringPeakMemory { autoreleasepool { _ = Compositor.composite(plainRequest) } }

        let clipped = maskedCompositorManager(layerCount: maskedCount + 1, masked: true)
        guard let maskedRequest = clipped.makeRenderRequest(atFrame: 0, includeBackground: true),
              let node = maskedRequest.tree.first(where: { !$0.masks.isEmpty }) else {
            return XCTFail("The fixture must produce a request carrying a mask")
        }

        // Cold first: an empty cache is the state a source edit leaves behind, and measuring it after
        // the warm case would measure a hit instead.
        MaskResolver.clearCache()
        let cold = measuringPeakMemory { autoreleasepool { _ = Compositor.composite(maskedRequest) } }
        let warm = measuringPeakMemory { autoreleasepool { _ = Compositor.composite(maskedRequest) } }

        MaskResolver.clearCache()
        var resolved: ResolvedMask?
        let resolve = measuringPeakMemory {
            autoreleasepool { resolved = MaskResolver.coverage(for: node.masks, of: maskedRequest) }
        }
        guard let resolved, let leaf = clipped.layers[1].cels[0].bakedImage?.cgImage else {
            return XCTFail("The fixture must resolve a coverage and carry canvas-sized leaf pixels")
        }
        let apply = measuringPeakMemory { autoreleasepool { _ = MaskResolver.apply(resolved, to: leaf) } }
        let maskImage = measuringPeakMemory { autoreleasepool { _ = resolved.makeMaskImage() } }

        report("masks, \(maskedCount) masked nodes at 2048x2048", [
            ("compositeUnmasked", milliseconds(unmasked.seconds)),
            ("compositeMaskedCold", milliseconds(cold.seconds)),
            ("compositeMaskedWarm", milliseconds(warm.seconds)),
            ("deltaCold", milliseconds(cold.seconds - unmasked.seconds)),
            ("deltaWarm", milliseconds(warm.seconds - unmasked.seconds)),
            ("resolveCold", milliseconds(resolve.seconds)),
            ("applyOnce", milliseconds(apply.seconds)),
            ("makeMaskImage", milliseconds(maskImage.seconds)),
            ("peakUnmasked", megabytes(unmasked.peakBytes)),
            ("peakMaskedCold", megabytes(cold.peakBytes)),
            ("peakApply", megabytes(apply.peakBytes)),
        ])

        // Sized around the measured Debug figures above, an order of magnitude clear of them: at
        // -Onone this multiply legitimately costs seconds, so an assertion tight enough to call that
        // a regression would fail on the number the doc comment records.
        XCTAssertLessThan(apply.seconds, 10.0,
                          "One canvas-sized mask multiply past 10 s is a structural regression, not -Onone")
        XCTAssertLessThan(warm.seconds, 30.0,
                          "A cached mask should cost a per-node multiply on top of the composite, not a new order of magnitude")
    }
}
