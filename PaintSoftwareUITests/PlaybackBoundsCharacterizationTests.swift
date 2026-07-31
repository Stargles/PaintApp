import XCTest
import UIKit

/// Characterization tests for `CanvasManager`'s playback bounds — `playbackStartFrame`,
/// `playbackEndFrame`, `playbackEntryFrame()` and `advancePlayback()`.
///
/// The one rule the whole group rests on: **an unset loop marker stands in for the scene's own
/// boundary**, the first frame for a missing loop start and the last frame for a missing loop end.
/// That substitution is what lets looping and normal playback share a single advance rule — wrap at
/// the end boundary back to the start boundary when looping, stop there when not — instead of each
/// mode needing its own special case for whether the markers happen to be set. Pinned here because
/// the substitution is invisible at the call sites: nothing in `advancePlayback` mentions markers,
/// so a change to `effectiveLoopRange` or to `hasLoopBoundary` could silently move where playback
/// stops.
///
/// See `CanvasManagerTestSupport.swift` for why these compile as plain unit tests inside the UI
/// test target.
final class PlaybackBoundsCharacterizationTests: XCTestCase {

    /// A manager with one layer and an explicit scene length — the fixture's default is 12 frames,
    /// which these tests shorten so the boundary arithmetic is easy to read.
    private func manager(sceneFrameCount: Int = 5) -> CanvasManager {
        let manager = CanvasFixture.manager()
        manager.sceneFrameCount = sceneFrameCount
        return manager
    }

    /// Runs playback from the current frame until it stops or `limit` steps elapse, returning the
    /// frames visited (excluding the starting frame) and whether it stopped on its own.
    private func play(_ manager: CanvasManager, steps limit: Int) -> (frames: [Int], stopped: Bool) {
        var frames: [Int] = []
        for _ in 0..<limit {
            guard manager.advancePlayback() else { return (frames, true) }
            frames.append(manager.currentFrame)
        }
        return (frames, false)
    }

    // MARK: - Bounds with no markers set

    func testWithNoMarkersTheBoundsAreTheWholeScene() {
        let manager = self.manager(sceneFrameCount: 5)

        XCTAssertFalse(manager.hasLoopBoundary)
        XCTAssertEqual(manager.playbackStartFrame, 0, "A missing loop start stands in as the first frame")
        XCTAssertEqual(manager.playbackEndFrame, 4, "…and a missing loop end as the last frame")
    }

    func testWithNoMarkersAndAnEmptySceneTheBoundsCollapseToFrameZero() {
        let manager = self.manager(sceneFrameCount: 0)

        XCTAssertEqual(manager.playbackStartFrame, 0)
        XCTAssertEqual(manager.playbackEndFrame, 0, "`max(sceneFrameCount - 1, 0)` must not go negative")
    }

    // MARK: - Bounds with one marker set

    // These assign `loopStartFrame`/`loopEndFrame` directly rather than going through
    // `setLoopStart`/`setLoopEnd`: those two materialize *both* markers (each fills the other in
    // from the scene bounds so the pair stays ordered), so neither can produce a genuinely
    // half-set range — which is exactly the state the substitution rule exists for. It is reachable
    // from a project loaded with only one marker persisted, and from `clearLoopRange` plus a single
    // marker drag in a future editor path.

    func testOnlyASetLoopStartLeavesTheEndAtTheLastFrame() {
        let manager = self.manager(sceneFrameCount: 5)
        manager.loopStartFrame = 2

        XCTAssertTrue(manager.hasLoopBoundary, "One marker is enough to count as a boundary")
        XCTAssertEqual(manager.playbackStartFrame, 2)
        XCTAssertEqual(manager.playbackEndFrame, 4, "The unset end marker is the scene's last frame, not frame 2")
    }

    func testOnlyASetLoopEndLeavesTheStartAtTheFirstFrame() {
        let manager = self.manager(sceneFrameCount: 5)
        manager.loopEndFrame = 3

        XCTAssertTrue(manager.hasLoopBoundary)
        XCTAssertEqual(manager.playbackStartFrame, 0, "The unset start marker is frame 0")
        XCTAssertEqual(manager.playbackEndFrame, 3)
    }

    /// The setters' own behaviour, pinned alongside: setting one marker fills the other in from the
    /// scene bounds, which is why the tests above have to bypass them.
    func testSettingOneMarkerThroughTheSettersMaterializesTheOther() {
        let manager = self.manager(sceneFrameCount: 5)
        manager.setLoopStart(2)

        XCTAssertEqual(manager.loopStartFrame, 2)
        XCTAssertEqual(manager.loopEndFrame, 4, "Filled in from the scene's last frame")
    }

    func testClearingTheMarkersReturnsTheBoundsToTheWholeScene() {
        let manager = self.manager(sceneFrameCount: 5)
        manager.setLoopStart(1)
        manager.setLoopEnd(2)
        manager.clearLoopRange()

        XCTAssertFalse(manager.hasLoopBoundary)
        XCTAssertEqual(manager.playbackStartFrame, 0)
        XCTAssertEqual(manager.playbackEndFrame, 4)
    }

    // MARK: - advancePlayback: looping on

    func testLoopingWrapsAtTheSceneEndWhenNoMarkersAreSet() {
        let manager = self.manager(sceneFrameCount: 4)
        manager.isLoopEnabled = true
        manager.currentFrame = 2

        let (frames, stopped) = play(manager, steps: 4)

        XCTAssertFalse(stopped, "Looping playback never reports stop")
        XCTAssertEqual(frames, [3, 0, 1, 2], "The unset markers make the wrap run 3 → 0")
    }

    func testLoopingWrapsAtTheLoopEndBackToTheLoopStart() {
        let manager = self.manager(sceneFrameCount: 8)
        manager.isLoopEnabled = true
        manager.setLoopStart(2)
        manager.setLoopEnd(4)
        manager.currentFrame = 3

        let (frames, stopped) = play(manager, steps: 4)

        XCTAssertFalse(stopped)
        XCTAssertEqual(frames, [4, 2, 3, 4], "Playback stays inside 2...4 and never reaches frame 7")
    }

    func testLoopingWithOnlyALoopStartWrapsBackToItAtTheSceneEnd() {
        let manager = self.manager(sceneFrameCount: 4)
        manager.isLoopEnabled = true
        manager.loopStartFrame = 2
        manager.currentFrame = 2

        let (frames, _) = play(manager, steps: 3)

        XCTAssertEqual(frames, [3, 2, 3], "End is the scene's last frame; start is the marker")
    }

    func testLoopingWithOnlyALoopEndWrapsBackToFrameZero() {
        let manager = self.manager(sceneFrameCount: 8)
        manager.isLoopEnabled = true
        manager.loopEndFrame = 2
        manager.currentFrame = 1

        let (frames, _) = play(manager, steps: 3)

        XCTAssertEqual(frames, [2, 0, 1], "Start is frame 0; end is the marker")
    }

    /// A one-frame loop range is the degenerate case of the wrap: `currentFrame < end` is already
    /// false, so every step re-enters the same frame rather than advancing off it.
    func testAOneFrameLoopRangeHoldsThePlayheadStill() {
        let manager = self.manager(sceneFrameCount: 8)
        manager.isLoopEnabled = true
        manager.setLoopStart(3)
        manager.setLoopEnd(3)
        manager.currentFrame = 3

        let (frames, stopped) = play(manager, steps: 3)

        XCTAssertFalse(stopped)
        XCTAssertEqual(frames, [3, 3, 3])
    }

    /// Parked outside the loop range with looping on, the first step snaps into the range rather
    /// than continuing forward — the `currentFrame < end` guard fails immediately past the end.
    func testLoopingFromPastTheLoopEndSnapsBackToTheLoopStart() {
        let manager = self.manager(sceneFrameCount: 8)
        manager.isLoopEnabled = true
        manager.setLoopStart(2)
        manager.setLoopEnd(4)
        manager.currentFrame = 6

        XCTAssertTrue(manager.advancePlayback())
        XCTAssertEqual(manager.currentFrame, 2)
    }

    /// …but parked *before* the loop start it plays forward into the range, because the guard only
    /// looks at the end boundary.
    func testLoopingFromBeforeTheLoopStartPlaysForwardIntoTheRange() {
        let manager = self.manager(sceneFrameCount: 8)
        manager.isLoopEnabled = true
        manager.setLoopStart(3)
        manager.setLoopEnd(5)
        manager.currentFrame = 0

        let (frames, _) = play(manager, steps: 6)

        XCTAssertEqual(frames, [1, 2, 3, 4, 5, 3], "It walks up to the end boundary, then wraps to the start")
    }

    // MARK: - advancePlayback: looping off

    func testWithLoopingOffPlaybackStopsAtTheLastFrame() {
        let manager = self.manager(sceneFrameCount: 4)
        manager.isLoopEnabled = false
        manager.currentFrame = 2

        let (frames, stopped) = play(manager, steps: 5)

        XCTAssertTrue(stopped, "Running off the end is the only case that returns false")
        XCTAssertEqual(frames, [3])
        XCTAssertEqual(manager.currentFrame, 3, "A stop leaves the playhead parked on the end frame")
    }

    /// The markers still bound playback with looping off — they are a range, not a loop-only
    /// feature — so playback stops at the loop end instead of the scene's last frame.
    func testWithLoopingOffPlaybackStillStopsAtTheLoopEnd() {
        let manager = self.manager(sceneFrameCount: 8)
        manager.isLoopEnabled = false
        manager.setLoopStart(1)
        manager.setLoopEnd(3)
        manager.currentFrame = 2

        let (frames, stopped) = play(manager, steps: 5)

        XCTAssertTrue(stopped)
        XCTAssertEqual(frames, [3], "Stops at the marker, not at frame 7")
    }

    func testWithLoopingOffAdvancingFromTheEndFrameReportsStopWithoutMoving() {
        let manager = self.manager(sceneFrameCount: 4)
        manager.isLoopEnabled = false
        manager.currentFrame = 3

        XCTAssertFalse(manager.advancePlayback())
        XCTAssertEqual(manager.currentFrame, 3, "A refused advance must not move the playhead")
    }

    // MARK: - playbackEntryFrame

    func testPressingPlayAtTheEndReplaysFromTheStart() {
        let manager = self.manager(sceneFrameCount: 5)
        manager.currentFrame = 4

        XCTAssertEqual(manager.playbackEntryFrame(), 0,
                       "Parked on the end frame, play restarts rather than stopping on the spot")
    }

    func testPressingPlayMidSceneResumesFromWhereThePlayheadIs() {
        let manager = self.manager(sceneFrameCount: 5)
        manager.currentFrame = 2

        XCTAssertEqual(manager.playbackEntryFrame(), 2)
    }

    func testPressingPlayOutsideTheLoopRangeEntersAtTheLoopStart() {
        let manager = self.manager(sceneFrameCount: 8)
        manager.setLoopStart(3)
        manager.setLoopEnd(5)

        manager.currentFrame = 1
        XCTAssertEqual(manager.playbackEntryFrame(), 3, "Before the range")

        manager.currentFrame = 5
        XCTAssertEqual(manager.playbackEntryFrame(), 3, "On the end boundary")

        manager.currentFrame = 7
        XCTAssertEqual(manager.playbackEntryFrame(), 3, "Past the range")

        manager.currentFrame = 4
        XCTAssertEqual(manager.playbackEntryFrame(), 4, "…but inside it, the playhead stands")
    }

    /// The entry frame ignores `isLoopEnabled` entirely — only the markers matter, which is what
    /// makes pressing play with looping off still start inside the marked range.
    func testTheEntryFrameIsTheSameWhetherOrNotLoopingIsEnabled() {
        for enabled in [true, false] {
            let manager = self.manager(sceneFrameCount: 8)
            manager.isLoopEnabled = enabled
            manager.setLoopStart(2)
            manager.setLoopEnd(6)
            manager.currentFrame = 0

            XCTAssertEqual(manager.playbackEntryFrame(), 2, "isLoopEnabled = \(enabled)")
        }
    }
}
