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
        let strokeSteps = manager.history.undoStack.filter { $0.label == .brushStroke }
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
        manager.recordUndo(label: .brushStroke, cost: cost, undo: {
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

    /// Baking a pending shape is idempotent however many times a caller asks for it.
    ///
    /// This used to be about the transform path: a `commitSnappedShapeIfTransforming` on every
    /// `.changed` frame of a two-finger gesture, and whether 50 frames laid down 50 strokes. That
    /// call is gone — moving the viewport is not editing the canvas, and the owner reported the bake
    /// it caused as a bug — so the concern is no longer about frames. What survives it is the
    /// property itself, which every remaining commit path still relies on: `commitInteractiveShape`
    /// opens with `guard shapeGestureActive, let shape = resolvedShape else { return }` and clears
    /// `shapeGestureActive` on the way through, and its `objectWillChange.send()` sits in a `defer`
    /// only reached past that guard — so the bake and the publish both happen exactly once. A tool
    /// switch, a frame change and an undo can all reach `commitAllInteractiveState` for the same
    /// pending shape within one turn, and each of them counts on that.
    ///
    /// It drives the real state machine — begin a shape, engage the snap, lift the pen into the
    /// adjustable state, then commit 50 times — and asserts one stroke lands, not 50. A regression
    /// that made the bake re-entrant would show up as 50 overlapping strokes and 50 undo steps.
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

        // The snap engages, then the pen lifts. That is the state every real commit path finds a
        // shape in — adjustable, snapped, waiting for a tool switch or a new stroke to bake it.
        manager.updateInteractiveShape(isConstrained: true)
        manager.endInteractiveShape()
        XCTAssertTrue(manager.isShapeInAdjustableState,
                      "Lifting the pen should leave the shape adjustable — the state a later edit then bakes")

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

    // MARK: - Mode 3 (cutToIntersection) live-drag cost — PERFORMANCE.md item 10, MEASURE ONLY

    /// **Measure only; do not fix.** `StrokeCanvasView.recordVectorSample` calls
    /// `resolveIntersectionCut` on **every** touch sample while Mode 3 is active, which calls
    /// `VectorCanvas.cutToIntersection` once per sample. On a cut, `cutToIntersection` calls
    /// `invalidate()`, nilling `cachedImage`, so the very next `refreshDisplay()` on this view calls
    /// `render()` cold and re-stamps every stored stroke in the layer through `BrushStamper`. That is
    /// O(total dabs in the layer), paid **per cut sample**, not once per gesture — and completely
    /// independent of canvas resolution, unlike every other scenario in this file.
    ///
    /// Nothing before this exercised it: `testEraseHeavyVectorLayerCostAndMemory` commits through
    /// `.erase`, which is a different code path (spatial-index-driven deletion/split/punch, one commit
    /// per *gesture*) and never calls `cutToIntersection` or forces a mid-drag `render()`.
    ///
    /// The scene is `eraseScenePaintStrokes()` unchanged — the same 200-stroke "total dabs" layer
    /// `testEraseHeavyVectorLayerCostAndMemory` uses, so the two numbers share a fixture. The drag is
    /// a dense vertical sweep down one whole column (every 6pt — denser than `eraseSceneGesture`'s
    /// 9-sample bands, because a live drag samples every touch-move, not once per test-authored
    /// waypoint), crossing all 50 rows in that column, so a large fraction of samples actually cut
    /// rather than miss.
    ///
    /// **Bucketed by outcome, not averaged**, because the bucket split *is* the finding: a
    /// `.missed`/`.unchanged` sample is a cache hit (`render()` returns `cachedImage` in O(1)), and a
    /// `.cut` sample is the one that pays the full re-stamp. Averaging the two together would hide the
    /// asymmetry item 10 exists to quantify.
    func testCutToIntersectionLiveDragCostPerSample() {
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.eraseScenePaintStrokes())
        let elementsBefore = canvas.elements.count

        // Warm-up: faults in the spatial index and the first render, matching
        // `testEraseHeavyVectorLayerCostAndMemory`'s rationale — otherwise sample 0 is charged a
        // one-time cold-cache cost that has nothing to do with the per-sample question this test asks.
        _ = autoreleasepool { canvas.render() }

        // Column 0's x-centre (`eraseSceneGesture`'s spacing: x0 = 100 + column*480, strokes span
        // x0...x0+400) and the column's full y-range (rows at 60, 100, …, 2020).
        let x: CGFloat = 300
        var samples: [CGPoint] = []
        var y: CGFloat = 40
        while y <= 2040 {
            samples.append(CGPoint(x: x, y: y))
            y += 6
        }

        var driver = VectorEraser.IntersectionDriver()
        var cutTimes: [Double] = []
        var missTimes: [Double] = []
        let totalMeasured = measuringPeakMemory {
            for point in samples {
                autoreleasepool {
                    let resolved = canvas.cutToIntersection(atCanvasPoint: point,
                                                            brush: Self.eraseSceneEraserBrush,
                                                            size: Self.eraseSceneEraserSize,
                                                            suppressing: driver.suppressed)
                    driver.accept(resolved.outcome, underTip: resolved.underTip)
                    // `refreshDisplay()`'s call to `vectorCanvas.render()`, run right here rather than
                    // batched, because the live view calls it after every `moveVectorStroke` — and at
                    // typical Pencil sampling rates that is once per sample, not once per gesture.
                    let start = CFAbsoluteTimeGetCurrent()
                    _ = canvas.render()
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    if resolved.outcome == .cut { cutTimes.append(elapsed) } else { missTimes.append(elapsed) }
                }
            }
        }

        let cuts = cutTimes.count
        let misses = missTimes.count
        let perCutMean = cuts > 0 ? cutTimes.reduce(0, +) / Double(cuts) : 0
        let perMissMean = misses > 0 ? missTimes.reduce(0, +) / Double(misses) : 0

        report("Mode 3 live-drag cut cost", [
            ("paintStrokesBefore", "\(elementsBefore)"),
            ("dragSamples", "\(samples.count)"),
            ("samplesThatCut", "\(cuts)"),
            ("samplesThatDidNotCut", "\(misses)"),
            ("elementsAfter", "\(canvas.elements.count)"),
            ("totalDragTime", milliseconds(totalMeasured.seconds)),
            ("meanRenderAfterACut", milliseconds(perCutMean)),
            ("meanRenderAfterAMiss", milliseconds(perMissMean)),
            ("cutOverMissRatio", perMissMean > 0.000_001 ? String(format: "%.0fx", perCutMean / perMissMean) : "n/a (miss cost ~0)"),
            ("peakFootprint", megabytes(totalMeasured.peakBytes)),
        ])

        XCTAssertGreaterThan(cuts, 0,
                             "This scenario only measures what it claims to if the sweep actually crosses strokes and cuts them")
        XCTAssertLessThan(totalMeasured.seconds, 60.0,
                          "A single drag down one column taking a minute is a catastrophic regression, not slowness")
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
    private func compositorManager(layerCount: Int, canvasSize: CGSize = PerfBaselineTests.canvasSize) -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = canvasSize
        for index in 0..<layerCount {
            manager.addLayer(name: "Layer \(index)")
            let inset = CGFloat(index) * 64
            let image = UIGraphicsImageRenderer(size: canvasSize, format: PixelOps.transparentFormat()).image { ctx in
                UIColor(hue: CGFloat(index) / CGFloat(layerCount), saturation: 0.8, brightness: 0.9, alpha: 0.6).setFill()
                ctx.cgContext.fill(CGRect(x: inset, y: inset,
                                          width: canvasSize.width - 2 * inset,
                                          height: canvasSize.height - 2 * inset))
            }
            manager.layers[index].cels[0].bakedImage = image
        }
        return manager
    }

    /// **The owner's canvas**, which is not the square this file's other cases use. TODO.md records
    /// them animating at 2048x1024; 2048x2048 is the app's default and twice the pixels. A figure
    /// that is going to be reasoned about at the document that actually exists has to be taken there.
    private static let ownersCanvasSize = CGSize(width: 2048, height: 1024)

    /// **How a sandwich rebuild splits between the picture the artist looks at and the two halves
    /// that are only shown mid-stroke** — the number PERFORMANCE.md item 4's second half turns on and
    /// which nobody had ever taken.
    ///
    /// `startSandwichRebuild` composites `full`, `below` and `above` unconditionally, but
    /// `below`/`above` are displayed only while a stroke is down. Making them lazy would skip two
    /// composites on every playback tick, scrub tick, undo and layer switch — and would also mean a
    /// stroke's first frames have nothing to show but `full`, which is ink the artist cannot see yet.
    /// **That trade cannot be judged without knowing how much of a rebuild the two halves are**, and
    /// the estimate it was being judged on was arithmetic over a per-layer slope, not a measurement.
    ///
    /// So this reports the four terms separately. What matters is the **ratio**, not the absolutes:
    /// this is a simulator on a shared Mac, and the pinned CoreGraphics backend is the reference
    /// implementation rather than the shipped one. A device figure would still be worth taking; this
    /// is what makes the question answerable without one.
    ///
    /// Six layers because that is the stack every other compositor case in this file uses, so the
    /// numbers sit beside each other.
    @MainActor
    func testHowASandwichRebuildSplitsBetweenFullAndTheTwoHalvesAtTheOwnersCanvas() {
        Compositor.backend = .coreGraphics
        let manager = compositorManager(layerCount: 6, canvasSize: Self.ownersCanvasSize)
        manager.currentLayerIndex = 3

        var requests: SandwichRequests?
        let snapshotCold = measuringPeakMemory {
            requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 3)
        }
        guard let requests else { return XCTFail("Six leaves must cut at index 3") }

        // **The same snapshot again, and the gap between the two is the point.** `PixelOps.rasterize`
        // is memoized on cel identity, so what a rebuild pays for its `@MainActor` half depends
        // entirely on whether the memo already holds these cels. A playback tick moves to a new
        // frame and pays the cold figure; a layer switch stays on the same frame and pays the warm
        // one. Sizing either optimisation against a single "snapshot" number would be sizing it
        // against whichever of the two happened to get measured.
        let snapshotWarm = measuringPeakMemory {
            _ = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 4)
        }

        // Warm: `PixelOps.rasterize` is memoized and the snapshot above has just walked these cels,
        // so a first composite would be measuring the memo filling rather than the walk. The same
        // reason the onion-skin table reports a warm series and its cold outlier separately.
        _ = Compositor.composite(requests.full)

        var fullSeconds = 0.0, belowSeconds = 0.0, aboveSeconds = 0.0
        autoreleasepool { fullSeconds = measuringPeakMemory { _ = Compositor.composite(requests.full) }.seconds }
        autoreleasepool { belowSeconds = measuringPeakMemory { _ = Compositor.composite(requests.below) }.seconds }
        autoreleasepool { aboveSeconds = measuringPeakMemory { _ = Compositor.composite(requests.above) }.seconds }

        let rebuild = fullSeconds + belowSeconds + aboveSeconds
        let halvesShare = rebuild > 0 ? (belowSeconds + aboveSeconds) / rebuild : 0

        report("sandwich rebuild split, 6 layers at 2048x1024 (CoreGraphics)", [
            ("snapshotCold", milliseconds(snapshotCold.seconds)),
            ("snapshotWarm", milliseconds(snapshotWarm.seconds)),
            ("full", milliseconds(fullSeconds)),
            ("below", milliseconds(belowSeconds)),
            ("above", milliseconds(aboveSeconds)),
            ("rebuild", milliseconds(rebuild)),
            ("halvesShareOfRebuild", String(format: "%.2f", halvesShare)),
            ("compositeSize", "\(requests.full.canvasSize)"),
        ])

        // All three composite the same canvas, so the sizes are the one thing here that is not a
        // timing and can be asserted rather than merely reported.
        XCTAssertEqual(requests.below.canvasSize, requests.full.canvasSize)
        XCTAssertEqual(requests.above.canvasSize, requests.full.canvasSize)
        XCTAssertEqual(requests.full.canvasSize, Self.ownersCanvasSize,
                       "Nothing should have reduced a 2048x1024 six-layer composite — `CompositorBudget` is inert at this size")
        // An order-of-magnitude ceiling in this file's house style. Read the reported numbers; do not
        // tighten this into a timing assertion on a machine that runs several suites at once.
        XCTAssertLessThan(rebuild, 30.0, "A three-composite rebuild taking half a minute is structural, not contention")
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
        // **Counted as a delta, because the counters are process-lifetime and the process is shared.**
        // A device run reported `uploadHits=76 uploadMisses=47` here and it reads like a 38% miss rate
        // on a fixture that cannot miss — it is not. `CompositorMetalEngine.shared` is one singleton
        // for the whole test process, every case in this file that composites contributes to those
        // totals, and each *distinct canvas size* is a distinct set of keys: `warmTheGPU` composites
        // at 64², `testRenderResolutionScalesRebuildCost` at three more sizes, and the budget cases at
        // others again. The lifetime total therefore says nothing about this rebuild. The delta below
        // does, and it is the number to read.
        // Twice: the first pass fills whatever the engine caches between composites and the second is
        // the steady state, which is the state a stroke-lift rebuild is actually in — every layer but
        // the one just drawn on is unchanged. Both are reported because the gap between them *is* the
        // cache's value, and a cold number alone would understate a warm path or flatter a broken one.
        let gpuCold = rebuild()
        let before = CompositorMetalEngine.shared?.uploadCacheCounts ?? (hits: 0, misses: 0)
        let gpuWarm = rebuild()
        let after = CompositorMetalEngine.shared?.uploadCacheCounts ?? (hits: 0, misses: 0)
        Compositor.backend = .coreGraphics

        report("sandwich rebuild, 6 layers at 2048x2048 (3 composites)", [
            ("cpu", milliseconds(cpu)),
            ("gpuCold", milliseconds(gpuCold)),
            ("gpuWarm", milliseconds(gpuWarm)),
            ("gpuAvailable", "\(CompositorMetalEngine.shared != nil)"),
            ("scratchAllocated", "\(CompositorMetalEngine.shared?.lastScratchAllocated ?? -1)"),
            ("warmHits", "\(after.hits - before.hits)"),
            ("warmMisses", "\(after.misses - before.misses)"),
            ("lifetimeHits", "\(after.hits)"),
            ("lifetimeMisses", "\(after.misses)"),
        ])

        // **The claim the cache exists to make**: a rebuild whose leaves are already resident misses
        // nothing. Asserted on the delta, which is the only figure that is about this rebuild.
        XCTAssertEqual(after.misses - before.misses, 0,
                       "A warm sandwich rebuild re-uploads nothing — every leaf keys the same as the last one")
        XCTAssertGreaterThan(after.hits - before.hits, 0,
                             "…and it must be hitting rather than bypassing the cache entirely")

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

    // MARK: - What actually costs the frame rate while drawing

    /// **The per-dab cost of drawing on a vector layer against drawing on a raster one** — the
    /// measurement that decides where the owner's 60 → 17 fps went, and the one that says it is not
    /// the compositor.
    ///
    /// The owner halved `renderResolution`, which cuts a sandwich rebuild from 52.7 ms to 12.0 ms on
    /// their iPad, and **reported no change in frame rate at all**. That single observation rules the
    /// composite out of the critical path, and with it the theory that Core Animation minifying three
    /// canvas-sized layers was the cost. Whatever is spending the frame is something
    /// `renderResolution` does not reach — and `RenderResolution`'s own doc comment says exactly which
    /// things those are: it is applied in `makeSandwichRequests` and nowhere else, so the *snapshot*
    /// and the live stroke preview are both outside it.
    ///
    /// So this measures the live stroke preview directly, in the two shapes `StrokeCanvasView`
    /// actually has:
    ///
    /// - **Raster**, `refreshDisplay`'s last line: `imageView.image = raster?.renderToUIImage()`.
    ///   One canvas-sized render, memoized on `version` — and a dab bumps the version, so it is paid
    ///   per dab.
    /// - **Vector**, `refreshDisplay`'s `.overlay` branch: one canvas-sized render of the scratch
    ///   into its own layer, plus a memoized read of the committed render for the layer beneath.
    ///   Since [PERFORMANCE.md](PERFORMANCE.md) item 11 shipped (2026-08-20) that is the whole of
    ///   it, and it is why `vectorLayered` below sits within noise of `raster`.
    ///
    /// **`vectorComposited` is the shape this branch had until item 11, kept deliberately.** It
    /// allocated a *fresh* canvas-sized `UIGraphicsImageRenderer` bitmap per dab, drew the committed
    /// render into it, rendered the live scratch and drew that over the top — four canvas-sized
    /// operations where raster has one, and one of them an allocation rather than a blit. It is
    /// retained here as a measured baseline rather than deleted, for two reasons: the before/after
    /// then comes from **one run on one machine state** instead of two runs a commit apart, which on
    /// this Mac is the difference between a number and a coin flip (CLAUDE.md on contention); and the
    /// gap it reports is the standing argument against anyone flattening these two layers again.
    /// It is dead code in the app and live evidence here, and that trade is worth about a second of
    /// test time.
    ///
    /// Measured at both canvas sizes because the ratio between them is the other half of the claim:
    /// the owner's canvas is 4096², which is 4x the pixels of the 2048² this file's other cases use.
    ///
    /// **And at 2048×1024, which is the canvas the owner actually animates on** —
    /// [PERFORMANCE.md](PERFORMANCE.md) item 8. Until 2026-08-20 this case measured 2048² and 4096²
    /// and nothing between, so every statement in that document about the owner's own document was a
    /// two-point linear fit (`fixed + k·area`) rather than a reading. The fit predicted ~10.2 ms per
    /// dab there; this third call is what turns that into a number. It is a third of a second of test
    /// time and it retires an inference the whole ranking leaned on.
    ///
    /// *The device figure is still owed.* Every number this case prints on this Mac is
    /// simulator/CoreGraphics, and the 53.8 ms / 16.4 ms pair in [BUGS.md](BUGS.md) is Release on the
    /// owner's iPad 9. The two are not interchangeable — see PERFORMANCE.md §1's ~1.3× device factor,
    /// and §5 on why a simulator GPU figure is worth less than that. What the simulator *is* good for
    /// here is the direction and the ratio, because this path is CPU-side: an allocation and two
    /// blits, no GPU anywhere in it.
    @MainActor
    func testTheLayeredLiveStrokePreviewCostsWhatTheRasterPathCosts() {
        func costs(at size: CGSize) -> (raster: Double, composited: Double, layered: Double) {
            let raster = RasterLayerTexture.empty(size: size)
            BrushStamper.stampStroke(into: raster, samples: syntheticStroke(sampleCount: 60),
                                     brush: Brush(name: "Perf", shape: .softRound, size: 24),
                                     color: .black, brushSize: 24, brushOpacity: 1)
            let scratch = RasterLayerTexture.empty(size: size)
            BrushStamper.stampStroke(into: scratch, samples: syntheticStroke(sampleCount: 12),
                                     brush: Brush(name: "Perf", shape: .softRound, size: 24),
                                     color: .black, brushSize: 24, brushOpacity: 1)
            let committed = VectorCanvas(size: size, strokes: [Self.previewStroke(in: size)])
            _ = committed.render()  // the committed render is cached across a stroke; only the rest is per dab

            let bounds = CGRect(origin: .zero, size: size)
            let brush = Brush(name: "Perf", shape: .softRound, size: 24)
            // **One dab is stamped inside each measured frame, and it has to be.** Both render paths
            // are memoized on the texture's `version`, so a loop that only read them would measure the
            // memo rather than a stroke — and the dab is what moves the version in the app too. It is
            // the same dab on both sides, so it cancels out of the ratio.
            func dab(into texture: RasterLayerTexture) {
                BrushStamper.stampStroke(into: texture, samples: syntheticStroke(sampleCount: 2),
                                         brush: brush, color: .black, brushSize: 24, brushOpacity: 1)
            }
            func rasterFrame() {
                autoreleasepool {
                    dab(into: raster)
                    _ = raster.renderToUIImage()
                }
            }
            // `StrokeCanvasView.refreshDisplay`'s `.overlay` branch **before** item 11 — the cost
            // being deleted, kept as the measured baseline. See the doc comment.
            func compositedFrame() {
                autoreleasepool {
                    dab(into: scratch)
                    let base = committed.renderIfNonEmpty()
                    _ = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
                        base?.draw(in: bounds)
                        scratch.renderToUIImage().draw(in: bounds)
                    }
                }
            }
            // Verbatim `StrokeCanvasView.refreshDisplay`'s `.overlay` branch as it stands now: the
            // scratch rendered once into `scratchView`, and a base read that the identity check in
            // `refreshDisplay` turns into a memo hit for every touch-move of a stroke (an `.overlay`
            // gesture does not touch the canvas until lift, so `renderIfNonEmpty` returns the same
            // object each time and the assignment never happens). Core Animation composites the two
            // layers on the GPU and none of that is on this thread, which is exactly the point.
            func layeredFrame() {
                autoreleasepool {
                    dab(into: scratch)
                    _ = committed.renderIfNonEmpty()
                    _ = scratch.renderToUIImage()
                }
            }
            // Discard the first of each: one-time faulting, not a dab.
            rasterFrame(); compositedFrame(); layeredFrame()
            let runs = 5
            let rasterTime = measuringPeakMemory { for _ in 0..<runs { rasterFrame() } }.seconds / Double(runs)
            let compositedTime = measuringPeakMemory { for _ in 0..<runs { compositedFrame() } }.seconds / Double(runs)
            let layeredTime = measuringPeakMemory { for _ in 0..<runs { layeredFrame() } }.seconds / Double(runs)
            return (rasterTime, compositedTime, layeredTime)
        }

        let small = costs(at: Self.canvasSize)
        let large = costs(at: CGSize(width: 4096, height: 4096))
        // PERFORMANCE.md item 8: the owner's own canvas, between the two that were already here.
        let owner = costs(at: CGSize(width: 2048, height: 1024))

        report("live stroke preview, one dab", [
            ("raster2048x1024", milliseconds(owner.raster)),
            ("compositedWas2048x1024", milliseconds(owner.composited)),
            ("layeredNow2048x1024", milliseconds(owner.layered)),
            ("raster2048", milliseconds(small.raster)),
            ("compositedWas2048", milliseconds(small.composited)),
            ("layeredNow2048", milliseconds(small.layered)),
            ("raster4096", milliseconds(large.raster)),
            ("compositedWas4096", milliseconds(large.composited)),
            ("layeredNow4096", milliseconds(large.layered)),
            ("item11Speedup2048x1024", String(format: "%.1fx", owner.layered > 0 ? owner.composited / owner.layered : 0)),
            ("item11Speedup2048", String(format: "%.1fx", small.layered > 0 ? small.composited / small.layered : 0)),
            ("item11Speedup4096", String(format: "%.1fx", large.layered > 0 ? large.composited / large.layered : 0)),
            ("layeredOverRaster4096", String(format: "%.1fx", large.raster > 0 ? large.layered / large.raster : 0)),
            ("fpsCeilingLayered4096", String(format: "%.0f", large.layered > 0 ? 1 / large.layered : 0)),
            ("fpsCeilingCompositedWas4096", String(format: "%.0f", large.composited > 0 ? 1 / large.composited : 0)),
        ])

        // Ceilings only, in this file's house style — the reported numbers are the output.
        //
        // **The claim being pinned is the direction, and item 11 reversed which direction that is.**
        // Until 2026-08-20 this test asserted `vector > raster` at every size: the overlay composite
        // did strictly more work per dab than the raster path and it was not close, which was the
        // defect. It now asserts the opposite property — that the layered path has *given that gap
        // up* — because "the vector preview is slower than the raster one" is no longer something
        // anyone should be able to reintroduce quietly.
        for (name, size) in [("2048x1024", owner), ("2048", small), ("4096", large)] {
            XCTAssertLessThan(size.layered, size.composited,
                              "\(name): the layered preview must beat the bitmap composite it "
                              + "replaced — a fresh canvas-sized allocation and two blits, per dab")
            XCTAssertLessThan(size.layered, size.raster * 2,
                              "\(name): the layered preview is one canvas-sized render plus a memo "
                              + "hit, so it must land within a small multiple of the raster path's "
                              + "one render. Drifting past this means a second full-canvas "
                              + "operation crept back onto the per-touch-move path")
        }
    }

    /// **Where the two backends actually cross over on this device** — the measurement the
    /// `.automatic` default is chosen from, rather than the blanket "Metal is faster" the simulator
    /// suggested.
    ///
    /// The two have opposite shapes: Metal has roughly half the per-layer slope and roughly twice the
    /// fixed intercept (`testWhereAWarmCompositeSpendsItself` reports both), so there is a layer count
    /// below which CoreGraphics wins and above which it does not. On top of that, Metal holds a
    /// canvas-sized texture pool the CPU path does not — so the crossover that matters is not where
    /// the times are equal but where Metal's win is worth its residency.
    ///
    /// Both warm, because warm is the state the live canvas is in: a rebuild follows an edit to one
    /// layer, and every other leaf keys the same as last time.
    @MainActor
    func testWhereTheTwoBackendsCrossOverOnThisDevice() {
        warmTheGPU()

        func cost(layerCount: Int, effect: Effect?, on backend: CompositorBackend) -> Double {
            Compositor.backend = backend
            let manager = effect.map { gradedCompositorManager(layerCount: layerCount, effect: $0) }
                ?? compositorManager(layerCount: layerCount)
            guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else { return 0 }
            func once() { autoreleasepool { _ = Compositor.composite(request) } }
            once()  // warm this fixture's leaves into the upload cache
            let runs = 5
            return measuringPeakMemory { for _ in 0..<runs { once() } }.seconds / Double(runs)
        }

        var pairs: [(String, String)] = []
        for layers in [1, 2, 4, 6] {
            let cpu = cost(layerCount: layers, effect: nil, on: .coreGraphics)
            let gpu = cost(layerCount: layers, effect: nil, on: .metal)
            pairs.append(("plain\(layers)cpu", milliseconds(cpu)))
            pairs.append(("plain\(layers)gpu", milliseconds(gpu)))
        }
        let grade = Effect.brightnessContrast(Effect.BrightnessContrast(brightness: 1.2, contrast: 1.5))
        let gradedCPU = cost(layerCount: 2, effect: grade, on: .coreGraphics)
        let gradedGPU = cost(layerCount: 2, effect: grade, on: .metal)
        pairs.append(("graded2cpu", milliseconds(gradedCPU)))
        pairs.append(("graded2gpu", milliseconds(gradedGPU)))
        Compositor.backend = Compositor.defaultBackend

        report("backend crossover at 2048x2048, warm", pairs)

        // **The one direction the predicate must not get wrong.** A grading document on the CPU
        // reference snapshots the canvas and grades every pixel in Swift; on the GPU it is one more
        // dispatch over a resident texture. Two layers is the smallest stack that can carry a grade,
        // so if Metal does not win *here* the `.automatic` rule's effect clause is measuring nothing.
        XCTAssertLessThan(gradedGPU, gradedCPU,
                          "A graded composite must be cheaper on the GPU, or the effect clause is wrong")
    }

    /// One long diagonal stroke as `VectorStroke`, for the committed half of the preview above.
    private static func previewStroke(in size: CGSize) -> VectorStroke {
        let samples = (0..<60).map { step -> VectorSample in
            let t = CGFloat(step) / 59
            return VectorSample(x: 128 + t * (size.width - 256),
                                y: 128 + t * (size.height - 256),
                                pressure: 0.2 + 0.8 * sin(t * .pi))
        }
        return VectorStroke(brush: Brush(name: "Perf", shape: .softRound, size: 24),
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: 24, opacity: 1, samples: samples)
    }

    // MARK: - The device memory budget (the iPad 9 crash)

    /// The scene the owner crashed the app with, counted texture by texture.
    ///
    /// **4096², one vector layer, two value layers carrying bloom and blur, on an iPad 9th generation
    /// (`iPad12,1`, A13, 3 GB shared between CPU and GPU).** Every measurement the Metal flip rested
    /// on was taken on this Mac, where the simulator borrows desktop memory and a desktop GPU, and
    /// this is the arithmetic that hides there and does not hide on a device.
    ///
    /// The count is asserted rather than merely reported because it is the input to
    /// `CompositorBudget.affordableSize`, and a walk that starts holding one more texture than this
    /// says would size every composite too generously — silently, since the only symptom is a crash on
    /// hardware nobody runs the tests on.
    ///
    /// **The upload cache was the obvious suspect and is not the cause**, which is the finding worth
    /// leaving behind: two of the three layers are grading layers, and `renderSources` elides those
    /// (they hold no pixels), so the cache holds exactly one entry and hits on every composite of the
    /// three a sandwich rebuild runs. The 192 MB cap it used to carry never bound. What had no budget
    /// at all was the other 335 MB — the scratch pool and the effect intermediates.
    @MainActor
    func testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold() {
        let scene = compositorManager(layerCount: 1)
        scene.addValueLayer(effect: .bloom(Effect.Bloom(threshold: 0.6, radius: 12, intensity: 1)))
        scene.addValueLayer(effect: .blur(Effect.Blur(radius: 8)))
        let tree = scene.renderTree

        let canvas = CGSize(width: 4096, height: 4096)
        let perTexture = CompositorBudget.textureBytes(for: canvas)
        let walk = tree.peakCompositeTextures
        let uploads = tree.uploadableLeafCount
        let iPad9 = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024)

        report("owner's crash scene — 4096x4096, vector + bloom + blur", [
            ("perTextureMB", megabytes(UInt64(perTexture))),
            ("walkTextures", "\(walk)"),
            ("uploadableLeaves", "\(uploads)"),
            ("walkBytes", megabytes(UInt64(walk * perTexture))),
            ("totalBytes", megabytes(UInt64((walk + uploads) * perTexture))),
            ("budget3GB", megabytes(UInt64(iPad9))),
            ("cappedTo", "\(CompositorBudget.affordableSize(for: canvas, textures: walk + uploads, budgetBytes: iPad9))"),
        ])

        // Two accumulators, one grade scratch, two bloom intermediates. The blur adds nothing: it
        // wants one intermediate and the bloom already forced two, and `EffectPipelines` keeps them.
        XCTAssertEqual(walk, 5, "The walk holds front, back, one grade scratch and two bloom intermediates")
        XCTAssertEqual(uploads, 1, "Only the vector layer has pixels — a grading layer is elided from sources")
        XCTAssertGreaterThan((walk + uploads) * perTexture, iPad9,
                             "This scene must not fit a 3 GB device's budget, or the fix is measuring nothing")
    }

    /// **The budget is a fraction of the device, not a constant tuned on a Mac** — the sentence the
    /// 192 MB upload cap could not say.
    ///
    /// Pinned at four points rather than asserted as a formula, so that changing the divisor is a
    /// deliberate edit to four numbers with a device name beside each rather than a silent retune.
    func testTheTextureBudgetIsAFractionOfTheDeviceItRunsOn() {
        func budget(gigabytes: UInt64) -> Int {
            CompositorBudget.textureBudgetBytes(physicalMemory: gigabytes * 1024 * 1024 * 1024)
        }
        report("compositor texture budget by device memory", [
            ("iPad9_3GB", megabytes(UInt64(budget(gigabytes: 3)))),
            ("iPadAir_8GB", megabytes(UInt64(budget(gigabytes: 8)))),
            ("iPadPro_16GB", megabytes(UInt64(budget(gigabytes: 16)))),
            ("thisHost", megabytes(UInt64(CompositorBudget.textureBudgetBytes))),
        ])

        XCTAssertEqual(budget(gigabytes: 3), 192 * 1024 * 1024, "iPad 9: one sixteenth of 3 GB")
        XCTAssertEqual(budget(gigabytes: 8), 512 * 1024 * 1024, "8 GB iPad: one sixteenth")
        // The cap, not the sixteenth — 16 GB / 16 is a gigabyte, which is not a reasonable thing for a
        // paint program to hold while the artist is in another app.
        XCTAssertEqual(budget(gigabytes: 16), 768 * 1024 * 1024, "Capped rather than one sixteenth")
        // The floor, for a device that reports something implausible: the GPU path must not switch
        // itself off, because the CPU reference is 375x slower on any document with an effect on it.
        XCTAssertEqual(CompositorBudget.textureBudgetBytes(physicalMemory: 512 * 1024 * 1024),
                       64 * 1024 * 1024, "Floored rather than one sixteenth")
    }

    /// **What the cap does and, as importantly, where it does nothing.**
    ///
    /// A canvas that already fits comes back unchanged — byte for byte the same `CGSize` — which is
    /// what makes this safe to put on the sandwich's path: every document the branch was measured on
    /// composites at exactly the size it did before.
    func testTheBudgetShrinksOnlyTheCanvasesThatDoNotFit() {
        let iPad9 = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024)
        let textures = 6  // the owner's scene: five for the walk, one uploadable leaf

        let ordinary = CGSize(width: 2048, height: 2048)
        XCTAssertEqual(CompositorBudget.affordableSize(for: ordinary, textures: textures, budgetBytes: iPad9),
                       ordinary, "A 2048² canvas fits six textures in 192 MB and must not be touched")

        let big = CGSize(width: 4096, height: 4096)
        let capped = CompositorBudget.affordableSize(for: big, textures: textures, budgetBytes: iPad9)
        XCTAssertLessThan(capped.width, big.width, "A 4096² canvas does not fit and must be reduced")
        XCTAssertLessThanOrEqual(CompositorBudget.textureBytes(for: capped) * textures, iPad9,
                                 "The reduced size is only useful if it actually fits the budget")
        // Aspect ratio preserved, or the composite would not line up with the canvas it is stretched
        // back over. Whole pixels, for `RenderResolution.renderSize`'s reason.
        XCTAssertEqual(capped.width, capped.height, "A square canvas must stay square")
        XCTAssertEqual(capped.width, capped.width.rounded(.down), "Whole pixels only")

        report("budget cap at 3 GB, six canvas-sized textures", [
            ("canvas", "\(Int(big.width))x\(Int(big.height))"),
            ("capped", "\(Int(capped.width))x\(Int(capped.height))"),
            ("scale", String(format: "%.3f", capped.width / big.width)),
            ("footprintMB", megabytes(UInt64(CompositorBudget.textureBytes(for: capped) * textures))),
        ])
    }

    /// **The flatten memo is bounded in bytes, not only in entries** — the other 4K hole this fix
    /// closed, and the one that had nothing to do with which backend composites.
    ///
    /// `PixelOps.rasterizeCache` held 24 canvas-sized `UIImage`s, which is 1.61 GB at 4096² — more
    /// than the whole process limit on the device that crashed. And it fills on its own: the key
    /// carries `rasterVersion`, so each finished stroke mints an entry and the one it replaces stays
    /// for another twenty-three. The budget stands in for a small device here for
    /// `CompositorBudget.budgetOverrideBytes`' usual reason.
    @MainActor
    func testTheFlattenMemoIsBoundedInBytesAndNotOnlyInEntries() {
        let manager = perfManager()
        let cel = manager.layers[0].cels[0]
        let oneImage = CompositorBudget.textureBytes(for: Self.canvasSize)
        defer { CompositorBudget.budgetOverrideBytes = nil }
        // Room for two flattens and no more, so the third store has to evict.
        CompositorBudget.budgetOverrideBytes = oneImage * 2

        PixelOps.clearRasterizeCache()
        for _ in 0..<6 {
            autoreleasepool {
                _ = PixelOps.rasterize(cel: cel, canvasSize: Self.canvasSize)
                // A stroke is what moves `rasterVersion`, which is what makes a fresh key — the same
                // thing the artist does that filled this cache in the first place.
                stamp(syntheticStroke(sampleCount: 8), into: manager)
            }
        }
        let resident = PixelOps.rasterizeCacheBytes
        PixelOps.clearRasterizeCache()

        report("flatten memo under a two-image budget at 2048x2048", [
            ("perImage", megabytes(UInt64(oneImage))),
            ("budget", megabytes(UInt64(oneImage * 2))),
            ("resident", megabytes(UInt64(resident))),
        ])

        XCTAssertLessThanOrEqual(resident, oneImage * 2,
                                 "Six distinct flattens must not all stay resident under a two-image budget")
        XCTAssertGreaterThan(resident, 0, "Evicting down to nothing would stop this being a memo at all")
    }

    /// **The `.automatic` default, pinned as a rule rather than as a benchmark.**
    ///
    /// The device timings that justify the rule live in `testWhereTheTwoBackendsCrossOverOnThisDevice`
    /// and in `[RenderNode].prefersGPUCompositing`'s doc comment; this pins the *decisions* so that a
    /// later session changing the threshold has to change a stated number and a named case, not
    /// discover a silent behaviour shift on hardware nobody runs the tests on.
    @MainActor
    func testTheAutomaticBackendPrefersTheGPUOnlyWhereTheDeviceSaysItWins() {
        func tree(layers: Int, effect: Effect? = nil) -> [RenderNode] {
            let manager = compositorManager(layerCount: layers)
            if let effect { manager.addValueLayer(effect: effect) }
            return manager.renderTree
        }

        // A grade sends any stack to the GPU, at the smallest layer count that can carry one — the
        // 203.3 ms against 2.7 ms row. This is the clause that does the real work.
        XCTAssertTrue(tree(layers: 1, effect: .brightnessContrast(Effect.BrightnessContrast())).prefersGPUCompositing,
                      "One grade is 75x on this device; layer count must not be able to veto it")
        XCTAssertTrue(tree(layers: 1, effect: .bloom(Effect.Bloom())).prefersGPUCompositing,
                      "A multi-pass grade even more so")

        // Below the threshold and ungraded, the CPU keeps it: Metal would buy about a millisecond a
        // composite and cost ~80 MB of resident texture on a 3 GB device.
        XCTAssertFalse(tree(layers: 1).prefersGPUCompositing)
        XCTAssertFalse(tree(layers: 3).prefersGPUCompositing)
        // At and above it the slope difference has paid for the residency.
        XCTAssertTrue(tree(layers: 4).prefersGPUCompositing)
        XCTAssertTrue(tree(layers: 8).prefersGPUCompositing)

        XCTAssertEqual(Array<RenderNode>.gpuLeafThreshold, 4,
                       "Moving the threshold is a device-measurement decision; see prefersGPUCompositing")
        XCTAssertEqual(Compositor.defaultBackend, .automatic,
                       "The shipped default is the predicate, not either backend")

        report("automatic backend predicate", [
            ("threshold", "\(Array<RenderNode>.gpuLeafThreshold)"),
            ("oneLayerPlain", "\(tree(layers: 1).prefersGPUCompositing)"),
            ("fourLayersPlain", "\(tree(layers: 4).prefersGPUCompositing)"),
            ("oneLayerGraded", "\(tree(layers: 1, effect: .bloom(Effect.Bloom())).prefersGPUCompositing)"),
        ])
    }

    /// **The refusal is wired, and refusing still produces a frame.**
    ///
    /// The three cases above are arithmetic; this one runs it. `budgetOverrideBytes` stands in for a
    /// device too small to hold the composite — the seam exists because no test host is that device,
    /// which is the whole reason this shipped — and the two things worth asserting are that the engine
    /// says so rather than allocating anyway, and that `Compositor.composite` still hands back the
    /// picture. A budget that turned a large canvas into a black frame would be a worse bug than the
    /// one it fixes.
    @MainActor
    func testAnOverBudgetCompositeIsDeclinedByTheGPUAndStillRendersOnTheCPU() throws {
        let engine = try XCTUnwrap(CompositorMetalEngine.shared,
                                   "This case is about the GPU engine's admission decision")
        let manager = compositorManager(layerCount: 2)
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("The perf manager must produce a request")
        }

        Compositor.backend = .coreGraphics
        let reference = Compositor.composite(request)

        Compositor.backend = .metal
        defer {
            CompositorBudget.budgetOverrideBytes = nil
            Compositor.backend = Compositor.defaultBackend
        }
        // One byte under what two accumulators alone would cost, so the walk cannot be admitted at any
        // layer count — the same shape as a 4096² canvas against 192 MB, at a size a test can afford.
        CompositorBudget.budgetOverrideBytes = CompositorBudget.textureBytes(for: Self.canvasSize) * 2 - 1
        let declined = Compositor.composite(request)

        XCTAssertEqual(engine.lastAdmission,
                       .overBudget(wantedBytes: request.tree.peakCompositeTextures
                                       * CompositorBudget.textureBytes(for: Self.canvasSize),
                                   budgetBytes: CompositorBudget.budgetOverrideBytes ?? 0),
                       "The engine must refuse before it allocates, and say why")
        XCTAssertNotNil(declined, "A declined GPU composite falls back to the reference, not to nothing")
        XCTAssertEqual(declined?.width, reference?.width)
        XCTAssertEqual(declined?.height, reference?.height)

        // And the budget being restored puts the GPU back on the path — a one-way valve would be a
        // performance regression that no other case here would catch.
        CompositorBudget.budgetOverrideBytes = nil
        _ = Compositor.composite(request)
        XCTAssertEqual(engine.lastAdmission, .admitted,
                       "With the device's own budget back, the same request is admitted")
    }

    // MARK: - Onion skin

    /// **What ten onion skins actually cost, on whatever machine this runs on.**
    ///
    /// The design claim is that N skins flatten into *one* image, so N buys draw time and not
    /// memory. This measures both halves at the size a 4096² document would actually composite at
    /// (`OnionSkinBudget`, against a stated 3 GB-device budget so the number describes the owner's
    /// iPad 9 rather than the host). Read the `PERF BASELINE` line; the assertions are this file's
    /// usual order-of-magnitude ceilings.
    ///
    /// **Tinted, because tinted is the default**, plus one untinted run for comparison — and that
    /// comparison corrected an assumption worth recording. A tint opens a transparency layer and
    /// fills it, so it looked like the expensive half; measured, ten tinted skins cost about a
    /// quarter more than ten untinted ones. **The cost is the draw itself, not the tint**, which
    /// means "switch to Original Colors" is not an escape hatch from a slow onion skin and the count
    /// is the only real lever.
    ///
    /// ### Why this warms up, times without the memory sampler, and takes a minimum
    ///
    /// The first version of this took **one sample per figure, with the peak-memory sampler thread
    /// running inside the timed region**, and on the owner's iPad 9 it reported `skins5 = 153.9 ms`
    /// against `skins10 = 136.9 ms` — ten skins apparently cheaper than five, which cannot be true of
    /// a loop that draws each skin once.
    ///
    /// It was not the source cache, and ruling that out is a matter of reading rather than measuring:
    /// the three `skinsN` figures call `OnionSkinFrame.composite` directly on frames built from one
    /// image made *before* the loop at skin size, and `composite` is a pure function that touches no
    /// cache at all. `OnionSkinRasterCache` is not reached until `sourceMiss` further down.
    ///
    /// Two things could inflate a single early sample, and this now removes both:
    ///
    ///  * **A cold CPU.** `skins1` is ~12 ms, far too short a burst for iOS to raise the clock, so
    ///    `skins5` was the first sustained work in the process and paid the ramp; by `skins10` the
    ///    cores were up. A Mac under sustained load from several agents is already at a high clock,
    ///    which is exactly why the simulator stayed monotonic and the device did not. `skins5Cold`
    ///    below is reported precisely so the next device run can confirm or refute this: it is the
    ///    very first composite in the process, and if it is far above the warmed `skins5` then this
    ///    was the mechanism.
    ///  * **The sampler thread.** `measuringPeakMemory` busy-polls `task_info` every 2 ms at
    ///    `.userInitiated`, which on a 2+4-core A13 competes for a core with the thing it is timing.
    ///    It cannot explain *this* inversion (its cost grows with duration, so it would inflate
    ///    `skins10` more, not less) but it has no business inside a timing measurement, so memory is
    ///    now sampled in its own pass.
    ///
    /// **The monotonicity assertion at the bottom is the point of the whole exercise.** A figure that
    /// reads as a warm draw has to be one; if the ordering ever inverts again the test fails and says
    /// so, rather than printing a number a later session would reasonably misread. That is the same
    /// rule as "a green suite that ran nothing", applied to a benchmark.
    ///
    /// This is the number the device check hangs on. If ten skins cost more than a frame on the
    /// owner's hardware, `OnionSkinSettings.maxSkinsPerSide` is the lever, and it is one constant.
    func testOnionSkinCompositeCostScalesWithSkinCountAndNotWithMemory() {
        let canvas = CGSize(width: 4096, height: 4096)
        // A 3 GB device's texture budget, stated rather than read, for
        // `CompositorBudget.textureBudgetBytes(physicalMemory:)`'s reason.
        let size = OnionSkinBudget.compositeSize(for: canvas, resolution: .quarter)

        // **Sources at skin resolution, because that is what the app now hands the composite.**
        // `OnionSkinRasterCache` reduces each cel once per version and the composite draws it 1:1;
        // measuring from a canvas-sized source would measure the code as it was before that fix and
        // report a number the app no longer pays. The reduction itself is measured separately, below.
        let source = CanvasFixture.solidImage(.red,
                                              rect: CGRect(x: 0, y: 0, width: size.width * 0.6,
                                                           height: size.height * 0.6),
                                              size: size)
        func skins(_ n: Int, tinted: Bool) -> [OnionSkinFrame] {
            (0..<n).map { OnionSkinFrame(image: source, opacity: CGFloat(n - $0) / CGFloat(n),
                                         tint: tinted ? .systemRed : nil) }
        }

        var timings: [(String, String)] = [("compositeSize", "\(Int(size.width))x\(Int(size.height))")]

        // **First, before anything else in this process**: one cold sample of the five-skin case, the
        // figure that inverted on the device. Reported beside the warmed one so the next device run
        // settles what caused it rather than leaving it argued.
        let coldStart = CFAbsoluteTimeGetCurrent()
        autoreleasepool { _ = OnionSkinFrame.composite(skins(5, tinted: true), size: size) }
        timings.append(("skins5Cold", milliseconds(CFAbsoluteTimeGetCurrent() - coldStart)))

        // Warm: every count run once, untimed, so no reported figure pays a first-touch page fault or
        // a clock ramp that belongs to the measurement before it.
        for count in [1, 5, 10] {
            autoreleasepool { _ = OnionSkinFrame.composite(skins(count, tinted: true), size: size) }
        }

        // Timed with no sampler thread in the way, minimum of five — contention and DVFS can only
        // ever make a sample longer, so the minimum is the one least contaminated by either.
        func timeMin(_ repeats: Int = 5, _ body: () -> Void) -> Double {
            var best = Double.greatestFiniteMagnitude
            for _ in 0..<repeats {
                let start = CFAbsoluteTimeGetCurrent()
                autoreleasepool { body() }
                best = Swift.min(best, CFAbsoluteTimeGetCurrent() - start)
            }
            return best
        }

        var warm: [Int: Double] = [:]
        for count in [1, 5, 10] {
            warm[count] = timeMin { _ = OnionSkinFrame.composite(skins(count, tinted: true), size: size) }
            timings.append(("skins\(count)", milliseconds(warm[count] ?? 0)))
        }

        // Memory in its own pass, where the sampler thread costs the timings nothing. Each result is
        // held so the peak reflects a composite that actually exists — the claim under test is that
        // this figure does not grow with the skin count.
        var images: [Int: UIImage?] = [:]
        for count in [1, 5, 10] {
            let run = measuringPeakMemory { autoreleasepool { images[count] = OnionSkinFrame.composite(skins(count, tinted: true), size: size) } }
            timings.append(("peak\(count)", megabytes(run.peakBytes)))
        }

        // The same ten skins untinted, so the two colouring modes are compared rather than guessed at.
        // See the doc comment: this pair is what showed the tint is a quarter of the cost and the
        // draw is the rest.
        timings.append(("skins10Untinted", milliseconds(timeMin { _ = OnionSkinFrame.composite(skins(10, tinted: false), size: size) })))

        // **What a cache miss costs, which is the other half of a rebuild.** A skin whose cel has not
        // been reduced to this size yet pays one downscale from the canvas-sized rasterize; after
        // that every rebuild the cel appears in is a hit. Measured on a real `Cel` rather than a bare
        // image, so the `PixelOps.rasterize` the reduction reads through is in the number.
        var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvas))
        cel.bakedImage = CanvasFixture.solidImage(.blue, rect: CGRect(x: 0, y: 0, width: canvas.width * 0.6,
                                                                     height: canvas.height * 0.6), size: canvas)
        // A miss is *inherently* cold, so it cannot be warmed — but it can still be repeated, with the
        // cache cleared before each attempt, and the minimum taken. Without that this figure swung
        // from 119 ms to 256 ms between two runs on the same code purely with machine load.
        var bestMiss = Double.greatestFiniteMagnitude
        for _ in 0..<4 {
            OnionSkinRasterCache.removeAll()
            let start = CFAbsoluteTimeGetCurrent()
            autoreleasepool { _ = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: size) }
            bestMiss = Swift.min(bestMiss, CFAbsoluteTimeGetCurrent() - start)
        }
        timings.append(("sourceMiss", milliseconds(bestMiss)))
        timings.append(("sourceHit", milliseconds(timeMin { _ = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: size) })))
        timings.append(("cacheResident", megabytes(UInt64(OnionSkinRasterCache.residentBytes))))
        timings.append(("residentCeiling", megabytes(UInt64(OnionSkinBudget.residentCeilingBytes(for: canvas, resolution: .quarter)))))
        report("onion skin composite, 4096x4096 canvas on a 3 GB device", timings)
        OnionSkinRasterCache.removeAll()

        for count in [1, 5, 10] {
            guard let image = images[count] ?? nil else { return XCTFail("\(count) skins must composite") }
            // The whole memory argument, asserted rather than asserted-about: ten skins produce one
            // image, the same size as one skin's.
            XCTAssertEqual(image.size, size, "\(count) skins must flatten into exactly one image of the budgeted size")
        }
        XCTAssertLessThan(size.width, canvas.width,
                          "a 4096 canvas at Quarter must composite below native — otherwise the resolution rule is inert")

        // **The ordering, asserted rather than printed.** `composite` draws each skin once, so more
        // skins must cost more; a figure that says otherwise is measuring something other than the
        // warm draw its name claims, and a later session would read it as gospel. The multipliers are
        // deliberately far below the real ratios (about 6x and 2x on every host measured) so this
        // fails on an inversion and not on a noisy machine — the device figure that prompted it had
        // ten skins at 0.89x five, which this catches with room to spare.
        guard let one = warm[1], let five = warm[5], let ten = warm[10] else {
            return XCTFail("every count must have been timed")
        }
        XCTAssertGreaterThan(five, one * 1.5,
                             "five skins must cost meaningfully more than one — got \(milliseconds(five)) against \(milliseconds(one))")
        XCTAssertGreaterThan(ten, five * 1.2,
                             "ten skins must cost more than five — got \(milliseconds(ten)) against \(milliseconds(five)). "
                             + "If this fails on the device with skins5Cold near the old 153.9 ms, the cold-clock reading was right; "
                             + "if it fails with skins5Cold close to skins5, it is something else and worth finding.")
    }

    /// **Is an onion composite bound by the pixels it writes, or by the pixels it reads?** The whole
    /// resolution decision turns on this and it cannot be reasoned out: `CGContext.draw(in:)` with a
    /// smaller destination still *samples* the whole source, so shrinking the composite might buy
    /// nothing at all.
    ///
    /// Two sweeps, both ten tinted skins, run back to back in one process so the ratios survive a
    /// loaded machine even where the absolute numbers do not (CLAUDE.md: five concurrent runs make
    /// this Mac return wrong answers, and a ratio between two adjacent measurements is the part that
    /// still holds).
    ///
    ///  1. **Destination sweep** — one 4096² source, four destination sizes. Falling with destination
    ///     area means the write dominates and shrinking the composite is the whole fix.
    ///  2. **Source isolation** — the same 1024² destination, from a 4096² source and from a 1024²
    ///     one. A large gap means the *read* dominates, and the fix is to rasterize the cels smaller
    ///     rather than to shrink the composite.
    func testOnionSkinCompositeCostIsBoundByDestinationOrBySourcePixels() {
        let canvas = CGSize(width: 4096, height: 4096)
        func source(_ size: CGSize) -> UIImage {
            CanvasFixture.solidImage(.red,
                                     rect: CGRect(x: 0, y: 0, width: size.width * 0.6, height: size.height * 0.6),
                                     size: size)
        }
        func skins(_ n: Int, from image: UIImage) -> [OnionSkinFrame] {
            (0..<n).map { OnionSkinFrame(image: image, opacity: CGFloat(n - $0) / CGFloat(n), tint: .systemRed) }
        }
        // **The minimum of several runs, not one run, and not the mean.** The first version of this
        // test took a single sample and reported `dest2508 = 10244 ms` for work measured at 1178 ms
        // half an hour earlier — the machine was at 1.3% idle, which CLAUDE.md records as the state
        // where a suite "does not merely run slowly, it returns wrong answers". Contention can only
        // ever make a measurement *longer*, so the minimum is the sample least contaminated by it,
        // and taking it is what lets this run at all on a Mac with four other agents on it.
        func time(_ repeats: Int = 4, _ body: () -> Void) -> Double {
            var best = Double.greatestFiniteMagnitude
            for _ in 0..<repeats {
                let start = CFAbsoluteTimeGetCurrent()
                autoreleasepool { body() }
                best = Swift.min(best, CFAbsoluteTimeGetCurrent() - start)
            }
            return best
        }

        let big = source(canvas)
        var destination: [(String, String)] = []
        var baseline: Double = 0
        for edge in [2508.0, 1254.0, 1024.0, 627.0] {
            let size = CGSize(width: edge, height: edge)
            let seconds = time { _ = OnionSkinFrame.composite(skins(10, from: big), size: size) }
            if edge == 2508 { baseline = seconds }
            // The share of the 2508² cost this size still pays, beside the share of the pixels it
            // writes. Equal shares mean write-bound; a cost share far above the pixel share means the
            // source read is being paid whatever the destination is.
            destination.append(("dest\(Int(edge))", String(format: "%@ (cost %.2f, pixels %.2f)",
                                                           milliseconds(seconds),
                                                           baseline > 0 ? seconds / baseline : 1,
                                                           (edge * edge) / (2508.0 * 2508.0))))
        }
        report("onion composite, destination sweep from a 4096² source, 10 tinted skins", destination)

        let target = CGSize(width: 1024, height: 1024)
        let fromBig = time { _ = OnionSkinFrame.composite(skins(10, from: big), size: target) }
        let small = source(target)
        let fromSmall = time { _ = OnionSkinFrame.composite(skins(10, from: small), size: target) }
        report("onion composite, source isolation at a 1024² destination, 10 tinted skins", [
            ("from4096Source", milliseconds(fromBig)),
            ("from1024Source", milliseconds(fromSmall)),
            ("speedup", String(format: "%.2fx", fromSmall > 0 ? fromBig / fromSmall : 0)),
        ])

        // No timing assertion — this test exists to print two ratios, and this file's header is
        // explicit that simulator timings are not assertable. The only thing worth failing on is the
        // premise: both paths really did produce a composite of the size asked for.
        XCTAssertEqual(OnionSkinFrame.composite(skins(10, from: big), size: target)?.size, target)
        XCTAssertEqual(OnionSkinFrame.composite(skins(10, from: small), size: target)?.size, target)
    }

    /// **What each resolution option costs, so "Full" is a fact rather than a surprise.**
    ///
    /// The artist picks a fraction of canvas resolution in the onion-skin panel (owner, 2026-08-17)
    /// and the panel cannot say what that costs — this can. Two skin counts are reported per option:
    /// the shipped default of one either side, which is what most artists will ever pay, and ten,
    /// which is the ceiling they can dial in.
    ///
    /// Sources are pre-reduced and the cache pre-warmed, because that is the steady state the app
    /// runs in: a rebuild happens when the playhead changes drawing, and by then the drawings in the
    /// window have been reduced once each. `sourceMiss` in the test above is the other half.
    func testOnionSkinCostOfEachResolutionOption() {
        // The owner's iPad 9 has 3 GB, and `CompositorBudget.textureBudgetBytes` is a sixteenth of
        // that. Stated rather than read, for `textureBudgetBytes(physicalMemory:)`'s reason: the
        // figures below describe that device, not whichever machine is running the test.
        let threeGigabyteTextureBudget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 * 1024 * 1024 * 1024)
        func timeMin(_ repeats: Int = 4, _ body: () -> Void) -> Double {
            var best = Double.greatestFiniteMagnitude
            for _ in 0..<repeats {
                let start = CFAbsoluteTimeGetCurrent()
                autoreleasepool { body() }
                best = Swift.min(best, CFAbsoluteTimeGetCurrent() - start)
            }
            return best
        }

        func measure(_ canvas: CGSize, _ label: String) {
            var rows: [(String, String)] = []
            for resolution in OnionSkinSettings.Resolution.allCases {
                let size = OnionSkinBudget.compositeSize(for: canvas, resolution: resolution)
                let source = CanvasFixture.solidImage(.red,
                                                      rect: CGRect(x: 0, y: 0, width: size.width * 0.6,
                                                                   height: size.height * 0.6),
                                                      size: size)
                func skins(_ n: Int) -> [OnionSkinFrame] {
                    (0..<n).map { OnionSkinFrame(image: source, opacity: CGFloat(n - $0) / CGFloat(n),
                                                 tint: .systemRed) }
                }
                // Warm, for `testOnionSkinCompositeCostScalesWithSkinCountAndNotWithMemory`'s reason: a
                // cold clock inverted two of its figures on the device.
                autoreleasepool { _ = OnionSkinFrame.composite(skins(10), size: size) }

                let name = resolution.title
                rows.append(("\(name)Size", "\(Int(size.width))x\(Int(size.height))"))
                rows.append(("\(name)Default2", milliseconds(timeMin { _ = OnionSkinFrame.composite(skins(2), size: size) })))
                rows.append(("\(name)Max10", milliseconds(timeMin { _ = OnionSkinFrame.composite(skins(10), size: size) })))
                rows.append(("\(name)Ceiling", megabytes(UInt64(OnionSkinBudget.residentCeilingBytes(for: canvas, resolution: resolution)))))
                // **What producing one skin's source costs at this option, which is the half the two
                // rows above leave out.** They composite from a pre-reduced source; this is the price
                // of getting that source in the first place, and at Full it is not zero merely
                // because `OnionSkinRasterCache` stores nothing there — the work moves to
                // `PixelOps.rasterize` at canvas size, it does not disappear. Both caches are cleared
                // per attempt, because a miss is inherently cold and the memoized Full path would
                // otherwise report a hit.
                var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvas))
                cel.bakedImage = CanvasFixture.solidImage(.blue,
                                                          rect: CGRect(x: 0, y: 0, width: canvas.width * 0.6,
                                                                       height: canvas.height * 0.6),
                                                          size: canvas)
                var bestMiss = Double.greatestFiniteMagnitude
                for _ in 0..<4 {
                    OnionSkinRasterCache.removeAll()
                    PixelOps.clearRasterizeCache()
                    let start = CFAbsoluteTimeGetCurrent()
                    autoreleasepool { _ = OnionSkinRasterCache.image(for: cel, canvasSize: canvas, at: size) }
                    bestMiss = Swift.min(bestMiss, CFAbsoluteTimeGetCurrent() - start)
                }
                rows.append(("\(name)SourceMiss", milliseconds(bestMiss)))
                rows.append(("\(name)Cached", "\(OnionSkinBudget.cachedSourceCount(for: canvas, resolution: resolution, sharedBudgetBytes: threeGigabyteTextureBudget))"))
                rows.append(("\(name)Est10", milliseconds(OnionSkinBudget.estimatedRebuildMilliseconds(
                    for: canvas, resolution: resolution, skins: 10,
                    sharedBudgetBytes: threeGigabyteTextureBudget) / 1000)))
                OnionSkinRasterCache.removeAll()
                PixelOps.clearRasterizeCache()
            }
            report("onion skin cost per resolution option, \(label)", rows)
        }

        // **The owner animates at 2048x1024** (TODO.md, 2026-08-17), and every onion figure this
        // project has recorded was taken at 4096x4096 — eight times the pixels. The ruling on whether
        // "Full" needs a warning in the UI turns on this table, not on the one below it, so it is
        // measured first and the 4K case is kept as the stress case it always was.
        let owner = CGSize(width: 2048, height: 1024)
        measure(owner, "2048x1024 — the owner's canvas")
        measure(CGSize(width: 4096, height: 4096), "4096x4096 — the stress case")

        // Structural, not a timing threshold: the options have to actually differ, or the control the
        // owner asked for is decoration.
        let sizes = OnionSkinSettings.Resolution.allCases.map {
            OnionSkinBudget.compositeSize(for: CGSize(width: 4096, height: 4096), resolution: $0)
        }
        XCTAssertEqual(Set(sizes.map(\.width)).count, sizes.count,
                       "every resolution option must produce a different size on a 4096 canvas")

        // **At the owner's canvas the readability floor is load-bearing, and it changes what the
        // control means.** A naive quarter of 2048 is 512, which `readableFloorEdge` raises to 768 —
        // so Half and Quarter are 1024 and 768 rather than 1024 and 512, a 1.8x gap in area where the
        // 4K table shows 4x. Pinned rather than described, because the whole argument about which
        // option an artist should reach for rests on it.
        XCTAssertEqual(OnionSkinBudget.compositeSize(for: owner, resolution: .full), owner,
                       "Full must be the canvas itself, never scaled")
        XCTAssertEqual(OnionSkinBudget.compositeSize(for: owner, resolution: .half),
                       CGSize(width: 1024, height: 512))
        XCTAssertEqual(OnionSkinBudget.compositeSize(for: owner, resolution: .quarter),
                       CGSize(width: 768, height: 384),
                       "the readability floor must raise Quarter above the naive 512x256")
    }

    // MARK: - Opening a project (PERFORMANCE.md item 9)

    /// How many layers and cels the open measurement uses. **Four layers of eight drawings each** is a
    /// modest but real animation document; the figure that matters is reported *per cel*, because the
    /// loop `ProjectStore.load` runs is bounded by the manifest's cel tree and nothing else, so a
    /// hundred-cel project extrapolates from it directly.
    private static let openLayerCount = 4
    private static let openCelsPerLayer = 8

    /// Real ink on one cel: three wavy strokes crossing the canvas.
    ///
    /// **A blank cel would make the whole measurement a lie in the cheap direction.** A transparent
    /// PNG compresses to almost nothing and inflates to almost nothing, so a document of empty cels
    /// would measure the `CGContext` allocation and nothing else — and the allocation is the half that
    /// does *not* depend on what the artist drew.
    private func inkOneCel(_ raster: RasterLayerTexture, canvas: CGSize, brush: Brush, seed: Int) {
        for strokeIndex in 0..<3 {
            let baseline = canvas.height * CGFloat(strokeIndex + 1) / 4
            let samples: [BrushStamper.Sample] = (0..<80).map { step in
                let t = CGFloat(step) / 79
                let y = baseline + sin(t * .pi * 3 + CGFloat(seed) * 0.7) * canvas.height * 0.15
                return BrushStamper.Sample(point: CGPoint(x: canvas.width * t, y: y),
                                           pressure: 0.3 + 0.7 * sin(t * .pi))
            }
            BrushStamper.stampStroke(into: raster, samples: samples, brush: brush,
                                     color: .black, brushSize: 18, brushOpacity: 1)
            raster.endStroke()
        }
    }

    /// `layerCount` raster layers of `celsPerLayer` cels each at the owner's 2048x1024, every cel
    /// carrying ink.
    ///
    /// Cels are built directly rather than through `addCel`, which would refuse them: `addLayer`
    /// gives its first cel `frameCount: max(sceneFrameCount, 1)`, so it already spans every frame a
    /// second cel could start on.
    ///
    /// **Raster layers only, and that makes the number a floor rather than a ceiling.** A vector cel
    /// re-stamps its whole display list through `BrushStamper` on the first render, which is a cost
    /// with no counterpart on the raster path — a document with vector layers in it opens for more
    /// than this, not less.
    @MainActor
    private func multiCelDocument(layerCount: Int, celsPerLayer: Int) -> CanvasManager {
        let canvas = Self.ownersCanvasSize
        let manager = CanvasManager()
        manager.canvasSize = canvas
        manager.fps = 24
        manager.sceneFrameCount = celsPerLayer * 2
        for layerIndex in 0..<layerCount {
            manager.addLayer(name: "Layer \(layerIndex)")
            manager.layers[layerIndex].cels = (0..<celsPerLayer).map { celIndex in
                Cel(id: UUID(), startFrame: celIndex * 2, frameCount: 2, raster: .empty(size: canvas))
            }
            for celIndex in 0..<celsPerLayer {
                autoreleasepool {
                    inkOneCel(manager.layers[layerIndex].cels[celIndex].raster, canvas: canvas,
                              brush: manager.selectedBrush, seed: layerIndex * celsPerLayer + celIndex)
                }
            }
        }
        return manager
    }

    /// **What tapping a project in the gallery actually costs**, split into the per-cel decode and
    /// `regenerateAllThumbnails()` — PERFORMANCE.md §6's "largest unmeasured quantity in the app",
    /// and item 9(a).
    ///
    /// Nobody could say whether §2 item 2 was 200 ms or 4 s. The spinner that shipped on 2026-08-20
    /// changed what the wait looks like and not how long it is, so the ranking of every remaining
    /// item rested on an INFERRED "plausibly 1-3 s". This is the run that replaces it.
    ///
    /// **Read `msPerCel`, not the total.** The total is a property of this fixture; the per-cel figure
    /// is the one that transfers, because the decode loop's bound is the cel tree. The split between
    /// the two halves is the other durable output: it is what says whether item 9(b) or 9(c) is the
    /// bigger half before either is built.
    ///
    /// **And read the count, which is not a timing at all.** A load rasterizes every cel once for its
    /// thumbnail, guaranteed cache-cold — every texture the decode just built is a new object identity
    /// at version 0, so nothing memoized on cel identity can hit. That is an integer about the calls,
    /// so it survives a contended machine in a way milliseconds do not, and it is what 9(c) has to
    /// move rather than merely shrink.
    @MainActor
    func testWhatOpeningAMultiCelProjectCosts() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-open-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: root)
        }

        let layerCount = Self.openLayerCount, celsPerLayer = Self.openCelsPerLayer
        let url = ProjectStore.createNewProjectURL(name: "Perf Open")
        var saveSeconds = 0.0
        autoreleasepool {
            let authored = multiCelDocument(layerCount: layerCount, celsPerLayer: celsPerLayer)
            let written = expectation(description: "the package is on disk")
            let start = CFAbsoluteTimeGetCurrent()
            ProjectStore.save(authored, to: url) { written.fulfill() }
            wait(for: [written], timeout: 600)
            saveSeconds = CFAbsoluteTimeGetCurrent() - start
        }

        // The flatten memo must not be able to answer for a cel this load is about to rebuild. It
        // cannot in the app — a fresh launch has an empty cache — and it holds entries here only
        // because the authoring document above was built in the same process.
        PixelOps.clearRasterizeCache()

        var manager: CanvasManager?
        let open = measuringPeakMemory { manager = ProjectStore.load(from: url) }
        guard let manager, let profile = ProjectStore.lastLoadProfile else {
            return XCTFail("The package this test just wrote must open")
        }

        report("project open, \(layerCount) layers x \(celsPerLayer) cels at 2048x1024", [
            ("cels", "\(profile.celCount)"),
            ("total", milliseconds(profile.totalSeconds)),
            ("decode", milliseconds(profile.decodeSeconds)),
            ("thumbnails", milliseconds(profile.thumbnailSeconds)),
            ("thumbnailShare", String(format: "%.2f", profile.thumbnailShare)),
            ("msPerCel", String(format: "%.1f", profile.millisecondsPerCel)),
            ("at100Cels", milliseconds(profile.millisecondsPerCel * 100 / 1000)),
            ("thumbnailRegens", "\(profile.thumbnailRegenerations)"),
            ("peak", megabytes(open.peakBytes)),
            ("saveForReference", milliseconds(saveSeconds)),
        ])

        // Structure, not timing — these hold on any machine at any load.
        XCTAssertEqual(profile.layerCount, layerCount)
        XCTAssertEqual(profile.celCount, layerCount * celsPerLayer)
        XCTAssertEqual(manager.layers.count, layerCount)
        // The headless half of item 9(a): opening an N-cel project costs exactly N uncached
        // thumbnail rasterizes, on the main actor, after an N-cel decode has already run.
        XCTAssertEqual(profile.thumbnailRegenerations, profile.celCount,
                       "Every cel is rasterized once for its thumbnail during a load, and the cache cannot help — see `LoadProfile`")
        // An order-of-magnitude ceiling in this file's house style. Read the reported numbers; do not
        // tighten this into a timing assertion on a machine that runs several suites at once.
        XCTAssertLessThan(profile.totalSeconds, 120.0,
                          "Opening a 32-cel project taking two minutes is structural, not contention")
    }
}
