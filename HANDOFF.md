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

Verify `git fetch origin`, `git worktree list` and every `tmp/*` branch before resuming. All build
worktrees are under `~/PaintWork`, outside Desktop. Never harvest a dirty worker tree: deliberate
faults may be running. The owner permits useful delegation but prioritises usage conservation and
quality over speed. Three workers are active; native runs are explicitly scheduled across two simlock
slots to avoid starving another worker's queued run.

**Main app/test source is `840d68a`; no Liquify is merged.** Later main commits are coordination docs.
Session 49 shipped: (190) first-fill transfer `e6b7d81`; (177) strict stream recovery `4d396c6`;
(35) masks `b625710`; (189) onion-panel updates `8616532`; and Fog Glow preview-radius equivalence
through `840d68a`. Causes and focused proof are in those commits. The combined Debug and Release
fast tiers each passed **5124 tests: 5120 passed, four skipped**, matching source census; full census
5694. Shared fill/stream and recovery UI passed 21/21, Glare 2/2 at integration. Native iPad9 pictures
were inspected. Evidence: `~/PaintWork/s49-integration-logs/` and the task evidence directories.

**The owner's iPad has `f813346` Release**, automatically re-signed and installed on October 15 at
01:08 Toronto during the usage limit. Its app source is `840d68a`, without Liquify. Profile expiry:
`2026-10-22T05:08:05Z`. Do not retire one-shot repairs until the owner confirms real scenes are good;
first run the final repair signature so preserved preupdate snapshots are converted too.

**Main full-suite triage:** `e3b487c` (same app/test source) ran **5694 total, 5624 passed, 57 skipped,
13 failed**, four clones, 5907 seconds; source census reconciles. Archive and per-class table:
`~/PaintWork/s49-final-validation/full-main/`. Twelve UI failures reran serially on a fresh device:
ten passed; Guide-above subsequently passed alone. Interpolation repeated, and its actual saved
pre-Commit package proved a test precondition error: synthetic slider time 0.49741339683532715 was
below the local stroke's 0.4980711340904236 visibility threshold. No Commit product defect was found.
Root's `tmp/s49-integration` now commits at 0.75, requires visible ink before Commit, compares the
same black-ink columns afterward and uses one screenshot per sweep. Cyan guide pixels were excluded
with the existing `isInk` predicate. The revised test passes; both deliberate faults are caught
(invisible precondition and missing committed local ink). Restored touched UI is currently running.
The pad timing failure also exposed a redundant unconditional cap: four warm opt-in runs measured
43.97–45.11 ms/stroke, below the existing stricter total-pad bound. That opt-in bound remains the sole
timing gate; structural checks and printed measurements remain. Root changes are committed through
`7561b91`, but not merged; Debug/Release fast gates still remain. The mutation script restores exact
committed source on exit. `tmp/s49-regression` is an earlier checkpoint, not authoritative.

A new intermittent Blend Mode menu failure occurred twice in the complete Fog Glow drive on fresh
simulators. Warm and fresh diagnostic captures then opened it on the first tap; recorded presentation
state was normal. These boundary-only diagnostics do not qualify the full drive. Keep the issue open;
no retry, delay or menu workaround was added. Evidence: `s49-final-validation/triage/` under
`regression-ui{,-2}`, `fog-flight{,-fresh}`. Root owns this triage and the regression gates.

**(178) Liquify: active worker ownership and immutable evidence**

- **Feature/material — `tmp/s49-liquify`, `d52950b`.** Owner requires linked generated frames to retain
  their links, all raster pixels to move (flattened text/pictures included), editable typed objects
  unchanged, and exterior selection pixels fixed while vectors remain editable. The new required
  placement representation replaces old Distort/rest ownership. Immutable material operations are
  shared at runtime and deduplicated by the strict scoped codec, never a global pool. Native group
  opacity, eraser and paper staging are retained; bounded source/inverse tiles reuse the existing
  stamping and ImageWarp seams. Focused native gate **26/26**; preview/cut gate **30/30**. The 100-stroke
  fixture uses one field, 144,000 inverse evaluations, 99 coordinate-cache hits, and 11,535,208 peak
  counted bytes including the field, below the unchanged 24 MiB payload cap. Scoped autorelease
  lifetimes removed accumulation near stroke 90. Outside-selection bytes, stationary-boundary
  gradients, long patterned tails, nonzero scratch offsets, render refusal and antialiased cuts pass.
  Root inspected native pictures. A broad Debug run is currently frozen at `d52950b`, expected
  **5218 methods in 254 filename-selected classes**. Known failures so far include panel/filter audit
  assumptions, storage repair not yet integrated, and a real per-stroke stride increase. The latter
  must be fixed by compact representation, not a higher memory assertion. After the run: integrate
  storage, fix those omissions, pin rendered-ink tap/retag and eraser candidacy before changing hit
  testing (lasso membership remains authoritative centreline), pin linked paper staging before any
  change, guard finite but integer-unsafe bridge outputs, and finish current assertion mutations.
- **Storage — `tmp/s49-liquify-material-format`, clean `52eda39`.** Focused Debug **115/115**, zero
  skips/failures. Seven deliberate faults produced nine expected failing method runs and 46 XCTest
  diagnostics, followed by restored repair **18/18**. The final fault separately proved a missing
  manifest rejects an intact failed-save stage. JSON failures prevent a final manifest and atomic
  swap; malformed material cannot silently load as empty. Ordinary nonmaterial damage policy is
  preserved. Actual unchanged producer `840d68a` wrote the prior-format package covering ordinary,
  Distort, retained bake, precise cut parent and recipe-local strokes; native walks/RGBA, repair,
  save and staged restore pass, with all nine provenance hashes unchanged. Evidence, delivery commits
  and results: `~/PaintWork/evidence/s49-liquify-material-format/`. Worker simulator deleted.
  Feature has the 12 storage-only commits to integrate at its clean boundary. This worker next owns
  mutations of the 13 non-native material/model methods from the combined immutable SHA; avoid an
  early throwing decode masking later geometric assertions. No Release/full/UI gate in this slice.
- **Raster/shared presentation — `tmp/s49-liquify-raster`.** Shared `LiveCelContentEdit`, complete
  `CelContentPicture` and one pending-window presenter replace separate vector/raster procedures.
  Atomic mixed history, one geometry producer, stream tick certification and document-version guards
  are implemented. Frozen bounds are preserved. Required render refusal leaves prior picture,
  backing, recipe and history unchanged; latest qualified native gate **6/6**. Source checkpoint
  `e079b69` adds immutable ink/backing placement and derivation identity, stale/cross-cel rejection,
  pending revision protection and explicit render-failure versus clear semantics. It is not yet
  built. Ordinary native ink uses container plus cel pose; backing uses container only; linked ink
  intentionally ignores those poses, as the existing spec/tests require. The complete held derivation
  must also use this shown-space picture, avoiding double posing or masking backing with ink-only
  pixels. A pose-changing base must cover the newest pending complete picture; same-pose advances
  remain allowed. Equal-key image reuse must certify the actually installed backing before it can
  mint newer coverage. Source work continues; next selected baseline is at least 37 methods.
  Native iPad9 posed preview/commit UI and current mutations are still owed.

**Raster appearance choice is pending.** Core Graphics high sampling changes with the full source
extent, so an independently cropped preview can differ at lift. A virtual full-extent provider
matched pixels but retained about 230 MiB of scaled-image cache over 100 draws and was rejected.
An external bounded Lanczos prototype matches full/window output and added about 3.2 MB peak over
100 512-square draws. It visibly smooths reduced grain. Root inspected and sent
`~/PaintWork/s49-liquify-logs/raster/pose-sampling-A-C-comparison.png` to the owner, asking whether C
is acceptable or A must be preserved. Do not adopt it without that ruling; all transformed raster
backing would share it for preview and committed pictures, while editable vector ink stays native.

Earlier qualified evidence remains useful only where the seam is unchanged: retained occurrence
identity for linked captures; strict selection/retarget/resize tests; shared surface handoff 30 logic
and six UI green with 19 faults caught; inverse acceleration Release 7/7 across 18 byte-identical
fixtures, no speed-ratio claim; current pre-material linked UI 3/3. Evidence directories and commits
are recorded in the feature history. New placement/preview ownership requires its own proof.

## What is next

1. Finish root regression mutations/restored UI and Debug/Release fast gates; merge the tested fixes.
2. Finish the three Liquify branches, combine clean commits, reconcile source census, run Debug and
   Release fast tiers, touched UI, native iPad9 landscape and a final integrated full suite. No Liquify
   install until the old artist operations are driven too: playback, grey-area pan, Move box, graph
   node drag/release and a stroke. Remove (178) whole from TODO in its merge.
3. **(179) physical probes:** current iPad build supports effect, opacity, shape and fill. Prior
   `7cf3245` supported only effect among these; unknown modes fell back to playback. Physical effect
   baselines at 4096²/2048×1024 produced 9/100 held pictures over 100 ticks (PERFORMANCE §30.6).
   After-build measurements remain. Ask for a freshly saved scene and unlocked iPad before restarting
   the app into temporary probe scenes. Preserve the whole-trace counting convention.
4. (27) real laptop verification remains owner-deferred; (22)/(10) deprioritised, (37) dropped, and
   Later features await discussion. Do not start researching those while the owner is unavailable.

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
