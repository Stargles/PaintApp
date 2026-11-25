# S1 worker notes (tmp/nov25-s1) — delete at merge

Simulator: own iPad 9, UDID in ~/PaintWork/nov25-s1-evidence/udid. Evidence: ~/PaintWork/nov25-s1-evidence/.
Owner ruled Q1 (2026-11-25): keep the previous frame until the new one is whole. Rebase before reporting.

## Done
- M1 probe: `Debug/FrameStepCensus.swift` (`step:` on canvas.host), hooks in goToFrame, FrameBakeStore.read,
  CanvasView baked-frame draw. `FrameStepUITests` (cold start owner's scene, slow + burst steps, never a mix).

- M1 BEFORE (evidence/m1-before.txt): decode starts 267-268 ms after every slow step (touch settle 250 +
  a frame), whole frame 324-347 ms (app clock), 8 main-thread decodes in 8 steps, 0 mixes sampled.
  Owner recording (evidence/owner): ruler scrub on a baked 2048x1024 scene, ringHit 0 / ringMiss 110.
- Scheduler core (Engine/Scheduling: Job, Executor+LanePolicy, TouchFlag, Scheduler) + Platform/Apple*;
  SchedulerLogicTests (VirtualExecutor, storm). InteractionGate deleted (touch flag in Scheduler).
- FrameBaker: R1 answer read (`requestRead`), no main decode, ring top-up on R2 lane (`topUpRing`,
  outward walk, +-1 when stopped). Baker logic tests updated (awaitImage). CanvasPresenter + logic tests.

## Next
- Run FrameStepUITests on old code (M1 before numbers) -> evidence/m1-before.txt
- Presenter into CanvasView: WindowSurfaceView parks swaps; delete coverTheHosts*/isAwaitingFirstPicture/
  presentFirst use; settle 0.5 -> 0.15
- FrameStepUITests on a small baked 2048x1024 scene too (owner's shape); after numbers; playcheck; fast tier
