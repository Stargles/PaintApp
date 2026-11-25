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

- Presenter wired (WindowSurfaceView parks; settlePresentation); cover/awaiting/presentFirst deleted; quiet 0.15 s.
- FrameStepUITests green: 5000² 39-94 ms, 2048x1024 18-27 ms, 0 mixes, 0 main decodes; old things test green.
- Mutations run: presenter isComplete (red), answer held by touch (Scheduler red), R1 as later + no behind
  prefetch (UI 182-196 ms -> threshold set 150). Playcheck GREEN (app peak 1140, backboardd 187).
- Rebased on 63269845 (owner Q1/Q2 rulings). Docs: SCHEDULER_DESIGN "S1 as built", SCHEDULER status, TODO 5.

- Fast tier Debug + Release: 5755/5755 run (= static count), 5751 passed, 4 skipped, 0 failed.
- Playcheck GREEN again: step 42 ms (app clock), probe 2.35 s; app peak 1143, backboardd 206. BakeWiringUITests 4/4.

## Next
- Nothing on this branch; orchestrator merges. Simulator deleted; evidence in ~/PaintWork/nov25-s1-evidence.
