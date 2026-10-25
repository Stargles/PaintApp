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

    /// Draws the loop and returns how deep the history is with it drawn — the loop is a step of its own
    /// (TODO (187)), so what a verb added is counted from here.
    @discardableResult
    private func select(_ manager: CanvasManager, _ rect: CGRect) -> Int {
        manager.finishSelection(path: CGPath(rect: rect, transform: nil))
        return manager.history.undoStack.count
    }

    private let aroundLeft = CGRect(x: 2, y: 24, width: 28, height: 16)

    // MARK: - The vector arm

    /// **The lassoed stroke moves to a new vector layer above, the source keeps the other, and one
    /// press of Undo puts it all back.**
    func testTheLoopsInkMovesToANewLayerAboveAndOneUndoPutsItBack() throws {
        let (manager, source, vector, left, right) = vectorFixture()
        let baseline = select(manager, aroundLeft)
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
        XCTAssertEqual(manager.history.undoStack.count - baseline, 1, "one undo step for the whole verb")

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
        let baseline = select(manager, CGRect(x: 30, y: 2, width: 6, height: 6))
        manager.moveSelectionToNewLayer()
        XCTAssertEqual(manager.layers.count, layersBefore, "nothing to move, no layer")
        XCTAssertEqual(manager.history.undoStack.count - baseline, 0, "…and no step")
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
        manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
            CanvasFixture.solidImage(.red, rect: painted), size: size, strokeCount: 1)
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        let baseline = select(manager, aroundLeft)

        manager.moveSelectionToNewLayer()

        XCTAssertEqual(manager.layers.count, 2, "a layer was added")
        XCTAssertEqual(manager.currentLayerIndex, 1, "…above the source, and current")
        XCTAssertEqual(manager.layers[1].kind, .raster)
        XCTAssertNil(manager.floatingPiece, "nothing floats: both halves were on hand at once")
        XCTAssertEqual(manager.history.undoStack.count - baseline, 1, "one undo step for the whole verb")

        func alpha(_ layer: Int, at point: CGPoint) throws -> UInt8 {
            let image = try XCTUnwrap((try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[layer].cels[0],
                                                         canvasSize: size))).cgImage)
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
        manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
            CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 24, width: 64, height: 16)),
            size: size, strokeCount: 1)
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
        manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
            CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 24, width: 64, height: 16)),
            size: size, strokeCount: 1)
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
    /// Unsupported placed geometry and a below-bound composed inverse are separate refusals. Each
    /// runs through the actual command with healthy selection premises and the same state oracles.
    func testSelectionTransfersRefuseAnUnsupportedLocalPoseBeforePublishingAnyElement() throws {
        for copying in [true, false] {
          for belowInverseBound in [false, true] {
            let (manager, sourceIndex, vector, _, _) = vectorFixture()
            let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
            if belowInverseBound {
                let group = UUID()
                manager.animationGroups.append(AnimationGroup(id: group, displayName: "tiny local group",
                    tagColor: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)))
                vector.elements = vector.elements.map { $0.taggedForAnimation(group) }
                let reference = CGRect(x: 0, y: 0, width: 1024, height: 1024)
                let small = PoseQuad(box: reference, mappedBy: CGAffineTransform(scaleX: 0.001, y: 0.001))
                let track = CanvasFixture.poseTrack([(0, small)])
                manager.layers[sourceIndex].cels[0].transformTracks = [TransformChannelID.cel.id: track,
                                                                    TransformChannelID.group(group).id: track]
                let mappings = CanvasManager.poseMappings(manager.layers[sourceIndex].cels[0].transformTracks,
                                                          atCelLocalFrame: 0)
                XCTAssertEqual(mappings.count, 2, "PREMISE: both finite local channels are admitted")
                XCTAssertTrue(mappings.allSatisfy { $0.1.inverse != nil }, "PREMISE: each channel has a usable inverse")
                let composed = mappings.reduce(PoseMap.identity) { $0.concatenating($1.1) }
                XCTAssertNil(composed.inverse, "PREMISE: two determinant1e-6 maps compose below the existing1e-9 bound")
                XCTAssertTrue(manager.celPoseMaps(vector.elements, layerID: manager.layers[sourceIndex].id,
                    celID: manager.layers[sourceIndex].cels[0].id, atFrame: 0).isEmpty,
                    "PREMISE: the target's map filter omits this composition rather than refusing the target")
            } else {
                let image = VectorImageElement(image: CanvasFixture.solidImage(.red,
                    rect: CGRect(x: 0, y: 0, width: 8, height: 8)),
                    transform: LayerTransform(position: CGPoint(x: 32, y: 32), scale: 1, rotation: 0))
                vector.addImage(image)
                let pose = PoseQuad(box: box, corners: Quad(CGPoint(x: 8, y: 0), CGPoint(x: 56, y: 0),
                                                           CGPoint(x: 64, y: 64), CGPoint(x: 0, y: 64)))
                manager.layers[sourceIndex].cels[0].transformTracks = [TransformChannelID.cel.id:
                    CanvasFixture.poseTrack([(0, pose)])]
            }
            let loop = CGPath(rect: box, transform: nil)
            manager.selection = Selection(path: loop, bounds: box)
            manager.setSelectionMembership(.touching)
            XCTAssertEqual(vector.elementIDs(insideLocalPath: loop, membership: .touching).count,
                           vector.elements.count, "PREMISE: a full-window loop admits every stored element")
            let before = vector.elements.map(\.id)
            let version = vector.contentVersion
            let layers = manager.layers.map(\.id)
            let history = manager.history.currentCost
            if copying { manager.beginDuplicate() } else { manager.moveSelectionToNewLayer() }
            XCTAssertEqual(manager.layers.map(\.id), layers, "no prefix of the refused selection was published")
            XCTAssertEqual(vector.elements.map(\.id), before)
            XCTAssertEqual(vector.contentVersion, version)
            XCTAssertEqual(manager.currentLayerIndex, sourceIndex)
            XCTAssertEqual(manager.selection?.bounds, box)
            XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
            XCTAssertNil(manager.vectorFloat)
            XCTAssertEqual(manager.history.currentCost, history)
          }
        }
    }

    /// These public commands have no enclosing production owner. Their explicit refusal is before
    /// tool settlement, so unsupported capture cannot swallow either payload price or pending ink.
    func testSelectionTransfersLeaveAnOpenOwnerAndItsPendingShapeUntouched() throws {
        for copying in [true, false] {
            for owner in 0..<3 {
                let (manager, sourceIndex, vector, _, _) = vectorFixture()
                let loop = CGPath(rect: aroundLeft, transform: nil)
                manager.selection = Selection(path: loop, bounds: aroundLeft)
                let attempt = {
                    manager.beginInteractiveShape(ShapeGeometry(kind: .line,
                        startPoint: CGPoint(x: 8, y: 12), endPoint: CGPoint(x: 24, y: 12)),
                        samples: [VectorSample(x: 8, y: 12, pressure: 1), VectorSample(x: 24, y: 12, pressure: 1)])
                    manager.endInteractiveShape()
                    let version = vector.contentVersion
                    let ids = vector.elements.map(\.id)
                    let layers = manager.layers.map(\.id)
                    let steps = manager.history.undoStack.count
                    let cost = manager.history.currentCost
                    if copying { manager.beginDuplicate() } else { manager.moveSelectionToNewLayer() }
                    XCTAssertNotNil(manager.activeShape, "the refused transfer must not settle the earlier tool")
                    XCTAssertEqual(vector.elements.map(\.id), ids)
                    XCTAssertEqual(vector.contentVersion, version)
                    XCTAssertEqual(manager.layers.map(\.id), layers)
                    XCTAssertEqual(manager.currentLayerIndex, sourceIndex)
                    XCTAssertEqual(manager.selection?.bounds, self.aroundLeft)
                    XCTAssertNil(manager.vectorFloat)
                    XCTAssertEqual(manager.history.undoStack.count, steps)
                    XCTAssertEqual(manager.history.currentCost, cost)
                    manager.cancelInteractiveShape()
                }
                switch owner {
                case 0: manager.withStructureUndo(label: .moveToNewLayer) { attempt() }
                case 1: manager.withInterpolationUndo(label: .moveToNewLayer) { attempt() }
                default:
                    XCTAssertTrue(manager.beginStructureGesture(), "PREMISE: the capture is open")
                    attempt()
                    manager.cancelStructureGesture()
                }
            }
        }
    }

    /// Real clipped archives are new owners; an uncut copy shares the original heap archive. The
    /// action price, undo pixels and ordinary eviction are read from the actual transfer consumer.
    @MainActor
    func testSelectionTransfersPriceTheirActualFreshAndSharedArchivesAndEvictByThatPrice() throws {
        for copying in [true, false] {
            for cutting in [true, false] {
                let manager = CanvasFixture.manager(layerCount: 1)
                manager.addVectorLayer()
                let sourceIndex = manager.currentLayerIndex
                let vector = try XCTUnwrap(manager.layers[sourceIndex].cels[0].vector)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 4, y: 8))
                for tooth in 1...1024 {
                    path.addLine(to: CGPoint(x: 4 + CGFloat(tooth) * 56 / 1024,
                                            y: tooth.isMultiple(of: 2) ? 8 : 10))
                }
                path.addLine(to: CGPoint(x: 60, y: 56)); path.addLine(to: CGPoint(x: 4, y: 56))
                path.closeSubpath()
                let fill = VectorFillElement(path: path, color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
                vector.addFill(fill)
                let original = try XCTUnwrap(vector.render(quality: .full)?.cgImage)
                let originalBytes = try XCTUnwrap(CanvasFixture.rgbaBytes(original))
                let loop = CGPath(rect: CGRect(x: 0, y: 0, width: 32, height: 64), transform: nil)
                manager.selection = Selection(path: loop, bounds: loop.boundingBoxOfPath)
                manager.setSelectionMembership(cutting ? .cutting : .touching)
                manager.history.removeAll()
                // Keep a distinguishable earlier step until the transfer's actual price trims it.
                manager.recordUndo(label: .renameLayer, cost: 256, undo: {}, redo: {})
                if copying { manager.beginDuplicate() } else { manager.moveSelectionToNewLayer() }
                manager.commitVectorFloatIfNeeded()
                let destination = try XCTUnwrap(manager.layers[sourceIndex + 1].cels[0].vector)
                let inside = try XCTUnwrap(destination.fills.first)
                let slots = 2 * MemoryLayout<VectorElement>.stride
                var expected = 4096 + slots
                if cutting {
                    XCTAssertGreaterThan(inside.pathData.count, 4096, "PREMISE: the actual inside archive is heap-backed")
                    fill.pathData.withUnsafeBytes { before in inside.pathData.withUnsafeBytes { after in
                        XCTAssertNotEqual(before.baseAddress, after.baseAddress, "PREMISE: clipping made a fresh inside owner")
                    } }
                    expected += inside.pathData.count
                    if !copying {
                        let outside = try XCTUnwrap(vector.fills.first)
                        XCTAssertGreaterThan(outside.pathData.count, 4096, "PREMISE: the outside archive is also a real heap owner")
                        expected += fill.pathData.count + outside.pathData.count
                    }
                } else {
                    fill.pathData.withUnsafeBytes { before in inside.pathData.withUnsafeBytes { after in
                        XCTAssertEqual(before.baseAddress, after.baseAddress, "PREMISE: the uncut archive really is shared")
                    } }
                }
                XCTAssertEqual(manager.history.undoStack.last?.cost, expected,
                               "price actual retained archives across both lists, without recharging shared owners")
                let destinationBytes = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(destination.render()?.cgImage)))
                manager.undo()
                XCTAssertEqual(manager.layers.count, 2)
                XCTAssertTrue(try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)))
                    .elementsEqual(originalBytes), "one undo restores the source's real pixels")
                manager.redo()
                let redone = try XCTUnwrap(manager.layers[sourceIndex + 1].cels[0].vector)
                XCTAssertTrue(try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(redone.render()?.cgImage)))
                    .elementsEqual(destinationBytes), "redo retains the transferred picture")
                manager.history.maxCost = expected
                manager.recordUndo(label: .opacity, cost: 1, undo: {}, redo: {})
                XCTAssertEqual(manager.history.undoStack.count, 1,
                               "ordinary cost trimming must evict the retained transfer, not leave a cheap zombie step")
                XCTAssertEqual(manager.history.currentCost, 1)
            }
        }
    }

}
