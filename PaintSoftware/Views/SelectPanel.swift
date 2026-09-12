import SwiftUI

/// The Select tool's bottom-docked bar (Procreate reference: mode tabs across the top of the bar,
/// action icons across the bottom), shown whenever the Select tool is engaged — see `DrawingView`,
/// which docks this near the bottom the same way `MoveTransformBottomBar` docks for Move. The action
/// row (Duplicate/Fill/Clear/Deselect) is disabled until a selection actually exists; the mode tabs
/// and the outside-interaction toggle are available immediately so a mode can be picked before the
/// first selection is drawn.
///
/// **The edit band — Colour, Brush, Size, Opacity — is TODO (42)**, the owner's *"a better tool where
/// you can also change the brush type, size, etc. of the strokes inside the selection … all changes
/// able to be seen live in the drawing."* It is the four things the toolbar shows for the *current*
/// brush, applied to ink that already exists, and it is up only while a selection exists: the panel
/// the owner called too tall (TODO (59)) is measured without one, and a band of sliders that is dim
/// with nothing to drive would be height for nothing. Colour is a swatch that opens the app's one
/// colour picker **on the selection's own colour** — *"defaulting to the current color"* — rather
/// than applying the palette's; Size and Opacity are sliders that preview on every tick and commit
/// **one** undo step on lift (`CanvasManager.beginSelectionEdit` / `previewSelectionEdit` /
/// `commitSelectionEdit`); Brush is BRUSH.md §2.10's apply-to-existing verb, one press. Every
/// control reads the selection's rule (`selectionMembership`) with no exception, LASSO_MOVE.md §5.26.
///
/// **The band can refuse, and it says why rather than going quietly grey** —
/// `CanvasManager.selectionEditUnavailableReason`, the rule and the voice `MoveTransformBottomBar`
/// states for Mirror. At most one caption is ever on screen at the foot of the bar: the refusal
/// replaces the "draw a selection" hint rather than stacking under it.
///
/// **"What the loop catches" sits directly above the edit band and the action row** (TODO item
/// (23)), because those are what obey it: Move — reached from the toolbar, not from here — Colour,
/// Brush, Size, Opacity and Clear all read `CanvasManager.selectionMembership`, so the artist should
/// be able to read the rule and the controls in one glance. It is above rather than below because it
/// is chosen *first*: the panel's order is how you select (the mode tabs), what the loop then
/// catches, and what to do with it.
struct SelectPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    private var hasSelection: Bool { canvasManager.selection != nil }

    /// Why Colour, Size and Opacity are off, or nil. Read once per body pass and used twice — to gate
    /// the band and to caption it — so the two can never disagree.
    private var editReason: String? { canvasManager.selectionEditUnavailableReason }

    /// Why Apply Brush is off, or nil — read once and used twice, exactly as `editReason` is.
    /// BRUSH.md §2.10's verb refuses on the same cels the band does, so today these two are never
    /// independently non-nil; reading both is what keeps that a fact rather than an assumption.
    private var applyBrushReason: String? { canvasManager.applyBrushUnavailableReason }

    /// The colour picker over the Colour swatch. Its transitions are the drag's beginning and end —
    /// see `colourSwatch`.
    @State private var showingColourPicker = false

    /// The value under the finger while a slider is being dragged, or nil between drags — so the
    /// slider follows the finger rather than the model's rounded readout, `ChannelScalarControl`'s
    /// own `dragValue`.
    @State private var sizeDrag: Double?
    @State private var opacityDrag: Double?

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
    ///
    /// **Two bands and a caption since TODO (59)**, the owner 2026-09-10: *"the lasso fill menu is
    /// way too tall. Try to compact the height. You can expand it horizontally."* MEASURED on an
    /// iPad Pro 13-inch at `BottomDock.preferredWidth`: **261.5 points before, 162.5 after** — the
    /// panel is now a rule row, an action row and one line of prose, against a card 760 wide.
    /// Three things paid for it and none of them removes a control:
    ///
    ///   * the **paint-outside switch joins the rule row** (`paintOutsideToggle`), where it costs no
    ///     height at all because that row is as tall as the membership column either way — the
    ///     owner's *"takes a whole layer for a switch"*;
    ///   * the **Animation Group band is up only while the graph editor is** — see that band's doc
    ///     for the §2.29 refusals this would otherwise strand, and what was done about them;
    ///   * the **caption brings its own divider**, so a panel with nothing to say ends at the action
    ///     row instead of carrying a rule and 14 points of air.
    var body: some View {
        VStack(spacing: 0) {
            // **The card's own top edge, as a one-point probe** — TODO (59), whose third ask is that
            // this panel be shorter and whose only honest answer is a measured number.
            // `bottomDock.floor` in `DrawingView` marks the column's bottom and has since item (49);
            // this is the other edge, and `OptionsPanelUITests.testTheSelectPanelIsCompact` is the
            // subtraction.
            //
            // **A sibling at the head of the stack, not an `.overlay` on `bottomDockCard`**, which is
            // where it was first written and which MEASURED as breaking the panel outright: an
            // `.accessibilityElement()` inside an overlay on the card made the card a *leaf*, and
            // every control in it — the mode tabs included — stopped resolving, so
            // `testTheSelectPanelsModeTabsShareARowWithTheMembershipPicker` went red for a change
            // that touched no layout. It is CLAUDE.md's "an identifier on a container beats its
            // descendants" reached through a door nobody had checked. One point of height is the
            // price of not going near that again.
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("selectPanel.top")
                .allowsHitTesting(false)

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

            HStack(alignment: .center, spacing: 12) {
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

                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 48)

                paintOutsideToggle
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            divider

            // **Only while the graph editor is open** — TODO (59), the owner: *"the animation group
            // section only really needs to be up when in graph editor."* See `animationGroupBand`'s
            // own doc for what that costs the two §2.29 refusals and how they were repaired.
            if canvasManager.isGraphEditorOpen {
                animationGroupBand
                divider
            }

            // **Up only with a selection** — see the type's doc. `hasSelection` rather than
            // `editReason == nil`, so that on a pixel layer the band is *dim and captioned* rather
            // than absent: an artist who lassoed a raster cel should read why the sliders are off,
            // not wonder where they went.
            if hasSelection {
                editBand
                divider
            }

            HStack(spacing: 0) {
                actionTab(icon: "plus.square.on.square", title: "Duplicate") { canvasManager.beginDuplicate() }
                    .accessibilityIdentifier("selectPanel.duplicateButton")
                actionTab(icon: "paintbrush.fill", title: "Fill") { canvasManager.fillSelection() }
                    .accessibilityIdentifier("selectPanel.fillButton")
                actionTab(icon: "xmark.square", title: "Clear") { canvasManager.clearSelectionPixels() }
                    .accessibilityIdentifier("selectPanel.clearButton")
                actionTab(icon: "rectangle.badge.xmark", title: "Deselect") { canvasManager.deselect() }
                    .accessibilityIdentifier("selectPanel.deselectButton")
            }
            .padding(.vertical, 6)

            if let caption {
                divider

                Text(caption)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - The edit band (TODO (42))

    /// **Colour · Brush · Size · Opacity, one flat row** — the four things the toolbar shows for the
    /// current brush, pointed at the ink the loop caught. Flat rather than stacked for TODO (49)'s and
    /// (59)'s reason: the owner asked for wider and shorter, and at `BottomDock.preferredWidth` a
    /// swatch, a button and two sliders fit one line.
    ///
    /// Every control here is gated on `editLive` and the band is captioned through `caption` when it
    /// is not — the refusal says *why*, in words, which is the rule every other refusing control in
    /// this panel already follows.
    private var editBand: some View {
        let style = canvasManager.selectionStyle
        let live = hasSelection && editReason == nil
        return HStack(alignment: .center, spacing: 12) {
            colourSwatch(style, live: live)

            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 36)

            actionTab(icon: "paintbrush.pointed.fill", title: "Brush",
                      enabled: applyBrushReason == nil) { canvasManager.applyBrushToSelection() }
                .accessibilityIdentifier("selectPanel.applyBrushButton")
                .fixedSize()

            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 36)

            bandSlider("Size", identifier: "selectPanel.sizeSlider",
                       current: style.size.map(Double.init), mixed: style.sizeIsMixed,
                       range: 1...50, drag: $sizeDrag, live: live && style.size != nil,
                       display: { String(format: "%.0f pt", $0) },
                       kind: .size, value: { .size(CGFloat($0)) })

            bandSlider("Opacity", identifier: "selectPanel.opacitySlider",
                       current: style.opacity, mixed: style.opacityIsMixed,
                       range: 0...1, drag: $opacityDrag, live: live && style.opacity != nil,
                       display: { String(format: "%.0f%%", $0 * 100) },
                       kind: .opacity, value: { .opacity($0) })
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// **The swatch opens the picker on the selection's own colour, and the picker's life is the
    /// drag.** `LayerOptionsPanel.valueColorRow`'s shape and `EffectSettingsBar.colorRow`'s: the
    /// picker writes through its binding on every tick of its own sliders, so bracketing each write
    /// would record a step per tick, and instead `onPresent` opens the session and `onDismiss` —
    /// which runs however the popover ends, a canvas touch included — commits it once.
    ///
    /// `supportsOpacity: false`, because the session discards the picked alpha by rule (only the hue
    /// travels; the Opacity slider beside this is the one door to alpha) and a slider whose value is
    /// thrown away is a control that lies.
    ///
    /// **"Mixed" is said in the swatch's own caption**, not in the picker: the picker opens on the
    /// most common colour and shows that; what the artist needs to know before the first tick is
    /// that the loop holds more than one, and that belongs where the swatch is.
    private func colourSwatch(_ style: SelectionStyle, live: Bool) -> some View {
        let enabled = live && style.color != nil
        let shown = style.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        return Button {
            showingColourPicker = true
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(shown ?? Color.white.opacity(0.08))
                    .frame(width: 44, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(enabled ? 0.35 : 0.15), lineWidth: 1))
                Text(style.colorIsMixed ? "Mixed" : "Colour")
                    .font(.caption2)
                    .foregroundColor(enabled ? .white : .white.opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityIdentifier("selectPanel.colourSwatch")
        // The hex rather than the resolved `Color`, for `EffectSettingsBar.colorRow`'s reason: a
        // test can read what the swatch opens on. "Mixed" is a value too — it is what the loop says.
        .accessibilityValue(style.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue).hexString
                                                  + (style.colorIsMixed ? " mixed" : "") } ?? "none")
        .canvasPresentation(.selectionColour, isPresented: $showingColourPicker,
                            canvasManager: canvasManager,
                            onPresent: { canvasManager.beginSelectionEdit(.color) },
                            onDismiss: { canvasManager.commitSelectionEdit() }) {
            // No `.accessibilityIdentifier` on this view — `EffectSettingsBar.colorRow` found live
            // that one here stamps the identifier onto every descendant and hides the panel's own.
            ColorPickerPanel(color: Binding(
                get: {
                    let colour = canvasManager.selectionStyle.color
                    return colour.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .black
                },
                set: { picked in
                    let c = picked.rgbaComponents
                    canvasManager.previewSelectionEdit(.color(CodableColor(red: c.r, green: c.g,
                                                                          blue: c.b, alpha: 1)))
                }), supportsOpacity: false)
                .frame(width: ColorPickerPanel.popoverSize.width,
                       height: ColorPickerPanel.popoverSize.height)
        }
    }

    /// One of the two sliders. Touch-down opens the session, every value write previews, lift
    /// commits — `ChannelScalarControl`'s bracket, with `beginSelectionEdit` for
    /// `beginStructureGesture`. The readout is a **value** (`accessibilityValue`), so a test asserting
    /// on it goes red if the control stops resolving what the loop holds.
    ///
    /// **"Mixed" shows beside the value the slider opens on**, and the first tick makes every caught
    /// element agree — which is what dragging a Size slider over three lines of three widths means,
    /// and what the caption is there to say before it happens.
    private func bandSlider(_ title: String, identifier: String,
                            current: Double?, mixed: Bool, range: ClosedRange<Double>,
                            drag: Binding<Double?>, live: Bool,
                            display: @escaping (Double) -> String,
                            kind: SelectionEditKind,
                            value: @escaping (Double) -> SelectionEditValue) -> some View {
        // The slider is clamped to its range; the readout is not. A line drawn wider than 50 pt
        // reads its true width beside a thumb pinned at the end, rather than a number that is
        // true of no stroke.
        let shown = drag.wrappedValue ?? current.map { min(max($0, range.lowerBound), range.upperBound) }
            ?? range.lowerBound
        let read = drag.wrappedValue ?? current ?? range.lowerBound
        let readout = current == nil ? "—" : (mixed && drag.wrappedValue == nil
                                              ? "Mixed · \(display(read))" : display(read))
        return HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(live ? .white : .white.opacity(0.3))
                .fixedSize()
            Slider(value: Binding(
                get: { shown },
                set: { newValue in
                    drag.wrappedValue = newValue
                    canvasManager.previewSelectionEdit(value(newValue))
                }),
                   in: range,
                   onEditingChanged: { editing in
                       if editing {
                           canvasManager.beginSelectionEdit(kind)
                       } else {
                           canvasManager.commitSelectionEdit()
                           drag.wrappedValue = nil
                       }
                   })
            .tint(.blue)
            .disabled(!live)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(readout)
            Text(readout)
                .font(.caption.monospacedDigit())
                .foregroundColor(live ? .gray : .white.opacity(0.3))
                .frame(minWidth: 52, alignment: .trailing)
                .accessibilityIdentifier("\(identifier).readout")
                .accessibilityValue(readout)
        }
        .frame(maxWidth: .infinity)
    }

    /// **The paint-outside rule, sharing the first row rather than owning one** — TODO (59), the
    /// owner: *"The paint outside selection for example takes a whole layer for a switch."*
    ///
    /// It belongs in the first band on the same argument §5.26 made for moving the membership picker
    /// into this panel: the band is *how the loop behaves* — the mode it is drawn in, what it then
    /// catches, and whether ink may land outside it — and the action row below is what to *do* with
    /// it. So this is the third column of a rule row, not a seventh verb.
    ///
    /// **It costs the panel no height at all**, which is the whole saving: the row's height is set by
    /// the membership column (a label, a segmented control and its caption), and this column is
    /// shorter than that, so the 52 points it used to own below the action row are simply gone.
    ///
    /// A plain Button driving the switch look (rather than SwiftUI's native `Toggle`) so tapping is a
    /// single reliable gesture end to end — a native Toggle bound through a custom
    /// `Binding(get:set:)` intermittently didn't flip when activated via accessibility (VoiceOver/
    /// XCUITest), while every other control in this bar is a Button and taps it consistently.
    private var paintOutsideToggle: some View {
        Button {
            canvasManager.allowsPaintingOutsideSelection.toggle()
        } label: {
            HStack(spacing: 8) {
                // **Wrapped in a fixed column rather than shortened**, because "Paint Outside" alone
                // reads as a verb the button performs; the words that say it is a *rule about the
                // selection* are the ones worth keeping. Two lines of `.caption` are still shorter
                // than the column beside them.
                Text("Paint Outside Selection")
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    // **A `maxWidth`, not a `width`, and not `fixedSize()` on the button** — 96 is
                    // what makes it two lines at `BottomDock.preferredWidth`, and a rigid column
                    // would *overflow* the card at `minimumWidth` rather than give ground. Three
                    // columns do not fit a 360-point card and the membership picker is already
                    // unreadable there (it was before this row gained a third column); giving
                    // rather than overflowing is the difference between cramped and broken.
                    .frame(maxWidth: 96, alignment: .leading)
                switchIndicator
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("selectPanel.allowOutsideToggle")
        .accessibilityAddTraits(canvasManager.allowsPaintingOutsideSelection ? [.isSelected] : [])
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
    ///
    /// ## It is up only while the graph editor is — TODO (59)
    ///
    /// The owner, on their first look at it: *"the animation group section only really needs to be up
    /// when in graph editor."* True of the workflow, and it takes a row and a divider off a panel
    /// they had just called too tall.
    ///
    /// **The cost is that KEYFRAMES §2.29's two refusals pointed here**, and a sentence that names a
    /// control the artist cannot see is worse than no sentence: both said *"…under Select ▸ Animation
    /// Group"*, and with the band hidden that is a dead end rather than an instruction. The repair is
    /// in the sentences, not in an exception to the rule — `CanvasNotice.Kind.message` says *"open
    /// the graph editor, then Select ▸ Animation Group"* now, which is two steps stated instead of
    /// one step implied.
    ///
    /// **The alternatives, and why each is worse.** Showing the band whenever a refusal is *live*
    /// ties a panel's layout to a banner that dismisses itself after 2.6 s — the panel would reflow
    /// under the artist's finger and then reflow back. Showing it whenever the document has any
    /// animation group makes it permanent the moment anyone animates anything, which is the state the
    /// owner is complaining about. Showing it whenever the loop *holds* group ink hides it in exactly
    /// the case an artist wants it most: adding untagged ink to a group.
    private var animationGroupBand: some View {
        let reason = canvasManager.animationGroupEditUnavailableReason
        // Read once and used for the readout, for the gate, and for every chip's outline, so the
        // sentence, the dimming and the ring can never disagree — `recolorReason`'s rule one property
        // up. It is memoized behind three gates (`selectionAnimationGroup`), so reading it here rather
        // than per chip costs one struct comparison a body pass on a document with no animation groups.
        let current = canvasManager.selectionAnimationGroup
        // **`.unavailable` rather than `selection != nil`, and that is a defect this caught.** A
        // selection is stamped with the cel it was drawn on and outlives a layer switch, so "there is
        // a selection" and "this verb can act on it" are different questions: with a loop drawn on
        // layer 1 and layer 2 active, `hasSelection` is true, `reason` is nil, and every chip would
        // have been live and done nothing silently — the "a refusal with no notice" defect, reached
        // through a third door. `selectionAnimationGroup` answers `.unavailable` for exactly the cases
        // `setAnimationGroupOfSelection` bails on, so gating on it makes the control's liveness and
        // the verb's guard one statement.
        let live = reason == nil && current != .unavailable
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
    ///
    /// **44x26 rather than UIKit's 51x31 since TODO (59)**: it shares a row now, and the row's height
    /// is the membership column's, so the switch has to fit under that rather than set it.
    private var switchIndicator: some View {
        let isOn = canvasManager.allowsPaintingOutsideSelection
        return ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Color.blue : Color.white.opacity(0.25))
            Circle().fill(Color.white).padding(2)
        }
        .frame(width: 44, height: 26)
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
            .padding(.vertical, 6)
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
        return editReason ?? applyBrushReason ?? canvasManager.animationGroupEditUnavailableReason
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
