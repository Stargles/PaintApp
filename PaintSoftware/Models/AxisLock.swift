import CoreGraphics

/// **What a touch that joins a graph-editor drag does to it** — TODO (166), the owner's *"when the
/// user is in the graph editor and is moving a key, pressing and holding their other finger down
/// anywhere should snap it to a cardinal axis (laterally through time, or vertically for the
/// variable)"*, asked to be *"pretty much the same second finger tap hold that snaps smart shapes"*.
///
/// It is. A finger on the glass means **more control** and what control is depends on the drag: a
/// handle drag slows to a fifth or rounds its turn (`PrecisionDrag`), a smart shape rounds to 15°
/// (`CanvasView.Coordinator`), and a key drag keeps to one axis. All three count the touch the same
/// way — `JoinedTouches`, so a hand already resting on the glass when the drag began is not the
/// gesture — and read the count off the window's one counter (`ModifierHold`).
///
/// ## Which axis, and when it is decided
///
/// **Once, from the way the drag is going, and held until the finger lifts.** The axis is the larger
/// of the translation's two components at the moment the lock has a direction to read: when the
/// finger lands on a drag already under way, that moment; when it was down first, the first tick of
/// the drag that travels `decisiveTravel`, before which a drag has no direction worth reading.
///
/// Held rather than re-read on every tick, because the alternative flips: a drag along the diagonal
/// is within a point of either axis for the whole of its length, and re-reading would swing the key
/// between *time only* and *value only* — a jump of the drag's whole travel — on every wobble of the
/// finger. A held axis does what the artist asked for and can be changed the way they would expect:
/// lift the finger, and press it again once the drag is going the other way.
///
/// ## What the lock reads and writes
///
/// The drag's **translation from where the finger landed**, which is what `TimelineGraphBand.moves`
/// and `draggingHandle` consume, so the lock sits in front of them and neither knows it is there. The
/// locked component is zeroed and the other is the finger's own, so the key follows the finger's
/// shadow on the axis and lets go of it when the second finger lifts — it **jumps to the finger**
/// then, as the shape snap's does, rather than staying displaced from it for the rest of the drag.
///
/// A pure value with no clock and no view, so `AxisLockLogicTests` walks every ordering of a landing,
/// a lift and a movement without a simulator.
struct AxisLock {

    /// The two directions a graph drag can be kept to.
    enum Axis: Equatable {
        /// Along the frame axis: the key retimes and holds its value.
        case time
        /// Along the value axis: the key changes value and holds its frame.
        case value
    }

    /// How far a drag must have travelled before its direction is read — UIKit's own pan slop, below
    /// which a finger is wobbling rather than going anywhere.
    static let decisiveTravel: CGFloat = 10

    private var joinedTouches: JoinedTouches

    /// The axis the drag is held to, or nil while no touch has joined it, or one has but the drag has
    /// not yet travelled `decisiveTravel`.
    private(set) var axis: Axis?

    /// - Parameter touchesDown: the touches down when the drag began, **including the dragging one** —
    ///   the baseline everything after is measured from.
    init(touchesDown: Int) {
        joinedTouches = JoinedTouches(baseline: touchesDown)
    }

    /// The translation the drag should act on for the finger's own `raw`, with `touchesDown` touches
    /// down now. `raw` comes back untouched until a touch has joined and the drag has a direction.
    mutating func translation(for raw: CGSize, touchesDown: Int) -> CGSize {
        guard joinedTouches.joined(with: touchesDown) > 0 else {
            axis = nil
            return raw
        }
        if axis == nil, hypot(raw.width, raw.height) >= Self.decisiveTravel {
            axis = abs(raw.width) >= abs(raw.height) ? .time : .value
        }
        switch axis {
        case .time: return CGSize(width: raw.width, height: 0)
        case .value: return CGSize(width: 0, height: raw.height)
        case nil: return raw
        }
    }
}
