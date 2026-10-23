# Handoff

Start at AGENTS.md, then CLAUDE.md, TODO.md, BUGS.md and the relevant specification. Verify origin
and every tmp branch before trusting this checkpoint. Kevin permits useful agents; conserve usage,
prioritize quality over speed, delegate substantive work, and continue without recommendation-only
pauses. Clean architecture is the first priority. Give occasional concise queue updates.

## Active session — 2026-10-23 evening

Main contains records/rulings only for the three new tasks. **No new feature fix is merged, installed
or fully qualified yet.** Previous installed normal Release is bcd7a6af, executable UUID
F6102F9A-6D31-3185-B078-47B4C41981D9. Do not reuse prior green counts as proof of current changes.
Preserve current iPad artwork; no physical device launch, restart or install occurred in this pass.

1. **Point-only vector Liquify cleanup.** Kevin explicitly requires moving stroke points through
   the ordinary brush renderer, preserving brush properties. Remove complex native vector pixel
   transport completely; no extra mode or flag. Original brief confirms this. Working implementation
   removes three material modules and their renderer/hit/eraser/archive dependencies, keeps genuine
   Distort/exact-bake placement, raster inverse Liquify, linked captures/recipes and existing edit/undo
   lifecycle. Preview uses one memoized procedure, LatestWins and complete ordinary painted bounds;
   bounds stream into one rectangle. New normal-render/ancestry/queue/budget tests are committed.
   Independent source review found no concrete runtime architecture defect; native qualification
   remains outstanding. Consumer inventories/audit: `~/PaintWork/s52-vector-points/`.
2. **Smart saving.** Existing3/6/24/7/4 age schedule, pre-save copies and4GB logical cap are real.
   Actual mismatch was oldest per bucket versus original TODO161's newest. Kevin now explicitly says
   implement the usual policy; Borg/Restic use newest. Correction4079a1c2 is in the combined branch.
   Actual VersionRetentionLogicTests ran as standalone Mac XCTest:14/14; reverse-loop fault8/14 red;
   restored exact source14/14. App backup-manager tests and integrated tiers still pending. Week of
   real-scene APFS storage cost is **unverified**; preserved library inventory is only a logical-byte
   inventory, not physical shared-block measurement. Bounded Session47–51 audit found no other
   concrete dropped actionable ask. Evidence `~/PaintWork/s52-saving-audit/`.
3. **Test1 erasing failure.** No Liquify used; black screen/loading spinner then Home Screen.
   App-vs-system cause unresolved. Two read-only listings found the same40ips records with no matching
   app/SpringBoard/Jetsam/panic report; privileged unified-log collection requires a password and was
   not obtained. Preserved pre-failure Test1 has4096²,527strokes on Vector3/frame2, To Cross size7.962,
   no material data. Old-code Debug iPad9 simulator diagnostics2/2: cold gallery open/four real erase
   drags/Undo plus107 isolated cuts and107 continuous sites with repeated4096px renders. All isolated
   cuts executed; zero crash. Six pictures inspected; Undo showed “Undid erase”. Screenshot orientation
   metadata inconsistent, so no landscape-layout qualification claimed. Temporary test source restored
   byte-exact and owned simulator deleted. This is **not a fix or device-memory proof**. Evidence:
   `~/PaintWork/s52-erase-crash/`, especially test1-diagnostic-status.json.

## Combined branch and current work

- Lead/root combined tree `~/PaintWork/PaintApp-s52-vector-points`, branch tmp/s52-vector-points,
  currently b7b1ae36 (saving + vector cleanup + initial repair). Read-only pending repair follow-ups.
- Active native/build/repair tree `~/PaintWork/PaintApp-s52-vector-repair`, branch tmp/s52-vector-repair,
  includes follow-ups through4e3d2ad5. Agent retire_file_repairs owns native; simulator
  88DFDBE7-FE41-4533-9E22-E077D56C9A14, serial simlock, DD
  `~/PaintWork/s52-vector-points/integration/DerivedData`. Focused repair build/test is in progress;
  no Debug/Release fast tier yet. Coordinate before any other compiler/simulator job.
- Saving tree `~/PaintWork/PaintApp-s52-saving-fix`, tmp/s52-saving-fix, clean4079a1c2.
- Old writer tree `~/PaintWork/PaintApp-s52-format-baseline`, clean1c5c422e. Actual old production
  writer produced/reopened six tiny packages and six roundtrips; focused producer1/1, all723 tracked
  source/resource/PBX files restored exactly. Evidence under s52-vector-points/baseline/.
- Root records/diagnostics tree `~/PaintWork/PaintApp-s52-erase-crash`, tmp/s52-erase-crash.

**Temporary saved-format repair is not ready.** Current vector/recipe codecs require geometryVersion1
and no material fields. Converter stages/validates packages, protects original update copies, converts
all Projects/Backups/Trash plus newly made snapshots, atomically exchanges paths, rolls back on failure,
then advances signature/prunes. No old decoder in normal models. Actual previous-writer fixture resource
includes six packages; ordinary pixel oracles use the previous reader's reopened Distort/bake thumbnails,
not pre-save in-memory thumbnails (old quantization changes even plain ink). Gesture brushes are full
Brush values; ordinary stroke brushes are package references. Do not invent a remap for full gestures.

Independent review caught three repair defects now assigned for correction:
- Tolerant package census follows parent-folder symlinks/loops, permitting conversion outside root.
- It swallows folder-listing errors, permitting hidden unconverted backups and early signature/prune.
- Parsing damaged current JSON before startup maintenance can block existing valid-backup recovery.
Use a strict census and a clean package-format boundary to preserve current recovery; no compatibility
flags, silent defaults or special corrupted-filename exemptions. Root/lead are reviewing the design.
Two compile-only issues were fixed (extra assumeIsolated call parentheses, duplicate MainActor attrs).
Native tests have not established the new implementation is green yet. Root owns PBX edits, done for
StrokePlacement, repair service/test and fixture; re-check unique ids after integration.

Next: finish safety fixes/review; focused baseline + committed-source mutation proof; real preserved
library conversion on a copy; exact fast tiers Debug/Release with static reconciliation/lints; cold UI
Liquify/raster/linked and affected old workflows, screenshots inspected at iPad9 landscape too. Before
physical install, obtain a **fresh** current library export (preserved copy predates later Liquify),
verify every file before changing device state, run required legacy workflows, signed clean Release,
normal no-argument launch. One-shot repair retires only after Kevin confirms real artwork.

## Previous completed work and preserved data

Prior cleanup retired six older saved-file repair services and fixed read-only ProjectExport to preserve
relative folders. Main df459377/installedbcd7a6af; details in
`docs/bug-evidence/saved-file-repair-retirement-2026-10-23.md`. Historical fast Debug/Release each5251
(5247passed+4skipped), focused UI3/3 and current library256packages strictly audited. These gates predate
current code. Prior device build/profile expires2026-10-30T00:18:54Z (October29 evening Toronto).

Preserved library `~/PaintWork/s51-cleanup/current-library/Export/`:10Projects+228Backups+18Trash,
567855190logical bytes. Owner manually deleted test scenes; no automated gallery deletion is needed.
Do not delete these recovery copies. Earlier AirDrop ZIP is historical under
`~/PaintWork/s50-liquify/device-backup-2/external-library/`. Device chosen root is File Provider storage;
Tailscale reachability alone does not expose it. ProjectExport is read-only and requires a saved-scene
restart before device use; copy its Export via app-container devicectl, verify, then clear temporary export.

Deferred TODO stays streaming27stage5 (owner/laptop), multi-cel22, linear-light10, dropped brush importers37,
audio28, video30 and future interpolation brief. Raster Move undo/freeform-text minimum remain deliberately
carried. No research on later features. Freeze logs October16–18 match pre-Liquify f813346; owner saw repair
messages only. Keep recognizer repair; no speculative UIKit fix. Renewal fix:
`docs/bug-evidence/auto-resign-2026-10-22.md`.
