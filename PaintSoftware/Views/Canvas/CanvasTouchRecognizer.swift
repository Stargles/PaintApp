import UIKit

/// **The canvas's one listener: every touch on the plane, told to `CanvasTouchCore` as the live set.**
///
/// It sits on the canvas plane's root (`CanvasPlaneView`), and each event it or a layer's stroke
/// recognizer hears is one `sync`: the whole contact set is rebuilt from `event.allTouches`, so what the
/// core believes is never older than the last event anybody on the canvas heard, and a touch UIKit
/// stopped reporting is gone at the next one. Idempotent within an event, which is what lets a stroke
/// recognizer that hears a landing first ask about it before this one has (`mayDraw`).
final class CanvasTouchRecognizer: ListeningGestureRecognizer {

    /// The view whose points the core is told, one the navigation does not move.
    weak var space: UIView?
    var onEvent: ((CanvasTouchCore.Event) -> Void)?
    /// Whether the view may follow these touches: false while a drag owns one of them.
    var mayNavigate: ((Set<UITouch>) -> Bool)?

    private(set) var core = CanvasTouchCore()

    private struct Known {
        let id: Int
        let touch: UITouch
        let landedAt: TimeInterval
    }
    private var known: [ObjectIdentifier: Known] = [:]
    private var nextID = 0

    /// Whether the canvas has heard of this touch and not of its end.
    func hears(_ touch: UITouch) -> Bool { known[ObjectIdentifier(touch)] != nil }

    /// Whether this touch is the one that may draw, as of `event`.
    func mayDraw(_ touch: UITouch, in event: UIEvent) -> Bool {
        sync(with: event)
        return known[ObjectIdentifier(touch)].map { $0.id == core.drawer } ?? false
    }

    private func sync(with event: UIEvent) {
        guard let plane = view, let all = event.allTouches else { return }
        var ends: [Int: CanvasTouchCore.End] = [:]
        var live: [ObjectIdentifier: Known] = [:]
        for touch in all {
            let key = ObjectIdentifier(touch)
            let old = known[key]
            switch touch.phase {
            case .began, .moved, .stationary:
                // UIKit hands a finished touch's object out again: one that begins after it landed is
                // another touch.
                if let old, touch.phase != .began || event.timestamp <= old.landedAt {
                    live[key] = old
                } else if touch.view?.isDescendant(of: plane) == true {
                    live[key] = Known(id: nextID, touch: touch, landedAt: event.timestamp)
                    nextID += 1
                }
            case .ended:
                if let old { ends[old.id] = .lifted }
            case .cancelled:
                if let old { ends[old.id] = .cancelled }
            default:
                break
            }
        }
        known = live
        let contacts = live.values.sorted { $0.id < $1.id }.map {
            CanvasTouchCore.Contact(id: $0.id, kind: $0.touch.type == .pencil ? .pencil : .finger,
                                    point: $0.touch.location(in: space))
        }
        let events = core.update(contacts, ends: ends, at: event.timestamp) {
            mayNavigate?(Set(live.values.map(\.touch))) ?? true
        }
        for event in events { onEvent?(event) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        sync(with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        sync(with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        sync(with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        sync(with: event)
    }
}
