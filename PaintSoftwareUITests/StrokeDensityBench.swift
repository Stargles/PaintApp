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
/// 4. *The size of the incremental-append prize*, if (2) says it matters.
///
/// **This class is a throwaway.** It lives on `tmp/strokebench` and is not meant to be merged: it
/// is minutes of wall clock, and (4) times a render path the app does not have.
///
/// It is deliberately *not* named `…LogicTests`, so CLAUDE.md's fast-tier selector does not pick it
/// up. Run it by name:
/// ```
/// -only-testing:PaintSoftwareUITests/StrokeDensityBench
/// ```
final class StrokeDensityBench: XCTestCase {

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

    private static let benchBrush = Brush(name: "Bench", shape: .softRound, size: brushSize)

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
        var samples: [VectorSample] = []
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

        // (a) Committing a new stroke at pen-up — the case the whole question is about.
        let elementsBefore = canvas.elements
        let append = step("append") { canvas.addStroke(canvasSpaceStroke: Self.benchStroke(n)) }
        XCTAssertTrue(append.rewalked, "a committed stroke must invalidate")
        XCTAssertGreaterThan(append.dabs, baseDabs,
                             "an append that re-walked stamps MORE than the whole layer did before it")
        XCTAssertEqual(Double(append.dabs), Double(baseDabs + oneStrokeDabs), accuracy: Double(oneStrokeDabs),
                       "the append re-stamps every earlier dab as well as the new stroke's")

        // (b) An eraser stroke.
        let erasePath = (0..<24).map { i -> VectorSample in
            let t = CGFloat(i) / 23
            return VectorSample(x: 64 + t * (Self.canvasSize.width - 128),
                                y: Self.canvasSize.height * 0.5, pressure: 1)
        }
        let erase = step("erase") {
            _ = canvas.erase(alongPath: erasePath, brush: Self.benchBrush,
                             size: 40, mode: .erase)
        }
        XCTAssertTrue(erase.rewalked, "an eraser stroke must invalidate")

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
        var samples: [VectorSample] = []
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
        var samples: [VectorSample] = []
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

    // MARK: - (4) The incremental-append spike — THROWAWAY, not a proposed render path

    /// **What making the memo incremental would buy**, measured rather than promised.
    ///
    /// (a) is the shipped full re-walk of *n+1* strokes. (b) stamps only the newly appended element
    /// — through `renderIsolated(ids:)`, the same walk and the same isolation rules — and draws it
    /// over a copy of the standing cached image.
    ///
    /// **The correctness constraint, which is why this is a spike and not a patch.** The display
    /// list is not associative in general: an `.erase` stroke composites `destinationOut` against
    /// everything beneath it, and a run of blend-mode strokes is wrapped in one transparency layer,
    /// so an element appended into or after either of those is *not* equivalent to compositing it
    /// over the finished picture. It is equivalent exactly under source-over, which
    /// `renderLocalContent`'s own rule 2 already states ("source-over is associative, so drawing
    /// straight into the context is identical"). The case timed here is source-over throughout, and
    /// the pixels are compared to prove it.
    func testWhatAnIncrementalAppendWouldBuy() {
        for n in [500, 2000, 4000] {
            autoreleasepool {
                let strokes = Self.scene(n)
                let newStroke = Self.benchStroke(n + 1)

                // (a) The shipped path: a canvas of n, memo warm, one append, one full re-walk.
                let full = VectorCanvas(size: Self.canvasSize, strokes: strokes)
                _ = full.render()
                full.addStroke(newStroke)
                let fullSeconds = medianSeconds(runs: 3) {
                    full.bumpVersion()
                    _ = full.render()
                }
                let fullDabs = full.lastRenderDabCount
                let fullImage = full.render()

                // (b) The incremental arm: the standing base plus this element's own dabs.
                let incremental = VectorCanvas(size: Self.canvasSize, strokes: strokes)
                let base = incremental.render()
                incremental.addStroke(newStroke)
                let id = incremental.elements.last!.id
                var composed: UIImage!
                let incrementalSeconds = medianSeconds(runs: 3) {
                    let onlyNew = incremental.renderIsolated(ids: [id])!
                    let format = PixelOps.transparentFormat()
                    composed = UIGraphicsImageRenderer(size: Self.canvasSize, format: format).image { _ in
                        base.draw(at: .zero)
                        onlyNew.draw(at: .zero)
                    }
                }
                let incrementalDabs = incremental.lastRenderDabCount

                let difference = Self.meanChannelDifference(fullImage, composed)

                report("incremental append", [
                    ("strokes", "\(n)"),
                    ("fullReWalk", ms(fullSeconds)),
                    ("incremental", ms(incrementalSeconds)),
                    ("speedup", String(format: "%.1fx", fullSeconds / max(incrementalSeconds, 1e-9))),
                    ("dabsFull", "\(fullDabs)"),
                    ("dabsIncremental", "\(incrementalDabs)"),
                    ("meanChannelDiff", String(format: "%.4f", difference)),
                ])

                XCTAssertLessThan(difference, 1.0,
                                  "under source-over the two arms must be the same picture — a spike "
                                  + "whose pixels differ is measuring two different things")
            }
        }
    }

    /// Mean absolute per-channel difference, 0-255. Not byte equality: the two arms round in
    /// different places (one composites the new dabs straight into the accumulated context, the
    /// other into a transparent layer first), so demanding exact bytes would be asserting something
    /// other than "same picture".
    private static func meanChannelDifference(_ a: UIImage, _ b: UIImage) -> Double {
        guard let ca = a.cgImage, let cb = b.cgImage,
              ca.width == cb.width, ca.height == cb.height else { return .infinity }
        let width = ca.width, height = ca.height
        let bytesPerRow = width * 4
        var bufferA = [UInt8](repeating: 0, count: bytesPerRow * height)
        var bufferB = [UInt8](repeating: 0, count: bytesPerRow * height)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        bufferA.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow, space: space, bitmapInfo: info)?
                .draw(ca, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        bufferB.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow, space: space, bitmapInfo: info)?
                .draw(cb, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var total = 0.0
        for i in 0..<bufferA.count { total += Double(abs(Int(bufferA[i]) - Int(bufferB[i]))) }
        return total / Double(bufferA.count)
    }
}
