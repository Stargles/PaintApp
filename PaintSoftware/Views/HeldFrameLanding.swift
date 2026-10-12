import Foundation

/// **Whether the whole-frame picture of a held grade stays over the canvas** — TODO (179).
///
/// While an effect slider is held the canvas shows a whole-frame composite of the held grade, drawn
/// as fast as the device can (`CanvasView.Coordinator`'s held frame). At the lift the grade is written
/// once and the document's key moves — and the canvas's own picture of the new key, the bake, takes a
/// bake's length to arrive (~350 ms on the owner's iPad, longer at 4096²). Taking the held frame down
/// at the lift would flash the old grade for that long; leaving it up past a later edit would hide
/// that edit. So it **stays up until the canvas's own picture is current for the key the canvas is
/// on**, and comes down the moment the key moves on past the one it landed on — `.moving`'s rule after
/// a transform edit's lift, and `UnlandedInk`'s for a stroke, asked of the whole frame.
///
/// **Outside `SandwichPresentation.next`, deliberately.** The held frame covers whatever the
/// presentation shows, so the state machine needs no new case; this only answers whether the cover is
/// still needed. A revert needs nothing of its own: the document never moved, so the first pass after
/// it finds the canvas's picture already current and the frame comes down.
///
/// Pure and headless, so the rule is pinned where the fast tier can reach it.
struct HeldFrameLanding: Equatable {

    enum Phase: Equatable {
        /// Nothing held, nothing landing — no held frame on screen.
        case idle
        /// A grade is under the finger.
        case held
        /// The finger let go; waiting for the canvas's own picture. The key is the one the first pass
        /// after the lift found the canvas on — nil until that pass has run.
        case landing(SandwichKey?)
    }

    private(set) var phase: Phase = .idle

    /// Whether the held frame should be on screen.
    var isUp: Bool { phase != .idle }

    /// Whether a grade is held right now — reported on every tick and every pass.
    mutating func update(held: Bool) {
        if held {
            phase = .held
        } else if phase == .held {
            phase = .landing(nil)
        }
    }

    /// **One pass of the canvas.** `key` is the key the canvas is on, nil when the compositor is not
    /// drawing it at all (the hosts then draw the document as it is, so there is nothing to wait for);
    /// `pictureIsCurrent` is whether the picture the canvas shows under the held frame is of `key`.
    mutating func pass(key: SandwichKey?, pictureIsCurrent: Bool) {
        guard case .landing(let landedOn) = phase else { return }
        guard let key, !pictureIsCurrent else {
            phase = .idle
            return
        }
        if let landedOn, landedOn != key {
            // Something moved the document past what the held frame shows: it is no longer the truth.
            phase = .idle
            return
        }
        phase = .landing(key)
    }
}
