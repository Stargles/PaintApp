# S3b worker notes (drop at the end)
Worktree ~/PaintWork/PaintApp-nov27-s3b, branch tmp/nov27-s3b from ac97b9a1. Sim nov27-s3b (udid in ~/PaintWork/nov27-s3b-evidence/udid).
## Done
- baseline playcheck main: r1late=30 (layer_picture=29, fill=1), undo peak 1126, others <=1015
- LayerPicture + in-place repair/append/patch; kept pixels (budgeted) for undo; walk turn join/preempt (rasterizeLock gone); cancellable walks
- fill taps queued (no main wait), undo while fill drawing takes it back; waitForFillWork test-only
- tests: LayerPictureLogicTests, InPlaceRepairLogicTests, FillGestureRestart queued tests, VectorRenderLock preempt, QueuedFillUITests
- playcheck after1 RED: undo while fill drawing fell through (fixed in last commit), pc-after2 running
## Next
- playcheck x3 green + numbers; mutations (scratchpad mutate.py); fast tier Debug+Release; UI classes; drive sim; docs (scratchpad s3b-asbuilt.md) + TODO 5/6
- pc-after2 GREEN: undo-phase peak 1014 (main 1126); r1late 30->28
- fast Debug: 5798 run, 5791 pass, 3 fail (fill-before-landing fixtures) -> fixed, those 3 suites 84/84
- fast Release running (fast-release.summary)
## Next
- playcheck x2 more, bench, UI classes (RapidUndoSurface, FillLiveAdjust, InkContinuity, FrameStep, ZoomEdges, QueuedFill), screenshots, fill GATE_NUMBERS/S3B_NUMBERS/UNDO_NUMBERS in docs, drop NOTES, delete sim + xcresults
