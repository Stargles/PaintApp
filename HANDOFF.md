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
   Root cause unresolved. Third read-only listing at19:22 found a new18:47EDT Jetsam report:
   backboardd reached its per-process limit at1850MiB. Active PaintSoftware730.4MiB/922.6MiB peak,
   UUID matches installedbcd7a6af, no PaintSoftware kill reason. This supports investigating system
   display memory, but reported-event timing and allocation origin are unproved. No physical app
   launch/restart/install. Earlier two listings had40ips and no matching report. Privileged unified
   logging requires a password and was not obtained. Preserved pre-failure Test1 has4096²,
   527strokes on Vector3/frame2, To Cross size7.962,
   no material data. Old-code Debug iPad9 simulator diagnostics2/2: cold gallery open/four real erase
   drags/Undo plus107 isolated cuts and107 continuous sites with repeated4096px renders. All isolated
   cuts executed; zero crash. Six pictures inspected; Undo showed “Undid erase”. Screenshot orientation
   metadata inconsistent, so no landscape-layout qualification claimed. Temporary test source restored
   byte-exact and owned simulator deleted. This is **not a fix or device-memory proof**. Evidence:
   `~/PaintWork/s52-erase-crash/`, especially test1-diagnostic-status.json.
   Two newly copied Test1 flights181634/181822 end27–30min before the Jetsam; recognizer repairs,
   no erase-completion/memory telemetry or causal link. Selecting Liquify is not applying it. Bounded
   ordinary-eraser source review found no concrete ownership defect; WindowSurfaceView/UnlandedInk
   unchanged from shipped source. Next physical reproduction should temporarily count retained
   UnlandedInk UIImage bytes/versions at lift/base landing, not merely IOSurfaces. See diagnostics
   flight-recordings-review.md and ordinary-eraser-source-audit.md. No speculative fix was made.
   Owner says this was today's only crash and cannot recall its time;18:47 is now the probable
   matching event, not a confirmed timestamp. Display-service allocation origin still unresolved.

## Combined branch and current work

- Lead/root combined tree `~/PaintWork/PaintApp-s52-vector-points`, branch tmp/s52-vector-points,
  currently60479341 (saving + vector cleanup + initial repair + round-dot UI regression). Its two
  UI-only commits must be rebased onto the completed repair branch before combined qualification.
- Active native/build/repair tree `~/PaintWork/PaintApp-s52-vector-repair`, branch tmp/s52-vector-repair,
  includes follow-ups throughb56900d2. Agent retire_file_repairs owns native; simulator
  88DFDBE7-FE41-4533-9E22-E077D56C9A14, serial simlock, DD
  `~/PaintWork/s52-vector-points/integration/DerivedData`. Focused repair/backup build is in progress;
  no Debug/Release fast tier yet. Coordinate before any other compiler/simulator job.
- Saving tree `~/PaintWork/PaintApp-s52-saving-fix`, tmp/s52-saving-fix, clean4079a1c2.
- Old writer tree `~/PaintWork/PaintApp-s52-format-baseline`, clean1c5c422e. Actual old production
  writer produced/reopened six tiny packages and six roundtrips; focused producer1/1, all723 tracked
  source/resource/PBX files restored exactly. Evidence under s52-vector-points/baseline/.
- Root records/diagnostics tree `~/PaintWork/PaintApp-s52-erase-crash`, tmp/s52-erase-crash.

**Temporary saved-format repair is not qualified.** Current manifest/vector/recipe codecs require
geometryVersion1 and no material fields. Converter strictly enumerates all Projects/Backups/Trash,
protects original update copies and stages/validates packages before atomic exchanges. Sibling owner
records pair source/stage directory identities; errors preserve both sides for restart. Before swaps
and destructive cleanup, recheck both identities, owner records and current strict package validation.
Cleanup precedes signature/pruning, since retention can remove backup addresses. No normal decoder
reads the old format. Actual previous-writer fixture resource
includes six packages; ordinary pixel oracles use the previous reader's reopened Distort/bake thumbnails,
not pre-save in-memory thumbnails (old quantization changes even plain ink). Gesture brushes are full
Brush values; ordinary stroke brushes are package references. Do not invent a remap for full gestures.

Independent review caught unsafe census, recovery and error-cleanup paths. Working corrections now
reject folder/package links, propagate listing failures and preserve ambiguous unreadable manifests
unchanged for existing recovery. Convert other known-old backups first; current valid backup restores,
no-backup remains a damaged gallery tile. Same-basename recovery now requires exactly one match.
No compatibility flag or special corrupted-filename exemption. Independent review ofb56900d2 pending.
The prior native focused batch executed20 repair methods:19 passed; one failed six unrelated manifest
number comparisons. Validate then insert the new marker into original manifest bytes, preserving
unrelated wire values; exact assertions retained. Final focused batch now selects33 repair methods plus
backup/location classes. Native baseline and committed-source mutations are still outstanding. Root
owns PBX edits, done for StrokePlacement, repair service/test and fixture; re-check ids after integration.

New round-dot cold UI regression60479341 taps one wide ordinary round dab, Pushes it sideways, then
requires visible movement with unchanged round diameter/coverage and full uncropped measurement bounds.
Not run yet. Runtime mutation/selectors plan: `~/PaintWork/s52-vector-points/runtime-qualification-plan.md`.

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
