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

**Status** — Glare shipped 2026-09-12; Colour Wheels not started. **Low priority — the owner: *"these
are not high priority so they can be put anywhere in the queue."*** Both are new `Effect` cases; (60)'s
six merges of 2026-09-11 (`70f793e` Recolour and `47c2d6a` Computer Screen for a whole case, `5ac52f0`
for a field) are the worked examples, and their two lessons apply unchanged: **`BakeKeyEncoder` must see
every new field or the frame store serves stale pixels**, and a cold-start XCUITest that asserts what is
*drawn* is what found both of that pass's defects.

> *"glare, and color wheels. Glare operates like blender's compositor glare. Different types of glare,
> sort of like bloom, etc. Color wheels are a color grading tool allowing the user to edit the luminance
> saturation and hue and strength (or some other combo, look to common ones in other color grading
> programs). It has 4 of these, one for global, highlights, midtones, and shadows. Try to put some effort
> into making the UI for it nice. 4 color pickers, plus their respective sliders. Also the same pinch to
> merge into ability for these like the HSV so I can bake them to the actual colors."*

**Glare shipped 2026-09-12: Streaks, Simple Star and Fog Glow, one `case glare(Glare)` with an in-bar
Type picker** (`EffectSection.swift`'s Computer Screen precedent — one catalogue entry, not a
`displayName` split — rather than `Blur`'s). Streaks and Simple Star are three passes always, whatever
`streaks` is: Bloom's own threshold kind, one new gather kind that loops over every direction inside a
single dispatch, and Bloom's own combine kind — the multi-pass contract hands a pass only its
predecessor and the effect's unchanged original, never a *named* earlier pass, so `N` independent
directions cannot be `N` chained blur-kind passes without each one blurring the direction before it
instead of the shared bright pass. Simple Star is Streaks at two directions (0°/90°, or 45°/135° with
`rotate45`) and Fog Glow **is** `Effect.bloom` at a derived radius, both reached by literal delegation
and pinned byte-for-byte in `GlareEffectLogicTests`. **Ghosts (the fourth type — mirrored, scaled
copies of the bright pass about the frame centre) was not built**: three types were the ask the effort
went into, a fourth is a nicety the brief itself named optional, and each iteration is a full resample
pass of `DuplicateOffset`'s own shape rather than sharing one dispatch the way a streak direction does —
see `Effect.Glare.GlareType`'s doc for the reasoning, not a half-built case anywhere in the code.
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
