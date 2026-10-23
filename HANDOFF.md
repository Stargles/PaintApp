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
Liquify procedure. No new cache, renderer or generic producer remains. Do not remove useful
feature-scoped state merely because one feature owns it; keep the existing synchronization,
cancellation and one-producer behavior. A focused Debug compile gate for `c78aac8` is running under
the separate agent; do not start overlapping native/compiler work.

The linked-frame diagnostic has finished and its temporary instrumentation is exactly restored. All
815 readable probes were sampled each poll; three changed before the 15.546-second timeout, and a
later still showed 141 changed. Preserve the gesture, predicate and timeout. The next test step is the
unchanged current Release gate after the focused compile gate completes; do not run another Debug
diagnostic for this symptom. Owner confirmed the Mac is idle.

The verified inventory is 5282 fast tests across 256 UI classes and 5864 full tests, excluding three
private static helpers. This is a census, not a claim that new final gates have passed. Material, raster
and storage/model evidence is indexed under `~/PaintWork/s49-liquify-logs/`: required-picture refusal
baseline/restored 4/4 with both fault batches caught; material 55/55; corrected raster refusal 3/3 after
one invalid fixture in the broader run; storage 115/115 and model restored 13/13. The accepted bounded
sampler C is integrated. Quiet optimized Release batching cost and sampler C physical first-use cost
remain open; prior Debug batching was slower than the scalar path, so make no speedup claim.

The five-method physical drive patch and native cold/warm sampler benchmark are prepared but not
compiled or run. Ordinary device helpers reset preferences and libraries; inspect the safe patch before
use. Get fresh saved/unlocked iPad readiness before physical work. Preserve screenshots and scene
packages. Existing physical and benchmark material is indexed under `~/PaintWork/s49-liquify-logs/`.

## Next

1. Wait for the focused `c78aac8` Debug compile gate, then run the unchanged current Release workflow.
2. Correct the existing modes/controls UI method: start in landscape before app launch, remove its
   end-of-test midflight rotation, preserve its assertions, and capture one final full-screen landscape
   image. Run it alone on a fresh native iPad 9 simulator so its long workflow settles rotation.
3. If the Release gate passes, continue final regression gates and measure optimized batching cost on a
   quiet Mac. Obtain fresh saved/unlocked device readiness before the prepared physical drives and
   cold/warm sampler benchmark; keep physical first-use cost separate from app gesture latency.
4. Keep Liquify out of the shipped app until required feature and regression qualification is done.
   Remove TODO (178) only with its fully qualified merge.

## Other queue state

(179) is complete; its six physical probes and limits are recorded in `PERFORMANCE.md` §30.7 and
`~/PaintWork/s49-device-probes/README-after-20261015.md`. The remaining queue is unchanged: (27) laptop
verification is owner-deferred; (22) and (10) are deprioritised; (37) is dropped; later features need
a design discussion.
