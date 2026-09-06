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
/// Several of the tests below exist because the thing they check is a decision that looks arbitrary
/// from inside the code and would be "tidied" away by the next reader: the list is built from the
/// **loose** membership predicate and carries the strict one per row (which is the opposite of what it
/// did until 2026-08-30 — see
/// `testTheListsRowsAreEveryCurveAndEachRowSaysWhetherItIsAnAnimation`), the filter is applied
/// **before** the layout key rather than at
/// draw time, a channel's colour survives its neighbour being hidden, a group's mixed box resolves
/// **upward**, and the group's *name* is read at the popup rather than carried on the channel — which
/// looks like a detour until an effect whose `displayName` moves relays out the whole timeline.
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
                               contentHeight: 200,
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

    /// **A grade is still one group, and it is no longer the only kind a band can hold.**
    ///
    /// This test was `testEveryBandTodayHasExactlyOneGroupBecauseALayerHasOneGrade` until
    /// KEYFRAMES.md §11.7, and it said so in its own name: §11.5 pinned *"every band today has
    /// exactly one group"* as the premise behind there being no fold, and named the day a second
    /// channel source arrived as the day the assertion changes. The transform channel is that source
    /// — a layer can carry a whole-cel Move and any number of animation groups — so the fold is
    /// built and this keeps only the half that is still true: a **grade** contributes exactly one
    /// group, named by the effect rather than by the descriptor table.
    ///
    /// `PoseBandLogicTests.testABandShowingTwoMoveChannelsHasTwoGroups` is what replaces the other
    /// half.
    func testAGradeContributesExactlyOneGroupNamedByTheEffect() throws {
        let manager = bandManager()
        let groups = try XCTUnwrap(manager.graphChannelGroups)
        XCTAssertEqual(groups.count, 1, "This layer carries a grade and no Move")
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.id, "brightnessContrast")
        XCTAssertEqual(group.name, "Brightness / Contrast",
                       "The group's label is the effect's own name — a group has no descriptor row")
        XCTAssertEqual(group.rows.map(\.parameterID), [brightnessID, contrastID],
                       "…in `Effect.parameters` order, which is the order the band draws them in")
        XCTAssertFalse(group.isCollapsed, "…and the list still comes up expanded")
    }

    /// **The rows are exactly the band's channels, and each row says which of the two predicates it
    /// satisfies.**
    ///
    /// **This assertion was reversed on 2026-08-30 and the reversal is the point.** It used to pin the
    /// rows equal to `listedAnimationChannelIDs` — the strict predicate — on the argument that a flat
    /// line the artist did not author must not be offered a checkbox. What that argument did not weigh
    /// is §11.4's vanishing channel: tapping away a channel's second-to-last key drops it below the
    /// strict predicate, so the whole curve left the band *mid-gesture*, and a band that does not draw
    /// a channel is a band no tap can add a key back to. The band now draws both kinds and dashes the
    /// flat one, so the list lists both and labels them.
    ///
    /// Both predicates are still pinned against the model's own accessors rather than against
    /// literals, which is §2.28's rule and is now doing twice the work it was: membership is
    /// `curvedEffectChannelIDs`, and `isAnimated` is `listedAnimationChannelIDs`.
    func testTheListsRowsAreEveryCurveAndEachRowSaysWhetherItIsAnAnimation() throws {
        let manager = bandManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.0), (6, 1.0)]))

        let rows = (manager.graphChannelGroups ?? []).flatMap(\.rows)
        XCTAssertEqual(rows.map(\.parameterID), manager.curvedEffectChannelIDs(of: target(manager)),
                       "Every channel carrying a curve is a row, in `Effect.parameters` order")
        XCTAssertEqual(rows.map(\.parameterID), [brightnessID, contrastID])
        XCTAssertEqual(rows.filter(\.isAnimated).map(\.parameterID),
                       manager.listedAnimationChannelIDs(of: target(manager)),
                       "…and the strict predicate is what the flag carries, not what the list omits")
        XCTAssertEqual(rows.map(\.isAnimated), [true, false],
                       "A curve keyed twice at one value is in force and is not an animation")

        XCTAssertEqual(drawnIDs(manager), [brightnessID, contrastID],
                       "The band draws both; the dash is what tells them apart")
        XCTAssertEqual(TimelineGraphBand.encode(try XCTUnwrap(manager.graphBandContent)),
                       "brightnessContrast.brightness:0,10|brightnessContrast.contrast~0,6",
                       "`~` for a flat channel, `:` for an animation — the tier that cannot see the dash")
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
    func testTheFilterMovesTheBandAndNoOtherPartOfTheKey() throws {
        let manager = bandManager()
        let before = key(manager)
        manager.setGraphChannels([brightnessID], visible: false)
        let after = key(manager)

        XCTAssertEqual(before.trackMarkers, after.trackMarkers,
                       "A hidden curve is still a keyed channel — the diamonds do not move")
        XCTAssertEqual(before.tracks, after.tracks, "…and no cel moved")
        // **The two heights measured either side of the filter**, rather than one of them against
        // `TimelineGraphBand.height`: comparing the after-height to the constant can only fail if
        // `graphBandExpansion` stopped using the constant, which no filter change can cause. What
        // "a filter is not a resize" actually forbids is a band whose height follows its channel
        // count — a curve each, say, or a band that shrinks to what is left — and that is a
        // difference between these two, not between either and a literal.
        let beforeBand = try XCTUnwrap(before.graphBand)
        let afterBand = try XCTUnwrap(after.graphBand)
        XCTAssertEqual(afterBand.channels.count, beforeBand.channels.count - 1,
                       "PREMISE: the filter really did take a curve off this band")
        XCTAssertEqual(afterBand.height, beforeBand.height,
                       "…and the row is exactly as tall: a filter is not a resize")
        XCTAssertNotEqual(beforeBand, afterBand)
    }

    /// **Flipping Directional on an animated blur reflows nothing** — the layout key's own rule,
    /// which the channel list is the stage most likely to break.
    ///
    /// `Effect.displayName` is constant per case for twelve of the thirteen effects and **not** for
    /// `.blur`, which answers "Directional Blur" or "Gaussian Blur" off a toggle. So a group name
    /// carried on `TimelineGraphBand.Channel` — the cheap spelling, since the channel is already in
    /// hand — puts a value the band never draws inside `TimelineLayoutKey`, and one tap in the effect
    /// settings bar then costs a full `relayout()`: every row frame, every cel accessibility
    /// identifier, the ruler's per-frame CoreText loop. The name is read at the popup instead
    /// (`TimelineGraphChannelList.groupNames(of:)`), which is the only surface that shows it.
    ///
    /// The blur fixture is the whole point: run this on the brightness/contrast document and it
    /// passes whatever the channel carries, because that effect's name never moves.
    ///
    /// **The layer is given a name, and that is not incidental either.** `setLayerEffect` — which is
    /// where `applyEffectParameterEdit`'s `.storedValue` arm lands — renames an *unnamed* value layer
    /// to its grade's `displayName`, so on a default-named layer this toggle moves the key through
    /// the name column as well and the band's own contribution cannot be seen. `hasCustomName` is
    /// what isolates it, and a named layer is the ordinary case in real work.
    func testFlippingTheDirectionalToggleDoesNotReflowTheTimeline() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        var blur = Effect.Blur()
        blur.radius = 8
        manager.addValueLayer(effect: .blur(blur), name: "Grade")
        manager.currentLayerIndex = gradeIndex
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: "blur.radius",
                                        to: linear([(0, 4.0), (10, 20.0)]))
        manager.isGraphEditorOpen = true

        let gaussian = key(manager)
        XCTAssertEqual(gaussian.graphBand?.channels.map(\.parameterID), ["blur.radius"],
                       "PREMISE: the band is open on an animated blur radius")
        XCTAssertEqual(try XCTUnwrap(manager.graphChannelGroups).first?.name, "Gaussian Blur",
                       "PREMISE: and the list labels the group with the effect's own name")

        blur.isDirectional = true
        manager.setLayerEffect(layerIndex: gradeIndex, to: .blur(blur))

        XCTAssertEqual(try XCTUnwrap(manager.graphChannelGroups).first?.name, "Directional Blur",
                       "PREMISE: the word the artist sees did change — this is the toggle that "
                       + "makes `displayName` inconstant, and the reason it is read at the popup")
        XCTAssertEqual(gaussian, key(manager),
                       "…and the timeline's layout key did not move, so nothing relaid out")
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
        // The index is the whole assertion, because the colour is a pure function of it — so the
        // one thing left to establish is that the two indices are not the same colour anyway. Asking
        // `colour(forDescriptorIndex:)` for `after.descriptorIndex` and for `1` and comparing the two
        // answers would be calling one pure function twice with arguments the line above has just
        // asserted equal, which cannot fail.
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
    ///
    /// **Checked against two independent properties rather than against a re-spelling of the
    /// implementation.** `visible` *is* `channels.filter { !hidden.contains($0.parameterID) }`, so an
    /// expected value written as `all.filter { !hidden.contains($0) }` restates it and proves only
    /// that the predicate is not inverted — which is much less than this test's name promises. What
    /// is asserted instead: the answer is an order-preserving **subsequence** of the unfiltered list,
    /// walked here by two indices and by nothing the implementation shares; and its **length** is
    /// `|all| - |all ∩ hidden|`, set arithmetic rather than a per-element filter, which is the half
    /// that says an id naming nothing on this band takes nothing away from it.
    func testTheFilterOnlySubtractsWhateverIdsItHolds() {
        let manager = bandManager()
        let all = channels(manager).map(\.parameterID)
        XCTAssertEqual(Set(all).count, all.count,
                       "PREMISE: ids are distinct, or the length assertion below means nothing")

        /// Every element of `sub`, in order, somewhere in `whole`. Deliberately not `filter`.
        func isSubsequence(_ sub: [String], of whole: [String]) -> Bool {
            var next = whole.startIndex
            for element in sub {
                guard let found = whole[next...].firstIndex(of: element) else { return false }
                next = whole.index(after: found)
            }
            return true
        }
        XCTAssertFalse(isSubsequence([contrastID, brightnessID], of: all),
                       "PREMISE: the subsequence walk rejects a reorder, not just an addition")

        for hidden in [Set<String>(), ["blur.radius"], [brightnessID],
                       [brightnessID, "levels.gamma"], Set(all), ["levels.gamma", "nonsense"]] {
            let drawn = TimelineGraphChannelList.visible(channels(manager), hidden: hidden)
                .map(\.parameterID)
            XCTAssertTrue(isSubsequence(drawn, of: all),
                          "\(hidden): a filter is a subsequence — nothing added, nothing reordered")
            XCTAssertEqual(drawn.count, all.count - hidden.intersection(Set(all)).count,
                           "\(hidden): it takes away exactly the ids it holds that this band lists, "
                           + "so an id naming nothing here hides nothing")
            // The three together are a complete characterisation and none of them builds the answer:
            // the survivors sit inside `all` in order, none of them is hidden, and there are exactly
            // as many of them as `all` has unhidden ids — so they are the unhidden ids and no other
            // arrangement satisfies all three.
            XCTAssertTrue(drawn.allSatisfy { !hidden.contains($0) },
                          "\(hidden): …and nothing it holds survived into the band")
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

    /// **The popup goes down with the band too, and not only the filter** — the other half of
    /// `isGraphEditorOpen`'s `didSet`, and the one line on this stage that is a workaround for
    /// somebody else's bug.
    ///
    /// `CanvasPresentationModifier` clears the registry from `.onDisappear` and deliberately never
    /// the site's own `isPresented`, so a popover whose host view is destroyed while it is up comes
    /// back by itself when the host returns (BUGS.md). Closing the band deletes
    /// `timeline.graphChannelsButton`, which is the app's first conditionally-rendered host with a
    /// presentation on it — so without this the artist reopens the graph editor and a popup they
    /// closed is sitting there.
    ///
    /// **This is a logic test because it cannot be a UI one.** Measured 2026-08-29 on the simulator:
    /// with the popover up, a tap on the graph editor's toggle is spent dismissing the popover and
    /// never reaches the button, so an XCUITest cannot get the app into the state at all — it closes
    /// the list first, every time, and then closes a band with nothing open on it. That is also why
    /// the flag lives on `CanvasManager` rather than as `@State` in `AnimationTimeline`: a guard in
    /// that file would be pinned by nothing from either tier.
    func testClosingTheEditorTakesTheChannelListDownWithIt() {
        let manager = bandManager()
        manager.isGraphChannelListOpen = true

        manager.isGraphEditorOpen = false
        XCTAssertFalse(manager.isGraphChannelListOpen,
                       "The list is a control of the editor and cannot outlive it")

        manager.isGraphEditorOpen = true
        XCTAssertFalse(manager.isGraphChannelListOpen,
                       "…and reopening the band does not raise it again — that is the bug itself")
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
