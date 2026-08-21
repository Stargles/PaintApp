# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

**At the start of a pass, empty "Done this pass".** It is a record of the pass you are in, not a
changelog — `git log` is the real history, and a list carried across passes stops meaning anything.
Prune it first, before adding the new asks.

## The canvas size that actually matters

**The owner works at 2048×1024, or 1080p — "likely the former" (2026-08-17).** Not 4096².

Every performance number this project has collected was measured at 4096², which is **eight times the
pixels** of 2048×1024. Any cost that scales with area is therefore overstated by roughly 8× against the
document the owner actually animates on, and a conclusion drawn at 4K may be about a canvas nobody uses.
Benchmark at 2048×1024 first and treat 4096² as the stress case, not the baseline. This applies to the
17 fps entry below, the gallery thumbnail, and the onion skin composite alike.

## In flight

*Nothing. The next owner ask starts here.*

## Queued

New this pass (owner, 2026-08-21, given after the device pass — four asks about the lasso and move
tools on a **vector layer**, framed as "isn't inline" with how they should work):

- [ ] **(a) A lasso selection should move only the selected part, not the whole drawing — text
      excepted.** *The owner's own framing, close to their words: "the move tool: when selected, it
      moves your entire drawings on the cel. This is currently correct, nothing needs to change.
      However, when you lasso and then move, only the parts inside the selection should be moved."*
      This is a real feature, not a fix: it means splitting `VectorStroke` geometry at the selection
      boundary and cutting a region out of a fill, the way the vector eraser already splits and punches
      strokes it crosses (see the vector eraser's split/punch decision). **The owner has already ruled
      it out for text — "it's okay if it moves text whole," since splitting a `TextFrame` mid-glyph is
      not a sane operation.**
- [ ] **(b) The lasso tool icon should stay highlighted while a different tool is briefly in use.**
      *Owner: "when you click the lasso icon, lasso, then pick eraser or brush or fill, the lasso icon
      should still stay blue. Blue means the lasso is currently on. Currently only lasso and move are
      able to both be blue."* A toolbar highlight-state question, not a canvas one.
- [ ] **(c) Move is extremely slow on a vector layer — down to ~5 fps, per the owner.** Likely the
      same overlay as (d) below and may be one branch with it.
- [ ] **(d) The move tool's handles do not stay a constant screen size across zoom, and do not
      respond to touch.** *Owner: "the move nodes' size doesn't stay constant to the screen, and right
      now they don't seem to respond to touch."* **This is the exact bug [ADD_TEXT.md](ADD_TEXT.md)
      §1 "Handles live outside the warped layer" already named and told the text-tool build not to
      copy**: `TransformHandleView`'s fixed `24×24` (`Views/TransformOverlaySupport.swift:39-51`)
      "lives inside the same transformed `container` and carries the unfixed shrink-with-zoom bug that
      produced 'faint blue line, does not have nodes in it.'" The owner has now hit that bug on the
      device, in the move overlay rather than the text one. **Add Text Stage 4 shipped the fix's
      pattern today** (`442dc16`) — `Views/TextTransformOverlayView.swift` is a non-warped sibling
      view pinned to `CanvasView`'s `container`, every handle dimension `screenPoints / canvasScale`
      pushed from the coordinator on each transform change, nearest-within-reach hit-testing, raw
      `touchesBegan/Moved/Ended` instead of a pan recognizer. So (d) is not open-ended: port
      `Views/ObjectTransformOverlayView.swift` onto that pattern rather than designing a new one —
      likely also the fix for (c), since a live-rendered handle view inside the transformed hierarchy
      is exactly the kind of per-touch-move cost item 11 found and fixed on the stroke-preview path.
      [BUGS.md](BUGS.md)'s cleanup note on `ObjectTransformOverlayView`/`FloatingPieceOverlayView`
      duplicating handle logic should converge on this pattern too, once it's ported.

Carried from the pre-device-pass programme:

- [ ] **[PERFORMANCE.md](PERFORMANCE.md) item 14's cheap half: stop writing and loading a raster tier
      for cels that carry no raster content.** Re-opened by the owner's stated intent for a real
      document (100–200 frames, 3–5 drawn layers — 300–1000 drawn cels, OWNER-STATED, and an
      intention rather than a package that exists), then re-scoped by reading the owner's actual iPad
      container directly: the largest of 25 real packages on the device has **4 cels**, and both live
      projects have **1**. The app has never been asked to hold what the owner intends — this is
      forward work, not a fire. The expensive half (evict-and-rehydrate the primary pixel data) stays
      **declined**: three independently-scoped designs for it were each traced by adversarial review
      to a silent-artwork-loss path in code that already exists (a `flipCanvas`/`setCanvasPadding`
      path that would blank the whole document under a windowed scheme, and an undo-restore path that
      would let a write-back LRU serve stale pixels). The cheap half is correctness-clean — it
      removes data nothing ever used, confirmed against the owner's own package
      (`Untitled.paintproj`'s one vector cel carries a `_raster.png` of 161 KB it has no use for) —
      and does not need item 9(c)'s thumbnail-persistence precondition the expensive half does.
      See PERFORMANCE.md item 14 for the full mechanism, citations and the corrected arithmetic.

## Done this pass

- **The performance programme is confirmed on hardware.** The owner ran seven checks on a Release
  build of `38e22c6` on their iPad 9, 2026-08-21 — the one thing every item in
  [PERFORMANCE.md](PERFORMANCE.md) had left owed. **All seven passed.** Headline: *"17fps is gone,
  good job. 4k screen displays full 60fps when painting"* (item 11) and *"leaving the gallery is
  instant"* (item 15) — both retire standing open questions for good, the second retiring §5's
  dirty-tracking memo along with it. Project open (item 9), Add Text with the keyboard up, the text
  transform handles (Stage 4), the lasso on its two named scenes, and the cross eraser all came back
  clean too — *"lasso fill works"*, *"cross eraser works as intended, very nice,"* *"text handles are
  good."* Full per-item writeups and exact quotes are in PERFORMANCE.md and ADD_TEXT.md; nothing
  above needed a fix, only confirmation.

- **A vector layer's move/scale/rotate is now undoable — merged (`b100d65`).** `setVectorTransform`
  wrote the cel's `VectorCanvas.transform` and registered no undo step, so Undo after a Move reached
  past it to whatever the artist did before. The bracket hangs off `CanvasManager.isVectorTransforming`'s
  own `didSet` rather than the gesture callback that fires on every touch-move, so it cannot leak
  through the two paths (`rasterizeLayer`, a layer/frame switch) that clear the flag without a gesture
  ending. 13 new tests, fast tier. The BUGS.md entry three sessions had noticed and none had taken is
  deleted.

- **Add Text Stage 4 — rotate, scale, and handles sized right — merged (`442dc16` etc.).**
  `Views/TextTransformOverlayView.swift`: nine grips in a non-warped sibling view pinned to
  `CanvasView`'s `container`, every dimension `screenPoints / canvasScale`, nearest-within-reach
  hit-testing. `.affine` gains rotation and independent-axis scale; Stage 1's canvas-edge growth cap
  is gone, as its own note promised. 27 new tests. **Confirmed on the device this pass**: *"text
  handles are good."* [ADD_TEXT.md](ADD_TEXT.md) §3 has the full writeup, including why "one
  `recordUndo` per drag" was deliberately not what shipped.

- **Save semantics when a project loads with something unreadable — ruled and built (`cfdddb5`).**
  The owner's choice: **prompt once, then remember.** A banner naming what could not be read, with
  Save Anyway / Cancel; an automatic save (backgrounding) never blocks and writes into version
  history instead, so an unanswered damaged document can't be silently overwritten. Save Anyway
  rewrites the package without the unreadable entries, so the next load is clean and asks nothing.
  15 new tests. `BUGS.md`'s `validateProject` entry is updated to record the ruling; the underlying
  blind spot (a payload that is intact-but-unreadable) is unchanged and still open there.

- **Two owner rulings recorded, both closing questions [PERFORMANCE.md](PERFORMANCE.md) had carried
  open.** *(1)* **192 MiB of undo (~12 whole-cel operations) is right, and trimming to half on a
  memory warning is right.** Both are OWNER-STATED decisions now, not guesses wearing constants'
  clothes — see item 13. *(2)* **The font favourites strip ships with sensible defaults the owner can
  edit later**, rather than waiting on their list — already recorded in ADD_TEXT.md §5 item 5 by the
  Stage 4 branch.

- **PERFORMANCE.md item 14 re-opened, then re-scoped — the owner's stated intent for a real document
  (300–1000 drawn cels) does not describe anything that exists on their device yet.** A direct read
  of the owner's iPad container found the largest of 25 real packages has 4 cels; both live projects
  have 1. The expensive half (evict-and-rehydrate the primary pixel data) stays declined — three
  independently-scoped designs for it were each traced to a silent-artwork-loss path in code that
  already exists. **A cheap half is newly justified and queued, above**: stop writing/loading a raster
  tier for cels with no raster content, confirmed against the owner's own package. Also corrected:
  the 787 MB / 6.6 MiB pair is only consistent at 6.558 MiB and both are MiB, not MB; that figure is
  the *stamping* path, not the *load* path, which has never been measured and costs the full 8.0 MiB;
  and item 13's 656 MiB of budget ceilings double-counts headroom that isn't gone — a defensible
  steady state is ~250–450 MiB.

- **Closed: the two "report not closed" carryovers from the pre-device-pass programme.** *17 fps
  drawing on a 4K canvas* — the owner's iPad now reports full 60 fps. *Leaving to the gallery ~3 s* —
  the owner reports it instant, and the ~150-cel inference that used to explain the "~3 s" is refuted
  by item 14's device read (1–4 cels a project, not ~150); whatever caused the original report was not
  cel count, and it no longer matters since the fix landed and reads as instant regardless.
