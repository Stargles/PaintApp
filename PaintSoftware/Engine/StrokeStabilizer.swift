import CoreGraphics

/// Smooths raw touch input into a trailing "follow" position — the "Streamline"/"lag brush"
/// technique used by Procreate and similar apps: rather than stamping exactly at the raw touch
/// position, the smoothed point continuously chases the raw point, moving only a fraction of the
/// remaining distance on each update. A higher `stabilization` makes that fraction smaller, so the
/// smoothed point both trails further behind the raw touch and reacts more slowly to jitter —
/// which is exactly what damps a shaky hand's noise out of a stroke's line.
///
/// Pure `CoreGraphics`/`CGPoint` math only — no UIKit — so this can be exercised by plain unit
/// tests against synthetic input, without a simulator or a real touch/pencil.
struct StrokeStabilizer {
    /// 0...1. 0 disables smoothing entirely (each `update` snaps straight to the raw input). 1 is
    /// maximal smoothing/lag, though `update` still guarantees forward progress (see below) so a
    /// held-still-then-moving pencil doesn't stall forever short of the raw point.
    var stabilization: Double {
        didSet { stabilization = max(0, min(stabilization, 1)) }
    }

    private(set) var current: CGPoint?

    init(stabilization: Double) {
        self.stabilization = max(0, min(stabilization, 1))
    }

    /// Snaps the trailing point to `point` — call at stroke start so the very first stamp lands
    /// exactly where the user touched down, rather than smoothing in from wherever a previous
    /// (unrelated) stroke happened to leave the trailing point.
    mutating func reset(to point: CGPoint) {
        current = point
    }

    /// Feeds one raw input sample and returns the smoothed position to actually stamp at. Safe to
    /// call before `reset(to:)` — the first call in that case seeds `current` at `rawPoint` and
    /// returns it unchanged, so a caller that forgets the explicit reset still gets sane behavior
    /// instead of smoothing in from `(0, 0)`.
    mutating func update(rawPoint: CGPoint) -> CGPoint {
        guard let existing = current else {
            current = rawPoint
            return rawPoint
        }
        // Fraction of the remaining distance to the raw point closed per update. At
        // stabilization == 0 this is 1 (snap straight to the raw point, no lag at all); as
        // stabilization -> 1 it approaches a small floor (0.05) rather than 0, so the trailing
        // point still keeps catching up on every update instead of asymptotically stalling.
        let followFraction = 1 - (0.95 * stabilization)
        let next = CGPoint(
            x: existing.x + (rawPoint.x - existing.x) * followFraction,
            y: existing.y + (rawPoint.y - existing.y) * followFraction
        )
        current = next
        return next
    }
}
