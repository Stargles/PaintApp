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

Nothing. Both lasso-fill asks from 2026-08-21 are merged and on the owner's iPad awaiting their eye.

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

New this pass (owner, 2026-08-22, given while the lasso Edge Overlap rebuild was in flight):

- [ ] **(e) Dragging the *line* of a smart ellipse or circle should move the whole shape**, the way
      dragging a line's or a rectangle's body already does — only the nodes should resize it. Owner:
      *"after you make a smartshape elipse or circle, selecting the line (not the node) of the circle
      should move the entire shape, same as line and rectangle."* So this is an inconsistency between
      shape kinds rather than a missing feature: find what the line and rectangle cases hit-test that
      the ellipse case does not. `ShapeGeometry.draggingEdge(_:to:anchor:)`
      ([ShapeGeometry.swift:438](PaintSoftware/Engine/ShapeGeometry.swift:438)) is where an edge drag
      is interpreted; the hit test that decides *edge versus body* is the thing to look at first.

- [ ] **(f) The "cut" eraser has no live feedback — it only applies on lift.** Owner: *"the to cut
      eraser does not have live feedback like the to cross eraser, it only applies when the eraser is
      lifted. I wonder since the to cross eraser is so similar to the to cut except with that one
      cross feature, if redundant code can be removed."* In code these are
      `VectorEraserMode.cutPoints` (Mode 2) and `.cutToIntersection` (Mode 3),
      [Tool.swift:165](PaintSoftware/Models/Tool.swift:165). The owner's second half is the more
      valuable one and should be answered before the first: if Mode 3 is Mode 2 plus a crossing rule,
      the live path already exists and Mode 2 should be able to use it rather than gaining a second
      copy. **One thing to know before making Mode 2 live**: CLAUDE.md records Mode 3's cutting pass
      at **~95 ms per sample**, measured and deliberately unfixed until the eraser rewrite settles —
      so "give Mode 2 the same live path" may mean giving it the same cost, and that wants measuring
      rather than assuming. It also compounds with the footprint eraser, which cuts every stroke it
      covers rather than one.

- [ ] **(g) A real-size stamp preview beside the brush/eraser size slider, while it is held.** Owner:
      *"when changing the size of a brush or eraser its hard to have a grasp of it, so when the
      sliders are pressed down, I want a sort of preview window showing a single realsize stamp of the
      brush pop up beside the slider."* Real-size means canvas pixels at the current zoom, not slider
      units — a 40 px brush on a canvas shown at 0.3x is 12 screen points, and showing 40 would be the
      same class of bug as the Move handles that scaled with the canvas. It should be the brush's own
      stamp with its actual hardness, opacity and colour, not a grey disc: the point is judging the
      mark it will make. Appears on touch-down of the slider, goes away on lift.

## Done this pass

- **A fill lands on top of what is already on the layer** (`5936014`). Owner, after testing:
  *"I cannot fill over things that already have been filled... thats discarded now because I want to
  be able to lasso fill many times over each other."* Asked whether that also covers line art on the
  same layer: ***"The previous decision is overruled as I tested it. Cover everything."*** That
  overrules LASSO_FILL.md §2a's ruling of the previous day, which is rewritten rather than annotated.
  One composite order was copied into four places and all four moved: the raster commit
  (`CanvasManager+Fill.swift:470`), both `addFill` overloads (`VectorLayer.swift:611`/`:753`, now
  appending instead of kind-ordered insert), the flatten (`PixelOps.swift:279`, `ThumbnailRenderer`)
  and the view stack (`LayerHostView.swift:56`). Blast radius is smaller than it looks and that is
  load-bearing: every commit path passes `newFill: nil`, so a cel at rest has no `fillImage` and
  onion skin, thumbnails, export, Move's lift and the eraser see no change. The vector half is paid
  for — `splicing` is now **positional**, and `registerVectorFillUndo` is deleted because a
  fills-bucket undo has to invent a z-position and would restack an appended fill under the ink on
  redo. Two existing tests were deliberately inverted; one had a comment asking for exactly that.

- **Edge Overlap's top is the ink's outer edge, and lowering it shrinks inward** (`e5f623c`). Owner:
  *"edge overlap makes the fill expand out, not contract inwards"*, and on which way the slider should
  move: *"I want it so on the high setting it is on the outer edge, and when you lower it, it shrinks
  inwards."* `lassoEdgeDilate` became `lassoEdgeErode`; the re-anchoring is one line,
  `fillEdgeRadius(lasso:)` — the lasso erodes by `upperBound - v`, so the slider keeps its direction
  and its whole range slides down by its own width. **No setting can paint on clean paper.** The lasso
  stores its own value (`fillLassoExpand`) defaulting to the top, because read through this mapping
  the bucket's shared default of 2 would have shipped a 4 px retreat — the seam reported that same
  morning — as the lasso's out-of-the-box behaviour. The empty-result count is retaken after the
  erode, which the dilate never had to do: growth cannot empty a result, erosion can.

- **The two branches merged clean and still disagreed** (`3f174d1`). §6 step 7 and its twin in
  `Fill.metal` said the fringe pixel *"composites 64 over 213"* — the fill underneath, which the other
  branch had just inverted. The number is right anyway: `over` combines alpha as `a1 + a2 - a1*a2`,
  which is symmetric, so turning the stack over changes the fringe's colour and not its opacity. Both
  copies now say why, so it is not corrected back.

  Merged tree verified: **1541 / 1538 passed / 0 failed / 3 skipped**, +10 over the 1531 base, matched
  by a static `func test` count of 1647 against 1637. Release build installed on the iPad.

