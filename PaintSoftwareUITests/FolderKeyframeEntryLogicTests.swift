import XCTest
import UIKit

/// **A folder's keyframes had no entry point** — TODO (21), found by the layer-opacity work on
/// 2026-09-10, built from `FolderOptionsPanel`'s own keyframe rows.
///
/// **What this file exists to prove, and what it deliberately does not.** Nothing in the *model* was
/// missing: `addKeyframe(_:atFrame:)` has taken a `KeyframeTarget` since stage 3b and the `.folder`
/// arm has always worked. So a test that calls `addKeyframe(.folder(…))` and reads back
/// `keyframeMarks` would pass on the commit before this one as readily as on this one, and would be
/// the "green assertion about the wrong thing" CLAUDE.md has a section on. The assertions here are
/// therefore about the three things the entry point has to be *true of* rather than about the call
/// landing:
///
///  * **§2.28's union, computed independently.** Every comparison's right-hand side is rebuilt from
///    the folder's own stored fields — `keyframeMarks`, `effectTracks`, `channelTracks` and
///    `transform?.track` — by `storedUnion(_:_:)` below, which never calls the accessor it is
///    checking. A test that read `keyframeFrames(of:)` on both sides would be comparing one
///    expression with itself.
///  * **What is drawn.** The workflow test's operands are the *folder node's opacity in the render
///    tree* at three frames, which is the number the compositor multiplies alpha by — not the curve,
///    and not the stored field. An assertion about `AnimationCurve` alone is true under any
///    implementation including one that reaches no tree.
///  * **That the entry point takes no channel argument.** One press has to serve the grade, every
///    row of `TargetChannel.all` and the container pose. That is asserted by *iterating*
///    `TargetChannel.all` rather than by naming `.opacity`, so the day a second row lands the test
///    widens with it instead of silently covering half the table.
///
/// The panel rows themselves are in `Views/LayerPanel.swift`, which is **not** compiled into this
/// target — so nothing here can pin them, and `FolderKeyframeEntryUITests` is what does.
@MainActor
final class FolderKeyframeEntryLogicTests: XCTestCase {

    // MARK: - Fixtures

    private let opacityID = TargetChannel.opacity.id
    private let brightnessID = "brightnessContrast.brightness"

    /// **A group with one drawing layer inside it and nothing animated anywhere** — the cold-start
    /// document the owner's four-step test starts from, minus the ink.
    ///
    /// The history is emptied afterwards because `addFolder` and `restackLayer` are both
    /// `withStructureUndo` edits; several tests below assert that some *later* action recorded exactly
    /// one step, which is unassertable while the fixture's own steps are still on the stack
    /// (`KeyframeControlLogicTests.gradedManager` carries the same note for the same reason).
    private func folderManager(frames: Int = 24) -> (manager: CanvasManager, folder: UUID,
                                                     target: KeyframeTarget) {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: frames)])
        let group = manager.addFolder(name: "Group")
        manager.restackLayer(manager.layers[0].id, above: .folder(group), parentFolderID: group)
        manager.currentLayerIndex = 0
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return (manager, group, .folder(id: group))
    }

    private func folderIndex(_ manager: CanvasManager, _ id: UUID,
                             file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let index = manager.folders.firstIndex(where: { $0.id == id }) else {
            XCTFail("The fixture's folder must be in the document, or every assertion below is "
                    + "about an absent target", file: file, line: line)
            return 0
        }
        return index
    }

    /// **§2.28's union rebuilt from the folder's stored fields, without asking the accessor.**
    ///
    /// This is the right-hand operand of every union assertion in this file, and it is the whole
    /// reason they are not tautologies. `CanvasManager.keyframeFrames(of:)` folds four sources; this
    /// folds the same four by reading `LayerFolder` directly, so the two agree only if the accessor
    /// is looking at all of them. A divergence here is precisely the defect §2.28 was written from —
    /// two lists that answer "is there a keyframe on this frame" differently.
    private func storedUnion(_ manager: CanvasManager, _ id: UUID) -> [Int] {
        guard let folder = manager.folders.first(where: { $0.id == id }) else { return [] }
        var frames = Set(folder.keyframeMarks)
        for curve in folder.effectTracks.values { frames.formUnion(curve.keys.map(\.frame)) }
        for curve in folder.channelTracks.values { frames.formUnion(curve.keys.map(\.frame)) }
        if let track = folder.transform?.track { frames.formUnion(track.keyedFrames) }
        return frames.sorted()
    }

    /// **The opacity the renderer would use for the folder at `frame`** — the group's `RenderNode`,
    /// which is the value `Compositor.draw` multiplies the whole group's alpha by.
    ///
    /// `OpacityChannelLogicTests.drawnOpacity`'s folder twin, and named the same way for the same
    /// reason: an assertion that reads `folders[i].opacity` pins the store, and the store is not what
    /// an artist sees.
    private func drawnFolderOpacity(_ manager: CanvasManager, _ id: UUID, atFrame frame: Int,
                                    file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard let node = flattened(manager.renderTree(atFrame: frame)).first(where: { $0.id == id })
        else {
            XCTFail("The group must have a node in the tree at frame \(frame), or there is nothing "
                    + "to assert an opacity about", file: file, line: line)
            return .nan
        }
        return node.opacity
    }

    private func flattened(_ nodes: [RenderNode]) -> [RenderNode] {
        nodes.flatMap { node -> [RenderNode] in
            guard case .node(_, let inputs) = node.content else { return [node] }
            return [node] + inputs.flatMap { flattened($0) }
        }
    }

    private func curve(_ pairs: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    /// One drag of the folder row's opacity slider, through the *same* call
    /// `LayerStackListView.onOpacityChange` makes. Named so a test reads as the artist's gesture.
    @discardableResult
    private func dragFolderOpacity(_ manager: CanvasManager, _ target: KeyframeTarget,
                                   to value: Double, atFrame frame: Int) -> KeyframeControl.Write {
        manager.currentFrame = frame
        return manager.applyTargetChannelEdit(target, channel: .opacity,
                                              newValue: value, atFrame: frame)
    }

    // MARK: - Cold start

    /// **A freshly made group carries no keyframes, and one press is the whole first step** — the
    /// model half of the owner's four-step test, and the premise every assertion below rests on.
    ///
    /// Operands: `keyframeFrames(of:)` against `storedUnion`, plus `hasKeyframe` swept across the
    /// scene. The sweep is what makes the "nowhere else" half real — a build that answered true for
    /// every frame would satisfy a single-frame assertion and would light the Remove row on every
    /// frame of the timeline.
    func testAFreshGroupHasNoKeyframesAndOnePressPlacesExactlyOne() {
        let (manager, folder, target) = folderManager()

        XCTAssertEqual(manager.keyframeFrames(of: target), [],
                       "A group nobody has keyed has no keyframes")
        XCTAssertEqual(storedUnion(manager, folder), [],
                       "…and its stored fields agree, which is the fixture premise")

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 7),
                      "The press must report that it changed the document, or the panel's row is inert")

        XCTAssertEqual(manager.keyframeFrames(of: target), [7])
        XCTAssertEqual(storedUnion(manager, folder), [7],
                       "The accessor and the folder's own fields must name the same one frame")
        for frame in 0..<24 where frame != 7 {
            XCTAssertFalse(manager.hasKeyframe(target, atFrame: frame),
                           "Frame \(frame) carries no keyframe, so the panel must not offer Remove "
                           + "there — a build that said yes everywhere passes a single-frame check")
        }
        XCTAssertTrue(manager.hasKeyframe(target, atFrame: 7),
                      "…and the frame the press named does, which is what lights the Remove row")
    }

    /// **One press, one undo step, and Undo puts the group back.**
    ///
    /// Operands: `canUndo` and the union, either side of `undo()`. A mark that cost two steps would
    /// leave the artist pressing Undo twice to take back one press, which is the shape
    /// `HistoryActionLabel`'s own notes are written against.
    func testPlacingAGroupKeyframeIsOneUndoStep() {
        let (manager, folder, target) = folderManager()
        manager.addKeyframe(target, atFrame: 3)

        XCTAssertTrue(manager.canUndo, "The press must be undoable")
        manager.undo()
        XCTAssertEqual(manager.keyframeFrames(of: target), [],
                       "Undo takes the mark off the group")
        XCTAssertEqual(storedUnion(manager, folder), [])
        XCTAssertFalse(manager.canUndo, "…and only one step, because there was only ever one press")
    }

    // MARK: - What the mark is *for* — §2.26 / §2.27

    /// **The mark is what turns the group's opacity slider from a setting into an animation tool**,
    /// and that is the whole reason this entry point had to exist.
    ///
    /// Operands: `keyframeWrite(_:channel:atFrame:)`'s answer **before** any mark, and its answer
    /// **after** one, on the same document. Before, the fifth arm — a slider is a slider and nothing
    /// about keyframes is visible. After, the fourth — the previous value is held for the next mark to
    /// commit. A pure function, asked twice, with one press between: so the assertion cannot be true
    /// of a build in which the press reached nothing.
    ///
    /// This is the assertion that would have gone red on the commit before this one had the panel row
    /// existed and written to the wrong target: `.layer(id:)` in place of `.folder(id:)` leaves the
    /// folder's own answer at `.storedValue`.
    func testTheMarkIsWhatMakesTheGroupsOpacitySliderHoldItsPreviousValue() {
        let (manager, _, target) = folderManager()

        XCTAssertEqual(manager.keyframeWrite(target, channel: .opacity, atFrame: 4), .storedValue,
                       "With no keyframe on the group, dragging its opacity is an ordinary setting "
                       + "— §2.26's fifth arm, and the state the feature starts from")

        manager.addKeyframe(target, atFrame: 4)

        XCTAssertEqual(manager.keyframeWrite(target, channel: .opacity, atFrame: 4),
                       .storedValueHoldingBaseline, """
                       One mark and the same drag now holds the previous value for the next mark to \
                       commit — §2.27. This is the routing arm the group could not reach before it \
                       had anywhere to place a mark from.
                       """)
    }

    /// **The owner's four steps on a group, asserted on what the canvas draws.**
    ///
    /// Mark at 0 → drag the group's opacity → mark at 10. Operands: the **folder node's opacity in
    /// the render tree** at frames 0, 5 and 10, against the two values the artist set. Frame 5 is the
    /// load-bearing one: it is neither value, so it can only be right if a curve exists *and* the
    /// tree resolves through it. Nothing here reads `channelTracks`.
    func testTheFourStepWorkflowOnAGroupProducesAnAnimationTheTreeDraws() {
        let (manager, folder, target) = folderManager()

        // 1. A bare mark at A. "Keyframe A is added, nothing is saved."
        manager.addKeyframe(target, atFrame: 0)
        XCTAssertEqual(drawnFolderOpacity(manager, folder, atFrame: 10), 1, accuracy: 0.0001,
                       "A mark alone animates nothing — the group still draws at full opacity "
                       + "everywhere, which is §2.26's first step stated as a picture")

        // 2. The slider moves at B. The previous value is held, not keyed.
        XCTAssertEqual(dragFolderOpacity(manager, target, to: 0.25, atFrame: 10),
                       .storedValueHoldingBaseline,
                       "Fixture premise: the drag held rather than keyed")

        // 3. Mark at B commits it.
        manager.addKeyframe(target, atFrame: 10)

        XCTAssertEqual(drawnFolderOpacity(manager, folder, atFrame: 0), 1, accuracy: 0.0001,
                       "The held value landed on A, so the group draws fully opaque at frame 0")
        XCTAssertEqual(drawnFolderOpacity(manager, folder, atFrame: 10), 0.25, accuracy: 0.0001,
                       "…and the new value is on B")
        XCTAssertEqual(drawnFolderOpacity(manager, folder, atFrame: 5), 0.625, accuracy: 0.0001, """
                       Halfway along the segment the tree draws the interpolated value. This is the \
                       assertion that fails under a build which stores a curve the render tree never \
                       consults, and it is neither of the two values the artist typed.
                       """)
    }

    /// **The two keyframes the artist placed are the two the union reports, and the marks are gone.**
    ///
    /// Operands: `folders[i].keyframeMarks` — the explicit list — against `keyframeFrames(of:)`, the
    /// union, after the same four steps. §2.28's rule is that the two lists are *disjoint*: a mark is
    /// stored only for a frame no channel keys, so once both marks are keyed the mark list must be
    /// empty while the union still names both frames. A build that kept the marks would draw a
    /// keyframe indicator that outlives the node under it, which is the report §2.28 was written from
    /// three times.
    func testOnceTheChannelKeysThemTheGroupsMarksAreDroppedAndOnlyTheUnionRemains() {
        let (manager, folder, target) = folderManager()
        let index = folderIndex(manager, folder)

        manager.addKeyframe(target, atFrame: 0)
        XCTAssertEqual(manager.folders[index].keyframeMarks, [0],
                       "Fixture premise: an unkeyed mark is stored, because nothing else can hold it")

        dragFolderOpacity(manager, target, to: 0.25, atFrame: 10)
        manager.addKeyframe(target, atFrame: 10)

        XCTAssertEqual(manager.folders[index].keyframeMarks, [], """
                       Both frames are keyed now, so neither needs a mark — `marks(_:droppingKeyed:)` \
                       on the folder home. A leftover mark here is §2.28's divergence.
                       """)
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 10],
                       "…and the union still names both, because the keys answer for them")
        XCTAssertEqual(storedUnion(manager, folder), [0, 10],
                       "The accessor and the folder's stored fields must agree, computed apart")
    }

    // MARK: - One press, every channel kind

    /// **One press serves the grade, every `TargetChannel` row and the container pose** — requirement
    /// 1, and the reason the panel row takes a `KeyframeTarget` and a frame and nothing else.
    ///
    /// Operands: for each of the three stores, *whether a key now sits on frame 10*, against the
    /// single `addKeyframe` call that is supposed to have put it there. Every one of the three is
    /// keyed 0 and 20 beforehand, so §2.24's surviving half — "hold this pose here" — must reach all
    /// of them or the group drifts through the new mark on whichever channel was missed.
    ///
    /// **The `TargetChannel` half iterates `all` rather than naming `.opacity`.** `addKeyframe`'s own
    /// loop is `for channel in TargetChannel.all`, so the day a second row lands (a blend amount, an
    /// effect strength) this assertion covers it without being rewritten — which is the claim that
    /// "the next row needs no third case here" stated as a test rather than as a comment.
    func testOneGroupKeyframePressHoldsEveryChannelKindAtOnce() {
        let (manager, folder, target) = folderManager(frames: 32)
        let index = folderIndex(manager, folder)

        manager.setNodeEffect(folder, to: .brightnessContrast(
            Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        let at = folderIndex(manager, folder)
        manager.folders[at].effectTracks[brightnessID] = curve([(0, 1), (20, 2)])
        for channel in TargetChannel.all {
            manager.folders[at].channelTracks[channel.id] = curve([(0, 1), (20, 0.2)])
        }
        guard var pose = manager.restingContainerPose else {
            return XCTFail("The fixture's canvas must have a size, or there is no resting pose to "
                           + "build a container channel from")
        }
        let resting = pose.pose
        pose.track.setKey(TransformTrack.Key(frame: 0, pose: resting))
        pose.track.setKey(TransformTrack.Key(frame: 20, pose: resting))
        manager.folders[at].transform = pose
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 20],
                       "Fixture premise: three channel kinds, all keyed on the same two frames")

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 10),
                      "One press on the group's Add Keyframe row")

        XCTAssertNotNil(manager.folders[index].effectTracks[brightnessID]?
                            .keys.first { $0.frame == 10 },
                        "The grade's channel took a key at 10 — §2.21's home, §2.24's hold")
        for channel in TargetChannel.all {
            XCTAssertNotNil(manager.folders[index].channelTracks[channel.id]?
                                .keys.first { $0.frame == 10 },
                            "\(channel.name): every row of `TargetChannel.all` took a key at 10, so "
                            + "the next row added to that table needs no new case in the panel")
        }
        XCTAssertNotNil(manager.folders[index].transform?.track.key(atFrame: 10),
                        "The container pose took a key at 10 — the kind that lives on `LayerPose` "
                        + "rather than in a curve dictionary, and the one a per-kind entry point "
                        + "would have forgotten")
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 10, 20],
                       "…and the union names the new frame once, however many channels key it")
        XCTAssertEqual(storedUnion(manager, folder), [0, 10, 20])
    }

    // MARK: - Remove

    /// **Remove is offered for a key that has no mark, and takes every channel's key with it.**
    ///
    /// Operands: `hasKeyframe(_:atFrame:)` — the predicate the panel computes the Remove row's
    /// presence from — against `folders[i].keyframeMarks`, which does *not* contain the frame. The
    /// whole point: after the four-step workflow there are no marks left, so a Remove row gated on
    /// the mark list would vanish exactly when the artist has an animation to edit. That is §2.28's
    /// second reported symptom — "a diamond with no Remove Keyframe".
    func testRemoveIsOfferedForAGroupKeyframeThatHasNoMarkAndClearsEveryChannel() {
        let (manager, folder, target) = folderManager()
        let index = folderIndex(manager, folder)

        manager.addKeyframe(target, atFrame: 0)
        dragFolderOpacity(manager, target, to: 0.25, atFrame: 10)
        manager.addKeyframe(target, atFrame: 10)

        XCTAssertFalse(manager.folders[index].keyframeMarks.contains(10),
                       "Fixture premise: frame 10 carries a key and no mark")
        XCTAssertTrue(manager.hasKeyframe(target, atFrame: 10),
                      "…and the panel still offers Remove there, because the predicate is the union "
                      + "and not the mark list")

        XCTAssertTrue(manager.removeKeyframe(target, atFrame: 10),
                      "Remove must report that it changed the document")
        XCTAssertEqual(manager.keyframeFrames(of: target), [0],
                       "Frame 10 is no longer a keyframe of the group")
        XCTAssertEqual(storedUnion(manager, folder), [0],
                       "…by the folder's own fields as well as by the accessor")
        XCTAssertNil(manager.folders[index].channelTracks[opacityID]?.keys.first { $0.frame == 10 },
                     "The opacity key went with the keyframe — leaving it would take the diamond off "
                     + "the timeline and leave the fade doing exactly what it did")
    }

    /// **A group's Remove does not reach into its children**, which is the one thing a container
    /// action has to be checked for.
    ///
    /// Operands: the *layer's* union either side of a `removeKeyframe` on the folder. A folder is a
    /// `KeyframeTarget` in its own right (`TimelineFolderRowView`'s own note: aggregating its
    /// descendants' keys "would draw a marker with no target to attribute it to"), so the artist who
    /// clears the group's keyframe must not lose the drawing's.
    func testRemovingAGroupKeyframeLeavesItsChildrensKeyframesAlone() {
        let (manager, folder, target) = folderManager()
        let child = KeyframeTarget.layer(id: manager.layers[0].id)

        manager.addKeyframe(target, atFrame: 5)
        manager.addKeyframe(child, atFrame: 5)
        XCTAssertEqual(manager.keyframeFrames(of: child), [5], "Fixture premise: the layer is keyed too")

        manager.removeKeyframe(target, atFrame: 5)

        XCTAssertEqual(manager.keyframeFrames(of: target), [],
                       "The group's keyframe went")
        XCTAssertEqual(manager.keyframeFrames(of: child), [5],
                       "…and the layer inside it kept its own, which is what addressing by target "
                       + "rather than by subtree means")
    }
}
