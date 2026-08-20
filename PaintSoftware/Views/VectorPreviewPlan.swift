import Foundation

/// How the live-preview scratch raster relates to the vector canvas's own render. Differs per tool
/// and — for the eraser — per mode. Set once in `StrokeCanvasView.beginVectorStroke`, read by
/// `refreshDisplay` through `VectorPreviewPlan`, and named in
/// `StrokeCanvasView.lastVectorGestureTrace`.
///
/// Lives here rather than nested in `StrokeCanvasView` for one reason: `StrokeCanvasView.swift` is
/// not a member of the UI-test target (it drags in `StrokeGestureRecognizer` and the rest of the
/// touch stack), so nothing nested inside it can be asserted headlessly. The three roles behave
/// differently and two of them are one-operation paths that must stay that way — that is a contract,
/// and a contract wants a test that is cheaper than a 22-minute UI suite.
enum VectorScratchRole {
    /// A paint stroke: the scratch holds only this stroke's ink, shown *over* the canvas render. The
    /// canvas itself is untouched until lift.
    case overlay
    /// Mode 1: the scratch starts as a copy of the canvas render and dabs punch `.destinationOut`
    /// into it, replacing the canvas render for the stroke's duration — the raster eraser's own code
    /// path applied to the vector layer's pixels.
    case replacement
    /// Modes 2 and 3: nothing is drawn into the scratch. Mode 3 commits during the drag and Mode 2
    /// on lift, so the canvas render alone is truth, and skipping the scratch avoids a canvas-sized
    /// allocation/composite per touch sample.
    case none

    /// Name used in `StrokeCanvasView.lastVectorGestureTrace`.
    var traceName: String {
        switch self {
        case .overlay: return "overlay"
        case .replacement: return "replacement"
        case .none: return "none"
        }
    }
}

/// What `StrokeCanvasView.refreshDisplay` puts in each of its two image slots for one refresh, as a
/// value — so the decision can be asserted without a simulator, a touch, or a pixel.
///
/// **The defect this exists to delete** ([PERFORMANCE.md](PERFORMANCE.md) item 11,
/// [BUGS.md](BUGS.md) "Drawing on a vector layer at 4K is capped at ~19 fps"). The `.overlay` branch
/// used to flatten the committed render and the live scratch into one bitmap on every touch-move:
/// a *fresh* canvas-sized `UIGraphicsImageRenderer` allocation, the committed render blitted into
/// it, the scratch rendered, and that blitted over the top. Four canvas-sized operations where the
/// raster path does one, and at 4096² the allocation alone is 64 MiB **per dab** — 53.8 ms against
/// 4.0 ms, MEASURED on the owner's iPad 9 in Release. Core Animation composites two sibling layers
/// anyway; asking Core Graphics to do it first on the CPU, once per pen sample, bought nothing.
///
/// **So the composite is not expressible here.** There is no `case composited`, and that is the
/// design rather than an omission: a plan says which single image goes in the base slot and whether
/// the scratch goes in its own slot above it. A future edit cannot reintroduce the per-dab bitmap
/// without changing this type, which is a conspicuous thing to do.
///
/// **The two one-operation roles are the risk, not the win.** `.replacement` and `.none` were
/// already paying one canvas-sized render per refresh and neither may pay more now. They are pinned
/// by `showsScratchLayer == false` here and by `VectorPreviewPlanLogicTests`, because a regression
/// there is not slow ink — it is Mode 1 previewing something other than the punched copy, which is
/// the artist erasing and seeing nothing until they lift.
struct VectorPreviewPlan: Equatable {

    /// Which single image fills the base slot. Exactly one, always — never a composite of two.
    enum Base: Equatable {
        /// The derived in-between frame, which replaces the cel's own content outright. At an
        /// in-between the cel's own canvas is empty, so this wins wherever it exists.
        case interpolation
        /// `VectorCanvas.renderIfNonEmpty()` — the committed content, memoized on the canvas's
        /// `version` and therefore free to re-read across a stroke that has not committed yet.
        case committedRender
        /// `.replacement` only: the scratch already holds a copy of the render with this stroke's
        /// holes punched in, and it *is* the display.
        case scratch
    }

    var base: Base

    /// Whether the scratch is handed to its own layer above the base for Core Animation to
    /// composite. False means the scratch contributes nothing to this refresh — **not** that it is
    /// flattened into the base, which is no longer a thing this type can say.
    var showsScratchLayer: Bool

    /// Whether this refresh published a live-preview frame, i.e. whether it moves
    /// `StrokeCanvasView.livePreviewFrames` and so the second field of `lastVectorGestureTrace`.
    ///
    /// **`.overlay` counts as of 2026-08-20 and did not before.** It was excluded when the counter
    /// was for proving Mode 1's punched copy reached the screen during a drag, and an overlay had no
    /// equivalent claim to prove. It does now: the overlay's ink reaches the screen through a
    /// *second layer* rather than through the base image, and "the scratch layer was updated
    /// repeatedly during the drag" is the only thing about that path an XCUITest can observe at all
    /// — `press(forDuration:thenDragTo:)` blocks the test thread for the gesture's whole duration,
    /// so every screenshot it can take is post-lift. `VectorEraserUITests` asserts the count for
    /// both roles, and `.none` still publishes zero.
    var publishesLivePreviewFrame: Bool

    /// The whole of `refreshDisplay`'s vector branch, as arithmetic.
    ///
    /// `hasInterpolationImage && !hasScratch` used to be an early return of its own. It is folded in
    /// here deliberately, not dropped: the `base` it produced was `interpolation`, which is exactly
    /// what the general case below produces for the same inputs, since a non-nil interpolation image
    /// always wins the base slot and a nil scratch always fails the overlay test. `forEveryCombination`
    /// in the logic tests walks all twelve (role × scratch × interpolation) inputs so the claim is
    /// checked rather than reasoned about.
    static func forVectorLayer(role: VectorScratchRole,
                               hasScratch: Bool,
                               hasInterpolationImage: Bool) -> VectorPreviewPlan {
        // Mode 1: the punched copy replaces the display outright. Checked before the base is chosen
        // because it is the one role whose base is neither the canvas nor the in-between.
        if role == .replacement, hasScratch {
            return VectorPreviewPlan(base: .scratch,
                                     showsScratchLayer: false,
                                     publishesLivePreviewFrame: true)
        }
        let base: Base = hasInterpolationImage ? .interpolation : .committedRender
        guard role == .overlay, hasScratch else {
            return VectorPreviewPlan(base: base,
                                     showsScratchLayer: false,
                                     publishesLivePreviewFrame: false)
        }
        return VectorPreviewPlan(base: base,
                                 showsScratchLayer: true,
                                 publishesLivePreviewFrame: true)
    }
}
