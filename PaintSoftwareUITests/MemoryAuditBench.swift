import XCTest
import UIKit
import Metal

/// **What the app actually holds, counted rather than guessed — RENDER.md §5 stage 7's baseline.**
///
/// [BUGS.md](BUGS.md)'s twelve-site census ranked allocation sites by reading the code, and
/// [PERFORMANCE.md](PERFORMANCE.md) §9 measured eight of them on the owner's iPad. Neither answers
/// the question this stage has to answer before it changes anything: **at the owner's canvas, on a
/// document the size the owner actually draws, which site is holding the bytes?** A ranking taken
/// from `w·h·4` arithmetic over a census is a ranking of *ceilings*; this is a ranking of what a rest
/// and a scrub leave resident.
///
/// **It counts what the app itself allocated wherever it can**, because `phys_footprint` on a
/// simulator includes the runner, UIKit, Metal's own allocations and the harness's fixture, and a
/// number that includes the fixture is a number about the fixture. Every row below that says
/// `counted=` is a sum over the app's own accounting — cache entry bytes, `MTLBuffer.length`, image
/// `bytesPerRow × height`. Rows that say `footprint=` are `task_vm_info.phys_footprint` and are a
/// **proxy**: they include everything above, and they are reported beside the counted figure so the
/// two can be compared rather than confused.
///
/// Deliberately *not* named `…LogicTests`, so CLAUDE.md's fast-tier selector
/// (`LogicTests$|CharacterizationTests$|^PerfBaselineTests$`) does not pick it up — it builds
/// hundred-cel documents at 2048×1024 and is minutes of wall clock. Run it by name:
/// ```
/// PAINTAPP_BENCH=1 xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
///   -destination 'platform=iOS Simulator,id=<udid>' \
///   -only-testing:PaintSoftwareUITests/MemoryAuditBench -parallel-testing-enabled NO
/// ```
/// Read the `MEM AUDIT |` lines, not the banner: no lines means nothing ran.
final class MemoryAuditBench: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "MemoryAuditBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
    }

    override func tearDown() {
        PixelOps.clearRasterizeCache()
        CompositorBudget.budgetOverrideBytes = nil
        super.tearDown()
    }

    // MARK: - The scene

    /// The owner's canvas (PERFORMANCE.md §1).
    private static let canvasSize = CGSize(width: 2048, height: 1024)
    private static var canvasBytes: Int { 2048 * 1024 * 4 }

    /// `StrokeDensityBench`'s stroke, verbatim — same RNG, same constants — so a figure here is
    /// directly comparable with that file's tables instead of being a new, incompatible curve.
    private static let strokeLengthPoints: CGFloat = 400
    private static let samplesPerStroke = 40
    private static let brushSize: CGFloat = 18
    private static let benchBrush = Brush(name: "Bench", tip: .round, size: brushSize)

    private static func benchStroke(_ index: Int, canvas: CGSize = canvasSize) -> VectorStroke {
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
                            size: brushSize, opacity: 1, samples: samples)
    }

    /// A vector document of `frames` one-frame cels on one layer, each holding `strokesPerCel`
    /// strokes — the owner's own shape (`project_real_document_size`: 300–1000 drawn cels, not 30),
    /// scaled down to what a simulator run can build in reasonable time.
    @MainActor
    private func vectorDocument(frames: Int, strokesPerCel: Int) -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.canvasSize
        manager.addVectorLayer()
        // The layer arrives with one cel spanning the whole scene; cut it back to frame 0 so every
        // frame below gets a picture of its own. A document made of holds cannot be scrubbed
        // meaningfully — RENDER.md §5's own "a document made of holds cannot count frames".
        manager.layers[0].cels = []
        for frame in 0..<frames {
            let canvas = VectorCanvas.empty(size: Self.canvasSize)
            for stroke in 0..<strokesPerCel {
                canvas.addStroke(Self.benchStroke(frame &* 1000 &+ stroke))
            }
            manager.layers[0].cels.append(Cel(id: UUID(), startFrame: frame, frameCount: 1,
                                              raster: .empty(size: Self.canvasSize), vector: canvas))
        }
        return manager
    }

    // MARK: - Measurement plumbing (`StrokeDensityBench`'s verbatim; see there for why phys_footprint)

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

    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "MEM AUDIT | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "MEM AUDIT — \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    private func mb(_ bytes: UInt64) -> String { mb(Int(bytes)) }
    private func ms(_ seconds: Double) -> String { String(format: "%.3f ms", seconds * 1000) }

    /// Canvas-sized renders the document's vector cels are memoizing right now, counted off the
    /// canvases themselves rather than off any cache — there is no cache to ask, which is the point
    /// of census item 5.
    @MainActor
    private func vectorRenderBytes(_ manager: CanvasManager) -> (entries: Int, bytes: Int) {
        var entries = 0
        for layer in manager.layers {
            for cel in layer.cels where cel.vector?.hasCachedImage == true { entries += 1 }
        }
        return (entries, entries * Self.canvasBytes)
    }

    // MARK: - 1. What a rest and a scrub leave resident

    /// **The baseline.** A hundred-frame vector document at the owner's canvas: what is held after
    /// the document is built, after the current frame is composited, and after the playhead has
    /// walked every frame once.
    @MainActor
    func testWhatARestAndAScrubHoldAtTheOwnersCanvas() {
        let frames = 100
        PixelOps.clearRasterizeCache()
        let built = residentBytes()
        let manager = vectorDocument(frames: frames, strokesPerCel: 12)
        let afterBuild = residentBytes()

        // Rest: composite the current frame the way the live canvas does.
        _ = manager.makeFrameRecipe(atFrame: 0, includeBackground: true)?.composite()
        let rest = vectorRenderBytes(manager)
        let restFlatten = PixelOps.rasterizeCacheBytes
        let afterRest = residentBytes()

        report("rest — 100 cels, 12 strokes each, 2048x1024", [
            ("vectorRenderEntries", "\(rest.entries)"),
            ("vectorRenderCounted", mb(rest.bytes)),
            ("flattenMemoCounted", mb(restFlatten)),
            ("footprintAfterBuild", mb(afterBuild &- built)),
            ("footprintAfterComposite", mb(afterRest &- built))
        ])

        // A scrub: every frame, in order, exactly as playback drives it. **Each frame in its own
        // autorelease pool**, or the footprint below is a reading of this loop's pool rather than of
        // what the app holds — the exact trap CLAUDE.md records a harness falling into.
        let start = CFAbsoluteTimeGetCurrent()
        for frame in 0..<frames {
            autoreleasepool {
                manager.currentFrame = frame
                _ = manager.makeFrameRecipe(atFrame: frame, includeBackground: true)?.composite()
            }
        }
        let scrubSeconds = CFAbsoluteTimeGetCurrent() - start
        let scrub = vectorRenderBytes(manager)
        let scrubFlatten = PixelOps.rasterizeCacheBytes
        let afterScrub = residentBytes()

        report("after a 100-frame scrub", [
            ("vectorRenderEntries", "\(scrub.entries)"),
            ("vectorRenderCounted", mb(scrub.bytes)),
            ("flattenMemoCounted", mb(scrubFlatten)),
            ("countedTotal", mb(scrub.bytes + scrubFlatten)),
            ("compositorBudget", mb(CompositorBudget.textureBudgetBytes)),
            ("footprint", mb(afterScrub &- built)),
            ("scrubWall", ms(scrubSeconds)),
            ("perFrame", ms(scrubSeconds / Double(frames)))
        ])
    }

    /// **What the per-playback-tick evictor cost, and what replaced it costs** — census item 5's
    /// second half, measured on both sides of the change.
    ///
    /// **Before**: `currentFrame.didSet` ran `handleActiveContextChanged`, which called
    /// `evictDistantVectorRenderCaches` — count every vector cel in the document, then walk them all
    /// again taking each canvas's lock through `hasCachedImage`, build an array and sort it. Twenty
    /// four times a second, for the whole of playback, to discover almost always that nothing needs
    /// evicting. That function is deleted, so the **before** arm below is its algorithm reproduced
    /// here verbatim rather than called — the only way to keep the number comparable once the code it
    /// measures is gone.
    ///
    /// **After**: a tick moves the playhead and nothing else. Eviction happens where a render is
    /// memoized (`VectorRenderCache.noteRendered`), so the arm measures what a document scan costs
    /// against what not doing one costs.
    @MainActor
    func testWhatTheEvictorCostsPerPlaybackTick() {
        for cels in [12, 100, 300] {
            let manager = vectorDocument(frames: cels, strokesPerCel: 2)
            // Warm: one render so some canvases hold a memo and the sort has work.
            for index in 0..<min(20, cels) { _ = manager.layers[0].cels[index].vector?.render() }
            let ticks = 240   // ten seconds of playback at 24 fps

            let beforeStart = CFAbsoluteTimeGetCurrent()
            for _ in 0..<ticks { Self.evictDistantVectorRenderCaches(manager, limit: 12) }
            let before = CFAbsoluteTimeGetCurrent() - beforeStart

            // The shipped path: a tick is a write to `currentFrame`, and eviction is not on it.
            let afterStart = CFAbsoluteTimeGetCurrent()
            for tick in 0..<ticks { manager.currentFrame = tick % max(1, cels) }
            let after = CFAbsoluteTimeGetCurrent() - afterStart

            report("playback tick", [
                ("cels", "\(cels)"),
                ("evictorPerTickBefore", ms(before / Double(ticks))),
                ("wholeTickAfter", ms(after / Double(ticks))),
                ("tenSecondsBefore", ms(before))
            ])
        }
    }

    /// `CanvasManager.evictDistantVectorRenderCaches` as it stood at `61c1b17`, kept here so the
    /// **before** arm above measures the code that was deleted rather than a description of it.
    @MainActor
    private static func evictDistantVectorRenderCaches(_ manager: CanvasManager, limit: Int) {
        let vectorCels = manager.layers.reduce(0) { $0 + $1.cels.lazy.filter { $0.vector != nil }.count }
        guard vectorCels > max(0, limit) else { return }
        var cached: [(distance: Int, canvas: VectorCanvas)] = []
        for layer in manager.layers {
            for cel in layer.cels {
                guard let canvas = cel.vector, canvas.hasCachedImage else { continue }
                let distance: Int
                if manager.currentFrame >= cel.startFrame && manager.currentFrame < cel.endFrame {
                    distance = 0
                } else if manager.currentFrame < cel.startFrame {
                    distance = cel.startFrame - manager.currentFrame
                } else {
                    distance = manager.currentFrame - (cel.endFrame - 1)
                }
                cached.append((distance: distance, canvas: canvas))
            }
        }
        guard cached.count > max(0, limit) else { return }
        for entry in cached.sorted(by: { $0.distance < $1.distance }).dropFirst(max(0, limit)) {
            entry.canvas.dropCachedImage()
        }
    }

    // MARK: - 2. The fill session

    /// **What one fill gesture allocates, summed off `MTLBuffer.length`** — census item 3, which
    /// reads ~34 bytes per canvas pixel out of the source. Counted rather than inferred, because a
    /// `.storageModeShared` buffer is resident the moment it is made (PERFORMANCE.md §9 item 8) and
    /// this is the one site where the census's `w·h·4` column *understates*.
    func testWhatAFillSessionAllocates() throws {
        let engine = try XCTUnwrap(MetalFillEngine.shared, "no Metal device")
        let width = 2048, height = 1024
        let count = width * height
        let reference = [UInt8](repeating: 0, count: count * 4)

        let before = residentBytes()
        let bucket = try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: width, height: height).session)
        let afterBucket = residentBytes()
        report("fill session — bucket, 2048x1024", [
            ("counted", mb(bucket.allocatedBytes)),
            ("bytesPerPixel", String(format: "%.1f", Double(bucket.allocatedBytes) / Double(count))),
            ("footprintDelta", mb(afterBucket &- before))
        ])

        var lasso = [UInt8](repeating: 0, count: count)
        for y in (height / 4)..<(3 * height / 4) {
            for x in (width / 4)..<(3 * width / 4) { lasso[y * width + x] = 255 }
        }
        let lassoSession = try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: width,
                                                            height: height, lassoMask: lasso).session)
        report("fill session — lasso, 2048x1024", [
            ("counted", mb(lassoSession.allocatedBytes)),
            ("bytesPerPixel", String(format: "%.1f", Double(lassoSession.allocatedBytes) / Double(count)))
        ])

        // What the same session would cost at the sizes the census names, by the same arithmetic the
        // measurement above just validated.
        let perPixel = Double(bucket.allocatedBytes) / Double(count)
        report("fill session — projected", [
            ("at4096sq", mb(Int(perPixel * 4096 * 4096))),
            ("at16383sq", mb(Int(perPixel * 16383 * 16383))),
            ("compositorBudget", mb(CompositorBudget.textureBudgetBytes))
        ])
        _ = lassoSession
    }

    // MARK: - 3. Undo accounting

    /// **What an undo step charges against what it retains** — census item 8, and the two
    /// measurements that disagree about its sign. [BUGS.md](BUGS.md) says a vector edit is charged
    /// 3–6× what it retains; PERFORMANCE.md §9 item 4 says one screen inch of stroke is charged
    /// 1/33rd of what it holds. Both can be true of a per-*element* constant, and this is where that
    /// is settled with numbers instead of prose.
    @MainActor
    func testWhatAnUndoStepChargesAgainstWhatItRetains() {
        for strokes in [1, 200, 1000] {
            let canvas = VectorCanvas.empty(size: Self.canvasSize)
            for index in 0..<strokes { canvas.addStroke(Self.benchStroke(index)) }
            let before = canvas.elements
            canvas.addStroke(Self.benchStroke(strokes))
            let after = canvas.elements

            let charged = (before.count + after.count) * 512
            let retained = Self.retainedBytes(before: before, after: after)
            report("undo charge — one stroke onto a cel", [
                ("strokesOnCel", "\(strokes)"),
                ("elementStride", "\(MemoryLayout<VectorElement>.stride) B"),
                ("charged", "\(charged) B"),
                ("retained", "\(retained) B"),
                ("ratio", String(format: "%.2fx", Double(charged) / Double(max(1, retained))))
            ])
        }

        // The other direction: one long stroke, where 512 is far too little.
        let canvas = VectorCanvas.empty(size: Self.canvasSize)
        let before = canvas.elements
        var long = Self.benchStroke(0)
        var samples = StrokeSamples(channels: .pressureOnly)
        samples.reserveCapacity(5631)
        for step in 0..<5631 {   // PERFORMANCE.md §9 item 3's stored samples per screen inch at 16383²
            let t = CGFloat(step) / 5630
            samples.append(VectorSample(x: 40 + t * 1900, y: 500, pressure: 0.5))
        }
        long.samples = samples
        canvas.addStroke(long)
        let after = canvas.elements
        report("undo charge — one 5631-sample stroke", [
            ("charged", "\((before.count + after.count) * 512) B"),
            ("retained", "\(Self.retainedBytes(before: before, after: after)) B")
        ])
    }

    /// **The same question asked of the allocator instead of of `MemoryLayout`** — thirty real undo
    /// steps on a thousand-stroke cel, and what the process's footprint does.
    ///
    /// PERFORMANCE.md §11.5 put "really retained, per step" at **0.30 MB** at a thousand strokes
    /// against 0.98 MB charged, and concluded the charge was 3–6× too high. That table is the reason
    /// this arm exists: an arithmetic answer that contradicts a device measurement is worth two
    /// measurements rather than an argument, and `phys_footprint` over a run of steps is the second
    /// one. Each step is recorded with a mutation after it, which is what forces the previous step's
    /// `to` array to stop being shared with the live canvas.
    @MainActor
    func testWhatThirtyUndoStepsActuallyCost() {
        let canvas = VectorCanvas.empty(size: Self.canvasSize)
        for index in 0..<1000 { canvas.addStroke(Self.benchStroke(index)) }
        var steps: [([VectorElement], [VectorElement])] = []
        steps.reserveCapacity(30)
        let before = residentBytes()
        for step in 0..<30 {
            autoreleasepool {
                let from = canvas.elements
                canvas.addStroke(Self.benchStroke(1000 + step))
                steps.append((from, canvas.elements))
            }
        }
        let after = residentBytes()
        report("thirty undo steps on a 1000-stroke cel", [
            ("elementStride", "\(MemoryLayout<VectorElement>.stride) B"),
            ("chargedPerStep", String(format: "%.2f MB", Double(2001 * 512) / 1_048_576)),
            ("footprintPerStep", String(format: "%.2f MB", Double(after &- before) / 30 / 1_048_576)),
            ("footprintTotal", mb(after &- before))
        ])
        steps.removeAll()
    }

    /// **Bytes an undo entry holding both lists actually retains, and the first version of this
    /// counted only half of it.**
    ///
    /// Two terms, not one. The **geometry** of every element in one list and not the other — an
    /// element in both is copy-on-write shared with the live canvas and costs the entry nothing. And
    /// the **two array buffers themselves**: `from` and `to` differ in length, so they are two
    /// distinct allocations of `count × MemoryLayout<VectorElement>.stride`, and after the artist's
    /// next edit neither is shared with anything. That second term is what makes a flat per-element
    /// charge nearly right for a list of short strokes and hopelessly wrong for one long one, and
    /// leaving it out is how a first pass here reported a 1067× overcharge that is really ~3×.
    private static func retainedBytes(before: [VectorElement], after: [VectorElement]) -> Int {
        let beforeIDs = Set(before.map(\.id)), afterIDs = Set(after.map(\.id))
        var total = (before.count + after.count) * MemoryLayout<VectorElement>.stride
        for element in before where !afterIDs.contains(element.id) { total += elementBytes(element) }
        for element in after where !beforeIDs.contains(element.id) { total += elementBytes(element) }
        return total
    }

    private static func elementBytes(_ element: VectorElement) -> Int {
        switch element {
        case .stroke(let stroke):
            let n = stroke.samples.count
            var bytes = n * MemoryLayout<CGPoint>.stride
            bytes += stroke.samples.channels.channels.count * n * MemoryLayout<CGFloat>.stride
            return bytes
        case .image(let image):
            guard let cg = image.image.cgImage else { return 0 }
            return cg.bytesPerRow * cg.height
        case .fill, .text, .video:
            return 0
        }
    }

    // MARK: - 4. The save snapshot

    /// **What `ProjectStore.SaveSnapshot` holds at once** — census item 12, which says it "renders
    /// every content-bearing cel … all live during the write".
    ///
    /// **Two arms, because the answer depends on something the census does not mention.** A cel whose
    /// `CGContext` has been touched in one corner is lazily committed (PERFORMANCE.md §9 item 8), so
    /// its nominal 8 MiB is not resident and `renderToUIImage()` hands back a `CGImage` sharing that
    /// same buffer copy-on-write. A cel painted edge to edge is fully committed and the image shares
    /// *that*. Either way the snapshot's images are shared with storage the document already holds —
    /// so the question is whether the walk adds bytes, and `sparse`/`dense` is how it is asked.
    @MainActor
    func testWhatASaveSnapshotHoldsAtOnce() {
        for (label, dense) in [("sparse", false), ("dense", true)] {
            let cels = 20
            let manager = CanvasManager()
            manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
            manager.canvasSize = Self.canvasSize
            manager.addLayer()
            manager.layers[0].cels = []
            for frame in 0..<cels {
                let raster = RasterLayerTexture.empty(size: Self.canvasSize)
                if dense {
                    // Edge to edge, so every page of the bitmap is committed. A grid of ordinary
                    // dabs rather than one enormous one: a radius past the canvas overflows
                    // `stampCircle`'s own geometry.
                    for x in stride(from: 0, through: 2048, by: 64) {
                        for y in stride(from: 0, through: 1024, by: 64) {
                            raster.stampCircle(at: CGPoint(x: x, y: y), radius: 48, color: .black,
                                               alpha: 1, hardness: 1, blendMode: .normal)
                        }
                    }
                } else {
                    raster.stampCircle(at: CGPoint(x: 100, y: 100), radius: 8, color: .black,
                                       alpha: 1, hardness: 1, blendMode: .normal)
                }
                manager.layers[0].cels.append(Cel(id: UUID(), startFrame: frame, frameCount: 1,
                                                  raster: raster))
            }
            let before = residentBytes()
            var held: [UIImage] = []
            let start = CFAbsoluteTimeGetCurrent()
            for cel in manager.layers[0].cels where cel.raster.hasContent {
                held.append(cel.raster.renderToUIImage())
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let after = residentBytes()
            let nominal = held.reduce(0) { $0 + (($1.cgImage?.bytesPerRow ?? 0) * ($1.cgImage?.height ?? 0)) }
            report("save snapshot — raster cels rendered and held", [
                ("fixture", label),
                ("cels", "\(cels)"),
                ("nominal", mb(nominal)),
                ("footprintDeltaOfTheWalk", mb(after &- before)),
                ("mainActorSeconds", ms(elapsed))
            ])
            held.removeAll()
        }

        // The other half of what `SaveSnapshot.init` does on the main actor: `makeCopy()` per vector
        // cel. A `VectorCanvas` copy shares its `_elements` buffer copy-on-write, so this is the
        // arm that says whether the census's "copies every vector cel" is bytes or a pointer.
        let manager = vectorDocument(frames: 300, strokesPerCel: 12)
        let before = residentBytes()
        let start = CFAbsoluteTimeGetCurrent()
        var copies: [VectorCanvas] = []
        for cel in manager.layers[0].cels { if let vector = cel.vector { copies.append(vector.makeCopy()) } }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let after = residentBytes()
        report("save snapshot — vector cels copied and held", [
            ("cels", "\(copies.count)"),
            ("footprintDelta", mb(after &- before)),
            ("mainActorSeconds", ms(elapsed))
        ])
        copies.removeAll()
        withExtendedLifetime(manager) {}
    }

    // MARK: - 6. After the change

    /// **What the same rest and the same scrub hold now** — the closing half of
    /// `testWhatARestAndAScrubHoldAtTheOwnersCanvas`, with the budget reading whatever the machine
    /// this runs on decides. Reported beside the budget so a run on a different device is still
    /// interpretable.
    @MainActor
    func testWhatARestAndAScrubHoldNowThatTheMemoIsBudgeted() {
        let frames = 100
        PixelOps.clearRasterizeCache()
        VectorRenderCache.removeAll()
        // The owner's iPad 9, so the number is about their device rather than about this Mac.
        CompositorBudget.budgetOverrideBytes = CompositorBudget.textureBudgetBytes(physicalMemory: 3 << 30)
        defer { CompositorBudget.budgetOverrideBytes = nil }

        let manager = vectorDocument(frames: frames, strokesPerCel: 12)
        let built = residentBytes()
        for frame in 0..<frames {
            autoreleasepool {
                manager.currentFrame = frame
                _ = manager.makeFrameRecipe(atFrame: frame, includeBackground: true)?.composite()
            }
        }
        let scrub = vectorRenderBytes(manager)
        report("after a 100-frame scrub — budgeted, at the iPad 9's budget", [
            ("vectorRenderEntries", "\(scrub.entries)"),
            ("vectorRenderCounted", mb(VectorRenderCache.residentBytes)),
            ("flattenMemoCounted", mb(PixelOps.rasterizeCacheBytes)),
            ("maskCacheCounted", mb(MaskResolver.cacheBytes)),
            ("countedTotal", mb(VectorRenderCache.residentBytes + PixelOps.rasterizeCacheBytes)),
            ("budget", mb(CompositorBudget.textureBudgetBytes)),
            ("footprint", mb(residentBytes() &- built))
        ])
    }

    // MARK: - 5. Blanked hosts

    /// **What a canvas-sized image costs while it is masked out** — census item 4 and PERFORMANCE.md
    /// §9 item 5. The device measured 19 MB of marginal cost for *displaying* one 2048² image; what
    /// nothing has measured is whether a zero-alpha `CALayer.mask` already avoids it, which is what
    /// decides whether `setBlanked` nilling `contents` buys anything at all.
    @MainActor
    func testWhatAMaskedOutImageViewStillHolds() {
        let image = Self.solidCanvasImage()
        let counted = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)

        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 400, height: 300)))
        let view = UIImageView(frame: window.bounds)
        window.addSubview(view)
        window.isHidden = false

        let empty = residentBytes()
        view.image = image
        CATransaction.flush()
        let shown = residentBytes()

        let mask = CALayer()
        view.layer.mask = mask
        CATransaction.flush()
        let masked = residentBytes()

        view.image = nil
        CATransaction.flush()
        let nilled = residentBytes()

        report("a canvas-sized image in a view", [
            ("imageCounted", mb(counted)),
            ("footprintOnShow", mb(shown &- empty)),
            ("footprintWhileMasked", mb(masked &- empty)),
            ("footprintAfterNilContents", mb(nilled &- empty))
        ])
        window.isHidden = true
    }

    private static func solidCanvasImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
        }
    }
}
