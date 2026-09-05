import XCTest
import CoreGraphics

/// **The transform channel's band, its rows, and the two funnels it made honest** — KEYFRAMES.md
/// §11.7.
///
/// `PoseComponentsLogicTests` beside this one pins the arithmetic — the six numbers, the round trip,
/// the projective refusal. This one pins everything that is about the *document*: which channels a
/// band lists, at which frames, what the channel list makes of them, that a node on the band and an
/// indicator on the track are the same thing (§2.28), and that the pose band takes no gesture.
///
/// Two of these tests are the funnels the transformation layer's own pass left open and named. Both
/// are §2.28's biconditional broken from a door §2.28 could not have known about, and both are
/// written so that reverting the one line that fixes them turns exactly one test red.
@MainActor
final class PoseBandLogicTests: XCTestCase {

    // MARK: - Fixtures

    private var size: CGSize { CanvasFixture.canvasSize }
    private var box: CGRect { CGRect(x: 4, y: 6, width: 16, height: 8) }

    private func stroke(_ points: [CGPoint]) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
    }

    private func slide(_ dx: CGFloat) -> PoseQuad {
        PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: dx, y: 0))
    }

    /// **A vector layer whose one cel starts at frame 4**, which is the whole point of the fixture:
    /// a cel track keys cel-local (§3.1) and the band's x is absolute, so a conversion that is
    /// missing is invisible on a cel that starts at 0.
    private func celFixture(start: Int = 4) -> (manager: CanvasManager, layerID: UUID, celID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cel = Cel(id: UUID(), startFrame: start, frameCount: 16,
                      raster: .empty(size: size), vector: .empty(size: size))
        cel.vector?.addStroke(stroke([CGPoint(x: 6, y: 10), CGPoint(x: 18, y: 10)]))
        manager.layers[1].cels = [cel]
        manager.sceneFrameCount = max(manager.sceneFrameCount, start + 16)
        manager.currentLayerIndex = 1
        manager.currentFrame = start
        manager.isGraphEditorOpen = true
        return (manager, manager.layers[1].id, cel.id)
    }

    private func target(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[manager.currentLayerIndex].id)
    }

    /// A pure slide on the whole-cel channel, cel-local frames 0 and 8.
    private func animateCel(_ manager: CanvasManager, layerID: UUID, celID: UUID,
                            channel: TransformChannelID = .cel, dx: CGFloat = 24) {
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: channel,
                                    atCelLocalFrame: 0, pose: PoseQuad(restingIn: box))
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: channel,
                                    atCelLocalFrame: 8, pose: slide(dx))
    }

    private func content(_ manager: CanvasManager) throws -> TimelineGraphBand.Content {
        try XCTUnwrap(manager.graphBandContent)
    }

    private func channel(_ content: TimelineGraphBand.Content,
                         _ id: String) -> TimelineGraphBand.Channel? {
        content.channels.first { $0.parameterID == id }
    }

    private var celX: String { PoseChannelID.cel(.cel).parameterID(.x) }
    private var celScaleX: String { PoseChannelID.cel(.cel).parameterID(.scaleX) }
    private var containerX: String { PoseChannelID.container.parameterID(.x) }

    // MARK: - The band lists a pose channel, at the timeline's own frames

    /// **A cel pose channel becomes six curves, keyed at *absolute* frames.**
    ///
    /// The cel starts at frame 4 and its keys are at cel-local 0 and 8, so the band draws them at 4
    /// and 12. Deleting `+ source.frameOffset` in `poseChannels` leaves them at 0 and 8, and the
    /// nodes then sit four frames left of the indicators on the track — the exact divergence §2.28
    /// exists to forbid, which is why the second assertion states the cel-local numbers as the thing
    /// the answer must *not* be.
    func testACelPoseChannelIsSixCurvesAtAbsoluteFrames() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)

        let content = try content(manager)
        XCTAssertEqual(content.channels.map(\.parameterID),
                       PoseComponents.Component.allCases.map { PoseChannelID.cel(.cel).parameterID($0) },
                       "Six channels, in `Component.allCases` order")
        XCTAssertEqual(content.channels.map(\.name),
                       ["X", "Y", "Scale X", "Scale Y", "Rotation", "Skew"])

        let x = try XCTUnwrap(channel(content, celX))
        XCTAssertEqual(x.curve.keys.map(\.frame), [4, 12],
                       "The cel starts at 4, so its cel-local 0 and 8 are absolute 4 and 12")
        XCTAssertNotEqual(x.curve.keys.map(\.frame), [0, 8],
                          "…and are emphatically not the numbers stored on the track")
    }

    /// **A pure slide animates X and leaves the other five flat**, which the band draws dashed and
    /// the model refuses to call animations.
    ///
    /// The values are checked against the geometry rather than against the decomposition: the box's
    /// centre starts at `box.midX` and ends 24 points right of it. An implementation that reported an
    /// offset from rest, or the box's origin, or a Y for an X, fails here and round-trips perfectly.
    func testASlideAnimatesXAloneAndTheRestAreDrawnFlat() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID, dx: 24)

        let content = try content(manager)
        let x = try XCTUnwrap(channel(content, celX))
        XCTAssertEqual(x.curve.keys.map(\.value), [Double(box.midX), Double(box.midX) + 24],
                       "X is where the box's centre is, in canvas points")
        XCTAssertTrue(x.isAnimated)

        for id in [PoseChannelID.cel(.cel).parameterID(.y),
                   celScaleX,
                   PoseChannelID.cel(.cel).parameterID(.rotation),
                   PoseChannelID.cel(.cel).parameterID(.skew)] {
            let flat = try XCTUnwrap(channel(content, id), id)
            XCTAssertFalse(flat.isAnimated, "\(id) is in force and is not an animation")
            XCTAssertEqual(Set(flat.curve.keys.map(\.value)).count, 1, "\(id) really is flat")
        }
        XCTAssertEqual(TimelineGraphBand.encode(content).contains("~"), true,
                       "…which the tier that cannot see a dash reads as `~` rather than `:`")
    }

    /// **A container pose is listed too, at its own time base** — §3.1's second kind, which needs no
    /// conversion because a transformation layer has no cel to ride.
    func testAContainerPoseIsListedInAbsoluteFramesWithNoOffset() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        let canvasBox = CGRect(origin: .zero, size: size)
        manager.layers[1].fill = nil
        manager.layers[1].transform = LayerPose(
            pose: PoseQuad(restingIn: canvasBox),
            track: TransformTrack(keys: [
                .init(frame: 0, pose: PoseQuad(restingIn: canvasBox)),
                .init(frame: 9, pose: PoseQuad(box: canvasBox,
                                               mappedBy: CGAffineTransform(translationX: 40, y: 0)))]))
        manager.currentLayerIndex = 1
        manager.isGraphEditorOpen = true

        let content = try content(manager)
        let x = try XCTUnwrap(channel(content, containerX))
        XCTAssertEqual(x.curve.keys.map(\.frame), [0, 9], "Document frames, exactly as stored")
        XCTAssertEqual(x.curve.keys.map(\.value),
                       [Double(canvasBox.midX), Double(canvasBox.midX) + 40])
    }

    /// **A layer that is not in transform mode contributes no pose channel**, which is
    /// `storedEffect(of:)`'s asymmetry one payload over: a pose left behind by a kind change poses
    /// nothing, so a curve for it would picture an animation the canvas is not running.
    func testAPoseLeftOnALayerThatIsNotInTransformModeIsNotListed() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        let canvasBox = CGRect(origin: .zero, size: size)
        manager.layers[1].transform = LayerPose(
            pose: PoseQuad(restingIn: canvasBox),
            track: TransformTrack(keys: [
                .init(frame: 0, pose: PoseQuad(restingIn: canvasBox)),
                .init(frame: 9, pose: PoseQuad(box: canvasBox,
                                               mappedBy: CGAffineTransform(translationX: 40, y: 0)))]))
        manager.currentLayerIndex = 1
        manager.isGraphEditorOpen = true
        XCTAssertNotNil(manager.layers[1].layerTransform, "Fixture: it is in transform mode now")
        XCTAssertFalse(try content(manager).channels.isEmpty)

        manager.layers[1].kind = .raster
        XCTAssertNil(manager.layers[1].layerTransform, "…and the kind flip takes it out of it")
        XCTAssertEqual(try content(manager).channels.map(\.parameterID), [],
                       "so the band draws nothing for a pose the renderer ignores")
    }

    // MARK: - §2.28's biconditional, in both directions

    /// **Every node on the band has an indicator on the track, and every indicator has a node** —
    /// the owner's rule of 2026-09-03, asked of the pose channel.
    func testEveryPoseNodeHasAnIndicatorAndEveryIndicatorHasANode() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)

        let nodes = Set(try content(manager).channels.flatMap { $0.curve.keys.map(\.frame) })
        XCTAssertEqual(nodes, [4, 12], "Fixture: the band has nodes somewhere")
        XCTAssertEqual(Set(manager.keyframeFrames(of: target(manager))), nodes,
                       "The union the timeline draws diamonds from is the band's own frames")
    }

    /// **A transformation layer's own keys reach `keyframeFrames`, and until §11.7 they did not.**
    ///
    /// `keyedFrames(of:tracks:)` folded the *cels'* pose tracks and stopped, with a comment that read
    /// as exhaustive — `Layer.transform` arrived afterwards. So a key on a transformation layer drew
    /// a node in the graph editor with no diamond beside it on the track, which is the report §2.28
    /// was written from, arriving through a third door.
    ///
    /// Watched failing with the `layerTransform` fold removed from `poseKeyframeFrames(inLayer:)`:
    /// this test and `testEveryPoseNodeHasAnIndicatorAndEveryIndicatorHasANode`'s container twin.
    func testATransformationLayersOwnKeysAreKeyframes() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        let canvasBox = CGRect(origin: .zero, size: size)
        manager.layers[1].fill = nil
        manager.layers[1].transform = LayerPose(
            pose: PoseQuad(restingIn: canvasBox),
            track: TransformTrack(keys: [
                .init(frame: 2, pose: PoseQuad(restingIn: canvasBox)),
                .init(frame: 11, pose: PoseQuad(box: canvasBox,
                                                mappedBy: CGAffineTransform(translationX: 40, y: 0)))]))
        manager.currentLayerIndex = 1
        manager.isGraphEditorOpen = true

        let target = KeyframeTarget.layer(id: manager.layers[1].id)
        XCTAssertEqual(manager.keyframeFrames(of: target), [2, 11])
        let nodes = Set(try content(manager).channels.flatMap { $0.curve.keys.map(\.frame) })
        XCTAssertEqual(nodes, [2, 11], "…which is exactly where the band puts its nodes")
    }

    /// **And so do a folder's**, §2.21's twin. `keyedFrames`' comment said a folder holds no cels and
    /// therefore no object channels, which was true and was read as exhaustive; §4.4 gave the folder
    /// a container pose of its own afterwards.
    func testAFoldersOwnPoseKeysAreKeyframes() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let folderID = manager.addFolder(name: "Moved")
        let canvasBox = CGRect(origin: .zero, size: size)
        let index = manager.folders.firstIndex { $0.id == folderID }
        XCTAssertNotNil(index, "Fixture: the folder is in the document")
        manager.folders[index!].transform = LayerPose(
            pose: PoseQuad(restingIn: canvasBox),
            track: TransformTrack(keys: [
                .init(frame: 3, pose: PoseQuad(restingIn: canvasBox)),
                .init(frame: 7, pose: PoseQuad(box: canvasBox,
                                               mappedBy: CGAffineTransform(translationX: 40, y: 0)))]))

        XCTAssertEqual(manager.keyframeFrames(of: .folder(id: folderID)), [3, 7])
    }

    /// **The band and `listedAnimationChannelIDs` are the same list, in both directions** — the pin
    /// the effect channels already carry, extended to the pose ones.
    ///
    /// **The fixture holds something the predicate must reject**, which is what makes it a pin rather
    /// than an identity: a pure slide leaves four of the six components flat, so an implementation
    /// that listed the whole track as animated returns six where this wants one.
    func testTheBandAndTheModelAgreeAboutWhichPoseChannelsAreAnimations() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)

        let drawn = try content(manager).channels.filter(\.isAnimated).map(\.parameterID)
        XCTAssertEqual(drawn, [celX], "Fixture: five of the six are refused")
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: target(manager)), drawn,
                       "The model's own answer, in the band's own order")
        XCTAssertFalse(manager.listedAnimationChannelIDs(of: target(manager)).contains(celScaleX),
                       "…and a flat component is not an animation")
    }

    // MARK: - The channel list — the fold and the navigator, §11.7

    /// **Two Move channels on one layer are two groups, which is the premise §11.5's fold was
    /// waiting for.** That section deferred the chevron because *"a band is one layer, a layer is one
    /// grade and a grade is one prefix, so every band today has exactly one group"*, and pinned the
    /// premise with `testEveryBandTodayHasExactlyOneGroupBecauseALayerHasOneGrade`. This is what
    /// replaces it.
    func testABandShowingTwoMoveChannelsHasTwoGroups() throws {
        let (manager, layerID, celID) = celFixture()
        let group = AnimationGroup(displayName: "Arm",
                                   tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.animationGroups.append(group)
        animateCel(manager, layerID: layerID, celID: celID)
        animateCel(manager, layerID: layerID, celID: celID, channel: .group(group.id), dx: -9)

        let groups = try XCTUnwrap(manager.graphChannelGroups)
        XCTAssertEqual(groups.count, 2, "One section per Move channel")
        XCTAssertEqual(Set(groups.map(\.name)), ["Move", "Arm"],
                       "…named by the artist's own group name where there is one")
        XCTAssertEqual(groups.map { $0.rows.count }, [6, 6])
        for section in groups {
            XCTAssertFalse(section.id.contains("."), "\(section.id) would split in the wrong place")
        }
    }

    /// **Folding a group changes what the list lays out and nothing the band draws** — the owner's
    /// analogy, *"like the hide/show layers and layer groups"*: the chevron is the folder's
    /// disclosure and the box is its eye.
    ///
    /// The second half is the assertion that would catch a later session routing the fold through
    /// the filter, which is the obvious simplification and is wrong.
    func testFoldingAGroupDrawsTheSameBand() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        let before = try content(manager)
        let id = try XCTUnwrap(manager.graphChannelGroups?.first?.id)

        manager.setGraphGroupCollapsed(id, collapsed: true)
        XCTAssertEqual(manager.graphChannelGroups?.first?.isCollapsed, true)
        XCTAssertEqual(manager.graphChannelGroups?.first?.rows.count, 6,
                       "The membership is still the whole group, so its box still describes it")
        XCTAssertEqual(try content(manager), before, "…and the band has not moved")

        manager.setGraphGroupCollapsed(id, collapsed: false)
        XCTAssertEqual(manager.graphChannelGroups?.first?.isCollapsed, false)
    }

    /// **The fold lives exactly as long as the band it was made on**, which is `Filter`'s rule and is
    /// the answer to the objection §11.5 raised against having a fold at all — that collapse state
    /// keyed by effect case *"would follow the artist to a layer they never folded it on"*.
    func testTheFoldIsScopedToItsOwnBandAndDropsWhenTheEditorCloses() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        let id = try XCTUnwrap(manager.graphChannelGroups?.first?.id)
        manager.setGraphGroupCollapsed(id, collapsed: true)
        XCTAssertNotEqual(manager.graphChannelFold, .none, "Fixture: something is folded")

        let other = KeyframeTarget.layer(id: manager.layers[0].id)
        XCTAssertEqual(manager.graphChannelFold.collapsed(on: other), [],
                       "Another band starts fully expanded")

        manager.isGraphEditorOpen = false
        XCTAssertEqual(manager.graphChannelFold, .none, "…and closing the editor drops it")
    }

    /// **A row's body names the Move it is about, and a grade's row names nothing** — §11.7's second
    /// ruling expressed as the value the view reads.
    ///
    /// All six rows of one channel name the same Move, which is the ruling rather than a shortcut:
    /// the owner asked for *"the move box for that move item"*, and the move item is the channel.
    func testEveryRowOfAMoveChannelNavigatesToThatChannelAndAGradesRowNavigatesNowhere() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        let rows = try XCTUnwrap(manager.graphChannelGroups?.first?.rows)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(Set(rows.map(\.navigation)), [PoseChannelID.cel(.cel)])
        XCTAssertEqual(manager.graphChannelGroups?.first?.navigation, PoseChannelID.cel(.cel))

        let graded = CanvasFixture.manager(layerCount: 1)
        graded.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1,
                                                                                   contrast: 1)))
        graded.currentLayerIndex = 1
        graded.isGraphEditorOpen = true
        graded.setEffectParameterTrack(layerIndex: 1, parameterID: "brightnessContrast.brightness",
                                       to: AnimationCurve(keys: [.init(frame: 0, value: 1),
                                                                 .init(frame: 8, value: 2)]))
        let gradeRows = try XCTUnwrap(graded.graphChannelGroups?.first?.rows)
        XCTAssertFalse(gradeRows.isEmpty, "Fixture: there is a grade row to ask about")
        XCTAssertEqual(Set(gradeRows.map(\.navigation)), [nil],
                       "A Brightness curve has no subject to raise")
    }

    /// **A container pose's rows navigate to the transformation layer's own Move box.**
    ///
    /// This test read the other way — *"offer no navigation, because there is no Move on a
    /// transformation layer to raise… the day that gesture exists there is a red pointing at the one
    /// line to change"*. It pointed, and this is the change: `beginContainerPoseMove()` is the
    /// gesture and it comes up as a `.containerPose` float rather than a vector one, because a
    /// container has no geometry to lift.
    func testAContainerPosesRowsNavigateToItsOwnMoveBox() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        let canvasBox = CGRect(origin: .zero, size: size)
        manager.layers[1].fill = nil
        manager.layers[1].transform = LayerPose(
            pose: PoseQuad(restingIn: canvasBox),
            track: TransformTrack(keys: [
                .init(frame: 0, pose: PoseQuad(restingIn: canvasBox)),
                .init(frame: 9, pose: PoseQuad(box: canvasBox,
                                               mappedBy: CGAffineTransform(translationX: 40, y: 0)))]))
        manager.currentLayerIndex = 1
        manager.isGraphEditorOpen = true

        let rows = try XCTUnwrap(manager.graphChannelGroups?.first?.rows)
        XCTAssertEqual(rows.count, 6, "Fixture: the rows are there")
        XCTAssertEqual(Set(rows.map(\.navigation)), [.container],
                       "All six decompose one channel, so all six name the same subject")
        XCTAssertTrue(manager.revealPoseChannel(.container))
        XCTAssertEqual(manager.floatingPiece?.kind, .containerPose,
                       "A container's box carries no pixels — it is the canvas frame, and the "
                       + "content beneath moves through the real render path rather than a preview")
        XCTAssertEqual(manager.floatingPiece?.targetLayerID, manager.layers[1].id)
    }

    // MARK: - The click that raises the Move box

    /// **Clicking a whole-cel Move row lifts the whole cel into the Move box** — the owner's *"so you
    /// don't need to select it manually again"*, which is `beginVectorWholeCelMove` reached from a
    /// list row instead of from the toolbar.
    func testClickingTheCelMoveRowRaisesTheMoveBoxOverTheWholeCel() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        XCTAssertNil(manager.vectorFloat, "Fixture: nothing is floating yet")

        XCTAssertTrue(manager.revealPoseChannel(.cel(.cel)))
        let float = try XCTUnwrap(manager.vectorFloat)
        XCTAssertEqual(float.layerID, layerID)
        XCTAssertEqual(float.celID, celID)
        let elements = try XCTUnwrap(manager.layers[1].cels[0].vector?.elements)
        XCTAssertEqual(float.insideIDs, Set(elements.map(\.id)),
                       "`.cel` means whatever is on this cel")
    }

    /// **Clicking a group's Move row lifts only that group's ink**, which is the half the whole-cel
    /// lift could not have shown: `liftWholeCel` returns every id, so a shared tail that took
    /// `lift.elements` rather than `lift.insideIDs` would pass the test above and put the artist's
    /// whole drawing in the float here.
    func testClickingAGroupsMoveRowRaisesTheBoxOverThatGroupAlone() throws {
        let (manager, layerID, celID) = celFixture()
        let vector = try XCTUnwrap(manager.layers[1].cels[0].vector)
        vector.addStroke(stroke([CGPoint(x: 40, y: 30), CGPoint(x: 60, y: 30)]))
        XCTAssertEqual(vector.elements.count, 2, "Fixture: there is something to leave behind")

        let group = AnimationGroup(displayName: "Arm",
                                   tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.animationGroups.append(group)
        let taggedID = vector.elements[1].id
        vector.elements = vector.elements.map {
            $0.id == taggedID ? $0.taggedForAnimation(group.id) : $0
        }
        animateCel(manager, layerID: layerID, celID: celID, channel: .group(group.id), dx: -9)

        XCTAssertTrue(manager.revealPoseChannel(.cel(.group(group.id))))
        let float = try XCTUnwrap(manager.vectorFloat)
        XCTAssertEqual(float.insideIDs, [taggedID], "Only the tagged element travels")
        XCTAssertEqual(float.liftedInside.count, 1)
    }

    /// A channel whose ink is not on the cel under the playhead raises nothing and says so, rather
    /// than putting up an empty box.
    func testAChannelWithNoInkHereRaisesNothing() {
        let (manager, _, _) = celFixture()
        XCTAssertFalse(manager.revealPoseChannel(.cel(.group(UUID()))))
        XCTAssertNil(manager.vectorFloat)
    }

    // MARK: - What a pose node takes, and what it still refuses

    /// **A pose node is dragged, marquee'd, focused and shaped, and it still raises no menu and takes
    /// no new key beside it** — the owner's report of 2026-09-03, *"why cant i access the bezier
    /// handles in move?"*.
    ///
    /// The two halves this used to state were "dragged and marquee'd" against "takes no tap", and the
    /// second half was too wide. Focusing is what puts the handles on the band and does nothing else;
    /// what a pose channel has no writer for is **Delete**, which funnels through
    /// `removeEffectParameterKey`, and **tap-to-add**, which would have to invent the five component
    /// values the artist never gave. Those two are still refused and are asserted here as such.
    ///
    /// **The second tap answers `.focus` again rather than `.nothing`**, and that is the assertion
    /// most worth having: `.nothing` is the empty-band case and its caller drops the selection *and*
    /// the focus, so refusing the menu that way would make the handles vanish on the second tap —
    /// the opposite of what the report asks for, and indistinguishable from it in a test that only
    /// checked "not `.menu`".
    ///
    /// **The fixture holds a grade channel too**, which is what stops the refusal halves being tests
    /// of an empty list: the same `tap` at the same kind of point raises a menu one channel over.
    func testAPoseNodeIsFocusedAndShapedButStillTakesNoMenuOrNewKey() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        let pose = try XCTUnwrap(channel(try content(manager), celX))
        XCTAssertEqual(pose.gestures, .dragAndHandles)

        let grade = TimelineGraphBand.Channel(
            parameterID: "brightnessContrast.brightness", name: "Brightness",
            curve: AnimationCurve(keys: [.init(frame: 4, value: 0), .init(frame: 12, value: 1)]),
            uiRange: 0...1, modelDomain: 0...1, format: "%.2f", descriptorIndex: 0,
            isAnimated: true)
        XCTAssertEqual(grade.gestures, .all, "Fixture: a grade's channel takes every gesture")

        let height = TimelineGraphBand.height
        let ppf: CGFloat = 30
        func at(_ channel: TimelineGraphBand.Channel, frame: Int) -> CGPoint {
            let key = channel.curve.keys.first { $0.frame == frame }!
            return CGPoint(x: TimelineGraphBand.x(ofFrame: frame, pixelsPerFrame: ppf),
                           y: TimelineGraphBand.y(ofValue: key.value, in: channel.axis,
                                                  bandHeight: height))
        }
        let both = [pose, grade]
        let poseNode = TimelineGraphBand.KeyRef(parameterID: celX, frame: 4)
        let posePoint = at(pose, frame: 4)
        XCTAssertEqual(TimelineGraphBand.grab(at: posePoint, focused: nil, channels: [pose],
                                              pixelsPerFrame: ppf, bandHeight: height),
                       .key(poseNode),
                       "A touch on a pose node takes hold of it")
        XCTAssertEqual(TimelineGraphBand.keys(in: CGRect(x: 0, y: 0, width: 1000, height: height),
                                              channels: [pose], pixelsPerFrame: ppf,
                                              bandHeight: height),
                       [.init(parameterID: celX, frame: 4), .init(parameterID: celX, frame: 12)],
                       "…and a marquee over the band picks up both of its nodes")
        XCTAssertEqual(TimelineGraphBand.tap(at: posePoint, channels: [pose], focused: nil,
                                             frameCount: 40, pixelsPerFrame: ppf,
                                             bandHeight: height),
                       .focus(poseNode), "…and a tap focuses it, which is what draws its handles")
        XCTAssertFalse(TimelineGraphBand.handles(of: poseNode, in: [pose], pixelsPerFrame: ppf,
                                                 bandHeight: height).isEmpty,
                       "…and the handles are there to be drawn")
        XCTAssertEqual(TimelineGraphBand.tap(at: posePoint, channels: [pose], focused: poseNode,
                                             frameCount: 40, pixelsPerFrame: ppf,
                                             bandHeight: height),
                       .focus(poseNode),
                       "A second tap re-focuses rather than raising a menu — and emphatically does " +
                       "not answer `.nothing`, which would drop the focus and take the handles away")

        // Halfway between the two nodes and on the drawn line, which on a grade is `.add`.
        let onTheLine = CGPoint(x: TimelineGraphBand.x(ofFrame: 8, pixelsPerFrame: ppf),
                                y: TimelineGraphBand.y(ofValue: pose.curve.evaluate(at: 8),
                                                       in: pose.axis, bandHeight: height))
        XCTAssertEqual(TimelineGraphBand.tap(at: onTheLine, channels: [pose], focused: nil,
                                             frameCount: 40, pixelsPerFrame: ppf,
                                             bandHeight: height),
                       .nothing, "A tap on a pose curve adds no key: five components are missing")
        let onTheGradeLine = CGPoint(x: TimelineGraphBand.x(ofFrame: 8, pixelsPerFrame: ppf),
                                     y: TimelineGraphBand.y(ofValue: grade.curve.evaluate(at: 8),
                                                            in: grade.axis, bandHeight: height))
        XCTAssertEqual(TimelineGraphBand.tap(at: onTheGradeLine, channels: [grade], focused: nil,
                                             frameCount: 40, pixelsPerFrame: ppf,
                                             bandHeight: height),
                       .add(parameterID: grade.parameterID, frame: 8,
                            value: grade.curve.evaluate(at: 8)),
                       "Fixture: the same geometry on a grade does add one, so the refusal above " +
                       "is about the channel and not about where the point landed")

        let gradePoint = at(grade, frame: 4)
        let gradeNode = TimelineGraphBand.KeyRef(parameterID: grade.parameterID, frame: 4)
        XCTAssertEqual(TimelineGraphBand.tap(at: gradePoint, channels: both, focused: nil,
                                             frameCount: 40, pixelsPerFrame: ppf,
                                             bandHeight: height),
                       .focus(gradeNode),
                       "…while a tap on the grade beside it focuses as it always did")
        XCTAssertEqual(TimelineGraphBand.tap(at: gradePoint, channels: both, focused: gradeNode,
                                             frameCount: 40, pixelsPerFrame: ppf,
                                             bandHeight: height),
                       .menu(gradeNode),
                       "…and its second tap still raises the menu the pose channel is refused")
        XCTAssertEqual(TimelineGraphBand.keys(in: CGRect(x: 0, y: 0, width: 1000, height: height),
                                              channels: both, pixelsPerFrame: ppf,
                                              bandHeight: height),
                       [.init(parameterID: celX, frame: 4), .init(parameterID: celX, frame: 12),
                        .init(parameterID: grade.parameterID, frame: 4),
                        .init(parameterID: grade.parameterID, frame: 12)],
                       "…and a marquee over both catches all four nodes")
    }

    // MARK: - The y axis a node is drawn against

    /// Runs one node drag through the funnels the band's own recogniser uses, and hands back the
    /// content the band would draw afterwards.
    @discardableResult
    private func dragNode(_ manager: CanvasManager, _ ref: TimelineGraphBand.KeyRef,
                          by translation: CGSize,
                          pixelsPerFrame: CGFloat = 30) throws -> TimelineGraphBand.Content {
        let content = try content(manager)
        let snapshot = manager.graphBandPoseSnapshot(layerIndex: content.layerIndex)
        let moves = TimelineGraphBand.moves(of: [ref], in: content.channels, translation: translation,
                                            pixelsPerFrame: pixelsPerFrame,
                                            bandHeight: TimelineGraphBand.height)
        XCTAssertTrue(manager.writeGraphBandPoseEdits(
            TimelineGraphBand.poseEdits(moves, in: content.channels),
            from: snapshot, layerIndex: content.layerIndex),
                      "Fixture: the drag has to reach the document")
        return try self.content(manager)
    }

    /// **A dragged node's *dot* moves, and by exactly what the finger travelled** — the owner's report
    /// of 2026-09-03: *"if i try to move the nodes, the nodes dont move? its value changes but the
    /// nodes just stay still in the graph."*
    ///
    /// **The assertion has to be a drawn y and not a value, because the value was always right.**
    /// `moves(of:in:…)` reads the axis captured at touch-down and writes the number the finger asked
    /// for; what was broken was the picture. A test that checked `key.value` passes against the build
    /// the owner is complaining about.
    ///
    /// **Two keys, which is the report's own case and the worst one.** The axis used to be
    /// `keyValues.min()...keyValues.max()`, so on a two-key channel both keys *are* the extremes and
    /// each is pinned to a rim for every value it could ever hold. `PoseNodeDragLogicTests`' own
    /// fixture doc records the same fact from the other side — it authors *three* keys precisely
    /// because "with exactly two keys every channel's axis is exactly its two values, so every node is
    /// at the very top or the very bottom of the band".
    ///
    /// The second half is the one an implementation gets wrong without noticing: **the node that was
    /// not dragged must not move either**. An axis that rescaled to keep both keys in view would slide
    /// it under a finger that is nowhere near it, which is §11.6's stated reason for preferring a
    /// declared range at all.
    func testDraggingAPoseNodeMovesItsDotByWhatTheFingerTravelled() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        let height = TimelineGraphBand.height
        let before = try XCTUnwrap(channel(try content(manager), celX))
        XCTAssertEqual(before.curve.keys.map(\.frame), [4, 12], "Fixture: the report's own two keys")

        func y(_ channel: TimelineGraphBand.Channel, _ frame: Int) throws -> CGFloat {
            TimelineGraphBand.y(ofValue: try XCTUnwrap(channel.curve.key(atFrame: frame)).value,
                                in: channel.axis, bandHeight: height)
        }
        let dragged0 = try y(before, 4)
        let bystander0 = try y(before, 12)

        let content = try dragNode(manager, .init(parameterID: celX, frame: 4),
                                   by: CGSize(width: 0, height: -20))
        let after = try XCTUnwrap(channel(content, celX))
        XCTAssertNotEqual(try XCTUnwrap(after.curve.key(atFrame: 4)).value,
                          try XCTUnwrap(before.curve.key(atFrame: 4)).value,
                          "Fixture: the value moved, which it did before this pass too")
        XCTAssertEqual(try y(after, 4), dragged0 - 20, accuracy: 0.001,
                       "The dot rises by the twenty points the finger did")
        XCTAssertEqual(try y(after, 12), bystander0, accuracy: 0.001,
                       "…and the node nobody touched stays exactly where it was")
    }

    /// **How far one point of finger moves a component does not depend on how close its keys are** —
    /// the second defect hiding behind the same report, and the one that made a nearly-flat channel
    /// undraggable in the value as well as in the picture.
    ///
    /// A fitted axis spans the keys, so the gain is the *spread* per band height: two X keys two
    /// points apart meant a full-band drag moved X by two points, and a channel that is keyed but not
    /// animated — which the band draws dashed and still lets you drag — got the half-unit widening on
    /// `range`'s flat branch, so a full-band drag moved it by **one**. Three documents that differ in
    /// nothing but that spread must now answer the same number.
    ///
    /// 20 points of an 80-point usable band is a quarter of X's own 100-point window, so the number
    /// is 25 — stated outright rather than as "they agree", because three implementations that are
    /// equally wrong also agree.
    func testDragGainIsTheComponentsOwnSpanAndNotTheKeysSpread() throws {
        var moved: [CGFloat: Double] = [:]
        for spread in [CGFloat(0), 2, 24] {
            let (manager, layerID, celID) = celFixture()
            animateCel(manager, layerID: layerID, celID: celID, dx: spread)
            let ref = TimelineGraphBand.KeyRef(parameterID: celX, frame: 4)
            let before = try XCTUnwrap(
                XCTUnwrap(channel(try content(manager), celX)).curve.key(atFrame: 4)).value
            let after = try XCTUnwrap(
                XCTUnwrap(channel(try dragNode(manager, ref, by: CGSize(width: 0, height: -20)),
                                  celX)).curve.key(atFrame: 4)).value
            moved[spread] = after - before
        }
        XCTAssertEqual(moved[0] ?? .nan, 25, accuracy: 1e-9,
                       "A channel with nothing to fit is dragged in the component's own units")
        XCTAssertEqual(moved[2] ?? .nan, 25, accuracy: 1e-9, "…and so is one whose keys nearly touch")
        XCTAssertEqual(moved[24] ?? .nan, 25, accuracy: 1e-9, "…and so is one whose keys are apart")
    }

    /// **The axis arithmetic itself** — centred on rest, constant inside one octave, doubling past it.
    ///
    /// The middle two rows are the whole point: two animations of different sizes share one window, so
    /// a value that changes inside it draws at a different height. Every axis derived from the keys
    /// alone fails that by arithmetic rather than by tuning — min/max, mean-and-deviation, and padded
    /// or minimum-spanned versions of either are all affine-equivariant in the key set, and an
    /// affine-equivariant map sends a two-point set to the same two positions whatever the two points
    /// are. The last row states that about the fallback the grade channels still use.
    func testTheAxisIsCentredOnRestAndGrowsInDoublings() {
        let rest = 12.0
        func axis(_ values: [Double]) -> ClosedRange<Double> {
            TimelineGraphBand.anchoredRange(reference: rest, minimumSpan: 100, keyValues: values)
        }
        XCTAssertEqual(axis([rest, rest]), -38...62, "A flat channel gets the component's own span")
        XCTAssertEqual(axis([rest, rest + 24]), -38...62, "…and so does an animation inside it")
        XCTAssertEqual(axis([rest, rest + 39]), -38...62, "…up to 80% of the half-axis")
        XCTAssertEqual(axis([rest, rest + 41]), -88...112, "…past which it doubles, once")
        XCTAssertEqual(axis([rest, rest + 81]), -188...212, "…and again")
        XCTAssertEqual(axis([rest - 41, rest]), -88...112, "Below rest counts the same as above it")

        let height = TimelineGraphBand.height
        func top(_ outer: Double) -> CGFloat {
            TimelineGraphBand.y(ofValue: outer, in: axis([rest, outer]), bandHeight: height)
        }
        XCTAssertNotEqual(top(rest + 24), top(rest + 36), accuracy: 1,
                          "The outermost key is not pinned: two animations one octave apart in size " +
                          "draw their far node at two different heights")
        XCTAssertEqual(TimelineGraphBand.y(ofValue: rest + 24,
                                           in: TimelineGraphBand.range(uiRange: nil,
                                                                       keyValues: [rest, rest + 24]),
                                           bandHeight: height),
                       TimelineGraphBand.y(ofValue: rest + 36,
                                           in: TimelineGraphBand.range(uiRange: nil,
                                                                       keyValues: [rest, rest + 36]),
                                           bandHeight: height),
                       "…which the fitted fallback the grade channels still use cannot say: it draws " +
                       "both at the same height, and that is the defect stated as arithmetic")
    }

    // MARK: - Bezier handles on a pose node

    /// **A handle on a pose node is grabbed, dragged, written, and drawn back where the finger left
    /// it** — the whole round trip, and the assertion that catches the units.
    ///
    /// **The units are the trap here, and they are invisible in the model.** `TransformTrack.timing`
    /// is an `AnimationCurve` whose key values are the pose **indices** `0, 1, 2, …` carrying this
    /// key's handles, so a stored `deltaValue` is a fraction of a *pose*; the band's six rows are in
    /// canvas points, degrees and multiples. `poseChannels` multiplies by the segment's own rise on
    /// the way out and `poseHandleEdits` divides by it on the way back, and this test does not check
    /// either of them — it checks that they are **inverses**, which is the only thing an artist can
    /// see. Delete the multiply, delete the divide, or change one and not the other, and the dot
    /// lands somewhere other than under the finger.
    ///
    /// It also pins the two funnels apart: the grade's writer answers empty for a pose row, because
    /// `setEffectParameterTrack` would drop such an id silently and read as a handle that did nothing.
    func testAPoseHandleIsGrabbedDraggedAndLandsWhereTheFingerLeftIt() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        let height = TimelineGraphBand.height
        let ppf: CGFloat = 30
        let before = try content(manager)
        let node = TimelineGraphBand.KeyRef(parameterID: celX, frame: 4)
        let ref = TimelineGraphBand.HandleRef(key: node, side: .outgoing)

        let drawn = TimelineGraphBand.handles(of: node, in: before.channels,
                                              pixelsPerFrame: ppf, bandHeight: height)
        XCTAssertEqual(drawn.map(\.side), [.outgoing],
                       "The first key of a two-key curve bounds one segment, so it offers one handle")
        let dot = try XCTUnwrap(drawn.first)
        XCTAssertEqual(TimelineGraphBand.grab(at: dot.point, focused: node, channels: before.channels,
                                              pixelsPerFrame: ppf, bandHeight: height),
                       .handle(ref), "A touch on the dot takes the handle rather than its node")

        let travel = CGSize(width: 9, height: -13)
        let edits = TimelineGraphBand.poseHandleEdits(ref, in: before.channels, translation: travel,
                                                      pixelsPerFrame: ppf, bandHeight: height)
        XCTAssertFalse(edits.isEmpty, "A pose handle writes through the pose funnel")
        XCTAssertTrue(TimelineGraphBand.draggingHandle(ref, in: before.channels, translation: travel,
                                                       pixelsPerFrame: ppf, bandHeight: height).isEmpty,
                      "…and not through the grade's, which would drop the id without saying so")
        let snapshot = manager.graphBandPoseSnapshot(layerIndex: before.layerIndex)
        XCTAssertTrue(manager.writeGraphBandPoseEdits(edits, from: snapshot,
                                                      layerIndex: before.layerIndex))

        let moved = try XCTUnwrap(TimelineGraphBand.handles(of: node, in: try content(manager).channels,
                                                            pixelsPerFrame: ppf,
                                                            bandHeight: height).first)
        XCTAssertEqual(moved.point.x, dot.point.x + travel.width, accuracy: 0.001)
        XCTAssertEqual(moved.point.y, dot.point.y + travel.height, accuracy: 0.001)
    }

    /// **One handle pair, drawn on all six rows** — which is why the gesture is offered at all.
    ///
    /// A `TransformTrack.Key` carries one `inHandle`/`outHandle` pair and one tangent mode for its
    /// whole pose, so shaping X's ease shapes Y's and Rotation's with it. That was the argument for
    /// refusing the gesture until 2026-09-03 and it over-corrected: a shared ease is what the model
    /// stores and what `PoseInterpolation.blend` runs, so the thing to repair was the picture. Drawing
    /// the handle on the six rows at once is that repair.
    ///
    /// **A row that does not move across the segment offers no dot**, which is the same rule
    /// `handles(of:in:…)` already applies to a curve's two ends: the conversion factor is that row's
    /// own rise, so on a flat row the dot would sit inside its node and a drag on it could not be read
    /// back. Five of these six are flat, which makes the fixture's one animated row the whole contrast.
    func testAPoseKeysHandlesAreOneEaseSharedByAllSixRows() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        let height = TimelineGraphBand.height
        let ppf: CGFloat = 30
        let before = try content(manager)
        let node = TimelineGraphBand.KeyRef(parameterID: celX, frame: 4)

        XCTAssertEqual(TimelineGraphBand.handleRows(of: node, in: before.channels),
                       PoseComponents.Component.allCases.map {
                           TimelineGraphBand.KeyRef(parameterID: PoseChannelID.cel(.cel).parameterID($0),
                                                    frame: 4)
                       },
                       "One node's handles belong to all six of its rows")

        let travel = CGSize(width: 9, height: -13)
        let snapshot = manager.graphBandPoseSnapshot(layerIndex: before.layerIndex)
        XCTAssertTrue(manager.writeGraphBandPoseEdits(
            TimelineGraphBand.poseHandleEdits(.init(key: node, side: .outgoing),
                                              in: before.channels, translation: travel,
                                              pixelsPerFrame: ppf, bandHeight: height),
            from: snapshot, layerIndex: before.layerIndex))

        let after = try content(manager)
        let stored = try XCTUnwrap(manager.layers.first { $0.id == layerID }?
            .cels.first { $0.id == celID }?
            .transformTracks[TransformChannelID.cel.id]?.keys.first { $0.frame == 0 })
        XCTAssertEqual(stored.tangentMode, .free, "The drag authored the key's own ease")
        XCTAssertNotEqual(stored.outHandle.deltaFrames, 0)

        for component in PoseComponents.Component.allCases {
            let id = PoseChannelID.cel(.cel).parameterID(component)
            let row = try XCTUnwrap(channel(after, id))
            let key = try XCTUnwrap(row.curve.key(atFrame: 4))
            XCTAssertEqual(key.tangentMode, .free, "\(component.name) carries the same mode")
            XCTAssertEqual(key.outHandle.deltaFrames, stored.outHandle.deltaFrames, accuracy: 1e-9,
                           "\(component.name) carries the same timing, unscaled")
            let rise = try XCTUnwrap(row.curve.key(atFrame: 12)).value - key.value
            XCTAssertEqual(key.outHandle.deltaValue, stored.outHandle.deltaValue * rise,
                           accuracy: 1e-9,
                           "\(component.name)'s drawn rise is the stored ease through its own segment")
            let dots = TimelineGraphBand.handles(of: .init(parameterID: id, frame: 4), in: after.channels,
                                                 pixelsPerFrame: ppf, bandHeight: height)
            XCTAssertEqual(dots.isEmpty, rise == 0,
                           "\(component.name) offers a dot exactly where its own segment moves")
        }
    }

    // MARK: - The projective refusal

    /// **A projective pose declines its whole channel and the band names it** — §11.7's ruling, and
    /// the one state in this file no writer in the app can reach: animated Distort is stage 5b.
    ///
    /// The channel is declined **whole** rather than per key: six curves five of whose keys were
    /// honest and one of which was a linearisation would be worse than none, because nothing would
    /// mark the sixth.
    func testAProjectivePoseDeclinesItsChannelAndTheBandSaysSo() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        XCTAssertFalse(try content(manager).channels.isEmpty, "Fixture: it drew before")

        let keystone = PoseQuad(box: box,
                                corners: Quad(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
                                              CGPoint(x: 80, y: 100), CGPoint(x: 20, y: 100)))
        manager.setTransformPoseKey(layerID: layerID, celID: celID, channel: .cel,
                                    atCelLocalFrame: 4, pose: keystone)

        let content = try content(manager)
        XCTAssertEqual(content.channels.map(\.parameterID), [],
                       "One projective key takes the whole channel out")
        XCTAssertEqual(content.declinedChannelIDs, [PoseChannelID.cel(.cel).groupID],
                       "…and it is named rather than merely absent")
        XCTAssertEqual(TimelineGraphBand.encode(content), "declined:celPose",
                       "which is what the tier that cannot read a `Content` sees")
        XCTAssertNotEqual(TimelineGraphBand.encode(content), "empty",
                          "a band that refused is not a band that had nothing")
    }
}
