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
   Independent source review found no concrete runtime architecture defect. Repair safety gates are
   green; integrated runtime, fast tiers and UI remain unqualified. The cut first-save failure is a
   proven ordinary Float32 fixture premise; its test correction is pending, not a production codec
   change. Evidence: `~/PaintWork/s52-vector-points/`.
2. **Smart saving.** Existing3/6/24/7/4 age schedule, pre-save copies and4GB logical cap are real.
   Actual mismatch was oldest per bucket versus original TODO161's newest. Kevin now explicitly says
   implement the usual policy; Borg/Restic use newest. Correction4079a1c2 is in the combined branch.
   Actual VersionRetentionLogicTests ran as standalone Mac XCTest:14/14; reverse-loop fault8/14 red;
   restored exact source14/14. BackupManagerLogicTests21/21 also passed in the repair gate; integrated
   tiers remain pending. Week-of-real-scene APFS storage cost is **unverified**; preserved library inventory is only a logical-byte
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
   initial eraser review generalized the replacement-preview path. Root corrected it: preserved
   ToCross is Mode3, with no scratch preview; cuts per sample refresh the canvas base. Investigate
   repeated canvas-sized UIImage/CoreAnimation handoff first (known respring cause in other features).
   Still a hypothesis. WindowSurfaceView/UnlandedInk are unchanged from shipped source; UnlandedInk
   image counters concern other eraser modes. See diagnostics
   flight-recordings-review.md and ordinary-eraser-source-audit.md. No speculative fix was made.
   Owner says this was today's only crash and cannot recall its time;18:47 is now the probable
   matching event, not a confirmed timestamp. Display-service allocation origin still unresolved.

## Combined branch and current work

- Active integrated tree `~/PaintWork/PaintApp-s52-vector-repair`, tmp/s52-vector-repair,
  code through **c04d2b87** before the next docs-only rebase. Two obsolete parallel-array decoder
  tests removedd678e65d; exact ordinary-codec cut reference correctedd2d4c1d0; unused recipe snapshot
  size removedc04d2b87 after independent final architecture review. Working tree clean. Lead
  vector-points tree is behind; root owns bringing refs together. No source change merged to main.
- **Root owns the sole native slot.** Old round-dot UI control3 finished with a setup failure:
  panels closed correctly, but stationary dot was not detected before reaching Liquify. Agent
  erase_crash_trace is inspecting its capture/source offline; do not loosen its shape assertions.
  Controls1/2 also failed setup and prove nothing about stretching. Owned iPad9 simulator
  **B0533278-3F74-4944-AC58-3514D87C85D6**; primary integrated simulator
  **39E84984-3C6F-4A6A-8DC8-D1098F6B623E** is shut down. Next native is corrected302-runtime
  baseline on39, followed by11mutants and fast tiers. DD:
  `~/PaintWork/s52-vector-points/integration/DerivedData`. No physical device operation.
- Saving tree `~/PaintWork/PaintApp-s52-saving-fix`, tmp/s52-saving-fix, clean 4079a1c2.
  Root records tree is `~/PaintWork/PaintApp-s52-erase-crash`; root owns the pending TODO edit.
- Old writer tree `~/PaintWork/PaintApp-s52-format-baseline`,1c5c422e, preserves shipped production
  source. Temporary old round-dot UI test remains under repair; restore its source byte-exact when
  controls finish. Actual old ProjectStore writer produced/reopened six tiny packages and six
  roundtrips (producer 1/1); all 723 tracked files were restored after fixture capture. Evidence:
  `s52-vector-points/baseline/` and `round-dot-old-control/`. Do not overwrite this baseline.

**Saved-format repair safety gate is qualified; the whole feature is not.** On committed c4d09f03
(before equivalent integration/rebase), 35 repair + 21 backup + 19 location methods passed **75/75**, both
before and after **13 intentional repair mutants, all assertion-red** (16 failed method executions,
no compiler/crash substitution). Every mutant was restored byte-exact. Actual previous-writer fixture
packages cover material strokes/fills, linked recipe/local edits/imported brush, plain ink, genuine
Distort and retained exact bake. Ordinary Distort/bake pixel oracles are the old reader's reopened
pictures; removed material stretching claims geometry/brush preservation, not old pixel parity.

The real-library gate ran on a temporary clone only: 256 input packages/3180 files/567855190bytes,
**266 conversions including 10 untouched protection snapshots**. Normal dated retention removed 24
inventoried backup packages; all **242 survivors (10 Projects / 214 Backups / 18 Trash)** passed current
normal/restore validation and actual ProjectStore.load (2034 cels / 1459 clean vector decodes). No
failures or stale stages; second run 0 and byte-exact idempotent. Original 3180 frozen file hashes
remained unchanged. All 722 tracked app/test/project files matched the pre/post temporary-audit freeze;
test injection removed exactly and M5 simulator 88DF deleted. This preserved export has no recipes
or animation sidecars; previous-writer fixtures cover recipes. Evidence summary:
`~/PaintWork/s52-vector-points/repair-qualification/README.md`; native results `restored-75.xcresult`
and `real-library.xcresult`, `fault-summary.json`, `real-library-report.json`, and full freeze JSONs.
Do not print the large real-library report wholesale.

Current manifest/vector/recipe codecs require geometryVersion 1. The one-shot converter enumerates
all Projects/Backups/Trash strictly, protects untouched update copies, converts newly made snapshots,
and validates staged packages before atomic exchanges. Directory-identity owner records preserve
copies on errors; both sides and current validity are rechecked before swaps/cleanup. Cleanup precedes
signature/retention. No old decoder/default/compatibility flag. Ambiguous unreadable manifests remain
intact for existing backup recovery; same-basename fallback requires exactly one backup ID. Gesture
brushes are full Brush values; ordinary stroke brushes use package references. Keep this temporary
repair until Kevin confirms real current artwork, then retire it whole.

**Latest integrated runtime result is red:** beddbf48 Debug ran 304 methods, **301 passed/3 failed**
(`runtime-qualification/focused-Debug-2.xcresult`). Two failures were the obsolete parallel-array codec
tests now removed in d678; no new complete runtime run is green yet. The new liquified-cut test agrees
with ordinary ink before save but fails first-save pixels. The raw versus Float32
sample/lattice codec premise was checked. **Control4 passed 1/1:** ordinary raw-to-Float32 first save changes
22 pixels (maximum byte difference 2), while independent precise-codec persistence differs by 0.
This proves the ordinary first-save premise was wrong; no production codec defect is established.
Correctiond2d4c1d0 keeps exact independently encoded ordinary geometry/picture assertions and removes
transient diagnostic counters; no production codec or behavior-tolerance change. Rerun the integrated gate.

**Runtime 11 mutants have NOT run.** The external driver is ready under
`s52-vector-points/runtime-fault-driver/`: explicit committed SHA/green count, exactly-once edit
checks, full source/test/PBX freeze and restoration, exact selected native assertion-red required;
compiler/crash/unexpected-green stops without qualification. After source fixes and a fully green
focused run, refresh its reviewed recipes/preparation for the final SHA, run with root's native grant,
then rebuild normal committed source before UI or install. Earlier dry-run metadata is not proof.

**Round-dot UI is NOT qualified.** Old-complex controls 1/2 both failed setup, not the intended brush
shape assertion: first no visibly painted dot, then brush library did not close. Old UI control 3 is
now running the corrected toolbar panel toggle/library dismissal; no behavior tolerances changed. Current
cold-start test requires visible Push movement, unchanged round footprint and an uncropped measurement
patch. No old/current appearance A/B or owner-size round-dot proof yet; inspect both at iPad9 landscape.

Next: commit the cut fixture correction and restore temporary methods exactly; rerun all focused
runtime classes with the reconciled new count; run 11 runtime faults;
then exact CLAUDE fast tiers **Debug and Release**, static counts/lints/PBX, touched cold UI classes and
old workflows, and inspected iPad9 landscape screenshots. **Fast tiers and UI are not qualified.**
No physical activity this turn. Before physical install, obtain/verify a **fresh** current library
export (the preserved export predates later Liquify), drive required old workflows, signed clean
Release, then normal no-argument launch. Keep the owner’s current scenes untouched meanwhile.

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
