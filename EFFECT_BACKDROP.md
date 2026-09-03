# Effect backdrop — what an adjustment layer grades

The specification for [BUGS.md](BUGS.md)'s *"Every effect and blend mode is masked to the layer's own
ink"*, opened 2026-08-27 off the owner's device report and their ruling on it. **Everything in it is
settled — §5's four questions were answered the same day and two of them overruled the recommendation.
§6 is the build order.**

## §0 — What is already true, verified rather than assumed

> **STALE BY CONSTRUCTION — READ THIS FIRST.** This section describes the tree **before this document's
> own build order (§6) ran**, and §6 has since shipped (`2a0379d`, `d90b329`, `5c00201`). Its first
> bullet in particular — *"The paper is not in the composite"* — **is no longer true**:
> `SandwichRecipe.resolve()` now builds `full` and `below` with `background: paper`
> (`Engine/FrameRecipe.swift:230-231`), both backends fill it, and `EffectLayerLogicTests:1491` is
> `testEveryBlendModeBlendsAgainstThePaper`. Only the disengaged Core Animation path still has the
> paper as a plain view. **A shipped spec's what-is-already-true section is the most
> confidently-worded stale text in the repo** — it carries the commits it was verified at, so it reads
> like a fresh statement of current behaviour and is a statement of the past. On 2026-08-30 it was
> quoted as current to the owner and produced a wrong scope argument for TODO (10). Kept rather than
> rewritten, because the *before* picture is what makes §2's reasoning legible.

Every line here was opened by two agents independently, at commit `500a53e`/`f5126d8`.

- **The paper is not in the composite.** It is a `UIView` painted behind the layer host
  (`CanvasView.swift:39-43`, `updatePaper()` at `:540-552`), added before the two sandwich image views
  that carry the composite (`:57-60`).
- **Every live-canvas request says so explicitly.** `makeSandwichRequests` builds all three halves with
  `background: nil` (`RenderRequest.swift:547`) and the doc at `:472-476` gives the reason: the live
  canvas paints its own `paperView`, a background in `below` would be a second one, and a background in
  `above` would be an opaque sheet over everything beneath it. **That last clause stays true under every
  option below** — `above` keeps `background: nil` whatever we do.
- **`RenderBackground` was designed for this disagreement.** Its doc (`RenderRequest.swift:249-259`)
  says the two consumers disagree and both are right, which is why it is a request-level choice. **The
  only caller in the app that passes a background today is the eyedropper**
  (`CanvasManager+Eyedropper.swift:52`) — which is why README can say the eyedropper samples the
  composite "paper included" while nothing else does.
- **An effect grades the accumulator, not its own layer.** `Layer.layerEffect` is
  `kind == .value ? effect : nil` (`Layer.swift:120`) and a value layer holds no pixels. Metal grades
  `front` (`MetalCompositor.swift:648-668`), CoreGraphics grades `context.currentImage`
  (`Compositor.swift:853-880`). Both dispatch over the full canvas — there is no scissor, no
  content-bounds rect, and `mix()` never uses the layer's alpha as a mask.
- **The background is filled into the accumulator *before* the walk**, premultiplied, with a nil
  background meaning a transparent clear rather than a skipped step (`MetalCompositor.swift:597-605`;
  `Compositor.swift:675-677` via `UIRectFill`).
- **So the kernels are correct and the input is wrong.** Every kernel short-circuits on alpha 0 —
  `if (!(alpha > 0.0f)) { … }` at `Composite.metal:773` (generic) and `:572` (chromatic aberration),
  CPU twins at `EffectKernels.swift:96` and `:279` — because a transparent pixel has no colour to
  unpremultiply. grade(transparent) = transparent, `mix` writes the backdrop back unchanged.

**Nothing in the effect subsystem needs fixing. The backdrop handed to it does.**

## §1 — The ruling

The owner, 2026-08-27, shown both options and taking the more expensive one:
**"Paper is part of the picture, but rescue those three."**

So: the paper becomes part of what an adjustment layer grades and what a blend mode blends against —
fixing the reported effect, seven others and twenty blend modes at once — **and** Outline, Bloom and
Sobel keep a way to see the ink alone rather than being allowed to regress.

**Sobel's half of that was withdrawn on 2026-08-27** — *"drop it"* — once the ink-only route was measured
and found to render nothing on a white canvas and nothing on black line art (§2.2, §5.2). Outline's
fixed `.ink` and Bloom's artist-facing one are what the rescue amounts to; Sobel does not need one,
because the alpha rule alone gives it the look the owner asked for.

## §2 — The consequences are inherent, not incidental

The first two were found by review before any code was written; the third arrived on 2026-09-03 as a
device report and is the same rule reached from a place nobody had looked. None is a tuning problem,
and it is worth being precise about *why*, because the instinct is to treat them as bugs in the fix.

### 2.1 Once an effect grades the paper, the composite is opaque from that node up

This is not a choice. If an artist brightens the canvas, the result **is** opaque — there is no longer
a transparent region to see through, because the thing that was transparent has been graded into a
colour. Any design that produces the correct picture produces an opaque one.

**That hides the "Behind" onion skin.** `onionSkin` is added to the container at `CanvasView.swift:49-50`,
*before* `sandwichBelow` (`:57-58`) and `sandwichAbove` (`:59-60`); the comment at `:54-56` states the
invariant outright — the disengaged z-order is `onionSkin < below < above < chrome` — and
`updateOnionSkin` routes the `.behind` placement to exactly that lower view (`:2311-2315`). The Behind
ghost is visible today **only because the composited images have always been transparent where the
artist has not painted**, which is the same transparency that is the bug.

**RULED 2026-08-27, and the ruling is what makes this cheap.** The owner: *"Onion skin goes over
compositing so user can see it clearly."* So the ghost is **not** composited into the request and is
**not** graded by any effect — it moves up in z-order instead, from below both sandwich views to
**between them**: above `sandwichBelow`, below `sandwichAbove`. The disengaged order becomes
`below < onionSkin < above < chrome`.

That is a **z-order change in `CanvasView`, not a compositor change**, and it deletes the whole
"composite the onion-skin frames into the `RenderRequest`" branch this document previously carried as
mandatory. `below` is opaque under §6 step 3, so a ghost drawn on top of it is visible by construction,
and `above` keeps `background: nil` so artwork on layers over the active one still covers the ghost —
which is what `.behind` means.

**THE PARAGRAPH THAT USED TO SIT HERE WAS WRONG, AND REVIEW CAUGHT IT BEFORE IT SHIPPED.** It said the
change *"differs only with layers beneath the active one and Behind placement selected"*. That is true
of the **mid-stroke** split and false at **rest**, which is where the artist actually lives — mid-stroke
lasts as long as a touch is down.

At rest the sandwich puts the **whole tree** in the lower view (`belowView.image = images.full`), sets
`aboveView.image = nil` and hides it, and blanks **every** layer host. So a ghost fronted above
`belowView` has nothing left to cover it: it paints over the layers above the active one, over the
active layer's own ink, and over the layers below. **`.behind` becomes pixel-identical to `.inFront`,
and one of the two placements is silently lost.**

Scope is wider than effect layers, because engagement is `needsCompositorOnCanvas` — any non-normal
blend mode, any alpha mask, any clip-to-below, any buffered group. One multiply shadow layer is enough.

**RULED 2026-08-27, and it took three passes, because the first two rulings were made against a cost
nobody had measured yet. The answer is (a): the ghost always draws on top, and Behind and In Front
coincide whenever the compositor engages.**

The sequence is worth keeping, because each step was reasonable on what was known and each was wrong:

1. *"Onion skin goes over compositing so user can see it clearly."* Correct about visibility, and it
   is what deleted the compositor change this document once called mandatory.
2. Shown that the literal reading collapses two placements into one, the owner chose **(b)**, keep
   Behind meaning behind. This document then described (b)'s cost as "a little extra compositing work"
   — and that description was wrong twice over. It is not extra compositing work at all (`full`,
   `below` and `above` are all three composited on every rebuild already, so the split *swaps* rather
   than adds), and the cost it does have was not compositing time, it was **the picture**.
3. Shown a rendered comparison, the owner chose **(a)**. That is this section's ruling.

**What the picture showed, and it is the fact both earlier rulings were made without.** `CanvasView`'s
own design note states the guarantee outright: at rest the canvas is `composite(full)` in one image,
*"exact for every mode and every nesting, byte-identical to the thumbnail"*, and **"lift is what snaps
it back"** — the mid-stroke approximation is tolerable precisely because stopping returns the artist to
the truth. Drawing the canvas in two pieces so a ghost can sit between them costs the **selected**
layer its backdrop, so its blend mode degrades to normal: `blendOver`'s `mix(cs, B(cb,cs), da)` sees
`da == 0` inside a half composited onto transparency. MEASURED on a multiply layer over a painted
floor: **max channel delta 121**, and it does not read as a 121 — a correctly-multiplied dark navy
blob renders as raw saturated blue. The layer *above* the active one measured **0**, so the loss is
narrow and total rather than broad and slight. Under (b) that would have been the **default** state,
because `isOnionSkinEnabled` defaults to true and `OnionSkinSettings.placement` defaults to `.behind`.

**So the z-order change stays and the at-rest split does not.** The ghost is fronted above
`sandwichBelow`, which mid-stroke puts it under the active layer's host and over the layers below —
`.behind` still means behind while a stroke is down. At rest the whole tree is in the lower view, so
the ghost is over everything and `.behind` reads as `.inFront`. **That collapse is now the accepted
behaviour, not a defect**, and it is scoped to documents `needsCompositorOnCanvas` answers true for —
any non-normal blend mode, alpha mask, clip-to-below or buffered group. A document with none of those
keeps both placements exactly as it always had them.

**The third option, and why it is recorded rather than taken.** Painting the ghost onto the paper
before the walk would restore the original meaning of Behind — under all the artwork, visible because
the paper is opaque — and would keep the at-rest composite a single exact image. It was offered and
declined, because it makes the ghost part of the picture *beneath* the artist's layers: an effect
layer would grade it and a multiply layer would multiply against it. Do not re-adopt it without
re-asking.

### 2.2 Once the paper is in the accumulator, alpha stops meaning coverage

Outline, Sobel and Bloom do not read colour, they read **shape**:

- **Outline** keys on `src.a > threshold` (`Composite.metal:696-698`, default 0.5 at `Effect.swift:364`).
  With an opaque backdrop that is true for every pixel and Outline is a **complete no-op**.
- **Sobel** convolves and emitted `(0,0,0,0)` in flat regions (`Composite.metal:655-670`), which is why
  the paper showed through it. **THE SENTENCE THAT USED TO FINISH THIS BULLET WAS FALSE AND IT SHIPPED.**
  It read *"With an opaque backdrop flat regions become opaque black"*, and that claim is the entire
  justification for §4's ruling that Sobel default to `.backdrop`. The kernel emitted `(m, m, m, m)` —
  **alpha *was* the magnitude** — so a flat region came out fully transparent no matter what image it was
  handed. No backdrop, opaque or otherwise, could have made it black.

  What the ruled default actually produced was a **hole**: `mixBack` is a crossfade, so at opacity 1 the
  graded image replaces the accumulator, paper included; `CanvasView.updateSandwich` had already called
  `paperIsNowPaintedBy(true)` and hidden `paperView`; and what was left behind a transparent composite is
  `paddingBackdrop` — `UIColor(white: 0.85)`, `CanvasView.swift:34`, byte **217**. The owner reported it
  within the hour, from their iPad: *"weird, sobel should be black mostly but right now its grey."*

  **What is true, as of 2026-08-27**: the alpha is `src.a`, always. Sobel writes back the coverage it was
  handed, so over the paper the flat regions really are opaque black and the edges are bright, which is
  the look §4 ruled. `src.a` rather than a literal 1, so the padding margin (§6 step 3's artwork rect)
  stays transparent.

  **For a few hours that rule was a per-mode choice carried by an `EffectParams.preserveAlpha` scalar,
  because `.ink` needed the old `(m, m, m, m)`. The owner deleted `.ink` the same day** — *"drop it.
  Remember to cleanly remove and delete the feature so no remnants of it are left in the code"* — and one
  rule needs no flag, so the scalar went with it and `EffectParams` is back to twenty packed fields. The
  two measurements immediately below are what killed the mode; they were made to justify keeping the
  flag and they read, on a second look, as the case against the setting existing at all.

  **Why three reviewers and a full suite missed it, which is the part worth keeping.** Every Sobel
  fixture in the suite was either a flat field or an impulse on transparency, and on both of those
  `(m, m, m, m)` and a correct opaque edge map are *the same bytes*. Nothing anywhere asserted what Sobel
  looked like over paper. `testSobelOverPaperIsAnOpaqueEdgeMapRatherThanAHoleInTheCanvas`,
  `testSobelOverAnOpaqueStepEdgeIsBrightEdgesOnOpaqueBlack` and `testNoEffectLayerCanPunchAHoleInThePaper`
  are the three that now do — the last of them generally, for every effect and every input, since the
  symptom was never a wrong colour, it was a hole. **A fourth followed from deleting the mode**: the
  impulse fixture in `EffectMultiPassLogicTests` had to move onto an opaque ground
  (`opaqueImpulseBytes`), because with the alpha rule unconditional a transparent ground clamps the
  magnitude out of the output and the published Gx/Gy table would read as nine zeroes whatever the
  stencil was. Same luminance field, so the same expected bytes.

  **The rule that needs no flag was measured and rejected**, so it does not get proposed again.
  `alpha = src.a` unconditionally fixes `.backdrop` on its own and adds no field to either backend — but
  it changes `.ink`, and not slightly. MEASURED 2026-08-27 over 64×64 line art (2–3px strokes plus one
  9px bar, 944 inked pixels): with **black** ink today's `.ink` Sobel lights **0** pixels — the kernel
  reads *premultiplied* rgb, and black ink is `(0,0,0)` inside the stroke and `(0,0,0)` outside it, so
  the luminance field is flat and the gradient is identically zero — and `alpha = src.a` would light all
  944, worst channel delta 255. With red or grey ink 1137 pixels are lit and **1404** would change:
  more pixels change than the magnitude ever reaches, because the ink's coverage and the magnitude are
  different *fields*, not the same field differing over a thick stroke's interior. The two rules are not
  close, so both are needed and the flag is what carries the difference.

  **Add to that: `.ink` Sobel was invisible on the default paper whatever the ink.** `(m,m,m,m)` over
  white composites to `m·255 + 255(1−m) = 255` for **every** m — the source-over arithmetic, not an
  approximation — so on a white canvas an ink-only Sobel renders nothing at all. The one test that could
  see the mode's output at all had to set the paper to grey 128 to do it; it was deleted with the mode.

  **Those two facts are why the setting is gone.** Together they say `.ink` Sobel shows nothing on the
  default paper, and nothing at all on black line art — the two commonest documents there are. That was
  put to the owner on 2026-08-27 and they ruled: *"drop it."* See §5.2.
- **Bloom** thresholds luminance (default 0.75, `Effect.swift:314`) and white paper is Lum 1.0
  (`Composite.metal:626-637`), so the entire canvas becomes a bright source.

The alpha channel of the accumulator *was* the ink coverage, and filling paper into it destroys that
information. **Rescuing these three means preserving the coverage somewhere.** The three shaders
themselves need no change under any option below — what changes is which image they are handed.

### 2.3 A merged adjustment layer cannot reproduce the picture it was part of

§1 says an adjustment layer grades — and a blend mode blends against — **the whole accumulator**: the
paper and every layer beneath it. A merge reaches exactly one layer. So the two cannot both be
honoured, and the merged result is necessarily a different picture from the one the artist was looking
at when they merged. That is arithmetic, not a bug in the merge.

**RULED 2026-09-03**, on the owner's report that a value layer set to HSV merged down into a vector
layer *"does nothing"*, and that *"this may be an issue other blend modes"* — it was both, and both had
one cause. The owner, shown the two shapes an answer could take:

> **The merged layer is that one layer's colours, transformed — Photoshop's answer.** The grade or
> blend is applied to the layer directly below and baked into it. Gaps where paper or another drawing
> showed through **do change appearance**, because the paper stops being graded once the adjustment
> layer is gone. That is accepted.

The rejected alternative was reproducing the picture exactly, which means baking the paper and the
whole stack beneath into the merged layer — and that makes it **opaque**, hiding everything under it.
That is §2.1 arriving in the layer panel: any design that reproduces the correct picture produces an
opaque one, and here the opacity is not confined to the canvas, it is written into the artist's
document.

**Where it acts**: `CoreGraphicsCompositor.mergedDown` (the composite: the lower layer alone as the
backdrop, on transparency, no `RenderBackground` parameter to pass a paper through even by accident),
`CanvasManager.mergeContribution` (what each layer of the pair *is*, resolved through the same three
accessors `leafSnapshots` reads), and `MergeBakeLogicTests`, whose
`testALayerBeneathThePairChangesNothingAboutTheMergedResult` is the ruling stated as an independence
and whose `testAMergedGradeLeavesTheUpperLayersGapsTransparent` is the assertion the rejected option
would have broken.

**One case stays a loss, and it is the mirror image**: a grading layer in the *lower* position acts on
everything beneath the pair, which the ruling excludes, so there is nothing inside the merge for it to
grade. `CanvasManager.MergeLossKind.unbakeableLayer` is the confirmation that warns about it — and the
two cases that predicate used to carry, a non-Normal blend mode and a `.value` layer in the upper
position, are gone, because both are baked now.

**An `.ink` effect needs no re-walk here**, which is worth stating because §3 exists entirely to give
one. The whole reason an ink-only input is needed is that the accumulator holds the paper and its alpha
has stopped meaning coverage (§2.2). A merge's backdrop is one layer on transparency, so `.ink` and
`.backdrop` are the same image — the same `paperInBackdrop: false` arm the walk itself takes inside
every buffered scope.

## §3 — Options for the ink-only input, with costs

The walk is bottom-up on a single accumulator and the paper sits at the bottom, so once it is in, it
cannot be taken out again. Four ways out, cheapest first to build:

| | Mechanism | Runtime cost | Parity risk | Verdict |
|---|---|---|---|---|
| **A. Re-walk** | When an `.ink` effect is reached, re-run the sub-walk below it into a fresh transparent buffer, grade that, composite the result over the paper-inclusive accumulator | One extra sub-walk per ink-effect node. `needsOwnBuffer` (`RenderTree.swift:234`) already exists for effect nodes, so the buffer is not new | **Lowest** — reuses the walk both backends already implement identically | **Recommended.** No new texture, no per-leaf cost, no shader change |
| **B. Coverage texture** | Maintain a canvas-sized R8 alongside the accumulator; every leaf also writes `cover = cover + a(1−cover)`; `.ink` effects read it instead of `src.a` | ~2 MB at 2048×1024, one extra write per leaf | **High** — the CG backend needs a parallel coverage bitmap, and byte-for-byte parity is this subsystem's whole gate | Cheaper at runtime, much more surface to get wrong |
| **C. Two accumulators** | Keep `front` (paper in) and `frontInk` (paper out) throughout; every leaf composites into both | 2× accumulator memory and 2× leaf composites, paid only when the tree contains an ink effect (a `RenderTree` property, exactly like `needsCompositorOnCanvas`) | Medium | Simplest to reason about, worst at 4K |
| **D. Do nothing, accept the regression** | — | none | none | **Refused by the owner's ruling.** Recorded so it is not silently re-adopted |

**Option A is the recommendation** because this project's binding constraint is not runtime, it is that
`CompositorParityLogicTests` gates the two backends byte-for-byte. A adds no new state to either
backend; B and C add state that both must maintain identically. A's cost is also bounded in practice —
a document has 0 or 1 ink effects, not 10.

## §4 — What the effect declares

Whichever option in §3 is taken, an effect gains one property: **what its input is.**

- `.backdrop` — everything below, paper included.
- `.ink` — everything below, paper excluded.

**For eleven effects this is a fixed property. For two it is a control the artist can see**, ruled by
the owner 2026-08-27:

| Effect | Input | Fixed or chosen |
|---|---|---|
| Levels, Curves, Brightness/Contrast, HSV Shift, Gradient Map, Posterize, Noise, Chromatic Aberration, Blur | `.backdrop` | fixed |
| **Sharpen** | `.backdrop` | fixed — **this table named twelve of thirteen and left it out**, and the build answered it by reasoning about the formula. Confirmed against the kernel instead: `sharpenCombine` (`Composite.metal:684-693`, CPU twin `EffectKernels.swift:455-471`) works on the full premultiplied vector, has no unpremultiply step and **no `alpha > 0` short-circuit**, and clamps `rgb <= a` at the end. Over flat paper `blur == base` exactly, so the difference term is exactly zero and the effect is the identity. At an ink/paper edge it sharpens the real ink-against-paper contrast, where before it sharpened ink against implicit transparent black — a visible improvement, and the only thing an artist sees change |
| Outline | `.ink` | fixed — over an opaque canvas there is no silhouette to trace, so `.backdrop` is not a mode, it is a no-op |
| **Bloom** | `.ink` **by default** | **artist's choice.** *"Lets make bloom have an option for both, with default being ink only."* Physically a bloom over a lit white sheet should blow out; practically every canvas is white, so ink-only is the useful default and paper-inclusive is the one you reach for deliberately |
| **Sobel** | `.backdrop` | **fixed — and it was the artist's choice for a few hours on 2026-08-27.** *"Same with sobel, defaulting this time to taking in the canvas color"* got the default right and the control wrong; the owner deleted the control the same day (*"drop it"*), and §5.2 keeps both rulings. So Sobel's shipped look still changes — bright edges on black, which is what an edge detector conventionally is — but there is no other setting. **Bright-edges-on-black also needs the alpha rule**: see §2.2, whose original claim that it came for free was false and shipped as a transparent canvas. With one mode left that rule is unconditional and needs no parameter |

**Sobel's look is a deliberate change to what ships**, not a preservation of it — the owner chose the
conventional edge-detector look over the current one. Say so in the commit message and in the release
note; an artist with a Sobel layer in an open document will see it change, and has **no setting to get
the old look back**. **It changed twice**: once when the paper entered the composite, and again on
2026-08-27 when §2.2's false claim was corrected and Sobel started producing the black the ruling had
asked for.

The property must be an **exhaustive switch over the effect case with no `default:`**, for the reason
CLAUDE.md records three times over in `CanvasManager`'s history: a hand-maintained list of exceptions
rots, and a fourteenth effect added later must be forced to answer the question rather than inherit a
default that happens to be wrong for it. `Effect.reshapesCoverage` (`Effect.swift:126-129`) is the
existing property of this shape and the new one should sit beside it. Where the answer is the artist's,
the stored value lives in that effect's own parameter struct (`Bloom`) and is **persisted**, so it is a
document change and needs a decode default for files written before it existed. **`Sobel` briefly had
such a field and no longer does**, which needs the mirror-image guarantee: a document written while it
existed must decode with the retired key *ignored* rather than throwing (§5.2, §6 step 5).

**One knock-on cost, and it is smaller than this section first said.** Bloom gains one control in the
effect settings bar; Sobel briefly gained one and lost it again, so **Sobel is still the zero-control
degenerate case** the bar has to handle and the per-effect control counts item (18) is sizing against are
unchanged for it. And one more `.ink`-input node exists in the wild than §3 assumed when it argued the
re-walk's cost is bounded; the argument still holds, since the count is per *document* and a document has
one or two effect layers, not ten.

**Chromatic aberration's centre-alpha rule stays untouched.** `Composite.metal:562-565` documents it
deliberately — "the shape of the artwork is the green channel's alpha and the fringe appears in colour,
never in coverage" — and with an opaque backdrop the coverage is 1 everywhere and the rule is moot. The
owner's report is fixed without editing that kernel, and editing it as well would be a second,
undiscussed behaviour change.

**`blendOver` stays untouched too.** `Composite.metal:236-250`'s `mix(cs, B(cb,cs), da)` is W3C
Compositing Level 1 and is correct for a genuinely transparent backdrop; the twenty affected blend modes
are fixed by *giving them a backdrop*, not by editing the formula. Eleven of them are gated
byte-for-byte against `CGBlendMode`, so an edit there breaks `CompositorParityLogicTests` by
construction.

## §5 — Answered, 2026-08-27

All four questions this section asked are ruled. Kept as answers rather than deleted, because two of
them overruled the recommendation and the reasoning is the part worth not rebuilding.

1. **Bloom — an option for both, defaulting to ink only.** *"Lets make bloom have an option for both,
   with default being ink only."* The recommendation was a fixed `.ink`; the owner made it a setting. The
   default is the recommendation, so the shipped look does not change.
2. **Sobel — the canvas colour, and no option. SUPERSEDED THE SAME DAY, and both halves are kept
   because the second only makes sense against the first.**

   **The original ruling, 2026-08-27**: *"Same with sobel, defaulting this time to taking in the canvas
   color."* That **overruled** the recommendation, which was to preserve today's edges-over-paper. It
   got the default right and the control wrong, and it was made on §2.2's false claim that
   bright-edges-on-black came for free from an opaque backdrop.

   **The superseding ruling, the same day, after the control had shipped and been measured**: *"drop it.
   Remember to cleanly remove and delete the feature so no remnants of it are left in the code."* The
   `.ink` setting is deleted; Sobel always takes the backdrop and there is no control. **What changed
   between the two rulings is evidence, not taste** — see §2.2: `(m,m,m,m)` over white paper composites
   to 255 for every m, so an ink-only Sobel is arithmetically invisible on the default paper whatever
   colour the ink is; and the kernel reads *premultiplied* rgb, so black ink is `(0,0,0)` on both sides
   of every stroke edge and an ink-only Sobel finds **zero** edges in black line art. The opt-out was a
   blank canvas for the two commonest documents there are.

   Sobel's look still changes for existing documents and still wants announcing — there is simply no
   setting that undoes it. **Do not re-propose the control**: it existed, it was measured, and it was
   near-useless in practice.
3. **The project thumbnail gets the paper. Decided here, at the owner's direction** — *"not sure what
   this is, you decide."* What it is: the small preview tile of each project in the project list.
   `ProjectStore.swift:284` composites it with `includeBackground: false`, so the tile has a transparent
   background where the artwork has none, and its own code comment already calls that "a real defect".
   **Decision: flip it**, because it is the same one-flag change as the fix, because the comment already
   says it is wrong, and because a tile that does not look like the artwork is the one thing a gallery
   tile has to do. **The cost, and it is why it was worth asking**: every existing tile keeps its old
   look until that project is next saved, so the gallery reads as mixed for a while. Not worth an eager
   regeneration pass — that is the operation Canvas Padding measured at 17% of a resize, and it would be
   paid per project for a cosmetic catch-up.
4. **The onion skin goes over the composite.** *"Onion skin goes over compositing so user can see it
   clearly."* See §2.1 — this **overrules** the recommendation of "over the paper, under the artwork" in
   the useful direction, and it is what removes the compositor change this document previously required.

## §6 — Staging

Nothing here should land as one commit.

1. **The Behind onion skin moves up in z-order** — from below both sandwich views to between them
   (§2.1). A `CanvasView` change, no compositor and no `RenderRequest` involvement. Visible only for a
   document with layers below the active one and Behind placement selected, so it ships and is looked at
   on the device on its own before anything depends on it.
2. **`Effect.input` lands as an exhaustive property with no behaviour attached**, plus the per-effect
   table from §4 as a test. Pure addition.
3. **`full` and `below` carry the background; `above` stays nil.** This is the fix. `paperView` must
   stop painting inside the artwork rect or a translucent canvas colour is applied twice — and note
   `canvasSize` includes `canvasPadding` (`CanvasManager.swift:20-27`) while both compositors fill
   across the whole bounds and `paperView` is inset (`CanvasView.swift:544-551`), so the padding margin
   needs deciding rather than inheriting. The key that decides whether to recomposite must gain
   `canvasBackgroundColor` and `isCanvasBackgroundVisible`, or a paper-colour change will not invalidate
   the cached composite — `CanvasView.SandwichKey` carries both, and `FrameBakeKey` carries the resolved
   background from the other side of the seam.
4. **Option A's re-walk for `.ink` effects**, which is what makes Outline work and what makes Bloom's
   ink setting mean anything. (It was Sobel's too until the owner deleted that setting — §5.2.)
5. **Bloom's control**, its persisted field and its decode default (§4). Sobel's fixed `.backdrop` is a
   change to shipped appearance and wants its own commit message saying so. **Sobel's control was built
   here and then deleted** — §5.2 — so this step is Bloom's alone; what survives of Sobel's half is the
   alpha rule §2.2 describes, which is unconditional and carries no parameter. A document written while
   Sobel's control existed holds `{"kind":"sobel","params":{"input":"ink"}}` and must still decode, with
   the key ignored: `testASobelSavedWithTheDeletedInputKeyStillDecodes`.
6. **The thumbnail flag** (§5.3).

**Expect to chase backend parity at step 3.** `MetalCompositor.swift:599-605` premultiplies in float and
dispatches `compositeFill`; `Compositor.swift:675-677` goes through `UIColor.setFill` + `UIRectFill`. Two
paths to the same colour that can land on opposite sides of an 8-bit rounding boundary, and parity is
this subsystem's gate.

**The test that is the owner's report in one line**, and it belongs in `EffectLayerLogicTests` beside
`testAnEffectLayerGradesItsBackdropToMatchTheHandComputedGrade` (`:117`): a brightness/contrast
adjustment layer over an **empty** canvas region changes those pixels. It fails today. Add the
`BlendMode.allCases` sweep too — one test covers all twenty modes by construction rather than twenty
tests covering them by enumeration.

## §7 — What the build got wrong, found by review before merge (2026-08-27)

Stages 1-4 are built on `tmp/effectbackdrop` (`e71e2a3`, `f1abe03`, `a0e611c`, `fe2743f`) and
**MUST NOT MERGE AS THEY STAND**. The mechanism is right and `testAnAdjustmentLayerGradesTheEmptyCanvas`
goes from `[0,0,0,0]` to `[128,128,128,255]` — the owner's report, byte for byte — but three
independent reviewers found four defects, all measured rather than argued.

1. **`PerfBaselineTests` is RED, in a file the branch never opened.** `RenderTree`'s texture estimate
   **doubled, 5 to 10**, for a bloom document, because Bloom's ruled default is `.ink` and the re-walk
   counts a second pair. That number is what the budget is divided by — `ChunkedCompositor.chunkSources`
   and `StripedCompositor`'s strip height both spend it, and `MetalCompositor.attempt` admits against it
   — so doubling it **halves the chunk width and the strip height on a memory-constrained device**, and
   on the mid-stroke halves, which are composited whole, it can tip the frame onto the CPU reference.
   The failing test is the owner's own crash scene, 4096² with vector + bloom + blur on the iPad 9
   budget. The estimate must count the re-walk's peak, not its sum.
2. **An `.ink` effect composites the ink a second time, and it is not subtle.** The re-walk builds the
   sub-tree on transparency and draws it over an accumulator that already holds the same sub-tree over
   paper; `blendOver` with `da == 0` returns the source unblended, so the ink is source-over'd onto
   itself. MEASURED: a 60%-alpha black square reads **[102,102,102]** normally and **[41,41,41]** with an
   Outline layer above it. **Adding an Outline layer, changing nothing else, darkens the layer by 40%.**
   Bloom is worse, because `.ink` is its shipped default. The fix is to composite the *difference* the
   grade made, or to re-walk into the accumulator rather than over it.
3. **Backend parity breaks on a fractional `canvasPadding`, and the slider produces one.**
   `ActionsMenu` passes a continuous `Double` straight through (the `px` readout rounds for display
   only), and `canvasBackground` rounds the **inset** but not the resulting **rect** — so Metal
   truncates 64.8 to 64 while CoreGraphics antialiases the last column. MEASURED: **max channel delta
   204** at one pixel. It also makes the paper asymmetric on screen, because `updatePaper` insets by the
   *unrounded* value. **Neither existing parity test catches it**: both use integer padding, so the only
   case the change altered is the only case nothing covers. Fix in one place — return an integral rect,
   not merely an integral inset.
4. **The onion skin at rest** — §2.1 above. **Ruled 2026-08-27, on the third pass and against a
   rendered comparison: option (a).** The z-order commit already on the branch is correct and is all
   there is. `.behind` reading as `.inFront` at rest, in a document the compositor engages for, is
   accepted behaviour. The at-rest split was built, measured, shown to the owner and reverted; §2.1
   carries the measurement so it is not rebuilt. See §2.1 for the gate.

**Two smaller things worth carrying**, both from the build agent rather than the reviewers, and both
now settled. `Effect.reshapesCoverage` is **not** exhaustive (it has a `default:`), so this document
was wrong to call it the model to copy — though a read of all thirteen kernels found no live defect
hiding behind that default, only the rot risk. **Sharpen was missing from §4's table and is now in
it**, confirmed against the kernel rather than inherited from the formula. And nothing downstream
switches on `Input` — all four consumers test `== .ink`, so a third case would compile clean and
silently take the backdrop path; the exhaustive switch protected the declaration and nothing that acts
on it. All four consumers are switches now.

## §8 — What the re-review found, and what it corrected in §7 (2026-08-27)

The four defects went back out to five analysts before a line was rewritten. Three of §7's four
survived intact; **two of its explanations did not**, and one of its two proposed fixes is wrong.

1. **§7 defect 2's "composite the *difference* the grade made" is REFUTED.** In premultiplied space
   the difference term is only correct where `graded == ink` — i.e. exactly the pixels that were
   already fine — and it destroys every pixel the effect *adds*. On a ring pixel the paper is
   `(255,255,255,255)`, the ink is `(0,0,0,0)` and the outline colour is opaque, so `acc + diff`
   clamps straight back to the paper and **Outline's ring disappears entirely**. Only §7's second
   candidate survives: clear the accumulator back to the background fill, draw the graded ink on it,
   and crossfade against the ungraded accumulator by opacity × mask — which is the backdrop path's
   own `mix`, reused verbatim rather than reimplemented.
2. **The 40% figure is right and understated.** Hand-traced through both backends: the ink's effective
   coverage goes 0.60 to `1 − (1 − 0.6)² = 0.84`, so the composited luminance falls *to* 40.2% of its
   former value — a ~60% darkening. The measured `[102,102,102]` → `[41,41,41]` is reproduced exactly
   by arithmetic (`102 × 0.4 = 40.8`), which is what makes it a defect rather than a fixture artefact.
3. **§7 defect 3's account of `renderSize` was incomplete, and the incompleteness is the whole fix.**
   `setCanvasPadding` folds the continuous slider value into `canvasSize` *itself*, so a fractional
   padding is a fractional **canvas**, and `RenderResolution.full` is the one case that does not round
   it away. Rounding the inset therefore *cannot* make the rect integral — the rect has to be derived
   from the whole-pixel buffer both backends actually allocate.
4. **§7 defect 3 blamed `updatePaper` for the on-screen asymmetry, and that is wrong.** `updatePaper`
   is exactly symmetric; the asymmetry is Metal's, from truncating an extent rather than clamping two
   edges. What `updatePaper` really causes is a *jump* — the paper's edge moves by up to half a pixel
   the moment an adjustment layer engages the sandwich, because the view and the composite round
   differently.
5. **The branch's own commit message contains a false claim about failure direction.** It argues an
   under-estimated texture count "makes the pool decline mid-walk and drops the whole frame onto the
   CPU reference". `ScratchTexturePool.acquire()` allocates on demand with no budget check, so no such
   decline exists: the real failure mode of an under-estimate is the iPad 9 jetsam crash this whole
   subsystem was built to prevent. The direction of safety is the same; the mechanism claimed is not
   real, and a false mechanism is worse than none because it invites tuning.
6. **A third inherent consequence, belonging beside §2.1 and §2.2.** A non-normal blend mode *below* an
   ink-input effect loses its blend against the paper: `blendOver`'s `mix(cs, B(cb,cs), da)` sees
   `da == 1` in the main walk and `da == 0` in the ink sub-walk, so an opaque red `difference` layer
   reads cyan alone and red under an Outline layer. Under replace-semantics that is the *definition* —
   those pixels are part of what the adjustment layer replaces — and it is a property of §3's option A
   however the result is recombined. Option C is the only formulation that preserves it, and §3 priced
   and rejected it. Pinned by a characterization test rather than left to be rediscovered.
8. **The eyedropper stopped picking a colour in the padding margin, and that is now ruled correct.**
   A consequence of the margin-is-not-paper decision rather than of any fix: `eyedropperRequest` passes
   `includeBackground: true`, `RenderBackground.rect` leaves the margin transparent, and
   `Eyedropper.color` has `guard a > 0`. So a tap that used to return the canvas colour now returns
   nothing. **RULED 2026-08-27: nothing to pick is correct.** The margin does not export, does not
   thumbnail and is not part of the picture — it is an on-screen affordance — so there is genuinely
   nothing there to sample and the eyedropper saying so is honest. This **overrides the argument in
   `eyedropperRequest`'s own doc comment**, which reasons the other way about unpainted white canvas;
   that comment is about the artwork rect, where it is still right, and it must say so rather than
   appear to have been forgotten. Nothing tests this in either direction.

7. **One load-bearing invariant is unpinned.** The ink path is correct only because an isolated folder
   holding an effect leaf always buffers, which is what stops `split(atLeaf:)`'s half-group — it copies
   opacity, mask, blend mode and effect verbatim — from applying a folder's fade twice. That rests on a
   single clause, `$0.effect != nil` inside `enclosesABlend`. Remove it as an optimisation and a faded
   folder's opacity is applied twice with nothing failing.
