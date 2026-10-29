import XCTest
import SwiftUI
import UIKit
import QuartzCore

/// **What one fill gesture adds to the process, at three canvas sizes — TODO (86)'s measurement.**
///
/// The claim `FillWindow` makes is that a fill's memory follows the region and not the canvas. This
/// takes `phys_footprint` before a gesture and at its peak — the preview installed, the session and
/// its window still alive — on a 2048², a 6000² and an 8192² document, and prints the three deltas.
/// If the claim holds they are the same number; before (86) they were 58 bytes a canvas pixel, so
/// 243 MB, 2.1 GB and 3.9 GB.
///
/// **The delta is a footprint proxy** (CLAUDE.md): it includes whatever else the process allocated
/// in the window, and it is taken with the layer's own display render already resident — the
/// canvas-sized memo the layer host holds while the artist is looking at the layer, which the fill
/// reads through the window rather than re-rendering. That memo is the canvas's cost and is charged
/// to the display, not to the gesture; a measurement that took it here would be measuring
/// `VectorCanvas.render` at three sizes.
///
/// The 2048²/6000²/8192² measurement is opt-in — configure
/// `PAINTAPP_FILL_FOOTPRINT=1` in the XCTest runner environment — because a footprint sampled on a
/// loaded machine is a sample of the machine (CLAUDE.md's bench rule). The guard runs before those
/// large fixtures are allocated.
///
/// The explicit Mend cost witnesses below use `PAINTAPP_BENCH=1`; they report warm simulator work
/// and baseline-relative process footprint without an invented wall-clock or memory threshold.
///
/// Not `…LogicTests`, so the fast tier does not build three canvases up to 8192² on every run.
final class FillFootprintBench: XCTestCase {

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    override func tearDown() {
        PixelOps.clearRasterizeCache()
        super.tearDown()
    }

    private struct FootprintSampleFailure: Error, CustomStringConvertible {
        let code: kern_return_t
        var description: String { "task_info(TASK_VM_INFO) failed with kern_return_t \(code)" }
    }

    private func footprintBytes() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw FootprintSampleFailure(code: result) }
        return UInt64(info.phys_footprint)
    }

    private func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "FILL FOOTPRINT | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "FILL FOOTPRINT — \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private final class PeakFootprint {
        private let lock = NSLock()
        private var maximum: UInt64
        private var stopped = false
        private var sampleFailure: Error?
        let finished = DispatchSemaphore(value: 0)
        init(_ initial: UInt64) { maximum = initial }
        func observe(_ result: Result<UInt64, Error>) {
            lock.lock()
            switch result {
            case .success(let value): maximum = max(maximum, value)
            case .failure(let error): sampleFailure = error; stopped = true
            }
            lock.unlock()
        }
        func stop() { lock.lock(); stopped = true; lock.unlock() }
        var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
        var value: UInt64 { lock.lock(); defer { lock.unlock() }; return maximum }
        func throwIfFailed() throws {
            lock.lock(); defer { lock.unlock() }
            if let sampleFailure { throw sampleFailure }
        }
    }

    private struct FootprintMeasurement {
        let baseline: UInt64
        let peak: UInt64
        let seconds: Double
    }

    private func startPeakSampler() throws -> (baseline: UInt64, peak: PeakFootprint) {
        let baseline = try footprintBytes()
        let peak = PeakFootprint(baseline)
        Thread { [self, peak] in
            defer { peak.finished.signal() }
            while !peak.isStopped {
                peak.observe(Result { try footprintBytes() })
                Thread.sleep(forTimeInterval: 0.002)
            }
        }.start()
        return (baseline, peak)
    }

    private func finishPeakSampler(_ started: (baseline: UInt64, peak: PeakFootprint), seconds: Double) throws -> FootprintMeasurement {
        started.peak.observe(Result { try footprintBytes() })
        started.peak.stop()
        started.peak.finished.wait()
        try started.peak.throwIfFailed()
        return FootprintMeasurement(baseline: started.baseline, peak: started.peak.value, seconds: seconds)
    }

    private func measuredPeak(_ work: () -> Void) throws -> FootprintMeasurement {
        let started = try startPeakSampler()
        let begin = CACurrentMediaTime()
        work()
        return try finishPeakSampler(started, seconds: CACurrentMediaTime() - begin)
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    private struct MendImage {
        let bytes: [UInt8]
        let side: Int
        let seconds: Double
        let memory: FootprintMeasurement
        let previewWindow: CGRect
    }

    private func mendReferenceStrokes() -> [VectorStroke] {
        func stroke(_ points: [CGPoint], size: CGFloat) -> VectorStroke {
            VectorStroke(brush: TestBrushes.hardRound,
                         color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                         size: size, opacity: 1,
                         samples: StrokeSamples(points: points), seed: 0x7354)
        }
        return [
            stroke([CGPoint(x: 8, y: 8), CGPoint(x: 56, y: 8), CGPoint(x: 56, y: 56),
                    CGPoint(x: 8, y: 56), CGPoint(x: 8, y: 8)], size: 2),
            stroke([CGPoint(x: 20, y: 20), CGPoint(x: 28, y: 20), CGPoint(x: 28, y: 28),
                    CGPoint(x: 20, y: 28), CGPoint(x: 20, y: 20)], size: 2),
            stroke([CGPoint(x: 34, y: 16), CGPoint(x: 34, y: 31)], size: 3),
            stroke([CGPoint(x: 8, y: 44), CGPoint(x: 34, y: 44)], size: 3)
        ]
    }

    private func interactiveMendTrial(mend: Bool, measured: Bool) throws -> MendImage {
        let size = CGSize(width: 64, height: 64)
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.canvasSize = size
        XCTAssertTrue(manager.addVectorLayer(), "fixture creates its vector reference layer")
        let referenceLayer = manager.currentLayerIndex
        let reference = try XCTUnwrap(manager.layers[referenceLayer].cels[0].vector)
        reference.restoreElements(mendReferenceStrokes().map(VectorElement.stroke), changedInk: nil)
        manager.setFillReference(layerIndex: referenceLayer, isReference: true)
        XCTAssertTrue(manager.addVectorLayer(), "fixture creates its vector fill layer")
        let fillLayer = manager.currentLayerIndex
        let fillCanvas = try XCTUnwrap(manager.layers[fillLayer].cels[0].vector)
        manager.fillSettings.bucketEdgeOverlap = 0
        manager.fillSettings.gapClosing = 0
        manager.fillSettings.mendReach = 12
        manager.setFillMendsGaps(mend)
        manager.brushColor = Self.red
        _ = reference.render()
        _ = fillCanvas.render()

        let measurement: FootprintMeasurement
        if measured {
            measurement = try measuredPeak {
                manager.beginInteractiveFill(at: CGPoint(x: 16, y: 16))
                manager.endInteractiveFill()
                manager.fillQueue.sync {}
            }
        } else {
            let start = CACurrentMediaTime()
            manager.beginInteractiveFill(at: CGPoint(x: 16, y: 16))
            manager.endInteractiveFill()
            manager.fillQueue.sync {}
            let footprint = try footprintBytes()
            measurement = FootprintMeasurement(baseline: footprint, peak: footprint,
                                               seconds: CACurrentMediaTime() - start)
        }
        settle()
        let preview = try XCTUnwrap(manager.fillLastRender, "the interactive fill produced a drawable preview")
        XCTAssertTrue(manager.isPointInPendingFill(at: CGPoint(x: 16, y: 16)), "the seed remains in the fill")
        XCTAssertTrue(manager.commitInteractiveFill(), "the measured fill lands through the normal commit")
        let picture = try XCTUnwrap(fillCanvas.render()?.cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(picture))
        return MendImage(bytes: bytes, side: picture.width, seconds: measurement.seconds,
                         memory: measurement, previewWindow: preview.window.rect)
    }

    private func red(_ bytes: [UInt8], side: Int, x: Int, y: Int) -> Bool {
        let offset = (y * side + x) * 4
        return bytes[offset] > 240 && bytes[offset + 1] < 20 && bytes[offset + 2] < 20 && bytes[offset + 3] > 240
    }

    private func alpha(_ bytes: [UInt8], side: Int, x: Int, y: Int) -> UInt8 {
        bytes[(y * side + x) * 4 + 3]
    }

    private struct BatchMendFixture {
        let manager: CanvasManager
        let layerIndex: Int
        let vectors: [VectorCanvas]
        let originalPathData: [Data]
    }

    private func fillPathData(_ vectors: [VectorCanvas]) -> [Data] {
        vectors.compactMap { $0.elements.first?.fill?.pathData }
    }

    private func warmBatchMendEngine() async throws {
        let fixture = try batchMendFixture(celCount: 3)
        let result = await fixture.manager.mendAllFills(layerIndex: fixture.layerIndex)
        XCTAssertEqual(result, .changed(3), "the small warm-up batch reaches the ordinary mend path")
    }

    /// A deliberately light, explicit scene: one 72² canonical vector line-art reference and one
    /// small fill with a detached and an attached gap in each target cel.
    private func batchMendFixture(celCount: Int) throws -> BatchMendFixture {
        _ = try XCTUnwrap(MetalFillEngine.shared, "the shared Metal fill engine is required")
        let size = CGSize(width: 72, height: 72)
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.canvasSize = size
        XCTAssertTrue(manager.addVectorLayer(), "batch fixture creates its vector reference layer")
        let referenceLayer = manager.currentLayerIndex
        CanvasFixture.setCelLayout(manager, layerIndex: referenceLayer, [(start: 0, length: celCount)])
        manager.layers[referenceLayer].cels[0].vector = VectorCanvas(size: size,
            strokes: mendReferenceStrokes())
        manager.setFillReference(layerIndex: referenceLayer, isReference: true)
        XCTAssertTrue(manager.addVectorLayer(), "batch fixture creates its vector fill layer")
        let fillLayer = manager.currentLayerIndex
        CanvasFixture.setCelLayout(manager, layerIndex: fillLayer,
            (0..<celCount).map { (start: $0, length: 1) })
        let field = CGRect(x: 10, y: 10, width: 44, height: 44)
        let hole = CGRect(x: 20, y: 20, width: 8, height: 8)
        let holePath = CGPath(rect: hole, transform: nil)
        let bodyGap = CGPath(rect: CGRect(x: 32, y: 16, width: 4, height: 16), transform: nil)
        let attachedGap = CGPath(rect: CGRect(x: 8, y: 42, width: 28, height: 4), transform: nil)
        let initialPath = CGPath(rect: field, transform: nil).subtracting(holePath, using: .winding)
            .subtracting(bodyGap, using: .winding).subtracting(attachedGap, using: .winding)
        var vectors: [VectorCanvas] = []
        var originals: [Data] = []
        vectors.reserveCapacity(celCount); originals.reserveCapacity(celCount)
        for index in 0..<celCount {
            let fill = VectorFillElement(path: initialPath,
                color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), evenOddFill: true)
            let vector = VectorCanvas(size: size, elements: [.fill(fill)])
            manager.layers[fillLayer].cels[index].vector = vector
            vectors.append(vector)
            originals.append(fill.pathData)
        }
        manager.fillSettings.threshold = 0.15
        manager.fillSettings.mendReach = 12
        return BatchMendFixture(manager: manager, layerIndex: fillLayer,
                                vectors: vectors, originalPathData: originals)
    }

    private func checkBatchMendPicture(_ vector: VectorCanvas, fillIndex: Int, phase: String) throws {
        let image = try XCTUnwrap(vector.render()?.cgImage, "\(phase) cel \(fillIndex) has a rendered vector picture")
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(image))
        XCTAssertGreaterThan(alpha(bytes, side: image.width, x: 34, y: 24), 240,
                             "\(phase) closes the detached interior stroke in cel \(fillIndex)")
        XCTAssertGreaterThan(alpha(bytes, side: image.width, x: 20, y: 44), 240,
                             "\(phase) closes the attached stroke in cel \(fillIndex)")
        XCTAssertEqual(alpha(bytes, side: image.width, x: 24, y: 24), 0,
                        "the \(phase) result preserves the intentional square paper hole in cel \(fillIndex)")
        XCTAssertEqual(alpha(bytes, side: image.width, x: 5, y: 36), 0,
                       "\(phase) keeps the original exterior edge in cel \(fillIndex)")
    }

    /// A vector document at `side`², one layer, one 200-pixel box of ink at the centre, its display
    /// render already made.
    private func document(side: Int) -> (CanvasManager, VectorCanvas, CGRect) {
        let size = CGSize(width: side, height: side)
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.canvasSize = size
        manager.addLayer()
        manager.layers[0].kind = .vector
        manager.brushColor = Self.red
        let brush = Brush(name: "Test", tip: .round, size: 12, opacity: 1,
                          dab: BrushDabSettings(flow: 1, spacing: 0.1, hardness: 1, angle: BrushAngleSettings(jitter: 0)),
                          stroke: BrushStrokeSettings(stabilization: 0, blendMode: .normal))
        let box = CGRect(x: side / 2 - 100, y: side / 2 - 100, width: 200, height: 200)
        let outline = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                   size: 12, opacity: 1,
                                   samples: [VectorSample(x: Double(box.minX), y: Double(box.minY), pressure: 1),
                                             VectorSample(x: Double(box.maxX), y: Double(box.minY), pressure: 1),
                                             VectorSample(x: Double(box.maxX), y: Double(box.maxY), pressure: 1),
                                             VectorSample(x: Double(box.minX), y: Double(box.maxY), pressure: 1),
                                             VectorSample(x: Double(box.minX), y: Double(box.minY), pressure: 1)])
        let canvas = VectorCanvas(size: size, strokes: [outline])
        manager.layers[0].cels[0].vector = canvas
        _ = canvas.render()   // the display's own memo, resident as it is while the layer is on screen
        return (manager, canvas, box)
    }

    /// One lasso around the box and one tap inside it, each measured from a resident display to its
    /// preview — the two shapes of the tool, on the same document.
    private func measure(side: Int) throws -> (lasso: Int, bucket: Int, lassoWindow: CGRect, bucketWindow: CGRect) {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        var lassoDelta = 0, bucketDelta = 0
        var lassoWindow = CGRect.null, bucketWindow = CGRect.null
        try autoreleasepool {
            let (manager, canvas, box) = document(side: side)
            let centre = CGPoint(x: box.midX, y: box.midY)

            let beforeLasso = try footprintBytes()
            let loop = CGMutablePath()
            loop.addRect(box.insetBy(dx: -40, dy: -40))
            manager.beginInteractiveLassoFill(path: loop)
            manager.endInteractiveFill()
            manager.fillQueue.sync {}
            settle()
            let render = try XCTUnwrap(manager.fillLastRender, "the lasso previewed nothing at \(side)²")
            XCTAssertTrue(manager.isPointInPendingFill(at: centre), "the box is filled at \(side)²")
            lassoDelta = Int(try footprintBytes()) - Int(beforeLasso)
            lassoWindow = render.window.rect
            manager.commitInteractiveFill()
            XCTAssertNotNil(canvas.elements.last?.fill, "the lasso committed a vector fill at \(side)²")
            // The commit changed the layer, so the display re-renders it — the canvas's cost again,
            // and the display's, taken before the next gesture is measured.
            _ = canvas.render()

            let beforeBucket = try footprintBytes()
            manager.beginInteractiveFill(at: centre)
            manager.endInteractiveFill()
            manager.fillQueue.sync {}
            settle()
            let tap = try XCTUnwrap(manager.fillLastRender, "the tap previewed nothing at \(side)²")
            XCTAssertTrue(manager.isPointInPendingFill(at: centre))
            bucketDelta = Int(try footprintBytes()) - Int(beforeBucket)
            bucketWindow = tap.window.rect
            manager.commitInteractiveFill()
            withExtendedLifetime(canvas) {}
        }
        report("\(side)x\(side)", [
            ("lassoPhysFootprintDelta", mb(lassoDelta)), ("lassoWindow", "\(Int(lassoWindow.width))x\(Int(lassoWindow.height))"),
            ("bucketPhysFootprintDelta", mb(bucketDelta)), ("bucketWindow", "\(Int(bucketWindow.width))x\(Int(bucketWindow.height))"),
            ("canvasBytes", mb(side * side * 4))
        ])
        return (lassoDelta, bucketDelta, lassoWindow, bucketWindow)
    }

    func testOneFillsFootprintIsFlatAcrossCanvasSizes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_FILL_FOOTPRINT"] == "1",
                          "explicit 2048²/6000²/8192² fill footprint measurement")
        let sides = [2048, 6000, 8192]
        let deltas = try sides.map { try measure(side: $0) }

        // The windows are the fixture's shape, not the canvas's: the lasso's is the loop (the 200-pixel
        // box and 40 pixels of slack either side) plus the halo, the bucket's is its first window, and
        // neither moves with `side`.
        let lassoSide = 280 + 2 * CanvasManager.fillWindowHalo
        for (side, delta) in zip(sides, deltas) {
            XCTAssertEqual(delta.lassoWindow.size, CGSize(width: lassoSide, height: lassoSide), "the lasso's window at \(side)²")
            XCTAssertEqual(delta.bucketWindow.size, CGSize(width: 1024, height: 1024), "the tap's window at \(side)²")
        }

        // Flat within the noise of a footprint proxy and CoreGraphics' row-strip copy
        // (`CanvasManager.compositeReferenceRGBA`): the largest may not exceed the smallest by more
        // than 32 MB, where the canvas alone grows by 240 MB from the first size to the last and the
        // gesture's old cost by 3.7 GB.
        let slack = 32 * 1_048_576
        let lasso = deltas.map(\.lasso), bucket = deltas.map(\.bucket)
        XCTAssertLessThan(lasso.max()! - lasso.min()!, slack, "a lasso fill's footprint moved with the canvas: \(lasso)")
        XCTAssertLessThan(bucket.max()! - bucket.min()!, slack, "a bucket fill's footprint moved with the canvas: \(bucket)")
    }

    func testOptInInteractiveVectorMendCostAndDrawnOutput() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] == "1",
                          "explicit interactive Mend cost run")
        _ = try XCTUnwrap(MetalFillEngine.shared, "the shared Metal fill engine is required")
        // Warm the common Metal/session path once for each option; fixture creation and this warm
        // fill are excluded from the reported preview interval.
        for mend in [false, true] { _ = try interactiveMendTrial(mend: mend, measured: false) }
        let off = try interactiveMendTrial(mend: false, measured: true)
        let on = try interactiveMendTrial(mend: true, measured: true)
        for (name, image) in [("Mend OFF", off), ("Mend ON", on)] {
            XCTAssertTrue(red(image.bytes, side: image.side, x: 16, y: 16), "PREMISE: \(name) fills the sampled interior")
            XCTAssertEqual(alpha(image.bytes, side: image.side, x: 24, y: 24), 0,
                           "\(name) preserves the intentional square paper hole")
            XCTAssertEqual(alpha(image.bytes, side: image.side, x: 5, y: 36), 0,
                           "\(name) leaves paper outside the original frame untouched")
        }
        for point in [(34, 24, "detached internal stroke"), (20, 44, "attached stem")] {
            XCTAssertFalse(red(off.bytes, side: off.side, x: point.0, y: point.1),
                           "PREMISE: Mend OFF leaves the \(point.2) gap visible")
            XCTAssertTrue(red(on.bytes, side: on.side, x: point.0, y: point.1),
                          "Mend ON covers the \(point.2) in the drawn vector fill")
        }
        for y in 0..<off.side { for x in 0..<off.side
            where x < 7 || x >= 57 || y < 7 || y >= 57 {
            XCTAssertEqual(alpha(off.bytes, side: off.side, x: x, y: y), 0,
                           "Mend OFF never paints the exterior at (\(x),\(y))")
            XCTAssertEqual(alpha(on.bytes, side: on.side, x: x, y: y), 0,
                           "Mend ON never grows past the exterior at (\(x),\(y))")
        } }
        report("interactive vector Mend 64x64", [
            ("MendOffQueueMs", String(format: "%.3f", off.seconds * 1000)),
            ("MendOnQueueMs", String(format: "%.3f", on.seconds * 1000)),
            ("MendOffPeakPhysFootprintDelta", mb(Int(off.memory.peak &- off.memory.baseline))),
            ("MendOnPeakPhysFootprintDelta", mb(Int(on.memory.peak &- on.memory.baseline))),
            ("peakSampleInterval", "2ms; task_vm_info.phys_footprint"),
            ("MendOffWindow", "\(Int(off.previewWindow.width))x\(Int(off.previewWindow.height))"),
            ("MendOnWindow", "\(Int(on.previewWindow.width))x\(Int(on.previewWindow.height))"),
            ("fixture", "1 vector reference; frame + hole + detached and attached strokes")
        ])
        for (name, image) in [("mend-off", off), ("mend-on", on)] {
            let cg = try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied: image.bytes,
                                                                      width: image.side, height: image.side))
            let attachment = XCTAttachment(image: UIImage(cgImage: cg))
            attachment.name = "interactive-vector-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testOptInMendAllCostsAndAtomicAdmissionAtThreeHundredAndOneThousandCels() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] == "1",
                          "explicit batch Mend All cost and footprint run")
        _ = try XCTUnwrap(MetalFillEngine.shared, "the shared Metal fill engine is required")
        // Warm the serial contour/Metal path before the per-population measurements.
        try await warmBatchMendEngine()

        for count in [300, 1000] {
            let fixture = try batchMendFixture(celCount: count)
            // Only the active reference/fill pictures are resident at the measurement baseline;
            // off-screen cels retain vector data but are not pre-rendered into a canvas-sized cache.
            _ = fixture.manager.layers[0].cels[0].vector?.render()
            _ = fixture.vectors[0].render()
            let baselineUndo = fixture.manager.history.undoStack.count
            let started = try startPeakSampler()
            let begin = CACurrentMediaTime()
            let result = await fixture.manager.mendAllFills(layerIndex: fixture.layerIndex)
            let measurement = try finishPeakSampler(started, seconds: CACurrentMediaTime() - begin)
            XCTAssertEqual(result, .changed(count), "every prepared target cel contributes one accepted fill")
            let mendedPaths = fillPathData(fixture.vectors)
            XCTAssertEqual(mendedPaths.count, count)
            XCTAssertTrue(zip(fixture.originalPathData, mendedPaths).allSatisfy { $0.0 != $0.1 },
                          "every small fixture fill receives the accepted mend geometry")
            XCTAssertEqual(fixture.manager.history.undoStack.count, baselineUndo + 1,
                           "one whole-layer request is exactly one undo step")
            let probeIndices = Array(Set([0, count / 2, count - 1])).sorted()
            for index in probeIndices { try checkBatchMendPicture(fixture.vectors[index], fillIndex: index, phase: "Mend All") }

            fixture.manager.undo()
            XCTAssertEqual(fixture.manager.history.undoStack.count, baselineUndo)
            XCTAssertEqual(fixture.manager.history.redoStack.count, 1)
            XCTAssertEqual(fillPathData(fixture.vectors), fixture.originalPathData,
                           "undo restores every original target-cel path")
            for index in probeIndices {
                let image = try XCTUnwrap(fixture.vectors[index].render()?.cgImage)
                let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(image))
                XCTAssertEqual(alpha(bytes, side: image.width, x: 34, y: 24), 0,
                               "undo restores the detached stroke gap in cel \(index)")
                XCTAssertEqual(alpha(bytes, side: image.width, x: 20, y: 44), 0,
                               "undo restores the attached stroke gap in cel \(index)")
            }
            fixture.manager.redo()
            XCTAssertEqual(fixture.manager.history.undoStack.count, baselineUndo + 1)
            XCTAssertEqual(fixture.manager.history.redoStack.count, 0)
            XCTAssertEqual(fillPathData(fixture.vectors), mendedPaths,
                           "redo restores every accepted target-cel path")
            for index in probeIndices { try checkBatchMendPicture(fixture.vectors[index], fillIndex: index, phase: "redo") }

            report("Mend All \(count) target cels", [
                ("result", "changed \(count); refused 0"),
                ("previewUndoRedo", "one undo; one redo; all \(count) path payloads verified"),
                ("MendAllElapsedMs", String(format: "%.1f", measurement.seconds * 1000)),
                ("physFootprintBaseline", mb(Int(measurement.baseline))),
                ("physFootprintPeakDelta", mb(Int(measurement.peak &- measurement.baseline))),
                ("peakSampleInterval", "2ms; task_vm_info.phys_footprint"),
                ("transientBudget", mb(MetalFillEngine.fillBudgetBytes / 2)),
                ("undoBudget", mb(fixture.manager.history.maxCost)),
                ("fixture", "one 72x72 vector line-art cel; \(count) light vector fill cels; 1 fill per target cel")
            ])

            let refused = try batchMendFixture(celCount: count)
            refused.manager.history.maxCost = 1
            let originalSteps = refused.manager.history.undoStack.count
            let refusal = await refused.manager.mendAllFills(layerIndex: refused.layerIndex)
            XCTAssertEqual(refusal, .exceedsBudget, "the same batch honors the existing undo-payload budget")
            XCTAssertEqual(fillPathData(refused.vectors), refused.originalPathData,
                           "a refused request changes zero of \(count) cels")
            XCTAssertEqual(refused.manager.history.undoStack.count, originalSteps,
                           "a refused plan creates no partial undo step")
            report("Mend All refusal \(count) target cels", [
                ("result", "exceedsBudget; changed 0; refused plan leaves \(count) original paths"),
                ("undoSteps", "unchanged at \(originalSteps)")
            ])
        }
    }
}
