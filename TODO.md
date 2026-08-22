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

- **(f) the cut eraser's live feedback** — `tmp/cuteraser`, opened with the owner's refutation ask.
- **(h) the pick tool is dead while the Select panel is open** — `tmp/pickselect`.

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
New this pass (owner, 2026-08-22, given while the lasso Edge Overlap rebuild was in flight):

- [ ] **(f) The "cut" eraser has no live feedback — it only applies on lift.** Owner: *"the to cut
      eraser does not have live feedback like the to cross eraser, it only applies when the eraser is
      lifted. I wonder since the to cross eraser is so similar to the to cut except with that one
      cross feature, if redundant code can be removed."* In code these are
      `VectorEraserMode.cutPoints` (Mode 2) and `.cutToIntersection` (Mode 3),
      [Tool.swift:165](PaintSoftware/Models/Tool.swift:165). The owner's second half is the more
      valuable one and should be answered before the first: if Mode 3 is Mode 2 plus a crossing rule,
      the live path already exists and Mode 2 should be able to use it rather than gaining a second
      copy. **Owner, 2026-08-22, mid-pass**: *"refute what I said about to cut eraser being similar to the to
      cross. I still would like it to be live feedback."* So the similarity question is to be **tested
      adversarially rather than assumed**, and the answer does not gate the ask: live feedback ships
      either way. **One thing to know before making Mode 2 live**: CLAUDE.md records Mode 3's cutting pass
      at **~95 ms per sample**, measured and deliberately unfixed until the eraser rewrite settles —
      so "give Mode 2 the same live path" may mean giving it the same cost, and that wants measuring
      rather than assuming. It also compounds with the footprint eraser, which cuts every stroke it
      covers rather than one.

New this pass (owner, 2026-08-22, while testing on the iPad):

- [ ] **(h) The pick tool does nothing while the lasso Select tool is up.** Owner: *"The pick tool does not
      work when the lasso select tool is selected."* First reported as "paint dropper tool doesnt work when in
      fill tool mode", withdrawn as a false alarm, then reproduced precisely — **the fill tool was never
      involved**; it is the Select *panel*. There is no `.select` case in `Tool`, so "the lasso select tool" is
      `ActivePanel.select`, and two lines conspire:
      [CanvasView.swift:1749](PaintSoftware/Views/CanvasView.swift:1749) disables the eyedropper's recognizer
      whenever `activePanel == .select`, while
      [CanvasView.swift:1617](PaintSoftware/Views/CanvasView.swift:1617) leaves the selection overlay capturing
      because it never consults `selectedTool`. Arming the dropper does not close the panel, so nothing
      re-enables it: the recognizer is off and the overlay eats the tap as the start of a lasso. The guard has a
      real purpose — the overlay owns single-touch gestures while it is up — it simply never considered a
      *momentary* tool being armed on top of it, which is precisely what
      [Tool.swift:11-20](PaintSoftware/Models/Tool.swift:11) says the eyedropper is for.

## Done this pass

- **PERFORMANCE.md item 14's cheap half: a cel nobody has drawn on stops paying for a canvas-sized
  transparent PNG** (`1d7332a`, `5cd6431`). Every cel wrote a `<uuid>_raster.png` on every save whatever its
  raster tier held; on the owner's live 2048×2048 project all three carry one of exactly 73,558 bytes whose
  alpha is min = max = 0 — **including the cel on the raster layer**. The save now decides from
  `RasterLayerTexture.hasContent`, which asks whether the *bitmap exists* and never scans pixels: `context ==
  nil` implies "no pixels" by construction, and that is the direction that cannot lose artwork. The converse is
  deliberately not claimed, so a cel erased back to transparency still writes, conservatively.
  `SaveSnapshot.CelContent.rasterImage` became optional in the same move — asking a blank texture for its image
  is what *created* the cost, since `renderToUIImage()` mints a canvas-sized transparent `UIImage` and memoizes
  it where nothing drops it again.

  **MEASURED, 60 vector-only cels at 2048×2048, iOS 26.5 simulator (iPad Pro 13-inch M4), Debug**, three
  samples each way, machine at 5.2% idle so the *timings* are contended and the byte and footprint figures are
  not:

  | | before | after |
  |---|---|---|
  | package on disk | 6.9 MB | **4.6 MB** |
  | of which `_raster.png` | 2.3 MB in 60 files | **0 bytes in 0 files** |
  | `pngsEncoded` per save | 60 | **0** |
  | save, awaited | 645 / 648 / 540 ms | **188 / 192 / 240 ms** |
  | `phys_footprint` after a load | 3317.1 / 3317.6 / 3319.5 MB | **1865.1 / 1865.3 / 1865.7 MB** |

  **~1453 MB, ~24.2 MB a cel** — 16 MiB of that is the `CGContext` arithmetic exactly, the rest the decoded
  `UIImage` the load no longer holds beside it. **Load wall-clock did not move** (4579/4720/5577 → 6183/6010/4939 ms,
  overlapping ranges): that fixture's load is dominated by rasterizing 60 vector cels for thumbnails, which this
  does not touch. Reported as unmoved rather than dressed up.

  Two traps decided the shape and both are now pinned by tests. `validateProject` **gates the atomic swap**, so
  a validator still demanding the file would have moved every staged package to Trash while the save reported
  success — silent total loss, in an app that looked fine. And `rasterFileName` stays **non-optional**: its
  absence is what makes PencilKit-era manifests fail to decode, which is what has the gallery skip those
  projects rather than open them blank. A legacy package heals on load — a blank PNG is scanned exactly, byte
  by byte with an early exit, and the bitmap released — and one opaque pixel in 2048² survives, with a test
  that fails if the scan is ever made cheap by sampling. **The owner's existing projects heal on their next
  open-and-save, not on load alone.**

  1583 fast-tier tests (1580 passed, 0 failed, 3 skipped), = 1573 + 10, matched against a static `func test`
  count of 1690 against 1680.
