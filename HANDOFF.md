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

**Final device build/install remains:** all qualification and screenshot review complete. Root owns
native work; both owned simulators are deleted, no adapter was injected. Merge by absolute-main-path
ff-only, push, then clean/build normal Release, verify all723 frozen files/signature/five-day profile
life, install and launch with no test arguments. The iPad currently runs intermediate audit788f576
(outgoing repairs retained plus export fixes), reopened normally after read-only copying; it is not
yet the retirement build. Profile expires2026-10-30T00:18:54Z. Prepared final scripts/evidence are under
`~/PaintWork/s51-cleanup/final-release/`.

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
Final device build scripts are prepared in `~/PaintWork/s51-cleanup/final-release/` but not run yet.
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
