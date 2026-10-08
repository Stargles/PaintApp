import XCTest
import CoreGraphics

/// **Dragging a node of the transform band** — KEYFRAMES.md §11.7's write-back, and TODO (139):
/// every row is one component's own curve, so a drag on one row moves that row and no other.
///
/// `PoseComponentsLogicTests` pins the arithmetic and `PoseBandLogicTests` pins what the band draws.
/// This one pins the **edit**, and every test in it goes through the *shipped* dispatch —
/// `TimelineGraphBand.grab`, then `moves`, then `applying`, then
/// `CanvasManager.setPoseChannelTrack` — the same three steps a grade's node drag takes.
///
/// **The property the whole file exists for is the opposite of what it pinned before TODO (139).**
/// A whole-pose key had one frame for all six rows, so a sideways drag on Scale X moved X, Y and
/// Rotation with it; the owner ruled the components *"fully independent from each other"*, and
/// `testDraggingOneRowSidewaysMovesThatRowAlone` is the test that goes red for a writer that still
/// carried the other rows along.
@MainActor
final class PoseNodeDragLogicTests: XCTestCase {

    // MARK: - Fixtures

    private var size: CGSize { CanvasFixture.canvasSize }
    private var box: CGRect { CGRect(x: 4, y: 6, width: 16, height: 8) }
    private let ppf: CGFloat = 30

    /// **A band taller than the shipped 96 pt, so a test can say which row it grabbed.** Every row of
    /// this fixture keys the same frames, so at a keyed frame the band draws eight dots on one x,
    /// spread over the band's height by per-channel normalisation alone. What is under test here is
    /// the **write**, so the fixture buys unambiguous targets rather than asserting around them; the
    /// hit arithmetic belongs to `TimelineGraphBandLogicTests`.
    private let height: CGFloat = 640

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
        manager.currentLayerIndex = 1
        manager.currentFrame = start
        manager.isGraphEditorOpen = true
        return (manager, manager.layers[1].id, cel.id)
    }

    /// **Three keyed values per component, stated as the stored curves rather than as poses.**
    ///
    /// None of them is neutral, so "the other rows did not move" cannot be true of an implementation
    /// that reset them to rest; and each row's middle value sits at a different fraction of its own
    /// axis, so the eight middle nodes draw at eight different heights and a grab names one row.
    private static let rows: [PoseComponents.Component: [Double]] = [
        .x: [20, 25, 70],
        .y: [14, 25.5, 60],
        .scaleX: [1.20, 2.08, 3.40],
        .scaleY: [0.70, 1.91, 2.90],
        .rotation: [13.0, 70.4, 95.0],
        .skew: [-8.0, 21.7, 25.0],
        .perspectiveX: [0.05, 0.20, 0.30],
        .perspectiveY: [-0.10, 0.18, -0.25],
    ]

    /// **Three keys on every component** of the whole-cel channel, at cel-local 0, 4 and 8 — absolute
    /// 4, 8 and 12 on the default fixture. The middle key is the one these tests grab.
    private func animate(_ manager: CanvasManager, layerID: UUID, celID: UUID,
                         at localFrames: [Int] = [0, 4, 8]) {
        var curves: [PoseComponents.Component: AnimationCurve] = [:]
        for (component, values) in Self.rows {
            curves[component] = AnimationCurve(keys: zip(localFrames, values).map {
                AnimationCurve.Key(frame: $0.0, value: $0.1)
            })
        }
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                   TransformTrack(box: box, curves: curves))
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

    /// The absolute frames every row holds a key on, by component. The operand of the test this file
    /// is named for.
    private func framesOfEachRow(_ manager: CanvasManager) throws -> [PoseComponents.Component: [Int]] {
        var frames: [PoseComponents.Component: [Int]] = [:]
        for component in PoseComponents.Component.allCases {
            frames[component] = try channel(manager, id(component)).curve.keys.map(\.frame)
        }
        return frames
    }

    /// Every row's keyed values, by component — read off the band, which reads the document.
    private func valuesOfEachRow(_ manager: CanvasManager) throws -> [PoseComponents.Component: [Double]] {
        var values: [PoseComponents.Component: [Double]] = [:]
        for component in PoseComponents.Component.allCases {
            values[component] = try channel(manager, id(component)).curve.keys.map(\.value)
        }
        return values
    }

    private func allRows(_ frames: [Int]) -> [PoseComponents.Component: [Int]] {
        Dictionary(uniqueKeysWithValues: PoseComponents.Component.allCases.map { ($0, frames) })
    }

    // MARK: - The shipped drag, run in a test

    /// **`TimelineTrackView.Coordinator`'s three steps, in order and with nothing else.**
    ///
    /// Touch-down resolves through `grab`, every tick resolves `moves` against the *starting*
    /// channels and writes the whole curves `applying` returns, and a cancel writes the starting
    /// curves back — the coordinator's own arrangement. The undo bracket is opened and committed
    /// exactly where the coordinator opens and commits it, because "one drag is one press of Undo" is
    /// one of the things under test. Written here because `TimelineTrackView.swift` is not compiled
    /// into `PaintSoftwareUITests`; every choice below is a call into the function the recogniser
    /// calls.
    ///
    /// - Parameter expecting: the row the touch must resolve to, asserted rather than assumed.
    @discardableResult
    private func drag(_ manager: CanvasManager, from start: CGPoint, by translation: CGSize,
                      expecting: String?, ticks: Int = 2, cancelled: Bool = false,
                      file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        let content = try content(manager)
        let grab = TimelineGraphBand.grab(at: start, focused: nil, channels: content.channels,
                                          pixelsPerFrame: ppf, bandHeight: height)
        guard case .key(let hit) = grab else {
            XCTAssertNil(expecting, "The touch took hold of nothing", file: file, line: line)
            return false
        }
        XCTAssertEqual(hit.parameterID, expecting, "The touch took hold of the wrong row",
                       file: file, line: line)
        return try dragKeys(manager, [hit], by: translation, ticks: ticks, cancelled: cancelled)
    }

    /// The tick loop and the bracket, for a carried set of keys — a single grab or a marquee.
    @discardableResult
    private func dragKeys(_ manager: CanvasManager, _ carried: Set<TimelineGraphBand.KeyRef>,
                          by translation: CGSize, ticks: Int = 2, cancelled: Bool = false) throws -> Bool {
        let content = try content(manager)
        manager.beginStructureGesture()
        var wrote = false
        for tick in 1...max(ticks, 1) {
            let step = CGSize(width: translation.width * CGFloat(tick) / CGFloat(max(ticks, 1)),
                              height: translation.height * CGFloat(tick) / CGFloat(max(ticks, 1)))
            let moves = TimelineGraphBand.moves(of: carried, in: content.channels, translation: step,
                                                pixelsPerFrame: ppf, bandHeight: height)
            for (id, curve) in TimelineGraphBand.applying(moves, to: content.channels)
            where manager.setPoseChannelTrack(content.target, parameterID: id, to: curve) {
                wrote = true
            }
        }
        if cancelled {
            for channel in content.channels where carried.contains(where: { $0.parameterID == channel.parameterID }) {
                manager.setPoseChannelTrack(content.target, parameterID: channel.parameterID, to: channel.curve)
            }
            manager.cancelStructureGesture()
        } else if wrote {
            manager.commitStructureGesture(label: .effectKeys)
        } else {
            manager.cancelStructureGesture()
        }
        return wrote
    }

    // MARK: - One row, one component — TODO (139)

    /// **Drag one row sideways and only that row's key moves** — the owner's *"fully independent"*.
    ///
    /// **The finger is on Scale X**, deliberately not on X: a writer that rebuilt the pose out of a
    /// translation would look right on the X row and wrong here. Every other row must still key 4,
    /// 8 and 12, and the document's track must carry the move on Scale X alone, in its own cel-local
    /// numbers.
    func testDraggingOneRowSidewaysMovesThatRowAlone() throws {
        let (manager, layerID, celID) = celFixture()
        animate(manager, layerID: layerID, celID: celID)
        XCTAssertEqual(try framesOfEachRow(manager), allRows([4, 8, 12]),
                       "Fixture: eight rows, three keys each, at the cel's absolute frames")

        let scaleX = try channel(manager, id(.scaleX))
        XCTAssertTrue(try drag(manager, from: try node(scaleX, frame: 8),
                               by: CGSize(width: ppf * 2, height: 0), expecting: id(.scaleX)),
                      "The drag wrote something")

        var expected = allRows([4, 8, 12])
        expected[.scaleX] = [4, 10, 12]
        XCTAssertEqual(try framesOfEachRow(manager), expected,
                       "Scale X moved to frame 10 and every other row still keys frame 8")
        let track = manager.layers[1].cels[0].transformTracks[TransformChannelID.cel.id]
        XCTAssertEqual(track?.curve(.scaleX)?.keys.map(\.frame), [0, 6, 8])
        XCTAssertEqual(track?.curve(.x)?.keys.map(\.frame), [0, 4, 8])
        XCTAssertEqual(track?.keyedFrames, [0, 4, 6, 8], "…so the timeline has a diamond at both 8 and 10")
    }

    /// **A marquee over every row of one frame retimes each row's own key** — the gesture that hands
    /// the writer eight requests, each about its own curve.
    func testAMarqueeOverEveryRowOfAFrameRetimesEachRowsKey() throws {
        let (manager, layerID, celID) = celFixture()
        animate(manager, layerID: layerID, celID: celID)
        let content = try content(manager)
        let caught = TimelineGraphBand.keys(in: CGRect(x: TimelineGraphBand.x(ofFrame: 8, pixelsPerFrame: ppf) - 6,
                                                       y: 0, width: 12, height: height),
                                            channels: content.channels,
                                            pixelsPerFrame: ppf, bandHeight: height)
        XCTAssertEqual(caught.count, 8, "Fixture: the marquee holds every row's frame-8 key")
        XCTAssertTrue(try dragKeys(manager, caught, by: CGSize(width: ppf * 2, height: 0)))
        XCTAssertEqual(try framesOfEachRow(manager), allRows([4, 10, 12]))
    }

    // MARK: - The vertical half

    /// **Drag one row up and that component takes the value the finger asked for, while every other
    /// row stays exactly where it was** — bit for bit, now that no row is derived from another.
    ///
    /// The expected value is computed from the band's own axis rather than from the answer.
    func testDraggingOneRowVerticallyChangesThatComponentAndNoOther() throws {
        let (manager, layerID, celID) = celFixture()
        animate(manager, layerID: layerID, celID: celID)
        let before = try valuesOfEachRow(manager)

        let rotation = try channel(manager, id(.rotation))
        let start = try node(rotation, frame: 8)
        let travel: CGFloat = -18
        let expected = TimelineGraphBand.value(atY: start.y + travel, in: rotation.axis, bandHeight: height)
        XCTAssertNotEqual(expected, before[.rotation]![1], accuracy: 1e-6,
                          "Fixture: the drag actually asks for a different rotation")

        XCTAssertTrue(try drag(manager, from: start, by: CGSize(width: 0, height: travel),
                               expecting: id(.rotation)))

        let after = try valuesOfEachRow(manager)
        XCTAssertEqual(after[.rotation]![1], expected, accuracy: 1e-9,
                       "Rotation took the value the finger asked for")
        for component in PoseComponents.Component.allCases where component != .rotation {
            XCTAssertEqual(after[component], before[component], "dragging Rotation moved \(component)")
        }
        XCTAssertEqual(try framesOfEachRow(manager), allRows([4, 8, 12]), "…and a vertical drag retimed nothing")
    }

    /// **A purely horizontal drag carries the key's value bit for bit** — `moves` short-circuits zero
    /// vertical travel, so four ticks of a retime cannot grind the value in the last place.
    func testARetimeCarriesTheValueRatherThanRecomputingIt() throws {
        let (manager, layerID, celID) = celFixture()
        animate(manager, layerID: layerID, celID: celID)
        let x = try channel(manager, id(.x))
        let before = try XCTUnwrap(x.curve.key(atFrame: 8)).value
        XCTAssertTrue(try drag(manager, from: try node(x, frame: 8),
                               by: CGSize(width: ppf * 2, height: 0), expecting: id(.x), ticks: 4))
        XCTAssertEqual(try channel(manager, id(.x)).curve.key(atFrame: 10)?.value, before)
    }

    /// **A perspective row drags like any other** — the ruling that made a keystone two curves, from
    /// the gesture side: the band's projective refusal is gone, and so is the drag it refused.
    func testAPerspectiveRowIsDraggedLikeAnyOther() throws {
        let (manager, layerID, celID) = celFixture()
        animate(manager, layerID: layerID, celID: celID)
        let perspective = try channel(manager, id(.perspectiveX))
        XCTAssertTrue(try drag(manager, from: try node(perspective, frame: 8),
                               by: CGSize(width: 0, height: -15), expecting: id(.perspectiveX)))
        XCTAssertNotEqual(try channel(manager, id(.perspectiveX)).curve.key(atFrame: 8)?.value,
                          perspective.curve.key(atFrame: 8)?.value)
        XCTAssertTrue(manager.resolvedPoseMap(layerID: layerID, celID: celID, channel: .cel, atFrame: 8)
                        .isProjective, "…and the drawing is still keystoned there")
    }

    // MARK: - Undo

    /// **One press of Undo puts the value and the frame back**, however many ticks the drag wrote.
    func testOnePressOfUndoRestoresBothHalvesOfADraggedNode() throws {
        let (manager, layerID, celID) = celFixture()
        animate(manager, layerID: layerID, celID: celID)
        let before = try valuesOfEachRow(manager)
        let depth = manager.history.undoStack.count

        let scaleY = try channel(manager, id(.scaleY))
        XCTAssertTrue(try drag(manager, from: try node(scaleY, frame: 8),
                               by: CGSize(width: ppf * 2, height: -22), expecting: id(.scaleY), ticks: 5))
        XCTAssertEqual(try framesOfEachRow(manager)[.scaleY], [4, 10, 12], "Fixture: the drag landed")
        XCTAssertEqual(manager.history.undoStack.count, depth + 1,
                       "Five ticks of one drag are one step, not five")

        manager.undo()
        XCTAssertEqual(try framesOfEachRow(manager), allRows([4, 8, 12]), "One press put the frame back")
        XCTAssertEqual(try valuesOfEachRow(manager), before, "…and the value")
    }

    /// **A cancelled drag puts the curve back and records nothing** — the two-finger case.
    func testACancelledDragLeavesNeitherAnEditNorAnUndoStep() throws {
        let (manager, layerID, celID) = celFixture()
        animate(manager, layerID: layerID, celID: celID)
        let before = try valuesOfEachRow(manager)
        let depth = manager.history.undoStack.count

        let x = try channel(manager, id(.x))
        _ = try drag(manager, from: try node(x, frame: 8),
                     by: CGSize(width: ppf * 2, height: -20), expecting: id(.x), ticks: 3, cancelled: true)

        XCTAssertEqual(try framesOfEachRow(manager), allRows([4, 8, 12]))
        XCTAssertEqual(try valuesOfEachRow(manager), before)
        XCTAssertEqual(manager.history.undoStack.count, depth, "…and nothing to press Undo on")
    }

    // MARK: - What a drag is still stopped by

    /// **A pose key is walled by the cel it rides** — §3.1's "a cel track keys cel-local and rides its
    /// cel", enforced where the node is drawn so that the dot stops where the document does.
    func testAPoseKeyIsStoppedByTheEndOfItsOwnCelAndNotOnlyByItsNeighbour() throws {
        let (manager, layerID, _) = celFixture(start: 0, length: 6)
        let second = Cel(id: UUID(), startFrame: 6, frameCount: 10,
                         raster: .empty(size: size), vector: .empty(size: size))
        second.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[1].cels.append(second)
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: manager.layers[1].cels[0].id,
                                   TransformTrack(box: box, curves: [.x: AnimationCurve(keys: [
                                       .init(frame: 0, value: 20), .init(frame: 2, value: 25)])]))
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: second.id,
                                   TransformTrack(box: box, curves: [.x: AnimationCurve(keys: [
                                       .init(frame: 6, value: 70)])]))

        let x = try channel(manager, id(.x))
        XCTAssertEqual(x.curve.keys.map(\.frame), [0, 2, 12],
                       "Fixture: two cels merge into one drawn row, keyed at 0, 2 and 12")
        XCTAssertEqual(x.frameWindows[2], 0...5, "Fixture: the frame-2 key rides the six-frame cel")

        XCTAssertTrue(try drag(manager, from: try node(x, frame: 2),
                               by: CGSize(width: ppf * 8, height: 0), expecting: id(.x)))
        XCTAssertEqual(try channel(manager, id(.x)).curve.keys.map(\.frame), [0, 5, 12],
                       "It stopped at frame 5, the last frame of its own cel — not at 11, one short "
                       + "of the neighbour it can see")
        XCTAssertEqual(manager.layers[1].cels[1].transformTracks[TransformChannelID.cel.id]?
                        .curve(.x)?.keys.map(\.frame), [6],
                       "…and the second cel's own key is untouched")
    }
}
