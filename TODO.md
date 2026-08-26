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

- **(k) stage 1 — the vector float's corner and rotate nodes** — `tmp/movenodes`.

New this pass (owner, 2026-08-23, after testing the touch-ownership build):

- [ ] **(k) Expand the Move tool, loosely after Procreate.** Owner: *"when moving, there should be an option
      menu on the bottom instead of still keeping the select menu, in which different types of moving can be
      done."* **Uniform** (today's raster behaviour), **Freeform** (corner drags scale x and y independently),
      **Distort** (each of the 4 corners moves independently, turning the box into a quadrilateral, with the
      contents foreshortening — "useful for 3d perspective"). **Warp is explicitly declined** — *"Unlike
      procreate, Warp will not be a feature (like liquify)."* Plus **Flip Horizontal**, **Flip Vertical** and
      **Rotate 45°**. Also reported: *"the move tool on vector layer does not have any move nodes for rotate or
      scale"* — which a read of the tree narrowed to the **lasso** path specifically; whole-cel vector Move
      already has all six handles, and one constant restricts the lasso float to `[.body]`.
      **Two rulings taken 2026-08-23**: the **yellow node rotates the box only** while the green one rotates
      box and art; and vector Distort **maps existing stroke points with no subdivision** — *"do no subdivision
      for now... then if i tell you subdivision may be necessary, go for it."*
      **Four more rulings, 2026-08-23.** (i) **Text**: *"Perspective distorting text is supposed to be a feature
      I remember explaining a while ago... It is useful to put text on 3d surfaces. Hold distort until text can
      warp."* (ii) **Stroke width under Distort**: *"There should be an extra option in the menu to switch
      between these two modes when in distort. I say do it properly with that, with default being no scaling."*
      — so a per-sample taper, behind a toggle, defaulting **off**. (iii) **Placed images**: *"Teach images to
      hold a stretched shape"* — the real work, not the refusal. (iv) **Reset** goes on the bar.

      **Two discoveries that reshape the order, both verified in the tree:**
      1. **`TransformMode` already exists** (`SelectionModels.swift:28`) with `freeform`, `uniform`, `distort`,
         `warp`, and its own comment says *"Distort/Warp aren't implemented with real per-corner/mesh geometry
         yet — they render and gesture identically to Uniform."* So Uniform and Freeform are already real for
         raster, Distort is a declared stub, and **`warp` is a case to delete** under the owner's ruling.
      2. **Perspective text was never lost — and it is the same work as Distort.** [ADD_TEXT.md](ADD_TEXT.md)'s
         **Stage 5 *is* "the projective distort"**, Stage 4 (rotate/scale/handles) shipped 2026-08-21 leaving a
         clean seam (`TextFrame.affineTransform` returns nil for any non-parallelogram and every drawing path
         already branches on it), and Stage 6's own list contains *"Converting `FloatingPiece`'s `.distort`,
         which today runs the uniform-scale path and whose own doc comment admits it, onto this solver."*
         **One `Homography` solver plus one projective render path unblocks both.** The owner's "hold distort
         until text can warp" is therefore the correct build order, not a delay.

      **Five more rulings, 2026-08-26.** (v) **One toggle governs whether the ink deforms with the shape**,
      in Freeform *and* Distort — the owner's own framing, *"there should be an option on if the ink should be
      scaled/deformed or should stay the same when distorted"* — **defaulting to "ink keeps its shape"**, which
      is also the cheap path, so the feature ships before the harder one is built. (vi) **Text in a flipped
      selection mirrors** like everything else. (vii) **A Freeform stretch survives a switch to Uniform** —
      3:1 stays 3:1 and scales from there. (viii) **A flip on a lassoed piece is its own undo press**, and the
      whole-layer flip deliberately differs. (ix) The yellow node is **float-only for now**; the whole-layer box
      has no `boxRef` to hang an angle on and no Freeform to aim.

      **The finding that made stage 3 affordable, verified in the tree**: `DabGradientCache.stamp` ends in
      `ctx.drawRadialGradient` **in the context's current user space** (`RasterLayerTexture.swift:85`), so a
      non-uniform CTM turns every dab into an ellipse *exactly*, through code that already exists in both
      `DabTarget` implementations. No new drawing primitive, no third implementation, no Metal question. The
      stretched-ink path is a `saveGState`/`concatenate`/`restoreGState` wrap plus a unit-determinant residue
      stored on the stroke — and because the dab walk then happens in the *pre-stretch* frame, the dab count,
      the parameters and the seeded RNG sequence are identical to the unstretched stroke.

      Order: (1) the missing handles, (2) the Move menu — delete Warp, add Rotate 45° and Reset, (3) Freeform +
      the yellow node + images holding a stretched shape, (4) **ADD_TEXT Stage 5's solver**, (5) Distort on both
      tiers with the width toggle. See the design in the branch.

## Verified on the device

**All five of this pass's changes were confirmed by the owner on their iPad, 2026-08-22**: *"five changes are
behaving correctly."* That covers the lasso move, the Cut eraser's live preview, the pick tool under the Select
panel, the raster-tier omission on save, and the raster Move's travelling ants. Nothing from this pass is
waiting on an eye any more.

Three behaviour questions are still carried, and are **not** defects — each was raised by us, not reported:
the Cut eraser across a line thicker than the eraser (visibly does nothing, and always did); a crossing line
that can flicker during a cut drag, under 10% of what the cut removes; and a fill chunk dropped on blank paper
staying a fill. All three want the owner's eye on real artwork rather than another run.

## Queued

## Verified on the device

**All five of this pass's changes were confirmed by the owner on their iPad, 2026-08-22**: *"five changes are
behaving correctly."* That covers the lasso move, the Cut eraser's live preview, the pick tool under the Select
panel, the raster-tier omission on save, and the raster Move's travelling ants. Nothing from this pass is
waiting on an eye any more.

Three behaviour questions are still carried, and are **not** defects — each was raised by us, not reported:
the Cut eraser across a line thicker than the eraser (visibly does nothing, and always did); a crossing line
that can flicker during a cut drag, under 10% of what the cut removes; and a fill chunk dropped on blank paper
staying a fill. All three want the owner's eye on real artwork rather than another run.

## Queued

New this pass (owner rulings, 2026-08-22, on the touch-ownership truth table):

- [ ] **(i) One touch, one actor.** Deriving `CanvasTouchOwner`'s contract enumerated the input space and found
      **1,678 reachable combinations where two things act on one touch** — drag a guide grip with Fill selected
      and the grip moves *and* a flood fill lands under it; with the pick tool armed, the brush colour changes
      too; drag a floating piece's box with Fill selected and the piece moves *and* a fill dumps under it. The
      cause is not a missing check anywhere: **every container recognizer sets `cancelsTouchesInView = false`**,
      so an overlay claiming a touch in `hitTest` does not take it away from the recognizer beneath. The rule
      to apply: **whatever chrome the artist actually grabbed wins, and the tool underneath does not also
      fire.** `handleTextPress` already works this way — it re-checks both text overlays before acting, and is
      the only handler in the app that does, which is exactly why text is absent from the collision list. It is
      the pattern the other thirteen sites need.
- [ ] **(j) A tap outside a floating vector piece commits it, as it already does for raster.** The same
      enumeration found **118 combinations owned by nobody**, all on a vector layer: mid-Move, or with a lassoed
      piece floating, a touch anywhere outside the box does nothing *and says nothing* — where a hidden layer
      would at least raise a banner. With the Select panel open the canvas is inert away from the box,
      including the lasso the open panel is for. **Owner's ruling, 2026-08-22: make the tap commit the float**,
      chosen over leaving it silent or raising a notice, because it makes the vector float behave like the
      raster one. The asymmetry today is structural: `FloatingPieceOverlayView` covers the whole container and
      commits a raster piece on a tap outside, while a vector float's `ObjectTransformOverlayView` claims only
      its own grips.


Nothing — the owner's list is empty. Two things are *carried*, both deliberate and neither an ask:

- **The raster Move's undo half of ruling 4 is not built** (the vector half and selection-at-bake shipped). A
  raster nudge changes only `FloatingPiece.transform`, which is transient and not in the document, so per-nudge
  steps must be transient — and the bake step then sits on top of them and its undo restores the pre-move cel,
  killing every step beneath. Making it work means the bake step's undo *re-creating the float* at its last
  transform, which doubles what a raster Move retains in history and needs `finalizePendingGesturesForHistoryAction`
  to grow a raster-float arm it has never had. That is a second feature. See LASSO_MOVE.md §3 stage 4.
- **[ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md)'s first finding**, unruled: fourteen places decide who owns
  a canvas touch and none of them is *the* place. Four defects trace to it, three in the last week. The remedy
  is one pure `CanvasTouchOwner` type, and it is the one item that pays for itself on the **first** new tool —
  which matters, because the next session is large features.

## Done this pass

- **One touch now does one thing, and a tap away from a vector Move box puts the piece down**
  (`38b6fed`), plus the type that found both (`e0d59b2` and its three parents). This is
  [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md)'s finding 1, which the owner ruled should go **before** the
  next large features.

  **Deriving the contract before touching a gate is what produced the value.** Enumerating the input space —
  every tool x every panel x floating-piece x layer state, 3,600 reachable combinations — found **1,678 where
  two things acted on one touch** and **118 owned by nobody**. Neither was reported by anyone; both were live.
  Drag a guide grip with Fill selected and the grip moved *and* a flood fill landed under it; with the pick
  tool armed the brush colour changed too; tap into your own text with Fill selected and the caret placed *and*
  the layer flooded. **The cause was never a missing check at any one site**: every container recognizer sets
  `cancelsTouchesInView = false`, so an overlay's `hitTest` claim does not take the touch from the recognizer
  beneath it. `handleTextPress` was the only handler in the app that compensated, by re-checking the overlays
  itself — which is exactly why text was absent from the collision list.

  Settled per the owner's rulings: each of the five container recognizers now asks `owner(in:)` and stands down
  when the answer is not itself — one rule in one place rather than thirteen bespoke guards of the kind that
  produced the defect — and `.moveBoxCommit` gives a vector float the tap-away commit a raster float always
  had, sitting **last in the precedence** so it takes only touches that used to do nothing.
  `contenders(in:)` still reports everything the gates *offer* a touch to; `actors(in:)` is what happens, and
  is never more than one. `.nobody` is kept as a case with no reachable producer, so a test can assert the
  empty set — deleting it would turn "the canvas went silent" back into a fallthrough nothing can name.

  **A review nearly cost the refactor its point and was right to.** The tests shipped with 38 hand-maintained
  expected counts, every one of which would shift the moment a tool was added — the exact event the work exists
  to make cheap. They are gone, replaced by properties asserted per state, and the replacement was
  mutation-checked rather than assumed. A second reviewer rebuilt the whole test file as a standalone `swiftc`
  harness and ran 24 mutations, catching 22, having gone in willing to conclude "not worth merging".

  1646 fast-tier tests (1643 passed, 0 failed, 3 skipped) = 1617 + 19 + 10, matched at every step by a static
  `func test` count. **An honest gap is recorded rather than papered over**: nothing couples `CanvasTouchInputs`
  to what `CanvasView` actually gathers, because an out-of-process test target cannot see it, and the type's
  doc comment names the five fields nothing covers.

  **One hypothesis eliminated on the way**, in [BUGS.md](BUGS.md): the open "two-finger pan is dead while Fill
  is selected" cannot be `shouldRequireFailure`, because `Tool.fill.paintsOnCanvas` is false so the guard
  returns before stating any dependency. Two readers reached that independently. **Do not ask the owner to
  re-test it as a fix check** — a green re-test would mean nothing.


- **(a) A lasso selection moves only what is inside it** (`a5fa3b2`). Draw a loop with Select on a vector layer
  and tap Move: the lassoed ink lifts out in one frame — strokes the loop crosses are **cut at the boundary**,
  a fill loses the chunk that was inside, text and placed images come whole if their centre is in. Drag at
  60 fps with the marching ants travelling with the piece; tap Move again, switch tools or save, and it bakes.
  Undo walks back one drag at a time and one more press rejoins the cut stroke. A loop that caught nothing does
  nothing — it does **not** fall back to moving the whole drawing.

  **Five owner rulings taken 2026-08-22, on top of §5's six.** The load-bearing one: *"The lasso will only pick
  up and move whatever is inside of it. If the hole is fully inside, it moves it. If its outside, it wont."* —
  which **overruled the design's proposal that eraser marks never move and never split**. An erase element now
  takes exactly the same centre-line test and the same split treatment as a paint stroke, which is both simpler
  and consistent with this app's own "the eraser is a stroke" decision. Two consequences are handled rather than
  discovered: a punch-only float renders legitimately blank (a punch lowers alpha on what is beneath it *in the
  same list*, so alone on transparency it draws nothing) and is latched anyway; and both halves of a split
  replace the parent **at the parent's index**, so a moved punch keeps its z-position.

  Also settled: undo past the move rejoins the line; an empty lasso does nothing; the raster Move inherits
  selection-at-bake and travelling ants. **The ants ruling was corrected mid-build** — the design proposed
  leaving them where drawn, LASSO_MOVE.md §5 had already argued they travel "which is what Photoshop and
  Illustrator do", and the spec won.

  1617 fast-tier tests (1614 passed, 0 failed, 3 skipped) = 1591 + 26, static `func test` 1730 against 1703
  with the extra one an XCUITest. The conservation-of-ink test — a lift-and-bake with no drag is pixel-identical
  to the drawing before it — was watched failing at *"Composites differ at (22, 15) channel A: got 182,
  expected 255"*.

- **[ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md)** (`6e1f9ce`), written for the next session's large
  features. **Fourteen independent decisions across three unrelated mechanisms** arbitrate one canvas touch —
  recognizer `isEnabled`, `isUserInteractionEnabled`, and five `hitTest` overrides — with `shouldRequireFailure`
  reading three of them back. Four defects trace to it, three from this week including today's pick tool and
  the shape-outline drag (*a different mechanism, same class*). **It is structural, not sloppiness**:
  `activePanel` is `@State` on `DrawingView` while `selectedTool` and `floatingPiece` are on `CanvasManager`,
  so no object can see all the inputs and no single function can be written. Also: eleven hand-written cache
  keys, every save-failure path returning silently, and a persisted layer property living in four hand-kept
  structs.


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
