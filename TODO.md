# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what *we* find.

## How to read and keep this file

Every item is a **status**, a short **description** a future session can pick up cold, and **what is
left** as a checklist. Items are in **queue order** — the top of the list is what to do next.

**An item leaves this file when it is merged, not when a branch exists**, and it leaves *whole* rather
than being marked done: `git log` and the spec documents are the history. The owner, 2026-09-06:
*"Basically I want to be able to read the tasks on TODO clearly without already finished tasks."*

**Three in flight at once** unless the extras need no simulator — the cap is about the machine, not the
plan (`tools/simlock.sh`).

**Before adding an item, check whether an existing one already covers it in different words.** A
restatement filed as a new item is how one feature came to be specified in six documents at three
scopes before a line of it was written. This file has since carried two live duplicates for weeks.

**Record an ask in the owner's own words, and fold a ruling into the item it rules on.** A quote is
cheaper to keep than a decision is to rebuild. But an item reads as *one current description*, not as
the transcript of the argument that produced it — what happened this pass belongs in
[HANDOFF.md](HANDOFF.md) and in `git log`.

**Cite a symbol, not a line number.** A 2026-09-06 audit found ~10 of one item's 15 `FILE:LINE`
citations and 5 of another's 11 no longer resolved — every named fact still true, every anchor wrong,
two of them because a file moved directory. A symbol name survives a refactor and a line does not.

**A bare item number in a spec or a code comment may name an item that has already left this file.**
That is the merge rule working, not a dangling reference: `git log` and the spec documents are where a
completed number resolves. Two are cited often enough to name here — **(10a)**, the Oklab colour ramps,
and **(38)**, the graph editor's bezier tangent handles and their tap grammar. Do not re-add a finished
item to this file to make a citation resolve.

**Verify a status before trusting it, including this file's own.** That same audit found fourteen
assertions here that the code contradicted — features called unbuilt that shipped weeks ago, a blocker
called live that had lifted, and two commit shas that are not on `main`.

**No document written so far has to survive.** The owner, 2026-08-27: *"Don't worry about legacy
documents right now, everything on the ipad right now is expendable."* A format change needs no
migration and no "existing documents change appearance" warning. This is standing permission, and it
lapses the day the owner starts keeping real artwork in the app — whoever notices that should say so
rather than assuming it still holds.

**The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works at
2048x1024, and every figure taken before 2026-08-17 was at 4096², eight times the pixels.

---

## (21) Keyframes — four stages and four gaps

**Status** — partly built. Stages 0, 1, 2, 2b, 3a, 3b, 4, 5, 5a, 5b, 7, 8 and 10 are merged; 6b was
delivered by (29); there is deliberately no stage 9.

A cel or an animation group carries a track of quad poses, ink is posed through the `sqrt(|det|)`
width rule with endpoints bit-exact, a pose channel has a six-curve graph-editor band that is
read-write, a transformation layer is reachable and usable, animation groups can be named, and every
pose key has a node.

**Left to build**
- [x] **Stage 7, live recording and an editable fps — merged, all three surfaces.** Editable fps
      (clamped 1-60, presets, live during playback, no undo step, persisted); §5.1's two-act arming
      per the owner's 2026-09-09 ruling (record turns blue and moves nothing, the take begins when the
      pencil lands); and every surface is recordable — the slider (effect and opacity channels,
      merged 2026-09-07), the Move box (2026-09-10, §5.2, `PoseRecording` — a container pose's four
      corners rather than a slider's one number, thinned by the largest single corner displacement
      rather than a mean), and the canvas (stage 10 below). A raster lift and a lassoed vector float
      refuse the Move box out loud, with the arm surviving. §5's slow-motion multiplier is
      **declined**, by the owner, 2026-09-10 — the editable fps already is the capture multiplier at
      no cost (the playback tick is `1.0 / fps`, so a scene recorded at 12 fps gives exactly twice the
      wall clock to perform in). See KEYFRAMES §5-§5.3.
- [x] **Stage 10, the timing recorder (§7) — built and merged 2026-09-10.** The owner gave the full
      brief on 2026-09-09 and it is larger than §7's laser pointer.

      > *"The user primes the recorder and selects the brush. Then as they put their pen on canvas, the
      > recorder starts and the user can draw while recording. This is just useful for timing. The
      > stroke will go on the cel of the layer that is active. The start and end of the stroke in the
      > cel will be where the stroke started and ended while that cel was active."*

      So one continuous gesture is **cut at cel boundaries by when it was drawn**, while playback runs
      under the pen: each cel keeps the arc the artist drew during it. That is roughing timing out in
      real ink, and it is a different thing from §7's laser-pointer trail — §7 is the *tail*, this is
      the ink.

      **The owner named the fork themselves and left the call to us**, with a hard ceiling on cost:
      > *"it is possible that this feature by itself (with the brush) may require extensive changes to
      > the engine. I do not want that. It is meant to be a relatively light feature. In the case that
      > doing the stroke baking thing costs too much, then just do this alternative workflow: The user
      > primes the record tool, then lays their pen down on the canvas (no need to select brush tool).
      > It will then do basically the same record stroke as before, but this time you can make it a
      > separate simple and specialized stroke engine, as part of the record tool instead of branching
      > off the actual brushstroke tool. Might be better or worse for clean architecture. Your call."*

      **A — the real brush, split live at each cel change.** The artist's own brush, so the ink is ink.
      The cut is a mid-gesture commit: close the stroke on the outgoing cel, open one on the incoming
      cel at the same point, carrying pressure and velocity so the seam does not show. Note this lands
      squarely in the scratch/base overlay lifecycle — the same code the disappearing-strokes fix is in
      — so the two must not be built at once.
      **B — a specialised stroke engine inside the record tool.** No brush selection, no reach into the
      shipped drawing path, and it is what §7 already specifies (a trail from `StrokeGeometry
      .stampRadius(forPressure:brush:size:)` plus the capsule chain, with decay-since-touch-down
      standing in for pressure). Cheap and contained, at the cost of a second thing that draws ink.

      **Built 2026-09-10 as A, and the measurement that chose it refuted the fork's own premise.**
      Both arms assumed the cut has to be a *mid-gesture commit*; it does not. The gesture already
      accumulates one knot stream and `commitVectorStroke` already walks **several runs** of it —
      that is what the selection clip does — so the cut is a **partition** recorded as indices while
      the pen moves and spent once at pen-up, with the target canvas varying per run. `TimingStrokeCut`
      is that partition, 97 lines and pure. Nothing in the stroke lifecycle moved: the single-cel path
      below the new early branch is byte-for-byte what it was. B would have had to invent an ink
      representation or reuse `VectorStroke`, at which point it is A with a worse brush.
      **What A did cost, and B would have cost identically, is the display**: playback engages the
      compositor unconditionally (`sandwichEngagesOnCanvas`'s `isPlaying` clause) and blanking is a
      `layer.mask` over the whole host, so the live scratch was inside it — an artist drawing during a
      take would have seen no mark at all. The trail is drawn by a sibling of the hosts now.
      **Two premises in this row were wrong and are worth recording**: "nothing refuses a touch while
      `isPlaying`" is true of *refusal* and false of the outcome — `canvasInteractionBegan` **stops
      playback** on the first touch, and its own comment names the cel-crossing hazard this feature
      turns into the feature; and "this lands squarely in the scratch/base overlay lifecycle, so the
      two must not be built at once" is true of a mid-gesture commit and does not apply to a partition.
      A frame with no block gets one, by the rule that already ships for touching a blank frame. One
      gesture is one undo press, blocks included.
- [ ] **Stage 6, bake to cels**, parked by the owner's 2026-09-06 scheduling ruling (stage 7 before
      stage 6) rather than dropped. It is cheaper than when it was planned — it shares its
      frame-walker with RENDER (29), which shipped, and the video bake merged 2026-09-06 is the same
      shape of operation with a worked pattern to copy. §6.
- [ ] A folder's pose channels are modelled and drawn but **cannot be opened into a graph band**,
      because `graphBandExpansion` is keyed by `layerIndex` throughout. Widening it to a
      `KeyframeTarget` is a stage, not a row — surfaced by the folder-transform work, KEYFRAMES §11.7.
**Spec** KEYFRAMES.md — **§2 is thirty owner rulings and §8 is the build order.** Four rulings
are superseded and kept; the file says which.

---

## (22) Select multiple cels at once

**Status** — not started, and **deprioritised by the owner 2026-09-07**. The menu row exists and is `.disabled(true)` with an empty action; no
cel-selection state exists. The keyframe half of the same idea is real and shipping.

---

## (10) Linear light as an option on the blend mode

**Status** — not started, and **deprioritised by the owner**.

No colour-pipeline setting, no sRGB/linear enum, no transfer LUT, no `Composite.metal` change.

**One adjacent strand did ship**: `ColorMath`'s sRGB↔linear and Oklab conversions feed the gradient
map, which is this item's own "Oklab still gets built, for interpolation" half. The code calls that
**(10a)** in eight places, corrected 2026-09-07 from a stale count of nine — `Effect.gradientTable`,
`EffectSection`, `ColorMathOklabLogicTests`, `EffectParityLogicTests` and `tools/oklab_ramp_ab.swift`
among them. It is finished, so it left this file by the merge rule and the citations stand; see the
convention above.

---

## (37) The brush engine — one stage, and the owner has dropped it

**Status** — stages 0 through 11 merged. **Stage 12, the importers, is dropped for now by the owner**
(2026-09-06: *"skip the importer for now"*), so there is nothing actionable in this item today.

Twenty brushes in five groups with every asset generated and no third-party content; opacity and flow
split with a per-stroke buffer; canvas-anchored texture; the brushes menu and the full-screen editor
with orderable module chains, noise octaves and second inputs; relocatable storage; two-axis scatter.

**Left, when the owner wants it**
- [ ] Stage 12 — the `.abr` / Procreate `.brushset` / Clip Studio `.sut` importers. All three are
      undocumented and reverse-engineered, so the stage opens with a survey against real files, not
      with a parser. Test files are a real dependency. §2.21 makes it an **adapter** onto §6's
      modulation matrix rather than a bitmap reader.

**Owner-side, not ours**: their tuning pass over the other nineteen presets, and driving a real Pencil
to exercise tilt, which no test here can reach. BRUSH.md §13 has **nine** genuinely open questions
(recounted 2026-09-07 — the sixteen bullets split seven answered/closed, nine still open; the "eight"
recorded here was a miscount on the day this line was written, not later drift). Three of the nine
were offered on 2026-09-06 and declined; which three is not recorded here and could not be verified
against a transcript this audit does not have.

**Spec** BRUSH.md — **§2 is thirty-three owner rulings.**

---

## (63) Glare and Colour Wheels — two more effects

**Status** — not started, asked 2026-09-11. **Low priority — the owner: *"these are not high priority
so they can be put anywhere in the queue."*** Both are new `Effect` cases; (60)'s six merges of
2026-09-11 (`70f793e` Recolour and `47c2d6a` Computer Screen for a whole case, `5ac52f0` for a field) are
the worked examples, and their two lessons apply unchanged: **`BakeKeyEncoder` must see every new field
or the frame store serves stale pixels**, and a cold-start XCUITest that asserts what is *drawn* is what
found both of that pass's defects.

> *"glare, and color wheels. Glare operates like blender's compositor glare. Different types of glare,
> sort of like bloom, etc. Color wheels are a color grading tool allowing the user to edit the luminance
> saturation and hue and strength (or some other combo, look to common ones in other color grading
> programs). It has 4 of these, one for global, highlights, midtones, and shadows. Try to put some effort
> into making the UI for it nice. 4 color pickers, plus their respective sliders. Also the same pinch to
> merge into ability for these like the HSV so I can bake them to the actual colors."*

- [ ] **Glare.** Blender's compositor Glare node has four types — *Fog Glow* (a wide soft bloom),
      *Streaks* (N directional streaks at an angle, fading), *Ghosts* (lens-flare ghost images mirrored
      about the centre) and *Simple Star* (a four-armed star) — each with a threshold, a mix and a
      size/iterations control. `Effect.bloom` already ships as four passes; Fog Glow is close to it, and
      Streaks and Star are directional blurs of the thresholded pass, so the multi-pass contract
      (`Effect.passes`) is the plumbing. A new `case glare(Glare)` with a `type` picker rather than a
      mode of Bloom, because the parameters differ per type. Both backends, byte-for-byte parity.
- [ ] **Colour wheels.** The four-way corrector every grading program has — DaVinci Resolve's Lift /
      Gamma / Gain / Offset, Premiere Lumetri's Shadows / Midtones / Highlights / Global: each wheel is a
      hue-and-saturation offset (the wheel) with a luminance slider beside it and a strength; the three
      tonal ranges are weighted by luminance with smooth overlaps and Global applies everywhere. A new
      `case colorWheels(…)` with four wheels × (hue angle, saturation amount, luminance, strength) as
      keyable `EffectParameter`s, and a settings bar that draws **four actual wheels** — the owner asked
      for effort on the UI. Oklab for the offsets is consistent with the gradient map's ruling.
- [ ] **Merge-down bakes both** like every other grade — the `hsvShift` precedent, a `MergeBakeLogicTests`
      row each.

---

## Later — the long-term features

**None of these are designed, and each needs its own conversation with the owner before it starts.**

- **(27) Screen-record the computer as a layer.** Requires (26). The app does have `Transferable` and
  `UTType` now; what is genuinely absent is the *drop* gesture — no `onDrop`, `dropDestination`,
  `NSItemProvider` or `fileImporter` anywhere.
- **(28) Audio.** Its stated blocker is **gone** — `PlaybackClock` is a drift-free wall-clock frame
  counter on the model, delivered by RENDER stage 1, which is exactly the hoist this item said it
  needed. `AVFoundation` is linked (for video), though no audio playback code exists.
- **(30) Video editor.** Its RENDER dependency is met — (29) shipped in full on 2026-09-06.
- **(35) Advanced masks** — colour-range masks and a colour-reassign blend mode. `MaskSource` has two
  cases and there are 25 blend modes with no reassign.
---

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.
