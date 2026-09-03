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

- `assetFileName: String` — the copied source in the project package, the same lifetime story as `ImageRef`.
- `sourceStart`, `sourceEnd` — the crop, **in source time**, as exact rationals. §2.2 writes these.
- `speed` — §2.5.
- the placement group: `transform`, `aspect`, `stretchAxis`, `mirrored`.

**Crop is stored in source time, not in document frames.** A crop expressed in document frames would move
under a speed change and under a document frame-rate change, and §2.5 changes the block length on purpose —
those two must not interact. Source time in, document frames out, once, in §4.3's map.

### 4.2 The cost of a fifth case, and it is the real work

`VectorElement` is switched exhaustively at roughly two dozen sites across `VectorLayer.swift` and seven more
engine and model files, plus its persisted twin `VectorCanvasData.ElementData`. **This is the bulk of the
change and it is mechanical**: the compiler names every site. Budget for it rather than being surprised by it,
and resolve each arm deliberately — several will be a genuine refusal (a video is not lassoable ink, not
splittable by the vector eraser, not interpolatable) rather than a translation of the image arm.

### 4.3 The frame map

One function, and everything about §2.3 and §2.5 lives in it:

```
documentFrame  →  sourceTime = sourceStart + (documentFrame - cel.startFrame) · speed / documentFPS
               →  nearest source frame at that time
```

§2.3's resampling *is* "nearest source frame at that time" — nothing else is needed for it. §2.3's
frame-for-frame arm is `speed = sourceFPS / documentFPS`, which is why it is a speed setting rather than a
separate mode: the two are the same control, and one of them has a name.

§2.5 is the inverse read: setting a speed rewrites `frameCount` to `(sourceEnd - sourceStart) / speed ·
documentFPS`, then leaves neighbours alone.

### 4.4 The `"video"` sentinel has to be replaced

`VectorCanvasData.ElementData` decodes its `kind` as a raw `String` and reports an unrecognised one through
`DecodeReport.unknownKinds`, dropping that one element rather than the cel. `VectorCanvasDataLogicTests` and
`SaveDamageGateLogicTests` use the literal `"video"` as their unimplemented kind. **Implementing it takes the
sentinel away**; both files need a new one that is genuinely unimplemented, and the comments naming why must
move with it.

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

1. **Split Drawing on ordinary cels.** A menu row in the `.block` arm gated on `startFrame < frame < endFrame`,
   calling the verb that already exists, plus the test it never had. **No video involved** — independently
   useful, and it proves the menu seam before anything larger leans on it.
2. **`VectorVideoElement` and the fifth case.** §4.1 and §4.2 — the model, the persisted twin, every exhaustive
   switch, and the sentinel swap (§4.4). Still no decoding: the element persists, round-trips, and renders a
   placeholder.
3. **The reader and the frame map.** §4.3 and §5 — `AVAssetReader`, the `FrameBakeKey` component,
   `derivedCelContent`'s third branch. A video now plays.
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
- **What a video element does under a transform, a lasso, or the vector eraser.** §4.2 says several arms are
  refusals; which ones is not settled, and the placed-image precedent is itself unresolved here — a photo has
  no Distort door, and a video inherits that.
- **Backwards scrubbing cost** (§5) is unmeasured, and it is the one performance question this feature owns.
