# S3b worker notes (drop at the end)
Worktree ~/PaintWork/PaintApp-nov27-s3b, branch tmp/nov27-s3b from ac97b9a1. Sim nov27-s3b (udid in ~/PaintWork/nov27-s3b-evidence/udid).
## Done
- baseline playcheck on main started -> ~/PaintWork/nov27-s3b-evidence/pc-before1
## Next
- map repair/undo/fill code
- baseline playcheck main: r1late=30 (layer_picture=29, fill=1), undo peak 1126, others <=1000
- LayerPicture + in-place repair/append/patch in VectorCanvas; walk turn (join/preempt) replaces rasterizeLock; cancellable walks (per element/stroke)
- 390 vector/scheduler logic tests green
## Next
- CanvasPictureView stale revision check; StrokeCanvasView cancel stale renders
- fill queue (waitForFillWork off main)
- kept-pixel undo test, cancellation test, queued fill test
- fast tier, playcheck x3, UI tests, docs
