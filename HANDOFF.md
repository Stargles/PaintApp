# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. Write it for any agent: the next session may not be Claude Code. -->

**Start here:** read [AGENTS.md](AGENTS.md) (the owner, the standing rules, the bar for done), then this
file, then [CLAUDE.md](CLAUDE.md) (build, test, merge, deploy), then the specification for whatever you
pick up. [TODO.md](TODO.md) is the owner's asks **in queue order — the top is next**; [BUGS.md](BUGS.md)
is what we find.

## State (session 48, 2026-10-13)

**Check `git worktree list` and every `tmp/*` branch first** (`git log --oneline origin/main..<branch>`)
— `origin/main` is a shared ref and a cut-off session's work sits on its branch.

**In flight when this was written:** TODO (179) part 3 on `tmp/throttle179c` (worktree
`~/PaintWork/PaintApp-throttle179c`): the assessment's commits 8–10 (smart-shape preview off the main
thread, text panel and text/float drags held, interpolation previews, the fill fold onto `LatestWins`),
the brush colour's own publisher, and graph drags of Opacity / transform / animation-group curves held.
If that branch is ahead of `main` and its worktree is idle, finish it from there; the brief is
`~/PaintWork/design/s48-179-throttle-assessment.md` §5 plus (179)'s open boxes.

**Build from `~/PaintWork`, not `~/Desktop`** (CLAUDE.md "Build and test", first paragraph).
`~/PaintWork/deploy` is a detached worktree kept for device builds.

**The owner's iPad has `7cf3245`** (Release, installed 2026-10-13 after an iPad-9-simulator regression
pass of 210 UI tests — every red was the known 13"-geometry debt or environmental). Its profile expires
**2026-10-15T04:52Z**; the re-signer (`~/PaintApp/deploy/resign.sh`, syncs to `origin/main`) is armed for
2026-10-14 23:52 local. **The next install runs `LegacyToolSettingsRepair` on the owner's scenes** (TODO
(176)'s one-shot repair, below) — say so to the owner when it lands.

**Fast tier at `786efac`**: 5049 passed / 4 skipped, Debug and Release reconciled. The full UI suite has not
been run since `38a3dd6` (session 47); every item since ran its own UI classes.

## What is next

1. **Finish TODO (179)** (above), then the owner's iPad `PlaybackProbe` run it still owes.
2. **TODO (177)** — a stream layer drawn in place: one more consumer of (179)'s seam (a windowed
   recomposite of the layers above the stream per stream tick). Survey:
   `~/PaintWork/design/s48-survey-masks-stream-liquify.md` §B.
3. **TODO (35)** — the colour mask on the ticked layers, mask tuning per mask, and mask tuning's live
   preview (the assessment's commit 7, moved here). Survey §A.
4. **TODO (178)** — liquify (raster + vector, Push / Pinch-Expand / Twirl, active layer, selection limits
   it), on (176)'s `ToolProfiles` as a third tool. Survey §C.

## What shipped this session (48)

`f368504..2fd79ac`; causes are in the commit messages. The decisions most likely to be tripped over:

- **(179) One seam for every live re-update** — `LatestWins` (newest request wins, one job in flight, the
  landing on main before the next mint; proven by an interleaving rig in `LatestWinsLogicTests`), one held
  slot `CanvasManager.liveEdit`, and lane F: a whole-frame composite from the held value via
  `makeFrameRecipe(holding:)` into `WindowSurfaceView`'s surface pair, held until the bake lands. Effect
  parameters, the whole-effect editors, the Adjust Box, effect-channel graph drags, layer/folder Opacity,
  value colour and Rotate/Shake/Parallax all write once at the lift. **Above ~4 MP a drag preview is half
  detail** (`DragPreviewDetail`; the owner's drag-only exception beside RENDER.md §2.12). PERFORMANCE §30.
- **(183) A window surface is not drawn while the render server still shows it**
  (`WindowSurfaceView.present` waits on `IOSurface.isInUse`); the colour picker no longer rebuilds per
  tick (`PickerColor`, PERFORMANCE §31). The owner's on-device confirmation of the flicker is owed.
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

**Questions to ask (plain language, with options):**
1. (176) Subtract, Paint Outside Selection, Keep Stroke Width and Keep Full Precision reset whenever a
   scene is **opened**, not only on relaunch — keep that, or keep them across scenes until the app quits?
2. (179) On big scenes the half-detail preview leaves **Fog Glow** up to twice as wide mid-drag (its Size
   cannot go below 2) — leave it, scale it anyway, or never use half detail when a scene has Fog Glow?
3. Once the next build has repaired his scenes and they look right: delete `LegacyToolSettingsRepair`
   (and `LegacyPoseTrackRepair`, if the keyed scene from session 47 was restored and animates — still
   unconfirmed: Gallery → scene "1" → Versions… → Oct 9 "Before app update" → Restore).

**To check on the iPad** (`7cf3245`): the selection-colour flicker (lasso, Fill, Edit, drag the colour),
colour-picker drags, the polygon lasso, a selection kept across layers and frames, the padding veil, a
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
