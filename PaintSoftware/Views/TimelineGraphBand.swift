import CoreGraphics
import Foundation

/// **What the graph editor band draws, and every number it draws it at** — KEYFRAMES.md §11.3,
/// stage D2.
///
/// **Why this is a type and not arithmetic inside `TimelineTrackView`.** `Views/TimelineTrackView.swift`
/// and `Views/AnimationTimeline.swift` are **not** compiled into `PaintSoftwareUITests`, so a logic
/// test written against either is silently a pin against nothing — `TimelineKeyMarkers` states the
/// rule at length and this file sits beside it for exactly that reason. Everything here is a
/// function of values; the view keeps only the CoreGraphics calls.
///
/// **The band is not `CurveEditor` moved.** `Views/EffectSection.swift:683` is a SwiftUI `Path` in a
/// square `ZStack` with its own normalised 0…1 space, and none of its drawing is portable to a
/// `UIView.draw(_:)` inside a scroll view whose x axis belongs to the timeline. What travels is the
/// *rules* — one sample per point of width, a 1.8 pt stroke, a small handle dot — and those are the
/// constants below.
///
/// **Three decisions the owner settled on 2026-08-29, which the arithmetic here encodes:**
///
/// 1. **Each curve is scaled to fill the band** (§11.6). Per-channel normalisation, not one shared
///    axis, so a 0…1 opacity and a 0…500 blur radius are both legible. What is given up is that two
///    slopes are no longer comparable — which they never were, being different units.
/// 2. **The axis is the parameter's `uiRange`** (`Effect.swift:1301`, a note written for this before
///    the feature existed), with the key extent used only where a parameter declares no `uiRange`.
///    Fitting to the key extent instead would rescale the axis on every drag, so a key would move
///    under the finger that is not dragging it.
/// 3. **And the band clips.** `AnimationCurve`'s decision 1 is that the output is never clamped, so
///    a bezier overshoot genuinely leaves `uiRange`; cutting it at the band's edge is honest, and
///    rescaling to admit it would be decision 2 undone once a frame.
enum TimelineGraphBand {

    // MARK: - How big the band is

    /// **How much height the band adds to the row it opens under.** Fixed, and not draggable — the
    /// owner's ruling of 2026-08-29 ("start fixed"), so there is no stored size and nothing to
    /// persist. Roughly three cel rows tall: enough that a curve's shape reads, small enough that
    /// the neighbouring layers stay on screen at the timeline's default 250 pt.
    static let height: CGFloat = 96

    /// The margin between the band's edges and the two ends of a channel's range, so a key sitting
    /// exactly at the top or bottom of `uiRange` is drawn as a dot rather than as a half dot on the
    /// boundary. It is *not* headroom for overshoot — see decision 3; an overshoot is cut.
    static let verticalInset: CGFloat = 8

    /// `CurveEditor.curvePath`'s stroke width, kept so the two surfaces read as the same object.
    static let lineWidth: CGFloat = 1.8

    /// The dot on a key. Smaller than `CurveEditor`'s 9 pt `Circle`, because that one is a *handle*
    /// sized for a finger and this is a mark on a curve: what a finger has to reach is `hitRadius`,
    /// which is 22 pt and independent of how big the dot is drawn.
    static let keyRadius: CGFloat = 2.5

    /// The hairline joining a key's dot to the line, where a step makes the two differ — see
    /// `stem(forKeyAt:in:)`. Thinner and fainter than the curve, because it is an annotation on the
    /// curve rather than a second one.
    static let stemWidth: CGFloat = 0.75
    static let stemAlpha: CGFloat = 0.55

    /// The band's own background, over the timeline's black, so the strip reads as a panel rather
    /// than as curves floating between two rows.
    static let backgroundWhite: CGFloat = 1
    static let backgroundAlpha: CGFloat = 0.06

    /// **How a channel that is not an animation is told apart from one that is** — `Channel.isAnimated`.
    ///
    /// A dash and a dimming, both, and neither is decoration. The dash is the distinction the doc on
    /// `channels(effect:tracks:)` used to say could not be made — *"a flat line with no way to tell it
    /// from one the artist authored"* — and it is the one property a flat line still has room for,
    /// having no shape to carry it. The dimming puts it behind the animations in the same band, which
    /// is the right order of attention: it is a curve in force, not one being animated.
    ///
    /// Its key dots are drawn **hollow** for the same reason and in the same colour, so the channel is
    /// still identifiable by hue and its keys are still visibly keys — they are what a tap has to be
    /// able to reach to remove, and what makes the state a door rather than a wall.
    static let flatDash: [CGFloat] = [4, 3]
    static let flatAlpha: CGFloat = 0.5

    // MARK: - What is on the band

    /// One curve. Everything the band draws for a channel, and nothing else — which is what lets
    /// `TimelineLayoutKey` carry this value directly and the view read what it draws *out of* the
    /// key rather than re-fetching it. See `Content`.
    struct Channel: Equatable {
        /// `EffectParameter.id`, `"<case>.<field>"`. The band's accessibility value is built from
        /// these, so a UI test names a channel the way a saved document does.
        let parameterID: String
        /// `EffectParameter.name` — the artist-facing label. Unused by the drawing today; D4's
        /// channel list is what displays it, and it is carried here so that stage needs no second
        /// walk of `Effect.parameters`.
        let name: String
        // **A `Channel` carries only what the band draws with, and that rule is load-bearing here
        // rather than tidy.** A `Channel` sits inside `Content`, `Content` sits inside
        // `TimelineLayoutKey`, and the key is what `relayout()` gates on — so a field the band never
        // reads still costs a full relayout (every row frame, every cel identifier, the ruler's
        // per-frame CoreText loop) every time something else moves it. D4's channel list needs the
        // *effect's* display name for its group header, which is not a channel's property and is not
        // even constant per case — `.blur` answers "Directional Blur" or "Gaussian Blur" off a
        // toggle. `TimelineGraphChannelList.groupNames(of:)` reads it at the popup, the one surface
        // that shows the word. Pinned by `testFlippingTheDirectionalToggleDoesNotReflowTheTimeline`.
        let curve: AnimationCurve
        /// `EffectParameter.uiRange`, verbatim, including its nil. `range(uiRange:keyValues:)` is
        /// what turns it into an axis.
        let uiRange: ClosedRange<Double>?
        /// **`EffectParameter.modelDomain` — every value the model accepts, which is wider than
        /// `uiRange` far more often than not.** D3's drag clamps to *this* and never to `uiRange`:
        /// `Effect.swift` says in as many words to draw the axis over `uiRange` and allow a key
        /// anywhere in here, and decision 3 above is the drawing half of the same sentence.
        ///
        /// In the `Channel` rather than looked up at drag time for `uiRange`'s reason one line up —
        /// the clamp a gesture applies is then keyed by `TimelineLayoutKey` like everything else the
        /// band decides, instead of being re-derived from `Effect.parameters` inside a recognizer.
        let modelDomain: ClosedRange<Double>
        /// **The channel's position in `Effect.parameters`, which is where its colour comes from.**
        ///
        /// Not the position in the *drawn* list: that one shifts when a channel starts animating,
        /// and every curve below the new one would change colour mid-session. The descriptor table
        /// is fixed by the source, so this index is stable for a given effect whatever is animated,
        /// and it is distinct per channel by construction — every curve in one band comes from one
        /// layer, hence from one effect, hence from one table.
        let descriptorIndex: Int
        /// **Whether this curve is an *animation*, or merely a curve in force** —
        /// `AnimationCurve.isAnimated`: two or more keys whose values are not all equal.
        ///
        /// **Both kinds are drawn, and they are drawn differently** — KEYFRAMES.md §11.4's "one thing
        /// found and left", settled 2026-08-30. A channel that is not an animation is drawn as a
        /// **dashed, dimmed** line (`flatDash`, `flatAlpha`) with hollow key dots. The objection this
        /// answers is the one `channels(effect:tracks:)`' doc used to make against drawing such a
        /// channel at all — *"a flat line in the band with no way to tell it from one the artist
        /// authored"* — and the answer is the dash: there is now a way to tell, so the two states are
        /// **distinguished** rather than merged.
        ///
        /// What that objection did not weigh is the state it leaves behind. Tapping away a channel's
        /// second-to-last key drops it below the predicate, and with only animations drawn the whole
        /// curve left the band **mid-gesture** — under the finger that was editing it. One press of
        /// Undo brought it back, but nothing on screen said so, and the band was then the one surface
        /// that could not put it back: a channel the band does not draw is a channel no tap in the
        /// band can add a key to.
        let isAnimated: Bool

        /// The y axis this channel is drawn against — `range(uiRange:keyValues:)` applied to this
        /// channel's own two inputs, named once so the drawing and the hit-testing cannot pick
        /// different axes and disagree about where a key is.
        var axis: ClosedRange<Double> {
            TimelineGraphBand.range(uiRange: uiRange, keyValues: curve.keys.map(\.value))
        }
    }

    /// **Everything one open band draws.** One value, so `TimelineLayoutKey` gains a single optional
    /// field and the whole of §11.3's first silent failure is closed by construction: what the band
    /// draws *is* what the layout gate compares.
    struct Content: Equatable {
        /// Which layer's row the band hangs under — `CanvasManager.currentLayerIndex` at the moment
        /// the key was built. In the key because the row it expands is a row whose *height* changes.
        let layerIndex: Int
        /// The expansion this band asked the row layout for. In the key for §11.2's reason: D2 is
        /// the first stage to derive a row height from something other than `(rows, rowHeight)`, and
        /// a height outside the key draws once and never moves again.
        let height: CGFloat
        /// In `Effect.parameters` order, which is `curvedEffectChannelIDs`' order — animations and
        /// curves-in-force alike, each flagged (`Channel.isAnimated`), **and with D4's channel list
        /// already applied**, which is why the filter needs no separate key field: switching a channel
        /// off shortens this array and the gate opens on the same comparison it always did.
        let channels: [Channel]
        /// How many of the band's channels the channel list is holding back — D4 (§11.5).
        ///
        /// **Not redundant with a shorter `channels`, and that is the whole reason it is here.** A
        /// band with nothing on it and a band with everything switched off draw the same picture and
        /// are different states: the first is a layer that carries no curve, the second is a filter
        /// the artist can undo. `encode(_ content:)` is what tells them apart, and this is the field
        /// it reads.
        let hiddenCount: Int
        /// **How far along the track the curves are drawn** — `drawnFrameCount(sceneFrameCount:channels:)`,
        /// and *not* the track's own laid-out length.
        ///
        /// In `Content`, and therefore in `TimelineLayoutKey`, for `height`'s reason exactly: it is an
        /// input the band draws with that is not otherwise in the key, and one that is not would draw
        /// once and freeze. Half of it is already in the key (the channels' own keys) and half is not
        /// (the scene's length), which is precisely the shape that makes such a field silently stale.
        let frameCount: Int
    }

    /// **How many frames the band draws its curves over.** The scene's own length, widened to hold any
    /// key that sits past the end of it.
    ///
    /// **The band view is as wide as the *track*, and the track is not the document.**
    /// `TimelineTrackView.Coordinator.displayedFrameCount(for:)` inflates the laid-out frame count past
    /// `CanvasManager.sceneFrameCount` by two screenfuls of look-ahead, so that the artist can scroll
    /// right and drop a cel past the end. Sampling a curve across all of that draws a flat line into
    /// track that holds no frames: on a 12-frame document at the default zoom more than half the band
    /// was tail. `AnimationCurve`'s constant-hold extrapolation makes the *value* out there correct,
    /// which is why this is a question about where drawing stops rather than about what it evaluates to.
    ///
    /// **Expressed as a frame count and handed to `sampling(in:visibleX:pixelsPerFrame:frameCount:)`,
    /// which already clips to one** — `TimelineRulerClip.frames(in:pixelsPerFrame:frameCount:)`'s shape,
    /// and the reason there is no second spelling of this bound anywhere.
    ///
    /// **The widening is not tidiness.** Nothing clamps a key to the scene's length: `moves` stops a key
    /// at its neighbour and at frame 0 and at no upper bound, `tap` adds one wherever the touch lands,
    /// and `sceneFrameCount` grows only from *cel* edits (`CanvasManager+Timeline`), never from a
    /// keyframe write. So a key genuinely can sit past the end of the scene, and bounding the drawing at
    /// `sceneFrameCount` alone would make it invisible while leaving it grabbable — a key the artist can
    /// delete by accident and cannot see. `+ 1` because a frame count is exclusive: the last key's own
    /// column has to be inside the bound, not on its edge.
    static func drawnFrameCount(sceneFrameCount: Int, channels: [Channel]) -> Int {
        let lastKey = channels.flatMap { $0.curve.keys.map(\.frame) }.max()
        return max(max(sceneFrameCount, 0), lastKey.map { $0 + 1 } ?? 0)
    }

    /// **Every channel the band lists: each of the target's effect parameters that carries a curve at
    /// all**, in `Effect.parameters` order, each tagged with whether that curve is an *animation*.
    ///
    /// This is `CanvasManager.curvedEffectChannelIDs`' membership — the **loose** predicate — with the
    /// strict one carried on the value rather than applied to it. `channels(effect:tracks:)` below is
    /// this filtered, so there is one walk and one place the two predicates are stated against each
    /// other; splitting them into two functions is what would let them drift.
    ///
    /// **A target with no grade contributes nothing**, which is `keyframeFrames(of:)`'s asymmetry read
    /// the same way: a layer that is not in effect form grades nothing, so tracks left on it by a
    /// kind change are storage rather than animation and must not draw a curve for a value the
    /// canvas is not showing.
    ///
    /// One walk of `Effect.parameters` — which rebuilds up to thirty-three closures per call — and
    /// the descriptor comes back with the curve rather than being looked up again per id, which the
    /// obvious spelling (`listedAnimationChannelIDs` then `first(where:)` per id) would make a
    /// linear scan over a rebuilt table per channel.
    static func allChannels(effect: Effect?, tracks: [String: AnimationCurve]) -> [Channel] {
        guard let effect, !tracks.isEmpty else { return [] }
        return effect.parameters.enumerated().compactMap { index, parameter in
            guard parameter.isScalarAnimatable,
                  let curve = tracks[parameter.id],
                  !curve.isEmpty
            else { return nil }
            return Channel(parameterID: parameter.id,
                           name: parameter.name,
                           curve: curve,
                           uiRange: parameter.uiRange,
                           modelDomain: parameter.modelDomain,
                           descriptorIndex: index,
                           isAnimated: curve.isAnimated)
        }
    }

    /// **The target's *animations*, by the strict predicate** — `AnimationCurve.isAnimated`, two or
    /// more keys not all holding the same value.
    ///
    /// **This is the same walk `CanvasManager.channelIDs` makes and it must stay so.** Both filter
    /// `Effect.parameters` by `isScalarAnimatable` and then by the curve predicate; the ids this
    /// returns are pinned equal to `listedAnimationChannelIDs(of:)` in
    /// `TimelineGraphBandLogicTests`, because two implementations of one invariant is the defect
    /// §2.28 was written about.
    ///
    /// **It is no longer "what the band draws", and that is 2026-08-30's change.** The band draws
    /// `allChannels` and dashes the ones this refuses — see `Channel.isAnimated` for why, and for the
    /// objection that used to be recorded here. What this still answers is the model's own question,
    /// *is this channel an animation*, which is what the pin above is about and what the channel
    /// list's rows are labelled by.
    ///
    /// **And that change left it with no caller in the app**, which is worth writing down rather than
    /// acting on at the end of a pass. `graphBandContent`, `graphChannelGroups` and `setGraphChannels`
    /// all take `allChannels` now, so the only callers are the two logic tests that pin this against
    /// `listedAnimationChannelIDs(of:)`. The invariant does not need it — `allChannels` carries both
    /// answers and both are pinned, membership against `curvedEffectChannelIDs` and the flag against
    /// `listedAnimationChannelIDs` — so a future session may delete this and let the tests spell the
    /// filter. It is kept for now because the alternative is deleting production code on a worker's
    /// own judgement immediately after the run that verified it, and because the name is the clearest
    /// statement in the tree of what the model means by "an animation".
    static func channels(effect: Effect?, tracks: [String: AnimationCurve]) -> [Channel] {
        allChannels(effect: effect, tracks: tracks).filter(\.isAnimated)
    }

    // MARK: - The y axis

    /// **The range a channel's y axis covers.**
    ///
    /// `uiRange` where the parameter declares one, which is 25 of the 33 and every parameter that
    /// has a slider; the extent of the channel's own keys otherwise. A parameter whose `uiRange` is
    /// degenerate falls through to the keys for the same reason a nil one does — an axis of zero
    /// height maps every value onto one line.
    ///
    /// A key extent that is itself flat is widened by half a unit either side. That case cannot
    /// arise from `channels(effect:tracks:)`, whose predicate is precisely that the values are *not*
    /// all equal, but this function is total and a caller with one key must get an axis rather than
    /// a division by zero.
    static func range(uiRange: ClosedRange<Double>?, keyValues: [Double]) -> ClosedRange<Double> {
        if let uiRange, uiRange.upperBound > uiRange.lowerBound { return uiRange }
        guard let low = keyValues.min(), let high = keyValues.max() else { return 0...1 }
        guard high > low else { return (low - 0.5)...(high + 0.5) }
        return low...high
    }

    /// **The band-local y a value sits at.** Up is more, which is every graph editor's convention
    /// and the opposite of the view's own coordinate direction.
    ///
    /// **Deliberately unclamped.** A bezier overshoot leaves `uiRange` (decision 3 above) and the
    /// answer for it is a y outside `0...bandHeight`, which the `CGContext` a `draw(_:)` runs in
    /// cuts at the view's edge for free. Clamping here would draw a flat line along the band's rim —
    /// a shape the curve does not have — and rescaling would move every other key on screen.
    static func y(ofValue value: Double, in range: ClosedRange<Double>, bandHeight: CGFloat) -> CGFloat {
        let usable = max(bandHeight - verticalInset * 2, 1)
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return verticalInset + usable / 2 }
        let t = (value - range.lowerBound) / span
        return verticalInset + usable * CGFloat(1 - t)
    }

    /// Whether a y is inside the band at all — what "the band clips" means as a predicate, so the
    /// fast tier can assert the cut rather than only the mapping.
    static func isInsideBand(_ y: CGFloat, bandHeight: CGFloat) -> Bool {
        y >= 0 && y <= bandHeight
    }

    /// **Where the drawn line is at a key's own frame, when that is not the key's own value** — and
    /// nil when the two agree, which is every key of every curve at `step == 1`.
    ///
    /// The band draws two things about a key and they are two different truths. The polyline is
    /// `AnimationCurve.evaluate`, which applies `stepped(_:)` and quantises time **down** onto a
    /// multiple of the curve's `step`, anchored at frame 0 of its own time base (`AnimationCurve.step`
    /// says so, and the anchor is why this cannot be reasoned about from the first key). So on twos,
    /// a key at an odd frame holds a value the animation never outputs: at that frame the curve
    /// reports what it held at the even frame below. The dot is the key's stored value, because that
    /// is what the artist authored and what D3 hands them to drag; the line is what the animation
    /// does, because that is what a graph editor is read for.
    ///
    /// Neither may move onto the other — a dot placed on the line would be a drag handle for a value
    /// no key holds, and a line drawn through the dots would be a picture of an animation that does
    /// not play. What they may not do is look like a mistake, so the view joins them with a hairline
    /// wherever this is non-nil. Returning the *value* rather than a `Bool` keeps the arithmetic here
    /// and leaves the view with the two `y(ofValue:)` calls and a `UIBezierPath`.
    static func stem(forKeyAt frame: Int, in curve: AnimationCurve) -> Double? {
        guard let key = curve.key(atFrame: frame) else { return nil }
        let onCurve = curve.evaluate(at: Double(frame))
        return onCurve == key.value ? nil : onCurve
    }

    // MARK: - The x axis, which belongs to the timeline

    /// **The curve time a band x maps to — the continuous inverse of
    /// `TimelineKeyMarkers.centerX(frame:)`.**
    ///
    /// A different question from `TimelineKeyMarkers.frame(atX:pixelsPerFrame:)`, which asks *which
    /// column* a point is in and floors to an `Int`. That one is what D3's key hit-testing wants;
    /// this one is what sampling a curve between two frames wants, and using either for the other's
    /// job puts the curve half a frame off its own keys. Both exist, and they are inverses of two
    /// different forward maps.
    static func time(atX x: CGFloat, pixelsPerFrame: CGFloat) -> Double {
        guard pixelsPerFrame > 0 else { return 0 }
        return Double(x / pixelsPerFrame) - 0.5
    }

    /// Where along the band a frame's key is drawn — `TimelineKeyMarkers.centerX`, named through
    /// here so the band and the marker band cannot drift apart about what a frame's x is. A key
    /// diamond on the marker band and its dot on the curve sit on one vertical line.
    static func x(ofFrame frame: Int, pixelsPerFrame: CGFloat) -> CGFloat {
        TimelineKeyMarkers.centerX(frame: frame, pixelsPerFrame: pixelsPerFrame)
    }

    /// The x positions a curve is evaluated at: one per point of width, which is
    /// `CurveEditor.curvePath`'s density, clipped to the dirty rect, to **what is on screen**, and
    /// to the frames the band draws over — `drawnFrameCount(sceneFrameCount:channels:)`, which is the
    /// document's own length rather than the track's.
    ///
    /// **A stride rather than an array**, because the whole point of clipping is not to allocate one
    /// sample per point of a track that can be nine thousand points wide.
    ///
    /// **One point of slack on each side**, `TimelineRulerClip`'s reason exactly: a polyline whose
    /// two endpoints straddle a tile boundary needs the vertex just outside the rect or the curve
    /// has a hole at the seam, and a hole is harder to spot in review than a redundant sample.
    struct Sampling: Equatable {
        let minX: CGFloat
        let maxX: CGFloat
        let step: CGFloat

        /// Always at least two, so there is a line rather than a point.
        var count: Int { max(Int(((maxX - minX) / step).rounded(.up)), 1) + 1 }
        /// The last sample lands exactly on `maxX` rather than past it, so the polyline ends where
        /// the clip does.
        func x(at index: Int) -> CGFloat { min(minX + CGFloat(index) * step, maxX) }
    }

    /// **The dirty rect is not a clip, and that is the whole reason `visibleX` exists.**
    ///
    /// `TimelineRulerView.draw`'s doc already states the premise: UIKit hands a **full-bounds**
    /// `rect` whenever a view is invalidated by the no-argument `setNeedsDisplay()`, which is what
    /// both `update` and `layoutSubviews` call — so on the band, whose own width *is* the whole
    /// laid-out track, clipping to `rect` clipped to nothing at all. The difference from the ruler
    /// is what a clipped-away unit costs: the ruler pays one CoreText layout per **frame** (one per
    /// 30 pt at the default zoom), the band pays a Bézier root-solve per **point**. Measured as
    /// counts rather than as time, because the constant is small and the count is the term that
    /// moved: a 300-frame document at the default zoom is 9,000 pt of track, so two animated
    /// channels cost ~18,000 `evaluate` calls — each a binary search plus, on a bezier segment, a
    /// Newton solve of 2–3 `cubic()` evaluations — on **every** redraw, and 216,000 `cubic()` calls
    /// at the 120 pt/frame zoom ceiling. That redraw fires on every `.changed` tick of a slider drag
    /// that is auto-keying with the band open, and on every `.changed` sample of a pinch.
    ///
    /// `visibleX` is the scroll view's window in the band's own x, so the count becomes a function
    /// of the *viewport* — ~1,366 pt on this iPad in landscape, whatever the document's length or
    /// the zoom. It is deliberately **not** an optional with a "no clip" default: a caller that
    /// forgot it would silently buy the whole track back, which is the failure this parameter is
    /// here to remove.
    ///
    /// **The viewport is not in `TimelineLayoutKey` and must not be.** A scroll changes what the
    /// band draws and moves nothing else on the track, so it takes the `movePlayhead` fast path —
    /// `Coordinator.updateGraphBandViewport`. Keying on it would make the key move on every tick of
    /// a gesture the gate exists to make cheap, which is `currentFrame`'s argument exactly.
    static func sampling(in rect: CGRect,
                         visibleX: ClosedRange<CGFloat>,
                         pixelsPerFrame: CGFloat,
                         frameCount: Int) -> Sampling? {
        guard pixelsPerFrame > 0, frameCount > 0, rect.width > 0,
              visibleX.upperBound > visibleX.lowerBound
        else { return nil }
        let full = CGFloat(frameCount) * pixelsPerFrame
        // The slack is applied *after* both clips, so the polyline still leaves the visible window
        // by a point at each end and the curve reaches the screen edge rather than stopping a pixel
        // short of it — the seam argument above, with the screen edge as the seam.
        let minX = max(0, max(rect.minX, visibleX.lowerBound) - 1)
        let maxX = min(full, min(rect.maxX, visibleX.upperBound) + 1)
        guard maxX > minX else { return nil }
        return Sampling(minX: minX, maxX: maxX, step: 1)
    }

    // MARK: - What a touch on the band means — stage D3, KEYFRAMES.md §11.4

    /// **One key, addressed the way the document addresses it**: which channel, and which frame.
    ///
    /// Not an index into `channels` and not an index into `curve.keys`. Both of those move under an
    /// edit — inserting a key renumbers every key above it, and a channel that stops satisfying
    /// `isAnimated` leaves the drawn list entirely — so a selection held across a gesture has to be
    /// stated in the model's own terms. `AnimationCurve` enforces one key per frame (decision 4), so
    /// this pair is unique by construction.
    struct KeyRef: Hashable {
        let parameterID: String
        let frame: Int
    }

    /// **How near a touch has to land to count as *on* a key, in points.** `CurveEditor.hitRadius`
    /// verbatim, and for the reason its own comment gives: the dots are a few points across and a
    /// fingertip is not. Re-declared rather than shared because that one is a `private let` on a
    /// SwiftUI `View` in `Views/EffectSection.swift`, which is not compiled into
    /// `PaintSoftwareUITests` — the constant is reachable from neither the type nor the test tier.
    /// The number travels; the widget does not.
    static let hitRadius: CGFloat = 22

    /// **Below this much travel the gesture is a tap, not a drag.** `CurveEditor.tapSlop`, same
    /// provenance and same job: without it a tap always resolves as a zero-length drag of whatever
    /// it landed on, and tap-to-remove could never fire.
    static let tapSlop: CGFloat = 5

    /// **Whether a finished touch was a tap: it never became a drag, *and* it went nowhere.**
    ///
    /// Both, and neither alone — which is the one place D3 could not inherit `CurveEditor`'s answer
    /// even though it inherited the grammar, and it is here rather than in the recogniser so that
    /// the rule is a value the fast tier can read like every other rule the band decides.
    ///
    /// - `didMove` alone is what `CurveEditor`'s own comment warns against, and it is wrong in both
    ///   files for the same reason: a touch that began on empty graph grabbed nothing, so the flag
    ///   stays false while the finger travels an inch, and calling that a tap drops a key wherever
    ///   it stopped.
    /// - The **translation** alone is wrong here and is *not* wrong in `CurveEditor`, and this is the
    ///   asymmetry that made the borrowed comment stop being true when it was carried over. There the
    ///   flag is set only after a handle was grabbed; here it is set for the marquee too, before the
    ///   gesture has decided which kind it is. So a drag that changes its mind — out past `tapSlop`,
    ///   then back to where it started — arrives with a translation of nothing, and the translation
    ///   alone reads it as a tap **on the key it was carrying**.
    ///
    /// **The stakes of that second half fell on 2026-09-03 and the predicate is unchanged.** Until
    /// (38)(b) a tap on a key *removed* it, so a reversed drag deleted the key it was carrying — and
    /// with the drag's bracket open, `setEffectParameterTrack` records nothing and
    /// `cancelStructureGesture` then drops the bracket, so the key was gone with **no undo step at
    /// all**. A tap on a node now focuses it, so the worst that case can do is draw two handle dots.
    /// The predicate stays because its *first* half was never about deletion: a sweep that began on
    /// empty band still resolves as `.add` under `didMove` alone, and lands a key wherever the finger
    /// happened to stop.
    static func isTap(didMove: Bool, translation: CGSize) -> Bool {
        !didMove && hypot(translation.width, translation.height) <= tapSlop
    }

    /// The ring drawn around a key the marquee has picked up. Larger than `keyRadius`, so a
    /// selection is legible without the dot itself changing size and appearing to move.
    static let selectedKeyRadius: CGFloat = 5

    /// **The value a band-local y means — the exact inverse of `y(ofValue:in:bandHeight:)`.**
    ///
    /// Unclamped, exactly as its inverse is: a y above the band's top is a value above the axis, and
    /// that is a state the model allows (`Effect.swift`: draw over `uiRange`, allow a key anywhere in
    /// `modelDomain`). The clamp that *does* apply is `modelDomain`'s, and it is applied where the
    /// domain is known — see `moves(of:in:translation:pixelsPerFrame:bandHeight:)`.
    static func value(atY y: CGFloat, in range: ClosedRange<Double>, bandHeight: CGFloat) -> Double {
        let usable = max(bandHeight - verticalInset * 2, 1)
        let t = 1 - Double((y - verticalInset) / usable)
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }

    /// **Where a touch may grab a key from, vertically.**
    ///
    /// A key's *drawn* y is unclamped and the band cuts it (decision 3), so a key dragged above the
    /// top of the range is off screen — and measuring the hit against that y would make it
    /// permanently ungrabbable, an unreachable state D3's own gesture had created. Measuring against
    /// the y clamped **into** the band instead makes such a key reachable from the rim of its own
    /// column, which is the only place an artist could sensibly look for it. Inside the range this is
    /// the identity, so it costs the ordinary case nothing.
    static func reachableY(ofValue value: Double, in range: ClosedRange<Double>,
                           bandHeight: CGFloat) -> CGFloat {
        min(max(y(ofValue: value, in: range, bandHeight: bandHeight), 0), bandHeight)
    }

    /// **The key a touch grabs: the nearest one inside `hitRadius`, across every drawn channel.**
    ///
    /// The nearest match rather than the first — `CurveEditor.nearestHandle`'s rule, and it matters
    /// more here than it does there, because two channels can key the same frame and their dots then
    /// share an x. Nil when nothing is in reach, which is what makes tap-to-add and the marquee
    /// reachable at all.
    static func nearestKey(to point: CGPoint, channels: [Channel],
                           pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> KeyRef? {
        var best: (ref: KeyRef, distance: CGFloat)?
        for channel in channels {
            let axis = channel.axis
            for key in channel.curve.keys {
                let dx = x(ofFrame: key.frame, pixelsPerFrame: pixelsPerFrame) - point.x
                let dy = reachableY(ofValue: key.value, in: axis, bandHeight: bandHeight) - point.y
                let distance = hypot(dx, dy)
                guard distance <= hitRadius else { continue }
                if best == nil || distance < best!.distance {
                    best = (KeyRef(parameterID: channel.parameterID, frame: key.frame), distance)
                }
            }
        }
        return best?.ref
    }

    /// **Which curve a tap that missed every key belongs to.**
    ///
    /// `CurveEditor` has no equivalent because it draws exactly one curve, so "add a point here" needs
    /// no subject. A band draws several, and the only non-arbitrary way to name one is the same
    /// proximity rule the keys use: the nearest drawn line within `hitRadius` of the touch. A tap that
    /// is near no line at all names no channel and adds nothing — which is what leaves the empty parts
    /// of the band free for the marquee.
    ///
    /// Measured against the **drawn** line, `evaluate` and all, rather than against the keys: that is
    /// the shape the artist is aiming at, and at `step > 1` it is deliberately not where the dots are.
    static func nearestChannel(to point: CGPoint, channels: [Channel],
                               pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> String? {
        let t = time(atX: point.x, pixelsPerFrame: pixelsPerFrame)
        var best: (id: String, distance: CGFloat)?
        for channel in channels {
            let lineY = y(ofValue: channel.curve.evaluate(at: t), in: channel.axis, bandHeight: bandHeight)
            let distance = abs(lineY - point.y)
            guard distance <= hitRadius else { continue }
            if best == nil || distance < best!.distance { best = (channel.parameterID, distance) }
        }
        return best?.id
    }

    /// **How many frames a horizontal travel of `translationX` is worth**, and the first caller of
    /// `TimelineKeyMarkers.frame(atX:pixelsPerFrame:)`, whose doc has been waiting for one.
    ///
    /// **The floored inverse, not the continuous one.** `time(atX:)` answers 7.4 because sampling a
    /// curve between two frames needs it; a key lands on an integer frame and nothing an artist can do
    /// puts one between two, so this asks *which column* instead. Using the other one here would put
    /// every drag half a frame out.
    ///
    /// Stated as a **delta** rather than as an absolute frame, which is what lets one expression serve
    /// a single key and a marquee of nine. It is exactly delta-invariant: `frame(atX:)` floors and
    /// `centerX` offsets by half a column, so `frame(atX: centerX(f) + dx) - f` is
    /// `floor(0.5 + dx / pixelsPerFrame)` for every integer `f`. Taking it at frame 0 is therefore the
    /// same answer as taking it at the key, and every key of a group gets the *same* answer — which is
    /// the property a group move needs and a per-key round trip would not guarantee.
    ///
    /// **And it keeps the grab offset.** A finger may take a key from up to `hitRadius` away, so
    /// resolving the destination from the touch's own x — `CurveEditor`'s spelling, on a 196 pt square
    /// where 22 pt is a tenth of the range — would snap the key under the finger and, at the pinched-out
    /// zoom of 10.5 pt per frame, teleport it two frames on touch-down.
    static func frameDelta(translationX: CGFloat, pixelsPerFrame: CGFloat) -> Int {
        TimelineKeyMarkers.frame(atX: TimelineKeyMarkers.centerX(frame: 0, pixelsPerFrame: pixelsPerFrame)
                                    + translationX,
                                 pixelsPerFrame: pixelsPerFrame)
    }

    /// Where one key ends up.
    struct Move: Equatable {
        let frame: Int
        let value: Double
    }

    /// **Where a drag puts every key it is carrying** — one key or a marquee's worth, one function.
    ///
    /// **The collision rule: a key is stopped by its neighbour rather than allowed to consume it.**
    /// `AnimationCurve.setKey` replaces on collision, so letting a key travel onto another's frame
    /// would silently destroy that key — a destructive edit produced by a continuous gesture, where
    /// "put it here" and "overshoot" are the same finger movement. `CurveEditor.moving(_:to:)` already
    /// answers exactly this question exactly this way, one epsilon at a time, and states the reason:
    /// `MonotoneCubic` drops a point whose x duplicates its neighbour's, so letting two coincide would
    /// delete one silently. Clamping is also the only one of the two answers that is *visible* — the
    /// dot stops under a finger that is still moving, which reads as a wall — and the only one that
    /// needs no confirmation, no toast and no second undo entry.
    ///
    /// **The group moves as a rigid body.** One `frameDelta` for every key, clamped to the tightest
    /// allowance any of them has, so a marquee's shape survives the move; the alternative — clamping
    /// each key independently — collapses a selection onto its blocked members and cannot be undone by
    /// dragging back. Keys *inside* the selection never block each other, since they travel together.
    ///
    /// **Vertically the group shares a travel in points, not in value**, and each channel maps that
    /// through its own axis. Per-channel normalisation (§11.6) means a point of band is a different
    /// number of units in every curve; a shared *value* delta would move a 0…1 opacity off the top of
    /// the band while a 0…500 blur radius did not visibly move at all.
    ///
    /// Frames are clamped at 0 as well as at the neighbour: §3.1 puts a layer channel in absolute
    /// document frames, and the track begins at x 0.
    static func moves(of selection: Set<KeyRef>, in channels: [Channel], translation: CGSize,
                      pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> [KeyRef: Move] {
        guard !selection.isEmpty else { return [:] }
        var minDelta = Int.min
        var maxDelta = Int.max
        var carried: [(ref: KeyRef, channel: Channel, value: Double)] = []

        for channel in channels {
            let taken = channel.curve.keys.filter { selection.contains(KeyRef(parameterID: channel.parameterID,
                                                                             frame: $0.frame)) }
            guard !taken.isEmpty else { continue }
            let blockers = channel.curve.keys.map(\.frame)
                .filter { frame in !selection.contains(KeyRef(parameterID: channel.parameterID, frame: frame)) }
            for key in taken {
                let below = blockers.last { $0 < key.frame }
                let above = blockers.first { $0 > key.frame }
                minDelta = max(minDelta, max(0, (below ?? -1) + 1) - key.frame)
                if let above { maxDelta = min(maxDelta, above - 1 - key.frame) }
                carried.append((KeyRef(parameterID: channel.parameterID, frame: key.frame), channel, key.value))
            }
        }
        guard !carried.isEmpty else { return [:] }
        // Zero is always inside the allowance — a key never blocks itself — so the two bounds can
        // never cross, whatever the requested delta is.
        let delta = min(max(frameDelta(translationX: translation.width, pixelsPerFrame: pixelsPerFrame),
                            minDelta), maxDelta)

        var result: [KeyRef: Move] = [:]
        for item in carried {
            let axis = item.channel.axis
            let startY = y(ofValue: item.value, in: axis, bandHeight: bandHeight)
            let raw = value(atY: startY + translation.height, in: axis, bandHeight: bandHeight)
            let domain = item.channel.modelDomain
            result[item.ref] = Move(frame: item.ref.frame + delta,
                                    value: min(max(raw, domain.lowerBound), domain.upperBound))
        }
        return result
    }

    /// **What a tap on the band does** — TODO (38)(b), the owner's ask of 2026-09-03.
    ///
    /// > *"Right now clicking on a node in it deletes it. Instead, when you click on it it should
    /// > open the adjust bezier curve from that node menu, the one with the line and two nodes.
    /// > Clicking on a node twice just like clicking on a cel twice brings up the menu and the option
    /// > to delete it."*
    ///
    /// **So a tap on a node no longer removes it**, and the case that did is gone rather than
    /// deprecated: deleting was the *default* outcome of the commonest gesture on the surface, on a
    /// control where a fingertip is 22 pt wide and the thing being destroyed is the artist's own
    /// timing. `CurveEditor`'s tap-to-remove — which §11.4 inherited wholesale along with the rest of
    /// that grammar — is right for a tone curve, where a point is one of four and costs nothing to
    /// redraw, and wrong for a keyframe.
    ///
    /// **The two-stage tap is `handleTapOnCel`'s, which is what the owner is naming**: the first tap
    /// on a cel only selects the layer and frame it landed on, and the menu opens on a *second* tap
    /// that lands where the selection already is. Here the first tap **focuses** the node, which is
    /// what puts its two bezier handles on the band (`handles(of:in:…)` — the line and two nodes), and
    /// the second opens the menu that carries Delete. Neither stage is a `UITapGestureRecognizer` with
    /// `numberOfTapsRequired = 2`; there is no double-tap anywhere in this app and adding one here
    /// would make the node the only control in the timeline with a different idiom.
    enum Tap: Equatable {
        /// Take this node as the focused one, so its handles are drawn and can be dragged. The first
        /// of the two stages, and the one that replaced `.remove`.
        case focus(KeyRef)
        /// A second tap on the node that is *already* focused: raise its menu, which is where Delete
        /// now lives. `TimelineTrackView.MenuRequest.graphNode` is what carries it.
        case menu(KeyRef)
        /// A new key on `parameterID`, at the tapped frame and the tapped value.
        case add(parameterID: String, frame: Int, value: Double)
        /// The touch named no channel, or named one that already holds a key on that frame.
        ///
        /// Spelled `nothing` rather than `none` so it can never be read as `Optional.none` at a call
        /// site that pattern-matches it.
        case nothing
    }

    /// **A tap resolved.** The value is the tapped y rather than the curve's own value there, which is
    /// `CurveEditor.adding`'s behaviour and makes the new dot land under the finger; a key placed on
    /// the line instead would be a gesture with no visible effect.
    ///
    /// **An add onto a frame the channel already keys is refused**, which is `CurveEditor.adding`'s
    /// own guard against creating a duplicate — and it is reachable here without a near miss, because
    /// at `step > 1` the drawn line and the key's dot are deliberately apart (`stem(forKeyAt:in:)`),
    /// so a tap can be on the line and 40 pt from the key that owns that frame. Without the refusal
    /// `setKey` would replace it and the artist's value would be gone with no gesture that looked
    /// destructive.
    ///
    /// **And an add past `frameCount` is refused, which is the gesture half of where drawing stops.**
    /// `nearestChannel`'s rule is proximity to the **drawn** line — that is the sentence its own doc
    /// makes the choice on — so once the curves stop at the document's own length
    /// (`drawnFrameCount(sceneFrameCount:channels:)`) a tap out in the look-ahead would be aiming at a
    /// line nobody can see, and would land a key by luck. A tap that lands *on a node* is deliberately
    /// not bounded the same way: the bound already widens to hold any key past the end, so every node
    /// the band draws is inside it and a node that is drawn must stay reachable.
    ///
    /// - Parameter focused: the node whose handles are currently drawn, which is what makes this a
    ///   two-stage gesture rather than a one-stage one. A tap on *that* node is the second stage and
    ///   answers `.menu`; a tap on any other node is the first and answers `.focus`. Passing nil is
    ///   the state a band opens in, where every node's tap is a first stage.
    static func tap(at point: CGPoint, channels: [Channel], focused: KeyRef?, frameCount: Int,
                    pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> Tap {
        if let hit = nearestKey(to: point, channels: channels,
                                pixelsPerFrame: pixelsPerFrame, bandHeight: bandHeight) {
            return hit == focused ? .menu(hit) : .focus(hit)
        }
        guard let id = nearestChannel(to: point, channels: channels,
                                      pixelsPerFrame: pixelsPerFrame, bandHeight: bandHeight),
              let channel = channels.first(where: { $0.parameterID == id })
        else { return .nothing }
        let frame = TimelineKeyMarkers.frame(atX: point.x, pixelsPerFrame: pixelsPerFrame)
        guard frame >= 0, frame < frameCount, channel.curve.key(atFrame: frame) == nil
        else { return .nothing }
        let raw = value(atY: point.y, in: channel.axis, bandHeight: bandHeight)
        let domain = channel.modelDomain
        return .add(parameterID: id, frame: frame,
                    value: min(max(raw, domain.lowerBound), domain.upperBound))
    }

    /// **Every key a rubber band encloses** — ask 6's *"select the keyframe nodes and move them"*.
    ///
    /// The rect is standardised, so a marquee drawn in any of the four directions selects the same
    /// keys; a drag that travels less than `tapSlop` is a tap and never reaches here.
    ///
    /// **Membership uses `reachableY`, the same y the single-key grab does.** One rule for "which keys
    /// can this gesture reach" rather than two: a key above the top of the axis is drawn nowhere, and
    /// if a marquee measured it at its true y it would be selectable by a rect the artist cannot draw,
    /// while the single-tap grab could still reach it from the rim. Reachable by both or by neither.
    static func keys(in rect: CGRect, channels: [Channel],
                     pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> Set<KeyRef> {
        let box = rect.standardized
        guard box.width > 0 || box.height > 0 else { return [] }
        var result: Set<KeyRef> = []
        for channel in channels {
            let axis = channel.axis
            for key in channel.curve.keys {
                let point = CGPoint(x: x(ofFrame: key.frame, pixelsPerFrame: pixelsPerFrame),
                                    y: reachableY(ofValue: key.value, in: axis, bandHeight: bandHeight))
                if box.contains(point) {
                    result.insert(KeyRef(parameterID: channel.parameterID, frame: key.frame))
                }
            }
        }
        return result
    }

    /// **The curves a set of moves produces, from the curves the drag started with.**
    ///
    /// Always applied to the drag's *starting* curves rather than to the document's current ones: a
    /// live drag rewrites the same keys on every `.changed` tick, and composing this tick's delta onto
    /// last tick's result would make the key accelerate away from the finger.
    ///
    /// Each carried key is removed before any is re-inserted, so a group sliding **into** the frames
    /// its own leading edge just vacated cannot have a member deleted by `setKey`'s replace-on-
    /// collision — the interior of a rigid selection is exactly the case where the neighbour clamp is
    /// silent because it never fires.
    ///
    /// **The walk is sorted, and that buys a test rather than a behaviour.** Removals-before-
    /// insertions makes the result independent of the order the carried keys are visited in, so
    /// sorting changes no answer this function gives. What it changes is what a *broken* version
    /// gives: interleave the two halves and a rightward slide survives untouched whenever the walk
    /// happens to run downwards, which for a `Dictionary` is a per-process coin flip — Swift seeds
    /// its hashing per launch, so `testAGroupSlidingOverItsOwnFramesLosesNothing` killed that
    /// mutation about five runs in six and was green on the sixth. A test that catches a defect
    /// sometimes is worse here than one that never does: CLAUDE.md's triage section exists because a
    /// one-off XCUITest red is usually environmental, and a genuinely intermittent test spends that
    /// judgement for everyone. Ascending is the direction that makes an interleaved walk fatal to
    /// the rightward slide the test drags.
    ///
    /// - Returns: only the channels whose curve actually changed, keyed by parameter id.
    static func applying(_ moves: [KeyRef: Move], to channels: [Channel]) -> [String: AnimationCurve] {
        var result: [String: AnimationCurve] = [:]
        for channel in channels {
            let mine = moves.filter { $0.key.parameterID == channel.parameterID }
                .sorted { $0.key.frame < $1.key.frame }
            guard !mine.isEmpty else { continue }
            var curve = channel.curve
            var moved: [AnimationCurve.Key] = []
            for (ref, move) in mine {
                guard var key = curve.key(atFrame: ref.frame) else { continue }
                curve.removeKey(atFrame: ref.frame)
                key.frame = move.frame
                key.value = move.value
                moved.append(key)
            }
            for key in moved { curve.setKey(key) }
            if curve != channel.curve { result[channel.parameterID] = curve }
        }
        return result
    }

    // MARK: - The bezier handles — TODO (38)(b)

    /// **Which of a node's two handles.** The owner's *"the line and two nodes"*: one straight line
    /// through the key, a dot at each end, the incoming handle shaping the segment that arrives and
    /// the outgoing one the segment that leaves.
    enum HandleSide: Hashable, CaseIterable {
        case incoming
        case outgoing
    }

    /// One handle, addressed the way `KeyRef` addresses a node — by channel and frame rather than by
    /// index, for `KeyRef`'s stated reason: an index moves under an edit and a selection held across
    /// a gesture has to be stated in the model's own terms.
    struct HandleRef: Hashable {
        let key: KeyRef
        let side: HandleSide
    }

    /// A handle dot, drawn. Smaller than `keyRadius`'s neighbour on purpose: `selectedKeyRadius` is
    /// the ring round a *selected* node and this is a different object, so it must not be mistaken
    /// for one at a glance.
    static let handleRadius: CGFloat = 3.5
    /// The line joining the two handle dots through their key. Thinner than a curve, because it is
    /// an annotation on one — `stemWidth`'s argument, one point wider so it reads as grabbable.
    static let handleLineWidth: CGFloat = 1

    /// **How near a touch has to land to count as *on* a handle.** Smaller than `hitRadius`
    /// deliberately, and the arbitration in `grab(at:…)` is what actually decides the contest — see
    /// its doc. A handle that has collapsed onto its own key is unreachable rather than making the
    /// key unreachable, which is the right way round: the key must always be draggable, and a handle
    /// too short to grab is reached by zooming in, which changes the dot's distance and not the key's.
    static let handleHitRadius: CGFloat = 18

    /// **Where a handle's dot sits, relative to its key, in the band's own points.**
    ///
    /// The two axes are different units — frames across, the channel's own value up — so this is the
    /// same pair of mappings the rest of the band uses (`x(ofFrame:)`'s scale and `y(ofValue:)`'s),
    /// applied to a *delta* rather than to a position. `deltaValue` is negated for `y(ofValue:)`'s
    /// reason: up is more.
    ///
    /// **A consequence worth naming rather than discovering**: a handle's drawn *direction* depends
    /// on the zoom and on the channel's axis, so the same stored handle looks steeper on a 0…1
    /// opacity than on a 0…500 blur radius. That is inherent to a graph editor with per-channel
    /// normalisation (§11.6) — `AnimationCurve.Handle.unit`'s doc records the same property about
    /// `.aligned` — and it is why a drag is expressed in points and converted here rather than being
    /// stored in points.
    static func handleOffset(_ handle: AnimationCurve.Handle, in range: ClosedRange<Double>,
                             pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> CGVector {
        let usable = max(bandHeight - verticalInset * 2, 1)
        let span = range.upperBound - range.lowerBound
        let dy = span > 0 ? -CGFloat(handle.deltaValue / span) * usable : 0
        return CGVector(dx: CGFloat(handle.deltaFrames) * pixelsPerFrame, dy: dy)
    }

    /// The exact inverse of `handleOffset(_:in:pixelsPerFrame:bandHeight:)`, so a handle dragged to a
    /// point and read back lands on the same point. Pinned by
    /// `testAHandleOffsetRoundTripsThroughTheBandsOwnAxes`.
    static func handle(fromOffset offset: CGVector, in range: ClosedRange<Double>,
                       pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> AnimationCurve.Handle {
        let usable = max(bandHeight - verticalInset * 2, 1)
        let span = range.upperBound - range.lowerBound
        return AnimationCurve.Handle(
            deltaFrames: pixelsPerFrame > 0 ? Double(offset.dx / pixelsPerFrame) : 0,
            deltaValue: span > 0 ? -Double(offset.dy / usable) * span : 0)
    }

    /// A handle as the band draws it: which one, and where its dot is.
    struct DrawnHandle: Equatable {
        let side: HandleSide
        let point: CGPoint
    }

    /// **The focused node's handles — the "line and two nodes", as points.**
    ///
    /// **Drawn from `effectiveHandles(at:)`, never from the stored pair.** Four of `AnimationCurve`'s
    /// five tangent modes *derive* their handles and ignore what is stored, so drawing the stored pair
    /// would put the dots at the origin for every key the artist has not yet touched — a control that
    /// looks broken on the whole document until it is used. `AnimationCurve`'s own doc names this
    /// function as the one an editor should draw the curve from, and the handles have to agree with
    /// the curve or the two operands of every judgement the artist makes are different things.
    ///
    /// **A handle that shapes nothing is not offered**, which is the one asymmetry here. The first
    /// key's incoming handle and the last key's outgoing one bound no segment —
    /// `value(inSegmentStartingAt:)` reads the earlier key's `outHandle` and the later key's
    /// `inHandle`, so those two are consulted by no evaluation whatever — and a dot an artist can drag
    /// that changes no pixel is worse than no dot: it teaches a wrong model of the control. So a
    /// one-key curve offers neither, and every curve's two ends offer one each.
    static func handles(of ref: KeyRef, in channels: [Channel],
                        pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> [DrawnHandle] {
        guard let channel = channels.first(where: { $0.parameterID == ref.parameterID }),
              let index = channel.curve.keys.firstIndex(where: { $0.frame == ref.frame })
        else { return [] }
        let key = channel.curve.keys[index]
        let effective = channel.curve.effectiveHandles(at: index)
        let axis = channel.axis
        let origin = CGPoint(x: x(ofFrame: key.frame, pixelsPerFrame: pixelsPerFrame),
                             y: y(ofValue: key.value, in: axis, bandHeight: bandHeight))
        func dot(_ handle: AnimationCurve.Handle) -> CGPoint {
            let offset = handleOffset(handle, in: axis, pixelsPerFrame: pixelsPerFrame,
                                      bandHeight: bandHeight)
            return CGPoint(x: origin.x + offset.dx, y: origin.y + offset.dy)
        }
        var drawn: [DrawnHandle] = []
        if index > 0 { drawn.append(DrawnHandle(side: .incoming, point: dot(effective.inHandle))) }
        if index < channel.curve.keys.count - 1 {
            drawn.append(DrawnHandle(side: .outgoing, point: dot(effective.outHandle)))
        }
        return drawn
    }

    /// What a touch-down on the band took hold of.
    enum Grab: Equatable {
        case handle(HandleRef)
        case key(KeyRef)
        case nothing
    }

    /// **The arbitration KEYFRAMES.md §11.4 named as the reason tangent handles were a stage rather
    /// than an afternoon**: *"the second hit target per key and the arbitration between grabbing a
    /// handle and grabbing the key it belongs to."*
    ///
    /// **A handle wins only when it is strictly nearer than the node it belongs to.** The naive rule —
    /// handles first, because they are drawn on top — is wrong in a way that is invisible until it
    /// bites: a handle's length in points is `deltaFrames * pixelsPerFrame`, so at the pinched-out
    /// zoom of 10.5 pt per frame a two-frame segment puts an `.autoClamped` dot **7 pt** from its own
    /// key, inside both radii, and the key underneath it could never be picked up again. Comparing the
    /// two distances makes the collapsed handle the unreachable one instead, and that is the right
    /// casualty: a node must always be draggable, and a handle is reached by zooming in — which moves
    /// the dot and not the key.
    ///
    /// **Only the focused node has handles**, so this reduces to `nearestKey` on every other node and
    /// on a band with nothing focused. That is what keeps the first stage of the two-stage tap cheap
    /// and unambiguous.
    static func grab(at point: CGPoint, focused: KeyRef?, channels: [Channel],
                     pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> Grab {
        let key = nearestKey(to: point, channels: channels,
                             pixelsPerFrame: pixelsPerFrame, bandHeight: bandHeight)
        guard let focused,
              let channel = channels.first(where: { $0.parameterID == focused.parameterID }),
              let anchor = channel.curve.key(atFrame: focused.frame)
        else { return key.map(Grab.key) ?? .nothing }

        let keyDistance = hypot(x(ofFrame: anchor.frame, pixelsPerFrame: pixelsPerFrame) - point.x,
                                reachableY(ofValue: anchor.value, in: channel.axis,
                                           bandHeight: bandHeight) - point.y)
        var best: (side: HandleSide, distance: CGFloat)?
        for handle in handles(of: focused, in: channels,
                              pixelsPerFrame: pixelsPerFrame, bandHeight: bandHeight) {
            let distance = hypot(handle.point.x - point.x, handle.point.y - point.y)
            guard distance <= handleHitRadius, distance < keyDistance else { continue }
            if best == nil || distance < best!.distance { best = (handle.side, distance) }
        }
        if let best { return .handle(HandleRef(key: focused, side: best.side)) }
        return key.map(Grab.key) ?? .nothing
    }

    /// **Where a handle drag leaves the curve it is shaping** — the whole of the authoring half of
    /// (38)(b), and the answer to *"the graph should be bezier curved"*.
    ///
    /// The curve was **already** bezier before this existed: `AnimationCurve.Key.interpolation`
    /// defaults to `.bezier`, `value(inSegmentStartingAt:)` solves the cubic, and the band has always
    /// drawn one sample per point of that solution. What no gesture in the app could do was *shape*
    /// one — every key ships `.autoClamped`, whose `effectiveHandles(at:)` ignores the stored pair
    /// outright, so an authored handle was unreachable and unreadable. This is the function that
    /// makes the stored pair take effect.
    ///
    /// **Both handles are seeded from the effective pair before either moves, and the mode goes to
    /// `.free` in the same write.** Doing it the obvious way round — flip the mode, then apply the
    /// translation — replaces the derived handles with the stored `.zero`s and **snaps the whole
    /// segment straight at touch-down**, before the finger has travelled a point. Seeding first makes
    /// the switch invisible: at zero translation the curve this returns is identical to the one it
    /// was given. `testTakingAHandleAtZeroTravelChangesNothingAboutTheCurve` is that property, and it
    /// is the one an implementation gets wrong without noticing, because the jump only shows on a key
    /// whose neighbours give it a slope.
    ///
    /// **`.free` rather than `.aligned`.** Aligned would keep the join smooth by moving the *other*
    /// handle under the artist's finger, which is a second thing happening for every one thing asked
    /// for, on a control the artist is meeting for the first time; free is what-you-drag-is-what-you-
    /// get, and the way back to a smooth join is the node menu's Reset Curve rather than a mode the
    /// artist has to know about. `AnimationCurve` carries `.aligned` and enforces it, so the choice
    /// is one line if the owner wants the other one.
    ///
    /// **Nothing is clamped here, and that is `AnimationCurve` decision 3 rather than an omission.**
    /// That decision rules the handle's frame component clamped *on the way out, at evaluation*, so
    /// that "the stored handle keeps what the artist drew" and the editor draws the dot where the
    /// finger left it while the curve stays a function of time. Clamping on the way in would make the
    /// dot stop under a finger that is still moving *and* silently rewrite what was stored.
    ///
    /// Applied to the drag's **starting** curves, exactly as `moves(of:…)` is and for the same
    /// reason: composing this tick's translation onto last tick's result accelerates the handle away
    /// from the finger.
    ///
    /// - Returns: the changed channel keyed by parameter id, or empty when the handle names nothing —
    ///   the same shape `applying(_:to:)` returns, so `writeGraphBandCurves` takes either.
    static func draggingHandle(_ ref: HandleRef, in channels: [Channel], translation: CGSize,
                               pixelsPerFrame: CGFloat, bandHeight: CGFloat) -> [String: AnimationCurve] {
        guard let channel = channels.first(where: { $0.parameterID == ref.key.parameterID }),
              let index = channel.curve.keys.firstIndex(where: { $0.frame == ref.key.frame })
        else { return [:] }
        let axis = channel.axis
        let effective = channel.curve.effectiveHandles(at: index)
        var key = channel.curve.keys[index]
        key.tangentMode = .free
        key.inHandle = effective.inHandle
        key.outHandle = effective.outHandle

        let base = ref.side == .incoming ? effective.inHandle : effective.outHandle
        let from = handleOffset(base, in: axis, pixelsPerFrame: pixelsPerFrame, bandHeight: bandHeight)
        let moved = handle(fromOffset: CGVector(dx: from.dx + translation.width,
                                                dy: from.dy + translation.height),
                           in: axis, pixelsPerFrame: pixelsPerFrame, bandHeight: bandHeight)
        switch ref.side {
        case .incoming: key.inHandle = moved
        case .outgoing: key.outHandle = moved
        }

        var curve = channel.curve
        curve.setKey(key)
        guard curve != channel.curve else { return [:] }
        return [channel.parameterID: curve]
    }

    // MARK: - Telling the curves apart

    /// A curve's colour as hue/saturation/brightness, so the choice stays a value the fast tier can
    /// read. The view is what turns it into a `UIColor`.
    struct Colour: Equatable {
        /// 0…1.
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    /// **Eight hues, hand-picked rather than generated, in degrees.**
    ///
    /// Generated hues (a golden-angle walk, a hash) are stable and evenly spread and cannot be told
    /// where *not* to go, which matters here because two hues are already spoken for on this
    /// surface: ~211° is the playhead and the current-layer highlight, and ~48° is an interpolation
    /// reference — §2.8 exists precisely so the two kinds of "keyframe" are never confused. This
    /// list avoids both, and each neighbouring pair is at least 40° apart.
    ///
    /// Saturation is below full and brightness is at it, which is what reads on the timeline's
    /// black; a fully saturated hue over black is where two adjacent hues stop being distinguishable.
    static let channelHues: [Double] = [145, 28, 195, 320, 90, 262, 8, 172]
    static let channelSaturation: Double = 0.68
    static let channelBrightness: Double = 1

    /// **A channel's colour, from its position in `Effect.parameters`.**
    ///
    /// Stable across launches (no `String.hashValue`, which is seeded per process and would repaint
    /// every curve on every run), stable when a channel starts or stops animating (the descriptor
    /// table does not move), and collision-free for the first eight channels of an effect — which is
    /// all of them for 30 of the 33 parameters, since only `Blur`, `Bloom` and the curve grades
    /// carry more. A ninth animated channel of one effect repeats the first hue; the id is in the
    /// band's accessibility value and D4's list names it, so the repeat is legible rather than
    /// ambiguous.
    static func colour(forDescriptorIndex index: Int) -> Colour {
        let slot = ((index % channelHues.count) + channelHues.count) % channelHues.count
        return Colour(hue: channelHues[slot] / 360,
                      saturation: channelSaturation,
                      brightness: channelBrightness)
    }

    // MARK: - What a test can see

    /// The band's accessibility value: each channel as `id:frame,frame,…`, joined by `|`, and
    /// `"empty"` for a band open on a layer that carries no curve at all.
    ///
    /// **A channel that is not an animation takes a `~` where the `:` would be** — `id~frame,frame,…`
    /// — because the two states are drawn differently and a value that spelled them the same would
    /// make the distinction unassertable from the tier that cannot see the dash. One character, and
    /// it is the separator rather than a suffix so that a reader's eye finds it at the same place in
    /// every entry.
    ///
    /// **An encoded value on one element rather than one element per curve**, which is
    /// `TimelineKeyMarkers.encode`'s convention and `CurveEditor.encode`'s before it, and it exists
    /// for the same reason: XCUITest can see neither a `CGContext` nor a colour, so "there is a
    /// curve for brightness with keys at 0 and 10" is not otherwise assertable at all.
    ///
    /// **`"empty"` is a state worth naming rather than an absence.** The band opens on whichever
    /// layer is selected, including one with no animation on it — saying so is §5.24's rule in
    /// LASSO_MOVE read across: a surface that came up holding nothing should say it did, because
    /// the alternative is an artist looking for a curve that was never there.
    static func encode(_ channels: [Channel]) -> String {
        guard !channels.isEmpty else { return "empty" }
        return channels.map { channel in
            channel.parameterID + (channel.isAnimated ? ":" : "~")
                + channel.curve.keys.map { "\($0.frame)" }.joined(separator: ",")
        }.joined(separator: "|")
    }

    /// **The band's value with D4's filter accounted for, which is one more state than the curves
    /// alone can express.**
    ///
    /// A band the artist has emptied by unchecking every box draws the same nothing as a band on a
    /// layer that carries no curve, and `"empty"` is the wrong word for it: `"empty"` exists because
    /// an artist looking for a curve that was never there is the failure, and here the curves *are*
    /// there. `"hidden"` says the band is blank on purpose and the way back is the list. It is what
    /// the view publishes, and it is why `Content` carries `hiddenCount` rather than only a shorter
    /// `channels`.
    ///
    /// The artist's own version of this distinction is not the accessibility value — it is
    /// `CanvasManager.graphBandHasHiddenChannels`, which tints the button the filter was set from.
    static func encode(_ content: Content) -> String {
        if content.channels.isEmpty && content.hiddenCount > 0 { return "hidden" }
        return encode(content.channels)
    }

    /// **The band's *gesture* state, as a string** — which node's handles are drawn (38)(b).
    ///
    /// **On the accessibility `label` rather than appended to the `value`**, which is the one design
    /// choice here. Every existing assertion in both tiers compares the value against a curve string
    /// — `"brightnessContrast.brightness:0,6"` — so widening it would rewrite tests that are about
    /// something else entirely and make each of them assert two unrelated facts. The band already has
    /// two accessibility slots and was using one.
    ///
    /// `"none"` rather than an omission, so the string's shape is constant and a test can assert the
    /// *absence* of a focus as directly as its presence — which is what the (38)(b) change most needs
    /// pinned, a single tap that no longer deletes having no other visible effect than this.
    static func encodeGesture(focus: KeyRef?) -> String {
        "focus:" + (focus.map { "\($0.parameterID)@\($0.frame)" } ?? "none")
    }
}

extension CanvasManager {

    /// **The row the graph editor band opens under, and how much height it asks for.**
    ///
    /// The **single** derivation, for `TimelineRowLayout.make`'s reason: the pinned name column in
    /// `AnimationTimeline` and the UIKit track in `TimelineTrackView` each build their own layout,
    /// and a band one of them knows about and the other does not shifts every track down while the
    /// names stay put, so a name labels the wrong layer. Both ask this.
    ///
    /// **The band follows the selection rather than being toggled per layer** — the owner's ruling
    /// of 2026-08-29, offered per-layer toggles and an open-every-animated-layer mode. So the state
    /// is one `Bool` and the row is `currentLayerIndex`, which is also the cheapest of the three to
    /// key correctly.
    ///
    /// **Except while a gesture owns the track**, when it is the row `pinGraphBand()` recorded.
    /// Selection is a *side effect* of half the timeline's gestures — picking a block up selects the
    /// layer it came from — so following `currentLayerIndex` unconditionally reflows the whole track
    /// by a band height in the middle of a drag. See `pinGraphBand()`.
    var graphBandExpansion: TimelineRowLayout.Expansion? {
        let row = graphBandPinnedLayerIndex ?? currentLayerIndex
        guard isGraphEditorOpen, layers.indices.contains(row) else { return nil }
        return TimelineRowLayout.Expansion(layerIndex: row, height: TimelineGraphBand.height)
    }

    /// **Hold the band on the row it is on now, for the duration of a gesture that owns the track.**
    ///
    /// The band is part of its row's *height* (§11.2's seam), so relocating it moves every row
    /// between the old position and the new one by 96 pt. That is correct and wanted when the artist
    /// selects another layer, and ruinous when the selection was a side effect of a gesture already
    /// in flight: `beginBlockDrag` writes `currentLayerIndex` and then relayouts inside the same
    /// touch, so the grabbed row travels a band height while the finger does not. The ghost detaches
    /// by that much, and — worse, because it is silent and changes the document —
    /// `layerIndex(atY:)` then resolves the unmoved finger against the moved rows and the block is
    /// dropped on a **different layer** than the one under it.
    ///
    /// **Only the row is held, not whether the band is open**: the toggle is a button press, which
    /// cannot happen under a finger that is already dragging the track.
    ///
    /// **Only the block drag takes this.** A cel resize, a ruler scrub and the name column's reorder
    /// all leave `currentLayerIndex` alone for the length of the gesture, so there is nothing for
    /// them to hold and a call in them would be a control that never fires. A gesture that starts
    /// selecting a layer mid-flight must take one.
    func pinGraphBand() {
        graphBandPinnedLayerIndex = currentLayerIndex
    }

    /// Lets the band go where the selection has moved to. Safe to call with nothing pinned, which is
    /// what makes the release unconditional at the top of `endBlockDrag` rather than paired with the
    /// guard that decides whether there was a drag at all.
    func releaseGraphBand() {
        graphBandPinnedLayerIndex = nil
    }

    /// **What the open band draws**, or nil when it is closed.
    ///
    /// Read once per layout into `TimelineLayoutKey`, and the view draws out of the key rather than
    /// calling this a second time — §11.3's first silent failure, closed the way `trackMarkers`
    /// closes it: "drawn from" and "keyed on" are the same array by construction.
    ///
    /// Costs nothing while the band is closed, which is every document that has not opened it: one
    /// `Bool` and a return.
    ///
    /// **D4's channel filter is applied *here*, before the key is built, and that placement is the
    /// whole of §11.5's silent failure.** `relayout()` early-returns on `built.key == laidOutKey`, so
    /// a filter applied any later — in `TimelineGraphBandView.draw`, say, reading the manager — would
    /// change what the band should draw without changing the key, and unchecking a box would move
    /// nothing on screen until some unrelated edit happened to reopen the gate. Filtering into
    /// `channels` makes the key move for free and leaves the drawing code untouched, which is the
    /// same bargain `trackMarkers` takes: what is drawn *is* what is keyed on.
    var graphBandContent: TimelineGraphBand.Content? {
        guard let expansion = graphBandExpansion,
              let target = keyframeTarget(layerIndex: expansion.layerIndex)
        else { return nil }
        // **`allChannels`, not `channels`** — every curve the layer carries, animation or not, each
        // tagged. §11.4's vanishing channel: with only animations drawn, tapping away a channel's
        // second-to-last key took the whole curve out of the band under the finger that was editing
        // it, and left the band unable to put it back.
        let all = TimelineGraphBand.allChannels(effect: storedEffect(of: target),
                                                tracks: keyframeState(of: target).tracks)
        let shown = TimelineGraphChannelList.visible(all,
                                                     hidden: graphChannelFilter.hidden(on: target))
        return TimelineGraphBand.Content(layerIndex: expansion.layerIndex,
                                         height: expansion.height,
                                         channels: shown,
                                         hiddenCount: all.count - shown.count,
                                         // The scene's length, not the track's — see
                                         // `drawnFrameCount`. Read here rather than in the view
                                         // because it is an input to the drawing and therefore has
                                         // to be inside the layout key.
                                         frameCount: TimelineGraphBand.drawnFrameCount(
                                             sceneFrameCount: sceneFrameCount, channels: shown))
    }
}
