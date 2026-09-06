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
        return recolorReason ?? applyBrushReason
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
