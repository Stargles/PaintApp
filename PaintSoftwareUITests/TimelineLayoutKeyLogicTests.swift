import XCTest
import UIKit

/// `TimelineLayoutKey` and `TimelineRulerClip` — the two halves of making the timeline stop
/// re-laying-out on every SwiftUI pass.
///
/// **What a memoization key has to be tested for is not that it is equal, but exactly which
/// mutations move it.** A key that misses an input produces a stale timeline row — a block drawn at
/// the wrong length, or a folder band that does not follow its children — and a key that carries too
/// much produces no saving at all while looking like one. Both failures are silent, and neither is
/// visible from the assertion "the key equals itself".
///
/// So every test below is a pair: take a key, change one thing about the document, and assert the
/// key moved — or, for `currentFrame`, that it did **not**, because the playhead has a fast path and
/// keying on it would defeat the whole gate on the one gesture that drives it hardest.
@MainActor
final class TimelineLayoutKeyLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// The view-side scalars, held constant so a test that changes the *document* is not also
    /// changing the geometry.
    private func key(_ manager: CanvasManager,
                     pixelsPerFrame: CGFloat = 30,
                     displayedFrameCount: Int = 24,
                     contentWidth: CGFloat = 720,
                     rowHeight: CGFloat = 34,
                     rulerHeight: CGFloat = 18,
                     drag: TimelineLayoutKey.DragKey? = nil) -> TimelineLayoutKey {
        TimelineLayoutKey.make(canvasManager: manager,
                               stackRows: manager.layerStackRows,
                               pixelsPerFrame: pixelsPerFrame,
                               displayedFrameCount: displayedFrameCount,
                               contentWidth: contentWidth,
                               rowHeight: rowHeight,
                               rulerHeight: rulerHeight,
                               drag: drag).key
    }

    private func manager(layerCount: Int = 2) -> CanvasManager {
        CanvasFixture.manager(layerCount: layerCount)
    }

    // MARK: - The gate holds when nothing moved

    func testTwoKeysOverAnUnchangedDocumentAreEqual() {
        let m = manager()
        XCTAssertEqual(key(m), key(m),
                       "Building the key twice with nothing between must be equal — otherwise the gate never hits and this is all cost")
    }

    /// **The one input deliberately left out.** Scrubbing writes `currentFrame` on every `.changed`
    /// sample; the playhead is its own subview and nothing else on the track moves with it. A key
    /// that carried it would move on every sample of the gesture this gate exists to make cheap.
    func testMovingThePlayheadDoesNotMoveTheKey() {
        let m = manager()
        let before = key(m)
        m.goToFrame(7)
        XCTAssertEqual(m.currentFrame, 7, "Fixture: the playhead really moved")
        XCTAssertEqual(before, key(m),
                       "A scrub takes the playhead fast path — see `Coordinator.movePlayhead`")
    }

    // MARK: - …and moves for everything the layout draws

    func testAddingACelMovesTheKey() {
        let m = manager()
        let before = key(m)
        XCTAssertTrue(m.addCel(layerIndex: 0, startFrame: 20, frameCount: 2), "Fixture: the cel should be added")
        XCTAssertNotEqual(before, key(m), "A new block has to be laid out")
    }

    func testMovingACelMovesTheKey() {
        let m = manager()
        XCTAssertTrue(m.addCel(layerIndex: 0, startFrame: 20, frameCount: 2))
        let before = key(m)
        guard let index = m.layers[0].cels.firstIndex(where: { $0.startFrame == 20 }) else {
            return XCTFail("Fixture: the cel should be findable")
        }
        m.moveCel(layerIndex: 0, celIndex: index, newStartFrame: 18)
        XCTAssertNotEqual(before, key(m), "A block that changed frames is a block drawn somewhere else")
    }

    func testResizingACelMovesTheKey() {
        let m = manager()
        let before = key(m)
        m.resizeCelRightEdge(layerIndex: 0, celIndex: 0, newEndFrame: 30)
        XCTAssertNotEqual(before, key(m), "A block that changed length is a block drawn at a different width")
    }

    /// A regenerated thumbnail replaces the object outright, so identity is the right comparison —
    /// and it has to be *in* the key, because the block draws it.
    func testANewCelThumbnailMovesTheKey() {
        let m = manager()
        let before = key(m)
        m.layers[0].cels[0].thumbnail = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 8))
        XCTAssertNotEqual(before, key(m), "The picture on the block is part of what the row draws")
    }

    func testSwitchingTheCurrentLayerMovesTheKey() {
        let m = manager()
        m.currentLayerIndex = 0
        let before = key(m)
        m.currentLayerIndex = 1
        XCTAssertNotEqual(before, key(m), "The current layer's blocks are drawn highlighted")
    }

    func testAddingALayerMovesTheKey() {
        let m = manager()
        let before = key(m)
        m.addLayer()
        XCTAssertNotEqual(before, key(m), "A new track is a new row")
    }

    func testCollapsingAFolderMovesTheKey() {
        let m = manager()
        guard let folderID = m.groupLayers(m.layers[1].id, with: m.layers[0].id, name: "Group") else {
            return XCTFail("Fixture: the group should form")
        }
        guard let folderIndex = m.folders.firstIndex(where: { $0.id == folderID }) else {
            return XCTFail("Fixture: the folder should exist")
        }
        m.folders[folderIndex].isExpanded = true
        let before = key(m)
        m.folders[folderIndex].isExpanded = false
        XCTAssertNotEqual(before, key(m), "Collapsing hides rows, which is a different set of rows to lay out")
    }

    /// The folder band spans its descendants' cels, so it moves when a *child's* block does even
    /// though the folder holds no cels itself. This is the field most likely to be forgotten.
    func testACelMovingInsideAFolderMovesTheFoldersHalfOfTheKey() {
        let m = manager()
        guard m.groupLayers(m.layers[1].id, with: m.layers[0].id, name: "Group") != nil else {
            return XCTFail("Fixture: the group should form")
        }
        XCTAssertTrue(m.addCel(layerIndex: 0, startFrame: 20, frameCount: 2))
        let before = key(m)
        XCTAssertFalse(before.folders.isEmpty, "Fixture: there should be a folder row to compare")

        guard let index = m.layers[0].cels.firstIndex(where: { $0.startFrame == 20 }) else {
            return XCTFail("Fixture: the cel should be findable")
        }
        m.resizeCelRightEdge(layerIndex: 0, celIndex: index, newEndFrame: 30)
        let after = key(m)
        XCTAssertNotEqual(before, after)
        XCTAssertNotEqual(before.folders, after.folders,
                          "…and specifically in the folder's span, not only in the track under it")
    }

    func testSettingALoopRangeMovesTheKey() {
        let m = manager()
        let before = key(m)
        m.loopStartFrame = 2
        m.loopEndFrame = 6
        XCTAssertNotEqual(before, key(m), "The loop band is drawn on the ruler")
    }

    func testZoomingTheTrackMovesTheKey() {
        let m = manager()
        XCTAssertNotEqual(key(m, pixelsPerFrame: 30), key(m, pixelsPerFrame: 45),
                          "Every block's width and x come from pixelsPerFrame")
    }

    func testGrowingTheDisplayedFrameCountMovesTheKey() {
        let m = manager()
        XCTAssertNotEqual(key(m, displayedFrameCount: 24), key(m, displayedFrameCount: 48),
                          "Scrolling right extends the track and the ruler")
    }

    func testResizingTheTrackMovesTheKey() {
        let m = manager()
        XCTAssertNotEqual(key(m, contentWidth: 720), key(m, contentWidth: 900),
                          "A rotation or a Split View resize changes every row's width")
        XCTAssertNotEqual(key(m, rowHeight: 34), key(m, rowHeight: 40))
        XCTAssertNotEqual(key(m, rulerHeight: 18), key(m, rulerHeight: 24))
    }

    /// A drag repositions every *other* block in the row to preview the gap, so the whole preview
    /// state is an input — and each field of it separately, since a drag that only slides sideways
    /// changes just one.
    func testEveryFieldOfADragMovesTheKey() {
        let m = manager()
        let celID = m.layers[0].cels[0].id
        let base = TimelineLayoutKey.DragKey(celID: celID, sourceLayerIndex: 0, targetLayerIndex: 0,
                                             targetStartFrame: 4, frameCount: 3)
        XCTAssertNotEqual(key(m, drag: nil), key(m, drag: base), "Picking a block up starts a preview")

        var moved = base
        XCTAssertNotEqual(key(m, drag: base),
                          key(m, drag: TimelineLayoutKey.DragKey(celID: celID, sourceLayerIndex: 0,
                                                                 targetLayerIndex: 1, targetStartFrame: 4,
                                                                 frameCount: 3)),
                          "Crossing to another row moves the preview to that row")
        moved = TimelineLayoutKey.DragKey(celID: celID, sourceLayerIndex: 0, targetLayerIndex: 0,
                                          targetStartFrame: 9, frameCount: 3)
        XCTAssertNotEqual(key(m, drag: base), key(m, drag: moved),
                          "Sliding along the row re-previews which blocks move aside")
    }

    // MARK: - The ruler's dirty rect

    func testTheRulerDrawsOnlyTheColumnsTheDirtyRectTouches() {
        // 30pt columns, a rect covering points 300..<600, i.e. columns 10..<20 — plus the one frame
        // of slack on each side that stops a label being clipped at a tile boundary.
        let range = TimelineRulerClip.frames(in: CGRect(x: 300, y: 0, width: 300, height: 18),
                                             pixelsPerFrame: 30, frameCount: 300)
        XCTAssertEqual(range, 9..<21)
        XCTAssertEqual(range.count, 12, "Twelve labels for a 300-frame scene, not three hundred")
    }

    func testTheClipIsClampedToTheSceneAtBothEnds() {
        XCTAssertEqual(TimelineRulerClip.frames(in: CGRect(x: 0, y: 0, width: 90, height: 18),
                                                pixelsPerFrame: 30, frameCount: 300),
                       0..<4,
                       "The slack must not produce a negative first frame")
        XCTAssertEqual(TimelineRulerClip.frames(in: CGRect(x: 0, y: 0, width: 10_000, height: 18),
                                                pixelsPerFrame: 30, frameCount: 12),
                       0..<12,
                       "A rect wider than the scene draws the scene and stops")
    }

    /// The whole ruler invalidated is the whole ruler drawn — the clip is not allowed to turn a full
    /// redraw into a partial one, which would leave numbers missing on screen.
    func testAFullBoundsRectStillDrawsEveryFrame() {
        let frameCount = 300
        let width = CGFloat(frameCount) * 30
        XCTAssertEqual(TimelineRulerClip.frames(in: CGRect(x: 0, y: 0, width: width, height: 18),
                                                pixelsPerFrame: 30, frameCount: frameCount),
                       0..<frameCount)
    }

    func testDegenerateInputsDrawNothingRatherThanCrashing() {
        XCTAssertEqual(TimelineRulerClip.frames(in: .zero, pixelsPerFrame: 30, frameCount: 300), 0..<0)
        XCTAssertEqual(TimelineRulerClip.frames(in: CGRect(x: 0, y: 0, width: 300, height: 18),
                                                pixelsPerFrame: 0, frameCount: 300), 0..<0)
        XCTAssertEqual(TimelineRulerClip.frames(in: CGRect(x: 0, y: 0, width: 300, height: 18),
                                                pixelsPerFrame: 30, frameCount: 0), 0..<0)
        XCTAssertEqual(TimelineRulerClip.frames(in: CGRect(x: 10_000, y: 0, width: 300, height: 18),
                                                pixelsPerFrame: 30, frameCount: 12), 0..<0,
                       "A rect entirely past the end of the scene draws nothing")
    }
}
