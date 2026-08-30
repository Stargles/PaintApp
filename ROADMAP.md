# ROADMAP

**What comes after the current list.** [TODO.md](TODO.md) is the owner's asks *live*, capped at three
in flight. This file is the six things they say come next — given unprompted on 2026-08-28, and their
own reason for sending it now is so that architecture decided today is not decided blind. Nothing here
is scoped, ruled, or in flight, and nothing here belongs on TODO.md yet.

**How to read it.** Everything in a blockquote is **the owner's own words, verbatim** — TODO.md's rule
that a quote is cheaper to keep than a decision is to rebuild applies with more force here than
anywhere, because none of this has been designed. Everything outside a blockquote is **our reading of
the tree at `b42a67b`**: a reading, not a ruling, and marked INFERRED where it is a guess rather than a
citation. Where the code disagrees with the brief, that is said in place rather than smoothed over.

**Every item ends the same way, and that is a property of this document rather than a footnote to it:**

> "When you get to these, prompt me to explain to you in more detail how they work."

So each item closes with **Ask the owner first** and the questions we would open with. That line is the
item's entry condition. An item built from this file alone was built wrong.

**Keep it a map.** A page an item at most. The specification for any one of them is its own document
once its conversation has happened, the way LASSO_MOVE.md and CANVAS_RESIZE.md exist.

---

## 0. The plan, and the order

> "After you or a future session finishes the things on the list, here is the plan for the future.
> When you get to these, prompt me to explain to you in more detail how they work."

The owner's stated dependencies: **(2) requires (1)**, **(3) requires (2)**, **(6) requires (5)**.

**The code agrees with all three.** One it agrees with for a sharper reason than the brief gives, one
is narrower than it looks, and the code adds three dependencies the owner did not name.

- **(2) requires (1) — agreed, and here is the precise reason.** `InterpolationRecipe.t` is a parameter
  of the *cel*, not of the frame (`PaintSoftware/Models/InterpolationRecipe.swift:181-188`), and a cel
  occupies a whole range of frames — `startFrame`/`frameCount` (`PaintSoftware/Models/Cel.swift:5-6`).
  So **nothing in the document varies across the frames one cel spans.** A video is exactly content
  that must. Item (1) is what introduces per-frame variation inside a cel; item (2) is its first
  consumer.
- **(3) requires (2) — agreed, trivially.** A live screen is a video whose frames arrive from a socket
  instead of a file. Everything below the frame source is shared.
- **(6) requires (5) — agreed, but narrower than it reads.** Item (6) is really two features, and only
  one of them needs (5). Organising documents into scenes needs no renderer at all; *exporting the
  movie* does. See item (6).
- **Unnamed: (5) was blocked on a model-side gap in the interpolation feature. That one is fixed.** ✅
  `makeRenderRequest` did not include a derived in-between — the cel's own canvas is empty and its
  pixels came only from `interpolatedImage(forCel:)`, reached from the **view** layer — so **an export
  written then would silently have omitted every interpolated in-between**. The `ContentProvider` seam
  (VECTOR_INTERPOLATION item 18, `Models/CelContentProvider.swift`) closes it: `renderSources` resolves
  a provider per frame and hands each flatten its derived content, so the composite an exporter walks
  contains in-betweens. `CanvasView.swift:985-1012` lists the other two things no composite contains,
  and those are still open — read it before writing the exporter rather than assuming this closed all
  three.
- **Unnamed: (4) needs a real playback clock, and there is none.** Playback is a
  `Timer.scheduledTimer(withTimeInterval: 1.0/fps)` whose callback re-dispatches onto the main queue
  and calls `advancePlayback()` (`PaintSoftware/Views/AnimationTimeline.swift:976-989` — **re-checked
  2026-08-30; this file said `:729-734`, which is now the frame label**); `isPlaying` and
  `playbackTimer` live on the *view* (`:13-14`), not the model. That drifts, and today nothing notices because the only
  consumer is the playhead. Audio is a hardware clock, so drift becomes what the artist hears, and
  lipsync is where they see it. **INFERRED**: the first work in item (4) is moving playback onto the
  model behind a monotonic time base — a timeline change, not an audio feature.
- **Unnamed: (1)'s "bake to multiple cels" and (5)'s exporter are the same walk.** Both are "evaluate
  the document at frame N, N+1, … and emit one picture per frame"; one writes cels, the other writes
  video frames. **INFERRED**: build the frame-walker once. `makeRenderRequest` is **already
  frame-parametric** (`atFrame frame: Int`, `PaintSoftware/Engine/RenderRequest.swift:527`), which is
  the half of it that exists.

---

## 1. Keyframes

> **SPECIFIED 2026-08-28 — [KEYFRAMES.md](KEYFRAMES.md) supersedes this section.** The conversation this
> item's entry condition asks for has happened; nineteen rulings came out of it and they are in that
> file's §2. What is below is the pre-conversation reading of the tree and is kept only because its
> citations are still accurate. **Do not design from it.** Three of its findings were changed by the
> conversation: `SpacingCurve` is *not* the curve type to reuse (it is a clamped, monotone, end-pinned
> time remap and a value channel needs none of that); the per-sample-width problem the transform arm
> looked to need does not exist once the dab walk is baked in rest space; and text's perspective distort
> is a **bitmap resample**, so it is not evidence that crisp projective ink is close.

> "Keyframes: (objects within a cel can get keyframed and move for the duration of that cel). Also
> applies to stuff like sliders for effects. Also includes interpolation curve customization. You
> should also be able to bake the cel containing animation into multiple cels (frames), and also set
> frame rate. Transformation layers adds transformation animation to whatever is under it."

**This item has far more groundwork than it looks like, and two of its five clauses are nearly done.**

**Already there.**

- **Stable per-object identity — the load-bearing seam.** `VectorElement` is `Identifiable` with a
  persisted `UUID` per element (`PaintSoftware/Engine/VectorLayer.swift:277`, id switch `:287-294`);
  strokes, fills, placed images and text each carry their own, in one ordered display list. "This
  object" is addressable and survives a save.
- **Precedent for keying document state to an element id.** `VectorStroke.motionGroupID: UUID?`
  (`VectorLayer.swift:57-58`) is that shape, and its own doc states the rule to follow: a field, not a
  side table, so it survives copy/duplicate/split/undo automatically. The same stroke also carries
  `visibilityThreshold` / `sampleVisibilityThresholds` — an already-persisted per-object *time* channel
  that nothing writes yet (VECTOR_INTERPOLATION.md §4 item 34).
- **Interpolation curve customization already ships — this clause is mostly *done*.** `SpacingCurve`
  (`PaintSoftware/Models/InterpolationRecipe.swift:47-92`) is a persisted easing type —
  `linear / easeIn / easeOut / easeInOut / sampled`, where `.sampled` is an **arbitrary** curve read at
  evenly spaced inputs. It applies frame-wide (`InterpolationEvaluator.swift:142`), per motion group
  with a documented precedence (`:227-233`), and per guide (`CanvasManager+Interpolation.swift:1527`);
  the artist edits it on a draggable chart (`PaintSoftware/Engine/GuidePath.swift:344`), and a guide's
  stylus timing derives one for free (`GuidePath.swift:166`, rationale `GuideStroke.swift:65`).
  **It is not on [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)'s future-upgrade list because it is
  not future.** What is missing is that a curve can attach only to a recipe or a motion group — never
  to one object, and never to an effect parameter.
- **`fps` exists, is persisted, and is already what playback runs on.** `CanvasManager.fps: Int = 24`
  (`PaintSoftware/Models/CanvasManager.swift:630`), in the manifest (`ProjectManifest.swift:11`, encoded
  `:102`, decoded `:75`), saved and loaded (`ProjectStore.swift:226`, `:1259`), read by the playback
  timer (`AnimationTimeline.swift:729`) and *displayed* (`:531`). **The only writer in the entire app is
  the load path.** So "set frame rate" is a UI-plus-undo task on a field that already works end to end —
  far cheaper than the clause sounds. BUGS.md already carries it under "Missing / stubbed, as designed"
  (`BUGS.md:1195`).
- **A whole-document bake with one undo step exists as a template.** `bakePreciseStrokes`
  (`PaintSoftware/Models/CanvasManager+Document.swift:636`) commits interactive state first, walks
  **every layer and every cel**, *collects* edits rather than applying them, and registers **one**
  `recordUndo` over all of them — explicitly so a menu tap costs one press to undo rather than one per
  cel (`:685-687`). It is also written to be safe about `Cel.vector` being a class reference that a
  structure snapshot shares rather than copies (`:604-606`). That is the shape "bake an animated cel
  into multiple cels" wants. The single-cel precedent for turning derived content into stored content is
  `commitInterpolation(layerIndex:celIndex:)` (`CanvasManager+Interpolation.swift:814`); a *range* bake
  does not exist, and range interpolation sits on VECTOR_INTERPOLATION.md's explicitly-deferred list
  (`:350`) with the note that architecture must not preclude it.

**What has to change.**

- **Time itself.** The document's timing model is integer frames — cel `startFrame`/`frameCount`,
  `sceneFrameCount`, `currentFrame` — and `fps` converts frames to wall clock in exactly one place, the
  playback timer. Interpolation's `t` is a *normalised span parameter* connected to neither. Per-object
  keyframing needs a third notion, local time within a cel, and the natural chokepoint to resolve it is
  `activeCelIndex(inLayer:atFrame:)` (`CanvasManager+Timeline.swift:12-15`), which every drawing path
  already goes through.
- **Effect parameters have neither an address nor a per-frame home.** `Effect`
  (`PaintSoftware/Models/Effect.swift:62`) is an enum of thirteen cases, each carrying a distinct struct
  of named Swift fields of heterogeneous type — `Double`, `Int`, `Bool`, `UInt32`, `CodableColor`,
  arrays, enums (payloads `:218-473`). Every slider in `EffectSettingsBar`
  (`PaintSoftware/Views/EffectSection.swift:133`, rows switch `:210-392`) is hand-wired and rebuilds the
  whole enum case on write: **no `KeyPath` registry, no `subscript(parameter:)`, no descriptor list.**
  The flat `EffectParams` block (`Effect.swift:507`) is a one-way lowering for the kernels whose fields
  are *reused* across effects, so it cannot serve as the address space either. And `Layer.effect` is a
  single `Effect?` on the **layer**, not the cel (`Layer.swift:74`), so there is nowhere for a
  time-varying value to live. **INFERRED**: this clause needs a parameter-descriptor table generated
  beside the existing `rows` switch so the two cannot drift, plus a ruling on where an animated effect
  value is stored.
- **"Transformation layers" is already recorded as the intended future shape — in a file designed to
  forget.** The only record in the repository is one sentence in the Session 70 entry of
  `SESSION_LOG.md`: item (12) bakes objects into canvas coordinates rather than scaling the layer,
  *"with a **transformation layer** applying a transform to the layers below it at render time recorded
  as the future shape … and the seam stays open"*. **Session 70 is the oldest of the five entries the
  log keeps, so that line rolls off next.** [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) never mentions it
  and its §9 open questions do not either. Rescuing it here is one of the reasons this document exists.
- **LAYER_TRANSFORM.md's rule is the argument for hanging animation off objects rather than layers**
  (`:376-377`): *"A transform is an object property when its consumers compose with it. It is an
  indirection when its consumers invert it away."* Object transforms survived that verdict; the layer
  transform did not — no path writes a non-identity `VectorCanvas._transform` any more (`:17`). So a
  transformation *layer* should be designed as a **render-time composite input**, not a stored affine —
  consistent with that ruling rather than a reversal of it.

**Two traps to carry into the design.**

- `InterpolationPreviewKey` (`PaintSoftware/Views/CanvasView.swift:2115`) must carry every input the
  evaluation reads, or a new animatable input appears to do nothing until something unrelated forces a
  re-render. VECTOR_INTERPOLATION.md settled fact 11 (`:90-92`): *"It has bitten three times."*
- Derived content is invisible to `PixelOps.rasterize(cel:)`, which reads stored tiers only — so
  thumbnails, ordinary onion skin and (eventually) export see an animated cel as empty.
  VECTOR_INTERPOLATION.md item 18 (`:267-271`) names the fix, and it is a passed-in `ContentProvider`,
  **not** a back-reference from `Cel` to the manager. This is the same gap §0 flags as blocking (5).

**What this constrains on today's list.** Nothing blocking. It *cheapens* two things: TODO (10)'s
recommendation already routes Oklab into **interpolation** rather than storage
(TODO.md:196-204, stage B names "keyframe colour tweens" explicitly), which is this item's colour arm;
and a `SpacingCurve` graph editor would reuse `CurveEditor` (`EffectSection.swift:605`), which exists
for the Curves effect and has never been pointed at timing.

**Ask the owner first.** What is a keyframe attached to — one object, a selection, or a named group?
Does a keyframed object's motion survive the cel being duplicated or split? When a cel is baked to
frames, do the source cel and its animation remain, or is the bake destructive the way Commit is? And
does a transformation layer transform the *pixels* of the composite below it, or re-pose the *vector
objects* below it — those are different features wearing the same name.

---

## 2. Import videos

> "Import videos: (requires #1) like import images, but exist as videos. Since videos have a specified
> length, a vector layer containing a video can only have one video and must be a specific length (but
> add that length able to be cropped). Should have the same option to bake to multiple cels containing
> images instead of the video."

**Already there.**

- **The vector display list is already forward-compatible with a new element kind, and `"video"` is
  literally the name the codebase reserved.** `VectorCanvasData.ElementData`
  (`PaintSoftware/Engine/VectorLayer.swift:3235`) reads its `kind` discriminator in two steps — raw
  `String`, then lookup — precisely so a kind this build has no case for is reported as a benign version
  gap rather than a defect, costing that element only (`DecodeReport.unknownKinds`).
  `CanvasManager.addImageToActiveVectorLayer`'s own doc says it out loud: *"Shapes and video slot in
  here the same way in future"* (`CanvasManager.swift:254`).
- **`VectorImageElement` (`VectorLayer.swift:263`) is the sibling a video element sits beside** — four
  fields, with `image` runtime-only and persistence storing a file name plus the transform through
  `VectorCanvasData.ImageRef` (`VectorLayer.swift:3218`), PNG written per element by `ProjectStore`
  (`ProjectStore.swift:815-830`). Import is one path: `PhotosPicker`
  (`PaintSoftware/Views/ActionsMenu.swift:48`) → `insertImage` (`CanvasManager.swift:297`) →
  `VectorCanvas.addImage` (`VectorLayer.swift:862`).

**A tripwire, and it is a pleasant one.** Because `"video"` is unimplemented, it is currently the
**sentinel** for "a kind nothing implements" in the forward-compatibility tests —
`VectorCanvasDataLogicTests.swift:141`, asserted by name at `:203` and `:221`, and reused in
`SaveDamageGateLogicTests.swift:121` and `:220`. It used to be `"text"`, and ADD_TEXT.md stage 3 is what
forced the change. **Implementing video breaks those four fixtures by design, and the fix is to pick a
new sentinel, not to delete the assertions** — the tests' own comments say so
(`VectorCanvasDataLogicTests.swift:137-139`).

**What has to change.**

- **There is no asset store, and the save path is hostile to a large blob.** Binary content is flat
  files in `<project>.paintproj/images/` named by UUID, with no dedupe and no refcounting. Two
  consequences: `duplicateCel` (`CanvasManager+Timeline.swift:105`) copies the vector canvas and the
  next save writes a *fresh* file per new element id; and `writeCel` re-encodes unconditionally
  (`ProjectStore.swift:819`, with `pngsReused: 0` at `:843` saying reuse is not implemented) — 95.6% of
  a cel's 15.2 ms save is `pngData()` (`ProjectStore.swift:631`). **A video must not go through that
  path**; it needs copy-once-and-reference, which does not exist. Two further blind spots to inherit:
  `ProjectBackupManager.validateProject` checks **PNG magic bytes** (`:480`, `:494-503`) and gates the
  atomic swap on its verdict (`:471`), so a `.mov` sidecar needs a branch there or the save is silently
  trashed; and image refs live inside the vector JSON, invisible to the validator
  (`ProjectStore.swift:1171-1172`).
- **There is no AVFoundation anywhere.** No import, no linked framework, no commented-out experiment.
  Decode, seek and frame-timing are all greenfield.

**What this constrains on today's list — the actionable part.** **A video element inherits whatever
Move stage 3c decides**, because it will be placed, stretched and mirrored by the same box.
`VectorImageElement.transform` is a `LayerTransform` — `position`, **one** `scale`, `rotation`
(`PaintSoftware/Models/LayerTransform.swift:6-12`) — and the persisted `ImageRef` stores the same five
scalars, so there is nowhere for a flip or a second axis even in memory. The refusals are hard-coded and
asserting, not degrading: `canBeStretched`/`canBeMirrored` return `false` for `.image`
(`VectorLayer.swift:2322-2327`, `:2355-2360`) and both `mapping` arms call `assertionFailure`
(`:2245-2249`, `:2102`). TODO.md `:215-226` records this as the one half of the Freeform/Mirror gate
still closed. Meanwhile the *transient* pose type already has what is missing:
`ObjectTransformFrame.aspect` is documented as *"Freeform's independent axes, held as the one number
`LayerTransform` has no room for"* (`PaintSoftware/Models/ObjectTransformFrame.swift:102-104`, `:122`).

**INFERRED, offered for the owner to accept or reject:** if 3c's stored field is designed as a shared
placed-object pose — a quad like `TextFrame`'s, or a two-axis scale on a protocol every placed kind
adopts — then video and any future shape kind inherit it for free; if it is bolted onto the image case,
each new kind pays the migration again. 3c is not *blocked* on this, but the choice is much cheaper to
make before it than after. Note also that stage 3b phase 3 left 3c a tripwire — the re-fitting box
measures a placed image exactly *only because* Freeform is refused on a float holding one
(`CanvasManager+LassoMove.swift:117-129`) — and that refusal would have to cover video too until the
same work lands.

**Ask the owner first.** What does "must be a specific length" mean when the cel's `frameCount` and the
video's duration disagree — does the cel resize, does the video retime, or is it refused? Does cropping
the length trim the source or re-time it? Is one video per *layer* or per *cel*? And at what rate is a
30 fps source shown in a 24 fps document?

---

## 3. Screen recording the computer as a layer

> "screen recording computer as layer: (requires #2) This is the big feature. It should connect live
> with the computer and display the screen live as a video or image like object in a vector layer.
> Performance will be big here, so some kind of optimization where you can freeze it will be good, along
> with it not updating when nothing is changing on screen. The objective is to be able to have blender
> on my computer, use my mouse to pick an angle, then rotoscope it on the drawing app, move to another
> perspective, and so on. This means another program for the windows computers side. I also would like a
> feature where the computer can drop in an image or video file somewhere and it will appear on the app,
> so I can directly pull out renders from blender and mash it with my animations."

**The owner's two performance instincts are exactly right, and the render path already has the
machinery for both.** A layer is cached behind `LayerContentVersion`
(`PaintSoftware/Engine/RenderRequest.swift:151`), which carries identity *and* version for both tiers.
When it is unchanged, three caches short-circuit in sequence — the SwiftUI `SandwichKey`
(`CanvasView.swift:1403`) schedules no rebuild at all, `PixelOps.rasterizeCache`
(`PixelOps.swift:118`) skips the Core Graphics flatten, and `UploadCache`
(`MetalCompositor.swift:231`) skips the CPU→GPU upload. So **"don't update when nothing is changing" is
not a new mechanism — it is not bumping the version, and "freeze it" is pinning it.** There is even a
precedent for holding a version constant deliberately: the stroke path latches it mid-gesture so the
compositor stays off the drawing path (`CanvasView.swift:1448-1457`), and the text editor does the same
(`:1458-1460`). A live layer wants a third such latch.

**What has to change, and the cost when the version *does* move.** There is **no dirty-rect or partial
update anywhere on the composite path** — `MetalCompositor.swift:1103` blits
`MTLRegionMake2D(0, 0, width, height)`, always the whole surface, and every cache above it stores whole
images. So a changed frame costs a full canvas render, a full flatten and a full-surface upload, and
one repaint is **three** composites over a shared source array (`MetalCompositor.swift:1051-1054`).
A canvas texture is 16.8 MB at 2048² (`MetalCompositor.swift:212`), and upload is recorded as *"the
dominant cost of a GPU composite"* (`:1047-1048`). **INFERRED, arithmetic only:** a 30 fps mirror at
2048² is on the order of 500 MB/s of upload before any compositing. A live layer also permanently
occupies a canvas-sized slot in a fixed byte budget and evicts a static layer that would have hit —
`MetalCompositor.swift:220-227` warns that degradation there is *"a cliff and not a slope"*.
Separately, `LAYER_COMPOSITING.md` §9.1 point 3 asks for a pure snapshot-driven
`composite(RenderRequest) -> Texture` precisely because the composite currently runs on the main actor
to read live texture objects; a screen feed is a second writer from off the main actor, which is the
case that entry point was designed for.

**Correcting one of this task's own leads: the existing "Windows" infrastructure is unrelated, and it is
zero percent of this feature.** `deploy/mac/` is a remote-build/test pipeline —
`cleanup_session.sh`, `fast_test.sh`, `parallel_test.sh`, `screenshot.sh`, `status.sh`, plus
`screenshot_fetch.ps1`, the only Windows file in the repo: a PowerShell script that SSHes to the Mac
over Tailscale, runs `simctl` and copies **a simulator screenshot** back. One-shot, seconds of latency,
and pointing the opposite direction from what this feature needs. **The app has no networking at all** —
no `URLSession`, no `Network`, no Bonjour, no Multipeer, no entitlements file, no local-network usage
description. Transport, discovery, permissions and the Windows binary are all greenfield. The only real
head start is soft: Tailscale is installed and the two machines are already on one tailnet.

**And the drag-and-drop half starts from nothing, with a testing constraint attached.** The app has
**zero** drop, drag, `Transferable`, `NSItemProvider`, `fileImporter` or `UTType` code; the only import
is a `PhotosPicker`. Worse, this repo has already ruled on the API: layer reordering is a hand-rolled
long-press *because* `UIDragInteraction` *"can't be driven by XCUITest at all (verified — a synthetic
press-and-drag never lifts the row), which would leave this panel's primary interaction unverifiable"*
(`PaintSoftware/Views/LayerStackListView.swift:13-18`). Whatever is proposed here has to say how it will
be verified.

**Ask the owner first** — more than anywhere else, because this one is a second program. Is the Mac in
the loop, or does the iPad talk to the Windows box directly? Is the goal a video *stream*, or a still
per camera move — the Blender workflow described sounds like the latter, and a still is enormously
cheaper. What does the layer show when the computer is not connected, and does the last frame save into
the document? And **is the "drop a file in and it appears" half a separate, much smaller feature that
could ship long before the live stream? INFERRED: it looks separable, and it would be worth asking.**

---

## 4. Audio

> "audio: implement the ability to add sounds to the animations, potentially including features like
> lipsync. Also ability to drop in audio files from computer."

**Nothing exists.** No audio framework is linked; the only hit in the whole app is an SF Symbol named
`waveform` on the debug action-recorder row (`PaintSoftware/Views/ActionRecorderControls.swift:90`). No
microphone usage description, no sound of any kind.

**What has to change — the dependency the owner did not name.** There is no clock to sync to. Playback
is a repeating `Timer` at `1.0/fps` whose callback re-dispatches onto the main queue and does
`currentFrame += 1` (`AnimationTimeline.swift:729-734`, `CanvasManager.swift:1384-1393`), and the
playback state lives on the **view** (`AnimationTimeline.swift:13-14`), not the model. A `Timer` on the
main run loop has no monotonic base and no drift correction. **INFERRED**: sync needs either a host-time
base with the frame derived from it, or an audio node as master and the playhead slaved to its render
time — and the playback state probably has to move onto `CanvasManager` first. Lipsync additionally
wants sub-frame time and a phoneme track, and neither `Cel` (whose `startFrame`/`frameCount` are `Int`)
nor `ProjectManifest` has anywhere to put one. Import has no route to copy either: there is no
`fileImporter` and no document picker anywhere, only a `PhotosPicker` for images.

**What this constrains on today's list.** Nothing. But it is worth knowing that item (1)'s "set frame
rate" makes the existing drift more visible, because a document at a rate other than 24 is the first
time anyone will watch the clock closely.

**Ask the owner first.** Is audio a property of the document or of a scene in item (6)? Does a sound
attach to a frame, to a cel, or to a free position on a time ruler that does not exist yet? And is
lipsync automatic — analyse the audio, pick a mouth shape — or a manual chart the artist fills in? Those
are completely different features.

---

## 5. Rendering and export

> "rendering: add the ability to export animations as video or a frame as image"

**The finding the owner should see first: there is no export feature at all, of any kind.** Not reduced,
not partial — absent. Searched exhaustively for `UIActivityViewController`, `.fileExporter`,
`CGImageDestination`, `AVAssetWriter`, `UIImageWriteToSavedPhotosAlbum`, `PHPhotoLibrary`,
`UIDocumentPicker`, `UTType`: **zero hits in app code and in tests.** The one `ShareLink` in the app
shares a **debug telemetry file** (`ActionRecorderControls.swift:142`). This is already recorded at
[LAYER_COMPOSITING.md](LAYER_COMPOSITING.md)`:411`: *"Export does not exist. There is no share sheet,
photo-library write, or image-export feature in the app — the only PNG writes are project persistence."*
The word "Export" reaches the artist only as reassurance copy for the Render Resolution knob
(`ActionsMenu.swift:253`, `:543`) — a promise about a feature with no code behind it. Several documents
name export as a consumer of some render path (README.md:42, LAYER_TRANSFORM.md:140 and `:243`,
CANVAS_RESIZE.md:795 and `:868`, TODO.md:166); **read all of them as describing a hypothetical consumer,
not a shipped one.**

**The only full-document composite on the save path is the gallery thumbnail, bounded to 320×320 since
`2f4b737`** ("Composite the gallery tile at the tile's size, not the whole canvas", 2026-08-20). The
bound is one constant, `ProjectStore.thumbnailBounds` (`PaintSoftware/Services/ProjectStore.swift:206`),
used as both the composite's size hint and the renderer's target so the two cannot drift, applied at
`:286-292`. Before that commit the save path *was* effectively a native full-document composite that
threw the pixels away — its message records 2,097,152 pixels rendered to fill the 51,200 a tile occupies
— and it anticipates this item: *"a future caller asking for something large is bounded by the same rule
the live canvas is"* (`RenderRequest.swift:520-521`).

**The good news is bigger than expected: the rendering primitive already exists, is pure, and is already
headless at arbitrary size.** `Compositor.composite(_:) -> CGImage?`
(`PaintSoftware/Engine/Compositor.swift:333-351`) documents itself as *"Pure: every input is a value the
caller owns, so this is safe to call from any thread"*, both backends run in the test tier with no view
or window (`Compositor.swift:62-68`), and `makeRenderRequest` is already frame-parametric
(`RenderRequest.swift:527`). **What is missing is a driver loop, an encoder and a destination — not a
renderer.**

**What it collides with.** An export must composite at **native** resolution, which is exactly the case
`CompositorBudget.affordableSize` does not bound: passing no `fittingWithin` skips the cap by
construction (`RenderRequest.swift:534-544`), the admission gate then returns `.unavailable`
(`MetalCompositor.swift:512-525`) and `Compositor` answers that with `CoreGraphicsCompositor.composite`
(`Compositor.swift:365-366`) at a MEASURED **203.3 ms** per grading composite (iPad 9, Release, warm,
2048²) — BUGS.md's 2026-08-28 entry (`:35-77`) is the write-up. **INFERRED, arithmetic only:** at that
cost a 240-frame export — ten seconds at 24 fps — is about **49 seconds** of CPU compositing, and the
owner's real documents are 300–1000 cels, not 240. `CanvasManager+Document.swift:287-288` currently
reassures that *"Saving and the project thumbnail are bounded to a 320×320 box and are unaffected at any
canvas size"*; **that sentence stops being true the day export ships**, and `CompositorSizeGate`
(`:292-316`) is the type that already knows how to warn about it. The memory constraint is written down
too, in LAYER_COMPOSITING.md §9.2 point 5: one frame is 16.8 MB at 2048², so 240 frames is **4 GB** and
at 4000² the same shot is 15 GB — *"Any design that holds baked frames as raw textures dies on the first
real sequence."* That paragraph was written for the sequencer and applies verbatim here.

**What this constrains on today's list.** Nothing blocking, but it changes how one open question reads:
CANVAS_RESIZE.md `:795` and `:868` reason about export being unaffected by canvas size. The reasoning is
sound and untested, because there is nothing to test.

**Ask the owner first.** Which container and codec, and does it need alpha? Is the paper background in
the export — [EFFECT_BACKDROP.md](EFFECT_BACKDROP.md)'s whole subject is that the paper is a `UIView`
behind the composite rather than part of it. At what resolution: the canvas, or a chosen one? And is a
slow, correct export acceptable, given the arithmetic above?

### 5b. Bake, stream and size to the device — **the single home for this feature**

**Consolidated here on 2026-08-30 at the owner's instruction**, after they observed it had been recorded
in two files at once and asked for it to stop being everywhere:

> "the feature that I just told you about the memory allocation render baking belongs in ROADMAP.md 5.
> Rendering and export. It's going to have to be implemented sometime as well as all the other stuff on
> roadmap, so it may be a good idea to clean up and organize the ideas properly instead of it being
> everywhere (todo and roadmap)."

**Six documents specify part of this. This section is the one that governs; the others are subordinate
and should be read as detail, not as competing designs.** They were written at different scopes on
different days, which is exactly how one feature acquired two eviction policies and two disk tiers:

| where | what it holds | status |
|---|---|---|
| **ROADMAP §5b — here** | the whole feature, the owner's three statements of it, and the couplings | **governs** |
| ROADMAP §5 (above) | export, which shares this feature's encoder and its native-resolution problem | sibling; build together |
| LAYER_COMPOSITING §9.2 | the same machine at *sequencer* scope — priority queue, disk LRU, evict on edit | detail |
| KEYFRAMES §4.6 | the same machine at *one keyframe span* — eager, complete, ruled 2026-08-28 (§2.19-20) | detail, and **ruled** |
| PERFORMANCE §8 | the ranked list of what would actually buy frames, each entry naming what is measured | evidence |
| TODO.md | **nothing, as of 2026-08-30.** Two items moved out of it into this section | — |

**The boundary that stops it scattering again**: TODO.md is asks being built or next; ROADMAP is
long-term features, none designed, each needing its own conversation first. **An ask that restates a
roadmap feature in new words belongs under that roadmap item** — not as a new TODO entry, which is the
mistake made on 2026-08-30 when the owner's memory architecture arrived and was filed as TODO (25).

---

**Originally: asked 2026-08-29, and the answer was that it is specified twice**

The owner, unprompted, on being told an in-between frame composites live:

> "does the compositor automatically bake in the background so that when playing every frame doesnt need
> to be composited live as it runs? ... the goal is to allow 24fps playback while conserving memory.
> Basically the animation bakes in the background, and the data of each frame other than the current
> frame gradually gets replaced with that baked 'video', so when the play button is run, every single
> frame does not need to be composited live. When something is modified, only the modified frames are
> rebaked."

**It does not, today.** `sandwichCacheKey` (`Views/CanvasView.swift:1145`) is a *single* key holding a
single composite: move the playhead and it recomposites. `MetalCompositor`'s caches are **upload**
caches — memoized, re-derivable texture uploads dropped under memory pressure — so they make one
composite cheaper and store no frames. Playback composites every frame, live.

**Worth pursuing, and the reason to write this down now is not the feature — it is that the feature
already exists in two documents at two scopes, and building them separately would give the app two
frame caches, two eviction policies and two disk tiers.**

- **§9.2 of [LAYER_COMPOSITING.md](LAYER_COMPOSITING.md)** is this proposal almost verbatim, written for
  the sequencer: priority queue (current frame → neighbours → rest of shot), disk-backed LRU, bake at the
  shot boundary, evict on edit.
- **§4.6 of [KEYFRAMES.md](KEYFRAMES.md)** is the same machine scoped to one keyframe span, and the owner
  **ruled on it on 2026-08-28** (§2.19, §2.20): span-scoped, eager, complete, recompute on settle, cache
  the **composite**, store it outside the project package.

Unify them before either is built. The two differ in exactly one interesting way and it is worth keeping:
§4.6 is **eager and complete over a span** because the owner rejected an LRU on the grounds that its hit
rate is invisible, while §9.2 is a **priority queue over a shot** because a shot does not fit anywhere.
Both are true, and the reconciliation is that the *policy* is scoped and the *store* is not.

**Three things are already built and should not be rebuilt.** §9.1 shipped: propagating content versions,
so a leaf edit bumps only its ancestors; **frame-scoped invalidation**, which is the owner's "only the
modified frames are rebaked" and cost nothing, because a cel already covers
`[startFrame, startFrame + frameCount)` and editing it invalidates exactly those frames; and a pure
snapshot-driven `composite(RenderRequest) -> Texture` taking an immutable tree snapshot, built that way
from day one so that adding a thread later is not a rewrite.

**The memory half of the ask is the hard part and it is already quantified** — §9.2 point 5, restated at
§5 above: one frame is 16.8 MB at 2048², so ten seconds at 24 fps is 240 frames = **4 GB**, and 15 GB at
4000². *"Any design that holds baked frames as raw textures dies on the first real sequence."* So the
owner's "gradually gets replaced with that baked video" is not a nicety, it is the only shape that works:
compressed to disk, with a small in-memory LRU of recent frames. **INFERRED**: a video codec is the
obvious store and it is the same encoder item (5) needs, which is a second reason to build the two
together — but a lossy intermediate is a decision the owner has not been asked for, and a scrub backwards
through a long-GOP stream is not free.

**Not scheduled.** The owner: *"let me know if it could be worth pursuing as a future task. Otherwise,
focus on current stuff for now."* This is the answer: yes, and it is nearer than it looks because the
substrate is in.

**And planning it settled a live question the same day, which is why this section earns its place rather
than merely recording an idea.** Told that engaging the compositor on an interpolation in-between costs
+75.7 ms/frame, the owner ruled the cost acceptable *because* of this feature: *"if we are planning for
this feature, then it is okay for things to take more than 1/24th of a second, including in-betweens...
if it prebakes and can play at 24fps after, then the original ask is covered."* That is KEYFRAMES §2.25 —
the live cost of a derived frame is not held to the frame budget; the prebake is. **So this unscheduled
item is already load-bearing**: it is the reason a 100 ms frame is allowed to exist on that path, and
anything that quietly drops it takes that permission with it.

**The owner's second thought on it, 2026-08-29, recorded and not investigated** — they asked explicitly
that a future ask be written down rather than researched now:

> "for the baking animation as video, I did some research, and it seems for the most part, the ipad gen 9
> has enough capability to just store that bake on disk, then play it from disk in real time without
> having to fill the entire animation to memory... So, store as many things on the disk. Only the current
> cel of the frame could be brought up to memory for example, with everything else that is baked stored in
> disk. Thus, it does not matter how large your animation is or how many layers or complex your compositor
> is, it always will play it 24fps while using minimal memory."

**This is an extension of a ruling they already gave**, not a new direction: cels are already specified as
**streamed, not held resident** (LAYER_TRANSFORM.md:295-296), and the arithmetic agrees — a drawn raster
cel is **6.558 MiB resident (MEASURED**, PERFORMANCE.md), and the owner's real scenes are 300-1000 cels,
so a fully-resident document is **2-6.5 GB (INFERRED**, arithmetic only). §9.2 point 5 reached the same
place from the other end.

**The owner's third statement, 2026-08-30, and it is the first one that specifies a *mechanism*.** Asked
to choose what to build next, they explained the feature again unprompted and in more detail:

> "the ipad does not have much memory, so I want the paint program to not use much by storing as many
> things it can to disk. Probably the current active cel is the only thing required to be in memory. The
> paint program automatically pulls unbaked frames from disk (layers, compositing, etc), bakes the
> compositing and stores it back straight to disk, so that when the play is pressed it can be played at
> 24fps. This way, the program doesn't run out of memory even with a hundred layers and a thousand cels.
> The memory is dynamically allocated: lets say we have layers 1 through 10 and the program has only
> enough memory for 3: the three bottom layers are pulled, composited and stored, then the next are
> pulled etc."

> "(NOTE: This is my thinking on how it may work, it may not be the most optimal. The session is gonna
> have to make a judgement on how exactly to do this. I eventually want to make it android and windows
> compatible so dynamic allocation of some sort may be nice.)"

**Three things this adds that the two earlier statements did not.**

1. **Layer-chunked accumulation is a new mechanism and it looks sound.** Pull as many layers as fit,
   composite, store, pull the next — valid for source-over and for every backdrop-reading blend mode,
   because each layer blends against the accumulation *below* it, which is exactly what a bottom-up
   chunk holds. **INFERRED; prove it against `blendOver` and the six non-separable modes before building
   on it.** Where it may not hold is anything reading content from *above* — the `above` half of the
   sandwich is where to look, and `RenderBackground`'s ink-exclusion walk is a second place.
2. **Portability is now a stated requirement, not a wish** — *"android and windows compatible"*. A budget
   hard-coded to an iPad, or an eviction signal that only iOS emits, fails it. This is a constraint on
   the design and it arrived before the design, which is the cheapest moment it could have.
3. **The mechanism is explicitly delegated and the goal is not.** The goal: a hundred layers and a
   thousand cels without running out of memory, and 24 fps on press-play. Anything meeting that is
   allowed to disagree with the sketch above, and the owner has said so in writing.

**What the performance end of the same feature already establishes**, moved here from TODO.md on
2026-08-30 so the two halves stop being read separately. The owner, 2026-08-29: *"Basically I want the
app to be able to play in realtime even with in betweens... if a smarter faster way is possible which
doesnt require a lot of code, then sure."* [PERFORMANCE.md](PERFORMANCE.md) §8 ranks the five candidates.
Two facts decide how that list reads: **composited playback already misses 24 fps on the device in
Release before interpolation is involved** (PERFORMANCE §2 item 5), so this is not one delta away; and
**KEYFRAMES §4.6's span cache does not cover it**, because §4.6 scopes itself to the transformation layer
and export. One prerequisite is shared by more of this repo than anything else on the list: **the
playback clock is a `Timer` whose state lives on the view** (`Views/AnimationTimeline.swift:13-14`, the
timer at `:976-989`), so it drifts; ROADMAP §4 (audio) and KEYFRAMES §5 (recording) each need it hoisted
onto the model for their own reasons.

**Three couplings that are cheap to note now and expensive to discover late. Nothing here was researched;
it is what the tree already says.**

1. **Scrubbing backwards is the hard direction, and it is the one an animator uses.** A long-GOP stream
   decodes forward from a keyframe, so stepping back one frame can mean decoding many. That probably
   forces an all-intra codec, which is larger on disk — a knowing trade, not a detail.
2. **Alpha.** [EFFECT_BACKDROP.md](EFFECT_BACKDROP.md)'s whole subject is that the paper is a `UIView`
   painted *behind* the composite, so the composite is not necessarily opaque. Few codecs carry alpha.
   Whether the baked store needs it is a real fork and it is unruled.
3. **It shares an encoder with item (5)**, which does not exist in any form. Whoever builds either should
   look at the other first.

**Unruled and owed by nobody yet**: whether a baked span survives a relaunch, and what sweeps it if the OS
purges `Library/Caches` (KEYFRAMES §9.4 asks the same question at span scope).

---

## 6. Video editor

> "video editor: (requires #5) right now each animation is viewed in the gallery. This would be the idea
> of being able to have them organized into scenes, episodes, etc, so an entire movie can be made and
> exported."

**Correcting this task's own lead, because it changes the shape of the item. The gallery has no folders
at all.** The test named `testDroppingFolderOntoFolderNestsIt` is
`PaintSoftwareUITests/LayerUITests.swift:262`, and it tests **layer** folders inside one open document —
nothing to do with the gallery. The gallery is a flat `LazyVGrid` over a flat array of `ProjectSummary`
(`PaintSoftware/Views/GalleryView.swift:7`, `:19`, `:34-43`), filled by a **single non-recursive**
`contentsOfDirectory` scan of `Documents/Projects` filtered to `.paintproj`
(`ProjectStore.swift:38-57`). `ProjectSummary` (`:19-29`) has no parent, no order field and no grouping.
A nested directory would simply be invisible.

**"Scene" in this codebase is a false friend.** `sceneFrameCount` is *"the laid-out length of the
timeline"*, per its own doc (`CanvasManager.swift:1352-1356`) — not a unit of a movie. Informally, one
document already ≈ one shot: the timeline's project-name field is literally labelled
`TextField("Scene", …)` (`AnimationTimeline.swift:524`).

**The blueprint exists, one level down.** The layer tree is a complete, tested, persisted,
arbitrarily-nested folder system with first-class per-node metadata: `LayerFolder`
(`PaintSoftware/Models/LayerFolder.swift:3`) carries `parentFolderID`, name, expansion, visibility,
opacity, blend mode, isolation, mask and effect; `rows(inContainer:depth:)`
(`CanvasManager+LayerTree.swift:28-41`) is recursive to arbitrary depth with cycle-safe subtree and
`canDrop` logic beside it; and it persists as `FolderManifest` (`ProjectManifest.swift:131`). **It is
inside the document, so item (6) cannot reuse the code — only the design.** That is still the most
valuable thing here: the hard questions have been answered once already in this repo.

**And the architecture has already been aimed at this item, before it was written down.**
[LAYER_COMPOSITING.md](LAYER_COMPOSITING.md) §9 opens: *"Aimed at the future video sequencer (many
shots, many scenes chained). **Decision: build the substrate now, the thread and the disk cache when the
sequencer exists.**"* §9.1 lists what is being built now — propagating content versions, frame-scoped
invalidation that falls out of `Cel.startFrame`/`frameCount` needing no new bookkeeping, and the pure
snapshot-driven entry point — and §9.2 lists what waits: the priority queue and the disk-backed LRU.
**INFERRED**: the honest ordering is *substrate → (5) → (6)*, with the substrate already under way for
its own reasons.

**What has to change beyond the tree.** A `.paintproj` is a package **directory**
(`ProjectStore.swift:59-70`, `:624-626`) with a versionless, additively-migratable `manifest.json`, so
nesting packages inside a scene directory is a filesystem operation rather than a format change — that
part is genuinely cheap. What is not: `ContentView` holds exactly **one** `CanvasManager` and one of
three screens (`ContentView.swift:3-11`, `:33-44`), and that manager is also the undo owner
(`CanvasManager.swift:659`). Ordered playback across documents needs either a second manager or a model
that can hold several. `ProjectBackupManager` keys version history by *project* UUID (`:72-74`), so a
scene needs its own identity and backup story. And canvas size, `fps` and `canvasPadding` are **per
document** (`ProjectManifest.swift:6-11`) — a movie assembled from documents that disagree on any of
those needs a conformance rule that does not exist anywhere today.

**Ask the owner first.** Is a scene a *folder of documents*, or a new document kind that references
them? Does a shot appear in more than one scene? Is the cut list part of a package or a separate file?
What happens when two documents in one movie disagree on frame rate or canvas size? And — the question
that decides the data model — when a movie is exported, is it re-rendered from the source documents, or
assembled from per-scene exports?

---

## The standing rule, once more

Every item above is unscoped and undesigned. The owner said what they want and asked to be asked how it
works. **Opening that conversation is the first task of whichever item is picked up, not a step inside
it** — and their answers belong in the item, in their own words, the way TODO.md keeps them.
