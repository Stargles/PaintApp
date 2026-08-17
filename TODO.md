# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

**At the start of a pass, empty "Done this pass".** It is a record of the pass you are in, not a
changelog — `git log` is the real history, and a list carried across passes stops meaning anything.
Prune it first, before adding the new asks.

## In flight

- [ ] **Snap does not engage** — pen down, shape formed, add a finger, nothing. The
      `isMultipleTouchEnabled` fix (`tmp/shapefix`, rebased as `tmp/shapedev`) was **built to the iPad
      2026-08-17 and did not fix it** — necessary but not sufficient, so the branch stays unmerged. A
      recording taken on that build says why: the finger now lands on the same view as the pen
      (`hitClass StrokeCanvasView`) but is bound to only 6 recognizers against the pen's 15, and
      **neither snap source — `stroke.*` nor `canvas.touchCounter` — is among them.** Never bound, so
      it is a delivery problem, not a delegate one. `tmp/snapbind`.
- [ ] **Pinch to merge two layers does not work.** Owner, 2026-08-17 — was listed done, was never true
      at the gesture level. The model layer (`mergeLayers`, `mergeLossKind`, the confirmation alert) is
      sound and covered; **nothing tests the pinch itself**, which is how it shipped. `tmp/pinchmerge`.
- [ ] **The two lasso bugs**, taken together — a stroke leaving the selection and re-entering counts as
      one and not two, and the lasso answers a finger while pencil-only mode is on. The second is
      likely a third instance of the `fillPress`/`catchAll` hole: a recognizer whose action never sees
      a `UITouch` and so cannot ask the touch type. `tmp/lasso`.

## Queued

New this pass (owner, 2026-08-17):

- [ ] **Rectangle nodes misbehave once the rectangle is rotated.** Flat, dragging a node is correct.
      Rotated, it produces unintended transforms. **The rule, in the owner's words: the node opposite
      the one being dragged must not move.** Second half of the same ask: dragging a node *past* the
      opposite edge should let the rectangle keep working, inverted into the other quadrants — today it
      pushes the opposite edge instead. This is the rectangle twin of the oval fix already sitting on
      `tmp/shapedev` ("oval handles rotate with the opposite node anchored"), so it should be built on
      that branch and can reuse its headless harness.
- [ ] **One colour picker, not two.** The canvas colour changer differs from the brush's; they should be
      the same control. If a second implementation exists, delete it rather than leaving it unreferenced.
- [ ] **A colour picker tool on the left sidebar, below the opacity slider**, for the brush.
- [ ] **Add Text, in the Actions menu.** Fonts from a large selection, plus colour, size, spacing and
      the rest of what a text tool carries. Move, rotate, and **distort by dragging each of the four
      corners independently, giving a 3D-perspective warp** (a projective/homography transform, not an
      affine one). **On a raster layer it bakes** once a canvas action follows it — a brush stroke,
      eraser, fill — the way the fill tool and smart shapes already behave. **On a vector layer it stays
      an editable object.** Large enough to be its own project, not a single branch.
- [ ] **Say what an undo or redo just undid.** A brief notice naming the action, using the same
      transient notice mechanism already used elsewhere in the app (the owner does not recall where —
      find it and reuse it rather than adding a second kind). Must not block or freeze the screen.

Carried over:

- [ ] **17 fps drawing on a 4K canvas.** Diagnosed and **not** the compositor: one dab costs 53.8 ms on
      a vector layer at 4096² against 4.0 ms on raster, because `StrokeCanvasView.refreshDisplay`'s
      `.overlay` branch allocates a fresh canvas-sized bitmap per touch-move. `renderResolution` never
      reaches that path, which is why the owner's 50% test changed nothing. Fix is to give the scratch
      its own layer; wants its own branch. Numbers in BUGS.md.
- [ ] **Returning from another app freezes for a few seconds**, with no memory warning fired.
- [ ] **Leaving to the gallery takes ~3 s.** The thumbnail composites the full 4K canvas for a 320×320
      tile; already in BUGS.md.

## Done this pass

_(nothing yet — this pass began 2026-08-17)_
