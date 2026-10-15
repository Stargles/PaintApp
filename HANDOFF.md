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

**The iPad has `f813346` Release**, automatically re-signed/installed October 15 at 01:08 Toronto
while usage was limited. App source is `840d68a`, without Liquify; profile expiry
`2026-10-22T05:08:05Z`. Fresh saved-scene/unlocked readiness is required before restarting it into
probes. Keep one-shot repairs until the owner confirms real scenes; first run the final repair
signature so preserved preupdate snapshots are also converted.

**(178) Liquify: active ownership and evidence**

- **Feature/material — `tmp/s49-liquify`.** Linked generated frames keep source links; all raster
  pixels move, including flattened pictures/text; editable typed objects stay untouched; exterior
  selection pixels stay fixed while vectors remain editable. Required placement replaces old
  Distort/rest ownership. Immutable material operations are shared and strictly codec-deduplicated,
  never globally pooled. Combined storage/native baseline `afef15c` passed 60/60. Boxing the lattice
  lowers VectorElement stride 1080→856 B, bridge 80 B, unchanged budget. Prior native/preview gates 26/26
  and 30/30 remain evidence only for unchanged seams. A 100-stroke fixture shares one field,
  144000 evaluations, 99 coordinate hits, 11,535,208 peak counted bytes including the field under the
  unchanged 24 MiB payload cap plus one field. Scoped autorelease lifetimes prevent accumulation.
  Four preserved pre-fix methods exposed exterior hit/outline/erase, unsupported map output,
  fractional gradient quantization and linked paper anchoring. Clean `3bf3d47` passed 22/23: the
  first three now pass, paper still fails exact RGB (phase/alpha improved; direct-byte diagnostic
  pending). It shares inverse transport and native tile sampling; lasso membership stays centreline.
  Review then found large supported integer texels rounding into the next tile and a negative
  local index. Recorded before integer-division fix `d74e247`; actual tile-lookup regression is in
  its focused 13-method run. The same run measures repeated native walks for 100 distant eraser
  candidates before optimizing through existing painted bounds, with no new cache. A paper
  precision change is only being evaluated, not yet qualified. Slot 2 currently belongs to this run.
- **Storage/model — completed slices.** `tmp/s49-liquify-material-format`, clean `52eda39`:
  Debug 115/115; seven faults/nine expected failed executions/46 diagnostics, restored 18/18.
  Twelve owned commits are already integrated at `afef15c`. Genuine producer `840d68a` wrote the
  prior-format package; nine provenance hashes unchanged. Projects/Backups/Trash/staged restore,
  retained native bytes, precise cut ancestry, recipes and failed-save rejection are covered.
  Ordinary nonmaterial damage policy stays intact. Model worktree is exact clean `afef15c`:
  five fault batches, 14 failed executions across 13 methods, then restored 13/13. Evidence:
  `~/PaintWork/evidence/s49-liquify-material-{format,model}/`. Their own simulators were deleted;
  no further cherry-picks. Final combined Release/full/UI remains owed.
- **Raster/shared presentation — `tmp/s49-liquify-raster`, clean `0d3c628`.** One held cel picture
  and pending-window presenter replace parallel vector/raster procedures. Atomic mixed history,
  one producer, exact stream tick certification, document-version guards and immutable coverage
  are implemented. Ordinary ink follows container+cel pose; backing follows container only;
  linked ink intentionally stays unposed. Required refusal preserves prior pixels/history.
  Pending windows retain pixels+path only. Equal-key reuse certifies the actually installed image,
  raster identity and displayed raster version; stale/cross-cel and delayed-base guards are tested.
  Independent review found both tiers were only drawing inside their own transformed lobe after
  clearing their union. Actual Colour/Opacity host+stream oracles produced four intended reds;
  `19e0153` redraws both tiers through the shared union using the existing snapshot/window renderer.
  Focused 41 now 40 passed/1 failed/zero skipped: the sole remaining method is the raster sampling
  mismatch below. Native-only posing and all placement/version/refusal checks pass. Latest images
  localize 156 differing channels/max 80 to 78 pixels around the painted raster edge, identical in
  raster/mixed cases. Fixture-only `0d3c628` retains union before/after pictures for its proof run.
  Cold portrait UI 5 is now running in slot 1; native iPad 9 landscape and current mutations follow.
  No supported small-pose projective refusal was demonstrated by source review: oversized output
  downsamples, noninvertibility refuses earlier, and allocation failure was not artificially induced.

**Newest source review:** the ordinary vector-eraser scratch still flattens ink plus backing in
`StrokeCanvasView.displayedScratch`, then host and stream apply different poses to that combined
picture. This bypasses the new complete cel-picture owner. Recorded in TODO before a native
reproduction; raster worker will characterize integer-translated ink over stationary nonuniform
backing, then consolidate the sibling path through the existing presenter if confirmed.

**Raster appearance choice is pending.** Core Graphics high sampling depends on full source extent,
so a cropped preview can differ at lift. A virtual full-extent provider matched but retained about
230 MiB of scaled-image cache over 100 draws and was rejected. An external bounded Lanczos prototype
matches full/window output and added about 3.2 MB peak over 100 512-square draws. It visibly smooths
reduced grain. Root inspected/sent `~/PaintWork/s49-liquify-logs/raster/pose-sampling-A-C-comparison.png`;
owner choice C (smoother) versus A (preserve appearance) remains unanswered. Do not adopt without that
ruling. All transformed raster backing would share preview/committed sampling; native vector ink
stays native. Prototype figures are not production/device qualification.

Earlier surface-handoff 30 logic/6 UI with 19 faults, inverse Release 7/7 over 18 byte-identical fixtures,
and pre-material linked UI 3/3 remain reusable only where the seam is unchanged. No speed-ratio claim.
New placement and rendering paths need current proof. Preserve evidence before cleaning worktrees.

## What is next

1. Finish material precision and bounded hit queries, raster UI/mutations and the pending sampling
   decision. Combine clean branches; final Debug/Release census/lints, touched UI, native iPad 9
   landscape and a full suite. Before Liquify install, drive playback, grey-area pan, Move box,
   graph node drag/release and a stroke too. Remove (178) whole only in its completed merge.
2. **(179) physical probes:** updated iPad build supports effect, opacity, shape and fill. Prior
   `7cf3245` supported only effect among these; unknown modes fell back to playback. Physical effect
   baselines at 4096²/2048×1024 yielded 9/100 held pictures over 100 ticks (PERFORMANCE §30.6).
   After-build measurements remain. Ask for fresh saved-scene/unlocked readiness; preserve whole-
   trace counts. Probe CLI: 100 ticks at 80 ms, not JSON tickCount (frame events).
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
material deformation while retaining editable strokes. The transformed-raster appearance choice above is now pending; the Liquify scope itself is settled.

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
