import XCTest
import CoreGraphics

/// **A folder's channels open into a graph band** — TODO (21)'s last box but one, KEYFRAMES.md §11.7.
///
/// `graphBandExpansion` was keyed by `layerIndex` throughout, so a folder's opacity, grade and
/// parallax share — all keyable from `FolderOptionsPanel`, all drawn as diamonds on the folder's
/// timeline row — could not be *opened* anywhere. The widening is to `KeyframeTarget`, and the row
/// a folder needs to be named by is `CanvasManager.selectedFolderID`, the timeline's second row
/// selection. (A folder's own pose was a fourth channel kind here until TODO (71), which made a
/// folder's Move the Move tool's rather than a container's; a folder poses nothing now.)
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
    private let parallaxShareID = TargetChannel.parallaxShare.id
    private let brightnessID = "brightnessContrast.brightness"
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
        manager.folders[folderIndex(manager, folder)].channelTracks[parallaxShareID] = curve([(0, 1), (8, 0.3)])
        // The child's own opacity, keyed on frames the folder does not key.
        XCTAssertTrue(manager.setTargetChannelTrack(layerRow(manager, 0), channelID: opacityID,
                                                    to: curve([(2, 1), (5, 0.4)])))

        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true
        let listed = manager.graphBandListing(of: try content(manager).target)

        XCTAssertEqual(listed.channels.map(\.parameterID), [opacityID, parallaxShareID],
                       "The folder's own scalars, and nothing of the layer inside it — a folder has "
                       + "no pose rows since TODO (71)")
        XCTAssertEqual(listed.channels.first { $0.parameterID == opacityID }?.curve.keys.map(\.frame),
                       [0, 8], "The opacity row is the *folder's* curve, keyed at 0 and 8 — the "
                       + "child's is keyed at 2 and 5 and shares the id")
        XCTAssertEqual(listed.channels.first { $0.parameterID == parallaxShareID }?.name,
                       TargetChannel.parallaxShare.name)
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
    /// popup over a folder band shows Opacity and Parallax — and hides on the folder's target, not
    /// the layer's.
    func testTheChannelListOverAFolderBandNamesTheFoldersGroupsAndFiltersOnTheFolder() throws {
        let (manager, folder, target) = folderManager()
        keyOpacity(manager, target)
        manager.folders[folderIndex(manager, folder)].channelTracks[parallaxShareID] = curve([(0, 1), (8, 0.3)])
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true

        let groups = try XCTUnwrap(manager.graphChannelGroups)
        XCTAssertEqual(groups.map(\.name), [TargetChannel.opacity.name, TargetChannel.parallaxShare.name],
                       "The folder's two scalar groups, and no pose group: a folder poses nothing")
        XCTAssertTrue(groups.allSatisfy { $0.navigation == nil },
                      "Neither header is the subject a tap raises a box for")

        // Switching the opacity row off must land on the folder's filter and shorten the folder's
        // band.
        let before = try content(manager).channels.count
        manager.setGraphChannels([opacityID], visible: false)
        XCTAssertEqual(try content(manager).channels.count, before - 1, "One row fewer is drawn")
        XCTAssertTrue(manager.graphChannelFilter.hidden(on: target, defaults: []).contains(opacityID),
                      "The filter is authored on the folder — beside (59)'s materialised defaults")
        XCTAssertEqual(manager.graphChannelFilter.hidden(on: layerRow(manager, 0), defaults: []), [],
                       "…and answers nothing for the layer's band")
    }

    /// **Tapping a container header over a folder band raises nothing** — a folder has no pose and
    /// so no container channel to reveal; `revealPoseChannel`'s `.container` arm asks the band's row
    /// and the row answers with no pose. The layer here is a plain drawing layer with no pose either,
    /// so both rows refuse the same way.
    func testRevealingTheContainerChannelOverAFolderBandRaisesNoBox() {
        let (manager, folder, target) = folderManager()
        keyOpacity(manager, target)
        manager.selectFolderRow(folder)
        manager.isGraphEditorOpen = true

        XCTAssertFalse(manager.revealPoseChannel(.container), "A folder has no container pose to reveal")
        XCTAssertNil(manager.floatingPiece, "…and nothing came up")

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

        // Straight up from the 0 line to the 0.5 line, through the band's own y mapping — opacity's
        // `uiRange` is 0…1 and the band insets its axis, so half the band is not half the range.
        let lift = TimelineGraphBand.y(ofValue: 0.5, in: 0...1, bandHeight: band)
            - TimelineGraphBand.y(ofValue: 0, in: 0...1, bandHeight: band)
        let moves = TimelineGraphBand.moves(of: [node], in: content.channels,
                                            translation: CGSize(width: 0, height: lift),
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

    /// **The node menu's writers address a folder** — Delete on an opacity node and Reset Curve's
    /// predicate — through the target-addressed funnels the menu now carries, each paired with the
    /// layer's own store staying untouched; and the pose writers refuse a folder outright, since it
    /// has no pose and no cels.
    func testTheNodeMenusWritersReachAFoldersOwnStores() {
        let (manager, folder, target) = folderManager()
        keyOpacity(manager, target)
        // The layer's own opacity curve shares the id and the frame 8 key, and carries a third key
        // the folder's does not: a writer that *read* the layer's curve and wrote the result onto
        // the folder would leave the folder keyed at 0 and 12, which the folder-only assertion
        // below refuses — mutation-tested; with identical curves that read went unnoticed.
        XCTAssertTrue(manager.setTargetChannelTrack(layerRow(manager, 0), channelID: opacityID,
                                                    to: curve([(0, 1), (8, 0), (12, 0.5)])))
        let at = folderIndex(manager, folder)

        // Delete Keyframe on the folder's opacity node at 8.
        XCTAssertFalse(manager.effectParameterKeyIsAuthored(target: target, parameterID: opacityID,
                                                            frame: 8),
                       "Nothing authored, so Reset Curve is not offered")
        XCTAssertTrue(manager.removeEffectParameterKey(target: target, parameterID: opacityID, frame: 8))
        XCTAssertEqual(manager.folders[at].channelTracks[opacityID]?.keys.map(\.frame), [0],
                       "The folder's node is gone, and the folder's curve is the one it was read from")
        XCTAssertEqual(manager.layers[0].channelTracks[opacityID]?.keys.map(\.frame), [0, 8, 12],
                       "The layer's node on the same id and frame is not")
        XCTAssertFalse(manager.removeEffectParameterKey(target: target, parameterID: opacityID, frame: 8),
                       "A second Delete on the same node is not an edit")

        // A container channel names nothing on a folder: a folder has no pose.
        let containerX = PoseChannelID.container.parameterID(.x)
        XCTAssertFalse(manager.removePoseChannelKey(target: target, parameterID: containerX, frame: 0))
        XCTAssertFalse(manager.addPoseChannelKey(target: target, parameterID: containerX,
                                                 frame: 4, value: 10))
        XCTAssertNil(manager.layers[0].transform, "The layer gained no pose from any of it")

        // And a cel channel names nothing on a folder either: a folder has no cels.
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
