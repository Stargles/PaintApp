import XCTest
import UIKit
import Darwin

/// **How many brush strokes a vector cel holds before drawing on it stops feeling instant.**
///
/// A measurement harness, not a regression suite: the owner is about to make an architecture
/// decision on the upper bound and does not know what it is. Everything here answers one of four
/// questions, and each has its own test:
///
/// 1. *What actually invalidates the cel's render memo* — demonstrated with `lastRenderDabCount`
///    and `rasterizations` rather than read off the source, because "it re-walks everything" is a
///    claim about dabs stamped and those are countable.
/// 2. *The curve* — full re-walk cost against stroke count, pushed past the owner's "couple
///    thousand" until it breaks or plainly stops being linear.
/// 3. *The pen-up-to-pixels number*, split into what runs on the main thread (the artist's freeze)
///    and what runs on `StrokeCanvasView.renderQueue` (the artist's stale base). Conflating those
///    two would make the whole exercise useless: a 400 ms background bake and a 400 ms main-thread
///    stall are different answers to "no lagspike, no latency".
/// 4. *The size of the incremental-append prize*, if (2) says it matters — which (2) said it did,
///    so (4) is now the **re-measurement of the shipped path** rather than the spike it started as.
///
/// **This class is minutes of wall clock and is opt-in for that reason**, not because it is
/// disposable: it is the only harness that measures the render's cost model, and every figure in
/// PERFORMANCE.md §11 came out of it.
///
/// It is deliberately *not* named `…LogicTests`, so CLAUDE.md's fast-tier selector does not pick it
/// up. Run it by name:
/// ```
/// -only-testing:PaintSoftwareUITests/StrokeDensityBench
/// ```
final class StrokeDensityBench: XCTestCase {

    /// **Opt-in, and the reason is the full suite rather than tidiness.** Staying out of the
    /// fast-tier selector by name keeps these off the tier that runs constantly, but the full suite
    /// runs every class it can find, and `xcodebuild` distributes parallel work **per test class**,
    /// so an indivisible class of tests measuring 23.5 s and 35.8 s apiece would set the whole
    /// suite's critical path on its own — CLAUDE.md's cost model, and the trap it records twice of a
    /// class growing past the floor while nobody looks.
    ///
    /// It is also unsafe to run them together unattended: the numbers in PERFORMANCE.md §11 were
    /// taken against an XCTest runner whose **cumulative-CPU watchdog SIGKILLs the process**, which
    /// is what the 64,000-stroke row was originally misread as jetsam. A 23.5 s test passes alone
    /// and dies when it follows a 35.8 s one in the same process, so these would not merely be slow
    /// in a full run, they would be an intermittent red that looks environmental.
    ///
    /// Re-measure deliberately — and note the **`TEST_RUNNER_` prefix**, which is not decoration:
    /// ```
    /// TEST_RUNNER_PAINTAPP_BENCH=1 xcodebuild test -configuration Release … \
    ///   -only-testing:PaintSoftwareUITests/StrokeDensityBench
    /// ```
    /// A bare `PAINTAPP_BENCH=1` sets it for **`xcodebuild`**, not for the runner process on the
    /// device, so `setUpWithError` skips every test and the run reports `** TEST SUCCEEDED **` with
    /// two skips — CLAUDE.md's banner-versus-count trap wearing one more costume. `xcodebuild`
    /// forwards `TEST_RUNNER_`-prefixed variables to the runner with the prefix stripped. Read the
    /// `STROKE BENCH |` lines, not the banner: no lines means nothing ran.
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "StrokeDensityBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
    }

    // MARK: - The scene

    /// The owner's canvas (PERFORMANCE.md §1), not the 2048² the older baselines use.
    private static let canvasSize = CGSize(width: 2048, height: 1024)

    /// A realistic line-art stroke: a gentle arc ~400 pt long — roughly a fifth of the canvas's
    /// width, which is what a single confident pen gesture covers — sampled 40 times.
    ///
    /// The owner's unit is strokes and the renderer's unit is **dabs**, so both are reported
    /// everywhere below. At `brushSize` 18 and the default `spacingFraction` 0.1,
    /// `BrushStamper.stampSpacing` is 1.8 pt, so a 400 pt arc is ~230 dabs. Changing either
    /// constant moves every number in this file proportionally to the dab count, not to the stroke
    /// count — which is the first thing to say to anyone quoting these figures at a different brush.
    private static let strokeLengthPoints: CGFloat = 400
    private static let samplesPerStroke = 40
    private static let brushSize: CGFloat = 18

    private static let benchBrush = Brush(name: "Bench", tip: .round, size: brushSize)

    /// Deterministic placement, so a run is comparable with the run before it.
    private static func benchStroke(_ index: Int, canvas: CGSize = canvasSize,
                                    composite: StrokeComposite = .paint) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset: CGFloat = 48
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        let length = strokeLengthPoints
        // Turn the direction inward when the far end would leave the canvas, so every stroke's
        // whole path is on-canvas: a dab CoreGraphics clips away still costs the walk that produced
        // it, and a scene that spills would understate the ink and overstate nothing.
        var ux = cos(angle), uy = sin(angle)
        if x0 + ux * length < inset || x0 + ux * length > canvas.width - inset { ux = -ux }
        if y0 + uy * length < inset || y0 + uy * length > canvas.height - inset { uy = -uy }
        var samples = StrokeSamples(channels: .pressureOnly)
        samples.reserveCapacity(samplesPerStroke)
        for step in 0..<samplesPerStroke {
            let t = CGFloat(step) / CGFloat(samplesPerStroke - 1)
            let bend = sin(t * .pi) * length * 0.16
            let dx = ux * t * length - uy * bend
            let dy = uy * t * length + ux * bend
            samples.append(VectorSample(x: x0 + dx, y: y0 + dy,
                                        pressure: 0.25 + 0.75 * sin(t * .pi)))
        }
        return VectorStroke(brush: benchBrush,
                            color: CodableColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            size: brushSize, opacity: 1, samples: samples, composite: composite)
    }

    private static func scene(_ n: Int) -> [VectorStroke] { (0..<n).map { benchStroke($0) } }

    /// Bytes of stroke geometry, by arithmetic over the stored representation — INFERRED, and
    /// reported beside a MEASURED resident delta so the two can be compared.
    private static func geometryBytes(_ strokes: [VectorStroke]) -> Int {
        strokes.reduce(0) { $0 + $1.samples.count * MemoryLayout<VectorSample>.stride }
    }

    // MARK: - Measurement plumbing (PerfBaselineTests' verbatim; see there for why phys_footprint)

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

    private final class Box<Value> {
        private let lock = NSLock()
        private var storage: Value
        init(_ value: Value) { storage = value }
        var value: Value {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); storage = newValue; lock.unlock() }
        }
        func mutate(_ transform: (inout Value) -> Void) {
            lock.lock(); transform(&storage); lock.unlock()
        }
    }

    private func measuringPeakMemory(_ body: () -> Void) -> (seconds: Double, peakBytes: UInt64) {
        let peak = Box(residentBytes())
        let stop = Box(false)
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
        peak.mutate { $0 = Swift.max($0, residentBytes()) }
        Thread.sleep(forTimeInterval: 0.01)
        return (elapsed, peak.value)
    }

    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "STROKE BENCH | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "STROKE BENCH — \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func ms(_ seconds: Double) -> String { String(format: "%.2f ms", seconds * 1000) }
    private func mb(_ bytes: UInt64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    private func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    /// Median of `runs` timings of `body`, which is what a figure taken beside three other agents'
    /// work should be quoted at rather than a mean.
    private func medianSeconds(runs: Int, _ body: () -> Void) -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            autoreleasepool {
                let start = CFAbsoluteTimeGetCurrent()
                body()
                samples.append(CFAbsoluteTimeGetCurrent() - start)
            }
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    // MARK: - (1) What actually invalidates the memo

    /// **The hypothesis, stated so it can be refuted**: a vector cel's memo is all-or-nothing and
    /// every edit drops it, so committing one stroke to a layer holding *n* re-walks all *n* and
    /// re-stamps every dab.
    ///
    /// **That was true when this was written and is deliberately no longer true of the append.** It
    /// is what PERFORMANCE.md §11.1's table measured and §11.6 priced; `VectorCanvas.Damage` and
    /// `appendableBase(quality:)` are what was done about it, and this test is now the *upper* half
    /// of that story — every row still re-walks except the two that append, which stamp only their
    /// own dabs. The rows are kept rather than deleted because "which edits still cost the whole
    /// layer" is exactly the question the next person will ask.
    ///
    /// `lastRenderDabCount` is the instrument and it has to be read carefully: `render()` leaves it
    /// standing on a cache hit, so it is *not* a proof of a re-walk on its own. `rasterizations`
    /// counts the calls that actually missed the memo, so the two together say both "did it
    /// re-walk" and "how much did it stamp".
    func testWhatInvalidatesTheVectorCelMemo() {
        let n = 40
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))

        // What one stroke costs on its own, so "n+1 strokes' worth" can be told apart from "one
        // stroke's worth" in the dab count below.
        let solo = VectorCanvas(size: Self.canvasSize, strokes: [Self.benchStroke(n)])
        _ = solo.render()
        let oneStrokeDabs = solo.lastRenderDabCount

        _ = canvas.render()
        let baseDabs = canvas.lastRenderDabCount
        var rasterizations = canvas.rasterizations
        XCTAssertEqual(rasterizations, 1, "the first render must be the only rasterize so far")

        func step(_ name: String, _ mutate: () -> Void) -> (dabs: Int, rewalked: Bool) {
            mutate()
            _ = canvas.render()
            let rewalked = canvas.rasterizations > rasterizations
            rasterizations = canvas.rasterizations
            return (canvas.lastRenderDabCount, rewalked)
        }

        // A second render of an untouched canvas.
        let memoHit = step("memo hit") {}
        XCTAssertFalse(memoHit.rewalked, "an untouched canvas must not rasterize twice")

        // (a) Committing a new stroke at pen-up — the case the whole question is about, and the
        //     one that changed. It still invalidates and still rasterizes; what it no longer does
        //     is stamp the layer again.
        let elementsBefore = canvas.elements
        let append = step("append") { canvas.addStroke(canvasSpaceStroke: Self.benchStroke(n)) }
        XCTAssertTrue(append.rewalked, "a committed stroke must still invalidate and rasterize")
        XCTAssertEqual(append.dabs, oneStrokeDabs,
                       "the append must stamp the new stroke's dabs and nothing else — "
                       + "\(baseDabs + oneStrokeDabs) is what it cost before the fast path")

        // (b) An eraser stroke. A punch appends one `.erase` element, so it takes the same path;
        //     a clean cut would not, and this brush at full pressure could take either — so this
        //     row asserts only that it is no worse than the whole layer.
        let erasePath = StrokeSamples((0..<24).map { i -> VectorSample in
            let t = CGFloat(i) / 23
            return VectorSample(x: 64 + t * (Self.canvasSize.width - 128),
                                y: Self.canvasSize.height * 0.5, pressure: 1)
        }, channels: .pressureOnly)
        let erase = step("erase") {
            _ = canvas.erase(alongPath: erasePath, brush: Self.benchBrush,
                             size: 40, mode: .erase)
        }
        XCTAssertTrue(erase.rewalked, "an eraser stroke must invalidate")
        XCTAssertLessThanOrEqual(erase.dabs, baseDabs + oneStrokeDabs * 2)

        // (c) Undo — the shipped path assigns the snapshot wholesale and calls `bumpVersion()`.
        let undo = step("undo") {
            canvas.elements = elementsBefore
            canvas.bumpVersion()
        }
        XCTAssertTrue(undo.rewalked, "undo must invalidate")
        XCTAssertEqual(Double(undo.dabs), Double(baseDabs), accuracy: 1,
                       "undo re-stamps the restored display list in full")

        // (d) A layer transform — `invalidateRenderOnly`, so the render is dropped even though the
        //     local content did not change.
        let transform = step("transform") { canvas.setTransform(CGAffineTransform(translationX: 12, y: 7)) }
        XCTAssertTrue(transform.rewalked, "a layer transform drops the render memo")
        XCTAssertEqual(Double(transform.dabs), Double(baseDabs), accuracy: 1,
                       "and re-stamps every dab to produce a picture it then merely translates")

        // (e) Evicting the cache (`CanvasManager.evictDistantVectorRenderCaches`) — content
        //     untouched, render gone.
        let evict = step("evict") { canvas.dropCachedImage() }
        XCTAssertTrue(evict.rewalked, "an evicted cel re-walks on the next render")

        // (f) A freshly loaded cel is memo-cold by construction, so a document open pays one full
        //     re-walk per vector cel it displays.
        let loaded = VectorCanvas(size: Self.canvasSize, elements: canvas.elements)
        XCTAssertEqual(loaded.rasterizations, 0)
        XCTAssertNil(loaded.cachedRender().image, "a loaded cel carries no render")
        if case .needsRasterize = loaded.cachedRender() {} else {
            XCTFail("a non-empty loaded cel must report .needsRasterize")
        }

        report("what invalidates", [
            ("strokes", "\(n)"),
            ("dabsWholeLayer", "\(baseDabs)"),
            ("dabsOneStroke", "\(oneStrokeDabs)"),
            ("dabsAfterAppend", "\(append.dabs)"),
            ("dabsAfterErase", "\(erase.dabs)"),
            ("dabsAfterUndo", "\(undo.dabs)"),
            ("dabsAfterTransform", "\(transform.dabs)"),
            ("dabsAfterEvict", "\(evict.dabs)"),
        ])
    }

    /// The two operations that are **not** invalidations, which matters as much as the list above:
    /// a zoom and a render-resolution change must leave the cel's memo standing.
    ///
    /// `renderResolution` writes through to `UserDefaults` and survives into the next run in the
    /// simulator container (CLAUDE.md), so it is pinned and restored here.
    @MainActor
    func testZoomAndRenderResolutionDoNotInvalidateAVectorCel() {
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(20))
        _ = canvas.render()
        let version = canvas.version
        let rasterizations = canvas.rasterizations

        // A zoom is a transform on the canvas *view*, not on the model: `VectorCanvas` has no input
        // a pinch could reach, and `render()` is always canvas-native.
        XCTAssertEqual(canvas.render().size, Self.canvasSize)

        let manager = CanvasManager()
        let previousResolution = manager.renderResolution
        defer { manager.renderResolution = previousResolution }
        manager.canvasSize = Self.canvasSize
        manager.renderResolution = previousResolution == .half ? .full : .half

        XCTAssertEqual(canvas.version, version, "a render-resolution change is not an edit")
        XCTAssertEqual(canvas.rasterizations, rasterizations, "and must not re-stamp a dab")
        XCTAssertNotNil(canvas.cachedRender().image, "the memo must still be standing")
    }

    // MARK: - (2) The curve

    private static let curveCounts = [100, 250, 500, 1000, 2000, 4000, 8000]

    func testFullReWalkAgainstStrokeCount() {
        // Faults in the first canvas-sized bitmap so its cost is not charged to the first row.
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        for n in Self.curveCounts {
            autoreleasepool {
                let strokes = Self.scene(n)
                let geometry = Self.geometryBytes(strokes)
                let held = residentBytes()
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: strokes)
                let measured = measuringPeakMemory { autoreleasepool { _ = canvas.render() } }
                let dabs = canvas.lastRenderDabCount

                // A second render must be a memo hit, whatever n is.
                let rasterizations = canvas.rasterizations
                _ = canvas.render()
                XCTAssertEqual(canvas.rasterizations, rasterizations)

                report("full re-walk", [
                    ("strokes", "\(n)"),
                    ("canvas", "2048x1024"),
                    ("reWalk", ms(measured.seconds)),
                    ("usPerDab", String(format: "%.2f", measured.seconds * 1e6 / Double(max(dabs, 1)))),
                    ("dabs", "\(dabs)"),
                    ("peak", mb(measured.peakBytes)),
                    ("footprintHoldingGeometry", mb(held)),
                    ("geometryBytes", mb(geometry)),
                ])
                XCTAssertGreaterThan(dabs, 0)
            }
        }
    }

    // MARK: - (3) Pen-up to pixels, split by thread

    /// What the design requirement is actually written in.
    ///
    /// The shipped pen-up sequence (`StrokeCanvasView.endVectorStroke` → `refreshDisplay` →
    /// `startVectorRender`) is:
    ///
    /// * **main thread** — `addStroke(canvasSpaceStroke:)` (which maps the samples into layer space
    ///   and inserts into the display list, copying the array because the undo snapshot taken at
    ///   touch-down still holds a reference to it), then `registerVectorUndo`, then `refreshDisplay`
    ///   asking `cachedRender()` and dispatching;
    /// * **`renderQueue`** — the full re-walk;
    /// * **main thread again** — one `UIImage` assignment.
    ///
    /// So the artist's *freeze* is the first bullet and their *stale base* is the second. Both are
    /// timed here, at each n, from the same fixture.
    func testPenUpToPixelsSplitBetweenMainThreadAndBackground() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        for n in Self.curveCounts {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()          // the state the artist is in before the new stroke

                // The undo snapshot the shipped path takes at touch-down. Holding it is what makes
                // the insert below copy rather than mutate in place, and that is a real cost of the
                // shipped design, not an artefact of the harness.
                let before = canvas.elements

                let commitStart = CFAbsoluteTimeGetCurrent()
                canvas.addStroke(canvasSpaceStroke: Self.benchStroke(n + 1))
                let cached = canvas.cachedRender()
                let commit = CFAbsoluteTimeGetCurrent() - commitStart
                if case .needsRasterize = cached {} else {
                    XCTFail("pen-up must leave the cel needing a rasterize at n=\(n)")
                }

                // What the undo entry is charged, in `registerVectorUndo`'s own arithmetic.
                let undoCost = (before.count + canvas.elements.count) * 512

                let backgroundStart = CFAbsoluteTimeGetCurrent()
                _ = canvas.render()
                let background = CFAbsoluteTimeGetCurrent() - backgroundStart

                report("pen-up to pixels", [
                    ("strokes", "\(n)"),
                    ("mainThreadCommit", String(format: "%.3f ms", commit * 1000)),
                    ("backgroundReWalk", ms(background)),
                    ("total", ms(commit + background)),
                    ("undoEntryCost", mb(undoCost)),
                ])
            }
        }
    }

    // MARK: - (5) Where it breaks, and what undo costs at density

    /// The owner asked for the **upper bound**, so this pushes past the curve above until the app is
    /// killed or the shape plainly departs from linear. A row that never prints is the answer: the
    /// harness is jetsammed and the run reports the test as a failure with no output after the last
    /// row it managed.
    func testHowFarItGoesBeforeSomethingBreaks() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }
        for n in [8000, 16000, 32000, 64000] {
            autoreleasepool {
                let strokes = Self.scene(n)
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: strokes)
                let measured = measuringPeakMemory { autoreleasepool { _ = canvas.render() } }
                report("upper bound", [
                    ("strokes", "\(n)"),
                    ("reWalk", ms(measured.seconds)),
                    ("usPerDab", String(format: "%.2f", measured.seconds * 1e6 / Double(max(canvas.lastRenderDabCount, 1)))),
                    ("dabs", "\(canvas.lastRenderDabCount)"),
                    ("peak", mb(measured.peakBytes)),
                    ("geometryBytes", mb(Self.geometryBytes(strokes))),
                ])
            }
        }
    }

    /// **The other half of the owner's "memory overflow" worry, and it is not the render.**
    ///
    /// `StrokeCanvasView.registerVectorUndo` retains the whole display list twice per stroke — the
    /// array as it was at touch-down and as it is at lift — and charges the history
    /// `(from.count + to.count) * 512` bytes. So both the retained bytes and the *charged* cost grow
    /// linearly with the strokes already on the layer, and the number of undo steps that fit inside
    /// `UndoBudget.maxCostBytes` therefore falls as 1/n.
    ///
    /// Retained bytes and charged cost are different quantities and both are reported: consecutive
    /// snapshots share every stroke's `samples` array by copy-on-write, so what an entry really holds
    /// is the element array, not the geometry.
    func testWhatUndoRetainsAndChargesAtDensity() {
        // The iPad 9's rule, asked on whatever machine this runs on — the seam `UndoBudget` exposes
        // for exactly this.
        let iPad9Budget = UndoBudget.maxCostBytes(physicalMemory: 3 * 1024 * 1024 * 1024)
        let depth = 30
        for n in [190, 500, 1000, 2000, 4000] {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                var snapshots: [[VectorElement]] = []
                snapshots.reserveCapacity(depth * 2)
                let settled = residentBytes()
                for k in 0..<depth {
                    let before = canvas.elements
                    canvas.addStroke(Self.benchStroke(n + k))
                    snapshots.append(before)
                    snapshots.append(canvas.elements)
                }
                let held = residentBytes()
                let retained = held > settled ? held - settled : 0
                let chargedPerStroke = (n + n + 1) * 512
                report("undo at density", [
                    ("strokes", "\(n)"),
                    ("undoStepsHeld", "\(depth)"),
                    ("retainedTotal", mb(retained)),
                    ("retainedPerStep", mb(Int(retained) / depth)),
                    ("chargedPerStep", mb(chargedPerStroke)),
                    ("stepsInsideIPad9Budget", "\(iPad9Budget / max(chargedPerStroke, 1))"),
                ])
                XCTAssertEqual(snapshots.count, depth * 2)
            }
        }
    }

    /// The 64,000-stroke case on its own, with the footprint printed at each stage.
    ///
    /// **Run as part of `testHowFarItGoesBeforeSomethingBreaks` it is killed with SIGKILL**, and that
    /// method reaches it having already spent ~42 s inside one synchronous block for the 32,000 row.
    /// SIGKILL on iOS is jetsam *or* a watchdog, and those are completely different answers to the
    /// owner's question — one is a memory ceiling on their document, the other is an artefact of a
    /// test method that never yields. Splitting it out is what tells them apart: if this passes
    /// alone, the kill was about the *method's* elapsed time and not about 64,000 strokes.
    func testSixtyFourThousandStrokesOnItsOwn() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }
        let n = 64000
        let start = residentBytes()
        let strokes = Self.scene(n)
        let afterGeometry = residentBytes()
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: strokes)
        let afterCanvas = residentBytes()
        report("64k stages", [
            ("start", mb(start)), ("afterGeometry", mb(afterGeometry)), ("afterCanvas", mb(afterCanvas)),
        ])
        let measured = measuringPeakMemory { autoreleasepool { _ = canvas.render() } }
        report("upper bound", [
            ("strokes", "\(n)"),
            ("reWalk", ms(measured.seconds)),
            ("usPerDab", String(format: "%.2f", measured.seconds * 1e6 / Double(max(canvas.lastRenderDabCount, 1)))),
            ("dabs", "\(canvas.lastRenderDabCount)"),
            ("peak", mb(measured.peakBytes)),
            ("geometryBytes", mb(Self.geometryBytes(strokes))),
        ])
    }

    /// A stroke of arbitrary path length, so memory and dab count can be varied independently —
    /// which is the only way to say what the 64,000-stroke SIGKILL was actually about.
    private static func benchStroke(_ index: Int, lengthPoints: CGFloat) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset: CGFloat = 48
        let canvas = canvasSize
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        var ux = cos(angle), uy = sin(angle)
        if x0 + ux * lengthPoints < inset || x0 + ux * lengthPoints > canvas.width - inset { ux = -ux }
        if y0 + uy * lengthPoints < inset || y0 + uy * lengthPoints > canvas.height - inset { uy = -uy }
        var samples = StrokeSamples(channels: .pressureOnly)
        samples.reserveCapacity(samplesPerStroke)
        for step in 0..<samplesPerStroke {
            let t = CGFloat(step) / CGFloat(samplesPerStroke - 1)
            let bend = sin(t * .pi) * lengthPoints * 0.16
            samples.append(VectorSample(x: x0 + ux * t * lengthPoints - uy * bend,
                                        y: y0 + uy * t * lengthPoints + ux * bend,
                                        pressure: 0.25 + 0.75 * sin(t * .pi)))
        }
        return VectorStroke(brush: benchBrush,
                            color: CodableColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            size: brushSize, opacity: 1, samples: samples)
    }

    /// **Arm A of the SIGKILL discriminator: the memory of 64,000 strokes, almost none of the dabs.**
    /// Same element count, same geometry footprint, ~8 pt paths. If this survives, the kill is not
    /// about how much a 64,000-element display list weighs.
    func testSixtyFourThousandStrokesWithAlmostNoDabs() {
        let n = 64000
        let strokes = (0..<n).map { Self.benchStroke($0, lengthPoints: 8) }
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: strokes)
        let before = residentBytes()
        let start = CFAbsoluteTimeGetCurrent()
        _ = autoreleasepool { canvas.render() }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        report("kill discriminator A (memory, no dabs)", [
            ("strokes", "\(n)"), ("dabs", "\(canvas.lastRenderDabCount)"),
            ("reWalk", ms(elapsed)), ("footprintBeforeRender", mb(before)),
            ("footprintAfterRender", mb(residentBytes())),
        ])
    }

    /// **Arm B — INVALID, kept as the refutation.** 3,200 strokes at 20x the path length was meant
    /// to be the same dab count on a display list a twentieth the size. It is not: a straight 8,000 pt
    /// path on a 2,048 pt canvas puts most of its dabs *off-canvas*, where CoreGraphics rejects them
    /// almost for free. It reported 15.1 M dabs at 0.59 us against the curve's 3.15 and read as a
    /// large per-stroke fixed cost; the ratio was the clipping. `testTheSameDabCountOnATenthAsManyStrokes`
    /// is the corrected experiment and it lands on 3.07 us. **Do not quote this number.**
    func testTheDabsOfSixtyFourThousandStrokesOnASmallDisplayList() {
        let n = 3200
        let strokes = (0..<n).map { Self.benchStroke($0, lengthPoints: Self.strokeLengthPoints * 20) }
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: strokes)
        let before = residentBytes()
        let start = CFAbsoluteTimeGetCurrent()
        _ = autoreleasepool { canvas.render() }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        report("kill discriminator B — INVALID, dabs mostly clipped off-canvas", [
            ("strokes", "\(n)"), ("dabs", "\(canvas.lastRenderDabCount)"),
            ("reWalk", ms(elapsed)), ("footprintBeforeRender", mb(before)),
            ("footprintAfterRender", mb(residentBytes())),
        ])
    }

    /// A stroke that zig-zags **inside** the canvas, so its whole path length is drawn.
    ///
    /// The first attempt at arm B used a single straight 8,000 pt path on a 2,048 pt canvas, which
    /// put most of its dabs off-canvas where CoreGraphics rejects them almost for free — it reported
    /// 15.1 M dabs at 0.59 us each against the curve's 3.15, and that ratio was the clipping, not a
    /// finding. `PerfBaselineTests.syntheticStroke`'s `passes` knob exists for exactly this reason;
    /// this is the same idea.
    private static func zigZagStroke(_ index: Int, legs: Int, legLength: CGFloat,
                                     samples sampleCount: Int) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 7)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset: CGFloat = 48
        let canvas = canvasSize
        let x0 = inset + next() * (canvas.width - 2 * inset - legLength)
        let y0 = inset + next() * (canvas.height - 2 * inset - CGFloat(legs) * 8)
        // Corner points of the zig-zag, then resampled uniformly so every sample sits on the path.
        var corners: [CGPoint] = []
        for leg in 0..<legs {
            let x = (leg % 2 == 0) ? x0 : x0 + legLength
            corners.append(CGPoint(x: x, y: y0 + CGFloat(leg) * 8))
            corners.append(CGPoint(x: (leg % 2 == 0) ? x0 + legLength : x0, y: y0 + CGFloat(leg) * 8))
        }
        var samples = StrokeSamples(channels: .pressureOnly)
        samples.reserveCapacity(sampleCount)
        for step in 0..<sampleCount {
            let t = CGFloat(step) / CGFloat(sampleCount - 1)
            let position = t * CGFloat(corners.count - 1)
            let i = min(Int(position), corners.count - 2)
            let f = position - CGFloat(i)
            let p = CGPoint(x: corners[i].x + (corners[i + 1].x - corners[i].x) * f,
                            y: corners[i].y + (corners[i + 1].y - corners[i].y) * f)
            samples.append(VectorSample(x: p.x, y: p.y, pressure: 0.25 + 0.75 * sin(t * .pi)))
        }
        return VectorStroke(brush: benchBrush,
                            color: CodableColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            size: brushSize, opacity: 1, samples: samples)
    }

    /// **Arm B, corrected: the 32,000-stroke row's dab count on a display list a tenth its size.**
    /// If the walk is paced by dabs, this lands near that row's 24 s. If it is paced by strokes, it
    /// lands near a tenth of it.
    func testTheSameDabCountOnATenthAsManyStrokes() {
        let n = 3200
        // ~2,360 dabs a stroke at 1.8 pt spacing: 10 legs of ~425 pt, resampled at 120 samples.
        let strokes = (0..<n).map { Self.zigZagStroke($0, legs: 10, legLength: 425, samples: 120) }
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: strokes)
        let before = residentBytes()
        let start = CFAbsoluteTimeGetCurrent()
        _ = autoreleasepool { canvas.render() }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        report("kill discriminator B2 (same dabs, tenth the strokes)", [
            ("strokes", "\(n)"), ("dabs", "\(canvas.lastRenderDabCount)"),
            ("reWalk", ms(elapsed)),
            ("usPerDab", String(format: "%.2f", elapsed * 1e6 / Double(max(canvas.lastRenderDabCount, 1)))),
            ("footprintBeforeRender", mb(before)), ("footprintAfterRender", mb(residentBytes())),
        ])
    }

    /// Brackets the SIGKILL: 32,000 completes in ~24 s, 64,000 is killed. This is the midpoint.
    func testFortyEightThousandStrokes() {
        let n = 48000
        let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
        let before = residentBytes()
        let start = CFAbsoluteTimeGetCurrent()
        _ = autoreleasepool { canvas.render() }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        report("upper bound", [
            ("strokes", "\(n)"), ("dabs", "\(canvas.lastRenderDabCount)"),
            ("reWalk", ms(elapsed)),
            ("usPerDab", String(format: "%.2f", elapsed * 1e6 / Double(max(canvas.lastRenderDabCount, 1)))),
            ("footprintBeforeRender", mb(before)), ("footprintAfterRender", mb(residentBytes())),
        ])
    }

    // MARK: - (4) What the incremental append actually bought, on the shipped path

    /// **The re-measurement of PERFORMANCE.md §11.6, against the render the app now has.**
    ///
    /// §11.6 was a spike: it stamped the new element through `renderIsolated(ids:)` into a separate
    /// bitmap and composited that over a copy of the cached image, which is *not* what shipped.
    /// `renderLocalContent(elements:quality:over:)` draws the new element's dabs **straight into a
    /// copy of the standing picture**, through the same walk the whole layer uses — so this arm is
    /// the app's own code path rather than a model of it, and the two arms are byte-identical
    /// instead of the spike's 0.0001-of-255 mean difference.
    ///
    /// (a) is what a pen-up used to cost and what an *undo* still costs: `bumpVersion()` declares
    /// `.everything`, so the memo and the appendable base both go and the layer is walked whole.
    /// (b) is the shipped pen-up: `addStroke` declares `.appended(count: 1)` and `render()` spends
    /// it. Three appends rather than one, so the figure is a median and not a first-touch.
    func testWhatTheIncrementalAppendBought() {
        for n in [500, 2000, 4000] {
            autoreleasepool {
                let strokes = Self.scene(n)

                // (a) The full re-walk of n+1 — the shipped cost of every edit that is not an append.
                let full = VectorCanvas(size: Self.canvasSize, strokes: strokes)
                full.addStroke(Self.benchStroke(n + 1))
                _ = full.render()
                let fullSeconds = medianSeconds(runs: 3) {
                    full.bumpVersion()
                    _ = full.render()
                }
                let fullDabs = full.lastRenderDabCount

                // (b) The shipped pen-up, three times over, on a layer that keeps growing.
                let incremental = VectorCanvas(size: Self.canvasSize, strokes: strokes)
                _ = incremental.render()
                var samples: [Double] = []
                var incrementalDabs = 0
                for k in 0..<3 {
                    incremental.addStroke(Self.benchStroke(n + 1 + k))
                    let start = CFAbsoluteTimeGetCurrent()
                    _ = incremental.render()
                    samples.append(CFAbsoluteTimeGetCurrent() - start)
                    incrementalDabs = incremental.lastRenderDabCount
                }
                samples.sort()
                let incrementalSeconds = samples[samples.count / 2]

                // Byte for byte against a canvas that cannot have taken the fast path, because it
                // has never rendered anything. A speed-up whose pixels differ is not a speed-up.
                let cold = VectorCanvas(size: Self.canvasSize, elements: incremental.elements)
                let identical = Self.identicalBytes(incremental.render(), cold.render())

                report("incremental append — shipped", [
                    ("strokes", "\(n)"),
                    ("fullReWalk", ms(fullSeconds)),
                    ("incremental", ms(incrementalSeconds)),
                    ("speedup", String(format: "%.1fx", fullSeconds / max(incrementalSeconds, 1e-9))),
                    ("dabsFull", "\(fullDabs)"),
                    ("dabsIncremental", "\(incrementalDabs)"),
                    ("byteIdentical", identical ? "yes" : "NO"),
                ])

                XCTAssertTrue(identical,
                              "the incremental render must be the same bytes as the full walk")
                XCTAssertLessThan(incrementalDabs, fullDabs / 4,
                                  "the append must not be stamping the layer")
            }
        }
    }

    /// **(4b) Where the append's milliseconds actually go — stamping ink, or moving 8 MB about.**
    ///
    /// PERFORMANCE.md §11.8 could state the append's *dab* half on the owner's iPad without going
    /// there — 236 dabs at §11.2's MEASURED 3.16 µs is 0.75 ms — and explicitly refused to infer the
    /// other half, because the other half is canvas-sized buffer work and §10.2 already caught that
    /// class of ratio **inverted** between this Mac and the device. This is the term only the
    /// hardware can settle, and it is taken on the shipped path rather than on a model of it.
    ///
    /// **The instrument is a slope, not a stopwatch around a private method.** An append costs
    /// `fixed + dabs × perDab`: one `UIGraphicsImageRenderer` context of the canvas's size, the
    /// standing picture drawn 1:1 into it, the walk, and the `CGImage` the renderer makes at the
    /// end — and only the walk depends on how much was appended. So appending *k* strokes before a
    /// single render multiplies the ink by *k* and leaves every other term exactly where it was, and
    /// a least-squares line through five such points reads the two off directly: **the intercept is
    /// the buffer work and the slope is the ink.**
    ///
    /// `lastRenderDabCount` is checked on every point, and that check is what makes the fit
    /// meaningful rather than decorative: a point that fell back to the full walk would report the
    /// whole layer's dabs and the line would be fitted to a different function.
    ///
    /// **The fit is taken at three layer sizes, and that is the second question rather than a
    /// repetition of the first.** The intercept is "everything that does not scale with the ink",
    /// which is not the same as "the two blits": `appendPreservesTheWalk`'s scan is O(the merged
    /// paint run), so on an all-strokes cel it is O(n) and it lands in the intercept too. If the
    /// intercept is the buffers it is the same at 500 strokes and at 4,000; if it carries the scan
    /// it grows with n. That is the only n-dependence left in the append and this is what says
    /// whether "flat in n" is exactly true or merely true to within the noise.
    ///
    /// **And the intercept is read a second time, independently, as a replica** — a bare renderer of
    /// the canvas's size with a standing picture drawn into it and no ink at all, and then the same
    /// with nothing drawn into it either, so the 8 MB blit can be told from the context it lands in.
    /// That is a model of the shipped path's buffer work rather than the path itself and is reported
    /// as such.
    ///
    /// **The replica is taken twice over, and the pair is the point.** One arm throws each image away
    /// before making the next, so the allocator hands back the same warm 8 MB slab every time; the
    /// other retains all of them, so every iteration faults in pages it has never touched — which is
    /// what the shipped append does, since the base it is drawing *from* is the previous render's
    /// output and is still live while the new context is allocated. A replica that reuses one buffer
    /// measures a memcpy; the append pays for the memory as well.
    func testWhereTheAppendsMillisecondsGo() {
        for n in [500, 2000, 4000] {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()                       // stands the incremental base up
                var nextIndex = n + 1
                canvas.addStroke(Self.benchStroke(nextIndex)); nextIndex += 1
                _ = canvas.render()                       // and one warm append, not timed

                var points: [(dabs: Double, seconds: Double)] = []
                for k in [1, 2, 4, 8, 16] {
                    var samples: [Double] = []
                    var dabs = 0
                    for _ in 0..<3 {
                        for _ in 0..<k {
                            canvas.addStroke(Self.benchStroke(nextIndex)); nextIndex += 1
                        }
                        let start = CFAbsoluteTimeGetCurrent()
                        _ = canvas.render()
                        samples.append(CFAbsoluteTimeGetCurrent() - start)
                        dabs = canvas.lastRenderDabCount
                    }
                    samples.sort()
                    let median = samples[samples.count / 2]
                    points.append((Double(dabs), median))
                    report("append cost by ink", [
                        ("strokesOnLayer", "\(n)"),
                        ("strokesAppended", "\(k)"),
                        ("dabs", "\(dabs)"),
                        ("render", ms(median)),
                    ])
                    XCTAssertLessThan(dabs, 16 * 400,
                                      "the k=\(k) point at n=\(n) fell back to the full walk (\(dabs) dabs); the fit would be of the wrong function")
                }

                let count = Double(points.count)
                let sumX = points.reduce(0) { $0 + $1.dabs }
                let sumY = points.reduce(0) { $0 + $1.seconds }
                let sumXX = points.reduce(0) { $0 + $1.dabs * $1.dabs }
                let sumXY = points.reduce(0) { $0 + $1.dabs * $1.seconds }
                let slope = (count * sumXY - sumX * sumY) / (count * sumXX - sumX * sumX)
                let intercept = (sumY - slope * sumX) / count
                let meanY = sumY / count
                let ssTot = points.reduce(0) { $0 + ($1.seconds - meanY) * ($1.seconds - meanY) }
                let ssRes = points.reduce(0) { $0 + ($1.seconds - (intercept + slope * $1.dabs)) * ($1.seconds - (intercept + slope * $1.dabs)) }
                let r2 = ssTot > 0 ? 1 - ssRes / ssTot : 0

                let oneStrokeDabs = points[0].dabs
                let oneStrokeInk = slope * oneStrokeDabs
                report("append cost split", [
                    ("strokesOnLayer", "\(n)"),
                    ("fixedBufferCost", ms(intercept)),
                    ("usPerDab", String(format: "%.2f", slope * 1e6)),
                    ("r2", String(format: "%.4f", r2)),
                    ("oneStrokeDabs", String(format: "%.0f", oneStrokeDabs)),
                    ("oneStrokeInk", ms(oneStrokeInk)),
                    ("oneStrokeTotal", ms(intercept + oneStrokeInk)),
                    ("bufferShare", String(format: "%.0f%%", 100 * intercept / max(intercept + oneStrokeInk, 1e-9))),
                ])

                XCTAssertGreaterThan(r2, 0.9,
                                     "the append's cost at n=\(n) is not linear in dabs (R²=\(r2)); the split read off it is not readable")
                XCTAssertGreaterThan(intercept, 0,
                                     "a negative fixed cost at n=\(n) means the fit is noise, not a split")
            }
        }

        // The replicas — the same canvas-sized buffer work with no ink in it at all, once against a
        // buffer the allocator can hand back warm and once against memory never touched before.
        autoreleasepool {
            let standing = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(200)).render()
            let format = PixelOps.transparentFormat()
            format.preferredRange = .standard
            func renderer(_ body: @escaping (UIGraphicsImageRendererContext) -> Void) -> UIImage {
                UIGraphicsImageRenderer(size: Self.canvasSize, format: format).image(actions: body)
            }
            let warmBlit = medianSeconds(runs: 7) { _ = renderer { _ in standing.draw(at: .zero) } }
            let warmEmpty = medianSeconds(runs: 7) { _ = renderer { _ in } }
            var kept: [UIImage] = []
            kept.reserveCapacity(16)
            let coldBlit = medianSeconds(runs: 7) { kept.append(renderer { _ in standing.draw(at: .zero) }) }
            var keptEmpty: [UIImage] = []
            keptEmpty.reserveCapacity(16)
            let coldEmpty = medianSeconds(runs: 7) { keptEmpty.append(renderer { _ in }) }
            report("append cost split — replica", [
                ("warmBufferReused", ms(warmBlit)),
                ("warmContextAlone", ms(warmEmpty)),
                ("freshBufferEachTime", ms(coldBlit)),
                ("freshContextAlone", ms(coldEmpty)),
                ("blitAloneWarm", ms(warmBlit - warmEmpty)),
                ("blitAloneFresh", ms(coldBlit - coldEmpty)),
                ("canvasBytes", mb(Int(Self.canvasSize.width * Self.canvasSize.height) * 4)),
            ])
            XCTAssertEqual(kept.count, 7)
            XCTAssertEqual(keptEmpty.count, 7)
        }
    }

    // MARK: - (5) Where the owner's cross-eraser lag spike actually is

    /// The eraser the owner reports the spike with. Mode 3's footprint is a *selection* radius fixed
    /// at the brush size (`VectorCanvas.cutToIntersection(atCanvasPoint:)` takes no pressure), so
    /// this is the whole of the nib.
    private static let eraserSize: CGFloat = 40
    private static let eraserBrush = Brush(name: "BenchEraser", tip: .round, size: eraserSize)

    /// A drag across the middle of the canvas, where `scene(n)`'s strokes are densest — the gesture
    /// the report describes. Sampled at the rate a finger delivers, not at the rate a test would
    /// like: **the cost this measures is per touch sample**, so a coarse path would understate it by
    /// exactly the factor it was coarsened by.
    private static func dragPath(samples: Int) -> [CGPoint] {
        (0..<samples).map { step in
            let t = CGFloat(step) / CGFloat(max(samples - 1, 1))
            return CGPoint(x: 200 + t * (canvasSize.width - 400),
                           y: canvasSize.height * 0.5 + sin(t * .pi * 2) * canvasSize.height * 0.18)
        }
    }

    /// **The owner, on a build carrying everything from this session**: *"right now when I draw a
    /// bunch of brushstrokes and then use the cross eraser on them, I get a lagspike."*
    ///
    /// *"Cross eraser"* is `VectorEraserMode.cutToIntersection`, whose segmented-control label is
    /// **"To Cross"** — Mode 3, not the Mode 2 cut that TODO (41) names. That distinction is the
    /// whole point of this test, because the two have completely different cost models:
    ///
    /// * Mode 2 commits **once, at lift**, through `erase(alongPath:…)`. One middle-of-list edit and
    ///   one re-walk for the whole gesture.
    /// * Mode 3 commits **once per touch sample**, through `cutToIntersection(atCanvasPoint:…)`, and
    ///   each commit that cuts calls `invalidate(.everything)`. So a 40-sample drag is up to 40
    ///   re-walks — and, before any of them, 40 runs of a search that `VectorLayer.swift:3470` marks
    ///   *"INFERRED, not measured … if a drag ever stutters in a dense drawing, this loop is where to
    ///   look first."*
    ///
    /// This splits the drag into those two halves so the profile decides which is the spike rather
    /// than the brief. `resolve` is what runs **on the main thread** during the drag; `render` is
    /// what `StrokeCanvasView.renderQueue` runs behind it, and is the term TODO (41) is aimed at.
    func testWhereACrossEraserDragSpendsItsTime() {
        // Warm every allocator and gradient cache the first row would otherwise pay for.
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }

        // **Four counts, because one number is a point and the ask is about a shape.** 2,000 is the
        // top of the owner's *"couple thousand"* and is where §11.2's straight line puts a full
        // re-walk at 1.13 s on this simulator — so the before/after pair at that row is the one the
        // report is really about.
        for n in [200, 500, 1000, 2000] {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                // A layer on screen has already rendered, so the drag starts from a warm memo.
                _ = canvas.render()

                var driver = VectorEraser.IntersectionDriver()
                var resolveSeconds = 0.0, renderSeconds = 0.0
                var worstResolve = 0.0, worstRender = 0.0
                var cuts = 0, walks = 0, dabs = 0
                var regionArea = 0.0
                let path = Self.dragPath(samples: 40)
                for point in path {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let resolved = canvas.cutToIntersection(atCanvasPoint: point,
                                                            brush: Self.eraserBrush,
                                                            size: Self.eraserSize,
                                                            suppressing: driver.suppressed)
                    let dtResolve = CFAbsoluteTimeGetCurrent() - t0
                    resolveSeconds += dtResolve
                    worstResolve = Swift.max(worstResolve, dtResolve)
                    driver.accept(resolved.outcome, underTip: resolved.underTip)
                    if resolved.outcome == .cut { cuts += 1 }

                    let before = canvas.rasterizations
                    let t1 = CFAbsoluteTimeGetCurrent()
                    _ = canvas.render()
                    let dtRender = CFAbsoluteTimeGetCurrent() - t1
                    renderSeconds += dtRender
                    worstRender = Swift.max(worstRender, dtRender)
                    if canvas.rasterizations > before {
                        walks += 1
                        dabs += canvas.lastRenderDabCount
                        let region = canvas.lastRepairedRegion
                        if !region.isNull {
                            regionArea += Double(region.width * region.height)
                                / Double(Self.canvasSize.width * Self.canvasSize.height)
                        }
                    }
                }

                report("cross eraser (Mode 3) drag — n=\(n)", [
                    ("touchSamples", "\(path.count)"),
                    ("cuts", "\(cuts)"),
                    ("reWalks", "\(walks)"),
                    ("resolveTotal", ms(resolveSeconds)),
                    ("renderTotal", ms(renderSeconds)),
                    ("dragTotal", ms(resolveSeconds + renderSeconds)),
                    ("worstSingleResolve", ms(worstResolve)),
                    ("worstSingleRender", ms(worstRender)),
                    ("resolveShare", String(format: "%.0f%%",
                                            100 * resolveSeconds / (resolveSeconds + renderSeconds))),
                    ("dabsStamped", "\(dabs)"),
                    ("regionRepairs", "\(canvas.regionRepairs)"),
                    ("repairsWidened", "\(canvas.regionRepairsWidened)"),
                    ("repairsAbandoned", "\(canvas.regionRepairsAbandoned)"),
                    ("meanRegionOfCanvas", String(format: "%.1f%%",
                                                  100 * regionArea / Double(Swift.max(walks, 1)))),
                ])
            }

            // Mode 2, the cut TODO (41) names, for the comparison that says whether the report is
            // about the re-walk at all: one commit, one re-walk, for the whole gesture.
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                var samples = StrokeSamples(channels: .pressureOnly)
                for point in Self.dragPath(samples: 40) {
                    samples.append(VectorSample(x: point.x, y: point.y, pressure: 1))
                }
                let t0 = CFAbsoluteTimeGetCurrent()
                let changed = canvas.erase(alongPath: samples, brush: Self.eraserBrush,
                                           size: Self.eraserSize, mode: .cutPoints)
                let cutSeconds = CFAbsoluteTimeGetCurrent() - t0
                let t1 = CFAbsoluteTimeGetCurrent()
                _ = canvas.render()
                let renderSeconds = CFAbsoluteTimeGetCurrent() - t1
                report("cut (Mode 2) whole gesture — n=\(n)", [
                    ("changed", "\(changed)"),
                    ("regionRepairs", "\(canvas.regionRepairs)"),
                    ("dabsStamped", "\(canvas.lastRenderDabCount)"),
                    ("cutOnce", ms(cutSeconds)),
                    ("reWalkOnce", ms(renderSeconds)),
                    ("gestureTotal", ms(cutSeconds + renderSeconds)),
                ])
            }

            // **Mode 2 again, as a flick rather than a sweep**, because the row above is the honest
            // worst case and not the common one: a cut across the whole canvas unions forty strokes'
            // footprints into a rectangle the size of the canvas, which `repairClip` correctly
            // refuses. A real cut is a short stroke through one or two lines.
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                var samples = StrokeSamples(channels: .pressureOnly)
                let mid = CGPoint(x: Self.canvasSize.width * 0.5, y: Self.canvasSize.height * 0.5)
                for step in 0...6 {
                    let t = CGFloat(step) / 6
                    samples.append(VectorSample(x: mid.x - 30 + t * 60, y: mid.y - 30 + t * 60,
                                                pressure: 1))
                }
                let t0 = CFAbsoluteTimeGetCurrent()
                let changed = canvas.erase(alongPath: samples, brush: Self.eraserBrush,
                                           size: Self.eraserSize, mode: .cutPoints)
                let cutSeconds = CFAbsoluteTimeGetCurrent() - t0
                let t1 = CFAbsoluteTimeGetCurrent()
                _ = canvas.render()
                let renderSeconds = CFAbsoluteTimeGetCurrent() - t1
                let region = canvas.lastRepairedRegion
                report("cut (Mode 2) short flick — n=\(n)", [
                    ("changed", "\(changed)"),
                    ("regionRepairs", "\(canvas.regionRepairs)"),
                    ("repairsAbandoned", "\(canvas.regionRepairsAbandoned)"),
                    ("dabsStamped", "\(canvas.lastRenderDabCount)"),
                    ("regionOfCanvas", region.isNull ? "full walk"
                        : String(format: "%.1f%%", 100 * Double(region.width * region.height)
                                 / Double(Self.canvasSize.width * Self.canvasSize.height))),
                    ("cutOnce", ms(cutSeconds)),
                    ("renderOnce", ms(renderSeconds)),
                ])
            }

            // What the *resolve* half of a Mode 3 sample is made of, so the 2–8% above is attributed
            // rather than left as one number. `strokeIndex()` is keyed on `version`, and every cut
            // moves it, so the sample after a cut rebuilds a grid over every segment on the layer.
            // A resolve aimed at bare canvas pays exactly that rebuild and then the candidate query,
            // and returns `.missed` before the O(segments × segments) intersection work — so the
            // difference between it and the cutting resolve above is the search.
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                _ = canvas.render()
                // A corner the `inset: 48` scene builder keeps clear of, so nothing is under the tip.
                let bare = CGPoint(x: 8, y: 8)
                let cold = medianSeconds(runs: 5) {
                    canvas.bumpVersion()
                    _ = canvas.cutToIntersection(atCanvasPoint: bare, brush: Self.eraserBrush,
                                                 size: Self.eraserSize)
                }
                let warm = medianSeconds(runs: 5) {
                    _ = canvas.cutToIntersection(atCanvasPoint: bare, brush: Self.eraserBrush,
                                                 size: Self.eraserSize)
                }
                report("Mode 3 resolve split — n=\(n)", [
                    ("indexRebuildPlusMiss", ms(cold)),
                    ("missAlone", ms(warm)),
                    ("indexRebuildAlone", ms(cold - warm)),
                ])
            }
        }
    }

    /// Byte equality of two renders' own backing bitmaps. Not a tolerance: since the append draws
    /// the new dabs into a copy of the standing picture rather than into a separate layer, there is
    /// nowhere for a rounding difference to enter, and anything but equality is a defect.
    /// `IncrementalAppendLogicTests` is where that is pinned; this is here so a *measurement* cannot
    /// quietly be of two different pictures.
    private static func identicalBytes(_ a: UIImage, _ b: UIImage) -> Bool {
        guard let ca = a.cgImage, let cb = b.cgImage,
              ca.width == cb.width, ca.height == cb.height,
              ca.bytesPerRow == cb.bytesPerRow, ca.bitmapInfo == cb.bitmapInfo,
              let da = ca.dataProvider?.data, let db = cb.dataProvider?.data else { return false }
        return (da as Data) == (db as Data)
    }

}
