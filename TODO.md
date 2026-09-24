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

## (110) The canvas freeze, again — after changing Dither to Lens Blur

**Status** — filed 2026-09-24. The owner: *"Canvas freeze happened again, The recording is listed on
the ipad but only captures the wedged state with me trying to move the canvas around. Due to the random
and infrequent nature of this canvas freeze bug, constantly recording my actions would produce way too
much data space, so that is out of the question. To guide you however, i changed a dither layer to a
lens blur layer and then tried to move the screen and thats when the canvas move froze. I tried to
recreate it but I cant."* Recording: `recording-20260923-200911.jsonl` (build 2026-09-18, `6f3c691`).

- [ ] Root cause from the recording and the effect-change path; fix; a test that fails without it.
- [ ] A way to catch the *transition* next time that costs no disk until it is wanted.

---

## (101) Streaming: "did not answer", LAN finds nothing, USB

**Status** — filed 2026-09-24. The owner: *"Alot of times like right now, I can see the ipad and the
computer clearly connected to tailscale, but for some reason it says the computer did not answer. The
ipad is doing this right now, no idea why. The Ipad also cannot sense the computer over LAN for some
reason It is also connected to the windows computer via the usb and still cannot see it through that."*
Found the same day: the laptop had rebooted and the streamer was not running (TODO (99) removed its
autostart, as asked), and the app declares neither `NSBonjourServices` nor
`NSLocalNetworkUsageDescription`, so iOS refuses the Nearby browse and any LAN connection silently.
USB was ruled out on 2026-09-17 (docs/STREAM.md §6).

- [ ] The two Info.plist keys; Nearby and a LAN address proved on the owner's iPad.
- [ ] The iPad says *why* it could not connect — the laptop is up but PaintStreamer is not running
      (refused) vs the laptop is unreachable (timeout) vs locked — in words the owner can act on.

---

## (102) The canvas name leaves the animation bar, and Scribble stays off it

**Status** — filed 2026-09-24. The owner: *"Currently it displays the canvas name on the bottom left on
the animation bar. This is ergonomically very bad, as it frequently activates the scribble write mode
when my apple pencil touches near it. Move it to the top left and disable the scribble feature. Text
writing has a similar disable scribble feature, I wonder if you can reuse that code."*

- [ ] The name at the top left; Scribble cannot start on it (the text tool's mechanism, reused).

---

## (103) Add (+) is its own top-bar icon, with shapes and a gradient

**Status** — filed 2026-09-24. The owner: *"The add button (+) is located under actions. Make it a
seperate independant icon on the top bar. Additionally, put other things under the add like add
square/rectangle, circle/ellipse, add linear gradient."*

- [ ] A top-bar + icon holding Insert Photo, Insert Video, Stream Screen, Add Text, Rectangle,
      Ellipse, Linear Gradient.

---

## (104) A Settings icon; Actions keeps only the actions

**Status** — filed 2026-09-24. The owner: *"Along with the new add icon, there should also be a
settings icon. Move resize canvas, canvas padding, bake percise strokes, fingers can paint, render
resolution to it. In actions should be cut, copy, paste, flip horizontal, flip vertical, export in that
order."*

- [ ] Settings: Resize Canvas, Canvas Padding, Bake Precise Strokes, Fingers Can Paint, Render
      Resolution (and whatever else in Actions is a setting, e.g. Record My Actions).
- [ ] Actions: Cut, Copy, Paste, Flip Horizontal, Flip Vertical, Export — in that order.

---

## (105) A video's speed follows the scene's frame rate

**Status** — filed 2026-09-24. The owner: *"When the fps is set to 12fps instead of 24 and it has an
inserted video, then that video should play twice as slow, not two times. Right now it plays the same
speed regardless of what fps you set."*

- [ ] A video advances one step per animation frame, so halving the scene's fps halves its speed.

---

## (106) Colour picker, second pass

**Status** — filed 2026-09-24. The owner: *"The color picker wheel's color is not accurate and rotated
around 90 degrees out of phase. The red on the wheel is right, but red is selected at the top.
Additionally, The wheel and the square/triangle inside should be a lot bigger, and the width of the ring
slightly smaller. Make the color picker itself as big as possible within the GUI (the diameter of the
circle is just under the width of the tab) Remove the disc color picker. If you look at the actual color
picker for triangle (and disc), the edges are very pixelated, not smooth. Fix. The triangle also should
be rotated 90 degrees clockwise. The opacity slider should also display the color like in the image.
Next, the current and previous color section takes up way too much space. Put it in the top left. The
image I attached is a good reference. Try to get it to look like it. Try to make everything compact."*
The reference (2026-09-24): a compact dark panel; current and previous colour as two overlapping
circles at the top left; a large hue ring nearly the panel's width with a triangle inside whose
full-hue vertex points right; below it an opacity bar drawn as a checkerboard fading into the colour,
with a round thumb; a **Recent** row of swatches; the palette's name and swatch grid; a bottom tab bar
(Classic, Wheel, Values, Pick, Palettes).

- [ ] Hue phase: the marker and the drawn ring agree (red picked where red is drawn).
- [ ] Disc removed; the ring as large as the panel allows, thinner; the inner shape larger; edges
      antialiased; the triangle turned 90° clockwise.
- [ ] Opacity bar in the colour over a checkerboard; the swatches compact at the top left; the whole
      panel compact, to the reference.

---

## (107) The onion skin panel is 25% wider

**Status** — filed 2026-09-24. The owner: *"The onion screen seems a bit too horizontally compressed.
Make it around 0.25x more wider."*

- [ ] 1.25x the width, the layout breathing into it.

---

## (108) To New Layer's cel spans the cel it was lifted from

**Status** — filed 2026-09-24. The owner: *"When I press to new layer on a selection, it makes a new
layer but makes the cel cover the entire length of the animation. Make it so the cel is just as long as
the cel it was lifted from."*

- [ ] The new layer's cel has the source cel's start and length.

---

## (109) Select panel: Edit sits beside Fill and To New Layer

**Status** — filed 2026-09-24. The owner: *"The edit button in the select menu should be beside fill
and to new layer."*

- [ ] Edit in the same row as Fill and To New Layer.

---

## (79) Brush size and opacity sliders — the follow-ups

**Status** — the log curve is **ruled** (the owner, 2026-09-24: *"the logorithmic brush size changer on
the ipad feels very nice"*). What is left, in their words: *"I noticed that the eraser does not have
it. Additionally, the % of screen size icon should not be there, it should only display the % when the
user is actively adjusting it, and it should display right over or under the brush size pop up
indicator. There also seems to be a bug where if I start drawing while holding the size indicator, the
indicator stays on the screen even when i lift my finger off the slider."*

- [ ] The eraser's size slider uses the same `BrushSizeCurve`.
- [ ] No permanent % badge over the icons; the % shows only while adjusting, beside the size pop-up.
- [ ] Drawing while a finger holds the slider, then lifting it, leaves no indicator on screen.

---

## (86) The canvas-size ceiling comes from the device, not a constant

**Status** — the fill half closed 2026-09-17 (`FillWindow`). The 6000 ceiling was MEASURED to be this
iPad's (docs/PERFORMANCE.md §22.2). The owner, 2026-09-24: *"Is 6k the true upper limit of this ipad
with no possible way to make it 16k? Like virtual memory or something. If so then that is okay, as a
limitation of the ipad, but remember: No part of this program should be specifically tuned for this
ipad only. Anything like this should automatically change based on the specs of the machine. For
example, running the paint app on a better ipad or another device should not necessarily limit the
canvas size to 6k, only whatever is best."*

- [ ] The ceiling is computed from the running device's memory and a MEASURED per-pixel cost model,
      not a literal; audit every other device-tuned constant the same way (ring budgets, fill budget,
      strip heights) and derive each from the machine.

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
