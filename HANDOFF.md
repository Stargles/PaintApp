# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. Write it for any agent: the next session may not be Claude Code. -->

**Start here:** read [AGENTS.md](AGENTS.md) (the owner, the standing rules, the bar for done), then this
file, then [CLAUDE.md](CLAUDE.md) (build, test, merge, deploy), then the specification for whatever you
pick up. [TODO.md](TODO.md) is the owner's asks **in queue order — the top is next**; [BUGS.md](BUGS.md)
is what we find.

## State (session 49 in progress, resumed 2026-10-15)

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

Main is `17b438c`; Liquify is unmerged. Root candidate `tmp/s49-integration` at `700e1ae`
combines material `72f686f` and raster `7d6d4eb`, plus the shared named-gallery helper correction.
The candidate does not yet contain the accepted C sampler or raster refusal adapters. Harvest only
clean worker commits; apply bounded deltas and preserve current main documentation.

- **Root integration/profiling.** `linked-release-2` passed 1/1 in Release: deformation, exact
  cold-reopen picture and later green source ink reaching its linked frame. Existing black/red ink
  is byte-identical across the source edit; a visual suspicion of missing ink was refuted. The saved
  package and inspected images are in `~/PaintWork/s49-liquify-logs/combined/`. Both named-save UI
  calls now use the shared helper with their actual scene name; final modes/profile UI remains.
  The real-window Release benchmark passed 1/1: hard/pattern 48,236,266 / 179,020,536 evaluations,
  zero failed solves. Profiled contended warm times 0.93 / 10.35 seconds are not isolated/device
  qualification. Long patterned inverse cost remains open. Exact alpha predecoding, lookup/SIMD
  and changed-map continuous-flow experiments were rejected; see evidence before repeating them.
- **Material — `tmp/s49-liquify`, `material_resume`.** Prior restored slice passed 54/54 at app
  `900331c`, including rendered Push/cut/later-Push/lattice/Move chronology. Four fault batches caught
  15 intended failed method executions; separate alpha-only faults cover actual alpha-1 query ink.
  Evidence: `~/PaintWork/s49-liquify-logs/material-native-{handoff.md,evidence-index.json}`.
  Clean `72f686f` clips coordinate/sampling work to actual visible output while preserving global
  pixel centres and full native source tiles; root integrated this delta. New full-versus-clipped
  pixel/count proof, two faults and restored 55-method slice are queued after sampler's quiet run.
- **Sampler — `tmp/s49-raster-sampler`, `raster_sampler`.** Owner accepted smoother C provided code
  and cost are proportionate. One shared bounded Lanczos kernel uses global coordinates; no extra
  cache, Core Graphics fallback or arbitrary scale cutoff. Clean `89440a2` passed native Debug20/20
  (11 sampling + nine warp agreement). Quiet Release21 includes the cost/retention method and is
  compiling. Afterwards only a small allocation cleanup in the CPU source-apron scan is planned,
  followed by focused restoration; final root Release will cover final bytes. Evidence:
  `~/PaintWork/s49-liquify-logs/raster/sampler/QUALIFICATION.md`.
- **Raster — `tmp/s49-liquify-raster`, `raster_resume`.** Root has its baseline `7d6d4eb`; later
  commits integrate sampler/adapters and atomic refusal. Earlier adapter run passed 76/77; the one
  raw-image mismatch was an invalid oracle comparing pixels outside the clipped held footprint.
  The actual held-window draw over unchanged base matches the full committed picture exactly.
  New native pre-fix proofs expose nested rollback, final texture allocation and ignored settlement
  failure. `6522ba8` addresses rollback/allocation; `63d8cae` removes temporary diagnostic notes.
  Clean `fcd35fa` adds actual save/resize/frame/layer/tool refusal tests. The worker is preparing
  central Bool success propagation and all mutating callers; failed save cannot close the scene.
  Restored/fault batches and all five raster UI methods on iPad 9 landscape remain.
- **Storage/model completed.** `52eda39` storage: Debug115/115, seven fault groups/nine failed
  executions/46 diagnostics, restored18/18; genuine prior-format producer `840d68a`, nine unchanged
  provenance hashes. Model `afef15c`: five fault groups/14 failed executions across13 methods,
  restored13/13. All source commits are already integrated. Evidence:
  `~/PaintWork/evidence/s49-liquify-material-{format,model}/`; do not repeat or cherry-pick again.

**Native queue:** sampler alone owns slot1 through quiet Release cost; all other simulators are
parked. Material then takes slot2 for its four qualification runs, followed by raster's restoration,
faults and landscape UI. Root has no native job running. Final combined census/lints, fast tiers,
touched UI, landscape inspection, full suite and pre-install legacy drives remain.

## What is next

1. Finish material precision/refusal/query tests, raster scratch UI/mutations and the accepted bounded
   sampling implementation (measure cost and code size). Combine clean branches; final Debug/Release
   census/lints, touched UI, native iPad 9
   landscape and a full suite. Before Liquify install, drive playback, grey-area pan, Move box,
   graph node drag/release and a stroke too. Remove (178) whole only in its completed merge.
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
