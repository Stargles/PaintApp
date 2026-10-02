import CoreGraphics

/// **The canvas pans itself to keep the text box being typed in view, and gives the view back when
/// the typing is over** — the owner, 2026-10-02: *"the canvas scrolls to keep the text box being typed
/// visible above the Text panel and keyboard, and back after."*
///
/// A box placed low on the paper is under the Text panel the moment it is placed, and under the
/// keyboard a moment later: the artist types into words they cannot see. The remedy is the pan the
/// artist makes by hand, not a second offset — `CanvasView.Coordinator` adds this struct's answer to the
/// canvas's own committed offset, so the box, the grips and every overlay ride the same transform they
/// always do.
///
/// **Vertical only.** What covers the canvas is a strip across its bottom (the timeline, the panel, and
/// above them the keyboard), so that is the only direction a box is ever lost in.
///
/// **It yields to the artist.** A pan, pinch or turn made while typing is theirs: the follow stops
/// moving the canvas for the rest of the session, and gives nothing back at its end, because "back"
/// would undo what they did on purpose. A session that never was panned by the artist ends with the
/// canvas exactly where it began.
struct ViewportFollow {

    /// Clear air kept between the box and the edge of what the artist can see. The grips stand about a
    /// dozen points off the box's own edges, and the rotate knob three dozen above the top one, so this
    /// keeps every grip a finger can reach on the glass.
    static let margin: CGFloat = 24

    /// The vertical pan, in screen points, that puts `box` inside `visible` with `margin` to spare — the
    /// least one, and zero when it already is. A box too tall for the room keeps its **top** in view,
    /// which is where the words start.
    static func pan(toKeep box: CGRect, within visible: CGRect) -> CGFloat {
        let top = visible.minY + margin, bottom = visible.maxY - margin
        if box.height >= bottom - top || box.minY < top { return top - box.minY }
        if box.maxY > bottom { return bottom - box.maxY }
        return 0
    }

    /// How far this session has panned the canvas — what `end()` gives back.
    private(set) var added: CGFloat = 0
    private var isLive = false
    private var yielded = false

    /// A text session is live and its box stands at `box` on the screen, with `visible` the part of the
    /// canvas the artist can see. Answers the pan to add to the canvas now.
    mutating func follow(box: CGRect, within visible: CGRect) -> CGFloat {
        isLive = true
        guard !yielded else { return 0 }
        let pan = Self.pan(toKeep: box, within: visible)
        added += pan
        return pan
    }

    /// The artist began to pan, pinch or turn the canvas. While a session is live that makes the view
    /// theirs for the rest of it.
    mutating func artistNavigated() {
        if isLive { yielded = true }
    }

    /// The session is over. Answers the pan that gives the canvas back — nothing when the artist took the
    /// view over, or when there was no session — and forgets the session.
    mutating func end() -> CGFloat {
        guard isLive else { return 0 }
        let back = yielded ? 0 : -added
        self = ViewportFollow()
        return back
    }
}
