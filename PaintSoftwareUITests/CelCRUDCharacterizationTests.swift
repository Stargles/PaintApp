import XCTest
import UIKit

/// Characterization tests for the three cel-creating operations in `CanvasManager` —
/// `addCel`, `duplicateCel`, `pasteCel` — and specifically for the frame-length clamp all three
/// carry as an identical, copy-pasted block:
///
/// ```swift
/// let laterStarts = layers[layerIndex].cels.map(\.startFrame).filter { $0 > startFrame }
/// if let nextStart = laterStarts.min() { length = min(length, nextStart - startFrame) }
/// guard length > 0 else { return }
/// ```
///
/// A later refactor stage wants to dedup that into one helper. These tests pin the exact edge
/// behavior of each of the three call sites — at the boundary, one frame short of it, one frame
/// past it, and the degenerate cases — so the dedup is provably behavior-preserving rather than
/// merely plausible.
///
/// One asymmetry was originally pinned as-is rather than fixed at Stage 0: `addCel` and `pasteCel`
/// both guard on `activeCelIndex(...) == nil` before clamping, and the clamp's filter was a strict
/// `filter { $0 > startFrame }`, so `duplicateCel` — whose start frame is the source cel's
/// `endFrame` — did not see a neighbour that begins *exactly* there and could create an overlapping
/// cel. Stage 4.3 fixed that by relaxing the shared clamp to `>=`; the test that pinned the bug was
/// replaced by `testDuplicatingIntoAnImmediatelyAdjacentNeighbourIsANoOpRatherThanOverlappingIt`,
/// which pins the fix. Every other test in this file still pins existing behavior unchanged.
///
/// See `CanvasManagerTestSupport.swift` for why these compile as plain unit tests inside the UI
/// test target.
final class CelCRUDCharacterizationTests: XCTestCase {

    // MARK: - addCel

    func testAddCelExactlyFillingTheGapKeepsTheRequestedLength() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 10, length: 2)])

        // Gap is frames 5..<10, i.e. exactly 5 free. Asking for exactly 5 must not be clamped.
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 5, frameCount: 5))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 5, 10])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 5, 2])
        assertNoOverlappingCels(manager)
    }

    func testAddCelOneFrameShortOfTheGapLeavesAOneFrameHole() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 10, length: 2)])

        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 5, frameCount: 4))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 4, 2],
                       "A request that fits should be honoured verbatim, hole and all — the clamp is an upper bound, not a fit-to-gap")
        assertNoOverlappingCels(manager)
    }

    func testAddCelOneFramePastTheGapIsClampedToTheGap() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 10, length: 2)])

        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 5, frameCount: 6))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 5, 2],
                       "6 frames requested into a 5-frame gap should clamp to 5, not overlap the cel at frame 10")
        assertNoOverlappingCels(manager)
    }

    func testAddCelFarPastTheGapIsStillClampedToTheGap() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 10, length: 2)])

        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 5, frameCount: 500))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 5, 2])
        assertNoOverlappingCels(manager)
    }

    func testAddCelWithNoLaterCelIsNotClampedAtAll() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])

        // Nothing after frame 5, so `laterStarts` is empty and the requested length stands —
        // extending the scene past its previous 12-frame length.
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 5, frameCount: 40))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 40])
        XCTAssertEqual(manager.sceneFrameCount, 45, "sceneFrameCount grows to cover the new cel")
    }

    func testAddCelWithZeroLengthIsRejected() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 10, length: 2)])

        // The `guard length > 0` arm. Note it is only reachable via a non-positive *request*: the
        // clamp itself can never drive length to 0, because `filter { $0 > startFrame }` means
        // `nextStart - startFrame` is always at least 1.
        XCTAssertFalse(manager.addCel(layerIndex: 0, startFrame: 5, frameCount: 0))
        XCTAssertFalse(manager.addCel(layerIndex: 0, startFrame: 5, frameCount: -3))

        XCTAssertEqual(CanvasFixture.celLayout(manager).count, 2, "A rejected add must leave the timeline untouched")
    }

    func testAddCelOntoAFrameAlreadyCoveredIsRejectedBeforeClamping() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 10, length: 2)])

        XCTAssertFalse(manager.addCel(layerIndex: 0, startFrame: 0, frameCount: 1))
        XCTAssertFalse(manager.addCel(layerIndex: 0, startFrame: 2, frameCount: 1), "Last frame of the first cel is still covered")
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 3, frameCount: 1), "First free frame after it is not")

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 3, 10])
    }

    func testAddCelOnAnOutOfRangeLayerIsRejected() {
        let manager = CanvasFixture.manager()
        XCTAssertFalse(manager.addCel(layerIndex: 7, startFrame: 0, frameCount: 1))
        XCTAssertFalse(manager.addCel(layerIndex: -1, startFrame: 0, frameCount: 1))
    }

    // MARK: - duplicateCel

    func testDuplicateCelExactlyFillingTheGapKeepsTheSourceLength() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 6, length: 2)])

        // Copy lands at the source's endFrame (3) and wants the source's length (3); the gap
        // 3..<6 is exactly 3 frames.
        manager.duplicateCel(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 3, 6])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 3, 2])
        assertNoOverlappingCels(manager)
    }

    func testDuplicateCelOneFrameShortOfTheGapLeavesAOneFrameHole() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2), (start: 5, length: 2)])

        manager.duplicateCel(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 2, 5])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [2, 2, 2], "Copy is 2 long in a 3-frame gap; frame 4 stays empty")
        assertNoOverlappingCels(manager)
    }

    func testDuplicateCelOneFramePastTheGapIsClampedToTheGap() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 4), (start: 7, length: 2)])

        // Copy starts at 4 wanting 4 frames, but only 4..<7 is free.
        manager.duplicateCel(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 4, 7])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [4, 3, 2])
        assertNoOverlappingCels(manager)
    }

    /// The one place the three clamps genuinely diverge, pinned as-is.
    ///
    /// **Supersedes `testDuplicatingIntoAnImmediatelyAdjacentNeighbourOverlapsIt`**, which pinned the
    /// *bug* this now pins the *fix* for (Stage 4.3; see BUGS.md).
    ///
    /// `duplicateCel`'s start frame is the source cel's `endFrame`. The shared clamp's filter used to
    /// be a strict `filter { $0 > startFrame }`, which made a neighbour beginning at exactly that
    /// frame invisible to it — and unlike `addCel`/`pasteCel` there is no `activeCelIndex(...) == nil`
    /// guard in front to reject the position outright. So nothing bounded the copy and two cels ended
    /// up covering the same frames, which `activeCelIndex` (a `firstIndex(where:)`) resolves
    /// arbitrarily: the layer draws into one and renders the other.
    ///
    /// This is reachable from the UI: "attach a new block to the end" (`addBlankCelAfter`) produces
    /// exactly this adjacency, and Duplicate is then available on the earlier block.
    ///
    /// The clamp is now `>=`, so this adjacency leaves zero free frames and Duplicate is a no-op.
    /// Accepting the no-op is the deliberate choice: with a neighbour starting exactly at the
    /// source's end frame, every fix that cannot overlap collapses to the same thing. The
    /// alternatives that aren't a no-op (place the copy at the next free run, shift later cels
    /// rightward) are timeline feature design, not a refactor. The no-op being *silent* is logged in
    /// BUGS.md as a low-priority UI follow-up.
    func testDuplicatingIntoAnImmediatelyAdjacentNeighbourIsANoOpRatherThanOverlappingIt() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 2)])

        manager.duplicateCel(layerIndex: 0, celIndex: 0)

        let layout = CanvasFixture.celLayout(manager)
        XCTAssertEqual(layout.count, 2, "There is no free frame at the source's end frame, so no cel should be created")
        XCTAssertEqual(layout.map(\.start), [0, 3], "The existing layout must be left exactly as it was")
        XCTAssertEqual(layout.map(\.length), [3, 2], "Neither the source nor the neighbour should be resized to make room")
        assertNoOverlappingCels(manager)
    }

    /// The partial-room counterpart of the above: a *gap* before the neighbour still duplicates, and
    /// the copy is clamped to exactly the free frames. This is what makes the `>=` clamp a real fix
    /// rather than a blanket refusal to duplicate near a neighbour.
    func testDuplicatingIntoAPartialGapClampsTheCopyToTheFreeFrames() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 4, length: 2)])

        manager.duplicateCel(layerIndex: 0, celIndex: 0)

        let layout = CanvasFixture.celLayout(manager)
        XCTAssertEqual(layout.map(\.start), [0, 3, 4], "The copy should land in the one free frame at 3")
        XCTAssertEqual(layout.map(\.length), [3, 1, 2],
                       "The copy is clamped from the source's 3 frames down to the 1 frame actually free")
        assertNoOverlappingCels(manager)
    }

    func testDuplicateCelWithNoLaterCelIsNotClamped() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 5)])

        manager.duplicateCel(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 5])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [5, 5])
        XCTAssertEqual(manager.sceneFrameCount, 12, "Scene was already long enough; it should not shrink or grow")
    }

    func testDuplicateCelCopiesContentRatherThanSharingIt() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])
        let sourceRaster = manager.layers[0].cels[0].raster

        manager.duplicateCel(layerIndex: 0, celIndex: 0)

        let copyRaster = manager.layers[0].cels[1].raster
        XCTAssertFalse(copyRaster === sourceRaster,
                       "`RasterLayerTexture` is a class; the copy must be a `makeCopy()`, or drawing on one cel would paint into the other")
    }

    func testDuplicateCelOnAnOutOfRangeIndexIsANoOp() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])

        manager.duplicateCel(layerIndex: 0, celIndex: 9)
        manager.duplicateCel(layerIndex: 5, celIndex: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).count, 1)
    }

    // MARK: - pasteCel

    /// Copy from a scratch layer so the clipboard's `frameCount` is independent of the layer being
    /// pasted into, which is what makes the paste clamp observable on its own.
    private func manageWithClipboard(sourceLength: Int,
                                     target: [(start: Int, length: Int)]) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: sourceLength)])
        manager.copyCel(layerIndex: 1, celIndex: 0)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, target)
        return manager
    }

    func testPasteCelExactlyFillingTheGapKeepsTheCopiedLength() {
        let manager = manageWithClipboard(sourceLength: 3, target: [(start: 0, length: 3), (start: 10, length: 2)])

        XCTAssertTrue(manager.pasteCel(layerIndex: 0, startFrame: 7))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 7, 10])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 3, 2])
        assertNoOverlappingCels(manager)
    }

    func testPasteCelOneFrameShortOfTheGapLeavesAOneFrameHole() {
        let manager = manageWithClipboard(sourceLength: 3, target: [(start: 0, length: 3), (start: 10, length: 2)])

        XCTAssertTrue(manager.pasteCel(layerIndex: 0, startFrame: 6))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 3, 2])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 6, 10], "Pasted 6..<9; frame 9 stays empty")
        assertNoOverlappingCels(manager)
    }

    func testPasteCelOneFramePastTheGapIsClampedToTheGap() {
        let manager = manageWithClipboard(sourceLength: 3, target: [(start: 0, length: 3), (start: 10, length: 2)])

        XCTAssertTrue(manager.pasteCel(layerIndex: 0, startFrame: 8))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 8, 10])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 2, 2],
                       "A 3-frame clipboard pasted into a 2-frame gap is truncated to 2")
        assertNoOverlappingCels(manager)
    }

    func testPasteCelOntoAFrameAlreadyCoveredIsRejected() {
        let manager = manageWithClipboard(sourceLength: 3, target: [(start: 0, length: 3), (start: 10, length: 2)])

        XCTAssertFalse(manager.pasteCel(layerIndex: 0, startFrame: 1))
        XCTAssertFalse(manager.pasteCel(layerIndex: 0, startFrame: 11))
        XCTAssertEqual(CanvasFixture.celLayout(manager).count, 2)
    }

    func testPasteCelWithAnEmptyClipboardIsRejected() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])

        XCTAssertNil(manager.copiedCel)
        XCTAssertFalse(manager.pasteCel(layerIndex: 0, startFrame: 5))
        XCTAssertEqual(CanvasFixture.celLayout(manager).count, 1)
    }

    func testPasteCelDoesNotConsumeTheClipboard() {
        let manager = manageWithClipboard(sourceLength: 2, target: [(start: 0, length: 2)])

        XCTAssertTrue(manager.pasteCel(layerIndex: 0, startFrame: 4))
        XCTAssertTrue(manager.pasteCel(layerIndex: 0, startFrame: 8), "The same clipboard entry pastes repeatedly")
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 4, 8])
    }

    func testPasteCelCopiesClipboardContentRatherThanSharingIt() {
        let manager = manageWithClipboard(sourceLength: 2, target: [(start: 0, length: 2)])

        XCTAssertTrue(manager.pasteCel(layerIndex: 0, startFrame: 4))
        XCTAssertTrue(manager.pasteCel(layerIndex: 0, startFrame: 8))

        let first = manager.layers[0].cels[1].raster
        let second = manager.layers[0].cels[2].raster
        XCTAssertFalse(first === second, "Two pastes of one clipboard entry must not share a texture")
        XCTAssertFalse(first === manager.copiedCel?.raster, "…nor share the clipboard's own texture")
    }

    // MARK: - The three clamps against each other

    /// The single test the dedup most needs: put all three operations in front of the *same*
    /// situation — a request for 8 frames into a 5-frame gap — and require the same answer. If the
    /// shared helper ever changes the arithmetic (off-by-one at the boundary, `>=` instead of `>`,
    /// clamping the start instead of the length), at least one of these three arms moves.
    func testAllThreeCelCreatorsClampAnEightFrameRequestIntoAFiveFrameGapIdentically() {
        func lengthAfterAdd() -> Int? {
            let manager = CanvasFixture.manager()
            CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 8), (start: 13, length: 2)])
            guard manager.addCel(layerIndex: 0, startFrame: 8, frameCount: 8) else { return nil }
            return manager.layers[0].cels.first { $0.startFrame == 8 }?.frameCount
        }

        func lengthAfterDuplicate() -> Int? {
            let manager = CanvasFixture.manager()
            CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 8), (start: 13, length: 2)])
            manager.duplicateCel(layerIndex: 0, celIndex: 0)
            return manager.layers[0].cels.first { $0.startFrame == 8 }?.frameCount
        }

        func lengthAfterPaste() -> Int? {
            let manager = CanvasFixture.manager(layerCount: 2)
            CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 8)])
            manager.copyCel(layerIndex: 1, celIndex: 0)
            CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 8), (start: 13, length: 2)])
            guard manager.pasteCel(layerIndex: 0, startFrame: 8) else { return nil }
            return manager.layers[0].cels.first { $0.startFrame == 8 }?.frameCount
        }

        XCTAssertEqual(lengthAfterAdd(), 5, "addCel")
        XCTAssertEqual(lengthAfterDuplicate(), 5, "duplicateCel")
        XCTAssertEqual(lengthAfterPaste(), 5, "pasteCel")
    }

    /// Same three-way comparison for the no-neighbour case, where the clamp must not fire at all.
    func testAllThreeCelCreatorsLeaveAnUnboundedRequestUnclamped() {
        let addManager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(addManager, layerIndex: 0, [(start: 0, length: 4)])
        XCTAssertTrue(addManager.addCel(layerIndex: 0, startFrame: 4, frameCount: 9))
        XCTAssertEqual(addManager.layers[0].cels.first { $0.startFrame == 4 }?.frameCount, 9)

        let duplicateManager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(duplicateManager, layerIndex: 0, [(start: 0, length: 9)])
        duplicateManager.duplicateCel(layerIndex: 0, celIndex: 0)
        XCTAssertEqual(duplicateManager.layers[0].cels.first { $0.startFrame == 9 }?.frameCount, 9)

        let pasteManager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setCelLayout(pasteManager, layerIndex: 1, [(start: 0, length: 9)])
        pasteManager.copyCel(layerIndex: 1, celIndex: 0)
        CanvasFixture.setCelLayout(pasteManager, layerIndex: 0, [(start: 0, length: 4)])
        XCTAssertTrue(pasteManager.pasteCel(layerIndex: 0, startFrame: 4))
        XCTAssertEqual(pasteManager.layers[0].cels.first { $0.startFrame == 4 }?.frameCount, 9)
    }

    // MARK: - Edge resizing pushes into the neighbour

    /// `resizeCelRightEdge` used to hard-clamp at the next block's `startFrame`. It now pushes: the
    /// neighbour gives up frames from its leading edge instead of stopping the drag dead. These pin
    /// the push, its one-frame floor, and the "already one frame long is an immovable wall" case,
    /// none of which had coverage.
    func testDraggingTheRightEdgeIntoTheNextCelPushesItRatherThanStopping() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 5)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 5)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 5])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [5, 3],
                       "The neighbour keeps its end frame (8) and gives up its first two frames")
        assertNoOverlappingCels(manager)
    }

    func testDraggingTheRightEdgeStopsOneFrameShortOfConsumingTheNeighbour() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 5)])

        // The neighbour ends at 8; asking to run right through it must leave it one frame long.
        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 40)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 7])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [7, 1],
                       "A block can't be squeezed out of existence — its floor is one frame")
        assertNoOverlappingCels(manager)
    }

    func testANeighbourAlreadyOneFrameLongIsAnImmovableWall() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 1)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 9)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 3])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 1],
                       "There is nothing left to give, so the drag can't advance at all")
        assertNoOverlappingCels(manager)
    }

    /// The push is an edit to the neighbour, not a temporary displacement: pulling the dragged block
    /// back afterwards opens a gap rather than restoring the neighbour.
    func testPullingTheRightEdgeBackAfterAPushLeavesAGapRatherThanRestoringTheNeighbour() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 5)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 6)
        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 3)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 6])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 2],
                       "Frames 3..<6 are now empty; the neighbour stays where the push put it")
        assertNoOverlappingCels(manager)
    }

    func testDraggingTheRightEdgeWithNoNeighbourIsUnboundedAndGrowsTheScene() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 30)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [30])
        XCTAssertEqual(manager.sceneFrameCount, 30)
    }

    func testTheDraggedBlockItselfCannotBeShrunkBelowOneFrame() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 2, length: 4)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [2])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [1])
    }

    /// The mirror image on the left edge: dragging back into the previous block shrinks it from its
    /// *trailing* edge, floored at one frame.
    func testDraggingTheLeftEdgeIntoThePreviousCelPushesItRatherThanStopping() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 5), (start: 5, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 3)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 3])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 5],
                       "The previous block keeps its start frame and loses its last two frames")
        assertNoOverlappingCels(manager)
    }

    func testDraggingTheLeftEdgeStopsOneFrameShortOfConsumingThePreviousCel() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 2, length: 5), (start: 7, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [2, 3])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [1, 7],
                       "The previous block starts at 2 and keeps one frame, so the floor is 3")
        assertNoOverlappingCels(manager)
    }

    func testAPreviousCelAlreadyOneFrameLongIsAnImmovableWall() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 4, length: 1), (start: 5, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [4, 5])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [1, 3])
        assertNoOverlappingCels(manager)
    }

    func testDraggingTheLeftEdgeWithNoPreviousCelIsFlooredAtFrameZero() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 4, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 0, newStartFrame: -5)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [7], "The right edge is held fixed at 7")
    }

    func testDraggingTheLeftEdgePastItsOwnRightEdgeLeavesOneFrame() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 5)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 0, newStartFrame: 99)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [4])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [1])
    }

    /// `extendCelToEnd` deliberately does *not* inherit the push — a menu item that promises "fill
    /// the space after this" must stop at the next block, not eat into it.
    func testExtendCelToEndStopsAtTheNeighbourInsteadOfPushingIt() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2), (start: 6, length: 3)])

        manager.extendCelToEnd(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 6])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [6, 3],
                       "Fills 0..<6 exactly and leaves the neighbour alone")
        assertNoOverlappingCels(manager)
    }

    // MARK: - Undo bracketing

    /// All three creators run inside `withStructureUndo`, so each is exactly one undo step. Pinned
    /// because a decomposition that moves these into extensions is a chance to drop or double a
    /// wrapper (session 41 fixed exactly that class of bug in `mergeLayers`/`deleteViewPreset`).
    func testEachCelCreatorRecordsExactlyOneUndoStep() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 2)])
        manager.copyCel(layerIndex: 1, celIndex: 0)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2)])

        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 4, frameCount: 2))
        XCTAssertTrue(manager.pasteCel(layerIndex: 0, startFrame: 8))
        manager.duplicateCel(layerIndex: 0, celIndex: 0)
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 2, 4, 8])

        manager.undo()
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 4, 8], "One undo reverses the duplicate")
        manager.undo()
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 4], "…the next reverses the paste")
        manager.undo()
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0], "…the next reverses the add")

        manager.redo()
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 4], "and redo replays them one at a time")
    }

    /// A rejected operation must not leave an empty undo step behind for the user to press through.
    func testRejectedCelCreationRecordsNoUndoStep() {
        // The fixture's own `addLayer` is itself one undo step, so the stack starts at depth 1 —
        // which is what makes it a usable probe: undo once at the end and the layer must be gone.
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])
        XCTAssertTrue(manager.canUndo)

        XCTAssertFalse(manager.addCel(layerIndex: 0, startFrame: 1, frameCount: 2), "Frame 1 is covered")
        XCTAssertFalse(manager.addCel(layerIndex: 0, startFrame: 5, frameCount: 0), "Zero length")
        XCTAssertFalse(manager.pasteCel(layerIndex: 0, startFrame: 5), "Empty clipboard")

        manager.undo()

        XCTAssertTrue(manager.layers.isEmpty,
                      "One undo must pop the `addLayer` — if any of the three rejected calls had recorded a step, it would have been popped instead and the layer would still be here")
        XCTAssertFalse(manager.canUndo, "…and that was the only step on the stack")
    }
}
