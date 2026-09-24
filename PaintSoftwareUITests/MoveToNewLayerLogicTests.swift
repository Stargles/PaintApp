import XCTest
import CoreGraphics
import UIKit

/// **"To New Layer" beside Duplicate** — TODO (93), the owner: *"duplicate the selection, then erase
/// it, so that the stuff in the selection is put into another layer and removed from the original."*
///
/// Two arms, one rule: the loop's ink leaves this layer for a new one above it, in **one undo step**.
/// Every test reads both layers — what the new one holds *and* what the source lost — because a
/// Duplicate that forgot to erase would satisfy the first alone, and a Clear that forgot to copy
/// would satisfy the second. The undo count is the third operand: the insertion and the removal are
/// one press to take back, which is the whole of what the owner asked for over doing the two by hand.
final class MoveToNewLayerLogicTests: XCTestCase {

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// A raster layer at 0 and an **active vector layer at 1** holding two strokes, `left` and
    /// `right`, apart enough for a rectangle to catch one and not the other.
    private func vectorFixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas,
                                     left: UUID, right: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        vector.addStroke(stroke(from: CGPoint(x: 8, y: 32), to: CGPoint(x: 24, y: 32)))
        vector.addStroke(stroke(from: CGPoint(x: 40, y: 32), to: CGPoint(x: 56, y: 32)))
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return (manager, layerIndex, vector, vector.elements[0].id, vector.elements[1].id)
    }

    private func stroke(from a: CGPoint, to b: CGPoint) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: 4, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)])
    }

    private func select(_ manager: CanvasManager, _ rect: CGRect) {
        manager.finishSelection(path: CGPath(rect: rect, transform: nil))
    }

    private let aroundLeft = CGRect(x: 2, y: 24, width: 28, height: 16)

    // MARK: - The vector arm

    /// **The lassoed stroke moves to a new vector layer above, the source keeps the other, and one
    /// press of Undo puts it all back.**
    func testTheLoopsInkMovesToANewLayerAboveAndOneUndoPutsItBack() throws {
        let (manager, source, vector, left, right) = vectorFixture()
        select(manager, aroundLeft)
        let layersBefore = manager.layers.count

        manager.moveSelectionToNewLayer()

        XCTAssertEqual(manager.layers.count, layersBefore + 1, "a layer was added")
        XCTAssertEqual(manager.currentLayerIndex, source + 1, "…directly above the source, and current")
        let added = manager.layers[source + 1]
        XCTAssertEqual(added.kind, .vector, "a vector layer, since the ink is geometry")
        XCTAssertEqual(added.parentFolderID, manager.layers[source].parentFolderID,
                       "in the same container as the layer it came from")
        XCTAssertEqual(added.cels[0].vector?.elements.map(\.id), [left],
                       "the new layer holds exactly the lassoed stroke, under its own id")
        XCTAssertEqual(vector.elements.map(\.id), [right], "…and the source lost it and kept the other")
        XCTAssertNil(manager.selection, "the loop has nothing left to be about on the source")

        // The moved ink comes up in the Move box on its new layer, as Duplicate's copy does; putting
        // it down without a nudge records nothing, so the verb is one step.
        XCTAssertEqual(manager.vectorFloat?.parts[0].layerID, added.id, "the box holds the moved ink")
        manager.commitVectorFloatIfNeeded()
        XCTAssertEqual(manager.history.undoStack.count, 1, "one undo step for the whole verb")

        manager.undo()
        XCTAssertEqual(manager.layers.count, layersBefore, "undo removes the layer")
        XCTAssertEqual(vector.elements.map(\.id), [left, right], "…and gives the source its stroke back")
        XCTAssertEqual(manager.currentLayerIndex, source, "…with the source current again")

        manager.redo()
        XCTAssertEqual(manager.layers.count, layersBefore + 1, "redo re-inserts the layer")
        XCTAssertEqual(manager.layers[source + 1].cels[0].vector?.elements.map(\.id), [left])
        XCTAssertEqual(vector.elements.map(\.id), [right])
    }

    /// **Under Cut the stroke is bisected at the loop** — LASSO_MOVE.md §5.26, membership belongs to
    /// the selection and this is one more consumer of it. The inside half goes, the outside half
    /// stays, and the samples say which is which.
    func testUnderCutAStraddlingStrokeIsSplitAtTheLoop() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let source = manager.currentLayerIndex
        let vector = try XCTUnwrap(manager.layers[source].cels[0].vector)
        vector.addStroke(stroke(from: CGPoint(x: 8, y: 32), to: CGPoint(x: 56, y: 32)))
        XCTAssertEqual(manager.selectionMembership, .cutting, "PREMISE: Cut is the default rule")
        select(manager, CGRect(x: 2, y: 24, width: 30, height: 16))

        manager.moveSelectionToNewLayer()
        manager.commitVectorFloatIfNeeded()

        let moved = try XCTUnwrap(manager.layers[source + 1].cels[0].vector?.elements.first?.stroke)
        let stayed = try XCTUnwrap(vector.elements.first?.stroke)
        XCTAssertEqual(vector.elements.count, 1, "the source keeps one half")
        XCTAssertLessThanOrEqual(moved.samples.positions.map(\.x).max() ?? 0, 32.5,
                                 "the moved half lies inside the loop")
        XCTAssertGreaterThanOrEqual(stayed.samples.positions.map(\.x).min() ?? 0, 31.5,
                                    "the half left behind lies outside it")
    }

    /// **A loop that catches nothing does nothing** — no layer, no step, and under Enclosed the
    /// notice every other consumer raises (§5.24).
    func testALoopThatCatchesNothingAddsNoLayerAndNoStep() {
        let (manager, _, vector, left, right) = vectorFixture()
        let layersBefore = manager.layers.count
        select(manager, CGRect(x: 30, y: 2, width: 6, height: 6))
        manager.moveSelectionToNewLayer()
        XCTAssertEqual(manager.layers.count, layersBefore, "nothing to move, no layer")
        XCTAssertEqual(manager.history.undoStack.count, 0, "…and no step")
        XCTAssertEqual(vector.elements.map(\.id), [left, right], "…and the source untouched")
        XCTAssertNil(manager.vectorFloat)
    }

    // MARK: - The raster arm

    /// **On a pixel layer the pixels under the loop move to a new raster layer, and the source is
    /// cleared under the loop — one step.** Read back as bytes on both layers.
    func testOnARasterLayerThePixelsMoveAndTheSourceIsClearedInOneStep() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let size = CanvasFixture.canvasSize
        let painted = CGRect(x: 0, y: 24, width: 64, height: 16)
        manager.layers[0].cels[0].raster = RasterLayerTexture(
            size: size, image: CanvasFixture.solidImage(.red, rect: painted), strokeCount: 1)
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        select(manager, aroundLeft)

        manager.moveSelectionToNewLayer()

        XCTAssertEqual(manager.layers.count, 2, "a layer was added")
        XCTAssertEqual(manager.currentLayerIndex, 1, "…above the source, and current")
        XCTAssertEqual(manager.layers[1].kind, .raster)
        XCTAssertNil(manager.floatingPiece, "nothing floats: both halves were on hand at once")
        XCTAssertEqual(manager.history.undoStack.count, 1, "one undo step for the whole verb")

        func alpha(_ layer: Int, at point: CGPoint) throws -> UInt8 {
            let image = try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[layer].cels[0],
                                                         canvasSize: size).cgImage)
            let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(image))
            let scaleX = image.width / Int(size.width), scaleY = image.height / Int(size.height)
            let x = Int(point.x) * scaleX, y = Int(point.y) * scaleY
            return bytes[(y * image.width + x) * 4 + 3]
        }
        let inside = CGPoint(x: 16, y: 32), outside = CGPoint(x: 48, y: 32)
        XCTAssertGreaterThan(try alpha(1, at: inside), 200, "the new layer holds the pixels under the loop")
        XCTAssertEqual(try alpha(1, at: outside), 0, "…and nothing outside it")
        XCTAssertEqual(try alpha(0, at: inside), 0, "the source is cleared under the loop")
        XCTAssertGreaterThan(try alpha(0, at: outside), 200, "…and keeps what was outside")

        manager.undo()
        XCTAssertEqual(manager.layers.count, 1, "undo removes the layer")
        XCTAssertGreaterThan(try alpha(0, at: inside), 200, "…and gives the source its pixels back")
    }

    // MARK: - TODO (108): the new layer's cel matches the source cel it was lifted from

    /// **The owner's own example**: a source cel spanning frames 3–5 in a 12-frame scene — the new
    /// layer gets one cel at 3–5, not a cel spanning the whole scene (`newLayerBlockLength`'s old
    /// answer, right for a genuinely new layer and wrong here, where there is a source cel to match).
    func testNewLayersCelSpansExactlyTheSourceCelOnAVectorLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        XCTAssertEqual(manager.contentEndFrame, 12, "PREMISE: the default 12-frame scene")
        manager.splitCel(layerIndex: layerIndex, celIndex: 0, atFrame: 3)
        manager.splitCel(layerIndex: layerIndex, celIndex: 1, atFrame: 6)
        let spans = manager.layers[layerIndex].cels.map { ($0.startFrame, $0.frameCount) }
        XCTAssertEqual(spans.map(\.0), [0, 3, 6], "PREMISE: three cels")
        XCTAssertEqual(spans.map(\.1), [3, 3, 6], "PREMISE: the middle one spans exactly 3–5")

        manager.currentFrame = 4
        let sourceVector = try XCTUnwrap(manager.layers[layerIndex].cels[1].vector)
        sourceVector.addStroke(stroke(from: CGPoint(x: 8, y: 32), to: CGPoint(x: 24, y: 32)))
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        select(manager, aroundLeft)
        XCTAssertNotNil(manager.selection, "PREMISE: the loop caught the stroke")

        manager.moveSelectionToNewLayer()

        let added = manager.layers[layerIndex + 1]
        XCTAssertEqual(added.cels.count, 1, "one cel, and nothing elsewhere")
        XCTAssertEqual(added.cels[0].startFrame, 3, "starts where the source cel started")
        XCTAssertEqual(added.cels[0].frameCount, 3, "lasts exactly as long as the source cel — frames 3–5")
    }

    /// The raster arm's twin.
    func testNewLayersCelSpansExactlyTheSourceCelOnARasterLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let size = CanvasFixture.canvasSize
        manager.layers[0].cels[0].raster = RasterLayerTexture(
            size: size, image: CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 24, width: 64, height: 16)),
            strokeCount: 1)
        manager.splitCel(layerIndex: 0, celIndex: 0, atFrame: 3)
        manager.splitCel(layerIndex: 0, celIndex: 1, atFrame: 6)
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        manager.currentFrame = 4
        select(manager, aroundLeft)
        XCTAssertNotNil(manager.selection, "PREMISE: the loop caught the painted pixels")

        manager.moveSelectionToNewLayer()

        let added = manager.layers[1]
        XCTAssertEqual(added.cels.count, 1, "one cel, and nothing elsewhere")
        XCTAssertEqual(added.cels[0].startFrame, 3, "starts where the source cel started")
        XCTAssertEqual(added.cels[0].frameCount, 3, "lasts exactly as long as the source cel — frames 3–5")
    }

    // MARK: - Duplicate had the identical defect

    /// **Duplicate shared `moveSelectionToNewLayer`'s bug and got the same fix** — both arms.
    func testDuplicateOnAVectorLayerAlsoSpansExactlyTheSourceCel() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        manager.splitCel(layerIndex: layerIndex, celIndex: 0, atFrame: 3)
        manager.splitCel(layerIndex: layerIndex, celIndex: 1, atFrame: 6)
        manager.currentFrame = 4
        let sourceVector = try XCTUnwrap(manager.layers[layerIndex].cels[1].vector)
        sourceVector.addStroke(stroke(from: CGPoint(x: 8, y: 32), to: CGPoint(x: 24, y: 32)))
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        select(manager, aroundLeft)

        manager.beginDuplicate()

        let added = manager.layers[layerIndex + 1]
        XCTAssertEqual(added.cels.count, 1, "one cel, and nothing elsewhere")
        XCTAssertEqual(added.cels[0].startFrame, 3, "starts where the source cel started")
        XCTAssertEqual(added.cels[0].frameCount, 3, "lasts exactly as long as the source cel — frames 3–5")
    }

    /// The raster arm's twin.
    func testDuplicateOnARasterLayerAlsoSpansExactlyTheSourceCel() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let size = CanvasFixture.canvasSize
        manager.layers[0].cels[0].raster = RasterLayerTexture(
            size: size, image: CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 24, width: 64, height: 16)),
            strokeCount: 1)
        manager.splitCel(layerIndex: 0, celIndex: 0, atFrame: 3)
        manager.splitCel(layerIndex: 0, celIndex: 1, atFrame: 6)
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        manager.currentFrame = 4
        select(manager, aroundLeft)

        manager.beginDuplicate()

        let added = manager.layers[1]
        XCTAssertEqual(added.cels.count, 1, "one cel, and nothing elsewhere")
        XCTAssertEqual(added.cels[0].startFrame, 3, "starts where the source cel started")
        XCTAssertEqual(added.cels[0].frameCount, 3, "lasts exactly as long as the source cel — frames 3–5")
    }
}
