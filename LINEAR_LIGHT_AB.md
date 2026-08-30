# Linear-light A/B — the picture for TODO item (10)

The owner's original complaint was *"RGB goes muddy through the middle between two saturated hues."*
TODO.md item (10) argues that is a gamma problem rather than an Oklab one, and asks for a rendered
A/B before anything is built. This is that A/B, plus what reading the real code changed about the
item's premises.

**Nothing here is a recommendation.** The pictures are in `docs/linear-light-ab/`; the generator is
[tools/linear_light_ab.swift](tools/linear_light_ab.swift), committed so this can be re-rendered
rather than re-derived.

---

## 0. What these images are, and what they are not

**INFERRED / SIMULATED.** These are **not screenshots of the app.** No Metal ran; no simulator ran.
The generator is a Swift port of `blendOver` (`PaintSoftware/Engine/Composite.metal:236-250`) and of
`blendChannels`' Normal / Multiply / Screen cases (`:189-234`), term for term, evaluated over
synthetic scenes in double precision and quantized once at the end.

What **is** real:

- **The antialiased coverage in scene 1 is CoreGraphics' own**, produced in a `CGContext` configured
  exactly as `PixelOps.rasterizeUncached` configures its own — `CGColorSpaceCreateDeviceRGB`,
  `premultipliedLast`, 8 bpc, antialiasing on. Those coverage bytes are the values the app would get.
- **The arithmetic is the shipped arithmetic**, including the unpremultiply → blend →
  re-premultiply that `blendOver` does and the `mix(cs, B(cb, cs), da)` interpolation.

What is **not** reproduced: the GPU's float32 rounding, CoreGraphics' per-operation 8-bit rounding on
the CPU backend, the mask/coverage kernels, and the effect stack. None of those change the size of
the effect being shown — they are ±1 phenomena and the numbers below are ×70.

---

## 1. The formulas actually in the tree

| what | where |
|---|---|
| source-over, Normal fast path | `Composite.metal:240` — `fma(dst, 1.0f - src.a, src)`, **premultiplied**, no colour management |
| the general blend wrapper | `Composite.metal:236-250` — unpremultiplies to float, blends, re-premultiplies |
| Multiply / Screen | `Composite.metal:70-71` — `cb * cs` and `cb + cs - cb*cs`, on **unpremultiplied** values |
| the "we do not linearize" ruling | `Composite.metal:6-12`, and it is explicit: every texture is `rgba8Unorm`, **not** `rgba8Unorm_srgb`, because the sRGB variants "linearize on read and re-encode on write" and would break the CPU-parity gate |
| texture format | `MetalCompositor.swift:173` (`.rgba8Unorm`) — **the item's line number is correct**; also `:1100`, with `:873` using `.r8Unorm` for mask coverage |
| CPU backend's blend | `Compositor.swift:1078-1084` — `image.draw(in:blendMode:alpha:)` for anything with a `CGBlendMode`, `drawHandRolled` otherwise |
| which modes go through CoreGraphics | `Compositor.swift:429-455` — ten do: normal, clipToBelow, multiply, screen, overlay, darken, lighten, hardLight, difference, exclusion |

**Where coverage enters — and this is the item's biggest error.** The item says "coverage
compositing is averaging light", which is true, but implies the averaging happens where the item
proposes to fix it. It mostly does not. There are three sites, and only one of them is
`Composite.metal`:

1. **Every brush dab.** `RasterLayerTexture.swift:66-88` paints a dab as a `CGGradient` built in
   `PixelOps.deviceRGBColorSpace` (`:102`) and drawn with `drawRadialGradient` into a persistent
   8-bit `premultipliedLast` DeviceRGB bitmap (`:281-283`). The dab's own alpha falloff, and every
   overlap of one dab on the next, is composited **by CoreGraphics, in sRGB, before the compositor
   exists**.
2. **A cel's four tiers.** `PixelOps.rasterizeUncached` (`:296-332`) stacks `bakedImage`,
   `strokesImage`, `vectorImage` and `fillImage` with plain `UIImage.draw(in:)` in a
   `UIGraphicsImageRenderer`. Also CoreGraphics, also unlinearized.
3. **Cross-layer compositing.** `Composite.metal`'s `blendOver`. This is the only one stage A touches.

**Consequence, and it should carry weight in the decision: linearizing the compositor would leave
scene 2 unchanged whenever both hues are on the same layer.** A soft blue dab laid over orange ink
the artist already put down on that layer is site 1, not site 3. That is the ordinary way a painter
works, and it would keep the dark ring.

**Second consequence, on the CPU/no-Metal path.** Ten modes — Normal among them — are computed by
CoreGraphics itself. There is no hook to insert a transfer function into
`image.draw(in:blendMode:alpha:)`. Linearizing forces all ten onto `drawHandRolled`, which
`Compositor.swift:1092-1097` documents as "slow on purpose... three canvas-sized allocations for one
draw, where a CG primitive is one blit." Stage A is not a shader edit; it is a shader edit plus the
deletion of the fast path on the reference backend.

**Third: "keeps `CompositorParityLogicTests`' byte-for-byte gate" is only half true.** That gate is
delta 0 **for source-over and for masks only** (`CompositorParityLogicTests.swift:906-942`). Blend
modes hold to `blendTolerance = 1` (`:968`), against a measured per-mode table at `:991-997` where
multiply, colorDodge, colorBurn, hardLight, vividLight, hue, color and luminosity already sit at 1.

---

## 2. Did the symptom reproduce?

**Yes — but not in the case the item leads with.** The three scenes are the same arithmetic at three
different pixel widths, and they are not equally convincing.

| scene | how wide the transition is | visible at | verdict |
|---|---|---|---|
| **1. hard antialiased edge** | 1–2 px | **~9x** | **weak.** At 1:1 it is a hairline. `05`'s difference map for this scene is a one-pixel outline on black — that is the honest picture of it. Nobody would call this "muddy". |
| **2. soft brush dab** | ~200 px | **1:1, unmistakable** | **strong.** The A half carries a dark desaturated ring around the dab that is not in the artwork. It is the artefact, and it is large. |
| **3. hue ramp** | full width | **1:1, unmistakable** | **strongest, and closest to the owner's words.** Every A band darkens and greys through its middle; the B band does not. |

Scenes 2 and 3 are the same phenomenon as scene 1 spread over enough pixels to see. Source-over at
coverage `t` of A onto opaque B is exactly `lerp(B, A, t)`, so the gradient case and the coverage
case are one formula — which is why "muddy through the middle" and "muddy antialiased edges" are the
same defect, and why the item was right to connect them even though it picked the least visible
example to argue from.

---

## 3. Worst case, MEASURED

**73 of 255 on one channel.** Exhaustive over all 256 × 256 × 256 (backdrop, source, coverage) 8-bit
triples for Normal, since source-over on one channel is a lerp: worst at **backdrop 0, source 252,
coverage 0.227** — today 57, linear 130.

Per scene (`docs/linear-light-ab/measurements.txt`):

```
scene 1  blue on orange   73      red on green    68
scene 2  blue dab/orange  73      red dab/green   67
scene 3  orange->blue     73 at coverage 0.20     green->red 66 at 0.19
scene 5  Multiply  interior  4, edge 73
         Screen    interior 22, edge 73
```

**The Multiply/Screen split is worth reading, because it refutes the guess I started with.** I
expected linearizing to move filled interiors under a product-shaped blend. It barely does: 4/255 for
Multiply on this pair (both operands land near black either way) and 22/255 for Screen. The large
numbers stay at partial coverage. **Even for a blend mode, this is an edge-and-gradient effect, not a
fills effect** — which also means the change would be least disruptive exactly where an artist has
laid down flat colour.

---

## 4. What it does to existing artwork — scene 4 is the evidence

`04-grey-control.png` is the control, and the owner should look at it before the pretty ones.

**(a)** A 1-px black/white checker is genuinely half the light of white. It sits beside flat sRGB 128
(what the app produces today for a half-covered pixel) and flat sRGB 188 (what linear light would
produce). Whichever patch the checker matches from across the room is the physically correct one.
That is the entire case for linear light, stated without a hue in it.

**(b)** Black over white, by coverage — MEASURED:

```
coverage  0.1  0.2  0.3  0.4  0.5  0.6  0.7  0.8  0.9
today     230  204  179  153  128  102   77   51   25
linear    243  231  218  203  188  170  149  124   89
delta     +13  +27  +39  +50  +60  +68  +72  +73  +64
```

**Every antialiased grey in every existing document gets lighter, by up to 73/255.** Hairline
strokes, antialiased text, soft-edged shading and every feathered dab already on the owner's iPad
would read thinner and paler. Reopening a finished drawing changes it. This is not a migration that
can be versioned away cheaply, because the pixels were never stored as coverage — a baked raster tier
is finished bytes.

That is the trade in one sentence: **the change makes new work right and old work different.**

---

## 5. Does the 256-entry-LUT parity argument survive?

**Half of it does, and the half that does is the half the item states.**

- **sRGB → linear on the way in: survives, for every formula I read.** The input is an 8-bit value
  and the function is per-channel, so a 256-entry table is exact and bit-identical on both backends
  by construction. This holds even for the six non-separable modes — `lum` (`Composite.metal:145`),
  `sat`, `clipColor`, `setLum`, `setSat` do mix channels, but they mix channels that the per-channel
  table has *already* transformed. **No gated mode mixes channels before the input transfer.** The
  item's construction is sound.

- **linear → sRGB on the way out: not a 256-entry lookup, and the item does not mention it.**
  `blendOver`'s result is a continuous float in linear light. Encoding it to an 8-bit sRGB byte is
  either `pow(x, 1/2.4)` evaluated on both backends — Metal's `pow` and Swift's `pow` are not
  required to agree to the last ulp, which is precisely what the delta-0 Normal gate exists to catch
  — or a quantize-to-8-bits-linear-first table, which throws away the shadows (8-bit linear has 1/255
  steps where sRGB's encoding puts far finer steps near black) and bands visibly. **This is the real
  parity risk and it is on the output side.**

- **A semantic caveat the LUT does not cover.** `lum`'s coefficients (0.3, 0.59, 0.11) are the W3C
  spec's, defined on **non-linear** values. Applying them to linear values changes what Luminosity,
  Color, Hue, Saturation, Lighter Color and Darker Color *mean* — the numbers stay reproducible on
  both backends, but they stop being the formula CoreGraphics and Photoshop implement. Six modes,
  and it is a design decision rather than a rounding one.

---

## 6. The images

| file | what it settles |
|---|---|
| `docs/linear-light-ab/03-hue-ramp.png` | **Send this one first.** Four saturated pairs, TODAY above LINEAR, at 1:1. The owner's own phrase, rendered. |
| `docs/linear-light-ab/02-soft-brush-dab.png` | The case an artist actually paints. The dark ring in each A half is the artefact. |
| `docs/linear-light-ab/04-grey-control.png` | **The cost.** What linearizing does to every grey already drawn. |
| `docs/linear-light-ab/01-antialiased-edge.png` | The item's own example, at 1:1 and at 9x. Included because it is the weak one and the owner should see that. |
| `docs/linear-light-ab/05-difference-and-blend-modes.png` | Amplified difference maps (×3) and Multiply/Screen with interior-vs-edge measured separately. |
| `docs/linear-light-ab/measurements.txt` | Every number above, as printed by the generator. |

Re-render with:

```bash
swiftc -O tools/linear_light_ab.swift -o /tmp/llab && /tmp/llab docs/linear-light-ab
```

No simulator, no `xcodebuild`, ~20 s.
