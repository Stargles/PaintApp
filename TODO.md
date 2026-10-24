# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what *we* find.

**Session 49 (2026-10-14):** the owner asked to continue through every actionable item, stopping only
for genuinely required input. On October24 the owner explicitly says not to park for context: rely
on automatic compaction and keep working. Agent count is unrestricted for now; usage
conservation and output quality take priority over speed. Use focused delegation and cheaper models
for routine work, with occasional queue reports. The owner asked to work independently while asleep
until 10 a.m. Toronto time. The later point-only vector ruling below supersedes fixed exterior pixels.

**Checkpoint2026-10-24:** point-only Liquify/newest retention remain unmerged and not installed; their
logic, affected UI and saving-cost gates qualify. Fill core focused206 and35 distinct fault recipes
qualify; Debug/Release each5278=5274passed+4known skips. Six old/new fixtures×five widths preserve filled
masks. New fill/batch UI2/2 and ten old workflows pass; corrected full fill class is3/4, with an extension
slider-driver failure remaining. Audit has19 source candidates, two unqualified implementation branches. Startup repair took
11.013s on M5 before first UI; cold-start/scheduling work remains before install. Erasing cause remains
unresolved. Installed Release is stillbcd7a6af; no device launch/restart/install this pass.

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

**Verify a status before trusting it, including this file's own.** That same audit found fourteen
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

## Vector Liquify must move points only — 2026-10-23

**Active — continue implementation.** Owner explicitly rejects treating the architecture question
as a pause and reiterates that work must continue. Remove complex vector Liquify, keep point-position
editing through the normal renderer, and perform the thorough cleanup below. Owner also warns that
the earlier failures have damaged confidence; verify against the actual original instructions and
actual consumers, not inferred scope. Do not stop at recommendations or mark work done prematurely.

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
bake, raster Liquify, linked source following and the temporary saved-file repair. Final independent
review found no concrete architecture defect;328 app files remain byte-identical since the tested
production baseline. Repair75/75,13 repair mutants and copy-only242-survivor real-library gate qualify.
Final runtime338/338 and17 runtime mutants qualify (16automatic+one exact manual native-assertion review).
Final affected UI9/9 and required old workflows10/10 passed. The final old-code control widens the dot
1.918×; current code keeps it round. Root inspected the actual pictures. No held-path helper remains.

Final exact Debug AND Release each5259=5255passed+4known skips, zero failures/expected, all method
identities/255 classes reconcile. Corrected classes33/33 before and after2 assertion-red faults;
723 bytes/modes restored, lints/plutil/PBX1317 unique clean. The corrections remove obsolete placement
and oldest-plus3 expectations only; production and earlier338/17/UI proof remain exact.

- [ ] Fresh verified current-library export before signed device install; owner confirms real scenes.
      Keep the one-shot repair until that confirmation, then retire it whole.

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
also passed in runtime338; combined Debug/Release each5259 now qualify.

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

**Active — shared engine and vector layer action in implementation.** Owner reports: “when I fill
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
Ten other current workflows pass. Old47d reproduces the stale seam control failure; its extension
passes. With shared screenshot/visible-paper fixtures the full fill class is3/4: the neighbouring-fill
seam now passes with its OFF control intact, but the extension slider disappears after the test drag.
Diagnose that gesture/visibility failure and rerun; no product cause is assumed.
Worktree: `~/PaintWork/PaintApp-s53-fill-mend`, `tmp/s53-fill-mend`.
- [ ] Qualify all four FillMend UI cases after fixture/helper corrections; inspect whole-screen pictures.
- [ ] Resolve the uncertain inside-press timing difference with paired baseline runs; no device extrapolation.
- [ ] Resolve first-screen repair scheduling/cold launch before deployment (audit item below).
- [ ] Fresh saved-scene readiness/export, signed clean Release, device checks, owner artwork confirmation and merge.

---

## Repository-wide architecture, cleanliness and performance audit — 2026-10-24

**Active initial review; isolated refactor snapshots remain unqualified.**
Owner asks for a thorough audit of everything:
“codebase cleanliness and good architecture as well as performance is a priority”, “refactor things
that are messy and also find and fix bugs”, “Zombie code or bloat … should be dealt with. Dont be
afraid to prune.” Clean architecture should make future additions smoother and less error-prone.
The owner now permits a large usage budget but prioritizes output quality and regression prevention.

Audit the app and adjacent streamer in bounded areas. Trace actual consumers/ownership before pruning;
identify duplicated mechanisms, tangled responsibilities, dead paths, correctness defects and avoidable
memory or latency in real-time actions. Record concrete findings before changing them. Prefer shared
existing seams and root-cause refactors; do not add parallel frameworks or speculative optimizations.
Use independent reviews where useful, measure performance claims, and qualify each coherent change
with meaningful logic/mutation coverage, affected workflows/pictures and required repository gates.
Preserve real scenes and saved-format repair rules. Deferred product features remain deferred.

The current19-candidate queue and evidence are in [ARCHITECTURE_AUDIT.md](docs/ARCHITECTURE_AUDIT.md).
The two implementation branches are WIP (no native qualification), not finished fixes. Subagents hit
account usage limits; root continues. The full source inventory is not yet fully reviewed.

- [ ] Data protection: migration identity and Trash backup ownership; qualify library branch.
- [ ] Background ownership: export cancellation, save-stage cleanup and thumbnail close; qualify branch.
- [ ] Temporary repair: cold old-library launch, responsive first screen, then retire whole after owner confirmation.
- [ ] Rendering/storage: derived-frame recovery/close, masked source budgets, editable raster residency, video pressure.
- [ ] Stream transport: bounded ordered backpressure, framing limits, connection readiness/close ownership.
- [ ] Editor/brush: preview identity/budget, undo payload accounting, saved palette validation; verify stationary-sample opportunity.
- [ ] Test hooks/obsolete runners: protect real-device persistent data and prune only verified unused paths.
- [ ] Complete file-level review gaps, independent reviews and regression/performance gates before closing audit.

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
