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
        let landed = try XCTUnwrap(try manager.layers[1].cels.first?.raster.renderToUIImage().get().cgImage)
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
        let landed = try XCTUnwrap(try manager.layers[0].cels[cel].raster.renderToUIImage().get().cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(landed))
        func landedAlpha(_ point: CGPoint) -> UInt8 { bytes[(Int(point.y) * landed.width + Int(point.x)) * 4 + 3] }
        XCTAssertGreaterThan(landedAlpha(inside), 200, "the commit lands the fill inside the region")
        XCTAssertEqual(landedAlpha(outside), 0, "…and nothing outside it")
    }

    /// The native contour and the raster flatten must land the same selected region as the live
    /// picture, including the pull-back under a Move. The untouched mark is outside every clip.
    @MainActor
    func testSelectedBucketPreviewAndCommitMatchForVectorRasterAndTranslatedLayers() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        for vector in [false, true] {
            for translated in [false, true] {
                let manager = CanvasFixture.manager(layerCount: 0)
                if vector { manager.addVectorLayer() } else { manager.addLayer() }
                let mark = CGPath(rect: CGRect(x: 54, y: 54, width: 5, height: 5), transform: nil)
                XCTAssertNotNil(manager.layDownSolidFill(mark, color: .black, layerIndex: 0, celIndex: 0, label: .fill))
                let layerID = manager.layers[0].id
                if translated {
                    manager.addTransformLayer()
                    manager.layers[1].transform = LayerPose(pose: PoseQuad(
                        box: CGRect(origin: .zero, size: CanvasFixture.canvasSize),
                        mappedBy: CGAffineTransform(translationX: 12, y: 8)), mode: .move)
                }
                manager.currentLayerIndex = 0
                let region = CGRect(x: 24, y: 20, width: 24, height: 20)
                manager.selection = Selection(path: CGPath(rect: region, transform: nil), bounds: region)
                manager.brushColor = Self.red
                let inside = CGPoint(x: 28, y: 24), outside = CGPoint(x: 56, y: 44)
                let localInside = manager.layerSpacePoint(inside, forLayerID: layerID)
                let localOutside = manager.layerSpacePoint(outside, forLayerID: layerID)
                let before = try celBytes(manager, layer: 0)
                let steps = manager.history.undoStack.count
                manager.beginInteractiveFill(at: inside)
                manager.endInteractiveFill()
                spin { manager.liveFill?.render != nil }
                let shown = try XCTUnwrap(manager.liveFill?.preview)
                XCTAssertGreaterThan(alpha(shown, at: localInside), 200, "the selected canvas point is painted in layer space")
                XCTAssertEqual(alpha(shown, at: localOutside), 0, "the clip is not carried through the pose twice")
                XCTAssertEqual(try celBytes(manager, layer: 0), before, "preview is off the document")

                XCTAssertTrue(manager.commitInteractiveFill())
                let landed = try celBytes(manager, layer: 0)
                XCTAssertEqual(sample(landed, at: localInside), [255, 0, 0, 255])
                XCTAssertEqual(sample(landed, at: localOutside), sample(before, at: localOutside), "selection exterior is unchanged")
                XCTAssertEqual(sample(landed, at: CGPoint(x: 56, y: 56)), [0, 0, 0, 255], "existing exterior ink is exact")
                XCTAssertEqual(manager.history.undoStack.count, steps + 1)
                if vector {
                    XCTAssertEqual(manager.layers[0].cels[0].vector?.fills.count, 2, "native fills remain editable")
                    XCTAssertNil(manager.layers[0].cels[0].bakedImage)
                }
                manager.undo()
                XCTAssertEqual(try celBytes(manager, layer: 0), before)
                manager.redo()
                XCTAssertEqual(try celBytes(manager, layer: 0), landed)
            }
        }
    }

    @MainActor
    func testNativeBucketCommitMatchesWindingPreviewForCrossedAndHoledSelections() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        let crossing = CGMutablePath()
        crossing.move(to: CGPoint(x: 8, y: 8))
        for point in [CGPoint(x: 48, y: 48), CGPoint(x: 8, y: 48), CGPoint(x: 48, y: 8)] { crossing.addLine(to: point) }
        crossing.closeSubpath()
        let doubled = CGMutablePath()
        doubled.move(to: CGPoint(x: 8, y: 8))
        for point in [CGPoint(x: 40, y: 8), CGPoint(x: 40, y: 40), CGPoint(x: 8, y: 40), CGPoint(x: 8, y: 8),
                      CGPoint(x: 24, y: 24), CGPoint(x: 56, y: 24), CGPoint(x: 56, y: 56), CGPoint(x: 24, y: 56),
                      CGPoint(x: 24, y: 24), CGPoint(x: 8, y: 8)] { doubled.addLine(to: point) }
        doubled.closeSubpath()
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        let outer = CGPath(rect: CGRect(x: 8, y: 8, width: 48, height: 48), transform: nil)
        let holed = try XCTUnwrap(Selection(path: outer, bounds: outer.boundingBoxOfPath).composed(
            with: CGPath(rect: CGRect(x: 22, y: 22, width: 20, height: 20), transform: nil), by: .subtract, within: box))
        let cases: [(Selection, [CGPoint], [CGPoint])] = [
            (Selection(path: crossing, bounds: crossing.boundingBoxOfPath),
             [CGPoint(x: 28, y: 14), CGPoint(x: 28, y: 42)], [CGPoint(x: 10, y: 28), CGPoint(x: 54, y: 28)]),
            (Selection(path: doubled, bounds: doubled.boundingBoxOfPath),
             [CGPoint(x: 16, y: 16), CGPoint(x: 32, y: 32), CGPoint(x: 48, y: 48)], [CGPoint(x: 12, y: 52)]),
            (holed, [CGPoint(x: 14, y: 14), CGPoint(x: 50, y: 50)], [CGPoint(x: 32, y: 32), CGPoint(x: 2, y: 2)])
        ]
        for (selection, painted, bare) in cases {
            let manager = CanvasFixture.manager(layerCount: 0)
            manager.addVectorLayer()
            manager.selection = selection
            manager.brushColor = Self.red
            let before = try celBytes(manager, layer: 0)
            let steps = manager.history.undoStack.count
            manager.beginInteractiveFill(at: painted[0])
            manager.endInteractiveFill()
            spin { manager.liveFill?.render != nil }
            let preview = try XCTUnwrap(manager.liveFill?.preview)
            for point in painted { XCTAssertGreaterThan(alpha(preview, at: point), 200, "PREMISE: winding clip paints this interior") }
            for point in bare { XCTAssertEqual(alpha(preview, at: point), 0, "PREMISE: winding clip leaves this hole/exterior bare") }
            XCTAssertTrue(manager.commitInteractiveFill())
            let after = try celBytes(manager, layer: 0)
            for point in painted { XCTAssertEqual(sample(after, at: point), [255, 0, 0, 255], "native commit matches winding preview") }
            for point in bare { XCTAssertEqual(sample(after, at: point), [0, 0, 0, 0], "native commit preserves holes/exterior") }
            XCTAssertEqual(manager.layers[0].cels[0].vector?.fills.count, 1)
            XCTAssertNil(manager.layers[0].cels[0].bakedImage)
            XCTAssertEqual(manager.history.undoStack.count, steps + 1)
            manager.undo()
            XCTAssertEqual(try celBytes(manager, layer: 0), before)
            manager.redo()
            XCTAssertEqual(try celBytes(manager, layer: 0), after)
        }
    }

    @MainActor
    func testBucketSelectionOutsidePermissionStillAllowsUnclippedPaint() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        for vector in [false, true] {
            let manager = CanvasFixture.manager(layerCount: 0)
            if vector { manager.addVectorLayer() } else { manager.addLayer() }
            let region = CGRect(x: 24, y: 20, width: 24, height: 20)
            manager.selection = Selection(path: CGPath(rect: region, transform: nil), bounds: region)
            manager.allowsPaintingOutsideSelection = true
            manager.brushColor = Self.red
            manager.beginInteractiveFill(at: CGPoint(x: 28, y: 24))
            manager.endInteractiveFill()
            spin { manager.liveFill?.render != nil }
            let shown = try XCTUnwrap(manager.liveFill?.preview)
            XCTAssertNil(manager.liveFill?.clip)
            XCTAssertGreaterThan(alpha(shown, at: CGPoint(x: 56, y: 44)), 200)
            XCTAssertTrue(manager.commitInteractiveFill())
            XCTAssertEqual(sample(try celBytes(manager, layer: 0), at: CGPoint(x: 56, y: 44)), [255, 0, 0, 255])
        }
    }

    /// A rejected clip is never interpreted as permission to paint freely. A prior accepted render
    /// stays owned while the artist can recover the selection/pose and try the same draft again.
    @MainActor
    func testBucketRefusesAnUnmappableSelectionAndRetainsTheAcceptedDraft() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        // One loop has a vertex on the inverse horizon; the other crosses it only between
        // vertices. Both must refuse before a folded local polygon can paint outside the ants.
        for unavailable in [CGRect(x: 32, y: 8, width: 8, height: 8),
                            CGRect(x: 24, y: 8, width: 16, height: 8)] {
            let manager = CanvasFixture.manager(layerCount: 0)
            manager.addVectorLayer()
            manager.addTransformLayer()
            manager.currentLayerIndex = 0
            manager.brushColor = Self.red
            let region = CGRect(x: 8, y: 8, width: 8, height: 8)
            manager.selection = Selection(path: CGPath(rect: region, transform: nil), bounds: region)
            let before = try celBytes(manager, layer: 0)
            let steps = manager.history.undoStack.count
            manager.beginInteractiveFill(at: CGPoint(x: 10, y: 10))
            manager.endInteractiveFill()
            spin { manager.liveFill?.render != nil }
            let accepted = try XCTUnwrap(manager.liveFill?.render)
            let renders = try XCTUnwrap(manager.fillRenders)
            let count = renders.landedCount
            let map = Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: 1 / 32, h: 0, i: 1)
            manager.layers[1].transform = LayerPose(pose: try XCTUnwrap(PoseQuad(
                box: CGRect(origin: .zero, size: CanvasFixture.canvasSize), mappedThrough: map)), mode: .move)
            manager.selection = Selection(path: CGPath(rect: unavailable, transform: nil), bounds: unavailable)
            let pose = try XCTUnwrap(manager.inkPose(forLayerID: manager.layers[0].id))
            XCTAssertNil(CanvasManager.layerSpacePathIfInvertible(manager.selection!.path, shownThrough: pose), "PREMISE: clip meets the inverse horizon")
            let localOutside = CGPoint(x: 32, y: 24)
            let shownOutside = try XCTUnwrap(pose.applied(to: localOutside))
            XCTAssertFalse(unavailable.contains(shownOutside), "PREMISE: this local point is shown outside the selection")
            manager.setFillGapClosing(1)
            spin { renders.landedCount > count }
            XCTAssertTrue(manager.liveFill?.render === accepted, "a refused landing retains the accepted preview")
            XCTAssertFalse(manager.commitInteractiveFill(), "a required clip that cannot map refuses commit")
            XCTAssertNotNil(manager.liveFill)
            XCTAssertEqual(manager.history.undoStack.count, steps)
            let after = try celBytes(manager, layer: 0)
            XCTAssertEqual(after, before)
            XCTAssertEqual(sample(after, at: localOutside), [0, 0, 0, 0], "Refusal cannot paint a point shown outside the ants")
            XCTAssertEqual(manager.notice?.kind, .drawingSourceUnavailable)
            manager.cancelInteractiveFill()
        }
    }

    /// The source kind and gesture mode share the same displayed-frame lookup. A three-frame Repeat
    /// at frame 3 shows cel 0; frame 3 intentionally has no raw reference or destination cel.
    @MainActor
    func testRepeatedBucketAndLassoUseDisplayedReferenceAndDestinationCels() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        for vectorReference in [false, true] {
            for lasso in [false, true] {
                var first: [UInt8]?
                for frame in [0, 3] {
                    let manager = CanvasFixture.manager(layerCount: 0)
                    if vectorReference { manager.addVectorLayer() } else { manager.addLayer() }
                    CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 1)])
                    let ring = CGPath(rect: CGRect(x: 12, y: 12, width: 40, height: 40), transform: nil)
                        .subtracting(CGPath(rect: CGRect(x: 16, y: 16, width: 32, height: 32), transform: nil))
                    XCTAssertNotNil(manager.layDownSolidFill(ring, color: .black, layerIndex: 0, celIndex: 0, label: .fill))
                    manager.addVectorLayer()
                    CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 1)])
                    manager.layers[1].cels[0].vector = .empty(size: CanvasFixture.canvasSize)
                    manager.addTransformLayer()
                    CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 0, length: 12)])
                    manager.layers[2].transform = LayerPose(pose: PoseQuad(restingIn: CGRect(
                        origin: .zero, size: CanvasFixture.canvasSize)), mode: .repeat, repeatPeriod: 3)
                    manager.currentLayerIndex = 1
                    manager.currentFrame = frame
                    manager.brushColor = Self.red
                    manager.setFillGapClosing(0)
                    let sourceID = manager.layers[0].cels[0].id, destinationID = manager.layers[1].cels[0].id
                    let source = try celBytes(manager, layer: 0)
                    let before = try celBytes(manager, layer: 1)
                    let steps = manager.history.undoStack.count
                    XCTAssertEqual(manager.displayedFrame(forLayer: 1, atFrame: frame), 0)
                    XCTAssertEqual(manager.fillReferenceSources().first(where: { $0.layer.id == manager.layers[0].id })?.cel.id, sourceID)
                    if lasso {
                        manager.beginInteractiveLassoFill(path: CGPath(rect: CGRect(x: 6, y: 6, width: 52, height: 52), transform: nil))
                    } else { manager.beginInteractiveFill(at: CGPoint(x: 32, y: 32)) }
                    manager.endInteractiveFill()
                    spin { manager.liveFill?.render != nil }
                    let shown = try XCTUnwrap(manager.liveFill?.preview)
                    XCTAssertGreaterThan(alpha(shown, at: CGPoint(x: 32, y: 32)), 200)
                    XCTAssertEqual(alpha(shown, at: CGPoint(x: 2, y: 2)), 0, "the displayed ring bounds the actual fill")
                    XCTAssertTrue(manager.commitInteractiveFill())
                    let landed = try celBytes(manager, layer: 1)
                    XCTAssertEqual(sample(landed, at: CGPoint(x: 32, y: 32)), [255, 0, 0, 255])
                    XCTAssertEqual(sample(landed, at: CGPoint(x: 2, y: 2)), [0, 0, 0, 0])
                    if let first { XCTAssertEqual(landed, first, "frame 3 paints exactly what frame 0 paints") }
                    else { first = landed }
                    XCTAssertEqual(manager.layers[1].cels.map(\.id), [destinationID], "the displayed source cel owns the new fill")
                    XCTAssertEqual(try celBytes(manager, layer: 0), source, "reference content is untouched")
                    XCTAssertEqual(manager.history.undoStack.count, steps + 1)
                    manager.undo()
                    XCTAssertEqual(try celBytes(manager, layer: 1), before)
                    manager.redo()
                    XCTAssertEqual(try celBytes(manager, layer: 1), landed)
                    // Mend requests supply each owned cel's frame, independently of the playhead.
                    manager.currentFrame = 1
                    XCTAssertEqual(manager.fillReferenceSources(atFrame: 3).first?.cel.id, sourceID)
                    XCTAssertNil(manager.fillReferenceSources().first(where: { $0.layer.id == manager.layers[0].id }))
                    manager.layers[0].fillReferenceOverride = false
                    XCTAssertNil(manager.fillReferenceSources(atFrame: 3).first(where: { $0.layer.id == manager.layers[0].id }), "the artist's reference override is preserved")
                }
            }
        }
    }

    @MainActor
    func testAcceptedSelectedFillSettlesAtItsOriginWhenTheTimelineChanges() throws {
        for result in try selectedFillSettledAtItsOrigin(waitForLanding: true) {
            XCTAssertEqual(result.interior, [255, 0, 0, 255], "accepted fill retains its origin's selected interior")
            XCTAssertEqual(result.exterior, [0, 0, 0, 0], "the incoming pose cannot expand an accepted fill")
            XCTAssertEqual(result.sourceExterior, [0, 0, 0, 0], "Repeat keeps the outer parent's document time")
        }
    }

    @MainActor
    func testSelectedFillBeforeItsFirstLandingSettlesAtItsOriginWhenTheTimelineChanges() throws {
        for result in try selectedFillSettledAtItsOrigin(waitForLanding: false) {
            XCTAssertEqual(result.interior, [255, 0, 0, 255], "a queued fill retains its origin's selected interior")
            XCTAssertEqual(result.exterior, [0, 0, 0, 0], "the incoming pose cannot expand a queued fill")
            XCTAssertEqual(result.sourceExterior, [0, 0, 0, 0], "a queued Repeat fill keeps document time")
        }
    }

    /// The source cel is held across both frames, so its identity cannot recover the origin's
    /// pose. Above Repeat, that origin is document3 rather than its source0. The live GPU result
    /// and its eventual commit must both mean the same red rectangle in the stored drawing.
    @MainActor
    private func selectedFillSettledAtItsOrigin(waitForLanding: Bool) throws
        -> [(interior: [UInt8], exterior: [UInt8], sourceExterior: [UInt8])] {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        var results: [(interior: [UInt8], exterior: [UInt8], sourceExterior: [UInt8])] = []
        for vector in [false, true] {
            for repeated in [false, true] {
                let manager = CanvasFixture.manager(layerCount: 0)
                if vector { manager.addVectorLayer() } else { manager.addLayer() }
                CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2)])
                let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
                if repeated {
                    manager.addTransformLayer(name: "Repeat")
                    CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 12)])
                    manager.layers[1].transform = LayerPose(pose: PoseQuad(restingIn: box),
                                                            mode: .repeat, repeatPeriod: 3)
                }
                manager.addTransformLayer(name: "Animated parent")
                let parent = manager.currentLayerIndex
                CanvasFixture.setCelLayout(manager, layerIndex: parent, [(start: 0, length: 12)])
                let origin = repeated ? 3 : 0
                let poses: [(Int, PoseQuad)] = (repeated ? [(0, CGFloat(-8))] : [])
                    .map { ($0.0, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: $0.1, y: 0))) }
                    + [(origin, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 4, y: 0))),
                       (origin + 1, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 16, y: 0)))]
                manager.layers[parent].transform = LayerPose(pose: PoseQuad(restingIn: box),
                    track: CanvasFixture.poseTrack(poses, interpolation: .linear))
                manager.currentLayerIndex = 0
                manager.currentFrame = origin
                let region = CGRect(x: 24, y: 20, width: 16, height: 20)
                manager.selection = Selection(path: CGPath(rect: region, transform: nil), bounds: region)
                manager.brushColor = Self.red
                manager.setFillCanvasEdgeIsBoundary(false)
                manager.setFillGapClosing(0)
                let target = manager.layers[0].cels[0].id
                let before = try celBytes(manager, layer: 0)
                manager.history.removeAll()
                manager.beginInteractiveFill(at: CGPoint(x: 28, y: 24))
                manager.endInteractiveFill()
                if waitForLanding {
                    spin { manager.liveFill?.render != nil }
                    let preview = try XCTUnwrap(manager.liveFill?.preview)
                    XCTAssertGreaterThan(alpha(preview, at: CGPoint(x: 28, y: 24)), 200,
                                         "PREMISE: the accepted origin preview paints this stored point")
                    XCTAssertEqual(alpha(preview, at: CGPoint(x: 12, y: 24)), 0,
                                   "PREMISE: the accepted origin preview leaves this stored point clear")
                } else {
                    XCTAssertNil(manager.liveFill?.render, "PREMISE: no main-thread landing has run")
                }
                XCTAssertEqual(try celBytes(manager, layer: 0), before, "the fill is still off the document")
                manager.goToFrame(origin + 1) // The same entry the timeline's scrub calls.
                XCTAssertEqual(manager.currentFrame, origin + 1)
                XCTAssertFalse(manager.fillGestureActive, "the outgoing draft is settled before the new frame is used")
                let landed = try celBytes(manager, layer: 0)
                results.append((sample(landed, at: CGPoint(x: 28, y: 24)),
                                sample(landed, at: CGPoint(x: 12, y: 24)),
                                sample(landed, at: CGPoint(x: 44, y: 24))))
                XCTAssertEqual(manager.layers[0].cels.map(\.id), [target], "the held source cel owns the committed fill")
                XCTAssertEqual(manager.history.undoStack.count, 1)
                manager.undo()
                XCTAssertTrue(try celBytes(manager, layer: 0) == before, "Undo restores the exact pre-fill drawing")
                manager.redo()
                XCTAssertTrue(try celBytes(manager, layer: 0) == landed, "Redo restores the exact origin-clipped fill")
            }
        }
        return results
    }

    private func celBytes(_ manager: CanvasManager, layer: Int) throws -> [UInt8] {
        let image = try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[layer].cels[0], canvasSize: CanvasFixture.canvasSize)?.cgImage)
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    private func sample(_ bytes: [UInt8], at point: CGPoint) -> [UInt8] {
        let offset = (Int(point.y) * Int(CanvasFixture.canvasSize.width) + Int(point.x)) * 4
        return Array(bytes[offset..<(offset + 4)])
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
