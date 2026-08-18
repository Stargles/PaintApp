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

- [ ] **The app-switch triple save** — `tmp/appswitch`. `ContentView`'s scene-phase guard never looks
      at where the transition came *from*, so SwiftUI passing `.inactive` on both legs fires
      `saveIfNeeded()` three times per app switch, one of them on the return leg while the artist is
      watching. Fixed by a pure `ScenePhaseSaveGate.shouldSave(from:to:)` phrased as "leaving
      `.active`" rather than an allow-list, so an unrecognised phase still saves — missing a save
      loses work, an extra one only costs a stall. Green, +5 tests over the full transition matrix.

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
- [ ] **An oval and a partial oval are one feature, with no modes.** The owner, asked whether a
      nearly-closed stroke should be snapped shut, answered by collapsing the whole design:
      *"The oval and arc feature should be the same feature with no modes. Whatever the user draws that
      follows an oval path whether partial or full spawns in that oval, and the stroke is then projected
      onto that oval. It may not be a full oval, in which case the stroke would only be projected to a
      portion of the oval. Finger snapping it will basically then turn that oval into a circle and the
      partial projection remains."*
      So the model is **an ellipse plus the angular span the stroke covered**. The hold fits the full
      ellipse the stroke lies on — always the whole ellipse, that is the geometry — and what gets drawn
      is the stroke *projected* onto it, which is the whole ellipse when the stroke closed and a portion
      of it when the stroke did not. Handles and editing operate on the ellipse; the two-finger snap
      makes it a circle and **the span is preserved across the snap**.
      **There is deliberately no arc-vs-oval decision to make**, and that is the point of the answer: no
      coverage threshold, no "was this sloppy or intentional", no second shape kind. A full stroke
      projects to a full oval and a half stroke to half, by the same rule. Anything that reintroduces a
      mode here is a misreading. Wants the headless sweep harness `ShapeDetectorLogicTests` already has,
      including spans either side of a closed loop and the span surviving a snap.

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
