import UIKit

/// **The ink that is on screen but is not in the layer's installed base**, as a value.
///
/// One invariant, and the whole of this type is holding it:
///
/// > *The pictures shown above the base are exactly the ink the installed base does not contain.*
///
/// **The defect it closes** ([BUGS.md](BUGS.md), 2026-09-04, "Starting a stroke before the last one
/// has rendered leaves the last one off screen"). RENDER.md §2.13 moved the pen-up rasterize off the
/// main thread, so between a stroke committing and its render landing the base slot holds a picture
/// the stroke is *not* in, and the stroke's own live scratch stands in for it. That worked for one
/// stroke and could not work for two: there is a single `scratchView`, so beginning stroke *n+1*
/// put its pixels where stroke *n*'s were and **stroke *n* was on screen nowhere at all** — not in
/// the base, which predates it, and not in the overlay, which the new stroke had taken. The artist
/// watched a finished stroke vanish and come back.
///
/// The fix is to stop conflating the two meanings the overlay had. *"The stroke under the pen"* is
/// one thing and *"ink the base does not have yet"* is another; the live scratch is the first, this
/// is the second, and a stroke moves from one to the other at pen-up.
///
/// **It allocates no pixels.** A held picture is the `UIImage` the live scratch was already showing
/// — windowed to the stroke's own box (`StrokeScratch`), never canvas-sized — so holding it retains
/// a bitmap that existed a moment ago and would otherwise have been released. It is in fact *less*
/// than the shipped code held: that kept the whole `StrokeScratch`, including its
/// `RasterLayerTexture` window and both of its memoized composites, until the render landed.
///
/// **And it is bounded by pen travel rather than by canvas area.** A picture is held from its
/// stroke's pen-up until a base containing it is installed — one render, MEASURED at 14.4 ms on
/// Test1 at 4096² and 27.3 ms at 6000² (`StrokeHandoffBench`) — so the set holds the strokes an
/// artist finished inside one render. A stroke's window is proportional to its own length and a long
/// stroke takes long enough to draw that its render lands first, which is why the sum does not grow
/// with the canvas: it grows with how far a pen can travel in one render, and that is the same few
/// hundred points at 512² as at 6000².
///
/// **Why a value type in `Views/` rather than state inside the view.** `StrokeCanvasView.swift` is
/// not a member of the UI-test target — it drags in `StrokeGestureRecognizer` and the rest of the
/// touch stack — so nothing nested inside it can be asserted headlessly, which is exactly why this
/// defect went two months without a test. `VectorPreviewPlan` and `DeferredVectorRender` are the two
/// existing members of that family and this is the third; the view holds one of these and obeys it.
struct UnlandedInk {

    /// One finished stroke's picture, exactly as the live scratch was showing it a moment before.
    ///
    /// The three display fields are the same three `StrokeCanvasView.showOverlays` reads off a live
    /// `StrokeScratch`, and they are copied rather than referenced for one reason: the scratch is
    /// released at pen-up now, so the picture has to outlive it.
    struct Picture {
        /// Identity, monotonic per view. Present so a test can say *which* picture without
        /// comparing bitmaps, and so the view can tell "the same held set" from "a set that happens
        /// to be the same length" when it decides whether to rebuild its layers.
        let id: Int
        /// **The `VectorCanvas.version` this ink is in.** A base rasterized at this version or later
        /// contains it, which is the whole of `retire(upTo:)`.
        let version: Int
        /// Where the picture goes, in canvas points — `StrokeScratch.windowRect`.
        let windowRect: CGRect
        /// What the picture is shown at — `StrokeScratch`'s own display alpha, which is the stroke's
        /// opacity for `.additive` and 1 for the two roles that have already applied it inside their
        /// pixels. BRUSH.md §2.11's cap, on the display side.
        let alpha: CGFloat
        /// Whether the picture *stands in for* the base inside its window rather than sitting over
        /// it — a vector eraser in Modes 1 and 2. The base is punched out underneath, exactly as it
        /// is for a live one.
        let replacesBase: Bool
        let image: UIImage
    }

    /// **In commit order, which is z-order.** Source-over of finished strokes in the order they were
    /// made is precisely what `VectorCanvas.renderLocalContent` does to a run of `.normal` paint
    /// strokes — each stroke flattened at its own opacity, then composited — so the screen and the
    /// base that replaces it are the same arithmetic rather than an approximation of it.
    private(set) var pictures: [Picture] = []

    var isEmpty: Bool { pictures.isEmpty }

    /// **The rectangle the base is punched out under**, or nil. See
    /// `StrokeCanvasView.setBaseHole`: an erase lowers alpha and Core Animation composites siblings
    /// source-over, so the layer's own ink would fill the removal straight back in.
    var baseHole: CGRect? { pictures.first(where: \.replacesBase)?.windowRect }

    /// **Holding a base-replacing picture retires any earlier one, and that is the base hole's
    /// geometry rather than a cap on memory.** Two removals need two holes; a `CAShapeLayer` with an
    /// even-odd path takes one, and two overlapping rectangles in an even-odd path cancel back to
    /// opaque. Widening to their bounding box over-punches the gap between them, which shows as the
    /// artist's ink disappearing where they did not erase.
    ///
    /// **It is unreachable in the shipped app, and this is belt and braces.** A Mode 1 or Mode 2
    /// eraser's touch-down builds its window from `VectorCanvas.renderIfNonEmpty()` — a *synchronous*
    /// canvas render, which fills the memo, so the `refreshDisplay` at the end of
    /// `beginVectorStroke` finds `.ready` and installs a current base. Everything held retires
    /// there, one call before this one could see it. What this rule buys is that the invariant is
    /// provable from this file rather than from a property of another one.
    ///
    /// An **additive** picture is kept whatever is below it, and needs no rule at all: it is the
    /// stroke's own ink over whatever was there, which is what source-over means.
    mutating func hold(_ picture: Picture) {
        if picture.replacesBase { pictures.removeAll(where: \.replacesBase) }
        pictures.append(picture)
    }

    /// **A base rasterized at `version` has been installed, so everything it contains stops being
    /// un-landed.** `<=` rather than `==`: renders are dispatched per commit onto one serial queue
    /// and a later one is a superset, so a base can arrive that covers several held pictures at once
    /// — which is exactly what happens when an artist finishes two strokes inside one render.
    mutating func retire(upTo version: Int) {
        pictures.removeAll { $0.version <= version }
    }

    /// **Nothing held is about this canvas any more.** Four callers, and each is a case where the
    /// base slot stops being a picture of the same list: the view is handed a different
    /// `VectorCanvas` (a layer, cel or frame change), the base becomes a derived in-between frame,
    /// the composite takes over drawing this layer, or an eraser's synchronous touch-down render has
    /// just made the base current.
    mutating func removeAll() {
        pictures.removeAll()
    }
}
