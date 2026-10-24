# Handoff

Start at AGENTS.md, then CLAUDE.md, TODO.md, BUGS.md and the relevant spec/PERFORMANCE.md. Verify origin,
worktrees and every tmp branch before trusting this file. Kevin authorizes useful agents and a large
budget, with quality/usage conservation before speed. Continue actionable work without recommendation-
only pauses; give concise queue reports. The owner explicitly says not to park for context; automatic
compaction must preserve continuing work. Architecture is the top priority. Record before acting.

## Authoritative checkpoint — 2026-10-24 morning

**Nothing new is merged, pushed, installed or physically device-qualified.** Main/origin is afd2030c.
Installed normal Release remains bcd7a6af, UUID F6102F9A-6D31-3185-B078-47B4C41981D9, provisioning expires
2026-10-30T00:18:54Z. Current iPad artwork must be preserved; no device restart/launch/install this pass.

- Integrated point/saving tree: `~/PaintWork/PaintApp-s52-vector-repair`, tmp/s52-vector-repair,
  clean65b39e01. Qualified production is unchanged from6656a5a8; latest corrections were two stale tests.
- Active fill tree: `~/PaintWork/PaintApp-s53-fill-mend`, tmp/s53-fill-mend. Production is frozen at
  d1ff2ad0/265e588e. Later commits change only UI fixtures/readers and records. Resolve current HEAD
  with Git; latest four-case UI fixture run is3/4 green; one extension-buffer driver failure remains.
- Audit library tree: `~/PaintWork/PaintApp-s54-library-ownership`, tmp/s54-library-ownership. Strict
  shared file-tree/content identity and UUID Trash ownership; PBX source registered. Two added logic
  regressions now cover migration preserving both sides after linked-destination comparison failure and
  unreadable retained Trash ownership. Rebased onto fill dependency `071c7eb2`; application production
  logic remains byte-identical to `265e588e`. The library fixtures carry current `geometryVersion: 1`.
  See the external mutation plan in `~/PaintWork/s54-architecture-audit/library-ownership/`. No native
  build/runtime/UI/mutation gate has run. WIP, do not merge.
- Audit background tree: `~/PaintWork/PaintApp-s54-background-ownership`, tmp/s54-background-ownership.
  Rebased from fd73d821 onto library-ready 9d3ff76e; implementation commit
  3238a5fec226279fbe5edc8a89890d39800b583b. Export cancellation, maintenance serialization and
  bounded/cancelled thumbnails; five regressions. No native compile/runtime/UI/mutation gate. WIP,
  do not merge.
- The empty, unused s54-test-safety worktree/branch was removed; no code/history was lost. Subagents
  hit account usage limits; root preserved partial implementations and completed initial tests/PBX.
  Do not assume those snapshots are finished or repeatedly retry limited agents without a changed limit.

Root owns the sole native slot. Last completed test run: `native/fill-ui4-cleaned-run01` at332cc84a,
**3passed/1failed/0skipped**, all723 source bytes/modes exact. No task-owned native process remains.
No iPad operation. All production/project/shared-helper bytes remain identical to265e588e; only the FillMend UI
file and records changed. This is NOT a fully green UI class. External live status:
`~/PaintWork/s52-vector-points/runtime-qualification/root-status.json`.

Owned simulators: logic M5 **39E84984-3C6F-4A6A-8DC8-D1098F6B623E** shut down; UI iPad9
**56CC563F-06D0-42FC-9C18-A2B230DE2D38** booted; old-control9
**B0533278-3F74-4944-AC58-3514D87C85D6** shut down. Confirm inventory; touch only owned devices.
Fill DD: `~/PaintWork/s53-fill-mend/DerivedData`; old47d DD: `~/PaintWork/s52-saving-audit/week-cost/DerivedData`.
Native wrappers under `s53-fill-mend/native` reuse the reviewed freeze/census/xcresult tools. The focused
wrapper now resolves explicit UI/bench classes including multiple classes in one file. It defaults to
prepare only; --run needs a clean full SHA and fresh output. Capture runner executes by default;
--prepare creates an output folder, so use a fresh folder for the actual run.

## Qualified point-only Liquify and saving

Native vector material transport is removed whole: InkMaterial, archives, renderer branch and obsolete
controls/tests. Point positions flow through the ordinary renderer with brush properties/seed retained.
Genuine Distort/exact-bake StrokePlacement (104lines), raster inverse flow, linked recipes, local edit/
undo and LatestWins remain. Independent source review found no concrete defect. Net899 production lines
removed includes424 lines of temporary repair ADDED and still present; that service is not retired.

At47d7079c or proven identical production: runtime338/338 before/after17 assertion-red faults (16auto,
manual case09 verified actual assertion/source after parser omission); corrected classes33/33 before/
after2 faults; Debug AND Release5259=5255passed+4known opt-in skipped, all identities/255classes reconcile.
PBX1317 unique, lints/plutil clean. UI9/9(Liquify4+Raster5), old workflows10/10; pictures inspected. Old
control widens a round dot1.918×; current retains its round brush mark. Full current UI suite not run.
Evidence: `s52-vector-points/serial-qualification/results-47d7079c-corrected-fasts/`,
`runtime-qualification/current-final-ui9-296/`, `round-dot-old-control/final-60a1/`.

Newest-per-clock-bucket retention preserves3/6/24/7/4 tiers, pre-save copies/update protection/4GB logical
cap. Standalone14/14; reverse-loop fault8/14red/restored14. Integrated retention14+backup21 qualify.
Session47–51 bounded ask audit found no other concrete dropped actionable request.

Storage cost: actual28 saves over7 daily reopens on copied real Misc/Test2(26cels,2048×1024) retained9
versions,182encodes/462reuse. Two matched APFS no-op forks16,207,872 allocated bytes; delete-only-Backups
fork3,645,440; **delta12,562,432bytes/11.98MiB**, including APFS/delete metadata.24 stable RO samples,
6 RO checks and all original/live hashes match; images detached. Initial8192-byte remount-control
failure preserved. This is one declared workload, not actual iPad history or300–1000-cel extrapolation.
Evidence: `s52-saving-audit/week-cost/storage-forks-47d7079c/review.md`.

## Fill implementation and exact qualification

Same Mend Gaps setting covers detached AND outline-attached interior stroke gaps, conservatively
protecting uncertain joins/true holes/outer outline. Shared per-new-fill correction covers raster and
vector; Mend All Fills is vector-only across owned cels, generated linked cels remain derived. Current
references/settings at cel.startFrame, serial one-window work, bounded path/undo preflight, atomic
all-cel commit/one undo and version guards. Exact current fill omitted from its own frozen references;
render/input failures propagate as atomic refusal. No saved seed/provenance or raster-history redesign.

Shared exact EDT replaces JFA whole; two existing8N buffers reused, no per-tick CPU image scan. Fixed
circle LUT/all tied witnesses, contiguous supercover rays and unknown-rim veto protect boundaries.
Reach counts remaining paint-to-paint gap AFTER overlap while proving full open/source endpoints;
proof bound derives existing overlap range. Default-overlap batch sampler uses known coverage through
shared preparation; ordinary lasso collar semantics unchanged. Structure metadata invalidated BEFORE
destructive rebuilding. Threshold uses precise RGBA8 division, no epsilon/global fast-math workaround.
Halo78; saved mendsNeighbourGap wire key and UI identifier remain stable despite internal name cleanup.
Shared contour tracer replaces old dictionary/outgoing arrays/COW/simplifier, one byte/grid vertex and
turn-only paths with early point cap; no duplicate batch tracer.

At265e588e: **206/206** focused before and after **22/22 actual assertion-red continuation faults**,
exact723 bytes/modes restored after each. Cache compound fault includes native one-basin marker and
direct assertion failures; green refusal-only control1/1 separately proved the fault path. Preserved
partial b84 batch18 faults plus current22 overlap5 => **35 distinct qualified recipes**, not40.
**Debug AND Release5278=5274passed+4known opt-in skips**, zero failures/expected, exact identities/counts.
Full static5863, PBX1317 unique, UI identifiers/helpers/plutil/diff clean. No full UI/device gate claimed.
Final report: `s53-fill-mend/native/qualification-265e588e-run02/report.json`.

Old/new capture each1/1: six fixtures including preserved Test1 crop(527strokes), five widths each,
zero changed filled masks. New exact distances/levels match exhaustive five-fixture oracles and33
real-crop probes; old JFA has11 synthetic distance errors. Real original package/input hashes match.
`old-vs-exact/comparison-265e.json`; new attachment858872F2-7288-4DC4-B607-EA81B8CC17C9.json.

Release MendOFF bench2/2: new inside/open press medians124.9/57.5ms, cached ticks3.4/1.6; old98.3/168.7,
ticks6.0/4.9. Wide overlapping press ranges do not establish improvement/no regression; paired repeat
for the inside difference remains. Reach matrix1/1 covers12 cases (Reach0/12/40), one structure build,
no tick rebuilds and session buffers+RGBA inside configured budget.32768-island/131072-corner contour
traces/archives/reopens; path payload2,360,231B, sampled held delta13,123,584B. Full4096 M5 stress peak
629.99MiB process footprint is not isolated GPU/driver/device RSS. Evidence `old-vs-exact/reach-matrix-265e-run01/`.

UI14 at265e:10passed/4failed. Liquify4, OutsideTheCanvas4, graph-key drag1 and playback1 pass. Two NEW
FillMend cases stopped on wrong raster-default premise; corrected6bc20170 uses Rasterize layer0 then
checks actual raster menu. These two now pass2/2 including batch undo/redo and one-fill output. Root
looked at whole-screen owner-landscape pictures: long attached/detached white gaps close, outside stays
white; tiny protected end pixels remain visible. `native/new-ui2-6bc-run01/` exact723 freeze.
Two OLD tests fail pixels in UI14; old47d control reproduces seam OFF failure, extension passes. Their
Screen duplicated pixel decoding/ignored orientation and hardcoded geometry could hit the dock. Current fixture correction reuses ScreenshotPixels, visiblePaperRect, explicit canvas sizes and
landscape, retaining the original positive/OFF assertions. Full class at332cc84a is3/4: both new
workflows and the older neighbouring-fill seam pass. Root looked at the seam picture: first divider
covered, last OFF-divider visibly white, outside white; frame remains1. Extension fails in the TEST
DRIVER at PaintUITestCase.adjustSlider:779 after its first drag; the popup/slider disappears before
value verification. No final picture assertion executes in that case. Native recording
`fill-ui4-cleaned-run01/attachments/EB25874B-6B80-4439-9279-B811A9915D23.mp4`; inspect around35s.
Root inspected native video at34s: the panel ends after the boundary description; the Extension
Buffer slider is below its clipped viewport, yet isHittable stops scrolling. The35.4s manual drag
lands outside and dismisses it. Fix shared scrollFillPanel to require full control-frame containment
before driving, preserving the outcome assertions. Rerun the selected extension case, then the full four-case class. Full-screen captures are correct owner1080×810;
app.screenshot PNG metadata/cropping can produce a misleading partial portrait view. Touched screenshots
now use existing XCUIScreen.main protocol seam. Do not mistake that for a product layout defect.

## Temporary repair / release safety

Repair75/75 and13 repair mutants (16failed executions) qualify. Actual prior writer generated six
fixtures (material/Distort/bake/linked/plain ink). Copy-only full library:256input packages/3180files/
567855190bytes,266 conversions incl10 untouched update snapshots; normal retention prunes24 backups,
all242survivors strictly validate AND load (2034cels/1459vectors). Second run0, original hashes exact.
Current codecs require geometryVersion1; no old/default decoder. Ambiguous unreadable manifests remain
for recovery; basename fallback requires exactly one backup ID. Keep repair until owner confirms CURRENT
real artwork after fresh backup/install, then retire it WHOLE. Evidence `s52-vector-points/repair-qualification/`.

New repair-only timer1/1: **11.013s** around run() on M5,266 conversions; second0/original3180 hashes exact.
The107s total includes clone/hash/reopen checks. PaintApp.init currently runs @MainActor repair BEFORE
first screen; resolve responsiveness before install. A detached call to @MainActor run is insufficient.
No iPad startup/watchdog claim. Prepared genuine old-writer cold harness under
`s54-architecture-audit/repair-timing/` is NOT run. Root fixed missing plist import/process stopper and
Study-folder navigation. It builds with temporary test, stops/restores723 source, host seeds an empty
owned simulator and tests without building. Review before grant; use a fresh owned simulator since56
contains test projects. No production hook. Timer evidence `capture-02` and `real-library-report.json`.

## Audit and crash next

[ARCHITECTURE_AUDIT.md](docs/ARCHITECTURE_AUDIT.md) records19 candidate clusters and qualification gaps.
Initial read-only review is consolidated; proceed to reproductions/coherent fixes, not endless generic
research. Full file coverage has inventory-only gaps. Both WIP branches start at origin afd2030c, so
integrate/rebase deliberately and preserve origin TODO on conflicts; do not resurrect finished items.

Test1 respring cause remains unresolved. Two installed-build Oct23 Jetsam candidates18:47/23:03Toronto
name backboardd1850MiB per-process limit; Paint active with no app kill reason, current/peak730.4/922.6
and768/1248.6MiB, sameF610 UUID/different lifetimes. Owner recalls one spinner incident, not time, so
neither report is a confirmed match. Disk warning with57/69captured stacks on FrameBakeStore atomic
writes is sampled stack evidence, not backup byte proportion or cause. No speculative production fix.

Preserved Test1:4096²,7cels/6vector, Vector3/frame2 has527strokes/12973samples/max118, no Liquify/material.
Eraser7.962 means CANVAS POINTS, not7.96%/326px. To Cross Mode3 repeatedly updates full base. Simulator
capture1:3successful cuts/3full4096RGBA assignments, footprint854–985MiB,2pictures inspected. Capture2
premise failed before gestures; capture3 clone removed before recorder so exact cut count unknown.
All original source restored; simulator evidence does not prove backboardd origin. Next physical plan:
standard bounded60s Activity Monitor trace, verify fields first, counted cuts and same-run flight on
UNIQUE owned Test1 copy, cleanup/fresh export. No privileged/root privacy bypass. Evidence
`s52-erase-crash/device-diagnostics/resume-2026-10-24/` and `next-device-memory-capture.md`.

## Device and deferred work

No fresh saved-scene/unlock readiness or current-library export yet. Before any physical restart or
install: fresh readiness, read-only -exportProject -exportAll, copy Export with devicectl, verify index/
all paths/counts/bytes/hashes, clear only temporary Export through index-only hook, then normal launch.
Preserved export predates later Liquify. Build signed clean Release with identical clean/build args/DD,
deep verify/profile>=5days, matching binary/dSYM UUID, required old workflows before install. External
final-release plan is STALE at b84; repin final source. No resetGallery/uninstall/normal scene deletion.
Device UDID00008030-000151492EC3C02E; CoreDevice E3B83820-DF74-5042-B52B-0D5BA17E4877; verify fresh inventory.
Secrets `~/.config/paintapp/.env`, never print. Beware auto-deploy before pushing unready code.

Preserved library `~/PaintWork/s51-cleanup/current-library/Export/`:10Projects+228Backups+18Trash,
567855190logical bytes, hashes frozen. Do not delete recovery copies. Owner manually deleted old
physical test scenes; no gallery cleanup needed. File Provider root requires read-only export; Tailscale
does not expose it. AirDrop history under s50-liquify/device-backup-2/external-library.

Deferred: Stream27stage5 needs owner/laptop; multi-cel22/linear-light10 owner-deprioritized; importer37
dropped; future audio28/video30/interpolation require briefs. Raster Move undo/freeform-text minimum
remain deliberately carried. Older freeze logs were pre-Liquify f813346, owner saw repair message only;
keep recognizer repair/no speculative UIKit fix. Renewal evidence docs/bug-evidence/auto-resign-2026-10-22.md.

Resume qualification: fd73 selected extension drive keeps the popup open with a fully visible slider,
but the manually inset shared slider driver stops at0.9813 instead of its requested endpoint. This
case originally used native normalized adjustment (old47d passes); restore that endpoint gesture,
retain full-visibility scrolling with an explicit assertion, then run the case and class. No product
change is attributed to either driver failure.


## Background lifecycle WIP — rebased on library-ready

The library-ready dependency's TODO/HANDOFF/BUGS records remain authoritative; this branch's focused
review found no concrete production defect. Current-format fixture scan found no legacy-format
assumptions. Native qualification remains pending. The refreshed external mutation plan is pinned to
3238a5fec226279fbe5edc8a89890d39800b583b.
