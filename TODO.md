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

## (68) The 2026-09-13 iPad build (`d398588`) regressed the app — four felt, more suspected

**Status** — filed 2026-09-16 from the owner's brief; BUGS.md's newest entry names the suspect
commits. **The four recordings the owner made on the iPad are the evidence** — pulled 2026-09-16 into
the session scratchpad from `Documents/Recordings/`: `recording-20260915-040910` and
`recording-20260915-215123` are the Move-node bake (#1, #2), `recording-20260916-014412` is the
freeze (#3), `recording-20260916-152252` is playback (#4).

**The owner, 2026-09-16:** *"The build currently shipped on the ipad by the previous session has
shipped significant regressions and bugs. Note: the amount of regressions triggers an alarm for me.
There being this many means that more undiscovered bugs could have been made. I want you to be able to
have the confidence at the end of fixing these that most if not all regressions are likely covered,
including the potential ones that have not been discovered yet. Remember that clean code and
architecture is a priority of this project. Find the root causes and fix it, don't slap on a messy fix."*

1. *"FPS is no longer smooth during animation playback. This hints that some heavy operation is being
   run every frame, or the pre-render bake isn't working properly. It is supposed to be 60 on the ipad,
   right now it is around 20 to 30. Recording #4 (latest) is proof of this. Remember, tests on ipad are
   the source of truth."*
2. *"The canvas freeze is back. I again cant find the combination of inputs which caused it, but
   recording 3 is me trying to do actions (i think it was moving the canvas) while it is frozen."*
3. *"I cant move the canvas when by touching outside the canvas. I suspect this one could be deep and
   connected to many more bugs."*
4. *"the bug where moving a node in the move tool baking the move is back. Recordings 1 and 2 are
   evidence."*

**What is left**
- [ ] Root cause and fix for each of the four, from the recordings and the `94caa67..d398588` diff.
- [ ] A sweep of that whole diff for regressions the owner has not felt yet, with the same standard.
- [ ] A Release build on the iPad, driven as CLAUDE.md says — play a scene, pan from the grey, drag
      and release a Move node, draw a stroke — and the owner's confirmation.

---

## (71) A layer folder's Move selects everything in it and uses the Move tool

**Status** — filed 2026-09-16. The owner: *"Currently there is a transform move in layer folders that
makes the folder function as a transform layer. I like that, but make it select everything in the
folder and use the move tool on it instead of a transform layer behaviour."*

- [ ] Folder Move = select every element in every layer of the folder, then the ordinary Move tool.

---

## (75) Move tool: a toggle to keep brushstroke size constant

**Status** — filed 2026-09-16. The owner: *"In the move tool, there should be a toggle where there is
the option that the brushstroke size is constant. Right now I believe it scales with the move."*

- [ ] The toggle in the Move options bar; off = today's scaling, on = stroke width unchanged by the move.

---

## (93) Move menu: a "cut" beside Duplicate

**Status** — filed 2026-09-16. The owner: *"beside the duplicate option in the move menu, there should
be a cut option (think of a better name if possible). What this does is duplicate the selection, then
erase it, so that the stuff in the selection is put into another layer and removed from the original."*

- [ ] The option, named better than "cut" if a better name exists; one undo step.

---

## (94) Tapping the Select tool off clears the selection

**Status** — filed 2026-09-16. The owner: *"when the select tool icon is deselected (clicked), the
selection disappears."*

- [ ] Deselecting the tool clears the selection.

---

## (95) Selecting again unions with the existing selection; a subtract toggle

**Status** — filed 2026-09-16. The owner: *"When the select tool is used again while a selection
already exists, then the new selection should be the boolean union of the two. A toggle to make a
boolean subtract would also be nice."*

- [ ] Union by default; a subtract toggle in the Select panel.

---

## (90) The brushstroke editor in the Select menu collapses to one icon

**Status** — filed 2026-09-16. The owner: *"The brushstroke editor in the select menu is taking an
entire layer. It should be a single icon, which expands that menu when pressed."*

- [ ] One icon in the panel; pressing it expands the editor.

---

## (80) Eraser mode: erase every line it touches

**Status** — filed 2026-09-16. The owner: *"Add a new eraser mode that just erases every line it
touches."*

- [ ] A fourth eraser mode beside the three CSP-style ones: any stroke the eraser touches is deleted whole.

---

## (81) Erase strokes that erase nothing are killed automatically

**Status** — filed 2026-09-16. The owner: *"Erase strokes that have no effect on the canvas (erasing
nothing) should be automatically killed."*

- [ ] An eraser stroke that touched no ink leaves nothing in the cel and no undo step.

---

## (82) Eraser sidebar: a Universal toggle — erase on every visible layer

**Status** — filed 2026-09-16. The owner: *"In the sidebar for the eraser, add a simple toggle to
switch into universal mode or not. Universal mode simply makes the eraser apply to all visible layers.
Note: for normal erase, the erase stroke will only appear on the layer if it is actually erasing
something. Otherwise there is no need for it there. Note, item 13 probably automatically applies this
behaviour because the strokes touching nothing will be removed."* ("item 13" is (81).)

- [ ] The toggle; in universal mode the stroke lands only on the visible layers where it erased something.

---

## (83) Cut erase still leaves stubs, and misses small strokes among many overlaps

**Status** — filed 2026-09-16. The owner: *"the cut erase still sometimes leaves stubs, and also small
strokes inside the circle sometimes dont get killed when there are a lot of overlapping strokes in a
small space."*

- [ ] Reproduce both in a logic test on a dense overlapping fixture; fix the geometry, not the threshold.

---

## (85) Splitting a stroke resets the randomizer seed for one half

**Status** — filed 2026-09-16. The owner: *"When a stroke is split, the randomizer seems to reset the
seed for one half of the stroke. Make it so splitting a stroke does not change half the entire stroke."*

- [ ] Both halves of a split render their dabs exactly as the unsplit stroke did.

---

## (84) A set stroke changes when it bakes

**Status** — filed 2026-09-16. The owner: *"I've noticed that after a stroke is set, the stroke changes
when it bakes. This may be inevitable as a concequence of the interpolation, but try to fix it the best
you can."*

- [ ] Find what differs between the live stroke and its baked pixels; close the gap where it can be closed,
      and name what cannot.

---

## (76) Autosave

**Status** — filed 2026-09-16. The owner: *"Right now I think the app saves too infrequently, or it
only saves when you exit to gallery. Make an autosave feature that saves whenever the system can afford
it or on intervals, or some other system, you decide. The one thing is that it must not lag out the main
thread or operations. User experience should remain unchanged, the autosave should practically be
unnoticeable that it happened."*

- [ ] Off the main thread, incremental where the store allows, MEASURED not to touch a stroke or playback.

---

## (77) Leaving to the gallery and coming back resets editor state

**Status** — filed 2026-09-16. The owner: *"Right now going out of the canvas to gallery then back
resets a bunch of things, like your brush size and opacity, the frame you are on, etc."*

- [ ] Brush size, opacity, current frame, and whatever else resets today survive the round trip.

---

## (87) Exiting a canvas returns to its folder in the gallery

**Status** — filed 2026-09-16. The owner: *"exiting a canvas should exit to the folder that the canvas
is in in the gallery."*

- [ ] The gallery opens on the document's folder, not the root.

---

## (78) Layer thumbnails show the cel on the current frame

**Status** — filed 2026-09-16. The owner: *"The thumbnails in the layers menu don't accurately reflect
the layers on that frame. Sometimes they show the cel of a different frame. Make them do so."*

- [ ] A thumbnail is the current frame's cel for that layer, on every frame change.

---

## (69) Onion skin: tap toggles, hold opens the menu

**Status** — filed 2026-09-16. The owner: *"lets make it so tapping the onion skin icon toggles it,
and the menu is opened by holding the icon for a short time."*

- [ ] Tap = toggle; a short hold = the menu.

---

## (70) Onion skin UI redesign

**Status** — filed 2026-09-16. The owner: *"I dont like the current onion skin UI. Try to make it look
better, like the image I linked. More compact and clean."* The reference is a compact dark panel:
Drawings/Frames mode row; Behind / In Front tabs; Previous Drawings and Next Drawings count sliders with
a link toggle between; Tinted / Original Colors with a red→green tint bar; per-drawing Opacity sliders
with a link.

- [ ] The panel rebuilt to that layout, on the app's existing controls.

---

## (72) One colour picker — the onion skin's is a second one

**Status** — filed 2026-09-16. The owner: *"the color picker in onion skin isnt the same color picker
as the color picker used in everything else, which means that we have 2 color pickers, bloating the
code. Make it the same as the normal color picker and cleanly delete all the bloat."*

- [ ] Onion skin uses the app's picker; the second picker and everything only it used is deleted.

---

## (73) Colour picker overhaul

**Status** — filed 2026-09-16. The owner: *"the color picker should be overhauled. There should be many
types, such as the one shown in image 2 with the triangle in the center and one with a square in the
center, etc. The procreate color picker is Image 3, and in it is the color history and selected palette
in the same tab which I would like you to have. In image 4 is the palette menu where you can modify the
palletes."* Image 2: a hue ring with an HSL triangle inside, HSL1–4 / IMG tabs, Hue/Saturation/Lightness
fields and a hex readout. Image 3 (Procreate): a hue ring with a saturation/brightness disc inside,
current + previous swatches top right, then **History** with a Clear button, then the selected palette's
name and swatch grid, and a bottom tab bar Disc / Classic / Harmony / Value / Palettes. Image 4
(Procreate Palettes tab): a list of named palettes, each a swatch grid with a Set Default button, and a
"New palette" action.

- [ ] Picker types: ring + triangle, ring + square, ring + disc (Procreate's), at least; a tab bar to switch.
- [ ] History and the selected palette on the picker tab itself.
- [ ] A palettes tab: create, rename, delete, set default, edit swatches.

---

## (74) Lens blur effect

**Status** — filed 2026-09-16. The owner: *"new lens blur effect. Simulates the type of blur an actual
defocused lens would produce like bokeh, etc."*

- [ ] A disc/polygon-kernel blur with highlight bloom in `Effect`, Metal and CoreGraphics backends at parity.

---

## (88) The drawing guide becomes a value-layer effect

**Status** — filed 2026-09-16. The owner: *"right now the drawing guide in actions does nothing. I
think it is best to remove it from actions and instead make it as an effect in value layer. Include grid,
isometric, perspective modes."*

- [ ] Remove the Actions entry and whatever it reached; a Guide effect with grid / isometric / perspective.

---

## (92) Effects apply to vector layers, masked by the layer's opacity

**Status** — filed 2026-09-16. The owner: *"effects should apply for vector layers too, not just value
layers. The rule is that it uses the layer's opacity as a mask for the effect. In the future I may have a
more complex assigner, such as being able to assign different values to different properties, but thats
for the future."*

- [ ] An effect on a vector layer grades the composite below, masked by that layer's own alpha.

---

## (79) Brush size and opacity sliders read in %, size possibly logarithmic

**Status** — filed 2026-09-16. The owner: *"Make the brush size slider on the left bar measured in %
of canvas size. Experiment with making it logarithmic to its actual size to offer finer control on
smaller brushes, though I probably have to experience it to decide if I like it or a simple linear scale.
The % should be displayed on top of the size logo so you know what it is. Same for opacity, though
opacity is just a linear 0 to 100."*

- [ ] Size in % of canvas, a log curve on the slider; opacity linear 0–100; the % drawn over each icon.
- [ ] The owner feels the log curve on the iPad and rules log or linear.

---

## (86) Canvas sizes over 6k, and the fill tool's memory

**Status** — filed 2026-09-16. The owner: *"Right now, canvas sizes over 6k are banned, as well as
using the fill tool because it takes too much memory. Try to find a way to fix this if there is a way.
The fill tool especially, I don't see why it should ever have a memory complexity which is affected by
the canvas size. For the canvas size, if it is genuinely too much to put into memory, then experiment
with virtual memory caching like the renderer already does with layers."*

- [ ] Fill at a resolution independent of the canvas extent (a bounded scan, or fill at a working
      resolution and vectorise), with the figure MEASURED.
- [ ] The 6k ban lifted where the strip compositor and the frame store already make it affordable.

---

## (91) The Views menu in Layers: delete and rename

**Status** — filed 2026-09-16. The owner: *"The views menu in layers may need a second look. For one,
you cant delete any views or rename them."*

- [ ] Delete and rename a view; a second look at the rest of the menu.

---

## (89) Organise the feature `.md` files into a folder

**Status** — filed 2026-09-16. The owner: *"It may be worth organizing all the feature .md files into
a folder since most of them are archived."*

- [ ] Move the archived feature specs under one folder; fix every link in CLAUDE.md, HANDOFF.md, README.md.

---

## (96) A stream does not reload when its frame becomes current or its layer visible

**Status** — filed 2026-09-16. The owner: *"The stream does not reload when the computer updated
while on a different frame, and then the frame changes onto the one with the steam. Same with hidden
streams made visible, etc."*

- [ ] A stream cel that becomes visible (frame change, layer shown) redraws with the latest picture.

---

## (97) The iPad crashed while the stream was on

**Status** — filed 2026-09-16. The owner: *"I have experienced multiple times the ipad crashed while
the stream was on."*

- [ ] Pull the crash logs from the iPad; fix the cause.

---

## (98) Same-network or USB streaming instead of Tailscale

**Status** — filed 2026-09-16. The owner: *"If possible, adding the option for same-network or usb
connection for streaming instead of tail scale will be nice."*

- [ ] LAN: the admission rule widened from Tailscale addresses to the local subnet; USB if the iPad
      exposes one.

---

## (99) The Windows streamer is a normal program: launch on click, no autostart

**Status** — filed 2026-09-16. The owner: *"The computer side program right now starts up on startup
and there is no app. Make it just like any normal computer program, clicking the app launches the
program, and it shouldn't start up every time the computer is started."*

- [ ] No scheduled task at logon; a Start-menu/desktop app the owner double-clicks; the tray stays.

---

## (100) Actions menu: an "Add" entry holding Insert Photo, Insert Video, Stream Screen, Add Text

**Status** — filed 2026-09-16. The owner: *"the actions menu right now has a bunch of stuff thrown
into it. Add an "add" icon, and in it move insert photo, insert video, stream screen, add text."*

- [ ] The four entries move under one Add submenu.

---

## (27) Stream the computer's screen as a layer

**Status** — briefed 2026-09-13, designed the same day ([STREAM.md](STREAM.md)), and **built through
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
