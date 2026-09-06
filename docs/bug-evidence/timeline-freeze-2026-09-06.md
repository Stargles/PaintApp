# The timeline freeze — TODO (39)(c), traced 2026-09-06

The owner captured it with the ActionRecorder. Trace:
[timeline-freeze-2026-09-06.jsonl](timeline-freeze-2026-09-06.jsonl), 571 events over 32.4 s, app
v1.0.43, iPad 9 (iPad12,1), iOS 26.5.2, canvas 2048².

Their note on where to look: *"After it happened, i swiped a back and fourth a bunch on the timeline,
then clicked actions, scrolled down, and clicked stop record."*

> **Read this file from the bottom section up if you are short of time.** The two analyses above it
> are kept because each one's *refutation* is the useful part, but both located the freeze in the
> wrong place and neither named the cause. The cause is **reproduced** and is in the last section.

---

## Reading 1 (superseded) — "the row view is detached"

**The freeze window is t ≈ 11.5 s → 26.5 s.** In it the owner produced **220 touches, 38 of them
touch-downs**, almost all hit-testing to `TimelineRowView` — and `currentFrame` moved **twice**.

**The cause is visible in the gesture-recognizer set attached to each touch** (`grNames`):

| | touch-downs on a timeline row | with a scroll-view pan attached | with a tap attached |
|---|---|---|---|
| before, 0–11.5 s | 17 | **17/17** | 17/17 |
| during, 11.5–26.5 s | 34 | **20/34** | 25/34 |

So the row view under the finger is **still on screen and still hit-testable, but its ancestor chain no
longer contains the scroll views**.

**Refuted.** The row's own `tapRecognizer` carries no delegate and is added in `init`, so a live row
offers it to every touch — and it is missing from 9 of the 14 dead touches. Re-parenting a view cannot
remove *its own* recogniser. At t=21.98 a `TimelineRulerView` keeps its own long press while carrying
none of its ancestors', so the ruler is affected too and it is not a recycled row. And `grNames` drifts
inside the healthy window as well.

## Reading 2 (superseded) — "a recogniser is wedged out of `.possible`"

That a recogniser which has failed for a sequence is not offered later touches, while the views stay
hit-testable, is the right *shape* — but it is not what is happening. The concrete suspect this reading
handed on was `TimelineTrackView.Coordinator.relayout`'s
`scrollView.panGestureRecognizer.require(toFail: row.panRecognizer)`: called once per row view ever
created, never undone, on a pool that grows and shrinks.

**Refuted, MEASURED** (iPad Pro 13-inch M4 simulator, iOS 26.5, 2026-09-06). There is no accumulation:

- `UIGestureRecognizer._failureRequirements` is an `NSSet` that **deduplicates** — the same pair
  required three times is one entry — and holds its members **weakly**: required recogniser
  deallocated, count **1 → 0**.
- `UIGestureRecognizer` does **not** retain the target it was created with, so a `TimelineRowView` that
  leaves the pool deallocates and takes its pan with it.
- Nothing else prunes the set and nothing needs to: `removeGestureRecognizer`, `removeFromSuperview`
  and `isEnabled = false` all leave the entry at 1 while the recogniser is alive, which is correct.
- A first harness *appeared* to show the set growing 3, 6, 9, 12, 15, 18 across six add-3/remove-3
  cycles. It was measuring **its own autorelease pool**. The identical cycles wrapped in
  `autoreleasepool` read **18, 18, 18, 18, 18, 18** — flat.

`TimelineGestureArbitrationLogicTests` pins this through public API (weak references, no private
ivar), so it goes red the day a future UIKit starts retaining — which is the day `relayout` *would*
become a leak.

**And driven end to end for good measure**: five cycles of adding three layers and deleting three
through the real layer panel — fifteen row views created and destroyed, so fifteen `require(toFail:)`
calls the pool cannot take back — with a 200 pt swipe on the track after each. The track scrolled
every time (188.0 → −181.5, then −189.0, −189.0, −189.0, −209.5, −209.5). Pool churn is not the
lever.

---

## What the trace actually shows

Both readings above are built on `grNames`, and neither reconstructed the **gestures**. Doing that
changes the picture completely. Grouping every touch from `began` to `ended` and measuring how far it
travelled:

- **Almost every "dead" touch is a swipe, not a tap** — 24 to 282 pt of horizontal travel over
  0.1–0.5 s. The owner said so: *"i swiped a back and fourth a bunch on the timeline."*
- **Every genuine tap worked.** t=18.38 (1.0 pt of travel) → `currentFrame` 3 at t=18.43. t=19.96
  (1.0 pt) → `currentFrame` 5 at t=20.01. The frames at t=6.47–6.63 came from a **drag on the ruler**
  at t=6.45, which is the scrub.
- **A drag along a row is supposed to scroll the track, not scrub** — the row's pan declines body and
  gap touches in `shouldReceive` precisely so the enclosing scroll view gets them. Scrolling leaves no
  model event, so the trace cannot say whether it happened, and 11.5–18.4 is **not** evidence of a
  freeze.

**The freeze is five seconds long, not fifteen, and it starts at t ≈ 21.**

- t=20.23 — a tap of 1.0 pt travel, 14 pt from the one that had just set `currentFrame` to 5.
  INFERRED (the trace records no menu event): that is `handleTapOnCel` / `handleTapOnGap`'s second
  stage — `clamped == currentFrame` on the current layer — and **it raises a menu**. What is MEASURED
  is that a popover is up one second later.
- t=21.00 — the first row touch carrying `_UIPassthroughScrollGestureRecognizer` and
  `_UIPassthroughGateGestureRecognizer`. Those are `UIPopoverPresentationController`'s. **A popover is
  up.**
- t=21.58 onward — every row touch collapses to a handful of recognizers and **not one timeline
  gesture fires again**, including a 63 pt drag on the ruler at t=21.98 that is carrying the ruler's
  own long press.
- t=26.57 — the owner **taps** the toolbar; `activePanel = actions` at t=26.68 and the app is normal
  again. A tap is the one thing that gets out.

## The cause, reproduced

**While a timeline menu popover is open, every drag anywhere on the timeline is swallowed whole: the
track does not scroll, the ruler does not scrub, and the popover does not dismiss. Only a tap
dismisses it.** An artist who raises a menu by accident and reacts by swiping the track has a timeline
that stays dead for as long as they keep swiping.

MEASURED in the simulator, from a new document (`MenuInterruptionUITests`
`testADragOnTheTimelineWhileABlockMenuIsUpIsSwallowedWhole`), two taps on a block to raise the menu,
then a 200 pt drag on the track 200 pt clear of the popover:

| | cel block's x | playhead | menu |
|---|---|---|---|
| menu up, after drag 1 | 188.0 → **188.0** | 7 → **7** | still up |
| menu up, after drag 2 | **188.0** | **7** | still up |
| after a **tap** in the same place | 188.0 | 7 | **dismissed** |
| menu gone, same drag | 188.0 → **−181.5** | 7 | — |

Five consecutive drags in an earlier probe: the menu survived all five and nothing moved.

**And the hierarchy is intact, which retires reading 1 for good.** Logging the row's whole ancestor
chain from `hitTest` while the popover is up, over 15 hit-tests during the dead drags: **every one
carries `timeline.row0.tap`, `timeline.row0.resize`, `timeline.row0.press`, `timeline.pinch`,
`timeline.scroll` and both `UIScrollViewPanGestureRecognizer`s** — plus
`_UIPassthroughGateGestureRecognizer` above them. `hitTest` returns the row every time. And
`TimelineRowView.touchesBegan` **never fires**. So the recognizers are all still attached and the
view is still in the scroll views; UIKit simply does not offer them the touch. (Their *states* were
not read, so reading 2's wedge cannot be disproved that way — but it does not need to be: a wedge
would have to reach the row's delegate-less tap, the ruler's long press, the pinch and both scroll
pans at once, and clear the instant the owner taps the toolbar.) `grNames` is `touch.gestureRecognizers`, which is UIKit's
*offered* set, and the passthrough gate is what prunes it — that is the whole of the column both
readings above were built on.

## What the fix turned out to be — built 2026-09-06

There is no in-app seam *while it is a popover*: the touch reaches `hitTest` and is then routed to the
popover's dismissal machinery, so nothing in `TimelineTrackView` can see it. Two measured dead ends,
kept because each is a plausible fix somebody will otherwise try again:

- **`.presentationBackgroundInteraction(.enabled)` on the menu content changes nothing.** It is a
  sheet API; a popover ignores it. Applied to `AnimationTimeline.menuList` and re-measured: identical
  numbers to the table above.
- `UIPopoverPresentationController.passthroughViews` is what would actually do it, and SwiftUI's
  `.popover` does not expose it. **The owner ruled against it anyway** on 2026-09-06: passthrough lets
  the drag through but leaves the menu standing while the track scrolls out from under it, and a cel
  menu names a *specific block*. That is a worse bug than the one being fixed.

**So the four timeline menus stopped being presentations.** `PaintSoftware/Views/AnchoredMenu.swift`
draws them inside the timeline's own hierarchy, sized to their content and positioned by
`AnchoredMenuPlacement`, so they capture exactly what they cover and nothing else. Dismissal is a
`PassiveTouchDownObserver` — a `UIGestureRecognizer` on the window that reports the touch-down location
and then immediately fails, with `cancelsTouchesInView = false`, so it delays nothing, cancels nothing
and competes with nothing. The touch it reported goes on to reach whatever was under it.

**One drag therefore does both**, which is the requirement the passthrough option could not meet.
MEASURED in the simulator at the fix, from a new document: with the block menu up, a single 250 pt drag
on the track dismissed the menu **and** scrolled the ruler from frames 1–28 to 18–45. The same gesture
before the fix moved the cel block 0.0 pt and left the menu standing.

All four were converted — `timelineSlotMenu`, `onionSkinOptions`, `interpolateOptions`,
`graphChannelList` — and each keeps its `CanvasPresentation` case and its registration, so the central
canvas-touch rule, the `onDismiss`-on-host-deletion guarantee and the `ActionRecorder` capture are all
unchanged. Only who draws them moved.
