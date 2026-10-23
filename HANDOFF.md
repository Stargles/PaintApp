# Handoff

<!-- Current state and next step only. Detailed rationale belongs in specs, evidence and history. -->

**Start here:** read [AGENTS.md](AGENTS.md), then this file, [CLAUDE.md](CLAUDE.md), the relevant
specification, [TODO.md](TODO.md) and [BUGS.md](BUGS.md). Verify origin and every tmp branch before
trusting main's handoff. The active worktree is `~/PaintWork/PaintApp-s49-integration`, branch
`tmp/s49-integration`.

## State — 2026-10-23

Main is `5e93bf0`. The iPad still runs the recovered main Release `17b438c` (app source `840d68a`);
the owner confirmed it opens. The verified profile expires 2026-10-30. Renewal repair aligns
clean/build arguments, fails closed on clean errors, verifies the seal and requires five days of
profile life. Nine isolated deployment scenarios and four mutations passed. Evidence:
`docs/bug-evidence/auto-resign-2026-10-22.md` and `~/PaintWork/s50-recovery/`.

**Liquify is not merged or installed. Simulator qualification is complete.** Final app/test source
was frozen for fast3 at `2b330c9`; later commits through `09af7c6` change documentation only.

- Fast Debug and Release: each5282 total,5278passed,4skipped,zero failures, reconciled against256
  selected classes. Evidence: `~/PaintWork/s50-liquify/fast-3/`.
- Full Release:5864 total,5799passed,3failed,62skipped,398 classes, exact census reconciliation.
  All three reds passed together unchanged serially:3/3,zero skips/failures. They concern two
  StreamLiveEngaged methods and LayerPanelControls mover visibility; exact parallel causes remain
  unproved, no product/test fix was made. Four actual workers, zero System Failures/restart/crash
  blocks;753 app/test/project hashes unchanged. Full command4751s,17970.666 class-seconds.
  Evidence: `~/PaintWork/s50-liquify/full-release-{1,serial-1}/` and `full-release-closeout.txt`.
- All8 Liquify UI methods passed in that full run (vector/linked3,raster5). Earlier isolated Release
  runs also passed8/8. Root inspected reshape/reopen/source-follow pictures and settled landscape
  controls at native iPad9 size; Documents copies41/89/5 files are hash-verified under
  `~/PaintWork/s50-liquify/release-ui/`. Every owned qualification simulator/clone is deleted.

The earlier Debug linked workflow really missed its15s picture deadline; it is not relabelled green
by Release qualification. No gesture, timeout or predicate was weakened. Its temporary instrumentation
is byte-exact restored; diagnosis: `~/PaintWork/s50-liquify/linked-ui-diagnosis.md`. The raster cold
workflow's unasserted mid-rotation photo tail was removed at `0cabd6c`; the valid reopen capture and
all assertions remain. Two malformed identity fixtures were repaired at `621c15d`/`b244a46`, preserving
every original assertion. Each focused baseline/restored gate passed2/2 and the deliberate identity
omissions caught the intended failures; production files restored byte-exact. Evidence is indexed
under `~/PaintWork/s50-liquify/{identity-fixture-20261023T012438Z,digest-fixture-20261023T014918Z}/`.

## Physical gate in progress

The architecture agent owns native/DerivedData for **build/staging only**, from clean `09af7c6`.
Exactly8 test files are temporarily adapted, no app/project changes: the existing guarded five-file
legacy patch, two unseeded Liquify methods and the native sampler benchmark. Exact backups, hashes,
diff and build evidence: `~/PaintWork/s50-liquify/device-build-1/`. It must restore all8 files byte-exact
and verify original753 source hashes/clean tree before handback. Root commits documentation only.
No physical test, candidate install or app launch has occurred.

Xcode lists the named iPad eligible: hardwareUDID `00008030-000151492EC3C02E`; devicectl identifier
`E3B83820-DF74-5042-B52B-0D5BA17E4877`. A passive preference transfer timed out, and one details refresh
returned a disconnected tunnel; backup coverage is unconfirmed. Artifacts and the reviewed two-method
patch: `~/PaintWork/s50-liquify/device-preparation/`. The owner last confirmed the Mac is free.

Next:
1. Finish the named-device Release clean/build-for-testing with identical common arguments; clean
   failure stops the job. Verify app/runner seals and five-day profile life, freeze product hashes and
   xctestrun metadata, restore all temporary sources. No install or launch during staging.
2. Obtain fresh saved/unlocked iPad readiness. Before install/launch, copy preferences and check
   `PaintApp.projectLocation.bookmark`. If absent, the library is in container Documents; if present,
   establish a verified external-library backup too. Copy/hash all current Documents and actual
   Projects/Backups/Trash coverage. Never reset libraries/settings or choose a storage invitation.
3. Against the frozen products, run the one native cold/warm C benchmark FIRST and ALONE, then five
   legacy UI drives and two unseeded Liquify drives separately: expected1/5/2,zero skips. Preserve
   screenshots and disposable-scene identities. Inspect six native PNGs and full UI screenshots.
   This measures native production-path cost, not app gesture latency. Existing fifth legacy drive
   checks actual transformed raster drawing; no C-specific app latency counter exists.
4. Build the final restored Release with matching clean/build arguments, verify seal/profile again,
   install and launch normally. Keep one-shot repairs until the owner confirms real scenes. The final
   executable's new repair signature converts older preserved preupdate snapshots too; its own newest
   snapshot intentionally remains untouched. Prior-writer round-trip/fault evidence:
   `~/PaintWork/evidence/s49-liquify-material-{format,model}/`.
5. Only after physical qualification, remove TODO(178) whole and the completed freeze-log-read entry,
   update SESSION_LOG (last5), recheck TODO/HANDOFF, ff-merge via the absolute main worktree path,
   verify merged SHA, push and clean up the task worktree. No unqualified Liquify deployment.

## Architecture and cost evidence to reuse

Ownership cleanup `c78aac8` consolidates the sole-consumer generic presenter with `LiquifyProcedure`;
the wrapper is gone. Existing synchronization/cancellation/single-producer behavior remains. The
spatial material renderer is integrated through VectorCanvas with tile-scoped work; cleanup adds no
renderer/cache. Do not remove useful feature-scoped state simply because one feature owns it.
Focused Debug cleanup gate25/25: `~/PaintWork/s50-liquify-producer-check-20261023T004538Z/`.

Quiet optimized simulator producer gate2/2 passed at `7e780d7`: all8 pictures exact, all18 frozen
inverse fixtures match. Retain batching: hard/pattern medians0.173/1.868s,19.1%/23.3% of scalar cost.
The patterned worst case remains seconds; no device speed claim. PERFORMANCE records scope and C's
bounded sampler evidence. Physical C first-use cost remains open. Evidence:
`~/PaintWork/s50-liquify/producer-release-1/`. Reuse unchanged material55/55, storage115/115,
model13/13 and required-picture refusal4/4 plus fault/restoration records in
`~/PaintWork/s49-liquify-logs/`; don't repeat qualified slices without new evidence.

## Other queue state

The freeze-log request is complete: six October16–18 repair flights correlate via exact executable
stamp to Releasef813346/app840d68a, before Liquify.346 deduplicated sequences include340 controls and
6 repair hits, not6 proven visible freezes. New Pencil/cancel cases disprove a universal late-third
fix; no common cause established and no behavior change. BUGS.md and `~/PaintWork/s50-freeze-logs/`
hold reproducible findings. The optional owner question about visible freezing versus a repair
message does not block Liquify.

TODO(27) laptop verification is owner-deferred; (22)/(10) deprioritised; (37) importers dropped.
Audio(28), video editor(30) and the future interpolation overhaul await owner briefs; do not research
them now. (179) is complete, including six physical probes in PERFORMANCE §30.7. Budget already
permits useful agents; prioritize usage/quality over speed. No new budget question is needed.
