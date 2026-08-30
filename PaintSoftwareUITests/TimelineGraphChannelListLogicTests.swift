import XCTest
import CoreGraphics

/// **The graph editor's channel list** — KEYFRAMES.md §11.5, stage D4.
///
/// `Views/AnimationTimeline.swift` is not compiled into this target, so the SwiftUI rows and their
/// checkmarks are not assertable here and none of the decisions behind them are made there:
/// `TimelineGraphChannelList` holds the grouping, the toggle arithmetic and the filter's scope, and
/// this file is where those are pinned. `GraphEditorUITests` is the one check that a real tap on a
/// real box takes a curve off a real band.
///
/// Four of the six tests below exist because the thing they check is a decision that looks arbitrary
/// from inside the code and would be "tidied" away by the next reader: the list is built from the
/// **strict** membership predicate, the filter is applied **before** the layout key rather than at
/// draw time, a channel's colour survives its neighbour being hidden, and a group's mixed box
/// resolves **upward**.
@MainActor
final class TimelineGraphChannelListLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// `TimelineGraphBandLogicTests`' graded document: an opaque floor under a value layer carrying a
    /// brightness/contrast grade, whose two parameters are `Effect.parameters` indices 0 and 1. Two
    /// channels is the smallest fixture in which hiding one is different from hiding all.
    private let gradeIndex = 1
    private let brightnessID = "brightnessContrast.brightness"
    private let contrastID = "brightnessContrast.contrast"

    private func linear(_ pairs: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    /// Both channels animated and the band open on the grade.
    private func bandManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1,
                                                                                    contrast: 1)))
        manager.currentLayerIndex = gradeIndex
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.0), (6, 0.2)]))
        manager.isGraphEditorOpen = true
        return manager
    }

    private func target(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[gradeIndex].id)
    }

    private func channels(_ manager: CanvasManager) -> [TimelineGraphBand.Channel] {
        let target = target(manager)
        return TimelineGraphBand.channels(effect: manager.storedEffect(of: target),
                                          tracks: manager.keyframeState(of: target).tracks)
    }

    private func key(_ manager: CanvasManager) -> TimelineLayoutKey {
        TimelineLayoutKey.make(canvasManager: manager,
                               stackRows: manager.layerStackRows,
                               pixelsPerFrame: 30,
                               displayedFrameCount: 24,
                               contentWidth: 720,
                               rowHeight: 34,
                               rulerHeight: 18,
                               drag: nil).key
    }

    private func drawnIDs(_ manager: CanvasManager) -> [String] {
        manager.graphBandContent?.channels.map(\.parameterID) ?? []
    }

    // MARK: - Grouping, which the id format is supposed to give for free

    /// **The group is the text before the first dot, and nothing else is consulted.**
    ///
    /// Total on purpose: a caller must not have to know the `"<case>.<field>"` format is honoured, so
    /// an id with no dot is its own group rather than an empty one, and only the *first* dot splits.
    func testAGroupIsTheTextBeforeTheFirstDot() {
        XCTAssertEqual(TimelineGraphChannelList.groupID(ofParameterID: "blur.radius"), "blur")
        XCTAssertEqual(TimelineGraphChannelList.groupID(ofParameterID: "hsvShift.hue"), "hsvShift")
        XCTAssertEqual(TimelineGraphChannelList.groupID(ofParameterID: "curves.points.0"), "curves",
                       "The first dot is the structural one; the field half keeps the rest")
        XCTAssertEqual(TimelineGraphChannelList.groupID(ofParameterID: "malformed"), "malformed",
                       "An id with no dot is its own group rather than a crash or an empty string")
    }

    /// **What the id format actually buys, stated as a fact rather than assumed.**
    ///
    /// §11.5 says grouping falls out of the format for free. It does — but a band is one layer, a
    /// layer is one grade and a grade is one id prefix, so **every band today has exactly one
    /// group**. That is worth a test rather than a comment: it is the premise behind the list coming
    /// up expanded, and the day a second channel source arrives (a transform, a folder's grade) this
    /// assertion is the one that changes and says so.
    func testEveryBandTodayHasExactlyOneGroupBecauseALayerHasOneGrade() throws {
        let manager = bandManager()
        let groups = try XCTUnwrap(manager.graphChannelGroups)
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.id, "brightnessContrast")
        XCTAssertEqual(group.name, "Brightness / Contrast",
                       "The group's label is the effect's own name — a group has no descriptor row")
        XCTAssertEqual(group.rows.map(\.parameterID), [brightnessID, contrastID],
                       "…in `Effect.parameters` order, which is the order the band draws them in")
    }

    /// **The rows are exactly the band's channels — the strict predicate, never the loose one.**
    ///
    /// A channel keyed twice at one value is a curve *in force* and is not an animation; the auto-key
    /// arm has to see it and the list must not, or the artist is offered a checkbox for a flat line
    /// they never drew. Pinned against the model's own accessor rather than against a literal, which
    /// is §2.28's rule: two implementations of one invariant is the defect the union was written for.
    func testTheListsRowsAreExactlyTheBandsChannels() {
        let manager = bandManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.0), (6, 1.0)]))

        let rows = (manager.graphChannelGroups ?? []).flatMap { $0.rows.map(\.parameterID) }
        XCTAssertEqual(rows, manager.listedAnimationChannelIDs(of: target(manager)))
        XCTAssertEqual(rows, [brightnessID],
                       "A flat curve is in force and is still not an animation, so it is not a row")
        XCTAssertEqual(manager.curvedEffectChannelIDs(of: target(manager)).count, 2,
                       "PREMISE: the loose predicate does see it, which is what the two are for")
    }

    /// A hidden channel keeps its row. The list is where a channel is switched back on, so a list
    /// that dropped its own hidden rows would be a one-way door.
    func testHidingAChannelLeavesItsRowOnTheList() {
        let manager = bandManager()
        manager.setGraphChannels([brightnessID], visible: false)

        let rows = (manager.graphChannelGroups ?? []).flatMap(\.rows)
        XCTAssertEqual(rows.map(\.parameterID), [brightnessID, contrastID])
        XCTAssertEqual(rows.map(\.isVisible), [false, true])
        XCTAssertEqual(drawnIDs(manager), [contrastID], "…and the band drew only the other one")
    }

    // MARK: - The group's box takes the whole group

    /// **"Visible or invisible like a whole"**, and the mixed case resolves *upward*.
    ///
    /// A tap on a partly-checked box must not take away a channel the artist has just switched on,
    /// so mixed goes to all-visible and only the tap after that hides the group. The three-state box
    /// is the other half: without the dash, "some are hidden" reads as "none are".
    func testAGroupsBoxTakesEveryChannelInItAndMixedResolvesUpward() throws {
        let manager = bandManager()
        func group() throws -> TimelineGraphChannelList.Group {
            try XCTUnwrap((manager.graphChannelGroups ?? []).first)
        }

        XCTAssertTrue(try group().isFullyVisible)
        XCTAssertFalse(try group().isMixed)

        manager.setGraphChannels([brightnessID], visible: false)
        XCTAssertTrue(try group().isMixed, "One of two off is the dashed box, not the empty one")
        XCTAssertTrue(try group().visibilityAfterToggle,
                      "A tap on a mixed group turns it all on rather than all off")

        manager.setGraphChannels(try group().rows.map(\.parameterID),
                                 visible: try group().visibilityAfterToggle)
        XCTAssertEqual(drawnIDs(manager), [brightnessID, contrastID], "…which is what it did")

        manager.setGraphChannels(try group().rows.map(\.parameterID),
                                 visible: try group().visibilityAfterToggle)
        XCTAssertEqual(drawnIDs(manager), [], "…and the tap after that took the whole group")
        XCTAssertFalse(try group().isMixed)
        XCTAssertFalse(try group().isFullyVisible)
    }

    // MARK: - The band an empty band is not

    /// **An all-hidden band and a band with nothing on it are different states and must not read the
    /// same.** `"empty"` exists because an artist looking for a curve that was never there is the
    /// failure; here the curves are there and the artist put them away, and `"hidden"` says the way
    /// back is the list. The artist's own version of this is the tinted button, which is the only
    /// signal in the state where the band itself is correctly blank.
    func testAnAllHiddenBandSaysHiddenRatherThanEmpty() throws {
        let manager = bandManager()
        XCTAssertEqual(TimelineGraphBand.encode(try XCTUnwrap(manager.graphBandContent)),
                       "brightnessContrast.brightness:0,10|brightnessContrast.contrast:0,6")
        XCTAssertFalse(manager.graphBandHasHiddenChannels)

        manager.setGraphChannels([brightnessID, contrastID], visible: false)
        let emptied = try XCTUnwrap(manager.graphBandContent)
        XCTAssertEqual(emptied.channels, [])
        XCTAssertEqual(emptied.hiddenCount, 2)
        XCTAssertEqual(TimelineGraphBand.encode(emptied), "hidden")
        XCTAssertTrue(manager.graphBandHasHiddenChannels, "…so the button that did it is lit")

        manager.currentLayerIndex = 0
        XCTAssertEqual(TimelineGraphBand.encode(try XCTUnwrap(manager.graphBandContent)), "empty",
                       "A layer that animates nothing still says `empty` — the other state entirely")
    }

    // MARK: - The layout gate, which is where a filter silently does nothing

    /// **The filter is applied before the key is built, and this is the proof.**
    ///
    /// `relayout()` early-returns on `built.key == laidOutKey`, so a filter applied at draw time —
    /// read off the manager inside `TimelineGraphBandView.draw` — would change what the band should
    /// show without changing the key, and unchecking a box would move nothing on screen until some
    /// unrelated edit happened to open the gate. Nothing is thrown and nothing is logged when that
    /// happens, which is why this is a mutation test and not "the field compiles".
    ///
    /// Both directions, because a gate that opens on hide and not on show is the same bug backwards.
    func testHidingAndShowingAChannelBothMoveTheLayoutKey() {
        let manager = bandManager()
        let all = key(manager)

        manager.setGraphChannels([brightnessID], visible: false)
        let filtered = key(manager)
        XCTAssertNotEqual(all, filtered, "Unchecking a channel has to reopen the layout gate")
        XCTAssertEqual(filtered.graphBand?.channels.map(\.parameterID), [contrastID])
        XCTAssertEqual(filtered.graphBand?.hiddenCount, 1)

        manager.setGraphChannels([brightnessID], visible: true)
        XCTAssertEqual(all, key(manager), "…and checking it again puts the layout back exactly")
    }

    /// The filter moves the band and **nothing else on the track**: no frame moved, so the marker
    /// band is unchanged. The half of the pin that proves the test above is about `graphBand` rather
    /// than about something else in the key happening to move.
    func testTheFilterMovesTheBandAndNoOtherPartOfTheKey() {
        let manager = bandManager()
        let before = key(manager)
        manager.setGraphChannels([brightnessID], visible: false)
        let after = key(manager)

        XCTAssertEqual(before.trackMarkers, after.trackMarkers,
                       "A hidden curve is still a keyed channel — the diamonds do not move")
        XCTAssertEqual(before.tracks, after.tracks, "…and no cel moved")
        XCTAssertEqual(after.graphBand?.height, TimelineGraphBand.height,
                       "…and the row is exactly as tall: a filter is not a resize")
        XCTAssertNotEqual(before.graphBand, after.graphBand)
    }

    // MARK: - Colour, which the filter must not touch

    /// **A curve keeps its colour when the curve above it is hidden.**
    ///
    /// The band colours a channel by its position in `Effect.parameters`, deliberately *not* by its
    /// position in the drawn list, because the drawn list reorders the moment a channel starts
    /// animating. A filter shortens the drawn list on every tap, so this stage is where that decision
    /// pays — and where re-deriving the colour from the row index, which is the obvious spelling,
    /// would repaint every remaining curve as the artist unchecks boxes.
    func testHidingAChannelRepaintsNothing() throws {
        let manager = bandManager()
        let before = manager.graphBandContent?.channels ?? []
        XCTAssertEqual(before.map(\.descriptorIndex), [0, 1])

        manager.setGraphChannels([brightnessID], visible: false)
        let after = try XCTUnwrap(manager.graphBandContent?.channels.first)
        XCTAssertEqual(after.parameterID, contrastID)
        XCTAssertEqual(after.descriptorIndex, 1,
                       "It is still descriptor 1 though it is now the only curve drawn")
        XCTAssertEqual(TimelineGraphBand.colour(forDescriptorIndex: after.descriptorIndex),
                       TimelineGraphBand.colour(forDescriptorIndex: 1))
        XCTAssertNotEqual(TimelineGraphBand.colour(forDescriptorIndex: 1),
                          TimelineGraphBand.colour(forDescriptorIndex: 0),
                          "PREMISE: the two indices are different colours, or this proves nothing")

        // And the list's swatch reads the same input, so the popup and the band cannot disagree.
        let rows = (manager.graphChannelGroups ?? []).flatMap(\.rows)
        XCTAssertEqual(rows.map(\.descriptorIndex), [0, 1])
    }

    // MARK: - Stale ids

    /// **The filter can only ever subtract**, which is the invariant §11.5 reduces to: the drawn
    /// channels are always a subsequence of the strict predicate's answer, whatever the filter holds.
    /// A hidden id that names nothing hides nothing, and no id can put a channel *back* that
    /// `isAnimated` refused.
    func testTheFilterOnlySubtractsWhateverIdsItHolds() {
        let manager = bandManager()
        let all = channels(manager).map(\.parameterID)

        for hidden in [Set<String>(), ["blur.radius"], [brightnessID],
                       [brightnessID, "levels.gamma"], Set(all), ["levels.gamma", "nonsense"]] {
            let drawn = TimelineGraphChannelList.visible(channels(manager), hidden: hidden)
                .map(\.parameterID)
            XCTAssertEqual(drawn, all.filter { !hidden.contains($0) },
                           "\(hidden): a filter is a subsequence, never an addition")
        }
    }

    /// **A stale id cannot be stored in the first place** — `setting` prunes to what the band is
    /// listing, so an id for a grade the layer no longer has never enters the set. Belt and braces
    /// over the subtraction rule above, and the reason the filter cannot grow without bound while
    /// the artist edits.
    func testAnIdTheBandIsNotListingIsNotStored() {
        let manager = bandManager()
        let filter = TimelineGraphChannelList.Filter.none
            .setting(["blur.radius", brightnessID], visible: false,
                     on: target(manager), listed: channels(manager).map(\.parameterID))
        XCTAssertEqual(filter.hidden, [brightnessID], "`blur.radius` is on no list this band offers")
    }

    /// **The filter lives exactly as long as the band it was made on** — the two halves of that one
    /// sentence, which is what stops one band's decision being applied to a list the artist has not
    /// seen.
    func testTheFilterDiesWithTheBandItWasMadeOn() {
        let manager = bandManager()
        manager.setGraphChannels([brightnessID], visible: false)
        XCTAssertEqual(drawnIDs(manager), [contrastID])

        manager.currentLayerIndex = 0
        XCTAssertEqual(manager.graphChannelFilter.hidden(on: .layer(id: manager.layers[0].id)), [],
                       "Another band starts from everything visible")
        manager.currentLayerIndex = gradeIndex
        XCTAssertEqual(drawnIDs(manager), [contrastID],
                       "…and coming back to the band it was made on restores it — same band, same list")

        manager.isGraphEditorOpen = false
        XCTAssertEqual(manager.graphChannelFilter, .none,
                       "Closing the editor drops it: §11.5's transience, in the one place it cannot "
                       + "be bypassed")
        manager.isGraphEditorOpen = true
        XCTAssertEqual(drawnIDs(manager), [brightnessID, contrastID])
    }

    /// With the band closed there is no band to filter, so a toggle is a no-op rather than a filter
    /// waiting for a surface that is not on screen.
    func testTogglingWithTheBandClosedChangesNothing() {
        let manager = bandManager()
        manager.isGraphEditorOpen = false
        manager.setGraphChannels([brightnessID], visible: false)
        XCTAssertEqual(manager.graphChannelFilter, .none)
        XCTAssertFalse(manager.graphBandHasHiddenChannels)
        XCTAssertNil(manager.graphChannelGroups)
    }
}
