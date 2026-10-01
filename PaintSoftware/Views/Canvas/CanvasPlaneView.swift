import UIKit

/// **A view in the canvas plane: its coordinates are canvas points, and its touch region has no edge.**
///
/// The owner, TODO (121): *"whatever is outside the canvas still should be counted, as if the canvas
/// does extend further, with the only difference being the stuff outside the border just isnt
/// rendered."* The model already works that way — a vector stroke, a Move box, a smart shape's
/// handle, a text box and a lassoed piece can all sit past the paper's edge, and nothing in
/// `CanvasManager` asks where the paper is. Touch did not, and for one reason: `CanvasView`'s
/// container and everything pinned to it are sized to the document, and `UIView.hitTest` refuses a
/// point outside the receiver's bounds without asking its subviews. So "on the canvas" meant "inside
/// the document rectangle" for input alone, and every feature that reached past it needed its own
/// way round the gate.
///
/// **This is the one rule that replaces those ways round it.** Every view in the plane — the
/// container, each layer host and its stroke view, and every overlay pinned to them — is one of
/// these, so `point(inside:)` is true wherever the artist can touch: the host that holds the plane
/// clips it to the canvas area, and nothing else bounds it. A touch on the surround is then
/// hit-tested exactly as a touch on the paper is — front to back, each overlay answering by its own
/// claim (`claimsTouch(at:)`) and never by its bounds, down to the active layer's stroke view or the
/// container itself — and it reaches the same recognizers, converted into the same canvas points.
/// Only rendering stops at the paper.
///
/// An overlay that claims only part of the plane overrides `hitTest` and answers from its own
/// geometry; a view that claims all of it (the stroke view, a capturing selection overlay, a raster
/// Move piece) inherits this answer. Neither consults `bounds`, so neither has an edge to forget.
class CanvasPlaneView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }
}
