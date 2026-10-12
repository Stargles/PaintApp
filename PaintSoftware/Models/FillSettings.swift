import Combine
import CoreGraphics

/// **The fill tool's slider values, in an object of their own** — TODO (157).
///
/// The owner: *"The gap closing slider in the fill tool is being janky."* These were `@Published` on
/// `CanvasManager`, and every view in the editor observes `CanvasManager`, so each tick of a fill slider
/// was a SwiftUI pass over the whole editor — the canvas's `reconcileLayers`, the sandwich and bake
/// sync, every toolbar body — for a number two sliders draw. MEASURED in PERFORMANCE.md §28. Here only
/// the views that show these values observe them (`FillSettingsPanel`, the left rail's fill sliders),
/// so a tick redraws its slider and nothing else. `CanvasManager.fillSettings` holds the one instance;
/// `CanvasManager.setFillSetting` and its siblings are the writers that also re-run an adjustable fill.
///
/// Not saved across launches: session state. The fill tool's switches are kept (`ToolSwitches`); these values are not.
final class FillSettings: ObservableObject {

    /// Which setting the fill tool's sideways drag adjusts, and which slider the Fill panel highlights.
    /// Changing any of the three re-points it at that one (`CanvasManager.setFillSetting`).
    @Published var selectedAxis: CanvasManager.FillAxis = .gapClosing

    static let defaultGapClosing: CGFloat = 8
    static let defaultBucketEdgeOverlap: CGFloat = 2

    /// **Gap Closing**, in canvas pixels: the widest opening in the ink that a fill will not escape
    /// through. It seals openings and nothing else — an edge or a corner fills right up to the ink at
    /// every setting (TODO (158); `FillBasins` is the rule).
    @Published var gapClosing: CGFloat = FillSettings.defaultGapClosing

    /// Colour-distance threshold (0..1) above which a boundary counts as a wall. Higher = the fill
    /// spreads across bigger colour differences (fewer walls); lower = subtle borders stop it.
    @Published var threshold: CGFloat = 0.15

    /// Edge Overlap for the **bucket** fill, in px: how far the finished region is grown under the
    /// wall it stopped against. The lasso keeps its own value below; they are separate settings
    /// wearing one slider, and `CanvasManager.fillEdgeOverlap` is the accessor that picks between them.
    @Published var bucketEdgeOverlap: CGFloat = FillSettings.defaultBucketEdgeOverlap

    /// Edge Overlap for the **lasso** fill, and it defaults to the top of the range rather than to
    /// the bucket's 2.
    ///
    /// Under the anchoring the owner ruled on 2026-08-21 the lasso reads this slider as *how far out
    /// the colour reaches, with the top being the ink's own outer edge* —
    /// `CanvasManager.fillEdgeRadius(lasso:)` turns it into an erosion of `upperBound - v`. Sharing the
    /// bucket's stored 2 would therefore ship a 4 px inward retreat by default: a pale seam all round
    /// the drawing, which is a version of the very complaint that opened the day. Per-mode storage is
    /// the smallest thing that stops one mode's sensible default from being the other's defect, and
    /// the slider itself is unchanged — it shows and writes whichever value belongs to the mode in
    /// front of the artist.
    @Published var lassoEdgeOverlap: CGFloat = CanvasManager.fillExpandRange.upperBound

    /// **Mend Reach**, in canvas pixels: the widest strip of ink between a fill and its neighbour that
    /// the mend will close, counted from the fill's edge *after* Edge Overlap has tucked it under the
    /// line — so the two add, and a mend that Edge Overlap already covered has nothing left to do
    /// rather than hiding behind it. The owner's *"its own slider … with a default set to 12px"*
    /// (TODO (113)): it was twice Gap Closing, which left the mend with no reach at all for an artist
    /// who keeps Gap Closing low. Only read while `CanvasManager.toolSwitches.fillMendsNeighbourGap` is on.
    @Published var mendReach: CGFloat = 12

    /// How far the canvas edge's boundary sits **outside the paper, into the padding**, in canvas
    /// pixels — the owner's *"if I set it to 100px, then the canvas edge fill boundary will be
    /// extended 100px into the padding."* 0 is the boundary at the paper's own edge, which is what the
    /// option has always meant.
    ///
    /// Only read while `CanvasManager.toolSwitches.fillCanvasEdgeIsBoundary` is on, and it cannot reach past the
    /// padded canvas: the fill's boundary rect is the artwork rect outset by this and clamped to
    /// `canvasSize` (`CanvasManager.currentFillKey` does the arithmetic, in the one place the rect is
    /// decided). A value larger than the padding is therefore the boundary at the canvas's own edge —
    /// the same fill the option off gives — which is why the slider's range follows the padding and
    /// the stored value need not.
    @Published var canvasEdgeExtension: CGFloat = 0
}
