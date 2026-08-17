# Handoff — 2026-08-17

Written while winding down a session deliberately at its usage limit. **Verify everything here before
trusting it** — `git log`, `git worktree list` and [TODO.md](TODO.md) are the live state; this is
orientation. Read [CLAUDE.md](CLAUDE.md) first, then TODO.md (the owner's asks) and
[BUGS.md](BUGS.md) (what we found).

## The single most important fact, and it is new

**The owner animates at 2048×1024, or 1080p. Not 4096².**

Every performance number in this repo was measured at 4096², which is **eight times the pixels**. Any
area-scaling cost is overstated by ~8× against the document the owner actually uses, and a conclusion
drawn at 4K may be about a canvas nobody works on. The 53.8 ms vector dab, the 3 s gallery thumbnail and
the onion skin composite were all sized against the wrong document. **Benchmark at 2048×1024 and treat
4096² as the stress case.** Recorded at the top of TODO.md's queue.

The corollary is the useful half: costs that do *not* scale with area become relatively **more**
important at the smaller canvas, and the existing 4K-biased measurements will have buried them.

## What landed this pass — eleven branches, all merged

`main` is green at **1132 tests / 1128 passed / 4 skipped / 0 failed**.

Pinch-to-merge · the smart-shape snap · rectangle node dragging · a deterministic replacement for a
flaky timing test · both lasso bugs · the cel-decode data-loss fix · the Add Text architecture ·
one unified colour picker · the eyedropper (and its follow-up fix) · the undo/redo notice ·
the canvas-edge fill boundary and lasso flood fill.

Four of those are worth remembering for their *cause* rather than their fix, because the pattern repeated:

- **The snap** was `UIGestureRecognizer.requiresExclusiveTouchType`, which **defaults to `YES`** and was
  set nowhere in the app. A recognizer holding the pencil is closed to finger touches, and the filter
  runs *at binding*, so the recognizer is never offered the touch and its `ignore` hook never fires. The
  earlier `isMultipleTouchEnabled` fix was necessary but could never be sufficient: that flag is per
  **view**, exclusivity is per **recognizer**.
- **The eyedropper painted a stroke** because `shouldInteract` was a hand-maintained list of tool
  exclusions that nobody updated. Now `Tool.paintsOnCanvas`, exhaustive, no `default:`.
- **The undo notice** needed history entries to carry names; they did, as unenforced `String`s at ~70
  sites. Now `HistoryActionLabel`, so the compiler enumerates the call sites.
- **Rectangle node dragging** lost its anchor through a `= nil` default. The parameter is now required.

The recurring lesson: **make the compiler do the remembering.** Every one of those bugs was a value that
could go missing silently. Reach for an exhaustive switch or a required argument before a comment.

## In flight, and what to do with it

**`tmp/onion` — the only live branch.** Worktree at `../PaintApp-onion`. The ToonSquid-style onion skin
panel: Drawings/Frames, Behind/In Front, count sliders with loop, Tinted/Original, linked opacity,
per-slot sliders. Out-of-pegs is deliberately **out of scope** (owner's call) but the layout leaves room.

Its performance story is settled and is the interesting part. First device numbers were catastrophic —
190 ms for one skin, **1302 ms for ten**, at 4096². The orchestrator proposed reducing resolution;
**the agent measured instead and proved that wrong**: 627² writes 6% of the pixels but still costs 20%,
because `CGContext.draw(in:)` samples the whole source regardless of destination. The cost was source
reads. The fix was `OnionSkinRasterCache` — reduce each cel once per version, draw 1:1 — giving on device:

| | before | after |
|---|---|---|
| 1 skin | 189.6 ms | **11.9 ms** |
| 10 skins | 1302.2 ms | **136.9 ms** |
| peak memory | ~170 MB | **27 MB** |

**The branch is complete and green at `f09f1bc`** — 1123 / 1120 passed / 0 failed / 3 skipped, working
tree clean. Nothing is half-built. Four things to know:

**1. Resolution is now a setting, and Full is a trap.** Full/Half/Quarter, default Half, wired through
the panel to both cache keys. The fraction is applied and then raised to a `readableFloorEdge = 768`, so
Half of a 1024² canvas gives 768² rather than the 512² that failed the readability sweep. Measured on
the simulator at 4096²:

| | size | 2 skins (default) | 10 skins |
|---|---|---|---|
| Full | 4096² | 262 ms | **1495 ms** |
| **Half** | 2048² | **61 ms** | 380 ms |
| Quarter | 1024² | 15 ms | 93 ms |

**Full at ten skins is worse than the original broken implementation was.** Whether that needs a warning
in the UI is the owner's call and is unanswered. Note also the default costs 61 ms, not single digits —
Quarter is the cheap one. At 2048×1024 divide by roughly eight.

**2. The `skins5 > skins10` non-monotonicity is explained, and it was not what I guessed.** Not
cache-miss ordering — that is ruled out by reading: the three `skinsN` figures call
`OnionSkinFrame.composite` directly on frames built from one image made before the loop, `composite` is
pure and touches no cache, and `OnionSkinRasterCache` is not reached until `sourceMiss`. The reading is
a **cold CPU**: `skins1` is ~5 ms, far too short a burst for iOS to raise the clock, so `skins5` was the
first sustained work and paid the ramp. The harness now warms up, times without the sampler thread,
takes the minimum of five, and reports `skins5Cold`. **If the device does not confirm it, the new
monotonicity assertion fails the test rather than printing a misleading number** — which is the right
outcome either way.

**3. Not written down anywhere else: the device/simulator ratio for this workload is ~1.1×.** That is
how to project every number above onto the owner's iPad.

**4. Also undocumented: Half + 10 skins + 4K thrashes.** Only ~3 cached sources fit against a 10-skin
window, so every rebuild pays ~7 misses. Quarter is the setting for that combination.

**Left to do**, in order: device re-run of both perf tests · the owner's ruling on whether Full needs a
warning · rebase onto `00ae6fb` or later · merge. The agent's `CanvasView.swift` conflict surface is
exactly two places — `updateUIView`'s call order (it moved `updateOnionSkin()` up deliberately, so
"In Front" out-ranks `sandwichAbove` but sits below the chrome overlays) and `makeUIView`'s subview
construction. A trial rebase was clean.

**Drawings vs Frames is settled** — the owner confirmed the semantics (Drawings steps by drawing
ignoring hold length; Frames steps by timeline frame, so several slots can resolve to the same drawing).

## The lasso flood fill may not do what the owner asked, on either layer kind

It merged, and its outer-boundary behaviour is right. But the core promise — *interior lines get filled
over* — is in doubt on **both** layer kinds, for two different reasons, and both are in BUGS.md:

- **Vector**: `VectorCanvas` orders elements fill=0, image=1, stroke=2, so fills render beneath strokes
  and the dividing line draws straight back over the fill.
- **Raster**: `Cel.fillImage` is documented as the bottom compositing tier, under `raster`'s live
  strokes, and both `PixelOps.rasterizeUncached` and `commitInteractiveFill`'s raster branch draw
  `cel.raster` last. So a line already on the same layer stays visible over a new lasso fill.

The raster finding was reached by reproducing the two draw calls in isolation, **not** by running the
gesture in the app — so it is high-confidence but unconfirmed end to end. **Confirm on the device before
acting**: draw two compartments divided by a line on one raster layer, lasso across both, and see
whether the line disappears. That is a thirty-second check and it decides whether this feature needs
real work or none.

## Owner asks still queued

Add Text stage 1 (the plan is in [ADD_TEXT.md](ADD_TEXT.md), six stages, decisions settled) · the
oval-and-partial-oval unification (one feature, no modes — the owner explicitly removed the
arc-vs-oval decision, and reintroducing a mode there is a misreading) · the onion panel finishing above.

**A performance investigation was launched and deliberately cancelled** when usage ran short — ten
agents over the drawing hot path, compositing and invalidation, memory, the app-switch freeze, timeline
and playback, and save/load/startup, then a three-lens ranking and a synthesis. Its script survives at
`.claude/projects/.../workflows/scripts/perf-investigation-wf_f6c930aa-045.js` and can be re-run as-is.
**Its whole point is the recalibration at the top of this file**, so it is worth re-running rather than
re-deriving. It was designed read-only so it never contends for simulators.

## Two questions the owner has not answered

- **Save semantics.** When a project loads and something in it was unreadable, may saving overwrite the
  good original? A backup of the pre-save package exists, so the intact file survives. Refuse, save-as,
  or prompt — all three change save behaviour for undamaged projects too, which is why the cel-decode fix
  stopped at recording counts and logging them.
- **Which faces belong in the font picker's favourites strip** (they asked for one; Add Text stage 1).

## Process, confirmed again this pass

- **Agents park on test runs without committing.** It happened four times. Read their worktree directly
  (`git log`, `git status`) rather than waiting for a resume round-trip, and **message them to commit** —
  never commit into their worktree yourself, it races their own commit.
- **`-only-testing` takes CLASS names, not FILE names.** After the session-24 split one file holds
  several classes, and a selector naming a file that is not also a class matches nothing **and still
  prints green**. This cost two silently-skipped tests in one merge and nearly shipped them.
- **Take the test count on both sides of a merge and account for the delta exactly.** Every close-out
  this pass did, and it is what proved nothing was dropped across eleven rebases.
- **The owner's device reports keep being right**, and twice this session the orchestrator told them
  something about their own build that was wrong by reasoning from branch state instead of from what was
  installed. **Check what the build actually contains before telling the owner what they are seeing.**
