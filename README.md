# PaintSoftware - iPad Drawing and Animation App

A Procreate-like drawing and animation app for iPad, built around a custom native-resolution
raster/vector drawing engine (no PencilKit), with layers, a full brush/eraser/fill/select-move
toolset, and a frame-by-frame animation timeline.

## Features

- **Drawing engine**: native-resolution raster strokes (own engine, not PencilKit — stays crisp at
  any zoom), plus resolution-independent vector layers that can be moved/rotated/scaled losslessly
- **Brushes**: a brush library (shape, hardness, spacing, stabilization, pressure dynamics) with
  custom brush import, and a matching Eraser tool with its own settings
- **Fill**: GPU (Metal) colour-based flood fill with adjustable threshold/gap-closing/edge-overlap,
  live drag-to-adjust before committing, and per-layer "fill reference" boundaries
- **Select & Move**: lasso/rectangle/automatic (magic wand) selection, a **Tap** mode that selects
  whatever object you tap, move/duplicate with resize/rotate/mirror, and a selection-clipped
  paint/fill mode. A loop around a text box and/or a gradient (or a tap on one) offers **Edit Text**
  and **Edit Gradient**, one button per kind caught, each opening that object's own panel live. A
  turn on any rotate knob shows its angle in a pill beside it, and a finger laid on the glass during
  a pen drag makes the drag a fifth as fast (**precision touch**) or, on a rotate knob, snaps the
  turn to 15° steps
- **Layers**: three kinds — **raster** and **vector** hold pixels, and a **value** layer holds none.
  Plus opacity, visibility, fill-reference toggle, object (photo) layers with on-canvas transform
  handles, and groups that composite as parentheses — isolated or pass-through, with their own
  opacity, blend mode and mask
- **Value layers, two modes in one kind**: with no effect set it is one flat colour across the canvas
  (Photoshop's Solid Colour layer); set an effect on it and it becomes an adjustment layer, grading
  everything below it inside its own container. Which mode it is in is decided by whether it carries
  an effect — there is no separate kind and no mode switch to keep in sync
- **Transform layers**, a kind of their own: a layer with no pixels that moves everything beneath it in
  its container through the Move box, keyframable; it acts only on the frames its timeline bar covers
  (TRANSFORM_LAYER.md)
- **Compositing**: 25 blend modes on layers and groups, following W3C Compositing Level 1 rather than
  `CGBlendMode` where the two disagree; render-time alpha masks (never baked, raster and vector
  alike, including "clip to below"); and compositor **nodes** — a node's direct children are its
  inputs, bottom child first, and its dropdown picks either a blend op (two inputs) or one of the
  effects (one input). Picks its backend per composite: the GPU (Metal) for anything that grades or
  has four or more layers, the Core Graphics implementation — which is also the byte-for-byte
  reference and the fallback where there is no GPU — below that, because the two have opposite cost
  shapes on real hardware. A composite is bounded by the device it runs on (`CompositorBudget`)
  without ever being made smaller: a frame whose working set would not fit — a 4K canvas with two
  effect layers on a 3 GB iPad — is walked in horizontal strips, and within a strip node by node, at
  the size that was asked for. The canvas at rest and playback are not composited on demand at all;
  they are read from a background bake on disk. See [LAYER_COMPOSITING.md](docs/LAYER_COMPOSITING.md) and
  [RENDER.md](docs/RENDER.md)
- **Effects**: 20, all configurable from the layer panel — levels, curves, brightness/contrast, HSV
  shift, gradient map, recolour, colour wheels, posterize (with dither and halftone screens), noise,
  gaussian/directional blur, lens blur (a disc or blade-polygon defocus with a highlight boost for
  bokeh), sharpen, bloom, sobel, outline, duplicate offset, chromatic aberration, computer screen,
  glare and a drawing guide (grid, isometric or perspective lines drawn over the picture) — with a
  curve editor, a gradient-stop editor, a colour-pair list and four colour wheels for the ones that
  need them. One shader per effect on both backends, used by every wrapper (value layer, node, and a
  vector layer's own ink)
- **Canvas**: adjustable padding margin, flip horizontal/vertical, custom size presets, and a
  **render resolution** setting (Full / 75% / 50%) that trades live-canvas sharpness for speed on
  heavily layered artwork — it reaches only what is on screen, never the saved file or the export
- **Vector eraser**: three CSP-style modes (erase, cut points, cut to intersection) and a fourth,
  Whole, that deletes every line the footprint touches. An eraser *is* a stroke — it is an `.erase`
  element in the same z-ordered display list as the paint it eats, so it is non-destructive and
  undoable, and Mode 1 splits a cleanly severed stroke into real pieces. A gesture that touches no
  ink lands nothing and records no undo step. In Mode 3 the brush size is a **selection radius**, not
  just a reach: every stroke whose centreline the circle covers is cut back to its own nearest
  crossings outside the circle, so erasing where two lines meet takes both. The circle is drawn on
  the canvas under the finger while the gesture is live. A **Universal** switch in the eraser panel
  aims one gesture at every visible vector layer at once, as one undo step
- **Animation Timeline**: multi-cel frame-by-frame animation, scrub/play, per-cel copy/clear/extend
- **Keyframe interpolation** on vector layers: mark two cels as references and the cels between them
  become derived (lattice + ARAP warp), with motion groups, guide strokes, editing at an in-between
  and Commit — see [VECTOR_INTERPOLATION.md](docs/VECTOR_INTERPOLATION.md)
- **Color**: four picker types over one shared colour model, switched by a bottom tab bar — **Wheel**
  (a hue ring with an HSL triangle, Paint Tool SAI/Krita's, the triangle's full-hue vertex pointing at
  the ring's own red), **Classic** (a hue ring with the SV square), **Values** (H/S/B sliders) and
  **Palettes** (the multi-palette library: create/rename/delete/set default, each with its own swatch
  grid). The ring fills nearly the panel's own width; current/previous sit as two small overlapping
  circles at the top-left rather than a labelled row, and the opacity control is a checkerboard bar
  fading into the current colour. Every type tab also shows a **Recent** strip of the last colours
  actually used to paint and the selected palette's grid — tap a swatch to pick it, long-press an
  empty cell to add the current colour. **One picker for the whole app** — brush, canvas background,
  value layer, effect colour, gradient stop, onion tint and selection style all open the same panel,
  and the only thing that varies between call sites is whether opacity is offered. Plus an
  **eyedropper** on the side rail: select
  it, tap the canvas, and the colour under the tap becomes the brush colour. A switch at the picker's
  top right chooses **Layer** (the default: the object under the tap in the colour it was painted,
  on whichever layer it is) or **Canvas** (what is on screen, effects and paper included); it
  reverts to the previous tool
- **Gallery**: a project browser with thumbnails, backed by on-disk project packages
- **Saving**: automatic — a few seconds after you stop editing, and every half minute while you
  do not stop — as well as when you leave to the gallery or the app goes to the background. Each
  save is atomic (staged, validated, then swapped in), writes only the cels that changed, and keeps
  the artist's thread out of it. Coming back from the gallery lands where you left: same frame,
  layer, zoom, onion skin and loop range are the document's; brush size, opacity, colour, tool and
  eraser follow you between documents
- **Gestures**: two-finger zoom, rotate, and pan

## Project Structure

```
PaintSoftware/
├── PaintApp.swift              # App entry point
├── ContentView.swift            # Root view (gallery <-> editor)
├── Engine/                      # Drawing engine
│   ├── RasterLayerTexture.swift #   persistent per-cel raster bitmap (stamp-based, thread-safe)
│   ├── VectorLayer.swift        #   resolution-independent vector layer content
│   ├── BrushStamper.swift       #   shared stamp pipeline (shape/dynamics)
│   ├── Brush.swift / BrushLibrary.swift
│   ├── StrokeInput.swift / StrokeStabilizer.swift
│   ├── StrokePath.swift         #   the refit (which samples are stored) and the curve every tier walks
│   ├── StrokeGeometry.swift / VectorEraser.swift  # vector eraser geometry + the four modes
│   ├── Eyedropper.swift         #   which pixel a canvas point names, and its colour (pure)
│   ├── InterpolationEvaluator.swift / GuidePath.swift
│   ├── Deform/                  #   lattice + ARAP deformation (app-type-free)
│   ├── Fill.metal / MetalFillEngine.swift  # GPU flood-fill
├── Models/
│   ├── CanvasManager.swift      # Core state/operations (layers, cels, tools, undo)
│   ├── InterpolationRecipe.swift / MotionGroup.swift / GuideStroke.swift
│   ├── SelectionModels.swift    # Select & Move tool operations
│   ├── Palette.swift / ColorHistory.swift  # Custom color palettes; last colours used to paint
│   └── ProjectManifest.swift    # On-disk project schema
├── Services/
│   ├── ProjectStore.swift       # Save/load a project package
│   ├── ProjectBackupManager.swift # Atomic saves, version history, trash, launch repair
│   ├── SaveDamageGate.swift     # What a save may do when the project loaded with something unreadable
│   └── PixelOps.swift           # Image compositing helpers
├── Utilities/
│   ├── ColorConversion.swift / ColorMath.swift
│   ├── ThumbnailRenderer.swift
│   └── AppVersion.swift
├── Debug/                       # off-by-default diagnostics (see "Action recorder" in CLAUDE.md)
│   ├── ActionRecorder.swift     #   records touches/recognizers/model changes to JSONL
│   └── WindowEventTap.swift     #   the one `sendEvent` interception it installs while recording
└── Views/                       # SwiftUI + UIKit-bridged views
    ├── CanvasView.swift, DrawingView.swift, ContentView-adjacent panels
    ├── TopToolbar.swift, SideToolbar.swift
    ├── LayerPanel.swift, LayerStackListView.swift, LayerStackCell.swift, EffectSection.swift
    ├── AnimationTimeline.swift, TimelineTrackView.swift (the rows), TimelineRulerStrip.swift (the pinned ruler)
    ├── ColorPickerPanel.swift, ColorPickerShapePickers.swift, PalettesLibraryView.swift,
    │   BrushSettingsPanel.swift, EraserSettingsPanel.swift, FillSettingsPanel.swift, SelectPanel.swift
    ├── ObjectTransformOverlayView.swift, FloatingPieceOverlayView.swift, SelectionOverlayView.swift
    ├── CanvasNoticeBanner.swift, DamagedSaveBanner.swift
    ├── GalleryView.swift, GalleryTileView.swift, CanvasSizePickerView.swift, ActionsMenu.swift
    └── ActionRecorderControls.swift
tools/
└── recording2xcuitest.py        # turns an action recording into a draft XCUITest
```

## Requirements

- Xcode 26 or later
- iPad simulator or device — this is an iPad-first app; the UI test suite specifically needs an iPad
  destination (an iPhone simulator's cramped layout fails several tests)
- Apple Pencil recommended, not required (finger drawing works out of the box)

## Building and Running

1. Open `PaintSoftware.xcodeproj` in Xcode.
2. Select an iPad simulator (or a connected iPad) as the run destination.
3. Press `Cmd + R` to build and run.

To run the UI test suite: `Cmd + U`, or via the command line:

```bash
xcodebuild -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination 'platform=iOS Simulator,name=<an iPad simulator>' test
```

### Deploying to a physical iPad

1. Connect the iPad via USB, select it as the run destination in Xcode, and set your team under
   **Signing & Capabilities**.
2. On first launch you may need to trust the developer certificate: **Settings → General → VPN &
   Device Management → [your developer profile] → Trust**.
3. For distribution without a cable, archive (**Product → Archive**) and distribute via TestFlight.

## Usage Guide

### Creating a Canvas
1. Launch the app into the Gallery.
2. Tap "New Canvas", pick a size preset (or custom dimensions), and tap "Create Canvas".

### Drawing
1. Pick Pen/Pencil, Eraser, Fill, or Select/Move from the top toolbar.
2. Adjust size/opacity (or a tool-specific setting) from the side rail sliders, or open the tool's
   panel for its full settings (shape, stabilization, etc.).
3. Pick a color from the color picker — Wheel, Classic or Values, whichever tab you're on — or a
   saved palette swatch, a recent colour from the Recent strip, or the Palettes tab's library.
   **There is one picker**: the same panel drives the brush, the canvas background, a value layer's
   colour, an effect's colour, a gradient stop, the onion tint and the selection style, differing
   only in whether it offers opacity.
4. Or take a colour off the artwork: tap the eyedropper below the side rail's opacity slider, then
   tap the canvas. In **Layer** mode (the default) it takes the colour the object under the tap was
   painted in; in **Canvas** mode it takes what you can actually see, effects and paper included. Either
   way it hands the canvas back to the tool you were using.
5. Draw with your finger or Apple Pencil (toggle "Apple Pencil only" in the side rail if you want to
   ignore accidental finger/palm touches while drawing with a Pencil). The toggle gates **strokes and
   the fill tool alike**, and the lasso and the eyedropper with them; two-finger pan/zoom/rotate
   stays on a finger either way.
6. If a touch cannot draw — no layers, the active layer hidden, or a layer with no drawing surface —
   a banner appears under the top toolbar saying which, with the fix as a button. It dismisses itself
   and never interrupts the stroke.
7. **Outside the paper is still canvas, only not drawn.** A stroke, a lasso or a two-finger pan can
   start on the black around the paper, and a Move box grip, a smart-shape node or a text handle out
   there takes a drag exactly as it would on the paper — one rule, `CanvasPlaneView`. A fill tapped
   out there floods from the nearest edge of the canvas; the eyedropper finds nothing to pick.

### Fill
1. Select the Fill tool and tap inside a region bounded by content on the current layer's fill
   references.
2. Drag to adjust threshold/gap-closing/edge-overlap live before it commits; it also stays adjustable
   after lifting your finger until you draw elsewhere or start a new fill.
3. Toggle which layers count as fill boundaries with each row's drop button, shown while a layer's
   options menu is open. Shown layers are boundaries and hidden ones are not, until you say otherwise
   — after which your choice sticks through the eye icon.

### Select & Move
1. Pick a selection mode (lasso, rectangle, automatic/magic-wand, or Tap) from the Select bar.
2. Draw a selection — or, in Tap mode, tap an object (text opens its editor, a gradient its panel);
   Single/Add/Subtract chooses how a tap meets what is already selected — then Move/Duplicate/Fill/
   Clear it, or switch to the Move tool to drag/resize/rotate/mirror the selected (or, with no
   selection, the whole) layer content. While you drag a handle with the pen, a finger on the canvas
   slows the drag to a fifth; on a rotate knob it snaps the turn to 15° steps, and the angle shows in
   a pill beside the knob. A smart-shape line snaps the same way.
3. "Paint Outside Selection" (off by default) controls whether strokes/fills can spill past the
   selection boundary.

### Layers
1. Open the Layers panel from the top toolbar.
2. **Tap** "+" for the menu: a raster, vector, value or transform layer, a group, a compositor node,
   or a photo as an object layer. The new item lands **directly above the active layer, inside that layer's own
   container** — not at the top of the document.
3. Adjust opacity with the slider, toggle visibility with the eye icon, tap a row to make it active.
4. Tap the active row again for its options menu (rename, blend mode, merge down — or **Bake** on an
   effect, flat-colour or transform layer — delete). While one is
   open every row carries a checkmark to clip that layer to, and a drop to make it a fill boundary.
   Mask opens as a sub-menu in place, with a Back button; so does a compositor node's Effect
   Settings, docked at the bottom of the screen.
5. Swipe a row to Duplicate or Delete.
6. Drag a row to reorder it. Dropping onto another layer reorders — it does not group; drop onto a
   folder or node row to go inside one. The row you are dragging leaves its slot, and an orange
   guide shows where it will land and at what indent.

### Value layers and effects
1. Add a value layer from the "+" menu. Out of the box it is a flat colour, Normal blend — pick the
   colour from the row's colour swatch.
2. Its options menu opens on **Blend Mode**, one merged menu listing every blend mode plus the 20
   effects below them, grouped under Colour, Blur & Light, Stylise and Guides. Pick a blend mode and
   the layer is a flat colour composited that way; pick an effect and it becomes an adjustment layer
   instead, grading everything beneath it inside its own container. The two are answers to the same
   question, so picking one always clears the other. The row itself is never hidden — it shows the
   effect's name in place of the blend mode's while one is set, and the colour swatch below it goes
   away for the same reason.
3. **The effect's settings are on screen whenever its layer is the active one** — docked at the
   bottom of the screen above the timeline, with no extra tap — and go when another layer is
   selected. They include a curve editor (Curves) and a gradient-stop editor (Gradient Map). The
   layer rail stays open beside them, and neither a pan, a pinch nor a tap on the canvas closes them.
4. A compositor node's operation dropdown offers the same effects beneath the blend ops. A blend op
   takes two inputs; an effect op takes one, so it grades that input's composite as a unit.
5. A value layer or node renames itself to follow the effect you pick, unless you have renamed it by
   hand — after which it keeps your name.
6. **A vector layer takes an effect too**, from the same merged menu, and its own ink is the mask:
   paint a blob on a vector layer, pick Gaussian Blur, and what is under the blob blurs — the blob's
   colour is not drawn, the blob is the stencil, and the layer's opacity scales how strongly the
   effect reaches through it. A raster layer does not; a vector layer keeps its name.
7. **A drawing guide is the Guide effect on a value layer**: grid (spacing, subdivisions), isometric
   (angle, spacing) or perspective (a horizon and one or two vanishing points typed in as shares of the
   canvas — no on-canvas handles yet), each with a line width, colour and opacity, drawn in canvas
   pixels over everything beneath the layer. Hide the layer before you export.

### Animation
1. Expand the timeline at the bottom to manage cels/frames.
2. Tap a cel block for Copy/Extend to End/Clear/Delete; tap an empty gap to add a new cel there.
3. Drag a cel's edges to resize its frame range; scrub the ruler or press Play to preview.

### Canvas
- **Actions menu**: Cut/Copy/Paste a selection, flip horizontal/vertical, export. The export sheet
  makes a video or one frame as a PNG; **Save to Photos** is the primary action, beside the share
  sheet and Send to Computer, and **Include Padding** (off by default) adds the canvas's padding
  margin around the artwork.
- **Settings menu**: resize the canvas, adjust canvas padding (a drawable margin around the artwork),
  bake precise strokes, fingers-can-paint, render resolution.
- **Add menu**: insert a photo/video, stream a computer's screen, add text, or add a solid
  rectangle, a solid ellipse or a linear gradient. The rectangle, ellipse, photo, video and gradient
  rows **prime the pen**: the Add icon lights, and the next pen-down on the canvas places the object and
  dragging sizes it, centred on the press with the pen on its edge (a rectangle is a square and an
  ellipse a circle, never turned; a picture or clip keeps its own shape). A gradient is the band from
  the press to the lift — its direction and length are the stroke's, and its width is the left rail's
  Width slider, a share of the canvas — and arrives with its panel up: two colours and an angle. Tap the
  primed row again, or pick another tool, to put it down. A rectangle, ellipse or gradient is an object of
  the fill tool's own kind; a gradient is an object in a vector layer, not a layer of its own. The text
  panel's font list shows every family set in itself.
- The document name is typed into where it stands in the middle of the top bar, and a layer's or
  folder's name in its row (its options menu's Rename puts the row into editing): Return or a touch
  anywhere else commits, and an empty name puts the old one back.
- **Pinch** to zoom, **two-finger rotate/drag** to rotate/pan the canvas.

## Troubleshooting

**Build errors** — make sure you're on Xcode 26+; the GPU fill engine's `Fill.metal` shader needs the
Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`), a one-time per-machine
install.

**Drawing not working** — the app says why in a banner under the top toolbar (no layers, hidden
layer, or a layer with no drawing surface) and offers the fix. If nothing happens at all and no
banner appears, "Apple Pencil only" is probably on (side rail) while you are using a simulator or a
finger — that gates fill as well as strokes, and is deliberately silent.

**UI tests failing on iPhone** — this app's layout assumes an iPad; run the test suite against an
iPad simulator destination.

### A project that opened with something unreadable

Vector content is decoded one element at a time, so a damaged file costs the marks it cannot read
rather than the whole drawing. The first time you then leave to the gallery, a banner says what was
lost — *"2 brush strokes on the Ink layer could not be read when this project opened"* — and offers
**Save Anyway** or **Cancel**. It is asked once per open and not again.

- **Save Anyway** rewrites the project without them. The next time you open it there is nothing left
  to ask about, which is why the answer is not remembered anywhere on disk.
- **Cancel** leaves the project file exactly as it was and writes your changes into the project's
  version history instead, as **Unsaved changes** in the gallery's Versions sheet.

**Backgrounding the app never asks.** An automatic save on a project you have not answered for takes
the Cancel path on its own: your work is written to the version history and the damaged original is
left alone, so nothing is lost and nothing is decided behind your back.

An element written by a *newer* build of the app is not counted as damage and never raises the
banner — nothing is wrong with the file, this build simply has no feature to draw it with. The
reasoning for all of it is in `Services/SaveDamageGate.swift`.

## Known limitations / open work

See [BUGS.md](BUGS.md) for the tracked list. Notable ones: **two-finger pan/pinch/rotate is reported
dead on device while the Fill tool is selected**, unexplained and unreproduced on the simulator;
Distort works on a raster floating piece, a text box and lassoed vector ink, but not yet on a floating
placed image or video — six numbers and a mirror bit have nowhere to keep a projective residue; and
Cut/Copy/Paste are still stubs with an "isn't available yet" notice.

## License

This project is provided as-is for educational and personal use.
