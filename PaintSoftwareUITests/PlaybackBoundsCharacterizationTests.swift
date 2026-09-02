import XCTest
import UIKit
import Combine

/// Characterization tests for `CanvasManager`'s playback bounds — `playbackStartFrame`,
/// `playbackEndFrame`, `playbackEntryFrame()` and `advancePlayback()`.
///
/// The one rule the whole group rests on: **an unset loop marker stands in for the animation's own
/// boundary**, the first frame for a missing loop start and the last *drawn* frame for a missing
/// loop end. That substitution is what lets looping and normal playback share a single advance
/// rule — wrap at the end boundary back to the start boundary when looping, stop there when not —
/// instead of each mode needing its own special case for whether the markers happen to be set.
/// Pinned here because the substitution is invisible at the call sites: nothing in
/// `advancePlayback` mentions markers, so a change to `effectiveLoopRange`, to `hasLoopBoundary` or
/// to `contentEndFrame` could silently move where playback stops.
///
/// "Last drawn frame" is `contentEndFrame`, not `sceneFrameCount`. The two are different numbers
/// and the distinction is the whole point: `sceneFrameCount` is the laid-out length of the track,
/// which starts at 12 and only ratchets upward, so keying playback to it made a short animation
/// run out over empty frames before wrapping. `theBoundsFollowTheContent...` below is the pair of
/// tests that pins that apart; everything above them keeps content and scene length equal so the
/// marker arithmetic stays easy to read.
///
/// See `CanvasManagerTestSupport.swift` for why these compile as plain unit tests inside the UI
/// test target.
final class PlaybackBoundsCharacterizationTests: XCTestCase {

    /// A manager with one layer holding a single block that spans exactly `sceneFrameCount` frames.
    ///
    /// Both halves matter. `CanvasFixture.manager()` gives the layer a cel covering the default
    /// 12-frame scene, so shortening `sceneFrameCount` alone would leave a 12-frame *block* behind
    /// and every bound here would read 11 — the cel has to be trimmed with it.
    private func manager(sceneFrameCount: Int = 5) -> CanvasManager {
        let manager = CanvasFixture.manager()
        manager.sceneFrameCount = sceneFrameCount
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: max(sceneFrameCount, 1))])
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

    func testWithNoMarkersTheBoundsAreTheWholeAnimation() {
        let manager = self.manager(sceneFrameCount: 5)

        XCTAssertFalse(manager.hasLoopBoundary)
        XCTAssertEqual(manager.playbackStartFrame, 0, "A missing loop start stands in as the first frame")
        XCTAssertEqual(manager.playbackEndFrame, 4, "…and a missing loop end as the last drawn frame")
    }

    func testWithNoMarkersAndAnEmptySceneTheBoundsCollapseToFrameZero() {
        let manager = self.manager(sceneFrameCount: 0)

        XCTAssertEqual(manager.playbackStartFrame, 0)
        XCTAssertEqual(manager.playbackEndFrame, 0, "`max(contentEndFrame - 1, 0)` must not go negative")
    }

    func testWithNoLayersAtAllTheBoundsCollapseToFrameZero() {
        let manager = CanvasManager()
        manager.canvasSize = CanvasFixture.canvasSize

        XCTAssertEqual(manager.contentEndFrame, 0, "Nothing drawn anywhere")
        XCTAssertEqual(manager.playbackEndFrame, 0, "…and no negative bound comes out of it")
    }

    // MARK: - Content end vs. scene length
    //
    // The distinction this whole change turns on. `sceneFrameCount` is the laid-out track; the
    // animation is however far the blocks actually reach.

    func testTheBoundsFollowTheContentNotTheLaidOutSceneLength() {
        let manager = self.manager(sceneFrameCount: 12)
        // A three-frame animation sitting in a track still laid out to 12 frames — the exact shape
        // that used to loop from frame 12.
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])

        XCTAssertEqual(manager.sceneFrameCount, 12, "The track is untouched…")
        XCTAssertEqual(manager.contentEndFrame, 3, "…but the animation is three frames long")
        XCTAssertEqual(manager.playbackEndFrame, 2, "Playback ends on the last drawn frame")
    }

    /// **Scrubbing is not authoring.** The owner asked to be able to move the playhead anywhere in
    /// the timeline, and the first fix let `goToFrame` raise `sceneFrameCount` to admit the frame.
    /// That looked safe — the field is documented as the laid-out track, and playback keys off
    /// `contentEndFrame`, which the test above pins. It was not safe, because `sceneFrameCount` is
    /// also **an input to cel creation**: every constructor mints a new layer's first cel with
    /// `frameCount: max(sceneFrameCount, 1)`. So the inflated track became a real 200-frame cel on
    /// the next layer, that cel became `contentEndFrame`, and playback ran out over empty frames
    /// again — the same bug at a bigger number, saved into the manifest.
    ///
    /// Both halves are asserted because either alone passes under the bug: the first would pass if
    /// `goToFrame` refused the frame (the original complaint), the second if it ratcheted.
    func testScrubbingPastTheSceneEndMovesThePlayheadWithoutLengtheningTheAnimation() {
        let manager = self.manager(sceneFrameCount: 12)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])

        manager.goToFrame(200)
        XCTAssertEqual(manager.currentFrame, 200, "The playhead goes where it is sent…")
        XCTAssertEqual(manager.sceneFrameCount, 12, "…without the track growing to meet it")

        manager.addLayer()
        XCTAssertEqual(manager.layers.last?.cels.first?.frameCount, 12,
                       "A layer added out there is sized by the scene, not by where the playhead is parked")
        XCTAssertEqual(manager.contentEndFrame, 12, "…so the animation is still as long as its content")
        XCTAssertEqual(manager.playbackEndFrame, 11, "…and playback does not run out over empty track")
    }

    func testTheContentEndIsTheFurthestBlockAcrossEveryLayer() {
        let manager = self.manager(sceneFrameCount: 12)
        manager.addLayer()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 4, length: 2)])

        XCTAssertEqual(manager.contentEndFrame, 6, "Layer 1's block reaches furthest, to frame 5")
        XCTAssertEqual(manager.playbackEndFrame, 5)
    }

    /// A gap before the last block counts as part of the animation: the bound is the furthest
    /// block's *end*, not the total number of drawn frames.
    func testATrailingBlockAfterAGapStillSetsTheEnd() {
        let manager = self.manager(sceneFrameCount: 12)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 2), (start: 7, length: 1)])

        XCTAssertEqual(manager.contentEndFrame, 8)
        XCTAssertEqual(manager.playbackEndFrame, 7)
    }

    func testLoopingWithNoMarkersWrapsAtTheLastBlockNotTheSceneEnd() {
        let manager = self.manager(sceneFrameCount: 12)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])
        manager.isLoopEnabled = true
        manager.currentFrame = 1

        let (frames, stopped) = play(manager, steps: 4)

        XCTAssertFalse(stopped)
        XCTAssertEqual(frames, [2, 0, 1, 2], "Wraps 2 → 0; frame 3 onward is empty track")
    }

    func testWithLoopingOffPlaybackStopsAtTheLastBlock() {
        let manager = self.manager(sceneFrameCount: 12)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])
        manager.isLoopEnabled = false
        manager.currentFrame = 1

        let (frames, stopped) = play(manager, steps: 5)

        XCTAssertTrue(stopped)
        XCTAssertEqual(frames, [2], "Stops on the last drawn frame rather than running out to 11")
    }

    /// Markers win over the content: set them and they *are* the animation window, even when they
    /// reach past every block into the empty track.
    func testMarkersSetPastTheContentAreStillHonoured() {
        let manager = self.manager(sceneFrameCount: 12)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 3)])
        manager.setLoopStart(1)
        manager.setLoopEnd(9)

        XCTAssertEqual(manager.playbackStartFrame, 1)
        XCTAssertEqual(manager.playbackEndFrame, 9, "The window is the artist's call, not the content's")
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

    // MARK: - The clock
    //
    // The playhead is derived from elapsed wall time (`PlaybackClock`), not accumulated from tick
    // counts, so these drive a fake clock by hand rather than sleeping. `manager.playbackNow` is
    // the whole injection point; the real `Timer` is still scheduled by `play()` and is harmless
    // here because every tick's *effect* is read off the frozen clock, so a stray fire computes
    // zero frames due. Each test stops playback so no timer outlives it.

    /// A wall clock the test moves itself. Times are absolute so a sequence of asserts can be
    /// expressed as offsets from one epoch — advancing by deltas accumulates floating-point error
    /// into exactly the `floor` these tests are about.
    private final class FakeClock {
        var now: TimeInterval = 1_000
    }

    private func playingManager(fps: Int = 24,
                                sceneFrameCount: Int = 10) -> (CanvasManager, FakeClock) {
        let manager = self.manager(sceneFrameCount: sceneFrameCount)
        let clock = FakeClock()
        manager.fps = fps
        manager.playbackNow = { clock.now }
        manager.currentFrame = 0
        manager.play()
        return (manager, clock)
    }

    /// **(a)** The defect that made this stage worth doing: the old timer advanced one frame per
    /// fire, so a main thread busy for two frame intervals played the animation back in slow motion
    /// and the clock fell permanently behind. Two and a half intervals is two frames of animation.
    func testALateTickSkipsFramesInsteadOfStretchingTime() {
        let (manager, clock) = playingManager()
        let epoch = clock.now

        XCTAssertEqual(manager.currentFrame, 0, "Pressing play does not itself advance a frame")

        clock.now = epoch + 2.5 / 24.0
        manager.tickPlayback()
        XCTAssertEqual(manager.currentFrame, 2, "Two and a half frame intervals is two frames, not one")

        // Measured from the epoch every time, so the half-frame left on the table above is still
        // owed rather than discarded — this is the no-drift half of the same property.
        clock.now = epoch + 4.5 / 24.0
        manager.tickPlayback()
        XCTAssertEqual(manager.currentFrame, 4)

        manager.stopPlayback()
    }

    /// A tick that arrives before the next frame is due changes nothing. The tick source deliberately
    /// oversamples the frame rate, so this is the common case rather than an edge one.
    func testATickBeforeTheNextFrameIsDueDoesNothing() {
        let (manager, clock) = playingManager()
        let epoch = clock.now

        clock.now = epoch + 0.5 / 24.0
        manager.tickPlayback()

        XCTAssertEqual(manager.currentFrame, 0)
        XCTAssertTrue(manager.isPlaying)
        manager.stopPlayback()
    }

    /// **(b)** `1.0 / fps` used to be captured into the timer's interval when play was pressed, so a
    /// rate change mid-playback did nothing at all. The rate is now read at derivation time — and
    /// the clock is re-based on the change, which is what stops the new rate being applied
    /// retroactively to the whole elapsed span and jumping the playhead.
    func testAFrameRateChangeMidPlaybackTakesEffectWithoutMovingThePlayhead() {
        let (manager, clock) = playingManager(fps: 24)
        let epoch = clock.now

        clock.now = epoch + 1.5 / 24.0
        manager.tickPlayback()
        XCTAssertEqual(manager.currentFrame, 1)

        let changed = clock.now
        manager.fps = 12
        XCTAssertEqual(manager.currentFrame, 1, "The rate changed; the playhead did not move with it")

        clock.now = changed + 0.5 / 12.0
        manager.tickPlayback()
        XCTAssertEqual(manager.currentFrame, 1, "Half a frame at the new rate is still not a frame")

        clock.now = changed + 1.5 / 12.0
        manager.tickPlayback()
        XCTAssertEqual(manager.currentFrame, 2, "…and one frame at 12 fps is one frame, not the two "
                       + "the elapsed span would be worth if the new rate were applied to all of it")

        manager.stopPlayback()
    }

    /// **(c)** The half that no view could provide: playback is a fact about the document, so
    /// anything in the app — the background baker of RENDER §3.6 above all — can observe it.
    func testIsPlayingIsObservableOnTheModelAndAStopClearsIt() {
        let manager = self.manager()
        var seen: [Bool] = []
        let sink = manager.$isPlaying.dropFirst().sink { seen.append($0) }
        defer { sink.cancel() }

        XCTAssertFalse(manager.isPlaying)
        manager.play()
        XCTAssertTrue(manager.isPlaying)
        manager.stopPlayback()
        XCTAssertFalse(manager.isPlaying)

        XCTAssertEqual(seen, [true, false], "Both edges are published")
    }

    /// A second stop publishes nothing. `@Published` fires on every write, equal or not, and
    /// `stopPlayback` is called from several places that do not know whether playback was running.
    func testStoppingTwiceIsNotASecondChange() {
        let manager = self.manager()
        manager.play()
        manager.stopPlayback()

        var seen = 0
        let sink = manager.$isPlaying.dropFirst().sink { _ in seen += 1 }
        defer { sink.cancel() }
        manager.stopPlayback()

        XCTAssertEqual(seen, 0)
    }

    func testPlayEntersAtTheEntryFrameAndPressingItTwiceIsAStop() {
        let manager = self.manager(sceneFrameCount: 5)
        manager.setLoopStart(2)
        manager.setLoopEnd(4)
        manager.currentFrame = 0

        manager.togglePlayback()
        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(manager.currentFrame, 2, "Play enters the loop range, as `playbackEntryFrame` says")

        manager.togglePlayback()
        XCTAssertFalse(manager.isPlaying)
    }

    /// A touch that is about to become an edit stops playback, so the playhead cannot move out from
    /// under a gesture mid-stroke. Routed through `canvasInteractionBegan`, the app's one entry point
    /// for "a touch has landed on the canvas".
    func testACanvasTouchStopsPlayback() {
        let manager = self.manager()
        manager.play()

        manager.canvasInteractionBegan()

        XCTAssertFalse(manager.isPlaying)
    }

    /// Running off the end stops playback from inside the model. The view used to own that decision.
    func testPlaybackStopsItselfAtTheEndWithLoopingOff() {
        let (manager, clock) = playingManager(sceneFrameCount: 3)
        manager.isLoopEnabled = false

        clock.now += 10.0 / 24.0
        manager.tickPlayback()

        XCTAssertEqual(manager.currentFrame, 2, "Parked on the end frame")
        XCTAssertFalse(manager.isPlaying, "…and not still ticking against it")
    }

    // MARK: - advancePlayback(by:)

    /// The multi-frame advance is what a late tick spends, and it must be the single-frame rule
    /// applied that many times — not a second, parallel account of where playback wraps and stops.
    /// Every combination of the boundary cases the tests above pin, walked both ways.
    func testAdvancingByNIsExactlyNSingleAdvances() {
        let cases: [(loop: Bool, markers: (Int, Int)?, from: Int)] = [
            (true, nil, 0), (true, nil, 3), (true, (2, 4), 3), (true, (2, 4), 6),
            (true, (3, 5), 0), (true, (3, 3), 3), (false, nil, 0), (false, nil, 3),
            (false, (1, 3), 2), (false, (1, 3), 3)
        ]
        for (loop, markers, from) in cases {
            for count in 0...9 {
                let batched = self.manager(sceneFrameCount: 8)
                let stepped = self.manager(sceneFrameCount: 8)
                for manager in [batched, stepped] {
                    manager.isLoopEnabled = loop
                    if let markers {
                        manager.setLoopStart(markers.0)
                        manager.setLoopEnd(markers.1)
                    }
                    manager.currentFrame = from
                }

                let batchedRan = batched.advancePlayback(by: count)
                var steppedRan = true
                for _ in 0..<count where steppedRan { steppedRan = stepped.advancePlayback() }

                let label = "loop \(loop), markers \(String(describing: markers)), from \(from), count \(count)"
                XCTAssertEqual(batched.currentFrame, stepped.currentFrame, label)
                XCTAssertEqual(batchedRan, steppedRan, label)
            }
        }
    }

    /// A catch-up longer than the loop itself folds into the range instead of walking every frame of
    /// it. Same answer, bounded work.
    func testALongCatchUpFoldsIntoTheLoopRange() {
        let manager = self.manager(sceneFrameCount: 8)
        manager.isLoopEnabled = true
        manager.setLoopStart(2)
        manager.setLoopEnd(4)
        manager.currentFrame = 2

        XCTAssertTrue(manager.advancePlayback(by: 7))
        XCTAssertEqual(manager.currentFrame, 3, "Seven steps around a three-frame loop is one step")
    }

    // MARK: - PlaybackClock

    func testTheClockOwesNothingBeforeAFrameIntervalHasPassed() {
        var clock = PlaybackClock(startedAt: 100)

        XCTAssertEqual(clock.take(at: 100, fps: 24), 0)
        XCTAssertEqual(clock.take(at: 100 + 0.9 / 24.0, fps: 24), 0)
        XCTAssertEqual(clock.take(at: 100 + 1.0 / 24.0, fps: 24), 1)
    }

    /// The property a per-fire increment cannot have: what is owed is measured from the epoch, so a
    /// tick that arrives late does not push the following one late as well.
    func testTheClockDoesNotDrift() {
        var clock = PlaybackClock(startedAt: 0)
        // Ticks at 0.9, 1.1, 2.05 and 3.0 frame intervals — jittered around the rate, the way a
        // Timer actually fires — hand out 0, 1, 1 and 1: four frame intervals of wall time, four
        // frames.
        XCTAssertEqual(clock.take(at: 0.9 / 24.0, fps: 24), 0)
        XCTAssertEqual(clock.take(at: 1.1 / 24.0, fps: 24), 1)
        XCTAssertEqual(clock.take(at: 2.05 / 24.0, fps: 24), 1)
        XCTAssertEqual(clock.take(at: 3.0 / 24.0, fps: 24), 1)
        XCTAssertEqual(clock.framesConsumed, 3)
    }

    func testRebasingRestartsTheCountWithoutOwingAFrame() {
        var clock = PlaybackClock(startedAt: 0)
        XCTAssertEqual(clock.take(at: 5.0 / 24.0, fps: 24), 5)

        clock.rebase(at: 5.0 / 24.0)
        XCTAssertEqual(clock.framesConsumed, 0)
        XCTAssertEqual(clock.take(at: 5.0 / 24.0 + 0.9 / 12.0, fps: 12), 0,
                       "The elapsed span before the rebase is not re-divided by the new rate")
        XCTAssertEqual(clock.take(at: 5.0 / 24.0 + 1.0 / 12.0, fps: 12), 1)
    }

    /// A clock that jumps backwards (the system clock being set) owes nothing rather than going
    /// negative, and one that jumps forwards by an absurd amount is clamped rather than trapping in
    /// `Int(_:)`.
    func testTheClockSurvivesAWallClockThatJumps() {
        var clock = PlaybackClock(startedAt: 1_000)

        XCTAssertEqual(clock.take(at: 0, fps: 24), 0, "Backwards owes nothing")
        XCTAssertEqual(clock.take(at: .greatestFiniteMagnitude, fps: 24), Int.max / 2)
    }
}
