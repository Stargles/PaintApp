# Handoff

<!-- Current state and next step only. Record rationale and detailed evidence in the specification,
     evidence indexes, and commit history. Refresh this file when closing a pass. -->

**Start here:** read [AGENTS.md](AGENTS.md), then this file, [CLAUDE.md](CLAUDE.md), the relevant
specification, and [TODO.md](TODO.md) in queue order. [BUGS.md](BUGS.md) records discovered issues.

## State — 2026-10-22

Main is `5e93bf0`. The iPad runs the qualified main Release from app source `840d68a` (`17b438c`),
with a verified signature and embedded profile; the owner confirmed PaintApp opens. The profile
expires 2026-10-30. Renewal repair `5e93bf0` aligns clean/build arguments, fails closed on clean errors,
checks the app seal and requires five days of profile life. Nine isolated deployment scenarios and
four mutations passed. Evidence: `docs/bug-evidence/auto-resign-2026-10-22.md` and
`~/PaintWork/s50-recovery/`.

Liquify is not merged and is not installed. Its integration source is `tmp/s49-integration`, currently
at `c78aac8` for the ownership cleanup. That change consolidates the one-consumer presenter with the
Liquify procedure. The cleanup removes the generic wrapper and adds no renderer or cache. The spatial
material renderer remains part of the existing VectorCanvas path, with tile-scoped work only. Do not remove useful
feature-scoped state merely because one feature owns it; keep the existing synchronization,
cancellation and one-producer behavior. Focused Debug compilation and all 25 lifecycle/raster tests
passed at `c78aac8`, zero failures/skips; its owned simulator was deleted. Evidence:
`~/PaintWork/s50-liquify-producer-check-20261023T004538Z/`. Candidate `7e780d7` starts the existing
controls workflow in landscape and removes its end rotation; assertions are unchanged. A delegated
Release build succeeded and its quiet
actual-producer gate passed2/2, zero skips; all8 picture comparisons are exact and all18 frozen inverse
fixtures match. Retain batching: hard/pattern producer medians are19.1%/23.3% of scalar reference cost.
PERFORMANCE records simulator scope and remaining seconds-long worst case. Evidence:
`~/PaintWork/s50-liquify/producer-release-1/`.

The unchanged linked Release workflow passed1/1, zero skips: visible reshape, exact picture after cold
reopen, then new green ink following an edited source. Root inspected before/after/reopen/source-follow
images; the archived package retains one deformation on the linked recipe. All41 Documents files are
copied/hash-verified under `~/PaintWork/s50-liquify/release-ui/linked-1/`. The earlier Debug diagnostic
remains genuinely late (815 readable probes,3 changed until15.546s; later141 changed); no timeout,
gesture or predicate changed. Its temporary instrumentation is exactly restored. Owner Mac is idle.

All8 feature UI methods passed in Release across isolated linked1, raster/vector6 and native9
controls1 runs, zero failures/skips. Root inspected the raster dip after reshape and exact cold reopen;
native9 controls show the settled landscape toolbar, Size/Power and all3 modes unclipped. Evidence:
`~/PaintWork/s50-liquify/release-ui/{raster-vector-1,controls9-1}/`. Documents copies89/5 files are
hash-verified. The controls test itself passed; its post-run archive initially met Xcode's shut-down
simulator and recovered Documents offline without another launch. Both owned simulators are being deleted.
The raster cold test's trailing rotation/layer-panel toggles/photo are removed at `0cabd6c`: that
unasserted capture caught rotation midflight. The valid portrait reopen picture, settled native9
controls proof and every existing assertion remain. Source is frozen for final gates.

The verified inventory is 5282 fast tests across 256 selected classes and 5864 full tests, excluding three
private static helpers. This is a census, not a claim that new final gates have passed. Material, raster
and storage/model evidence is indexed under `~/PaintWork/s49-liquify-logs/`: required-picture refusal
baseline/restored 4/4 with both fault batches caught; material 55/55; corrected raster refusal 3/3 after
one invalid fixture in the broader run; storage 115/115 and model restored 13/13. The accepted bounded
sampler C is integrated. Sampler C physical first-use cost remains open. The earlier Debug batching
slowdown is separate from the now-qualified optimized simulator result; no device speed claim.

The five-method physical drive patch and native cold/warm sampler benchmark are prepared but not
compiled or run. Ordinary device helpers reset preferences and libraries; inspect the safe patch before
use. Get fresh saved/unlocked iPad readiness before physical work. Preserve screenshots and scene
packages. Existing physical and benchmark material is indexed under `~/PaintWork/s49-liquify-logs/`.

Keep the one-shot format repairs until the owner confirms real scenes look right. Run the final
executable's repair signature so preserved preupdate snapshots are converted too; the current
signature's own backup intentionally retains the previous format. Prior-writer package provenance
and fault/restoration evidence remain under `~/PaintWork/evidence/s49-liquify-material-{format,model}/`.
Linked timing diagnosis: `~/PaintWork/s50-liquify/linked-ui-diagnosis.md`. Final gate scripts and safe
physical patch: `~/PaintWork/s49-liquify-logs/combined/final/`. Final fast Debug/Release and full suite
have not run at the current candidate; run the full suite once at the phase boundary, then triage
failures serially as CLAUDE.md specifies.

## Next

1. Fixture repair `621c15d` keeps fitted lattices and every original identity assertion/case. Focused
   baseline/restored2/2 each; omitting identity groups fails exactly the two intended group/spacing
   assertions, with no unwrap failures. Production file restored byte-exact and guard unchanged.
   Evidence: `~/PaintWork/s50-liquify/identity-fixture-20261023T012438Z/`. The first final Debug attempt
   was interrupted1430/5282 (1427passed, one genuine fixture failure, one cancelled test, one skip);
   Release did not start. Rerun complete fast Debug/Release in a fresh evidence directory; never cancel
   a configuration merely because a test fails, let its result/count finish and stop before the next.
   Root owns running fast2 session2105 (`~/PaintWork/s50-liquify/fast-2/`). It has a further fixture
   failure in FrameBakeKeyLogicTests.testEveryDocumentFieldTheKeyCoversMovesTheDigest: acquired and
   retimed recipes have zero refs, so the new provider rightly refuses both. Arch agent's bounded scan
   found no more positive identity fixtures. Let Debug finish, then fix this row with two existing
   resolvable non-probe cels, preserve25 rows/assertions, and fault-prove omission of version.derived.
   No production guard change and no source edit while the configuration is running.
2. Run one phase-boundary full suite in Release to qualify the shipped
   configuration. Rules do not mandate a full-suite configuration; simulator test seeds remain enabled
   in Release. This does not relabel the known Debug linked timeout as passing.
3. Obtain fresh
   saved/unlocked device readiness before the prepared physical drives and
   cold/warm sampler benchmark; keep physical first-use cost separate from app gesture latency.
4. Keep Liquify out of the shipped app until required feature and regression qualification is done.
   Remove TODO (178) only with its fully qualified merge.

## Other queue state

(179) is complete; its six physical probes and limits are recorded in `PERFORMANCE.md` §30.7 and
`~/PaintWork/s49-device-probes/README-after-20261015.md`. The remaining queue is unchanged: (27) laptop
verification is owner-deferred; (22) and (10) are deprioritised; (37) is dropped; later features need
a design discussion.

The read-only freeze-log request is complete: six October16–18 repairs correlate via exact executable
stamp to Releasef813346/app840d68a;346 deduplicated sequences/340 controls. New Pencil/cancel cases
mean the old late-third proposal is incomplete; no proven common cause or behavior fix. BUGS.md has
the current qualified findings and `~/PaintWork/s50-freeze-logs/` has reproducible evidence. Remove
the completed log-read TODO entry when merging. Interpolation's
future overhaul is recorded in TODO Later and awaits the owner's brief; do not research it now.
