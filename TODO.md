# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

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

- [ ] **17 fps drawing on a 4K canvas.** Diagnosed and **not** the compositor: one dab costs 53.8 ms on
      a vector layer at 4096² against 4.0 ms on raster, because `StrokeCanvasView.refreshDisplay`'s
      `.overlay` branch allocates a fresh canvas-sized bitmap per touch-move. `renderResolution` never
      reaches that path, which is why the owner's 50% test changed nothing. Fix is to give the scratch
      its own layer; wants its own branch. Numbers in BUGS.md.
- [ ] **Returning from another app freezes for a few seconds**, with no memory warning fired.
- [ ] **Leaving to the gallery takes ~3 s.** The thumbnail composites the full 4K canvas for a 320×320
      tile; already in BUGS.md.

## Done this pass

- Value layer's Mode menu merged into Blend Mode
- Adjust icon removed (its panel was an empty placeholder)
- Timeline scrubbing past frame 12
- Block resize pushes neighbours instead of shrinking them, with shuffle UI
- Add-drawing menu gated; three timeline popovers collapsed into one
- Layer drag un-nesting
- Stroke cost follows a stroke's length, not its duration
- Oval handles rotate with the opposite node anchored; handles sized in screen points
- Compositor moved onto the GPU with a device-aware memory budget (merge gated on the 17 fps question)
