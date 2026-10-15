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

Main is `17b438c`; Liquify remains unmerged. Root candidate `tmp/s49-integration`
combines material `72f686f`, raster `ae40f66`, sampler `effb239`, the named-gallery helper correction,
and exact inverse batching. Harvest only clean worker commits; the next raster delta starts at
`ae40f66`. Shared required-picture failures now retain the prior live picture and avoid immediate
same-version retry loops. The attempted headless view assertion could not compile because that view
is not in the logic target; it was removed, never counted as a native proof. Material is reviewing
the view guard; raster is running the restored consumer logic and eraser UI. Preserve current main
documentation rather than importing workers' historical copies.

- **Root integration and exact batching.** Existing `PixelOps.parallelMap` fans out disjoint point
  batches and raster row strips over a shared immutable prepared field. Scalar arithmetic, global
  pixel centres, ordered failure and evaluation counts remain exact. All temporary arrays are
  charged; the joined raster allocation is exact-sized. Baseline Debug34/34 passed. Three committed-
  baseline faults caught wrong sources/counters, hidden or invented failure, strip offsets and
  underestimated memory (2/3, 2/3, 1/3 methods failed respectively); sources were restored. The first
  raster fault launch ran zero tests and is explicitly excluded. The restored opt-in Debug run was
  cancelled after the18-fixture benchmark passed and four hard/one patterned actual windows matched
  every reference byte. Debug patterned batches took202.6s versus scalar90.9s; this is a real Debug
  slowdown, not a shipped-speed claim. Release correctness is green; batching acceptance
  depends on its optimized actual-producer measurement. The cancelled run is not4/4 qualification.
  Evidence: `~/PaintWork/s49-liquify-logs/combined/batches/`. External matching C++ batches were faster
  in four alternating pairs, but native Release and device costs remain unqualified.
- **Linked UI.** `linked-release-2` passed 1/1 in Release: deformation, exact cold-reopen picture and
  green source ink subsequently reaching the linked frame. Existing black/red ink stays byte-identical;
  the missing-ink suspicion was refuted. Both named saves use the shared helper with the scene name.
  Final modes/profile UI remains. Evidence/package: `~/PaintWork/s49-liquify-logs/combined/`.
- **Material — `material_resume`, clean `aee14ec`, source `72f686f`.** Restored55/55 passed, including
  clipped output and rendered Push/cut/later-Push/lattice/Move chronology. Same fractional crop now
  processes17,248/38,577 output points at scales1/1.5 instead of262,144 each; global source sampling is
  unchanged. Full-tile and lost-origin faults caught six intended assertions. Earlier model/query
  faults remain qualified. Evidence: `material-visible-handoff.md` and `material-native-handoff.md`
  under the Liquify log directory. Currently reviewing the shared refusal boundaries read-only.
- **Sampler — `raster_sampler`, final `effb239`.** Native Debug20/20 and quiet Release21/21 passed;
  final allocation-only cleanup passed11/11 production-source Mac checks. One bounded Lanczos kernel,
  no added cache, arbitrary filter cutoff or Core Graphics fallback. PERFORMANCE§36 records memory,
  native warm/cold costs and numerical limits. First simulator window cost523ms included initial Metal
  engine/pipeline access; actual app/device first use remains. External qualification complete; worker
  owns no simulator job. Evidence: `~/PaintWork/s49-liquify-logs/raster/sampler/QUALIFICATION.md`.
- **Raster — `raster_resume`, current checkpoint `ae40f66`.** Shared settlement
  reports success through every mutation/save boundary; refused edits retain state and do not close
  the scene. Required source failures propagate, nested rollback is atomic, transformed scratch
  opacity is preserved. Restored109/109 passed; two final adapter faults reproduced eight intended
  diagnostics. Native iPad9 landscape8/8 UI passed, and a focused3/3 raw simctl recapture is green;
  root inspected all three correctly oriented1080×810pt pictures. XCTest app-cropped attachments
  were malformed, not the UI. A new pre-fix method failed19 intended assertions: full/fitted frozen
  rendering, thumbnails/onions, a posed provider and destructive merge hide required render refusal.
  That non-fallible contract is now removed through existing PixelOps callers, preserving prior
  thumbnails/onions and refusing destructive copy operations. Existing success tests explicitly
  unwrap required renders. Compile-only adaptation attempts ran no tests and are excluded; restored
  110 logic plus five raster UI methods are in progress, followed by the deliberate fallback fault.
- **Storage/model completed.** `52eda39` storage: Debug115/115, seven fault groups/nine failed
  executions/46 diagnostics, restored18/18; genuine prior-format producer `840d68a`, nine unchanged
  provenance hashes. Model `afef15c`: five fault groups/14 failed executions across13 methods,
  restored13/13. Source is integrated. Evidence:
  `~/PaintWork/evidence/s49-liquify-material-{format,model}/`; do not repeat or cherry-pick again.

**Restored Release batching correctness:** both new logic methods passed, followed by all 18 native
source/pixel fixtures in a separately opted-in method (1/1, zero skips). The first selection omitted
that opt-in and skipped it; do not report that run alone as complete. No optimized timing was run.

**Native queue:** the owner is using the Mac and will notify when finished; performance measurement
is deferred. Root Release build succeeded; slot2, simulator `80BE77F5-9118-4CDD-854D-07C3E9A9009B`,
will run the three Liquify UI methods. No performance timing run has begun. Raster owns slot1 for
restored consumer logic/UI; material reviews the live view guard, with production edits owned solely by raster. After final raster integration: recount,
lints, fast Debug/Release, quiet actual-producer Release measurement, touched UI, full suite and
pre-install legacy drives. Current static census at `149fc7a`: fast5284 across256 matching classes,
full5866; recount after the last delta. Obtain fresh saved/unlocked readiness before device work;
the earlier readiness was consumed by the completed179 probes and the iPad has been released.

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
