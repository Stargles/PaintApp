import XCTest
import UIKit

/// Tests for picking a timeline block up and putting it down somewhere else —
/// `CanvasManager+BlockDrag.swift`.
///
/// The gesture that drives these lives in `TimelineTrackView` and resolves a finger position into
/// one of three outcomes (re-time, shuffle, re-home). Everything it can decide is decided by the
/// four entry points pinned here, so the view layer holds no rules of its own:
///
///   * `celInsertionIndex` / `celOrderIndex` — which of the three a drop means;
///   * `shuffleCel` — reorder within a layer, preserving lengths and the run's timing;
///   * `celDropVerdict` — whether a cross-layer drop is allowed, costly, or refused;
///   * `moveCelToLayer` — the move itself, including the rasterization and the reference fix-up.
///
/// See `CanvasManagerTestSupport.swift` for why these compile as plain unit tests inside the UI
/// test target.
final class BlockDragCharacterizationTests: XCTestCase {

    // MARK: - Fixtures

    /// A raster layer with `blocks` laid out on it.
    private func manager(blocks: [(start: Int, length: Int)]) -> CanvasManager {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, blocks)
        return manager
    }

    private func celIndex(_ manager: CanvasManager, layerIndex: Int = 0, startingAt start: Int) -> Int {
        manager.layers[layerIndex].cels.firstIndex { $0.startFrame == start } ?? -1
    }

    // MARK: - Which outcome a drop means

    /// The order flips at the *midpoint* of the neighbour, not at its leading edge — dragging a
    /// block one frame past another must not already count as trading places with it, or every
    /// small re-timing nudge near a boundary would reorder the animation.
    func testABlockTradesPlacesOnlyOnceItPassesTheNeighboursMidpoint() {
        let manager = self.manager(blocks: [(start: 0, length: 4), (start: 4, length: 4)])
        let dragged = celIndex(manager, startingAt: 4)

        XCTAssertEqual(manager.celOrderIndex(layerIndex: 0, celIndex: dragged), 1)
        XCTAssertEqual(manager.celInsertionIndex(layerIndex: 0, celIndex: dragged, startFrame: 3), 1,
                       "Still past the first block's midpoint (frame 2), so still second")
        XCTAssertEqual(manager.celInsertionIndex(layerIndex: 0, celIndex: dragged, startFrame: 1), 0,
                       "Dragged back over the midpoint — now first")
    }

    func testAReTimeInsideItsOwnSlotDoesNotChangeTheOrder() {
        let manager = self.manager(blocks: [(start: 0, length: 2), (start: 6, length: 2)])
        let dragged = celIndex(manager, startingAt: 6)

        XCTAssertEqual(manager.celInsertionIndex(layerIndex: 0, celIndex: dragged, startFrame: 4),
                       manager.celOrderIndex(layerIndex: 0, celIndex: dragged),
                       "Moved earlier but still after block one — a re-time, not a shuffle")
    }

    // MARK: - Shuffle within a layer

    func testShufflingSwapsTwoAdjacentBlocksKeepingTheirLengths() {
        let manager = self.manager(blocks: [(start: 0, length: 2), (start: 2, length: 5)])
        let first = manager.layers[0].cels[celIndex(manager, startingAt: 0)].id
        let second = manager.layers[0].cels[celIndex(manager, startingAt: 2)].id

        manager.shuffleCel(layerIndex: 0, celIndex: celIndex(manager, startingAt: 2), toOrderIndex: 0)

        // The five-frame block now plays first, and the run still starts at frame 0.
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 5])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [5, 2])
        XCTAssertEqual(manager.layers[0].cels.first { $0.startFrame == 0 }?.id, second)
        XCTAssertEqual(manager.layers[0].cels.first { $0.startFrame == 5 }?.id, first)
        assertNoOverlappingCels(manager)
    }

    /// The gaps belong to the *sequence*, not to the blocks: gap 0 stays the gap after whichever
    /// block is first. That is what keeps the timing an artist spaced out intact while the drawings
    /// change places.
    func testShufflingKeepsTheGapsWhereTheyWereInTheSequence() {
        let manager = self.manager(blocks: [(start: 0, length: 2), (start: 5, length: 1), (start: 8, length: 2)])

        // Move the last block to the front.
        manager.shuffleCel(layerIndex: 0, celIndex: celIndex(manager, startingAt: 8), toOrderIndex: 0)

        // Lengths in the new order are 2, 2, 1; the gaps after positions 0 and 1 stay 3 and 2.
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [2, 2, 1])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 5, 9])
        assertNoOverlappingCels(manager)
    }

    func testShufflingNeverDriftsTheRunInTime() {
        let manager = self.manager(blocks: [(start: 3, length: 2), (start: 5, length: 3)])

        manager.shuffleCel(layerIndex: 0, celIndex: celIndex(manager, startingAt: 5), toOrderIndex: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start).first, 3,
                       "The run still begins where it began, not at frame 0")
    }

    func testShufflingIsOneUndoStep() {
        let manager = self.manager(blocks: [(start: 0, length: 2), (start: 2, length: 5)])

        manager.shuffleCel(layerIndex: 0, celIndex: celIndex(manager, startingAt: 2), toOrderIndex: 0)
        manager.undo()

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 2])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [2, 5])
    }

    func testShufflingASoleBlockIsANoOp() {
        let manager = self.manager(blocks: [(start: 4, length: 3)])

        manager.shuffleCel(layerIndex: 0, celIndex: 0, toOrderIndex: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [4])
    }

    // MARK: - Drop verdicts

    /// Two layers, each holding **two** blocks. Two and not one on purpose: a layer down to its last
    /// block refuses to give it up at all (`testALayersLastBlockCannotLeaveIt`), and that rule is
    /// checked before the kind rules — so a one-block fixture would make the vector/raster tests
    /// pass for entirely the wrong reason.
    ///
    /// `setCelLayout` builds raster-only cels, so a vector layer's blocks have their `VectorCanvas`
    /// put back afterwards — without it the "vector block" under test would not be one.
    private func twoLayerManager(secondIsVector: Bool) -> CanvasManager {
        let manager = CanvasFixture.manager()
        if secondIsVector { manager.addVectorLayer() } else { manager.addLayer() }
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2), (start: 4, length: 2)])
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 2), (start: 9, length: 1)])
        if secondIsVector {
            let size = manager.canvasSize ?? CanvasFixture.canvasSize
            for index in manager.layers[1].cels.indices { manager.layers[1].cels[index].vector = .empty(size: size) }
        }
        return manager
    }

    func testARasterBlockIsRefusedByAVectorLayer() {
        let manager = twoLayerManager(secondIsVector: true)
        let cel = manager.layers[0].cels[0]

        let verdict = manager.celDropVerdict(celID: cel.id,
                                             fromLayer: manager.layers[0].id,
                                             toLayer: manager.layers[1].id)

        guard case .rejected = verdict else { return XCTFail("Expected a refusal, got \(verdict)") }
        XCTAssertFalse(manager.moveCelToLayer(celID: cel.id, fromLayer: manager.layers[0].id,
                                              toLayer: manager.layers[1].id, startFrame: 0),
                       "…and the move itself refuses too, not just the verdict")
        XCTAssertEqual(manager.layers[0].cels.count, 2, "Nothing left the source layer")
    }

    func testAVectorBlockOntoARasterLayerAsksBeforeItRasterizes() {
        let manager = twoLayerManager(secondIsVector: true)
        let vectorCel = manager.layers[1].cels[0]

        let verdict = manager.celDropVerdict(celID: vectorCel.id,
                                             fromLayer: manager.layers[1].id,
                                             toLayer: manager.layers[0].id)

        XCTAssertEqual(verdict, .needsRasterization)
        XCTAssertFalse(manager.moveCelToLayer(celID: vectorCel.id, fromLayer: manager.layers[1].id,
                                              toLayer: manager.layers[0].id, startFrame: 8),
                       "Without `rasterizing: true` the model refuses — a confirmation can't be skipped")
    }

    /// A layer stripped of its last block is undrawable, so the drop is refused rather than
    /// silently leaving one behind or emptying the layer.
    func testALayersLastBlockCannotLeaveIt() {
        let manager = twoLayerManager(secondIsVector: false)
        manager.layers[1].cels = Array(manager.layers[1].cels.prefix(1))
        let sole = manager.layers[1].cels[0]

        let verdict = manager.celDropVerdict(celID: sole.id,
                                             fromLayer: manager.layers[1].id,
                                             toLayer: manager.layers[0].id)

        guard case .rejected = verdict else { return XCTFail("Expected a refusal, got \(verdict)") }
    }

    // MARK: - Moving between layers

    func testAnAllowedMoveLandsOnTheTargetLayerAndLeavesTheSource() {
        let manager = twoLayerManager(secondIsVector: false)
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 2), (start: 9, length: 1)])
        let moving = manager.layers[1].cels.first { $0.startFrame == 9 }!
        let sourceID = manager.layers[1].id
        let targetID = manager.layers[0].id

        XCTAssertTrue(manager.moveCelToLayer(celID: moving.id, fromLayer: sourceID,
                                             toLayer: targetID, startFrame: 7))

        XCTAssertFalse(manager.layers[1].cels.contains { $0.id == moving.id }, "Gone from the source")
        XCTAssertEqual(manager.layers[0].cels.first { $0.id == moving.id }?.startFrame, 7)
        assertNoOverlappingCels(manager, layerIndex: 0)
    }

    /// A drop onto occupied frames pushes what was there along rather than overwriting it or
    /// landing on top of it — a block dropped on a layer adds content, it never destroys any.
    func testADropOntoOccupiedFramesPushesTheExistingBlocksLater() {
        let manager = twoLayerManager(secondIsVector: false)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2), (start: 2, length: 2)])
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 2), (start: 9, length: 3)])
        let moving = manager.layers[1].cels.first { $0.startFrame == 9 }!

        XCTAssertTrue(manager.moveCelToLayer(celID: moving.id, fromLayer: manager.layers[1].id,
                                             toLayer: manager.layers[0].id, startFrame: 0))

        XCTAssertEqual(manager.layers[0].cels.count, 3)
        assertNoOverlappingCels(manager, layerIndex: 0)
        XCTAssertEqual(CanvasFixture.celLayout(manager, layerIndex: 0).map(\.length).reduce(0, +), 7,
                       "Every block survived at its own length")
    }

    func testRasterizingOnTheWayInFlattensTheGeometryIntoTheRasterTier() {
        let manager = twoLayerManager(secondIsVector: true)
        let vectorCel = manager.layers[1].cels[0]

        XCTAssertTrue(manager.moveCelToLayer(celID: vectorCel.id, fromLayer: manager.layers[1].id,
                                             toLayer: manager.layers[0].id, startFrame: 8,
                                             rasterizing: true))

        guard let landed = manager.layers[0].cels.first(where: { $0.id == vectorCel.id }) else {
            return XCTFail("The block did not land")
        }
        XCTAssertNil(landed.vector, "A raster layer's cel must not still carry vector geometry")
        XCTAssertNil(landed.bakedImage, "…and holds its content in exactly one tier at rest")
        XCTAssertNil(landed.fillImage)
    }

    /// Recipes address a keyframe as (layer, cel). A block that changes layers has to take every
    /// reference to it along, or the in-betweens it feeds quietly stop resolving.
    func testMovingABlockRetargetsEveryInterpolationReferenceToIt() {
        let manager = twoLayerManager(secondIsVector: false)
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 2), (start: 9, length: 1)])
        let moving = manager.layers[1].cels.first { $0.startFrame == 9 }!
        let sourceLayerID = manager.layers[1].id
        let targetLayerID = manager.layers[0].id
        let other = manager.layers[1].cels.first { $0.startFrame == 0 }!

        // A recipe elsewhere in the document that reads the block about to move.
        manager.layers[0].cels[0].interpolation = InterpolationRecipe(
            references: [InterpolationReference(layerID: sourceLayerID, celID: other.id),
                         InterpolationReference(layerID: sourceLayerID, celID: moving.id)],
            t: 0.5)

        XCTAssertTrue(manager.moveCelToLayer(celID: moving.id, fromLayer: sourceLayerID,
                                             toLayer: targetLayerID, startFrame: 7))

        let refs = manager.layers[0].cels[0].interpolation?.referencedCels ?? []
        XCTAssertTrue(refs.contains(CelRef(layerID: targetLayerID, celID: moving.id)),
                      "The reference follows the block onto its new layer")
        XCTAssertFalse(refs.contains(CelRef(layerID: sourceLayerID, celID: moving.id)),
                       "…and the stale one is gone")
        XCTAssertTrue(refs.contains(CelRef(layerID: sourceLayerID, celID: other.id)),
                      "References to blocks that did not move are untouched")
    }

    func testMovingBetweenLayersIsOneUndoStep() {
        let manager = twoLayerManager(secondIsVector: false)
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 2), (start: 9, length: 1)])
        let moving = manager.layers[1].cels.first { $0.startFrame == 9 }!

        XCTAssertTrue(manager.moveCelToLayer(celID: moving.id, fromLayer: manager.layers[1].id,
                                             toLayer: manager.layers[0].id, startFrame: 7))
        manager.undo()

        XCTAssertTrue(manager.layers[1].cels.contains { $0.id == moving.id }, "Back on its own layer")
        XCTAssertEqual(manager.layers[1].cels.first { $0.id == moving.id }?.startFrame, 9,
                       "…at the frame it started on")
        XCTAssertFalse(manager.layers[0].cels.contains { $0.id == moving.id })
    }
}
