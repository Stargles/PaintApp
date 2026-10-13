import XCTest
import SwiftUI
import UIKit
import Combine

/// **A fill slider's tick is a render of the adjustable fill and nothing else** — TODO (157). The owner:
/// *"The gap closing slider in the fill tool is being janky for some reason."*
///
/// Each tick used to write the slider's value into a `@Published` property of `CanvasManager` and the
/// render's picture into the cel, so every tick was a SwiftUI pass over the editor and a document
/// change the canvas re-baked. These pin the replacement from the model's side: the value lives in
/// `FillSettings`, the picture in `CanvasManager.liveFill`, the canvas hears of it through
/// `onHeldPictureMoved`, and the document changes once — at the commit, as one undo step.
final class FillLiveSliderLogicTests: XCTestCase {

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    /// A 64² document whose only layer holds a black box with a 6 px opening in its right side, and a
    /// fill tapped inside it with the slider at 0 — so the fill leaks out through the opening until the
    /// slider seals it.
    private func adjustableFill() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        let ink = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setFill()
            for rect in [CGRect(x: 10, y: 10, width: 44, height: 3), CGRect(x: 10, y: 51, width: 44, height: 3),
                         CGRect(x: 10, y: 10, width: 3, height: 44), CGRect(x: 51, y: 10, width: 3, height: 19),
                         CGRect(x: 51, y: 35, width: 3, height: 19)] {
                ctx.fill(rect)
            }
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ink)
        manager.addLayer()
        manager.brushColor = Self.red
        manager.setFillGapClosing(0)
        manager.beginInteractiveFill(at: CGPoint(x: 30, y: 30))
        manager.endInteractiveFill()
        settle()
        return manager
    }

    private func settle(_ seconds: TimeInterval = 0.4) {
        let done = expectation(description: "the render's hop to main has run")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    private func alpha(_ preview: FillPreview?, at point: CGPoint) -> UInt8 {
        guard let preview, let cg = preview.image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg),
              preview.rect.contains(point) else { return 0 }
        let x = Int(point.x - preview.rect.minX), y = Int(point.y - preview.rect.minY)
        return bytes[(y * cg.width + x) * 4 + 3]
    }

    /// **Zero `objectWillChange` per tick, and the picture follows.** Eight slider values with the
    /// fill adjustable: the canvas manager publishes nothing — no editor pass, no document change —
    /// while `FillSettings` publishes each value, the canvas is told every new picture, and the last
    /// picture is the sealed fill: the opening at the slider's top no longer lets it out.
    func testATickPublishesNothingOnTheManagerAndTheCanvasIsToldThePicture() throws {
        let manager = adjustableFill()
        let outside = CGPoint(x: 60, y: 32)
        XCTAssertGreaterThan(alpha(manager.liveFill?.preview, at: outside), 0,
                             "Fixture check: at 0 the fill leaks out through the opening")

        var managerChanges = 0, settingsChanges = 0, told = 0
        let a = manager.objectWillChange.sink { managerChanges += 1 }
        let b = manager.fillSettings.objectWillChange.sink { settingsChanges += 1 }
        manager.onHeldPictureMoved = { told += 1 }
        defer { a.cancel(); b.cancel() }
        let versions = manager.layers.map { $0.cels.map { $0.raster.version } }

        for gap in stride(from: CGFloat(5), through: 40, by: 5) {
            manager.setFillGapClosing(gap)
            manager.fillQueue.sync {}
            settle(0.15)
        }

        XCTAssertEqual(managerChanges, 0, "a tick raises no pass over the editor")
        XCTAssertGreaterThanOrEqual(settingsChanges, 8, "the sliders hear every value")
        XCTAssertGreaterThanOrEqual(told, 1, "the canvas is told the new picture")
        XCTAssertEqual(manager.layers.map { $0.cels.map { $0.raster.version } }, versions,
                       "no cel is written while the fill is adjustable")
        XCTAssertEqual(alpha(manager.liveFill?.preview, at: outside), 0, "the sealed fill stays inside the box")
        XCTAssertGreaterThan(alpha(manager.liveFill?.preview, at: CGPoint(x: 14, y: 14)), 0,
                             "…and reaches into its corner")
    }

    /// **The document changes once, at the commit, as one undo step**, and the picture it lands is the
    /// one the slider left on screen.
    func testTheCommitWritesTheSlidersLastPictureAsOneUndoStep() throws {
        let manager = adjustableFill()
        let before = manager.history.undoStack.count
        for gap in stride(from: CGFloat(5), through: 40, by: 5) {
            manager.setFillGapClosing(gap)
            manager.fillQueue.sync {}
            settle(0.15)
        }
        XCTAssertEqual(manager.history.undoStack.count, before, "no step while the slider moves")
        let shown = try XCTUnwrap(manager.liveFill?.preview)

        manager.commitInteractiveFill()

        XCTAssertNil(manager.liveFill, "the picture is let go")
        XCTAssertEqual(manager.history.undoStack.count, before + 1, "one step for the fill")
        let landed = try XCTUnwrap(manager.layers[1].cels.first?.raster.renderToUIImage().cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(landed))
        for point in [CGPoint(x: 30, y: 30), CGPoint(x: 14, y: 14), CGPoint(x: 60, y: 32)] {
            let landedAlpha = bytes[(Int(point.y) * landed.width + Int(point.x)) * 4 + 3]
            XCTAssertEqual(landedAlpha > 0, alpha(shown, at: point) > 0, "the commit lands what was shown at \(point)")
        }
    }

    /// **While a fill is adjustable its layer's host draws itself**, whatever the compositor would
    /// otherwise show — the bake holds no fill that has not landed — and not a moment longer.
    @MainActor
    func testTheFillsLayerIsAHeldHostWhileTheFillIsUp() throws {
        let manager = adjustableFill()
        XCTAssertEqual(manager.heldHostLayerIndices, [1], "the fill lands on layer 1, so its host draws it")
        manager.commitInteractiveFill()
        XCTAssertEqual(manager.heldHostLayerIndices, [], "committed: the document holds it now")

        let cancelled = adjustableFill()
        cancelled.cancelInteractiveFill()
        XCTAssertNil(cancelled.liveFill)
        XCTAssertEqual(cancelled.heldHostLayerIndices, [], "cancelled: nothing to draw")
    }

    // MARK: - One render in flight, the newest next (TODO (179))

    /// Spins the main run loop until `done` holds, up to ten seconds — a landing is a hop back to main,
    /// and a loaded machine outruns any guessed interval.
    private func spin(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// **A burst of ticks while a render is in flight is one more render: the newest.** Forty ticks of
    /// the slider with `fillQueue` held — the first is minted at once and waits on the queue, and every
    /// tick after it replaces the one waiting behind it — so when the queue frees, two renders land:
    /// the first tick's and the last's. None of the thirty-eight between is ever rendered, and the
    /// picture left on screen is the last value's: sealed.
    @MainActor
    func testABurstOfTicksWhileARenderIsInFlightIsOneRenderOfTheNewest() throws {
        let manager = adjustableFill()
        let renders = try XCTUnwrap(manager.fillRenders, "Fixture check: the adjustable fill has its renders")
        let landed = renders.landedCount
        let gate = DispatchSemaphore(value: 0)
        manager.fillQueue.async { gate.wait() }
        for gap in stride(from: CGFloat(1), through: 40, by: 1) { manager.setFillGapClosing(gap) }
        gate.signal()
        spin { renders.landedCount >= landed + 2 }
        settle(0.3)   // and nothing after them

        XCTAssertEqual(renders.landedCount - landed, 2, "the first tick's render and the newest, nothing between")
        XCTAssertEqual(alpha(manager.liveFill?.preview, at: CGPoint(x: 60, y: 32)), 0,
                       "the newest is the one shown: the sealed fill stays inside the box")
    }

    /// **A touch-move that moves no value renders nothing** — the sideways drag calls
    /// `updateInteractiveFill` on every touch-move, and most of them land on the same quantized Gap
    /// Closing as the last.
    @MainActor
    func testATouchMoveThatMovesNoValueRendersNothing() throws {
        let manager = adjustableFill()
        let renders = try XCTUnwrap(manager.fillRenders)
        let landed = renders.landedCount
        for _ in 0..<10 { manager.updateInteractiveFill(gapClosing: manager.fillSettings.gapClosing) }
        settle(0.3)
        XCTAssertEqual(renders.landedCount, landed, "ten touch-moves at the same value rendered nothing")
        XCTAssertFalse(renders.isBusy)
    }

    /// **A fill obeys the marching ants on screen and in the document alike.** A region selected on blank
    /// paper and a bucket fill tapped inside it: the render the host is handed comes with the region to
    /// clip it to (`LiveFill.clip`), and the commit lands the same clipped picture — one function builds
    /// both (`FillRenderResult.preview(clippedTo:)`), so the fill does not spill when the pencil lifts.
    func testAFillInsideASelectionIsClippedOnScreenAndInTheCommit() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let region = CGRect(x: 16, y: 16, width: 24, height: 20)
        manager.selection = Selection(path: CGPath(rect: region, transform: nil), bounds: region)
        manager.brushColor = Self.red
        let inside = CGPoint(x: 28, y: 26), outside = CGPoint(x: 5, y: 5)
        manager.beginInteractiveFill(at: inside)
        manager.endInteractiveFill()
        settle()

        let live = try XCTUnwrap(manager.liveFill)
        XCTAssertNotNil(live.clip, "the fill's render comes with the selection to clip it to")
        let shown = try XCTUnwrap(live.preview, "Fixture check: the fill rendered")
        XCTAssertGreaterThan(alpha(shown, at: inside), 0, "inside the region the fill is shown")
        XCTAssertEqual(alpha(shown, at: outside), 0, "…and outside it nothing, though the paper there is open")

        manager.commitInteractiveFill()
        let cel = try XCTUnwrap(manager.activeCelIndex(inLayer: 0, atFrame: manager.currentFrame))
        let landed = try XCTUnwrap(manager.layers[0].cels[cel].raster.renderToUIImage().cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(landed))
        func landedAlpha(_ point: CGPoint) -> UInt8 { bytes[(Int(point.y) * landed.width + Int(point.x)) * 4 + 3] }
        XCTAssertGreaterThan(landedAlpha(inside), 200, "the commit lands the fill inside the region")
        XCTAssertEqual(landedAlpha(outside), 0, "…and nothing outside it")
    }

    // MARK: - The sideways drag (TODO (186))

    /// **Gap Closing and nothing else, and rightward lowers it** — the owner's *"invert the direction, so
    /// that drag right decreases gap fill."* The whole range is one sweep, and the ends clamp.
    func testTheSidewaysDragLowersGapClosingToTheRightAndRaisesItToTheLeft() {
        let range = CanvasManager.fillGapRange
        let sweep = CanvasManager.fillDragSweepPoints
        let start: CGFloat = 8
        XCTAssertLessThan(CanvasManager.fillDragGapClosing(from: start, travelled: 20), start, "Right lowers it")
        XCTAssertGreaterThan(CanvasManager.fillDragGapClosing(from: start, travelled: -20), start, "Left raises it")
        XCTAssertEqual(CanvasManager.fillDragGapClosing(from: start, travelled: 0), start)
        XCTAssertEqual(CanvasManager.fillDragGapClosing(from: range.upperBound, travelled: sweep), range.lowerBound,
                       accuracy: 1e-9, "One sweep to the right crosses the whole range")
        XCTAssertEqual(CanvasManager.fillDragGapClosing(from: start, travelled: 10 * sweep), range.lowerBound, "…and clamps")
        XCTAssertEqual(CanvasManager.fillDragGapClosing(from: start, travelled: -10 * sweep), range.upperBound)
    }
}
