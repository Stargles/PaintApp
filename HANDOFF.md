# Handoff

<!-- Current state and next step only. Rationale and raw evidence live outside this checkpoint. -->

Start at AGENTS.md, then CLAUDE.md, TODO.md, BUGS.md and the relevant specification. Verify origin
and tmp branches before trusting the checkpoint. Budget permits useful agents; prioritize usage
conservation and output quality over speed. The owner requested a clean checkpoint to park.

## Checkpoint — 2026-10-23

Liquify is complete. The owner confirmed real artwork “looks right” and manually deleted all gallery
test scenes. One-shot saved-file repairs are now retired completely in `tmp/s51-cleanup`, worktree
`~/PaintWork/PaintApp-s51-cleanup`. Strict current decoding and restore validation, update snapshots,
canvas recognizer repair and project-location migration remain. The read-only exporter now preserves
relative folders so same-named packages cannot overwrite exported copies; no product cleanup hook.
CLAUDE.md requires physical harnesses to record unique owned fixtures, Trash only those in teardown,
preserve owner settings/libraries and verify fresh inventory before closeout.

**New active report:** owner just experienced a crash while erasing strokes on the iPad, after the
final Release installation below. Owner identifies **Test1**, with **no Liquify used on those strokes**. Actual crashing build/cause
not established yet. Owner reports return to the iPad Home Screen (“the entire ipad crashed”). No
current named app crash/Jetsam report was found in root/Retired/synced Mac logs. Preserved Test1 was
saved with To Cross, Vector3/frame2,527strokes; no material operations in its six drawings. New task tree:
`~/PaintWork/PaintApp-s52-erase-crash`, tmp/s52-erase-crash from origindf459377. First collect newest
crash log/read-only diagnostics and correlate its executable UUID; preserve the scene/backups and
avoid app restart/reinstall or another unlock request until genuinely required. TODO records the
report before investigation. The prior cleanup qualification remains evidence, not proof against
this new crash.

**Previous cleanup checkpoint (complete).** Final normal Release **bcd7a6af** installed: clean/build0, all723 frozen
files exact, strict deep signature verified. Profile expires **2026-10-30T00:18:54Z** (October29
evening Toronto), over six days at install. First launch was refused solely because iPad locked;
after owner unlocked, normal launch with **no test arguments** succeeded, **PID53501 observed alive**.
No further device work remains. Owner is now asleep; no further iPad interaction is needed or queued.
The cleanup item is gone from TODO; all other work is deliberately deferred/owner-side.

Final app/build/signature/install/launch evidence: `~/PaintWork/s51-cleanup/final-release/`,
including `final-status.json`. Both task worktrees are being removed after final docs merge; native
jobs and owned simulators are already finished/deleted. Reuse the frozen-source qualification; do
not repeat tests or restart the iPad for this completed work.

## Completed gates

- Current device library: **256packages =10Projects+228Backups+18Trash**,3,180package files,
  567,855,190B. Exact index paths/per-package bytes; second device index identical. Temporary568MB
  app-container export cleared through index-only launch. No automated gallery deletion performed.
- Current production decoders audited every copied package:2,181cels,1,565vectors,95,350strokes,
  1,955fills,93streams; zero decode failures or pending repair conditions. There were no animation/
  interpolation sidecars in the real copy. Before/after3,182-file SHA inventory identical, including
  index/log; temporary audit removed byte-exact. Old AirDrop ZIP is historical, not current evidence.
- Final fast **Debug and Release each5,251 total =5,247passed+4skipped**, zero failures;254classes,
  exact static count. Full static census5,833. Four exporter cases are included in native tiers.
- Current restore/storage focused117/117 and25/25; four deliberate validation faults red, restored
  source green. Actual exporter source Mac XCTest4/4 baseline/restored, five faults red.
- Release UI **3/3**: GalleryRecoveryUITests2 and TransformKeysSurviveUITests1. All three kept
  keyframe/bake/cold-reopen pictures reviewed. Owner iPad9 landscape gallery2160×1620px reviewed;
  header, actions, scene tile/title/date fully visible. Orientation-only view retains native raw.
- UI identifier/helper lints85symbols/137helpers clean; PBX plutil clean,1,314unique definitions.
  All723 tracked source/resource/project files frozen for final build, no temporary audit hook.
- Full UI and physical gestures were not rerun for this cleanup. Prior Liquify/input/rendering
  qualification is unchanged: fast5282each; full Release5864 with3reds passing unchanged serially;
  native sampler1/1, five legacy workflows, Liquify2/2, all pictures reviewed. Full Debug not run.

Detailed retirement record: docs/bug-evidence/saved-file-repair-retirement-2026-10-23.md.
Raw current evidence: `~/PaintWork/s51-cleanup/{current-library,repair-qualification,export-qualification}/`.
Final device build, strict verification, installation and normal launch are complete.
Prior normal Release/app and evidence: `~/PaintWork/s50-liquify/final-release/`.

## Preserved data and deferred queue

Current exported library and file hashes are under `~/PaintWork/s51-cleanup/current-library/`.
Earlier owner AirDrop backup is under `~/PaintWork/s50-liquify/device-backup-2/external-library/`;
117 historical manifests, all3,830 archive members CRC/SHA/path checked. Container brush/palette
files stayed hash-identical through physical testing. Do not delete or broadly reset owner content.

TODO retains streaming27 stage5 (owner/laptop verification), multi-cel22 and linear-light10
(deprioritised), brush importers37 (dropped for now), audio28, video30 and the future interpolation
brief. No research on deferred features. The raster Move undo half and freeform-text minimum remain
explicitly carried, not active asks. Existing freeze investigation stays in BUGS: October16–18 logs
belong to pre-Liquify Releasef813346; owner noticed repair messages only, not a visible freeze. Keep
the recognizer repair; no speculative UIKit change. Renewal-script fix/evidence is in
`docs/bug-evidence/auto-resign-2026-10-22.md`.
