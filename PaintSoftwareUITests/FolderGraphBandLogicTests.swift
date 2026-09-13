import XCTest
import CoreGraphics

/// **A folder's channels open into a graph band** — TODO (21)'s last box but one, KEYFRAMES.md §11.7.
///
/// `graphBandExpansion` was keyed by `layerIndex` throughout, so a folder's opacity, grade, rotate
/// speed, parallax share, shake rows and its own pose — all keyable from `FolderOptionsPanel` since
/// `eef2e65`, all drawn as diamonds on the folder's timeline row — could not be *opened* anywhere.
/// The widening is to `KeyframeTarget`, and the row a folder needs to be named by is
/// `CanvasManager.selectedFolderID`, the timeline's second row selection.
///
/// **What this file pins, and what it leaves to `FolderGraphBandUITests`.** Everything here reaches
/// the model: which row the band resolves to, what it lists, where a write lands, what the pick
/// yields to. The view that draws the band and the two controls that make a folder pickable
/// (`AnimationTimeline`'s name column, `FolderOptionsPanel`'s row) are not compiled into this target,
/// so the cold-start reachability and the drawn curve are the UI class's.
///
/// **Every write assertion reads the folder's stored field on one side and the *layer's* on the
/// other.** The likeliest wrong implementation of any of these funnels is one that resolves the
/// target back to `currentLayerIndex` — which is what every one of them did before — and a test
/// that only checked the folder would pass against a write that landed on both.
@MainActor
final class FolderGraphBandLogicTests: XCTestCase {

    // MARK: - Fixtures

    private let opacityID = TargetChannel.opacity.id
    private let rotateSpeedID = TargetChannel.rotateSpeed.id
    private let brightnessID = "brightnessContrast.brightness"
    private var containerX: String { PoseChannelID.container.parameterID(.x) }
    private var containerRotation: String { PoseChannelID.container.parameterID(.rotation) }
    private let ppf = TimelineKeyMarkers.basePixelsPerFrame
    private let band = TimelineGraphBand.height

    /// **A group holding one drawing layer, the layer current, nothing picked and nothing keyed** —
    /// the document an artist has after "add a folder, drag the layer in".
    ///
    /// The history is emptied afterwards, `FolderKeyframeEntryLogicTests.folderManager`'s reason:
    /// `addFolder` and `restackLayer` are structural edits and several tests count steps.
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
            XCTFail("The fixture's folder must be in the document", file: file, line: line)
            return 0
        }
        return index
    }

    private func curve(_ pairs: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    /// The folder's opacity keyed 1 at 0 and 0 at 8, through the same funnel the slider and the band
    /// write through — so the fixture cannot key a store the band does not read.
    private func keyOpacity(_ manager: CanvasManager, _ target: KeyframeTarget) {
        XCTAssertTrue(manager.setTargetChannelTrack(target, channelID: opacityID,
                                                    to: curve([(0, 1), (8, 0)])),
                      "Fixture premise: the folder's opacity took a curve")
    }

    /// A container pose on the folder, keyed at rest on 0 and slid 24 points right on 8.
    private func keyPose(_ manager: CanvasManager, _ folder: UUID,
                         file: StaticString = #filePath, line: UInt = #line) {
        guard var pose = manager.restingContainerPose else {
            return XCTFail("The fixture's canvas must have a size", file: file, line: line)
        }
        let rest = pose.pose
        pose.track.setKey(TransformTrack.Key(frame: 0, pose: rest))
        pose.track.setKey(TransformTrack.Key(
            frame: 8, pose: PoseQuad(box: rest.box, mappedBy: CGAffineTransform(translationX: 24, y: 0))))
        manager.setFolderTransform(folder, to: pose)
    }

    private func layerRow(_ manager: CanvasManager, _ index: Int) -> KeyframeTarget {
        .layer(id: manager.layers[index].id)
    }

    private func content(_ manager: CanvasManager,
                         file: StaticString = #filePath, line: UInt = #line) throws
        -> TimelineGraphBand.Content {
        try XCTUnwrap(manager.graphBandContent, "The band is not open", file: file, line: line)
    }

    // MARK: - The row the band resolves to

    /// **Picking a folder's row puts the band under it; picking a layer's row takes it back.** The
    /// owner's ruling that the band follows the selection, with a second kind of row to follow.
    ///
    /// Operands: `graphBandTarget` — what every reader of the expansion asks — against the ids of
    /// the folder and the layer, in both directions, and with the band both closed and open. The
    /// closed half matters: a pick is a selection, not a property of an open band, so the band has
    /// to open *on* the picked row rather than the pick being lost when there is no band to move.
    func testPickingAFolderRowIsWhereTheBandOpensAndPickingALayerTakesItBack() {
        let (manager, folder, target) = folderManager()
        XCTAssertNil(manager.selectedFolderID, "A fresh document has picked no folder")
        XCTAssertEqual(manager.graphBandTarget, layerRow(manager, 0),
                       "PREMISE: with nothing picked the band's row is the current layer")

        manager.selectFolderRow(folder)
        XCTAssertEqual(manager.graphBandTarget, target, "The band's row is the picked folder")
        XCTAssertNil(manager.graphBandExpansion, "…and it is still closed — a pick opens nothing")
        XCTAssertEqual(manager.currentLayerIndex, 0,
                       "The brush's layer did not move: a folder pick is the band's selection, not "
                       + "the layer panel's")

        manager.isGraphEditorOpen = true
        XCTAssertEqual(manager.graphBandExpansion?.target, target,
                       "Opened later, the band opens on the picked row")
        XCTAssertEqual(manager.graphBandExpansion?.height, TimelineGraphBand.height)

        manager.selectLayer(0)
        XCTAssertNil(manager.selectedFolderID, "Picking a layer's row drops the folder pick…")
        XCTAssertEqual(manager.graphBandExpansion?.target, layerRow(manager, 0),
                       "…and the band goes to the layer, though `currentLayerIndex` did not change: "
                       + "a tap on the row the brush is already on is still a pick of that row")
    }

    /// **A layer that becomes current by any route takes the band** — a new layer, a restack, an
    /// undo that restores another selection — because that is the ruling a layer already obeys.
    /// But **an undo that writes the same index back leaves the pick alone**, and that is the case
    /// a folder band's own drag reaches: the drag is a gesture bracket, its undo is a structure
    /// snapshot restore, and that restore assigns `currentLayerIndex` unconditionally.
    func testAChangeOfCurrentLayerDropsThePickAndAnUndoOfTheBandsOwnDragDoesNot() {
        let (manager, folder, target) = folderManager()
        manager.addLayer()
        manager.currentLayerIndex = 0
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        keyOpacity(manager, target)
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true

        // A band drag on the folder's opacity, as the track view performs one: one bracket, the
        // curve written per tick through the target-addressed funnel.
        manager.beginStructureGesture()
        XCTAssertTrue(manager.setTargetChannelTrack(target, channelID: opacityID,
                                                    to: curve([(0, 1), (8, 0.5)])))
        manager.commitStructureGesture(label: .effectKeyframes)
        XCTAssertEqual(manager.graphBandExpansion?.target, target, "PREMISE: the band is on the folder")

        manager.undo()
        XCTAssertEqual(manager.folders[folderIndex(manager, folder)].channelTracks[opacityID]?
                            .keys.last?.value, 0, "PREMISE: the undo took the drag back")
        XCTAssertEqual(manager.graphBandExpansion?.target, target, """
            One press of Undo on a folder band's drag must leave the band on the folder. The undo \
            restores a structure snapshot that assigns `currentLayerIndex` to the value it already \
            holds; a pick cleared on every assignment rather than on a change would move the band \
            to the layer on the first Undo.
            """)

        manager.currentLayerIndex = 1
        XCTAssertNil(manager.selectedFolderID)
        XCTAssertEqual(manager.graphBandExpansion?.target, layerRow(manager, 1),
                       "A layer that became current by any route is the band's row")
    }

    /// **A pinned band holds a folder row through the selection a block drag makes** —
    /// `pinGraphBand`'s contract, on the second kind of row. A block lifted off a layer selects that
    /// layer inside the touch, which drops the folder pick; without the pin the band would reflow
    /// by 96 pt under a finger already dragging.
    func testAPinnedFolderBandStaysPutWhileABlockDragSelectsALayer() {
        let (manager, folder, target) = folderManager()
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true

        manager.pinGraphBand()
        manager.selectLayer(0)
        XCTAssertNil(manager.selectedFolderID, "The drag's selection dropped the pick…")
        XCTAssertEqual(manager.graphBandExpansion?.target, target,
                       "…and the band is not allowed to follow yet")
        XCTAssertEqual(manager.graphBandContent?.target, target,
                       "…nor is what it draws, so the curves do not change mid-gesture")

        manager.releaseGraphBand()
        XCTAssertEqual(manager.graphBandExpansion?.target, layerRow(manager, 0),
                       "The finger is off the track: the band goes where the selection went")
    }

    /// **A deleted folder is not a row the band can be on, and an undo that brings it back brings
    /// the band with it.** The pick is an id, so it survives the folder's absence; `graphBandTarget`
    /// answers as if nothing were picked while the folder is gone.
    func testAPickedFolderThatIsDeletedYieldsToTheLayerUntilItComesBack() {
        let (manager, folder, target) = folderManager()
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true
        XCTAssertEqual(manager.graphBandExpansion?.target, target, "PREMISE")

        manager.deleteFolder(folder)
        XCTAssertEqual(manager.graphBandExpansion?.target, layerRow(manager, 0),
                       "No folder, no folder row: the band is on the current layer")

        manager.undo()
        XCTAssertTrue(manager.folders.contains { $0.id == folder }, "PREMISE: the folder is back")
        XCTAssertEqual(manager.graphBandExpansion?.target, target,
                       "…and so is the band, because the pick named the folder and not a position")
    }

    /// **Both halves of the timeline resolve a folder expansion to the folder's row**, through the
    /// one `TimelineRowLayout.make` — so the name column and the track agree about which row grew.
    /// A folder inside a collapsed parent resolves to no row, the layer rule read across.
    func testTheRowLayoutResolvesAFolderExpansionToTheFoldersRow() {
        let (manager, folder, target) = folderManager()
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true
        let rows = manager.layerStackRows
        let position = try? XCTUnwrap(rows.firstIndex { $0.folderID == folder })
        XCTAssertEqual(position, 0, "PREMISE: the folder is the top row and its layer sits under it")

        let layout = TimelineRowLayout.make(rows: rows, rulerHeight: 18, rowHeight: 34,
                                            expansion: manager.graphBandExpansion)
        XCTAssertEqual(layout.expandedRow, 0, "The folder's row is the expanded one")
        XCTAssertEqual(layout.expansion(ofRow: 0), band)
        XCTAssertEqual(layout.blockHeight(ofRow: 0), 34,
                       "The folder's bar and diamonds keep the block half — the band hangs below")
        XCTAssertEqual(layout.height(ofRow: 0), 34 + band)
        XCTAssertEqual(layout.expansion(ofRow: 1), 0, "The layer inside it is not expanded")
        XCTAssertEqual(layout.y(ofRow: 1), 18 + TimelineRowLayout.verticalInset + 34 + band
                       + TimelineRowLayout.gap,
                       "…and it moved down by exactly one band, because the band arrived above it")

        // Inside a collapsed parent the folder row is not presented, and there is nothing to open
        // the band under.
        let parent = manager.addFolder(name: "Parent")
        manager.restackFolder(folder, above: .folder(parent), parentFolderID: parent)
        manager.toggleFolderExpanded(parent)
        XCTAssertFalse(manager.layerStackRows.contains { $0.folderID == folder },
                       "PREMISE: the picked folder is hidden inside its collapsed parent")
        let hidden = TimelineRowLayout.make(rows: manager.layerStackRows, rulerHeight: 18,
                                            rowHeight: 34, expansion: manager.graphBandExpansion)
        XCTAssertNil(hidden.expandedRow, "A row that is not on screen is not expanded")
        XCTAssertEqual(manager.graphBandExpansion?.target, target,
                       "…though the pick itself is untouched, so expanding the parent shows the band")
    }

    // MARK: - What a folder's band lists

    /// **A folder's band lists the folder's own channels and none of its children's.**
    ///
    /// Three kinds on the folder — opacity and a keyed rotate speed (`TargetChannel` rows), and the
    /// container pose (six decomposed rows) — with the child layer carrying a keyed opacity of its
    /// own that must not appear. The child's curve is the operand that separates "listed the
    /// folder" from "listed the current layer": both have an `opacity` id, so a band that resolved
    /// the folder target back to `layers[currentLayerIndex]` would list one `opacity` row too, and
    /// only the key frames tell them apart.
    func testAFoldersBandListsTheFoldersChannelsAndNotItsChildrens() throws {
        let (manager, folder, target) = folderManager()
        keyOpacity(manager, target)
        manager.folders[folderIndex(manager, folder)].channelTracks[rotateSpeedID] = curve([(0, 1), (8, 3)])
        keyPose(manager, folder)
        // The child's own opacity, keyed on frames the folder does not key.
        XCTAssertTrue(manager.setTargetChannelTrack(layerRow(manager, 0), channelID: opacityID,
                                                    to: curve([(2, 1), (5, 0.4)])))

        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true
        let listed = manager.graphBandListing(of: try content(manager).target)

        XCTAssertEqual(listed.channels.map(\.parameterID),
                       [opacityID, rotateSpeedID]
                       + PoseComponents.Component.allCases.map { PoseChannelID.container.parameterID($0) },
                       "The folder's own scalars first, then its pose decomposed — and nothing of "
                       + "the layer inside it")
        XCTAssertEqual(listed.channels.first { $0.parameterID == opacityID }?.curve.keys.map(\.frame),
                       [0, 8], "The opacity row is the *folder's* curve, keyed at 0 and 8 — the "
                       + "child's is keyed at 2 and 5 and shares the id")
        XCTAssertEqual(listed.channels.first { $0.parameterID == rotateSpeedID }?.name,
                       TargetChannel.rotateSpeed.name)
        XCTAssertEqual(listed.channels.first { $0.parameterID == containerX }?.curve.keys.map(\.frame),
                       [0, 8], "The pose rows are the authored track at absolute frames — a folder's "
                       + "container pose keys in document frames, so no offset applies")
        XCTAssertEqual(listed.declined, [], "Nothing projective, nothing declined")

        // The band's own accessibility value says the same thing, which is what the UI class reads.
        XCTAssertTrue(TimelineGraphBand.encode(try content(manager)).hasPrefix("\(opacityID):0,8|"),
                      "What is drawn starts with the folder's opacity curve")

        manager.selectLayer(0)
        XCTAssertEqual(try content(manager).channels.map(\.parameterID), [opacityID],
                       "Back on the layer, the band lists the child's one channel")
        XCTAssertEqual(try content(manager).channels.first?.curve.keys.map(\.frame), [2, 5])
    }

    /// **The channel list is built from the same listing and names the folder's groups**, so the
    /// popup over a folder band shows Opacity, Rotate Speed and the pose group with its Move name —
    /// and hides on the folder's target, not the layer's.
    func testTheChannelListOverAFolderBandNamesTheFoldersGroupsAndFiltersOnTheFolder() throws {
        let (manager, folder, target) = folderManager()
        keyOpacity(manager, target)
        manager.folders[folderIndex(manager, folder)].channelTracks[rotateSpeedID] = curve([(0, 1), (8, 3)])
        keyPose(manager, folder)
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true

        let groups = try XCTUnwrap(manager.graphChannelGroups)
        XCTAssertEqual(groups.map(\.name),
                       [TargetChannel.opacity.name, TargetChannel.rotateSpeed.name, "Group Transform"],
                       "The pose group is named for a group, not `defaultName`'s \"Layer Transform\"")
        XCTAssertEqual(groups.last?.navigation, .container,
                       "The pose group's header is the subject a tap raises the box for")

        // TODO (59)'s default hides the pose's flat scale and skew rows; switching the opacity row
        // off must land on the folder's filter and shorten the folder's band.
        let before = try content(manager).channels.count
        manager.setGraphChannels([opacityID], visible: false)
        XCTAssertEqual(try content(manager).channels.count, before - 1, "One row fewer is drawn")
        XCTAssertEqual(manager.graphChannelFilter.hidden(on: target, defaults: []), [opacityID],
                       "The filter is authored on the folder…")
        XCTAssertEqual(manager.graphChannelFilter.hidden(on: layerRow(manager, 0), defaults: []), [],
                       "…and answers nothing for the layer's band")
    }

    /// **Tapping the pose group's header over a folder band raises the folder's box**, not the
    /// current layer's — `revealPoseChannel`'s `.container` arm asks the band's row. The layer here
    /// is a plain drawing layer with no pose, so the old answer would have been a refusal.
    func testRevealingTheContainerChannelOverAFolderBandRaisesTheFoldersBox() {
        let (manager, folder, target) = folderManager()
        keyPose(manager, folder)
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true

        XCTAssertTrue(manager.revealPoseChannel(.container), "A box came up")
        XCTAssertEqual(manager.floatingPiece?.kind, .containerPose)
        XCTAssertEqual(manager.floatingPiece?.containerTarget, target, """
            The box poses the folder — the row whose curves the list is a control of. A build that \
            raised `beginContainerPoseMove()` with no target would pose the current layer, which \
            here has no pose and refuses, so the assertion above would have gone red first; on a \
            transformation layer it would have raised the wrong box in silence.
            """)
        manager.commitAllInteractiveState()

        manager.selectLayer(0)
        XCTAssertFalse(manager.revealPoseChannel(.container),
                       "Back on the layer, which poses nothing, the same tap refuses")
    }

    // MARK: - Where a write lands

    /// **A node drag on a folder's opacity curve writes the folder's `channelTracks`** — the
    /// funnel `writeGraphBandCurves` takes for a target channel, exercised at the model with the
    /// band's own drag arithmetic.
    ///
    /// Operands: the folder's stored curve against the layer's. The layer carries an opacity curve
    /// of its own, keyed on the same frames, so a write routed to `layers[currentLayerIndex]` would
    /// move the layer's key at 8 and leave the folder's where it was — both assertions go red.
    func testANodeDragOnAFoldersOpacityCurveWritesTheFolderAndNotTheLayer() throws {
        let (manager, folder, target) = folderManager()
        keyOpacity(manager, target)
        XCTAssertTrue(manager.setTargetChannelTrack(layerRow(manager, 0), channelID: opacityID,
                                                    to: curve([(0, 1), (8, 0)])))
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true
        let content = try content(manager)
        let node = TimelineGraphBand.KeyRef(parameterID: opacityID, frame: 8)

        // Straight up by half the band: opacity's `uiRange` is 0…1, so that is +0.5.
        let moves = TimelineGraphBand.moves(of: [node], in: content.channels,
                                            translation: CGSize(width: 0, height: -band / 2),
                                            pixelsPerFrame: ppf, bandHeight: band)
        let written = TimelineGraphBand.applying(moves, to: content.channels)
        let rewritten = try XCTUnwrap(written[opacityID], "The drag rewrote the opacity curve")
        XCTAssertEqual(rewritten.keys.last?.value ?? 0, 0.5, accuracy: 0.02, "PREMISE: it went up by half")

        let before = manager.history.undoStack.count
        XCTAssertTrue(manager.setTargetChannelTrack(content.target, channelID: opacityID, to: rewritten))
        XCTAssertEqual(manager.history.undoStack.count - before, 1, "One drag, one press of Undo")

        let at = folderIndex(manager, folder)
        XCTAssertEqual(manager.folders[at].channelTracks[opacityID]?.keys.last?.value ?? 0, 0.5,
                       accuracy: 0.02, "The folder's key at 8 moved")
        XCTAssertEqual(manager.layers[0].channelTracks[opacityID]?.keys.last?.value, 0,
                       "The layer's key at 8, on the same id and the same frame, did not")
        XCTAssertEqual(manager.folders[at].opacity(atFrame: 8), 0.5, accuracy: 0.02,
                       "…and the folder resolves the new value at that frame, which is what the "
                       + "compositor multiplies its alpha by")

        manager.undo()
        XCTAssertEqual(manager.folders[at].channelTracks[opacityID]?.keys.last?.value, 0,
                       "One press puts the folder's key back")
    }

    /// **A node drag on a folder's pose curve writes the folder's `transform.track`** — the pose
    /// funnel on the second home. The snapshot names the folder, carries no cels, and the write
    /// and the restore both re-resolve it by id.
    func testANodeDragOnAFoldersPoseCurveWritesTheFoldersTrack() throws {
        let (manager, folder, target) = folderManager()
        keyPose(manager, folder)
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true
        // Draw the X row alone so the grab is unambiguous: six rows key the same two frames.
        manager.setGraphChannels(PoseComponents.Component.allCases
                                    .map { PoseChannelID.container.parameterID($0) }
                                    .filter { $0 != containerX }, visible: false)
        let content = try content(manager)
        XCTAssertEqual(content.channels.map(\.parameterID), [containerX], "PREMISE: one row drawn")

        let snapshot = manager.graphBandPoseSnapshot(of: content.target)
        XCTAssertEqual(snapshot.target, target)
        XCTAssertTrue(snapshot.cels.isEmpty, "A folder has no cels to snapshot")
        XCTAssertEqual(snapshot.container?.track.keyedFrames, [0, 8], "…and its container pose")

        let node = TimelineGraphBand.KeyRef(parameterID: containerX, frame: 8)
        let moves = TimelineGraphBand.moves(of: [node], in: content.channels,
                                            translation: CGSize(width: ppf * 3, height: 0),
                                            pixelsPerFrame: ppf, bandHeight: band)
        XCTAssertEqual(moves[node]?.frame, 11, "PREMISE: a retime of three frames")

        let before = manager.history.undoStack.count
        XCTAssertTrue(manager.writeGraphBandPoseEdits(
            TimelineGraphBand.poseEdits(moves, in: content.channels),
            from: snapshot, target: content.target))
        let at = folderIndex(manager, folder)
        XCTAssertEqual(manager.folders[at].transform?.track.keyedFrames, [0, 11],
                       "The folder's key travelled from 8 to 11")
        XCTAssertNil(manager.layers[0].transform, "The layer inside it gained no pose")
        XCTAssertEqual(manager.history.undoStack.count - before, 1, "Outside a bracket, one step")
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 11],
                       "…and the diamond on the folder's row went with the node — §2.28")

        XCTAssertTrue(manager.restoreGraphBandPoses(snapshot, target: content.target))
        XCTAssertEqual(manager.folders[at].transform?.track.keyedFrames, [0, 8],
                       "A cancelled drag puts the folder's track back in one call")
    }

    /// **The node menu's writers address a folder** — Delete on an opacity node, Reset Curve's
    /// predicate, and Delete and tap-to-add on a pose node — through the target-addressed funnels
    /// the menu now carries. Each is paired with the layer's own store staying untouched.
    func testTheNodeMenusWritersReachAFoldersOwnStores() {
        let (manager, folder, target) = folderManager()
        keyOpacity(manager, target)
        XCTAssertTrue(manager.setTargetChannelTrack(layerRow(manager, 0), channelID: opacityID,
                                                    to: curve([(0, 1), (8, 0)])))
        keyPose(manager, folder)
        let at = folderIndex(manager, folder)

        // Delete Keyframe on the folder's opacity node at 8.
        XCTAssertFalse(manager.effectParameterKeyIsAuthored(target: target, parameterID: opacityID,
                                                            frame: 8),
                       "Nothing authored, so Reset Curve is not offered")
        XCTAssertTrue(manager.removeEffectParameterKey(target: target, parameterID: opacityID, frame: 8))
        XCTAssertEqual(manager.folders[at].channelTracks[opacityID]?.keys.map(\.frame), [0],
                       "The folder's node is gone")
        XCTAssertEqual(manager.layers[0].channelTracks[opacityID]?.keys.map(\.frame), [0, 8],
                       "The layer's node on the same id and frame is not")
        XCTAssertFalse(manager.removeEffectParameterKey(target: target, parameterID: opacityID, frame: 8),
                       "A second Delete on the same node is not an edit")

        // Delete Keyframe on the folder's pose node at 8, then tap-to-add one back at 4.
        XCTAssertTrue(manager.removePoseChannelKey(target: target, parameterID: containerX, frame: 8))
        XCTAssertEqual(manager.folders[at].transform?.track.keyedFrames, [0])
        XCTAssertTrue(manager.addPoseChannelKey(target: target, parameterID: containerRotation,
                                                frame: 4, value: 10))
        XCTAssertEqual(manager.folders[at].transform?.track.keyedFrames, [0, 4],
                       "A tap on the Rotation row added a key at 4")
        let added = manager.folders[at].transform?.track.key(atFrame: 4)?.pose
        XCTAssertEqual(added.flatMap { PoseComponents.decompose($0)?.rotation } ?? 0, 10, accuracy: 0.01,
                       "…holding the tapped rotation and the other five components as they resolved")
        XCTAssertNil(manager.layers[0].transform, "The layer gained no pose from any of it")

        // A cel channel names nothing on a folder: a folder has no cels.
        XCTAssertFalse(manager.removePoseChannelKey(target: target,
                                                    parameterID: PoseChannelID.cel(.cel).parameterID(.x),
                                                    frame: 0))
        XCTAssertFalse(manager.addPoseChannelKey(target: target,
                                                 parameterID: PoseChannelID.cel(.cel).parameterID(.x),
                                                 frame: 0, value: 0))
    }

    /// **A folder's grade node goes through the folder overload of `setEffectParameterTrack`** —
    /// the third home a band can write to, on a node folder carrying a grade.
    func testAGradeNodeOnAFolderWritesTheFoldersEffectTracks() {
        let (manager, folder, target) = folderManager()
        manager.setNodeEffect(folder, to: .brightnessContrast(
            Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        XCTAssertTrue(manager.setEffectParameterTrack(target, parameterID: brightnessID,
                                                      to: curve([(0, 1), (8, 2)])),
                      "The target-addressed writer reaches the folder's grade")
        let at = folderIndex(manager, folder)
        XCTAssertEqual(manager.folders[at].effectTracks[brightnessID]?.keys.map(\.frame), [0, 8])

        XCTAssertTrue(manager.removeEffectParameterKey(target: target, parameterID: brightnessID, frame: 8))
        XCTAssertEqual(manager.folders[at].effectTracks[brightnessID]?.keys.map(\.frame), [0])
        XCTAssertTrue(manager.layers[0].effectTracks.isEmpty, "The drawing layer has no grade to key")
    }
}
