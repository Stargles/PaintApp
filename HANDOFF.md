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

**No branches, no worktrees, stash empty, no simulator debris.**

**Fast tier: 3547 total / 3544 passed / 0 failed / 3 skipped**, Debug *and* Release, reconciled at
each step (3533 → 3540 → 3544, and each increment is exactly the tests added).

**No full suite has run for two passes, and the last two both changed the render path.** The onion
skin moved off the main thread and `CanvasView.updateUIView` was restructured around it; the fast
tier selects logic suites by filename and **runs no XCUITest**, so nothing in either pass is evidence
about anything on screen. `RecordingUITests` and any onion-skin UI test are unverified. **A full run
is owed before the next merge.**

**The owner has confirmed on their own iPad, on `Test1`, that playback now holds 24 fps.**

## The thing to read before measuring anything

**Three consecutive passes measured large wins on a Mac and delivered nothing the owner could feel**
— the undo lock (25.6 → 1.7 ms), the thumbnail render (34.1 → 1.08 ms), and playback engagement
(115.9 → 9.8 ms a flip). All three numbers were true. **All three benches call an engine function and
none of them runs a SwiftUI pass**, and the cost was inside `CanvasView.updateUIView`, which none of
them ever entered.

So the correction is not "the simulator is faster" — that is calibrated at ~1.3x. It is that **a
bench measuring a component cannot find a cost in the composition.** What broke the deadlock was a
runloop-observer pair (`PlaybackTrace`) measuring main-thread-busy whether or not the code under it
is instrumented, on the device, with Core Animation's commit bracketed rather than inferred — which
also refuted the leading hypothesis for free (`caCommit` is **0.00 ms** across 349 commits, so the
64 MB texture upload was never the cost).

**Measure on the iPad.** `PlaybackProbe` + `PlaybackTrace` drive the real editor from launch
arguments with no test runner attached, and write a JSON report into the container to be pulled back.
Device `E3B83820-DF74-5042-B52B-0D5BA17E4877`; CLAUDE.md's "Deploy to iPad" section has the rest.

## What shipped this pass

**The onion skin did every pixel of its work synchronously inside `updateUIView`** — on by default,
not persisted, so every launch had it, and **nobody had ever timed it**. It was in none of the
candidate lists three separate briefs offered. MEASURED on the device: **52.7 ms a frame flip at
4096²** against a 41.7 ms budget. The fix is one rule applied to the one path exempt from it — RENDER
§2.2 says the main thread never composites, this app has four renderers and three had queues. Deleted
with it: `onionSkinClipInputs`, the `onionSkinClip` memo, `onionSkinKey`, and the synchronous
composite/clip/ink calls.

**`frameRingByteBudget` was a fixed 96 MiB, which is smaller than two 4096² frames** — and a ring
holding one frame of a two-frame loop serves it *not at all*: every tick missed, decoded 67 MB of LZ4
on the display thread, and evicted the frame `fillRingAhead` had just placed. It is a function of the
frame now, floored at 96 MiB and ceilinged at `CompositorBudget.textureBudgetBytes`, and **switched
off above that ceiling**, because holding one frame is strictly worse than holding none.

MEASURED on the owner's iPad, 4096², 3 layers, 2 frames: **16.0 → 24.0 fps**; `updateUIView` per flip
**76.6 → 1.1 ms**; on-main decode **22.8 → 0.0 ms**; ring **0/83 → 255/0**. 2048² with **8 layers and
6 frames** also holds 24.0 fps, so the layer term is gone. PERFORMANCE.md §16 is the measurement.

**The disk-bandwidth wall the owner offered was declined, because it is the wrong name.** The file
read inside `loadDecoded` is 0.1 ms; the cost is the **LZ4 decode**, CPU and proportional to pixels.
The honest boundary is a **product — canvas area × distinct frames in the loop** — about two 4096²
frames or six 2048² ones on a 3 GB device.

## Start here

**(57), then (56) — and (56) is where the owner's attention is.**

**(56) is half done and the half that is left is the one the owner will notice.** Per-edit
main-thread busy is **20-121 ms** at 4096² after §16, down from 64-214, and their bar is *"no
noticeable lag... no matter how many strokes or cels or layers"*. The two stalls per edit are
identified — one at 401-402 ms is the debounced thumbnail and the SwiftUI pass it raises, the other
is the operation's own — and §16 removed the onion skin from both. **What those two passes still do
is the next measurement, and it must be taken on the device.**

**The disappearing strokes are untouched and are the owner's oldest live complaint.** BUGS.md's
*"Starting a stroke before the last one has rendered leaves the last one off screen"* is the
mechanism and its own text says the window *"scales with canvas area"*. Closing it needs a second
overlay for un-landed ink, or a synchronous composite at pen-up — and the second reverses RENDER.md
§2.13 deliberately, so **it is the owner's trade rather than a session's.**

After that, in queue order: **(36)**'s one remaining box, **(41)**, then **(42)**.

## Waiting on the owner

- **Should the onion skin draw during playback at all?** It costs the main thread nothing now but
  still ~49-111 ms of a background core per flip, and it draws ghosts over the animation while it
  plays. One guard removes it; it changes what they see.
- **6000² is killed by jetsam before it can play** — one layer, two frames, and **reproduced on
  `origin/main` with only the harness added, so it is pre-existing rather than a regression.** In
  BUGS.md. The lever is a memory decision on a 3 GB iPad, not a bug to fix in isolation.
- **The disappearing strokes' fix** — see above; it reverses a RENDER.md ruling either way.
- **(21) stage 7's other half.** §5 asks for one mechanism on two surfaces and only the slider is
  built; the Move box needs rulings on resampling and tolerance for a **quad**, which `ValueRecording`
  cannot express. Stage 10 sits on a whole stage 7.
- **(21) animation-group membership** — retagging, which changes the meaning of every key on both
  groups' tracks. The refusal half shipped 2026-09-03 (§2.29).
- **(22)** and **(10)** deprioritised; **(37)**'s importer dropped.
- **BUGS.md's five remaining `.popover`s** have the timeline's swallow-every-drag defect. Three are
  colour pickers whose chrome would visibly change — the owner's call.
- **The pencil half of (47)** cannot be driven by any test here: XCUITest cannot synthesise a pencil.
  **Nor can it reach the Move-box bake fixed on 2026-09-08** — `MoveBoxCommitUITests` records the five
  runs that established it so nobody spends them again.
