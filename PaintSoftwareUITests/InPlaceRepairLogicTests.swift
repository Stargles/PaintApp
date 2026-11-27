import XCTest
import UIKit

/// **S3b's promises, asserted on the layer's own picture** (SCHEDULER_DESIGN.md §3.1, §6 S3b): an edit
/// repairs the picture it already has, in place, over the damage only; an Undo copies the pixels that
/// edit replaced back and walks nothing; those kept pixels are asked of the one budget and given up
/// when it needs the room; and a walk nobody wants any more stops at its next element — driven here
/// through a scheduler on the virtual executor, so the cancel lands exactly where the test puts it.
///
/// Both sides of every picture comparison are shipped code drawing one display list: the canvas's own
/// repaired picture against a cold canvas's full walk of the elements it holds.
final class InPlaceRepairLogicTests: XCTestCase {

    private static let size = CGSize(width: 320, height: 240)

    private static func brush() -> Brush {
        Brush(name: "InPlace", tip: .round, size: 6, dab: BrushDabSettings(spacing: 0.25),
              stroke: BrushStrokeSettings(blendMode: .normal))
    }

    /// A short mark in cell `index` of a 10x8 grid.
    private static func mark(_ index: Int) -> VectorStroke {
        let x = 8 + CGFloat(index % 10) * 31, y = 8 + CGFloat((index / 10) % 8) * 29
        let samples = StrokeSamples((0..<6).map { step -> VectorSample in
            let t = CGFloat(step) / 5
            return VectorSample(x: x + t * 18, y: y + t * 12, pressure: 0.5 + 0.5 * t)
        }, channels: .pressureOnly)
        return VectorStroke(brush: brush(), color: CodableColor(red: Double(index % 7) / 7, green: 0.4, blue: 0.7, alpha: 1),
                            size: 6, opacity: 0.9, samples: samples, composite: .paint, seed: UInt64(index &+ 3))
    }

    /// A long, dense stroke — a walk that takes long enough to be stopped in the middle.
    private static func heavy(_ index: Int) -> VectorStroke {
        let samples = StrokeSamples((0..<1500).map { step -> VectorSample in
            let t = CGFloat(step) / 1499
            return VectorSample(x: 10 + t * 300, y: 120 + sin(t * 30 * .pi + CGFloat(index)) * 100, pressure: 1)
        }, channels: .pressureOnly)
        return VectorStroke(brush: Brush(name: "Heavy", tip: .round, size: 30, dab: BrushDabSettings(spacing: 0.02)),
                            color: CodableColor(red: 0.3, green: 0.3, blue: 0.1, alpha: 1), size: 30, opacity: 0.6,
                            samples: samples, composite: .paint, seed: UInt64(index &+ 11))
    }

    private static func drawn(_ n: Int) -> VectorCanvas {
        let canvas = VectorCanvas(size: size, elements: (0..<n).map { .stroke(mark($0)) })
        _ = canvas.render()
        return canvas
    }

    /// The bytes of `image`, copied — a layer picture's `dataProvider?.data` is its own bytes, held.
    private func bytes(_ image: UIImage) throws -> [UInt8] {
        [UInt8](try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data)
    }

    /// The worst channel difference between `canvas`'s own picture and a cold full walk of its list.
    private func worstAgainstColdWalk(_ canvas: VectorCanvas, _ what: String) throws -> Int {
        let live = try bytes(try XCTUnwrap(canvas.render(), "\(what): no picture"))
        let cold = try bytes(try XCTUnwrap(VectorCanvas(size: canvas.size, elements: canvas.elements).render()))
        XCTAssertEqual(live.count, cold.count, "\(what): layouts differ")
        return zip(live, cold).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }

    // MARK: - Repair in place

    /// **A stroke landing repairs the picture the layer already has**: the same picture object, a new
    /// revision, written over the new mark's ink only — not a canvas-sized copy — and the pixels are a
    /// full walk's.
    ///
    /// Mutation that reddens it: `inPlaceShare` 0 — every append makes a new picture again.
    func testAStrokeLandingRepairsThePictureInPlaceOverItsInkOnly() throws {
        let canvas = Self.drawn(20)
        let before = try XCTUnwrap(LayerPicture.of(canvas.render()))
        canvas.addStroke(Self.mark(55))
        let after = try XCTUnwrap(LayerPicture.of(canvas.render()))
        XCTAssertTrue(after.picture === before.picture, "the landing made a new picture instead of repairing the one it had")
        XCTAssertGreaterThan(after.revision, before.revision, "a repair moves the revision")
        XCTAssertEqual(canvas.inPlaceWrites, 1)
        let ink = canvas.lastInPlaceRect
        XCTAssertLessThan(ink.width * ink.height, Self.size.width * Self.size.height / 20,
                          "the repair wrote \(ink), not the mark's own ink")
        XCTAssertLessThanOrEqual(try worstAgainstColdWalk(canvas, "after the landing"), 0,
                                 "an appended mark drawn over the picture in place must be the full walk, byte for byte")
    }

    /// **An eraser cut repairs in place too** — the region repair, its rectangle walked into a patch of
    /// its own and copied in — and matches the full walk to within the repair seam's rounding unit.
    func testACutRepairsInPlaceToWithinARoundingUnit() throws {
        let canvas = Self.drawn(40)
        let picture = try XCTUnwrap(LayerPicture.of(canvas.render())).picture
        let centre = CGPoint(x: 8 + 3 * 31 + 9, y: 8 + 2 * 29 + 6)
        let flick = StrokeSamples((0..<5).map { step -> VectorSample in
            let t = CGFloat(step) / 4
            return VectorSample(x: centre.x - 10 + t * 20, y: centre.y - 6 + t * 12, pressure: 1)
        }, channels: .pressureOnly)
        XCTAssertTrue(canvas.erase(alongPath: flick, brush: Self.brush(), size: 10, opacity: 1, mode: .cutPoints, seed: 0))
        let repaired = try XCTUnwrap(LayerPicture.of(canvas.render()))
        XCTAssertTrue(repaired.picture === picture, "the cut made a new picture")
        XCTAssertGreaterThan(canvas.regionRepairs, 0, "PREMISE: the cut was a region repair")
        XCTAssertLessThanOrEqual(try worstAgainstColdWalk(canvas, "after the cut"), 2)
    }

    // MARK: - Undo from kept pixels

    /// **An Undo copies back the pixels its edit replaced, and walks nothing** — and so does its Redo,
    /// whose pixels the copy-back kept in turn. Both land a full walk's picture.
    ///
    /// Mutation that reddens it: `keptPatchLocked` answering nil — the Undo walks its rectangle again.
    func testUndoAndRedoCopyKeptPixelsBackWithoutAWalk() throws {
        let canvas = Self.drawn(30)
        let before = canvas.elements
        canvas.addStroke(Self.mark(64))
        _ = canvas.render()
        let after = canvas.elements
        WalkProbe.reset()
        canvas.restoreElements(before, changedInk: nil)
        _ = canvas.render()
        XCTAssertEqual(canvas.keptRestores, 1, "the Undo did not copy the kept pixels back")
        XCTAssertEqual(WalkProbe.walks, 0, "the Undo walked the layer")
        XCTAssertEqual(try worstAgainstColdWalk(canvas, "undone"), 0, "the kept pixels are not the picture before the stroke")

        WalkProbe.reset()   // the comparison's cold walk is not the Redo's
        canvas.restoreElements(after, changedInk: nil)
        _ = canvas.render()
        XCTAssertEqual(canvas.keptRestores, 2, "the Redo did not copy back the pixels the Undo kept")
        XCTAssertEqual(WalkProbe.walks, 0, "the Redo walked the layer")
        XCTAssertEqual(try worstAgainstColdWalk(canvas, "redone"), 0)
    }

    /// **A copy-back puts the footprints back with the pixels**: a mark taken away and brought back by
    /// an Undo served from kept pixels was never walked on its way back, yet the next edit that takes it
    /// away again is still bounded by its footprint — a region repair, not a whole-cel walk.
    ///
    /// Mutation that reddens it: drop `paintedBounds = used.footprints` in `acceptInPlaceLocked`.
    func testAMarkBroughtBackByAKeptUndoIsStillBounded() throws {
        let canvas = Self.drawn(30)
        let all = canvas.elements
        let without = all.filter { $0.id != all[5].id }
        canvas.restoreElements(without, changedInk: nil)          // take mark 5 away
        _ = canvas.render()
        canvas.restoreElements(all, changedInk: nil)              // its Undo: a copy-back
        _ = canvas.render()
        XCTAssertEqual(canvas.keptRestores, 1, "PREMISE: the Undo was a copy-back")
        canvas.restoreElements(without, changedInk: nil)          // the Redo, with the kept pixels gone
        XCTAssertNotEqual(canvas.lastDamage, .everything,
                          "the mark came back without its footprint, so taking it away again could not be bounded")
        canvas.dropKeptPixels()
        _ = canvas.render()
        XCTAssertLessThanOrEqual(try worstAgainstColdWalk(canvas, "after the bounded edit"), 2)
    }

    /// **Kept pixels are asked of the one budget, and given up to it**: keeping them raises what the
    /// budget holds by their bytes, and an eviction drops them — after which the Undo walks its rectangle,
    /// as it did before S3b, and is still right.
    ///
    /// Mutation that reddens it: `PixelPatch` allocating without `MemoryBudget.shared.admit`.
    func testKeptPixelsAreChargedToTheBudgetAndEvictable() throws {
        let canvas = Self.drawn(30)
        let before = canvas.elements
        let held = MemoryBudget.shared.heldBytes
        canvas.addStroke(Self.mark(64))
        _ = canvas.render()
        let kept = canvas.keptPixelBytes
        XCTAssertGreaterThan(kept, 0, "the landing kept nothing for its Undo")
        XCTAssertGreaterThanOrEqual(MemoryBudget.shared.heldBytes - held, kept, "the kept pixels are not counted by the budget")
        MemoryBudget.shared.trimCaches(toBytes: 0)
        XCTAssertEqual(canvas.keptPixelBytes, 0, "an eviction left the kept pixels in place")
        canvas.restoreElements(before, changedInk: nil)
        _ = canvas.render()
        XCTAssertEqual(canvas.keptRestores, 0)
        XCTAssertLessThanOrEqual(try worstAgainstColdWalk(canvas, "undone without kept pixels"), 2)
    }

    // MARK: - Cancellable walks, on the virtual executor

    /// **A layer walk whose job is cancelled stops at its next element** and installs nothing. The job
    /// runs on a scheduler over the virtual executor; a newer job of the same key — a step to another
    /// frame, an Undo — cancels it while it walks (rule 4), and the walk must give up its remaining
    /// strokes rather than run to the end.
    ///
    /// Mutation that reddens it: drop the per-stroke `cancelled()` check in `drawLocalContent`.
    func testACancelledJobsWalkStopsAndInstallsNothing() throws {
        let executor = VirtualExecutor()
        let scheduler = Scheduler(executor: executor, machine: VirtualExecutor.Machine(fastCores: 2, efficientCores: 4))
        let canvas = VectorCanvas(size: Self.size, elements: (0..<12).map { .stroke(Self.heavy($0)) })
        let key = JobKey("layer picture", 1)
        var landed: UIImage??
        scheduler.submit(Job(key: key, jobClass: .answer, name: "layer picture", work: { _ in canvas.render() },
                             land: { landed = $0 }))
        XCTAssertEqual(executor.workers.count, 1, "PREMISE: the walk's job started")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { scheduler.cancel(key: key) }
        DabProbe.begin()
        executor.runWorker()
        let stamped = DabProbe.end().count
        executor.drainMain()
        XCTAssertNil(landed, "a cancelled walk's job landed")
        XCTAssertEqual(canvas.rasterizations, 0, "a cancelled walk installed a picture")
        XCTAssertFalse(canvas.hasCachedImage, "a cancelled walk left a memo")
        DabProbe.begin()
        _ = VectorCanvas(size: Self.size, elements: canvas.elements).render()
        let whole = DabProbe.end().count
        XCTAssertLessThan(stamped, whole, "the cancelled walk stamped every dab (\(stamped) of \(whole)) — it ran to the end")
        XCTAssertLessThan(stamped, whole / 2, "the walk went on long after the cancel: \(stamped) of \(whole) dabs")
    }

    /// **An Undo's repair on the virtual executor is a copy-back**: the job that draws the undone layer
    /// walks nothing, so it is an answer in the time of a copy, not of a walk.
    func testAnUndoJobOnTheSchedulerWalksNothing() throws {
        let executor = VirtualExecutor()
        let scheduler = Scheduler(executor: executor, machine: VirtualExecutor.Machine(fastCores: 2, efficientCores: 4))
        let canvas = Self.drawn(30)
        let before = canvas.elements
        canvas.addStroke(Self.mark(64))
        _ = canvas.render()
        canvas.restoreElements(before, changedInk: nil)
        var landed: UIImage?
        scheduler.submit(Job(key: JobKey("layer picture", 2), jobClass: .answer, name: "layer picture",
                             work: { _ in canvas.render() }, land: { landed = $0 }))
        WalkProbe.reset()
        executor.runWorker()
        executor.drainMain()
        XCTAssertNotNil(landed, "the Undo's picture did not land")
        XCTAssertEqual(WalkProbe.walks, 0, "the Undo's job walked the layer")
        XCTAssertEqual(canvas.keptRestores, 1)
    }
}
