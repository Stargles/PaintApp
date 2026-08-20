# Add Text

Text is placed on the canvas as a live, editable object. On a raster layer it bakes into pixels the moment you do anything else to the canvas, exactly like the fill tool and smart shapes. On a vector layer it stays a real element in the display list and can be re-opened, retyped, restyled and re-warped forever. It can be moved, rotated and distorted by dragging its four corners independently, which is a true projective (perspective) warp, not an affine one.

The owner's ask is recorded verbatim at [TODO.md](TODO.md) — delete that entry when Stage 5 merges, not when a branch exists.

---

## 1. The decisions

### The object stores a recipe, never a result

`TextRecipe` is what the text *is* — string, font reference, typography, colour, opacity. `TextFrame` is where it sits — a local layout box `size`, the four canvas-space points its corners map to, and a `mode`. `VectorTextElement` is the two of them plus an `id` and a `motionGroupID`.

Nothing derived is stored: not glyph positions, not measured bounds, not a warped bitmap, not the 3×3 matrix. The homography is a computed property over `(size, corners)`. That single rule is what makes the perspective survive a re-edit — retype the string, change the font, change the size, and the glyphs re-lay-out into the same box and land in the same perspective, because the warp was never baked into anything. It is the same derived-recipe discipline [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md) already uses.

Storing `size` and `corners` separately is not "two transforms." They are the domain and the codomain of one map. Collapsing them into a bare quad forces an invented rule for what happens to the quad when the text grows — and "the quad grows along its top and bottom edges" is not a well-defined operation on a projected quad, since the whole point of perspective is that those edges are not parallel and do not scale alike.

Fields are grouped into defaulted sub-structs from day one (`Typography`, and later `outline`/`shadow` as their own), which is the generalizable lesson [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) extracts from `dynamics`/`grain`/`taper`: every flat scalar is a Codable-compatibility question later.

`TextFrame.mode` is an enum (`.affine`, `.projective`) from the first commit even though only two cases exist, so a later `.mesh(Lattice)` — Photoshop's Warp Text, which a homography cannot express — is an additive case rather than a Codable migration. Nothing in this project builds it.

### Point text grows; a box you sized wraps

`TextFrame.autoSize` is a stored bit, not an inference. While true (a fresh box nobody has resized), `size` tracks the measured layout and `corners` are re-derived by projecting the new box's corners through the existing homography — adding a character extends the text to the right *in perspective*, which is correct. The first handle drag sets it false; from then on `size` is authoritative, text wraps and clips into it, and `corners` never move on a re-edit. This is Illustrator's point-text-becomes-area-text moment, and it feels broken if it is left implicit. A pristine box draws a dashed outline; a sized box a solid one.

### The overlay is the editor; the model is the owner

A live text session draws through its own `CALayer` above the canvas — a `UITextView` for the caret, a glyph bitmap sized to the *text box*, never the canvas. Every mutation during a session lands in a draft copy on `CanvasManager`, mirroring the smart-shape scalars at `CanvasManager.swift:1719-1744`.

But a text object that has already been committed to a vector layer stays in `VectorCanvas._elements` for the whole session. It is suppressed from the flatten by a single transient `VectorCanvas.editingElementID`, which `renderLocalContent` skips. It is *not* lifted out of the array. Lifting it makes the persisted source of truth momentarily not contain an object the user already committed — and on this device [Compositor.swift](PaintSoftware/Engine/Compositor.swift)'s own header documents that jetsam kills the process rather than `makeTexture` failing gracefully, so that window is a data-loss window. Lifting also removes the object from thumbnails, the layer panel and other cels mid-edit, and buys nothing: the setters at `VectorLayer.swift:246-275` splice without invalidating and callers follow with `bumpVersion()`, so a lift costs a version bump exactly like the flag does.

Exactly two `invalidate()` calls per session: one when the session opens, one when it commits.

### Persistence: one new case, no sidecar, no version number

`VectorCanvasData.ElementData` (`Engine/VectorLayer.swift:1352`) gains a fourth case with kind string `"text"`, following the explicit-discriminator design that file's own comment says exists for this. Text rides inside the existing per-cel `<celID>_vector.json`.

`VectorTextElement` is the first vector element whose runtime and persisted forms are the same type — it holds no runtime resource, so it needs none of the `ImageRef` / `<project>/images/` machinery that `.image` forces on `ProjectStore`.

There is no `formatVersion` in this project and this feature does not add one. Compatibility is per-field `decodeIfPresent` with defaults, which means `TextRecipe` and `TextRecipe.Typography` carry **hand-written `init(from:)` from the first commit**, for the reason `VectorStroke` already does (`VectorLayer.swift:29-31`): synthesized `Decodable` ignores property defaults and throws on a missing key.

**The backward-compatibility hazard, which is worse than it looks. It has since been fixed — see Stage 2 — and this section is kept because the reasoning is why the fix has to stay.** `ProjectStore.swift` decoded the vector file through `try?`:

```swift
if let vectorFileName = celManifest.vectorFileName,
   let data = try? Data(contentsOf: ...),
   let payload = try? JSONDecoder().decode(VectorCanvasData.self, from: data) {
```

An older build meeting a `"text"` discriminator does **not** throw and lose the text — it swallows the error and degrades the whole cel to `.empty(size:)`, discarding every stroke, fill and image on that cel. Save from that build and the loss is permanent. Decoding elements one at a time and skipping only the unrecognised ones is the fix, and it is already in place; a `"text"` discriminator will therefore cost an older build the text element alone.

### The bake trigger is one line

```swift
func beginCanvasEdit() {          // CanvasManager.swift:556-562
    guard canvasEditDepth == 0 else { return }
    canvasEditDepth += 1
    defer { canvasEditDepth -= 1 }
    commitInteractiveFill()
    commitInteractiveShape()
    commitInteractiveText()       // ← the whole raster-bake wiring
}
```

Last in the list, because the text overlay draws above the shape overlay and committing last preserves what the user was looking at.

Every existing caller inherits the bake with no per-tool retrofit: brush and eraser touch-down through `CanvasView.Coordinator.commitTransientsAndRefresh` (`CanvasView.swift:1482`, from `onStrokeBegan` at `Views/Canvas/StrokeCanvasView.swift:59` — one wiring covers both, since `host.strokeView` is the same view for pen/pencil/eraser), fill start, shape start, image insert, the structure/interpolation undo brackets, `copyCel`, all five `SelectionModels` entry points, layer and frame switches, and — through `commitAllInteractiveState()` — save and app backgrounding.

Three places cannot simply alias to it:

**Undo/redo.** `finalizePendingGesturesForHistoryAction()` (`CanvasManager.swift:1819`) needs its own three-way branch. A handle under the finger is discarded. Lifted-but-adjustable commits, so the following undo has a real step to revert. And the case fill and shape do not have: **keyboard focused with no finger down resigns first responder and then commits** — undo mid-typing must not strand a floating editor over a baked bitmap, and must not silently throw away what was typed. Within a session, `UITextView` provides its own undo, so undo while the caret is live routes there first.

**The settings and colour panels must not bake.** `TopToolbar.toggle(_:)` (`:79-85`) calls `commitAllInteractiveState()`; `toggleSettingsPanel(_:)` (`:94-96`) deliberately does not, and its comment states why — committing a fill on the way into its panel "turns every slider in the panel into a no-op." The text panel routes through `toggleSettingsPanel(.text)`, and **while a text session is live, `.color` must too**, or picking a colour for your text bakes the text you were about to recolour. One conditional, extending a rule already written down.

**Landing the pixels** is `registerUndoableCelChange(...)` (`SelectionModels.swift:447`), not `stampShapeIntoRaster`. Render the glyphs, warp into the destination bbox, `PixelOps.compositeOver` against the cel's raster, and hand it over — which wraps it via `bakedRasterTexture(image:likeExisting:)` into `Cel.raster` and never `bakedImage` (the ghost-layer bug documented at `:440-446`), applies by resolved layer/cel **ID**, and registers one atomic undo step. That primitive is already tool-agnostic across Fill, Shape, Move, Duplicate and both selection operations.

Vector commit is an upsert into `_elements` at the same index (preserving z-order), plus `registerVectorTextUndo` — a copy of `registerVectorFillUndo` (`CanvasManager+Fill.swift:350`): whole-array before/after swap, `bumpVersion()`, `celContentChangedOutsideStroke`. Coarse-grained whole-array swap is what every other element kind already does; no new undo machinery. One undo step per session, named "Add Text" or "Edit Text" — not one per keystroke, which would flood `UndoHistory` with entries whose `cost` accounting was never sized for it.

`setVectorTransform` (`CanvasManager.swift:260-269`) is explicitly **not** the pattern to copy: it contains no `recordUndo` call and its caller has no begin/end bracket. A text move/rotate/distort drag registers exactly one step on lift. (That existing gap is worth its own [BUGS.md](BUGS.md) line; it is adjacent to this work, not part of it.)

### The distort is a real homography, and the maths is twenty lines

Four corner correspondences determine an 8-DOF projective map. Do not build a general DLT solver — for the unit square there is a closed form (Heckbert). Normalise the box to the unit square with `S = diag(1/w, 1/h, 1)`, then for unit corners `(0,0),(1,0),(1,1),(0,1)` mapping to `(x₀,y₀)…(x₃,y₃)`:

```
sx = x₀-x₁+x₂-x₃ ;  sy = y₀-y₁+y₂-y₃
if sx == 0 && sy == 0:                      // parallelogram → affine, g = h = 0
    a = x₁-x₀ ; b = x₂-x₁ ; c = x₀
    d = y₁-y₀ ; e = y₂-y₁ ; f = y₀
else:
    dx₁ = x₁-x₂ ; dx₂ = x₃-x₂ ; dy₁ = y₁-y₂ ; dy₂ = y₃-y₂
    den = dx₁·dy₂ - dx₂·dy₁                 // ~0 ⇒ three corners collinear, reject
    g = (sx·dy₂ - sy·dx₂)/den ;  h = (dx₁·sy - dy₁·sx)/den
    a = x₁-x₀+g·x₁ ; b = x₃-x₀+h·x₃ ; c = x₀
    d = y₁-y₀+g·y₁ ; e = y₃-y₀+h·y₃ ; f = y₀
```

`H = [a b c; d e f; g h 1] · S`. Inverse is the 3×3 adjugate. `affine()` returns a `CGAffineTransform` when `|g|` and `|h|` are below an extent-scaled epsilon — true for every move, rotate and uniform scale, which is the overwhelmingly common case and which draws glyphs natively with no bitmap and no resampling at all.

This is deliberately **not** `Lattice.bilinear` (`Engine/Deform/Lattice.swift:473`). Bilinear-in-(u,v) agrees with a homography at the four corners and along the four edges but has no perspective divide, so it bows interior content — and the interior is exactly where foreshortening lives. Right shape of primitive, wrong interpolation rule. `Lattice` is also points-only; there are zero `UIImage`/`CGImage`/texture references anywhere in `Engine/Deform`.

`Quad` and `Homography` live in `Engine/Deform/` beside `Lattice`, so the whole distort maths compiles standalone with `swiftc` in ~5 s instead of a 90 s `xcodebuild test`, and so a future interpolation feature can reach them.

**The validity predicate is projective, not affine.** `isValidQuad` requires: convex, non-self-intersecting, `den ≠ 0`, area above a floor, **and all four `w > 0`** — the last one rejects a corner dragged behind the vanishing line, which is the specific way a homography produces silent visual garbage rather than a crash. A drag that would fail it clamps to the last valid position. It never throws, so it needs headless tests, not eyeballing. Clamping is a UX cliff and the handle will feel like it sticks; rendering garbage or flipping through the horizon are both worse, and the big editors do the same thing.

### Live warp is Core Animation; the bake is a compute kernel

Live: the glyph bitmap sits in a `CALayer` whose `transform` is a `CATransform3D` built from `H`. Core Animation uses the **row-vector** convention (`p' = p·M`), so the embedding is the transpose of the naive one — this is the gotcha:

```swift
t.m11 = a ; t.m21 = b ; t.m41 = c
t.m12 = d ; t.m22 = e ; t.m42 = f
t.m14 = g ; t.m24 = h ; t.m44 = 1
```

with `bounds = CGRect(origin: .zero, size: frame.size)`, `anchorPoint = .zero`, `position = .zero` (the matrix carries translation), and `allowsEdgeAntialiasing = true` — without it a warped edge aliases hard. `contentsScale` comes from the largest per-corner destination scale of `H`, capped at 3× **and** at a 4096×4096-texel backing store.

The render server does the perspective divide and the resampling off the app thread. **A 60 Hz corner drag writes sixteen floats and rasterizes nothing.**

Bake: a `warpHomography` compute kernel in `Composite.metal`, the same function shape as the existing `sampleBilinear()`/`texelClamped()` helpers (`:543,551`) — per destination pixel, inverse `H` with the `1/w` divide, discard where `w ≤ 0`, sample. This codebase has zero `MTLRenderPipelineState` (compute-only, 29 `MTLComputePipelineState` hits, zero `drawPrimitives`), so a compute kernel doing its own divide is the only thing that fits, and it fits cleanly. A scalar Swift reference implementation of the same loop backs the `CoreGraphicsCompositor` path and export.

The Swift and MSL warps must be tested **against each other**, not each against itself. A green warp test proves its two operands are equal, not that they are the two rasterizers you think.

### Handles live outside the warped layer

Under a perspective warp the four corners sit at four *different* effective scales. Handles inside the warped layer render at four different sizes. So the handles are a sibling `TextTransformOverlayView` pinned to `CanvasView`'s `container`, drawing at `H(corner)`.

Every handle dimension is `screenPoints / canvasScale`, with `canvasScale` pushed from the coordinator on each transform change — 14 pt dot, 44 pt hit target, 1 pt outline, constant at any zoom. A handle is chrome: it belongs to the screen, not to the artwork. Do **not** copy `TransformHandleView`'s fixed `24×24` (`TransformOverlaySupport.swift:39-51`); it lives inside the same transformed `container` and carries the unfixed shrink-with-zoom bug that produced "faint blue line, does not have nodes in it."

Three more disciplines inherited from `ShapeOverlayView`: one `handleLayout(for:)` that both rebuild and reposition read, so they cannot drift; nearest-within-reach hit-testing rather than first-match, because on a small text box the corner targets overlap; and raw `touchesBegan/Moved/Ended` rather than a pan recognizer, so a drag bites on the first pixel instead of after ~10 pt of slop. The opposite corner and the whole starting quad are **latched at touch-down**, so a mid-drag pinch-zoom cannot move the reference frame under the gesture.

### Typing in a distorted box happens unwarped

iOS caret, selection handles and the loupe render badly under a `CATransform3D` with a perspective component. While `mode == .affine` you edit in place under the affine transform. While `mode == .projective`, entering text edit temporarily shows the **unwarped** box for typing with the warped result ghosted behind, restoring the warp on dismiss. Illustrator's envelope-distort "edit contents" makes the same compromise. It is a visible concession and it is the honest one.

### Fonts go through one seam and nothing else

```swift
protocol FontProvider {
    var id: String { get }                                              // "system", "google-noto"
    func groups() -> [FontFamilyGroup]
    func faces(inFamily: String) -> [FontFace]
    func uiFont(_ d: FontDescriptor, size: CGFloat) -> UIFont?          // nil = not mine
}
```

`FontLibrary` holds a composed `[FontProvider]`, structurally `BrushLibrary` (`Engine/BrushLibrary.swift:6-49`) — built-in defaults plus a user directory at `Documents/Fonts/<packID>/`, mirroring `customBrushesDirectory`. `SystemFontProvider` is the only implementation shipped; it wraps `UIFont.familyNames`/`fontNames(forFamilyName:)`, with San Francisco surfaced as a distinguished "System" entry rather than buried alphabetically.

**No call site outside `SystemFontProvider` may touch `UIFont.familyNames`.** That one greppable rule is the entire seam. Adding a pack later is "append a provider," not a call-site change.

`FontDescriptor` stores `(familyName, faceName?, packID?)` — qualified by pack, so two packs shipping "Inter" cannot collide and a missing font is diagnosable rather than mysterious. `FontLibrary.resolve` walks exact face → any face in the family matching the descriptor's traits → system, and reports whether it substituted. The panel shows the substitution and a missing pack raises a `CanvasNotice` banner; the stored descriptor is never rewritten, so reinstalling the pack restores the intended face. Nothing short of embedding the font makes the document round-trip, and this design does not pretend otherwise. Same class of problem `Brush.customTextureFileName` already has.

Picker UI follows the house idiom for many named options: a grouped native `Menu` with `Section`s and a checkmark on the current value, the `blendModeRow` / `BlendMode.menuGroups` pattern (`LayerPanel.swift:590-`), sectioned System / Serif / Sans / Mono / Display / *pack name*, each row drawn in its own face as the preview. Alignment is a segmented `Picker` (`EraserSettingsPanel.vectorModePicker:42`). Sliders are `StrokeSettingsPanel.sliderRow`.

Licensing is a per-pack checklist, not a one-time task. OFL 1.1 requires the notice ship with the font, forbids selling the font standalone, and forbids a modified copy keeping the Reserved Font Name. That means a `LICENSE` per pack directory and a Legal/About screen — **which does not exist in this app** and is a real prerequisite for shipping any pack, not a footnote.

### The vector eraser does not bite text

An erase stroke above a text element in the display list already masks it at render time (`VectorLayer.swift:665` — the eraser is a stroke composited `.destinationOut` and appended last), so mode 1 works for free by z-order. The split and punch modes operate on `VectorStroke` sample geometry and **skip text elements**; a glyph run is not splittable the way a polyline is. To carve text, delete the object or convert it to outlines (deferred, Stage 6). This is a decision, not a bug report.

### `ActionsMenu` gains the ability to enter a mode

It is constructed with only `canvasManager` (`DrawingView.swift:289`) and has no `activePanel` binding; every row today is a direct action, a `PhotosPicker`, or an inert stub. Threading the binding through and adding `Tool.text` + `ActivePanel.text` is a real, small change to a file every panel shares — it lands first and alone.

---

## 2. Why the rejected alternatives were rejected

**Text as a `ShapeKind`, committing through `commitInteractiveShape`.** The commit flattens `ShapeGeometry` into a `VectorStroke` — its own comment says what lands "is a real brush stroke, not a separate shape object" — which is precisely the property the owner forbids for vector text. `ShapeGeometry` is also 5 DOF against the distort's 8, and deliberately CoreGraphics-only so it compiles headlessly; glyph layout is CoreText. Over half the type's surface (`pointOnOutline`, `outlineParameter`, `collapsedShapeSamples`, `draggingEdge`) would be dead for the text case.

**Reusing `VectorImageElement`** — render text to a `UIImage` and stash the recipe beside it. Three failures: it drags in the `images/` sidecar and `ImageRef` machinery for content that is otherwise pure JSON; it caches the *result*, so a font change or a pack install leaves a stale bitmap unless every edit rewrites a PNG to disk; and its `LayerTransform` is affine-only, so a quad type gets built anyway, bolted beside a field that now lies.

**Quad-as-the-entire-transform, with no separate layout box.** Argued as avoiding "two transform representations," but `size` and `corners` are the domain and codomain of one map, not two maps. Collapsing them forces an invented growth rule for retyping under distort, and "the quad grows along its top and bottom edges" is undefined on a projected quad whose top and bottom edges are not parallel.

**CPU inverse-homography resample as the live path**, with the GPU kernel deferred until a measurement demands it. This is the [BUGS.md](BUGS.md) 53.8 ms trap in a new costume: a re-warp per input event, with a supersample factor capped only "to bound memory." A 3000×600 quad at 3× is a 9000×1800 intermediate — 64 MiB, the same number BUGS.md cites for the per-dab allocation at 4096². "The destination is the quad's bbox, never the canvas" is not a bound; a title across a 4096 canvas has a bbox approaching canvas size.

**Core Image's `CIPerspectiveTransform`.** It does this warp in one line, and there is zero Core Image in the tree today. Adopting it means a `CIContext` with its own Metal device, command queue, kernel cache and intermediate pool — unbudgeted, invisible to `CompositorBudget.hasHeadroom`, in a process sized against 192 MiB on a 3 GB device where jetsam rather than `makeTexture` is the failure mode. The kernel is ~40 lines reusing helpers that already exist in `Composite.metal`. Core Image would win if a filter *chain* were needed; it is not.

**`Lattice` / bilinear quad interpolation.** No perspective divide, so interior straight lines bow — visible exactly on the strongly-skewed quad the feature exists for. It is also points-only; nothing in `Engine/Deform` touches an image.

**Lifting the committed element out of `_elements` during an edit.** Sold as making `VectorCanvas.version` immovable, but `VectorLayer.swift:246-275` says the setters splice without invalidating and callers follow with `bumpVersion()`, so the lift costs a bump anyway. What it does buy is a window where the persisted array does not contain an object the user already committed, on the one device documented to be killed by jetsam rather than fail gracefully, plus the object vanishing from thumbnails and other cels mid-edit. A transient `editingElementID` gets the identical cache-freeze with none of that.

**Undo-per-keystroke.** `UndoHistory`'s `cost` accounting was never sized for 200 entries from one sentence. `UITextView` supplies within-session undo for free.

**A `formatVersion` field.** There is none anywhere in this project; compatibility is per-field defaults, and adding one for this feature alone would be a second, inconsistent mechanism.

**Claiming one shared `Homography` value makes the live preview and the bake identical.** The projective *map* is shared; the sampler, gamma handling and premultiplication are not, and Core Animation's filtering is unspecified and OS-version-dependent. This is a real divergence and it is recorded as an open risk in §4, not argued away.

---

## 3. Staged delivery

Each stage merges to `main` on its own and is usable on the owner's iPad. Follow the multi-session protocol in [CLAUDE.md](CLAUDE.md): one worktree per stage, and a new *test* file needs a hand-written `project.pbxproj` entry with an id derived from the file name — plus the duplicate-id check after any rebase touching that file.

**Stage 1 — "Add Text" exists, on raster layers, and it bakes. ~~To build~~ — done and on `main` (2026-08-20).**
`TextObject.swift` (`TextRecipe`, `FontDescriptor`, `Typography`, `TextFrame` with `.affine` only, `VectorTextElement`), plus `Engine/TextLayout.swift`, `Engine/FontLibrary.swift`, `Models/CanvasManager+Text.swift`, `Views/TextOverlayView.swift`, and `TextSettingsPanel` filled in. `Tool.text`, `ActivePanel.text` and the `ActionsMenu` row landed first and alone, ahead of the rest. `commitInteractiveText()` is in `beginCanvasEdit()`; the three-way branch is in `finalizePendingGesturesForHistoryAction()`; the bake goes through `registerUndoableCelChange`.
Three things shipped differently from the sketch this entry used to carry, and each is written up where it lives:

- **The overlay's `UITextView` draws no glyphs.** It supplies the caret, the selection, the keyboard and Scribble; the pixels are `TextLayout.renderBox`, *the same drawing code the bake calls*. Sharing the rasterizer rather than only the transform is what makes the live preview and the commit agree — §2's closing warning, taken seriously a stage early.
- **The font `Menu`'s rows are not drawn in their own faces.** A SwiftUI `Menu` is presented by UIKit, which discards a custom `.font` on a button label. A live per-face preview needs a custom picker sheet; that is more UI than this stage should spend.
- **`autoSize` stops growing at the canvas's right edge and wraps instead.** A point-text box is supposed to grow rightward forever, but with no handles until Stage 4 there is no way to drag a runaway one back. `TextLayout.autoSize` carries the note; the cap can go once handles exist.

**Still not done here:** ~~vector layers (the row is disabled with a note)~~ — stage 3 — rotate, scale, distort, font packs.
**Tests:** 75, across `TextLayoutLogicTests`, `TextRecipeCodableLogicTests`, `FontResolveLogicTests` and `TextBakeCharacterizationTests`. The layout tests assert *identities* rather than measured widths — tracking adds exactly `t × (characters − 1)`, each spacing knob moves one baseline gap by exactly its own delta, the alignments place a line at `0` / `box − width` / `(box − width)/2`, a justified line that is not the last fills the box — because "this string is 412.5 points wide" is a claim about a font file Apple revises, not about this code.
**Still owed, and it needs the owner's iPad.** Keyboard-over-canvas was never exercised: first-responder handoff across panel toggles, `keyboardLayoutGuide` against a canvas with its own pan/zoom, a box off-screen or at 0.3× scale, and whether iOS's own Scribble recognizer fights the canvas's. None of it is reachable headlessly, and **`ActionRecorder` is how to get it off the device** rather than guessing at a simulator.

**Stage 2 — the per-element decode fix. ~~To build~~ — already on `main`, do not build it (verified 2026-08-18).**
It landed ahead of this plan, as the fix for the `try?` in `ProjectStore` that discarded a whole vector cel on one unreadable field. `VectorCanvasData` decodes its display list one element at a time through `LossySlot`, an unknown `kind` and a malformed known `kind` are told apart at the discriminator and logged at different severities, and the counts land in a `DecodeReport` (`Engine/VectorLayer.swift:1351-1436`). `VectorCanvasDataLogicTests` pins it with 13 tests, on counts and identities rather than "did not throw".
The stage number is kept rather than renumbered so every reference to Stages 3-6 elsewhere in this document still means what it says.

**Stage 3 — vector layers keep it editable. ~~To build~~ — done and on `main` (2026-08-20).**
`.text` on `VectorElement` (+ `id` arm, `text` accessor), `Kind.text` / `kind(of:)`, the `texts` accessor, the `renderLocalContent` arm and `Self.draw(text:into:quality:)`, the `contentBounds(of:)` arm via a measure-only `TextMeasure.inkBounds`, `topmostText(atCanvasPoint:)` (box hit through `H⁻¹`, not glyph hit). `.text` on `ElementData`, discriminator `"text"`. `editingElementID` suppression, `registerVectorTextUndo`, `isTextEditLive` in `makeSandwichKey`. The row is enabled on vector layers — deleting `Tool.textUnavailableReason`'s `.vector` arm was the whole of the UI change, exactly the un-shipping stage 1 planned for.
Four things are worth knowing that the sketch above does not say:

- **`Kind.text` is numbered *below* `.stroke`, and a new object is `append`ed rather than inserted.** The rawValue governs insertion arithmetic, not z-order: keeping `.stroke` highest is what makes a brush stroke drawn after an erase still land at the end of the list, above the `.erase` punch `eraseHybrid` appends. Number text above strokes instead and that stroke is inserted *underneath* a punch that predates it. Text and strokes therefore stack chronologically, and §1's "an erase stroke above a text element already masks it" holds unchanged.
- **The whole `elements` array is what undo swaps**, not the `texts` bucket. The kind-filtered setters gather their kind back at the first one's index, which is order-stable for a contiguous bucket and not for text, which is interleaved with strokes by construction.
- **`TextMeasure` lives in `Engine/TextLayout.swift`** rather than a file of its own — same subject, one fewer `project.pbxproj` entry to collide over — and `TextLayout.draw` went from `private` to internal so the vector flatten reaches the *same* rasterizer the bake and the overlay use. That is stage 1's report taken at its word: there is one rasterizer, and adding a second for the vector path is the divergence §2 warns about.
- **`isTextEditLive` latches forward, not backward.** `isSandwichStrokeLive` holds the *previous* pass's content version because a dab publishes nothing; opening a text edit does the opposite — it sets `editingElementID`, which invalidates — so the first key after the session opens is computed fresh and then held. Freezing against the previous pass would leave the committed glyphs composited under the live editor and the artist would see their text twice.

**Explicitly not yet:** rotate, scale, distort. Two known limits fall out of that and are stated where they live: a frame that is not an upright translation draws through its bounding box (`VectorCanvas.draw(text:…)`) and reports its bounding box as ink (`TextMeasure.inkBounds`), which stage 5's homography is what fixes; and a text object is passed through `InterpolationEvaluator` unwarped, since warping a `TextFrame`'s corners is that same projective work.
**Tests:** 34 new, across `VectorTextPersistenceLogicTests` (element → JSON → element round-trip on a *rotated* quad so a repair cannot pass for a decode, z-order preserved across an upsert at index, and the long round trip — canvas → JSON → canvas → *edited* — which is the only one that proves the reloaded thing is the object and not a picture of it), `TextHitTestLogicTests` (a point inside a rotated box hits, one in the corner outside it misses, with a fixture check asserting that corner really is inside the AABB so the test fails loudly if the quad test is ever swapped for a rectangle one), and a rewritten block in `TextBakeCharacterizationTests` where `testTextIsRefusedOnAVectorLayerForNow` used to be. Three existing tests changed because stage 3 moved the boundary they pinned, and one of them is worth naming: `VectorCanvasDataLogicTests`' fictional "unknown kind" *was* `"text"`, so it had to become `"video"` — a sentinel has to be a kind nothing implements.

**Stage 4 — rotate, scale, and handles that are the right size.**
`TextTransformOverlayView`: handles in a non-warped sibling view at the projected corners, `screenPoints / canvasScale`, anchor latched at touch-down, nearest-within-reach hit-testing, raw touch handling. `.affine` gains rotation and independent-axis scale. One `recordUndo` per drag.
**Explicitly not yet:** the four corners moving independently.
**Tests:** `TextTransformLogicTests` — anchor-preserving resize on a rotated box (the opposite corner does not move in canvas space), rotation about the box centre, one undo step per drag. Not headless: that a handle actually looks 14 pt at 0.3× zoom on the device.

**Stage 5 — the projective distort.**
`Engine/Deform/Quad.swift` and `Homography.swift` (Heckbert closed form, adjugate inverse, `affine()`, `isValidQuad`, `catransform3D`). Four independent corner handles with clamping. Live warp via `CATransform3D` with the capped `contentsScale` and backing store. Bake via the `warpHomography` kernel in `Composite.metal` plus the scalar Swift reference. The unwarp-while-typing rule for `.projective`. **A Release build on the iPad 9 before merge.**
**Explicitly not yet:** mesh/envelope warps, outline conversion, WYSIWYG convergence between the CA preview and the kernel bake.
**Tests:** `HomographyLogicTests` compiles with `swiftc` in ~5 s — forward∘inverse ≈ I to 1e-9, `affine()` non-nil for a parallelogram and nil for a trapezoid, three-collinear-corners → nil, a corner past the vanishing line rejected by `w > 0`, clamping holds the last valid quad. `WarpAgreementCharacterizationTests` asserts the scalar Swift warp and the MSL kernel agree within tolerance across a fixed set of quads. A matrix-construction test asserts the nine `CATransform3D` elements rather than comparing pixels. Not headless: whether the CA preview and the kernel bake *look* the same on a strongly foreshortened quad — that is an eyes-on-device judgement.

**Stage 6 — deferred polish, independent small branches.** Font packs (`PackFontProvider`, `CTFontManagerRegisterFontsForURL`, `Documents/Fonts/<pack>/`, per-pack `LICENSE`, the Legal/About screen). "Convert to Outlines," which also gives the eraser something to bite. Promoting `motionGroupID` off `VectorStroke` onto a `VectorElement` accessor so fills and images can be tagged too — the wart [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md) items 11/41 already record. Converting `FloatingPiece`'s `.distort`, which today runs the uniform-scale path and whose own doc comment admits it, onto this solver. WYSIWYG convergence, if Stage 5's device check shows it is visible.

That font packs can be deferred indefinitely without blocking Stages 1-5 is the proof the seam in §1 worked.

---

## 4. Performance rules

The measured trap ([BUGS.md](BUGS.md), `StrokeCanvasView.swift:275-284`) has three ingredients: a **canvas-sized** allocation, **per input event**, plus two canvas-sized `draw(in:)` calls. At 4096² that is 53.8 ms/dab against 4.0 ms for raster — a 19 fps ceiling — and halving `renderResolution` changes it not at all, because the cost is upstream of the sandwich entirely. This feature must break all three ingredients, and does:

1. **Nothing in the live path is canvas-sized.** The overlay's backing store is the text box (a 1000×400 box is ~1.6 MiB, forty times smaller than a 4096² buffer), capped absolutely at 4096×4096 texels even fully supersampled.
2. **Nothing in the live path allocates per frame.** The glyph bitmap is re-rendered only when the *recipe* changes, and move/rotate/distort assign `layer.transform` only. **A 60 Hz corner drag rasterizes nothing** — a strictly better position than even the 4.0 ms raster dab.
3. **Re-layout is coalesced to the display link**, not run synchronously in `textViewDidChange`, so a fast typist gets at most one CoreText pass per frame. CoreText into a 1000×400 bitmap is well under a millisecond on an A13.
4. **Two `VectorCanvas.invalidate()` calls per session, at open and at commit.** Never during. Every bump cascades into `RasterizeKey` (`PixelOps.swift:104-106`), `LayerContentVersion` (`RenderRequest.swift:167-169`), `SandwichKey`, and both upload caches, each costing a fresh canvas-sized flatten and an LRU eviction.
5. **`isTextEditLive` joins `isSandwichStrokeLive` in `makeSandwichKey`** (`CanvasView.swift:1084-1086`), freezing the active layer's content version for the session — belt and braces over rule 4, and it also stops an unrelated bump (a timeline tick) triggering the 276 ms snapshot `RenderRequest.swift:374-376` records as the expensive half of a composite.
6. **Budget against 192 MiB on the iPad 9** — `CompositorBudget.textureBudgetBytes` is `physicalMemory / 16` and `PixelOps.RasterizeCache` deliberately borrows the same number, so the ceiling is shared and holds only 3-12 canvas-sized entries. Text mints **zero** cache entries per edit. Minting one per keystroke would thrash to a 0% hit rate — "a cliff, not a slope" — degrading every *other* layer's flatten, and an over-budget composite is declined *silently* with a `purgeLocked()` that drops the entire upload cache process-wide, felt as random full-canvas stutter unrelated to the text.
7. **One canvas-sized cost, once, at bake** — one supersampled glyph raster, one warp over the destination bbox, one `compositeOver`, one `registerUndoableCelChange`. Identical in shape and cost to a fill commit, which is already accepted.
8. **The one per-frame GPU cost to watch** is the render server resampling the warped layer's whole backing store each frame. It is off the app thread and tens of microseconds at text-box size on an A13, but it scales with the box — which is what the `contentsScale` and backing-store caps exist for.
9. **Measure in Release on the device.** Debug measured 62× slower on the alpha-mask path and the simulator misreports GPU cost by more than 10×. Worse for this feature specifically: `CompositorBudget.hasHeadroom` returns true whenever `os_proc_available_memory()` is 0, which is the simulator — **the memory valve never closes there**, so every memory-pressure consequence of this feature is structurally invisible off-device. Any stage touching the warp path needs a Release device run *before* merge.

**The known open risk.** Live is Core Animation warping a CA-managed bitmap at screen scale; bake is our kernel at canvas scale. The projective map is shared, the sampling, gamma and premultiplication are not, and CA's filtering is unspecified and OS-version-dependent. WYSIWYG will diverge, worst on exactly the strongly foreshortened quad the feature exists for. Stage 5's characterization test measures it and the device check judges whether it is visible; the fix, if needed, is driving the preview through the same kernel into a `CAMetalLayer` off a `CADisplayLink`, which is ~1 ms/frame at text-box size but adds a second Metal path and a display link to the most gesture-sensitive code in the app. Do not let "gated on it being visible" become "never looked."

---

## 5. Behaviour, decided

These were open behaviour questions. The owner answered all of them on 2026-08-17; they are settled and
should not be re-litigated.

1. **Undo while you are typing undoes the typing.** With the caret live, undo steps back through what
   was typed (the keyboard's own undo stack). Only once you tap away does undo remove the whole text
   object. The rejected alternative — undo always stepping through drawing history and dropping the
   text mid-type — is simpler but throws away typing corrections.

2. **Typing into distorted text happens flat.** Tap into perspective text and the box springs back to
   flat while you type, the perspective version ghosted behind, snapping back when you tap away. This
   is Illustrator's behaviour. Typing directly on the warped box was rejected: the caret and selection
   handles are wrong there, and no amount of care fixes that.

3. **Overflow clips.** A box you sized by dragging a handle is authoritative — text wraps inside it and
   anything past the bottom is hidden until you enlarge it. Shrink-to-fit was rejected because it
   silently makes the chosen size stop being the size you set. A box nobody has resized still grows to
   fit; that is `TextFrame.autoSize` in §1, and it is a different case.

4. **Text stays whole under the eraser.** The eraser hides text as it hides anything else, but the
   cut-into-it modes do not carve letterforms. To carve, delete the text, or convert to outlines once
   Stage 6 exists. Slicing letters directly was rejected because it forces an outline conversion on
   first cut, after which the text is no longer text.

5. **The font picker gets a favourites strip**, above the full grouped list, in the same shape as the
   brush presets. **Which faces belong in it is still open, and it is now the one thing Stage 1 left
   unanswered.** Stage 1 has reached the panel and shipped *without* a strip — all families grouped
   System / Serif / Sans / Mono / Display, with a second menu for the faces within the chosen family
   — because inventing a shortlist would have made it the answer by default. iOS ships roughly 60-80
   families; naming five or six turns the picker from a list into a set of defaults, so it wants the
   owner's own list rather than a guess at one.