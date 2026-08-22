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

- [ ] **The second-fill race, on the lasso path only** — `tmp/lassorace`. Owner, on device
      2026-08-21: *"remember that weird bug when you filled something and then filled another thing
      while the previous thing was unbaked and it did the weird fill thing? that bug is present in
      the lasso bug right now. currently I havent found the normal fill to do it though."* The
      generation guard `2226ef0` gave the normal fill does not reach the lasso path. **The owner's
      negative half is the lead**: whatever differs between the two paths is where it lives.
      Carrying two more owner asks on the same branch, as separate commits:
      **the gap-closing and edge-overlap sliders must be inverted in lasso mode**, in the sense that
      *"moving the gap closing slider up means bigger gaps get filled, and moving the edge overlap up
      means the fill gets bigger."* Edge overlap is currently hard-zeroed in lasso mode
      (`CanvasManager+Fill.swift:215`) **on my instruction, which was wrong** — the owner reports the
      fill bleeding at antialiased edges, which is the halo that control exists to close.
      The owner has also ruled that the two modes are **not** meant to agree pixel-for-pixel, and that
      more gap closing making the normal fill smaller while making the inverted fill bigger is
      *intended*. So the properties to pin are single-mode and monotonic — the gap width that seals
      grows with the slider, the filled area grows with edge overlap — not a cross-mode parity.

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

## Done this pass

- **(b) The lasso icon stays lit while another tool is in use** — and the answer to the question the
  branch was really asking is that **the selection already survived a tool change; only the readout
  lied.** Proved from the tree rather than from prose: the fix adds no code to any clearing path (one
  changed argument in `TopToolbar` plus one pure static predicate), no clearing site is a tool change
  (`selectedTool`'s `didSet` only writes to `ActionRecorder`), and `CanvasView` was already handing
  the stroke view `selectionClipPath` regardless of which tool was current — so brush, eraser and
  fill were being clipped to the selection all along. Blast radius is the icon alone.
  The predicate became a static function precisely so it could be tested: `TopToolbar.swift` is a
  `View` file outside the logic target's compile. The new XCUITest is **verified non-vacuous** — with
  the pre-fix wiring restored by hand it fails on its own assertion, which is the check that
  separates a real test from one that would pass against anything.
  1525 / 1522 passed / 0 failed / 3 skipped, +12 over 1513, matched by a static `func test` count on
  both trees. UI suites 18/18. Note `ToolsAndSelectionUITests` is a **file, not a class** — a selector
  naming it matches nothing and still prints green.

- **(c) and (d): the Move drag, and handles that keep their size.** Owner: *"Move is extremely slow on
  a vector layer"* and *"the move nodes' size doesn't stay constant to the screen, and right now they
  don't seem to respond to touch."* Both were the same overlay and merged as one branch.
  **(c) was measured rather than guessed**: one touch-move sample of a Move drag cost **102.3 ms** at
  2048x1024 — the owner's ~5 fps, found — because the drag rasterized on every sample. After: **0.004
  ms**, with a cold-render control at 41.7 ms holding to 6% across four separate readings, which is
  what says the ratio is about the code and not the machine. Three of those readings predate the fix's
  verification run and one is inside it; a fourth agreeing with three is not a new claim, so
  PERFORMANCE.md is untouched.
  **(d) is the bug [ADD_TEXT.md](ADD_TEXT.md) §1 had already named and told the text build not to
  copy** — `TransformHandleView`'s fixed 24x24 living inside the transformed `container`. The Move
  overlay now sizes in screen points. **`FloatingPieceOverlayView` is knowingly still on the broken
  one**, documented in BUGS.md and in `TransformOverlaySupport.swift` ("Do not add a third user"), so
  the raster Move tool's floating piece still shrinks with zoom — and the lasso-move feature lists it
  as a blocker.
  Verified 1513 / 1510 passed / 0 failed / 3 skipped, +32 over baseline accounted for by counting
  `func test` in the two new files; `VectorLayerContentUITests` 5/5, `SelectionAndMoveUITests` 4/4,
  `CanvasTransformFreezeUITests` 3/3 with one standing skip. **Two of those three class names live in
  differently-named files**, so a file-name selector would have matched nothing and printed green.
  One cost to know: the proof of the headline number is a perf test that adds **~19 s to every fast-tier
  run** from here. It is the only thing pinning the number, so it stayed.
  Device half genuinely unverified — every figure is a Debug simulator against a Release A13, and
  whether a 14 pt grip is findable with a fingertip is not something a headless test reaches.

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
