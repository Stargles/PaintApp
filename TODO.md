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

- **(a) the lasso move** — being designed.

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
## Done this pass

- **(h) The pick tool works while the Select panel is open** (`dd89769`). Owner: *"The pick tool does not work
  when the lasso select tool is selected."* Reported first as a fill-tool problem, withdrawn as a false alarm,
  then reproduced exactly — **the fill tool was never involved.** There is no `.select` case in `Tool`, so "the
  lasso select tool" is a *panel*: `activePanel == .select` disabled the eyedropper's recognizer while the
  selection overlay went on capturing, because its own gate never consulted `selectedTool`. Recognizer off,
  overlay eating the tap, and arming the dropper does not close the panel, so nothing re-enabled it.

  Fixed as **one shared `isEyedropperArmed` read by both sites**, not two edited conditions — the defect was
  precisely that the two disagreed and left the touch owned by nobody, and separate spellings can drift back
  into both-live (two recognizers racing one tap) or both-dead.

  **A fourth edit the brief did not ask for, and the first fixed run is what found it.** The pick worked and
  the run then failed on *"The Select panel is still open after the pick"*: picking sends `interactionBegan`,
  which closes any open panel, and **the Select panel had been immune to that rule only by accident** — its
  overlay ate every canvas touch, so no handler ever fired to send it. Letting the pick through exposed the
  accident. Scoped to Select alone; a brush or fill dropdown still closes on a pick.

  Floating piece: moot — `commitAllInteractiveState()` bakes it one line before the arm — pinned by a test
  rather than by changing the guard. Text: unreachable, because `ActionsMenu.addTextRow` closes the Select
  panel on the way in, pinned by a test since the argument would die silently if those two statements were
  reordered. **Carried for the owner**: entering text mode *first* and then opening Select leaves the text
  placement tap dead, the mirror of this bug. Left alone deliberately — Select is the more recent word there —
  and it is the same one-line change if they disagree.

  43 at-risk UI tests green (41 passed, 2 pre-existing skips), all four new ones verified as *executed* in the
  xcresult. Fast tier unmoved at 1573; XCUITests do not move it.

- **(f) The Cut eraser previews live, and the owner's similarity theory is refuted** (`55f002b`). Owner:
  *"the to cut eraser does not have live feedback like the to cross eraser"*, then *"refute what I said about
  to cut eraser being similar to the to cross. I still would like it to be live feedback."*

  **The refutation.** The *plumbing* around the two modes is near-duplicate — Mode 3's splice even carries the
  comment `// As in Mode 2:` — and `Sweep.mode` was a dead switch, assigned by both and read by nothing (now
  deleted). But "To Cross is Cut plus one cross feature" is not what the app does. Cut removes the ink under
  the eraser; To Cross removes it **and keeps going outward along each line until that line hits another**,
  deleting the line whole if it crosses nothing. `cutRanges` has exactly one caller and `cutToIntersection`
  exactly one; neither calls the other. **Take the cross feature out of Mode 3 and you get nothing, not Cut.**
  ~18 lines to save, and merging would put a mode switch inside the shared body — a wash, declined.

  **The finding that changed the design, and it inverted the brief.** The orchestrator briefed that a
  footprint-shaped preview would show *less* than the cut removes, since the stroke's whole width goes. Wrong:
  `BrushStamper` gives the two surviving pieces **round end caps that grow back into the gap by the stroke's
  own radius**. **Cutting a 40pt line with an 8pt eraser changes zero pixels** — MEASURED, asserted at exactly
  0, with the same test asserting a footprint punch *would* open a 250+ pixel notch, so it cannot pass against
  a scene that fails to exercise the problem. So the preview erases the doomed spans **and draws the caps**,
  and carries the accumulated span per stroke across the drag, because the cut boundary walks outward with the
  finger and stale caps otherwise fill the gap back in behind the eraser. Found by watching a test fail at 99%
  pop-back, not by reasoning.

  **The cost, all three arms in one run**, 334-sample drag on the 200-stroke layer at 2048² that item 10 used
  for Mode 3. **CONTENDED** — 25–42% idle, a standing Adobe background load, never came quiet — but three
  isolated runs agreed to ±0.5%, which a 0.4 ms unit of work can survive where a whole suite cannot:

  | per touch sample (median) | cutting | not cutting |
  |---|---|---|
  | Cut as it was — no preview | 0.000 ms | 0.000 ms |
  | **exact span-and-caps preview — SHIPPED** | **0.439 ms** (p95 0.662) | 0.082 ms |
  | plain footprint punch | 0.014 ms | ~0 |

  0.439 ms is **3.7% of a 60 Hz frame and 220× cheaper than Mode 3's ~95 ms**, because the preview never
  mutates the display list and so never pays the cold layer re-render that makes To Cross expensive. Mode 2
  gets Mode 1's `.replacement` scratch role, not Mode 3's per-sample commit.

  1581 fast-tier tests (1578 passed, 0 failed, 3 skipped) = 1573 + 8, the ninth added test being an XCUITest
  the fast tier does not select. `VectorCutPreviewLogicTests` is a **new file**, hand-added to `project.pbxproj`
  — verified as 7 executed cases in the xcresult rather than assumed, and the duplicate-id check prints `[]`.

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
