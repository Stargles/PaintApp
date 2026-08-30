# Handoff — 2026-08-29 (session 77)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md, KEYFRAMES.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is `4b86966` plus the close-out commits above it. **Fast tier 2153 / 2150 / 0 / 3.**
**Full suite 2274 / 2268 / 0 / 6 in 22.3 minutes — zero reds, not even an environmental one**, on a
freshly erased `eraser-mutex-test`. No branches in flight, one worktree, clean tree. **The iPad has
`a85a316` Release**, so the owner is holding the new keyframe workflow and both bugs they reported
against it are fixed on the device.

**1. The keyframe UI is the owner's design now, not §2.1's. Four of their six asks are merged and the
   graph editor is the whole of what is left.**
   Animate mode is deleted — the flag, the bar, the UIKit button host, the hold recognizer, the
   hoisted constant and every doc comment that argued for them. The workflow is: place a keyframe from
   the cel menu, move sliders, place another. §2.26 to §2.28 record it and mark §2.1, §2.23 and §2.24
   superseded with their reasoning intact, which is what stops a later session restoring them.

   **The invariant that must not be undone is §2.28's: a keyframe is any frame the target marks
   explicitly *or* any frame a channel holds a key on.** Both of the owner's device-reported bugs were
   one divergence — the timeline drew the union while the model knew only the marks, so a diamond you
   could see was not a keyframe the menu or the seeding logic could find. One accessor computes it now
   and `TimelineKeyMarkers`' second copy is deleted. **Adding a mark on every key write is the wrong
   fix and was rejected**: it stores the same fact twice and drifts again the first time a writer
   forgets, which is the defect, not the cure.

**2. The graph editor is stages D2 to D4 and KEYFRAMES §11 is the design.** D1 — row geometry as a
   lookup over per-row heights — is merged and behaviour-neutral (`4329e3d`).
   **§11.3's three silent-failure modes are the brief for D2**, and one of them is newly sharpened:
   `TimelineLayoutKey` still carries a **scalar** `rowHeight`, which is sufficient *only* because row
   heights are a pure function of `(rows, rowHeight)` and `rows` is already in the key. D2 opens a band
   per layer, so it is the first stage to derive a height from something else — put that input in the
   key or the row draws once at its old height and never moves again.
   Also inherited from D1 and not a defect to chase: **the name column and the track have always been
   2 pt out of vertical register** (track row 0 at `rulerHeight + 4`, name column at `+ 6`, same pitch
   and same total). Carried through exactly. A band drawn across both columns must know.

**3. One offer is outstanding and the owner has not answered it.** Asked when Move, the transformation
   layer and Distort arrive, they were given the written order and this lever: **Distort needs only the
   transform channel (stage 5), not stages 6, 7 or 8**, so pulling it to sit directly after that — which
   is what §2.13 intended anyway — puts it several weeks earlier than §8's table implies. Ask before
   assuming the table.

**4. `LayerPanelUITests` is still 515 s across 19 tests and splitting it is still the cheapest big
   win.** The table was re-taken this pass and holds: 3,542 class-seconds over four clones is ~15 min of
   ideal work against a 22.3 min run, and that gap is one indivisible class. It lives in
   `LayerUITests.swift`, which already holds three. **Verify a split by test count from the xcresult,
   before and after** — a test that stops running still prints green.

**5. TODO (10) Oklab is still untouched and its first move is still not to build anything.** Stage A is
   **linear-light compositing through a 256-entry LUT**, not Oklab. **Render the A/B and show it before
   building** — this owner reverses on a picture what they accept on a number, and it happened again.

**Do not re-litigate**: KEYFRAMES §2's rulings, now **twenty-eight**; LASSO_MOVE §5's twenty-five;
CANVAS_RESIZE §5 and §6; EFFECT_BACKDROP §5 and §2.1; (10)'s three-stage recommendation.

**The process rules that earned their keep this pass.** **Invite every worker to refute its brief** —
four did, and every catch changed the shipped code, including two defects that were mine. **Remove
cleanly**: the owner asked that a deleted feature leave no vestigial parameter, no half-live control and
no "this used to be" comment, with history going to the spec docs and `git log` instead. And **do not
re-measure a baseline another session already took on the same commit** — at load this suite returns
wrong answers rather than slow ones.
```

---

## State

`main` = `4b86966` plus the close-out commits above it. **Fast tier 2153 total / 2150 passed / 0 failed
/ 3 skipped**, up from 2098 at the start of the pass.

**FULL SUITE: 2274 total / 2268 passed / 0 failed / 6 skipped, in 22.3 minutes**, parallel, on a freshly
erased `eraser-mutex-test`. Up from **2221 / 2214 / 1 / 6** at `0717ed6`, and **the first full run in
several passes with no red at all** — the environmental `LayerPanelUITests` failure that has recurred
did not this time.

The class table was **re-taken and holds**: `LayerPanelUITests` 515 s / 19 tests, `SelectionAndMove`
327 / 10, `SandwichCompositing` 297 / 10, `BlendModesAndCompositor` 222 / 8, `CuttingModes` 177 / 4,
`PerfBaseline` 173 / 53, and two entries the previous table did not carry — `EraserAndPersistence`
171 / 7 and `TimelineGesture` 144 / 7. 3,542 class-seconds total, so four clones hold ~15 min of ideal
work and the extra seven minutes is still one indivisible class.

No branches. One worktree. Clean tree.

## What landed

Six owner asks arrived in one message plus a follow-up; four are merged and two are the graph editor.

- **`de4e43e`** — ask 2. A grade's keyframes die with the grade. The rule is **parameter ids**, because
  both case-shaped tests in this tree are wrong for it: `kindCode` merges `.levels` with `.curves` at 0
  and `.blur` with `.sharpen` at 7, and `EffectCatalog.isCurrent` splits one `.blur` into Gaussian and
  Directional. It also found `duplicateLayer` had been silently dropping `effectTracks`.
- **`167e44a`** — ask 3's model. Bare keyframe marks, held baselines, the five-arm slider rule,
  `addKeyframe` / `removeKeyframe` / `clearKeyframes`, and Animate mode deleted outright.
- **`4057e9d`** — ask 1. Add / Remove / Clear Keyframes in the cel menu, and **a bare keyframe draws at
  last** — hollow against the filled diamond of one carrying values.
- **`4329e3d`** — the graph editor's D1. Row geometry is a lookup over per-row heights.
- **`a85a316`** — both device-reported bugs, one root cause.
- Docs: `2d9f16e` the six asks verbatim, `68fb98f` KEYFRAMES §11, `fcc3b1f` the y-axis ruling,
  `fc96b18` TODO (23), `4b86966` a BUGS entry.

## What this pass learned that outlives it

- **A thing that is drawn and a thing that is stored must be the same thing.** The timeline drew the
  union of marks and curve keys; the model knew only marks. Two owner-visible bugs from one divergence,
  and the cure was to make the *accessor* the union rather than to write marks harder — the second
  option preserves the duplication that caused it.
- **Both obvious "did the effect change" tests in this tree are wrong, in opposite directions.** One
  merges cases, the other splits one. The exact question is *which parameter ids does the new grade
  name*, and it needs no case comparison at all.
- **A guarantee can hold at the instant you check it and not after.** The cel menu's frame was proved
  equal to the playhead when the menu opened — and **playback keeps running behind a `.popover`**, so
  during playback the two walk apart. The menu carries the frame it was opened at now.
- **`pgrep`-style contention checks are not the only shared resource.** A worker was told to reuse a
  baseline another session measured on the same commit rather than re-run it, because a fast-tier run
  under two live workers is exactly the load CLAUDE.md says returns wrong answers.
- **The merge-from-the-main-worktree trap has now fired four times**, this pass on a docs branch: a bare
  `git merge --ff-only` after a `cd` merges the branch into itself, says "Already up to date", and
  pushes nothing.
- **`duplicateLayer` builds its copy from an explicit argument list**, and that list has now missed a
  newly added field three times. Three fields ride it as of this pass, with one test pinning all three.

## Still open, unchanged

TODO (10) Oklab. TODO (23), the owner's not-priority ask that selection membership move from Move to
Select so Recolour can use it. `ARCHITECTURE_REVIEW.md` findings 2-4. KEYFRAMES §9's four open
questions, and §11.6's two (the band's height, and the collapsed folder that hides its children's key
markers). BUGS.md carries the interactive-gesture CPU composites, Fill/Clear on a derived in-between,
the raster-storage bound, the unclamped zoom, `TextFrame.homography` decoding with no validity check,
PERFORMANCE item 14, the narrowed mask-cache structural gap, and the new folder-row accessibility gap.

Two behaviour questions are owed: save semantics when a project loaded with something unreadable, and
which faces belong in the font picker's favourites strip.

**Found and deliberately not fixed this pass**: colour, toggle and picker rows still write a whole
resolved `Effect`; stepped and compound parameters still cannot be keyed; the Render Resolution knob
still does not reach the expensive half of a derived frame; and `setEffectParameterTrack`'s two
overloads write a whole curve with no mark, which the union makes harmless today and which the graph
editor will be the first real caller of.
