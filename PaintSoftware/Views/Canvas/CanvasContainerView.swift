import UIKit

/// An overlay whose grips can legitimately sit **outside the canvas rectangle** — a Move box scaled
/// larger than the document has all four of its corners out there — and which therefore has to be
/// offered touches `CanvasContainerView` would otherwise never pass on.
///
/// The answer is deliberately narrower than the view's own `hitTest`: only a *grip*, never the
/// overlay's body or move band. Off-canvas is empty space that today reaches nothing at all
/// (`CanvasContainerView`'s doc comment has the measurement), so claiming a grip out there takes
/// nothing away from anyone, while claiming a band would hand a box larger than the canvas every
/// touch on the black surround.
protocol OffCanvasHandleHitTesting: UIView {
    /// The grip at `point` — in **this view's** own coordinates — or nil if there is none there.
    /// Asked only for points outside the canvas rectangle.
    func offCanvasHandle(at point: CGPoint, with event: UIEvent?) -> UIView?
}

/// `CanvasView`'s zoom/pan container: the view every layer host and every overlay is pinned to, and
/// the view all of the canvas's own gesture recognizers live on.
///
/// **Its bounds are exactly the document** — `CanvasView.Coordinator.hostBoundsDidChange` sets
/// `bounds` to `canvasSize` and `applyTransform` puts the zoom on `transform` — so everything
/// outside the artwork is outside this view. `UIView.hitTest` only recurses into subviews once the
/// point is inside the receiver's own bounds, so a grip drawn past the canvas edge received no
/// touches at all: the overlays' own `hitTest` overrides, which are written to accept exactly such a
/// point (`ObjectTransformOverlayView.hitTest` says so in as many words), were never asked. That is
/// the owner's 2026-09-05 report — *"I cannot grab a move node that is outside of the canvas. If the
/// box is too big to fit on the canvas, then I got to first move the box to bring one of the nodes
/// inside the canvas and then tap that node to scale it down."*
///
/// The handle is drawn where it is and stays there; the owner ruled that half correct
/// (*"the move handle right now goes off the canvas, thats fine. I just want to be able to adjust
/// it"*). Only the reach changes.
///
/// **Nothing is taken away by this.** Every canvas recognizer — pan, pinch, rotation, the taps, the
/// fill press, the catch-all — is added to this view, so a point outside these bounds hit-tested to
/// the *host* and reached no recognizer whatsoever before this override existed. The off-canvas
/// surround was dead to touch, and now a grip out there is the one thing in it.
final class CanvasContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = super.hitTest(point, with: event) { return hit }
        // `super` returns nil in two cases and only one of them is ours: the point is outside these
        // bounds, or this view is not taking touches at all. The guard is what separates them —
        // without it a hidden or disabled container would still hand out grips.
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        // Front to back, the order UIKit itself would ask in. Each overlay gates itself on its own
        // live-ness — `ObjectTransformOverlayView` through the same `claimsTouch` its `hitTest`
        // uses — so none of that is restated here where it could drift.
        for case let overlay as OffCanvasHandleHitTesting in subviews.reversed() {
            if let handle = overlay.offCanvasHandle(at: overlay.convert(point, from: self), with: event) {
                return handle
            }
        }
        return nil
    }
}
