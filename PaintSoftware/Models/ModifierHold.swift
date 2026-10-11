import UIKit

/// **The one rule for a finger held down as a modifier** — TODO (168), the owner's *"a finger used as
/// the hold is ignored when it lifts"*. A finger on the glass beside a drag means **more control**: a
/// graph node keeps to one axis (`AxisLock`), a Move box slows to a fifth or rounds its turn
/// (`PrecisionDrag`), a smart shape rounds to 15°. Those three read the finger as a *count*
/// (`JoinedTouches`); this is the half that says what the finger itself does, which is nothing.
///
/// ## When a touch becomes a hold
///
/// **The instant it lands, if a drag that takes a modifier is live and a touch is already down.** Not
/// after it has stayed down for a while: a quick tap during a drag is still the artist reaching for
/// more control, and a finger that could act until it had been watched would act on exactly the quick
/// ones. A touch is therefore never a hold *and* a tap; which one it is is settled at touch-down and
/// does not change.
///
/// ## What a hold does
///
/// **Nothing, wherever it lands, until it lifts** — it hit-tests to `HoldShieldView`, which has no
/// recogniser and no responder, so the control it landed on, the recogniser that would have read its
/// lift, the canvas that would have painted its dab and the slider it would have grabbed never hear of
/// it. It is *counted* all the same — the window's one `TouchCountRecognizer` sees every touch whatever
/// view it is bound to — because the count is the whole of the modifier.
///
/// **If the drag ends first, the hold goes on being one.** The touch is bound to the shield for its
/// whole life, so it stays inert until it lifts; a new drag that starts while it is still down takes it
/// as a resting hand (its baseline already counts it, `JoinedTouches`) and the hold does not become the
/// new drag's modifier.
///
/// ## When a touch is *not* a hold
///
/// With no modifier-aware drag live, a landing touch is whatever it always was: the first finger of a
/// two-finger pan or pinch, a tap, a scrub, a stroke. The rule can never swallow the first touch of a
/// gesture (a touch needs another to be down), and it stands down on its own when every touch lifts,
/// so a drag that never reports its end cannot leave the screen deaf.
///
/// A class with no view and no clock, so `ModifierHoldLogicTests` walks the rule without a simulator.
final class ModifierHold {

    /// How many touches are down, as the window's one counter reports them. A protocol rather than the
    /// recogniser, which is a view-layer type this model must not reach for.
    protocol Counter: AnyObject {
        /// Every touch on the window, the pencil included.
        var activeCount: Int { get }
        /// The touches that are not the pencil.
        var fingerCount: Int { get }
        /// The count with `touch` in it, whether or not the counter has heard of it yet.
        func activeCount(including touch: UITouch?) -> Int
    }

    /// The window's counter, installed by `ModifierHoldHost` for as long as the editor is on a window.
    weak var counter: Counter?

    /// Told when the count changes, for whoever must re-read it at that moment (the smart shape's snap).
    var onTouchesChanged: (() -> Void)?

    private struct Source {
        weak var owner: AnyObject?
        let isDragLive: () -> Bool
    }
    private var sources: [ObjectIdentifier: Source] = [:]

    /// Declares a drag that takes a modifier: `isDragLive` answers whether one is under way **right
    /// now**, asked fresh at every touch-down. One source per `owner`, which is held weakly and whose
    /// source goes with it; a second registration replaces the first.
    func register(_ owner: AnyObject, isDragLive: @escaping () -> Bool) {
        sources[ObjectIdentifier(owner)] = Source(owner: owner, isDragLive: isDragLive)
    }

    /// Whether a touch landing now is a hold. Asked at hit-test, once per landing touch.
    var claimsLanding: Bool {
        var dragLive = false
        for (key, source) in sources {
            if source.owner == nil {
                sources.removeValue(forKey: key)
            } else if source.isDragLive() {
                dragLive = true
            }
        }
        return Self.claims(dragLive: dragLive, touchesDown: counter?.activeCount ?? 0)
    }

    /// The rule, as a function of its two inputs. A touch needs another to be down — a drag's own
    /// touch is never a hold, and a stale `dragLive` with the glass empty cannot swallow anything.
    static func claims(dragLive: Bool, touchesDown: Int) -> Bool {
        dragLive && touchesDown >= 1
    }

    // MARK: - Counting

    /// How many touches are down, with `touch` counted whether or not the counter has heard of it yet.
    /// Zero until the editor is on a window.
    func touchesDown(including touch: UITouch?) -> Int {
        counter?.activeCount(including: touch) ?? 0
    }

    /// The touches that are not the pencil. A pen stroke's "a finger joined" is `fingers >= 1`.
    var fingers: Int { counter?.fingerCount ?? 0 }
}
