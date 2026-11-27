# S3b worker notes — hand-off to the next agent (drop this file at the end)
Worktree ~/PaintWork/PaintApp-nov27-s3b, branch tmp/nov27-s3b from ac97b9a1. Own sim "nov27-s3b",
UDID in ~/PaintWork/nov27-s3b-evidence/udid (delete it when done). Evidence: ~/PaintWork/nov27-s3b-evidence/.

## Done (all committed)
- Engine/LayerPicture.swift: native vector picture repaired in place; reads fenced via direct-access
  CGDataProvider; per-revision UIImage wrapper (tag: LayerPicture.of / isCurrent); PixelPatch (budget-admitted).
- VectorCanvas: append/repair walk only the damage into a PixelPatch, commitInPlace copies it in (canvas lock
  only for bookkeeping; moved-on canvas keeps bases true; rollback if memo is this picture); >1/4 picture
  (inPlaceShare) or writeWait timeout -> old copy path. KeptPixels: replaced pixels kept per transition
  (storage identity + footprints), MemoryBudget-admitted, evictable entry, <=1 picture/16 per canvas;
  restoreElements -> .patch plan = copy-back, no walk (keptRestores). rasterizeLock DELETED -> walk turn
  (walkInFlight: join same/lower class, higher class pre-empts). Cancellable walks (per element/stroke,
  JobContext.current task-local bound by Scheduler).
- CanvasPictureView: draws a layer picture only at the revision it was handed.
- Fill: queuedFills (owner ruling Nov 26), landQueuedFills, fillCommitsOnLanding; Undo while a fill is drawing
  takes it back (takeBackDrawingFill), Redo spent. waitForFillWork/awaitFillRenderIfNothingProduced removed from
  app; test-only waitForFillWork in CanvasManagerTestSupport.swift. -uiTestSlowFillMillis seam, fillsQueued: field.
- Tests: LayerPictureLogicTests, InPlaceRepairLogicTests (virtual executor cancel/undo), FillGestureRestart queued
  tests, VectorRenderLock preempt test, QueuedFillUITests (UI, not yet run), InPlaceRepairBench (not yet run).
- Mutations: all new assertions reddened (mut1-4 logs in evidence). Seam/ui-identifiers/ui-helpers checks clean.
- Docs drafted: SCHEDULER_DESIGN "S3b as built", SCHEDULER.md status, TODO 5/6 — contain placeholders
  PLAYCHECK_RUNS (design), S3B_NUMBERS (TODO 5), UNDO_NUMBERS (TODO 6) to fill.

## Numbers so far
- Baseline main playcheck: GREEN, r1late 30 (layer_picture 29, fill 1), undo-phase peak 1126 MiB (others <=1000).
- S3b playcheck pc-after2: GREEN, r1late 28 (layer_picture 27, fill 1), undo-phase peak 1014 (= other phases).
- Brief premise refuted: late answers are whole-cel renders of un-memoized cels on scene entry/frame steps, not repairs.

## Last fast tier
- Debug: 5798 run (= static func-test count 5797 + 1 added later), 5791 passed, 3 failed, 4 skipped. The 3
  (FillLiveSlider pre-landing fill, 2 RasterResidency fixtures) fixed; those suites re-run 84/84 green.
- Release: STARTED, then cancelled before any test ran — NOT RUN.

## Open problems
- Move lift's renderIsolated still on main (design S3b row) — not built; proposed for S5.
- Non-fill edits made while a fill has not rendered yet: fill is baked when it lands (lands above that edit).
- Kept pixels are often evicted under the playcheck's full budget (patches=0 seen in logs); cache, so correct.

## QueuedFillUITests (fixed)
Root cause: harness-visible app defect. Queueing a tap changes no @Published value, so no SwiftUI pass ran and
the canvas.host label (fillsQueued:) stayed stale. Fix: objectWillChange.send() in queueFillIfTheLiveOneIsDrawing.
Passes alone on erased device (0->1, second tap 0.57 s). FillLiveAdjust: only the 2 known reds. Debug fast tier
green: 5794 passed + 4 skipped = 5798, 0 failed. Screenshots viewed: boxes empty, both red, one Undo leaves first.

## Next steps (exact)
1. Fill-in fast tier: rerun Debug (expect 5798) and Release via scratch-free command in CLAUDE.md, reconcile.
2. tools/playcheck.sh <udid> two more times (need 3 GREEN); record undo peak + r1late; fill PLAYCHECK_RUNS etc.
3. Run UI classes -only-testing: RapidUndoSurfaceUITests, FillLiveAdjustUITests (FillUITests.swift), InkContinuityUITests,
   FrameStepUITests, ZoomEdgesUITests, QueuedFillUITests; run InPlaceRepairBench for whole-cel vs repair ms.
4. Look at QueuedFillUITests screenshots; drop NOTES.md; delete sim + xcresults; report. Do not merge.
