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

## The owner's 2026-10-01 brief — (111)–(146)

Thirty-six asks in one message. **Each number is 110 + the owner's own ask number**, so the owner's
"ask 14" is (124). Where the owner said two asks are one task, they share an entry. Queue order below;
the owner left the order to us. Every entry is the owner's words, then what is left.

---

## (125) Realtime feedback for every transform edit — with (136) and (140)

**Status** — not started. The owner names these as one task:

- **(125)** *"I've noticed that moving a transform layer is extremely laggy. I need proper realtime
  feedback especially when I am recording my movement for keyframes. I wonder if you can use the same
  sandwich thing that the brush uses to eliminate lag. It may also help to pause the background
  renderer until the user raises their pen off the move tool, because the background renderer
  re-renders every frame if a move is keyframed, and that move is adjusted."*
- **(136)** *"Using the folder move is extremely laggy (as with all other move tools). This is similar to
  ask 15, just for folders, since multiple layers are being moved at once. When moving the stuff inside
  a folder, it should be realtime."*
- **(140)** *"This is a similar thing with the move adjusting causing a lot of lag, editing the nodes on
  a transform in the graph editor lags heavily. It should be real time. I feel like this fix and ask 15
  should basically be the same task without the need for two separate mechanisms."*

- [ ] One live-preview mechanism for a transform being edited — transform-layer Move, folder Move,
      graph-editor node drag — measured before and after on the device-sized document.
- [ ] The frame baker holds off while a transform edit is live and re-bakes once on release.

## (124) follow-up: raster selections and Move under a transform layer

**Status** — not started. (124) merged (`dbd53b0`): every brush, eraser, smart shape, text box, fill and
the **vector** lasso/Move now read the pen through the inverse of the pose a layer is shown through
(`CanvasManager.inkPose(forLayerID:)`). The **raster** lasso and raster Move under a transformation
layer do not yet — the same defect class as (124), so it is finished rather than asked about.

- [ ] Raster lasso loops and the raster floating piece map through `inkPose`; a cold-start UI test
      lassoes and moves raster ink under a Move layer and asserts the pixels land under the pen.

## (112) The stream says "paused" and stops updating until the artist draws

**Status** — not started. *"The live streamer sometimes does this thing where it pauses and refuses to
update until I draw something on the canvas. It says stream paused. I wonder where that message even
comes from, because it is separate to it being frozen manually through the freeze button. I'm not even
sure why it exists at all. There could be a lot of other bugs with it not updating when it is supposed
to, so an investigate. I will just explain the ideal behaviour: The streamer should update when the
computer screen is changed. Whatever is shown on the computer screen should be on the ipad when the
streamer is not frozen manually. There could be a lot of edge cases with this such as the streaming
layer being hidden and then shown again, etc."*

**Folds in (101)'s last check** — (101)'s reconnect loop and LAN discovery are fixed and
owner-confirmed (`4b0da3c`, 2026-09-25: *"LAN works"*); what was left was the owner's word that a stream
stays Live instead of reading "Paused", and this report is that word.

- [ ] Every source of a "Paused" state found and named; any not owed to the manual Freeze removed or
      made self-healing.
- [ ] The stream redraws on every laptop frame while visible and unfrozen — hide/show, layer switch,
      background/foreground, laptop lock/unlock — tested against `tools/stream/fake-streamer.py`.

## (139) Keys, not keyframes — every channel component independent

**Status** — ruled, not started. *"An update has to be done to the graph editor and key
framing. First off, remove all notion of keyframes, everything should just be keys. Lets say we have a
move option. The X and Y and rotation etc components keys should be fully independent from each
other."* KEYFRAMES.md §2.26–§2.28 (the keyframe-mark workflow) and §2.5 (a transform key stores a quad)
are what this reverses.

**Ruled 2026-10-01:**
- **Priming replaces keyframes.** *"you select 'add keys' which primes it, then when you move a slider
  or transform, only the keys of thingd that changed are added. Note, if you prime this in two frames
  and then change something, then it should put down two keys like the behaviour today, but only the
  things that changed"* — so a primed frame is still a bare mark in time (today's mark workflow,
  renamed "Add Keys"), but what it commits is per component: only the channels that changed get keys.
- **Distort is two more independent curves**, Perspective X and Perspective Y, beside X / Y / rotation /
  scale / skew — no corner keys, and the graph editor's "declined" state goes.
- **The in-between feature's "keyframe" drawings keep their name** — a different feature.

- [ ] One curve per pose component (`TransformTrack`'s whole-quad keys replaced); a Move keys only the
      components it changed; the graph editor edits each independently.
- [ ] "Add Keyframe" becomes "Add Keys" (priming); commits key only changed components, at every
      primed frame as today.

## (131) Bake an effect, blend or transform layer into the layers below

**Status** — ruled, not started. *"Right now, there is the option to merge down effects
layers with the layer below them. This is an incomplete implementation. Instead, replace that buttons
function with baking: lets say you have 2 layers and a blend mode value layer or effect layer above it.
When that layer bakes, it should adjust the color of all the strokes/objects etc affected below it. In
this case, it is both the layers below. Add the same feature for transform layers."*

**Ruled 2026-10-01:**
- Colour effects and blend-mode value layers bake into each element's colour, over every layer beneath
  in the baking layer's scope.
- **Shape-changing effects** (blur, bloom, glare, outline, sharpen, sobel, CRT, lens blur) **turn each
  affected layer into a raster layer** with the effect applied, after a confirm prompt.
- **Animated effects and moving transforms bake one drawing per frame** the bar covers (unchanged runs
  stay one cel), count and save cost shown first — Bake Animation's rule.
- **What cannot take a colour** (video, stream) **or is only partly covered** (a mask, a stencilled
  effect) **is left as it was, the rest bakes, and a notice says so.**
- **The paper stays white** — Bake changes the drawings only.

- [ ] Merge Down on effect / value / transform layers replaced by Bake, one undo step.

## (119) The eyedropper can sample the layer itself, ignoring what is composited over it

**Status** — not started. *"In the colour picker menu, add a small switch on the top right which
switches the eyedropper between two modes: the first is its current behaviour, and the second should be
that the eyedropper choses the colour of the thing it is over in the layer that it is in. For example if
I add an effect or blend mode on top, it does not affect it. This should be the default. This is also
one of the things the canvas should remember so if the user exits and enters back, it sticks."*

- [ ] The switch, layer mode the default, persisted per document.

## (120) An image's Move box is far bigger than the image

**Status** — not started. *"When moving an image, right now the move box is vastly bigger than the
actual bounding box of the image itself. Fix that."*

## (146) A second finger makes a Move precise

**Status** — not started. *"When in the move menu, add a thing where if the user presses a finger onto
the canvas while moving the box with their pen, it makes the move more precise, like 5x less than the
pen's movement. This should work with recording movement too."*

## (135) Folder Move: every frame or this cel

**Status** — not started. *"If you click on edit on a folder and then click on move, you can move
everything inside the folder. However that only moves everything that is in the current cel. Make the
user have the option in the move menu for folders (the one that has keep stroke width, etc.) to select
between moving things in all frames, or just that cel."*

## (134) A folder cannot be dragged below another folder

**Status** — not started. *"make two folders, then try to move the top folder down below the other.
You can't. Fix this."*

## (122) Timeline: a sticky frame row, seconds when zoomed out, 1.5× taller

**Status** — not started. *"the animation timeline shows the frame number in the top row. When there
are a lot of layers, this top row should still remain on the top and not disappear when scrolling down.
When the timeline iszoomed out it should display seconds instead of frames. Also make it around 1.5x
taller."*

## (123) Timeline: pinch-zoom while panning, as the canvas does

**Status** — not started. *"The animation timeline supports zooming in and out with two fingers, but it
seems that it does not support zooming while panning sideways like the canvas move. Make it do so. I
wonder if you can reuse the canvas pan/zoom code for this to cut clutter."*

## (126) Export straight to Photos

**Status** — not started. *"The export right now saves to files, if possible I'd like it to be saved as
an image (like in the camera roll) directly from the menu. It just needs to pop up in google photos so I
can access it easily."*

## (127) Export: include the padding (default off)

**Status** — not started. *"When I render, there should be an option to include the padding in the
render (default off)."*

## (133) Settings: draw the canvas padding over the artwork (default on)

**Status** — not started. *"In the settings menu as part of canvas padding, add the option to render
canvas padding on top (not below), default on. This means that the canvas border wont get covered up by
the drawings."*

## (132) Direction-following brushes: messy stroke start and end

**Status** — not started. *"For brushes which rotation follows the direction of the stroke, the start
and end of those brushes are messy. I have left a recording to prove this ending in 02122, 50kb."* The
recording is `recording-20261001-002122.jsonl`, pulled to `~/PaintWork/evidence/`.

---

## (27) Stream the computer's screen as a layer

**Status** — briefed 2026-09-13, designed the same day ([STREAM.md](docs/STREAM.md)), and **built through
stage 4 the same day**: the Windows streamer (`streamer/`, installed on the laptop as the `PaintStreamer`
task), the iPad stream layer, the bar with Freeze / Bake Frame, files both ways. On the owner's iPad.
What remains is stage 5 — proving it on the real link with the owner at the laptop — and the one
device figure §5.3 asks for.

**The owner's brief, 2026-09-13, verbatim in the numbered points:**

1. *"The purpose of this feature is to be able to stream my windows computer's screen as a layer live
   on the app. The example use case is that the user will open up blender on their computer, then
   rotoscope a character, move the camera around in the computer, then continue rotoscoping, etc."*
2. *"This feature will require another app that is to be installed on my windows laptop which will
   stream the video to the Ipad."*
3. *"The windows app should also have a drop box for videos or images which when they are pasted into
   or uploaded, will appear on the app via the import video or image feature. If it is also possible,
   make the ipad app able to export to the windows app and save to the laptop."*
4. *"In the app, the stream tool should be under actions, and like a video it makes its own layer with
   the stream object inside of it."*
5. *"When the user is actively on the layer, there should be an options bar (the same kind as move or
   lasso tool), and in it should be the option to freeze the stream, or to bake the current frame. When
   the user presses bake to frame, the current frame in the layer is split as a new cel, and in that
   cel will be an image of the screen when it was baked. For example there are 4 frames and the stream
   layer has one cel stretching the 4 frames. The user is currently on cel 2. Once they hit bake, the
   cel will split into 3 cels: frame 1, frame 2, and frame 3 to 4. the cels in frame 1 and frame 3 to 4
   will not change. However, the cel in frame 2 will have the stream object replaced with an image
   object containing the snapshot of that frame."*
6. *"The paintapp streamer should be low latency and should not lag the main thread. Running it in a
   background thread might be smart, your decision. Note that for the most part, the computer side
   wont move."*
7. *"Just like a video layer, the user should be able to move the stream object in the layer using the
   move tool. The architecture for this is already well established."*
8. *"Note that the user may potentially use many screens or just want to stream a specific app."*
9. *"Note, this part is for the far future. I eventually intend to make the paint app compatible with
   windows, and thus there is the idea that instead of having a separate app, the paint app itself
   contains the streamer. This is a far off feature, but in case the two apps eventually merge, put
   some thought into the design of the architecture of the computer side streamer app. Better to plan
   ahead for potential future changes."*
10. *"There is the case the user may actively stream, then turn off their computer and continue on the
    app, then turn the computer back on and continue streaming."*
11. *"stream layers actively moving do not have to be rendered."*
12. *"The laptop that I want the streamer app in is not this mac but my windows computer. You should
    see it through tailscale."* — it is `desktop-cbr0fl6`, `100.104.85.111` on the tailnet; the iPad is
    `100.70.220.4`. SSH on the Windows box was **closed** on 2026-09-13 and needs the owner to enable
    OpenSSH Server before any Windows-side work can happen from this Mac.

**What is left** — STREAM.md §7 stage 5
- [ ] The owner streams Blender from the laptop to the iPad and rotoscopes over it; source switch,
      window close, laptop lock and reboot behave as STREAM.md §4.5 / §2.8 say.
- [ ] End-to-end latency MEASURED on the real link (a clock on the laptop screen beside the iPad);
      bitrate/GOP tuned if it needs it; numbers into PERFORMANCE.md.
- [ ] The redraw tick's cost MEASURED on the iPad (STREAM.md §8 names the outlet: the
      `ScreenStream` log line or the bar's `streamBar.tickSummary` marker).
- [ ] Owner-verified: Ctrl+V of a bitmap into the drop box (not exercisable over SSH).
- [ ] Known limitation to rule on: a stream layer under a blend mode or effect is not live (46–73 ms
      a tick); the bar says so. Opacity is fine.

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

## Later — the long-term features

**None of these are designed, and each needs its own conversation with the owner before it starts.**

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
