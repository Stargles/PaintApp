import Combine
import CoreGraphics

/// **The fill tool's settings, in an object of their own** — TODO (157).
///
/// The owner: *"The gap closing slider in the fill tool is being janky."* These were `@Published` on
/// `CanvasManager`, and every view in the editor observes `CanvasManager`, so each tick of a fill slider
/// was a SwiftUI pass over the whole editor — the canvas's `reconcileLayers`, the sandwich and bake
/// sync, every toolbar body — for a number two sliders draw. MEASURED in PERFORMANCE.md §28. Here only
/// the views that show these values observe them (`FillSettingsPanel`, the left rail's fill sliders),
/// so a tick redraws its slider and nothing else. `CanvasManager.fillSettings` holds the one instance;
/// `CanvasManager.setFillSetting` and its siblings are the writers that also re-run an adjustable fill.
///
/// **Saved with the scene** (TODO (176)): `FillToolManifest` is their record in the manifest, with the Fill
/// Type beside them.
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
    /// who keeps Gap Closing low. Only read while `mendsNeighbourGap` is on.
    @Published var mendReach: CGFloat = 12

    /// How far the canvas edge's boundary sits **outside the paper, into the padding**, in canvas
    /// pixels — the owner's *"if I set it to 100px, then the canvas edge fill boundary will be
    /// extended 100px into the padding."* 0 is the boundary at the paper's own edge, which is what the
    /// option has always meant.
    ///
    /// Only read while `canvasEdgeIsBoundary` is on, and it cannot reach past the
    /// padded canvas: the fill's boundary rect is the artwork rect outset by this and clamped to
    /// `canvasSize` (`CanvasManager.currentFillKey` does the arithmetic, in the one place the rect is
    /// decided). A value larger than the padding is therefore the boundary at the canvas's own edge —
    /// the same fill the option off gives — which is why the slider's range follows the padding and
    /// the stored value need not.
    @Published var canvasEdgeExtension: CGFloat = 0

    /// Whether the canvas rectangle's edge bounds the fill the way a drawn line does. On by default,
    /// at the owner's request.
    ///
    /// **"The canvas edge" is the edge of the artwork rect — `canvasSize` inset by `canvasPadding` on
    /// every side — and not the edge of the pixel buffer.** With padding those are different
    /// rectangles, and confusing them is what made this option not work: the flood has always been
    /// clamped to the *buffer*, which is free and needs no option, but with a margin around the
    /// artwork that clamp sits `canvasPadding` px too far out and an enclosure that leans on the
    /// paper's border is open along that whole border.
    ///
    /// Two things happen when it is on, and only the first is what the artist means by the name:
    /// - the artwork rect's boundary **bounds the flood**, on both sides — a fill started on the
    ///   paper stops at the paper's edge instead of spreading onto the grey margin, and a fill
    ///   started on the margin stays there. This does not consult Gap Closing at all.
    /// - the paper's edge counts as **ink for gap closing**, so a boundary stroke ending a few px
    ///   short of it leaves an opening that seals rather than letting the fill run around its end.
    ///   This half is the one that does nothing while Gap Closing is 0.
    ///
    /// At `canvasPadding == 0` the two rectangles coincide, the flood already could not leave the
    /// buffer, and the option reduces exactly to the second half. See `gapLevels` in Fill.metal for
    /// both mechanisms and for why the boundary is a barrier between pixels rather than ink added to
    /// the wall mask.
    @Published var canvasEdgeIsBoundary = true

    /// Whether a fill grows into the gap between itself and paint already on its layer — the owner's
    /// *"have fill B smartly detect its edge is near fill A, and mend the gap"* (TODO (113)). On by
    /// default (owner, 2026-10-12): a fill that ends short of the one beside it is a defect the artist
    /// would otherwise have to remember to switch off, and the switch is still in the fill menu.
    ///
    /// How far it reaches is `mendReach`, its own setting. Both fill types honour it.
    @Published var mendsNeighbourGap = true
}

/// **The fill tool's settings in the scene's manifest** — Fill Type (`CanvasManager.fillMode`) and
/// everything `FillSettings` holds.
struct FillToolManifest: Codable, Equatable {
    var mode: FillMode
    var gapClosing: CGFloat
    var threshold: CGFloat
    var bucketEdgeOverlap: CGFloat
    var lassoEdgeOverlap: CGFloat
    var mendsNeighbourGap: Bool
    var mendReach: CGFloat
    var canvasEdgeIsBoundary: Bool
    var canvasEdgeExtension: CGFloat

    /// A new scene's: Flood, and `FillSettings`' own defaults.
    init() {
        self.init(mode: .flood, settings: FillSettings())
    }

    init(mode: FillMode, settings: FillSettings) {
        self.mode = mode
        gapClosing = settings.gapClosing
        threshold = settings.threshold
        bucketEdgeOverlap = settings.bucketEdgeOverlap
        lassoEdgeOverlap = settings.lassoEdgeOverlap
        mendsNeighbourGap = settings.mendsNeighbourGap
        mendReach = settings.mendReach
        canvasEdgeIsBoundary = settings.canvasEdgeIsBoundary
        canvasEdgeExtension = settings.canvasEdgeExtension
    }

    func apply(to settings: FillSettings) {
        settings.gapClosing = gapClosing
        settings.threshold = threshold
        settings.bucketEdgeOverlap = bucketEdgeOverlap
        settings.lassoEdgeOverlap = lassoEdgeOverlap
        settings.mendsNeighbourGap = mendsNeighbourGap
        settings.mendReach = mendReach
        settings.canvasEdgeIsBoundary = canvasEdgeIsBoundary
        settings.canvasEdgeExtension = canvasEdgeExtension
    }
}
