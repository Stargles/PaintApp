import SwiftUI

/// **The geometry the four bottom-docked options panels share** — Lasso/Select, Move, Add Text and
/// the compositor effect settings. TODO item (49), the owner 2026-09-05:
///
/// > *"the options panel that pops up on the bottom of the screen in lasso, move, add text, effect
/// > settings for compositor effects (that type of options panel UI) is too tall and obstructs your
/// > view. Make all of them wider and flatter. Additionally, make it move with the timeline
/// > expansion."*
///
/// Until now there was no shared anything: the four each spelled their own width (360, 560, 560 and
/// whatever the content came to) and their own card chrome, and `DrawingView.bottomDock` — the one
/// seam that did exist — floated the column a **hard-coded 100 points** above the bottom of the
/// canvas area against a timeline whose default height is 250. So the dock sat 150 points *inside*
/// the timeline before the artist had touched anything, which is the second half of the ask.
///
/// **This type is in the test target and the four panels are not**, which is the whole reason the
/// numbers live here rather than in the views: `BottomDockLogicTests` can hold the width rule and
/// the timeline anchor to their claims, and nothing in a SwiftUI body is reachable from a test.
enum BottomDock {

    /// What a panel takes when there is room for it. Wide enough that a slider row fits its label,
    /// its travel and its readout on **one line** — which is what buys the flatness, and buys it
    /// without shortening any slider: `EffectSettingsBar` gave a slider 532 points of travel over
    /// two lines at 560 wide, and gives it the same 532 over one line here.
    static let preferredWidth: CGFloat = 760

    /// Below this a panel stops shrinking and accepts being narrower than the canvas area — every
    /// control in these four still lays out here, and a panel that kept shrinking would start
    /// clipping them instead. It is the width `SelectPanel` shipped at.
    static let minimumWidth: CGFloat = 360

    /// Canvas left either side of the card at `preferredWidth`, so a docked panel never reads as a
    /// full-bleed sheet.
    static let sideMargin: CGFloat = 16

    /// Air between the dock's bottom edge and the top of the timeline. Small on purpose: the point
    /// is that the two touch rather than overlap.
    static let timelineGap: CGFloat = 8

    /// The ceiling on a panel's own scrolling region — `EffectSettingsBar`'s old `maxRowsHeight`, lifted
    /// here so the text panel takes the same one. It is a **ceiling, not a height**: a panel with
    /// two sliders is as short as two sliders (`ContentHeightCap`).
    ///
    /// 260 rather than the 300 it was. Two things set it and they pull opposite ways: Levels, the
    /// tallest all-slider effect, is five one-line rows and wants ~195, and the text panel is a
    /// fixed list of eleven controls that scrolls at any height and wants as much as it can get
    /// without becoming the thing the owner complained about. MEASURED on the simulator: at 220 the
    /// text panel cut its fourth row in half at the card's rounded edge, which reads as broken
    /// rather than as scrollable.
    static let maxScrollHeight: CGFloat = 260

    /// A docked row's own insets, and the two fixed columns a **one-line slider row** puts either
    /// side of its slider: the label (with its animated-channel marker) on the left, the live
    /// readout on the right.
    ///
    /// Fixed rather than intrinsic so every slider in a panel starts and ends on the same two
    /// verticals — thirteen effects' worth of labels differ in length, and a ragged left edge on a
    /// column of sliders reads as a column of unrelated controls.
    static let rowHorizontalPadding: CGFloat = 14
    static let rowSpacing: CGFloat = 10
    static let sliderLabelWidth: CGFloat = 128
    static let sliderReadoutWidth: CGFloat = 52

    /// **What a slider actually has to travel in**, once the fold has taken its two columns.
    ///
    /// This is the number the flatness rests on, and it is why `preferredWidth` is what it is: the
    /// two-line row at 560 wide gave a slider **532 points** (560 less 14 either side), and the
    /// one-line row has to give it no less, or "flatter" would have been bought by making every
    /// control worse. `BottomDockLogicTests` holds it to that.
    static var inlineSliderTravel: CGFloat {
        preferredWidth - 2 * rowHorizontalPadding - sliderLabelWidth - sliderReadoutWidth - 2 * rowSpacing
    }

    /// How wide the card is in a canvas area `available` points across.
    ///
    /// Three regimes and the middle one is the point: on the owner's iPad it is `preferredWidth`,
    /// on a narrow split view it gives the margins back before it gives up any width, and it never
    /// goes below `minimumWidth` however little room there is.
    static func width(in available: CGFloat) -> CGFloat {
        max(minimumWidth, min(preferredWidth, available - 2 * sideMargin))
    }

    /// How far above the bottom of the canvas area the dock's own bottom edge sits, given how much
    /// of that area the timeline currently occupies.
    ///
    /// **`occupiedHeight` is the timeline's *rendered* height, not its `timelineHeight` state** —
    /// `AnimationTimeline` reports it through `TimelineOccupiedHeightKey`, so the interpolate strip
    /// that sits above the panel in interpolate mode is included without this file knowing the strip
    /// exists, and there is no second copy of the timeline's own arithmetic to drift.
    static func bottomInset(clearing occupiedHeight: CGFloat) -> CGFloat {
        max(0, occupiedHeight) + timelineGap
    }
}

/// The rendered height of the whole timeline — the panel plus whatever strip is above it — reported
/// up to `DrawingView` so the bottom dock can ride on top of it. See `BottomDock.bottomInset`.
struct TimelineOccupiedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// The card chrome a docked options panel wears. **One definition for the four**, which is what
    /// the owner's *"make all of them"* asks for — before this, three of them painted a near-identical
    /// but not identical chain (0.9 / 0.9 / 0.95 opacity, radius 14 / 14 / 16, and the Move bar had
    /// neither the hairline nor the shadow).
    func bottomDockCard(width: CGFloat) -> some View {
        self
            .frame(width: width)
            .background(Color.black.opacity(0.92))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}
