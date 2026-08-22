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

- **PERFORMANCE.md item 14's cheap half** — `tmp/rasteromit`.
- **(f) the cut eraser's live feedback** — `tmp/cuteraser`, opened with the owner's refutation ask.

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
      removes data nothing ever used. **Confirmed again 2026-08-22 by pulling the owner's live package
      off the iPad and reading the pixels**: `Untitled 2.paintproj` has 3 cels on 3 layers at
      **2048×2048**, and all three `_raster.png` are **fully transparent** (alpha min = max = 0),
      73,558 bytes each — including the one on the *raster* layer. So the cost is one canvas-sized PNG
      encode per cel per save and 16 MiB of resident buffer per cel per load, for zero pixels —
      and does not need item 9(c)'s thumbnail-persistence precondition the expensive half does.
      See PERFORMANCE.md item 14 for the full mechanism, citations and the corrected arithmetic.

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

## Done this pass

Nothing yet — this pass opened 2026-08-22.
