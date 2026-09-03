import Foundation

/// **The graph editor's channel list — a filter over the band *and*, since KEYFRAMES.md §11.7, a
/// navigator through it** — §11.5, stage D4, amended.
///
/// This file opened by calling itself *"a filter over the band, not a navigator through it"*, and the
/// owner reversed exactly that: *"in the menu list of animations, clicking on a move item in there
/// should bring up the move box for that move item so you don't need to select it manually again."*
/// So a row now has two jobs, and they are split by **which part of the row the finger lands on**:
///
///   * the **box** is the filter, on a channel row and on a group header alike — unchanged, and the
///     only thing that changes what the band draws;
///   * the **row body** is the subject: tapping it raises the Move box over the drawing that channel
///     moves (`Row.navigation`), which is the ruling;
///   * the **chevron** on a group header is the fold (`Fold`), which is §11.5's deferred control.
///
/// **A grade's channel has no subject and its body is therefore inert.** That is one rule rather than
/// two — "the box filters, the row reveals what it is about" — and a Brightness curve has nothing to
/// reveal, because the surface an artist edits it on is the settings bar and it is already there. The
/// alternative considered and rejected was letting the body toggle the box wherever there was nothing
/// to navigate to, which would make one gesture mean two different things depending on a property of
/// the row the artist cannot see.
///
/// The owner: *"just a button option in the graph editor which brings up a scrollable popup menu,
/// which is basically an include or exclude checkmark box for each animation. Animations may have
/// multiple values being modified at once (like transform x and y), so those should have a drop down
/// so they are visible or invisible like a whole. This is basically like the hide/show layers and
/// layer groups."*
///
/// So the band keeps showing **every** channel that carries a curve and this list takes some of them
/// away again. It never adds one: `visible(_:hidden:)` is a `filter`, so whatever a stale id says, the
/// answer is always a subset of `TimelineGraphBand.allChannels(effect:tracks:)`.
///
/// **Membership was the strict `isAnimated` predicate until 2026-08-30 and is now the loose one**, with
/// the strict answer carried per row as `Row.isAnimated` — §11.4's vanishing channel, and the amendment
/// to §11.5 it forced. The band draws a channel that is *not* an animation as a dashed flat line, so
/// the list has to list it: the filter can hide a channel, and a channel hidden while it was an
/// animation must not reappear the moment a key is tapped away from it, nor become unreachable.
///
/// **Why this is a type and not arithmetic inside `AnimationTimeline`.** The same reason
/// `TimelineGraphBand` and `TimelineKeyMarkers` are types: `Views/AnimationTimeline.swift` is **not**
/// compiled into `PaintSoftwareUITests`, so grouping written there would be pinned by nothing. The
/// SwiftUI in that file keeps the rows and the checkmarks; every decision about *what* the rows are
/// is here.
///
/// **What the id format does and does not buy.** §11.5 says grouping falls out of it for free, and
/// mechanically that is true — `EffectParameter.id` is `"<case>.<field>"` and `groupID(of:)` is the
/// text before the dot, so no second table is needed. What it did not say, and what was true until
/// §11.7, is the consequence: one band was one layer, one layer was one grade, and one grade was one
/// prefix, so **every band had exactly one group** — which was the reason there was no fold.
///
/// **The transform channel is the second channel source that premise was waiting for**, so
/// `testEveryBandTodayHasExactlyOneGroupBecauseALayerHasOneGrade` is now
/// `testAGradeContributesExactlyOneGroupNamedByTheEffect` beside
/// `PoseBandLogicTests.testABandShowingTwoMoveChannelsHasTwoGroups`, and the fold is built. The
/// scoping objection §11.5
/// raised against it — that collapse state keyed by effect case *"would follow the artist to a layer
/// they never folded it on"* — is **answered rather than waived**: `Fold` carries the
/// `KeyframeTarget` it was authored on exactly as `Filter` does, and `isGraphEditorOpen`'s `didSet`
/// drops both.
///
/// **A pose channel's group prefix is minted rather than taken from `TransformChannelID.id`**, and
/// that is a repair rather than a preference — see `PoseChannelID`, which carries the arithmetic.
/// `"group.<uuid>"` already contains a dot, so appending a component would make every animation
/// group on a cel share the prefix `"group"` and one tap on a header would switch off channels
/// belonging to drawings the artist never picked.
///
/// **The group's *name* is the one thing the id format cannot supply**, and §11.5's "display names
/// come from the descriptor table" is only true of the channels. `EffectParameter.name` is a field
/// label ("Radius"); a group has no descriptor and so no name of its own, so `groupNames(of:)` reads
/// the effect's own `displayName` — the words the artist picked the grade by. Deriving "Chromatic
/// Aberration" from `chromaticAberration` by splitting camel case would work for twelve of the
/// thirteen and spell `hsvShift` "Hsv Shift".
///
/// **It is read here and not carried on the channel**, which is the one thing about this file that
/// looks like a detour and is not. A `TimelineGraphBand.Channel` is inside the layout key, and
/// `Effect.displayName` is not constant per case — `.blur` answers "Directional Blur" or "Gaussian
/// Blur" off a toggle no curve draws — so a name on the channel makes an effect-settings tap relayout
/// the whole timeline for a band that did not change. This list is SwiftUI, is built only while the
/// popup is up, and already has the effect in hand: `graphChannelGroups` calls `storedEffect(of:)` to
/// get the channels at all, so reading the name costs one walk of at most thirteen descriptors on a
/// surface that is not on screen the rest of the time.
enum TimelineGraphChannelList {

    // MARK: - What the artist has switched off

    /// **The hidden channels, and the band they were hidden on.**
    ///
    /// Transient view state, §11.5: it filters what is drawn, has no meaning with the editor closed,
    /// and persisting it would put a field in the manifest that changes no pixel. Nothing here
    /// reaches `LayerManifest`, `FolderManifest` or any codec.
    ///
    /// **The scope field is what makes stale ids impossible rather than merely harmless.** Hiding is
    /// by `EffectParameter.id`, and an id outsurvives the thing it names: change a layer's grade from
    /// Blur to Levels and `"blur.radius"` addresses nothing. Filtering alone already refuses to
    /// *resurrect* anything — it can only subtract — but a set with no scope would also apply to the
    /// **next** layer the band opens on, which is a different band's decision applied to a list the
    /// artist has not seen. So the filter carries the `KeyframeTarget` it was authored against and
    /// answers `[]` for any other, and `CanvasManager.isGraphEditorOpen` clears it on close. One
    /// sentence: **the filter lives exactly as long as the band it was made on.**
    struct Filter: Equatable {
        /// Nothing hidden, no band. The state every document starts and ends in.
        static let none = Filter(target: nil, hidden: [])

        /// The band this was authored on, or nil when nothing is hidden.
        let target: KeyframeTarget?
        /// `EffectParameter.id`s. Always a subset of what that band listed at the last toggle —
        /// `setting` prunes — so the set cannot accumulate ids from grades the layer no longer has.
        let hidden: Set<String>

        /// The hidden ids **as they apply to `target`**: this filter's set on the band it was made
        /// on, and nothing at all on any other. A band that opens on another layer starts from
        /// everything visible, which is the state the artist expects from a surface whose whole
        /// premise is that it shows every animated channel.
        func hidden(on target: KeyframeTarget) -> Set<String> {
            self.target == target ? hidden : []
        }

        /// **One row's box, or a whole group's, flipped.**
        ///
        /// `listed` is the band's current channel ids and is the prune: anything not on it is
        /// dropped, so a grade swap cannot leave `"blur.radius"` sitting in the set waiting for a
        /// Blur to come back. `ids` is one channel for a row's box and the group's whole membership
        /// for a group's — the owner's *"visible or invisible like a whole"*, which is one call with
        /// a longer array rather than a second code path.
        ///
        /// Returns `.none` rather than an empty-but-scoped filter when nothing is left hidden, so
        /// "is anything filtered" is `!= .none` and there is one spelling of the neutral state.
        func setting(_ ids: [String], visible: Bool, on target: KeyframeTarget,
                     listed: [String]) -> Filter {
            let listedSet = Set(listed)
            var next = hidden(on: target).intersection(listedSet)
            for id in ids where listedSet.contains(id) {
                if visible { next.remove(id) } else { next.insert(id) }
            }
            return next.isEmpty ? .none : Filter(target: target, hidden: next)
        }
    }

    // MARK: - What the artist has folded shut

    /// **The collapsed groups, and the band they were collapsed on** — KEYFRAMES.md §11.7's fold.
    ///
    /// `Filter`'s twin in every respect, deliberately: the same scope field for the same reason, the
    /// same `.none` neutral state so "is anything folded" has one spelling, and the same pruning
    /// against what the band currently lists so a grade swap cannot leave `"blur"` folded waiting for
    /// a Blur to come back.
    ///
    /// **What it is not is a second filter.** A folded group's channels are still drawn — the band
    /// reads `Filter` and has never heard of this — so folding is a way to get thirty rows of a long
    /// list out of the way, which is the owner's *"scrollable popup menu"* problem, and hiding is a
    /// way to get a curve off the band. `testFoldingAGroupDrawsTheSameBand` is the pin, and it is the
    /// assertion that would go red if a later session routed one through the other.
    struct Fold: Equatable {
        /// Nothing folded, no band.
        static let none = Fold(target: nil, collapsed: [])

        let target: KeyframeTarget?
        /// Group ids — `groupID(ofParameterID:)`'s answers, not parameter ids.
        let collapsed: Set<String>

        /// The collapsed ids **as they apply to `target`**, `Filter.hidden(on:)`'s rule verbatim: a
        /// band that opens on another layer starts fully expanded, which is the state §11.5 says the
        /// expanded default exists to guarantee.
        func collapsed(on target: KeyframeTarget) -> Set<String> {
            self.target == target ? collapsed : []
        }

        /// One group's chevron, flipped. `listed` is the band's current group ids and is the prune.
        func setting(_ id: String, collapsed shut: Bool, on target: KeyframeTarget,
                     listed: [String]) -> Fold {
            let listedSet = Set(listed)
            var next = collapsed(on: target).intersection(listedSet)
            guard listedSet.contains(id) else {
                return next.isEmpty ? .none : Fold(target: target, collapsed: next)
            }
            if shut { next.insert(id) } else { next.remove(id) }
            return next.isEmpty ? .none : Fold(target: target, collapsed: next)
        }
    }

    // MARK: - The rows

    /// One channel's row: a checkbox, a name, and the swatch that ties it to a curve.
    struct Row: Equatable {
        /// `EffectParameter.id` — what the box toggles and what a UI test names it by.
        let parameterID: String
        /// `EffectParameter.name`, the artist-facing label, carried on the channel by D2 so this
        /// stage needs no second walk of `Effect.parameters`.
        let name: String
        /// **The channel's position in `Effect.parameters`, passed straight through.** The list's
        /// swatch must be the colour the band draws that curve in, and the band takes its colour from
        /// the *descriptor* index rather than from the drawn list's — so a row keeps its swatch when
        /// a channel above it is hidden. Re-deriving the colour from the row's position here would
        /// undo that on this surface only, and the two would disagree about which curve is which.
        let descriptorIndex: Int
        let isVisible: Bool
        /// **Whether the band draws this one as a curve or as a dashed flat line** —
        /// `TimelineGraphBand.Channel.isAnimated`, passed straight through.
        ///
        /// The list shows both because the band draws both (§11.4, settled 2026-08-30), and it has to
        /// show both for a reason the band alone does not supply: the filter can hide a channel, and a
        /// channel hidden while it was an animation must not reappear the moment a key is tapped away
        /// from it. A row the artist cannot see is a row they cannot switch back on.
        let isAnimated: Bool
        /// **What tapping this row's body raises** — §11.7's second ruling, nil for a channel that
        /// has no subject to raise.
        ///
        /// The channel rather than the parameter: all six of a pose channel's rows name the same
        /// Move, because they are six readings of one `TransformTrack`, so tapping "Rotation" and
        /// tapping "X" put up the same box. That is the right answer and not a shortcut — the owner
        /// asked for *"the move box for that move item"*, and the move item is the channel.
        let navigation: PoseChannelID?

        init(parameterID: String, name: String, descriptorIndex: Int, isVisible: Bool,
             isAnimated: Bool, navigation: PoseChannelID? = nil) {
            self.parameterID = parameterID
            self.name = name
            self.descriptorIndex = descriptorIndex
            self.isVisible = isVisible
            self.isAnimated = isAnimated
            self.navigation = navigation
        }
    }

    /// One group: every channel sharing an id prefix, with the whole-group box the owner asked for.
    struct Group: Equatable, Identifiable {
        /// The text before the dot — the effect case. Also the accessibility identifier's suffix.
        let id: String
        /// The artist-facing label for the group. See the type's doc: not from the descriptor table.
        let name: String
        /// In `Effect.parameters` order, which is the order the band draws them in.
        ///
        /// **Always the whole membership, folded or not.** The fold is a property of the group that
        /// the view reads to decide what to lay out; dropping the rows here instead would make
        /// `visibilityAfterToggle` and `isMixed` answer about a subset, so a folded group's box would
        /// stop describing the group.
        let rows: [Row]
        /// **Whether the chevron is shut** — §11.7's fold. A view concern by construction: nothing
        /// the band draws depends on it.
        let isCollapsed: Bool
        /// What tapping the header's body raises — the group's own channel, when every row in it
        /// names one. Nil for a grade, whose header has no subject.
        let navigation: PoseChannelID?

        init(id: String, name: String, rows: [Row], isCollapsed: Bool = false,
             navigation: PoseChannelID? = nil) {
            self.id = id
            self.name = name
            self.rows = rows
            self.isCollapsed = isCollapsed
            self.navigation = navigation
        }

        /// Every channel in the group is drawn — the checked box.
        var isFullyVisible: Bool { rows.allSatisfy(\.isVisible) }
        /// Some are and some are not — the dashed box. False when the group is uniform either way.
        var isMixed: Bool { !isFullyVisible && rows.contains(where: \.isVisible) }

        /// **What one tap on the group's box does.** `!isFullyVisible`, so a *mixed* group resolves
        /// to all-visible first and only a second tap hides it. The alternative — mixed resolving to
        /// hidden — would take away a channel the artist had just switched on, which is the one
        /// outcome a tap on a partly-checked box must not have.
        var visibilityAfterToggle: Bool { !isFullyVisible }
    }

    // MARK: - Grouping, which is one `split` and no table

    /// **The group an id belongs to: the text before the first dot.**
    ///
    /// Total, because a caller must not have to know the format is honoured. An id with no dot is its
    /// own group rather than a crash or an empty string, and a compound id keeps everything after the
    /// first dot in the field half — `EffectParameter.id`'s doc fixes the shape as `"<case>.<field>"`
    /// with the field lower-camel, so the first dot is the only structural one.
    static func groupID(ofParameterID id: String) -> String {
        guard let dot = id.firstIndex(of: ".") else { return id }
        return String(id[id.startIndex..<dot])
    }

    /// **The label for every group one effect can contribute**, by group id.
    ///
    /// A dictionary rather than one string because that is the shape the second channel source needs:
    /// the day a band lists a transform beside a grade, its names are two of these merged, and
    /// nothing above here changes. Today it has exactly one entry for the same reason the list has
    /// exactly one group.
    ///
    /// A group with no entry falls back to its id in `groups(of:hidden:names:)`, so a channel whose
    /// prefix the effect does not address is labelled `"blur"` rather than blank — legible, and
    /// obviously a bug, which is the right pair for a case that should not arise.
    static func groupNames(of effect: Effect?) -> [String: String] {
        guard let effect else { return [:] }
        var names: [String: String] = [:]
        for parameter in effect.parameters {
            names[groupID(ofParameterID: parameter.id)] = effect.displayName
        }
        return names
    }

    /// **The list the popup shows: every channel the band could draw, grouped, with its box's state.**
    ///
    /// Built from the band's *unfiltered* channels, so the rows are exactly the band's membership, and
    /// hiding a channel removes it from the band without removing it from the list it is switched off
    /// in. A list that dropped its own hidden rows would be a one-way door.
    ///
    /// Groups and rows both keep `Effect.parameters` order: a group is ordered by where its first
    /// channel appears, so the list cannot reshuffle itself when a channel starts animating.
    static func groups(of channels: [TimelineGraphBand.Channel],
                       hidden: Set<String>,
                       names: [String: String],
                       collapsed: Set<String> = []) -> [Group] {
        var order: [String] = []
        var rows: [String: [Row]] = [:]
        for channel in channels {
            let group = groupID(ofParameterID: channel.parameterID)
            if rows[group] == nil { order.append(group) }
            rows[group, default: []].append(
                Row(parameterID: channel.parameterID,
                    name: channel.name,
                    descriptorIndex: channel.descriptorIndex,
                    isVisible: !hidden.contains(channel.parameterID),
                    isAnimated: channel.isAnimated,
                    navigation: Self.navigation(forParameterID: channel.parameterID)))
        }
        return order.map { id in
            Group(id: id, name: names[id] ?? id, rows: rows[id] ?? [],
                  isCollapsed: collapsed.contains(id),
                  navigation: Self.navigation(forGroupID: id))
        }
    }

    /// **What a row's body raises, or nil** — the resolution in one place, so the row and its group
    /// header cannot disagree about whether a channel has a subject.
    ///
    /// Resolved from the id rather than carried on the channel, `groupNames(of:)`'s rule: a
    /// `TimelineGraphBand.Channel` is inside `TimelineLayoutKey`, so a field the band never draws
    /// with would gate `relayout()` for nothing.
    static func navigation(forParameterID id: String) -> PoseChannelID? {
        navigation(forGroupID: groupID(ofParameterID: id))
    }

    static func navigation(forGroupID id: String) -> PoseChannelID? {
        guard let channel = PoseChannelID(groupID: id), channel.raisesMoveBox else { return nil }
        return channel
    }

    /// **The channels the band actually draws.**
    ///
    /// A `filter`, which is the whole of §11.5's ruling expressed as code: the answer is a subsequence
    /// of `allChannels`, so a hidden id that names nothing hides nothing and no id in this set can put
    /// a channel *back* that the band was not going to draw. Order is preserved, which keeps the band
    /// drawing in `Effect.parameters` order — and every channel keeps its own `descriptorIndex`, so
    /// its colour does not move when the channel above it is switched off, and its `isAnimated`, so
    /// hiding a neighbour cannot turn a dashed line solid.
    static func visible(_ channels: [TimelineGraphBand.Channel],
                        hidden: Set<String>) -> [TimelineGraphBand.Channel] {
        hidden.isEmpty ? channels : channels.filter { !hidden.contains($0.parameterID) }
    }
}

extension CanvasManager {

    /// **The rows the channel list shows for the band that is open**, or nil when it is closed.
    ///
    /// The band's own membership, unfiltered — `graphBandContent` is the filtered half, and the two
    /// walk `Effect.parameters` from the same `TimelineGraphBand.channels(effect:tracks:)` call so
    /// they cannot disagree about what a channel is. This one is read only while the popup is up.
    var graphChannelGroups: [TimelineGraphChannelList.Group]? {
        guard let expansion = graphBandExpansion,
              let target = keyframeTarget(layerIndex: expansion.layerIndex)
        else { return nil }
        let channels = graphBandListing(of: target).channels
        // **Two name tables merged, which is the shape `groupNames(of:)`' doc predicted**: *"the day
        // a band lists a transform beside a grade, its names are two of these merged, and nothing
        // above here changes."* It is that day.
        var names = TimelineGraphChannelList.groupNames(of: storedEffect(of: target))
        for (id, name) in TimelineGraphBand.poseGroupNames(poseSources(of: target)) {
            names[id] = name
        }
        return TimelineGraphChannelList.groups(of: channels,
                                               hidden: graphChannelFilter.hidden(on: target),
                                               names: names,
                                               collapsed: graphChannelFold.collapsed(on: target))
    }

    /// Whether anything is switched off on the band that is open.
    ///
    /// **The channel list's button is tinted from this**, for `graphEditorButton`'s reason one stage
    /// earlier: a filter with no visible sign of itself is a band that looks broken. It is also the
    /// only signal an artist who hid every channel has — the band itself is then correctly blank.
    var graphBandHasHiddenChannels: Bool {
        (graphBandContent?.hiddenCount ?? 0) > 0
    }

    /// **One row's box, or one group's, flipped on the band that is open.** No-op with the band
    /// closed, which is what stops a filter existing for a surface that is not on screen.
    func setGraphChannels(_ ids: [String], visible: Bool) {
        guard let expansion = graphBandExpansion,
              let target = keyframeTarget(layerIndex: expansion.layerIndex)
        else { return }
        let listed = graphBandListing(of: target).channels.map(\.parameterID)
        graphChannelFilter = graphChannelFilter.setting(ids, visible: visible,
                                                        on: target, listed: listed)
    }

    /// **One group's chevron, flipped on the band that is open** — §11.7's fold, and
    /// `setGraphChannels`' twin down to the no-op with the band closed.
    func setGraphGroupCollapsed(_ id: String, collapsed: Bool) {
        guard let expansion = graphBandExpansion,
              let target = keyframeTarget(layerIndex: expansion.layerIndex)
        else { return }
        let listed = graphBandListing(of: target).channels
            .map { TimelineGraphChannelList.groupID(ofParameterID: $0.parameterID) }
        graphChannelFold = graphChannelFold.setting(id, collapsed: collapsed,
                                                    on: target, listed: listed)
    }
}
