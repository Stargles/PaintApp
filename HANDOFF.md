# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks **in queue order — the top of the list is what to do next**;
[BUGS.md](BUGS.md) is what we find.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**No branches, no worktrees, stash empty, no simulator debris.** Session 41 closed at `921e1ce`,
**68 commits** past session 40's `aff11df`, everything merged and pushed.

**Fast tier at `921e1ce`: 3971 total / 3968 passed / 0 failed / 3 skipped**, Debug and Release
(3761 at the session's start), reconciled against a static `func test` count at every one of the
seventeen merges. The 3-count gap between static and xcresult is three `private static func
testBrush()` fixture helpers — constant, and every worker re-derived it.

**The full UI suite has NOT been run since `d2205d5` (session 40).** Every worker ran the UI classes it
touched in isolation — about forty class-runs, all green — but no run has tried the ~20 new UI classes
against each other under four parallel clones, and CLAUDE.md's class table predates all of them.
**Run the full suite on a freshly created device before anything else**, take the per-class table
immediately after (the bundle gets evicted), and triage by the rule session 40 taught: **a regression
fails the same tests twice.** Two classes to expect near the top: `TransformLayerModesUITests` (~350 s
across four tests, measured in isolation) and `TransformLayerSpanUITests`.

**The owner's iPad has `921e1ce` on it** (Release, installed 2026-09-12). They tried the 2026-09-10
build and found nothing wrong; this one carries everything below and has not been reported on.

## What shipped this pass

**Five items closed whole and deleted: (60), (61), (62), (41), (42), plus (45).**

- **(60)** — six effect changes: Recolour with its under-the-effect eyedropper (Oklab tolerance,
  softness, ordered entries claiming what earlier entries left unclaimed, shading preserved), Bloom
  colour, Sobel gain, Computer Screen (six knobs, four presets, strip-apron aware), Dither/Halftone
  as menu entries over the existing ordered screen, Hue Colorize as a mode of HSV Shift. `Effect.Kind`
  is **16 cases** (13 → `recolor`, `crtScreen`, `duplicateOffset`); Dither, Halftone and Hue Colorize
  are menu entries over existing cases, the Blur precedent. Recount before quoting.
- **(61)** — the transform layer is its own `LayerKind` with a migration, and all five modes shipped
  from a spec written and ruled the same morning: Parallax, Rotate, Shake, Repeat (a per-entry frame
  carry in `renderNodes`; the frame store hits for free), and Duplicate Offset as a value-layer effect
  with the Move box as its writer. [TRANSFORM_LAYER.md](TRANSFORM_LAYER.md) §2 holds the seventeen
  rulings; **the bar means "only here" for every non-drawing layer** — an effect layer's grade now stops
  at its bar too, which changes existing documents whose effect bar is shorter than the scene (the owner
  accepted that knowingly).
- **(62)** — keys past a shortened block are cropped, one undo step, a banner names them. Built, then
  **adversarially reviewed** (four real findings: a third undo door leaked the banner, a second split
  erased the first's report, two live key writers minted keys outside the span on a fresh document —
  which refuted the invariant the builder had deleted a crop on — and a wrong BUGS.md filing). The
  owner then ruled **twice against what was built**: the crop first inserts a key at the new last frame
  so the remaining frames keep their motion; and a transform layer's own keys are cropped to its bar
  rather than kept inert (*"I explicitly wanted keyframes clamped to inside the cels … I don't care
  about data loss"*). Both shipped.
- **(41)** — the `autoSize` text box is bounded by measured glyph ink (undo of a title at 2,000 strokes
  **1,082 → 128 ms** MEASURED, Release), and a rewrite in place gets its hook at the mutation site
  (undo of a recolour of 50 at 2,000: **1,093 → 303 ms**; the hook costs ~0.2–0.5 ms a tick). PERFORMANCE
  §11.11e/f.
- **(42)** — colour, size and opacity at selection scope, live, one undo step per drag; the picker opens
  on the selection's own colour; a rasterize the canvas outran is now *shown* as an intermediate frame
  rather than thrown away (§11.11g — the brief's coalescing premise was backwards, and the worker said
  so and did the opposite).
- **(45)** — the audit re-run: ~230 citations checked, ~30 fixed across seven specs; most rot traced to
  one deletion (`d8d7ba8`, the whole-layer vector transform) that LAYER_TRANSFORM.md, LASSO_MOVE.md and
  PERFORMANCE.md still cited as live. Those three are annotated, not rewritten — **their bodies still
  describe that mechanism as history**, which is where a future reader will be confused first.
- **(21)** — two boxes reconciled as already shipped (stage 7's Move-box surface, the folder keyframe
  entry point); two remain.
- **Small defects**: `duplicateLayer` no longer drops animation/transform/in-betweens; three colour
  pickers' stomped identifiers; a hidden transform layer poses nothing; every artist-facing frame
  number counts from 1; `RecolorUITests` scrolls to its entry (and the scroll helper is shared).

**What the cold-start UI tests found that nothing else did** — five defects, each in a green fast
tier: the bake key ignored `Bloom.color`/`Sobel.gain` (a slider that painted nothing); an
`.accessibilityIdentifier` on a container stomping every child; the baker's `StructuralStamp` never
seeing container poses (every rotated frame stale on the display path — pre-existing); a multi-tick
bar drag cropping a different key every tick; `press(forDuration:thenDragTo:)` returning ~0.6 s after
the lift, which let a deferred implementation pass a "live" assertion. **The rule is CLAUDE.md's and
it held every time: assert what is drawn.**

**Process**: the session ran two lanes (one Opus, one Sonnet) of one agent per item, each carrying
survey → build → mutate → drive → merge, ~450–620 K tokens each; a fresh reviewer only for (62). Two
workers ended their turn to "wait for a background run" and could not be resumed (the brief now
forbids it); two more were cut off by a usage limit and **were** resumed via `SendMessage` with their
context intact — worktrees survive either way, and every worker had committed as it went.

## Start here

1. **Full suite on a fresh device**, per State. Nothing else until the count is read.
2. **Ask the owner what they found on the iPad** (`921e1ce`, installed 2026-09-12).
3. Then, in queue order: **(21)**'s two boxes — the folder graph band (`graphBandExpansion` keyed by
   `layerIndex` → `KeyframeTarget`, KEYFRAMES §11.7) and stage 6, bake to cels (KEYFRAMES §6 is the
   spec: follow `bakePreciseStrokes`, mint fresh ids, bake at the channel's step, disclose the
   permanent save cost with a MEASURED number; a bake under a Repeat layer reads the source frame).
   Then **(63)** Glare and Colour Wheels (low priority by the owner's word), (22), (10), (37).

## Waiting on the owner

- **What they found on the device.** Nothing is blocked on it.
- **Questions that took a default this pass** — each is reversible and recorded where the behaviour
  lives; ask when one bites rather than all at once:
  - Selection editing: dragging Size over lines of several widths sets them all to one width — or
    scale them together? Same for Opacity. Show the edit band dimmed before a loop is drawn?
  - Duplicate Offset: default is a white rim 8 px up-right (a black shadow instead?); the box is the
    whole canvas (sit on the drawing?); the panel closes on the first canvas touch after Adjust Box;
    all 25 blend modes offered.
  - Repeat: the brush lands on the source drawing, but Move, lasso and text still see an empty frame
    there, silently (TRANSFORM_LAYER §5.5 lists them).
  - Shake speed is 1–12 frames per jolt; a folder in Rotate/Shake counts from the document's first
    frame (no bar).
  - Recolour's soft edge blends into the *next* entry rather than the original ink; 64 entries max;
    the paper can be recoloured if a picked colour is close to it (kept, by the owner).
  - Computer Screen: bent corners are see-through (kept); line spacing in the picture's own pixels;
    the Blend Mode menu is four pages long with the effects at the end.
- **(22)** and **(10)** deprioritised; **(37)**'s importer dropped.
- **BUGS.md** carries the stepped-split timing change, the simulator-only keyboard band, and the five
  `.popover`s — none ruled.
- **XCUITest cannot synthesise a Pencil**; the owner has granted device build and deploy, so the pen
  halves are checkable on the iPad rather than unprovable.
