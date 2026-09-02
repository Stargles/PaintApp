# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## State

**`main` is `5152c55`.** `git fetch` before trusting any of this — `origin/main` is a shared ref.

**Two branches were in flight when this pass ended at a usage limit** and both were told to commit
before they died, which this repo has learned to do because a background agent does not survive a 429
and its committed work does. Check them first:

```bash
git worktree list && git branch -a
```

- **`tmp/distort-raster`** — LASSO_MOVE stage 5, Distort's raster tier. Two commits at last look
  (`0bcc0c7`, `bff05f5`), rebasing onto `c1ca875`. It touches `Views/CanvasView.swift`, which stage
  4d rewrote, so its conflict there is real and must be resolved by understanding both sides.
- **`tmp/keyframe-transform`** — KEYFRAMES stage 5, the transform channel. `PoseInterpolation.swift`,
  `AnimationGroup.swift`, `TransformChannel.swift` plus edits to `TextObject.swift`,
  `VectorLayer.swift`, `Cel.swift`. It was mid-build.

**Neither has been reviewed or merged. Harvest their commits, do not trust their working trees** — a
worker's tree legitimately holds deliberate poison from mutation testing, and this repo shipped that
to `main` once.

**Fast tier at `c1ca875`: 2476 total / 2473 passed / 0 failed / 3 skipped.** Up from 2351 at the
start of the pass. **No full suite was run**, and the sandwich path changed structurally, so **the
next session owes one** — on an idle machine, after the two branches above are resolved.

## RENDER (29) stage 4 is merged and the app runs on it

[RENDER.md](RENDER.md) is the specification. **§2 is sixteen owner rulings; read them rather than
re-deriving them.** §5 is the build order.

Stages 0 through 4 are merged. `Engine/FrameBakeKey.swift`, `FrameBakeStore.swift`, `BakeQueue.swift`,
`DecodedFrameRing.swift` and `FrameBaker.swift` are the store and the scheduler, and **the live canvas
at rest and playback are served from the bake**. What stage 4 still owes is small:

- **The timeline's baked-frame indication.** `FrameBaker.isBaked(atFrame:)` and `onFrameFinished` are
  its read path and nothing consumes them yet. `TimelineRulerView.draw` (`TimelineTrackView.swift`)
  is the only per-frame drawing loop in the timeline and is document-wide rather than per-layer, so it
  is the natural home. Mind `TimelineLayoutKey`: a per-frame baked set changing on every bake would
  move a key compared on every layout — give the ruler its own `setNeedsDisplay()` path the way
  `movePlayhead` does.
- `FrameBaker.reset()` and `markEverythingDirty()` have tests but **no app caller**, because a re-root
  discards the whole baker. Either wire them or delete them.
- The compression ratio on the owner's own **"UI Test"** document, and a decode against a frame the
  *compositor* produced rather than one drawn for the purpose. PERFORMANCE §10.4 records both as owed.

**Stage 5 is next: strips (§3.8), then remove `affordableSize` from the live path.** It is now the
only thing between the app and §2.12's "the knob is the truth" — and stage 4d put the bake and the
live halves on one buffer size, so removing `affordableSize` from `liveCompositeSize` moves both
together. Then §3.9, export, which reads the bake and re-renders nothing.

## What this pass established, and would otherwise be re-derived

- **A content-addressed disk store cannot be built out of this app's `Hashable` conformances.**
  `LayerContentVersion.hash(into:)` deliberately omits `effect` and is right to — every in-memory
  cache here compares `==` after the bucket lookup, so a collision costs one compare. A store whose
  filename *is* the digest has no second chance. `FrameBakeKey` is a hand-written canonical byte
  encoder: a discriminator per enum case, a length prefix per collection, floats by `bitPattern`, and
  **no `default:` clause anywhere**, so a fourteenth `Effect` case is a compile error rather than a
  silent collision on disk.
- **`COMPRESSION_LZ4` is not portable** and §3.5 named it for portability. Apple's constant wraps the
  stream in `bv41` block framing no other LZ4 decoder reads. It is `COMPRESSION_LZ4_RAW`.
- **The per-row Up filter §3.5 held in reserve loses.** MEASURED: it makes every fixture *bigger*
  (cel art +39%, hold +28%) and costs 4.3–8.9 ms each way against a 1.5 ms decode. Refuted, not
  deferred.
- **Decode tracks pixels, not file size.** A hold is a quarter of cel art's file and decodes *slower*
  at every size. A ring budget must therefore mean *decoded* bytes.
- **The simulator inverts this measurement.** Between Debug/simulator and Release/device the two halves
  of the decode moved in opposite directions — LZ4 8.9 → 1.4 ms, `CGImage` build 0.8 → 2.6 ms. Debug
  reads as "the codec is 91% of the decode"; the device reads as the reverse. PERFORMANCE §1's
  "device is ~1.3x the simulator" is a *compositing* rule and does not generalise.
- **There is no push funnel in this model that knows a frame.** `beginCanvasEdit()` runs *before* an
  edit; `recordUndo`'s stored closures bypass it on replay; and a dab lands in `VectorCanvas` /
  `RasterLayerTexture`, which are classes, so `@Published var layers` is never written. Dirty marking
  is a **sweep** — `FrameBaker.syncDirty()` diffs the cel layout against the layout last seen, once
  per `reconcileLayers` pass, which is an identity rather than an estimate: the passes that publish
  are exactly the ones that used to move `SandwichKey`.
- **§3.6's claim that `isSandwichRebuilding` is a drop-if-busy was wrong.** `finishSandwichRebuild`
  ends in `reconcileLayers()`, which re-derives the key and starts the rebuild the guard declined — it
  always was coalesce-and-retry. Deleting it hands a two-second scrub ~120 serial jobs. §3.6 now says
  so.
- **§3.6's "same worker and same memo" is bought by the buffer size, not the queue.**
  `PixelOps.rasterize` and `MaskResolver.CacheKey` are keyed on width and height, so the bake mints at
  `.liveComposite` rather than `.native` and the halves stayed on `sandwichQueue`.
- **"Rest" is an eventual state now** — MEASURED 0.40 s after a stroke, 0.024 s after a frame step.
  Every instant assertion on it is a race; `PaintUITestCase.waitForSandwichState` is the helper.
  `"off"` is deliberately not waited for, because disengaging is synchronous.
- **`CanvasManager.renderResolution` writes through to `UserDefaults`**, so it is process-wide *and
  persists in the simulator container*. A suite that left it on `.half` produced 15 reds in a *later*
  fast tier, across `EffectLayerLogicTests` and `PerfBaselineTests`, all of them half-resolution
  artifacts of a previous run. Pin it in `setUp`, restore in `tearDown`, exactly as with
  `Compositor.backend`.
- **A ring top-up needs an outward-only marker or it does not terminate.** The ring is routinely
  narrower than the lookahead, so a plain rescan fills a far frame, evicts a near one, finds the near
  one missing, and never converges — while leaving the far end resident, which is backwards.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do. The cap is **3 opus or 6 sonnet at once**
   (1 opus = 2 sonnet), raised 2026-09-02.
2. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be", no narrating which premise an investigation
   overturned.
3. **A replaced path is deleted, not left beside the new one.** RENDER §2.15 in the owner's words:
   *"very clean and non-redundant, with no peculiarities, and no legacy code left by the previous
   functionality."*
4. **At most one investigation agent at a time.** Building is separate.
5. **Weighty programs may be killed to free the machine.** Standing permission.

## Traps this pass paid for

- **A test table that builds a fresh fixture per row compares allocation addresses.**
  `LayerContentVersion` names a cel's tiers by `ObjectIdentifier`, so two `CanvasManager`s differ in
  every leaf before anything is mutated — a per-field digest table built that way passed with the
  field under test **deleted from the encoder**. Mutate one fixture cumulatively.
- **`Layer.layerEffect` is `kind == .value ? effect : nil`** and the whole render path reads that
  accessor, so `layers[0].effect = …` on a raster layer is inert. Forty test rows were setting
  nothing. `Layer.valueFill` is gated the same way. **Before trusting a green assertion, check that
  its two operands are the two things you meant to compare.**
- **The obvious fixture for §2.16 measures nothing.** A cel spanning frames 2–6 *is* a hold, so those
  five frames are one key and one composite — the §3.3 dedupe eats the very thing the test counts.
  Every frame needs its own picture before "five frames re-rendered" is expressible.
- **`CompositeProbe` counts calls to `Compositor.composite`, which is chunks, not frames.** Pin
  "one small frame is one composite" separately rather than assuming it inside another test.
- **A brief's prescription is a hypothesis.** Six were refuted this pass by the workers holding the
  code, and two of those were errors in the specification rather than in the brief. Invite the
  refutation explicitly; it is the cheapest review in the project.
- **`xcodebuild` waits on "Unlock Kevin's iPad to Continue" rather than failing** — one run sat twelve
  minutes and then completed by itself. PERFORMANCE §9 had given up at that same wall.
- **Three agents at once take this machine to 4% idle**, which is the band CLAUDE.md records as
  returning wrong answers rather than slow ones — and `PerfBaselineTests`' timing assertions are in the
  fast tier. `simlock`'s two slots throttle `xcodebuild` but not compiles. Check idle before treating a
  timing red as a finding.

## Everything else open

**The owner's asks** are in TODO. **(21) keyframes stage 5 and (12) LASSO_MOVE stage 5 are the two
branches above.** KEYFRAMES §8's **5b is *animated* Distort** — a quad keyed across frames, needing
the transform channel — while LASSO_MOVE stage 5 is the one-off Move-box Distort; they are two
different features and §2.13 makes a pose a quad so that they meet later with no migration.

(31) holds the large-canvas symptoms; its `minificationFilter` half is **fixed** (`4f85759`), and what
remains is that **16383² cannot be composited at all** and needs a downscaled display proxy. (32)-(34)
are small. (22), (24), (35)-(37) and (26)-(30) are unstarted, and the last group needs a design
conversation each.

**Deferred by the owner, not refused:** scaling the stroke sample gate by zoom, which would fix the 8x
dab explosion when zoomed out. It is a permanent quality trade, so it wants an A/B the owner can look
at, not a number.

**BUGS.md's memory audit** is the remaining ranked sites plus PERFORMANCE §9's. RENDER §5 stage 7 is
where they land.
