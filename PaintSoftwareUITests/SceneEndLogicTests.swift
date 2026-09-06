import XCTest
import UIKit

/// Where the animation ends, and the one number that says so.
///
/// TODO (50). The owner, from behaviour alone:
///
/// > *"The end of the animation timeline should be the last frame. This is important because if I do
/// > an extend to end on a cel, then it extends that cel to the 12th frame even if the last cel is
/// > not on frame 12. If I manually extend a frame to a further frame, then retract it back, then do
/// > an extend to end, then the extend to end goes up to that last frame I extended to."*
///
/// The cause was `CanvasManager.sceneFrameCount`, a stored `@Published var … = 12` whose **every**
/// write in the app was `sceneFrameCount = max(sceneFrameCount, …)` — eight of them, none of which
/// could lower it — persisted into `ProjectManifest` and snapshotted by `captureStructure`, so the
/// high-water mark outlived the cel that set it, the save that followed it and the undo that
/// reverted it. It is gone; `contentEndFrame` is the only account of where the scene ends.
///
/// **Every assertion here is on a *verb*, not on the field**, because the field is what was wrong.
/// A test that read the number back would have passed against the bug for the whole of its life.
/// `@MainActor` because `ProjectStore.save`/`load` are, and `wait(for:)` spins the run loop on it.
@MainActor
final class SceneEndLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// A manager whose layers hold exactly the given blocks — `[layerIndex: [(start, length)]]`.
    ///
    /// Built through `CanvasFixture.setCelLayout`, which writes the cel arrays directly, so the
    /// starting timeline is stated rather than assembled out of the verbs under test.
    private func manager(_ blocks: [[(start: Int, length: Int)]]) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: blocks.count)
        for (index, layerBlocks) in blocks.enumerated() {
            CanvasFixture.setCelLayout(manager, layerIndex: index, layerBlocks)
        }
        return manager
    }

    /// A layer's blocks as `[[start, length], …]` — `CanvasFixture.celLayout` returns tuples, and an
    /// array of tuples is not `Equatable`, so `XCTAssertEqual` cannot take one.
    private func layout(_ manager: CanvasManager, layerIndex: Int = 0) -> [[Int]] {
        CanvasFixture.celLayout(manager, layerIndex: layerIndex).map { [$0.start, $0.length] }
    }

    // MARK: - Extend to end

    /// The owner's first sentence. Two layers, the longest reaching frame 5, and a fresh document's
    /// twelve-frame default still hanging around in the old high-water mark: extending the short
    /// block "to the end" must stop at 5, which is where the animation actually ends.
    ///
    /// **Red before the fix at 12** — the default, reached because nothing had ever lowered it.
    func testExtendToEndStopsAtTheLastCelRatherThanAtTheTwelveFrameDefault() {
        let manager = self.manager([[(start: 0, length: 2)],
                                    [(start: 0, length: 5)]])
        XCTAssertEqual(manager.contentEndFrame, 5, "PREMISE: the animation is five frames long")

        manager.extendCelToEnd(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(layout(manager), [[0, 5]],
                       "Extend to end fills to the last cel in the document, not to the default 12")
        XCTAssertEqual(manager.contentEndFrame, 5, "…and does not lengthen the animation to do it")
    }

    /// The owner's second sentence, driven through the real verbs: extend a block out to frame 30,
    /// retract it back to 3, then extend to end. The answer must be 3.
    ///
    /// **Red before the fix at 30.** The retraction gave back the frames and left the mark behind,
    /// so "the end" was still wherever the artist had last reached, minutes or sessions ago.
    func testExtendToEndAfterAnExtendAndARetractStopsAtTheLastCel() {
        let manager = self.manager([[(start: 0, length: 3)]])

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 30)
        XCTAssertEqual(manager.contentEndFrame, 30, "PREMISE: the drag lengthened the animation")

        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 3)
        XCTAssertEqual(manager.contentEndFrame, 3, "The retraction shortens it again")

        manager.extendCelToEnd(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(layout(manager), [[0, 3]],
                       "Extend to end has nowhere to go — the block already reaches the end")
    }

    /// Deleting the last block shortens the scene, which is the general form of the retraction above
    /// and the half the owner named as *"never falls back down when the last cel changes"*.
    func testDeletingTheLastBlockBringsTheEndBackToWhatIsLeft() {
        let manager = self.manager([[(start: 0, length: 2), (start: 20, length: 4)]])
        XCTAssertEqual(manager.contentEndFrame, 24, "PREMISE: the far block is the end of the scene")

        manager.deleteCel(layerIndex: 0, celIndex: 1)

        XCTAssertEqual(manager.contentEndFrame, 2, "The end falls back to the block that is left")
        manager.extendCelToEnd(layerIndex: 0, celIndex: 0)
        XCTAssertEqual(layout(manager), [[0, 2]],
                       "…and extend to end agrees with it rather than with the deleted block")
    }

    /// Extend to end still stops at the **next block on the same layer** when there is one. That
    /// clamp is `neighborBounds`, not the scene end, and removing the stored field must not have
    /// quietly taken it with it — a menu item whose promise is *"fill the empty space after this"*
    /// may not push its neighbour down the track.
    func testExtendToEndStillStopsAtTheNextBlockOnItsOwnLayer() {
        let manager = self.manager([[(start: 0, length: 2), (start: 6, length: 2)],
                                    [(start: 0, length: 20)]])
        XCTAssertEqual(manager.contentEndFrame, 20, "PREMISE: the scene runs to frame 20")

        manager.extendCelToEnd(layerIndex: 0, celIndex: 0)

        XCTAssertEqual(layout(manager), [[0, 6], [6, 2]],
                       "It fills up to its neighbour and stops, leaving the neighbour where it was")
    }

    // MARK: - Undo

    /// `captureStructure` used to snapshot the mark, so undo restored the *old* high-water mark
    /// rather than recomputing where the drawing now ends. With the field gone there is nothing to
    /// restore and nothing to get wrong: undo puts the cels back and the end follows them.
    ///
    /// **Red before the fix**: the undo left the mark at 12 and the extend went to 12.
    func testUndoingABlockAddedPastTheEndTakesTheEndBackWithIt() {
        let manager = self.manager([[(start: 0, length: 3)]])

        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 20, frameCount: 2),
                      "PREMISE: a block can be added out past the last one")
        XCTAssertEqual(manager.contentEndFrame, 22, "PREMISE: it is now the end of the scene")

        manager.undo()

        XCTAssertEqual(manager.contentEndFrame, 3, "Undo takes the end back with the block")
        manager.extendCelToEnd(layerIndex: 0, celIndex: 0)
        XCTAssertEqual(layout(manager), [[0, 3]],
                       "…and extend to end agrees, rather than reaching the undone block's end")
    }

    /// Redo puts it back, so the end is not a one-way door in the other direction either.
    func testRedoingThatBlockPutsTheEndBack() {
        let manager = self.manager([[(start: 0, length: 3)]])
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 20, frameCount: 2))
        manager.undo()
        XCTAssertEqual(manager.contentEndFrame, 3, "PREMISE: the undo shortened it")

        manager.redo()

        XCTAssertEqual(manager.contentEndFrame, 22, "Redo lengthens it again")
    }

    /// The playhead is pulled back inside the scene when an undo shortens it, which is
    /// `restoreStructure`'s own long-standing rule now reading a derived end instead of a snapshotted
    /// field — and therefore reading the document it just restored rather than a number that could
    /// only ever have been too large.
    func testUndoingABlockPastTheEndPullsThePlayheadBackInside() {
        let manager = self.manager([[(start: 0, length: 3)]])
        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 20, frameCount: 2))
        manager.goToFrame(21)

        manager.undo()

        XCTAssertEqual(manager.currentFrame, 2,
                       "Frame 21 no longer exists in the document, so the playhead comes back to the last one")
    }

    // MARK: - The gap menu's range

    /// A gap **between** two blocks is bounded by both of them, which is untouched by any of this.
    func testAGapBetweenTwoBlocksIsBoundedByBoth() {
        let manager = self.manager([[(start: 0, length: 2), (start: 10, length: 2)]])

        XCTAssertEqual(manager.gapFrameRange(layerIndex: 0, containing: 5), 2..<10)
    }

    /// **The trailing gap ends at the frame that was tapped**, because past the last block there is
    /// no end for it to run to. It used to run to the stored scene length, which is to say to
    /// whatever the artist's furthest reach had happened to be — so the same tap covered a different
    /// stretch depending on history. It now covers the stretch between the last drawing and the
    /// column the artist actually pointed at.
    func testTheTrailingGapRunsFromTheLastBlockToTheTappedFrame() {
        let manager = self.manager([[(start: 0, length: 2)]])

        XCTAssertEqual(manager.gapFrameRange(layerIndex: 0, containing: 8), 2..<9)
        XCTAssertEqual(manager.gapFrameRange(layerIndex: 0, containing: 2), 2..<3,
                       "…including the very first empty column, which is a one-frame gap")
    }

    /// A frame inside a block is not a gap at all.
    func testAFrameInsideABlockHasNoGapRange() {
        let manager = self.manager([[(start: 0, length: 4)]])

        XCTAssertNil(manager.gapFrameRange(layerIndex: 0, containing: 2))
    }

    // MARK: - Save and reload

    /// The mark was a field of `ProjectManifest`, so an inflated one survived a save and came back
    /// on open — a document could carry a wrong end across sessions with nothing on screen saying
    /// where it came from. The field is gone from the format; the end is recomputed from the cels
    /// that were loaded.
    ///
    /// **Red before the fix**: the reloaded document extended to 30.
    func testASavedDocumentDoesNotCarryAnInflatedEndAcrossAReload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-end-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: root)
        }

        let manager = self.manager([[(start: 0, length: 3)]])
        // Inflate the way the owner did, then give the frames back.
        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 30)
        manager.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 3)
        XCTAssertEqual(manager.contentEndFrame, 3, "PREMISE: the live document is three frames long")

        let url = ProjectStore.createNewProjectURL(name: "Scene End")
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)

        let reloaded = try XCTUnwrap(ProjectStore.load(from: url), "The saved package should load")

        XCTAssertEqual(reloaded.contentEndFrame, 3, "The reloaded document ends where its drawing does")
        reloaded.extendCelToEnd(layerIndex: 0, celIndex: 0)
        XCTAssertEqual(layout(reloaded), [[0, 3]],
                       "…and extend to end on it does not reach the mark the save used to carry")
    }

    // MARK: - The empty track is still there

    /// **Shortening the end must not make the frames past it unreachable.** The artist's route to a
    /// block out beyond the last one is the timeline's own look-ahead, not the scene length — see
    /// `TimelineTrackView.Coordinator.displayedFrameCount(contentEndFrame:contentOffsetX:viewportWidth:pixelsPerFrame:)`,
    /// pinned below. This is the model half of the same claim: a two-frame scene still takes a block
    /// at frame 20.
    func testAShortSceneStillTakesABlockOutPastItsEnd() {
        let manager = self.manager([[(start: 0, length: 2)]])

        XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 20, frameCount: 3),
                      "A block lands at frame 20 in a two-frame scene")
        XCTAssertEqual(manager.contentEndFrame, 23, "…and the scene grows to hold it")
    }

    /// **The view half of the same claim, and the one that answers "have you broken the timeline?"**
    ///
    /// `TimelineTrackExtent.displayedFrameCount` is what lays out the empty slots the artist drops a
    /// block into. The scene is only its **floor**; the binding term is two screenfuls past the
    /// current scroll. A 900pt viewport at the default-ish 30pt a frame reaches 61 columns whatever
    /// the document holds, so cutting a twelve-frame scene to two costs the artist no track at all.
    func testTheLaidOutTrackIsTheLookAheadRatherThanTheScene() {
        let twelve = TimelineTrackExtent.displayedFrameCount(contentEndFrame: 12, contentOffsetX: 0,
                                                             viewportWidth: 900, pixelsPerFrame: 30)
        let two = TimelineTrackExtent.displayedFrameCount(contentEndFrame: 2, contentOffsetX: 0,
                                                          viewportWidth: 900, pixelsPerFrame: 30)
        XCTAssertEqual(twelve, 61, "Two screenfuls of 30pt columns across 900pt, plus the partial one")
        XCTAssertEqual(two, twelve, "…and a two-frame scene lays out exactly as much empty track")
    }

    /// Scrolling right keeps producing track, so there is no frame the artist cannot reach.
    func testScrollingRightLaysOutMoreTrack() {
        let atRest = TimelineTrackExtent.displayedFrameCount(contentEndFrame: 2, contentOffsetX: 0,
                                                             viewportWidth: 900, pixelsPerFrame: 30)
        let scrolled = TimelineTrackExtent.displayedFrameCount(contentEndFrame: 2, contentOffsetX: 3000,
                                                               viewportWidth: 900, pixelsPerFrame: 30)
        XCTAssertGreaterThan(scrolled, atRest + 90, "3000pt of scroll is another 100 columns of track")
    }

    /// The scene *is* the floor when it is the larger of the two — a long document zoomed in far
    /// enough that two screenfuls is only a handful of frames still lays out all of itself.
    func testALongSceneIsTheFloorWhenTheLookAheadIsShorterThanIt() {
        let count = TimelineTrackExtent.displayedFrameCount(contentEndFrame: 400, contentOffsetX: 0,
                                                            viewportWidth: 900, pixelsPerFrame: 300)
        XCTAssertEqual(count, 400, "Six columns of look-ahead must not truncate a 400-frame document")
    }

    /// A pinch can hand this a zero, and dividing by it would trap on the `Int` conversion rather
    /// than merely draw wrongly.
    func testAZeroZoomDoesNotTrap() {
        let count = TimelineTrackExtent.displayedFrameCount(contentEndFrame: 5, contentOffsetX: 0,
                                                            viewportWidth: 900, pixelsPerFrame: 0)
        XCTAssertGreaterThan(count, 5)
    }

    // MARK: - Loop markers

    /// **A marker placed past the last drawing is honoured, and this is the assertion that stopped
    /// the fix from going too far.** The natural way to write `effectiveLoopRange` once the stored
    /// length was gone is to clamp into `contentEndFrame`; that is wrong, because the empty track
    /// past the end is exactly where a marker for a shot you are about to draw goes, and
    /// `FrameExport`'s own ruling is that markers are intent.
    func testALoopMarkerPastTheLastDrawingIsHonoured() {
        let manager = self.manager([[(start: 0, length: 3)]])

        manager.setLoopStart(1)
        manager.setLoopEnd(9)

        XCTAssertEqual(manager.playbackStartFrame, 1)
        XCTAssertEqual(manager.playbackEndFrame, 9, "The window is the artist's call, not the content's")
    }

    /// With no markers the window *is* the content, and it shortens with it — which is the same
    /// derivation the rest of this file is about, reached through playback.
    func testWithNoMarkersTheWindowShortensWithTheContent() {
        let manager = self.manager([[(start: 0, length: 12)]])
        XCTAssertEqual(manager.playbackEndFrame, 11, "PREMISE: twelve frames of drawing")

        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])

        XCTAssertEqual(manager.playbackEndFrame, 2, "Playback follows the cels down as well as up")
    }

    /// The playhead has no ceiling either, and never had one — `goToFrame` deliberately does not
    /// author the document. Pinned here because the fix removed the field that a reader might
    /// reasonably have thought was the ceiling.
    func testThePlayheadStillGoesPastTheEndWithoutLengtheningTheScene() {
        let manager = self.manager([[(start: 0, length: 2)]])

        manager.goToFrame(200)

        XCTAssertEqual(manager.currentFrame, 200, "The playhead goes where it is sent…")
        XCTAssertEqual(manager.contentEndFrame, 2, "…and the animation is still two frames long")
    }

    // MARK: - What the transport says

    /// **"Frame n/N" counts the scene, and the scene shortens.** Pinned as its own test because the
    /// arithmetic used to live inside `AnimationTimeline.frameLabel`, where the fast tier could not
    /// see it — hard-coding the old twelve there passed the entire suite when it was tried as a
    /// mutation.
    func testTheFrameLabelDenominatorFollowsTheScene() {
        let manager = self.manager([[(start: 0, length: 12)]])
        XCTAssertEqual(manager.displayedSceneLength, 12, "PREMISE: twelve frames of drawing")

        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])

        XCTAssertEqual(manager.displayedSceneLength, 3, "…and it comes down with them")
    }

    /// …and widens for a playhead parked past the end, so the counter never reads the impossible
    /// "Frame 40/3".
    func testTheFrameLabelDenominatorWidensToAdmitAParkedPlayhead() {
        let manager = self.manager([[(start: 0, length: 3)]])

        manager.goToFrame(39)

        XCTAssertEqual(manager.displayedSceneLength, 40, "Frame 40/40, not Frame 40/3")
        XCTAssertEqual(manager.contentEndFrame, 3, "…and the widening is display-only")
    }

    // MARK: - The default twelve

    /// The twelve did not vanish with the field: it is the length of a **new document's** first
    /// block, which is the only thing the default ever really meant. `CanvasSizePickerView` calls
    /// `addVectorLayer()` on a manager with no layers at all, and that is the moment it applies.
    func testTheFirstLayerOfAnEmptyDocumentIsTwelveFramesLong() {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = CanvasFixture.canvasSize
        XCTAssertEqual(manager.contentEndFrame, 0, "PREMISE: an empty document has no scene yet")

        manager.addVectorLayer()

        XCTAssertEqual(layout(manager), [[0, 12]],
                       "A brand-new document is twelve frames long")
        XCTAssertEqual(manager.contentEndFrame, 12)
    }

    /// …and only then. A layer added to a document that already has one spans **that** document,
    /// which under the old field meant "the high-water mark" and now means "the scene".
    func testALayerAddedToAShortDocumentSpansTheSceneRatherThanTwelve() {
        let manager = self.manager([[(start: 0, length: 4)]])

        manager.addLayer()

        XCTAssertEqual(layout(manager, layerIndex: manager.layers.count - 1), [[0, 4]],
                       "The new layer covers the animation, not twelve frames of it")
        XCTAssertEqual(manager.contentEndFrame, 4, "…and adding a layer does not lengthen the scene")
    }

    /// A layer added to a document **longer** than twelve spans all of it — the direction the old
    /// field got right, kept.
    func testALayerAddedToALongDocumentSpansAllOfIt() {
        let manager = self.manager([[(start: 0, length: 40)]])

        manager.addLayer()

        XCTAssertEqual(layout(manager, layerIndex: manager.layers.count - 1), [[0, 40]])
    }
}
