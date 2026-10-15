# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. Write it for any agent: the next session may not be Claude Code. -->

**Start here:** read [AGENTS.md](AGENTS.md) (the owner, the standing rules, the bar for done), then this
file, then [CLAUDE.md](CLAUDE.md) (build, test, merge, deploy), then the specification for whatever you
pick up. [TODO.md](TODO.md) is the owner's asks **in queue order — the top is next**; [BUGS.md](BUGS.md)
is what we find.

## State (session 49 parked at the owner’s request, 2026-10-15)

**Parked after the requested current UI batch.** App/test checkpoint `9dfd96b` is committed in
`~/PaintWork/PaintApp-s49-integration` (`tmp/s49-integration`). No active jobs or faults remain.
Resume only when the owner asks; performance still waits for their Mac-idle notice.

Verify `git fetch origin`, `git worktree list` and every `tmp/*` branch before resuming. Worktrees
live under `~/PaintWork`, outside Desktop. Never harvest a dirty worker tree: deliberate faults may
be running. The owner permits useful delegation but prioritises usage conservation and quality over
speed. Two native slots are handed over explicitly; simlock is not a fair queue.

**App source remains `840d68a`; no Liquify is merged.** Session 49 shipped (190) first-fill transfer
`e6b7d81`, (177) strict stream recovery `4d396c6`, (35) masks `b625710`, (189) onion-panel updates
`8616532`, and Fog Glow preview-radius equivalence through `840d68a`. Initial combined Debug/Release
fast tiers each passed 5124 total/5120 passed/four skipped; shared recovery UI 21/21 and Glare 2/2.
Native iPad 9 pictures were inspected. Evidence: `~/PaintWork/s49-integration-logs/` and task archives.

**Regression corrections are verified.** Full main run `e3b487c` (same app source)
ran **5694 total, 5624 passed, 57 skipped, 13 failed**, four clones, 5907 seconds. Census reconciles;
archive `~/PaintWork/s49-final-validation/full-main/`. Ten of twelve UI failures passed in the fresh
serial batch; Guide-above passed subsequently alone. Interpolation repeated. Its actual pre-Commit
package proved the local stroke was already absent: synthetic slider time 0.497413 was below its
0.498071 visibility threshold. The corrected test commits at 0.75, requires visible local ink first,
and compares the same black-ink columns afterward using one screenshot per sweep. It catches both
deliberate faults (invisible precondition and missing committed ink). Restored touched UI passed 3/3
(InterpolationWorkflow 1, Glare 2); the opt-in timing test skipped. Root inspected before/after images.
The pad timing failure was an unconditional duplicate gate under parallel load; four warm opt-in
runs were below the unchanged stricter total-pad bound. That remains the only timing assertion.
The unused RGB extension was deleted. No app code changed for this triage.

**Final regression gates at `f336001`: Debug and Release each 5124 total/5120 passed/four skipped,
zero failures**, matching 251 selected classes and full source census 5694. Rebase onto `0a233a0`
changed no app/test/project source. Both UI lints pass. Evidence:
`~/PaintWork/s49-final-validation/triage/regression-gates/` and `regression-ui-2/`.
An intermittent Blend Mode menu failure occurred twice in the Fog Glow drive; diagnostic first taps
and the complete restored run subsequently passed. Cause remains unconfirmed in BUGS; no retry,
delay or menu workaround was added. No second full suite was run just for these test corrections.

**The iPad has main17b438c Release, recovered October22.** App source840d68a remains unchanged,
without Liquify. The expired profile was renewed, but an incremental build copied it without CodeSign;
actual launch failed. The external renewal script now cleans the same DerivedData tree, verifies the
signature and requires five days of profile life. A proper clean rebuild verifies, installed without
removing app data, and the owner confirmed it opens. Profile expires2026-10-30T00:18:54Z (October29
Toronto). Nine isolated deployment tests and four deliberate faults passed; no new Swift source.
Evidence: docs/bug-evidence/auto-resign-2026-10-22.md and ~/PaintWork/s50-recovery/.

**Liquify resume source is tmp/s49-integration**, outside Desktop at
~/PaintWork/PaintApp-s49-integration. Its handoff supersedes the older in-flight detail below; source
9dfd96b plus producer ownership cleanup is unmerged. October22 isolated Debug linked checks repeated
the15-second predicate timeout; exact815 readable probes change only after the deadline. Next useful
gate is the unchanged current Release workflow and quiet producer cost. The owner confirmed Mac idle.
Keep one-shot repairs until the owner confirms real scenes; first run the final repair
signature so preserved preupdate snapshots are also converted.

**(178) Liquify: active ownership and evidence**

Main remains `17b438c`; Liquify is unmerged. Root `tmp/s49-integration` has material `72f686f`,
raster `f056af7`, sampler `effb239`, exact inverse batching, and root caller fixes `f66bd95`.
Raster's final delta is integrated; do not cherry-pick its older history. Never harvest a dirty
worker/root tree. All worker tasks are complete and faults restored; root source is clean.
`9dfd96b` adds the explicit raster-layer UI setup and a landscape controls capture attempt.

- **Required-picture refusal.** The shared optional contract replaces the old forced transparent
  fallback through actual render/copy/merge/save/thumbnail/onion consumers. Root `f66bd95` also
  publishes document coverage only with an accepted picture, captures it for async landing, resets
  coverage on canvas identity changes, and admits a Move latch only with both isolated piece and
  hole. A failed initial lift rolls back; a failed relatch preserves earlier nudges and their Undo
  steps through existing settlement. Eraser-only isolated images were already valid transparent
  images; the contrary old comment is deleted. No new renderer, result enum or cache.
- **Caller proof — complete.** Focused native baseline and restored gates each passed4/4 at
  `f66bd95`. FaultA failed2/2 with two diagnostics; faultB failed2/2 with16. All eight source files
  restored exactly; slot and simulator returned to root. Evidence:
  `~/PaintWork/s49-liquify-logs/combined/final/caller-refusal/`. View installation/coverage and canvas
  identity are source-reviewed: the actual view is absent from the headless target; no compiled
  native-view assertion is claimed. Existing scheduling, actual rendering and settlement are tested.
- **Raster — complete at clean `f056af7`, source `75f75b7`.** Final selected115 ran114 passed/one
  invalid fixture (one-reference interpolation), zero skips; all33 raster logic and five UI passed.
  The repaired test uses two actual sources, requires visible ink and keeps the exact identity
  assertion. Restored3 passed3/3; faults3 caught22 diagnostics and a separate empty-source fault
  caught the visible-ink assertion; final restored3 passed. Earlier restored109 and adapter faults
  remain valid. Index: `raster/final-raster-handoff.md` and `sampler-adapter-proof.md` under the Liquify
  logs. Both owned simulators deleted, slot1 free; 0.91GiB of rebuildable caches removed, evidence kept.
- **Final UI checkpoint —7/8 passed,0 skips at9dfd96b.** The corrected cold test explicitly creates
  raster backing; all five raster methods pass, plus vector Push and saved controls. The linked test
  timed out at line97 and stopped before later reopen/source-following steps. Root viewed before/after:
  deformation is visible in the later still. Cause remains unclassified; isolate it and inspect timing
  before changing product code or thresholds. Earlier linked Release1/1 is a different source/run.
  The controls landscape image caught system rotation mid-flight and is not settled layout evidence.
  Native iPad9 controls capture remains. The earlier three native9 images were inspected; mixed backing
  and eraser are valid raster evidence, while the old cold-reopen image was on the default vector tier.
  Evidence/counts/saved171-file Documents copy: `combined/final/liquify-ui-final-1-review.md`.
- **Exact batching.** Existing PixelOps fan-out shares an immutable field across disjoint point/row
  batches; exact scalar arithmetic, global pixel centres, failure and counts are retained. All
  temporary arrays are budgeted, joined allocation exact-sized. Debug34/34 and three faults132
  intended diagnostics are qualified. Restored Release logic2/2 and opted-in18-fixture method1/1
  pass, zero skips in the latter. Long Debug was cancelled after five actual windows matched every
  reference byte; patterned batching202.6s versus scalar90.9s is a real Debug slowdown. Acceptance
  waits for quiet optimized actual-producer cost. External matching C++ speed is not native/device
  qualification. Evidence: `combined/batches/EVIDENCE.md` and its logs.
- **Material and sampler earlier gates.** Material55/55 at72f686f; visible crop reduced output points
  from262144 to17248/38577 at scales1/1.5 without changing bytes, six fault diagnostics. Sampler effb239
  native Debug20/20, quiet Release21/21, final allocation cleanup production-source Mac11/11. One
  bounded Lanczos kernel, no added cache/CG fallback; PERFORMANCE§36 records memory and warm/cold
  limits. Simulator first window523ms included initial Metal access; physical cost remains open.
- **Storage/model complete.** 52eda39 storage115/115, seven fault groups/nine failed executions/46
  diagnostics, restored18/18; genuine840d68a prior writer with nine unchanged provenance hashes.
  afef15c model five fault groups/14 failed executions across13 methods, restored13/13. Integrated;
  do not redo. Keep one-shot repair until owner confirms. A new executable signature converts older
  preupdate snapshots; the current signature's own backup intentionally retains the prior format.

**Remaining qualification:** parked. No active native/compiler jobs or agents; root's owned
`80BE77F5-9118-4CDD-854D-07C3E9A9009B` simulator was already shut down after the UI batch and is now
deleted, with its Documents copied and171 file hashes verified. Create a fresh owned simulator on
resumption; integration DerivedData remains available. The owner is using the Mac and will notify when
finished; performance is deferred. Final census: **fast5282/256 classes, full5864**. Both UI lints pass,
PBX IDs unique. Final fast/full scripts are prepared but not run. No final Release build after optional
API/caller changes, quiet batching measurement, owner-sized controls capture or new physical run.
Root UI compile attempts1–4 ran zero tests; the final8-method batch compiled and ran as recorded above.

**Physical preparation, not execution:** external `combined/final/device-drive.patch` and exact-byte
apply/restore helper preserve user preferences, brush/palette libraries and packages. Ordinary helpers
reset physical preferences/libraries, so never run them unchanged on the iPad. Five methods
cover playback/grey pan/Move/graph and an explicit raster layer under a transform with actual held-pixel checks; the patch has not compiled or run.
A separate temporary actual-CelContentPicture benchmark is prepared for native process-cold/warm
cost and exact pixels, not app gesture latency. The seeded backing UI is simulator-only and prewarms
its reference; the existing explicit raster app flow is prepared for physical first-presentation
correctness (`device-raster-app-first-use.md`). No new production timing hook. Get fresh saved/unlocked readiness only when ready for
device work; the prior readiness was consumed by179 and the iPad is released to ordinary use.

## What is next

1. On owner resumption, isolate the linked UI predicate failure and capture settled Liquify controls
   at native iPad9 size. Then build Release, qualify optimized batching cost once the Mac is quiet,
   run final fast Debug/Release and full suite, and obtain fresh device readiness for the five safe
   UI drives plus native cold/warm sampler cost. Keep screenshots and actual scene packages. No
   threshold change or timing claim is justified by the contended UI failure alone. Remove (178)
   whole only in its fully qualified merge; no Liquify is currently on main or the iPad.
2. **(179) is complete:** six physical probes on `f813346`, every process exited 0, no failed bakes or
   trace overflow. Effect preview 99/100 at 4096² and 100/100 at 2048×1024; opacity 100/100 both. Every
   drag had zero editor passes (two whole-trace passes). Shape/fill picture counts are not instrumented.
   PERFORMANCE §30.7 and `~/PaintWork/s49-device-probes/README-after-20261015.md` preserve exact scope,
   arguments, raw reports and memory limits. Removed the completed TODO item whole in this merge.
3. (27) laptop verification is owner-deferred; (22)/(10) deprioritised; (37) dropped; Later features
   await a design discussion. Do not research those while the owner is unavailable.

## What shipped this session (48)

`f368504..` (~70 merges); causes are in the commit messages. The decisions most likely to be tripped over:

- **(179) One seam for every live re-update** — `LatestWins` (newest request wins, one job in flight, the
  landing on main before the next mint; proven by an interleaving rig in `LatestWinsLogicTests`), one held
  slot `CanvasManager.liveEdit`, and lane F: a whole-frame composite from the held value via
  `makeFrameRecipe(holding:)` into `WindowSurfaceView`'s surface pair, held until the bake lands. Effect
  parameters, the whole-effect editors, the Adjust Box, effect-channel graph drags, layer/folder Opacity,
  value colour, Rotate/Shake/Parallax, the smart-shape and text previews, the interpolation Timing/guide
  drags, graph-band channel drags and the fill's renders all write once at the lift; the brush colour
  has its own publisher (`BrushColorState`). **Above ~4 MP a drag preview is half detail**
  (`DragPreviewDetail`; the owner's drag-only exception beside RENDER.md §2.12). PERFORMANCE §30–§34:
  a 4096² fill-slider drag handed Core Animation 102 canvas-sized images before and 2 after.
- **(183) A window surface is not drawn while the render server still shows it**
  (`WindowSurfaceView.present` waits on `IOSurface.isInUse`); the colour picker no longer rebuilds per
  tick (`PickerColor`, PERFORMANCE §31). The owner confirmed the selection-colour flicker is fixed;
  the separate first-fill flash when starting another fill is (190).
- **(176) Where options are saved** — ruled row by row (`~/PaintWork/design/s48-176-ruling.md`): tools,
  brush/eraser size-opacity-colour, fill, text, interpolate switches, picker tab, recent colours,
  selected palette and active view are **per scene** (`SceneTools` in `EditorStateManifest`, decoded
  strictly); the brush library, preset edits, imported tips and Palettes are **app-wide** through one
  store, `AppSettings`; Select/Move switches reset. `ToolProfiles[StrokeTool]` replaced the eraser's
  parallel properties. `LegacyToolSettingsRepair` (sharing `LibraryRepair` with `LegacyPoseTrackRepair`)
  is the throwaway. (186): the fill's sideways drag moves Gap Closing only, right decreases.
- **Select** (182, 184, 185, 187, 188): the Freehand lasso stays open — taps are corners, a stroke joins
  with a straight edge, a tap on the start node closes (`OpenLasso`); a drawn region survives layer and
  frame switches (`Selection` carries no cel; tapped sets are `SelectedObjects`); making, adding,
  subtracting, tap selections and Deselect are all undo steps (`replaceSelection(with:label:)`).
  LASSO_MOVE §5.28–33.
- **(180)** the Padding On Top cover is a 50% veil (`PaddingCoverView.veil`; `marginGrey` stays opaque).
  **(181)** the vector eraser defaults to Cut (`VectorEraserMode.default`); Cut cuts strokes only (ruled).
- **Stranded recognisers**: analysed (`~/PaintWork/design/s48-stranded-analysis.md`, BUGS.md) — a third
  touch joining a pair strands `canvas.pan` in 8 of 9 cases; the owner ruled **diagnostics first**
  (`7bbd90c`: per-touch `moves`, `uid`, recognisers' `touches` per sweep, and "Canvas freezes caught: N"
  in Settings). The fix waits for one or two more flights.
- **AGENTS.md** is the tool-neutral start-here; the owner's working agreements live there now.

## Waiting on the owner

**Owner confirmations, 2026-10-14:** (176)'s Subtract, Paint Outside Selection, Keep Stroke Width and
Keep Full Precision continue resetting whenever a scene opens. (183)'s selection recolour no longer
flickers on the iPad; the different two-fill flash is now (190). (178) includes linked in-between frames.

**Liquify raster scope ruled:** *"Move all raster pixels; leave editable objects alone."* This includes
flattened pictures/text that old raster layers can no longer distinguish from paint. **Vector selection
edge is also ruled:** *"B — Keep outside ink fixed."* Keep every exterior pixel fixed through spatial
material deformation while retaining editable strokes. The transformed-raster appearance choice C above is accepted subject to compact code and measured cost; the Liquify scope itself is settled.

**After the October 15 install:**
Once this build has repaired his scenes and they look right: retire the one-shot repairs.
   First run a final repair build with a new signature so the preceding build's preserved preupdate
   snapshots are also converted; verify all library packages decode before removing repair code.
   This keeps old snapshots usable without a permanent legacy decoder. Delete `LegacyToolSettingsRepair`
   (and `LegacyPoseTrackRepair`, if the keyed scene from session 47 was restored and animates — still
   unconfirmed: Gallery → scene "1" → Versions… → Oct 9 "Before app update" → Restore).

**To check on the iPad** (`f813346`): colour-picker drags, the polygon lasso, a selection kept across
layers and frames, the padding veil, a
long effect-slider drag; and still from session 47: the graph-node drag, the Move box, the gap slider,
idle with a stream connected. Send the next `flight-…` file after a "Caught a canvas freeze" badge.

**Ruled to wait / carried**: (27) stage 5 (the owner at the laptop); (22) and (10) deprioritised, (37) dropped; the
"Later" features need a design conversation first.

## Engineering notes

- **The UI suite runs in portrait on the 13" simulator; the owner works in landscape on an iPad 9.**
  ~20 UI tests are red on an iPad 9 simulator for 13"-geometry reasons (probes under the dock, the
  `tapAway` gap) — test debt, listed by the 2026-10-13 regression pass (`~/PaintWork/deploycheck-logs/`).
  Landscape `XCUIScreenshot`s come out rotated and cropped: use `simctl io … screenshot` + `sips -r 270`.
- **A busy main thread turns a swatch tap into a long-press** ("Delete Swatch"), which swallows later
  taps — a trap for any test seam that holds the main thread.
- Simulators degrade over a long session; make a fresh device rather than debugging a stale one.
- Survey and design notes for the queued items are in `~/PaintWork/design/` (outside git).
