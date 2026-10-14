# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. Write it for any agent: the next session may not be Claude Code. -->

**Start here:** read [AGENTS.md](AGENTS.md) (the owner, the standing rules, the bar for done), then this
file, then [CLAUDE.md](CLAUDE.md) (build, test, merge, deploy), then the specification for whatever you
pick up. [TODO.md](TODO.md) is the owner's asks **in queue order — the top is next**; [BUGS.md](BUGS.md)
is what we find.

## State (session 49 in progress, 2026-10-14)

**Check `git worktree list` and every `tmp/*` branch first** (`git log --oneline origin/main..<branch>`)
— `origin/main` is a shared ref and a cut-off session's work sits on its branch.

**Session 49 is in flight.** The verified starting point was `5d73184`; no prior `tmp/*` branch held
unmerged work. (189) is merged at `8616532`, and (190) at `e6b7d81`. Active task branches under
`~/PaintWork/` are `tmp/s49-liquify` (178), `tmp/s49-liquify-format` (isolated storage validation),
`tmp/s49-liquify-inverse` (same-map inverse validation), and `tmp/s49-liquify-raster` (the now-ruled
raster/mixed cel path).
The integration, Fog Glow and coordination trees are retained for evidence and final regression work.
Never harvest dirty worker files: mutations may be intentional.

- **(190) merged:** the owner’s transient-to-baked theory was confirmed. Commit writes the fill before
  transferring its exact preview to the existing held-picture lane. Debug/Release 5089 each, four skips,
  zero failures; touched classes 19/19 green. Missing handoff, early callback and false cancellation
  mutations fail. Native iPad9 fill and onion-panel screenshots were inspected. Existing reference-layer
  geometry fails on iPad9 and passes on fresh 13-inch. `MidGestureSampler` assumes portrait.
  The combined stream landing correction below clears the held fill before a new stream recipe
  is minted, while keeping the old surface until the replacement is held.
- **(177) merged** at `4d396c6`. Debug 5101 and Release 5102 (extra merged189
  assertion), four skips and zero failures each. New UI class 4/4, production mutants red/restored,
  actual prior-build package roundtrip and native landscape inspected. Combined fill landing and
  staged backup repair also passed the integration gates below.
- **(35) merged** at `b625710`: Debug and Release at `deb168f` each ran 5107 tests,
  5103 passed and four skipped. Nineteen mutation batches restored, feature/recovery and filing UI
  green, native landscape inspected. Strict staged restore exposed package collision/queued-rename
  bugs, fixed through the existing serialized save queue with exact marker rollback. The combined tree passes
  5124 fast tests in each configuration; its overall census is 5694.
- **Fill/stream integration is merged:** clear the held model before
  transferring the committed fill picture, then release the old surface. Reverting the order produces
  a visible second coat (red 126→64→126); restored ordering stays at one. Four staged-restore mutations
  fail: actual previous-build stream backups restore through a repaired copy, original snapshot bytes
  remain pristine, and malformed present stream metadata cannot replace healthy artwork. Repair
  retains only drawing paths and validates/rewrites one file at a time. The combined touched classes
  passed 21/21 on an erased simulator; two earlier Guide-menu setup failures did not recur with the
  same preceding tests. No menu workaround was added.
- **Fog Glow is merged** (source through `840d68a`): convert to the existing equivalent Bloom before scaling
  its render radius. Dimensionless Size was never scaled, so every size widened in half-detail.
  Focused logic/UI 3/3 green; reverting the fix fails actual pixels at Size 2 and 6 and during a held
  slider drag. Comparison panels and native iPad9 landscape were viewed. Combined Debug and Release each passed
  5124 tests (5120 passed, four skipped, zero failures), reconciled against source. Integrated
  `GlareUITests` passed 2/2. UI identifier/helper checks and PBX duplicate-ID scan are clean.
  Results are preserved in `~/PaintWork/s49-integration-logs/`; the QA simulator was deleted.
- **(178) in progress; no Liquify code is merged.** The owner requires linked in-betweens to retain
  their source links. The feature branch includes occurrence captures (`ea0152f`): source-cel/element
  identity survives regrouping and cloned cels. Prior gestures affect only local edits already in
  their membership; later gestures capture newly drawn marks normally. Inverting older gestures for
  new local ink was rejected after the high-precision check showed it cannot preserve stored precision.
  The owner ruled all raster pixels move, including flattened pictures/text; separately editable
  text, picture, video and stream objects remain untouched.
  - **Storage:** actual `5d73184`-written package retained with provenance. Retarget, resize and strict
    selection decoding (`ae58c7e`, `1fd073e`, `42ff0b1`) are integrated: 47/47 Debug, fourteen distinct
    faults caught in fifteen runs, restored 3/3; earlier storage pass sixteen faults red, restored 12/12.
    Expanded fixtures `f9ecedb` (feature `6c457c9`): all 25 distinct faults caught across 31 selected
    executions, restored 11/11 green. Format worker simulator deleted. That worker now
    owns the isolated raster task.
  - **Lift and held pictures:** shared source `25791ab`/feature `c07406f` transfers the shown IOSurface
    and composes overlapping pending replacement windows. Independent expected-image oracle
    `86dd98c`/feature `71acf33` corrected a test that previously shared the broken list with production.
    Nineteen distinct faults are now red, restored logic 30/30. Existing held-picture UI **6/6 green**
    (SelectionEditLive 2, SelectionFillRecolour 1, UnlandedInk 3); pending/landed screenshots viewed.
    Evidence: `~/PaintWork/s49-surface-handoff-logs/`; root simulator deleted. Feature finalizer
    `17db4c3` passes 58/58 Debug: one geometry producer, normal lift off main, subsequent edit/snapshot
    settles the pending result before writing history. Changed strokes use existing precise storage.
  - **Selection and target ink:** true-curve containment disagreed with chord distances at a curved
    selection edge. The worker's certified curve-error taper passes three raster fixtures with zero
    changed exterior bytes. A new fixture found **2,904 changed alpha pixels well outside a local
    Push** on a 960-point Streaky target stroke: moving its spine changes the downstream stamp phase.
    This must be fixed at the existing rest-walk/stamping seam, not hidden by a wider preview window.
    Compact retained-parent/site correspondence is the candidate. A wide/scattered stamp can overhang
    a selection even when its anchor is inside. Native A/B was inspected and sent to the owner:
    shipped Streaky spacing, 48 native dabs; A moves 1,703 exterior alpha pixels, B moves zero.
    Required behavior question is pending: A moves whole brush marks; B keeps all outside pixels
    fixed and needs a 2D material representation to keep vectors editable. No material schema is
    chosen. Comparison: `~/PaintWork/evidence/s49-liquify-selection-options-native-spacing/comparison.png`.
    Fixture checkpoint `99ef7c8`; current vector/linked/profile UI passed 3/3 on `57d8247`.
    The canonical linked fixture reopens with zero changed sampled bits, then follows later source
    ink. Screenshots inspected under `~/PaintWork/evidence/s49-liquify-ui-current/`.
    Evidence: `~/PaintWork/evidence/s49-liquify-curved-selection/` and `s49-liquify-target-phase/`.
  - **Raster cost:** the original direct map folded under strong brushes; bounded reversible Euler
    steps replaced it. Prepared brush data/indexed bins and removal of a diagnostic forward pass keep
    native pixels unchanged. Isolated Release `ddebad6`: hard 67,100 pixels / 54,319,422 field evaluations
    / 1.663 s; patterned 84,956 / 290,752,890 / 12.426 s. Zero source-solve failures, eight independent
    60-digit source-coordinate references agree within 3.96e-13 pixels. Simulator seconds are not
    device throughput. Full-sweep prepared field is 6,540,296 bytes; prepare one field at a time.
    Raster interaction cost remains open. CPU sampling identifies native alpha sampling as the largest
    cost; exact lookup/SIMD trials had no reliable gain. Continuous-flow integration changes the map
    or loses its saving at higher accuracy. Neither experiment is adopted. Same-Euler inverse
    acceleration cuts the horizontal fixture's evaluations by 38.43% with identical RGBA. Focused
    native Release validation passed 7/7: 18 signed/diagonal/pattern/grain/selection fixtures have
    identical RGBA and zero source failures. Hard-window evaluations fall to 48,236,266; patterned
    to 179,020,536. Commits `ac8a177`, `2acece9` (feature `ab99f9d`, `57d8247`): temporary oracle removed, restored
    Release 7/7, seven solver mutations and five retained-assertion input faults red. Inverse worker
    simulator deleted. Root reviewed code and image pairs. Timings were not paired, so claim
    evaluation savings, not a speed ratio. `~/PaintWork/evidence/s49-liquify-inverse-native/README.md`.
    Evidence: `~/PaintWork/s49-liquify-profile/`, `~/PaintWork/evidence/s49-liquify-sampler/`,
    `s49-liquify-flow-prototype/`, and `s49-liquify-inverse-acceleration/`.
  - **Raster:** ordinary raster hold/commit was absent. The owner ruled all pixels move, including
    flattened backing on a vector cel; typed editable objects stay unchanged. The raster worker owns
    the shared cel-content window generalization, one-producer resolution, atomic mixed history,
    drawn-pixel/undo/reopen tests. Reuse one window presenter rather than parallel vector/raster lanes.
    Reading exposed a backing-pose mismatch: `LayerHostView.shownPose` leaves `bakedImageView` unposed
    although `PixelOps` poses it. Align its origin-based layout and replacement hole with the shared
    pose, and verify actual translated/scaled/rotated pixels. Its current center anchor cannot simply
    receive the fill plane's origin-based transform.
  - **Still owed:** target material-phase fix, raster completion, feature mutations,
    pending edit/undo/save and rapid overlapping previews,
    native iPad9 UI, final Debug/Release fast tiers, final audit and integrated full UI run.

The owner permits any useful agent count but prioritises usage conservation and quality over speed.
Keep delegation focused and report the queue occasionally. It is now after the owner’s 10 a.m. return.
**Owner saved the scene and unlocked the iPad on 2026-10-14 for probes.** Installed `7cf3245` only supports
playback/edit/recolour/effect; unknown modes silently fall back to playback. Physical effect baselines
are complete: 100 ticks produced 9 held pictures at 4096² and 100 at 2048×1024 (PERFORMANCE §30.6).
Opacity/shape/fill after-measurements require the updated build. Do not mislabel old-build probes.
The full UI suite is owed on the integrated tree before the next install.

**Build from `~/PaintWork`, not `~/Desktop`** (CLAUDE.md "Build and test", first paragraph).
`~/PaintWork/deploy` is a detached worktree kept for device builds.

**The owner's iPad has `7cf3245`** (Release, installed 2026-10-13 after an iPad-9-simulator regression
pass of 210 UI tests — every red was the known 13"-geometry debt or environmental). Its profile expires
**2026-10-15T04:52Z**; the re-signer (`~/PaintApp/deploy/resign.sh`, syncs to `origin/main`) is armed for
2026-10-14 23:52 local — **and it installs whatever `origin/main` is then**, so the full UI suite below
should run before that, or the re-sign ships an unproven build. **The next install runs
`LegacyToolSettingsRepair` on the owner's scenes** (TODO (176)'s one-shot repair, below) — tell the owner
when it lands and ask them to open a few scenes.

**Latest integrated fast tier (app/test source `840d68a`)**: Debug and Release each 5124 tests,
5120 passed, four skipped and zero failures; static full census 5694. The full UI suite has not been run since `38a3dd6`
(session 47) — every item since ran its own UI classes; **run it (CLAUDE.md "Full run", erased device)
before the next device install**, since ~70 merges landed without one.

## What is next

1. **TODO (179)** — the combined integration gates are complete; run the
   owner's iPad `PlaybackProbe` after-measurements on an updated build after the final full UI suite.
   **(189) merged** at `8616532`: 100 onion-opacity ticks cause zero editor passes (previously 100);
   Debug and Release fast tier 5087 each, 4 skipped, zero failures. **(190)** merged at `e6b7d81`.
2. **TODO (177) and (35) are merged.** Their shared integration checks are described above.
3. **TODO (178)** — liquify (raster + vector, Push / Pinch-Expand / Twirl, active layer, selection limits
   it), on (176)'s `ToolProfiles` as a third tool. Survey §C.

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
flattened pictures/text that old raster layers can no longer distinguish from paint. **A separate vector selection-edge choice is pending**, with a native A/B already shown:
A carries whole brush marks (including overhang); B keeps every outside pixel fixed (recommended),
requiring 2D material deformation while retaining editable strokes. Do not infer an answer from elapsed
time. Independent raster and current feature UI work continues.

**After the next install:**
Once the next build has repaired his scenes and they look right: retire the one-shot repairs.
   First run a final repair build with a new signature so the preceding build's preserved preupdate
   snapshots are also converted; verify all library packages decode before removing repair code.
   This keeps old snapshots usable without a permanent legacy decoder. Delete `LegacyToolSettingsRepair`
   (and `LegacyPoseTrackRepair`, if the keyed scene from session 47 was restored and animates — still
   unconfirmed: Gallery → scene "1" → Versions… → Oct 9 "Before app update" → Restore).

**To check on the iPad** (`7cf3245`): colour-picker drags, the polygon lasso, a selection kept across
layers and frames, the padding veil, a
long effect-slider drag; and still from session 47: the graph-node drag, the Move box, the gap slider,
idle with a stream connected. Send the next `flight-…` file after a "Caught a canvas freeze" badge.

**Ruled to wait / carried**: (27) stage 5 (the owner at the laptop); (22), (10), (37) deprioritised; the
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
