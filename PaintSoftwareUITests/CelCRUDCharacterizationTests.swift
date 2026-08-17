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

    // MARK: - Edge resizing pushes the neighbour along, instead of shrinking or stopping at it

    /// The contract these pin is not the original one. `resizeCelRightEdge` used to hard-clamp at
    /// the next block's `startFrame - 1` and shrink that neighbour from its own leading edge — which
    /// made a one-frame neighbour an immovable wall the drag simply could not get past. The owner
    /// overruled that: with two-or-more blocks side by side, extending the first one right is now
    /// supposed to shove the others along, each keeping its own length, not eat into them. See the
    /// doc comments on `resizeCelRightEdge`/`resizeCelLeftEdge` in `CanvasManager+Timeline.swift` for
    /// the full argument, including why every push has to be computed from a gesture's baseline
    /// rather than the live model — `testOutAndBackRightEdgeDragWithinOneGestureRestoresEveryPushed
    /// NeighbourExactly` below is what that baseline requirement is actually for.
    func testDraggingTheRightEdgeIntoTheNextCelPushesItRatherThanStopping() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 5)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 5)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 5])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [5, 5],
                       "The neighbour keeps its length (5) and its end moves with it — translating, not shrinking")
        assertNoOverlappingCels(manager)
    }

    /// A three-deep chain: pushing the first block far enough has to carry the second *and* the
    /// third along, each still full length, not just shove the immediate neighbour and stop.
    func testDraggingTheRightEdgeThroughMultipleNeighboursPushesAllOfThemTransitively() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0,
                                   [(start: 0, length: 3), (start: 3, length: 2), (start: 5, length: 2), (start: 7, length: 2)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 6)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 6, 8, 10])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [6, 2, 2, 2],
                       "All three later blocks moved, none of them shrank")
        assertNoOverlappingCels(manager)
    }

    /// The owner's own worked example, verbatim, resolving what "push the neighbours" means when it
    /// was first ambiguous whether the *whole* track downstream should shift or only the blocks the
    /// resize actually collides with: "you have 4 animation blocks in frames 1 2 3 and 5. Extend
    /// block 1 to occupy frames 1 and 2. The second and third animation block should move to frame 3
    /// and 4 respectively, and the fifth animation block shouldn't move." The fourth block (at frame
    /// 5) is the point of the example — the cascade in `resizeCelRightEdge` already stops the instant
    /// a successor's baseline doesn't overlap the running cursor, and this is the owner's own case for
    /// why that has to be true rather than shifting everything downstream by the same amount.
    func testOwnersWorkedExampleFourBlocksCascadeStopsAtTheFirstNonCollision() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0,
                                   [(start: 1, length: 1), (start: 2, length: 1), (start: 3, length: 1), (start: 5, length: 1)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 3)   // block 1 now occupies frames 1 and 2

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [1, 3, 4, 5],
                       "Blocks 2 and 3 move to 3 and 4; block 4, at frame 5, has nothing left pushing on it and doesn't move")
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [2, 1, 1, 1])
        assertNoOverlappingCels(manager)
    }

    /// The owner's second worked example, verbatim: "you have 2 animation blocks, the first on frame
    /// 1 and the second on frames 2 and 3. You extend block 1 to occupy frame 1 and 2, then block 2
    /// should now be 3 and 4 (animation block length preserved)." The parenthetical is the owner
    /// stating the core invariant themselves — length survives the push unconditionally, which is
    /// this file's whole departure from the contract it used to pin.
    func testOwnersWorkedExampleTwoBlocksLengthPreservedThroughThePush() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 1, length: 1), (start: 2, length: 2)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 3)   // block 1 now occupies frame 1 and 2

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [1, 3])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [2, 2],
                       "Block 2 is still 2 frames long, now at 3 and 4")
        assertNoOverlappingCels(manager)
    }

    /// The bug this fixes, in one test: a neighbour this short used to stop the drag outright because
    /// shrinking it below one frame was refused and there was nothing else the old contract could do.
    /// Translating doesn't touch its length, so it has nothing to refuse — it just moves.
    func testANeighbourOneFrameLongIsNoLongerAnImmovableWall() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 1)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 9)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 9])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [9, 1],
                       "Still one frame long, just nine frames further along than where it started")
        assertNoOverlappingCels(manager)
    }

    /// Two *independent* calls — no gesture bracket open between them — each treat wherever the
    /// model currently stands as their own baseline, so the second call has no way to know the first
    /// call's push was part of the "same" drag. Pulling back therefore leaves a gap rather than
    /// restoring the neighbour. This is the correct behavior for two unrelated edits; it is exactly
    /// what `beginStructureGesture`/`gestureSnapshot` exist to prevent *within* one continuous drag —
    /// see the bracketed version of this test below.
    func testPullingTheRightEdgeBackAcrossTwoIndependentCallsLeavesAGapRatherThanRestoringTheNeighbour() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 5)])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 6)
        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 3)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 6])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 5],
                       "Frames 3..<6 are now empty; the neighbour, still 5 long, stays where the first call put it")
        assertNoOverlappingCels(manager)
    }

    /// The idempotence the correctness of the whole rewrite hinges on: `TimelineTrackView`'s pan
    /// handler calls `resizeCelRightEdge` on every `.changed` event of a *single* drag, bracketed by
    /// `beginStructureGesture()`/`commitStructureGesture(label:)`. Dragging out and back within that
    /// one bracket must restore every pushed block exactly, because every call reads its baseline
    /// from `gestureSnapshot` (frozen at `.began`) rather than from whatever the previous call left
    /// behind — contrast with the unbracketed version above, where restoration is explicitly *not*
    /// what happens.
    func testOutAndBackRightEdgeDragWithinOneGestureRestoresEveryPushedNeighbourExactly() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3), (start: 3, length: 5)])

        manager.beginStructureGesture()
        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 5)   // pushes the neighbour
        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 8)   // pushes it further
        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 3)   // back to where the drag started
        manager.commitStructureGesture(label: .resizeFrame)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 3],
                       "Every intermediate push undone — this is the drift Change 1 exists to fix")
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [3, 5])
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

    /// The mirror image on the left edge: dragging back into the previous block translates it
    /// earlier, keeping its length, instead of shrinking it from its trailing edge.
    func testDraggingTheLeftEdgeIntoThePreviousCelPushesItRatherThanStopping() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 3, length: 5), (start: 8, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 6)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [1, 6])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [5, 5],
                       "The previous block keeps its length (5) and its start moves with it")
        assertNoOverlappingCels(manager)
    }

    /// A three-deep chain walking left, mirroring the right edge's transitive test — with enough room
    /// before frame 0 that the floor never engages, so this isolates the cascade from the clamp.
    func testDraggingTheLeftEdgeThroughMultipleNeighboursPushesAllOfThemTransitively() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0,
                                   [(start: 10, length: 2), (start: 12, length: 2), (start: 14, length: 2), (start: 16, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 3, newStartFrame: 11)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [5, 7, 9, 11])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [2, 2, 2, 8],
                       "All three earlier blocks moved, none of them shrank")
        assertNoOverlappingCels(manager)
    }

    /// Frame 0 is a hard floor, but it only clips the shortfall — a push that reaches it is still a
    /// push, just capped, not silently refused outright the way `testDraggingTheLeftEdgeIsANoOp...`
    /// below is.
    func testDraggingTheLeftEdgeIsFlooredAtFrameZeroWhenThePushWouldGoFurther() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 2, length: 5), (start: 7, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 5])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [5, 5],
                       "The previous block is pushed exactly to frame 0, keeping its full length, and the dragged block follows it as far as that allows")
        assertNoOverlappingCels(manager)
    }

    /// The previous block already sits flush against frame 0 with nothing to give — the push has
    /// nowhere to put it, so the whole drag is a no-op rather than a partial or negative one.
    func testDraggingTheLeftEdgeIsANoOpWhenThePredecessorAlreadyHasNoRoomToGive() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 5), (start: 5, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 3)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 5])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [5, 3],
                       "Nothing moved: the previous block was already touching frame 0")
        assertNoOverlappingCels(manager)
    }

    /// Left-edge mirror of the right edge's out-and-back test — the deficit-and-shift floor logic is
    /// enough more involved than the right edge's unbounded push that it earns its own idempotence
    /// check rather than trusting the mirror to be exact by inspection.
    func testOutAndBackLeftEdgeDragWithinOneGestureRestoresEveryPushedNeighbourExactly() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 2, length: 5), (start: 7, length: 3)])

        manager.beginStructureGesture()
        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 5)   // pushes the previous block
        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 0)   // pushes it into the floor
        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 7)   // back to where the drag started
        manager.commitStructureGesture(label: .resizeFrame)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [2, 7])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [5, 3])
        assertNoOverlappingCels(manager)
    }

    func testAPreviousCelOneFrameLongIsNoLongerAnImmovableWall() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 4, length: 1), (start: 5, length: 3)])

        manager.resizeCelLeftEdge(layerIndex: 0, celIndex: 1, newStartFrame: 0)

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 1])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [1, 7],
                       "Still one frame long, just pushed down to frame 0 instead of staying put")
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

    // MARK: - ensureCelAtCurrentFrame
    //
    // The blank-frame drawing path. Every drawing operation is gated on `activeCelIndex` finding
    // something, so parking the playhead past the last block used to leave the canvas inert; this
    // is the hook that turns "draw on an empty frame" into "make a block and draw on it".

    func testEnsureCelReturnsTheExistingBlockWithoutCreatingAnything() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])
        manager.currentFrame = 1

        XCTAssertEqual(manager.ensureCelAtCurrentFrame(layerIndex: 0), 0)
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0], "No second block")
    }

    func testEnsureCelSpawnsAOneFrameBlockOnAnEmptyFrame() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2)])
        manager.currentFrame = 6

        let celIndex = manager.ensureCelAtCurrentFrame(layerIndex: 0)

        XCTAssertNotNil(celIndex)
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 6])
        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.length), [2, 1],
                       "One frame long — extending it is `Extend to End`'s job, not the first stroke's")
        assertNoOverlappingCels(manager)
    }

    /// The spawned block is clamped by the next one, same as any other creation — a frame sitting in
    /// a one-frame hole gets a one-frame block, not one that swallows its neighbour.
    func testASpawnedBlockCannotOverlapTheBlockAfterIt() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2), (start: 3, length: 4)])
        manager.currentFrame = 2

        XCTAssertNotNil(manager.ensureCelAtCurrentFrame(layerIndex: 0))

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0, 2, 3])
        assertNoOverlappingCels(manager)
    }

    /// A block spawned on a `.vector` layer has to be a *vector* block. Without its own
    /// `VectorCanvas` the stroke view silently falls back to raster mode and the drawing lands as
    /// pixels on a vector layer — invisible to the geometric eraser, to the save payload's vector
    /// half, and to interpolation, which reads `cel.vector` and finds nothing.
    func testASpawnedBlockOnAVectorLayerGetsItsOwnVectorCanvas() {
        let manager = CanvasFixture.manager()
        manager.addVectorLayer()
        let layerIndex = manager.layers.count - 1
        CanvasFixture.setCelLayout(manager, layerIndex: layerIndex, [(start: 0, length: 2)])
        manager.currentFrame = 5

        guard let celIndex = manager.ensureCelAtCurrentFrame(layerIndex: layerIndex) else {
            return XCTFail("No block spawned")
        }

        XCTAssertNotNil(manager.layers[layerIndex].cels[celIndex].vector)
    }

    func testSpawningABlockIsOneUndoStep() {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2)])
        manager.currentFrame = 6

        XCTAssertNotNil(manager.ensureCelAtCurrentFrame(layerIndex: 0))
        manager.undo()

        XCTAssertEqual(CanvasFixture.celLayout(manager).map(\.start), [0],
                       "One undo takes the spawned block back off again")
    }

    func testEnsureCelOnAMissingLayerIsANoOp() {
        let manager = CanvasFixture.manager()
        manager.currentFrame = 3

        XCTAssertNil(manager.ensureCelAtCurrentFrame(layerIndex: 7))
    }

    // MARK: - The rasterize memo (LAYER_COMPOSITING.md §5.2)

    /// `PixelOps.rasterize` memoizes its flatten on model state — cel id, both tier versions, both
    /// image identities, size and quality. These pin the two halves that matter in opposite
    /// directions: that it *hits* when nothing changed (or it is pointless), and that it *misses*
    /// on every input that can change the pixels (or it is a stale-frame bug).
    ///
    /// The staleness half is the one worth having. A cache keyed on a version that fails to bump
    /// serves last frame's ink forever, and the symptom — a stroke that lands everywhere except the
    /// thumbnail — looks nothing like a caching problem.

    private func size() -> CGSize { CGSize(width: 64, height: 64) }

    func testFlatteningTheSameUntouchedCelTwiceReturnsTheMemoizedImage() {
        PixelOps.clearRasterizeCache()
        let manager = CanvasFixture.manager(layerCount: 1)
        let cel = manager.layers[0].cels[0]

        let first = PixelOps.rasterize(cel: cel, canvasSize: size())
        let second = PixelOps.rasterize(cel: cel, canvasSize: size())
        XCTAssertTrue(first === second, "An unchanged cel must not be flattened twice — that flatten is the 276 ms")
    }

    func testAStrokeOnTheRasterTierInvalidatesTheMemo() {
        PixelOps.clearRasterizeCache()
        let manager = CanvasFixture.manager(layerCount: 1)
        let cel = manager.layers[0].cels[0]
        let before = PixelOps.rasterize(cel: cel, canvasSize: size())

        cel.raster.beginStroke()
        cel.raster.stampCircle(at: CGPoint(x: 20, y: 20), radius: 6, color: .red, alpha: 1, hardness: 1)
        cel.raster.endStroke()

        XCTAssertFalse(PixelOps.rasterize(cel: cel, canvasSize: size()) === before,
                       "RasterLayerTexture.version bumped, so the flatten must be redone")
    }

    func testAVectorEditInvalidatesTheMemo() {
        PixelOps.clearRasterizeCache()
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        let cel = manager.layers[0].cels[0]
        guard let vector = cel.vector else { return XCTFail("A vector layer's cel carries a VectorCanvas") }
        let before = PixelOps.rasterize(cel: cel, canvasSize: size())

        vector.addStroke(VectorStroke(brush: manager.selectedBrush,
                                      color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                      size: 8, opacity: 1,
                                      samples: [VectorSample(x: 8, y: 8, pressure: 1),
                                                VectorSample(x: 40, y: 40, pressure: 1)]))

        XCTAssertFalse(PixelOps.rasterize(cel: cel, canvasSize: size()) === before,
                       "The vector tier has its own version and it is part of the key")
    }

    func testReplacingTheFillOrBakedImageInvalidatesTheMemo() {
        PixelOps.clearRasterizeCache()
        let manager = CanvasFixture.manager(layerCount: 1)
        var cel = manager.layers[0].cels[0]
        let before = PixelOps.rasterize(cel: cel, canvasSize: size())

        // Wholesale replacement is how a fill or a bake actually lands, which is why the key
        // compares these by object identity rather than content.
        cel.fillImage = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 20, height: 20))
        let afterFill = PixelOps.rasterize(cel: cel, canvasSize: size())
        XCTAssertFalse(afterFill === before, "A new fillImage is a new flatten")

        cel.bakedImage = CanvasFixture.solidImage(.blue, rect: CGRect(x: 10, y: 10, width: 20, height: 20))
        XCTAssertFalse(PixelOps.rasterize(cel: cel, canvasSize: size()) === afterFill,
                       "And so is a new bakedImage")
    }

    /// The collision the key's object-identity half exists to prevent, in the form it actually
    /// takes: a cel id outlives the buffers under it, so a reopened project presents the same id
    /// with a `RasterLayerTexture` whose version counter has restarted at 0. A version-only key
    /// would match an entry cached before the last edit and hand back pre-edit pixels.
    func testAFreshBufferUnderTheSameCelIdIsNotAHit() {
        PixelOps.clearRasterizeCache()
        let manager = CanvasFixture.manager(layerCount: 1)
        var cel = manager.layers[0].cels[0]

        cel.raster.beginStroke()
        cel.raster.stampCircle(at: CGPoint(x: 20, y: 20), radius: 6, color: .red, alpha: 1, hardness: 1)
        cel.raster.endStroke()
        let drawn = PixelOps.rasterize(cel: cel, canvasSize: size())

        // What a reload does: same cel id, a brand-new buffer, version back to 0.
        cel.raster = .empty(size: size())
        XCTAssertEqual(cel.raster.version, 0, "Fixture: a fresh texture starts its counter over")
        XCTAssertFalse(PixelOps.rasterize(cel: cel, canvasSize: size()) === drawn,
                       "A new buffer must be a new key however its version happens to read")
    }

    func testQualityAndCanvasSizeAreBothPartOfTheKey() {
        PixelOps.clearRasterizeCache()
        let manager = CanvasFixture.manager(layerCount: 1)
        let cel = manager.layers[0].cels[0]

        let full = PixelOps.rasterize(cel: cel, canvasSize: size(), quality: .full)
        XCTAssertFalse(PixelOps.rasterize(cel: cel, canvasSize: size(), quality: .preview) === full,
                       "`.preview` resolves the vector tier differently, so it is a different flatten")
        XCTAssertFalse(PixelOps.rasterize(cel: cel, canvasSize: CGSize(width: 32, height: 32)) === full,
                       "A different canvas size is a different image, not a scaled one")
    }
}
