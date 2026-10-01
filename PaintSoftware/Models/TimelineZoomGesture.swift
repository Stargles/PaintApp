import CoreGraphics

/// **Two fingers on the timeline, zooming and panning its frame axis at once.**
///
/// The frame that was under the fingers when they landed stays under them — wherever they travel
/// sideways, however far they spread. That is `ViewportAnchor`'s rule, the one the canvas turns and
/// zooms by, applied to the timeline's one axis: the content's origin is the track's left edge (so
/// `-contentOffsetX` in the viewport's space) and the scale is `pixelsPerFrame` over where it was.
///
/// **This is a type and not arithmetic inside `TimelineTrackView.Coordinator`** for the standing
/// reason: that file is not compiled into `PaintSoftwareUITests`, so the same arithmetic written
/// there is a pin against nothing. The coordinator keeps only the recognizers and the scroll view.
///
/// **Taken at a non-zero scroll offset or it cannot be seen.** A scroll view's coordinate system *is*
/// its content — `bounds.origin` is `contentOffset` — so `UIGestureRecognizer.location(in:)` on one
/// is content space, and the fingers' place *in the viewport* is that minus the offset. Mixing the two
/// puts the anchor `contentOffsetX · (scale − 1)` points out: exact at frame 0, and wrong by a whole
/// screenful once the artist has scrolled one. Both inputs here are in the viewport's space, named so.
struct TimelineZoomGesture: Equatable {
    private let startPixelsPerFrame: CGFloat
    private let anchor: ViewportAnchor

    /// - Parameters:
    ///   - fingersInViewportX: the centroid's x measured from the track's **visible** left edge.
    ///   - contentOffsetX: how far the track was scrolled when the fingers landed.
    ///   - pixelsPerFrame: the zoom when the fingers landed.
    init(fingersInViewportX: CGFloat, contentOffsetX: CGFloat, pixelsPerFrame: CGFloat) {
        startPixelsPerFrame = pixelsPerFrame
        anchor = ViewportAnchor(fingers: CGPoint(x: fingersInViewportX, y: 0),
                                contentOrigin: CGPoint(x: -contentOffsetX, y: 0))
    }

    /// The zoom a pinch of `scale` (relative to the landing) comes to, held inside what the timeline
    /// can reach. `TimelineKeyMarkers.pixelsPerFrameRange` is the range, and lives there for that
    /// file's own reason: its marker-collapse threshold is a relationship to its floor.
    func pixelsPerFrame(scale: CGFloat) -> CGFloat {
        let range = TimelineKeyMarkers.pixelsPerFrameRange
        return min(max(startPixelsPerFrame * scale, range.lowerBound), range.upperBound)
    }

    /// **The scroll offset that keeps the anchored frame under the fingers** at `pixelsPerFrame`, with
    /// the fingers now at `fingersInViewportX`, clamped to what the track can scroll to.
    ///
    /// Pass the zoom `pixelsPerFrame(scale:)` returned, not the raw pinch: the scale the anchor is
    /// carried by is the one the track actually took, so a pinch held past the end of the range keeps
    /// the frame under the fingers instead of sliding off it.
    func contentOffsetX(pixelsPerFrame: CGFloat,
                        fingersInViewportX: CGFloat,
                        contentWidth: CGFloat,
                        viewportWidth: CGFloat) -> CGFloat {
        let scale = startPixelsPerFrame > 0 ? pixelsPerFrame / startPixelsPerFrame : 1
        let origin = anchor.contentOrigin(fingersAt: CGPoint(x: fingersInViewportX, y: 0), scale: scale)
        return min(max(-origin.x, 0), max(0, contentWidth - viewportWidth))
    }
}
