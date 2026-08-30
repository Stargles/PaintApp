# Keyframes

**Animating properties across the frames one cel spans.** ROADMAP.md item (1), specified 2026-08-28
after the conversation that file names as each item's entry condition. This is the design; nothing is
built yet.

**What this is not.** It is not the interpolation feature. That one in-betweens *drawings* between two
reference cels and ships already ([VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)). This one moves
and grades content that is already drawn. They are complementary, they will sit in the same timeline,
and §2.8 is how the artist tells them apart.

**How to read it.** Blockquotes are the owner's own words. §2 is the settled rulings — twenty-seven of
them, twenty from 2026-08-28 and seven from 2026-08-29 — and TODO.md's rule applies: *a question the owner has answered stops being a
question*. Everything else is our reading of the tree at `2eb3e5f`, marked INFERRED where it is a guess.

---

## 1. The brief, verbatim

> "Keyframes: (objects within a cel can get keyframed and move for the duration of that cel). Also
> applies to stuff like sliders for effects. Also includes interpolation curve customization. You
> should also be able to bake the cel containing animation into multiple cels (frames), and also set
> frame rate. Transformation layers adds transformation animation to whatever is under it."

And, expanding it:

> "User has a cel selected to which they can then have the option in the animation menu to add a
> keyframe to that frame on that cel. Then, they go to another frame of the same cel, add another
> keyframe, and adjust whatever thing they want as long as it is not destructive or constructive (like
> adding a new stroke)."

> "when you press on the keyframe button again when a keyframe is already made, a menu will show up
> containing a list of every transformation that currently is changing with that keyframe as an anchor
> point. The user can now click on these and open up the graph editor similar to blender."

> "I also want a feature where the user can somehow record transformations live. For example, they
> press a record button and put their pencil on the slider, and then it starts recording the motion of
> that slider and puts it into the graph editor. Another example is say they want screenshake, the user
> will press move on the entire canvas and then record, place his pencil down on the box and then shake
> it, and it will record it."

> "I want a feature in which the user can record their own stylus on the canvas for timing… With the
> tool selected, it will start recording when the pen touches the paper, stop recording when its
> lifted, and after that generate a cel in the current vector layer at the selected position (unless it
> has no space) in which something akin to a laser pointer is displayed. Like a brush stroke, but the
> tail tapers and ends from the point at where it was on the previous frame."

Videos as vector-layer objects are **ROADMAP item (2)**, not this document. They inherit this feature's
pose channel and its bake, which is why item (2) is stated to require item (1).

---

## 2. Rulings — settled 2026-08-28 and 2026-08-29, do not re-litigate

**Three of these are superseded, and they are kept rather than deleted.** §2.1, §2.23 and §2.24 were
overtaken by §2.26 and §2.27 later on 2026-08-29 — the owner reversing their own ruling, which is not a
re-litigation. Each is marked in place with the date and the reason, because the reasoning is what stops
a later session reinstating it by rediscovering the argument that produced it.

1. ~~**Tap the keyframe button inserts a key. Hold it 0.8 s enters or exits Animate mode.** In Animate
   mode any non-destructive change at the playhead writes a key on exactly the channel touched. The
   button is therefore both an action and a mode, and the channel list is a panel, not a second press.~~
   **SUPERSEDED 2026-08-29 by §2.26.** Built as stage 3a and then withdrawn on sight of it: *"I'm not
   sure if I like the animation mode."* What replaced it keeps the half that was right — the channel
   list is reached by pressing the button — and drops the mode. Worth keeping because two of its
   findings outlived it: a mode reached by a hold has to be advertised or it is undiscoverable
   (`LayerPanel`'s `primaryAction` was reverted for exactly that), and a control that is *disabled*
   cannot be held either. Neither applies now, and both would apply again to any future mode reached
   by a gesture.
2. **Transform channels must eventually cover all three Move modes — Uniform, Freeform and perspective
   Distort** — including the Distort that is not implemented today
   (`TransformMode.distort.isImplemented == false`, `Models/SelectionModels.swift:54`).
3. **A transformation layer re-poses the vector objects below it**, rather than resampling the
   composited pixels below it. The owner wants crisp lines, not a bitmap magnify. This answers the
   question ROADMAP.md:173-174 raised and called *"different features wearing the same name"*.
4. **Effect-parameter keys live on the layer, in absolute document frames** — not on the cel. The owner:
   *"for effects it really does not have to be anchored to one singular cel, in fact that would likely
   be better."*
5. **A transform key stores a pose, and it is written at commit.** The owner: *"as soon as it starts
   moving, it should save a state of the unmoved item at keyframe A, then when the move 'bakes' as in
   the box disappears, keyframe B receives the second position."* So the cel holds **one** drawing, in
   its rest position; keys hold poses; the render composes them. **A nudge writes no key** — §4.2.
6. **The value layer's "Blend Mode" menu is relabelled to follow what is set** — Blend Mode / Effect /
   Transform. The owner: *"that 'blend mode' is very vague since effects, blend modes, and now the
   transform will be added to it."*
7. **An editable fps control ships with this feature**, so the artist can take the document below 24.
8. **The two meanings of "keyframe" are separated in the UI as "animation keyframes" (this feature) and
   "interpolation keyframes" (the existing reference cels).** The collision is real and is in the code:
   `CanvasManager.interpolationReferences` is documented as *"the cels the artist has flagged as
   keyframes"* and groups them into `interpolationKeyframes` (`Models/CanvasManager.swift:114-119`).
9. **Bake is destructive and undoable.** The animated cel is replaced by the baked one-frame cels and
   the animation is gone, in one undo step. Consistent with Commit, which is one-way by design
   (`InterpolationEvaluator.flattened`) — and the reason to bake is to hand-edit the in-betweens, so a
   live rig underneath them would be a lie. **Bake is an authoring feature and never a performance
   instruction** — see §2.19 and §4.6.
10. **Every channel carries a step**: 1 = every frame, 2 = on twos, 3 = on threes. The curve is
    evaluated and then held. This is Blender's Stepped modifier and it exists because ink drawn on twos
    beside a perfectly smooth 24 fps camera move reads as CG.
11. **Membership is a named animation group, and there is no conflict prompt.** An object carries an
    `animationGroupID` the way a stroke already carries a `motionGroupID`. "Already animated" means
    "already in group A", shown in the channel list and reassignable by a tap. The brief's *"a prompt
    probably will be thrown so the user decides to remove the objects out of the previous one"* is
    superseded.
12. **A transform layer resamples raster content below it and re-poses vector content below it** — each
    tier in its own currency. Accepted consequence: a raster layer softens under a push-in while the
    vector layer beside it stays sharp. That difference is inherent, not a defect to chase.
13. **The keyframe substrate ships before Distort; Distort follows immediately after.** Enabled by §2.14
    — see §3.3. Keyframes ship with Uniform and Freeform working and Distort still greyed exactly as it
    is today.
14. **A transform key stores a quad — four corners plus a box size — from day one.** One representation
    expresses Uniform, Freeform *and* Distort, so §2.13 costs no migration. `TextFrame`
    (`Engine/TextObject.swift:239`) is the shipped precedent: `size` + `corners` + `mode`, `Codable`,
    with the 3×3 **computed and never stored**.
15. **Two poses are interpolated through their factored form** — affine × pure-projective — not by
    lerping matrix entries and **not** by lerping corners. See §4.3 for why corner-lerp is not the safe
    alternative it looks like.
16. **Brush grain travels with the ink.** Each dab's grain value is baked when the stroke is drawn, so
    the texture is part of the mark. Accepted consequence: a stroke you Move keeps its grain instead of
    re-sampling, which is a visible change to how existing artwork behaves under Move.
17. **The graph editor is a drawer that grows the timeline upward**, sharing the timeline's frame ruler
    and playhead, so a curve sits literally above the frames it controls — not a popover and not a
    full-screen sheet.
18. **A derived in-between carries no object channels.** It has no stable elements to key: the display
    list is computed. This mirrors what already ships — Move is refused outright on an interpolated cel
    in two places (`Views/TopToolbar.swift:142-143`, `Models/CanvasManager+LassoMove.swift:916-922`).
    Layer-scoped channels (§2.4) are unaffected, because their target is not the cel.
19. **Smooth playback comes from a cache, not from baking.** The owner: *"I would like not having to
    bake into frames while keeping performance."* Animation stays live and editable; a playback cache
    makes it fast. §4.6.
20. **That cache is span-scoped, complete and eager — not a lazy per-frame LRU.** The owner: *"we store
    the two keyframes, plus the cached frames in between. Then when something changes, the stuff in
    between can be overwritten using the new keyframes once, before its stored again."* Adopted over the
    LRU this document first proposed, because an LRU thrashes invisibly — playback is smooth or not
    depending on what else happens to be resident — while a span either is cached or is not, and the UI
    can say which. Three amendments in §4.6: recompute **on settle**, cache the **composite**, and store
    it **outside the project package**.
21. **A folder's effect animates exactly as a layer's does.** 2026-08-29, closing §9.3.
    `LayerFolder.effect` is a second home for the same grade and it gets the same track, rather than
    being declared un-animatable in writing. It costs one more storage site and one more arm on the
    resolver; the alternative costs a slider that silently refuses to key, which nothing reveals until
    the artist reaches for it.
22. **The keyframe button lives in the timeline's own control strip**, beside play, fps and add-cel —
    not in the top toolbar. 2026-08-29. It writes at the playhead and §2.17's drawer grows upward out
    of the same timeline, so the button, the frames it writes onto and the curve it opens are all in
    one place. It is chrome and **not a `Tool`** — and not an `ActivePanel` case either. The shipped
    precedent is exact: onion skin, interpolate and loop are `@Published` flags on `CanvasManager` with
    buttons in that same strip (`AnimationTimeline.swift:406`, `:440`, `:455`), touching none of the
    `Tool` switches. **Note that strip is written out twice** — `collapsedBar` and `miniToolbar` — and a
    button added to one is invisible in the other.
23. **A channel that is already animated keys on every edit, in or out of Animate mode. Animate mode is
    only what creates the *first* curve.** 2026-08-29, and it is After Effects' rule. Stage 3a hit the
    hole and shipped this as an inference; the owner then chose it, and the reasoning is the part to
    keep, because it is what stops someone undoing it: once the settings bar reads the value resolved at
    the playhead, an edit that writes the *stored base* instead of a
    key springs straight back to the curve under the artist's finger. The alternative is not "edit the
    value", it is a **dead control**. So the choice was between keying and refusing, and refusing costs
    an 0.8 s hold every time an existing animation is adjusted.
    **Half superseded 2026-08-29 by §2.27.** The mode clause is void with the mode. **The first half is
    not superseded and is now load-bearing in a new way**: it is why the auto-key arm asks whether a
    channel has a *curve* rather than whether it is an *animation* by §2.27's stricter definition. A
    curve whose two keys hold equal values is not in the channel list and is still in force, so routing
    an edit on it to the stored base reproduces the dead control by a new door.
24. **A plain tap keys every channel that already has a curve, at its current value.** 2026-08-29 —
    the "hold this pose here" move, and one undo step for the whole tap rather than one per channel. When
    the target has no tracks at all the button is **dimmed but still hittable**, which is not a detail:
    a *disabled* control cannot be held either, and the hold is the only way into Animate mode, so
    disabling it on a fresh document would make the mode unreachable by the exact gesture that creates
    the first track. The tap is refused; the press lands.
    **Superseded 2026-08-29 by §2.26**, which moves placing a keyframe off this button entirely. **The
    behaviour survives inside `addKeyframe`** and is the whole of its step 3: every channel that already
    carries a curve takes a key at the new mark holding the value it *resolves* to there, or placing a
    mark lets every other animated channel drift straight through it. The dimming rule is void — nothing
    is refused now, because a bare mark is a legal thing to place on an untouched layer.
25. **The live per-frame cost of a *derived* frame is not held to the 24 fps budget. The prebake is what
    must play at 24 fps.** 2026-08-29, and it is the widest-reaching of these rulings because it decides
    how every future measurement on this path is read. Shown that engaging the compositor on an
    interpolation in-between costs +75.7 ms/frame, the owner: *"if we are planning for this feature, then
    it is okay for things to take more than 1/24th of a second, including in-betweens... if it prebakes
    and can play at 24fps after, then the original ask is covered."* The "feature" is background baking —
    ROADMAP §5b, asked for the same day, unscheduled, and **already specified twice** (§4.6 here and
    LAYER_COMPOSITING §9.2). So a derived frame is allowed to be expensive to *compute*; what must be
    cheap is *replaying* it. One door stayed open — *"if a smarter faster way is possible which doesnt
    require a lot of code, then sure"* — which is a standing preference for cheap wins, not a reopening.
    **The corollary is the part to keep**: a frame-time figure on this path is evidence about the bake,
    not about playback, and a future reader who finds a 100 ms frame here should not "fix" it without
    reading this.
26. **A keyframe is placed from the cel menu, and the timeline button opens the graph editor. Animate
    mode is removed.** 2026-08-29, and it is the owner reversing §2.1 on sight of the built mode:

    > "I'm not sure if I like the animation mode. Just make it this workflow: select on cel, tap again,
    > tap add keyframe icon in the menu, everything gets saved at that point. Then select another frame,
    > edit sliders etc, tap add keyframe again and the new keyframe data at that frame is saved. When
    > tapping the keyframe button it brings up the list of things being animated and graph editor instead
    > of placing a keyframe (icon and its name also may have to be changed to graph editor). This means
    > removing the current keyframe mode UI. This means that animations will be added to the list when
    > two keyframes are placed, and something changes in one keyframe which from the other."

    **A keyframe is therefore a bare mark in time that acquires channels lazily** — `keyframeMarks` on
    the layer and on the folder, sorted, unique, absolute document frames, beside `effectTracks` and in
    §2.4's time base. A mark with no channel is legal and is the point. It cannot be derived from the
    curves in either direction: a curve carries keys the artist never marked (an auto-key, a seeded
    neighbour) and a mark carries no key at all until something changes.

    **The last sentence is a second ruling wearing the same paragraph**: what appears in the channel list
    is a channel with **two or more keys whose values are not all equal**. That is strictly narrower than
    "has a curve", and §2.23's surviving half is why the two must not be merged.
27. **Nothing is saved when a keyframe is placed; the previous value is held, and the *next* keyframe
    commits it.** 2026-08-29, the owner's own architecture, given when asked what "everything gets saved"
    means:

    > "keyframe A is added, nothing is saved. A slider or something is then adjusted. The previous value
    > is held. Then keyframe B is added. That previous value gets saved to A and the new value gets saved
    > to B and the held value is discarded. Thus, A and B are assigned the two states of that one
    > animation. Then the user modifies another slider while on B. The previous value of that other
    > slider goes to A, and the current saves to B. Now there are two animations, and each of the
    > keyframes store the values of both, without having to store every single number on the layer, only
    > the things which change."

    And, on what a slider edit does once a channel is animated:

    > "if the current frame is a keyframe, then the value gets updated on that keyframe. If it isnt a
    > current keyframe the drag creates a keyframe at that frame. This only happens when the value is
    > already being animated (2 keyframes plus the thing being animated changes between those two
    > frames)."

    **Three consequences that are decisions rather than transcription.**

    - **The held value is stored on the document (`pendingBaselines`) and persisted**, because the gap
      between A and B can span a save. Lose it across a reopen and placing B writes two identical keys
      and produces no animation — a wrong result with nothing on screen to explain it.
    - **The edit still writes the stored base, exactly as it always did.** The owner's description reads
      as though a slider goes provisional once a mark exists; it must not. A provisional edit that is
      never committed is lost work, and a slider that means two different things depending on invisible
      state is worse than either. The baseline is recorded *beside* the ordinary write, not instead of it.
    - **"Modifies another slider while on B" is its own arm** — seed the old value onto the neighbouring
      mark and key the new one here, in one write — because standing on B there is no third keyframe
      press coming to commit a baseline. It needs a *neighbouring* mark to exist: with one mark and the
      playhead on it, seeding would pin the new value in a one-key curve and lose the old one, so the
      answer there is to hold the baseline and let B commit it. That is the owner's canonical story and
      the reason the rule counts marks rather than asking whether any exist.
28. **A keyframe is any frame the target marks explicitly *or* any of its channels holds a key on.**
    2026-08-29, and it is not a preference — it is the invariant two bug reports off the owner's iPad
    turned out to be the same defect of:

    > "1. if i have two keyframes and then put one keyframe in between them and then select on the
    > middle keyframe, there is no delete keyframe"

    > "2. lets say i have an effect where there are two sliders. I have 3 keyframes and only slider A is
    > being controlled right now. Then I go to keyframe 3 (the last one) and modify slider B. It starts
    > from keyframe 1 to 3, skipping 2. It should start at keyframe 2, ending at keyframe 3"

    The middle keyframe in both stories was placed by *moving a slider*, which §2.26 already says a
    curve records and no mark does: the auto-key arm writes a key and nothing else. The timeline drew
    the union of marks and curve keys and every model question asked the marks alone, so a frame could
    be a keyframe on screen and not one to the code. Report 1 is `hasKeyframe` answering no and the cel
    menu withholding Remove Keyframe; report 2 is the seed arm's *nearest keyframe below* stepping over
    it to the one before. One divergence, two symptoms, and neither is reachable if the two lists are
    never asked separately.

    **The union is computed, never stored, and that is the load-bearing half.** Making every key write
    append a mark as well would put the same fact in two places and let it drift again the first time a
    writer forgot — which is the defect, not the fix. So `keyframeMarks` keeps its narrow meaning, the
    frames the artist marked *explicitly*, which is what makes §2.27's "keyframe A is added, nothing is
    saved" storable at all; it just stops being the whole answer. `CanvasManager.keyframes(of:)` is the
    one accessor, and `TimelineKeyMarkers` no longer computes a union of its own — it is handed the
    frames and told which carry a key, which is all it ever needed to draw bare against landed.

    **Two consequences worth keeping.** A grade that is not in force contributes no curves — a track
    left on a layer by a kind change is storage, so it draws no diamond and offers no Remove Keyframe,
    while its marks stand, because a mark is a point in time rather than a property of an effect. And
    `addKeyframe` still records the explicit mark on a frame a channel already keys: a key is a value
    some channel holds and a mark is the artist saying *this frame is a keyframe*, and the two come
    apart the moment that key is dragged or deleted in the graph editor.

---

## 3. The model

### 3.1 Two time bases, each obviously right for its target

| channel target | stored where | time base | why |
|---|---|---|---|
| an object / animation group in a cel | on the **cel** | **cel-local frames** (offset from `startFrame`) | it rides the cel through move, split, duplicate and paste for free — the same argument `motionGroupID`'s doc makes for a field over a side table |
| a layer or folder (effect params, opacity, a transform layer's pose) | on the **layer** | **absolute document frames** | §2.4. Its target has no cel to ride |

There is no third notion and no fractional document time. `activeCelIndex(inLayer:atFrame:)`
(`Models/CanvasManager+Timeline.swift:12-15`) is the chokepoint every drawing path already funnels
through, and it is where cel-local time is resolved.

**Eleven cel operations each owe an answer** and none of them can be evidence of correct behaviour
today, because there is no keyframe data for them to touch: `addCel`, `duplicateCel`, `pasteCel`,
`deleteCel`, `extendCelToEnd`, `clearCel`, `resizeCelLeftEdge`, `resizeCelRightEdge`, `moveCel`,
`splitCel`, `addBlankCelAfter` (all in `CanvasManager+Timeline.swift`). The two that need a real rule
rather than "it falls out of cel-local time":

- **`splitCel`** — keys before the cut go left, keys after go right, and **a key is inserted at the cut
  in both** so the value is continuous across it.
- **`resizeCelRightEdge` / `resizeCelLeftEdge`** — keys keep their cel-local frame and are **clamped,
  not rescaled**. Rescaling would retime an animation as a side effect of dragging a cel edge, which no
  artist expects. A key pushed outside the new span is held, not deleted, so shrinking and re-growing a
  cel is lossless.

### 3.2 The curve

A new `AnimationCurve` type: an ordered list of keys, each `{ frame, value, inHandle, outHandle,
tangentMode }`, plus a per-channel `step` (§2.10) and an interpolation mode **per segment**, carried on
the key that begins it — which is how Blender stores it, and it is what lets one hold sit between two
eases.

**`SpacingCurve` is not this type and must not be widened into it.** It is a *time remap*: `eased(t)`
returns a new `t` fed to lattice deformation, its input is clamped to 0…1
(`Models/InterpolationRecipe.swift:74`), monotonicity is enforced in two separate places on purpose
(`Engine/GuidePath.swift:376-378`, `:387-392`) because a dipping curve runs an in-between backwards
mid-scrub, and both ends are pinned. Reusing it for bloom intensity silently imposes all three, and
**overshoot — the thing a bezier graph editor exists to give you — is structurally excluded.**

What *is* reused: `CurveEditor`'s gesture grammar verbatim (`Views/EffectSection.swift:665-885` —
`DragGesture(minimumDistance: 0)`, `hitRadius` 22 pt, `tapSlop` 5 pt, drag moves / tap-on-handle deletes
/ tap-on-empty adds, and its `Self.encode(points)` accessibility-value convention that the UI suite
reads); and `SpacingChart`'s **write-back discipline** — begin/drag/commit as one undo bracket, and a
chart that is a *view* of whichever curve is in force rather than a second store
(`Models/CanvasManager+Interpolation.swift:1544-1566`). Those three rules are what keep the existing
timing UI from creeping, and they are worth more than the widget.

**One-way bridge, offered not required**: an `AnimationCurve` can emit a `SpacingCurve.sampled`, so the
graph editor could drive an interpolation span's easing. Never the reverse.

### 3.3 The pose is a quad

§2.14. `Quad` (`Engine/Deform/Quad.swift:18`) exists with `isConvex`, `isSimple`, `isParallelogram` and
`mapped(by:)`, and `Homography` (`Engine/Deform/Homography.swift:31`) is a finished projective solver —
Heckbert closed form, exact `inverse`, an exact `affine()` decision, `linearised(at:)`, `localScale(at:)`
and `isValidQuad` — with 27 headless tests across `HomographyLogicTests` and
`WarpAgreementCharacterizationTests`. **`Quad` is `Equatable` but not `Codable`** and has no lerp; both
are needed.

**Why not the six-scalar pose the Move tool uses today.** `ObjectTransformFrame` is `position` +
`scale` + `rotation` + `aspect` + `stretchAxis`, and LASSO_MOVE.md §5.20 already establishes that those
six *are* a general affine *"with nothing left over for a later stage to invent"* and that it
*"stops well short of stage 5's Distort, which is a homography and needs 8"*. Storing six would force a
migration the day Distort lands. Storing a quad costs nothing extra now and none later.

**Trap, and it has a pinned test.** `boxAngle` and `stretchAxis` are opposites —
*"boxAngle draws and never maps, stretchAxis maps and never draws"* (`ObjectTransformFrame.swift:22-26`),
pinned by `testANonZeroBoxAngleChangesNoSampleAndNoPixel`. A channel list that offers "rotation of the
box" and stores `boxAngle` animates a value that reaches no geometry at all.

### 3.4 Animation groups

`AnimationGroup` mirrors `MotionGroup` exactly: a document-level identity carrying **no geometry** — id,
display name, tag colour — persisted in the manifest, with membership as an `animationGroupID: UUID?`
**field on the element**. That split is the codebase's own settled shape: `MotionGroup` is identity,
`MotionGroupBinding` inside the recipe is the geometry, and `motionGroupID`'s doc gives the reason for
the field — *"so it survives copy/duplicate/split/undo automatically and a cut piece keeps its parent's
tag"* (`Engine/VectorLayer.swift:52-54`).

**That reason is load-bearing here and not merely tidy.** Element ids **do not survive a lasso lift** —
the split mints fresh UUIDs on both pieces (`VectorLayer.swift:1146`, `:1234`) — so a channel keyed to
raw element ids is orphaned the moment the artist re-lassoes. A field is the only thing that survives.

**It must go on every element kind, not just strokes.** `motionGroupID` today is on `VectorStroke` and
`VectorTextElement` only, so fills and placed images ride the recipe's first binding and cannot be
tinted by the group overlay — VECTOR_INTERPOLATION.md items 11/41 already ask for this to be fixed.
Doing it once serves both features.

### 3.5 Persistence

- **The track sidecar.** A cel's animation goes in its own file beside the interpolation recipe, named
  from a new **optional** `CelManifest.animationFileName`, exactly as `interpolationFileName` works
  (`Models/ProjectManifest.swift:373-375`, written only when non-nil at
  `Services/ProjectStore.swift:829-838`). The stated reason applies verbatim: `manifest.json` is read in
  full for every gallery tile, so bulky per-cel data does not belong in it. A missing or unreadable
  sidecar costs the link, not the drawing.
- **Add it to the validator on day one.** `ProjectBackupManager.ManifestSkeleton.Cel`
  (`Services/ProjectBackupManager.swift:466-477`) checks the raster, fill, baked and vector files but
  **never `interpolationFileName`** — a cel whose recipe sidecar is missing still validates and the
  atomic save proceeds. That is a real, existing, silent gap. Do not inherit it: add
  `animationFileName` to the skeleton in the same commit that adds it to the manifest, and consider
  fixing `interpolationFileName` while the file is open.
- **Layer-scoped tracks** (§2.4) go on `LayerManifest` beside `effect`, optional, written only when
  present — the format is versioned by field presence, not by a number, and every persisted field in
  the tree follows that idiom. **§2.26's `keyframeMarks` and §2.27's `pendingBaselines` join them
  there and on `FolderManifest`, same idiom, same absence-is-the-migration.** The baseline is the one
  that looks like a transient and is not: it is the state *between* keyframe A and keyframe B, and
  that gap can span a save.
- **A track outlives the effect it was written for, deliberately.** Key `bloom.intensity`, then switch
  the layer to a blur: the track is **kept and inert**. Inert falls out of evaluation walking the
  *effect's* descriptors rather than the track dictionary, and ids are `"<case>.<field>"`, so
  `blur.radius` and `bloom.radius` cannot collide. Kept rather than pruned on `Layer.valueFill`'s own
  asymmetry — a picker that silently destroys the other mode's setting is what a picker must not do —
  so flipping back restores the animation.
- **Precision.** Keys are `Double`. Do **not** route a pose through `PackedSampleRun`: its Int16
  quarter-pixel grid **saturates rather than throwing** (`Engine/ShapeGeometry.swift:783-791`), which for
  a handful of anchor values would silently teleport an out-of-range key. That encoding is tuned for
  thousands of samples a stroke; a key wants exactness over compactness.

---

## 4. Evaluation and rendering

### 4.1 `renderTree(atFrame:)` — the one structural change, and it is small

`renderTree` is a computed var with a single private producer (`Models/RenderTree.swift:751-761`,
recursing at `:832`). The effect is read at `:784` (`layer.layerEffect`) and `:891` (`folder.effect`),
**where the frame is not in scope** — so §2.4 forces the tree to become a function of the frame. That is
the whole cost, and it is six production call sites, five of which already hold a frame.

**Invalidation is free.** `SandwichKey` (`Views/CanvasView.swift:1398-1421`) and `SandwichFullKey`
(`Engine/RenderRequest.swift:462-494`) each already carry the resolved `[RenderNode]` **and** the frame,
`RenderNode` is `Equatable`, and its `effect` field is compared verbatim. A per-frame-resolved effect
moves the key with no new plumbing.

**The template already exists and says so.** `ValueFill.resolvedColor(atFrame:)`
(`Models/Layer.swift:203`) is `{ color }` today, and its doc comment cut this seam deliberately:
*"a keyframe phase would then have to cut this seam under a deadline instead of finding it already
cut."* `Effect.resolved(atFrame:)` is the same shape one level over.

**The cache that actually moves is not the one it looks like.** `SandwichKey` and `SandwichFullKey`
both carry `frame` outright, so two keys at two frames differ *whatever* the tree says — a test that
compares them across frames passes on unmodified `main` and proves nothing. Pin it by holding `frame`
**equal** and deriving the tree at two different frames. And the cache where staleness would actually
bite is **`MaskResolver`'s**, which is keyed on `LayerContentVersion` and carries neither the frame nor
the tree: it moves only because stage 0 put the frame-resolved effect *into* the version. Do not remove
that, or a grade that reshapes alpha will serve stale coverage. (Note `LayerContentVersion.hash(into:)`
deliberately omits `effect` while `==` includes it — legal, and it only costs collisions.)

**And `MaskResolver`'s key had a second hole, on the folder side, which stage 2b closed.** Those
per-layer versions are gathered from `stack.leafLayerIndices`, and a *folder* is not a leaf — so a mask
naming a graded folder went on serving the coverage it resolved under the old grade. That was true
before any of this and was filed in the file as a KNOWN GAP; §2.21 is what made it bite every frame
instead of once per edit. The key now also carries the node grades in the mask stacks
(`MaskResolver.nodeEffects(readBy:of:)`).

**One thing §2.4 did not cover, now ruled and built, and one nobody has.** `LayerFolder.effect`
(`Models/LayerFolder.swift:73`) is a second effect home reached at `RenderTree.swift:891`, and §2.21
gives it the same track a layer's effect gets — stage 2b. And
`CanvasManager.compositorSizeGate` (`CanvasManager+Document.swift:546-550`) is frame-invariant **only
for as long as a key cannot turn an effect on or off**; it counts `effect != nil`, so the day a track
can add one, the resize dialog's admission gate becomes a function of the playhead and will answer for
one frame about a document that dies on another.

### 4.2 Posed ink: bake the dab walk in rest space

**This is the load-bearing engine idea and it makes posing cheaper than today, not dearer.**

**How big is the risk really? Smaller than this section sizes it — for now.** §9 asked whether the
in-betweens the interpolation evaluator already generates visibly boil, since it re-walks the dab lattice
per in-between under a non-uniform map, which is the exact artifact. Checked on the device, 2026-08-29,
against a build of `main`. The owner: *"the interpolation shimmer seems fine for now, I can't notice it...
It may possibly be a bigger concern once the planned import brush feature comes out with custom brushes,
but if it does I'll let you know by then, so disregard for now."* So the rest-space bake is still the
right construction and still buys the per-sample-width result, but it is **not** rescuing a visible defect
and must not be scheduled as though it were. **INFERRED, and the owner's instinct about why**: every dab
that ships today is a circle (`RasterLayerTexture.stampCircle` is the whole drawing surface — see
[BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md)), and small per-frame differences in a
circle's centre and radius are close to invisible. An imported `.ABR` or Procreate brush is a **stamp
image** with orientation and internal texture, where the same jitter becomes texture crawl. That is the
same mechanism §2.16 rules on for grain, and it means **this risk is coupled to the brush-import feature
rather than to time**.

Today a mapped stroke re-walks the dab lattice in destination space, so the dab count and phase are
re-derived per frame. At 24 fps that is the shimmer everyone fears. The fix is to bake the walk **once
in rest space** and then, per frame, map each dab's **centre** through the pose and scale its **radius**
by the pose's local area root. Dab count, phase and the seeded `DabRNG` become invariant across the
whole animation *by construction*. The per-frame walk arithmetic disappears, leaving four multiplies and
four adds per dab.

**This is not an invention — the tree already does it one level down.** `DabLattice`
(`Engine/VectorLayer.swift:82-126`) stores a cut piece's *parent's whole walk* and filters it, and
`BrushStamper.swift:144-162` states the rule to generalise: *"a filter over the original walk, not a
re-derivation"*, with its acceptance test asserted at zero tolerance. Generalising "the walk that
defines the lattice" from a cut parent to a rest pose is a small, well-precedented change. What is
missing is a `DabTarget` that **collects** instead of drawing — structurally identical to the existing
`DiscardedDabTarget` (`BrushStamper.swift:303-310`) — plus a replay entry point taking a point map.

**And it dissolves the per-sample-width problem completely.** LASSO_MOVE.md §5.17 settles that ink
scales by `sqrt(|det|)`, the map's own area root, *"not by one axis, and not by nothing"*, chosen because
for a similarity `sqrt(|det|)` *is* `k` and so **Freeform contains Uniform** rather than sitting beside
it. `Homography.localScale(at:)` (`Deform/Homography.swift:266-269`) is the *local* area root — the
sqrt of the Jacobian determinant — and reduces exactly to `sqrt(|det|)` for an affine and to `k` for a
similarity. So each dab's width comes from the pose at render time. **No per-sample width, no
`VectorSample` change, no wire-format change, no decode migration** — which was supposed to be the
expensive half of vector Distort.

**Build the pose as a point map, not a `CGAffineTransform`.** `drawn(_:through:widthScale:)`
(`VectorLayer.swift:2262`) and every CTM seam take an affine and cannot hold a homography; `CGContext`
has no projective CTM at all. One evaluator over `Homography.map` + `localScale(at:)` serves Uniform,
Freeform and Distort. Three separate arms do not.

**Do not implement §2.3 by concatenating the pose onto the CTM before stamping.** It is one line and it
would fix LAYER_TRANSFORM.md's defects A and B at once — but `drawRadialGradient` draws in user space,
so it turns every round dab into an ellipse, contradicting the shipped ink-keeps-its-shape default of
2026-08-26. The CTM route is the correct implementation of the *opposite* toggle setting.

**Three artifacts, named honestly.**

- **Grain is the real one** — §2.16. It is an absolute canvas-position noise field sampled at the
  *posed* stamp point (`BrushStamper.swift:250`, `:269-273`). `VectorLayer.swift:2075-2077` dismisses
  re-sampling as "no regression" because it already happens under a plain translation; that reasoning
  holds for a one-off Move and fails completely at 24 fps. **The baked dab record carries the
  multiplier, not the position.**
- **Square and custom brush shapes** re-derive a sub-dab grid from the posed diameter with 1 pt floors
  (`BrushStamper.swift:275-294`), so they shimmer while the five round built-ins do not, unless their
  sub-lattice is baked too.
- **Under Distort a dab is drawn as a circle at the local scale**, not the true projected ellipse — a
  sub-pixel error at reasonable distorts, and the same approximation `TextLayout.warpSourceScale`
  already makes.

**Two tiers, and the house pattern already exists.** During a scrub or a recorded drag, drive
`floatView`'s `UIView.transform` — PERFORMANCE.md:209-212 records that taking a Move drag onto that path
went from 96.1–107.8 ms a sample to **0.002 ms** — and accept the nearest-neighbour magnify. Re-stamp
crisply on the settled frame and at bake. §2.5's "the key is written at commit, not on every nudge"
points at the same seam, so the ruling and the performance pattern agree.

### 4.3 Interpolating two poses

§2.15. **Corner-lerp is not the safe alternative to matrix-lerp — it fails the same way.**
`DeformFactorization.swift:56` already warns that lerping matrix entries collapses a rotating arm to a
line at `t = 0.5` and re-expands; a vertex-wise lerp of two quads has the identical defect, because the
blended edge cross product goes negative when the two poses differ by a large rotation. **Convexity is
not preserved by corner lerp, so an in-between can be invalid between two valid keys.**

The construction: factor each pose as **affine × pure-projective**; interpolate the affine part through
the project's own `Matrix2x2.polar` / `interpolatedFromIdentity`
(`Engine/Deform/DeformFactorization.swift:62`, `:80`) with `ARAPInterpolation`'s angle unwrapping; lerp
the perspective row, which is small and well-behaved; recompose.

**That is not a guarantee, so a fallback is owed.** `Homography.isValidQuad` today is a *drag* clamp
whose failure mode is *"the handle feels like it sticks"* (`Homography.swift:310-312`) — a scrubbed
in-between has no finger to stick. **Open, §9.1.**

### 4.4 The transformation layer

§2.3 and §2.12. It is **not** a blend mode and cannot be: all 25 modes are per-channel colour functions
over two same-size, same-position images, with no positional argument anywhere in either backend's call
chain. It is an **arity-1 `CompositorOp`**, the shape the existing effect node already takes. §2.6's
relabelled menu is what makes that invisible to the artist — the value layer's menu already merges blend
modes and effects into one list, so a third kind of entry there is consistent with what ships.

**Scope is already defined and reusable verbatim**: a value layer with an effect grades *"everything
beneath it inside its own container"*. A transform layer uses the same rule.

**Where the pose is applied.** `renderNodes(atFrame:inContainer:)` accumulates a `Homography` down each
container using the same `below` / `containerIsNode` scope machinery it already has, and emits
`[layerIndex: Homography]` alongside the tree; `renderSources` maps the cel's elements through it and
hands the posed display list to `renderLocalContent(elements:)`. **Ink is stamped at the posed position
— it is never resampled afterwards.** Injecting at `VectorCanvas.render()`'s existing
`ctx.concatenate(_transform)` (`VectorLayer.swift:2916-2919`) is the one-line change any reader will
reach for and it is exactly LAYER_TRANSFORM.md's defect B — a bitmap magnify of an already-stamped
canvas — plus defect A, because `renderLocalContent` allocates a context of exactly `size` in local
space and clips ink the pose moves outward.

**A pose is not scoped by a buffer the way an effect is.** An effect's containment is enforced at
composite time by `needsOwnBuffer` / `isIsolated`. A pose applied at rasterisation has no buffer to be
bounded by, so the scope must be computed structurally in `renderNodes` and carried per layer index —
get it wrong and the pose silently leaves its folder with nothing downstream to stop it.

**Two placed-object refusals ride along.** `mapping(_:throughStretch:)` `assertionFailure`s on a placed
image (`VectorLayer.swift:2247`) and `canBeStretched` returns false for `.image` — so a transform layer
over a cel holding a photo trips an assert in debug and silently leaves the photo behind in release,
while the strokes around it move. That is Move stage 3c's gate
(`VectorImageElement.transform` is a `LayerTransform` with nowhere for a second axis), and it must be
refused out loud here rather than left to assert.

### 4.5 The caching trap — pin this on day one

An animated pose defeats `PixelOps.rasterize`'s flatten memo for every leaf beneath it, on every frame.
Neither `PixelOps.RasterizeKey` nor `LayerContentVersion` has a pose field.

**The failure is invisible in the obvious place.** `SandwichKey` compares the whole `[RenderNode]`, so
adding a pose to `RenderNode` invalidates the *sandwich* automatically — the composite dutifully
rebuilds, **from `rasterize`'s cached un-posed image.** Green tests, wrong pixels, and no key that looks
wrong. Both keys need the pose, and a test needs to pin it.

**The honest cost, and it splits sharply by blast radius.** *(INFERRED, arithmetic over MEASURED
components.)* Playback already re-composites every frame — the frame is in the cache key — so ~21 ms of
composite is the *existing* cost of pressing play, not something animation adds. What animation adds is
the defeated flatten, and how much of it depends entirely on how many leaves the pose reaches:

| what is animated | leaves whose flatten is invalidated | added cost per frame |
|---|---|---|
| one object, or a group, inside one cel | **one** | ~4 ms — **fits 24 fps with no cache at all** |
| a transformation layer over a six-layer container | **six** | ~22 ms — 43 ms total against a 41.7 ms budget, i.e. it misses |

So **per-object animation is not a performance problem and must not be designed as though it were.** The
transformation layer is, and §4.6 is its answer.

### 4.6 The playback cache — and why Bake is not the performance answer

**Owner's ruling, 2026-08-28**, and it corrects an earlier framing in this document:

> "if bake into frames is able to speed up the transformations, is it possible to automatically cache
> the transformations as baked so that they dont need to be recalculated every frame? Because I would
> like not having to bake into frames while keeping performance."

**Bake is an authoring feature, not an optimisation.** You bake when you want to *draw on* the
in-betweens. Nobody should ever be told to bake to get a smooth preview, and §6 is written for the first
reason only.

**The shape is the owner's, §2.20: span-scoped, complete and eager.** The frames between two animation
keys are computed as a unit, kept as a unit, and recomputed as a unit when anything they depend on
moves. This was chosen over a lazy per-frame LRU for a reason that is about the artist rather than the
machine: an LRU's hit rate is invisible, so playback is smooth or stuttery depending on what else is
resident, whereas a span is either cached or not and the timeline can show it. It also removes the
"first pass is always uncached" concession, which is what the owner objected to.

**Amendment 1 — "once" means *on settle*, not *on change*.** A span recomputed on every touch-move of a
curve handle recomputes sixty times a second. While a gesture is live, fall back to the live path (fast
for per-object work — §4.5); recompute when it commits, after an idle delay, cancellably.

**The app has exactly one precedent for this and it is a good one**: thumbnail regeneration is a Combine
`.debounce(for: .milliseconds(400), scheduler: RunLoop.main)` where the *payload* travels separately in
an accumulating `pendingThumbnailRegens: Set<CelLocation>` (`Models/CanvasManager.swift:966-981`,
`:1449-1461`) — so the debounce coalesces the timing while the set loses nothing, and ids are resolved
back to indices at drain time so a reorder or a delete in the window is survivable. It also keeps an
explicit **non-debounced** escape hatch for load and canvas resize (`regenerateAllThumbnails()`), on the
argument that queueing there "would only defer the same work by 400 ms while leaving the timeline
blank". A span cache wants all three properties. Nothing else in the app debounces a recompute — the
other `asyncAfter` sites are gesture disambiguation and fade timing.

**Amendment 2 — cache the composite, not the per-layer flattens.** The owner's "the cached frames in
between" means the *pictures*, and that is the cheaper unit by roughly the layer count: one image per
frame rather than one per layer per frame.

*MEASURED*: a canvas texture is 16.8 MB at 2048² (`Engine/MetalCompositor.swift:212`), and
PERFORMANCE.md's "six canvas-sized textures are 48 MiB at 2048×1024" gives **8 MiB a frame at the
owner's own working size**. At the 50% Render Resolution the app already ships that is **2 MiB a frame**.
So a 48-frame span is **384 MiB full-res and 96 MiB at half**.

**And it must key on `RenderResolution`.** `SandwichKey` and `SandwichFullKey` already do
(`Views/CanvasView.swift:1410`, `Engine/RenderRequest.swift:467`) and their comments say why in the words
to reuse: otherwise the setting becomes *"a control that visibly does nothing when you use it"*. Note
also what that setting actually reaches — **only `makeSandwichRequests`, the on-screen live composite**
(`RenderRequest.swift:195-199`). It does not scale the flatten, the thumbnail, the saved package or a
future export, and the Actions menu promises the artist exactly that. A preview-resolution span cache is
therefore consistent with what the control already means; a full-resolution one is a different tier.

**Amendment 3 — "stored" must mean outside the `.paintproj`.** Three reasons and the first is decisive:
the save path re-encodes **every** cel on **every** save with no skip-unchanged path, at a MEASURED
15.2 ms/cel of which 95.6% is `pngData()`, so cached frames inside the package would tax every future
save of that document. Second, `ProjectBackupManager.validateProject` gates the atomic swap on the files
the manifest names, so a large derived sidecar becomes a new way for a save to be refused. Third,
derived data living in the document is a class of problem this repo already has and wants out —
`fillImage` and `bakedImage` are the cautionary tale, and VECTOR_INTERPOLATION item 26 records that the
owner wants vector fully divorced from raster features. A cache that can be deleted at any moment by
anyone with zero loss is the only kind worth having.

**Two findings that change the cost, both from the 2026-08-28 survey.**

- **There is no multi-frame composite cache to extend — this is new machinery.** The sandwich holds
  **exactly one generation** (three canvas-sized images in `sandwichImages`, `CanvasView.swift:1128`),
  overwritten on every rebuild and **dropped entirely on disengage**, with the comment that names the
  principle: *"an address for pixels that have been released is not a cache"*
  (`CanvasView.swift:1500-1501`). There is no dictionary, no LRU and no count budget behind it.
- **Memory alone cannot hold a span, so the disk tier is required rather than nice to have.** The house
  rule for a large budget is `physicalMemory / 16` clamped to [64 MiB, 768 MiB] — **192 MiB on the
  owner's iPad 9** — and three budgets share that one function, pinned equal by
  `MemoryBudgetLogicTests.testTheThreeLargeBudgetsRunOnOneRule`. But that 192 MiB is already spent: it is
  the compositor's texture pool *and* `PixelOps.rasterizeCache`'s budget. A feature-scoped budget takes
  the other shape in the house table — a flat literal justified as a property of the frame rather than of
  the device, as `OnionSkinBudget.residentBudgetBytes` is at 64 MiB. **At 2 MiB a frame that is 32
  frames, about 1.3 seconds.** A 48-frame span does not fit.

**Where the disk tier lives is a genuine departure and should be taken knowingly.** The app has **no
on-disk derived-data store of any kind** — no `Library/Caches`, no temporary directory, not one hit.
Its only "outside the package" precedent is `ProjectBackupManager`'s named sibling folders under
`Documents/` (`Projects/`, `Backups/`, `Trash/`), app-managed, rotated by count with a 1 GB global cap
and purged at launch, never on a low-disk signal. **INFERRED recommendation: use `Library/Caches`
anyway.** It is the platform's home for exactly this — evictable derived data, purged by the OS under
disk pressure, excluded from backup — and `Documents/` is backed up and counted against the artist's
storage, which is wrong for bytes whose whole contract is that losing them costs nothing. This is the
case where the platform convention should beat the local one, and it is the first time the app would
need one. Say so in the commit rather than letting it read as an oversight.

**Eviction is by whole span, least-recently-played.** The owner's model is otherwise unbounded, and a
300–1000 cel document can hold hundreds of animated spans. Span granularity is the better unit anyway:
a half-evicted span is useless, so keeping fragments buys nothing. Note that
`PixelOps.rasterizeCache` is **FIFO, not LRU**, 24 entries under the shared byte budget, and is cleared
wholesale on a memory warning and on backgrounding (`Services/PixelOps.swift:210-250`) — a span cache
should honour the same two signals.

**Invalidation is the hard part, and it is the same requirement either design had.** A cached span dies
when the ink changes, when the curve changes, when the layer's effect changes, and — for a
transformation layer — when *anything below it* changes. `LayerContentVersion` already propagates
exactly this kind of dependency, which is why LAYER_COMPOSITING §9.1 lists propagating content versions
as substrate to build now. Get it wrong and §4.5's trap is waiting: the composite rebuilds happily from
a stale flatten, with green tests and no key that looks wrong.

**Two limits to state in the UI rather than let someone discover.** A span is **uncached until it has
been computed once**, which after amendment 1 means "until the edit settles" rather than "until you have
played it" — better, but not free. And **editing a curve throws away that span**, so the cache helps
review rather than authoring.

**Scope, unchanged: per-object animation needs none of this** (§4.5 — it already fits inside 24 fps).
This is machinery for the transformation layer and, later, for export.

---

## 5. Recording

§2.1's Animate mode with a clock. One mechanism, two surfaces: a slider, and the Move box.

**Capture at the pencil's own rate and resample on stop. Never sample at 24 Hz.** A 24 Hz sample of a
shake **aliases** — a fast shake records as a slow wobble. The intake already carries what is needed:
`onStrokeMoved: ((VectorSample, TimeInterval) -> Void)` hands over `UITouch.timestamp`, the pen's own
hardware clock, at the full coalesced rate, and its doc comment explains why the timestamp rides beside
the sample rather than inside `VectorSample` (a Codable migration on the format's most numerous type).
For a slider, sample its continuous `set` closure (`Views/EffectSection.swift:409-432`) on the clock —
**not** `WindowEventTap`, which is debug-only, thinned to ~20 Hz by design, and **cannot identify a
SwiftUI control on a real iPad** because no accessibility client is attached (`WindowEventTap.swift:435-461`,
verified on device).

**Then decimate and simplify.** `GuidePath.spacingCurve(resolution:)` (`Engine/GuidePath.swift:166-196`)
is the template for the resample — walk evenly spaced output stops, read the raw recorded stream at each,
pin the ends, and return `.linear` when the duration is zero rather than reading noise as intent. Drive
the stop count from `fps` × recorded duration rather than its fixed 33. A tolerance-based simplify then
turns a 3-second shake from 72 keys a channel into something a graph editor can hold. **Note the
opposite precedent and why it does not apply**: VECTOR_INTERPOLATION §3 fact 13 rejected Douglas-Peucker
for *stroke geometry*, because two points bend as a straight line under a warp that should curve them.
A value curve has no warp; deviation-based simplification is the right family here.

**Slow motion is a capture-speed multiplier on the record control, not the document fps.** §2.7 makes
fps editable, but changing it to get slow-mo retimes everything else in the document. Note also that
`GuidePath.spacingCurve` **discards absolute duration entirely** (it normalises both axes and pins the
ends), so "lower fps = slow motion" does not fall out of the existing derivation — the recorder must keep
real time.

**Two prerequisites.** Playback's `isPlaying` / `playbackTimer` live as `@State` on the timeline **view**
(`Views/AnimationTimeline.swift:13-14`) and the timer just adds 1 per fire with no wall-clock
comparison, so it drifts. The recorder needs a model-level clock — which is the same prerequisite
ROADMAP item (4) names for audio, so it is worth doing once and properly. And an fps stepper that only
writes `canvasManager.fps` will **silently play at the old rate** until playback is stopped and
restarted, because `togglePlayback()` captures `1.0 / fps` once (`AnimationTimeline.swift:729`).

**Expect it to feel twitchy before it feels good.** VECTOR_INTERPOLATION §5 open call 1 says exactly that
of the velocity→easing mapping, which has *"never met a real stylus"*. Smoothing is part of this feature,
not polish on top of it.

---

## 6. Bake

§2.9. Destructive, undoable, one step. **It exists so the artist can draw on the in-betweens.**
It is not the answer to a slow preview and must never be offered as one — that is §4.6.

**Follow `bakePreciseStrokes` exactly** (`Models/CanvasManager+Document.swift:982-1049`): call
`commitAllInteractiveState()` first so a float under the artist's finger is not baked mid-motion; walk
and **collect** per-cel edits; mutate; register **one** `recordUndo` over all of them. Its own comment
states the reason — *"rather than registering per cel, which would cost the artist one press per cel to
take back a single menu tap."*

**Mint fresh element ids, unlike every existing copy path.** `VectorCanvas.makeCopy()` preserves element
UUIDs verbatim, which is deliberate and correct for `duplicateCel` (a motion-group tag should travel).
For a bake it is wrong: 48 cels whose elements share ids will alias anything keyed by id.

**Bake at the channel's step (§2.10), not always at 1.** A cel animated on twos bakes to 24 cels, not 48.

**Two costs to disclose, not hide.**

- **There is no batch cel-creation primitive.** Every path — `addCel`, `duplicateCel`, `pasteCel`,
  `splitCel`, `addBlankCelAfter` — creates exactly one cel per call. A bake loops one of them inside a
  single bracket, and `withInterpolationUndo` **silently no-ops its own bracket when re-entrant**
  (`guard structureUndoDepth == 0, gestureSnapshot == nil`), which the loop must rely on deliberately
  rather than trip over.
- **Save cost is permanent.** `ProjectStore` re-encodes every cel on every save with no
  skip-unchanged-cel path, at a MEASURED 15.2 ms/cel at 2048×1024, **95.6% of it `pngData()`**,
  parallelised across cores. Baking one cel into 48 raises the cost of every future save **for the life
  of the document**. Say so at the bake, with the number.

**A range bake is also (5)'s exporter.** ROADMAP §0 notes both are "evaluate the document at frame N,
N+1, … and emit one picture per frame", and that `makeRenderRequest` is already frame-parametric. Build
the frame-walker once.

---

## 7. The timing recorder

The laser-pointer tool. It is §5's recorder with no target channel: capture `[TimedSample]` from the
canvas, then draw a trail whose tail tapers from where the point was on the previous frame.

Both halves exist. Taper is `StrokeGeometry.stampRadius(forPressure:brush:size:)` plus the capsule chain
— substitute a decay-since-touch-down scalar for pressure. Cel creation is `addCel(layerIndex:startFrame:
frameCount:)`, already `withStructureUndo`-wrapped. **INFERRED**: the cleanest shape is an animated dot
with a position curve, so it *is* an instance of this feature rather than a special case, and the trail
is a render style; baking it then falls out of §6.

**It enters through the Actions menu, not the toolbar.** `.text` was routed through Actions because the
toolbar was full (`Models/Tool.swift:22-24`), and every switch over `Tool` is exhaustive with **no
`default:`** on purpose, because three past bugs shipped from someone adding a case and missing a
hand-maintained exclusion list (`Tool.swift:48-53`, `:78-104`). **But do not plan around a slot count.**
This document said "seven slots" and that was wrong twice over: `Tool` has **six** cases, and the number
at `Tool.swift:24` is a remark about the *toolbar*, which itself now ships **nine** controls
(`TopToolbar.swift:33-75`) after the adjust icon was removed. Count the cases before believing either.

---

## 8. Build order

Each stage is mergeable and leaves the app working.

| # | stage | notes |
|---|---|---|
| **0** ✅ | **`renderTree(atFrame:)`** — merged `654f863`. | Behaviour-neutral. Six production call sites, one recursion, ~60 fast-tier test references. Both §2.3 and §2.4 are blocked on it. Ship it alone so the frame-threading diff is not inside a diff that changes pixels. |
| **1** ✅ | **`AnimationCurve` + the effect descriptor table** — merged `c09ddf0`, `c6ecb49`, `6a379bf`. | The table is an exhaustive `switch self` with **no `default:`** — `Effect` cannot be `CaseIterable` and every existing all-effects sweep in the suite is a hand-typed literal, so a `default:` would silently miss a fourteenth effect. Make `EffectSettingsBar.rows` *read* the table so the two cannot drift; the 25 slider sites already carry range, format and target. |
| **2** ✅ | **One channel end to end: a layer effect parameter** — merged `4d55aae`. Continuous scalars only; the six stepped fields, the two array ones and `outline.color` are refused at the writer as well as the resolver, so the app cannot reach a track that stores and renders nothing. | `Effect.resolved(atFrame:)`, keys on the layer, absolute frames. Proves storage, evaluation, invalidation, undo, save/load. No new geometry. |
| **2b** ✅ | **The same channel on the other grade home: `LayerFolder.effect`** — §2.21. `effectTracks` on the folder, `resolvedEffect(atFrame:)` filled in, `setEffectParameterTrack(folderID:…)`, the optional `FolderManifest` key. Nothing in it is new machinery; the whole stage is the one arm §2.21 costs. | It also closed a **pre-existing** defect §4.1 had recorded as a KNOWN GAP: `MaskResolver`'s cache key is per-*layer* content versions and a folder is not a leaf, so a mask naming a graded folder served coverage resolved under the old grade. A hand edit hit it once; a track hits it every frame, which is what forced it. The key now carries the mask stacks' node grades. |
| **3a** ✅ | **The effect-parameter channel end to end, from the artist's side** — the settings bar reading the value **resolved at the playhead**, the keyframe writer that keys many channels as one undo step, and `KeyframeTarget` making §2.21's two grade homes one path. | Two findings the plan did not have. **Making the bar read the playhead is not one line** — the bar writes back a whole `Effect`, so one slider move would bake every other animated channel's resolved value into the stored base; it needs the resolved and stored grades side by side. And **a routing rule that a view holds is a rule the fast tier cannot see**, which is why the whole edit path is a `CanvasManager` method rather than a `switch` in a callback. This stage also shipped Animate mode, which §2.26 withdrew the same day; §2.1 carries what that cost and what it taught. |
| **3b** | **The keyframe marks, the channel panel and the graph-editor drawer** | §2.26 and §2.27. The **model** half is built: `keyframeMarks` and `pendingBaselines` on both grade homes, persisted by field presence; `addKeyframe` / `removeKeyframe` / `clearKeyframes`, one undo step each; and the five-arm routing rule. **The cel menu and the marks' timeline form are built too** — Add / Remove / Clear Keyframes on the block menu, addressing the tapped block's layer at the frame the request carries (the playhead, captured when the menu is raised, because playback does not stop for a menu); and `TimelineKeyMarkers.markers` is now the **union** of marks and curve keys, with a bare mark drawn hollow and a mixed run drawn landed. **The grade gates the curves and does not gate the marks** — a mark on an ungraded layer is where the workflow starts, so `TimelineLayoutKey` passes `[:]` for the tracks and the marks in full. What is left is the channel panel and the drawer. **Decide which shape each one is before writing it** — `CanvasPresentation` covers only presentations whose openness is held in a `Binding`, i.e. real `.popover`s, and one of those must add a case, an `overlapsLiveCanvas` arm, an entry in `CanvasPresentationLogicTests.expectedOverlapsLiveCanvas` and route through `.canvasPresentation` or it reproduces the stroke-teardown bug. An inline docked panel is **not** a presentation and adding a case for one would be wrong. An `ActivePanel` case is a third thing again, and breaks `CanvasTouchOwnerLogicTests`' hand-derived 1_920/440 constants — loudly, but they must be re-derived rather than bumped. **§10 carries what the drawer actually attaches to, and it is a constraint rather than a preference.** |
| **4** | **The rest-space dab bake + grain** | §4.2 and §2.16. Engine-only, testable in the fast tier, and `Engine/Deform` compiles standalone with `swiftc` in ~5 s. |
| **5** | **The transform channel** | Quad keys, animation groups, §2.5's write-at-commit, §4.3's factored interpolation. Uniform + Freeform. |
| **5b** | **Real Distort** | §2.13. **Moved here from the end of this table on 2026-08-29.** Raster tier first (the gesture is `TextFrameDrag.distortedFrame` and the bake is `ImageWarp`), then ink through §4.2's point map, then placed images behind Move stage 3c. |
| **6** | **Bake to cels** | §6. Shares its frame-walker with ROADMAP (5). |
| **6b** | **The playback cache** | §4.6. Only stage 8 actually needs it — per-object animation fits the budget without it — so it lands beside the transformation layer, not before it. |
| **7** | **Live recording + editable fps** | §5. Needs the playback clock hoisted onto the model first. |
| **8** | **The transformation layer** | §4.4. Late because §4.6's cache is its real cost, and because it is the only stage that needs one. |
| **10** | **The timing recorder** | §7. Small, sits on 7. |

**Why Distort moved, ruled 2026-08-29.** It sat last, which read as a dependency and was not one: Distort
needs the **transform channel and nothing else** — not bake, not the playback cache, not the
transformation layer — because §2.13's whole content is that a pose is a quad, which stage 5 stores from
day one precisely so this lands with no migration. Left at the end it would have waited on three stages it
does not use. Asked to schedule it, the owner delegated the call; the ordering above is that call, and the
stage numbers of 6 through 10 were left alone so that references to them elsewhere stay true. There is no
stage 9 now, deliberately.

**Stage 0's one prerequisite — the `ContentProvider` seam — is built.** ✅ Derived content used to be
invisible to `PixelOps.rasterize(cel:)`, so thumbnails, ordinary onion skin and the composite an export
walks saw an animated cel as **empty** (VECTOR_INTERPOLATION item 18). `PixelOps.rasterize` now takes a
`DerivedCelContent`, resolved from a passed-in `CelContentProvider` — not a back-reference from `Cel`.

**What stage 5 inherits, and what it still owes.** The provider is **frame-aware** already
(`CelContentProvider.frame`, rebindable with `at(_:)`), so a pose channel adds a derivation source and
touches no call site a second time. §4.5's trap is closed for both keys it names: `PixelOps.RasterizeKey`
and `LayerContentVersion` each carry `DerivedCelContent.identity`, and `CelContentProviderLogicTests`
pins both — the second by mutation. What stage 5 owes is the *identity*: a derivation builds its own,
beside the closure it belongs to, and a pose one must include the frame (interpolation's does not,
deliberately, because interpolation does not read it and a spurious frame field would mint a second
cache entry per frame of a held cel).

---

## 9. Open questions

1. **What does an invalid in-between pose do?** §4.3's factored blend makes validity much easier to
   preserve but does not guarantee it. Clamp to the last valid pose (never draws anything broken, can
   visibly stutter), or refuse the key pair when it is authored (predictable, needs a message, can
   refuse a pair that only fails for a few frames)? **Cheap now, expensive once keys are on disk.**
2. **A value layer below a transformation layer has two irreconcilable readings.** In flat-colour mode
   it is a full-canvas sheet, so posing it means posing a quad and leaving transparency outside —
   plausible. In *effect* mode it holds no pixels at all and grades the accumulator, so there is nothing
   to pose. Same layer kind, two answers.
3. **What happens to a curve whose two keys have different cardinality?** Two of the thirteen effects
   have variable-length parameter arrays — `Curves.points` and `GradientMap.stops`. Tweening a 3-point
   curve to a 5-point curve needs a definition or a refusal.
4. **Where does the playback cache's disk tier live, and do cached spans outlive the session?**
   §4.6 settles that a disk tier is required rather than optional — 64 MiB of memory is about 32 frames
   at preview resolution and a 48-frame span does not fit — and recommends `Library/Caches` over the
   `Documents/` sibling-folder pattern `ProjectBackupManager` established, knowingly departing from the
   only local precedent because the OS purges Caches under disk pressure and excludes it from backup.
   Unruled: whether a span survives a relaunch at all, and what sweeps it if the OS does not.

## 10. Traps inherited from elsewhere

- **The evaluation's input list is `InterpolatedCelIdentity`, and it is now the only one.**
  VECTOR_INTERPOLATION settled fact 11: *"It has bitten three times."* Omission is silent — the canvas
  shows a stale frame forever. As of 2026-08-29 `CanvasView.InterpolationPreviewKey` has **no field
  list of its own**: it is `DerivedCelContent.identity` plus the render quality, and that identity is
  minted from the same locals as the render thunk, so there is one list rather than two and they
  cannot drift. Adding an input to the evaluation means adding it to `InterpolatedCelIdentity`, in
  `CanvasManager.derivedCelContent`, twenty lines from the code that reads it;
  `CelContentProviderLogicTests.testEveryEvaluationInputMovesTheDerivationIdentity` is the sweep that
  fails when one is missed. **But the rule is narrower than it sounds, and stage 2 established where
  the line is**: that identity covers the in-between *drawing* evaluation — lattice and ARAP over
  vector geometry — so it binds **object** channels, which feed the evaluator. A layer-scoped grade is
  applied at composite time through `RenderNode.effect` and is not an input to it, so stage 2 owed the
  key nothing. Ask which side a new channel falls on rather than adding a field reflexively.
- ~~**The compositor comes off the live canvas whenever an in-between is under the playhead.**~~
  **Fixed 2026-08-29.** `isSandwichEngaged` used to return false if *any* layer's active cel carried a
  recipe, so blend modes, effects and mask clipping fell back to Core Animation for that frame, and an
  effect parameter animated near an interpolated cel was authored against a path where effects are
  off. The predicate is `CanvasManager.sandwichEngagesOnCanvas(tree:)` now and engages on in-betweens;
  what replaced the clause is a **gesture** one, `isScrubbingInterpolation`, because the `t` slider
  writes per tick. **Removing it needed a second change and that is the part worth remembering**:
  `SandwichKey`'s content versions carried no derivation, and `t` moves no version number, so the
  canvas would have engaged on an in-between and frozen on the first one it composited — §4.5's
  invisible failure, reached from a third door. Cost, MEASURED 2026-08-29 at 2048×1024: see
  PERFORMANCE.md §7.
- **0.8 s matches nothing that ships.** Every long-press in the app is 0.5 s (row and block reorder) or
  0.0 s (tool touch-down). It must be a real gesture recognizer — not a `.contextMenu`, which absorbs the
  whole touch, and never `UIDragInteraction`, which **XCUITest cannot drive at all** (verified;
  `Views/LayerStackListView.swift:13-18`). Keep it off any element that already carries a 0.5 s press:
  *"Two long presses of equal duration competing for one touch have no stable winner"*
  (`Views/MotionGroupRow.swift:5-8`).
- **Timeline markers collide at minimum zoom.** `pixelsPerFrame` bottoms out at 10.5, and `CelBlockView`
  draws one thumbnail across the whole cel with **no per-frame subdivision at all** — plus resize-handle
  bars at each end. Key markers need a zoom-aware collapsed form, drawn in the UIKit coordinator rather
  than as a SwiftUI overlay. **This document cited the wrong reason for that.** `TimelineTrackView.swift:4-17`
  is about *gesture* reliability — SwiftUI sibling gestures silently stopping mid-drag inside a horizontal
  ScrollView — and says nothing about drawing. The drawing-side reason is **coordinate ownership**, below,
  and it is the harder constraint of the two.
- **The drawer cannot be a sibling SwiftUI view, and §2.17 as written does not say where it attaches.**
  `pixelsPerFrame` is `private(set)` on the `TimelineTrackView.Coordinator` (`:97`), the `UIScrollView` is
  held `weak` and private, `contentOffset.x` is published nowhere, and `TimelineRulerView` (`:616`) and
  `TimelinePlayheadView` (`:792`) are `private final class`es inside that file. So **nothing outside the
  coordinator can map frame N to an x**, and a drawer placed like `InterpolateBar` — above the panel,
  which is otherwise the right precedent for growing the timeline upward — would drift out of register
  with the frames the instant the artist pinch-zooms or scrolls. Sharing the ruler and the playhead means
  living **inside that scroll content**, or hoisting those three things out. Five things follow, and each
  fails silently:
  - **`relayout()` early-returns whenever `TimelineLayoutKey` is unchanged** (`:194-217`), and the key
    holds no curve data and no `currentFrame`. Drawer state that is not in the key renders once and never
    again — the same family as `InterpolationPreviewKey` above, reached from the other side.
  - **The content-height formula exists twice** — `contentHeight` in SwiftUI (`AnimationTimeline.swift:169-171`)
    sizes the host, `totalHeight` in `relayout` (`TimelineTrackView.swift:192`) sizes the scroll content,
    the playhead and the row bands. A drawer added to one clips or leaves dead space.
  - **The pinned name column aligns by a hard-coded `Color.clear.frame(height: rulerHeight)` spacer**
    (`AnimationTimeline.swift:553-554`). Anything inserted above the ruler shifts every row down while the
    names stay, so layer names label the wrong tracks until that spacer grows by the same amount.
  - **Any drag inside the scroll content is eaten** unless it calls
    `scrollView.panGestureRecognizer.require(toFail:)`, which both existing interactive views do (`:232`, `:254`).
  - **The shared playhead is a *column*, not a hairline** — width `pixelsPerFrame`, so 10.5 to 120 pt of
    35%-blue over everything, re-fronted every layout (`:331-337`, `:795`). A curve drawn under it is tinted.
  Two more, outside the scroll view: the ruler is **not pinned** — it sits at y=0 inside content that a
  SwiftUI vertical `ScrollView` sized to the full `contentHeight` scrolls, so with enough layers the ruler
  and anything above it scroll away while the tracks stay; and `bottomDock` — which carries
  `EffectSettingsBar`, the exact surface Animate mode records from — is pinned with a literal
  `.padding(.bottom, 100)` (`DrawingView.swift:404`) while `timelineHeight` is `@State private` and
  defaults to 250, so **growing the timeline upward puts more of the bar over the panel and nothing can
  see the collision**.
- **A test class is often not named after its file here.** `InterpolationWorkflowUITests` lives in
  `TimelineAndUndoUITests.swift`; `LayerPanelUITests` lives in `LayerUITests.swift`. A `-only-testing:`
  selector derived from a filename matches nothing and reports **success**.
- **`ImageWarp` is documented as wrong for a per-frame path** — it uploads and reads back per call,
  *"exactly right for a bake that happens once at commit"* (`Engine/ImageWarp.swift:240-241`). A keyframed
  distorted text box or placed image is one GPU round trip per in-between at bake time.

---

## 11. The graph editor

Asks 4, 5 and 6 of 2026-08-29, and §2.17 sharpened by the owner from *"a drawer that grows the timeline
upward"* to *"it pops up above the layer that has it when on"*. **D1 and D2 are built; D3 onward is
not.** Line numbers are **gone from §11.2 and §11.3** rather than re-taken: every one they carried was
stale twice, and D2 moved all four timeline files again. Name the symbol, not the line — the two
sections below now do, and §11.4's remaining numbers should be re-taken rather than trusted.

**Scope, ruled 2026-08-29: one band at a time, under the selected layer.** Offered per-layer toggles and
an open-every-animated-layer mode, the owner took the selected layer. It is also the cheapest of the
three to key correctly — the expanded row is a single `Int?`, so `TimelineLayoutKey` grows one optional
field rather than a set, and the timeline's height changes by one band whatever the document holds.

### 11.1 It lives inside the timeline's scroll content

§10's coordinate-ownership finding stops being advisory here. `pixelsPerFrame` is `private(set)` on
`TimelineTrackView.Coordinator`, `contentOffset.x` is published nowhere, and the ruler and playhead are
`private final class`es in that file, so **nothing outside the coordinator can map frame N to an x**. A
band drawn anywhere else drifts out of register on the first pinch-zoom. It is drawn by the coordinator,
inside `contentView`.

**That placement also dodges a collision §10 records with nothing able to see it.** Growing the *panel*
upward puts more of `bottomDock` — which carries `EffectSettingsBar`, the surface being edited — over
the timeline, because that dock is pinned by a literal `.padding(.bottom, 100)`
(`DrawingView.swift:436`) while `timelineHeight` is `@State private` in `AnimationTimeline`. A band
inside the scroll *content* grows the scrollable area instead, and the collision never arises.

### 11.2 Stage D1 — variable row height, behaviour-neutral, merged alone — **done 2026-08-29**

`Models/TimelineRowLayout.swift` owns the geometry: an array of heights in, and out of it a row's y
origin (a prefix sum), a row's height, the content height, the drop strip a finger's y resolves
against, how far a row slides to open a reorder gap, and how many rows a drag has crossed. Both halves
of the timeline build one from `TimelineRowLayout.make(rows:rulerHeight:rowHeight:)` — the **single**
derivation, which is what stops the pinned name column and the UIKit track from disagreeing about
where a row starts. Every row is still 34 pt, so no pixel moved.

**Give a row extra height in `make` and both sides take it.** That is the seam D2 attaches to. What
still has to be decided there is whether the band is part of the row's height or a sibling view — the
name column has no gap to insert into (it is a `VStack` of one row per `LayerStackRow` under a
hard-coded `Color.clear.frame(height: rulerHeight)`), so a band the track has and the column does not
shifts every track down while the names stay and names label the wrong layers. Routing it through the
row's own height is what makes that impossible rather than merely remembered.

**The site that broke outright was not in the UIKit file**, and it is the reason this shipped alone.
`reorderGesture` counted rows by `Int((drag.translation.height / rowPitch).rounded())` — one tall row
makes that wrong for every row past it, and the symptom is a layer reorder landing in the wrong slot
with nothing thrown and nothing logged. `rowsCrossed(from:by:)` walks the pitches instead, and is
**direction-dependent**: from a short row between two unequal neighbours the same travel up and down
gives different counts, which no single divisor can express. `rowPitch` is gone.

`layerIndex(atY:)` was the one prediction that held exactly — a linear scan over `layerRowGeometry`,
independent of uniformity, unchanged to the byte.

**What `TimelineLayoutKey` did *not* need.** It still carries a scalar `rowHeight`, which is
sufficient only because the heights are a pure function of `(rows, rowHeight)` and `rows` is already
in the key. The first stage that derives a height from anything else — which is D2, since a band
opens per layer — must put that input in the key or the row draws once at its old height and never
moves again. §11.3's first bullet, reached from the geometry side. **D2 confirmed it: the field it
added carries the row's height as well as the curves, and each half fails on its own.**

**The seam took an `Expansion`, and one thing it also had to grow was a way to say *not* the whole
row.** `make(rows:rulerHeight:rowHeight:expansion:)` resolves a layer index to a row position and
gives that row the extra height, so `height(ofRow:)`, `dropBand`, `rowsCrossed` and `contentHeight`
are all right about a tall row without being touched. What D1 could not have predicted is
`blockHeight(ofRow:)`, the complement: `TimelineRowView` measures **both** a cel block's rect and the
key-marker band's origin from its own `bounds.height`, so a row view handed the expanded height
stretches every thumbnail down over the curves *and* slides the diamonds to the bottom of the band.
The track therefore sizes the row view to the block half and hangs the graph band beside it as a
sibling — which also keeps the row's pan/tap/long-press, which pick their zone from x alone, away
from a band they would read as a cel body.

### 11.3 Stage D2 — the band, and three ways it renders once and never again — **done 2026-08-29**

**D2 also repurposed the button, because otherwise nothing could open the band.** §2.22's keyframe
button is now `graphEditorButton` — `chart.xyaxis.line`, id `timeline.graphEditorButton` — and the tap
toggles the band on the selected layer instead of writing a mark. This section claimed **"no function
was lost"** on the strength of Add / Remove / Clear Keyframes being in the cel menu, which is the
workflow ask 3 described — and that was **half true and shipped as if it were whole**. The items were
on the `.block` arm of `timelineMenuContent` only. §2.4 and §2.26 put marks on the *layer*, in
absolute document frames, and `TimelineLayoutKey.trackMarkers` says in as many words that they "exist
perfectly well at frames the layer has no cel at" — which is why the marker band spans the whole
track. So a layer whose one block covered frames 0–9 could not be given a bare mark at frame 20 by
any gesture in the app: a region of the model's own address space had lost its only UI, and the
sentence asserting otherwise is what stopped anyone looking. **The `.gap` arm now carries the same
section**, and Clear is scoped there to `gapFrameRange(layerIndex:containing:)`, the run of empty
frames the artist tapped — because the owner's *"clear all keyframes in that cel"* has to generalise
to *the stretch of track you tapped* or a gap full of marks comes back one at a time. It is **tinted
blue when open**, like `interpolateButton`, because the band lives inside the scroll content and can
therefore be open and scrolled out of sight; unconditionally white left the artist no way to tell a
closed editor from one below the fold. The **channel list is not part of this stage**; ask 3 wants the
button to raise the list as well, and that is D4 hanging a control inside the band rather than a
second thing on the button, which would give one control two jobs and make one of them win the second
tap.

- **`TimelineLayoutKey` gates everything, and the field it needed is bigger than "the curves".**
  `relayout()` early-returns on `built.key == laidOutKey`, so `graphBand` carries the whole band as
  one optional `TimelineGraphBand.Content` — the expanded layer index, the height it asked for, and
  every channel with its curve and its `uiRange`. Two failures, not one: without the height the row
  draws at 34 pt forever, and without the curves the line freezes at its first shape. **The
  distinction the mutation test made concrete is that a curve's shape moves nothing else on the
  track.** A key's value, a bezier handle, a tangent mode, a segment's interpolation and the
  channel's `step` all change the drawn line and change **no frame** — so `trackMarkers`, which is
  positions only, is unchanged and the gate stays shut. Only a key's *frame* moves both.
  `AnimationCurve` is `Equatable`, so this is an ordinary field rather than a hash: nothing has to
  describe what the hash covers or keep it in step, and the cost argument survives because the band
  is nil while it is closed and holds one layer's channels while it is open. The view reads what it
  draws **out of** the key, `trackMarkers`' rule.
- **The playhead is a column, not a hairline** — width `pixelsPerFrame`, so 10.5 to 120 pt of 35 %
  blue, `bringSubviewToFront` on every `movePlayhead`. **Left in front, having looked at it**: a
  saturated 1.8 pt curve reads through the wash perfectly well, and the one thing an artist wants
  from a graph editor beside the shape is where the playhead crosses it — fronting the band would cut
  that column into two halves with a gap where the curves are, which is worse than a tint.
- **Any drag inside the scroll content is eaten** without
  `scrollView.panGestureRecognizer.require(toFail:)`; both sites are inside `relayout()`, not
  `makeUIView`. D2 adds no recogniser and sets `isUserInteractionEnabled = false` on the band, so the
  arbitration question is D3's whole and undisturbed. **The band is a sibling of the row pool rather
  than a member of it**, so the "add it inside the same loop" advice above does not apply as written:
  what applies is that D3's recogniser must make that call wherever the band is created.

**What it cost, and the two predictions that were wrong.** The band is `Views/TimelineGraphBand.swift`
(every number: the value-to-y map, the range fallback, the sampling stride, the palette, the
accessibility encoding) plus a `UIView` in `TimelineTrackView.swift` that owns only `UIBezierPath` and
`UIColor` — the split `TimelineKeyMarkers` argues for, and the reason 18 of the 29 new tests are in
the fast tier. **The marker band did not follow the row down**, because sizing the row view to
`blockHeight` removes the hazard rather than fixing it. **And the name column's trap is real but is
not assertable from XCUITest**: a SwiftUI `Text` with an accessibility identifier, inside a row that
also carries `.contentShape` and a gesture, reports the **cell's** frame rather than the glyph's — so
"the name stayed at the top of the tall row" was checked by eye and the test pins the row cells'
tops and heights instead, which is the failure that actually loses the artist their place. The fix
is two frames: the name is centred in `blockHeight` and that block is pinned `.top` in the full
height, which is a no-op for every row with no band.

**What an adversarial review of D2 found, and what each finding cost.** Five findings, all five real
and all five fixed; the one question inside them that is answered *"leave it"* is the band's backing
store, and it is answered with arithmetic below rather than with a shrug. They are recorded here
rather than folded into the bullets above because each is a place where a sentence in this section
was true of the code and wrong about the behaviour — which is the pattern worth recognising more than
any one of them.

- **The band sampled the whole track, not the screen.** `sampling(in:)` clipped to the dirty rect,
  and the dirty rect **is not a clip on this view**: the band's own width is the whole laid-out track
  and UIKit hands a full-bounds rect for the no-argument `setNeedsDisplay()` that both `update` and
  `layoutSubviews` call. `TimelineRulerView.draw` already states that premise; what nobody carried
  across is that the ruler pays one CoreText layout per **frame** and the band pays a Bézier
  root-solve per **point**. A 300-frame document at the default zoom is 9,000 pt, so two animated
  channels were ~18,000 `evaluate` calls — each a binary search and, on a bezier segment, a Newton
  solve of 2–3 `cubic()` — per redraw, and 216,000 `cubic()` calls at the 120 pt/frame ceiling; on
  every `.changed` tick of an auto-keying slider drag and every `.changed` sample of a pinch.
  `sampling` now takes `visibleX`, and the cost is the viewport — ~1,366 pt on this iPad — whatever
  the document's length and zoom are. **The clip brought an obligation with it**: clipping without
  invalidating on scroll trades a slow band for a blank one, so `scrollViewDidScroll` redraws the
  band *before* its own growth gate, and `relayout`'s early-return path refreshes the window too
  (a scroll raises no SwiftUI pass; the first pass after the scroll view has a width raises no scroll
  event, and neither call subsumes the other). The viewport is deliberately **not** in
  `TimelineLayoutKey`: it moves faster than the layout, which is `currentFrame`'s argument for
  `movePlayhead` reached from the other axis.
- **The backing store is a second question and it is answered "not the band's", with numbers.** The
  band view is `totalWidth` × 96 pt and `draw(_:)`-backed, so UIKit allocates `totalWidth × 96 × 4 ×
  scale²` regardless of what is sampled into it — at scale 2, `totalWidth × 1536` bytes: **13.8 MB**
  for 300 frames at the default 30 pt/frame, **55 MB** for the same document at the 120 pt ceiling,
  **184 MB** at 1,000 frames × 120. Real numbers, and the band is the largest single store on the
  track — but `contentView`, `rulerView`, every `TimelineRowView` and every `TimelineKeyMarkerBand`
  are all `totalWidth` wide too, and the last two are `draw(_:)`-backed as well. So the *width* is a
  property of the track rather than of the band, and above ~8,192 pt of view width (16,384 px, the
  Metal 2D texture limit — **INFERRED**, not observed on device) nothing on the track can be backed
  at all, the 18 pt ruler included, which a 273-frame document reaches at the default zoom. Sizing
  the band's drawing view to the viewport would therefore buy a correct band under a ruler that had
  already failed, which is worse than the status quo and not a D2-shaped fix. **Left as it is,
  deliberately**; the owner of the fix is the track — a cap on `totalWidth`, or viewport-sized
  drawing views for all of it — and it predates D2 by every one of those views.
- **The drop strip and the drag ghost disagreed by the whole band.** `relayout` recorded
  `dropBand(ofRow:)`, built from `height(ofRow:)`, which now *includes* the expansion — so the
  expanded layer's drop strip was 130 pt, while `layoutDragChrome` draws the ghost and the drop
  indicator at `blockHeight`. A finger over the curves resolved to that layer and painted the block
  it was carrying up to 96 pt above itself. **A cel cannot live on a value axis**, so the band is not
  a drop target of its own — but "not a target" is not an available answer, because every y between
  two rows has to resolve to one of them. Three readings, and the arithmetic picks between them:
  giving the band to its own layer costs the 130 pt detachment *and* makes an expanded layer a sticky
  target its neighbour is 96 pt further away than it looks; leaving it covered by no strip hands it
  to `layerIndex(atY:)`'s nearest-row fallback, which compares distances to row **tops** and so
  would split it 30 pt down rather than in the middle — emergent and untestable; **halving it
  deliberately** gives the smallest worst-case gap between the finger and its ghost (66 pt rather
  than 130) and is the only one of the three a logic test can see. So `dropBand` takes the row's
  blocks plus half of its own band, and reaches up for half of the band belonging to the row above;
  with nothing expanded both terms are zero and the arithmetic is what it always was, so the strips
  still meet everywhere. The ghost is drawn from a **separately recorded** `blockTop` rather than
  derived from the strip, which is the half of this that would otherwise silently come back.
- **A key's dot does not sit on the drawn line when a curve's `step` is above 1, and it is meant not
  to.** `evaluate` applies `stepped(_:)`, which quantises time **down** onto a multiple of the step,
  anchored at frame 0 of the curve's own time base — so on twos a key at an odd frame holds a value
  the animation never outputs. Both are truths worth drawing: the line is what the animation *does*,
  which is what a graph editor is read for, and the dot is where the key *is*, which is what D3 hands
  the artist to drag — a dot moved onto the line would be a handle reporting a value no key holds.
  They are kept apart and **joined by a hairline stem** wherever `TimelineGraphBand.stem(forKeyAt:in:)`
  is non-nil, so the gap reads as a fact about the step rather than as a rendering bug. Latent today:
  nothing in the app writes a step above 1 yet (§2.10), and `step` decodes from a document.
- **And one test that could not fail**, which is the finding worth carrying forward.
  `testBothColumnsPutEveryRowInTheSamePlaceWithTheBandOpen` named the exact failure `TimelineRowLayout`
  exists to prevent and then built its two layouts from two `make` calls with byte-identical
  arguments, so it asserted that `make` is deterministic and nothing else. It could not have asserted
  more: neither call site is compiled into the test target, which is the reason the type exists. It is
  gone, its non-vacuous half kept under a name that says what it checks, and the real guard is named
  in its place — `GraphEditorUITests.testOpeningTheBandKeepsEveryNameLinedUpWithItsTrack`, which
  measures the two columns' on-screen frames. **A test that cannot fail is worse than no test**,
  because it reads as coverage; the tell here was that the failure it named was a disagreement between
  two *files* and every symbol in its body came from one.

**The reflow the band causes lands inside the timeline's own gestures, because selection is a side
effect of half of them.** The scope ruling above is not in question — *"graphs are layer based, so
tapping on another layer should just open the other layer's graph."* What it costs is that
`currentLayerIndex` is written by gestures whose subject is a *cel*, and the band is part of a row's
**height**, so each of those writes moves every row between the old band position and the new one by
96 pt. Three sites, and they do not have the same answer.

- **A block drag: fixed, and it was changing the document rather than merely detaching a ghost.**
  `beginBlockDrag` writes `currentLayerIndex` for the layer the block came from and `updateBlockDrag`
  relayouts inside the same touch. The finger does not move with the rows, so `layerIndex(atY:)`
  resolves it against the new geometry: three layers with the band open on the top one, a finger 17 pt
  into the grabbed row's block becomes 113 pt into that row's now-130 pt height, and `dropBand` gives
  everything past 83 pt to the row **below**. So a re-time became a **cross-layer move** — the 96 pt
  ghost detachment was the visible half of a defect whose other half moved the artist's drawing to a
  layer they never touched. `CanvasManager.pinGraphBand()` / `releaseGraphBand()` hold the band on the
  row it is on for the length of the drag and let it go when the finger lifts. **Only the row is
  held**, not whether the band is open: the toggle is a button, and a button cannot be pressed by a
  finger already dragging the track. **And only the block drag takes the pin** — a cel resize, a ruler
  scrub and the name column's reorder all leave `currentLayerIndex` alone for the length of their
  gesture, so a call in any of them would be a control that never fires.
- **The two-stage tap: not fixable, and that is the answer rather than a partial fix.**
  `handleTapOnCel` and `handleTapOnGap` write `currentLayerIndex` on the *first* tap of the documented
  "first tap moves the cursor there, a second tap opens it" contract, so with the band open on a row
  above, the tapped row rises 96 pt between the two taps and the point the artist first touched is
  inside the band. **The arming survives the move** — it is a cel identity (`layerIndex ==
  currentLayerIndex && clamped == currentFrame`), never a screen position — so the menu opens on the
  second tap wherever the row has gone;
  `GraphEditorUITests.testTheTwoStageTapSurvivesTheBandMovingToTheLayerItTapped` measures the 96 pt of
  travel and then takes the menu, which is both halves of the claim in one test. What cannot be
  recovered is the finger: the row *must* move, because the band is a row's height and the ruling puts
  it under the layer that was just selected. The cost is **one wasted tap per layer switch while the
  band is open**, paid once — every further two-stage tap on that layer is already in register. This
  is the same hazard the `.gap` arm's keyframe items are reached through, and it costs them the same
  one tap.
- **Compensating the timeline's own scroll offset does not work, and the reason is structural rather
  than a corner case.** Moving the band from row C to row L below it leaves every row at or above C
  and every row past L exactly where it was, and lifts only the rows in between — a scroll is a
  **uniform** translation of all of them, so giving L its 96 pt back displaces every other row by 96 pt
  the other way. It does not remove the reflow; it moves it onto the rows the artist did not touch.
  The shortage of range is real too and arrives second: the viewport is `timelineHeight - 12 - 40 - 1`,
  197 pt at the default 250, against `18 + 8 + 36N + 96` of content, so a **three-layer** document has
  33 pt of scroll range to pay a 96 pt debt with and **five layers** is where the full 96 pt first
  exists at all.
- **Animating the relocation was considered and rejected.** It fixes nothing — the row still ends up
  96 pt away and the finger still has to follow — and the timeline's row geometry has never animated
  anywhere else: a folder collapsing, a layer added or deleted, and the band's own open and close all
  reflow instantly. The failure mode is also invisible from the test tier: the two columns are laid
  out by SwiftUI and by UIKit, so easing them at different rates is a **new** defect that XCUITest can
  see only as flakiness in `testOpeningTheBandKeepsEveryNameLinedUpWithItsTrack`. Bridging one
  transaction into both is not available either — `withAnimation` around the write would put
  `handleActiveContextChanged`, which bakes floating pieces and commits canvas edits, inside the
  transaction, and the name column's rows already carry an `.animation(_:value:)` over the same
  subtree as the height frames.
- **A tap inside the band does nothing, before this pass and after it.** The band's rectangle is
  covered by no row view — `TimelineRowView` is sized to `blockHeight` — and the band itself takes no
  touches, so the touch reaches the scroll view, which pans and nothing else. That is the right answer
  for D2 because §11.4 claims this area for curve gestures, and wiring it to the row underneath would
  be building something D3 has to take out again. It is pinned by
  `GraphEditorUITests.testATapInsideTheBandDoesNothing`, because the plausible regression — sizing the
  row view to the full expanded height, the simplification §11.2 warns about — would make the band
  read as that row's cel body and raise a block menu over the curves.
- **`dropBand`'s deliberate half-and-half survives the pin unchanged.** The pin stops the band
  *moving* during a drag; it does not remove the band, and every y between two rows still has to
  resolve to one of them, so all three readings above are still on the table and the arithmetic still
  picks the same one. The separately recorded `blockTop` stays for the same reason.

**Colour comes from `Effect.parameters` order, not from the drawn list.** Eight hand-picked hues,
indexed by the channel's descriptor position — hand-picked because a generated palette cannot be told
that ~211° is the playhead and ~48° is an interpolation reference (§2.8), and descriptor-indexed
because the drawn list reorders the moment a channel starts animating, which happens mid-drag while
the artist is watching. Every channel of one band comes from one effect, hence one table, so the
first eight are distinct by construction.

### 11.4 Stage D3 — the gestures, most of which are already written

`TimelineKeyMarkers.frame(atX:pixelsPerFrame:)` is the exact inverse of `centerX(frame:)` and its own
doc says **"Nothing calls this yet and that is deliberate"** — it was written for this, and D2 left it
untouched.

**There are now two inverses and they answer different questions.** D2 added
`TimelineGraphBand.time(atX:pixelsPerFrame:)`, the **continuous** inverse of the same forward map,
because sampling a curve between two frames needs 7.4 and not 7. `frame(atX:)` floors to a column and
is the one D3's hit-testing wants. Using either for the other's job puts the answer half a frame out —
which is exactly enough to pick up the wrong key at the default zoom and to draw a curve that misses
its own dots.

Reuse `CurveEditor`'s gesture grammar (`Views/EffectSection.swift:683` onward), which §3.2 already
nominates: `DragGesture(minimumDistance: 0)`, `hitRadius` 22 pt, `tapSlop` 5 pt, drag moves,
tap-on-empty adds. Reuse the **rules and constants, not the widget** — that one is SwiftUI and this is a
`CGContext` in the coordinator. The hit arithmetic goes in a logic-testable enum beside
`TimelineKeyMarkers`, for that file's own stated reason.

**`AnimationCurve` needs no model work.** It already carries `setKey`, `removeKey`, bezier handles, five
tangent modes, per-segment interpolation and the per-channel step, and its decision 1 — the output is
never clamped — is what makes dragging a handle worth doing.

**Ask 6, the marquee.** The owner: *"the ability to use the select tool on it to select the keyframe
nodes and move them."* Build it as the band's **own** drag-in-empty-space rather than as an observation
of `currentTool`. A drag in empty space inside a graph editor has no competing meaning, so routing it
through the canvas's `Tool` would couple two unrelated surfaces to buy a mode the artist would then have
to switch into. **The cel half of that ask is future and already has its stub**: "Select Multiple" sits
in the cel menu today, `.disabled(true)`, and a marquee over cels is what enables it.

### 11.5 Stage D4 — the channel list is a filter, not a navigator — **done 2026-08-29**

The owner: *"just a button option in the graph editor which brings up a scrollable popup menu, which is
basically an include or exclude checkmark box for each animation. Animations may have multiple values
being modified at once (like transform x and y), so those should have a drop down so they are visible or
invisible like a whole. This is basically like the hide/show layers and layer groups."*

So it is visibility, not selection: the editor shows every animated channel and the list turns them off.
Membership of the list is `channelIsAnimated` — the strict predicate, ≥2 keys whose values are not all
equal — never the loose one auto-key uses. Visibility is **transient view state, not document state**: it
filters what is drawn, it has no meaning with the editor closed, and persisting it would put a field in
the manifest that changes no pixel. `TimelineGraphChannelList` holds the grouping, the toggle arithmetic
and the filter's scope, beside `TimelineGraphBand` and for that file's reason — `AnimationTimeline.swift`
is not compiled into the test target, so a rule written there is pinned by nothing.

**Grouping falls out of the id format, and what falls out is one group.** Parameter ids are
`"<case>.<field>"` so `groupID(ofParameterID:)` is the text before the first dot and no second table is
needed — but a band is one layer, a layer is one grade, and a grade is one prefix, so **every band today
has exactly one group**. That is not a reason to drop it: the group row is the only control that switches
a whole effect off in one tap, which is the owner's *"visible or invisible like a whole"*, and the shape
is what a second channel source (a transform, a folder's grade) will need. It is pinned by
`testEveryBandTodayHasExactlyOneGroupBecauseALayerHasOneGrade`, which is the assertion that changes the
day the premise does.

**And it is why there is no fold.** The groups are not merely expanded by default, they cannot be
collapsed at all: a chevron over one group folds the only thing in the list, so its only reachable state
today is the empty list the expanded default exists to prevent. Collapse state is also the one piece of
this feature that has no natural scope — keyed by effect case it is *"brightnessContrast"*, which follows
the artist to the next layer carrying a Brightness/Contrast grade and greets them with a header and no
channels, where the visibility filter carries its `KeyframeTarget` and dies with the band. The control
comes back with the second channel source, when it has something to fold and a reason to be scoped, and
the premise test above is what says when. **The decision lives in `TimelineGraphChannelList`, not in the
view** — `AnimationTimeline.swift` is not compiled into the test target, so a rule written there is
pinned by nothing, which is the same reason the grouping and the toggle arithmetic are in that file.

**The group's *name* is the one thing the id format cannot supply**, and "display names come from the
descriptor table" was true only of the channels. `EffectParameter.name` is a field label ("Radius"); a
group has no descriptor row, so `TimelineGraphChannelList.groupNames(of:)` reads the effect's own
`displayName`, which is the word the artist picked the grade by. Splitting camel case out of the prefix
instead would have worked for twelve of the thirteen and spelled `hsvShift` "Hsv Shift".

**It is read at the popup and *not* carried on `TimelineGraphBand.Channel`, which is the cheap spelling
and a layout-key defect.** A `Channel` is inside `Content` and `Content` is inside `TimelineLayoutKey`,
so a field the band never draws still gates `relayout()` — and `Effect.displayName` is constant per case
for twelve of the thirteen effects but not for `.blur`, which answers "Directional Blur" or "Gaussian
Blur" off a toggle. One tap on Directional therefore relaid out every row frame, every cel accessibility
identifier and the ruler's per-frame CoreText loop, for a band whose curves had not moved. The rule the
fix states is the general one: **a `Channel` carries only what the band draws with.** The list is SwiftUI,
is built only while the popup is up, and `graphChannelGroups` already holds the effect, so reading the
name there costs one walk of at most thirteen descriptors on a surface that is off screen the rest of the
time. `testFlippingTheDirectionalToggleDoesNotReflowTheTimeline` pins it, on a *named* layer: an unnamed
value layer is renamed to its grade's `displayName` by `setLayerEffect`, so the name column moves the key
too and hides what is being measured.

**The filter is applied inside `graphBandContent`, before the key is built, and that placement is the
whole feature.** `relayout()` early-returns on `built.key == laidOutKey`; a filter applied later — read
off the manager inside `TimelineGraphBandView.draw` — would change what the band should show without
moving the key, and unchecking a box would move nothing on screen until an unrelated edit happened to
reopen the gate, with nothing thrown and nothing logged. Filtering into `Content.channels` makes the key
move for free and leaves every line of the drawing code untouched: what is drawn *is* what is keyed on,
`trackMarkers`' rule. Mutation-tested both ways — with the filter lifted out of `graphBandContent`, six
tests fail including both key ones. **Colour survives it**: a channel keeps its `descriptorIndex`
through the filter, which is what D2's colour rule was for, and re-deriving it from the drawn position
(the obvious spelling, since the list is now short) fails `testHidingAChannelRepaintsNothing`.

**Where it hangs, and which of the three presentation shapes it is.** A second button,
`timeline.graphChannelsButton`, rendered from both timeline bars **only while the band is open** — ask 3
wants the graph-editor button to raise the list too, and a control that both toggles and raises a menu
has no answer for its second tap. It is a real `.popover` and therefore a **`CanvasPresentation` case**
(`graphChannelList`, `overlapsLiveCanvas` true), which is `onionSkinOptions` and `interpolateOptions`
line for line: a list of controls presented from timeline chrome over a mounted, touchable `CanvasView`,
with its openness in a `Binding`. §8 stage 3b's other two were read and rejected — an inline docked panel
is not a presentation and a case for one would be wrong, and `ActivePanel` is the canvas's settings rail
that `CanvasTouchOwner` reads to decide who owns a touch, which this list is no part of. One consequence
of the conditional button: `CanvasPresentationModifier.onDisappear` deliberately does not clear the
site's own flag, so a popover open through a host deletion returns when the host does. That is a
pre-existing bug in a modifier every presentation in the app routes through (BUGS.md, "A popover whose
host view disappears re-presents itself when the host comes back") and D4 is only where it became
reachable, being the first control rendered conditionally with a presentation hanging off it — so this
stage carries a local guard rather than changing a modifier the whole app routes through.

**The guard is `isGraphEditorOpen`'s `didSet`, beside the filter it is the twin of**, and the list's
`isPresented` is `CanvasManager.isGraphChannelListOpen` rather than `@State` in `AnimationTimeline` for
that reason alone: the other popovers in that file are `@State` because none of them has a rule, and this
one does. Written in the view it would be pinned by nothing — and **it cannot be pinned from the UI tier
either**, measured 2026-08-29: with the popover up, a tap on the graph editor's toggle is spent
dismissing the popover and never reaches the button, so an XCUITest closes the list first every time and
never reaches the state. On the model it is one line and
`testClosingTheEditorTakesTheChannelListDownWithIt`.

**An all-hidden band is not an empty one and does not say so.** D2 made an empty band report `"empty"`
because an artist looking for a curve that was never there is the failure; here the curves are there and
the artist put them away, so the band reports `"hidden"` — which is why `Content` carries `hiddenCount`
rather than only a shorter `channels`. The artist's version of that distinction is not an accessibility
value: the channel-list button is **tinted blue while anything is switched off**, `graphEditorButton`'s
reason, and in the all-hidden state it is the only signal there is.

**The filter lives exactly as long as the band it was made on**, which is what makes a stale id
impossible rather than merely harmless. It carries the `KeyframeTarget` it was authored against and
answers `[]` for any other band, `isGraphEditorOpen`'s `didSet` drops it on close, and `setting` prunes
to the ids the band is currently listing so a grade swap cannot leave `"blur.radius"` waiting for a Blur
to come back. The invariant underneath all three is that the filter can only ever **subtract**: the drawn
channels are a subsequence of the strict predicate's answer whatever the set holds, so a hidden id that
names nothing hides nothing and no id can resurrect a channel `isAnimated` refused.

### 11.6 Open

- ~~**The y axis when several channels are visible at once.**~~ **Ruled 2026-08-29: each curve is scaled
  to fill the band.** Shown the trade — per-channel normalisation makes every curve legible and makes two
  slopes incomparable, one shared axis is honest and leaves a 0…1 opacity flat beside a 0…500 blur radius
  — the owner took normalisation. The reasoning to keep is that the comparison being given up is not one
  worth having: a blur radius and an opacity are different units, so their slopes were never comparable in
  any useful sense, while a band a couple of inches tall makes the shared axis lose the small-range channel
  outright. Blender and Maya both ship the toggle; this ships the default that suits the screen, and the
  toggle stays available as a later addition rather than a thing the first version owes.

  **Normalised against what, sharpened 2026-08-29.** Two readings of "fill the band" survive the ruling —
  the channel's declared `uiRange`, or the extent of the keys actually present — and the tree already
  answers it. `Effect.swift:1300-1301` says to draw the y axis over **`uiRange`** and to allow a key
  anywhere in `modelDomain`, which is a note written before this feature and for it. Fitting to the key
  extent instead would rescale the axis on every drag, so a key would move under the finger that is not
  dragging it. Take `uiRange`, fall back to the key extent only for a parameter whose `uiRange` is nil,
  and **clip to the band** — `AnimationCurve`'s decision 1 is that the output is never clamped, so a
  bezier overshoot genuinely leaves the range and the band must cut it rather than rescale for it.
- ~~**The band's height, and whether it is draggable.**~~ **Fixed at 96 pt, D2, not draggable.** There
  is no stored size and nothing to persist; it is `TimelineGraphBand.height`, asked for by
  `CanvasManager.graphBandExpansion` and carried in the layout key so the row it expands can move.
- ~~**A collapsed folder hides its children's key markers.**~~ **Ruled 2026-08-29: it shows nothing, which
  is today's behaviour, so there is no work.** Offered merged per-frame diamonds from the hidden children
  and a single "there is animation in here" indicator, the owner kept the blank row. Recorded as ruled
  rather than deleted because it was found as a gap and will be found again: the next session to notice
  a folder swallowing its children's markers should read this and move on.
