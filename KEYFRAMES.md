# Keyframes

**Animating properties across the frames one cel spans.** TODO.md item (21), specified 2026-08-28
after the conversation that file names as each item's entry condition. This is the design; nothing is
built yet.

**What this is not.** It is not the interpolation feature. That one in-betweens *drawings* between two
reference cels and ships already ([VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)). This one moves
and grades content that is already drawn. They are complementary, they will sit in the same timeline,
and §2.8 is how the artist tells them apart.

**How to read it.** Blockquotes are the owner's own words. §2 is the settled rulings — thirty of
them, twenty from 2026-08-28, eight from 2026-08-29 and two from 2026-09-03 — and TODO.md's rule applies: *a question the owner has answered stops being a
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

Videos as vector-layer objects are **TODO item (26)**, not this document. They inherit this feature's
pose channel and its bake, which is why item (2) is stated to require item (1).

---

## 2. Rulings — settled 2026-08-28 and 2026-08-29, do not re-litigate

**Four of these are superseded, and they are kept rather than deleted.** §2.1, §2.23 and §2.24 were
overtaken by §2.26 and §2.27 later on 2026-08-29 — the owner reversing their own ruling, which is not a
re-litigation. §2.16 was overtaken by BRUSH.md §2.4/§2.5 on 2026-09-03, the brush overhaul it said would
inherit grain deleting grain instead. Each is marked in place with the date and the reason, because the
reasoning is what stops a later session reinstating it by rediscovering the argument that produced it.

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
   Distort.** Distort was *"not implemented today"* when this was written and shipped on 2026-09-02
   for the raster floating piece (LASSO_MOVE.md §0, stage 5) — `FloatingPiece.distortQuad` through
   `Homography`/`ImageWarp` — which is the same representation §2.14 asks a transform key to store, so
   the two still meet with no migration. It is refused on a lassoed *vector* float
   (`CanvasManager.distortUnavailableReason`) for §8's own reason: the per-dab width a homography
   needs is §4.2's rest-space bake, which is stage 5b's prerequisite and not stage 5's.
3. **A transformation layer re-poses the vector objects below it**, rather than resampling the
   composited pixels below it. The owner wants crisp lines, not a bitmap magnify. This answers the
   question TODO (21) raises and calls *"different features wearing the same name"*.
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
16. ~~**Brush grain travels with the ink.** Each dab's grain value is baked when the stroke is drawn, so
    the texture is part of the mark. Accepted consequence: a stroke you Move keeps its grain instead of
    re-sampling, which is a visible change to how existing artwork behaves under Move.~~
    **SUPERSEDED 2026-09-03 by BRUSH.md §2.4/§2.5.** Stage 4 below delivered this ruling's headline and
    declined its parenthetical, on the reasoning that grain was *"expected to change with the brush
    overhaul that makes brushes importable, so TODO (37) inherits it."* TODO (37) is that overhaul, and
    the owner's ruling there was *"Delete all of grain"* — not carry it forward changed. §2.4/§2.5:
    *"§2.16 is discharged by §2.4, not implemented... It changes by ceasing to exist."* `BrushGrain`,
    `noiseValue` and `grainAlphaMultiplier` are gone, and the tests that pinned grain-travels-with-
    posed-ink are deleted with the feature rather than rewritten.
17. **The graph editor is a drawer that grows the timeline upward**, sharing the timeline's frame ruler
    and playhead, so a curve sits literally above the frames it controls — not a popover and not a
    full-screen sheet.
18. **A derived in-between carries no object channels.** It has no stable elements to key: the display
    list is computed. This mirrors what already ships — Move is refused outright on an interpolated cel,
    in `CanvasManager.activeVectorMoveTarget`, which since 2026-09-03 is the **one** place rather than
    two (`TopToolbar.toggleMove` spelled the same rule again, where the fast tier could not see it) and
    which raises `CanvasNotice.cannotMoveDerivedFrame` rather than returning in silence.
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
    is refused now, because a mark with no channel is a legal thing to place on an untouched layer.
25. **The live per-frame cost of a *derived* frame is not held to the 24 fps budget. The prebake is what
    must play at 24 fps.** 2026-08-29, and it is the widest-reaching of these rulings because it decides
    how every future measurement on this path is read. Shown that engaging the compositor on an
    interpolation in-between costs +75.7 ms/frame, the owner: *"if we are planning for this feature, then
    it is okay for things to take more than 1/24th of a second, including in-betweens... if it prebakes
    and can play at 24fps after, then the original ask is covered."* The "feature" is background baking —
    TODO (29), asked for the same day, unscheduled, and **already specified twice** (§4.6 here and
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

    **A keyframe is therefore a mark in time that acquires channels lazily** — and the mark is dropped
    the moment a channel takes that frame, so the two never both hold it (§2.28's superseded rule is
    what used to let them). `keyframeMarks` on
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
    frames, and there is one form of marker.

    **One consequence worth keeping.** A grade that is not in force contributes no curves — a track
    left on a layer by a kind change is storage, so it draws no diamond and offers no Remove Keyframe,
    while its marks stand, because a mark is a point in time rather than a property of an effect.

    **SUPERSEDED, 2026-09-03 — this section's own closing rule was the divergence it exists to
    prevent, reached by the other door.** It said `addKeyframe` still records an explicit mark on a
    frame a channel already keys, and that *"the two come apart the moment that key is dragged or
    deleted in the graph editor"*. They did, and the graph editor could not repair it:
    `writeGraphBandCurves` reaches `setEffectParameterTrack`, which writes `effectTracks` and nothing
    else, so dragging the node at frame 10 to 14 left a mark at 10 beside a key at 14 — an indicator
    with no node, drawn hollow. **A green test asserted that as a feature**, band string `"(0)|4|10"`
    captioned *"the frame it left keeps its explicit mark, now hollow"*, pinned end to end by an
    XCUITest twin.

    **The replacement ruling, the owner 2026-09-03**: *"if a node exists on the graph editor, it
    should also exist on the cel as an indicator and vice versa."* A mark that a key lands on is
    **dropped**, so `keyframeMarks` holds exactly the keyframes no channel keys and
    `keyframeFrames(of:)` is their union. The rule is applied by `marks(_:droppingKeyed:)` at the two
    funnels every writer reaches — `commitKeyframeState` and `setEffectParameterTrack` — asked against
    the keys *either side* of the write, which is what makes a key dragged off a marked frame take the
    mark with it and what heals a document saved under the old rule on first touch.

    **`keyframeMarks` itself cannot be deleted, and that is the load-bearing correction.** It is the
    only storage for §2.26/§2.27's first step: `KeyframeControl.write` counts keyframes to route, and
    with none, a slider edit takes the `.storedValue` arm, holds no baseline, and the owner's own
    canonical A-then-B workflow produces no animation at all. What is deleted is the *overlap*, not
    the list.

    **The biconditional has two residues and neither is a defect.** A mark no channel keys is an
    indicator with no node — that is §2.26's first step and deleting it would delete the workflow.
    ~~And **pose keys draw indicators while a pose channel has no graph-editor band at all** (TODO
    (21)'s stage-5 gap), so every pose keyframe is an indicator with no possible node until that band
    exists.~~ **Gone**: §11.7 built the band, and the two funnels a *container* pose reaches — the
    ones `removeKeyframe` and `addKeyframe` go through — were widened to see it when the
    transformation layer got its artist entry (§4.4). Both had walked the layer's cels and stopped,
    so a container pose key drew an indicator the artist could not delete.
29. **A Move that catches part of an animation group is refused, and says so.** 2026-09-03, and the
    owner's words are the whole of it:

    > "Lets say animation A is a movement of a selection to a location. Now if you select half of the
    > selection, then it shouldn't allow you to move it because that would break things."

    A group's members are carried by **one** channel, so a key written for it moves every one of them.
    `existingAnimationChannel` reused a group as soon as every element the lasso *caught* shared it,
    and never asked whether the group had members the loop had missed — so a half-lasso routed onto
    that group's channel and `commitTransformPose`'s `.key` arm restored the pre-lift display list and
    keyed the whole thing. The artist dragged half a drawing and all of it moved, in silence. The
    other two writing arms fail the same way one step later: `.seedAndKey` leaves the drag baked *and*
    keys the group, and `.storedValueHoldingBaseline` parks a baseline that does it when the next mark
    lands.

    **The predicate is stated over group *membership*, not over which channel the write would land
    on**: a Move is refused when the elements it caught include some but not all of the members an
    animation group has on that cel. `CanvasManager.animationGroupHarmedByMove` is the one statement
    of it — of both halves, since §2.30 below joined them — and
    `CanvasNotice.onlyPartOfAnAnimationGroup` is the sentence the artist reads, which names the way
    out, since selecting the whole group is a Move this rule permits.

    **The cel channel is not one of these, and that narrowing is required rather than an exemption.**
    `.cel` carries every element, so a rule stated over channels would make an animated cel refuse
    every lasso drawn on it — and it would protect nothing, because `existingAnimationChannel` answers
    `.cel` only for a Move that carries the whole list. A partial lasso on a cel-animated drawing
    mints a group of its own and nests inside the cel move, which is a character's arm swinging while
    the character walks.

    **Refused at the lift, not at the commit.** The damage is at the commit, but by then the artist
    has drawn a loop, tapped Move, dragged a box across the canvas and let go — and a refusal that
    lands there tells them their gesture was wasted after they made it. The lassoed set is known at
    the lift (`splitForLassoMove` has answered it on a list it has not yet installed), so waiting buys
    nothing and costs a gesture.

    **And refused rather than narrowed to the lassoed half.** Splitting one animated group into two is
    a different feature; the owner ruled for the refusal.
30. **A Move that catches a whole animation group *plus anything else* is refused too, and says so.**
    2026-09-03, the same day and the same rule reaching its second case. The owner's reasoning is the
    one they set in §2.29 just before:

    > if a Move would damage an existing animation, it does not happen, and it says why

    §2.29 covers a lasso that catches **part** of one group. This is a lasso that catches **all** of
    two — which that refusal deliberately allows — and it silently ends both of their animations.
    `existingAnimationChannel` reuses a group only when *every* carried element shares one, so a
    selection spanning two answers nil and `commitPoseFromFloat` falls through to
    `mintAnimationChannel`, which **overwrites** `animationGroupID` on every carried element with the
    fresh group's id. From that moment `isMoved(by: .group(old))` is false for all of them, so the two
    tracks still sitting on the cel claim no elements and pose nothing. Nothing looks wrong at the
    frame the Move was made on — the ink keeps moving, under the new channel, from wherever the drag
    left it — and the loss shows up only when the artist scrubs, with nothing pointing back at the
    Move.

    **One rule, and §2.29 is restated by it rather than sitting beside it:** *an animation group moves
    whole, and on its own.* `CanvasManager.animationGroupHarmedByMove` is the one statement of both
    halves and answers which one failed.

    **Two whole groups is not the only door, and the rule is not a count of groups.**
    `existingAnimationChannel` builds a `Set` of the carried elements' tags, so an untagged element
    contributes `nil` and the set has two members exactly as two groups would — meaning **one whole
    group carried beside ink in no group** takes the same fall-through and loses that group's
    animation identically. A four-element drawing is enough to reach it. Both are one case, because
    the way out of them is the same: loop around just one group.

    **The whole-cel escape is required rather than an exemption, and it is the trap in this rule.** A
    whole-cel lift carries every element, so it carries every group whole and *not alone* — and a
    predicate that stopped at the sentence above would refuse **Move with no selection on every
    animated document**. It is allowed because `existingAnimationChannel` answers `.cel` for exactly
    that Move: nothing is minted, no tag is rewritten, and each group travels whole nested inside the
    cel's own move, which is a character walking with both arms still swinging. Stated as *every
    element on the cel is carried*, not as *no group was left behind* — the damaging case has untagged
    ink outside the loop and no group's member there at all.

    **`beginVectorChannelMove` still does not ask, and still does not need to.** It lifts
    `isMoved(by:)`'s membership — every member of one group and no other ink — which fails neither
    half, on a document with any number of groups.

    **Two sentences, not one, and that is the one place this rule is not single.** A torn group is
    fixed by widening the loop until it holds all of the group; a group carried with ink it does not
    own by narrowing it until it holds nothing else. A single notice would have to say "wider or
    narrower", which is not an instruction, and the owner's requirement of both refusals is that they
    name the way out. So `CanvasNotice.animationGroupNotAlone` reads *"The loop holds an animated
    group and ink that isn't part of it — a group moves on its own, so loop around just one group."*

    **Refused at the lift** for §2.29's reason, and **refused rather than narrowed to one of the
    groups**: choosing which of them the artist meant is a Move on ink they did not point at.

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

**The identity is reachable now, and half of it had never been drawn.** A minted group is called
"Group 1" by a count, and `poseChannelName(_:)` draws that over the curve in the graph editor's channel
list — so a document with four of them offered four rows differing by a number.
`CanvasManager.renameAnimationGroup` is the writer and a long press on the group's header is the way in.
**`tagColor` was specified here and displayed nowhere**: the swatch on a *channel* row is
`TimelineGraphBand.colour(forDescriptorIndex:)`, the band's curve colour, which is a different thing
keyed on a different input. The group header draws the tag now. **What is still missing is membership
editing** — adding an element to a group or taking one out — and it is not a UI gap but an unruled one:
§2.29 settles that splitting one animated group into two is *"a different feature"*, and retagging is
that question from the other side, since every key on both tracks changes meaning. §2.11's *"reassignable
by a tap"* is one line and its consequences are not settled; it needs a design conversation.

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
  there and on `FolderManifest`, same idiom, same absence-is-the-migration.** **And so does the
  container pose's own held baseline, which is a *third* place rather than an entry in
  `pendingBaselines`**: that dictionary is `[String: Double]` keyed by `EffectParameter.id`, and every
  effect writer that walks it prunes it against the grade's descriptors, so a pose stored there would be
  either unnameable or thrown away. `LayerPose.baseline` is nested beside the track for `LayerPose`'s
  own reason — one channel, fixed shape — and rides `LayerManifest.transform`, which already persists.
  The baseline is the one
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

**Invalidation is free.** `SandwichKey` (`Views/CanvasView.swift`) already carries the resolved
`[RenderNode]` **and** the frame, and `FrameBakeKey` (`Engine/FrameBakeKey.swift`) encodes the same tree
field by field with no frame at all. `RenderNode` is `Equatable` and its `effect` field is compared
verbatim, so a per-frame-resolved effect moves both with no new plumbing.

**The template already exists and says so.** `ValueFill.resolvedColor(atFrame:)`
(`Models/Layer.swift:203`) is `{ color }` today, and its doc comment cut this seam deliberately:
*"a keyframe phase would then have to cut this seam under a deadline instead of finding it already
cut."* `Effect.resolved(atFrame:)` is the same shape one level over.

**The cache that actually moves is not the one it looks like.** `SandwichKey` carries `frame`
outright, so two keys at two frames differ *whatever* the tree says — a test that compares them across
frames passes on unmodified `main` and proves nothing. Pin it by holding `frame` **equal** and deriving
the tree at two different frames. `FrameBakeKey` has the opposite shape and needs no such care: it
carries no frame at all, deliberately, so the resolved tree is the *only* thing that can separate two
frames — which is what makes a hold one file on disk and what makes the frame-resolved effect
load-bearing there. And the cache where staleness would actually
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
`RenderTree.peakCompositeTextures` (`Models/RenderTree.swift:543`) is frame-invariant **only for as
long as a key cannot turn an effect on or off**; it branches on `node.effect != nil`, and the strip
planner, the chunk planner and `MetalCompositor`'s admission gate all spend its answer — so the day a
track can add a grade, how a frame is cut up becomes a function of the playhead, and a document
measured at one frame is sized for another.

### 4.2 Posed ink: bake the dab walk in rest space

**BUILT 2026-09-02 as stage 4, and four of this section's claims did not survive contact with the
code.** The construction itself did, exactly: walk in rest space, map each finished dab's centre,
scale its radius by the local area root. It landed as `BrushStamper.DabPose` / `PosedDabTarget` /
`CollectingDabTarget` / `bake` / `replay`, a non-persisted `VectorStroke.restWalk`, and
`VectorCanvas.posing` beside `mapping(_:throughStretch:)`. What was wrong:

1. **"The per-frame walk arithmetic disappears."** It does not, in the form that shipped. Wrapping
   the *sink* rather than the walk is what makes the dab count, phase, RNG, grain and sub-lattice
   invariant — the walk still runs per frame, in rest space. Making it disappear needs the bake
   **memoised per stroke**, which is a cache and therefore PERFORMANCE.md's business, not this
   stage's. The invariance and the saving are two changes and this section reads as one.
2. **Square is not the everyday second artifact; the Pencil is.** MEASURED over 24 frames of a
   uniform 1.0 → 0.3 shrink: `BrushLibrary.square` produces **one** sub-dab count *before* this stage
   as well as after, because its `spacingFraction` is **0.15** — 3.6 pt at 24 pt, clear of
   `stampSpacing`'s 1 pt floor down to scale 0.278, and clear of the sixteen-circle approximation's
   own two floors at 0.3. (That approximation is gone — BRUSH.md §12 stage 3 — so the sub-lattice
   half of this finding is now moot as well as false.) The mechanism this section names is real; the
   exposure is not. The brush that
   re-phases on **24 frames of 24** is the Pencil (`spacingFraction` 0.04) — which is also the grain
   brush, so §4.2's two named non-round-dab cases are one brush. Hard Round (0.05) gives 19 of 24.
3. **A *pure translation* re-phases the walk too**, which nothing here or in §8 predicted: 110 dabs
   on some frames and 111 on others across 24 frames of a translate-only pose. A translation
   preserves every distance, so the count "cannot" change — and `Int(distance / spacing)` sits on a
   knife edge that translated coordinates land on either side of. There is no map mild enough to be
   safe, which strengthens the case for this section rather than weakening it.
4. **§2.16's Move consequence is not delivered and cannot be by this construction.** *"A stroke you
   Move keeps its grain instead of re-sampling"* describes a multiplier **stored at draw time**. What
   shipped derives it in rest space per render, so grain is invariant across the frames of a *pose*
   and still re-samples under a *committed* Move — the commit rewrites the stored samples, so the
   rest space itself moves. Storing it would be ~8 floats per stored sample (a 110 pt stroke walks 92
   dabs from 12 samples) for a value that is a pure function of position, which is `VectorStroke`
   `precise`'s own argument against a second copy of a derivable fact. **The headline ruling is
   delivered; the parenthetical is declined, in writing, at `mapping(_:throughSimilarity:)`, and the
   owner has since ruled the decline stands** — grain is expected to change with the brush overhaul
   that makes brushes importable, so TODO (37) inherits it.

Two things this section got exactly right and they were the load-bearing ones: **no `VectorSample`
change, no wire-format change, no decode migration** (`VectorStroke`'s hand-written coder names every
key, so `restWalk` is off the wire by construction — pinned by encoding one stroke with and without
it and comparing bytes), and **build the pose as a point map** — `DabPose` wraps a `Homography` and
short-circuits the affine case through `affine()`, so stage 5b changes what *builds* a pose and not
one line of what consumes it.

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

**The problem it dissolves is Distort's, not Freeform's**, and §8 carries the measurement. An affine's
`|det|` does not vary with position, so under a Uniform or a Freeform pose the single scalar
`VectorStroke.size` already *is* the per-dab area root, and `mapping(_:throughStretch:)` already writes
it. It is a homography whose `|det J|` varies across one stroke, and that is the case no scalar answers.

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
- **Square and custom brush shapes** used to re-derive a sub-dab grid from the posed diameter with
  1 pt floors, so they could shimmer where the round built-ins do not. **Measured false for the
  shipped Square over an ordinary shrink** — see finding 2 above — and then **moot**: BRUSH.md §12
  stage 3 replaced the grid with one `stampImage` of an alpha mask, so there is no sub-lattice left
  to re-derive. What replaced it is baked the same way and needs no special case: the walk runs in
  rest space and the pose maps the finished dab, turning its **angle** as well as moving and scaling
  it, which the sub-lattice never had.
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

**COMPLETE — the model, the render path, the cache safety and, since the entry pass, the artist's way
in.** What that pass added is below; the model pass's own findings follow it.

#### The artist's entry — the menu, the Move box and the writer

**Creating one is §2.6's relabelled menu doing exactly what §2.6 says it does.** The value layer's row
title now follows what is set — Blend Mode / Effect / Transform — and a Transform section of one entry
makes the layer a transformation layer through `CanvasManager.setLayerTransform`. It is the third
payload on the same recipe, and the accessors were already written for it: `Layer.layerTransform` is
`kind == .value && effect == nil ? transform : nil` and `valueFill` was already gated on
`transform == nil`, so nothing about the discriminant had to be invented. **The two ways out differ, and
that asymmetry is load-bearing**: picking a grade leaves the pose stored and inert (that `effect == nil`
clause takes it out of force, so flipping back restores the move *and its keyframes*), while picking a
blend destroys it, because `valueFill` has no clause left and a layer that kept its pose would answer
"transform" to the renderer with the artist's tick beside Multiply.

**Moving one is the Move box, with three things that are new.** `FloatingPieceKind.containerPose` is a
piece that carries no pixels: a container holds no geometry, so the box is *the canvas frame*, which is
the fallback `beginMove` already takes for a cel with no opaque pixels in it. **The preview is the real
render path** — `showContainerPoseLive` writes the pose on every tick and the canvas composites through
it — because §2.3's whole content is that the content beneath is re-posed rather than resampled, so a
bitmap preview would be a picture of the wrong feature. And **the commit puts the preview back before it
routes**, since `commitContainerPose` reads the stored pose to take its undo baseline from; without that
line one press of Undo leaves the drawing exactly where the artist had just dragged it.
`FloatingPiece.containerRest` carries the whole `LayerPose` the lift found, which is also what lets a
second Move compose onto the first instead of replacing it.

**Every arm of the writer writes the stored base, and that is the one real difference from a cel
channel.** `commitTransformPose`'s `.key` arm *takes the bake back* because a cel has no stored base and
the render composes geometry x pose. A container has one, and `LayerPose.resolvedPose(atFrame:)` is a
**precedence** — the track when it holds keys, the base otherwise — so nothing is doubled and §2.27's
*"the edit still writes the stored base, exactly as it always did"* applies unchanged. The practical
consequence is that deleting every key leaves the container where the artist last saw it rather than
snapping it to rest.

**Distort is refused on a container float and says so.** Not for the raster arm's reason — a `PoseQuad`
is four corners and could hold a keystone — but because `affineOrLinearised` would linearise it at the
box centre, which §8 measures as wrong by 315% at the far end. That is §2.13 arriving at the one surface
that could have offered Distort early.

#### Three findings, all of them holes this section could not have predicted

1. **§2.27's held baseline had nowhere to live on a container.** `Layer.pendingBaselines` is
   `[String: Double]` keyed by `EffectParameter.id`, and a pose is neither a `Double` nor addressed by
   one. `LayerPose.baseline` is the field, persisted by the same field-presence idiom, because §2.27
   rules that the gap between A and B can span a save. Without it the owner's canonical A-then-B
   workflow wrote two identical keys and produced no animation.
2. **`removeKeyframe` could not remove a container pose key.** `keyedFrames(of:)` folds them into
   §2.28's union — so the timeline *drew* a keyframe — but `poseDeltaClearing` walked the layer's cels
   and nothing else. The artist's tap took the mark it did not have and left the key it did: the
   drawing kept moving with the marker gone, which is report 1 of the two §2.28 was written from,
   arriving through a fourth door.
3. **And `addKeyframe` could not hold one.** The same walk, so §2.24's surviving half — *"every channel
   that already carries a curve takes a key at the new mark"* — skipped the container, and a mark placed
   halfway through its move let the move run straight through the keyframe placed to stop it. Both are
   fixed by `KeyframePoseDelta` gaining a `container` arm, **and it serves the folder too**, which
   neither producer reached at all because both bailed on a folder target before their first line.

**§11.7's `raisesMoveBox` note is kept rather than deleted.** It said *"the day that Move exists, this
returns true and nothing else changes"*; it returns true, and one other thing changed —
`revealPoseChannel` had routed every channel through `beginVectorChannelMove`, which lifts geometry a
container has none of.

#### A fourth finding, from the owner's own iPad: the entry was closed on itself

The three above are holes in the machinery. This one is the machinery being complete and **unreachable**,
and it is the more expensive kind because every test we had passed over it. The owner installed the build
and asked *"i selected the transform mode, now how do i use it? there is nothing in the graph editor. Im
not even sure if the feature is implemented fully."*

**Move was already the verb and nothing on screen said so.** `CanvasManager.beginMove` routes a posing
layer to `beginContainerPoseMove` — so the toolbar button worked — but `LayerPanel` rendered
**`EmptyView()`** for transform mode, with a code comment saying the pose *"is authored with the Move box
on the canvas"*: a sentence written for us and never shown to the artist. The one affordance that *did*
say so was §11.7's channel row, and that row cannot exist yet: `listedAnimationChannelIDs` lists a pose
channel only when two of its keys hold different poses, and only a Move can put those there. **You had to
use the feature to be told how to use it.** The fix is one row in the value layer's options —
`LayerPanel.transformMoveRow`, the toolbar's own move glyph, calling `beginContainerPoseMove` directly.

**And underneath it there was a genuine silent refusal, which is the reason the row alone would not have
been enough.** `beginContainerPoseMove` required `activeCelIndex(inLayer:atFrame:)` — but `addValueLayer`
stamps one block of `max(sceneFrameCount, 1)` frames **at creation** and never extends it, while
`sceneFrameCount` goes on ratcheting up as blocks are added elsewhere. Add the transformation layer to a
fresh 12-frame document, draw out to frame 30, park the playhead at 20, and the layer had no block there:
`beginContainerPoseMove` returned false, `beginMove` discarded the result, and there was no float, no
highlight and no `CanvasNotice`. **The gate is deleted rather than repaired, because there was nothing to
refuse.** A container pose lives on `Layer.transform` in absolute document frames and
`RenderTree.renderNodes` composes it with *no cel test at all*, so the layer poses everything beneath it
at every frame; the box was being refused at frames the renderer was posing at. Extending the cel
(`ensureCelAtCurrentFrame`) would have minted a stray one-frame block in the timeline — and moved
`contentEndFrame` with it — for a payload that is not cel-scoped; a notice would have announced a refusal
with nothing behind it. `FloatingPiece.sourceCelID`/`targetCelID` are optional now and nil for a
`.containerPose` box, which is the honest statement of the same fact.

**What the deeper version of that would be, and why it was not taken here.** The cel gate is spurious only
for transform mode. `leafSnapshots` gates *every* leaf on `activeCelIndex`, so a value layer in the other
two modes — flat colour, and §4.4's grade — genuinely stops contributing past the end of the block it was
created with. That is filed in BUGS.md rather than fixed here: it is a rendering change touching every
adjustment layer in every document, and it wants its own pass.

**A third thing, found only by trying to drive it.** The Transform entry sat at the bottom of its menu,
below the thirteen-item grade catalogue — which is **past the point where an accessibility client can see a
menu item at all** (BUGS.md's *"The effects menu only exposes its first few items to XCUITest"*, a
scrollable-menu limit rather than an app defect). An artist scrolling by hand could still reach it, so it
was never a wall for them; it was a wall for every UI test, which means **the one entry point to this whole
feature could not be driven by anything but a human**. That is the same blindness that let the feature ship
unusable, one layer further out. The Transform section is above the catalogue now: two of the row's three
answers are single picks and the third is a list of thirteen, so putting the list last is what keeps the
other two in reach.

**The acceptance bar this changes.** Every test in the repo reached the model and asserted stored values,
and a feature can be perfect at that level and unusable. `LayerPanelControlsUITests.
testTransformModeOffersAMoveRowThatRaisesTheBox` asserts what is on the screen — the row exists, tapping it
raises the box, and the app's own two reports of a live Move agree — so it goes red if the affordance
disappears while the model stays correct. `TransformLayerEntryLogicTests`' cold-start section starts from a
document in the state the app actually creates, rather than from a fixture that has already been told the
answer.

#### What the model pass found

**Six findings, and the construction itself survived exactly — accumulate down each container, emit per
layer index, stamp ink at the posed position. Four of the six are claims this section makes that are
false against the code; two are things it does not mention that turned out to be half the work.**
`Layer.transform` and `LayerFolder.transform` are both a `LayerPose` (a stored `PoseQuad` plus a
`TransformTrack` in §3.1's absolute document frames); `CanvasManager.renderTreeAndPoses(atFrame:)`
accumulates the pose down each container and emits `[layerIndex: CGAffineTransform]` beside the tree.
What was wrong:

1. **"`FrameRecipe.resolveSources` maps the cel's elements through it."** It cannot. RENDER.md §3.2
   cut `renderSources` in two after this section was written: `resolveSources` is pass 2, it runs on
   `PixelOps.parallelMap`'s workers over `LeafSnapshot` values, and it may not read `layers` at all.
   The pose is spent one step earlier, in **`leafSnapshots`** — which is where the frame, the layer
   index, the derivation and the freeze are all already in scope, and which is therefore the only
   place all three consumers can be fed from one value.
2. **"…and hands the posed display list to `renderLocalContent(elements:)`."** There is no such
   consumer on this path. The `CelContentProvider` seam (VECTOR_INTERPOLATION item 18) landed in
   between, so a posed cel is a `DerivedCelContent` whose thunk renders a whole `VectorCanvas` — and
   `CanvasManager.posed(_:through:inheriting:)` is the one line that had to change.
3. **"Two placed-object refusals ride along."** Stale. The `assertionFailure` at
   `VectorLayer.swift:2247` is gone and `canBeStretched` does not exist: LASSO_MOVE.md stage 3c gave
   `VectorImageElement` a stored shape (`aspect`, `stretchAxis`, `mirrored`) and
   `VectorCanvas.placed(_:through:)` composes and re-decomposes an arbitrary affine through it. A
   photo under a transformation layer travels with the strokes around it, so **the refusal this
   section asks for is not built, deliberately** —
   `TransformLayerLogicTests.testAPlacedImageFollowsAContainerPoseRatherThanBeingRefused` pins the
   behaviour that made it unnecessary.
4. **"It is an arity-1 `CompositorOp`, the shape the existing effect node already takes."** It is
   not, and the difference is the whole reason §4.5 exists. An effect node reaches the compositor as
   `RenderNode.effect`; a pose **never reaches the compositor at all**, because the only thing a
   compositor can do with one is resample the pixels it was handed, which is what §2.3 refuses. The
   transformation layer is a leaf that contributes no pixels — elided by `leafSnapshots` exactly as a
   grading layer is — and whose entire effect is spent before rasterisation. The observation that
   *survives* is the one about the menu (§2.6): it is a third payload of a `.value` layer, beside
   `effect` and `fill`, on the same "presence is the discriminant" recipe.
5. **The refusal this section did not predict is the *interpolated* cel.** §2.18 says a derived
   in-between has no stable elements, and `InterpolationEvaluator.render` answers with an image rather
   than with the elements a pose maps — so there is nothing for "re-poses the vector objects" to act
   on, and the alternative is the bitmap magnify §2.3 refuses. An in-between under a transformation
   layer keeps its evaluated ink where the cel drew it (its *stored raster* tiers still move, by
   §2.12's other currency). Stated at `derivedCelContent` and pinned.
6. **And §2.12's raster half is not a footnote to this section, it is half of the implementation.**
   `PixelOps.rasterizeUncached` lets a derivation replace the *vector* tier only and draws the baked,
   stroke and fill tiers beside it, so re-posing vector objects moves exactly one of four tiers.
   `PixelOps.FrozenCel.pose` carries the same affine onto the other three as a CTM. That is the
   ruling working correctly — "a raster layer softens under a push-in while the vector layer beside
   it stays sharp" — but it is two mechanisms, not one, and this section describes only the first.

§2.3 and §2.12. It is **not** a blend mode and cannot be: all 25 modes are per-channel colour functions
over two same-size, same-position images, with no positional argument anywhere in either backend's call
chain. It is an **arity-1 `CompositorOp`**, the shape the existing effect node already takes. §2.6's
relabelled menu is what makes that invisible to the artist — the value layer's menu already merges blend
modes and effects into one list, so a third kind of entry there is consistent with what ships.

**Scope is already defined and reusable verbatim**: a value layer with an effect grades *"everything
beneath it inside its own container"*. A transform layer uses the same rule.

**Where the pose is applied.** `renderNodes(atFrame:inContainer:)` accumulates a `Homography` down each
container using the same `below` / `containerIsNode` scope machinery it already has, and emits
`[layerIndex: Homography]` alongside the tree; `FrameRecipe.resolveSources` maps the cel's elements through it and
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

**BUILT 2026-09-03, and this section was right about the danger and wrong about the count: it is
three keys, not two, and the two it names were already half-safe.**

- **The two it names already carry `DerivedCelContent.identity`**, which stage 5 put there for the
  cel-scoped channel. A *vector* cel's container pose rides in `PosedCelIdentity.inherited` and both
  keys move for free. So the sentence below is false as written and the field that was actually
  missing is elsewhere.
- **A cel whose ink is in the raster tier has no derivation at all** — `posedCelContent` answers nil
  without a `vector` — so for that leaf the pose reaches neither key by any route, and the failure
  arrives in exactly the form described. `PixelOps.FrozenCel.Identity.pose` and
  `LayerContentVersion.pose` are the two genuinely new fields, and both are pinned over a **raster**
  fixture for that reason; a test written over a vector cel is green with either of them deleted.
- **The third key is `FrameBakeKey`, and it is the one no compiler could have caught.** That file's
  rule 1 — no `default:` anywhere — turns a new *enum case* into a build error; a new *stored
  property* on `LayerContentVersion` is not a build error anywhere, and the hand-written walk simply
  stops naming it. A content-addressed store has no second chance: two frames of a move resolve to
  one file and it serves the first frame's pixels for the whole move. MEASURED by mutation — deleting
  that one line compiles and reddens exactly one test.
- **And a fourth cache is reached through the identity rather than through a key of its own.**
  `CanvasView.updateInterpolationPreviews` builds `InterpolationPreviewKey` out of
  `DerivedCelContent.identity` alone, so `PosedCelIdentity.inherited` is what stops the live canvas
  freezing on the first posed frame while every export of the same frames moves.

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

> **The cache is specified in [RENDER.md](RENDER.md) §3.5-3.7 now; this section's rulings (§2.19, §2.20, §2.25) stand
> and its store is that one.** Its claim that `LayerContentVersion` propagates dependencies is wrong: it is a flat
> per-leaf value.

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

**And it must key on `RenderResolution`.** `SandwichKey` and `FrameBakeKey` already do
(`Views/CanvasView.swift`, `Engine/FrameBakeKey.swift`) and their comments say why in the words to
reuse: otherwise the setting becomes *"a control that visibly does nothing when you use it"*. Note what
that setting reaches — the on-screen live composite **and the on-disk bake**, which mint at one size
(`liveCompositeSize`, `RenderSizing.liveComposite`) so that they share one flatten memo, with a
directory per resolution under the bake root. It does not scale the flatten, the thumbnail or the saved
package, and RENDER §2.8 rules that export resolution *is* this knob's value. A preview-resolution span
cache is therefore consistent with what the control already means; a full-resolution one is a different
tier.

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
**BRUSH.md §12 stage 4 has since put timing in the record** — one byte of Δt a point, and no migration,
because the record became a channel set rather than a fixed struct. A guide still reads the absolute
timestamp beside the sample; what changed is that "a stroke cannot carry time" is no longer true.
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
TODO (28) names for audio, so it is worth doing once and properly. And an fps stepper that only
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

**A range bake is also (29)'s exporter.** TODO's "Later" section notes both are "evaluate the document at frame N,
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
| **3b** ✅ | **The keyframe marks, the channel panel and the graph-editor drawer** | §2.26 and §2.27, and §11's D1 through D4. The **model** half: `keyframeMarks` and `pendingBaselines` on both grade homes, persisted by field presence; `addKeyframe` / `removeKeyframe` / `clearKeyframes` in `KeyframeControl.swift`, one undo step each; and the five-arm routing rule. **The cel menu and the marks' timeline form** — Add / Remove / Clear Keyframes on the block menu, addressing the tapped block's layer at the frame the request carries (the playhead, captured when the menu is raised, because playback does not stop for a menu); and `TimelineKeyMarkers.markers` is the **union** of marks and curve keys, and there is one form of marker: §2.28's closing rule, which let a mark and a key both live at one frame, is superseded. **The grade gates the curves and does not gate the marks** — a mark on an ungraded layer is where the workflow starts, so `TimelineLayoutKey` passes `[:]` for the tracks and the marks in full. **The drawer** is `TimelineGraphBand`, drawn by `TimelineTrackView`'s coordinator inside the scroll content (§11.1) and sized through `CanvasManager.graphBandExpansion` in the layout key — not a presentation of any kind. **The channel panel** is `TimelineGraphChannelList`, raised from `timeline.graphChannelsButton` and presented as `CanvasPresentation.graphChannelList`; §11.5 is why it is a filter rather than a navigator. §2.22's keyframe button became the graph-editor button, which is why the marks are placed from the cel menu. |
| **4** ✅ | **The rest-space dab bake + grain** — built 2026-09-02. | §4.2 and §2.16, and §4.2 now carries the four of its own claims that contact with the code refuted. Engine-only, as predicted; every number in it was taken on the standalone `swiftc` loop at ~4 s a cycle. **The test written to go red did not go red, and could not have** — `testGrainReSamplesUnderAPoseWhichIsTheArtifactStageFourRemoves` compared `grainAlphaMultiplier` at a stroke's rest samples against its *posed* samples, which is the position-dependence of a noise field rather than any behaviour of the ink; the posed display list still carries posed samples after this stage, because §4.2 requires it to. It is rewritten as `testGrainTravelsWithTheInkUnderAPose` and compares the **dab alphas** two poses of one stroke actually stamp. `RestSpaceDabBakeLogicTests` is the engine half. **What this unblocks is real**: `DabPose` answers `localScale` per dab, so stage 5b's projective ink has per-dab width. |
| **5** ✅ | **The transform channel** — merged `4e18b7a` and the test commits after it. | Quad keys (`PoseQuad`, box plus four corners, which stage 5 only ever writes as parallelograms), animation groups, §2.5's write-at-commit — `commitVectorFloatIfNeeded` and not the nudge — and §4.3's factored blend in `Engine/Deform/PoseInterpolation.swift`. Ink is posed through `mapping(_:throughStretch:)`, the `sqrt(|det|)` arm. §2.10's `step`, §2.27's held baselines, §2.28's keyframe union, §3.5's `_anim.json` sidecar and §4.5's cache trap all land with it, the last pinned by mutation. ~~**Two things it does not have**: there is no graph-editor band for a pose channel, and animation groups have no UI — names and tag colours are generated.~~ **Both closed**: §11.7 is the band, and §3.4's identity is reachable — the channel-list header draws the tag colour and renames the group. Membership editing is what is left of the second, and it is unruled rather than unbuilt (§3.4). The third, *Move is refused at a frame whose pose is not resting*, is **done 2026-09-03** and is the entry below. |
| **5a** ✅ | **Move at a posed frame** — the owner's *"trying to move an object from A to B, then try to select it in an inbetween, it does not let you"*. | The refusal was `activeVectorMoveTarget`'s `celPoseIsResting` guard, and its argument was sound: the box was measured on stored ink while the cel showed a derived picture. **Relaxing it alone would have been strictly worse than the refusal** — the lasso was rest-space-blind too (`localPath(fromCanvas:)` maps through `_transform` and nothing else), so a loop drawn around visible ink would have selected the wrong elements *silently*. Both land together. `VectorFloat.poses` is the pose each lifted element is shown through; the box is `MoveBoxInk` of the posed ink, the loop is pulled back per element (`LassoLoops`, exact because containment and the boolean ops commute with an invertible affine, which is what lets the *split* stay on stored geometry), every nudge is conjugated `P·D·P⁻¹`, and the latch renders `renderIsolated(ids:posedBy:)`. **The commit is §2.27 rather than a new ruling** — *"if it isnt a current keyframe the drag creates a keyframe at that frame… only when the value is already being animated"* — so it is the `.key` arm the refusal had made unreachable, with the delta conjugated onto the channel as `M · O · D · O⁻¹` for the channel's own map `M` and whatever is applied after it (`O` is the cel map when writing a group, the identity for the cel itself). Both reduce to `D` on an unkeyframed document, so an ordinary Move is byte-for-byte what it was. |
| **5b** | **Real Distort** — the *animated* one, a projective quad keyed across frames | §2.13. **Not to be confused with the Move-box Distort that shipped** (LASSO_MOVE §3 stage 5): that is a raster floating piece reshaped by a live gesture, and nothing keys a projective quad over time — `TransformKeyframes` only ever writes a `PoseQuad` built from a `CGAffineTransform`, and `PoseQuad.affineOrLinearised` treats a projective pose as something only a document *this* stage wrote could contain. Ink through §4.2's point map, then placed images behind Move stage 3c. |
| **6** | **Bake to cels** | §6. Shares its frame-walker with TODO (29). |
| **6b** | **The playback cache** | **Delivered by TODO (29) instead**, and this row is a cross-reference rather than work: §4.6's store is RENDER.md §3.5-3.7, whose stages 4 and 5 are merged, so playback is served from LZ4 frames on disk today. What it is *not* is §2.20's span-scoped unit — it is a per-frame content-addressed store with playhead-distance eviction. Read RENDER §3.5-3.7 before planning anything on this row. |
| **7** | **Live recording + editable fps** | §5. Its one prerequisite is met: the playback clock is on the model (`Engine/PlaybackClock.swift`, RENDER stage 1). Nothing else of it exists — `fps` is fixed at 24 and only load and save write it. |
| **8** ✅ | **The transformation layer** | §4.4, complete: the model and the render path, then the artist's entry — §2.6's relabelled menu, a Move box that previews through the render path rather than a bitmap, and `commitContainerPose` routing through `KeyframeControl.write`'s same five arms. Three holes fell out of making it reachable and all three are in §4.4: §2.27's baseline had nowhere to live on a container, and neither `removeKeyframe` nor `addKeyframe` could see a container pose key — the second of those had been drawing a keyframe indicator the artist could not delete. **`LayerFolder.transform` still has no entry**, and it is a row in the folder options menu plus the same box, not new machinery. |
| **10** | **The timing recorder** | §7. Small, sits on 7. |

**Stage 5 comes before stage 4, ruled by the owner 2026-08-30.** Asked whether the effort should go to
stage 4 or to stage 5 — given that §4.2 says in its own words that the rest-space dab bake is *"not
rescuing a visible defect and must not be scheduled as though it were"* — the owner answered *"keyframe
stage 5 comes first."* Stage 5 is the transform channel, which is where the feature becomes something an
artist can see: keyframed movement.

**What makes that schedulable rather than merely preferred is the owner's own earlier ruling.** §4.2's
construction exists to remove the per-frame shimmer of re-walking the dab lattice under a non-uniform
map — and the owner checked that shimmer on the device against a build of `main` and said *"the
interpolation shimmer seems fine for now, I can't notice it… disregard for now."* So stage 5 may pose ink
through the path that ships today and accept an artifact the owner has already accepted, rather than
blocking on stage 4 to avoid it.

**And the width rule costs stage 5 nothing, because a pose stage 5 can store is affine and an affine's
area root is a constant.** `mapping(_:throughStretch:)` already computes LASSO_MOVE §5.17's rule verbatim
— `sqrt(abs(t.a * t.d - t.b * t.c))` into `stroke.size` — so the ink follows a Uniform or a Freeform pose
with no new machinery at all. It is not an approximation that improves toward the similarity limit: for
an affine, `|det|` does not vary with position, so the single scalar `VectorStroke.size` carries **is**
the per-dab local area root at every dab. MEASURED over eight poses — uniform, axis-aligned Freeform, and
Freeform about a hand-turned box — sampled at 41 points along a diagonal stroke,
`Homography.localScale(at:)` holds `max/min == 1.0` to seventeen digits on every one of them and sits **0**
away from `sqrt(|det|)` in double precision. `tools/pose_width_ab.swift` is the harness, compiling the
shipped `Homography` and `Quad` unmodified, and carries every other figure below. Two further identities fall
out and are worth keeping because they make the channel cheap: `sqrt(|det|)` equals `ObjectTransformFrame`'s
own `transform.scale` exactly for every one of the eight, `stretchAxis` and `aspect` included, so a pure
shape change moves no ink weight; and the stage-5 chain a stored **quad** implies — `Homography(boxSize:to:)`
then `affine()` — returns the width scale it was built from to within **2.2e-16**.

**What needs per-dab width is the projective case, which is stage 5b.** A homography's `|det J|` varies
across the plane, so no scalar can be right: MEASURED over the same stroke, local scale spans **1.3x** on a
mild keystone and **8.5x** on a quad with one corner dragged in, where the best single scalar — the
linearisation at the stroke's midpoint — is wrong by 15% and by 315% at the far end. **§4.2's rest-space
bake is therefore a prerequisite of stage 5b and not of stage 5**, and that is the whole of what "it
dissolves the per-sample-width problem completely" buys.

**Two things stage 5 does inherit, both already accepted.** The **dab walk** is what loses exactness under
a non-uniform map, not the width: MEASURED at Hard Round's own spacing, a 1:1 → 4:1 stretch animated over
24 frames re-derives a different dab count on all 24 of them. It is the shimmer §4.2 describes and the
owner disregarded. And it is **not confined to Freeform** — `stampSpacing`'s 1 pt floor makes a *Uniform*
shrink re-phase too, on 19 of 24 frames for a 24 pt Hard Round animated from 1.0 to 0.3, because the floor
binds below scale 0.833 there. A re-phased walk is invisible on a round dab — no built-in sets `scatter`
or `rotationJitter` — and §4.2 already names the two that are not round dabs, Pencil's grain and Square's
sub-lattice. What is new is that the Uniform arm reaches it too, so "pose through the similarity path and
nothing re-phases" is not available as a fallback.

**Pose ink through `mapping(_:throughStretch:)`, not through the interpolation evaluator.** They are two
per-frame mapped-stroke paths and only one carries the rule: `InterpolationEvaluator.warped` scales
`result.size` by `thicknessFade` alone and never by an area root, which is right for a lattice warp — whose
local scale varies per point, so it is the projective case again — and wrong for a pose.

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

**What stage 5 inherited.** The provider is **frame-aware** already (`CelContentProvider.frame`,
rebindable with `at(_:)`), so a pose channel adds a derivation source and touches no call site a second
time. §4.5's trap is closed for both keys it names: `PixelOps.RasterizeKey` and `LayerContentVersion`
each carry `DerivedCelContent.identity`, and `CelContentProviderLogicTests` pins both — the second by
mutation.

**A pose identity carries the resolved maps, not the frame**, which is the opposite of what this section
prescribed and is strictly tighter (`Models/TransformChannel.swift`, `PosedCelIdentity`). What an
identity owes is whatever `render` reads: two frames that resolve to the same pose *are* the same
picture, so keying on the maps dedupes a hold for free where a frame field would mint an entry per
frame of it — the same argument interpolation's identity already makes for omitting the frame.

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
upward"* to *"it pops up above the layer that has it when on"*. **D1 through D4 are built, §11.6 is
empty, and §11.7 is the transform band on top of them**, so the drawer and the channel panel §8's 3b row
owes are the ones described here. Line numbers
are **gone from §11.2 and §11.3** rather than re-taken: every one they carried was stale twice, and D2
moved all four timeline files again. Name the symbol, not the line — the two sections below now do, and
§11.4's remaining numbers should be re-taken rather than trusted.

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
track. So a layer whose one block covered frames 0–9 could not be given a mark at frame 20 by
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
- ~~**The playhead is a column, not a hairline**, and is left in front because a saturated curve reads
  through the wash.~~ **Reversed by D3 on 2026-08-30 — see §11.4.** The column is still 10.5 to 120 pt
  of 35 % blue, re-fronted on every `movePlayhead`; what was wrong was "a saturated 1.8 pt curve reads
  through the wash perfectly well", which was **true of the one hue it was looked at** and false of
  three of the palette's eight — orange at 28° renders as a grey stub for the column's width. D3 fronts
  the band instead, and the objection recorded here did not survive contact: the band's background is
  white at `backgroundAlpha` **0.06**, so the column stays visually unbroken from the ruler through the
  band to the row below and only the 1.8 pt strokes and key dots lift clear. Verified by rendered
  before/after images rather than by reasoning about alpha, which is how the original claim went wrong.
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

  **And the other half of that clip was wrong until 2026-08-30, which nobody saw because it was
  *correct*.** `sampling` also clips to a `frameCount`, and the caller passed
  `displayedFrameCount(for:)` — the track's own length, which the scroll's look-ahead inflates two
  screenfuls past `sceneFrameCount`. So a curve was sampled across dead track and `AnimationCurve`'s
  constant-hold extrapolation drew a **correct** flat line out there: on a 12-frame document, more than
  half the band. The bound is `TimelineGraphBand.drawnFrameCount(sceneFrameCount:channels:)`, and it
  lives in `Content` rather than beside it, because half its input is in the key (the channels' keys)
  and half is not (the scene's length) — the exact shape that draws once and freezes. It **widens** for
  a key past the end of the scene: `moves` clamps at a neighbour and at frame 0 and at no upper bound,
  and `sceneFrameCount` grows only from cel edits, so such a key is reachable and would otherwise be
  drawn nowhere while still being grabbable. `tap` takes the same bound, `nearestChannel` naming a
  curve by proximity to the *drawn* line. `docs/graph-editor/5-*` is the pair.
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

### 11.4 Stage D3 — the gestures — **done 2026-08-29, both halves**

**A key drags on both axes, a tap on one removes it, a tap on a curve adds one, and a rubber band in
empty space picks up a set that then travels as one body.** Two commits in that order, because the
first has to stand on its own.

**`TimelineKeyMarkers.frame(atX:pixelsPerFrame:)` has its first caller and its doc's blocker is
settled.** It is reached through `TimelineGraphBand.frameDelta(translationX:pixelsPerFrame:)`, which
asks it *once at frame 0* rather than once per key, because the answer is exactly delta-invariant:
`frame(atX:)` floors and `centerX` offsets by half a column, so `frame(atX: centerX(f) + dx) − f` is
`floor(0.5 + dx / pixelsPerFrame)` for every integer `f`. That is what lets one number carry a whole
group rigidly, and it is why the drag keeps the **grab offset** rather than resolving from the touch's
own x the way `CurveEditor` does: a finger may take a key from 22 pt away, which at the pinched-out
10.5 pt per frame is two frames of teleport on touch-down.

D2's `time(atX:)` is untouched and remains the sampler's. Both inverses exist and neither has moved.

**Where `require(toFail:)` went, and the arbitration in full.** In `layoutGraphBand`'s
`graphBandView.superview == nil` block, which runs exactly once per coordinator — the band is
*hidden* when the editor closes, never removed — beside the one `addTarget` for the same reason: a
second one fires the handler twice per touch and opens two brackets for one drag. §11.3 was right
that the existing two calls are inside `relayout()`; this is a third of the same shape.
The recogniser is a `UILongPressGestureRecognizer` with `minimumPressDuration = 0`, which is
`TimelineRulerView.panRecognizer`'s configuration exactly and this file's UIKit spelling of
`DragGesture(minimumDistance: 0)`: it begins on touch-down, so a tap arrives as a began/ended pair
with no travel, and it holds the touch for its whole life, which a `UIPanGestureRecognizer` would not
do until ~10 pt — three times `tapSlop`. Everything else falls out of where the band sits: it is a
**sibling** of the row pool, so a row's pan, tap and long press are on views the touch never reaches;
the pinch is two-touch on `contentView` against this recogniser's one, the coexistence the ruler
already relies on; and the playhead is already `isUserInteractionEnabled = false`, so a key under
120 pt of blue is grabbable — that was checked rather than assumed.

**The cost is that a finger on the band no longer scrolls the timeline.** Deliberate, and the marquee
is what spends it: §11.4's ruling makes the rubber band *the* meaning of a drag in the band's empty
space, so there is nothing left for the scroll view to pan from. The ruler and every cel row still
scroll, so what is given up is a 96 pt strip and not the gesture.

**Three decisions the stage had to make, none of which the brief settled.**

- **A key is stopped by its neighbour rather than consuming it.** `setKey` replaces on collision, so
  travelling onto a neighbour's frame silently destroys it — a destructive edit made by a continuous
  gesture, where "put it here" and "overshoot" are the same movement. `CurveEditor.moving(_:to:)`
  already answers this exact question this exact way, an epsilon at a time, for the identical reason
  (`MonotoneCubic` drops a duplicate x). Clamping is also the only one of the two answers that is
  **visible**: the dot stops under a finger that is still going, which reads as a wall, and it needs
  no confirmation and no second undo entry. The same clamp puts the floor at frame 0.
- **A drag clamps to `modelDomain` and never to `uiRange`, and a key above the axis is drawn nowhere.**
  `Effect.swift` says to draw the axis over one and allow a key anywhere in the other; decision 3 of
  §11.3 is the drawing half of that sentence, so the band cuts an out-of-range key exactly as it cuts
  the line through it, and the picture stays coherent — the curve leaves the top where the dot did.
  Neither of the alternatives survives its own consequence: rescaling to admit it is decision 2 undone
  once a frame, and a marker pinned at the rim is a *handle reporting a value no key holds*, which
  §11.3 already refused for the step stem. What that leaves is a key that cannot be grabbed back, so
  **hit-testing measures the key's y clamped into the band** — one line, `reachableY` — and an
  out-of-range key is reachable from the rim of its own column. Inside the axis it is the identity.
- **One drag is one press of Undo, and it is `beginStructureGesture` that makes it so.**
  `setEffectParameterTrack` records one step *per call* and the drag calls it on every `.changed`
  tick, so the bracket is the whole of the arithmetic: opened on the **first real movement** rather
  than at touch-down (`CurveEditor`'s rule — a drag that never moved closes no bracket because it
  never opened one), and closed with `commitStructureGesture` only if a write actually changed
  something, because `recordStructureChange` records unconditionally and would otherwise leave a step
  that undoes nothing. A cancelled drag restores the starting curve *before* dropping the bracket:
  `cancelStructureGesture` throws the baseline away without recording, so "record nothing" and
  "change nothing" have to be arranged separately. A tap needs no bracket, being one write.

**The marquee, and the two things it forced on the arithmetic that a single key never would have.**
A drag that begins on no key is a rubber band; the keys inside it become a standing selection that
survives the gesture, and grabbing *any member* of it then carries the whole set — which is why it is
two gestures rather than one compound one, and why the selection is view state that dies with the band
(§11.5's rule for channel visibility, reached from the other side). It uses `reachableY` for
membership, the same y the single grab does, so "what this gesture can reach" is one rule rather than
two: a key above the axis is reachable by both or by neither. The two consequences:

- **The group is clamped by its tightest member, not per key.** One `frameDelta` for all of them,
  intersected with each carried key's own allowance against the keys that are *not* selected — a
  per-key clamp collapses the selection onto whichever member hit a wall, and dragging back does not
  restore its shape.
- **Vertically the group shares a travel in *points*, not in value**, mapped through each channel's own
  axis. Per-channel normalisation (§11.6) makes a point of band a different number of units in every
  curve, so a shared value delta would carry a 0…1 opacity off the top while a 0…500 blur radius
  visibly did not move.

And one that is invisible until it bites: `applying` removes **every** carried key before inserting
any of them, because a selection sliding into the frames its own leading edge just vacated is the one
case where the neighbour clamp is silent — the interior of a rigid group never blocks itself, so
`setKey`'s replace-on-collision would eat a member with nothing to see.

**§2.28's union follows for free, and that was verified rather than assumed** — end to end, by a real
finger. `GraphEditorGestureUITests.testDraggingAKeyMovesItAndTheKeyframeUnderneathItFollows` drags the key at
frame 0 and asserts the marker band a row up goes from `0|6` to `N|6`: the diamond moved with the
key, and the frame it left kept the artist's explicit mark and went **hollow**, which is exactly the
two-kinds distinction §2.26 exists for. Nothing writes a mark; the accessor computes the union, which
is the whole point of it.

**What a `Channel` gained**, and it is the only widening of D2's key: `modelDomain`, so the clamp a
gesture applies is keyed like everything else the band decides rather than re-derived from
`Effect.parameters` inside a recogniser. All the hit arithmetic is on `TimelineGraphBand` itself,
which is already in the test target — **no new file, and therefore no `project.pbxproj` entry and no
object id to collide with anyone's.**

**One thing found and left — settled 2026-08-30, and it is the listed-but-flat state.** Tapping away a
channel's second-to-last key makes the curve stop satisfying `isAnimated`, so the whole curve left the
band mid-gesture. That was §11.5's predicate behaving correctly and one press of Undo brought it back,
but an artist watching a curve vanish does not read it that way.

**The band now draws every channel that carries a curve, and dashes the ones that are not
animations** — dimmed to `flatAlpha`, `flatDash`, with **hollow** key dots, and a `~` where the
accessibility value would put a `:`. The objection recorded against this on
`TimelineGraphBand.channels` — *"a flat line in the band with no way to tell it from one the artist
authored"* — is a demand for a **distinction**, not for an omission, and the dash is one; the two
states are told apart rather than merged, which is the condition the fix had to meet.

**What the objection did not weigh is the state it left behind, and that is what decided this.** A
channel the band does not draw is a channel no tap in the band can add a key to, so the one surface
built for editing curves was the one surface that could not undo this edit. The flat state is a
**door**: tap the dashed line to key it again, tap the hollow dot to remove the last key, at which
point `setEffectParameterTrack` drops the empty curve and the channel is gone for real.

**One walk, so the §2.28 pin is untouched.** `allChannels(effect:tracks:)` is the loose predicate with
the strict one carried on the value; `channels(effect:tracks:)` is that filtered, so its ids are still
exactly `listedAnimationChannelIDs(of:)`. The channel list is built from `allChannels` and labels each
row — a **deliberate reversal of §11.5's membership ruling**, forced by the filter: a channel hidden
while it was an animation must not reappear the moment a key is tapped away from it, and a row that is
not listed cannot be switched back on.

**And mutation-testing that reversal found the §2.28 pin was itself vacuous.**
`testTheBandDrawsExactlyTheChannelsTheModelCallsAnimations` animated *both* of its fixture's channels,
so deleting `.filter(\.isAnimated)` returned the identical array and the test stayed green — caught
only by a neighbour. **A filter is unpinned until its fixture holds something the filter must reject**,
which is the "nearest, not first" lesson three paragraphs down in a fourth costume. The fixture now
flattens one channel after asserting the animated case.

Seen rather than reasoned about: `docs/graph-editor/7-before-a-flattened-curve-vanishes.png` and
`7-after-a-flattened-curve-goes-dashed.png`, one tap apart on the same fixture.

**Five mutations, and the fifth is why this note exists.** Each of D3's load-bearing rules was
poisoned in turn against the fast tier — remove the neighbour clamp, clamp to `uiRange` instead of
`modelDomain`, hit-test the true y instead of `reachableY`, insert a group's keys as they are removed
rather than after — and four were caught. **"The nearest key, not the first" was not**, because the
fixture never put two keys in reach at once: the two channels' dots were 80 pt apart, so the two
answers could not differ and the assertion was true of any implementation that returned *something in
range*. §11.3's own finding, one stage later and in a subtler costume — the test named the right rule
and could not see it. It now puts two dots 20 pt apart with the wrong one first.

## Reviewed 2026-08-30 — one real defect, and a comment that outlived its reasoning

**`finishGraphBandTouch` decided tap-versus-drag from the translation alone**, under a comment copied
from `CurveEditor` saying `didMove` "would be the wrong question". That sentence is true where it was
written: `CurveEditor` sets the flag only after `guard let index = dragIndex`, so there it means *a
handle was grabbed and then moved*. It is false here, because `updateGraphBandTouch` sets it for the
marquee too, before the gesture has decided which kind it is. **The predicate is the conjunction,
`!didMove && travel <= tapSlop`, and neither half is redundant** — the flag alone drops a key wherever
an empty-band sweep stops, which is what the borrowed comment was really about; the travel alone calls
a reversed drag a tap.

What the missing half cost: press a key, nudge it past `tapSlop`, change your mind, bring the finger
back and lift. The travel is nothing, so the touch resolved as a tap **on the key it was carrying** —
which is a *remove*. And the deletion was **unrecoverable**: the tap's `setEffectParameterTrack` ran
while the drag's bracket was still open, that call records nothing while a gesture snapshot is open,
and the bracket was then dropped by `cancelStructureGesture` — the arm a drag takes when it wrote
nothing of its own, which any key pinned at its `modelDomain` edge does (a `blur.radius` key at 0
dragged downward clamps to 0, frame delta 0, `applying` returns `[:]`).

**Both doors are shut, deliberately twice over.** The predicate is now
`TimelineGraphBand.isTap(didMove:translation:)`, moved onto the band so the *fast tier* can read it —
`TimelineTrackView.swift` is not compiled into `PaintSoftwareUITests`, which is exactly why a rule
this load-bearing went a whole stage with no test that named it. And `endGraphBandDrag` is now called
**before** the tap's write rather than in a `defer` after it, so no bracket can span a discrete write
whatever the predicate is later changed to. The truth table is
`testATouchIsATapOnlyIfItNeitherMovedNorTravelled`; that a tapped-away key comes back on one press of
Undo is `testATapAddsAKeyToTheCurveItLandsOnAndRemovesOneItLandsOn`, end to end through a finger.

**A cancelled drag now restores the selection as well as the curves, and it is one restore rather than
two.** The drag rewrites the rings every tick alongside the keys — deliberately, so a set dragged four
frames right is still drawn around itself — so putting only the curves back left refs naming frames
that no longer key: no ring drew, grabbing a member stopped carrying the group, and nothing repaired
it, `layoutGraphBand` clearing the selection when the band changes layer but never recomputing one.
Two fingers reach it, the second touch cancelling the recogniser mid-drag. It is the only one of the
four findings with no test: the selection is coordinator state and the band's accessibility value
carries content only, so neither tier can see it without new machinery for a cosmetic bug.

**And `applying` walks its keys sorted, which buys a test rather than a behaviour.** Removals-before-
insertions is what makes the answer independent of the walk order, so sorting changes nothing this
function returns. It changes what the *poisoned* version returns: interleave the two halves and a
rightward slide is untouched whenever the walk runs downwards, which for a `Dictionary` is a coin flip
on Swift's per-process hash seed — three keys, six orders, one of them safe, so
`testAGroupSlidingOverItsOwnFramesLosesNothing` killed that mutation about five runs in six. **A test
that catches a defect sometimes is worse than one that never does**, because this repo triages a
one-off red as environmental until an isolated re-run says otherwise (CLAUDE.md), and an intermittent
test spends that judgement for everyone.

**"The nearest, not the first" has now been the same miss three times, at three levels.** §11.3 found
it; the five-mutation pass above found it again for `nearestKey` and fixed *that* fixture — and left
`nearestChannel` one level down with no test that could fail. Its only coverage was through `tap()`,
on a fixture whose two lines sit 4 pt and 36 pt from the touch against a `hitRadius` of 22: one
candidate, so "nearest" and "first" are the same answer and `if best == nil { best = ... }` is green
across the whole suite. It now has a fixture of its own — both lines in reach, 8 pt apart, the wrong
one first — and the case is real rather than contrived, because a grade's two curves cross mid-band
and a first-match rule adds a key there to whichever channel `Effect.parameters` lists first rather
than to the one under the finger. **The rule worth carrying out of the third occurrence: a proximity
test proves nothing until its fixture holds two candidates.** With one, the assertion reads correctly
and is true of any implementation that returns *something* in range.

**A smaller one, and the brief that named it was half wrong.** The frame-0 floor in `moves` was
untested, and is now covered by a curve whose earliest key is at frame 2 dragged ten frames left —
`testAKeyIsStoppedByItsNeighbourRatherThanConsumingIt`'s backwards case has a blocker sitting *on*
frame 0, so it exercises the neighbour arm and never this one. But the `max(0, …)` in that expression
is not what makes the floor: `below` is never negative and the `?? -1` sentinel already yields 0, so
the `max` is provably a no-op and no test could have distinguished it. The floor is the sentinel. The
code is left as it stands, being correct; the note is here so the next reader does not go looking for
the coverage gap that would justify it.

**What it cost the suite, and the split that paid it back.** `GraphEditorUITests` went from three
tests to ten and from ~40 s to a MEASURED **271 s** — taken serially on a dedicated device on
2026-08-30, which made it the suite's **second-longest class**, behind `SelectionAndMoveUITests`
(327 s) and ahead of `PerfBaselineTests`. Class granularity is the whole cost model: a class is
indivisible and the longest one sets the critical path, so it was split in two along the seam between
the band's *existence* and D3's *gestures*, both classes in the same file.

| class | tests | MEASURED s |
|---|---|---|
| `GraphEditorUITests` — open/close, register with the pinned name column, drop targets, the two-stage tap, the channel-list button | 7 | **133** |
| `GraphEditorGestureUITests` — drag a key, tap to add and remove, the marquee | 3 | **136** |

Same run, same device, serial: 2237 tests, 0 failed, 3 skipped, and the graph tests still ten. The
split cost the suite nothing — 269 s of work against 271 before it — and it can now occupy two clones.

**Balanced on seconds and not on tests, which is why 7 against 3 is the right cut.** Each gesture test
spends ~45 s and nearly all of it is `authorAnAnimatedBrightnessCurve` — two keyframe marks and a
slider drag, there being no shorter way to author an animated channel, since the graph editor edits
curves and cannot be the thing that makes the first one. A split on test count would have left 3 s on
one side and 268 on the other and bought nothing. That is `LayerPanelUITests`' lesson of the day
before, where one test was a seventh of its class. If a fourth gesture test is ever wanted, the
fixture is what to attack; it now lives as a `fileprivate` extension on `PaintUITestCase`, both halves
of the split needing it.

**And the band now sits above the playhead, which reverses §11.3's fourth decision** (the paragraph
beginning "The playhead is a column, not a hairline" — it is stale from here on, and so is the class
doc it seeded on `TimelineGraphBandView`, which has been rewritten in place). D2 made that call
*having looked at it* and recorded that "a saturated 1.8 pt curve reads through the wash perfectly
well". That was **true of the hue it was looked at and not of the palette**: screenshotted with green
(145°) and orange (28°) crossing the column together, the green survives and the orange is a grey
stub. Red (8°) and violet (262°) are the next two the same compositing reaches — the second by
landing on the playhead's own colour rather than on grey — and which channel gets which hue depends
only on its position in `Effect.parameters`.

**The objection to fronting the band assumed a panel, and the band is not one.** Its background is
white at `backgroundAlpha` **0.06**, so putting it above the playhead does not cut the column in two:
the column reads through 96 pt of 6 % white unchanged, and what rises clear of the wash is the 1.8 pt
strokes and the key dots — a few percent of the band's area. The alternative that was going to be
needed otherwise, redrawing the curves above the playhead inside its own x range, buys exactly the
same picture for the price of a second view kept in register with this one; and repainting the palette
to survive 35 % blue would constrain all eight hues for one overlap. One `bringSubviewToFront` in
`movePlayhead`, beside the playhead's own so the two orderings stay in one place.

**Verified by looking, which is the only way this could have been verified.** Two screenshots of the
same fixture — a grade with brightness (descriptor index 0, green) and contrast (index 1, orange) both
animated, the playhead scrubbed onto frame 4 in the middle of both curves — taken on the same device
before and after the change. Before: the orange curve is **a grey stub** for the width of the column
and orange either side, while the green curve is untouched, exactly as reported. After: both curves
hold their colour across the column, and the column is continuous from the ruler through the band to
the row below. Only those two hues were rendered, and that is enough, because the fix removes the
composite rather than tuning it: nothing is drawn over a curve any more, so the remaining six hues
cannot be affected differently. The harness that took the pair was a throwaway and is not in the tree
— XCUITest can see neither a `CGContext` nor a colour, so there is nothing here for either tier to
assert and this is a decision made by eye, as D2's was.

**Ask 6's *cel* marquee stays future**, with its stub: "Select Multiple" sits in the cel menu today,
`.disabled(true)`. What this stage built is the keyframe half of that ask, and the shape it settles —
a drag in empty space rubber-bands, a grab on a member carries the set — is the one a cel marquee
would copy.

**Bezier tangent handles — done 2026-09-03, TODO (38)(b).** The curve was already bezier in the model
*and drawn as one*: `AnimationCurve.Key.interpolation` defaults to `.bezier`, every construction site
takes that default, and `TimelineGraphBandView.draw` samples `evaluate` once per point of width. **What
was missing was the authoring, and not for the reason this paragraph gave.** Every key shipped
`.autoClamped`, and `effectiveHandles(at:)` *derives* the pair and discards the stored one — so an
authored handle changed nothing at all. Taking a handle therefore has to move the key to `.free` **and
seed both derived handles into the stored pair in the same write**; doing it the other way round snaps
the segment straight at touch-down.

The arbitration this paragraph named is resolved by nearest-wins (`TimelineGraphBand.grab`): a handle
takes the grab only when it is nearer than its own node. **Dragging sets `.free`, by owner ruling** —
what you drag is what moves, rather than `.aligned` swinging the far handle under the finger — and the
way back is the node menu's **Reset Curve**. Nothing is clamped on the way in; that is decision 3
already, not an omission.

**The tap grammar changed with it and the old one is superseded.** It was *on a key it removes, on empty
graph it adds*; a single tap deleting was a destructive default. It is now: on a node it **focuses**
(which is what draws the handles), on the already-focused node it opens a **menu** carrying Reset Curve
and Delete Keyframe, and on empty graph it still adds. That second stage is `handleTapOnCel`'s existing
two-stage contract — the app has no double-tap recogniser anywhere, and "clicking twice" means a second
tap that lands where the selection already is — so `MenuRequest` gained a `.graphNode` case and reuses
the one `timelineMenu` state and anchor path. Delete funnels through
`CanvasManager.removeEffectParameterKey` to the *same* writer the old tap used, so it is still one undo
step and it still drops a mark through `marks(_:droppingKeyed:)`. No third writer.

**A dragged node reads its own value (TODO (38)(d))** in `EffectParameter.format` verbatim — the exact
string that parameter's own settings-bar slider prints, so the two can never disagree about a number.
It sits above the node, beside it when there is no room above, clamped to the *visible* window rather
than the band's bounds, and appears only when the drag has changed the node's **value**, so a pure
retiming drag shows nothing by construction rather than by a threshold.

### 11.5 Stage D4 — the channel list is a filter — **done 2026-08-29, amended by §11.7**

**Its title said *"a filter, not a navigator"* and the owner reversed exactly that half.** The list is
both now: the box filters and the row body navigates. §11.7 carries the ruling and the gesture split;
everything below about *what* the rows are is unchanged.

The owner: *"just a button option in the graph editor which brings up a scrollable popup menu, which is
basically an include or exclude checkmark box for each animation. Animations may have multiple values
being modified at once (like transform x and y), so those should have a drop down so they are visible or
invisible like a whole. This is basically like the hide/show layers and layer groups."*

So it is visibility, not selection: the editor shows every animated channel and the list turns them off.
~~Membership of the list is `channelIsAnimated` — the strict predicate, ≥2 keys whose values are not all
equal — never the loose one auto-key uses.~~ **Reversed 2026-08-30 by §11.4's vanishing channel:
membership is the loose predicate (a curve at all) and the strict one is carried per row, because the
band now draws both kinds and a channel hidden while it was an animation must stay listed to be
switched back on.** Visibility is **transient view state, not document state**: it
filters what is drawn, it has no meaning with the editor closed, and persisting it would put a field in
the manifest that changes no pixel. `TimelineGraphChannelList` holds the grouping, the toggle arithmetic
and the filter's scope, beside `TimelineGraphBand` and for that file's reason — `AnimationTimeline.swift`
is not compiled into the test target, so a rule written there is pinned by nothing.

**Grouping falls out of the id format, and what falls out is one group.** Parameter ids are
`"<case>.<field>"` so `groupID(ofParameterID:)` is the text before the first dot and no second table is
needed — but a band is one layer, a layer is one grade, and a grade is one prefix, so **every band today
has exactly one group**. That is not a reason to drop it: the group row is the only control that switches
a whole effect off in one tap, which is the owner's *"visible or invisible like a whole"*, and the shape
is what a second channel source (a transform, a folder's grade) will need. It was pinned by
`testEveryBandTodayHasExactlyOneGroupBecauseALayerHasOneGrade`, which is the assertion that changes the
day the premise does — **and the day came**: §11.7's transform band makes two Move channels on one layer
two groups, so that test is now `testAGradeContributesExactlyOneGroupNamedByTheEffect` beside
`PoseBandLogicTests.testABandShowingTwoMoveChannelsHasTwoGroups`.

**One thing the id format was said to give for free and does not.** `TransformChannelID`'s own doc says
its id doubles as the grouping key *"so a transform channel lands in the channel list's existing shape
rather than needing a second one"*. That is true of `.cel` and false of `.group`, whose id is
`"group.<uuid>"` — already carrying a dot — so a component appended to it would put **every** animation
group under the prefix `"group"`, and one tap on that header would switch off channels belonging to
drawings the artist never picked. `PoseChannelID` mints a dot-free prefix instead — `"celPose"`,
`"poseGroup-<uuid>"`, `"containerPose"` — and `groupID(ofParameterID:)` is untouched.

~~**And it is why there is no fold.**~~ **Built in §11.7, and the two objections recorded here were
answered rather than waived.** They were that a chevron over one group folds the only thing in the list,
and that collapse state has no natural scope — keyed by effect case it is *"brightnessContrast"*, which
follows the artist to the next layer carrying that grade and greets them with a header and no channels.
The transform channel is the second channel source this paragraph named as the condition for revisiting:
a layer can carry a whole-cel Move and any number of animation groups, so there is something to fold; and
`TimelineGraphChannelList.Fold` carries the `KeyframeTarget` it was authored on exactly as `Filter` does,
so it dies with the band. **The decision lives in `TimelineGraphChannelList`, not in the
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

- ~~**A transform channel has no band, so an object animated with Move has no curve to edit.**~~
  **Built in §11.7, and editable since.** The six decomposed curves are drawn, listed, grouped, folded
  and navigable, and a node on one is dragged on both axes — vertically it edits that component,
  horizontally it retimes the whole key. Since 2026-09-03 a node is also **focused and its bezier
  handles shaped**; what stays refused is the node menu's Delete and tap-to-add, both for want of a
  writer rather than for want of a rule.

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

  **Asked again on 2026-08-30 and answered the same way**, because a 250 pt panel does not hold four
  layers plus an open band. Nothing is lost — the content scrolls — and none of the three levers is
  free: shrinking the band trades the shape it exists to show, growing `timelineHeight` takes canvas
  space back without being asked, and auto-scrolling the expanded row into view has 33 pt of range to
  pay a 96 pt debt with on a three-layer document (§11.3). BUGS.md carries the note; it stays a note
  until the owner says the drag grates.
- ~~**A collapsed folder hides its children's key markers.**~~ **Ruled 2026-08-29: it shows nothing, which
  is today's behaviour, so there is no work.** Offered merged per-frame diamonds from the hidden children
  and a single "there is animation in here" indicator, the owner kept the blank row. Recorded as ruled
  rather than deleted because it was found as a gap and will be found again: the next session to notice
  a folder swallowing its children's markers should read this and move on.

### 11.7 The transform band — the two rulings, and what shipped

**A transform/pose channel had no band at all.** `TimelineGraphBand.allChannels(effect:tracks:)` took
an `Effect?` and a `[String: AnimationCurve]`, so a `TransformTrack` could not reach it — a missing
door rather than a hidden band, and the brief that opened this stage said so and was right.

#### Ruling 1 — the band shows the pose decomposed

Asked whether a transform band should show eight raw corner coordinates, six decomposed curves (X, Y,
Scale X, Scale Y, Rotation, Skew — what After Effects and Clip Studio show), or decomposed with a
corner fallback for a genuinely projective pose, the owner answered: **"decomposed"**.

**`DeformFactorization.Matrix2x2.polar` is not the decomposition to reuse, and the brief's hypothesis
that it would be is refuted.** §4.3 blends two poses through `polar` and `interpolatedFromIdentity`,
which factor a 2×2 as rotation × **symmetric** remainder — the right choice for interpolation, because
it is the path from the identity that makes an arm swing instead of collapsing, and `polar`'s own doc
says so. It is the wrong one for *naming*: a pure horizontal shear `[1 k; 0 1]` has
`atan2(c − b, a + d)`, so **polar reports a rotation for a pose that was never rotated** — a skew of
0.5 comes back as −16.7° of turn plus a squash, and an artist who skewed would watch the Rotation
curve move. The six the owner named are the **QR / Gram-Schmidt** factorisation
`M = R(θ) · Sk(φ) · diag(sx, sy)`, which is what AE, CSP and the CSS transform specification all
report; it is eight lines in `Models/PoseComponents.swift`, and everything else in `Engine/Deform` —
`Matrix2x2`, `Homography.affine()`, `Quad.rect(_:).mapped(by:)` — is reused unchanged. Pinned by
`PoseComponentsLogicTests.testPolarReportsARotationForAPureSkewAndTheQRDecompositionDoesNot`, which
exists so the next session reaching for the shared primitive finds the arithmetic rather than an
opinion.

**A projective pose is declined, with a reason, rather than shown as its affine part.** A homography
has eight degrees of freedom and these six curves have six, so there is no honest drawing of one.
`PoseQuad.affineOrLinearised` *does* answer — the linearisation at the box centre, which is right for
rendering (§4.2's third honest artifact; drawing nothing would make a frame vanish) and wrong for a
graph editor, where it would show six curves that are not what the pose does and a write-back through
them would flatten the keystone the artist authored. So `PoseComponents.decompose` asks
`Homography.affine()` at its exact-zero tolerance, the **whole channel** is declined if any of its keys
is projective (five honest curves and one linearisation would be worse, because nothing would mark the
sixth), and `Content.declinedChannelIDs` names it — the band's accessibility value reads
`declined:celPose`, which is a third state beside `empty` and `hidden`. Unreachable today: animated
Distort is stage 5b and no writer produces a projective `PoseQuad`. **Whoever builds 5b decides whether
to add a corner fallback beside these six or to widen the six; do not quietly make `decompose`
linearise.**

~~**The band is read-only, deliberately and explicitly.**~~ **Superseded — the nodes are draggable on
both axes, and the refusal is gone rather than relaxed.** What stood between the decomposition round
trip and a drag was never the arithmetic (`recompose` is `decompose`'s exact inverse over its own
range, and `setting(_:to:of:)` replaces one component and leaves the other five alone, both tested)
but the **write funnel**: `setEffectParameterTrack` addresses one curve at a time, a pose key has one
frame and six rows, and a curve-at-a-time writer has no shape in which to say so. Passing a pose id
through it was dropped outright, which was read-only by accident of another function's guard — the
bracket opens, the node travels under the finger and snaps back on lift with nothing saying why.

**The repair is a second funnel, and the desynchronisation is unrepresentable rather than guarded
against.** `TimelineGraphBand.poseEdits(_:in:)` folds a drag's row-level `Move`s into a `PoseEdit`
whose `retimes` are keyed **by frame, not by `KeyRef`** — so a destination frame is a property of the
key and six rows cannot ask for two of them — and
`CanvasManager.writeGraphBandPoseEdits(_:from:layerIndex:)` applies it to the `TransformTrack.Key`
itself. A vertical drag lists only the component that moved, and only when its value actually changed,
so a pure retime carries the pose by identity rather than round-tripping it through `recompose` once a
tick. Every tick applies to `GraphBandPoseSnapshot`, the poses as they stood at touch-down, for the
reason `applying(_:to:)` applies to the drag's starting curves — and that snapshot is also what a
cancelled drag restores, in one call. One undo step, by recording nothing while the gesture bracket is
open, which is `setEffectParameterTrack`'s own arithmetic.

**A key that rides a cel cannot be dragged out of it** — `Channel.frameWindows`, folded into the same
`minDelta`/`maxDelta` the neighbour clamp uses so it reads as the same wall. A layer's cels merge into
one drawn channel per component, so without it a key of cel A travels into cel B's frames, where it
renders nothing (it is past its own cel's span) and can land on the same *absolute* frame as one of
B's keys — one drawn node over two stored ones. The clamp is in the band rather than in the writer so
that the dot stops where the document stops.

**What a pose channel still refuses is the tap family, and `Channel.Gestures` is where that is said.**
`.dragOnly` against a grade's `.all`: no focus, no bezier handles, no node menu, no tap-to-add. Each
has the same cause one level down — a `TransformTrack.Key` carries **one** handle pair for all six
components, so shaping Scale X's tangent would bend the other five; the menu's Delete funnels through
`removeEffectParameterKey`, a grade writer; and tapping a curve to add a key would have to invent five
component values the artist never gave. Those belong to whoever extends (38)(b), not to this stage.
`TimelineGraphBand.editable(_:)` is replaced by `tappable(_:)`, and there is deliberately no
`draggable(_:)` beside it: every channel the band draws takes a drag, so such a filter would return
its argument and read as a rule being enforced.

**One thing the surface cannot do at the shipped height, found while writing the tests and not fixed.**
All six rows of a pose channel key the same frames, so at any keyed frame the band draws six dots on
one x, spread over 96 pt by per-channel normalisation alone — about 16 pt apart against a `hitRadius`
of 22. `nearestKey` does exactly what it says and there is no room for six independent targets, so a
finger cannot reliably pick *which* component it is grabbing where all six key. The artist's answer is
the channel list's filter — hide the five rows you are not editing — which is an argument for that
filter rather than against this band, and `PoseNodeDragLogicTests` buys unambiguous targets by
choosing a taller band because what it tests is the write.

**Two consequences of the drawing worth knowing rather than discovering.** The drawn line is the
*timing* curve's interpolation of a component, while the animation's actual in-between is
`PoseInterpolation.blend`, which factors and blends the two poses; they agree exactly at every key and
differ slightly between them for a large rotation. That is the same shape as the `step > 1` gap
`stem(forKeyAt:in:)` already draws — two truths, neither bent onto the other — with the difference that
here there is no disagreement at any *node*, which is where the artist grabs. And all six components
declare **no `uiRange`**, so each is normalised to its own key extent: none of them has a
canvas-independent range, and the one that looks as though it does (rotation, −180…180) is the worst
case, drawing a 5°-to-10° animation as a flat line in the middle of the band. §11.6's argument for
preferring a declared range is about drags — **which this band now has, and the ruling is still to keep
the nil.** The value written is exact either way: `moves` reads the axis captured at touch-down, so the
finger gets the number it asked for. What rescales is the *drawing*, and it does so for the eight grade
parameters that declare no `uiRange` too, so it is a pre-existing property of the band rather than
something write-back introduced. Declaring −180…180 for rotation would trade a node that lags the
finger for an animation drawn as a flat line, which is the worse of the two.

#### Ruling 2 — the channel list is a navigator as well as a filter

The owner, verbatim: *"in the menu list of animations, clicking on a move item in there should bring up
the move box for that move item so you don't need to select it manually again."*

This amends §11.5, whose title and whose file's opening line both said *"a filter over the band, not a
navigator through it"*. Both are rewritten rather than left to contradict the shipped behaviour.

**The gesture split: the box filters, the row body is the subject, the chevron folds.** One rule for the
whole list rather than one per kind of row — tapping a row's body raises the thing that row is about. A
grade's channel has nothing to raise (the surface an artist edits a Brightness curve on is the settings
bar, and they are already there), so its body is inert; the alternative considered and rejected was
letting the body toggle the box wherever there was nothing to navigate to, which makes one gesture mean
two things depending on a property of the row the artist cannot see. All six rows of one Move channel
raise the same box, because the owner asked for *"the move box for that move item"* and the move item
is the channel, not the component.

**What it raises is `beginVectorWholeCelMove` with the moved set narrowed** — membership on a pose
channel is `VectorElement.isMoved(by:)`, a field rather than a region, so nothing is split, no id is
minted and the float is the ordinary one. It does **not** move the playhead or the layer: the band is
open on the selected layer and the cel is the one under the playhead, so a click reveals the channel
where the artist is standing. **A container pose navigates too, since §4.4's entry pass**: it raises
`beginContainerPoseMove()` rather than the vector lift, because a container has no geometry to lift and
its box is the canvas frame. `PoseChannelID.raisesMoveBox` was the one line that had to change and it
is true for every channel now; `revealPoseChannel` was the one that had to learn there are two kinds of
box. `LayerFolder.transform` is the case still without an entry.

#### The fold, and the two funnels

**The fold is §11.5's deferred chevron, built now that there is something to fold.** It is a
disclosure and not a second filter, which is the owner's own analogy taken literally — *"like the
hide/show layers and layer groups"*: a layer folder has a chevron that shows or hides its rows in the
panel and an eye that shows or hides its contents on the canvas. Folding changes nothing the band
draws, and a folded group still carries its whole membership so its box still describes it.

**Both funnels the transformation layer's pass left open are closed, and both were §2.28's
biconditional broken from a door §2.28 could not have known about.** `keyedFrames(of:tracks:)` folded
the *cels'* pose tracks and stopped, under a comment that read as exhaustive — so a key on a
transformation layer or on a folder's own pose drew a node in the graph editor with no diamond beside
it on the track, which is the report §2.28 was written from arriving a third and fourth time.
`poseKeyframeFrames(inLayer:)` now folds `layerTransform?.track` (through the accessor, so a pose left
behind by a kind change contributes nothing, which is `storedEffect(of:)`'s asymmetry one payload
over), `poseKeyframeFrames(inFolder:)` is its twin, and `listedAnimationChannelIDs` lists the pose
channels **per component** — a pure translation leaves four of the six flat, and a track-level answer
would call them animations. `curvedEffectChannelIDs` deliberately stays effect-only: its one caller
marks the *sliders* that carry a curve, and a pose channel has no slider.

#### Two device reports, both about the band's y axis and its handles — **done 2026-09-03**

> *"if i try to move the nodes, the nodes dont move? its value changes but the nodes just stay still
> in the graph."* … *"why cant i access the bezier handles in move?"*

**The first is arithmetic and not tuning, which is the finding.** §11.6 rules the axis is a
parameter's `uiRange` where it declares one and the extent of the channel's own keys otherwise, and
all six pose components declared none — reasonably, since X and Y are canvas coordinates and an axis
of −180…180 would draw a 5°-to-10° rotation as a flat line. But `keyValues.min()...keyValues.max()`
maps the smallest key to the bottom of the band and the largest to the top, so **on a two-key channel
both keys are extremes and each is pinned for every value it could hold** — which is a Move keyed at
A and at B, the owner's plural exactly. The value a drag wrote was always right; only the picture was
invariant.

Three repairs were considered against that arithmetic before one was written, and the first two do
not work:

- **Padding the fit** moves the pin off the rim and leaves it a pin. Any axis built from the keys
  alone — min/max, mean and maximum deviation, padded or minimum-spanned versions of either — is
  affine-equivariant in the key set, and an affine-equivariant map sends a two-point set to the same
  two positions whatever the two points are.
- **Freezing the axis for the length of the drag**, which is where this pass was told to start, makes
  the node follow the finger and then **snap back to where it started on lift**, when the fit is
  retaken. It is worth having for a different reason (below) and it is not the fix.
- **What shipped**: `TimelineGraphBand.anchoredRange` centres the axis on the component's *rest*
  value — `PoseComponents.Component.restValue(inRestBox:)`, which is 1 for a scale, 0 for an angle
  and the rest box's own centre for a position — and grows the half-axis in **doublings** from
  `minimumAxisSpan`. Anchoring breaks the equivariance; the doublings stop the *outermost* key being
  the thing that sets the scale, which a plain anchored fit would leave pinned. Inside one octave the
  window is constant, so every node moves under the finger with a constant gain and the outermost
  lands somewhere in (0.7, 0.9] of the half-band whatever the animation's size.

**The second defect was hiding behind the same report**: gain followed the spread, so two X keys two
points apart meant a full-band drag moved X by two points, and a channel keyed but not animated —
drawn dashed, still draggable — got `range`'s half-unit widening and moved by **one**. The window is
now a property of the component, so `minimumAxisSpan` is chosen for gain rather than for framing: 100
points of X over an 80-point usable band is 1.25 points a point, 40° of rotation is half a degree a
point. **The cost, stated**: an animation is drawn at between 35% and 90% of the half-band instead of
always filling it, so a small one reads shallower than it did. The doubling is what bounds that to a
factor of two rather than leaving it to the data.

**The freeze shipped as well, for the case the anchor does not cover.** `moves(of:in:…)` reads the
axis captured at touch-down and the redraw derived one afresh; they agree for every drag inside one
octave, and `TimelineGraphBandView.frozenAxes` makes them agree at a boundary crossing and for the
**eight grade parameters that declare no `uiRange`**, whose axis is still the key extent and still
rescales on every tick — §11.6's *"a key would move under the finger that is not dragging it"*, which
was that ruling's own reason for preferring a declared range. Those eight keep the fitted fallback:
the anchor here is *rest*, and a blur radius has no rest.

**The handles were refused on an argument that over-corrected.** A `TransformTrack.Key` carries one
`inHandle`/`outHandle` pair and one tangent mode for all six components, and the refusal reasoned that
shaping Scale X's tangent would bend the other five. It would — and that is the *model*: a shared ease
is what is stored and what `PoseInterpolation.blend` runs. So the repair is the picture, not the
gesture: `handleRows(of:in:)` draws the pair on **all six rows at once**, `grab` arbitrates across
them and returns the row the finger took, and `Channel.Gestures` gains `.dragAndHandles` — everything
except the node menu and tap-to-add. `.dragOnly` is deleted rather than left standing, having lost its
only producer. A second tap on a pose node answers `.focus` again and deliberately not `.nothing`,
which is the empty-band case and whose caller drops the focus — that would take the handles away on
the second tap.

**The units are the trap, and the brief that commissioned this did not see them.**
`TransformTrack.timing` is an `AnimationCurve` whose key values are the pose **indices** `0, 1, 2, …`
carrying those same handles, so a stored `deltaValue` is a fraction of a *pose*, while the band's six
rows are in canvas points, degrees and multiples. Writing a row's handle through verbatim would have
put a `deltaValue` of order 100 into a curve whose values are 0 and 1 — a hundred-pose overshoot on
every drag. A `timing` segment rises by exactly one and a row's rises by that segment's own
difference, so the row's curve is the **affine image** of the timing curve's and a bezier is
affine-equivariant: `poseChannels` multiplies by the rise on the way out, `poseHandleEdits` divides by
it on the way back, and `PoseEdit.Ease` carries the result through the pose funnel. **The copy at
`poseChannels` was already unscaled and was already wrong**; it was inert only because every pose key
ships `.autoClamped` and `effectiveHandles(at:)` ignores a stored pair under four of the five modes.
This pass is what made `.free` reachable. A row that does not move across the segment offers no dot,
which is `handles(of:in:…)`' existing rule about a handle that shapes nothing, reached by a second
door.

**And one thing the fitted axis had been holding up by accident.** `PoseEdit`'s "only what moved is
listed" rule compares a move's value against the value the drag started from, so that a pure retime
lists no component and `PoseComponents.setting` never grinds the other five in the last place. That
comparison needs `moves` to hand back the key's own value bit for bit on a horizontal drag, and it
was getting it only because the fitted axis put the fixture's values on the band's own rim, where the
`y`/`value` round trip happens to be exact. `moves` short-circuits zero vertical travel now, the way
`PoseInterpolation.blend` short-circuits `t == 0`. `testARetimeCarriesThePoseRatherThanRecomputingIt`
is what found it.

**Pinned in `PoseBandLogicTests`, and the assertions are about drawn y rather than about values** —
a test that checked `key.value` passes against the build the owner is reporting. Six mutations, six
reds: the anchored axis reverted to the fit (3 tests), the tap filtered pose nodes out again (1), the
handle scale dropped on the way out (2), the divide dropped on the way back (1), a flat row offered a
dot anyway (1), and the retime short-circuit removed (1, in `PoseNodeDragLogicTests`). The first of
those also exposed a fixture whose grade node and pose node shared a point, so `nearestKey` was
answering about the wrong channel; the two are now a fingertip apart and a fixture assertion says so.
