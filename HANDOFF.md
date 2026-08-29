# Handoff — 2026-08-29 (session 76)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md, KEYFRAMES.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is `0717ed6` plus the close-out commits above it. **Fast tier 2098 / 2095 / 0 / 3.**
**Full suite at `0717ed6`: 2221 / 2214 / 1 / 6**, the one red environmental and confirmed by isolated
re-run. No branches in flight, one worktree, clean tree. The iPad has current `main`.

**1. Keyframes reached the artist this pass. Stage 3b is next and it is the harder half.**
   Stages 0–3a are merged: hold the keyframe button 0.8 s to arm **Animate mode**, move an effect
   slider, and a key lands at the playhead — on a layer's grade or a folder's, through one writer.
   Key markers are visible on the timeline. **Stage 3b is the channel panel and the graph-editor
   drawer**, and §8's row for it now carries what §10 established the hard way:

   **§2.17's drawer is a constraint, not a layout preference.** `pixelsPerFrame` is `private(set)` on
   `TimelineTrackView.Coordinator`, `contentOffset.x` is published nowhere, and the ruler and playhead
   are `private final class`es in that file — so **nothing outside the coordinator can map frame N to
   an x**, and a drawer placed above the panel drifts out of register on the first pinch-zoom. It
   lives inside the scroll content. §10 lists the five things that then follow, **each of which fails
   silently**: the `TimelineLayoutKey` early-return, the content-height formula that exists twice, the
   name column's hard-coded spacer, `panGestureRecognizer.require(toFail:)`, and a playhead that is a
   *column* up to 120 pt wide rather than a hairline.

   And before writing either surface: **decide which shape it is.** `CanvasPresentation` covers only
   `Binding`-held popovers; an inline docked panel is not one and adding a case for it would be wrong;
   an `ActivePanel` case is a third thing that re-derives `CanvasTouchOwnerLogicTests`' 1_920/440.

**2. The pass's biggest finding was a scope gap, and it was found by the owner asking why a number was
   big.** **KEYFRAMES §4.6's span cache scopes itself, in its own closing line, to "the transformation
   layer and, later, for export"** — so it was never pointed at *interpolation* in-betweens. Shipping
   stage 6b exactly as specified leaves a generated in-between costing precisely what it costs today.
   Do not plan around that cache covering playback of interpolated spans; it does not.

**3. Realtime playback is a bigger target than it looks, and PERFORMANCE §8 is the shortlist.**
   **Composited playback already misses 24 fps on the device in Release with no interpolation in the
   document** — 54.8 ms Metal against a 41.6 ms budget, recorded since 2026-08-20 (§2 item 5). §8's
   five entries are written from what the tree records; nothing is started. **Its two cheapest entries
   share one prerequisite — hoisting the playback clock onto the model — which ROADMAP §4 (audio) and
   KEYFRAMES §5 (recording) already require.** That makes the clock the natural first move.

**4. The iPad is current — it has this pass's `main`, Release**, so Animate mode, the key markers, the
   `ContentProvider` seam and the compositor change are all on the device and the owner can try them.
   Deployed twice this pass, both times `available (paired)`; the first install needed the documented
   `NWError 54` retry and the second did not. **When it next goes stale, redeploy from a worktree and
   not `deploy.sh`** — that script pulls `main` from a different checkout and so never ships branch
   work. Run `devicectl list devices` first: `unavailable` means the owner must wake and unlock the
   iPad, `info details` will answer from cache and *look* like it worked, and nothing on this Mac
   fixes it.

**5. TODO (10) Oklab is still untouched and its first move is still not to build anything.** Stage A
   is **linear-light compositing through a 256-entry LUT**, not Oklab. **Render the A/B and show it
   before building** — this owner reverses on a picture what they accept on a number, and that
   happened again this pass.

**Do not re-litigate**: KEYFRAMES §2's **twenty-five** rulings; LASSO_MOVE §5's twenty-five;
CANVAS_RESIZE §5 and §6; EFFECT_BACKDROP §5 and §2.1; (10)'s three-stage recommendation.

**Two process rules the owner gave this pass, and one is about how you spend their money.**
**When the owner describes a feature for later, write the ask down — do not commission research.**
Verbatim: *"the research is ultimately not for a future session, not you. You are supposed to be
working on the tasks, the asks i give you for future sessions, just write them down."* Two agent
fleets were stopped mid-flight on that instruction. And **if you ever do stop background work,
harvest it first** — one of six agents had already returned the pass's biggest finding, and it was
nearly thrown away.

**The trap this pass paid for is a measurement one, and it was the orchestrator's.** Three
simulator-bound agents at once took the machine to **1.5% idle while two of them were taking
performance measurements**, voiding every figure they produced (idle ranged 0–34.8%). CLAUDE.md
already says this returns *wrong answers rather than slow ones*; it does not say the obvious
corollary, which is that **the orchestrator is the third caller `simlock`'s two slots do not
account for**. Serialise anything that measures.
```

---

## State

`main` = `0717ed6` plus the close-out commits above it. **Fast tier 2098 total / 2095 passed / 0 failed
/ 3 skipped**, up from 2022 at the start of the pass. Static `func test` count moved with it.

**FULL SUITE at `0717ed6`: 2221 total / 2214 passed / 1 failed / 6 skipped**, parallel, on a freshly
erased `eraser-mutex-test`. Up from **2125 / 2118 / 1 / 6** at `05a3e7c`. The one red —
`LayerPanelUITests.testTappingSelectedLayerOpensOptionsAndTogglesFillReference`, *"A second tap on the
now-selected layer should open its options"* — **passed clean in isolation** (24.8 s, zero failures, after
an erase). Environmental. Nothing owed.

**But the run took 25.6 minutes, which is where the suite sat *before* the 2026-08-15 split**, and the
reason is one class: **`LayerPanelUITests` is 517 s across 19 tests**, 2.7x the 189 s test that used to be
the floor. Total class-work is 3,607 s — about 15 min of ideal work for four clones — so the extra ten
minutes is that one indivisible class. **Splitting it is the highest-value cheap job available and it is
the same fix that worked before**; it lives in `LayerUITests.swift`, which already holds three classes.
The measured table is now in CLAUDE.md's cost-model section, replacing the floor claim it invalidated.
It is also, not coincidentally, the class that produced the environmental red.

No branches. One worktree. Clean tree.

## What landed

**Keyframes went from "nothing is visible to the artist" to a feature they can use**, plus one piece of
groundwork that serves both animation systems.

- **`444adce`, `8942477`, `965df1a`** — rulings §2.21 to §2.25, each recorded with its *reasoning*,
  because that is what stops a later session undoing it.
- **`6158e8b` stage 2b** — a folder's grade animates exactly as a layer's (§2.21), and it forced a
  two-week-old deferred defect into the open (below).
- **`531cb0a`** — **`CelContentProvider`**, VECTOR_INTERPOLATION item 18. A derived cel is no longer
  blank in thumbnails, onion skin, mask resolution, layer flatten or the magic wand.
- **`f2f85b5` stage 3a** — Animate mode, the keyframe button, and the settings bar finally reading the
  value at the playhead.
- **`11862a0`** — timeline key markers, with a gap-based collapse rather than a zoom flag, so **keys on
  twos stay countable at every zoom** (which §2.10 makes load-bearing).
- **`5c88276`** — the compositor stays engaged on in-between frames: blend modes, effects and mask
  clipping work there now, where they were silently off.
- **`280bbcb`, `64c48dd`, `0717ed6`** — ROADMAP §5b (background baking, asked for, unscheduled),
  the disk-first ask recorded verbatim, and PERFORMANCE §8's playback shortlist.

## What this pass learned that outlives it

- **A deferred invalidation gap is cheap only while nothing animates its input.** `MaskResolver`'s key
  is per-*layer* content versions and a folder is not a leaf, so a mask over a graded group had served
  stale coverage since 2026-08-15 — filed and deferred *because it needed an artist edit to bite*.
  A keyframe changes that grade on every frame of playback. Fixed, mutation-verified.
- **Removing a clause can ship a frozen canvas.** Dropping the compositor's in-between exclusion alone
  would have frozen the canvas on its first composited in-between: the sandwich key was built without
  the derivation, and `t` moves no version and no object identity. Closed by **one builder both call
  sites share** rather than two hand-maintained field lists — the same cure the `ContentProvider`
  identity uses, and the one `InterpolationPreviewKey` still needs.
- **`InterpolationPreviewKey` was missing a *fourth* field** nobody had named: `.reproject`'s subject
  version, which is that mode's entire content.
- **A disabled control cannot be held.** The brief said to disable the keyframe button when nothing is
  animated; that would have made Animate mode unreachable on a fresh document by the exact gesture that
  creates the first track.
- **A parameter that is always true is a comment pretending to be a condition.** `targetSupportsTracks`
  became `KeyframeTarget`, and §2.21's sameness is structural rather than two arms kept in step.
- **`pgrep -f` counts substrings, not processes** — about 3x per run, and it matches its own caller.
  Now in CLAUDE.md, along with the cleanup filter that protected 962 processes out of 962, and the rule
  that a worker told to wait must be told *how*: block on one wait, do not queue timers.

## Still open, unchanged

TODO (10) Oklab. `ARCHITECTURE_REVIEW.md` findings 2-4. KEYFRAMES §9 has **four** open questions (the
owner's boil question is answered — no visible shimmer today, and they named **custom brush import** as
what would change that, which is now recorded in BRUSH_ENGINE_EXTENSIBILITY.md as a dependency rather
than an optimisation). BUGS.md carries the interactive-gesture CPU composites, Fill/Clear on a derived
in-between, the raster-storage bound, the unclamped zoom, `TextFrame.homography` decoding with no
validity check, PERFORMANCE item 14, and the narrowed mask-cache structural gap.

Two behaviour questions are owed: save semantics when a project loaded with something unreadable, and
which faces belong in the font picker's favourites strip.

**Found and deliberately not fixed this pass**: a collapsed folder hides its children's key markers
(worth a decision when the channel panel lands); colour/toggle/picker rows still write a whole resolved
`Effect`; stepped and compound parameters still cannot be keyed; and the **Render Resolution knob does
not reach the expensive half** of a derived frame — it is currently a control that does not do what a
user would assume.
