import Foundation

/// Which frame the background baker should bake next, and nothing else.
///
/// RENDER §3.6: *"One serial baker owns a priority queue of frames. Order: the frame the artist is
/// on; then frames ahead of the playhead in the play direction; then outward from the playhead;
/// then nothing."* This is that order, as a pure value with no queue, no thread and no pixels — so
/// the scheduler's policy can be exercised headlessly against a set of integers instead of against
/// a running baker.
///
/// ## The queue reorders, it never discards
///
/// That sentence in §3.6 is aimed at `CanvasView.isSandwichRebuilding`, a single `Bool` slot that
/// *drops* a rebuild request arriving while one is in flight. The dropped request is simply lost:
/// the picture is stale and nothing remembers to fix it. So the property is structural here rather
/// than a comment. There is one container, it is a `Set<Int>`, and the only two things that ever
/// take a frame out of it are `markClean(_:)` — the baker reporting a file on disk — and a document
/// that got *shorter*, through `frameCount`. There is no capacity, no slot, no overwrite and no
/// eviction, and `next` is not `mutating`, so asking cannot lose anything either.
///
/// ## Reordering is free because `next` derives the order every call
///
/// `next` takes the playhead as an argument and mutates nothing. An artist scrubbing the timeline
/// therefore reorders the whole queue at no cost: nothing is re-sorted, nothing is re-inserted, and
/// the answer to "what next" is simply computed against wherever the playhead now is. A queue that
/// stored its order would have to be resorted on every scrub tick, and the scrub is exactly the
/// moment the main thread has no time to spare.
///
/// ## Dirty is a hint, never the truth
///
/// RENDER §3.3/§3.6: the exact test is the bake key. A frame this queue calls pending may already
/// have a file — because the change did not reach it, or because it is one frame of a hold whose
/// key another frame already baked — and the consumer discovers that by recomputing the key and
/// finding the file, then calls `markClean`. That is what makes a scrub through a hold free, and it
/// is why nothing here is named "unbaked": this type does not know, and must not assume, that a
/// pending frame needs work. Marking too much dirty is always safe; marking too little is not.
struct BakeQueue {

    /// Which way playback (or a scrub) is travelling. §3.6's "the play direction".
    ///
    /// **Playback itself is forward-only today.** `CanvasManager.advancePlayback(by:)` only ever
    /// does `frame += 1`; there is no reverse-play transport and no ping-pong. `.backward` is here
    /// for the *scrub*, which `stepFrame(by: -1)` walks backwards under the same wrap rule, and
    /// which RENDER §3.5 explicitly wants served ("scrubbing backwards costs what forwards costs").
    /// A caller that is not scrubbing passes `.forward`.
    enum Direction {
        case forward
        case backward
    }

    /// The frames the queue believes want a bake. Never grows past `0..<frameCount`.
    private var dirty: Set<Int> = []

    /// How many frames the document lays out — the queue's whole universe. No frame outside
    /// `0..<frameCount` is ever held or returned.
    ///
    /// It lives on the queue rather than being passed to `next` because `markDirty` cannot clamp
    /// without it: a range has a lower bound to clamp against (0) and no upper one. Setting it
    /// smaller drops the frames the document no longer has, which is the only removal besides
    /// `markClean` — a scene that shrinks must not leave the baker asking forever for frames that
    /// are gone, and `pendingCount` must not count them.
    var frameCount: Int {
        didSet {
            guard frameCount < oldValue else { return }
            dirty = dirty.filter { $0 < frameCount }
        }
    }

    init(frameCount: Int = 0) {
        self.frameCount = max(frameCount, 0)
    }

    // MARK: - Marking

    /// Marks `frames` as wanting a bake, clamped to `0..<frameCount`.
    ///
    /// The half-open range is the shape the model already speaks: a cel edit dirties
    /// `[cel.startFrame, cel.endFrame)` (RENDER §3.6), and `Cel.endFrame` is already one past the
    /// last frame the cel covers.
    mutating func markDirty(_ frames: Range<Int>) {
        let low = max(frames.lowerBound, 0)
        let high = min(frames.upperBound, frameCount)
        guard low < high else { return }
        dirty.formUnion(low..<high)
    }

    /// Marks one frame as wanting a bake.
    mutating func markDirty(frame: Int) {
        markDirty(frame..<(frame + 1))
    }

    /// Marks the whole document. §3.6's structural edit — an order change, a folder, a mask, a
    /// blend mode or an effect track, none of which is confined to one cel's span.
    mutating func markAllDirty() {
        markDirty(0..<frameCount)
    }

    /// The baker reporting that `frame`'s pixels are on disk under its current key. The only
    /// removal that is not a document shrinking.
    ///
    /// Costs nothing when the frame was not pending, which is the ordinary case for the free
    /// cleans §3.3 describes — a dirty frame whose recomputed key already has a file.
    mutating func markClean(_ frame: Int) {
        dirty.remove(frame)
    }

    /// How many frames are waiting. Not a count of unbaked frames — see the note on hints above.
    var pendingCount: Int { dirty.count }

    /// Whether one frame is waiting.
    func isPending(_ frame: Int) -> Bool { dirty.contains(frame) }

    // MARK: - The order

    /// The frame to bake next, or nil when nothing is pending.
    ///
    /// Derived from the playhead every call and mutating nothing — see the note above. The order is
    /// §3.6's, in three bands:
    ///
    ///  1. **The playhead**, if it is pending. §2.10: the frame the artist is on is baked first so
    ///     they can keep drawing.
    ///  2. **Ahead in the play direction**, walked with playback's own single-step rule so the
    ///     bake order is literally the order the artist is about to see (see `playbackRange`).
    ///  3. **Outward from the playhead**, over the whole document, nearest first, the direction of
    ///     travel winning ties. This is what covers frames playback will not reach at all — the
    ///     ones outside the loop markers — so every pending frame is eventually returned and the
    ///     queue drains.
    ///
    /// - Parameters:
    ///   - playhead: `CanvasManager.currentFrame`, clamped here into the document.
    ///   - direction: which way the playhead is travelling; `.forward` during playback.
    ///   - playbackRange: the frames playback actually cycles through —
    ///     `manager.playbackStartFrame...manager.playbackEndFrame`. **Not `0...frameCount - 1`**,
    ///     and passing that instead is a real defect rather than a simplification: with loop markers
    ///     at 5 and 9 and the playhead on 7, the frames playback shows next are 8, 9, 5, 6 — so
    ///     band 2 driven by the document's extent would bake 10 and 11 ahead of 5 and 6, which is
    ///     exactly the frames the artist is *not* about to see, ahead of the ones they are. nil
    ///     means the whole document, which is also what `playbackStartFrame`/`playbackEndFrame`
    ///     resolve to when no marker is set.
    ///   - looping: `manager.isLoopEnabled`. It changes what "ahead" means at the end of the range
    ///     and nothing else: **playback with looping off stops at the end rather than wrapping**
    ///     (`advancePlayback` returns false and `tickPlayback` calls `stopPlayback`), so there is
    ///     nothing ahead of the last frame to prebake, and band 3 takes over.
    func next(playhead: Int,
              direction: Direction = .forward,
              playbackRange: ClosedRange<Int>? = nil,
              looping: Bool = false) -> Int? {
        guard frameCount > 0, !dirty.isEmpty else { return nil }
        let here = min(max(playhead, 0), frameCount - 1)

        // 1. The frame the artist is on.
        if dirty.contains(here) { return here }

        // 2. Ahead in the play direction.
        let low = max(playbackRange?.lowerBound ?? 0, 0)
        let high = min(playbackRange?.upperBound ?? frameCount - 1, frameCount - 1)
        if low <= high {
            var frame = here
            // At most one full cycle plus the walk in from outside the range; `frameCount` bounds
            // both, and the wrap makes the sequence periodic so nothing longer can find anything new.
            for _ in 0..<frameCount {
                guard let step = Self.step(from: frame, low: low, high: high,
                                           direction: direction, looping: looping) else { break }
                frame = step
                if frame == here { break }
                if dirty.contains(frame) { return frame }
            }
        }

        // 3. Outward from the playhead, over the whole document.
        let reach = max(here, frameCount - 1 - here)
        if reach > 0 {
            for distance in 1...reach {
                let near = direction == .forward ? here + distance : here - distance
                let far = direction == .forward ? here - distance : here + distance
                if near >= 0, near < frameCount, dirty.contains(near) { return near }
                if far >= 0, far < frameCount, dirty.contains(far) { return far }
            }
        }
        return nil
    }

    /// One frame of playback's own advance rule, or nil when playback would stop here.
    ///
    /// Deliberately the same shape as `CanvasManager.advancePlayback(by:)`'s inner step — "past the
    /// end, wrap if looping else stop" — rather than a second, parallel account of where playback
    /// goes. The two must agree or band 2 prebakes frames the artist never sees; the mirrored
    /// backward case is `stepFrame(by: -1)`'s looping branch, which wraps a step below the start up
    /// to the end.
    ///
    /// Note the asymmetry that is *not* a bug: a playhead parked outside the range walks toward it
    /// on the near side (frame 2 with a 5...9 range steps 3, 4, 5, …, exactly as `advancePlayback`
    /// does) and snaps to the far side on the other (frame 11 wraps to 5). That is what playback
    /// does today, and matching it is the whole point of this function.
    private static func step(from frame: Int, low: Int, high: Int,
                             direction: Direction, looping: Bool) -> Int? {
        switch direction {
        case .forward:
            if frame < high { return frame + 1 }
            return looping ? low : nil
        case .backward:
            if frame > low { return frame - 1 }
            return looping ? high : nil
        }
    }
}
