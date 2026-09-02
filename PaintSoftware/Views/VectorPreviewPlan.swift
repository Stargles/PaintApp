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
    /// Modes 1 and 2: the scratch starts as a copy of the canvas render *inside its own window* and
    /// dabs punch `.destinationOut` into it, standing in for the canvas render over that window for
    /// the stroke's duration — the raster eraser's own code path applied to the vector layer's
    /// pixels. `StrokeCanvasView.showScratch` punches the base out under it; see `StrokeScratch`.
    case replacement
    /// Mode 3: nothing is drawn into the scratch. It commits during the drag, so the canvas render
    /// alone is truth and a scratch would show what is already on screen.
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
/// **`.replacement` reaches the screen through the scratch layer too, since 2026-09-01.** It used to
/// win the base slot outright, because its scratch was a canvas-sized copy of the render with the
/// stroke's holes punched in and so *was* the whole picture. The scratch is a window over the
/// stroke's own dirty rect now (`StrokeScratch`), which cannot fill the base slot — so the base is
/// the committed render, as it is for every other role, and the window sits above it with the base
/// punched out underneath. `.none` is the one role that shows no second layer, and a regression
/// there or in `.replacement` is not slow ink: it is the artist erasing and seeing nothing happen
/// until they lift. `VectorPreviewPlanLogicTests` pins both.
struct VectorPreviewPlan: Equatable {

    /// Which single image fills the base slot. Exactly one, always — never a composite of two.
    enum Base: Equatable {
        /// The derived in-between frame, which replaces the cel's own content outright. At an
        /// in-between the cel's own canvas is empty, so this wins wherever it exists.
        case interpolation
        /// `VectorCanvas.renderIfNonEmpty()` — the committed content, memoized on the canvas's
        /// `version` and therefore free to re-read across a stroke that has not committed yet.
        case committedRender
    }

    var base: Base

    /// Whether the scratch is handed to its own layer above the base for Core Animation to
    /// composite. False means the scratch contributes nothing to this refresh — **not** that it is
    /// flattened into the base, which is no longer a thing this type can say.
    ///
    /// **This is also the live-preview frame count**, i.e. it is what moves
    /// `StrokeCanvasView.livePreviewFrames` and so the second field of `lastVectorGestureTrace`.
    /// The two were separate fields while `.replacement` published a frame through the base slot
    /// rather than through the scratch layer; now that every role that draws draws through the
    /// scratch layer they are the same question, and a second field that could only ever repeat this
    /// one would be a place for them to disagree. "The scratch layer was updated repeatedly during
    /// the drag" is the only thing about the live path an XCUITest can observe at all —
    /// `press(forDuration:thenDragTo:)` blocks the test thread for the gesture's whole duration, so
    /// every screenshot it can take is post-lift. `VectorEraserUITests` asserts the count for both
    /// drawing roles, and `.none` still publishes zero.
    var showsScratchLayer: Bool

    /// The whole of `refreshDisplay`'s vector branch, as arithmetic.
    ///
    /// **The base slot no longer depends on the role at all**, which is what the window made
    /// possible: an in-between frame if there is one, the committed render otherwise, for every
    /// role including `.replacement`. `forEveryCombination` in the logic tests walks all twelve
    /// (role × scratch × interpolation) inputs so that is checked rather than reasoned about.
    static func forVectorLayer(role: VectorScratchRole,
                               hasScratch: Bool,
                               hasInterpolationImage: Bool) -> VectorPreviewPlan {
        let base: Base = hasInterpolationImage ? .interpolation : .committedRender
        // Every role that draws draws into the scratch layer; `.none` is the one that does not draw.
        return VectorPreviewPlan(base: base, showsScratchLayer: hasScratch && role != .none)
    }
}
