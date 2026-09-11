import XCTest


/// **Keyframable layer opacity** — the owner's ask of 2026-09-09, *"layer opacity should also be
/// able to be keyframed, currently its not"*, and TODO (21)'s second channel *kind*.
///
/// **What this file has to prove is not "a curve can be stored".** Every failure shape CLAUDE.md
/// records for this repo is a green assertion about the wrong thing, and three of them are live
/// here:
///
///  * **A field the render path does not read.** `Layer.layerEffect` is `kind == .value ? effect :
///    nil`, so writing `layers[0].effect` on a raster layer pins nothing. The opacity equivalent
///    would be asserting `layer.channelTracks[...]` and calling it done — storage, not behaviour.
///    So the load-bearing assertions here read **`RenderNode.opacity`**, which is the number the
///    compositor multiplies alpha by, and **`FrameBakeKey`**, which is the name of the file on disk.
///  * **An assertion true at the wrong level.** "A curve evaluates differently at two frames" is
///    true of `AnimationCurve` under any implementation of this feature, including one that never
///    reaches the tree. The operands below are always *the document's own render tree at two
///    frames*, never the curve.
///  * **A per-row fresh fixture.** Every comparison here mutates one manager, so a difference is
///    attributable to the mutation rather than to two allocations.
@MainActor
final class OpacityChannelLogicTests: XCTestCase {

    // MARK: - Fixtures

    private let channel = TargetChannel.opacity
    private var opacityID: String { TargetChannel.opacity.id }

    /// A wall clock the test moves itself — `RecordingLogicTests`' fixture, reused because a take's
    /// timestamps come off the same `playbackNow` closure.
    private final class FakeClock {
        var now: TimeInterval = 1_000
    }

    /// **A plain drawing layer, no grade anywhere in the document** — and that is the fixture's
    /// whole point rather than incidental brevity.
    ///
    /// Opacity is a property of every layer. If a single assertion below only holds on a `.value`
    /// layer in effect mode, the channel has been built as an appendix to the grade rather than as
    /// a channel of the layer, and this fixture is what says so.
    private func drawingManager(frames: Int = 24) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: frames)])
        manager.currentLayerIndex = 0
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return manager
    }

    private func target(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[0].id)
    }

    private func curve(_ pairs: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    /// **The opacity the *renderer* would use for layer 0 at `frame`** — the leaf's `RenderNode`,
    /// which is the value `Compositor.draw` multiplies the layer's alpha by.
    ///
    /// Named so that every assertion below reads as "what the canvas shows", because that is the
    /// operand this feature is about. Reading `layers[0].opacity` instead would pin the store.
    private func drawnOpacity(_ manager: CanvasManager, atFrame frame: Int,
                              file: StaticString = #filePath, line: UInt = #line) -> Double {
        let id = manager.layers[0].id
        guard let node = flattened(manager.renderTree(atFrame: frame)).first(where: { $0.id == id })
        else {
            XCTFail("Layer 0 must have a node in the tree at frame \(frame), or there is nothing "
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

    /// The name of the file the bake store would write for `frame` — the on-disk identity of the
    /// picture, so two frames that differ in what they draw must differ here.
    private func bakeFileName(_ manager: CanvasManager, atFrame frame: Int,
                              file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let recipe = manager.makeFrameRecipe(atFrame: frame, quality: .full,
                                                   includeBackground: true, sizing: .native) else {
            XCTFail("The manager has no canvas size, so it mints no recipe at frame \(frame)",
                    file: file, line: line)
            return ""
        }
        return FrameBakeKey(recipe: recipe, renderResolution: .full,
                            maskTuningGeneration: 0, backend: .coreGraphics).fileName
    }

    // MARK: - What is drawn

    /// **The claim the whole feature reduces to: the picture differs between two frames.**
    ///
    /// The two operands are *the render tree's leaf opacity at frame 0* and *at frame 12*, on one
    /// document with one curve written on it. Neither is the curve, and neither is the stored field.
    ///
    /// It cannot pass under a build where `renderNodes(inContainer:atFrame:)` reads `layer.opacity`
    /// — both frames would answer the stored 1.0 — nor under one where the resolution is right and
    /// the tree is not, which is the "correct value drawn in the wrong place" failure that shipped
    /// three unusable features in one pass.
    func testTheRenderTreeShowsTheOpacityTheCurveResolvesToAtEachFrame() {
        let manager = drawingManager()
        manager.layers[0].channelTracks[opacityID] = curve([(0, 1), (12, 0)])

        XCTAssertEqual(drawnOpacity(manager, atFrame: 0), 1, accuracy: 0.0001,
                       "At the first key the leaf draws that key's value")
        XCTAssertEqual(drawnOpacity(manager, atFrame: 6), 0.5, accuracy: 0.0001,
                       "Halfway along a linear segment the leaf draws the interpolated value — this "
                       + "is the assertion a build that resolved nowhere near the tree fails")
        XCTAssertEqual(drawnOpacity(manager, atFrame: 12), 0, accuracy: 0.0001,
                       "At the last key the leaf draws that key's value")
    }

    /// **A document nobody has animated is untouched, and the guard is what guarantees it.**
    ///
    /// Operands: the leaf's opacity with no curve, against the stored number. The failure this
    /// forbids is a resolver that returns `AnimationCurve().evaluate(at:)`'s total answer — 0 — for
    /// an absent curve, which would fade every layer in every existing document to nothing.
    func testALayerWithNoCurveDrawsItsStoredOpacityUnchanged() {
        let manager = drawingManager()
        manager.layers[0].opacity = 0.42

        XCTAssertEqual(drawnOpacity(manager, atFrame: 0), 0.42, accuracy: 0.0001,
                       "With no curve the leaf draws the stored value")
        XCTAssertEqual(drawnOpacity(manager, atFrame: 20), 0.42, accuracy: 0.0001,
                       "…at every frame, including ones far from any keyframe")
        XCTAssertTrue(manager.layers[0].channelTracks.isEmpty,
                      "Fixture premise: nothing wrote a track, so the guard is the thing under test")
    }

    /// **A folder's opacity is the same channel, not a second feature** — the design question the
    /// owner's ask forces, answered as an assertion rather than in a comment.
    ///
    /// Operands: the *folder's* node opacity in the tree at two frames, written through the same
    /// `TargetChannel.opacity` descriptor that the layer test above uses. One descriptor, two key
    /// paths; a build that special-cased the layer fails here with no other symptom.
    func testAFoldersOpacityAnimatesThroughTheSameChannel() {
        let manager = drawingManager()
        let group = manager.addFolder(name: "Group")
        manager.restackLayer(manager.layers[0].id, above: .folder(group), parentFolderID: group)
        guard let index = manager.folders.firstIndex(where: { $0.id == group }) else {
            return XCTFail("Fixture premise: the folder must be in the document")
        }
        manager.folders[index].channelTracks[opacityID] = curve([(0, 1), (10, 0.25)])

        let at0 = flattened(manager.renderTree(atFrame: 0)).first { $0.id == group }
        let at10 = flattened(manager.renderTree(atFrame: 10)).first { $0.id == group }
        XCTAssertEqual(at0?.opacity ?? .nan, 1, accuracy: 0.0001,
                       "The group node draws the curve's value at frame 0")
        XCTAssertEqual(at10?.opacity ?? .nan, 0.25, accuracy: 0.0001,
                       "…and its value at frame 10, through the same descriptor the layer uses")
    }

    /// **An overshooting handle cannot put alpha out of gamut.**
    ///
    /// Operands: the leaf opacity at the overshoot's peak, against 1. `TargetChannel.modelDomain`
    /// is `0...1` for opacity — unlike an effect parameter's, which is usually *wider* than the
    /// slider precisely so a graph editor can overshoot — so the clamp is the descriptor's, applied
    /// once in `resolvedValue`.
    func testAnOvershootingCurveIsClampedIntoTheChannelsDomain() {
        let manager = drawingManager()
        manager.layers[0].channelTracks[opacityID] = curve([(0, 0), (5, 1.8), (10, -0.6)])

        XCTAssertEqual(drawnOpacity(manager, atFrame: 5), 1, accuracy: 0.0001,
                       "A key above the domain draws at the top of it, not above")
        XCTAssertEqual(drawnOpacity(manager, atFrame: 10), 0, accuracy: 0.0001,
                       "…and one below draws at the bottom")
    }

    /// **The bake store must not serve one file for two different pictures** — KEYFRAMES §4.5's
    /// caching trap, which the spec says to pin on day one.
    ///
    /// Operands: the content-addressed file name at frame 0 and at frame 12 of one animated
    /// document. `FrameBakeKey` digests `RenderNode.opacity`, so this holds *because* the resolution
    /// happens in the tree — and it is the assertion that would go red if a later change resolved
    /// opacity somewhere further down, in the compositor, where the key cannot see it. That is the
    /// failure mode this test exists for: the canvas would look right and the disk cache would serve
    /// the wrong frame.
    func testTwoFramesOfAnOpacityAnimationNameTwoDifferentBakeFiles() {
        let manager = drawingManager()
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(.red,
                                                               rect: CGRect(x: 4, y: 4, width: 20, height: 20)))
        let before = bakeFileName(manager, atFrame: 0)
        XCTAssertEqual(before, bakeFileName(manager, atFrame: 12),
                       "Fixture premise: with no curve, one hold is one file — that is §3.3's claim "
                       + "and it is what makes the difference below attributable to the curve")

        manager.layers[0].channelTracks[opacityID] = curve([(0, 1), (12, 0.1)])
        XCTAssertNotEqual(bakeFileName(manager, atFrame: 0), bakeFileName(manager, atFrame: 12),
                          "Two frames an opacity curve draws differently must name two files, or the "
                          + "store serves frame 0's pixels for frame 12")
    }

    // MARK: - §2.28's union — one accessor, never a second list

    /// **An opacity key is a keyframe, on a layer with no grade whatsoever.**
    ///
    /// Operands: `keyframeFrames(of:)` — the one accessor, which the timeline's markers and the cel
    /// menu both read — against the frames the curve keys. The gate this is aimed at is real and one
    /// line long: `keyedFrames` ignores `effectTracks` entirely unless `storedEffect(of:) != nil`,
    /// which is right for the grade's channels and would be catastrophic here. Under that gate this
    /// fixture reports **no** keyframes at all, and the artist gets a graph-editor node with no
    /// indicator on the cel — the exact divergence §2.28 exists to forbid, reported three times.
    func testAnOpacityKeyIsAKeyframeOnALayerThatGradesNothing() {
        let manager = drawingManager()
        let tgt = target(manager)
        XCTAssertNil(manager.storedEffect(of: tgt),
                     "Fixture premise: this layer has no grade, so the grade's gate is in force")

        manager.layers[0].channelTracks[opacityID] = curve([(3, 1), (9, 0)])

        XCTAssertEqual(manager.keyframeFrames(of: tgt), [3, 9],
                       "The union counts an opacity key exactly as it counts a pose key")
        XCTAssertTrue(manager.hasKeyframe(tgt, atFrame: 9),
                      "…so the cel menu offers Remove Keyframe on a frame the artist can see a node on")
        XCTAssertFalse(manager.hasKeyframe(tgt, atFrame: 5),
                       "…and does not offer it between two keys, where there is no node")
    }

    /// **Remove Keyframe takes the opacity key with it.**
    ///
    /// Operands: the curve's keys before and after, and the union before and after. Leaving the key
    /// behind would take the diamond off the timeline and leave the fade running, which is the shape
    /// of a control that appears not to work — `clearKeyframes`' own stated reason for dropping the
    /// grade's keys, which this channel had to join rather than be forgotten by.
    func testRemovingAKeyframeDropsTheOpacityKeyOnThatFrame() {
        let manager = drawingManager()
        let tgt = target(manager)
        manager.layers[0].channelTracks[opacityID] = curve([(3, 1), (9, 0)])

        XCTAssertTrue(manager.removeKeyframe(tgt, atFrame: 9), "The write changed the document")

        XCTAssertEqual(manager.layers[0].channelTracks[opacityID]?.keys.map(\.frame), [3],
                       "The key on the removed frame is gone and the other is untouched")
        XCTAssertEqual(manager.keyframeFrames(of: tgt), [3],
                       "…and the timeline agrees, because both read the one accessor")
    }

    /// **A mark a key lands on is dropped** — the owner's rule of 2026-09-03, *"if a node exists on
    /// the graph editor, it should also exist on the cel as an indicator and vice versa"*.
    ///
    /// Operands: `keyframeMarks` (the explicit list) and `keyframeFrames` (the union) after a key
    /// lands on a marked frame. The first must lose the frame and the second must keep it. A new
    /// channel that wrote its keys outside `commitKeyframeState` would pass the second and fail the
    /// first, leaving a mark beside a key — which is the state that made a dragged node leave its
    /// indicator behind.
    func testAKeyLandingOnAMarkedFrameDropsTheMark() {
        let manager = drawingManager()
        let tgt = target(manager)
        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 4), "A bare mark is placed")
        XCTAssertEqual(manager.layers[0].keyframeMarks, [4], "Fixture premise: the mark is stored")

        XCTAssertEqual(manager.setTargetChannelKeys(tgt, frame: 4, values: [opacityID: 0.5]), 1,
                       "One channel took a key")

        XCTAssertEqual(manager.layers[0].keyframeMarks, [],
                       "The mark is dropped once a key answers for that frame")
        XCTAssertEqual(manager.keyframeFrames(of: tgt), [4],
                       "…and the frame is still a keyframe, now by its key")
    }

    // MARK: - The owner's A-then-B workflow, on opacity

    /// **§2.26 and §2.27 end to end on a plain drawing layer** — the artist's actual path, and the
    /// one an XCUITest drives with a finger.
    ///
    /// *"Keyframe A is added, nothing is saved. A slider is then adjusted. The previous value is
    /// held. Then keyframe B is added. That previous value gets saved to A and the new value gets
    /// saved to B."*
    ///
    /// The operands are the **drawn** opacity at A and at B — the render tree, not the curve — so
    /// this is a statement about what the artist sees when they scrub between the two marks.
    func testTheOwnersABWorkflowProducesAFadeOnAPlainLayer() {
        let manager = drawingManager()
        let tgt = target(manager)
        manager.layers[0].opacity = 1
        manager.currentFrame = 0

        // A.
        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 0), "Keyframe A is placed")
        XCTAssertTrue(manager.layers[0].channelTracks.isEmpty,
                      "…and nothing is saved by it — the owner's first sentence")

        // The slider moves. One tick is enough; the rule is about routing, not about the drag.
        manager.currentFrame = 6
        let route = manager.applyTargetChannelEdit(tgt, channel: channel, newValue: 0.2, atFrame: 6)
        XCTAssertEqual(route, .storedValueHoldingBaseline,
                       "With one keyframe and no neighbour to seed onto, the edit holds the old value")
        XCTAssertEqual(manager.layers[0].channelBaselines[opacityID], 1,
                       "The held value is the one at A, recorded beside the ordinary write")
        XCTAssertEqual(manager.layers[0].opacity, 0.2, accuracy: 0.0001,
                       "…and the ordinary write still happened, so the artist sees the value move")

        // B.
        manager.currentFrame = 12
        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 12), "Keyframe B is placed")
        XCTAssertTrue(manager.layers[0].channelBaselines.isEmpty, "The held value is consumed")

        XCTAssertEqual(drawnOpacity(manager, atFrame: 0), 1, accuracy: 0.0001,
                       "A holds the value the artist moved away from")
        XCTAssertEqual(drawnOpacity(manager, atFrame: 12), 0.2, accuracy: 0.0001,
                       "B holds the value they moved to")
        XCTAssertLessThan(drawnOpacity(manager, atFrame: 6), 1,
                          "…and the frames between the two are genuinely a fade rather than a hold")
        XCTAssertGreaterThan(drawnOpacity(manager, atFrame: 6), 0.2,
                             "…in both directions, which is what makes it an interpolation")
    }

    /// **Once a curve exists, every later edit keys** — §2.23's surviving half, and the reason it is
    /// not optional: the settings surface reads the value resolved at the playhead, so an edit
    /// routed to the stored base would be overwritten by the curve and spring back under the
    /// artist's finger. The alternative to keying is a dead control.
    ///
    /// Operands: the routing arm, and the curve's key count before and after.
    func testAnEditOnAnAnimatedChannelWritesAKeyRatherThanTheBase() {
        let manager = drawingManager()
        let tgt = target(manager)
        manager.layers[0].opacity = 1
        manager.layers[0].channelTracks[opacityID] = curve([(0, 1), (12, 0.2)])

        let route = manager.applyTargetChannelEdit(tgt, channel: channel, newValue: 0.7, atFrame: 6)

        XCTAssertEqual(route, .key, "A channel with a curve keys, whatever the playhead is standing on")
        XCTAssertEqual(manager.layers[0].channelTracks[opacityID]?.keys.map(\.frame), [0, 6, 12],
                       "…and the key lands at the playhead")
        XCTAssertEqual(manager.layers[0].opacity, 1, accuracy: 0.0001,
                       "The stored base is untouched — writing it would bake a curve's value into it")
        XCTAssertEqual(drawnOpacity(manager, atFrame: 6), 0.7, accuracy: 0.0001,
                       "…and the canvas shows what the artist just dragged to")
    }

    /// **A document nobody has keyframed is a plain slider.** Operands: the routing arm and the
    /// track dictionary. §2.26's fifth arm — *"nothing about this feature is visible"* — which is
    /// what stops this change altering how the opacity slider behaves for every existing user.
    func testWithNoKeyframesTheSliderJustSetsTheValue() {
        let manager = drawingManager()
        let tgt = target(manager)

        let route = manager.applyTargetChannelEdit(tgt, channel: channel, newValue: 0.3, atFrame: 4)

        XCTAssertEqual(route, .storedValue, "No keyframes means no keyframe rule")
        XCTAssertTrue(manager.layers[0].channelTracks.isEmpty, "…and no channel is created")
        XCTAssertTrue(manager.layers[0].channelBaselines.isEmpty, "…and nothing is held")
        XCTAssertEqual(manager.layers[0].opacity, 0.3, accuracy: 0.0001, "The number simply moved")
    }

    /// **Standing on one of two keyframes and moving the slider seeds the other** — §2.27's *"the
    /// user modifies another slider while on B"*, the arm that needs a neighbouring mark to exist.
    ///
    /// Operands: the two keys the write produced, by frame and value. The old value must land on the
    /// *neighbour* and the new one here; a build that keyed only the playhead would leave a one-key
    /// curve pinning the new value and lose the old one with nothing on screen to explain it.
    func testEditingWhileStandingOnBSeedsTheOldValueOntoA() {
        let manager = drawingManager()
        let tgt = target(manager)
        manager.layers[0].opacity = 0.9
        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 0), "A")
        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 10), "B")

        let route = manager.applyTargetChannelEdit(tgt, channel: channel, newValue: 0.1, atFrame: 10)

        XCTAssertEqual(route, .seedAndKey, "Two keyframes with the playhead on one is the seed arm")
        let keys = manager.layers[0].channelTracks[opacityID]?.keys ?? []
        XCTAssertEqual(keys.map(\.frame), [0, 10], "One key on each of the two keyframes")
        XCTAssertEqual(keys.first?.value ?? .nan, 0.9, accuracy: 0.0001,
                       "A receives the value the artist is moving away from")
        XCTAssertEqual(keys.last?.value ?? .nan, 0.1, accuracy: 0.0001,
                       "B receives the value they moved to")
    }

    // MARK: - The two stores stay apart — the finding that decided the design

    /// **An opacity baseline survives a grade change, and a `pendingBaselines` one would not.**
    ///
    /// This is the reason `channelBaselines` exists as a third home rather than as two more entries
    /// in `pendingBaselines`. Every writer of `Layer.effect` prunes that dictionary against the
    /// grade's descriptors — `Effect.channelEntriesAddressed(by:from:)`, five call sites — so an
    /// opacity baseline parked there is silently destroyed the moment the artist picks a different
    /// effect, and keyframe B then commits nothing. The artist would place A, fade, place B, and get
    /// no animation, with nothing on screen to explain it.
    ///
    /// Operands: the held value, before and after a real `setLayerEffect` call. The control operand
    /// is the *grade's* baseline in the same document, which must be pruned — otherwise this test
    /// would pass on a build where nothing prunes anything, and prove nothing about the split.
    func testAnOpacityBaselineOutlivesAGradeChangeAndTheGradesOwnDoesNot() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        let index = 1
        manager.currentLayerIndex = index
        let tgt = KeyframeTarget.layer(id: manager.layers[index].id)

        manager.layers[index].pendingBaselines["brightnessContrast.brightness"] = 1
        manager.layers[index].channelBaselines[opacityID] = 1

        manager.setLayerEffect(layerIndex: index, to: .posterize(Effect.Posterize(levels: 5)))

        XCTAssertNil(manager.layers[index].pendingBaselines["brightnessContrast.brightness"],
                     "Control: a grade's held value is pruned when the grade it addressed goes — this "
                     + "is the pruning the opacity baseline had to be kept out of")
        XCTAssertEqual(manager.layers[index].channelBaselines[opacityID], 1,
                       "Opacity is not a property of the grade, so its held value survives the change")
    }

    /// **And so does the opacity curve.** Same argument one field over:
    /// `Effect.tracksAddressed(by:from:)` destroys a curve the current grade cannot drive, which is
    /// correct for a grade's channel and would delete a fade the artist authored.
    ///
    /// Operands: the two dictionaries either side of one `setLayerEffect` call.
    func testAnOpacityCurveOutlivesAGradeChangeAndTheGradesOwnDoesNot() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        let index = 1
        manager.currentLayerIndex = index

        manager.layers[index].effectTracks["brightnessContrast.brightness"] = curve([(0, 1), (8, 2)])
        manager.layers[index].channelTracks[opacityID] = curve([(0, 1), (8, 0)])

        manager.setLayerEffect(layerIndex: index, to: .posterize(Effect.Posterize(levels: 5)))

        XCTAssertNil(manager.layers[index].effectTracks["brightnessContrast.brightness"],
                     "Control: a curve the new grade cannot drive is destroyed, by design")
        XCTAssertNotNil(manager.layers[index].channelTracks[opacityID],
                        "The opacity curve is not the grade's to destroy")
    }

    // MARK: - What the artist sees in the graph editor

    /// **The channel reaches the graph editor's list and its band.**
    ///
    /// A model that is correct and unreachable is the exact failure the owner found three of in one
    /// minute. Operands: the ids `graphBandListing(of:)` reports — the one walk that
    /// `graphBandContent`, `graphChannelGroups` and `setGraphChannels` all read — and the group name
    /// the popup draws. Both are what is *exposed*, not what is stored.
    ///
    /// The second assertion is the invariant §2.28 is written about: the band's membership and
    /// `listedAnimationChannelIDs` are two implementations of one question, pinned equal here in the
    /// direction that matters — a channel the band draws and the list does not offer is a curve the
    /// artist can see and cannot switch off.
    func testTheOpacityChannelIsListedAndNamedInTheGraphEditor() {
        let manager = drawingManager()
        let tgt = target(manager)
        manager.layers[0].channelTracks[opacityID] = curve([(0, 1), (12, 0)])
        manager.currentLayerIndex = 0
        manager.isGraphEditorOpen = true

        XCTAssertEqual(manager.graphBandListing(of: tgt).channels.map(\.parameterID), [opacityID],
                       "The band lists the opacity curve")
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: tgt), [opacityID],
                       "…and the model's own 'what is an animation' answer agrees with it")

        let groups = manager.graphChannelGroups ?? []
        XCTAssertEqual(groups.map(\.name), ["Opacity"],
                       "The popup names the group from the descriptor rather than falling back to its id")
        XCTAssertEqual(groups.first?.rows.map(\.name), ["Opacity"],
                       "…and the row inside it is the channel")
    }

    /// **A curve that holds one value is a curve in force and not an animation** —
    /// `AnimationCurve.isAnimated`, the owner's definition, applied to this channel like any other.
    ///
    /// Operands: the band's membership (which must include it, so the artist can edit it back) and
    /// the *animated* list (which must not, so a flat line is not offered as an animation). Two
    /// predicates, two jobs — the pair `curvedEffectChannelIDs` and `listedAnimationChannelIDs`
    /// exist to keep apart.
    func testAFlatOpacityCurveIsDrawnButNotListedAsAnAnimation() {
        let manager = drawingManager()
        let tgt = target(manager)
        manager.layers[0].channelTracks[opacityID] = curve([(0, 0.5), (12, 0.5)])
        manager.currentLayerIndex = 0
        manager.isGraphEditorOpen = true

        XCTAssertEqual(manager.graphBandListing(of: tgt).channels.map(\.parameterID), [opacityID],
                       "The band draws it, dashed, so the artist can put a key back")
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: tgt), [],
                       "…and the model does not call it an animation")
        XCTAssertEqual(manager.applyTargetChannelEdit(tgt, channel: channel,
                                                      newValue: 0.1, atFrame: 6), .key,
                       "…while an edit on it still keys, because it is in force — routing asks "
                       + "`channelHasCurve`, never `isAnimated`, and merging the two is a dead control")
    }

    /// **A node dragged in the band reaches the document, and its Delete works.**
    ///
    /// `writeGraphBandCurves` funnels every band gesture through `setEffectParameterTrack`, which
    /// refuses an id no `EffectParameter` claims — silently. Under that, an opacity node would move
    /// under the finger and spring back, and Delete Keyframe would do nothing.
    ///
    /// Operands: the curve after the write, and the union after the delete. The delete is asserted
    /// through `removeEffectParameterKey`, which is the method the node menu's Delete Keyframe
    /// button calls, so this is a pin on the artist's own path rather than on the store.
    func testTheBandsWriteAndTheNodeMenusDeleteBothReachTheOpacityCurve() {
        let manager = drawingManager()
        let tgt = target(manager)
        manager.layers[0].channelTracks[opacityID] = curve([(0, 1), (12, 0)])

        XCTAssertTrue(manager.setTargetChannelTrack(tgt, channelID: opacityID,
                                                    to: curve([(0, 1), (18, 0)])),
                      "A retimed curve is written")
        XCTAssertEqual(manager.layers[0].channelTracks[opacityID]?.keys.map(\.frame), [0, 18],
                       "…and the node really moved")

        XCTAssertTrue(manager.removeEffectParameterKey(layerIndex: 0, parameterID: opacityID, frame: 18),
                      "The node menu's Delete Keyframe reaches this channel's store")
        XCTAssertEqual(manager.keyframeFrames(of: tgt), [0],
                       "…and the timeline loses the indicator with it")
    }

    /// **A dragged node's readout says the number it is on** — and for a 0…1 channel that is a trap
    /// worth a test.
    ///
    /// `TimelineGraphBand.readout(value:format:)` applies the descriptor's `String(format:)` to the
    /// **stored** value, with no scale factor anywhere. A percentage format on opacity therefore
    /// prints a half-faded layer as `"0%"` — wrong by a factor of a hundred at every value the
    /// artist can drag to, and invisible to every other test here because the model would be right.
    ///
    /// The two operands are the readout string and the value it claims to show, compared by parsing
    /// the string back: a readout that does not round-trip is not a readout. Stated over
    /// `TargetChannel.all` rather than over opacity, so the next channel added to the table inherits
    /// the check instead of the trap.
    func testEveryTargetChannelsReadoutRoundTripsToTheValueItShows() {
        for channel in TargetChannel.all {
            let span = channel.uiRange.upperBound - channel.uiRange.lowerBound
            for step in 0...4 {
                let value = channel.uiRange.lowerBound + span * Double(step) / 4
                let text = TimelineGraphBand.readout(value: value, format: channel.format)
                guard let shown = Double(text) else {
                    XCTFail("\(channel.id): the readout \"\(text)\" for \(value) is not a number, so "
                            + "the band would show the artist something they cannot act on")
                    continue
                }
                XCTAssertEqual(shown, value, accuracy: span / 100,
                               "\(channel.id): the readout \"\(text)\" does not say \(value)")
            }
        }
    }

    // MARK: - Persistence — §3.5's field-presence versioning

    /// **The round trip, and both directions of the migration.**
    ///
    /// Three operands, each a different claim:
    ///  1. a curve written here comes back equal — the document keeps the animation;
    ///  2. a layer with no curve writes **no key at all**, so a document nobody has animated is
    ///     byte-for-byte the manifest it was and an older build sees nothing new;
    ///  3. a manifest written before this feature decodes with the field absent, which the model
    ///     takes as empty — absence is the whole migration.
    func testAnOpacityCurveSurvivesAManifestRoundTripAndItsAbsenceNeedsNoMigration() throws {
        let cel = CelManifest(id: UUID(), startFrame: 0, frameCount: 12, rasterFileName: "r.png")
        let animated = LayerManifest(id: UUID(), name: "Ink", opacity: 1, isVisible: true,
                                     channelTracks: [opacityID: curve([(0, 1), (12, 0)])],
                                     cels: [cel])
        let decoded = try JSONDecoder().decode(LayerManifest.self,
                                               from: try JSONEncoder().encode(animated))
        XCTAssertEqual(decoded.channelTracks?[opacityID], curve([(0, 1), (12, 0)]),
                       "The curve round-trips through the document format")

        let plain = LayerManifest(id: UUID(), name: "Ink", opacity: 1, isVisible: true, cels: [cel])
        let plainJSON = String(data: try JSONEncoder().encode(plain), encoding: .utf8) ?? ""
        XCTAssertFalse(plainJSON.contains("channelTracks"),
                       "A layer with no opacity curve writes no key, so its manifest is what it was")
        XCTAssertFalse(plainJSON.contains("channelBaselines"),
                       "…and the same for the held value")

        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Ink","opacity":1,"isVisible":true,
         "cels":[{"id":"\(UUID().uuidString)","startFrame":0,"frameCount":12,"rasterFileName":"r.png"}]}
        """
        let old = try JSONDecoder().decode(LayerManifest.self, from: Data(legacy.utf8))
        XCTAssertNil(old.channelTracks, "A manifest saved before this feature carries no such key")
        XCTAssertEqual(Layer(id: old.id, name: old.name, opacity: old.opacity,
                             isVisible: old.isVisible,
                             channelTracks: old.channelTracks ?? [:], cels: []).channelTracks, [:],
                       "…and the model reads absence as 'nothing animated', which is one meaning")
    }

    /// **The curve is in a key of its own, and that is what makes the older build degrade
    /// gracefully.**
    ///
    /// Operands: `effectTracks` and `channelTracks` on a layer whose opacity is animated. Had the
    /// opacity curve ridden `effectTracks` — the tempting one-store design — a build without this
    /// feature would find an id no `EffectParameter` claims, count its keys into §2.28's union and
    /// draw keyframe diamonds for a channel it cannot render, then destroy them at the next grade
    /// change. This assertion is the whole of that argument in two lines.
    func testAnAnimatedOpacityWritesNothingIntoTheGradesOwnStore() {
        let manager = drawingManager()
        let tgt = target(manager)
        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 0))
        manager.applyTargetChannelEdit(tgt, channel: channel, newValue: 0.2, atFrame: 6)
        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 12))

        XCTAssertFalse(manager.layers[0].channelTracks.isEmpty,
                       "Fixture premise: the workflow really did produce a curve")
        XCTAssertTrue(manager.layers[0].effectTracks.isEmpty,
                      "…and none of it is in the grade's store, which an older build would misread")
        XCTAssertTrue(manager.layers[0].pendingBaselines.isEmpty,
                      "…nor in the grade's baselines, which its writers prune")
    }

    // MARK: - Recording — §5.1's shared trigger

    /// **A take on the opacity slider writes an opacity curve** — §5.1's *"a scalar surface is one
    /// line plus a routing hook"*, exercised through the same two calls the slider makes.
    ///
    /// Operands: the curve the take committed, and the stored base afterwards. The second is the
    /// one that is easy to get wrong: the base is a **scratch pad** during a take — the artist has
    /// to watch the layer fade under their finger — so it must be put back at the commit or the
    /// fade applies twice, once from the base and once from the curve.
    func testATakeOnTheOpacitySliderWritesACurveAndRestoresTheBase() {
        let manager = drawingManager(frames: 240)
        let clock = FakeClock()
        manager.playbackNow = { clock.now }
        let tgt = target(manager)
        manager.layers[0].opacity = 1

        XCTAssertNil(manager.armRecording(), "The recorder arms on a document with a scene to record")
        XCTAssertTrue(manager.beginArmedTake(on: tgt, isRecordable: true),
                      "The pencil landing on the opacity slider starts the take — §5.1's whole ruling")

        for (index, value) in [0.9, 0.6, 0.3, 0.1].enumerated() {
            clock.now = 1_000 + Double(index) * 0.25
            manager.applyTargetChannelEdit(tgt, channel: channel, newValue: value,
                                           atFrame: manager.currentFrame)
        }
        clock.now = 1_001
        XCTAssertNil(manager.stopRecording(), "The take produced something")

        let recorded = manager.layers[0].channelTracks[opacityID]
        XCTAssertNotNil(recorded, "The take wrote an opacity curve")
        XCTAssertTrue(recorded?.isAnimated ?? false,
                      "…and it is an animation by the owner's definition, not a flat line")
        XCTAssertEqual(manager.layers[0].opacity, 1, accuracy: 0.0001,
                       "The stored base is put back — it was a scratch pad for the length of the take")
    }

    /// **A take routes the value away from the keyframe rule while it runs.**
    ///
    /// Operands: the routing arm each reported value takes, and the key count. Keying per reported
    /// value is the aliased sample §5 forbids in its first paragraph — a three-second take would
    /// leave 72 keys a channel — so every tick must answer `.storedValue` even on a channel that
    /// already carries a curve, which is otherwise the `.key` arm.
    func testWhileATakeRunsEachReportedValueBypassesTheKeyframeRule() {
        let manager = drawingManager(frames: 240)
        let clock = FakeClock()
        manager.playbackNow = { clock.now }
        let tgt = target(manager)
        manager.layers[0].channelTracks[opacityID] = curve([(0, 1), (24, 0.5)])
        let keysBefore = manager.layers[0].channelTracks[opacityID]?.keys.count ?? 0

        XCTAssertNil(manager.armRecording())
        XCTAssertTrue(manager.beginArmedTake(on: tgt, isRecordable: true))

        clock.now = 1_000.1
        XCTAssertEqual(manager.applyTargetChannelEdit(tgt, channel: channel,
                                                      newValue: 0.8, atFrame: manager.currentFrame),
                       .storedValue,
                       "A live take takes the routing decision away, even from a channel with a curve")
        XCTAssertEqual(manager.layers[0].channelTracks[opacityID]?.keys.count, keysBefore,
                       "…so the tick wrote no key")
        manager.stopRecording()
    }

    // MARK: - Merging bakes the fade, so the curve goes with it

    /// **A merge drops the opacity curve it just baked into pixels.**
    ///
    /// `mergeLayers` resolves each layer's opacity at the merge frame, composites with it, and sets
    /// the survivor's own opacity to 1 because that fade is now in the pixels. A surviving curve
    /// would fade the merged result a second time.
    ///
    /// Operands: the survivor's `channelTracks` and its stored opacity, after a merge of a layer
    /// carrying a curve. The paired assertion is `vectorMergeIsExact`, which reads the *stored*
    /// opacity and would otherwise take the fast path on a layer stored at 1 and drawn at 0.2.
    func testMergingALayerWithAnOpacityCurveDropsTheCurveAndRefusesTheVectorFastPath() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Lower")
        manager.addVectorLayer(name: "Upper")
        manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: [])
        manager.layers[1].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: [])
        XCTAssertTrue(manager.vectorMergeIsExact(bottomIndex: 0, topIndex: 1),
                      "Fixture premise: two plain vector layers concatenate exactly")

        manager.layers[0].channelTracks[opacityID] = curve([(0, 1), (8, 0.2)])
        XCTAssertFalse(manager.vectorMergeIsExact(bottomIndex: 0, topIndex: 1),
                       "An animated opacity is not 1 at every frame, so the exact-concatenation "
                       + "predicate must refuse it — it reads the stored base, which the curve overrides")

        let survivor = manager.layers[0].id
        XCTAssertTrue(manager.mergeLayers(survivor, manager.layers[1].id), "The merge happened")
        guard let index = manager.layers.firstIndex(where: { $0.id == survivor }) else {
            return XCTFail("The survivor must still be in the document")
        }
        XCTAssertEqual(manager.layers[index].opacity, 1, accuracy: 0.0001,
                       "The survivor's own opacity is spent — that is what a merge already did")
        XCTAssertNil(manager.layers[index].channelTracks[opacityID],
                     "…and the curve that drove it goes too, or the merged pixels fade twice")
    }

    // MARK: - Undo

    /// **One opacity keyframe write is one undo step, and it takes the whole state back.**
    ///
    /// Operands: the curve and the marks before the write and after the undo. They ride in one
    /// `KeyframeState`, which is what makes "one artist action is one step" true by construction
    /// rather than by four careful closures — and adding a channel kind to that state is what bought
    /// this for free.
    func testOneKeyframePressOnOpacityIsOneUndoStep() {
        let manager = drawingManager()
        let tgt = target(manager)
        manager.layers[0].opacity = 1
        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 0))
        manager.applyTargetChannelEdit(tgt, channel: channel, newValue: 0.2, atFrame: 6)
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        XCTAssertTrue(manager.addKeyframe(tgt, atFrame: 12), "B commits the held value")
        XCTAssertEqual(manager.history.undoStack.count, 1,
                       "The mark, the baseline and the curve are one step, not three")

        manager.undo()
        XCTAssertTrue(manager.layers[0].channelTracks.isEmpty,
                      "One press of undo takes the whole commit back")
        XCTAssertEqual(manager.layers[0].channelBaselines[opacityID], 1,
                       "…including the held value, which is restored rather than lost")
    }

    // MARK: - The percentage the rail shows while you drag — TODO (59)

    /// **The readout's string, over the values a slider can be at.**
    ///
    /// `TargetChannel.format` is `"%.2f"` and is applied to the stored 0…1 number; a percentage
    /// spelled there would print a half-faded layer as `"0%"`, which is why `percentText` is its own
    /// function and why this test states the two ends and a rounding case rather than "it is
    /// non-empty".
    func testTheOpacityReadoutIsTheSlidersOwnPercentage() {
        XCTAssertEqual(channel.percentText(0), "0%")
        XCTAssertEqual(channel.percentText(1), "100%")
        XCTAssertEqual(channel.percentText(0.5), "50%")
        XCTAssertEqual(channel.percentText(0.875), "88%", "rounded to a whole percent, not truncated")
        XCTAssertEqual(channel.percentText(0.874), "87%")
        // The value handed in is a live slider position, so it must never print 103%.
        XCTAssertEqual(channel.percentText(1.03), "100%", "clamped into the control's own travel")
        XCTAssertEqual(channel.percentText(-0.2), "0%")
    }

    /// **The readout shows what the slider shows, which on an animated layer is not the stored
    /// base** — the one thing that could have gone wrong here, because layer opacity became
    /// keyframable the day before this was asked for.
    ///
    /// The two operands are the same layer read two ways at one frame: the percentage of the value
    /// the rail puts on the slider (`LayerRowModel` calls `opacity(atFrame:)`) and the percentage of
    /// `layers[0].opacity`, the stored base. They differ by 80 points here, so a readout wired to
    /// the wrong one is not a rounding question — it would disagree with both the slider under the
    /// finger and the canvas behind it.
    func testTheReadoutFollowsThePlayheadRatherThanTheStoredBase() {
        let manager = drawingManager()
        manager.layers[0].opacity = 1
        manager.layers[0].channelTracks[opacityID] = curve([(0, 1.0), (10, 0.2)])

        manager.currentFrame = 10
        let resolved = manager.layers[0].opacity(atFrame: manager.currentFrame)
        XCTAssertEqual(channel.percentText(resolved), "20%",
                       "the slider is at the value the playhead resolves, so the readout says 20%")
        XCTAssertEqual(channel.percentText(manager.layers[0].opacity), "100%",
                       "PREMISE: the stored base still says 100%, so the two really do disagree")
        XCTAssertEqual(channel.percentText(drawnOpacity(manager, atFrame: 10)), "20%",
                       "…and the readout agrees with what the compositor multiplies alpha by")

        manager.currentFrame = 5
        XCTAssertEqual(channel.percentText(manager.layers[0].opacity(atFrame: 5)), "60%",
                       "and it follows the playhead into an in-between rather than snapping to a key")
    }

    /// **A folder's readout is the same channel on the other home**, which is `TargetChannel`'s whole
    /// design claim and the reason the owner's *"both the layer rail's slider and a folder's"* costs
    /// nothing extra: one descriptor, two key paths.
    func testAFoldersReadoutIsTheSameChannelOnTheOtherHome() throws {
        let manager = drawingManager()
        let folderID = manager.addFolder(name: "Group")
        let index = try XCTUnwrap(manager.folders.firstIndex { $0.id == folderID },
                                  "PREMISE: the fixture has a folder to read")
        manager.folders[index].opacity = 1
        manager.folders[index].channelTracks[opacityID] = curve([(0, 1.0), (10, 0.4)])

        XCTAssertEqual(channel.percentText(manager.folders[index].opacity(atFrame: 10)), "40%")
        XCTAssertEqual(channel.percentText(manager.folders[index].opacity), "100%",
                       "PREMISE: the folder's stored base disagrees with the playhead too")
    }
}
