import CoreGraphics

/// **How tall the timeline panel is allowed to be, and how tall it opens** — the one place the rules
/// live, so `AnimationTimeline` draws what this says and a test can hold it to its claims. TODO (169),
/// the owner, who holds a 9th-generation iPad in landscape (810 pt, 790 of it the editor's): *"the
/// timeline's default height is a fraction of the window, not a fixed 375 pt."* At a fixed 375 the
/// panel took 47% of that window, and a docked card on top of it left about 90 pt of paper.
///
/// **A share of the window, up to a ceiling.** The panel opens at `defaultShare` of the height it has
/// to share with the canvas, and never taller than `openingCeiling` — the 375 pt TODO (122) ruled, about
/// eight layers in view before the rows scroll. The ceiling is what keeps the 13-inch iPad exactly
/// where it was in portrait (1376 pt tall; a bare share would open it 480 pt tall, and since the paper
/// is as wide as the window and no taller, the extra height would only cover more of the picture) and
/// within 14 pt of it in landscape. The share is what the short windows — the owner's iPad, a Split
/// View — get back.
///
/// **The default is derived, never stored**: an artist who has not touched the panel has a timeline
/// that follows the window, rotation included. A height they dragged is a number of points and stays
/// one (`AnimationTimeline`).
enum TimelinePanelSize {

    /// Of the height the timeline shares with the canvas. A touch over a third: the owner's iPad opens
    /// at 276 of its 790 pt and the 13-inch's landscape at 354 of 1012.
    static let defaultShare: CGFloat = 0.35

    /// The tallest the panel ever opens at (TODO (122): 1.5× the 250 pt it opened at before). The artist
    /// can still drag it taller, to `maxHeight(in:)`.
    static let openingCeiling: CGFloat = 375

    /// The bar the panel shrinks to; the drag is continuous all the way into it.
    static let collapsedHeight: CGFloat = 48

    /// Below this an expanded panel is not usable — the grab bar, the toolbar, the ruler and one row
    /// — so a drag that ends under it settles collapsed, and a default never opens under it.
    static let minExpandedHeight: CGFloat = 130

    /// How tall the artist may drag the panel in a window `availableHeight` tall: leaves just enough
    /// room for the top toolbar to stay visible above it.
    static func maxHeight(in availableHeight: CGFloat) -> CGFloat {
        max(availableHeight - 64, minExpandedHeight)
    }

    /// What the panel opens at, in a window `availableHeight` tall — always at least the usable
    /// minimum and never past `maxHeight(in:)`.
    static func defaultHeight(in availableHeight: CGFloat) -> CGFloat {
        min(max(availableHeight * defaultShare, minExpandedHeight), openingCeiling, maxHeight(in: availableHeight))
    }
}
