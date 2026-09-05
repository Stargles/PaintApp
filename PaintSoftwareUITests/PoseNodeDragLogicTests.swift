import XCTest
import CoreGraphics

/// **Dragging a node of the transform band** — KEYFRAMES.md §11.7's write-back, the owner's *"make
/// the nodes draggable next"*.
///
/// `PoseComponentsLogicTests` pins the arithmetic and `PoseBandLogicTests` pins what the band draws.
/// This one pins the **edit**, and every test in it goes through the *shipped* dispatch —
/// `TimelineGraphBand.grab`, then `moves`, then `poseEdits`, then
/// `CanvasManager.writeGraphBandPoseEdits` — rather than through `PoseComponents.setting` directly.
/// That is deliberate and it is the difference between a test of this stage and a test of the last
/// one: `setting` replaces one component and leaves five alone, and that is already pinned; an
/// assertion built on it here would be an algebraic consequence of a function nobody changed, true of
/// a band with no write-back at all.
///
/// **The defect the whole stage exists to prevent** is a horizontal drag that pulls one of a pose
/// key's six rows out of step with the other five. It cannot happen in the model — six rows are one
/// `TransformTrack.Key`, which has one frame — so the way to *reach* it is a writer shaped like the
/// grade's, one curve at a time. `testDraggingOneRowSidewaysMovesTheWholeKey` is the test that would
/// go red for such a writer, and `PoseEdit`'s shape is what makes it unwritable.
@MainActor
final class PoseNodeDragLogicTests: XCTestCase {

    // MARK: - Fixtures

    private var size: CGSize { CanvasFixture.canvasSize }
    private var box: CGRect { CGRect(x: 4, y: 6, width: 16, height: 8) }
    private let ppf: CGFloat = 30

    /// **A band taller than the shipped 96 pt, so a test can say which row it grabbed.**
    ///
    /// Not a workaround but a consequence, and it is worth stating because it is a property of the
    /// *surface* rather than of these tests. Every one of a pose channel's six rows keys the same
    /// frames, so at any keyed frame the band draws six dots on one x, spread over the band's usable
    /// height by per-channel normalisation alone — about 16 pt apart on a 96 pt band, against a
    /// `hitRadius` of 22. `nearestKey` is doing exactly what it says; there simply is not room for
    /// six independent targets in 96 points, so at the shipped height a finger cannot reliably pick
    /// *which* component of a pose it is grabbing where all six key. (The channel list's filter is
    /// the artist's answer — hide the five rows you are not editing — and it is why that filter
    /// exists.)
    ///
    /// What is under test here is the **write**, so the fixture buys unambiguous targets rather than
    /// asserting around them; the hit arithmetic itself belongs to `TimelineGraphBandLogicTests`.
    private let height: CGFloat = 480

    private func stroke(_ points: [CGPoint]) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
    }

    /// A vector layer whose one cel starts at frame 4 — `PoseBandLogicTests`' fixture, and for its
    /// reason: a cel track keys cel-local and the band's x is absolute, so an offset that is missing
    /// or applied twice is invisible on a cel that starts at 0.
    private func celFixture(start: Int = 4,
                            length: Int = 16) -> (manager: CanvasManager, layerID: UUID, celID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: start, frameCount: length,
                      raster: .empty(size: size), vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[1].cels = [cel]
        manager.sceneFrameCount = max(manager.sceneFrameCount, start + length)
        manager.currentLayerIndex = 1
        manager.currentFrame = start
        manager.isGraphEditorOpen = true
        return (manager, manager.layers[1].id, cel.id)
    }

    /// **Three poses, stated as their six numbers rather than as a composition of transforms.**
    ///
    /// Two fixture rules meet here and the second was learned twice. The first is
    /// `PoseComponentsLogicTests`': a pose that is *neutral* in some component makes "the other five
    /// did not move" true of an implementation that resets them to rest, so none of these is.
    ///
    /// The second belongs to this band, and **the axis it was learned against is gone** — 2026-09-03
    /// replaced the fit with `anchoredRange`, a window centred on rest. What it was: a component flat
    /// across the keys got a degenerate axis widened by half a unit, so its node landed in the middle
    /// of the band and five flat components put five nodes on one point; widening the poses fixed that
    /// and left a subtler version, since with three keys a channel's **middle** node sits at the
    /// fraction of its own axis that its middle value occupies and two channels at the same fraction
    /// draw at the same height. The anchored axis makes both far less likely and neither impossible —
    /// six windows centred on six different rest values still admit a coincidence — so the fixture
    /// stands as it is rather than being loosened on the strength of a change it was not written
    /// against.
    ///
    /// So the fixture is authored in the currency it is read back in: minimum, a chosen fraction, and
    /// maximum, with the six fractions spread 0.10 to 0.90 so the six middle nodes are far apart.
    /// `recompose` is the author, and it is a function `PoseComponentsLogicTests` already pins as
    /// `decompose`'s inverse — so what these tests read back is what this table says.
    private static let poseValues: [PoseComponents.Values] = [
        //          x     y   scaleX  scaleY  rotation  skew
        .init(x: 20,   y: 14,   scaleX: 1.20, scaleY: 0.70, rotation: 13.0, skew: -8.0),
        .init(x: 25,   y: 25.5, scaleX: 2.08, scaleY: 1.91, rotation: 70.4, skew: 21.7),
        .init(x: 70,   y: 60,   scaleX: 3.40, scaleY: 2.90, rotation: 95.0, skew: 25.0),
    ]

    private func busyPose(_ n: Int) throws -> PoseQuad {
        try XCTUnwrap(PoseComponents.recompose(Self.poseValues[n % 3], box: box))
    }

    /// **Three keys** on the whole-cel channel at cel-local 0, 4 and 8 — absolute 4, 8 and 12 on the
    /// default fixture.
    ///
    /// Three rather than two, which is the other half of `poseValues`' lesson: under the axis this
    /// file was written against, two keys *were* a channel's whole axis, so every node sat at the very
    /// top or the very bottom of the band and six channels put six dots on two points. That is the
    /// owner's report of 2026-09-03 seen from inside a fixture a month early — the nodes did not move
    /// because the axis was the keys — and `PoseBandLogicTests` now pins the repair. The **middle** key
    /// is still the one these tests grab, and it is still the only one whose height is a channel's own
    /// business.
    private func animate(_ manager: CanvasManager, layerID: UUID, celID: UUID,
                         at localFrames: [Int] = [0, 4, 8]) throws {
        for (n, frame) in localFrames.enumerated() {
            manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                        atCelLocalFrame: frame, pose: try busyPose(n))
        }
    }

    private func content(_ manager: CanvasManager) throws -> TimelineGraphBand.Content {
        try XCTUnwrap(manager.graphBandContent)
    }

    private func channel(_ manager: CanvasManager, _ id: String) throws -> TimelineGraphBand.Channel {
        try XCTUnwrap(content(manager).channels.first { $0.parameterID == id })
    }

    private func id(_ component: PoseComponents.Component) -> String {
        PoseChannelID.cel(.cel).parameterID(component)
    }

    /// Where the band draws one channel's node, in the band's own points.
    private func node(_ channel: TimelineGraphBand.Channel, frame: Int) throws -> CGPoint {
        let key = try XCTUnwrap(channel.curve.key(atFrame: frame))
        return CGPoint(x: TimelineGraphBand.x(ofFrame: frame, pixelsPerFrame: ppf),
                       y: TimelineGraphBand.y(ofValue: key.value, in: channel.axis, bandHeight: height))
    }

    /// The six components a channel's key holds, read back off the document through the band.
    private func six(_ manager: CanvasManager, atFrame frame: Int) throws -> PoseComponents.Values {
        var values = PoseComponents.Values(x: 0, y: 0, scaleX: 0, scaleY: 0, rotation: 0, skew: 0)
        for component in PoseComponents.Component.allCases {
            let key = try XCTUnwrap(channel(manager, id(component)).curve.key(atFrame: frame),
                                    "\(component) has no key at frame \(frame)")
            values[component] = key.value
        }
        return values
    }

    /// The absolute frames every one of the six curves holds a key on, one array per component. The
    /// operand of the test this file is named for.
    private func framesOfEachRow(_ manager: CanvasManager) throws -> [[Int]] {
        try PoseComponents.Component.allCases.map { try channel(manager, id($0)).curve.keys.map(\.frame) }
    }

    // MARK: - The shipped drag, run in a test

    /// **`TimelineTrackView.Coordinator`'s three steps, in order and with nothing else.**
    ///
    /// Touch-down resolves through `grab`, every tick resolves `moves` against the *starting*
    /// channels and the *starting* pose snapshot, and the two funnels each take the half of the
    /// answer they own. The undo bracket is opened and committed exactly where the coordinator opens
    /// and commits it, because "one drag is one press of Undo" is one of the things under test.
    ///
    /// Written here rather than reached through the view because `TimelineTrackView.swift` is not
    /// compiled into `PaintSoftwareUITests` — §11.4's own reason for moving `isTap` onto the band.
    /// What it must not do is *decide* anything the coordinator decides; every choice below is a call
    /// into the same function the recogniser calls.
    ///
    /// - Parameter expecting: the row the touch must resolve to, or nil where the test's point is
    ///   that it resolves to nothing. **Asserted rather than assumed**, because several channels can
    ///   key one frame and their dots then share an x: a fixture that stacked two nodes would have
    ///   this drag silently steer a different curve than the test's name says, and every assertion
    ///   downstream would be about the wrong operand. That is exactly what the first draft of this
    ///   file did.
    @discardableResult
    private func drag(_ manager: CanvasManager, from start: CGPoint, by translation: CGSize,
                      expecting: String?, ticks: Int = 2, cancelled: Bool = false,
                      file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        let content = try content(manager)
        let baseline = manager.graphBandPoseSnapshot(layerIndex: content.layerIndex)
        let grab = TimelineGraphBand.grab(at: start, focused: nil, channels: content.channels,
                                          pixelsPerFrame: ppf, bandHeight: height)
        guard case .key(let hit) = grab else {
            XCTAssertNil(expecting, "The touch took hold of nothing", file: file, line: line)
            return false
        }
        XCTAssertEqual(hit.parameterID, expecting, "The touch took hold of the wrong row",
                       file: file, line: line)

        manager.beginStructureGesture()
        var wrote = false
        // Several ticks, because a drag writes on every `.changed` and the property that makes that
        // safe — each tick applied to the state the *drag* started from — is invisible on one tick.
        for tick in 1...max(ticks, 1) {
            let step = CGSize(width: translation.width * CGFloat(tick) / CGFloat(max(ticks, 1)),
                              height: translation.height * CGFloat(tick) / CGFloat(max(ticks, 1)))
            let moves = TimelineGraphBand.moves(of: [hit], in: content.channels, translation: step,
                                                pixelsPerFrame: ppf, bandHeight: height)
            if manager.writeGraphBandPoseEdits(TimelineGraphBand.poseEdits(moves, in: content.channels),
                                               from: baseline, layerIndex: content.layerIndex) {
                wrote = true
            }
        }
        if cancelled {
            manager.restoreGraphBandPoses(baseline, layerIndex: content.layerIndex)
            manager.cancelStructureGesture()
        } else if wrote {
            manager.commitStructureGesture(label: .effectKeyframes)
        } else {
            manager.cancelStructureGesture()
        }
        return wrote
    }

    // MARK: - The six stay at one frame

    /// **Drag one row sideways and the whole key moves: all six components report the new frame and
    /// none of them the old one.**
    ///
    /// This is the test the stage exists for. The gesture layer names a **row** (`KeyRef` is a
    /// parameter id and a frame) and the document has no such thing — six rows are one
    /// `TransformTrack.Key` with one frame — so a writer that took the band's own vocabulary
    /// literally would move one row and leave five behind, or insert a seventh key beside them. It
    /// goes red for either.
    ///
    /// **The finger is on Scale X**, deliberately not on X: a writer that happened to rebuild the key
    /// out of a translation would look right on the X row and wrong here.
    ///
    /// Three assertions rather than one, and the last two are what stop it passing for the wrong
    /// implementation: every row must hold **three** keys afterwards and not four, and the document's
    /// one track must carry the move in its own cel-local numbers.
    func testDraggingOneRowSidewaysMovesTheWholeKey() throws {
        let (manager, layerID, celID) = celFixture()
        try animate(manager, layerID: layerID, celID: celID)
        XCTAssertEqual(try framesOfEachRow(manager), Array(repeating: [4, 8, 12], count: 6),
                       "Fixture: six rows, three keys each, at the cel's absolute frames")

        let scaleX = try channel(manager, id(.scaleX))
        XCTAssertTrue(try drag(manager, from: try node(scaleX, frame: 8),
                               by: CGSize(width: ppf * 2, height: 0), expecting: id(.scaleX)),
                      "The drag wrote something")

        XCTAssertEqual(try framesOfEachRow(manager), Array(repeating: [4, 10, 12], count: 6),
                       "All six rows moved to frame 10 together, and each still holds three keys")
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks[TransformChannelID.cel.id]?.keys
                        .map(\.frame), [0, 6, 8],
                       "…and the document holds one track whose cel-local keys are 0, 6 and 8")
    }

    /// **A marquee that catches all six rows of one key retimes it once**, which is the same property
    /// reached from the gesture that can genuinely hand the writer six requests instead of one.
    ///
    /// `moves(of:…)` gives one frame delta to a whole carried set, so the six agree by arithmetic;
    /// `PoseEdit` keys its retimes by frame rather than by row, so they agree by shape as well. This
    /// is the test of the second: hand the writer six rows and the key must move once, not six times.
    func testAMarqueeOverAllSixRowsRetimesTheKeyOnceAndNotSixTimes() throws {
        let (manager, layerID, celID) = celFixture()
        try animate(manager, layerID: layerID, celID: celID)
        let content = try content(manager)
        let baseline = manager.graphBandPoseSnapshot(layerIndex: content.layerIndex)

        let caught = TimelineGraphBand.keys(in: CGRect(x: TimelineGraphBand.x(ofFrame: 8,
                                                                             pixelsPerFrame: ppf) - 6,
                                                       y: 0, width: 12, height: height),
                                            channels: content.channels,
                                            pixelsPerFrame: ppf, bandHeight: height)
        XCTAssertEqual(caught.count, 6, "Fixture: the marquee holds all six rows of the frame-8 key")

        let moves = TimelineGraphBand.moves(of: caught, in: content.channels,
                                            translation: CGSize(width: ppf * 2, height: 0),
                                            pixelsPerFrame: ppf, bandHeight: height)
        let edits = TimelineGraphBand.poseEdits(moves, in: content.channels)
        XCTAssertEqual(edits[PoseChannelID.cel(.cel).groupID]?.retimes, [8: 10],
                       "Six rows fold into one retime of one key")
        manager.writeGraphBandPoseEdits(edits, from: baseline, layerIndex: content.layerIndex)
        XCTAssertEqual(try framesOfEachRow(manager), Array(repeating: [4, 10, 12], count: 6))
    }

    // MARK: - The vertical half

    /// **Drag one row up and that component takes the value the finger asked for, while the other
    /// five stay where they were.**
    ///
    /// **Read through the shipped dispatch**, not through `PoseComponents.setting`: the operands are
    /// the six numbers the *band* reports after the write, so the assertion is about the funnel and
    /// not about the factorisation, which `PoseComponentsLogicTests` already owns.
    ///
    /// The expected value is computed from the band's own axis rather than from the answer — the
    /// travel is `TimelineGraphBand.value(atY:)` of the start y plus the drag, which is what `moves`
    /// says a point of band is worth on that channel — so an implementation that wrote *something*
    /// different would fail rather than defining itself correct.
    ///
    /// The tolerance is `decompose`'s and not zero, and it is the same 1e-7
    /// `testEditingOneComponentLeavesTheOtherFiveAlone` states: a write-back is a round trip through
    /// `atan2`, `hypot` and `tan`, so "the other five did not move" is a tolerance by construction.
    func testDraggingOneRowVerticallyChangesThatComponentAndLeavesTheOtherFive() throws {
        let (manager, layerID, celID) = celFixture()
        try animate(manager, layerID: layerID, celID: celID)
        let before = try six(manager, atFrame: 8)

        let rotation = try channel(manager, id(.rotation))
        let start = try node(rotation, frame: 8)
        let travel: CGFloat = -18
        let expected = TimelineGraphBand.value(atY: start.y + travel, in: rotation.axis,
                                               bandHeight: height)
        XCTAssertNotEqual(expected, before.rotation, accuracy: 1e-6,
                          "Fixture: the drag actually asks for a different rotation")

        XCTAssertTrue(try drag(manager, from: start, by: CGSize(width: 0, height: travel),
                               expecting: id(.rotation)))

        let after = try six(manager, atFrame: 8)
        XCTAssertEqual(after.rotation, expected, accuracy: 1e-7,
                       "Rotation took the value the finger asked for")
        for component in PoseComponents.Component.allCases where component != .rotation {
            XCTAssertEqual(after[component], before[component], accuracy: 1e-7,
                           "dragging Rotation moved \(component)")
        }
        XCTAssertEqual(try framesOfEachRow(manager), Array(repeating: [4, 8, 12], count: 6),
                       "…and a vertical drag retimed nothing")
    }

    /// **A purely horizontal drag leaves every one of the six components bit-identical**, which is
    /// `PoseEdit`'s "only what moved is listed" rule and not a tolerance.
    ///
    /// It matters because `PoseComponents.setting` is an exact inverse to floating point and not to
    /// the bit: writing a component back at the value it already holds perturbs the other five in the
    /// last place, and a drag does it on every tick. Asserted with `XCTAssertEqual` on `Double` and no
    /// accuracy on purpose — the point is that the pose was **carried**, not recomputed.
    func testARetimeCarriesThePoseRatherThanRecomputingIt() throws {
        let (manager, layerID, celID) = celFixture()
        try animate(manager, layerID: layerID, celID: celID)
        let track = try XCTUnwrap(manager.layers[1].cels[0].transformTracks[TransformChannelID.cel.id])
        let before = try XCTUnwrap(track.key(atFrame: 4)).pose

        let x = try channel(manager, id(.x))
        XCTAssertTrue(try drag(manager, from: try node(x, frame: 8),
                               by: CGSize(width: ppf * 2, height: 0), expecting: id(.x), ticks: 4))

        let after = try XCTUnwrap(manager.layers[1].cels[0]
            .transformTracks[TransformChannelID.cel.id]?.key(atFrame: 6))
        XCTAssertEqual(after.pose, before, "Four ticks of a pure retime and the pose is the same value")
    }

    // MARK: - Undo

    /// **One press of Undo puts the pose and the frame back**, however many ticks the drag wrote.
    ///
    /// Both halves in one gesture — the node is dragged up *and* across — because the two travel
    /// through different fields of the same key and an undo that restored one and not the other would
    /// pass a test of either alone.
    func testOnePressOfUndoRestoresBothHalvesOfADraggedNode() throws {
        let (manager, layerID, celID) = celFixture()
        try animate(manager, layerID: layerID, celID: celID)
        let before = try six(manager, atFrame: 8)
        let depth = manager.history.undoStack.count

        let scaleY = try channel(manager, id(.scaleY))
        XCTAssertTrue(try drag(manager, from: try node(scaleY, frame: 8),
                               by: CGSize(width: ppf * 2, height: -22), expecting: id(.scaleY),
                               ticks: 5))
        XCTAssertEqual(try framesOfEachRow(manager), Array(repeating: [4, 10, 12], count: 6),
                       "Fixture: the drag landed")
        XCTAssertEqual(manager.history.undoStack.count, depth + 1,
                       "Five ticks of one drag are one step, not five")

        manager.undo()
        XCTAssertEqual(try framesOfEachRow(manager), Array(repeating: [4, 8, 12], count: 6),
                       "One press put the frame back")
        let after = try six(manager, atFrame: 8)
        for component in PoseComponents.Component.allCases {
            XCTAssertEqual(after[component], before[component], accuracy: 1e-9,
                           "\(component) did not come back")
        }
    }

    /// **A cancelled drag puts the poses back and records nothing** — the two-finger case, where a
    /// second touch cancels the recogniser mid-drag.
    ///
    /// The undo depth is the operand that matters: `cancelStructureGesture` throws the baseline away
    /// *without* recording, so "record nothing" and "change nothing" are two separate arrangements
    /// and a restore that recorded would leave a step that puts the cancelled edit back.
    func testACancelledDragLeavesNeitherAnEditNorAnUndoStep() throws {
        let (manager, layerID, celID) = celFixture()
        try animate(manager, layerID: layerID, celID: celID)
        let before = try six(manager, atFrame: 8)
        let depth = manager.history.undoStack.count

        let x = try channel(manager, id(.x))
        _ = try drag(manager, from: try node(x, frame: 8),
                     by: CGSize(width: ppf * 2, height: -20), expecting: id(.x), ticks: 3,
                     cancelled: true)

        XCTAssertEqual(try framesOfEachRow(manager), Array(repeating: [4, 8, 12], count: 6))
        let after = try six(manager, atFrame: 8)
        for component in PoseComponents.Component.allCases {
            XCTAssertEqual(after[component], before[component], accuracy: 1e-9, "\(component)")
        }
        XCTAssertEqual(manager.history.undoStack.count, depth, "…and nothing to press Undo on")
    }

    // MARK: - What a drag is still stopped by

    /// **A pose key is walled by the cel it rides** — §3.1's "a cel track keys cel-local and rides its
    /// cel", enforced where the node is drawn so that the dot stops where the document does.
    ///
    /// Two cels, each with a key, and the left one's key is dragged right by more than the gap. The
    /// neighbour clamp alone would let it travel to one frame short of the right cel's key, which is
    /// **inside the right cel's span** — where it renders nothing (it is past its own cel's last
    /// frame) and can land on the same absolute frame as one of that cel's keys, at which point the
    /// band draws one node for two stored keys.
    ///
    /// The fixture leaves a gap between the two keys wider than the wall, which is what makes the two
    /// clamps give different answers and the assertion able to tell them apart.
    func testAPoseKeyIsStoppedByTheEndOfItsOwnCelAndNotOnlyByItsNeighbour() throws {
        let (manager, layerID, _) = celFixture(start: 0, length: 6)
        let second = Cel(id: UUID(), startFrame: 6, frameCount: 10,
                         raster: .empty(size: size), vector: .empty(size: size))
        second.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[1].cels.append(second)
        manager.sceneFrameCount = 16
        for (n, frame) in [0, 2].enumerated() {
            manager.setTransformPoseKey(layerID: layerID, celID: manager.layers[1].cels[0].id,
                                        channel: .cel, atCelLocalFrame: frame, pose: try busyPose(n))
        }
        manager.setTransformPoseKey(layerID: layerID, celID: second.id,
                                    channel: .cel, atCelLocalFrame: 6, pose: try busyPose(2))

        let x = try channel(manager, id(.x))
        XCTAssertEqual(x.curve.keys.map(\.frame), [0, 2, 12],
                       "Fixture: two cels merge into one drawn channel, keyed at 0, 2 and 12")
        XCTAssertEqual(x.frameWindows[2], 0...5, "Fixture: the frame-2 key rides the six-frame cel")

        XCTAssertTrue(try drag(manager, from: try node(x, frame: 2),
                               by: CGSize(width: ppf * 8, height: 0), expecting: id(.x)))
        XCTAssertEqual(try channel(manager, id(.x)).curve.keys.map(\.frame), [0, 5, 12],
                       "It stopped at frame 5, the last frame of its own cel — not at 11, one short "
                       + "of the neighbour it can see")
        XCTAssertEqual(manager.layers[1].cels[1].transformTracks[TransformChannelID.cel.id]?
                        .keys.map(\.frame), [6],
                       "…and the second cel's own key is untouched")
    }

    /// **A projective channel is not drawn, so there is nothing to drag** — §11.7's ruling, from the
    /// gesture side.
    ///
    /// The refusal it pins is `decompose`'s, and the assertion that makes it a test rather than a
    /// tautology is the first one: the *same fixture* drew six draggable rows one key earlier, so
    /// what changed is the keystone and not the absence of a channel. `grab` at the point the node
    /// used to be takes hold of nothing, which is the state a drag can actually reach.
    func testAProjectiveChannelIsDrawnNowhereAndSoTakesNoDrag() throws {
        let (manager, layerID, celID) = celFixture()
        try animate(manager, layerID: layerID, celID: celID)
        let x = try channel(manager, id(.x))
        let point = try node(x, frame: 8)
        XCTAssertEqual(TimelineGraphBand.grab(at: point, focused: nil,
                                              channels: try content(manager).channels,
                                              pixelsPerFrame: ppf, bandHeight: height),
                       .key(.init(parameterID: id(.x), frame: 8)),
                       "Fixture: this node is grabbable before the pose goes projective")

        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 4,
                                    pose: PoseQuad(box: box,
                                                   corners: Quad(CGPoint(x: 0, y: 0),
                                                                 CGPoint(x: 100, y: 0),
                                                                 CGPoint(x: 80, y: 100),
                                                                 CGPoint(x: 20, y: 100))))
        let declined = try content(manager)
        XCTAssertEqual(declined.declinedChannelIDs, [PoseChannelID.cel(.cel).groupID])
        XCTAssertTrue(declined.channels.isEmpty, "The whole channel is declined, not five of its six")
        XCTAssertEqual(TimelineGraphBand.grab(at: point, focused: nil, channels: declined.channels,
                                              pixelsPerFrame: ppf, bandHeight: height),
                       .nothing, "…so a touch where the node was takes hold of nothing")

        let before = manager.layers[1].cels[0].transformTracks
        XCTAssertFalse(try drag(manager, from: point, by: CGSize(width: ppf * 3, height: -20),
                                expecting: nil),
                       "…and the drag writes nothing")
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks, before)
    }
}
