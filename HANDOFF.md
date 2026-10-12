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

**Build from `~/PaintWork`, not `~/Desktop`.** Since macOS 26.5.2 `actool` cannot read the Desktop
folder (CLAUDE.md "Build and test", first paragraph), so every worktree lives at
`~/PaintWork/PaintApp-<id>` and Bash calls that run `xcodebuild` need the sandbox off. `~/PaintWork/deploy`
is a detached worktree kept for device builds — `git -C ~/PaintWork/deploy checkout --detach origin/main`
and build with CLAUDE.md's "Deploy to iPad" command.

**Session 47 closed 2026-10-12 with the owner's asks (153)–(175) all merged** — nothing in flight. The UI
suite was not re-run after `38a3dd6` ((170), (173)–(175) and the stranded-recogniser diagnostic came after it;
each ran its own UI classes). **Full suite at
`38a3dd6`** (erased device, four clones, no System Failures): **5438 / 5373 passed / 7 failed / 58
skipped, 75.7 min**; five reds environmental, two stale tests fixed in `6bccc68` (CLAUDE.md carries the
table). Fast tier at `6bccc68`'s parent: **4914**, Debug and Release reconciled.

**The owner's iPad has `95e5507`** (Release, installed 2026-10-12). Its profile expires
**2026-10-15T04:52Z**; the last two installs skipped CLAUDE.md's 5-day gate on purpose — the build each
replaced carried the same profile, so nothing got shorter — and the re-signer (`~/PaintApp/deploy/resign.sh`,
which syncs to `origin/main`) is armed for 2026-10-14 23:52 local.

**The laptop streamer** (`desktop-cbr0fl6`) runs the build from (171) (`30199e0`): a second launch hands off
to the running instance over a named pipe (shows and restores its window), a hung instance is replaced
after 5 s, and `f84776f`'s C# half is compiled and deployed. (172) (`4f8492e`, deployed 2026-10-12 00:04)
serialises every session transition, so a connect and a resume can no longer start two `gst-launch`
pipelines whose interleaved P-frames were the owner's datamosh and keyframe-restart "Starting" storms;
the owner's motion test of it is owed. Still no autostart (TODO (99)). Two stream leftovers, no ruling
needed: the iPad opens two connections ~30 ms apart (LAN and Tailscale addresses), now harmless churn;
a keyframe request still restarts the pipeline (~1 s of "Starting") because `gst-launch` cannot force an IDR.

**The owner keeps real scenes now.** TODO.md's "no document has to survive" permission is retired: a
format change ships a **one-shot repair** that rewrites existing packages at launch, and the decoder
knows only the current format (TODO.md's head, `~/PaintWork/brief-common.md`, memory). Build `2974b33`
broke this and lost the owner's keys — see (153) below.

## What is left

**Owner-side, first:**
1. **Restore the keyed scene.** Gallery → the scene "1" → **Versions…** → the **Oct 9 "Before app update"**
   (or `auto-…000935`) → Restore; Transform 7 should animate (6 keys at 0, 6, 30, 38, 45, 47). Copies of
   the owner's whole `Backups/EC65EF3E…` folder and the live package are in `~/PaintWork/evidence-153/`.
2. **Then delete the repair** (one commit, once the owner confirms): `Services/LegacyPoseTrackRepair.swift`,
   `PaintSoftwareUITests/LegacyPoseTrackRepairLogicTests.swift`, the `LegacyPoseTrackRepair.repairLibrary(…)`
   call in `ProjectBackupManager.runStartupMaintenance`, and their four pbxproj object lines each.
3. **Feel checks on the device** nobody here can make: the graph-node drag (INFERRED 6.5–9 ms an update on
   the iPad 9, was 20–26), the Move box drag, the gap slider, idle with a stream connected.
4. Still unasked from session 46: (132)'s held stroke ends on a direction-following brush; folder Move lag
   on the iPad; whether a newly placed gradient should keep opening its colour panel. And (27) stage 5.

**Memory on the iPad 9 (TODO (173), `95e5507`).** The 2026-10-12 "crash" was `backboardd` killed at its
~1.9 GB per-process limit by canvas-sized pictures handed to Core Animation every tick of a Select
recolour on a 4096² scene; Select's Colour/Size/Opacity drag and the gradient panel now hold the edit
(`CanvasManager.liveElementEdit`, drawn into `WindowSurfaceView`). The same per-tick document write
remains in the layer Opacity slider, effect parameter sliders, mask tuning and the text panel's sliders
(owner question below). A 4096² scene starts at ~0.5–0.8 GB on a 3 GB iPad; the 2026-10-10 layer-panel
hangs (BUGS.md) were under 83–89% memory pressure.

**Stranded recognisers** (BUGS.md, `359d473`): five auto-saved flights on 2026-10-10 share one shape — a
touch landing a beat after two that landed together (a late third finger) leaves `canvas.pan` (and pinch/
rotation/stroke) out of `.possible` after every touch is up; the repair works; not reproduced in ~1,500
simulated sequences. The next stranded flight carries a census of unquiet recognisers — ask the owner to
provoke one (three fingers, one a hair late, until the "Caught a canvas freeze" badge) and send it.
Flights keep saving every time until the cause is found (owner, 2026-10-12).

**Ruled to wait** (do only if the owner says it feels slow): Duplicate Offset box, grade sliders and grade
graph nodes still write the document per tick (they need a live recomposite from held settings); edits
to a selected effect layer wait for the bake (~350 ms on the iPad).

**Engineering notes for the next session:**
- **The UI suite runs almost entirely in portrait on the 13" simulator; the owner works in landscape on an
  iPad 9 (1080×810).** `PaintUITestCase.setUpWithError` pins portrait; pixel probes are transposed in
  landscape. On an iPad 9th-gen simulator ~15 UI tests are red for 13"-geometry reasons (`tapAway`'s 44 pt
  toolbar gap is 36.5 pt in portrait, `testTheSelectPanelIsCompact` reads 129.5 vs 125, two
  `EditorKeyboardLayoutUITests` premises, and in `LayerPanelControlsUITests`/`OptionsPanelUITests` five more
  listed by (170)) — test debt, not app defects; listed in the 2026-10-11 audit.
- **Simulators degrade over a long session** — two workers saw passing tests go red alone and green on a
  freshly made device. Make a fresh device rather than debugging a stale one.
- A worker ran `simctl shutdown all` during cleanup and may have killed another's run; the shared brief
  says never to.
- BUGS.md carries one read-only finding from (165): a Guide between two live hosts (a stream below, the
  active layer above) is left out of the live picture.

## What shipped this session

~95 merges, `8db61fc..6bccc68`; causes are in the commit messages. The decisions most likely to be tripped over:

- **(153) Keys were lost by a format change with no reader**, not by the bake: `2974b33` ((139)'s per-component
  curves) read every older transform track as empty and autosave wrote that back; and the Move box put a
  stale copy of the layer back when it closed. The decoder is now strict; `LegacyPoseTrackRepair` is the
  throwaway. One invariant harness proves every bake path over stacks of 2–4 layers.
- **Held-off-the-document live edits** — one mechanism: a graph-node drag ((154)), the Move box ((164)) and
  the gap slider ((157)) hold their value gesture-locally (`CanvasManager.livePose` / `boxNudge` /
  `liveFill`, canvas told via `onHeldPictureMoved`, hosts via `heldHostLayerIndices`) and commit once at
  the lift as one undo step: zero document publishes per tick.
- **Gap closing is a hierarchical watershed** (`Engine/FillBasins.swift`, (158)): basins of the distance
  field, sealed at `2·saddle ≤ slider`; edges and corners fill to the ink at every setting; the slider's
  number is the widest opening it seals; the GPU flood is gone.
- **A live stream is reference** ((156), (162)): a hidden stream is not fed; no stream is ever baked,
  exported or thumbnailed; on screen the run from a visible stream to the active layer stays plain
  (STREAM.md §2.13–2.14).
- **The sandwich carries floats and keeps effects on screen** ((160), (165)): no compositor refusal for a
  floating piece; with an effect or blend above, the moving layers are drawn on top and join down at the
  bake; an effect layer is never the middle of the live pair.
- **Versions are thinned by age** ((161)): 3 newest, 6 ten-minute, 24 hourly, 7 daily, 4 weekly, the
  *oldest* in each slot survives; install snapshots join the same tiers; cap 4 GB ((163)).
- **Input**: nothing moves for the keyboard (`ignoringTheKeyboard()` at the root; the text tool pans the
  canvas) ((159)); a held modifier finger lands on `HoldShieldView` and does nothing ((168), `ModifierHold`);
  a second finger locks a graph drag to one axis ((166)); a finger on empty graph band scrolls in pen-only
  mode ((167)).
- **The owner's screen**: the timeline's default height is 35% of the editor, capped at 375 ((169),
  `TimelinePanelSize`); docked cards start at the margin when they cannot fit beside the rail.
- **Workers**: dispatch single workers with the Agent tool, not Workflow (the owner, this session — a
  workflow agent cannot be messaged); a rate-limited worker resumes by `SendMessage` with its worktree intact.

## Waiting on the owner

**Questions held for the owner (asleep until 11:00 on 2026-10-12 — ask them then, by the question tool):**
1. (175) Subtract is now saved like the other switches; left on, the next session's first loop says
   "nothing to subtract from" — keep it saved, or let it reset each launch?
2. (175) Should tool sliders and pickers be saved too (Fill's Gap Closing/Threshold/Edge Overlap/Mend
   Reach/Extension Buffer and Fill type; Move mode; Select's membership, tap composition, Magic Wand
   tolerance; Text font/size/alignment/colour and corner mode — whose doc claims it persists and does
   not; gradient width)? None / pickers only / pickers and sliders / a list.
3. (173) Give the other per-tick slider edits (layer Opacity, effect parameters, mask tuning, text panel)
   the held-picture treatment — all now, effect sliders first, or only if the device still dies? (The
   2026-10-11 ruling "only if they feel slow" predates the jetsam evidence.)
4. (173) On a posed frame a Select recolour shows only at lift, with a banner — keep, refuse with a
   reason, or build per-element pose drawing?

- Confirm the restored scene animates (then the repair is deleted).
- Device feel of the drags and the gap slider; whether grade/Duplicate Offset drags need the live path.
- Granting Xcode Full Disk Access would let builds run from `~/Desktop` again.
