import CoreGraphics

/// **How one continuous gesture is shared out among the cels it was drawn over** — KEYFRAMES.md §7,
/// the timing recorder, and the owner's brief in one sentence: *"The start and end of the stroke in
/// the cel will be where the stroke started and ended while that cel was active."*
///
/// ## Why this is a partition and not a mid-gesture commit
///
/// The obvious reading of "cut the stroke at each cel boundary" is that the outgoing cel's arc is
/// *committed* the instant the playhead leaves it — close one stroke, open another. That would put
/// a display-list mutation, a version bump, a render invalidation and an undo record on the main
/// thread up to twenty-four times a second, inside a live gesture, and it would have to keep
/// `UnlandedInk`'s invariant true across a cel change while doing it.
///
/// None of that is necessary. The gesture already accumulates one knot stream
/// (`StrokeCanvasView.currentVectorSamples`), and the commit already knows how to walk **several
/// runs** of it — that is what the selection clip does (`StrokeGeometry.splitRuns`). So the cut is
/// a *partition*, recorded as indices while the pen moves and spent once at pen-up: the same shape
/// as the clip, with the target canvas varying per run instead of the samples being dropped.
///
/// ## The boundary sample belongs to both runs, and that is the whole of the seam
///
/// A cut at index `i` gives the outgoing run `samples[…i]` and the incoming run `samples[i…]` —
/// **`i` appears in both**. The two arcs therefore start and end at exactly one point, with one
/// pressure and one tilt, so a round dab's end cap on the outgoing arc and its opening dab on the
/// incoming one are the same circle at the same width. Split them at `i`/`i+1` instead and the
/// seam is a gap the length of one knot spacing — up to `StrokePathFit.maximumKnotSpacing`, twelve
/// points, which is a visible hole in the middle of a line.
///
/// What the shared sample cannot make identical is anything a brush derives from *arc length*: the
/// grain field and the scatter walk restart per stroke, and `taper` reads the whole stroke's length.
/// Two arcs of one gesture are two strokes to the replay walk, so a tapering or scattering brush
/// will show the cut. That is inherent to storing the pieces as independent strokes (which
/// LASSO_MOVE §5.4 already rules for a split stroke) and is not something a different cut index
/// could fix.
enum TimingStrokeCut {

    /// The fewest samples a run may keep. **Two**, because one is a dab the pen never travelled for:
    /// a cel the playhead crossed between two knots would otherwise collect a lone dot at the
    /// boundary point, which reads as a speck of dirt rather than as timing.
    ///
    /// A tap is unaffected and that is worth stating, since it is the case this bound could plausibly
    /// have broken: `beginVectorStroke` records the touch-down sample and `commitVectorStroke`
    /// records the lift through `pathFit.finish`, so the shortest real gesture is already two.
    static let minimumSamplesPerRun = 2

    /// One cel's share of the gesture, and **which** share it is.
    ///
    /// `slot` is the run's ordinal — 0 before the first boundary, 1 between the first and the second,
    /// and so on — and it is the field that makes this a struct rather than a bare array. The caller
    /// holds one canvas, one snapshot and one seed *per slot*, and a run too short to keep is
    /// dropped: return a plain `[StrokeSamples]` and the survivors silently renumber, so a gesture
    /// that skimmed one cel would commit every later run into the wrong cel. That is the failure
    /// this repo files as "a green assertion with the wrong two operands", reached before anyone
    /// wrote the assertion.
    struct Run {
        let slot: Int
        let samples: StrokeSamples
    }

    /// Splits `samples` at `boundaries`, sharing each boundary sample between the run it ends and
    /// the run it begins.
    ///
    /// - Parameters:
    ///   - samples: the whole gesture's stored knots, in order.
    ///   - boundaries: ascending indices into `samples`. Each is the last knot of one run **and**
    ///     the first knot of the next. An entry that is out of range, or not past the run it would
    ///     cut, still **consumes its slot** and yields no run — it is clamped rather than skipped, so
    ///     the slots stay aligned with the caller's per-run arrays. That case is real rather than
    ///     defensive: a playhead crossing two cels between two knots records two boundaries at the
    ///     same index, and the middle cel is one the pen genuinely did not travel on.
    /// - Returns: the runs that survive, in gesture order, each carrying `samples`' own channel set.
    ///   Runs shorter than `minimumSamplesPerRun` are dropped, so this can be shorter than
    ///   `boundaries.count + 1` — and empty, for a gesture that never travelled.
    static func split(_ samples: StrokeSamples, at boundaries: [Int]) -> [Run] {
        guard !samples.isEmpty else { return [] }
        let last = samples.count - 1
        var runs: [Run] = []
        var start = 0
        for (slot, boundary) in boundaries.enumerated() {
            let end = min(max(boundary, start), last)
            appendRun(&runs, slot: slot, of: samples, from: start, through: end)
            start = end
        }
        appendRun(&runs, slot: boundaries.count, of: samples, from: start, through: last)
        return runs
    }

    private static func appendRun(_ runs: inout [Run], slot: Int, of samples: StrokeSamples,
                                  from start: Int, through end: Int) {
        guard end - start + 1 >= minimumSamplesPerRun else { return }
        // `replacingSamples` rather than `StrokeSamples(_:channels:)` so the run carries the
        // gesture's own channel set verbatim — the same call, and the same reason, as the selection
        // clip's runs in `commitVectorStroke`.
        runs.append(Run(slot: slot, samples: samples.replacingSamples(Array(samples[start...end]))))
    }
}
