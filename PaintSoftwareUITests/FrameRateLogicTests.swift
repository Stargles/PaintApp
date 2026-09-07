import XCTest
import Combine

/// The document's frame rate as a thing the artist can change — KEYFRAMES.md §2.7 and §5, stage 7.
///
/// **What was already built before this stage, and is pinned elsewhere.** `PlaybackClock` takes `fps`
/// as an argument to `framesDue` rather than capturing `1/fps` when play is pressed, so a rate change
/// during playback is obeyed on the next tick and does not move the playhead —
/// `PlaybackBoundsCharacterizationTests.testAFrameRateChangeMidPlaybackTakesEffectWithoutMovingThePlayhead`
/// is that test and it predates this file. `ProjectSaveLogicTests` already round-trips `fps` through a
/// save. Neither is repeated here.
///
/// **What stage 7 added, and what this file is about**, is the half that was missing: nothing in the
/// app ever wrote `fps` except a load, so 24 was the only rate a document could have. That is a
/// *bound* and an *entry*, and both are stated on the model rather than in the timeline's view — a
/// rule a view holds is a rule the fast tier cannot see, which is the reason `KeyframeControl`'s whole
/// routing lives on `CanvasManager` and the same reason applies here.
final class FrameRateLogicTests: XCTestCase {

    private func manager() -> CanvasManager {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 5)])
        return manager
    }

    // MARK: - The bound

    /// **The clamp is on the property, so it holds for every writer including a load.**
    ///
    /// `fps` is a divisor on four paths and each of them carries its own `max(fps, 1)` because nothing
    /// upstream promised anything; this is that promise. A manifest holding `fps: 0` is reachable —
    /// TODO's standing "no document has to survive" permission covers a document that *looks* wrong,
    /// not one that divides by zero — and `ProjectStore.assemble` writes `manager.fps = manifest.fps`
    /// with no filter of its own.
    func testTheRateIsClampedIntoRangeWhateverIsWrittenToIt() {
        let manager = self.manager()

        manager.fps = 0
        XCTAssertEqual(manager.fps, CanvasManager.fpsRange.lowerBound,
                       "A zero rate would be a division by zero on four paths, not merely a slow document")

        manager.fps = -30
        XCTAssertEqual(manager.fps, CanvasManager.fpsRange.lowerBound)

        manager.fps = 10_000
        XCTAssertEqual(manager.fps, CanvasManager.fpsRange.upperBound)

        manager.fps = 12
        XCTAssertEqual(manager.fps, 12, "…and a rate inside the range is left exactly alone")
    }

    /// **No observer ever sees a rate outside the range, not even for an instant.**
    ///
    /// This is the assertion that forced the clamp onto the *setter*. Written the obvious way — a
    /// `didSet` on an ordinary `@Published var` — it read `[999, 60]`: `@Published` emits from
    /// `willSet`, so the raw value is delivered to every observer and the corrected one arrives
    /// behind it. That is a real transient, not a technicality; a `objectWillChange` sink is how the
    /// timeline's readout redraws.
    ///
    /// It observes `objectWillChange` rather than a projected `$fps`, which a computed property
    /// cannot have — and that is the publisher SwiftUI actually subscribes to, so it is the right
    /// operand anyway.
    func testAnOutOfRangeWriteIsNeverObservableAsAnOutOfRangeRate() {
        let manager = self.manager()
        var seen: [Int] = []
        let sink = manager.objectWillChange.sink { [weak manager] _ in
            // `objectWillChange` fires *before* the store, so the value read here is the previous
            // one — which is exactly the point: every value an observer can read, at any moment of
            // the write, is in range. Both ends are sampled.
            if let manager { seen.append(manager.fps) }
        }
        defer { sink.cancel() }

        manager.fps = 999
        seen.append(manager.fps)

        XCTAssertEqual(manager.fps, CanvasManager.fpsRange.upperBound)
        for value in seen {
            XCTAssertTrue(CanvasManager.fpsRange.contains(value),
                          "\(value) fps was observable during the write")
        }
        XCTAssertFalse(seen.isEmpty, "Setup: the write must actually have published something")
    }

    /// A write that the clamp turns into a no-op publishes nothing at all.
    ///
    /// Otherwise every out-of-range write at the ceiling would redraw the timeline and re-cut the
    /// playback timer for a rate that did not change — `rebasePlaybackClock` re-schedules the tick
    /// source, so a spurious call is not free during playback.
    func testAWriteTheClampTurnsIntoANoOpPublishesNothing() {
        let manager = self.manager()
        manager.fps = CanvasManager.fpsRange.upperBound

        var publishes = 0
        let sink = manager.objectWillChange.sink { _ in publishes += 1 }
        defer { sink.cancel() }

        manager.fps = 999
        XCTAssertEqual(publishes, 0, "60 clamped from 999 is still 60")

        manager.fps = 30
        XCTAssertEqual(publishes, 1, "…and a real change still publishes")
    }

    // MARK: - The entry, and the refusal

    /// **`stepFPS` refuses rather than clamps**, so the two answers are distinguishable.
    ///
    /// An artist at 2 fps pressing minus twice should land on 1 and then be told no. Clamping instead
    /// would land on 1 twice, which is a button that looks broken — the same complaint §5.24 of
    /// LASSO_MOVE settled for an empty lasso and the same one behind this repo's filed
    /// "a refusal with no notice".
    func testSteppingRefusesAtEachEndRatherThanClampingSilently() {
        let manager = self.manager()

        manager.fps = CanvasManager.fpsRange.lowerBound
        XCTAssertFalse(manager.stepFPS(by: -1), "There is nowhere below the floor to go, and it says so")
        XCTAssertEqual(manager.fps, CanvasManager.fpsRange.lowerBound)
        XCTAssertTrue(manager.stepFPS(by: 1), "…while the other direction is still open")
        XCTAssertEqual(manager.fps, CanvasManager.fpsRange.lowerBound + 1)

        manager.fps = CanvasManager.fpsRange.upperBound
        XCTAssertFalse(manager.stepFPS(by: 1))
        XCTAssertEqual(manager.fps, CanvasManager.fpsRange.upperBound)
        XCTAssertTrue(manager.stepFPS(by: -1))
        XCTAssertEqual(manager.fps, CanvasManager.fpsRange.upperBound - 1)
    }

    /// A step that would jump clean over the far end is refused whole rather than clamped to it.
    ///
    /// The panel only ever steps by one, so this is about the rule rather than about the button: a
    /// refusal that quietly does *part* of what was asked is the worst of the three answers.
    func testAStepThatWouldLeapPastTheEndIsRefusedWhole() {
        let manager = self.manager()
        manager.fps = 24

        XCTAssertFalse(manager.stepFPS(by: 100))
        XCTAssertEqual(manager.fps, 24, "Not 60 — the whole step was refused, not trimmed to fit")

        XCTAssertFalse(manager.stepFPS(by: -100))
        XCTAssertEqual(manager.fps, 24)
    }

    /// **The affordances the panel disables itself from, stated on the model.**
    ///
    /// This is the assertion that fails if the refusal stops being *visible* — the arrows read these
    /// to grey themselves out, and a control that stays live while refusing is the shape this repo
    /// has filed twice. It cannot see the greying itself (that is
    /// `FrameRateUITests.testTheFrameRatePanelRefusesVisiblyAtTheFloor`); what it can see is that the
    /// two answers exist and follow the bounds rather than being hard-coded true.
    func testTheStepAffordancesFollowTheBoundsAndNotTheOtherWayAround() {
        let manager = self.manager()

        manager.fps = CanvasManager.fpsRange.lowerBound
        XCTAssertFalse(manager.canDecreaseFPS, "At the floor, the minus arrow has nowhere to go")
        XCTAssertTrue(manager.canIncreaseFPS)

        manager.fps = CanvasManager.fpsRange.upperBound
        XCTAssertTrue(manager.canDecreaseFPS)
        XCTAssertFalse(manager.canIncreaseFPS)

        manager.fps = 24
        XCTAssertTrue(manager.canDecreaseFPS)
        XCTAssertTrue(manager.canIncreaseFPS)
    }

    /// Every preset is a rate the document may actually be set to.
    ///
    /// A preset outside the range would be a button that clamps to something else on press — which is
    /// the silent-clamp defect reached through the one door the arrows cannot cover, since presets are
    /// never disabled.
    func testEveryPresetIsInsideTheRangeAndLandsExactly() {
        let manager = self.manager()

        XCTAssertFalse(CanvasManager.fpsPresets.isEmpty)
        for rate in CanvasManager.fpsPresets {
            XCTAssertTrue(CanvasManager.fpsRange.contains(rate), "\(rate) fps is offered but out of range")
            manager.fps = rate
            XCTAssertEqual(manager.fps, rate, "\(rate) fps is offered and must land on itself")
        }
        XCTAssertTrue(CanvasManager.fpsPresets.contains(24), "24 is where a document starts")
        XCTAssertTrue(CanvasManager.fpsPresets.contains { $0 < 24 },
                      "§2.7 is about taking the document *below* 24, so at least one shortcut must")
    }

    // MARK: - What a rate change is, and is not

    /// **A rate change is not an undo step**, and that is the shipped precedent rather than an
    /// omission — `projectName`, `canvasBackgroundColor` and `isCanvasBackgroundVisible` are the other
    /// document-level settings and none of them registers one either.
    ///
    /// Pinned because the alternative is cheap to add and would be wrong: an undo stack that
    /// interleaves "un-set the frame rate" with "un-draw that line" is not the stack the artist
    /// pressed the button for.
    func testChangingTheRateRegistersNoUndoStep() {
        let manager = self.manager()
        let before = manager.history.undoStack.count
        let couldUndo = manager.canUndo

        manager.fps = 12
        manager.stepFPS(by: -1)

        XCTAssertEqual(manager.history.undoStack.count, before,
                       "A document setting is not an edit to the drawing")
        XCTAssertEqual(manager.canUndo, couldUndo,
                       "…and it does not light the undo button either. (The fixture's own cel layout "
                       + "is on the stack already, so this is a *change* test, not an emptiness one.)")
    }

    /// **A rate change does not move the playhead**, awake or asleep.
    ///
    /// The playing case is `PlaybackBoundsCharacterizationTests`'; this is the *stopped* one, which
    /// that test cannot reach — `rebasePlaybackClock` returns early when nothing is playing, and an
    /// early return is exactly the kind of thing that gets "simplified" into something that resets
    /// state it should not touch.
    func testChangingTheRateWhileStoppedMovesNothing() {
        let manager = self.manager()
        manager.goToFrame(3)
        XCTAssertFalse(manager.isPlaying, "Setup: this is the stopped case")

        manager.fps = 8

        XCTAssertEqual(manager.currentFrame, 3)
        XCTAssertFalse(manager.isPlaying, "…and it does not start playback either")
    }

    /// A rate the artist set survives a save and a reload **through the artist's own writer**.
    ///
    /// `ProjectSaveLogicTests` already round-trips `manager.fps = 18`, and this is not that test: it
    /// goes through `stepFPS`, which is the path the panel uses, and it checks the *clamp* survives
    /// the trip — a manifest is the one place an out-of-range rate can come from.
    func testARateReachedByTheStepperSurvivesTheManifestAndAnOutOfRangeOneIsHealedOnLoad() {
        let manager = self.manager()
        manager.fps = 12
        XCTAssertTrue(manager.stepFPS(by: -1))
        XCTAssertEqual(manager.fps, 11)

        let manifest = ProjectManifest(id: manager.projectID, name: manager.projectName,
                                       canvasWidth: 64, canvasHeight: 64, fps: manager.fps,
                                       layers: [], modifiedAt: Date())
        XCTAssertEqual(manifest.fps, 11)

        let reopened = self.manager()
        reopened.fps = manifest.fps
        XCTAssertEqual(reopened.fps, 11)

        // The healing half: a manifest from a build with no range cannot poison the document.
        reopened.fps = 0
        XCTAssertEqual(reopened.fps, CanvasManager.fpsRange.lowerBound)
    }
}
