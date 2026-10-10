import XCTest
import CoreGraphics

/// **The transform channel's band and its rows** — KEYFRAMES.md §11.7, and TODO (139): each row is a
/// component's own stored curve, so it is drawn, dragged, shaped, deleted and added to exactly as a
/// grade's row is, through one whole-curve funnel (`CanvasManager.setPoseChannelTrack`).
///
/// `PoseComponentsLogicTests` beside this one pins the arithmetic. This one pins everything that is
/// about the *document*: which rows a band lists, at which frames, what the channel list makes of
/// them, that a node on the band and an indicator on the track are the same thing (§2.28), and that
/// an edit to one row leaves every other row alone.
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
        manager.currentLayerIndex = 1
        manager.currentFrame = start
        manager.isGraphEditorOpen = true
        return (manager, manager.layers[1].id, cel.id)
    }

    private func target(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[manager.currentLayerIndex].id)
    }

    /// A pure slide on the whole-cel channel, cel-local frames 0 and 8 — which keys X alone.
    private func animateCel(_ manager: CanvasManager, layerID: UUID, celID: UUID,
                            channel: TransformChannelID = .cel, dx: CGFloat = 24) {
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID, channel: channel,
                                   CanvasFixture.poseTrack(box: box, [(0, PoseQuad(restingIn: box)),
                                                                      (8, slide(dx))]))
    }

    /// **A slide whose other five affine components are keyed too, flat** — the state TODO (59)'s
    /// default exists for: a row keyed but not animated, which the band draws dashed.
    private func animateCelWithFlatRows(_ manager: CanvasManager, layerID: UUID, celID: UUID) {
        let rest = PoseComponents.Values.resting(in: box)
        var curves: [PoseComponents.Component: AnimationCurve] = [
            .x: AnimationCurve(keys: [.init(frame: 0, value: rest.x), .init(frame: 8, value: rest.x + 24)])
        ]
        for component in [PoseComponents.Component.y, .scaleX, .scaleY, .rotation, .skew] {
            curves[component] = AnimationCurve(keys: [.init(frame: 0, value: rest[component]),
                                                      .init(frame: 8, value: rest[component])])
        }
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                   TransformTrack(box: box, curves: curves))
    }

    /// A transformation layer whose own pose slides 40 points between frames `from` and `to`.
    private func slidingTransformLayer(from: Int = 0, to: Int = 9, box canvasBox: CGRect? = nil,
                                       dx: CGFloat = 40) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addTransformLayer()
        let canvasBox = canvasBox ?? CGRect(origin: .zero, size: size)
        manager.layers[1].transform = LayerPose(
            pose: PoseQuad(restingIn: canvasBox),
            track: CanvasFixture.poseTrack(box: canvasBox, [
                (from, PoseQuad(restingIn: canvasBox)),
                (to, PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: dx, y: 0)))]))
        manager.currentLayerIndex = 1
        manager.isGraphEditorOpen = true
        return manager
    }

    private func content(_ manager: CanvasManager) throws -> TimelineGraphBand.Content {
        try XCTUnwrap(manager.graphBandContent)
    }

    /// **Every channel the band *lists*, before TODO (59)'s default filter subtracts from it.**
    ///
    /// `graphBandContent` is the *drawn* half and has been the filtered one since (59): a transform
    /// channel's flat Scale X, Scale Y and Skew start switched off
    /// (`TimelineGraphChannelList.defaultHidden(in:)`). A test asking which rows a pose keys is
    /// asking about the listing, so it reads this.
    private func listed(_ manager: CanvasManager) throws -> [TimelineGraphBand.Channel] {
        let expansion = try XCTUnwrap(manager.graphBandExpansion, "the band is not open")
        return manager.graphBandListing(of: expansion.target)
    }

    private func channel(_ channels: [TimelineGraphBand.Channel],
                         _ id: String) -> TimelineGraphBand.Channel? {
        channels.first { $0.parameterID == id }
    }

    private func channel(_ content: TimelineGraphBand.Content,
                         _ id: String) -> TimelineGraphBand.Channel? {
        content.channels.first { $0.parameterID == id }
    }

    private var celX: String { PoseChannelID.cel(.cel).parameterID(.x) }
    private var celScaleX: String { PoseChannelID.cel(.cel).parameterID(.scaleX) }
    private var containerX: String { PoseChannelID.container.parameterID(.x) }

    // MARK: - The band lists a pose channel, at the timeline's own frames

    /// **A cel pose channel draws one row per keyed component, at *absolute* frames.**
    ///
    /// The cel starts at frame 4 and its keys are at cel-local 0 and 8, so the band draws them at 4
    /// and 12. Deleting `+ source.frameOffset` in `poseChannels` leaves them at 0 and 8, and the
    /// nodes then sit four frames left of the indicators on the track — the exact divergence §2.28
    /// exists to forbid.
    func testACelPoseChannelDrawsItsKeyedComponentsAtAbsoluteFrames() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)

        let listed = try listed(manager)
        XCTAssertEqual(listed.map(\.parameterID), [celX],
                       "TODO (139): a slide keys X, so X is the one row — no flat Scale, Rotation or Skew")
        XCTAssertEqual(listed.map(\.name), ["X"])

        let x = try XCTUnwrap(channel(listed, celX))
        XCTAssertEqual(x.curve.keys.map(\.frame), [4, 12],
                       "The cel starts at 4, so its cel-local 0 and 8 are absolute 4 and 12")
        XCTAssertNotEqual(x.curve.keys.map(\.frame), [0, 8],
                          "…and are emphatically not the numbers stored on the track")
    }

    /// **The row is the stored curve, and its values are where the box's centre is.** Checked against
    /// the geometry rather than the decomposition: the centre starts at `box.midX` and ends 24 points
    /// right of it. An implementation that reported an offset from rest, or the box's origin, or a Y
    /// for an X, fails here.
    func testASlidesRowIsWhereTheBoxCentreIs() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID, dx: 24)

        let x = try XCTUnwrap(channel(try listed(manager), celX))
        XCTAssertEqual(x.curve.keys.map(\.value), [Double(box.midX), Double(box.midX) + 24],
                       "X is where the box's centre is, in canvas points")
        XCTAssertTrue(x.isAnimated)
        XCTAssertEqual(x.curve, manager.layers[1].cels[0].transformTracks[TransformChannelID.cel.id]?
                        .curve(.x)?.shifted(by: 4),
                       "…and is the stored curve itself, moved onto the timeline's frames")
    }

    /// **A container pose is listed too, at its own time base** — §3.1's second kind, which needs no
    /// conversion because a transformation layer has no cel to ride.
    func testAContainerPoseIsListedInAbsoluteFramesWithNoOffset() throws {
        let manager = slidingTransformLayer()
        let canvasBox = CGRect(origin: .zero, size: size)
        let content = try content(manager)
        let x = try XCTUnwrap(channel(content, containerX))
        XCTAssertEqual(x.curve.keys.map(\.frame), [0, 9], "Document frames, exactly as stored")
        XCTAssertEqual(x.curve.keys.map(\.value),
                       [Double(canvasBox.midX), Double(canvasBox.midX) + 40])
    }

    /// **A layer that is not a transform layer contributes no pose channel**, which is
    /// `storedEffect(of:)`'s asymmetry one payload over: a pose left behind by a kind change poses
    /// nothing, so a curve for it would picture an animation the canvas is not running.
    func testAPoseLeftOnALayerThatIsNotATransformLayerIsNotListed() throws {
        let manager = slidingTransformLayer()
        XCTAssertNotNil(manager.layers[1].layerTransform, "Fixture: it is a transform layer")
        XCTAssertFalse(try content(manager).channels.isEmpty)

        manager.layers[1].kind = .raster
        XCTAssertNil(manager.layers[1].layerTransform, "…and the kind flip takes it out of it")
        XCTAssertEqual(try content(manager).channels.map(\.parameterID), [],
                       "so the band draws nothing for a pose the renderer ignores")
    }

    /// **A Distort draws Perspective X and Perspective Y rows** — TODO (139)'s ruling, which replaced
    /// §11.7's "declined" state: the band's refusal is gone, because a keystone is two more curves.
    func testADistortDrawsPerspectiveRowsBesideTheRest() throws {
        let (manager, layerID, celID) = celFixture()
        let keystone = PoseQuad(box: box, corners: Quad(CGPoint(x: 4, y: 6), CGPoint(x: 20, y: 6),
                                                        CGPoint(x: 18, y: 14), CGPoint(x: 6, y: 14)))
        XCTAssertEqual(keystone.map?.isProjective, true, "Fixture: a genuine keystone")
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                   CanvasFixture.poseTrack(box: box, [(0, PoseQuad(restingIn: box)),
                                                                      (8, keystone)]))
        let ids = try listed(manager).map(\.parameterID)
        XCTAssertTrue(ids.contains(PoseChannelID.cel(.cel).parameterID(.perspectiveY)),
                      "the narrowing bottom is drawn as a Perspective Y curve")
        XCTAssertEqual(try listed(manager).first { $0.parameterID == PoseChannelID.cel(.cel).parameterID(.perspectiveY) }?.name,
                       "Perspective Y")
        XCTAssertFalse(TimelineGraphBand.encode(try content(manager)).contains("declined"))
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
        let manager = slidingTransformLayer(from: 2, to: 11)

        let target = KeyframeTarget.layer(id: manager.layers[1].id)
        XCTAssertEqual(manager.keyframeFrames(of: target), [2, 11])
        let nodes = Set(try content(manager).channels.flatMap { $0.curve.keys.map(\.frame) })
        XCTAssertEqual(nodes, [2, 11], "…which is exactly where the band puts its nodes")
    }

    /// **The band and `listedAnimationChannelIDs` are the same list, in both directions** — the pin
    /// the effect channels already carry, extended to the pose ones.
    ///
    /// **The fixture holds something the predicate must reject**, which is what makes it a pin rather
    /// than an identity: five flat rows beside the animated X, so an implementation that listed every
    /// keyed component as animated returns six where this wants one.
    func testTheBandAndTheModelAgreeAboutWhichPoseChannelsAreAnimations() throws {
        let (manager, layerID, celID) = celFixture()
        animateCelWithFlatRows(manager, layerID: layerID, celID: celID)

        let drawn = try listed(manager).filter(\.isAnimated).map(\.parameterID)
        XCTAssertEqual(drawn, [celX], "Fixture: five of the six are refused")
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: target(manager)), drawn,
                       "The model's own answer, in the band's own order")
        XCTAssertFalse(manager.listedAnimationChannelIDs(of: target(manager)).contains(celScaleX),
                       "…and a flat component is not an animation")
    }

    // MARK: - What a transform channel starts with switched off — TODO (59)

    /// Poses the cel's own channel so that a *scale* varies across its two keys, which is what makes
    /// `celPose.scaleX` an animation rather than a flat row.
    private func scaleCel(_ manager: CanvasManager, layerID: UUID, celID: UUID) {
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                   CanvasFixture.poseTrack(box: box, [
                                       (0, PoseQuad(restingIn: box)),
                                       (8, PoseQuad(box: box, mappedBy: CGAffineTransform(scaleX: 2, y: 1)))]))
    }

    private func drawnIDs(_ manager: CanvasManager) throws -> [String] {
        try content(manager).channels.map(\.parameterID)
    }

    /// **The owner's ask, whole** — 2026-09-10: *"transformations should hide scale x, scale y, and
    /// skew by default."*
    ///
    /// Since TODO (139) a slide keys none of those rows, so the default only has work to do where
    /// they are keyed and flat. The two operands are the band's **listing** and its **drawn
    /// content**: six rows are listed and three are drawn, and the three missing ones are exactly the
    /// three the ask names.
    func testATransformChannelStartsWithItsFlatScaleAndSkewRowsHidden() throws {
        let (manager, layerID, celID) = celFixture()
        animateCelWithFlatRows(manager, layerID: layerID, celID: celID)

        XCTAssertEqual(try listed(manager).map(\.parameterID),
                       [PoseComponents.Component.x, .y, .scaleX, .scaleY, .rotation, .skew]
                        .map { PoseChannelID.cel(.cel).parameterID($0) },
                       "PREMISE: all six are still listed — the default is a filter, not a deletion")
        XCTAssertEqual(try drawnIDs(manager),
                       [PoseChannelID.cel(.cel).parameterID(.x),
                        PoseChannelID.cel(.cel).parameterID(.y),
                        PoseChannelID.cel(.cel).parameterID(.rotation)],
                       "Scale X, Scale Y and Skew are off the band before the artist touches anything")
        XCTAssertTrue(manager.graphBandHasHiddenChannels,
                      "…and the channel-list button is tinted, so the filter has a visible sign")
    }

    /// **A hidden row is still findable, and switching it on sticks.**
    func testSwitchingADefaultHiddenRowBackOnDrawsThatOneAndLeavesTheOthersOff() throws {
        let (manager, layerID, celID) = celFixture()
        animateCelWithFlatRows(manager, layerID: layerID, celID: celID)

        let rows = try XCTUnwrap(manager.graphChannelGroups?.first?.rows)
        XCTAssertEqual(rows.count, 6, "Every channel is in the list, hidden or not")
        XCTAssertEqual(rows.filter { !$0.isVisible }.map(\.parameterID),
                       [celScaleX,
                        PoseChannelID.cel(.cel).parameterID(.scaleY),
                        PoseChannelID.cel(.cel).parameterID(.skew)],
                       "…and the three unticked boxes are the three the default hid")

        manager.setGraphChannels([celScaleX], visible: true)
        XCTAssertTrue(try drawnIDs(manager).contains(celScaleX),
                      "One tap puts Scale X back on the band")
        XCTAssertFalse(try drawnIDs(manager).contains(PoseChannelID.cel(.cel).parameterID(.scaleY)),
                       "…and Scale Y stays off, so the first toggle kept the rest of the default")

        manager.setGraphChannels([celScaleX], visible: false)
        XCTAssertFalse(try drawnIDs(manager).contains(celScaleX), "…and it can go off again")

        manager.setGraphChannels(rows.map(\.parameterID), visible: true)
        XCTAssertEqual(manager.graphChannelFilter.hidden, [], "Nothing is switched off any more")
        XCTAssertEqual(try drawnIDs(manager).count, 6,
                       "…and all six are drawn, so an emptied filter does not read as untouched")
    }

    /// **An animated scale is never hidden**, which is the qualifier that keeps the default from
    /// taking an artist's own animation off the surface they made it on.
    func testAnAnimatedScaleIsDrawnWhereAFlatOneIsHidden() throws {
        let flat = celFixture()
        animateCelWithFlatRows(flat.manager, layerID: flat.layerID, celID: flat.celID)
        XCTAssertFalse(try drawnIDs(flat.manager).contains(celScaleX),
                       "A flat Scale X is hidden by the default")

        let scaled = celFixture()
        scaleCel(scaled.manager, layerID: scaled.layerID, celID: scaled.celID)
        XCTAssertTrue(try drawnIDs(scaled.manager).contains(celScaleX),
                      "An animated Scale X is an animation the artist made, and it is drawn")
        XCTAssertTrue(try XCTUnwrap(channel(try listed(scaled.manager), celScaleX)).isAnimated,
                      "PREMISE: the fixture really did animate it")
    }

    /// **"Includes transformation layers and normal move"** — the same default on §3.1's other time
    /// base. The operand worth stating is the `containerPose` id: a rule written against `"celPose"`
    /// would pass every test above and fail exactly here.
    func testTheDefaultReachesATransformationLayersOwnPose() throws {
        let manager = slidingTransformLayer()
        var track = try XCTUnwrap(manager.layers[1].transform?.track)
        track.setCurve(AnimationCurve(keys: [.init(frame: 0, value: 1), .init(frame: 9, value: 1)]), for: .scaleX)
        manager.layers[1].transform?.track = track

        XCTAssertEqual(try listed(manager).map(\.parameterID),
                       [PoseChannelID.container.parameterID(.x), PoseChannelID.container.parameterID(.scaleX)],
                       "PREMISE: a transformation layer lists its keyed rows")
        XCTAssertEqual(try drawnIDs(manager), [PoseChannelID.container.parameterID(.x)],
                       "and starts with its flat Scale X switched off")
    }

    /// **A full-size slide keys X and nothing else** — the measured case behind `flatTolerance`.
    ///
    /// The numbers are the ones `-uiTestSeedKeyframedMove` builds and the owner works at
    /// (PERFORMANCE.md §1): a 2048-wide box slid `2048 * 0.4` points. `(2048 + 819.2) - 819.2` is not
    /// 2048 in binary floating point, so the decomposition reads the slid pose's Scale X a few bits
    /// short of 1 — and an exact change test would key Scale X beside X. The commit goes through the
    /// shipped writer on two primed frames, so what this pins is the change test the writer applies.
    func testAFullSizeSlideKeysXAloneDespiteTheDecompositionsFloatingPointNoise() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addTransformLayer()
        let wide = CGRect(x: 0, y: 0, width: 2048, height: 1024)
        manager.layers[1].transform = LayerPose(pose: PoseQuad(restingIn: wide))
        manager.currentLayerIndex = 1
        manager.isGraphEditorOpen = true
        let target = KeyframeTarget.layer(id: manager.layers[1].id)
        manager.addKeys(target, atFrame: 0)
        manager.addKeys(target, atFrame: 11)

        let slid = PoseQuad(box: wide, mappedBy: CGAffineTransform(translationX: 2048 * 0.4, y: 0))
        let noisy = try XCTUnwrap(PoseComponents.decompose(slid, inBox: wide)).scaleX
        XCTAssertNotEqual(noisy, 1, "PREMISE: the decomposition really is bit-unequal across a pure slide")
        XCTAssertEqual(manager.commitContainerPose(target, restingAt: PoseQuad(restingIn: wide),
                                                   movedTo: slid, atFrame: 11), .seedAndKey)

        XCTAssertEqual(try listed(manager).map(\.parameterID), [PoseChannelID.container.parameterID(.x)],
                       "X is keyed, and Scale X — moved by float noise alone — is not")
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: target), [PoseChannelID.container.parameterID(.x)])
    }

    /// **A grade's channels are untouched by the default**, which is the boundary the rule draws:
    /// the ask is about transformations, and an effect parameter called anything at all keeps being
    /// drawn.
    func testAGradesFlatChannelIsStillDrawn() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1,
                                                                                    contrast: 1)))
        manager.currentLayerIndex = 1
        // Two keys of **equal** value, so the channel is in force and is not an animation — the same
        // state the three default-hidden pose rows are in, on a channel the default must not touch.
        manager.setEffectParameterTrack(layerIndex: 1, parameterID: "brightnessContrast.brightness",
                                        to: AnimationCurve(keys: [.init(frame: 0, value: 1),
                                                                  .init(frame: 6, value: 1)]))
        manager.isGraphEditorOpen = true

        XCTAssertEqual(try drawnIDs(manager), ["brightnessContrast.brightness"],
                       "A flat grade channel is drawn dashed, exactly as §11.4 rules")
        XCTAssertFalse(manager.graphBandHasHiddenChannels, "…and nothing is filtered on this band")
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
        XCTAssertEqual(groups.map { $0.rows.count }, [1, 1], "a slide keys one row in each")
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
        animateCelWithFlatRows(manager, layerID: layerID, celID: celID)
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
    /// Every row of one channel names the same Move, which is the ruling rather than a shortcut:
    /// the owner asked for *"the move box for that move item"*, and the move item is the channel.
    func testEveryRowOfAMoveChannelNavigatesToThatChannelAndAGradesRowNavigatesNowhere() throws {
        let (manager, layerID, celID) = celFixture()
        animateCelWithFlatRows(manager, layerID: layerID, celID: celID)
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
        let manager = slidingTransformLayer()

        let rows = try XCTUnwrap(manager.graphChannelGroups?.first?.rows)
        XCTAssertEqual(rows.count, 1, "Fixture: the slide's row is there")
        XCTAssertEqual(Set(rows.map(\.navigation)), [.container],
                       "A row of the channel names the channel's own subject")
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
        XCTAssertEqual(float.parts[0].layerID, layerID)
        XCTAssertEqual(float.parts[0].celID, celID)
        let elements = try XCTUnwrap(manager.layers[1].cels[0].vector?.elements)
        XCTAssertEqual(float.parts[0].insideIDs, Set(elements.map(\.id)),
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
        XCTAssertEqual(float.parts[0].insideIDs, [taggedID], "Only the tagged element travels")
        XCTAssertEqual(float.parts[0].liftedInside.count, 1)
    }

    /// A channel whose ink is not on the cel under the playhead raises nothing and says so, rather
    /// than putting up an empty box.
    func testAChannelWithNoInkHereRaisesNothing() {
        let (manager, _, _) = celFixture()
        XCTAssertFalse(manager.revealPoseChannel(.cel(.group(UUID()))))
        XCTAssertNil(manager.vectorFloat)
    }

    // MARK: - A pose row takes every gesture a grade's row does — TODO (139)

    /// **A pose node is grabbed, marquee'd, focused, menu'd and tapped-to-add exactly as a grade's
    /// is** — and since TODO (139) there is nothing pose-specific left to say about it: the row is a
    /// stored curve, so the same `tap`, `grab` and `keys(in:)` answer the same things on both.
    ///
    /// **The second tap answers `.menu`, not `.focus` and emphatically not `.nothing`** — `.nothing`
    /// is the empty-band case and its caller drops the selection *and* the focus.
    func testAPoseNodeTakesTheSameGesturesAGradesDoes() throws {
        let (manager, layerID, celID) = celFixture()
        animateCel(manager, layerID: layerID, celID: celID)
        let pose = try XCTUnwrap(channel(try content(manager), celX))
        let grade = TimelineGraphBand.Channel(
            parameterID: "brightnessContrast.brightness", name: "Brightness",
            curve: AnimationCurve(keys: [.init(frame: 4, value: 0), .init(frame: 12, value: 1)]),
            uiRange: 0...1, modelDomain: 0...1, format: "%.2f", descriptorIndex: 0,
            isAnimated: true)

        let height = TimelineGraphBand.height
        let ppf: CGFloat = 30
        func at(_ channel: TimelineGraphBand.Channel, frame: Int) -> CGPoint {
            let key = channel.curve.keys.first { $0.frame == frame }!
            return CGPoint(x: TimelineGraphBand.x(ofFrame: frame, pixelsPerFrame: ppf),
                           y: TimelineGraphBand.y(ofValue: key.value, in: channel.axis,
                                                  bandHeight: height))
        }
        for row in [pose, grade] {
            let node = TimelineGraphBand.KeyRef(parameterID: row.parameterID, frame: 4)
            let point = at(row, frame: 4)
            XCTAssertEqual(TimelineGraphBand.grab(at: point, focused: nil, channels: [row],
                                                  pixelsPerFrame: ppf, bandHeight: height),
                           .key(node), "\(row.name): a touch on a node takes hold of it")
            XCTAssertEqual(TimelineGraphBand.tap(at: point, channels: [row], focused: nil,
                                                 frameCount: 40, pixelsPerFrame: ppf, bandHeight: height),
                           .focus(node), "\(row.name): a tap focuses it")
            XCTAssertEqual(TimelineGraphBand.handles(of: node, in: [row], pixelsPerFrame: ppf,
                                                     bandHeight: height).map(\.side), [.outgoing],
                           "\(row.name): its own handle is drawn")
            XCTAssertEqual(TimelineGraphBand.tap(at: point, channels: [row], focused: node,
                                                 frameCount: 40, pixelsPerFrame: ppf, bandHeight: height),
                           .menu(node), "\(row.name): and a second tap raises the menu")
            let onTheLine = CGPoint(x: TimelineGraphBand.x(ofFrame: 8, pixelsPerFrame: ppf),
                                    y: TimelineGraphBand.y(ofValue: row.curve.evaluate(at: 8),
                                                           in: row.axis, bandHeight: height))
            XCTAssertEqual(TimelineGraphBand.tap(at: onTheLine, channels: [row], focused: nil,
                                                 frameCount: 40, pixelsPerFrame: ppf, bandHeight: height),
                           .add(parameterID: row.parameterID, frame: 8, value: row.curve.evaluate(at: 8)),
                           "\(row.name): a tap on the line adds a key")
        }
    }

    // MARK: - The writes, one component at a time

    /// A pose track with X and Rotation both keyed at cel-local 0 and 8 — two independent rows that
    /// share frames, which is the case a whole-pose model could not keep apart.
    private func slideAndTurn(_ manager: CanvasManager, layerID: UUID, celID: UUID) {
        let rest = PoseComponents.Values.resting(in: box)
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID, TransformTrack(box: box, curves: [
            .x: AnimationCurve(keys: [.init(frame: 0, value: rest.x), .init(frame: 8, value: rest.x + 24)]),
            .rotation: AnimationCurve(keys: [.init(frame: 0, value: 0), .init(frame: 8, value: 30)])
        ]))
    }

    private var celRotation: String { PoseChannelID.cel(.cel).parameterID(.rotation) }

    private func storedTrack(_ manager: CanvasManager) -> TransformTrack? {
        manager.layers[1].cels[0].transformTracks[TransformChannelID.cel.id]
    }

    /// **Delete on the X row takes X's key and leaves Rotation's at the same frame** — the owner's
    /// *"fully independent"*, on the graph editor's own menu. One undo step brings it back.
    func testDeletingOneRowsNodeLeavesTheOtherRowsKeyAtThatFrame() throws {
        let (manager, layerID, celID) = celFixture()
        slideAndTurn(manager, layerID: layerID, celID: celID)

        XCTAssertTrue(manager.removeGraphNodeKey(target: target(manager), parameterID: celX, frame: 12),
                      "Frame 12 is cel-local 8 (the fixture's cel starts at 4)")
        XCTAssertEqual(storedTrack(manager)?.curve(.x)?.keys.map(\.frame), [0])
        XCTAssertEqual(storedTrack(manager)?.curve(.rotation)?.keys.map(\.frame), [0, 8],
                       "Rotation still keys frame 8")
        XCTAssertEqual(Set(manager.keyframeFrames(of: target(manager))), [4, 12],
                       "…so the indicator at 12 stays: Rotation's node is still there")

        manager.undo()
        XCTAssertEqual(storedTrack(manager)?.curve(.x)?.keys.map(\.frame), [0, 8], "Undo brings it back")
    }

    /// **Deleting a row's last key removes that row, and the channel when it was the last row** — an
    /// empty curve is never stored, and an empty channel is never stored either.
    func testDeletingTheLastKeysRemoveTheRowAndThenTheChannel() throws {
        let (manager, layerID, celID) = celFixture()
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID, TransformTrack(box: box, curves: [
            .x: AnimationCurve(keys: [.init(frame: 0, value: 30)]),
            .rotation: AnimationCurve(keys: [.init(frame: 0, value: 5)])
        ]))
        XCTAssertTrue(manager.removeGraphNodeKey(target: target(manager), parameterID: celX, frame: 4))
        XCTAssertNil(storedTrack(manager)?.curve(.x), "X's row is gone")
        XCTAssertNotNil(storedTrack(manager)?.curve(.rotation))
        XCTAssertTrue(manager.removeGraphNodeKey(target: target(manager), parameterID: celRotation, frame: 4))
        XCTAssertNil(storedTrack(manager), "and with its last row the channel is gone, not stored empty")
    }

    /// A frame the row does not key is refused rather than deleting whatever key is nearest.
    func testDeletingAFrameTheRowDoesNotKeyIsRefused() throws {
        let (manager, layerID, celID) = celFixture()
        slideAndTurn(manager, layerID: layerID, celID: celID)
        let before = storedTrack(manager)
        XCTAssertFalse(manager.removeGraphNodeKey(target: target(manager), parameterID: celX, frame: 7))
        XCTAssertEqual(storedTrack(manager), before)
    }

    /// **A tap-to-add on the X row adds an X key and nothing else** — no component is invented and
    /// none is reset, because there is nothing to invent: the row is one curve.
    func testAddingOnOneRowKeysThatComponentAlone() throws {
        let (manager, layerID, celID) = celFixture()
        slideAndTurn(manager, layerID: layerID, celID: celID)
        let x = try XCTUnwrap(channel(try content(manager), celX))
        var curve = x.curve
        curve.setKey(AnimationCurve.Key(frame: 8, value: Double(box.midX) + 3))
        XCTAssertTrue(manager.setPoseChannelTrack(target(manager), parameterID: celX, to: curve))
        XCTAssertEqual(storedTrack(manager)?.curve(.x)?.keys.map(\.frame), [0, 4, 8],
                       "absolute 8 is cel-local 4")
        XCTAssertEqual(storedTrack(manager)?.curve(.rotation)?.keys.map(\.frame), [0, 8],
                       "Rotation took no key")
    }

    /// **A row merged across two cels is written back to each cel's own span** — the band draws a
    /// layer's cels as one row per component, so the write splits it again.
    func testAMergedRowIsWrittenBackToEachCelsOwnSpan() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let first = Cel(id: UUID(), startFrame: 0, frameCount: 6, raster: .empty(size: size), vector: .empty(size: size))
        let second = Cel(id: UUID(), startFrame: 6, frameCount: 6, raster: .empty(size: size), vector: .empty(size: size))
        manager.layers[1].cels = [first, second]
        manager.currentLayerIndex = 1
        manager.isGraphEditorOpen = true
        let rest = PoseComponents.Values.resting(in: box)
        for cel in [first, second] {
            CanvasFixture.setPoseTrack(manager, layerID: manager.layers[1].id, celID: cel.id,
                                       TransformTrack(box: box, curves: [.x: AnimationCurve(keys: [
                                           .init(frame: 0, value: rest.x), .init(frame: 5, value: rest.x + 10)])]))
        }
        let merged = try XCTUnwrap(channel(try listed(manager), celX))
        XCTAssertEqual(merged.curve.keys.map(\.frame), [0, 5, 6, 11], "PREMISE: one row, both cels")

        var curve = merged.curve
        var key = try XCTUnwrap(curve.key(atFrame: 11))
        curve.removeKey(atFrame: 11)
        key.frame = 9
        curve.setKey(key)
        XCTAssertTrue(manager.setPoseChannelTrack(target(manager), parameterID: celX, to: curve))
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks["cel"]?.curve(.x)?.keys.map(\.frame), [0, 5],
                       "the first cel is untouched")
        XCTAssertEqual(manager.layers[1].cels[1].transformTracks["cel"]?.curve(.x)?.keys.map(\.frame), [0, 3],
                       "the second cel's key moved from local 5 to local 3")
    }

    // MARK: - The y axis a node is drawn against

    /// Runs one node drag through the funnels the band's own recogniser uses, and hands back the
    /// content the band would draw afterwards.
    @discardableResult
    private func dragNode(_ manager: CanvasManager, _ ref: TimelineGraphBand.KeyRef,
                          by translation: CGSize,
                          pixelsPerFrame: CGFloat = 30) throws -> TimelineGraphBand.Content {
        let content = try content(manager)
        let moves = TimelineGraphBand.moves(of: [ref], in: content.channels, translation: translation,
                                            pixelsPerFrame: pixelsPerFrame,
                                            bandHeight: TimelineGraphBand.height)
        let curves = TimelineGraphBand.applying(moves, to: content.channels)
        XCTAssertFalse(curves.isEmpty, "Fixture: the drag has to change a curve")
        for (id, curve) in curves {
            XCTAssertTrue(manager.setPoseChannelTrack(content.target, parameterID: id, to: curve),
                          "Fixture: the drag has to reach the document")
        }
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
            CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: celID,
                                       TransformTrack(box: box, curves: [.x: AnimationCurve(keys: [
                                           .init(frame: 0, value: Double(box.midX)),
                                           .init(frame: 8, value: Double(box.midX + spread))])]))
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
    /// it** — through the same writer a grade's handle uses, because the row is a stored curve.
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
        let curves = TimelineGraphBand.draggingHandle(ref, in: before.channels, translation: travel,
                                                      pixelsPerFrame: ppf, bandHeight: height)
        XCTAssertEqual(Array(curves.keys), [celX], "the handle shapes its own row's curve")
        XCTAssertTrue(manager.setPoseChannelTrack(before.target, parameterID: celX, to: curves[celX]))

        let moved = try XCTUnwrap(TimelineGraphBand.handles(of: node, in: try content(manager).channels,
                                                            pixelsPerFrame: ppf,
                                                            bandHeight: height).first)
        XCTAssertEqual(moved.point.x, dot.point.x + travel.width, accuracy: 0.001)
        XCTAssertEqual(moved.point.y, dot.point.y + travel.height, accuracy: 0.001)
        XCTAssertEqual(storedTrack(manager)?.curve(.x)?.key(atFrame: 0)?.tangentMode, .free,
                       "the stored key took the authored ease")
    }

    /// **Shaping X's ease shapes X's alone** — TODO (139). A whole-pose key carried one handle pair
    /// for every component, so a handle drag on one row bent all six; a component's curve carries
    /// its own, and Rotation's curve is untouched by a drag on X's.
    func testShapingOneRowsEaseLeavesEveryOtherRowsCurveAlone() throws {
        let (manager, layerID, celID) = celFixture()
        slideAndTurn(manager, layerID: layerID, celID: celID)
        let rotationBefore = storedTrack(manager)?.curve(.rotation)
        let before = try listed(manager)
        let curves = TimelineGraphBand.draggingHandle(.init(key: .init(parameterID: celX, frame: 4), side: .outgoing),
                                                      in: before, translation: CGSize(width: 9, height: -13),
                                                      pixelsPerFrame: 30, bandHeight: TimelineGraphBand.height)
        XCTAssertTrue(manager.setPoseChannelTrack(target(manager), parameterID: celX, to: curves[celX]))
        XCTAssertEqual(storedTrack(manager)?.curve(.x)?.key(atFrame: 0)?.tangentMode, .free)
        XCTAssertEqual(storedTrack(manager)?.curve(.rotation), rotationBefore,
                       "Rotation's keys, handles and tangent modes are exactly what they were")
    }

    // MARK: - The legend names the curves the band draws

    /// The owner, 2026-10-10: *"When in the graph editor, I cant tell which coloured line is which."* The
    /// legend is the answer, and it is read off the band's own content — so this pins that it is *that* list,
    /// in that order, in those colours, rather than a second walk of the model.

    /// **A diagonal slide draws X and Y, and the legend says which hue is which.** Each line carries the
    /// colour its curve is drawn in (`colour(forDescriptorIndex:)` of the channel's own index), and the two
    /// are different colours — otherwise the legend would be a list of names beside two identical lines.
    func testTheLegendNamesXAndYInTheColoursTheirCurvesAreDrawnIn() throws {
        let manager = slidingBothWays()
        let drawn = try content(manager).channels
        XCTAssertEqual(drawn.map(\.name), ["X", "Y"], "PREMISE: a diagonal slide draws X and Y")

        let legend = TimelineGraphBand.legend(of: try content(manager))
        XCTAssertEqual(legend.map(\.name), ["X", "Y"], "the legend lists what the band draws, in its order")
        XCTAssertEqual(legend.map(\.parameterID), drawn.map(\.parameterID))
        for (entry, channel) in zip(legend, drawn) {
            XCTAssertEqual(entry.colour, TimelineGraphBand.colour(forDescriptorIndex: channel.descriptorIndex),
                           "\(entry.name) is named in the colour its curve is drawn in")
            XCTAssertTrue(entry.isAnimated, "\(entry.name) is an animation")
        }
        XCTAssertNotEqual(legend[0].colour, legend[1].colour, "X and Y are told apart by colour")
    }

    /// **The legend follows the band, not the model**: the three flat rows a transform channel starts with
    /// switched off (TODO (59)) are not drawn and so are not named, and switching one on adds its line and
    /// marks it as not animated — it is drawn dashed, and a legend that named it in full colour would be
    /// describing a different line.
    func testTheLegendFollowsWhatTheBandDrawsAndMarksAFlatCurve() throws {
        let (manager, layerID, celID) = celFixture()
        animateCelWithFlatRows(manager, layerID: layerID, celID: celID)
        XCTAssertEqual(TimelineGraphBand.legend(of: try content(manager)).map(\.name), ["X", "Y", "Rotation"],
                       "Scale X, Scale Y and Skew are off the band, so they are off the legend")

        manager.setGraphChannels([celScaleX], visible: true)
        let legend = TimelineGraphBand.legend(of: try content(manager))
        XCTAssertEqual(legend.map(\.name), ["X", "Y", "Scale X", "Rotation"], "switching a row on brings its line in")
        XCTAssertEqual(legend.map(\.isAnimated), [true, false, false, false],
                       "…and a flat curve is named as the dashed, dimmed line it is drawn as")
    }

    func testAClosedBandHasNoLegend() {
        XCTAssertEqual(TimelineGraphBand.legend(of: nil), [])
    }

    /// **More curves than lines say so**, rather than shrinking the text past reading or scrolling inside a
    /// column that is itself scrolled: as many entries as leave room for a last "+N more" line.
    func testMoreCurvesThanLinesLeaveALastLineSayingHowManyAreLeftOut() {
        func entries(_ count: Int) -> [TimelineGraphBand.LegendEntry] {
            (0..<count).map {
                TimelineGraphBand.LegendEntry(parameterID: "c\($0)", name: "Channel \($0)",
                                              colour: TimelineGraphBand.colour(forDescriptorIndex: $0),
                                              isAnimated: true)
            }
        }
        let capacity = TimelineGraphBand.legendCapacity
        XCTAssertGreaterThanOrEqual(capacity, 6, "PREMISE: the band's strip holds at least six lines")
        XCTAssertEqual(CGFloat(capacity) * TimelineGraphBand.legendLineHeight <= TimelineGraphBand.height, true,
                       "…and every line, the last included, fits inside it")

        let exact = TimelineGraphBand.legendLines(of: entries(capacity))
        XCTAssertEqual(exact.shown.count, capacity, "as many as there is room for is all shown")
        XCTAssertEqual(exact.more, 0)

        let over = TimelineGraphBand.legendLines(of: entries(capacity + 3))
        XCTAssertEqual(over.shown.count, capacity - 1, "one line is given up to say how many are not shown")
        XCTAssertEqual(over.more, 4, "…and it counts the one that line replaced")
        XCTAssertEqual(over.shown.map(\.name), (0..<capacity - 1).map { "Channel \($0)" }, "in the band's order")

        XCTAssertEqual(TimelineGraphBand.legendLines(of: []), .init(shown: [], more: 0))
    }

    /// A transformation layer whose own pose slides between frames 0 and 9 along both axes, so the band
    /// draws X and Y.
    private func slidingBothWays() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addTransformLayer()
        let canvasBox = CGRect(origin: .zero, size: size)
        manager.layers[1].transform = LayerPose(
            pose: PoseQuad(restingIn: canvasBox),
            track: CanvasFixture.poseTrack(box: canvasBox, [
                (0, PoseQuad(restingIn: canvasBox)),
                (9, PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 40, y: 24)))]))
        manager.currentLayerIndex = 1
        manager.isGraphEditorOpen = true
        return manager
    }
}
