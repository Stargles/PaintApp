import CoreGraphics

/// **How far to the right the timeline is laid out** — the one rule that decides whether there is
/// empty track for the artist to put a drawing in.
///
/// It lives here rather than inside `TimelineTrackView.Coordinator` because a rule a view holds is a
/// rule the fast tier cannot see, and this one is load-bearing in a way that is easy to miss. TODO
/// (50) deleted `CanvasManager.sceneFrameCount`, a stored high-water mark that only ever rose, and
/// the obvious objection to deleting it was that the timeline would then end at the last drawing and
/// a block could no longer be dropped past it. That objection is answered here rather than in the
/// model: the scene's length is only a **floor**, and the term that is normally binding is the
/// look-ahead — two screenfuls past wherever the artist has currently scrolled.
enum TimelineTrackExtent {

    /// How many frame columns the track lays out, which is deliberately more than the scene holds.
    ///
    /// The larger of two things:
    ///
    ///  - **the scene** (`CanvasManager.contentEndFrame`, floored at one), so a document is never laid
    ///    out shorter than its own drawings even at a zoom where a screenful is a couple of frames; and
    ///  - **the look-ahead**: everything up to two viewport widths past the current scroll offset, so
    ///    scrolling right always arrives at empty slots and the track has no end to run into.
    ///
    /// At the default zoom the second term is dozens of frames, so on any short document it is the
    /// one that answers — which is exactly why shortening the scene cannot strand the artist.
    ///
    /// `pixelsPerFrame` is floored rather than trusted: it is a live pinch value, and a zero would
    /// divide the reach into infinity and then trap converting it to `Int`.
    static func displayedFrameCount(contentEndFrame: Int,
                                    contentOffsetX: CGFloat,
                                    viewportWidth: CGFloat,
                                    pixelsPerFrame: CGFloat) -> Int {
        let width = max(viewportWidth, 1)
        let reach = max(contentOffsetX, 0) + width * 2
        let needed = Int((reach / max(pixelsPerFrame, 0.001)).rounded(.up)) + 1
        return max(max(contentEndFrame, 1), needed)
    }
}
