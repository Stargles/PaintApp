# Handoff — 2026-08-30 (session 79)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md, KEYFRAMES.md and TODO.md. ROADMAP.md no longer exists — its six
features are TODO items (21) and (26)-(30) under "Later".

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is clean, one worktree, no branches. **Full suite 2373 passed / 0 failed / 6 skipped.
Fast tier 2248 / 0 failed / 3 skipped.**

**Two standing instructions from the owner about how you work. Both were given this pass and both
were given because they were violated.**

1. **Conserve tokens, and state the size of a multi-agent run BEFORE you launch it.** An eleven-agent
   workflow was killed mid-flight at 95% weekly usage; the question it existed to answer took three
   greps. Default to answering directly. Delegate building and test runs, not thinking you can do.
2. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no "at
   the owner's instruction", no "this used to be", no narrating which premise an investigation
   overturned. Keep the ask in the owner's words, the decision, non-obvious reasoning, trap warnings
   and file:line evidence. Cut the rest.

**1. Build KEYFRAMES §8 stage 5 — the transform channel. The owner ruled it comes before stage 4.**
   Quad keys, animation groups, §2.5's write-at-commit, §4.3's factored interpolation, Uniform +
   Freeform. **The gate that could have reversed that order is already answered**:
   `drawn(_:through:widthScale:)` (`Engine/VectorLayer.swift:2262`) takes a `CGAffineTransform` and
   **one scalar** width — and an affine has a constant Jacobian, so `sqrt(|det|)` (LASSO_MOVE §5.17)
   is the same everywhere in the stroke and one number is exactly right for Uniform and Freeform.
   Per-dab width is a **projective** problem, so it belongs to stage 5b (Distort), not here. Stage 4
   is not a prerequisite. The owner has also already ruled the interpolation shimmer imperceptible on
   the device, so posing ink through the shipped path is licensed.
   **§4.5 is where this fails silently if it fails.** `PixelOps.rasterize`'s memo has no pose field
   while `SandwichKey` compares the whole node tree — a posed frame composites happily from a stale
   un-posed image: green tests, wrong pixels, no key that looks wrong. Enumerate every cache key
   before writing code, not after. A plan reviewed this pass missed five of them.
   Stage 5 also owes a derivation **identity** that includes the frame, where interpolation's
   deliberately does not (KEYFRAMES §8, `CelContentProvider`).

**2. What else is open.** (22) the cel marquee — the owner put it in the future themselves. (23)
   selection membership moves to Select — they said not priority. (10) linear light **as an option on
   the blend mode**, deprioritised, with five things any implementation must handle already listed in
   the item. (24) is answered "do not" and can be closed on read. (26)-(30) are the long-term
   features and **each needs a design conversation with the owner before it starts** — an item built
   from its TODO entry alone was built wrong.
   **(28)'s first move is not an audio feature**: the playback clock is a `Timer` whose state lives
   on the view (`Views/AnimationTimeline.swift:13-14`, timer at `:976-989`), so it drifts. Hoisting it
   onto the model is a timeline change that (28), KEYFRAMES §5 and (29) all need.

**3. The cost model changed and CLAUDE.md now says so.** MEASURED on an idle machine: **2358 tests in
   24.4 min**, 3,893 class-seconds over 102 classes — 16.2 min of ideal work on four clones, longest
   class 5.7 min. **For the first time the gap is not an indivisible class**: ~7 min, 45% over ideal,
   is scheduling. Splitting further cannot recover it and past some point makes it worse. Do not
   reach for a class split as the lever without re-taking the table.
   `SandwichCompositingUITests` (344 s) is the longest class and produced an environmental red in
   each of two runs.

**4. The traps this pass paid for.**
   - **A shipped spec's "what is already true" section describes the world before its own build order
     ran.** EFFECT_BACKDROP §0 says the paper is not in the composite; it has been since §6 shipped.
     Quoting it as current produced a wrong scope argument to the owner. §0 now carries a banner.
     Check any §0 against the build order below it.
   - **A filter is unpinned until its fixture holds something the filter must reject.** The §2.28 pin
     animated both fixture channels, so deleting the filter returned an identical array — green under
     an implementation with no filter at all. Fourth occurrence of this shape.
   - **A red suite under load is evidence about the machine.** Measuring the full run while a
     workflow compiled on the same cores cost four minutes of wall clock while leaving per-class
     seconds within noise — so the table looked right and the headline was wrong.
   - **This suite has no tier that can see a rendered pixel.** Budget a look at any visual feature.
     Two of the three graph-editor defects fixed this pass were found only by screenshot.

**Do not re-litigate**: KEYFRAMES §2's twenty-eight rulings and §11.6's three; LASSO_MOVE §5's
twenty-five; CANVAS_RESIZE §5 and §6; EFFECT_BACKDROP §5 and §2.1; (10)'s per-blend-mode scope; the
greys ruling in `Effect.gradientColour`; stage 5 before stage 4.
```

---

## State

`main` is clean, one worktree, no branches. **Full suite 2373 passed / 0 failed / 6 skipped.** Fast
tier **2248 / 0 / 3**.

**A Release build of `7c38ba2` is on the iPad**, installed 2026-08-30 01:34. Everything merged since —
the Oklab ramps, the dark colour scheme, all three graph-editor fixes — **is not on the device**. The
last build *confirmed* on it is `a85a316`. Ask the owner rather than assuming.

## What landed

**(10a) Oklab ramps.** `ColorMath` gained sRGB↔linear and Oklab both ways; `Effect`'s gradient ramp
mixes through it; the picker's hue bar went 7 samples → 73; the settings-panel gradient preview is
resampled from the same evaluator, which fixed an unreported bug — it was a plain gradient over the
raw stops and could disagree with the render by **85/255**. Pictures in `docs/oklab-ramps/`, generator
`tools/oklab_ramp_ab.swift`. The owner ruled its one cost intended: a black-to-white Gradient Map
darkens midtones by up to 31/255, recorded in `Effect.gradientColour` so it is not "fixed" later.

**The graph editor's three visible defects.** Curves stop at the document end rather than running two
screenfuls into dead track; the app declares `.preferredColorScheme(.dark)` globally — chosen over a
per-surface fix because ~20 editor surfaces inherit system appearance and `Menu`/`alert`/`contextMenu`/
`ColorPicker` have no background to set at all; and a channel that stops being an animation goes
dashed and dimmed instead of vanishing under the finger. Before/after screenshots in
`docs/graph-editor/`. The 250 pt timeline height was deliberately left alone, with the reasoning
recorded so it is not re-derived.

**The cost model, re-measured and re-explained.** See the paste block.

**Documentation.** ROADMAP.md deleted, 644 lines folded into TODO as (26)-(30). EFFECT_BACKDROP §0
banner. The eyedropper doc now carries the margin ruling it had been hiding since 2026-08-27.

## Still open

KEYFRAMES §8 stage 5 onward; §9's four open questions. TODO (22), (23), (10), (26)-(30).
`ARCHITECTURE_REVIEW.md` findings 2-4.

BUGS.md carries the popover that re-presents itself, the track's `draw(_:)` view widths, the
interactive-gesture CPU composites, Fill/Clear on a derived in-between, the raster-storage bound, the
unclamped zoom, `TextFrame.homography` decoding with no validity check, PERFORMANCE item 14, the
narrowed mask-cache structural gap, and the folder-row accessibility gap.

Two behaviour questions are still owed: save semantics when a project loaded with something
unreadable, and which faces belong in the font picker's favourites strip.

**Found and deliberately not fixed**: `TimelineGraphBand.channels(effect:tracks:)` has no caller in
the app any more — documented in its own doc rather than deleted minutes after the run that verified
it, and a later pass should remove it. The band's backing store is `totalWidth × 96` and the largest
single store on the track, left because *every* view on the track is `totalWidth` wide and the fix
belongs to the track. Colour, toggle and picker rows still write a whole resolved `Effect`. Stepped
and compound parameters still cannot be keyed. Six of the thirteen effects never match an XCUITest
query, almost certainly a scrollable-menu accessibility limit, and will read as a broken app to
whoever reaches for one next.
