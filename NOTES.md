# S3a worker notes (delete before merge)

Sim UDID in ~/PaintWork/nov25-s3a-evidence/udid. Baseline worktree ~/PaintWork/PaintApp-nov25-s3a-base (delete at end).
Baseline outputs: evidence/base-rapid.log, base-playcheck.txt.

## Done
- Job.group (serial group), Scheduler.waitUntilIdle(group:), lateByName stats, R1 capacity = max(1,P-1)+ceil(E/2).
- LatestWins(scheduler:key:...) lane (queue init kept for S2/S7 users).
- Moved: StrokeScratch, canvasPixels, liquify, fill (fillWork/waitForFillWork, fillGroup), shape/text previews,
  DeferredVectorRender (StrokeCanvasView.vectorRenders + edit surfaces). Pacing deleted pending measurement.
- Allowlist shrunk by 5 files. Fill tests: fillQueue.sync -> waitForFillWork.

## Next
- build, fix compile; logic tests for each moved job (virtual executor); mutation tests
- undo-storm A/B vs baseline (Pacing); playcheck; fast tier Debug+Release; docs (§6 as built, TODO item 5)
