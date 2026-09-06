# The timeline freeze — TODO (39)(c), traced 2026-09-06

The owner captured it with the ActionRecorder. Trace:
[timeline-freeze-2026-09-06.jsonl](timeline-freeze-2026-09-06.jsonl), 571 events over 32.4 s, app
v1.0.43, iPad 9 (iPad12,1), iOS 26.5.2, canvas 2048².

Their note on where to look: *"After it happened, i swiped a back and fourth a bunch on the timeline,
then clicked actions, scrolled down, and clicked stop record."*

## What the trace says

**The freeze window is t ≈ 11.5 s → 26.5 s.** In it the owner produced **220 touches, 38 of them
touch-downs**, almost all hit-testing to `TimelineRowView` — and `currentFrame` moved **twice**. Before
it, the same view and the same kinds of touch were scrubbing frames normally.

**The cause is visible in the gesture-recognizer set attached to each touch** (`grNames`):

| | touch-downs on a timeline row | with a scroll-view pan attached | with a tap attached |
|---|---|---|---|
| before, 0–11.5 s | 17 | **17/17** | 17/17 |
| during, 11.5–26.5 s | 34 | **20/34** | 25/34 |

**14 of 34 touch-downs during the freeze carry no scroll-view recognizer at all.** Their whole set is
`_UISystemGestureGateGestureRecognizer` plus two `_UIFlexInteraction.Pan` — system gates only. Before
the freeze that never happens once.

So the row view under the finger is **still on screen and still hit-testable, but its ancestor chain no
longer contains the scroll views**. Nothing in the timeline can respond to those touches, because no
recognizer that would act is watching them. The remaining 20 touches land on live rows, which is why
`currentFrame` moved twice and why the freeze reads as intermittent rather than total.

**This is a detached-view problem, not a gesture-arbitration one.** CLAUDE.md's standing suspicion was
an unresolved `require(toFail:)` between the scroll view's pan and the row/ruler long-presses. That is
**refuted**: during the freeze the recognizers are not losing an arbitration, they are *not attached*.
The count of ancestor `_UIFlexInteraction.Pan` interactions also drops from 5 to 2, which is the same
fact seen from the other end — the responder chain above the row is shorter than it should be.

## What immediately precedes it

- t = 6.47–6.63 — `currentFrame` 16 → 20, ordinary scrubbing.
- t = 9.63 — a pencil stroke on the canvas. `layers: added cel on layer 0 at frame 20, length 1 — now
  2 layers, active 0`. **Note frame 20 against `sceneFrameCount`'s default of 12** — see TODO (50).
- t = 11.17–11.41 — finger touches on the canvas ending in `canvas.twoFingerTap possible → ended`.
- t = 11.95 — the first dead touch on `TimelineRowView`.

So the timeline stops responding **immediately after a cel is created past the old scene end and a
two-finger tap fires**. Whether either is causal is unproven; the cel-past-the-end is the more
interesting of the two because it forces the track content to re-lay out, and a re-layout is exactly
when a row view would be rebuilt and an old one left detached.

## What the trace cannot say

The recorder instruments the **canvas** view's recognizers only — every `recognizer` and
`requireFailure` event in the file is a `canvas.*` or `stroke.*` one. So the absence of recognizer
state transitions during the freeze is **not** evidence about the timeline's own recognizers; it only
means the recorder does not watch them. The `grNames` column is what carries the finding, because it
is recorded per touch from the touch itself.

Instrumenting the timeline's recognizers the way the canvas's are would make the next trace of this
much sharper, and is cheap.

---

## Correction, 2026-09-06 — the conclusion above does not follow from the table above

Everything down to "What the trace says" holds: 34 touch-downs on a `TimelineRowView` in fifteen
seconds, `currentFrame` moved twice. **"The row view is on screen but its ancestor chain no longer
contains the scroll views" is wrong**, and three things in this same file say so.

**The row's own tap recogniser is missing too, and re-parenting cannot do that.**
`TimelineRowView.tapRecognizer` is added in `init` and — unlike the pan and the long press — carries
**no delegate**, so a live row is offered it on every touch. MEASURED in a clean simulator capture
(iPad Pro 13-inch M4, iOS 26.5, 2026-09-06): present in **100 %** of row touch-downs. In the freeze
window here it is absent from **9 of the 14** dead touches. Moving a view changes which *ancestors'*
recognizers a touch sees; it cannot take away the view's own.

**The ruler is affected as well, and it kept its own recogniser.** At t=21.98 a `TimelineRulerView`
touch carries `UILongPressGestureRecognizer` — the ruler's own scrub — and none of its ancestors'.
The ruler and the rows are siblings in one `contentView`, so whatever this is reaches the whole
subtree; it is not one recycled row left behind by a re-layout.

**And `grNames` drifts inside the healthy window too.** t=5.80 has one `UIScrollViewPanGestureRecognizer`
and no delayed-touches; t=8.23 has two of each. So "before it, 17 of 17 carry the full set" overstates
what the column can support — the *set* varies with recogniser state, not only with parenting.

**What does fit is the timeline's recognizers wedged in a non-`.possible` state.** A recogniser that
has failed for a sequence is not offered later touches while the views stay perfectly hit-testable,
which is the exact signature here. The clean capture shows `timeline.scroll` sitting in `.failed` for
seconds at a stretch between sweeps, so the state is ordinary; what is not known is what holds it
there.

**Not reproduced.** Five sequences driven in the simulator on 2026-09-06 — plain row taps; a cel
created at frame 20 with `sceneFrameCount` still 12, then taps; the gap menu raised and dismissed;
repeated two-finger swipes across the track; a pinch — and the timeline scrubbed after every one. The
cel-past-the-scene-end lead this document offers is therefore refuted as a trigger on its own.

**The next capture will settle it.** The timeline's recognizers are now named for `ActionRecorder`
(`timeline.scroll`, `timeline.pinch`, `timeline.rulerScrub`, `timeline.graphBand`, and
`timeline.row<N>.tap` / `.press` / `.resize`), so a recording of the freeze now carries their state
transitions rather than only the per-touch `grNames`. That is the one thing this trace could not say.
