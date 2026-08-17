# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

## In flight

- [ ] **17 fps drawing on a 4K canvas.** Render resolution at 50% changes nothing, which rules out the
      compositor. Device run points at `vector layer render | firstRender=70.0ms` at 2048² — the layer
      being drawn on invalidates its own cache, and the resolution option scales the compositor but not
      the vector rasterization. `tmp/compperf`.
- [ ] **Snap does not engage** — pen down, shape formed, add a finger, nothing. Cause: every canvas view
      left `isMultipleTouchEnabled` at its `false` default, so a touch arriving in a *later* event is
      dropped before any recognizer sees it. Fixed on `tmp/shapefix`; **needs device confirmation, and
      testing with a resting palm** — a palm used to be harmless only because UIKit discarded it.
- [ ] **Returning from another app freezes for a few seconds**, with no memory warning fired.

## Queued

- [ ] **Lasso bridges the gap** — a stroke leaving the selection and re-entering counts as one, not two.
- [ ] **Lasso responds to a finger in pencil-only mode.** Likely related to the snap finding.
- [ ] **Leaving to the gallery takes ~3 s.** The thumbnail composites the full 4K canvas for a 320×320
      tile; already in BUGS.md.

## Done this pass

- Value layer's Mode menu merged into Blend Mode
- Adjust icon removed (its panel was an empty placeholder)
- Timeline scrubbing past frame 12
- Block resize pushes neighbours instead of shrinking them, with shuffle UI
- Add-drawing menu gated; three timeline popovers collapsed into one
- Layer drag un-nesting
- Pinch-to-merge
- Stroke cost follows a stroke's length, not its duration
- Oval handles rotate with the opposite node anchored; handles sized in screen points
- Compositor moved onto the GPU with a device-aware memory budget (merge gated on the 17 fps question)
