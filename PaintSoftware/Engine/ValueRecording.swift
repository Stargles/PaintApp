import Foundation

/// A live take of one scalar channel — KEYFRAMES.md §5, stage 7.
///
/// The artist arms the recorder, playback runs, and they drag a control while it does. What lands in
/// here is every value the control reported *with the wall time it reported it at*; what comes out is
/// a short list of `AnimationCurve.Key`s. The three steps §5 prescribes are `record`, `resampled` and
/// `simplified`, and each of them exists because the obvious shortcut past it is wrong:
///
///  * **Capture at the source's own rate, never at 24 Hz.** §5's opening rule, and the reason is
///    aliasing: a 24 Hz sample of a shake records as a slow wobble, because the samples beat against
///    the motion. `record` therefore takes whatever the control gives it, as often as it gives it,
///    and the frame rate does not appear until `resampled`.
///  * **Resample against `fps`, not against a fixed stop count.** `GuidePath.spacingCurve` is the
///    template — walk evenly spaced output stops, read the raw stream at each, pin the ends — but its
///    33 is a constant because a spacing curve is *normalised*, and this is not: a two-second take at
///    12 fps is 24 keys and the same take at 24 fps is 48, because the document's frames are what a
///    key can land on.
///  * **Then simplify**, or a three-second take is 72 keys on one channel and the graph editor cannot
///    be used on it.
///
/// **Pure Foundation and no `CanvasManager`**, so every claim above is a fast-tier test rather than a
/// UI one, and so this compiles standalone under `swiftc` at ~5 s a loop.
struct ValueRecording: Equatable {

    /// One value as the control reported it, with the wall time it was reported at.
    ///
    /// Absolute rather than relative, unlike `TimedSample.time` (which is relative because a guide's
    /// timing is normalised and only its *shape* survives). This one keeps real time on purpose:
    /// §5 rules that *"slow motion is a capture-speed multiplier… the recorder must keep real time"*,
    /// and `GuidePath.spacingCurve` discarding absolute duration is exactly what makes it the wrong
    /// type to reuse here.
    struct Sample: Equatable {
        var time: TimeInterval
        var value: Double
    }

    private(set) var samples: [Sample] = []

    init(samples: [Sample] = []) {
        self.samples = samples
    }

    /// Takes one reported value.
    ///
    /// **Out-of-order and duplicate timestamps are dropped rather than sorted in.** A control's
    /// callback is a stream and time only goes forward in it; a sample that claims otherwise is a
    /// clock artefact, and inserting it would put a fold in the curve that no drag made. A repeat of
    /// the *previous* timestamp is likewise dropped — it carries no new information, and keeping it
    /// would give `value(at:)` a zero-width segment to divide by.
    mutating func record(_ value: Double, at time: TimeInterval) {
        if let last = samples.last, time <= last.time { return }
        samples.append(Sample(time: time, value: value))
    }

    var isEmpty: Bool { samples.isEmpty }

    /// Wall seconds from the first sample to the last. Zero for a take of one sample.
    var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.time - first.time)
    }

    /// The value the control held at `time`, linearly between the two samples bracketing it and held
    /// flat outside the take.
    ///
    /// Linear and not eased: this reads the artist's *hand*, and interpolating it with a curve would
    /// invent motion between two things they actually did. The easing belongs on the keys that come
    /// out of `resampled`, where `AnimationCurve` puts it.
    func value(at time: TimeInterval) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }

        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        let span = b.time - a.time
        guard span > 0 else { return b.value }
        let t = (time - a.time) / span
        return a.value + (b.value - a.value) * t
    }

    /// The take walked onto document frames at `fps`, one stop per frame, starting at `startFrame`.
    ///
    /// **The stop count comes from the take's own duration**, so the last stop lands on the frame the
    /// playhead was on when the artist let go: playback advances at `fps` from the moment recording
    /// began, so `startFrame + i` *is* the playhead at the i-th stop. The two arithmetics are the
    /// same one and that is what keeps a recording aligned with what the artist watched.
    ///
    /// **The ends are pinned.** The walk lands on them arithmetically already; a key is read at
    /// exactly the first and last frame on every evaluation, and that is the one place the rounding
    /// in `first.time + i/fps` would show. Same rule and same reason as `spacingCurve`'s.
    ///
    /// A take too short to cover one frame yields a **single** stop rather than none — the honest
    /// answer for "the artist recorded, briefly": one key holding what they left it on. What that
    /// then *means* is a caller's decision, and `CanvasManager` refuses it out loud rather than
    /// writing a one-key curve nothing can animate.
    func resampled(fps: Int, startFrame: Int) -> [(frame: Int, value: Double)] {
        guard let first = samples.first, let last = samples.last else { return [] }
        let rate = Double(max(fps, 1))
        let stops = Int((duration * rate).rounded())
        guard stops >= 1 else { return [(frame: startFrame, value: last.value)] }

        var out: [(frame: Int, value: Double)] = []
        out.reserveCapacity(stops + 1)
        for i in 0...stops {
            let t = first.time + TimeInterval(i) / rate
            out.append((frame: startFrame + i, value: value(at: t)))
        }
        out[0].value = first.value
        out[stops].value = last.value
        return out
    }

    /// Douglas–Peucker over the resampled stops, with the deviation measured **in value units**.
    ///
    /// **§5 blesses this family explicitly and names the precedent that points the other way**:
    /// VECTOR_INTERPOLATION §3 fact 13 rejected Douglas–Peucker for *stroke geometry*, because two
    /// points that a warp should bend apart are collinear before it and get thrown away. A value
    /// curve is under no warp, so that argument does not reach here — which is worth stating, since
    /// the two look like the same algorithm being used twice with opposite verdicts.
    ///
    /// **The deviation is `|v − lerp|` at the point's own frame, not a Euclidean distance in
    /// (frame, value).** Frames and values are different units with no exchange rate — the same trap
    /// `AnimationCurve.Handle.unit` documents for aligned handles — so a Euclidean measure would
    /// simplify an opacity channel (0…1) into two keys and a blur radius (0…500) into all of them.
    /// Measuring the error the artist can actually see, in the channel's own units, is the only
    /// definition that behaves the same on both.
    ///
    /// - Parameter tolerance: the largest value error the simplification may introduce. **A fraction
    ///   of the channel's own range**, supplied by the caller, for the reason above.
    static func simplified(_ points: [(frame: Int, value: Double)],
                           tolerance: Double) -> [(frame: Int, value: Double)] {
        guard points.count > 2, tolerance > 0 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        // Iterative rather than recursive: a 60-second take at 60 fps is 3,600 stops, and a
        // worst-case recursion that deep is a stack the app does not need to spend.
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (lo, hi) = stack.popLast() {
            guard hi - lo > 1 else { continue }
            let a = points[lo], b = points[hi]
            let span = Double(b.frame - a.frame)
            var worst = 0.0
            var worstIndex = lo
            for i in (lo + 1)..<hi {
                let p = points[i]
                let onChord = span > 0
                    ? a.value + (b.value - a.value) * (Double(p.frame - a.frame) / span)
                    : a.value
                let deviation = abs(p.value - onChord)
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

    /// The whole pipeline: resample at `fps`, simplify, and hand back keys ready for an
    /// `AnimationCurve`.
    ///
    /// `tolerance` is absolute in the channel's units; `CanvasManager` derives it from the
    /// parameter's `uiRange` so that one number means the same thing on every channel.
    func keys(fps: Int, startFrame: Int, tolerance: Double) -> [AnimationCurve.Key] {
        Self.simplified(resampled(fps: fps, startFrame: startFrame), tolerance: tolerance)
            .map { AnimationCurve.Key(frame: $0.frame, value: $0.value) }
    }
}
