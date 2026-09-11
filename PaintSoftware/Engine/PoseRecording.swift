import CoreGraphics
import Foundation

/// A live take of one **pose** channel — KEYFRAMES.md §5's second surface, the Move box.
///
/// `ValueRecording` is this type's scalar twin and every structural decision is shared with it, which
/// is the whole reason the two exist side by side rather than one generic over a protocol: §5.1 says a
/// quad surface *"needs its own intercept, because `ValueRecording` is scalar-only"*, and the three
/// steps a take takes — `record`, `resampled`, `simplified` — mean the same things here in a different
/// currency. Read that file's header for why each step exists; what follows is only what is different
/// about a shape.
///
/// ## What a pose take records, in the artist's terms
///
/// Recording a slider captures **one number** over time. Recording the Move box captures **a shape** —
/// four corners. Both then get thinned, so a straight drag lands as two keyframes rather than sixty.
/// The owner was asked to rule on "resampling and tolerance for a quad" on 2026-09-10 and answered
/// *"i have no idea what the question is"*, correctly: the phrasing was entirely ours, and the only
/// genuinely open part was **how much corner movement counts as a change worth keeping** — a number a
/// person can judge only by feel, after they can see a recorded drag. So it is one named constant
/// (`CanvasManager.recordingPoseSimplifyPoints`) and this file takes it as a parameter.
///
/// ## The three departures from `ValueRecording`, each forced
///
///  * **Interpolation between two samples is a straight lerp of the eight corner coordinates**, not
///    `PoseInterpolation.blend`. That function is the *authoring* interpolant — it decomposes a pair
///    of poses and is what the finished `TransformTrack` runs between two keys — and using it inside
///    the raw stream would invent motion between two positions the artist's hand actually passed
///    through, which is exactly the argument `ValueRecording.value(at:)` makes for being linear and
///    not eased. It also cannot fail, where `blend` is optional: a stream sampled at the pencil's own
///    rate has ~8 ms between samples and there is no degenerate pair to guard against.
///  * **The deviation a simplification measures is the largest distance any one corner is displaced**,
///    in canvas points. `ValueRecording` measures `|v − lerp|` in the channel's own units and argues
///    at length that frames and values have no exchange rate; corners do not have that problem —
///    every one of them is already in canvas points, which is a unit the artist can see. So the
///    tolerance here is **absolute** where the scalar one is a fraction of a range, and that is not an
///    inconsistency: a pose channel has no `uiRange` to take a fraction of, and "two canvas points" is
///    the same amount of visible movement on every document.
///  * **A `PoseQuad` carries a `box` beside its corners**, and the box is not interpolated — the
///    earlier of the two bracketing samples supplies it. Within one take the box is constant by
///    construction (it is the rest box latched when the Move box came up), so this never arises in
///    practice; carrying it rather than averaging it is what keeps a resampled pose a pose the same
///    `Homography(rect:to:)` can read, instead of one measured against a box halfway between two.
///
/// **Pure `CoreGraphics` + `Foundation` and no `CanvasManager`**, so every claim above is a fast-tier
/// test rather than a UI one — `ValueRecording`'s own rule, for its own reason.
struct PoseRecording: Equatable {

    /// One pose as the Move box reported it, with the wall time it was reported at. Absolute time, for
    /// `ValueRecording.Sample`'s reason: §5 rules that the recorder must keep real time.
    struct Sample: Equatable {
        var time: TimeInterval
        var pose: PoseQuad
    }

    private(set) var samples: [Sample] = []

    init(samples: [Sample] = []) {
        self.samples = samples
    }

    /// Takes one reported pose. **Out-of-order and duplicate timestamps are dropped rather than sorted
    /// in**, `ValueRecording.record`'s rule and for its reason: a control's callback is a stream, time
    /// only goes forward in it, and a repeat of the previous timestamp would give `pose(at:)` a
    /// zero-width segment to divide by.
    mutating func record(_ pose: PoseQuad, at time: TimeInterval) {
        if let last = samples.last, time <= last.time { return }
        samples.append(Sample(time: time, pose: pose))
    }

    var isEmpty: Bool { samples.isEmpty }

    /// Wall seconds from the first sample to the last. Zero for a take of one sample.
    var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.time - first.time)
    }

    /// The pose the box held at `time` — linear between the two samples bracketing it and held flat
    /// outside the take. Nil only for an empty recording, which has no pose to report.
    func pose(at time: TimeInterval) -> PoseQuad? {
        guard !samples.isEmpty else { return nil }
        return interpolated(at: time)
    }

    /// `pose(at:)` with the non-empty invariant already established, so the walk in `resampled` has no
    /// optional to unwrap per stop and therefore no unreachable fallback arm to get wrong. Every caller
    /// has checked `samples.first`/`samples.last` itself.
    private func interpolated(at time: TimeInterval) -> PoseQuad {
        let first = samples[0], last = samples[samples.count - 1]
        if time <= first.time { return first.pose }
        if time >= last.time { return last.pose }

        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        let span = b.time - a.time
        guard span > 0 else { return b.pose }
        return Self.lerp(a.pose, b.pose, CGFloat((time - a.time) / span))
    }

    /// **Two poses' corners mixed at `t`, with the box taken from `a`.**
    ///
    /// `t` is not clamped, and the two callers are why: `pose(at:)` only ever hands in a `t` inside
    /// `0...1` because it has already placed `time` between two samples, and `simplified` reads the
    /// chord *at a point's own frame*, which is likewise between its two ends. Clamping would hide a
    /// caller that got its arithmetic wrong rather than fix one.
    static func lerp(_ a: PoseQuad, _ b: PoseQuad, _ t: CGFloat) -> PoseQuad {
        var corners = a.corners
        for i in 0..<4 {
            corners[i] = CGPoint(x: a.corners[i].x + (b.corners[i].x - a.corners[i].x) * t,
                                 y: a.corners[i].y + (b.corners[i].y - a.corners[i].y) * t)
        }
        return PoseQuad(box: a.box, corners: corners)
    }

    /// **The largest distance any one of the four corners is apart in these two poses**, in canvas
    /// points — the whole of what "how much did the shape change" means here.
    ///
    /// The *largest* rather than the mean: a keystone pulled at one corner changes one corner a long
    /// way and the other three not at all, and a mean would thin exactly the frames that carry the
    /// gesture. The box is not compared, for `lerp`'s reason — within a take there is only one.
    static func cornerDeviation(_ a: PoseQuad, _ b: PoseQuad) -> CGFloat {
        var worst: CGFloat = 0
        for i in 0..<4 {
            let dx = a.corners[i].x - b.corners[i].x
            let dy = a.corners[i].y - b.corners[i].y
            worst = max(worst, (dx * dx + dy * dy).squareRoot())
        }
        return worst
    }

    /// The take walked onto document frames at `fps`, one stop per frame, starting at `startFrame` —
    /// `ValueRecording.resampled`'s arithmetic to the line, including the pinned ends and the
    /// single-stop answer for a take too short to cover a frame.
    ///
    /// **`startFrame + i` *is* the playhead at the i-th stop**, because playback advances at `fps`
    /// from the moment recording began. That correspondence is what keeps a recording aligned with
    /// what the artist watched, and it is the reason the stop count comes from the take's own duration
    /// rather than from a fixed number.
    func resampled(fps: Int, startFrame: Int) -> [(frame: Int, pose: PoseQuad)] {
        guard let first = samples.first, let last = samples.last else { return [] }
        let rate = Double(max(fps, 1))
        let stops = Int((duration * rate).rounded())
        guard stops >= 1 else { return [(frame: startFrame, pose: last.pose)] }

        var out: [(frame: Int, pose: PoseQuad)] = []
        out.reserveCapacity(stops + 1)
        for i in 0...stops {
            out.append((frame: startFrame + i,
                        pose: interpolated(at: first.time + TimeInterval(i) / rate)))
        }
        out[0].pose = first.pose
        out[stops].pose = last.pose
        return out
    }

    /// Douglas–Peucker over the resampled stops, with the deviation measured as **the largest corner
    /// displacement from the chord**, in canvas points.
    ///
    /// §5 blesses this family explicitly and names the precedent that points the other way:
    /// VECTOR_INTERPOLATION §3 fact 13 rejected Douglas–Peucker for *stroke geometry*, because two
    /// points a warp should bend apart are collinear before it and get thrown away. A pose channel is
    /// under no warp — it *is* the warp — so that argument does not reach here.
    ///
    /// Iterative rather than recursive, `ValueRecording.simplified`'s reason: a 60-second take at
    /// 60 fps is 3,600 stops and a worst-case recursion that deep is a stack the app does not need.
    ///
    /// - Parameter tolerance: the largest corner error the simplification may introduce, in canvas
    ///   points. Non-positive keeps every stop, which is the honest answer for "thin nothing".
    static func simplified(_ points: [(frame: Int, pose: PoseQuad)],
                           tolerance: CGFloat) -> [(frame: Int, pose: PoseQuad)] {
        guard points.count > 2, tolerance > 0 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (lo, hi) = stack.popLast() {
            guard hi - lo > 1 else { continue }
            let a = points[lo], b = points[hi]
            let span = CGFloat(b.frame - a.frame)
            var worst: CGFloat = 0
            var worstIndex = lo
            for i in (lo + 1)..<hi {
                let p = points[i]
                let onChord = span > 0
                    ? lerp(a.pose, b.pose, CGFloat(p.frame - a.frame) / span)
                    : a.pose
                let deviation = cornerDeviation(p.pose, onChord)
                if deviation > worst {
                    worst = deviation
                    worstIndex = i
                }
            }
            guard worst > tolerance else { continue }
            keep[worstIndex] = true
            stack.append((lo, worstIndex))
            stack.append((worstIndex, hi))
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// The whole pipeline: resample at `fps`, simplify, and hand back keys ready for a
    /// `TransformTrack` — `ValueRecording.keys`' counterpart, and the only thing `CanvasManager` calls.
    func keys(fps: Int, startFrame: Int, tolerance: CGFloat) -> [TransformTrack.Key] {
        Self.simplified(resampled(fps: fps, startFrame: startFrame), tolerance: tolerance)
            .map { TransformTrack.Key(frame: $0.frame, pose: $0.pose) }
    }
}
