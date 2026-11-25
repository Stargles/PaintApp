# S1 worker notes (tmp/nov25-s1) — delete at merge

Simulator: own iPad 9, UDID in ~/PaintWork/nov25-s1-evidence/udid. Evidence: ~/PaintWork/nov25-s1-evidence/.
Owner ruled Q1 (2026-11-25): keep the previous frame until the new one is whole. Rebase before reporting.

## Done
- M1 probe: `Debug/FrameStepCensus.swift` (`step:` on canvas.host), hooks in goToFrame, FrameBakeStore.read,
  CanvasView baked-frame draw. `FrameStepUITests` (cold start owner's scene, slow + burst steps, never a mix).

## Next
- Run FrameStepUITests on old code (M1 before numbers) -> evidence/m1-before.txt
- Scheduler core Engine/Scheduling + Platform/Apple*, VirtualExecutor tests
- R1 frame reads, delete InteractionGate, presenter, settle
