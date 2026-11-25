import CoreGraphics
import Foundation

/// **Who a touch on the canvas belongs to, and where the fingers have taken the view** — the whole of
/// canvas navigation, the two- and three-finger undo and redo taps, and the question "may this touch
/// draw?", as one pure state machine.
///
/// **Why the app does this itself.** A `UIPanGestureRecognizer`, a pinch, a rotation, the taps and the
/// layer's stroke recognizer, tied by failure requirements so a stroke could hand over to a pan, are one
/// component UIKit resets only as a whole. On the owner's iPad 43 flights show that component left
/// terminal: a third finger landing in an event of its own, a contact the system cancels and begins
/// again, a palm cancelled at once. Every recognizer in it was then deaf for good, or the new contact
/// reached the pan and not the pinch. The recognizers that never leave `.possible` were right in all 43,
/// so the canvas's are of that kind (`ListeningGestureRecognizer`) and what UIKit would have decided is
/// decided here.
///
/// **It keeps nothing UIKit could contradict.** `update` is handed *every* contact on the canvas plane
/// as it stands after an event, not a list of changes, so a contact that ended without anybody being told
/// is simply absent from the next set and a contact that was cancelled and begun again is a new one:
/// the pair is baselined afresh and the view carries on from where it is. With no contacts left the
/// core is at rest, whatever came before.
///
/// | on the canvas plane | who has it |
/// |---|---|
/// | a lone finger | it may draw (`drawer`), and it may be the first of a tap |
/// | a second finger, in the same event or a later one | a pair: nobody draws, and a finger's stroke is handed over |
/// | the pair past its slop | the view follows the fingers — position at once, zoom and turn each past their own slop |
/// | a pair, when a drag already holds one of its touches | that drag (`mayNavigate`); the pair is spent |
/// | a third finger before the pair moved | a three-finger tap, unless the hand moves well past the slop |
/// | a finger joining or leaving a moving pair | the view holds, then carries on with whichever two are down |
/// | a pencil | it draws, and every finger down with it is a palm for the rest of its life |
/// | a pencil while two fingers move the view | nobody: the view keeps moving |
/// | a contact that is cancelled | nothing but the end of that contact |
struct CanvasTouchCore {

    enum Kind { case finger, pencil }

    /// One contact as it is after an event. `id` is the caller's, and is never reused.
    struct Contact: Equatable {
        let id: Int
        let kind: Kind
        /// Screen points, in a space the view being moved does not move.
        let point: CGPoint
    }

    /// How a contact that is no longer on the glass left it.
    enum End { case lifted, cancelled }

    enum Event: Equatable {
        case countChanged(Int)
        /// The touch that may draw may not any more. What becomes of the ink is the reason's to say.
        case strokeRevoked(Int, StrokeGiveUp)
        case navigationBegan(CGPoint)
        /// `scale` and `turn` are the whole gesture's so far, 1 and 0 at its start.
        case navigationMoved(centroid: CGPoint, scale: CGFloat, turn: CGFloat)
        /// The fingers moving the view are not the ones they were: the same content, now held here.
        case navigationRebased(CGPoint)
        case navigationEnded
        case tapped(fingers: Int)

        /// Arrives with every movement of the fingers, so a log that is kept short leaves it out.
        var isContinuous: Bool {
            if case .navigationMoved = self { return true }
            return false
        }
    }

    /// How far the fingers travel before the view follows, how far apart or together before it zooms and
    /// how far round before it turns. The last two are taken off the gesture as well as waited for. All
    /// three are what UIKit's pan, pinch and rotation use — MEASURED on the iPadOS 26.5 simulator.
    static let panSlop: CGFloat = 10
    static let zoomSlop: CGFloat = 8
    static let turnSlop: CGFloat = 5 * .pi / 180
    /// Three fingers put down to redo wander further than two before they mean to move the view.
    static let thirdFingerSlopFactor: CGFloat = 3
    /// First landing to last lift, and first landing to last, for the taps — UIKit's own tap's, which
    /// these replaced.
    static let tapDuration: TimeInterval = 1.5
    static let tapLandingWindow: TimeInterval = 0.75

    private struct Touch {
        let id: Int
        let kind: Kind
        var point: CGPoint
        /// A palm: down with a pencil, or with a drag that owns the canvas. It moves nothing, whoever
        /// lifts first.
        var spent = false
    }

    /// The two fingers the view is following or may come to follow.
    private struct Pair: Equatable {
        let first: Int, second: Int
        let centroid: CGPoint, distance: CGFloat, angle: CGFloat

        func isOf(_ a: Touch, _ b: Touch) -> Bool { first == a.id && second == b.id }

        init(_ a: Touch, _ b: Touch) {
            first = a.id
            second = b.id
            centroid = CGPoint(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2)
            let dx = b.point.x - a.point.x, dy = b.point.y - a.point.y
            distance = max(hypot(dx, dy), 1)
            angle = atan2(dy, dx)
        }
    }

    private struct Navigation {
        var scale: CGFloat = 1
        var turn: CGFloat = 0
        var zooms = false
        var turns = false
        /// The distance and angle the next movement is measured from, once zooming or turning.
        var distance: CGFloat = 1
        var angle: CGFloat = 0
    }

    private struct Tap {
        let startedAt: TimeInterval
        var fingers: Int
    }

    private var touches: [Touch] = []
    private var pair: Pair?
    private var navigation: Navigation?
    private var tap: Tap?

    /// The contact that may draw, if one may.
    private(set) var drawer: Int?
    /// Two fingers have been down together since the first contact of this sequence landed, so what one of
    /// them does on its own — a tap, a lasso — is not what the hand is doing. Stands until the next
    /// sequence begins, because a tap is decided as its last finger lifts.
    private(set) var hadPair = false

    var count: Int { touches.count }
    var isNavigating: Bool { navigation != nil }
    /// How many of the contacts are fingers that may move the view.
    var fingerCount: Int { fingers.count }
    /// Nothing is on the canvas and nothing is waiting on a touch.
    var isAtRest: Bool { touches.isEmpty && pair == nil && navigation == nil && tap == nil && drawer == nil }

    /// - Parameters:
    ///   - contacts: every contact on the canvas plane after the event, newly landed ones included.
    ///   - ends: how each contact that has left went. One that is missing from both was never reported
    ///     as ending, and is taken as cancelled.
    ///   - mayNavigate: asked once, as the pair passes its slop.
    mutating func update(_ contacts: [Contact], ends: [Int: End] = [:], at time: TimeInterval,
                         mayNavigate: () -> Bool = { true }) -> [Event] {
        var events: [Event] = []
        let before = touches.count
        leave(contacts, ends: ends, &events)
        for index in touches.indices {
            if let contact = contacts.first(where: { $0.id == touches[index].id }) { touches[index].point = contact.point }
        }
        land(contacts, at: time, &events)
        if touches.count != before { events.insert(.countChanged(touches.count), at: 0) }
        navigate(mayNavigate: mayNavigate, &events)
        if touches.isEmpty, let tap {
            self.tap = nil
            if (2...3).contains(tap.fingers), time - tap.startedAt <= Self.tapDuration {
                events.append(.tapped(fingers: tap.fingers))
            }
        }
        return events
    }

    private mutating func leave(_ contacts: [Contact], ends: [Int: End], _ events: inout [Event]) {
        for touch in touches where !contacts.contains(where: { $0.id == touch.id }) {
            let cancelled = ends[touch.id, default: .cancelled] == .cancelled
            if cancelled { tap = nil }
            if touch.id == drawer {
                drawer = nil
                if cancelled { events.append(.strokeRevoked(touch.id, .interrupted)) }
            }
            touches.removeAll { $0.id == touch.id }
        }
    }

    private mutating func land(_ contacts: [Contact], at time: TimeInterval, _ events: inout [Event]) {
        let landings = contacts.filter { contact in !touches.contains { $0.id == contact.id } }
        guard !landings.isEmpty else { return }
        if touches.isEmpty {
            tap = Tap(startedAt: time, fingers: 0)
            hadPair = false
        }
        let fingersMoveTheView = navigation != nil && fingers.count >= 2
        touches += landings.map { Touch(id: $0.id, kind: $0.kind, point: $0.point) }

        if let pencil = landings.first(where: { $0.kind == .pencil }), !fingersMoveTheView {
            revokeDrawer(&events)
            drawer = pencil.id
        }
        if touches.contains(where: { $0.kind == .pencil }) {
            tap = nil
            if !fingersMoveTheView {
                for index in touches.indices where touches[index].kind == .finger { touches[index].spent = true }
            }
        } else if landings.count == 1, fingers.count == 1, navigation == nil {
            drawer = landings[0].id
        } else if fingers.count > 1 {
            revokeDrawer(&events)
        }
        if let tap {
            self.tap = time - tap.startedAt > Self.tapLandingWindow
                ? nil : Tap(startedAt: tap.startedAt, fingers: max(tap.fingers, touches.count))
        }
    }

    private mutating func revokeDrawer(_ events: inout [Event]) {
        guard let drawer else { return }
        self.drawer = nil
        events.append(.strokeRevoked(drawer, .handedOver))
    }

    /// The fingers that may move the view, in the order they landed.
    private var fingers: [Touch] { touches.filter { $0.kind == .finger && !$0.spent } }

    private mutating func navigate(mayNavigate: () -> Bool, _ events: inout [Event]) {
        let fingers = self.fingers
        guard !fingers.isEmpty else {
            pair = nil
            if navigation != nil {
                navigation = nil
                events.append(.navigationEnded)
            }
            return
        }
        guard fingers.count >= 2 else {
            pair = nil
            return
        }
        hadPair = true
        let now = Pair(fingers[0], fingers[1])
        guard let start = pair, start.isOf(fingers[0], fingers[1]) else {
            pair = now
            if navigation != nil {
                navigation?.distance = now.distance
                navigation?.angle = now.angle
                events.append(.navigationRebased(now.centroid))
            }
            return
        }
        guard navigation != nil || begins(from: start, to: now, fingers: fingers.count) else { return }
        if navigation == nil {
            tap = nil
            guard mayNavigate() else {
                for index in touches.indices where touches[index].kind == .finger { touches[index].spent = true }
                pair = nil
                return
            }
            navigation = Navigation()
            events.append(.navigationBegan(now.centroid))
        }
        follow(from: start, to: now)
        if let navigation {
            events.append(.navigationMoved(centroid: now.centroid, scale: navigation.scale, turn: navigation.turn))
        }
    }

    private func begins(from start: Pair, to now: Pair, fingers: Int) -> Bool {
        let factor = fingers > 2 ? Self.thirdFingerSlopFactor : 1
        return hypot(now.centroid.x - start.centroid.x, now.centroid.y - start.centroid.y) >= Self.panSlop * factor
            || abs(now.distance - start.distance) >= Self.zoomSlop * factor
            || abs(Self.shortest(now.angle - start.angle)) >= Self.turnSlop * factor
    }

    private mutating func follow(from start: Pair, to now: Pair) {
        guard var navigation else { return }
        let stretch = now.distance - start.distance
        if !navigation.zooms, abs(stretch) >= Self.zoomSlop {
            navigation.zooms = true
            navigation.distance = max(start.distance + Self.zoomSlop * (stretch < 0 ? -1 : 1), 1)
        }
        if navigation.zooms {
            navigation.scale *= now.distance / navigation.distance
            navigation.distance = now.distance
        }
        let round = Self.shortest(now.angle - start.angle)
        if !navigation.turns, abs(round) >= Self.turnSlop {
            navigation.turns = true
            navigation.angle = start.angle + Self.turnSlop * (round < 0 ? -1 : 1)
        }
        if navigation.turns {
            navigation.turn += Self.shortest(now.angle - navigation.angle)
            navigation.angle = now.angle
        }
        self.navigation = navigation
    }

    /// An angle as the shortest way round.
    private static func shortest(_ angle: CGFloat) -> CGFloat { remainder(angle, 2 * .pi) }
}
