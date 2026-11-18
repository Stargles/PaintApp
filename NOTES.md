# nov17-hitch — notes for whoever finishes this (uncommitted on purpose)

Evidence folder: ~/PaintWork/nov17-hitch-evidence/ (scripts/run.sh <name> <Debug|Release> runs one
InteractionHitchUITests test, ONLY=<testName> env; copies the recorder file to <name>.jsonl). Simulator
UDID in evidence/udid (own iPad 9 sim, delete when done).

## Done
- WIP commit 8a7c2bce plus InteractionGateLogicTests (5 tests, mutation-checked); Debug and Release fast tiers green (5691/0/4).
- RESOLVED (it was the TEST): testAFinishedStrokeStaysOnScreenUntilItsBaseLands failed because a 50 px brush stamps live dabs on main for ~380 ms (mainStall DabImageCache.stamp), so a screenshot at lift+0.2 s shows no ink YET (first-appearance latency, not a vanish; the ink log shows held at the recogniser end and retired+base in one main turn). Test now judges dips only after the stroke was first shown, skips strokes the probes cannot see, needs >=3 judged. Mutation (retire held ink at hold time) goes red; unmutated green 4x serially. Running all 3 tests in one xcodebuild session slowed the 3rd to ~60 s per tap (sim degradation); alone it is 155 s green.

## Proven (simulator)
- Stall sampler names the cost: with a large Rough Ink brush, 550-713 ms main passes, cpu==wall, all in
  `DabImageCache.stamp` (live dab stamping on main: CG `.high` resample + per-draw image-data copy).
  At the owner's 6 px brush the sim max pass was ~17 ms (sim is ~8x the iPad 9); device unproven.
- Earlier `sample` of the app: CA commit converting RGBA (premultipliedLast, rowBytes=w*4) canvas-sized
  images on main (CA::Render::copy_image -> vImage permute) — RasterSurface format is not CA-native.
- Ink log at 3 s spacing: held -> retired+base in the same main turn; no gap seen yet.

## Found in handoff-1 (Debug, slowed render 300 ms)
- Drawing: held -> retired+base in one main turn for every stroke; screenshots (~110 ms apart) show no
  dip. The owner's flicker is NOT reproduced on the simulator yet.
- ERASER: one vertical eraser pass on the 5000² five-layer scene = a 6,125 ms main-thread pass,
  cpu == wall, 93/200 samples in `CelContentPicture.rendered` <- `StrokeScratch.replaceCelContent` <-
  `StrokeScratch.replaceVectorDisplay` <- StrokeCanvasView move handler: the live vector eraser re-renders
  the whole touched window of the cel (all ink in it) with UIGraphicsImageRenderer ON MAIN per move. That
  is canvas-sized work on main during interaction (SCHEDULER rule 2) and the likeliest root of both
  "erase a lot -> erased strokes reappear" (main frozen while the old base is on screen) and the hitch.
  Fix direction: draw that window off main into WindowSurfaceView (IOSurface, LatestWins — the same
  path held edits / stream use), main only swaps the surface.

## Gate verified (hitch-after-1, Debug)
- Builds and runs; during the stroke+pan burst bakes ran only in the gaps (0-2 composites per 2 s vs
  ~3 every 2 s throughout the burst before), max main pass 20-50 ms in the burst. No logic test for the
  gate yet (write InteractionGateLogicTests: closed while count>0 and 250 ms after; stuck count opens at
  10 s; checkpoint() blocks a worker until open and never blocks main; mutation: drop the
  StripedComposite checkpoint / the FrameBaker guard).

## Frame-step mix (owner, "parts of the layer you are on overlaid on other layers for up to a second")
Different mechanism from the stroke handoff, not fixed: on a frame step the active host is handed a
different VectorCanvas; StrokeCanvasView drops its held ink and, when the new cel has no memo (the iPad 9
budget holds two 5000² renders and evicts cels not on screen), refreshDisplay takes `.rasterize` and
deliberately KEEPS THE PREVIOUS PICTURE in the base slot until the off-main render lands — but that
picture is the previous frame's cel, so for the render's length (up to ~1 s at 5000² on the iPad 9) the
old frame's ink of this layer sits over the new frame's other layers. Rule needed: across a cel change
the stale picture is not "the last complete one"; hold the whole previous frame (or show the baked new
frame) until every host of the new frame is ready.

## Next
1. (Triage done.) Real remaining work, not done: fix the handoff (stroke/eraser/frame-step) and commit separately.
