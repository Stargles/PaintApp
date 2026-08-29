import CoreGraphics
import Foundation

/// **Where a target's keys sit on the timeline, and what to draw when they are too close together
/// to draw one at a time** — KEYFRAMES.md stage 3b, the marker half.
///
/// **Why this is a type and not arithmetic inside `TimelineTrackView`.** `Views/TimelineTrackView.swift`
/// and `Views/AnimationTimeline.swift` are **not** compiled into the `PaintSoftwareUITests` target, so
/// a logic test written against either is silently a pin against nothing — the trap commit `6a396e1`
/// exists to record, and the same split `KeyframeControl` and `TimelineLayoutKey` already make. Every
/// decision here is a function of values, so all of it lives on this side of the line and the view
/// keeps only the CoreGraphics calls.
///
/// **The two collapses, which are different things and are easy to conflate.**
///
/// 1. **Channels collapse unconditionally.** A target can key thirteen effect parameters on one frame
///    and the artist needs to see *a key is here*, not thirteen stacked diamonds. `markers`
///    therefore works from a **set** of frames — one marker per (target, frame), at every zoom. Which
///    channels those are is the channel panel's question, not the marker's.
/// 2. **Frames collapse by zoom, and only when they actually touch.** See `runs(markers:pixelsPerFrame:)`.
enum TimelineKeyMarkers {

    // MARK: - The timeline's zoom limits, declared here so the threshold below is a relationship

    /// `TimelineTrackView.Coordinator`'s unzoomed scale, and the two ends of its pinch range —
    /// **moved out of that file rather than copied**, because that file is not compiled into
    /// `PaintSoftwareUITests`. The collapse threshold below is only meaningful *relative to* these numbers:
    /// too small and no zoom the artist can reach ever collapses anything, too large and the default
    /// zoom collapses keys that had room. A test asserting either relationship against a `10.5`
    /// re-typed into this file would be comparing a constant to a copy of a constant — green forever,
    /// including on the day somebody widens the pinch range. The coordinator reads these.
    static let basePixelsPerFrame: CGFloat = 30
    /// 0.35…4.0 of the base: 10.5 pt per frame fully pinched out, 120 pt fully in.
    static let pixelsPerFrameRange: ClosedRange<CGFloat> =
        (basePixelsPerFrame * 0.35)...(basePixelsPerFrame * 4.0)

    // MARK: - How big a marker is

    /// The diamond's width and height in points. 9 pt is the ruler's own font size one type over, so
    /// the marker is the same scale as the chrome it sits beside rather than a size of its own.
    ///
    /// **Fixed, not proportional to `pixelsPerFrame`.** A marker is chrome: it says *a key is here*,
    /// and a fact that is either true or false should not get quieter as the artist zooms out — which
    /// is precisely the zoom at which they are surveying the whole scene and most want to see it. The
    /// cost of fixing it is that markers can collide, and `runs` is the answer to that rather than a
    /// shrinking diamond that is illegible at both ends of the range.
    static let markerWidth: CGFloat = 9

    /// The smallest gap between two markers' **edges** that still reads as a gap. A third of a marker;
    /// below it the pair reads as one serrated shape rather than as two diamonds, which is worse than
    /// an honest capsule because it looks like information and is not.
    static let markerGap: CGFloat = 3

    /// **The collapse threshold: two keys closer than this on screen, centre to centre, are drawn as
    /// one run.** `markerWidth + markerGap` — the distance at which two diamonds stop having daylight
    /// between them, which is the only thing that decides whether they are legible separately.
    ///
    /// Stating it in *points* rather than in frames or in zoom levels is the whole point. What
    /// collides is pixels, so the rule is about pixels, and it keeps working if either end of
    /// `pixelsPerFrameRange` moves. What it means today, spelled out because it is narrower than the
    /// rule sounds and the next reader should not have to derive it:
    ///
    /// | zoom | pt/frame | keys on consecutive frames | keys on twos |
    /// |---|---|---|---|
    /// | default | 30 | separate (30 ≥ 12) | separate |
    /// | fully pinched out | 10.5 | **collapse** (10.5 < 12) | separate (21 ≥ 12) |
    ///
    /// So at the floor only *adjacent* frames merge, and nothing merges at the default. That is the
    /// behaviour worth having: ink on twos beside a key on every frame should not look the same, and
    /// §2.10 makes "on twos" a first-class thing this feature can produce. A run recorded live (§5)
    /// keys every frame and becomes a capsule; an authored pose held on twos stays countable.
    /// `TimelineKeyMarkersLogicTests` pins both relationships against `pixelsPerFrameRange` rather
    /// than against these numbers.
    static var minimumSeparation: CGFloat { markerWidth + markerGap }

    /// How tall the band is inside a row. 12 pt against a 34 pt row, so the cel thumbnail keeps 22 pt
    /// — the band overlays the block's lower edge rather than growing the row.
    ///
    /// **Not growing the row is a decision, not a shortcut.** `rowHeight` feeds `contentHeight`
    /// (`AnimationTimeline.swift`), `totalHeight` (`TimelineTrackView.relayout`) *and* the pinned name
    /// column's per-row frame, and the ruler spacer above it is a hard-coded `Color.clear`. Growing
    /// rows would be correct only if every document wanted the room, and the overwhelming majority
    /// have no keys at all — so the band is hidden outright when a row has none, and an un-animated
    /// document looks exactly as it did.
    static let bandHeight: CGFloat = 12

    /// The bar joining a collapsed run's ends. Thin enough that the diamonds capping it still read as
    /// diamonds rather than as bulges in a lozenge.
    static let runBarHeight: CGFloat = 3

    // MARK: - What is on a row

    /// One frame of one target that has something to show, and which of the two kinds it is.
    struct Marker: Equatable {
        let frame: Int
        /// **True when the artist has placed a keyframe here and no channel keys on it** — §2.26's
        /// bare mark, which is the first step of the whole workflow: *"keyframe A is added, nothing
        /// is saved."*
        ///
        /// The two kinds are drawn differently (hollow against filled) because otherwise the one
        /// question the artist most needs answered — *did my edit land on a channel?* — has no
        /// answer on screen, and a keyframe that saved nothing looks exactly like one that saved
        /// everything.
        let isBare: Bool
    }

    /// **Every marker on one target's row: the union of the frames it carries a keyframe mark on and
    /// the frames its curves key on**, deduped and ascending.
    ///
    /// **Neither list contains the other, which is why this is a union rather than one of them.**
    /// §2.26: a mark with no channel is legal and is the point, and a curve carries keys the artist
    /// never marked — an auto-key, or a value seeded onto a neighbouring mark. Deriving one from the
    /// other in either direction loses real frames.
    ///
    /// **Deduping *is* collapse (1) above**, and it happens here rather than at the drawing so the
    /// marker count is a property of the document rather than of the paint code.
    ///
    /// **The sort is not cosmetic.** This feeds `TimelineLayoutKey`, which is an `Equatable`
    /// memoization key, and `Dictionary.values` has no defined order — an unsorted result would make
    /// the key unequal to itself at random and turn the layout gate off in a way that looks like a
    /// performance regression with no cause.
    ///
    /// **No `isScalarAnimatable` filter, deliberately.** Both `setEffectParameterTrack` overloads and
    /// `setEffectParameterKeys` refuse a non-scalar channel at the writer as well as at the resolver
    /// (stage 2), so a track that stores and renders nothing cannot be created; filtering here would
    /// buy nothing and would cost a call to `Effect.parameters`, which rebuilds up to thirty-three
    /// closures and is read from a path that runs on every SwiftUI pass.
    ///
    /// - Parameter tracks: the curves whose keys count as landed. The caller decides whether this
    ///   target's grade is in force at all — see `TimelineLayoutKey.make`, where a layer that is not
    ///   in effect form passes none, while its marks still pass in full.
    static func markers(marks: [Int], tracks: [String: AnimationCurve]) -> [Marker] {
        guard !marks.isEmpty || !tracks.isEmpty else { return [] }
        var keyed: Set<Int> = []
        for curve in tracks.values {
            for key in curve.keys { keyed.insert(key.frame) }
        }
        var frames = keyed
        frames.formUnion(marks)
        return frames.sorted().map { Marker(frame: $0, isBare: !keyed.contains($0)) }
    }

    /// One drawn thing on the band: either a single key, or a run of keys too close together to draw
    /// apart.
    ///
    /// **The run keeps its two end frames exactly.** A collapsed run is drawn as its first and last
    /// key with a bar between them, so the one fact a dope sheet must never lose — *where the
    /// animation starts and stops* — survives the collapse. What is lost is only which interior
    /// frames carry keys, which is what the artist zooms in to find out.
    struct Run: Equatable {
        let firstFrame: Int
        let lastFrame: Int
        /// How many keys the run swallowed. 1 is a plain diamond.
        let count: Int
        /// **True only when every marker in the run is bare**, so a run that mixes the two kinds
        /// draws as landed.
        ///
        /// The collapse is already lossy — it gives up which interior frames carry keys — and this
        /// is the same species of loss, resolved the same way, by zooming in. What decides the
        /// direction is which error is worse: hollow says *nothing here is saved yet*, which is the
        /// alarming, actionable reading, so claiming it over a run that does contain saved keys
        /// would send the artist looking for a bug that is not there. Filled says *something is
        /// here*, which is true of a mixed run.
        let isBare: Bool

        /// A run of one is not collapsed — it is just a key. Derived rather than stored so the two
        /// can never disagree.
        var isCollapsed: Bool { count > 1 }
    }

    /// **Groups keys into what can actually be drawn at this zoom.**
    ///
    /// Single-linkage on the on-screen gap: a run keeps growing while the next key is nearer than
    /// `minimumSeparation` to the previous one. Chaining is the right behaviour and not an oversight —
    /// twenty keys each 10 pt from the last are twenty keys with no daylight anywhere along the run,
    /// and that is one dense region, not ten pairs.
    ///
    /// **The grouping is by neighbour gap, not by a global "is the zoom low" flag**, which is the
    /// difference that makes this worth having: two keys forty frames apart stay two diamonds at the
    /// minimum zoom, because they do not collide. Only the parts of the track that are actually dense
    /// collapse, and the rest of the row is untouched.
    ///
    /// - Parameter markers: ascending and unique — `markers(marks:tracks:)`' output. Unsorted input
    ///   would merge the wrong things silently, and the single production caller is that function.
    static func runs(markers: [Marker], pixelsPerFrame: CGFloat) -> [Run] {
        guard let first = markers.first else { return [] }
        var result: [Run] = []
        var start = first.frame
        var last = first.frame
        var count = 1
        var isBare = first.isBare
        for marker in markers.dropFirst() {
            if CGFloat(marker.frame - last) * pixelsPerFrame < minimumSeparation {
                last = marker.frame
                count += 1
                isBare = isBare && marker.isBare
            } else {
                result.append(Run(firstFrame: start, lastFrame: last, count: count, isBare: isBare))
                start = marker.frame
                last = marker.frame
                count = 1
                isBare = marker.isBare
            }
        }
        result.append(Run(firstFrame: start, lastFrame: last, count: count, isBare: isBare))
        return result
    }

    // MARK: - Geometry

    /// The centre of a frame's column. Markers are centred **in** the column rather than sitting on
    /// its leading edge, which is what puts a key at the middle of the frame the playhead highlights
    /// — the playhead is a column of the same width, not a hairline, so an edge-aligned marker would
    /// read as belonging to the frame before it.
    static func centerX(frame: Int, pixelsPerFrame: CGFloat) -> CGFloat {
        (CGFloat(frame) + 0.5) * pixelsPerFrame
    }

    /// Which frame a point on the band belongs to — the exact inverse of `centerX`.
    ///
    /// **Nothing calls this yet and that is deliberate.** Dragging a key along the timeline is the
    /// graph editor's, and it is the next stage; what this stage owes it is a geometry that will not
    /// have to be redone, so the mapping exists in both directions and is pinned as a round trip.
    /// The gesture itself is not built — adding one inside the scroll content means
    /// `scrollView.panGestureRecognizer.require(toFail:)`, which is a decision about arbitration
    /// rather than about arithmetic.
    static func frame(atX x: CGFloat, pixelsPerFrame: CGFloat) -> Int {
        guard pixelsPerFrame > 0 else { return 0 }
        return Int((x / pixelsPerFrame).rounded(.down))
    }

    /// The rect a run occupies, from the first key's column centre to the last's, grown by half a
    /// marker at each end so the capping diamonds are inside it.
    static func rect(for run: Run, pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> CGRect {
        let leading = centerX(frame: run.firstFrame, pixelsPerFrame: pixelsPerFrame) - markerWidth / 2
        let trailing = centerX(frame: run.lastFrame, pixelsPerFrame: pixelsPerFrame) + markerWidth / 2
        return CGRect(x: leading,
                      y: (bandHeight - markerWidth) / 2,
                      width: trailing - leading,
                      height: markerWidth)
    }

    // MARK: - What a test can see

    /// The band's accessibility value: each run as `frame`, or `first-last` when it collapsed,
    /// **parenthesised when it is bare**, joined by `|`. So `"(3)|7-9"` is a keyframe at frame 3 that
    /// has saved nothing yet, beside a collapsed run of landed keys. Frames are 0-based, matching
    /// `TimelineRowView`'s `"startFrame,frameCount"`.
    ///
    /// **An encoded value on one element rather than one element per marker**, which is
    /// `CurveEditor.encode(points)`' convention and `TimelineFolderRowView`'s. It exists because
    /// XCUITest can see neither a `CGContext` nor a colour, so "there is a diamond at frame 6" is not
    /// otherwise assertable — and the collapse and the hollow form are *only* visible as shapes, so
    /// without this the two things this stage designs would be untestable above the logic tier.
    static func encode(_ runs: [Run]) -> String {
        runs.map { run in
            let span = run.isCollapsed ? "\(run.firstFrame)-\(run.lastFrame)" : "\(run.firstFrame)"
            return run.isBare ? "(\(span))" : span
        }.joined(separator: "|")
    }
}
