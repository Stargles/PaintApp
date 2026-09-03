# Importing video

TODO item (26). A video lives in a vector layer as an element, occupies a cel, and is cropped by dragging
that cel's edges. It is the first content in the document that varies across the frames one cel spans, and
it is the dependency for (27), screen recording.

---

## 1. The brief, verbatim

> "Import videos: (requires #1) like import images, but exist as videos. Since videos have a specified
> length, a vector layer containing a video can only have one video and must be a specific length (but add
> that length able to be cropped). Should have the same option to bake to multiple cels containing images
> instead of the video."

And the design briefing that settled it:

> "This implementation can be rather straight forward. When you import a video, lets have it be imported
> inside of its own vector layer for simplicity. adjusting the length of the block from both ends will have
> the effect of cropping the video. In the double click menu, there should also be an adjust speed option in
> which you can adjust the video speed. I also want an option in the double click cel menu to split drawing,
> which will work both in video and in normal cels. This splits the cel into two cels at the time cursor. For
> video it splits the video and automatically crops it into two. For normal cels it just splits them. For now
> I don't think it will be used much for keyframe animated cels, so you dont need to add that functionality
> in."

---

## 2. Rulings — settled, do not re-litigate

**2.1 A video arrives in its own vector layer.** One video per layer, created by the import. *"lets have it
be imported inside of its own vector layer for simplicity."*

**2.2 Dragging either edge of the block crops the video.** Not a retime and not a stretch — the frames
outside the block are simply not shown. *"adjusting the length of the block from both ends will have the
effect of cropping the video."* Both edges, so a left-edge drag crops the head.

**2.3 A source frame rate that differs from the document's is resampled to the document's rate**, so a clip
plays at correct real-world speed and duration. Frame-for-frame playback — every source frame shown, one per
document frame — is reachable, but as a *setting of Adjust Speed* rather than as the import default.

**2.4 A video imported into a shorter scene clips to the scene and crops outward.** The block arrives at the
current scene's length holding the head of the clip; dragging its right edge outward reveals more, up to the
full duration. **Import never changes the shape of the timeline.**

**2.5 Adjust Speed changes the block's length.** At 2x the block halves: same footage, half the frames, and
the block's length continues to mean its duration. Later cels do not move — the timeline does not ripple.

**2.6 Audio is not decoded now, and the seam for it is built now.** Owner: *"audio will eventually get added.
Set it up so the implementation when it eventually does is smooth."* §6.

**2.7 Split Drawing cuts a cel in two at the time cursor, on video cels and ordinary cels alike.** On a video
it splits the footage and crops each half to its own block. On an ordinary cel both halves hold the same
drawing.

**2.8 Split Drawing is not built for keyframe-animated cels.** *"For now I don't think it will be used much
for keyframe animated cels, so you dont need to add that functionality in."*

**2.9 Baking a video to cels of images stays in scope** — the brief's *"same option to bake to multiple cels
containing images instead of the video"*, which is KEYFRAMES §6's Bake reaching a new source.

**2.10 A video is an object like a placed image: a lasso catches it the same way, it moves, and it never
splits.** Owner: *"lasso should be able to catch a video in the same way it catches an image. Videos should
be objects similar to images which can be moved around, but not split (unless it is rasterized and
baked)."* So membership follows LASSO_MOVE §5.23-24 exactly as a photo does — by centre under Cut, by its
own quad under Touching and Enclosed — and the four refusals in §4.2 stand, `splitForLassoMove` among them.
The parenthesis is §2.9 arriving by another door: bake the video to cels of images and those images split
like any other ink, because by then it is ink.

---

## 3. What already exists, and it is most of the plumbing

**Split Drawing is nine-tenths built.** `CanvasManager.splitCel(layerIndex:celIndex:atFrame:)`
(`Models/CanvasManager+Timeline.swift:578`) copies every content tier to both halves, splits
`transformTracks` through `TransformTrack.split(atCelLocalFrame:)`, carries `pendingPoseBaselines`, sorts the
array and regenerates the thumbnail — all inside `withStructureUndo`. It guards
`atFrame > cel.startFrame, atFrame < cel.endFrame`, so an edge cut is already refused rather than producing an
empty cel. **It has no caller outside four tests.** The verb is a menu row.

**The menu it belongs in already carries the frame.** `AnimationTimeline.swift`'s `.block` arm — Copy, Select
Multiple (a disabled stub), Extend to End, Clear, the keyframe section, Delete — is built from
`menuButton(_:icon:role:action:)` and destructures `frame` from the case. **It opens on a single tap, not a
double tap; there is no double-tap gesture anywhere in the app** and the brief's "double click menu" means
this one.

**Cropping is the existing edge-drag verbs.** `resizeCelLeftEdge` mutates `startFrame` *and* `frameCount`
keeping `endFrame` fixed; `resizeCelRightEdge` mutates only `frameCount`. §2.2 needs no new gesture — it needs
those two to mean "crop" when the cel holds a video.

**A video element is a placed image with a time axis.** `VectorImageElement` carries `transform:
LayerTransform` plus `aspect` / `stretchAxis` / `mirrored`, read back through the computed `placement`. A video
element reuses that geometry verbatim; the only new state is which source frame to show.

**The export path already establishes the codec conventions a reader must mirror.** `VideoFrameWriter`
(`Engine/FrameExport.swift`) writes H.264 in `.mp4`, `kCVPixelFormatType_32BGRA`, timing as
`CMTime(value: index, timescale: fps)` — an exact rational, deliberately not seconds, to avoid drift on long
exports — and tags no colour space, inheriting `PixelOps.deviceRGBColorSpace`. `import AVFoundation` appears
in that one file; there is no reader anywhere.

**Import lands on the `PhotosPicker` seam.** `ActionsMenu.swift` picks a photo, loads it as `Transferable`
`Data`, and calls `CanvasManager.insertImage`, which creates a vector layer if the active one is not vector.
`matching: .videos` on a picker beside it is the whole import gesture. (TODO (27)'s claim that the app has zero
`Transferable` code is wrong in this one respect; it is right about `fileImporter`, `UTType`, `NSItemProvider`
and drag-and-drop.)

---

## 4. The model

### 4.1 The element

A fifth `VectorElement` case, `.video(VectorVideoElement)`, holding the placement fields
`VectorImageElement` holds plus the source binding:

- `assetFileName: String` — the copied source in the project package.
- `assetURL: URL` — runtime-only, where those bytes are *now*; `ProjectStore`'s load resolves it out
  of the package and drops the element when the file is not there, exactly as a missing PNG drops a
  placed image. The persisted twin stores no path.
- `naturalSize: CGSize` — **the source's own pixel dimensions, and this list did not have it.**
  Added by stage 2, because a placement has to be expressible with no decoder present: `placement`
  maps a rect of this size, so without it the element cannot say where its own rectangle is and
  neither the render, the membership quad nor the lasso's reach has anything to work with. An image
  gets its size free with its pixels; a video does not.
- `sourceStart`, `sourceEnd` — the crop, **in source time**, as exact rationals. §2.2 writes these.
  Stage 2's `SourceTime` is a normalised `value`/`timescale` pair, not `CMTime`: `CMTime` is not
  `Codable` and would need this struct as its DTO anyway, and normalising is what makes `==` agree
  with `seconds` about whether `2/4` and `1/2` are one instant.
- `speed` — §2.5.
- the placement group: `transform`, `aspect`, `stretchAxis`, `mirrored`. Shared with
  `VectorImageElement` through the `PlacedRectangle` protocol stage 2 factored out, which is also
  where `placement`, `quad(of:)`, `bounds(of:)` and `placed(_:through:)` now live — once, for both
  kinds, so the two cannot come to disagree about where a rectangle of pixels is.

**The lifetime is *not* `ImageRef`'s, and that sentence was the misleading half of this list.** An
image's runtime payload is a `UIImage` in memory and its file is a cache the save re-encodes; a
video's payload *is* the file, so `assetFileName` is non-optional and the save copies bytes rather
than encoding them. What makes that copy safe is `writeAtomically`'s step order — the new package is
staged *before* the live one is moved aside, so `assetURL` still names a real file when `writeCel`
reads it, and the swap puts the new package back at the same path.

**Crop is stored in source time, not in document frames.** A crop expressed in document frames would move
under a speed change and under a document frame-rate change, and §2.5 changes the block length on purpose —
those two must not interact. Source time in, document frames out, once, in §4.3's map.

### 4.2 The cost of a fifth case, and it is the real work

`VectorElement` is switched exhaustively at roughly two dozen sites across `VectorLayer.swift` and seven more
engine and model files, plus its persisted twin `VectorCanvasData.ElementData`. **This is the bulk of the
change and it is mechanical**: the compiler names every site. Budget for it rather than being surprised by it,
and resolve each arm deliberately — several will be a genuine refusal (a video is not lassoable ink, not
splittable by the vector eraser, not interpolatable) rather than a translation of the image arm.

**Built, and smaller than the survey said. It was fifteen arms, not two dozen** — one `VectorElement`
switch each in `AnimationGroup.swift` (×2), `CanvasManager+Interpolation.swift`,
`CanvasManager+LassoMove.swift`, `CanvasManager+Document.swift`, `SelectionModels.swift` and
`InterpolationEvaluator.swift` (×2), and eight in `VectorLayer.swift`. **`Compositor.swift` and
`MetalCompositor.swift` are not on the list at all**: their `case .image` is
`MetalCompositor.Attempt.image`, a different enum, and the compiler names neither file.

How they resolved. **A video is a placed rectangle wherever the arm is about the rectangle** — the
similarity and stretch maps, `canBeMapped`, the eraser's residue-overlap test, the lasso's
membership under all three modes, the move cluster's hull, and the render. It is caught by a lasso
by its centre under Cut and by its own quad under Touching and Enclosed, exactly as LASSO_MOVE.md
§5.23-24 settled for a photo — refusing instead would make a Move that lassoes the whole canvas
silently leave the video behind, which §9's open question can still overrule but which is the worse
default. **Four are refusals**, each explicit rather than a fallthrough: it is never split by the
lasso (§7 reserves the only legitimate cut of a video for Split Drawing, which cuts it in *time*);
Change Colour skips it, as it skips a photo; `InterpolationEvaluator` passes it through unwarped;
and it contributes **no registration points**, for the text arm's reason — a lattice grown to cover
it would move nothing inside it and would only make every other element's warp coarser.


### 4.3 The frame map

One function, and everything about §2.3 and §2.5 lives in it:

```
documentFrame  →  sourceTime = sourceStart + (documentFrame - cel.startFrame) · speed / documentFPS
               →  nearest source frame at that time
```

§2.3's resampling *is* "nearest source frame at that time" — nothing else is needed for it. It is a speed
setting rather than a separate mode: the two are the same control, and one of them has a name.

§2.5 is the inverse read: setting a speed rewrites `frameCount` to `(sourceEnd - sourceStart) / speed ·
documentFPS`, then leaves neighbours alone.

**Built as `VideoFrameMap` (`Engine/VideoFrameMap.swift`), and this section had the frame-for-frame
formula upside down.** It said `speed = sourceFPS / documentFPS`; the line above it refutes that. One
document frame advances the source by `speed / documentFPS` seconds, so showing exactly one source frame
per document frame means that quantity is `1 / sourceFPS`, i.e. **`speed = documentFPS / sourceFPS`**. The
inverse read corroborates it: at that value the block length is `span · sourceFPS`, the number of source
frames, where the inverted value gives `span · documentFPS² / sourceFPS`, a number with no meaning.
Concretely, 30 fps footage in a 24 fps document plays frame-for-frame at **0.8** — slowed down, over 30
document frames rather than 24 — which is what "every source frame shown" costs and is the reason §2.3
makes real time the default and this the setting. `VideoFrameMapLogicTests.testFrameForFrameShowsEvery
SourceFrameExactlyOnce` is the pin, and at the documented 1.25 it lands on `0, 1, 3, 3, 4, 5, 6, 8, 8, …`.

**The map is exact at `speed == 1` and the working timescale is what makes it so** — but the obvious
denominator is not fine enough, and the reason is a property of `SourceTime` rather than of the map.
`sourceStart.timescale · documentFPS` divides both terms and looks sufficient; `SourceTime` *normalises*,
so a crop starting at the head of the clip has timescale **1**, and the denominator collapses to
`documentFPS` — one tick per document frame, every fractional speed quantised to a whole document frame.
The map builds on `lcm(sourceStart.timescale, documentFPS)` scaled up by a thousand, which keeps the start
and the speed-1 step exact, makes the tick about a microsecond, and keeps every decimal speed an artist can
type (0.5, 0.8, 1.25, 2) exact as well.

**Two "nearest"s exist and they have to agree about ties.** `VideoFrameMap.sourceFrameIndex` names a
source frame by arithmetic, for a test or a menu; `VideoFrameReader` picks one by the presentation
timestamps the file actually carries, which is right for variable-rate footage where a nominal rate is a
lie. Ties are reachable rather than exotic — 30 into 24 lands on one every fifth frame — so both round
**up**, to the later frame.

### 4.4 The `"video"` sentinel has to be replaced

`VectorCanvasData.ElementData` decodes its `kind` as a raw `String` and reports an unrecognised one through
`DecodeReport.unknownKinds`, dropping that one element rather than the cel. `VectorCanvasDataLogicTests` and
`SaveDamageGateLogicTests` use the literal `"video"` as their unimplemented kind. **Implementing it takes the
sentinel away**; both files need a new one that is genuinely unimplemented, and the comments naming why must
move with it.

**Done. The sentinel is now `"nurbsPatch"`, and it is the last time this can happen quietly.** It was
`"text"` until `ADD_TEXT.md` stage 3 and `"video"` until this stage, and on both occasions the tests
went on passing while measuring something else entirely — not "an unknown kind costs one element" but
"a feature this build ships is absent". `VectorCanvasDataLogicTests.testTheSentinelIsNotAKindThisBuildImplements`
closes it mechanically: it asks the *encoder* for the discriminators it writes and fails if the
sentinel is among them. `SaveDamageGateLogicTests` reads the same constant, so the two cannot drift.


---

## 5. Where a decoded frame comes from

`CanvasManager.derivedCelContent(for:atFrame:overridingT:)`
(`Models/CanvasManager+Interpolation.swift:1294`) already branches on `cel.interpolation` and otherwise falls
through to `posedCelContent`. **A video is a third branch of that accessor** — the seam TODO (26) predicted,
arriving exactly where it said it would.

The two cache tiers are reusable rather than duplicated. `FrameBakeStore` is the SHA-256-addressed disk tier
under a 512 MiB byte budget; `DecodedFrameRing` is the in-memory LRU under a byte budget, refusing any single
frame larger than the whole budget. A decoded video frame is a `DecodedFrame`. **What is owed is one component
in `FrameBakeKey`** so "source frame N of asset X" cannot collide with an ordinary bake — and `FrameBakeKey` is
a hand-written canonical byte encoder with a discriminator per case and no `default:` clause, so adding one is
a compile-error-guided change rather than a silent collision.

**Decoding is sequential and the ring is not.** `AVAssetReader` is a forward pipe; scrubbing backwards means
tearing it down and re-seeking, which is the one place this feature can be slow in a way the store cannot fix.
Design the reader around a playhead the way `BakeQueue` already is, rather than around random access.

**Built. `VideoFrameReader` is that playhead and `VideoFrameSource` owns the fleet of them.** The reader
holds two samples — the newest at or before the instant wanted and the first after it — so "nearest"
costs one sample the pipe was going to deliver anyway, a forward scrub across a whole clip is **one**
pipe however many frames it holds, and a backward step is **one** rebuild and no more (both MEASURED, as
`seekCount`, in `VideoFrameReaderLogicTests`). Resuming forwards after a backward step re-seeks nothing.
The only unbounded case is an instant past the end of the clip on a fresh reader, which re-opens at the
head and walks to the tail once, because a pipe opened past the end delivers nothing at all.

**The ring is keyed by the timestamp the *file* carries, not by the instant the map asked for.** That is
what makes a clip at half speed one decode per source frame rather than two, and it is why `locate` and
`currentFrame` are two calls: the ring is consulted between them, so a hit converts no pixels.

**Three corrections to this section's cache story.** *One:* only the in-memory tier is reused —
`FrameBakeStore` holds *composited* frames and is reached without the reader knowing about it, so there
is deliberately **no** second on-disk store of decoded source frames; the source file already is one, and
re-decoding it is what a seek costs. *Two:* the component `FrameBakeKey` was owed is
`VideoCelIdentity.cuts` — asset file name plus resolved `SourceTime`, per video element — and it arrives
through `LayerContentVersion.derived` rather than through a new field on the key, which is what keeps
RENDER §3.3's "a hold is one file" intact for everything that is not a video. `VideoCelIdentity` is the
first type in the app to conform to `BakeKeyEncodable`, so it is walked field by field rather than
through `BakeKeyEncoder.derived`'s reflective fallback. *Three:* this file said adding the component is
"compile-error-guided". **It is not.** `FrameBakeKey`'s no-`default:` rule catches a new enum *case*; a
new stored *property* is a compile error nowhere, which is exactly the shape of `cuts` — omit it and
every document frame of a video block is one digest, the store serves frame 0's picture for the whole
block, and nothing errors at any level. MEASURED by mutation: deleting those four lines reddens
`testTwoFramesOfOneVideoBlockAreTwoDigests` and leaves the ordinary-hold control green.

**The render substitutes a frame into the video element rather than swapping in a `VectorImageElement`,
and the shorter route would have moved the picture.** An image draws at `image.size`; a video's placement
maps `naturalSize`. A decoded buffer disagreeing with the stored size by a pixel would then land
somewhere the lasso's own quad is not. So `VectorVideoElement` gains a runtime-only `displayFrame` in
`assetURL`'s exact sense, `draw(video:into:)` fills the identical rect whether the frame arrived or not,
and stage 2's placeholder becomes the not-decoded-yet state instead of a second code path — which is
also what an asset that will not open still shows.

**A video cel that also carries transform channels is one derivation, not two.**
`CanvasManager.videoCelContent` is a superset of `posedCelContent`: same `poseMappings`, same
`posed(_:through:inheriting:)`, plus the frames. `derivedCelContent` asks it first and falls through to
the pose arm, and it answers nil on one memoized `Bool` (`VectorCanvas.holdsVideo`) for every cel of
every document that has never imported a video.

---

## 6. Audio — the seam, per §2.6

Nothing decodes or plays audio. What is built now is that **nothing makes it harder later**:

- **The source file is copied into the project whole**, tracks and all — not a re-encoded video-only asset.
  Once discarded, audio cannot be recovered without the artist re-importing.
- **The crop is stored in source time** (§4.1), which is the same axis audio will be cut on. A crop in document
  frames would have to be re-derived against the source clock the day audio arrives.
- **`speed` is a property of the element, not baked into the crop**, so audio can later read the same field and
  decide independently whether to pitch-shift.
- **The frame map (§4.3) is one function**, so an audio-time map is a sibling of it rather than a re-derivation.

---

## 7. What Split Drawing does to each kind of cel

| cel holds | result |
|---|---|
| an ordinary drawing | two cels, both holding the same drawing — what `splitCel` already does |
| a video | two cels; `sourceEnd` of the left half and `sourceStart` of the right are both set to the cut's source time, so each half is cropped to its own span with no re-encode and one shared asset file |
| an interpolated in-between | both halves carry the recipe — already implemented, and deliberate: a split makes no copy, so both halves are the same in-between of the same pair at the same `t` |
| keyframe-animated content | §2.8 — not built. `splitCel` already splits `transformTracks` correctly, so the model is not the gap; the gap is that nobody has decided what it should mean. **It must refuse visibly rather than silently mis-split** |

---

## 8. Build order

1. ~~**Split Drawing on ordinary cels.**~~ **Merged.** A menu row in the `.block` arm gated on `startFrame < frame < endFrame`,
   calling the verb that already exists, plus the test it never had. **No video involved** — independently
   useful, and it proves the menu seam before anything larger leans on it.
2. ~~**`VectorVideoElement` and the fifth case.**~~ **Built.** §4.1 and §4.2 — the model, the persisted twin,
   every exhaustive switch, and the sentinel swap (§4.4). No decoding: the element persists, round-trips,
   degrades when its asset is missing, and renders a placeholder rectangle drawn through its own `placement`
   so that what a lasso catches is what the artist can see. `VideoElementLogicTests` is its suite.
3. ~~**The reader and the frame map.**~~ **Built.** §4.3 and §5 — `VideoFrameMap`, `VideoFrameReader` and
   `VideoFrameSource`, `VideoCelIdentity` as the `FrameBakeKey` component, and `videoCelContent` as
   `derivedCelContent`'s third branch. A video plays. `VideoFrameMapLogicTests` and
   `VideoFrameReaderLogicTests` are its suites, and their clips are generated at test time with the app's
   own `VideoFrameWriter` so a test can say *which* frame came back.
4. **Import.** `matching: .videos` beside the existing picker, landing a video in its own new vector layer per
   §2.1, clipped to the scene per §2.4.
5. **Crop.** Teach `resizeCelLeftEdge` / `resizeCelRightEdge` to write `sourceStart` / `sourceEnd`. §2.2.
6. **Adjust Speed.** A menu row and §4.3's inverse. §2.5, including the frame-for-frame setting §2.3 names.
7. **Split Drawing on video cels.** §7's second row — trivial once 2 and 5 exist, which is why it is not
   stage 1's problem.
8. **Bake to cels of images.** §2.9.

---

## 9. Open

- **§2.8's refusal has no wording.** What the artist sees when they ask to split a keyframe-animated cel is
  undecided; the ruling is only that the functionality is not built.
- **Whether a video layer refuses ink.** §2.1 gives a video its own layer, but nothing yet says whether the
  artist can draw into it, and the rotoscoping workflow (27) is built around wanting to draw *over* a video
  rather than on it.
- **A video has no Distort door**, inheriting the placed image's gap: six numbers plus a mirror bit where a
  homography needs eight. §2.10 settles the lasso and the refusals — §4.2's built note carries the arms and
  the reasoning behind each — but not this one.
- **Backwards scrubbing cost** (§5) is now counted rather than timed: one pipe rebuild per backward step,
  zero for any forward walk. What is still unmeasured is what a rebuild costs in *milliseconds* on the
  iPad, which depends on the clip's keyframe interval and is the number PERFORMANCE.md would want. Also
  unmeasured: `VideoFrameSource` holds one lock across the decode, so a backward seek blocks the other
  render workers behind it.
- **A quarter-turn clip is decoded the way it is stored.** `VideoFrameReader.info` reports the track's
  `preferredTransform` and the `rotation` it implies, so an import can fold it into
  `LayerTransform.rotation` and resample nothing — but nothing does that yet, so a phone-shot portrait
  clip imported today would lie on its side. Stage 4's problem, and the seam for it is built.
- **The element stores no source frame rate**, and stage 3 does not need one: the reader picks by real
  presentation timestamps and the bake key names an *instant* rather than a frame index. **Stage 6 does**
  — §2.3's frame-for-frame setting is `documentFPS / sourceFPS` and the menu has to offer it without
  opening a decoder, which is `naturalSize`'s argument (§4.1) reaching a second field. Adding it also
  lets the key snap to the source's own frame grid, so a clip at half speed would be one bake per source
  frame instead of two; today it is two, which costs disk and never a wrong picture.
