import UIKit

// The two full-height columns the timeline's ruler strip and its track both draw — one instance of
// each per surface (`TimelineRulerStripView`, `TimelineTrackView.Coordinator`).

/// **Frame gridlines — TODO (38)(a): "add vertical grey lines to segment the timeline so that I can
/// see which frame is which."**
///
/// A sibling spanning the whole extent rather than something the ruler or each row draws for itself,
/// because the ask covers the ruler strip *and* the track beneath it: one rule reads as one thing,
/// where a rule drawn separately for each row would seam between them. There are two instances, one
/// per surface — the ruler strip's, and the track's — which meet at the strip's bottom edge at the
/// same x and in the same grey, so the line runs unbroken from the ruler down through the rows. Each
/// is its surface's **first** subview — behind the ruler, the bake bar, every row and the graph band —
/// so a line never sits on top of a cel's picture, only behind it.
///
/// **Every frame, at every zoom — density needed no decision beyond the one the pinch already
/// makes.** `TimelineKeyMarkers.pixelsPerFrameRange` floors `pixelsPerFrame` at 10.5 pt — the same
/// floor `minimumSeparation` (12 pt) is measured against to decide when two 9 pt *marker* diamonds
/// start to crowd. A gridline is a 1 pt hairline, not a 9 pt diamond, so at that same floor it still
/// has ~9.5 pt of daylight either side and never approaches a wash. Below the pinch floor there is
/// no reachable zoom to thin lines *at*, so an every-Nth-frame rule would be answering a question
/// this geometry does not ask — unlike the marker collapse, which exists because diamonds really do
/// touch at that floor.
///
/// **The graph editor draws its own copy of this rather than being drawn on by this view.** The band
/// sits above this view in `contentView`'s z-order and paints its own near-opaque backdrop
/// (`TimelineGraphBand.backgroundWhite`) over it, so a line only this view drew would be washed out
/// exactly where the ask most wants it kept — "Same with the graph editor." `TimelineGraphBandView.draw`
/// draws the identical line, at the identical x, behind its curves instead.
final class TimelineGridlinesView: UIView {
    /// Shared with `TimelineGraphBandView`, so the timeline and the graph editor rule off the same
    /// grey — the TODO heading's "should read as one thing" made literal for this one property.
    /// Width is `TimelineKeyMarkers.gridlineWidth`, not a second constant here — see its own doc for
    /// why it lives on the geometry side of the split instead.
    static let lineColor = UIColor.gray.withAlphaComponent(0.22)

    var frameCount: Int = 0
    var pixelsPerFrame: CGFloat = TimelineKeyMarkers.basePixelsPerFrame

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Clipped to `rect` by `TimelineRulerClip`, for the reason its own doc gives: partial
    /// invalidation should cost what is redrawn, not the whole scene.
    override func draw(_ rect: CGRect) {
        // Timed because `PlaybackTrace` measured a stall that runs entirely in the runloop's
        // source half, *after* the last `updateUIView` returns — which is where `CALayer`
        // display happens, and this is the only `draw(_:)` on the editing path.
        PlaybackTrace.span(.viewDraw) { drawNow(rect) }
    }

    private func drawNow(_ rect: CGRect) {
        guard pixelsPerFrame > 0, frameCount > 0 else { return }
        Self.lineColor.setFill()
        for frame in TimelineRulerClip.frames(in: rect, pixelsPerFrame: pixelsPerFrame, frameCount: frameCount) {
            let x = TimelineKeyMarkers.columnX(frame: frame, pixelsPerFrame: pixelsPerFrame)
            UIRectFill(CGRect(x: x, y: 0, width: TimelineKeyMarkers.gridlineWidth, height: bounds.height))
        }
    }
}

/// Non-interactive playhead indicator: a column the width of a frame. One in the track over the rows, and
/// one in the ruler strip over the ruler, at the same x, so it reads as a single column.
final class TimelinePlayheadView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.35)
        isUserInteractionEnabled = false

        let leading = UIView()
        leading.backgroundColor = .systemBlue
        leading.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leading)
        let trailing = UIView()
        trailing.backgroundColor = .systemBlue
        trailing.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trailing)
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: leadingAnchor),
            leading.topAnchor.constraint(equalTo: topAnchor),
            leading.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading.widthAnchor.constraint(equalToConstant: 1.5),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailing.topAnchor.constraint(equalTo: topAnchor),
            trailing.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailing.widthAnchor.constraint(equalToConstant: 1.5)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
