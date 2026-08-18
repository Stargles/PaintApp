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

- **An oval and a partial oval are one feature, with no modes** — built, all six stages. The model is
  two defaulted scalars on `ShapeGeometry`: where on the outline the pen started, and the **signed,
  never-wrapped** fraction it turned through. Not reducing that mod 1 is the whole trick — seam
  crossing, direction and overshoot stop being cases and become the number itself. No new `Kind`, no
  flag, no coverage threshold; the owner deleted the arc-vs-oval decision and nothing reintroduces it.
  **Eccentric angle, and the snap is what proves it.** The two-finger snap is an anisotropic scale that
  maps the point at eccentric angle `t` on the ellipse to the point at the same `t` on the circle,
  exactly, for every `t` — so the drawn portion survives the snap with **zero new code in
  `constrained`**. Polar angle is not invariant: on a 4:1 oval the end of a 45° arc would land 106.77 pt
  away on a 200 pt circle. A test asserting only "a quarter oval snaps to a quarter circle" passes under
  both, which is why the sweep tests an interior angle.
  Both flagged risks measured rather than assumed. `testRejectsRandomScribble`'s fit error falls from
  0.2230 against the box fit to **0.1399** against the conic fit, inside `closedFitErrorMax = 0.16`, so
  it now survives on the length gate alone at ratio 31.23 — two independent rejections became one, and
  the test carries a comment saying to tighten the *length* gate if it ever creeps. The conic fit
  changes **every** oval, not just partial ones: across 50 jittered shapes, **zero** kind disagreements,
  and full ovals come out slightly smaller and more accurate (149.10×39.73 against 151.95×41.66 on a
  true 150×40 at 5 pt jitter). Real change, no tolerance retuned to hide it.
  **Four numbers in the design were wrong and are corrected in the tests**: a chord length off by 2×
  (an angle halved twice), a claimed "moves < 4 pt" that actually moves by the step's own arc length,
  two sweeps asserting `.oval` for cases that are legitimately lines, and a guard slack claimed at 1.42×
  that measures 2.83×.
  **Pre-existing, found while testing, wants an owner ruling**: a double-traced ellipse detects as a
  *rectangle* — the oval is correctly rejected at ratio 2.00 and the rectangle runner-up then wins.
  Verified against the prior commit; not a regression.

- **Add Text, the first stage of it: a mode you can enter.** The menu row, `Tool.text`,
  `ActivePanel.text`, and the `activePanel` binding threaded into `ActionsMenu` — landing alone,
  because `ActionsMenu` is shared by every panel and [ADD_TEXT.md](ADD_TEXT.md) says to bisect there.
  Nothing text-visible yet: no font seam, no overlay, no bake. The row is disabled on a vector layer
  with a reason, so this stage ships nothing it has to un-ship.
  The question it had to answer was `Tool.paintsOnCanvas`, whose exhaustive switch refuses to compile
  until a new case states its answer. Text is **false**: a text tap places a box for an overlay above
  the layers, so the layer host must decline the touch — otherwise one tap paints a stroke *and* opens
  a text box, which is the eyedropper bug of 2026-08-17 with a different tool's name on it. The smart
  shapes are what make that non-obvious and they resolve it: a shape is not a `Tool` case at all, it
  falls out of holding a stroke still, so its touch genuinely is a stroke and must reach the host.
  **Also found: ADD_TEXT.md's Stage 2 was already built** — the per-element vector decode is the same
  work as yesterday's `try?` data-loss fix, and `LossySlot`/`DecodeReport`/13 tests are on main. A
  session following the plan literally would have rebuilt it. Marked done, number kept so references
  to Stages 3-6 still resolve. Ten of the plan's line citations had drifted, one naming the wrong file.

- **The app-switch triple save.** The owner's *"returning from another app freezes for a few seconds"*,
  and their own answer is what found it: asked whether the app comes back where they left it or on the
  Gallery, they said *"exactly where I left off"*, which rules out a jetsam kill because nothing in this
  app restores state — a real relaunch provably lands on the Gallery. So it was never iOS; it was
  `ContentView`'s scene-phase guard never looking at where the transition came *from*. SwiftUI passes
  `.inactive` on both legs, so one round trip fired `saveIfNeeded()` three times, the last of them on
  the way back in while the artist watched. `ScenePhaseSaveGate.shouldSave(from:to:)` is phrased as
  "leaving `.active`" rather than an allow-list of the two known departures, deliberately: missing a
  save loses work where an extra one only costs a stall, so an unrecognised phase still saves.
  Two things found on the way that make the size of it clear. **`saveIfNeeded` has no dirty check at
  all** — the "IfNeeded" is a guard on the *screen*, and `writePackage` stages a fresh directory so it
  cannot reuse a prior file even in principle. All three saves did the full job. And every save mints a
  rotating `auto-` backup slot, five deep, so **one app switch was consuming three of the artist's five
  restore points, two of them byte-identical.**

- **The performance investigation, and [PERFORMANCE.md](PERFORMANCE.md).** Ten read-only agents over
  the drawing hot path, compositing, memory, the app-switch freeze, timeline/playback and
  save/load/startup, then three ranking lenses and a synthesis. Two owner answers on 2026-08-18 did
  more to rank it than any of the analysis: the app returns *"exactly where I left off"*, which rules
  out a jetsam kill and demotes the whole memory programme, and the 17 fps was measured at 4096²,
  which closes the one contradiction in the cost model. A citation audit of the investigation's own
  output found every *mechanism* real but a third of the line numbers drifted, and four figures
  labelled "measured on device" that appear nowhere in the tree — they came from the saved workflow
  script's own ground text, which has since been corrected. **Verify numbers, trust mechanisms.**
- **The onion skin panel**, merged. What the device settled: the old `skins5 > skins10` inversion was
  a cold CPU (`skins5Cold` 98.8 ms against 56.2 ms warm), not cache ordering, and the warm series is
  monotonic. At the owner's 2048×1024 the whole resolution question is smaller than it looked — Full
  is 237 ms at ten skins, not the 1495 ms the 4096² table implied. Cost is calculable: 11.5 ms per
  megapixel per skin at ten skins, holding within 3% across both canvases and all three options.
  The device is **~1.3× the simulator** for this workload, not the ~1.1× previously recorded.
  Owner ruled "Both" on the Full question, so the picker now shows each option's real composite size
  and a caution line appears only when the estimate crosses 250 ms — silent on the owner's document at
  every setting, speaking at 4096² Full even at the shipped default.
  Closing it out turned up a finding worth more than the feature: **at Full, `OnionSkinRasterCache`
  falls through to the compositor's shared cache with canvas-sized entries**, which is exactly the
  eviction its own doc comment exists to prevent. Full's real cost at 4096² is ~2.9 s per drawing
  change rather than 1954 ms, and the onion skin can walk the current frame's own layers out of the
  cache. The owner's canvas is unaffected. In BUGS.md; the caution is a mitigation, not the fix.
