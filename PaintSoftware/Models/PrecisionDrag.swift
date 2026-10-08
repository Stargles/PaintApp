import CoreGraphics

/// **What a touch that joins a handle's drag does to it** — TODO (146), the owner's *"when in the move
/// menu, … if the user presses a finger onto the canvas while moving the box with their pen, it makes
/// the move more precise, like 5x less than the pen's movement"*, and TODO (151), *"snaps in 15 degree
/// increments … when rotating any rotate node"*. A finger on the glass means **more precision**, and
/// what precision is depends on the handle:
///
///  * **A handle that moves or sizes the box** (the body, a corner, an edge) gets its point slowed to a
///    fifth.
///  * **A handle that turns it** (a knob, or either end of a smart-shape line, which turns the line
///    about its other end) is not slowed — a turn a fifth as fast is not what an artist reaching for a
///    round angle wants — and reports `snapsAngle` instead, which the turn rounds to
///    `RotationAngle.snapIncrement`.
///
/// Both Move overlays take their drags from a point — `ObjectTransformOverlayView`'s raw touches and
/// `FloatingPieceOverlayView`'s pans — and every handle reads that point the same way: the body as a
/// delta from where it began, a corner as the grip's position, the knobs as an angle about the centre.
/// So the slowing lives **in the point, once, upstream of all of them**: a drag asks this for the
/// pen's *effective* point and everything downstream — the move, the scale, the Distort corner, and the
/// take a transformation layer's box records — is slower by construction, with no handle having to
/// know. That is also why *"this should work with recording movement too"* costs the recorder nothing:
/// its samples are the poses these points produce.
///
/// ## Re-anchoring, so nothing jumps
///
/// A touch landing or lifting changes the *rate* (1 or 1/5) and not the position, so the mapping is
/// re-based at the last point the pen reported: `effective = anchorEffective + (raw − anchorRaw) ·
/// rate`. The re-base is at the **previous** raw point rather than the one that revealed the change,
/// which is what makes a finger that lands while the pen is held still slow the very next movement
/// instead of letting its first step through at full speed.
///
/// ## Which touch counts
///
/// **Only one that joined after the drag began** — `JoinedTouches`, the smart-shape snap's rule too, for
/// its reason: a hand already resting on the glass is not the gesture, and a palm must not make every
/// drag a fifth as fast. The baseline is the count of touches on the canvas when the drag began, the
/// dragging touch included — whatever its type, which is also what lets a finger-driven drag with a
/// second finger stand in for the pen in a test.
///
/// A pure value with no clock and no view, so `MoveBoxPrecisionLogicTests` walks every ordering of a
/// landing, a lift and a movement without a simulator. XCUITest cannot synthesise a Pencil, and this is
/// what lets the rule be asserted anyway.
struct PrecisionDrag {

    /// How many times slower the point moves while precision is held — the owner's "5x less".
    static let slowdown: CGFloat = 5

    private var rawAnchor: CGPoint
    private var effectiveAnchor: CGPoint
    private var lastRaw: CGPoint
    private var joinedTouches: JoinedTouches
    /// Whether the handle sets the box's angle — see the type's note. Latched at the drag's start.
    private let turns: Bool
    /// Whether a touch had joined as of the last point asked for.
    private var isJoined = false

    /// Whether the last point asked for was slowed. Read by nothing in the drag itself; it is how a
    /// test says which rate the pen is moving at. Never true on a handle that turns.
    var isPrecise: Bool { isJoined && !turns }

    /// Whether the turn this drag makes is to land on a round angle: a touch has joined, as of the
    /// last point asked for, and the handle turns the box. The turn rounds its angle with
    /// `RotationAngle.snapped`.
    var snapsAngle: Bool { isJoined && turns }

    /// - Parameters:
    ///   - point: where the drag began, which is also where the effective point starts.
    ///   - touchesDown: the touches on the canvas at that moment, **including the dragging one** —
    ///     the baseline everything after is measured from.
    ///   - turns: whether the handle sets the box's angle rather than moving or sizing it.
    init(startingAt point: CGPoint, touchesDown: Int, turns: Bool = false) {
        rawAnchor = point
        effectiveAnchor = point
        lastRaw = point
        joinedTouches = JoinedTouches(baseline: touchesDown)
        self.turns = turns
    }

    /// The point the drag should act on for the pen's current position `raw`, with `touchesDown`
    /// touches on the canvas now. A handle that turns always gets `raw` back: what a joined touch does
    /// to it is `snapsAngle`, read after this call.
    mutating func point(for raw: CGPoint, touchesDown: Int) -> CGPoint {
        let joined = joinedTouches.joined(with: touchesDown) > 0
        guard !turns else {
            isJoined = joined
            return raw
        }
        if joined != isJoined {
            effectiveAnchor = mapped(lastRaw)
            rawAnchor = lastRaw
            isJoined = joined
        }
        lastRaw = raw
        return mapped(raw)
    }

    private func mapped(_ raw: CGPoint) -> CGPoint {
        // A drag that has never been slowed hands back the pen's own point, to the bit —
        // `a + (b − a)` is not always `b`, and a drag nobody slowed must be exactly what it was.
        if !isPrecise && effectiveAnchor == rawAnchor { return raw }
        let rate = isPrecise ? 1 / Self.slowdown : 1
        return CGPoint(x: effectiveAnchor.x + (raw.x - rawAnchor.x) * rate,
                       y: effectiveAnchor.y + (raw.y - rawAnchor.y) * rate)
    }
}
