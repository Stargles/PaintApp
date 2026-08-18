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

- [ ] **The lasso fill fills the whole canvas** — owner, on device, 2026-08-18: *"Lasso tool is not
      working as intended. When i circle something the entire canvas gets filled."* Diagnosed, ruled on,
      specified, **not built**. Branch `tmp/lasso` (worktree `../PaintApp-lasso`) carries two test-only
      commits: a characterization pinning today's behaviour, and a test-side proof that the replacement
      works with no production change.
      **It is the design, not a defect, and the design misses the gesture.** Every open pixel under the
      loop is a seed and nothing bounds the flood, so *because circling something means drawing around
      it*, the loop necessarily encircles paper outside the shape and that paper seeds the whole canvas.
      Measured on a **perfectly closed** box, same tool and artwork, differing only in which side of the
      outline the loop was drawn on: **1.000** of the canvas filled from outside, 0.338 from inside. No
      setting recovers it. It shipped because every prior assertion sampled individual pixels and none
      asked *how much*.
      **The fix is specified in [LASSO_FILL.md](LASSO_FILL.md)** and the owner's own proposal — flood the
      outside from the loop, then invert — turns out to be, word for word, steps 1-2 of Krita's shipped
      *Enclose and Fill*, which was itself derived from studying Clip Studio Paint. Its formal name is
      morphological hole filling. In this codebase it is roughly a one-character change to `Fill.metal`
      plus swapping a union for an intersect; the multi-pixel seeding, the winding mask and the
      gap-closing order are all already right.
      **Three things the owner should see before it lands**: the real cost is not "circling blank paper
      fills nothing" but *any loop not wholly containing an enclosed region fills nothing* — a loop drawn
      inside a shape fills 0, one crossing the outline fills 0.0022; `fillExpand` (default 2) must be 0
      in this mode or the fill runs 2 px past the artwork; and "the loop is a wall" must **not** be
      implemented literally — the flood has to enter the ring in order to exclude it, and the wall
      property comes from the final intersect.

- [ ] **The "To Cross" eraser leaves stubs, and its size does nothing** — owner, on device, 2026-08-18:
      *"The cross eraser behaviour is a bit weird. I want it to erase the lines right at the point that
      the line crosses the center of another line, but in many cases it leaves stubs. Also, the eraser
      brush size should be the radius around which everything is erased. For example if I erase the
      section where two lines intersect, it should erase both of them (up to any other lines they
      hit)."*
      Two rulings in one ask, against `VectorEraserMode.cutToIntersection`:
      **(a) cut at the centreline crossing, not at the ink boundary.** `cutToIntersection` brackets the
      touch with `low = max(p)` / `high = min(p)` over crossings found at a **width-aware tolerance**
      (the sum of the two strokes' half-widths, `VectorEraser.swift:449-483`), so the surviving piece
      runs to the *near edge of the tolerance band* rather than to where the centrelines actually meet
      — which is a stub roughly a half-width long, sticking through the line that was supposed to stop
      it. Hypothesis, to be verified before it is fixed.
      **(b) the eraser radius selects the victims.** Today one drag cuts the single stroke under the
      tip; the owner wants every stroke inside the brush's footprint cut, each back to *its own*
      neighbouring crossings.

- [ ] **The canvas border does not act as a fill boundary once there is padding** — owner, on device,
      2026-08-18: *"Treating the canvas as fill border does not work. You can test this by increasing
      padding, drawing a line which starts outside the canvas (in the padding), goes inside, and then
      back out using the canvas border as a line in the enclosure while otherwise being open, then
      using the fill tool on that enclosure. Right now it fills the entire page."*
      `fillCanvasEdgeIsBoundary` shipped in session 41 and defaults on. Note that `setCanvasPadding`
      grows `canvasSize` itself (`CanvasManager+Document.swift:19-57`), so with padding the buffer edge
      is the *outer* margin and the artwork border the owner draws across is an inset rectangle no wall
      rule currently knows about. Hypothesis, to be verified before it is fixed.

## Queued

New this pass (owner, 2026-08-17):

- [ ] **Add Text, in the Actions menu.** Fonts from a large selection, plus colour, size, spacing and
      the rest of what a text tool carries. Move, rotate, and **distort by dragging each of the four
      corners independently, giving a 3D-perspective warp** (a projective/homography transform, not an
      affine one). **On a raster layer it bakes** once a canvas action follows it — a brush stroke,
      eraser, fill — the way the fill tool and smart shapes already behave. **On a vector layer it stays
      an editable object.** Large enough to be its own project, not a single branch.
      Owner's decisions, 2026-08-17: **iOS system fonts to begin with, behind a provider seam** so
      open-source font packs can be added later without touching call sites; and **delivered in stages,
      each one usable**, rather than as one branch that lands whole.
- [ ] **A performance pass, calibrated to 2048×1024.** The owner asked for it directly: *"any
      performance enhancements that can be made to reduce memory, stop lagspikes, or increase fps?"*
      **The investigation has been run; nothing has been built yet, which is why this stays open.**
      Its output is [PERFORMANCE.md](PERFORMANCE.md) — a fourteen-item programme in three tiers, the
      work deliberately *not* worth doing, and the open questions with the measurement that closes
      each. The conclusion in one line: **the felt problems are not the compositor and not the canvas
      size — they are a save that fires three times per app switch, a project open that blocks the
      main thread for an unmeasured multi-second stretch, and two ungated main-thread costs on every
      timeline tick.** Tier A is seven changes, none of which needs a device run to justify.

Carried over:

- [ ] **17 fps drawing on a 4K canvas.** Diagnosed and **not** the compositor: one dab costs 53.8 ms on
      a vector layer at 4096² against 4.0 ms on raster, because `StrokeCanvasView.refreshDisplay`'s
      `.overlay` branch allocates a fresh canvas-sized bitmap per touch-move. `renderResolution` never
      reaches that path, which is why the owner's 50% test changed nothing. Fix is to give the scratch
      its own layer; wants its own branch. Numbers in BUGS.md.
      **The owner confirmed (2026-08-18) that the 17 fps was measured at 4096×4096**, not at their
      usual 2048×1024 — so the area model holds and the extrapolated ~10.2 ms/dab at their canvas
      stands. [PERFORMANCE.md](PERFORMANCE.md) item 11.
- [ ] **Returning from another app freezes for a few seconds**, with no memory warning fired.
      **Cause found, 2026-08-18.** The owner confirmed the app returns *"exactly where I left off"*,
      which rules out a jetsam kill (a relaunch provably resets to the Gallery), so it is the app's
      own main-thread work: `ContentView`'s scene-phase guard has no direction check, so one round
      trip fires three full saves and one of them lands on the way back in. One-line fix,
      [PERFORMANCE.md](PERFORMANCE.md) item 1; the defect is in BUGS.md.
- [ ] **Leaving to the gallery takes ~3 s.** The thumbnail composites the full 4K canvas for a 320×320
      tile; already in BUGS.md.

## Done this pass

_(nothing yet this pass)_
