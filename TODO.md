# TODO

## Current owner-facing status — October 29

**Active: continue; do not park.** Kevin resumed after noon Toronto time. Work continues; a new disruptive device
workflow still requires fresh saved/unlocked readiness. Overall completion is approximately **75%**: most implementation is present,
but combined checks, remaining audit work and physical confirmation are still open. This is an
estimate of the whole queue, not a measured percentage of code.

The installed iPad version is still Release `6fb979f4`. Kevin confirmed it opens and his usual
scenes look right. The newer audit work is assembled in an isolated branch; it is **not installed,
merged or pushed**. Separate passing checks do not qualify that complete build.

| Owner task | Done so far | Still outstanding |
|---|---|---|
| Simple vector Liquify | Point-only version installed and owner-confirmed; complex vector material path removed | Final combined checks and current performance measurements |
| Mend interior/attached vector strokes and Mend All Fills | Installed; public fill/Mend All workflows, outline and uncertain-join checks passed | Current Release cost/memory checks, including whole-layer work |
| Smart father–grandfather saving | Newest clock-bucket retention installed; failed-save retry/safe-exit correction integrated | Combined checks and real-scene storage/device confirmation |
| Test1 rapid-erasing crash | To Cross bounded-window candidate passed whole112, four mapped source controls, and clean normal35 at740e; source/look evidence preserved | Determine actual allocation/latency cause; current installed-build physical evidence |
| Drawing/erasing lag | Ordinary single-cel To Cross uses the bounded replacement window; whole112, four mapped controls, and clean normal35 passed at740e | Final combined/Release checks and new iPad confirmation |
| Move needs repeated taps in Test | Required vector-picture acquisition corrected; copied Test passed one-tap Move | Final combined checks and device confirmation |
| Small Move boxes | Reachable body/grip arbitration corrected and separately checked | Final combined checks |
| Move Set Down drawing gap | Old gap reproduced; existing lifted-picture owner now lasts until finished frame is shown | Final combined checks and device confirmation |
| Stream picture separates from Move box | Shared placement correction integrated; public stream routes passed | Final combined/device checks, including release and Set Down |
| Undo shows wrong edited-cel thumbnail | Correction integrated; model/public/fault checks passed | Final combined checks |
| Huge curve coordinates | Checked narrowing integrated; logic/archive/fault checks passed | Final combined checks; no crash-cause claim |
| Library relocation, Trash and damaged saved data | Shared checked addresses/ownership and strict fields integrated; old-writer roundtrip passed | Final assembled/current-format recovery checks |
| Export, Resize and Gradient | Root-cause corrections integrated; painted public workflows separately passed | Combined checks and remaining performance boundaries |
| Text, colour, effects and gesture interaction | Text touch-owner correction integrated; native Select All/colour passes without false repair | Remaining effects, opacity, masks, menu and whole-class checks |
| Architecture, cleanup and performance audit | Several shared-owner corrections tested and integrated; retired paths removed | Remaining file review, documented assertion gaps, combined checks and performance |
| Development disk cleanup | Repeated bounded cleanups; latest recovered about4GB with artwork/app files verified | Keep generated storage bounded between native batches |
| Windows streaming | Earlier transport checks passed | DNS/resource/clipboard/keep-awake/Quit gates; real-link work waits for reachable Windows host/owner laptop |
| Install latest qualified build | Existing installed version preserved by automatic-renewal source protection | Qualify next build, drive old workflows, verify signing, then install with fresh saved/unlocked readiness |

## New audit findings — recorded October 29 before implementation

The combined409 native baseline remains frozen atd798 in the integration worktree. This records-only
branch is the live queue so new root-cause work can proceed independently; merge these records back
only after the native/source extraction boundary. None of these findings is physical crash proof.

- [ ] Simplify the fresh-fragment eraser correction before final qualification. Source review proves
  a cut piece emits a subset of the same original dab lattice, including recursively cut pieces:
  no re-anchoring or extra endpoint/cap dabs. Keep measured fresh-ID insertion in the existing map,
  remove redundant arriving-bounds union/flags/new-child fallback branches, and retain the existing
  departing-bound/unknown-victim fallback. An unseeded child uses that same fallback on its next cut.
  Trim duplicated scratch/window/Undo test work already covered by the existing component; retain
  consecutive cuts without an interim render and final full-picture parity. The union mutant has no
  valid sensitivity and earns no credit. Evidence: root-next-gates + eraser source proof messages.
- [ ] Reject malformed current compositor-node metadata through the existing manifest error/recovery owner. Source d798 FolderManifest catches current node/mix decode errors into an ordinary folder, bypassing full-manifest recovery and omitting the role on resave. Add finite wrong-type op/mixMode and actual-package preservation/recovery regressions beside valid stack/mix. Preserve absent-role and known retired-slot semantics as explicit separate cases; do not infer a new future-format policy. Source-only finding; no native reproduction or implementation yet.
- [ ] Bound accepted video timing arithmetic at the existing VideoFrameMap/VideoRef boundary. Positive-timescale decoding and finite saved Double speed do not guarantee Int64 tick products/sums or Double-to-integer conversion fit; source d798 can trap before its crop clamp. Add finite current-decode-to-map rows for extreme ticks, large/small finite speeds and exact valid boundary neighbors, preserving ordinary fractional/frame-for-frame/held-end semantics. No owner crash attribution, large allocation or new timing policy; source-only until root records and grants proof.
- [ ] Preserve independent backing and ink placement during a cel-pose graph drag. At d798 LiveTransformEdit selects the whole leaf as a moving band but applies the cel ink delta to it; that band also holds stored raster/baked pixels, whose normal renderer follows only the container. Add a finite blue-backing/red-vector-fill drawn comparison through the actual live-band owner and a cold public mixed-tier graph witness. Prefer existing CelContentPicture/Placement ownership; no parallel cache/state or special transform. Source facts confirmed, visible release jump inferred/unrun; separate from Move/stream fixes.
- [ ] Bound Bake to Images’ retained output through the existing source/residency owners. Current `bakeVideoToCels` keeps a source-sized UIImage for every distinct decoded frame in the document; the64MiB decoder ring’s eviction/close cannot reclaim those image aliases. The public count/save-time confirmation and import’s initial scene-length clamp impose no output byte budget. This narrows the existing placed-image/video ownership exclusion. Record a small distinct-frame ownership/pixel witness, then reuse existing RasterSource/checkpoint/package-serializer seams where appropriate; do not add a parallel cache or flatten/change placement. No RSS measurement, device crash cause or qualification claimed.
- [ ] Preserve keyed movement when Resize Canvas → Scale artwork changes coordinate space. `applyCanvasResize` maps vector geometry but retains cel TransformTrack.box/curves/baselines in old canvas coordinates. For resize M and pose P, require P_new·M=M·P at the drawn frames. A100→200 canvas with a10pt keyed translation currently gives a50pt position where the scaled original is60pt. Prove with an opaque rectangle, then root-cause transport through existing pose/resize owners, Undo/Redo and save/reopen; crop/rotation/container cases retain separate limits. Move’s Keep Stroke Width is unrelated to this translation witness. No native reproduction yet; this is separate from the older held-Move/padding issue. Resize uses one uniform Fit/Fill factor, and no broader affine design is authorized by this report.
- [ ] Delete uncalled TransformKeyframes.clearPoseKeys whole and its obsolete KeyframeControl
  comment. The existing poseDeltaClearing undo owner is the only live path; repository symbol search
  finds no invocation of the old in-place clearer. Reuse existing clear-key tests; add no helper/state.
- [ ] Reconcile the already documented Flip Canvas vector omission/history clear and derived-thumbnail
  backfill identity mismatch against existing rulings/queue. Do not duplicate the separate derived
  thumbnail full-size-render cost issue or reopen owner-deferred behavior without checking its ruling.

### Current evidence and decisions

- **Eraser/brush source assembly:** root reviewed the fragment-bounds source and bounded tiny-dab
  transition. Whole BrushEngine67 passed with source731 exact. Their five production/test paths
  are assembled for a combined native baseline; no diagnostic sentinel/temporary cost method was
  harvested. Fragment bounds124, mutation controls, public1pt and matched cost still remain. The
  arrival-union control is sensitivity-unproven and unknown-fragment defense has no fixture credit.

- **Picture component assembly:** f422 public Paste/Multiply/Bake/save/reopen passed1/1; root
  verified source731 and inspected all three owner-landscape captures. The six-cell arrangement
  stays correct. Its five source/test paths are now assembled into the integration candidate;
  whole68, mapped controls and final combined checks still remain. No install or main merge.

- **Assembly efficiency:** root has source-reviewed and assembled the small Shape scale and export
  frame-range corrections into the integration candidate before their native checks. Their original
  pins and control proposals stay frozen. This is unqualified source assembly, not completion, main
  merge or install; the next combined slice must repin its classes, counts and controls.

- **Current checks:** HUD teardown is integrated after its release/menu checks and old-code control.
  Tiny-brush direct-area8a5 finished65/66; only its actual-gradient handoff failed. The calibrated
  coordinate sentinel passed. Fresh7a400 transition candidate has whole67 and matched-cost proposals
  prepared; none of its source is integrated. PNG/Bake64 logic and old3 public tests passed, while
  the new public test stopped on optional Move premises. Simplifiedf422 is now running the actual
  Paste/Bake/save/reopen workflow with unchanged pixel checks. Eraser A2 Release passed1 and counted
  27full4096²pictures plus6reduced480²pictures across36cuts. The fresh-fragment bounds candidate
  reuses the existing geometry walk/map; focused124 is pending. No physical crash cause is proved.

- **Old generated-file cleanup:** the single-log compression trial passed byte/metadata checks.
  The26-path derived-PNG trial preserved bytes and permissions but failed its original exact-xattr
  oracle because macOS updated `com.apple.provenance`. Keep that result failed. Root permits a new
  narrow revalidation accepting only the exact recorded old/new OS-managed token on these old
  nonexecutable derived PNGs, never manual security-xattr writes. Original parent-directory times
  were not durably saved: record this limit, never invent restoration. Before more mutations,
  journal timestamps durably and restore them in finally. Root reviewed helper98a2d853 and
  the independent all1085-group validation; the exact fixed three-folder derived-PNG batch is
  approved under its matching external grant, with full byte/metadata checks, durable directory
  restoration and measured free-space change. No DSC mutation is approved. Timing waits for IO join.
  Protected artist packages, original recordings, current54/55 evidence and Products stay untouched.

- **Generated-build resource audit:** recorded Release builds compile the UI tests for both
  arm64 and x86_64, while the owned iPad simulator executes arm64. Select only the active
  architecture for the Release UI-test target; retain the shipping app target's existing settings.
  Verify actual arm64 build and unchanged test counts in the final Release gate. This is a test
  resource correction, not an app performance claim.

- **Shape handles during a tiny pinch:** source review found that ShapeOverlayView skips update
  side effects for nonpositive canvas scale but still stores it; several handle/chrome dimensions
  divide by that value. Reuse the consistent scale guard already used by the sibling object overlay,
  then check finite hit/chrome geometry and public shape manipulation. No crash attribution.

- **Photo-import feedback audit:** `AddMenu.primePhoto` silently discarded transfer/decode/priming
  failure while the adjacent video path reports it. Reuse the existing menu notice for photo
  failure; no new state or import abstraction. Existing Add-menu checks and assembled gates remain.

- **Picture saving audit:** an actual save/reload showed a scale2 placed picture doubling in drawn
  size. Its PNG keeps rotation but reloads at scale1; the placement needs correct image-unit
  conversion. Fix and package round-trip checks are pending; no new saved format is proposed.
- **Missing new ink:** the exact saved red stroke also disappears in an independent full render,
  so the investigation now targets shared small-brush rendering rather than only preview handoff.

- **Architecture/performance audit:** the optional performance readout can leave its frame counter
  running after returning to Gallery. Its display link retains its monitor, so monitor-deinit
  cleanup is unreachable. Teardown now belongs to the existing HUD owner; release/public checks and the old-code
  control passed their intended outcomes. The correction is integrated; final combined gates
  remain. No crash-cause claim.

- **Bake audit:** a pasted picture could lose its rotation when baked. OLD drawn-pixel reproduction
  failed as expected; the one-line orientation-preserving candidate passed25 logic checks. Public
  UI1 stopped on an unanswered iOS Paste prompt before Bake; a test-only prompt correction, controls
  and assembled qualification remain. This is part of the architecture/effects audit.
- **Recovery gate:** the fresh strict-text run stopped at its new red-ink drawing premise before
  Cancel/Restore. Its exact saved1pt stroke reproduced missing ink independently; the shared-dab
  candidate now renders it and passed its strict dedicated saved-stroke method. Keep that regression.
  The recovery test itself needs a reliably opaque larger mark and the existing measured slider
  helper, because native low-position adjustment produced1pt instead of the requested size. Preserve
  the red-core assertion, then restage a fresh simulator for actual Cancel/Versions/Restore/Trash
  proof; no recovery pass is claimed yet.

- **Crash and lag:** Test1 is4096²; Kevin confirms rapid To Cross erasing triggers the failure. The
  crash cause remains unproved. The simulator Test1 capture made36 cuts and produced25 full4096²
  picture outputs; immediate dark ink became Recolour red at rest, so no persistent Recolour loss was
  found. The separate740 candidate replaces repeated per-sample full-base work with the admitted
  native window on ordinary single-cel To Cross. It passed whole112, four mapped direct assertion
  controls, and a clean normal35 rebuild; root inspected white paper, all three removed lines, Undo,
  and effect-pan images. These are simulator component results, not a physical crash diagnosis or
  final Release/performance qualification. Preserve the Test1 input/flight and obtain fresh owner
  readiness before another device workflow.
- **Move and stream:** only repeated-tap Move was reported as specific to Test. Stream displacement
  occurs after release or Set Down. For the brief Move-exit gap, Kevin explicitly prefers the
  existing lifted drawing remain visible until the compositor's finished picture is shown.
  Current corrections reuse those owners; no timeout or parallel Move cache was added.
- **Text/menu:** source and two flights tied false repair notices to the canvas recognizer accepting
  live text-view touches. Existing touch ownership now excludes it at touch-down; no timer/state
  added. Whole owner/text34 passed before/after deliberate controls and inspected red-word/menu
  pictures. Portrait menu continuity1+whole8 passed. Owner-landscape1 stopped at the next-pan
  assertion with Lens Blur settings visible over the canvas; inspect fixture occlusion first.
- **Saved files:** synthesized MotionGroup decoding removed its custom defaults. One typed array
  helper preserves omitted/empty registries while rejecting explicit null. Real previous-writer
  load/save/reload and whole30 passed; six null assertions failed under the old helper; temporary
  witness/staged copy removed; final whole29 passed. No null files in the250-package inventory and
  no current writer emits null, so no new repair/schema is justified.
- **Performance:** three opt-in Mend/Liquify cost tests are now harvested but **not compiled or run**.
  The300/1000-cel Mend All fixture is light synthetic72² data, not dense artwork. The actual
  copy-only week-of-saving APFS measurement is already qualified; do not repeat or extrapolate it
  into a physical300–1000-cel claim. Exact metrics/pins live in HANDOFF and evidence packets.
- **Storage:** latest owned56C cleanup archived/hash-verified11,112 container entries, removed only
  two generated cache roots, reclaimed4,287,086,592bytes and verified artwork/active bundles after
  boot. Receipt: `~/PaintWork/s55-recorded-regressions/owned56C-cache-cleanup-before-final-gates-20261029/`.
- **macOS prompts:** Kevin sees requests for ChatGPT access to OneDrive/other app data. Cause is
  unproved. Scope work to explicit repository, PaintWork and owned-simulator paths; do not scan cloud
  folders or change privacy settings.
- **Artwork/readiness:** original library exports, fresh Test export, recordings and copied Test1
  are hashed/protected. Earlier saved/unlocked readiness was consumed exporting Test; obtain fresh
  readiness before a further device restart. Automatic renewal must preserve installed6fb while
  main is older and advance its source/artifact/profile state only after a successful install.

**Mode3 source follow-up:** the740 candidate reuses the existing replacement window, CelContentPicture,
and UnlandedInk for ordinary single-cel To Cross. Per-sample cut resolution, one-gesture Undo,
captured references/poses, and refusal fallback remain. Four mapped controls reached their intended
assertions and the restored source rebuilt cleanly for normal35; whole112 and normal35 are component
checks only. No parallel cache/service/timer/state was added. Universal multi-layer erasing remains on
its existing route. Measure final Release work before claiming a latency benefit; no simulator result
establishes the crash cause.

**Current assembled-build boundary:** d30a's normal146 stopped at145pass/1fail because a pan crossed
the still-open Duplicate/Bake layer-options popup; the corrected740 fixture closed that popup through
its public control and the whole112 slice passed. The earlier7cc compile failure was a CGRect/CGPath
mistake in the benchmark fixture, later corrected. Release copied-Test1 capture1 passed with36 cuts and25
full picture landings; its timings do not prove owner-device performance or crash cause.

**Composed d30a result:** the earlier normal146 was145pass/1fail/0skip with exact source731. Its only
failure was the obstructed effect-bar pan; the corrected740 fixture closes the Duplicate/Bake popup.
The740 whole112 passed and raw/normalized image review confirmed white paper after all three cuts and
restored lines after Undo; the apparent black view came from image metadata/display. The full-screen
and element-pixel evidence has been reconciled. Keep the old packet immutable; no product visual fix or
crash cause was established.

**Latest validation:** candidate740e whole112 passed112/112 with0 skips; all four reviewed controls
reached their mapped assertion failures; then a clean Debug normal35 passed35/35 with0 skips. Root
inspected white paper after cuts, Undo restoration and effect-pan crops. Candidate files are now
harvested into integration in separate source, cleanup and screenshot commits. Static integration census
is731 source entries, fast5448/full6062; identifier/helper checks pass. The assembled integration has
not been compiled or run. Final Release, full fast/UI, performance and device gates remain open.

### Work queue

1. Finish copied-Test1 Mode3 diagnosis and review the existing shared-window presentation seam.
   Do not attribute the crash or claim an iPad speedup from simulator observations.
2. Complete remaining colour/effect/mask/graph/recovery workflows and actual drawn/owner-size
   evidence. A fixture setup failure proves no product outcome; preserve original results.
3. Finish genuine architecture/file-review gaps and remaining source findings through existing
   owners. Keep coherent compiler-isolation candidates out until their whole boundary is reviewed.
4. Qualify the exact assembled source: static/lint/project checks, complete fast tier in Debug and
   Release, affected UI classes, required deliberate controls, and the full phase gate. Count actual
   methods; Mode3 and opt-in cost witnesses bring static full count6062, fast5448.
5. Run paired Release fill/effect and current Mend/Liquify measurements with correct output and
   honest memory limits. Never call counted cache bytes whole process/device memory.
6. Complete Windows gates once its external state changes; no repeated unreachable-host polling.
7. Drive existing playback, grey-area pan, Move/graph drag-release and strokes; verify Release
   signature/profile/library protection; install qualified source after fresh device readiness.
   Confirm the recorded drawing, erasing, Move and stream behaviors on that build.
8. Remove each completed item whole only in the qualified main merge; push and update HANDOFF.
   Preserve original evidence/pins and name anything that could not be run.

Deferred interpolation overhaul, multi-cel selection, linear-light blending, audio/video editing and
other explicitly later features stay written down. Dropped brush importers are not reopened.
Detailed task sections below remain unchanged. Technical authority: HANDOFF.md and
`~/PaintWork/s54-final-qualification/root-next-gates.json`.

<!-- Status-preamble compaction only. Original bytes retained at ~/PaintWork/s55-recorded-regressions/status-preamble-compaction-17c00484/TODO-before.md and in Git. No task was closed. -->

## How to read and keep this file

Every item is a **status**, a short **description** a future session can pick up cold, and **what is
left** as a checklist. Items are in **queue order** — the top of the list is what to do next.

**An item leaves this file when it is merged, not when a branch exists**, and it leaves *whole* rather
than being marked done: `git log` and the spec documents are the history. The owner, 2026-09-06:
*"Basically I want to be able to read the tasks on TODO clearly without already finished tasks."*

**Three in flight at once** unless the extras need no simulator — the cap is about the machine, not the
plan (`tools/simlock.sh`).

**Before adding an item, check whether an existing one already covers it in different words.** A
restatement filed as a new item is how one feature came to be specified in six documents at three
scopes before a line of it was written. This file has since carried two live duplicates for weeks.

**Record an ask in the owner's own words, and fold a ruling into the item it rules on.** A quote is
cheaper to keep than a decision is to rebuild. But an item reads as *one current description*, not as
the transcript of the argument that produced it — what happened this pass belongs in
[HANDOFF.md](HANDOFF.md) and in `git log`.

**Cite a symbol, not a line number.** A 2026-09-06 audit found ~10 of one item's 15 `FILE:LINE`
citations and 5 of another's 11 no longer resolved — every named fact still true, every anchor wrong,
two of them because a file moved directory. A symbol name survives a refactor and a line does not.

**A bare item number in a spec or a code comment may name an item that has already left this file.**
That is the merge rule working, not a dangling reference: `git log` and the spec documents are where a
completed number resolves. Two are cited often enough to name here — **(10a)**, the Oklab colour ramps,
and **(38)**, the graph editor's bezier tangent handles and their tap grammar. Do not re-add a finished
item to this file to make a citation resolve.

**Verify a status before trusting it, including this file's own.** That same audit found fifteen
assertions here that the code contradicted — features called unbuilt that shipped weeks ago, a blocker
called live that had lifted, and two commit shas that are not on `main`.

**Old files are repaired once, never read forever.** The owner, 2026-10-10, retiring the earlier "no
document has to survive" permission now that real scenes live in the app: *"I will still keep the rule of
no legacy code. If an update causes existing files to be outdated, then they should be automatically
repaired by a throwaway script the session makes."* So a format change ships with a **one-shot repair**
that rewrites the owner's existing files (Projects, Backups, Trash) to the new format at launch, and the
app's decoder knows only the current format. The repair is deleted, whole, once the owner confirms
their files are repaired. Build `2974b33` broke this rule and lost the owner's keys (TODO (153)).

**The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works at
2048x1024, and every figure taken before 2026-08-17 was at 4096², eight times the pixels.

---

## Reclaim accumulated development and test storage — 2026-10-26

October29 continuation: bounded inventories locate most growth in retained test results and video
analysis frames, rather than compiler caches. A storage agent may inspect only the old closed
`s49-liquify-logs`, `recolour-logs`, `evidence`, and `logs` roots initially. Current54/55 proof,
compiled products, all artist packages/exports/ZIPs and original videos stay protected. A reversible
single-file filesystem-compression trial is queued for the old generated
`s49-liquify-logs/combined/batches/field-output.log`; bytes/ownership/mode/times/xattrs must be
verified before replacement. Exact duplicate derived PNG frames are a separate path-preserving
dedup proposal; any loss of distinct modification times requires explicit recorded review. Root reviewed the exact trial helper/plan and approves only its26-path/25-alias duplicate-frame
trial plus the single verified log replacement. Derived-frame timestamp/inode sharing and the log's
recorded creation-time/compression-flag change are accepted; all bytes/paths/permissions/provenance
stay exact. Full batch remains conditional on observed positive reclaim and root review. No
performance measurements run alongside cleanup IO. Concrete allowlists/receipts live in PaintWork.


Kevin reports free disk fell from about70GB and asks for thorough cleanup before it causes more
problems. Inventory storage created by current/past agent work: test simulators, checkouts, compiler
caches and repeated evidence blobs. Keep real artwork/exports, required benchmark binaries and all
needed source/evidence; prefer exact deduplication and verified archives. Delete only confirmed
obsolete owned outputs/devices; do not touch unrelated personal files or other sessions' work.

- [x] Inventory and first cleanup:10.11GiB actual simulator caches plus20.72GiB exact report
      dedup recovered;~35GiB free. All app data/evidence paths/protected baselines verified.
      PaintWork initially~76GiB attributed, results~60GiB;56C OS caches~10GiB.
      Reclaim exact verified closed-result duplicate blobs and reviewed offline56C caches; retain
      evidence paths/artwork/baselines. Verify actual free space and bounded phase-boundary cleanup.
      External detailed plans/identity manifests live in resume-20261026/storage-inventory-20261026-vector.
- [x] Five obsolete owned simulators deleted after independently verified data archives; all unlisted/
      protected device identities exact. Actual DELETE-phase gain13.05GiB;47.06GiB/50.53GB free.
      Keep820782758bytes of archives/manifests. RequiredProducts/shared/ambiguous devices remain held.
- [x] Bound storage checks at native phase boundaries in CLAUDE.md. This item remains until merge;
      no global/personal cleanup, mutable hardlinks or app background-cleanup service was added.

---

## Keep the edited cel's thumbnail correct after Undo — 2026-10-26

Actual whole CuttingModes4 atb60 is3pass/1intended thumbnail failure, with inspected whole
landscape pictures. Undo restores A while current-view callback resolves B, leaving A's tile cut.
Source1c99512c reuses existing cel ID, lookup and registerVectorElementsUndo; duplicate view
closures are removed and the generic helper moves +Text→+Undo. No new state/service/renderer or
respring attribution. Independent peer accepted source. Normallogic70 and public4 passed70/70 and4/4. The3logic/1public
controls qualify6 application contracts; root inspected all4 whole landscape pictures. Exact4-path
source is harvested d7090060. Separate B fixture premise control and final integrated gates remain.

The completed CuttingModes4 run atb60 reached the intended public failure at526 after CutA and
scrubbingB. All earlier ink/tile/history premises passed; ReturnA/Redo/B outcomes were unreached.
Before code, root accepts reusing registerVectorElementsUndo with the actual gesture canvas's
existing layer/cel identity, same label/VectorUndoCost/changed-ink rectangle. Remove the view-owned
duplicate restore/current-view callback closures whole; move the existing generic ElementSwap and
registration block from +Text to +Undo. No new state/service/renderer or current-playhead lookup at
undo time. Extend the existing shared thumbnail logic workflow across a frame change, preserving its
drawn/cold-render assertions; existing public repro retains all Redo/B checks. Commit before faults.

- [x] Actual reproduction, independent owner review and minimal existing-owner correction; component
      logic/UI/controls passed at their recorded pins. Retain whole item until merged.
- [ ] Verify actual edited/restored drawing and thumbnail across frame changes, Undo/Redo, cold UI and
      meaningful controls; final fast Debug/Release and touched-class gates before merge.

---

## Bound curve flattening before integer conversion — 2026-10-26

The audit found that StrokeGeometry.flatteningSteps converts an unbounded control-polygon length
before applying its documented64-chord cap. A finite current-format curved fill can carry controls
above Int range; actual fill posing/Liquify mapping flattens before its later region/map checks.
Source finding62b0df17 is corrected8272 and harvested8682859f: the existing bound moves before
conversion, preserving ordinary rounding and coordinates. Current-format archive/reopen/nonlinear
consumer and whole94 passed;6 safe owner controls qualify7 new canonical application statements.
No unsafe old cast, new schema/parallel validator or Test1 attribution.

- [x] Finite current-writer/read witness, existing-owner correction, ordinary/capped consumer tests
      and6 safe controls are component-qualified/root-reviewed. Retain whole item until merged.
- [ ] Final assembled Debug/Release and cold drawn gates; review any newly reached downstream
      arithmetic separately, without claiming global bounds.

---

## Protect library relocation and Trash backup ownership — 2026-10-24

Implemented and included in normal847/847/base49 qualification, unmerged. Strict shared file-tree
and content comparison replaces equal-count/bytes identity; Trash purge uses project UUID ownership.
Comparison/read/link/ambiguous ownership failures preserve original artwork and history. The direct
linked-entry assertion is retained; a later unrelated filesystem rejection cannot prove this policy.

- [ ] Qualify final integrated fast/UI gates, graph/lints and source restoration before merge.
- [ ] Keep real packages/backups protected; no backup retention policy change is part of this correction.

---

## Background lifecycle ownership fixes — 2026-10-24

Implemented in the same qualified dependency: export cancellation fences old completions, startup
stage cleanup uses the existing package serializer, and document close cancels bounded batches of
eight thumbnail backfills. A synchronous batch may finish if close is triggered reentrantly. Source
review found no concrete remaining defect; final-source fast/UI/device gates are still pending.

- [ ] Preserve cancellation/refusal and exact-source proof in final qualification; do not claim older
      component results cover new integrated code automatically.

---

## Vector Liquify must move points only — 2026-10-23

**Implemented, installed6fb and owner-confirmed, unmerged.** Finish retirement and final gates on resume.
The owner's point-only instruction below is authoritative; no unwanted material path or compatibility
flag may return during integration. Independent review and passing controls supplement drawn proof.

Owner reports that Liquify stretches strokes horizontally on vector layers and rules:
“All that you had to do was to change the position of the points in the stroke, not apply
transformations to them. I remember EXPLICITLY telling you this.”
Audit the actual vector path and original brief/history against point-position editing through the
normal stroke renderer. Identify and remove unnecessary vector-only deformation/material machinery
rather than adding another mode or patch. No implementation cause is assumed from the observation.
If prior appearance rulings conflict with point-only behavior, show the concrete difference and ask
one plain-language decision; do not silently retain the unwanted transformation path. Raster Liquify
and linked in-between support keep their existing rulings unless the new correction affects them.

Owner calls this a “significant failure” and makes **very thorough architectural cleanup** an explicit
requirement. Trace every vector-specific field/module/render/archive/test dependency and its real
consumers; remove obsolete machinery and redundant abstraction, not just the visible stretch. Verify
saved-scene conversion/round-trip, focused mutation-backed tests and real workflows, with an independent
final architecture review. Do not claim certainty from passing tests alone or retain this path behind
a compatibility flag. The new point-only vector instruction is authoritative over implementation
interpretations made earlier. Record any actual behavior conflict with evidence before asking.

The implementation removes native vector material transport whole and retains genuine Distort/exact
bake, raster Liquify, linked source following and the temporary saved-file repair. At earlier point-only
checkpoint47d7079c, independent review found no concrete architecture defect and328 app files were
byte-identical to that tested point-only baseline. This is historical proof, not a current-head claim.
Repair75/75,13 repair mutants and copy-only242-survivor real-library gate qualify at their recorded pins.
That earlier point-only runtime338/338 and17 runtime mutants qualify (16automatic+one exact manual native-assertion review).
At that earlier point-only source, affected UI9/9 and required old workflows10/10 passed. The final old-code control widens the dot
1.918×; current code keeps it round. Root inspected the actual pictures. No held-path helper remains.

At that earlier point-only checkpoint47d7079c, Debug AND Release each5259=5255passed+4known skips,
zero failures/expected, all method identities/255 classes reconcile. Corrected classes33/33 before and after2 assertion-red faults;
723 bytes/modes restored, lints/plutil/PBX1317 unique clean. The corrections remove obsolete placement
and oldest-plus3 expectations only; production and earlier338/17/UI proof remain exact.

- [ ] Qualify whole one-shot repair removalec62d712 and retained permanent owners: fresh250-package preservation,
      signed6fb install/normal launch and owner “Looks right” confirmation are complete. Preserve
      permanent maintenance/readiness/current-format validation; finish final qualification/merge.

---

## Verify smart document saving and reconcile outstanding asks — 2026-10-23

Owner asks whether the father–grandfather saving scheme was implemented; if not, implement it too.
Trace the actual retention/save behavior and tests before claiming completion. Audit earlier owner
requests and queue history for other missing or incorrectly completed tasks, and restore actionable
ones to TODO before working on them. Previous notes claim age-thinned backup generations and a4GB
cap; those are evidence to verify, not proof. Continue all actionable work without an unnecessary pause.

Audit confirmed the 44-slot 3/6/24/7/4 schedule, install-burst protection and 4GB cap. The mismatch was
oldest-per-bucket versus TODO(161)'s newest policy. Owner ruled 2026-10-23 to use the usual newest
clock-bucket policy, preserving age tiers, pre-save copies, update protection and cap; no oldest exception.
The correction is integrated but unmerged. Actual standalone retention 14/14 passed, reverse-order
mutation 8/14 was assertion-red and exact restore 14/14 passed. Integrated retention 14 and backup 21
also passed in runtime338 at earlier point-only checkpoint47d7079c; Debug/Release each5259
qualified at that source, not the broader current integration.

The bounded Session47–51 audit found no other concrete dropped actionable ask. The controlled copy-only
week storage measurement below is qualified; preserved228 backups/522461597 logical bytes alone do not
measure APFS shared-block cost. Evidence: `~/PaintWork/s52-saving-audit/audit.md`.

The adjacent corrupted-manifest recovery guard is implemented: same-basename fallback accepts exactly
one backup ID, preserving the live package on ambiguity. Regression and mutation are qualified in the
repair gate; this safety change is also unmerged.

The declared copy-only APFS workload passed1/1:7 daily reopens×4 real saves,9 retained versions,
182 encodes/462 reuse operations. Initial RW remount control differed8192bytes and was rejected.
Three byte-identical retained-image forks then used matched RW cycles and strictly RO measurements;
both no-op controls agreed16,207,872 bytes, deletion treatment3,645,440, **delta12,562,432 bytes**.
All24 stable readings/RO remount controls, Library hashes and original hashes qualify; every image
is detached. Includes APFS/delete metadata; NOT historical iPad or300–1000-cel extrapolation.
Evidence: `~/PaintWork/s52-saving-audit/week-cost/storage-forks-47d7079c/review.md`.

---

## Erasing strokes crashes on iPad — 2026-10-23

Owner: “a crash just happened on the ipad when i was tryiong to erase some strokes.” Test1, no
Liquify applied; black screen/loading spinner then Home Screen after normal Release bcd7a6af install.
Preserve the scene/backups. Diagnose the actual eraser/rendering cause before changing production.

Two matching-build system reports are now preserved: October23 at18:47 and23:03 Toronto time.
Both kill backboardd at1850MiB, with PaintSoftware active and no app kill reason. App memory/peak is
730.4/922.6MiB in the first and768.0/1248.6MiB in the second; both use installedF6102F9A UUID.
The owner recalls only one observed failure and cannot identify its time, so neither report is chosen
as its confirmed match. Allocation origin remains unproved. Existing flights end27–30minutes before
the earlier event and establish no causal link. New read-only device inventory/copies did not restart,
launch or install the app. Evidence: `~/PaintWork/s52-erase-crash/device-diagnostics/`.

A separate October24 disk-write diagnostic for the same build reports1.074GB dirtied over8h09,
**action taken:none**. Matching binary/dSYM symbolication points the dominant captured stack samples
to FrameBaker/FrameBakeStore; ordinary saves also appear.505samples were lost and sampling covers only
part of the interval: these are not byte shares, backup physical-storage cost or crash causation.
Preserve this evidence for measured follow-up; do not speculate a cache/backup fix from it.

Preserved Test1 has 4096², 527 strokes and no material data. Its To Cross eraser is Mode3: successful cuts
update the canvas base without a scratch preview. **Raw size 7.962 means canvas points, not 7.96% or 326px.**
Repeated canvas-sized UIImage/CoreAnimation handoff is a hypothesis to test, not a proven cause.
Mode3 capture1 passed1/1 with3 successful cuts and3 full4096RGBA assignments, footprint854–985MiB;
root inspected2 pictures. Capture2 stopped before gestures at an added dark-pixel premise. Capture3
passed1/1 but its temporary clone disappeared before recorder collection, so exact cut/render counts
are unavailable. Simulator footprint does not prove backboardd behavior. Original scene and source
hashes are preserved. Evidence: `~/PaintWork/s52-erase-crash/mode3-diagnostic/`.

- [ ] Correct the reproduction premise and trace successful Mode3 cut/image ownership with bounded
      diagnostics; preserve actual geometry and avoid a speculative production fix.
- [ ] Establish the allocation cause and reproducing regression, then run the required gates.

---

## Mend fill gaps beneath interior brushstrokes; apply across a layer — 2026-10-24

**Latest scope ruling, 2026-10-25:** “All i know is that the mend gaps stuff is only required for
vector if that helps.” Kevin says this implementation choice does not require approval and asks us
to continue while he sleeps. Use current vector brush geometry for interior mending, protect uncertain
joins and keep fast feedback; unknown flattened content remains conservative. Preserve the existing
neighbor seam. Do not ask this capability question again.

**Implemented and installed; final performance/merge gates remain.** Shared brush-renderer support
replaces the tiny-cap path whole. At83380, Fill126, wholeFillMendUI4 and29 deliberate controls qualify;
root inspected6 actual whole owner-size pictures, including attached/detached/full caps and batch
Undo/Redo. Outer outline/uncertain joins remain protected. No new raster storage is introduced. Owner reports: “when I fill
stuff, the fill leaves white in places where brushstrokes were.” An enclosed filled region can contain
an internal brushstroke whose footprint stays unfilled. Extend the **same Mend Gaps setting** to cover
those interior stroke-shaped gaps as well as its current behavior. Preserve the actual original outer
edge: a naive expansion that crosses the fill boundary is explicitly rejected. Reuse the existing fill
geometry, retained source and mending calculation rather than adding a parallel fill mechanism.

Owner also asks for **a new layer action that applies Mend Gaps to all fills in all cels of that layer**.
**Owner ruling2026-10-24: include interior strokes attached to the outside outline, while preserving
the outside edge and avoiding side effects.** The fully-enclosed-components-only restriction is
rejected; do not silently ship it as full coverage. **Further owner ruling: protect uncertain joins**;
do not infer the hidden covered outline. Attached stems still mend; ambiguous overlap can remain.
**Performance requirement:** filling must retain real-time, quick visual feedback. Reuse cached
preparation and bound any new work; avoid expensive full-image CPU analysis on each interactive tick. Scope illustration: `~/PaintWork/s53-fill-mend/design/connected-stroke-scope.png`.

**Owner ruling2026-10-24: this action is vector layers only.** Raster fills are flattened into paint and
are not individually identifiable; no raster storage redesign is authorized. The per-fill mending
correction still uses the shared raster/vector fill pipeline. Use the same setting/semantics as an
individual fill; inspect existing batch edit/undo/save patterns.
Core, vector batch and compact shared contours are implemented. Default-Overlap sampling, Reach-after-
Overlap, refused-rebuild invalidation and exact own-fill reference exclusion are fixed and qualified.
At265e588e, focused206 passed before/after22 assertion-red faults with exact723-source restoration;
preserved earlier faults bring distinct qualified recipes to35. Debug AND Release each5278 reconcile.
Old/new masks match six fixtures×five widths;12 Reach stress cases and fragmented archive gate pass.
New fill and Mend All Fills cold UI2/2 pass at6bc20170, with owner-size whole-screen pictures inspected.
Ten other current workflows pass. The corrected full FillMend class passed4/4 at071c7eb2, followed
an actual visibility assertion-red control, then restored normal4/4;723 files+modes exact and five
owner-size whole-screen pictures inspected by root. The old driver failures are resolved, not product
layout defects. Worktree `~/PaintWork/PaintApp-s53-fill-mend` retains the exact earlier evidence.

- [ ] Final integrated regression/performance gates; preserve qualified83380 drawn/control evidence.
- [ ] Resolve the uncertain inside-press timing difference with paired baseline runs; no device extrapolation.
      Targeted follow-up `tmp/s54-fill-demand-map` now defers unused exact open-feature work until
      enabled Reach, retains one map per Structure and invalidates before independent mend writes.
      Its three normal regressions are included in root's500/500 at59d69f12 (724 files unchanged).
      Lazy-fill normal regressions and base49 controls are qualified in the dependency; final fast
      tiers and paired old/lazy Release ABBA still remain. Sixteen earlier paired trials passed, with
      inside paired median delta+5.1ms; this is simulator evidence, not device timing or attribution.
- [ ] Qualify permanent startup/gallery readiness after removing the now-owner-confirmed temporary converter.
      Retire its obsolete old-library converter gate; preserve pre-conversion exports and current-format tests.
- [ ] Final qualification/merge; current250-package export, signed6fb install/normal launch and owner
      artwork confirmation are complete. Any further device restart requires fresh saved-scene readiness.

---

## Repository-wide architecture, cleanliness and performance audit — 2026-10-24

**Active, source consolidated; final qualification and file-review gaps remain.** Owner asks for a
thorough audit: “codebase cleanliness and good architecture as well as performance is a priority”,
“refactor things that are messy and also find and fix bugs”, “Zombie code or bloat … should be dealt
with. Dont be afraid to prune.” Trace actual consumers before changing them; reuse one existing owner
or seam, remove superseded paths whole, and measure claims. Real scenes contain300–1000 drawn cels:
design around a window/byte budget, never load it all. Deferred features stay deferred.
Kevin reiterates October26 that fixes must address root causes and preserve good architecture;
remove superseded owners/paths instead of stacking workarounds. Independent review and actual
regression evidence support bounded confidence, not a claim that every fix is certainly correct.

The18 current finding headings and file-level gaps are in docs/ARCHITECTURE_AUDIT.md; the old19
index also counted the now-retired temporary converter. Current statuses replace historical pending notes.
Inventory-only files are not reviewed code. New source is not called complete because it is committed.

- [ ] Data protection/background: finish final-source gates for strict migration/Trash ownership,
      export cancellation, serialized cleanup and close-owned thumbnails; retain the qualified controls.
- [ ] Triage current compiler warnings by ownership: distinguish pure-value isolation mismatches,
      real background actor access, missing awaits and deliberately synchronous media reads. Actual
      Video normal11 log has259 warning occurrences,182 distinct location/message rows; not182bugs.
      Do not silence warnings with blanket unsafe annotations or change scheduling without tracing
      callers. Unused locals may be pruned after confirming their initializer has no required effect.
      Source/independent review accepts a bounded first patch: only existing package serializer
      queue/key/functions, lock-owned RasterStorage/RasterResidency and pure/locked CompositorBudget
      get explicit nonisolated boundaries; remove the unused PoseBake startFrame and estimate-only
      Onion canvasMP declarations whole. No bodies, locks, scheduling, protocols or policies change.
      Root reviewed core6 patchbb437dce before implementation. Its Debug app+UITests build succeeded
      with0 tests, exposing candidate-interface warnings. The three-prefix successor07a was
      interrupted on new cache/factory warnings (operator cancellation, not completed compiler
      failure). Both annotation candidates stay UNHARVESTED: the coherent pixel/primitive boundary
      is larger and no runtime defect is proved. Keep the source triage; the two dead-local
      deletions are harvested alone ate88a25ab. Finish drawn-workflow gates before considering a wider isolation migration.
      No automatic cascade, blanket namespace opt-out, new locks or actor hops.
- [ ] Finish current-source Tap combined checks. The canonical correction3219c8b4 is integrated;
      historical logic37 and UI6+benchmark1 passed at75607279, root inspected three pictures,
      and17 actual mutations exposed23 accepted logic assertions. Release evidence is one benchmark,
      not a whole tier. Later relevant files changed; current normal/Release gates remain. Do not
      rerun the historical15-control proposal as though it never executed. Reconciliation:
      `~/PaintWork/s55-recorded-regressions/menu-card-and-tap-status-20261029.md`.
- [ ] Qualify source-integrated removalec62d712 of geometry repair and converter-only UI/tests/fixtures/PBX paths: Kevin
      confirmed current scenes “Looks right” after the preserved250-package export and signed6fb
      install/normal launch. Keep permanent startup maintenance scheduling, truthful gallery readiness
      and strict current-model validation. Retire obsolete converter-specific cold-library gates;
      retain current-format package/startup coverage. Whole source removal and permanent-owner regressions are integrated; native qualification remains pending.
- [ ] Bake recovery/close: existing baker/store/read demands share one authoritative source and checked
      admission; corrupt/missing/zero-byte derived files recover without permanent retry. Keep final
      headroom refusal and actual unlink failure coverage. Derived cache bytes are separate from source pixels.
- [ ] Mask budgets/video/vector undo: included in normal847. Mask planning prices transitive indivisible
      closure and retained mix slots; minimum-one-row exception stays explicit. One MaskResolver checks
      metadata cache before dependency pixels. Refusal never becomes an unmasked stroke; onion refusal
      cancels/hides stale frame/clip. Video reads use per-manager closeable clients, pressure trims ring
      and reader LRU, late work cannot land after close. Two held native samples/reader and private
      AVFoundation allocations remain separate from copied ring bytes. Vector costs count actual
      retained payload identity without copying/unpacking or persistent pointer caches; saturated costs
      propagate through existing UndoBudget/history. Preserve the qualified52-target ledger; finish final consumer UI/gates.
- [ ] Editable raster: one app-wide RasterResidency charges provider-owned source allocations and
      configured working/checkpoint reservations; native image aliases and unresolved snapshot leases
      keep their real charge. Explicit COW admits before mutation. Immutable version/backing handles
      serve raster/baked tiers, frozen recipes, undo and save; current-document compressed protection
      and dirty checkpoints use existing ProjectStore clone/PNG serializer, with owned stale-temp cleanup.
      No schema, backup-policy, parallel writer/cache,1000FD or eager all-cel hydrate. Staged affected
      cels preserve Liquify→fill→shape→text order, queued text, masks and drafts on later refusal.
      Planned-frame stroke tuple settles before recording then begins after playback/before spawn;
      patch/whole-cel undo preflight distinguishes admitted blank from failed reads and drops pins.
      Resize/flip prepare all outputs serially before fenced atomic install. Owner UUID+version keys
      include interpolation references; frozen snapshots reuse original owners. Tag04 changes only
      disposable .pbk digests. Original32 methods and5 finite-pass additions pass within normal430;
      qualified raster faults and the original broad-control limits are recorded in the current ledger.
      Full fast/cold drawn UI/landscape and remaining assertion gates remain. Counted ownership is not whole RSS,
      private ImageIO, derived compositor memory, placed-image/video ownership or Test1 causation.
- [ ] Stream: one completion-paced writer/run, bounded producer payloads,64MiB frame/256KiB chunk checks,
      old-connection callback fencing/join and error/stop settlement replace unbounded ownership.
      Final7c C#166 normal methods pass both configurations;16 assertion targets/15 recipes and4
      arrangement controls qualify, with63 source/fixture entries exact. Swift76 and the callback
      completion correction passed within normal1cf422/422, zero skips; final35 stream/fit/walk
      controls qualify at their selected mapped assertions; remaining assertion gaps and final-source/UI
      gates stay pending. Windows fake transcripts return synchronized snapshots. Real-link stage5 remains owner-waiting; no deploy.
- [ ] Bound discovery-name decoding at its existing Windows DnsName.Decode owner. Source72885a50
      lacks RFC1035's255-octet expanded-name/63-octet-label bound; compressed repeated questions can
      amplify work despite physical packet checks. Record finite255/256 and compression/Consumed
      regression before a minimal guard; preserve valid discovery/QU and the existing20jump limit.
      No giant exhaustion attempt, protocol service/cache/rate limiter or unrelated socket rewrite.
      Windows old19 completed15pass/4intended refusal failures; root originalTRX reviewf069c555
      accepts3canonical refusal sites and exactsource/IDs. Native exit capture remains unknown;
      no green/exit1 claim. Minimal existing Decode correction is source-authorized; normal whole
      Debug/Release/meaningful controls and exact-child closure remain. Actual attack/latency/RSS
      is unmeasured; no giant resource test or live malformed packet is needed.
- [ ] Brush/editor: bounded8MiB actual-image preview LRU and keyed row result replace unbounded/unkeyed
      retention. Final823e proof distinguishes exact2 vs2.25 scale within one old rounded bucket and
      checks actual requested600×120 pixels. Shared PaletteColor rejects malformed persisted hex rather
      than silently displaying black; normal strings are byte-preserved. Brush/palette logic passed within normal1cf422. Cold A→B→A drawn row and typed-colour
      recovery methods individually passed/LOOKed in676 (whole73 was67pass/5fail/1skip). First29/gap8 fault qualification covers all53
      selected brush/palette/metadata/curve assertions. Final-source whole UI classes remain pending.
- [ ] Curve editor drag: sourcecf184033 is integrated. Existing moving returns the authoritative
      landed frame with the updated curve, so clamped continuation cannot freeze or retarget a neighbor.
      Two logic and one drawn landscape UI method added; the selected logic/fault assertions qualify
      in the first29/gap8 ledger. Final full UI class still must preserve brush response/channel behavior.
- [ ] Stroke path/heading: exact redundant stationary chord-scan bypass and LiveWalk prefix draining
      retain all samples/channels and floating-point timing order. Naive coalescing was refuted by a1ULP
      counterexample; O(N) input storage remains. Qualify new controls/faults/drawn parity and measure
      any performance claim. No interpolation overhaul is authorized.
- [ ] Test hooks/obsolete runner: destructive reset/corruption seeding is simulator-only even in Release;
      use direct existing platform fact, no policy wrapper. Verified unused parallel_test.sh removed.
      Ordinary simulator UI/device compile and final static gates remain pending.
- [ ] Newly traced Mode1 eraser handoff: preserve the already-minted gesture seed through existing
      VectorCanvas.erase/hybrid punch and universal commit. Actual pixel/undo/archive qualify at260/seed5; new coldMode1 source59a3 is harvested,
      public runtime/wholepictures pending. Do not attribute the owner's Mode3 respring to this independent issue.
- [ ] Finish text final combined checks. Full UTF-16 style restoration is integrated;31 actual-view
      checks and two reverse faults qualified earlier. The cold public Select All/colour route now
      passes with a grip-clear fixture. Touch-down ownership fixfccc06db removes false repair notices
      without timers/state; wholeowner29+Text5 passed before/after two controls (three direct targets),
      with native menu and both red words inspected. Actual induced stranded-repair recovery is not
      claimed; landscape menu-continuity fixture remains separate.
- [ ] Resolve actual current graph gesture delivery and landscape menu continuity without
      weakening product oracles, then fresh whole-class runs and whole owner pictures.
- [ ] Current saved text omission/null defaults: source reportb6582fb1/receipt133f2e95 shows a
      required string can become empty without existing text-damage/save gating. Peer/scope accepted;
      remove saved required-field fallbacks through existing owners, preserve API defaults/explicit
      empty/legitimate nils. Current writer equals previousafd; no invented blank repair/schema.
      Actual previous-writer four-file46680B package provenance and strict-decoder controls are
      qualified. Temporary capture changes are removed; the original export contains no text.
      Cold Cancel→Versions→UnsavedRestore and exact displaced Trash bytes remain to qualify.
- [ ] Graph/capacity: shared resolved-destination/net-child admission is integrated at8e80; actual155
      normal and original42 deliberately broken contracts qualify. Capacity24follow-on qualifies all41 further contracts; public cold6ef
      remains open and four further outcome limits stay recorded. Keep proper-descendant semantics and
      one resolver; no renderer truncation, fake IDs, duplicate state or new rollback service.
- [ ] Effects numeric domains are component-qualified:5a63/63+13safecontrols, ec50CRT116/116+
      13safecontrols; exact root harvests retain original CPU/oracles/tolerances/global flags. Curve
      narrowing8272 passed94/94+6safecontrols and is harvested868. Final assembled Release/cold UI/
      paired output-verified cost remain; no unsafe old cast or Test1-cause claim.
- [ ] Correct confirmed affine-gradient colour-field transport through existing transformed(by:).
      Actual9dd native Freeform/independentCTM mismatch39 exceeds predeclared2; all other outcomes/
      premises pass, rootLOOK2. Retain two points/API/schema, ordinary/singular/coincident contracts
      and separate projective/lattice approximation. Commit, meaningful controls and public drawn
      stretch/Undo/Redo/whole class before qualification; no new gradient subsystem.
- [ ] Finish file-level/independent review, new affected zero-skip baseline, actual assertion mutants,
      exact final fast Debug/Release, lints/PBX/graph, cold workflows/pictures and paired performance.
      Then fresh owner save/unlock/export, signed clean Release/device checks and actual eraser cause.
      Owner now permits review installs at agent discretion; preservation/signing/actualdevice gates remain.

---

## (27) Stream the computer's screen as a layer

**Status** — briefed 2026-09-13, designed the same day ([STREAM.md](docs/STREAM.md)), and **built through
stage 4 the same day**: the Windows streamer (`streamer/`, installed on the laptop as the `PaintStreamer`
task), the iPad stream layer, the bar with Freeze / Bake Frame, files both ways. On the owner's iPad.
What remains is stage 5 — proving it on the real link with the owner at the laptop — and the one
device figure §5.3 asks for.

**The owner's brief, 2026-09-13, verbatim in the numbered points:**

1. *"The purpose of this feature is to be able to stream my windows computer's screen as a layer live
   on the app. The example use case is that the user will open up blender on their computer, then
   rotoscope a character, move the camera around in the computer, then continue rotoscoping, etc."*
2. *"This feature will require another app that is to be installed on my windows laptop which will
   stream the video to the Ipad."*
3. *"The windows app should also have a drop box for videos or images which when they are pasted into
   or uploaded, will appear on the app via the import video or image feature. If it is also possible,
   make the ipad app able to export to the windows app and save to the laptop."*
4. *"In the app, the stream tool should be under actions, and like a video it makes its own layer with
   the stream object inside of it."*
5. *"When the user is actively on the layer, there should be an options bar (the same kind as move or
   lasso tool), and in it should be the option to freeze the stream, or to bake the current frame. When
   the user presses bake to frame, the current frame in the layer is split as a new cel, and in that
   cel will be an image of the screen when it was baked. For example there are 4 frames and the stream
   layer has one cel stretching the 4 frames. The user is currently on cel 2. Once they hit bake, the
   cel will split into 3 cels: frame 1, frame 2, and frame 3 to 4. the cels in frame 1 and frame 3 to 4
   will not change. However, the cel in frame 2 will have the stream object replaced with an image
   object containing the snapshot of that frame."*
6. *"The paintapp streamer should be low latency and should not lag the main thread. Running it in a
   background thread might be smart, your decision. Note that for the most part, the computer side
   wont move."*
7. *"Just like a video layer, the user should be able to move the stream object in the layer using the
   move tool. The architecture for this is already well established."*
8. *"Note that the user may potentially use many screens or just want to stream a specific app."*
9. *"Note, this part is for the far future. I eventually intend to make the paint app compatible with
   windows, and thus there is the idea that instead of having a separate app, the paint app itself
   contains the streamer. This is a far off feature, but in case the two apps eventually merge, put
   some thought into the design of the architecture of the computer side streamer app. Better to plan
   ahead for potential future changes."*
10. *"There is the case the user may actively stream, then turn off their computer and continue on the
    app, then turn the computer back on and continue streaming."*
11. *"stream layers actively moving do not have to be rendered."*
12. *"The laptop that I want the streamer app in is not this mac but my windows computer. You should
    see it through tailscale."* — it is `desktop-cbr0fl6`, `100.104.85.111` on the tailnet; the iPad is
    `100.70.220.4`. SSH on the Windows box was **closed** on 2026-09-13 and needs the owner to enable
    OpenSSH Server before any Windows-side work can happen from this Mac.

**What is left** — STREAM.md §7 stage 5
- [ ] The owner streams Blender from the laptop to the iPad and rotoscopes over it; source switch,
      window close, laptop lock and reboot behave as STREAM.md §4.5 / §2.8 say.
- [ ] End-to-end latency MEASURED on the real link (a clock on the laptop screen beside the iPad);
      bitrate/GOP tuned if it needs it; numbers into PERFORMANCE.md.
- [ ] The redraw tick's cost MEASURED on the iPad (STREAM.md §8 names the outlet: the
      `ScreenStream` log line or the bar's `streamBar.tickSummary` marker).
- [ ] Owner-verified: Ctrl+V of a bitmap into the drop box (not exercisable over SSH).

---

## (22) Select multiple cels at once

**Status** — not started, and **deprioritised by the owner 2026-09-07**. The menu row exists and is `.disabled(true)` with an empty action; no
cel-selection state exists. The keyframe half of the same idea is real and shipping.

---

## (10) Linear light as an option on the blend mode

**Status** — not started, and **deprioritised by the owner**.

No colour-pipeline setting, no sRGB/linear enum, no transfer LUT, no `Composite.metal` change.

**One adjacent strand did ship**: `ColorMath`'s sRGB↔linear and Oklab conversions feed the gradient
map, which is this item's own "Oklab still gets built, for interpolation" half. The code calls that
**(10a)** in eight places, corrected 2026-09-07 from a stale count of nine — `Effect.gradientTable`,
`EffectSection`, `ColorMathOklabLogicTests`, `EffectParityLogicTests` and `tools/oklab_ramp_ab.swift`
among them. It is finished, so it left this file by the merge rule and the citations stand; see the
convention above.

---

## (37) The brush engine — one stage, and the owner has dropped it

**Status** — stages 0 through 11 merged. **Stage 12, the importers, is dropped for now by the owner**
(2026-09-06: *"skip the importer for now"*), so there is nothing actionable in this item today.

Twenty brushes in five groups with every asset generated and no third-party content; opacity and flow
split with a per-stroke buffer; canvas-anchored texture; the brushes menu and the full-screen editor
with orderable module chains, noise octaves and second inputs; relocatable storage; two-axis scatter.

**Left, when the owner wants it**
- [ ] Stage 12 — the `.abr` / Procreate `.brushset` / Clip Studio `.sut` importers. All three are
      undocumented and reverse-engineered, so the stage opens with a survey against real files, not
      with a parser. Test files are a real dependency. §2.21 makes it an **adapter** onto §6's
      modulation matrix rather than a bitmap reader.

**Owner-side, not ours**: their tuning pass over the other nineteen presets, and driving a real Pencil
to exercise tilt, which no test here can reach. BRUSH.md §13 has **nine** genuinely open questions
(recounted 2026-09-07 — the sixteen bullets split seven answered/closed, nine still open; the "eight"
recorded here was a miscount on the day this line was written, not later drift). Three of the nine
were offered on 2026-09-06 and declined; which three is not recorded here and could not be verified
against a transcript this audit does not have.

**Spec** BRUSH.md — **§2 is thirty-three owner rulings.**

---

## Later — the long-term features

**None of these are designed, and each needs its own conversation with the owner before it starts.**

- **(28) Audio.** Its stated blocker is **gone** — `PlaybackClock` is a drift-free wall-clock frame
  counter on the model, delivered by RENDER stage 1, which is exactly the hoist this item said it
  needed. `AVFoundation` is linked (for video), though no audio playback code exists.
- **(30) Video editor.** Its RENDER dependency is met — (29) shipped in full on 2026-09-06.
- **Interpolation overhaul.** Owner, 2026-10-22: "Interpolation will probably be overhauled sometime
  soon so it works better. I'll let you know in the future." Await that design conversation; do not
  research or implement an overhaul now.
---

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.

**Recording-cost audit follow-up — source hypothesis, October29:** raw input-rate history is an
explicit recording requirement; linear sample retention alone is not a bug. The current scalar and
Move-box capture methods copy the `RecordingTake` value, mutate its dictionaries/arrays and write it
back, which may force a full sample-buffer copy per event. Investigate actual backing-buffer changes
at unchanged capacity with the existing injected clock before any optimization. Preserve source-rate
capture, timestamps, eight pose channels, rotation unwrapping and target/stop ownership; no frame-rate
downsampling, new cache/counter/service or latency/crash attribution without evidence.

**Fresh owner readiness and stream timing, October28 evening:** owner confirms current work saved
and iPad unlocked NOW, authorizing restart/export of affected Test through installed PaintApp's
existing ProjectExport. Prioritize this unlocked window; no install/build is requested by this
readiness. Owner clarifies streamed picture separates after release or Set Down, matching the
prepared placement-correction timing. Record export provenance and preserve all originals.

**Conditional OnTop Move handoff, October28:** source trace finds a mixed-lifetime risk, not yet a
measured visible failure. Successful vector Move commit holds the already-shown float together with
its OnTop stream surface; the vector base can land without that stream, retire the held picture by
revision, and precede the next host surface's successful draw. Add one cold public OnTop Move-to-Brush
continuity witness using the existing 5000 ms window-draw seam and normal vector rendering. Keep In
Place's global composite ownership unchanged. No runtime lifetime change until the witness proves a
gap; then reuse the surface's existing presentation completion/ownership boundary rather than a
global acknowledgement cache.

**On Top reference handoff boundary — October29:** source tracing shows the new held Move group
contains both vector ink and frozen On Top stream windows, while its retirement currently follows
the reference-free ink base alone. A fresh host stream surface may still be drawing when that base
lands. In Place has its own retained global display and is outside this path. Add one cold existing-
stream-helper witness with a fixed5000ms window draw seam and normal vector base; require real red
pixels at the moved hull before tool exit, capture every phase before asserting, and require final
green. No periodic fake-frame loop. The test-only source373 is prepared/unrun; no new runtime fix or
global acknowledgement state before actual evidence. Prefer retaining each original window's front
through its existing presentation completion rather than mixing two retirement lifetimes.

**Current qualification snapshot — October29, integration `0d4b2b3e`.** The recording four-path
harvest is integrated; Debug75/Release75, two intended copy controls, and `RecordingUITests` 4/4
passed at their component pins, with both landscape captures reviewed. Stream placement and Move-exit
corrections are integrated; `StreamPlacementUITests` 9/9 and the normal1 rebuild passed at the
recorded component pin. Assembled-source and device confirmation remain for both.

The private Export/Resize/Gradient candidate `219790247dc684df1ec1182a7a45c0c2cd3daa95` has a
strict731-source baseline of179/179 and nine root-reviewed pictures. Controls1–6 have been reviewed;
the remaining eight controls are active under the root native lease. No harvest or assembled-green
claim yet. Follow the live lease and grant files; do not repeat completed component gates.

The fresh Test diagnostic is being repinned after source494. Until the root updates it, use
`/Users/juliapark/PaintWork/s54-final-qualification/root-next-gates.json` as the locator for the
current diagnostic map; do not freeze an older diagnostic pin as latest. Keep the fresh Test and older
Test1 inputs immutable and preserve the copy-flight evidence before teardown. Test1/Mode3 physical
cause remains unproved and needs fresh readiness.

The historical Mend-cap result is superseded by the connected-stroke/Mend All Fills work. Exact
canonical square-hole verification remains pending; do not credit the older cap pictures as proof of
that case. Disk maintenance recovered3.116GB with12,578 archived app-data entries preserved.
