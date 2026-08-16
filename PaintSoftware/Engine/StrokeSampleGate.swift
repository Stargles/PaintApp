import CoreGraphics

/// Decides which of the touch samples arriving during a stroke are worth **storing** as vector
/// geometry. Nothing here changes where dabs land: `BrushStamper.advance` has always walked the
/// recorded path at a fixed *distance*, so this is about the size of the shape a stroke leaves
/// behind in the document, not about how it is drawn.
///
/// ## Why it exists
///
/// A pencil resting on the glass keeps delivering samples at ~120 Hz whether or not it has moved,
/// and `StrokeCanvasView.recordVectorSample` used to append every one of them unconditionally. So a
/// two-second pause mid-stroke stored ~240 points describing a single location, and the size of a
/// stroke was a function of **how long the artist took** rather than of how long the line is. Those
/// points are persisted with the document, copied wholesale into every `DabLattice` when the stroke
/// is cut, walked by `StrokeGeometry.capsuleChain` on every erase, and fed to interpolation's
/// registration.
///
/// The rule is therefore distance, not time: a sample is stored only once the pen has travelled
/// `minimumTravel` from the last stored one. What a line costs now scales with its length.
///
/// ## Why pressure gets a way past the gate
///
/// A pen held still while pressure changes is a real drawable event and a pure distance gate deletes
/// it. The mechanism is specific and worth naming, because it is not "the dab at that point gets
/// thicker": `BrushStamper.stampStroke` emits *no* dabs while the path is not advancing, so a
/// stationary swell draws nothing by itself. What it does is set `lastPressure`, which is the value
/// the pressure ramp starts from across the **next** segment. Drop the swell and the stroke resumes
/// at the pressure the pen had before the pause, then ramps up over the first segment — a press-then-
/// move starts thin and fattens instead of starting fat. Measured on a synthetic hold: without the
/// escape a 0.2 → 0.9 swell carries 0.200 into the resumed drag instead of 0.900.
///
/// `StrokeGeometry.capsuleChain` reads the same per-sample pressure for the eraser's footprint, so
/// the escape keeps erase width honest for the same reason.
///
/// Pure `CoreGraphics` — no UIKit, no `Brush` — so the rule can be exercised headless against
/// synthetic sample sequences, the same bargain `StrokeStabilizer` makes.
struct StrokeSampleGate {
    /// How far the pen must travel from the last stored sample before the next one is kept.
    /// `BrushStamper.recordSpacing` derives this from the brush; see there for the size.
    var minimumTravel: CGFloat

    /// How much pressure must differ from the last stored sample to keep it anyway, at a standstill.
    ///
    /// 0.02 of the 0...1 range moves a 20pt brush's dab diameter by about a third of a point under a
    /// typical size-to-pressure curve — below the width the renderer can resolve, so a finer
    /// threshold stores points describing a difference that cannot be drawn. Deriving it per brush
    /// from `BrushTipDynamics` was considered and dropped: pressure drives width *and* alpha through
    /// two separate curves, so an honest derivation needs both, and for every preset in
    /// `BrushLibrary` it lands within a factor of two of this constant.
    var minimumPressureChange: CGFloat

    /// The last sample actually kept — what both thresholds are measured against. Nil until the
    /// first sample of a stroke, which is always kept.
    private var lastStored: (point: CGPoint, pressure: CGFloat)?

    init(minimumTravel: CGFloat, minimumPressureChange: CGFloat = 0.02) {
        self.minimumTravel = minimumTravel
        self.minimumPressureChange = minimumPressureChange
    }

    /// Starts a new stroke: the next sample offered is kept whatever it is.
    mutating func reset() { lastStored = nil }

    /// Whether this sample is worth storing — and, when it is, remembers it as the one the next
    /// sample is measured against.
    ///
    /// Pass `unconditionally: true` for a sample that is not optional geometry whatever the
    /// thresholds say. That is the **lift point**, and it is not an edge case: artists decelerate
    /// into the end of nearly every stroke, so the last few samples each fail the travel test
    /// individually and a gate without this special case shaves the tail off the stroke — it ends
    /// short of where the pen actually stopped. The endpoint is also the one sample that cannot be
    /// reconstructed by interpolating between its survivors, because it has no successor.
    mutating func admits(_ point: CGPoint, pressure: CGFloat, unconditionally: Bool = false) -> Bool {
        guard let last = lastStored else {
            lastStored = (point, pressure)
            return true
        }
        let travelled = hypot(point.x - last.point.x, point.y - last.point.y) >= minimumTravel
        let pressed = abs(pressure - last.pressure) >= minimumPressureChange
        guard unconditionally || travelled || pressed else { return false }
        lastStored = (point, pressure)
        return true
    }
}
