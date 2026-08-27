# Effect backdrop — what an adjustment layer grades

The specification for [BUGS.md](BUGS.md)'s *"Every effect and blend mode is masked to the layer's own
ink"*, opened 2026-08-27 off the owner's device report and their ruling on it. **§5 is the part that
needs an answer; everything before it is analysis and is settled by reading.**

## §0 — What is already true, verified rather than assumed

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

## §2 — The two consequences are inherent, not incidental

Both were found by review before any code was written. Neither is a tuning problem, and it is worth
being precise about *why*, because the instinct is to treat them as bugs in the fix.

### 2.1 Once an effect grades the paper, the composite is opaque from that node up

This is not a choice. If an artist brightens the canvas, the result **is** opaque — there is no longer
a transparent region to see through, because the thing that was transparent has been graded into a
colour. Any design that produces the correct picture produces an opaque one.

**That hides the "Behind" onion skin.** `onionSkin` is added to the container at `CanvasView.swift:49-50`,
*before* `sandwichBelow` (`:57-58`) and `sandwichAbove` (`:59-60`); the comment at `:54-56` states the
invariant outright — the disengaged z-order is `onionSkin < below < above < chrome` — and
`updateOnionSkin` routes the `.behind` placement to exactly that lower view (`:2311-2315`). The Behind
ghost is visible today **only because the composited images have always been transparent where the
artist has not painted**, which is the same transparency that is the bug. Once paper and artwork are one
image there is no z-position left that is above the paper and below the artwork.

**Therefore the Behind onion skin must move into the composite**, between the paper and the layer stack.
The frames are already CGImages (`OnionSkinFrame.composite(frames, size:)`, `CanvasView.swift:2378`);
they have simply never been part of a `RenderRequest`. This is plumbing, not a new concept — but it is
not optional, and it is the half most likely to be discovered on the device instead of designed.

### 2.2 Once the paper is in the accumulator, alpha stops meaning coverage

Outline, Sobel and Bloom do not read colour, they read **shape**:

- **Outline** keys on `src.a > threshold` (`Composite.metal:696-698`, default 0.5 at `Effect.swift:364`).
  With an opaque backdrop that is true for every pixel and Outline is a **complete no-op**.
- **Sobel** convolves and emits `(0,0,0,0)` in flat regions (`Composite.metal:655-670`), which is why the
  paper currently shows through white. With an opaque backdrop flat regions become opaque black.
- **Bloom** thresholds luminance (default 0.75, `Effect.swift:314`) and white paper is Lum 1.0
  (`Composite.metal:626-637`), so the entire canvas becomes a bright source.

The alpha channel of the accumulator *was* the ink coverage, and filling paper into it destroys that
information. **Rescuing these three means preserving the coverage somewhere.** The three shaders
themselves need no change under any option below — what changes is which image they are handed.

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

Whichever option is taken, an effect gains one property: **what its input is.**

- `.backdrop` — everything below, paper included. Levels, Curves, Brightness/Contrast, HSV Shift,
  Gradient Map, Posterize, Noise, Chromatic Aberration, Blur.
- `.ink` — everything below, paper excluded. Outline, Sobel, Bloom.

It must be an **exhaustive switch over the effect case with no `default:`**, for the reason CLAUDE.md
records three times over in `CanvasManager`'s history: a hand-maintained list of exceptions rots, and a
fourteenth effect added later must be forced to answer the question rather than inherit a default that
happens to be wrong for it. `Effect.reshapesCoverage` (`Effect.swift:126-129`) is the existing property
of this shape and the new one should sit beside it.

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

## §5 — What the owner has to answer

1. **Bloom over paper — is `.ink` actually what you want?** Bloom is the one of the three where the
   paper-inclusive answer is arguably *right*: a bloom over a lit white sheet blowing out is what bloom
   does. Putting it in `.ink` means it glows from your ink only, which is almost certainly what an
   animator wants but is not what the effect physically models. **Recommendation: `.ink`**, because the
   alternative makes the effect useless on a white canvas, which is every canvas.
2. **Sobel's background — black or paper?** Under `.ink` it keeps today's behaviour: edges over
   unchanged paper. Under `.backdrop` it becomes bright edges on black, which is what an edge detector
   conventionally looks like. **Recommendation: `.ink`**, to preserve what ships today.
3. **Should the project thumbnail get the paper too?** `ProjectStore.swift:284` passes
   `includeBackground: false` and its own comment already calls the transparent-backed tile "a real
   defect". Same one-flag change, same ruling — but flipping it changes **every existing gallery
   thumbnail** until each project is re-saved, so the gallery will look mixed for a while.
   **Recommendation: yes, and say so in the release note rather than letting it be noticed.**
4. **Does the Behind onion skin belong under the paper or over it?** §2.1 forces it into the composite;
   it does not decide where. Over the paper (the ghost sits on the sheet, and an effect grading the
   backdrop grades the ghost too) or under it (the ghost is invisible on an opaque sheet, which is
   useless). **Recommendation: over the paper, under the artwork** — and note this means a
   Brightness/Contrast layer now dims your onion skin, which is arguably correct and definitely new.

## §6 — Staging

Nothing here should land as one commit.

1. **The onion skin moves into the composite**, with `background` still nil. No visible change, and it
   is the change §2.1 says is not optional. Ships and is looked at on the device on its own.
2. **`Effect.input` lands as an exhaustive property with no behaviour attached**, plus the per-effect
   table as a test. Pure addition.
3. **`full` and `below` carry the background; `above` stays nil.** This is the fix. `paperView` must
   stop painting inside the artwork rect or a translucent canvas colour is applied twice — and note
   `canvasSize` includes `canvasPadding` (`CanvasManager.swift:20-27`) while both compositors fill
   across the whole bounds and `paperView` is inset (`CanvasView.swift:544-551`), so the padding margin
   needs deciding rather than inheriting. `SandwichFullKey` (`RenderRequest.swift:385-398`) must gain
   `canvasBackgroundColor` and `isCanvasBackgroundVisible`, or a paper-colour change will not invalidate
   the cached composite.
4. **Option A's re-walk for `.ink` effects.**
5. **The thumbnail flag**, if §5.3 is yes.

**Expect to chase backend parity at step 3.** `MetalCompositor.swift:599-605` premultiplies in float and
dispatches `compositeFill`; `Compositor.swift:675-677` goes through `UIColor.setFill` + `UIRectFill`. Two
paths to the same colour that can land on opposite sides of an 8-bit rounding boundary, and parity is
this subsystem's gate.

**The test that is the owner's report in one line**, and it belongs in `EffectLayerLogicTests` beside
`testAnEffectLayerGradesItsBackdropToMatchTheHandComputedGrade` (`:117`): a brightness/contrast
adjustment layer over an **empty** canvas region changes those pixels. It fails today. Add the
`BlendMode.allCases` sweep too — one test covers all twenty modes by construction rather than twenty
tests covering them by enumeration.
