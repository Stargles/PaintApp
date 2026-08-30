import Foundation

/// **The graph editor's channel list — a filter over the band, not a navigator through it** —
/// KEYFRAMES.md §11.5, stage D4.
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
/// text before the dot, so no second table is needed. What it does not say is the consequence:
/// **one band is one layer, one layer is one grade, and one grade is one prefix, so every band today
/// has exactly one group.** That is not a reason to drop the grouping — the group row is what
/// carries the owner's *"visible or invisible like a whole"*, and it is the only control that can
/// switch a whole effect off in one tap — but it **is** the reason there is no fold. A chevron over
/// one group folds the only thing in the list, so its only reachable effect today is the empty list
/// §11.5 says the expanded default exists to prevent; and collapse state, being keyed by effect case
/// and scoped to no band, would follow the artist to a layer they never folded it on. The control
/// arrives with the second channel source, when it has something to fold and a reason to be scoped.
/// **`testEveryBandTodayHasExactlyOneGroupBecauseALayerHasOneGrade` is that premise**, so the day it
/// fails is the day to reconsider — which is what putting the decision on this side of the target
/// boundary buys, since `Views/AnimationTimeline.swift` can pin nothing.
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
    }

    /// One group: every channel sharing an id prefix, with the whole-group box the owner asked for.
    struct Group: Equatable, Identifiable {
        /// The text before the dot — the effect case. Also the accessibility identifier's suffix.
        let id: String
        /// The artist-facing label for the group. See the type's doc: not from the descriptor table.
        let name: String
        /// In `Effect.parameters` order, which is the order the band draws them in.
        let rows: [Row]

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
                       names: [String: String]) -> [Group] {
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
                    isAnimated: channel.isAnimated))
        }
        return order.map { Group(id: $0, name: names[$0] ?? $0, rows: rows[$0] ?? []) }
    }

    /// **The channels the band actually draws.**
    ///
    /// A `filter`, which is the whole of §11.5's ruling expressed as code: the answer is a subsequence
    /// of the strict predicate's, so a hidden id that names nothing hides nothing, and no id in this
    /// set can put a channel *back* that `isAnimated` refused. Order is preserved, which keeps the
    /// band drawing in `Effect.parameters` order — and every channel keeps its own
    /// `descriptorIndex`, so its colour does not move when the channel above it is switched off.
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
        let effect = storedEffect(of: target)
        let channels = TimelineGraphBand.allChannels(effect: effect,
                                                     tracks: keyframeState(of: target).tracks)
        return TimelineGraphChannelList.groups(of: channels,
                                               hidden: graphChannelFilter.hidden(on: target),
                                               names: TimelineGraphChannelList.groupNames(of: effect))
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
        let listed = TimelineGraphBand.allChannels(effect: storedEffect(of: target),
                                                   tracks: keyframeState(of: target).tracks)
            .map(\.parameterID)
        graphChannelFilter = graphChannelFilter.setting(ids, visible: visible,
                                                        on: target, listed: listed)
    }
}
