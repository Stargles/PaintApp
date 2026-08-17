# TODO

The owner's asks, live. **This file is theirs; [BUGS.md](BUGS.md) is ours** — bugs an agent found and
wrote down go there, things the owner asked for go here. An item leaves this file when it is done and
merged, not when a branch exists.

**At most three items may be in flight at once**, unless the extra ones need no simulator — reading,
docs and pure-arithmetic work do not contend and may overlap freely. The cap is about the machine, not
the plan: this Mac has 8 cores, and five concurrent test runs took it to 1–3% idle, at which point
suites start returning *wrong answers* rather than slow ones. See `tools/simlock.sh`.

## In flight

- [ ] **Drawing on a 4K canvas runs at 17 fps** — and setting render resolution to 50% changes nothing,
      which falsifies the leading theory (that the cost was Core Animation minifying three canvas-sized
      sandwich layers). The bottleneck is resolution-independent. Needs a fresh diagnosis, on device.
- [ ] **Snap does not engage** — pen down, shape formed, add a finger, nothing happens. Root cause
      identified as `UIView.isMultipleTouchEnabled` defaulting to `false` on every canvas view, so a
      second touch arriving in a *later* event is dropped before any recognizer sees it. Fix is written;
      **needs device confirmation**, and carries an explicit palm-rejection guard that must be verified
      with a resting hand.
- [ ] **Returning from another app freezes for a few seconds**, with no memory warning fired.

## Queued

- [ ] **Lasso bridges the gap** — a stroke that leaves the selection and re-enters is treated as one
      stroke instead of two.
- [ ] **Lasso responds to a finger while pencil-only drawing is on.** Related to the snap finding: both
      are finger touches going somewhere they should not, or not arriving where they should.
- [ ] **Leaving to the gallery takes ~3 s** — presumably the save. The thumbnail composites the full 4K
      canvas to make a 320×320 tile, which is the leading suspect and is already in BUGS.md.

## Done this pass

Value layer Mode merged into Blend Mode · Adjust icon removed · timeline scrubbing past frame 12 ·
block resize pushes neighbours, with shuffle UI · add-drawing menu gated and the three timeline
popovers collapsed into one · layer drag un-nesting · pinch-to-merge · stroke sampling reworked so a
stroke's cost follows its length, not its duration · oval handles rotate with the opposite node
anchored · shape handles sized in screen points · compositor moved onto the GPU with a device-aware
memory budget (merge still gated on the 17 fps question).
