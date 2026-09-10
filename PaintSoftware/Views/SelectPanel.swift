import SwiftUI

/// The Select tool's bottom-docked bar (Procreate reference: mode tabs across the top of the bar,
/// action icons across the bottom), shown whenever the Select tool is engaged — see `DrawingView`,
/// which docks this near the bottom the same way `MoveTransformBottomBar` docks for Move. The action
/// row (Duplicate/Fill/Recolour/Brush/Clear/Deselect) is disabled until a selection actually exists; the
/// mode tabs and the outside-interaction toggle are available immediately so a mode can be picked
/// before the first selection is drawn.
///
/// **Brush is BRUSH.md §2.10's apply-to-existing verb** — every stroke the loop caught is re-pointed
/// at the brush now selected, which is the only door in the app to *"the brush I just edited, on the
/// line I already drew"*. It sits beside Recolour because the two are the pair that push the current
/// tool settings onto ink that already exists, and it is captioned in one word for the reason
/// Recolour is: six tabs now share the 360 pt bar.
///
/// **Recolour sits beside Fill** rather than at the end of the row, because the two are the pair
/// that apply the currently picked colour and reading them together is what tells them apart. It is
/// captioned in one word for a plain layout reason: five tabs share a 360 pt bar, so 72 pt each, and
/// "Duplicate" was already the longest caption `.caption2` had to fit.
///
/// **It is the one action here that can refuse**, and it says why rather than going quietly grey —
/// `CanvasManager.recolorUnavailableReason`, the rule and the voice `MoveTransformBottomBar` states
/// for Mirror. At most one caption is ever on screen at the foot of the bar: the refusal replaces the
/// "draw a selection" hint rather than stacking under it.
///
/// **"What the loop catches" sits directly above the action row** (TODO item (23)), because that row
/// is what obeys it: Move — reached from the toolbar, not from here — Recolour and Brush all read
/// `CanvasManager.selectionMembership`, so the artist should be able to read the rule and the buttons
/// in one glance. It is above rather than below because it is chosen *first*: the panel's order is
/// how you select (the mode tabs), what the loop then catches, and what to do with it.
struct SelectPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    private var hasSelection: Bool { canvasManager.selection != nil }

    /// Why Change Colour is off, or nil. Read once per body pass and used twice — to gate the button
    /// and to caption it — so the two can never disagree.
    private var recolorReason: String? { canvasManager.recolorUnavailableReason }

    /// Why Apply Brush is off, or nil — read once and used twice, exactly as `recolorReason` is.
    /// BRUSH.md §2.10's verb refuses on the same cels a recolour does, so today these two are never
    /// independently non-nil; reading both is what keeps that a fact rather than an assumption.
    private var applyBrushReason: String? { canvasManager.applyBrushUnavailableReason }

    /// **Three bands, not six** — TODO item (49), the owner: *"too tall and obstructs your view. Make
    /// all of them wider and flatter."* At `BottomDock.preferredWidth` the mode tabs sit beside the
    /// membership picker and the tolerance slider is one line instead of two; the panel's order —
    /// how you select, what the loop then catches, what to do with it — is unchanged, it is just
    /// read left-to-right in the first band instead of top-to-bottom over three.
    ///
    /// **Four since TODO (21)'s membership editing**, and the new one obeys item (49) rather than
    /// relaxing it: `animationGroupBand` is one flat row whose destinations scroll sideways, so it
    /// costs the panel the same height on a document with one animation group and on one with six.
    /// It sits between the loop rule and the action row because it is a *fourth* thing to do with the
    /// loop rather than a rule the action row obeys.
    var body: some View {
        VStack(spacing: 0) {
            if canvasManager.selectionMode == .automatic {
                HStack(spacing: 12) {
                    Text("Tolerance: \(Int(canvasManager.magicWandTolerance * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                        .fixedSize()
                    Slider(value: $canvasManager.magicWandTolerance, in: 0.02...1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(SelectionMode.allCases) { mode in
                        modeTab(mode)
                    }
                }
                .fixedSize()

                // **A height as well as a width, and that is not tidiness.** A `Rectangle` given
                // only a width is greedy in the other axis, so this one grew to fill the screen and
                // took the whole panel with it — a card 1,580 points tall over the artwork, which
                // every assertion about the dock's *bottom* edge stayed green through.
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 48)

                membershipPicker
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            divider

            animationGroupBand

            HStack(spacing: 0) {
                actionTab(icon: "plus.square.on.square", title: "Duplicate") { canvasManager.beginDuplicate() }
                    .accessibilityIdentifier("selectPanel.duplicateButton")
                actionTab(icon: "paintbrush.fill", title: "Fill") { canvasManager.fillSelection() }
                    .accessibilityIdentifier("selectPanel.fillButton")
                actionTab(icon: "paintpalette.fill", title: "Recolour",
                          enabled: recolorReason == nil) { canvasManager.recolorSelection() }
                    .accessibilityIdentifier("selectPanel.recolorButton")
                actionTab(icon: "paintbrush.pointed.fill", title: "Brush",
                          enabled: applyBrushReason == nil) { canvasManager.applyBrushToSelection() }
                    .accessibilityIdentifier("selectPanel.applyBrushButton")
                actionTab(icon: "xmark.square", title: "Clear") { canvasManager.clearSelectionPixels() }
                    .accessibilityIdentifier("selectPanel.clearButton")
                actionTab(icon: "rectangle.badge.xmark", title: "Deselect") { canvasManager.deselect() }
                    .accessibilityIdentifier("selectPanel.deselectButton")
            }
            .padding(.vertical, 8)

            divider

            // A plain Button driving the switch look (rather than SwiftUI's native `Toggle`) so tapping
            // is a single reliable gesture end to end — a native Toggle bound through a custom
            // Binding(get:set:) intermittently didn't flip when activated via accessibility (VoiceOver/
            // XCUITest), while every other control in this bar is a Button and taps it consistently.
            Button {
                canvasManager.allowsPaintingOutsideSelection.toggle()
            } label: {
                HStack {
                    Text("Paint Outside Selection")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    switchIndicator
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("selectPanel.allowOutsideToggle")
            .accessibilityAddTraits(canvasManager.allowsPaintingOutsideSelection ? [.isSelected] : [])

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }

    /// **TODO item (23) — "What the loop catches".** `Enclosed · Cut · Touching`, ordered by how much
    /// of the drawing the loop takes, with the shipped rule — Cut — in the middle and selected until
    /// the artist touches it.
    ///
    /// **It moved here from the Move bar rather than being copied here**, which is the owner's ask:
    /// *"i feel like it would be better in select menu because i want it to affect recolour"*
    /// (2026-08-29). One property, one control; the tools that consume a lasso read it.
    ///
    /// **Available with no selection**, like the mode tabs above and unlike the action row, because it
    /// is the rule the *next* loop will answer with — an artist who has to draw a lasso before they
    /// can choose how it behaves has the order backwards.
    ///
    /// **It refuses on a pixel layer and says why** (`selectionMembershipUnavailableReason`), which is
    /// a real limit rather than a policy: every consumer cuts at the selection there and can do
    /// nothing else. Disabled and captioned rather than dropped, so switching layers does not reflow
    /// the bar under a finger.
    ///
    /// Its caption carries the refusal when there is one and otherwise says what the *selected* rule
    /// does, because the difference between the three is invisible until something has already been
    /// moved or recoloured.
    private var membershipPicker: some View {
        let reason = canvasManager.selectionMembershipUnavailableReason
        let shown = canvasManager.displayedSelectionMembership
        return VStack(alignment: .leading, spacing: 4) {
            Text("What the Loop Catches")
                .font(.caption)
                .foregroundColor(.white)

            Picker("What the Loop Catches", selection: Binding(
                get: { shown },
                set: { canvasManager.setSelectionMembership($0) }
            )) {
                ForEach(LassoMembership.allCases) { membership in
                    Text(membership.displayName).tag(membership)
                }
            }
            .pickerStyle(.segmented)
            .disabled(reason != nil)
            .opacity(reason == nil ? 1 : 0.45)
            .accessibilityIdentifier("selectPanel.membershipPicker")

            Text(reason ?? shown.selectionExplanation)
                .font(.caption2)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("selectPanel.membershipCaption")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 6)
    }

    /// **TODO (21) — "Animation Group": add, remove, and move a selection between animated groups.**
    ///
    /// **It lives here because all three operations act on a selection**, which is the owner's own
    /// framing — *"the ability to add new selections to an animation group … and remove selections
    /// from groups"* — and it is the same argument §5.26 made for moving the membership picker into
    /// this panel: one property, one control, in the panel whose subject is the loop. The Move bar was
    /// the alternative and is wrong twice over: a membership edit is not a transform, and `DrawingView`
    /// hides this panel for exactly as long as a piece floats, so the two controls are never on screen
    /// together and an artist refused by §2.29 would have had to put the piece down to find the fix.
    ///
    /// **One flat band, not a third stack of rows** — the owner on item (49): *"too tall and obstructs
    /// your view. Make all of them wider and flatter."* The readout is two `.caption`-sized lines in a
    /// `fixedSize` column on the left and the destinations scroll horizontally beside it, so the band
    /// costs one row however many groups the document has.
    ///
    /// **Chips rather than a `Picker` or a `Menu`, and each alternative fails on something real.** A
    /// segmented `Picker` needs the current value to be one of its segments and this one can honestly
    /// be *Mixed* — a loop may hold ink from two groups, and the edit is still perfectly well defined
    /// for it. A `Menu` is a system presentation over a live canvas, which is the family
    /// MENU_PRESENTATION_CENSUS.md found seven defects in, and it would hide every destination behind
    /// a tap for no gain at the two-or-three groups a document actually has.
    ///
    /// **The readout is a *value*, not just a label.** `selectionAnimationGroupName` resolves what the
    /// loop has caught, so an XCUITest asserting on it goes red if the control stops resolving —
    /// whereas an `exists` assertion on a chip would stay green against a feature that had been
    /// deleted from underneath it.
    private var animationGroupBand: some View {
        let reason = canvasManager.animationGroupEditUnavailableReason
        let live = reason == nil && hasSelection
        // Read once and used for the readout and for every chip's outline, so the sentence and the
        // ring can never disagree — `recolorReason`'s rule one property up. It is memoized behind
        // three gates (`selectionAnimationGroup`), so reading it here rather than per chip costs one
        // struct comparison a body pass on a document with no animation groups at all.
        let current = canvasManager.selectionAnimationGroup
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Animation Group")
                    .font(.caption)
                    .foregroundColor(.white)
                Text(canvasManager.selectionAnimationGroupName)
                    .font(.caption2)
                    .foregroundColor(live ? .gray : .white.opacity(0.3))
                    .accessibilityIdentifier("selectPanel.animationGroupReadout")
                    .accessibilityValue(canvasManager.selectionAnimationGroupName)
            }
            .fixedSize()

            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 36)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    groupChip(title: "No Group", tint: nil, enabled: live,
                              isCurrent: live && current == .untagged,
                              identifier: "selectPanel.animationGroup.none") {
                        canvasManager.setAnimationGroupOfSelection(.none)
                    }
                    ForEach(Array(canvasManager.animationGroups.enumerated()), id: \.element.id) { index, group in
                        groupChip(title: group.displayName, tint: Color(group.tagColor.uiColor),
                                  enabled: live, isCurrent: live && current == .one(group.id),
                                  identifier: "selectPanel.animationGroup.\(index)") {
                            canvasManager.setAnimationGroupOfSelection(.existing(group.id))
                        }
                    }
                    // **Never current, by construction**: a fresh group is by definition not the one
                    // the loop's ink is already in, which is also why `setAnimationGroupOfSelection`
                    // cannot skip it as a no-op.
                    groupChip(title: "New Group", tint: nil, enabled: live, isCurrent: false,
                              identifier: "selectPanel.animationGroup.new") {
                        canvasManager.setAnimationGroupOfSelection(.newGroup)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// One destination. The tag colour is drawn as a dot rather than as the chip's fill, which is
    /// `AnimationGroup.tagColor`'s own argument — the swatch identifies the group, and a chip filled
    /// with it would be saying two things at once with one colour.
    ///
    /// **`isCurrent` is a ring rather than a fill, and it is not a `Picker`'s selection.** It marks
    /// where the loop's ink *already is*, which is often no chip at all: the loop can hold two groups
    /// at once (`SelectionAnimationGroup.mixed`), and then no chip is ringed and the readout says
    /// Mixed. A control that promised one-of-N would have to lie about that case.
    private func groupChip(title: String, tint: Color?, enabled: Bool, isCurrent: Bool,
                           identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let tint {
                    Circle().fill(tint).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundColor(enabled ? .white : .white.opacity(0.3))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(enabled ? 0.12 : 0.05))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue, lineWidth: isCurrent ? 1.5 : 0))
            .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }

    /// A plain iOS-switch look-alike (capsule track + circular knob) purely for display — the
    /// enclosing Button owns the actual tap handling, see the comment above its call site.
    private var switchIndicator: some View {
        let isOn = canvasManager.allowsPaintingOutsideSelection
        return ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Color.blue : Color.white.opacity(0.25))
            Circle().fill(Color.white).padding(2)
        }
        .frame(width: 51, height: 31)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }

    private func modeTab(_ mode: SelectionMode) -> some View {
        let isActive = canvasManager.selectionMode == mode
        return Button {
            canvasManager.beginSelection(mode: mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.body)
                Text(mode.displayName)
                    .font(.caption2)
            }
            .foregroundColor(isActive ? .blue : .white)
            // A fixed width rather than `maxWidth: .infinity`: the three tabs now share a row with
            // the membership picker instead of a band of their own, so there is no width for them
            // to divide, and ragged tabs would read as three different controls.
            .frame(width: 74)
            .padding(.vertical, 8)
            .background(isActive ? Color.white.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .accessibilityIdentifier("selectPanel.mode.\(mode.rawValue)")
    }

    /// The one line under the bar, or none. Ordered by what the artist is most likely to have just
    /// pressed against: without a selection nothing in the row does anything, so that hint comes
    /// first; with one, a refusal is about the button they can now see is dim.
    private var caption: String? {
        if !hasSelection {
            return "Draw a selection on the canvas with the mode above, or tap Move to transform the whole layer."
        }
        // The animation-group refusal is last because it refuses on exactly the two conditions the
        // other two do — a non-vector cel and an in-between — so with a selection in hand it is never
        // independently non-nil. Reading all three is what keeps that a fact rather than an assumption,
        // which is `applyBrushReason`'s own note one property up.
        return recolorReason ?? applyBrushReason ?? canvasManager.animationGroupEditUnavailableReason
    }

    /// `enabled` is *additional* to `hasSelection`, never instead of it — every tab in this row is
    /// selection-scoped, and an action that is also unavailable for a reason of its own says so in
    /// the caption above.
    private func actionTab(icon: String, title: String, enabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        let live = hasSelection && enabled
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(live ? .white : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .disabled(!live)
    }
}
