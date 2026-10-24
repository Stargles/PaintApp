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

1. **Point-only vector Liquify cleanup.** The combined implementation removes native vector pixel
   transport and moves stroke points through the ordinary brush renderer, preserving brush properties.
   Genuine Distort/exact-bake placement, raster inverse Liquify, linked recipes, edit/undo, LatestWins
   and bounded preview ownership remain. Independent source review found no concrete runtime
   architecture defect. Repair 75/75 and corrected runtime 302/302 are green; combined 303, runtime
   faults, fast tiers and current UI are still pending. Evidence: `~/PaintWork/s52-vector-points/`.
2. **Smart saving.** The correction keeps the newest backup in each clock bucket, retaining the
   3/6/24/7/4 schedule, pre-save copies, install protection and4GB logical cap. Standalone retention
   14/14, reverse-loop mutation 8/14 assertion-red and restored14/14; integrated retention 14 and backup 21
   also passed within runtime 302. Week-of-real-scene APFS storage cost remains unverified; logical
   inventory does not measure shared physical blocks. The bounded Session47–51 audit found no other
   concrete dropped actionable ask. Evidence: `~/PaintWork/s52-saving-audit/`.
3. **Test1 erasing failure.** Root cause remains unresolved. Kevin used no Liquify and saw a black
   screen/loading spinner before Home Screen. The probable matching 18:47EDT Jetsam names backboardd
   at its1850MiB limit; active PaintSoftware was730.4MiB/922.6MiB peak, with the installed bcd7a6af
   executable UUID and no app kill reason. Kevin says this was today's only crash but cannot recall
   its time. Display-service allocation origin is unproved; no speculative fix or physical operation.
   Preserved Test1 is 4096² with 527 strokes on Vector3/frame2, no material data, and To Cross selected.
   **Raw eraser size 7.962 is canvas points, not 7.96% or 326px.** To Cross is Mode3: cuts per sample
   update the canvas base without a scratch preview. Repeated full-image handoff is the current
   hypothesis. Mode3 capture 1 passed 1/1 with 3 successful cuts and 3 full 4096 RGBA image assignments,
   footprint 854–985 MiB; root inspected 2 pictures. This is simulator evidence, not backboardd proof.
   Capture 2 mapped 527 source points and selected 20, but stopped before gestures at an added
   RGB-below-100 pixel premise; it adds no crash evidence. Renewal is diagnosing that premise.
   Earlier old-code stress diagnostics also did not crash. Flights ending27–30minutes before Jetsam
   establish no causal link. All 3 temporary root source files are restored hash-exact. Evidence:
   `~/PaintWork/s52-erase-crash/mode3-diagnostic/` and `device-diagnostics/`.

## Combined branch and current work

- Active integrated tree `~/PaintWork/PaintApp-s52-vector-repair`, tmp/s52-vector-repair,
  clean **25fb7618**. App production source is unchanged from b70d3065; later commits correct UI
  screenshot orientation, slider-axis setup and the field-edge round-dot probe. No new code is merged.
  Root records tree is `~/PaintWork/PaintApp-s52-erase-crash`.
- **Root owns the sole native slot.** Current iPad9 UI run is session 21395 on
  **56CC563F-06D0-42FC-9C18-A2B230DE2D38** at 25fb7618: LiquifyUITests 4 + LiquifyRasterUITests 5, results pending. Primary simulator
  **39E84984-3C6F-4A6A-8DC8-D1098F6B623E** is shut down. Old-control iPad9 is
  **B0533278-3F74-4944-AC58-3514D87C85D6**. Integration DD:
  `~/PaintWork/s52-vector-points/integration/DerivedData`. No physical operation this turn.
- Old writer tree `~/PaintWork/PaintApp-s52-format-baseline`,1c5c422e, preserves shipped production
  source. Actual old ProjectStore writer produced/reopened six tiny packages and six roundtrips
  (producer 1/1); all 723 tracked files restored after capture. Latest old UI control also restored both
  temporary UI/helper files: all 720 tracked hashes, including 329 production/PBX files, match and git
  is clean. Evidence: `s52-vector-points/baseline/` and `round-dot-old-control/`. Preserve this baseline.

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

**Corrected runtime baseline is green:** b70d3065 Debug **302/302**, zero failures/skips, across
11 classes. Full 722-file source/test/PBX freeze matched before/after and git remained clean. Two obsolete
parallel-array codec tests are removed. The cut first-save oracle now compares independent ordinary
Float32 encoding exactly; control proved the earlier raw-to-first-save pixel premise wrong, without
changing production precision or adding pixel tolerance. Evidence:
`runtime-qualification/focused-Debug-final-b70d3065.xcresult` and `b70d3065-native-boundary.md`.

The new ScreenshotPixelsLogicTests separately passed **1/1** at a628a6ad, covering all 8 image orientations
and screen scale. Shared screenshot reading now follows displayed orientation; UI slider setup uses
the actual horizontal/vertical control axis. **Combined focused count 303 has not run.** Static counts
are **fast 5259 / full 5842**, PBX **1316 unique objects**; these counts are not native qualification.

**Runtime 13 mutants have NOT run.** The reviewed external driver/plan under
`s52-vector-points/runtime-fault-driver/` includes orientation and scale faults. It requires a clean
committed SHA, green baseline, exactly-once edits, full source/test/PBX restoration and actual selected
native assertion-red; compiler/crash/unexpected-green stops without qualification. Refresh preparation
against the final committed baseline, run under root's native grant, then rebuild normal source before
UI or install. Static validation is not mutation proof.

**Round-dot appearance:** old controls 1–7 failed setup; control 8 passed 1/1 but placed the whole circle
inside a uniform field, so it did not discriminate stretching. Control 9 crossed the field edge and
produced the intended width assertion-red: width 0.2000→0.3797468354 (**1.899×**); setup, movement and crop
assertions passed. Root inspected both pictures and saw the elongated tail. Old source is restored
exactly. Current Liquify 4 + Raster 5 is running; no success count or current appearance qualification yet.

Next: finish current UI and inspect owner-size landscape captures; run combined 303 and all 13 runtime
faults, restore exact source and rebuild normally; then exact CLAUDE fast tiers **Debug and Release**,
reconcile 5259 including skips, lints/PBX, touched UI classes and required old workflows. **Fast tiers
are NOT run; the feature is not complete.** Before physical install, obtain/verify a **fresh** current
library export (the preserved export predates later Liquify), drive required old workflows, build signed
clean Release and launch normally without arguments. Preserve the owner’s current scenes meanwhile.

## Previous completed work and preserved data

Prior cleanup retired six older saved-file repair services and fixed read-only ProjectExport to preserve
relative folders. Main df459377/installed bcd7a6af; details in
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
