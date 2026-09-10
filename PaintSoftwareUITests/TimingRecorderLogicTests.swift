import XCTest
import Foundation
import UIKit

/// **The timing recorder's model half** — KEYFRAMES.md §7, stage 10, the owner's brief of
/// 2026-09-10: *"as they put their pen on canvas, the recorder starts and the user can draw while
/// recording… The start and end of the stroke in the cel will be where the stroke started and ended
/// while that cel was active."*
///
/// Three separable things are pinned here and they are pinned apart on purpose:
///
///  * **The cut** — `TimingStrokeCut`, a pure function over a knot stream. Its operands are the
///    stream and the runs, and the only interesting property is that a boundary knot is in *both*
///    runs, because that is the seam.
///  * **The take** — a take whose whole product is ink has to end without telling the artist that
///    nothing was recorded, and without recording an undo step of its own over blocks the stroke's
///    own step already owns.
///  * **The undo** — one press takes back the ink on every cel the gesture crossed *and* the blocks
///    it had to make, which is the brief's second requirement.
///
/// **What is NOT here is the gesture**, and that is deliberate rather than a gap. Cutting a live
/// stroke is `StrokeCanvasView`'s, which is a `UIView` this target does not compile, and the thing
/// worth asserting about it is what an artist sees — so it is `TimingRecorderUITests`, driven from
/// a cold launch, and it asserts pixels.
@MainActor
final class TimingRecorderLogicTests: XCTestCase {

    // MARK: - Fixtures

    private final class FakeClock {
        var now: TimeInterval = 1_000
    }

    /// A document with one **vector** layer laid out as `blocks`, plus the fake wall clock a take is
    /// driven against. The layer is active and the undo stack is empty, so every count below starts
    /// from zero.
    private func manager(blocks: [(start: Int, length: Int)] = [(start: 0, length: 12)])
        -> (manager: CanvasManager, clock: FakeClock) {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        setVectorCels(manager, blocks)
        manager.currentLayerIndex = 0
        manager.currentFrame = 0
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        let clock = FakeClock()
        manager.playbackNow = { clock.now }
        return (manager, clock)
    }

    /// `CanvasFixture.setCelLayout`'s vector twin — it builds raster-only cels, and a cel with no
    /// `vector` is one a stroke cannot land on, so a fixture built with it would measure the
    /// refusal rather than the feature.
    private func setVectorCels(_ manager: CanvasManager, _ blocks: [(start: Int, length: Int)]) {
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        manager.layers[0].cels = blocks.sorted { $0.start < $1.start }.map {
            Cel(id: UUID(), startFrame: $0.start, frameCount: $0.length,
                raster: .empty(size: size), vector: .empty(size: size))
        }
    }

    private func target(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[0].id)
    }

    /// A straight run of `count` knots, one point apart, with a pressure that changes per knot so
    /// that "the same sample" is a claim about more than a position.
    private func line(_ count: Int) -> StrokeSamples {
        var samples = StrokeSamples(channels: .captured)
        for i in 0..<count {
            samples.append(VectorSample(x: CGFloat(i), y: CGFloat(i) * 2,
                                        pressure: 0.1 + CGFloat(i) * 0.05))
        }
        return samples
    }

    private func stroke(_ manager: CanvasManager, _ samples: StrokeSamples) -> VectorStroke {
        VectorStroke(brush: manager.selectedBrush,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 8, opacity: 1, samples: samples)
    }

    // MARK: - The cut: a boundary knot belongs to both runs

    /// **The seam, stated as the only thing that makes it invisible.**
    ///
    /// The two operands are *the last sample of one run* and *the first sample of the next*, taken
    /// off the runs the shipped function returns — not off the indices that were passed in. They are
    /// compared on position **and pressure**, because a shared position with a different pressure is
    /// two caps of different widths meeting, which is a step in the line rather than a gap.
    ///
    /// It could go red: cut the stream at `i` / `i+1` instead, which is the obvious reading of "split
    /// at index i", and consecutive runs no longer touch — the two arcs are then up to a whole
    /// `StrokePathFit.maximumKnotSpacing` apart, a twelve-point hole in the middle of a stroke.
    func testABoundaryKnotIsTheLastSampleOfOneRunAndTheFirstOfTheNext() {
        let samples = line(10)

        let runs = TimingStrokeCut.split(samples, at: [3, 6])

        XCTAssertEqual(runs.count, 3, "Two boundaries make three runs when every run has travelled")
        for (index, pair) in zip(runs, runs.dropFirst()).enumerated() {
            let ending = pair.0.samples[pair.0.samples.count - 1]
            let opening = pair.1.samples[0]
            XCTAssertEqual(ending.point, opening.point,
                           "Run \(index) must end exactly where run \(index + 1) begins, or the "
                           + "seam is a gap the length of one knot spacing")
            XCTAssertEqual(ending.pressure, opening.pressure, accuracy: 1e-9,
                           "…and at the same pressure, or the two end caps are different widths and "
                           + "the seam is a step in the line")
        }
    }

    /// **Nothing the artist drew is lost and nothing but the boundaries is drawn twice.**
    ///
    /// Operands: the concatenated run positions with each shared boundary counted once, against the
    /// gesture's own positions. This is the property that would catch a cut which dropped the knots
    /// between two runs, which is the failure mode a "split at i/i+1" implementation has at every
    /// boundary at once.
    func testTheRunsReassembleTheGestureWithEachBoundaryCountedOnce() {
        let samples = line(10)

        let runs = TimingStrokeCut.split(samples, at: [3, 6])

        var rebuilt: [CGPoint] = []
        for run in runs {
            for index in 0..<run.samples.count {
                let point = run.samples[index].point
                if rebuilt.last == point { continue }
                rebuilt.append(point)
            }
        }
        XCTAssertEqual(rebuilt, (0..<10).map { CGPoint(x: CGFloat($0), y: CGFloat($0) * 2) },
                       "Every knot the pen laid down is in exactly one run, in order")
    }

    /// **A run the pen did not travel on is dropped, and the runs after it keep their own slots.**
    ///
    /// This is the operand the type exists for. Two boundaries at the same index is a real gesture —
    /// the playhead crossing two cels between two knots — and the middle cel genuinely gets nothing.
    /// If `split` returned bare samples, the survivors would renumber and every later run would be
    /// committed into the wrong cel: ink on screen, in the wrong drawing, with nothing red anywhere.
    ///
    /// Operands: the surviving runs' `slot` values, against the slots the boundaries define.
    func testASkippedCelKeepsItsSlotSoLaterRunsStillNameTheirOwnCanvas() {
        let samples = line(10)

        let runs = TimingStrokeCut.split(samples, at: [3, 3])

        XCTAssertEqual(runs.map(\.slot), [0, 2],
                       "Slot 1 is the cel the pen crossed without travelling — it is dropped, and "
                       + "slot 2 is still slot 2")
        XCTAssertEqual(runs[0].samples[0].point, CGPoint(x: 0, y: 0))
        XCTAssertEqual(runs[1].samples[0].point, CGPoint(x: 3, y: 6),
                       "The surviving later run still opens on the boundary knot")
    }

    /// A gesture that never travelled leaves nothing behind — the one-dab case the length bound is
    /// about. A single knot is a dab the pen never moved for, and a lone dot at a cel boundary reads
    /// as dirt rather than as timing.
    func testARunOfOneSampleIsNotInk() {
        XCTAssertTrue(TimingStrokeCut.split(line(1), at: []).isEmpty,
                      "One knot is not a stroke")
        XCTAssertEqual(TimingStrokeCut.split(line(2), at: []).count, 1,
                       "…and two are, which is what an ordinary tap already produces")
        XCTAssertTrue(TimingStrokeCut.split(StrokeSamples(channels: .captured), at: [0]).isEmpty,
                      "An empty gesture splits into nothing, boundaries or not")
    }

    /// The channel set travels with each run. A gesture captures every channel and `compacted()`
    /// drops the ones that held only their neutral — so a run built with a *different* set would
    /// read its pressures out of the wrong storage.
    func testEachRunCarriesTheGesturesOwnChannelSet() {
        var samples = StrokeSamples(channels: .captured)
        for i in 0..<6 { samples.append(VectorSample(x: CGFloat(i), y: 0, pressure: 0.3)) }

        let runs = TimingStrokeCut.split(samples, at: [2])

        for run in runs {
            XCTAssertEqual(run.samples.storedChannels.map(\.rawValue).sorted(),
                           samples.storedChannels.map(\.rawValue).sorted(),
                           "A run's channels are the gesture's own")
            XCTAssertEqual(run.samples[0].pressure, 0.3, accuracy: 1e-9,
                           "…so its pressures read back off the right storage")
        }
    }

    // MARK: - The take: ink is something to have caught

    /// **A take whose whole product is ink ends clean.**
    ///
    /// Before stage 10 the only thing a take could catch was a channel, so a take with no channels
    /// was `.nothingCaptured` — whose sentence tells the artist to go and move an opacity slider.
    /// An artist who has just drawn across four cels reading that is the "refusal that names the
    /// wrong way out" this file's own `RecordingRefusal.noScene` records.
    ///
    /// Operands: `stopRecording()`'s returned case, and the notice actually raised.
    /// MUTATION-TESTED — with the `caughtInk` arm removed from `commitRecordingTake` this fails on
    /// both.
    func testATakeThatOnlyCaughtInkEndsWithoutTellingTheArtistNothingHappened() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 24)])
        let tgt = target(manager)
        XCTAssertNil(manager.armRecording(), "Setup: the recorder arms on a 24-frame scene")
        XCTAssertTrue(manager.beginArmedTake(on: tgt), "Setup: the pencil landing starts the take")
        XCTAssertTrue(manager.noteRecordedInk(on: tgt), "Setup: the timing stroke reports its ink")

        let outcome = manager.stopRecording()

        XCTAssertNil(outcome, "A take that caught ink caught something")
        if case .recordingRefused = manager.notice?.kind {
            XCTFail("…and says nothing about having recorded nothing (raised \(manager.notice!.message))")
        }
    }

    /// And the same take with **no** ink still refuses, which is what stops the assertion above
    /// passing for the wrong reason: an unconditional success would be green here too.
    func testATakeThatCaughtNothingAtAllStillSaysSo() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 24)])
        manager.armRecording()
        XCTAssertTrue(manager.beginArmedTake(on: target(manager)))

        let outcome = manager.stopRecording()

        XCTAssertEqual(outcome, .nothingCaptured)
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.nothingCaptured))
    }

    /// **An ink-only take records no undo step of its own**, because the strokes it caught have
    /// already recorded theirs and a second step over the same blocks is a press that changes
    /// nothing on screen.
    ///
    /// Operand: the depth of the undo stack across the whole take. It could go red — this is exactly
    /// what `commitStructureGesture` would do if `stopRecording` committed its bracket the way a
    /// channel take does.
    func testAnInkOnlyTakeLeavesTheUndoStackWhereItFoundIt() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 24)])
        let tgt = target(manager)
        manager.armRecording()
        XCTAssertTrue(manager.beginArmedTake(on: tgt))
        manager.noteRecordedInk(on: tgt)
        let stepsDuring = manager.history.undoStack.count

        manager.stopRecording()

        XCTAssertEqual(manager.history.undoStack.count, stepsDuring,
                       "The take's own bracket held nothing of its own — the ink's step owns every "
                       + "byte it changed, blocks included")
        XCTAssertEqual(manager.structureGestureDepth, 0,
                       "…and the bracket is closed either way, or the next gesture inherits it")
    }

    /// `noteRecordedInk` answers about *this* take. A stroke on another layer during a take aimed at
    /// this one is an ordinary stroke, and must not rescue the take from its own refusal.
    func testInkOnAnotherTargetIsNotThisTakesInk() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 24)])
        manager.armRecording()
        XCTAssertTrue(manager.beginArmedTake(on: target(manager)))

        XCTAssertFalse(manager.noteRecordedInk(on: .layer(id: UUID())),
                       "A take is scoped to one target, exactly as `recordParameterSample` is")
        XCTAssertEqual(manager.stopRecording(), .nothingCaptured)
    }

    // MARK: - The frame with no cel

    /// **What happens at a frame the layer has no block on**, and it is the rule that already ships
    /// rather than a new one: touching a blank frame with a drawing tool spawns a one-frame block.
    ///
    /// Operands: `activeCelIndex(inLayer:atFrame:)` before and after, and the canvas the surface
    /// answers with — which must be *that* cel's, not some other cel's.
    func testAFrameWithNoBlockGetsOneRatherThanSwallowingTheInk() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 3)])
        manager.currentFrame = 7
        XCTAssertNil(manager.activeCelIndex(inLayer: 0, atFrame: 7),
                     "Setup: frame 7 is past the only block")

        let surface = manager.timingStrokeSurface()

        let celIndex = try? XCTUnwrap(manager.activeCelIndex(inLayer: 0, atFrame: 7))
        XCTAssertNotNil(celIndex, "A block is made where the pen passed")
        XCTAssertNotNil(surface, "…and the surface answers rather than declining")
        XCTAssertTrue(surface?.canvas === manager.layers[0].cels[celIndex!].vector,
                      "…with that block's own canvas, not a neighbour's")
        XCTAssertEqual(manager.layers[0].cels[celIndex!].frameCount, 1,
                       "One frame, which is `ensureCelAtCurrentFrame`'s own shape")
    }

    /// The surface declines on a layer a stroke cannot land on at all, rather than making a block on
    /// it. `.raster` is the case an artist reaches by arming and drawing on the default layer kind
    /// of an older document.
    func testTheSurfaceDeclinesOnALayerThatIsNotVector() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentLayerIndex = 0
        let celsBefore = manager.layers[0].cels.count

        XCTAssertNil(manager.timingStrokeSurface())
        XCTAssertEqual(manager.layers[0].cels.count, celsBefore,
                       "…and makes nothing on the way to declining")
    }

    // MARK: - One gesture, one undo step

    /// **The brief's second requirement, on the two things a timing gesture changes.**
    ///
    /// The fixture is the shape a real take makes: two blocks that existed, one that the take had to
    /// spawn, and a stroke on each. Operands: every canvas's element count and the layer's block
    /// count, before the gesture, after it, after **one** undo press, and after one redo.
    ///
    /// It could go red in two independent ways — a step per cel (three presses to take back one
    /// gesture) and a step that puts the ink back but leaves the spawned block behind.
    func testOneUndoPressTakesBackEveryCelAndEveryBlockTheGestureMade() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 2), (start: 2, length: 2)])
        let layerID = manager.layers[0].id
        let celsBefore = manager.layers[0].cels

        // The third cel, as `timingStrokeSurface` would make it mid-gesture.
        manager.currentFrame = 9
        let spawned = manager.timingStrokeSurface()
        XCTAssertNotNil(spawned, "Setup: the run past the blocks gets a block of its own")
        let canvases = manager.layers[0].cels.compactMap(\.vector)
        XCTAssertEqual(canvases.count, 3, "Setup: three cels, three canvases")

        var edits: [CanvasManager.TimingStrokeEdit] = []
        for canvas in canvases {
            let before = canvas.elements
            canvas.addStroke(stroke(manager, line(4)))
            let celID = manager.layers[0].cels.first { $0.vector === canvas }?.id ?? UUID()
            edits.append(CanvasManager.TimingStrokeEdit(celID: celID, canvas: canvas, before: before,
                                                        after: canvas.elements, changedInk: nil))
        }
        let celsAfter = manager.layers[0].cels
        manager.history.removeAll()

        manager.recordTimingStrokeUndo(layerID: layerID, celsBefore: celsBefore,
                                       celsAfter: celsAfter, edits: edits)

        XCTAssertEqual(manager.history.undoStack.count, 1,
                       "One gesture is one step, whatever it spanned")
        XCTAssertEqual(canvases.map { $0.elements.count }, [1, 1, 1], "Setup: each cel has its arc")

        manager.undo()

        XCTAssertEqual(canvases.map { $0.elements.count }, [0, 0, 0],
                       "One press takes the ink off every cel the gesture crossed")
        XCTAssertEqual(manager.layers[0].cels.count, 2,
                       "…and takes back the block the take had to make, which nothing else owns")

        manager.redo()

        XCTAssertEqual(canvases.map { $0.elements.count }, [1, 1, 1], "…and redo puts it all back")
        XCTAssertEqual(manager.layers[0].cels.count, 3)
    }

    /// **The step resolves its layer by id at undo time**, because a step can be taken back after a
    /// restack and an index that was right when the ink was drawn addresses somebody else's layer by
    /// then. Operand: the *other* layer's block count, which must not move.
    func testTheUndoStepFindsItsLayerAfterARestack() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 2)])
        let inkedID = manager.layers[0].id
        let celsBefore = manager.layers[0].cels
        manager.currentFrame = 5
        XCTAssertNotNil(manager.timingStrokeSurface(), "Setup: a second block is spawned")
        let celsAfter = manager.layers[0].cels
        manager.addVectorLayer()          // inserts above, and makes itself active
        let otherID = manager.layers[manager.currentLayerIndex].id
        let otherCels = manager.layers[manager.currentLayerIndex].cels.count
        manager.layers.swapAt(0, 1)       // the inked layer is index 1 now
        manager.history.removeAll()

        manager.recordTimingStrokeUndo(layerID: inkedID, celsBefore: celsBefore,
                                       celsAfter: celsAfter, edits: [])
        manager.undo()

        let inkedIndex = try? XCTUnwrap(manager.layerIndex(ofID: inkedID))
        XCTAssertEqual(manager.layers[inkedIndex!].cels.count, 1,
                       "The block came off the layer the ink was on")
        let otherIndex = try? XCTUnwrap(manager.layerIndex(ofID: otherID))
        XCTAssertEqual(manager.layers[otherIndex!].cels.count, otherCels,
                       "…and the layer that moved into its old index is untouched")
    }

    // MARK: - A canvas touch during a take

    /// **A second stroke does not end the take it is part of**, which is the whole reason
    /// `canvasInteractionBegan` grew a parameter. `stopPlayback` ends a take outright, so without
    /// this the artist's second pen-down would silently finish the recording.
    ///
    /// Operands: `isRecording` and `isPlaying`, across the call.
    func testACanvasTouchDuringATakeDoesNotEndIt() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 24)])
        manager.armRecording()
        XCTAssertTrue(manager.beginArmedTake(on: target(manager)))
        XCTAssertTrue(manager.isPlaying, "Setup: a take plays")

        manager.canvasInteractionBegan(mayContinueTake: true)

        XCTAssertTrue(manager.isRecording, "The take survives the pen landing again")
        XCTAssertTrue(manager.isPlaying, "…and so does the clock it is timed against")
    }

    /// And every other way in still stops it, which is what keeps the exception narrow: a fill tap or
    /// an eyedropper press during a take has no cel-crossing story and would land against a moving
    /// playhead. The default argument is the operand — a call written the old way behaves the old way.
    func testEveryOtherCanvasInteractionStillEndsTheTake() {
        let (manager, _) = self.manager(blocks: [(start: 0, length: 24)])
        manager.armRecording()
        XCTAssertTrue(manager.beginArmedTake(on: target(manager)))

        manager.canvasInteractionBegan()

        XCTAssertFalse(manager.isPlaying, "Playback stops, exactly as it did before stage 10")
        XCTAssertFalse(manager.isRecording, "…and the take goes with it")
    }

    /// The armed sentence names the canvas. Stage 10 makes the canvas the surface an artist is most
    /// likely to have armed the recorder *for*, and a notice that sent them to a settings panel
    /// instead is the closed loop this repo has shipped three times.
    func testTheArmedNoticeNamesTheCanvas() {
        let (manager, _) = self.manager()

        manager.armRecording()

        let message = manager.notice?.message ?? ""
        XCTAssertTrue(message.lowercased().contains("canvas"),
                      "The armed banner has to name drawing as a way to start a take (read \"\(message)\")")
        XCTAssertTrue(message.lowercased().contains("slider"),
                      "…without dropping the surface that already worked")
    }
}
